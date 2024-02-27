{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE IncoherentInstances #-}
{-# LANGUAGE PatternSynonyms #-}

-- |

module Fort.Utils
  ( module Fort.Utils
  , module Control.Monad
  , module Control.Monad.Reader
  , module Control.Monad.State
  , module Data.Generics.Uniplate.Data
  , module Data.Maybe
  , module Debug.Trace
  , module Fort.AST
  , module Fort.Errors
  , module Prelude
  , module Prettyprinter
  , module Data.List.NonEmpty
  , Data
  , Map
  , Set
  , Text
  , toList
  )

where

import Control.Monad
import Control.Monad.Reader
import Control.Monad.State
import Data.Data (Data)
import Data.Generics.Uniplate.Data
import Data.List.NonEmpty (NonEmpty(..), (<|))
import Data.Foldable (toList)
import Data.Map (Map)
import Data.Maybe
import Data.Set (Set)
import Data.Text (Text)
import Debug.Trace
import Fort.AST hiding (Char, Int, String)
import Fort.Errors
import Numeric (readBin)
import Prelude
import Prettyprinter
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as Text

type Sz = Integer

bitsizePointer :: Sz
bitsizePointer = 64 -- BAL: architecture dependent

instance (Pretty a, Pretty b) => Pretty (Either a b) where
  pretty x = case x of
    Left a -> "Left" <+> pretty a
    Right b -> "Right" <+> pretty b

lookup_ :: (Pretty k, Ord k) => k -> Map k a -> a
lookup_ k tbl = fromMaybe (unreachable "unexpected lookup failure" k) $ Map.lookup k tbl

nameOf :: (Positioned a, HasText a) => a -> Name
nameOf x = Name (positionOf x) (textOf x)

qnToLIdent :: QualLIdent -> LIdent
qnToLIdent x = mkTok (positionOf x) (textOf x)

instance Positioned Name where
  positionOf (Name pos _) = pos

noTCHint :: String
noTCHint = "is type checking disabled?"

mkQName :: (Tok a, HasText a, Positioned a) => Text -> a -> a
mkQName a b = mkTok (positionOf b) (mkQNameText a $ textOf b)

data Name = Name Position Text deriving (Data)

instance Show Name where
  show = Text.unpack . textOf

instance HasText Name where
  textOf (Name _ s) = s

instance Pretty Name where
  pretty = pretty . textOf

instance (Pretty k, Pretty a, Ord k) => Pretty (Map k a) where
  pretty m = vlist mempty [ pretty k <> ":" <+> pretty a | (k, a) <- sortByFst $ Map.toList m ]

braced :: [Doc ann] -> Doc ann
braced xs = "{" <+> hsep (punctuate comma xs) <+> "}"

vlist :: Doc ann -> [Doc ann] -> Doc ann
vlist _ [] = "{}"
vlist _ [x] = braces x
vlist a xs = braces $ nest 2 $ vsep (a : xs)

isSubmapByKeys :: Ord k => Map k a -> Map k a -> Bool
isSubmapByKeys = Map.isSubmapOfBy (\_ _ -> True)

isEqualByKeys :: Ord k => Map k a -> Map k a -> Bool
isEqualByKeys a b = isSubmapByKeys a b && isSubmapByKeys b a

intersectionWithM :: (Monad m, Ord k) => (a -> a -> m a) -> Map k a -> Map k a -> m (Map k a)
intersectionWithM f m n = mapM (uncurry f) $ Map.intersectionWith (,) m n

intersections :: Ord a => [Set a] -> Set a
intersections [] = mempty
intersections (x : xs) = foldr Set.intersection x xs

unionWithM :: (Monad m, Ord k, Pretty a) => (a -> a -> m a) -> Map k a -> Map k a -> m (Map k a)
unionWithM f m n = mapM g $ Map.unionWith h (fmap Right m) (fmap Right n)
  where
    g eab = case eab of
      Left a -> uncurry f a
      Right b -> pure b

    h :: Pretty a => Either (a, a) a -> Either (a, a) a -> Either (a, a) a
    h (Right c) (Right d) = Left (c, d)
    h a b = unreachable "unionWithM" [a, b]

instance Pretty a => Pretty (Set a) where
  pretty x = braced $ fmap pretty (Set.toList x)

instance Ord Name where
  compare a b = compare (textOf a) (textOf b)

instance Eq Name where
  a == b = textOf a == textOf b

class ValTok a b | a -> b where
  valOf :: a -> b

instance ValTok UInt Integer where
  valOf x = case x of
    Bin _ a -> case readBin $ removeUnderscores $ List.drop 2 $ Text.unpack a of
      [(n, "")] -> n
      b -> unreachable "valOf:Bin" b
    Dec _ a -> read $ removeUnderscores $ Text.unpack a
    Hex _ a -> read $ removeUnderscores $ Text.unpack a
    Oct _ a -> read $ removeUnderscores $ Text.unpack a

removeUnderscores :: String -> String
removeUnderscores = filter ((/=) '_')

instance ValTok AString Text where
  valOf x = Text.pack $ read $ Text.unpack $ textOf x

instance ValTok ADouble Double where
  valOf = read . removeUnderscores . Text.unpack . textOf

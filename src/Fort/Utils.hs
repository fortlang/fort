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
  , module Fort.Abs
  , module Fort.Errors
  , module Prelude
  , module Prettyprinter
  , Data
  , Map
  , Set
  , Text
  )

where

import Control.Monad
import Control.Monad.Reader
import Control.Monad.State
import Data.Data (Data)
import Data.Generics.Uniplate.Data
import Data.Map (Map)
import Data.Maybe
import Data.Set (Set)
import Data.Text (Text)
import Debug.Trace
import Fort.Abs (pattern ADouble, pattern TupleElemPat, pattern Binding, pattern Module, pattern LIdent, pattern ExpDecl, pattern InfixOp, pattern UIdent, pattern PrefixOp, pattern TailRecDecl, pattern Stmt, pattern LayoutElemStmt, pattern TupleElemExp, pattern LayoutElemExpDecl, pattern InfixInfo, pattern FieldDecl, pattern LayoutElemIfBranch, pattern IfBranch, pattern LayoutElemFieldDecl, pattern UInt, pattern LayoutElemCaseAlt, pattern CaseAlt, pattern LayoutElemExp, pattern Scalar, pattern TupleElemType, pattern LayoutElemTField, pattern TField, pattern LayoutElemTSum, pattern TSum, pattern LayoutElemTailRecDecl, pattern TailRecDecls, pattern AString)
import Fort.Abs hiding (Exp, ADouble, InfixOp, PrefixOp, LIdent, UIdent, Module, Binding, Decl, ExpDecl, Pat, TupleElemPat, TailRecDecl, Fixity, Stmt, LayoutElemStmt, TupleElemExp, LayoutElemExpDecl, AltPat, QualLIdent, InfixInfo, FieldDecl, LayoutElemIfBranch, IfBranch, LayoutElemFieldDecl, UInt, LayoutElemCaseAlt, CaseAlt, LayoutElemExp, Type, Scalar, TupleElemType, Size, LayoutElemTField, TField, LayoutElemTSum, TSum, LayoutElemTailRecDecl, TailRecDecls, TailRecDecl, AString)
import Fort.Errors
import Numeric (readBin)
import Prelude
import Prettyprinter
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Fort.Print as Print

type Size = Size' Position
type TailRecDecls = TailRecDecls' Position
type LayoutElemTailRecDecl = LayoutElemTailRecDecl' Position

type Type = Type' Position
type Scalar = Scalar' Position
type Exp = Exp' Position
type UInt = UInt' Position
type LayoutElemIfBranch = LayoutElemIfBranch' Position
type LayoutElemTSum = LayoutElemTSum' Position
type TSum = TSum' Position
type LayoutElemTField = LayoutElemTField' Position
type TField = TField' Position
type LayoutElemExp = LayoutElemExp' Position
type LayoutElemCaseAlt = LayoutElemCaseAlt' Position
type CaseAlt = CaseAlt' Position
type IfBranch = IfBranch' Position
type FieldDecl = FieldDecl' Position
type QualLIdent = QualLIdent' Position
type InfixInfo = InfixInfo' Position
type LayoutElemStmt = LayoutElemStmt' Position
type LayoutElemExpDecl = LayoutElemExpDecl' Position
type LayoutElemFieldDecl = LayoutElemFieldDecl' Position
type TupleElemExp = TupleElemExp' Position
type TupleElemType = TupleElemType' Position
type Stmt = Stmt' Position
type ADouble = ADouble' Position
type AString = AString' Position
type InfixOp = InfixOp' Position
type PrefixOp = PrefixOp' Position
type LIdent = LIdent' Position
type UIdent = UIdent' Position
type Binding = Binding' Position
type Module = Module' Position
type Decl = Decl' Position
type ExpDecl = ExpDecl' Position
type TailRecDecl = TailRecDecl' Position
type Pat = Pat' Position
type AltPat = AltPat' Position
type Fixity = Fixity' Position
type TupleElemPat = TupleElemPat' Position

type Sz = Integer

bitsizePointer :: Sz
bitsizePointer = 64 -- BAL: architecture dependent

instance (Pretty a, Pretty b) => Pretty (Either a b) where
  pretty x = case x of
    Left a -> "Left" <+> pretty a
    Right b -> "Right" <+> pretty b

lookup_ :: (Pretty k, Ord k) => k -> Map k a -> a
lookup_ k tbl = fromMaybe (unreachable "unexpected lookup failure" k) $ Map.lookup k tbl

instance Positioned Scalar where
  positionOf x = case x of
    AFalse pos -> pos
    ATrue pos -> pos
    Char pos _ -> pos
    Double pos _ -> pos
    Int pos _ -> pos
    String pos _ -> pos
    UInt pos _ -> pos

instance Positioned ExpDecl where
  positionOf x = case x of
    Binding pos _ _ -> pos
    TailRec pos _ -> pos

instance Positioned Type where
  positionOf x = case x of
    TOpaque pos _ -> pos
    TLam pos _ _ -> pos
    TFun pos _ _ -> pos
    TApp pos _ _ -> pos
    TQualName pos _ _ -> pos
    TTuple pos _ _ -> pos

    TRecord pos _ -> pos
    TName pos _ -> pos
    TParens pos _ -> pos
    TSize pos _ -> pos
    TSizes pos _ -> pos
    TSum pos _ -> pos
    TVar pos _ -> pos

    TArray pos -> pos
    TBool pos -> pos
    TChar pos -> pos
    TFloat pos -> pos
    TInt pos -> pos
    TPointer pos -> pos
    TString pos -> pos
    TUInt pos -> pos
    TUnit pos -> pos

instance Positioned Name where
  positionOf (Name pos _) = pos

instance Positioned Stmt where
  positionOf x = case x of
    Let pos _ _ -> pos
    Stmt pos _ -> pos
    TailRecLet pos _ -> pos
    XLet pos _ _ -> pos

instance Positioned AltPat where
  positionOf x = case x of
    PCon pos _ _ -> pos
    PDefault pos _ -> pos
    PEnum pos _ -> pos
    PScalar pos _ -> pos

instance Positioned Exp where
  positionOf x = case x of
    Lam pos _ _ -> pos
    Where pos _ _ -> pos
    Typed pos _ _ -> pos
    With pos _ _ -> pos
    InfixOper pos _ _ _ -> pos
    App pos _ _ -> pos
    PrefixOper pos _ _ -> pos
    Array pos _ -> pos
    Case pos _ _ -> pos
    Con pos _ -> pos
    Do pos _ -> pos
    EType pos _ -> pos
    If pos _ -> pos
    Parens pos _ -> pos
    Qualified pos _ _ -> pos
    Record pos _ -> pos
    Scalar pos _ -> pos
    Select pos _ _ -> pos
    Tuple pos _ _ -> pos
    Unit pos -> pos
    Var pos _ -> pos
    XArray pos _ -> pos
    XDot pos _ _ -> pos
    XRecord pos _ -> pos
    Extern pos _ _ -> pos

instance Positioned Pat where
  positionOf x = case x of
    PParens pos _ -> pos
    PTuple pos _ _ -> pos
    PTyped pos _ _ -> pos
    PUnit pos -> pos
    PVar pos _ -> pos

instance Positioned Size where
  positionOf x = case x of
    SzNat pos _ -> pos
    SzVar pos _ -> pos

instance Positioned PrefixOp where
  positionOf (PrefixOp pos _) = pos

instance Positioned InfixOp where
  positionOf (InfixOp pos _) = pos

instance Positioned LIdent where
  positionOf (LIdent pos _) = pos

instance Positioned UIdent where
  positionOf (UIdent pos _) = pos

class Tok a where
  mkTok :: Position -> Text -> a

class IsNewtype a b | a -> b where
  newtypeOf :: a -> b

instance IsNewtype LayoutElemTailRecDecl TailRecDecl where
  newtypeOf (LayoutElemTailRecDecl _ a) = a

instance IsNewtype LayoutElemTSum TSum where
  newtypeOf (LayoutElemTSum _ a) = a

instance IsNewtype LayoutElemTField TField where
  newtypeOf (LayoutElemTField _ a) = a

instance IsNewtype LayoutElemCaseAlt CaseAlt where
  newtypeOf (LayoutElemCaseAlt _ a) = a

instance IsNewtype LayoutElemExpDecl ExpDecl where
  newtypeOf (LayoutElemExpDecl _ a) = a

instance IsNewtype LayoutElemExp Exp where
  newtypeOf (LayoutElemExp _ a) = a

instance IsNewtype LayoutElemFieldDecl FieldDecl where
  newtypeOf (LayoutElemFieldDecl _ a) = a

instance IsNewtype TupleElemPat Pat where
  newtypeOf (TupleElemPat _ p) = p

instance Positioned LayoutElemStmt where
  positionOf (LayoutElemStmt pos _) = pos

instance IsNewtype LayoutElemStmt Stmt where
  newtypeOf (LayoutElemStmt _ a) = a

instance IsNewtype LayoutElemIfBranch IfBranch where
  newtypeOf (LayoutElemIfBranch _ a) = a

instance IsNewtype TupleElemType Type where
  newtypeOf (TupleElemType _ a) = a

instance IsNewtype TupleElemExp Exp where
  newtypeOf (TupleElemExp _ a) = a

nameOf :: (Positioned a, HasText a) => a -> Name
nameOf x = Name (positionOf x) (textOf x)

qnToLIdent :: QualLIdent -> LIdent
qnToLIdent x = mkTok (positionOf x) (textOf x)

instance Positioned QualLIdent where
  positionOf x = case x of
    Qual pos _ _ -> pos
    UnQual pos _ -> pos

noTCHint :: String
noTCHint = "is type checking disabled?"

mkQName :: (Tok a, HasText a, Positioned a) => Text -> a -> a
mkQName a b = mkTok (positionOf b) (mkQNameText a $ textOf b)

mkQNameText :: Text -> Text -> Text
mkQNameText a b = a <> "." <> b

instance HasText QualLIdent where
  textOf x = case x of
    Qual _ a b -> mkQNameText (textOf a) (textOf b)
    UnQual _ a -> textOf a

instance HasText LIdent where
  textOf (LIdent _ (LIdentTok s)) = s

instance Tok LIdent where
  mkTok pos = LIdent pos . LIdentTok

instance HasText InfixOp where
  textOf (InfixOp _ (InfixOpTok s)) = s

instance Tok InfixOp where
  mkTok pos = InfixOp pos . InfixOpTok

instance HasText PrefixOp where
  textOf (PrefixOp _ (PrefixOpTok s)) = s

instance Tok PrefixOp where
  mkTok pos = PrefixOp pos . PrefixOpTok

instance HasText AString where
  textOf (AString _ (AStringTok s)) = s

instance HasText ADouble where
  textOf (ADouble _ (ADoubleTok s)) = s

instance HasText UIdent where
  textOf (UIdent _ (UIdentTok s)) = s

instance Tok UIdent where
  mkTok pos = UIdent pos . UIdentTok

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

instance Ord UIdent where
  compare a b = compare (textOf a) (textOf b)

instance Ord LIdent where
  compare a b = compare (textOf a) (textOf b)

instance Ord PrefixOp where
  compare a b = compare (textOf a) (textOf b)

instance Eq UIdent where
  a == b = textOf a == textOf b

instance Eq LIdent where
  a == b = textOf a == textOf b

instance Eq PrefixOp where
  a == b = textOf a == textOf b

instance Ord InfixOp where
  compare a b = compare (textOf a) (textOf b)

instance Eq InfixOp where
  a == b = textOf a == textOf b

instance Ord Name where
  compare a b = compare (textOf a) (textOf b)

instance Eq Name where
  a == b = textOf a == textOf b

instance Positioned AString where
  positionOf (AString pos _) = pos

instance Positioned Decl where
  positionOf x = case x of
    ExpDecl pos _ -> pos
    InfixDecl pos _ _ -> pos
    QualDecl pos _ _ -> pos
    PrefixDecl pos _ _ -> pos
    TypeDecl pos _ _ -> pos
    ExportDecl pos _ _ _ -> pos
  
instance (Data a, Print.Print a) => Pretty a where -- UndecidableInstance, IncoherentInstance
  pretty = pretty . Print.printTree . transformBi infixOpParens

infixOpParens :: Exp -> Exp
infixOpParens x@InfixOper{} = Parens (positionOf x) x
infixOpParens x = x

class ValTok a b | a -> b where
  valOf :: a -> b

instance ValTok CharTok Char where
  valOf (CharTok t) = read $ Text.unpack t

instance ValTok IntTok Integer where
  valOf (IntTok t) = read $ Text.unpack t

instance ValTok UInt Integer where
  valOf x = case x of
    Bin _ a -> case readBin $ List.drop 2 $ Text.unpack $ textOf a of
      [(n, "")] -> n
      b -> unreachable "valOf:Bin" b
    Dec _ a -> read $ Text.unpack $ textOf a
    Hex _ a -> read $ Text.unpack $ textOf a
    Oct _ a -> read $ Text.unpack $ textOf a

instance HasText DecTok where
  textOf (DecTok t) = t

instance HasText HexTok where
  textOf (HexTok t) = t

instance HasText OctTok where
  textOf (OctTok t) = t

instance HasText BinTok where
  textOf (BinTok t) = t

instance ValTok AString Text where
  valOf x = Text.pack $ read $ Text.unpack $ textOf x

instance ValTok ADouble Double where
  valOf = read . Text.unpack . textOf

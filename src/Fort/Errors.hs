module Fort.Errors
( HasText
, Location
, Position
, Positioned
, UserException(..)
, Posn(..)
, noPos
, err100
, err101
, err110
, err11n
, err111
, err10n
, err1n0
, err1n1
, errnn1
, errn00
, errn01
, noPosition
, outputErrorReport
, outputSystemError
, pair
, positionOf
, sortByFst
, textOf
, unreachable
, unreachable100
, unreachable110
, unreachable001
, unreachable00n
, unreachablen00
, unreachable101
, unreachablen01
, getLineAt
)

where

import Prelude
import Control.Exception
import Control.Monad
import Control.Monad.IO.Class
import Data.Maybe
import Data.Text (Text)
import Prettyprinter
import System.IO
import qualified Data.List as List
import qualified Error.Diagnose as Diagnose

type Position = (Maybe FilePath, Maybe Location)
type Location = (Int, Int)

noPosition :: Position
noPosition = (Nothing, Nothing)

noPos :: a -> Posn a
noPos = Posn noPosition

sortByFst :: Ord a => [(a, b)] -> [(a, b)]
sortByFst = List.sortBy $ \a b -> compare (fst a) (fst b)

class HasText a where
  textOf :: a -> Text

unreachable :: Pretty a => String -> a -> b
unreachable msg a = error ("unreachable: " <> msg <> ": " <> show (pretty a))

pair :: a -> b -> (a, b)
pair a b = (a, b)

data UserException = UserException
  { header :: Doc ()
  , thiss :: [(Doc (), Position)] -- must be non-empty
  , wheres :: [(Doc (), Position)]
  , hints :: [Doc ()]
  } deriving Show

instance Exception UserException where

class Positioned a where
  positionOf :: a -> Position

data Posn a = Posn Position a

instance Positioned (Posn a) where
  positionOf (Posn pos _) = pos

instance Pretty a => Pretty (Posn a) where
  pretty (Posn _ a) = pretty a

err111 :: (MonadIO m, Pretty b, Positioned b, Pretty c, Positioned c, Pretty d) => Doc () -> b -> c -> d -> m a
err111 msg b c d = throwUE msg [ (pretty b, positionOf b) ] [(pretty c, positionOf c)] [pretty d]

unreachablen01 :: (MonadIO m, Pretty b, Positioned b, Pretty d) => Doc () -> [b] -> d -> m a
unreachablen01 msg bs d = throwUE msg [ (pretty b, positionOf b) | b <- bs ] [] ["unreachable", pretty d]

unreachable001 :: (MonadIO m, Pretty d) => Doc () -> d -> m a
unreachable001 msg d = throwUE msg [("unreachable", noPosition)] [] [pretty d]

unreachable00n :: (MonadIO m, Pretty d) => Doc () -> [d] -> m a
unreachable00n msg ds = throwUE msg [("unreachable", noPosition)] [] $ fmap pretty ds

unreachable101 :: (MonadIO m, Pretty b, Positioned b, Pretty d) => Doc () -> b -> d -> m a
unreachable101 msg b d = throwUE msg [ (pretty b, positionOf b) ] [] ["unreachable", pretty d]

unreachable100 :: (MonadIO m, Pretty b, Positioned b) => Doc () -> b -> m a
unreachable100 msg b = throwUE msg [ (pretty b, positionOf b) ] [] ["unreachable"]

unreachablen00 :: (MonadIO m, Pretty b, Positioned b) => Doc () -> [b] -> m a
unreachablen00 msg bs = throwUE msg [ (pretty b, positionOf b) | b <- bs ] [] ["unreachable"]

unreachable110 :: (MonadIO m, Pretty b, Positioned b, Pretty c, Positioned c) => Doc () -> b -> c -> m a
unreachable110 msg b c = throwUE msg [ (pretty b, positionOf b) ] [(pretty c, positionOf c)] ["unreachable"]

err110 :: (MonadIO m, Pretty b, Positioned b, Pretty c, Positioned c) => Doc () -> b -> c -> m a
err110 msg b c = throwUE msg [ (pretty b, positionOf b) ] [(pretty c, positionOf c)] []

err101 :: (MonadIO m, Pretty b, Positioned b, Pretty d) => Doc () -> b -> d -> m a
err101 msg b d = throwUE msg [ (pretty b, positionOf b) ] [] [pretty d]

errn01 :: (MonadIO m, Pretty b, Positioned b, Pretty d) => Doc () -> [b] -> d -> m a
errn01 msg bs d = throwUE msg [ (pretty b, positionOf b) | b <- bs ] [] [pretty d]

errnn1 :: (MonadIO m, Pretty b, Positioned b, Pretty c, Positioned c, Pretty d) => Doc () -> [b] -> [c] -> d -> m a
errnn1 msg bs cs d = throwUE msg [ (pretty b, positionOf b) | b <- bs ] [ (pretty c, positionOf c) | c <- cs ] [pretty d]

err10n :: (MonadIO m, Pretty b, Positioned b, Pretty d) => Doc () -> b -> [d] -> m a
err10n msg b ds = throwUE msg [ (pretty b, positionOf b) ] [] (fmap pretty ds)

err11n :: (MonadIO m, Pretty b, Positioned b, Pretty c, Positioned c, Pretty d) => Doc () -> b -> c -> [d] -> m a
err11n msg b c ds = throwUE msg [ (pretty b, positionOf b) ] [ (pretty c, positionOf c) ] (fmap pretty ds)

err100 :: (MonadIO m, Pretty b, Positioned b) => Doc () -> b -> m a
err100 msg b = throwUE msg [ (pretty b, positionOf b) ] [] []

err1n0 :: (MonadIO m, Pretty b, Positioned b, Pretty c, Positioned c) => Doc () -> b -> [c] -> m a
err1n0 msg b cs = throwUE msg [ (pretty b, positionOf b) ] [ (pretty c, positionOf c) | c <- cs ] []

err1n1 :: (MonadIO m, Pretty b, Positioned b, Pretty c, Positioned c, Pretty d) => Doc () -> b -> [c] -> d -> m a
err1n1 msg b cs d = throwUE msg [ (pretty b, positionOf b) ] [ (pretty c, positionOf c) | c <- cs ] [pretty d]

errn00 :: (MonadIO m, Pretty b, Positioned b) => Doc () -> [b] -> m a
errn00 msg bs = throwUE msg [ (pretty b, positionOf b) | b <- bs ] [] []

throwUE :: MonadIO m => Doc () -> [(Doc (), Position)] -> [(Doc (), Position)] -> [Doc ()] -> m a
throwUE hdr bs cs ds = liftIO $ throwIO (UserException hdr bs cs ds)

outputSystemError :: SomeException -> IO Int
outputSystemError x = do
  hPutStrLn stderr "An error occured:"
  hPrint stderr x
  pure 1

outputErrorReport :: Bool -> UserException -> IO Int
outputErrorReport _ (UserException _ [] _ _) = error "unexpected user exception with empty messages"
outputErrorReport basicOutput (UserException hdr bs cs ds) = do
  let fns = List.nub [ fn | (_, (Just fn, _)) <- bs ++ cs ]
  let addFile d fn = Diagnose.addFile d fn <$> readFile fn
  dfile :: Diagnose.Diagnostic String <- foldM addFile Diagnose.def fns

  drpt <- foldM addReport dfile [ (hdr, b, cs, ds) | b <- bs ]

  if basicOutput
    then Diagnose.printDiagnostic stderr False False 2 Diagnose.defaultStyle drpt
    else Diagnose.printDiagnostic stderr True True 2 Diagnose.defaultStyle drpt

  pure 1

addReport :: Diagnose.Diagnostic String -> (Doc (), (Doc (), Position), [(Doc (), Position)], [Doc ()]) -> IO (Diagnose.Diagnostic String)
addReport diag (hdr, (msg, pos), whrs, hnts) = do
  dpos <- toDiagnosePosition pos
  dwhrs <- sequence [ (,Diagnose.Where $ show w) <$> toDiagnosePosition p | (w, p) <- whrs ]
  let e = Diagnose.err Nothing (show hdr) ((dpos, Diagnose.This $ show msg) : dwhrs) (fmap show hnts)
  pure $ Diagnose.addReport diag e

toDiagnosePosition :: Position -> IO Diagnose.Position
toDiagnosePosition (mfn, mbegin) = do
  end <- case (mfn, mbegin) of
    (Just{}, Just{}) -> getPositionEnd fn begin
    _ -> pure begin
  pure $ Diagnose.Position begin end fn

  where
    fn = fromMaybe "<stdin>" mfn
    begin = fromMaybe (0, 0) mbegin

getPositionEnd :: FilePath -> Location -> IO Location
getPositionEnd fn (j, i) = do
  ln <- getLineAt fn j
  case words $ drop (i - 1) ln of
    [] -> pure (j, i + length ln)
    w : _ -> pure (j, i + length w)

getLineAt :: FilePath -> Int -> IO String
getLineAt fn j = do
  s <- readFile fn
  case drop (j - 1) $ lines s of
    [] -> error "dropped too many lines"
    ln : _ -> pure ln

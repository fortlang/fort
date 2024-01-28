module Fort.Parse (parseModule) where

import Control.Exception
import Control.Monad
import Data.Text (Text)
import Fort.Errors
import Prelude
import Prettyprinter
import qualified Data.Text.IO as Text

type BNFCPosition = Maybe Location

parseModule :: Show a => (Functor ast) => Bool -> (Text -> [a]) -> (Bool -> [a] -> [a]) -> ([a] -> Either String (ast BNFCPosition)) -> FilePath -> IO (ast Position)
parseModule showLexemes myLexer resolveLayout pModule fn = do
  s <- Text.readFile fn
  when showLexemes $ mapM_ print $ myLexer s
  case pModule $ resolveLayout True $ myLexer s of
    Left msg -> throwIO $ parserErrToErr fn msg
    Right a -> pure (fmap (pair (Just fn)) a)

parserErrToErr :: FilePath -> String -> UserException
parserErrToErr fn msg = case dropWhile ("line" /=) $ words msg of
  _:ln:rest -> case dropWhile ("column" /=) rest of
    _:col:rest' -> dflt{ thiss = [ (pretty $ unwords rest', (Just fn, Just (read $ init ln, read col))) ] }
    _ -> dflt
  _ -> dflt
  where
    dflt = UserException
      { header = "syntax error"
      , thiss = [(pretty msg, (Just fn, Just (0, 1)))]
      , wheres = mempty
      , hints = mempty
      }

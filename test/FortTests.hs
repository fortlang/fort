-- |

module Main where

import Control.Exception
import Control.Monad
import Data.List
import Fort
import Fort.Errors
import Options.Applicative
import Prelude
import Prettyprinter
import System.Directory
import System.FilePath

main :: IO ()
main = do
  case execParserPure defaultPrefs fortInfo ["--help"] of
    Failure f -> print f
    a -> unreachable "FortTests: help message" a

  getFiles "eval" >>= mapM_ runFn
  getFiles "multieval" >>= mapM_ runFn
  getFiles "tcerr" >>= mapM_ runFnErr
  getFiles "multierr" >>= mapM_ runFnErr
  getFiles "tcerr" >>= mapM_ runFnNoTCErr

expectNoError fn f = do
  r <- f
  when (r /= 0) $ error $ "test failed:" ++ fn

expectError fn f = do
  r <- f
  when (r /= 1) $ error $ "test failed:" ++ fn

runFn fn = do
  expectNoError fn $ fort $ toOpts ["--run", "--show-fil", "--no-ansi", "--show-llvm", "--show-parse", "-qeds", fn ]

runFnNoTCErr fn = fort $ toOpts ["--no-tc", "--show-fil", "--no-ansi", "--show-llvm", "--no-build", fn ]

runFnErr fn = expectError fn $ fort $ toOpts ["--run", "--no-ansi", "--checks", fn ]

toOpts xs = case execParserPure defaultPrefs fortInfo xs of
  Success opts -> opts
  a -> unreachable "FortTests: toOpts" a

getFiles dir0 = do
  let dir = "test" </> dir0
  bs <- getDirectoryContents dir
  pure $ fmap (dir </>) $ sort $ filter (isExtensionOf "fort") bs

instance Pretty (ParserResult Options) where
  pretty = pretty . show



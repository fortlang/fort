{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Fort(fort, Options(..), options, fortInfo) where

import Control.Exception
import Control.Monad
import Data.Generics.Uniplate.Data
import Data.Version (showVersion)
import Fort.Dependencies
import Fort.FIL
import Fort.LLVM
import Fort.Layout
import Fort.Par
import Fort.Parse
import Fort.Precedence
import Fort.Qualify
import Fort.Simplify
import Fort.TypeChecker
import Fort.Utils hiding (header)
import Options.Applicative
import Paths_fort (version)
import System.FilePath
import System.Process
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Text as Text

fortInfo :: ParserInfo Options
fortInfo = info (options <**> simpleVersioner (showVersion version) <**> helper)
    (fullDesc <> progDesc "compiler for the fort programming language" <> header "fort")

data Options = Options
  { showLexer :: Bool
  , showParser :: Bool
  , showQualify :: Bool
  , showPrecedence :: Bool
  , showDependencies :: Bool
  , showSimplify :: Bool
  , showFIL :: Bool
  , showLLVM :: Bool
  , generateLLVM :: Bool
  , noTypeChecker :: Bool
  , noBuild :: Bool
  , doRun :: Bool
  , noANSI :: Bool
  , runTimeChecks :: Bool
  , mainIs :: Text
  , files :: [FilePath]
  } deriving Show

options :: Parser Options
options = Options
  <$> switch (long "show-lex" <> short 'x' <> help "show output of lexer")
  <*> switch (long "show-parse" <> short 'p' <> help "show output of parser")
  <*> switch (long "show-qualify" <> short 'q' <> help "show output of name qualification")
  <*> switch (long "show-prec" <> short 'e' <> help "show output of precedence reordering")
  <*> switch (long "show-deps" <> short 'd' <> help "show output of dependency solver")
  <*> switch (long "show-simple" <> short 's' <> help "show output of simplifier")
  <*> switch (long "show-fil" <> short 'f' <> help "show output of fort intermediate language")
  <*> switch (long "show-llvm" <> short 'l' <> help "show output of llvm code generation")
  <*> switch (long "gen-llvm" <> short 'm' <> help "generate llvm code (.ll) file")
  <*> switch (long "no-tc" <> short 'T' <> help "don't run the type checker")
  <*> switch (long "no-build" <> short 'B' <> help "don't compile the resulting code")
  <*> switch (long "run" <> short 'r' <> help "run the resulting executable (.exe) file after building")
  <*> switch (long "no-ansi" <> short 'A' <> help "don't output colorized (ANSI) output")
  <*> switch (long "checks" <> short 'c' <> help "turn on extra run-time checks")
  <*> strOption (long "main-is" <> metavar "FUNCTION" <> showDefault <> value "main" <> short 'm' <> help "name of function to generate code for")
  <*> some (argument str (metavar "FILES..."))

fort :: Options -> IO Int
fort opts = do
  let fns = fmap normalise $ files opts
  let mainNm = mainIs opts
  let doBuild = not (noBuild opts) || doRun opts
  let doGen = generateLLVM opts || doBuild
  let doLLVM = showLLVM opts || doGen
  let doFIL = showFIL opts || doLLVM
  let doSimplify = showSimplify opts || doFIL
  let doDeps = showDependencies opts || doSimplify
  let doPrec = showPrecedence opts || doDeps
  let doQualify = showQualify opts || doPrec

  putStrLn $ "fort processing files: " ++ List.intercalate ", " fns

  handle outputSystemError $
   handle (outputErrorReport $ noANSI opts) $ do
    (quals, ms) <- parseModules opts fns
    when (showParser opts) $ do mapM_ (pp "(parsed)") ms

    when doQualify $ do
      msqual <- qualifyModules quals ms
      when (showQualify opts) $ mapM_ (pp "(qualified)") msqual
      when doPrec $ do
        msops <- fixInfixOpsModules msqual
        when (showPrecedence opts) $ mapM_ (pp "(precedence)") msops
        when doDeps $ do
          (bldds, msdeps) <- dependenciesModules mainNm fns msops
          when (showDependencies opts) $ mapM_ (pp "(deps)") msdeps
          when doSimplify $ do
            unless (noTypeChecker opts) $ typeCheckModules msdeps
            bldCmd <- toCallCommandArgs <$> simplifyBuildDecls (runTimeChecks opts) bldds
            doCallCommand "clang" $ ["-opaque-pointers", "-dynamiclib", "-o", "fort-ffi.dylib"] ++ bldCmd
            msstmts <- simplifyModules (runTimeChecks opts) msdeps
            
            when (showSimplify opts) $ mapM_ (pp "(simplify)") msstmts
            when doFIL $ do
              msfil <- filModules msstmts
              when (showFIL opts) $ mapM_ (pp "(fil)") msfil
              when doLLVM $ do
                msllvm <- llvmModules msfil
                when (showLLVM opts) $ mapM_ (ppFnDoc "(llvm)") $ fmap (fmap snd) msllvm
                when doGen $ do
                  mapM_ (writeFnDoc llvmFn) $ fmap (fmap snd) msllvm
                  when doBuild $ do
                    unless (noTypeChecker opts) $ typeCheckDecls bldds
                    mapM_ (buildFn bldCmd) $ fmap (fmap fst) msllvm
                    when (doRun opts) $ mapM_ runExeFn $ fmap (fmap fst) msllvm
    pure 0

parseModules :: Options -> [FilePath] -> IO ([(UIdent, FilePath)], [(FilePath, Module)])
parseModules opts = go mempty mempty
  where
    go quals tbl [] =
      pure (quals, Map.toList tbl)
    go quals tbl (fn : fns) =
      case Map.lookup fn tbl of
        Nothing -> do
          putStr "parsing "
          putStrLn fn
          absm <- parseModule (showLexer opts) myLexer resolveLayout pModule fn
          m <- toModule absm
          let qs = [ (q, Text.unpack s) | QualDecl _ q s <- universeBi m ]
          go (qs ++ quals) (Map.insert fn m tbl) (fmap snd qs ++ fns)
        Just _ -> go quals tbl fns
        
pp :: Pretty a => String -> (FilePath, a) -> IO ()
pp msg (fn, m) = ppFnDoc msg (fn, pretty m)

ppFnDoc :: String -> (FilePath, Doc ann) -> IO ()
ppFnDoc msg (fn, d) = do
  putStr fn
  putStr ":"
  putStrLn msg
  print d
  putStrLn ""

llvmFn :: FilePath -> FilePath
llvmFn fn = fn <> ".ll"

exeFn :: FilePath -> FilePath
exeFn fn = llvmFn fn <> ".exe"

objFn :: FilePath -> FilePath
objFn fn = llvmFn fn <> ".o"

runExeFn :: (FilePath, BuildType) -> IO ()
runExeFn (fn, bt) = do
  putStrLn $ exeFn fn ++ ": (run)"
  case bt of
    Exe -> doCallCommand (exeFn fn) []
    _ -> putStrLn "no .exe (no main found)"

doCallCommand :: FilePath -> [String] -> IO ()
doCallCommand nm xs = do
  let cmd = unwords (nm : xs)
  putStrLn cmd
  callCommand cmd

toCallCommandArgs :: [Text] -> [String]
toCallCommandArgs t = fmap normalise (concat (fmap (words . Text.unpack) t))

buildFn :: [String] -> (FilePath, BuildType) -> IO ()
buildFn bldAppend (fn, bt) = case bt of
  Exe -> do
    putStrLn $ exeFn fn ++ ": (exe)"
    doCallCommand "clang" $ ["-opaque-pointers", "-O3", "-mavx2", "-flto", "-o", exeFn fn, llvmFn fn] ++ bldAppend
  Obj -> do
    putStrLn $ llvmFn fn ++ ": (obj)"
    doCallCommand "clang" ["-opaque-pointers", "-O3", "-mavx2", "-c", "-o", objFn fn, llvmFn fn]
  NoCode -> do
    putStrLn $ fn ++ ": (no code)"
    putStrLn "no .exe/.o (no main or exported functions found)"

writeFnDoc :: (FilePath -> FilePath) -> (FilePath, Doc ann) -> IO ()
writeFnDoc f (fn, d) = do
  writeFile (f fn) $ show d
  putStrLn ("wrote " <> f fn)


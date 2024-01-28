module Main (main) where

import Fort
import Options.Applicative
import Prelude

main :: IO Int
main = execParser fortInfo >>= fort


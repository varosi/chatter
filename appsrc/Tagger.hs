{-# LANGUAGE OverloadedStrings #-}
module Tagger where

import qualified Data.ByteString as BS
import Data.Serialize (decode)
import qualified Data.Text as T
import qualified Data.Text.IO as T

import System.Environment (getArgs)

import NLP.POS (tagStr)

main :: IO ()
main = do
  args <- getArgs
  let modelFile = args!!0
      sentence  = args!!1
  model <- BS.readFile modelFile
  case decode model of
    Left err -> putStrLn ("Could not load model: "++err)
    Right tagger -> T.putStrLn $ tagStr tagger (T.pack sentence)

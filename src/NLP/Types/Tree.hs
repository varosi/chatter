{-# LANGUAGE OverloadedStrings #-}
module NLP.Types.Tree where

import Prelude hiding (print)
import Control.Applicative ((<$>), (<*>))
import Data.String (IsString(..))
import Data.Text (Text)
import qualified Data.Text as T
import Data.List (intercalate)

import Test.QuickCheck (Arbitrary(..), listOf, elements, NonEmptyList(..))
import Test.QuickCheck.Instances ()

import NLP.Types.Tags
import NLP.Types.General
import qualified NLP.Corpora.Brown as B

-- | A sentence of tokens without tags.  Generated by the tokenizer.
-- (tokenizer :: Text -> Sentence)
data Sentence = Sent [Token]
  deriving (Read, Show, Eq)

instance Arbitrary Sentence where
  arbitrary = Sent <$> arbitrary

tokens :: Sentence -> [Token]
tokens (Sent ts) = ts

applyTags :: Tag t => Sentence -> [t] -> TaggedSentence t
applyTags (Sent ts) tags = TaggedSent $ zipWith POS tags ts

-- | A chunked sentence has POS tags and chunk tags. Generated by a
-- chunker.
--
-- (chunker :: (Chunk chunk, Tag tag) => TaggedSentence tag -> ChunkedSentence chunk tag)
data ChunkedSentence chunk tag = ChunkedSent [ChunkOr chunk tag]
  deriving (Read, Show, Eq)

instance (ChunkTag c, Arbitrary c, Arbitrary t, Tag t) => Arbitrary (ChunkedSentence c t) where
  arbitrary = ChunkedSent <$> arbitrary

-- | A tagged sentence has POS Tags.  Generated by a part-of-speech
-- tagger. (tagger :: Tag tag => Sentence -> TaggedSentence tag)
data TaggedSentence tag = TaggedSent [POS tag]
  deriving (Read, Show, Eq)

instance (Arbitrary t, Tag t) => Arbitrary (TaggedSentence t) where
  arbitrary = TaggedSent <$> arbitrary

-- | Generate a Text representation of a TaggedSentence in the common
-- tagged format, eg:
--
-- > "the/at dog/nn jumped/vbd ./."
--
printTS :: Tag t => TaggedSentence t -> Text
printTS (TaggedSent ts) = T.intercalate " " $ map printPOS ts

-- | Remove the tags from a tagged sentence
stripTags :: Tag t => TaggedSentence t -> Sentence
stripTags ts = fst $ unzipTags ts

-- | Extract the tags from a tagged sentence, returning a parallel
-- list of tags along with the underlying Sentence.
unzipTags :: Tag t => TaggedSentence t -> (Sentence, [t])
unzipTags (TaggedSent ts) =
  let (tags, toks) = unzip $ map topair ts
      topair (POS tag tok) = (tag, tok)
  in (Sent toks, tags)

-- | Combine the results of POS taggers, using the second param to
-- fill in 'tagUNK' entries, where possible.
combine :: Tag t => [TaggedSentence t] -> [TaggedSentence t] -> [TaggedSentence t]
combine xs ys = zipWith combineSentences xs ys

combineSentences :: Tag t => TaggedSentence t -> TaggedSentence t -> TaggedSentence t
combineSentences (TaggedSent xs) (TaggedSent ys) = TaggedSent $ zipWith pickTag xs ys

-- | Returns the first param, unless it is tagged 'tagUNK'.
-- Throws an error if the text does not match.
pickTag :: Tag t => POS t -> POS t -> POS t
pickTag a@(POS t1 txt1) b@(POS t2 txt2)
  | txt1 /= txt2 = error ("Text does not match: "++ show a ++ " " ++ show b)
  | t1 /= tagUNK = POS t1 txt1
  | otherwise    = POS t2 txt1

-- | This type seem redundant, it just exists to support the
-- differences in TaggedSentence and ChunkedSentence.
--
-- See the t3 example below to see how verbose this becomes.
data ChunkOr chunk tag = Chunk_CN (Chunk chunk tag)
                       | POS_CN   (POS tag)
                         deriving (Read, Show, Eq)

instance (ChunkTag c, Arbitrary c, Arbitrary t, Tag t) => Arbitrary (ChunkOr c t) where
  arbitrary = elements =<< do
                chunk <- mkChunk <$> arbitrary <*> listOf arbitrary
                chink <- mkChink <$> arbitrary <*> arbitrary
                return [chunk, chink]

mkChunk :: (ChunkTag chunk, Tag tag) => chunk -> [ChunkOr chunk tag] -> ChunkOr chunk tag
mkChunk chunk children = Chunk_CN (Chunk chunk children)

mkChink :: (ChunkTag chunk, Tag tag) => tag -> Token -> ChunkOr chunk tag
mkChink tag token      = POS_CN (POS tag token)


data Chunk chunk tag = Chunk chunk [ChunkOr chunk tag]
  deriving (Read, Show, Eq)

instance (ChunkTag c, Arbitrary c, Arbitrary t, Tag t) => Arbitrary (Chunk c t) where
  arbitrary = Chunk <$> arbitrary <*> arbitrary

data POS tag = POS tag Token
  deriving (Read, Show, Eq)

instance (Arbitrary t, Tag t) => Arbitrary (POS t) where
  arbitrary = POS <$> arbitrary <*> arbitrary

-- | Show the underlying text token only.
showPOS :: Tag tag => POS tag -> Text
showPOS (POS _ (Token txt)) = txt

-- | Show the text and tag.
printPOS :: Tag tag => POS tag -> Text
printPOS (POS tag (Token txt)) = T.intercalate "" [txt, "/", tagTerm tag]

data Token = Token Text
  deriving (Read, Show, Eq)

instance Arbitrary Token where
  arbitrary = do NonEmpty txt <- arbitrary
                 return $ Token (T.pack txt)

instance IsString Token where
  fromString = Token . T.pack

showTok :: Token -> Text
showTok (Token txt) = txt

suffix :: Token -> Text
suffix (Token str) | T.length str <= 3 = str
                   | otherwise         = T.drop (T.length str - 3) str

unTS :: Tag t => TaggedSentence t -> [POS t]
unTS (TaggedSent ts) = ts

tsLength :: Tag t => TaggedSentence t -> Int
tsLength (TaggedSent ts) = length ts

tsConcat :: Tag t => [TaggedSentence t] -> TaggedSentence t
tsConcat tss = TaggedSent (concatMap unTS tss)

-- flattenText :: Tag t => TaggedSentence t -> Text
-- flattenText (TS ts) = T.unwords $ map fst ts

-- | True if the input sentence contains the given text token.  Does
-- not do partial or approximate matching, and compares details in a
-- fully case-sensitive manner.
contains :: Tag t => TaggedSentence t -> Text -> Bool
contains (TaggedSent ts) tok = any (posTokMatches tok) ts

-- | True if the input sentence contains the given POS tag.
-- Does not do partial matching (such as prefix matching)
containsTag :: Tag t => TaggedSentence t -> t -> Bool
containsTag (TaggedSent ts) tag = any (posTagMatches tag) ts

-- | Compare the POS-tag token with a supplied tag string.
posTagMatches :: Tag t => t -> POS t -> Bool
posTagMatches t1 (POS t2 _) = t1 == t2

-- | Compare the POS-tagged token with a text string.
posTokMatches :: Tag t => Text -> POS t -> Bool
posTokMatches txt (POS _ tok) = tokenMatches txt tok

-- | Compare a token with a text string.
tokenMatches :: Text -> Token -> Bool
tokenMatches txt (Token tok) = txt == tok



-- (S (NP (NN I)) (VP (V saw) (NP (NN him))))
t1 :: Sentence
t1 = Sent
     [ Token "I"
     , Token "saw"
     , Token "him"
     , Token "."
     ]

t2 :: TaggedSentence B.Tag
t2 = TaggedSent
     [ POS B.NN    (Token "I")
     , POS B.VB    (Token "saw")
     , POS B.NN    (Token "him")
     , POS B.Term  (Token ".")
     ]

t3 :: ChunkedSentence B.Chunk B.Tag
t3 = ChunkedSent
     [ mkChunk B.C_NP [ mkChink B.NN (Token "I")  ]
     , mkChunk B.C_VP [ mkChink B.VB (Token "saw")
                      , mkChink B.NN (Token "him")
                      ]
     , mkChink B.Term (Token ".")
     ]


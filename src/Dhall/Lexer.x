{
{-# LANGUAGE OverloadedStrings #-}

-- | Lexing logic for the Dhall language
module Dhall.Lexer (
    -- * Lexer
      lexer

    -- * Types
    , Token(..)

    -- * Re-exports
    , Alex
    , AlexPosn(..)
    , alexError
    , alexGetInput
    , runAlex
    ) where

import Data.ByteString.Lazy (ByteString)
import Data.Monoid ((<>))
import Data.Text.Buildable (Buildable(..))
import Data.Text.Lazy (Text)
import Filesystem.Path (FilePath)
import Numeric.Natural (Natural)
import Prelude hiding (FilePath)

import qualified Data.ByteString.Lazy
import qualified Data.ByteString.Lex.Fractional
import qualified Data.ByteString.Lex.Integral
import qualified Data.Text.Buildable
import qualified Data.Text.Lazy
import qualified Data.Text.Lazy.Encoding
import qualified Filesystem.Path.CurrentOS
}

%wrapper "monad-bytestring"

$digit = 0-9

-- Same as Haskell
$opchar = [\!\#\$\%\&\*\+\.\/\<\=\>\?\@\\\^\|\-\~]

$fst       = [A-Za-z\_]
$labelchar = [A-Za-z0-9\_]

$nonwhite = ~$white

tokens :-

    $white+                             ;
    "--".*                              ;
    "("                                 { emit OpenParen        }
    ")"                                 { emit CloseParen       }
    "{"                                 { emit OpenBrace        }
    "}"                                 { emit CloseBrace       }
    "{{"                                { emit DoubleOpenBrace  }
    "}}"                                { emit DoubleCloseBrace }
    "["                                 { emit OpenBracket      }
    "]"                                 { emit CloseBracket     }
    ":"                                 { emit Colon            }
    ","                                 { emit Comma            }
    "."                                 { emit Dot              }
    "="                                 { emit Equals           }
    "&&"                                { emit And              }
    "||"                                { emit Or               }
    "+"                                 { emit Plus             }
    "++"                                { emit DoublePlus       }
    "-"                                 { emit Dash             }
    "*"                                 { emit Star             }
    "let"                               { emit Let              }
    "in"                                { emit In               }
    "Type"                              { emit Type             }
    "Kind"                              { emit Kind             }
    "->"                                { emit Arrow            }
    "forall"                            { emit Forall           }
    "\"                                 { emit Lambda           }
    "Bool"                              { emit Bool             }
    "True"                              { emit True_            }
    "False"                             { emit False_           }
    "if"                                { emit If               }
    "then"                              { emit Then             }
    "else"                              { emit Else             }
    "Natural"                           { emit Natural          }
    "Natural/fold"                      { emit NaturalFold      }
    "Integer"                           { emit Integer          }
    "Double"                            { emit Double           }
    "Text"                              { emit Text             }
    "Maybe"                             { emit Maybe            }
    "Nothing"                           { emit Nothing_         }
    "Just"                              { emit Just_            }
    "List/build"                        { emit ListBuild        }
    "List/fold"                         { emit ListFold         }
    \" ([^\"] | \\.)* \"                { capture (TextLit . str)        }
    $fst $labelchar* | "(" $opchar+ ")" { capture (Label . toText)       }
    $digit+                             { capture (Number . toInt)       }
    $digit+ (\. $digit+)? ([eE][\+\-]? $digit+)?
                                        { capture (DoubleLit . toDouble) }
    "+" $digit+                         { capture (NaturalLit . toNat)   }
    "https://" $nonwhite+               { capture (URL . toText)         }
    "http://" $nonwhite+                { capture (URL . toText)         }
    "/" $nonwhite+                      { capture (File . toFile 0   )   }
    "./" $nonwhite+                     { capture (File . toFile 2   )   }
    "../" $nonwhite+                    { capture (File . toFile 0   )   }
{
emit :: Token -> AlexAction Token
emit x = \_ _ -> return x

alexEOF :: Alex Token
alexEOF = return EOF

capture :: (ByteString -> Token) -> AlexAction Token
capture k (_, _, rest, _) len = return (k bytes)
  where
    bytes = Data.ByteString.Lazy.take len rest

toInt :: ByteString -> Natural
toInt =
    Data.ByteString.Lex.Integral.readDecimal_ . Data.ByteString.Lazy.toStrict

toDouble :: ByteString -> Double
toDouble bytes =
    case Data.ByteString.Lex.Fractional.readExponential bytes' of
        Just (n, _) -> n
        _           -> error "toDouble: internal error"
  where
    bytes' = Data.ByteString.Lazy.toStrict bytes

toNat :: ByteString -> Natural
toNat = toInt . Data.ByteString.Lazy.drop 1

toFile :: Int64 -> ByteString -> FilePath
toFile n =
      Filesystem.Path.CurrentOS.fromText
    . Data.Text.Lazy.toStrict
    . Data.Text.Lazy.Encoding.decodeUtf8
    . Data.ByteString.Lazy.drop n

toText :: ByteString -> Text
toText = Data.Text.Lazy.Encoding.decodeUtf8

-- TODO: Properly handle errors here
str :: ByteString -> Text
str = read . Data.Text.Lazy.unpack . Data.Text.Lazy.Encoding.decodeUtf8

-- | Convert a text representation of an expression into a stream of tokens
lexer :: (Token -> Alex a) -> Alex a
lexer k = alexMonadScan >>= k

-- | Token type, used to communicate between the lexer and parser
data Token
    = OpenParen
    | CloseParen
    | OpenBrace
    | CloseBrace
    | DoubleOpenBrace
    | DoubleCloseBrace
    | OpenBracket
    | CloseBracket
    | Colon
    | Comma
    | Dot
    | Equals
    | And
    | Or
    | Plus
    | DoublePlus
    | Dash
    | At
    | Star
    | Let
    | In
    | Type
    | Kind
    | Arrow
    | Lambda
    | Forall
    | Bool
    | True_
    | False_
    | If
    | Then
    | Else
    | Natural
    | NaturalLit Natural
    | NaturalFold
    | Integer
    | Text
    | Double
    | DoubleLit Double
    | Maybe
    | Nothing_
    | Just_
    | ListBuild
    | ListFold
    | TextLit Text
    | Label Text
    | Number Natural
    | File FilePath
    | URL Text
    | EOF
    deriving (Eq, Show)

instance Buildable Token where
    build  OpenParen
        = "("
    build  CloseParen
        = ")"
    build  OpenBrace
        = "{"
    build  CloseBrace
        = "}"
    build  DoubleOpenBrace
        = "{{"
    build  DoubleCloseBrace
        = "}}"
    build  OpenBracket
        = "["
    build  CloseBracket
        = "]"
    build  Colon
        = ":"
    build  Comma
        = ","
    build  Dot
        = "."
    build  Equals
        = "="
    build  And
        = "&&"
    build  Or
        = "||"
    build  Plus
        = "+"
    build  DoublePlus
        = "++"
    build  Dash
        = "-"
    build  At
        = "@"
    build  Star
        = "*"
    build  Let
        = "let"
    build  In
        = "in"
    build  Type
        = "Type"
    build  Kind
        = "Kind"
    build  Arrow
        = "->"
    build  Lambda
        = "\\"
    build  Forall
        = "forall"
    build  Bool
        = "Bool"
    build  True_
        = "True"
    build  False_
        = "False"
    build  If
        = "if"
    build  Then
        = "then"
    build  Else
        = "else"
    build  Natural
        = "Natural"
    build (NaturalLit n)
        = "+" <> Data.Text.Buildable.build (fromIntegral n :: Integer)
    build  NaturalFold
        = "Natural/fold"
    build  Integer
        = "Integer"
    build  Text
        = "Text"
    build  Double
        = "Double"
    build (DoubleLit n)
        = Data.Text.Buildable.build n
    build  Maybe
        = "Maybe"
    build  Nothing_
        = "Nothing"
    build  Just_
        = "Just"
    build  ListBuild
        = "List/build"
    build  ListFold
        = "List/fold"
    build (TextLit t)
        = Data.Text.Buildable.build (show t)
    build (Label t)
        = Data.Text.Buildable.build t
    build (Number n)
        = Data.Text.Buildable.build (fromIntegral n :: Integer)
    build (File f)
        = Data.Text.Buildable.build (Filesystem.Path.CurrentOS.encodeString f)
    build (URL t)
        = Data.Text.Buildable.build t
    build  EOF
        = "EOF"
}
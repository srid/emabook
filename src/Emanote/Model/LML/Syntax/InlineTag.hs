{-# LANGUAGE UndecidableInstances #-}

module Emanote.Model.LML.Syntax.InlineTag (inlineTagSpec) where

import Commonmark (TokType (..))
import qualified Commonmark as CM
import qualified Commonmark.Inlines as CM
import qualified Commonmark.Pandoc as CP
import Commonmark.TokParsers (noneOfToks, symbol)
import qualified Text.Pandoc.Builder as B
import qualified Text.Parsec as P

newtype InlineTag = InlineTag {unInlineTag :: Text}
  deriving (Eq, Show, Ord)

class HasInlineTag il where
  inlineTag :: InlineTag -> il

instance CM.Rangeable (CM.Html a) => HasInlineTag (CM.Html a) where
  inlineTag (InlineTag tag) =
    -- CM.link url (show typ) il
    CM.htmlInline "span" (Just $ CM.str tag)
      & CM.addAttribute attrs

attrs :: (Text, Text)
attrs = ("emanaote-type", "inline-tag")

instance HasInlineTag (CP.Cm b B.Inlines) where
  inlineTag (InlineTag tag) =
    CP.Cm $ B.spanWith ("", [], one attrs) $ B.str tag

inlineTagSpec ::
  (Monad m, CM.IsBlock il bl, CM.IsInline il, HasInlineTag il) =>
  CM.SyntaxSpec m il bl
inlineTagSpec =
  mempty
    { CM.syntaxInlineParsers = [pInlineTag]
    }
  where
    pInlineTag ::
      (Monad m, CM.IsInline il, HasInlineTag il) =>
      CM.InlineParser m il
    pInlineTag = P.try $ do
      _ <- symbol '#'
      tag <- CM.untokenize <$> inlineTagP
      pure $ inlineTag $ InlineTag tag
    inlineTagP :: Monad m => P.ParsecT [CM.Tok] s m [CM.Tok]
    inlineTagP =
      some (noneOfToks $ [Spaces, UnicodeSpace, LineEnd] <> fmap Symbol punctuation)
      where
        punctuation = "[];:,.?!"
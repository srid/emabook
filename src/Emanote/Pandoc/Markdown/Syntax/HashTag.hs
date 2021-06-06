{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

-- | TODO: Rename to HashTag?
module Emanote.Pandoc.Markdown.Syntax.HashTag
  ( hashTagSpec,
    hashTags,
    HashTag (..),
  )
where

import Commonmark (TokType (..))
import qualified Commonmark as CM
import qualified Commonmark.Inlines as CM
import qualified Commonmark.Pandoc as CP
import Commonmark.TokParsers (noneOfToks, symbol)
import Ema.Helper.Markdown (plainify)
import qualified Text.Pandoc.Builder as B
import qualified Text.Pandoc.Walk as W
import qualified Text.Parsec as P

mkHashTagFrom :: B.Inline -> Maybe HashTag
mkHashTagFrom = \case
  B.Span (_, [cls], _) is
    | cls == hashTagCls ->
      pure $ HashTag $ plainify is
  _ -> Nothing

hashTags :: B.Pandoc -> [HashTag]
hashTags = W.query $ maybeToList . mkHashTagFrom

newtype HashTag = HashTag {unHashTag :: Text}
  deriving (Eq, Show, Ord)

class HasHashTag il where
  hashTag :: HashTag -> il

instance HasHashTag (CP.Cm b B.Inlines) where
  hashTag (HashTag tag) =
    CP.Cm $ B.spanWith ("", one hashTagCls, one ("title", "Tag")) $ B.str $ "#" <> tag

hashTagCls :: Text
hashTagCls = "emanote:inline-tag"

hashTagSpec ::
  (Monad m, CM.IsBlock il bl, CM.IsInline il, HasHashTag il) =>
  CM.SyntaxSpec m il bl
hashTagSpec =
  mempty
    { CM.syntaxInlineParsers = [pHashTag]
    }
  where
    pHashTag ::
      (Monad m, CM.IsInline il, HasHashTag il) =>
      CM.InlineParser m il
    pHashTag = P.try $ do
      _ <- symbol '#'
      tag <- CM.untokenize <$> hashTagP
      pure $ hashTag $ HashTag tag
    hashTagP :: Monad m => P.ParsecT [CM.Tok] s m [CM.Tok]
    hashTagP =
      some (noneOfToks $ [Spaces, UnicodeSpace, LineEnd] <> fmap Symbol punctuation)
      where
        punctuation = "[];:,.?!"

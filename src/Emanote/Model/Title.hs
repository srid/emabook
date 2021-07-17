{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeApplications #-}

module Emanote.Model.Title
  ( Title,

    -- * Title conversion
    fromRoute,
    fromInlines,
    toInlines,

    -- * Rendering a Title
    titleSplice,
    titleSpliceNoHtml,
  )
where

import Data.Aeson (ToJSON)
import qualified Emanote.Route as R
import Heist (HeistT)
import qualified Heist.Extra.Splices.Pandoc as HP
import qualified Heist.Extra.Splices.Pandoc.Ctx as HP
import Heist.Extra.Splices.Pandoc.Render (plainify)
import qualified Heist.Interpreted as HI
import qualified Text.Pandoc.Definition as B

data Title
  = TitlePlain Text
  | TitlePandoc [B.Inline]
  deriving (Show, Generic, ToJSON)

instance Eq Title where
  (==) =
    -- Use toPlain here, rather than toInlines, because the same text can have
    -- different inlines structure. For example, "Foo Bar" can be represented as
    --   [Str "Foo", Space, Str "Bar"],
    -- or as,
    --   [Str "Foo Bar"]
    on (==) toPlain

instance Ord Title where
  compare =
    on compare toPlain

instance Semigroup Title where
  TitlePlain a <> TitlePlain b =
    TitlePlain (a <> b)
  x <> y =
    TitlePandoc $ on (<>) toInlines x y

instance IsString Title where
  fromString = TitlePlain . toText

fromRoute :: R.LMLRoute -> Title
fromRoute =
  TitlePlain . R.routeBaseName . R.lmlRouteCase

fromInlines :: [B.Inline] -> Title
fromInlines = TitlePandoc

toInlines :: Title -> [B.Inline]
toInlines = \case
  TitlePlain s -> one (B.Str s)
  TitlePandoc is -> is

toPlain :: Title -> Text
toPlain = \case
  TitlePlain s -> s
  TitlePandoc is -> plainify is

titleSplice :: Monad n => HP.RenderCtx n -> (B.Pandoc -> B.Pandoc) -> Title -> HI.Splice n
titleSplice ctx f = \case
  TitlePlain x ->
    HI.textSplice x
  TitlePandoc is -> do
    let titleDoc = f $ B.Pandoc mempty $ one $ B.Plain is
    HP.pandocSplice ctx titleDoc

_mkEmptyRenderCtx :: (Monad m, Monad n) => HeistT n m (HP.RenderCtx n)
_mkEmptyRenderCtx =
  HP.mkRenderCtx mempty (const . const $ Nothing) (const . const $ Nothing)

titleSpliceNoHtml :: Monad n => Title -> HI.Splice n
titleSpliceNoHtml =
  HI.textSplice . toPlain

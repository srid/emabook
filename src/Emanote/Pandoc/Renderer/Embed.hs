{-# LANGUAGE RecordWildCards #-}

module Emanote.Pandoc.Renderer.Embed where

import Control.Lens.Operators ((^.))
import Data.Map.Syntax ((##))
import qualified Data.Text as T
import Emanote.Model (Model)
import qualified Emanote.Model.Link.Rel as Rel
import qualified Emanote.Model.Link.Resolve as Resolve
import qualified Emanote.Model.Note as MN
import qualified Emanote.Model.StaticFile as SF
import qualified Emanote.Model.Title as Tit
import Emanote.Pandoc.BuiltinFilters (prepareNoteDoc, preparePandoc)
import qualified Emanote.Pandoc.Link as Link
import qualified Emanote.Pandoc.Markdown.Syntax.WikiLink as WL
import Emanote.Pandoc.Renderer (PandocBlockRenderer, PandocInlineRenderer)
import qualified Emanote.Pandoc.Renderer.Url as RenderedUrl
import qualified Emanote.Route as R
import qualified Emanote.Route.SiteRoute as SR
import qualified Heist as H
import qualified Heist.Extra as HE
import Heist.Extra.Splices.Pandoc (pandocSplice)
import qualified Heist.Extra.Splices.Pandoc as HP
import qualified Heist.Interpreted as HI
import Relude
import qualified Text.Pandoc.Definition as B

embedBlockWikiLinkResolvingSplice ::
  Monad n => PandocBlockRenderer n i b
embedBlockWikiLinkResolvingSplice emaAction model _nf ctx _ = \case
  B.Para [inl] -> do
    (inlRef, (_, _, otherAttrs), is, (url, tit)) <- Link.parseInlineRef inl
    guard $ inlRef == Link.InlineLink
    Rel.URTWikiLink (WL.WikiLinkEmbed, wl) <-
      Rel.parseUnresolvedRelTarget (otherAttrs <> one ("title", tit)) url
    let rRel = Resolve.resolveWikiLinkMustExist model wl
    let f = embedBlockSiteRoute model ctx
    RenderedUrl.renderSomeInlineRefWith f Resolve.resourceSiteRoute (is, (url, tit)) rRel emaAction model ctx inl
  _ ->
    Nothing

embedInlineWikiLinkResolvingSplice ::
  Monad n => PandocInlineRenderer n i b
embedInlineWikiLinkResolvingSplice emaAction model _nf ctx _ inl = do
  (inlRef, (_, _, otherAttrs), is, (url, tit)) <- Link.parseInlineRef inl
  guard $ inlRef == Link.InlineLink
  Rel.URTWikiLink (WL.WikiLinkEmbed, wl) <- Rel.parseUnresolvedRelTarget (otherAttrs <> one ("title", tit)) url
  let rRel = Resolve.resolveWikiLinkMustExist model wl
      f = embedInlineSiteRoute wl
  RenderedUrl.renderSomeInlineRefWith f Resolve.resourceSiteRoute (is, (url, tit)) rRel emaAction model ctx inl

embedBlockSiteRoute :: Monad n => Model -> HP.RenderCtx n -> Either MN.Note SF.StaticFile -> Maybe (HI.Splice n)
embedBlockSiteRoute model ctx = either (embedResourceRoute model ctx) (const Nothing)

embedInlineSiteRoute :: Monad n => WL.WikiLink -> Either MN.Note SF.StaticFile -> Maybe (HI.Splice n)
embedInlineSiteRoute wl = either (const Nothing) (embedStaticFileRoute wl)

runEmbedTemplate :: Monad n => ByteString -> H.Splices (HI.Splice n) -> HI.Splice n
runEmbedTemplate name splices = do
  tpl <- HE.lookupHtmlTemplateMust $ "/templates/filters/embed-" <> name
  HE.runCustomTemplate tpl splices

embedResourceRoute :: Monad n => Model -> HP.RenderCtx n -> MN.Note -> Maybe (HI.Splice n)
embedResourceRoute model ctx note = do
  pure . runEmbedTemplate "note" $ do
    "ema:note:title" ## Tit.titleSplice ctx (preparePandoc model) (MN._noteTitle note)
    "ema:note:url" ## HI.textSplice (SR.siteRouteUrl model $ SR.lmlSiteRoute $ note ^. MN.noteRoute)
    "ema:note:pandoc"
      ## pandocSplice ctx (prepareNoteDoc model $ MN._noteDoc note)

embedStaticFileRoute :: Monad n => WL.WikiLink -> SF.StaticFile -> Maybe (HI.Splice n)
embedStaticFileRoute wl staticFile = do
  let r = staticFile ^. SF.staticFileRoute
      fp = staticFile ^. SF.staticFilePath
  if
      | any (`T.isSuffixOf` toText fp) imageExts ->
        pure . runEmbedTemplate "image" $ do
          "ema:url" ## HI.textSplice (toText $ R.encodeRoute r)
          "ema:alt" ## HI.textSplice $ show wl
      | any (`T.isSuffixOf` toText fp) videoExts -> do
        pure . runEmbedTemplate "video" $ do
          "ema:url" ## HI.textSplice (toText $ R.encodeRoute r)
      | otherwise -> Nothing

imageExts :: [Text]
imageExts =
  [ ".jpg",
    ".jpeg",
    ".png",
    ".svg",
    ".gif",
    ".bmp"
  ]

videoExts :: [Text]
videoExts =
  [ ".mp4",
    ".webm",
    ".ogv"
  ]

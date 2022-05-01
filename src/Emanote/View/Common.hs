{-# LANGUAGE RecordWildCards #-}

module Emanote.View.Common
  ( commonSplices,
    inlineRenderers,
    renderModelTemplate,
    routeBreadcrumbs,
    TemplateRenderCtx (..),
    mkTemplateRenderCtx,
    generatedCssFile,
  )
where

import Data.Aeson.Types qualified as Aeson
import Data.Map.Syntax ((##))
import Data.Text qualified as T
import Data.Version (showVersion)
import Ema qualified
import Emanote.Model.Note qualified as MN
import Emanote.Model.Title qualified as Tit
import Emanote.Model.Type (Model)
import Emanote.Model.Type qualified as M
import Emanote.Pandoc.BuiltinFilters (preparePandoc)
import Emanote.Pandoc.Renderer (PandocRenderers (..))
import Emanote.Pandoc.Renderer qualified as Renderer
import Emanote.Pandoc.Renderer.Embed qualified as PF
import Emanote.Pandoc.Renderer.Query qualified as PF
import Emanote.Pandoc.Renderer.Url qualified as PF
import Emanote.Route (LMLRoute)
import Emanote.Route qualified as R
import Emanote.Route.SiteRoute.Class qualified as SR
import Emanote.View.LiveServerFiles qualified as LiveServerFiles
import Heist qualified as H
import Heist.Extra.Splices.List qualified as Splices
import Heist.Extra.Splices.Pandoc.Ctx (RenderCtx)
import Heist.Extra.TemplateState qualified as Tmpl
import Heist.Interpreted qualified as HI
import Heist.Splices.Apply qualified as HA
import Heist.Splices.Bind qualified as HB
import Heist.Splices.Json qualified as HJ
import Optics.Operators ((^.))
import Paths_emanote qualified
import Relude
import Text.Blaze.Html ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Blaze.Renderer.XmlHtml qualified as RX

blockRenderers :: Monad n => PandocRenderers n
blockRenderers =
  PandocRenderers
    [ PF.embedInlineWikiLinkResolvingSplice, -- embedInlineWikiLinkResolvingSplice should be first to recognize inline Link elements first
      PF.urlResolvingSplice
    ]
    [ PF.embedBlockWikiLinkResolvingSplice,
      PF.queryResolvingSplice
    ]

-- | Like `blockRenderers` but for use in inline contexts.
--
-- Backlinks and titles constitute an example of inline context, where we don't
-- care about block elements.
inlineRenderers :: Monad n => PandocRenderers n
inlineRenderers =
  PandocRenderers
    [ PF.embedInlineWikiLinkResolvingSplice, -- embedInlineWikiLinkResolvingSplice should be first to recognize inline Link elements first
      PF.urlResolvingSplice
    ]
    mempty

-- | Like `inlineRenderers` but suitable for use inside links (<a> tags).
linkInlineRenderers :: Monad n => PandocRenderers n
linkInlineRenderers =
  PandocRenderers
    [ PF.plainifyWikiLinkSplice
    ]
    mempty

data TemplateRenderCtx n = TemplateRenderCtx
  { withInlineCtx :: (RenderCtx n -> HI.Splice n) -> HI.Splice n,
    withBlockCtx :: (RenderCtx n -> HI.Splice n) -> HI.Splice n,
    withLinkInlineCtx :: (RenderCtx n -> HI.Splice n) -> HI.Splice n,
    titleSplice :: Tit.Title -> HI.Splice n
  }

-- | Create the context in which Heist templates (notably `pandoc.tpl`) will be
-- rendered.
mkTemplateRenderCtx ::
  Monad n =>
  -- | Current model.
  Model ->
  -- | Current route.
  R.LMLRoute ->
  -- | Associated metadata.
  Aeson.Value ->
  TemplateRenderCtx n
mkTemplateRenderCtx model r meta =
  let withInlineCtx =
        withRenderCtx inlineRenderers
      withLinkInlineCtx =
        withRenderCtx linkInlineRenderers
      withBlockCtx =
        withRenderCtx blockRenderers
      -- TODO: We should be using withInlineCtx, so as to make the wikilink
      -- render in note title.
      titleSplice titleDoc = withLinkInlineCtx $ \ctx ->
        Tit.titleSplice ctx preparePandoc titleDoc
   in TemplateRenderCtx {..}
  where
    withRenderCtx ::
      (Monad m, Monad n) =>
      PandocRenderers n ->
      (RenderCtx n -> H.HeistT n m x) ->
      H.HeistT n m x
    withRenderCtx pandocRenderers f =
      f
        =<< Renderer.mkRenderCtxWithPandocRenderers
          pandocRenderers
          classRules
          model
          r
    classRules :: Map Text Text
    classRules =
      MN.lookupAeson mempty ("pandoc" :| ["rewriteClass"]) meta

generatedCssFile :: FilePath
generatedCssFile = "tailwind.css"

commonSplices ::
  HasCallStack =>
  Monad n =>
  ((RenderCtx n -> HI.Splice n) -> HI.Splice n) ->
  Model ->
  Aeson.Value ->
  Tit.Title ->
  H.Splices (HI.Splice n)
commonSplices withCtx model meta routeTitle = do
  let siteTitle = fromString . toString $ MN.lookupAeson @Text "Emabook Site" ("page" :| ["siteTitle"]) meta
      routeTitleFull =
        if routeTitle == siteTitle
          then siteTitle
          else routeTitle <> " – " <> siteTitle
  -- Heist helpers
  "bind" ## HB.bindImpl
  "apply" ## HA.applyImpl
  -- Add tailwind css shim
  "tailwindCssShim"
    ## do
      pure . RX.renderHtmlNodes $
        if M.inLiveServer model
          then do
            -- Twind shim doesn't reliably work in dev server mode. Let's just use the
            -- tailwind CDN.
            cachedTailwindCdn
          else do
            H.link
              -- TODO: Use ?md5 to prevent stale browser caching of CSS.
              ! A.href (H.toValue $ cannotBeCached generatedCssFile)
              ! A.rel "stylesheet"
              ! A.type_ "text/css"
  "ema:version"
    ## HI.textSplice (toText $ showVersion Paths_emanote.version)
  "ema:metadata"
    ## HJ.bindJson meta
  "ema:title" ## withCtx $ \ctx ->
    Tit.titleSplice ctx preparePandoc routeTitle
  -- <head>'s <title> cannot contain HTML
  "ema:titleFull"
    ## Tit.titleSpliceNoHtml routeTitleFull
  -- `ema:homeUrl` is normally `""`; but if Emanote is being served from an URL
  -- prefix, it would be "/foo/" (with a slash at the end). This allows you to
  -- just concatanate homeUrl with a relative URL path (no slash in between), to
  -- get the full URL. The reason there is no slash in between is to account for
  -- the usual case of homeUrl being an empty string.
  "ema:homeUrl"
    ## ( let homeR = SR.lmlSiteRoute $ R.liftLMLRoute @('R.LMLType 'R.Md) R.indexRoute
             homeUrl' = SR.siteRouteUrl model homeR
             homeUrl = if homeUrl' /= "" then homeUrl' <> "/" else homeUrl'
          in HI.textSplice homeUrl
       )
  "ema:indexUrl"
    ## HI.textSplice (SR.siteRouteUrl model SR.indexRoute)
  "ema:tagIndexUrl"
    ## HI.textSplice (SR.siteRouteUrl model $ SR.tagIndexRoute [])
  "ema:taskIndexUrl"
    ## HI.textSplice (SR.siteRouteUrl model SR.taskIndexRoute)
  "ema:emanoteStaticLayerUrl"
    ## HI.textSplice
      ( -- HACK
        -- Also: more-head.tpl is the one place where this is hardcoded.
        let itUrl =
              SR.siteRouteUrl model $
                SR.staticFileSiteRoute $
                  fromMaybe (error "no _emanote-static?") $ M.modelLookupStaticFile "_emanote-static/inverted-tree.css" model
         in fst $ T.breakOn "/inverted-tree.css" itUrl
      )
  -- For those cases the user really wants to hardcode the URL
  "ema:urlStrategySuffix"
    ## HI.textSplice (SR.urlStrategySuffix model)
  where
    -- A hack to force the browser not to cache the CSS, because we are not md5
    -- hashing the CSS yet (because the CSS is generated *after* the HTML files
    -- are generated.)
    -- For a proper way to do this, see: https://github.com/srid/ema/issues/20
    cannotBeCached url = url <> "?instanceId=" <> show (model ^. M.modelInstanceID)
    cachedTailwindCdn = do
      let localCdnUrl =
            SR.siteRouteUrl model $
              SR.staticFileSiteRoute $ LiveServerFiles.tailwindCssFile model
      H.link
        ! A.href (H.toValue localCdnUrl)
        ! A.rel "stylesheet"
        ! A.type_ "text/css"

renderModelTemplate :: Model -> Tmpl.TemplateName -> H.Splices (HI.Splice Identity) -> LByteString
renderModelTemplate model templateName =
  let handleErr =
        if M.inLiveServer model
          then Ema.emaErrorHtmlResponse
          else -- When staticaly generating, we must fail asap on template errors.
            error
   in -- Until Ema's error handling improves ...
      either handleErr id
        . flip (Tmpl.renderHeistTemplate templateName) (model ^. M.modelHeistTemplate)

routeBreadcrumbs :: Monad n => TemplateRenderCtx n -> Model -> LMLRoute -> HI.Splice n
routeBreadcrumbs TemplateRenderCtx {..} model r =
  Splices.listSplice (init $ R.routeInits . R.lmlRouteCase $ r) "each-crumb" $
    \(R.liftLMLRoute -> crumbR) -> do
      "crumb:url" ## HI.textSplice (SR.siteRouteUrl model $ SR.lmlSiteRoute crumbR)
      "crumb:title" ## titleSplice (M.modelLookupTitle crumbR model)

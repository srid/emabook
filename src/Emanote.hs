{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Emanote
  ( run,
    defaultEmanoteConfig,
  )
where

import Control.Monad.Logger (runStderrLoggingT, runStdoutLoggingT)
import Control.Monad.Writer.Strict (MonadWriter (tell), WriterT (runWriterT))
import Data.Default (def)
import Data.Dependent.Sum (DSum ((:=>)))
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Ema
  ( CanRender (..),
    HasModel (..),
    IsRoute (..),
    runSiteWithCli,
  )
import Ema.CLI qualified
import Emanote.CLI qualified as CLI
import Emanote.Model.Link.Rel (ResolvedRelTarget (..))
import Emanote.Model.Type qualified as Model
import Emanote.Pandoc.Renderer
import Emanote.Pandoc.Renderer.Embed qualified as PF
import Emanote.Pandoc.Renderer.Query qualified as PF
import Emanote.Pandoc.Renderer.Url qualified as PF
import Emanote.Prelude (log, logE, logW)
import Emanote.Route.ModelRoute (LMLRoute, lmlRouteCase)
import Emanote.Route.SiteRoute.Class (emanoteGeneratableRoutes, emanoteRouteEncoder)
import Emanote.Route.SiteRoute.Type (SiteRoute)
import Emanote.Source.Dynamic (EmanoteConfig (..), emanoteModelDynamic)
import Emanote.View.Common (generatedCssFile)
import Emanote.View.Export qualified as Export
import Emanote.View.Template qualified as View
import Optics.Core ((%), (.~))
import Relude
import System.FilePath ((</>))
import UnliftIO (MonadUnliftIO)
import Web.Tailwind qualified as Tailwind

instance IsRoute SiteRoute where
  type RouteModel SiteRoute = Model.Model
  routeEncoder = emanoteRouteEncoder
  allRoutes = emanoteGeneratableRoutes

instance CanRender SiteRoute where
  routeAsset = View.emanoteRouteAsset

instance HasModel SiteRoute where
  type ModelInput SiteRoute = EmanoteConfig
  modelDynamic = emanoteModelDynamic

defaultEmanoteConfig :: CLI.Cli -> EmanoteConfig
defaultEmanoteConfig cli =
  EmanoteConfig cli id defaultEmanotePandocRenderers

run :: EmanoteConfig -> IO ()
run cfg@EmanoteConfig {..} = do
  Ema.runSiteWithCli @SiteRoute (CLI.emaCli _emanoteConfigCli) cfg
    >>= postRun cfg

postRun :: EmanoteConfig -> (Model.Model, DSum Ema.CLI.Action Identity) -> IO ()
postRun EmanoteConfig {..} = \case
  (model0, Ema.CLI.Generate outPath :=> Identity genPaths) -> do
    compileTailwindCss outPath genPaths
    checkBrokenLinks _emanoteConfigCli $ Export.modelRels model0
    checkBadMarkdownFiles $ Model.modelNoteErrors model0
  _ ->
    pure ()

checkBadMarkdownFiles :: Map LMLRoute [Text] -> IO ()
checkBadMarkdownFiles noteErrs = runStderrLoggingT $ do
  forM_ (Map.toList noteErrs) $ \(noteRoute, errs) -> do
    logW $ "Bad markdown file: " <> show noteRoute
    forM_ errs $ \err -> do
      logE $ "  - " <> err
  unless (null noteErrs) $ do
    logE "Errors found."
    exitFailure

checkBrokenLinks :: CLI.Cli -> Map LMLRoute [Export.Link] -> IO ()
checkBrokenLinks cli modelRels = runStderrLoggingT $ do
  ((), res :: Sum Int) <- runWriterT $
    forM_ (Map.toList modelRels) $ \(noteRoute, rels) ->
      forM_ (Set.toList $ Set.fromList rels) $ \(Export.Link urt rrt) ->
        case rrt of
          RRTFound _ -> pure ()
          RRTMissing -> do
            logW $ "Broken link: " <> show (lmlRouteCase noteRoute) <> " -> " <> show urt
            tell 1
          RRTAmbiguous ls -> do
            logW $ "Ambiguous link: " <> show (lmlRouteCase noteRoute) <> " -> " <> show urt <> " ambiguities: " <> show ls
            tell 1
  if res == 0
    then do
      log "No broken links detected."
    else unless (CLI.allowBrokenLinks cli) $ do
      logE $ "Found " <> show (getSum res) <> " broken links! Emanote generated the site, but the generated site has broken links."
      log "(Tip: use `--allow-broken-links` to ignore this check.)"
      exitFailure

compileTailwindCss :: MonadUnliftIO m => FilePath -> [FilePath] -> m ()
compileTailwindCss outPath genPaths = do
  let cssPath = outPath </> generatedCssFile
  putStrLn $ "Compiling CSS using tailwindcss: " <> cssPath
  runStdoutLoggingT . Tailwind.runTailwind $
    def
      & Tailwind.tailwindConfig % Tailwind.tailwindConfigContent .~ genPaths
      & Tailwind.tailwindOutput .~ cssPath
      & Tailwind.tailwindMode .~ Tailwind.Production

defaultEmanotePandocRenderers :: EmanotePandocRenderers Model.Model LMLRoute
defaultEmanotePandocRenderers =
  let blockRenderers =
        PandocRenderers
          [ PF.embedInlineWikiLinkResolvingSplice, -- embedInlineWikiLinkResolvingSplice should be first to recognize inline Link elements first
            PF.urlResolvingSplice
          ]
          [ PF.embedBlockWikiLinkResolvingSplice,
            PF.queryResolvingSplice
          ]
      inlineRenderers =
        PandocRenderers
          [ PF.embedInlineWikiLinkResolvingSplice, -- embedInlineWikiLinkResolvingSplice should be first to recognize inline Link elements first
            PF.urlResolvingSplice
          ]
          mempty
      linkInlineRenderers =
        PandocRenderers
          [ PF.plainifyWikiLinkSplice
          ]
          mempty
   in EmanotePandocRenderers {..}

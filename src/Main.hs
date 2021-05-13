{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Main where

import Control.Exception (throw)
import Control.Monad.Logger
import Data.Default (Default (..))
import Data.Map.Syntax ((##))
import qualified Data.Map.Syntax as MapSyntax
import qualified Data.Text as T
import qualified Ema
import qualified Ema.CLI
import qualified Ema.Helper.FileSystem as FileSystem
import qualified Ema.Helper.Markdown as Markdown
import qualified Ema.Helper.PathTree as PathTree
import Emabook.Model (Model)
import qualified Emabook.Model as M
import qualified Emabook.PandocUtil as PandocUtil
import Emabook.Route (MarkdownRoute)
import qualified Emabook.Route as R
import qualified Emabook.Template as T
import qualified Emabook.Template.Splices.List as Splices
import qualified Emabook.Template.Splices.Pandoc as Splices
import qualified Emabook.Template.Splices.Tree as Splices
import qualified Heist.Interpreted as HI
import System.FilePath ((</>))
import qualified Text.Blaze.Html5 as H
import qualified Text.Pandoc.Builder as B
import Text.Pandoc.Definition (Pandoc (..))

-- ------------------------
-- Main entry point
-- ------------------------

log :: MonadLogger m => Text -> m ()
log = logInfoNS "emabook"

logD :: MonadLogger m => Text -> m ()
logD = logDebugNS "emabook"

logE :: MonadLogger m => Text -> m ()
logE = logErrorNS "emabook"

data Source
  = SourceMarkdown
  | SourceTemplate FilePath
  deriving (Eq, Show)

sourcePattern :: Source -> FilePath
sourcePattern = \case
  SourceMarkdown -> "**/*.md"
  SourceTemplate dir -> dir </> "*.tpl"

main :: IO ()
main =
  Ema.runEma render $ \model -> do
    let pats = [SourceMarkdown, SourceTemplate ".emabook/templates"] <&> id &&& sourcePattern
    FileSystem.mountOnLVar "." pats model $ \(src, fp) action ->
      case src of
        SourceMarkdown -> case action of
          FileSystem.Update ->
            readMarkdown fp
              <&> maybe id (uncurry M.modelInsert)
          FileSystem.Delete ->
            pure $ maybe id M.modelDelete (R.mkMarkdownRouteFromFilePath fp)
        SourceTemplate dir ->
          M.modelSetHeistTemplate <$> T.loadHeistTemplates dir
  where
    readMarkdown :: (MonadIO m, MonadLogger m) => FilePath -> m (Maybe (MarkdownRoute, (M.Meta, Pandoc)))
    readMarkdown fp =
      runMaybeT $ do
        r :: MarkdownRoute <- MaybeT $ pure $ R.mkMarkdownRouteFromFilePath fp
        logD $ "Reading " <> toText fp
        !s <- readFileText fp
        case parseMarkdown fp s of
          Left (BadMarkdown -> err) -> do
            throw err
          Right (mMeta, doc) ->
            pure (r, (fromMaybe def mMeta, doc))
    parseMarkdown =
      Markdown.parseMarkdownWithFrontMatter @M.Meta $
        Markdown.wikilinkSpec <> Markdown.fullMarkdownSpec

newtype BadMarkdown = BadMarkdown Text
  deriving (Show, Exception)

-- ------------------------
-- Our site rendering
-- ------------------------

render :: Ema.CLI.Action -> Model -> MarkdownRoute -> LByteString
render _ model r = do
  let mDoc = M.modelLookup r model
  -- TODO: Look for "${r}" template, and then fallback to _default
  flip (T.renderHeistTemplate "_default") (M.modelHeistTemplate model) $ do
    -- Common stuff
    "theme" ## HI.textSplice "yellow"
    -- Nav stuff
    "ema:route-tree"
      ## ( let tree = PathTree.treeDeleteChild "index" $ M.modelNav model
            in Splices.treeSplice tree r R.MarkdownRoute $ H.toHtml . flip M.routeTitle model
         )
    "ema:breadcrumbs"
      ## Splices.listSplice (init $ R.markdownRouteInits r) "crumb"
      $ \crumb ->
        MapSyntax.mapV HI.textSplice $ do
          "crumb:url" ## Ema.routeUrl crumb
          "crumb:title" ## M.routeTitle crumb model
    -- Note stuff
    "ema:note:title"
      ## HI.textSplice
      $ M.routeTitle r model
    "ema:note:tags"
      ## Splices.listSplice (fromMaybe mempty $ M.tags . fst =<< mDoc) "tag"
      $ \tag ->
        MapSyntax.mapV HI.textSplice $ do
          "tag:name" ## tag
    "ema:note:pandoc"
      ## Splices.pandocSplice
      $ case mDoc of
        Nothing ->
          -- This route doesn't correspond to any Markdown file on disk. Could be one of the reasons,
          -- 1. Refers to a folder route (and no ${folder}.md exists)
          -- 2. A broken wiki-links
          -- In both cases, we take the lenient approach, and display an empty page (but with title).
          -- TODO: Display folder children if this is a folder note. It is hinted to in the sidebar too.
          Pandoc mempty $ one $ B.Plain $ one $ B.Str "No Markdown file for this route"
        Just (_, doc) ->
          sanitizeMarkdown model doc

sanitizeMarkdown :: Model -> Pandoc -> Pandoc
sanitizeMarkdown model doc =
  doc
    & PandocUtil.withoutH1 -- Eliminate H1, because we are handling it separately.
    & rewriteWikiLinks
    & rewriteMdLinks
  where
    -- Rewrite [[Foo]] -> path/to/where/it/exists/Foo.md
    rewriteWikiLinks =
      PandocUtil.rewriteRelativeLinks $ \url -> fromMaybe url $ do
        guard $ not $ "/" `T.isSuffixOf` url
        -- Resolve [[Foo]] -> Foo.md's route if it exists in model anywhere in
        -- hierarchy.
        -- TODO: If "Foo" doesdn't exist, *and* is not refering to a staticAsset, then
        -- We should track it as a "missing wiki-link", to be resolved (in
        -- future) when the target gets created by the user.
        r <- M.modelLookupFileName url model
        pure $ toText $ R.markdownRouteSourcePath r
    -- Rewrite /foo/bar.md to `Ema.routeUrl` of the markdown route.
    rewriteMdLinks =
      PandocUtil.rewriteRelativeLinks $ \url -> fromMaybe url $ do
        guard $ ".md" `T.isSuffixOf` url
        r <- R.mkMarkdownRouteFromFilePath $ toString url
        pure $ Ema.routeUrl r

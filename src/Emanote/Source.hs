{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Emanote.Source where

import Control.Exception (throw)
import Control.Lens.Operators ((%~))
import Control.Monad.Logger
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Yaml as Yaml
import qualified Ema.Helper.FileSystem as FileSystem
import qualified Ema.Helper.Markdown as Markdown
import Emanote.Model (Model)
import qualified Emanote.Model as M
import qualified Emanote.Route as R
import Emanote.Route.Ext (FileType (LMLType), LML (Md))
import qualified Emanote.Route.Ext as Ext
import qualified Heist.Extra.TemplateState as T
import qualified Paths_emanote
import System.Directory (withCurrentDirectory)
import System.FilePath ((</>))
import System.FilePattern (FilePattern)
import qualified System.FilePattern.Directory as FP

log :: MonadLogger m => Text -> m ()
log = logInfoNS "emanote"

logD :: MonadLogger m => Text -> m ()
logD = logDebugNS "emanote"

logE :: MonadLogger m => Text -> m ()
logE = logErrorNS "emanote"

-- | Represents the different kinds of file the application will handle.
data Source
  = -- | Markdown file
    SourceLML Ext.LML
  | -- | YAML data file
    SourceData
  | -- | Heist template file
    SourceTemplate
  | -- | The rest are considered static files to copy as-is
    SourceStatic
  deriving (Eq, Ord, Show)

sourcePattern :: Source -> FilePath
sourcePattern = \case
  SourceLML Ext.Md ->
    Ext.withExt @('Ext.LMLType 'Ext.Md) $
      "**/*"
  SourceData ->
    Ext.withExt @'Ext.Yaml $
      "**/*"
  SourceTemplate ->
    Ext.withExt @'Ext.HeistTpl $
      "**/*"
  SourceStatic ->
    "**"

filePatterns :: [(Source, FilePattern)]
filePatterns =
  (id &&& sourcePattern)
    <$> [ SourceLML Ext.Md,
          SourceData,
          SourceTemplate,
          SourceStatic
        ]

ignorePatterns :: [FilePattern]
ignorePatterns =
  [ -- Ignore all top-level dotfile directories (eg: .git, .vscode)
    ".*/**"
  ]

defaultTemplateState :: (MonadIO m, MonadLogger m) => m T.TemplateState
defaultTemplateState = do
  st <- T.newTemplateState
  defaultFiles <- liftIO Paths_emanote.getDataDir
  let tmplDir = defaultFiles </> "templates"
  log $ "Loading default templates from " <> toText tmplDir
  liftIO $
    withCurrentDirectory defaultFiles $ do
      files <- FP.getDirectoryFiles "." ["**/*.tpl"]
      filesWithContent <- forM files $ \fp -> (fp,) <$> readFileBS fp
      pure $ addTemplateFiles filesWithContent st

addTemplateFiles :: [(FilePath, ByteString)] -> T.TemplateState -> T.TemplateState
addTemplateFiles tpls ts = do
  foldl' (\st (fp, s) -> T.addTemplateFile fp s st) ts tpls

defaultData :: (MonadIO m, MonadLogger m) => m Aeson.Value
defaultData = do
  defaultFiles <- liftIO Paths_emanote.getDataDir
  let indexYaml = defaultFiles </> "index.yaml"
  log $ "Loading index.yaml from " <> toText indexYaml
  parseSData =<< readFileBS indexYaml

-- | Like `transformAction` but operates on multiple source types at a time
transformActions :: (MonadIO m, MonadLogger m) => [(Source, [FilePath])] -> FileSystem.FileAction -> m (Model -> Model)
transformActions sources action =
  chainM sources $ \(src, fps) ->
    transformAction src fps action

-- | Transform a filesystem action (on a source) to model update
transformAction :: (MonadIO m, MonadLogger m) => Source -> [FilePath] -> FileSystem.FileAction -> m (Model -> Model)
transformAction src fps action =
  case src of
    SourceLML Ext.Md -> case action of
      FileSystem.Update ->
        chainM fps $ \fp ->
          fmap (fromMaybe id) . runMaybeT $ do
            r :: R.Route ('LMLType 'Md) <- MaybeT $ pure $ R.mkRouteFromFilePath @('Ext.LMLType 'Ext.Md) fp
            -- TODO: Log in batches, to avoid slowing things down when using large notebooks
            logD $ "Reading note: " <> toText fp
            !s <- readFileText fp
            (mMeta, doc) <- either (throw . BadInput) pure $ parseMarkdown fp s
            pure $ M.modelInsertMarkdown r (fromMaybe Aeson.Null mMeta, doc)
      FileSystem.Delete ->
        chainM fps $ \fp ->
          pure $ maybe id M.modelDeleteMarkdown (R.mkRouteFromFilePath @('Ext.LMLType 'Ext.Md) fp)
    SourceData -> case action of
      FileSystem.Update -> do
        chainM fps $ \fp ->
          fmap (fromMaybe id) . runMaybeT $ do
            r :: R.Route 'Ext.Yaml <- MaybeT $ pure $ R.mkRouteFromFilePath @'Ext.Yaml fp
            logD $ "Reading data: " <> toText fp
            !s <- readFileBS fp
            sdata <- parseSData s
            pure $ M.modelInsertData r sdata
      FileSystem.Delete ->
        chainM fps $ \fp ->
          pure $ maybe id M.modelDeleteData (R.mkRouteFromFilePath @'Ext.Yaml fp)
    SourceTemplate -> do
      -- TODO: Juse use chainM?
      print fps
      tpls <- forM fps $ \fp -> (fp,) <$> readFileBS fp
      -- TODO: Handle *removing* of templates! ... however, don't remove *default* ones.
      log $ "Reading " <> show (length tpls) <> " template: " <> Text.intercalate ", " (toText . fst <$> tpls)
      pure $ M.modelHeistTemplate %~ addTemplateFiles tpls
    SourceStatic -> do
      let setAction = case action of
            FileSystem.Update -> Set.union
            FileSystem.Delete -> flip Set.difference
      pure $ M.modelStaticFiles %~ setAction (Set.fromList $ mapMaybe R.mkRouteFromFilePath fps)
  where
    parseMarkdown =
      Markdown.parseMarkdownWithFrontMatter @Aeson.Value $
        Markdown.wikilinkSpec <> Markdown.fullMarkdownSpec

parseSData :: (Applicative f, Yaml.FromJSON a) => ByteString -> f a
parseSData s =
  either (throw . BadInput . show) pure $
    Yaml.decodeEither' s

-- | Apply the list of actions in the given order to an initial argument.
--
-- chain [f1, f2, ...] x = ... (f2 (f1 x))
chain :: [a -> a] -> a -> a
chain = flip (foldl' $ flip ($))

-- | Monadic version of `chain`
chainM :: Monad m => [b] -> (b -> m (a -> a)) -> m (a -> a)
chainM xs =
  fmap chain . forM xs

newtype BadInput = BadInput Text
  deriving (Show, Exception)

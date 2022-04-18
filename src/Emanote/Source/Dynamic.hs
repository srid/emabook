module Emanote.Source.Dynamic
  ( emanoteModelDynamic,
  )
where

import Control.Monad.Logger (MonadLogger, MonadLoggerIO)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Some (Some)
import Data.UUID.V4 qualified as UUID
import Ema (Dynamic (..))
import Ema.CLI qualified
import Ema.Route.Encoder (RouteEncoder)
import Emanote.CLI qualified as CLI
import Emanote.Model.Type qualified as Model
import Emanote.Prelude (chainM)
import Emanote.Route.SiteRoute.Type (SiteRoute)
import Emanote.Source.Loc (Loc)
import Emanote.Source.Loc qualified as Loc
import Emanote.Source.Patch qualified as Patch
import Emanote.Source.Pattern qualified as Pattern
import Paths_emanote qualified
import Relude
import System.UnionMount qualified as UM
import UnliftIO (MonadUnliftIO)

-- | Make an Ema `Dynamic` for the Emanote model.
--
-- The bulk of logic for building the Dynamic is in `Patch.hs`.
emanoteModelDynamic :: (MonadUnliftIO m, MonadLoggerIO m) => Some Ema.CLI.Action -> RouteEncoder Model.Model SiteRoute -> CLI.Cli -> m (Dynamic m Model.Model)
emanoteModelDynamic cliAct enc cli = do
  defaultLayer <- Loc.defaultLayer <$> liftIO Paths_emanote.getDataDir
  instanceId <- liftIO UUID.nextRandom
  let layers = Loc.userLayers (CLI.layers cli) <> one defaultLayer
      initialModel = Model.emptyModel layers cliAct enc instanceId
  Dynamic
    <$> UM.unionMount
      (layers & Set.map (id &&& Loc.locPath))
      Pattern.filePatterns
      Pattern.ignorePatterns
      initialModel
      (mapFsChanges Patch.patchModel)

type ChangeHandler tag model m = tag -> FilePath -> UM.FileAction (NonEmpty (Loc, FilePath)) -> m (model -> model)

mapFsChanges :: (MonadIO m, MonadLogger m) => ChangeHandler tag model m -> UM.Change Loc tag -> m (model -> model)
mapFsChanges h ch = do
  uncurry (mapFsChangesOnExt h) `chainM` Map.toList ch
  where
    -- Temporarily use block buffering before calling an IO action that is
    -- known ahead to log rapidly, so as to not hamper serial processing speed.
    -- FIXME: This buffers warnings and errors (when parsing .md file) without
    -- dumping them to console. So disabling for now. But we need a proper fix.
    _withBlockBuffering f =
      (hSetBuffering stdout (BlockBuffering Nothing) >> hSetBuffering stderr LineBuffering)
        *> f
        <* (hFlush stdout >> hFlush stderr >> hSetBuffering stdout LineBuffering)

mapFsChangesOnExt ::
  (MonadIO m, MonadLogger m) =>
  ChangeHandler tag model m ->
  tag ->
  Map FilePath (UM.FileAction (NonEmpty (Loc, FilePath))) ->
  m (model -> model)
mapFsChangesOnExt h fpType fps = do
  uncurry (h fpType) `chainM` Map.toList fps

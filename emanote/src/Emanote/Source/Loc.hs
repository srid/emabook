{-# LANGUAGE DeriveAnyClass #-}

-- | Notebook location
module Emanote.Source.Loc (
  -- * Type
  Loc (..),

  -- * Making a `Loc`
  defaultLayer,
  userLayers,

  -- * Using a `Loc`
  locResolve,
  locPath,

  -- * Dealing with layers of locs
  LocLayers,
  userLayersToSearch,
) where

import Data.Set qualified as Set
import Deriving.Aeson qualified as Aeson
import Relude
import System.FilePath ((</>))

{- | Location of the notebook

 The order here matters. Top = higher precedence.
-}
data Loc
  = -- | The Int argument specifies the precedence (lower value = higher precedence)
    LocUser Int FilePath
  | -- | The default location (ie., emanote default layer)
    LocDefault FilePath
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Aeson.ToJSON)

type LocLayers = Set Loc

{- | List of user layers, highest precedent being at first.

This is useful to delay searching for content in layers.
-}
userLayersToSearch :: LocLayers -> [FilePath]
userLayersToSearch =
  mapMaybe
    ( \case
        LocUser _ fp -> Just fp
        LocDefault _ -> Nothing
    )
    . Set.toAscList

defaultLayer :: FilePath -> Loc
defaultLayer = LocDefault

userLayers :: NonEmpty FilePath -> Set Loc
userLayers paths =
  fromList
    $ zip [1 ..] (toList paths)
    <&> uncurry LocUser

-- | Return the effective path of a file.
locResolve :: (Loc, FilePath) -> FilePath
locResolve (loc, fp) = locPath loc </> fp

locPath :: Loc -> FilePath
locPath = \case
  LocUser _ fp -> fp
  LocDefault fp -> fp

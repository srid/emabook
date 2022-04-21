-- | Notebook location
module Emanote.Source.Loc
  ( -- * Type
    Loc (..),

    -- * Making a `Loc`
    defaultLayer,
    userLayers,

    -- * Using a `Loc`
    locResolve,
    locPath,

    -- * Dealing with layers of locs
    LocLayers,
    immediateLayer,
  )
where

import Data.Set qualified as Set
import Relude
import System.FilePath ((</>))

-- | Location of the notebook
--
-- The order here matters. Top = higher precedence.
data Loc
  = -- | The Int argument specifies the precedence (lower value = higher precedence)
    LocUser Int FilePath
  | -- | The default location (ie., emanote default layer)
    LocDefault FilePath
  deriving stock (Eq, Ord, Show)

type LocLayers = Set Loc

-- | Return the `Loc` with highest precedence.
immediateLayer :: HasCallStack => LocLayers -> Loc
immediateLayer = Set.findMin

defaultLayer :: FilePath -> Loc
defaultLayer = LocDefault

userLayers :: NonEmpty FilePath -> Set Loc
userLayers paths =
  fromList $
    zip [1 ..] (toList paths) <&> uncurry LocUser

-- | Return the effective path of a file.
locResolve :: (Loc, FilePath) -> FilePath
locResolve (loc, fp) = locPath loc </> fp

locPath :: Loc -> FilePath
locPath = \case
  LocUser _ fp -> fp
  LocDefault fp -> fp

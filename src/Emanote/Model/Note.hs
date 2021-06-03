{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

module Emanote.Model.Note where

import Control.Lens.Operators as Lens ((^.))
import Control.Lens.TH (makeLenses)
import qualified Data.Aeson as Aeson
import Data.IxSet.Typed (Indexable (..), IxSet, ixFun, ixList)
import qualified Data.IxSet.Typed as Ix
import Ema (Slug)
import qualified Ema.Helper.Markdown as Markdown
import qualified Emanote.Prelude as EP
import Emanote.Route (R)
import qualified Emanote.Route as R
import qualified Emanote.WikiLink as WL
import Relude.Extra.Map (StaticMap (lookup))
import Text.Pandoc.Definition (Pandoc (..))
import qualified Text.Pandoc.Definition as B

data Note = Note
  { _noteDoc :: Pandoc,
    _noteMeta :: Aeson.Value,
    -- TODO:L remove and derive from meta
    _noteTags :: [Text],
    _noteRoute :: R.LinkableLMLRoute,
    -- | Custom slug set in frontmatter if any. Overrides _noteRoute for
    -- determining the URL.
    _noteSlug :: Maybe Slug
  }
  deriving (Eq, Ord, Show, Generic, Aeson.ToJSON)

-- | All possible wiki-links that refer to this note.
noteSelfRefs :: Note -> [WL.WikiLink]
noteSelfRefs =
  WL.allowedWikiLinks
    . (R.liftLinkableRoute . R.someLinkableLMLRouteCase)
    . _noteRoute

type NoteIxs = '[R.LinkableLMLRoute, R 'R.Folder, WL.WikiLink, Text, Slug]

type IxNote = IxSet NoteIxs Note

instance Indexable NoteIxs Note where
  indices =
    ixList
      (ixFun $ one . _noteRoute)
      -- The parent folder of this note.
      (ixFun $ maybeToList . R.routeParent . R.someLinkableLMLRouteCase . _noteRoute)
      (ixFun noteSelfRefs)
      (ixFun _noteTags)
      (ixFun $ maybeToList . _noteSlug)

makeLenses ''Note

noteTitle :: Note -> Text
noteTitle note =
  fromMaybe (R.routeBaseName . R.someLinkableLMLRouteCase $ note ^. noteRoute) $
    EP.getPandocTitle $ note ^. noteDoc

noteHtmlRoute :: Note -> R 'R.Html
noteHtmlRoute note =
  -- Favour slug if one exixts, otherwise use the full path.
  case lookupAeson @(Maybe Slug) Nothing (one "slug") (note ^. noteMeta) of
    Nothing ->
      coerce $ R.someLinkableLMLRouteCase (note ^. noteRoute)
    Just slug ->
      R.mkRouteFromSlug slug

-- | Does the given folder have any notes?
hasNotes :: R 'R.Folder -> IxNote -> Bool
hasNotes r =
  not . Ix.null . Ix.getEQ r

-- | TODO: Ditch this in favour of direct indexing in html route.
lookupNote :: R 'R.Html -> IxNote -> Maybe Note
lookupNote htmlRoute ns =
  (Ix.getOne . Ix.getEQ (R.liftLinkableLMLRoute mdRoute)) ns
    <|> (mSlug >>= \slug -> (Ix.getOne . Ix.getEQ slug) ns)
  where
    mSlug :: Maybe Slug = do
      slug :| [] <- pure $ R.unRoute htmlRoute
      pure slug
    mdRoute :: R ('R.LMLType 'R.Md) =
      coerce htmlRoute

lookupNoteOrItsParent :: R 'R.Html -> IxNote -> Maybe Note
lookupNoteOrItsParent r ns =
  case lookupNote r ns of
    Just note -> pure note
    Nothing -> do
      guard $ hasNotes (coerce r) ns
      let placeHolder =
            Pandoc mempty $ one $ B.Plain $ one $ B.Str "Folder without associated .md file"
          folderMdR = R.liftLinkableLMLRoute @('R.LMLType 'R.Md) . coerce $ r
      pure $ mkEmptyNoteWith folderMdR placeHolder
  where
    mkEmptyNoteWith someR doc =
      Note doc Aeson.Null [] someR Nothing

parseNote :: MonadIO m => R.LinkableLMLRoute -> FilePath -> m (Either Text Note)
parseNote r fp = do
  !s <- readFileText fp
  pure $ do
    (mMeta, doc) <- parseMarkdown fp s
    let meta = fromMaybe Aeson.Null mMeta
        tags = lookupAeson [] (one "tags") meta
        mSlug = lookupAeson Nothing (one "slug") meta
    pure $ Note doc meta tags r mSlug
  where
    parseMarkdown =
      Markdown.parseMarkdownWithFrontMatter @Aeson.Value $
        WL.wikilinkSpec <> Markdown.fullMarkdownSpec

-- TODO: Use https://hackage.haskell.org/package/lens-aeson
lookupAeson :: forall a. Aeson.FromJSON a => a -> NonEmpty Text -> Aeson.Value -> a
lookupAeson x (k :| ks) meta =
  fromMaybe x $ do
    Aeson.Object obj <- pure meta
    val <- lookup k obj
    case nonEmpty ks of
      Nothing -> resultToMaybe $ Aeson.fromJSON val
      Just ks' -> pure $ lookupAeson x ks' val
  where
    resultToMaybe :: Aeson.Result b -> Maybe b
    resultToMaybe = \case
      Aeson.Error _ -> Nothing
      Aeson.Success b -> pure b

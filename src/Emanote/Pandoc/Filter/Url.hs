module Emanote.Pandoc.Filter.Url (urlResolvingSplice) where

import Control.Lens.Operators ((^.))
import Control.Monad.Except (throwError)
import Data.Time (UTCTime, defaultTimeLocale, formatTime)
import qualified Ema
import qualified Ema.CLI
import Emanote.Model (Model)
import qualified Emanote.Model as M
import qualified Emanote.Model.Link.Rel as Rel
import qualified Emanote.Model.Note as MN
import qualified Emanote.Model.StaticFile as SF
import qualified Emanote.Route as R
import Emanote.View.SiteRoute (SiteRoute (..))
import qualified Emanote.View.SiteRoute as SR
import qualified Heist.Extra.Splices.Pandoc as HP
import Heist.Extra.Splices.Pandoc.Ctx (ctxSansCustomSplicing)
import Heist.Extra.Splices.Pandoc.Render (plainify)
import qualified Heist.Interpreted as HI
import qualified Text.Pandoc.Definition as B

-- | Resolve all URLs in inlines (<a> and <img>)
urlResolvingSplice ::
  Monad n => Ema.CLI.Action -> Model -> HP.RenderCtx n -> B.Inline -> Maybe (HI.Splice n)
urlResolvingSplice emaAction model (ctxSansCustomSplicing -> ctx) inl =
  case inl of
    B.Link attr@(_id, _class, otherAttrs) is (url, tit) ->
      pure $ case resolveUrl emaAction model (otherAttrs <> one ("title", tit)) (is, url) of
        Left err ->
          brokenLinkSpanWrapper err inl
        Right (newIs, newUrl) ->
          HP.rpInline ctx $ B.Link attr newIs (newUrl, tit)
    B.Image attr@(id', class', otherAttrs) is' (url, tit) -> do
      let is = imageInlineFallback url is'
      pure $ case resolveUrl emaAction model (otherAttrs <> one ("title", tit)) (is, url) of
        Left err ->
          brokenLinkSpanWrapper err $
            B.Image (id', class', otherAttrs) is (url, tit)
        Right (newIs, newUrl) ->
          HP.rpInline ctx $ B.Image attr newIs (newUrl, tit)
    _ -> Nothing
  where
    -- Fallback to filename if no "alt" text is specified
    imageInlineFallback fn = \case
      [] -> one $ B.Str fn
      x -> x
    brokenLinkSpanWrapper err inline =
      HP.rpInline ctx $
        B.Span ("", one "emanote:broken-link", one ("title", err)) $
          one inline

resolveUrl :: Ema.CLI.Action -> Model -> [(Text, Text)] -> ([B.Inline], Text) -> Either Text ([B.Inline], Text)
resolveUrl emaAction model linkAttrs x@(inner, url) =
  fromMaybe (Right x) $ do
    uRel <- Rel.parseUnresolvedRelTarget linkAttrs url
    let target = resolveUnresolvedRelTarget model uRel
    pure $ second renderUrl target
  where
    renderUrl ::
      (SiteRoute, Maybe UTCTime) ->
      ([B.Inline], Text)
    renderUrl (r, mTime) =
      let isWikiLinkSansCustom = url == plainify inner
          mQuery = do
            -- In live server mode, append last modification time if any, such
            -- that the browser is forced to refresh the inline image on hot
            -- reload (Ema's DOM patch).
            guard $ emaAction == Ema.CLI.Run
            t <- mTime
            pure $ toText $ "?t=" <> formatTime defaultTimeLocale "%s" t
       in ( fromMaybe
              inner
              ( guard isWikiLinkSansCustom >> wikiLinkDefaultInnerText r
              ),
            Ema.routeUrl model r <> fromMaybe "" mQuery
          )
      where
        wikiLinkDefaultInnerText = \case
          SRLMLFile lmlR -> do
            one . B.Str . MN.noteTitle <$> M.modelLookupNoteByRoute lmlR model
          SRStaticFile _ -> do
            -- Just append a file: prefix.
            pure $ B.Str "File: " : inner
          SRIndex ->
            Nothing
          SRTagIndex ->
            Nothing
          SR404 _ ->
            Nothing

resolveUnresolvedRelTarget ::
  Model -> Rel.UnresolvedRelTarget -> Either Text (SiteRoute, Maybe UTCTime)
resolveUnresolvedRelTarget model = \case
  Right r ->
    resolveLinkableRouteMustExist r
  Left (wlType, wl) -> do
    resolveLinkableRouteMustExist <=< resolveWikiLinkMust $ wl
  where
    resolveWikiLinkMust wl =
      case nonEmpty (M.modelResolveWikiLink wl model) of
        Nothing -> do
          throwError "Wiki-link does not resolve to any known file"
        Just targets ->
          -- TODO: Deal with ambiguous targets here
          pure $ head targets
    resolveLinkableRouteMustExist r =
      case resolveLinkableRoute model r of
        Nothing -> Left "Link does not resolve to any known file"
        Just v -> Right v

resolveLinkableRoute :: Model -> R.LinkableRoute -> Maybe (SiteRoute, Maybe UTCTime)
resolveLinkableRoute model lr =
  case R.linkableRouteCase lr of
    Left lmlR -> do
      note <- M.modelLookupNoteByRoute lmlR model
      pure $
        SR.noteFileSiteRoute note
          & (,Nothing)
    Right sR -> do
      sf <- M.modelLookupStaticFileByRoute sR model
      pure $
        SR.staticFileSiteRoute sf
          & (,Just $ sf ^. SF.staticFileTime)

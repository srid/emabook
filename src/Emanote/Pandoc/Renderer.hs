{-# LANGUAGE RecordWildCards #-}

-- | Types for custom render extensions to Pandoc AST nodes.
--
-- Note that unlike Pandoc *filters* (which operate on entire document), these
-- are modeled based on Text.Pandoc.Walk, ie. fine-grained on individual inline
-- and block processing. We do this only so as to render a specific node during
-- recursion (cf. `rpBlock` and `rpInline` in Render.hs).
--
-- So we expect the extensions to be in Haskell, however external script may be
-- supported using a traditional whole-AST extension API.
module Emanote.Pandoc.Renderer
  ( PandocRenderers (PandocRenderers),
    PandocInlineRenderer,
    PandocBlockRenderer,
    mkRenderCtxWithPandocRenderers,
    EmanotePandocRenderers (..),
  )
where

import Heist (HeistT)
import Heist.Extra.Splices.Pandoc qualified as Splices
import Heist.Extra.Splices.Pandoc.Ctx qualified as Splices
import Heist.Interpreted qualified as HI
import Relude
import Text.Pandoc.Definition qualified as B

-- | Custom Heist renderer function for specific Pandoc AST nodes
type PandocRenderF model route astNode n =
  model ->
  PandocRenderers model route n ->
  Splices.RenderCtx n ->
  route ->
  astNode ->
  Maybe (HI.Splice n)

type PandocInlineRenderer model route n = PandocRenderF model route B.Inline n

type PandocBlockRenderer model route n = PandocRenderF model route B.Block n

data PandocRenderers model route n = PandocRenderers
  { pandocInlineRenderers :: [PandocInlineRenderer model route n],
    pandocBlockRenderers :: [PandocBlockRenderer model route n]
  }

mkRenderCtxWithPandocRenderers ::
  forall model route m n.
  (Monad m, Monad n) =>
  PandocRenderers model route n ->
  Map Text Text ->
  model ->
  route ->
  HeistT n m (Splices.RenderCtx n)
mkRenderCtxWithPandocRenderers nr@PandocRenderers {..} classRules model x =
  Splices.mkRenderCtx
    classRules
    ( \ctx blk ->
        asum $
          pandocBlockRenderers <&> \f ->
            f model nr ctx x blk
    )
    ( \ctx blk ->
        asum $
          pandocInlineRenderers <&> \f ->
            f model nr ctx x blk
    )

data EmanotePandocRenderers a r = EmanotePandocRenderers
  { blockRenderers :: PandocRenderers a r Identity,
    -- | Like `blockRenderers` but for use in inline contexts.
    --
    -- Backlinks and titles constitute an example of inline context, where we don't
    -- care about block elements.
    inlineRenderers :: PandocRenderers a r Identity,
    -- | Like `inlineRenderers` but suitable for use inside links (<a> tags).
    linkInlineRenderers :: PandocRenderers a r Identity
  }

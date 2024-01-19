# Revision history for emanote

## Unreleased

- Features
  - Obsidian-style callouts ([\#466](https://github.com/srid/emanote/pull/466))
  - `emanote run --no-ws` option to disable WebSocket monitoring. This is useful for using Emanote to serve the HTML site directly on the internet, without needing to statically generate it.
  - Add query syntax for listing folgezetten children & parents ([\#476](https://github.com/srid/emanote/pull/476))
  - **BACKWARDS INCOMPATIBLE** A new HTML template layout "default" (unifies and) replaces both "book" and "note" layout. ([\#483](https://github.com/srid/emanote/pull/483))
    - Sidebar tree is now computed from the folgezettel graph, which is a superset of the folder hierarchy. The index page's tree inherits the same.
    - The semantics of `folder-folgezettel` is now applied in inverse (see docs)
  - Allow specifying custom page title in sidebar ([\#488](https://github.com/srid/emanote/pull/488))
  - Allow specifying `lang` attribute for HTML page in YAML config ([\#485](https://github.com/srid/emanote/pull/485))
  - KaTeX support ([\#489](https://github.com/srid/emanote/pull/489))
  - Lua filters: filter paths will now be looked up in all layers now.
  - **BACKWARDS INCOMPTABILE**: `feed.siteUrl` is now `page.siteUrl`
- Bug fixes:
  - Emanote no longer crashes when run on an empty directory ([\#487](https://github.com/srid/emanote/issues/487))
  - Stork search fixes
    - Fix empty stork index generation when using more than 1 layer ([\#493](https://github.com/srid/emanote/issues/493))
    - Stork search index is now uses note path from their associated layer ([\#495](https://github.com/srid/emanote/pull/495))

## 1.2.0.0 (2023-08-24)

- Bug fixes
  - Make Stork recognize orgmode notes ([\#413](https://github.com/srid/emanote/issues/413))
- Features
  - Audio embedding ([\#418](https://github.com/srid/emanote/pull/418))
  - Source code embedding ([\#444](https://github.com/srid/emanote/pull/444))
  - Atom feed ([\#451](https://github.com/srid/emanote/pull/451))
  - Add option to show folders first in the sidebar [\#399](https://github.com/srid/emanote/pull/399)
- UI
  - Remove inline styling of H2 elements
- Misc
  - Update Ema to simplify the live server websocket observation logic
  - Use GHC 9.4 & Pandoc 3

## 1.0.2.0 (2023-01-29)

- Nix
  - Reduce Emanote's Nix runtime closure size
- UI
  - Add source map for Stork [\#391](https://github.com/srid/emanote/pull/391)
  - Workaround for Prism.js and Tailwind CSS both using `table` class [\#320](https://github.com/srid/emanote/pull/396)
  - Add option to include YAML frontmatter in the Stork index [\#398](https://github.com/srid/emanote/pull/398)
- Features
  - Timeline backlinks recognize flexible daily notes suffixed with arbitrary string [\#395](https://github.com/srid/emanote/issues/395)
- Performance
  - Address client-side memory leak due to Stork search in live server [\#411](https://github.com/srid/emanote/issues/411#issuecomment-1402056235)
- Misc
  - Ignore toplevel `flake.{nix,lock}` by default.
  - Remove deprecated `_emanote-bin/compile-css` script

## 1.0.0.0 (2022-12-04)

- UI
  - Index pages are no longer marked as 'experimental'
  - Add external link icon to external links (this behaviour is customizable). [\#189](https://github.com/srid/emanote/pull/189)
  - `js.mermaid` snippet uses the "module" script tag approach, which is added to end of `<body>`. See [here](https://mermaid-js.github.io/mermaid/#/n00b-gettingStarted?id=_3-calling-the-javascript-api). 
  - Align dates in timeline queries
- Configuration
  - Add `page.bodyHtml` option to inject custom HTML at the end of `<body>` tag.
- Packaging
  - Move tests to their own cabal component (thereby, also, unexpose them from library exposed modules)
  - Wikilink parser is now a separate library: https://github.com/srid/commonmark-wikilink
  - Use `heist-extra` 0.2.0.0 which switches over from `heist-emanote` to using official `heist` package.
- Bug fixes
  - #380 & #386: Better handling of `.org` and `.md` ambiguties. Default layer's `index.md` has been removed.

## 0.8.0.0 (2022-11-03)

Initial release.

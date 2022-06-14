module Emanote.Route.SiteRoute
  ( SiteRoute (..),
    VirtualRoute (..),
    ResourceRoute (..),
    decodeVirtualRoute,
    noteFileSiteRoute,
    staticFileSiteRoute,
    lmlSiteRoute,
    siteRouteUrl,
    siteRouteUrlStatic,
  )
where

import Emanote.Route.SiteRoute.Class
import Emanote.Route.SiteRoute.Type

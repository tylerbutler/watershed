import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed_site/error.{type BuildError, DuplicateRoute}

pub type Route {
  Route(
    path: String,
    layout: Layout,
    content_path: String,
    client_script: Option(String),
    analytics: Analytics,
  )
}

pub type Layout {
  Guide
  GuideIndex
}

pub type Analytics {
  NoAnalytics
  Tinylytics
}

pub fn guide_race() -> Route {
  Route(
    path: "/guide/race",
    layout: Guide,
    content_path: "content/guide/race.djot",
    client_script: Some("/guide_race.js"),
    analytics: Tinylytics,
  )
}

pub fn all() -> List(Route) {
  [
    Route(
      path: "/guide",
      layout: GuideIndex,
      content_path: "content/guide/index.djot",
      client_script: None,
      analytics: Tinylytics,
    ),
    guide_race(),
  ]
}

pub fn stylesheets(route: Route) -> List(String) {
  case route.layout {
    Guide -> ["/styles/site.css", "/styles/guide-race.css"]
    GuideIndex -> ["/styles/site.css", "/styles/guide-index.css"]
  }
}

pub fn validate(routes: List(Route)) -> Result(List(Route), BuildError) {
  use _ <- result.try(
    list.try_fold(routes, dict.new(), fn(seen, route) {
      case dict.get(seen, route.path) {
        Ok(first) ->
          Error(DuplicateRoute(route.path, first, route.content_path))
        Error(Nil) -> Ok(dict.insert(seen, route.path, route.content_path))
      }
    }),
  )
  Ok(routes)
}

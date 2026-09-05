import gleam/list
import gleam/option.{Some}
import gleeunit/should
import watershed_site/error
import watershed_site/route

pub fn pilot_route_is_registered_test() {
  route.all()
  |> list.filter(fn(route) { route.path == "/guide/race" })
  |> should.equal([
    route.Route(
      path: "/guide/race",
      layout: route.Guide,
      content_path: "content/guide/race.djot",
      client_script: Some("/guide_race.js"),
      analytics: route.Tinylytics,
    ),
  ])
}

pub fn duplicate_paths_report_both_sources_test() {
  let first = route.guide_race()
  let second = route.Route(..first, content_path: "other.djot")
  route.validate([first, second])
  |> should.equal(
    Error(error.DuplicateRoute(
      "/guide/race",
      "content/guide/race.djot",
      "other.djot",
    )),
  )
}

pub fn unique_routes_are_preserved_test() {
  let first = route.guide_race()
  let second = route.Route(..first, path: "/guide/notes")
  route.validate([first, second])
  |> should.equal(Ok([first, second]))
}

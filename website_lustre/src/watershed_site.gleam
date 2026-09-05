import gleam/list
import gleam/option
import gleam/result
import gleam/string
import lustre/ssg
import simplifile
import watershed_site/content
import watershed_site/error.{type BuildError}
import watershed_site/page
import watershed_site/route
import watershed_site/snippet

pub fn build(
  out_dir: String,
  static_dir: String,
  snippet_manifest: String,
  revision: String,
) -> Result(Nil, BuildError) {
  build_routes(route.all(), out_dir, static_dir, snippet_manifest, revision)
}

pub fn build_routes(
  routes: List(route.Route),
  out_dir: String,
  static_dir: String,
  snippet_manifest: String,
  revision: String,
) -> Result(Nil, BuildError) {
  use routes <- result.try(route.validate(routes))
  use manifest <- result.try(snippet.load(snippet_manifest))
  use pages <- result.try(
    list.try_map(routes, fn(route) {
      use source <- result.try(content.load(route))
      use rendered <- result.try(page.render(source, route, manifest, revision))
      Ok(#(route.path, rendered))
    }),
  )
  let assets =
    list.append(
      ["/styles/site.css", "/styles/guide-race.css", "/favicon.svg", "/og.png"],
      list.filter_map(routes, fn(route) {
        option.to_result(route.client_script, Nil)
      }),
    )
  use _ <- result.try(
    list.try_each(assets, fn(asset) {
      let path = static_dir <> asset
      case simplifile.is_file(path) {
        Ok(True) -> Ok(Nil)
        Ok(False) ->
          Error(error.CannotRead(
            path,
            "The required asset for " <> out_dir <> " is missing.",
          ))
        Error(reason) -> Error(error.CannotRead(path, string.inspect(reason)))
      }
    }),
  )
  case pages {
    [] ->
      Error(error.InvalidContent(
        "route registry",
        "At least one route is required.",
      ))
    [#(path, page), ..rest] -> {
      let config =
        ssg.new(out_dir)
        |> ssg.add_static_dir(static_dir)
        |> ssg.use_index_routes
        |> ssg.add_static_route(path, page)
      list.fold(rest, config, fn(config, entry) {
        ssg.add_static_route(config, entry.0, entry.1)
      })
      |> ssg.build
      |> result.map_error(fn(reason) {
        error.SiteGenerationFailed(string.inspect(reason))
      })
    }
  }
}

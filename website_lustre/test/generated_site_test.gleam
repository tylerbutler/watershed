import gleam/list
import gleam/string
import gleeunit/should
import simplifile
import support
import watershed_site
import watershed_site/route

const output = ".cache/generated-site-test"

const manifest = "src/generated/snippets.json"

pub fn generated_route_and_assets_test() {
  let assert Ok(_) = simplifile.create_directory_all(".cache")
  watershed_site.build(output, "build/static", manifest, "fixture-revision")
  |> should.be_ok()

  let assert Ok(html) = simplifile.read(output <> "/guide/race/index.html")
  [
    "Try two edits at once",
    "id=\"guide-race-mount\"",
    "src=\"/guide_race.js\"",
    "tinylytics.app",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  ["astro-island", "/_astro/", "@vite"]
  |> list.each(fn(absent) {
    let assert False = string.contains(html, absent) as absent
  })
  [
    "guide_race.js",
    "scripts/motion.js",
    "scripts/guide-index.js",
    "scripts/concept-index.js",
    "styles/site.css",
    "styles/guide-race.css",
    "fonts/archivo/wdth.css",
    "favicon.svg",
    "og.png",
  ]
  |> list.each(fn(path) {
    let assert Ok(_) = simplifile.read_bits(output <> "/" <> path) as path
  })
  simplifile.read(output <> "/_redirects")
  |> should.equal(Ok(
    "/foundations/components /component-model/components 301\n"
    <> "/foundations/ports /component-model/ports 301\n"
    <> "/foundations/workspaces /component-model/workspaces 301\n",
  ))

  let invalid =
    route.Route(
      ..support.route("/guide/race"),
      content_path: "test/fixtures/raw-html.djot",
    )
  watershed_site.build_routes(
    [invalid],
    output,
    "build/static",
    manifest,
    "fixture-revision",
  )
  |> should.be_error()
  simplifile.read(output <> "/guide/race/index.html") |> should.equal(Ok(html))
  let assert Ok(_) = simplifile.delete(output)
}

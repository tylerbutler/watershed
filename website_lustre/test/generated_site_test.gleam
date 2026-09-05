import gleam/list
import gleam/string
import gleeunit/should
import html_parser
import simplifile
import watershed_site
import watershed_site/route

const output = ".cache/generated-site-test"

const manifest = "../website/src/generated/snippets.json"

pub fn generated_route_and_assets_test() {
  let assert Ok(_) = simplifile.create_directory_all(".cache")
  watershed_site.build(output, "build/static", manifest, "fixture-revision")
  |> should.be_ok()
  let assert Ok(index) = simplifile.read(output <> "/guide/index.html")
  string.contains(index, "The survey procedure") |> should.be_true()
  string.contains(index, "/guide_race.js") |> should.be_false()
  let assert Ok(motion) = simplifile.read("../website/src/scripts/motion.js")
  simplifile.read(output <> "/scripts/guide-index.js")
  |> should.equal(Ok(motion <> "\ninitReveals();\n"))
  let assert Ok(html) = simplifile.read(output <> "/guide/race/index.html")
  let tree = html_parser.as_tree(html)
  find(tree, "id", "guide-race-demo") |> list.length |> should.equal(1)
  find(tree, "id", "guide-race-mount") |> list.length |> should.equal(1)
  find(tree, "src", "/guide_race.js")
  |> list.length
  |> should.equal(1)
  find(tree, "href", "/guide/notes") |> list.is_empty |> should.be_false()
  [
    "ship week went smoothly",
    "The live race needs JavaScript",
    "Try two edits at once",
  ]
  |> list.each(fn(text) {
    let assert True = string.contains(html, text) as text
  })
  ["astro-island", "/_astro/", "@vite", "data-component"]
  |> list.each(fn(text) { string.contains(html, text) |> should.be_false() })
  [
    "guide_race.js",
    "styles/site.css",
    "styles/guide-race.css",
    "styles/guide-index.css",
    "fonts/archivo/wdth.css",
    "favicon.svg",
    "og.png",
  ]
  |> list.each(fn(path) {
    let assert Ok(_) = simplifile.read_bits(output <> "/" <> path) as path
  })
  let invalid =
    route.Route(
      ..route.guide_race(),
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

fn find(
  tree: html_parser.Element,
  key: String,
  value: String,
) -> List(html_parser.Element) {
  case tree {
    html_parser.StartElement(_, attributes, children) -> {
      let matches = case
        list.contains(attributes, html_parser.Attribute(key, value))
      {
        True -> [tree]
        False -> []
      }
      list.append(matches, list.flat_map(children, find(_, key, value)))
    }
    _ -> []
  }
}

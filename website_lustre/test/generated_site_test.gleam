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
  simplifile.read(output <> "/scripts/concept-index.js")
  |> should.equal(Ok(motion <> "\ninitReveals();\n"))
  let assert Ok(component_model_html) =
    simplifile.read(output <> "/component-model/index.html")
  let component_model_tree = html_parser.as_tree(component_model_html)
  let assert False =
    find(component_model_tree, "href", "/component-model/components")
    |> list.is_empty
    as "component model entry"
  find(component_model_tree, "src", "/scripts/concept-index.js")
  |> list.length
  |> should.equal(1)
  let assert Ok(foundations_html) =
    simplifile.read(output <> "/foundations/index.html")
  let foundations_tree = html_parser.as_tree(foundations_html)
  let assert False =
    find(foundations_tree, "href", "/foundations/schema")
    |> list.is_empty
    as "foundations schema link"
  find(foundations_tree, "src", "/scripts/concept-index.js")
  |> list.length
  |> should.equal(1)
  let assert Ok(schema_html) =
    simplifile.read(output <> "/foundations/schema/index.html")
  let schema_tree = html_parser.as_tree(schema_html)
  let assert False =
    find(schema_tree, "href", "/foundations/topology")
    |> list.is_empty
    as "schema next link"
  let assert False =
    find(schema_tree, "href", "/guide/notes#stamp-schema")
    |> list.is_empty
    as "schema related note link"
  let assert Ok(topology_html) =
    simplifile.read(output <> "/foundations/topology/index.html")
  string.contains(
    topology_html,
    "examples/scoreboard_cli/src/scoreboard_cli.gleam (diagram)",
  )
  |> should.be_true()
  let assert Ok(lifecycle_html) =
    simplifile.read(output <> "/foundations/lifecycle/index.html")
  string.contains(
    lifecycle_html,
    "class=\"fd-pager-cell fd-pager-next\" href=\"/guide\"",
  )
  |> should.be_true()
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
  let assert Ok(connect_html) =
    simplifile.read(output <> "/guide/connect/index.html")
  let connect_tree = html_parser.as_tree(connect_html)
  [
    "ffi-surface",
    "claims-seeding",
    "shared-core-two-runtimes",
  ]
  |> list.each(fn(id) {
    find(connect_tree, "id", id) |> list.length |> should.equal(1)
  })
  find(connect_tree, "src", "/scripts/field-notes.js")
  |> list.length
  |> should.equal(1)
  find(connect_tree, "src", "/guide_race.js")
  |> list.is_empty
  |> should.be_true()
  find(connect_tree, "href", "/guide")
  |> list.is_empty
  |> should.be_false()
  find(connect_tree, "href", "/guide/race")
  |> list.is_empty
  |> should.be_false()
  [
    "examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam",
    "examples/retro_tutorial_lustre/gleam.toml",
    "document_on_navigate reads ?document= from the URL",
    "watershed_beam · for comparison only, the tutorial stays in the browser",
  ]
  |> list.each(fn(text) {
    string.contains(connect_html, text) |> should.be_true()
  })
  let assert Ok(notes_html) =
    simplifile.read(output <> "/guide/notes/index.html")
  let notes_tree = html_parser.as_tree(notes_html)
  [
    "fallible-edits",
    "authoritative-channel",
    "stamp-schema",
    "anchors-not-offsets",
  ]
  |> list.each(fn(id) {
    find(notes_tree, "id", id) |> list.length |> should.equal(1)
  })
  find(notes_tree, "src", "/scripts/field-notes.js")
  |> list.length
  |> should.equal(1)
  find(notes_tree, "src", "/guide_race.js")
  |> list.is_empty
  |> should.be_true()
  find(notes_tree, "href", "/guide/connect")
  |> list.is_empty
  |> should.be_false()
  find(notes_tree, "href", "/guide/race")
  |> list.is_empty
  |> should.be_false()
  [
    "Each note gets its own id",
    "examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam",
    "examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam",
  ]
  |> list.each(fn(text) {
    string.contains(notes_html, text) |> should.be_true()
  })
  let assert Ok(votes_html) =
    simplifile.read(output <> "/guide/votes/index.html")
  let votes_tree = html_parser.as_tree(votes_html)
  ["quorum-pending-roster", "unsettled-writes"]
  |> list.each(fn(id) {
    find(votes_tree, "id", id) |> list.length |> should.equal(1)
  })
  find(votes_tree, "src", "/scripts/field-notes.js")
  |> list.length
  |> should.equal(1)
  find(votes_tree, "src", "/guide_race.js")
  |> list.is_empty
  |> should.be_true()
  find(votes_tree, "href", "/guide/race")
  |> list.is_empty
  |> should.be_false()
  find(votes_tree, "href", "/guide/presence")
  |> list.is_empty
  |> should.be_false()
  [
    "(illustrative — not in the tutorial source)",
    "the tally for a note that isn&#39;t there renders nowhere and breaks nothing",
    "Deepening: what a tally deliberately can&#39;t do",
  ]
  |> list.each(fn(text) {
    string.contains(votes_html, text) |> should.be_true()
  })
  let assert Ok(presence_html) =
    simplifile.read(output <> "/guide/presence/index.html")
  let presence_tree = html_parser.as_tree(presence_html)
  ["realtime-out-of-band", "presence-idiom", "protocol-on-ripples"]
  |> list.each(fn(id) {
    find(presence_tree, "id", id) |> list.length |> should.equal(1)
  })
  find(presence_tree, "src", "/scripts/field-notes.js")
  |> list.length
  |> should.equal(1)
  find(presence_tree, "src", "/guide_race.js")
  |> list.is_empty
  |> should.be_true()
  find(presence_tree, "href", "/guide/votes")
  |> list.is_empty
  |> should.be_false()
  find(presence_tree, "href", "/guide/testing")
  |> list.is_empty
  |> should.be_false()
  [
    "Some facts should be allowed to expire",
    "The roster arrives as events, including the bad ones",
    "Deepening: one highlight, built from two systems",
  ]
  |> list.each(fn(text) {
    string.contains(presence_html, text) |> should.be_true()
  })
  let assert Ok(testing_html) =
    simplifile.read(output <> "/guide/testing/index.html")
  let testing_tree = html_parser.as_tree(testing_html)
  ["pure-modules", "deterministic-death"]
  |> list.each(fn(id) {
    find(testing_tree, "id", id) |> list.length |> should.equal(1)
  })
  find(testing_tree, "src", "/scripts/field-notes.js")
  |> list.length
  |> should.equal(1)
  find(testing_tree, "src", "/guide_race.js")
  |> list.is_empty
  |> should.be_true()
  find(testing_tree, "href", "/guide/presence")
  |> list.is_empty
  |> should.be_false()
  find(testing_tree, "href", "/examples#retro_board_lustre")
  |> list.is_empty
  |> should.be_false()
  [
    "(illustrative — scripted delivery)",
    "examples/retro_tutorial_lustre/",
    "Where to go when this board gets too small",
  ]
  |> list.each(fn(text) {
    string.contains(testing_html, text) |> should.be_true()
  })
  [
    "guide_race.js",
    "styles/site.css",
    "styles/guide-race.css",
    "styles/guide-index.css",
    "styles/concept-index.css",
    "styles/concept-sheet.css",
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

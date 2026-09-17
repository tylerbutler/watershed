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
  let assert Ok(structures_html) =
    simplifile.read(output <> "/structures/index.html")
  let structures_tree = html_parser.as_tree(structures_html)
  find(structures_tree, "class", "family")
  |> list.length
  |> should.equal(7)
  find(structures_tree, "src", "/scripts/concept-index.js")
  |> list.length
  |> should.equal(1)
  let assert Ok(maps_html) =
    simplifile.read(output <> "/structures/maps/index.html")
  let maps_tree = html_parser.as_tree(maps_html)
  find(maps_tree, "id", "map") |> list.length |> should.equal(1)
  find(maps_tree, "id", "lww-map") |> list.length |> should.equal(1)
  find(maps_tree, "id", "ormap") |> list.length |> should.equal(1)
  find(maps_tree, "id", "directory") |> list.length |> should.equal(1)
  find(maps_tree, "src", "/guide_race.js")
  |> list.is_empty
  |> should.be_true()
  let assert Ok(models_html) = simplifile.read(output <> "/models/index.html")
  string.contains(models_html, "Conflict-free Replicated Data Type")
  |> should.be_true()
  string.contains(models_html, "href=\"/structures/maps#map\"")
  |> should.be_true()
  let assert Ok(patterns_html) =
    simplifile.read(output <> "/patterns/index.html")
  let patterns_tree = html_parser.as_tree(patterns_html)
  find(patterns_tree, "class", "p-step")
  |> list.length
  |> should.equal(4)
  find(patterns_tree, "class", "p-rule-link")
  |> list.length
  |> should.equal(17)
  find(patterns_tree, "src", "/guide_race.js")
  |> list.is_empty
  |> should.be_true()
  simplifile.read(output <> "/styles/patterns.css")
  |> should.be_ok()
  let assert Ok(examples_html) =
    simplifile.read(output <> "/examples/index.html")
  let examples_tree = html_parser.as_tree(examples_html)
  find(examples_tree, "class", "e-group")
  |> list.length
  |> should.equal(4)
  find(examples_tree, "class", "e-entry")
  |> list.length
  |> should.equal(14)
  find(examples_tree, "href", "/structures/maps#map")
  |> list.is_empty
  |> should.be_false()
  simplifile.read(output <> "/styles/examples.css")
  |> should.be_ok()
  let assert Ok(sharedtree_html) =
    simplifile.read(output <> "/sharedtree/index.html")
  let sharedtree_tree = html_parser.as_tree(sharedtree_html)
  find(sharedtree_tree, "class", "g-code")
  |> list.length
  |> should.equal(14)
  find(sharedtree_tree, "scope", "row")
  |> list.length
  |> should.equal(13)
  find(sharedtree_tree, "id", "gaps")
  |> list.length
  |> should.equal(1)
  find(sharedtree_tree, "src", "/scripts/concept-index.js")
  |> list.length
  |> should.equal(1)
  simplifile.read(output <> "/styles/sharedtree.css")
  |> should.be_ok()
  let assert Ok(sudoku_html) = simplifile.read(output <> "/sudoku/index.html")
  let sudoku_tree = html_parser.as_tree(sudoku_html)
  let assert 1 = find(sudoku_tree, "id", "sudoku-mount") |> list.length
    as "Sudoku mount"
  let assert 1 = find(sudoku_tree, "data-testid", "client-a") |> list.length
    as "Sudoku client"
  let assert 1 = find(sudoku_tree, "src", "/sudoku.js") |> list.length
    as "Sudoku client script"
  let assert 1 =
    find(sudoku_tree, "src", "/scripts/concept-index.js") |> list.length
    as "Sudoku reveal script"
  [
    "SharedMap sudoku cells, live",
    "Race the same cell",
    "The live demo needs JavaScript",
  ]
  |> list.each(fn(text) {
    string.contains(sudoku_html, text) |> should.be_true()
  })
  simplifile.read(output <> "/styles/sudoku.css")
  |> should.be_ok()
  simplifile.read(output <> "/_redirects")
  |> should.equal(Ok(
    "/foundations/components /component-model/components 301\n"
    <> "/foundations/ports /component-model/ports 301\n"
    <> "/foundations/workspaces /component-model/workspaces 301\n",
  ))
  let assert Ok(runtime_html) = simplifile.read(output <> "/runtime/index.html")
  let runtime_tree = html_parser.as_tree(runtime_html)
  let assert False =
    find(runtime_tree, "href", "/runtime/optimistic")
    |> list.is_empty
    as "runtime entry"
  find(runtime_tree, "src", "/scripts/concept-index.js")
  |> list.length
  |> should.equal(1)
  let assert Ok(optimistic_html) =
    simplifile.read(output <> "/runtime/optimistic/index.html")
  string.contains(optimistic_html, "href=\"/runtime/reconnect\"")
  |> should.be_true()
  string.contains(
    optimistic_html,
    "tools/website-samples/src/website_samples/optimistic_sample.gleam",
  )
  |> should.be_true()
  let assert Ok(reconnect_html) =
    simplifile.read(output <> "/runtime/reconnect/index.html")
  string.contains(reconnect_html, "href=\"/runtime/optimistic\"")
  |> should.be_true()
  string.contains(reconnect_html, "href=\"/runtime/redelivery\"")
  |> should.be_true()
  let assert Ok(redelivery_html) =
    simplifile.read(output <> "/runtime/redelivery/index.html")
  string.contains(
    redelivery_html,
    "aria-label=\"Op-log excerpt: a duplicate delta absorbed\"",
  )
  |> should.be_true()
  string.contains(redelivery_html, "href=\"/runtime/presence\"")
  |> should.be_true()
  let assert Ok(presence_html) =
    simplifile.read(output <> "/runtime/presence/index.html")
  string.contains(presence_html, "(illustrative — presence configuration)")
  |> should.be_true()
  string.contains(presence_html, "href=\"/runtime/p2p\"")
  |> should.be_true()
  let assert Ok(p2p_html) = simplifile.read(output <> "/runtime/p2p/index.html")
  string.contains(
    p2p_html,
    "tools/website-samples/src/website_samples/p2p_sample.gleam",
  )
  |> should.be_true()
  string.contains(p2p_html, "href=\"/guide\"")
  |> should.be_true()
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
  let assert Ok(components_html) =
    simplifile.read(output <> "/component-model/components/index.html")
  string.contains(components_html, "/component-model/ports")
  |> should.be_true()
  let assert Ok(ports_html) =
    simplifile.read(output <> "/component-model/ports/index.html")
  string.contains(ports_html, "component port flow")
  |> should.be_true()
  let assert Ok(workspaces_html) =
    simplifile.read(output <> "/component-model/workspaces/index.html")
  string.contains(workspaces_html, "src/watershed/workspace.gleam")
  |> should.be_true()
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
    "styles/structures-index.css",
    "styles/structure-sheet.css",
    "styles/models.css",
    "styles/sudoku.css",
    "sudoku.js",
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

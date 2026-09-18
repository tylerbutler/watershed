import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import support
import watershed_site/error
import watershed_site/route

pub fn registry_matches_expected_routes_test() {
  let expected = [
    #("/", route.Home, "content/home.djot", Some("/home.js"), [
      "/styles/site.css",
      "/styles/home.css",
    ]),
    #(
      "/foundations",
      route.ConceptIndex,
      "content/foundations/index.djot",
      None,
      ["/styles/site.css", "/styles/concept-index.css"],
    ),
    #(
      "/foundations/schema",
      route.ConceptSheet,
      "content/foundations/schema.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #(
      "/foundations/topology",
      route.ConceptSheet,
      "content/foundations/topology.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #(
      "/foundations/lifecycle",
      route.ConceptSheet,
      "content/foundations/lifecycle.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #(
      "/component-model",
      route.ConceptIndex,
      "content/component-model/index.djot",
      None,
      ["/styles/site.css", "/styles/concept-index.css"],
    ),
    #(
      "/component-model/components",
      route.ConceptSheet,
      "content/component-model/components.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #(
      "/component-model/ports",
      route.ConceptSheet,
      "content/component-model/ports.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #(
      "/component-model/workspaces",
      route.ConceptSheet,
      "content/component-model/workspaces.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #("/runtime", route.ConceptIndex, "content/runtime/index.djot", None, [
      "/styles/site.css",
      "/styles/concept-index.css",
    ]),
    #(
      "/runtime/optimistic",
      route.ConceptSheet,
      "content/runtime/optimistic.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #(
      "/runtime/reconnect",
      route.ConceptSheet,
      "content/runtime/reconnect.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #(
      "/runtime/redelivery",
      route.ConceptSheet,
      "content/runtime/redelivery.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #(
      "/runtime/presence",
      route.ConceptSheet,
      "content/runtime/presence.djot",
      None,
      ["/styles/site.css", "/styles/concept-sheet.css"],
    ),
    #("/runtime/p2p", route.ConceptSheet, "content/runtime/p2p.djot", None, [
      "/styles/site.css",
      "/styles/concept-sheet.css",
    ]),
    #(
      "/structures",
      route.StructureIndex,
      "content/structures/index.djot",
      None,
      ["/styles/site.css", "/styles/structures-index.css"],
    ),
    #(
      "/structures/counters",
      route.StructureSheet,
      "content/structures/counters.djot",
      None,
      ["/styles/site.css", "/styles/structure-sheet.css"],
    ),
    #(
      "/structures/sets",
      route.StructureSheet,
      "content/structures/sets.djot",
      None,
      ["/styles/site.css", "/styles/structure-sheet.css"],
    ),
    #(
      "/structures/registers",
      route.StructureSheet,
      "content/structures/registers.djot",
      None,
      ["/styles/site.css", "/styles/structure-sheet.css"],
    ),
    #(
      "/structures/maps",
      route.StructureSheet,
      "content/structures/maps.djot",
      None,
      ["/styles/site.css", "/styles/structure-sheet.css"],
    ),
    #(
      "/structures/sequences",
      route.StructureSheet,
      "content/structures/sequences.djot",
      None,
      ["/styles/site.css", "/styles/structure-sheet.css"],
    ),
    #(
      "/structures/coordination",
      route.StructureSheet,
      "content/structures/coordination.djot",
      None,
      ["/styles/site.css", "/styles/structure-sheet.css"],
    ),
    #(
      "/structures/transforms",
      route.StructureSheet,
      "content/structures/transforms.djot",
      None,
      ["/styles/site.css", "/styles/structure-sheet.css"],
    ),
    #("/models", route.Models, "content/models.djot", None, [
      "/styles/site.css",
      "/styles/models.css",
    ]),
    #("/patterns", route.Patterns, "content/patterns.djot", None, [
      "/styles/site.css",
      "/styles/patterns.css",
    ]),
    #("/examples", route.Examples, "content/examples.djot", None, [
      "/styles/site.css",
      "/styles/examples.css",
    ]),
    #("/sharedtree", route.SharedTree, "content/sharedtree.djot", None, [
      "/styles/site.css",
      "/styles/sharedtree.css",
    ]),
    #("/sudoku", route.Sudoku, "content/sudoku.djot", Some("/sudoku.js"), [
      "/styles/site.css",
      "/styles/sudoku.css",
    ]),
    #(
      "/directory",
      route.Directory,
      "content/directory.djot",
      Some("/directory.js"),
      ["/styles/site.css", "/styles/directory.css"],
    ),
    #(
      "/counter-bug",
      route.CounterBug,
      "content/counter-bug.djot",
      Some("/counter_bug.js"),
      ["/styles/site.css", "/styles/counter-bug.css"],
    ),
    #("/json-ot", route.JsonOt, "content/json-ot.djot", Some("/json_ot.js"), [
      "/styles/site.css",
      "/styles/json-ot.css",
    ]),
    #(
      "/mv-register",
      route.MvRegister,
      "content/mv-register.djot",
      Some("/mv_register.js"),
      ["/styles/site.css", "/styles/mv-register.css"],
    ),
    #(
      "/rich-text",
      route.RichText,
      "content/rich-text.djot",
      Some("/rich_text.js"),
      ["/styles/site.css", "/rich_text.css", "/styles/rich-text.css"],
    ),
    #(
      "/sequence",
      route.Sequence,
      "content/sequence.djot",
      Some("/sequence.js"),
      ["/styles/site.css", "/styles/sequence.css"],
    ),
    #("/text", route.Text, "content/text.djot", Some("/text.js"), [
      "/styles/site.css",
      "/styles/text.css",
    ]),
    #("/guide", route.GuideIndex, "content/guide/index.djot", None, [
      "/styles/site.css",
      "/styles/guide-index.css",
    ]),
    #("/guide/connect", route.Guide, "content/guide/connect.djot", None, [
      "/styles/site.css",
    ]),
    #("/guide/notes", route.Guide, "content/guide/notes.djot", None, [
      "/styles/site.css",
    ]),
    #(
      "/guide/race",
      route.Guide,
      "content/guide/race.djot",
      Some("/guide_race.js"),
      ["/styles/site.css", "/styles/guide-race.css"],
    ),
    #("/guide/votes", route.Guide, "content/guide/votes.djot", None, [
      "/styles/site.css",
    ]),
    #("/guide/presence", route.Guide, "content/guide/presence.djot", None, [
      "/styles/site.css",
    ]),
    #("/guide/testing", route.Guide, "content/guide/testing.djot", None, [
      "/styles/site.css",
    ]),
  ]
  route.all()
  |> list.map(fn(item) {
    #(
      item.path,
      item.layout,
      item.content_path,
      item.client_script,
      route.stylesheets(item),
    )
  })
  |> should.equal(expected)
}

pub fn routes_are_found_by_path_test() {
  route.find("/guide/race") |> should.equal(Ok(support.route("/guide/race")))
  route.find("/missing") |> should.equal(Error(Nil))
}

pub fn duplicate_paths_report_both_sources_test() {
  let first = support.route("/guide/race")
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
  let first = support.route("/guide/race")
  let second = route.Route(..first, path: "/guide/other")
  route.validate([first, second])
  |> should.equal(Ok([first, second]))
}

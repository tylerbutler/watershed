import gleam/list
import gleam/option.{None, Some}
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

pub fn connect_route_is_static_and_uses_shared_styles_test() {
  route.guide_connect()
  |> should.equal(route.Route(
    path: "/guide/connect",
    layout: route.Guide,
    content_path: "content/guide/connect.djot",
    client_script: None,
    analytics: route.Tinylytics,
  ))
  route.stylesheets(route.guide_connect())
  |> should.equal(["/styles/site.css"])
  route.stylesheets(route.guide_race())
  |> should.equal(["/styles/site.css", "/styles/guide-race.css"])
}

pub fn notes_route_is_registered_as_a_static_guide_test() {
  route.all()
  |> list.filter(fn(item) { item.path == "/guide/notes" })
  |> should.equal([route.guide_notes()])
  route.guide_notes()
  |> should.equal(route.Route(
    path: "/guide/notes",
    layout: route.Guide,
    content_path: "content/guide/notes.djot",
    client_script: None,
    analytics: route.Tinylytics,
  ))
  route.stylesheets(route.guide_notes())
  |> should.equal(["/styles/site.css"])
}

pub fn votes_route_is_registered_as_a_static_guide_test() {
  route.all()
  |> list.filter(fn(item) { item.path == "/guide/votes" })
  |> should.equal([route.guide_votes()])
  route.guide_votes()
  |> should.equal(route.Route(
    path: "/guide/votes",
    layout: route.Guide,
    content_path: "content/guide/votes.djot",
    client_script: None,
    analytics: route.Tinylytics,
  ))
  route.stylesheets(route.guide_votes())
  |> should.equal(["/styles/site.css"])
}

pub fn presence_route_is_registered_as_a_static_guide_test() {
  route.all()
  |> list.filter(fn(item) { item.path == "/guide/presence" })
  |> should.equal([route.guide_presence()])
  route.guide_presence()
  |> should.equal(route.Route(
    path: "/guide/presence",
    layout: route.Guide,
    content_path: "content/guide/presence.djot",
    client_script: None,
    analytics: route.Tinylytics,
  ))
  route.stylesheets(route.guide_presence())
  |> should.equal(["/styles/site.css"])
}

pub fn testing_route_is_registered_as_a_static_guide_test() {
  route.all()
  |> list.filter(fn(item) { item.path == "/guide/testing" })
  |> should.equal([route.guide_testing()])
  route.guide_testing()
  |> should.equal(route.Route(
    path: "/guide/testing",
    layout: route.Guide,
    content_path: "content/guide/testing.djot",
    client_script: None,
    analytics: route.Tinylytics,
  ))
  route.stylesheets(route.guide_testing())
  |> should.equal(["/styles/site.css"])
}

pub fn foundations_index_is_registered_as_a_static_page_test() {
  let assert Ok(foundations) =
    route.all()
    |> list.find(fn(item) { item.path == "/foundations" })
  foundations.content_path
  |> should.equal("content/foundations/index.djot")
  foundations.client_script |> should.equal(None)
  route.stylesheets(foundations)
  |> should.equal(["/styles/site.css", "/styles/concept-index.css"])
}

pub fn component_model_index_uses_the_shared_concept_index_test() {
  let assert Ok(component_model) =
    route.all()
    |> list.find(fn(item) { item.path == "/component-model" })
  component_model.content_path
  |> should.equal("content/component-model/index.djot")
  component_model.client_script |> should.equal(None)
  route.stylesheets(component_model)
  |> should.equal(["/styles/site.css", "/styles/concept-index.css"])
}

pub fn structures_index_is_registered_as_the_field_atlas_test() {
  let assert Ok(structures) =
    route.all()
    |> list.find(fn(item) { item.path == "/structures" })
  structures.layout |> should.equal(route.StructureIndex)
  structures.content_path
  |> should.equal("content/structures/index.djot")
  structures.client_script |> should.equal(None)
  route.stylesheets(structures)
  |> should.equal(["/styles/site.css", "/styles/structures-index.css"])
}

pub fn structure_family_routes_use_the_shared_atlas_sheet_test() {
  [
    "counters", "sets", "registers", "maps", "sequences", "coordination",
    "transforms",
  ]
  |> list.each(fn(slug) {
    let assert Ok(item) =
      route.all()
      |> list.find(fn(item) { item.path == "/structures/" <> slug })
    item.layout |> should.equal(route.StructureSheet)
    item.content_path
    |> should.equal("content/structures/" <> slug <> ".djot")
    item.client_script |> should.equal(None)
    route.stylesheets(item)
    |> should.equal(["/styles/site.css", "/styles/structure-sheet.css"])
  })
}

pub fn foundations_detail_routes_use_the_shared_concept_sheet_test() {
  [
    #("schema", "content/foundations/schema.djot"),
    #("topology", "content/foundations/topology.djot"),
    #("lifecycle", "content/foundations/lifecycle.djot"),
  ]
  |> list.each(fn(expected) {
    let assert Ok(item) =
      route.all()
      |> list.find(fn(item) { item.path == "/foundations/" <> expected.0 })
    item.layout |> should.equal(route.ConceptSheet)
    item.content_path |> should.equal(expected.1)
    item.client_script |> should.equal(None)
    route.stylesheets(item)
    |> should.equal(["/styles/site.css", "/styles/concept-sheet.css"])
  })
}

pub fn component_model_detail_routes_use_the_shared_concept_sheet_test() {
  [
    #("components", "content/component-model/components.djot"),
    #("ports", "content/component-model/ports.djot"),
    #("workspaces", "content/component-model/workspaces.djot"),
  ]
  |> list.each(fn(expected) {
    let assert Ok(item) =
      route.all()
      |> list.find(fn(item) { item.path == "/component-model/" <> expected.0 })
    item.layout |> should.equal(route.ConceptSheet)
    item.content_path |> should.equal(expected.1)
    item.client_script |> should.equal(None)
    route.stylesheets(item)
    |> should.equal(["/styles/site.css", "/styles/concept-sheet.css"])
  })
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

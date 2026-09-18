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
  )
}

pub type Layout {
  Home
  Guide
  GuideIndex
  ConceptIndex
  ConceptSheet
  StructureIndex
  StructureSheet
  Models
  Patterns
  Examples
  SharedTree
  Sudoku
  Directory
  CounterBug
  JsonOt
  MvRegister
  RichText
  Sequence
  Text
}

fn page(
  path: String,
  layout: Layout,
  content_path: String,
  client_script: Option(String),
) -> Route {
  Route(path, layout, content_path, client_script)
}

pub fn all() -> List(Route) {
  [
    page("/", Home, "content/home.djot", Some("/home.js")),
    page("/foundations", ConceptIndex, "content/foundations/index.djot", None),
    page(
      "/foundations/schema",
      ConceptSheet,
      "content/foundations/schema.djot",
      None,
    ),
    page(
      "/foundations/topology",
      ConceptSheet,
      "content/foundations/topology.djot",
      None,
    ),
    page(
      "/foundations/lifecycle",
      ConceptSheet,
      "content/foundations/lifecycle.djot",
      None,
    ),
    page(
      "/component-model",
      ConceptIndex,
      "content/component-model/index.djot",
      None,
    ),
    page(
      "/component-model/components",
      ConceptSheet,
      "content/component-model/components.djot",
      None,
    ),
    page(
      "/component-model/ports",
      ConceptSheet,
      "content/component-model/ports.djot",
      None,
    ),
    page(
      "/component-model/workspaces",
      ConceptSheet,
      "content/component-model/workspaces.djot",
      None,
    ),
    page("/runtime", ConceptIndex, "content/runtime/index.djot", None),
    page(
      "/runtime/optimistic",
      ConceptSheet,
      "content/runtime/optimistic.djot",
      None,
    ),
    page(
      "/runtime/reconnect",
      ConceptSheet,
      "content/runtime/reconnect.djot",
      None,
    ),
    page(
      "/runtime/redelivery",
      ConceptSheet,
      "content/runtime/redelivery.djot",
      None,
    ),
    page(
      "/runtime/presence",
      ConceptSheet,
      "content/runtime/presence.djot",
      None,
    ),
    page("/runtime/p2p", ConceptSheet, "content/runtime/p2p.djot", None),
    page("/structures", StructureIndex, "content/structures/index.djot", None),
    page(
      "/structures/counters",
      StructureSheet,
      "content/structures/counters.djot",
      None,
    ),
    page(
      "/structures/sets",
      StructureSheet,
      "content/structures/sets.djot",
      None,
    ),
    page(
      "/structures/registers",
      StructureSheet,
      "content/structures/registers.djot",
      None,
    ),
    page(
      "/structures/maps",
      StructureSheet,
      "content/structures/maps.djot",
      None,
    ),
    page(
      "/structures/sequences",
      StructureSheet,
      "content/structures/sequences.djot",
      None,
    ),
    page(
      "/structures/coordination",
      StructureSheet,
      "content/structures/coordination.djot",
      None,
    ),
    page(
      "/structures/transforms",
      StructureSheet,
      "content/structures/transforms.djot",
      None,
    ),
    page("/models", Models, "content/models.djot", None),
    page("/patterns", Patterns, "content/patterns.djot", None),
    page("/examples", Examples, "content/examples.djot", None),
    page("/sharedtree", SharedTree, "content/sharedtree.djot", None),
    page("/sudoku", Sudoku, "content/sudoku.djot", Some("/sudoku.js")),
    page(
      "/directory",
      Directory,
      "content/directory.djot",
      Some("/directory.js"),
    ),
    page(
      "/counter-bug",
      CounterBug,
      "content/counter-bug.djot",
      Some("/counter_bug.js"),
    ),
    page("/json-ot", JsonOt, "content/json-ot.djot", Some("/json_ot.js")),
    page(
      "/mv-register",
      MvRegister,
      "content/mv-register.djot",
      Some("/mv_register.js"),
    ),
    page(
      "/rich-text",
      RichText,
      "content/rich-text.djot",
      Some("/rich_text.js"),
    ),
    page("/sequence", Sequence, "content/sequence.djot", Some("/sequence.js")),
    page("/text", Text, "content/text.djot", Some("/text.js")),
    page("/guide", GuideIndex, "content/guide/index.djot", None),
    page("/guide/connect", Guide, "content/guide/connect.djot", None),
    page("/guide/notes", Guide, "content/guide/notes.djot", None),
    page(
      "/guide/race",
      Guide,
      "content/guide/race.djot",
      Some("/guide_race.js"),
    ),
    page("/guide/votes", Guide, "content/guide/votes.djot", None),
    page("/guide/presence", Guide, "content/guide/presence.djot", None),
    page("/guide/testing", Guide, "content/guide/testing.djot", None),
  ]
}

pub fn stylesheets(route: Route) -> List(String) {
  case route.layout {
    Home -> ["/styles/site.css", "/styles/home.css"]
    Guide ->
      case route.path {
        "/guide/race" -> ["/styles/site.css", "/styles/guide-race.css"]
        _ -> ["/styles/site.css"]
      }
    GuideIndex -> ["/styles/site.css", "/styles/guide-index.css"]
    ConceptIndex -> ["/styles/site.css", "/styles/concept-index.css"]
    ConceptSheet -> ["/styles/site.css", "/styles/concept-sheet.css"]
    StructureIndex -> ["/styles/site.css", "/styles/structures-index.css"]
    StructureSheet -> ["/styles/site.css", "/styles/structure-sheet.css"]
    Models -> ["/styles/site.css", "/styles/models.css"]
    Patterns -> ["/styles/site.css", "/styles/patterns.css"]
    Examples -> ["/styles/site.css", "/styles/examples.css"]
    SharedTree -> ["/styles/site.css", "/styles/sharedtree.css"]
    Sudoku -> ["/styles/site.css", "/styles/sudoku.css"]
    Directory -> ["/styles/site.css", "/styles/directory.css"]
    CounterBug -> ["/styles/site.css", "/styles/counter-bug.css"]
    JsonOt -> ["/styles/site.css", "/styles/json-ot.css"]
    MvRegister -> ["/styles/site.css", "/styles/mv-register.css"]
    RichText -> ["/styles/site.css", "/styles/rich-text.css"]
    Sequence -> ["/styles/site.css", "/styles/sequence.css"]
    Text -> ["/styles/site.css", "/styles/text.css"]
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

pub fn find(path: String) -> Result(Route, Nil) {
  list.find(all(), fn(route) { route.path == path })
}

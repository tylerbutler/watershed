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

pub fn guide_connect() -> Route {
  Route(
    path: "/guide/connect",
    layout: Guide,
    content_path: "content/guide/connect.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn guide_notes() -> Route {
  Route(
    path: "/guide/notes",
    layout: Guide,
    content_path: "content/guide/notes.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn guide_votes() -> Route {
  Route(
    path: "/guide/votes",
    layout: Guide,
    content_path: "content/guide/votes.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn guide_presence() -> Route {
  Route(
    path: "/guide/presence",
    layout: Guide,
    content_path: "content/guide/presence.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn guide_testing() -> Route {
  Route(
    path: "/guide/testing",
    layout: Guide,
    content_path: "content/guide/testing.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn foundations_index() -> Route {
  Route(
    path: "/foundations",
    layout: ConceptIndex,
    content_path: "content/foundations/index.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn component_model_index() -> Route {
  Route(
    path: "/component-model",
    layout: ConceptIndex,
    content_path: "content/component-model/index.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn runtime_index() -> Route {
  Route(
    path: "/runtime",
    layout: ConceptIndex,
    content_path: "content/runtime/index.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn structures_index() -> Route {
  Route(
    path: "/structures",
    layout: StructureIndex,
    content_path: "content/structures/index.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn structure_family(slug: String) -> Route {
  Route(
    path: "/structures/" <> slug,
    layout: StructureSheet,
    content_path: "content/structures/" <> slug <> ".djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn models() -> Route {
  Route(
    path: "/models",
    layout: Models,
    content_path: "content/models.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn patterns() -> Route {
  Route(
    path: "/patterns",
    layout: Patterns,
    content_path: "content/patterns.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn examples() -> Route {
  Route(
    path: "/examples",
    layout: Examples,
    content_path: "content/examples.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn sharedtree() -> Route {
  Route(
    path: "/sharedtree",
    layout: SharedTree,
    content_path: "content/sharedtree.djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn sudoku() -> Route {
  Route(
    path: "/sudoku",
    layout: Sudoku,
    content_path: "content/sudoku.djot",
    client_script: Some("/sudoku.js"),
    analytics: Tinylytics,
  )
}

pub fn directory() -> Route {
  Route(
    path: "/directory",
    layout: Directory,
    content_path: "content/directory.djot",
    client_script: Some("/directory.js"),
    analytics: Tinylytics,
  )
}

pub fn counter_bug() -> Route {
  Route(
    path: "/counter-bug",
    layout: CounterBug,
    content_path: "content/counter-bug.djot",
    client_script: Some("/counter_bug.js"),
    analytics: Tinylytics,
  )
}

pub fn json_ot() -> Route {
  Route(
    path: "/json-ot",
    layout: JsonOt,
    content_path: "content/json-ot.djot",
    client_script: Some("/json_ot.js"),
    analytics: Tinylytics,
  )
}

pub fn mv_register() -> Route {
  Route(
    path: "/mv-register",
    layout: MvRegister,
    content_path: "content/mv-register.djot",
    client_script: Some("/mv_register.js"),
    analytics: Tinylytics,
  )
}

pub fn rich_text() -> Route {
  Route(
    path: "/rich-text",
    layout: RichText,
    content_path: "content/rich-text.djot",
    client_script: Some("/rich_text.js"),
    analytics: Tinylytics,
  )
}

pub fn foundation(slug: String) -> Route {
  Route(
    path: "/foundations/" <> slug,
    layout: ConceptSheet,
    content_path: "content/foundations/" <> slug <> ".djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn component_model(slug: String) -> Route {
  Route(
    path: "/component-model/" <> slug,
    layout: ConceptSheet,
    content_path: "content/component-model/" <> slug <> ".djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn runtime(slug: String) -> Route {
  Route(
    path: "/runtime/" <> slug,
    layout: ConceptSheet,
    content_path: "content/runtime/" <> slug <> ".djot",
    client_script: None,
    analytics: Tinylytics,
  )
}

pub fn all() -> List(Route) {
  [
    foundations_index(),
    foundation("schema"),
    foundation("topology"),
    foundation("lifecycle"),
    component_model_index(),
    component_model("components"),
    component_model("ports"),
    component_model("workspaces"),
    runtime_index(),
    runtime("optimistic"),
    runtime("reconnect"),
    runtime("redelivery"),
    runtime("presence"),
    runtime("p2p"),
    structures_index(),
    structure_family("counters"),
    structure_family("sets"),
    structure_family("registers"),
    structure_family("maps"),
    structure_family("sequences"),
    structure_family("coordination"),
    structure_family("transforms"),
    models(),
    patterns(),
    examples(),
    sharedtree(),
    sudoku(),
    directory(),
    counter_bug(),
    json_ot(),
    mv_register(),
    rich_text(),
    Route(
      path: "/guide",
      layout: GuideIndex,
      content_path: "content/guide/index.djot",
      client_script: None,
      analytics: Tinylytics,
    ),
    guide_connect(),
    guide_notes(),
    guide_race(),
    guide_votes(),
    guide_presence(),
    guide_testing(),
  ]
}

pub fn stylesheets(route: Route) -> List(String) {
  case route.layout {
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

import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/ssg/djot
import watershed_site/code
import watershed_site/content
import watershed_site/error.{type BuildError}
import watershed_site/guide
import watershed_site/guide_race/view as race_view
import watershed_site/practice
import watershed_site/route
import watershed_site/snippet
import watershed_site/view/concept_index
import watershed_site/view/concept_sheet
import watershed_site/view/counter_bug
import watershed_site/view/directory
import watershed_site/view/document
import watershed_site/view/examples
import watershed_site/view/field_notes
import watershed_site/view/guide as guide_view
import watershed_site/view/guide_index
import watershed_site/view/json_ot
import watershed_site/view/models
import watershed_site/view/mv_register
import watershed_site/view/patterns
import watershed_site/view/runtime_index
import watershed_site/view/runtime_sheet
import watershed_site/view/sharedtree
import watershed_site/view/structure_sheet
import watershed_site/view/structures_index
import watershed_site/view/sudoku

pub type GuidePage(msg) {
  GuidePage(
    route: route.Route,
    metadata: content.Metadata,
    step: guide.Step,
    body: List(Element(msg)),
    demo: Element(msg),
    field_notes: Element(msg),
  )
}

pub fn render(
  source: content.Source,
  route: route.Route,
  manifest: snippet.Manifest,
  revision: String,
) -> Result(Element(Nil), BuildError) {
  use _ <- result.try(content.validate(source.document, source.path))
  use _ <- result.try(content.validate_snippets(
    source.document,
    manifest,
    source.path,
  ))
  let default = code.renderer(manifest, revision)
  let renderer =
    djot.Renderer(
      ..default,
      div: fn(attributes, children) {
        case dict.get(attributes, "data-component") {
          Ok("guide-race") ->
            html.div(
              [
                attribute.id("guide-race-mount"),
              ],
              [race_view.static()],
            )
          Ok("sharedtree-gaps") -> sharedtree.gaps()
          Ok("field-note-ref") -> {
            let assert Ok(id) = dict.get(attributes, "data-practice")
            let assert Ok(item) = practice.get(id)
            field_notes.reference(item)
          }
          Ok(name) ->
            case guide_index.component(name) {
              Ok(component) -> guide_index.component_view(component, children)
              Error(Nil) ->
                case concept_index.component(name) {
                  Ok(component) ->
                    concept_index.component_view(
                      component,
                      route.path,
                      children,
                    )
                  Error(Nil) ->
                    case runtime_index.component(name) {
                      Ok(component) ->
                        runtime_index.component_view(component, children)
                      Error(Nil) ->
                        case runtime_sheet.component(name) {
                          Ok(component) ->
                            runtime_sheet.component_view(component)
                          Error(Nil) ->
                            case structures_index.component(name) {
                              Ok(component) ->
                                structures_index.component_view(
                                  component,
                                  children,
                                )
                              Error(Nil) -> default.div(attributes, children)
                            }
                        }
                    }
                }
            }
          Error(Nil) -> default.div(attributes, children)
        }
      },
      paragraph: fn(attributes, children) {
        case dict.get(attributes, "class") {
          Ok("cta-row" as class) | Ok("gi-companion-links" as class) ->
            html.div([attribute.class(class)], children)
          Ok("annot" as class) -> html.span([attribute.class(class)], children)
          Ok("fh-scope annot" as class) ->
            html.span([attribute.class(class)], children)
          Ok("fh-scope annot fh-scope-optional" as class) ->
            html.span([attribute.class(class)], children)
          _ -> default.paragraph(attributes, children)
        }
      },
      bullet_list: fn(_, style, items) {
        let items = list.map(items, fn(item) { html.li([], item) })
        // Jot 8 has no ordered-list node. Star markers select ordered lists.
        case style {
          "*" -> html.ol([], items)
          _ -> html.ul([], items)
        }
      },
      heading: fn(attributes, level, children) {
        // Jot replaces explicit heading IDs with its generated IDs.
        let attributes = case dict.get(attributes, "data-heading-id") {
          Ok(id) ->
            attributes
            |> dict.delete("data-heading-id")
            |> dict.insert("id", id)
          Error(Nil) -> attributes
        }
        default.heading(attributes, level, children)
      },
    )
  let body = djot.render(source.body, renderer)
  case source.metadata.kind {
    content.GuideStep(slug) -> {
      use notes <- result.try(field_notes.view(slug, manifest))
      Ok(
        view(GuidePage(
          route,
          source.metadata,
          guide.get(slug),
          body,
          element.none(),
          notes,
        )),
      )
    }
    content.GuideIndex ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — build guide",
        guide_index.view(body),
      ))
    content.ConceptIndex ->
      Ok(
        render_document(
          route,
          source.metadata,
          "watershed — "
            <> case route.path {
            "/component-model" -> "component model"
            "/runtime" -> "runtime behavior"
            _ -> "foundations"
          },
          case route.path {
            "/runtime" -> runtime_index.view(body)
            _ -> concept_index.view(route.path, body)
          },
        ),
      )
    content.ConceptSheet(doc) ->
      Ok(render_document(
        route,
        source.metadata,
        concept_sheet.title(doc),
        concept_sheet.view(doc, body),
      ))
    content.RuntimeSheet(doc) ->
      Ok(render_document(
        route,
        source.metadata,
        runtime_sheet.title(doc),
        runtime_sheet.view(doc, body),
      ))
    content.StructureIndex ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — data structures",
        structures_index.view(body),
      ))
    content.StructureSheet(family) ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — " <> string.lowercase(family.name),
        structure_sheet.view(family),
      ))
    content.Models ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — DDS vs CRDT vs OT",
        models.view(),
      ))
    content.Patterns -> {
      use body <- result.try(patterns.view(manifest))
      Ok(render_document(
        route,
        source.metadata,
        "watershed — patterns from the examples",
        body,
      ))
    }
    content.Examples ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — browser examples",
        examples.view(),
      ))
    content.SharedTree ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — SharedTree and the schema layer",
        sharedtree.view(body),
      ))
    content.Sudoku ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — SharedMap Sudoku demo",
        sudoku.view(),
      ))
    content.Directory ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — SharedDirectory demo",
        directory.view(),
      ))
    content.CounterBug ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — a counter is not a map cell",
        counter_bug.view(),
      ))
    content.JsonOt ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — JSON operational transform demo",
        json_ot.view(),
      ))
    content.MvRegister ->
      Ok(render_document(
        route,
        source.metadata,
        "watershed — MV-register revision slate",
        mv_register.view(body),
      ))
  }
}

pub fn view(page: GuidePage(msg)) -> Element(Nil) {
  let title = "watershed — " <> string.lowercase(page.step.title)
  render_document(
    page.route,
    page.metadata,
    title,
    guide_view.view(
      page.route.path <> "/",
      page.step,
      page.body,
      page.demo,
      page.field_notes,
    )
      |> element.map(fn(_) { Nil }),
  )
}

fn render_document(
  page_route: route.Route,
  metadata: content.Metadata,
  title: String,
  body: Element(Nil),
) -> Element(Nil) {
  let scripts = case page_route.analytics {
    route.NoAnalytics -> []
    route.Tinylytics -> [
      document.Deferred(
        "https://tinylytics.app/embed/uhk_zvSq2fBb_T2hTaLx/min.js?hits&events&beacon",
        [],
      ),
    ]
  }
  let scripts =
    list.append(scripts, case page_route.client_script {
      option.None -> []
      option.Some(src) -> [document.Module(src)]
    })
  let scripts = case metadata.kind {
    content.GuideStep(slug) ->
      case list.is_empty(practice.by_step(slug)) {
        True -> scripts
        False ->
          list.append(scripts, [document.Module("/scripts/field-notes.js")])
      }
    content.GuideIndex
    | content.ConceptIndex
    | content.ConceptSheet(_)
    | content.RuntimeSheet(_)
    | content.StructureIndex
    | content.StructureSheet(_)
    | content.Models
    | content.Patterns
    | content.Examples
    | content.SharedTree
    | content.Sudoku
    | content.Directory
    | content.CounterBug
    | content.JsonOt
    | content.MvRegister -> scripts
  }
  let scripts = case page_route.layout {
    route.Guide -> scripts
    route.GuideIndex ->
      list.append(scripts, [document.Module("/scripts/guide-index.js")])
    route.ConceptIndex ->
      scripts
      |> list.append([document.Module("/scripts/concept-index.js")])
    route.ConceptSheet -> scripts
    route.StructureIndex ->
      scripts
      |> list.append([document.Module("/scripts/concept-index.js")])
    route.StructureSheet -> scripts
    route.Models ->
      scripts
      |> list.append([document.Module("/scripts/concept-index.js")])
    route.Patterns -> scripts
    route.Examples -> scripts
    route.SharedTree ->
      scripts
      |> list.append([document.Module("/scripts/concept-index.js")])
    route.Sudoku ->
      scripts
      |> list.append([document.Module("/scripts/concept-index.js")])
    route.Directory ->
      scripts
      |> list.append([document.Module("/scripts/concept-index.js")])
    route.CounterBug -> scripts
    route.JsonOt -> scripts
    route.MvRegister ->
      scripts
      |> list.append([document.Module("/scripts/concept-index.js")])
  }
  document.view(document.Document(
    title:,
    description: metadata.description,
    url: document.site_url <> page_route.path <> "/",
    og_title: option.unwrap(metadata.og_title, title),
    og_description: option.unwrap(metadata.og_description, metadata.description),
    stylesheets: route.stylesheets(page_route),
    scripts:,
    body:,
  ))
}

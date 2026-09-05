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
import watershed_site/route
import watershed_site/snippet
import watershed_site/view/document
import watershed_site/view/guide as guide_view
import watershed_site/view/guide_index

pub type GuidePage(msg) {
  GuidePage(
    route: route.Route,
    metadata: content.Metadata,
    step: guide.Step,
    body: List(Element(msg)),
    demo: Element(msg),
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
          Ok(name) ->
            case guide_index.component(name) {
              Ok(component) -> guide_index.component_view(component, children)
              Error(Nil) -> default.div(attributes, children)
            }
          Error(Nil) -> default.div(attributes, children)
        }
      },
      paragraph: fn(attributes, children) {
        case dict.get(attributes, "class") {
          Ok("cta-row" as class) | Ok("gi-companion-links" as class) ->
            html.div([attribute.class(class)], children)
          _ -> default.paragraph(attributes, children)
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
  Ok(case source.metadata.kind {
    content.GuideStep(slug) ->
      view(GuidePage(
        route,
        source.metadata,
        guide.get(slug),
        body,
        element.none(),
      ))
    content.GuideIndex ->
      render_document(
        route,
        source.metadata,
        "watershed — build guide",
        guide_index.view(body),
      )
  })
}

pub fn view(page: GuidePage(msg)) -> Element(Nil) {
  let title = "watershed — " <> string.lowercase(page.step.title)
  render_document(
    page.route,
    page.metadata,
    title,
    guide_view.view(page.route.path <> "/", page.step, page.body, page.demo)
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
  let scripts = case page_route.layout {
    route.Guide -> scripts
    route.GuideIndex ->
      list.append(scripts, [document.Module("/scripts/guide-index.js")])
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

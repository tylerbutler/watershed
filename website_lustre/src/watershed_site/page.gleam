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
    djot.Renderer(..default, div: fn(attributes, children) {
      case dict.get(attributes, "data-component") {
        Ok("guide-race") ->
          html.div(
            [
              attribute.id("guide-race-mount"),
            ],
            [race_view.static()],
          )
        _ -> default.div(attributes, children)
      }
    })
  Ok(
    view(GuidePage(
      route,
      source.metadata,
      guide.get(source.metadata.guide_step),
      djot.render(source.body, renderer),
      element.none(),
    )),
  )
}

pub fn view(page: GuidePage(msg)) -> Element(Nil) {
  let title = "watershed — " <> string.lowercase(page.step.title)
  let scripts = case page.route.analytics {
    route.NoAnalytics -> []
    route.Tinylytics -> [
      document.Deferred(
        "https://tinylytics.app/embed/uhk_zvSq2fBb_T2hTaLx/min.js?hits&events&beacon",
        [],
      ),
    ]
  }
  let scripts =
    list.append(scripts, case page.route.client_script {
      option.None -> []
      option.Some(src) -> [document.Module(src)]
    })
  document.view(document.Document(
    title:,
    description: page.metadata.description,
    url: document.site_url <> page.route.path,
    og_title: option.unwrap(page.metadata.og_title, title),
    og_description: option.unwrap(
      page.metadata.og_description,
      page.metadata.description,
    ),
    stylesheets: ["/styles/site.css", "/styles/guide-race.css"],
    scripts:,
    body: guide_view.view(page.route.path, page.step, page.body, page.demo)
      |> element.map(fn(_) { Nil }),
  ))
}

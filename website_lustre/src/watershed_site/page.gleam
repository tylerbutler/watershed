import gleam/list
import gleam/option
import gleam/string
import lustre/element.{type Element}
import watershed_site/content
import watershed_site/guide
import watershed_site/route
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

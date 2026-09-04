import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h

pub const site_url = "https://watershed.tylerbutler.com"

pub type Document {
  Document(
    title: String,
    description: String,
    url: String,
    og_title: String,
    og_description: String,
    stylesheets: List(String),
    scripts: List(Script),
    body: Element(Nil),
  )
}

pub type Script {
  Module(src: String)
  Deferred(src: String, attributes: List(#(String, String)))
}

pub fn view(document: Document) -> Element(Nil) {
  h.html([a.lang("en")], [
    h.head([], [
      h.meta([a.charset("utf-8")]),
      meta("viewport", "width=device-width, initial-scale=1"),
      h.title([], document.title),
      meta("description", document.description),
      h.link([a.rel("icon"), a.href("/favicon.svg"), a.type_("image/svg+xml")]),
      property("og:title", document.og_title),
      property("og:description", document.og_description),
      property("og:type", "website"),
      property("og:url", document.url),
      property("og:image", site_url <> "/og.png"),
      property("og:image:width", "2400"),
      property("og:image:height", "1260"),
      property(
        "og:image:alt",
        "A survey-sheet card reading “Edit upstream. Converge downstream.” (watershed, collaborative data structures for Gleam).",
      ),
      meta("twitter:card", "summary_large_image"),
      element.fragment(
        list.map(document.stylesheets, fn(path) {
          h.link([a.rel("stylesheet"), a.href(path)])
        }),
      ),
      element.fragment(
        list.map(document.scripts, fn(script) {
          case script {
            Module(src) -> h.script([a.type_("module"), a.src(src)], "")
            Deferred(src, attributes) ->
              h.script(
                [
                  a.src(src),
                  a.attribute("defer", ""),
                  ..list.map(attributes, fn(pair) {
                    a.attribute(pair.0, pair.1)
                  })
                ],
                "",
              )
          }
        }),
      ),
    ]),
    h.body([], [document.body]),
  ])
}

fn meta(name: String, value: String) -> Element(msg) {
  h.meta([a.name(name), a.content(value)])
}

fn property(name: String, value: String) -> Element(msg) {
  h.meta([a.attribute("property", name), a.content(value)])
}

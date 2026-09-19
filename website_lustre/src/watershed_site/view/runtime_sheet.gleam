import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/runtime
import watershed_site/view/ecosystem
import watershed_site/view/related_field_notes
import watershed_site/view/sheet

pub type Component {
  OpLog
}

pub fn component(name: String) -> Result(Component, Nil) {
  case name {
    "runtime-oplog" -> Ok(OpLog)
    _ -> Error(Nil)
  }
}

pub fn component_view(component: Component) -> Element(msg) {
  case component {
    OpLog ->
      h.figure(
        [
          a.class("oplog"),
          a.attribute(
            "aria-label",
            "Op-log excerpt: a duplicate delta absorbed",
          ),
        ],
        [
          op_log_line("#03", "cut −5 yd³ → net −5", ""),
          op_log_line("#03", "again · cut −5 yd³ · absorbed", " oplog-dupe"),
        ],
      )
  }
}

fn op_log_line(
  sequence: String,
  operation: String,
  class: String,
) -> Element(msg) {
  h.div([a.class("oplog-line" <> class)], [
    h.span([a.class("oplog-sn")], [h.text(sequence)]),
    h.span([a.class("oplog-op")], [h.text(operation)]),
  ])
}

pub fn view(doc: runtime.Doc, body: List(Element(msg))) -> Element(msg) {
  let path = "/runtime/" <> doc.slug
  sheet.view(path <> "/", [
    hero(doc),
    h.main([a.class("doc-body"), a.id("content")], body),
    related_field_notes.view(path),
    pager(doc),
    ecosystem.view(path <> "/"),
  ])
}

fn hero(doc: runtime.Doc) -> Element(msg) {
  h.header([a.class("r-hero fd-hero")], [
    h.div([a.class("r-hero-inner fd-hero-inner")], [
      h.p([a.class("r-crumbs fd-crumbs annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" · "),
        h.a([a.href("/runtime")], [h.text("Runtime")]),
        h.text(" / " <> doc.title),
      ]),
      h.span(
        [
          a.class("r-eyebrow fd-eyebrow annot"),
          a.attribute("aria-hidden", "true"),
        ],
        [h.text("Runtime behavior")],
      ),
      h.h1([], [h.text(doc.title)]),
      h.p([a.class("r-gloss fd-gloss")], [h.text(doc.gloss)]),
      h.p([a.class("r-concept fd-concept annot")], [
        h.span([], [h.text("Traces")]),
        h.text(" " <> doc.concept),
      ]),
    ]),
  ])
}

fn pager(doc: runtime.Doc) -> Element(msg) {
  let #(previous, next) = runtime.neighbours(doc.slug)
  h.nav(
    [
      a.class("r-pager fd-pager"),
      a.attribute("aria-label", "Runtime sheets"),
    ],
    [
      case previous {
        Ok(previous) -> pager_cell(previous, "prev")
        Error(Nil) ->
          h.a(
            [
              a.class("r-pager-cell r-pager-prev fd-pager-cell fd-pager-prev"),
              a.href("/runtime"),
            ],
            [
              h.span([a.class("annot")], [h.text("← Index")]),
              h.span([a.class("r-pager-gloss fd-pager-gloss")], [
                h.text("All runtime behaviors"),
              ]),
            ],
          )
      },
      case next {
        Ok(next) -> pager_cell(next, "next")
        Error(Nil) ->
          h.a(
            [
              a.class("r-pager-cell r-pager-next fd-pager-cell fd-pager-next"),
              a.href("/guide"),
            ],
            [
              h.span([a.class("annot")], [h.text("Build guide →")]),
              h.span([a.class("r-pager-gloss fd-pager-gloss")], [
                h.text("Put these behaviors to work"),
              ]),
            ],
          )
      },
    ],
  )
}

fn pager_cell(doc: runtime.Doc, direction: String) -> Element(msg) {
  let previous = direction == "prev"
  let label = case previous {
    True -> "← " <> doc.title
    False -> doc.title <> " →"
  }
  h.a(
    [
      a.class(
        "r-pager-cell r-pager-"
        <> direction
        <> " fd-pager-cell fd-pager-"
        <> direction,
      ),
      a.href("/runtime/" <> doc.slug),
    ],
    [
      h.span([a.class("annot")], [h.text(label)]),
      h.span([a.class("r-pager-gloss fd-pager-gloss")], [h.text(doc.gloss)]),
    ],
  )
}

pub fn title(doc: runtime.Doc) -> String {
  "watershed — " <> string.lowercase(doc.title)
}

import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/foundations
import watershed_site/view/ecosystem
import watershed_site/view/related_field_notes
import watershed_site/view/sheet

pub fn view(doc: foundations.Doc, body: List(Element(msg))) -> Element(msg) {
  let path = "/foundations/" <> doc.slug
  sheet.view(path <> "/", [
    hero(doc),
    h.main([a.class("doc-body"), a.id("content")], body),
    related_field_notes.view(path),
    pager(doc),
    ecosystem.view(path <> "/"),
  ])
}

fn hero(doc: foundations.Doc) -> Element(msg) {
  h.header([a.class("fd-hero")], [
    h.div([a.class("fd-hero-inner")], [
      h.p([a.class("fd-crumbs annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" · "),
        h.a([a.href("/foundations")], [h.text("Foundations")]),
        h.text(" / " <> doc.title),
      ]),
      h.span([a.class("fd-eyebrow annot"), a.attribute("aria-hidden", "true")], [
        h.text("Foundations"),
      ]),
      h.h1([], [h.text(doc.title)]),
      h.p([a.class("fd-scope")], [h.text("Core · every watershed app")]),
      h.p([a.class("fd-gloss")], [h.text(doc.gloss)]),
      h.p([a.class("fd-concept annot")], [
        h.span([], [h.text("Traces")]),
        h.text(" " <> doc.concept),
      ]),
    ]),
  ])
}

fn pager(doc: foundations.Doc) -> Element(msg) {
  let #(previous, next) = foundations.neighbours(doc.slug)
  h.nav([a.class("fd-pager"), a.attribute("aria-label", "Foundations sheets")], [
    case previous {
      Ok(previous) -> pager_cell(previous, "prev")
      Error(Nil) ->
        h.a([a.class("fd-pager-cell fd-pager-prev"), a.href("/foundations")], [
          h.span([a.class("annot")], [h.text("← Index")]),
          h.span([a.class("fd-pager-gloss")], [
            h.text("All foundations sheets"),
          ]),
        ])
    },
    case next {
      Ok(next) -> pager_cell(next, "next")
      Error(Nil) ->
        h.a([a.class("fd-pager-cell fd-pager-next"), a.href("/guide")], [
          h.span([a.class("annot")], [h.text("Build guide →")]),
          h.span([a.class("fd-pager-gloss")], [
            h.text("Put these ideas to work"),
          ]),
        ])
    },
  ])
}

fn pager_cell(doc: foundations.Doc, direction: String) -> Element(msg) {
  let previous = direction == "prev"
  let label = case previous {
    True -> "← " <> doc.title
    False -> doc.title <> " →"
  }
  h.a(
    [
      a.class("fd-pager-cell fd-pager-" <> direction),
      a.href("/foundations/" <> doc.slug),
    ],
    [
      h.span([a.class("annot")], [h.text(label)]),
      h.span([a.class("fd-pager-gloss")], [h.text(doc.gloss)]),
    ],
  )
}

pub fn title(doc: foundations.Doc) -> String {
  "watershed — " <> string.lowercase(doc.title)
}

import gleam/int
import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/foundations
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub type Component {
  Intro
  Content
  Aside
}

pub fn component(name: String) -> Result(Component, Nil) {
  case name {
    "concept-intro" -> Ok(Intro)
    "concept-content" -> Ok(Content)
    "concept-aside" -> Ok(Aside)
    _ -> Error(Nil)
  }
}

pub fn component_view(
  component: Component,
  children: List(Element(msg)),
) -> Element(msg) {
  case component {
    Intro ->
      h.header(
        [a.class("fh-hero"), a.attribute("data-testid", "foundations-intro")],
        [h.div([a.class("fh-hero-inner")], children)],
      )
    Content ->
      h.main(
        [
          a.id("content"),
          a.class("fh-ledger"),
          a.attribute("aria-labelledby", "fh-ledger-title"),
          a.attribute("data-testid", "foundations-ledger"),
        ],
        [
          h.div([a.class("fh-ledger-head")], children),
          h.ol(
            [a.class("fh-list"), a.attribute("data-testid", "foundations-list")],
            list.index_map(foundations.all(), doc),
          ),
        ],
      )
    Aside -> h.div([a.class("fh-aside")], children)
  }
}

pub fn view(children: List(Element(msg))) -> Element(msg) {
  sheet.view(
    "/foundations/",
    list.append(children, [ecosystem.view("/foundations/")]),
  )
}

fn doc(item: foundations.Doc, index: Int) -> Element(msg) {
  h.li([a.class("fh-item"), a.attribute("data-reveal", "rise")], [
    h.a([a.href("/foundations/" <> item.slug)], [
      h.span([a.class("fh-n annot")], [
        h.text(int.to_string(index + 1) |> pad_number),
      ]),
      h.span([a.class("fh-body")], [
        h.span([a.class("fh-title")], [h.text(item.title)]),
        h.span([a.class("fh-gloss")], [h.text(item.gloss)]),
        h.span([a.class("fh-concept annot")], [h.text(item.concept)]),
      ]),
      h.span([a.class("fh-go annot"), a.attribute("aria-hidden", "true")], [
        h.text("→"),
      ]),
    ]),
  ])
}

fn pad_number(number: String) -> String {
  case number {
    "1" -> "01"
    "2" -> "02"
    "3" -> "03"
    _ -> number
  }
}

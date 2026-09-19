import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/guide
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub type Component {
  Intro
  Content
  Build
  Document
  Procedure
  Companion
}

pub fn component(name: String) -> Result(Component, Nil) {
  case name {
    "guide-intro" -> Ok(Intro)
    "guide-content" -> Ok(Content)
    "guide-build" -> Ok(Build)
    "guide-document" -> Ok(Document)
    "guide-procedure" -> Ok(Procedure)
    "guide-companion" -> Ok(Companion)
    _ -> Error(Nil)
  }
}

pub fn component_view(
  component: Component,
  children: List(Element(msg)),
) -> Element(msg) {
  case component {
    Intro ->
      h.header([a.class("gi-hero"), a.attribute("data-testid", "guide-intro")], [
        h.div([a.class("gi-hero-inner")], children),
      ])
    Content ->
      h.main([a.id("content"), a.class("guide-index-content")], children)
    Build ->
      h.section(
        [
          a.class("gi-build"),
          a.attribute("aria-labelledby", "gi-build-title"),
          a.attribute("data-testid", "guide-build"),
        ],
        [
          h.div(
            [
              a.class("gi-build-inner"),
              a.attribute("data-testid", "guide-build-grid"),
            ],
            children,
          ),
        ],
      )
    Document -> document()
    Procedure ->
      h.section(
        [
          a.class("gi-ledger"),
          a.attribute("aria-labelledby", "gi-ledger-title"),
          a.attribute("data-testid", "guide-procedure"),
        ],
        [
          h.div([a.class("gi-ledger-head")], children),
          h.ol(
            [a.class("gi-steps"), a.attribute("data-testid", "guide-steps")],
            list.map(guide.all(), step),
          ),
        ],
      )
    Companion ->
      h.aside(
        [
          a.class("gi-companion"),
          a.attribute("aria-labelledby", "gi-companion-title"),
          a.attribute("data-testid", "guide-companion"),
        ],
        [h.div([], children)],
      )
  }
}

pub fn view(children: List(Element(msg))) -> Element(msg) {
  sheet.view("/guide/", list.append(children, [ecosystem.view("/guide/")]))
}

fn step(step: guide.Step) -> Element(msg) {
  h.li([a.class("gi-step"), a.attribute("data-reveal", "rise")], [
    h.a([a.href(guide.path(step.slug))], [
      h.span([a.class("gi-step-n annot")], [h.text(step.number)]),
      h.text(" "),
      h.span([a.class("gi-step-body")], [
        h.span([a.class("gi-step-title")], [h.text(step.title)]),
        h.text(" "),
        h.span([a.class("gi-step-goal")], [h.text(step.goal)]),
        h.text(" "),
        h.span([a.class("gi-step-surface annot")], [h.text(step.surface)]),
      ]),
      h.text(" "),
      h.span([a.class("gi-step-go annot"), a.attribute("aria-hidden", "true")], [
        h.text("→"),
      ]),
    ]),
  ])
}

fn document() -> Element(msg) {
  h.figure(
    [
      a.class("gi-doc"),
      a.attribute("aria-label", "The retro board document shape"),
      a.attribute("data-testid", "guide-document"),
    ],
    [
      h.figcaption([a.class("annot")], [
        h.text("document · retro-tutorial"),
      ]),
      h.ul(
        [a.class("gi-doc-tree")],
        list.map(
          [
            #("title", "String field → the board's name", ""),
            #("notes", "OR-map · RegisterMode → note id to whole note", ""),
            #("votes", "OR-map · TallyMode → note id to signed total", ""),
            #("↯ focus", "presence → who's reading which note", "gi-doc-eph"),
          ],
          fn(row) {
            h.li([a.class(row.2)], [
              h.span([a.class("gi-key")], [h.text(row.0)]),
              h.span([a.class("gi-typ")], [h.text(row.1)]),
            ])
          },
        ),
      ),
    ],
  )
}

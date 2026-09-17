import gleam/int
import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/structures
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub type Component {
  Intro
}

pub fn component(name: String) -> Result(Component, Nil) {
  case name {
    "structures-intro" -> Ok(Intro)
    _ -> Error(Nil)
  }
}

pub fn component_view(
  component: Component,
  children: List(Element(msg)),
) -> Element(msg) {
  case component {
    Intro ->
      h.header([a.class("hub-hero")], [
        h.div([a.class("hub-hero-inner")], children),
      ])
  }
}

pub fn view(children: List(Element(msg))) -> Element(msg) {
  sheet.view(
    "/structures/",
    children
      |> list.append([families(), ecosystem.view("/structures/")]),
  )
}

fn families() -> Element(msg) {
  h.main(
    [a.id("content"), a.class("families")],
    structures.all()
      |> list.index_map(fn(family, index) {
        h.a(
          [
            a.class("family"),
            a.href("/structures/" <> family.slug),
            a.attribute("data-reveal", "rise"),
          ],
          [
            h.div([a.class("family-top")], [
              h.span([a.class("family-index annot")], [
                h.text("Family " <> pad_number(index + 1)),
              ]),
              h.h2([], [h.text(family.name)]),
              h.p([a.class("family-tagline")], [h.text(family.tagline)]),
            ]),
            h.ul(
              [a.class("family-list")],
              list.map(family.entries, fn(entry) {
                let kind = structures.kind_name(entry.kind)
                h.li([], [
                  h.code([], [h.text(entry.name)]),
                  h.span(
                    [
                      a.class("kind"),
                      a.attribute("data-kind", kind),
                    ],
                    [h.text(kind)],
                  ),
                ])
              }),
            ),
            h.span(
              [a.class("family-go annot"), a.attribute("aria-hidden", "true")],
              [h.text("Open family →")],
            ),
          ],
        )
      }),
  )
}

fn pad_number(number: Int) -> String {
  let value = int.to_string(number)
  case number < 10 {
    True -> "0" <> value
    False -> value
  }
}

import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/practice

pub fn view(path: String) -> Element(msg) {
  case practice.related_to(path) {
    [] -> element.none()
    notes ->
      h.aside([a.class("rfn"), a.attribute("aria-labelledby", "rfn-title")], [
        h.div([a.class("rfn-inner")], [
          h.h2([a.id("rfn-title")], [h.text("Field notes from the examples")]),
          h.p([a.class("rfn-lede")], [
            h.text(
              "How the checked-in examples handle the problems described on this page.",
            ),
          ]),
          h.ul(
            [a.class("rfn-list")],
            list.map(notes, fn(item) {
              h.li([], [
                h.a([a.href(practice.href(item))], [h.text(item.title)]),
                h.p([], [h.text(item.rule)]),
                h.span([a.class("annot")], [h.text(item.example_name)]),
              ])
            }),
          ),
        ]),
      ])
  }
}

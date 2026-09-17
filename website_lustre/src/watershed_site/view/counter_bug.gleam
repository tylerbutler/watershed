import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/counter_bug/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view() -> Element(Nil) {
  sheet.view("/counter-bug/", [
    hero(),
    h.main([], [
      h.div([a.id("counter-bug-mount")], [demo.static()]),
    ]),
    ecosystem.view("/counter-bug/"),
  ])
}

fn hero() -> Element(msg) {
  h.header([a.class("page-hero")], [
    h.div([a.class("page-hero-inner")], [
      h.p([a.class("eyebrow annot")], [
        h.a([a.href("/#demo")], [h.text("← watershed")]),
        h.text(" · SharedMap · a common miswiring"),
      ]),
      h.h1([], [
        h.text("A counter is not"),
        h.br([]),
        h.text("a "),
        h.em([], [h.text("map cell.")]),
      ]),
      h.p([a.class("lede")], [
        h.text(
          "SharedMap resolves each key to the write with the higher server sequence number. That gives every replica the same value, but it does not preserve read-modify-write intent. If two clients read the same count and each writes ",
        ),
        h.code([], [h.text("count + 1")]),
        h.text(
          ", both submit the same replacement value, and the later write adds nothing. Here it is, live, through watershed's compiled ",
        ),
        h.code([], [h.text("map_kernel")]),
        h.text("."),
      ]),
      h.div([a.class("cta-row")], [
        h.a([a.class("cta-quiet"), a.href("#counter-bug")], [
          h.text("See the bug ↓"),
        ]),
        h.a([a.class("cta-quiet"), a.href("/structures/counters")], [
          h.text("SharedCounter, the fix →"),
        ]),
      ]),
    ]),
  ])
}

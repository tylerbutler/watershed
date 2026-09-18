import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/sequence/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view() -> Element(Nil) {
  sheet.view("/sequence/", [
    h.header([a.class("page-hero")], [
      h.div([a.class("page-hero-inner")], [
        h.p([a.class("eyebrow annot")], [
          h.a([a.href("/structures/sequences")], [h.text("← Sequences")]),
          h.text(" · SharedSequence"),
        ]),
        h.h1([], [
          h.text("Stable identity"),
          h.br([]),
          h.em([], [h.text("beneath every index.")]),
        ]),
        h.p([a.class("lede")], [
          h.text(
            "An index only means something against one version of a list. SharedSequence gives every item a stable identity beneath its index: you say insert at 2 or move 4 to 1, but the delta that ships names the item, not the slot. Two surveyors can rearrange the same stretch of river at the same instant: moves follow their waypoint, concurrent inserts both land, and every replica converges on the same order. watershed's sequence_kernel models that identity and converges.",
          ),
        ]),
        h.div([a.class("cta-row")], [
          h.a([a.class("cta-quiet"), a.href("#route-demo")], [
            h.text("Jump to the demo ↓"),
          ]),
          h.text(" "),
          h.a(
            [
              a.class("cta-quiet"),
              a.href("https://github.com/tylerbutler/watershed"),
            ],
            [h.text("Read the source")],
          ),
        ]),
      ]),
    ]),
    h.main([], [demo.static()]),
    ecosystem.view("/sequence/"),
  ])
}

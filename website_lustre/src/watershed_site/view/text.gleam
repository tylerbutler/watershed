import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/text/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view() -> Element(Nil) {
  sheet.view("/text/", [
    h.header([a.class("page-hero")], [
      h.div([a.class("page-hero-inner")], [
        h.p([a.class("eyebrow annot")], [
          h.a([a.href("/structures/sequences")], [h.text("← Sequences")]),
          h.text(" · SharedText"),
        ]),
        h.h1([], [
          h.text("Graphemes keep"),
          h.br([]),
          h.em([], [h.text("their place.")]),
        ]),
        h.p([a.class("lede")], [
          h.text(
            "A character offset only means something against one version of a string. The instant two people type in the same word, “index 6” names different characters on different screens. SharedText gives every grapheme a stable identity beneath its index: you say insert at 6 or replace 0..5, but the delta that ships names the graphemes, not the offsets. Two people can type into the same word at once: concurrent inserts both land, overlapping edits merge, and every replica converges on the same text. Indexing is by grapheme, never UTF-16 code unit, so an emoji or a combining accent is one indivisible character. watershed's text_kernel models that identity and converges.",
          ),
        ]),
        h.div([a.class("cta-row")], [
          h.a([a.class("cta-quiet"), a.href("#text-demo")], [
            h.text("Jump to the demo ↓"),
          ]),
          h.a([a.class("cta-quiet"), a.href("/rich-text")], [
            h.text("Compare SharedRichText →"),
          ]),
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
    h.main([], [h.div([a.id("text-mount")], [demo.static()])]),
    ecosystem.view("/text/"),
  ])
}

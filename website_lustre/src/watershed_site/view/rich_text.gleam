import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/rich_text/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view() -> Element(Nil) {
  sheet.view("/rich-text/", [
    hero(),
    h.main([], [h.div([a.id("rich-text-mount")], [demo.static()])]),
    ecosystem.view("/rich-text/"),
  ])
}

fn hero() -> Element(msg) {
  h.header([a.class("page-hero")], [
    h.div([a.class("page-hero-inner")], [
      h.p([a.class("eyebrow annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" · SharedRichText operational transform"),
      ]),
      h.h1([], [
        h.text("Transform edits,"),
        h.br([]),
        h.em([], [h.text("preserve intent.")]),
      ]),
      h.p([a.class("lede")], [
        h.code([], [h.text("json_ot")]),
        h.text(
          " transforms a shared JSON document; this is the same protocol turned on rich text. watershed's rich_text_kernel ports the quill-delta algebra (retain/insert/delete spans, attribute patches, embeds) behind the same single-op-in-flight client-transform machinery. Three Quill editors share one document with concurrent typing, formatting, and deletion, and transformed deltas bring every replica to the same text, formatting, and embeds. SharedRichText is OT-backed; the CRDT-backed ",
        ),
        h.a([a.href("/text")], [
          h.code([], [h.text("SharedText")]),
        ]),
        h.text(
          " handles plain text with grapheme identities and merge-based convergence.",
        ),
      ]),
      h.div([a.class("cta-row")], [
        h.a([a.class("cta-quiet"), a.href("#rt-demo")], [
          h.text("Jump to the demo ↓"),
        ]),
        h.text(" "),
        h.a([a.class("cta-quiet"), a.href("/text")], [
          h.text("Compare SharedText →"),
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
  ])
}

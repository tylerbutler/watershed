import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/json_ot/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view() -> Element(Nil) {
  sheet.view("/json-ot/", [
    hero(),
    h.main([], [demo.static()]),
    ecosystem.view("/json-ot/"),
  ])
}

fn hero() -> Element(msg) {
  h.header([a.class("page-hero")], [
    h.div([a.class("page-hero-inner")], [
      h.p([a.class("eyebrow annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" · JSON operational transform"),
      ]),
      h.h1([], [
        h.text("One document."),
        h.br([]),
        h.text("Concurrent edits. "),
        h.em([], [h.text("One order.")]),
      ]),
      h.p([a.class("lede")], [
        h.text("The homepage starts with "),
        h.code([], [h.text("SharedMap")]),
        h.text(
          ": the server orders its operations, then the map resolves each key by that order. JSON OT also uses a sequencer, but concurrent document operations are transformed against one another instead of resolved per key. watershed's json_ot kernel is a faithful port of the ottypes json0 algebra with the single-op-in-flight client protocol. Every client edits a shared JSON document optimistically, a central server sequences each op, and concurrent ops are transformed past one another. All replicas reach the same state, indices and all.",
        ),
      ]),
      h.div([a.class("cta-row")], [
        h.a([a.class("cta-quiet"), a.href("#jot-demo")], [
          h.text("Jump to the demo ↓"),
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
  ])
}

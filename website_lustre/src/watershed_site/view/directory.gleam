import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/directory/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view() -> Element(Nil) {
  sheet.view("/directory/", [
    hero(),
    h.main([], [h.div([a.id("directory-mount")], [demo.static()])]),
    ecosystem.view("/directory/"),
  ])
}

fn hero() -> Element(msg) {
  h.header([a.class("page-hero")], [
    h.div([a.class("page-hero-inner")], [
      h.p([a.class("eyebrow annot")], [
        h.a([a.href("/structures/maps")], [h.text("← Maps")]),
        h.text(" · SharedDirectory"),
      ]),
      h.h1([], [
        h.text("Folder identity"),
        h.br([]),
        h.em([], [h.text("survives the race.")]),
      ]),
      h.p([a.class("lede")], [
        h.a([a.href("/structures/maps")], [h.text("SharedMap")]),
        h.text(" resolves a flat set of keys. "),
        h.strong([], [h.text("SharedDirectory")]),
        h.text(
          " is the recursive version: a map at every node plus named child folders, modeled after Fluid Framework's design. The hard part is ",
        ),
        h.em([], [h.text("hierarchical identity")]),
        h.text(
          ", not storage. A folder can be created by two clients at once, deleted, and recreated under the same path, and every replica must still agree on which folder is which. watershed's ",
        ),
        h.code([], [h.text("directory_kernel")]),
        h.text(" models that identity explicitly and converges."),
      ]),
      h.div([a.class("cta-row")], [
        h.a([a.class("cta-quiet"), a.href("#dir-demo")], [
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

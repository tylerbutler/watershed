import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/sudoku/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view() -> Element(Nil) {
  sheet.view("/sudoku/", [
    hero(),
    h.main([], [
      h.div([a.id("sudoku-mount")], [static_demo()]),
    ]),
    ecosystem.view("/sudoku/"),
  ])
}

pub fn static_demo() -> Element(Nil) {
  demo.static()
}

fn hero() -> Element(msg) {
  h.header([a.class("page-hero")], [
    h.div([a.class("page-hero-inner")], [
      h.p([a.class("eyebrow annot")], [
        h.a([a.href("/structures/maps")], [h.text("← Maps")]),
        h.text(" · SharedMap Sudoku cells"),
      ]),
      h.h1([], [
        h.text("One board."),
        h.br([]),
        h.text("Three clients. "),
        h.em([], [h.text("One cell value.")]),
      ]),
      h.p([a.class("lede")], [
        h.text("The full "),
        h.a(
          [
            a.href(
              "https://github.com/tylerbutler/watershed/tree/main/examples/sudoku_lustre",
            ),
          ],
          [h.text("Sudoku example")],
        ),
        h.text(" layers "),
        h.strong([], [h.text("SharedMap")]),
        h.text(
          " cell values with SharedOrSet pencil notes, SharedClaims givens, SharedCounter mistakes, and ephemeral signals for presence. This page isolates the cell layer: keys like ",
        ),
        h.code([], [h.text("r0c0")]),
        h.text(
          " hold JSON digits, clears delete the key, and server-sequenced last-write-wins order makes concurrent edits converge.",
        ),
      ]),
      h.div([a.class("cta-row")], [
        h.a([a.class("cta-quiet"), a.href("#sudoku-demo")], [
          h.text("Jump to the demo ↓"),
        ]),
        h.a(
          [
            a.class("cta-quiet"),
            a.href(
              "https://github.com/tylerbutler/watershed/tree/main/examples/sudoku_lustre",
            ),
          ],
          [h.text("Read the full example")],
        ),
      ]),
    ]),
  ])
}

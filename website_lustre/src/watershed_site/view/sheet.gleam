import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h

pub fn active(path: String, match: String) -> Bool {
  path == match || string.starts_with(path, match <> "/")
}

pub fn view(path: String, children: List(Element(msg))) -> Element(msg) {
  element.fragment([
    h.a([a.class("skip-link"), a.href("#content")], [h.text("Skip to content")]),
    h.header([a.class("sheet-index")], [
      h.a([a.class("si-mark"), a.href("/"), ..current(path == "/")], [
        h.span([a.class("si-name")], [h.text("watershed")]),
        h.span([a.class("si-tag annot")], [
          h.text("Collaborative data structures for Gleam"),
        ]),
      ]),
      h.nav(
        [a.class("si-nav"), a.attribute("aria-label", "Sheet index")],
        list.map(
          [
            #("Atlas", "/structures"),
            #("Foundations", "/foundations"),
            #("Guide", "/guide"),
            #("Examples", "/examples"),
            #("Models", "/models"),
            #("Runtime", "/runtime"),
          ],
          fn(item) {
            h.a(
              [
                a.href(item.1),
                a.class("si-link annot"),
                ..current(active(path, item.1))
              ],
              [h.text(item.0)],
            )
          },
        )
          |> list.append([
            h.a(
              [
                a.class("si-link si-link-out annot"),
                a.href("https://github.com/tylerbutler/watershed"),
              ],
              [
                h.text("Source "),
                h.span([a.attribute("aria-hidden", "true")], [h.text("↗")]),
              ],
            ),
          ]),
      ),
    ]),
    h.div(
      [a.class("sheet")],
      list.map(["tl", "tr", "bl", "br"], fn(corner) {
        h.span(
          [a.class("reg reg-" <> corner), a.attribute("aria-hidden", "true")],
          [],
        )
      })
        |> list.append(children),
    ),
    h.div(
      [
        a.class("margin-row margin-bottom annot"),
        a.attribute("aria-hidden", "true"),
      ],
      [
        h.span([], [h.text("Magenta indicates revisions not yet field-checked")]),
        h.span([a.class("margin-mid")], [
          h.text(
            "Convergence by server sequencing — assumptions on the models sheet",
          ),
        ]),
        h.span([], [h.text("tylerbutler.com")]),
      ],
    ),
  ])
}

pub fn current(active: Bool) -> List(a.Attribute(msg)) {
  case active {
    True -> [a.attribute("aria-current", "page")]
    False -> []
  }
}

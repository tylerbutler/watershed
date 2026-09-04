import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/guide
import watershed_site/view/sheet

type Column {
  Column(title: String, href: String, links: List(#(String, String)))
}

pub fn view(path: String) -> Element(msg) {
  h.nav(
    [a.class("adjoining"), a.attribute("aria-labelledby", "adjoining-title")],
    [
      h.div([a.class("adjoining-inner")], [
        h.div([a.class("adjoining-head")], [
          h.h2([a.id("adjoining-title"), a.class("annot")], [
            h.text("Adjoining sheets"),
          ]),
          h.p([a.class("annot")], [
            h.text("The full index: every sheet in the survey"),
          ]),
        ]),
        h.div(
          [a.class("adjoining-grid")],
          list.map(columns(), fn(column) {
            h.div([a.class("adj-col")], [
              h.a([a.class("adj-col-title annot"), a.href(column.href)], [
                h.text(column.title),
              ]),
              h.ul(
                [],
                list.index_map(column.links, fn(link, index) {
                  h.li([], [
                    h.a(
                      [
                        a.href(link.1),
                        a.class(case index {
                          0 -> "adj-link adj-link-hub"
                          _ -> "adj-link"
                        }),
                        ..sheet.current(path == link.1)
                      ],
                      [h.text(link.0)],
                    ),
                  ])
                }),
              ),
            ])
          }),
        ),
      ]),
    ],
  )
}

fn columns() -> List(Column) {
  [
    Column("Data structures", "/structures", [
      #("Field atlas", "/structures"),
      #("Counters", "/structures/counters"),
      #("Sets", "/structures/sets"),
      #("Maps", "/structures/maps"),
      #("Sequences", "/structures/sequences"),
      #("Coordination", "/structures/coordination"),
      #("Transforms", "/structures/transforms"),
    ]),
    Column("Foundations", "/foundations", [
      #("Overview", "/foundations"),
      #("Schemas and fields", "/foundations/schema"),
      #("Documents and handles", "/foundations/topology"),
      #("Starting a document", "/foundations/lifecycle"),
    ]),
    Column("Component model", "/component-model", [
      #("Overview", "/component-model"),
      #("Components and catalogs", "/component-model/components"),
      #("Ports and dispatch", "/component-model/ports"),
      #("Workspaces and instances", "/component-model/workspaces"),
    ]),
    Column("Build guide", "/guide", [
      #("Overview", "/guide"),
      ..list.map(guide.all(), fn(step) {
        #(step.number <> " · " <> step.title, guide.path(step.slug))
      })
    ]),
    Column("Runtime", "/runtime", [
      #("Behaviors", "/runtime"),
      #("Optimistic edits", "/runtime/optimistic"),
      #("Reconnect & resync", "/runtime/reconnect"),
      #("Idempotent re-delivery", "/runtime/redelivery"),
      #("Presence & ripples", "/runtime/presence"),
      #("Peer-to-peer over WebRTC", "/runtime/p2p"),
    ]),
    Column("Reference & demos", "/examples", [
      #("Browser examples", "/examples"),
      #("Patterns", "/patterns"),
      #("Convergence models", "/models"),
      #("SharedTree comparison", "/sharedtree"),
      #("The counter bug", "/counter-bug"),
      #("Shared directory", "/directory"),
      #("JsonOt", "/json-ot"),
      #("Rich text", "/rich-text"),
      #("Sudoku", "/sudoku"),
      #("Source ↗", "https://github.com/tylerbutler/watershed"),
    ]),
  ]
}

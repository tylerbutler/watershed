import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/view/adjoining_sheets

const repo = "https://github.com/tylerbutler/watershed"

const server = "https://floodgate.tylerbutler.com"

type Flow {
  Flow(
    label: String,
    source: #(String, String),
    verb: String,
    path: List(#(String, String)),
    target: #(String, String),
    note: String,
  )
}

pub fn view(path: String) -> Element(msg) {
  element.fragment([
    adjoining_sheets.view(path),
    h.footer([a.class("eco"), a.attribute("aria-labelledby", "eco-title")], [
      h.div([a.class("eco-inner")], [
        h.h2([a.id("eco-title")], [h.text("Packages and protocol boundaries")]),
        h.p([], [
          h.text(
            "The shared DDS core stays target-independent. These paths show which packages provide each target's transport and framing, and which protocol types cross the client/server boundary. floodgate is shown as the reference server; the same protocol also reaches levee and Fluid Framework's own routerlicious.",
          ),
        ]),
        h.ol(
          [
            a.class("flow-list"),
            a.attribute("aria-label", "Package relationships"),
          ],
          list.map(flows(), fn(flow) {
            h.li([a.class("flow-row")], [
              h.span([a.class("flow-label annot")], [h.text(flow.label)]),
              h.div([a.class("flow-line")], [
                link(flow.source),
                h.span([], [h.text(flow.verb)]),
                h.span(
                  [a.class("flow-path")],
                  list.map(flow.path, link) |> list.intersperse(arrow()),
                ),
                arrow(),
                link(flow.target),
              ]),
              h.p([], [h.text(flow.note)]),
            ])
          }),
        ),
        h.div([a.class("eco-take")], [
          h.p([a.class("annot eco-take-label")], [
            h.text("Take it into a project · Gleam ≥ 1.7"),
          ]),
          h.pre([a.class("dep-line")], [
            h.code([], [
              h.text(
                "[dependencies]\nwatershed = { git = \"https://github.com/tylerbutler/watershed\", ref = \"<commit-sha>\" }",
              ),
            ]),
          ]),
        ]),
        h.div([a.class("eco-close")], [
          h.a([a.class("cta-primary"), a.href(repo)], [
            h.text("Read the source"),
          ]),
          h.a([a.class("eco-star"), a.href(repo <> "/stargazers")], [
            h.text("★ Star the repo"),
          ]),
          h.span([a.class("annot")], [h.text("MIT · built by Tyler Butler")]),
        ]),
      ]),
    ]),
  ])
}

fn link(item: #(String, String)) -> Element(msg) {
  h.a([a.href(item.1)], [h.code([], [h.text(item.0)])])
}

fn arrow() -> Element(msg) {
  h.span([a.attribute("aria-hidden", "true")], [h.text("→")])
}

fn flows() -> List(Flow) {
  [
    Flow(
      "BEAM client",
      #("watershed", repo),
      "opens Phoenix channels with",
      [
        #("aquamarine", "https://aquamarine.tylerbutler.com"),
        #("roost", "https://github.com/tylerbutler/roost"),
      ],
      #("floodgate", server),
      "OTP runtime, Gun transport, Roost Phoenix V2 frame codec.",
    ),
    Flow(
      "Browser client",
      #("watershed", repo),
      "opens Phoenix channels with",
      [#("Phoenix.js", "https://hexdocs.pm/phoenix/js/")],
      #("floodgate", server),
      "Gleam JavaScript runtime over transport_js and the browser Web Crypto API.",
    ),
    Flow(
      "Protocol layer",
      #("watershed core", repo),
      "encodes document messages through",
      [#("spillway", "https://spillway.tylerbutler.com")],
      #("floodgate", server),
      "Shared operation, session, sequencing, and watershed summary types.",
    ),
    Flow(
      "Server side",
      #("floodgate", server),
      "hosts rooms and broadcasts through",
      [
        #("beryl", "https://beryl.tylerbutler.com"),
        #("dewdrop", "https://dewdrop.tylerbutler.com"),
      ],
      #("clients", repo),
      "Channel runtime plus adapters for sequenced service events.",
    ),
  ]
}

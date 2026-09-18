import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h

pub fn static() -> Element(Nil) {
  h.section(
    [
      a.id("jot-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "jot-demo-title"),
      test_id("json-ot-demo"),
    ],
    [
      h.div([a.class("demo-head"), a.attribute("data-reveal", "rise")], [
        h.h2([a.id("jot-demo-title")], [
          h.text("Operational transform, live"),
        ]),
        h.p([], [
          h.text("Three "),
          h.code([], [h.text("watershed")]),
          h.text(
            " documents share one JSON document over the ottypes json0 algebra with the single-op-in-flight client protocol. One client creates it and shares the handle; the others resolve it. They talk to one ",
          ),
          h.code([], [h.text("sluice")]),
          h.text(
            ", the in-memory server that ships in the library. It runs the production client runtime without a network backend. Optimistic edits are drawn in ",
          ),
          h.strong([a.class("k-pending")], [h.text("magenta")]),
          h.text("; server-sequenced state in "),
          h.strong([a.class("k-seq")], [h.text("ink")]),
          h.text("."),
        ]),
        h.p([a.class("demo-hint")], [
          h.text(
            "Nudge the gauge.stage reading or flip its trend, rename the site, add or remove a surveyor, reorder the crew, switch on jitter, then race two inserts at the same index. Ops address any depth: the gauge is nested inside an object, so a bump targets the path .gauge.stage. Numbers add commutatively; a rename is last-writer-by-sequencing; but the crew list is where OT earns its keep. Concurrent inserts have their indices transformed, so every replica converges to the same array (positions and all).",
          ),
        ]),
      ]),
      h.div(
        [
          a.class("rig"),
          a.attribute("data-jot-rig", ""),
          test_id("json-ot-rig"),
        ],
        [
          client("a", "Client A"),
          client("b", "Client B"),
          client("c", "Client C"),
          h.div([a.class("channel"), a.style("grid-area", "seq")], [
            h.div([a.class("seq-node"), a.attribute("data-seq-node", "")], [
              h.span([a.class("annot")], [h.text("Sequencer")]),
              h.output(
                [
                  a.class("seq-counter"),
                  a.attribute("data-seq-counter", ""),
                  a.attribute("aria-label", "Latest sequence number"),
                ],
                [h.text("SN 0")],
              ),
            ]),
            h.ol(
              [
                a.class("op-log"),
                a.attribute("data-op-log", ""),
                a.attribute("aria-live", "polite"),
                a.attribute("aria-label", "Sequenced operations, newest first"),
              ],
              [],
            ),
          ]),
          h.div(
            [
              a.class("flow-layer"),
              a.attribute("data-flow-layer", ""),
              a.attribute("aria-hidden", "true"),
            ],
            [],
          ),
        ],
      ),
      controls(),
      h.p([a.class("controls-hint")], [
        h.text(
          "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency.",
        ),
      ]),
      element.element("noscript", [], [
        h.p([a.class("demo-noscript"), test_id("noscript")], [
          h.text(
            "The live demo needs JavaScript: it runs the production client runtime and the in-memory sluice as compiled JavaScript in your browser. The rest of the page works fine without it.",
          ),
        ]),
      ]),
      h.p(
        [
          a.class("demo-noscript json-ot-fallback"),
          a.attribute("data-jot-fallback", ""),
          a.hidden(True),
          test_id("json-ot-fallback"),
        ],
        [
          h.text(
            "The live demo couldn't start: it runs the production client runtime against the in-memory sluice as compiled JavaScript, and this browser didn't load it. The rest of the page works fine without it.",
          ),
        ],
      ),
    ],
  )
}

fn client(id: String, label: String) -> Element(Nil) {
  h.article(
    [
      a.class("client"),
      a.attribute("data-client", id),
      a.attribute("aria-label", label <> " replica"),
      a.style("grid-area", id),
      test_id("client-" <> id),
    ],
    [
      h.header([a.class("client-head")], [
        h.h3([], [h.text(label)]),
        h.span(
          [
            a.class("pending-count annot"),
            a.attribute("data-pending-count", ""),
          ],
          [h.text("0 pending")],
        ),
      ]),
      h.div(
        [
          a.class("doc"),
          a.role("group"),
          a.attribute("aria-label", label <> " JSON document"),
        ],
        [
          h.span([a.class("jp brace")], [h.text("{")]),
          row("crew", [
            h.span([a.class("jkey")], [h.text("\"crew\"")]),
            h.span([a.class("jp colon")], [h.text(": ")]),
            h.span([a.class("jp bracket")], [h.text("[")]),
            h.ul(
              [
                a.class("crew"),
                a.attribute("data-crew", ""),
                a.attribute("aria-label", "crew array on " <> label),
              ],
              [],
            ),
            h.span([a.class("jp bracket")], [h.text("]")]),
            h.span([a.class("jp comma")], [h.text(" ,")]),
            button(
              "+ surveyor",
              "Add a surveyor to crew on " <> label,
              "data-crew-add",
            ),
          ]),
          h.div([a.class("jrow jrow-open"), a.attribute("data-node", "gauge")], [
            h.span([a.class("jkey")], [h.text("\"gauge\"")]),
            h.span([a.class("jp colon")], [h.text(": ")]),
            h.span([a.class("jp brace")], [h.text("{")]),
          ]),
          h.div([a.class("jnest")], [
            field_row("gauge.stage", "\"stage\"", "24", "num", False, True, [
              button("−", "Lower stage on " <> label, "data-stage-dec"),
              button("+", "Raise stage on " <> label, "data-stage-inc"),
            ]),
            field_row("gauge.trend", "\"trend\"", "steady", "", True, False, [
              button(
                "cycle",
                "Cycle the gauge trend on " <> label,
                "data-trend-cycle",
              ),
            ]),
          ]),
          h.div(
            [a.class("jrow jrow-close"), a.attribute("data-node", "gauge")],
            [
              h.span([a.class("jp brace")], [h.text("}")]),
              h.span([a.class("jp comma")], [h.text(" ,")]),
            ],
          ),
          field_row("site", "\"site\"", "Mill Race", "", True, False, [
            button("rename", "Rename the site on " <> label, "data-site-cycle"),
          ]),
          h.span([a.class("jp brace")], [h.text("}")]),
        ],
      ),
    ],
  )
}

fn row(field: String, children: List(Element(Nil))) -> Element(Nil) {
  h.div(
    [
      a.class("jrow crew-row"),
      a.attribute("data-field", field),
      a.attribute("data-node", field),
    ],
    children,
  )
}

fn field_row(
  field: String,
  key: String,
  value: String,
  extra: String,
  quoted: Bool,
  comma: Bool,
  actions: List(Element(Nil)),
) -> Element(Nil) {
  h.div(
    [
      a.class("jrow"),
      a.attribute("data-field", field),
      a.attribute("data-node", field),
    ],
    [
      h.span([a.class("jkey")], [h.text(key)]),
      h.span([a.class("jp colon")], [h.text(": ")]),
      h.span(
        case quoted {
          True -> [a.class("jstr")]
          False -> []
        },
        [
          case quoted {
            True -> h.span([a.class("jp quote")], [h.text("\"")])
            False -> h.text("")
          },
          h.span(
            [
              a.class(
                "field-value"
                <> case extra {
                  "" -> ""
                  _ -> " " <> extra
                },
              ),
              a.attribute("data-value", ""),
            ],
            [h.text(value)],
          ),
          case quoted {
            True -> h.span([a.class("jp quote")], [h.text("\"")])
            False -> h.text("")
          },
        ],
      ),
      case comma {
        True -> h.span([a.class("jp comma")], [h.text(" ,")])
        False -> h.text("")
      },
      h.span([a.class("node-action-group")], actions),
    ],
  )
}

fn button(label: String, aria: String, attribute: String) -> Element(Nil) {
  h.button(
    [
      a.type_("button"),
      a.class("node-action"),
      a.attribute(attribute, ""),
      a.attribute("aria-label", aria),
      a.disabled(True),
    ],
    [h.text(label)],
  )
}

fn controls() -> Element(Nil) {
  h.div([a.class("demo-controls"), a.attribute("data-reveal", "rise")], [
    h.label([a.class("pace")], [
      h.span([a.class("annot")], [h.text("Animation speed")]),
      h.input([
        a.type_("range"),
        a.min("0.25"),
        a.max("2"),
        a.step("0.25"),
        a.value("1"),
        a.attribute("data-jot-pace", ""),
        a.title("Playback only; does not affect simulated ordering."),
        a.disabled(True),
      ]),
      h.output([a.attribute("data-jot-pace-out", "")], [h.text("1×")]),
    ]),
    h.label([a.class("field-notes-toggle")], [
      h.input([
        a.type_("checkbox"),
        a.attribute("data-jot-latency-variance", ""),
        a.title("Add random ±100 ms per hop; arrival order may change."),
        a.disabled(True),
      ]),
      h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
    ]),
    h.button(
      [
        a.type_("button"),
        a.class("race-btn"),
        a.attribute("data-jot-race", ""),
        a.disabled(True),
      ],
      [h.text("Race two inserts at index 0")],
    ),
    h.button(
      [
        a.type_("button"),
        a.class("reset-btn"),
        a.attribute("data-jot-reset", ""),
        a.attribute("aria-label", "Reset the document to its surveyed baseline"),
        a.disabled(True),
      ],
      [h.text("Reset survey")],
    ),
    h.p(
      [
        a.class("status"),
        a.attribute("data-jot-status", ""),
        a.role("status"),
      ],
      [
        h.span([a.class("stamp converged")], [h.text("Converged")]),
        h.text(" replicas identical · nothing pending"),
      ],
    ),
  ])
}

fn test_id(id: String) -> a.Attribute(msg) {
  a.attribute("data-testid", id)
}

import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h

pub fn static() -> Element(Nil) {
  h.section(
    [
      a.id("route-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "route-demo-title"),
    ],
    [
      h.div([a.class("demo-head"), a.attribute("data-reveal", "rise")], [
        h.h2([a.id("route-demo-title")], [
          h.text("A shared portage route, live"),
        ]),
        h.p([], [
          h.text(
            "Three watershed documents share one SharedSequence, an ordered list of waypoints down a river. One client creates it and shares the handle; the others resolve it. They talk to one sluice, the in-memory server that ships in the library. It runs the production client runtime without a network backend. Local edits are drawn in magenta until the sluice stamps them; server-sequenced state is ink.",
          ),
        ]),
        h.p([a.class("demo-hint")], [
          h.text(
            "Select a station to move, rename, or delete it, or press + between stations to insert one. Then stage a race: Race a move has B and C drag the same waypoint opposite ways; Crowd an insert has them insert different waypoints at the same spot. Both converge: a move follows its waypoint and concurrent inserts both survive, because ops name items, not index numbers.",
          ),
        ]),
      ]),
      h.p(
        [
          a.class("field-note"),
          a.attribute("data-route-note", ""),
          a.attribute("role", "note"),
          a.hidden(True),
        ],
        [],
      ),
      h.div([a.class("rig"), a.attribute("data-route-rig", "")], [
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
      ]),
      controls(),
      h.p([a.class("controls-hint")], [
        h.text(
          "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency.",
        ),
      ]),
      h.noscript([], [
        h.p(
          [
            a.class("demo-noscript"),
            a.attribute("data-testid", "noscript"),
          ],
          [
            h.text(
              "The live demo needs JavaScript: it runs the production client runtime and the in-memory sluice as compiled JavaScript in your browser. The rest of the page works fine without it.",
            ),
          ],
        ),
      ]),
      h.p(
        [
          a.class("demo-noscript"),
          a.attribute("data-route-fallback", ""),
          a.attribute("data-testid", "sequence-fallback"),
          a.hidden(True),
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
          a.class("route"),
          a.attribute("data-route", ""),
          a.attribute("aria-label", label <> " route"),
        ],
        [],
      ),
      h.div([a.class("route-actions"), a.attribute("data-route-actions", "")], [
        h.span(
          [a.class("selected-label annot"), a.attribute("data-selected", "")],
          [
            h.text("select a station"),
          ],
        ),
        action("up", "↑", "Move the selected waypoint upstream on " <> label),
        action(
          "down",
          "↓",
          "Move the selected waypoint downstream on " <> label,
        ),
        action("rename", "✎", "Rename the selected waypoint on " <> label),
        action("delete", "×", "Delete the selected waypoint on " <> label),
      ]),
    ],
  )
}

fn action(name: String, glyph: String, label: String) -> Element(Nil) {
  h.button(
    [
      a.type_("button"),
      a.class("node-action"),
      a.attribute("data-act", name),
      a.attribute("aria-label", label),
      a.title(label),
      a.disabled(True),
    ],
    [h.text(glyph)],
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
        a.attribute("data-route-pace", ""),
        a.title("Playback only; does not affect simulated ordering."),
        a.disabled(True),
      ]),
      h.output([a.attribute("data-route-pace-out", "")], [h.text("1×")]),
    ]),
    toggle("data-route-latency-variance", "Jitter ±100 ms"),
    toggle("data-route-notes", "Field notes"),
    button("race-btn", "data-route-race-move", "Race a move"),
    button("race-btn", "data-route-race-insert", "Crowd an insert"),
    button("reset-btn", "data-route-reset", "Reset"),
    h.p(
      [
        a.class("status"),
        a.attribute("data-route-status", ""),
        a.attribute("role", "status"),
      ],
      [
        h.span([a.class("stamp converged")], [h.text("Converged")]),
        h.text(" all routes identical · nothing pending"),
      ],
    ),
  ])
}

fn toggle(attribute: String, label: String) -> Element(Nil) {
  h.label([a.class("field-notes-toggle")], [
    h.input([
      a.type_("checkbox"),
      a.attribute(attribute, ""),
      a.disabled(True),
    ]),
    h.span([a.class("annot")], [h.text(label)]),
  ])
}

fn button(class: String, attribute: String, label: String) -> Element(Nil) {
  h.button(
    [
      a.type_("button"),
      a.class(class),
      a.attribute(attribute, ""),
      a.disabled(True),
    ],
    [h.text(label)],
  )
}

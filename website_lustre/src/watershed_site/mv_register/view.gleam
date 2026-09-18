import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h

pub fn static() -> Element(Nil) {
  h.section(
    [
      a.id("demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "demo-title"),
    ],
    [
      h.a([a.class("demo-skip"), a.href("#after-demo")], [
        h.text("Skip past the interactive demo"),
      ]),
      h.div([a.class("demo-head")], [
        h.h2([a.id("demo-title")], [
          h.text("One slate, three field crews"),
        ]),
        h.div([a.class("demo-head-grid")], [
          h.div([a.class("demo-intro")], [
            h.p([], [
              h.text(
                "Confirmed alternatives stay in ink; your pending revision appears in magenta. Cut Client B's link, write on both sides, then restore it. Agreement means every crew sees the same alternatives, not necessarily a single answer.",
              ),
            ]),
            h.p([], [
              h.text(
                "Re-deliver keeps an earlier delta even after resolution. The old revision stays retired. Reset tears off a fresh slate and discards delayed work from the previous one.",
              ),
            ]),
          ]),
          h.ol(
            [
              a.class("demo-legend annot"),
              a.attribute("aria-label", "How an edit converges"),
            ],
            [
              h.li([], [
                h.span([a.class("k-pending")], [
                  h.text("1 · local edit"),
                ]),
                h.text(" prints in magenta"),
              ]),
              h.li([], [
                h.span([a.class("k-flow")], [
                  h.text("2 · the sequencer"),
                ]),
                h.text(" stamps it with an SN"),
              ]),
              h.li([], [
                h.span([a.class("k-seq")], [
                  h.text("3 · every client"),
                ]),
                h.text(" lands the same ink state"),
              ]),
            ],
          ),
        ]),
      ]),
      h.p(
        [
          a.class("merge-rule"),
          a.attribute("data-merge-rule", "mv-register"),
        ],
        [
          h.strong([], [h.text("Merge rule: keep concurrent alternatives.")]),
          h.text(
            " Two revisions can converge without agreeing on one answer. After both arrive, write a combined revision to replace the alternatives you've seen.",
          ),
        ],
      ),
      h.p([a.attribute("data-ormap-tally-note", ""), a.hidden(True)], []),
      h.p([a.attribute("data-ormap-set-note", ""), a.hidden(True)], []),
      h.div([a.class("field-notes-row")], [
        h.label([a.class("field-notes-toggle")], [
          h.input([
            a.type_("checkbox"),
            a.attribute("data-field-notes", ""),
            a.attribute("aria-describedby", "field-notes-help"),
            a.disabled(True),
          ]),
          h.span([a.class("field-note-tip")], [
            h.span([a.class("annot")], [h.text("Field notes")]),
            h.span(
              [
                a.class("field-note-mark"),
                a.attribute("aria-hidden", "true"),
              ],
              [h.text("?")],
            ),
            h.span(
              [
                a.class("field-note-tooltip"),
                a.id("field-notes-help"),
                a.attribute("role", "tooltip"),
              ],
              [
                h.text(
                  "Show hand-drawn annotations as edits move from pending to sequenced.",
                ),
              ],
            ),
          ]),
        ]),
      ]),
      h.div(
        [
          a.class("rig"),
          a.attribute("data-demo-rig", ""),
          a.attribute("data-dds", "mv-register"),
          a.attribute("data-views", "mv-register"),
        ],
        [
          client("a", "Client A", "raise crest"),
          client("b", "Client B", "arm pump"),
          client("c", "Client C", "check datum"),
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
        h.span([], [
          h.text(
            "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency. “Ops in flight” counts every hop still travelling: one client → sequencer leg, then one sequencer → replica leg per client.",
          ),
        ]),
      ]),
      h.noscript([], [
        h.p(
          [
            a.class("demo-noscript"),
            a.attribute("data-testid", "noscript"),
          ],
          [
            h.text(
              "The live demo needs JavaScript: it runs watershed's actual ",
            ),
            h.code([], [h.text("mv_register_kernel")]),
            h.text(
              " in your browser. The rest of the page works fine without it.",
            ),
          ],
        ),
      ]),
      h.p(
        [
          a.class("demo-noscript"),
          a.attribute("data-demo-fallback", ""),
          a.attribute("data-testid", "mv-register-fallback"),
          a.hidden(True),
        ],
        [
          h.text(
            "The live demo couldn't start: it runs watershed's kernels as compiled JavaScript modules, and this browser didn't load them. The rest of the page works fine without it. ",
          ),
          h.a([a.href("")], [h.text("Reload the page to retry.")]),
        ],
      ),
    ],
  )
}

fn client(id: String, label: String, revision: String) -> Element(Nil) {
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
        case id {
          "b" ->
            h.button(
              [
                a.type_("button"),
                a.class("link-btn"),
                a.attribute("data-cut-link", ""),
                a.attribute("aria-pressed", "false"),
                a.title(
                  "Sever this replica's link to the sequencer; its edits park locally until the link is restored",
                ),
                a.disabled(True),
              ],
              [h.text("Cut link")],
            )
          _ -> h.text("")
        },
        h.span(
          [
            a.class("pending-count annot"),
            a.attribute("data-pending-count", ""),
            a.attribute("data-live", id),
          ],
          [h.text("0 pending")],
        ),
      ]),
      case id {
        "b" ->
          h.p(
            [
              a.class("annot link-note"),
              a.attribute("data-link-note", ""),
              a.hidden(True),
            ],
            [
              h.text("link cut — ops park locally until the link is restored"),
            ],
          )
        _ -> h.text("")
      },
      h.div([a.class("mv-register-panel dds-mv-register")], [
        h.h3([a.class("annot")], [h.text("Revision slate")]),
        h.p([a.class("annot")], [h.text("Confirmed alternatives")]),
        h.output(
          [
            a.class("mv-alternatives k-seq"),
            a.attribute("data-mv-register-confirmed", ""),
            a.attribute("aria-live", "polite"),
            a.attribute(
              "aria-label",
              "Confirmed MV register alternatives on " <> label,
            ),
          ],
          [h.text("[\"Survey datum\"]")],
        ),
        h.p([a.class("annot")], [h.text("Local view")]),
        h.output(
          [
            a.class("mv-alternatives"),
            a.attribute("data-mv-register-values", ""),
            a.attribute("aria-live", "polite"),
            a.attribute(
              "aria-label",
              "Local MV register alternatives on " <> label,
            ),
          ],
          [h.text("[\"Survey datum\"]")],
        ),
        h.label([a.class("annot"), a.attribute("for", "mv-revision-" <> id)], [
          h.text("Next revision"),
        ]),
        h.input([
          a.id("mv-revision-" <> id),
          a.attribute("data-mv-register-input", ""),
          a.value(revision),
          a.disabled(True),
        ]),
        h.div([a.class("mv-actions")], [
          h.button(
            [
              a.type_("button"),
              a.attribute("data-mv-register-write", ""),
              a.disabled(True),
            ],
            [h.text("Write revision")],
          ),
          h.button(
            [
              a.type_("button"),
              a.attribute("data-mv-register-resolve", ""),
              a.disabled(True),
            ],
            [h.text("Resolve with both")],
          ),
        ]),
        h.p([a.class("mv-hint")], [
          h.text(
            "Resolve writes \"raise crest + arm pump\". Any new revision replaces only the history this client has seen.",
          ),
        ]),
      ]),
      h.div([a.hidden(True)], [
        h.input([a.attribute("data-ormap-set-input", "")]),
        h.input([a.attribute("data-ormap-key", "")]),
        h.input([a.attribute("data-or-map-mv-register-key", "")]),
        h.input([a.attribute("data-or-map-mv-register-input", "")]),
        h.input([a.attribute("data-lww-map-key", "")]),
        h.input([a.attribute("data-lww-map-input", "")]),
        h.input([a.attribute("data-lww-register-input", "")]),
      ]),
    ],
  )
}

fn controls() -> Element(Nil) {
  h.div([a.class("demo-controls")], [
    h.label([a.class("pace")], [
      h.span([a.class("annot")], [h.text("Animation speed")]),
      h.input([
        a.type_("range"),
        a.min("0.25"),
        a.max("2"),
        a.step("0.25"),
        a.value("1"),
        a.attribute("data-pace", ""),
        a.title("Playback only; does not affect simulated ordering."),
        a.disabled(True),
      ]),
      h.output([a.attribute("data-pace-out", "")], [h.text("1×")]),
    ]),
    h.label([a.class("field-notes-toggle")], [
      h.input([
        a.type_("checkbox"),
        a.attribute("data-latency-variance", ""),
        a.title("Add random ±100 ms per hop; arrival order may change."),
        a.disabled(True),
      ]),
      h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
    ]),
    h.button(
      [
        a.type_("button"),
        a.class("race-btn"),
        a.attribute("data-race", ""),
        a.disabled(True),
      ],
      [h.text("Race a concurrent write")],
    ),
    h.button(
      [
        a.type_("button"),
        a.class("race-btn"),
        a.attribute("data-replay", ""),
        a.attribute(
          "aria-label",
          "Deliver the most recently sequenced delta a second time to every replica",
        ),
        a.hidden(True),
        a.disabled(True),
      ],
      [h.text("Re-deliver last delta")],
    ),
    h.button(
      [
        a.type_("button"),
        a.class("reset-btn"),
        a.attribute("data-reset", ""),
        a.attribute(
          "aria-label",
          "Reset all revisions to their surveyed baseline values",
        ),
        a.disabled(True),
      ],
      [h.text("Reset survey")],
    ),
    h.p(
      [
        a.class("status"),
        a.attribute("data-status", ""),
        a.attribute("role", "status"),
      ],
      [
        h.span([a.class("stamp booting")], [h.text("Loading")]),
        h.text(" booting watershed kernels…"),
      ],
    ),
  ])
}

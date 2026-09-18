import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h

pub fn static() -> Element(Nil) {
  h.section(
    [
      a.id("rt-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "rt-demo-title"),
    ],
    [
      h.div([a.class("demo-head"), a.attribute("data-reveal", "rise")], [
        h.h2([a.id("rt-demo-title")], [h.text("SharedRichText, live")]),
        h.p([], [
          h.text(
            "Three watershed documents share one rich-text channel over the rich_text_kernel. It runs the same single-op-in-flight client-transform protocol as the ",
          ),
          h.a([a.href("/json-ot")], [h.text("json_ot demo")]),
          h.text(
            ", but over quill-delta's algebra: operations retain, insert, or delete spans of text. Each op can carry an attribute patch (bold, color, …) or wrap an embed (an image) instead of plain text. Positions are counted in UTF-16 code units (the units Quill and JavaScript strings index by), so nothing converts at the editor boundary. Each editor keeps at most one op in flight; anything typed while it's outstanding composes into a single buffered op behind it. This is SharedRichText, watershed's OT-backed rich text. For CRDT-backed plain text, ",
          ),
          h.a([a.href("/text")], [
            h.code([], [h.text("SharedText")]),
          ]),
          h.text(
            " indexes graphemes by stable identity and converges by merge rather than by transform.",
          ),
        ]),
        h.p([a.class("demo-hint")], [
          h.text(
            "Local edits apply the instant you type, Quill's own optimistic model, no different from typing into any editor. Race two clients at the same spot, format concurrently, or delete under someone else's formatting, then watch the op log and the canonical text below each editor converge. Peer cursors (dashed, colored) track where the other two are looking, transformed through every edit exactly like the local caret is.",
          ),
        ]),
      ]),
      h.div([a.class("rig"), a.attribute("data-rt-rig", "")], [
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
              a.attribute("aria-label", "Sequenced rich-text ops, newest first"),
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
      h.div([a.class("demo-controls"), a.attribute("data-reveal", "rise")], [
        h.label([a.class("pace")], [
          h.span([a.class("annot")], [h.text("Animation speed")]),
          h.input([
            a.type_("range"),
            a.min("0.25"),
            a.max("2"),
            a.step("0.25"),
            a.value("1"),
            a.attribute("data-rt-pace", ""),
            a.title("Playback only; does not affect simulated ordering."),
            a.disabled(True),
          ]),
          h.output([a.attribute("data-rt-pace-out", "")], [h.text("1×")]),
        ]),
        h.label([a.class("field-notes-toggle")], [
          h.input([
            a.type_("checkbox"),
            a.attribute("data-rt-latency-variance", ""),
            a.title("Add random ±100 ms per hop; arrival order may change."),
            a.disabled(True),
          ]),
          h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
        ]),
        h.p(
          [
            a.class("status"),
            a.attribute("data-rt-status", ""),
            a.attribute("role", "status"),
          ],
          [
            h.span([a.class("stamp converged")], [h.text("Converged")]),
            h.text(" replicas identical · nothing pending"),
          ],
        ),
      ]),
      scenarios(),
      h.p([a.class("controls-hint")], [
        h.text(
          "The scenario buttons submit through each editor's own Quill instance (the same path a browser keystroke takes), so you're watching the genuine client-transform protocol, not a scripted animation. Manual typing and toolbar formatting work in all three editors too; try editing one while a race is still in flight in another.",
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
              "The live demo needs JavaScript: it runs the production client runtime, the rich_text_kernel, and the in-memory sluice as compiled JavaScript in your browser, plus Quill for the editor surface. The rest of the page works fine without it.",
            ),
          ],
        ),
      ]),
      h.p(
        [
          a.class("demo-noscript"),
          a.attribute("data-rt-fallback", ""),
          a.attribute("data-testid", "rich-text-fallback"),
          a.hidden(True),
        ],
        [
          h.text(
            "The live demo couldn't start: it runs the production client runtime against the in-memory sluice and a Quill editor as compiled JavaScript, and this browser didn't load it. The rest of the page works fine without it.",
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
      a.attribute("aria-label", label <> " editor"),
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
          [h.text("synced")],
        ),
      ]),
      h.div([a.class("quill-mount"), a.attribute("data-quill-root", "")], []),
      h.footer([a.class("client-foot")], [
        h.p([a.class("canonical annot"), a.attribute("data-canonical", "")], []),
        h.ul(
          [
            a.class("peer-list"),
            a.attribute("data-peer-list", ""),
            a.attribute("aria-label", "Peer selections visible to " <> label),
          ],
          [],
        ),
      ]),
    ],
  )
}

fn scenarios() -> Element(Nil) {
  h.div([a.class("scenario-row"), a.attribute("data-reveal", "rise")], [
    scenario("scenario-btn", "data-rt-race-type", "Race: type at the same spot"),
    scenario(
      "scenario-btn",
      "data-rt-race-format",
      "Race: bold vs. color, same span",
    ),
    scenario("scenario-btn", "data-rt-race-delete", "Race: delete vs. format"),
    scenario("scenario-btn", "data-rt-embed", "Insert an image embed"),
    scenario("step-btn", "data-rt-step", "Step one delivery"),
    scenario("step-btn", "data-rt-settle", "Settle to quiescence"),
    h.button(
      [
        a.type_("button"),
        a.class("reset-btn"),
        a.attribute("data-rt-reset", ""),
        a.attribute(
          "aria-label",
          "Reset all three editors to the formatted baseline",
        ),
        a.disabled(True),
      ],
      [h.text("Reset")],
    ),
  ])
}

fn scenario(class: String, attribute: String, label: String) -> Element(Nil) {
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

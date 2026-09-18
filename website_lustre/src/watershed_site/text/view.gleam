import lustre/attribute as a
import lustre/element.{type Element, element, fragment}
import lustre/element/html as h

pub fn static() -> Element(Nil) {
  fragment([mechanics(), component()])
}

fn mechanics() -> Element(Nil) {
  h.section(
    [
      a.id("text-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "text-demo-title"),
    ],
    [
      head(
        "text-demo-title",
        "One shared string, live",
        "Three watershed documents share one SharedText, a collaboratively-typed string. One client creates it and shares the handle; the others resolve it. They talk to one sluice, the in-memory server that ships in the library. Type in any editor: your keystrokes show in magenta while pending, then settle to ink once every replica lands the same text.",
      ),
      h.p([a.class("demo-hint")], [
        h.text(
          "Every keystroke is diffed into one minimal grapheme edit: an insert, delete, or replace against grapheme indexes, never raw UTF-16 offsets. Stage a race: Crowd an insert has B and C type different words at the same spot; Overlapping edit has B replace a word while C deletes across it. Both converge, because each grapheme keeps a stable identity: the delta names graphemes, not character positions.",
        ),
      ]),
      h.p([a.class("grapheme-legend")], [
        h.text(
          "The seed text is grapheme-rich on purpose. 👨‍👩‍👧 is a ZWJ sequence, several code points joined into one grapheme, one index; a cursor can never split it. The í in río is a letter plus a combining accent, again one grapheme. And 🏞️ includes a variation selector. SharedText indexes by grapheme, so none of these can be bisected by an edit.",
        ),
      ]),
      h.div([a.class("rig"), a.attribute("data-text-rig", "")], [
        client("a", "Client A"),
        client("b", "Client B"),
        client("c", "Client C"),
        channel(),
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
      fallback("data-text-fallback", "text-fallback"),
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
        h.span([a.class("counts")], [
          h.span(
            [
              a.class("grapheme-count annot"),
              a.attribute("data-grapheme-count", ""),
            ],
            [h.text("0 graphemes")],
          ),
          h.span(
            [
              a.class("pending-count annot"),
              a.attribute("data-pending-count", ""),
            ],
            [h.text("0 pending")],
          ),
        ]),
      ]),
      h.label([a.class("editor-label annot"), a.for("text-editor-" <> id)], [
        h.text(label <> " editor, type to edit the shared text"),
      ]),
      h.textarea(
        [
          a.id("text-editor-" <> id),
          a.class("text-editor"),
          a.attribute("data-text-editor", ""),
          a.rows(3),
          a.attribute("spellcheck", "false"),
          a.attribute("aria-describedby", "anchor-readout-" <> id),
          a.disabled(True),
        ],
        "",
      ),
      h.div([a.class("pane-actions")], [
        button("node-action", "data-anchor-pin", "Pin anchor at caret"),
        button("node-action", "data-anchor-clear", "Clear"),
        button("node-action", "data-text-append", "Append ⇣"),
      ]),
      h.p(
        [
          a.class("anchor-readout annot"),
          a.id("anchor-readout-" <> id),
          a.attribute("data-anchor-readout", ""),
          a.attribute("role", "status"),
        ],
        [h.text("no anchor pinned")],
      ),
    ],
  )
}

fn channel() -> Element(Nil) {
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
  ])
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
        a.attribute("data-text-pace", ""),
        a.disabled(True),
      ]),
      h.output([a.attribute("data-text-pace-out", "")], [h.text("1×")]),
    ]),
    h.label([a.class("toggle")], [
      h.input([
        a.type_("checkbox"),
        a.attribute("data-text-latency-variance", ""),
        a.disabled(True),
      ]),
      h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
    ]),
    button("race-btn", "data-text-race-insert", "Crowd an insert"),
    button("race-btn", "data-text-race-overlap", "Overlapping edit"),
    button("reset-btn", "data-text-reset", "Reset"),
    h.p(
      [
        a.class("status"),
        a.attribute("data-text-status", ""),
        a.attribute("role", "status"),
      ],
      [
        h.span([a.class("stamp converged")], [h.text("Converged")]),
        h.text(" all replicas identical · nothing pending"),
      ],
    ),
  ])
}

fn component() -> Element(Nil) {
  h.section(
    [
      a.id("text-element-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "text-element-demo-title"),
    ],
    [
      head(
        "text-element-demo-title",
        "All of that, as one tag",
        "Everything the rig above does by hand ships as a component: <watershed-textarea>, the watershed_lustre editor compiled from Gleam and registered as a custom element. These two panes are that element: two documents, one shared SharedText, and the same in-memory sluice.",
      ),
      h.p([a.class("demo-hint")], [
        h.text(
          "The component owns what the naïve bridge gets wrong: each keystroke is diffed into one minimal grapheme op, a peer's edit can't teleport your caret, and an IME composition survives remote keystrokes. Select a few words in one pane and a named highlight appears in the other, then type before them and watch it stay glued to those words. It travels as content-bound anchors, not offsets, which is the same machinery that keeps your own caret in place.",
        ),
      ]),
      h.div([a.class("element-rig")], [
        pane("a", "Client A"),
        pane("b", "Client B"),
      ]),
      h.p([a.class("controls-hint")], [
        h.text(
          "Cursors here hop panes through a property assignment; in an app the cursor event's payload rides your presence channel unchanged.",
        ),
      ]),
      fallback("data-text-element-fallback", "text-element-fallback"),
    ],
  )
}

fn pane(id: String, label: String) -> Element(Nil) {
  h.article(
    [
      a.class("pane"),
      a.attribute("data-pane", id),
      a.attribute("aria-label", label <> " editor"),
    ],
    [
      h.header([a.class("pane-head")], [
        h.h3([], [h.text(label)]),
        h.span([a.class("annot"), a.attribute("data-count", "")], [
          h.text("0 graphemes"),
        ]),
      ]),
      element("watershed-textarea", [a.attribute("rows", "5")], []),
      h.p(
        [
          a.class("pane-error annot"),
          a.attribute("data-error", ""),
          a.attribute("role", "status"),
        ],
        [],
      ),
    ],
  )
}

fn head(id: String, title: String, copy: String) -> Element(Nil) {
  h.div([a.class("demo-head"), a.attribute("data-reveal", "rise")], [
    h.h2([a.id(id)], [h.text(title)]),
    h.p([], [h.text(copy)]),
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

fn fallback(attribute: String, testid: String) -> Element(Nil) {
  fragment([
    h.noscript([], [
      h.p([a.class("demo-noscript"), a.attribute("data-testid", "noscript")], [
        h.text(
          "The live demo needs JavaScript. The rest of the page works fine without it.",
        ),
      ]),
    ]),
    h.p(
      [
        a.class("demo-noscript"),
        a.attribute(attribute, ""),
        a.attribute("data-testid", testid),
        a.hidden(True),
      ],
      [
        h.text(
          "The live demo couldn't start. The rest of the page works fine without it.",
        ),
      ],
    ),
  ])
}

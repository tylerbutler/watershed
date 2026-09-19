import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{type Attribute} as a
import lustre/element.{type Element, element, fragment}
import lustre/element/html as h
import lustre/event
import watershed_site/text/runtime

pub fn static() -> Element(Nil) {
  view(runtime.static_model(), True)
  |> element.map(fn(_) { Nil })
}

pub fn view(
  model: runtime.Model,
  include_noscript: Bool,
) -> Element(runtime.Msg) {
  fragment([
    mechanics(model, include_noscript),
    component(model, include_noscript),
  ])
}

fn mechanics(
  model: runtime.Model,
  include_noscript: Bool,
) -> Element(runtime.Msg) {
  let unavailable =
    model.phase == runtime.Static
    || model.phase == runtime.Starting
    || model.phase == runtime.Failed
  h.section(
    [
      a.id("text-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "text-demo-title"),
      ..mounted(model)
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
        client(model, runtime.ClientA, "a", unavailable),
        client(model, runtime.ClientB, "b", unavailable),
        client(model, runtime.ClientC, "c", unavailable),
        channel(model),
        h.div(
          [
            a.class("flow-layer"),
            a.attribute("data-flow-layer", ""),
            a.attribute("aria-hidden", "true"),
          ],
          [],
        ),
      ]),
      controls(model, unavailable),
      h.p([a.class("controls-hint")], [
        h.text(
          "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency.",
        ),
      ]),
      fallback(model, include_noscript, "data-text-fallback", "text-fallback"),
      error(model),
    ],
  )
}

fn client(
  model: runtime.Model,
  replica: runtime.Replica,
  id: String,
  unavailable: Bool,
) -> Element(runtime.Msg) {
  let label = runtime.replica_label(replica)
  let pending = runtime.pending_count(model, replica)
  let editor_attributes = [
    a.id("text-editor-" <> id),
    a.class("text-editor"),
    a.attribute("data-text-editor", ""),
    a.rows(3),
    a.attribute("spellcheck", "false"),
    a.attribute("aria-describedby", "anchor-readout-" <> id),
    a.attribute("data-composing", case runtime.is_composing(model, replica) {
      True -> "true"
      False -> "false"
    }),
    a.disabled(unavailable),
    event.on(
      "input",
      value_decoder(fn(value, start, end) {
        runtime.Defer(runtime.InputChanged(replica, value, start, end))
      }),
    ),
    event.on("select", selection_decoder(replica)),
    event.on("keyup", selection_decoder(replica)),
    event.on("mouseup", selection_decoder(replica)),
    event.on("focus", selection_decoder(replica)),
    event.on(
      "compositionstart",
      value_decoder(fn(value, start, end) {
        runtime.Defer(runtime.CompositionStarted(replica, value, start, end))
      }),
    ),
    event.on(
      "compositionend",
      value_decoder(fn(value, start, end) {
        runtime.Defer(runtime.CompositionEnded(replica, value, start, end))
      }),
    ),
  ]
  h.article(
    [
      a.class("client"),
      a.attribute("data-client", id),
      a.attribute("data-flow-node", id),
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
            [
              h.text(
                int.to_string(
                  runtime.value(model, replica)
                  |> string.to_graphemes
                  |> list.length,
                )
                <> " graphemes",
              ),
            ],
          ),
          h.span(
            [
              a.class(case pending > 0 {
                True -> "pending-count annot is-pending"
                False -> "pending-count annot"
              }),
              a.attribute("data-pending-count", ""),
            ],
            [h.text(int.to_string(pending) <> " pending")],
          ),
        ]),
      ]),
      h.label([a.class("editor-label annot"), a.for("text-editor-" <> id)], [
        h.text(label <> " editor, type to edit the shared text"),
      ]),
      case runtime.is_composing(model, replica) {
        False ->
          h.textarea(editor_attributes, runtime.rendered_value(model, replica))
        True ->
          element("textarea", editor_attributes, [
            h.text(runtime.rendered_value(model, replica)),
          ])
      },
      h.div([a.class("pane-actions")], [
        button(
          "node-action",
          "data-anchor-pin",
          "Pin anchor at caret",
          unavailable,
          runtime.Defer(runtime.PinAnchor(replica)),
        ),
        button(
          "node-action",
          "data-anchor-clear",
          "Clear",
          runtime.anchor_position(model, replica) == None,
          runtime.Defer(runtime.ClearAnchor(replica)),
        ),
        button(
          "node-action",
          "data-text-append",
          "Append ⇣",
          unavailable,
          runtime.Defer(runtime.Insert(
            replica,
            runtime.value(model, replica)
              |> string.to_graphemes
              |> list.length,
            " ⇣",
          )),
        ),
      ]),
      h.p(
        [
          a.class("anchor-readout annot"),
          a.id("anchor-readout-" <> id),
          a.attribute("data-anchor-readout", ""),
          a.attribute("role", "status"),
        ],
        [
          h.text(case runtime.anchor_position(model, replica) {
            None -> "no anchor pinned"
            Some(position) ->
              "anchor pinned @"
              <> int.to_string(position.0)
              <> " → now grapheme "
              <> int.to_string(position.1)
          }),
        ],
      ),
    ],
  )
}

fn channel(model: runtime.Model) -> Element(msg) {
  h.div([a.class("channel"), a.style("grid-area", "seq")], [
    h.div([a.class("seq-node"), a.attribute("data-seq-node", "")], [
      h.span([a.class("annot")], [h.text("Sequencer")]),
      h.output(
        [
          a.class("seq-counter"),
          a.attribute("data-seq-counter", ""),
          a.attribute("aria-label", "Latest sequence number"),
        ],
        [h.text("SN " <> int.to_string(model.latest_sequence))],
      ),
    ]),
    h.ol(
      [
        a.class("op-log"),
        a.attribute("data-op-log", ""),
        a.attribute("aria-live", "polite"),
        a.attribute("aria-label", "Sequenced operations, newest first"),
      ],
      model.log
        |> list.take(24)
        |> list.map(fn(entry) {
          h.li([], [
            h.span([a.class("op-meta")], [
              h.text(
                "SN "
                <> int.to_string(entry.sequence_number)
                <> " · "
                <> string.drop_start(runtime.replica_label(entry.author), 7),
              ),
            ]),
            h.span([a.class("op-path")], [h.text(entry.label)]),
            h.span([a.class("op-kind")], [h.text("op")]),
          ])
        }),
    ),
  ])
}

fn controls(model: runtime.Model, unavailable: Bool) -> Element(runtime.Msg) {
  h.div([a.class("demo-controls")], [
    h.label([a.class("pace")], [
      h.span([a.class("annot")], [h.text("Animation speed")]),
      h.input([
        a.type_("range"),
        a.min("0.25"),
        a.max("2"),
        a.step("0.25"),
        a.value(pace(model.pace_quarters)),
        a.attribute("data-text-pace", ""),
        event.on_input(runtime.SetPace),
        a.disabled(unavailable),
      ]),
      h.output([a.attribute("data-text-pace-out", "")], [
        h.text(pace(model.pace_quarters) <> "×"),
      ]),
    ]),
    h.label([a.class("toggle")], [
      h.input([
        a.type_("checkbox"),
        a.checked(model.jitter),
        a.attribute("data-text-latency-variance", ""),
        event.on_check(runtime.SetJitter),
        a.disabled(unavailable),
      ]),
      h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
    ]),
    button(
      "race-btn",
      "data-text-race-insert",
      "Crowd an insert",
      unavailable,
      runtime.Defer(runtime.RaceInserts),
    ),
    button(
      "race-btn",
      "data-text-race-overlap",
      "Overlapping edit",
      unavailable,
      runtime.Defer(runtime.RaceOverlap),
    ),
    button(
      "race-btn",
      "data-text-settle",
      "Settle to quiescence",
      unavailable,
      runtime.Defer(runtime.Settle),
    ),
    button(
      "reset-btn",
      "data-text-reset",
      "Reset",
      unavailable,
      runtime.Defer(runtime.Reset),
    ),
    h.p(
      [
        a.class("status"),
        a.attribute("data-text-status", ""),
        a.attribute("role", "status"),
      ],
      case runtime.all_values_equal(model) && model.pending == [] {
        True -> [
          h.span([a.class("stamp converged")], [h.text("Converged")]),
          h.text(" all replicas identical · nothing pending"),
        ]
        False -> [
          h.span([a.class("stamp")], [h.text("Revising")]),
          h.text(" operations are still moving"),
        ]
      },
    ),
  ])
}

fn component(
  model: runtime.Model,
  include_noscript: Bool,
) -> Element(runtime.Msg) {
  h.section(
    [
      a.id("text-element-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "text-element-demo-title"),
      ..mounted(model)
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
        pane(model, runtime.ElementA, "a", "Client A"),
        pane(model, runtime.ElementB, "b", "Client B"),
      ]),
      h.p([a.class("controls-hint")], [
        h.text(
          "Cursors here hop panes through a property assignment; in an app the cursor event's payload rides your presence channel unchanged.",
        ),
      ]),
      fallback(
        model,
        include_noscript,
        "data-text-element-fallback",
        "text-element-fallback",
      ),
    ],
  )
}

fn pane(
  model: runtime.Model,
  replica: runtime.Replica,
  id: String,
  label: String,
) -> Element(runtime.Msg) {
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
          h.text(
            int.to_string(
              runtime.value(model, replica)
              |> string.to_graphemes
              |> list.length,
            )
            <> " graphemes",
          ),
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

fn head(id: String, title: String, copy: String) -> Element(msg) {
  h.div([a.class("demo-head"), a.attribute("data-reveal", "rise")], [
    h.h2([a.id(id)], [h.text(title)]),
    h.p([], [h.text(copy)]),
  ])
}

fn button(
  class: String,
  attribute: String,
  label: String,
  disabled: Bool,
  message: msg,
) -> Element(msg) {
  h.button(
    [
      a.type_("button"),
      a.class(class),
      a.attribute(attribute, ""),
      a.disabled(disabled),
      event.on_click(message),
    ],
    [h.text(label)],
  )
}

fn mounted(model: runtime.Model) -> List(Attribute(msg)) {
  case model.phase {
    runtime.Ready | runtime.Delivering -> [a.attribute("data-mounted", "")]
    _ -> []
  }
}

fn fallback(
  model: runtime.Model,
  include_noscript: Bool,
  attribute: String,
  testid: String,
) -> Element(runtime.Msg) {
  fragment([
    case include_noscript {
      True ->
        element("noscript", [], [
          h.p(
            [a.class("demo-noscript"), a.attribute("data-testid", "noscript")],
            [
              h.text(
                "The live demo needs JavaScript. The rest of the page works fine without it.",
              ),
            ],
          ),
        ])
      False -> element.none()
    },
    case model.phase {
      runtime.Static ->
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
        )
      _ -> element.none()
    },
  ])
}

fn error(model: runtime.Model) -> Element(msg) {
  h.p(
    [
      a.class("demo-noscript"),
      a.attribute("data-text-error", ""),
      a.attribute("aria-live", "polite"),
    ],
    case model.error {
      None -> []
      Some(reason) -> [h.text(reason)]
    },
  )
}

fn value_decoder(
  to_message: fn(String, Int, Int) -> runtime.Msg,
) -> Decoder(runtime.Msg) {
  use value <- decode.subfield(["target", "value"], decode.string)
  use selection_start <- decode.then(caret("selectionStart"))
  use selection_end <- decode.then(caret("selectionEnd"))
  decode.success(to_message(value, selection_start, selection_end))
}

fn selection_decoder(replica: runtime.Replica) -> Decoder(runtime.Msg) {
  use selection_start <- decode.then(caret("selectionStart"))
  use selection_end <- decode.then(caret("selectionEnd"))
  decode.success(runtime.SelectionChanged(
    replica,
    selection_start,
    selection_end,
  ))
}

fn caret(name: String) -> Decoder(Int) {
  decode.optionally_at(
    ["target", name],
    -1,
    decode.one_of(decode.int, or: [decode.success(-1)]),
  )
}

fn pace(quarters: Int) -> String {
  case quarters {
    1 -> "0.25"
    2 -> "0.5"
    3 -> "0.75"
    4 -> "1"
    5 -> "1.25"
    6 -> "1.5"
    7 -> "1.75"
    8 -> "2"
    _ -> "1"
  }
}

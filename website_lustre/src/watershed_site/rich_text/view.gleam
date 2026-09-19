import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{type Attribute} as a
import lustre/element.{type Element, element}
import lustre/element/html as h
import lustre/event
import watershed_site/rich_text/runtime

pub fn static() -> Element(Nil) {
  view(runtime.static_model(), True)
  |> element.map(fn(_) { Nil })
}

pub fn view(
  model: runtime.Model,
  include_noscript: Bool,
) -> Element(runtime.Msg) {
  let unavailable =
    model.phase == runtime.Static
    || model.phase == runtime.Starting
    || model.phase == runtime.Failed
  h.section(
    [
      a.id("rt-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "rt-demo-title"),
      ..mounted(model)
    ],
    [
      heading(),
      h.div([a.class("rig"), a.attribute("data-rt-rig", "")], [
        client(model, runtime.ClientA, "a"),
        client(model, runtime.ClientB, "b"),
        client(model, runtime.ClientC, "c"),
        channel(),
        h.div(
          [
            a.class("flow-layer"),
            a.attribute("data-flow-layer", ""),
            a.attribute("aria-hidden", "true"),
          ],
          case model.pending {
            [] -> []
            [pending, ..] -> [
              h.div(
                [
                  a.class("rich-text-flow"),
                  a.attribute("data-flow-id", "rich-text"),
                  a.attribute("data-from", runtime.replica_id(pending.replica)),
                  a.attribute("data-to", "seq"),
                ],
                [h.span([a.class("flow-dot-label")], [h.text(pending.label)])],
              ),
            ]
          },
        ),
      ]),
      controls(model, unavailable),
      scenarios(model, unavailable),
      h.p([a.class("controls-hint")], [
        h.text(
          "The scenario buttons submit through each editor's own Quill instance (the same path a browser keystroke takes), so you're watching the genuine client-transform protocol, not a scripted animation. Manual typing and toolbar formatting work in all three editors too; try editing one while a race is still in flight in another.",
        ),
      ]),
      case include_noscript {
        False -> element.none()
        True ->
          element("noscript", [], [
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
          ])
      },
      case model.phase {
        runtime.Static ->
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
          )
        _ -> element.none()
      },
      h.p(
        [
          a.class("demo-noscript"),
          a.attribute("aria-live", "polite"),
          a.attribute("data-testid", "rich-text-error"),
        ],
        case model.error {
          None -> []
          Some(reason) -> [h.text(reason)]
        },
      ),
    ],
  )
}

fn heading() -> Element(msg) {
  h.div([a.class("demo-head")], [
    h.h2([a.id("rt-demo-title")], [h.text("SharedRichText, live")]),
    h.p([], [
      h.text(
        "Three watershed documents share one rich-text channel over the rich_text_kernel. It runs the same single-op-in-flight client-transform protocol as the ",
      ),
      h.a([a.href("/json-ot")], [h.text("json_ot demo")]),
      h.text(
        ", but over quill-delta's algebra: operations retain, insert, or delete spans of text. Each op can carry an attribute patch (bold, color, …) or wrap an embed (an image) instead of plain text. Positions are counted in UTF-16 code units (the units Quill and JavaScript strings index by), so nothing converts at the editor boundary. Each editor keeps at most one op in flight; anything typed while it's outstanding composes into a single buffered op behind it. This is SharedRichText, watershed's OT-backed rich text. For CRDT-backed plain text, ",
      ),
      h.a([a.href("/text")], [h.code([], [h.text("SharedText")])]),
      h.text(
        " indexes graphemes by stable identity and converges by merge rather than by transform.",
      ),
    ]),
    h.p([a.class("demo-hint")], [
      h.text(
        "Local edits apply the instant you type, Quill's own optimistic model, no different from typing into any editor. Race two clients at the same spot, format concurrently, or delete under someone else's formatting, then watch the op log and the canonical text below each editor converge. Peer cursors (dashed, colored) track where the other two are looking, transformed through every edit exactly like the local caret is.",
      ),
    ]),
  ])
}

fn client(
  model: runtime.Model,
  replica: runtime.Replica,
  id: String,
) -> Element(runtime.Msg) {
  let pending = runtime.pending_count(model, replica)
  h.article(
    [
      a.class("client"),
      a.attribute("data-client", id),
      a.attribute("aria-label", runtime.replica_label(replica) <> " editor"),
      a.style("grid-area", id),
    ],
    [
      h.header([a.class("client-head")], [
        h.h3([], [h.text(runtime.replica_label(replica))]),
        h.span(
          [
            a.class(case pending > 0 {
              True -> "pending-count annot is-pending"
              False -> "pending-count annot"
            }),
            a.attribute("data-pending-count", ""),
          ],
          [
            h.text(case pending > 0 {
              True -> "in flight / buffered"
              False -> "synced"
            }),
          ],
        ),
      ]),
      h.div(
        [
          a.id("rich-text-editor-" <> id),
          a.class("quill-mount"),
          a.attribute("data-quill-root", ""),
        ],
        [],
      ),
      h.footer([a.class("client-foot")], [
        h.p([a.class("canonical annot"), a.attribute("data-canonical", "")], [
          h.text("“" <> canonical(model, replica) <> "”"),
        ]),
        h.ul(
          [
            a.class("peer-list"),
            a.attribute("data-peer-list", ""),
            a.attribute(
              "aria-label",
              "Peer selections visible to " <> runtime.replica_label(replica),
            ),
          ],
          [],
        ),
      ]),
    ],
  )
}

fn canonical(model: runtime.Model, replica: runtime.Replica) -> String {
  let value = runtime.canonical(model, replica)
  case string.ends_with(value, "\n") {
    True -> string.drop_end(value, 1)
    False -> value
  }
}

fn channel() -> Element(msg) {
  h.div([a.class("channel"), a.style("grid-area", "seq")], [
    h.div([a.class("seq-node"), a.attribute("data-seq-node", "")], [
      h.span([a.class("annot")], [h.text("Sequencer")]),
      h.output(
        [
          a.class("seq-counter"),
          a.attribute("data-seq-counter", ""),
          a.attribute("aria-label", "Latest sequence number"),
        ],
        [h.text("SN")],
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
        a.value("1"),
        a.attribute("data-rt-pace", ""),
        a.title("Playback only; does not affect simulated ordering."),
        a.disabled(unavailable),
      ]),
      h.output([a.attribute("data-rt-pace-out", "")], [h.text("1×")]),
    ]),
    h.label([a.class("field-notes-toggle")], [
      h.input([
        a.type_("checkbox"),
        a.attribute("data-rt-latency-variance", ""),
        a.title("Add random ±100 ms per hop; arrival order may change."),
        a.disabled(unavailable),
      ]),
      h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
    ]),
    h.p(
      [
        a.class("status"),
        a.attribute("data-rt-status", ""),
        a.attribute("role", "status"),
      ],
      case
        model.phase == runtime.Ready
        && runtime.all_documents_equal(model)
        && model.pending == []
      {
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

fn scenarios(model: runtime.Model, unavailable: Bool) -> Element(runtime.Msg) {
  h.div([a.class("scenario-row")], [
    scenario(
      "scenario-btn",
      "data-rt-race-type",
      "Race: type at the same spot",
      unavailable,
      runtime.NoOp,
    ),
    scenario(
      "scenario-btn",
      "data-rt-race-format",
      "Race: bold vs. color, same span",
      unavailable,
      runtime.NoOp,
    ),
    scenario(
      "scenario-btn",
      "data-rt-race-delete",
      "Race: delete vs. format",
      unavailable,
      runtime.NoOp,
    ),
    scenario(
      "scenario-btn",
      "data-rt-embed",
      "Insert an image embed",
      unavailable,
      runtime.NoOp,
    ),
    scenario(
      "scenario-btn",
      "data-rt-step",
      "Step one delivery",
      unavailable,
      runtime.Defer(runtime.Deliver(model.generation)),
    ),
    scenario(
      "scenario-btn",
      "data-rt-settle",
      "Settle to quiescence",
      unavailable,
      runtime.NoOp,
    ),
    scenario(
      "reset-btn",
      "data-rt-reset",
      "Reset",
      unavailable,
      runtime.Defer(runtime.Reset),
    ),
  ])
}

fn scenario(
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

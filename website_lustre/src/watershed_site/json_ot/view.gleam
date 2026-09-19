import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/keyed
import lustre/event
import watershed_site/demo/flow
import watershed_site/json_ot/runtime

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
      a.id("jot-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "jot-demo-title"),
      test_id("json-ot-demo"),
      ..mounted(model)
    ],
    [
      heading(),
      h.div(
        [
          a.class("rig"),
          a.attribute("data-jot-rig", ""),
          test_id("json-ot-rig"),
        ],
        [
          client(model, runtime.ClientA, "a", unavailable),
          client(model, runtime.ClientB, "b", unavailable),
          client(model, runtime.ClientC, "c", unavailable),
          channel(model),
          flows(model),
        ],
      ),
      controls(model, unavailable),
      h.p([a.class("controls-hint")], [
        h.text(
          "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency.",
        ),
      ]),
      case include_noscript {
        False -> element.none()
        True ->
          element.element("noscript", [], [
            h.p([a.class("demo-noscript"), test_id("noscript")], [
              h.text(
                "The live demo needs JavaScript: it runs the production client runtime and the in-memory sluice as compiled JavaScript in your browser. The rest of the page works fine without it.",
              ),
            ]),
          ])
      },
      case model.phase {
        runtime.Static ->
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
          )
        _ -> element.none()
      },
      h.p(
        [
          a.class("demo-noscript"),
          a.attribute("aria-live", "polite"),
          test_id("error"),
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
  h.div([a.class("demo-head"), a.attribute("data-reveal", "rise")], [
    h.h2([a.id("jot-demo-title")], [h.text("Operational transform, live")]),
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
  ])
}

fn client(
  model: runtime.Model,
  replica: runtime.Replica,
  area: String,
  unavailable: Bool,
) -> Element(runtime.Msg) {
  let snapshot = runtime.snapshot(model, replica)
  let label = runtime.replica_label(replica)
  h.article(
    [
      a.class("client"),
      a.attribute("data-client", area),
      a.attribute("data-flow-node", area),
      a.attribute("aria-label", label <> " replica"),
      a.style("grid-area", area),
      test_id("client-" <> area),
    ],
    [
      h.header([a.class("client-head")], [
        h.h3([], [h.text(label)]),
        h.span(
          [
            a.class(pending_class(runtime.pending_count(model, replica))),
            a.attribute("data-pending-count", ""),
          ],
          [
            h.text(
              int.to_string(runtime.pending_count(model, replica)) <> " pending",
            ),
          ],
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
          h.div(
            [
              a.class("jrow crew-row"),
              a.attribute("data-field", "crew"),
              a.attribute("data-node", "crew"),
            ],
            [
              h.span([a.class("jkey")], [h.text("\"crew\"")]),
              h.span([a.class("jp colon")], [h.text(": ")]),
              h.span([a.class("jp bracket")], [h.text("[")]),
              h.ul(
                [
                  a.class("crew"),
                  a.attribute("data-crew", ""),
                  a.attribute("aria-label", "crew array on " <> label),
                ],
                list.index_map(snapshot.crew, fn(name, index) {
                  crew_member(model, replica, name, index, unavailable)
                }),
              ),
              h.span([a.class("jp bracket")], [h.text("]")]),
              h.span([a.class("jp comma")], [h.text(" ,")]),
              action(
                "+ surveyor",
                "Add a surveyor to crew on " <> label,
                "data-crew-add",
                runtime.Defer(runtime.AddCrew(replica)),
                unavailable,
              ),
            ],
          ),
          h.div([a.class("jrow jrow-open"), a.attribute("data-node", "gauge")], [
            h.span([a.class("jkey")], [h.text("\"gauge\"")]),
            h.span([a.class("jp colon")], [h.text(": ")]),
            h.span([a.class("jp brace")], [h.text("{")]),
          ]),
          h.div([a.class("jnest")], [
            field_row(
              model,
              replica,
              "gauge.stage",
              "\"stage\"",
              int.to_string(snapshot.stage),
              "num",
              False,
              True,
              [
                action(
                  "−",
                  "Lower stage on " <> label,
                  "data-stage-dec",
                  runtime.Defer(runtime.StepStage(replica, -1)),
                  unavailable,
                ),
                action(
                  "+",
                  "Raise stage on " <> label,
                  "data-stage-inc",
                  runtime.Defer(runtime.StepStage(replica, 1)),
                  unavailable,
                ),
              ],
            ),
            field_row(
              model,
              replica,
              "gauge.trend",
              "\"trend\"",
              snapshot.trend,
              "",
              True,
              False,
              [
                action(
                  "cycle",
                  "Cycle the gauge trend on " <> label,
                  "data-trend-cycle",
                  runtime.Defer(runtime.CycleTrend(replica)),
                  unavailable,
                ),
              ],
            ),
          ]),
          h.div(
            [a.class("jrow jrow-close"), a.attribute("data-node", "gauge")],
            [
              h.span([a.class("jp brace")], [h.text("}")]),
              h.span([a.class("jp comma")], [h.text(" ,")]),
            ],
          ),
          field_row(
            model,
            replica,
            "site",
            "\"site\"",
            snapshot.site,
            "",
            True,
            False,
            [
              action(
                "rename",
                "Rename the site on " <> label,
                "data-site-cycle",
                runtime.Defer(runtime.CycleSite(replica)),
                unavailable,
              ),
            ],
          ),
          h.span([a.class("jp brace")], [h.text("}")]),
        ],
      ),
    ],
  )
}

fn crew_member(
  model: runtime.Model,
  replica: runtime.Replica,
  name: String,
  index: Int,
  unavailable: Bool,
) -> Element(runtime.Msg) {
  let label = runtime.replica_label(replica)
  let pending = pending_field(model, replica, "crew")
  h.li(
    [
      a.class(case pending {
        True -> "chip pending"
        False -> "chip"
      }),
    ],
    [
      h.span([a.class("jp")], [h.text("\"")]),
      h.span([a.class("chip-name")], [h.text(name)]),
      h.span([a.class("jp")], [
        h.text(case index < list.length(runtime.crew(model, replica)) - 1 {
          True -> "\","
          False -> "\""
        }),
      ]),
      h.span([a.class("chip-actions")], [
        case index > 0 {
          True ->
            h.button(
              [
                a.type_("button"),
                a.attribute("aria-label", "Move " <> name <> " up on " <> label),
                a.disabled(unavailable),
                event.on_click(runtime.Defer(runtime.MoveCrew(replica, index))),
              ],
              [h.text("↑")],
            )
          False -> element.none()
        },
        h.button(
          [
            a.type_("button"),
            a.class("chip-del"),
            a.attribute(
              "aria-label",
              "Remove " <> name <> " from crew on " <> label,
            ),
            a.disabled(unavailable),
            event.on_click(runtime.Defer(runtime.DeleteCrew(replica, index))),
          ],
          [h.text("×")],
        ),
      ]),
    ],
  )
}

fn field_row(
  model: runtime.Model,
  replica: runtime.Replica,
  field: String,
  key: String,
  value: String,
  extra: String,
  quoted: Bool,
  comma: Bool,
  actions: List(Element(runtime.Msg)),
) -> Element(runtime.Msg) {
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
                }
                <> case pending_field(model, replica, field) {
                  True -> " pending"
                  False -> ""
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

fn action(
  label: String,
  aria: String,
  attribute: String,
  message: runtime.Msg,
  unavailable: Bool,
) -> Element(runtime.Msg) {
  h.button(
    [
      a.type_("button"),
      a.class("node-action"),
      a.attribute(attribute, ""),
      a.attribute("aria-label", aria),
      a.disabled(unavailable),
      event.on_click(message),
    ],
    [h.text(label)],
  )
}

fn channel(model: runtime.Model) -> Element(runtime.Msg) {
  h.div([a.class("channel"), a.style("grid-area", "seq")], [
    h.div(
      [
        a.class("seq-node"),
        a.attribute("data-flow-node", "seq"),
        a.attribute("data-seq-node", ""),
      ],
      [
        h.span([a.class("annot")], [h.text("Sequencer")]),
        h.output(
          [
            a.class("seq-counter"),
            a.attribute("data-seq-counter", ""),
            a.attribute("aria-label", "Latest sequence number"),
          ],
          [h.text("SN " <> int.to_string(model.latest_sequence))],
        ),
      ],
    ),
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

fn flows(model: runtime.Model) -> Element(runtime.Msg) {
  keyed.div(
    [
      a.class("flow-layer"),
      a.attribute("data-flow-layer", ""),
      a.attribute("aria-hidden", "true"),
      test_id("flow-layer"),
    ],
    list.map(model.flows, fn(item) {
      #(
        int.to_string(item.id),
        h.span(
          [
            a.class(case item.from {
              flow.Sequencer -> "flow-dot sequenced"
              flow.Replica(_) -> "flow-dot"
            }),
            a.attribute("data-flow-id", int.to_string(item.id)),
            a.attribute("data-from", endpoint(item.from)),
            a.attribute("data-to", endpoint(item.to)),
          ],
          [h.span([a.class("flow-dot-label")], [h.text(item.label)])],
        ),
      )
    }),
  )
}

fn controls(model: runtime.Model, unavailable: Bool) -> Element(runtime.Msg) {
  h.div([a.class("demo-controls"), a.attribute("data-reveal", "rise")], [
    h.label([a.class("pace")], [
      h.span([a.class("annot")], [h.text("Animation speed")]),
      h.input([
        a.type_("range"),
        a.min("0.25"),
        a.max("2"),
        a.step("0.25"),
        a.value(pace(model.pace_quarters)),
        a.attribute("data-jot-pace", ""),
        a.title("Playback only; does not affect simulated ordering."),
        a.disabled(unavailable),
        event.on_input(runtime.SetPace),
      ]),
      h.output([a.attribute("data-jot-pace-out", "")], [
        h.text(pace(model.pace_quarters) <> "×"),
      ]),
    ]),
    h.label([a.class("field-notes-toggle")], [
      h.input([
        a.type_("checkbox"),
        a.checked(model.jitter),
        a.attribute("data-jot-latency-variance", ""),
        a.title("Add random ±100 ms per hop; arrival order may change."),
        a.disabled(unavailable),
        event.on_check(runtime.SetJitter),
      ]),
      h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
    ]),
    h.button(
      [
        a.type_("button"),
        a.class("race-btn"),
        a.attribute("data-jot-race", ""),
        a.disabled(unavailable),
        event.on_click(runtime.Defer(runtime.RaceInserts)),
      ],
      [h.text("Race two inserts at index 0")],
    ),
    h.button(
      [
        a.type_("button"),
        a.class("reset-btn"),
        a.attribute("data-jot-reset", ""),
        a.attribute("aria-label", "Reset the document to its surveyed baseline"),
        a.disabled(unavailable),
        event.on_click(runtime.Defer(runtime.Reset)),
      ],
      [h.text("Reset survey")],
    ),
    h.p(
      [
        a.class("status"),
        a.attribute("data-jot-status", ""),
        a.role("status"),
        test_id("status"),
      ],
      status(model),
    ),
  ])
}

fn status(model: runtime.Model) -> List(Element(msg)) {
  case model.phase, runtime.is_converged(model) {
    _, True -> [
      h.span([a.class("stamp converged")], [h.text("Converged")]),
      h.text(" all replicas identical · nothing pending"),
    ]
    runtime.Failed, _ -> [
      h.span([a.class("stamp revising")], [h.text("Unavailable")]),
      h.text(" the demo stopped"),
    ]
    _, _ -> [
      h.span([a.class("stamp revising")], [h.text("Revising")]),
      h.text(
        " "
        <> int.to_string(list.length(model.pending))
        <> " operations pending",
      ),
    ]
  }
}

fn pending_field(
  model: runtime.Model,
  replica: runtime.Replica,
  field: String,
) -> Bool {
  list.any(model.pending, fn(item) {
    item.replica == replica && item.marker == "field:" <> field
  })
}

fn pending_class(count: Int) -> String {
  "pending-count annot"
  <> case count > 0 {
    True -> " is-pending"
    False -> ""
  }
}

fn mounted(model: runtime.Model) -> List(a.Attribute(msg)) {
  case model.phase {
    runtime.Static -> []
    _ -> [a.attribute("data-mounted", "")]
  }
}

fn endpoint(value: flow.Endpoint) -> String {
  case value {
    flow.Replica(id) -> id
    flow.Sequencer -> "seq"
  }
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

fn test_id(id: String) -> a.Attribute(msg) {
  a.attribute("data-testid", id)
}

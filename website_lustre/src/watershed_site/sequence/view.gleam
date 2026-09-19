import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/keyed
import lustre/element/svg
import lustre/event
import watershed_site/demo/flow
import watershed_site/sequence/runtime

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
      a.id("route-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "route-demo-title"),
      ..mounted(model)
    ],
    [
      heading(),
      case model.field_notes {
        True ->
          h.p(
            [
              a.class("field-note"),
              a.attribute("data-route-note", ""),
              a.attribute("role", "note"),
            ],
            [
              h.text(
                "SharedSequence — items keep identity, so concurrent inserts, moves, and deletes merge instead of fighting over index numbers. Watch a station flash magenta the moment a client edits the route, then ink on every replica as the op is sequenced and applied; the newest log line boxes as each op lands.",
              ),
            ],
          )
        False -> element.none()
      },
      h.div([a.class("rig"), a.attribute("data-route-rig", "")], [
        client(model, runtime.ClientA, "a", unavailable),
        client(model, runtime.ClientB, "b", unavailable),
        client(model, runtime.ClientC, "c", unavailable),
        channel(model),
        flows(model),
      ]),
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
              a.class("demo-noscript"),
              a.attribute("data-route-fallback", ""),
              test_id("sequence-fallback"),
              a.hidden(True),
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
  ])
}

fn client(
  model: runtime.Model,
  replica: runtime.Replica,
  area: String,
  unavailable: Bool,
) -> Element(runtime.Msg) {
  let stations = runtime.route(model, replica)
  let selected = runtime.selected(model, replica)
  let label = runtime.replica_label(replica)
  let selected_index = case selected {
    None -> -1
    Some(name) -> index_of(stations, name)
  }
  h.article(
    [
      a.class("client"),
      a.attribute("data-client", area),
      a.attribute("data-flow-node", area),
      a.attribute("aria-label", label <> " replica"),
      a.style("grid-area", area),
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
      keyed.div(
        [
          a.class("route"),
          a.attribute("data-route", ""),
          a.attribute("aria-label", label <> " route"),
          a.style(
            "height",
            int.to_string(route_height(list.length(stations))) <> "px",
          ),
        ],
        [
          #("river", river(list.length(stations))),
          ..list.append(
            list.index_map(stations, fn(name, index) {
              #(
                "station:" <> name,
                station(model, replica, name, index, unavailable),
              )
            }),
            indexes(list.length(stations))
              |> list.map(fn(index) {
                #(
                  "gap:" <> int.to_string(index),
                  gap(replica, index, unavailable),
                )
              }),
          )
        ],
      ),
      h.div([a.class("route-actions"), a.attribute("data-route-actions", "")], [
        h.span(
          [a.class("selected-label annot"), a.attribute("data-selected", "")],
          [h.text(selected |> option_name)],
        ),
        route_action(
          "up",
          "↑",
          "Move the selected waypoint upstream on " <> label,
          selected_index < 1 || unavailable,
          runtime.Defer(runtime.Move(
            replica,
            selected_index,
            selected_index - 1,
          )),
        ),
        route_action(
          "down",
          "↓",
          "Move the selected waypoint downstream on " <> label,
          selected_index < 0
            || selected_index >= list.length(stations) - 1
            || unavailable,
          runtime.Defer(runtime.Move(
            replica,
            selected_index,
            selected_index + 1,
          )),
        ),
        route_action(
          "rename",
          "✎",
          "Rename the selected waypoint on " <> label,
          selected_index < 0 || unavailable,
          runtime.Defer(runtime.Rename(replica, selected_index)),
        ),
        route_action(
          "delete",
          "×",
          "Delete the selected waypoint on " <> label,
          selected_index < 0 || unavailable,
          runtime.Defer(runtime.Delete(replica, selected_index)),
        ),
      ]),
    ],
  )
}

fn station(
  model: runtime.Model,
  replica: runtime.Replica,
  name: String,
  index: Int,
  unavailable: Bool,
) -> Element(runtime.Msg) {
  let selected = runtime.selected(model, replica) == Some(name)
  let pending =
    list.any(model.pending, fn(item) {
      item.replica == replica && item.marker == "st:" <> name
    })
  h.div(
    [
      a.class(
        "station"
        <> case selected {
          True -> " selected"
          False -> ""
        }
        <> case pending {
          True -> " pending"
          False -> ""
        }
        <> station_note_class(model, replica, name),
      ),
      a.style(
        "transform",
        "translate("
          <> int.to_string(x_at(index) - 8)
          <> "px, "
          <> int.to_string(y_at(index) - 8)
          <> "px)",
      ),
    ],
    [
      h.span([a.class("station-dot"), a.attribute("aria-hidden", "true")], []),
      h.span([a.class("station-no annot"), a.attribute("data-station-no", "")], [
        h.text(int.to_string(index + 1)),
      ]),
      h.button(
        [
          a.type_("button"),
          a.class("station-name"),
          a.attribute(
            "aria-label",
            "Select " <> name <> " on " <> runtime.replica_label(replica),
          ),
          a.disabled(unavailable),
          event.on_click(runtime.Select(replica, name)),
        ],
        [h.text(name)],
      ),
    ],
  )
}

fn gap(
  replica: runtime.Replica,
  index: Int,
  unavailable: Bool,
) -> Element(runtime.Msg) {
  let x = { x_at(index - 1) + x_at(index) } / 2
  let y = 20 + index * 56
  h.button(
    [
      a.type_("button"),
      a.class("gap"),
      a.attribute(
        "aria-label",
        "Insert a waypoint at position "
          <> int.to_string(index + 1)
          <> " on "
          <> runtime.replica_label(replica),
      ),
      a.title("Insert a waypoint at position " <> int.to_string(index + 1)),
      a.style(
        "transform",
        "translate("
          <> int.to_string(x - 10)
          <> "px, "
          <> int.to_string(y - 10)
          <> "px)",
      ),
      a.disabled(unavailable),
      event.on_click(runtime.Defer(runtime.Insert(replica, index))),
    ],
    [h.text("+")],
  )
}

fn route_action(
  name: String,
  glyph: String,
  label: String,
  disabled: Bool,
  message: runtime.Msg,
) -> Element(runtime.Msg) {
  h.button(
    [
      a.type_("button"),
      a.class("node-action"),
      a.attribute("data-act", name),
      a.attribute("aria-label", label),
      a.title(label),
      a.disabled(disabled),
      event.on_click(message),
    ],
    [h.text(glyph)],
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
    keyed.ol(
      [
        a.class("op-log"),
        a.attribute("data-op-log", ""),
        a.attribute("aria-live", "polite"),
        a.attribute("aria-label", "Sequenced operations, newest first"),
      ],
      model.log
        |> list.take(24)
        |> list.map(fn(entry) {
          #(
            int.to_string(entry.sequence_number),
            h.li([a.class(log_note_class(model, entry.sequence_number))], [
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
            ]),
          )
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

fn river(count: Int) -> Element(msg) {
  svg.svg([a.class("route-river"), a.attribute("aria-hidden", "true")], [
    svg.path([a.attribute("d", river_path(count))]),
  ])
}

fn river_path(count: Int) -> String {
  let points = [-1, ..indexes(count)]
  case points {
    [] -> ""
    [first, ..rest] ->
      list.fold(
        rest,
        "M " <> int.to_string(x_at(first)) <> " " <> int.to_string(y_at(first)),
        fn(path, index) {
          path
          <> " L "
          <> int.to_string(x_at(index))
          <> " "
          <> int.to_string(y_at(index))
        },
      )
  }
}

fn station_note_class(
  model: runtime.Model,
  replica: runtime.Replica,
  name: String,
) -> String {
  case model.field_notes {
    False -> ""
    True -> {
      let local =
        list.any(model.annotations, fn(annotation) {
          annotation.target == runtime.StationTarget(replica, name)
          && annotation.tone == runtime.LocalNote
        })
      let sequenced =
        list.any(model.annotations, fn(annotation) {
          annotation.target == runtime.StationTarget(replica, name)
          && annotation.tone == runtime.SequencedNote
        })
      case local, sequenced {
        False, False -> ""
        True, False -> " note-local"
        False, True -> " note-sequenced"
        True, True -> " note-local note-sequenced"
      }
    }
  }
}

fn log_note_class(model: runtime.Model, sequence_number: Int) -> String {
  case
    model.field_notes
    && list.any(model.annotations, fn(annotation) {
      annotation.target == runtime.LogTarget(sequence_number)
    })
  {
    True -> "note-newest"
    False -> ""
  }
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
        a.attribute("data-route-pace", ""),
        a.title("Playback only; does not affect simulated ordering."),
        a.disabled(unavailable),
        event.on_input(runtime.SetPace),
      ]),
      h.output([a.attribute("data-route-pace-out", "")], [
        h.text(pace(model.pace_quarters) <> "×"),
      ]),
    ]),
    toggle(
      "data-route-latency-variance",
      "Jitter ±100 ms",
      model.jitter,
      unavailable,
      runtime.SetJitter,
    ),
    toggle(
      "data-route-notes",
      "Field notes",
      model.field_notes,
      unavailable,
      runtime.SetFieldNotes,
    ),
    button(
      "race-btn",
      "data-route-race-move",
      "Race a move",
      unavailable,
      runtime.Defer(runtime.RaceMove),
    ),
    button(
      "race-btn",
      "data-route-race-insert",
      "Crowd an insert",
      unavailable,
      runtime.Defer(runtime.RaceInsert),
    ),
    button(
      "reset-btn",
      "data-route-reset",
      "Reset",
      unavailable,
      runtime.Defer(runtime.Reset),
    ),
    h.p(
      [
        a.class("status"),
        a.attribute("data-route-status", ""),
        a.attribute("role", "status"),
        test_id("status"),
      ],
      status(model),
    ),
  ])
}

fn toggle(
  attribute: String,
  label: String,
  checked: Bool,
  disabled: Bool,
  message: fn(Bool) -> runtime.Msg,
) -> Element(runtime.Msg) {
  h.label([a.class("field-notes-toggle")], [
    h.input([
      a.type_("checkbox"),
      a.attribute(attribute, ""),
      a.checked(checked),
      a.disabled(disabled),
      event.on_check(message),
    ]),
    h.span([a.class("annot")], [h.text(label)]),
  ])
}

fn button(
  class: String,
  attribute: String,
  label: String,
  disabled: Bool,
  message: runtime.Msg,
) -> Element(runtime.Msg) {
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

fn mounted(model: runtime.Model) -> List(a.Attribute(msg)) {
  case model.phase {
    runtime.Static -> []
    _ -> [a.attribute("data-mounted", "")]
  }
}

fn pending_class(count: Int) -> String {
  "pending-count annot"
  <> case count > 0 {
    True -> " is-pending"
    False -> ""
  }
}

fn endpoint(value: flow.Endpoint) -> String {
  case value {
    flow.Replica(id) -> id
    flow.Sequencer -> "seq"
  }
}

fn option_name(selected: Option(String)) -> String {
  case selected {
    Some(name) -> name
    None -> "select a station"
  }
}

fn index_of(values: List(String), target: String) -> Int {
  values
  |> list.index_map(fn(value, index) { #(value, index) })
  |> list.find(fn(item) { item.0 == target })
  |> result.map(fn(item) { item.1 })
  |> result.unwrap(-1)
}

fn x_at(index: Int) -> Int {
  let meander = [0, 26, 42, 26, 0, -22, -36, -22]
  let remainder = index % list.length(meander)
  let normalized = case remainder < 0 {
    True -> remainder + list.length(meander)
    False -> remainder
  }
  64 + at(meander, normalized)
}

fn y_at(index: Int) -> Int {
  20 + index * 56 + 28
}

fn route_height(count: Int) -> Int {
  40 + int.max(count, 1) * 56
}

fn at(values: List(Int), index: Int) -> Int {
  case values, index {
    [], _ -> 0
    [value, ..], 0 -> value
    [_, ..rest], index -> at(rest, index - 1)
  }
}

fn indexes(last: Int) -> List(Int) {
  int.range(from: last, to: -1, with: [], run: list.prepend)
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

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/keyed
import lustre/event
import lustre/server_component
import watershed_site/sudoku/runtime as sudoku

pub type Options {
  Options(include_noscript: Bool)
}

pub fn static() -> Element(Nil) {
  view(sudoku.static_model(), Options(True))
  |> element.map(fn(_) { Nil })
}

pub fn view(model: sudoku.Model, options: Options) -> Element(sudoku.Msg) {
  let unavailable =
    model.phase == sudoku.Static
    || model.phase == sudoku.Starting
    || model.phase == sudoku.Failed
  h.section(
    [
      a.id("sudoku-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "sudoku-demo-title"),
      test_id("sudoku-demo"),
    ],
    [
      h.div([a.class("demo-head"), a.attribute("data-reveal", "rise")], [
        h.h2([a.id("sudoku-demo-title")], [
          h.text("SharedMap sudoku cells, live"),
        ]),
        h.p([], [
          h.text("Three "),
          h.code([], [h.text("watershed")]),
          h.text(
            " documents run the full runtime in your browser, wire codecs and pending queues included. The runtime is compiled to JavaScript. They talk to one ",
          ),
          h.code([], [h.text("sluice")]),
          h.text(
            ": the in-memory server that ships in the library, standing in for floodgate with no backend. A cell edit renders optimistically and pushes an op the sluice sequences; delivery is explicit, so state propagates one stamped hop at a time. Local edits are drawn in ",
          ),
          h.strong([a.class("k-pending")], [h.text("magenta")]),
          h.text(" until the sequencer stamps them; server-sequenced state is "),
          h.strong([a.class("k-seq")], [h.text("ink")]),
          h.text("."),
        ]),
        h.p([a.class("demo-hint")], [
          h.text("Click any cell to cycle its digit, type "),
          h.strong([], [h.text("1–9")]),
          h.text(
            " to write directly, or press Delete or Shift-click to clear. Arrow keys move across each board. Press ",
          ),
          h.strong([], [h.text("Race the same cell")]),
          h.text(" and A, B, and C write different digits to the center cell, "),
          h.code([], [h.text("r4c4")]),
          h.text(
            ", at the same instant. The sluice sequences those writes FIFO, and every replica converges on the last sequenced value.",
          ),
        ]),
      ]),
      h.div([a.class("rig"), test_id("sudoku-rig")], [
        board(model, sudoku.ClientA, "a"),
        board(model, sudoku.ClientB, "b"),
        board(model, sudoku.ClientC, "c"),
        h.div([a.class("channel"), a.style("grid-area", "seq")], [
          h.div(
            [
              a.class("seq-node"),
              a.attribute("data-flow-node", "seq"),
              test_id("sequence-node"),
            ],
            [
              h.span([a.class("annot")], [h.text("Sequencer")]),
              h.output(
                [
                  a.class("seq-counter"),
                  test_id("sequence"),
                  a.attribute("aria-label", "Latest sequence number"),
                ],
                [h.text("SN " <> int.to_string(model.latest_sequence))],
              ),
            ],
          ),
          h.ol(
            [
              a.class("op-log"),
              test_id("operation-log"),
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
                      <> string.drop_start(
                        sudoku.replica_label(entry.author),
                        7,
                      ),
                    ),
                  ]),
                  h.span([a.class("op-path")], [h.text(entry.label)]),
                  h.span([a.class("op-kind")], [h.text("op")]),
                ])
              }),
          ),
        ]),
        keyed.div(
          [
            a.class("flow-layer"),
            test_id("flow-layer"),
            a.attribute("aria-hidden", "true"),
          ],
          list.map(model.flows, fn(marker) {
            #(
              int.to_string(marker.id),
              h.span(
                [
                  a.class(case marker.from {
                    "seq" -> "flow-dot sequenced"
                    _ -> "flow-dot"
                  }),
                  a.attribute("data-flow-id", int.to_string(marker.id)),
                  a.attribute("data-from", marker.from),
                  a.attribute("data-to", marker.to),
                ],
                [h.span([a.class("flow-dot-label")], [h.text(marker.label)])],
              ),
            )
          }),
        ),
      ]),
      h.div(
        [
          a.class("demo-controls"),
          a.attribute("data-reveal", "rise"),
        ],
        [
          h.label([a.class("pace")], [
            h.span([a.class("annot")], [h.text("Animation speed")]),
            h.input([
              a.type_("range"),
              a.min("0.25"),
              a.max("2"),
              a.step("0.25"),
              a.value(pace_value(model.pace_quarters)),
              a.title("Playback only; does not affect simulated ordering."),
              a.disabled(unavailable),
              test_id("pace"),
              event.on_input(sudoku.SetPace),
            ]),
            h.output([test_id("pace-output")], [
              h.text(pace_value(model.pace_quarters) <> "×"),
            ]),
          ]),
          h.label([a.class("field-notes-toggle")], [
            h.input([
              a.type_("checkbox"),
              a.checked(model.jitter),
              a.title("Add random ±100 ms per hop; arrival order may change."),
              a.disabled(unavailable),
              test_id("jitter"),
              event.on_check(sudoku.SetJitter),
            ]),
            h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
          ]),
          h.button(
            [
              a.type_("button"),
              a.class("race-btn"),
              a.disabled(unavailable),
              test_id("race"),
              event.on_click(sudoku.RunRace),
            ],
            [h.text("Race the same cell")],
          ),
          h.button(
            [
              a.type_("button"),
              a.class("reset-btn"),
              a.disabled(unavailable),
              test_id("seed"),
              event.on_click(sudoku.Seed),
            ],
            [h.text("Place corner givens")],
          ),
          h.button(
            [
              a.type_("button"),
              a.class("reset-btn"),
              a.attribute(
                "aria-label",
                "Reset all replicas to an empty Sudoku board",
              ),
              a.disabled(unavailable),
              test_id("reset"),
              event.on_click(sudoku.Reset),
            ],
            [h.text("Reset")],
          ),
          h.p(
            [
              a.class("status"),
              a.attribute("role", "status"),
              test_id("status"),
            ],
            status(model),
          ),
        ],
      ),
      h.p([a.class("controls-hint")], [
        h.text(
          "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency.",
        ),
      ]),
      case options.include_noscript {
        False -> element.none()
        True ->
          element.element("noscript", [], [
            h.p([a.class("demo-noscript"), test_id("noscript")], [
              h.text(
                "The live demo needs JavaScript: it runs the production client runtime and the in-memory ",
              ),
              h.code([], [h.text("sluice")]),
              h.text(
                " as compiled JavaScript in your browser. The rest of the page works fine without it.",
              ),
            ]),
          ])
      },
      case model.phase {
        sudoku.Static ->
          h.p(
            [
              a.class("demo-noscript sudoku-fallback"),
              test_id("sudoku-fallback"),
            ],
            [
              h.text(
                "The live demo couldn't start: it runs the production client runtime against the in-memory ",
              ),
              h.code([], [h.text("sluice")]),
              h.text(
                " as compiled JavaScript, and this browser didn't load it. The rest of the page works fine without it.",
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

fn board(
  model: sudoku.Model,
  replica: sudoku.Replica,
  area: String,
) -> Element(sudoku.Msg) {
  let label = sudoku.replica_label(replica)
  let id = sudoku.replica_id(replica)
  let pending =
    model.pending
    |> list.filter(fn(marker) { marker.replica == replica })
    |> list.length
  h.article(
    [
      a.class("client"),
      a.attribute("data-client", id),
      a.attribute("data-flow-node", id),
      a.attribute("aria-label", label <> " replica"),
      a.style("grid-area", area),
      test_id("client-" <> id),
    ],
    [
      h.header([a.class("client-head")], [
        h.h3([], [h.text(label)]),
        h.span(
          [
            a.class(case pending > 0 {
              True -> "pending-count annot is-pending"
              False -> "pending-count annot"
            }),
            test_id("pending-" <> id),
          ],
          [h.text(int.to_string(pending) <> " pending")],
        ),
      ]),
      h.div(
        [
          a.class("board"),
          a.role("grid"),
          a.attribute("aria-label", label <> " 9 by 9 Sudoku cell map"),
          a.attribute("aria-rowcount", "9"),
          a.attribute("aria-colcount", "9"),
          test_id("board-" <> id),
        ],
        case model.phase {
          sudoku.Static | sudoku.Starting -> []
          _ ->
            list.repeat(Nil, 81)
            |> list.index_map(fn(_, index) {
              cell_view(model, replica, index / 9, index % 9)
            })
        },
      ),
      h.p([a.class("board-note annot")], [
        h.text("81 keys · r0c0–r8c8 · values 1–9"),
      ]),
    ],
  )
}

fn cell_view(
  model: sudoku.Model,
  replica: sudoku.Replica,
  row: Int,
  column: Int,
) -> Element(sudoku.Msg) {
  let value = sudoku.cell(model, replica, row, column)
  let key = "r" <> int.to_string(row) <> "c" <> int.to_string(column)
  let pending =
    list.any(model.pending, fn(marker) {
      marker.replica == replica && marker.key == key
    })
  let class = case value, pending {
    None, True -> "sudoku-cell is-empty k-pending"
    None, False -> "sudoku-cell is-empty"
    Some(_), True -> "sudoku-cell k-pending"
    Some(_), False -> "sudoku-cell k-seq"
  }
  let focused = case model.focus {
    Some(sudoku.Focus(focus_replica, focus_row, focus_column)) ->
      focus_replica == replica && focus_row == row && focus_column == column
    None -> row == 0 && column == 0
  }
  h.button(
    [
      a.type_("button"),
      a.class(class),
      a.role("gridcell"),
      a.attribute("aria-rowindex", int.to_string(row + 1)),
      a.attribute("aria-colindex", int.to_string(column + 1)),
      a.attribute(
        "aria-label",
        sudoku.replica_label(replica)
          <> " row "
          <> int.to_string(row + 1)
          <> ", column "
          <> int.to_string(column + 1)
          <> ", "
          <> case value {
          None -> "empty"
          Some(digit) -> "digit " <> int.to_string(digit)
        }
          <> ". Type 1 through 9 to set; Delete clears.",
      ),
      a.tabindex(case focused {
        True -> 0
        False -> -1
      }),
      test_id(
        "cell-"
        <> sudoku.replica_id(replica)
        <> "-"
        <> int.to_string(row)
        <> "-"
        <> int.to_string(column),
      ),
      click(replica, row, column),
      keydown(replica, row, column),
    ],
    [
      h.text(case value {
        None -> "·"
        Some(digit) -> int.to_string(digit)
      }),
    ],
  )
}

fn click(
  replica: sudoku.Replica,
  row: Int,
  column: Int,
) -> a.Attribute(sudoku.Msg) {
  event.advanced("click", {
    use shift <- decode.field("shiftKey", decode.bool)
    decode.success(event.handler(
      dispatch: case shift {
        True -> sudoku.ClearCell(replica, row, column)
        False -> sudoku.CycleCell(replica, row, column)
      },
      prevent_default: False,
      stop_propagation: False,
    ))
  })
  |> server_component.include(["shiftKey"])
}

fn keydown(
  replica: sudoku.Replica,
  row: Int,
  column: Int,
) -> a.Attribute(sudoku.Msg) {
  event.advanced("keydown", {
    use key <- decode.field("key", decode.string)
    use shift <- decode.field("shiftKey", decode.bool)
    use control <- decode.field("ctrlKey", decode.bool)
    use alt <- decode.field("altKey", decode.bool)
    use meta <- decode.field("metaKey", decode.bool)
    let #(message, handled) = case key {
      "ArrowUp" -> #(sudoku.MoveFocus(replica, row - 1, column), True)
      "ArrowDown" -> #(sudoku.MoveFocus(replica, row + 1, column), True)
      "ArrowLeft" -> #(sudoku.MoveFocus(replica, row, column - 1), True)
      "ArrowRight" -> #(sudoku.MoveFocus(replica, row, column + 1), True)
      "Home" -> #(
        sudoku.MoveFocus(
          replica,
          case control {
            True -> 0
            False -> row
          },
          0,
        ),
        True,
      )
      "End" -> #(
        sudoku.MoveFocus(
          replica,
          case control {
            True -> 8
            False -> row
          },
          8,
        ),
        True,
      )
      "Enter" | " " if shift -> #(sudoku.ClearCell(replica, row, column), True)
      "Delete" | "Backspace" | "0" -> #(
        sudoku.ClearCell(replica, row, column),
        True,
      )
      _ if !alt && !control && !meta -> #(
        sudoku.CellKey(replica, row, column, key),
        is_digit(key),
      )
      _ -> #(sudoku.MoveFocus(replica, row, column), False)
    }
    decode.success(event.handler(
      dispatch: message,
      prevent_default: handled,
      stop_propagation: False,
    ))
  })
  |> server_component.include(["shiftKey", "ctrlKey", "altKey", "metaKey"])
}

fn is_digit(value: String) -> Bool {
  case int.parse(value) {
    Ok(digit) -> digit >= 1 && digit <= 9
    Error(Nil) -> False
  }
}

fn pace_value(quarters: Int) -> String {
  case quarters {
    1 -> "0.25"
    2 -> "0.5"
    3 -> "0.75"
    4 -> "1"
    5 -> "1.25"
    6 -> "1.5"
    7 -> "1.75"
    _ -> "2"
  }
}

fn status(model: sudoku.Model) -> List(Element(sudoku.Msg)) {
  case model.converged {
    True -> [
      h.span([a.class("stamp converged")], [h.text("Converged")]),
      h.text(" all replicas identical · nothing pending"),
    ]
    False -> [
      h.span([a.class("stamp revising")], [h.text("Revising")]),
      h.text(" ops in flight"),
    ]
  }
}

fn test_id(id: String) -> a.Attribute(msg) {
  a.attribute("data-testid", id)
}

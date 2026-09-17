import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/sluice_js
import watershed_lustre

pub type Replica {
  ClientA
  ClientB
  ClientC
}

pub type Phase {
  Static
  Starting
  Ready
  Delivering
  Failed
}

pub type Board {
  Board(replica: Replica, cells: List(Option(Int)))
}

pub type PendingMarker {
  PendingMarker(
    sequence_number: Int,
    replica: Replica,
    key: String,
    label: String,
  )
}

pub type FlowMarker {
  FlowMarker(id: Int, from: String, to: String, label: String)
}

pub type LogEntry {
  LogEntry(sequence_number: Int, author: Replica, label: String)
}

pub type Focus {
  Focus(replica: Replica, row: Int, column: Int)
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    boards: List(Board),
    pending: List(PendingMarker),
    flows: List(FlowMarker),
    log: List(LogEntry),
    generation: Int,
    pace_quarters: Int,
    jitter: Bool,
    delivery_active: Bool,
    converged: Bool,
    error: Option(String),
    latest_sequence: Int,
    focus: Option(Focus),
    cursors: List(#(Replica, Int)),
  )
}

pub type Msg {
  Start
  Started(generation: Int, outcome: Result(Rig, DemoError))
  SetCell(replica: Replica, row: Int, column: Int, digit: Int)
  ClearCell(replica: Replica, row: Int, column: Int)
  CycleCell(replica: Replica, row: Int, column: Int)
  CellKey(replica: Replica, row: Int, column: Int, key: String)
  MoveFocus(replica: Replica, row: Int, column: Int)
  RunRace
  Seed
  MutationSubmitted(generation: Int, outcome: Result(Mutation, DemoError))
  Deliver(generation: Int)
  Delivered(generation: Int, outcome: Result(DeliveryState, DemoError))
  ClearFlow(generation: Int, marker_id: Int)
  SetPace(String)
  SetJitter(Bool)
  Reset
  ResetDone(generation: Int, outcome: Result(Rig, DemoError))
  BrowserFailed(reason: String)
}

pub opaque type Rig {
  Rig(sluice: sluice_js.Sluice, clients: List(ReplicaState))
}

type ReplicaState {
  ReplicaState(
    replica: Replica,
    client_id: String,
    document: watershed.Document(Nil),
    map: watershed.SharedMap,
  )
}

pub type Mutation {
  Mutation(
    boards: List(Board),
    pending: List(PendingMarker),
    flows: List(FlowMarker),
  )
}

pub type DeliveryState {
  DeliveryState(
    boards: List(Board),
    sequence_number: Int,
    author: Replica,
    has_more: Bool,
  )
}

pub type DemoError {
  MissingClientId(Replica)
  MissingReplica(Replica)
  InvalidCell(row: Int, column: Int)
  InvalidDigit(Int)
  InvalidValue(replica: Replica, key: String)
  UnexpectedDelivery(String)
}

pub fn static_model() -> Model {
  Model(Static, None, [], [], [], [], 0, 4, False, False, True, None, 0, None, [
    #(ClientA, 0),
    #(ClientB, 1),
    #(ClientC, 2),
  ])
}

pub fn init() -> #(Model, Effect(Msg)) {
  update(static_model(), Start)
}

pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Started(generation, _)
      | ResetDone(generation, _)
      | MutationSubmitted(generation, _)
      | Delivered(generation, _)
      | Deliver(generation)
      | ClearFlow(generation, _)
      if generation != model.generation
    -> #(model, effect.none())
    Start if model.phase == Static -> begin(model, False)
    Start -> #(model, effect.none())
    Reset ->
      begin(
        Model(
          ..static_model(),
          generation: model.generation + 1,
          pace_quarters: model.pace_quarters,
          jitter: model.jitter,
        ),
        True,
      )
    Started(_, outcome) | ResetDone(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(rig) ->
          case project_all(rig) {
            Error(reason) -> failed(model, reason)
            Ok(boards) -> #(
              Model(
                ..model,
                phase: Ready,
                rig: Some(rig),
                boards:,
                converged: True,
                error: None,
              ),
              effect.none(),
            )
          }
      }
    SetCell(replica, row, column, digit) ->
      submit(model, fn(rig) { submit_set(rig, replica, row, column, digit) })
    ClearCell(replica, row, column) ->
      submit(model, fn(rig) { submit_clear(rig, replica, row, column) })
    CycleCell(replica, row, column) -> {
      let current = cell(model, replica, row, column)
      let #(digit, cursors) = case current {
        Some(value) -> {
          let digit = value % 9 + 1
          #(digit, model.cursors)
        }
        None -> {
          let cursor =
            model.cursors
            |> list.find(fn(item) { item.0 == replica })
            |> result.map(fn(item) { item.1 })
            |> result.unwrap(0)
          let cursors =
            list.map(model.cursors, fn(item) {
              case item.0 == replica {
                True -> #(item.0, item.1 + 1)
                False -> item
              }
            })
          let digit = cursor % 9 + 1
          #(digit, cursors)
        }
      }
      submit(
        Model(..model, cursors:, focus: Some(Focus(replica, row, column))),
        fn(rig) { submit_set(rig, replica, row, column, digit) },
      )
    }
    CellKey(replica, row, column, key) ->
      case int.parse(key) {
        Ok(digit) if digit >= 1 && digit <= 9 ->
          update(model, SetCell(replica, row, column, digit))
        _ if key == "Delete" || key == "Backspace" || key == "0" ->
          update(model, ClearCell(replica, row, column))
        _ -> #(model, effect.none())
      }
    MoveFocus(replica, row, column) -> #(
      Model(
        ..model,
        focus: Some(Focus(
          replica,
          int.clamp(row, 0, 8),
          int.clamp(column, 0, 8),
        )),
      ),
      effect.none(),
    )
    RunRace -> submit(model, submit_race)
    Seed -> submit(model, submit_seed)
    MutationSubmitted(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(mutation) -> {
          let schedule = case model.delivery_active {
            True -> effect.none()
            False ->
              watershed_lustre.after(delay(model), Deliver(model.generation))
          }
          #(
            Model(
              ..model,
              phase: Delivering,
              boards: mutation.boards,
              pending: list.append(model.pending, mutation.pending),
              flows: list.append(model.flows, mutation.flows),
              delivery_active: True,
              converged: False,
            ),
            effect.batch([schedule, clear_flows(model, mutation.flows)]),
          )
        }
      }
    Deliver(_) if model.phase != Delivering -> #(model, effect.none())
    Deliver(_) ->
      case model.rig {
        Some(rig) -> #(
          model,
          watershed_lustre.perform(
            operation: fn() { deliver_group(rig) },
            outcome: fn(value) { Delivered(model.generation, value) },
          ),
        )
        None -> #(model, effect.none())
      }
    Delivered(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(delivery) -> {
          let delivered_marker =
            model.pending
            |> list.find(fn(marker) {
              marker.sequence_number == delivery.sequence_number
            })
          let pending =
            list.filter(model.pending, fn(marker) {
              marker.sequence_number > delivery.sequence_number
            })
          let flows =
            replicas()
            |> list.index_map(fn(replica, index) {
              FlowMarker(
                delivery.sequence_number * 4 + index,
                "seq",
                replica_id(replica),
                "SN " <> int.to_string(delivery.sequence_number),
              )
            })
          let next = case delivery.has_more {
            True ->
              watershed_lustre.after(delay(model), Deliver(model.generation))
            False -> effect.none()
          }
          #(
            Model(
              ..model,
              phase: case delivery.has_more {
                True -> Delivering
                False -> Ready
              },
              boards: delivery.boards,
              pending:,
              flows: list.append(model.flows, flows),
              log: [
                LogEntry(
                  delivery.sequence_number,
                  delivery.author,
                  case delivered_marker {
                    Ok(marker) -> marker.label
                    Error(Nil) ->
                      "SN " <> int.to_string(delivery.sequence_number)
                  },
                ),
                ..model.log
              ],
              latest_sequence: delivery.sequence_number,
              delivery_active: delivery.has_more,
              converged: !delivery.has_more
                && boards_equal(delivery.boards)
                && list.is_empty(pending),
            ),
            effect.batch([next, clear_flows(model, flows)]),
          )
        }
      }
    ClearFlow(_, id) -> #(
      Model(
        ..model,
        flows: list.filter(model.flows, fn(marker) { marker.id != id }),
      ),
      effect.none(),
    )
    SetPace(value) ->
      case float_quarters(value) {
        Error(Nil) -> #(model, effect.none())
        Ok(quarters) -> #(
          Model(..model, pace_quarters: int.clamp(quarters, 1, 8)),
          effect.none(),
        )
      }
    SetJitter(value) -> #(Model(..model, jitter: value), effect.none())
    BrowserFailed(reason) -> failed(model, UnexpectedDelivery(reason))
  }
}

fn submit(
  model: Model,
  operation: fn(Rig) -> Result(Mutation, DemoError),
) -> #(Model, Effect(Msg)) {
  case model.rig, model.phase {
    Some(rig), Ready | Some(rig), Delivering -> #(
      Model(..model, phase: Delivering, converged: False),
      watershed_lustre.perform(
        operation: fn() { operation(rig) },
        outcome: fn(value) { MutationSubmitted(model.generation, value) },
      ),
    )
    _, _ -> #(model, effect.none())
  }
}

fn begin(model: Model, reset: Bool) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, phase: Starting, converged: False),
    watershed_lustre.perform(operation: start_rig, outcome: fn(value) {
      case reset {
        True -> ResetDone(model.generation, value)
        False -> Started(model.generation, value)
      }
    }),
  )
}

fn failed(model: Model, reason: DemoError) -> #(Model, Effect(Msg)) {
  #(
    Model(
      ..model,
      phase: Failed,
      error: Some(describe_error(reason)),
      delivery_active: False,
      converged: False,
    ),
    effect.none(),
  )
}

fn clear_flows(model: Model, flows: List(FlowMarker)) -> Effect(Msg) {
  flows
  |> list.map(fn(marker) {
    watershed_lustre.after(delay(model), ClearFlow(model.generation, marker.id))
  })
  |> effect.batch
}

fn delay(model: Model) -> Int {
  case model.jitter {
    True -> 3200 / model.pace_quarters
    False -> 2800 / model.pace_quarters
  }
}

fn float_quarters(value: String) -> Result(Int, Nil) {
  case value {
    "0.25" -> Ok(1)
    "0.5" -> Ok(2)
    "0.75" -> Ok(3)
    "1" -> Ok(4)
    "1.25" -> Ok(5)
    "1.5" -> Ok(6)
    "1.75" -> Ok(7)
    "2" -> Ok(8)
    _ -> Error(Nil)
  }
}

pub fn start_rig() -> Result(Rig, DemoError) {
  let sluice = sluice_js.start(tenant: "sudoku-demo", document: "sudoku-demo")
  let states =
    replicas()
    |> list.map(fn(replica) {
      let document = sluice_js.connect(sluice, "user-" <> replica_id(replica))
      #(replica, document)
    })
  sluice_js.settle(sluice)
  use clients <- result.try(
    list.try_map(states, fn(state) {
      use client_id <- result.try(
        sluice_js.client_id(sluice, state.1)
        |> result.replace_error(MissingClientId(state.0)),
      )
      Ok(ReplicaState(state.0, client_id, state.1, watershed.root(state.1)))
    }),
  )
  Ok(Rig(sluice, clients))
}

pub fn submit_set(
  rig: Rig,
  replica: Replica,
  row: Int,
  column: Int,
  digit: Int,
) -> Result(Mutation, DemoError) {
  use _ <- result.try(validate_cell(row, column))
  use _ <- result.try(case digit >= 1 && digit <= 9 {
    True -> Ok(Nil)
    False -> Error(InvalidDigit(digit))
  })
  use state <- result.try(replica_state(rig, replica))
  let key = cell_key(row, column)
  watershed.set(state.map, key, json.int(digit))
  mutation(rig, [
    PendingMarker(
      sluice_js.sequence_number(rig.sluice),
      replica,
      key,
      cell_label(row, column) <> " → " <> int.to_string(digit),
    ),
  ])
}

pub fn submit_clear(
  rig: Rig,
  replica: Replica,
  row: Int,
  column: Int,
) -> Result(Mutation, DemoError) {
  use _ <- result.try(validate_cell(row, column))
  use state <- result.try(replica_state(rig, replica))
  let key = cell_key(row, column)
  watershed.delete(state.map, key)
  mutation(rig, [
    PendingMarker(
      sluice_js.sequence_number(rig.sluice),
      replica,
      key,
      cell_label(row, column) <> " clear",
    ),
  ])
}

pub fn submit_race(rig: Rig) -> Result(Mutation, DemoError) {
  use a <- result.try(write(rig, ClientA, 4, 4, 1))
  use b <- result.try(write(rig, ClientB, 4, 4, 5))
  use c <- result.try(write(rig, ClientC, 4, 4, 9))
  mutation(rig, [a, b, c])
}

pub fn submit_seed(rig: Rig) -> Result(Mutation, DemoError) {
  use a <- result.try(write(rig, ClientA, 0, 0, 5))
  use b <- result.try(write(rig, ClientA, 0, 8, 9))
  use c <- result.try(write(rig, ClientB, 8, 0, 8))
  use d <- result.try(write(rig, ClientC, 8, 8, 2))
  mutation(rig, [a, b, c, d])
}

fn write(
  rig: Rig,
  replica: Replica,
  row: Int,
  column: Int,
  digit: Int,
) -> Result(PendingMarker, DemoError) {
  use state <- result.try(replica_state(rig, replica))
  let key = cell_key(row, column)
  watershed.set(state.map, key, json.int(digit))
  Ok(PendingMarker(
    sluice_js.sequence_number(rig.sluice),
    replica,
    key,
    cell_label(row, column) <> " → " <> int.to_string(digit),
  ))
}

fn mutation(
  rig: Rig,
  pending: List(PendingMarker),
) -> Result(Mutation, DemoError) {
  use _ <- result.try(next_operation(rig))
  use boards <- result.try(project_all(rig))
  Ok(Mutation(
    boards,
    pending,
    list.map(pending, fn(marker) {
      FlowMarker(
        -marker.sequence_number,
        replica_id(marker.replica),
        "seq",
        marker.label,
      )
    }),
  ))
}

fn next_operation(rig: Rig) -> Result(sluice_js.Delivery, DemoError) {
  use next <- result.try(
    sluice_js.peek_info(rig.sluice)
    |> result.replace_error(UnexpectedDelivery("No operation is queued.")),
  )
  case next.sequence_number > 0 && next.event == "op" {
    True -> Ok(next)
    False -> Error(UnexpectedDelivery(next.event))
  }
}

pub fn deliver_group(rig: Rig) -> Result(DeliveryState, DemoError) {
  use next <- result.try(next_operation(rig))
  use author <- result.try(replica_by_client_id(rig, next.author))
  use _ <- result.try(drain_group(rig, next.sequence_number))
  use boards <- result.try(project_all(rig))
  Ok(DeliveryState(
    boards,
    next.sequence_number,
    author,
    sluice_js.pending(rig.sluice),
  ))
}

fn drain_group(rig: Rig, sequence: Int) -> Result(Nil, DemoError) {
  case sluice_js.peek_info(rig.sluice) {
    Ok(next) if next.sequence_number == sequence -> {
      use _ <- result.try(
        sluice_js.step_info(rig.sluice)
        |> result.replace_error(UnexpectedDelivery(
          "Cannot deliver the queued operation.",
        )),
      )
      drain_group(rig, sequence)
    }
    Ok(next) if next.sequence_number == 0 ->
      Error(UnexpectedDelivery(next.event))
    Ok(_) | Error(Nil) -> Ok(Nil)
  }
}

fn project_all(rig: Rig) -> Result(List(Board), DemoError) {
  list.try_map(rig.clients, fn(state) {
    use cells <- result.try(
      list.repeat(None, 81)
      |> list.index_map(fn(_, index) {
        let row = index / 9
        let column = index % 9
        case watershed.get(state.map, cell_key(row, column)) {
          Error(Nil) -> Ok(None)
          Ok(value) ->
            json.parse(json.to_string(value), decode.int)
            |> result.map(Some)
            |> result.map_error(fn(_) {
              InvalidValue(state.replica, cell_key(row, column))
            })
        }
      })
      |> result.all,
    )
    Ok(Board(state.replica, cells))
  })
}

pub fn cell(
  model: Model,
  replica: Replica,
  row: Int,
  column: Int,
) -> Option(Int) {
  case validate_cell(row, column) {
    Error(_) -> None
    Ok(Nil) ->
      case list.find(model.boards, fn(board) { board.replica == replica }) {
        Error(Nil) -> None
        Ok(board) -> cell_at(board.cells, row * 9 + column)
      }
  }
}

fn cell_at(cells: List(Option(Int)), index: Int) -> Option(Int) {
  case cells, index {
    [], _ -> None
    [cell, ..], 0 -> cell
    [_, ..rest], index -> cell_at(rest, index - 1)
  }
}

fn boards_equal(boards: List(Board)) -> Bool {
  case boards {
    [] -> True
    [first, ..rest] -> list.all(rest, fn(board) { board.cells == first.cells })
  }
}

fn validate_cell(row: Int, column: Int) -> Result(Nil, DemoError) {
  case row >= 0 && row < 9 && column >= 0 && column < 9 {
    True -> Ok(Nil)
    False -> Error(InvalidCell(row, column))
  }
}

fn replica_state(
  rig: Rig,
  replica: Replica,
) -> Result(ReplicaState, DemoError) {
  rig.clients
  |> list.find(fn(state) { state.replica == replica })
  |> result.replace_error(MissingReplica(replica))
}

fn replica_by_client_id(rig: Rig, id: String) -> Result(Replica, DemoError) {
  rig.clients
  |> list.find(fn(state) { state.client_id == id })
  |> result.map(fn(state) { state.replica })
  |> result.replace_error(UnexpectedDelivery("Unknown replica: " <> id))
}

pub fn replicas() -> List(Replica) {
  [ClientA, ClientB, ClientC]
}

pub fn replica_id(replica: Replica) -> String {
  case replica {
    ClientA -> "a"
    ClientB -> "b"
    ClientC -> "c"
  }
}

pub fn replica_label(replica: Replica) -> String {
  case replica {
    ClientA -> "Client A"
    ClientB -> "Client B"
    ClientC -> "Client C"
  }
}

fn cell_key(row: Int, column: Int) -> String {
  "r" <> int.to_string(row) <> "c" <> int.to_string(column)
}

fn cell_label(row: Int, column: Int) -> String {
  "r" <> int.to_string(row + 1) <> "c" <> int.to_string(column + 1)
}

pub fn describe_error(error: DemoError) -> String {
  case error {
    MissingClientId(replica) -> replica_label(replica) <> ": Missing client ID."
    MissingReplica(replica) -> replica_label(replica) <> ": Missing replica."
    InvalidCell(row, column) ->
      "Invalid cell: row "
      <> int.to_string(row)
      <> ", column "
      <> int.to_string(column)
      <> "."
    InvalidDigit(digit) -> "Invalid digit: " <> int.to_string(digit) <> "."
    InvalidValue(replica, key) ->
      replica_label(replica) <> ": Invalid value at " <> key <> "."
    UnexpectedDelivery(event) -> "Unexpected delivery: " <> event
  }
}

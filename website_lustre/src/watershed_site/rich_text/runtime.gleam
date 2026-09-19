import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/effect.{type Effect}
import watershed
import watershed/rich_text
import watershed/rich_text/operation_iterator.{InsertEmbed, InsertText}
import watershed/rich_text_kernel.{type RichTextEvent, RichTextChanged}
import watershed/sluice_js
import watershed/transport_js
import watershed_lustre
import watershed_site/demo/timing

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

pub type Pending {
  Pending(sequence_number: Int, replica: Replica, label: String)
}

pub type Snapshot {
  Snapshot(replica: Replica, document: rich_text.Document)
}

pub type AdapterChange {
  AdapterChange(replica: Replica, delta: String, author: Replica)
}

pub type PeerSelection {
  PeerSelection(viewer: Replica, peer: Replica, index: Int, length: Int)
}

pub type LogEntry {
  LogEntry(sequence_number: Int, author: Replica, label: String)
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    snapshots: List(Snapshot),
    pending: List(Pending),
    changes: List(AdapterChange),
    reloads: List(#(Replica, String)),
    selections: List(PeerSelection),
    log: List(LogEntry),
    generation: Int,
    pace_quarters: Int,
    jitter: Bool,
    latest_sequence: Int,
    random_seed: Int,
    delivery_armed: Bool,
    error: Option(String),
    deferred_work: List(fn(Model) -> Result(#(Model, Model), String)),
    work_running: Bool,
  )
}

pub type Msg {
  NoOp
  Defer(Msg)
  Deferred(generation: Int, outcome: Result(#(Model, Model), String))
  Start
  Started(generation: Int, outcome: Result(Model, String))
  EditorChanged(Replica, rich_text.Delta)
  SelectionChanged(Replica, Int, Int)
  SelectionCleared(Replica)
  Deliver(generation: Int)
  SetPace(String)
  SetJitter(Bool)
  Settle
  RaceType
  RaceFormat
  RaceDelete
  ScenarioEmbed
  Reset
  Reconnect(Replica)
  AdapterApplied(Replica)
  AdaptersApplied
  DocumentLoaded(Replica)
  AdapterFailed(Replica, String)
}

pub opaque type Rig {
  Rig(sluice: sluice_js.Sluice, clients: List(Client))
}

type Client {
  Client(
    replica: Replica,
    client_id: String,
    document: watershed.Document(Nil),
    rich_text: watershed.SharedRichText,
    events: transport_js.Cell(List(RichTextEvent)),
    subscription: watershed.SubscriptionToken,
  )
}

const baseline = "[{\"insert\":\"Watershed \"},{\"insert\":\"keeps\",\"attributes\":{\"bold\":true}},{\"insert\":\" every replica in the \"},{\"insert\":\"same state\",\"attributes\":{\"color\":\"#9d174d\"}},{\"insert\":\".\\n\"}]"

pub fn seed() -> String {
  "Watershed keeps every replica in the same state.\n"
}

pub fn static_model() -> Model {
  let assert Ok(document) = rich_text.parse_document(baseline)
  Model(
    phase: Static,
    rig: None,
    snapshots: list.map(replicas(), fn(replica) { Snapshot(replica, document) }),
    pending: [],
    changes: [],
    reloads: [],
    selections: [],
    log: [],
    generation: 0,
    pace_quarters: 4,
    jitter: False,
    latest_sequence: 0,
    random_seed: 73,
    delivery_armed: False,
    error: None,
    deferred_work: [],
    work_running: False,
  )
}

pub fn init() -> #(Model, Effect(Msg)) {
  let model = static_model()
  #(
    Model(..model, phase: Starting),
    watershed_lustre.perform(operation: start_model, outcome: fn(outcome) {
      Started(model.generation, outcome)
    }),
  )
}

pub fn ready_model() -> Model {
  let assert Ok(model) = start_model()
  model
}

pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Started(generation, _)
      | Deferred(generation, _)
      | Deliver(generation)
      if generation != model.generation
    -> #(model, effect.none())
    NoOp -> #(model, effect.none())
    Start if model.phase == Static -> init()
    Start -> #(model, effect.none())
    Started(_, Ok(ready)) -> #(
      Model(
        ..ready,
        generation: model.generation,
        pace_quarters: model.pace_quarters,
        jitter: model.jitter,
      ),
      effect.none(),
    )
    Started(_, Error(reason)) | AdapterFailed(_, reason) -> fail(model, reason)
    Deferred(_, Error(reason)) -> finish_deferred_error(model, reason)
    Deferred(_, Ok(pair)) -> finish_deferred(model, pair.0, pair.1)
    AdapterApplied(_)
    | AdaptersApplied
    | DocumentLoaded(_)
    | SelectionChanged(_, _, _)
    | SelectionCleared(_)
    | SetPace(_)
    | SetJitter(_) -> update_now(model, message)
    Defer(command) -> defer(model, command)
    _ -> defer(model, message)
  }
}

pub fn transition(model: Model, message: Msg) -> Model {
  update_now(model, message).0
}

fn defer(model: Model, command: Msg) -> #(Model, Effect(Msg)) {
  let work = fn(current: Model) {
    let next = transition(current, command)
    case next.error {
      Some(reason) -> Error(reason)
      None -> Ok(#(current, next))
    }
  }
  let queued =
    Model(
      ..model,
      phase: case command {
        Reset | Reconnect(_) -> Starting
        _ -> Delivering
      },
      deferred_work: list.append(model.deferred_work, [work]),
    )
  case model.work_running {
    True -> #(queued, effect.none())
    False -> start_work(queued)
  }
}

fn start_work(model: Model) -> #(Model, Effect(Msg)) {
  case model.deferred_work {
    [] -> #(Model(..model, work_running: False), effect.none())
    [work, ..] -> {
      let running = Model(..model, work_running: True)
      #(
        running,
        watershed_lustre.perform(
          operation: fn() { work(running) },
          outcome: fn(outcome) { Deferred(running.generation, outcome) },
        ),
      )
    }
  }
}

fn finish_deferred(
  model: Model,
  before: Model,
  next: Model,
) -> #(Model, Effect(Msg)) {
  let remaining = case model.deferred_work {
    [] -> []
    [_, ..rest] -> rest
  }
  let next =
    Model(
      ..next,
      changes: changed(model.changes, before.changes, next.changes),
      reloads: changed(model.reloads, before.reloads, next.reloads),
      selections: changed(model.selections, before.selections, next.selections),
      pace_quarters: changed(
        model.pace_quarters,
        before.pace_quarters,
        next.pace_quarters,
      ),
      jitter: changed(model.jitter, before.jitter, next.jitter),
      deferred_work: remaining,
      work_running: False,
    )
  let #(next, delivery) = case
    !next.delivery_armed && !list.is_empty(next.pending)
  {
    True -> {
      let #(next, delay) = sampled_delay(next)
      #(
        Model(..next, delivery_armed: True),
        watershed_lustre.after(delay, Deliver(next.generation)),
      )
    }
    False -> #(next, effect.none())
  }
  let #(next, work) = start_work(next)
  #(next, effect.batch([delivery, work]))
}

fn finish_deferred_error(
  model: Model,
  reason: String,
) -> #(Model, Effect(Msg)) {
  let remaining = case model.deferred_work {
    [] -> []
    [_, ..rest] -> rest
  }
  let #(failed, _) =
    fail(Model(..model, deferred_work: remaining, work_running: False), reason)
  start_work(failed)
}

fn changed(current: a, before: a, next: a) -> a {
  case current == before {
    True -> next
    False -> current
  }
}

fn update_now(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Started(generation, _)
      | Deferred(generation, _)
      | Deliver(generation)
      if generation != model.generation
    -> #(model, effect.none())
    NoOp | Start | Defer(_) -> #(model, effect.none())
    Started(_, Ok(ready)) -> #(ready, effect.none())
    Started(_, Error(reason)) | AdapterFailed(_, reason) -> fail(model, reason)
    Deferred(_, Ok(pair)) -> #(pair.1, effect.none())
    Deferred(_, Error(reason)) -> fail(model, reason)
    AdapterApplied(replica) -> #(
      Model(
        ..model,
        changes: list.filter(model.changes, fn(change) {
          change.replica != replica
        }),
      ),
      effect.none(),
    )
    AdaptersApplied -> #(Model(..model, changes: []), effect.none())
    DocumentLoaded(replica) -> #(
      Model(
        ..model,
        reloads: list.filter(model.reloads, fn(item) { item.0 != replica }),
      ),
      effect.none(),
    )
    SelectionChanged(replica, index, length) -> #(
      publish_selection(model, replica, Some(#(index, length))),
      effect.none(),
    )
    SelectionCleared(replica) -> #(
      publish_selection(model, replica, None),
      effect.none(),
    )
    SetPace(value) -> #(
      Model(..model, pace_quarters: pace(value, model.pace_quarters)),
      effect.none(),
    )
    SetJitter(value) -> #(Model(..model, jitter: value), effect.none())
    Reset -> {
      stop(model)
      case start_model() {
        Error(reason) -> fail(model, reason)
        Ok(reset) -> #(
          Model(
            ..reset,
            generation: model.generation + 1,
            pace_quarters: model.pace_quarters,
            jitter: model.jitter,
          ),
          effect.none(),
        )
      }
    }
    Reconnect(replica) -> reconnect(model, replica)
    EditorChanged(replica, delta) -> submit(model, replica, delta)
    Settle -> settle(model)
    RaceType | RaceFormat | RaceDelete | ScenarioEmbed -> #(
      model,
      effect.none(),
    )
    Deliver(_) -> deliver(model)
  }
}

fn submit(
  model: Model,
  replica: Replica,
  delta: rich_text.Delta,
) -> #(Model, Effect(Msg)) {
  case model.rig, client_from_model(model, replica) {
    Some(rig), Ok(client) -> {
      clear_events(rig)
      let before = sluice_js.sequence_number(rig.sluice)
      watershed.submit_rich_text(client.rich_text, delta)
      let after = sluice_js.sequence_number(rig.sluice)
      clear_events(rig)
      case project_all(rig) {
        Error(reason) -> fail(model, reason)
        Ok(snapshots) -> #(
          Model(
            ..model,
            phase: Delivering,
            snapshots:,
            pending: list.append(model.pending, [
              Pending(
                sequence_number: case after > before {
                  True -> after
                  False -> 0
                },
                replica:,
                label: describe(delta),
              ),
            ]),
            selections: transform_viewer(model.selections, replica, delta, None),
          ),
          effect.none(),
        )
      }
    }
    _, Error(reason) -> fail(model, reason)
    None, _ -> fail(model, "The rich-text rig is not available.")
  }
}

fn deliver(model: Model) -> #(Model, Effect(Msg)) {
  case model.rig, model.pending {
    None, _ -> fail(model, "The rich-text rig is not available.")
    _, [] -> #(
      Model(..model, phase: Ready, delivery_armed: False),
      effect.none(),
    )
    Some(rig), [next, ..] -> {
      clear_events(rig)
      case next_operation(rig.sluice) {
        Error(reason) -> fail(model, reason)
        Ok(delivery) ->
          case drain(rig.sluice, delivery.sequence_number) {
            Error(reason) -> fail(model, reason)
            Ok(Nil) -> {
              let author =
                replica_by_client_id(rig, delivery.author)
                |> result.unwrap(next.replica)
              let promoted = sluice_js.sequence_number(rig.sluice)
              let pending =
                acknowledge_pending(
                  model.pending,
                  delivery.sequence_number,
                  author,
                  promoted,
                )
              case project_all(rig) {
                Error(reason) -> fail(model, reason)
                Ok(snapshots) -> {
                  let changes = remote_changes(rig, author)
                  #(
                    Model(
                      ..model,
                      phase: case list.is_empty(pending) {
                        True -> Ready
                        False -> Delivering
                      },
                      snapshots:,
                      pending:,
                      changes: list.append(model.changes, changes),
                      selections: list.fold(
                        changes,
                        model.selections,
                        fn(selections, change) {
                          transform_change(selections, change, author)
                        },
                      ),
                      log: [
                        LogEntry(
                          delivery.sequence_number,
                          author,
                          pending_label(model.pending, delivery.sequence_number),
                        ),
                        ..model.log
                      ],
                      latest_sequence: delivery.sequence_number,
                      delivery_armed: False,
                    ),
                    effect.none(),
                  )
                }
              }
            }
          }
      }
    }
  }
}

fn reconnect(model: Model, replica: Replica) -> #(Model, Effect(Msg)) {
  case model.rig, client_from_model(model, replica) {
    Some(rig), Ok(client) -> {
      sluice_js.reconnect(rig.sluice, client.document)
      sluice_js.settle(rig.sluice)
      case refresh_client_identity(rig, client) {
        Error(reason) -> fail(model, reason)
        Ok(refreshed) ->
          case project_all(refreshed) {
            Error(reason) -> fail(model, reason)
            Ok(snapshots) -> #(
              Model(
                ..model,
                phase: Ready,
                rig: Some(refreshed),
                snapshots:,
                pending: [],
                changes: [],
                reloads: list.map(snapshots, fn(snapshot) {
                  #(snapshot.replica, document_json_from(snapshot.document))
                }),
              ),
              effect.none(),
            )
          }
      }
    }
    _, Error(reason) -> fail(model, reason)
    None, _ -> fail(model, "The rich-text rig is not available.")
  }
}

fn settle(model: Model) -> #(Model, Effect(Msg)) {
  case model.pending {
    [] -> #(Model(..model, phase: Ready, delivery_armed: False), effect.none())
    [_, ..] -> {
      let #(next, _) = deliver(Model(..model, delivery_armed: False))
      case next.error {
        Some(_) -> #(next, effect.none())
        None -> settle(next)
      }
    }
  }
}

fn refresh_client_identity(rig: Rig, client: Client) -> Result(Rig, String) {
  use client_id <- result.try(
    sluice_js.client_id(rig.sluice, client.document)
    |> result.replace_error("Missing client ID after reconnect."),
  )
  let refreshed = Client(..client, client_id:)
  Ok(
    Rig(..rig, clients: [
      refreshed,
      ..list.filter(rig.clients, fn(item) { item.replica != client.replica })
    ]),
  )
}

fn publish_selection(
  model: Model,
  peer: Replica,
  selection: Option(#(Int, Int)),
) -> Model {
  let selections = list.filter(model.selections, fn(item) { item.peer != peer })
  case selection {
    None -> Model(..model, selections:)
    Some(#(index, length)) ->
      Model(
        ..model,
        selections: list.append(
          selections,
          replicas()
            |> list.filter(fn(viewer) { viewer != peer })
            |> list.map(fn(viewer) {
              PeerSelection(viewer, peer, int.max(0, index), int.max(0, length))
            }),
        ),
      )
  }
}

fn transform_viewer(
  selections: List(PeerSelection),
  viewer: Replica,
  delta: rich_text.Delta,
  author: Option(Replica),
) -> List(PeerSelection) {
  list.map(selections, fn(item) {
    case item.viewer == viewer, author == Some(item.peer) {
      False, _ | True, True -> item
      True, False -> {
        let assert Ok(selection) = rich_text.selection(item.index, item.length)
        case rich_text.transform_selection(delta, selection, False) {
          Error(_) -> item
          Ok(transformed) ->
            PeerSelection(
              ..item,
              index: rich_text.selection_index(transformed),
              length: rich_text.selection_length(transformed),
            )
        }
      }
    }
  })
}

fn transform_change(
  selections: List(PeerSelection),
  change: AdapterChange,
  author: Replica,
) -> List(PeerSelection) {
  case rich_text.parse_delta(change.delta) {
    Error(_) -> selections
    Ok(delta) ->
      transform_viewer(selections, change.replica, delta, Some(author))
  }
}

fn start_model() -> Result(Model, String) {
  use rig <- result.try(start_rig())
  use snapshots <- result.try(project_all(rig))
  Ok(
    Model(
      ..static_model(),
      phase: Ready,
      rig: Some(rig),
      snapshots:,
      reloads: list.map(snapshots, fn(snapshot) {
        #(snapshot.replica, document_json_from(snapshot.document))
      }),
    ),
  )
}

fn start_rig() -> Result(Rig, String) {
  let sluice =
    sluice_js.start(tenant: "rich-text-demo", document: "rich-text-demo")
  let documents =
    list.map(replicas(), fn(replica) {
      #(replica, sluice_js.connect(sluice, "user-" <> replica_id(replica)))
    })
  sluice_js.settle(sluice)
  let assert [#(ClientA, alpha), ..] = documents
  use rich_text <- result.try(watershed.create_rich_text(alpha))
  use initial <- result.try(
    rich_text.parse_delta(baseline)
    |> result.map_error(fn(_) { "Invalid rich-text baseline." }),
  )
  watershed.submit_rich_text(rich_text, initial)
  watershed.set(
    watershed.root(alpha),
    "doc",
    watershed.rich_text_handle_of(rich_text),
  )
  sluice_js.settle(sluice)
  use clients <- result.try(
    list.try_map(documents, fn(item) {
      use client_id <- result.try(
        sluice_js.client_id(sluice, item.1)
        |> result.replace_error("Missing client ID."),
      )
      use channel <- result.try(case item.0 {
        ClientA -> Ok(rich_text)
        ClientB | ClientC -> {
          use stored <- result.try(
            watershed.get(watershed.root(item.1), "doc")
            |> result.replace_error("Missing rich-text handle."),
          )
          watershed.resolve_rich_text(item.1, stored)
        }
      })
      let events = transport_js.new_cell([])
      let subscription =
        watershed.subscribe_rich_text(channel, fn(event) {
          transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
        })
      Ok(Client(item.0, client_id, item.1, channel, events, subscription))
    }),
  )
  Ok(Rig(sluice, clients))
}

fn stop(model: Model) -> Nil {
  case model.rig {
    None -> Nil
    Some(rig) ->
      list.each(rig.clients, fn(client) {
        watershed.unsubscribe(client.subscription)
      })
  }
}

fn project_all(rig: Rig) -> Result(List(Snapshot), String) {
  list.try_map(rig.clients, fn(client) {
    use document <- result.try(
      watershed.rich_text_view(client.rich_text)
      |> result.replace_error("Invalid rich-text view."),
    )
    Ok(Snapshot(client.replica, document))
  })
}

fn remote_changes(rig: Rig, author: Replica) -> List(AdapterChange) {
  rig.clients
  |> list.filter(fn(client) { client.replica != author })
  |> list.flat_map(fn(client) {
    let events = take_events(client)
    events
    |> list.filter_map(fn(event) {
      case event {
        RichTextChanged(_, True) -> Error(Nil)
        RichTextChanged(delta, False) ->
          Ok(AdapterChange(client.replica, delta_json(delta), author))
      }
    })
  })
}

fn clear_events(rig: Rig) -> Nil {
  list.each(rig.clients, fn(client) { transport_js.set_cell(client.events, []) })
}

fn take_events(client: Client) -> List(RichTextEvent) {
  let events = transport_js.get_cell(client.events) |> list.reverse
  transport_js.set_cell(client.events, [])
  events
}

fn next_operation(
  sluice: sluice_js.Sluice,
) -> Result(sluice_js.Delivery, String) {
  use next <- result.try(
    sluice_js.peek_info(sluice)
    |> result.replace_error("No rich-text operation is queued."),
  )
  case next.sequence_number > 0 && next.event == "op" {
    True -> Ok(next)
    False -> Error("Unexpected delivery: " <> next.event)
  }
}

fn drain(
  sluice: sluice_js.Sluice,
  sequence_number: Int,
) -> Result(Nil, String) {
  case sluice_js.peek_info(sluice) {
    Ok(next) if next.sequence_number == sequence_number -> {
      use _ <- result.try(
        sluice_js.step_info(sluice)
        |> result.replace_error("Cannot deliver the rich-text operation."),
      )
      drain(sluice, sequence_number)
    }
    Ok(next) if next.sequence_number == 0 ->
      Error("Unexpected delivery: " <> next.event)
    Ok(_) | Error(Nil) -> Ok(Nil)
  }
}

fn acknowledge_pending(
  pending: List(Pending),
  sequence_number: Int,
  author: Replica,
  promoted_sequence_number: Int,
) -> List(Pending) {
  pending
  |> list.filter(fn(item) { item.sequence_number != sequence_number })
  |> list.map(fn(item) {
    case
      item.sequence_number == 0
      && item.replica == author
      && promoted_sequence_number > sequence_number
    {
      True -> Pending(..item, sequence_number: promoted_sequence_number)
      False -> item
    }
  })
}

fn pending_label(pending: List(Pending), sequence_number: Int) -> String {
  pending
  |> list.find(fn(item) { item.sequence_number == sequence_number })
  |> result.map(fn(item) { item.label })
  |> result.unwrap("edit")
}

pub fn adapter_changes(model: Model, replica: Replica) -> List(String) {
  model.changes
  |> list.filter_map(fn(change) {
    case change.replica == replica {
      True -> Ok(change.delta)
      False -> Error(Nil)
    }
  })
}

pub fn peer_selection(
  model: Model,
  viewer: Replica,
  peer: Replica,
) -> Option(#(Int, Int)) {
  model.selections
  |> list.find(fn(item) { item.viewer == viewer && item.peer == peer })
  |> result.map(fn(item) { #(item.index, item.length) })
  |> option_from_result
}

pub fn selections_json(model: Model, viewer: Replica) -> String {
  model.selections
  |> list.filter(fn(item) { item.viewer == viewer })
  |> list.map(fn(item) {
    json.object([
      #("id", json.string(replica_id(item.peer))),
      #("name", json.string(replica_label(item.peer))),
      #("colour", json.string(replica_colour(item.peer))),
      #("index", json.int(item.index)),
      #("length", json.int(item.length)),
    ])
  })
  |> json.preprocessed_array
  |> json.to_string
}

pub fn document_reload(model: Model, replica: Replica) -> Option(String) {
  model.reloads |> list.key_find(replica) |> option_from_result
}

pub fn document_json(model: Model, replica: Replica) -> String {
  document_for(model.snapshots, replica)
}

fn document_for(snapshots: List(Snapshot), replica: Replica) -> String {
  snapshots
  |> list.find(fn(snapshot) { snapshot.replica == replica })
  |> result.map(fn(snapshot) { document_json_from(snapshot.document) })
  |> result.unwrap("[]")
}

fn document_json_from(document: rich_text.Document) -> String {
  document |> rich_text.document_to_json |> json.to_string
}

fn delta_json(delta: rich_text.Delta) -> String {
  delta |> rich_text.delta_to_json |> json.to_string
}

pub fn canonical(model: Model, replica: Replica) -> String {
  snapshot(model, replica).document
  |> rich_text.document_to_operations
  |> list.map(fn(operation) {
    case operation {
      InsertText(text, _) -> text
      InsertEmbed(_, _) -> "▣"
      _ -> ""
    }
  })
  |> string.concat
}

pub fn snapshot(model: Model, replica: Replica) -> Snapshot {
  model.snapshots
  |> list.find(fn(snapshot) { snapshot.replica == replica })
  |> result.unwrap({
    let assert Ok(document) = rich_text.parse_document(baseline)
    Snapshot(replica, document)
  })
}

pub fn pending_count(model: Model, replica: Replica) -> Int {
  model.pending
  |> list.filter(fn(item) { item.replica == replica })
  |> list.length
}

pub fn client_identity(model: Model, replica: Replica) -> Option(String) {
  case client_from_model(model, replica) {
    Ok(client) -> Some(client.client_id)
    Error(_) -> None
  }
}

pub fn all_documents_equal(model: Model) -> Bool {
  case model.snapshots {
    [] -> True
    [first, ..rest] ->
      list.all(rest, fn(snapshot) { snapshot.document == first.document })
  }
}

fn describe(delta: rich_text.Delta) -> String {
  case rich_text.delta_to_operations(delta) {
    [InsertText(text, _), ..] -> "insert " <> text
    [InsertEmbed(_, _), ..] -> "insert embed"
    _ -> "edit"
  }
}

fn client_from_model(model: Model, replica: Replica) -> Result(Client, String) {
  case model.rig {
    None -> Error("The rich-text rig is not available.")
    Some(rig) ->
      rig.clients
      |> list.find(fn(client) { client.replica == replica })
      |> result.replace_error(replica_label(replica) <> ": Missing replica.")
  }
}

fn replica_by_client_id(rig: Rig, client_id: String) -> Result(Replica, Nil) {
  rig.clients
  |> list.find(fn(client) { client.client_id == client_id })
  |> result.map(fn(client) { client.replica })
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

fn replica_colour(replica: Replica) -> String {
  case replica {
    ClientA -> "#9d174d"
    ClientB -> "#1d4ed8"
    ClientC -> "#237a4b"
  }
}

fn option_from_result(value: Result(a, b)) -> Option(a) {
  case value {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn sampled_delay(model: Model) -> #(Model, Int) {
  let #(seed, sample) = timing.next_sample(model.random_seed)
  #(
    Model(..model, random_seed: seed),
    timing.delay_ms(model.pace_quarters, model.jitter, sample),
  )
}

fn pace(value: String, fallback: Int) -> Int {
  case value {
    "0.25" -> 1
    "0.5" -> 2
    "0.75" -> 3
    "1" -> 4
    "1.25" -> 5
    "1.5" -> 6
    "1.75" -> 7
    "2" -> 8
    _ -> fallback
  }
}

fn fail(model: Model, reason: String) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, phase: Failed, error: Some(reason), delivery_armed: False),
    effect.none(),
  )
}

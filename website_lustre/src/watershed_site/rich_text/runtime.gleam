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
  AdapterChange(replica: Replica, delta: String)
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    snapshots: List(Snapshot),
    pending: List(Pending),
    changes: List(AdapterChange),
    reloads: List(#(Replica, String)),
    generation: Int,
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
  Deliver(generation: Int)
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
    generation: 0,
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
      Model(..ready, generation: model.generation),
      effect.none(),
    )
    Started(_, Error(reason)) | AdapterFailed(_, reason) -> fail(model, reason)
    Deferred(_, Error(reason)) -> finish_deferred_error(model, reason)
    Deferred(_, Ok(pair)) -> finish_deferred(model, pair.0, pair.1)
    AdapterApplied(_) | AdaptersApplied | DocumentLoaded(_) ->
      update_now(model, message)
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
      deferred_work: remaining,
      work_running: False,
    )
  let #(next, delivery) = case
    !next.delivery_armed && !list.is_empty(next.pending)
  {
    True -> #(
      Model(..next, delivery_armed: True),
      watershed_lustre.after(150, Deliver(next.generation)),
    )
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
    Reset -> {
      stop(model)
      case start_model() {
        Error(reason) -> fail(model, reason)
        Ok(reset) -> #(
          Model(..reset, generation: model.generation + 1),
          effect.none(),
        )
      }
    }
    Reconnect(replica) -> reconnect(model, replica)
    EditorChanged(replica, delta) -> submit(model, replica, delta)
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
                Ok(snapshots) -> #(
                  Model(
                    ..model,
                    phase: case list.is_empty(pending) {
                      True -> Ready
                      False -> Delivering
                    },
                    snapshots:,
                    pending:,
                    changes: list.append(
                      model.changes,
                      remote_changes(rig, author),
                    ),
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

fn reconnect(model: Model, replica: Replica) -> #(Model, Effect(Msg)) {
  case model.rig, client_from_model(model, replica) {
    Some(rig), Ok(client) -> {
      sluice_js.reconnect(rig.sluice, client.document)
      sluice_js.settle(rig.sluice)
      case project_all(rig) {
        Error(reason) -> fail(model, reason)
        Ok(snapshots) -> #(
          Model(
            ..model,
            phase: Ready,
            snapshots:,
            pending: [],
            changes: [],
            reloads: set_reload(
              model.reloads,
              replica,
              document_for(snapshots, replica),
            ),
          ),
          effect.none(),
        )
      }
    }
    _, Error(reason) -> fail(model, reason)
    None, _ -> fail(model, "The rich-text rig is not available.")
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
          Ok(AdapterChange(client.replica, delta_json(delta)))
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

fn set_reload(
  reloads: List(#(Replica, String)),
  replica: Replica,
  document: String,
) -> List(#(Replica, String)) {
  [#(replica, document), ..list.filter(reloads, fn(item) { item.0 != replica })]
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

fn option_from_result(value: Result(a, b)) -> Option(a) {
  case value {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn fail(model: Model, reason: String) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, phase: Failed, error: Some(reason), delivery_armed: False),
    effect.none(),
  )
}

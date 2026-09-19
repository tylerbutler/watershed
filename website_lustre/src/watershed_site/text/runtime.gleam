import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/sluice_js
import watershed_lustre
import watershed_lustre/grapheme_diff

pub type Replica {
  ClientA
  ClientB
  ClientC
  ElementA
  ElementB
}

pub type Phase {
  Static
  Starting
  Ready
  Delivering
  Failed
}

pub type Channel {
  Mechanics
  Elements
}

pub type Pending {
  Pending(
    sequence_number: Int,
    replica: Replica,
    channel: Channel,
    label: String,
  )
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    values: List(#(Replica, String)),
    pending: List(Pending),
    cursors: List(#(Replica, String)),
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
  Insert(Replica, Int, String)
  ReplaceValue(Replica, String)
  ElementChanged(Replica)
  CursorChanged(Replica, String)
  Deliver(generation: Int)
  Reset
  EditorFailed(Replica, String)
}

pub opaque type Rig {
  Rig(
    mechanics: sluice_js.Sluice,
    elements: sluice_js.Sluice,
    clients: List(Client),
  )
}

type Client {
  Client(
    replica: Replica,
    client_id: String,
    document: watershed.Document(Nil),
    text: watershed.SharedText,
  )
}

const mechanics_seed = "río 🛶 café ☕ 👨‍👩‍👧 weir 🏞️"

const element_seed = "Select a few words here, then look at the other pane. Type in one editor while your caret is in the other — it stays on its text."

pub fn seed() -> String {
  mechanics_seed
}

pub fn static_model() -> Model {
  Model(
    phase: Static,
    rig: None,
    values: initial_values(),
    pending: [],
    cursors: [],
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
    Started(_, Error(reason)) | EditorFailed(_, reason) -> fail(model, reason)
    Deferred(_, Error(reason)) -> finish_deferred_error(model, reason)
    Deferred(_, Ok(pair)) -> finish_deferred(model, pair.0, pair.1)
    CursorChanged(_, _) -> update_now(model, message)
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
        Reset -> Starting
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
      cursors: changed(model.cursors, before.cursors, next.cursors),
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
    Started(_, Error(reason)) | EditorFailed(_, reason) -> fail(model, reason)
    Deferred(_, Ok(pair)) -> #(pair.1, effect.none())
    Deferred(_, Error(reason)) -> fail(model, reason)
    CursorChanged(replica, payload) -> #(
      Model(..model, cursors: [
        #(replica, payload),
        ..list.filter(model.cursors, fn(item) { item.0 != replica })
      ]),
      effect.none(),
    )
    Reset ->
      case start_model() {
        Error(reason) -> fail(model, reason)
        Ok(reset) -> #(
          Model(..reset, generation: model.generation + 1),
          effect.none(),
        )
      }
    Insert(replica, index, inserted) ->
      mutate(
        model,
        replica,
        fn(text) { watershed.text_insert(text, index, inserted) },
        "insert",
      )
    ReplaceValue(replica, next_value) ->
      case client_from_model(model, replica) {
        Error(reason) -> fail(model, reason)
        Ok(client) ->
          case
            grapheme_diff.diff(watershed.text_value(client.text), next_value)
          {
            grapheme_diff.NoChange -> #(model, effect.none())
            grapheme_diff.Insert(index, inserted) ->
              mutate(
                model,
                replica,
                fn(text) { watershed.text_insert(text, index, inserted) },
                "insert",
              )
            grapheme_diff.Delete(start, end) ->
              mutate(
                model,
                replica,
                fn(text) { watershed.text_delete_range(text, start, end) },
                "delete",
              )
            grapheme_diff.Replace(start, end, inserted) ->
              mutate(
                model,
                replica,
                fn(text) {
                  watershed.text_replace_range(text, start, end, inserted)
                },
                "replace",
              )
          }
      }
    ElementChanged(replica) -> record_external_edit(model, replica)
    Deliver(_) -> deliver(model)
  }
}

fn mutate(
  model: Model,
  replica: Replica,
  operation: fn(watershed.SharedText) -> Result(Nil, String),
  label: String,
) -> #(Model, Effect(Msg)) {
  case model.rig, client_from_model(model, replica) {
    Some(rig), Ok(client) -> {
      let channel = channel_for(replica)
      let sluice = sluice_for(rig, channel)
      let before = sluice_js.sequence_number(sluice)
      case operation(client.text) {
        Error(reason) -> fail(model, reason)
        Ok(Nil) -> {
          let after = sluice_js.sequence_number(sluice)
          project(
            model,
            rig,
            list.append(model.pending, [
              Pending(
                sequence_number: case after > before {
                  True -> after
                  False -> 0
                },
                replica:,
                channel:,
                label:,
              ),
            ]),
          )
        }
      }
    }
    _, Error(reason) -> fail(model, reason)
    None, _ -> fail(model, "The text rig is not available.")
  }
}

fn record_external_edit(
  model: Model,
  replica: Replica,
) -> #(Model, Effect(Msg)) {
  case model.rig {
    None -> fail(model, "The text rig is not available.")
    Some(rig) -> {
      let channel = channel_for(replica)
      let sluice = sluice_for(rig, channel)
      let sequence_number = sluice_js.sequence_number(sluice)
      let already_recorded =
        list.any(model.pending, fn(item) {
          item.channel == channel
          && item.replica == replica
          && item.sequence_number == sequence_number
        })
      project(model, rig, case already_recorded || !sluice_js.pending(sluice) {
        True -> model.pending
        False ->
          list.append(model.pending, [
            Pending(sequence_number, replica, channel, "edit"),
          ])
      })
    }
  }
}

fn project(
  model: Model,
  rig: Rig,
  pending: List(Pending),
) -> #(Model, Effect(Msg)) {
  #(
    Model(
      ..model,
      phase: case list.is_empty(pending) {
        True -> Ready
        False -> Delivering
      },
      values: values(rig),
      pending:,
    ),
    effect.none(),
  )
}

fn deliver(model: Model) -> #(Model, Effect(Msg)) {
  case model.rig, model.pending {
    None, _ -> fail(model, "The text rig is not available.")
    _, [] -> #(
      Model(..model, phase: Ready, delivery_armed: False),
      effect.none(),
    )
    Some(rig), [next, ..] -> {
      let sluice = sluice_for(rig, next.channel)
      case next_operation(sluice) {
        Error(reason) -> fail(model, reason)
        Ok(delivery) ->
          case drain(sluice, delivery.sequence_number) {
            Error(reason) -> fail(model, reason)
            Ok(Nil) -> {
              let author =
                replica_by_client_id(rig, next.channel, delivery.author)
                |> result.unwrap(next.replica)
              let promoted = sluice_js.sequence_number(sluice)
              let pending =
                acknowledge_pending(
                  model.pending,
                  next.channel,
                  delivery.sequence_number,
                  author,
                  promoted,
                )
              #(
                Model(
                  ..model,
                  phase: case list.is_empty(pending) {
                    True -> Ready
                    False -> Delivering
                  },
                  values: values(rig),
                  pending:,
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

fn acknowledge_pending(
  pending: List(Pending),
  channel: Channel,
  sequence_number: Int,
  author: Replica,
  promoted_sequence_number: Int,
) -> List(Pending) {
  pending
  |> list.filter(fn(item) {
    !{ item.channel == channel && item.sequence_number == sequence_number }
  })
  |> list.map(fn(item) {
    case
      item.channel == channel
      && item.sequence_number == 0
      && item.replica == author
      && promoted_sequence_number > sequence_number
    {
      True -> Pending(..item, sequence_number: promoted_sequence_number)
      False -> item
    }
  })
}

fn start_model() -> Result(Model, String) {
  use rig <- result.try(start_rig())
  Ok(Model(..static_model(), phase: Ready, rig: Some(rig), values: values(rig)))
}

fn start_rig() -> Result(Rig, String) {
  use mechanics <- result.try(start_channel(
    "text-demo",
    [ClientA, ClientB, ClientC],
    mechanics_seed,
  ))
  use elements <- result.try(start_channel(
    "text-element-demo",
    [ElementA, ElementB],
    element_seed,
  ))
  Ok(Rig(mechanics.0, elements.0, list.append(mechanics.1, elements.1)))
}

fn start_channel(
  document_id: String,
  replicas: List(Replica),
  initial: String,
) -> Result(#(sluice_js.Sluice, List(Client)), String) {
  let sluice = sluice_js.start(tenant: "text-demo", document: document_id)
  let documents =
    list.map(replicas, fn(replica) {
      #(replica, sluice_js.connect(sluice, "user-" <> replica_id(replica)))
    })
  sluice_js.settle(sluice)
  let assert [#(creator_replica, creator_document), ..] = documents
  use created <- result.try(watershed.create_text(creator_document))
  use _ <- result.try(watershed.text_insert(created, 0, initial))
  watershed.set(
    watershed.root(creator_document),
    "prose",
    watershed.text_handle_of(created),
  )
  sluice_js.settle(sluice)
  use clients <- result.try(
    list.try_map(documents, fn(item) {
      use client_id <- result.try(
        sluice_js.client_id(sluice, item.1)
        |> result.replace_error("Missing client ID."),
      )
      case item.0 == creator_replica {
        True -> Ok(Client(item.0, client_id, item.1, created))
        False -> {
          use stored <- result.try(
            watershed.get(watershed.root(item.1), "prose")
            |> result.replace_error("Missing text handle."),
          )
          use text <- result.try(watershed.resolve_text(item.1, stored))
          Ok(Client(item.0, client_id, item.1, text))
        }
      }
    }),
  )
  Ok(#(sluice, clients))
}

fn next_operation(
  sluice: sluice_js.Sluice,
) -> Result(sluice_js.Delivery, String) {
  use next <- result.try(
    sluice_js.peek_info(sluice)
    |> result.replace_error("No text operation is queued."),
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
        |> result.replace_error("Cannot deliver the text operation."),
      )
      drain(sluice, sequence_number)
    }
    Ok(next) if next.sequence_number == 0 ->
      Error("Unexpected delivery: " <> next.event)
    Ok(_) | Error(Nil) -> Ok(Nil)
  }
}

fn values(rig: Rig) -> List(#(Replica, String)) {
  list.map(rig.clients, fn(client) {
    #(client.replica, watershed.text_value(client.text))
  })
}

fn initial_values() -> List(#(Replica, String)) {
  [
    #(ClientA, mechanics_seed),
    #(ClientB, mechanics_seed),
    #(ClientC, mechanics_seed),
    #(ElementA, element_seed),
    #(ElementB, element_seed),
  ]
}

pub fn value(model: Model, replica: Replica) -> String {
  model.values
  |> list.key_find(replica)
  |> result.unwrap("")
}

pub fn all_values_equal(model: Model) -> Bool {
  let mechanics = [
    value(model, ClientA),
    value(model, ClientB),
    value(model, ClientC),
  ]
  case mechanics {
    [] -> True
    [first, ..rest] -> list.all(rest, fn(item) { item == first })
  }
}

pub fn peer_cursor(model: Model, replica: Replica) -> Option(String) {
  let peer = case replica {
    ElementA -> ElementB
    ElementB -> ElementA
    _ -> replica
  }
  model.cursors |> list.key_find(peer) |> option_from_result
}

pub fn channel(model: Model, replica: Replica) -> Option(watershed.SharedText) {
  case model.rig {
    None -> None
    Some(rig) ->
      rig.clients
      |> list.find(fn(client) { client.replica == replica })
      |> result.map(fn(client) { client.text })
      |> option_from_result
  }
}

pub fn pending_count(model: Model, replica: Replica) -> Int {
  model.pending
  |> list.filter(fn(item) { item.replica == replica })
  |> list.length
}

fn client_from_model(model: Model, replica: Replica) -> Result(Client, String) {
  case model.rig {
    None -> Error("The text rig is not available.")
    Some(rig) ->
      rig.clients
      |> list.find(fn(client) { client.replica == replica })
      |> result.replace_error(replica_label(replica) <> ": Missing replica.")
  }
}

fn replica_by_client_id(
  rig: Rig,
  channel: Channel,
  client_id: String,
) -> Result(Replica, Nil) {
  rig.clients
  |> list.find(fn(client) {
    channel_for(client.replica) == channel && client.client_id == client_id
  })
  |> result.map(fn(client) { client.replica })
}

fn channel_for(replica: Replica) -> Channel {
  case replica {
    ClientA | ClientB | ClientC -> Mechanics
    ElementA | ElementB -> Elements
  }
}

fn sluice_for(rig: Rig, channel: Channel) -> sluice_js.Sluice {
  case channel {
    Mechanics -> rig.mechanics
    Elements -> rig.elements
  }
}

pub fn replica_id(replica: Replica) -> String {
  case replica {
    ClientA | ElementA -> "a"
    ClientB | ElementB -> "b"
    ClientC -> "c"
  }
}

pub fn replica_label(replica: Replica) -> String {
  case replica {
    ClientA | ElementA -> "Client A"
    ClientB | ElementB -> "Client B"
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

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/effect.{type Effect}
import watershed
import watershed/sluice_js
import watershed_lustre
import watershed_lustre/grapheme_diff
import watershed_lustre/grapheme_offset
import watershed_site/demo/timing

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

pub type LogEntry {
  LogEntry(sequence_number: Int, author: Replica, label: String)
}

pub type Composition {
  Composition(
    replica: Replica,
    frozen: String,
    region: #(Int, Int),
    span: Result(#(watershed.TextAnchor, watershed.TextAnchor), Nil),
  )
}

pub type PinnedAnchor {
  PinnedAnchor(replica: Replica, pinned_at: Int, anchor: watershed.TextAnchor)
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    values: List(#(Replica, String)),
    pending: List(Pending),
    cursors: List(#(Replica, String)),
    selections: List(#(Replica, #(Int, Int))),
    compositions: List(Composition),
    committed_values: List(#(Replica, String)),
    anchors: List(PinnedAnchor),
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
  Insert(Replica, Int, String)
  ReplaceValue(Replica, String)
  InputChanged(Replica, String, Int, Int)
  SelectionChanged(Replica, Int, Int)
  CompositionStarted(Replica, String, Int, Int)
  CompositionEnded(Replica, String, Int, Int)
  PinAnchor(Replica)
  ClearAnchor(Replica)
  RaceInserts
  RaceOverlap
  ElementChanged(Replica)
  CursorChanged(Replica, String)
  Deliver(generation: Int)
  SetPace(String)
  SetJitter(Bool)
  Settle
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
    selections: [],
    compositions: [],
    committed_values: [],
    anchors: [],
    log: [],
    generation: 0,
    pace_quarters: 4,
    jitter: False,
    latest_sequence: 0,
    random_seed: 41,
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
    Started(_, Error(reason)) | EditorFailed(_, reason) -> fail(model, reason)
    Deferred(_, Error(reason)) -> finish_deferred_error(model, reason)
    Deferred(_, Ok(pair)) -> finish_deferred(model, pair.0, pair.1)
    CursorChanged(_, _)
    | SelectionChanged(_, _, _)
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
    case next.phase, next.error {
      Failed, Some(reason) -> Error(reason)
      Failed, None -> Error("The text demo failed.")
      _, _ -> Ok(#(current, next))
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
      selections: changed(model.selections, before.selections, next.selections),
      compositions: changed(
        model.compositions,
        before.compositions,
        next.compositions,
      ),
      committed_values: changed(
        model.committed_values,
        before.committed_values,
        next.committed_values,
      ),
      anchors: changed(model.anchors, before.anchors, next.anchors),
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
    SelectionChanged(replica, selection_start, selection_end) -> #(
      set_selection(model, replica, selection_start, selection_end),
      effect.none(),
    )
    SetPace(value) -> #(
      Model(..model, pace_quarters: pace(value, model.pace_quarters)),
      effect.none(),
    )
    SetJitter(value) -> #(Model(..model, jitter: value), effect.none())
    Reset ->
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
    Insert(replica, index, inserted) ->
      mutate(
        model,
        replica,
        fn(text) { watershed.text_insert(text, index, inserted) },
        "insert",
      )
    ReplaceValue(replica, next_value) ->
      replace_value(model, replica, next_value)
    InputChanged(replica, next_value, selection_start, selection_end) ->
      input_changed(model, replica, next_value, selection_start, selection_end)
    CompositionStarted(replica, value, selection_start, selection_end) ->
      composition_started(model, replica, value, selection_start, selection_end)
    CompositionEnded(replica, value, selection_start, selection_end) ->
      composition_ended(model, replica, value, selection_start, selection_end)
    PinAnchor(replica) -> pin_anchor(model, replica)
    ClearAnchor(replica) -> #(
      Model(
        ..model,
        anchors: list.filter(model.anchors, fn(anchor) {
          anchor.replica != replica
        }),
      ),
      effect.none(),
    )
    RaceInserts -> race_inserts(model)
    RaceOverlap -> race_overlap(model)
    Settle -> settle(model)
    ElementChanged(replica) -> record_external_edit(model, replica)
    Deliver(_) -> deliver(model)
  }
}

fn replace_value(
  model: Model,
  replica: Replica,
  next_value: String,
) -> #(Model, Effect(Msg)) {
  case client_from_model(model, replica) {
    Error(reason) -> fail(model, reason)
    Ok(client) ->
      apply_edit(
        model,
        replica,
        grapheme_diff.diff(watershed.text_value(client.text), next_value),
      )
  }
}

fn input_changed(
  model: Model,
  replica: Replica,
  next_value: String,
  selection_start: Int,
  selection_end: Int,
) -> #(Model, Effect(Msg)) {
  case composition(model, replica), committed_value(model, replica) {
    Some(_), _ -> #(model, effect.none())
    None, Some(committed) if committed == next_value -> #(
      set_selection(
        Model(
          ..model,
          committed_values: remove_key(model.committed_values, replica),
        ),
        replica,
        selection_start,
        selection_end,
      ),
      effect.none(),
    )
    None, _ -> {
      let model =
        Model(
          ..model,
          committed_values: remove_key(model.committed_values, replica),
        )
      let #(model, effect) = replace_value(model, replica, next_value)
      #(set_selection(model, replica, selection_start, selection_end), effect)
    }
  }
}

fn composition_started(
  model: Model,
  replica: Replica,
  frozen: String,
  selection_start: Int,
  selection_end: Int,
) -> #(Model, Effect(Msg)) {
  case client_from_model(model, replica) {
    Error(reason) -> fail(model, reason)
    Ok(client) -> {
      let length = watershed.text_length(client.text)
      let head = reported(frozen, selection_start, length)
      let tail = reported(frozen, selection_end, length)
      let region = #(int.min(head, tail), int.max(head, tail))
      #(
        Model(
          ..model,
          compositions: [
            Composition(
              replica:,
              frozen:,
              region:,
              span: anchors(client.text, region.0, region.1),
            ),
            ..remove_composition(model.compositions, replica)
          ],
          committed_values: remove_key(model.committed_values, replica),
        ),
        effect.none(),
      )
    }
  }
}

fn composition_ended(
  model: Model,
  replica: Replica,
  next_value: String,
  selection_start: Int,
  selection_end: Int,
) -> #(Model, Effect(Msg)) {
  case composition(model, replica), client_from_model(model, replica) {
    None, _ ->
      input_changed(model, replica, next_value, selection_start, selection_end)
    _, Error(reason) -> fail(model, reason)
    Some(session), Ok(client) -> {
      let #(start, end) = composition_site(client.text, session)
      let edit = composition_edit(session, next_value, start, end)
      let model =
        Model(
          ..model,
          compositions: remove_composition(model.compositions, replica),
          committed_values: [
            #(replica, next_value),
            ..remove_key(model.committed_values, replica)
          ],
        )
      let #(model, effect) = apply_edit(model, replica, edit)
      let shift = start - session.region.0
      let length = next_value |> string.to_graphemes |> list.length
      #(
        set_grapheme_selection(
          model,
          replica,
          reported(next_value, selection_start, length) + shift,
          reported(next_value, selection_end, length) + shift,
        ),
        effect,
      )
    }
  }
}

fn apply_edit(
  model: Model,
  replica: Replica,
  edit: grapheme_diff.Edit,
) -> #(Model, Effect(Msg)) {
  case edit {
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
        fn(text) { watershed.text_replace_range(text, start, end, inserted) },
        "replace",
      )
  }
}

fn set_selection(
  model: Model,
  replica: Replica,
  selection_start: Int,
  selection_end: Int,
) -> Model {
  let text = rendered_value(model, replica)
  let length = text |> string.to_graphemes |> list.length
  let start = reported(text, selection_start, length)
  let end = reported(text, selection_end, length)
  set_grapheme_selection(model, replica, start, end)
}

fn set_grapheme_selection(
  model: Model,
  replica: Replica,
  start: Int,
  end: Int,
) -> Model {
  Model(..model, selections: [
    #(replica, #(start, end)),
    ..remove_key(model.selections, replica)
  ])
}

fn pin_anchor(model: Model, replica: Replica) -> #(Model, Effect(Msg)) {
  case
    client_from_model(model, replica),
    list.key_find(model.selections, replica)
  {
    Error(reason), _ -> fail(model, reason)
    _, Error(_) -> #(model, effect.none())
    Ok(client), Ok(selection) ->
      case
        watershed.text_anchor_at(client.text, selection.0, watershed.bias_after)
      {
        Error(reason) -> fail(model, reason)
        Ok(anchor) -> #(
          Model(..model, anchors: [
            PinnedAnchor(replica, selection.0, anchor),
            ..list.filter(model.anchors, fn(item) { item.replica != replica })
          ]),
          effect.none(),
        )
      }
  }
}

fn race_inserts(model: Model) -> #(Model, Effect(Msg)) {
  case
    find_grapheme(value(model, ClientB), "weir"),
    find_grapheme(value(model, ClientC), "weir")
  {
    Ok(at_b), Ok(at_c) -> {
      let model = transition(model, Insert(ClientB, at_b, "still "))
      #(transition(model, Insert(ClientC, at_c, "calm ")), effect.none())
    }
    _, _ ->
      recoverable_error(
        model,
        "The crowd insert target is not available. Reset to restore it.",
      )
  }
}

fn race_overlap(model: Model) -> #(Model, Effect(Msg)) {
  case
    find_grapheme(value(model, ClientB), "weir"),
    find_grapheme(value(model, ClientC), "weir")
  {
    Ok(at_b), Ok(at_c) -> {
      let #(model, _) =
        mutate(
          model,
          ClientB,
          fn(text) {
            watershed.text_replace_range(text, at_b, at_b + 4, "levee")
          },
          "replace",
        )
      mutate(
        model,
        ClientC,
        fn(text) { watershed.text_delete_range(text, at_c + 1, at_c + 3) },
        "delete",
      )
    }
    _, _ ->
      recoverable_error(
        model,
        "The overlapping edit target is not available. Reset to restore it.",
      )
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
            Model(..model, error: None),
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
                  log: [
                    LogEntry(
                      delivery.sequence_number,
                      author,
                      pending_label(
                        model.pending,
                        next.channel,
                        delivery.sequence_number,
                      ),
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

fn pending_label(
  pending: List(Pending),
  channel: Channel,
  sequence_number: Int,
) -> String {
  pending
  |> list.find(fn(item) {
    item.channel == channel && item.sequence_number == sequence_number
  })
  |> result.map(fn(item) { item.label })
  |> result.unwrap("edit")
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

pub fn rendered_value(model: Model, replica: Replica) -> String {
  case composition(model, replica) {
    Some(session) -> session.frozen
    None -> value(model, replica)
  }
}

pub fn is_composing(model: Model, replica: Replica) -> Bool {
  composition(model, replica) != None
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

pub fn anchor_position(model: Model, replica: Replica) -> Option(#(Int, Int)) {
  case
    list.find(model.anchors, fn(anchor) { anchor.replica == replica }),
    client_from_model(model, replica)
  {
    Ok(anchor), Ok(client) ->
      watershed.text_resolve_anchor(client.text, anchor.anchor)
      |> result.map(fn(index) { #(anchor.pinned_at, index) })
      |> option_from_result
    _, _ -> None
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

fn composition(model: Model, replica: Replica) -> Option(Composition) {
  model.compositions
  |> list.find(fn(session) { session.replica == replica })
  |> option_from_result
}

fn remove_composition(
  compositions: List(Composition),
  replica: Replica,
) -> List(Composition) {
  list.filter(compositions, fn(session) { session.replica != replica })
}

fn committed_value(model: Model, replica: Replica) -> Option(String) {
  model.committed_values |> list.key_find(replica) |> option_from_result
}

fn remove_key(values: List(#(a, b)), key: a) -> List(#(a, b)) {
  list.filter(values, fn(item) { item.0 != key })
}

fn reported(text: String, offset: Int, length: Int) -> Int {
  int.clamp(
    grapheme_offset.from_utf16(text, int.max(offset, 0)),
    min: 0,
    max: length,
  )
}

fn anchors(
  text: watershed.SharedText,
  start: Int,
  end: Int,
) -> Result(#(watershed.TextAnchor, watershed.TextAnchor), Nil) {
  let head_bias = case start == end {
    True -> watershed.bias_after
    False -> watershed.bias_before
  }
  case
    watershed.text_anchor_at(text, start, head_bias),
    watershed.text_anchor_at(text, end, watershed.bias_after)
  {
    Ok(head), Ok(tail) -> Ok(#(head, tail))
    _, _ -> Error(Nil)
  }
}

fn composition_site(
  text: watershed.SharedText,
  composition: Composition,
) -> #(Int, Int) {
  let width = composition.region.1 - composition.region.0
  case composition.span {
    Error(Nil) -> composition.region
    Ok(#(head, tail)) ->
      case
        watershed.text_resolve_anchor(text, head),
        watershed.text_resolve_anchor(text, tail)
      {
        Ok(start), Ok(end) -> #(start, int.max(start, end))
        Ok(start), Error(_) -> #(start, start + width)
        Error(_), Ok(end) -> #(int.max(0, end - width), end)
        Error(_), Error(_) -> composition.region
      }
  }
}

fn composition_edit(
  composition: Composition,
  value: String,
  start: Int,
  end: Int,
) -> grapheme_diff.Edit {
  case value == composition.frozen {
    True -> grapheme_diff.NoChange
    False ->
      case
        grapheme_diff.replacement(
          old: composition.frozen,
          new: value,
          region: composition.region,
        )
      {
        Ok(composed) -> grapheme_diff.splice(start:, end:, value: composed)
        Error(Nil) ->
          grapheme_diff.diff(old: composition.frozen, new: value)
          |> grapheme_diff.shift(by: start - composition.region.0)
      }
  }
}

fn find_grapheme(text: String, target: String) -> Result(Int, Nil) {
  case string.contains(text, target), string.split(text, target) {
    True, [prefix, ..] -> Ok(prefix |> string.to_graphemes |> list.length)
    _, _ -> Error(Nil)
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

fn recoverable_error(model: Model, reason: String) -> #(Model, Effect(Msg)) {
  #(Model(..model, error: Some(reason)), effect.none())
}

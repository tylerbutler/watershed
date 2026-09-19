import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/json_ot.{
  type JsonValue, type Operation, Index, Key, NInt, VArray, VNumber, VObject,
  VString,
}
import watershed/sluice_js
import watershed_lustre
import watershed_site/demo/flow
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

pub type Snapshot {
  Snapshot(
    replica: Replica,
    value: JsonValue,
    crew: List(String),
    stage: Int,
    trend: String,
    site: String,
  )
}

pub type Pending {
  Pending(sequence_number: Int, replica: Replica, marker: String, label: String)
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
    flows: List(flow.Flow),
    log: List(LogEntry),
    generation: Int,
    pace_quarters: Int,
    jitter: Bool,
    delivery_active: Bool,
    delivery_armed: Bool,
    converged: Bool,
    latest_sequence: Int,
    error: Option(String),
    name_cursors: List(Int),
    site_cursors: List(Int),
    trend_cursors: List(Int),
    random_seed: Int,
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
  Submit(Replica, Operation, marker: String, label: String)
  StepStage(Replica, Int)
  CycleTrend(Replica)
  CycleSite(Replica)
  AddCrew(Replica)
  DeleteCrew(Replica, Int)
  MoveCrew(Replica, Int)
  RaceInserts
  Deliver(generation: Int)
  ClearFlow(generation: Int, id: Int)
  SetPace(String)
  SetJitter(Bool)
  Reset
  RuntimeFailed(String)
}

pub opaque type Rig {
  Rig(sluice: sluice_js.Sluice, clients: List(Client))
}

type Client {
  Client(
    replica: Replica,
    client_id: String,
    document: watershed.Document(Nil),
    json_ot: watershed.JsonOt,
  )
}

type Mutation {
  Mutation(
    snapshots: List(Snapshot),
    pending: List(Pending),
    flows: List(flow.Flow),
  )
}

type Delivery {
  Delivery(
    snapshots: List(Snapshot),
    sequence_number: Int,
    author: Replica,
    more: Bool,
  )
}

const initial_stage = 24

const initial_site = "Mill Race"

const initial_trend = "steady"

pub fn static_model() -> Model {
  Model(
    Static,
    None,
    initial_snapshots(),
    [],
    [],
    [],
    0,
    4,
    False,
    False,
    False,
    True,
    0,
    None,
    [0, 1, 2],
    [0, 0, 0],
    [0, 0, 0],
    41,
    [],
    False,
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
      | ClearFlow(generation, _)
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
    Started(_, Error(reason)) | RuntimeFailed(reason) -> fail(model, reason)
    Deferred(_, Error(reason)) -> finish_deferred_error(model, reason)
    Deferred(_, Ok(pair)) -> finish_deferred(model, pair.0, pair.1)
    SetPace(_) | SetJitter(_) -> update_now(model, message)
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
      converged: False,
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
    !next.delivery_armed
    && { next.delivery_active || !list.is_empty(next.pending) }
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
  let old_ids = list.map(model.flows, fn(item) { item.id })
  let clears =
    next.flows
    |> list.filter(fn(item) { !list.contains(old_ids, item.id) })
    |> list.map(fn(item) {
      watershed_lustre.after(
        timing.playback_ms(next.pace_quarters, 5000),
        ClearFlow(next.generation, item.id),
      )
    })
  let #(next, work) = start_work(next)
  #(next, effect.batch([delivery, work, ..clears]))
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
      | ClearFlow(generation, _)
      if generation != model.generation
    -> #(model, effect.none())
    NoOp | Start | Defer(_) -> #(model, effect.none())
    Started(_, Ok(ready)) -> #(ready, effect.none())
    Started(_, Error(reason)) | RuntimeFailed(reason) -> fail(model, reason)
    Deferred(_, Ok(pair)) -> #(pair.1, effect.none())
    Deferred(_, Error(reason)) -> fail(model, reason)
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
    Submit(replica, operation, marker, label) ->
      submit_many(model, [#(replica, operation, marker, label)])
    StepStage(replica, amount) ->
      submit_many(model, [
        #(
          replica,
          [
            json_ot.number_add([Key("gauge"), Key("stage")], NInt(amount)),
          ],
          "field:gauge.stage",
          "add .gauge.stage "
            <> case amount > 0 {
            True -> "+" <> int.to_string(amount)
            False -> int.to_string(amount)
          },
        ),
      ])
    CycleTrend(replica) -> {
      let current = snapshot(model, replica)
      let cursor = cursor(model.trend_cursors, replica)
      let next =
        next_distinct(
          ["rising", "cresting", "falling", "steady"],
          cursor,
          current.trend,
        )
      submit_many(
        Model(
          ..model,
          trend_cursors: set_cursor(model.trend_cursors, replica, next.1),
        ),
        [
          #(
            replica,
            [
              json_ot.object_replace(
                [Key("gauge"), Key("trend")],
                VString(current.trend),
                VString(next.0),
              ),
            ],
            "field:gauge.trend",
            "set .gauge.trend \"" <> next.0 <> "\"",
          ),
        ],
      )
    }
    CycleSite(replica) -> {
      let current = snapshot(model, replica)
      let cursor = cursor(model.site_cursors, replica)
      let next =
        next_distinct(
          ["Mill Race", "Kettle Run", "Low Ford", "Spillway Gate"],
          cursor,
          current.site,
        )
      submit_many(
        Model(
          ..model,
          site_cursors: set_cursor(model.site_cursors, replica, next.1),
        ),
        [
          #(
            replica,
            [
              json_ot.object_replace(
                [Key("site")],
                VString(current.site),
                VString(next.0),
              ),
            ],
            "field:site",
            "set .site \"" <> next.0 <> "\"",
          ),
        ],
      )
    }
    AddCrew(replica) -> {
      let #(name, cursors) = next_name(model, replica, None)
      submit_many(Model(..model, name_cursors: cursors), [
        crew_insert(replica, name),
      ])
    }
    DeleteCrew(replica, index) -> {
      let current = snapshot(model, replica)
      case at(current.crew, index) {
        Error(Nil) -> fail(model, "Invalid crew index.")
        Ok(name) ->
          submit_many(model, [
            #(
              replica,
              [
                json_ot.list_delete([Key("crew"), Index(index)], VString(name)),
              ],
              "field:crew",
              "delete .crew[" <> int.to_string(index) <> "] \"" <> name <> "\"",
            ),
          ])
      }
    }
    MoveCrew(replica, index) ->
      case index > 0 {
        False -> #(model, effect.none())
        True ->
          submit_many(model, [
            #(
              replica,
              [json_ot.list_move([Key("crew"), Index(index)], index - 1)],
              "field:crew",
              "move .crew["
                <> int.to_string(index)
                <> "] → "
                <> int.to_string(index - 1),
            ),
          ])
      }
    RaceInserts -> {
      let #(first, cursors) = next_name(model, ClientA, None)
      let #(second, cursors) =
        next_name(Model(..model, name_cursors: cursors), ClientB, Some(first))
      submit_many(Model(..model, name_cursors: cursors), [
        crew_insert(ClientA, first),
        crew_insert(ClientB, second),
      ])
    }
    Deliver(_) ->
      case model.rig {
        None -> fail(model, "The JSON OT rig is not available.")
        Some(rig) ->
          case deliver_group(rig) {
            Error(reason) -> fail(model, reason)
            Ok(delivery) -> {
              let pending =
                list.filter(model.pending, fn(item) {
                  item.sequence_number > delivery.sequence_number
                })
              let flows =
                replicas()
                |> list.index_map(fn(replica, index) {
                  flow.Flow(
                    delivery.sequence_number * 4 + index,
                    flow.Sequencer,
                    flow.Replica(replica_id(replica)),
                    "SN " <> int.to_string(delivery.sequence_number),
                  )
                })
              #(
                Model(
                  ..model,
                  phase: case delivery.more {
                    True -> Delivering
                    False -> Ready
                  },
                  snapshots: delivery.snapshots,
                  pending:,
                  flows: list.append(model.flows, flows),
                  log: [
                    LogEntry(
                      delivery.sequence_number,
                      delivery.author,
                      pending_label(model.pending, delivery.sequence_number),
                    ),
                    ..model.log
                  ],
                  latest_sequence: delivery.sequence_number,
                  delivery_active: delivery.more,
                  delivery_armed: False,
                  converged: !delivery.more
                    && list.is_empty(pending)
                    && snapshots_equal(delivery.snapshots),
                ),
                effect.none(),
              )
            }
          }
      }
    ClearFlow(_, id) -> #(
      Model(..model, flows: flow.remove(model.flows, id)),
      effect.none(),
    )
  }
}

fn submit_many(
  model: Model,
  operations: List(#(Replica, Operation, String, String)),
) -> #(Model, Effect(Msg)) {
  case model.rig, model.phase {
    Some(rig), Ready | Some(rig), Delivering ->
      case mutate(rig, operations) {
        Error(reason) -> fail(model, reason)
        Ok(mutation) -> #(
          Model(
            ..model,
            phase: Delivering,
            snapshots: mutation.snapshots,
            pending: list.append(model.pending, mutation.pending),
            flows: list.append(model.flows, mutation.flows),
            delivery_active: True,
            converged: False,
          ),
          effect.none(),
        )
      }
    _, _ -> #(model, effect.none())
  }
}

fn mutate(
  rig: Rig,
  operations: List(#(Replica, Operation, String, String)),
) -> Result(Mutation, String) {
  use pending <- result.try(
    list.try_map(operations, fn(item) {
      use client <- result.try(client(rig, item.0))
      watershed.submit_json_ot(client.json_ot, item.1)
      Ok(Pending(sluice_js.sequence_number(rig.sluice), item.0, item.2, item.3))
    }),
  )
  use snapshots <- result.try(project_all(rig))
  Ok(Mutation(
    snapshots,
    pending,
    list.map(pending, fn(item) {
      flow.Flow(
        -item.sequence_number,
        flow.Replica(replica_id(item.replica)),
        flow.Sequencer,
        item.label,
      )
    }),
  ))
}

fn deliver_group(rig: Rig) -> Result(Delivery, String) {
  use next <- result.try(next_operation(rig))
  use author <- result.try(replica_by_client_id(rig, next.author))
  use _ <- result.try(drain(rig, next.sequence_number))
  use snapshots <- result.try(project_all(rig))
  Ok(Delivery(
    snapshots,
    next.sequence_number,
    author,
    sluice_js.pending(rig.sluice),
  ))
}

fn drain(rig: Rig, sequence_number: Int) -> Result(Nil, String) {
  case sluice_js.peek_info(rig.sluice) {
    Ok(next) if next.sequence_number == sequence_number -> {
      use _ <- result.try(
        sluice_js.step_info(rig.sluice)
        |> result.replace_error("Cannot deliver the JSON OT operation."),
      )
      drain(rig, sequence_number)
    }
    Ok(next) if next.sequence_number == 0 ->
      Error("Unexpected delivery: " <> next.event)
    Ok(_) | Error(Nil) -> Ok(Nil)
  }
}

fn next_operation(rig: Rig) -> Result(sluice_js.Delivery, String) {
  use next <- result.try(
    sluice_js.peek_info(rig.sluice)
    |> result.replace_error("No JSON OT operation is queued."),
  )
  case next.sequence_number > 0 && next.event == "op" {
    True -> Ok(next)
    False -> Error("Unexpected delivery: " <> next.event)
  }
}

fn start_model() -> Result(Model, String) {
  use rig <- result.try(start_rig())
  use snapshots <- result.try(project_all(rig))
  Ok(Model(..static_model(), phase: Ready, rig: Some(rig), snapshots:))
}

fn start_rig() -> Result(Rig, String) {
  let sluice = sluice_js.start(tenant: "json-ot-demo", document: "json-ot-demo")
  let documents =
    replicas()
    |> list.map(fn(replica) {
      #(replica, sluice_js.connect(sluice, "user-" <> replica_id(replica)))
    })
  sluice_js.settle(sluice)
  let assert [#(ClientA, alpha), ..] = documents
  use json_ot <- result.try(watershed.create_json_ot(alpha))
  watershed.submit_json_ot(json_ot, seed_operation())
  watershed.set(
    watershed.root(alpha),
    "doc",
    watershed.json_ot_handle_of(json_ot),
  )
  sluice_js.settle(sluice)
  use clients <- result.try(
    list.try_map(documents, fn(item) {
      use client_id <- result.try(
        sluice_js.client_id(sluice, item.1)
        |> result.replace_error("Missing client ID."),
      )
      case item.0 {
        ClientA -> Ok(Client(item.0, client_id, item.1, json_ot))
        ClientB | ClientC -> {
          use value <- result.try(
            watershed.get(watershed.root(item.1), "doc")
            |> result.replace_error("Missing JSON OT handle."),
          )
          use resolved <- result.try(watershed.resolve_json_ot(item.1, value))
          Ok(Client(item.0, client_id, item.1, resolved))
        }
      }
    }),
  )
  Ok(Rig(sluice, clients))
}

fn seed_operation() -> Operation {
  [
    json_ot.object_insert([Key("crew")], string_array(["Ada", "Ben"])),
    json_ot.object_insert(
      [Key("gauge")],
      gauge_value(initial_stage, initial_trend),
    ),
    json_ot.object_insert([Key("site")], VString(initial_site)),
  ]
}

pub fn string_array(values: List(String)) -> JsonValue {
  VArray(list.map(values, VString))
}

pub fn gauge_value(stage: Int, trend: String) -> JsonValue {
  VObject([
    #("stage", VNumber(NInt(stage))),
    #("trend", VString(trend)),
  ])
}

fn project_all(rig: Rig) -> Result(List(Snapshot), String) {
  list.try_map(rig.clients, fn(client) {
    use value <- result.try(
      watershed.json_ot_view(client.json_ot)
      |> result.replace_error(
        replica_label(client.replica) <> ": Invalid JSON OT view.",
      ),
    )
    use decoded <- result.try(decode_snapshot(client.replica, value))
    Ok(decoded)
  })
}

fn decode_snapshot(
  replica: Replica,
  value: JsonValue,
) -> Result(Snapshot, String) {
  use members <- result.try(object_members(value, "document"))
  use crew_value <- result.try(member(members, "crew"))
  use crew_values <- result.try(array_values(crew_value, "crew"))
  use crew <- result.try(
    list.try_map(crew_values, fn(value) { string_value(value, "crew item") }),
  )
  use gauge <- result.try(member(members, "gauge"))
  use gauge_members <- result.try(object_members(gauge, "gauge"))
  use stage_value <- result.try(member(gauge_members, "stage"))
  use stage <- result.try(int_value(stage_value, "gauge.stage"))
  use trend_value <- result.try(member(gauge_members, "trend"))
  use trend <- result.try(string_value(trend_value, "gauge.trend"))
  use site_value <- result.try(member(members, "site"))
  use site <- result.try(string_value(site_value, "site"))
  Ok(Snapshot(replica, value, crew, stage, trend, site))
}

fn member(
  members: List(#(String, JsonValue)),
  key: String,
) -> Result(JsonValue, String) {
  list.key_find(members, key)
  |> result.replace_error("Missing JSON OT field: " <> key <> ".")
}

fn object_members(
  value: JsonValue,
  field: String,
) -> Result(List(#(String, JsonValue)), String) {
  case value {
    VObject(members) -> Ok(members)
    _ -> Error("Invalid JSON OT object: " <> field <> ".")
  }
}

fn array_values(
  value: JsonValue,
  field: String,
) -> Result(List(JsonValue), String) {
  case value {
    VArray(values) -> Ok(values)
    _ -> Error("Invalid JSON OT array: " <> field <> ".")
  }
}

fn string_value(value: JsonValue, field: String) -> Result(String, String) {
  case value {
    VString(text) -> Ok(text)
    _ -> Error("Invalid JSON OT string: " <> field <> ".")
  }
}

fn int_value(value: JsonValue, field: String) -> Result(Int, String) {
  case value {
    VNumber(NInt(number)) -> Ok(number)
    _ -> Error("Invalid JSON OT integer: " <> field <> ".")
  }
}

fn initial_snapshots() -> List(Snapshot) {
  let value =
    VObject([
      #("crew", string_array(["Ada", "Ben"])),
      #("gauge", gauge_value(initial_stage, initial_trend)),
      #("site", VString(initial_site)),
    ])
  replicas()
  |> list.map(fn(replica) {
    Snapshot(
      replica,
      value,
      ["Ada", "Ben"],
      initial_stage,
      initial_trend,
      initial_site,
    )
  })
}

pub fn documents(model: Model) -> List(JsonValue) {
  list.map(model.snapshots, fn(item) { item.value })
}

pub fn crew(model: Model, replica: Replica) -> List(String) {
  snapshot(model, replica).crew
}

pub fn snapshot(model: Model, replica: Replica) -> Snapshot {
  model.snapshots
  |> list.find(fn(item) { item.replica == replica })
  |> result.unwrap(Snapshot(replica, VObject([]), [], 0, "", ""))
}

pub fn pending_count(model: Model, replica: Replica) -> Int {
  model.pending
  |> list.filter(fn(item) { item.replica == replica })
  |> list.length
}

fn snapshots_equal(snapshots: List(Snapshot)) -> Bool {
  case snapshots {
    [] -> True
    [first, ..rest] -> list.all(rest, fn(item) { item.value == first.value })
  }
}

pub fn is_converged(model: Model) -> Bool {
  model.error == None
  && list.is_empty(model.pending)
  && list.is_empty(model.deferred_work)
  && !model.work_running
  && snapshots_equal(model.snapshots)
}

fn pending_label(pending: List(Pending), sequence_number: Int) -> String {
  pending
  |> list.find(fn(item) { item.sequence_number == sequence_number })
  |> result.map(fn(item) { item.label })
  |> result.unwrap("SN " <> int.to_string(sequence_number))
}

fn crew_insert(
  replica: Replica,
  name: String,
) -> #(Replica, Operation, String, String) {
  #(
    replica,
    [json_ot.list_insert([Key("crew"), Index(0)], VString(name))],
    "field:crew",
    "insert .crew[0] \"" <> name <> "\"",
  )
}

fn next_name(
  model: Model,
  replica: Replica,
  excluded: Option(String),
) -> #(String, List(Int)) {
  let names = ["Cy", "Dot", "Eli", "Fen", "Gus", "Hana", "Ime", "Jo"]
  let current = cursor(model.name_cursors, replica)
  let name = next_allowed(names, current, excluded, list.length(names))
  #(name, set_cursor(model.name_cursors, replica, current + 3))
}

fn next_distinct(
  values: List(String),
  cursor: Int,
  current: String,
) -> #(String, Int) {
  let next = next_allowed(values, cursor, Some(current), list.length(values))
  #(next, cursor + 1)
}

fn cursor(cursors: List(Int), replica: Replica) -> Int {
  cursors |> at(replica_index(replica)) |> result.unwrap(0)
}

fn set_cursor(cursors: List(Int), replica: Replica, value: Int) -> List(Int) {
  list.index_map(cursors, fn(current, index) {
    case index == replica_index(replica) {
      True -> value
      False -> current
    }
  })
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
    Model(
      ..model,
      phase: Failed,
      error: Some(reason),
      delivery_active: False,
      delivery_armed: False,
      converged: False,
    ),
    effect.none(),
  )
}

fn client(rig: Rig, replica: Replica) -> Result(Client, String) {
  rig.clients
  |> list.find(fn(item) { item.replica == replica })
  |> result.replace_error(replica_label(replica) <> ": Missing replica.")
}

fn replica_by_client_id(rig: Rig, id: String) -> Result(Replica, String) {
  rig.clients
  |> list.find(fn(item) { item.client_id == id })
  |> result.map(fn(item) { item.replica })
  |> result.replace_error("Unknown replica: " <> id)
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

fn replica_index(replica: Replica) -> Int {
  case replica {
    ClientA -> 0
    ClientB -> 1
    ClientC -> 2
  }
}

fn next_allowed(
  values: List(String),
  index: Int,
  excluded: Option(String),
  remaining: Int,
) -> String {
  case
    remaining <= 0,
    at(values, positive_remainder(index, list.length(values)))
  {
    True, _ -> ""
    False, Ok(value) ->
      case Some(value) == excluded {
        True -> next_allowed(values, index + 1, excluded, remaining - 1)
        False -> value
      }
    False, Error(Nil) -> ""
  }
}

fn positive_remainder(value: Int, divisor: Int) -> Int {
  case divisor <= 0 {
    True -> 0
    False -> {
      let remainder = value % divisor
      case remainder < 0 {
        True -> remainder + divisor
        False -> remainder
      }
    }
  }
}

fn at(values: List(a), index: Int) -> Result(a, Nil) {
  case values, index {
    [], _ -> Error(Nil)
    [value, ..], 0 -> Ok(value)
    [_, ..rest], index if index > 0 -> at(rest, index - 1)
    [_, ..], _ -> Error(Nil)
  }
}

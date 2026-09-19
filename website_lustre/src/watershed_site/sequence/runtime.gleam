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

pub type Route {
  Route(replica: Replica, stations: List(String), selected: Option(String))
}

pub type Pending {
  Pending(sequence_number: Int, replica: Replica, marker: String, label: String)
}

pub type LogEntry {
  LogEntry(sequence_number: Int, author: Replica, label: String)
}

pub type AnnotationTone {
  LocalNote
  SequencedNote
}

pub type AnnotationTarget {
  StationTarget(replica: Replica, name: String)
  LogTarget(sequence_number: Int)
}

pub type Annotation {
  Annotation(id: Int, target: AnnotationTarget, tone: AnnotationTone)
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    routes: List(Route),
    pending: List(Pending),
    flows: List(flow.Flow),
    log: List(LogEntry),
    generation: Int,
    pace_quarters: Int,
    jitter: Bool,
    field_notes: Bool,
    delivery_active: Bool,
    delivery_armed: Bool,
    converged: Bool,
    latest_sequence: Int,
    error: Option(String),
    name_cursors: List(Int),
    random_seed: Int,
    annotations: List(Annotation),
    next_annotation_id: Int,
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
  Select(Replica, String)
  Insert(Replica, Int)
  Move(Replica, from: Int, to: Int)
  Rename(Replica, Int)
  Delete(Replica, Int)
  RaceMove
  RaceInsert
  Deliver(generation: Int)
  ClearFlow(generation: Int, id: Int)
  ClearAnnotation(generation: Int, id: Int)
  SetPace(String)
  SetJitter(Bool)
  SetFieldNotes(Bool)
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
    sequence: watershed.SharedSequence,
  )
}

type Mutation {
  Mutation(routes: List(Route), pending: List(Pending), flows: List(flow.Flow))
}

type Delivery {
  Delivery(
    routes: List(Route),
    sequence_number: Int,
    author: Replica,
    more: Bool,
  )
}

const initial_route = [
  "put-in",
  "mill-race weir",
  "kettle-run rapids",
  "low-ford portage",
  "take-out",
]

pub fn static_model() -> Model {
  Model(
    Static,
    None,
    list.map(replicas(), fn(replica) { Route(replica, initial_route, None) }),
    [],
    [],
    [],
    0,
    4,
    False,
    False,
    False,
    False,
    True,
    0,
    None,
    [0, 1, 2],
    73,
    [],
    1,
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
      | ClearAnnotation(generation, _)
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
        field_notes: model.field_notes,
      ),
      effect.none(),
    )
    Started(_, Error(reason)) | RuntimeFailed(reason) -> fail(model, reason)
    Deferred(_, Error(reason)) -> finish_deferred_error(model, reason)
    Deferred(_, Ok(pair)) -> finish_deferred(model, pair.0, pair.1)
    Select(_, _) | SetPace(_) | SetJitter(_) | SetFieldNotes(_) ->
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
    case next.phase, next.error {
      Failed, Some(reason) -> Error(reason)
      _, _ -> Ok(#(current, next))
    }
  }
  let queued =
    Model(
      ..model,
      phase: case command {
        Reset -> Starting
        _ -> model.phase
      },
      converged: case command {
        Reset -> False
        _ -> model.converged
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
      pace_quarters: changed(
        model.pace_quarters,
        before.pace_quarters,
        next.pace_quarters,
      ),
      jitter: changed(model.jitter, before.jitter, next.jitter),
      field_notes: changed(
        model.field_notes,
        before.field_notes,
        next.field_notes,
      ),
      routes: reconcile_selection(model.routes, before.routes, next.routes),
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
  let old_annotation_ids =
    list.map(model.annotations, fn(annotation) { annotation.id })
  let annotation_clears =
    next.annotations
    |> list.filter(fn(annotation) {
      !list.contains(old_annotation_ids, annotation.id)
    })
    |> list.map(fn(annotation) {
      watershed_lustre.after(
        timing.playback_ms(next.pace_quarters, annotation_ttl(annotation)),
        ClearAnnotation(next.generation, annotation.id),
      )
    })
  let #(next, work) = start_work(next)
  #(
    next,
    effect.batch([delivery, work, ..list.append(clears, annotation_clears)]),
  )
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
      | ClearAnnotation(generation, _)
      if generation != model.generation
    -> #(model, effect.none())
    NoOp | Start | Defer(_) -> #(model, effect.none())
    Started(_, Ok(ready)) -> #(ready, effect.none())
    Started(_, Error(reason)) | RuntimeFailed(reason) -> fail(model, reason)
    Deferred(_, Ok(pair)) -> #(pair.1, effect.none())
    Deferred(_, Error(reason)) -> fail(model, reason)
    Select(replica, station) -> {
      let routes =
        list.map(model.routes, fn(route) {
          case route.replica == replica {
            False -> route
            True ->
              Route(..route, selected: case route.selected == Some(station) {
                True -> None
                False -> Some(station)
              })
          }
        })
      #(Model(..model, routes:), effect.none())
    }
    SetPace(value) -> #(
      Model(..model, pace_quarters: pace(value, model.pace_quarters)),
      effect.none(),
    )
    SetJitter(value) -> #(Model(..model, jitter: value), effect.none())
    SetFieldNotes(value) -> #(
      Model(..model, field_notes: value, annotations: case value {
        True -> model.annotations
        False -> []
      }),
      effect.none(),
    )
    Reset ->
      case start_model() {
        Error(reason) -> fail(model, reason)
        Ok(reset) -> #(
          Model(
            ..reset,
            generation: model.generation + 1,
            pace_quarters: model.pace_quarters,
            jitter: model.jitter,
            field_notes: model.field_notes,
          ),
          effect.none(),
        )
      }
    Insert(replica, index) -> {
      let #(name, cursors) = next_name(model, replica)
      mutate_one(
        Model(..model, name_cursors: cursors),
        replica,
        "st:" <> name,
        "insert " <> name <> " @" <> int.to_string(index + 1),
        fn(sequence) {
          watershed.sequence_insert(sequence, index, json.string(name))
        },
      )
    }
    Move(replica, from, to) -> {
      let stations = route(model, replica)
      case at(stations, from) {
        Error(Nil) -> fail(model, "Invalid route index.")
        Ok(name) ->
          mutate_one(
            model,
            replica,
            "st:" <> name,
            "move "
              <> name
              <> " "
              <> int.to_string(from + 1)
              <> "→"
              <> int.to_string(to + 1),
            fn(sequence) { watershed.sequence_move(sequence, from, to) },
          )
      }
    }
    Rename(replica, index) -> {
      let stations = route(model, replica)
      case at(stations, index) {
        Error(Nil) -> fail(model, "Invalid route index.")
        Ok(old_name) -> {
          let #(name, cursors) = next_name(model, replica)
          mutate_one(
            Model(
              ..model,
              routes: select_name(model.routes, replica, old_name, name),
              name_cursors: cursors,
            ),
            replica,
            "st:" <> name,
            "rename " <> old_name <> " → " <> name,
            fn(sequence) {
              watershed.sequence_replace(sequence, index, json.string(name))
            },
          )
        }
      }
    }
    Delete(replica, index) -> {
      let stations = route(model, replica)
      case at(stations, index) {
        Error(Nil) -> fail(model, "Invalid route index.")
        Ok(name) ->
          mutate_one(
            Model(..model, routes: clear_selection(model.routes, replica)),
            replica,
            "",
            "delete " <> name <> " @" <> int.to_string(index + 1),
            fn(sequence) { watershed.sequence_delete(sequence, index) },
          )
      }
    }
    RaceMove ->
      case movable_station(model) {
        Error(reason) -> #(Model(..model, error: Some(reason)), effect.none())
        Ok(#(name, beta_index, gamma_index)) ->
          mutate_many(model, [
            #(
              ClientB,
              "st:" <> name,
              "move " <> name <> " upstream",
              fn(sequence) {
                watershed.sequence_move(sequence, beta_index, beta_index - 1)
              },
            ),
            #(
              ClientC,
              "st:" <> name,
              "move " <> name <> " downstream",
              fn(sequence) {
                watershed.sequence_move(sequence, gamma_index, gamma_index + 1)
              },
            ),
          ])
      }
    RaceInsert -> {
      let beta_index = int.min(2, list.length(route(model, ClientB)))
      let gamma_index = int.min(2, list.length(route(model, ClientC)))
      let #(beta_name, cursors) = next_name(model, ClientB)
      let #(gamma_name, cursors) =
        next_name(Model(..model, name_cursors: cursors), ClientC)
      mutate_many(Model(..model, name_cursors: cursors), [
        #(
          ClientB,
          "st:" <> beta_name,
          "insert " <> beta_name <> " @" <> int.to_string(beta_index + 1),
          fn(sequence) {
            watershed.sequence_insert(
              sequence,
              beta_index,
              json.string(beta_name),
            )
          },
        ),
        #(
          ClientC,
          "st:" <> gamma_name,
          "insert " <> gamma_name <> " @" <> int.to_string(gamma_index + 1),
          fn(sequence) {
            watershed.sequence_insert(
              sequence,
              gamma_index,
              json.string(gamma_name),
            )
          },
        ),
      ])
    }
    Deliver(_) ->
      case model.rig {
        None -> fail(model, "The sequence rig is not available.")
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
              let annotated =
                Model(
                  ..model,
                  phase: case delivery.more {
                    True -> Delivering
                    False -> Ready
                  },
                  routes: preserve_selection(model.routes, delivery.routes),
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
                    && all_routes_equal(delivery.routes),
                )
                |> annotate_routes(
                  model.routes,
                  delivery.routes,
                  replicas(),
                  SequencedNote,
                )
                |> annotate_log(delivery.sequence_number)
              #(annotated, effect.none())
            }
          }
      }
    ClearFlow(_, id) -> #(
      Model(..model, flows: flow.remove(model.flows, id)),
      effect.none(),
    )
    ClearAnnotation(_, id) -> #(
      Model(
        ..model,
        annotations: list.filter(model.annotations, fn(annotation) {
          annotation.id != id
        }),
      ),
      effect.none(),
    )
  }
}

fn mutate_one(
  model: Model,
  replica: Replica,
  marker: String,
  label: String,
  operation: fn(watershed.SharedSequence) -> Result(Nil, String),
) -> #(Model, Effect(Msg)) {
  mutate_many(model, [#(replica, marker, label, operation)])
}

fn mutate_many(
  model: Model,
  operations: List(
    #(
      Replica,
      String,
      String,
      fn(watershed.SharedSequence) -> Result(Nil, String),
    ),
  ),
) -> #(Model, Effect(Msg)) {
  case model.rig, model.phase {
    Some(rig), Ready | Some(rig), Delivering ->
      case mutate(rig, operations) {
        Error(reason) -> fail(model, reason)
        Ok(mutation) -> {
          let next =
            Model(
              ..model,
              phase: Delivering,
              error: None,
              routes: preserve_selection(model.routes, mutation.routes),
              pending: list.append(model.pending, mutation.pending),
              flows: list.append(model.flows, mutation.flows),
              delivery_active: True,
              converged: False,
            )
            |> annotate_routes(
              model.routes,
              mutation.routes,
              operations
                |> list.map(fn(operation) { operation.0 })
                |> list.unique,
              LocalNote,
            )
          #(next, effect.none())
        }
      }
    _, _ -> #(model, effect.none())
  }
}

fn mutate(
  rig: Rig,
  operations: List(
    #(
      Replica,
      String,
      String,
      fn(watershed.SharedSequence) -> Result(Nil, String),
    ),
  ),
) -> Result(Mutation, String) {
  use pending <- result.try(
    list.try_map(operations, fn(item) {
      use client <- result.try(client(rig, item.0))
      use _ <- result.try(item.3(client.sequence))
      Ok(Pending(sluice_js.sequence_number(rig.sluice), item.0, item.1, item.2))
    }),
  )
  use routes <- result.try(project_all(rig))
  Ok(Mutation(
    routes,
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
  use routes <- result.try(project_all(rig))
  Ok(Delivery(
    routes,
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
        |> result.replace_error("Cannot deliver the sequence operation."),
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
    |> result.replace_error("No sequence operation is queued."),
  )
  case next.sequence_number > 0 && next.event == "op" {
    True -> Ok(next)
    False -> Error("Unexpected delivery: " <> next.event)
  }
}

fn start_model() -> Result(Model, String) {
  use rig <- result.try(start_rig())
  use routes <- result.try(project_all(rig))
  Ok(Model(..static_model(), phase: Ready, rig: Some(rig), routes:))
}

fn start_rig() -> Result(Rig, String) {
  let sluice =
    sluice_js.start(tenant: "sequence-demo", document: "sequence-demo")
  let documents =
    replicas()
    |> list.map(fn(replica) {
      #(replica, sluice_js.connect(sluice, "user-" <> replica_id(replica)))
    })
  sluice_js.settle(sluice)
  let assert [#(ClientA, alpha), ..] = documents
  use sequence <- result.try(watershed.create_sequence(alpha))
  watershed.set(
    watershed.root(alpha),
    "route",
    watershed.sequence_handle_of(sequence),
  )
  use _ <- result.try(
    initial_route
    |> list.index_map(fn(name, index) {
      watershed.sequence_insert(sequence, index, json.string(name))
    })
    |> result.all,
  )
  sluice_js.settle(sluice)
  use clients <- result.try(
    list.try_map(documents, fn(item) {
      use client_id <- result.try(
        sluice_js.client_id(sluice, item.1)
        |> result.replace_error("Missing client ID."),
      )
      case item.0 {
        ClientA -> Ok(Client(item.0, client_id, item.1, sequence))
        ClientB | ClientC -> {
          use value <- result.try(
            watershed.get(watershed.root(item.1), "route")
            |> result.replace_error("Missing sequence handle."),
          )
          use resolved <- result.try(watershed.resolve_sequence(item.1, value))
          Ok(Client(item.0, client_id, item.1, resolved))
        }
      }
    }),
  )
  Ok(Rig(sluice, clients))
}

fn project_all(rig: Rig) -> Result(List(Route), String) {
  list.try_map(rig.clients, fn(client) {
    use stations <- result.try(
      watershed.sequence_values(client.sequence)
      |> list.try_map(fn(value) {
        json.parse(json.to_string(value), decode.string)
        |> result.map_error(fn(_) {
          replica_label(client.replica) <> ": Invalid route value."
        })
      }),
    )
    Ok(Route(client.replica, stations, None))
  })
}

pub fn routes(model: Model) -> List(Route) {
  model.routes
}

pub fn route(model: Model, replica: Replica) -> List(String) {
  model.routes
  |> list.find(fn(item) { item.replica == replica })
  |> result.map(fn(item) { item.stations })
  |> result.unwrap([])
}

pub fn all_routes_equal(routes: List(Route)) -> Bool {
  case routes {
    [] -> True
    [first, ..rest] ->
      list.all(rest, fn(item) { item.stations == first.stations })
  }
}

pub fn is_converged(model: Model) -> Bool {
  model.phase != Failed
  && list.is_empty(model.pending)
  && list.is_empty(model.deferred_work)
  && !model.work_running
  && all_routes_equal(model.routes)
}

pub fn pending_count(model: Model, replica: Replica) -> Int {
  model.pending
  |> list.filter(fn(item) { item.replica == replica })
  |> list.length
}

pub fn selected(model: Model, replica: Replica) -> Option(String) {
  model.routes
  |> list.find(fn(item) { item.replica == replica })
  |> result.map(fn(item) { item.selected })
  |> result.unwrap(None)
}

fn preserve_selection(
  current: List(Route),
  projected: List(Route),
) -> List(Route) {
  list.map(projected, fn(route) {
    let selected =
      current
      |> list.find(fn(item) { item.replica == route.replica })
      |> result.map(fn(item) { item.selected })
      |> result.unwrap(None)
    Route(..route, selected: case selected {
      Some(name) ->
        case list.contains(route.stations, name) {
          True -> selected
          False -> None
        }
      _ -> None
    })
  })
}

fn reconcile_selection(
  current: List(Route),
  before: List(Route),
  next: List(Route),
) -> List(Route) {
  list.map(next, fn(route) {
    let current_selection = selection_for(current, route.replica)
    let before_selection = selection_for(before, route.replica)
    let selected = case current_selection == before_selection {
      True -> route.selected
      False -> current_selection
    }
    Route(..route, selected: valid_selection(route.stations, selected))
  })
}

fn selection_for(routes: List(Route), replica: Replica) -> Option(String) {
  routes
  |> list.find(fn(route) { route.replica == replica })
  |> result.map(fn(route) { route.selected })
  |> result.unwrap(None)
}

fn valid_selection(
  stations: List(String),
  selected: Option(String),
) -> Option(String) {
  case selected {
    Some(name) ->
      case list.contains(stations, name) {
        True -> selected
        False -> None
      }
    _ -> None
  }
}

fn select_name(
  routes: List(Route),
  replica: Replica,
  old_name: String,
  new_name: String,
) -> List(Route) {
  list.map(routes, fn(route) {
    case route.replica == replica && route.selected == Some(old_name) {
      True -> Route(..route, selected: Some(new_name))
      False -> route
    }
  })
}

fn clear_selection(routes: List(Route), replica: Replica) -> List(Route) {
  list.map(routes, fn(route) {
    case route.replica == replica {
      True -> Route(..route, selected: None)
      False -> route
    }
  })
}

fn movable_station(model: Model) -> Result(#(String, Int, Int), String) {
  let beta = route(model, ClientB)
  let gamma = route(model, ClientC)
  beta
  |> list.index_map(fn(name, beta_index) { #(name, beta_index) })
  |> list.find(fn(item) {
    let gamma_index = index_of(gamma, item.0)
    item.1 > 0 && gamma_index >= 0 && gamma_index < list.length(gamma) - 1
  })
  |> result.map(fn(item) { #(item.0, item.1, index_of(gamma, item.0)) })
  |> result.replace_error("No waypoint can move in both directions.")
}

fn index_of(values: List(String), target: String) -> Int {
  values
  |> list.index_map(fn(value, index) { #(value, index) })
  |> list.find(fn(item) { item.0 == target })
  |> result.map(fn(item) { item.1 })
  |> result.unwrap(-1)
}

fn next_name(model: Model, replica: Replica) -> #(String, List(Int)) {
  let names = [
    "beaver dam",
    "gravel bar",
    "oxbow",
    "sweeper",
    "boulder garden",
    "eddy pool",
    "cache point",
    "lining chute",
    "high camp",
  ]
  let current = cursor(model.name_cursors, replica)
  let visible = route(model, replica)
  let #(name, next_cursor) =
    next_disjoint_name(names, visible, current, list.length(names))
  #(name, set_cursor(model.name_cursors, replica, next_cursor))
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

fn pending_label(pending: List(Pending), sequence_number: Int) -> String {
  pending
  |> list.find(fn(item) { item.sequence_number == sequence_number })
  |> result.map(fn(item) { item.label })
  |> result.unwrap("SN " <> int.to_string(sequence_number))
}

fn sampled_delay(model: Model) -> #(Model, Int) {
  let #(seed, sample) = timing.next_sample(model.random_seed)
  #(
    Model(..model, random_seed: seed),
    timing.delay_ms(model.pace_quarters, model.jitter, sample),
  )
}

fn annotate_routes(
  model: Model,
  before: List(Route),
  after: List(Route),
  replicas: List(Replica),
  tone: AnnotationTone,
) -> Model {
  case model.field_notes {
    False -> model
    True -> {
      let #(annotations, next_id) =
        list.fold(
          replicas,
          #(model.annotations, model.next_annotation_id),
          fn(state, replica) {
            changed_names(route_in(before, replica), route_in(after, replica))
            |> list.fold(state, fn(state, name) {
              #(
                [
                  Annotation(state.1, StationTarget(replica, name), tone),
                  ..state.0
                ],
                state.1 + 1,
              )
            })
          },
        )
      Model(..model, annotations:, next_annotation_id: next_id)
    }
  }
}

fn annotate_log(model: Model, sequence_number: Int) -> Model {
  case model.field_notes {
    False -> model
    True ->
      Model(
        ..model,
        annotations: [
          Annotation(
            model.next_annotation_id,
            LogTarget(sequence_number),
            SequencedNote,
          ),
          ..model.annotations
        ],
        next_annotation_id: model.next_annotation_id + 1,
      )
  }
}

fn changed_names(before: List(String), after: List(String)) -> List(String) {
  after
  |> list.index_map(fn(name, index) { #(name, index) })
  |> list.filter_map(fn(item) {
    case at(before, item.1) {
      Ok(previous) if previous == item.0 -> Error(Nil)
      _ -> Ok(item.0)
    }
  })
}

fn route_in(routes: List(Route), replica: Replica) -> List(String) {
  routes
  |> list.find(fn(route) { route.replica == replica })
  |> result.map(fn(route) { route.stations })
  |> result.unwrap([])
}

fn annotation_ttl(annotation: Annotation) -> Int {
  case annotation.target {
    StationTarget(_, _) -> 1300
    LogTarget(_) -> 1400
  }
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

fn next_disjoint_name(
  names: List(String),
  visible: List(String),
  index: Int,
  remaining: Int,
) -> #(String, Int) {
  case
    remaining <= 0,
    at(names, positive_remainder(index, list.length(names)))
  {
    True, Ok(base) -> #(suffixed_name(base, visible, 2), index + 3)
    True, Error(Nil) -> #("waypoint " <> int.to_string(index + 1), index + 3)
    False, Ok(name) ->
      case list.contains(visible, name) {
        True -> next_disjoint_name(names, visible, index + 3, remaining - 1)
        False -> #(name, index + 3)
      }
    False, Error(Nil) -> #("waypoint " <> int.to_string(index + 1), index + 3)
  }
}

fn suffixed_name(base: String, visible: List(String), suffix: Int) -> String {
  let name = base <> " " <> int.to_string(suffix)
  case list.contains(visible, name) {
    True -> suffixed_name(base, visible, suffix + 1)
    False -> name
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

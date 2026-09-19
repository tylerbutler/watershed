import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import lustre/effect.{type Effect}
import watershed/claims_kernel
import watershed/counter_kernel
import watershed/g_counter_kernel
import watershed/g_set_kernel
import watershed/lww_map_kernel
import watershed/lww_register_kernel
import watershed/map_kernel
import watershed/mv_register_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/ordered_collection_kernel
import watershed/pact_map_kernel
import watershed/pn_counter_kernel
import watershed/register_collection_kernel
import watershed/task_manager_kernel
import watershed/two_p_set_kernel
import watershed_lustre
import watershed_site/structure_demo/model.{
  type Model, type Operation, type PendingOperation, type Replica,
  type ReplicaState, type Structure, AllReplicas, ClaimOperation, Claims,
  ClaimsReplica, ClientA, ClientB, ClientBOnly, ClientC, Counter,
  CounterOperation, CounterReplica, Delivering, Failed, Flow, GCounter,
  GCounterOperation, GCounterReplica, GSet, GSetOperation, GSetReplica, LogEntry,
  LwwMap, LwwMapOperation, LwwMapReplica, LwwRegister, LwwRegisterOperation,
  LwwRegisterReplica, Map, MapOperation, MapReplica, Model, MvRegister,
  MvRegisterOperation, MvRegisterReplica, OrMap, OrMapMvRegister, OrMapOperation,
  OrMapReplica, OrSet, OrSetOperation, OrSetReplica, OrderedCollection,
  OrderedOperation, OrderedReplica, PactMap, PactOperation, PactReplica,
  PendingOperation, PnCounter, PnOperation, PnReplica, Ready, RegisterCollection,
  RegisterOperation, RegisterReplica, Starting, Static, TaskManager,
  TaskOperation, TaskReplica, TwoPSet, TwoPSetOperation, TwoPSetReplica,
}

pub type Msg {
  Start
  Started(generation: Int, outcome: Result(Model, String))
  SelectStructure(Structure)
  SelectId(String)
  TogglePanel(Structure)
  StepMap(Replica, key: String, amount: Int)
  IncrementCounter(Replica, amount: Int)
  WriteMv(Replica, value: String)
  ResolveMv(Replica)
  RunRace
  Replay
  ToggleLink
  SetLatency(String)
  SetJitter(Bool)
  SetOrMapMode(String)
  Deliver(generation: Int)
  CounterFinished(
    generation: Int,
    replicas: #(ReplicaState, ReplicaState, ReplicaState),
  )
  Reset
  RuntimeFailed(String)
}

const counter_baseline = 120

pub fn init(selected: Structure) -> #(Model, Effect(Msg)) {
  let model = static_model(selected)
  #(
    Model(..model, phase: Starting),
    watershed_lustre.perform(
      operation: fn() { Ok(ready_model(selected)) },
      outcome: fn(outcome) { Started(model.generation, outcome) },
    ),
  )
}

pub fn static_model(selected: Structure) -> Model {
  let model = ready_model(selected)
  Model(..model, phase: Static)
}

pub fn ready_model(selected: Structure) -> Model {
  let #(alpha, beta, gamma) = replicas(selected)
  Model(
    selected:,
    alpha:,
    beta:,
    gamma:,
    pending: [],
    sequence_number: 0,
    flows: [],
    latency_ms: 700,
    jitter: False,
    link_up: True,
    log: [],
    generation: 0,
    visible_error: None,
    phase: Ready,
    queued_for_b: 0,
    open_panel: None,
    or_map_set_mode: False,
  )
}

pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Started(generation, _)
      | Deliver(generation)
      | CounterFinished(generation, _)
      if generation != model.generation
    -> #(model, effect.none())
    Start if model.phase == Static -> init(model.selected)
    Start -> #(model, effect.none())
    Started(_, Ok(ready)) -> #(
      Model(
        ..ready,
        generation: model.generation,
        latency_ms: model.latency_ms,
        jitter: model.jitter,
        open_panel: model.open_panel,
        or_map_set_mode: model.or_map_set_mode,
      ),
      effect.none(),
    )
    Started(_, Error(reason)) | RuntimeFailed(reason) -> fail(model, reason)
    SelectStructure(selected) -> {
      let next = ready_model(selected)
      #(
        Model(
          ..next,
          generation: model.generation + 1,
          latency_ms: model.latency_ms,
          jitter: model.jitter,
          open_panel: model.open_panel,
          or_map_set_mode: model.or_map_set_mode,
        ),
        effect.none(),
      )
    }
    SelectId(id) ->
      case structure_from_id(id) {
        Ok(selected) -> update(model, SelectStructure(selected))
        Error(Nil) -> fail(model, "Unknown structure: " <> id)
      }
    TogglePanel(selected) ->
      case model.open_panel == Some(selected) {
        True -> #(Model(..model, open_panel: None), effect.none())
        False -> {
          let #(next, _) = update(model, SelectStructure(selected))
          #(Model(..next, open_panel: Some(selected)), effect.none())
        }
      }
    StepMap(replica, key, amount) ->
      case map_value(replica_state(model, replica), key) {
        Error(reason) -> fail(model, reason)
        Ok(current) ->
          enqueue_map(model, replica, key, int.max(0, current + amount))
      }
    IncrementCounter(replica, amount) -> #(
      Model(..model, phase: Delivering),
      watershed_lustre.perform(
        operation: fn() { counter_increment_replicas(model, replica, amount) },
        outcome: fn(replicas) { CounterFinished(model.generation, replicas) },
      ),
    )
    WriteMv(replica, value) -> enqueue_mv(model, replica, value)
    ResolveMv(replica) -> enqueue_mv(model, replica, "raise crest + arm pump")
    RunRace ->
      case model.selected {
        Map -> {
          let #(model, _) = enqueue_map(model, ClientA, "mill-race", 34)
          let #(model, _) = enqueue_map(model, ClientB, "mill-race", 14)
          #(
            model,
            watershed_lustre.after(
              delivery_delay(model),
              Deliver(model.generation),
            ),
          )
        }
        Counter -> #(
          Model(..model, phase: Delivering),
          watershed_lustre.perform(
            operation: counter_race_replicas,
            outcome: fn(replicas) {
              CounterFinished(model.generation, replicas)
            },
          ),
        )
        MvRegister -> {
          let #(model, _) = enqueue_mv(model, ClientA, "raise crest")
          let #(model, _) = enqueue_mv(model, ClientB, "arm pump")
          #(
            model,
            watershed_lustre.after(
              delivery_delay(model),
              Deliver(model.generation),
            ),
          )
        }
        OrSet -> #(
          replace_replicas(model, or_set_race_replicas()),
          effect.none(),
        )
        TwoPSet -> #(
          replace_replicas(model, two_p_set_race_replicas()),
          effect.none(),
        )
        Claims -> #(
          replace_replicas(model, claim_race_replicas()),
          effect.none(),
        )
        OrderedCollection -> #(
          replace_replicas(model, ordered_race_replicas()),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    Replay -> #(model, effect.none())
    ToggleLink ->
      case model.link_up {
        True -> #(
          Model(
            ..model,
            link_up: False,
            queued_for_b: list.length(model.pending),
          ),
          effect.none(),
        )
        False ->
          case model.pending {
            [] -> #(
              Model(..model, link_up: True, queued_for_b: 0),
              effect.none(),
            )
            [_, ..] -> #(
              Model(..model, link_up: True, queued_for_b: 0),
              watershed_lustre.after(0, Deliver(model.generation)),
            )
          }
      }
    SetLatency(value) ->
      case int.parse(value) {
        Ok(milliseconds) -> #(
          Model(..model, latency_ms: int.clamp(milliseconds, 100, 2000)),
          effect.none(),
        )
        Error(_) -> #(model, effect.none())
      }
    SetJitter(value) -> #(Model(..model, jitter: value), effect.none())
    SetOrMapMode(value) ->
      case value {
        "set" -> #(
          Model(
            ..ready_model(OrMap),
            generation: model.generation + 1,
            latency_ms: model.latency_ms,
            jitter: model.jitter,
            open_panel: model.open_panel,
            or_map_set_mode: True,
          ),
          effect.none(),
        )
        "tally" ->
          update(Model(..model, or_map_set_mode: False), SelectStructure(OrMap))
        _ -> #(model, effect.none())
      }
    Deliver(_) if !model.link_up -> #(
      Model(..model, queued_for_b: list.length(model.pending)),
      effect.none(),
    )
    Deliver(_) ->
      case model.pending {
        [] -> #(Model(..model, phase: Ready), effect.none())
        [pending, ..rest] ->
          case deliver(model, pending) {
            Error(reason) -> fail(model, reason)
            Ok(delivered) -> {
              let next =
                Model(..delivered, pending: rest, phase: case rest {
                  [] -> Ready
                  [_, ..] -> Delivering
                })
              #(next, case rest {
                [] -> effect.none()
                [_, ..] ->
                  watershed_lustre.after(
                    delivery_delay(model),
                    Deliver(model.generation),
                  )
              })
            }
          }
      }
    CounterFinished(_, replicas) -> #(
      Model(
        ..replace_replicas(model, replicas),
        phase: Ready,
        sequence_number: model.sequence_number + 2,
        log: [
          LogEntry(model.sequence_number + 2, ClientB, "increment +3"),
          LogEntry(model.sequence_number + 1, ClientA, "increment +7"),
          ..model.log
        ],
      ),
      effect.none(),
    )
    Reset -> {
      let next = ready_model(model.selected)
      #(
        Model(
          ..next,
          generation: model.generation + 1,
          latency_ms: model.latency_ms,
          jitter: model.jitter,
          open_panel: model.open_panel,
        ),
        effect.none(),
      )
    }
  }
}

fn enqueue_map(
  model: Model,
  replica: Replica,
  key: String,
  value: Int,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    MapReplica(state) -> {
      let #(state, _, operation) = map_kernel.set(state, key, json.int(value))
      enqueue(
        put_replica(model, replica, MapReplica(state)),
        replica,
        MapOperation(operation),
        None,
      )
    }
    _ -> fail(model, "The selected structure is not a shared map.")
  }
}

fn enqueue_mv(
  model: Model,
  replica: Replica,
  value: String,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    MvRegisterReplica(state) -> {
      let #(state, _, operation, message_id) =
        mv_register_kernel.set(state, value)
      let model = put_replica(model, replica, MvRegisterReplica(state))
      case model.link_up {
        True ->
          enqueue(
            model,
            replica,
            MvRegisterOperation(operation),
            Some(message_id),
          )
        False ->
          enqueue_offline_mv(
            model,
            replica,
            MvRegisterOperation(operation),
            message_id,
          )
      }
    }
    _ -> fail(model, "The selected structure is not an MV register.")
  }
}

fn enqueue(
  model: Model,
  origin: Replica,
  operation: Operation,
  message_id: Option(Int),
) -> #(Model, Effect(Msg)) {
  let was_empty = list.is_empty(model.pending)
  let pending =
    list.append(model.pending, [
      PendingOperation(
        origin,
        operation,
        message_id,
        model.generation,
        AllReplicas,
      ),
    ])
  let next =
    Model(
      ..model,
      pending:,
      phase: Delivering,
      queued_for_b: case model.link_up {
        True -> model.queued_for_b
        False -> model.queued_for_b + 1
      },
    )
  #(next, case was_empty && model.link_up {
    True ->
      watershed_lustre.after(delivery_delay(model), Deliver(model.generation))
    False -> effect.none()
  })
}

fn deliver(model: Model, pending: PendingOperation) -> Result(Model, String) {
  let PendingOperation(origin, operation, message_id, _, scope) = pending
  case scope {
    ClientBOnly -> {
      use beta <- result.try(deliver_to(
        model.beta,
        ClientB,
        origin,
        operation,
        message_id,
        model.sequence_number,
      ))
      Ok(Model(..model, beta:))
    }
    AllReplicas -> deliver_all(model, origin, operation, message_id)
  }
}

fn deliver_all(
  model: Model,
  origin: Replica,
  operation: Operation,
  message_id: Option(Int),
) -> Result(Model, String) {
  let sequence = model.sequence_number + 1
  use alpha <- result.try(deliver_to(
    model.alpha,
    ClientA,
    origin,
    operation,
    message_id,
    sequence,
  ))
  use beta <- result.try(deliver_to(
    model.beta,
    ClientB,
    origin,
    operation,
    message_id,
    sequence,
  ))
  use gamma <- result.try(deliver_to(
    model.gamma,
    ClientC,
    origin,
    operation,
    message_id,
    sequence,
  ))
  Ok(
    Model(
      ..model,
      alpha:,
      beta:,
      gamma:,
      sequence_number: sequence,
      flows: [
        Flow(
          sequence * 4,
          replica_id_string(origin),
          "seq",
          operation_label(operation),
        ),
        ..model.flows
      ],
      log: [LogEntry(sequence, origin, operation_label(operation)), ..model.log],
    ),
  )
}

fn enqueue_offline_mv(
  model: Model,
  origin: Replica,
  operation: Operation,
  message_id: Int,
) -> #(Model, Effect(Msg)) {
  case origin {
    ClientB ->
      queue_pending(
        model,
        PendingOperation(
          origin,
          operation,
          Some(message_id),
          model.generation,
          AllReplicas,
        ),
      )
    ClientA | ClientC ->
      case deliver_online_without_b(model, origin, operation, message_id) {
        Error(reason) -> fail(model, reason)
        Ok(model) ->
          queue_pending(
            model,
            PendingOperation(
              origin,
              operation,
              Some(message_id),
              model.generation,
              ClientBOnly,
            ),
          )
      }
  }
}

fn deliver_online_without_b(
  model: Model,
  origin: Replica,
  operation: Operation,
  message_id: Int,
) -> Result(Model, String) {
  let sequence = model.sequence_number + 1
  use alpha <- result.try(deliver_to(
    model.alpha,
    ClientA,
    origin,
    operation,
    Some(message_id),
    sequence,
  ))
  use gamma <- result.try(deliver_to(
    model.gamma,
    ClientC,
    origin,
    operation,
    Some(message_id),
    sequence,
  ))
  Ok(
    Model(..model, alpha:, gamma:, sequence_number: sequence, log: [
      LogEntry(sequence, origin, operation_label(operation)),
      ..model.log
    ]),
  )
}

fn queue_pending(
  model: Model,
  pending_operation: PendingOperation,
) -> #(Model, Effect(Msg)) {
  #(
    Model(
      ..model,
      pending: list.append(model.pending, [pending_operation]),
      phase: Delivering,
      queued_for_b: model.queued_for_b + 1,
    ),
    effect.none(),
  )
}

fn deliver_to(
  state: ReplicaState,
  target: Replica,
  origin: Replica,
  operation: Operation,
  message_id: Option(Int),
  sequence: Int,
) -> Result(ReplicaState, String) {
  case state, operation, target == origin {
    MapReplica(state), MapOperation(operation), True ->
      map_kernel.ack_local(state, operation)
      |> result.map(MapReplica)
      |> result.map_error(fn(error) { string_error(error) })
    MapReplica(state), MapOperation(operation), False -> {
      let #(state, _) = map_kernel.apply_remote(state, operation)
      Ok(MapReplica(state))
    }
    MvRegisterReplica(state), MvRegisterOperation(operation), True ->
      case message_id {
        Some(id) ->
          mv_register_kernel.ack_local_with_message_id(state, operation, id)
          |> result.map(MvRegisterReplica)
          |> result.map_error(fn(error) { string_error(error) })
        None -> Error("Missing MV-register message ID.")
      }
    MvRegisterReplica(state), MvRegisterOperation(operation), False -> {
      let #(state, _) = mv_register_kernel.apply_remote(state, operation)
      Ok(MvRegisterReplica(state))
    }
    ClaimsReplica(state), ClaimOperation(operation), True -> {
      let assert Ok(#(state, _, _)) =
        claims_kernel.ack_local(state, operation, sequence)
      Ok(ClaimsReplica(state))
    }
    ClaimsReplica(state), ClaimOperation(operation), False -> {
      let #(state, _) = claims_kernel.apply_remote(state, operation, sequence)
      Ok(ClaimsReplica(state))
    }
    _, _, _ -> Error("The operation does not match the selected structure.")
  }
}

fn fail(model: Model, reason: String) -> #(Model, Effect(Msg)) {
  #(Model(..model, phase: Failed, visible_error: Some(reason)), effect.none())
}

fn delivery_delay(model: Model) -> Int {
  case model.jitter {
    True -> model.latency_ms + 100
    False -> model.latency_ms
  }
}

fn replicas(
  structure: Structure,
) -> #(ReplicaState, ReplicaState, ReplicaState) {
  case structure {
    MvRegister -> {
      let seed_id = replica_id.new("survey-mv")
      let #(seed, _, _) =
        mv_register_kernel.p2p_set(
          mv_register_kernel.new(seed_id),
          "Survey datum",
        )
      let summary = mv_register_kernel.summary(seed) |> json.to_string
      let make = fn(replica) {
        let id = replica_id.new("client-" <> replica_id_string(replica))
        let assert Ok(state) = mv_register_kernel.from_summary(summary, id)
        MvRegisterReplica(state)
      }
      #(make(ClientA), make(ClientB), make(ClientC))
    }
    _ -> #(
      new_replica(structure, ClientA),
      new_replica(structure, ClientB),
      new_replica(structure, ClientC),
    )
  }
}

fn new_replica(structure: Structure, replica: Replica) -> ReplicaState {
  let id = replica_id.new("client-" <> replica_id_string(replica))
  case structure {
    Map ->
      MapReplica(
        map_kernel.from_sequenced([
          #("mill-race", json.int(24)),
          #("kettle-run", json.int(61)),
          #("low-ford", json.int(42)),
        ]),
      )
    Counter -> CounterReplica(counter_kernel.from_summary(counter_baseline))
    GCounter -> GCounterReplica(g_counter_kernel.new(id))
    PnCounter -> PnReplica(pn_counter_kernel.new(id))
    OrMap | OrMapMvRegister ->
      OrMapReplica(
        or_map_kernel.new(id, case structure {
          OrMapMvRegister -> or_map_kernel.MvRegisterMode
          _ -> or_map_kernel.TallyMode
        }),
      )
    LwwMap -> LwwMapReplica(lww_map_kernel.new(id))
    LwwRegister -> LwwRegisterReplica(lww_register_kernel.new(id))
    MvRegister -> {
      let #(state, _, _) =
        mv_register_kernel.p2p_set(mv_register_kernel.new(id), "Survey datum")
      MvRegisterReplica(state)
    }
    OrSet -> OrSetReplica(or_set_kernel.new(id))
    GSet -> GSetReplica(g_set_kernel.new())
    TwoPSet -> TwoPSetReplica(two_p_set_kernel.new())
    Claims ->
      ClaimsReplica(
        claims_kernel.from_summary([
          #("pump-house", json.string("Survey"), 0),
        ]),
      )
    RegisterCollection -> RegisterReplica(register_collection_kernel.new())
    OrderedCollection ->
      OrderedReplica(
        ordered_collection_kernel.from_summary(
          [
            json.string("grade-stakes"),
            json.string("pump-check"),
          ],
          [],
        ),
      )
    TaskManager ->
      TaskReplica(
        task_manager_kernel.from_summary([
          #("sluice-inspection", [1]),
        ]),
      )
    PactMap -> PactReplica(pact_map_kernel.new())
  }
}

fn replica_state(model: Model, replica: Replica) -> ReplicaState {
  case replica {
    ClientA -> model.alpha
    ClientB -> model.beta
    ClientC -> model.gamma
  }
}

fn put_replica(model: Model, replica: Replica, state: ReplicaState) -> Model {
  case replica {
    ClientA -> Model(..model, alpha: state)
    ClientB -> Model(..model, beta: state)
    ClientC -> Model(..model, gamma: state)
  }
}

fn replace_replicas(
  model: Model,
  replicas: #(ReplicaState, ReplicaState, ReplicaState),
) -> Model {
  Model(
    ..model,
    alpha: replicas.0,
    beta: replicas.1,
    gamma: replicas.2,
    phase: Ready,
  )
}

fn map_value(state: ReplicaState, key: String) -> Result(Int, String) {
  case state {
    MapReplica(state) ->
      map_kernel.get(state, key)
      |> result.map(fn(value) {
        json.parse(json.to_string(value), decode.int)
        |> result.unwrap(0)
      })
      |> result.replace_error("Unknown map key.")
    _ -> Error("The selected structure is not a shared map.")
  }
}

pub fn map_values(model: Model, key: String) -> List(Int) {
  [model.alpha, model.beta, model.gamma]
  |> list.map(fn(state) { map_value(state, key) |> result.unwrap(0) })
}

pub fn map_value_for(model: Model, replica: Replica, key: String) -> Int {
  map_value(replica_state(model, replica), key) |> result.unwrap(0)
}

pub fn counter_value(model: Model, replica: Replica) -> Int {
  case replica_state(model, replica) {
    CounterReplica(state) -> state.value
    _ -> 0
  }
}

pub fn mv_sequenced_values(model: Model, replica: Replica) -> List(String) {
  case replica_state(model, replica) {
    MvRegisterReplica(state) -> mv_register_kernel.sequenced_values(state)
    _ -> []
  }
}

pub fn mv_values(model: Model, replica: Replica) -> List(String) {
  case replica_state(model, replica) {
    MvRegisterReplica(state) -> mv_register_kernel.values(state)
    _ -> []
  }
}

pub fn pending_count(model: Model, replica: Replica) -> Int {
  case replica_state(model, replica) {
    MapReplica(state) -> list.length(state.pending)
    CounterReplica(state) -> list.length(state.pending)
    GCounterReplica(state) -> list.length(state.pending)
    PnReplica(state) -> list.length(state.pending)
    OrMapReplica(state) -> list.length(state.pending)
    LwwMapReplica(state) -> list.length(state.pending)
    LwwRegisterReplica(state) -> list.length(state.pending)
    MvRegisterReplica(state) -> list.length(state.pending)
    OrSetReplica(state) -> list.length(state.pending)
    GSetReplica(state) -> list.length(state.pending)
    TwoPSetReplica(state) -> list.length(state.pending)
    ClaimsReplica(state) -> dict.size(state.pending)
    RegisterReplica(_) | OrderedReplica(_) | TaskReplica(_) | PactReplica(_) ->
      0
  }
}

pub fn structure_id(structure: Structure) -> String {
  case structure {
    Map -> "map"
    Counter -> "counter"
    GCounter -> "gcounter"
    PnCounter -> "pn"
    OrMap -> "ormap"
    OrMapMvRegister -> "or-map-mv-register"
    LwwMap -> "lww-map"
    LwwRegister -> "lww-register"
    MvRegister -> "mv-register"
    OrSet -> "orset"
    GSet -> "gset"
    TwoPSet -> "twopset"
    Claims -> "claims"
    RegisterCollection -> "registers"
    OrderedCollection -> "ordered"
    TaskManager -> "tasks"
    PactMap -> "pact"
  }
}

pub fn structure_from_id(id: String) -> Result(Structure, Nil) {
  case id {
    "map" -> Ok(Map)
    "counter" -> Ok(Counter)
    "gcounter" -> Ok(GCounter)
    "pn" -> Ok(PnCounter)
    "ormap" -> Ok(OrMap)
    "or-map-mv-register" -> Ok(OrMapMvRegister)
    "lww-map" -> Ok(LwwMap)
    "lww-register" -> Ok(LwwRegister)
    "mv-register" -> Ok(MvRegister)
    "orset" -> Ok(OrSet)
    "gset" -> Ok(GSet)
    "twopset" -> Ok(TwoPSet)
    "claims" -> Ok(Claims)
    "registers" -> Ok(RegisterCollection)
    "ordered" -> Ok(OrderedCollection)
    "tasks" -> Ok(TaskManager)
    "pact" -> Ok(PactMap)
    _ -> Error(Nil)
  }
}

fn replica_id_string(replica: Replica) -> String {
  case replica {
    ClientA -> "a"
    ClientB -> "b"
    ClientC -> "c"
  }
}

fn operation_label(operation: Operation) -> String {
  case operation {
    MapOperation(_) -> "map write"
    CounterOperation(_) -> "counter increment"
    GCounterOperation(_) -> "grow-only increment"
    PnOperation(_) -> "PN update"
    OrMapOperation(_) -> "OR-map edit"
    LwwMapOperation(_) -> "LWW-map edit"
    LwwRegisterOperation(_) -> "LWW-register write"
    MvRegisterOperation(_) -> "MV-register write"
    OrSetOperation(_) -> "OR-set edit"
    GSetOperation(_) -> "G-set add"
    TwoPSetOperation(_) -> "2P-set edit"
    ClaimOperation(_) -> "claim"
    RegisterOperation(_) -> "register write"
    OrderedOperation(_) -> "ordered operation"
    TaskOperation(_) -> "task operation"
    PactOperation(_) -> "pact operation"
  }
}

fn string_error(error: a) -> String {
  "Kernel operation failed: " <> string.inspect(error)
}

pub fn map_race_values() -> List(Int) {
  let initial = map_kernel.from_sequenced([#("mill-race", json.int(24))])
  let #(a, _, a_op) = map_kernel.set(initial, "mill-race", json.int(34))
  let #(b, _, b_op) = map_kernel.set(initial, "mill-race", json.int(14))
  let assert Ok(a) = map_kernel.ack_local(a, a_op)
  let #(a, _) = map_kernel.apply_remote(a, b_op)
  let #(b, _) = map_kernel.apply_remote(b, a_op)
  let assert Ok(b) = map_kernel.ack_local(b, b_op)
  let #(c, _) = map_kernel.apply_remote(initial, a_op)
  let #(c, _) = map_kernel.apply_remote(c, b_op)
  [MapReplica(a), MapReplica(b), MapReplica(c)]
  |> list.map(fn(state) { map_value(state, "mill-race") |> result.unwrap(0) })
}

pub fn counter_race_values() -> List(Int) {
  let replicas = counter_race_replicas()
  [replicas.0, replicas.1, replicas.2]
  |> list.map(fn(state) {
    let assert CounterReplica(state) = state
    state.value
  })
}

fn counter_race_replicas() -> #(ReplicaState, ReplicaState, ReplicaState) {
  let initial = counter_kernel.from_summary(counter_baseline)
  let #(a, _, a_op, _) = counter_kernel.increment(initial, 7)
  let #(b, _, b_op, _) = counter_kernel.increment(initial, 3)
  let assert Ok(a) = counter_kernel.ack_local(a, a_op)
  let #(a, _) = counter_kernel.apply_remote(a, b_op)
  let #(b, _) = counter_kernel.apply_remote(b, a_op)
  let assert Ok(b) = counter_kernel.ack_local(b, b_op)
  let #(c, _) = counter_kernel.apply_remote(initial, a_op)
  let #(c, _) = counter_kernel.apply_remote(c, b_op)
  #(CounterReplica(a), CounterReplica(b), CounterReplica(c))
}

fn counter_increment_replicas(
  model: Model,
  origin: Replica,
  amount: Int,
) -> #(ReplicaState, ReplicaState, ReplicaState) {
  let assert CounterReplica(author) = replica_state(model, origin)
  let #(author, _, operation, _) = counter_kernel.increment(author, amount)
  let assert Ok(author) = counter_kernel.ack_local(author, operation)
  let update = fn(replica, state) {
    case replica == origin, state {
      True, _ -> CounterReplica(author)
      False, CounterReplica(state) -> {
        let #(state, _) = counter_kernel.apply_remote(state, operation)
        CounterReplica(state)
      }
      _, _ -> state
    }
  }
  #(
    update(ClientA, model.alpha),
    update(ClientB, model.beta),
    update(ClientC, model.gamma),
  )
}

pub fn duplicate_pn_values() -> List(Int) {
  let initial = pn_counter_kernel.new(replica_id.new("baseline"))
  let #(initial, _, baseline, _) = pn_counter_kernel.update(initial, 44)
  let assert Ok(initial) = pn_counter_kernel.ack_local(initial, baseline)
  let #(author, _, operation, _) =
    pn_counter_kernel.update(
      pn_counter_kernel.from_sequenced(initial.sequenced, replica_id.new("a")),
      8,
    )
  let assert Ok(author) = pn_counter_kernel.ack_local(author, operation)
  let observer =
    pn_counter_kernel.from_sequenced(initial.sequenced, replica_id.new("b"))
  let #(observer, _) = pn_counter_kernel.apply_remote(observer, operation)
  let #(observer, _) = pn_counter_kernel.apply_remote(observer, operation)
  [author, observer, observer] |> list.map(pn_counter_kernel.value)
}

pub fn or_set_race_values() -> List(List(String)) {
  let replicas = or_set_race_replicas()
  [replicas.0, replicas.1, replicas.2]
  |> list.map(fn(replica) {
    let assert OrSetReplica(state) = replica
    or_set_kernel.values(state)
  })
}

fn or_set_race_replicas() -> #(ReplicaState, ReplicaState, ReplicaState) {
  let a0 = or_set_kernel.new(replica_id.new("a"))
  let #(a0, _, north, _) = or_set_kernel.add(a0, "north-stake")
  let assert Ok(a0) = or_set_kernel.ack_local(a0, north)
  let #(a0, _, sluice, _) = or_set_kernel.add(a0, "sluice-tag")
  let assert Ok(a0) = or_set_kernel.ack_local(a0, sluice)
  let raw = json.to_string(or_set_kernel.summary(a0))
  let assert Ok(a) = or_set_kernel.from_summary(raw, replica_id.new("a"))
  let assert Ok(b) = or_set_kernel.from_summary(raw, replica_id.new("b"))
  let assert Ok(c) = or_set_kernel.from_summary(raw, replica_id.new("c"))
  let #(_, _, remove, _) = or_set_kernel.remove(a, "north-stake")
  let #(_, _, add, _) = or_set_kernel.add(b, "north-stake")
  let #(a, _) = or_set_kernel.apply_remote(a, remove)
  let #(a, _) = or_set_kernel.apply_remote(a, add)
  let #(b, _) = or_set_kernel.apply_remote(b, remove)
  let #(b, _) = or_set_kernel.apply_remote(b, add)
  let #(c, _) = or_set_kernel.apply_remote(c, remove)
  let #(c, _) = or_set_kernel.apply_remote(c, add)
  #(OrSetReplica(a), OrSetReplica(b), OrSetReplica(c))
}

pub fn two_p_set_race_values() -> List(List(String)) {
  let replicas = two_p_set_race_replicas()
  [replicas.0, replicas.1, replicas.2]
  |> list.map(fn(replica) {
    let assert TwoPSetReplica(state) = replica
    two_p_set_kernel.values(state)
  })
}

fn two_p_set_race_replicas() -> #(ReplicaState, ReplicaState, ReplicaState) {
  let #(_, _, add, _) = two_p_set_kernel.add(two_p_set_kernel.new(), "stake-3")
  let #(_, _, remove, _) =
    two_p_set_kernel.remove(two_p_set_kernel.new(), "stake-3")
  let apply = fn() {
    let #(state, _) = two_p_set_kernel.apply_remote(two_p_set_kernel.new(), add)
    let #(state, _) = two_p_set_kernel.apply_remote(state, remove)
    TwoPSetReplica(state)
  }
  #(apply(), apply(), apply())
}

pub fn claim_race_values() -> List(Option(String)) {
  let replicas = claim_race_replicas()
  [replicas.0, replicas.1, replicas.2]
  |> list.map(fn(replica) {
    let assert ClaimsReplica(state) = replica
    claims_kernel.get(state, "north-levee")
    |> result.map(fn(value) {
      json.parse(json.to_string(value), decode.string) |> result.unwrap("")
    })
    |> fn(value) {
      case value {
        Ok(value) -> Some(value)
        Error(_) -> None
      }
    }
  })
}

fn claim_race_replicas() -> #(ReplicaState, ReplicaState, ReplicaState) {
  let a = claims_kernel.new()
  let b = claims_kernel.new()
  let c = claims_kernel.new()
  let assert Ok(claims_kernel.Submitted(a, a_op)) =
    claims_kernel.claim_once(a, "north-levee", json.string("A"), 0)
  let assert Ok(claims_kernel.Submitted(b, b_op)) =
    claims_kernel.claim_once(b, "north-levee", json.string("B"), 0)
  let assert Ok(#(a, _, _)) = claims_kernel.ack_local(a, a_op, 1)
  let #(a, _) = claims_kernel.apply_remote(a, b_op, 2)
  let #(b, _) = claims_kernel.apply_remote(b, a_op, 1)
  let assert Ok(#(b, _, _)) = claims_kernel.ack_local(b, b_op, 2)
  let #(c, _) = claims_kernel.apply_remote(c, a_op, 1)
  let #(c, _) = claims_kernel.apply_remote(c, b_op, 2)
  #(ClaimsReplica(a), ClaimsReplica(b), ClaimsReplica(c))
}

pub fn ordered_race_values() -> List(Option(String)) {
  let initial =
    ordered_collection_kernel.from_summary([json.string("flood-watch")], [])
  let a_op = ordered_collection_kernel.acquire("a1")
  let b_op = ordered_collection_kernel.acquire("b1")
  let assert #(_, _, Some(a_outcome)) =
    ordered_collection_kernel.ack_local(initial, a_op, 1)
  let #(after_a, _) = ordered_collection_kernel.apply_remote(initial, a_op, 1)
  let assert #(_, _, Some(b_outcome)) =
    ordered_collection_kernel.ack_local(after_a, b_op, 2)
  [ordered_value(a_outcome), ordered_value(b_outcome)]
}

fn ordered_race_replicas() -> #(ReplicaState, ReplicaState, ReplicaState) {
  let initial =
    ordered_collection_kernel.from_summary([json.string("flood-watch")], [])
  let a_op = ordered_collection_kernel.acquire("a1")
  let b_op = ordered_collection_kernel.acquire("b1")
  let #(a, _, _) = ordered_collection_kernel.ack_local(initial, a_op, 1)
  let #(a, _) = ordered_collection_kernel.apply_remote(a, b_op, 2)
  let #(b, _) = ordered_collection_kernel.apply_remote(initial, a_op, 1)
  let #(b, _, _) = ordered_collection_kernel.ack_local(b, b_op, 2)
  let #(c, _) = ordered_collection_kernel.apply_remote(initial, a_op, 1)
  let #(c, _) = ordered_collection_kernel.apply_remote(c, b_op, 2)
  #(OrderedReplica(a), OrderedReplica(b), OrderedReplica(c))
}

fn ordered_value(
  outcome: ordered_collection_kernel.AcquireOutcome,
) -> Option(String) {
  case outcome {
    ordered_collection_kernel.AcquiredItem(_, value) ->
      json.parse(json.to_string(value), decode.string)
      |> fn(value) {
        case value {
          Ok(value) -> Some(value)
          Error(_) -> None
        }
      }
    ordered_collection_kernel.QueueEmpty -> None
    ordered_collection_kernel.Aborted -> None
  }
}

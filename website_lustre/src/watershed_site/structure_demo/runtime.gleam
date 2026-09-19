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
  type Instance, type Model, type Operation, type PendingOperation,
  type ReplayOperation, type Replica, type ReplicaState, type Structure,
  AllReplicas, ClaimOperation, Claims, ClaimsReplica, ClientA, ClientB,
  ClientBOnly, ClientC, Counter, CounterOperation, CounterReplica, Delivering,
  Failed, Flow, GCounter, GCounterOperation, GCounterReplica, GSet,
  GSetOperation, GSetReplica, Instance, LogEntry, LwwMap, LwwMapOperation,
  LwwMapReplica, LwwRegister, LwwRegisterOperation, LwwRegisterReplica, Map,
  MapOperation, MapReplica, Model, MvRegister, MvRegisterOperation,
  MvRegisterReplica, OrMap, OrMapMvRegister, OrMapOperation, OrMapReplica, OrSet,
  OrSetOperation, OrSetReplica, OrderedCollection, OrderedOperation,
  OrderedReplica, PactMap, PactOperation, PactReplica, PendingOperation,
  PnCounter, PnOperation, PnReplica, Ready, RegisterCollection,
  RegisterOperation, RegisterReplica, ReplayAll, ReplayOperation, Starting,
  Static, TaskManager, TaskOperation, TaskReplica, TwoPSet, TwoPSetOperation,
  TwoPSetReplica,
}

pub type Msg {
  NoOp
  Defer(Msg)
  Deferred(generation: Int, outcome: Result(#(Model, Model), String))
  Project
  Start
  Started(generation: Int, outcome: Result(Model, String))
  SelectStructure(Structure)
  SelectId(String)
  TogglePanel(Structure)
  StepMap(Replica, key: String, amount: Int)
  IncrementCounter(Replica, amount: Int)
  IncrementGCounter(Replica, amount: Int)
  UpdatePnCounter(Replica, amount: Int)
  IncrementOrMap(Replica, key: String, amount: Int)
  RemoveOrMap(Replica, key: String)
  AddOrMapMember(Replica, key: String, member: String)
  RemoveOrMapMember(Replica, key: String, member: String)
  WriteLwwMap(Replica, key: String, value: Option(String))
  WriteLwwRegister(Replica, value: String)
  WriteOrMapMv(Replica, key: String, value: Option(String))
  WriteMv(Replica, value: String)
  SetDraft(Replica, value: String)
  SetKeyDraft(Replica, value: String)
  SubmitDraft(Replica)
  ResolveMv(Replica)
  AddOrSet(Replica, element: String)
  RemoveOrSet(Replica, element: String)
  AddGSet(Replica, element: String)
  AddTwoPSet(Replica, element: String)
  RemoveTwoPSet(Replica, element: String)
  Claim(Replica, key: String)
  WriteRegister(Replica, key: String)
  OrderedAdd(Replica)
  OrderedAcquire(Replica)
  OrderedComplete(Replica)
  OrderedRelease(Replica)
  TaskVolunteer(Replica, task_id: String)
  TaskAbandon(Replica, task_id: String)
  TaskComplete(Replica, task_id: String)
  PactSet(Replica, key: String)
  PactDelete(Replica, key: String)
  RunRace
  Replay
  ToggleLink
  SetPace(String)
  SetJitter(Bool)
  SetFieldNotes(Bool)
  SetOrMapMode(String)
  Deliver(generation: Int)
  ClearFlow(generation: Int, id: Int)
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
      operation: fn() { project_model(ready_model(selected)) },
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
    draft_a: "raise crest",
    draft_b: "arm pump",
    draft_c: "check datum",
    key_a: "gate-mode",
    key_b: "gate-mode",
    key_c: "gate-mode",
    playback_ms: 600,
    field_notes: False,
    last_replay: None,
    instances: [],
    deferred_work: [],
    work_running: False,
    delivery_armed: False,
  )
}

pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Started(generation, _)
      | Deferred(generation, _)
      | Deliver(generation)
      | CounterFinished(generation, _)
      | ClearFlow(generation, _)
      if generation != model.generation
    -> #(model, effect.none())
    NoOp -> #(model, effect.none())
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
        playback_ms: model.playback_ms,
        field_notes: model.field_notes,
        draft_a: model.draft_a,
        draft_b: model.draft_b,
        draft_c: model.draft_c,
        key_a: model.key_a,
        key_b: model.key_b,
        key_c: model.key_c,
        link_up: model.link_up,
        instances: model.instances,
      ),
      effect.none(),
    )
    Started(_, Error(reason)) | RuntimeFailed(reason) -> fail(model, reason)
    Deferred(_, Error(reason)) -> finish_deferred_error(model, reason)
    Deferred(_, Ok(pair)) -> finish_deferred(model, pair.0, pair.1)
    Deliver(_) -> defer(model, message)
    SetDraft(_, _)
    | SetKeyDraft(_, _)
    | SetPace(_)
    | SetJitter(_)
    | SetFieldNotes(_) -> update_now(model, message)
    Defer(command) -> defer(model, command)
    _ -> defer(model, message)
  }
}

@internal
pub fn transition(model: Model, message: Msg) -> Model {
  update_now(model, message).0
}

fn defer(model: Model, command: Msg) -> #(Model, Effect(Msg)) {
  let work = fn(current: Model) {
    let next = transition(current, command)
    project_model(next)
    |> result.map(fn(next) { #(current, next) })
  }
  let queued =
    Model(..model, deferred_work: list.append(model.deferred_work, [work]))
  case model.work_running {
    True -> #(queued, effect.none())
    False -> start_work(queued)
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
      selected: next.selected,
      alpha: next.alpha,
      beta: next.beta,
      gamma: next.gamma,
      pending: next.pending,
      sequence_number: next.sequence_number,
      flows: next.flows,
      latency_ms: changed(model.latency_ms, before.latency_ms, next.latency_ms),
      jitter: changed(model.jitter, before.jitter, next.jitter),
      link_up: next.link_up,
      log: next.log,
      generation: next.generation,
      visible_error: next.visible_error,
      phase: next.phase,
      queued_for_b: next.queued_for_b,
      open_panel: next.open_panel,
      or_map_set_mode: next.or_map_set_mode,
      last_replay: next.last_replay,
      instances: next.instances,
      draft_a: changed(model.draft_a, before.draft_a, next.draft_a),
      draft_b: changed(model.draft_b, before.draft_b, next.draft_b),
      draft_c: changed(model.draft_c, before.draft_c, next.draft_c),
      key_a: changed(model.key_a, before.key_a, next.key_a),
      key_b: changed(model.key_b, before.key_b, next.key_b),
      key_c: changed(model.key_c, before.key_c, next.key_c),
      playback_ms: changed(
        model.playback_ms,
        before.playback_ms,
        next.playback_ms,
      ),
      field_notes: changed(
        model.field_notes,
        before.field_notes,
        next.field_notes,
      ),
      deferred_work: remaining,
      work_running: False,
      delivery_armed: next.delivery_armed,
    )
  let #(next, delivery) = case
    !next.delivery_armed && next.link_up && !list.is_empty(next.pending)
  {
    True -> #(
      Model(..next, delivery_armed: True),
      watershed_lustre.after(delivery_delay(next), Deliver(next.generation)),
    )
    False -> #(next, effect.none())
  }
  let old_ids = list.map(model.flows, fn(flow) { flow.id })
  let clears =
    next.flows
    |> list.filter(fn(flow) { !list.contains(old_ids, flow.id) })
    |> list.map(fn(flow) {
      watershed_lustre.after(
        next.playback_ms,
        ClearFlow(next.generation, flow.id),
      )
    })
  let #(next, work) = start_work(next)
  #(next, effect.batch([work, delivery, ..clears]))
}

fn changed(current: a, before: a, next: a) -> a {
  case current == before {
    True -> next
    False -> current
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

fn update_now(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Started(generation, _)
      | Deferred(generation, _)
      | Deliver(generation)
      | CounterFinished(generation, _)
      | ClearFlow(generation, _)
      if generation != model.generation
    -> #(model, effect.none())
    NoOp -> #(model, effect.none())
    Start if model.phase == Static -> init(model.selected)
    Start -> #(model, effect.none())
    Defer(command) -> update_now(model, command)
    Deferred(_, Ok(pair)) -> #(pair.1, effect.none())
    Deferred(_, Error(reason)) -> fail(model, reason)
    Project ->
      case project_model(model) {
        Ok(projected) -> #(projected, effect.none())
        Error(reason) -> fail(model, reason)
      }
    Started(_, Ok(ready)) -> #(
      Model(
        ..ready,
        generation: model.generation,
        latency_ms: model.latency_ms,
        jitter: model.jitter,
        open_panel: model.open_panel,
        or_map_set_mode: model.or_map_set_mode,
        playback_ms: model.playback_ms,
        field_notes: model.field_notes,
        draft_a: model.draft_a,
        draft_b: model.draft_b,
        draft_c: model.draft_c,
        key_a: model.key_a,
        key_b: model.key_b,
        key_c: model.key_c,
        link_up: model.link_up,
        instances: model.instances,
      ),
      effect.none(),
    )
    Started(_, Error(reason)) | RuntimeFailed(reason) -> fail(model, reason)
    SelectStructure(selected) -> select_structure(model, selected)
    SelectId(id) ->
      case structure_from_id(id) {
        Ok(selected) -> update_now(model, SelectStructure(selected))
        Error(Nil) -> fail(model, "Unknown structure: " <> id)
      }
    TogglePanel(selected) ->
      case model.open_panel == Some(selected) {
        True -> #(Model(..model, open_panel: None), effect.none())
        False -> {
          let #(next, effect) = select_structure(model, selected)
          #(Model(..next, open_panel: Some(selected)), effect)
        }
      }
    StepMap(replica, key, amount) ->
      case map_value(replica_state(model, replica), key) {
        Error(reason) -> fail(model, reason)
        Ok(current) ->
          enqueue_map(model, replica, key, int.max(0, current + amount))
      }
    IncrementCounter(replica, amount) -> #(
      Model(
        ..replace_replicas(
          model,
          counter_increment_replicas(model, replica, amount),
        ),
        sequence_number: model.sequence_number + 1,
        log: [
          LogEntry(
            model.sequence_number + 1,
            replica,
            "increment " <> signed(amount),
          ),
          ..model.log
        ],
      ),
      effect.none(),
    )
    IncrementGCounter(replica, amount) ->
      enqueue_g_counter(model, replica, amount)
    UpdatePnCounter(replica, amount) -> enqueue_pn(model, replica, amount)
    IncrementOrMap(replica, key, amount) ->
      enqueue_or_map_increment(model, replica, key, amount)
    RemoveOrMap(replica, key) -> enqueue_or_map_remove(model, replica, key)
    AddOrMapMember(replica, key, member) ->
      enqueue_or_map_member(model, replica, key, member, True)
    RemoveOrMapMember(replica, key, member) ->
      enqueue_or_map_member(model, replica, key, member, False)
    WriteLwwMap(replica, key, value) ->
      enqueue_lww_map(model, replica, key, value)
    WriteLwwRegister(replica, value) ->
      enqueue_lww_register(model, replica, value)
    WriteOrMapMv(replica, key, value) ->
      enqueue_or_map_mv(model, replica, key, value)
    WriteMv(replica, value) -> enqueue_mv(model, replica, value)
    SetDraft(replica, value) -> #(
      put_draft(model, replica, value),
      effect.none(),
    )
    SetKeyDraft(replica, value) -> #(
      put_key_draft(model, replica, value),
      effect.none(),
    )
    SubmitDraft(replica) -> enqueue_mv(model, replica, draft(model, replica))
    ResolveMv(replica) -> enqueue_mv(model, replica, "raise crest + arm pump")
    AddOrSet(replica, element) ->
      enqueue_set(model, replica, element, "orset-add")
    RemoveOrSet(replica, element) ->
      enqueue_set(model, replica, element, "orset-remove")
    AddGSet(replica, element) ->
      enqueue_set(model, replica, element, "gset-add")
    AddTwoPSet(replica, element) ->
      enqueue_set(model, replica, element, "twopset-add")
    RemoveTwoPSet(replica, element) ->
      enqueue_set(model, replica, element, "twopset-remove")
    Claim(replica, key) -> enqueue_claim(model, replica, key)
    WriteRegister(replica, key) -> enqueue_register(model, replica, key)
    OrderedAdd(replica) -> enqueue_ordered(model, replica, "add")
    OrderedAcquire(replica) -> enqueue_ordered(model, replica, "acquire")
    OrderedComplete(replica) -> enqueue_ordered(model, replica, "complete")
    OrderedRelease(replica) -> enqueue_ordered(model, replica, "release")
    TaskVolunteer(replica, task_id) ->
      enqueue_task(model, replica, task_id, "volunteer")
    TaskAbandon(replica, task_id) ->
      enqueue_task(model, replica, task_id, "abandon")
    TaskComplete(replica, task_id) ->
      enqueue_task(model, replica, task_id, "complete")
    PactSet(replica, key) -> enqueue_pact(model, replica, key, False)
    PactDelete(replica, key) -> enqueue_pact(model, replica, key, True)
    RunRace -> #(
      run_commands(model, case model.selected {
        Map -> [
          StepMap(ClientA, "mill-race", 10),
          StepMap(ClientB, "mill-race", -10),
        ]
        Counter -> [IncrementCounter(ClientA, 8), IncrementCounter(ClientB, 5)]
        GCounter -> [
          IncrementGCounter(ClientA, 7),
          IncrementGCounter(ClientB, 3),
        ]
        PnCounter -> [
          UpdatePnCounter(ClientA, 8),
          UpdatePnCounter(ClientB, -5),
        ]
        OrMap ->
          case model.or_map_set_mode {
            True -> [
              AddOrMapMember(ClientA, "inspection-brief", "draft"),
              AddOrMapMember(ClientB, "inspection-brief", "reviewed"),
            ]
            False -> [
              RemoveOrMap(ClientA, "spoil-north"),
              IncrementOrMap(ClientB, "spoil-north", 6),
            ]
          }
        OrMapMvRegister -> [
          WriteOrMapMv(ClientA, "gate-mode", Some("raise crest")),
          WriteOrMapMv(ClientB, "gate-mode", Some("arm pump")),
        ]
        LwwMap -> [
          WriteLwwMap(ClientA, "gate-mode", Some("open")),
          WriteLwwMap(ClientB, "gate-mode", Some("closed")),
        ]
        LwwRegister -> [
          WriteLwwRegister(ClientA, "raise crest"),
          WriteLwwRegister(ClientB, "arm pump"),
        ]
        MvRegister -> [
          WriteMv(ClientA, "raise crest"),
          WriteMv(ClientB, "arm pump"),
        ]
        OrSet -> [
          RemoveOrSet(ClientA, "north-stake"),
          AddOrSet(ClientB, "north-stake"),
        ]
        GSet -> [
          AddGSet(ClientA, "BM-22"),
          AddGSet(ClientB, "BM-31"),
        ]
        TwoPSet -> [
          RemoveTwoPSet(ClientA, "stake-3"),
          AddTwoPSet(ClientB, "stake-3"),
        ]
        Claims -> [
          Claim(ClientA, "spillway-gate"),
          Claim(ClientB, "spillway-gate"),
        ]
        RegisterCollection -> [
          WriteRegister(ClientA, "gate-setpoint"),
          WriteRegister(ClientB, "gate-setpoint"),
        ]
        OrderedCollection -> [
          OrderedAcquire(ClientA),
          OrderedAcquire(ClientB),
        ]
        TaskManager -> [
          TaskVolunteer(ClientA, "pump-watch"),
          TaskVolunteer(ClientB, "pump-watch"),
        ]
        PactMap -> [
          PactSet(ClientA, "gate-policy"),
          PactSet(ClientB, "gate-policy"),
        ]
      }),
      effect.none(),
    )
    Replay ->
      case model.last_replay {
        None -> #(model, effect.none())
        Some(ReplayOperation(operation, message_id, sequence_number)) ->
          queue_pending(
            model,
            PendingOperation(
              ClientA,
              operation,
              message_id,
              model.generation,
              ReplayAll(sequence_number),
            ),
          )
      }
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
        False -> restore_link(model)
      }
    SetPace(value) -> #(
      Model(..model, playback_ms: pace_milliseconds(value)),
      effect.none(),
    )
    SetJitter(value) -> #(Model(..model, jitter: value), effect.none())
    SetFieldNotes(value) -> #(Model(..model, field_notes: value), effect.none())
    SetOrMapMode(value) ->
      case value {
        "set" if !model.or_map_set_mode -> {
          let replicas = or_map_replicas(or_map_kernel.OrSetMode)
          #(
            Model(
              ..replace_replicas(model, replicas),
              generation: model.generation + 1,
              pending: [],
              sequence_number: 0,
              log: [],
              flows: [],
              last_replay: None,
              delivery_armed: False,
              or_map_set_mode: True,
              key_a: "inspection-brief",
              key_b: "inspection-brief",
              key_c: "inspection-brief",
            ),
            effect.none(),
          )
        }
        "tally" if model.or_map_set_mode -> {
          let replicas = or_map_replicas(or_map_kernel.TallyMode)
          #(
            Model(
              ..replace_replicas(model, replicas),
              generation: model.generation + 1,
              pending: [],
              sequence_number: 0,
              log: [],
              flows: [],
              last_replay: None,
              delivery_armed: False,
              or_map_set_mode: False,
            ),
            effect.none(),
          )
        }
        _ -> #(model, effect.none())
      }
    Deliver(_) if !model.link_up -> #(
      Model(
        ..model,
        queued_for_b: list.length(model.pending),
        delivery_armed: False,
      ),
      effect.none(),
    )
    Deliver(_) -> {
      let model = Model(..model, delivery_armed: False)
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
              #(next, effect.none())
            }
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
    ClearFlow(_, id) -> #(
      Model(
        ..model,
        flows: list.filter(model.flows, fn(flow) { flow.id != id }),
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
          playback_ms: model.playback_ms,
          field_notes: model.field_notes,
          draft_a: model.draft_a,
          draft_b: model.draft_b,
          draft_c: model.draft_c,
          key_a: model.key_a,
          key_b: model.key_b,
          key_c: model.key_c,
          instances: model.instances,
        ),
        effect.none(),
      )
    }
  }
}

fn run_commands(model: Model, commands: List(Msg)) -> Model {
  list.fold(commands, model, fn(model, command) { update_now(model, command).0 })
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
      enqueue(model, replica, MvRegisterOperation(operation), Some(message_id))
    }
    _ -> fail(model, "The selected structure is not an MV register.")
  }
}

fn enqueue_g_counter(
  model: Model,
  replica: Replica,
  amount: Int,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    GCounterReplica(state) ->
      case g_counter_kernel.increment(state, amount) {
        Error(reason) -> fail(model, string_error(reason))
        Ok(#(state, _, operation, message_id)) ->
          enqueue(
            put_replica(model, replica, GCounterReplica(state)),
            replica,
            GCounterOperation(operation),
            Some(message_id),
          )
      }
    _ -> fail(model, "The selected structure is not a G-counter.")
  }
}

fn enqueue_pn(
  model: Model,
  replica: Replica,
  amount: Int,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    PnReplica(state) -> {
      let #(state, _, operation, message_id) =
        pn_counter_kernel.update(state, amount)
      enqueue(
        put_replica(model, replica, PnReplica(state)),
        replica,
        PnOperation(operation),
        Some(message_id),
      )
    }
    _ -> fail(model, "The selected structure is not a PN counter.")
  }
}

fn enqueue_or_map_increment(
  model: Model,
  replica: Replica,
  key: String,
  amount: Int,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    OrMapReplica(state) ->
      finish_or_map_edit(
        model,
        replica,
        or_map_kernel.increment(state, key, amount),
      )
    _ -> fail(model, "The selected structure is not an OR-map.")
  }
}

fn enqueue_or_map_remove(
  model: Model,
  replica: Replica,
  key: String,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    OrMapReplica(state) ->
      finish_or_map_edit(model, replica, or_map_kernel.remove(state, key))
    _ -> fail(model, "The selected structure is not an OR-map.")
  }
}

fn enqueue_or_map_member(
  model: Model,
  replica: Replica,
  key: String,
  member: String,
  add: Bool,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    OrMapReplica(state) ->
      finish_or_map_edit(model, replica, case add {
        True -> or_map_kernel.add_member(state, key, member)
        False -> or_map_kernel.remove_member(state, key, member)
      })
    _ -> fail(model, "The selected structure is not an OR-map.")
  }
}

fn finish_or_map_edit(
  model: Model,
  replica: Replica,
  outcome: Result(
    #(
      or_map_kernel.OrMapState,
      List(or_map_kernel.OrMapEvent),
      or_map_kernel.OrMapOperation,
      Int,
    ),
    or_map_kernel.KernelError,
  ),
) -> #(Model, Effect(Msg)) {
  case outcome {
    Error(reason) -> fail(model, string_error(reason))
    Ok(#(state, _, operation, message_id)) ->
      enqueue(
        put_replica(model, replica, OrMapReplica(state)),
        replica,
        OrMapOperation(operation),
        Some(message_id),
      )
  }
}

fn enqueue_lww_map(
  model: Model,
  replica: Replica,
  key: String,
  value: Option(String),
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    LwwMapReplica(state) -> {
      let outcome = case value {
        Some(value) ->
          lww_map_kernel.set(state, key, value, model.sequence_number + 101)
        None -> lww_map_kernel.remove(state, key, model.sequence_number + 101)
      }
      case outcome {
        Error(reason) -> fail(model, string_error(reason))
        Ok(#(state, _, operation, message_id)) ->
          enqueue(
            put_replica(model, replica, LwwMapReplica(state)),
            replica,
            LwwMapOperation(operation),
            Some(message_id),
          )
      }
    }
    _ -> fail(model, "The selected structure is not an LWW map.")
  }
}

fn enqueue_lww_register(
  model: Model,
  replica: Replica,
  value: String,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    LwwRegisterReplica(state) ->
      case lww_register_kernel.set(state, value, model.sequence_number + 101) {
        Error(reason) -> fail(model, string_error(reason))
        Ok(#(state, _, operation, message_id)) ->
          enqueue(
            put_replica(model, replica, LwwRegisterReplica(state)),
            replica,
            LwwRegisterOperation(operation),
            Some(message_id),
          )
      }
    _ -> fail(model, "The selected structure is not an LWW register.")
  }
}

fn enqueue_or_map_mv(
  model: Model,
  replica: Replica,
  key: String,
  value: Option(String),
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    OrMapReplica(state) -> {
      let outcome = case value {
        Some(value) -> or_map_kernel.set_mv_register(state, key, value)
        None -> or_map_kernel.remove(state, key)
      }
      finish_or_map_edit(model, replica, outcome)
    }
    _ -> fail(model, "The selected structure is not an OR-map.")
  }
}

fn enqueue_set(
  model: Model,
  replica: Replica,
  element: String,
  action: String,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica), action {
    OrSetReplica(state), "orset-add" -> {
      let #(state, _, operation, message_id) = or_set_kernel.add(state, element)
      enqueue(
        put_replica(model, replica, OrSetReplica(state)),
        replica,
        OrSetOperation(operation),
        Some(message_id),
      )
    }
    OrSetReplica(state), "orset-remove" -> {
      let #(state, _, operation, message_id) =
        or_set_kernel.remove(state, element)
      enqueue(
        put_replica(model, replica, OrSetReplica(state)),
        replica,
        OrSetOperation(operation),
        Some(message_id),
      )
    }
    GSetReplica(state), "gset-add" -> {
      let #(state, _, operation, message_id) = g_set_kernel.add(state, element)
      enqueue(
        put_replica(model, replica, GSetReplica(state)),
        replica,
        GSetOperation(operation),
        Some(message_id),
      )
    }
    TwoPSetReplica(state), "twopset-add" -> {
      let #(state, _, operation, message_id) =
        two_p_set_kernel.add(state, element)
      enqueue(
        put_replica(model, replica, TwoPSetReplica(state)),
        replica,
        TwoPSetOperation(operation),
        Some(message_id),
      )
    }
    TwoPSetReplica(state), "twopset-remove" -> {
      let #(state, _, operation, message_id) =
        two_p_set_kernel.remove(state, element)
      enqueue(
        put_replica(model, replica, TwoPSetReplica(state)),
        replica,
        TwoPSetOperation(operation),
        Some(message_id),
      )
    }
    _, _ ->
      fail(model, "The set command does not match the selected structure.")
  }
}

fn enqueue_claim(
  model: Model,
  replica: Replica,
  key: String,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    ClaimsReplica(state) ->
      case
        claims_kernel.claim_once(
          state,
          key,
          json.string(case replica {
            ClientA -> "Survey"
            ClientB -> "Works"
            ClientC -> "Ecology"
          }),
          model.sequence_number,
        )
      {
        Error(reason) -> fail(model, string_error(reason))
        Ok(claims_kernel.AlreadyClaimed(_)) -> #(model, effect.none())
        Ok(claims_kernel.Submitted(state, operation)) ->
          enqueue(
            put_replica(model, replica, ClaimsReplica(state)),
            replica,
            ClaimOperation(operation),
            None,
          )
      }
    _ -> fail(model, "The selected structure is not a claims map.")
  }
}

fn enqueue_register(
  model: Model,
  replica: Replica,
  key: String,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    RegisterReplica(state) -> {
      let operation =
        register_collection_kernel.write(
          state,
          key,
          json.string(case replica {
            ClientA -> "Survey"
            ClientB -> "Works"
            ClientC -> "Ecology"
          }),
          model.sequence_number,
        )
      enqueue(model, replica, RegisterOperation(operation), None)
    }
    _ -> fail(model, "The selected structure is not a register collection.")
  }
}

fn enqueue_ordered(
  model: Model,
  replica: Replica,
  action: String,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    OrderedReplica(state) -> {
      let operation = case action {
        "add" ->
          ordered_collection_kernel.add(
            state,
            json.string(
              "field-task-" <> int.to_string(model.sequence_number + 1),
            ),
          )
        "acquire" ->
          ordered_collection_kernel.acquire(
            replica_id_string(replica)
            <> int.to_string(model.sequence_number + 1),
          )
        "complete" ->
          ordered_collection_kernel.complete(
            first_ordered_job(state, replica) |> result.unwrap(""),
          )
        _ ->
          ordered_collection_kernel.release(
            first_ordered_job(state, replica) |> result.unwrap(""),
          )
      }
      enqueue(model, replica, OrderedOperation(operation), None)
    }
    _ -> fail(model, "The selected structure is not an ordered collection.")
  }
}

fn first_ordered_job(
  state: ordered_collection_kernel.OrderedState,
  replica: Replica,
) -> Result(String, Nil) {
  ordered_collection_kernel.summary_jobs(state)
  |> list.find(fn(entry) {
    let #(_, ordered_collection_kernel.JobEntry(_, owner)) = entry
    owner == Some(replica_number(replica))
  })
  |> result.map(fn(entry) { entry.0 })
}

fn enqueue_task(
  model: Model,
  replica: Replica,
  task_id: String,
  action: String,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    TaskReplica(state) -> {
      let message_id = model.sequence_number + pending_count(model, replica) + 1
      let outcome = case action {
        "volunteer" -> {
          let #(state, operation, _) =
            task_manager_kernel.volunteer(
              state,
              task_id,
              replica_number(replica),
              message_id,
            )
          #(state, operation)
        }
        "abandon" -> {
          let #(state, operation, _) =
            task_manager_kernel.abandon(
              state,
              task_id,
              replica_number(replica),
              message_id,
            )
          #(state, operation)
        }
        _ ->
          case
            task_manager_kernel.complete(
              state,
              task_id,
              replica_number(replica),
              message_id,
            )
          {
            Ok(#(state, operation)) -> #(state, Some(operation))
            Error(_) -> #(state, None)
          }
      }
      case outcome.1 {
        None -> #(
          put_replica(model, replica, TaskReplica(outcome.0)),
          effect.none(),
        )
        Some(operation) ->
          enqueue(
            put_replica(model, replica, TaskReplica(outcome.0)),
            replica,
            TaskOperation(operation),
            Some(message_id),
          )
      }
    }
    _ -> fail(model, "The selected structure is not a task manager.")
  }
}

fn enqueue_pact(
  model: Model,
  replica: Replica,
  key: String,
  remove: Bool,
) -> #(Model, Effect(Msg)) {
  case replica_state(model, replica) {
    PactReplica(state) -> {
      let operation = case remove {
        True -> pact_map_kernel.delete(state, key, model.sequence_number)
        False ->
          pact_map_kernel.set(
            state,
            key,
            Some(
              json.string(case replica {
                ClientA -> "Survey"
                ClientB -> "Works"
                ClientC -> "Ecology"
              }),
            ),
            model.sequence_number,
          )
      }
      case operation {
        Error(reason) -> fail(model, string_error(reason))
        Ok(operation) -> enqueue(model, replica, PactOperation(operation), None)
      }
    }
    _ -> fail(model, "The selected structure is not a pact map.")
  }
}

fn enqueue(
  model: Model,
  origin: Replica,
  operation: Operation,
  message_id: Option(Int),
) -> #(Model, Effect(Msg)) {
  case model.link_up, origin {
    False, ClientB ->
      queue_pending(
        model,
        PendingOperation(
          origin,
          operation,
          message_id,
          model.generation,
          AllReplicas,
        ),
      )
    False, ClientA | False, ClientC -> {
      let delivered = {
        use model <- result.try(sequence_online_pending(model))
        deliver_online_without_b(model, origin, operation, message_id)
      }
      case delivered {
        Error(reason) -> fail(model, reason)
        Ok(model) ->
          queue_pending(
            model,
            PendingOperation(
              origin,
              operation,
              message_id,
              model.generation,
              ClientBOnly,
            ),
          )
      }
    }
    True, _ -> {
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
      let next = Model(..model, pending:, phase: Delivering)
      #(next, effect.none())
    }
  }
}

fn deliver(model: Model, pending: PendingOperation) -> Result(Model, String) {
  let PendingOperation(origin, operation, message_id, _, scope) = pending
  case scope {
    ReplayAll(sequence_number) -> replay_all(model, operation, sequence_number)
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
  case operation {
    PactOperation(operation) -> deliver_pact_all(model, origin, operation)
    _ -> {
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
          log: [
            LogEntry(sequence, origin, operation_label(operation)),
            ..model.log
          ],
          last_replay: remember_replay(
            model.last_replay,
            operation,
            message_id,
            sequence,
          ),
        ),
      )
    }
  }
}

fn deliver_pact_all(
  model: Model,
  origin: Replica,
  operation: pact_map_kernel.PactMapOperation,
) -> Result(Model, String) {
  let assert PactReplica(alpha) = model.alpha
  let assert PactReplica(beta) = model.beta
  let assert PactReplica(gamma) = model.gamma
  let sequence = model.sequence_number + 1
  let key = case operation {
    pact_map_kernel.Set(key, _, _) | pact_map_kernel.Accept(key) -> key
  }
  let apply = fn(state, self_id) {
    let #(state, _, _) =
      pact_map_kernel.apply_set(state, operation, sequence, [1, 2, 3], self_id)
    [1, 2, 3]
    |> list.fold(Ok(state), fn(outcome, signer) {
      use state <- result.try(outcome)
      pact_map_kernel.apply_accept(state, key, signer, sequence + signer)
      |> result.map(fn(value) { value.0 })
      |> result.map_error(string_error)
    })
  }
  use alpha <- result.try(apply(alpha, 1))
  use beta <- result.try(apply(beta, 2))
  use gamma <- result.try(apply(gamma, 3))
  Ok(
    Model(
      ..model,
      alpha: PactReplica(alpha),
      beta: PactReplica(beta),
      gamma: PactReplica(gamma),
      sequence_number: sequence + 3,
      flows: [
        Flow(sequence * 4, replica_id_string(origin), "seq", "pact operation"),
        ..model.flows
      ],
      log: [LogEntry(sequence, origin, "pact operation"), ..model.log],
    ),
  )
}

fn replay_all(
  model: Model,
  operation: Operation,
  sequence_number: Int,
) -> Result(Model, String) {
  use alpha <- result.try(apply_remote_to(
    model.alpha,
    operation,
    sequence_number,
  ))
  use beta <- result.try(apply_remote_to(model.beta, operation, sequence_number))
  use gamma <- result.try(apply_remote_to(
    model.gamma,
    operation,
    sequence_number,
  ))
  Ok(
    Model(..model, alpha:, beta:, gamma:, log: [
      LogEntry(sequence_number, ClientA, operation_label(operation) <> " again"),
      ..model.log
    ]),
  )
}

fn remember_replay(
  _current: Option(ReplayOperation),
  operation: Operation,
  message_id: Option(Int),
  sequence_number: Int,
) -> Option(ReplayOperation) {
  Some(ReplayOperation(operation, message_id, sequence_number))
}

fn deliver_online_without_b(
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
      last_replay: remember_replay(
        model.last_replay,
        operation,
        message_id,
        sequence,
      ),
    ),
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
    GCounterReplica(state), GCounterOperation(operation), True ->
      g_counter_kernel.ack_local_with_message_id(
        state,
        operation,
        option.unwrap(message_id, -1),
      )
      |> result.map(GCounterReplica)
      |> result.map_error(string_error)
    GCounterReplica(state), GCounterOperation(operation), False -> {
      let #(state, _) = g_counter_kernel.apply_remote(state, operation)
      Ok(GCounterReplica(state))
    }
    PnReplica(state), PnOperation(operation), True ->
      pn_counter_kernel.ack_local_with_message_id(
        state,
        operation,
        option.unwrap(message_id, -1),
      )
      |> result.map(PnReplica)
      |> result.map_error(string_error)
    PnReplica(state), PnOperation(operation), False -> {
      let #(state, _) = pn_counter_kernel.apply_remote(state, operation)
      Ok(PnReplica(state))
    }
    OrMapReplica(state), OrMapOperation(operation), True ->
      or_map_kernel.ack_local_with_message_id(
        state,
        operation,
        option.unwrap(message_id, -1),
      )
      |> result.map(OrMapReplica)
      |> result.map_error(string_error)
    OrMapReplica(state), OrMapOperation(operation), False ->
      or_map_kernel.apply_remote(state, operation)
      |> result.map(fn(value) { OrMapReplica(value.0) })
      |> result.map_error(string_error)
    LwwMapReplica(state), LwwMapOperation(operation), True ->
      lww_map_kernel.ack_local_with_message_id(
        state,
        operation,
        option.unwrap(message_id, -1),
      )
      |> result.map(LwwMapReplica)
      |> result.map_error(string_error)
    LwwMapReplica(state), LwwMapOperation(operation), False ->
      lww_map_kernel.apply_remote(state, operation)
      |> result.map(fn(value) { LwwMapReplica(value.0) })
      |> result.map_error(string_error)
    LwwRegisterReplica(state), LwwRegisterOperation(operation), True ->
      lww_register_kernel.ack_local_with_message_id(
        state,
        operation,
        option.unwrap(message_id, -1),
      )
      |> result.map(LwwRegisterReplica)
      |> result.map_error(string_error)
    LwwRegisterReplica(state), LwwRegisterOperation(operation), False ->
      lww_register_kernel.apply_remote(state, operation)
      |> result.map(fn(value) { LwwRegisterReplica(value.0) })
      |> result.map_error(string_error)
    OrSetReplica(state), OrSetOperation(operation), True ->
      or_set_kernel.ack_local_with_message_id(
        state,
        operation,
        option.unwrap(message_id, -1),
      )
      |> result.map(OrSetReplica)
      |> result.map_error(string_error)
    OrSetReplica(state), OrSetOperation(operation), False -> {
      let #(state, _) = or_set_kernel.apply_remote(state, operation)
      Ok(OrSetReplica(state))
    }
    GSetReplica(state), GSetOperation(operation), True ->
      g_set_kernel.ack_local_with_message_id(
        state,
        operation,
        option.unwrap(message_id, -1),
      )
      |> result.map(GSetReplica)
      |> result.map_error(string_error)
    GSetReplica(state), GSetOperation(operation), False -> {
      let #(state, _) = g_set_kernel.apply_remote(state, operation)
      Ok(GSetReplica(state))
    }
    TwoPSetReplica(state), TwoPSetOperation(operation), True ->
      two_p_set_kernel.ack_local_with_message_id(
        state,
        operation,
        option.unwrap(message_id, -1),
      )
      |> result.map(TwoPSetReplica)
      |> result.map_error(string_error)
    TwoPSetReplica(state), TwoPSetOperation(operation), False -> {
      let #(state, _) = two_p_set_kernel.apply_remote(state, operation)
      Ok(TwoPSetReplica(state))
    }
    ClaimsReplica(state), ClaimOperation(operation), True -> {
      claims_kernel.ack_local(state, operation, sequence)
      |> result.map(fn(value) { ClaimsReplica(value.0) })
      |> result.map_error(string_error)
    }
    ClaimsReplica(state), ClaimOperation(operation), False -> {
      let #(state, _) = claims_kernel.apply_remote(state, operation, sequence)
      Ok(ClaimsReplica(state))
    }
    RegisterReplica(state), RegisterOperation(operation), True -> {
      let #(state, _, _) =
        register_collection_kernel.ack_local(state, operation, sequence)
      Ok(RegisterReplica(state))
    }
    RegisterReplica(state), RegisterOperation(operation), False -> {
      let #(state, _) =
        register_collection_kernel.apply_remote(state, operation, sequence)
      Ok(RegisterReplica(state))
    }
    OrderedReplica(state), OrderedOperation(operation), True -> {
      let #(state, _, _) =
        ordered_collection_kernel.ack_local(
          state,
          operation,
          replica_number(target),
        )
      Ok(OrderedReplica(state))
    }
    OrderedReplica(state), OrderedOperation(operation), False -> {
      let #(state, _) =
        ordered_collection_kernel.apply_remote(
          state,
          operation,
          replica_number(origin),
        )
      Ok(OrderedReplica(state))
    }
    TaskReplica(state), TaskOperation(operation), True ->
      task_manager_kernel.ack_local(
        state,
        operation,
        replica_number(target),
        option.unwrap(message_id, -1),
        [1, 2, 3],
      )
      |> result.map(fn(value) { TaskReplica(value.0) })
      |> result.map_error(string_error)
    TaskReplica(state), TaskOperation(operation), False -> {
      let #(state, _) =
        task_manager_kernel.apply_remote(
          state,
          operation,
          replica_number(origin),
          [1, 2, 3],
        )
      Ok(TaskReplica(state))
    }
    _, _, _ -> Error("The operation does not match the selected structure.")
  }
}

fn apply_remote_to(
  state: ReplicaState,
  operation: Operation,
  sequence: Int,
) -> Result(ReplicaState, String) {
  case state, operation {
    MapReplica(state), MapOperation(operation) -> {
      let #(state, _) = map_kernel.apply_remote(state, operation)
      Ok(MapReplica(state))
    }
    MvRegisterReplica(state), MvRegisterOperation(operation) -> {
      let #(state, _) = mv_register_kernel.apply_remote(state, operation)
      Ok(MvRegisterReplica(state))
    }
    GCounterReplica(state), GCounterOperation(operation) -> {
      let #(state, _) = g_counter_kernel.apply_remote(state, operation)
      Ok(GCounterReplica(state))
    }
    PnReplica(state), PnOperation(operation) -> {
      let #(state, _) = pn_counter_kernel.apply_remote(state, operation)
      Ok(PnReplica(state))
    }
    OrMapReplica(state), OrMapOperation(operation) ->
      or_map_kernel.apply_remote(state, operation)
      |> result.map(fn(value) { OrMapReplica(value.0) })
      |> result.map_error(string_error)
    LwwMapReplica(state), LwwMapOperation(operation) ->
      lww_map_kernel.apply_remote(state, operation)
      |> result.map(fn(value) { LwwMapReplica(value.0) })
      |> result.map_error(string_error)
    LwwRegisterReplica(state), LwwRegisterOperation(operation) ->
      lww_register_kernel.apply_remote(state, operation)
      |> result.map(fn(value) { LwwRegisterReplica(value.0) })
      |> result.map_error(string_error)
    OrSetReplica(state), OrSetOperation(operation) -> {
      let #(state, _) = or_set_kernel.apply_remote(state, operation)
      Ok(OrSetReplica(state))
    }
    GSetReplica(state), GSetOperation(operation) -> {
      let #(state, _) = g_set_kernel.apply_remote(state, operation)
      Ok(GSetReplica(state))
    }
    TwoPSetReplica(state), TwoPSetOperation(operation) -> {
      let #(state, _) = two_p_set_kernel.apply_remote(state, operation)
      Ok(TwoPSetReplica(state))
    }
    ClaimsReplica(state), ClaimOperation(operation) -> {
      let #(state, _) = claims_kernel.apply_remote(state, operation, sequence)
      Ok(ClaimsReplica(state))
    }
    RegisterReplica(state), RegisterOperation(operation) -> {
      let #(state, _) =
        register_collection_kernel.apply_remote(state, operation, sequence)
      Ok(RegisterReplica(state))
    }
    OrderedReplica(state), OrderedOperation(operation) -> {
      let #(state, _) =
        ordered_collection_kernel.apply_remote(state, operation, 1)
      Ok(OrderedReplica(state))
    }
    TaskReplica(state), TaskOperation(operation) -> {
      let #(state, _) =
        task_manager_kernel.apply_remote(state, operation, 1, [1, 2, 3])
      Ok(TaskReplica(state))
    }
    _, _ -> Error("The replay operation does not match the selected structure.")
  }
}

fn fail(model: Model, reason: String) -> #(Model, Effect(Msg)) {
  #(Model(..model, phase: Failed, visible_error: Some(reason)), effect.none())
}

fn delivery_delay(model: Model) -> Int {
  case model.jitter {
    True -> int.clamp(model.latency_ms + sample_jitter(100), 0, 2100)
    False -> model.latency_ms
  }
}

fn pace_milliseconds(value: String) -> Int {
  case value {
    "0.25" -> 2400
    "0.5" -> 1200
    "0.75" -> 800
    "1.25" -> 480
    "1.5" -> 400
    "1.75" -> 343
    "2" -> 300
    _ -> 600
  }
}

fn draft(model: Model, replica: Replica) -> String {
  case replica {
    ClientA -> model.draft_a
    ClientB -> model.draft_b
    ClientC -> model.draft_c
  }
}

fn put_draft(model: Model, replica: Replica, value: String) -> Model {
  case replica {
    ClientA -> Model(..model, draft_a: value)
    ClientB -> Model(..model, draft_b: value)
    ClientC -> Model(..model, draft_c: value)
  }
}

fn put_key_draft(model: Model, replica: Replica, value: String) -> Model {
  case replica {
    ClientA -> Model(..model, key_a: value)
    ClientB -> Model(..model, key_b: value)
    ClientC -> Model(..model, key_c: value)
  }
}

fn sequence_online_pending(model: Model) -> Result(Model, String) {
  let queued = Model(..model, pending: [], queued_for_b: 0)
  list.try_fold(model.pending, queued, fn(current, pending) {
    case pending.scope, pending.origin {
      AllReplicas, ClientA | AllReplicas, ClientC -> {
        use delivered <- result.try(deliver_online_without_b(
          current,
          pending.origin,
          pending.operation,
          pending.message_id,
        ))
        Ok(
          queue_pending(
            delivered,
            PendingOperation(..pending, scope: ClientBOnly),
          ).0,
        )
      }
      _, _ -> Ok(queue_pending(current, pending).0)
    }
  })
}

fn restore_link(model: Model) -> #(Model, Effect(Msg)) {
  case model.selected, model.beta {
    MvRegister, MvRegisterReplica(beta) ->
      case rebase_mv_pending(model, beta) {
        Error(reason) -> fail(model, reason)
        Ok(#(beta, pending)) -> #(
          Model(
            ..model,
            beta: MvRegisterReplica(beta),
            pending: pending,
            link_up: True,
            queued_for_b: 0,
            phase: case pending {
              [] -> Ready
              [_, ..] -> Delivering
            },
          ),
          effect.none(),
        )
      }
    _, _ -> #(
      Model(
        ..model,
        pending: reconnect_pending(model.pending),
        link_up: True,
        queued_for_b: 0,
        phase: case model.pending {
          [] -> Ready
          [_, ..] -> Delivering
        },
      ),
      effect.none(),
    )
  }
}

fn reconnect_pending(
  pending: List(PendingOperation),
) -> List(PendingOperation) {
  let catch_up =
    list.filter(pending, fn(item) {
      let PendingOperation(_, _, _, _, scope) = item
      scope == ClientBOnly
    })
  let submitted =
    list.filter(pending, fn(item) {
      let PendingOperation(_, _, _, _, scope) = item
      scope != ClientBOnly
    })
  list.append(catch_up, submitted)
}

fn rebase_mv_pending(
  model: Model,
  beta: mv_register_kernel.MvRegisterState,
) -> Result(
  #(mv_register_kernel.MvRegisterState, List(PendingOperation)),
  String,
) {
  let catch_up =
    list.filter(model.pending, fn(pending) {
      let PendingOperation(_, _, _, _, scope) = pending
      scope == ClientBOnly
    })
  let local =
    list.filter(model.pending, fn(pending) {
      let PendingOperation(origin, operation, _, _, scope) = pending
      origin == ClientB
      && scope == AllReplicas
      && case operation {
        MvRegisterOperation(_) -> True
        _ -> False
      }
    })
  let other =
    list.filter(model.pending, fn(pending) {
      let PendingOperation(origin, operation, _, _, scope) = pending
      scope != ClientBOnly
      && !{
        origin == ClientB
        && scope == AllReplicas
        && case operation {
          MvRegisterOperation(_) -> True
          _ -> False
        }
      }
    })
  use rolled_back <- result.try(
    local
    |> list.reverse
    |> list.fold(Ok(beta), fn(outcome, pending) {
      use state <- result.try(outcome)
      let PendingOperation(_, operation, message_id, _, _) = pending
      case operation, message_id {
        MvRegisterOperation(operation), Some(message_id) ->
          mv_register_kernel.rollback(state, operation, message_id)
          |> result.map(fn(value) { value.0 })
          |> result.map_error(string_error)
        _, _ -> Error("Cannot rebase an MV-register write without its ID.")
      }
    }),
  )
  use caught_up <- result.try(
    list.fold(catch_up, Ok(rolled_back), fn(outcome, pending) {
      use state <- result.try(outcome)
      let PendingOperation(origin, operation, message_id, _, _) = pending
      deliver_to(
        MvRegisterReplica(state),
        ClientB,
        origin,
        operation,
        message_id,
        model.sequence_number,
      )
      |> result.map(fn(replica) {
        let assert MvRegisterReplica(state) = replica
        state
      })
    }),
  )
  local
  |> list.fold(Ok(#(caught_up, other)), fn(outcome, pending) {
    use pair <- result.try(outcome)
    let PendingOperation(_, operation, _, _, _) = pending
    let assert MvRegisterOperation(mv_register_kernel.Set(value, _)) = operation
    let #(state, _, operation, message_id) =
      mv_register_kernel.set(pair.0, value)
    Ok(#(
      state,
      list.append(pair.1, [
        PendingOperation(
          ClientB,
          MvRegisterOperation(operation),
          Some(message_id),
          model.generation,
          AllReplicas,
        ),
      ]),
    ))
  })
}

fn select_structure(
  model: Model,
  selected: Structure,
) -> #(Model, Effect(Msg)) {
  case selected == model.selected {
    True -> #(model, effect.none())
    False -> {
      let generation = model.generation + 1
      let instances = save_instance(model)
      let restored =
        list.find(instances, fn(instance) { instance.structure == selected })
      let next = case restored {
        Ok(Instance(
          _,
          alpha,
          beta,
          gamma,
          pending,
          sequence,
          flows,
          log,
          replay,
        )) ->
          Model(
            ..ready_model(selected),
            alpha:,
            beta:,
            gamma:,
            pending: list.map(pending, fn(item) {
              let PendingOperation(origin, operation, message_id, _, scope) =
                item
              PendingOperation(origin, operation, message_id, generation, scope)
            }),
            sequence_number: sequence,
            flows:,
            log:,
            last_replay: replay,
          )
        Error(Nil) -> ready_model(selected)
      }
      let next =
        Model(
          ..next,
          generation:,
          latency_ms: model.latency_ms,
          jitter: model.jitter,
          link_up: model.link_up,
          open_panel: model.open_panel,
          or_map_set_mode: model.or_map_set_mode,
          draft_a: model.draft_a,
          draft_b: model.draft_b,
          draft_c: model.draft_c,
          key_a: model.key_a,
          key_b: model.key_b,
          key_c: model.key_c,
          playback_ms: model.playback_ms,
          field_notes: model.field_notes,
          instances:,
          queued_for_b: case model.link_up {
            True -> 0
            False -> list.length(next.pending)
          },
          phase: case next.pending {
            [] -> Ready
            [_, ..] -> Delivering
          },
        )
      #(next, effect.none())
    }
  }
}

fn save_instance(model: Model) -> List(Instance) {
  let saved =
    Instance(
      model.selected,
      model.alpha,
      model.beta,
      model.gamma,
      model.pending,
      model.sequence_number,
      model.flows,
      model.log,
      model.last_replay,
    )
  [
    saved,
    ..list.filter(model.instances, fn(instance) {
      instance.structure != model.selected
    })
  ]
}

fn replica_number(replica: Replica) -> Int {
  case replica {
    ClientA -> 1
    ClientB -> 2
    ClientC -> 3
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
    GCounter -> shared_g_counter_replicas()
    PnCounter -> shared_pn_replicas()
    OrMap | OrMapMvRegister -> shared_or_map_replicas(structure)
    OrSet -> shared_or_set_replicas()
    _ -> #(
      new_replica(structure, ClientA),
      new_replica(structure, ClientB),
      new_replica(structure, ClientC),
    )
  }
}

fn or_map_replicas(
  mode: or_map_kernel.OrMapMode,
) -> #(ReplicaState, ReplicaState, ReplicaState) {
  let seed = or_map_kernel.new(replica_id.new("survey-ormap"), mode)
  shared_or_map_summary(or_map_kernel.summary(seed) |> json.to_string)
}

fn shared_g_counter_replicas() {
  let assert Ok(#(seed, _, _)) =
    g_counter_kernel.p2p_increment(
      g_counter_kernel.new(replica_id.new("survey-gcounter")),
      18,
    )
  let summary = g_counter_kernel.summary(seed) |> json.to_string
  let make = fn(replica) {
    let assert Ok(state) =
      g_counter_kernel.from_summary(summary, local_replica_id(replica))
    GCounterReplica(state)
  }
  #(make(ClientA), make(ClientB), make(ClientC))
}

fn shared_pn_replicas() {
  let #(seed, _, _) =
    pn_counter_kernel.p2p_update(
      pn_counter_kernel.new(replica_id.new("survey-pn")),
      44,
    )
  let summary = pn_counter_kernel.summary(seed) |> json.to_string
  let make = fn(replica) {
    let assert Ok(state) =
      pn_counter_kernel.from_summary(summary, local_replica_id(replica))
    PnReplica(state)
  }
  #(make(ClientA), make(ClientB), make(ClientC))
}

fn shared_or_map_replicas(structure: Structure) {
  let id = replica_id.new("survey-ormap")
  let seed = case structure {
    OrMapMvRegister -> {
      let assert Ok(#(state, _, _)) =
        or_map_kernel.p2p_set_mv_register(
          or_map_kernel.new(id, or_map_kernel.MvRegisterMode),
          "gate-mode",
          "surveyed",
        )
      state
    }
    _ -> {
      let assert Ok(#(state, _, _)) =
        or_map_kernel.p2p_increment(
          or_map_kernel.new(id, or_map_kernel.TallyMode),
          "spoil-north",
          18,
        )
      let assert Ok(#(state, _, _)) =
        or_map_kernel.p2p_increment(state, "borrow-pit-7", -6)
      let assert Ok(#(state, _, _)) =
        or_map_kernel.p2p_increment(state, "wash-fill", 12)
      state
    }
  }
  shared_or_map_summary(or_map_kernel.summary(seed) |> json.to_string)
}

fn shared_or_map_summary(summary: String) {
  let make = fn(replica) {
    let assert Ok(state) =
      or_map_kernel.from_summary(summary, local_replica_id(replica))
    OrMapReplica(state)
  }
  #(make(ClientA), make(ClientB), make(ClientC))
}

fn shared_or_set_replicas() {
  let #(seed, _, _) =
    or_set_kernel.p2p_add(
      or_set_kernel.new(replica_id.new("survey-orset")),
      "north-stake",
    )
  let #(seed, _, _) = or_set_kernel.p2p_add(seed, "sluice-tag")
  let summary = or_set_kernel.summary(seed) |> json.to_string
  let make = fn(replica) {
    let assert Ok(state) =
      or_set_kernel.from_summary(summary, local_replica_id(replica))
    OrSetReplica(state)
  }
  #(make(ClientA), make(ClientB), make(ClientC))
}

fn local_replica_id(replica: Replica) {
  replica_id.new("client-" <> replica_id_string(replica))
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
    GCounter -> {
      let assert Ok(#(state, _, _)) =
        g_counter_kernel.p2p_increment(g_counter_kernel.new(id), 18)
      GCounterReplica(state)
    }
    PnCounter -> {
      let #(state, _, _) =
        pn_counter_kernel.p2p_update(pn_counter_kernel.new(id), 44)
      PnReplica(state)
    }
    OrMap | OrMapMvRegister ->
      case structure {
        OrMapMvRegister -> {
          let state = or_map_kernel.new(id, or_map_kernel.MvRegisterMode)
          let assert Ok(#(state, _, _)) =
            or_map_kernel.p2p_set_mv_register(state, "gate-mode", "surveyed")
          OrMapReplica(state)
        }
        _ -> {
          let state = or_map_kernel.new(id, or_map_kernel.TallyMode)
          let assert Ok(#(state, _, _)) =
            or_map_kernel.p2p_increment(state, "spoil-north", 18)
          let assert Ok(#(state, _, _)) =
            or_map_kernel.p2p_increment(state, "borrow-pit-7", -6)
          let assert Ok(#(state, _, _)) =
            or_map_kernel.p2p_increment(state, "wash-fill", 12)
          OrMapReplica(state)
        }
      }
    LwwMap -> {
      let assert Ok(#(state, _, _)) =
        lww_map_kernel.p2p_set(
          lww_map_kernel.new(id),
          "gate-mode",
          "surveyed",
          100,
        )
      LwwMapReplica(state)
    }
    LwwRegister -> {
      let assert Ok(#(state, _, _)) =
        lww_register_kernel.p2p_set(
          lww_register_kernel.new(id),
          "Survey datum",
          100,
        )
      LwwRegisterReplica(state)
    }
    MvRegister -> {
      let #(state, _, _) =
        mv_register_kernel.p2p_set(mv_register_kernel.new(id), "Survey datum")
      MvRegisterReplica(state)
    }
    OrSet -> {
      let #(state, _, _) =
        or_set_kernel.p2p_add(or_set_kernel.new(id), "north-stake")
      let #(state, _, _) = or_set_kernel.p2p_add(state, "sluice-tag")
      OrSetReplica(state)
    }
    GSet -> {
      let #(state, _, _) = g_set_kernel.p2p_add(g_set_kernel.new(), "BM-17")
      GSetReplica(state)
    }
    TwoPSet -> {
      let #(state, _, _) =
        two_p_set_kernel.p2p_add(two_p_set_kernel.new(), "stake-3")
      let #(state, _, _) = two_p_set_kernel.p2p_add(state, "silt-flag")
      let #(state, _, _) = two_p_set_kernel.p2p_remove(state, "silt-flag")
      TwoPSetReplica(state)
    }
    Claims ->
      ClaimsReplica(
        claims_kernel.from_summary([
          #("pump-house", json.string("Survey"), 0),
        ]),
      )
    RegisterCollection -> {
      let #(state, _) =
        register_collection_kernel.write_detached(
          register_collection_kernel.new(),
          "north-bench",
          json.string("Survey"),
        )
      RegisterReplica(state)
    }
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
    PactMap ->
      PactReplica(
        pact_map_kernel.from_summary([
          #(
            "datum-grid",
            pact_map_kernel.Pact(
              Some(pact_map_kernel.Accepted(
                Some(json.string("Survey datum")),
                0,
              )),
              None,
            ),
          ),
        ]),
      )
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
    MapReplica(state) -> {
      use value <- result.try(
        map_kernel.get(state, key)
        |> result.replace_error("Unknown map key."),
      )
      json.parse(json.to_string(value), decode.int)
      |> result.map_error(fn(_) { "Map value is not an integer." })
    }
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

fn project_model(model: Model) -> Result(Model, String) {
  let expected = fn(replica, state) {
    let valid = case model.selected, state {
      Map, MapReplica(_) -> True
      Counter, CounterReplica(_) -> True
      GCounter, GCounterReplica(_) -> True
      PnCounter, PnReplica(_) -> True
      OrMap, OrMapReplica(_) | OrMapMvRegister, OrMapReplica(_) -> True
      LwwMap, LwwMapReplica(_) -> True
      LwwRegister, LwwRegisterReplica(_) -> True
      MvRegister, MvRegisterReplica(_) -> True
      OrSet, OrSetReplica(_) -> True
      GSet, GSetReplica(_) -> True
      TwoPSet, TwoPSetReplica(_) -> True
      Claims, ClaimsReplica(_) -> True
      RegisterCollection, RegisterReplica(_) -> True
      OrderedCollection, OrderedReplica(_) -> True
      TaskManager, TaskReplica(_) -> True
      PactMap, PactReplica(_) -> True
      _, _ -> False
    }
    case valid {
      True -> Ok(Nil)
      False ->
        Error(
          "Cannot project "
          <> replica
          <> " as "
          <> structure_name(model.selected)
          <> ".",
        )
    }
  }
  use _ <- result.try(expected("Client A", model.alpha))
  use _ <- result.try(expected("Client B", model.beta))
  use _ <- result.try(expected("Client C", model.gamma))
  case model.selected {
    Map -> {
      use _ <- result.try(validate_map_projection(model.alpha))
      use _ <- result.try(validate_map_projection(model.beta))
      use _ <- result.try(validate_map_projection(model.gamma))
      Ok(model)
    }
    _ -> Ok(model)
  }
}

fn validate_map_projection(state: ReplicaState) -> Result(Nil, String) {
  ["mill-race", "kettle-run", "low-ford"]
  |> list.fold(Ok(Nil), fn(outcome, key) {
    use _ <- result.try(outcome)
    use _ <- result.try(map_value(state, key))
    Ok(Nil)
  })
}

fn structure_name(structure: Structure) -> String {
  case structure {
    Map -> "a shared map"
    Counter -> "a shared counter"
    GCounter -> "a G-counter"
    PnCounter -> "a PN-counter"
    OrMap | OrMapMvRegister -> "an OR-map"
    LwwMap -> "an LWW map"
    LwwRegister -> "an LWW register"
    MvRegister -> "an MV register"
    OrSet -> "an OR-set"
    GSet -> "a G-set"
    TwoPSet -> "a 2P-set"
    Claims -> "a claims map"
    RegisterCollection -> "a register collection"
    OrderedCollection -> "an ordered collection"
    TaskManager -> "a task manager"
    PactMap -> "a pact map"
  }
}

pub fn counter_value(model: Model, replica: Replica) -> Int {
  case replica_state(model, replica) {
    CounterReplica(state) -> state.value
    _ -> 0
  }
}

pub fn g_counter_value(model: Model, replica: Replica) -> Int {
  case replica_state(model, replica) {
    GCounterReplica(state) -> g_counter_kernel.value(state)
    _ -> 0
  }
}

pub fn pn_value(model: Model, replica: Replica) -> Int {
  case replica_state(model, replica) {
    PnReplica(state) -> pn_counter_kernel.value(state)
    _ -> 0
  }
}

pub fn or_map_value(model: Model, replica: Replica, key: String) -> String {
  case replica_state(model, replica) {
    OrMapReplica(state) ->
      case or_map_kernel.get(state, key) {
        Ok(or_map_kernel.Tally(value)) -> int.to_string(value)
        Ok(or_map_kernel.Register(value)) -> value
        Ok(or_map_kernel.SetMembers(values))
        | Ok(or_map_kernel.MvRegister(values)) -> string.inspect(values)
        Error(Nil) -> "missing"
      }
    _ -> "missing"
  }
}

pub fn or_map_entries(
  model: Model,
  replica: Replica,
  sequenced: Bool,
) -> String {
  case replica_state(model, replica) {
    OrMapReplica(state) ->
      case sequenced {
        True -> or_map_kernel.sequenced_entries(state)
        False -> or_map_kernel.entries(state)
      }
      |> string.inspect
    _ -> "[]"
  }
}

pub fn lww_map_entries(
  model: Model,
  replica: Replica,
  sequenced: Bool,
) -> String {
  case replica_state(model, replica) {
    LwwMapReplica(state) ->
      case sequenced {
        True -> lww_map_kernel.sequenced_entries(state)
        False -> lww_map_kernel.entries(state)
      }
      |> string.inspect
    _ -> "[]"
  }
}

pub fn lww_register_value(
  model: Model,
  replica: Replica,
  sequenced: Bool,
) -> String {
  case replica_state(model, replica) {
    LwwRegisterReplica(state) ->
      case sequenced {
        True -> lww_register_kernel.sequenced_value(state)
        False -> lww_register_kernel.value(state)
      }
    _ -> ""
  }
}

pub fn set_contains(model: Model, replica: Replica, element: String) -> Bool {
  case replica_state(model, replica) {
    OrSetReplica(state) -> or_set_kernel.contains(state, element)
    GSetReplica(state) -> g_set_kernel.contains(state, element)
    TwoPSetReplica(state) -> two_p_set_kernel.contains(state, element)
    _ -> False
  }
}

pub fn claim_value(model: Model, replica: Replica, key: String) -> String {
  case replica_state(model, replica) {
    ClaimsReplica(state) ->
      claims_kernel.get(state, key)
      |> result.map(json_string)
      |> result.unwrap("—")
    _ -> "—"
  }
}

pub fn register_value(
  model: Model,
  replica: Replica,
  key: String,
  atomic: Bool,
) -> String {
  case replica_state(model, replica) {
    RegisterReplica(state) ->
      register_collection_kernel.read(state, key, case atomic {
        True -> register_collection_kernel.Atomic
        False -> register_collection_kernel.Lww
      })
      |> result.map(json_string)
      |> result.unwrap("—")
    _ -> "—"
  }
}

pub fn register_versions(
  model: Model,
  replica: Replica,
  key: String,
) -> String {
  case replica_state(model, replica) {
    RegisterReplica(state) ->
      register_collection_kernel.read_versions(state, key)
      |> result.map(fn(values) { list.map(values, json_string) })
      |> result.map(string.inspect)
      |> result.unwrap("[]")
    _ -> "[]"
  }
}

pub fn ordered_queue(model: Model, replica: Replica) -> String {
  case replica_state(model, replica) {
    OrderedReplica(state) ->
      ordered_collection_kernel.summary_queue(state)
      |> list.map(json_string)
      |> fn(values) {
        case values {
          [] -> "empty"
          _ -> string.join(values, ", ")
        }
      }
    _ -> "empty"
  }
}

pub fn ordered_jobs(model: Model, replica: Replica) -> String {
  case replica_state(model, replica) {
    OrderedReplica(state) ->
      ordered_collection_kernel.summary_jobs(state)
      |> list.map(fn(entry) { entry.0 <> ": " <> json_string(entry.1.value) })
      |> fn(values) {
        case values {
          [] -> "none"
          _ -> string.join(values, ", ")
        }
      }
    _ -> "none"
  }
}

pub fn task_assignee(
  model: Model,
  replica: Replica,
  task_id: String,
) -> String {
  case replica_state(model, replica) {
    TaskReplica(state) ->
      [ClientA, ClientB, ClientC]
      |> list.find(fn(candidate) {
        task_manager_kernel.assigned(
          state,
          task_id,
          replica_number(candidate),
          True,
        )
      })
      |> result.map(replica_id_string)
      |> result.unwrap("—")
    _ -> "—"
  }
}

pub fn task_waiters(model: Model, replica: Replica, task_id: String) -> String {
  case replica_state(model, replica) {
    TaskReplica(state) ->
      task_manager_kernel.summary_queues(state)
      |> list.find(fn(entry) { entry.0 == task_id })
      |> result.map(fn(entry) {
        entry.1 |> list.map(int.to_string) |> string.join(", ")
      })
      |> result.unwrap("empty")
    _ -> "empty"
  }
}

pub fn pact_value(
  model: Model,
  replica: Replica,
  key: String,
  pending: Bool,
) -> String {
  case replica_state(model, replica) {
    PactReplica(state) ->
      case pending {
        True ->
          pact_map_kernel.get_pending(state, key)
          |> result.map(fn(value) {
            case value {
              Some(value) -> json_string(value)
              None -> "delete"
            }
          })
        False -> pact_map_kernel.get(state, key) |> result.map(json_string)
      }
      |> result.unwrap("—")
    _ -> "—"
  }
}

fn json_string(value: json.Json) -> String {
  json.parse(json.to_string(value), decode.string)
  |> result.unwrap(json.to_string(value))
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
    MvRegisterOperation(mv_register_kernel.Set(value, _)) ->
      "MV-register write " <> value
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

fn signed(value: Int) -> String {
  case value >= 0 {
    True -> "+" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

@external(javascript, "../client/structure_demo_ffi.mjs", "sampleJitter")
fn sample_jitter(maximum: Int) -> Int

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

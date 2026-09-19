import gleam/option.{type Option}
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
import watershed/wire

pub type Structure {
  Map
  Counter
  GCounter
  PnCounter
  OrMap
  OrMapMvRegister
  LwwMap
  LwwRegister
  MvRegister
  OrSet
  GSet
  TwoPSet
  Claims
  RegisterCollection
  OrderedCollection
  TaskManager
  PactMap
}

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

pub type ReplicaState {
  MapReplica(map_kernel.MapState)
  CounterReplica(counter_kernel.CounterState)
  GCounterReplica(g_counter_kernel.GCounterState)
  PnReplica(pn_counter_kernel.PnCounterState)
  OrMapReplica(or_map_kernel.OrMapState)
  LwwMapReplica(lww_map_kernel.LwwMapState)
  LwwRegisterReplica(lww_register_kernel.LwwRegisterState)
  MvRegisterReplica(mv_register_kernel.MvRegisterState)
  OrSetReplica(or_set_kernel.OrSetState)
  GSetReplica(g_set_kernel.GSetState)
  TwoPSetReplica(two_p_set_kernel.TwoPSetState)
  ClaimsReplica(claims_kernel.ClaimsState)
  RegisterReplica(register_collection_kernel.RegisterState)
  OrderedReplica(ordered_collection_kernel.OrderedState)
  TaskReplica(task_manager_kernel.TaskManagerState)
  PactReplica(pact_map_kernel.PactMapState)
}

pub type Operation {
  MapOperation(map_kernel.MapOperation)
  CounterOperation(wire.OutboundOperation)
  GCounterOperation(g_counter_kernel.GCounterOperation)
  PnOperation(pn_counter_kernel.PnCounterOperation)
  OrMapOperation(or_map_kernel.OrMapOperation)
  LwwMapOperation(lww_map_kernel.LwwMapOperation)
  LwwRegisterOperation(lww_register_kernel.LwwRegisterOperation)
  MvRegisterOperation(mv_register_kernel.MvRegisterOperation)
  OrSetOperation(or_set_kernel.OrSetOperation)
  GSetOperation(g_set_kernel.GSetOperation)
  TwoPSetOperation(two_p_set_kernel.TwoPSetOperation)
  ClaimOperation(claims_kernel.ClaimOperation)
  RegisterOperation(register_collection_kernel.WriteOperation)
  OrderedOperation(ordered_collection_kernel.OrderedOperation)
  TaskOperation(task_manager_kernel.TaskManagerOperation)
  PactOperation(pact_map_kernel.PactMapOperation)
}

pub type DeliveryScope {
  AllReplicas
  ClientBOnly
  ReplayAll(sequence_number: Int)
}

pub type PendingOperation {
  PendingOperation(
    origin: Replica,
    operation: Operation,
    message_id: Option(Int),
    generation: Int,
    scope: DeliveryScope,
  )
}

pub type Flow {
  Flow(id: Int, from: String, to: String, label: String)
}

pub type ReplayOperation {
  ReplayOperation(
    operation: Operation,
    message_id: Option(Int),
    sequence_number: Int,
  )
}

pub type Instance {
  Instance(
    structure: Structure,
    alpha: ReplicaState,
    beta: ReplicaState,
    gamma: ReplicaState,
    pending: List(PendingOperation),
    sequence_number: Int,
    flows: List(Flow),
    log: List(LogEntry),
    last_replay: Option(ReplayOperation),
  )
}

pub type LogEntry {
  LogEntry(sequence_number: Int, author: Replica, label: String)
}

pub type Model {
  Model(
    selected: Structure,
    alpha: ReplicaState,
    beta: ReplicaState,
    gamma: ReplicaState,
    pending: List(PendingOperation),
    sequence_number: Int,
    flows: List(Flow),
    latency_ms: Int,
    jitter: Bool,
    link_up: Bool,
    log: List(LogEntry),
    generation: Int,
    visible_error: Option(String),
    phase: Phase,
    queued_for_b: Int,
    open_panel: Option(Structure),
    or_map_set_mode: Bool,
    draft_a: String,
    draft_b: String,
    draft_c: String,
    key_a: String,
    key_b: String,
    key_c: String,
    playback_ms: Int,
    field_notes: Bool,
    last_replay: Option(ReplayOperation),
    instances: List(Instance),
    deferred_work: List(fn(Model) -> Result(#(Model, Model), String)),
    work_running: Bool,
    // Keep ownership until deferred delivery completes, including queue time.
    delivery_armed: Bool,
  )
}

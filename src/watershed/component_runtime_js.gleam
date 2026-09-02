//// Stateful JavaScript runtime for persisted component workspaces.
////
//// The runtime observes workspace topology, starts prepared instances, and
//// executes typed port deliveries. It owns no view framework. A browser host
//// reads running values and turns the change callback into its own message.

@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/int
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/result
@target(javascript)
import gleam/string
@target(javascript)
import watershed
@target(javascript)
import watershed/component
@target(javascript)
import watershed/component_runtime
@target(javascript)
import watershed/dispatch
@target(javascript)
import watershed/map_kernel
@target(javascript)
import watershed/port
@target(javascript)
import watershed/port_graph
@target(javascript)
import watershed/schema.{type ChildField, child_key}
@target(javascript)
import watershed/transport_js.{type Cell, type Scheduler}
@target(javascript)
import watershed/workspace
@target(javascript)
import watershed/workspace_js

@target(javascript)
/// A runtime or component lifecycle failure.
pub type RuntimeError {
  InstanceNotReady(instance_id: String)
  ActionFailed(instance_id: String, reason: String)
  ComponentFailed(instance_id: String, reason: component.ComponentError)
  PreparationFailed(instance_id: String, reason: workspace.PreparationError)
  CatalogChanged(instance_id: String, reason: component.LookupError)
  WorkspaceFailed(reason: workspace_js.WorkspaceError)
}

@target(javascript)
/// The local lifecycle state of one stored instance.
pub type LifecycleState {
  Loading(entry: workspace.ManifestEntry, reason: String)
  Starting(entry: workspace.ManifestEntry)
  Ready(entry: workspace.ManifestEntry)
  Unavailable(entry: workspace.ManifestEntry, reason: component.LookupError)
  Failed(instance_id: String, reason: RuntimeError)
}

@target(javascript)
/// A reason one output or delivery could not run.
pub type DispatchFailure {
  PlanningFailed(reason: dispatch.DispatchError)
  SourceOutputRejected(instance_id: String, reason: component.ComponentError)
  TargetNotReady(instance_id: String)
  TargetInputRejected(instance_id: String, reason: component.ComponentError)
}

@target(javascript)
/// One observable stage of an origin-side dispatch.
pub type DispatchReport {
  Triggered(trace_id: String, source: port_graph.PortRef)
  LocalDelivered(trace_id: String, edge_id: String, target: port_graph.PortRef)
  MutationSubmitted(
    trace_id: String,
    edge_id: String,
    target: port_graph.PortRef,
  )
  DispatchFailed(
    trace_id: String,
    edge_id: Option(String),
    reason: DispatchFailure,
  )
  RuntimeFailed(reason: RuntimeError)
}

@target(javascript)
type RunningInstance(context, running) {
  RunningInstance(
    entry: workspace.ManifestEntry,
    identity: component_runtime.InstanceIdentity,
    descriptor: component.Descriptor(context, running),
    running: running,
  )
}

@target(javascript)
type PendingStart {
  PendingStart(
    entry: workspace.ManifestEntry,
    identity: component_runtime.InstanceIdentity,
    generation: Int,
  )
}

@target(javascript)
type State(root, context, running) {
  State(
    workspace: Option(workspace_js.Workspace(root)),
    workspace_subscription: Option(workspace_js.Subscription),
    instances: Dict(String, RunningInstance(context, running)),
    pending: Dict(String, PendingStart),
    failed: Dict(String, component_runtime.InstanceIdentity),
    lifecycle: Dict(String, LifecycleState),
    snapshot: Option(workspace.Snapshot),
    next_generation: Int,
    next_trace: Int,
    workspace_generation: Int,
    reconcile_armed: Bool,
    notify_armed: Bool,
    stopped: Bool,
  )
}

@target(javascript)
/// A running component workspace.
pub opaque type Runtime(root, context, running) {
  Runtime(
    document: watershed.Document(root),
    root: watershed.TypedMap(root),
    field: ChildField(root, workspace.WorkspaceSchema),
    catalog: component.Catalog(context, running),
    context_for: fn(workspace.ManifestEntry, watershed.SharedMap, fn() -> Nil) ->
      context,
    scheduler: Scheduler,
    on_change: fn() -> Nil,
    on_report: fn(DispatchReport) -> Nil,
    state: Cell(State(root, context, running)),
    root_subscription: Option(watershed.SubscriptionToken),
  )
}

@target(javascript)
/// Start observing and running one ensured workspace.
pub fn start(
  document document: watershed.Document(root),
  root root: watershed.TypedMap(root),
  field field: ChildField(root, workspace.WorkspaceSchema),
  store _store: workspace_js.Workspace(root),
  catalog catalog: component.Catalog(context, running),
  context_for context_for: fn(
    workspace.ManifestEntry,
    watershed.SharedMap,
    fn() -> Nil,
  ) -> context,
  scheduler scheduler: Scheduler,
  on_change on_change: fn() -> Nil,
  on_report on_report: fn(DispatchReport) -> Nil,
) -> Runtime(root, context, running) {
  let state =
    transport_js.new_cell(State(
      workspace: None,
      workspace_subscription: None,
      instances: dict.new(),
      pending: dict.new(),
      failed: dict.new(),
      lifecycle: dict.new(),
      snapshot: None,
      next_generation: 0,
      next_trace: 0,
      workspace_generation: 0,
      reconcile_armed: False,
      notify_armed: False,
      stopped: False,
    ))
  let runtime =
    Runtime(
      document: document,
      root: root,
      field: field,
      catalog: catalog,
      context_for: context_for,
      scheduler: scheduler,
      on_change: on_change,
      on_report: on_report,
      state: state,
      root_subscription: None,
    )
  let workspace_key = child_key(field)
  let root_subscription =
    watershed.subscribe_typed(root, fn(event) {
      case event {
        map_kernel.ValueChanged(key, _, _, _) if key == workspace_key ->
          reopen_workspace(runtime)
        map_kernel.Cleared(_) -> reopen_workspace(runtime)
        map_kernel.ValueChanged(_, _, _, _) -> Nil
      }
    })
  let runtime = Runtime(..runtime, root_subscription: Some(root_subscription))
  reopen_workspace(runtime)
  runtime
}

@target(javascript)
/// The lifecycle states, sorted by instance ID.
pub fn lifecycle(
  runtime: Runtime(root, context, running),
) -> List(#(String, LifecycleState)) {
  get_state(runtime).lifecycle
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

@target(javascript)
/// The latest effective workspace layout.
pub fn layout(runtime: Runtime(root, context, running)) -> List(String) {
  case get_state(runtime).snapshot {
    Some(snapshot) -> workspace.layout(snapshot)
    None -> []
  }
}

@target(javascript)
/// The latest effective connection graph.
pub fn graph(
  runtime: Runtime(root, context, running),
) -> Option(port_graph.EffectiveGraph) {
  get_state(runtime).snapshot
  |> result_from_option
  |> result.map(workspace.graph)
  |> option_from_result
}

@target(javascript)
/// Read one ready instance's running value.
pub fn running(
  runtime: Runtime(root, context, running),
  instance_id: String,
) -> Result(running, Nil) {
  dict.get(get_state(runtime).instances, instance_id)
  |> result.map(fn(instance) { instance.running })
}

@target(javascript)
/// Apply one host action and route its typed output events.
pub fn command(
  runtime: Runtime(root, context, running),
  instance_id: String,
  action: fn(running) -> Result(#(running, List(component.OutputEvent)), String),
) -> Result(Nil, RuntimeError) {
  let state = get_state(runtime)
  use instance <- result.try(
    dict.get(state.instances, instance_id)
    |> result.map_error(fn(_) { InstanceNotReady(instance_id) }),
  )
  use outcome <- result.try(
    action(instance.running)
    |> result.map_error(fn(reason) { ActionFailed(instance_id, reason) }),
  )
  use _ <- result.try(
    validate_outputs(instance, outcome.1)
    |> result.map_error(fn(reason) { ComponentFailed(instance_id, reason) }),
  )
  let instance = RunningInstance(..instance, running: outcome.0)
  let output_count = list.length(outcome.1)
  let state =
    State(
      ..state,
      instances: dict.insert(state.instances, instance_id, instance),
      next_trace: state.next_trace + output_count,
    )
  set_state(runtime, state)
  notify(runtime)

  case state.snapshot, outcome.1 {
    _, [] -> Ok(Nil)
    None, _ -> Error(InstanceNotReady(instance_id))
    Some(snapshot), outputs -> {
      let graph = workspace.graph(snapshot)
      dispatch_outputs(
        runtime,
        graph,
        instance_id,
        outputs,
        state.next_trace - output_count + 1,
      )
      Ok(Nil)
    }
  }
}

@target(javascript)
/// Stop the runtime and every running component.
///
/// Cleanup errors are returned after all instances and subscriptions have had
/// a chance to stop.
pub fn stop(
  runtime: Runtime(root, context, running),
) -> List(component.ComponentError) {
  let state = get_state(runtime)
  case state.stopped {
    True -> []
    False -> {
      case runtime.root_subscription {
        Some(subscription) -> watershed.unsubscribe(subscription)
        None -> Nil
      }
      case state.workspace_subscription {
        Some(subscription) -> workspace_js.unsubscribe(subscription)
        None -> Nil
      }
      let errors =
        dict.values(state.instances)
        |> list.filter_map(fn(instance) {
          case component.stop(instance.descriptor, instance.running) {
            Ok(Nil) -> Error(Nil)
            Error(reason) -> Ok(reason)
          }
        })
      set_state(
        runtime,
        State(
          ..state,
          workspace_subscription: None,
          instances: dict.new(),
          pending: dict.new(),
          failed: dict.new(),
          lifecycle: dict.new(),
          notify_armed: False,
          stopped: True,
        ),
      )
      errors
    }
  }
}

@target(javascript)
fn arm_reconcile(runtime: Runtime(root, context, running)) -> Nil {
  let state = get_state(runtime)
  case state.stopped || state.reconcile_armed {
    True -> Nil
    False -> {
      set_state(runtime, State(..state, reconcile_armed: True))
      let transport_js.Scheduler(schedule: schedule, ..) = runtime.scheduler
      let _cancel = schedule(fn() { reconcile_now(runtime) }, 0)
      Nil
    }
  }
}

@target(javascript)
fn reconcile_now(runtime: Runtime(root, context, running)) -> Nil {
  let state = get_state(runtime)
  set_state(runtime, State(..state, reconcile_armed: False))
  case state.stopped, state.workspace {
    True, _ | _, None -> Nil
    False, Some(store) -> {
      let snapshot = workspace_js.read(store, runtime.catalog)
      let prepared = workspace_js.prepare(store, runtime.catalog)
      let active =
        list.append(
          dict.to_list(state.instances)
            |> list.map(fn(pair) {
              component_runtime.CurrentInstance(pair.0, pair.1.identity)
            }),
          dict.to_list(state.pending)
            |> list.map(fn(pair) {
              component_runtime.CurrentInstance(pair.0, pair.1.identity)
            }),
        )
      let current =
        list.append(
          active,
          dict.to_list(state.failed)
            |> list.map(fn(pair) {
              component_runtime.CurrentInstance(pair.0, pair.1)
            }),
        )
      let plan = component_runtime.reconcile(current, prepared)
      list.each(component_runtime.stops(plan), fn(instance_id) {
        stop_instance(runtime, instance_id)
      })
      let state = get_state(runtime)
      let lifecycle = lifecycle_for_plan(state, plan)
      set_state(
        runtime,
        State(..state, snapshot: Some(snapshot), lifecycle: lifecycle),
      )
      list.each(component_runtime.starts(plan), fn(starting) {
        start_instance(runtime, starting)
      })
      notify(runtime)
    }
  }
}

@target(javascript)
fn lifecycle_for_plan(
  state: State(root, context, running),
  plan: component_runtime.ReconcilePlan(watershed.SharedMap),
) -> Dict(String, LifecycleState) {
  let kept =
    list.fold(component_runtime.keeps(plan), dict.new(), fn(states, id) {
      case dict.get(state.instances, id), dict.get(state.pending, id) {
        Ok(instance), _ -> dict.insert(states, id, Ready(instance.entry))
        _, Ok(pending) -> dict.insert(states, id, Starting(pending.entry))
        _, _ ->
          case dict.get(state.lifecycle, id) {
            Ok(Failed(_, _) as failed) -> dict.insert(states, id, failed)
            _ -> states
          }
      }
    })
  let blocked =
    list.fold(component_runtime.blocked(plan), kept, fn(states, blocked) {
      case blocked {
        component_runtime.Loading(entry, reason) ->
          dict.insert(states, entry.instance_id, Loading(entry, reason))
        component_runtime.Unavailable(entry, reason) ->
          dict.insert(states, entry.instance_id, Unavailable(entry, reason))
        component_runtime.Failed(instance_id, reason) ->
          dict.insert(
            states,
            instance_id,
            Failed(instance_id, PreparationFailed(instance_id, reason)),
          )
      }
    })
  list.fold(component_runtime.starts(plan), blocked, fn(states, starting) {
    let component_runtime.StartInstance(entry:, ..) = starting
    dict.insert(states, entry.instance_id, Starting(entry))
  })
}

@target(javascript)
fn start_instance(
  runtime: Runtime(root, context, running),
  starting: component_runtime.StartInstance(watershed.SharedMap),
) -> Nil {
  let component_runtime.StartInstance(entry, identity, subtree) = starting
  case component.find(runtime.catalog, entry.kind, entry.version) {
    Error(reason) -> {
      let state = get_state(runtime)
      set_state(
        runtime,
        State(
          ..state,
          lifecycle: dict.insert(
            state.lifecycle,
            entry.instance_id,
            Failed(entry.instance_id, CatalogChanged(entry.instance_id, reason)),
          ),
        ),
      )
      notify(runtime)
    }
    Ok(descriptor) -> {
      let state = get_state(runtime)
      let generation = state.next_generation + 1
      let pending = PendingStart(entry, identity, generation)
      set_state(
        runtime,
        State(
          ..state,
          pending: dict.insert(state.pending, entry.instance_id, pending),
          next_generation: generation,
        ),
      )
      let context =
        runtime.context_for(entry, subtree, fn() { notify(runtime) })
      component.start(descriptor, context, entry.config, fn(started) {
        finish_start(runtime, descriptor, pending, started)
      })
    }
  }
}

@target(javascript)
fn finish_start(
  runtime: Runtime(root, context, running),
  descriptor: component.Descriptor(context, running),
  pending: PendingStart,
  started: Result(running, component.ComponentError),
) -> Nil {
  let state = get_state(runtime)
  let active = case dict.get(state.pending, pending.entry.instance_id) {
    Ok(found) -> found.generation == pending.generation && !state.stopped
    Error(Nil) -> False
  }
  case active, started {
    False, Ok(running) -> {
      case component.stop(descriptor, running) {
        Ok(Nil) -> Nil
        Error(reason) ->
          runtime.on_report(
            RuntimeFailed(ComponentFailed(pending.entry.instance_id, reason)),
          )
      }
    }
    False, Error(_) -> Nil
    True, Error(reason) -> {
      set_state(
        runtime,
        State(
          ..state,
          pending: dict.delete(state.pending, pending.entry.instance_id),
          failed: dict.insert(
            state.failed,
            pending.entry.instance_id,
            pending.identity,
          ),
          lifecycle: dict.insert(
            state.lifecycle,
            pending.entry.instance_id,
            Failed(
              pending.entry.instance_id,
              ComponentFailed(pending.entry.instance_id, reason),
            ),
          ),
        ),
      )
      notify(runtime)
    }
    True, Ok(running) -> {
      let instance =
        RunningInstance(
          entry: pending.entry,
          identity: pending.identity,
          descriptor: descriptor,
          running: running,
        )
      set_state(
        runtime,
        State(
          ..state,
          pending: dict.delete(state.pending, pending.entry.instance_id),
          failed: dict.delete(state.failed, pending.entry.instance_id),
          instances: dict.insert(
            state.instances,
            pending.entry.instance_id,
            instance,
          ),
          lifecycle: dict.insert(
            state.lifecycle,
            pending.entry.instance_id,
            Ready(pending.entry),
          ),
        ),
      )
      notify(runtime)
    }
  }
}

@target(javascript)
fn stop_instance(
  runtime: Runtime(root, context, running),
  instance_id: String,
) -> Nil {
  let state = get_state(runtime)
  case dict.get(state.instances, instance_id) {
    Error(Nil) -> Nil
    Ok(instance) ->
      case component.stop(instance.descriptor, instance.running) {
        Ok(Nil) -> Nil
        Error(reason) ->
          runtime.on_report(RuntimeFailed(ComponentFailed(instance_id, reason)))
      }
  }
  let state = get_state(runtime)
  set_state(
    runtime,
    State(
      ..state,
      instances: dict.delete(state.instances, instance_id),
      pending: dict.delete(state.pending, instance_id),
      failed: dict.delete(state.failed, instance_id),
    ),
  )
}

@target(javascript)
fn reopen_workspace(runtime: Runtime(root, context, running)) -> Nil {
  let state = get_state(runtime)
  case state.stopped {
    True -> Nil
    False -> {
      let generation = state.workspace_generation + 1
      set_state(runtime, State(..state, workspace_generation: generation))
      workspace_js.ensure(
        runtime.document,
        runtime.root,
        runtime.field,
        fn(opened) { finish_reopen(runtime, generation, opened) },
      )
    }
  }
}

@target(javascript)
fn finish_reopen(
  runtime: Runtime(root, context, running),
  generation: Int,
  opened: Result(workspace_js.Workspace(root), workspace_js.WorkspaceError),
) -> Nil {
  let state = get_state(runtime)
  case state.stopped || generation != state.workspace_generation, opened {
    True, _ -> Nil
    False, Error(reason) -> {
      case state.workspace_subscription {
        Some(subscription) -> workspace_js.unsubscribe(subscription)
        None -> Nil
      }
      dict.keys(state.instances)
      |> list.each(fn(instance_id) { stop_instance(runtime, instance_id) })
      let state = get_state(runtime)
      set_state(
        runtime,
        State(
          ..state,
          workspace: None,
          workspace_subscription: None,
          instances: dict.new(),
          pending: dict.new(),
          failed: dict.new(),
          lifecycle: dict.new(),
          snapshot: None,
        ),
      )
      runtime.on_report(RuntimeFailed(WorkspaceFailed(reason)))
      notify(runtime)
    }
    False, Ok(store) -> {
      case state.workspace_subscription {
        Some(subscription) -> workspace_js.unsubscribe(subscription)
        None -> Nil
      }
      let subscription =
        workspace_js.subscribe(store, fn() { arm_reconcile(runtime) })
      set_state(
        runtime,
        State(
          ..state,
          workspace: Some(store),
          workspace_subscription: Some(subscription),
        ),
      )
      arm_reconcile(runtime)
    }
  }
}

@target(javascript)
fn validate_outputs(
  instance: RunningInstance(context, running),
  outputs: List(component.OutputEvent),
) -> Result(Nil, component.ComponentError) {
  list.try_fold(outputs, Nil, fn(_, event) {
    component.validate_output(instance.descriptor, event)
  })
}

@target(javascript)
fn dispatch_outputs(
  runtime: Runtime(root, context, running),
  graph: port_graph.EffectiveGraph,
  instance_id: String,
  outputs: List(component.OutputEvent),
  trace_number: Int,
) -> Nil {
  case outputs {
    [] -> Nil
    [event, ..rest] -> {
      let trace =
        enqueue_output(
          runtime,
          graph,
          component_runtime.new_trace("trace-" <> int.to_string(trace_number)),
          instance_id,
          event,
        )
      drain(runtime, graph, trace)
      dispatch_outputs(runtime, graph, instance_id, rest, trace_number + 1)
    }
  }
}

@target(javascript)
fn enqueue_output(
  runtime: Runtime(root, context, running),
  graph: port_graph.EffectiveGraph,
  trace: component_runtime.DispatchTrace,
  instance_id: String,
  event: component.OutputEvent,
) -> component_runtime.DispatchTrace {
  let source = port_graph.PortRef(instance_id, component.output_id(event))
  runtime.on_report(Triggered(component_runtime.trace_id(trace), source))
  let plan =
    dispatch.plan(
      trace_id: component_runtime.trace_id(trace),
      origin: dispatch.LocalIntent,
      source: source,
      payload: component.output_payload(event),
      graph: graph,
      ports_for: fn(id) { ports_for(runtime, id) },
    )
  list.each(dispatch.errors(plan), fn(reason) {
    runtime.on_report(DispatchFailed(
      component_runtime.trace_id(trace),
      None,
      PlanningFailed(reason),
    ))
  })
  component_runtime.enqueue(trace, dispatch.deliveries(plan))
}

@target(javascript)
fn drain(
  runtime: Runtime(root, context, running),
  graph: port_graph.EffectiveGraph,
  trace: component_runtime.DispatchTrace,
) -> Nil {
  let #(next, trace) = component_runtime.next(trace)
  case next {
    None -> Nil
    Some(delivery) -> {
      let dispatch.Delivery(
        edge_id: edge_id,
        target: target,
        input_class: input_class,
        payload: payload,
        ..,
      ) = delivery
      let state = get_state(runtime)
      let trace = case dict.get(state.instances, target.instance_id) {
        Error(Nil) -> {
          runtime.on_report(DispatchFailed(
            component_runtime.trace_id(trace),
            Some(edge_id),
            TargetNotReady(target.instance_id),
          ))
          trace
        }
        Ok(instance) ->
          case
            component.deliver(
              instance.descriptor,
              instance.running,
              target.port_id,
              payload,
            )
          {
            Error(reason) -> {
              runtime.on_report(DispatchFailed(
                component_runtime.trace_id(trace),
                Some(edge_id),
                TargetInputRejected(target.instance_id, reason),
              ))
              trace
            }
            Ok(delivered) -> {
              let instance = RunningInstance(..instance, running: delivered.0)
              let state = get_state(runtime)
              set_state(
                runtime,
                State(
                  ..state,
                  instances: dict.insert(
                    state.instances,
                    target.instance_id,
                    instance,
                  ),
                ),
              )
              notify(runtime)
              case input_class {
                port.LocalInput ->
                  runtime.on_report(LocalDelivered(
                    component_runtime.trace_id(trace),
                    edge_id,
                    target,
                  ))
                port.CollaborativeInput(_) ->
                  runtime.on_report(MutationSubmitted(
                    component_runtime.trace_id(trace),
                    edge_id,
                    target,
                  ))
              }
              list.fold(delivered.1, trace, fn(trace, event) {
                case component.validate_output(instance.descriptor, event) {
                  Ok(Nil) ->
                    enqueue_output(
                      runtime,
                      graph,
                      trace,
                      target.instance_id,
                      event,
                    )
                  Error(reason) -> {
                    runtime.on_report(DispatchFailed(
                      component_runtime.trace_id(trace),
                      Some(edge_id),
                      SourceOutputRejected(target.instance_id, reason),
                    ))
                    trace
                  }
                }
              })
            }
          }
      }
      drain(runtime, graph, trace)
    }
  }
}

@target(javascript)
fn ports_for(
  runtime: Runtime(root, context, running),
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  dict.get(get_state(runtime).instances, instance_id)
  |> result.map(fn(instance) { component.ports(instance.descriptor) })
}

@target(javascript)
fn notify(runtime: Runtime(root, context, running)) -> Nil {
  let state = get_state(runtime)
  case state.stopped || state.notify_armed {
    True -> Nil
    False -> {
      set_state(runtime, State(..state, notify_armed: True))
      let transport_js.Scheduler(schedule: schedule, ..) = runtime.scheduler
      let _cancel = schedule(fn() { flush_notification(runtime) }, 0)
      Nil
    }
  }
}

@target(javascript)
fn flush_notification(runtime: Runtime(root, context, running)) -> Nil {
  let state = get_state(runtime)
  set_state(runtime, State(..state, notify_armed: False))
  case state.stopped {
    True -> Nil
    False -> runtime.on_change()
  }
}

@target(javascript)
fn get_state(
  runtime: Runtime(root, context, running),
) -> State(root, context, running) {
  transport_js.get_cell(runtime.state)
}

@target(javascript)
fn set_state(
  runtime: Runtime(root, context, running),
  state: State(root, context, running),
) -> Nil {
  transport_js.set_cell(runtime.state, state)
}

@target(javascript)
fn result_from_option(value: Option(a)) -> Result(a, Nil) {
  case value {
    Some(inner) -> Ok(inner)
    None -> Error(Nil)
  }
}

@target(javascript)
fn option_from_result(value: Result(a, Nil)) -> Option(a) {
  case value {
    Ok(inner) -> Some(inner)
    Error(Nil) -> None
  }
}

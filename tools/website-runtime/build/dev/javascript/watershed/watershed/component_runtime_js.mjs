/// <reference types="./component_runtime_js.d.mts" />
import * as $bool from "../../gleam_stdlib/gleam/bool.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  makeError,
} from "../gleam.mjs";
import * as $watershed from "../watershed.mjs";
import * as $callback_js from "../watershed/callback_js.mjs";
import * as $component from "../watershed/component.mjs";
import * as $component_runtime from "../watershed/component_runtime.mjs";
import * as $dispatch from "../watershed/dispatch.mjs";
import * as $map_kernel from "../watershed/map_kernel.mjs";
import * as $port from "../watershed/port.mjs";
import * as $port_graph from "../watershed/port_graph.mjs";
import * as $schema from "../watershed/schema.mjs";
import { child_key } from "../watershed/schema.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import * as $workspace from "../watershed/workspace.mjs";
import * as $workspace_js from "../watershed/workspace_js.mjs";

const FILEPATH = "src/watershed/component_runtime_js.gleam";

export class RuntimeBusy extends $CustomType {}
export const RuntimeError$RuntimeBusy$const = new RuntimeBusy();
export const RuntimeError$RuntimeBusy = () => RuntimeError$RuntimeBusy$const;
export const RuntimeError$isRuntimeBusy = (value) =>
  value instanceof RuntimeBusy;

export class RuntimeStopped extends $CustomType {}
export const RuntimeError$RuntimeStopped$const = new RuntimeStopped();
export const RuntimeError$RuntimeStopped = () =>
  RuntimeError$RuntimeStopped$const;
export const RuntimeError$isRuntimeStopped = (value) =>
  value instanceof RuntimeStopped;

export class DuplicateStartCompletion extends $CustomType {
  constructor(instance_id) {
    super();
    this.instance_id = instance_id;
  }
}
export const RuntimeError$DuplicateStartCompletion = (instance_id) =>
  new DuplicateStartCompletion(instance_id);
export const RuntimeError$isDuplicateStartCompletion = (value) =>
  value instanceof DuplicateStartCompletion;
export const RuntimeError$DuplicateStartCompletion$instance_id = (value) =>
  value.instance_id;
export const RuntimeError$DuplicateStartCompletion$0 = (value) =>
  value.instance_id;

/**
 * Host-wide hooks use an empty instance ID.
 */
export class HookThrew extends $CustomType {
  constructor(instance_id, hook, reason) {
    super();
    this.instance_id = instance_id;
    this.hook = hook;
    this.reason = reason;
  }
}
export const RuntimeError$HookThrew = (instance_id, hook, reason) =>
  new HookThrew(instance_id, hook, reason);
export const RuntimeError$isHookThrew = (value) => value instanceof HookThrew;
export const RuntimeError$HookThrew$instance_id = (value) => value.instance_id;
export const RuntimeError$HookThrew$0 = (value) => value.instance_id;
export const RuntimeError$HookThrew$hook = (value) => value.hook;
export const RuntimeError$HookThrew$1 = (value) => value.hook;
export const RuntimeError$HookThrew$reason = (value) => value.reason;
export const RuntimeError$HookThrew$2 = (value) => value.reason;

export class InstanceNotReady extends $CustomType {
  constructor(instance_id) {
    super();
    this.instance_id = instance_id;
  }
}
export const RuntimeError$InstanceNotReady = (instance_id) =>
  new InstanceNotReady(instance_id);
export const RuntimeError$isInstanceNotReady = (value) =>
  value instanceof InstanceNotReady;
export const RuntimeError$InstanceNotReady$instance_id = (value) =>
  value.instance_id;
export const RuntimeError$InstanceNotReady$0 = (value) => value.instance_id;

export class ActionFailed extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const RuntimeError$ActionFailed = (instance_id, reason) =>
  new ActionFailed(instance_id, reason);
export const RuntimeError$isActionFailed = (value) =>
  value instanceof ActionFailed;
export const RuntimeError$ActionFailed$instance_id = (value) =>
  value.instance_id;
export const RuntimeError$ActionFailed$0 = (value) => value.instance_id;
export const RuntimeError$ActionFailed$reason = (value) => value.reason;
export const RuntimeError$ActionFailed$1 = (value) => value.reason;

export class ComponentFailed extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const RuntimeError$ComponentFailed = (instance_id, reason) =>
  new ComponentFailed(instance_id, reason);
export const RuntimeError$isComponentFailed = (value) =>
  value instanceof ComponentFailed;
export const RuntimeError$ComponentFailed$instance_id = (value) =>
  value.instance_id;
export const RuntimeError$ComponentFailed$0 = (value) => value.instance_id;
export const RuntimeError$ComponentFailed$reason = (value) => value.reason;
export const RuntimeError$ComponentFailed$1 = (value) => value.reason;

export class PreparationFailed extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const RuntimeError$PreparationFailed = (instance_id, reason) =>
  new PreparationFailed(instance_id, reason);
export const RuntimeError$isPreparationFailed = (value) =>
  value instanceof PreparationFailed;
export const RuntimeError$PreparationFailed$instance_id = (value) =>
  value.instance_id;
export const RuntimeError$PreparationFailed$0 = (value) => value.instance_id;
export const RuntimeError$PreparationFailed$reason = (value) => value.reason;
export const RuntimeError$PreparationFailed$1 = (value) => value.reason;

export class CatalogChanged extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const RuntimeError$CatalogChanged = (instance_id, reason) =>
  new CatalogChanged(instance_id, reason);
export const RuntimeError$isCatalogChanged = (value) =>
  value instanceof CatalogChanged;
export const RuntimeError$CatalogChanged$instance_id = (value) =>
  value.instance_id;
export const RuntimeError$CatalogChanged$0 = (value) => value.instance_id;
export const RuntimeError$CatalogChanged$reason = (value) => value.reason;
export const RuntimeError$CatalogChanged$1 = (value) => value.reason;

export class WorkspaceFailed extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const RuntimeError$WorkspaceFailed = (reason) =>
  new WorkspaceFailed(reason);
export const RuntimeError$isWorkspaceFailed = (value) =>
  value instanceof WorkspaceFailed;
export const RuntimeError$WorkspaceFailed$reason = (value) => value.reason;
export const RuntimeError$WorkspaceFailed$0 = (value) => value.reason;

export class Loading extends $CustomType {
  constructor(entry, reason) {
    super();
    this.entry = entry;
    this.reason = reason;
  }
}
export const LifecycleState$Loading = (entry, reason) =>
  new Loading(entry, reason);
export const LifecycleState$isLoading = (value) => value instanceof Loading;
export const LifecycleState$Loading$entry = (value) => value.entry;
export const LifecycleState$Loading$0 = (value) => value.entry;
export const LifecycleState$Loading$reason = (value) => value.reason;
export const LifecycleState$Loading$1 = (value) => value.reason;

export class Starting extends $CustomType {
  constructor(entry) {
    super();
    this.entry = entry;
  }
}
export const LifecycleState$Starting = (entry) => new Starting(entry);
export const LifecycleState$isStarting = (value) => value instanceof Starting;
export const LifecycleState$Starting$entry = (value) => value.entry;
export const LifecycleState$Starting$0 = (value) => value.entry;

export class Ready extends $CustomType {
  constructor(entry) {
    super();
    this.entry = entry;
  }
}
export const LifecycleState$Ready = (entry) => new Ready(entry);
export const LifecycleState$isReady = (value) => value instanceof Ready;
export const LifecycleState$Ready$entry = (value) => value.entry;
export const LifecycleState$Ready$0 = (value) => value.entry;

export class Unavailable extends $CustomType {
  constructor(entry, reason) {
    super();
    this.entry = entry;
    this.reason = reason;
  }
}
export const LifecycleState$Unavailable = (entry, reason) =>
  new Unavailable(entry, reason);
export const LifecycleState$isUnavailable = (value) =>
  value instanceof Unavailable;
export const LifecycleState$Unavailable$entry = (value) => value.entry;
export const LifecycleState$Unavailable$0 = (value) => value.entry;
export const LifecycleState$Unavailable$reason = (value) => value.reason;
export const LifecycleState$Unavailable$1 = (value) => value.reason;

export class Failed extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const LifecycleState$Failed = (instance_id, reason) =>
  new Failed(instance_id, reason);
export const LifecycleState$isFailed = (value) => value instanceof Failed;
export const LifecycleState$Failed$instance_id = (value) => value.instance_id;
export const LifecycleState$Failed$0 = (value) => value.instance_id;
export const LifecycleState$Failed$reason = (value) => value.reason;
export const LifecycleState$Failed$1 = (value) => value.reason;

export class PlanningFailed extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const DispatchFailure$PlanningFailed = (reason) =>
  new PlanningFailed(reason);
export const DispatchFailure$isPlanningFailed = (value) =>
  value instanceof PlanningFailed;
export const DispatchFailure$PlanningFailed$reason = (value) => value.reason;
export const DispatchFailure$PlanningFailed$0 = (value) => value.reason;

export class SourceNotReady extends $CustomType {
  constructor(instance_id) {
    super();
    this.instance_id = instance_id;
  }
}
export const DispatchFailure$SourceNotReady = (instance_id) =>
  new SourceNotReady(instance_id);
export const DispatchFailure$isSourceNotReady = (value) =>
  value instanceof SourceNotReady;
export const DispatchFailure$SourceNotReady$instance_id = (value) =>
  value.instance_id;
export const DispatchFailure$SourceNotReady$0 = (value) => value.instance_id;

export class SourceOutputRejected extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const DispatchFailure$SourceOutputRejected = (instance_id, reason) =>
  new SourceOutputRejected(instance_id, reason);
export const DispatchFailure$isSourceOutputRejected = (value) =>
  value instanceof SourceOutputRejected;
export const DispatchFailure$SourceOutputRejected$instance_id = (value) =>
  value.instance_id;
export const DispatchFailure$SourceOutputRejected$0 = (value) =>
  value.instance_id;
export const DispatchFailure$SourceOutputRejected$reason = (value) =>
  value.reason;
export const DispatchFailure$SourceOutputRejected$1 = (value) => value.reason;

export class TargetNotReady extends $CustomType {
  constructor(instance_id) {
    super();
    this.instance_id = instance_id;
  }
}
export const DispatchFailure$TargetNotReady = (instance_id) =>
  new TargetNotReady(instance_id);
export const DispatchFailure$isTargetNotReady = (value) =>
  value instanceof TargetNotReady;
export const DispatchFailure$TargetNotReady$instance_id = (value) =>
  value.instance_id;
export const DispatchFailure$TargetNotReady$0 = (value) => value.instance_id;

export class TargetInputRejected extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const DispatchFailure$TargetInputRejected = (instance_id, reason) =>
  new TargetInputRejected(instance_id, reason);
export const DispatchFailure$isTargetInputRejected = (value) =>
  value instanceof TargetInputRejected;
export const DispatchFailure$TargetInputRejected$instance_id = (value) =>
  value.instance_id;
export const DispatchFailure$TargetInputRejected$0 = (value) =>
  value.instance_id;
export const DispatchFailure$TargetInputRejected$reason = (value) =>
  value.reason;
export const DispatchFailure$TargetInputRejected$1 = (value) => value.reason;

export class Triggered extends $CustomType {
  constructor(trace_id, source) {
    super();
    this.trace_id = trace_id;
    this.source = source;
  }
}
export const DispatchReport$Triggered = (trace_id, source) =>
  new Triggered(trace_id, source);
export const DispatchReport$isTriggered = (value) => value instanceof Triggered;
export const DispatchReport$Triggered$trace_id = (value) => value.trace_id;
export const DispatchReport$Triggered$0 = (value) => value.trace_id;
export const DispatchReport$Triggered$source = (value) => value.source;
export const DispatchReport$Triggered$1 = (value) => value.source;

export class LocalDelivered extends $CustomType {
  constructor(trace_id, edge_id, target) {
    super();
    this.trace_id = trace_id;
    this.edge_id = edge_id;
    this.target = target;
  }
}
export const DispatchReport$LocalDelivered = (trace_id, edge_id, target) =>
  new LocalDelivered(trace_id, edge_id, target);
export const DispatchReport$isLocalDelivered = (value) =>
  value instanceof LocalDelivered;
export const DispatchReport$LocalDelivered$trace_id = (value) => value.trace_id;
export const DispatchReport$LocalDelivered$0 = (value) => value.trace_id;
export const DispatchReport$LocalDelivered$edge_id = (value) => value.edge_id;
export const DispatchReport$LocalDelivered$1 = (value) => value.edge_id;
export const DispatchReport$LocalDelivered$target = (value) => value.target;
export const DispatchReport$LocalDelivered$2 = (value) => value.target;

export class MutationSubmitted extends $CustomType {
  constructor(trace_id, edge_id, target) {
    super();
    this.trace_id = trace_id;
    this.edge_id = edge_id;
    this.target = target;
  }
}
export const DispatchReport$MutationSubmitted = (trace_id, edge_id, target) =>
  new MutationSubmitted(trace_id, edge_id, target);
export const DispatchReport$isMutationSubmitted = (value) =>
  value instanceof MutationSubmitted;
export const DispatchReport$MutationSubmitted$trace_id = (value) =>
  value.trace_id;
export const DispatchReport$MutationSubmitted$0 = (value) => value.trace_id;
export const DispatchReport$MutationSubmitted$edge_id = (value) =>
  value.edge_id;
export const DispatchReport$MutationSubmitted$1 = (value) => value.edge_id;
export const DispatchReport$MutationSubmitted$target = (value) => value.target;
export const DispatchReport$MutationSubmitted$2 = (value) => value.target;

export class DispatchFailed extends $CustomType {
  constructor(trace_id, edge_id, reason) {
    super();
    this.trace_id = trace_id;
    this.edge_id = edge_id;
    this.reason = reason;
  }
}
export const DispatchReport$DispatchFailed = (trace_id, edge_id, reason) =>
  new DispatchFailed(trace_id, edge_id, reason);
export const DispatchReport$isDispatchFailed = (value) =>
  value instanceof DispatchFailed;
export const DispatchReport$DispatchFailed$trace_id = (value) => value.trace_id;
export const DispatchReport$DispatchFailed$0 = (value) => value.trace_id;
export const DispatchReport$DispatchFailed$edge_id = (value) => value.edge_id;
export const DispatchReport$DispatchFailed$1 = (value) => value.edge_id;
export const DispatchReport$DispatchFailed$reason = (value) => value.reason;
export const DispatchReport$DispatchFailed$2 = (value) => value.reason;

export class RuntimeFailed extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const DispatchReport$RuntimeFailed = (reason) =>
  new RuntimeFailed(reason);
export const DispatchReport$isRuntimeFailed = (value) =>
  value instanceof RuntimeFailed;
export const DispatchReport$RuntimeFailed$reason = (value) => value.reason;
export const DispatchReport$RuntimeFailed$0 = (value) => value.reason;

class RunningInstance extends $CustomType {
  constructor(entry, identity, generation, descriptor, running, disable_output) {
    super();
    this.entry = entry;
    this.identity = identity;
    this.generation = generation;
    this.descriptor = descriptor;
    this.running = running;
    this.disable_output = disable_output;
  }
}

class PendingStart extends $CustomType {
  constructor(entry, identity, generation, disable_output) {
    super();
    this.entry = entry;
    this.identity = identity;
    this.generation = generation;
    this.disable_output = disable_output;
  }
}

class State extends $CustomType {
  constructor(workspace, workspace_subscription, instances, pending, failed, lifecycle, snapshot, next_generation, next_trace, workspace_generation, reconcile_armed, notify_armed, operation_active, hook_failed, stopped) {
    super();
    this.workspace = workspace;
    this.workspace_subscription = workspace_subscription;
    this.instances = instances;
    this.pending = pending;
    this.failed = failed;
    this.lifecycle = lifecycle;
    this.snapshot = snapshot;
    this.next_generation = next_generation;
    this.next_trace = next_trace;
    this.workspace_generation = workspace_generation;
    this.reconcile_armed = reconcile_armed;
    this.notify_armed = notify_armed;
    this.operation_active = operation_active;
    this.hook_failed = hook_failed;
    this.stopped = stopped;
  }
}

class Runtime extends $CustomType {
  constructor(document, root, field, catalog, context_for, scheduler, on_change, on_report, state, root_subscription) {
    super();
    this.document = document;
    this.root = root;
    this.field = field;
    this.catalog = catalog;
    this.context_for = context_for;
    this.scheduler = scheduler;
    this.on_change = on_change;
    this.on_report = on_report;
    this.state = state;
    this.root_subscription = root_subscription;
  }
}

function report(runtime, event) {
  let $ = $callback_js.capture(() => { return runtime.on_report(event); });
  if ($ instanceof Ok) {
    return undefined;
  } else {
    let reason = $[0];
    return $callback_js.report("component runtime on_report: " + reason);
  }
}

function set_state(runtime, state) {
  return $transport_js.set_cell(runtime.state, state);
}

function get_state(runtime) {
  return $transport_js.get_cell(runtime.state);
}

function release_operation(runtime) {
  return set_state(
    runtime,
    (() => {
      let _record = get_state(runtime);
      return new State(
        _record.workspace,
        _record.workspace_subscription,
        _record.instances,
        _record.pending,
        _record.failed,
        _record.lifecycle,
        _record.snapshot,
        _record.next_generation,
        _record.next_trace,
        _record.workspace_generation,
        _record.reconcile_armed,
        _record.notify_armed,
        false,
        _record.hook_failed,
        _record.stopped,
      );
    })(),
  );
}

function own_lifecycle(runtime, work) {
  let state = get_state(runtime);
  let $ = state.operation_active;
  if ($) {
    let $1 = runtime.scheduler;
    let schedule = $1.schedule;
    let $2 = schedule(() => { return own_lifecycle(runtime, work); }, 0);
    
    return undefined;
  } else {
    set_state(
      runtime,
      new State(
        state.workspace,
        state.workspace_subscription,
        state.instances,
        state.pending,
        state.failed,
        state.lifecycle,
        state.snapshot,
        state.next_generation,
        state.next_trace,
        state.workspace_generation,
        state.reconcile_armed,
        state.notify_armed,
        true,
        state.hook_failed,
        state.stopped,
      ),
    );
    work();
    return release_operation(runtime);
  }
}

function flush_notification(runtime) {
  return own_lifecycle(
    runtime,
    () => {
      let state = get_state(runtime);
      set_state(
        runtime,
        new State(
          state.workspace,
          state.workspace_subscription,
          state.instances,
          state.pending,
          state.failed,
          state.lifecycle,
          state.snapshot,
          state.next_generation,
          state.next_trace,
          state.workspace_generation,
          state.reconcile_armed,
          false,
          state.operation_active,
          state.hook_failed,
          state.stopped,
        ),
      );
      let $ = state.stopped;
      if ($) {
        return undefined;
      } else {
        let $1 = $callback_js.capture(runtime.on_change);
        if ($1 instanceof Ok) {
          return undefined;
        } else {
          let reason = $1[0];
          return report(
            runtime,
            new RuntimeFailed(new HookThrew("", "on_change", reason)),
          );
        }
      }
    },
  );
}

function notify(runtime) {
  let state = get_state(runtime);
  let $ = state.stopped || state.notify_armed;
  if ($) {
    return undefined;
  } else {
    set_state(
      runtime,
      new State(
        state.workspace,
        state.workspace_subscription,
        state.instances,
        state.pending,
        state.failed,
        state.lifecycle,
        state.snapshot,
        state.next_generation,
        state.next_trace,
        state.workspace_generation,
        state.reconcile_armed,
        true,
        state.operation_active,
        state.hook_failed,
        state.stopped,
      ),
    );
    let $1 = runtime.scheduler;
    let schedule = $1.schedule;
    let $2 = schedule(() => { return flush_notification(runtime); }, 0);
    
    return undefined;
  }
}

function stop_component(descriptor, running) {
  let $ = $callback_js.capture(
    () => { return $component.stop(descriptor, running); },
  );
  if ($ instanceof Ok) {
    let outcome = $[0];
    return outcome;
  } else {
    let reason = $[0];
    return new Error(
      new $component.StopFailed(
        $component.kind(descriptor),
        $component.version(descriptor),
        reason,
      ),
    );
  }
}

function finish_start(runtime, descriptor, pending, started) {
  let state = get_state(runtime);
  let _block;
  let $ = $dict.get(state.pending, pending.entry.instance_id);
  if ($ instanceof Ok) {
    let found = $[0];
    _block = (found.generation === pending.generation) && !state.stopped;
  } else {
    _block = false;
  }
  let active = _block;
  if (active) {
    if (started instanceof Ok) {
      let running$1 = started[0];
      let instance = new RunningInstance(
        pending.entry,
        pending.identity,
        pending.generation,
        descriptor,
        running$1,
        pending.disable_output,
      );
      set_state(
        runtime,
        new State(
          state.workspace,
          state.workspace_subscription,
          $dict.insert(state.instances, pending.entry.instance_id, instance),
          $dict.delete$(state.pending, pending.entry.instance_id),
          $dict.delete$(state.failed, pending.entry.instance_id),
          $dict.insert(
            state.lifecycle,
            pending.entry.instance_id,
            new Ready(pending.entry),
          ),
          state.snapshot,
          state.next_generation,
          state.next_trace,
          state.workspace_generation,
          state.reconcile_armed,
          state.notify_armed,
          state.operation_active,
          state.hook_failed,
          state.stopped,
        ),
      );
      return notify(runtime);
    } else {
      let reason = started[0];
      pending.disable_output();
      set_state(
        runtime,
        new State(
          state.workspace,
          state.workspace_subscription,
          state.instances,
          $dict.delete$(state.pending, pending.entry.instance_id),
          $dict.insert(
            state.failed,
            pending.entry.instance_id,
            pending.identity,
          ),
          $dict.insert(
            state.lifecycle,
            pending.entry.instance_id,
            new Failed(
              pending.entry.instance_id,
              new ComponentFailed(pending.entry.instance_id, reason),
            ),
          ),
          state.snapshot,
          state.next_generation,
          state.next_trace,
          state.workspace_generation,
          state.reconcile_armed,
          state.notify_armed,
          state.operation_active,
          state.hook_failed,
          state.stopped,
        ),
      );
      return notify(runtime);
    }
  } else if (started instanceof Ok) {
    let running$1 = started[0];
    pending.disable_output();
    let $1 = stop_component(descriptor, running$1);
    if ($1 instanceof Ok) {
      return undefined;
    } else {
      let reason = $1[0];
      return report(
        runtime,
        new RuntimeFailed(
          new ComponentFailed(pending.entry.instance_id, reason),
        ),
      );
    }
  } else {
    return pending.disable_output();
  }
}

function stop_owned(runtime) {
  let state = get_state(runtime);
  let $ = state.stopped;
  if ($) {
    return $List$Empty$const;
  } else {
    set_state(
      runtime,
      new State(
        state.workspace,
        Option$None$const,
        $dict.new$(),
        $dict.new$(),
        $dict.new$(),
        $dict.new$(),
        state.snapshot,
        state.next_generation,
        state.next_trace,
        state.workspace_generation,
        state.reconcile_armed,
        false,
        state.operation_active,
        state.hook_failed,
        true,
      ),
    );
    let _pipe = $dict.values(state.instances);
    $list.each(_pipe, (instance) => { return instance.disable_output(); });
    let _pipe$1 = $dict.values(state.pending);
    $list.each(_pipe$1, (pending) => { return pending.disable_output(); });
    let $1 = runtime.root_subscription;
    if ($1 instanceof Some) {
      let subscription = $1[0];
      $watershed.unsubscribe(subscription);
    } else {
      undefined;
    }
    let $2 = state.workspace_subscription;
    if ($2 instanceof Some) {
      let subscription = $2[0];
      $workspace_js.unsubscribe(subscription);
    } else {
      undefined;
    }
    let _block;
    let _pipe$2 = $dict.values(state.instances);
    _block = $list.filter_map(
      _pipe$2,
      (instance) => {
        let $3 = stop_component(instance.descriptor, instance.running);
        if ($3 instanceof Ok) {
          return new Error(undefined);
        } else {
          let reason = $3[0];
          return new Ok([instance.entry.instance_id, reason]);
        }
      },
    );
    let errors = _block;
    return errors;
  }
}

function invoke_hook(runtime, instance_id, hook, work) {
  let $ = $callback_js.capture(work);
  if ($ instanceof Ok) {
    return $;
  } else {
    let reason = $[0];
    let fault = new HookThrew(instance_id, hook, reason);
    set_state(
      runtime,
      (() => {
        let _record = get_state(runtime);
        return new State(
          _record.workspace,
          _record.workspace_subscription,
          _record.instances,
          _record.pending,
          _record.failed,
          _record.lifecycle,
          _record.snapshot,
          _record.next_generation,
          _record.next_trace,
          _record.workspace_generation,
          _record.reconcile_armed,
          _record.notify_armed,
          _record.operation_active,
          true,
          _record.stopped,
        );
      })(),
    );
    let cleanup_errors = stop_owned(runtime);
    report(runtime, new RuntimeFailed(fault));
    $list.each(
      cleanup_errors,
      (failure) => {
        return report(
          runtime,
          new RuntimeFailed(new ComponentFailed(failure[0], failure[1])),
        );
      },
    );
    return new Error(fault);
  }
}

function check_running(runtime) {
  let $ = get_state(runtime).stopped;
  if ($) {
    return new Error(RuntimeError$RuntimeStopped$const);
  } else {
    return new Ok(undefined);
  }
}

function start_prepared(runtime, descriptor, pending, subtree, emitter) {
  let entry = pending.entry;
  return $result.try$(
    invoke_hook(
      runtime,
      entry.instance_id,
      "context",
      () => {
        return runtime.context_for(
          entry,
          subtree,
          () => { return notify(runtime); },
          emitter,
        );
      },
    ),
    (context) => {
      return $result.try$(
        check_running(runtime),
        (_) => {
          let inline_completions = $transport_js.new_cell(
            new Some($List$Empty$const),
          );
          let completed = $transport_js.new_cell(false);
          let outcome = invoke_hook(
            runtime,
            entry.instance_id,
            "start",
            () => {
              return $component.start(
                descriptor,
                context,
                entry.config,
                (started) => {
                  let duplicate = $transport_js.get_cell(completed);
                  $transport_js.set_cell(completed, true);
                  let finish = () => {
                    if (duplicate) {
                      return report(
                        runtime,
                        new RuntimeFailed(
                          new DuplicateStartCompletion(entry.instance_id),
                        ),
                      );
                    } else {
                      return finish_start(runtime, descriptor, pending, started);
                    }
                  };
                  let $ = $transport_js.get_cell(inline_completions);
                  if ($ instanceof Some) {
                    let completions = $[0];
                    return $transport_js.set_cell(
                      inline_completions,
                      new Some(listPrepend(finish, completions)),
                    );
                  } else {
                    return own_lifecycle(runtime, finish);
                  }
                },
              );
            },
          );
          let $ = $transport_js.get_cell(inline_completions);
          let completions;
          if ($ instanceof Some) {
            completions = $[0];
          } else {
            throw makeError(
              "let_assert",
              FILEPATH,
              "watershed/component_runtime_js",
              602,
              "start_prepared",
              "Pattern match failed, no pattern matched the value.",
              {
                value: $,
                start: 19011,
                end: 19083,
                pattern_start: 19022,
                pattern_end: 19039
              }
            )
          }
          $transport_js.set_cell(inline_completions, Option$None$const);
          let _pipe = completions;
          let _pipe$1 = $list.reverse(_pipe);
          $list.each(_pipe$1, (finish) => { return finish(); });
          return outcome;
        },
      );
    },
  );
}

function ports_for(runtime, instance_id) {
  let _pipe = $dict.get(get_state(runtime).instances, instance_id);
  return $result.map(
    _pipe,
    (instance) => { return $component.ports(instance.descriptor); },
  );
}

function enqueue_output(runtime, graph, trace, instance_id, event) {
  return $bool.guard(
    get_state(runtime).stopped,
    trace,
    () => {
      let source = new $port_graph.PortRef(
        instance_id,
        $component.output_id(event),
      );
      report(runtime, new Triggered($component_runtime.trace_id(trace), source));
      return $bool.guard(
        get_state(runtime).stopped,
        trace,
        () => {
          let plan = $dispatch.plan(
            $component_runtime.trace_id(trace),
            $dispatch.Origin$LocalIntent$const,
            source,
            $component.output_payload(event),
            graph,
            (id) => { return ports_for(runtime, id); },
          );
          $list.each(
            $dispatch.errors(plan),
            (reason) => {
              return $bool.guard(
                get_state(runtime).stopped,
                undefined,
                () => {
                  return report(
                    runtime,
                    new DispatchFailed(
                      $component_runtime.trace_id(trace),
                      Option$None$const,
                      new PlanningFailed(reason),
                    ),
                  );
                },
              );
            },
          );
          return $component_runtime.enqueue(trace, $dispatch.deliveries(plan));
        },
      );
    },
  );
}

function drain(runtime, graph, trace) {
  return $bool.guard(
    get_state(runtime).stopped,
    undefined,
    () => {
      let $ = $component_runtime.next(trace);
      let next = $[0];
      let trace$1 = $[1];
      if (next instanceof Some) {
        let delivery = next[0];
        let edge_id = delivery.edge_id;
        let target = delivery.target;
        let input_class = delivery.input_class;
        let payload = delivery.payload;
        let state = get_state(runtime);
        let _block;
        let $1 = $dict.get(state.instances, target.instance_id);
        if ($1 instanceof Ok) {
          let instance = $1[0];
          let delivered = invoke_hook(
            runtime,
            target.instance_id,
            "input",
            () => {
              return $component.deliver(
                instance.descriptor,
                instance.running,
                target.port_id,
                payload,
              );
            },
          );
          _block = $bool.guard(
            get_state(runtime).stopped,
            trace$1,
            () => {
              let delivered$1;
              if (delivered instanceof Ok) {
                delivered$1 = delivered[0];
              } else {
                throw makeError(
                  "let_assert",
                  FILEPATH,
                  "watershed/component_runtime_js",
                  1001,
                  "drain",
                  "Pattern match failed, no pattern matched the value.",
                  {
                    value: delivered,
                    start: 30527,
                    end: 30563,
                    pattern_start: 30538,
                    pattern_end: 30551
                  }
                )
              }
              if (delivered$1 instanceof Ok) {
                let delivered$2 = delivered$1[0];
                let instance$1 = new RunningInstance(
                  instance.entry,
                  instance.identity,
                  instance.generation,
                  instance.descriptor,
                  delivered$2[0],
                  instance.disable_output,
                );
                let state$1 = get_state(runtime);
                set_state(
                  runtime,
                  new State(
                    state$1.workspace,
                    state$1.workspace_subscription,
                    $dict.insert(
                      state$1.instances,
                      target.instance_id,
                      instance$1,
                    ),
                    state$1.pending,
                    state$1.failed,
                    state$1.lifecycle,
                    state$1.snapshot,
                    state$1.next_generation,
                    state$1.next_trace,
                    state$1.workspace_generation,
                    state$1.reconcile_armed,
                    state$1.notify_armed,
                    state$1.operation_active,
                    state$1.hook_failed,
                    state$1.stopped,
                  ),
                );
                notify(runtime);
                if (input_class instanceof $port.LocalInput) {
                  report(
                    runtime,
                    new LocalDelivered(
                      $component_runtime.trace_id(trace$1),
                      edge_id,
                      target,
                    ),
                  );
                } else {
                  report(
                    runtime,
                    new MutationSubmitted(
                      $component_runtime.trace_id(trace$1),
                      edge_id,
                      target,
                    ),
                  );
                }
                return $list.fold(
                  delivered$2[1],
                  trace$1,
                  (trace, event) => {
                    return $bool.guard(
                      get_state(runtime).stopped,
                      trace,
                      () => {
                        let $2 = $component.validate_output(
                          instance$1.descriptor,
                          event,
                        );
                        if ($2 instanceof Ok) {
                          return enqueue_output(
                            runtime,
                            graph,
                            trace,
                            target.instance_id,
                            event,
                          );
                        } else {
                          let reason = $2[0];
                          report(
                            runtime,
                            new DispatchFailed(
                              $component_runtime.trace_id(trace),
                              new Some(edge_id),
                              new SourceOutputRejected(
                                target.instance_id,
                                reason,
                              ),
                            ),
                          );
                          return trace;
                        }
                      },
                    );
                  },
                );
              } else {
                let reason = delivered$1[0];
                report(
                  runtime,
                  new DispatchFailed(
                    $component_runtime.trace_id(trace$1),
                    new Some(edge_id),
                    new TargetInputRejected(target.instance_id, reason),
                  ),
                );
                return trace$1;
              }
            },
          );
        } else {
          report(
            runtime,
            new DispatchFailed(
              $component_runtime.trace_id(trace$1),
              new Some(edge_id),
              new TargetNotReady(target.instance_id),
            ),
          );
          _block = trace$1;
        }
        let trace$2 = _block;
        return drain(runtime, graph, trace$2);
      } else {
        return undefined;
      }
    },
  );
}

function dispatch_outputs(runtime, graph, instance_id, outputs, trace_number) {
  return $bool.guard(
    get_state(runtime).stopped,
    undefined,
    () => {
      if (outputs instanceof $Empty) {
        return undefined;
      } else {
        let event = outputs.head;
        let rest = outputs.tail;
        let trace = enqueue_output(
          runtime,
          graph,
          $component_runtime.new_trace("trace-" + $int.to_string(trace_number)),
          instance_id,
          event,
        );
        drain(runtime, graph, trace);
        return dispatch_outputs(
          runtime,
          graph,
          instance_id,
          rest,
          trace_number + 1,
        );
      }
    },
  );
}

function report_async_failure(runtime, reason) {
  let state = get_state(runtime);
  let trace_number = state.next_trace + 1;
  set_state(
    runtime,
    new State(
      state.workspace,
      state.workspace_subscription,
      state.instances,
      state.pending,
      state.failed,
      state.lifecycle,
      state.snapshot,
      state.next_generation,
      trace_number,
      state.workspace_generation,
      state.reconcile_armed,
      state.notify_armed,
      state.operation_active,
      state.hook_failed,
      state.stopped,
    ),
  );
  return report(
    runtime,
    new DispatchFailed(
      "trace-" + $int.to_string(trace_number),
      Option$None$const,
      reason,
    ),
  );
}

function validate_outputs(instance, outputs) {
  return $list.try_fold(
    outputs,
    undefined,
    (_, event) => {
      return $component.validate_output(instance.descriptor, event);
    },
  );
}

function dispatch_async_outputs(runtime, instance_id, generation, outputs) {
  return own_lifecycle(
    runtime,
    () => {
      let state = get_state(runtime);
      let $ = state.stopped;
      let $1 = $dict.get(state.instances, instance_id);
      if ($) {
        return report_async_failure(runtime, new SourceNotReady(instance_id));
      } else if ($1 instanceof Ok) {
        let instance = $1[0];
        if (instance.generation !== generation) {
          return report_async_failure(runtime, new SourceNotReady(instance_id));
        } else {
          let instance = $1[0];
          let $2 = validate_outputs(instance, outputs);
          if ($2 instanceof Ok) {
            let $3 = state.snapshot;
            if ($3 instanceof Some) {
              let snapshot = $3[0];
              let output_count = $list.length(outputs);
              let first_trace = state.next_trace + 1;
              set_state(
                runtime,
                new State(
                  state.workspace,
                  state.workspace_subscription,
                  state.instances,
                  state.pending,
                  state.failed,
                  state.lifecycle,
                  state.snapshot,
                  state.next_generation,
                  state.next_trace + output_count,
                  state.workspace_generation,
                  state.reconcile_armed,
                  state.notify_armed,
                  state.operation_active,
                  state.hook_failed,
                  state.stopped,
                ),
              );
              return dispatch_outputs(
                runtime,
                $workspace.graph(snapshot),
                instance_id,
                outputs,
                first_trace,
              );
            } else {
              return report_async_failure(
                runtime,
                new SourceNotReady(instance_id),
              );
            }
          } else {
            let reason = $2[0];
            return report_async_failure(
              runtime,
              new SourceOutputRejected(instance_id, reason),
            );
          }
        }
      } else {
        return report_async_failure(runtime, new SourceNotReady(instance_id));
      }
    },
  );
}

function output_emitter(runtime, instance_id, generation) {
  let enabled = $transport_js.new_cell(true);
  let emitter = $component.output_emitter(
    (outputs) => {
      let $ = $transport_js.get_cell(enabled);
      if ($) {
        if (outputs instanceof $Empty) {
          return undefined;
        } else {
          let $1 = runtime.scheduler;
          let schedule = $1.schedule;
          let $2 = schedule(
            () => {
              return dispatch_async_outputs(
                runtime,
                instance_id,
                generation,
                outputs,
              );
            },
            0,
          );
          
          return undefined;
        }
      } else {
        return undefined;
      }
    },
  );
  return [emitter, () => { return $transport_js.set_cell(enabled, false); }];
}

function start_instance(runtime, starting) {
  return $bool.guard(
    get_state(runtime).stopped,
    undefined,
    () => {
      let entry = starting.entry;
      let identity = starting.identity;
      let subtree = starting.subtree;
      let $ = $component.find(runtime.catalog, entry.kind, entry.version);
      if ($ instanceof Ok) {
        let descriptor = $[0];
        let state = get_state(runtime);
        let generation = state.next_generation + 1;
        let $1 = output_emitter(runtime, entry.instance_id, generation);
        let emitter = $1[0];
        let disable_output = $1[1];
        let pending = new PendingStart(
          entry,
          identity,
          generation,
          disable_output,
        );
        set_state(
          runtime,
          new State(
            state.workspace,
            state.workspace_subscription,
            state.instances,
            $dict.insert(state.pending, entry.instance_id, pending),
            state.failed,
            state.lifecycle,
            state.snapshot,
            generation,
            state.next_trace,
            state.workspace_generation,
            state.reconcile_armed,
            state.notify_armed,
            state.operation_active,
            state.hook_failed,
            state.stopped,
          ),
        );
        let $2 = start_prepared(runtime, descriptor, pending, subtree, emitter);
        
        return undefined;
      } else {
        let reason = $[0];
        let state = get_state(runtime);
        set_state(
          runtime,
          new State(
            state.workspace,
            state.workspace_subscription,
            state.instances,
            state.pending,
            state.failed,
            $dict.insert(
              state.lifecycle,
              entry.instance_id,
              new Failed(
                entry.instance_id,
                new CatalogChanged(entry.instance_id, reason),
              ),
            ),
            state.snapshot,
            state.next_generation,
            state.next_trace,
            state.workspace_generation,
            state.reconcile_armed,
            state.notify_armed,
            state.operation_active,
            state.hook_failed,
            state.stopped,
          ),
        );
        return notify(runtime);
      }
    },
  );
}

function lifecycle_for_plan(state, plan) {
  let kept = $list.fold(
    $component_runtime.keeps(plan),
    $dict.new$(),
    (states, id) => {
      let $ = $dict.get(state.instances, id);
      let $1 = $dict.get(state.pending, id);
      if ($ instanceof Ok) {
        let instance = $[0];
        return $dict.insert(states, id, new Ready(instance.entry));
      } else if ($1 instanceof Ok) {
        let pending = $1[0];
        return $dict.insert(states, id, new Starting(pending.entry));
      } else {
        let $2 = $dict.get(state.lifecycle, id);
        if ($2 instanceof Ok) {
          let $3 = $2[0];
          if ($3 instanceof Failed) {
            let failed = $3;
            return $dict.insert(states, id, failed);
          } else {
            return states;
          }
        } else {
          return states;
        }
      }
    },
  );
  let blocked = $list.fold(
    $component_runtime.blocked(plan),
    kept,
    (states, blocked) => {
      if (blocked instanceof $component_runtime.Loading) {
        let entry = blocked.entry;
        let reason = blocked.reason;
        return $dict.insert(
          states,
          entry.instance_id,
          new Loading(entry, reason),
        );
      } else if (blocked instanceof $component_runtime.Unavailable) {
        let entry = blocked.entry;
        let reason = blocked.reason;
        return $dict.insert(
          states,
          entry.instance_id,
          new Unavailable(entry, reason),
        );
      } else {
        let instance_id = blocked.instance_id;
        let reason = blocked.reason;
        return $dict.insert(
          states,
          instance_id,
          new Failed(instance_id, new PreparationFailed(instance_id, reason)),
        );
      }
    },
  );
  return $list.fold(
    $component_runtime.starts(plan),
    blocked,
    (states, starting) => {
      let entry = starting.entry;
      return $dict.insert(states, entry.instance_id, new Starting(entry));
    },
  );
}

function stop_instance(runtime, instance_id) {
  let state = get_state(runtime);
  set_state(
    runtime,
    new State(
      state.workspace,
      state.workspace_subscription,
      $dict.delete$(state.instances, instance_id),
      $dict.delete$(state.pending, instance_id),
      $dict.delete$(state.failed, instance_id),
      state.lifecycle,
      state.snapshot,
      state.next_generation,
      state.next_trace,
      state.workspace_generation,
      state.reconcile_armed,
      state.notify_armed,
      state.operation_active,
      state.hook_failed,
      state.stopped,
    ),
  );
  let $ = $dict.get(state.pending, instance_id);
  if ($ instanceof Ok) {
    let pending = $[0];
    pending.disable_output();
  } else {
    undefined;
  }
  let $1 = $dict.get(state.instances, instance_id);
  if ($1 instanceof Ok) {
    let instance = $1[0];
    instance.disable_output();
    let $2 = stop_component(instance.descriptor, instance.running);
    if ($2 instanceof Ok) {
      return undefined;
    } else {
      let reason = $2[0];
      return report(
        runtime,
        new RuntimeFailed(new ComponentFailed(instance_id, reason)),
      );
    }
  } else {
    return undefined;
  }
}

function reconcile_now(runtime) {
  return own_lifecycle(
    runtime,
    () => {
      let state = get_state(runtime);
      set_state(
        runtime,
        new State(
          state.workspace,
          state.workspace_subscription,
          state.instances,
          state.pending,
          state.failed,
          state.lifecycle,
          state.snapshot,
          state.next_generation,
          state.next_trace,
          state.workspace_generation,
          false,
          state.notify_armed,
          state.operation_active,
          state.hook_failed,
          state.stopped,
        ),
      );
      let $ = state.stopped;
      let $1 = state.workspace;
      if ($) {
        return undefined;
      } else if ($1 instanceof Some) {
        let store = $1[0];
        let snapshot = $workspace_js.read(store, runtime.catalog);
        let prepared = $workspace_js.prepare(store, runtime.catalog);
        let active = $list.append(
          (() => {
            let _pipe = $dict.to_list(state.instances);
            return $list.map(
              _pipe,
              (pair) => {
                return new $component_runtime.CurrentInstance(
                  pair[0],
                  pair[1].identity,
                );
              },
            );
          })(),
          (() => {
            let _pipe = $dict.to_list(state.pending);
            return $list.map(
              _pipe,
              (pair) => {
                return new $component_runtime.CurrentInstance(
                  pair[0],
                  pair[1].identity,
                );
              },
            );
          })(),
        );
        let current = $list.append(
          active,
          (() => {
            let _pipe = $dict.to_list(state.failed);
            return $list.map(
              _pipe,
              (pair) => {
                return new $component_runtime.CurrentInstance(pair[0], pair[1]);
              },
            );
          })(),
        );
        let plan = $component_runtime.reconcile(current, prepared);
        $list.each(
          $component_runtime.stops(plan),
          (instance_id) => { return stop_instance(runtime, instance_id); },
        );
        let state$1 = get_state(runtime);
        return $bool.guard(
          state$1.stopped,
          undefined,
          () => {
            let lifecycle$1 = lifecycle_for_plan(state$1, plan);
            set_state(
              runtime,
              new State(
                state$1.workspace,
                state$1.workspace_subscription,
                state$1.instances,
                state$1.pending,
                state$1.failed,
                lifecycle$1,
                new Some(snapshot),
                state$1.next_generation,
                state$1.next_trace,
                state$1.workspace_generation,
                state$1.reconcile_armed,
                state$1.notify_armed,
                state$1.operation_active,
                state$1.hook_failed,
                state$1.stopped,
              ),
            );
            $list.each(
              $component_runtime.starts(plan),
              (starting) => { return start_instance(runtime, starting); },
            );
            return notify(runtime);
          },
        );
      } else {
        return undefined;
      }
    },
  );
}

function arm_reconcile(runtime) {
  let state = get_state(runtime);
  let $ = state.stopped || state.reconcile_armed;
  if ($) {
    return undefined;
  } else {
    set_state(
      runtime,
      new State(
        state.workspace,
        state.workspace_subscription,
        state.instances,
        state.pending,
        state.failed,
        state.lifecycle,
        state.snapshot,
        state.next_generation,
        state.next_trace,
        state.workspace_generation,
        true,
        state.notify_armed,
        state.operation_active,
        state.hook_failed,
        state.stopped,
      ),
    );
    let $1 = runtime.scheduler;
    let schedule = $1.schedule;
    let $2 = schedule(() => { return reconcile_now(runtime); }, 0);
    
    return undefined;
  }
}

function finish_reopen(runtime, generation, opened) {
  return own_lifecycle(
    runtime,
    () => {
      let state = get_state(runtime);
      let $ = state.stopped || (generation !== state.workspace_generation);
      if ($) {
        return undefined;
      } else if (opened instanceof Ok) {
        let store = opened[0];
        let $1 = state.workspace_subscription;
        if ($1 instanceof Some) {
          let subscription = $1[0];
          $workspace_js.unsubscribe(subscription);
        } else {
          undefined;
        }
        let subscription = $workspace_js.subscribe(
          store,
          () => { return arm_reconcile(runtime); },
        );
        set_state(
          runtime,
          new State(
            new Some(store),
            new Some(subscription),
            state.instances,
            state.pending,
            state.failed,
            state.lifecycle,
            state.snapshot,
            state.next_generation,
            state.next_trace,
            state.workspace_generation,
            state.reconcile_armed,
            state.notify_armed,
            state.operation_active,
            state.hook_failed,
            state.stopped,
          ),
        );
        return arm_reconcile(runtime);
      } else {
        let reason = opened[0];
        let $1 = state.workspace_subscription;
        if ($1 instanceof Some) {
          let subscription = $1[0];
          $workspace_js.unsubscribe(subscription);
        } else {
          undefined;
        }
        let _pipe = $dict.keys(state.instances);
        $list.each(
          _pipe,
          (instance_id) => { return stop_instance(runtime, instance_id); },
        );
        let _pipe$1 = $dict.values(state.pending);
        $list.each(_pipe$1, (pending) => { return pending.disable_output(); });
        let state$1 = get_state(runtime);
        set_state(
          runtime,
          new State(
            Option$None$const,
            Option$None$const,
            $dict.new$(),
            $dict.new$(),
            $dict.new$(),
            $dict.new$(),
            Option$None$const,
            state$1.next_generation,
            state$1.next_trace,
            state$1.workspace_generation,
            state$1.reconcile_armed,
            state$1.notify_armed,
            state$1.operation_active,
            state$1.hook_failed,
            state$1.stopped,
          ),
        );
        report(runtime, new RuntimeFailed(new WorkspaceFailed(reason)));
        return notify(runtime);
      }
    },
  );
}

function reopen_workspace(runtime) {
  return own_lifecycle(
    runtime,
    () => {
      let state = get_state(runtime);
      let $ = state.stopped;
      if ($) {
        return undefined;
      } else {
        let generation = state.workspace_generation + 1;
        set_state(
          runtime,
          new State(
            state.workspace,
            state.workspace_subscription,
            state.instances,
            state.pending,
            state.failed,
            state.lifecycle,
            state.snapshot,
            state.next_generation,
            state.next_trace,
            generation,
            state.reconcile_armed,
            state.notify_armed,
            state.operation_active,
            state.hook_failed,
            state.stopped,
          ),
        );
        return $workspace_js.ensure(
          runtime.document,
          runtime.root,
          runtime.field,
          (opened) => { return finish_reopen(runtime, generation, opened); },
        );
      }
    },
  );
}

/**
 * Start observing and running one ensured workspace.
 */
export function start(
  document,
  root,
  field,
  _,
  catalog,
  context_for,
  scheduler,
  on_change,
  on_report
) {
  let state = $transport_js.new_cell(
    new State(
      Option$None$const,
      Option$None$const,
      $dict.new$(),
      $dict.new$(),
      $dict.new$(),
      $dict.new$(),
      Option$None$const,
      0,
      0,
      0,
      false,
      false,
      false,
      false,
      false,
    ),
  );
  let runtime = new Runtime(
    document,
    root,
    field,
    catalog,
    context_for,
    scheduler,
    on_change,
    on_report,
    state,
    Option$None$const,
  );
  let workspace_key = child_key(field);
  let root_subscription = $watershed.subscribe_typed(
    root,
    (event) => {
      if (event instanceof $map_kernel.ValueChanged) {
        let key = event.key;
        if (key === workspace_key) {
          return reopen_workspace(runtime);
        } else {
          return undefined;
        }
      } else {
        return reopen_workspace(runtime);
      }
    },
  );
  let runtime$1 = new Runtime(
    runtime.document,
    runtime.root,
    runtime.field,
    runtime.catalog,
    runtime.context_for,
    runtime.scheduler,
    runtime.on_change,
    runtime.on_report,
    runtime.state,
    new Some(root_subscription),
  );
  reopen_workspace(runtime$1);
  return runtime$1;
}

/**
 * The lifecycle states, sorted by instance ID.
 */
export function lifecycle(runtime) {
  let _pipe = get_state(runtime).lifecycle;
  let _pipe$1 = $dict.to_list(_pipe);
  return $list.sort(_pipe$1, (a, b) => { return $string.compare(a[0], b[0]); });
}

/**
 * The latest effective workspace layout.
 */
export function layout(runtime) {
  let $ = get_state(runtime).snapshot;
  if ($ instanceof Some) {
    let snapshot = $[0];
    return $workspace.layout(snapshot);
  } else {
    return $List$Empty$const;
  }
}

/**
 * The latest effective connection graph.
 */
export function graph(runtime) {
  return $option.map(get_state(runtime).snapshot, $workspace.graph);
}

/**
 * Read one ready instance's running value.
 */
export function running(runtime, instance_id) {
  let _pipe = $dict.get(get_state(runtime).instances, instance_id);
  return $result.map(_pipe, (instance) => { return instance.running; });
}

function command_owned(runtime, instance_id, action) {
  let state = get_state(runtime);
  return $result.try$(
    (() => {
      let _pipe = $dict.get(state.instances, instance_id);
      return $result.map_error(
        _pipe,
        (_) => { return new InstanceNotReady(instance_id); },
      );
    })(),
    (instance) => {
      return $result.try$(
        invoke_hook(
          runtime,
          instance_id,
          "action",
          () => { return action(instance.running); },
        ),
        (outcome) => {
          return $result.try$(
            check_running(runtime),
            (_) => {
              return $result.try$(
                (() => {
                  let _pipe = outcome;
                  return $result.map_error(
                    _pipe,
                    (reason) => { return new ActionFailed(instance_id, reason); },
                  );
                })(),
                (outcome) => {
                  return $result.try$(
                    (() => {
                      let _pipe = validate_outputs(instance, outcome[1]);
                      return $result.map_error(
                        _pipe,
                        (reason) => {
                          return new ComponentFailed(instance_id, reason);
                        },
                      );
                    })(),
                    (_) => {
                      return $result.try$(
                        check_running(runtime),
                        (_) => {
                          let instance$1 = new RunningInstance(
                            instance.entry,
                            instance.identity,
                            instance.generation,
                            instance.descriptor,
                            outcome[0],
                            instance.disable_output,
                          );
                          let output_count = $list.length(outcome[1]);
                          let state$1 = get_state(runtime);
                          let state$2 = new State(
                            state$1.workspace,
                            state$1.workspace_subscription,
                            $dict.insert(
                              state$1.instances,
                              instance_id,
                              instance$1,
                            ),
                            state$1.pending,
                            state$1.failed,
                            state$1.lifecycle,
                            state$1.snapshot,
                            state$1.next_generation,
                            state$1.next_trace + output_count,
                            state$1.workspace_generation,
                            state$1.reconcile_armed,
                            state$1.notify_armed,
                            state$1.operation_active,
                            state$1.hook_failed,
                            state$1.stopped,
                          );
                          set_state(runtime, state$2);
                          notify(runtime);
                          let $ = state$2.snapshot;
                          let $1 = outcome[1];
                          if ($1 instanceof $Empty) {
                            return new Ok(undefined);
                          } else if ($ instanceof Some) {
                            let outputs = $1;
                            let snapshot = $[0];
                            let graph$1 = $workspace.graph(snapshot);
                            dispatch_outputs(
                              runtime,
                              graph$1,
                              instance_id,
                              outputs,
                              (state$2.next_trace - output_count) + 1,
                            );
                            let $2 = get_state(runtime).hook_failed;
                            if ($2) {
                              return new Ok(undefined);
                            } else {
                              return check_running(runtime);
                            }
                          } else {
                            return new Error(new InstanceNotReady(instance_id));
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Apply one host action and route its typed output events.
 *
 * Nested commands return `RuntimeBusy`. A stopped runtime returns
 * `RuntimeStopped`. Reads remain available during an operation.
 *
 * `Ok(Nil)` accepts the source state and output batch. Delivery failures are
 * reported separately. Acceptance does not acknowledge sequencing or undo
 * channel mutations that the action has already submitted.
 */
export function command(runtime, instance_id, action) {
  return $result.try$(
    check_running(runtime),
    (_) => {
      let state = get_state(runtime);
      let $ = state.operation_active;
      if ($) {
        return new Error(RuntimeError$RuntimeBusy$const);
      } else {
        set_state(
          runtime,
          new State(
            state.workspace,
            state.workspace_subscription,
            state.instances,
            state.pending,
            state.failed,
            state.lifecycle,
            state.snapshot,
            state.next_generation,
            state.next_trace,
            state.workspace_generation,
            state.reconcile_armed,
            state.notify_armed,
            true,
            state.hook_failed,
            state.stopped,
          ),
        );
        let outcome = command_owned(runtime, instance_id, action);
        release_operation(runtime);
        return outcome;
      }
    },
  );
}

/**
 * Stop the runtime and every running component.
 *
 * Cleanup errors are returned after all instances and subscriptions have had
 * a chance to stop. The runtime is terminal before cleanup starts. A stop
 * during an action prevents the action from committing its returned state.
 */
export function stop(runtime) {
  let _pipe = stop_owned(runtime);
  return $list.map(_pipe, (failure) => { return failure[1]; });
}

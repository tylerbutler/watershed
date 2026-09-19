import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $watershed from "../watershed.d.mts";
import type * as $component from "../watershed/component.d.mts";
import type * as $component_runtime from "../watershed/component_runtime.d.mts";
import type * as $dispatch from "../watershed/dispatch.d.mts";
import type * as $port from "../watershed/port.d.mts";
import type * as $port_graph from "../watershed/port_graph.d.mts";
import type * as $schema from "../watershed/schema.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";
import type * as $workspace from "../watershed/workspace.d.mts";
import type * as $workspace_js from "../watershed/workspace_js.d.mts";

export class RuntimeBusy extends _.CustomType {}
export function RuntimeError$RuntimeBusy(): RuntimeError$;
export function RuntimeError$isRuntimeBusy(value: any): value is RuntimeError$;

export class RuntimeStopped extends _.CustomType {}
export function RuntimeError$RuntimeStopped(): RuntimeError$;
export function RuntimeError$isRuntimeStopped(
  value: any,
): value is RuntimeError$;

export class DuplicateStartCompletion extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string);
  /** @deprecated */
  instance_id: string;
}
export function RuntimeError$DuplicateStartCompletion(
  instance_id: string,
): RuntimeError$;
export function RuntimeError$isDuplicateStartCompletion(
  value: any,
): value is RuntimeError$;
export function RuntimeError$DuplicateStartCompletion$0(value: RuntimeError$): string;
export function RuntimeError$DuplicateStartCompletion$instance_id(
  value: RuntimeError$,
): string;

export class HookThrew extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, hook: string, reason: string);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  hook: string;
  /** @deprecated */
  reason: string;
}
export function RuntimeError$HookThrew(
  instance_id: string,
  hook: string,
  reason: string,
): RuntimeError$;
export function RuntimeError$isHookThrew(value: any): value is RuntimeError$;
export function RuntimeError$HookThrew$0(value: RuntimeError$): string;
export function RuntimeError$HookThrew$instance_id(value: RuntimeError$): string;
export function RuntimeError$HookThrew$1(
  value: RuntimeError$,
): string;
export function RuntimeError$HookThrew$hook(value: RuntimeError$): string;
export function RuntimeError$HookThrew$2(value: RuntimeError$): string;
export function RuntimeError$HookThrew$reason(value: RuntimeError$): string;

export class InstanceNotReady extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string);
  /** @deprecated */
  instance_id: string;
}
export function RuntimeError$InstanceNotReady(
  instance_id: string,
): RuntimeError$;
export function RuntimeError$isInstanceNotReady(
  value: any,
): value is RuntimeError$;
export function RuntimeError$InstanceNotReady$0(value: RuntimeError$): string;
export function RuntimeError$InstanceNotReady$instance_id(value: RuntimeError$): string;

export class ActionFailed extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: string);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: string;
}
export function RuntimeError$ActionFailed(
  instance_id: string,
  reason: string,
): RuntimeError$;
export function RuntimeError$isActionFailed(value: any): value is RuntimeError$;
export function RuntimeError$ActionFailed$0(value: RuntimeError$): string;
export function RuntimeError$ActionFailed$instance_id(value: RuntimeError$): string;
export function RuntimeError$ActionFailed$1(
  value: RuntimeError$,
): string;
export function RuntimeError$ActionFailed$reason(value: RuntimeError$): string;

export class ComponentFailed extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: $component.ComponentError$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: $component.ComponentError$;
}
export function RuntimeError$ComponentFailed(
  instance_id: string,
  reason: $component.ComponentError$,
): RuntimeError$;
export function RuntimeError$isComponentFailed(
  value: any,
): value is RuntimeError$;
export function RuntimeError$ComponentFailed$0(value: RuntimeError$): string;
export function RuntimeError$ComponentFailed$instance_id(value: RuntimeError$): string;
export function RuntimeError$ComponentFailed$1(
  value: RuntimeError$,
): $component.ComponentError$;
export function RuntimeError$ComponentFailed$reason(value: RuntimeError$): $component.ComponentError$;

export class PreparationFailed extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: $workspace.PreparationError$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: $workspace.PreparationError$;
}
export function RuntimeError$PreparationFailed(
  instance_id: string,
  reason: $workspace.PreparationError$,
): RuntimeError$;
export function RuntimeError$isPreparationFailed(
  value: any,
): value is RuntimeError$;
export function RuntimeError$PreparationFailed$0(value: RuntimeError$): string;
export function RuntimeError$PreparationFailed$instance_id(value: RuntimeError$): string;
export function RuntimeError$PreparationFailed$1(
  value: RuntimeError$,
): $workspace.PreparationError$;
export function RuntimeError$PreparationFailed$reason(value: RuntimeError$): $workspace.PreparationError$;

export class CatalogChanged extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: $component.LookupError$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: $component.LookupError$;
}
export function RuntimeError$CatalogChanged(
  instance_id: string,
  reason: $component.LookupError$,
): RuntimeError$;
export function RuntimeError$isCatalogChanged(
  value: any,
): value is RuntimeError$;
export function RuntimeError$CatalogChanged$0(value: RuntimeError$): string;
export function RuntimeError$CatalogChanged$instance_id(value: RuntimeError$): string;
export function RuntimeError$CatalogChanged$1(
  value: RuntimeError$,
): $component.LookupError$;
export function RuntimeError$CatalogChanged$reason(value: RuntimeError$): $component.LookupError$;

export class WorkspaceFailed extends _.CustomType {
  /** @deprecated */
  constructor(reason: $workspace_js.WorkspaceError$);
  /** @deprecated */
  reason: $workspace_js.WorkspaceError$;
}
export function RuntimeError$WorkspaceFailed(
  reason: $workspace_js.WorkspaceError$,
): RuntimeError$;
export function RuntimeError$isWorkspaceFailed(
  value: any,
): value is RuntimeError$;
export function RuntimeError$WorkspaceFailed$0(value: RuntimeError$): $workspace_js.WorkspaceError$;
export function RuntimeError$WorkspaceFailed$reason(
  value: RuntimeError$,
): $workspace_js.WorkspaceError$;

export type RuntimeError$ = RuntimeBusy | RuntimeStopped | DuplicateStartCompletion | HookThrew | InstanceNotReady | ActionFailed | ComponentFailed | PreparationFailed | CatalogChanged | WorkspaceFailed;

export class Loading extends _.CustomType {
  /** @deprecated */
  constructor(entry: $workspace.ManifestEntry$, reason: string);
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
  /** @deprecated */
  reason: string;
}
export function LifecycleState$Loading(
  entry: $workspace.ManifestEntry$,
  reason: string,
): LifecycleState$;
export function LifecycleState$isLoading(value: any): value is LifecycleState$;
export function LifecycleState$Loading$0(value: LifecycleState$): $workspace.ManifestEntry$;
export function LifecycleState$Loading$entry(
  value: LifecycleState$,
): $workspace.ManifestEntry$;
export function LifecycleState$Loading$1(value: LifecycleState$): string;
export function LifecycleState$Loading$reason(value: LifecycleState$): string;

export class Starting extends _.CustomType {
  /** @deprecated */
  constructor(entry: $workspace.ManifestEntry$);
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
}
export function LifecycleState$Starting(
  entry: $workspace.ManifestEntry$,
): LifecycleState$;
export function LifecycleState$isStarting(value: any): value is LifecycleState$;
export function LifecycleState$Starting$0(value: LifecycleState$): $workspace.ManifestEntry$;
export function LifecycleState$Starting$entry(
  value: LifecycleState$,
): $workspace.ManifestEntry$;

export class Ready extends _.CustomType {
  /** @deprecated */
  constructor(entry: $workspace.ManifestEntry$);
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
}
export function LifecycleState$Ready(
  entry: $workspace.ManifestEntry$,
): LifecycleState$;
export function LifecycleState$isReady(value: any): value is LifecycleState$;
export function LifecycleState$Ready$0(value: LifecycleState$): $workspace.ManifestEntry$;
export function LifecycleState$Ready$entry(
  value: LifecycleState$,
): $workspace.ManifestEntry$;

export class Unavailable extends _.CustomType {
  /** @deprecated */
  constructor(entry: $workspace.ManifestEntry$, reason: $component.LookupError$);
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
  /** @deprecated */
  reason: $component.LookupError$;
}
export function LifecycleState$Unavailable(
  entry: $workspace.ManifestEntry$,
  reason: $component.LookupError$,
): LifecycleState$;
export function LifecycleState$isUnavailable(
  value: any,
): value is LifecycleState$;
export function LifecycleState$Unavailable$0(value: LifecycleState$): $workspace.ManifestEntry$;
export function LifecycleState$Unavailable$entry(
  value: LifecycleState$,
): $workspace.ManifestEntry$;
export function LifecycleState$Unavailable$1(value: LifecycleState$): $component.LookupError$;
export function LifecycleState$Unavailable$reason(
  value: LifecycleState$,
): $component.LookupError$;

export class Failed extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: RuntimeError$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: RuntimeError$;
}
export function LifecycleState$Failed(
  instance_id: string,
  reason: RuntimeError$,
): LifecycleState$;
export function LifecycleState$isFailed(value: any): value is LifecycleState$;
export function LifecycleState$Failed$0(value: LifecycleState$): string;
export function LifecycleState$Failed$instance_id(value: LifecycleState$): string;
export function LifecycleState$Failed$1(
  value: LifecycleState$,
): RuntimeError$;
export function LifecycleState$Failed$reason(value: LifecycleState$): RuntimeError$;

export type LifecycleState$ = Loading | Starting | Ready | Unavailable | Failed;

export class PlanningFailed extends _.CustomType {
  /** @deprecated */
  constructor(reason: $dispatch.DispatchError$);
  /** @deprecated */
  reason: $dispatch.DispatchError$;
}
export function DispatchFailure$PlanningFailed(
  reason: $dispatch.DispatchError$,
): DispatchFailure$;
export function DispatchFailure$isPlanningFailed(
  value: any,
): value is DispatchFailure$;
export function DispatchFailure$PlanningFailed$0(value: DispatchFailure$): $dispatch.DispatchError$;
export function DispatchFailure$PlanningFailed$reason(
  value: DispatchFailure$,
): $dispatch.DispatchError$;

export class SourceNotReady extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string);
  /** @deprecated */
  instance_id: string;
}
export function DispatchFailure$SourceNotReady(
  instance_id: string,
): DispatchFailure$;
export function DispatchFailure$isSourceNotReady(
  value: any,
): value is DispatchFailure$;
export function DispatchFailure$SourceNotReady$0(value: DispatchFailure$): string;
export function DispatchFailure$SourceNotReady$instance_id(
  value: DispatchFailure$,
): string;

export class SourceOutputRejected extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: $component.ComponentError$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: $component.ComponentError$;
}
export function DispatchFailure$SourceOutputRejected(
  instance_id: string,
  reason: $component.ComponentError$,
): DispatchFailure$;
export function DispatchFailure$isSourceOutputRejected(
  value: any,
): value is DispatchFailure$;
export function DispatchFailure$SourceOutputRejected$0(value: DispatchFailure$): string;
export function DispatchFailure$SourceOutputRejected$instance_id(
  value: DispatchFailure$,
): string;
export function DispatchFailure$SourceOutputRejected$1(value: DispatchFailure$): $component.ComponentError$;
export function DispatchFailure$SourceOutputRejected$reason(
  value: DispatchFailure$,
): $component.ComponentError$;

export class TargetNotReady extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string);
  /** @deprecated */
  instance_id: string;
}
export function DispatchFailure$TargetNotReady(
  instance_id: string,
): DispatchFailure$;
export function DispatchFailure$isTargetNotReady(
  value: any,
): value is DispatchFailure$;
export function DispatchFailure$TargetNotReady$0(value: DispatchFailure$): string;
export function DispatchFailure$TargetNotReady$instance_id(
  value: DispatchFailure$,
): string;

export class TargetInputRejected extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: $component.ComponentError$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: $component.ComponentError$;
}
export function DispatchFailure$TargetInputRejected(
  instance_id: string,
  reason: $component.ComponentError$,
): DispatchFailure$;
export function DispatchFailure$isTargetInputRejected(
  value: any,
): value is DispatchFailure$;
export function DispatchFailure$TargetInputRejected$0(value: DispatchFailure$): string;
export function DispatchFailure$TargetInputRejected$instance_id(
  value: DispatchFailure$,
): string;
export function DispatchFailure$TargetInputRejected$1(value: DispatchFailure$): $component.ComponentError$;
export function DispatchFailure$TargetInputRejected$reason(
  value: DispatchFailure$,
): $component.ComponentError$;

export type DispatchFailure$ = PlanningFailed | SourceNotReady | SourceOutputRejected | TargetNotReady | TargetInputRejected;

export class Triggered extends _.CustomType {
  /** @deprecated */
  constructor(trace_id: string, source: $port_graph.PortRef$);
  /** @deprecated */
  trace_id: string;
  /** @deprecated */
  source: $port_graph.PortRef$;
}
export function DispatchReport$Triggered(
  trace_id: string,
  source: $port_graph.PortRef$,
): DispatchReport$;
export function DispatchReport$isTriggered(
  value: any,
): value is DispatchReport$;
export function DispatchReport$Triggered$0(value: DispatchReport$): string;
export function DispatchReport$Triggered$trace_id(value: DispatchReport$): string;
export function DispatchReport$Triggered$1(
  value: DispatchReport$,
): $port_graph.PortRef$;
export function DispatchReport$Triggered$source(value: DispatchReport$): $port_graph.PortRef$;

export class LocalDelivered extends _.CustomType {
  /** @deprecated */
  constructor(trace_id: string, edge_id: string, target: $port_graph.PortRef$);
  /** @deprecated */
  trace_id: string;
  /** @deprecated */
  edge_id: string;
  /** @deprecated */
  target: $port_graph.PortRef$;
}
export function DispatchReport$LocalDelivered(
  trace_id: string,
  edge_id: string,
  target: $port_graph.PortRef$,
): DispatchReport$;
export function DispatchReport$isLocalDelivered(
  value: any,
): value is DispatchReport$;
export function DispatchReport$LocalDelivered$0(value: DispatchReport$): string;
export function DispatchReport$LocalDelivered$trace_id(value: DispatchReport$): string;
export function DispatchReport$LocalDelivered$1(
  value: DispatchReport$,
): string;
export function DispatchReport$LocalDelivered$edge_id(value: DispatchReport$): string;
export function DispatchReport$LocalDelivered$2(
  value: DispatchReport$,
): $port_graph.PortRef$;
export function DispatchReport$LocalDelivered$target(value: DispatchReport$): $port_graph.PortRef$;

export class MutationSubmitted extends _.CustomType {
  /** @deprecated */
  constructor(trace_id: string, edge_id: string, target: $port_graph.PortRef$);
  /** @deprecated */
  trace_id: string;
  /** @deprecated */
  edge_id: string;
  /** @deprecated */
  target: $port_graph.PortRef$;
}
export function DispatchReport$MutationSubmitted(
  trace_id: string,
  edge_id: string,
  target: $port_graph.PortRef$,
): DispatchReport$;
export function DispatchReport$isMutationSubmitted(
  value: any,
): value is DispatchReport$;
export function DispatchReport$MutationSubmitted$0(value: DispatchReport$): string;
export function DispatchReport$MutationSubmitted$trace_id(
  value: DispatchReport$,
): string;
export function DispatchReport$MutationSubmitted$1(value: DispatchReport$): string;
export function DispatchReport$MutationSubmitted$edge_id(
  value: DispatchReport$,
): string;
export function DispatchReport$MutationSubmitted$2(value: DispatchReport$): $port_graph.PortRef$;
export function DispatchReport$MutationSubmitted$target(
  value: DispatchReport$,
): $port_graph.PortRef$;

export class DispatchFailed extends _.CustomType {
  /** @deprecated */
  constructor(
    trace_id: string,
    edge_id: $option.Option$<string>,
    reason: DispatchFailure$
  );
  /** @deprecated */
  trace_id: string;
  /** @deprecated */
  edge_id: $option.Option$<string>;
  /** @deprecated */
  reason: DispatchFailure$;
}
export function DispatchReport$DispatchFailed(
  trace_id: string,
  edge_id: $option.Option$<string>,
  reason: DispatchFailure$,
): DispatchReport$;
export function DispatchReport$isDispatchFailed(
  value: any,
): value is DispatchReport$;
export function DispatchReport$DispatchFailed$0(value: DispatchReport$): string;
export function DispatchReport$DispatchFailed$trace_id(value: DispatchReport$): string;
export function DispatchReport$DispatchFailed$1(
  value: DispatchReport$,
): $option.Option$<string>;
export function DispatchReport$DispatchFailed$edge_id(value: DispatchReport$): $option.Option$<
  string
>;
export function DispatchReport$DispatchFailed$2(value: DispatchReport$): DispatchFailure$;
export function DispatchReport$DispatchFailed$reason(
  value: DispatchReport$,
): DispatchFailure$;

export class RuntimeFailed extends _.CustomType {
  /** @deprecated */
  constructor(reason: RuntimeError$);
  /** @deprecated */
  reason: RuntimeError$;
}
export function DispatchReport$RuntimeFailed(
  reason: RuntimeError$,
): DispatchReport$;
export function DispatchReport$isRuntimeFailed(
  value: any,
): value is DispatchReport$;
export function DispatchReport$RuntimeFailed$0(value: DispatchReport$): RuntimeError$;
export function DispatchReport$RuntimeFailed$reason(
  value: DispatchReport$,
): RuntimeError$;

export type DispatchReport$ = Triggered | LocalDelivered | MutationSubmitted | DispatchFailed | RuntimeFailed;

declare class RunningInstance<BMRC, BMRD> extends _.CustomType {
  /** @deprecated */
  constructor(
    entry: $workspace.ManifestEntry$,
    identity: $component_runtime.InstanceIdentity$,
    generation: number,
    descriptor: $component.Descriptor$<BMRC, BMRD>,
    running: BMRD,
    disable_output: () => undefined
  );
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
  /** @deprecated */
  identity: $component_runtime.InstanceIdentity$;
  /** @deprecated */
  generation: number;
  /** @deprecated */
  descriptor: $component.Descriptor$<BMRC, BMRD>;
  /** @deprecated */
  running: BMRD;
  /** @deprecated */
  disable_output: () => undefined;
}

type RunningInstance$<BMRC, BMRD> = RunningInstance<BMRC, BMRD>;

declare class PendingStart extends _.CustomType {
  /** @deprecated */
  constructor(
    entry: $workspace.ManifestEntry$,
    identity: $component_runtime.InstanceIdentity$,
    generation: number,
    disable_output: () => undefined
  );
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
  /** @deprecated */
  identity: $component_runtime.InstanceIdentity$;
  /** @deprecated */
  generation: number;
  /** @deprecated */
  disable_output: () => undefined;
}

type PendingStart$ = PendingStart;

declare class State<BMRE, BMRF, BMRG> extends _.CustomType {
  /** @deprecated */
  constructor(
    workspace: $option.Option$<$workspace_js.Workspace$<BMRE>>,
    workspace_subscription: $option.Option$<$workspace_js.Subscription$>,
    instances: $dict.Dict$<string, RunningInstance$<BMRF, BMRG>>,
    pending: $dict.Dict$<string, PendingStart$>,
    failed: $dict.Dict$<string, $component_runtime.InstanceIdentity$>,
    lifecycle: $dict.Dict$<string, LifecycleState$>,
    snapshot: $option.Option$<$workspace.Snapshot$>,
    next_generation: number,
    next_trace: number,
    workspace_generation: number,
    reconcile_armed: boolean,
    notify_armed: boolean,
    operation_active: boolean,
    hook_failed: boolean,
    stopped: boolean
  );
  /** @deprecated */
  workspace: $option.Option$<$workspace_js.Workspace$<BMRE>>;
  /** @deprecated */
  workspace_subscription: $option.Option$<$workspace_js.Subscription$>;
  /** @deprecated */
  instances: $dict.Dict$<string, RunningInstance$<BMRF, BMRG>>;
  /** @deprecated */
  pending: $dict.Dict$<string, PendingStart$>;
  /** @deprecated */
  failed: $dict.Dict$<string, $component_runtime.InstanceIdentity$>;
  /** @deprecated */
  lifecycle: $dict.Dict$<string, LifecycleState$>;
  /** @deprecated */
  snapshot: $option.Option$<$workspace.Snapshot$>;
  /** @deprecated */
  next_generation: number;
  /** @deprecated */
  next_trace: number;
  /** @deprecated */
  workspace_generation: number;
  /** @deprecated */
  reconcile_armed: boolean;
  /** @deprecated */
  notify_armed: boolean;
  /** @deprecated */
  operation_active: boolean;
  /** @deprecated */
  hook_failed: boolean;
  /** @deprecated */
  stopped: boolean;
}

type State$<BMRE, BMRF, BMRG> = State<BMRE, BMRF, BMRG>;

declare class Runtime<BMRH, BMRI, BMRJ> extends _.CustomType {
  /** @deprecated */
  constructor(
    document: $watershed.Document$<BMRH>,
    root: $watershed.TypedMap$<BMRH>,
    field: $schema.ChildField$<BMRH, $workspace.WorkspaceSchema$>,
    catalog: $component.Catalog$<BMRI, BMRJ>,
    context_for: (
      x0: $workspace.ManifestEntry$,
      x1: $watershed.SharedMap$,
      x2: () => undefined,
      x3: $component.OutputEmitter$
    ) => BMRI,
    scheduler: $transport_js.Scheduler$,
    on_change: () => undefined,
    on_report: (x0: DispatchReport$) => undefined,
    state: $transport_js.Cell$<State$<BMRH, BMRI, BMRJ>>,
    root_subscription: $option.Option$<$watershed.SubscriptionToken$>
  );
  /** @deprecated */
  document: $watershed.Document$<BMRH>;
  /** @deprecated */
  root: $watershed.TypedMap$<BMRH>;
  /** @deprecated */
  field: $schema.ChildField$<BMRH, $workspace.WorkspaceSchema$>;
  /** @deprecated */
  catalog: $component.Catalog$<BMRI, BMRJ>;
  /** @deprecated */
  context_for: (
    x0: $workspace.ManifestEntry$,
    x1: $watershed.SharedMap$,
    x2: () => undefined,
    x3: $component.OutputEmitter$
  ) => BMRI;
  /** @deprecated */
  scheduler: $transport_js.Scheduler$;
  /** @deprecated */
  on_change: () => undefined;
  /** @deprecated */
  on_report: (x0: DispatchReport$) => undefined;
  /** @deprecated */
  state: $transport_js.Cell$<State$<BMRH, BMRI, BMRJ>>;
  /** @deprecated */
  root_subscription: $option.Option$<$watershed.SubscriptionToken$>;
}

export type Runtime$<BMRH, BMRI, BMRJ> = Runtime<BMRH, BMRI, BMRJ>;

export function start<BMRK, BMRQ, BMRR>(
  document: $watershed.Document$<BMRK>,
  root: $watershed.TypedMap$<BMRK>,
  field: $schema.ChildField$<BMRK, $workspace.WorkspaceSchema$>,
  x3: $workspace_js.Workspace$<BMRK>,
  catalog: $component.Catalog$<BMRQ, BMRR>,
  context_for: (
    x0: $workspace.ManifestEntry$,
    x1: $watershed.SharedMap$,
    x2: () => undefined,
    x3: $component.OutputEmitter$
  ) => BMRQ,
  scheduler: $transport_js.Scheduler$,
  on_change: () => undefined,
  on_report: (x0: DispatchReport$) => undefined
): Runtime$<BMRK, BMRQ, BMRR>;

export function lifecycle(runtime: Runtime$<any, any, any>): _.List<
  [string, LifecycleState$]
>;

export function layout(runtime: Runtime$<any, any, any>): _.List<string>;

export function graph(runtime: Runtime$<any, any, any>): $option.Option$<
  $port_graph.EffectiveGraph$
>;

export function running<BMSU>(
  runtime: Runtime$<any, any, BMSU>,
  instance_id: string
): _.Result<BMSU, undefined>;

export function command<BMTC>(
  runtime: Runtime$<any, any, BMTC>,
  instance_id: string,
  action: (x0: BMTC) => _.Result<
    [BMTC, _.List<$component.OutputEvent$>],
    string
  >
): _.Result<undefined, RuntimeError$>;

export function stop(runtime: Runtime$<any, any, any>): _.List<
  $component.ComponentError$
>;

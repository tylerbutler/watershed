import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $component from "../watershed/component.d.mts";
import type * as $dispatch from "../watershed/dispatch.d.mts";
import type * as $workspace from "../watershed/workspace.d.mts";

declare class InstanceIdentity extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: string,
    version: number,
    config: string,
    child_handle: string
  );
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  config: string;
  /** @deprecated */
  child_handle: string;
}

export type InstanceIdentity$ = InstanceIdentity;

export class CurrentInstance extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, identity: InstanceIdentity$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  identity: InstanceIdentity$;
}
export function CurrentInstance$CurrentInstance(
  instance_id: string,
  identity: InstanceIdentity$,
): CurrentInstance$;
export function CurrentInstance$isCurrentInstance(
  value: any,
): value is CurrentInstance$;
export function CurrentInstance$CurrentInstance$0(value: CurrentInstance$): string;
export function CurrentInstance$CurrentInstance$instance_id(
  value: CurrentInstance$,
): string;
export function CurrentInstance$CurrentInstance$1(value: CurrentInstance$): InstanceIdentity$;
export function CurrentInstance$CurrentInstance$identity(
  value: CurrentInstance$,
): InstanceIdentity$;

export type CurrentInstance$ = CurrentInstance;

export class StartInstance<BLXF> extends _.CustomType {
  /** @deprecated */
  constructor(
    entry: $workspace.ManifestEntry$,
    identity: InstanceIdentity$,
    subtree: BLXF
  );
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
  /** @deprecated */
  identity: InstanceIdentity$;
  /** @deprecated */
  subtree: BLXF;
}
export function StartInstance$StartInstance<BLXF>(
  entry: $workspace.ManifestEntry$,
  identity: InstanceIdentity$,
  subtree: BLXF,
): StartInstance$<BLXF>;
export function StartInstance$isStartInstance<BLXF>(
  value: any,
): value is StartInstance$<unknown>;
export function StartInstance$StartInstance$0<BLXF>(value: StartInstance$<BLXF>): $workspace.ManifestEntry$;
export function StartInstance$StartInstance$entry<BLXF>(
  value: StartInstance$<BLXF>,
): $workspace.ManifestEntry$;
export function StartInstance$StartInstance$1<BLXF>(value: StartInstance$<BLXF>): InstanceIdentity$;
export function StartInstance$StartInstance$identity<BLXF>(
  value: StartInstance$<BLXF>,
): InstanceIdentity$;
export function StartInstance$StartInstance$2<BLXF>(value: StartInstance$<BLXF>): BLXF;
export function StartInstance$StartInstance$subtree<BLXF>(
  value: StartInstance$<BLXF>,
): BLXF;

export type StartInstance$<BLXF> = StartInstance<BLXF>;

export class Loading extends _.CustomType {
  /** @deprecated */
  constructor(entry: $workspace.ManifestEntry$, reason: string);
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
  /** @deprecated */
  reason: string;
}
export function BlockedInstance$Loading(
  entry: $workspace.ManifestEntry$,
  reason: string,
): BlockedInstance$;
export function BlockedInstance$isLoading(
  value: any,
): value is BlockedInstance$;
export function BlockedInstance$Loading$0(value: BlockedInstance$): $workspace.ManifestEntry$;
export function BlockedInstance$Loading$entry(
  value: BlockedInstance$,
): $workspace.ManifestEntry$;
export function BlockedInstance$Loading$1(value: BlockedInstance$): string;
export function BlockedInstance$Loading$reason(value: BlockedInstance$): string;

export class Unavailable extends _.CustomType {
  /** @deprecated */
  constructor(entry: $workspace.ManifestEntry$, reason: $component.LookupError$);
  /** @deprecated */
  entry: $workspace.ManifestEntry$;
  /** @deprecated */
  reason: $component.LookupError$;
}
export function BlockedInstance$Unavailable(
  entry: $workspace.ManifestEntry$,
  reason: $component.LookupError$,
): BlockedInstance$;
export function BlockedInstance$isUnavailable(
  value: any,
): value is BlockedInstance$;
export function BlockedInstance$Unavailable$0(value: BlockedInstance$): $workspace.ManifestEntry$;
export function BlockedInstance$Unavailable$entry(
  value: BlockedInstance$,
): $workspace.ManifestEntry$;
export function BlockedInstance$Unavailable$1(value: BlockedInstance$): $component.LookupError$;
export function BlockedInstance$Unavailable$reason(
  value: BlockedInstance$,
): $component.LookupError$;

export class Failed extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: $workspace.PreparationError$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: $workspace.PreparationError$;
}
export function BlockedInstance$Failed(
  instance_id: string,
  reason: $workspace.PreparationError$,
): BlockedInstance$;
export function BlockedInstance$isFailed(value: any): value is BlockedInstance$;
export function BlockedInstance$Failed$0(value: BlockedInstance$): string;
export function BlockedInstance$Failed$instance_id(value: BlockedInstance$): string;
export function BlockedInstance$Failed$1(
  value: BlockedInstance$,
): $workspace.PreparationError$;
export function BlockedInstance$Failed$reason(value: BlockedInstance$): $workspace.PreparationError$;

export type BlockedInstance$ = Loading | Unavailable | Failed;

declare class ReconcilePlan<BLXG> extends _.CustomType {
  /** @deprecated */
  constructor(
    stop_ids: _.List<string>,
    keep_ids: _.List<string>,
    starts: _.List<StartInstance$<BLXG>>,
    blocked: _.List<BlockedInstance$>
  );
  /** @deprecated */
  stop_ids: _.List<string>;
  /** @deprecated */
  keep_ids: _.List<string>;
  /** @deprecated */
  starts: _.List<StartInstance$<BLXG>>;
  /** @deprecated */
  blocked: _.List<BlockedInstance$>;
}

export type ReconcilePlan$<BLXG> = ReconcilePlan<BLXG>;

declare class DispatchTrace extends _.CustomType {
  /** @deprecated */
  constructor(
    id: string,
    pending: _.List<$dispatch.Delivery$>,
    seen_edges: _.List<string>
  );
  /** @deprecated */
  id: string;
  /** @deprecated */
  pending: _.List<$dispatch.Delivery$>;
  /** @deprecated */
  seen_edges: _.List<string>;
}

export type DispatchTrace$ = DispatchTrace;

export function identity(entry: $workspace.ManifestEntry$): InstanceIdentity$;

export function reconcile<BLXI>(
  current: _.List<CurrentInstance$>,
  prepared: _.List<$workspace.PreparationState$<BLXI>>
): ReconcilePlan$<BLXI>;

export function stops(plan: ReconcilePlan$<any>): _.List<string>;

export function keeps(plan: ReconcilePlan$<any>): _.List<string>;

export function starts<BLXS>(plan: ReconcilePlan$<BLXS>): _.List<
  StartInstance$<BLXS>
>;

export function blocked(plan: ReconcilePlan$<any>): _.List<BlockedInstance$>;

export function new_trace(id: string): DispatchTrace$;

export function trace_id(trace: DispatchTrace$): string;

export function enqueue(
  trace: DispatchTrace$,
  deliveries: _.List<$dispatch.Delivery$>
): DispatchTrace$;

export function next(trace: DispatchTrace$): [
  $option.Option$<$dispatch.Delivery$>,
  DispatchTrace$
];

export function is_empty(trace: DispatchTrace$): boolean;

export function seen_edges(trace: DispatchTrace$): _.List<string>;

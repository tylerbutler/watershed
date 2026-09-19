import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $g_set from "../../lattice_sets/lattice_sets/g_set.d.mts";
import type * as _ from "../gleam.d.mts";

export class GSetState extends _.CustomType {
  /** @deprecated */
  constructor(
    sequenced: $g_set.GSet$<string>,
    optimistic: $g_set.GSet$<string>,
    pending: _.List<PendingOperation$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  sequenced: $g_set.GSet$<string>;
  /** @deprecated */
  optimistic: $g_set.GSet$<string>;
  /** @deprecated */
  pending: _.List<PendingOperation$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function GSetState$GSetState(
  sequenced: $g_set.GSet$<string>,
  optimistic: $g_set.GSet$<string>,
  pending: _.List<PendingOperation$>,
  next_pending_message_id: number,
): GSetState$;
export function GSetState$isGSetState(value: any): value is GSetState$;
export function GSetState$GSetState$0(value: GSetState$): $g_set.GSet$<string>;
export function GSetState$GSetState$sequenced(value: GSetState$): $g_set.GSet$<
  string
>;
export function GSetState$GSetState$1(value: GSetState$): $g_set.GSet$<string>;
export function GSetState$GSetState$optimistic(value: GSetState$): $g_set.GSet$<
  string
>;
export function GSetState$GSetState$2(value: GSetState$): _.List<
  PendingOperation$
>;
export function GSetState$GSetState$pending(value: GSetState$): _.List<
  PendingOperation$
>;
export function GSetState$GSetState$3(value: GSetState$): number;
export function GSetState$GSetState$next_pending_message_id(value: GSetState$): number;

export type GSetState$ = GSetState;

export class PendingOperation extends _.CustomType {
  /** @deprecated */
  constructor(operation: GSetOperation$, message_id: number);
  /** @deprecated */
  operation: GSetOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOperation$PendingOperation(
  operation: GSetOperation$,
  message_id: number,
): PendingOperation$;
export function PendingOperation$isPendingOperation(
  value: any,
): value is PendingOperation$;
export function PendingOperation$PendingOperation$0(value: PendingOperation$): GSetOperation$;
export function PendingOperation$PendingOperation$operation(
  value: PendingOperation$,
): GSetOperation$;
export function PendingOperation$PendingOperation$1(value: PendingOperation$): number;
export function PendingOperation$PendingOperation$message_id(
  value: PendingOperation$,
): number;

export type PendingOperation$ = PendingOperation;

export class Add extends _.CustomType {
  /** @deprecated */
  constructor(element: string, delta: $g_set.GSet$<string>);
  /** @deprecated */
  element: string;
  /** @deprecated */
  delta: $g_set.GSet$<string>;
}
export function GSetOperation$Add(
  element: string,
  delta: $g_set.GSet$<string>,
): GSetOperation$;
export function GSetOperation$isAdd(value: any): value is GSetOperation$;
export function GSetOperation$Add$0(value: GSetOperation$): string;
export function GSetOperation$Add$element(value: GSetOperation$): string;
export function GSetOperation$Add$1(value: GSetOperation$): $g_set.GSet$<string>;
export function GSetOperation$Add$delta(
  value: GSetOperation$,
): $g_set.GSet$<string>;

export type GSetOperation$ = Add;

export class ElementAdded extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function GSetEvent$ElementAdded(element: string): GSetEvent$;
export function GSetEvent$isElementAdded(value: any): value is GSetEvent$;
export function GSetEvent$ElementAdded$0(value: GSetEvent$): string;
export function GSetEvent$ElementAdded$element(value: GSetEvent$): string;

export type GSetEvent$ = ElementAdded;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(detail: string): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(detail: string): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback;

export function KernelError$detail(value: KernelError$): string;

export function new$(): GSetState$;

export function contains(state: GSetState$, element: string): boolean;

export function values(state: GSetState$): _.List<string>;

export function sequenced_values(state: GSetState$): _.List<string>;

export function add(state: GSetState$, element: string): [
  GSetState$,
  _.List<GSetEvent$>,
  GSetOperation$,
  number
];

export function p2p_add(state: GSetState$, element: string): [
  GSetState$,
  _.List<GSetEvent$>,
  GSetOperation$
];

export function p2p_merge(state: GSetState$, other: $g_set.GSet$<string>): [
  GSetState$,
  _.List<GSetEvent$>
];

export function apply_remote(state: GSetState$, operation: GSetOperation$): [
  GSetState$,
  _.List<GSetEvent$>
];

export function ack_local(state: GSetState$, operation: GSetOperation$): _.Result<
  GSetState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: GSetState$,
  operation: GSetOperation$,
  message_id: number
): _.Result<GSetState$, KernelError$>;

export function rollback(
  state: GSetState$,
  operation: GSetOperation$,
  message_id: number
): _.Result<[GSetState$, _.List<GSetEvent$>], KernelError$>;

export function apply_stashed_operation(
  state: GSetState$,
  operation: GSetOperation$
): [GSetState$, _.List<GSetEvent$>, GSetOperation$, number];

export function promote_attach(state: GSetState$): GSetState$;

export function summary(state: GSetState$): $json.Json$;

export function from_sequenced(sequenced: $g_set.GSet$<string>): GSetState$;

export function from_summary(summary_json: string): _.Result<
  GSetState$,
  $json.DecodeError$
>;

export function check_cache_coherence(state: GSetState$): _.Result<
  undefined,
  string
>;

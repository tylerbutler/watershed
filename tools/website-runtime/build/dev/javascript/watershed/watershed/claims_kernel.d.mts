import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class ClaimsState extends _.CustomType {
  /** @deprecated */
  constructor(
    claims: $dict.Dict$<string, ClaimEntry$>,
    pending: $dict.Dict$<string, $json.Json$>
  );
  /** @deprecated */
  claims: $dict.Dict$<string, ClaimEntry$>;
  /** @deprecated */
  pending: $dict.Dict$<string, $json.Json$>;
}
export function ClaimsState$ClaimsState(
  claims: $dict.Dict$<string, ClaimEntry$>,
  pending: $dict.Dict$<string, $json.Json$>,
): ClaimsState$;
export function ClaimsState$isClaimsState(value: any): value is ClaimsState$;
export function ClaimsState$ClaimsState$0(value: ClaimsState$): $dict.Dict$<
  string,
  ClaimEntry$
>;
export function ClaimsState$ClaimsState$claims(value: ClaimsState$): $dict.Dict$<
  string,
  ClaimEntry$
>;
export function ClaimsState$ClaimsState$1(value: ClaimsState$): $dict.Dict$<
  string,
  $json.Json$
>;
export function ClaimsState$ClaimsState$pending(value: ClaimsState$): $dict.Dict$<
  string,
  $json.Json$
>;

export type ClaimsState$ = ClaimsState;

export class ClaimEntry extends _.CustomType {
  /** @deprecated */
  constructor(value: $json.Json$, sequence_number: number);
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  sequence_number: number;
}
export function ClaimEntry$ClaimEntry(
  value: $json.Json$,
  sequence_number: number,
): ClaimEntry$;
export function ClaimEntry$isClaimEntry(value: any): value is ClaimEntry$;
export function ClaimEntry$ClaimEntry$0(value: ClaimEntry$): $json.Json$;
export function ClaimEntry$ClaimEntry$value(value: ClaimEntry$): $json.Json$;
export function ClaimEntry$ClaimEntry$1(value: ClaimEntry$): number;
export function ClaimEntry$ClaimEntry$sequence_number(value: ClaimEntry$): number;

export type ClaimEntry$ = ClaimEntry;

export class Claim extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    value: $json.Json$,
    reference_sequence_number: number
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  reference_sequence_number: number;
}
export function ClaimOperation$Claim(
  key: string,
  value: $json.Json$,
  reference_sequence_number: number,
): ClaimOperation$;
export function ClaimOperation$isClaim(value: any): value is ClaimOperation$;
export function ClaimOperation$Claim$0(value: ClaimOperation$): string;
export function ClaimOperation$Claim$key(value: ClaimOperation$): string;
export function ClaimOperation$Claim$1(value: ClaimOperation$): $json.Json$;
export function ClaimOperation$Claim$value(value: ClaimOperation$): $json.Json$;
export function ClaimOperation$Claim$2(value: ClaimOperation$): number;
export function ClaimOperation$Claim$reference_sequence_number(value: ClaimOperation$): number;

export type ClaimOperation$ = Claim;

export class Claimed extends _.CustomType {
  /** @deprecated */
  constructor(key: string, local: boolean);
  /** @deprecated */
  key: string;
  /** @deprecated */
  local: boolean;
}
export function ClaimEvent$Claimed(key: string, local: boolean): ClaimEvent$;
export function ClaimEvent$isClaimed(value: any): value is ClaimEvent$;
export function ClaimEvent$Claimed$0(value: ClaimEvent$): string;
export function ClaimEvent$Claimed$key(value: ClaimEvent$): string;
export function ClaimEvent$Claimed$1(value: ClaimEvent$): boolean;
export function ClaimEvent$Claimed$local(value: ClaimEvent$): boolean;

export type ClaimEvent$ = Claimed;

export class Submitted extends _.CustomType {
  /** @deprecated */
  constructor(state: ClaimsState$, operation: ClaimOperation$);
  /** @deprecated */
  state: ClaimsState$;
  /** @deprecated */
  operation: ClaimOperation$;
}
export function SubmitResult$Submitted(
  state: ClaimsState$,
  operation: ClaimOperation$,
): SubmitResult$;
export function SubmitResult$isSubmitted(value: any): value is SubmitResult$;
export function SubmitResult$Submitted$0(value: SubmitResult$): ClaimsState$;
export function SubmitResult$Submitted$state(value: SubmitResult$): ClaimsState$;
export function SubmitResult$Submitted$1(
  value: SubmitResult$,
): ClaimOperation$;
export function SubmitResult$Submitted$operation(value: SubmitResult$): ClaimOperation$;

export class AlreadyClaimed extends _.CustomType {
  /** @deprecated */
  constructor(current_value: $json.Json$);
  /** @deprecated */
  current_value: $json.Json$;
}
export function SubmitResult$AlreadyClaimed(
  current_value: $json.Json$,
): SubmitResult$;
export function SubmitResult$isAlreadyClaimed(
  value: any,
): value is SubmitResult$;
export function SubmitResult$AlreadyClaimed$0(value: SubmitResult$): $json.Json$;
export function SubmitResult$AlreadyClaimed$current_value(
  value: SubmitResult$,
): $json.Json$;

export type SubmitResult$ = Submitted | AlreadyClaimed;

export class Accepted extends _.CustomType {
  /** @deprecated */
  constructor(value: $json.Json$);
  /** @deprecated */
  value: $json.Json$;
}
export function ClaimOutcome$Accepted(value: $json.Json$): ClaimOutcome$;
export function ClaimOutcome$isAccepted(value: any): value is ClaimOutcome$;
export function ClaimOutcome$Accepted$0(value: ClaimOutcome$): $json.Json$;
export function ClaimOutcome$Accepted$value(value: ClaimOutcome$): $json.Json$;

export class Lost extends _.CustomType {
  /** @deprecated */
  constructor(current_value: $option.Option$<$json.Json$>);
  /** @deprecated */
  current_value: $option.Option$<$json.Json$>;
}
export function ClaimOutcome$Lost(
  current_value: $option.Option$<$json.Json$>,
): ClaimOutcome$;
export function ClaimOutcome$isLost(value: any): value is ClaimOutcome$;
export function ClaimOutcome$Lost$0(value: ClaimOutcome$): $option.Option$<
  $json.Json$
>;
export function ClaimOutcome$Lost$current_value(value: ClaimOutcome$): $option.Option$<
  $json.Json$
>;

export class Aborted extends _.CustomType {}
export function ClaimOutcome$Aborted(): ClaimOutcome$;
export function ClaimOutcome$isAborted(value: any): value is ClaimOutcome$;

export type ClaimOutcome$ = Accepted | Lost | Aborted;

export class AlreadyPendingLocally extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function KernelError$AlreadyPendingLocally(key: string): KernelError$;
export function KernelError$isAlreadyPendingLocally(
  value: any,
): value is KernelError$;
export function KernelError$AlreadyPendingLocally$0(value: KernelError$): string;
export function KernelError$AlreadyPendingLocally$key(
  value: KernelError$,
): string;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: ClaimOperation$, detail: string);
  /** @deprecated */
  operation: ClaimOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: ClaimOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): ClaimOperation$;
export function KernelError$UnexpectedAck$operation(
  value: KernelError$,
): ClaimOperation$;
export function KernelError$UnexpectedAck$1(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: ClaimOperation$, detail: string);
  /** @deprecated */
  operation: ClaimOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(
  operation: ClaimOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): ClaimOperation$;
export function KernelError$UnexpectedRollback$operation(
  value: KernelError$,
): ClaimOperation$;
export function KernelError$UnexpectedRollback$1(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export type KernelError$ = AlreadyPendingLocally | UnexpectedAck | UnexpectedRollback;

export function new$(): ClaimsState$;

export function from_summary(entries: _.List<[string, $json.Json$, number]>): ClaimsState$;

export function summary_entries(state: ClaimsState$): _.List<
  [string, $json.Json$, number]
>;

export function get(state: ClaimsState$, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function has(state: ClaimsState$, key: string): boolean;

export function claim_once(
  state: ClaimsState$,
  key: string,
  value: $json.Json$,
  last_seen_sequence_number: number
): _.Result<SubmitResult$, KernelError$>;

export function compare_and_set_claim(
  state: ClaimsState$,
  key: string,
  value: $json.Json$,
  last_seen_sequence_number: number
): _.Result<SubmitResult$, KernelError$>;

export function set_detached(
  state: ClaimsState$,
  key: string,
  value: $json.Json$
): ClaimsState$;

export function apply_remote(
  state: ClaimsState$,
  operation: ClaimOperation$,
  sequence_number: number
): [ClaimsState$, _.List<ClaimEvent$>];

export function ack_local(
  state: ClaimsState$,
  operation: ClaimOperation$,
  sequence_number: number
): _.Result<[ClaimsState$, _.List<ClaimEvent$>, ClaimOutcome$], KernelError$>;

export function rollback(state: ClaimsState$, operation: ClaimOperation$): _.Result<
  [ClaimsState$, ClaimOutcome$],
  KernelError$
>;

export function apply_stashed_operation(
  state: ClaimsState$,
  operation: ClaimOperation$
): _.Result<[ClaimsState$, ClaimOperation$], KernelError$>;

export function abort_all(state: ClaimsState$): [ClaimsState$, _.List<string>];

export function pending_values(state: ClaimsState$): _.List<$json.Json$>;

import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class PactMapState extends _.CustomType {
  /** @deprecated */
  constructor(values: $dict.Dict$<string, Pact$>);
  /** @deprecated */
  values: $dict.Dict$<string, Pact$>;
}
export function PactMapState$PactMapState(
  values: $dict.Dict$<string, Pact$>,
): PactMapState$;
export function PactMapState$isPactMapState(value: any): value is PactMapState$;
export function PactMapState$PactMapState$0(value: PactMapState$): $dict.Dict$<
  string,
  Pact$
>;
export function PactMapState$PactMapState$values(value: PactMapState$): $dict.Dict$<
  string,
  Pact$
>;

export type PactMapState$ = PactMapState;

export class Pact extends _.CustomType {
  /** @deprecated */
  constructor(
    accepted: $option.Option$<Accepted$>,
    pending: $option.Option$<Pending$>
  );
  /** @deprecated */
  accepted: $option.Option$<Accepted$>;
  /** @deprecated */
  pending: $option.Option$<Pending$>;
}
export function Pact$Pact(
  accepted: $option.Option$<Accepted$>,
  pending: $option.Option$<Pending$>,
): Pact$;
export function Pact$isPact(value: any): value is Pact$;
export function Pact$Pact$0(value: Pact$): $option.Option$<Accepted$>;
export function Pact$Pact$accepted(value: Pact$): $option.Option$<Accepted$>;
export function Pact$Pact$1(value: Pact$): $option.Option$<Pending$>;
export function Pact$Pact$pending(value: Pact$): $option.Option$<Pending$>;

export type Pact$ = Pact;

export class Accepted extends _.CustomType {
  /** @deprecated */
  constructor(value: $option.Option$<$json.Json$>, sequence_number: number);
  /** @deprecated */
  value: $option.Option$<$json.Json$>;
  /** @deprecated */
  sequence_number: number;
}
export function Accepted$Accepted(
  value: $option.Option$<$json.Json$>,
  sequence_number: number,
): Accepted$;
export function Accepted$isAccepted(value: any): value is Accepted$;
export function Accepted$Accepted$0(value: Accepted$): $option.Option$<
  $json.Json$
>;
export function Accepted$Accepted$value(value: Accepted$): $option.Option$<
  $json.Json$
>;
export function Accepted$Accepted$1(value: Accepted$): number;
export function Accepted$Accepted$sequence_number(value: Accepted$): number;

export type Accepted$ = Accepted;

export class Pending extends _.CustomType {
  /** @deprecated */
  constructor(
    value: $option.Option$<$json.Json$>,
    expected_signoffs: _.List<number>
  );
  /** @deprecated */
  value: $option.Option$<$json.Json$>;
  /** @deprecated */
  expected_signoffs: _.List<number>;
}
export function Pending$Pending(
  value: $option.Option$<$json.Json$>,
  expected_signoffs: _.List<number>,
): Pending$;
export function Pending$isPending(value: any): value is Pending$;
export function Pending$Pending$0(value: Pending$): $option.Option$<$json.Json$>;
export function Pending$Pending$value(
  value: Pending$,
): $option.Option$<$json.Json$>;
export function Pending$Pending$1(value: Pending$): _.List<number>;
export function Pending$Pending$expected_signoffs(value: Pending$): _.List<
  number
>;

export type Pending$ = Pending;

export class Set extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    value: $option.Option$<$json.Json$>,
    reference_sequence_number: number
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $option.Option$<$json.Json$>;
  /** @deprecated */
  reference_sequence_number: number;
}
export function PactMapOperation$Set(
  key: string,
  value: $option.Option$<$json.Json$>,
  reference_sequence_number: number,
): PactMapOperation$;
export function PactMapOperation$isSet(value: any): value is PactMapOperation$;
export function PactMapOperation$Set$0(value: PactMapOperation$): string;
export function PactMapOperation$Set$key(value: PactMapOperation$): string;
export function PactMapOperation$Set$1(value: PactMapOperation$): $option.Option$<
  $json.Json$
>;
export function PactMapOperation$Set$value(value: PactMapOperation$): $option.Option$<
  $json.Json$
>;
export function PactMapOperation$Set$2(value: PactMapOperation$): number;
export function PactMapOperation$Set$reference_sequence_number(value: PactMapOperation$): number;

export class Accept extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function PactMapOperation$Accept(key: string): PactMapOperation$;
export function PactMapOperation$isAccept(
  value: any,
): value is PactMapOperation$;
export function PactMapOperation$Accept$0(value: PactMapOperation$): string;
export function PactMapOperation$Accept$key(value: PactMapOperation$): string;

export type PactMapOperation$ = Set | Accept;

export function PactMapOperation$key(value: PactMapOperation$): string;

export class WentPending extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function PactMapEvent$WentPending(key: string): PactMapEvent$;
export function PactMapEvent$isWentPending(value: any): value is PactMapEvent$;
export function PactMapEvent$WentPending$0(value: PactMapEvent$): string;
export function PactMapEvent$WentPending$key(value: PactMapEvent$): string;

export class WentAccepted extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function PactMapEvent$WentAccepted(key: string): PactMapEvent$;
export function PactMapEvent$isWentAccepted(value: any): value is PactMapEvent$;
export function PactMapEvent$WentAccepted$0(value: PactMapEvent$): string;
export function PactMapEvent$WentAccepted$key(value: PactMapEvent$): string;

export type PactMapEvent$ = WentPending | WentAccepted;

export function PactMapEvent$key(value: PactMapEvent$): string;

export class OweAccept extends _.CustomType {
  /** @deprecated */
  constructor(operation: PactMapOperation$);
  /** @deprecated */
  operation: PactMapOperation$;
}
export function SetReaction$OweAccept(
  operation: PactMapOperation$,
): SetReaction$;
export function SetReaction$isOweAccept(value: any): value is SetReaction$;
export function SetReaction$OweAccept$0(value: SetReaction$): PactMapOperation$;
export function SetReaction$OweAccept$operation(value: SetReaction$): PactMapOperation$;

export class NoReaction extends _.CustomType {}
export function SetReaction$NoReaction(): SetReaction$;
export function SetReaction$isNoReaction(value: any): value is SetReaction$;

export type SetReaction$ = OweAccept | NoReaction;

export class UnexpectedAccept extends _.CustomType {
  /** @deprecated */
  constructor(key: string, client: number, detail: string);
  /** @deprecated */
  key: string;
  /** @deprecated */
  client: number;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAccept(
  key: string,
  client: number,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAccept(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedAccept$0(value: KernelError$): string;
export function KernelError$UnexpectedAccept$key(value: KernelError$): string;
export function KernelError$UnexpectedAccept$1(value: KernelError$): number;
export function KernelError$UnexpectedAccept$client(value: KernelError$): number;
export function KernelError$UnexpectedAccept$2(
  value: KernelError$,
): string;
export function KernelError$UnexpectedAccept$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAccept;

export class ProposalAlreadyPending extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function ProposeError$ProposalAlreadyPending(key: string): ProposeError$;
export function ProposeError$isProposalAlreadyPending(
  value: any,
): value is ProposeError$;
export function ProposeError$ProposalAlreadyPending$0(value: ProposeError$): string;
export function ProposeError$ProposalAlreadyPending$key(
  value: ProposeError$,
): string;

export class KeyNotFound extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function ProposeError$KeyNotFound(key: string): ProposeError$;
export function ProposeError$isKeyNotFound(value: any): value is ProposeError$;
export function ProposeError$KeyNotFound$0(value: ProposeError$): string;
export function ProposeError$KeyNotFound$key(value: ProposeError$): string;

export class KeyAlreadyDeleted extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function ProposeError$KeyAlreadyDeleted(key: string): ProposeError$;
export function ProposeError$isKeyAlreadyDeleted(
  value: any,
): value is ProposeError$;
export function ProposeError$KeyAlreadyDeleted$0(value: ProposeError$): string;
export function ProposeError$KeyAlreadyDeleted$key(value: ProposeError$): string;

export type ProposeError$ = ProposalAlreadyPending | KeyNotFound | KeyAlreadyDeleted;

export function ProposeError$key(value: ProposeError$): string;

export function new$(): PactMapState$;

export function from_summary(entries: _.List<[string, Pact$]>): PactMapState$;

export function summary_entries(state: PactMapState$): _.List<[string, Pact$]>;

export function get(state: PactMapState$, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function get_with_details(state: PactMapState$, key: string): _.Result<
  Accepted$,
  undefined
>;

export function is_pending(state: PactMapState$, key: string): boolean;

export function get_pending(state: PactMapState$, key: string): _.Result<
  $option.Option$<$json.Json$>,
  undefined
>;

export function pending(state: PactMapState$, key: string): _.Result<
  Pending$,
  undefined
>;

export function keys(state: PactMapState$): _.List<string>;

export function set(
  state: PactMapState$,
  key: string,
  value: $option.Option$<$json.Json$>,
  last_seen_sequence_number: number
): _.Result<PactMapOperation$, ProposeError$>;

export function delete$(
  state: PactMapState$,
  key: string,
  last_seen_sequence_number: number
): _.Result<PactMapOperation$, ProposeError$>;

export function apply_set(
  state: PactMapState$,
  operation: PactMapOperation$,
  sequence_number: number,
  connected: _.List<number>,
  self_id: number
): [PactMapState$, _.List<PactMapEvent$>, SetReaction$];

export function apply_accept(
  state: PactMapState$,
  key: string,
  from_client: number,
  sequence_number: number
): _.Result<[PactMapState$, _.List<PactMapEvent$>], KernelError$>;

export function remove_member(
  state: PactMapState$,
  client_id: number,
  leave_sequence_number: number
): [PactMapState$, _.List<PactMapEvent$>];

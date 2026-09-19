import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as _ from "../gleam.d.mts";

export class ClientSequenceState extends _.CustomType {
  /** @deprecated */
  constructor(last_csn: number, last_rsn: number);
  /** @deprecated */
  last_csn: number;
  /** @deprecated */
  last_rsn: number;
}
export function ClientSequenceState$ClientSequenceState(
  last_csn: number,
  last_rsn: number,
): ClientSequenceState$;
export function ClientSequenceState$isClientSequenceState(
  value: any,
): value is ClientSequenceState$;
export function ClientSequenceState$ClientSequenceState$0(value: ClientSequenceState$): number;
export function ClientSequenceState$ClientSequenceState$last_csn(
  value: ClientSequenceState$,
): number;
export function ClientSequenceState$ClientSequenceState$1(value: ClientSequenceState$): number;
export function ClientSequenceState$ClientSequenceState$last_rsn(
  value: ClientSequenceState$,
): number;

export type ClientSequenceState$ = ClientSequenceState;

export class SequenceState extends _.CustomType {
  /** @deprecated */
  constructor(
    sequence_number: number,
    minimum_sequence_number: number,
    client_states: $dict.Dict$<string, ClientSequenceState$>
  );
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  minimum_sequence_number: number;
  /** @deprecated */
  client_states: $dict.Dict$<string, ClientSequenceState$>;
}
export function SequenceState$SequenceState(
  sequence_number: number,
  minimum_sequence_number: number,
  client_states: $dict.Dict$<string, ClientSequenceState$>,
): SequenceState$;
export function SequenceState$isSequenceState(
  value: any,
): value is SequenceState$;
export function SequenceState$SequenceState$0(value: SequenceState$): number;
export function SequenceState$SequenceState$sequence_number(value: SequenceState$): number;
export function SequenceState$SequenceState$1(
  value: SequenceState$,
): number;
export function SequenceState$SequenceState$minimum_sequence_number(value: SequenceState$): number;
export function SequenceState$SequenceState$2(
  value: SequenceState$,
): $dict.Dict$<string, ClientSequenceState$>;
export function SequenceState$SequenceState$client_states(value: SequenceState$): $dict.Dict$<
  string,
  ClientSequenceState$
>;

export type SequenceState$ = SequenceState;

export class SequenceOk extends _.CustomType {
  /** @deprecated */
  constructor(state: SequenceState$, assigned_sn: number, msn: number);
  /** @deprecated */
  state: SequenceState$;
  /** @deprecated */
  assigned_sn: number;
  /** @deprecated */
  msn: number;
}
export function SequenceResult$SequenceOk(
  state: SequenceState$,
  assigned_sn: number,
  msn: number,
): SequenceResult$;
export function SequenceResult$isSequenceOk(
  value: any,
): value is SequenceResult$;
export function SequenceResult$SequenceOk$0(value: SequenceResult$): SequenceState$;
export function SequenceResult$SequenceOk$state(
  value: SequenceResult$,
): SequenceState$;
export function SequenceResult$SequenceOk$1(value: SequenceResult$): number;
export function SequenceResult$SequenceOk$assigned_sn(value: SequenceResult$): number;
export function SequenceResult$SequenceOk$2(
  value: SequenceResult$,
): number;
export function SequenceResult$SequenceOk$msn(value: SequenceResult$): number;

export class SequenceError extends _.CustomType {
  /** @deprecated */
  constructor(reason: SequenceError$);
  /** @deprecated */
  reason: SequenceError$;
}
export function SequenceResult$SequenceError(
  reason: SequenceError$,
): SequenceResult$;
export function SequenceResult$isSequenceError(
  value: any,
): value is SequenceResult$;
export function SequenceResult$SequenceError$0(value: SequenceResult$): SequenceError$;
export function SequenceResult$SequenceError$reason(
  value: SequenceResult$,
): SequenceError$;

export type SequenceResult$ = SequenceOk | SequenceError;

export class InvalidCsn extends _.CustomType {
  /** @deprecated */
  constructor(expected_greater_than: number, received: number);
  /** @deprecated */
  expected_greater_than: number;
  /** @deprecated */
  received: number;
}
export function SequenceError$InvalidCsn(
  expected_greater_than: number,
  received: number,
): SequenceError$;
export function SequenceError$isInvalidCsn(value: any): value is SequenceError$;
export function SequenceError$InvalidCsn$0(value: SequenceError$): number;
export function SequenceError$InvalidCsn$expected_greater_than(value: SequenceError$): number;
export function SequenceError$InvalidCsn$1(
  value: SequenceError$,
): number;
export function SequenceError$InvalidCsn$received(value: SequenceError$): number;

export class InvalidRsn extends _.CustomType {
  /** @deprecated */
  constructor(current_sn: number, received_rsn: number);
  /** @deprecated */
  current_sn: number;
  /** @deprecated */
  received_rsn: number;
}
export function SequenceError$InvalidRsn(
  current_sn: number,
  received_rsn: number,
): SequenceError$;
export function SequenceError$isInvalidRsn(value: any): value is SequenceError$;
export function SequenceError$InvalidRsn$0(value: SequenceError$): number;
export function SequenceError$InvalidRsn$current_sn(value: SequenceError$): number;
export function SequenceError$InvalidRsn$1(
  value: SequenceError$,
): number;
export function SequenceError$InvalidRsn$received_rsn(value: SequenceError$): number;

export class UnknownClient extends _.CustomType {
  /** @deprecated */
  constructor(client_id: string);
  /** @deprecated */
  client_id: string;
}
export function SequenceError$UnknownClient(client_id: string): SequenceError$;
export function SequenceError$isUnknownClient(
  value: any,
): value is SequenceError$;
export function SequenceError$UnknownClient$0(value: SequenceError$): string;
export function SequenceError$UnknownClient$client_id(value: SequenceError$): string;

export type SequenceError$ = InvalidCsn | InvalidRsn | UnknownClient;

export function new$(): SequenceState$;

export function from_checkpoint(sn: number, msn: number): SequenceState$;

export function client_join(
  state: SequenceState$,
  client_id: string,
  join_rsn: number
): SequenceState$;

export function client_leave(state: SequenceState$, client_id: string): SequenceState$;

export function assign_sequence_number(
  state: SequenceState$,
  client_id: string,
  csn: number,
  rsn: number
): SequenceResult$;

export function update_client_rsn(
  state: SequenceState$,
  client_id: string,
  new_rsn: number
): _.Result<SequenceState$, SequenceError$>;

export function reserve_sequence_number(state: SequenceState$): [
  SequenceState$,
  number
];

export function current_sn(state: SequenceState$): number;

export function current_msn(state: SequenceState$): number;

export function client_count(state: SequenceState$): number;

export function is_client_connected(state: SequenceState$, client_id: string): boolean;

export function connected_clients(state: SequenceState$): _.List<string>;

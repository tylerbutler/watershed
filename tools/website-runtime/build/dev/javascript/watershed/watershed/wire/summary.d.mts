import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../../gleam.d.mts";

export class Ack extends _.CustomType {
  /** @deprecated */
  constructor(proposal_sequence_number: number, version_id: string);
  /** @deprecated */
  proposal_sequence_number: number;
  /** @deprecated */
  version_id: string;
}
export function SummaryResponse$Ack(
  proposal_sequence_number: number,
  version_id: string,
): SummaryResponse$;
export function SummaryResponse$isAck(value: any): value is SummaryResponse$;
export function SummaryResponse$Ack$0(value: SummaryResponse$): number;
export function SummaryResponse$Ack$proposal_sequence_number(value: SummaryResponse$): number;
export function SummaryResponse$Ack$1(
  value: SummaryResponse$,
): string;
export function SummaryResponse$Ack$version_id(value: SummaryResponse$): string;

export class Nack extends _.CustomType {
  /** @deprecated */
  constructor(proposal_sequence_number: number, reason: string);
  /** @deprecated */
  proposal_sequence_number: number;
  /** @deprecated */
  reason: string;
}
export function SummaryResponse$Nack(
  proposal_sequence_number: number,
  reason: string,
): SummaryResponse$;
export function SummaryResponse$isNack(value: any): value is SummaryResponse$;
export function SummaryResponse$Nack$0(value: SummaryResponse$): number;
export function SummaryResponse$Nack$proposal_sequence_number(value: SummaryResponse$): number;
export function SummaryResponse$Nack$1(
  value: SummaryResponse$,
): string;
export function SummaryResponse$Nack$reason(value: SummaryResponse$): string;

export type SummaryResponse$ = Ack | Nack;

export function SummaryResponse$proposal_sequence_number(
  value: SummaryResponse$,
): number;

export function decode_message(
  message_type: string,
  contents: $dynamic.Dynamic$
): _.Result<SummaryResponse$, undefined>;

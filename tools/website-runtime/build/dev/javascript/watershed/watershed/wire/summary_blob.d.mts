import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $channel from "../../watershed/channel.d.mts";

export class SummaryBlob extends _.CustomType {
  /** @deprecated */
  constructor(
    sequence_number: number,
    members: _.List<number>,
    channels: _.List<ChannelSnapshot$>
  );
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  members: _.List<number>;
  /** @deprecated */
  channels: _.List<ChannelSnapshot$>;
}
export function SummaryBlob$SummaryBlob(
  sequence_number: number,
  members: _.List<number>,
  channels: _.List<ChannelSnapshot$>,
): SummaryBlob$;
export function SummaryBlob$isSummaryBlob(value: any): value is SummaryBlob$;
export function SummaryBlob$SummaryBlob$0(value: SummaryBlob$): number;
export function SummaryBlob$SummaryBlob$sequence_number(value: SummaryBlob$): number;
export function SummaryBlob$SummaryBlob$1(
  value: SummaryBlob$,
): _.List<number>;
export function SummaryBlob$SummaryBlob$members(value: SummaryBlob$): _.List<
  number
>;
export function SummaryBlob$SummaryBlob$2(value: SummaryBlob$): _.List<
  ChannelSnapshot$
>;
export function SummaryBlob$SummaryBlob$channels(value: SummaryBlob$): _.List<
  ChannelSnapshot$
>;

export type SummaryBlob$ = SummaryBlob;

export class ChannelSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(address: string, snapshot: $channel.Snapshot$);
  /** @deprecated */
  address: string;
  /** @deprecated */
  snapshot: $channel.Snapshot$;
}
export function ChannelSnapshot$ChannelSnapshot(
  address: string,
  snapshot: $channel.Snapshot$,
): ChannelSnapshot$;
export function ChannelSnapshot$isChannelSnapshot(
  value: any,
): value is ChannelSnapshot$;
export function ChannelSnapshot$ChannelSnapshot$0(value: ChannelSnapshot$): string;
export function ChannelSnapshot$ChannelSnapshot$address(
  value: ChannelSnapshot$,
): string;
export function ChannelSnapshot$ChannelSnapshot$1(value: ChannelSnapshot$): $channel.Snapshot$;
export function ChannelSnapshot$ChannelSnapshot$snapshot(
  value: ChannelSnapshot$,
): $channel.Snapshot$;

export type ChannelSnapshot$ = ChannelSnapshot;

export const version: number;

export function encode_channels(
  sequence_number: number,
  members: _.List<number>,
  channels: _.List<[string, $channel.Snapshot$]>
): $json.Json$;

export function decoder(): $decode.Decoder$<SummaryBlob$>;

export function decode(raw: string): _.Result<SummaryBlob$, $json.DecodeError$>;

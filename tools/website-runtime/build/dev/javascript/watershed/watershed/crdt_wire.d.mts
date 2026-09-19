import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $channel from "../watershed/channel.d.mts";
import type * as $p2p from "../watershed/p2p.d.mts";

export class Limits extends _.CustomType {
  /** @deprecated */
  constructor(
    room_peers: number,
    envelope_bytes: number,
    snapshot_bytes: number,
    channels: number,
    buffered_deltas: number,
    recent_message_ids: number
  );
  /** @deprecated */
  room_peers: number;
  /** @deprecated */
  envelope_bytes: number;
  /** @deprecated */
  snapshot_bytes: number;
  /** @deprecated */
  channels: number;
  /** @deprecated */
  buffered_deltas: number;
  /** @deprecated */
  recent_message_ids: number;
}
export function Limits$Limits(
  room_peers: number,
  envelope_bytes: number,
  snapshot_bytes: number,
  channels: number,
  buffered_deltas: number,
  recent_message_ids: number,
): Limits$;
export function Limits$isLimits(value: any): value is Limits$;
export function Limits$Limits$0(value: Limits$): number;
export function Limits$Limits$room_peers(value: Limits$): number;
export function Limits$Limits$1(value: Limits$): number;
export function Limits$Limits$envelope_bytes(value: Limits$): number;
export function Limits$Limits$2(value: Limits$): number;
export function Limits$Limits$snapshot_bytes(value: Limits$): number;
export function Limits$Limits$3(value: Limits$): number;
export function Limits$Limits$channels(value: Limits$): number;
export function Limits$Limits$4(value: Limits$): number;
export function Limits$Limits$buffered_deltas(value: Limits$): number;
export function Limits$Limits$5(value: Limits$): number;
export function Limits$Limits$recent_message_ids(value: Limits$): number;

export type Limits$ = Limits;

export class MessageId extends _.CustomType {
  /** @deprecated */
  constructor(replica: string, counter: number);
  /** @deprecated */
  replica: string;
  /** @deprecated */
  counter: number;
}
export function MessageId$MessageId(
  replica: string,
  counter: number,
): MessageId$;
export function MessageId$isMessageId(value: any): value is MessageId$;
export function MessageId$MessageId$0(value: MessageId$): string;
export function MessageId$MessageId$replica(value: MessageId$): string;
export function MessageId$MessageId$1(value: MessageId$): number;
export function MessageId$MessageId$counter(value: MessageId$): number;

export type MessageId$ = MessageId;

export class ChannelDescriptor extends _.CustomType {
  /** @deprecated */
  constructor(
    address: string,
    channel_type: $channel.ChannelType$,
    created_by: string
  );
  /** @deprecated */
  address: string;
  /** @deprecated */
  channel_type: $channel.ChannelType$;
  /** @deprecated */
  created_by: string;
}
export function ChannelDescriptor$ChannelDescriptor(
  address: string,
  channel_type: $channel.ChannelType$,
  created_by: string,
): ChannelDescriptor$;
export function ChannelDescriptor$isChannelDescriptor(
  value: any,
): value is ChannelDescriptor$;
export function ChannelDescriptor$ChannelDescriptor$0(value: ChannelDescriptor$): string;
export function ChannelDescriptor$ChannelDescriptor$address(
  value: ChannelDescriptor$,
): string;
export function ChannelDescriptor$ChannelDescriptor$1(value: ChannelDescriptor$): $channel.ChannelType$;
export function ChannelDescriptor$ChannelDescriptor$channel_type(
  value: ChannelDescriptor$,
): $channel.ChannelType$;
export function ChannelDescriptor$ChannelDescriptor$2(value: ChannelDescriptor$): string;
export function ChannelDescriptor$ChannelDescriptor$created_by(
  value: ChannelDescriptor$,
): string;

export type ChannelDescriptor$ = ChannelDescriptor;

export class ChannelEntry extends _.CustomType {
  /** @deprecated */
  constructor(descriptor: ChannelDescriptor$, snapshot: $channel.Snapshot$);
  /** @deprecated */
  descriptor: ChannelDescriptor$;
  /** @deprecated */
  snapshot: $channel.Snapshot$;
}
export function ChannelEntry$ChannelEntry(
  descriptor: ChannelDescriptor$,
  snapshot: $channel.Snapshot$,
): ChannelEntry$;
export function ChannelEntry$isChannelEntry(value: any): value is ChannelEntry$;
export function ChannelEntry$ChannelEntry$0(value: ChannelEntry$): ChannelDescriptor$;
export function ChannelEntry$ChannelEntry$descriptor(
  value: ChannelEntry$,
): ChannelDescriptor$;
export function ChannelEntry$ChannelEntry$1(value: ChannelEntry$): $channel.Snapshot$;
export function ChannelEntry$ChannelEntry$snapshot(
  value: ChannelEntry$,
): $channel.Snapshot$;

export type ChannelEntry$ = ChannelEntry;

export class Hello extends _.CustomType {
  /** @deprecated */
  constructor(compatibility: string, root: $channel.ChannelType$);
  /** @deprecated */
  compatibility: string;
  /** @deprecated */
  root: $channel.ChannelType$;
}
export function Message$Hello(
  compatibility: string,
  root: $channel.ChannelType$,
): Message$;
export function Message$isHello(value: any): value is Message$;
export function Message$Hello$0(value: Message$): string;
export function Message$Hello$compatibility(value: Message$): string;
export function Message$Hello$1(value: Message$): $channel.ChannelType$;
export function Message$Hello$root(value: Message$): $channel.ChannelType$;

export class ChannelAnnounce extends _.CustomType {
  /** @deprecated */
  constructor(entry: ChannelEntry$);
  /** @deprecated */
  entry: ChannelEntry$;
}
export function Message$ChannelAnnounce(entry: ChannelEntry$): Message$;
export function Message$isChannelAnnounce(value: any): value is Message$;
export function Message$ChannelAnnounce$0(value: Message$): ChannelEntry$;
export function Message$ChannelAnnounce$entry(value: Message$): ChannelEntry$;

export class Delta extends _.CustomType {
  /** @deprecated */
  constructor(
    id: MessageId$,
    address: string,
    channel_type: $channel.ChannelType$,
    operation: $channel.ChannelOperation$
  );
  /** @deprecated */
  id: MessageId$;
  /** @deprecated */
  address: string;
  /** @deprecated */
  channel_type: $channel.ChannelType$;
  /** @deprecated */
  operation: $channel.ChannelOperation$;
}
export function Message$Delta(
  id: MessageId$,
  address: string,
  channel_type: $channel.ChannelType$,
  operation: $channel.ChannelOperation$,
): Message$;
export function Message$isDelta(value: any): value is Message$;
export function Message$Delta$0(value: Message$): MessageId$;
export function Message$Delta$id(value: Message$): MessageId$;
export function Message$Delta$1(value: Message$): string;
export function Message$Delta$address(value: Message$): string;
export function Message$Delta$2(value: Message$): $channel.ChannelType$;
export function Message$Delta$channel_type(value: Message$): $channel.ChannelType$;
export function Message$Delta$3(
  value: Message$,
): $channel.ChannelOperation$;
export function Message$Delta$operation(value: Message$): $channel.ChannelOperation$;

export class StateRequest extends _.CustomType {}
export function Message$StateRequest(): Message$;
export function Message$isStateRequest(value: any): value is Message$;

export class State extends _.CustomType {
  /** @deprecated */
  constructor(entries: _.List<ChannelEntry$>);
  /** @deprecated */
  entries: _.List<ChannelEntry$>;
}
export function Message$State(entries: _.List<ChannelEntry$>): Message$;
export function Message$isState(value: any): value is Message$;
export function Message$State$0(value: Message$): _.List<ChannelEntry$>;
export function Message$State$entries(value: Message$): _.List<ChannelEntry$>;

export class Digest extends _.CustomType {
  /** @deprecated */
  constructor(digest: string);
  /** @deprecated */
  digest: string;
}
export function Message$Digest(digest: string): Message$;
export function Message$isDigest(value: any): value is Message$;
export function Message$Digest$0(value: Message$): string;
export function Message$Digest$digest(value: Message$): string;

export class Rejected extends _.CustomType {
  /** @deprecated */
  constructor(reason: string, detail: string);
  /** @deprecated */
  reason: string;
  /** @deprecated */
  detail: string;
}
export function Message$Rejected(reason: string, detail: string): Message$;
export function Message$isRejected(value: any): value is Message$;
export function Message$Rejected$0(value: Message$): string;
export function Message$Rejected$reason(value: Message$): string;
export function Message$Rejected$1(value: Message$): string;
export function Message$Rejected$detail(value: Message$): string;

export type Message$ = Hello | ChannelAnnounce | Delta | StateRequest | State | Digest | Rejected;

export class Envelope extends _.CustomType {
  /** @deprecated */
  constructor(room: string, from: string, session: string, message: Message$);
  /** @deprecated */
  room: string;
  /** @deprecated */
  from: string;
  /** @deprecated */
  session: string;
  /** @deprecated */
  message: Message$;
}
export function Envelope$Envelope(
  room: string,
  from: string,
  session: string,
  message: Message$,
): Envelope$;
export function Envelope$isEnvelope(value: any): value is Envelope$;
export function Envelope$Envelope$0(value: Envelope$): string;
export function Envelope$Envelope$room(value: Envelope$): string;
export function Envelope$Envelope$1(value: Envelope$): string;
export function Envelope$Envelope$from(value: Envelope$): string;
export function Envelope$Envelope$2(value: Envelope$): string;
export function Envelope$Envelope$session(value: Envelope$): string;
export function Envelope$Envelope$3(value: Envelope$): Message$;
export function Envelope$Envelope$message(value: Envelope$): Message$;

export type Envelope$ = Envelope;

declare class Preamble extends _.CustomType {
  /** @deprecated */
  constructor(
    version: number,
    room: string,
    from: string,
    session: string,
    message: $json.Json$
  );
  /** @deprecated */
  version: number;
  /** @deprecated */
  room: string;
  /** @deprecated */
  from: string;
  /** @deprecated */
  session: string;
  /** @deprecated */
  message: $json.Json$;
}

type Preamble$ = Preamble;

declare class RawHello extends _.CustomType {
  /** @deprecated */
  constructor(compatibility: string, root: string);
  /** @deprecated */
  compatibility: string;
  /** @deprecated */
  root: string;
}

declare class RawChannel extends _.CustomType {
  /** @deprecated */
  constructor(entry: RawEntry$);
  /** @deprecated */
  entry: RawEntry$;
}

declare class RawDelta extends _.CustomType {
  /** @deprecated */
  constructor(
    replica: string,
    counter: number,
    address: string,
    channel_type: string,
    contents: $json.Json$
  );
  /** @deprecated */
  replica: string;
  /** @deprecated */
  counter: number;
  /** @deprecated */
  address: string;
  /** @deprecated */
  channel_type: string;
  /** @deprecated */
  contents: $json.Json$;
}

declare class RawStateRequest extends _.CustomType {}

declare class RawState extends _.CustomType {
  /** @deprecated */
  constructor(entries: _.List<$json.Json$>);
  /** @deprecated */
  entries: _.List<$json.Json$>;
}

declare class RawDigest extends _.CustomType {
  /** @deprecated */
  constructor(digest: string);
  /** @deprecated */
  digest: string;
}

declare class RawRejected extends _.CustomType {
  /** @deprecated */
  constructor(reason: string, detail: string);
  /** @deprecated */
  reason: string;
  /** @deprecated */
  detail: string;
}

type RawMessage$ = RawHello | RawChannel | RawDelta | RawStateRequest | RawState | RawDigest | RawRejected;

declare class RawEntry extends _.CustomType {
  /** @deprecated */
  constructor(
    address: string,
    channel_type: string,
    created_by: string,
    snapshot: $json.Json$
  );
  /** @deprecated */
  address: string;
  /** @deprecated */
  channel_type: string;
  /** @deprecated */
  created_by: string;
  /** @deprecated */
  snapshot: $json.Json$;
}

type RawEntry$ = RawEntry;

export const root_address: string;

export const protocol_version: number;

export function default_limits(): Limits$;

export function message_type(message: Message$): string;

export function channel_address(replica: string, counter: number): string;

export function valid_replica_id(replica: string): boolean;

export function address_creator(address: string): _.Result<string, undefined>;

export function encode_descriptor(descriptor: ChannelDescriptor$): $json.Json$;

export function encode_channel_entry(entry: ChannelEntry$): $json.Json$;

export function sort_entries(entries: _.List<ChannelEntry$>): _.List<
  ChannelEntry$
>;

export function encode_message(message: Message$): $json.Json$;

export function encode_envelope(envelope: Envelope$): $json.Json$;

export function envelope_to_string(envelope: Envelope$): string;

export function decode_channel_entry(
  value: $json.Json$,
  from: string,
  limits: Limits$
): _.Result<ChannelEntry$, $p2p.P2pError$>;

export function decode_envelope(raw: string, limits: Limits$): _.Result<
  Envelope$,
  $p2p.P2pError$
>;

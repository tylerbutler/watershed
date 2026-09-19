import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $channel from "../watershed/channel.d.mts";
import type * as $crdt_wire from "../watershed/crdt_wire.d.mts";
import type * as $json_ot from "../watershed/json_ot.d.mts";
import type * as $p2p from "../watershed/p2p.d.mts";

export class Config extends _.CustomType {
  /** @deprecated */
  constructor(
    room: string,
    compatibility: string,
    replica: string,
    session: string,
    root: $channel.ChannelInit$,
    limits: $crdt_wire.Limits$
  );
  /** @deprecated */
  room: string;
  /** @deprecated */
  compatibility: string;
  /** @deprecated */
  replica: string;
  /** @deprecated */
  session: string;
  /** @deprecated */
  root: $channel.ChannelInit$;
  /** @deprecated */
  limits: $crdt_wire.Limits$;
}
export function Config$Config(
  room: string,
  compatibility: string,
  replica: string,
  session: string,
  root: $channel.ChannelInit$,
  limits: $crdt_wire.Limits$,
): Config$;
export function Config$isConfig(value: any): value is Config$;
export function Config$Config$0(value: Config$): string;
export function Config$Config$room(value: Config$): string;
export function Config$Config$1(value: Config$): string;
export function Config$Config$compatibility(value: Config$): string;
export function Config$Config$2(value: Config$): string;
export function Config$Config$replica(value: Config$): string;
export function Config$Config$3(value: Config$): string;
export function Config$Config$session(value: Config$): string;
export function Config$Config$4(value: Config$): $channel.ChannelInit$;
export function Config$Config$root(value: Config$): $channel.ChannelInit$;
export function Config$Config$5(value: Config$): $crdt_wire.Limits$;
export function Config$Config$limits(value: Config$): $crdt_wire.Limits$;

export type Config$ = Config;

declare class Document extends _.CustomType {
  /** @deprecated */
  constructor(
    config: Config$,
    counter: number,
    registry: $dict.Dict$<string, $crdt_wire.ChannelDescriptor$>,
    states: $dict.Dict$<string, $channel.ChannelState$>,
    buffered: Fifo$<BufferedDelta$>,
    recent: Recent$
  );
  /** @deprecated */
  config: Config$;
  /** @deprecated */
  counter: number;
  /** @deprecated */
  registry: $dict.Dict$<string, $crdt_wire.ChannelDescriptor$>;
  /** @deprecated */
  states: $dict.Dict$<string, $channel.ChannelState$>;
  /** @deprecated */
  buffered: Fifo$<BufferedDelta$>;
  /** @deprecated */
  recent: Recent$;
}

export type Document$ = Document;

declare class BufferedDelta extends _.CustomType {
  /** @deprecated */
  constructor(
    id: $crdt_wire.MessageId$,
    address: string,
    channel_type: $channel.ChannelType$,
    operation: $channel.ChannelOperation$
  );
  /** @deprecated */
  id: $crdt_wire.MessageId$;
  /** @deprecated */
  address: string;
  /** @deprecated */
  channel_type: $channel.ChannelType$;
  /** @deprecated */
  operation: $channel.ChannelOperation$;
}

type BufferedDelta$ = BufferedDelta;

declare class Recent extends _.CustomType {
  /** @deprecated */
  constructor(
    seen: $dict.Dict$<$crdt_wire.MessageId$, undefined>,
    queue: Fifo$<$crdt_wire.MessageId$>
  );
  /** @deprecated */
  seen: $dict.Dict$<$crdt_wire.MessageId$, undefined>;
  /** @deprecated */
  queue: Fifo$<$crdt_wire.MessageId$>;
}

type Recent$ = Recent;

declare class Fifo<BRBQ> extends _.CustomType {
  /** @deprecated */
  constructor(front: _.List<BRBQ>, back: _.List<BRBQ>, size: number);
  /** @deprecated */
  front: _.List<BRBQ>;
  /** @deprecated */
  back: _.List<BRBQ>;
  /** @deprecated */
  size: number;
}

type Fifo$<BRBQ> = Fifo<BRBQ>;

export class Outcome extends _.CustomType {
  /** @deprecated */
  constructor(
    broadcast: _.List<$crdt_wire.Message$>,
    reply: _.List<$crdt_wire.Message$>,
    created: _.List<$crdt_wire.ChannelDescriptor$>,
    events: _.List<[string, $channel.ChannelEvent$]>
  );
  /** @deprecated */
  broadcast: _.List<$crdt_wire.Message$>;
  /** @deprecated */
  reply: _.List<$crdt_wire.Message$>;
  /** @deprecated */
  created: _.List<$crdt_wire.ChannelDescriptor$>;
  /** @deprecated */
  events: _.List<[string, $channel.ChannelEvent$]>;
}
export function Outcome$Outcome(
  broadcast: _.List<$crdt_wire.Message$>,
  reply: _.List<$crdt_wire.Message$>,
  created: _.List<$crdt_wire.ChannelDescriptor$>,
  events: _.List<[string, $channel.ChannelEvent$]>,
): Outcome$;
export function Outcome$isOutcome(value: any): value is Outcome$;
export function Outcome$Outcome$0(value: Outcome$): _.List<$crdt_wire.Message$>;
export function Outcome$Outcome$broadcast(value: Outcome$): _.List<
  $crdt_wire.Message$
>;
export function Outcome$Outcome$1(value: Outcome$): _.List<$crdt_wire.Message$>;
export function Outcome$Outcome$reply(value: Outcome$): _.List<
  $crdt_wire.Message$
>;
export function Outcome$Outcome$2(value: Outcome$): _.List<
  $crdt_wire.ChannelDescriptor$
>;
export function Outcome$Outcome$created(value: Outcome$): _.List<
  $crdt_wire.ChannelDescriptor$
>;
export function Outcome$Outcome$3(value: Outcome$): _.List<
  [string, $channel.ChannelEvent$]
>;
export function Outcome$Outcome$events(value: Outcome$): _.List<
  [string, $channel.ChannelEvent$]
>;

export type Outcome$ = Outcome;

declare class CanonicalSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(
    version: number,
    room: string,
    compatibility: string,
    root: string,
    channels: _.List<$json.Json$>
  );
  /** @deprecated */
  version: number;
  /** @deprecated */
  room: string;
  /** @deprecated */
  compatibility: string;
  /** @deprecated */
  root: string;
  /** @deprecated */
  channels: _.List<$json.Json$>;
}

type CanonicalSnapshot$ = CanonicalSnapshot;

export function config(
  room: string,
  compatibility: string,
  replica: string,
  session: string,
  root: $channel.ChannelInit$
): Config$;

export function empty_outcome(): Outcome$;

export function new$(config: Config$): _.Result<Document$, $p2p.P2pError$>;

export function config_of(document: Document$): Config$;

export function room(document: Document$): string;

export function compatibility(document: Document$): string;

export function replica(document: Document$): string;

export function session(document: Document$): string;

export function limits(document: Document$): $crdt_wire.Limits$;

export function root_type(document: Document$): $channel.ChannelType$;

export function canonical_json(document: Document$): string;

export function descriptors(document: Document$): _.List<
  $crdt_wire.ChannelDescriptor$
>;

export function channel_count(document: Document$): number;

export function buffered_count(document: Document$): number;

export function recent_count(document: Document$): number;

export function seen(document: Document$, id: $crdt_wire.MessageId$): boolean;

export function descriptor(document: Document$, address: string): _.Result<
  $crdt_wire.ChannelDescriptor$,
  $p2p.P2pError$
>;

export function channel_type(document: Document$, address: string): _.Result<
  $channel.ChannelType$,
  $p2p.P2pError$
>;

export function channel_state(document: Document$, address: string): _.Result<
  $channel.ChannelState$,
  $p2p.P2pError$
>;

export function hello_message(document: Document$): $crdt_wire.Message$;

export function state_request_message(): $crdt_wire.Message$;

export function state_message(document: Document$): $crdt_wire.Message$;

export function digest_canonical_json(document: Document$): string;

export function digest(document: Document$): string;

export function digest_message(document: Document$): $crdt_wire.Message$;

export function rejection_message(reason: string, detail: string): $crdt_wire.Message$;

export function envelope(document: Document$, message: $crdt_wire.Message$): $crdt_wire.Envelope$;

export function encode(document: Document$, message: $crdt_wire.Message$): string;

export function create_channel(document: Document$, init: $channel.ChannelInit$): _.Result<
  [Document$, Outcome$],
  $p2p.P2pError$
>;

export function edit(
  document: Document$,
  address: string,
  edit: $channel.P2pEdit$
): _.Result<[Document$, Outcome$], $p2p.P2pError$>;

export function receive(document: Document$, envelope: $crdt_wire.Envelope$): _.Result<
  [Document$, Outcome$],
  $p2p.P2pError$
>;

export function receive_encoded(document: Document$, raw: string): _.Result<
  [Document$, Outcome$],
  $p2p.P2pError$
>;

export function receive_with_digest(
  document: Document$,
  envelope: $crdt_wire.Envelope$,
  local: string
): _.Result<[Document$, Outcome$], $p2p.P2pError$>;

export function import_snapshot(document: Document$, raw: string): _.Result<
  [Document$, Outcome$],
  $p2p.P2pError$
>;

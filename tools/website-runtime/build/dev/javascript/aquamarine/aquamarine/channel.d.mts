import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $codec from "../aquamarine/codec.d.mts";
import type * as $error from "../aquamarine/error.d.mts";
import type * as $heartbeat from "../aquamarine/heartbeat.d.mts";
import type * as $ref from "../aquamarine/ref.d.mts";
import type * as $transport from "../aquamarine/transport.d.mts";
import type * as _ from "../gleam.d.mts";

declare class Channel extends _.CustomType {
  /** @deprecated */
  constructor(
    transport: $transport.Transport$,
    topic: string,
    join_ref: string,
    counter: $ref.Counter$,
    heartbeat: $heartbeat.Heartbeat$,
    codec: $codec.Codec$
  );
  /** @deprecated */
  transport: $transport.Transport$;
  /** @deprecated */
  topic: string;
  /** @deprecated */
  join_ref: string;
  /** @deprecated */
  counter: $ref.Counter$;
  /** @deprecated */
  heartbeat: $heartbeat.Heartbeat$;
  /** @deprecated */
  codec: $codec.Codec$;
}

export type Channel$ = Channel;

export function connect_with(
  connector: () => _.Result<$transport.Transport$, $error.AquamarineError$>,
  topic: string,
  payload: $json.Json$,
  codec: $codec.Codec$,
  heartbeat_ms: number
): _.Result<Channel$, $error.AquamarineError$>;

export function connect(
  host: string,
  port: number,
  path: string,
  topic: string,
  payload: $json.Json$,
  codec: $codec.Codec$
): _.Result<Channel$, $error.AquamarineError$>;

export function push(channel: Channel$, event: string, payload: $json.Json$): _.Result<
  undefined,
  $error.AquamarineError$
>;

export function receive(channel: Channel$): _.Result<
  $codec.Incoming$,
  $error.AquamarineError$
>;

export function close(channel: Channel$): _.Result<
  undefined,
  $error.AquamarineError$
>;

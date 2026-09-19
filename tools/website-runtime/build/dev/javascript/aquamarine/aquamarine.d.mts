import type * as $json from "../gleam_json/gleam/json.d.mts";
import type * as $channel from "./aquamarine/channel.d.mts";
import type * as $codec from "./aquamarine/codec.d.mts";
import type * as $error from "./aquamarine/error.d.mts";
import type * as _ from "./gleam.d.mts";

export function connect(
  host: string,
  port: number,
  path: string,
  topic: string,
  payload: $json.Json$,
  codec: $codec.Codec$
): _.Result<$channel.Channel$, $error.AquamarineError$>;

export function push(
  channel: $channel.Channel$,
  event: string,
  payload: $json.Json$
): _.Result<undefined, $error.AquamarineError$>;

export function receive(channel: $channel.Channel$): _.Result<
  $codec.Incoming$,
  $error.AquamarineError$
>;

export function close(channel: $channel.Channel$): _.Result<
  undefined,
  $error.AquamarineError$
>;

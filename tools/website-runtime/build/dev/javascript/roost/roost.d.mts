import type * as $json from "../gleam_json/gleam/json.d.mts";
import type * as $option from "../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "./gleam.d.mts";
import type * as $frame from "./roost/frame.d.mts";

export function encode(
  join_ref: $option.Option$<string>,
  ref: $option.Option$<string>,
  topic: string,
  event: string,
  payload: $json.Json$
): string;

export function decode(text: string): _.Result<
  $frame.Incoming$,
  $frame.DecodeError$
>;

export function encode_heartbeat(ref: string): string;

export function encode_reply(
  join_ref: $option.Option$<string>,
  ref: string,
  topic: string,
  status: $frame.ReplyStatus$,
  response: $json.Json$
): string;

export function is_system_event(event: string): boolean;

export function matches_join_reply(incoming: $frame.Incoming$, join_ref: string): boolean;

export function reply_status(incoming: $frame.Incoming$): _.Result<
  undefined,
  string
>;

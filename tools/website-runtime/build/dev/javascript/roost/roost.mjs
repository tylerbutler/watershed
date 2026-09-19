/// <reference types="./roost.d.mts" />
import * as $json from "../gleam_json/gleam/json.mjs";
import * as $option from "../gleam_stdlib/gleam/option.mjs";
import * as $frame from "./roost/frame.mjs";

/**
 * Encode an outbound Phoenix wire frame.
 */
export function encode(join_ref, ref, topic, event, payload) {
  return $frame.encode(join_ref, ref, topic, event, payload);
}

/**
 * Decode a Phoenix wire JSON string into an inbound frame.
 */
export function decode(text) {
  return $frame.decode(text);
}

/**
 * Encode a Phoenix heartbeat frame.
 */
export function encode_heartbeat(ref) {
  return $frame.encode_heartbeat(ref);
}

/**
 * Encode a Phoenix reply frame.
 */
export function encode_reply(join_ref, ref, topic, status, response) {
  return $frame.encode_reply(join_ref, ref, topic, status, response);
}

/**
 * Check whether an event name is a Phoenix-reserved system event.
 */
export function is_system_event(event) {
  return $frame.is_system_event(event);
}

/**
 * Check whether an inbound frame is the `phx_reply` for the given join.
 */
export function matches_join_reply(incoming, join_ref) {
  return $frame.matches_join_reply(incoming, join_ref);
}

/**
 * Interpret a Phoenix `phx_reply` payload's `status`.
 */
export function reply_status(incoming) {
  return $frame.reply_status(incoming);
}

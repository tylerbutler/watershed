/// <reference types="./phoenix.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some } from "../../gleam_stdlib/gleam/option.mjs";
import * as $roost_frame from "../../roost/roost/frame.mjs";
import * as $aquamarine_codec from "../aquamarine/codec.mjs";
import { Ok, Error } from "../gleam.mjs";

function to_roost(incoming) {
  return new $roost_frame.Incoming(
    incoming.join_ref,
    incoming.ref,
    incoming.topic,
    incoming.event,
    incoming.payload,
  );
}

function reply_status(incoming) {
  return $roost_frame.reply_status(to_roost(incoming));
}

function matches_reply(incoming, join_ref) {
  return $roost_frame.matches_join_reply(to_roost(incoming), join_ref);
}

function encode_push(join_ref, ref, topic, event, payload) {
  return $roost_frame.encode(
    new Some(join_ref),
    new Some(ref),
    topic,
    event,
    payload,
  );
}

function encode_join(ref, topic, payload) {
  return $roost_frame.encode(
    new Some(ref),
    new Some(ref),
    topic,
    $roost_frame.join_event,
    payload,
  );
}

function decode_error(error) {
  if (error instanceof $roost_frame.InvalidJson) {
    let reason = error.reason;
    return new $aquamarine_codec.InvalidJson(reason);
  } else {
    let reason = error.reason;
    return new $aquamarine_codec.InvalidFormat(reason);
  }
}

function decode(text) {
  let $ = $roost_frame.decode(text);
  if ($ instanceof Ok) {
    let incoming = $[0];
    return new Ok(
      new $aquamarine_codec.Incoming(
        incoming.join_ref,
        incoming.ref,
        incoming.topic,
        incoming.event,
        incoming.payload,
      ),
    );
  } else {
    let error = $[0];
    return new Error(decode_error(error));
  }
}

export function codec() {
  return new $aquamarine_codec.Codec(
    decode,
    encode_join,
    encode_push,
    $roost_frame.encode_heartbeat,
    matches_reply,
    reply_status,
    $roost_frame.join_event,
    $roost_frame.reply_event,
    $roost_frame.close_event,
    $roost_frame.error_event,
    $roost_frame.heartbeat_topic,
  );
}

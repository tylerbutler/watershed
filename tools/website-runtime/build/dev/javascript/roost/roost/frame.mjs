/// <reference types="./frame.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";

export class Incoming extends $CustomType {
  constructor(join_ref, ref, topic, event, payload) {
    super();
    this.join_ref = join_ref;
    this.ref = ref;
    this.topic = topic;
    this.event = event;
    this.payload = payload;
  }
}
export const Incoming$Incoming = (join_ref, ref, topic, event, payload) =>
  new Incoming(join_ref, ref, topic, event, payload);
export const Incoming$isIncoming = (value) => value instanceof Incoming;
export const Incoming$Incoming$join_ref = (value) => value.join_ref;
export const Incoming$Incoming$0 = (value) => value.join_ref;
export const Incoming$Incoming$ref = (value) => value.ref;
export const Incoming$Incoming$1 = (value) => value.ref;
export const Incoming$Incoming$topic = (value) => value.topic;
export const Incoming$Incoming$2 = (value) => value.topic;
export const Incoming$Incoming$event = (value) => value.event;
export const Incoming$Incoming$3 = (value) => value.event;
export const Incoming$Incoming$payload = (value) => value.payload;
export const Incoming$Incoming$4 = (value) => value.payload;

export class InvalidJson extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const DecodeError$InvalidJson = (reason) => new InvalidJson(reason);
export const DecodeError$isInvalidJson = (value) =>
  value instanceof InvalidJson;
export const DecodeError$InvalidJson$reason = (value) => value.reason;
export const DecodeError$InvalidJson$0 = (value) => value.reason;

export class InvalidFormat extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const DecodeError$InvalidFormat = (reason) => new InvalidFormat(reason);
export const DecodeError$isInvalidFormat = (value) =>
  value instanceof InvalidFormat;
export const DecodeError$InvalidFormat$reason = (value) => value.reason;
export const DecodeError$InvalidFormat$0 = (value) => value.reason;

export const DecodeError$reason = (value) => value.reason;

export class StatusOk extends $CustomType {}
export const ReplyStatus$StatusOk$const = new StatusOk();
export const ReplyStatus$StatusOk = () => ReplyStatus$StatusOk$const;
export const ReplyStatus$isStatusOk = (value) => value instanceof StatusOk;

export class StatusError extends $CustomType {}
export const ReplyStatus$StatusError$const = new StatusError();
export const ReplyStatus$StatusError = () => ReplyStatus$StatusError$const;
export const ReplyStatus$isStatusError = (value) =>
  value instanceof StatusError;

/**
 * Phoenix heartbeat event.
 */
export const heartbeat_event = "heartbeat";

/**
 * Phoenix heartbeat topic.
 */
export const heartbeat_topic = "phoenix";

/**
 * Phoenix reply event.
 */
export const reply_event = "phx_reply";

/**
 * Phoenix channel close event.
 */
export const close_event = "phx_close";

/**
 * Phoenix channel error event.
 */
export const error_event = "phx_error";

/**
 * Phoenix channel leave event.
 */
export const leave_event = "phx_leave";

/**
 * Phoenix channel join event.
 */
export const join_event = "phx_join";

/**
 * Encode an outbound frame as a Phoenix wire JSON string.
 */
export function encode(join_ref, ref, topic, event, payload) {
  return $json.to_string(
    $json.preprocessed_array(
      toList([
        $json.nullable(join_ref, $json.string),
        $json.nullable(ref, $json.string),
        $json.string(topic),
        $json.string(event),
        payload,
      ]),
    ),
  );
}

/**
 * Encode a Phoenix heartbeat frame.
 *
 * Heartbeats use the reserved topic `"phoenix"` and event `"heartbeat"`,
 * with an empty object payload and no `join_ref`.
 */
export function encode_heartbeat(ref) {
  return encode(
    Option$None$const,
    new Some(ref),
    heartbeat_topic,
    heartbeat_event,
    $json.object($List$Empty$const),
  );
}

/**
 * Encode a Phoenix reply frame.
 */
export function encode_reply(join_ref, ref, topic, status, response) {
  let _block;
  if (status instanceof StatusOk) {
    _block = "ok";
  } else {
    _block = "error";
  }
  let status_string = _block;
  return encode(
    join_ref,
    new Some(ref),
    topic,
    reply_event,
    $json.object(
      toList([["status", $json.string(status_string)], ["response", response]]),
    ),
  );
}

function decode_frame_field(field, decoder, error_message) {
  let _pipe = field;
  let _pipe$1 = $decode.run(_pipe, decoder);
  return $result.replace_error(_pipe$1, new InvalidFormat(error_message));
}

function decode_fields(join_ref, ref, topic, event, payload) {
  return $result.try$(
    decode_frame_field(
      join_ref,
      $decode.optional($decode.string),
      "Expected join_ref to be a string or null",
    ),
    (join_ref) => {
      return $result.try$(
        decode_frame_field(
          ref,
          $decode.optional($decode.string),
          "Expected ref to be a string or null",
        ),
        (ref) => {
          return $result.try$(
            decode_frame_field(
              topic,
              $decode.string,
              "Expected topic to be a string",
            ),
            (topic) => {
              return $result.try$(
                decode_frame_field(
                  event,
                  $decode.string,
                  "Expected event to be a string",
                ),
                (event) => {
                  return new Ok(
                    new Incoming(join_ref, ref, topic, event, payload),
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Decode a Phoenix wire JSON string into an `Incoming`.
 */
export function decode(text) {
  let $ = $json.parse(text, $decode.list($decode.dynamic));
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $Empty) {
      return new Error(
        new InvalidFormat(
          "Expected array of 5 elements [join_ref, ref, topic, event, payload]",
        ),
      );
    } else {
      let $2 = $1.tail;
      if ($2 instanceof $Empty) {
        return new Error(
          new InvalidFormat(
            "Expected array of 5 elements [join_ref, ref, topic, event, payload]",
          ),
        );
      } else {
        let $3 = $2.tail;
        if ($3 instanceof $Empty) {
          return new Error(
            new InvalidFormat(
              "Expected array of 5 elements [join_ref, ref, topic, event, payload]",
            ),
          );
        } else {
          let $4 = $3.tail;
          if ($4 instanceof $Empty) {
            return new Error(
              new InvalidFormat(
                "Expected array of 5 elements [join_ref, ref, topic, event, payload]",
              ),
            );
          } else {
            let $5 = $4.tail;
            if ($5 instanceof $Empty) {
              return new Error(
                new InvalidFormat(
                  "Expected array of 5 elements [join_ref, ref, topic, event, payload]",
                ),
              );
            } else {
              let $6 = $5.tail;
              if ($6 instanceof $Empty) {
                let join_ref = $1.head;
                let ref = $2.head;
                let topic = $3.head;
                let event = $4.head;
                let payload = $5.head;
                return decode_fields(join_ref, ref, topic, event, payload);
              } else {
                return new Error(
                  new InvalidFormat(
                    "Expected array of 5 elements [join_ref, ref, topic, event, payload]",
                  ),
                );
              }
            }
          }
        }
      }
    }
  } else {
    let $1 = $[0];
    if ($1 instanceof $json.UnexpectedEndOfInput) {
      return new Error(new InvalidJson("Unexpected end of input"));
    } else if ($1 instanceof $json.UnexpectedByte) {
      let byte = $1[0];
      return new Error(new InvalidJson("Unexpected byte: " + byte));
    } else if ($1 instanceof $json.UnexpectedSequence) {
      let seq = $1[0];
      return new Error(new InvalidJson("Unexpected sequence: " + seq));
    } else {
      return new Error(
        new InvalidFormat(
          "Expected array of 5 elements [join_ref, ref, topic, event, payload]",
        ),
      );
    }
  }
}

/**
 * Check whether an inbound frame is the `phx_reply` for the given join.
 *
 * True when the event is `phx_reply` and the frame's `ref` matches the
 * `join_ref` the join was sent with. This is the Phoenix correlation rule for
 * pairing a join request with its reply.
 */
export function matches_join_reply(incoming, join_ref) {
  return (incoming.event === reply_event) && (isEqual(
    incoming.ref,
    new Some(join_ref)
  ));
}

/**
 * Interpret a Phoenix `phx_reply` payload's `status`.
 *
 * Returns `Ok(Nil)` when the status is `"ok"` (joined), or `Error(reason)`
 * when the join was rejected. The reason comes from `response.reason` if
 * present, otherwise the status string.
 */
export function reply_status(incoming) {
  let _block;
  let _pipe = incoming.payload;
  let _pipe$1 = $decode.run(
    _pipe,
    $decode.at(toList(["status"]), $decode.string),
  );
  _block = $result.unwrap(_pipe$1, "error");
  let status = _block;
  if (status === "ok") {
    return new Ok(undefined);
  } else {
    let _block$1;
    let _pipe$2 = incoming.payload;
    let _pipe$3 = $decode.run(
      _pipe$2,
      $decode.at(toList(["response", "reason"]), $decode.string),
    );
    _block$1 = $result.unwrap(_pipe$3, status);
    let reason = _block$1;
    return new Error(reason);
  }
}

/**
 * Check whether an event name is a Phoenix-reserved system event.
 */
export function is_system_event(event) {
  let _pipe = toList([
    join_event,
    leave_event,
    reply_event,
    error_event,
    close_event,
    heartbeat_event,
  ]);
  return $list.contains(_pipe, event);
}

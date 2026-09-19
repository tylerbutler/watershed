/// <reference types="./codec.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

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

export class Codec extends $CustomType {
  constructor(decode, encode_join, encode_push, encode_heartbeat, matches_reply, reply_status, join_event, reply_event, close_event, error_event, heartbeat_topic) {
    super();
    this.decode = decode;
    this.encode_join = encode_join;
    this.encode_push = encode_push;
    this.encode_heartbeat = encode_heartbeat;
    this.matches_reply = matches_reply;
    this.reply_status = reply_status;
    this.join_event = join_event;
    this.reply_event = reply_event;
    this.close_event = close_event;
    this.error_event = error_event;
    this.heartbeat_topic = heartbeat_topic;
  }
}
export const Codec$Codec = (decode, encode_join, encode_push, encode_heartbeat, matches_reply, reply_status, join_event, reply_event, close_event, error_event, heartbeat_topic) =>
  new Codec(decode,
  encode_join,
  encode_push,
  encode_heartbeat,
  matches_reply,
  reply_status,
  join_event,
  reply_event,
  close_event,
  error_event,
  heartbeat_topic);
export const Codec$isCodec = (value) => value instanceof Codec;
export const Codec$Codec$decode = (value) => value.decode;
export const Codec$Codec$0 = (value) => value.decode;
export const Codec$Codec$encode_join = (value) => value.encode_join;
export const Codec$Codec$1 = (value) => value.encode_join;
export const Codec$Codec$encode_push = (value) => value.encode_push;
export const Codec$Codec$2 = (value) => value.encode_push;
export const Codec$Codec$encode_heartbeat = (value) => value.encode_heartbeat;
export const Codec$Codec$3 = (value) => value.encode_heartbeat;
export const Codec$Codec$matches_reply = (value) => value.matches_reply;
export const Codec$Codec$4 = (value) => value.matches_reply;
export const Codec$Codec$reply_status = (value) => value.reply_status;
export const Codec$Codec$5 = (value) => value.reply_status;
export const Codec$Codec$join_event = (value) => value.join_event;
export const Codec$Codec$6 = (value) => value.join_event;
export const Codec$Codec$reply_event = (value) => value.reply_event;
export const Codec$Codec$7 = (value) => value.reply_event;
export const Codec$Codec$close_event = (value) => value.close_event;
export const Codec$Codec$8 = (value) => value.close_event;
export const Codec$Codec$error_event = (value) => value.error_event;
export const Codec$Codec$9 = (value) => value.error_event;
export const Codec$Codec$heartbeat_topic = (value) => value.heartbeat_topic;
export const Codec$Codec$10 = (value) => value.heartbeat_topic;

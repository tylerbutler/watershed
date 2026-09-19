/// <reference types="./channel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $codec from "../aquamarine/codec.mjs";
import * as $error from "../aquamarine/error.mjs";
import * as $heartbeat from "../aquamarine/heartbeat.mjs";
import * as $ref from "../aquamarine/ref.mjs";
import * as $transport from "../aquamarine/transport.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";

class Channel extends $CustomType {
  constructor(transport, topic, join_ref, counter, heartbeat, codec) {
    super();
    this.transport = transport;
    this.topic = topic;
    this.join_ref = join_ref;
    this.counter = counter;
    this.heartbeat = heartbeat;
    this.codec = codec;
  }
}

/**
 * Default heartbeat interval, matching the Phoenix JS client.
 * 
 * @ignore
 */
const default_heartbeat_ms = 30_000;

function match_join_reply(tx, join_ref, incoming, codec) {
  let $ = codec.matches_reply(incoming, join_ref);
  if ($) {
    let $1 = codec.reply_status(incoming);
    if ($1 instanceof Ok) {
      return $1;
    } else {
      let reason = $1[0];
      return new Error(new $error.JoinRejected(reason));
    }
  } else {
    return await_join_reply(tx, join_ref, codec);
  }
}

function await_join_reply(tx, join_ref, codec) {
  return $result.try$(
    tx.receive(),
    (frame) => {
      if (frame instanceof $transport.Text) {
        let text = frame.text;
        let $ = codec.decode(text);
        if ($ instanceof Ok) {
          let incoming = $[0];
          return match_join_reply(tx, join_ref, incoming, codec);
        } else {
          let err = $[0];
          return new Error(new $error.DecodeFailed(err));
        }
      } else if (frame instanceof $transport.Binary) {
        return await_join_reply(tx, join_ref, codec);
      } else {
        return new Error($error.AquamarineError$ChannelClosed$const);
      }
    },
  );
}

function handle_incoming(channel, incoming) {
  let $ = incoming.event;
  let e = $;
  if (e === channel.codec.close_event) {
    return new Error($error.AquamarineError$ChannelClosed$const);
  } else {
    let e = $;
    if (e === channel.codec.error_event) {
      return new Error($error.AquamarineError$ChannelClosed$const);
    } else {
      let e = $;
      if (
        (e === channel.codec.reply_event) && (incoming.topic === channel.codec.heartbeat_topic)
      ) {
        return do_receive(channel);
      } else {
        return new Ok(incoming);
      }
    }
  }
}

function do_receive(channel) {
  return $result.try$(
    channel.transport.receive(),
    (frame) => {
      if (frame instanceof $transport.Text) {
        let text = frame.text;
        let $ = channel.codec.decode(text);
        if ($ instanceof Ok) {
          let incoming = $[0];
          return handle_incoming(channel, incoming);
        } else {
          let err = $[0];
          return new Error(new $error.DecodeFailed(err));
        }
      } else if (frame instanceof $transport.Binary) {
        return do_receive(channel);
      } else {
        return new Error($error.AquamarineError$ChannelClosed$const);
      }
    },
  );
}

/**
 * Receive the next inbound frame on the channel.
 *
 * Skips heartbeat replies so the caller only sees real channel activity.
 * Returns `Error(ChannelClosed)` if the server sent a close/error event, or
 * the socket itself closed.
 */
export function receive(channel) {
  return do_receive(channel);
}

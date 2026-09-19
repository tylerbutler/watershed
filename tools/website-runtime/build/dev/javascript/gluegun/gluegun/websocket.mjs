/// <reference types="./websocket.d.mts" />
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
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
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $connection from "../gluegun/connection.mjs";
import * as $error from "../gluegun/error.mjs";
import * as $internal from "../gluegun/internal.mjs";
import * as $ffi_result from "../gluegun/internal/ffi_result.mjs";
import * as $message from "../gluegun/message.mjs";
import * as $request from "../gluegun/request.mjs";

class Socket extends $CustomType {
  constructor(connection, stream, timeout) {
    super();
    this.connection = connection;
    this.stream = stream;
    this.timeout = timeout;
  }
}

class Options extends $CustomType {
  constructor(connect_options, headers, upgrade_options, timeout) {
    super();
    this.connect_options = connect_options;
    this.headers = headers;
    this.upgrade_options = upgrade_options;
    this.timeout = timeout;
  }
}

class UpgradeOptions extends $CustomType {
  constructor(closing_timeout, compress, default_protocol, flow, keepalive, protocols, reply_to, silence_pings, tunnel, user_opts) {
    super();
    this.closing_timeout = closing_timeout;
    this.compress = compress;
    this.default_protocol = default_protocol;
    this.flow = flow;
    this.keepalive = keepalive;
    this.protocols = protocols;
    this.reply_to = reply_to;
    this.silence_pings = silence_pings;
    this.tunnel = tunnel;
    this.user_opts = user_opts;
  }
}

/**
 * Construct a reusable WebSocket handle from an upgraded connection and stream.
 * 
 * @ignore
 */
export function socket(connection, stream, timeout) {
  return new Socket(connection, stream, timeout);
}

/**
 * Construct default WebSocket upgrade options.
 */
export function upgrade_options() {
  return new UpgradeOptions(
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    $List$Empty$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
  );
}

/**
 * Construct default high-level WebSocket connection options.
 */
export function options() {
  return new Options(
    (() => {
      let _pipe = $connection.options();
      return $connection.with_protocols(
        _pipe,
        toList([$connection.Protocol$Http1$const]),
      );
    })(),
    $List$Empty$const,
    upgrade_options(),
    new $connection.Milliseconds(5000),
  );
}

/**
 * Set headers sent with the WebSocket upgrade request.
 */
export function with_headers(options, headers) {
  return new Options(
    options.connect_options,
    headers,
    options.upgrade_options,
    options.timeout,
  );
}

/**
 * Set Gun connection options used when opening the connection.
 */
export function with_connect_options(options, connect) {
  return new Options(
    connect,
    options.headers,
    options.upgrade_options,
    options.timeout,
  );
}

/**
 * Set Gun WebSocket upgrade options used for the upgrade request.
 */
export function with_upgrade_options(options, upgrade) {
  return new Options(
    options.connect_options,
    options.headers,
    upgrade,
    options.timeout,
  );
}

/**
 * Set the timeout used when awaiting connection readiness, upgrade, and frames.
 */
export function with_timeout(options, timeout) {
  return new Options(
    options.connect_options,
    options.headers,
    options.upgrade_options,
    timeout,
  );
}

/**
 * Inspect configured upgrade headers. Intended for deterministic tests.
 * 
 * @ignore
 */
export function options_headers(options) {
  return options.headers;
}

/**
 * Inspect configured connection options. Intended for deterministic tests.
 * 
 * @ignore
 */
export function options_connect_options(options) {
  return options.connect_options;
}

/**
 * Inspect configured upgrade options. Intended for deterministic tests.
 * 
 * @ignore
 */
export function options_upgrade_options(options) {
  return options.upgrade_options;
}

/**
 * Inspect configured timeout. Intended for deterministic tests.
 * 
 * @ignore
 */
export function options_timeout(options) {
  return options.timeout;
}

/**
 * Route a pre-resolved message result to an upgrade confirmation.
 *
 * This is an internal helper exposed for deterministic unit testing.
 * Production callers should use `await_upgrade/3` instead.
 * 
 * @ignore
 */
export function await_upgrade_from(message_result) {
  return $result.try$(
    message_result,
    (msg) => {
      if (msg instanceof $message.Upgrade) {
        return new Ok(undefined);
      } else {
        return new Error(
          new $error.InvalidMessage(
            "websocket.await_upgrade: expected Upgrade message",
          ),
        );
      }
    },
  );
}

function prepend_optional_dynamic(fields, key, value) {
  if (value instanceof Some) {
    let value$1 = value[0];
    return listPrepend([$dynamic.string(key), value$1], fields);
  } else {
    return fields;
  }
}

function prepend_optional_bool(fields, key, value) {
  if (value instanceof Some) {
    let value$1 = value[0];
    return listPrepend([$dynamic.string(key), $dynamic.bool(value$1)], fields);
  } else {
    return fields;
  }
}

function prepend_protocols(fields, protocols) {
  if (protocols instanceof $Empty) {
    return fields;
  } else {
    let protocols$1 = protocols;
    return listPrepend(
      [
        $dynamic.string("protocols"),
        $dynamic.list(
          $list.map(
            protocols$1,
            (protocol) => {
              return $dynamic.array(
                toList([
                  $dynamic.string(protocol[0]),
                  $dynamic.string(protocol[1]),
                ]),
              );
            },
          ),
        ),
      ],
      fields,
    );
  }
}

function prepend_optional_int(fields, key, value) {
  if (value instanceof Some) {
    let value$1 = value[0];
    return listPrepend([$dynamic.string(key), $dynamic.int(value$1)], fields);
  } else {
    return fields;
  }
}

function prepend_optional_string(fields, key, value) {
  if (value instanceof Some) {
    let value$1 = value[0];
    return listPrepend([$dynamic.string(key), $dynamic.string(value$1)], fields);
  } else {
    return fields;
  }
}

/**
 * Combine callback and cleanup results using `with_socket` error precedence.
 * 
 * @ignore
 */
export function with_socket_result(
  callback_result,
  close_frame_result,
  close_connection_result
) {
  if (callback_result instanceof Ok) {
    let value = callback_result[0];
    if (close_frame_result instanceof Ok) {
      if (close_connection_result instanceof Ok) {
        return new Ok(value);
      } else {
        return close_connection_result;
      }
    } else {
      return close_frame_result;
    }
  } else {
    return callback_result;
  }
}

/**
 * Set Gun's WebSocket closing timeout.
 */
export function with_closing_timeout(options, timeout) {
  return new UpgradeOptions(
    new Some(timeout),
    options.compress,
    options.default_protocol,
    options.flow,
    options.keepalive,
    options.protocols,
    options.reply_to,
    options.silence_pings,
    options.tunnel,
    options.user_opts,
  );
}

/**
 * Enable or disable WebSocket compression.
 */
export function with_compress(options, enabled) {
  return new UpgradeOptions(
    options.closing_timeout,
    new Some(enabled),
    options.default_protocol,
    options.flow,
    options.keepalive,
    options.protocols,
    options.reply_to,
    options.silence_pings,
    options.tunnel,
    options.user_opts,
  );
}

/**
 * Set the initial WebSocket flow-control allowance.
 */
export function with_flow(options, initial_flow) {
  return new UpgradeOptions(
    options.closing_timeout,
    options.compress,
    options.default_protocol,
    new Some(initial_flow),
    options.keepalive,
    options.protocols,
    options.reply_to,
    options.silence_pings,
    options.tunnel,
    options.user_opts,
  );
}

/**
 * Set Gun's WebSocket keepalive timeout.
 */
export function with_keepalive(options, timeout) {
  return new UpgradeOptions(
    options.closing_timeout,
    options.compress,
    options.default_protocol,
    options.flow,
    new Some(timeout),
    options.protocols,
    options.reply_to,
    options.silence_pings,
    options.tunnel,
    options.user_opts,
  );
}

/**
 * Enable or disable silencing automatic ping frames.
 */
export function with_silence_pings(options, enabled) {
  return new UpgradeOptions(
    options.closing_timeout,
    options.compress,
    options.default_protocol,
    options.flow,
    options.keepalive,
    options.protocols,
    options.reply_to,
    new Some(enabled),
    options.tunnel,
    options.user_opts,
  );
}

/**
 * Set the default WebSocket protocol callback module.
 */
export function with_default_protocol_module(options, module_name) {
  return new UpgradeOptions(
    options.closing_timeout,
    options.compress,
    new Some(module_name),
    options.flow,
    options.keepalive,
    options.protocols,
    options.reply_to,
    options.silence_pings,
    options.tunnel,
    options.user_opts,
  );
}

/**
 * Add a WebSocket subprotocol callback module.
 */
export function with_protocol_module(options, protocol, module_name) {
  return new UpgradeOptions(
    options.closing_timeout,
    options.compress,
    options.default_protocol,
    options.flow,
    options.keepalive,
    $list.append(options.protocols, toList([[protocol, module_name]])),
    options.reply_to,
    options.silence_pings,
    options.tunnel,
    options.user_opts,
  );
}

/**
 * Set Gun's raw `reply_to` option.
 */
export function with_reply_to_dynamic(options, reply_to) {
  return new UpgradeOptions(
    options.closing_timeout,
    options.compress,
    options.default_protocol,
    options.flow,
    options.keepalive,
    options.protocols,
    new Some(reply_to),
    options.silence_pings,
    options.tunnel,
    options.user_opts,
  );
}

/**
 * Set Gun's raw `tunnel` option.
 */
export function with_tunnel_dynamic(options, tunnel) {
  return new UpgradeOptions(
    options.closing_timeout,
    options.compress,
    options.default_protocol,
    options.flow,
    options.keepalive,
    options.protocols,
    options.reply_to,
    options.silence_pings,
    new Some(tunnel),
    options.user_opts,
  );
}

/**
 * Set Gun's raw `user_opts` option.
 */
export function with_user_opts_dynamic(options, user_opts) {
  return new UpgradeOptions(
    options.closing_timeout,
    options.compress,
    options.default_protocol,
    options.flow,
    options.keepalive,
    options.protocols,
    options.reply_to,
    options.silence_pings,
    options.tunnel,
    new Some(user_opts),
  );
}

/**
 * Route a pre-resolved message result to a WebSocket frame.
 *
 * This is an internal helper exposed for deterministic unit testing.
 * Production callers should use `receive/3` instead.
 * 
 * @ignore
 */
export function receive_from(message_result) {
  return $result.try$(
    message_result,
    (msg) => {
      if (msg instanceof $message.Upgrade) {
        return new Error(
          new $error.InvalidMessage(
            "websocket.receive: expected WebSocket frame, got Upgrade message; call await_upgrade first",
          ),
        );
      } else if (msg instanceof $message.WebSocket) {
        let frame = msg.frame;
        return new Ok(frame);
      } else {
        return new Error(
          new $error.InvalidMessage(
            "websocket.receive: expected WebSocket frame, got HTTP message",
          ),
        );
      }
    },
  );
}

/**
 * Route pre-resolved frame results through application-frame handling.
 *
 * This is an internal helper exposed for deterministic unit testing.
 * Production callers should use `receive_app_frame/1` instead.
 * 
 * @ignore
 */
export function receive_app_frame_from(frame_results, send_pong) {
  if (frame_results instanceof $Empty) {
    return new Error(
      new $error.InvalidMessage(
        "websocket.receive_app_frame: expected WebSocket application frame",
      ),
    );
  } else {
    let frame_result = frame_results.head;
    let rest = frame_results.tail;
    return $result.try$(
      frame_result,
      (frame) => {
        if (frame instanceof $message.Text) {
          return new Ok(frame);
        } else if (frame instanceof $message.Binary) {
          return new Ok(frame);
        } else if (frame instanceof $message.Ping) {
          let payload = frame[0];
          return $result.try$(
            send_pong(payload),
            (_) => { return receive_app_frame_from(rest, send_pong); },
          );
        } else if (frame instanceof $message.Pong) {
          return receive_app_frame_from(rest, send_pong);
        } else if (frame instanceof $message.Close) {
          return new Ok(frame);
        } else {
          return new Ok(frame);
        }
      },
    );
  }
}

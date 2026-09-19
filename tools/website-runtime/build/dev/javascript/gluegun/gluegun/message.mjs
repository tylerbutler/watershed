/// <reference types="./message.d.mts" />
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $dyn_decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { toList, CustomType as $CustomType, toBitArray, stringBits } from "../gleam.mjs";
import * as $connection from "../gluegun/connection.mjs";
import { timeout_to_ffi } from "../gluegun/connection.mjs";
import * as $error from "../gluegun/error.mjs";
import * as $fin from "../gluegun/fin.mjs";
import { Fin$NoFin$const, Fin$Fin$const } from "../gluegun/fin.mjs";
import * as $internal from "../gluegun/internal.mjs";
import * as $request from "../gluegun/request.mjs";
import {
  Custom,
  Method$Head$const,
  Method$Connect$const,
  Method$Put$const,
  Method$Get$const,
  Method$Delete$const,
  Method$Trace$const,
  Method$Options$const,
  Method$Patch$const,
  Method$Post$const,
} from "../gluegun/request.mjs";

export class Text extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Frame$Text = ($0) => new Text($0);
export const Frame$isText = (value) => value instanceof Text;
export const Frame$Text$0 = (value) => value[0];

export class Binary extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Frame$Binary = ($0) => new Binary($0);
export const Frame$isBinary = (value) => value instanceof Binary;
export const Frame$Binary$0 = (value) => value[0];

export class Ping extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Frame$Ping = ($0) => new Ping($0);
export const Frame$isPing = (value) => value instanceof Ping;
export const Frame$Ping$0 = (value) => value[0];

export class Pong extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Frame$Pong = ($0) => new Pong($0);
export const Frame$isPong = (value) => value instanceof Pong;
export const Frame$Pong$0 = (value) => value[0];

export class Close extends $CustomType {}
export const Frame$Close$const = new Close();
export const Frame$Close = () => Frame$Close$const;
export const Frame$isClose = (value) => value instanceof Close;

export class CloseWithReason extends $CustomType {
  constructor(code, reason) {
    super();
    this.code = code;
    this.reason = reason;
  }
}
export const Frame$CloseWithReason = (code, reason) =>
  new CloseWithReason(code, reason);
export const Frame$isCloseWithReason = (value) =>
  value instanceof CloseWithReason;
export const Frame$CloseWithReason$code = (value) => value.code;
export const Frame$CloseWithReason$0 = (value) => value.code;
export const Frame$CloseWithReason$reason = (value) => value.reason;
export const Frame$CloseWithReason$1 = (value) => value.reason;

export class Inform extends $CustomType {
  constructor(status, headers) {
    super();
    this.status = status;
    this.headers = headers;
  }
}
export const Message$Inform = (status, headers) => new Inform(status, headers);
export const Message$isInform = (value) => value instanceof Inform;
export const Message$Inform$status = (value) => value.status;
export const Message$Inform$0 = (value) => value.status;
export const Message$Inform$headers = (value) => value.headers;
export const Message$Inform$1 = (value) => value.headers;

export class Response extends $CustomType {
  constructor(fin, status, headers) {
    super();
    this.fin = fin;
    this.status = status;
    this.headers = headers;
  }
}
export const Message$Response = (fin, status, headers) =>
  new Response(fin, status, headers);
export const Message$isResponse = (value) => value instanceof Response;
export const Message$Response$fin = (value) => value.fin;
export const Message$Response$0 = (value) => value.fin;
export const Message$Response$status = (value) => value.status;
export const Message$Response$1 = (value) => value.status;
export const Message$Response$headers = (value) => value.headers;
export const Message$Response$2 = (value) => value.headers;

export class Data extends $CustomType {
  constructor(fin, data) {
    super();
    this.fin = fin;
    this.data = data;
  }
}
export const Message$Data = (fin, data) => new Data(fin, data);
export const Message$isData = (value) => value instanceof Data;
export const Message$Data$fin = (value) => value.fin;
export const Message$Data$0 = (value) => value.fin;
export const Message$Data$data = (value) => value.data;
export const Message$Data$1 = (value) => value.data;

export class Trailers extends $CustomType {
  constructor(headers) {
    super();
    this.headers = headers;
  }
}
export const Message$Trailers = (headers) => new Trailers(headers);
export const Message$isTrailers = (value) => value instanceof Trailers;
export const Message$Trailers$headers = (value) => value.headers;
export const Message$Trailers$0 = (value) => value.headers;

export class Push extends $CustomType {
  constructor(stream, method, uri, headers) {
    super();
    this.stream = stream;
    this.method = method;
    this.uri = uri;
    this.headers = headers;
  }
}
export const Message$Push = (stream, method, uri, headers) =>
  new Push(stream, method, uri, headers);
export const Message$isPush = (value) => value instanceof Push;
export const Message$Push$stream = (value) => value.stream;
export const Message$Push$0 = (value) => value.stream;
export const Message$Push$method = (value) => value.method;
export const Message$Push$1 = (value) => value.method;
export const Message$Push$uri = (value) => value.uri;
export const Message$Push$2 = (value) => value.uri;
export const Message$Push$headers = (value) => value.headers;
export const Message$Push$3 = (value) => value.headers;

export class Upgrade extends $CustomType {
  constructor(protocols, headers) {
    super();
    this.protocols = protocols;
    this.headers = headers;
  }
}
export const Message$Upgrade = (protocols, headers) =>
  new Upgrade(protocols, headers);
export const Message$isUpgrade = (value) => value instanceof Upgrade;
export const Message$Upgrade$protocols = (value) => value.protocols;
export const Message$Upgrade$0 = (value) => value.protocols;
export const Message$Upgrade$headers = (value) => value.headers;
export const Message$Upgrade$1 = (value) => value.headers;

export class WebSocket extends $CustomType {
  constructor(frame) {
    super();
    this.frame = frame;
  }
}
export const Message$WebSocket = (frame) => new WebSocket(frame);
export const Message$isWebSocket = (value) => value instanceof WebSocket;
export const Message$WebSocket$frame = (value) => value.frame;
export const Message$WebSocket$0 = (value) => value.frame;

function message_decode_placeholder() {
  return new Data(
    Fin$NoFin$const,
    toBitArray([stringBits("gluegun decode failure placeholder")]),
  );
}

function fail_message_decode() {
  return $dyn_decode.failure(message_decode_placeholder(), "Message");
}

function frame_decode_placeholder() {
  return new Text("gluegun decode failure placeholder");
}

function fail_frame_decode() {
  return $dyn_decode.failure(frame_decode_placeholder(), "Frame");
}

function pong_frame_decoder() {
  return $dyn_decode.field(
    "data",
    $dyn_decode.bit_array,
    (data) => { return $dyn_decode.success(new Pong(data)); },
  );
}

function ping_frame_decoder() {
  return $dyn_decode.field(
    "data",
    $dyn_decode.bit_array,
    (data) => { return $dyn_decode.success(new Ping(data)); },
  );
}

function close_with_reason_frame_decoder() {
  return $dyn_decode.field(
    "code",
    $dyn_decode.int,
    (code) => {
      return $dyn_decode.field(
        "reason",
        $dyn_decode.bit_array,
        (reason) => {
          return $dyn_decode.success(new CloseWithReason(code, reason));
        },
      );
    },
  );
}

function binary_frame_decoder() {
  return $dyn_decode.field(
    "data",
    $dyn_decode.bit_array,
    (data) => { return $dyn_decode.success(new Binary(data)); },
  );
}

function text_frame_decoder() {
  return $dyn_decode.field(
    "data",
    $dyn_decode.string,
    (data) => { return $dyn_decode.success(new Text(data)); },
  );
}

function frame_decoder() {
  return $dyn_decode.field(
    "type",
    $dyn_decode.string,
    (tag) => {
      if (tag === "text") {
        return text_frame_decoder();
      } else if (tag === "binary") {
        return binary_frame_decoder();
      } else if (tag === "close") {
        return $dyn_decode.success(Frame$Close$const);
      } else if (tag === "close_with_reason") {
        return close_with_reason_frame_decoder();
      } else if (tag === "ping") {
        return ping_frame_decoder();
      } else if (tag === "pong") {
        return pong_frame_decoder();
      } else {
        return fail_frame_decode();
      }
    },
  );
}

function websocket_decoder() {
  return $dyn_decode.field(
    "frame",
    frame_decoder(),
    (frame) => { return $dyn_decode.success(new WebSocket(frame)); },
  );
}

function header_decoder() {
  return $dyn_decode.then$(
    $dyn_decode.at(toList([0]), $dyn_decode.string),
    (name) => {
      return $dyn_decode.map(
        $dyn_decode.at(toList([1]), $dyn_decode.string),
        (value) => { return [name, value]; },
      );
    },
  );
}

function headers_decoder() {
  return $dyn_decode.map(
    $dyn_decode.list(header_decoder()),
    $request.normalize_headers,
  );
}

function upgrade_decoder() {
  return $dyn_decode.field(
    "protocols",
    $dyn_decode.list($dyn_decode.string),
    (protocols) => {
      return $dyn_decode.field(
        "headers",
        headers_decoder(),
        (headers) => {
          return $dyn_decode.success(new Upgrade(protocols, headers));
        },
      );
    },
  );
}

function method_decoder() {
  return $dyn_decode.map(
    $dyn_decode.string,
    (method) => {
      let $ = $string.uppercase(method);
      if ($ === "GET") {
        return Method$Get$const;
      } else if ($ === "HEAD") {
        return Method$Head$const;
      } else if ($ === "POST") {
        return Method$Post$const;
      } else if ($ === "PUT") {
        return Method$Put$const;
      } else if ($ === "PATCH") {
        return Method$Patch$const;
      } else if ($ === "DELETE") {
        return Method$Delete$const;
      } else if ($ === "OPTIONS") {
        return Method$Options$const;
      } else if ($ === "TRACE") {
        return Method$Trace$const;
      } else if ($ === "CONNECT") {
        return Method$Connect$const;
      } else {
        return new Custom(method);
      }
    },
  );
}

function stream_decoder() {
  return $dyn_decode.map($dyn_decode.dynamic, $internal.stream);
}

function push_decoder() {
  return $dyn_decode.field(
    "stream",
    stream_decoder(),
    (stream) => {
      return $dyn_decode.field(
        "method",
        method_decoder(),
        (method) => {
          return $dyn_decode.field(
            "uri",
            $dyn_decode.string,
            (uri) => {
              return $dyn_decode.field(
                "headers",
                headers_decoder(),
                (headers) => {
                  return $dyn_decode.success(
                    new Push(stream, method, uri, headers),
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

function trailers_decoder() {
  return $dyn_decode.field(
    "headers",
    headers_decoder(),
    (headers) => { return $dyn_decode.success(new Trailers(headers)); },
  );
}

function fin_decoder() {
  return $dyn_decode.map(
    $dyn_decode.bool,
    (fin) => {
      if (fin) {
        return Fin$Fin$const;
      } else {
        return Fin$NoFin$const;
      }
    },
  );
}

function data_decoder() {
  return $dyn_decode.field(
    "fin",
    fin_decoder(),
    (fin) => {
      return $dyn_decode.field(
        "data",
        $dyn_decode.bit_array,
        (data) => { return $dyn_decode.success(new Data(fin, data)); },
      );
    },
  );
}

function response_decoder() {
  return $dyn_decode.field(
    "fin",
    fin_decoder(),
    (fin) => {
      return $dyn_decode.field(
        "status",
        $dyn_decode.int,
        (status) => {
          return $dyn_decode.field(
            "headers",
            headers_decoder(),
            (headers) => {
              return $dyn_decode.success(new Response(fin, status, headers));
            },
          );
        },
      );
    },
  );
}

function inform_decoder() {
  return $dyn_decode.field(
    "status",
    $dyn_decode.int,
    (status) => {
      return $dyn_decode.field(
        "headers",
        headers_decoder(),
        (headers) => { return $dyn_decode.success(new Inform(status, headers)); },
      );
    },
  );
}

function message_decoder() {
  return $dyn_decode.field(
    "type",
    $dyn_decode.string,
    (tag) => {
      if (tag === "inform") {
        return inform_decoder();
      } else if (tag === "response") {
        return response_decoder();
      } else if (tag === "data") {
        return data_decoder();
      } else if (tag === "trailers") {
        return trailers_decoder();
      } else if (tag === "push") {
        return push_decoder();
      } else if (tag === "upgrade") {
        return upgrade_decoder();
      } else if (tag === "websocket") {
        return websocket_decoder();
      } else if (tag === "ws") {
        return websocket_decoder();
      } else {
        return fail_message_decode();
      }
    },
  );
}

/**
 * Decode a raw Erlang Gun message into a typed Gleam message.
 */
export function decode(data) {
  let _pipe = $dyn_decode.run(data, message_decoder());
  return $result.map_error(
    _pipe,
    (_) => { return new $error.DecodeError("Invalid Gun message"); },
  );
}

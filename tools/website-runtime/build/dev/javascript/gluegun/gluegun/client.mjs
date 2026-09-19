/// <reference types="./client.d.mts" />
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  toBitArray,
} from "../gleam.mjs";
import * as $connection from "../gluegun/connection.mjs";
import { Milliseconds } from "../gluegun/connection.mjs";
import * as $error from "../gluegun/error.mjs";
import * as $fin from "../gluegun/fin.mjs";
import * as $internal from "../gluegun/internal.mjs";
import * as $message from "../gluegun/message.mjs";
import * as $low_request from "../gluegun/request.mjs";
import * as $response from "../gluegun/response.mjs";

class Request extends $CustomType {
  constructor(method, path, headers, body, options, timeout) {
    super();
    this.method = method;
    this.path = path;
    this.headers = headers;
    this.body = body;
    this.options = options;
    this.timeout = timeout;
  }
}

export class RequestFields extends $CustomType {
  constructor(method, path, headers, body, options, timeout) {
    super();
    this.method = method;
    this.path = path;
    this.headers = headers;
    this.body = body;
    this.options = options;
    this.timeout = timeout;
  }
}
export const RequestFields$RequestFields = (method, path, headers, body, options, timeout) =>
  new RequestFields(method, path, headers, body, options, timeout);
export const RequestFields$isRequestFields = (value) =>
  value instanceof RequestFields;
export const RequestFields$RequestFields$method = (value) => value.method;
export const RequestFields$RequestFields$0 = (value) => value.method;
export const RequestFields$RequestFields$path = (value) => value.path;
export const RequestFields$RequestFields$1 = (value) => value.path;
export const RequestFields$RequestFields$headers = (value) => value.headers;
export const RequestFields$RequestFields$2 = (value) => value.headers;
export const RequestFields$RequestFields$body = (value) => value.body;
export const RequestFields$RequestFields$3 = (value) => value.body;
export const RequestFields$RequestFields$options = (value) => value.options;
export const RequestFields$RequestFields$4 = (value) => value.options;
export const RequestFields$RequestFields$timeout = (value) => value.timeout;
export const RequestFields$RequestFields$5 = (value) => value.timeout;

class AwaitingResponse extends $CustomType {
  constructor(informational) {
    super();
    this.informational = informational;
  }
}

class Collecting extends $CustomType {
  constructor(status, headers, chunks, trailers, informational) {
    super();
    this.status = status;
    this.headers = headers;
    this.chunks = chunks;
    this.trailers = trailers;
    this.informational = informational;
  }
}

class Continue extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Done extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

/**
 * Construct a collected HTTP request command.
 */
export function new$(method, path) {
  return new Request(
    method,
    path,
    $List$Empty$const,
    toBitArray([]),
    $low_request.options(),
    new Milliseconds(5000),
  );
}

/**
 * Append a single request header.
 */
export function with_header(request, name, value) {
  return new Request(
    request.method,
    request.path,
    $list.append(request.headers, toList([[name, value]])),
    request.body,
    request.options,
    request.timeout,
  );
}

/**
 * Append request headers.
 */
export function with_headers(request, headers) {
  return new Request(
    request.method,
    request.path,
    $list.append(request.headers, headers),
    request.body,
    request.options,
    request.timeout,
  );
}

/**
 * Replace the request body.
 */
export function with_body(request, body) {
  return new Request(
    request.method,
    request.path,
    request.headers,
    body,
    request.options,
    request.timeout,
  );
}

/**
 * Replace low-level request options.
 */
export function with_options(request, options) {
  return new Request(
    request.method,
    request.path,
    request.headers,
    request.body,
    options,
    request.timeout,
  );
}

/**
 * Replace the request timeout.
 */
export function with_timeout(request, timeout) {
  return new Request(
    request.method,
    request.path,
    request.headers,
    request.body,
    request.options,
    timeout,
  );
}

/**
 * Inspect a request command.
 * 
 * @ignore
 */
export function inspect_request(request) {
  return new RequestFields(
    request.method,
    request.path,
    request.headers,
    request.body,
    request.options,
    request.timeout,
  );
}

function invalid(message) {
  return new Error(new $error.InvalidMessage(message));
}

function build_response(status, headers, chunks, trailers, informational) {
  let _pipe = $response.new$(
    status,
    headers,
    $bit_array.concat($list.reverse(chunks)),
    trailers,
  );
  return $response.with_informational(_pipe, informational);
}

function step(collection, message) {
  if (message instanceof $message.Inform) {
    let status = message.status;
    let headers = message.headers;
    if (collection instanceof AwaitingResponse) {
      let informational = collection.informational;
      return new Ok(
        new Continue(
          new AwaitingResponse(
            $list.append(informational, toList([[status, headers]])),
          ),
        ),
      );
    } else {
      return invalid(
        "HTTP helper received informational response after final response",
      );
    }
  } else if (message instanceof $message.Response) {
    let fin = message.fin;
    let status = message.status;
    let headers = message.headers;
    if (collection instanceof AwaitingResponse) {
      let informational = collection.informational;
      if (fin instanceof $fin.Fin) {
        return new Ok(
          new Done(
            build_response(
              status,
              headers,
              $List$Empty$const,
              $List$Empty$const,
              informational,
            ),
          ),
        );
      } else {
        return new Ok(
          new Continue(
            new Collecting(
              status,
              headers,
              $List$Empty$const,
              $List$Empty$const,
              informational,
            ),
          ),
        );
      }
    } else {
      return invalid("HTTP helper received duplicate response");
    }
  } else if (message instanceof $message.Data) {
    let fin = message.fin;
    let data = message.data;
    if (collection instanceof AwaitingResponse) {
      return invalid("HTTP helper received body before response");
    } else {
      let status = collection.status;
      let headers = collection.headers;
      let chunks = collection.chunks;
      let trailers = collection.trailers;
      let informational = collection.informational;
      let chunks$1 = listPrepend(data, chunks);
      if (fin instanceof $fin.Fin) {
        return new Ok(
          new Done(
            build_response(status, headers, chunks$1, trailers, informational),
          ),
        );
      } else {
        return new Ok(
          new Continue(
            new Collecting(status, headers, chunks$1, trailers, informational),
          ),
        );
      }
    }
  } else if (message instanceof $message.Trailers) {
    let headers = message.headers;
    if (collection instanceof AwaitingResponse) {
      return invalid("HTTP helper received trailers before response");
    } else {
      let status = collection.status;
      let response_headers = collection.headers;
      let chunks = collection.chunks;
      let trailers = collection.trailers;
      let informational = collection.informational;
      return new Ok(
        new Done(
          build_response(
            status,
            response_headers,
            chunks,
            $list.append(trailers, headers),
            informational,
          ),
        ),
      );
    }
  } else if (message instanceof $message.Push) {
    return invalid("HTTP helper received push message");
  } else if (message instanceof $message.Upgrade) {
    return invalid("HTTP helper received upgrade message");
  } else {
    return invalid("HTTP helper received websocket message");
  }
}

function collect_stream_with(connection, stream, collection, timeout, await_fn) {
  return $result.try$(
    await_fn(connection, stream, timeout),
    (awaited) => {
      return $result.try$(
        step(collection, awaited),
        (next) => {
          if (next instanceof Continue) {
            let collection$1 = next[0];
            return collect_stream_with(
              connection,
              stream,
              collection$1,
              timeout,
              await_fn,
            );
          } else {
            let response = next[0];
            return new Ok(response);
          }
        },
      );
    },
  );
}

export function request_with(
  connection,
  method,
  path,
  headers,
  body,
  options,
  timeout,
  request_fn,
  await_fn
) {
  return $result.try$(
    request_fn(connection, method, path, headers, body, options),
    (stream) => {
      return collect_stream_with(
        connection,
        stream,
        new AwaitingResponse($List$Empty$const),
        timeout,
        await_fn,
      );
    },
  );
}

function finalize_end(collection) {
  if (collection instanceof AwaitingResponse) {
    return invalid("HTTP helper stream ended before response");
  } else {
    return invalid("HTTP helper stream ended before final message");
  }
}

function collect_message_results(messages, collection) {
  if (messages instanceof $Empty) {
    return finalize_end(collection);
  } else {
    let message_result = messages.head;
    let rest = messages.tail;
    return $result.try$(
      message_result,
      (awaited) => {
        return $result.try$(
          step(collection, awaited),
          (next) => {
            if (next instanceof Continue) {
              let collection$1 = next[0];
              return collect_message_results(rest, collection$1);
            } else {
              let response = next[0];
              return new Ok(response);
            }
          },
        );
      },
    );
  }
}

export function collect_messages(messages) {
  return collect_message_results(
    messages,
    new AwaitingResponse($List$Empty$const),
  );
}

export function get_with(
  connection,
  path,
  headers,
  timeout,
  request_fn,
  await_fn
) {
  return request_with(
    connection,
    $low_request.Method$Get$const,
    path,
    headers,
    toBitArray([]),
    $low_request.options(),
    timeout,
    request_fn,
    await_fn,
  );
}

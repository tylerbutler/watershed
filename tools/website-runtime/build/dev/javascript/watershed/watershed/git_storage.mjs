/// <reference types="./git_storage.d.mts" />
import * as $fetch from "../../gleam_fetch/gleam/fetch.mjs";
import * as $http from "../../gleam_http/gleam/http.mjs";
import * as $request from "../../gleam_http/gleam/http/request.mjs";
import * as $response from "../../gleam_http/gleam/http/response.mjs";
import * as $promise from "../../gleam_javascript/gleam/javascript/promise.mjs";
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $types from "../../spillway/spillway/types.mjs";
import { Ok, Error, toList, CustomType as $CustomType, toBitArray, stringBits } from "../gleam.mjs";
import * as $channel from "../watershed/channel.mjs";
import * as $socket from "../watershed/wire/socket.mjs";
import * as $summary_blob from "../watershed/wire/summary_blob.mjs";

export class SummaryVersion extends $CustomType {
  constructor(id, tree_id, message, created_at) {
    super();
    this.id = id;
    this.tree_id = tree_id;
    this.message = message;
    this.created_at = created_at;
  }
}
export const SummaryVersion$SummaryVersion = (id, tree_id, message, created_at) =>
  new SummaryVersion(id, tree_id, message, created_at);
export const SummaryVersion$isSummaryVersion = (value) =>
  value instanceof SummaryVersion;
export const SummaryVersion$SummaryVersion$id = (value) => value.id;
export const SummaryVersion$SummaryVersion$0 = (value) => value.id;
export const SummaryVersion$SummaryVersion$tree_id = (value) => value.tree_id;
export const SummaryVersion$SummaryVersion$1 = (value) => value.tree_id;
export const SummaryVersion$SummaryVersion$message = (value) => value.message;
export const SummaryVersion$SummaryVersion$2 = (value) => value.message;
export const SummaryVersion$SummaryVersion$created_at = (value) =>
  value.created_at;
export const SummaryVersion$SummaryVersion$3 = (value) => value.created_at;

/**
 * A version history request must ask for at least one version.
 */
export class InvalidVersionCount extends $CustomType {
  constructor(count) {
    super();
    this.count = count;
  }
}
export const StorageError$InvalidVersionCount = (count) =>
  new InvalidVersionCount(count);
export const StorageError$isInvalidVersionCount = (value) =>
  value instanceof InvalidVersionCount;
export const StorageError$InvalidVersionCount$count = (value) => value.count;
export const StorageError$InvalidVersionCount$0 = (value) => value.count;

/**
 * The client could not build the request. The URL is not a valid one.
 */
export class BadRequestUrl extends $CustomType {
  constructor(url) {
    super();
    this.url = url;
  }
}
export const StorageError$BadRequestUrl = (url) => new BadRequestUrl(url);
export const StorageError$isBadRequestUrl = (value) =>
  value instanceof BadRequestUrl;
export const StorageError$BadRequestUrl$url = (value) => value.url;
export const StorageError$BadRequestUrl$0 = (value) => value.url;

/**
 * The network call did not complete.
 */
export class RequestFailed extends $CustomType {
  constructor(url, detail) {
    super();
    this.url = url;
    this.detail = detail;
  }
}
export const StorageError$RequestFailed = (url, detail) =>
  new RequestFailed(url, detail);
export const StorageError$isRequestFailed = (value) =>
  value instanceof RequestFailed;
export const StorageError$RequestFailed$url = (value) => value.url;
export const StorageError$RequestFailed$0 = (value) => value.url;
export const StorageError$RequestFailed$detail = (value) => value.detail;
export const StorageError$RequestFailed$1 = (value) => value.detail;

/**
 * The client could not read the body of the response.
 */
export class BodyReadFailed extends $CustomType {
  constructor(url, detail) {
    super();
    this.url = url;
    this.detail = detail;
  }
}
export const StorageError$BodyReadFailed = (url, detail) =>
  new BodyReadFailed(url, detail);
export const StorageError$isBodyReadFailed = (value) =>
  value instanceof BodyReadFailed;
export const StorageError$BodyReadFailed$url = (value) => value.url;
export const StorageError$BodyReadFailed$0 = (value) => value.url;
export const StorageError$BodyReadFailed$detail = (value) => value.detail;
export const StorageError$BodyReadFailed$1 = (value) => value.detail;

/**
 * The server answered with a status outside the 2xx range.
 */
export class UnexpectedStatus extends $CustomType {
  constructor(url, status, body) {
    super();
    this.url = url;
    this.status = status;
    this.body = body;
  }
}
export const StorageError$UnexpectedStatus = (url, status, body) =>
  new UnexpectedStatus(url, status, body);
export const StorageError$isUnexpectedStatus = (value) =>
  value instanceof UnexpectedStatus;
export const StorageError$UnexpectedStatus$url = (value) => value.url;
export const StorageError$UnexpectedStatus$0 = (value) => value.url;
export const StorageError$UnexpectedStatus$status = (value) => value.status;
export const StorageError$UnexpectedStatus$1 = (value) => value.status;
export const StorageError$UnexpectedStatus$body = (value) => value.body;
export const StorageError$UnexpectedStatus$2 = (value) => value.body;

/**
 * The body of the response is not the JSON that this client expects.
 */
export class ResponseDecodeFailed extends $CustomType {
  constructor(url, detail) {
    super();
    this.url = url;
    this.detail = detail;
  }
}
export const StorageError$ResponseDecodeFailed = (url, detail) =>
  new ResponseDecodeFailed(url, detail);
export const StorageError$isResponseDecodeFailed = (value) =>
  value instanceof ResponseDecodeFailed;
export const StorageError$ResponseDecodeFailed$url = (value) => value.url;
export const StorageError$ResponseDecodeFailed$0 = (value) => value.url;
export const StorageError$ResponseDecodeFailed$detail = (value) => value.detail;
export const StorageError$ResponseDecodeFailed$1 = (value) => value.detail;

/**
 * The summary tree holds no entry at the summary blob path.
 */
export class SummaryBlobMissing extends $CustomType {
  constructor(handle, path) {
    super();
    this.handle = handle;
    this.path = path;
  }
}
export const StorageError$SummaryBlobMissing = (handle, path) =>
  new SummaryBlobMissing(handle, path);
export const StorageError$isSummaryBlobMissing = (value) =>
  value instanceof SummaryBlobMissing;
export const StorageError$SummaryBlobMissing$handle = (value) => value.handle;
export const StorageError$SummaryBlobMissing$0 = (value) => value.handle;
export const StorageError$SummaryBlobMissing$path = (value) => value.path;
export const StorageError$SummaryBlobMissing$1 = (value) => value.path;

/**
 * The content of the summary blob is not base64, or the bytes in it are
 * not UTF-8 text.
 */
export class SummaryBlobUnreadable extends $CustomType {
  constructor(blob_sha, detail) {
    super();
    this.blob_sha = blob_sha;
    this.detail = detail;
  }
}
export const StorageError$SummaryBlobUnreadable = (blob_sha, detail) =>
  new SummaryBlobUnreadable(blob_sha, detail);
export const StorageError$isSummaryBlobUnreadable = (value) =>
  value instanceof SummaryBlobUnreadable;
export const StorageError$SummaryBlobUnreadable$blob_sha = (value) =>
  value.blob_sha;
export const StorageError$SummaryBlobUnreadable$0 = (value) => value.blob_sha;
export const StorageError$SummaryBlobUnreadable$detail = (value) =>
  value.detail;
export const StorageError$SummaryBlobUnreadable$1 = (value) => value.detail;

/**
 * The summary blob is text, but it is not a summary.
 */
export class SummaryBlobInvalid extends $CustomType {
  constructor(blob_sha, detail) {
    super();
    this.blob_sha = blob_sha;
    this.detail = detail;
  }
}
export const StorageError$SummaryBlobInvalid = (blob_sha, detail) =>
  new SummaryBlobInvalid(blob_sha, detail);
export const StorageError$isSummaryBlobInvalid = (value) =>
  value instanceof SummaryBlobInvalid;
export const StorageError$SummaryBlobInvalid$blob_sha = (value) =>
  value.blob_sha;
export const StorageError$SummaryBlobInvalid$0 = (value) => value.blob_sha;
export const StorageError$SummaryBlobInvalid$detail = (value) => value.detail;
export const StorageError$SummaryBlobInvalid$1 = (value) => value.detail;

class BlobContent extends $CustomType {
  constructor(content) {
    super();
    this.content = content;
  }
}

/**
 * The tree entry path that stores a watershed summary blob.
 * 
 * @ignore
 */
const summary_blob_path = "header";

/**
 * One line of text for a `StorageError` value, for a caller that reports a
 * String.
 */
export function error_to_string(error) {
  if (error instanceof InvalidVersionCount) {
    let count = error.count;
    return "version count must be positive: " + $int.to_string(count);
  } else if (error instanceof BadRequestUrl) {
    let url = error.url;
    return "storage url is not valid: " + url;
  } else if (error instanceof RequestFailed) {
    let url = error.url;
    let detail = error.detail;
    return (("storage request to " + url) + " failed: ") + detail;
  } else if (error instanceof BodyReadFailed) {
    let url = error.url;
    let detail = error.detail;
    return (("storage response from " + url) + " could not be read: ") + detail;
  } else if (error instanceof UnexpectedStatus) {
    let url = error.url;
    let status = error.status;
    let body = error.body;
    return (((("storage request to " + url) + " answered http ") + $int.to_string(
      status,
    )) + ": ") + body;
  } else if (error instanceof ResponseDecodeFailed) {
    let url = error.url;
    let detail = error.detail;
    return (("storage response from " + url) + " did not decode: ") + detail;
  } else if (error instanceof SummaryBlobMissing) {
    let handle = error.handle;
    let path = error.path;
    return ((("summary tree " + handle) + " has no '") + path) + "' entry";
  } else if (error instanceof SummaryBlobUnreadable) {
    let blob_sha = error.blob_sha;
    let detail = error.detail;
    return (("summary blob " + blob_sha) + " could not be read: ") + detail;
  } else {
    let blob_sha = error.blob_sha;
    let detail = error.detail;
    return (("summary blob " + blob_sha) + " did not decode: ") + detail;
  }
}

/**
 * Decode the content of a blob from base64, then decode the summary blob in
 * it.
 * 
 * @ignore
 */
function decode_blob(blob_sha, blob) {
  return $result.try$(
    (() => {
      let _pipe = $bit_array.base64_decode(blob.content);
      return $result.replace_error(
        _pipe,
        new SummaryBlobUnreadable(blob_sha, "the content is not base64"),
      );
    })(),
    (bits) => {
      return $result.try$(
        (() => {
          let _pipe = $bit_array.to_string(bits);
          return $result.replace_error(
            _pipe,
            new SummaryBlobUnreadable(blob_sha, "the bytes are not UTF-8 text"),
          );
        })(),
        (raw) => {
          let _pipe = $summary_blob.decode(raw);
          return $result.map_error(
            _pipe,
            (error) => {
              return new SummaryBlobInvalid(blob_sha, $string.inspect(error));
            },
          );
        },
      );
    },
  );
}

/**
 * The blob response `{sha, size, content: <base64>, encoding, url}`.
 * 
 * @ignore
 */
function blob_content_decoder() {
  return $decode.field(
    "content",
    $decode.string,
    (content) => { return $decode.success(new BlobContent(content)); },
  );
}

function blob_url(base_url, tenant, blob_sha) {
  return (((base_url + "/repos/") + tenant) + "/git/blobs/") + blob_sha;
}

function is_success(response) {
  return (response.status >= 200) && (response.status < 300);
}

/**
 * Decode a successful response body, or report an HTTP-error response.
 * 
 * @ignore
 */
function decode_response(request, response, decoder) {
  let url = request.host + request.path;
  let $ = is_success(response);
  if ($) {
    let _pipe = $json.parse(response.body, decoder);
    return $result.map_error(
      _pipe,
      (error) => {
        return new ResponseDecodeFailed(url, $string.inspect(error));
      },
    );
  } else {
    return new Error(new UnexpectedStatus(url, response.status, response.body));
  }
}

function send(request, decoder) {
  return $promise.try_await(
    (() => {
      let _pipe = $fetch.send(request);
      return $promise.map(
        _pipe,
        (_capture) => {
          return $result.map_error(
            _capture,
            (error) => {
              return new RequestFailed(
                request.host + request.path,
                $string.inspect(error),
              );
            },
          );
        },
      );
    })(),
    (sent) => {
      return $promise.try_await(
        (() => {
          let _pipe = $fetch.read_text_body(sent);
          return $promise.map(
            _pipe,
            (_capture) => {
              return $result.map_error(
                _capture,
                (error) => {
                  return new BodyReadFailed(
                    request.host + request.path,
                    $string.inspect(error),
                  );
                },
              );
            },
          );
        })(),
        (response) => {
          return $promise.resolve(decode_response(request, response, decoder));
        },
      );
    },
  );
}

function authorize(request, token) {
  return $request.set_header(request, "authorization", "Bearer " + token);
}

function build_get(url, token) {
  return $result.try$(
    (() => {
      let _pipe = $request.to(url);
      return $result.replace_error(_pipe, new BadRequestUrl(url));
    })(),
    (request) => {
      return new Ok(
        (() => {
          let _pipe = request;
          let _pipe$1 = $request.set_method(_pipe, $http.Method$Get$const);
          return authorize(_pipe$1, token);
        })(),
      );
    },
  );
}

function get_json(url, token, decoder) {
  let $ = build_get(url, token);
  if ($ instanceof Ok) {
    let request = $[0];
    return send(request, decoder);
  } else {
    let reason = $[0];
    return $promise.resolve(new Error(reason));
  }
}

/**
 * Find the SHA of the summary blob in a decoded tree.
 * 
 * @ignore
 */
function find_blob_sha(tree, handle) {
  let $ = $list.find(
    tree,
    (entry) => { return entry[0] === summary_blob_path; },
  );
  if ($ instanceof Ok) {
    let sha = $[0][1];
    return new Ok(sha);
  } else {
    return new Error(new SummaryBlobMissing(handle, summary_blob_path));
  }
}

/**
 * Lift a synchronous `Result` value into the `try_await` chain of a promise.
 * 
 * @ignore
 */
function promise_try(result, next) {
  if (result instanceof Ok) {
    let value = result[0];
    return next(value);
  } else {
    let error = result[0];
    return $promise.resolve(new Error(error));
  }
}

function tree_entry_decoder() {
  return $decode.field(
    "path",
    $decode.string,
    (path) => {
      return $decode.field(
        "sha",
        $decode.string,
        (sha) => { return $decode.success([path, sha]); },
      );
    },
  );
}

/**
 * The tree response `{sha, url, tree: [{path, sha, type, ...}]}`, decoded to
 * `[#(path, sha)]`.
 * 
 * @ignore
 */
function tree_decoder() {
  return $decode.at(toList(["tree"]), $decode.list(tree_entry_decoder()));
}

function tree_url(base_url, tenant, handle) {
  return (((base_url + "/repos/") + tenant) + "/git/trees/") + handle;
}

function fetch_tree_summary(base_url, tenant, token, tree_id) {
  return $promise.try_await(
    get_json(tree_url(base_url, tenant, tree_id), token, tree_decoder()),
    (tree) => {
      return promise_try(
        find_blob_sha(tree, tree_id),
        (blob_sha) => {
          return $promise.try_await(
            get_json(
              blob_url(base_url, tenant, blob_sha),
              token,
              blob_content_decoder(),
            ),
            (blob) => { return $promise.resolve(decode_blob(blob_sha, blob)); },
          );
        },
      );
    },
  );
}

/**
 * Use a published commit's tree, or a legacy tree ID after a commit 404.
 */
export function resolve_summary_tree_id(version_id, commit_result) {
  if (commit_result instanceof Ok) {
    return commit_result;
  } else {
    let $ = commit_result[0];
    if ($ instanceof UnexpectedStatus) {
      let $1 = $.status;
      if ($1 === 404) {
        return new Ok(version_id);
      } else {
        return commit_result;
      }
    } else {
      return commit_result;
    }
  }
}

/**
 * Decode a commit response to its root tree SHA.
 */
export function commit_tree_decoder() {
  return $decode.subfield(
    toList(["tree", "sha"]),
    $decode.string,
    $decode.success,
  );
}

export function commit_url(base_url, tenant, commit_id) {
  return (((base_url + "/repos/") + tenant) + "/git/commits/") + commit_id;
}

/**
 * Fetch and decode the summary that a published commit identifies.
 * A missing commit falls back to the supplied ID as a legacy tree SHA.
 */
export function fetch_summary(base_url, tenant, token, handle) {
  return $promise.await$(
    get_json(commit_url(base_url, tenant, handle), token, commit_tree_decoder()),
    (commit_result) => {
      return promise_try(
        resolve_summary_tree_id(handle, commit_result),
        (tree_id) => {
          return fetch_tree_summary(base_url, tenant, token, tree_id);
        },
      );
    },
  );
}

/**
 * The create response for a blob or a tree, `{sha, url, ...}`, decoded to the
 * SHA.
 * 
 * @ignore
 */
function sha_decoder() {
  return $decode.field("sha", $decode.string, $decode.success);
}

function tree_body(blob_sha) {
  let _pipe = $json.object(
    toList([
      [
        "tree",
        $json.array(
          toList([blob_sha]),
          (sha) => {
            return $json.object(
              toList([
                ["path", $json.string(summary_blob_path)],
                ["sha", $json.string(sha)],
                ["type", $json.string("blob")],
              ]),
            );
          },
        ),
      ],
    ]),
  );
  return $json.to_string(_pipe);
}

function trees_url(base_url, tenant) {
  return ((base_url + "/repos/") + tenant) + "/git/trees";
}

function build_post(url, token, body) {
  return $result.try$(
    (() => {
      let _pipe = $request.to(url);
      return $result.replace_error(_pipe, new BadRequestUrl(url));
    })(),
    (request) => {
      return new Ok(
        (() => {
          let _pipe = request;
          let _pipe$1 = $request.set_method(_pipe, $http.Method$Post$const);
          let _pipe$2 = $request.set_header(
            _pipe$1,
            "content-type",
            "application/json",
          );
          let _pipe$3 = $request.set_body(_pipe$2, body);
          return authorize(_pipe$3, token);
        })(),
      );
    },
  );
}

function post_json(url, token, body, decoder) {
  let $ = build_post(url, token, body);
  if ($ instanceof Ok) {
    let request = $[0];
    return send(request, decoder);
  } else {
    let reason = $[0];
    return $promise.resolve(new Error(reason));
  }
}

function blob_body(sequence_number, members, channels) {
  let _block;
  let _pipe = $summary_blob.encode_channels(sequence_number, members, channels);
  _block = $json.to_string(_pipe);
  let blob_json = _block;
  let content = $bit_array.base64_encode(
    toBitArray([stringBits(blob_json)]),
    true,
  );
  let _pipe$1 = $json.object(
    toList([
      ["content", $json.string(content)],
      ["encoding", $json.string("base64")],
    ]),
  );
  return $json.to_string(_pipe$1);
}

function blobs_url(base_url, tenant) {
  return ((base_url + "/repos/") + tenant) + "/git/blobs";
}

/**
 * Serialize the supplied channel state as a summary blob. Upload that blob as
 * a git blob in a tree with one entry. Return the staged tree SHA for the
 * `handle` field of the summarize operation.
 *
 * `members` is the connected roster at `sequence_number`. It travels with the
 * snapshots, and not beside them, because it is checkpoint state of the same
 * kind. The consensus kernels read it when they replay an operation that
 * sequenced after this point.
 */
export function upload_summary(
  base_url,
  tenant,
  token,
  sequence_number,
  members,
  channels
) {
  return $promise.try_await(
    post_json(
      blobs_url(base_url, tenant),
      token,
      blob_body(sequence_number, members, channels),
      sha_decoder(),
    ),
    (blob_sha) => {
      return post_json(
        trees_url(base_url, tenant),
        token,
        tree_body(blob_sha),
        sha_decoder(),
      );
    },
  );
}

/**
 * The deltas response `{value: [SequencedDocumentMessage]}`. A document
 * channel push uses the same message format, so this decoder uses the channel
 * decoder.
 * 
 * @ignore
 */
function deltas_decoder() {
  return $decode.at(
    toList(["value"]),
    $decode.list($socket.sequenced_document_message_decoder()),
  );
}

/**
 * `from` is an exclusive lower bound on the sequence number, and `to` is an
 * inclusive upper bound. The query behaviour of the server is the same.
 * 
 * @ignore
 */
function deltas_url(base_url, tenant, document, from, to) {
  return (((((((base_url + "/deltas/") + tenant) + "/") + document) + "?from=") + $int.to_string(
    from,
  )) + "&to=") + $int.to_string(to);
}

/**
 * Fetch the sequenced operations in `(from, to]` from the deltas REST
 * endpoint. The server limits each response, at present to 2000 operations. A
 * large range can thus give an incomplete result. The caller must then request
 * again from the last sequence number that it received.
 */
export function fetch_deltas(base_url, tenant, token, document, from, to) {
  return get_json(
    deltas_url(base_url, tenant, document, from, to),
    token,
    deltas_decoder(),
  );
}

function version_decoder() {
  return $decode.field(
    "sha",
    $decode.string,
    (id) => {
      return $decode.subfield(
        toList(["commit", "message"]),
        $decode.string,
        (message) => {
          return $decode.subfield(
            toList(["commit", "committer", "date"]),
            $decode.string,
            (created_at) => {
              return $decode.subfield(
                toList(["commit", "tree", "sha"]),
                $decode.string,
                (tree_id) => {
                  return $decode.success(
                    new SummaryVersion(id, tree_id, message, created_at),
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
 * Decode the newest-first commit history response.
 */
export function versions_decoder() {
  return $decode.list(version_decoder());
}

export function versions_url(base_url, tenant, document, count) {
  return (((((base_url + "/repos/") + tenant) + "/commits?sha=") + document) + "&count=") + $int.to_string(
    count,
  );
}

export function validate_version_count(count) {
  let $ = count > 0;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new InvalidVersionCount(count));
  }
}

/**
 * List the published summary commits of the document, newest first. Give the
 * `id` of a version to `fetch_summary` to read its snapshot.
 */
export function fetch_versions(base_url, tenant, token, document, count) {
  return promise_try(
    validate_version_count(count),
    (_use0) => {
      
      return get_json(
        versions_url(base_url, tenant, document, count),
        token,
        versions_decoder(),
      );
    },
  );
}

//// The HTTP client for the storage REST endpoints of floodgate. There are two
//// of them. The git-storage (Historian) API reads and writes the SharedMap
//// summaries. The deltas API (`GET /deltas/:tenant_id/:id`) fetches the
//// sequenced operations that are older than the in-band history window of the
//// server.
////
//// A watershed summary is one JSON blob. See `summary_blob.encode_channels`.
//// A git tree holds that blob at the path `"header"`. The client sets the
//// `handle` field of the summarize operation to the tree SHA. To load a
//// summary, the client thus fetches the tree by its handle, reads the `header`
//// blob, decodes that blob from base64, and then decodes the summary.
////
//// A write with `upload_summary` needs the `summary:write` scope on the token.
//// A read with `fetch_summary` needs the `doc:read` scope.
////
//// This module is a **cross-target seam**. The request construction, the
//// response decoders, and the blob serialization are shared. The network
//// `send` function differs for each target. The Erlang path uses
//// `gleam_httpc` and is synchronous, because it runs in the OTP actor. The
//// JavaScript path uses `gleam_fetch` and returns a `Promise`, because the
//// `fetch` function of a browser is always asynchronous.

import gleam/bit_array
import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string

import spillway/types.{type SequencedDocumentMessage}

import watershed/channel
import watershed/wire/socket
import watershed/wire/summary_blob.{type SummaryBlob}

@target(erlang)
import gleam/httpc

@target(javascript)
import gleam/fetch
@target(javascript)
import gleam/javascript/promise.{type Promise}

/// The tree entry path that stores a watershed summary blob.
const summary_blob_path = "header"

/// One stored summary version, as `GET /versions/:tenant_id/:id` lists it,
/// newest first. `handle` identifies the snapshot tree. Give that handle to
/// `fetch_summary` to read the state that the snapshot captured.
/// `sequence_number` is the sequence number that the server gave to the
/// summarize operation.
pub type SummaryVersion {
  SummaryVersion(
    handle: String,
    sequence_number: Int,
    message: Option(String),
    created_at: Option(String),
  )
}

/// The reasons that a storage call fails. Each variant names the step of the
/// storage protocol that failed, and it carries the data that a reader needs
/// to find the fault.
pub type StorageError {
  /// The client could not build the request. The URL is not a valid one.
  BadRequestUrl(url: String)
  /// The network call did not complete.
  RequestFailed(url: String, detail: String)
  /// The client could not read the body of the response.
  BodyReadFailed(url: String, detail: String)
  /// The server answered with a status outside the 2xx range.
  UnexpectedStatus(url: String, status: Int, body: String)
  /// The body of the response is not the JSON that this client expects.
  ResponseDecodeFailed(url: String, detail: String)
  /// The summary tree holds no entry at the summary blob path.
  SummaryBlobMissing(handle: String, path: String)
  /// The content of the summary blob is not base64, or the bytes in it are
  /// not UTF-8 text.
  SummaryBlobUnreadable(blob_sha: String, detail: String)
  /// The summary blob is text, but it is not a summary.
  SummaryBlobInvalid(blob_sha: String, detail: String)
}

/// One line of text for a `StorageError` value, for a caller that reports a
/// String.
pub fn error_to_string(error: StorageError) -> String {
  case error {
    BadRequestUrl(url) -> "storage url is not valid: " <> url
    RequestFailed(url, detail) ->
      "storage request to " <> url <> " failed: " <> detail
    BodyReadFailed(url, detail) ->
      "storage response from " <> url <> " could not be read: " <> detail
    UnexpectedStatus(url, status, body) ->
      "storage request to "
      <> url
      <> " answered http "
      <> int.to_string(status)
      <> ": "
      <> body
    ResponseDecodeFailed(url, detail) ->
      "storage response from " <> url <> " did not decode: " <> detail
    SummaryBlobMissing(handle, path) ->
      "summary tree " <> handle <> " has no '" <> path <> "' entry"
    SummaryBlobUnreadable(blob_sha, detail) ->
      "summary blob " <> blob_sha <> " could not be read: " <> detail
    SummaryBlobInvalid(blob_sha, detail) ->
      "summary blob " <> blob_sha <> " did not decode: " <> detail
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API — erlang (synchronous, runs inside the OTP actor)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Fetch and decode the summary that `handle` identifies. A handle is a git
/// tree SHA.
pub fn fetch_summary(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  handle handle: String,
) -> Result(SummaryBlob, StorageError) {
  use tree <- result.try(get_json(
    tree_url(base_url, tenant, handle),
    token,
    tree_decoder(),
  ))
  use blob_sha <- result.try(find_blob_sha(tree, handle))
  use blob <- result.try(get_json(
    blob_url(base_url, tenant, blob_sha),
    token,
    blob_content_decoder(),
  ))
  decode_blob(blob_sha, blob)
}

@target(erlang)
/// Serialize the supplied channel state as a summary blob. Upload that blob as
/// a git blob in a tree with one entry. Return the tree SHA, which is both the
/// `head` field and the `handle` field of the summarize operation.
///
/// `members` is the connected roster at `sequence_number`. It travels with the
/// snapshots, and not beside them, because it is checkpoint state of the same
/// kind. The consensus kernels read it when they replay an operation that
/// sequenced after this point.
pub fn upload_summary(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  sequence_number sequence_number: Int,
  members members: List(Int),
  channels channels: List(#(String, channel.Snapshot)),
) -> Result(String, StorageError) {
  use blob_sha <- result.try(post_json(
    blobs_url(base_url, tenant),
    token,
    blob_body(sequence_number, members, channels),
    sha_decoder(),
  ))
  post_json(
    trees_url(base_url, tenant),
    token,
    tree_body(blob_sha),
    sha_decoder(),
  )
}

@target(erlang)
/// Fetch the sequenced operations in `(from, to]` from the deltas REST
/// endpoint. The server limits each response, at present to 2000 operations. A
/// large range can thus give an incomplete result. The caller must then request
/// again from the last sequence number that it received.
pub fn fetch_deltas(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  document document: String,
  from from: Int,
  to to: Int,
) -> Result(List(SequencedDocumentMessage), StorageError) {
  get_json(
    deltas_url(base_url, tenant, document, from, to),
    token,
    deltas_decoder(),
  )
}

@target(erlang)
/// List the stored summary versions of the document, newest first. This is the
/// client half of the `getVersions` function of Fluid. Give the `handle` of a
/// version to `fetch_summary` to read the snapshot that it captured.
pub fn fetch_versions(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  document document: String,
  count count: Int,
) -> Result(List(SummaryVersion), StorageError) {
  get_json(
    versions_url(base_url, tenant, document, count),
    token,
    versions_decoder(),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API — JavaScript (asynchronous, returns a Promise)
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Fetch and decode the summary that `handle` identifies. A handle is a git
/// tree SHA.
pub fn fetch_summary(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  handle handle: String,
) -> Promise(Result(SummaryBlob, StorageError)) {
  use tree <- promise.try_await(get_json(
    tree_url(base_url, tenant, handle),
    token,
    tree_decoder(),
  ))
  use blob_sha <- promise_try(find_blob_sha(tree, handle))
  use blob <- promise.try_await(get_json(
    blob_url(base_url, tenant, blob_sha),
    token,
    blob_content_decoder(),
  ))
  promise.resolve(decode_blob(blob_sha, blob))
}

@target(javascript)
/// Serialize the supplied channel state as a summary blob. Upload that blob as
/// a git blob in a tree with one entry. Return the tree SHA, which is both the
/// `head` field and the `handle` field of the summarize operation.
///
/// `members` is the connected roster at `sequence_number`. It travels with the
/// snapshots, and not beside them, because it is checkpoint state of the same
/// kind. The consensus kernels read it when they replay an operation that
/// sequenced after this point.
pub fn upload_summary(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  sequence_number sequence_number: Int,
  members members: List(Int),
  channels channels: List(#(String, channel.Snapshot)),
) -> Promise(Result(String, StorageError)) {
  use blob_sha <- promise.try_await(post_json(
    blobs_url(base_url, tenant),
    token,
    blob_body(sequence_number, members, channels),
    sha_decoder(),
  ))
  post_json(
    trees_url(base_url, tenant),
    token,
    tree_body(blob_sha),
    sha_decoder(),
  )
}

@target(javascript)
/// Fetch the sequenced operations in `(from, to]` from the deltas REST
/// endpoint. The server limits each response, at present to 2000 operations. A
/// large range can thus give an incomplete result. The caller must then request
/// again from the last sequence number that it received.
pub fn fetch_deltas(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  document document: String,
  from from: Int,
  to to: Int,
) -> Promise(Result(List(SequencedDocumentMessage), StorageError)) {
  get_json(
    deltas_url(base_url, tenant, document, from, to),
    token,
    deltas_decoder(),
  )
}

@target(javascript)
/// List the stored summary versions of the document, newest first. This is the
/// client half of the `getVersions` function of Fluid. Give the `handle` of a
/// version to `fetch_summary` to read the snapshot that it captured.
pub fn fetch_versions(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  document document: String,
  count count: Int,
) -> Promise(Result(List(SummaryVersion), StorageError)) {
  get_json(
    versions_url(base_url, tenant, document, count),
    token,
    versions_decoder(),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared URL construction
// ─────────────────────────────────────────────────────────────────────────────

fn tree_url(base_url: String, tenant: String, handle: String) -> String {
  base_url <> "/repos/" <> tenant <> "/git/trees/" <> handle
}

fn blob_url(base_url: String, tenant: String, blob_sha: String) -> String {
  base_url <> "/repos/" <> tenant <> "/git/blobs/" <> blob_sha
}

fn blobs_url(base_url: String, tenant: String) -> String {
  base_url <> "/repos/" <> tenant <> "/git/blobs"
}

fn trees_url(base_url: String, tenant: String) -> String {
  base_url <> "/repos/" <> tenant <> "/git/trees"
}

/// `from` is an exclusive lower bound on the sequence number, and `to` is an
/// inclusive upper bound. The query behaviour of the server is the same.
fn deltas_url(
  base_url: String,
  tenant: String,
  document: String,
  from: Int,
  to: Int,
) -> String {
  base_url
  <> "/deltas/"
  <> tenant
  <> "/"
  <> document
  <> "?from="
  <> int.to_string(from)
  <> "&to="
  <> int.to_string(to)
}

fn versions_url(
  base_url: String,
  tenant: String,
  document: String,
  count: Int,
) -> String {
  base_url
  <> "/versions/"
  <> tenant
  <> "/"
  <> document
  <> "?count="
  <> int.to_string(count)
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared request-body construction
// ─────────────────────────────────────────────────────────────────────────────

fn blob_body(
  sequence_number: Int,
  members: List(Int),
  channels: List(#(String, channel.Snapshot)),
) -> String {
  let blob_json =
    summary_blob.encode_channels(sequence_number, members, channels)
    |> json.to_string
  let content = bit_array.base64_encode(<<blob_json:utf8>>, True)
  json.object([
    #("content", json.string(content)),
    #("encoding", json.string("base64")),
  ])
  |> json.to_string
}

fn tree_body(blob_sha: String) -> String {
  json.object([
    #(
      "tree",
      json.array([blob_sha], fn(sha) {
        json.object([
          #("path", json.string(summary_blob_path)),
          #("sha", json.string(sha)),
          #("type", json.string("blob")),
        ])
      }),
    ),
  ])
  |> json.to_string
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared response handling
// ─────────────────────────────────────────────────────────────────────────────

/// Find the SHA of the summary blob in a decoded tree.
fn find_blob_sha(
  tree: List(#(String, String)),
  handle: String,
) -> Result(String, StorageError) {
  case list.find(tree, fn(entry) { entry.0 == summary_blob_path }) {
    Ok(#(_, sha)) -> Ok(sha)
    Error(Nil) -> Error(SummaryBlobMissing(handle, summary_blob_path))
  }
}

/// Decode the content of a blob from base64, then decode the summary blob in
/// it.
fn decode_blob(
  blob_sha: String,
  blob: BlobContent,
) -> Result(SummaryBlob, StorageError) {
  use bits <- result.try(
    bit_array.base64_decode(blob.content)
    |> result.replace_error(SummaryBlobUnreadable(
      blob_sha,
      "the content is not base64",
    )),
  )
  use raw <- result.try(
    bit_array.to_string(bits)
    |> result.replace_error(SummaryBlobUnreadable(
      blob_sha,
      "the bytes are not UTF-8 text",
    )),
  )
  summary_blob.decode(raw)
  |> result.map_error(fn(error) {
    SummaryBlobInvalid(blob_sha, string.inspect(error))
  })
}

fn is_success(response: Response(String)) -> Bool {
  response.status >= 200 && response.status < 300
}

/// Decode a successful response body, or report an HTTP-error response.
fn decode_response(
  request: Request(String),
  response: Response(String),
  decoder: Decoder(a),
) -> Result(a, StorageError) {
  let url = request.host <> request.path
  case is_success(response) {
    False -> Error(UnexpectedStatus(url, response.status, response.body))
    True ->
      json.parse(response.body, decoder)
      |> result.map_error(fn(error) {
        ResponseDecodeFailed(url, string.inspect(error))
      })
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared request construction
// ─────────────────────────────────────────────────────────────────────────────

fn build_get(
  url: String,
  token: String,
) -> Result(Request(String), StorageError) {
  use request <- result.try(
    request.to(url)
    |> result.replace_error(BadRequestUrl(url)),
  )
  Ok(
    request
    |> request.set_method(http.Get)
    |> authorize(token),
  )
}

fn build_post(
  url: String,
  token: String,
  body: String,
) -> Result(Request(String), StorageError) {
  use request <- result.try(
    request.to(url)
    |> result.replace_error(BadRequestUrl(url)),
  )
  Ok(
    request
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)
    |> authorize(token),
  )
}

fn authorize(request: Request(String), token: String) -> Request(String) {
  request.set_header(request, "authorization", "Bearer " <> token)
}

// ─────────────────────────────────────────────────────────────────────────────
// Target-specific transport: erlang (httpc, synchronous)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn get_json(
  url: String,
  token: String,
  decoder: Decoder(a),
) -> Result(a, StorageError) {
  use request <- result.try(build_get(url, token))
  send(request, decoder)
}

@target(erlang)
fn post_json(
  url: String,
  token: String,
  body: String,
  decoder: Decoder(a),
) -> Result(a, StorageError) {
  use request <- result.try(build_post(url, token, body))
  send(request, decoder)
}

@target(erlang)
fn send(
  request: Request(String),
  decoder: Decoder(a),
) -> Result(a, StorageError) {
  // Force a fresh connection per request. Erlang's default httpc profile keeps
  // connections alive and pools them; a second sequential request that tries to
  // reuse a pooled (possibly server-closed) session can stall until timeout.
  // `Connection: close` makes the server close after each response so httpc
  // never reuses a stale session.
  let request = request.set_header(request, "connection", "close")
  use response <- result.try(
    httpc.send(request)
    |> result.map_error(fn(error) {
      RequestFailed(request.host <> request.path, string.inspect(error))
    }),
  )
  decode_response(request, response, decoder)
}

// ─────────────────────────────────────────────────────────────────────────────
// Target-specific transport: JavaScript (fetch, asynchronous)
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn get_json(
  url: String,
  token: String,
  decoder: Decoder(a),
) -> Promise(Result(a, StorageError)) {
  case build_get(url, token) {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(request) -> send(request, decoder)
  }
}

@target(javascript)
fn post_json(
  url: String,
  token: String,
  body: String,
  decoder: Decoder(a),
) -> Promise(Result(a, StorageError)) {
  case build_post(url, token, body) {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(request) -> send(request, decoder)
  }
}

@target(javascript)
fn send(
  request: Request(String),
  decoder: Decoder(a),
) -> Promise(Result(a, StorageError)) {
  use sent <- promise.try_await(
    fetch.send(request)
    |> promise.map(
      result.map_error(_, fn(error) {
        RequestFailed(request.host <> request.path, string.inspect(error))
      }),
    ),
  )
  use response <- promise.try_await(
    fetch.read_text_body(sent)
    |> promise.map(
      result.map_error(_, fn(error) {
        BodyReadFailed(request.host <> request.path, string.inspect(error))
      }),
    ),
  )
  promise.resolve(decode_response(request, response, decoder))
}

@target(javascript)
/// Lift a synchronous `Result` value into the `try_await` chain of a promise.
fn promise_try(
  result: Result(a, e),
  next: fn(a) -> Promise(Result(b, e)),
) -> Promise(Result(b, e)) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> promise.resolve(Error(error))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Response decoders (shared)
// ─────────────────────────────────────────────────────────────────────────────

/// The tree response `{sha, url, tree: [{path, sha, type, ...}]}`, decoded to
/// `[#(path, sha)]`.
fn tree_decoder() -> Decoder(List(#(String, String))) {
  decode.at(["tree"], decode.list(tree_entry_decoder()))
}

fn tree_entry_decoder() -> Decoder(#(String, String)) {
  use path <- decode.field("path", decode.string)
  use sha <- decode.field("sha", decode.string)
  decode.success(#(path, sha))
}

type BlobContent {
  BlobContent(content: String)
}

/// The blob response `{sha, size, content: <base64>, encoding, url}`.
fn blob_content_decoder() -> Decoder(BlobContent) {
  use content <- decode.field("content", decode.string)
  decode.success(BlobContent(content: content))
}

/// The create response for a blob or a tree, `{sha, url, ...}`, decoded to the
/// SHA.
fn sha_decoder() -> Decoder(String) {
  decode.field("sha", decode.string, decode.success)
}

/// The deltas response `{value: [SequencedDocumentMessage]}`. A document
/// channel push uses the same message format, so this decoder uses the channel
/// decoder.
fn deltas_decoder() -> Decoder(List(SequencedDocumentMessage)) {
  decode.at(["value"], decode.list(socket.sequenced_document_message_decoder()))
}

/// The versions response `{value: [{handle, sequenceNumber, message, ...}]}`,
/// newest first.
fn versions_decoder() -> Decoder(List(SummaryVersion)) {
  decode.at(["value"], decode.list(version_decoder()))
}

fn version_decoder() -> Decoder(SummaryVersion) {
  use handle <- decode.field("handle", decode.string)
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  use message <- decode.optional_field(
    "message",
    None,
    decode.optional(decode.string),
  )
  use created_at <- decode.optional_field(
    "createdAt",
    None,
    decode.optional(decode.string),
  )
  decode.success(SummaryVersion(
    handle: handle,
    sequence_number: sequence_number,
    message: message,
    created_at: created_at,
  ))
}

//// The HTTP client for the storage REST endpoints of floodgate.
//// The git-storage (Historian) API reads and writes full Fluid
//// summary hierarchies. The deltas API (`GET /deltas/:tenant_id/:id`) fetches the
//// sequenced operations that are older than the in-band history window of the
//// server.
//// The document-create API publishes a complete initial container and returns
//// its assigned ID. It requires tenant write access and does not retry.
////
//// Staging writes blobs and trees only. The summarize operation publishes
//// a commit over the staged root tree. A read needs the `doc:read` scope;
//// a write needs the `summary:write` scope.
////
//// This module is a **cross-target seam**. The request construction, the
//// response decoders, and the blob serialization are shared. The network
//// `send` function differs for each target. The Erlang path uses
//// `gleam_httpc` for ordinary storage and Gluegun for one-shot creation.
//// Both are synchronous. The
//// JavaScript path uses `gleam_fetch` and returns a `Promise`, because the
//// `fetch` function of a browser is always asynchronous.

import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
@target(erlang)
import gleam/option
import gleam/result
import gleam/string
import gleam/uri

import spillway/types.{type SequencedDocumentMessage}

import watershed/wire/fluid_document
import watershed/wire/fluid_summary
import watershed/wire/socket

@target(erlang)
import gleam/httpc
@target(erlang)
import gluegun/client as http_client
@target(erlang)
import gluegun/connection
@target(erlang)
import gluegun/error as http_error
@target(erlang)
import gluegun/message as http_message
@target(erlang)
import gluegun/request as http_request
@target(erlang)
import gluegun/response as http_response

@target(javascript)
import gleam/fetch
@target(javascript)
import gleam/javascript/promise.{type Promise}

/// One published summary version from the document's commit history.
/// `id` is the published commit SHA. `tree_id` is its root tree SHA.
pub type SummaryVersion {
  SummaryVersion(
    id: String,
    tree_id: String,
    message: String,
    created_at: String,
  )
}

pub type HierarchyEntryKind {
  HierarchyBlob
  HierarchyTree
}

pub type HierarchyTreeEntry {
  HierarchyTreeEntry(name: String, sha: String, kind: HierarchyEntryKind)
}

/// The reasons that a storage call fails. Each variant names the step of the
/// storage protocol that failed, and it carries the data that a reader needs
/// to find the fault.
pub type StorageError {
  /// A version history request must ask for at least one version.
  InvalidVersionCount(count: Int)
  /// The client could not build the request. The URL is not a valid one.
  BadRequestUrl(url: String)
  /// The network call did not complete.
  RequestFailed(url: String, detail: String)
  /// The client could not read the body of the response.
  BodyReadFailed(url: String, detail: String)
  /// The server answered with a status that the operation does not accept.
  UnexpectedStatus(url: String, status: Int, body: String)
  /// The body of the response is not the JSON that this client expects.
  ResponseDecodeFailed(url: String, detail: String)
  /// A summary hierarchy has an invalid structure.
  SummaryStructure(error: fluid_summary.SummaryError)
  /// A hierarchy blob could not be decoded without losing bytes.
  HierarchyBlobUnreadable(path: String, blob_sha: String, detail: String)
  /// A referenced hierarchy object does not exist.
  HierarchyObjectMissing(
    path: String,
    object_sha: String,
    kind: HierarchyEntryKind,
  )
}

/// One line of text for a `StorageError` value, for a caller that reports a
/// String.
pub fn error_to_string(error: StorageError) -> String {
  case error {
    InvalidVersionCount(count) ->
      "version count must be positive: " <> int.to_string(count)
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
    SummaryStructure(error) ->
      "summary hierarchy is invalid: " <> summary_error_to_string(error)
    HierarchyBlobUnreadable(path, blob_sha, detail) ->
      "summary blob "
      <> blob_sha
      <> " at "
      <> path
      <> " could not be read: "
      <> detail
    HierarchyObjectMissing(path, object_sha, kind) ->
      "summary "
      <> hierarchy_kind_to_string(kind)
      <> " "
      <> object_sha
      <> " is missing at "
      <> path
  }
}

fn summary_error_to_string(error: fluid_summary.SummaryError) -> String {
  case error {
    fluid_summary.MissingEntry(path) -> "missing entry at " <> path
    fluid_summary.CyclicReference(path) -> "cyclic reference at " <> path
    fluid_summary.WrongKind(path, expected) ->
      "wrong entry kind at "
      <> path
      <> "; expected "
      <> handle_kind_to_string(expected)
    fluid_summary.MalformedEntry(path, detail) ->
      "malformed entry at " <> path <> ": " <> detail
    fluid_summary.UnsupportedEntry(path, detail) ->
      "unsupported entry at " <> path <> ": " <> detail
  }
}

fn handle_kind_to_string(kind: fluid_summary.HandleKind) -> String {
  case kind {
    fluid_summary.TreeHandle -> "tree"
    fluid_summary.BlobHandle -> "blob"
  }
}

fn hierarchy_kind_to_string(kind: HierarchyEntryKind) -> String {
  case kind {
    HierarchyBlob -> "blob"
    HierarchyTree -> "tree"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API — erlang (synchronous, runs inside the OTP actor)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Fetch a complete summary hierarchy from a published commit.
///
/// `commit_id` must identify a commit. This function does not treat a missing
/// commit as a tree ID.
pub fn fetch_hierarchy(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  commit_id commit_id: String,
) -> Result(fluid_summary.SummaryEntry, StorageError) {
  use tree_id <- result.try(get_json(
    commit_url(base_url, tenant, commit_id),
    token,
    commit_tree_decoder(),
  ))
  fetch_hierarchy_tree(base_url, tenant, token, tree_id, "/", [tree_id])
}

@target(erlang)
/// Stage a complete summary hierarchy and return its root tree ID.
///
/// This function does not publish a commit. It validates the complete input
/// before it writes any object.
pub fn stage_hierarchy(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  tree tree: fluid_summary.SummaryEntry,
) -> Result(String, StorageError) {
  use Nil <- result.try(validate_hierarchy(tree))
  let assert fluid_summary.SummaryTree(entries) = tree
  stage_hierarchy_tree(base_url, tenant, token, entries)
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
/// List the published summary commits of the document, newest first. Give the
/// `id` of a version to `fetch_hierarchy` to read its full snapshot.
pub fn fetch_versions(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  document document: String,
  count count: Int,
) -> Result(List(SummaryVersion), StorageError) {
  use Nil <- result.try(validate_version_count(count))
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
/// Fetch a complete summary hierarchy from a published commit.
///
/// `commit_id` must identify a commit. This function does not treat a missing
/// commit as a tree ID.
pub fn fetch_hierarchy(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  commit_id commit_id: String,
) -> Promise(Result(fluid_summary.SummaryEntry, StorageError)) {
  use commit_result <- promise.await(get_json(
    commit_url(base_url, tenant, commit_id),
    token,
    commit_tree_decoder(),
  ))
  use tree_id <- promise_try(commit_result)
  fetch_hierarchy_tree(base_url, tenant, token, tree_id, "/", [tree_id])
}

@target(javascript)
/// Stage a complete summary hierarchy and return its root tree ID.
///
/// This function does not publish a commit. It validates the complete input
/// before it writes any object.
pub fn stage_hierarchy(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  tree tree: fluid_summary.SummaryEntry,
) -> Promise(Result(String, StorageError)) {
  case validate_hierarchy(tree) {
    Error(error) -> promise.resolve(Error(error))
    Ok(Nil) -> {
      let assert fluid_summary.SummaryTree(entries) = tree
      stage_hierarchy_tree(base_url, tenant, token, entries)
    }
  }
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
/// List the published summary commits of the document, newest first. Give the
/// `id` of a version to `fetch_hierarchy` to read its full snapshot.
pub fn fetch_versions(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  document document: String,
  count count: Int,
) -> Promise(Result(List(SummaryVersion), StorageError)) {
  use Nil <- promise_try(validate_version_count(count))
  get_json(
    versions_url(base_url, tenant, document, count),
    token,
    versions_decoder(),
  )
}

@target(erlang)
/// Publish an initial container once. A lost response does not cause a retry.
pub fn create_document(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  summary summary: fluid_document.DocumentSummary,
) -> Result(String, StorageError) {
  use body <- result.try(
    fluid_document.encode_create_request(summary)
    |> result.map_error(SummaryStructure),
  )
  use request <- result.try(build_post(
    document_create_url(base_url, tenant),
    token,
    json.to_string(body),
  ))
  use response <- result.try(send_initial_request(request))
  decode_created_response(request, response)
}

@target(javascript)
/// Publish an initial container once. A lost response does not cause a retry.
pub fn create_document(
  base_url base_url: String,
  tenant tenant: String,
  token token: String,
  summary summary: fluid_document.DocumentSummary,
) -> Promise(Result(String, StorageError)) {
  use body <- promise_try(
    fluid_document.encode_create_request(summary)
    |> result.map_error(SummaryStructure),
  )
  use request <- promise_try(build_post(
    document_create_url(base_url, tenant),
    token,
    json.to_string(body),
  ))
  send_fetch(
    request,
    initial_fetch_request(fetch.to_fetch_request(request)),
    decode_created_response,
  )
}

@target(erlang)
fn send_initial_request(
  request: Request(String),
) -> Result(Response(String), StorageError) {
  // httpc retries 503 responses even for POST. Gun returns the first response.
  let deadline = monotonic_time(Millisecond) + 30_000
  let #(transport, default_port) = case request.scheme {
    http.Http -> #(connection.Tcp, 80)
    http.Https -> #(connection.Tls, 443)
  }
  let options =
    connection.options()
    |> connection.with_transport(transport)
    |> connection.with_protocols([connection.Http1])
    |> connection.with_retry(connection.Milliseconds(0))
    |> connection.with_connect_timeout(connection.Milliseconds(30_000))
  let failed =
    RequestFailed(
      request.host <> request.path,
      "initial request did not complete",
    )
  use connection <- result.try(
    connection.open(
      options,
      request.host,
      option.unwrap(request.port, default_port),
    )
    |> result.replace_error(failed),
  )
  let sent = {
    use _ <- result.try(connection.await_up(
      connection,
      remaining_time(deadline),
    ))
    http_client.request_with(
      connection,
      http_request.Post,
      request.path,
      request.headers,
      bit_array.from_string(request.body),
      http_request.options(),
      connection.Milliseconds(30_000),
      http_request.request,
      fn(connection, stream, _) {
        case remaining_time(deadline) {
          connection.Milliseconds(0) -> Error(http_error.Timeout)
          timeout -> http_message.await(connection, stream, timeout)
        }
      },
    )
  }
  let closed = connection.shutdown(connection)
  use response <- result.try(sent |> result.replace_error(failed))
  use _ <- result.try(closed |> result.replace_error(failed))
  use body <- result.try(
    http_response.body_text(response)
    |> result.replace_error(BodyReadFailed(
      request.host <> request.path,
      "initial response is not UTF-8",
    )),
  )
  Ok(response.Response(
    http_response.status(response),
    http_response.headers(response),
    body,
  ))
}

@target(erlang)
type TimeUnit {
  Millisecond
}

@target(erlang)
@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: TimeUnit) -> Int

@target(erlang)
fn remaining_time(deadline: Int) -> connection.Timeout {
  let remaining = deadline - monotonic_time(Millisecond)
  connection.Milliseconds(int.max(0, remaining))
}

@target(javascript)
@external(javascript, "./git_storage_ffi.mjs", "initial_request")
fn initial_fetch_request(request: fetch.FetchRequest) -> fetch.FetchRequest

fn decode_created_response(
  request: Request(String),
  response: Response(String),
) -> Result(String, StorageError) {
  case response.status {
    201 -> decode_response(request, response, created_document_decoder())
    _ ->
      Error(UnexpectedStatus(
        request.host <> request.path,
        response.status,
        response.body,
      ))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared URL construction
// ─────────────────────────────────────────────────────────────────────────────

pub fn document_create_url(base_url: String, tenant: String) -> String {
  let base_url = case string.ends_with(base_url, "/") {
    True -> string.drop_end(base_url, 1)
    False -> base_url
  }
  base_url <> "/documents/" <> fluid_summary.encode_component(tenant)
}

pub fn created_document_decoder() -> Decoder(String) {
  use id <- decode.then(decode.string)
  case
    id != ""
    && id != "."
    && id != ".."
    && id == string.trim(id)
    && !list.any(string.to_utf_codepoints(id), fn(codepoint) {
      let value = string.utf_codepoint_to_int(codepoint)
      value <= 32 || value == 127
    })
    && !list.any(["/", "\\", "?", "#", ":", "%"], string.contains(id, _))
  {
    True -> decode.success(id)
    False -> decode.failure("", "a document identifier")
  }
}

pub fn commit_url(
  base_url: String,
  tenant: String,
  commit_id: String,
) -> String {
  base_url <> "/repos/" <> tenant <> "/git/commits/" <> commit_id
}

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

pub fn versions_url(
  base_url: String,
  tenant: String,
  document: String,
  count: Int,
) -> String {
  base_url
  <> "/repos/"
  <> tenant
  <> "/commits?sha="
  <> document
  <> "&count="
  <> int.to_string(count)
}

pub fn validate_version_count(count: Int) -> Result(Nil, StorageError) {
  case count > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidVersionCount(count))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared request-body construction
// ─────────────────────────────────────────────────────────────────────────────

pub fn hierarchy_blob_body(bytes: BitArray) -> String {
  json.object([
    #("content", json.string(bit_array.base64_encode(bytes, True))),
    #("encoding", json.string("base64")),
  ])
  |> json.to_string
}

pub fn hierarchy_tree_body(entries: List(HierarchyTreeEntry)) -> String {
  json.object([
    #(
      "tree",
      json.array(entries, fn(entry) {
        let #(mode, kind) = case entry.kind {
          HierarchyBlob -> #("100644", "blob")
          HierarchyTree -> #("040000", "tree")
        }
        json.object([
          #("mode", json.string(mode)),
          #("path", json.string(fluid_summary.encode_component(entry.name))),
          #("sha", json.string(entry.sha)),
          #("type", json.string(kind)),
        ])
      }),
    ),
  ])
  |> json.to_string
}

pub fn validate_hierarchy(
  tree: fluid_summary.SummaryEntry,
) -> Result(Nil, StorageError) {
  case tree {
    fluid_summary.SummaryTree(entries) ->
      validate_hierarchy_entries(entries, "/")
    fluid_summary.SummaryBlob(_) ->
      Error(
        SummaryStructure(fluid_summary.WrongKind("/", fluid_summary.TreeHandle)),
      )
    fluid_summary.SummaryHandle(_, _) ->
      Error(
        SummaryStructure(fluid_summary.UnsupportedEntry(
          "/",
          "hierarchy contains an unresolved handle",
        )),
      )
  }
}

fn validate_hierarchy_entries(
  entries: List(#(String, fluid_summary.SummaryEntry)),
  path: String,
) -> Result(Nil, StorageError) {
  use _ <- result.try(
    list.try_fold(entries, dict.new(), fn(seen, entry) {
      case dict.has_key(seen, entry.0) {
        True ->
          Error(
            SummaryStructure(fluid_summary.MalformedEntry(
              path,
              "duplicate entry: " <> entry.0,
            )),
          )
        False -> Ok(dict.insert(seen, entry.0, Nil))
      }
    }),
  )
  use _ <- result.try(
    list.try_each(entries, fn(entry) {
      let entry_path = hierarchy_child_path(path, entry.0)
      case entry.1 {
        fluid_summary.SummaryBlob(_) -> Ok(Nil)
        fluid_summary.SummaryTree(children) ->
          validate_hierarchy_entries(children, entry_path)
        fluid_summary.SummaryHandle(_, _) ->
          Error(
            SummaryStructure(fluid_summary.UnsupportedEntry(
              entry_path,
              "hierarchy contains an unresolved handle",
            )),
          )
      }
    }),
  )
  Ok(Nil)
}

fn hierarchy_child_path(parent: String, name: String) -> String {
  let encoded = fluid_summary.encode_component(name)
  case parent {
    "/" -> "/" <> encoded
    _ -> parent <> "/" <> encoded
  }
}

@target(erlang)
fn fetch_hierarchy_tree(
  base_url: String,
  tenant: String,
  token: String,
  tree_sha: String,
  path: String,
  active: List(String),
) -> Result(fluid_summary.SummaryEntry, StorageError) {
  use body <- result.try(
    get_text(tree_url(base_url, tenant, tree_sha), token)
    |> with_object_context(path, tree_sha, HierarchyTree),
  )
  use entries <- result.try(decode_hierarchy_tree(path, tree_sha, body))
  use children <- result.try(
    list.try_map(entries, fn(entry) {
      let entry_path = hierarchy_child_path(path, entry.name)
      case entry.kind {
        HierarchyBlob -> {
          use body <- result.try(
            get_text(blob_url(base_url, tenant, entry.sha), token)
            |> with_object_context(entry_path, entry.sha, HierarchyBlob),
          )
          use bytes <- result.try(decode_hierarchy_blob(
            entry_path,
            entry.sha,
            body,
          ))
          Ok(#(entry.name, fluid_summary.SummaryBlob(bytes)))
        }
        HierarchyTree ->
          case list.contains(active, entry.sha) {
            True ->
              Error(SummaryStructure(fluid_summary.CyclicReference(entry_path)))
            False -> {
              use tree <- result.try(
                fetch_hierarchy_tree(
                  base_url,
                  tenant,
                  token,
                  entry.sha,
                  entry_path,
                  [entry.sha, ..active],
                ),
              )
              Ok(#(entry.name, tree))
            }
          }
      }
    }),
  )
  Ok(fluid_summary.SummaryTree(children))
}

@target(javascript)
fn fetch_hierarchy_tree(
  base_url: String,
  tenant: String,
  token: String,
  tree_sha: String,
  path: String,
  active: List(String),
) -> Promise(Result(fluid_summary.SummaryEntry, StorageError)) {
  use body_result <- promise.await(get_text(
    tree_url(base_url, tenant, tree_sha),
    token,
  ))
  use body <- promise_try(with_object_context(
    body_result,
    path,
    tree_sha,
    HierarchyTree,
  ))
  use entries <- promise_try(decode_hierarchy_tree(path, tree_sha, body))
  use children <- promise.try_await(
    fetch_hierarchy_entries(base_url, tenant, token, entries, path, active, []),
  )
  promise.resolve(Ok(fluid_summary.SummaryTree(children)))
}

@target(javascript)
fn fetch_hierarchy_entries(
  base_url: String,
  tenant: String,
  token: String,
  entries: List(HierarchyTreeEntry),
  path: String,
  active: List(String),
  children: List(#(String, fluid_summary.SummaryEntry)),
) -> Promise(Result(List(#(String, fluid_summary.SummaryEntry)), StorageError)) {
  case entries {
    [] -> promise.resolve(Ok(list.reverse(children)))
    [entry, ..rest] -> {
      let entry_path = hierarchy_child_path(path, entry.name)
      case entry.kind {
        HierarchyBlob -> {
          use body_result <- promise.await(get_text(
            blob_url(base_url, tenant, entry.sha),
            token,
          ))
          use body <- promise_try(with_object_context(
            body_result,
            entry_path,
            entry.sha,
            HierarchyBlob,
          ))
          use bytes <- promise_try(decode_hierarchy_blob(
            entry_path,
            entry.sha,
            body,
          ))
          fetch_hierarchy_entries(base_url, tenant, token, rest, path, active, [
            #(entry.name, fluid_summary.SummaryBlob(bytes)),
            ..children
          ])
        }
        HierarchyTree ->
          case list.contains(active, entry.sha) {
            True ->
              promise.resolve(
                Error(
                  SummaryStructure(fluid_summary.CyclicReference(entry_path)),
                ),
              )
            False -> {
              use tree <- promise.try_await(
                fetch_hierarchy_tree(
                  base_url,
                  tenant,
                  token,
                  entry.sha,
                  entry_path,
                  [entry.sha, ..active],
                ),
              )
              fetch_hierarchy_entries(
                base_url,
                tenant,
                token,
                rest,
                path,
                active,
                [#(entry.name, tree), ..children],
              )
            }
          }
      }
    }
  }
}

@target(erlang)
fn stage_hierarchy_tree(
  base_url: String,
  tenant: String,
  token: String,
  entries: List(#(String, fluid_summary.SummaryEntry)),
) -> Result(String, StorageError) {
  use staged <- result.try(
    list.try_map(entries, fn(entry) {
      case entry.1 {
        fluid_summary.SummaryBlob(bytes) -> {
          use sha <- result.try(post_json(
            blobs_url(base_url, tenant),
            token,
            hierarchy_blob_body(bytes),
            sha_decoder(),
          ))
          Ok(HierarchyTreeEntry(entry.0, sha, HierarchyBlob))
        }
        fluid_summary.SummaryTree(children) -> {
          use sha <- result.try(stage_hierarchy_tree(
            base_url,
            tenant,
            token,
            children,
          ))
          Ok(HierarchyTreeEntry(entry.0, sha, HierarchyTree))
        }
        fluid_summary.SummaryHandle(_, _) ->
          Error(
            SummaryStructure(fluid_summary.UnsupportedEntry(
              hierarchy_child_path("/", entry.0),
              "hierarchy contains an unresolved handle",
            )),
          )
      }
    }),
  )
  post_json(
    trees_url(base_url, tenant),
    token,
    hierarchy_tree_body(staged),
    sha_decoder(),
  )
}

@target(javascript)
fn stage_hierarchy_tree(
  base_url: String,
  tenant: String,
  token: String,
  entries: List(#(String, fluid_summary.SummaryEntry)),
) -> Promise(Result(String, StorageError)) {
  use staged <- promise.try_await(
    stage_hierarchy_entries(base_url, tenant, token, entries, []),
  )
  post_json(
    trees_url(base_url, tenant),
    token,
    hierarchy_tree_body(staged),
    sha_decoder(),
  )
}

@target(javascript)
fn stage_hierarchy_entries(
  base_url: String,
  tenant: String,
  token: String,
  entries: List(#(String, fluid_summary.SummaryEntry)),
  staged: List(HierarchyTreeEntry),
) -> Promise(Result(List(HierarchyTreeEntry), StorageError)) {
  case entries {
    [] -> promise.resolve(Ok(list.reverse(staged)))
    [entry, ..rest] ->
      case entry.1 {
        fluid_summary.SummaryBlob(bytes) -> {
          use sha <- promise.try_await(post_json(
            blobs_url(base_url, tenant),
            token,
            hierarchy_blob_body(bytes),
            sha_decoder(),
          ))
          stage_hierarchy_entries(base_url, tenant, token, rest, [
            HierarchyTreeEntry(entry.0, sha, HierarchyBlob),
            ..staged
          ])
        }
        fluid_summary.SummaryTree(children) -> {
          use sha <- promise.try_await(stage_hierarchy_tree(
            base_url,
            tenant,
            token,
            children,
          ))
          stage_hierarchy_entries(base_url, tenant, token, rest, [
            HierarchyTreeEntry(entry.0, sha, HierarchyTree),
            ..staged
          ])
        }
        fluid_summary.SummaryHandle(_, _) ->
          promise.resolve(
            Error(
              SummaryStructure(fluid_summary.UnsupportedEntry(
                hierarchy_child_path("/", entry.0),
                "hierarchy contains an unresolved handle",
              )),
            ),
          )
      }
  }
}

fn with_object_context(
  response: Result(String, StorageError),
  path: String,
  object_sha: String,
  kind: HierarchyEntryKind,
) -> Result(String, StorageError) {
  case response {
    Error(UnexpectedStatus(_, 404, _)) ->
      Error(HierarchyObjectMissing(path, object_sha, kind))
    other -> other
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared response handling
// ─────────────────────────────────────────────────────────────────────────────

pub fn decode_hierarchy_blob(
  path: String,
  blob_sha: String,
  body: String,
) -> Result(BitArray, StorageError) {
  use blob <- result.try(
    json.parse(body, hierarchy_blob_content_decoder())
    |> result.map_error(fn(error) {
      HierarchyBlobUnreadable(
        path,
        blob_sha,
        "invalid blob response: " <> string.inspect(error),
      )
    }),
  )
  case blob.encoding {
    "base64" ->
      bit_array.base64_decode(blob.content)
      |> result.replace_error(HierarchyBlobUnreadable(
        path,
        blob_sha,
        "the content is not base64",
      ))
    "utf-8" -> Ok(<<blob.content:utf8>>)
    encoding ->
      Error(HierarchyBlobUnreadable(
        path,
        blob_sha,
        "unsupported encoding: " <> encoding,
      ))
  }
}

pub fn decode_hierarchy_tree(
  path: String,
  tree_sha: String,
  body: String,
) -> Result(List(HierarchyTreeEntry), StorageError) {
  use entries <- result.try(
    json.parse(body, hierarchy_tree_decoder())
    |> result.map_error(fn(error) {
      SummaryStructure(fluid_summary.MalformedEntry(
        path,
        "tree "
          <> tree_sha
          <> " response did not decode: "
          <> string.inspect(error),
      ))
    }),
  )
  use decoded <- result.try(
    list.try_map(entries, fn(entry) {
      use name <- result.try(
        uri.percent_decode(entry.path)
        |> result.replace_error(
          SummaryStructure(fluid_summary.MalformedEntry(
            path,
            "invalid percent encoding: " <> entry.path,
          )),
        ),
      )
      let entry_path = hierarchy_child_path(path, name)
      use kind <- result.try(case entry.kind, entry.mode {
        "blob", "100644" -> Ok(HierarchyBlob)
        "tree", "040000" -> Ok(HierarchyTree)
        kind, mode ->
          Error(
            SummaryStructure(fluid_summary.UnsupportedEntry(
              entry_path,
              "git entry type " <> kind <> " with mode " <> mode,
            )),
          )
      })
      Ok(HierarchyTreeEntry(name:, sha: entry.sha, kind:))
    }),
  )
  use _ <- result.try(
    list.try_fold(decoded, dict.new(), fn(seen, entry) {
      case dict.has_key(seen, entry.name) {
        True ->
          Error(
            SummaryStructure(fluid_summary.MalformedEntry(
              path,
              "duplicate entry: " <> entry.name,
            )),
          )
        False -> Ok(dict.insert(seen, entry.name, Nil))
      }
    }),
  )
  Ok(decoded)
}

/// Find the SHA of the summary blob in a decoded tree.
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

fn response_body(
  request: Request(String),
  response: Response(String),
) -> Result(String, StorageError) {
  let url = request.host <> request.path
  case is_success(response) {
    True -> Ok(response.body)
    False -> Error(UnexpectedStatus(url, response.status, response.body))
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
fn get_text(url: String, token: String) -> Result(String, StorageError) {
  use request <- result.try(build_get(url, token))
  send_text(request)
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

@target(erlang)
fn send_text(request: Request(String)) -> Result(String, StorageError) {
  let request = request.set_header(request, "connection", "close")
  use response <- result.try(
    httpc.send(request)
    |> result.map_error(fn(error) {
      RequestFailed(request.host <> request.path, string.inspect(error))
    }),
  )
  response_body(request, response)
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
fn get_text(
  url: String,
  token: String,
) -> Promise(Result(String, StorageError)) {
  case build_get(url, token) {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(request) -> send_text(request)
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
  send_fetch(request, fetch.to_fetch_request(request), fn(request, response) {
    decode_response(request, response, decoder)
  })
}

@target(javascript)
fn send_fetch(
  request: Request(String),
  fetch_request: fetch.FetchRequest,
  decode: fn(Request(String), Response(String)) -> Result(a, StorageError),
) -> Promise(Result(a, StorageError)) {
  use sent <- promise.try_await(
    fetch.raw_send(fetch_request)
    |> promise.map(
      result.map_error(_, fn(error) {
        RequestFailed(request.host <> request.path, string.inspect(error))
      }),
    ),
  )
  use response <- promise.try_await(
    fetch.read_text_body(fetch.from_fetch_response(sent))
    |> promise.map(
      result.map_error(_, fn(error) {
        BodyReadFailed(request.host <> request.path, string.inspect(error))
      }),
    ),
  )
  promise.resolve(decode(request, response))
}

@target(javascript)
fn send_text(
  request: Request(String),
) -> Promise(Result(String, StorageError)) {
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
  promise.resolve(response_body(request, response))
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

type HierarchyBlobContent {
  HierarchyBlobContent(content: String, encoding: String)
}

type HierarchyRawTreeEntry {
  HierarchyRawTreeEntry(path: String, sha: String, kind: String, mode: String)
}

fn hierarchy_blob_content_decoder() -> Decoder(HierarchyBlobContent) {
  use content <- decode.field("content", decode.string)
  use encoding <- decode.field("encoding", decode.string)
  decode.success(HierarchyBlobContent(content:, encoding:))
}

fn hierarchy_tree_decoder() -> Decoder(List(HierarchyRawTreeEntry)) {
  decode.at(["tree"], decode.list(hierarchy_tree_entry_decoder()))
}

fn hierarchy_tree_entry_decoder() -> Decoder(HierarchyRawTreeEntry) {
  use path <- decode.field("path", decode.string)
  use sha <- decode.field("sha", decode.string)
  use kind <- decode.field("type", decode.string)
  use mode <- decode.field("mode", decode.string)
  decode.success(HierarchyRawTreeEntry(path:, sha:, kind:, mode:))
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

/// Decode a commit response to its root tree SHA.
pub fn commit_tree_decoder() -> Decoder(String) {
  decode.subfield(["tree", "sha"], decode.string, decode.success)
}

/// Decode the newest-first commit history response.
pub fn versions_decoder() -> Decoder(List(SummaryVersion)) {
  decode.list(version_decoder())
}

fn version_decoder() -> Decoder(SummaryVersion) {
  use id <- decode.field("sha", decode.string)
  use message <- decode.subfield(["commit", "message"], decode.string)
  use created_at <- decode.subfield(
    ["commit", "committer", "date"],
    decode.string,
  )
  use tree_id <- decode.subfield(["commit", "tree", "sha"], decode.string)
  decode.success(SummaryVersion(
    id: id,
    tree_id: tree_id,
    message: message,
    created_at: created_at,
  ))
}

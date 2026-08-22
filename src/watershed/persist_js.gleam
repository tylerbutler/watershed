//// Durable browser persistence for peer-to-peer CRDT documents.
////
//// A stored snapshot is another replica, not a cache. A save joins the most
//// recent stored snapshot into the live document, then exports and writes the
//// joined state. One storage update contains all of those steps.
////
//// The module reports a corrupt or incompatible value and keeps it in storage.
//// It never deletes the only copy of the offline edits, unless the caller
//// selects `replace/3` recovery.
////
//// JavaScript target only.

@target(javascript)
import gleam/json
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/result
@target(javascript)
import gleam/string
@target(javascript)
import watershed/crdt_js.{type Config, type CrdtDocument}
@target(javascript)
import watershed/p2p.{type P2pError}
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/wire

@target(javascript)
pub type PersistenceError {
  StorageFailure(detail: String)
  SnapshotFailure(error: P2pError)
  SnapshotDecodeFailure(detail: String)
}

@target(javascript)
/// A replaceable storage seam that supplies a read and an atomic update.
/// Production code uses `indexed_db`. A test can supply an in-memory
/// implementation, which needs no browser.
pub opaque type Storage {
  Storage(
    get: fn(String, fn(Result(Option(String), String)) -> Nil) -> Nil,
    update: fn(
      String,
      fn(Bool, String, fn(String) -> Nil, fn() -> Nil) -> Nil,
      fn() -> Nil,
      fn() -> Nil,
      fn(String) -> Nil,
    ) -> Nil,
  )
}

@target(javascript)
pub fn storage(
  get get: fn(String, fn(Result(Option(String), String)) -> Nil) -> Nil,
  update update: fn(
    String,
    fn(Bool, String, fn(String) -> Nil, fn() -> Nil) -> Nil,
    fn() -> Nil,
    fn() -> Nil,
    fn(String) -> Nil,
  ) -> Nil,
) -> Storage {
  Storage(get:, update:)
}

@target(javascript)
/// IndexedDB storage under the `watershed/snapshots` object store.
pub fn indexed_db() -> Storage {
  storage(
    get: fn(key, done) {
      idb_get(
        key,
        on_missing: fn() { done(Ok(None)) },
        on_found: fn(value) { done(Ok(Some(value))) },
        on_error: fn(detail) { done(Error(detail)) },
      )
    },
    update: fn(key, transform, on_ok, on_abort, on_error) {
      idb_update(
        key,
        transform: transform,
        on_ok: on_ok,
        on_abort: on_abort,
        on_error: on_error,
      )
    },
  )
}

@target(javascript)
/// Load a detached document. The result is `None` if this browser has never
/// stored the room. Invalid bytes stay in storage, and the function returns an
/// error.
pub fn load(
  storage: Storage,
  config: Config(root),
  done: fn(Result(Option(CrdtDocument(root)), PersistenceError)) -> Nil,
) -> Nil {
  let Storage(get:, ..) = storage
  get(
    storage_key(
      crdt_js.config_room(config),
      crdt_js.config_compatibility(config),
    ),
    fn(found) {
      case found {
        Error(detail) -> done(Error(StorageFailure(detail)))
        Ok(None) -> done(Ok(None))
        Ok(Some(raw)) -> done(load_snapshot(config, raw))
      }
    },
  )
}

@target(javascript)
fn load_snapshot(
  config: Config(root),
  raw: String,
) -> Result(Option(CrdtDocument(root)), PersistenceError) {
  use snapshot <- result.try(decode_snapshot(raw))
  crdt_js.import_snapshot(config, snapshot)
  |> result.map(Some)
  |> result.map_error(SnapshotFailure)
}

@target(javascript)
/// Join the most recent stored value into `document`. Then replace the stored
/// value with the joined canonical snapshot, in one atomic update.
pub fn save(
  storage: Storage,
  document: CrdtDocument(root),
  done: fn(Result(String, PersistenceError)) -> Nil,
) -> Nil {
  write_snapshot(
    storage,
    document,
    fn(found, raw) { prepare_save(document, found, raw) },
    done,
  )
}

@target(javascript)
/// Replace the stored snapshot with the current document, in one atomic
/// update. This function ignores unreadable or incompatible stored bytes on
/// purpose.
pub fn replace(
  storage: Storage,
  document: CrdtDocument(root),
  done: fn(Result(String, PersistenceError)) -> Nil,
) -> Nil {
  write_snapshot(
    storage,
    document,
    fn(_, _) { prepare_replace(document) },
    done,
  )
}

@target(javascript)
fn write_snapshot(
  storage: Storage,
  document: CrdtDocument(root),
  prepare: fn(Bool, String) -> Result(#(String, String), PersistenceError),
  done: fn(Result(String, PersistenceError)) -> Nil,
) -> Nil {
  let Storage(update:, ..) = storage
  let key =
    storage_key(crdt_js.room_id(document), crdt_js.compatibility_tag(document))
  let resolution = transport_js.new_cell(None)
  update(
    key,
    fn(found, raw, write, abort) {
      case prepare(found, raw) {
        Ok(#(saved_digest, snapshot)) -> {
          transport_js.set_cell(resolution, Some(WriteDigest(saved_digest)))
          write(snapshot)
        }
        Error(error) -> {
          transport_js.set_cell(resolution, Some(WriteTransformFailed(error)))
          abort()
        }
      }
    },
    fn() { finish_snapshot_written(resolution, done) },
    fn() { finish_snapshot_aborted(resolution, done) },
    fn(detail) { done(Error(StorageFailure(detail))) },
  )
}

@target(javascript)
type WriteResolution {
  WriteDigest(String)
  WriteTransformFailed(PersistenceError)
}

@target(javascript)
fn prepare_save(
  document: CrdtDocument(root),
  found: Bool,
  raw: String,
) -> Result(#(String, String), PersistenceError) {
  use _ <- result.try(case found {
    True -> merge_stored(document, raw)
    False -> Ok(Nil)
  })
  use snapshot <- result.try(
    crdt_js.export_snapshot(document)
    |> result.map_error(SnapshotFailure),
  )
  Ok(#(crdt_js.digest(document), json.to_string(snapshot)))
}

@target(javascript)
fn prepare_replace(
  document: CrdtDocument(root),
) -> Result(#(String, String), PersistenceError) {
  crdt_js.export_snapshot(document)
  |> result.map(fn(snapshot) {
    #(crdt_js.digest(document), json.to_string(snapshot))
  })
  |> result.map_error(SnapshotFailure)
}

@target(javascript)
fn finish_snapshot_written(
  resolution: transport_js.Cell(Option(WriteResolution)),
  done: fn(Result(String, PersistenceError)) -> Nil,
) -> Nil {
  case transport_js.get_cell(resolution) {
    Some(WriteDigest(saved_digest)) -> done(Ok(saved_digest))
    Some(WriteTransformFailed(error)) -> done(Error(error))
    None ->
      done(
        Error(StorageFailure(
          "browser storage completed without writing a snapshot",
        )),
      )
  }
}

@target(javascript)
fn finish_snapshot_aborted(
  resolution: transport_js.Cell(Option(WriteResolution)),
  done: fn(Result(String, PersistenceError)) -> Nil,
) -> Nil {
  case transport_js.get_cell(resolution) {
    Some(WriteTransformFailed(error)) -> done(Error(error))
    Some(WriteDigest(_)) ->
      done(
        Error(StorageFailure(
          "browser storage aborted after queueing a snapshot write",
        )),
      )
    None -> done(Error(StorageFailure("browser storage aborted the save")))
  }
}

@target(javascript)
fn merge_stored(
  document: CrdtDocument(root),
  raw: String,
) -> Result(Nil, PersistenceError) {
  use snapshot <- result.try(decode_snapshot(raw))
  crdt_js.merge_snapshot(document, snapshot)
  |> result.map(fn(_) { Nil })
  |> result.map_error(SnapshotFailure)
}

@target(javascript)
fn decode_snapshot(raw: String) -> Result(json.Json, PersistenceError) {
  json.parse(raw, wire.json_value_decoder())
  |> result.map_error(fn(error) {
    SnapshotDecodeFailure(
      "stored snapshot is not valid JSON: " <> string.inspect(error),
    )
  })
}

@target(javascript)
fn storage_key(room: String, compatibility: String) -> String {
  json.to_string(
    json.preprocessed_array([
      json.string(room),
      json.string(compatibility),
    ]),
  )
}

@target(javascript)
pub fn describe_error(error: PersistenceError) -> String {
  case error {
    StorageFailure(detail) -> "browser storage failed: " <> detail
    SnapshotFailure(error) -> crdt_js.describe_error(error)
    SnapshotDecodeFailure(detail) -> detail
  }
}

@target(javascript)
@external(javascript, "./persist_js_ffi.mjs", "getSnapshot")
fn idb_get(
  key: String,
  on_missing on_missing: fn() -> Nil,
  on_found on_found: fn(String) -> Nil,
  on_error on_error: fn(String) -> Nil,
) -> Nil

@target(javascript)
@external(javascript, "./persist_js_ffi.mjs", "updateSnapshot")
fn idb_update(
  key: String,
  transform transform: fn(Bool, String, fn(String) -> Nil, fn() -> Nil) -> Nil,
  on_ok on_ok: fn() -> Nil,
  on_abort on_abort: fn() -> Nil,
  on_error on_error: fn(String) -> Nil,
) -> Nil

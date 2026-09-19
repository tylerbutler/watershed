/// <reference types="./persist_js.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, Error, toList, CustomType as $CustomType } from "../gleam.mjs";
import * as $crdt_js from "../watershed/crdt_js.mjs";
import * as $p2p from "../watershed/p2p.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import * as $wire from "../watershed/wire.mjs";
import { updateSnapshot as idb_update, getSnapshot as idb_get } from "./persist_js_ffi.mjs";

export class StorageFailure extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const PersistenceError$StorageFailure = (detail) =>
  new StorageFailure(detail);
export const PersistenceError$isStorageFailure = (value) =>
  value instanceof StorageFailure;
export const PersistenceError$StorageFailure$detail = (value) => value.detail;
export const PersistenceError$StorageFailure$0 = (value) => value.detail;

export class SnapshotFailure extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const PersistenceError$SnapshotFailure = (error) =>
  new SnapshotFailure(error);
export const PersistenceError$isSnapshotFailure = (value) =>
  value instanceof SnapshotFailure;
export const PersistenceError$SnapshotFailure$error = (value) => value.error;
export const PersistenceError$SnapshotFailure$0 = (value) => value.error;

export class SnapshotDecodeFailure extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const PersistenceError$SnapshotDecodeFailure = (detail) =>
  new SnapshotDecodeFailure(detail);
export const PersistenceError$isSnapshotDecodeFailure = (value) =>
  value instanceof SnapshotDecodeFailure;
export const PersistenceError$SnapshotDecodeFailure$detail = (value) =>
  value.detail;
export const PersistenceError$SnapshotDecodeFailure$0 = (value) => value.detail;

class Storage extends $CustomType {
  constructor(get, update) {
    super();
    this.get = get;
    this.update = update;
  }
}

class WriteDigest extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class WriteTransformFailed extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

export function storage(get, update) {
  return new Storage(get, update);
}

/**
 * IndexedDB storage under the `watershed/snapshots` object store.
 */
export function indexed_db() {
  return storage(
    (key, done) => {
      return idb_get(
        key,
        () => { return done(new Ok(Option$None$const)); },
        (value) => { return done(new Ok(new Some(value))); },
        (detail) => { return done(new Error(detail)); },
      );
    },
    (key, transform, on_ok, on_abort, on_error) => {
      return idb_update(key, transform, on_ok, on_abort, on_error);
    },
  );
}

function decode_snapshot(raw) {
  let _pipe = $json.parse(raw, $wire.json_value_decoder());
  return $result.map_error(
    _pipe,
    (error) => {
      return new SnapshotDecodeFailure(
        "stored snapshot is not valid JSON: " + $string.inspect(error),
      );
    },
  );
}

function load_snapshot(config, raw) {
  return $result.try$(
    decode_snapshot(raw),
    (snapshot) => {
      let _pipe = $crdt_js.import_snapshot(config, snapshot);
      let _pipe$1 = $result.map(_pipe, (var0) => { return new Some(var0); });
      return $result.map_error(
        _pipe$1,
        (var0) => { return new SnapshotFailure(var0); },
      );
    },
  );
}

function storage_key(room, compatibility) {
  return $json.to_string(
    $json.preprocessed_array(
      toList([$json.string(room), $json.string(compatibility)]),
    ),
  );
}

/**
 * Load a detached document. The result is `None` if this browser has never
 * stored the room. Invalid bytes stay in storage, and the function returns an
 * error.
 */
export function load(storage, config, done) {
  let get = storage.get;
  return get(
    storage_key(
      $crdt_js.config_room(config),
      $crdt_js.config_compatibility(config),
    ),
    (found) => {
      if (found instanceof Ok) {
        let $ = found[0];
        if ($ instanceof Some) {
          let raw = $[0];
          return done(load_snapshot(config, raw));
        } else {
          return done(new Ok(Option$None$const));
        }
      } else {
        let detail = found[0];
        return done(new Error(new StorageFailure(detail)));
      }
    },
  );
}

function merge_stored(document, raw) {
  return $result.try$(
    decode_snapshot(raw),
    (snapshot) => {
      let _pipe = $crdt_js.merge_snapshot(document, snapshot);
      let _pipe$1 = $result.map(_pipe, (_) => { return undefined; });
      return $result.map_error(
        _pipe$1,
        (var0) => { return new SnapshotFailure(var0); },
      );
    },
  );
}

function prepare_save(document, found, raw) {
  return $result.try$(
    (() => {
      if (found) {
        return merge_stored(document, raw);
      } else {
        return new Ok(undefined);
      }
    })(),
    (_) => {
      return $result.try$(
        (() => {
          let _pipe = $crdt_js.export_snapshot(document);
          return $result.map_error(
            _pipe,
            (var0) => { return new SnapshotFailure(var0); },
          );
        })(),
        (snapshot) => {
          return new Ok([$crdt_js.digest(document), $json.to_string(snapshot)]);
        },
      );
    },
  );
}

function finish_snapshot_aborted(resolution, done) {
  let $ = $transport_js.get_cell(resolution);
  if ($ instanceof Some) {
    let $1 = $[0];
    if ($1 instanceof WriteDigest) {
      return done(
        new Error(
          new StorageFailure(
            "browser storage aborted after queueing a snapshot write",
          ),
        ),
      );
    } else {
      let error = $1[0];
      return done(new Error(error));
    }
  } else {
    return done(
      new Error(new StorageFailure("browser storage aborted the save")),
    );
  }
}

function finish_snapshot_written(resolution, done) {
  let $ = $transport_js.get_cell(resolution);
  if ($ instanceof Some) {
    let $1 = $[0];
    if ($1 instanceof WriteDigest) {
      let saved_digest = $1[0];
      return done(new Ok(saved_digest));
    } else {
      let error = $1[0];
      return done(new Error(error));
    }
  } else {
    return done(
      new Error(
        new StorageFailure(
          "browser storage completed without writing a snapshot",
        ),
      ),
    );
  }
}

function write_snapshot(storage, document, prepare, done) {
  let update = storage.update;
  let key = storage_key(
    $crdt_js.room_id(document),
    $crdt_js.compatibility_tag(document),
  );
  let resolution = $transport_js.new_cell(Option$None$const);
  return update(
    key,
    (found, raw, write, abort) => {
      let $ = prepare(found, raw);
      if ($ instanceof Ok) {
        let saved_digest = $[0][0];
        let snapshot = $[0][1];
        $transport_js.set_cell(
          resolution,
          new Some(new WriteDigest(saved_digest)),
        );
        return write(snapshot);
      } else {
        let error = $[0];
        $transport_js.set_cell(
          resolution,
          new Some(new WriteTransformFailed(error)),
        );
        return abort();
      }
    },
    () => { return finish_snapshot_written(resolution, done); },
    () => { return finish_snapshot_aborted(resolution, done); },
    (detail) => { return done(new Error(new StorageFailure(detail))); },
  );
}

/**
 * Join the most recent stored value into `document`. Then replace the stored
 * value with the joined canonical snapshot, in one atomic update.
 */
export function save(storage, document, done) {
  return write_snapshot(
    storage,
    document,
    (found, raw) => { return prepare_save(document, found, raw); },
    done,
  );
}

function prepare_replace(document) {
  let _pipe = $crdt_js.export_snapshot(document);
  let _pipe$1 = $result.map(
    _pipe,
    (snapshot) => {
      return [$crdt_js.digest(document), $json.to_string(snapshot)];
    },
  );
  return $result.map_error(
    _pipe$1,
    (var0) => { return new SnapshotFailure(var0); },
  );
}

/**
 * Replace the stored snapshot with the current document, in one atomic
 * update. This function ignores unreadable or incompatible stored bytes on
 * purpose.
 */
export function replace(storage, document, done) {
  return write_snapshot(
    storage,
    document,
    (_, _1) => { return prepare_replace(document); },
    done,
  );
}

export function describe_error(error) {
  if (error instanceof StorageFailure) {
    let detail = error.detail;
    return "browser storage failed: " + detail;
  } else if (error instanceof SnapshotFailure) {
    let error$1 = error.error;
    return $crdt_js.describe_error(error$1);
  } else {
    let detail = error.detail;
    return detail;
  }
}

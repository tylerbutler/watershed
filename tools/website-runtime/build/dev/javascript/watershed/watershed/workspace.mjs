/// <reference types="./workspace.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  makeError,
} from "../gleam.mjs";
import * as $component from "../watershed/component.mjs";
import * as $handle from "../watershed/handle.mjs";
import * as $port from "../watershed/port.mjs";
import * as $port_graph from "../watershed/port_graph.mjs";
import * as $schema from "../watershed/schema.mjs";
import * as $wire from "../watershed/wire.mjs";

const FILEPATH = "src/watershed/workspace.gleam";

export class ManifestEntry extends $CustomType {
  constructor(instance_id, kind, version, config, child_handle) {
    super();
    this.instance_id = instance_id;
    this.kind = kind;
    this.version = version;
    this.config = config;
    this.child_handle = child_handle;
  }
}
export const ManifestEntry$ManifestEntry = (instance_id, kind, version, config, child_handle) =>
  new ManifestEntry(instance_id, kind, version, config, child_handle);
export const ManifestEntry$isManifestEntry = (value) =>
  value instanceof ManifestEntry;
export const ManifestEntry$ManifestEntry$instance_id = (value) =>
  value.instance_id;
export const ManifestEntry$ManifestEntry$0 = (value) => value.instance_id;
export const ManifestEntry$ManifestEntry$kind = (value) => value.kind;
export const ManifestEntry$ManifestEntry$1 = (value) => value.kind;
export const ManifestEntry$ManifestEntry$version = (value) => value.version;
export const ManifestEntry$ManifestEntry$2 = (value) => value.version;
export const ManifestEntry$ManifestEntry$config = (value) => value.config;
export const ManifestEntry$ManifestEntry$3 = (value) => value.config;
export const ManifestEntry$ManifestEntry$child_handle = (value) =>
  value.child_handle;
export const ManifestEntry$ManifestEntry$4 = (value) => value.child_handle;

export class StoredManifestEntry extends $CustomType {
  constructor(key, raw, decoded) {
    super();
    this.key = key;
    this.raw = raw;
    this.decoded = decoded;
  }
}
export const StoredManifestEntry$StoredManifestEntry = (key, raw, decoded) =>
  new StoredManifestEntry(key, raw, decoded);
export const StoredManifestEntry$isStoredManifestEntry = (value) =>
  value instanceof StoredManifestEntry;
export const StoredManifestEntry$StoredManifestEntry$key = (value) => value.key;
export const StoredManifestEntry$StoredManifestEntry$0 = (value) => value.key;
export const StoredManifestEntry$StoredManifestEntry$raw = (value) => value.raw;
export const StoredManifestEntry$StoredManifestEntry$1 = (value) => value.raw;
export const StoredManifestEntry$StoredManifestEntry$decoded = (value) =>
  value.decoded;
export const StoredManifestEntry$StoredManifestEntry$2 = (value) =>
  value.decoded;

export class InvalidManifest extends $CustomType {
  constructor(key, reason) {
    super();
    this.key = key;
    this.reason = reason;
  }
}
export const Diagnostic$InvalidManifest = (key, reason) =>
  new InvalidManifest(key, reason);
export const Diagnostic$isInvalidManifest = (value) =>
  value instanceof InvalidManifest;
export const Diagnostic$InvalidManifest$key = (value) => value.key;
export const Diagnostic$InvalidManifest$0 = (value) => value.key;
export const Diagnostic$InvalidManifest$reason = (value) => value.reason;
export const Diagnostic$InvalidManifest$1 = (value) => value.reason;

export class ManifestIdMismatch extends $CustomType {
  constructor(key, encoded_id) {
    super();
    this.key = key;
    this.encoded_id = encoded_id;
  }
}
export const Diagnostic$ManifestIdMismatch = (key, encoded_id) =>
  new ManifestIdMismatch(key, encoded_id);
export const Diagnostic$isManifestIdMismatch = (value) =>
  value instanceof ManifestIdMismatch;
export const Diagnostic$ManifestIdMismatch$key = (value) => value.key;
export const Diagnostic$ManifestIdMismatch$0 = (value) => value.key;
export const Diagnostic$ManifestIdMismatch$encoded_id = (value) =>
  value.encoded_id;
export const Diagnostic$ManifestIdMismatch$1 = (value) => value.encoded_id;

export class InvalidLayout extends $CustomType {
  constructor(index, reason) {
    super();
    this.index = index;
    this.reason = reason;
  }
}
export const Diagnostic$InvalidLayout = (index, reason) =>
  new InvalidLayout(index, reason);
export const Diagnostic$isInvalidLayout = (value) =>
  value instanceof InvalidLayout;
export const Diagnostic$InvalidLayout$index = (value) => value.index;
export const Diagnostic$InvalidLayout$0 = (value) => value.index;
export const Diagnostic$InvalidLayout$reason = (value) => value.reason;
export const Diagnostic$InvalidLayout$1 = (value) => value.reason;

export class DuplicateLayout extends $CustomType {
  constructor(instance_id) {
    super();
    this.instance_id = instance_id;
  }
}
export const Diagnostic$DuplicateLayout = (instance_id) =>
  new DuplicateLayout(instance_id);
export const Diagnostic$isDuplicateLayout = (value) =>
  value instanceof DuplicateLayout;
export const Diagnostic$DuplicateLayout$instance_id = (value) =>
  value.instance_id;
export const Diagnostic$DuplicateLayout$0 = (value) => value.instance_id;

export class UnknownLayout extends $CustomType {
  constructor(instance_id) {
    super();
    this.instance_id = instance_id;
  }
}
export const Diagnostic$UnknownLayout = (instance_id) =>
  new UnknownLayout(instance_id);
export const Diagnostic$isUnknownLayout = (value) =>
  value instanceof UnknownLayout;
export const Diagnostic$UnknownLayout$instance_id = (value) =>
  value.instance_id;
export const Diagnostic$UnknownLayout$0 = (value) => value.instance_id;

export class InvalidConnection extends $CustomType {
  constructor(index, reason) {
    super();
    this.index = index;
    this.reason = reason;
  }
}
export const Diagnostic$InvalidConnection = (index, reason) =>
  new InvalidConnection(index, reason);
export const Diagnostic$isInvalidConnection = (value) =>
  value instanceof InvalidConnection;
export const Diagnostic$InvalidConnection$index = (value) => value.index;
export const Diagnostic$InvalidConnection$0 = (value) => value.index;
export const Diagnostic$InvalidConnection$reason = (value) => value.reason;
export const Diagnostic$InvalidConnection$1 = (value) => value.reason;

export class InvalidGraph extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const Diagnostic$InvalidGraph = (error) => new InvalidGraph(error);
export const Diagnostic$isInvalidGraph = (value) =>
  value instanceof InvalidGraph;
export const Diagnostic$InvalidGraph$error = (value) => value.error;
export const Diagnostic$InvalidGraph$0 = (value) => value.error;

/**
 * The entry is valid, but its child map is not available yet.
 */
export class Loading extends $CustomType {
  constructor(entry, reason) {
    super();
    this.entry = entry;
    this.reason = reason;
  }
}
export const PreparationState$Loading = (entry, reason) =>
  new Loading(entry, reason);
export const PreparationState$isLoading = (value) => value instanceof Loading;
export const PreparationState$Loading$entry = (value) => value.entry;
export const PreparationState$Loading$0 = (value) => value.entry;
export const PreparationState$Loading$reason = (value) => value.reason;
export const PreparationState$Loading$1 = (value) => value.reason;

/**
 * The descriptor, config, and child map are available.
 */
export class Prepared extends $CustomType {
  constructor(entry, subtree) {
    super();
    this.entry = entry;
    this.subtree = subtree;
  }
}
export const PreparationState$Prepared = (entry, subtree) =>
  new Prepared(entry, subtree);
export const PreparationState$isPrepared = (value) => value instanceof Prepared;
export const PreparationState$Prepared$entry = (value) => value.entry;
export const PreparationState$Prepared$0 = (value) => value.entry;
export const PreparationState$Prepared$subtree = (value) => value.subtree;
export const PreparationState$Prepared$1 = (value) => value.subtree;

/**
 * The local catalog does not support the stored kind and version.
 */
export class Unavailable extends $CustomType {
  constructor(entry, reason) {
    super();
    this.entry = entry;
    this.reason = reason;
  }
}
export const PreparationState$Unavailable = (entry, reason) =>
  new Unavailable(entry, reason);
export const PreparationState$isUnavailable = (value) =>
  value instanceof Unavailable;
export const PreparationState$Unavailable$entry = (value) => value.entry;
export const PreparationState$Unavailable$0 = (value) => value.entry;
export const PreparationState$Unavailable$reason = (value) => value.reason;
export const PreparationState$Unavailable$1 = (value) => value.reason;

/**
 * The stored entry or component config is invalid.
 */
export class Failed extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const PreparationState$Failed = (instance_id, reason) =>
  new Failed(instance_id, reason);
export const PreparationState$isFailed = (value) => value instanceof Failed;
export const PreparationState$Failed$instance_id = (value) => value.instance_id;
export const PreparationState$Failed$0 = (value) => value.instance_id;
export const PreparationState$Failed$reason = (value) => value.reason;
export const PreparationState$Failed$1 = (value) => value.reason;

export class InvalidStoredManifest extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const PreparationError$InvalidStoredManifest = (reason) =>
  new InvalidStoredManifest(reason);
export const PreparationError$isInvalidStoredManifest = (value) =>
  value instanceof InvalidStoredManifest;
export const PreparationError$InvalidStoredManifest$reason = (value) =>
  value.reason;
export const PreparationError$InvalidStoredManifest$0 = (value) => value.reason;

export class StoredIdMismatch extends $CustomType {
  constructor(encoded_id) {
    super();
    this.encoded_id = encoded_id;
  }
}
export const PreparationError$StoredIdMismatch = (encoded_id) =>
  new StoredIdMismatch(encoded_id);
export const PreparationError$isStoredIdMismatch = (value) =>
  value instanceof StoredIdMismatch;
export const PreparationError$StoredIdMismatch$encoded_id = (value) =>
  value.encoded_id;
export const PreparationError$StoredIdMismatch$0 = (value) => value.encoded_id;

export class InvalidComponentConfig extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const PreparationError$InvalidComponentConfig = (reason) =>
  new InvalidComponentConfig(reason);
export const PreparationError$isInvalidComponentConfig = (value) =>
  value instanceof InvalidComponentConfig;
export const PreparationError$InvalidComponentConfig$reason = (value) =>
  value.reason;
export const PreparationError$InvalidComponentConfig$0 = (value) =>
  value.reason;

export class RejectedConnection extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const ConnectionError$RejectedConnection = (reason) =>
  new RejectedConnection(reason);
export const ConnectionError$isRejectedConnection = (value) =>
  value instanceof RejectedConnection;
export const ConnectionError$RejectedConnection$reason = (value) =>
  value.reason;
export const ConnectionError$RejectedConnection$0 = (value) => value.reason;

export class DisplacesConnection extends $CustomType {
  constructor(connection_id) {
    super();
    this.connection_id = connection_id;
  }
}
export const ConnectionError$DisplacesConnection = (connection_id) =>
  new DisplacesConnection(connection_id);
export const ConnectionError$isDisplacesConnection = (value) =>
  value instanceof DisplacesConnection;
export const ConnectionError$DisplacesConnection$connection_id = (value) =>
  value.connection_id;
export const ConnectionError$DisplacesConnection$0 = (value) =>
  value.connection_id;

export class Move extends $CustomType {
  constructor(remove_indexes, from_index, to_index) {
    super();
    this.remove_indexes = remove_indexes;
    this.from_index = from_index;
    this.to_index = to_index;
  }
}
export const Move$Move = (remove_indexes, from_index, to_index) =>
  new Move(remove_indexes, from_index, to_index);
export const Move$isMove = (value) => value instanceof Move;
export const Move$Move$remove_indexes = (value) => value.remove_indexes;
export const Move$Move$0 = (value) => value.remove_indexes;
export const Move$Move$from_index = (value) => value.from_index;
export const Move$Move$1 = (value) => value.from_index;
export const Move$Move$to_index = (value) => value.to_index;
export const Move$Move$2 = (value) => value.to_index;

class Snapshot extends $CustomType {
  constructor(manifest, entries, raw_layout, layout, raw_connections, stored_connections, graph, diagnostics) {
    super();
    this.manifest = manifest;
    this.entries = entries;
    this.raw_layout = raw_layout;
    this.layout = layout;
    this.raw_connections = raw_connections;
    this.stored_connections = stored_connections;
    this.graph = graph;
    this.diagnostics = diagnostics;
  }
}

/**
 * The workspace manifest.
 */
export function manifest_field() {
  return $schema.channel_field("manifest");
}

/**
 * The ordered component instance IDs.
 */
export function layout_field() {
  return $schema.channel_field("layout");
}

/**
 * The stored component port connections.
 */
export function connections_field() {
  return $schema.channel_field("connections");
}

/**
 * Encode one manifest entry.
 */
export function encode_manifest(entry) {
  return $json.object(
    toList([
      ["instanceId", $json.string(entry.instance_id)],
      ["kind", $json.string(entry.kind)],
      ["version", $json.int(entry.version)],
      ["config", entry.config],
      ["child", entry.child_handle],
    ]),
  );
}

/**
 * Decode one manifest entry.
 */
export function manifest_decoder() {
  return $decode.field(
    "instanceId",
    $decode.string,
    (instance_id) => {
      return $decode.field(
        "kind",
        $decode.string,
        (kind) => {
          return $decode.field(
            "version",
            $decode.int,
            (version) => {
              return $decode.field(
                "config",
                $wire.json_value_decoder(),
                (config) => {
                  return $decode.field(
                    "child",
                    $wire.json_value_decoder(),
                    (child_handle) => {
                      let $ = $handle.parse_handle(child_handle);
                      if ($ instanceof Ok) {
                        return $decode.success(
                          new ManifestEntry(
                            instance_id,
                            kind,
                            version,
                            config,
                            child_handle,
                          ),
                        );
                      } else {
                        return $decode.failure(
                          new ManifestEntry(
                            instance_id,
                            kind,
                            version,
                            config,
                            child_handle,
                          ),
                          "ChildHandle",
                        );
                      }
                    },
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
 * Parse one manifest JSON value.
 */
export function decode_manifest(value) {
  return $json.parse($json.to_string(value), manifest_decoder());
}

function encode_port_ref(ref) {
  return $json.object(
    toList([
      ["instanceId", $json.string(ref.instance_id)],
      ["portId", $json.string(ref.port_id)],
    ]),
  );
}

/**
 * Encode one stored port connection.
 */
export function encode_connection(connection) {
  return $json.object(
    toList([
      ["id", $json.string(connection.id)],
      ["source", encode_port_ref(connection.source)],
      ["target", encode_port_ref(connection.target)],
    ]),
  );
}

function port_ref_decoder() {
  return $decode.field(
    "instanceId",
    $decode.string,
    (instance_id) => {
      return $decode.field(
        "portId",
        $decode.string,
        (port_id) => {
          return $decode.success(new $port_graph.PortRef(instance_id, port_id));
        },
      );
    },
  );
}

/**
 * Decode one stored port connection.
 */
export function connection_decoder() {
  return $decode.field(
    "id",
    $decode.string,
    (id) => {
      return $decode.field(
        "source",
        port_ref_decoder(),
        (source) => {
          return $decode.field(
            "target",
            port_ref_decoder(),
            (target) => {
              return $decode.success(
                new $port_graph.Connection(id, source, target),
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Parse one connection JSON value.
 */
export function decode_connection(value) {
  return $json.parse($json.to_string(value), connection_decoder());
}

function ports_for(entries, catalog, instance_id) {
  return $result.try$(
    $list.find(
      entries,
      (entry) => { return entry.instance_id === instance_id; },
    ),
    (entry) => {
      return $result.try$(
        (() => {
          let _pipe = $component.find(catalog, entry.kind, entry.version);
          return $result.replace_error(_pipe, undefined);
        })(),
        (descriptor) => {
          return $result.try$(
            (() => {
              let _pipe = $component.validate_config(descriptor, entry.config);
              return $result.replace_error(_pipe, undefined);
            })(),
            (_) => { return new Ok($component.ports(descriptor)); },
          );
        },
      );
    },
  );
}

function partition_results(values) {
  let $ = $list.fold(
    values,
    [$List$Empty$const, $List$Empty$const],
    (acc, value) => {
      if (value instanceof Ok) {
        let ok = value[0];
        return [listPrepend(ok, acc[0]), acc[1]];
      } else {
        let error = value[0];
        return [acc[0], listPrepend(error, acc[1])];
      }
    },
  );
  let oks = $[0];
  let errors = $[1];
  return [$list.reverse(oks), $list.reverse(errors)];
}

function valid_connections(raw) {
  let outcomes = $list.index_map(
    raw,
    (value, index) => {
      let _pipe = decode_connection(value);
      return $result.map_error(
        _pipe,
        (reason) => { return new InvalidConnection(index, reason); },
      );
    },
  );
  return partition_results(outcomes);
}

function decode_string(value) {
  return $json.parse($json.to_string(value), $decode.string);
}

function effective_layout(raw, entries) {
  let _block;
  let _pipe = entries;
  let _pipe$1 = $list.map(_pipe, (entry) => { return entry.instance_id; });
  _block = $set.from_list(_pipe$1);
  let known = _block;
  let initial = [$List$Empty$const, $List$Empty$const, $set.new$()];
  let _block$1;
  let _pipe$2 = raw;
  let _pipe$3 = $list.index_map(
    _pipe$2,
    (value, index) => { return [index, value]; },
  );
  _block$1 = $list.fold(
    _pipe$3,
    initial,
    (state, item) => {
      let $1 = decode_string(item[1]);
      if ($1 instanceof Ok) {
        let id = $1[0];
        let $2 = $set.contains(known, id);
        let $3 = $set.contains(state[2], id);
        if ($2) {
          if ($3) {
            return [
              state[0],
              listPrepend(new DuplicateLayout(id), state[1]),
              state[2],
            ];
          } else {
            return [
              listPrepend(id, state[0]),
              state[1],
              $set.insert(state[2], id),
            ];
          }
        } else {
          return [
            state[0],
            listPrepend(new UnknownLayout(id), state[1]),
            state[2],
          ];
        }
      } else {
        let reason = $1[0];
        return [
          state[0],
          listPrepend(new InvalidLayout(item[0], reason), state[1]),
          state[2],
        ];
      }
    },
  );
  let $ = _block$1;
  let layout$1 = $[0];
  let diagnostics$1 = $[1];
  return [$list.reverse(layout$1), $list.reverse(diagnostics$1)];
}

function valid_manifest(stored) {
  let outcomes = $list.map(
    stored,
    (item) => {
      let $ = item.decoded;
      if ($ instanceof Ok) {
        let entry = $[0];
        if (entry.instance_id !== item.key) {
          return new Error(new ManifestIdMismatch(item.key, entry.instance_id));
        } else {
          return $;
        }
      } else {
        let reason = $[0];
        return new Error(new InvalidManifest(item.key, reason));
      }
    },
  );
  return partition_results(outcomes);
}

/**
 * Derive one effective workspace view without changing stored values.
 */
export function snapshot(raw_manifest, raw_layout, raw_connections, catalog) {
  let stored_manifest$1 = $list.map(
    raw_manifest,
    (item) => {
      return new StoredManifestEntry(item[0], item[1], decode_manifest(item[1]));
    },
  );
  let $ = valid_manifest(stored_manifest$1);
  let entries = $[0];
  let manifest_diagnostics = $[1];
  let $1 = effective_layout(raw_layout, entries);
  let layout$1 = $1[0];
  let layout_diagnostics = $1[1];
  let $2 = valid_connections(raw_connections);
  let stored_connections = $2[0];
  let connection_diagnostics = $2[1];
  let ports_for$1 = (instance_id) => {
    return ports_for(entries, catalog, instance_id);
  };
  let graph$1 = $port_graph.effective(stored_connections, ports_for$1);
  let _block;
  let _pipe = $port_graph.errors(graph$1);
  _block = $list.map(_pipe, (var0) => { return new InvalidGraph(var0); });
  let graph_diagnostics = _block;
  return new Snapshot(
    stored_manifest$1,
    entries,
    raw_layout,
    layout$1,
    raw_connections,
    stored_connections,
    graph$1,
    $list.flatten(
      toList([
        manifest_diagnostics,
        layout_diagnostics,
        connection_diagnostics,
        graph_diagnostics,
      ]),
    ),
  );
}

/**
 * The valid, key-matched manifest entries.
 */
export function manifest_entries(snapshot) {
  return snapshot.entries;
}

/**
 * The raw manifest values and their decode results.
 */
export function stored_manifest(snapshot) {
  return snapshot.manifest;
}

/**
 * The effective layout.
 */
export function layout(snapshot) {
  return snapshot.layout;
}

/**
 * The stored layout values, including invalid and duplicate values.
 */
export function raw_layout(snapshot) {
  return snapshot.raw_layout;
}

/**
 * The effective connection graph.
 */
export function graph(snapshot) {
  return snapshot.graph;
}

/**
 * The stored connection values, including values that did not decode.
 */
export function raw_connections(snapshot) {
  return snapshot.raw_connections;
}

/**
 * All diagnostics found while deriving the snapshot.
 */
export function diagnostics(snapshot) {
  return snapshot.diagnostics;
}

/**
 * Prepare every stored manifest entry against a local catalog.
 */
export function prepare(snapshot, catalog, resolve_child) {
  return $list.map(
    snapshot.manifest,
    (stored) => {
      let $ = stored.decoded;
      if ($ instanceof Ok) {
        let entry = $[0];
        if (entry.instance_id !== stored.key) {
          return new Failed(stored.key, new StoredIdMismatch(entry.instance_id));
        } else {
          let entry = $[0];
          let $1 = $component.find(catalog, entry.kind, entry.version);
          if ($1 instanceof Ok) {
            let descriptor = $1[0];
            let $2 = $component.validate_config(descriptor, entry.config);
            if ($2 instanceof Ok) {
              let $3 = resolve_child(entry.child_handle);
              if ($3 instanceof Ok) {
                let child = $3[0];
                return new Prepared(entry, child);
              } else {
                let reason = $3[0];
                return new Loading(entry, reason);
              }
            } else {
              let reason = $2[0];
              return new Failed(
                entry.instance_id,
                new InvalidComponentConfig(reason),
              );
            }
          } else {
            let reason = $1[0];
            return new Unavailable(entry, reason);
          }
        }
      } else {
        let reason = $[0];
        return new Failed(stored.key, new InvalidStoredManifest(reason));
      }
    },
  );
}

function first_raw_layout_index(raw, instance_id) {
  let _pipe = raw;
  let _pipe$1 = $list.index_map(
    _pipe,
    (value, index) => {
      let $ = decode_string(value);
      if ($ instanceof Ok) {
        let id = $[0];
        if (id === instance_id) {
          return new Ok(index);
        } else {
          return new Error(undefined);
        }
      } else {
        return new Error(undefined);
      }
    },
  );
  let _pipe$2 = $result.values(_pipe$1);
  return $list.first(_pipe$2);
}

function value_at(values, index) {
  let _pipe = values;
  let _pipe$1 = $list.drop(_pipe, index);
  return $list.first(_pipe$1);
}

function remove_indexes(values, indexes) {
  let _pipe = values;
  let _pipe$1 = $list.index_map(
    _pipe,
    (value, index) => { return [index, value]; },
  );
  let _pipe$2 = $list.filter(
    _pipe$1,
    (item) => { return !$list.contains(indexes, item[0]); },
  );
  return $list.map(_pipe$2, (item) => { return item[1]; });
}

function descending(indexes) {
  let _pipe = indexes;
  let _pipe$1 = $list.sort(_pipe, $int.compare);
  return $list.reverse(_pipe$1);
}

function duplicate_raw_layout_indexes(raw, instance_id) {
  let _block;
  let _pipe = raw;
  let _pipe$1 = $list.index_map(
    _pipe,
    (value, index) => { return [index, value]; },
  );
  _block = $list.fold(
    _pipe$1,
    [false, $List$Empty$const],
    (state, item) => {
      let $1 = decode_string(item[1]);
      if ($1 instanceof Ok) {
        let id = $1[0];
        if (id === instance_id) {
          let $2 = state[0];
          if ($2) {
            return [true, listPrepend(item[0], state[1])];
          } else {
            return [true, state[1]];
          }
        } else {
          return state;
        }
      } else {
        return state;
      }
    },
  );
  let $ = _block;
  let indexes = $[1];
  return descending(indexes);
}

function find_index(values, wanted) {
  let _pipe = values;
  let _pipe$1 = $list.index_map(
    _pipe,
    (value, index) => {
      let $ = value === wanted;
      if ($) {
        return new Ok(index);
      } else {
        return new Error(undefined);
      }
    },
  );
  let _pipe$2 = $result.values(_pipe$1);
  return $list.first(_pipe$2);
}

/**
 * Plan a move by effective layout index.
 */
export function plan_move(snapshot, instance_id, to_index) {
  let $ = (to_index < 0) || (to_index >= $list.length(snapshot.layout));
  if ($) {
    return new Error(undefined);
  } else {
    return $result.try$(
      find_index(snapshot.layout, instance_id),
      (from_effective) => {
        let removal_indexes = duplicate_raw_layout_indexes(
          snapshot.raw_layout,
          instance_id,
        );
        let normalized = remove_indexes(snapshot.raw_layout, removal_indexes);
        let $1 = first_raw_layout_index(normalized, instance_id);
        let from_raw;
        if ($1 instanceof Ok) {
          from_raw = $1[0];
        } else {
          throw makeError(
            "let_assert",
            FILEPATH,
            "watershed/workspace",
            338,
            "plan_move",
            "Pattern match failed, no pattern matched the value.",
            {
              value: $1,
              start: 10769,
              end: 10842,
              pattern_start: 10780,
              pattern_end: 10792
            }
          )
        }
        let $2 = from_effective === to_index;
        if ($2) {
          return new Ok(new Move(removal_indexes, from_raw, from_raw));
        } else {
          let $3 = value_at(snapshot.layout, to_index);
          let target_id;
          if ($3 instanceof Ok) {
            target_id = $3[0];
          } else {
            throw makeError(
              "let_assert",
              FILEPATH,
              "watershed/workspace",
              342,
              "plan_move",
              "Pattern match failed, no pattern matched the value.",
              {
                value: $3,
                start: 10974,
                end: 11036,
                pattern_start: 10985,
                pattern_end: 10998
              }
            )
          }
          let $4 = first_raw_layout_index(normalized, target_id);
          let to_raw;
          if ($4 instanceof Ok) {
            to_raw = $4[0];
          } else {
            throw makeError(
              "let_assert",
              FILEPATH,
              "watershed/workspace",
              343,
              "plan_move",
              "Pattern match failed, no pattern matched the value.",
              {
                value: $4,
                start: 11047,
                end: 11116,
                pattern_start: 11058,
                pattern_end: 11068
              }
            )
          }
          return new Ok(new Move(removal_indexes, from_raw, to_raw));
        }
      },
    );
  }
}

/**
 * The raw layout indexes that name one instance, highest first.
 */
export function layout_removal_indices(snapshot, instance_id) {
  let _pipe = snapshot.raw_layout;
  let _pipe$1 = $list.index_map(
    _pipe,
    (value, index) => {
      let $ = decode_string(value);
      if ($ instanceof Ok) {
        let id = $[0];
        if (id === instance_id) {
          return new Ok(index);
        } else {
          return new Error(undefined);
        }
      } else {
        return new Error(undefined);
      }
    },
  );
  let _pipe$2 = $result.values(_pipe$1);
  return descending(_pipe$2);
}

/**
 * The raw connection indexes that carry one connection ID, highest first.
 */
export function connection_id_removal_indices(snapshot, connection_id) {
  let _pipe = snapshot.raw_connections;
  let _pipe$1 = $list.index_map(
    _pipe,
    (value, index) => {
      let $ = decode_connection(value);
      if ($ instanceof Ok) {
        let connection = $[0];
        if (connection.id === connection_id) {
          return new Ok(index);
        } else {
          return new Error(undefined);
        }
      } else {
        return new Error(undefined);
      }
    },
  );
  let _pipe$2 = $result.values(_pipe$1);
  return descending(_pipe$2);
}

/**
 * The raw connection indexes incident to one instance, highest first.
 */
export function instance_connection_indices(snapshot, instance_id) {
  let _pipe = snapshot.raw_connections;
  let _pipe$1 = $list.index_map(
    _pipe,
    (value, index) => {
      let $ = decode_connection(value);
      if ($ instanceof Ok) {
        let connection = $[0];
        if (
          (connection.source.instance_id === instance_id) || (connection.target.instance_id === instance_id)
        ) {
          return new Ok(index);
        } else {
          return new Error(undefined);
        }
      } else {
        return new Error(undefined);
      }
    },
  );
  let _pipe$2 = $result.values(_pipe$1);
  return descending(_pipe$2);
}

function graph_error_id(error) {
  if (error instanceof $port_graph.DuplicateConnection) {
    let id = error.connection_id;
    return id;
  } else if (error instanceof $port_graph.UnknownInstance) {
    let id = error.connection_id;
    return id;
  } else if (error instanceof $port_graph.UnknownPort) {
    let id = error.connection_id;
    return id;
  } else if (error instanceof $port_graph.WrongDirection) {
    let id = error.connection_id;
    return id;
  } else if (error instanceof $port_graph.SchemaMismatch) {
    let id = error.connection_id;
    return id;
  } else {
    let id = error.connection_id;
    return id;
  }
}

/**
 * Check a connection against the current effective graph.
 */
export function validate_connection(snapshot, candidate, catalog) {
  let ports_for$1 = (instance_id) => {
    return ports_for(snapshot.entries, catalog, instance_id);
  };
  let candidate_graph = $port_graph.effective(
    $list.append(snapshot.stored_connections, toList([candidate])),
    ports_for$1,
  );
  let _block;
  let _pipe = $port_graph.connections(candidate_graph);
  _block = $list.map(_pipe, (connection) => { return connection.id; });
  let accepted_ids = _block;
  let $ = $list.contains(accepted_ids, candidate.id);
  if ($) {
    let _block$1;
    let _pipe$1 = $port_graph.connections(snapshot.graph);
    _block$1 = $list.find(
      _pipe$1,
      (connection) => { return !$list.contains(accepted_ids, connection.id); },
    );
    let displaced = _block$1;
    if (displaced instanceof Ok) {
      let connection = displaced[0];
      return new Error(new DisplacesConnection(connection.id));
    } else {
      return new Ok(undefined);
    }
  } else {
    let $1 = $list.find(
      $port_graph.errors(candidate_graph),
      (error) => { return graph_error_id(error) === candidate.id; },
    );
    if ($1 instanceof Ok) {
      let reason = $1[0];
      return new Error(new RejectedConnection(reason));
    } else {
      return new Error(
        new RejectedConnection(new $port_graph.Cycle(candidate.id)),
      );
    }
  }
}

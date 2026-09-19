/// <reference types="./workspace_js.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";
import * as $watershed from "../watershed.mjs";
import * as $component from "../watershed/component.mjs";
import * as $port_graph from "../watershed/port_graph.mjs";
import * as $schema from "../watershed/schema.mjs";
import { child_key } from "../watershed/schema.mjs";
import * as $workspace from "../watershed/workspace.mjs";

export class InvalidInstanceId extends $CustomType {}
export const WorkspaceError$InvalidInstanceId$const = new InvalidInstanceId();
export const WorkspaceError$InvalidInstanceId = () =>
  WorkspaceError$InvalidInstanceId$const;
export const WorkspaceError$isInvalidInstanceId = (value) =>
  value instanceof InvalidInstanceId;

export class DuplicateInstance extends $CustomType {
  constructor(instance_id) {
    super();
    this.instance_id = instance_id;
  }
}
export const WorkspaceError$DuplicateInstance = (instance_id) =>
  new DuplicateInstance(instance_id);
export const WorkspaceError$isDuplicateInstance = (value) =>
  value instanceof DuplicateInstance;
export const WorkspaceError$DuplicateInstance$instance_id = (value) =>
  value.instance_id;
export const WorkspaceError$DuplicateInstance$0 = (value) => value.instance_id;

export class InvalidMove extends $CustomType {
  constructor(instance_id, to_index) {
    super();
    this.instance_id = instance_id;
    this.to_index = to_index;
  }
}
export const WorkspaceError$InvalidMove = (instance_id, to_index) =>
  new InvalidMove(instance_id, to_index);
export const WorkspaceError$isInvalidMove = (value) =>
  value instanceof InvalidMove;
export const WorkspaceError$InvalidMove$instance_id = (value) =>
  value.instance_id;
export const WorkspaceError$InvalidMove$0 = (value) => value.instance_id;
export const WorkspaceError$InvalidMove$to_index = (value) => value.to_index;
export const WorkspaceError$InvalidMove$1 = (value) => value.to_index;

export class UnsupportedComponent extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const WorkspaceError$UnsupportedComponent = (reason) =>
  new UnsupportedComponent(reason);
export const WorkspaceError$isUnsupportedComponent = (value) =>
  value instanceof UnsupportedComponent;
export const WorkspaceError$UnsupportedComponent$reason = (value) =>
  value.reason;
export const WorkspaceError$UnsupportedComponent$0 = (value) => value.reason;

export class InvalidComponentConfig extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const WorkspaceError$InvalidComponentConfig = (reason) =>
  new InvalidComponentConfig(reason);
export const WorkspaceError$isInvalidComponentConfig = (value) =>
  value instanceof InvalidComponentConfig;
export const WorkspaceError$InvalidComponentConfig$reason = (value) =>
  value.reason;
export const WorkspaceError$InvalidComponentConfig$0 = (value) => value.reason;

export class ConnectionRejected extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const WorkspaceError$ConnectionRejected = (reason) =>
  new ConnectionRejected(reason);
export const WorkspaceError$isConnectionRejected = (value) =>
  value instanceof ConnectionRejected;
export const WorkspaceError$ConnectionRejected$reason = (value) => value.reason;
export const WorkspaceError$ConnectionRejected$0 = (value) => value.reason;

export class StorageError extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const WorkspaceError$StorageError = (reason) => new StorageError(reason);
export const WorkspaceError$isStorageError = (value) =>
  value instanceof StorageError;
export const WorkspaceError$StorageError$reason = (value) => value.reason;
export const WorkspaceError$StorageError$0 = (value) => value.reason;

class Workspace extends $CustomType {
  constructor(document, map, manifest, layout, connections) {
    super();
    this.document = document;
    this.map = map;
    this.manifest = manifest;
    this.layout = layout;
    this.connections = connections;
  }
}

class Subscription extends $CustomType {
  constructor(manifest, layout, connections) {
    super();
    this.manifest = manifest;
    this.layout = layout;
    this.connections = connections;
  }
}

function require(value, missing) {
  if (value instanceof Ok) {
    let $ = value[0];
    if ($ instanceof Some) {
      let inner = $[0];
      return new Ok(inner);
    } else {
      return new Error(new StorageError(missing));
    }
  } else {
    let reason = value[0];
    return new Error(new StorageError(reason));
  }
}

/**
 * Resolve the manifest map and the layout and connection sequences that an
 * already-resolved workspace child carries.
 * 
 * @ignore
 */
function open(document, map) {
  return $result.try$(
    (() => {
      let _pipe = $watershed.resolve_map_field(
        document,
        map,
        $workspace.manifest_field(),
      );
      return require(_pipe, "workspace manifest is missing");
    })(),
    (manifest) => {
      return $result.try$(
        (() => {
          let _pipe = $watershed.resolve_sequence_field(
            document,
            map,
            $workspace.layout_field(),
          );
          return require(_pipe, "workspace layout is missing");
        })(),
        (layout) => {
          return $result.try$(
            (() => {
              let _pipe = $watershed.resolve_sequence_field(
                document,
                map,
                $workspace.connections_field(),
              );
              return require(_pipe, "workspace connections are missing");
            })(),
            (connections) => {
              return new Ok(
                new Workspace(document, map, manifest, layout, connections),
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Build a complete, detached workspace subtree and attach it in one write.
 * 
 * @ignore
 */
function create(document, root, field) {
  return $result.try$(
    (() => {
      let _pipe = $watershed.create_map(document);
      return $result.map_error(
        _pipe,
        (var0) => { return new StorageError(var0); },
      );
    })(),
    (raw_map) => {
      let map = $watershed.typed(raw_map);
      return $result.try$(
        (() => {
          let _pipe = $watershed.create_map(document);
          return $result.map_error(
            _pipe,
            (var0) => { return new StorageError(var0); },
          );
        })(),
        (manifest) => {
          return $result.try$(
            (() => {
              let _pipe = $watershed.create_sequence(document);
              return $result.map_error(
                _pipe,
                (var0) => { return new StorageError(var0); },
              );
            })(),
            (layout) => {
              return $result.try$(
                (() => {
                  let _pipe = $watershed.create_sequence(document);
                  return $result.map_error(
                    _pipe,
                    (var0) => { return new StorageError(var0); },
                  );
                })(),
                (connections) => {
                  $watershed.set_map_field(
                    map,
                    $workspace.manifest_field(),
                    manifest,
                  );
                  $watershed.set_sequence_field(
                    map,
                    $workspace.layout_field(),
                    layout,
                  );
                  $watershed.set_sequence_field(
                    map,
                    $workspace.connections_field(),
                    connections,
                  );
                  $watershed.set_child(root, field, map);
                  return new Ok(
                    new Workspace(document, map, manifest, layout, connections),
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
 * Adopt an existing workspace or create a complete workspace subtree.
 *
 * When the workspace child is absent, the function builds the whole
 * subtree — the workspace map, the manifest map, and the layout and
 * connection sequences — while every channel is still detached, and then
 * attaches all of it with the one write that stores the workspace child on
 * `root`. Recursive handle discovery attaches the nested channels together
 * with the workspace map, so there is no window with a partially attached
 * topology, and this path never waits on a timer.
 *
 * When the workspace child is already present, the function adopts it. It
 * resolves the child through the existing, retrying `ensure_child`, because
 * a handle that a remote peer just wrote can still be mid-attach, and then
 * it resolves the three channels directly: a workspace that this function
 * created always carries all three together.
 *
 * A cold-start race has the same semantics as before: two callers can
 * converge on one root handle, but a later remote write to the root field
 * can still replace the handle that an earlier caller received.
 */
export function ensure(document, root, field, done) {
  let $ = $watershed.has($watershed.untyped(root), child_key(field));
  if ($) {
    return $watershed.ensure_child(
      document,
      root,
      field,
      (result) => {
        if (result instanceof Ok) {
          let map = result[0];
          return done(open(document, map));
        } else {
          let reason = result[0];
          return done(new Error(new StorageError(reason)));
        }
      },
    );
  } else {
    return done(create(document, root, field));
  }
}

/**
 * Resolve an existing workspace without changing it.
 */
export function resolve(document, root, field) {
  return $result.try$(
    (() => {
      let _pipe = $watershed.resolve_child(document, root, field);
      return require(_pipe, "workspace child is missing");
    })(),
    (map) => { return open(document, map); },
  );
}

/**
 * Read the effective workspace state.
 */
export function read(store, catalog) {
  return $workspace.snapshot(
    $watershed.entries(store.manifest),
    $watershed.sequence_values(store.layout),
    $watershed.sequence_values(store.connections),
    catalog,
  );
}

/**
 * Prepare stored instances for the later runtime layer.
 */
export function prepare(store, catalog) {
  return $workspace.prepare(
    read(store, catalog),
    catalog,
    (child_handle) => {
      return $watershed.resolve(store.document, child_handle);
    },
  );
}

/**
 * Observe manifest, layout, and connection changes.
 *
 * The callback identifies no individual channel because a runtime must read
 * one fresh effective snapshot after any of the three changes.
 */
export function subscribe(store, changed) {
  return new Subscription(
    $watershed.subscribe(store.manifest, (_) => { return changed(); }),
    $watershed.subscribe_sequence(store.layout, (_) => { return changed(); }),
    $watershed.subscribe_sequence(
      store.connections,
      (_) => { return changed(); },
    ),
  );
}

/**
 * Stop observing one workspace. Repeated calls are safe.
 */
export function unsubscribe(subscription) {
  $watershed.unsubscribe(subscription.manifest);
  $watershed.unsubscribe(subscription.layout);
  return $watershed.unsubscribe(subscription.connections);
}

/**
 * Add one initialized instance and append it to the layout.
 *
 * `initialize` runs while the instance map is detached. Its channel handles
 * are therefore part of the subtree before the manifest publishes the
 * instance handle.
 */
export function add_instance_with(
  store,
  catalog,
  instance_id,
  kind,
  version,
  config,
  initialize
) {
  let $ = $string.is_empty(instance_id);
  let $1 = $watershed.has(store.manifest, instance_id);
  if ($) {
    return new Error(WorkspaceError$InvalidInstanceId$const);
  } else if ($1) {
    return new Error(new DuplicateInstance(instance_id));
  } else {
    return $result.try$(
      (() => {
        let _pipe = $component.find(catalog, kind, version);
        return $result.map_error(
          _pipe,
          (var0) => { return new UnsupportedComponent(var0); },
        );
      })(),
      (descriptor) => {
        return $result.try$(
          (() => {
            let _pipe = $component.validate_config(descriptor, config);
            return $result.map_error(
              _pipe,
              (var0) => { return new InvalidComponentConfig(var0); },
            );
          })(),
          (_) => {
            return $result.try$(
              (() => {
                let _pipe = $watershed.create_map(store.document);
                return $result.map_error(
                  _pipe,
                  (var0) => { return new StorageError(var0); },
                );
              })(),
              (child) => {
                return $result.try$(
                  (() => {
                    let _pipe = initialize(store.document, child);
                    return $result.map_error(
                      _pipe,
                      (var0) => { return new StorageError(var0); },
                    );
                  })(),
                  (_) => {
                    let entry = new $workspace.ManifestEntry(
                      instance_id,
                      kind,
                      version,
                      config,
                      $watershed.handle_of(child),
                    );
                    $watershed.set(
                      store.manifest,
                      instance_id,
                      $workspace.encode_manifest(entry),
                    );
                    return $result.try$(
                      (() => {
                        let _pipe = $watershed.sequence_insert(
                          store.layout,
                          $watershed.sequence_length(store.layout),
                          $json.string(instance_id),
                        );
                        return $result.map_error(
                          _pipe,
                          (var0) => { return new StorageError(var0); },
                        );
                      })(),
                      (_) => { return new Ok(child); },
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
}

/**
 * Add one instance and append it to the layout.
 */
export function add_instance(store, catalog, instance_id, kind, version, config) {
  return add_instance_with(
    store,
    catalog,
    instance_id,
    kind,
    version,
    config,
    (_, _1) => { return new Ok(undefined); },
  );
}

function delete_indices(sequence, indices) {
  return $list.try_fold(
    indices,
    undefined,
    (_, index) => {
      let _pipe = $watershed.sequence_delete(sequence, index);
      return $result.map_error(
        _pipe,
        (var0) => { return new StorageError(var0); },
      );
    },
  );
}

/**
 * Move one instance to an effective layout index.
 */
export function move_instance(store, catalog, instance_id, to_index) {
  let $ = $workspace.plan_move(read(store, catalog), instance_id, to_index);
  if ($ instanceof Ok) {
    let remove_indexes = $[0].remove_indexes;
    let from_index = $[0].from_index;
    let target_index = $[0].to_index;
    return $result.try$(
      delete_indices(store.layout, remove_indexes),
      (_) => {
        let $1 = from_index === target_index;
        if ($1) {
          return new Ok(undefined);
        } else {
          let _pipe = $watershed.sequence_move(
            store.layout,
            from_index,
            target_index,
          );
          return $result.map_error(
            _pipe,
            (var0) => { return new StorageError(var0); },
          );
        }
      },
    );
  } else {
    return new Error(new InvalidMove(instance_id, to_index));
  }
}

/**
 * Validate and append one port connection.
 */
export function add_connection(store, catalog, connection) {
  return $result.try$(
    (() => {
      let _pipe = $workspace.validate_connection(
        read(store, catalog),
        connection,
        catalog,
      );
      return $result.map_error(
        _pipe,
        (var0) => { return new ConnectionRejected(var0); },
      );
    })(),
    (_) => {
      let _pipe = $watershed.sequence_insert(
        store.connections,
        $watershed.sequence_length(store.connections),
        $workspace.encode_connection(connection),
      );
      return $result.map_error(
        _pipe,
        (var0) => { return new StorageError(var0); },
      );
    },
  );
}

/**
 * Remove every stored occurrence of one connection ID.
 */
export function remove_connection(store, catalog, connection_id) {
  return delete_indices(
    store.connections,
    $workspace.connection_id_removal_indices(
      read(store, catalog),
      connection_id,
    ),
  );
}

/**
 * Remove one instance from workspace reachability.
 *
 * The attached child map remains readable through a handle retained before
 * this operation.
 */
export function delete_instance(store, catalog, instance_id) {
  let snapshot = read(store, catalog);
  return $result.try$(
    delete_indices(
      store.layout,
      $workspace.layout_removal_indices(snapshot, instance_id),
    ),
    (_) => {
      return $result.try$(
        delete_indices(
          store.connections,
          $workspace.instance_connection_indices(snapshot, instance_id),
        ),
        (_) => {
          $watershed.delete$(store.manifest, instance_id);
          return new Ok(undefined);
        },
      );
    },
  );
}

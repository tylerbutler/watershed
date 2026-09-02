//// Persisted state and effective views for a component workspace.
////
//// A workspace owns a manifest map, a layout sequence, and a connection
//// sequence. Target-specific adapters create and edit those channels. This
//// module decodes their values and derives the state that a host can use.
////
//// Reads do not change stored data. Invalid values remain in their channels
//// and appear as diagnostics.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/set
import watershed/component
import watershed/handle
import watershed/port
import watershed/port_graph
import watershed/schema
import watershed/wire

/// The schema tag for the workspace child map.
pub type WorkspaceSchema

/// The workspace manifest.
pub fn manifest_field() -> schema.ChannelField(
  WorkspaceSchema,
  schema.MapChannel,
) {
  schema.channel_field("manifest")
}

/// The ordered component instance IDs.
pub fn layout_field() -> schema.ChannelField(
  WorkspaceSchema,
  schema.SequenceChannel,
) {
  schema.channel_field("layout")
}

/// The stored component port connections.
pub fn connections_field() -> schema.ChannelField(
  WorkspaceSchema,
  schema.SequenceChannel,
) {
  schema.channel_field("connections")
}

/// One component instance in the manifest.
pub type ManifestEntry {
  ManifestEntry(
    instance_id: String,
    kind: String,
    version: Int,
    config: Json,
    child_handle: Json,
  )
}

/// A raw manifest value and its decode result.
pub type StoredManifestEntry {
  StoredManifestEntry(
    key: String,
    raw: Json,
    decoded: Result(ManifestEntry, json.DecodeError),
  )
}

/// A problem found while reading stored workspace data.
pub type Diagnostic {
  InvalidManifest(key: String, reason: json.DecodeError)
  ManifestIdMismatch(key: String, encoded_id: String)
  InvalidLayout(index: Int, reason: json.DecodeError)
  DuplicateLayout(instance_id: String)
  UnknownLayout(instance_id: String)
  InvalidConnection(index: Int, reason: json.DecodeError)
  InvalidGraph(error: port_graph.GraphError)
}

/// Local preparation state before component runtime startup.
pub type PreparationState(subtree) {
  /// The entry is valid, but its child map is not available yet.
  Loading(entry: ManifestEntry, reason: String)
  /// The descriptor, config, and child map are available.
  Prepared(entry: ManifestEntry, subtree: subtree)
  /// The local catalog does not support the stored kind and version.
  Unavailable(entry: ManifestEntry, reason: component.LookupError)
  /// The stored entry or component config is invalid.
  Failed(instance_id: String, reason: PreparationError)
}

/// A reason an instance could not be prepared.
pub type PreparationError {
  InvalidStoredManifest(reason: json.DecodeError)
  StoredIdMismatch(encoded_id: String)
  InvalidComponentConfig(reason: component.ComponentError)
}

/// A reason a connection cannot be appended.
pub type ConnectionError {
  RejectedConnection(reason: port_graph.GraphError)
  DisplacesConnection(connection_id: String)
}

/// A move in the raw layout sequence.
pub type Move {
  Move(remove_indexes: List(Int), from_index: Int, to_index: Int)
}

/// The effective view of three raw workspace channels.
pub opaque type Snapshot {
  Snapshot(
    manifest: List(StoredManifestEntry),
    entries: List(ManifestEntry),
    raw_layout: List(Json),
    layout: List(String),
    raw_connections: List(Json),
    stored_connections: List(port_graph.Connection),
    graph: port_graph.EffectiveGraph,
    diagnostics: List(Diagnostic),
  )
}

/// Encode one manifest entry.
pub fn encode_manifest(entry: ManifestEntry) -> Json {
  json.object([
    #("instanceId", json.string(entry.instance_id)),
    #("kind", json.string(entry.kind)),
    #("version", json.int(entry.version)),
    #("config", entry.config),
    #("child", entry.child_handle),
  ])
}

/// Decode one manifest entry.
pub fn manifest_decoder() -> Decoder(ManifestEntry) {
  use instance_id <- decode.field("instanceId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use version <- decode.field("version", decode.int)
  use config <- decode.field("config", wire.json_value_decoder())
  use child_handle <- decode.field("child", wire.json_value_decoder())
  case handle.parse_handle(child_handle) {
    Ok(_) ->
      decode.success(ManifestEntry(
        instance_id: instance_id,
        kind: kind,
        version: version,
        config: config,
        child_handle: child_handle,
      ))
    Error(Nil) ->
      decode.failure(
        ManifestEntry(instance_id, kind, version, config, child_handle),
        "ChildHandle",
      )
  }
}

/// Parse one manifest JSON value.
pub fn decode_manifest(value: Json) -> Result(ManifestEntry, json.DecodeError) {
  json.parse(json.to_string(value), manifest_decoder())
}

/// Encode one stored port connection.
pub fn encode_connection(connection: port_graph.Connection) -> Json {
  json.object([
    #("id", json.string(connection.id)),
    #("source", encode_port_ref(connection.source)),
    #("target", encode_port_ref(connection.target)),
  ])
}

fn encode_port_ref(ref: port_graph.PortRef) -> Json {
  json.object([
    #("instanceId", json.string(ref.instance_id)),
    #("portId", json.string(ref.port_id)),
  ])
}

/// Decode one stored port connection.
pub fn connection_decoder() -> Decoder(port_graph.Connection) {
  use id <- decode.field("id", decode.string)
  use source <- decode.field("source", port_ref_decoder())
  use target <- decode.field("target", port_ref_decoder())
  decode.success(port_graph.Connection(id: id, source: source, target: target))
}

fn port_ref_decoder() -> Decoder(port_graph.PortRef) {
  use instance_id <- decode.field("instanceId", decode.string)
  use port_id <- decode.field("portId", decode.string)
  decode.success(port_graph.PortRef(instance_id: instance_id, port_id: port_id))
}

/// Parse one connection JSON value.
pub fn decode_connection(
  value: Json,
) -> Result(port_graph.Connection, json.DecodeError) {
  json.parse(json.to_string(value), connection_decoder())
}

/// Derive one effective workspace view without changing stored values.
pub fn snapshot(
  manifest raw_manifest: List(#(String, Json)),
  layout raw_layout: List(Json),
  connections raw_connections: List(Json),
  catalog catalog: component.Catalog(context, running),
) -> Snapshot {
  let stored_manifest =
    list.map(raw_manifest, fn(item) {
      StoredManifestEntry(item.0, item.1, decode_manifest(item.1))
    })
  let #(entries, manifest_diagnostics) = valid_manifest(stored_manifest)
  let #(layout, layout_diagnostics) = effective_layout(raw_layout, entries)
  let #(stored_connections, connection_diagnostics) =
    valid_connections(raw_connections)
  let ports_for = fn(instance_id) { ports_for(entries, catalog, instance_id) }
  let graph = port_graph.effective(stored_connections, ports_for)
  let graph_diagnostics =
    port_graph.errors(graph)
    |> list.map(InvalidGraph)

  Snapshot(
    manifest: stored_manifest,
    entries: entries,
    raw_layout: raw_layout,
    layout: layout,
    raw_connections: raw_connections,
    stored_connections: stored_connections,
    graph: graph,
    diagnostics: list.flatten([
      manifest_diagnostics,
      layout_diagnostics,
      connection_diagnostics,
      graph_diagnostics,
    ]),
  )
}

/// The valid, key-matched manifest entries.
pub fn manifest_entries(snapshot: Snapshot) -> List(ManifestEntry) {
  snapshot.entries
}

/// The raw manifest values and their decode results.
pub fn stored_manifest(snapshot: Snapshot) -> List(StoredManifestEntry) {
  snapshot.manifest
}

/// The effective layout.
pub fn layout(snapshot: Snapshot) -> List(String) {
  snapshot.layout
}

/// The stored layout values, including invalid and duplicate values.
pub fn raw_layout(snapshot: Snapshot) -> List(Json) {
  snapshot.raw_layout
}

/// The effective connection graph.
pub fn graph(snapshot: Snapshot) -> port_graph.EffectiveGraph {
  snapshot.graph
}

/// The stored connection values, including values that did not decode.
pub fn raw_connections(snapshot: Snapshot) -> List(Json) {
  snapshot.raw_connections
}

/// All diagnostics found while deriving the snapshot.
pub fn diagnostics(snapshot: Snapshot) -> List(Diagnostic) {
  snapshot.diagnostics
}

/// Prepare every stored manifest entry against a local catalog.
pub fn prepare(
  snapshot: Snapshot,
  catalog: component.Catalog(context, running),
  resolve_child: fn(Json) -> Result(subtree, String),
) -> List(PreparationState(subtree)) {
  list.map(snapshot.manifest, fn(stored) {
    case stored.decoded {
      Error(reason) -> Failed(stored.key, InvalidStoredManifest(reason))
      Ok(entry) if entry.instance_id != stored.key ->
        Failed(stored.key, StoredIdMismatch(entry.instance_id))
      Ok(entry) ->
        case component.find(catalog, entry.kind, entry.version) {
          Error(reason) -> Unavailable(entry, reason)
          Ok(descriptor) ->
            case component.validate_config(descriptor, entry.config) {
              Error(reason) ->
                Failed(entry.instance_id, InvalidComponentConfig(reason))
              Ok(Nil) ->
                case resolve_child(entry.child_handle) {
                  Ok(child) -> Prepared(entry, child)
                  Error(reason) -> Loading(entry, reason)
                }
            }
        }
    }
  })
}

/// Plan a move by effective layout index.
pub fn plan_move(
  snapshot: Snapshot,
  instance_id: String,
  to_index: Int,
) -> Result(Move, Nil) {
  case to_index < 0 || to_index >= list.length(snapshot.layout) {
    True -> Error(Nil)
    False -> {
      use from_effective <- result.try(find_index(snapshot.layout, instance_id))
      let removal_indexes =
        duplicate_raw_layout_indexes(snapshot.raw_layout, instance_id)
      let normalized = remove_indexes(snapshot.raw_layout, removal_indexes)
      let assert Ok(from_raw) = first_raw_layout_index(normalized, instance_id)
      case from_effective == to_index {
        True -> Ok(Move(removal_indexes, from_raw, from_raw))
        False -> {
          let assert Ok(target_id) = value_at(snapshot.layout, to_index)
          let assert Ok(to_raw) = first_raw_layout_index(normalized, target_id)
          Ok(Move(removal_indexes, from_raw, to_raw))
        }
      }
    }
  }
}

/// The raw layout indexes that name one instance, highest first.
pub fn layout_removal_indices(
  snapshot: Snapshot,
  instance_id: String,
) -> List(Int) {
  snapshot.raw_layout
  |> list.index_map(fn(value, index) {
    case decode_string(value) {
      Ok(id) if id == instance_id -> Ok(index)
      _ -> Error(Nil)
    }
  })
  |> result.values
  |> descending
}

/// The raw connection indexes that carry one connection ID, highest first.
pub fn connection_id_removal_indices(
  snapshot: Snapshot,
  connection_id: String,
) -> List(Int) {
  snapshot.raw_connections
  |> list.index_map(fn(value, index) {
    case decode_connection(value) {
      Ok(connection) if connection.id == connection_id -> Ok(index)
      _ -> Error(Nil)
    }
  })
  |> result.values
  |> descending
}

/// The raw connection indexes incident to one instance, highest first.
pub fn instance_connection_indices(
  snapshot: Snapshot,
  instance_id: String,
) -> List(Int) {
  snapshot.raw_connections
  |> list.index_map(fn(value, index) {
    case decode_connection(value) {
      Ok(connection)
        if connection.source.instance_id == instance_id
        || connection.target.instance_id == instance_id
      -> Ok(index)
      _ -> Error(Nil)
    }
  })
  |> result.values
  |> descending
}

/// Check a connection against the current effective graph.
pub fn validate_connection(
  snapshot: Snapshot,
  candidate: port_graph.Connection,
  catalog: component.Catalog(context, running),
) -> Result(Nil, ConnectionError) {
  let ports_for = fn(instance_id) {
    ports_for(snapshot.entries, catalog, instance_id)
  }
  let candidate_graph =
    port_graph.effective(
      list.append(snapshot.stored_connections, [candidate]),
      ports_for,
    )
  let accepted_ids =
    port_graph.connections(candidate_graph)
    |> list.map(fn(connection) { connection.id })
  case list.contains(accepted_ids, candidate.id) {
    False ->
      case
        list.find(port_graph.errors(candidate_graph), fn(error) {
          graph_error_id(error) == candidate.id
        })
      {
        Ok(reason) -> Error(RejectedConnection(reason))
        Error(Nil) -> Error(RejectedConnection(port_graph.Cycle(candidate.id)))
      }
    True -> {
      let displaced =
        port_graph.connections(snapshot.graph)
        |> list.find(fn(connection) {
          !list.contains(accepted_ids, connection.id)
        })
      case displaced {
        Ok(connection) -> Error(DisplacesConnection(connection.id))
        Error(Nil) -> Ok(Nil)
      }
    }
  }
}

fn valid_manifest(
  stored: List(StoredManifestEntry),
) -> #(List(ManifestEntry), List(Diagnostic)) {
  let outcomes =
    list.map(stored, fn(item) {
      case item.decoded {
        Error(reason) -> Error(InvalidManifest(item.key, reason))
        Ok(entry) if entry.instance_id != item.key ->
          Error(ManifestIdMismatch(item.key, entry.instance_id))
        Ok(entry) -> Ok(entry)
      }
    })
  partition_results(outcomes)
}

fn effective_layout(
  raw: List(Json),
  entries: List(ManifestEntry),
) -> #(List(String), List(Diagnostic)) {
  let known =
    entries
    |> list.map(fn(entry) { entry.instance_id })
    |> set.from_list
  let initial = #([], [], set.new())
  let #(layout, diagnostics, _) =
    raw
    |> list.index_map(fn(value, index) { #(index, value) })
    |> list.fold(initial, fn(state, item) {
      case decode_string(item.1) {
        Error(reason) -> #(
          state.0,
          [InvalidLayout(item.0, reason), ..state.1],
          state.2,
        )
        Ok(id) ->
          case set.contains(known, id), set.contains(state.2, id) {
            False, _ -> #(state.0, [UnknownLayout(id), ..state.1], state.2)
            True, True -> #(state.0, [DuplicateLayout(id), ..state.1], state.2)
            True, False -> #([id, ..state.0], state.1, set.insert(state.2, id))
          }
      }
    })
  #(list.reverse(layout), list.reverse(diagnostics))
}

fn valid_connections(
  raw: List(Json),
) -> #(List(port_graph.Connection), List(Diagnostic)) {
  let outcomes =
    list.index_map(raw, fn(value, index) {
      decode_connection(value)
      |> result.map_error(fn(reason) { InvalidConnection(index, reason) })
    })
  partition_results(outcomes)
}

fn ports_for(
  entries: List(ManifestEntry),
  catalog: component.Catalog(context, running),
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  use entry <- result.try(
    list.find(entries, fn(entry) { entry.instance_id == instance_id }),
  )
  use descriptor <- result.try(
    component.find(catalog, entry.kind, entry.version)
    |> result.replace_error(Nil),
  )
  use _ <- result.try(
    component.validate_config(descriptor, entry.config)
    |> result.replace_error(Nil),
  )
  Ok(component.ports(descriptor))
}

fn decode_string(value: Json) -> Result(String, json.DecodeError) {
  json.parse(json.to_string(value), decode.string)
}

fn first_raw_layout_index(
  raw: List(Json),
  instance_id: String,
) -> Result(Int, Nil) {
  raw
  |> list.index_map(fn(value, index) {
    case decode_string(value) {
      Ok(id) if id == instance_id -> Ok(index)
      _ -> Error(Nil)
    }
  })
  |> result.values
  |> list.first
}

fn duplicate_raw_layout_indexes(
  raw: List(Json),
  instance_id: String,
) -> List(Int) {
  let #(_, indexes) =
    raw
    |> list.index_map(fn(value, index) { #(index, value) })
    |> list.fold(#(False, []), fn(state, item) {
      case decode_string(item.1) {
        Ok(id) if id == instance_id ->
          case state.0 {
            False -> #(True, state.1)
            True -> #(True, [item.0, ..state.1])
          }
        _ -> state
      }
    })
  descending(indexes)
}

fn remove_indexes(values: List(a), indexes: List(Int)) -> List(a) {
  values
  |> list.index_map(fn(value, index) { #(index, value) })
  |> list.filter(fn(item) { !list.contains(indexes, item.0) })
  |> list.map(fn(item) { item.1 })
}

fn find_index(values: List(String), wanted: String) -> Result(Int, Nil) {
  values
  |> list.index_map(fn(value, index) {
    case value == wanted {
      True -> Ok(index)
      False -> Error(Nil)
    }
  })
  |> result.values
  |> list.first
}

fn value_at(values: List(a), index: Int) -> Result(a, Nil) {
  values
  |> list.drop(index)
  |> list.first
}

fn partition_results(values: List(Result(a, e))) -> #(List(a), List(e)) {
  let #(oks, errors) =
    list.fold(values, #([], []), fn(acc, value) {
      case value {
        Ok(ok) -> #([ok, ..acc.0], acc.1)
        Error(error) -> #(acc.0, [error, ..acc.1])
      }
    })
  #(list.reverse(oks), list.reverse(errors))
}

fn descending(indexes: List(Int)) -> List(Int) {
  indexes
  |> list.sort(int.compare)
  |> list.reverse
}

fn graph_error_id(error: port_graph.GraphError) -> String {
  case error {
    port_graph.DuplicateConnection(id)
    | port_graph.UnknownInstance(id, _)
    | port_graph.UnknownPort(id, _)
    | port_graph.WrongDirection(id, _, _)
    | port_graph.SchemaMismatch(id, _, _)
    | port_graph.Cycle(id) -> id
  }
}

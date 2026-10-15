//// Checked Fluid document summaries for the supported container profile.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import spillway/types.{type SequencedDocumentMessage}
import watershed/canonical_json
import watershed/channel
import watershed/client_id
import watershed/fluid_ids
import watershed/handle
import watershed/tree/codec
import watershed/tree/codec/summary as summary_codec
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/identifier
import watershed/tree/schema
import watershed/tree/summary as tree_summary
import watershed/tree/types as tree_types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/fluid_summary.{
  type SummaryEntry, type SummaryError, SummaryBlob, SummaryTree,
}
import watershed/wire/op as wire_op
import watershed/wire/socket
import watershed/wire/summary as summary_message
import watershed/wire/summary_blob as inspection

pub type InitialLayout {
  InitialLayout(
    stores: List(InitialDatastore),
    channels: List(InitialChannel),
    bindings: List(InitialBinding),
  )
}

pub type InitialDatastore {
  InitialDatastore(id: String, alias: Option(String))
}

pub type InitialChannel {
  InitialMap(store: String, id: String, entries: List(#(String, Json)))
  InitialTree(
    store: String,
    id: String,
    stored: schema.StoredSchema,
    root: Option(tree_types.TreeValue),
  )
}

pub type InitialBinding {
  InitialBinding(
    source_store: String,
    source_channel: String,
    key: String,
    target_store: String,
    target_channel: String,
  )
}

/// Build the supported initial container. No edit has been sequenced.
pub fn initial_tree(
  stored: schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  session: fluid_ids.SessionId,
  view_id: fluid_ids.StableId,
) -> Result(DocumentSummary, SummaryError) {
  initial_tree_with_layout(
    stored,
    initial_root,
    session,
    view_id,
    InitialLayout([], [], []),
  )
}

/// Build an initial container with declared map and tree channels.
pub fn initial_tree_with_layout(
  stored: schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  session: fluid_ids.SessionId,
  view_id: fluid_ids.StableId,
  layout: InitialLayout,
) -> Result(DocumentSummary, SummaryError) {
  use #(snapshot, compressor) <- result.try(initial_tree_snapshot(
    stored,
    initial_root,
    fluid_ids.new(session),
    view_id,
    "/.channels/A/.channels/_C",
  ))
  let code =
    json.array(
      [
        json.array(
          [
            json.string("code"),
            json.object([
              #("key", json.string("code")),
              #(
                "value",
                json.object([#("package", json.string("watershed-shared-tree"))]),
              ),
              #("approvalSequenceNumber", json.int(0)),
              #("commitSequenceNumber", json.int(0)),
              #("sequenceNumber", json.int(0)),
            ]),
          ],
          fn(value) { value },
        ),
      ],
      fn(value) { value },
    )
  let metadata =
    json.object([
      #("createContainerRuntimeVersion", json.string("3.1.0")),
      #("summaryNumber", json.int(1)),
      #("summaryFormatVersion", json.int(1)),
      #("gcFeature", json.int(3)),
      #("sessionExpiryTimeoutMs", json.int(2_592_000_000)),
      #("sweepEnabled", json.bool(False)),
      #("tombstoneTimeoutMs", json.int(3_110_400_000)),
      #("message", json.object([#("sequenceNumber", json.int(-1))])),
      #(
        "documentSchema",
        json.object([
          #("version", json.int(1)),
          #("refSeq", json.int(0)),
          #(
            "info",
            json.object([#("minVersionForCollab", json.string("2.117.0"))]),
          ),
          #(
            "runtime",
            json.object([
              #("explicitSchemaControl", json.bool(True)),
              #("idCompressorMode", json.string("on")),
              #("opGroupingEnabled", json.bool(True)),
            ]),
          ),
        ]),
      ),
    ])
  let store =
    Datastore(
      "A",
      json.object([
        #("pkg", json.string("[\"org.watershed.shared-tree.m1.bootstrap\"]")),
        #("summaryFormatVersion", json.int(2)),
        #("isRootDataStore", json.bool(True)),
      ]),
      ["org.watershed.shared-tree.m1.bootstrap"],
      [
        Channel(
          "root",
          channel.fluid_attributes(channel.MapChannel),
          channel.MapSnapshot([#("tree", handle.encode_handle("A/_C"))]),
        ),
        Channel(
          "_C",
          channel.fluid_attributes(channel.TreeChannel),
          channel.TreeSnapshot(snapshot),
        ),
      ],
    )
  let summary =
    DocumentSummary(
      0,
      0,
      metadata,
      json.array([], json.string),
      [],
      json.array([], json.string),
      code,
      [#("root", "A")],
      [store],
      Some(compressor),
      view_id,
      json.object([#("gcNodes", json.object([]))]),
      None,
      0,
      [],
    )
  use summary <- result.try(apply_initial_layout(summary, layout))
  use gc <- result.try(refresh_gc(summary))
  Ok(DocumentSummary(..summary, gc:))
}

fn initial_tree_snapshot(
  stored: schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  compressor: fluid_ids.Compressor,
  view_id: fluid_ids.StableId,
  path: String,
) -> Result(#(tree_kernel.TreeSnapshot, fluid_ids.Compressor), SummaryError) {
  use #(initial_root, compressor) <- result.try(case initial_root {
    None -> {
      use _ <- result.try(
        schema.validate_root_field(stored, None)
        |> result.map_error(fn(error) {
          fluid_summary.MalformedEntry(path, string.inspect(error))
        }),
      )
      Ok(#(None, compressor))
    }
    Some(value) -> {
      use #(value, compressor) <- result.try(
        identifier.materialize_value(stored, value, compressor)
        |> result.map_error(fn(error) {
          fluid_summary.MalformedEntry(path, string.inspect(error))
        }),
      )
      use _ <- result.try(
        schema.validate_root(stored, value)
        |> result.map_error(fn(error) {
          fluid_summary.MalformedEntry(path, string.inspect(error))
        }),
      )
      Ok(#(Some(value), compressor))
    }
  })
  // ponytail: Fragmented modules. To make an initial tree, this caller builds
  // the internal records forest.ForestData and history.HistorySnapshot. Add one
  // tree function that makes the initial snapshot.
  use snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      forest.ForestData(initial_root, [], 1),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0, []),
    )
    |> result.map_error(fn(error) {
      fluid_summary.MalformedEntry(path, string.inspect(error))
    }),
  )
  Ok(#(snapshot, compressor))
}

fn apply_initial_layout(
  summary: DocumentSummary,
  layout: InitialLayout,
) -> Result(DocumentSummary, SummaryError) {
  use summary <- result.try(
    list.try_fold(layout.stores, summary, fn(summary, definition) {
      use _ <- result.try(validate_initial_route(definition.id, "root"))
      use _ <- result.try(require(
        !list.any(summary.datastores, fn(store) { store.id == definition.id }),
        "/.channels/" <> definition.id,
        "duplicate initial datastore",
      ))
      let aliases = case definition.alias {
        None -> summary.aliases
        Some(alias) -> list.append(summary.aliases, [#(alias, definition.id)])
      }
      let store =
        Datastore(
          definition.id,
          json.object([
            #("pkg", json.string("[\"org.watershed.shared-tree.m7.graph\"]")),
            #("summaryFormatVersion", json.int(2)),
            #("isRootDataStore", json.bool(definition.alias != None)),
          ]),
          ["org.watershed.shared-tree.m7.graph"],
          [
            Channel(
              "root",
              channel.fluid_attributes(channel.MapChannel),
              channel.MapSnapshot([]),
            ),
          ],
        )
      Ok(
        DocumentSummary(
          ..summary,
          aliases: aliases,
          datastores: list.append(summary.datastores, [store]),
        ),
      )
    }),
  )
  use _ <- result.try(require(
    list.length(list.unique(list.map(summary.aliases, fn(alias) { alias.0 })))
      == list.length(summary.aliases),
    "/.aliases",
    "duplicate initial alias",
  ))
  use _ <- result.try(
    list.try_each(summary.aliases, fn(alias) {
      use _ <- result.try(validate_initial_route(alias.0, "root"))
      require(
        !list.any(summary.datastores, fn(store) { store.id == alias.0 }),
        "/.aliases/" <> alias.0,
        "initial alias conflicts with a datastore identity",
      )
    }),
  )
  use summary <- result.try(
    list.try_fold(layout.channels, summary, fn(summary, definition) {
      use _ <- result.try(validate_initial_route(
        definition.store,
        definition.id,
      ))
      let path =
        "/.channels/" <> definition.store <> "/.channels/" <> definition.id
      use #(snapshot, compressor) <- result.try(case definition {
        InitialMap(_, _, entries) ->
          Ok(#(channel.MapSnapshot(entries), summary.compressor))
        InitialTree(_, _, stored, root) -> {
          use compressor <- result.try(case summary.compressor {
            Some(compressor) -> Ok(compressor)
            None -> Error(fluid_summary.MissingEntry("/.idCompressor"))
          })
          use #(snapshot, compressor) <- result.try(initial_tree_snapshot(
            stored,
            root,
            compressor,
            summary.view_id,
            path,
          ))
          Ok(#(channel.TreeSnapshot(snapshot), Some(compressor)))
        }
      })
      let summary = DocumentSummary(..summary, compressor:)
      update_initial_channels(summary, definition.store, fn(channels) {
        use _ <- result.try(require(
          !list.any(channels, fn(item) { item.id == definition.id }),
          path,
          "duplicate initial channel",
        ))
        Ok(
          list.append(channels, [
            Channel(
              definition.id,
              channel.fluid_attributes(channel.snapshot_type(snapshot)),
              snapshot,
            ),
          ]),
        )
      })
    }),
  )
  use summary <- result.try(
    list.try_fold(layout.bindings, summary, fn(summary, binding) {
      use _ <- result.try(validate_initial_route(
        binding.source_store,
        binding.source_channel,
      ))
      use target <- result.try(validate_initial_route(
        binding.target_store,
        binding.target_channel,
      ))
      use _ <- result.try(require(
        initial_channel_exists(summary, "/" <> target),
        "/.channels/" <> binding.target_store,
        "unknown initial binding target",
      ))
      update_initial_channels(summary, binding.source_store, fn(channels) {
        use source <- result.try(
          list.find(channels, fn(item) { item.id == binding.source_channel })
          |> result.replace_error(fluid_summary.MissingEntry(
            "/" <> binding.source_store <> "/" <> binding.source_channel,
          )),
        )
        use entries <- result.try(case source.snapshot {
          channel.MapSnapshot(entries) -> Ok(entries)
          _ ->
            Error(fluid_summary.MalformedEntry(
              "/" <> binding.source_store <> "/" <> binding.source_channel,
              "initial binding source must be a SharedMap",
            ))
        })
        use _ <- result.try(require(
          !result.is_ok(list.key_find(entries, binding.key)),
          "/" <> binding.source_store <> "/" <> binding.source_channel,
          "duplicate initial map key",
        ))
        let updated =
          Channel(
            ..source,
            snapshot: channel.MapSnapshot(
              list.append(entries, [
                #(binding.key, handle.encode_handle(target)),
              ]),
            ),
          )
        Ok(
          list.map(channels, fn(item) {
            case item.id == source.id {
              True -> updated
              False -> item
            }
          }),
        )
      })
    }),
  )
  use _ <- result.try(validate_initial_references(summary))
  Ok(summary)
}

fn validate_initial_route(
  store: String,
  channel: String,
) -> Result(String, SummaryError) {
  use route <- result.try(
    fluid_container.route_key(fluid_container.Route(store, channel))
    |> result.map_error(fn(error) {
      fluid_summary.MalformedEntry("/.channels", string.inspect(error))
    }),
  )
  use _ <- result.try(require(
    route == store <> "/" <> channel
      && !string.starts_with(store, ".")
      && !string.starts_with(channel, "."),
    "/.channels/" <> route,
    "initial names must be canonical path components without a leading dot",
  ))
  Ok(route)
}

fn update_initial_channels(
  summary: DocumentSummary,
  store_id: String,
  update: fn(List(Channel)) -> Result(List(Channel), SummaryError),
) -> Result(DocumentSummary, SummaryError) {
  use store <- result.try(
    list.find(summary.datastores, fn(store) { store.id == store_id })
    |> result.replace_error(fluid_summary.MissingEntry(
      "/.channels/" <> store_id,
    )),
  )
  use channels <- result.try(update(store.channels))
  Ok(
    DocumentSummary(
      ..summary,
      datastores: list.map(summary.datastores, fn(candidate) {
        case candidate.id == store_id {
          True -> Datastore(..store, channels:)
          False -> candidate
        }
      }),
    ),
  )
}

fn initial_channel_exists(summary: DocumentSummary, path: String) -> Bool {
  list.any(summary.datastores, fn(store) {
    list.any(store.channels, fn(item) {
      "/" <> store.id <> "/" <> item.id == path
    })
  })
}

fn validate_initial_references(
  summary: DocumentSummary,
) -> Result(Nil, SummaryError) {
  list.try_each(summary.datastores, fn(store) {
    list.try_each(store.channels, fn(item) {
      let path = "/" <> store.id <> "/" <> item.id
      use references <- result.try(case item.snapshot {
        channel.MapSnapshot(entries) -> {
          use _ <- result.try(require(
            list.length(list.unique(list.map(entries, fn(entry) { entry.0 })))
              == list.length(entries),
            path,
            "duplicate initial map key",
          ))
          list.try_map(entries, fn(entry) {
            handle.collect_routed_addresses(entry.1, "/" <> store.id)
            |> result.map(fn(addresses) {
              list.map(addresses, fn(address) { "/" <> address })
            })
            |> result.map_error(fn(error) {
              fluid_summary.MalformedEntry(path, string.inspect(error))
            })
          })
          |> result.map(list.flatten)
        }
        channel.TreeSnapshot(snapshot) ->
          Ok(
            tree_kernel.snapshot_handle_references(snapshot)
            |> list.map(handle.reference_path),
          )
        _ -> Ok([])
      })
      list.try_each(references, fn(reference) {
        require(
          initial_channel_exists(summary, reference),
          path,
          "initial handle must name a declared channel",
        )
      })
    })
  })
}

/// Encode the Routerlicious first-summary POST body, not a Historian upload.
pub fn encode_create_request(
  summary: DocumentSummary,
) -> Result(Json, SummaryError) {
  use _ <- result.try(require(
    summary.sequence_number == 0
      && summary.minimum_sequence_number == 0
      && json.to_string(summary.protocol_members) == "[]"
      && json.to_string(summary.protocol_proposals) == "[]",
    "/.protocol",
    "creation requires an initial document",
  ))
  use tree <- result.try(encode(summary))
  use entries <- result.try(tree_entries(tree, "/"))
  use application <- result.try(whole_summary(
    SummaryTree(list.filter(entries, fn(entry) { entry.0 != ".protocol" })),
    "/",
  ))
  Ok(
    json.object([
      #("summary", application),
      #("sequenceNumber", json.int(0)),
      #("values", summary.protocol_values),
      #("enableDiscovery", json.bool(False)),
      #("generateToken", json.bool(False)),
      #("isEphemeralContainer", json.bool(False)),
      #("enableAnyBinaryBlobOnFirstSummary", json.bool(True)),
    ]),
  )
}

fn whole_summary(
  entry: SummaryEntry,
  path: String,
) -> Result(Json, SummaryError) {
  case entry {
    SummaryBlob(bytes) -> {
      let #(content, encoding) = case bit_array.to_string(bytes) {
        Ok(text) -> #(text, "utf-8")
        Error(_) -> #(bit_array.base64_encode(bytes, True), "base64")
      }
      Ok(
        json.object([
          #("type", json.string("blob")),
          #("content", json.string(content)),
          #("encoding", json.string(encoding)),
        ]),
      )
    }
    SummaryTree(entries) -> {
      use entries <- result.try(
        list.try_map(entries, fn(pair) {
          use value <- result.try(whole_summary(pair.1, path <> "/" <> pair.0))
          let kind = case pair.1 {
            SummaryBlob(_) -> "blob"
            _ -> "tree"
          }
          Ok(
            json.object([
              #("path", json.string(fluid_summary.encode_component(pair.0))),
              #("type", json.string(kind)),
              #("value", value),
            ]),
          )
        }),
      )
      Ok(
        json.object([
          #("type", json.string("tree")),
          #("entries", json.array(entries, fn(value) { value })),
        ]),
      )
    }
    fluid_summary.SummaryHandle(_, _) ->
      Error(fluid_summary.UnsupportedEntry(
        path,
        "initial summary has a prior reference",
      ))
  }
}

pub fn native(
  sequence_number: Int,
  minimum_sequence_number: Int,
  members: List(Int),
  channels: List(#(String, channel.Snapshot)),
) -> Result(DocumentSummary, SummaryError) {
  use _ <- result.try(require(
    sequence_number >= 0
      && minimum_sequence_number >= 0
      && minimum_sequence_number <= sequence_number,
    "/.protocol/attributes",
    "invalid sequence watermark",
  ))
  use view_id <- result.try(
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000000")
    |> result.map_error(fn(error) {
      fluid_summary.MalformedEntry("/.metadata", string.inspect(error))
    }),
  )
  use entries <- result.try(
    list.try_map(channels, fn(entry) {
      case string.split(entry.0, "/") {
        [store, id] if store != "" && id != "" ->
          Ok(#(
            store,
            Channel(
              id,
              channel.fluid_attributes(channel.snapshot_type(entry.1)),
              entry.1,
            ),
          ))
        _ ->
          Error(fluid_summary.MalformedEntry(
            "/.channels",
            "invalid channel address",
          ))
      }
    }),
  )
  use _ <- result.try(require(
    list.any(entries, fn(entry) {
      entry.0 == "watershed"
      && entry.1.id == "root"
      && channel.snapshot_type(entry.1.snapshot) == channel.MapChannel
    }),
    "/.channels/watershed/.channels/root",
    "native summary has no root map",
  ))
  use _ <- result.try(require(
    !list.any(entries, fn(entry) {
      channel.snapshot_type(entry.1.snapshot) == channel.TreeChannel
    }),
    "/.idCompressor",
    "tree summary requires document metadata",
  ))
  let ids = list.map(members, fn(id) { "native:" <> int.to_string(id) })
  let protocol_members =
    json.array(ids, fn(id) {
      json.array(
        [
          json.string(id),
          json.object([#("sequenceNumber", json.int(0))]),
        ],
        fn(value) { value },
      )
    })
  let stores =
    list.unique(list.map(entries, fn(entry) { entry.0 }))
    |> list.map(fn(id) {
      Datastore(
        id,
        json.object([
          #("pkg", json.string("[\"org.watershed\"]")),
          #("summaryFormatVersion", json.int(2)),
          #("isRootDataStore", json.bool(id == "watershed")),
        ]),
        ["org.watershed"],
        list.filter(entries, fn(entry) { entry.0 == id })
          |> list.map(fn(entry) { entry.1 }),
      )
    })
  let metadata =
    json.object([
      #("summaryFormatVersion", json.int(1)),
      #("summaryNumber", json.int(1)),
      #("gcFeature", json.int(3)),
      #(
        "documentSchema",
        json.object([
          #("version", json.int(1)),
          #("runtime", json.object([#("idCompressorMode", json.string("off"))])),
        ]),
      ),
      #(
        "lastMessage",
        json.object([#("sequenceNumber", json.int(sequence_number))]),
      ),
    ])
  let gc =
    json.object([
      #(
        "gcNodes",
        json.object(list.append(
          [
            #(
              "/",
              json.object([
                #(
                  "outboundRoutes",
                  json.array(
                    list.map(stores, fn(store) { "/" <> store.id }),
                    json.string,
                  ),
                ),
              ]),
            ),
            ..list.map(stores, fn(store) {
              #(
                "/" <> store.id,
                json.object([
                  #(
                    "outboundRoutes",
                    json.array(
                      list.map(store.channels, fn(item) {
                        "/" <> store.id <> "/" <> item.id
                      }),
                      json.string,
                    ),
                  ),
                ]),
              )
            })
          ],
          list.map(entries, fn(entry) {
            #(
              "/" <> entry.0 <> "/" <> entry.1.id,
              json.object([#("outboundRoutes", json.array([], json.string))]),
            )
          }),
        )),
      ),
    ])
  let summary =
    DocumentSummary(
      sequence_number,
      minimum_sequence_number,
      metadata,
      protocol_members,
      ids,
      json.array([], fn(value) { value }),
      json.array([], fn(value) { value }),
      [#("root", "watershed")],
      stores,
      None,
      view_id,
      gc,
      None,
      sequence_number,
      [],
    )
  use gc <- result.try(refresh_gc(summary))
  Ok(DocumentSummary(..summary, gc:))
}

pub type Datastore {
  Datastore(
    id: String,
    component: Json,
    package_path: List(String),
    channels: List(Channel),
  )
}

pub type Channel {
  Channel(id: String, attributes: Json, snapshot: channel.Snapshot)
}

pub type CaptureRouting {
  CaptureRouting(
    aliases: List(#(String, String)),
    datastores: List(#(String, List(String))),
    channel_attributes: List(#(String, Json)),
  )
}

pub opaque type DocumentSummary {
  DocumentSummary(
    sequence_number: Int,
    minimum_sequence_number: Int,
    metadata: Json,
    protocol_members: Json,
    member_ids: List(String),
    protocol_proposals: Json,
    protocol_values: Json,
    aliases: List(#(String, String)),
    datastores: List(Datastore),
    compressor: Option(fluid_ids.Compressor),
    view_id: fluid_ids.StableId,
    gc: Json,
    recent_batches: Option(Json),
    last_acknowledged_summary: Int,
    intervening_gc_edges: List(#(String, String)),
  )
}

pub fn decode(
  tree: SummaryEntry,
  previous: Option(SummaryEntry),
  local_session: fluid_ids.SessionId,
  view_id: fluid_ids.StableId,
) -> Result(DocumentSummary, SummaryError) {
  use resolved <- result.try(fluid_summary.resolve(tree, previous))
  use resolved <- result.try(application_root(resolved))
  use protocol <- result.try(required(resolved, [".protocol"]))
  use attributes <- result.try(json_blob(protocol, ["attributes"], "/.protocol"))
  use sequence_number <- result.try(integer(
    attributes,
    ["sequenceNumber"],
    "/.protocol/attributes",
  ))
  use minimum_sequence_number <- result.try(integer(
    attributes,
    ["minimumSequenceNumber"],
    "/.protocol/attributes",
  ))
  use _ <- result.try(require(
    sequence_number >= 0
      && minimum_sequence_number >= 0
      && minimum_sequence_number <= sequence_number,
    "/.protocol/attributes",
    "invalid sequence watermark",
  ))
  use members <- result.try(json_blob(protocol, ["quorumMembers"], "/.protocol"))
  use ids <- result.try(member_ids(members))
  use proposals <- result.try(json_blob(
    protocol,
    ["quorumProposals"],
    "/.protocol",
  ))
  use values <- result.try(json_blob(protocol, ["quorumValues"], "/.protocol"))
  use metadata <- result.try(json_blob(resolved, [".metadata"], "/"))
  use _ <- result.try(validate_last_message(metadata))
  use _ <- result.try(version(
    metadata,
    ["summaryFormatVersion"],
    1,
    "/.metadata",
  ))
  use _ <- result.try(version(
    metadata,
    ["documentSchema", "version"],
    1,
    "/.metadata",
  ))
  use _ <- result.try(version(metadata, ["gcFeature"], 3, "/.metadata"))
  use summary_number <- result.try(integer(
    metadata,
    ["summaryNumber"],
    "/.metadata",
  ))
  use _ <- result.try(require(
    summary_number >= 0,
    "/.metadata",
    "invalid summary number",
  ))
  use mode <- result.try(text(
    metadata,
    ["documentSchema", "runtime", "idCompressorMode"],
    "/.metadata",
  ))
  use _ <- result.try(require(
    mode == "on" || mode == "off",
    "/.metadata/documentSchema/runtime",
    "unsupported ID compressor mode",
  ))
  use compressor <- result.try(case find(resolved, [".idCompressor"]) {
    Ok(_) -> {
      use _ <- result.try(require(
        mode == "on",
        "/.metadata/documentSchema/runtime",
        "compressor mode does not match stored state",
      ))
      use encoded <- result.try(json_blob(resolved, [".idCompressor"], "/"))
      fluid_ids.deserialize(encoded, local_session)
      |> result.map(Some)
      |> result.map_error(fn(error) {
        fluid_summary.MalformedEntry("/.idCompressor", string.inspect(error))
      })
    }

    Error(fluid_summary.MissingEntry(_)) -> {
      use mode <- result.try(text(
        metadata,
        ["documentSchema", "runtime", "idCompressorMode"],
        "/.metadata",
      ))
      use _ <- result.try(require(
        mode == "off",
        "/.idCompressor",
        "missing ID compressor",
      ))
      Ok(None)
    }
    Error(error) -> Error(error)
  })
  use aliases_blob <- result.try(json_blob(resolved, [".aliases"], "/"))
  use aliases <- result.try(alias_pairs(aliases_blob))
  use gc <- result.try(case find(resolved, ["gc", "__gc_root"]) {
    Ok(_) -> json_blob(resolved, ["gc", "__gc_root"], "/gc")
    Error(fluid_summary.MissingEntry(_)) ->
      case sequence_number, minimum_sequence_number, find(resolved, ["gc"]) {
        0, 0, Error(fluid_summary.MissingEntry(_)) ->
          Ok(json.object([#("gcNodes", json.object([]))]))
        _, _, _ -> Error(fluid_summary.MissingEntry("/gc/__gc_root"))
      }
    Error(error) -> Error(error)
  })
  use _ <- result.try(
    json.parse(json.to_string(gc), decode.at(["gcNodes"], decode.dynamic))
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry("/gc/__gc_root", "missing GC nodes")
    }),
  )
  use recent_batches <- result.try(case find(resolved, [".recentBatchInfo"]) {
    Ok(_) -> {
      use value <- result.try(json_blob(resolved, [".recentBatchInfo"], "/"))
      use _ <- result.try(validate_batches(value, sequence_number))
      Ok(Some(value))
    }
    Error(fluid_summary.MissingEntry(_)) -> Ok(None)
    Error(error) -> Error(error)
  })
  use stores <- result.try(required(resolved, [".channels"]))
  use stores <- result.try(tree_entries(stores, "/.channels"))
  use datastores <- result.try(
    list.try_map(stores, fn(store) {
      decode_datastore(
        store,
        compressor,
        view_id,
        sequence_number,
        minimum_sequence_number,
      )
    }),
  )
  use _ <- result.try(
    list.try_each(aliases, fn(alias) {
      require(
        list.any(datastores, fn(store) { store.id == alias.1 }),
        "/.aliases",
        "alias names an unknown datastore",
      )
    }),
  )
  use root_store <- result.try(
    list.key_find(aliases, "root")
    |> result.replace_error(fluid_summary.MissingEntry("/.aliases/root")),
  )
  use _ <- result.try(require(
    list.any(datastores, fn(store) {
      store.id == root_store
      && list.any(store.channels, fn(item) {
        channel.snapshot_type(item.snapshot) == channel.MapChannel
      })
    }),
    "/.channels/" <> root_store,
    "root datastore has no map",
  ))
  Ok(
    DocumentSummary(
      sequence_number,
      minimum_sequence_number,
      metadata,
      members,
      ids,
      proposals,
      values,
      aliases,
      datastores,
      compressor,
      view_id,
      gc,
      recent_batches,
      sequence_number,
      [],
    ),
  )
}

fn application_root(tree: SummaryEntry) -> Result(SummaryEntry, SummaryError) {
  case find(tree, [".app"]) {
    Ok(app) -> {
      use app_entries <- result.try(tree_entries(app, "/.app"))
      use outer_protocol <- result.try(required(tree, [".protocol"]))
      use root_entries <- result.try(tree_entries(tree, "/"))
      use _ <- result.try(require(
        list.length(root_entries) == 2
          && !list.any(app_entries, fn(entry) { entry.0 == ".app" }),
        "/.app",
        "invalid application wrapper",
      ))
      let protocol = case list.key_find(app_entries, ".protocol") {
        Ok(protocol) -> protocol
        Error(_) -> outer_protocol
      }
      Ok(
        SummaryTree([
          #(".protocol", protocol),
          ..list.filter(app_entries, fn(entry) { entry.0 != ".protocol" })
        ]),
      )
    }
    Error(fluid_summary.MissingEntry(_)) -> Ok(tree)
    Error(error) -> Error(error)
  }
}

fn decode_datastore(
  store: #(String, SummaryEntry),
  compressor: Option(fluid_ids.Compressor),
  view_id: fluid_ids.StableId,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(Datastore, SummaryError) {
  let path = "/.channels/" <> store.0
  use component <- result.try(json_blob(store.1, [".component"], path))
  use _ <- result.try(version(
    component,
    ["summaryFormatVersion"],
    2,
    path <> "/.component",
  ))
  use encoded_pkg <- result.try(
    json.parse(json.to_string(component), decode.at(["pkg"], decode.string))
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry(path <> "/.component", "missing package")
    }),
  )
  use package_path <- result.try(
    json.parse(encoded_pkg, decode.list(decode.string))
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry(path <> "/.component", "invalid package")
    }),
  )
  use _ <- result.try(require(
    package_path != [],
    path <> "/.component",
    "empty package",
  ))
  use channels <- result.try(required(store.1, [".channels"]))
  use channels <- result.try(tree_entries(channels, path <> "/.channels"))
  use channels <- result.try(
    list.try_map(channels, fn(entry) {
      let channel_path = path <> "/.channels/" <> entry.0
      use attributes <- result.try(json_blob(
        entry.1,
        [".attributes"],
        channel_path,
      ))
      use kind <- result.try(
        json.parse(
          json.to_string(attributes),
          decode.at(["type"], decode.string),
        )
        |> result.map_error(fn(_) {
          fluid_summary.MalformedEntry(
            channel_path <> "/.attributes",
            "missing channel type",
          )
        }),
      )
      use snapshot <- result.try(case kind {
        "https://graph.microsoft.com/types/tree" -> {
          use compressor <- result.try(case compressor {
            Some(compressor) -> Ok(compressor)
            None -> Error(fluid_summary.MissingEntry("/.idCompressor"))
          })
          use entries <- result.try(tree_entries(entry.1, channel_path))
          let entry =
            SummaryTree(
              list.filter(entries, fn(item) { item.0 != ".attributes" }),
            )
          use entry <- result.try(bind_summary_references(
            entry,
            "/" <> store.0,
            channel_path,
          ))
          // ponytail: Fragmented modules. To decode one tree summary, this
          // caller uses tree/codec/summary, tree/codec, and tree/summary. Add
          // one tree function that decodes a summary.
          use data <- result.try(
            summary_codec.decode(
              entry,
              None,
              fluid_ids.local_session(compressor),
              codec.DecodeContext(codec.Fluid310, compressor),
            )
            |> result.map_error(fn(error) {
              fluid_summary.MalformedEntry(channel_path, string.inspect(error))
            }),
          )
          tree_summary.from_wire(
            data,
            view_id,
            compressor,
            sequence_number,
            minimum_sequence_number,
          )
          |> result.map(channel.TreeSnapshot)
          |> result.map_error(fn(error) {
            fluid_summary.MalformedEntry(channel_path, string.inspect(error))
          })
        }
        "https://graph.microsoft.com/types/map" -> {
          use raw <- result.try(blob(entry.1, ["header"]))
          use raw <- result.try(bind_json_string_references(
            raw,
            "/" <> store.0,
            channel_path <> "/header",
          ))
          use entries <- result.try(tree_entries(entry.1, channel_path))
          use external <- result.try(
            list.try_map(
              list.filter(entries, fn(entry) {
                entry.0 != ".attributes" && entry.0 != "header"
              }),
              fn(entry) {
                use bytes <- result.try(case entry.1 {
                  SummaryBlob(bytes) -> Ok(bytes)
                  _ ->
                    Error(fluid_summary.WrongKind(
                      channel_path <> "/" <> entry.0,
                      fluid_summary.BlobHandle,
                    ))
                })
                use raw <- result.try(
                  bit_array.to_string(bytes)
                  |> result.map_error(fn(_) {
                    fluid_summary.MalformedEntry(
                      channel_path <> "/" <> entry.0,
                      "invalid UTF-8",
                    )
                  }),
                )
                bind_json_string_references(
                  raw,
                  "/" <> store.0,
                  channel_path <> "/" <> entry.0,
                )
                |> result.map(fn(raw) { #(entry.0, raw) })
              },
            ),
          )
          wire_op.decode_map_snapshot(raw, external)
          |> result.map(channel.MapSnapshot)
          |> result.map_error(fn(detail) {
            fluid_summary.MalformedEntry(channel_path <> "/header", detail)
          })
        }
        _ -> {
          use kind <- result.try(
            channel.fluid_string_to_type(kind)
            |> result.map_error(fn(_) {
              fluid_summary.UnsupportedEntry(
                channel_path <> "/.attributes",
                "unsupported channel type: " <> kind,
              )
            }),
          )
          use decoder <- result.try(
            channel.snapshot_decoder(kind)
            |> result.map_error(fn(error) {
              fluid_summary.MalformedEntry(
                channel_path <> "/header",
                string.inspect(error),
              )
            }),
          )
          use payload <- result.try(json_blob(entry.1, ["header"], channel_path))
          json.parse(json.to_string(payload), decoder)
          |> result.map_error(fn(_) {
            fluid_summary.MalformedEntry(
              channel_path <> "/header",
              "invalid snapshot",
            )
          })
        }
      })
      use _ <- result.try(validate_attributes(
        attributes,
        snapshot,
        channel_path,
      ))
      Ok(Channel(entry.0, attributes, snapshot))
    }),
  )
  Ok(Datastore(store.0, component, package_path, channels))
}

fn bind_summary_references(
  entry: SummaryEntry,
  context: String,
  path: String,
) -> Result(SummaryEntry, SummaryError) {
  fluid_summary.map_utf8_blobs(entry, fn(raw) {
    bind_json_string_references(raw, context, path)
  })
}

fn bind_json_string_references(
  raw: String,
  context: String,
  path: String,
) -> Result(String, SummaryError) {
  case json.parse(raw, wire.json_value_decoder()) {
    Error(_) ->
      Error(fluid_summary.MalformedEntry(path, "invalid JSON summary blob"))
    Ok(value) ->
      handle.bind_serialized_references(value, context)
      |> result.map(json.to_string)
      |> result.map_error(fn(error) {
        fluid_summary.MalformedEntry(path, string.inspect(error))
      })
  }
}

fn validate_attributes(
  attributes: Json,
  snapshot: channel.Snapshot,
  path: String,
) -> Result(Nil, SummaryError) {
  use kind <- result.try(text(attributes, ["type"], path))
  use format <- result.try(text(attributes, ["snapshotFormatVersion"], path))
  use package <- result.try(text(attributes, ["packageVersion"], path))
  let expected = case channel.snapshot_type(snapshot) {
    channel.TreeChannel -> #("0.0.0", "3.1.0")
    channel.MapChannel -> #("0.2", "3.1.0")
    _ -> #("1", "1")
  }
  require(
    kind == channel.fluid_type_to_string(channel.snapshot_type(snapshot))
      && format == expected.0
      && package == expected.1,
    path <> "/.attributes",
    "unsupported channel attributes",
  )
}

pub fn encode(summary: DocumentSummary) -> Result(SummaryEntry, SummaryError) {
  let DocumentSummary(
    sequence_number,
    minimum_sequence_number,
    metadata,
    members,
    _ids,
    proposals,
    values,
    aliases,
    datastores,
    compressor,
    _view_id,
    gc,
    recent_batches,
    _last_acknowledged_summary,
    _intervening_gc_edges,
  ) = summary
  use compressor_entry <- result.try(case compressor {
    Some(compressor) ->
      fluid_ids.serialize(compressor, False)
      |> result.map(fn(serialized) {
        [#(".idCompressor", SummaryBlob(<<json.to_string(serialized):utf8>>))]
      })
      |> result.map_error(fn(error) {
        fluid_summary.MalformedEntry("/.idCompressor", string.inspect(error))
      })
    None -> Ok([])
  })
  use stores <- result.try(
    list.try_map(datastores, fn(store) {
      use channels <- result.try(
        list.try_map(store.channels, fn(item) {
          use entries <- result.try(case item.snapshot {
            channel.TreeSnapshot(snapshot) -> {
              use compressor <- result.try(case compressor {
                Some(compressor) -> Ok(compressor)
                None -> Error(fluid_summary.MissingEntry("/.idCompressor"))
              })
              // ponytail: Fragmented modules. To encode one tree summary, this
              // caller uses tree/summary, tree/codec/summary, and tree/codec.
              // Add one tree function that encodes a summary.
              use wire <- result.try(
                tree_summary.to_wire(snapshot)
                |> result.map_error(fn(error) {
                  fluid_summary.MalformedEntry(
                    "/.channels/" <> store.id <> "/.channels/" <> item.id,
                    string.inspect(error),
                  )
                }),
              )
              summary_codec.encode(
                wire,
                fluid_ids.local_session(compressor),
                codec.EncodeContext(
                  codec.Fluid310,
                  compressor,
                  Some(wire.schema),
                ),
              )
              |> result.map_error(fn(error) {
                fluid_summary.MalformedEntry(
                  "/.channels/" <> store.id <> "/.channels/" <> item.id,
                  string.inspect(error),
                )
              })
            }
            channel.MapSnapshot(entries) ->
              Ok(
                SummaryTree([
                  #("header", json_entry(wire_op.encode_map_header(entries))),
                ]),
              )
            other -> {
              use payload <- result.try(
                channel.encode_snapshot(other)
                |> result.map_error(fn(error) {
                  fluid_summary.MalformedEntry(
                    "/.channels/" <> store.id <> "/.channels/" <> item.id,
                    string.inspect(error),
                  )
                }),
              )
              Ok(SummaryTree([#("header", json_entry(payload))]))
            }
          })
          use entries <- result.try(tree_entries(
            entries,
            "/.channels/" <> store.id <> "/.channels/" <> item.id,
          ))
          Ok(#(
            item.id,
            SummaryTree([
              #(".attributes", json_entry(item.attributes)),
              ..entries
            ]),
          ))
        }),
      )
      Ok(#(
        store.id,
        SummaryTree([
          #(".component", json_entry(store.component)),
          #(".channels", SummaryTree(channels)),
        ]),
      ))
    }),
  )
  let application_entries = [
    #(".metadata", json_entry(metadata)),
    #(
      ".aliases",
      json_entry(
        json.array(aliases, fn(alias) {
          json.array([json.string(alias.0), json.string(alias.1)], fn(value) {
            value
          })
        }),
      ),
    ),
    #(".channels", SummaryTree(stores)),
    #("gc", SummaryTree([#("__gc_root", json_entry(gc))])),
    ..list.append(compressor_entry, case recent_batches {
      Some(batches) -> [#(".recentBatchInfo", json_entry(batches))]
      None -> []
    })
  ]
  Ok(
    SummaryTree([
      #(
        ".protocol",
        SummaryTree([
          #(
            "attributes",
            json_entry(
              json.object([
                #("sequenceNumber", json.int(sequence_number)),
                #("minimumSequenceNumber", json.int(minimum_sequence_number)),
              ]),
            ),
          ),
          #("quorumMembers", json_entry(members)),
          #("quorumProposals", json_entry(proposals)),
          #("quorumValues", json_entry(values)),
        ]),
      ),
      ..application_entries
    ]),
  )
}

pub fn inspect(summary: DocumentSummary) -> inspection.SummaryBlob {
  let DocumentSummary(sequence_number:, member_ids: ids, datastores: stores, ..) =
    summary
  let members = list.map(ids, member_int)
  inspection.SummaryBlob(
    sequence_number,
    members,
    list.flat_map(stores, fn(store) {
      list.map(store.channels, fn(item) {
        inspection.ChannelSnapshot(store.id <> "/" <> item.id, item.snapshot)
      })
    }),
  )
}

pub fn sequence_number(summary: DocumentSummary) -> Int {
  summary.sequence_number
}

pub fn minimum_sequence_number(summary: DocumentSummary) -> Int {
  summary.minimum_sequence_number
}

pub fn aliases(summary: DocumentSummary) -> List(#(String, String)) {
  summary.aliases
}

pub fn datastores(summary: DocumentSummary) -> List(Datastore) {
  summary.datastores
}

pub fn gc(summary: DocumentSummary) -> Json {
  summary.gc
}

pub fn compressor(summary: DocumentSummary) -> Option(fluid_ids.Compressor) {
  summary.compressor
}

pub fn view_id(summary: DocumentSummary) -> fluid_ids.StableId {
  summary.view_id
}

pub fn members(summary: DocumentSummary) -> List(Int) {
  list.map(summary.member_ids, member_int)
}

fn member_int(id: String) -> Int {
  case string.starts_with(id, "native:") {
    True ->
      case int.parse(string.drop_start(id, 7)) {
        Ok(number) -> number
        Error(_) -> client_id.to_int(id)
      }
    False -> client_id.to_int(id)
  }
}

pub fn advance(
  summary: DocumentSummary,
  message: SequencedDocumentMessage,
) -> Result(DocumentSummary, SummaryError) {
  use _ <- result.try(require(
    message.sequence_number == summary.sequence_number + 1
      && message.minimum_sequence_number >= summary.minimum_sequence_number
      && message.minimum_sequence_number <= message.sequence_number,
    "/.protocol/attributes",
    "invalid sequenced message watermark",
  ))
  use _ <- result.try(check_batch(summary, message))
  use #(protocol_members, member_ids) <- result.try(advance_members(
    summary.protocol_members,
    summary.member_ids,
    message,
  ))
  use last_message <- result.try(last_message(message))
  use metadata <- result.try(replace_member(
    summary.metadata,
    "lastMessage",
    last_message,
    "/.metadata",
  ))
  use last_acknowledged_summary <- result.try(case message.message_type {
    "summaryAck" -> {
      use response <- result.try(
        summary_message.decode_message(message.message_type, message.contents)
        |> result.map_error(fn(_) {
          fluid_summary.MalformedEntry(
            "/.metadata",
            "invalid summary acknowledgement",
          )
        }),
      )
      use proposal <- result.try(case response {
        summary_message.Ack(proposal, _) -> Ok(proposal)
        summary_message.Nack(_, _) ->
          Error(fluid_summary.MalformedEntry(
            "/.metadata",
            "unexpected summary rejection",
          ))
      })
      use _ <- result.try(require(
        proposal >= 0 && proposal < message.sequence_number,
        "/.metadata",
        "invalid summary proposal sequence",
      ))
      case proposal > summary.last_acknowledged_summary {
        True -> Ok(proposal)
        False -> Ok(summary.last_acknowledged_summary)
      }
    }
    _ -> Ok(summary.last_acknowledged_summary)
  })
  use batches <- result.try(advance_batches(summary.recent_batches, message))
  use #(gc, intervening_gc_edges) <- result.try(advance_gc_references(
    summary.gc,
    summary.intervening_gc_edges,
    message,
  ))
  Ok(
    DocumentSummary(
      ..summary,
      sequence_number: message.sequence_number,
      minimum_sequence_number: message.minimum_sequence_number,
      metadata:,
      protocol_members:,
      member_ids:,
      recent_batches: batches,
      last_acknowledged_summary:,
      gc:,
      intervening_gc_edges:,
    ),
  )
}

pub fn capture(
  summary: DocumentSummary,
  channels: List(#(String, channel.Snapshot)),
  compressor: Option(fluid_ids.Compressor),
  routing: CaptureRouting,
) -> Result(DocumentSummary, SummaryError) {
  let CaptureRouting(current_aliases, stores, attributes) = routing
  use _ <- result.try(
    list.try_each(summary.aliases, fn(alias) {
      require(
        list.key_find(current_aliases, alias.0) == Ok(alias.1),
        "/.aliases",
        "stored alias changed",
      )
    }),
  )
  let aliases =
    list.append(
      summary.aliases,
      list.filter(current_aliases, fn(alias) {
        !list.any(summary.aliases, fn(existing) { existing.0 == alias.0 })
      }),
    )
  use _ <- result.try(
    list.try_each(aliases, fn(alias) {
      require(
        list.key_find(stores, alias.1) != Error(Nil),
        "/.aliases",
        "alias names an unknown datastore",
      )
    }),
  )
  use _ <- result.try(require(
    list.key_find(aliases, "root") != Error(Nil),
    "/.aliases/root",
    "root alias is missing",
  ))
  use newly_attached <- result.try(
    list.try_map(
      list.filter(stores, fn(entry) {
        !list.any(summary.datastores, fn(store) { store.id == entry.0 })
      }),
      fn(entry) {
        use _ <- result.try(require(
          entry.1 != [],
          "/.channels/" <> entry.0 <> "/.component",
          "empty datastore package",
        ))
        Ok(
          Datastore(
            entry.0,
            json.object([
              #(
                "pkg",
                json.string(json.to_string(json.array(entry.1, json.string))),
              ),
              #("summaryFormatVersion", json.int(2)),
              #("isRootDataStore", json.bool(False)),
            ]),
            entry.1,
            [],
          ),
        )
      },
    ),
  )
  use datastores <- result.try(
    list.try_map(list.append(summary.datastores, newly_attached), fn(store) {
      use package_path <- result.try(
        list.key_find(stores, store.id)
        |> result.replace_error(fluid_summary.MissingEntry(
          "/.channels/" <> store.id,
        )),
      )
      use _ <- result.try(require(
        store.package_path == package_path,
        "/.channels/" <> store.id <> "/.component",
        "datastore package changed",
      ))
      use snapshots <- result.try(
        list.try_map(
          list.filter(channels, fn(entry) {
            string.starts_with(entry.0, store.id <> "/")
          }),
          fn(entry) {
            use attributes <- result.try(
              list.key_find(attributes, entry.0)
              |> result.replace_error(fluid_summary.MissingEntry(
                "/.channels/" <> entry.0 <> "/.attributes",
              )),
            )
            use _ <- result.try(validate_attributes(
              attributes,
              entry.1,
              "/.channels/" <> entry.0,
            ))
            case string.split(entry.0, "/") {
              [_, id] -> Ok(Channel(id, attributes, entry.1))
              _ ->
                Error(fluid_summary.MalformedEntry(
                  "/.channels/" <> entry.0,
                  "invalid channel route",
                ))
            }
          },
        ),
      )
      use _ <- result.try(
        list.try_each(store.channels, fn(item) {
          require(
            list.any(snapshots, fn(snapshot) { snapshot.id == item.id }),
            "/.channels/" <> store.id <> "/.channels/" <> item.id,
            "stored channel disappeared",
          )
        }),
      )
      use component <- result.try(
        case list.any(aliases, fn(alias) { alias.1 == store.id }) {
          True ->
            replace_member(
              store.component,
              "isRootDataStore",
              json.bool(True),
              "/.channels/" <> store.id <> "/.component",
            )
          False -> Ok(store.component)
        },
      )
      Ok(Datastore(..store, component:, channels: snapshots))
    }),
  )
  use _ <- result.try(require(
    list.length(channels)
      == list.fold(datastores, 0, fn(total, store) {
      total + list.length(store.channels)
    }),
    "/.channels",
    "unregistered channel snapshot",
  ))
  let next = DocumentSummary(..summary, aliases:, datastores:, compressor:)
  use gc <- result.try(refresh_gc(next))
  Ok(DocumentSummary(..next, gc:, intervening_gc_edges: []))
}

pub fn generated(
  summary: DocumentSummary,
) -> Result(DocumentSummary, SummaryError) {
  use count <- result.try(integer(
    summary.metadata,
    ["summaryNumber"],
    "/.metadata",
  ))
  use metadata <- result.try(replace_member(
    summary.metadata,
    "summaryNumber",
    json.int(count + 1),
    "/.metadata",
  ))
  Ok(DocumentSummary(..summary, metadata:))
}

fn refresh_gc(summary: DocumentSummary) -> Result(Json, SummaryError) {
  use previous_nodes <- result.try(
    json.parse(
      json.to_string(summary.gc),
      decode.at(
        ["gcNodes"],
        decode.dict(decode.string, wire.json_value_decoder()),
      ),
    )
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry("/gc/__gc_root", "invalid GC nodes")
    }),
  )
  let stores = summary.datastores
  use current_nodes <- result.try(
    list.try_fold(stores, previous_nodes, fn(nodes, store) {
      use nodes <- result.try(update_routes(
        nodes,
        "/" <> store.id,
        list.map(store.channels, fn(item) { "/" <> store.id <> "/" <> item.id }),
      ))
      list.try_fold(store.channels, nodes, fn(nodes, item) {
        let path = "/" <> store.id <> "/" <> item.id
        use links <- result.try(case item.snapshot {
          channel.MapSnapshot(entries) ->
            list.try_fold(entries, [], fn(links, entry) {
              use addresses <- result.try(
                handle.collect_routed_addresses(entry.1, "/" <> store.id)
                |> result.map_error(fn(error) {
                  fluid_summary.MalformedEntry(
                    "/.channels" <> path,
                    string.inspect(error),
                  )
                }),
              )
              Ok(list.append(
                links,
                list.map(addresses, fn(address) { "/" <> address }),
              ))
            })
          channel.TreeSnapshot(snapshot) ->
            tree_kernel.snapshot_handle_references(snapshot)
            |> list.map(handle.reference_path)
            |> Ok
          _ -> Ok([])
        })
        update_routes(nodes, path, ["/" <> store.id, ..list.unique(links)])
      })
    }),
  )
  use roots <- result.try(
    list.try_map(stores, fn(store) {
      json.parse(
        json.to_string(store.component),
        decode.at(["isRootDataStore"], decode.bool),
      )
      |> result.map(fn(is_root) {
        case is_root {
          True -> ["/" <> store.id]
          False -> []
        }
      })
      |> result.map_error(fn(_) {
        fluid_summary.MalformedEntry(
          "/.channels/" <> store.id <> "/.component",
          "invalid datastore root status",
        )
      })
    }),
  )
  use current_nodes <- result.try(update_routes(
    current_nodes,
    "/",
    list.append(
      list.flatten(roots),
      list.map(summary.aliases, fn(alias) { "/" <> alias.1 }),
    ),
  ))
  use current_reachable <- result.try(reachable_gc_nodes(
    current_nodes,
    ["/"],
    dict.new(),
  ))
  use combined_nodes <- result.try(union_gc_nodes(previous_nodes, current_nodes))
  use combined_nodes <- result.try(
    list.try_fold(summary.intervening_gc_edges, combined_nodes, fn(nodes, edge) {
      append_route(nodes, edge.0, edge.1)
    }),
  )
  use intervening_reachable <- result.try(case summary.intervening_gc_edges {
    [] -> Ok(dict.new())
    edges ->
      reachable_gc_nodes(
        combined_nodes,
        ["/", ..list.map(edges, fn(edge) { edge.1 })],
        dict.new(),
      )
  })
  use nodes <- result.try(
    list.try_map(dict.to_list(current_nodes), fn(entry) {
      let #(path, node) = entry
      use fields <- result.try(
        json.parse(
          json.to_string(node),
          decode.dict(decode.string, wire.json_value_decoder()),
        )
        |> result.map_error(fn(_) {
          fluid_summary.MalformedEntry(
            "/gc/__gc_root" <> path,
            "invalid GC node",
          )
        }),
      )
      use fields <- result.try(case dict.has_key(current_reachable, path) {
        True -> Ok(dict.delete(fields, "unreferencedTimestampMs"))
        False ->
          case dict.has_key(intervening_reachable, path) {
            True -> {
              use timestamp <- result.try(reference_timestamp(summary.metadata))
              Ok(dict.insert(
                fields,
                "unreferencedTimestampMs",
                json.int(timestamp),
              ))
            }
            False ->
              case dict.get(fields, "unreferencedTimestampMs") {
                Ok(value) -> {
                  use _ <- result.try(
                    json.parse(json.to_string(value), decode.int)
                    |> result.map_error(fn(_) {
                      fluid_summary.MalformedEntry(
                        "/gc/__gc_root" <> path,
                        "invalid unreferenced timestamp",
                      )
                    }),
                  )
                  Ok(fields)
                }
                Error(_) -> {
                  use timestamp <- result.try(reference_timestamp(
                    summary.metadata,
                  ))
                  Ok(dict.insert(
                    fields,
                    "unreferencedTimestampMs",
                    json.int(timestamp),
                  ))
                }
              }
          }
      })
      Ok(#(path, json.object(dict.to_list(fields))))
    }),
  )
  replace_member(summary.gc, "gcNodes", json.object(nodes), "/gc/__gc_root")
}

fn union_gc_nodes(
  previous: Dict(String, Json),
  current: Dict(String, Json),
) -> Result(Dict(String, Json), SummaryError) {
  list.try_fold(dict.to_list(previous), current, fn(nodes, entry) {
    use previous_routes <- result.try(gc_routes(entry.1, entry.0))
    use current_routes <- result.try(case dict.get(nodes, entry.0) {
      Ok(node) -> gc_routes(node, entry.0)
      Error(_) -> Ok([])
    })
    update_routes(nodes, entry.0, list.append(previous_routes, current_routes))
  })
}

fn append_route(
  nodes: Dict(String, Json),
  source: String,
  target: String,
) -> Result(Dict(String, Json), SummaryError) {
  use routes <- result.try(case dict.get(nodes, source) {
    Ok(node) -> gc_routes(node, source)
    Error(_) -> Ok([])
  })
  update_routes(nodes, source, [target, ..routes])
}

fn gc_routes(node: Json, path: String) -> Result(List(String), SummaryError) {
  json.parse(
    json.to_string(node),
    decode.at(["outboundRoutes"], decode.list(decode.string)),
  )
  |> result.map_error(fn(_) {
    fluid_summary.MalformedEntry(
      "/gc/__gc_root" <> path,
      "invalid outbound routes",
    )
  })
}

fn reachable_gc_nodes(
  nodes: Dict(String, Json),
  pending: List(String),
  visited: Dict(String, Bool),
) -> Result(Dict(String, Bool), SummaryError) {
  case pending {
    [] -> Ok(visited)
    [path, ..rest] ->
      case dict.has_key(visited, path) {
        True -> reachable_gc_nodes(nodes, rest, visited)
        False -> {
          use routes <- result.try(case dict.get(nodes, path) {
            Error(_) -> Ok([])
            Ok(node) ->
              json.parse(
                json.to_string(node),
                decode.at(["outboundRoutes"], decode.list(decode.string)),
              )
              |> result.map_error(fn(_) {
                fluid_summary.MalformedEntry(
                  "/gc/__gc_root" <> path,
                  "invalid outbound routes",
                )
              })
          })
          reachable_gc_nodes(
            nodes,
            list.append(routes, rest),
            dict.insert(visited, path, True),
          )
        }
      }
  }
}

fn metadata_fields(metadata: Json) -> Result(Dict(String, Json), SummaryError) {
  json.parse(
    json.to_string(metadata),
    decode.dict(decode.string, wire.json_value_decoder()),
  )
  |> result.map_error(fn(_) {
    fluid_summary.MalformedEntry("/.metadata", "invalid metadata object")
  })
}

fn validate_last_message(metadata: Json) -> Result(Nil, SummaryError) {
  use fields <- result.try(metadata_fields(metadata))
  case dict.get(fields, "lastMessage") {
    Error(_) -> Ok(Nil)
    Ok(message) ->
      case message == json.null() {
        True -> Ok(Nil)
        False -> {
          use fields <- result.try(
            metadata_fields(message)
            |> result.map_error(fn(_) {
              fluid_summary.MalformedEntry(
                "/.metadata/lastMessage",
                "invalid last message object",
              )
            }),
          )
          case dict.has_key(fields, "timestamp") {
            False -> Ok(Nil)
            True ->
              integer(message, ["timestamp"], "/.metadata/lastMessage")
              |> result.replace(Nil)
          }
        }
      }
  }
}

fn reference_timestamp(metadata: Json) -> Result(Int, SummaryError) {
  use fields <- result.try(metadata_fields(metadata))
  case dict.get(fields, "lastMessage") {
    Ok(message) ->
      case message == json.null() {
        True -> integer(metadata, ["message", "timestamp"], "/.metadata")
        False -> integer(message, ["timestamp"], "/.metadata/lastMessage")
      }
    Error(_) -> integer(metadata, ["message", "timestamp"], "/.metadata")
  }
}

fn advance_gc_references(
  gc: Json,
  intervening: List(#(String, String)),
  message: SequencedDocumentMessage,
) -> Result(#(Json, List(#(String, String))), SummaryError) {
  case message.message_type {
    "op" -> {
      let metadata = option.map(message.metadata, wire.dynamic_to_json)
      use contents <- result.try(
        socket.container_contents(message.contents)
        |> result.map_error(fn(error) {
          fluid_summary.MalformedEntry("/gc/__gc_root", error)
        }),
      )
      use batch <- result.try(
        fluid_container.decode(contents, metadata)
        |> result.map_error(fn(error) {
          fluid_summary.MalformedEntry("/gc/__gc_root", string.inspect(error))
        }),
      )
      use edges <- result.try(
        list.try_map(batch.messages, fn(item) {
          case item.kind {
            fluid_container.ChannelOperation(route, contents) ->
              handle.collect_routed_addresses(
                contents,
                "/" <> fluid_summary.encode_component(route.data_store_id),
              )
              |> result.map(fn(paths) {
                let source = route_path(route)
                list.map(paths, fn(path) { #(source, "/" <> path) })
              })
              |> result.map_error(fn(error) {
                fluid_summary.MalformedEntry(
                  "/gc/__gc_root",
                  string.inspect(error),
                )
              })
            fluid_container.ChannelAttach(route, _, snapshot) -> {
              use references <- result.try(attach_snapshot_references(
                snapshot,
                "/" <> fluid_summary.encode_component(route.data_store_id),
              ))
              let datastore =
                "/" <> fluid_summary.encode_component(route.data_store_id)
              let channel = route_path(route)
              Ok([
                #(datastore, channel),
                #(channel, datastore),
                ..list.map(references, fn(target) { #(channel, target) })
              ])
            }
            fluid_container.DatastoreAttach(store, contents) -> {
              use snapshot <- result.try(
                json.parse(
                  json.to_string(contents),
                  decode.at(["snapshot"], wire.json_value_decoder()),
                )
                |> result.map_error(fn(_) {
                  fluid_summary.MalformedEntry(
                    "/gc/__gc_root",
                    "invalid datastore attach snapshot",
                  )
                }),
              )
              use references <- result.try(attach_snapshot_references(
                snapshot,
                "/" <> fluid_summary.encode_component(store),
              ))
              let source = "/" <> fluid_summary.encode_component(store)
              Ok(list.map(references, fn(target) { #(source, target) }))
            }
            fluid_container.IdAllocation(_)
            | fluid_container.DatastoreAlias(_, _) -> Ok([])
          }
        }),
      )
      Ok(#(gc, list.unique(list.append(intervening, list.flatten(edges)))))
    }
    _ -> Ok(#(gc, intervening))
  }
}

fn route_path(route: fluid_container.Route) -> String {
  "/"
  <> fluid_summary.encode_component(route.data_store_id)
  <> "/"
  <> fluid_summary.encode_component(route.channel_id)
}

fn attach_snapshot_references(
  snapshot: Json,
  context: String,
) -> Result(List(String), SummaryError) {
  use entries <- result.try(
    json.parse(
      json.to_string(snapshot),
      decode.at(["entries"], decode.list(wire.json_value_decoder())),
    )
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry("/gc/__gc_root", "invalid attach entries")
    }),
  )
  use references <- result.try(
    list.try_map(entries, fn(entry) {
      use kind <- result.try(text(entry, ["type"], "/gc/__gc_root"))
      case kind {
        "Tree" -> {
          use child <- result.try(
            json.parse(
              json.to_string(entry),
              decode.at(["value"], wire.json_value_decoder()),
            )
            |> result.map_error(fn(_) {
              fluid_summary.MalformedEntry(
                "/gc/__gc_root",
                "invalid attach subtree",
              )
            }),
          )
          attach_snapshot_references(child, context)
        }
        "Blob" -> {
          use encoding <- result.try(text(
            entry,
            ["value", "encoding"],
            "/gc/__gc_root",
          ))
          use _ <- result.try(require(
            encoding == "utf-8",
            "/gc/__gc_root",
            "unsupported attach blob encoding",
          ))
          use raw <- result.try(text(
            entry,
            ["value", "contents"],
            "/gc/__gc_root",
          ))
          use value <- result.try(
            json.parse(raw, wire.json_value_decoder())
            |> result.map_error(fn(_) {
              fluid_summary.MalformedEntry(
                "/gc/__gc_root",
                "invalid attach blob JSON",
              )
            }),
          )
          handle.collect_routed_addresses(value, context)
          |> result.map(fn(paths) { list.map(paths, fn(path) { "/" <> path }) })
          |> result.map_error(fn(error) {
            fluid_summary.MalformedEntry("/gc/__gc_root", string.inspect(error))
          })
        }
        _ ->
          Error(fluid_summary.UnsupportedEntry(
            "/gc/__gc_root",
            "unsupported attach entry",
          ))
      }
    }),
  )
  Ok(list.flatten(references))
}

fn update_routes(
  nodes: Dict(String, Json),
  path: String,
  routes: List(String),
) -> Result(Dict(String, Json), SummaryError) {
  let original = case dict.get(nodes, path) {
    Ok(node) -> node
    Error(_) -> json.object([])
  }
  use node <- result.try(replace_member(
    original,
    "outboundRoutes",
    json.array(
      list.sort(list.unique(routes), canonical_json.compare),
      json.string,
    ),
    "/gc/__gc_root" <> path,
  ))
  Ok(dict.insert(nodes, path, node))
}

fn advance_members(
  members: Json,
  ids: List(String),
  message: SequencedDocumentMessage,
) -> Result(#(Json, List(String)), SummaryError) {
  use entries <- result.try(
    json.parse(
      json.to_string(members),
      decode.list(decode.list(wire.json_value_decoder())),
    )
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry(
        "/.protocol/quorumMembers",
        "invalid member table",
      )
    }),
  )
  case message.message_type {
    "join" -> {
      use raw <- result.try(case message.data {
        Some(raw) -> Ok(raw)
        None ->
          Error(fluid_summary.MalformedEntry(
            "/.protocol/quorumMembers",
            "join has no data",
          ))
      })
      use joining <- result.try(
        json.parse(raw, wire.json_value_decoder())
        |> result.map_error(fn(_) {
          fluid_summary.MalformedEntry(
            "/.protocol/quorumMembers",
            "invalid join data",
          )
        }),
      )
      use id <- result.try(text(
        joining,
        ["clientId"],
        "/.protocol/quorumMembers",
      ))
      use detail <- result.try(
        json.parse(
          json.to_string(joining),
          decode.at(["detail"], wire.json_value_decoder()),
        )
        |> result.map_error(fn(_) {
          fluid_summary.MalformedEntry(
            "/.protocol/quorumMembers",
            "join has no client details",
          )
        }),
      )
      use _ <- result.try(require(
        !list.contains(ids, id),
        "/.protocol/quorumMembers",
        "duplicate joined member",
      ))
      let record =
        json.object([
          #("client", detail),
          #("sequenceNumber", json.int(message.sequence_number)),
        ])
      Ok(#(
        json.array(list.append(entries, [[json.string(id), record]]), fn(pair) {
          json.array(pair, fn(value) { value })
        }),
        list.append(ids, [id]),
      ))
    }
    "leave" -> {
      use raw <- result.try(case message.data {
        Some(raw) -> Ok(raw)
        None ->
          Error(fluid_summary.MalformedEntry(
            "/.protocol/quorumMembers",
            "leave has no data",
          ))
      })
      use id <- result.try(
        json.parse(raw, decode.string)
        |> result.map_error(fn(_) {
          fluid_summary.MalformedEntry(
            "/.protocol/quorumMembers",
            "invalid leave identity",
          )
        }),
      )
      let id = case list.contains(ids, id) {
        True -> id
        False -> "native:" <> int.to_string(client_id.to_int(id))
      }
      use _ <- result.try(require(
        list.contains(ids, id),
        "/.protocol/quorumMembers",
        "unknown leaving member",
      ))
      let remaining =
        list.filter(entries, fn(pair) {
          case pair {
            [first, _] -> first != json.string(id)
            _ -> False
          }
        })
      Ok(#(
        json.array(remaining, fn(pair) { json.array(pair, fn(value) { value }) }),
        list.filter(ids, fn(member) { member != id }),
      ))
    }
    _ -> Ok(#(members, ids))
  }
}

fn last_message(
  message: SequencedDocumentMessage,
) -> Result(Json, SummaryError) {
  Ok(
    json.object([
      #("clientId", case message.client_id {
        Some(id) -> json.string(id)
        None -> json.null()
      }),
      #("clientSequenceNumber", json.int(message.client_sequence_number)),
      #("minimumSequenceNumber", json.int(message.minimum_sequence_number)),
      #("referenceSequenceNumber", json.int(message.reference_sequence_number)),
      #("sequenceNumber", json.int(message.sequence_number)),
      #("timestamp", json.int(message.timestamp)),
      #("type", json.string(message.message_type)),
    ]),
  )
}

pub fn check_batch(
  summary: DocumentSummary,
  message: SequencedDocumentMessage,
) -> Result(Nil, SummaryError) {
  use identity <- result.try(effective_batch_id(message))
  case identity, summary.recent_batches {
    Some(identity), Some(records) -> {
      use entries <- result.try(
        json.parse(
          json.to_string(records),
          decode.list(decode.list(wire.json_value_decoder())),
        )
        |> result.map_error(fn(_) {
          fluid_summary.MalformedEntry(
            "/.recentBatchInfo",
            "invalid batch table",
          )
        }),
      )
      require(
        !list.any(entries, fn(entry) {
          case entry {
            [position, recorded] ->
              case json.parse(json.to_string(position), decode.int) {
                Ok(sequence) ->
                  sequence >= message.minimum_sequence_number
                  && recorded == json.string(identity)
                Error(_) -> False
              }
            _ -> False
          }
        }),
        "/.recentBatchInfo",
        "duplicate batch identity",
      )
    }
    _, _ -> Ok(Nil)
  }
}

fn effective_batch_id(
  message: SequencedDocumentMessage,
) -> Result(Option(String), SummaryError) {
  case message.message_type, message.client_id {
    "op", Some(id) -> {
      use explicit <- result.try(case message.metadata {
        Some(raw) ->
          decode.run(raw, {
            use id <- decode.optional_field(
              "batchId",
              None,
              decode.map(decode.string, Some),
            )
            decode.success(id)
          })
          |> result.map_error(fn(_) {
            fluid_summary.MalformedEntry(
              "/.recentBatchInfo",
              "invalid batch ID",
            )
          })
        None -> Ok(None)
      })
      case explicit {
        Some(id) -> {
          use _ <- result.try(require(
            id != "",
            "/.recentBatchInfo",
            "empty batch ID",
          ))
          Ok(Some(id))
        }
        None ->
          Ok(Some(
            id <> "_[" <> int.to_string(message.client_sequence_number) <> "]",
          ))
      }
    }
    _, _ -> Ok(None)
  }
}

fn advance_batches(
  previous: Option(Json),
  message: SequencedDocumentMessage,
) -> Result(Option(Json), SummaryError) {
  use entries <- result.try(case previous {
    Some(value) ->
      json.parse(
        json.to_string(value),
        decode.list(decode.list(wire.json_value_decoder())),
      )
      |> result.map_error(fn(_) {
        fluid_summary.MalformedEntry("/.recentBatchInfo", "invalid batch table")
      })
    None -> Ok([])
  })
  use retained <- result.try(
    list.try_fold(entries, [], fn(retained, pair) {
      use sequence <- result.try(case pair {
        [number, _] ->
          json.parse(json.to_string(number), decode.int)
          |> result.map_error(fn(_) {
            fluid_summary.MalformedEntry(
              "/.recentBatchInfo",
              "invalid batch sequence",
            )
          })
        _ ->
          Error(fluid_summary.MalformedEntry(
            "/.recentBatchInfo",
            "invalid batch record",
          ))
      })
      Ok(case sequence < message.minimum_sequence_number {
        True -> retained
        False -> list.append(retained, [pair])
      })
    }),
  )
  use identity <- result.try(effective_batch_id(message))
  let retained = case identity {
    Some(id) ->
      list.append(retained, [
        [
          json.int(message.sequence_number),
          json.string(id),
        ],
      ])
    None -> retained
  }
  Ok(case retained {
    [] -> None
    _ ->
      Some(
        json.array(retained, fn(pair) { json.array(pair, fn(value) { value }) }),
      )
  })
}

fn validate_batches(
  value: Json,
  sequence_number: Int,
) -> Result(Nil, SummaryError) {
  use entries <- result.try(
    json.parse(
      json.to_string(value),
      decode.list(decode.list(wire.json_value_decoder())),
    )
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry("/.recentBatchInfo", "invalid batch table")
    }),
  )
  list.try_each(entries, fn(entry) {
    use #(position, identity) <- result.try(case entry {
      [position, identity] -> {
        use position <- result.try(
          json.parse(json.to_string(position), decode.int)
          |> result.map_error(fn(_) {
            fluid_summary.MalformedEntry(
              "/.recentBatchInfo",
              "invalid batch sequence",
            )
          }),
        )
        use identity <- result.try(
          json.parse(json.to_string(identity), decode.string)
          |> result.map_error(fn(_) {
            fluid_summary.MalformedEntry(
              "/.recentBatchInfo",
              "invalid batch identity",
            )
          }),
        )
        Ok(#(position, identity))
      }
      _ ->
        Error(fluid_summary.MalformedEntry(
          "/.recentBatchInfo",
          "invalid batch record",
        ))
    })
    require(
      position >= 0 && position <= sequence_number && identity != "",
      "/.recentBatchInfo",
      "invalid batch position or identity",
    )
  })
}

fn replace_member(
  object: Json,
  key: String,
  value: Json,
  path: String,
) -> Result(Json, SummaryError) {
  use fields <- result.try(
    json.parse(
      json.to_string(object),
      decode.dict(decode.string, wire.json_value_decoder()),
    )
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry(path, "invalid metadata object")
    }),
  )
  Ok(json.object(dict.insert(fields, key, value) |> dict.to_list))
}

fn json_entry(value: Json) -> SummaryEntry {
  SummaryBlob(<<json.to_string(value):utf8>>)
}

fn tree_entries(
  tree: SummaryEntry,
  path: String,
) -> Result(List(#(String, SummaryEntry)), SummaryError) {
  case tree {
    SummaryTree(entries) -> Ok(entries)
    _ -> Error(fluid_summary.WrongKind(path, fluid_summary.TreeHandle))
  }
}

fn find(
  tree: SummaryEntry,
  parts: List(String),
) -> Result(SummaryEntry, SummaryError) {
  case parts {
    [] -> Ok(tree)
    [name, ..rest] -> {
      use entries <- result.try(tree_entries(tree, "/" <> name))
      use value <- result.try(
        list.key_find(entries, name)
        |> result.replace_error(fluid_summary.MissingEntry(
          "/" <> string.join(parts, "/"),
        )),
      )
      find(value, rest)
    }
  }
}

fn required(
  tree: SummaryEntry,
  parts: List(String),
) -> Result(SummaryEntry, SummaryError) {
  find(tree, parts)
}

fn blob(
  tree: SummaryEntry,
  parts: List(String),
) -> Result(String, SummaryError) {
  use entry <- result.try(required(tree, parts))
  let path = "/" <> string.join(parts, "/")
  case entry {
    SummaryBlob(bytes) ->
      bit_array.to_string(bytes)
      |> result.map_error(fn(_) {
        fluid_summary.MalformedEntry(path, "invalid UTF-8")
      })
    _ -> Error(fluid_summary.WrongKind(path, fluid_summary.BlobHandle))
  }
}

fn json_blob(
  tree: SummaryEntry,
  parts: List(String),
  parent: String,
) -> Result(Json, SummaryError) {
  use raw <- result.try(blob(tree, parts))
  json.parse(raw, wire.json_value_decoder())
  |> result.map_error(fn(_) {
    fluid_summary.MalformedEntry(
      parent <> "/" <> string.join(parts, "/"),
      "invalid JSON",
    )
  })
}

fn integer(
  source: Json,
  path: List(String),
  location: String,
) -> Result(Int, SummaryError) {
  json.parse(json.to_string(source), decode.at(path, decode.int))
  |> result.map_error(fn(_) {
    fluid_summary.MalformedEntry(
      location,
      "missing integer: " <> string.join(path, "."),
    )
  })
}

fn text(
  source: Json,
  path: List(String),
  location: String,
) -> Result(String, SummaryError) {
  json.parse(json.to_string(source), decode.at(path, decode.string))
  |> result.map_error(fn(_) {
    fluid_summary.MalformedEntry(
      location,
      "missing text: " <> string.join(path, "."),
    )
  })
}

fn version(
  source: Json,
  path: List(String),
  expected: Int,
  location: String,
) -> Result(Nil, SummaryError) {
  use actual <- result.try(integer(source, path, location))
  require(
    actual == expected,
    location,
    "unsupported version: " <> string.join(path, "."),
  )
}

fn require(
  valid: Bool,
  location: String,
  detail: String,
) -> Result(Nil, SummaryError) {
  case valid {
    True -> Ok(Nil)
    False -> Error(fluid_summary.MalformedEntry(location, detail))
  }
}

fn alias_pairs(value: Json) -> Result(List(#(String, String)), SummaryError) {
  use pairs <- result.try(
    json.parse(json.to_string(value), decode.list(decode.list(decode.string)))
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry("/.aliases", "invalid alias table")
    }),
  )
  list.try_map(pairs, fn(pair) {
    case pair {
      [alias, datastore] -> Ok(#(alias, datastore))
      _ ->
        Error(fluid_summary.MalformedEntry("/.aliases", "invalid alias pair"))
    }
  })
}

fn member_ids(value: Json) -> Result(List(String), SummaryError) {
  use pairs <- result.try(
    json.parse(json.to_string(value), decode.list(decode.list(decode.dynamic)))
    |> result.map_error(fn(_) {
      fluid_summary.MalformedEntry(
        "/.protocol/quorumMembers",
        "invalid member table",
      )
    }),
  )
  use ids <- result.try(
    list.try_map(pairs, fn(pair) {
      case pair {
        [raw, _] ->
          json.parse(json.to_string(wire.dynamic_to_json(raw)), decode.string)
          |> result.map_error(fn(_) {
            fluid_summary.MalformedEntry(
              "/.protocol/quorumMembers",
              "invalid member identity",
            )
          })
        _ ->
          Error(fluid_summary.MalformedEntry(
            "/.protocol/quorumMembers",
            "invalid member record",
          ))
      }
    }),
  )
  use _ <- result.try(require(
    list.length(ids) == list.length(list.unique(ids)),
    "/.protocol/quorumMembers",
    "duplicate member identity",
  ))
  use _ <- result.try(
    list.try_each(ids, fn(id) {
      case string.starts_with(id, "native:") {
        True ->
          int.parse(string.drop_start(id, 7))
          |> result.map(fn(_) { Nil })
          |> result.map_error(fn(_) {
            fluid_summary.MalformedEntry(
              "/.protocol/quorumMembers",
              "invalid native member identity",
            )
          })
        False -> Ok(Nil)
      }
    }),
  )
  Ok(ids)
}

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
import watershed/channel
import watershed/client_id
import watershed/fluid_ids
import watershed/handle
import watershed/tree/codec
import watershed/tree/codec/summary as summary_codec
import watershed/tree/summary as tree_summary
import watershed/wire
import watershed/wire/fluid_summary.{
  type SummaryEntry, type SummaryError, SummaryBlob, SummaryTree,
}
import watershed/wire/op as wire_op
import watershed/wire/summary_blob as inspection

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
  use gc <- result.try(json_blob(resolved, ["gc", "__gc_root"], "/gc"))
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
  Ok(DocumentSummary(
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
  ))
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
                bit_array.to_string(bytes)
                |> result.map(fn(raw) { #(entry.0, raw) })
                |> result.map_error(fn(_) {
                  fluid_summary.MalformedEntry(
                    channel_path <> "/" <> entry.0,
                    "invalid UTF-8",
                  )
                })
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
  use batches <- result.try(advance_batches(summary.recent_batches, message))
  Ok(
    DocumentSummary(
      ..summary,
      sequence_number: message.sequence_number,
      minimum_sequence_number: message.minimum_sequence_number,
      metadata:,
      protocol_members:,
      member_ids:,
      recent_batches: batches,
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
      Ok(Datastore(..store, channels: snapshots))
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
  let next =
    DocumentSummary(..summary, aliases:, datastores:, compressor:, metadata:)
  use gc <- result.try(refresh_gc(next))
  Ok(DocumentSummary(..next, gc:))
}

fn refresh_gc(summary: DocumentSummary) -> Result(Json, SummaryError) {
  use nodes <- result.try(
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
  use nodes <- result.try(
    list.try_fold(stores, nodes, fn(nodes, store) {
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
                handle.collect_routed_addresses(entry.1, path)
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
          _ -> Ok([])
        })
        update_routes(nodes, path, ["/" <> store.id, ..list.unique(links)])
      })
    }),
  )
  use nodes <- result.try(update_routes(
    nodes,
    "/",
    list.map(stores, fn(store) { "/" <> store.id }),
  ))
  replace_member(
    summary.gc,
    "gcNodes",
    json.object(dict.to_list(nodes)),
    "/gc/__gc_root",
  )
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
    json.array(routes, json.string),
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

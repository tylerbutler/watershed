//// Portable checkpoints for pending edits in persisted SharedTree documents.
////
//// The application owns durable storage. Store the checkpoint before you
//// rely on recovery. Credentials and application handles are not retained.

import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/runtime_core
import watershed/tree/branch
import watershed/tree/codec as tree_codec
import watershed/tree/recovery as tree_recovery
import watershed/tree/shared_change
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/fluid_document
import watershed/wire/fluid_summary

const max_safe_integer = 9_007_199_254_740_991

/// Capture one live sequence point. Settle ordinary DDS edits, attachments,
/// transactions, and unmerged branches before you capture a checkpoint.
pub fn capture(
  core: runtime_core.Core,
  tenant tenant: String,
  document document: String,
) -> Result(Json, String) {
  use _ <- result.try(require(
    tenant != "" && document != "" && core.client_id != "",
    "checkpoint requires document and client identities",
  ))
  use _ <- result.try(require(
    core.persistence != None
      && runtime_core.has_tree(core)
      && core.ingest == runtime_core.Live
      && core.reconnect_barrier == None
      && core.active_tree_transaction == None
      && core.active_tree_transaction_checkouts == None
      && core.out_of_order == []
      && dict.size(core.detached) == 0
      && dict.size(core.local_datastores) == 0
      && core.prepared_attachments == []
      && dict.size(core.owed) == 0,
    "checkpoint requires a live persisted document without local attachments or transactions",
  ))
  use compressor <- result.try(
    core.compressor
    |> option.to_result("checkpoint requires a document compressor"),
  )
  use serialized <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )
  use summary <- result.try(
    runtime_core.pending_summary_evidence(core)
    |> result.map_error(string.inspect),
  )
  use trees <- result.try(
    list.try_fold(core.channel_order, [], fn(trees, address) {
      use state <- result.try(
        dict.get(core.channels, address)
        |> result.replace_error("checkpoint channel is missing"),
      )
      case state {
        channel.TreeState(tree) -> {
          use encoded <- result.try(
            tree_recovery.capture(tree, compressor)
            |> result.map_error(string.inspect),
          )
          Ok(
            list.append(trees, [
              json.object([
                #("address", json.string(address)),
                #("state", encoded),
              ]),
            ]),
          )
        }
        _ -> Ok(trees)
      }
    }),
  )
  use _ <- result.try(validate_submissions(core))
  use submissions <- result.try(
    list.try_map(core.in_flight, encode_submission(_, 0)),
  )
  use bootstrap_map <- result.try(
    fluid_container.route_key(core.routing.bootstrap_map)
    |> result.map_error(string.inspect),
  )
  Ok(
    json.object([
      #("version", json.int(1)),
      #("tenant", json.string(tenant)),
      #("document", json.string(document)),
      #("clientId", json.string(core.client_id)),
      #("nextClientSequenceNumber", json.int(core.next_client_sequence_number)),
      #(
        "lastSummarySequenceNumber",
        json.int(core.last_summary_sequence_number),
      ),
      #("summaryHead", json.nullable(core.summary_head, json.string)),
      #(
        "session",
        json.string(
          fluid_ids.session_id_to_string(fluid_ids.local_session(compressor)),
        ),
      ),
      #("compressor", serialized),
      #("summary", summary),
      #("trees", json.array(trees, fn(value) { value })),
      #("submissions", json.array(submissions, fn(value) { value })),
      #(
        "bindings",
        json.array(dict.to_list(core.bindings), fn(entry) {
          json.object([
            #("address", json.string(entry.0)),
            #(
              "references",
              json.array(entry.1, fn(reference) {
                json.string(handle.reference_path(reference))
              }),
            ),
          ])
        }),
      ),
      #("bootstrapMap", json.string(bootstrap_map)),
    ]),
  )
}

/// Validate and restore a checkpoint before a transport starts. Supply a new
/// view ID. Reconnect must catch up before it resubmits the saved edits.
pub fn restore(
  data: Json,
  tenant tenant: String,
  document document: String,
  view_id view_id: fluid_ids.StableId,
) -> Result(runtime_core.Core, String) {
  use version <- result.try(field(data, "version", decode.int))
  use _ <- result.try(require(version == 1, "unsupported checkpoint version"))
  use saved_tenant <- result.try(field(data, "tenant", decode.string))
  use saved_document <- result.try(field(data, "document", decode.string))
  use _ <- result.try(require(
    saved_tenant == tenant
      && saved_document == document
      && tenant != ""
      && document != "",
    "checkpoint belongs to a different document",
  ))
  use client_id <- result.try(field(data, "clientId", decode.string))
  use next_csn <- result.try(field(data, "nextClientSequenceNumber", decode.int))
  use last_summary <- result.try(field(
    data,
    "lastSummarySequenceNumber",
    decode.int,
  ))
  use summary_head <- result.try(field(
    data,
    "summaryHead",
    decode.optional(decode.string),
  ))
  use _ <- result.try(require(
    client_id != "" && safe(next_csn) && next_csn > 0 && safe(last_summary),
    "invalid checkpoint client sequence metadata",
  ))
  use session <- result.try(field(data, "session", decode.string))
  use session <- result.try(
    fluid_ids.session_id(session) |> result.map_error(string.inspect),
  )
  use serialized <- result.try(field(
    data,
    "compressor",
    wire.json_value_decoder(),
  ))
  use compressor <- result.try(
    fluid_ids.deserialize(serialized, session)
    |> result.map_error(string.inspect),
  )
  use new_session <- result.try(
    fluid_ids.session_id(fluid_ids.stable_id_to_string(view_id))
    |> result.map_error(string.inspect),
  )
  use evidence <- result.try(field(data, "summary", wire.json_value_decoder()))
  use sequence_number <- result.try(field(
    evidence,
    "sequenceNumber",
    decode.int,
  ))
  use entry <- result.try(field(evidence, "tree", wire.json_value_decoder()))
  use entry <- result.try(decode_summary(entry, 0))
  use summary <- result.try(
    fluid_document.decode(entry, None, new_session, view_id)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(require(
    safe(sequence_number)
      && sequence_number == fluid_document.sequence_number(summary)
      && last_summary <= sequence_number,
    "invalid checkpoint sequence watermark",
  ))
  use _ <- result.try(
    runtime_core.document_seed(summary) |> result.map_error(string.inspect),
  )
  let minimum = fluid_document.minimum_sequence_number(summary)
  use encoded_trees <- result.try(field(
    data,
    "trees",
    decode.list({
      use address <- decode.field("address", decode.string)
      use state <- decode.field("state", wire.json_value_decoder())
      decode.success(#(address, state))
    }),
  ))
  use _ <- result.try(unique(encoded_trees))
  use trees <- result.try(
    list.try_map(encoded_trees, fn(entry) {
      use tree <- result.try(
        tree_recovery.restore(entry.1, view_id, compressor)
        |> result.map_error(string.inspect),
      )
      let sequenced = tree_kernel.history_view(tree).sequenced
      use _ <- result.try(require(
        sequenced.sequence_number == sequence_number
          && sequenced.minimum_sequence_number == minimum,
        "checkpoint tree has a different sequence watermark",
      ))
      Ok(#(entry.0, tree))
    }),
  )
  let stores = fluid_document.datastores(summary)
  use entries <- result.try(
    stores
    |> list.flat_map(fn(store) {
      list.map(store.channels, fn(item) {
        #(fluid_container.Route(store.id, item.id), item)
      })
    })
    |> list.try_map(fn(entry) {
      use address <- result.try(
        fluid_container.route_key(entry.0) |> result.map_error(string.inspect),
      )
      Ok(#(address, entry.1))
    }),
  )
  use channels <- result.try(
    list.try_map(entries, fn(entry) {
      use state <- result.try(case entry.1.snapshot {
        channel.TreeSnapshot(_) ->
          list.key_find(trees, entry.0)
          |> result.map(channel.TreeState)
          |> result.replace_error("checkpoint is missing a tree")
        snapshot -> channel.from_snapshot(snapshot, replica: client_id)
      })
      Ok(#(entry.0, state))
    }),
  )
  use _ <- result.try(require(
    trees != []
      && list.length(trees)
      == list.count(channels, fn(entry) {
      channel.channel_type(entry.1) == channel.TreeChannel
    }),
    "checkpoint contains an unknown tree",
  ))
  use root <- result.try(field(data, "bootstrapMap", decode.string))
  use bootstrap_map <- result.try(
    fluid_container.route_from_path("/" <> root)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(require(
    case list.key_find(channels, root) {
      Ok(channel.MapState(_)) ->
        list.key_find(fluid_document.aliases(summary), "root")
        == Ok(bootstrap_map.data_store_id)
      _ -> False
    },
    "checkpoint bootstrap map is missing",
  ))
  use encoded_bindings <- result.try(field(
    data,
    "bindings",
    decode.list({
      use address <- decode.field("address", decode.string)
      use references <- decode.field("references", decode.list(decode.string))
      decode.success(#(address, references))
    }),
  ))
  use _ <- result.try(unique(encoded_bindings))
  use bindings <- result.try(
    list.try_map(encoded_bindings, fn(entry) {
      use _ <- result.try(require(
        list.key_find(channels, entry.0) |> result.is_ok,
        "checkpoint binding belongs to an unknown channel",
      ))
      use references <- result.try(
        list.try_map(entry.1, fn(path) {
          handle.reference_from_path(path) |> result.map_error(string.inspect)
        }),
      )
      Ok(#(entry.0, references))
    }),
  )
  use submissions <- result.try(field(
    data,
    "submissions",
    decode.list(wire.json_value_decoder()),
  ))
  use in_flight <- result.try(
    list.try_map(submissions, decode_submission(_, 0)),
  )
  let core =
    runtime_core.Core(
      client_id: client_id,
      alias_claims: dict.new(),
      routing: runtime_core.Routing(
        runtime_core.RoutedSeed,
        dict.from_list(
          list.map(stores, fn(store) { #(store.id, store.package_path) }),
        ),
        dict.from_list(fluid_document.aliases(summary)),
        dict.from_list(
          list.map(entries, fn(entry) { #(entry.0, entry.1.attributes) }),
        ),
        bootstrap_map,
      ),
      compressor: Some(compressor),
      tree_checkouts: list.fold(trees, dict.new(), fn(checkouts, entry) {
        dict.insert(
          checkouts,
          entry.0,
          branch.new(branch.origin(client_id, "document", entry.0), entry.1),
        )
      }),
      tree_publication_scopes: dict.new(),
      active_tree_transaction: None,
      active_tree_transaction_checkouts: None,
      persistence: Some(summary),
      minimum_sequence_number: minimum,
      channels: dict.from_list(channels),
      channel_order: list.map(entries, fn(entry) { entry.0 }),
      detached: dict.new(),
      local_datastores: dict.new(),
      bindings: dict.from_list(bindings),
      prepared_attachments: [],
      next_client_sequence_number: next_csn,
      last_seen_sequence_number: sequence_number,
      in_flight: in_flight,
      out_of_order: [],
      reconnect_barrier: None,
      recovery_replay: None,
      members: set.from_list(fluid_document.members(summary)),
      live_members: set.from_list(fluid_document.members(summary)),
      ingest: runtime_core.Live,
      last_summary_sequence_number: last_summary,
      summary_head: summary_head,
      owed: dict.new(),
    )
  use _ <- result.try(validate_submissions(core))
  use sequenced_channels <- result.try(
    list.try_map(entries, fn(entry) {
      use state <- result.try(case entry.1.snapshot {
        channel.TreeSnapshot(snapshot) ->
          tree_kernel.restore_unviewed(snapshot, view_id, new_session)
          |> result.map(channel.TreeState)
          |> result.map_error(string.inspect)
        snapshot -> channel.from_snapshot(snapshot, replica: client_id)
      })
      Ok(#(entry.0, state))
    }),
  )
  let sequenced_channels = dict.from_list(sequenced_channels)
  // Replay the base with a fresh session for accepted edits after this checkpoint.
  // Switch only after the server acknowledges all saved submissions.
  let sequenced =
    runtime_core.Core(
      ..core,
      client_id: fluid_ids.session_id_to_string(new_session),
      compressor: fluid_document.compressor(summary),
      channels: sequenced_channels,
      tree_checkouts: dict.fold(
        sequenced_channels,
        dict.new(),
        fn(checkouts, address, state) {
          case state {
            channel.TreeState(tree) ->
              dict.insert(
                checkouts,
                address,
                branch.new(branch.origin(client_id, "document", address), tree),
              )
            _ -> checkouts
          }
        },
      ),
      in_flight: [],
      ingest: runtime_core.Replaying,
    )
  Ok(
    runtime_core.Core(
      ..core,
      recovery_replay: Some(runtime_core.RecoveryReplay(
        sequenced,
        dict.from_list([#(sequence_number, core)]),
      )),
    ),
  )
}

fn validate_submissions(core: runtime_core.Core) -> Result(Nil, String) {
  use _ <- result.try(
    list.try_fold(core.in_flight, #(0, set.new()), fn(acc, entry) {
      let #(previous, batch_ids) = acc
      case entry {
        runtime_core.InFlightBatch(
          client_id,
          csn,
          rsn,
          grouped,
          batch_id,
          items,
          pending,
        ) -> {
          let needs_batch_id = case items {
            [
              fluid_container.IdAllocation(fluid_ids.CreationRange(
                ids: Some(fluid_ids.RangeIds(local_id_ranges: [_, ..], ..)),
                ..,
              )),
              ..
            ] -> True
            _ -> False
          }
          use batch_ids <- result.try(case batch_id {
            Some(id) -> {
              use _ <- result.try(require(
                id != "" && !set.contains(batch_ids, id),
                "invalid checkpoint batch identity",
              ))
              Ok(set.insert(batch_ids, id))
            }
            None -> {
              use _ <- result.try(require(
                !needs_batch_id,
                "checkpoint batch identity is missing",
              ))
              Ok(batch_ids)
            }
          })
          use _ <- result.try(require(
            client_id == core.client_id
              && csn > previous
              && csn < core.next_client_sequence_number
              && safe(rsn)
              && rsn <= core.last_seen_sequence_number
              && items != []
              && { grouped || list.length(items) == 1 }
              && {
              pending == []
              || list.length(pending) == list.length(items)
              && list.length(pending) > 1
            },
            "invalid checkpoint submission metadata",
          ))
          use _ <- result.try(
            list.try_map(items, fn(item) {
              case item {
                fluid_container.IdAllocation(_) -> Ok(Nil)
                fluid_container.ChannelOperation(route, _) -> {
                  use address <- result.try(
                    fluid_container.route_key(route)
                    |> result.map_error(string.inspect),
                  )
                  require(
                    case dict.get(core.channels, address) {
                      Ok(channel.TreeState(_)) -> True
                      _ -> False
                    },
                    "checkpoint does not support pending ordinary DDS operations",
                  )
                }
                _ ->
                  Error(
                    "checkpoint does not support pending attachments or aliases",
                  )
              }
            }),
          )
          use _ <- result.try(
            list.try_map(list.zip(items, pending), fn(pair) {
              case pair.1 {
                runtime_core.InFlightBatch(
                  client,
                  sequence,
                  reference,
                  False,
                  None,
                  [item],
                  [],
                ) -> {
                  use encoded <- result.try(
                    fluid_container.encode(item)
                    |> result.map_error(string.inspect),
                  )
                  use expected <- result.try(
                    fluid_container.encode(pair.0)
                    |> result.map_error(string.inspect),
                  )
                  require(
                    client == client_id
                      && sequence == csn
                      && safe(reference)
                      && reference <= core.last_seen_sequence_number
                      && json.to_string(encoded) == json.to_string(expected),
                    "checkpoint nested submission does not match its batch",
                  )
                }
                _ -> Error("unsupported checkpoint nested submission")
              }
            }),
          )
          Ok(#(csn, batch_ids))
        }
        _ ->
          Error(
            "checkpoint does not support pending ordinary DDS operations or attachments",
          )
      }
    }),
  )
  use compressor <- result.try(
    core.compressor
    |> option.to_result("checkpoint requires a document compressor"),
  )
  use _ <- result.try(validate_pending_order(core, compressor))
  use _ <- result.try(
    runtime_core.resubmit(core) |> result.map_error(string.inspect),
  )
  Ok(Nil)
}

fn validate_pending_order(
  core: runtime_core.Core,
  compressor: fluid_ids.Compressor,
) -> Result(Nil, String) {
  let pending =
    dict.fold(core.channels, dict.new(), fn(pending, address, state) {
      case state {
        channel.TreeState(tree) ->
          dict.insert(pending, address, tree_kernel.history_view(tree).pending)
        _ -> pending
      }
    })
  use remaining <- result.try(
    list.try_fold(core.in_flight, pending, fn(pending, batch) {
      case batch {
        runtime_core.InFlightBatch(items: items, ..) ->
          list.try_fold(items, pending, fn(pending, item) {
            case item {
              fluid_container.IdAllocation(_) -> Ok(pending)
              fluid_container.ChannelOperation(route, contents) -> {
                use address <- result.try(
                  fluid_container.route_key(route)
                  |> result.map_error(string.inspect),
                )
                use expected <- result.try(
                  dict.get(pending, address)
                  |> result.replace_error(
                    "checkpoint submission has no tree history",
                  ),
                )
                case expected {
                  [] -> Error("checkpoint has an extra tree submission")
                  [first, ..rest] -> {
                    use message <- result.try(
                      tree_codec.decode_message(
                        json.to_string(contents),
                        tree_codec.DecodeContext(
                          tree_codec.Fluid310,
                          compressor,
                        ),
                      )
                      |> result.map_error(string.inspect),
                    )
                    use _ <- result.try(require(
                      message.commit.revision == first.revision
                        && message.commit.originator == first.originator,
                      "checkpoint submissions do not follow pending tree history",
                    ))
                    use _ <- result.try(require(
                      message.extra_fields == []
                        && message.commit.custom_metadata == None,
                      "checkpoint submission has unsupported tree metadata",
                    ))
                    use _ <- result.try(
                      shared_change.from_changes(message.commit.changes)
                      |> result.map_error(string.inspect),
                    )
                    Ok(dict.insert(pending, address, rest))
                  }
                }
              }
              _ -> Error("unsupported checkpoint submission")
            }
          })
        _ -> Error("unsupported checkpoint submission")
      }
    }),
  )
  require(
    list.all(dict.values(remaining), fn(commits) { commits == [] }),
    "checkpoint pending history has no submission",
  )
}

fn encode_submission(
  entry: runtime_core.InFlight,
  depth: Int,
) -> Result(Json, String) {
  use _ <- result.try(require(
    depth < 16,
    "checkpoint submission nesting limit exceeded",
  ))
  case entry {
    runtime_core.InFlightBatch(
      client_id,
      csn,
      rsn,
      grouped,
      batch_id,
      items,
      pending,
    ) -> {
      use items <- result.try(
        list.try_map(items, fn(item) {
          fluid_container.encode(item) |> result.map_error(string.inspect)
        }),
      )
      use pending <- result.try(
        list.try_map(pending, encode_submission(_, depth + 1)),
      )
      Ok(
        json.object([
          #("clientId", json.string(client_id)),
          #("clientSequenceNumber", json.int(csn)),
          #("referenceSequenceNumber", json.int(rsn)),
          #("grouped", json.bool(grouped)),
          #("batchId", json.nullable(batch_id, json.string)),
          #("items", json.array(items, fn(value) { value })),
          #("pending", json.array(pending, fn(value) { value })),
        ]),
      )
    }
    _ -> Error("unsupported checkpoint submission")
  }
}

fn decode_submission(
  data: Json,
  depth: Int,
) -> Result(runtime_core.InFlight, String) {
  use _ <- result.try(require(
    depth < 16,
    "checkpoint submission nesting limit exceeded",
  ))
  use client <- result.try(field(data, "clientId", decode.string))
  use csn <- result.try(field(data, "clientSequenceNumber", decode.int))
  use rsn <- result.try(field(data, "referenceSequenceNumber", decode.int))
  use grouped <- result.try(field(data, "grouped", decode.bool))
  use batch_id <- result.try(field(
    data,
    "batchId",
    decode.optional(decode.string),
  ))
  use items <- result.try(field(
    data,
    "items",
    decode.list(wire.json_value_decoder()),
  ))
  use pending <- result.try(field(
    data,
    "pending",
    decode.list(wire.json_value_decoder()),
  ))
  use items <- result.try(
    list.try_map(items, fn(item) {
      use batch <- result.try(
        fluid_container.decode(item, None) |> result.map_error(string.inspect),
      )
      case batch.messages {
        [fluid_container.ContainerMessage(kind, 0, None)] if !batch.grouped ->
          Ok(kind)
        _ -> Error("checkpoint item is not one container operation")
      }
    }),
  )
  use pending <- result.try(
    list.try_map(pending, decode_submission(_, depth + 1)),
  )
  Ok(runtime_core.InFlightBatch(
    client,
    csn,
    rsn,
    grouped,
    batch_id,
    items,
    pending,
  ))
}

fn decode_summary(
  data: Json,
  depth: Int,
) -> Result(fluid_summary.SummaryEntry, String) {
  use _ <- result.try(require(
    depth < 128,
    "checkpoint summary nesting limit exceeded",
  ))
  use kind <- result.try(field(data, "type", decode.string))
  case kind {
    "blob" -> {
      use encoded <- result.try(field(data, "base64", decode.string))
      use bytes <- result.try(
        bit_array.base64_decode(encoded)
        |> result.replace_error("invalid checkpoint blob"),
      )
      Ok(fluid_summary.SummaryBlob(bytes))
    }
    "tree" -> {
      use entries <- result.try(field(
        data,
        "entries",
        decode.list({
          use name <- decode.field(0, decode.string)
          use value <- decode.field(1, wire.json_value_decoder())
          decode.success(#(name, value))
        }),
      ))
      use _ <- result.try(unique(entries))
      use entries <- result.try(
        list.try_map(entries, fn(entry) {
          use value <- result.try(decode_summary(entry.1, depth + 1))
          Ok(#(entry.0, value))
        }),
      )
      Ok(fluid_summary.SummaryTree(entries))
    }
    _ -> Error("unsupported checkpoint summary entry")
  }
}

fn field(
  data: Json,
  key: String,
  decoder: decode.Decoder(value),
) -> Result(value, String) {
  json.parse(json.to_string(data), decode.at([key], decoder))
  |> result.map_error(fn(error) {
    "invalid checkpoint field " <> key <> ": " <> string.inspect(error)
  })
}

fn unique(entries: List(#(String, value))) -> Result(Nil, String) {
  require(
    list.length(entries) == dict.size(dict.from_list(entries)),
    "duplicate checkpoint entry",
  )
}

fn safe(value: Int) -> Bool {
  value >= 0 && value <= max_safe_integer
}

fn require(condition: Bool, error: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(error)
  }
}

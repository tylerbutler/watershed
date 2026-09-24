import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import signet/types as token
import spillway/message
import spillway/types.{type SequencedDocumentMessage}
import watershed/channel
import watershed/fluid_ids
import watershed/map_kernel
import watershed/runtime_core
import watershed/sluice/frame
import watershed/tree/codec
import watershed/tree/codec/summary
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types as tree_types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/fluid_summary
import watershed/wire/op as wire_op
import watershed/wire/socket

pub type RuntimeInput {
  RuntimeInput(
    document: fluid_summary.SummaryEntry,
    tree: summary.TreeSummaryData,
    map_header: Json,
    compressor: fluid_ids.Compressor,
    sequence_number: Int,
    minimum_sequence_number: Int,
    prefix: List(SequencedDocumentMessage),
    operations: List(SequencedDocumentMessage),
  )
}

pub fn connected(
  client_id: String,
  messages: List(SequencedDocumentMessage),
  checkpoint: Int,
) -> message.ConnectedMessage {
  message.ConnectedMessage(
    claims: token.TokenClaims(
      document_id: "tree",
      scopes: [token.DocRead, token.DocWrite],
      tenant_id: "default",
      user: token.User(id: "test", properties: dict.new()),
      issued_at: 0,
      expiration: 0,
      version: "1.0",
      jti: None,
    ),
    client_id: client_id,
    existing: True,
    max_message_size: 16_000,
    mode: types.WriteMode,
    service_configuration: types.ServiceConfiguration(
      block_size: 65_536,
      max_message_size: 16_000,
      noop_time_frequency: None,
      noop_count_frequency: None,
    ),
    initial_clients: [],
    initial_messages: messages,
    initial_signals: [],
    supported_versions: ["^0.1.0"],
    supported_features: dict.new(),
    version: "^0.1.0",
    timestamp: None,
    checkpoint_sequence_number: Some(checkpoint),
    epoch: None,
    relay_service_agent: None,
    summary_context: None,
  )
}

pub fn sequenced_frame(message: SequencedDocumentMessage) -> frame.Sequenced {
  frame.Sequenced(
    client_id: message.client_id,
    sequence_number: message.sequence_number,
    minimum_sequence_number: message.minimum_sequence_number,
    client_sequence_number: message.client_sequence_number,
    reference_sequence_number: message.reference_sequence_number,
    operation_type: message.message_type,
    contents: wire.dynamic_to_json(message.contents),
    metadata: option.map(message.metadata, wire.dynamic_to_json),
    timestamp: message.timestamp,
    data: message.data,
  )
}

pub fn read(
  input: Json,
  session: fluid_ids.SessionId,
) -> Result(RuntimeInput, String) {
  use decoder_input <- result.try(field(input, "decoderInput"))
  use snapshot <- result.try(field(decoder_input, "initialSnapshot"))
  use encoding <- result.try(read_field(snapshot, "blobEncoding", decode.string))
  use Nil <- result.try(case encoding {
    "base64" -> Ok(Nil)
    _ -> Error("runtime fixture snapshot is not base64")
  })
  use tree_json <- result.try(field(snapshot, "tree"))
  use encoded_blobs <- result.try(read_field(
    snapshot,
    "blobs",
    decode.dict(decode.string, decode.string),
  ))
  use blobs <- result.try(
    encoded_blobs
    |> dict.to_list
    |> list.try_map(fn(entry) {
      use bytes <- result.try(
        bit_array.base64_decode(entry.1)
        |> result.replace_error("runtime fixture has invalid blob bytes"),
      )
      Ok(#(entry.0, bytes))
    }),
  )
  use document <- result.try(
    fluid_summary.from_snapshot(tree_json, dict.from_list(blobs))
    |> result.map_error(string.inspect),
  )
  use attributes <- result.try(blob(document, "/.protocol/attributes"))
  use sequence_number <- result.try(read_field(
    attributes,
    "sequenceNumber",
    decode.int,
  ))
  use minimum_sequence_number <- result.try(read_field(
    attributes,
    "minimumSequenceNumber",
    decode.int,
  ))
  use Nil <- result.try(
    case
      minimum_sequence_number >= 0 && minimum_sequence_number <= sequence_number
    {
      True -> Ok(Nil)
      False -> Error("runtime fixture has invalid snapshot sequence numbers")
    },
  )
  use serialized <- result.try(blob(document, "/.idCompressor"))
  use compressor <- result.try(
    fluid_ids.deserialize(serialized, session)
    |> result.map_error(string.inspect),
  )
  use tree_entry <- result.try(
    fluid_summary.resolve(
      fluid_summary.SummaryHandle(
        "/.channels/A/.channels/_C",
        fluid_summary.TreeHandle,
      ),
      Some(document),
    )
    |> result.map_error(string.inspect),
  )
  use tree_entries <- result.try(case tree_entry {
    fluid_summary.SummaryTree(entries) -> Ok(entries)
    _ -> Error("runtime fixture tree channel is not a summary tree")
  })
  use tree <- result.try(
    summary.decode(
      fluid_summary.SummaryTree(
        list.filter(tree_entries, fn(entry) { entry.0 != ".attributes" }),
      ),
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  use Nil <- result.try(case tree.history {
    summary.EditManagerSummary([], []) -> Ok(Nil)
    _ -> Error("runtime fixture requires an initial empty tree history")
  })
  use map_header <- result.try(blob(
    document,
    "/.channels/A/.channels/root/header",
  ))
  use prefix <- result.try(read_field(
    decoder_input,
    "deliveryPrefix",
    decode.list(socket.sequenced_document_message_decoder()),
  ))
  use operations <- result.try(
    json.parse(json.to_string(decoder_input), {
      decode.one_of(
        decode.at(
          ["groupedWireMessages"],
          decode.list(socket.sequenced_document_message_decoder()),
        ),
        or: [
          decode.at(
            ["bootstrapMessages"],
            decode.list(socket.sequenced_document_message_decoder()),
          ),
        ],
      )
    })
    |> result.map_error(fn(error) {
      "runtime fixture operations: " <> string.inspect(error)
    }),
  )
  use _ <- result.try(
    list.try_fold(
      list.append(prefix, operations),
      #(sequence_number, minimum_sequence_number),
      fn(previous, message) {
        case
          message.sequence_number == previous.0 + 1
          && message.minimum_sequence_number >= previous.1
          && message.minimum_sequence_number <= message.sequence_number
          && message.reference_sequence_number <= previous.0
        {
          True ->
            Ok(#(message.sequence_number, message.minimum_sequence_number))
          False -> Error("runtime fixture has an invalid delivery prefix")
        }
      },
    ),
  )
  Ok(RuntimeInput(
    document:,
    tree:,
    map_header:,
    compressor:,
    sequence_number:,
    minimum_sequence_number:,
    prefix:,
    operations:,
  ))
}

pub fn routed_seed_input() -> Result(
  #(runtime_core.BootstrapSeedInput, List(SequencedDocumentMessage)),
  String,
) {
  use fixture <- result.try(fixtures.load("batched-commits"))
  use session <- result.try(
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
    |> result.map_error(string.inspect),
  )
  use input <- result.try(read(fixture.input, session))
  use seed <- result.try(seed_input(input))
  Ok(#(seed, input.prefix))
}

fn seed_input(
  input: RuntimeInput,
) -> Result(runtime_core.BootstrapSeedInput, String) {
  use component <- result.try(blob(input.document, "/.channels/A/.component"))
  use package_json <- result.try(read_field(component, "pkg", decode.string))
  use package_path <- result.try(
    json.parse(package_json, decode.list(decode.string))
    |> result.map_error(string.inspect),
  )
  use map <- result.try(wire_op.decode_map_header(input.map_header))
  use view <- result.try(
    schema.view_from_json(schema.stored_to_json(input.tree.schema))
    |> result.map_error(string.inspect),
  )
  use view_id <- result.try(
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
    |> result.map_error(string.inspect),
  )
  use snapshot <- result.try(snapshot(
    input.tree,
    input.sequence_number,
    input.minimum_sequence_number,
    view_id,
  ))
  Ok(
    runtime_core.BootstrapSeedInput(
      profile: runtime_core.RoutedSeed,
      sequence_number: input.sequence_number,
      minimum_sequence_number: input.minimum_sequence_number,
      members: [],
      datastores: [runtime_core.DatastoreSeed("A", package_path)],
      aliases: [#("root", "A")],
      channels: [
        runtime_core.ChannelSeed(
          fluid_container.Route("A", "root"),
          channel.fluid_attributes(channel.MapChannel),
          channel.MapSnapshot(map),
        ),
        runtime_core.ChannelSeed(
          fluid_container.Route("A", "_C"),
          channel.fluid_attributes(channel.TreeChannel),
          channel.TreeSnapshot(snapshot),
        ),
      ],
      bootstrap_map: fluid_container.Route("A", "root"),
      compressor: Some(input.compressor),
      tree_views: [
        runtime_core.TreeViewSeed(
          fluid_container.Route("A", "_C"),
          view_id,
          view,
        ),
      ],
    ),
  )
}

fn checked_core(
  input: RuntimeInput,
  client_id: String,
) -> Result(runtime_core.Core, String) {
  use seed <- result.try(seed_input(input))
  use seed <- result.try(
    runtime_core.bootstrap_seed(seed) |> result.map_error(string.inspect),
  )
  use ready <- result.try(
    runtime_core.bootstrap_seeded(
      connected(
        client_id,
        input.prefix,
        input.sequence_number + list.length(input.prefix),
      ),
      seed,
    )
    |> result.map_error(string.inspect),
  )
  case ready {
    runtime_core.Complete(core) -> Ok(core)
    runtime_core.MissingPrefix(_, _, _, _) ->
      Error("runtime fixture did not replay the delivery prefix")
  }
}

fn reader_input(input: Json) -> Result(RuntimeInput, String) {
  use session <- result.try(
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
    |> result.map_error(string.inspect),
  )
  read(input, session)
}

fn root(core: runtime_core.Core) -> Result(Json, String) {
  use title <- result.try(read_tree(core, ["title"]))
  use enabled <- result.try(read_tree(core, ["enabled"]))
  use rating <- result.try(read_tree(core, ["rating"]))
  use marker <- result.try(read_tree(core, ["marker"]))
  use x <- result.try(read_tree(core, ["point", "x"]))
  use y <- result.try(read_tree(core, ["point", "y"]))
  use note <- result.try(case runtime_core.tree_read(core, "A/_C", ["note"]) {
    Ok(Some(tree_types.StringValue(value))) ->
      Ok([#("note", json.string(value))])
    Ok(None) -> Ok([])
    Ok(_) -> Error("runtime fixture note has the wrong kind")
    Error(error) -> Error(string.inspect(error))
  })
  Ok(
    json.object(list.append(
      [
        #("title", title),
        #("enabled", enabled),
        #("rating", rating),
        #("marker", marker),
        #("point", json.object([#("x", x), #("y", y)])),
      ],
      note,
    )),
  )
}

fn read_tree(
  core: runtime_core.Core,
  path: List(String),
) -> Result(Json, String) {
  use value <- result.try(
    runtime_core.tree_read(core, "A/_C", path)
    |> result.map_error(string.inspect),
  )
  case value {
    Some(tree_types.StringValue(value)) -> Ok(json.string(value))
    Some(tree_types.BooleanValue(value)) -> Ok(json.bool(value))
    Some(tree_types.NumberValue(value)) -> Ok(json.float(value))
    Some(tree_types.NullValue) -> Ok(json.null())
    _ -> Error("runtime fixture has an absent or non-scalar tree field")
  }
}

fn observe(
  core: runtime_core.Core,
  checkpoint: String,
  extras: List(#(String, Json)),
) -> Result(Json, String) {
  use root <- result.try(root(core))
  Ok(
    json.object(list.append(
      [#("checkpoint", json.string(checkpoint)), #("root", root)],
      extras,
    )),
  )
}

fn tree_history(core: runtime_core.Core) -> Result(#(Int, Json), String) {
  use state <- result.try(
    dict.get(core.channels, "A/_C")
    |> result.replace_error("runtime fixture tree channel is missing"),
  )
  case state {
    channel.TreeState(tree) -> {
      let history = tree_kernel.history_view(tree)
      let points =
        list.map(history.sequenced.trunk, fn(entry) {
          let tree_types.SequencePoint(sequence_number, index_in_batch) =
            entry.point
          json.object([
            #("sequenceNumber", json.int(sequence_number)),
            #("indexInBatch", json.int(index_in_batch)),
          ])
        })
      Ok(#(
        list.length(history.pending),
        json.array(points, fn(value) { value }),
      ))
    }
    _ -> Error("runtime fixture channel has the wrong kind")
  }
}

fn outer(operation: SequencedDocumentMessage) -> Result(Json, String) {
  use client <- result.try(
    operation.client_id
    |> option.to_result("runtime fixture outer operation has no client"),
  )
  Ok(
    json.object([
      #("clientId", json.string(client)),
      #("clientSequenceNumber", json.int(operation.client_sequence_number)),
      #(
        "referenceSequenceNumber",
        json.int(operation.reference_sequence_number),
      ),
      #("sequenceNumber", json.int(operation.sequence_number)),
      #("minimumSequenceNumber", json.int(operation.minimum_sequence_number)),
    ]),
  )
}

fn deliver_with_events(
  core: runtime_core.Core,
  operation: SequencedDocumentMessage,
) -> Result(#(runtime_core.Core, runtime_core.Ingested), String) {
  runtime_core.handle_sequenced(core, operation)
  |> result.map_error(string.inspect)
}

fn tree_handle(core: runtime_core.Core) -> Result(String, String) {
  use address <- result.try(
    runtime_core.root_channel_address(core) |> result.map_error(string.inspect),
  )
  use value <- result.try(
    runtime_core.get(core, address, "tree")
    |> result.replace_error("missing-tree-handle"),
  )
  use tree <- result.try(
    runtime_core.resolve_handle_address(core, value)
    |> result.map_error(string.inspect),
  )
  case dict.get(core.channels, tree) {
    Ok(channel.TreeState(_)) -> Ok(tree)
    _ -> Error("wrong-tree-handle-kind")
  }
}

pub fn run_bootstrap(input: Json) -> Result(Json, String) {
  use input <- result.try(reader_input(input))
  use _ <- result.try(case input.operations {
    [_, _, _] -> Ok(Nil)
    _ -> Error("runtime fixture requires three bootstrap operations")
  })
  use core <- result.try(checked_core(input, "reader"))
  use map <- result.try(
    runtime_core.root_channel_address(core) |> result.map_error(string.inspect),
  )
  use tree <- result.try(tree_handle(core))
  use #(pending, positions) <- result.try(tree_history(core))
  use first <- result.try(
    observe(core, "valid-bootstrap", [
      #("schedule", json.string("valid-bootstrap")),
      #("bootstrapPath", json.string("/" <> map)),
      #("treePath", json.string("/" <> tree)),
      #(
        "bootstrapType",
        json.string(channel.fluid_type_to_string(channel.MapChannel)),
      ),
      #(
        "treeType",
        json.string(channel.fluid_type_to_string(channel.TreeChannel)),
      ),
      #("handleResolvedToTree", json.bool(True)),
      #("pendingCount", json.int(pending)),
      #("treePositions", positions),
      #("invalidated", json.bool(False)),
    ]),
  )
  use #(observations, _) <- result.try(
    list.try_fold(input.operations, #([first], core), fn(acc, operation) {
      let #(observations, core) = acc
      use #(core, ingested) <- result.try(deliver_with_events(core, operation))
      use #(pending, positions) <- result.try(tree_history(core))
      use outer <- result.try(outer(operation))
      use root <- result.try(root(core))
      use _ <- result.try(case ingested.events {
        [
          #(
            "A/root",
            channel.MapEvent(map_kernel.ValueChanged("tree", _, _, False)),
          ),
        ] -> Ok(Nil)
        _ ->
          Error("runtime fixture map invalidation did not match the tree key")
      })
      use label <- result.try(case tree_handle(core) {
        Error("missing-tree-handle") -> Ok("missing-tree-handle")
        Error("wrong-tree-handle-kind") -> Ok("wrong-tree-handle-kind")
        Ok(_) -> Ok("restored-tree-handle")
        Error(detail) -> Error(detail)
      })
      let fields = [
        #("checkpoint", json.string(label)),
        #("root", root),
        #("pendingCount", json.int(pending)),
        #("treePositions", positions),
        #("outer", outer),
        #("invalidated", json.bool(True)),
      ]
      let fields = case label {
        "restored-tree-handle" ->
          list.append(fields, [#("handleResolvedToTree", json.bool(True))])
        _ -> list.append(fields, [#("rejection", json.string(label))])
      }
      Ok(#(list.append(observations, [json.object(fields)]), core))
    }),
  )
  case observations {
    [valid, missing, wrong, restored] ->
      Ok(
        json.object([
          #(
            "observations",
            json.array([valid, missing, wrong, restored], fn(value) { value }),
          ),
        ]),
      )
    _ -> Error("runtime fixture has an unexpected bootstrap operation count")
  }
}

pub fn run_batched(input: Json) -> Result(Json, String) {
  use writer <- result.try(field(input, "writer"))
  use session_string <- result.try(read_field(
    writer,
    "sessionId",
    decode.string,
  ))
  use session <- result.try(
    fluid_ids.session_id(session_string) |> result.map_error(string.inspect),
  )
  use writer_compressor <- result.try(read_field(
    writer,
    "compressor",
    decode.string,
  ))
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(writer_compressor), session)
    |> result.map_error(fn(error) {
      "writer compressor: " <> string.inspect(error)
    }),
  )
  use client <- result.try(read_field(writer, "clientId", decode.string))
  use fixture <- result.try(reader_input(input))
  use _ <- result.try(case fixture.operations {
    [_] -> Ok(Nil)
    _ -> Error("runtime fixture requires one grouped operation")
  })
  use core <- result.try(
    checked_core(RuntimeInput(..fixture, compressor: compressor), client)
    |> result.map_error(fn(error) { "writer core: " <> error }),
  )
  use edits <- result.try(read_field(
    input,
    "localEdits",
    decode.list({
      use path <- decode.field("path", decode.list(decode.string))
      use value <- decode.field("value", fixtures.tree_value_decoder())
      decode.success(tree_types.SetField(path, value))
    }),
  ))
  use #(local, events, outbound) <- result.try(
    runtime_core.submit_tree_edits(core, "A/_C", edits)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(case events {
    [#("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(True)))] -> Ok(Nil)
    _ -> Error("runtime fixture local tree invalidation did not match")
  })
  use sent <- result.try(case outbound {
    [sent] -> Ok(sent)
    _ -> Error("runtime fixture did not emit one outer batch")
  })
  use #(pending, positions) <- result.try(tree_history(local))
  use first <- result.try(
    observe(local, "local-after-batch", [
      #("pendingCount", json.int(pending)),
      #("treePositions", positions),
      #("invalidated", json.bool(events != [])),
      #(
        "outer",
        json.object([
          #("clientId", json.string(client)),
          #("clientSequenceNumber", json.int(sent.client_sequence_number)),
          #("referenceSequenceNumber", json.int(sent.reference_sequence_number)),
        ]),
      ),
    ]),
  )
  use reader <- result.try(reader_input(input))
  use reader <- result.try(checked_core(reader, "reader"))
  use #(peer, peer_events) <- result.try(
    list.try_fold(fixture.operations, #(reader, []), fn(acc, operation) {
      use #(peer, ingested) <- result.try(deliver_with_events(acc.0, operation))
      Ok(#(peer, list.append(acc.1, ingested.events)))
    }),
  )
  use _ <- result.try(case peer_events {
    [#("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False)))] -> Ok(Nil)
    _ -> Error("runtime fixture peer tree invalidation did not match")
  })
  use #(pending, positions) <- result.try(tree_history(peer))
  use operation <- result.try(
    list.last(fixture.operations)
    |> result.replace_error("runtime fixture has no grouped operation"),
  )
  use outer <- result.try(outer(operation))
  use second <- result.try(
    observe(peer, "peer-after-delivery", [
      #("pendingCount", json.int(pending)),
      #("treePositions", positions),
      #("invalidated", json.bool(peer_events != [])),
      #("outer", outer),
    ]),
  )
  Ok(
    json.object([
      #("observations", json.array([first, second], fn(value) { value })),
    ]),
  )
}

fn native_outbound(id: String, operation: wire.OutboundOperation) -> Json {
  json.object([
    #("id", json.string(id)),
    #("clientSequenceNumber", json.int(operation.client_sequence_number)),
    #("referenceSequenceNumber", json.int(operation.reference_sequence_number)),
    #("type", json.string(operation.operation_type)),
    #("contents", operation.contents),
    #("metadata", option.unwrap(operation.metadata, json.null())),
  ])
}

fn native_edit(
  core: runtime_core.Core,
  id: String,
  edits: List(tree_types.Edit),
) -> Result(#(runtime_core.Core, Json), String) {
  use #(core, _, operations) <- result.try(
    runtime_core.submit_tree_edits(core, "A/_C", edits)
    |> result.map_error(string.inspect),
  )
  case operations {
    [operation] -> Ok(#(core, native_outbound(id, operation)))
    _ -> Error("native tree edit did not produce one outer message")
  }
}

pub fn export_runtime(input: Json) -> Result(Json, String) {
  use session_string <- result.try(read_field(input, "sessionId", decode.string))
  use session <- result.try(
    fluid_ids.session_id(session_string) |> result.map_error(string.inspect),
  )
  use client <- result.try(read_field(input, "clientId", decode.string))
  use fixture <- result.try(read(input, session))
  use decoder_input <- result.try(field(input, "decoderInput"))
  use initial_snapshot <- result.try(field(decoder_input, "initialSnapshot"))
  use core <- result.try(checked_core(fixture, client))
  use map <- result.try(
    runtime_core.root_channel_address(core) |> result.map_error(string.inspect),
  )
  use handle <- result.try(
    runtime_core.get(core, map, "tree")
    |> result.replace_error("native bootstrap has no tree handle"),
  )
  let map_header =
    wire_op.encode_map_header([
      #("z", json.int(0)),
      #("10", json.int(10)),
      #("2", json.int(2)),
      #("01", json.int(1)),
      #("tree", handle),
    ])
  use #(core, _, map_outbound) <- result.try(
    runtime_core.set(core, map, "tree", handle)
    |> result.map_error(string.inspect),
  )
  use map_outbound <- result.try(case map_outbound {
    [operation] -> Ok(native_outbound("bootstrap-map-handle", operation))
    _ -> Error("native map set did not produce one outer message")
  })
  use #(core, required) <- result.try(
    native_edit(core, "required-field", [
      tree_types.SetField(["title"], tree_types.StringValue("native-required")),
    ]),
  )
  use #(core, optional_set) <- result.try(
    native_edit(core, "optional-set", [
      tree_types.SetField(["note"], tree_types.StringValue("native-note")),
    ]),
  )
  use #(core, optional_clear) <- result.try(
    native_edit(core, "optional-clear", [
      tree_types.ClearField(["note"]),
    ]),
  )
  use #(core, grouped) <- result.try(
    native_edit(core, "batched-commits", [
      tree_types.SetField(["title"], tree_types.StringValue("native-batched")),
      tree_types.SetField(["enabled"], tree_types.BooleanValue(True)),
      tree_types.SetField(["rating"], tree_types.NumberValue(3.0)),
    ]),
  )
  let outbound = [map_outbound, required, optional_set, optional_clear, grouped]
  use replay <- result.try(read_field(
    input,
    "replayMessages",
    decode.list(socket.sequenced_document_message_decoder()),
  ))
  use core <- result.try(
    list.try_fold(replay, core, fn(core, message) {
      deliver_with_events(core, message)
      |> result.map(fn(outcome) { outcome.0 })
    }),
  )
  use #(pending, positions) <- result.try(tree_history(core))
  use visible <- result.try(root(core))
  use path <- result.try(tree_handle(core))
  Ok(
    json.object([
      #("formatVersion", json.int(1)),
      #("clientId", json.string(client)),
      #("sessionId", json.string(session_string)),
      #("bootstrapPath", json.string("/" <> map)),
      #("treePath", json.string("/" <> path)),
      #(
        "initialDocument",
        json.object([
          #("snapshot", initial_snapshot),
          #("sequenceNumber", json.int(fixture.sequence_number)),
          #("minimumSequenceNumber", json.int(fixture.minimum_sequence_number)),
          #("bootstrapPath", json.string("/" <> map)),
          #("treePath", json.string("/" <> path)),
        ]),
      ),
      #("mapHeader", map_header),
      #("outbound", json.array(outbound, fn(value) { value })),
      #("root", visible),
      #("pendingCount", json.int(pending)),
      #("treePositions", positions),
      #("sequenceNumber", json.int(core.last_seen_sequence_number)),
    ]),
  )
}

pub fn routed_core() -> Result(runtime_core.Core, String) {
  use #(input, prefix) <- result.try(routed_seed_input())
  use seed <- result.try(
    runtime_core.bootstrap_seed(input) |> result.map_error(string.inspect),
  )
  use bootstrapped <- result.try(
    runtime_core.bootstrap_seeded(connected("reader", prefix, 2), seed)
    |> result.map_error(string.inspect),
  )
  case bootstrapped {
    runtime_core.Complete(core) -> Ok(core)
    runtime_core.MissingPrefix(_, _, _, _) ->
      Error("runtime fixture did not replay the prefix")
  }
}

fn snapshot(
  data: summary.TreeSummaryData,
  sequence_number: Int,
  minimum_sequence_number: Int,
  view_id: fluid_ids.StableId,
) -> Result(tree_kernel.TreeSnapshot, String) {
  let summary.TreeSummaryData(
    stored,
    summary.ForestSummary(fields),
    summary.DetachedFieldIndex(detached, next_id),
    summary.EditManagerSummary(trunk, branches),
  ) = data
  use _ <- result.try(case detached == [] && trunk == [] && branches == [] {
    True -> Ok(Nil)
    False -> Error("runtime fixture requires an initial empty tree history")
  })
  use roots <- result.try(
    list.key_find(fields, "rootFieldKey")
    |> result.map_error(fn(_) { "runtime fixture root field is missing" }),
  )
  use root <- result.try(case roots {
    [] -> Ok(None)
    [root] -> Ok(Some(root))
    _ -> Error("runtime fixture has multiple root trees")
  })
  tree_kernel.snapshot_from_parts(
    view_id,
    stored,
    forest.ForestData(root, [], next_id),
    history.HistorySnapshot(
      history.InitialBase,
      [],
      [],
      sequence_number,
      minimum_sequence_number,
    ),
  )
  |> result.map_error(string.inspect)
}

fn blob(
  document: fluid_summary.SummaryEntry,
  path: String,
) -> Result(Json, String) {
  use entry <- result.try(
    fluid_summary.resolve(
      fluid_summary.SummaryHandle(path, fluid_summary.BlobHandle),
      Some(document),
    )
    |> result.map_error(string.inspect),
  )
  use bytes <- result.try(case entry {
    fluid_summary.SummaryBlob(bytes) -> Ok(bytes)
    _ -> Error("runtime fixture entry is not a blob: " <> path)
  })
  use raw <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error("runtime fixture blob is not UTF-8: " <> path),
  )
  json.parse(raw, wire.json_value_decoder())
  |> result.map_error(fn(error) {
    "runtime fixture blob is not JSON: "
    <> path
    <> ": "
    <> string.inspect(error)
  })
}

fn field(input: Json, name: String) -> Result(Json, String) {
  read_field(input, name, wire.json_value_decoder())
}

fn read_field(
  input: Json,
  name: String,
  decoder: decode.Decoder(value),
) -> Result(value, String) {
  json.parse(json.to_string(input), decode.at([name], decoder))
  |> result.map_error(fn(error) {
    "runtime fixture field " <> name <> ": " <> string.inspect(error)
  })
}

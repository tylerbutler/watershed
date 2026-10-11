import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import spillway/types
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/runtime_core
import watershed/tree/fixtures
import watershed/tree/runtime_fixture
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/fluid_summary
import watershed/wire/op as wire_op

const graph_store_type = "org.watershed.shared-tree.m7.graph"

type Replay {
  Replay(
    writer: runtime_core.Core,
    receiver: runtime_core.Core,
    outbounds: List(wire.OutboundOperation),
    last_items: List(fluid_container.MessageKind),
    last_messages: List(Json),
    context_messages: List(Json),
    sequence_number: Int,
  )
}

type ScenarioResult {
  ScenarioResult(observation: Json, messages: List(Json), serialization: Json)
}

pub type EvidenceMutation {
  SnapshotBytes
  Route
  Order
  Allocation
  ClientSequenceNumber
  GroupMetadata
}

type Command {
  CreateDatastore(
    datastore_id: String,
    store_type: String,
    package_path: List(String),
    entry_point_channel_id: String,
    channels: List(#(String, String)),
  )
  MapSet(target: String, key: String, value: Json)
  Settle(checkpoint: String)
  UnsupportedCommand(command_type: String)
}

pub fn run(_input: Json) -> Result(Json, String) {
  Error("full lifecycle replay requires Task 4 tree support")
}

pub fn run_case(id: String, _input: Json) -> Result(Json, String) {
  case id {
    "cross-datastore-attachment" ->
      Error("full lifecycle replay requires Task 4 tree support")
    _ -> Error("unsupported lifecycle case " <> id)
  }
}

pub fn assert_scenario(case_id: String, scenario_id: String) -> Nil {
  case fixtures.load(case_id) {
    Error(detail) -> panic as { "SharedTree case " <> case_id <> ": " <> detail }
    Ok(fixture) ->
      case run_scenario(case_id, scenario_id, fixture.input) {
        Error(detail) ->
          panic as {
            "SharedTree case "
            <> case_id
            <> " scenario "
            <> scenario_id
            <> " runner error: "
            <> detail
          }
        Ok(actual) ->
          case expected_observation(fixture.expected, scenario_id) {
            Error(detail) ->
              panic as {
                "SharedTree case "
                <> case_id
                <> " scenario "
                <> scenario_id
                <> ": "
                <> detail
              }
            Ok(expected) ->
              case fixtures.first_difference(actual.observation, expected) {
                Ok(Nil) ->
                  case
                    compare_raw_evidence(
                      fixture.raw,
                      scenario_id,
                      actual.messages,
                      actual.serialization,
                    )
                  {
                    Ok(Nil) -> Nil
                    Error(path) ->
                      panic as {
                        "SharedTree case "
                        <> case_id
                        <> " scenario "
                        <> scenario_id
                        <> " raw evidence differs at "
                        <> path
                      }
                  }
                Error(path) ->
                  panic as {
                    "SharedTree case "
                    <> case_id
                    <> " scenario "
                    <> scenario_id
                    <> " differs at "
                    <> path
                  }
              }
          }
      }
  }
}

pub fn assert_scenario_rejects_evidence_mutation(
  case_id: String,
  scenario_id: String,
  mutation: EvidenceMutation,
) -> Nil {
  let assert Ok(fixture) = fixtures.load(case_id)
  let assert Ok(actual) = run_scenario(case_id, scenario_id, fixture.input)
  let messages = case mutation {
    Order -> list.reverse(actual.messages)
    SnapshotBytes -> mutate_messages(actual.messages, "3.1.0", "3.1.1")
    Route ->
      mutate_messages(
        actual.messages,
        "\"address\":\"A\"",
        "\"address\":\"changed\"",
      )
    Allocation ->
      mutate_messages(
        actual.messages,
        "\"firstGenCount\":1",
        "\"firstGenCount\":99",
      )
    ClientSequenceNumber ->
      mutate_messages(
        actual.messages,
        "\"clientSequenceNumber\":1",
        "\"clientSequenceNumber\":99",
      )
    GroupMetadata ->
      mutate_messages(
        actual.messages,
        "\"groupedOpCount\":3",
        "\"groupedOpCount\":99",
      )
  }
  let assert Error(_) =
    compare_raw_evidence(
      fixture.raw,
      scenario_id,
      messages,
      actual.serialization,
    )
  Nil
}

fn mutate_messages(
  messages: List(Json),
  before: String,
  after: String,
) -> List(Json) {
  let raw = json.to_string(json.array(messages, fn(value) { value }))
  let changed = string.replace(raw, before, after)
  let assert True = changed != raw
  let assert Ok(messages) =
    json.parse(changed, decode.list(wire.json_value_decoder()))
  messages
}

fn run_scenario(
  case_id: String,
  scenario_id: String,
  input: Json,
) -> Result(ScenarioResult, String) {
  use _ <- result.try(case case_id {
    "cross-datastore-attachment" -> Ok(Nil)
    _ -> Error("unsupported lifecycle case " <> case_id)
  })
  use scenario <- result.try(matching_scenario(input, scenario_id))
  use commands <- result.try(read_field(
    scenario,
    "commands",
    decode.list(command_decoder()),
  ))
  use #(writer, receiver, writer_client_id, receiver_client_id) <- result.try(
    cores(input),
  )
  use context <- result.try(context_messages(input))
  let sequence_number = context_sequence_number(context)
  let writer =
    runtime_core.Core(..writer, last_seen_sequence_number: sequence_number)
  let receiver =
    runtime_core.Core(..receiver, last_seen_sequence_number: sequence_number)
  use replay <- result.try(
    list.try_fold(
      commands,
      Replay(writer, receiver, [], [], [], context, sequence_number),
      fn(replay, command) { execute_command(replay, command, writer_client_id) },
    ),
  )
  use _ <- result.try(case replay.outbounds {
    [] -> Ok(Nil)
    _ -> Error("scenario ended before its settle checkpoint")
  })
  use observation <- result.try(observation(
    scenario_id,
    replay.receiver,
    receiver_client_id,
    replay.last_items,
    replay.sequence_number,
  ))
  use serialization <- result.try(receiver_serialization(
    scenario_id,
    replay.receiver,
    receiver_client_id,
  ))
  Ok(ScenarioResult(observation, replay.last_messages, serialization))
}

fn execute_command(
  replay: Replay,
  command: Command,
  writer_client_id: String,
) -> Result(Replay, String) {
  case command {
    CreateDatastore(
      datastore_id,
      store_type,
      package_path,
      entry_point,
      channels,
    ) -> {
      use _ <- result.try(
        case
          store_type == graph_store_type,
          package_path == [graph_store_type],
          entry_point,
          channels
        {
          True,
            True,
            "root",
            [#("root", "https://graph.microsoft.com/types/map")]
          -> Ok(Nil)
          _, _, _, _ -> Error("unsupported declared datastore package")
        },
      )
      use writer <- result.try(
        runtime_core.create_detached_data_store(replay.writer, datastore_id)
        |> result.map_error(string.inspect),
      )
      Ok(Replay(..replay, writer:))
    }
    MapSet(target, key, value) -> {
      use address <- result.try(channel_address(target))
      use #(writer, _, outbound) <- result.try(
        runtime_core.set(replay.writer, address, key, value)
        |> result.map_error(string.inspect),
      )
      Ok(
        Replay(
          ..replay,
          writer:,
          outbounds: list.append(replay.outbounds, outbound),
        ),
      )
    }
    Settle(_) ->
      list.try_fold(
        replay.outbounds,
        Replay(
          ..replay,
          outbounds: [],
          last_items: [],
          last_messages: replay.context_messages,
          context_messages: [],
        ),
        fn(replay, outbound) {
          let sequence_number = replay.sequence_number + 1
          use items <- result.try(outbound_items(outbound))
          use transport <- result.try(transport_message(
            outbound,
            writer_client_id,
            sequence_number,
          ))
          use message <- result.try(sequenced(
            outbound,
            writer_client_id,
            sequence_number,
          ))
          use #(writer, _) <- result.try(
            runtime_core.handle_sequenced(replay.writer, message)
            |> result.map_error(string.inspect),
          )
          use #(receiver, _) <- result.try(
            runtime_core.handle_sequenced(replay.receiver, message)
            |> result.map_error(string.inspect),
          )
          Ok(Replay(
            writer,
            receiver,
            [],
            list.append(replay.last_items, items),
            list.append(replay.last_messages, [transport]),
            replay.context_messages,
            sequence_number,
          ))
        },
      )
    UnsupportedCommand(command_type) ->
      Error("unsupported lifecycle command " <> command_type)
  }
}

fn cores(
  input: Json,
) -> Result(#(runtime_core.Core, runtime_core.Core, String, String), String) {
  use decoder_input <- result.try(field(input, "decoderInput"))
  use runtime <- result.try(field(decoder_input, "runtime"))
  use store_type <- result.try(read_field(
    runtime,
    "graphStoreType",
    decode.string,
  ))
  use _ <- result.try(case store_type {
    "org.watershed.shared-tree.m7.graph" -> Ok(Nil)
    _ -> Error("unsupported lifecycle graph store type")
  })
  use sessions <- result.try(field(decoder_input, "sessions"))
  use writer_client_id <- result.try(read_field(
    sessions,
    "writerClientId",
    decode.string,
  ))
  use receiver_client_id <- result.try(read_field(
    sessions,
    "receiverClientId",
    decode.string,
  ))
  use writer <- result.try(field(sessions, "writer"))
  use writer_session_id <- result.try(read_field(
    writer,
    "sessionId",
    decode.string,
  ))
  use writer_session <- result.try(
    fluid_ids.session_id(writer_session_id)
    |> result.map_error(string.inspect),
  )
  use writer_compressor_raw <- result.try(read_field(
    writer,
    "compressor",
    decode.string,
  ))
  use writer_compressor <- result.try(
    fluid_ids.deserialize(json.string(writer_compressor_raw), writer_session)
    |> result.map_error(string.inspect),
  )
  use snapshot <- result.try(field(decoder_input, "initialSnapshot"))
  use hierarchy <- result.try(runtime_fixture.read_snapshot(snapshot))
  use sequence_number <- result.try(read_field(
    snapshot,
    "sequenceNumber",
    decode.int,
  ))
  use entry_point <- result.try(field(runtime, "entryPoint"))
  use data_store_id <- result.try(read_field(
    entry_point,
    "datastoreId",
    decode.string,
  ))
  use channel_id <- result.try(read_field(
    entry_point,
    "channelId",
    decode.string,
  ))
  use package_path <- result.try(read_field(
    entry_point,
    "packagePath",
    decode.list(decode.string),
  ))
  use header <- result.try(blob(
    hierarchy,
    "/.channels/" <> data_store_id <> "/.channels/" <> channel_id <> "/header",
  ))
  use entries <- result.try(
    wire_op.decode_map_header(header) |> result.map_error(string.inspect),
  )
  let seed_input =
    runtime_core.BootstrapSeedInput(
      profile: runtime_core.RoutedSeed,
      sequence_number: sequence_number,
      minimum_sequence_number: 0,
      members: [],
      datastores: [runtime_core.DatastoreSeed(data_store_id, package_path)],
      aliases: [#("root", data_store_id)],
      channels: [
        runtime_core.ChannelSeed(
          fluid_container.Route(data_store_id, channel_id),
          channel.fluid_attributes(channel.MapChannel),
          channel.MapSnapshot(entries),
        ),
      ],
      bootstrap_map: fluid_container.Route(data_store_id, channel_id),
      compressor: Some(writer_compressor),
      tree_views: [],
    )
  use writer_seed <- result.try(
    runtime_core.bootstrap_seed(seed_input)
    |> result.map_error(string.inspect),
  )
  use writer_core <- result.try(
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(writer_client_id, [], sequence_number),
      writer_seed,
    )
    |> complete_core,
  )
  use receiver_session <- result.try(
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
    |> result.map_error(string.inspect),
  )
  use settled_compressor <- result.try(
    fluid_ids.serialize(writer_compressor, False)
    |> result.map_error(string.inspect),
  )
  use receiver_compressor <- result.try(
    fluid_ids.deserialize(settled_compressor, receiver_session)
    |> result.map_error(string.inspect),
  )
  use receiver_seed <- result.try(
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..seed_input,
        compressor: Some(receiver_compressor),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use receiver_core <- result.try(
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(receiver_client_id, [], sequence_number),
      receiver_seed,
    )
    |> complete_core,
  )
  Ok(#(
    runtime_core.Core(..writer_core, compressor: Some(writer_compressor)),
    receiver_core,
    writer_client_id,
    receiver_client_id,
  ))
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
    _ -> Error("lifecycle fixture entry is not a blob: " <> path)
  })
  use raw <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error("lifecycle fixture blob is not UTF-8: " <> path),
  )
  json.parse(raw, wire.json_value_decoder())
  |> result.map_error(string.inspect)
}

fn complete_core(
  value: Result(runtime_core.Bootstrapped, runtime_core.CoreError),
) -> Result(runtime_core.Core, String) {
  case value {
    Ok(runtime_core.Complete(core)) -> Ok(core)
    Ok(runtime_core.MissingPrefix(..)) ->
      Error("lifecycle snapshot requires a missing prefix")
    Error(error) -> Error(string.inspect(error))
  }
}

fn observation(
  scenario_id: String,
  receiver: runtime_core.Core,
  receiver_client_id: String,
  items: List(fluid_container.MessageKind),
  sequence_number: Int,
) -> Result(Json, String) {
  let attach_order = list.map(items, message_label)
  case scenario_id {
    "map-cross-datastore" -> {
      let secondary = "d6b524d6-ef34-4709-b1d9-bc0a70887c2a/root"
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      Ok(
        json.object([
          #("id", json.string(scenario_id)),
          #(
            "value",
            json.object([
              #("primary", json.string("/A/root")),
              #("secondary", json.string("/" <> secondary)),
              #("entryPoint", json.string("root")),
              #("attachOrder", json.array(attach_order, json.string)),
              #("receiver", serialization),
            ]),
          ),
          #("evidence", evidence(scenario_id, 0)),
        ]),
      )
    }
    "map-cycle" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      Ok(
        json.object([
          #("id", json.string(scenario_id)),
          #(
            "value",
            json.object([
              #("left", json.string("/D/root")),
              #("right", json.string("/F/root")),
              #("attachOrder", json.array(attach_order, json.string)),
              #("receiver", serialization),
            ]),
          ),
          #("evidence", evidence(scenario_id, 1)),
        ]),
      )
    }
    _ ->
      Error(
        "unsupported map-only lifecycle scenario "
        <> scenario_id
        <> " at sequence "
        <> int.to_string(sequence_number),
      )
  }
}

fn receiver_serialization(
  scenario_id: String,
  receiver: runtime_core.Core,
  receiver_client_id: String,
) -> Result(Json, String) {
  case scenario_id {
    "map-cross-datastore" -> {
      let secondary = "d6b524d6-ef34-4709-b1d9-bc0a70887c2a/root"
      use target <- result.try(resolved_target(receiver, "A/root", "secondary"))
      Ok(
        json.object([
          #("clientId", json.string(receiver_client_id)),
          #(
            "targets",
            json.array(
              [
                target_json(receiver, "A/root"),
                target_json(receiver, secondary),
              ],
              fn(value) { value },
            ),
          ),
          #(
            "graph",
            json.object([
              #("source", json.string("/A/root")),
              #("edge", json.string("secondary")),
              #("target", json.string("/" <> target)),
              #("targetData", map_data(receiver, target)),
            ]),
          ),
        ]),
      )
    }
    "map-cycle" -> {
      use target <- result.try(resolved_target(receiver, "D/root", "right"))
      use returned <- result.try(resolved_target(receiver, target, "left"))
      Ok(
        json.object([
          #("clientId", json.string(receiver_client_id)),
          #(
            "targets",
            json.array(
              [
                target_json(receiver, "D/root"),
                target_json(receiver, "F/root"),
              ],
              fn(value) { value },
            ),
          ),
          #(
            "graph",
            json.object([
              #("source", json.string("/D/root")),
              #("edge", json.string("right")),
              #("target", json.string("/" <> target)),
              #("returnEdge", json.string("left")),
              #("returnTarget", json.string("/" <> returned)),
              #("resolvesToSource", json.bool(returned == "D/root")),
            ]),
          ),
        ]),
      )
    }
    _ -> Error("unsupported lifecycle serialization scenario " <> scenario_id)
  }
}

fn message_label(message: fluid_container.MessageKind) -> String {
  case message {
    fluid_container.IdAllocation(_) -> "id-allocation"
    fluid_container.DatastoreAttach(id, _) -> "datastore-attach:" <> id
    fluid_container.ChannelOperation(route, _) ->
      "component:" <> route.data_store_id <> "/" <> route.channel_id
    fluid_container.ChannelAttach(route, _, _) ->
      "channel-attach:" <> route.data_store_id <> "/" <> route.channel_id
    fluid_container.DatastoreAlias(id, alias) ->
      "datastore-alias:" <> id <> ":" <> alias
  }
}

fn target_json(core: runtime_core.Core, address: String) -> Json {
  json.object([
    #("path", json.string("/" <> address)),
    #("channelType", json.string("https://graph.microsoft.com/types/map")),
    #("data", map_data(core, address)),
  ])
}

fn map_data(core: runtime_core.Core, address: String) -> Json {
  json.object(runtime_core.entries(core, address))
}

fn resolved_target(
  core: runtime_core.Core,
  source: String,
  key: String,
) -> Result(String, String) {
  use value <- result.try(
    runtime_core.get(core, source, key)
    |> result.map_error(fn(_) { "missing map handle " <> source <> "/" <> key }),
  )
  runtime_core.resolve_handle_address(core, value)
  |> result.map_error(string.inspect)
}

fn evidence(scenario_id: String, index: Int) -> Json {
  json.array(
    [
      json.object([
        #("section", json.string("messages")),
        #(
          "id",
          json.string(scenario_id <> ":messages:" <> int.to_string(index)),
        ),
      ]),
      json.object([
        #("section", json.string("serialization")),
        #(
          "id",
          json.string(scenario_id <> ":serialization:" <> int.to_string(index)),
        ),
      ]),
    ],
    fn(value) { value },
  )
}

fn sequenced(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> Result(types.SequencedDocumentMessage, String) {
  use contents <- result.try(
    json.parse(json.to_string(outbound.contents), decode.dynamic)
    |> result.map_error(fn(_) { "invalid outbound contents" }),
  )
  use metadata <- result.try(case outbound.metadata {
    None -> Ok(None)
    Some(value) ->
      json.parse(json.to_string(value), decode.dynamic)
      |> result.map(Some)
      |> result.map_error(fn(_) { "invalid outbound metadata" })
  })
  Ok(types.SequencedDocumentMessage(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: outbound.operation_type,
    contents: contents,
    metadata: metadata,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 1_700_000_000_000,
    data: None,
  ))
}

fn transport_message(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> Result(Json, String) {
  transport_projection(
    json.object([
      #("clientId", json.string(client_id)),
      #("clientSequenceNumber", json.int(outbound.client_sequence_number)),
      #("contents", json.string(json.to_string(outbound.contents))),
      #("metadata", case outbound.metadata {
        Some(value) -> value
        None -> json.null()
      }),
      #("minimumSequenceNumber", json.int(outbound.reference_sequence_number)),
      #("referenceSequenceNumber", json.int(outbound.reference_sequence_number)),
      #("sequenceNumber", json.int(sequence_number)),
      #("timestamp", json.int(1_700_000_000_000)),
      #("type", json.string(outbound.operation_type)),
    ]),
  )
}

fn context_messages(input: Json) -> Result(List(Json), String) {
  use decoder_input <- result.try(field(input, "decoderInput"))
  use messages <- result.try(read_field(
    decoder_input,
    "deliveryPrefix",
    decode.list(wire.json_value_decoder()),
  ))
  Ok(
    list.filter_map(messages, fn(message) {
      case read_field(message, "type", decode.string) {
        Ok("op") | Error(_) -> Error(Nil)
        Ok(_) ->
          case transport_projection(message) {
            Ok(projected) -> Ok(projected)
            Error(_) -> Error(Nil)
          }
      }
    }),
  )
}

fn context_sequence_number(messages: List(Json)) -> Int {
  list.fold(messages, 0, fn(highest, message) {
    case read_field(message, "sequenceNumber", decode.int) {
      Ok(value) if value > highest -> value
      _ -> highest
    }
  })
}

fn compare_raw_evidence(
  raw: Json,
  scenario_id: String,
  actual_messages: List(Json),
  actual_serialization: Json,
) -> Result(Nil, String) {
  use raw_messages <- result.try(raw_record(
    raw,
    "messages",
    scenario_id,
    "attach",
  ))
  use expected_messages <- result.try(
    json.parse(
      json.to_string(raw_messages),
      decode.list(wire.json_value_decoder()),
    )
    |> result.map_error(fn(_) { "raw.messages.value" }),
  )
  use expected_messages <- result.try(list.try_map(
    expected_messages,
    transport_projection,
  ))
  use _ <- result.try(
    fixtures.first_difference(
      json.array(actual_messages, fn(value) { value }),
      json.array(expected_messages, fn(value) { value }),
    )
    |> result.map_error(fn(path) { "raw.messages" <> path }),
  )
  use expected_serialization <- result.try(raw_record(
    raw,
    "serialization",
    scenario_id,
    "receiver-graph",
  ))
  fixtures.first_difference(actual_serialization, expected_serialization)
  |> result.map_error(fn(path) { "raw.serialization" <> path })
}

fn raw_record(
  raw: Json,
  section: String,
  scenario_id: String,
  kind: String,
) -> Result(Json, String) {
  use records <- result.try(
    json.parse(
      json.to_string(raw),
      decode.at([section], decode.list(decode.dynamic)),
    )
    |> result.map_error(fn(_) { "missing raw." <> section }),
  )
  let matches =
    list.filter_map(records, fn(record) {
      case
        decode.run(record, {
          use id <- decode.field("scenarioId", decode.string)
          use record_kind <- decode.field("kind", decode.string)
          use value <- decode.field("value", wire.json_value_decoder())
          decode.success(#(id, record_kind, value))
        })
      {
        Ok(#(id, record_kind, value))
          if id == scenario_id && record_kind == kind
        -> Ok(value)
        _ -> Error(Nil)
      }
    })
  case matches {
    [value] -> Ok(value)
    [] -> Error("missing raw." <> section <> " for " <> scenario_id)
    [_, _, ..] -> Error("duplicate raw." <> section <> " for " <> scenario_id)
  }
}

fn transport_projection(message: Json) -> Result(Json, String) {
  use client_id <- result.try(field(message, "clientId"))
  use client_sequence_number <- result.try(read_field(
    message,
    "clientSequenceNumber",
    decode.int,
  ))
  use contents <- result.try(field(message, "contents"))
  use minimum_sequence_number <- result.try(read_field(
    message,
    "minimumSequenceNumber",
    decode.int,
  ))
  use reference_sequence_number <- result.try(read_field(
    message,
    "referenceSequenceNumber",
    decode.int,
  ))
  use sequence_number <- result.try(read_field(
    message,
    "sequenceNumber",
    decode.int,
  ))
  use timestamp <- result.try(read_field(message, "timestamp", decode.int))
  use message_type <- result.try(read_field(message, "type", decode.string))
  let metadata = optional_json_field(message, "metadata")
  use #(contents, metadata) <- result.try(normalize_batch_identity(
    contents,
    metadata,
    client_sequence_number,
  ))
  Ok(
    json.object([
      #("clientId", client_id),
      #("clientSequenceNumber", json.int(client_sequence_number)),
      #("contents", contents),
      #("metadata", metadata),
      #("minimumSequenceNumber", json.int(minimum_sequence_number)),
      #("referenceSequenceNumber", json.int(reference_sequence_number)),
      #("sequenceNumber", json.int(sequence_number)),
      #("timestamp", json.int(timestamp)),
      #("type", json.string(message_type)),
    ]),
  )
}

fn normalize_batch_identity(
  contents: Json,
  metadata: Json,
  client_sequence_number: Int,
) -> Result(#(Json, Json), String) {
  let batch_id =
    json.parse(json.to_string(metadata), {
      use value <- decode.optional_field(
        "batchId",
        None,
        decode.map(decode.string, Some),
      )
      decode.success(value)
    })
    |> result.unwrap(None)
  let replacement =
    "transport-batch-[" <> int.to_string(client_sequence_number) <> "]"
  let normalize = fn(value: Json) {
    case batch_id {
      None -> Ok(value)
      Some(batch_id) ->
        json.to_string(value)
        |> string.replace(batch_id, replacement)
        |> json.parse(wire.json_value_decoder())
        |> result.map_error(fn(_) { "invalid normalized batch metadata" })
    }
  }
  use metadata <- result.try(normalize(metadata))
  case json.to_string(contents) {
    "null" -> Ok(#(contents, metadata))
    _ -> {
      use raw <- result.try(
        json.parse(json.to_string(contents), decode.string)
        |> result.map_error(fn(_) { "invalid transport contents" }),
      )
      let raw = case batch_id {
        Some(batch_id) -> string.replace(raw, batch_id, replacement)
        None -> raw
      }
      use contents <- result.try(
        json.parse(raw, wire.json_value_decoder())
        |> result.map_error(fn(_) { "invalid transport message JSON" }),
      )
      Ok(#(contents, metadata))
    }
  }
}

fn optional_json_field(source: Json, name: String) -> Json {
  json.parse(json.to_string(source), {
    use value <- decode.optional_field(
      name,
      json.null(),
      wire.json_value_decoder(),
    )
    decode.success(value)
  })
  |> result.unwrap(json.null())
}

fn outbound_items(
  outbound: wire.OutboundOperation,
) -> Result(List(fluid_container.MessageKind), String) {
  fluid_container.decode(outbound.contents, outbound.metadata)
  |> result.map(fn(batch) {
    list.map(batch.messages, fn(message) { message.kind })
  })
  |> result.map_error(string.inspect)
}

fn matching_scenario(input: Json, scenario_id: String) -> Result(Json, String) {
  use scenarios <- result.try(
    json.parse(
      json.to_string(input),
      decode.at(["scenarios"], decode.list(decode.dynamic)),
    )
    |> result.map_error(fn(_) { "missing lifecycle scenarios" }),
  )
  let matches =
    list.filter_map(scenarios, fn(scenario) {
      case
        decode.run(scenario, {
          use id <- decode.field("id", decode.string)
          decode.success(id)
        })
      {
        Ok(id) if id == scenario_id -> Ok(wire.dynamic_to_json(scenario))
        _ -> Error(Nil)
      }
    })
  case matches {
    [scenario] -> Ok(scenario)
    [] -> Error("missing scenario " <> scenario_id)
    [_, _, ..] -> Error("duplicate scenario " <> scenario_id)
  }
}

fn expected_observation(
  expected: Json,
  scenario_id: String,
) -> Result(Json, String) {
  use observations <- result.try(
    json.parse(
      json.to_string(expected),
      decode.at(["observations"], decode.list(decode.dynamic)),
    )
    |> result.map_error(fn(_) { "missing expected observations" }),
  )
  let matches =
    list.filter_map(observations, fn(observation) {
      case
        decode.run(observation, {
          use id <- decode.field("id", decode.string)
          decode.success(id)
        })
      {
        Ok(id) if id == scenario_id -> Ok(wire.dynamic_to_json(observation))
        _ -> Error(Nil)
      }
    })
  case matches {
    [observation] -> Ok(observation)
    [] -> Error("missing expected observation " <> scenario_id)
    [_, _, ..] -> Error("duplicate expected observation " <> scenario_id)
  }
}

fn command_decoder() -> decode.Decoder(Command) {
  use command_type <- decode.field("type", decode.string)
  case command_type {
    "create-datastore" -> {
      use datastore_id <- decode.field("datastoreId", decode.string)
      use store_type <- decode.field("storeType", decode.string)
      use package_path <- decode.field(
        "packagePath",
        decode.list(decode.string),
      )
      use entry_point <- decode.field("entryPointChannelId", decode.string)
      use channels <- decode.field(
        "channels",
        decode.list({
          use id <- decode.field("id", decode.string)
          use channel_type <- decode.field("type", decode.string)
          decode.success(#(id, channel_type))
        }),
      )
      decode.success(CreateDatastore(
        datastore_id,
        store_type,
        package_path,
        entry_point,
        channels,
      ))
    }
    "map-set" -> {
      use target <- decode.field("target", decode.string)
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", {
        use kind <- decode.field("kind", decode.string)
        use value <- decode.field("value", wire.json_value_decoder())
        case kind {
          "handle" -> decode.success(value)
          _ -> decode.failure(json.null(), "map value kind")
        }
      })
      decode.success(MapSet(target, key, value))
    }
    "settle" -> {
      use checkpoint <- decode.field("checkpoint", decode.string)
      decode.success(Settle(checkpoint))
    }
    other -> decode.success(UnsupportedCommand(other))
  }
}

fn channel_address(path: String) -> Result(String, String) {
  handle.routed_address(handle.encode_handle(string.drop_start(path, 1)), "/")
  |> result.map_error(string.inspect)
}

fn field(source: Json, name: String) -> Result(Json, String) {
  read_field(source, name, wire.json_value_decoder())
}

fn read_field(
  source: Json,
  name: String,
  decoder: decode.Decoder(a),
) -> Result(a, String) {
  json.parse(json.to_string(source), {
    use value <- decode.field(name, decoder)
    decode.success(value)
  })
  |> result.map_error(fn(_) { "missing or invalid " <> name })
}

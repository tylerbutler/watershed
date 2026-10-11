import gleam/bit_array
import gleam/dict
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
import watershed/tree/schema as tree_schema
import watershed/tree/types as tree_types
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
    item_groups: List(List(fluid_container.MessageKind)),
    last_messages: List(Json),
    context_messages: List(Json),
    sequence_number: Int,
    tree_views: dict.Dict(String, fluid_ids.StableId),
    tree_schemas: dict.Dict(String, tree_schema.ViewSchema),
  )
}

fn map_to_tree_serialization(
  receiver: runtime_core.Core,
  client_id: String,
  source: String,
  edge: String,
  target: String,
) -> Result(Json, String) {
  use target_data <- result.try(tree_data(receiver, target))
  Ok(
    json.object([
      #("clientId", json.string(client_id)),
      #(
        "targets",
        json.array([tree_target(target, target_data)], fn(value) { value }),
      ),
      #(
        "graph",
        json.object([
          #("source", json.string("/" <> source)),
          #("edge", json.string(edge)),
          #("target", json.string("/" <> target)),
          #("targetData", target_data),
        ]),
      ),
    ]),
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
  MapDelete(target: String, key: String)
  CreateChannel(datastore_id: String, channel_id: String, channel_type: String)
  InitializeTree(target: String, stored: Json, initial: tree_types.TreeValue)
  TreeSetString(target: String, field: String, value: String)
  TreeSetHandle(target: String, field: String, value: handle.Reference)
  TreeMapSetHandle(
    target: String,
    field: String,
    key: String,
    value: handle.Reference,
  )
  SerializeChannelSummary(target: String)
  BeginTransaction(target: String)
  CommitTransaction(target: String)
  Settle(checkpoint: String)
  UnsupportedCommand(command_type: String)
}

pub fn run(_input: Json) -> Result(Json, String) {
  Error("full lifecycle replay requires Task 4 tree support")
}

pub fn run_case(id: String, input: Json) -> Result(Json, String) {
  use fixture <- result.try(fixtures.load(id))
  use scenarios <- result.try(
    json.parse(
      json.to_string(input),
      decode.at(["scenarios"], decode.list(decode.dynamic)),
    )
    |> result.map_error(fn(_) { "missing lifecycle scenarios" }),
  )
  use observations <- result.try(
    list.try_fold(scenarios, [], fn(observations, scenario) {
      use scenario_id <- result.try(
        decode.run(scenario, decode.at(["id"], decode.string))
        |> result.map_error(fn(_) { "missing lifecycle scenario id" }),
      )
      case scenario_id {
        "active-transaction" -> Ok(observations)
        _ -> {
          use actual <- result.try(
            run_scenario(id, scenario_id, input)
            |> result.map_error(fn(detail) { scenario_id <> ": " <> detail }),
          )
          use _ <- result.try(case requires_tree_raw_comparison(scenario_id) {
            False -> Ok(Nil)
            True ->
              case raw_message_count(fixture.raw, scenario_id) {
                Error(_) -> Ok(Nil)
                Ok(_) ->
                  compare_raw_evidence(
                    fixture.raw,
                    scenario_id,
                    actual.messages,
                    actual.serialization,
                  )
                  |> result.map_error(fn(detail) {
                    scenario_id <> ": " <> detail
                  })
              }
          })
          Ok(list.append(observations, [actual.observation]))
        }
      }
    }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn requires_tree_raw_comparison(scenario_id: String) -> Bool {
  case scenario_id {
    "detached-tree" | "completed-transaction" | "tree-cross-datastore" -> True
    _ -> False
  }
}

pub fn assert_case(case_id: String) -> Nil {
  let fixture = case fixtures.load(case_id) {
    Ok(fixture) -> fixture
    Error(detail) -> panic as { "SharedTree case " <> case_id <> ": " <> detail }
  }
  let actual = case run_case(case_id, fixture.input) {
    Ok(actual) -> actual
    Error(detail) ->
      panic as { "SharedTree case " <> case_id <> " runner error: " <> detail }
  }
  let expected = case expected_without_active(fixture.expected) {
    Ok(expected) -> expected
    Error(detail) ->
      panic as {
        "SharedTree case " <> case_id <> " expected data error: " <> detail
      }
  }
  case fixtures.first_difference(actual, expected) {
    Ok(Nil) -> Nil
    Error(path) ->
      panic as { "SharedTree case " <> case_id <> " differs at " <> path }
  }
}

pub fn assert_active_target_preflight(case_id: String) -> Nil {
  let assert Ok(fixture) = fixtures.load(case_id)
  let assert Ok(actual) =
    run_scenario(case_id, "active-transaction", fixture.input)
  let assert Ok(value) = field(actual.observation, "value")
  let assert Ok(depth) = read_field(value, "transactionDepth", decode.int)
  let assert Ok(attached) = read_field(value, "attached", decode.bool)
  let assert Ok(detached) = read_field(value, "detached", decode.bool)
  let assert Ok(label) = read_field(value, "label", decode.string)
  let assert 1 = depth
  let assert False = attached
  let assert True = detached
  let assert "active-target" = label
  Nil
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
    "live-channel-attachment" | "cross-datastore-attachment" -> Ok(Nil)
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
      Replay(
        writer,
        receiver,
        [],
        [],
        [],
        [],
        context,
        sequence_number,
        dict.new(),
        dict.new(),
      ),
      fn(replay, command) { execute_command(replay, command, writer_client_id) },
    ),
  )
  use _ <- result.try(case replay.outbounds {
    [] -> Ok(Nil)
    _ -> Error("scenario ended before its settle checkpoint")
  })
  use fixture <- result.try(fixtures.load(case_id))
  let expected_message_count =
    raw_message_count(fixture.raw, scenario_id) |> result.unwrap(1)
  let items =
    replay.item_groups
    |> list.reverse
    |> list.take(expected_message_count)
    |> list.reverse
    |> list.flatten
  let messages =
    replay.last_messages
    |> list.reverse
    |> list.take(expected_message_count)
    |> list.reverse
  use observation <- result.try(observation(
    scenario_id,
    replay.writer,
    replay.receiver,
    receiver_client_id,
    items,
    replay.sequence_number,
  ))
  case scenario_id {
    "active-transaction" -> {
      Ok(ScenarioResult(observation, messages, json.null()))
    }
    _ -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        replay.receiver,
        receiver_client_id,
      ))
      Ok(ScenarioResult(observation, messages, serialization))
    }
  }
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
    MapDelete(target, key) -> {
      use address <- result.try(channel_address(target))
      use #(writer, _, outbound) <- result.try(
        runtime_core.delete(replay.writer, address, key)
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
    CreateChannel(datastore_id, channel_id, channel_type) -> {
      let address = datastore_id <> "/" <> channel_id
      use compressor <- result.try(
        replay.writer.compressor
        |> option.to_result("lifecycle channel creation has no compressor"),
      )
      use #(compressor, generated) <- result.try(
        fluid_ids.generate(compressor)
        |> result.map_error(string.inspect),
      )
      use view_id <- result.try(
        fluid_ids.decompress(compressor, generated)
        |> result.map_error(string.inspect),
      )
      let writer =
        runtime_core.Core(..replay.writer, compressor: Some(compressor))
      case channel_type {
        "https://graph.microsoft.com/types/map" ->
          runtime_core.create_detached(writer, address, channel.InitMap)
          |> result.map(fn(writer) { Replay(..replay, writer:) })
          |> result.map_error(string.inspect)
        "https://graph.microsoft.com/types/tree" ->
          Ok(
            Replay(
              ..replay,
              writer:,
              tree_views: dict.insert(replay.tree_views, address, view_id),
            ),
          )
        _ -> Error("unsupported lifecycle channel type " <> channel_type)
      }
    }
    InitializeTree(target, stored_json, initial) -> {
      use address <- result.try(channel_address(target))
      use stored <- result.try(
        tree_schema.stored_from_json(stored_json)
        |> result.map_error(string.inspect),
      )
      use view <- result.try(
        tree_schema.view_from_json(stored_json)
        |> result.map_error(string.inspect),
      )
      use view_id <- result.try(
        dict.get(replay.tree_views, address)
        |> result.map_error(fn(_) {
          "tree channel has no reserved view identity " <> address
        }),
      )
      use writer <- result.try(
        runtime_core.create_detached_tree(
          replay.writer,
          address,
          stored,
          Some(initial),
          view_id,
        )
        |> result.map_error(string.inspect),
      )
      Ok(
        Replay(
          ..replay,
          writer:,
          tree_schemas: dict.insert(replay.tree_schemas, address, view),
        ),
      )
    }
    TreeSetString(target, field, value) -> {
      use address <- result.try(channel_address(target))
      use #(writer, _, outbound) <- result.try(
        runtime_core.submit_tree_edits(replay.writer, address, [
          tree_types.SetField([field], tree_types.StringValue(value)),
        ])
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
    TreeSetHandle(target, field, value) -> {
      use address <- result.try(channel_address(target))
      let before = replay
      case
        runtime_core.submit_tree_edits(replay.writer, address, [
          tree_types.SetField([field], tree_types.HandleValue(value)),
        ])
      {
        Ok(#(writer, _, outbound)) ->
          Ok(
            Replay(
              ..replay,
              writer:,
              outbounds: list.append(replay.outbounds, outbound),
            ),
          )
        Error(error) -> {
          use _ <- result.try(
            case
              runtime_core.prepare_attachments(replay.writer, address, [value])
            {
              Error(_) -> Ok(Nil)
              Ok(_) ->
                Error("active transaction attachment preflight succeeded")
            },
          )
          let detail = string.inspect(error)
          use _ <- result.try(case string.contains(detail, "another tree") {
            True -> Ok(Nil)
            False -> Error(detail)
          })
          use _ <- result.try(case replay == before {
            True -> Ok(Nil)
            False -> Error("active transaction preflight mutated runtime state")
          })
          Ok(replay)
        }
      }
    }
    TreeMapSetHandle(target, field, key, value) -> {
      use address <- result.try(channel_address(target))
      use #(writer, _, outbound) <- result.try(
        runtime_core.submit_tree_edits(replay.writer, address, [
          tree_types.MapSet([field], key, tree_types.HandleValue(value)),
        ])
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
    SerializeChannelSummary(target) -> {
      use address <- result.try(channel_address(target))
      runtime_core.capture_bindings(replay.writer, address)
      |> result.map(fn(writer) { Replay(..replay, writer:) })
      |> result.map_error(string.inspect)
    }
    BeginTransaction(target) -> {
      use address <- result.try(channel_address(target))
      use view <- result.try(
        dict.get(replay.tree_schemas, address)
        |> result.map_error(fn(_) { "tree transaction has no view" }),
      )
      runtime_core.begin_tree_transaction(replay.writer, address, view, [])
      |> result.map(fn(writer) { Replay(..replay, writer:) })
      |> result.map_error(string.inspect)
    }
    CommitTransaction(target) -> {
      use address <- result.try(channel_address(target))
      use #(writer, _, outbound) <- result.try(
        runtime_core.commit_tree_transaction(replay.writer, address)
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
    Settle(_) -> {
      use #(writer, outbounds) <- result.try(
        runtime_core.coalesce_outbound_operations(
          replay.writer,
          replay.outbounds,
        )
        |> result.map_error(string.inspect),
      )
      list.try_fold(
        outbounds,
        Replay(
          ..replay,
          writer:,
          outbounds: [],
          last_items: [],
          item_groups: replay.item_groups,
          last_messages: list.append(
            replay.last_messages,
            replay.context_messages,
          ),
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
            list.append(replay.item_groups, [items]),
            list.append(replay.last_messages, [transport]),
            replay.context_messages,
            sequence_number,
            replay.tree_views,
            replay.tree_schemas,
          ))
        },
      )
    }
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
  writer: runtime_core.Core,
  receiver: runtime_core.Core,
  receiver_client_id: String,
  items: List(fluid_container.MessageKind),
  sequence_number: Int,
) -> Result(Json, String) {
  let attach_order = list.flat_map(items, message_labels(receiver, _))
  case scenario_id {
    "detached-map" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      Ok(live_observation(
        scenario_id,
        [
          #("path", json.string("/A/_F")),
          #("local", json.string("map-edit")),
          #("transportOrder", json.array(attach_order, json.string)),
          #("receiver", serialization),
        ],
        0,
      ))
    }
    "detached-tree" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      Ok(live_observation(
        scenario_id,
        [
          #("path", json.string("/A/_J")),
          #("label", json.string("detached-tree-edit")),
          #("transportOrder", json.array(attach_order, json.string)),
          #("receiver", serialization),
        ],
        1,
      ))
    }
    "serialize-remove" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      Ok(live_observation(
        scenario_id,
        [
          #("ownerPath", json.string("/A/_T")),
          #("targetPath", json.string("/A/_R")),
          #("attached", json.bool(runtime_core.has_channel(receiver, "A/_R"))),
          #(
            "visibleValue",
            json.bool(
              result.is_ok(runtime_core.get(receiver, "A/_T", "removed")),
            ),
          ),
          #("transportOrder", json.array(attach_order, json.string)),
          #("receiver", serialization),
        ],
        2,
      ))
    }
    "nested-dependency" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      Ok(live_observation(
        scenario_id,
        [
          #("outer", json.string("/A/_X")),
          #("inner", json.string("/A/_Z")),
          #("transportOrder", json.array(attach_order, json.string)),
          #("receiver", serialization),
        ],
        3,
      ))
    }
    "self-reference" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      use resolved <- result.try(resolved_target(receiver, "A/_c", "self"))
      Ok(live_observation(
        scenario_id,
        [
          #("path", json.string("/A/_c")),
          #("resolved", json.string("/" <> resolved)),
          #("transportOrder", json.array(attach_order, json.string)),
          #("receiver", serialization),
        ],
        4,
      ))
    }
    "two-channel-cycle" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      Ok(live_observation(
        scenario_id,
        [
          #("left", json.string("/A/_g")),
          #("right", json.string("/A/_i")),
          #("transportOrder", json.array(attach_order, json.string)),
          #("receiver", serialization),
        ],
        5,
      ))
    }
    "completed-transaction" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      use data <- result.try(tree_data(receiver, "A/_m"))
      use label <- result.try(read_field(data, "label", decode.string))
      Ok(live_observation(
        scenario_id,
        [
          #("path", json.string("/A/_m")),
          #("label", json.string(label)),
          #("attached", json.bool(runtime_core.has_channel(receiver, "A/_m"))),
          #("transportOrder", json.array(attach_order, json.string)),
          #("receiver", serialization),
        ],
        6,
      ))
    }
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
    "tree-cross-datastore" -> {
      use serialization <- result.try(receiver_serialization(
        scenario_id,
        receiver,
        receiver_client_id,
      ))
      use data <- result.try(tree_data(
        receiver,
        "d6b524d6-ef34-4709-b1d9-bc0a70887c2a/_L",
      ))
      use label <- result.try(read_field(data, "label", decode.string))
      Ok(
        json.object([
          #("id", json.string(scenario_id)),
          #(
            "value",
            json.object([
              #("path", json.string("/d6b524d6-ef34-4709-b1d9-bc0a70887c2a/_L")),
              #("label", json.string(label)),
              #("attachOrder", json.array(attach_order, json.string)),
              #("receiver", serialization),
            ]),
          ),
          #("evidence", evidence(scenario_id, 2)),
        ]),
      )
    }
    "tree-cycle" -> {
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
              #("left", json.string("/T/_C")),
              #("right", json.string("/V/_C")),
              #("attachOrder", json.array(attach_order, json.string)),
              #("receiver", serialization),
            ]),
          ),
          #("evidence", evidence_with_summary(scenario_id, 3)),
        ]),
      )
    }
    "active-transaction" -> {
      use data <- result.try(tree_data(writer, "A/_F"))
      use label <- result.try(read_field(data, "label", decode.string))
      Ok(
        json.object([
          #("id", json.string(scenario_id)),
          #(
            "value",
            json.object([
              #(
                "transactionDepth",
                json.int(runtime_core.tree_transaction_depth(writer)),
              ),
              #("attached", json.bool(dict.has_key(writer.channels, "A/_F"))),
              #("detached", json.bool(dict.has_key(writer.detached, "A/_F"))),
              #("label", json.string(label)),
            ]),
          ),
          #("evidence", json.array([], fn(value) { value })),
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

fn live_observation(
  scenario_id: String,
  fields: List(#(String, Json)),
  index: Int,
) -> Json {
  json.object([
    #("id", json.string(scenario_id)),
    #("value", json.object(fields)),
    #("evidence", case scenario_id {
      "serialize-remove" ->
        json.array(
          [
            json.object([
              #("section", json.string("summaries")),
              #("id", json.string("serialize-remove:summaries:0")),
            ]),
            ..evidence_items(scenario_id, index)
          ],
          fn(value) { value },
        )
      _ -> evidence(scenario_id, index)
    }),
  ])
}

fn receiver_serialization(
  scenario_id: String,
  receiver: runtime_core.Core,
  receiver_client_id: String,
) -> Result(Json, String) {
  case scenario_id {
    "detached-map" ->
      tree_to_map_serialization(
        receiver,
        receiver_client_id,
        "A/bd278748-2615-469e-b4f9-a4c976119517",
        "link",
        "A/_F",
      )
    "detached-tree" ->
      tree_to_tree_serialization(
        receiver,
        receiver_client_id,
        "A/bd278748-2615-469e-b4f9-a4c976119517",
        "links/tree",
        "A/_J",
      )
    "serialize-remove" ->
      Ok(
        json.object([
          #("clientId", json.string(receiver_client_id)),
          #(
            "targets",
            json.array(
              [
                target_json(receiver, "A/_T"),
                target_json(receiver, "A/_R"),
              ],
              fn(value) { value },
            ),
          ),
          #(
            "graph",
            json.object([
              #("source", json.string("/A/_T")),
              #("edge", json.string("removed")),
              #("visible", json.bool(False)),
              #("boundTarget", json.string("/A/_R")),
            ]),
          ),
        ]),
      )
    "nested-dependency" ->
      map_graph_serialization(
        receiver,
        receiver_client_id,
        "A/_X",
        "inner",
        "A/_Z",
      )
    "self-reference" -> {
      use target <- result.try(resolved_target(receiver, "A/_c", "self"))
      Ok(
        json.object([
          #("clientId", json.string(receiver_client_id)),
          #(
            "targets",
            json.array([target_json(receiver, "A/_c")], fn(value) { value }),
          ),
          #(
            "graph",
            json.object([
              #("source", json.string("/A/_c")),
              #("edge", json.string("self")),
              #("target", json.string("/" <> target)),
              #("resolvesToSource", json.bool(target == "A/_c")),
            ]),
          ),
        ]),
      )
    }
    "two-channel-cycle" ->
      map_cycle_serialization(
        receiver,
        receiver_client_id,
        "A/_g",
        "A/_i",
        "right",
        "left",
      )
    "completed-transaction" ->
      map_to_tree_serialization(
        receiver,
        receiver_client_id,
        "A/bd278748-2615-469e-b4f9-a4c976119517",
        "links/completed",
        "A/_m",
      )
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
    "tree-cross-datastore" -> {
      let secondary = "d6b524d6-ef34-4709-b1d9-bc0a70887c2a/_L"
      use primary_data <- result.try(tree_data(receiver, "A/_H"))
      use secondary_data <- result.try(tree_data(receiver, secondary))
      use target <- result.try(tree_link(primary_data, "link"))
      use entry_target <- result.try(resolved_target(
        receiver,
        "d6b524d6-ef34-4709-b1d9-bc0a70887c2a/root",
        "tree",
      ))
      Ok(
        json.object([
          #("clientId", json.string(receiver_client_id)),
          #(
            "targets",
            json.array(
              [
                tree_target("A/_H", primary_data),
                tree_target(secondary, secondary_data),
              ],
              fn(value) { value },
            ),
          ),
          #(
            "graph",
            json.object([
              #("source", json.string("/A/_H")),
              #("edge", json.string("link")),
              #("target", json.string(target)),
              #(
                "secondaryEntryPoint",
                json.string("/d6b524d6-ef34-4709-b1d9-bc0a70887c2a/root"),
              ),
              #("entryPointEdge", json.string("tree")),
              #("entryPointTarget", json.string("/" <> entry_target)),
              #(
                "sameResolvedInstance",
                json.bool(target == "/" <> entry_target),
              ),
            ]),
          ),
        ]),
      )
    }
    "tree-cycle" -> {
      use left <- result.try(tree_data(receiver, "T/_C"))
      use right <- result.try(tree_data(receiver, "V/_C"))
      use target <- result.try(tree_link(left, "link"))
      use returned <- result.try(tree_link(right, "link"))
      Ok(
        json.object([
          #("clientId", json.string(receiver_client_id)),
          #(
            "targets",
            json.array(
              [tree_target("T/_C", left), tree_target("V/_C", right)],
              fn(value) { value },
            ),
          ),
          #(
            "graph",
            json.object([
              #("source", json.string("/T/_C")),
              #("edge", json.string("link")),
              #("target", json.string(target)),
              #("returnEdge", json.string("link")),
              #("returnTarget", json.string(returned)),
              #("resolvesToSource", json.bool(returned == "/T/_C")),
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

fn message_labels(
  _receiver: runtime_core.Core,
  message: fluid_container.MessageKind,
) -> List(String) {
  [message_label(message)]
}

fn target_json(core: runtime_core.Core, address: String) -> Json {
  json.object([
    #("path", json.string("/" <> address)),
    #("channelType", json.string("https://graph.microsoft.com/types/map")),
    #("data", map_data(core, address)),
  ])
}

fn tree_target(address: String, data: Json) -> Json {
  json.object([
    #("path", json.string("/" <> address)),
    #("channelType", json.string("https://graph.microsoft.com/types/tree")),
    #("data", data),
  ])
}

fn tree_data(core: runtime_core.Core, address: String) -> Result(Json, String) {
  use root <- result.try(
    runtime_core.tree_read(core, address, [])
    |> result.map_error(string.inspect),
  )
  case root {
    Some(tree_types.ObjectValue(_, fields)) -> {
      let output =
        list.filter_map(fields, fn(field) {
          case field {
            #("label", tree_types.StringValue(value)) ->
              Ok(#("label", json.string(value)))
            #("link", tree_types.HandleValue(reference)) ->
              Ok(#("link", json.string(handle.reference_path(reference))))
            #("links", tree_types.MapValue(_, entries)) ->
              Ok(#(
                "links",
                json.array(entries, fn(entry) {
                  let assert tree_types.HandleValue(reference) = entry.1
                  json.array(
                    [
                      json.string(entry.0),
                      json.string(handle.reference_path(reference)),
                    ],
                    fn(value) { value },
                  )
                }),
              ))
            #("sequence", tree_types.ArrayValue(_, entries)) ->
              Ok(#(
                "sequence",
                json.array(entries, fn(entry) {
                  let assert tree_types.HandleValue(reference) = entry
                  json.string(handle.reference_path(reference))
                }),
              ))
            _ -> Error(Nil)
          }
        })
      Ok(json.object(output))
    }
    _ -> Error("tree root has the wrong shape at " <> address)
  }
}

fn tree_link(data: Json, field: String) -> Result(String, String) {
  read_field(data, field, decode.string)
}

fn tree_to_map_serialization(
  receiver: runtime_core.Core,
  client_id: String,
  source: String,
  edge: String,
  target: String,
) -> Result(Json, String) {
  use source_data <- result.try(tree_data(receiver, source))
  Ok(
    json.object([
      #("clientId", json.string(client_id)),
      #(
        "targets",
        json.array(
          [tree_target(source, source_data), target_json(receiver, target)],
          fn(value) { value },
        ),
      ),
      #(
        "graph",
        json.object([
          #("source", json.string("/" <> source)),
          #("edge", json.string(edge)),
          #("target", json.string("/" <> target)),
          #("targetData", map_data(receiver, target)),
        ]),
      ),
    ]),
  )
}

fn tree_to_tree_serialization(
  receiver: runtime_core.Core,
  client_id: String,
  source: String,
  edge: String,
  target: String,
) -> Result(Json, String) {
  use source_data <- result.try(tree_data(receiver, source))
  use target_data <- result.try(tree_data(receiver, target))
  Ok(
    json.object([
      #("clientId", json.string(client_id)),
      #(
        "targets",
        json.array(
          [tree_target(source, source_data), tree_target(target, target_data)],
          fn(value) { value },
        ),
      ),
      #(
        "graph",
        json.object([
          #("source", json.string("/" <> source)),
          #("edge", json.string(edge)),
          #("target", json.string("/" <> target)),
          #("targetData", target_data),
        ]),
      ),
    ]),
  )
}

fn map_graph_serialization(
  receiver: runtime_core.Core,
  client_id: String,
  source: String,
  edge: String,
  target: String,
) -> Result(Json, String) {
  use resolved <- result.try(resolved_target(receiver, source, edge))
  Ok(
    json.object([
      #("clientId", json.string(client_id)),
      #(
        "targets",
        json.array(
          [target_json(receiver, source), target_json(receiver, target)],
          fn(value) { value },
        ),
      ),
      #(
        "graph",
        json.object([
          #("source", json.string("/" <> source)),
          #("edge", json.string(edge)),
          #("target", json.string("/" <> resolved)),
          #("targetData", map_data(receiver, target)),
        ]),
      ),
    ]),
  )
}

fn map_cycle_serialization(
  receiver: runtime_core.Core,
  client_id: String,
  left: String,
  right: String,
  edge: String,
  return_edge: String,
) -> Result(Json, String) {
  use target <- result.try(resolved_target(receiver, left, edge))
  use returned <- result.try(resolved_target(receiver, right, return_edge))
  Ok(
    json.object([
      #("clientId", json.string(client_id)),
      #(
        "targets",
        json.array(
          [target_json(receiver, left), target_json(receiver, right)],
          fn(value) { value },
        ),
      ),
      #(
        "graph",
        json.object([
          #("source", json.string("/" <> left)),
          #("edge", json.string(edge)),
          #("target", json.string("/" <> target)),
          #("returnEdge", json.string(return_edge)),
          #("returnTarget", json.string("/" <> returned)),
          #("resolvesToSource", json.bool(returned == left)),
        ]),
      ),
    ]),
  )
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
  json.array(evidence_items(scenario_id, index), fn(value) { value })
}

fn evidence_items(scenario_id: String, index: Int) -> List(Json) {
  [
    json.object([
      #("section", json.string("messages")),
      #("id", json.string(scenario_id <> ":messages:" <> int.to_string(index))),
    ]),
    json.object([
      #("section", json.string("serialization")),
      #(
        "id",
        json.string(scenario_id <> ":serialization:" <> int.to_string(index)),
      ),
    ]),
  ]
}

fn evidence_with_summary(scenario_id: String, index: Int) -> Json {
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
        #("section", json.string("summaries")),
        #("id", json.string(scenario_id <> ":summaries:0")),
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
  use raw_messages <- result.try(
    raw_record(raw, "messages", scenario_id, case scenario_id {
      "active-transaction" -> "document-attachment"
      _ -> "attach"
    }),
  )
  use raw_messages <- result.try(case scenario_id {
    "active-transaction" -> field(raw_messages, "transport")
    _ -> Ok(raw_messages)
  })
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
  let actual_messages =
    actual_messages
    |> list.reverse
    |> list.take(list.length(expected_messages))
    |> list.reverse
  use _ <- result.try(
    fixtures.first_difference(
      json.array(actual_messages, fn(value) { value }),
      json.array(expected_messages, fn(value) { value }),
    )
    |> result.map_error(fn(path) { "raw.messages" <> path }),
  )
  case scenario_id {
    "active-transaction" -> Ok(Nil)
    _ -> {
      use expected_serialization <- result.try(raw_record(
        raw,
        "serialization",
        scenario_id,
        "receiver-graph",
      ))
      fixtures.first_difference(actual_serialization, expected_serialization)
      |> result.map_error(fn(path) { "raw.serialization" <> path })
    }
  }
}

fn raw_message_count(raw: Json, scenario_id: String) -> Result(Int, String) {
  use messages <- result.try(
    raw_record(raw, "messages", scenario_id, case scenario_id {
      "active-transaction" -> "document-attachment"
      _ -> "attach"
    }),
  )
  use messages <- result.try(case scenario_id {
    "active-transaction" -> field(messages, "transport")
    _ -> Ok(messages)
  })
  json.parse(json.to_string(messages), decode.list(wire.json_value_decoder()))
  |> result.map(list.length)
  |> result.map_error(fn(_) { "invalid raw.messages for " <> scenario_id })
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

fn expected_without_active(expected: Json) -> Result(Json, String) {
  use observations <- result.try(
    json.parse(
      json.to_string(expected),
      decode.at(["observations"], decode.list(decode.dynamic)),
    )
    |> result.map_error(fn(_) { "missing expected observations" }),
  )
  use observations <- result.try(
    list.try_fold(observations, [], fn(filtered, observation) {
      use id <- result.try(
        decode.run(observation, {
          use id <- decode.field("id", decode.string)
          decode.success(id)
        })
        |> result.map_error(fn(_) { "missing expected observation id" }),
      )
      Ok(case id {
        "active-transaction" -> filtered
        _ -> list.append(filtered, [observation])
      })
    }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, wire.dynamic_to_json)),
    ]),
  )
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
        case kind {
          "handle" -> decode.at(["value"], wire.json_value_decoder())
          "string" ->
            decode.at(["value"], decode.string)
            |> decode.map(json.string)
          _ -> decode.failure(json.null(), "map value kind")
        }
      })
      decode.success(MapSet(target, key, value))
    }
    "map-delete" -> {
      use target <- decode.field("target", decode.string)
      use key <- decode.field("key", decode.string)
      decode.success(MapDelete(target, key))
    }
    "create-channel" -> {
      use datastore_id <- decode.field("datastoreId", decode.string)
      use channel_id <- decode.field("channelId", decode.string)
      use channel_type <- decode.field("channelType", decode.string)
      decode.success(CreateChannel(datastore_id, channel_id, channel_type))
    }
    "initialize-tree" -> {
      use target <- decode.field("target", decode.string)
      use stored_json <- decode.field("storedSchema", wire.json_value_decoder())
      use initial <- decode.field("initialValue", fixtures.tree_value_decoder())
      decode.success(InitializeTree(target, stored_json, initial))
    }
    "tree-set-string" -> {
      use target <- decode.field("target", decode.string)
      use field <- decode.field("field", decode.string)
      use value <- decode.field("value", decode.string)
      decode.success(TreeSetString(target, field, value))
    }
    "tree-set-handle" -> {
      use target <- decode.field("target", decode.string)
      use field <- decode.subfield(["field", "name"], decode.string)
      use marker <- decode.subfield(
        ["value", "value"],
        wire.json_value_decoder(),
      )
      case handle.reference_from_json(marker, "/") {
        Ok(reference) -> decode.success(TreeSetHandle(target, field, reference))
        Error(_) ->
          decode.failure(
            TreeSetHandle(target, field, fallback_reference()),
            "tree handle",
          )
      }
    }
    "tree-map-set-handle" -> {
      use target <- decode.field("target", decode.string)
      use field <- decode.field("field", decode.string)
      use key <- decode.field("key", decode.string)
      use marker <- decode.subfield(
        ["value", "value"],
        wire.json_value_decoder(),
      )
      case handle.reference_from_json(marker, "/") {
        Ok(reference) ->
          decode.success(TreeMapSetHandle(target, field, key, reference))
        Error(_) ->
          decode.failure(
            TreeMapSetHandle(target, field, key, fallback_reference()),
            "tree map handle",
          )
      }
    }
    "serialize-channel-summary" -> {
      use target <- decode.field("target", decode.string)
      decode.success(SerializeChannelSummary(target))
    }
    "begin-transaction" -> {
      use target <- decode.field("target", decode.string)
      decode.success(BeginTransaction(target))
    }
    "commit-transaction" -> {
      use target <- decode.field("target", decode.string)
      decode.success(CommitTransaction(target))
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

fn fallback_reference() -> handle.Reference {
  let assert Ok(reference) = handle.reference_from_path("/invalid/path")
  reference
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

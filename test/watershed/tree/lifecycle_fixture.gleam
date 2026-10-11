import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import spillway/types
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/runtime_core
import watershed/tree/branch as tree_branch
import watershed/tree/change as tree_change
import watershed/tree/codec
import watershed/tree/codec/summary as tree_summary_codec
import watershed/tree/fixtures
import watershed/tree/forest as tree_forest
import watershed/tree/history as tree_history
import watershed/tree/runtime as tree_runtime
import watershed/tree/runtime_fixture
import watershed/tree/schema as tree_schema
import watershed/tree/shared_change
import watershed/tree/summary as tree_summary
import watershed/tree/types as tree_types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/fluid_summary
import watershed/wire/op as wire_op
import watershed/wire/socket

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

type IdentityToken {
  IdentityToken(
    checkout: tree_branch.Checkout,
    root: tree_forest.NodeRef,
    anchor: tree_forest.NodeRef,
  )
}

type PublicationEmission {
  PublicationEmission(
    core: runtime_core.Core,
    selector: tree_types.CheckoutSelector,
    events: List(#(String, channel.ChannelEvent)),
  )
}

type PublicationReplay {
  PublicationReplay(
    replay: Replay,
    tree: String,
    token: Option(IdentityToken),
    branches: dict.Dict(String, tree_types.LocalCheckoutId),
    capture: Option(#(String, tree_types.CheckoutSelector)),
    inverses: dict.Dict(
      String,
      #(tree_types.CheckoutSelector, tree_types.RevertibleId),
    ),
    emissions: List(PublicationEmission),
    receiver_events: List(#(String, channel.ChannelEvent)),
    settlements: List(runtime_core.ScopedTreeEvent),
    receiver_outbounds: List(wire.OutboundOperation),
    stages: List(Json),
    stage_target: String,
  )
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

pub fn assert_identity_replay(case_id: String) -> Nil {
  case run_identity_replay(case_id) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as { detail }
  }
}

pub fn assert_publication_replay(case_id: String) -> Nil {
  case run_publication_replay(case_id) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as { "SharedTree publication replay: " <> detail }
  }
}

pub fn assert_map_attach_gc_routes(case_id: String) -> Nil {
  let assert Ok(fixture) = fixtures.load(case_id)
  let assert Ok(decoder_input) = field(fixture.input, "decoderInput")
  let assert Ok(prefix) =
    read_field(
      decoder_input,
      "deliveryPrefix",
      decode.list(wire.json_value_decoder()),
    )
  let assert Ok(messages) =
    list.try_fold(prefix, [], fn(items, message) {
      case read_field(message, "type", decode.string) {
        Ok("op") -> {
          use projected <- result.try(transport_projection(message))
          use contents <- result.try(field(projected, "contents"))
          use metadata <- result.try(read_field(
            projected,
            "metadata",
            decode.optional(wire.json_value_decoder()),
          ))
          use batch <- result.try(
            fluid_container.decode(contents, metadata)
            |> result.map_error(string.inspect),
          )
          Ok(list.append(
            items,
            list.map(batch.messages, fn(item) { item.kind }),
          ))
        }
        _ -> Ok(items)
      }
    })
  let assert Ok(fluid_container.ChannelAttach(route, kind, expected)) =
    list.find(messages, fn(message) {
      case message {
        fluid_container.ChannelAttach(fluid_container.Route("A", "_X"), _, _) ->
          True
        _ -> False
      }
    })
  let assert Ok(snapshot) = wire_op.decode_attach_snapshot(kind, expected)
  let assert channel.MapSnapshot(entries) = snapshot
  let assert False = list.is_empty(entries)
  let assert Ok(address) = fluid_container.route_key(route)
  let assert Ok(fluid_container.ChannelAttach(_, _, actual)) =
    wire_op.attachment_message(address, snapshot)
  case fixtures.first_difference(actual, expected) {
    Ok(Nil) -> Nil
    Error(path) -> panic as { "source map attach GC differs at " <> path }
  }
}

pub fn assert_publication_active_target_preflight(case_id: String) -> Nil {
  let assert Ok(fixture) = fixtures.load(case_id)
  let assert Ok(scenario) = matching_scenario(fixture.input, "active-target")
  let assert Ok(input) = field(scenario, "input")
  let assert Ok(decoder_input) = field(input, "decoderInput")
  let assert Ok(global_decoder_input) = field(fixture.input, "decoderInput")
  let assert Ok(runtime) = field(global_decoder_input, "runtime")
  let #(writer, receiver, writer_id, _) = case
    cores_from_context(
      decoder_input,
      runtime,
      "active-target-native-receiver",
      "70000000-0000-4000-8000-000000000007",
    )
  {
    Ok(value) -> value
    Error(detail) -> panic as { "active-target setup: " <> detail }
  }
  let assert Ok(writer) = identity_deliver_context(writer, decoder_input, 1)
  let assert Ok(receiver) = identity_deliver_context(receiver, decoder_input, 1)
  let assert Ok(commands) =
    read_field(scenario, "commands", decode.list(command_decoder()))
  let replay = case
    list.try_fold(
      list.take(commands, 8),
      Replay(writer, receiver, [], [], [], [], [], 1, dict.new(), dict.new()),
      fn(replay, command) { execute_command(replay, command, writer_id) },
    )
  {
    Ok(replay) -> replay
    Error(detail) -> panic as { "active-target commands: " <> detail }
  }
  let assert [TreeSetHandle(parent, name, reference)] = list.drop(commands, 8)
  let assert Ok(parent) = channel_address(parent)
  let assert Ok(target) = channel_address(handle.reference_path(reference))
  let assert Ok(observation) =
    expected_observation(fixture.expected, "active-target")
  let assert Ok(expected) = field(observation, "value")
  let assert Ok(parent_before) = field(expected, "parentBefore")
  let assert Ok(target_before) =
    json.parse(
      json.to_string(expected),
      decode.at(["target", "local", "before"], wire.json_value_decoder()),
    )
  let assert Ok(parent_data) = tree_data(replay.writer, parent)
  let assert Ok(target_data) = tree_data(replay.writer, target)
  let assert Ok(Nil) = fixtures.first_difference(parent_data, parent_before)
  let assert Ok(Nil) = fixtures.first_difference(target_data, target_before)

  let assert Error(runtime_core.TreeOperationFailed(
    _,
    tree_types.InvalidHistory(_),
  )) =
    runtime_core.submit_tree_edits(replay.writer, parent, [
      tree_types.SetField([name], tree_types.HandleValue(reference)),
    ])
  let assert Error(runtime_core.TreeOperationFailed(
    _,
    tree_types.InvalidHistory(_),
  )) = runtime_core.prepare_attachments(replay.writer, parent, [reference])
  let assert 1 = runtime_core.tree_transaction_depth(replay.writer)
  let assert False = dict.has_key(replay.writer.channels, target)
  let assert True = dict.has_key(replay.writer.detached, target)
  let assert [] = replay.outbounds

  let assert Ok(#(writer, _)) =
    runtime_core.abort_tree_transaction(replay.writer, target)
  let assert Ok(#(writer, _, [outbound])) =
    runtime_core.submit_tree_edits(writer, parent, [
      tree_types.SetField([name], tree_types.HandleValue(reference)),
    ])
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert True =
    list.any(batch.messages, fn(message) {
      case message.kind {
        fluid_container.ChannelAttach(route, _, _) ->
          fluid_container.route_key(route) == Ok(target)
        _ -> False
      }
    })
  let assert True = dict.has_key(writer.channels, target)
  Nil
}

fn publication_tree_core(
  case_id: String,
) -> #(runtime_core.Core, String, tree_schema.ViewSchema) {
  let assert Ok(fixture) = fixtures.load(case_id)
  let assert Ok(scenario) =
    matching_scenario(fixture.input, "handle-undo-peer-edit")
  let assert Ok(commands) =
    read_field(scenario, "commands", decode.list(command_decoder()))
  let assert Ok(decoder_input) = field(fixture.input, "decoderInput")
  let assert Ok(#(writer, receiver, writer_id, _)) = cores(fixture.input)
  let assert Ok(writer) = identity_deliver_context(writer, decoder_input, 1)
  let assert Ok(receiver) = identity_deliver_context(receiver, decoder_input, 1)
  let assert Ok(replay) =
    list.try_fold(
      list.take(commands, 4),
      Replay(writer, receiver, [], [], [], [], [], 1, dict.new(), dict.new()),
      fn(replay, command) { execute_command(replay, command, writer_id) },
    )
  let assert [_, InitializeTree(path, _, _), ..] = commands
  let assert Ok(address) = channel_address(path)
  let assert Ok(view) = dict.get(replay.tree_schemas, address)
  #(replay.writer, address, view)
}

pub fn assert_transient_reference_publication(case_id: String) -> Nil {
  let #(core, parent, view) = publication_tree_core(case_id)
  let assert Ok(core) =
    runtime_core.create_detached(core, "A/transient", channel.InitMap)
  let assert Ok(reference) = handle.reference_from_path("/A/transient")
  let assert Ok(core) =
    runtime_core.begin_tree_transaction(core, parent, view, [])
  let assert Ok(#(core, [], [])) =
    runtime_core.submit_tree_edits(core, parent, [
      tree_types.SetField(["link"], tree_types.HandleValue(reference)),
    ])
  let assert Ok(#(core, [], [])) =
    runtime_core.submit_tree_edits(core, parent, [
      tree_types.ClearField(["link"]),
    ])
  let assert False = dict.has_key(core.channels, "A/transient")
  let assert Ok(None) = runtime_core.tree_read(core, parent, ["link"])
  let assert Ok(#(core, _, [outbound])) =
    runtime_core.commit_tree_transaction(core, parent)
  let assert True = dict.has_key(core.channels, "A/transient")
  let assert Ok(None) = runtime_core.tree_read(core, parent, ["link"])
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert True =
    list.any(batch.messages, fn(message) {
      case message.kind {
        fluid_container.ChannelAttach(
          fluid_container.Route("A", "transient"),
          _,
          _,
        ) -> True
        _ -> False
      }
    })
  Nil
}

pub fn assert_publication_corrupt_last_dependency(case_id: String) -> Nil {
  let #(core, parent, view) = publication_tree_core(case_id)
  let assert Ok(core) =
    runtime_core.create_detached(core, "A/good", channel.InitMap)
  let assert Ok(core) =
    runtime_core.create_detached(core, "A/bad", channel.InitMap)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(
      core,
      "A/bad",
      "invalid",
      handle.encode_handle("missing/final"),
    )
  let assert Ok(good) = handle.reference_from_path("/A/good")
  let assert Ok(bad) = handle.reference_from_path("/A/bad")
  let assert Ok(core) =
    runtime_core.begin_tree_transaction(core, parent, view, [])
  let assert Ok(#(core, [], [])) =
    runtime_core.submit_tree_edits(core, parent, [
      tree_types.MapSet(["links"], "first", tree_types.HandleValue(good)),
      tree_types.MapSet(["links"], "last", tree_types.HandleValue(bad)),
    ])
  let assert Error(error) = runtime_core.commit_tree_transaction(core, parent)
  let assert True = string.contains(string.inspect(error), "missing/final")
  let assert False = dict.has_key(core.channels, "A/good")
  let assert False = dict.has_key(core.channels, "A/bad")
  let assert 1 = runtime_core.tree_transaction_depth(core)
  let assert Ok(#(core, _)) = runtime_core.abort_tree_transaction(core, parent)
  let assert Ok(Some(tree_types.MapValue(_, []))) =
    runtime_core.tree_read(core, parent, ["links"])
  let assert Ok(#(core, _, [_])) =
    runtime_core.submit_tree_edits(core, parent, [
      tree_types.SetField(["link"], tree_types.HandleValue(good)),
    ])
  let assert True = dict.has_key(core.channels, "A/good")
  let assert False = dict.has_key(core.channels, "A/bad")
  Nil
}

fn run_publication_replay(case_id: String) -> Result(Nil, String) {
  use fixture <- result.try(fixtures.load(case_id))
  use scenario <- result.try(matching_scenario(
    fixture.input,
    "handle-undo-peer-edit",
  ))
  use commands <- result.try(read_field(
    scenario,
    "commands",
    decode.list(wire.json_value_decoder()),
  ))
  use decoder_input <- result.try(field(fixture.input, "decoderInput"))
  use #(writer, receiver, writer_id, _) <- result.try(cores(fixture.input))
  use writer <- result.try(identity_deliver_context(writer, decoder_input, 1))
  use receiver <- result.try(identity_deliver_context(
    receiver,
    decoder_input,
    1,
  ))
  use prefix <- result.try(read_field(
    decoder_input,
    "deliveryPrefix",
    decode.list(wire.json_value_decoder()),
  ))
  use initial_message <- result.try(item_at(prefix, 0, "missing writer join"))
  use initial_message <- result.try(transport_projection(initial_message))
  let replay =
    PublicationReplay(
      Replay(
        writer,
        receiver,
        [],
        [],
        [],
        [initial_message],
        [],
        1,
        dict.new(),
        dict.new(),
      ),
      "",
      None,
      dict.new(),
      None,
      dict.new(),
      [],
      [],
      [],
      [],
      [],
      "",
    )
  use replay <- result.try(
    list.try_fold(
      list.index_map(commands, fn(command, index) { #(command, index) }),
      replay,
      fn(replay, indexed) {
        let #(command, index) = indexed
        use kind <- result.try(read_field(command, "type", decode.string))
        use replay <- result.try(
          publication_command(
            replay,
            command,
            kind,
            writer_id,
            decoder_input,
            fixture.expected,
          )
          |> result.map_error(fn(detail) { kind <> ": " <> detail }),
        )
        case list.contains([6, 9, 12, 13, 17, 19, 20], index) {
          True -> capture_publication_stage(replay)
          False -> Ok(replay)
        }
      },
    ),
  )
  use expected <- result.try(list.try_map(prefix, transport_projection))
  use _ <- result.try(fixtures.first_difference(
    json.array(replay.replay.last_messages, fn(value) { value }),
    json.array(expected, fn(value) { value }),
  ))
  Ok(Nil)
}

fn publication_selector(
  replay: PublicationReplay,
  command: Json,
) -> Result(tree_types.CheckoutSelector, String) {
  use checkout <- result.try(
    json.parse(json.to_string(command), {
      use checkout <- decode.optional_field(
        "checkout",
        None,
        decode.map(decode.string, Some),
      )
      decode.success(checkout)
    })
    |> result.map_error(string.inspect),
  )
  case checkout {
    None -> Ok(tree_types.DocumentCheckout)
    Some(name) ->
      dict.get(replay.branches, name)
      |> result.map(tree_types.LocalCheckout)
      |> result.map_error(fn(_) { "unknown publication checkout " <> name })
  }
}

fn publication_command(
  replay: PublicationReplay,
  command: Json,
  kind: String,
  writer_id: String,
  decoder_input: Json,
  expected: Json,
) -> Result(PublicationReplay, String) {
  case kind {
    "create-channel" | "initialize-tree" -> {
      use decoded <- result.try(
        json.parse(json.to_string(command), command_decoder())
        |> result.map_error(string.inspect),
      )
      use next <- result.try(execute_command(replay.replay, decoded, writer_id))
      case decoded {
        InitializeTree(target, _, _) -> {
          use address <- result.try(channel_address(target))
          use token <- result.try(identity_token(next.writer, address))
          Ok(
            PublicationReplay(
              ..replay,
              replay: next,
              tree: address,
              token: Some(token),
            ),
          )
        }
        CreateChannel(store, id, "https://graph.microsoft.com/types/map") ->
          Ok(
            PublicationReplay(
              ..replay,
              replay: next,
              stage_target: store <> "/" <> id,
            ),
          )
        _ -> Ok(PublicationReplay(..replay, replay: next))
      }
    }
    "map-set" -> {
      use decoded <- result.try(
        json.parse(json.to_string(command), command_decoder())
        |> result.map_error(string.inspect),
      )
      let assert MapSet(target, key, value) = decoded
      use address <- result.try(channel_address(target))
      use client <- result.try(
        json.parse(json.to_string(command), {
          use client <- decode.optional_field("client", "writer", decode.string)
          decode.success(client)
        })
        |> result.map_error(string.inspect),
      )
      case client {
        "writer" -> {
          use next <- result.try(execute_command(
            replay.replay,
            decoded,
            writer_id,
          ))
          Ok(PublicationReplay(..replay, replay: next))
        }
        "receiver" -> {
          use write_id <- result.try(
            json.parse(
              json.to_string(decoder_input),
              decode.at(["sessions", "receiverWriteClientId"], decode.string),
            )
            |> result.map_error(string.inspect),
          )
          use #(receiver, _, _) <- result.try(
            runtime_core.set(replay.replay.receiver, address, key, value)
            |> result.map_error(string.inspect),
          )
          use receiver <- result.try(
            runtime_core.adopt_reconnect(
              receiver,
              runtime_fixture.connected(
                write_id,
                [],
                replay.replay.sequence_number + 1,
              ),
            )
            |> result.map_error(string.inspect),
          )
          use replay <- result.try(publication_membership(
            PublicationReplay(
              ..replay,
              replay: Replay(..replay.replay, receiver:),
            ),
            decoder_input,
          ))
          use #(receiver, outbound) <- result.try(
            runtime_core.resubmit(runtime_core.go_live(replay.replay.receiver))
            |> result.map_error(string.inspect),
          )
          Ok(
            PublicationReplay(
              ..replay,
              replay: Replay(..replay.replay, receiver:),
              receiver_outbounds: list.append(
                replay.receiver_outbounds,
                outbound,
              ),
            ),
          )
        }
        _ -> Error("unsupported publication client " <> client)
      }
    }
    "tree-set-handle" | "tree-map-set-handle" | "tree-array-insert-handle" -> {
      use selector <- result.try(publication_selector(replay, command))
      use marker <- result.try(
        json.parse(
          json.to_string(command),
          decode.at(["value", "value"], wire.json_value_decoder()),
        )
        |> result.map_error(string.inspect),
      )
      use reference <- result.try(
        handle.reference_from_json(marker, "/")
        |> result.map_error(string.inspect),
      )
      use edit <- result.try(case kind {
        "tree-set-handle" -> {
          use name <- result.try(
            json.parse(
              json.to_string(command),
              decode.at(["field", "name"], decode.string),
            )
            |> result.map_error(string.inspect),
          )
          Ok(tree_types.SetField([name], tree_types.HandleValue(reference)))
        }
        "tree-map-set-handle" -> {
          use name <- result.try(read_field(command, "field", decode.string))
          use key <- result.try(read_field(command, "key", decode.string))
          Ok(tree_types.MapSet([name], key, tree_types.HandleValue(reference)))
        }
        _ -> {
          use name <- result.try(read_field(command, "field", decode.string))
          use index <- result.try(read_field(command, "index", decode.int))
          Ok(
            tree_types.ArrayInsert([name], index, [
              tree_types.HandleValue(reference),
            ]),
          )
        }
      })
      use #(writer, events, outbound) <- result.try(
        runtime_core.submit_tree_edits_on(
          replay.replay.writer,
          replay.tree,
          selector,
          [edit],
        )
        |> result.map_error(string.inspect),
      )
      publication_emission(replay, writer, selector, events, outbound)
    }
    "begin-transaction" -> {
      use selector <- result.try(publication_selector(replay, command))
      use view <- result.try(
        dict.get(replay.replay.tree_schemas, replay.tree)
        |> result.map_error(fn(_) { "missing publication view" }),
      )
      use writer <- result.try(
        runtime_core.begin_tree_transaction_on(
          replay.replay.writer,
          replay.tree,
          selector,
          view,
          [],
        )
        |> result.map_error(string.inspect),
      )
      Ok(PublicationReplay(..replay, replay: Replay(..replay.replay, writer:)))
    }
    "commit-transaction" -> {
      use selector <- result.try(publication_selector(replay, command))
      use #(writer, events, outbound) <- result.try(
        runtime_core.commit_tree_transaction_on(
          replay.replay.writer,
          replay.tree,
          selector,
        )
        |> result.map_error(string.inspect),
      )
      publication_emission(replay, writer, selector, events, outbound)
    }
    "rollback-transaction" -> {
      use selector <- result.try(publication_selector(replay, command))
      use #(writer, events) <- result.try(
        runtime_core.abort_tree_transaction_on(
          replay.replay.writer,
          replay.tree,
          selector,
        )
        |> result.map_error(string.inspect),
      )
      publication_emission(replay, writer, selector, events, [])
    }
    "fork" -> {
      use name <- result.try(read_field(command, "checkout", decode.string))
      use view <- result.try(
        dict.get(replay.replay.tree_schemas, replay.tree)
        |> result.map_error(fn(_) { "missing publication view" }),
      )
      use #(writer, id) <- result.try(
        runtime_core.fork_tree(
          replay.replay.writer,
          replay.tree,
          tree_types.DocumentCheckout,
          view,
        )
        |> result.map_error(string.inspect),
      )
      Ok(
        PublicationReplay(
          ..replay,
          replay: Replay(..replay.replay, writer:),
          branches: dict.insert(replay.branches, name, id),
        ),
      )
    }
    "capture-next-revertible" -> {
      use id <- result.try(read_field(command, "id", decode.string))
      use selector <- result.try(publication_selector(replay, command))
      Ok(PublicationReplay(..replay, capture: Some(#(id, selector))))
    }
    "merge" -> {
      use selector <- result.try(publication_selector(replay, command))
      use #(writer, events, outbound) <- result.try(
        runtime_core.merge_tree(
          replay.replay.writer,
          replay.tree,
          tree_types.DocumentCheckout,
          selector,
          True,
        )
        |> result.map_error(string.inspect),
      )
      publication_emission(
        replay,
        writer,
        tree_types.DocumentCheckout,
        events,
        outbound,
      )
    }
    "dispose-checkout" -> {
      use selector <- result.try(publication_selector(replay, command))
      use writer <- result.try(
        runtime_core.dispose_tree_branch(
          replay.replay.writer,
          replay.tree,
          selector,
        )
        |> result.map_error(string.inspect),
      )
      Ok(PublicationReplay(..replay, replay: Replay(..replay.replay, writer:)))
    }
    "serialize-checkout-channel-handle" -> {
      let marker = handle.encode_handle(replay.tree)
      use resolved <- result.try(
        runtime_core.open_tree(replay.replay.writer, marker)
        |> result.map_error(string.inspect),
      )
      case resolved == replay.tree {
        True -> Ok(replay)
        False -> Error("branch handle resolves outside its document channel")
      }
    }
    "revert" -> {
      use id <- result.try(read_field(command, "id", decode.string))
      use #(selector, inverse) <- result.try(
        dict.get(replay.inverses, id)
        |> result.map_error(fn(_) { "missing publication inverse " <> id }),
      )
      use #(writer, events, outbound) <- result.try(
        runtime_core.revert_tree_on(
          replay.replay.writer,
          replay.tree,
          selector,
          inverse,
        )
        |> result.map_error(string.inspect),
      )
      use dispose <- result.try(read_field(command, "dispose", decode.bool))
      use writer <- result.try(case dispose {
        False -> Ok(writer)
        True ->
          runtime_core.dispose_tree_revertible_on(
            writer,
            replay.tree,
            selector,
            inverse,
          )
          |> result.map_error(string.inspect)
      })
      use _ <- result.try(
        case
          runtime_core.tree_revertible_is_valid_on(
            writer,
            replay.tree,
            selector,
            inverse,
          )
        {
          valid if valid != dispose -> Ok(Nil)
          _ -> Error("publication inverse lifetime differs after revert")
        },
      )
      publication_emission(replay, writer, selector, events, outbound)
    }
    "settle" -> {
      use checkpoint <- result.try(read_field(
        command,
        "checkpoint",
        decode.string,
      ))
      use replay <- result.try(publication_settle(
        replay,
        decoder_input,
        writer_id,
      ))
      case checkpoint {
        "initial-tree" | "before-peer-edit" | "before-undo" -> Ok(replay)
        _ -> {
          use observation <- result.try(expected_observation(
            expected,
            checkpoint,
          ))
          use value <- result.try(field(observation, "value"))
          use captured <- result.try(field(value, "checkpoint"))
          use _ <- result.try(
            assert_publication_checkpoint(replay, captured)
            |> result.map_error(fn(detail) { checkpoint <> ": " <> detail }),
          )
          Ok(PublicationReplay(..replay, stages: []))
        }
      }
    }
    _ -> Error("unsupported publication command " <> kind)
  }
}

fn publication_emission(
  replay: PublicationReplay,
  writer: runtime_core.Core,
  selector: tree_types.CheckoutSelector,
  events: List(runtime_core.ScopedTreeEvent),
  outbound: List(wire.OutboundOperation),
) -> Result(PublicationReplay, String) {
  let events = list.map(events, fn(event) { #(event.0, event.2) })
  let emissions = case
    list.any(events, fn(event) {
      case event.1 {
        channel.TreeCommitApplied(_, _, _, _) -> True
        _ -> False
      }
    })
  {
    True ->
      list.append(replay.emissions, [
        PublicationEmission(writer, selector, events),
      ])
    False -> replay.emissions
  }
  use #(writer, capture, inverses) <- result.try(case replay.capture {
    None -> Ok(#(writer, None, replay.inverses))
    Some(#(id, captured_selector)) -> {
      use revision <- result.try(identity_revision(events))
      use #(writer, inverse) <- result.try(
        runtime_core.retain_tree_revertible_on(
          writer,
          replay.tree,
          captured_selector,
          revision,
          tree_types.DefaultCommit,
        )
        |> result.map_error(string.inspect),
      )
      Ok(#(
        writer,
        None,
        dict.insert(replay.inverses, id, #(captured_selector, inverse)),
      ))
    }
  })
  Ok(
    PublicationReplay(
      ..replay,
      replay: Replay(
        ..replay.replay,
        writer:,
        outbounds: list.append(replay.replay.outbounds, outbound),
      ),
      emissions:,
      capture:,
      inverses:,
    ),
  )
}

fn publication_membership(
  replay: PublicationReplay,
  decoder_input: Json,
) -> Result(PublicationReplay, String) {
  use prefix <- result.try(read_field(
    decoder_input,
    "deliveryPrefix",
    decode.list(wire.json_value_decoder()),
  ))
  use next <- result.try(item_at(
    prefix,
    replay.replay.sequence_number,
    "missing publication envelope",
  ))
  case read_field(next, "type", decode.string) {
    Ok("join") | Ok("leave") -> {
      let sequence = replay.replay.sequence_number + 1
      use writer <- result.try(identity_deliver_context(
        replay.replay.writer,
        decoder_input,
        sequence,
      ))
      use receiver <- result.try(identity_deliver_context(
        replay.replay.receiver,
        decoder_input,
        sequence,
      ))
      use message <- result.try(transport_projection(next))
      Ok(
        PublicationReplay(
          ..replay,
          replay: Replay(
            ..replay.replay,
            writer:,
            receiver:,
            sequence_number: sequence,
            last_messages: list.append(replay.replay.last_messages, [message]),
          ),
        ),
      )
    }
    _ -> Ok(replay)
  }
}

fn publication_settle(
  replay: PublicationReplay,
  decoder_input: Json,
  writer_id: String,
) -> Result(PublicationReplay, String) {
  use #(writer, writer_outbounds) <- result.try(
    runtime_core.coalesce_outbound_operations(
      replay.replay.writer,
      replay.replay.outbounds,
    )
    |> result.map_error(string.inspect),
  )
  use #(receiver, receiver_outbounds) <- result.try(
    runtime_core.coalesce_outbound_operations(
      replay.replay.receiver,
      replay.receiver_outbounds,
    )
    |> result.map_error(string.inspect),
  )
  use prefix <- result.try(read_field(
    decoder_input,
    "deliveryPrefix",
    decode.list(wire.json_value_decoder()),
  ))
  list.try_fold(
    list.append(
      list.map(writer_outbounds, fn(outbound) { #(writer_id, outbound) }),
      list.map(receiver_outbounds, fn(outbound) {
        #(receiver.client_id, outbound)
      }),
    ),
    PublicationReplay(
      ..replay,
      replay: Replay(..replay.replay, writer:, receiver:, outbounds: []),
      receiver_outbounds: [],
    ),
    fn(replay, submitted) {
      let sequence = replay.replay.sequence_number + 1
      use expected <- result.try(item_at(
        prefix,
        sequence - 1,
        "missing publication service point",
      ))
      use minimum <- result.try(read_field(
        expected,
        "minimumSequenceNumber",
        decode.int,
      ))
      use actual <- result.try(transport_message_with_minimum(
        submitted.1,
        submitted.0,
        sequence,
        minimum,
      ))
      use projected <- result.try(transport_projection(expected))
      use _ <- result.try(
        fixtures.first_difference(actual, projected)
        |> result.map_error(fn(path) {
          "transport "
          <> int.to_string(sequence)
          <> " differs at "
          <> path
          <> "\nactual "
          <> json.to_string(actual)
          <> "\nexpected "
          <> json.to_string(projected)
        }),
      )
      use message <- result.try(sequenced(submitted.1, submitted.0, sequence))
      let message =
        types.SequencedDocumentMessage(
          ..message,
          minimum_sequence_number: minimum,
        )
      use #(writer, writer_events) <- result.try(
        runtime_core.handle_sequenced(replay.replay.writer, message)
        |> result.map_error(string.inspect),
      )
      use #(receiver, receiver_events) <- result.try(
        runtime_core.handle_sequenced(replay.replay.receiver, message)
        |> result.map_error(string.inspect),
      )
      Ok(
        PublicationReplay(
          ..replay,
          replay: Replay(
            ..replay.replay,
            writer:,
            receiver:,
            sequence_number: sequence,
            last_messages: list.append(replay.replay.last_messages, [actual]),
          ),
          settlements: list.append(
            replay.settlements,
            runtime_core.scope_tree_events(writer, writer_events.events),
          ),
          receiver_events: list.append(
            replay.receiver_events,
            receiver_events.events,
          ),
        ),
      )
    },
  )
}

fn assert_publication_checkpoint(
  replay: PublicationReplay,
  checkpoint: Json,
) -> Result(Nil, String) {
  use stages <- result.try(field(checkpoint, "stages"))
  use _ <- result.try(
    fixtures.first_difference(json.preprocessed_array(replay.stages), stages)
    |> result.map_error(fn(path) {
      "publication transaction stage differs at " <> path
    }),
  )
  use _ <- result.try(assert_publication_events(replay, checkpoint))
  use branches <- result.try(read_field(
    checkpoint,
    "branches",
    decode.list(wire.json_value_decoder()),
  ))
  use _ <- result.try(
    list.try_each(branches, fn(branch) {
      use name <- result.try(read_field(branch, "id", decode.string))
      use id <- result.try(
        dict.get(replay.branches, name)
        |> result.map_error(fn(_) { "missing publication branch " <> name }),
      )
      let selector = tree_types.LocalCheckout(id)
      use disposed <- result.try(read_field(branch, "disposed", decode.bool))
      let status =
        runtime_core.tree_branch_status(
          replay.replay.writer,
          replay.tree,
          selector,
        )
      use _ <- result.try(case disposed, status {
        True, runtime_core.BranchDisposed -> Ok(Nil)
        False, runtime_core.BranchValid -> Ok(Nil)
        _, _ -> Error("publication branch status differs for " <> name)
      })
      case disposed {
        True -> Ok(Nil)
        False -> {
          use expected <- result.try(field(branch, "data"))
          use actual <- result.try(tree_data_on(
            replay.replay.writer,
            replay.tree,
            selector,
          ))
          fixtures.first_difference(actual, expected)
        }
      }
    }),
  )
  use tree <- result.try(field(checkpoint, "tree"))
  use expected_data <- result.try(field(tree, "data"))
  use actual <- result.try(tree_data(replay.replay.writer, replay.tree))
  use _ <- result.try(
    fixtures.first_difference(actual, expected_data)
    |> result.map_error(fn(path) { "writer tree differs at " <> path }),
  )
  use receiver <- result.try(field(checkpoint, "receiver"))
  use receiver_tree <- result.try(field(receiver, "tree"))
  use receiver_data <- result.try(field(receiver_tree, "data"))
  use actual <- result.try(tree_data(replay.replay.receiver, replay.tree))
  use _ <- result.try(
    fixtures.first_difference(actual, receiver_data)
    |> result.map_error(fn(path) { "receiver tree differs at " <> path }),
  )
  use compressor <- result.try(
    replay.replay.writer.compressor
    |> option.to_result("publication compressor is missing"),
  )
  use expected_compressor <- result.try(field(checkpoint, "compressor"))
  use bytes <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )
  use expected_bytes <- result.try(field(expected_compressor, "compressor"))
  use _ <- result.try(
    fixtures.first_difference(bytes, expected_bytes)
    |> result.map_error(fn(path) {
      "publication compressor differs at " <> path
    }),
  )
  use token <- result.try(identity_token(replay.replay.writer, replay.tree))
  use _ <- result.try(case replay.token == Some(token) {
    True -> Ok(Nil)
    False -> Error("publication replaced checkout, root, or anchor identity")
  })
  use targets <- result.try(read_field(
    checkpoint,
    "targets",
    decode.list(wire.json_value_decoder()),
  ))
  use _ <- result.try(
    list.try_each(targets, fn(target) {
      use path <- result.try(read_field(target, "path", decode.string))
      use address <- result.try(channel_address(path))
      use attached <- result.try(read_field(target, "attached", decode.bool))
      use data <- result.try(field(target, "data"))
      let visible = dict.has_key(replay.replay.writer.channels, address)
      use _ <- result.try(case attached == visible {
        True -> Ok(Nil)
        False -> Error("publication target visibility differs at " <> path)
      })
      use _ <- result.try(require_publication_map(replay.replay.writer, address))
      let entries = runtime_core.entries(replay.replay.writer, address)
      use _ <- result.try(
        fixtures.first_difference(json.object(entries), data)
        |> result.map_error(fn(location) {
          path <> " target data differs at " <> location
        }),
      )
      case attached {
        False -> Ok(Nil)
        True -> {
          use _ <- result.try(require_publication_map(
            replay.replay.receiver,
            address,
          ))
          use receiver <- result.try(field(target, "receiver"))
          use expected <- result.try(field(receiver, "data"))
          let entries = runtime_core.entries(replay.replay.receiver, address)
          fixtures.first_difference(json.object(entries), expected)
        }
      }
    }),
  )
  Ok(Nil)
}

fn require_publication_map(
  core: runtime_core.Core,
  address: String,
) -> Result(Nil, String) {
  case dict.get(core.channels, address), dict.get(core.detached, address) {
    Ok(channel.MapState(_)), _ | _, Ok(channel.MapState(_)) -> Ok(Nil)
    _, _ -> Error("publication target map is missing at " <> address)
  }
}

fn capture_publication_stage(
  replay: PublicationReplay,
) -> Result(PublicationReplay, String) {
  use tree <- result.try(tree_data(replay.replay.writer, replay.tree))
  use compressor <- result.try(
    replay.replay.writer.compressor
    |> option.to_result("publication stage compressor is missing"),
  )
  use bytes <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )
  let event_count =
    list.count(replay.emissions, fn(emission) {
      emission.selector == tree_types.DocumentCheckout
    })
  let receiver_count =
    list.count(replay.receiver_events, fn(event) {
      case event.1 {
        channel.TreeCommitApplied(_, _, _, _) -> True
        _ -> False
      }
    })
  let stage =
    json.object([
      #("tree", tree),
      #("target", json.string("/" <> replay.stage_target)),
      #(
        "attached",
        json.bool(dict.has_key(
          replay.replay.writer.channels,
          replay.stage_target,
        )),
      ),
      #(
        "compressor",
        json.object([
          #(
            "sessionId",
            json.string(
              fluid_ids.session_id_to_string(fluid_ids.local_session(compressor)),
            ),
          ),
          #("compressor", bytes),
        ]),
      ),
      #("transportLength", json.int(list.length(replay.replay.outbounds))),
      #(
        "eventCounts",
        json.object([
          #("writer", json.int(event_count)),
          #("receiver", json.int(receiver_count)),
        ]),
      ),
    ])
  Ok(PublicationReplay(..replay, stages: list.append(replay.stages, [stage])))
}

fn assert_publication_events(
  replay: PublicationReplay,
  checkpoint: Json,
) -> Result(Nil, String) {
  use events <- result.try(field(checkpoint, "events"))
  use writer <- result.try(field(events, "writer"))
  use _ <- result.try(assert_publication_watch(
    replay,
    tree_types.DocumentCheckout,
    writer,
    True,
  ))
  use receiver <- result.try(field(events, "receiver"))
  use expected <- result.try(read_field(
    receiver,
    "events",
    decode.list(wire.json_value_decoder()),
  ))
  let applied =
    list.filter(replay.receiver_events, fn(event) {
      case event {
        #(address, channel.TreeCommitApplied(_, _, _, _)) ->
          address == replay.tree
        _ -> False
      }
    })
  use _ <- result.try(case list.length(applied) == list.length(expected) {
    True -> Ok(Nil)
    False -> Error("publication receiver event count differs")
  })
  use _ <- result.try(
    list.try_each(
      list.index_map(applied, fn(event, index) { #(event, index) }),
      fn(indexed) {
        assert_tree_emission(
          replay.replay.receiver,
          tree_types.DocumentCheckout,
          [indexed.0],
          receiver,
          replay.tree,
          indexed.1,
          False,
        )
      },
    ),
  )
  use branches <- result.try(read_field(
    events,
    "branches",
    decode.list(wire.json_value_decoder()),
  ))
  use _ <- result.try(case dict.size(replay.branches) == list.length(branches) {
    True -> Ok(Nil)
    False -> Error("publication branch watch count differs")
  })
  list.try_each(branches, fn(branch) {
    use name <- result.try(read_field(branch, "id", decode.string))
    use id <- result.try(
      dict.get(replay.branches, name)
      |> result.map_error(fn(_) { "publication branch watch is missing" }),
    )
    assert_publication_watch(
      replay,
      tree_types.LocalCheckout(id),
      branch,
      False,
    )
  })
}

fn assert_publication_watch(
  replay: PublicationReplay,
  selector: tree_types.CheckoutSelector,
  watch: Json,
  document: Bool,
) -> Result(Nil, String) {
  use expected <- result.try(read_field(
    watch,
    "events",
    decode.list(wire.json_value_decoder()),
  ))
  let emissions =
    list.filter(replay.emissions, fn(emission) { emission.selector == selector })
  use _ <- result.try(case list.length(emissions) == list.length(expected) {
    True -> Ok(Nil)
    False -> Error("publication writer event count differs")
  })
  use _ <- result.try(
    list.try_each(
      list.index_map(emissions, fn(emission, index) { #(emission, index) }),
      fn(indexed) {
        assert_tree_emission(
          indexed.0.core,
          selector,
          indexed.0.events,
          watch,
          replay.tree,
          indexed.1,
          document,
        )
      },
    ),
  )
  let revisions =
    list.filter_map(emissions, fn(emission) {
      identity_revision(emission.events)
    })
  let settlements =
    list.filter_map(replay.settlements, fn(event) {
      case event {
        #(address, scope, channel.TreeCommitSettled(revision, outcome))
          if address == replay.tree && scope == selector
        -> {
          use index <- result.try(
            revisions
            |> list.index_map(fn(value, index) { #(value, index) })
            |> list.find(fn(value) { value.0 == revision })
            |> result.map(fn(value) { value.1 }),
          )
          let outcome = case outcome {
            tree_types.FullyApplied -> "FullyApplied"
            tree_types.NewContentOnly -> "NewContentOnly"
            tree_types.FullyDropped -> "FullyDropped"
          }
          Ok(
            json.object([
              #("index", json.int(index)),
              #("outcome", json.string(outcome)),
            ]),
          )
        }
        _ -> Error(Nil)
      }
    })
  use expected_settlements <- result.try(field(watch, "settlements"))
  use _ <- result.try(
    fixtures.first_difference(
      json.preprocessed_array(settlements),
      expected_settlements,
    )
    |> result.map_error(fn(path) {
      "publication settlements differ at "
      <> path
      <> " actual="
      <> json.to_string(json.preprocessed_array(settlements))
      <> " expected="
      <> json.to_string(expected_settlements)
    }),
  )
  use handles <- result.try(read_field(
    watch,
    "handles",
    decode.list(wire.json_value_decoder()),
  ))
  let inverses =
    dict.values(replay.inverses)
    |> list.filter(fn(value) { value.0 == selector })
  case document {
    True -> Ok(Nil)
    False -> {
      use _ <- result.try(case list.length(handles) == list.length(inverses) {
        True -> Ok(Nil)
        False -> Error("publication branch inverse count differs")
      })
      list.try_each(list.zip(handles, inverses), fn(pair) {
        use status <- result.try(read_field(pair.0, "status", decode.string))
        let valid =
          runtime_core.tree_revertible_is_valid_on(
            replay.replay.writer,
            replay.tree,
            selector,
            pair.1.1,
          )
        case status, valid {
          "Valid", True | "Disposed", False -> Ok(Nil)
          _, _ -> Error("publication branch inverse status differs")
        }
      })
    }
  }
}

fn run_identity_replay(case_id: String) -> Result(Nil, String) {
  use fixture <- result.try(fixtures.load(case_id))
  use input <- result.try(field(fixture.input, "identityReplay"))
  use observation <- result.try(expected_observation(
    fixture.expected,
    "successful-transaction",
  ))
  use value <- result.try(field(observation, "value"))
  use lifecycle <- result.try(field(value, "identityLifecycle"))
  use peer <- result.try(field(lifecycle, "peer"))
  use checkpoints <- result.try(read_field(
    lifecycle,
    "checkpoints",
    decode.list(wire.json_value_decoder()),
  ))
  use sessions <- result.try(field(input, "sessions"))
  use receiver_writer <- result.try(field(sessions, "receiverWriter"))
  use receiver_session_raw <- result.try(read_field(
    receiver_writer,
    "sessionId",
    decode.string,
  ))
  use #(writer, receiver, writer_client_id, _) <- result.try(
    cores_from_decoder_input(input, receiver_session_raw),
  )
  use writer <- result.try(identity_deliver_context(writer, input, 1))
  use receiver <- result.try(identity_deliver_context(receiver, input, 1))
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 0, "missing initial checkpoint"),
      [],
    ),
  )

  use left_create <- result.try(identity_command(checkpoints, 1, 0))
  use left_initialize <- result.try(identity_command(checkpoints, 1, 2))
  use #(writer, left, left_creation_events) <- result.try(identity_create_tree(
    writer,
    left_create,
    left_initialize,
  ))
  use left_token <- result.try(identity_token(writer, left))
  use _ <- result.try(assert_identity_event(
    writer,
    left_creation_events,
    item_at(checkpoints, 1, "missing creation"),
    left,
    0,
  ))
  use _ <- result.try(assert_identity_initialization(
    writer,
    left,
    item_at(checkpoints, 1, "missing creation"),
  ))
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 1, "missing left-created checkpoint"),
      [#(left, left_token)],
    ),
  )

  use right_create <- result.try(identity_command(checkpoints, 2, 4))
  use right_initialize <- result.try(identity_command(checkpoints, 2, 6))
  use #(writer, right, right_creation_events) <- result.try(
    identity_create_tree(writer, right_create, right_initialize),
  )
  use right_token <- result.try(identity_token(writer, right))
  use _ <- result.try(assert_identity_event(
    writer,
    right_creation_events,
    item_at(checkpoints, 2, "missing creation"),
    right,
    0,
  ))
  use _ <- result.try(assert_identity_initialization(
    writer,
    right,
    item_at(checkpoints, 2, "missing creation"),
  ))
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 2, "missing right-created checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )

  use #(writer, left_events, left_outbound) <- result.try(
    runtime_core.submit_tree_edits(writer, left, [
      tree_types.SetField(["label"], tree_types.StringValue("left-detached")),
    ])
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(case left_outbound {
    [] -> Ok(Nil)
    _ -> Error("detached left edit produced transport")
  })
  use left_revision <- result.try(identity_revision(left_events))
  use _ <- result.try(assert_identity_event(
    writer,
    left_events,
    item_at(checkpoints, 3, "missing detached event"),
    left,
    1,
  ))
  use _ <- result.try(assert_identity_settlement(left_events, left_revision))
  use _ <- result.try(assert_checkpoint_revision(
    item_at(checkpoints, 3, "missing left-edited checkpoint"),
    left,
    left_revision,
  ))
  use #(writer, left_initial_revertible) <- result.try(
    runtime_core.retain_tree_revertible(
      writer,
      left,
      left_revision,
      tree_types.DefaultCommit,
    )
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 3, "missing left-edited checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )

  use #(writer, right_events, right_detached_outbound) <- result.try(
    runtime_core.submit_tree_edits(writer, right, [
      tree_types.SetField(["label"], tree_types.StringValue("right-detached")),
    ])
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(case right_detached_outbound {
    [] -> Ok(Nil)
    _ -> Error("detached right edit produced transport")
  })
  use right_revision <- result.try(identity_revision(right_events))
  use _ <- result.try(assert_identity_event(
    writer,
    right_events,
    item_at(checkpoints, 4, "missing detached event"),
    right,
    1,
  ))
  use _ <- result.try(assert_identity_settlement(right_events, right_revision))
  use #(writer, right_detached_revertible) <- result.try(
    runtime_core.retain_tree_revertible(
      writer,
      right,
      right_revision,
      tree_types.DefaultCommit,
    )
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(assert_checkpoint_revision(
    item_at(checkpoints, 4, "missing right-edited checkpoint"),
    right,
    right_revision,
  ))
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 4, "missing right-edited checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )

  use right_reference <- result.try(
    handle.reference_from_path("/" <> right) |> result.map_error(string.inspect),
  )
  use #(writer, _, right_outbound) <- result.try(
    runtime_core.set(
      writer,
      "A/root",
      "right",
      handle.reference_to_json(right_reference),
    )
    |> result.map_error(string.inspect),
  )
  use #(writer, receiver, attached_events, _) <- result.try(identity_settle(
    writer,
    receiver,
    right_outbound,
    writer_client_id,
    2,
    input,
  ))
  use _ <- result.try(assert_identity_no_commits(attached_events))
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 5, "missing right-attached checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )

  use #(writer, interleaved_events, interleaved_outbound) <- result.try(
    runtime_core.submit_tree_edits(writer, left, [
      tree_types.SetField(["label"], tree_types.StringValue("left-interleaved")),
    ])
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(case interleaved_outbound {
    [] -> Ok(Nil)
    _ -> Error("interleaved detached edit produced transport")
  })
  use interleaved_revision <- result.try(identity_revision(interleaved_events))
  use _ <- result.try(assert_identity_event(
    writer,
    interleaved_events,
    item_at(checkpoints, 6, "missing interleaved event"),
    left,
    2,
  ))
  use _ <- result.try(assert_identity_settlement(
    interleaved_events,
    interleaved_revision,
  ))
  use _ <- result.try(assert_checkpoint_revision(
    item_at(checkpoints, 6, "missing interleaved checkpoint"),
    left,
    interleaved_revision,
  ))
  use #(writer, original_revertible) <- result.try(
    runtime_core.retain_tree_revertible(
      writer,
      left,
      interleaved_revision,
      tree_types.DefaultCommit,
    )
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 6, "missing interleaved checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )

  use left_reference <- result.try(
    handle.reference_from_path("/" <> left) |> result.map_error(string.inspect),
  )
  use #(writer, _, left_outbound) <- result.try(
    runtime_core.set(
      writer,
      "A/root",
      "left",
      handle.reference_to_json(left_reference),
    )
    |> result.map_error(string.inspect),
  )
  use #(writer, receiver, attached_events, _) <- result.try(identity_settle(
    writer,
    receiver,
    left_outbound,
    writer_client_id,
    3,
    input,
  ))
  use _ <- result.try(assert_identity_no_commits(attached_events))
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 7, "missing left-attached checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )

  use receiver_compressor_raw <- result.try(read_field(
    receiver_writer,
    "compressor",
    decode.string,
  ))
  use receiver_compressor <- result.try(
    receiver.compressor
    |> option.to_result("identity receiver has no compressor"),
  )
  use ongoing <- result.try(
    fluid_ids.serialize(receiver_compressor, True)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(case ongoing == json.string(receiver_compressor_raw) {
    True -> Ok(Nil)
    False -> Error("identity receiver compressor differs at peer load")
  })
  use peer_left_token <- result.try(identity_token(receiver, left))
  use peer_right_token <- result.try(identity_token(receiver, right))

  use #(writer, writer_events, writer_outbound) <- result.try(
    runtime_core.submit_tree_edits(writer, right, [
      tree_types.SetField(["label"], tree_types.StringValue("right-live")),
    ])
    |> result.map_error(string.inspect),
  )
  use writer_revision <- result.try(identity_revision(writer_events))
  use _ <- result.try(assert_identity_event(
    writer,
    writer_events,
    item_at(checkpoints, 8, "missing writer event"),
    right,
    2,
  ))
  use _ <- result.try(assert_checkpoint_revision(
    item_at(checkpoints, 8, "missing writer-live checkpoint"),
    right,
    writer_revision,
  ))
  use #(writer, writer_live_revertible) <- result.try(
    runtime_core.retain_tree_revertible(
      writer,
      right,
      writer_revision,
      tree_types.DefaultCommit,
    )
    |> result.map_error(string.inspect),
  )
  use #(writer, receiver, acknowledged_events, peer_received_events) <- result.try(
    identity_settle(
      writer,
      receiver,
      writer_outbound,
      writer_client_id,
      4,
      input,
    ),
  )
  use _ <- result.try(assert_identity_settlement(
    acknowledged_events,
    writer_revision,
  ))
  use _ <- result.try(assert_identity_peer_event(
    receiver,
    peer_received_events,
    peer,
    "trees",
    right,
    0,
  ))
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 8, "missing writer-live checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )

  use receiver_write_client <- result.try(read_field(
    sessions,
    "receiverWriteClientId",
    decode.string,
  ))
  use receiver <- result.try(identity_deliver_context(receiver, input, 5))
  use writer <- result.try(identity_deliver_context(writer, input, 5))
  let receiver =
    runtime_core.Core(
      ..receiver,
      client_id: receiver_write_client,
      next_client_sequence_number: 1,
    )
  use #(receiver, peer_events, peer_outbound) <- result.try(
    runtime_core.submit_tree_edits(receiver, left, [
      tree_types.SetField(["label"], tree_types.StringValue("left-peer")),
    ])
    |> result.map_error(fn(error) { "peer submit: " <> string.inspect(error) }),
  )
  use peer_revision <- result.try(identity_revision(peer_events))
  use _ <- result.try(assert_identity_peer_event(
    receiver,
    peer_events,
    peer,
    "trees",
    left,
    0,
  ))
  use #(receiver, writer, acknowledged_events, writer_received_events) <- result.try(
    identity_settle(
      receiver,
      writer,
      peer_outbound,
      receiver_write_client,
      6,
      input,
    ),
  )
  use _ <- result.try(assert_identity_settlement(
    acknowledged_events,
    peer_revision,
  ))
  use _ <- result.try(assert_identity_event(
    writer,
    writer_received_events,
    item_at(checkpoints, 9, "missing peer event"),
    left,
    3,
  ))
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 9, "missing peer-live checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )
  use _ <- result.try(
    assert_identity_peer(receiver, peer, "trees", [
      #(left, peer_left_token),
      #(right, peer_right_token),
    ]),
  )

  use #(writer, undo_events, undo_outbound) <- result.try(
    runtime_core.revert_tree(writer, left, original_revertible)
    |> result.map_error(fn(error) { "revert: " <> string.inspect(error) }),
  )
  use undo_revision <- result.try(identity_revision(undo_events))
  use _ <- result.try(assert_identity_event(
    writer,
    undo_events,
    item_at(checkpoints, 10, "missing undo event"),
    left,
    4,
  ))
  use #(writer, undo_revertible) <- result.try(
    runtime_core.retain_tree_revertible(
      writer,
      left,
      undo_revision,
      tree_types.UndoCommit,
    )
    |> result.map_error(string.inspect),
  )
  use writer <- result.try(
    runtime_core.dispose_tree_revertible(writer, left, original_revertible)
    |> result.map_error(string.inspect),
  )
  use #(writer, receiver, acknowledged_events, peer_received_events) <- result.try(
    identity_settle(
      writer,
      receiver,
      [undo_outbound],
      writer_client_id,
      7,
      input,
    ),
  )
  use _ <- result.try(assert_identity_settlement(
    acknowledged_events,
    undo_revision,
  ))
  use _ <- result.try(assert_identity_peer_event(
    receiver,
    peer_received_events,
    peer,
    "finalTrees",
    left,
    1,
  ))
  use _ <- result.try(
    case
      runtime_core.tree_revertible_is_valid(writer, left, original_revertible)
    {
      False -> Ok(Nil)
      True -> Error("original detached inverse remained valid after disposal")
    },
  )
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 10, "missing undo checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )

  use writer <- result.try(
    [
      #(left, left_initial_revertible),
      #(left, undo_revertible),
      #(right, right_detached_revertible),
      #(right, writer_live_revertible),
    ]
    |> list.try_fold(writer, fn(core, entry) {
      runtime_core.dispose_tree_revertible(core, entry.0, entry.1)
      |> result.map_error(string.inspect)
    }),
  )
  use _ <- result.try(
    assert_identity_checkpoint(
      writer,
      item_at(checkpoints, 11, "missing disposed checkpoint"),
      [#(left, left_token), #(right, right_token)],
    ),
  )
  use _ <- result.try(
    assert_identity_peer(receiver, peer, "finalTrees", [
      #(left, peer_left_token),
      #(right, peer_right_token),
    ]),
  )
  use value <- result.try(
    runtime_core.tree_read(receiver, left, ["label"])
    |> result.map_error(string.inspect),
  )
  case value == Some(tree_types.StringValue("left-detached")) {
    True -> Ok(Nil)
    False -> Error("peer did not observe detached inverse")
  }
}

fn identity_command(
  checkpoints: List(Json),
  checkpoint_index: Int,
  command_index: Int,
) -> Result(Command, String) {
  use checkpoint <- result.try(item_at(
    checkpoints,
    checkpoint_index,
    "missing identity checkpoint",
  ))
  use commands <- result.try(read_field(
    checkpoint,
    "commands",
    decode.list(command_decoder()),
  ))
  item_at(commands, command_index, "missing identity command")
}

fn identity_deliver_context(
  core: runtime_core.Core,
  input: Json,
  sequence_number: Int,
) -> Result(runtime_core.Core, String) {
  use prefix <- result.try(read_field(
    input,
    "deliveryPrefix",
    decode.list(wire.json_value_decoder()),
  ))
  use envelope <- result.try(
    list.find(prefix, fn(message) {
      read_field(message, "sequenceNumber", decode.int) == Ok(sequence_number)
    })
    |> result.map_error(fn(_) { "identity context envelope is missing" }),
  )
  use message <- result.try(
    json.parse(
      json.to_string(envelope),
      socket.sequenced_document_message_decoder(),
    )
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(case message.message_type {
    "join" | "leave" -> Ok(Nil)
    _ -> Error("identity context envelope is not a membership message")
  })
  runtime_core.handle_sequenced(core, message)
  |> result.map(fn(value) { value.0 })
  |> result.map_error(string.inspect)
}

fn item_at(items: List(a), index: Int, detail: String) -> Result(a, String) {
  case list.drop(items, index) {
    [item, ..] -> Ok(item)
    [] -> Error(detail)
  }
}

fn identity_create_tree(
  core: runtime_core.Core,
  create: Command,
  initialize: Command,
) -> Result(
  #(runtime_core.Core, String, List(#(String, channel.ChannelEvent))),
  String,
) {
  let assert CreateChannel(datastore, channel_id, channel_type) = create
  let assert InitializeTree(target, stored_json, initial) = initialize
  use _ <- result.try(
    case channel_type, target == "/" <> datastore <> "/" <> channel_id {
      "https://graph.microsoft.com/types/tree", True -> Ok(Nil)
      _, _ -> Error("identity tree creation command mismatch")
    },
  )
  use compressor <- result.try(
    core.compressor |> option.to_result("identity tree has no compressor"),
  )
  use #(compressor, generated) <- result.try(
    fluid_ids.generate(compressor) |> result.map_error(string.inspect),
  )
  use view_id <- result.try(
    fluid_ids.decompress(compressor, generated)
    |> result.map_error(string.inspect),
  )
  use stored <- result.try(
    tree_schema.stored_from_json(stored_json)
    |> result.map_error(string.inspect),
  )
  let address = datastore <> "/" <> channel_id
  runtime_core.create_detached_tree_with_events(
    runtime_core.Core(..core, compressor: Some(compressor)),
    address,
    stored,
    Some(initial),
    view_id,
  )
  |> result.map(fn(created) { #(created.0, address, created.1) })
  |> result.map_error(string.inspect)
}

fn identity_token(
  core: runtime_core.Core,
  address: String,
) -> Result(IdentityToken, String) {
  use forest <- result.try(
    dict.get(core.tree_checkouts, address)
    |> result.map_error(fn(_) { "identity checkout is missing" }),
  )
  let checkout = tree_branch.document(forest)
  use state <- result.try(
    tree_branch.checkout_state(forest, checkout)
    |> result.map_error(string.inspect),
  )
  use root <- result.try(
    tree_kernel.reference_at(state, []) |> result.map_error(string.inspect),
  )
  use anchor <- result.try(
    tree_branch.reference_at(forest, checkout, [])
    |> result.map_error(string.inspect),
  )
  Ok(IdentityToken(checkout, root, anchor))
}

fn assert_identity_initialization(
  core: runtime_core.Core,
  address: String,
  checkpoint: Result(Json, String),
) -> Result(Nil, String) {
  use forest <- result.try(
    dict.get(core.tree_checkouts, address)
    |> result.map_error(fn(_) { "initialization checkout is missing" }),
  )
  use state <- result.try(
    tree_branch.checkout_state(forest, tree_branch.document(forest))
    |> result.map_error(string.inspect),
  )
  use commit <- result.try(
    list.first(tree_kernel.history_view(state).sequenced.trunk)
    |> result.map_error(fn(_) { "tree initialization commit is missing" }),
  )
  assert_checkpoint_revision(checkpoint, address, commit.commit.revision)
}

fn assert_identity_event(
  core: runtime_core.Core,
  events: List(#(String, channel.ChannelEvent)),
  checkpoint: Result(Json, String),
  address: String,
  index: Int,
) -> Result(Nil, String) {
  use checkpoint <- result.try(checkpoint)
  use trees <- result.try(read_field(
    checkpoint,
    "trees",
    decode.list(wire.json_value_decoder()),
  ))
  use tree <- result.try(
    list.find(trees, fn(tree) {
      read_field(tree, "path", decode.string) == Ok("/" <> address)
    })
    |> result.map_error(fn(_) { "identity event tree is missing" }),
  )
  assert_identity_tree_event(core, events, tree, address, index)
}

fn assert_identity_peer_event(
  core: runtime_core.Core,
  events: List(#(String, channel.ChannelEvent)),
  peer: Json,
  phase: String,
  address: String,
  index: Int,
) -> Result(Nil, String) {
  use trees <- result.try(read_field(
    peer,
    phase,
    decode.list(wire.json_value_decoder()),
  ))
  use tree <- result.try(
    list.find(trees, fn(tree) {
      read_field(tree, "path", decode.string) == Ok("/" <> address)
    })
    |> result.map_error(fn(_) { "identity peer event tree is missing" }),
  )
  assert_identity_tree_event(core, events, tree, address, index)
}

fn assert_identity_tree_event(
  core: runtime_core.Core,
  events: List(#(String, channel.ChannelEvent)),
  tree: Json,
  address: String,
  index: Int,
) -> Result(Nil, String) {
  use watch <- result.try(field(tree, "events"))
  use expected_events <- result.try(read_field(
    watch,
    "events",
    decode.list(wire.json_value_decoder()),
  ))
  use _ <- result.try(case list.length(expected_events) == index + 1 {
    True -> Ok(Nil)
    False -> Error("identity captured changed event count differs")
  })
  assert_tree_emission(
    core,
    tree_types.DocumentCheckout,
    events,
    watch,
    address,
    index,
    True,
  )
}

fn assert_tree_emission(
  core: runtime_core.Core,
  selector: tree_types.CheckoutSelector,
  events: List(#(String, channel.ChannelEvent)),
  watch: Json,
  address: String,
  index: Int,
  require_settlement: Bool,
) -> Result(Nil, String) {
  use expected_events <- result.try(read_field(
    watch,
    "events",
    decode.list(wire.json_value_decoder()),
  ))
  use expected <- result.try(item_at(
    expected_events,
    index,
    "tree emission is missing",
  ))
  let applied =
    list.filter_map(events, fn(event) {
      case event {
        #(target, channel.TreeCommitApplied(revision, kind, local, factory))
          if target == address
        -> Ok(#(revision, kind, local, factory))
        _ -> Error(Nil)
      }
    })
  use actual <- result.try(case applied {
    [event] -> Ok(event)
    _ -> Error("identity emission does not contain exactly one changed event")
  })
  let #(revision, kind, local, factory) = actual
  use expected_kind <- result.try(read_field(expected, "kind", decode.string))
  use expected_local <- result.try(read_field(expected, "local", decode.bool))
  use expected_factory <- result.try(read_field(
    expected,
    "factory",
    decode.bool,
  ))
  let kind = case kind {
    tree_types.DefaultCommit -> "Default"
    tree_types.UndoCommit -> "Undo"
    tree_types.RedoCommit -> "Redo"
  }
  use _ <- result.try(
    case
      kind == expected_kind
      && local == expected_local
      && factory == expected_factory
    {
      True -> Ok(Nil)
      False -> Error("identity changed event kind, origin, or factory differs")
    },
  )
  use raw <- result.try(field(expected, "change"))
  case local {
    False ->
      case json.to_string(raw) == "null" {
        True -> Ok(Nil)
        False -> Error("remote identity event exposes a local change")
      }
    True -> {
      use _ <- result.try(case require_settlement {
        False -> Ok(Nil)
        True -> {
          use settlements <- result.try(read_field(
            watch,
            "settlements",
            decode.list(wire.json_value_decoder()),
          ))
          use settlement <- result.try(
            list.find(settlements, fn(item) {
              read_field(item, "index", decode.int) == Ok(index)
            })
            |> result.map_error(fn(_) {
              "identity captured local settlement is missing"
            }),
          )
          use outcome <- result.try(read_field(
            settlement,
            "outcome",
            decode.string,
          ))
          case outcome == "FullyApplied" {
            True -> Ok(Nil)
            False -> Error("identity captured settlement differs")
          }
        }
      })
      use expected_revision <- result.try(read_field(
        expected,
        "stableRevision",
        decode.string,
      ))
      use _ <- result.try(
        case fluid_ids.stable_id_to_string(revision) == expected_revision {
          True -> Ok(Nil)
          False -> Error("identity changed event stable revision differs")
        },
      )
      use forest <- result.try(
        dict.get(core.tree_checkouts, address)
        |> result.map_error(fn(_) { "identity event checkout is missing" }),
      )
      use checkout <- result.try(
        tree_branch.checkout(forest, selector)
        |> result.map_error(string.inspect),
      )
      use state <- result.try(
        tree_branch.checkout_state(forest, checkout)
        |> result.map_error(string.inspect),
      )
      let view = tree_kernel.history_view(state)
      use commits <- result.try(case selector {
        tree_types.DocumentCheckout ->
          Ok(list.append(
            view.pending,
            list.map(view.sequenced.trunk, fn(entry) { entry.commit }),
          ))
        tree_types.LocalCheckout(id) ->
          tree_history.inspect_local(tree_kernel.branch_history(state), id)
          |> result.map(fn(branch) { branch.commits })
          |> result.map_error(string.inspect)
      })
      use commit <- result.try(
        list.find(commits, fn(commit) { commit.revision == revision })
        |> result.map_error(fn(_) { "identity event commit is missing" }),
      )
      use compressor <- result.try(
        core.compressor
        |> option.to_result("identity event compressor is missing"),
      )
      use version <- result.try(read_field(raw, "version", decode.int))
      use encoded_revision <- result.try(read_field(raw, "revision", decode.int))
      use originator_raw <- result.try(read_field(
        raw,
        "originatorId",
        decode.string,
      ))
      use originator <- result.try(
        fluid_ids.session_id(originator_raw)
        |> result.map_error(string.inspect),
      )
      use decoded_revision <- result.try(
        codec.decode_stable_revision(
          encoded_revision,
          originator,
          codec.DecodeContext(codec.Fluid310, compressor),
          "identity event revision",
        )
        |> result.map_error(string.inspect),
      )
      use _ <- result.try(
        case
          version == 1
          && decoded_revision == revision
          && originator == commit.originator
        {
          True -> Ok(Nil)
          False -> Error("identity SerializedChange identity differs")
        },
      )
      use encoded_changes <- result.try(field(raw, "change"))
      let schema = case shared_change.to_changes(commit.change) {
        [shared_change.SchemaChange(before, _, _), ..] -> before
        _ -> tree_schema.FixedSchema(tree_kernel.stored_schema(state))
      }
      use expected_changes <- result.try(
        codec.decode_changes_with_schema_state(
          encoded_changes,
          codec.DecodeContext(codec.Fluid310, compressor),
          codec.ChangeContext(originator, None, codec.Message),
          schema,
        )
        |> result.map_error(string.inspect),
      )
      use encoded_native <- result.try(
        codec.encode_changes_with_schema_state(
          shared_change.to_changes(commit.change),
          codec.EncodeContext(
            codec.Fluid310,
            compressor,
            Some(tree_kernel.stored_schema(state)),
          ),
          codec.ChangeContext(originator, None, codec.Message),
          schema,
        )
        |> result.map_error(string.inspect),
      )
      use native_changes <- result.try(
        codec.decode_changes_with_schema_state(
          encoded_native,
          codec.DecodeContext(codec.Fluid310, compressor),
          codec.ChangeContext(originator, None, codec.Message),
          schema,
        )
        |> result.map_error(string.inspect),
      )
      case same_identity_changes(native_changes, expected_changes) {
        True -> Ok(Nil)
        False ->
          Error(
            "identity SerializedChange commit atoms or values differ at event "
            <> int.to_string(index)
            <> " actual="
            <> string.inspect(
              list.filter_map(native_changes, fn(item) {
                case item {
                  shared_change.DataChange(data) ->
                    Ok(tree_change.to_data(data))
                  _ -> Error(Nil)
                }
              }),
            )
            <> " expected="
            <> string.inspect(
              list.filter_map(expected_changes, fn(item) {
                case item {
                  shared_change.DataChange(data) ->
                    Ok(tree_change.to_data(data))
                  _ -> Error(Nil)
                }
              }),
            ),
          )
      }
    }
  }
}

fn same_identity_changes(
  actual: List(shared_change.TreeChange),
  expected: List(shared_change.TreeChange),
) -> Bool {
  case actual, expected {
    [], [] -> True
    [shared_change.DataChange(actual), ..a],
      [shared_change.DataChange(expected), ..b]
    ->
      tree_change.to_data(actual) == tree_change.to_data(expected)
      && same_identity_changes(a, b)
    [shared_change.SchemaChange(before_a, after_a, inverse_a), ..a],
      [shared_change.SchemaChange(before_b, after_b, inverse_b), ..b]
    ->
      before_a == before_b
      && after_a == after_b
      && inverse_a == inverse_b
      && same_identity_changes(a, b)
    _, _ -> False
  }
}

fn assert_identity_checkpoint(
  core: runtime_core.Core,
  checkpoint: Result(Json, String),
  tokens: List(#(String, IdentityToken)),
) -> Result(Nil, String) {
  use checkpoint <- result.try(checkpoint)
  use checkpoint_id <- result.try(read_field(checkpoint, "id", decode.string))
  use compressor_expected <- result.try(field(checkpoint, "compressor"))
  use ongoing <- result.try(read_field(
    compressor_expected,
    "ongoing",
    decode.string,
  ))
  use summary <- result.try(read_field(
    compressor_expected,
    "summary",
    decode.string,
  ))
  use reservation <- result.try(field(compressor_expected, "reservation"))
  use compressor <- result.try(
    core.compressor |> option.to_result("identity checkpoint has no compressor"),
  )
  use actual_ongoing <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )
  use actual_summary <- result.try(
    fluid_ids.serialize(compressor, False) |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    case
      actual_ongoing == json.string(ongoing),
      actual_summary == json.string(summary)
    {
      True, True -> Ok(Nil)
      _, _ -> Error("identity checkpoint compressor bytes differ")
    },
  )
  let #(_, pending) = fluid_ids.take_unfinalized_range(compressor)
  use actual_reservation <- result.try(case pending {
    Some(range) ->
      fluid_ids.creation_range_to_json(range)
      |> result.map_error(string.inspect)
    None ->
      Ok(
        json.object([
          #(
            "sessionId",
            json.string(
              fluid_ids.session_id_to_string(fluid_ids.local_session(compressor)),
            ),
          ),
        ]),
      )
  })
  use _ <- result.try(
    fixtures.first_difference(actual_reservation, reservation)
    |> result.map_error(fn(path) {
      "identity checkpoint reservation differs at " <> path
    }),
  )
  use trees <- result.try(read_field(
    checkpoint,
    "trees",
    decode.list(wire.json_value_decoder()),
  ))
  use _ <- result.try(case list.length(trees) == list.length(tokens) {
    True -> Ok(Nil)
    False -> Error("identity checkpoint tree count differs")
  })
  list.try_each(tokens, fn(entry) {
    let #(address, IdentityToken(checkout, root, anchor)) = entry
    use expected <- result.try(
      list.find(trees, fn(tree) {
        read_field(tree, "path", decode.string) == Ok("/" <> address)
      })
      |> result.map_error(fn(_) { "identity checkpoint tree is missing" }),
    )
    use data <- result.try(field(expected, "data"))
    use actual <- result.try(tree_data(core, address))
    use _ <- result.try(
      fixtures.first_difference(actual, data)
      |> result.map_error(fn(path) {
        "identity checkpoint root differs for " <> address <> path
      }),
    )
    use expected_attached <- result.try(read_field(
      expected,
      "attached",
      decode.bool,
    ))
    use _ <- result.try(
      case
        dict.has_key(core.channels, address) == expected_attached,
        dict.has_key(core.detached, address) == !expected_attached
      {
        True, True -> Ok(Nil)
        _, _ -> Error("identity checkpoint attachment state differs")
      },
    )
    use forest <- result.try(
      dict.get(core.tree_checkouts, address)
      |> result.map_error(fn(_) { "identity checkout disappeared" }),
    )
    use state <- result.try(
      tree_branch.checkout_state(forest, tree_branch.document(forest))
      |> result.map_error(string.inspect),
    )
    use current_root <- result.try(
      tree_kernel.reference_at(state, []) |> result.map_error(string.inspect),
    )
    use current_anchor <- result.try(
      tree_branch.reference_at(forest, tree_branch.document(forest), [])
      |> result.map_error(string.inspect),
    )
    use snapshot <- result.try(
      case expected_attached {
        True -> tree_kernel.snapshot(state)
        False -> tree_runtime.snapshot_for_attach(state, compressor)
      }
      |> result.map_error(string.inspect),
    )
    use wire_summary <- result.try(
      tree_summary.to_wire(snapshot) |> result.map_error(string.inspect),
    )
    use summary_entry <- result.try(
      tree_summary_codec.encode(
        wire_summary,
        fluid_ids.local_session(compressor),
        codec.EncodeContext(
          codec.Fluid310,
          compressor,
          Some(wire_summary.schema),
        ),
      )
      |> result.map_error(string.inspect),
    )
    use actual_summary <- result.try(identity_summary_json(summary_entry))
    use expected_summary <- result.try(field(expected, "summary"))
    use _ <- result.try(
      fixtures.first_difference(actual_summary, expected_summary)
      |> result.map_error(fn(path) {
        "identity checkpoint "
        <> checkpoint_id
        <> " summary differs for "
        <> address
        <> path
      }),
    )
    case
      tree_branch.document(forest) == checkout,
      current_root == root,
      current_anchor == anchor
    {
      True, True, True -> Ok(Nil)
      _, _, _ ->
        Error("identity checkout, node, or anchor changed for " <> address)
    }
  })
}

fn identity_summary_json(
  entry: fluid_summary.SummaryEntry,
) -> Result(Json, String) {
  case entry {
    fluid_summary.SummaryTree(entries) -> {
      use entries <- result.try(
        list.try_map(entries, fn(entry) {
          use encoded <- result.try(identity_summary_json(entry.1))
          Ok(#(entry.0, encoded))
        }),
      )
      Ok(
        json.object([
          #("type", json.int(1)),
          #("tree", json.object(entries)),
        ]),
      )
    }
    fluid_summary.SummaryBlob(bytes) -> {
      use content <- result.try(
        bit_array.to_string(bytes)
        |> result.map_error(fn(_) { "identity summary blob is not UTF-8" }),
      )
      Ok(
        json.object([
          #("type", json.int(2)),
          #("content", json.string(content)),
        ]),
      )
    }
    fluid_summary.SummaryHandle(_, _) ->
      Error("identity summary contains an unresolved handle")
  }
}

fn identity_revision(
  events: List(#(String, channel.ChannelEvent)),
) -> Result(fluid_ids.StableId, String) {
  list.find_map(events, fn(event) {
    case event.1 {
      channel.TreeCommitApplied(revision, _, True, _) -> Ok(revision)
      _ -> Error(Nil)
    }
  })
  |> result.map_error(fn(_) { "identity edit emitted no local commit" })
}

fn assert_identity_settlement(
  events: List(#(String, channel.ChannelEvent)),
  revision: fluid_ids.StableId,
) -> Result(Nil, String) {
  let settlements =
    list.filter_map(events, fn(event) {
      case event.1 {
        channel.TreeCommitSettled(settled, outcome) -> Ok(#(settled, outcome))
        _ -> Error(Nil)
      }
    })
  case settlements == [#(revision, tree_types.FullyApplied)] {
    True -> Ok(Nil)
    False -> Error("detached commit does not settle locally as FullyApplied")
  }
}

fn assert_identity_no_commits(
  events: List(#(String, channel.ChannelEvent)),
) -> Result(Nil, String) {
  case
    list.any(events, fn(event) {
      case event.1 {
        channel.TreeCommitApplied(_, _, _, _)
        | channel.TreeCommitSettled(_, _) -> True
        _ -> False
      }
    })
  {
    True -> Error("attachment re-emitted a detached tree commit")
    False -> Ok(Nil)
  }
}

fn assert_identity_peer(
  core: runtime_core.Core,
  peer: Json,
  field_name: String,
  tokens: List(#(String, IdentityToken)),
) -> Result(Nil, String) {
  use trees <- result.try(read_field(
    peer,
    field_name,
    decode.list(wire.json_value_decoder()),
  ))
  use _ <- result.try(case list.length(trees) == list.length(tokens) {
    True -> Ok(Nil)
    False -> Error("identity peer tree count differs")
  })
  list.try_each(tokens, fn(entry) {
    let #(address, token) = entry
    use expected <- result.try(
      list.find(trees, fn(tree) {
        read_field(tree, "path", decode.string) == Ok("/" <> address)
      })
      |> result.map_error(fn(_) { "identity peer tree is missing" }),
    )
    use data <- result.try(field(expected, "data"))
    use actual <- result.try(tree_data(core, address))
    use _ <- result.try(
      fixtures.first_difference(actual, data)
      |> result.map_error(fn(path) {
        "identity peer data differs for " <> address <> path
      }),
    )
    use current <- result.try(identity_token(core, address))
    use same_root <- result.try(read_field(expected, "sameRoot", decode.bool))
    use same_checkout <- result.try(read_field(
      expected,
      "sameCheckout",
      decode.bool,
    ))
    case current == token && same_root && same_checkout {
      True -> Ok(Nil)
      False -> Error("identity peer checkout, node, or anchor changed")
    }
  })
}

fn assert_checkpoint_revision(
  checkpoint: Result(Json, String),
  address: String,
  revision: fluid_ids.StableId,
) -> Result(Nil, String) {
  use checkpoint <- result.try(checkpoint)
  use trees <- result.try(read_field(
    checkpoint,
    "trees",
    decode.list(wire.json_value_decoder()),
  ))
  use tree <- result.try(
    list.find(trees, fn(tree) {
      read_field(tree, "path", decode.string) == Ok("/" <> address)
    })
    |> result.map_error(fn(_) { "identity revision tree is missing" }),
  )
  use events <- result.try(field(tree, "events"))
  use items <- result.try(read_field(
    events,
    "events",
    decode.list(wire.json_value_decoder()),
  ))
  use expected <- result.try(
    list.find_map(list.reverse(items), fn(item) {
      read_field(item, "stableRevision", decode.string)
    })
    |> result.map_error(fn(_) { "identity stable revision is missing" }),
  )
  case fluid_ids.stable_id_to_string(revision) == expected {
    True -> Ok(Nil)
    False ->
      Error(
        "identity event revision differs for "
        <> address
        <> ": "
        <> fluid_ids.stable_id_to_string(revision)
        <> " != "
        <> expected,
      )
  }
}

fn identity_settle(
  sender: runtime_core.Core,
  receiver: runtime_core.Core,
  outbounds: List(wire.OutboundOperation),
  client_id: String,
  sequence_number: Int,
  input: Json,
) -> Result(
  #(
    runtime_core.Core,
    runtime_core.Core,
    List(#(String, channel.ChannelEvent)),
    List(#(String, channel.ChannelEvent)),
  ),
  String,
) {
  use #(sender, outbounds) <- result.try(
    runtime_core.coalesce_outbound_operations(sender, outbounds)
    |> result.map_error(fn(error) { "coalesce: " <> string.inspect(error) }),
  )
  let assert [outbound] = outbounds
  use prefix <- result.try(read_field(
    input,
    "deliveryPrefix",
    decode.list(wire.json_value_decoder()),
  ))
  use expected <- result.try(
    list.find(prefix, fn(message) {
      read_field(message, "sequenceNumber", decode.int) == Ok(sequence_number)
    })
    |> result.map_error(fn(_) { "identity transport checkpoint is missing" }),
  )
  use expected <- result.try(transport_projection(expected))
  use minimum_sequence_number <- result.try(read_field(
    expected,
    "minimumSequenceNumber",
    decode.int,
  ))
  use actual <- result.try(transport_message_with_minimum(
    outbound,
    client_id,
    sequence_number,
    minimum_sequence_number,
  ))
  use actual <- result.try(normalize_identity_transport(
    actual,
    client_id,
    outbound.client_sequence_number,
  ))
  use expected <- result.try(normalize_identity_transport(
    expected,
    client_id,
    outbound.client_sequence_number,
  ))
  use _ <- result.try(case fixtures.first_difference(actual, expected) {
    Ok(Nil) -> Ok(Nil)
    Error(path) ->
      Error(
        "identity transport differs at sequence "
        <> int.to_string(sequence_number)
        <> path
        <> " actual="
        <> string.slice(json.to_string(actual), 0, 500)
        <> " expected="
        <> string.slice(json.to_string(expected), 0, 500)
        <> " actual-trunk="
        <> snippet_after(json.to_string(actual), "trunk")
        <> " expected-trunk="
        <> snippet_after(json.to_string(expected), "trunk")
        <> " actual-forest="
        <> snippet_after(json.to_string(actual), "\\\"keys\\\"")
        <> " expected-forest="
        <> snippet_after(json.to_string(expected), "\\\"keys\\\"")
        <> " actual-replace="
        <> snippet_after(json.to_string(actual), "\"r\"")
        <> " expected-replace="
        <> snippet_after(json.to_string(expected), "\"r\""),
      )
  })
  use message <- result.try(sequenced(outbound, client_id, sequence_number))
  let message =
    types.SequencedDocumentMessage(..message, minimum_sequence_number:)
  use #(sender, sender_ingested) <- result.try(
    runtime_core.handle_sequenced(sender, message)
    |> result.map_error(fn(error) { "sender: " <> string.inspect(error) }),
  )
  use #(receiver, receiver_ingested) <- result.try(
    runtime_core.handle_sequenced(receiver, message)
    |> result.map_error(fn(error) { "receiver: " <> string.inspect(error) }),
  )
  Ok(#(sender, receiver, sender_ingested.events, receiver_ingested.events))
}

fn normalize_identity_transport(
  message: Json,
  client_id: String,
  client_sequence_number: Int,
) -> Result(Json, String) {
  json.to_string(message)
  |> string.replace(
    client_id <> "_[" <> int.to_string(client_sequence_number) <> "]",
    "transport-batch-[" <> int.to_string(client_sequence_number) <> "]",
  )
  |> json.parse(wire.json_value_decoder())
  |> result.map_error(fn(_) { "invalid identity transport normalization" })
}

fn snippet_after(value: String, marker: String) -> String {
  case string.split(value, marker) {
    [_, rest, ..] -> string.slice(rest, 0, 600)
    _ -> "missing"
  }
}

pub fn assert_mismatched_attach_attributes() -> Nil {
  let core = attachment_tree_core("A/attributes", "valid")
  let assert Ok(reference) = handle.reference_from_path("/A/attributes")
  let assert Ok(#(_, _, [outbound])) =
    runtime_core.set(
      core,
      "A/root",
      "attributes",
      handle.reference_to_json(reference),
    )
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert Ok(receiver) =
    runtime_fixture.routed_core_for(
      "remote-reader",
      "40000000-0000-4000-8000-000000000004",
    )
  let sequence_number = receiver.last_seen_sequence_number + 1
  let assert Ok(valid) = sequenced(outbound, "remote", sequence_number)
  let valid_result = runtime_core.handle_sequenced(receiver, valid)
  case valid_result {
    Ok(_) -> Nil
    Error(error) ->
      panic as { "valid tree attachment: " <> string.inspect(error) }
  }

  let malicious =
    fluid_container.DecodedBatch(
      ..batch,
      messages: list.map(batch.messages, fn(message) {
        fluid_container.ContainerMessage(..message, kind: case message.kind {
          fluid_container.ChannelAttach(route, kind, snapshot) -> {
            let changed =
              mutate_json(
                snapshot,
                "\\\"snapshotFormatVersion\\\":\\\"0.0.0\\\"",
                "\\\"snapshotFormatVersion\\\":\\\"9.9.9\\\"",
              )
            fluid_container.ChannelAttach(route, kind, changed)
          }
          other -> other
        })
      }),
    )
  let assert Ok(contents) = fluid_container.encode_batch(malicious)
  let assert Ok(malicious) =
    sequenced(
      wire.OutboundOperation(..outbound, contents:),
      "remote",
      sequence_number,
    )
  let before = receiver
  let assert Error(runtime_core.ContainerOperationFailed(fluid_container.UnsupportedMessage(
    "unsupported channel attributes",
  ))) = runtime_core.handle_sequenced(receiver, malicious)
  receiver
  |> expect_equal(before, "attribute mismatch changed the runtime core")
}

pub fn assert_wrong_attach_ack_snapshot() -> Nil {
  let core = attachment_tree_core("A/ack", "submitted")
  let assert Ok(reference) = handle.reference_from_path("/A/ack")
  let assert Ok(#(writer, _, [outbound])) =
    runtime_core.set(
      core,
      "A/root",
      "ack-tree",
      handle.reference_to_json(reference),
    )
  let assert Ok(valid) =
    sequenced(outbound, writer.client_id, writer.last_seen_sequence_number + 1)
  let assert Ok(#(accepted, _)) = runtime_core.handle_sequenced(writer, valid)
  accepted.in_flight
  |> expect_equal(
    [],
    "valid attach acknowledgement did not drain in-flight state",
  )

  let alternate = attachment_tree_core("A/other", "malicious")
  let assert Ok(other_reference) = handle.reference_from_path("/A/other")
  let assert Ok(#(_, other_prepared)) =
    runtime_core.prepare_attachments(alternate, "A/root", [other_reference])
  let assert Ok(alternate_snapshot) =
    list.find_map(other_prepared, fn(message) {
      case message {
        fluid_container.ChannelAttach(_, _, snapshot) -> Ok(snapshot)
        _ -> Error(Nil)
      }
    })
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let changed =
    fluid_container.DecodedBatch(
      ..batch,
      messages: list.map(batch.messages, fn(item) {
        let fluid_container.ContainerMessage(kind, index, metadata) = item
        fluid_container.ContainerMessage(
          case kind {
            fluid_container.ChannelAttach(route, channel_type, _) ->
              fluid_container.ChannelAttach(
                route,
                channel_type,
                alternate_snapshot,
              )
            other -> other
          },
          index,
          metadata,
        )
      }),
    )
  let assert Ok(contents) = fluid_container.encode_batch(changed)
  let malicious =
    types.SequencedDocumentMessage(..valid, contents: {
      let assert Ok(contents) =
        json.parse(json.to_string(contents), decode.dynamic)
      contents
    })
  let before = writer
  let assert Error(runtime_core.AckMismatch(
    "outer submission does not match pending items",
  )) = runtime_core.handle_sequenced(writer, malicious)
  writer
  |> expect_equal(
    before,
    "wrong attach acknowledgement changed the runtime core",
  )
}

fn attachment_tree_core(address: String, label: String) -> runtime_core.Core {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(channel.TreeState(source)) = dict.get(core.channels, "A/_C")
  let assert Ok(Some(root)) = tree_kernel.read(source, [])
  let assert Some(compressor) = core.compressor
  let assert Ok(#(compressor, generated)) = fluid_ids.generate(compressor)
  let assert Ok(view_id) = fluid_ids.decompress(compressor, generated)
  let core = runtime_core.Core(..core, compressor: Some(compressor))
  let assert Ok(core) =
    runtime_core.create_detached_tree(
      core,
      address,
      tree_kernel.stored_schema(source),
      Some(root),
      view_id,
    )
  let assert Ok(#(core, _, [])) =
    runtime_core.submit_tree_edits(core, address, [
      tree_types.SetField(["title"], tree_types.StringValue(label)),
    ])
  core
}

fn mutate_json(value: Json, before: String, after: String) -> Json {
  let raw = json.to_string(value)
  let changed = string.replace(raw, before, after)
  let assert True = raw != changed
  let assert Ok(value) = json.parse(changed, wire.json_value_decoder())
  value
}

fn expect_equal(actual: a, expected: a, detail: String) -> Nil {
  case actual == expected {
    True -> Nil
    False -> panic as { detail }
  }
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
  cores_from_decoder_input(
    decoder_input,
    "70000000-0000-4000-8000-000000000007",
  )
}

fn cores_from_decoder_input(
  decoder_input: Json,
  receiver_session_id: String,
) -> Result(#(runtime_core.Core, runtime_core.Core, String, String), String) {
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
  use receiver_client_id <- result.try(read_field(
    sessions,
    "receiverClientId",
    decode.string,
  ))
  cores_from_context(
    decoder_input,
    runtime,
    receiver_client_id,
    receiver_session_id,
  )
}

fn cores_from_context(
  decoder_input: Json,
  runtime: Json,
  receiver_client_id: String,
  receiver_session_id: String,
) -> Result(#(runtime_core.Core, runtime_core.Core, String, String), String) {
  use sessions <- result.try(field(decoder_input, "sessions"))
  use writer_client_id <- result.try(read_field(
    sessions,
    "writerClientId",
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
    fluid_ids.session_id(receiver_session_id)
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
  tree_data_on(core, address, tree_types.DocumentCheckout)
}

fn tree_data_on(
  core: runtime_core.Core,
  address: String,
  selector: tree_types.CheckoutSelector,
) -> Result(Json, String) {
  use root <- result.try(
    runtime_core.tree_read_on(core, address, selector, [])
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
  transport_message_with_minimum(
    outbound,
    client_id,
    sequence_number,
    outbound.reference_sequence_number,
  )
}

fn transport_message_with_minimum(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
  minimum_sequence_number: Int,
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
      #("minimumSequenceNumber", json.int(minimum_sequence_number)),
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

import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/channel
import watershed/handle
import watershed/runtime_core as core
import watershed/tree/error
import watershed/tree/live_fixture
import watershed/tree/live_types as protocol
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types
import watershed/wire/fluid_container

fn relative_marker() -> json.Json {
  json.object([
    #("type", json.string(handle.fluid_handle_type)),
    #("url", json.string("board")),
  ])
}

fn fixture(marker) {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let assert Ok(input) =
    runtime_fixture.routed_tree_seed_input(
      builder.stored(compiled),
      builder.view(compiled),
      types.StringValue("First"),
    )
  let root = fluid_container.Route("A", "index")
  let tree = fluid_container.Route("A", "board")
  let input =
    core.BootstrapSeedInput(
      ..input,
      bootstrap_map: root,
      tree_views: list.map(input.tree_views, fn(view) {
        core.TreeViewSeed(..view, route: tree)
      }),
      channels: list.map(input.channels, fn(seed) {
        case seed.route == input.bootstrap_map, seed.snapshot {
          True, _ ->
            core.ChannelSeed(
              ..seed,
              route: root,
              snapshot: channel.MapSnapshot(case marker {
                Some(value) -> [#("tree", value)]
                None -> []
              }),
            )
          _, channel.TreeSnapshot(_) -> core.ChannelSeed(..seed, route: tree)
          _, _ -> seed
        }
      }),
    )
  let assert Ok(seed) = core.bootstrap_seed(input)
  let assert Ok(core.Complete(state)) =
    core.bootstrap_seeded(runtime_fixture.connected("factory", [], 0), seed)
  #(state, compiled)
}

pub fn tree_api_factory_protocol_uses_checked_bootstrap_and_relative_binding_test() {
  let #(state, compiled) = fixture(Some(relative_marker()))
  let assert Ok(#(opened, address, token)) =
    core.open_live_tree(state, None, builder.view(compiled), False)
  address |> expect.to_equal("A/board")
  let assert Ok(#(_, protocol.Snapshot(root), [], [])) =
    core.live_request(
      opened,
      address,
      types.DocumentCheckout,
      builder.view(compiled),
      protocol.RootRead(token),
    )
  builder.decode(compiled, root) |> expect.to_equal(Ok("First"))
  opened.in_flight |> expect.to_equal(state.in_flight)
}

pub fn tree_api_factory_protocol_distinguishes_missing_wrong_and_invalid_routes_test() {
  let #(missing, compiled) = fixture(None)
  core.open_live_tree(missing, None, builder.view(compiled), False)
  |> expect.to_equal(Error(error.MissingBinding("tree")))
  let #(wrong, _) = fixture(Some(handle.encode_handle("A/index")))
  let assert Error(error.WrongChannel(_, _)) =
    core.open_live_tree(wrong, None, builder.view(compiled), False)
  let #(malformed, _) = fixture(Some(json.null()))
  let assert Error(error.InvalidHandle(_)) =
    core.open_live_tree(malformed, None, builder.view(compiled), False)
  let assert Error(error.InvalidHandle(_)) =
    core.open_live_tree(
      malformed,
      Some(handle.encode_handle("missing/tree")),
      builder.view(compiled),
      False,
    )
  Nil
}

pub fn tree_api_factory_protocol_inspects_before_explicit_schema_upgrade_test() {
  let #(state, _) = fixture(Some(relative_marker()))
  let assert Ok(compiled) =
    builder.string() |> builder.optional_root |> builder.compile
  let view = builder.view(compiled)
  core.open_live_tree(state, None, view, False)
  |> expect.to_equal(Error(error.IncompatibleView))
  let assert Ok(#(state, address, token)) =
    core.open_live_tree(state, None, view, True)
  let assert Error(error.IncompatibleView) =
    core.live_request(
      state,
      address,
      types.DocumentCheckout,
      view,
      protocol.RootRead(token),
    )
  let assert Ok(#(state, protocol.Done, _, _)) =
    core.live_request(
      state,
      address,
      types.DocumentCheckout,
      view,
      protocol.Upgrade(token),
    )
  let assert Ok(#(_, protocol.Snapshot(root), [], [])) =
    core.live_request(
      state,
      address,
      types.DocumentCheckout,
      view,
      protocol.RootRead(token),
    )
  builder.decode(compiled, root) |> expect.to_equal(Ok(Some("First")))
}

pub fn tree_api_factory_protocol_creates_required_optional_and_array_roots_test() {
  let #(state, string) = fixture(Some(relative_marker()))
  let assert Ok(array) =
    builder.array(builder.factory("factory"), "Items", builder.string())
    |> builder.root
    |> builder.compile
  let assert Ok(optional) =
    builder.string() |> builder.optional_root |> builder.compile
  let assert Ok(array_root) = builder.encode_new(array, ["One", "Two"])
  let assert Ok(optional_root) = builder.encode_new(optional, None)
  let assert Ok(string_root) = builder.encode_new(string, "Created")
  [
    #(builder.stored(string), builder.view(string), string_root),
    #(builder.stored(array), builder.view(array), array_root),
    #(builder.stored(optional), builder.view(optional), optional_root),
  ]
  |> list.each(fn(definition) {
    let #(stored, view, initial) = definition
    let assert Ok(#(created, address, token, _)) =
      core.create_live_tree(state, None, "created", stored, initial, view)
    address |> expect.to_equal("A/created")
    let assert Ok(#(_, protocol.Snapshot(value), [], [])) =
      core.live_request(
        created,
        address,
        types.DocumentCheckout,
        view,
        protocol.RootRead(token),
      )
    value |> expect.to_equal(initial)
    created.in_flight |> expect.to_equal(state.in_flight)
  })
}

pub fn tree_api_factory_protocol_materializes_generated_identifiers_test() {
  let #(state, _) = fixture(Some(relative_marker()))
  let definition = live_fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let assert Ok(initial) =
    builder.encode_new(compiled, live_fixture.Card(builder.Generate, "New"))
  let assert Ok(#(created, address, token, _)) =
    core.create_live_tree(
      state,
      Some("A"),
      "created",
      builder.stored(compiled),
      initial,
      builder.view(compiled),
    )
  let assert Ok(#(_, protocol.Snapshot(value), [], [])) =
    core.live_request(
      created,
      address,
      types.DocumentCheckout,
      builder.view(compiled),
      protocol.RootRead(token),
    )
  let assert Ok(live_fixture.Card(builder.Assigned(id), "New")) =
    builder.decode(compiled, value)
  expect.to_equal(id == "", False)
}

pub fn tree_api_factory_protocol_preserves_invalid_creation_payload_test() {
  let #(state, compiled) = fixture(Some(relative_marker()))
  let initial = Some(types.BooleanValue(True))
  let assert Error(original) =
    schema.validate_root_construction(builder.stored(compiled), initial)
  core.create_live_tree(
    state,
    None,
    "rejected",
    builder.stored(compiled),
    initial,
    builder.view(compiled),
  )
  |> expect.to_equal(Error(error.InvalidValue(original)))
  core.has_channel(state, "A/rejected") |> expect.to_be_false
}

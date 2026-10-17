import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/channel
import watershed/handle
import watershed/runtime_core as core
import watershed/tree/error
import watershed/tree/live_types as protocol
import watershed/tree/runtime_fixture
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

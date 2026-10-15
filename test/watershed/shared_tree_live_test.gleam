import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/runtime_core as core
import watershed/tree/identifier_fixture
import watershed/tree/live_types as live
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types
import watershed/wire/fluid_container

const address = "A/_C"

fn initial() -> core.Core {
  initial_for("typed-live")
}

fn initial_for(client_id: String) -> core.Core {
  let assert Ok(input) =
    runtime_fixture.routed_tree_seed_input(
      identifier_fixture.full_stored(),
      identifier_fixture.full_view(),
      identifier_fixture.full_root(
        identifier_fixture.point("featured", "featured"),
        [
          identifier_fixture.point("duplicate", "A"),
          identifier_fixture.point("duplicate", "B"),
        ],
        [],
        [],
      ),
    )
  let assert [datastore] = input.datastores
  let assert [tree_view] = input.tree_views
  let assert Ok(tree_channel) =
    list.find(input.channels, fn(seed) { seed.route == tree_view.route })
  let second = fluid_container.Route("B", "_C")
  let input =
    core.BootstrapSeedInput(
      ..input,
      datastores: list.append(input.datastores, [
        core.DatastoreSeed("B", datastore.package_path),
      ]),
      channels: list.append(input.channels, [
        core.ChannelSeed(..tree_channel, route: second),
      ]),
      tree_views: list.append(input.tree_views, [
        core.TreeViewSeed(..tree_view, route: second),
      ]),
    )
  let assert Ok(seed) = core.bootstrap_seed(input)
  let assert Ok(core.Complete(core)) =
    core.bootstrap_seeded(runtime_fixture.connected(client_id, [], 0), seed)
  core
}

fn request(
  core: core.Core,
  request: live.Request,
) -> #(core.Core, live.Response) {
  let assert Ok(#(core, response, _, _)) =
    core.live_request(
      core,
      address,
      types.DocumentCheckout,
      identifier_fixture.full_view(),
      request,
    )
  #(core, response)
}

fn proof(parent: String, key: String) -> live.FieldProof {
  let assert Ok(definition) =
    schema.field_schema(identifier_fixture.full_stored(), parent, key)
  live.FieldProof(key, definition)
}

fn acquire_b(
  core: core.Core,
) -> #(core.Core, live.ViewToken, live.AnchorToken, live.AnchorToken) {
  let assert #(core, live.Bound(view)) =
    request(core, live.Bind(identifier_fixture.full_view()))
  let assert #(core, live.Acquired(Some(root))) =
    request(core, live.RootAcquire(view, schema.Required))
  let assert #(core, live.Acquired(Some(left))) =
    request(
      core,
      live.ChildAcquire(
        root.anchor,
        proof(identifier_fixture.root_type, "left"),
      ),
    )
  let assert #(core, live.Acquired(Some(b))) =
    request(core, live.ArrayAcquire(left.anchor, 1))
  #(core, view, left.anchor, b.anchor)
}

pub fn live_core_resolves_saved_identity_after_untyped_insert_test() {
  let #(core, _, _, saved) = acquire_b(initial())
  let assert Ok(#(core, _, _)) =
    core.submit_tree_edits(core, address, [
      types.ArrayInsert(["left"], 0, [
        identifier_fixture.point("new", "inserted"),
      ]),
    ])
  let assert Ok(#(expected, events, outbound)) =
    core.submit_tree_edits_on(core, address, types.DocumentCheckout, [
      types.SetField(["left", "2", "label"], types.StringValue("edited")),
    ])
  let actual =
    core.live_request(
      core,
      address,
      types.DocumentCheckout,
      identifier_fixture.full_view(),
      live.PropertySet(
        saved,
        proof(identifier_fixture.point_type, "label"),
        Some(types.StringValue("edited")),
      ),
    )
  actual |> expect.to_equal(Ok(#(expected, live.Done, events, outbound)))
  let assert Ok(#(core, _, _, _)) = actual
  ["inserted", "A", "edited"]
  |> list.index_map(fn(label, index) {
    let assert Ok(Some(value)) =
      core.tree_array_get(core, address, ["left"], index)
    let assert types.ObjectValue(_, fields) = value
    list.key_find(fields, "label")
    |> expect.to_equal(Ok(types.StringValue(label)))
  })
  Nil
}

pub fn live_core_refuses_wrong_property_and_identifier_write_test() {
  let #(core, _, _, saved) = acquire_b(initial())
  let wrong =
    live.FieldProof(
      "label",
      schema.FieldSchema(schema.Optional, ["com.fluidframework.leaf.string"]),
    )
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.PropertySet(saved, wrong, Some(types.StringValue("bad"))),
  )
  |> expect.to_equal(Error(live.WrongProperty("label")))
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.PropertySet(
      saved,
      proof(identifier_fixture.point_type, "id"),
      Some(types.StringValue("changed")),
    ),
  )
  |> expect.to_be_error
  Nil
}

pub fn live_core_removed_reference_and_disposal_test() {
  let #(core, view, left, saved) = acquire_b(initial())
  let assert #(core, live.Done) = request(core, live.ArrayRemove(left, 1, 2))
  let #(core, response) = request(core, live.Status(saved))
  response |> expect.to_equal(live.ReferenceState(live.Removed))
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.Read(saved),
  )
  |> expect.to_equal(Error(live.InvalidReference(live.Removed)))
  let assert #(core, live.Done) = request(core, live.Close(view))
  let assert #(core, live.Done) = request(core, live.Close(view))
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.RootRead(view),
  )
  |> expect.to_equal(Error(live.ClosedView))
}

pub fn live_core_aborted_preview_is_invalidated_test() {
  let #(core, _, left, existing) = acquire_b(initial())
  let assert Ok(core) =
    core.begin_tree_transaction(
      core,
      address,
      identifier_fixture.full_view(),
      [],
    )
  let assert #(core, live.Done) =
    request(
      core,
      live.ArrayInsert(left, 2, [identifier_fixture.point("preview", "preview")]),
    )
  let assert #(core, live.Acquired(Some(preview))) =
    request(core, live.ArrayAcquire(left, 2))
  let assert Ok(#(core, _)) = core.abort_tree_transaction(core, address)
  let #(core, status) = request(core, live.Status(preview.anchor))
  status |> expect.to_equal(live.ReferenceState(live.Invalidated))
  let #(core, status) = request(core, live.Status(existing))
  status |> expect.to_equal(live.ReferenceState(live.Attached))
  let assert #(core, live.Done) =
    request(
      core,
      live.ArrayInsert(left, 2, [
        identifier_fixture.point("replacement", "replacement"),
      ]),
    )
  let #(_, status) = request(core, live.Status(preview.anchor))
  status |> expect.to_equal(live.ReferenceState(live.Invalidated))
}

pub fn live_core_committed_preview_remains_attached_test() {
  let #(core, _, left, _) = acquire_b(initial())
  let assert Ok(core) =
    core.begin_tree_transaction(
      core,
      address,
      identifier_fixture.full_view(),
      [],
    )
  let assert #(core, live.Done) =
    request(
      core,
      live.ArrayInsert(left, 2, [identifier_fixture.point("preview", "preview")]),
    )
  let assert #(core, live.Acquired(Some(preview))) =
    request(core, live.ArrayAcquire(left, 2))
  let assert Ok(#(core, _, _)) = core.commit_tree_transaction(core, address)
  let #(core, status) = request(core, live.Status(preview.anchor))
  status |> expect.to_equal(live.ReferenceState(live.Attached))
  let assert #(_, live.Acquired(Some(after))) =
    request(core, live.ArrayAcquire(left, 2))
  after.anchor |> expect.to_equal(preview.anchor)
}

pub fn live_core_checks_runtime_tree_checkout_and_disposed_scope_test() {
  let #(core, _, _, saved) = acquire_b(initial())
  core.live_request(
    initial_for("other-runtime"),
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.Read(saved),
  )
  |> expect.to_equal(Error(live.ForeignOrigin))
  core.live_request(
    core,
    "B/_C",
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.Read(saved),
  )
  |> expect.to_equal(Error(live.ForeignOrigin))
  let assert Ok(#(core, branch)) =
    core.fork_tree(
      core,
      address,
      types.DocumentCheckout,
      identifier_fixture.full_view(),
    )
  let selector = types.LocalCheckout(branch)
  core.live_request(
    core,
    address,
    selector,
    identifier_fixture.full_view(),
    live.Read(saved),
  )
  |> expect.to_equal(Error(live.ForeignOrigin))
  let assert Ok(#(core, live.Bound(view), _, _)) =
    core.live_request(
      core,
      address,
      selector,
      identifier_fixture.full_view(),
      live.Bind(identifier_fixture.full_view()),
    )
  let assert Ok(core) = core.dispose_tree_branch(core, address, selector)
  core.live_request(
    core,
    address,
    selector,
    identifier_fixture.full_view(),
    live.RootRead(view),
  )
  |> expect.to_equal(Error(live.DisposedCheckout))
}

pub fn live_core_checks_handle_and_compiled_schema_test() {
  let core = initial()
  let assert Ok(compiled) = builder.compile(builder.root(builder.string()))
  let incompatible = builder.view(compiled)
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.Bind(incompatible),
  )
  |> expect.to_equal(Error(live.IncompatibleView))
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    incompatible,
    live.Bind(identifier_fixture.full_view()),
  )
  |> expect.to_equal(Error(live.IncompatibleView))
  let #(core, view, _, _) = acquire_b(core)
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    incompatible,
    live.RootRead(view),
  )
  |> expect.to_equal(Error(live.IncompatibleView))
}

pub fn live_core_refuses_partial_array_insert_and_wrong_kinds_test() {
  let #(core, view, left, saved) = acquire_b(initial())
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.ArrayInsert(left, 1, [
      identifier_fixture.point("valid", "valid"),
      types.NumberValue(1.0),
    ]),
  )
  |> expect.to_be_error
  let assert Ok(values) = core.tree_array_values(core, address, ["left"])
  list.length(values) |> expect.to_equal(2)
  let #(_, response) = request(core, live.Read(saved))
  response
  |> expect.to_equal(
    live.Snapshot(Some(identifier_fixture.point("duplicate", "B"))),
  )
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.RootAcquire(view, schema.Optional),
  )
  |> expect.to_equal(Error(live.WrongCardinality))
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.ArrayRead(saved, 0),
  )
  |> expect.to_be_error
  core.live_request(
    core,
    address,
    types.DocumentCheckout,
    identifier_fixture.full_view(),
    live.ChildAcquire(saved, proof(identifier_fixture.point_type, "label")),
  )
  |> expect.to_be_error
  Nil
}

pub fn live_core_moves_and_map_keys_keep_identity_test() {
  let #(core, view, left, saved) = acquire_b(initial())
  let assert #(core, live.Acquired(Some(root))) =
    request(core, live.RootAcquire(view, schema.Required))
  let assert #(core, live.Acquired(Some(right))) =
    request(
      core,
      live.ChildAcquire(
        root.anchor,
        proof(identifier_fixture.root_type, "right"),
      ),
    )
  let assert #(core, live.Done) =
    request(core, live.ArrayMove(left, 1, 2, right.anchor, 0))
  let assert #(core, live.Done) =
    request(
      core,
      live.PropertySet(
        saved,
        proof(identifier_fixture.point_type, "label"),
        Some(types.StringValue("moved")),
      ),
    )
  let assert #(core, live.Acquired(Some(by_key))) =
    request(
      core,
      live.ChildAcquire(
        root.anchor,
        proof(identifier_fixture.root_type, "byKey"),
      ),
    )
  let assert #(core, live.Done) =
    request(
      core,
      live.MapSet(
        by_key.anchor,
        "a/b.0",
        identifier_fixture.point("map", "original"),
      ),
    )
  let assert #(core, live.Acquired(Some(entry))) =
    request(core, live.MapAcquire(by_key.anchor, "a/b.0"))
  let assert #(core, live.Done) =
    request(
      core,
      live.PropertySet(
        entry.anchor,
        proof(identifier_fixture.point_type, "label"),
        Some(types.StringValue("map-edit")),
      ),
    )
  let #(core, response) = request(core, live.MapRead(by_key.anchor, "a/b.0"))
  response
  |> expect.to_equal(
    live.Snapshot(Some(identifier_fixture.point("map", "map-edit"))),
  )
  let assert #(core, live.Acquired(None)) =
    request(core, live.MapAcquire(by_key.anchor, "missing"))
  let assert #(core, live.Done) =
    request(core, live.MapDelete(by_key.anchor, "a/b.0"))
  let #(_, status) = request(core, live.Status(entry.anchor))
  status |> expect.to_equal(live.ReferenceState(live.Removed))
}

pub fn live_core_nested_abort_only_invalidates_discarded_preview_test() {
  let #(core, _, left, _) = acquire_b(initial())
  let assert Ok(core) =
    core.begin_tree_transaction(
      core,
      address,
      identifier_fixture.full_view(),
      [],
    )
  let assert #(core, live.Done) =
    request(
      core,
      live.ArrayInsert(left, 2, [identifier_fixture.point("outer", "outer")]),
    )
  let assert #(core, live.Acquired(Some(outer))) =
    request(core, live.ArrayAcquire(left, 2))
  let assert Ok(core) =
    core.begin_tree_transaction(
      core,
      address,
      identifier_fixture.full_view(),
      [],
    )
  let assert #(core, live.Done) =
    request(
      core,
      live.ArrayInsert(left, 3, [identifier_fixture.point("inner", "inner")]),
    )
  let assert #(core, live.Acquired(Some(inner))) =
    request(core, live.ArrayAcquire(left, 3))
  let assert Ok(#(core, _)) = core.abort_tree_transaction(core, address)
  let #(core, state) = request(core, live.Status(inner.anchor))
  state |> expect.to_equal(live.ReferenceState(live.Invalidated))
  let #(core, state) = request(core, live.Status(outer.anchor))
  state |> expect.to_equal(live.ReferenceState(live.Attached))
  let assert Ok(#(core, _, _)) = core.commit_tree_transaction(core, address)
  let #(core, state) = request(core, live.Status(outer.anchor))
  state |> expect.to_equal(live.ReferenceState(live.Attached))
  let #(_, state) = request(core, live.Status(inner.anchor))
  state |> expect.to_equal(live.ReferenceState(live.Invalidated))
}

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import spillway/types as document
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core as core
import watershed/tree/branch
import watershed/tree/identifier_fixture
import watershed/tree/live_types as live
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container

const address = "A/_C"

fn initial() -> core.Core {
  initial_for("typed-live")
}

fn initial_for(client_id: String) -> core.Core {
  initial_in_session(client_id, None)
}

fn initial_in_session(
  client_id: String,
  session_id: Option(String),
) -> core.Core {
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
  let input = case session_id {
    None -> input
    Some(session_id) -> {
      let assert Some(compressor) = input.compressor
      let assert Ok(serialized) = fluid_ids.serialize(compressor, False)
      let assert Ok(session) = fluid_ids.session_id(session_id)
      let assert Ok(compressor) = fluid_ids.deserialize(serialized, session)
      core.BootstrapSeedInput(..input, compressor: Some(compressor))
    }
  }
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
  request_on(core, types.DocumentCheckout, request)
}

fn request_on(
  core: core.Core,
  selector: types.CheckoutSelector,
  request: live.Request,
) -> #(core.Core, live.Response) {
  let assert Ok(#(core, response, _, _)) =
    core.live_request(
      core,
      address,
      selector,
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
  acquire_b_on(core, types.DocumentCheckout)
}

fn acquire_b_on(
  core: core.Core,
  selector: types.CheckoutSelector,
) -> #(core.Core, live.ViewToken, live.AnchorToken, live.AnchorToken) {
  let request = fn(core, request) { request_on(core, selector, request) }
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
  let assert Some(#(_, _, _, transaction)) = core.active_tree_transaction
  let assert Ok(preview_physical) =
    tree_kernel.reference_at(branch.transaction_state(transaction), [
      "left",
      "2",
    ])
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
  let assert #(core, live.Acquired(Some(replacement))) =
    request(core, live.ArrayAcquire(left, 2))
  replacement.anchor |> expect.to_not_equal(preview.anchor)
  let #(core, state) = request(core, live.Status(replacement.anchor))
  state |> expect.to_equal(live.ReferenceState(live.Attached))
  let assert Ok(checkouts) = dict.get(core.tree_checkouts, address)
  let assert Ok(current) =
    branch.checkout_state(checkouts, branch.document(checkouts))
  let assert Ok(replacement_physical) =
    tree_kernel.reference_at(current, ["left", "2"])
  replacement_physical |> expect.to_not_equal(preview_physical)
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
  dict.has_key(core.live_views, view) |> expect.to_equal(False)
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

fn sequenced(
  sender: core.Core,
  outbound: wire.OutboundOperation,
  sequence_number: Int,
) -> document.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    None -> None
    Some(value) -> {
      let assert Ok(value) = json.parse(json.to_string(value), decode.dynamic)
      Some(value)
    }
  }
  document.SequencedDocumentMessage(
    client_id: Some(sender.client_id),
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
    timestamp: 0,
    data: None,
  )
}

pub fn live_core_saved_reference_survives_reconciliation_and_reconnect_test() {
  let reader = initial()
  let reader = core.Core(..reader, live_namespace: Some("reader-runtime"))
  let #(reader, _, _, saved) = acquire_b(reader)
  let writer =
    initial_in_session("peer", Some("50000000-0000-4000-8000-000000000005"))
  let assert Ok(#(reader, _, [local])) =
    core.submit_tree_edits(reader, address, [
      types.SetField(["left", "0", "label"], types.StringValue("local-A")),
    ])
  let assert Ok(#(writer, _, [remote])) =
    core.submit_tree_edits(writer, address, [
      types.ArrayInsert(["left"], 0, [
        identifier_fixture.point("new", "inserted"),
      ]),
    ])
  let remote = sequenced(writer, remote, 1)
  let assert Ok(#(reader, _)) = core.handle_sequenced(reader, remote)
  let assert Ok(#(reader, _)) =
    core.handle_sequenced(reader, sequenced(reader, local, 2))
  let assert Ok(reader) =
    core.adopt_reconnect(
      reader,
      runtime_fixture.connected("reconnected-reader", [], 2),
    )
  let reader = core.go_live(reader)
  let assert #(reader, live.Done) =
    request(
      reader,
      live.PropertySet(
        saved,
        proof(identifier_fixture.point_type, "label"),
        Some(types.StringValue("saved-B")),
      ),
    )
  core.tree_array_values(reader, address, ["left"])
  |> expect.to_equal(
    Ok([
      identifier_fixture.point("new", "inserted"),
      identifier_fixture.point("duplicate", "local-A"),
      identifier_fixture.point("duplicate", "saved-B"),
    ]),
  )
  let #(_, status) = request(reader, live.Status(saved))
  status |> expect.to_equal(live.ReferenceState(live.Attached))
}

pub fn live_core_rebase_merge_preserve_saved_checkout_references_test() {
  let #(core, _, _, document_b) = acquire_b(initial())
  let assert Ok(#(core, branch_id)) =
    core.fork_tree(
      core,
      address,
      types.DocumentCheckout,
      identifier_fixture.full_view(),
    )
  let selector = types.LocalCheckout(branch_id)
  let #(core, branch_view, _, branch_b) = acquire_b_on(core, selector)
  let assert Ok(#(core, _, _)) =
    core.submit_tree_edits_on(core, address, selector, [
      types.SetField(["left", "1", "label"], types.StringValue("branch-B")),
    ])
  let #(_, before) = request(core, live.Read(document_b))
  before
  |> expect.to_equal(
    live.Snapshot(Some(identifier_fixture.point("duplicate", "B"))),
  )
  let assert Ok(#(core, _, _)) =
    core.submit_tree_edits(core, address, [
      types.ArrayInsert(["left"], 0, [
        identifier_fixture.point("new", "inserted"),
      ]),
    ])
  let assert Ok(#(core, _)) =
    core.rebase_tree_onto(core, address, selector, types.DocumentCheckout)
  let #(core, response) = request_on(core, selector, live.Read(branch_b))
  response
  |> expect.to_equal(
    live.Snapshot(Some(identifier_fixture.point("duplicate", "branch-B"))),
  )
  let assert Ok(#(core, _, _)) =
    core.merge_tree(core, address, types.DocumentCheckout, selector, False)
  let #(core, response) = request(core, live.Read(document_b))
  response
  |> expect.to_equal(
    live.Snapshot(Some(identifier_fixture.point("duplicate", "branch-B"))),
  )
  let assert #(core, live.Done) =
    request_on(
      core,
      selector,
      live.PropertySet(
        branch_b,
        proof(identifier_fixture.point_type, "label"),
        Some(types.StringValue("retained-B")),
      ),
    )
  let assert Ok(#(core, _, _)) =
    core.merge_tree(core, address, types.DocumentCheckout, selector, True)
  let #(_, response) = request(core, live.Read(document_b))
  response
  |> expect.to_equal(
    live.Snapshot(Some(identifier_fixture.point("duplicate", "retained-B"))),
  )
  dict.has_key(core.live_views, branch_view) |> expect.to_equal(False)
  core.live_request(
    core,
    address,
    selector,
    identifier_fixture.full_view(),
    live.Read(branch_b),
  )
  |> expect.to_equal(Error(live.DisposedCheckout))
}

pub fn live_core_remove_undo_reattaches_the_original_anchor_test() {
  let #(core, _, left, saved) = acquire_b(initial())
  let #(core, events, _) =
    core.submit_tree_edits(core, address, [
      types.ArrayRemove(["left"], 1, 2),
    ])
    |> expect.to_be_ok
  let revision =
    list.find_map(events, fn(event) {
      case event.1 {
        channel.TreeCommitApplied(revision, types.DefaultCommit, True, True) ->
          Ok(revision)
        _ -> Error(Nil)
      }
    })
    |> expect.to_be_ok
  let #(core, undo) =
    core.retain_tree_revertible_on(
      core,
      address,
      types.DocumentCheckout,
      revision,
      types.DefaultCommit,
    )
    |> expect.to_be_ok
  let #(core, status) = request(core, live.Status(saved))
  status |> expect.to_equal(live.ReferenceState(live.Removed))
  let #(core, _, _) =
    core.revert_tree_on(core, address, types.DocumentCheckout, undo)
    |> expect.to_be_ok
  let assert #(core, live.Acquired(Some(reattached))) =
    request(core, live.ArrayAcquire(left, 1))
  reattached.anchor |> expect.to_equal(saved)
  let #(_, response) = request(core, live.Read(saved))
  response
  |> expect.to_equal(
    live.Snapshot(Some(identifier_fixture.point("duplicate", "B"))),
  )
}

pub fn live_core_anchors_do_not_pin_detached_repair_data_test() {
  let #(core, _, left, saved) = acquire_b(initial())
  let #(core, _, outbounds) =
    core.submit_tree_edits(core, address, [
      types.ArrayRemove(["left"], 1, 2),
    ])
    |> expect.to_be_ok
  let assert [removed] = outbounds
  let #(core, _) =
    core.handle_sequenced(core, sequenced(core, removed, 1))
    |> expect.to_be_ok
  let #(core, status) = request(core, live.Status(saved))
  status |> expect.to_equal(live.ReferenceState(live.Removed))
  let #(core, _, outbounds) =
    core.submit_tree_edits(core, address, [
      types.SetField(["child", "label"], types.StringValue("later")),
    ])
    |> expect.to_be_ok
  let assert [later] = outbounds
  let #(core, _) =
    core.handle_sequenced(core, sequenced(core, later, 2))
    |> expect.to_be_ok
  let #(core, _, outbounds) =
    core.submit_tree_edits(core, address, [
      types.SetField(["child", "label"], types.StringValue("pruning")),
    ])
    |> expect.to_be_ok
  let assert [pruning] = outbounds
  let pruning =
    document.SequencedDocumentMessage(
      ..sequenced(core, pruning, 3),
      minimum_sequence_number: 2,
    )
  let #(core, _) = core.handle_sequenced(core, pruning) |> expect.to_be_ok
  let #(core, status) = request(core, live.Status(saved))
  status |> expect.to_equal(live.ReferenceState(live.Deleted))
  let assert #(core, live.Done) =
    request(
      core,
      live.ArrayInsert(left, 1, [
        identifier_fixture.point("duplicate", "B"),
      ]),
    )
  let assert #(core, live.Acquired(Some(replacement))) =
    request(core, live.ArrayAcquire(left, 1))
  replacement.anchor |> expect.to_not_equal(saved)
  let #(_, status) = request(core, live.Status(saved))
  status |> expect.to_equal(live.ReferenceState(live.Deleted))
}

pub fn live_core_outer_abort_invalidates_committed_inner_preview_test() {
  let #(core, _, left, existing) = acquire_b(initial())
  let assert Ok(core) =
    core.begin_tree_transaction(
      core,
      address,
      identifier_fixture.full_view(),
      [],
    )
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
      live.ArrayInsert(left, 2, [identifier_fixture.point("inner", "inner")]),
    )
  let assert #(core, live.Acquired(Some(preview))) =
    request(core, live.ArrayAcquire(left, 2))
  let assert Ok(#(core, _, [])) = core.commit_tree_transaction(core, address)
  let #(core, status) = request(core, live.Status(preview.anchor))
  status |> expect.to_equal(live.ReferenceState(live.Attached))
  let assert Ok(#(core, _)) = core.abort_tree_transaction(core, address)
  let #(core, status) = request(core, live.Status(preview.anchor))
  status |> expect.to_equal(live.ReferenceState(live.Invalidated))
  let #(_, response) = request(core, live.Read(existing))
  response
  |> expect.to_equal(
    live.Snapshot(Some(identifier_fixture.point("duplicate", "B"))),
  )
}

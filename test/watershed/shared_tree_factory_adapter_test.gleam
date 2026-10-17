@target(erlang)
import gleam/erlang/process
import gleam/option.{None, Some}
import startest/expect
@target(javascript)
import watershed as facade
import watershed/handle
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam as runtime
import watershed/tree
import watershed/tree/error
import watershed/tree/live_fixture as fixture
import watershed/tree/schema_builder as builder
@target(erlang)
import watershed_beam as facade

@target(javascript)
fn connection(document: facade.Document(root)) -> runtime.Runtime {
  facade.runtime_of(document)
}

@target(erlang)
fn connection(document: facade.Document(root)) -> process.Subject(runtime.Msg) {
  facade.runtime_subject(document)
}

@target(javascript)
fn connecting() -> facade.Document(Nil) {
  facade.connect_via(
    tenant: "default",
    document: "tree",
    user_id: "factory",
    transport: runtime.Transport(connect: fn(_) {
      runtime.TransportHandle(
        push: fn(_, _) { Nil },
        close: fn() { Nil },
        drop: fn() { Nil },
        hold: fn() { Nil },
        resume: fn() { Nil },
      )
    }),
    on_ready: fn(_) { Nil },
  )
}

@target(erlang)
fn connecting() -> facade.Document(Nil) {
  let assert Ok(document) =
    facade.connect_via(
      tenant: "default",
      document: "tree",
      user_id: "factory",
      transport: runtime.Transport(connect: fn(_) { Nil }),
    )
  document
}

pub fn tree_api_factory_adapter_binds_and_preserves_closed_runtime_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(document, _) = fixture.tree(compiled, "Initial")
  let runtime = connection(document)
  let assert Ok(value) = runtime.open_live_tree(runtime, None, compiled, False)
  tree.handle_of(value) |> expect.to_equal(handle.encode_handle("A/_C"))
  tree.read_root(value) |> expect.to_equal(Ok("Initial"))
  facade.close(document)
  runtime.open_live_tree(runtime, None, compiled, False)
  |> expect.to_equal(Error(error.ClosedRuntime))
  runtime.create_live_tree(runtime, None, compiled, "Rejected")
  |> expect.to_equal(Error(error.ClosedRuntime))
}

pub fn tree_api_factory_adapter_distinguishes_not_ready_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let document = connecting()
  runtime.open_live_tree(connection(document), None, compiled, False)
  |> expect.to_equal(Error(error.NotReady))
  runtime.create_live_tree(connection(document), None, compiled, "Rejected")
  |> expect.to_equal(Error(error.NotReady))
  facade.close(document)
}

pub fn tree_api_factory_adapter_can_open_during_commit_delivery_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(document, _) = fixture.tree(compiled, "Initial")
  let runtime = connection(document)
  let assert Ok(value) = runtime.open_live_tree(runtime, None, compiled, False)
  let #(send, receive) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_commits(value, fn(_) {
      let assert Ok(opened) =
        runtime.open_live_tree(runtime, None, compiled, False)
      send(tree.read_root(opened))
    })
  tree.replace_root(value, "Updated") |> expect.to_equal(Ok(Nil))
  receive(1)
  |> expect.to_equal([Ok("Updated")])
  tree.unsubscribe(subscription)
  facade.close(document)
}

pub fn tree_api_factory_adapter_creates_bound_content_without_submitting_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(send, receive) = fixture.capture()
  let #(document, _, _) =
    fixture.tree_with_submissions(compiled, "Initial", send)
  let runtime = connection(document)
  let assert Ok(value) =
    runtime.create_live_tree(runtime, Some("A"), compiled, "Created")
  tree.read_root(value) |> expect.to_equal(Ok("Created"))
  receive(0) |> expect.to_equal([])
  facade.close(document)
}

pub fn tree_api_factory_adapter_rejects_reentrant_creation_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(document, _) = fixture.tree(compiled, "Initial")
  let runtime = connection(document)
  let assert Ok(value) = runtime.open_live_tree(runtime, None, compiled, False)
  let #(send, receive) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_commits(value, fn(_) {
      send(runtime.create_live_tree(runtime, None, compiled, "Rejected"))
    })
  tree.replace_root(value, "Updated") |> expect.to_equal(Ok(Nil))
  receive(1) |> expect.to_equal([Error(error.ReentrantEdit)])
  tree.unsubscribe(subscription)
  facade.close(document)
}

pub fn tree_api_factory_adapter_preserves_invalid_value_without_submitting_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(send, receive) = fixture.capture()
  let #(document, _, _) =
    fixture.tree_with_submissions(compiled, "Initial", send)
  let assert Ok(partial) =
    builder.union([
      builder.variant(builder.string(), fn(value) { value }, fn(value) {
        case value {
          "Allowed" -> Some(value)
          _ -> None
        }
      }),
    ])
    |> builder.root
    |> builder.compile
  let assert Error(original) = builder.encode_new(partial, "Rejected")
  runtime.create_live_tree(connection(document), None, partial, "Rejected")
  |> expect.to_equal(Error(error.InvalidValue(original)))
  receive(0) |> expect.to_equal([])
  facade.close(document)
}

pub fn tree_api_factory_adapter_does_not_create_outside_the_active_transaction_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(document, _) = fixture.tree(compiled, "Initial")
  let runtime = connection(document)
  let assert Ok(value) = runtime.open_live_tree(runtime, None, compiled, False)
  let assert Error(tree.Aborted(error.TransactionConflict(_))) =
    tree.transaction(value, [], fn(_) {
      runtime.create_live_tree(runtime, None, compiled, "Rejected")
    })
  tree.read_root(value) |> expect.to_equal(Ok("Initial"))
  facade.close(document)
}

pub fn tree_api_factory_adapter_created_tree_owns_live_branch_and_history_access_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, _) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("seed"), "Initial"))
  let assert Ok(created) =
    runtime.create_live_tree(
      connection(document),
      None,
      compiled,
      fixture.Card(builder.Generate, "Created"),
    )
  let assert Ok(initial) = tree.read_root(created)
  let assert fixture.Card(builder.Assigned(id), "Created") = initial
  expect.to_equal(id == "", False)
  let #(send, receive) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_commits(created, fn(event) {
      let assert Some(acquire) = event.get_revertible
      send(acquire(fn(_) { Nil }))
    })
  let assert Ok(root) = tree.required_root(created)
  tree.set(root, definition.title, "Edited") |> expect.to_equal(Ok(Nil))
  let assert [Ok(revertible)] = receive(1)
  tree.unsubscribe(subscription)
  tree.revert(revertible, tree.DisposeRevertible)
  |> expect.to_equal(Ok(Nil))
  tree.read_root(created) |> expect.to_equal(Ok(initial))
  let assert Ok(branch) = tree.fork(created)
  let assert Ok(root) = tree.required_root(branch)
  tree.set(root, definition.title, "Branched") |> expect.to_equal(Ok(Nil))
  tree.read_root(created) |> expect.to_equal(Ok(initial))
  tree.merge(created, branch, tree.DisposeSource) |> expect.to_equal(Ok(Nil))
  tree.read_root(created)
  |> expect.to_equal(Ok(fixture.Card(builder.Assigned(id), "Branched")))
  tree.branch_status(branch) |> expect.to_equal(Ok(tree.BranchDisposed))
  facade.close(document)
}

pub fn tree_api_factory_adapter_inspects_and_upgrades_incompatible_schema_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let assert Ok(optional) =
    builder.string() |> builder.optional_root |> builder.compile
  let #(document, _) = fixture.tree(compiled, "Initial")
  let runtime = connection(document)
  let marker = Some(handle.encode_handle("A/_C"))
  runtime.open_live_tree(runtime, marker, optional, False)
  |> expect.to_equal(Error(error.IncompatibleView))
  let assert Ok(inspected) =
    runtime.open_live_tree(runtime, marker, optional, True)
  let assert Ok(compatibility) = tree.compatibility(inspected)
  compatibility.can_view |> expect.to_equal(False)
  compatibility.can_upgrade |> expect.to_equal(True)
  tree.read_root(inspected) |> expect.to_equal(Error(error.IncompatibleView))
  tree.upgrade_schema(inspected) |> expect.to_equal(Ok(Nil))
  tree.read_root(inspected) |> expect.to_equal(Ok(Some("Initial")))
  let assert Ok(created) =
    runtime.create_live_tree(runtime, None, optional, None)
  tree.read_root(created) |> expect.to_equal(Ok(None))
  tree.replace_root(created, Some("Present")) |> expect.to_equal(Ok(Nil))
  tree.read_root(created) |> expect.to_equal(Ok(Some("Present")))
  facade.close(document)
}

@target(erlang)
pub fn tree_api_factory_adapter_checks_transaction_caller_before_binding_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(document, _) = fixture.tree(compiled, "Initial")
  let runtime = connection(document)
  let assert Ok(value) = runtime.open_live_tree(runtime, None, compiled, False)
  tree.transaction(value, [], fn(_) {
    let replies = process.new_subject()
    let _ =
      process.spawn(fn() {
        process.send(
          replies,
          runtime.open_live_tree(runtime, None, compiled, False),
        )
      })
    let assert Ok(Error(error.TransactionConflict(_))) =
      process.receive(replies, 1000)
    Ok(Nil)
  })
  |> expect.to_equal(Ok(Nil))
  facade.close(document)
}

@target(erlang)
pub fn tree_api_factory_adapter_reports_actual_request_timeout_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let unresponsive = process.new_subject()
  runtime.open_live_tree(unresponsive, None, compiled, False)
  |> expect.to_equal(Error(error.RequestTimeout))
  let assert Ok(runtime.OpenLiveTree(_, _, _, _)) =
    process.receive(unresponsive, 0)
  Nil
}

@target(erlang)
import gleam/erlang/process
import gleam/option.{None, Some}
import startest/expect
@target(javascript)
import watershed as facade
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam as runtime
import watershed/tree
import watershed/tree/error
import watershed/tree/live_fixture as fixture
import watershed/tree/live_types as protocol
import watershed/tree/schema_builder as builder
import watershed/tree/types
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
  let assert Ok(#(address, token)) =
    runtime.open_live_tree(runtime, None, builder.view(compiled), False)
  address |> expect.to_equal("A/_C")
  runtime.live_request(
    runtime,
    address,
    types.DocumentCheckout,
    builder.view(compiled),
    protocol.RootRead(token),
  )
  |> expect.to_equal(Ok(protocol.Snapshot(Some(types.StringValue("Initial")))))
  facade.close(document)
  runtime.open_live_tree(runtime, None, builder.view(compiled), False)
  |> expect.to_equal(Error(error.ClosedRuntime))
}

pub fn tree_api_factory_adapter_distinguishes_not_ready_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let document = connecting()
  runtime.open_live_tree(
    connection(document),
    None,
    builder.view(compiled),
    False,
  )
  |> expect.to_equal(Error(error.NotReady))
  facade.close(document)
}

pub fn tree_api_factory_adapter_can_open_during_commit_delivery_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(document, native) = fixture.tree(compiled, "Initial")
  let runtime = connection(document)
  let assert Ok(value) = facade.tree_typed(native, compiled)
  let #(send, receive) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_commits(value, fn(_) {
      let assert Ok(#(address, token)) =
        runtime.open_live_tree(runtime, None, builder.view(compiled), False)
      send(runtime.live_request(
        runtime,
        address,
        types.DocumentCheckout,
        builder.view(compiled),
        protocol.RootRead(token),
      ))
    })
  tree.replace_root(value, "Updated") |> expect.to_equal(Ok(Nil))
  receive(1)
  |> expect.to_equal([
    Ok(protocol.Snapshot(Some(types.StringValue("Updated")))),
  ])
  tree.unsubscribe(subscription)
  facade.close(document)
}

@target(erlang)
pub fn tree_api_factory_adapter_checks_transaction_caller_before_binding_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let #(document, _) = fixture.tree(compiled, "Initial")
  let runtime = connection(document)
  let view = builder.view(compiled)
  let assert Ok(#(address, token)) =
    runtime.open_live_tree(runtime, None, view, False)
  let assert Ok(_) =
    runtime.live_request(
      runtime,
      address,
      types.DocumentCheckout,
      view,
      protocol.Begin(token, []),
    )
  let replies = process.new_subject()
  let _ =
    process.spawn(fn() {
      process.send(replies, runtime.open_live_tree(runtime, None, view, False))
    })
  let assert Ok(Error(error.TransactionConflict(_))) =
    process.receive(replies, 1000)
  let assert Ok(_) =
    runtime.live_request(
      runtime,
      address,
      types.DocumentCheckout,
      view,
      protocol.Abort(token),
    )
  facade.close(document)
}

@target(erlang)
pub fn tree_api_factory_adapter_reports_actual_request_timeout_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let unresponsive = process.new_subject()
  runtime.open_live_tree(unresponsive, None, builder.view(compiled), False)
  |> expect.to_equal(Error(error.RequestTimeout))
  let assert Ok(runtime.OpenLiveTree(_, _, _, _)) =
    process.receive(unresponsive, 0)
  Nil
}

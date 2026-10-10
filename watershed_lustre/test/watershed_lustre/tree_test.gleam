import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/container
import watershed/fluid_ids
import watershed/runtime
import watershed/runtime_core
import watershed/sluice/frame
import watershed/transport_js
import watershed/tree/schema
import watershed/tree/types
import watershed/wire/fluid_document
import watershed_lustre/tree

type CallbackProblem {
  Stop
}

type Msg {
  Performed(Result(Nil, String))
  Created(Result(String, String))
  TransactionCompleted(Result(Int, watershed.TreeTransactionError(String)))
  TransactionText(
    Result(String, watershed.TreeTransactionError(CallbackProblem)),
  )
}

const definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}"

type Fixture(root) {
  Fixture(
    document: watershed.Document(root),
    tree: watershed.SharedTree,
    callbacks: runtime.TransportCallbacks,
    submissions: transport_js.Cell(List(json.Json)),
  )
}

pub fn transaction_runs_lazily_and_defers_the_typed_result_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  let pending =
    tree.transaction(
      fixture.tree,
      [],
      fn(_) {
        transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
        Ok(42)
      },
      TransactionCompleted,
    )

  let assert 0 = transport_js.get_cell(calls)
  run(pending, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionCompleted(Ok(42))] = messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn transaction_aborts_real_edits_and_preserves_callback_errors_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  run(
    tree.transaction(
      fixture.tree,
      [],
      fn(tree) {
        let assert Ok(Nil) =
          watershed.tree_set(tree, [], types.StringValue("temporary"))
        Error(Stop)
      },
      TransactionText,
    ),
    sink,
  )

  let assert Ok(Some(types.StringValue("initial"))) =
    watershed.tree_get(fixture.tree, [])
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionText(Error(watershed.Aborted(Stop)))] = messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn transaction_rejects_invalid_constraints_without_running_callback_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  run(
    tree.transaction(
      fixture.tree,
      [watershed.NodeInDocument(["missing"])],
      fn(_) {
        transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
        Ok(1)
      },
      TransactionCompleted,
    ),
    sink,
  )

  let assert 0 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionCompleted(Error(watershed.TransactionFailed(_)))] =
    messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn transaction_composes_two_real_edits_into_one_commit_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let commits = transport_js.new_cell(0)
  let subscription =
    watershed.subscribe_tree_commits(fixture.tree, fn(_) {
      transport_js.set_cell(commits, transport_js.get_cell(commits) + 1)
    })
  run(
    tree.transaction(
      fixture.tree,
      [],
      fn(tree) {
        use _ <- result.try(watershed.tree_set(
          tree,
          [],
          types.StringValue("first"),
        ))
        use _ <- result.try(watershed.tree_set(
          tree,
          [],
          types.StringValue("second"),
        ))
        Ok(7)
      },
      TransactionCompleted,
    ),
    sink,
  )

  let assert 1 = transport_js.get_cell(commits)
  let assert [_] = transport_js.get_cell(fixture.submissions)
  let assert Ok(Some(types.StringValue("second"))) =
    watershed.tree_get(fixture.tree, [])
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionCompleted(Ok(7))] = messages(sink)
  watershed.unsubscribe(subscription)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn perform_runs_lazily_and_defers_the_outcome_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  let operation = fn() {
    transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
    Ok(Nil)
  }
  let pending = tree.perform(operation, Performed)
  let assert 0 = transport_js.get_cell(calls)
  run(pending, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Ok(Nil))] = messages(sink)
  promise.resolve(Nil)
}

pub fn perform_preserves_errors_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  run(tree.perform(fn() { Error("refused") }, Performed), sink)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Error("refused"))] = messages(sink)
  promise.resolve(Nil)
}

pub fn create_preserves_invalid_configuration_and_defers_dispatch_test() -> Promise(
  Nil,
) {
  let assert Ok(stored) = schema.stored_from_string(definition)
  let sink = transport_js.new_cell([])
  run(
    tree.create(
      container.CreateConfig("ftp://invalid", "dev-tenant", "token"),
      stored,
      None,
      Created,
    ),
    sink,
  )
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Created(Error(detail))] = messages(sink)
  let assert True = detail != ""
  promise.resolve(Nil)
}

fn run(effect_to_run: Effect(Msg), sink: transport_js.Cell(List(Msg))) -> Nil {
  effect.perform(
    effect_to_run,
    fn(message) {
      transport_js.set_cell(sink, [message, ..transport_js.get_cell(sink)])
    },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { panic as "unexpected root action" },
    fn(_, _) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
  )
}

fn messages(sink: transport_js.Cell(List(Msg))) -> List(Msg) {
  transport_js.get_cell(sink) |> list.reverse
}

fn fixture(inline_ack: Bool) -> Fixture(root) {
  let assert Ok(stored) = schema.stored_from_string(definition)
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(view_id) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(summary) =
    fluid_document.initial_tree(
      stored,
      Some(types.StringValue("initial")),
      session,
      view_id,
    )
  let assert Ok(seed) = runtime_core.document_seed(summary)
  let callbacks: transport_js.Cell(Option(runtime.TransportCallbacks)) =
    transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event, inline_ack {
              "submitOp", True ->
                handlers.on_event(
                  "op",
                  acknowledgement(payload) |> json.to_string,
                )
              "submitOp", False ->
                transport_js.set_cell(submissions, [
                  payload,
                  ..transport_js.get_cell(submissions)
                ])
              _, _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let assert Ok(root) = watershed.resolve_root(document)
  let assert Ok(marker) = watershed.get(root, "tree")
  let assert Ok(view) = schema.view_from_json(schema.stored_to_json(stored))
  let assert Ok(tree) = watershed.resolve_tree(document, marker, view)
  Fixture(document:, tree:, callbacks:, submissions:)
}

fn acknowledgement(payload: json.Json) -> json.Json {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(sender, [[submitted]])) =
    frame.decode_submit_operation(dynamic)
  frame.encode_operation_event([
    frame.Sequenced(
      client_id: Some(sender),
      sequence_number: submitted.client_sequence_number,
      minimum_sequence_number: 0,
      client_sequence_number: submitted.client_sequence_number,
      reference_sequence_number: submitted.reference_sequence_number,
      operation_type: submitted.operation_type,
      contents: submitted.contents,
      metadata: submitted.metadata,
      timestamp: 0,
      data: None,
    ),
  ])
}

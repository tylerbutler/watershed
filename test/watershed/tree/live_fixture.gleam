import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/process
import gleam/json
@target(javascript)
import gleam/list
import gleam/option.{None, Some}
@target(javascript)
import watershed as facade
import watershed/fluid_ids
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam
import watershed/runtime_core
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js
import watershed/tree as tree_api
import watershed/tree/error
import watershed/tree/runtime_fixture
import watershed/tree/schema_builder as builder
import watershed/tree/types
@target(erlang)
import watershed_beam as facade

@target(javascript)
pub fn open(
  document: facade.Document(root),
  compiled: builder.Compiled(a),
) -> Result(tree_api.Tree(a), error.Error) {
  runtime.open_live_tree(facade.runtime_of(document), None, compiled, False)
}

@target(erlang)
pub fn open(
  document: facade.Document(root),
  compiled: builder.Compiled(a),
) -> Result(tree_api.Tree(a), error.Error) {
  runtime_beam.open_live_tree(
    facade.runtime_subject(document),
    None,
    compiled,
    False,
  )
}

@target(javascript)
pub fn inspect(
  document: facade.Document(root),
  marker: json.Json,
  compiled: builder.Compiled(a),
) -> Result(tree_api.Tree(a), error.Error) {
  runtime.open_live_tree(
    facade.runtime_of(document),
    Some(marker),
    compiled,
    True,
  )
}

@target(erlang)
pub fn inspect(
  document: facade.Document(root),
  marker: json.Json,
  compiled: builder.Compiled(a),
) -> Result(tree_api.Tree(a), error.Error) {
  runtime_beam.open_live_tree(
    facade.runtime_subject(document),
    Some(marker),
    compiled,
    True,
  )
}

pub type Card {
  Card(id: builder.Identifier, title: String)
}

pub type CardSchema {
  CardSchema(
    node: builder.Node(Card),
    id: builder.Property(Card, builder.Identifier),
    title: builder.Property(Card, String),
  )
}

pub fn card_schema() -> CardSchema {
  let id = builder.identifier("id", fn(card: Card) { card.id })
  let title =
    builder.required("title", builder.string(), fn(card: Card) { card.title })
  CardSchema(
    builder.object2(builder.factory("typed.test"), "Card", Card, id, title),
    id,
    title,
  )
}

fn seed(
  compiled: builder.Compiled(a),
  initial: a,
) -> runtime_core.BootstrapSeed {
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(seed_input(compiled, initial))
  seed
}

fn seed_input(
  compiled: builder.Compiled(a),
  initial: a,
) -> runtime_core.BootstrapSeedInput {
  let assert Ok(Some(value)) = builder.encode(compiled, initial)
  let assert Ok(input) =
    runtime_fixture.routed_tree_seed_input(
      builder.stored(compiled),
      builder.view(compiled),
      value,
    )
  input
}

pub fn remote_edit(
  compiled: builder.Compiled(a),
  initial: a,
  edit: types.Edit,
) -> frame.Sequenced {
  let input = seed_input(compiled, initial)
  let assert Some(compressor) = input.compressor
  let assert Ok(serialized) = fluid_ids.serialize(compressor, False)
  let assert Ok(session) =
    fluid_ids.session_id("50000000-0000-4000-8000-000000000005")
  let assert Ok(compressor) = fluid_ids.deserialize(serialized, session)
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(..input, compressor: Some(compressor)),
    )
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("typed-peer", [], 0),
      seed,
    )
  let assert Ok(#(_, _, [operation])) =
    runtime_core.submit_tree_edits(core, "A/_C", [edit])
  frame.Sequenced(
    client_id: Some("typed-peer"),
    sequence_number: 1,
    minimum_sequence_number: 0,
    client_sequence_number: operation.client_sequence_number,
    reference_sequence_number: operation.reference_sequence_number,
    operation_type: operation.operation_type,
    contents: operation.contents,
    metadata: operation.metadata,
    timestamp: 0,
    data: None,
    compression: None,
  )
}

pub fn acknowledgement(payload: json.Json) -> frame.Sequenced {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(sender, [[submitted]])) =
    frame.decode_submit_operation(dynamic)
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
    compression: None,
  )
}

fn connected() {
  frame.encode_connected(
    client_id: "typed-reader",
    tenant_id: "default",
    document_id: "tree",
    scopes: ["doc:read", "doc:write"],
    checkpoint_sequence_number: 0,
    initial_clients: ["typed-reader"],
    initial_messages: [],
    timestamp: 0,
    presence_v1: False,
  )
}

@target(javascript)
pub fn capture() -> #(fn(a) -> Nil, fn(Int) -> List(a)) {
  let values = transport_js.new_cell([])
  #(
    fn(value) {
      transport_js.set_cell(values, [value, ..transport_js.get_cell(values)])
    },
    fn(_) {
      let result = list.reverse(transport_js.get_cell(values))
      transport_js.set_cell(values, [])
      result
    },
  )
}

@target(erlang)
pub fn capture() -> #(fn(a) -> Nil, fn(Int) -> List(a)) {
  let values = process.new_subject()
  #(process.send(values, _), fn(count) { receive_values(values, count) })
}

@target(erlang)
fn receive_values(subject: process.Subject(a), count: Int) -> List(a) {
  case count {
    0 -> {
      let assert Error(Nil) = process.receive(subject, 0)
      []
    }
    _ -> {
      let assert Ok(value) = process.receive(subject, 1000)
      [value, ..receive_values(subject, count - 1)]
    }
  }
}

pub fn tree(
  compiled: builder.Compiled(a),
  initial: a,
) -> #(facade.Document(Nil), tree_api.Tree(a)) {
  let #(document, tree, _) = tree_with_operations(compiled, initial)
  #(document, tree)
}

pub fn tree_with_operations(
  compiled: builder.Compiled(a),
  initial: a,
) -> #(facade.Document(Nil), tree_api.Tree(a), fn(List(frame.Sequenced)) -> Nil) {
  tree_with_submissions(compiled, initial, fn(_) { Nil })
}

@target(javascript)
pub fn tree_with_submissions(
  compiled: builder.Compiled(a),
  initial: a,
  on_submit: fn(json.Json) -> Nil,
) -> #(facade.Document(Nil), tree_api.Tree(a), fn(List(frame.Sequenced)) -> Nil) {
  let callbacks = transport_js.new_cell(option.None)
  let document =
    facade.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "typed-reader",
      seed: seed(compiled, initial),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> on_submit(payload)
              _ -> Nil
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
  callbacks.on_event("connect_document_success", connected() |> json.to_string)
  let assert Ok(tree) = open(document, compiled)
  #(document, tree, fn(operations) {
    callbacks.on_event(
      "op",
      frame.encode_operation_event(operations) |> json.to_string,
    )
  })
}

@target(erlang)
pub fn tree_with_submissions(
  compiled: builder.Compiled(a),
  initial: a,
  on_submit: fn(json.Json) -> Nil,
) -> #(facade.Document(Nil), tree_api.Tree(a), fn(List(frame.Sequenced)) -> Nil) {
  let connections = process.new_subject()
  let assert Ok(document) =
    facade.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "typed-reader",
      seed: seed(compiled, initial),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(connections, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(connections, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> on_submit(payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event("connect_document_success", connected())
  let assert Ok(Nil) =
    runtime_beam.await_ready(facade.runtime_subject(document))
  let assert Ok(tree) = open(document, compiled)
  #(document, tree, fn(operations) {
    callbacks.on_event("op", frame.encode_operation_event(operations))
  })
}

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
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/typed
import watershed/tree/types
@target(erlang)
import watershed_beam as facade

pub type NativeRoot

pub fn definition(
  compiled: builder.Compiled(a),
) -> typed.Schema(NativeRoot, types.TreeValue) {
  let assert [identifier, ..] =
    schema.root_field_schema(builder.stored(compiled)).allowed_types
  let assert Ok(root) = typed.node(identifier, fn(value) { Ok(value) })
  let assert Ok(value) = typed.schema(builder.view(compiled), root)
  value
}

pub fn native_cards(
  tree: facade.SharedTree(NativeRoot, types.TreeValue),
) -> facade.TreeArray(Card, types.TreeValue) {
  let assert Ok(Some(root)) = facade.tree_root(tree)
  let assert Ok(item) = typed.node("typed.test.Card", fn(value) { Ok(value) })
  let assert Ok(cards) =
    facade.tree_array(
      root,
      typed.array_field("cards", "typed.test.Cards", item),
    )
  cards
}

pub fn native_card_builder() -> typed.Builder(Card, types.TreeValue) {
  let assert Ok(value) =
    typed.builder("typed.test.Card", fn(value) { Ok(value) })
  value
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
) -> #(facade.Document(Nil), facade.SharedTree(NativeRoot, types.TreeValue)) {
  let #(document, tree, _) = tree_with_operations(compiled, initial)
  #(document, tree)
}

@target(javascript)
pub fn tree_with_operations(
  compiled: builder.Compiled(a),
  initial: a,
) -> #(
  facade.Document(Nil),
  facade.SharedTree(NativeRoot, types.TreeValue),
  fn(List(frame.Sequenced)) -> Nil,
) {
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
          push: fn(_, _) { Nil },
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
  let assert Ok(root) = facade.resolve_root(document)
  let assert Ok(marker) = facade.get(root, "tree")
  let assert Ok(tree) =
    facade.resolve_tree(document, marker, definition(compiled))
  #(document, tree, fn(operations) {
    callbacks.on_event(
      "op",
      frame.encode_operation_event(operations) |> json.to_string,
    )
  })
}

@target(erlang)
pub fn tree_with_operations(
  compiled: builder.Compiled(a),
  initial: a,
) -> #(
  facade.Document(Nil),
  facade.SharedTree(NativeRoot, types.TreeValue),
  fn(List(frame.Sequenced)) -> Nil,
) {
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
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event("connect_document_success", connected())
  let assert Ok(Nil) =
    runtime_beam.await_ready(facade.runtime_subject(document))
  let assert Ok(root) = facade.resolve_root(document)
  let assert Ok(marker) = facade.get(root, "tree")
  let assert Ok(tree) =
    facade.resolve_tree(document, marker, definition(compiled))
  #(document, tree, fn(operations) {
    callbacks.on_event("op", frame.encode_operation_event(operations))
  })
}

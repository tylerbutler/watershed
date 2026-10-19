import gleam/option.{None, Some}
import shared_tree_project_brief_lustre/brief
import shared_tree_project_brief_lustre/schema
import watershed
import watershed/fluid_ids
import watershed/runtime
import watershed/runtime_core
import watershed/sluice/frame
import watershed/transport_js
import watershed/tree
import watershed/tree/schema_builder as builder
import watershed/wire/fluid_document

@external(javascript, "./fixture_ffi.mjs", "stringify")
fn stringify(value: value) -> String

pub type Fixture {
  Fixture(
    document: watershed.Document(Nil),
    tree: tree.Tree(brief.ProjectBrief),
  )
}

pub fn new(initial: brief.ProjectBrief) -> Fixture {
  let declaration = schema.configuration()
  let assert Ok(compiled) = builder.compile(declaration)
  let assert Ok(encoded) = builder.encode_new(compiled, initial)
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(view_id) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(summary) =
    fluid_document.initial_tree(
      builder.stored(compiled),
      encoded,
      session,
      view_id,
    )
  let assert Ok(seed) = runtime_core.document_seed(summary)
  let callbacks = transport_js.new_cell(None)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "project-brief",
      user_id: "reader",
      seed: seed,
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
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "project-brief",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> stringify,
  )
  let assert Ok(tree) = watershed.open_tree(document, declaration)
  Fixture(document:, tree:)
}

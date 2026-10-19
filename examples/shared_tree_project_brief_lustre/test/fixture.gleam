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
  let #(document, callbacks, _) = pending(initial)
  handshake(callbacks, "reader")
  let assert Ok(tree) = watershed.open_tree(document, schema.configuration())
  Fixture(document:, tree:)
}

pub fn pending(
  initial: brief.ProjectBrief,
) -> #(
  watershed.Document(Nil),
  runtime.TransportCallbacks,
  transport_js.Cell(List(#(String, String))),
) {
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
  let submissions = transport_js.new_cell([])
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "project-brief",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            transport_js.set_cell(submissions, [
              #(event, stringify(payload)),
              ..transport_js.get_cell(submissions)
            ])
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
  #(document, callbacks, submissions)
}

pub fn handshake(
  callbacks: runtime.TransportCallbacks,
  session: String,
) -> Nil {
  handshake_at(callbacks, session, 0)
}

pub fn handshake_at(
  callbacks: runtime.TransportCallbacks,
  session: String,
  checkpoint: Int,
) -> Nil {
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: session,
      tenant_id: "default",
      document_id: "project-brief",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: checkpoint,
      initial_clients: [session],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> stringify,
  )
}

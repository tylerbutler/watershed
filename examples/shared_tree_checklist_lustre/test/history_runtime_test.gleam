import gleam/option.{type Option, None, Some}
import gleeunit
import shared_tree_checklist_lustre
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/schema as document_schema
import watershed
import watershed/fluid_ids
import watershed/runtime
import watershed/runtime_core
import watershed/sluice/frame
import watershed/transport_js
import watershed/tree/schema
import watershed/wire/fluid_document

@external(javascript, "./history_runtime_test_ffi.mjs", "stringify")
fn stringify(value: value) -> String

type Fixture(root) {
  Fixture(
    document: watershed.Document(root),
    tree: watershed.SharedTree,
    submissions: transport_js.Cell(Int),
  )
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn complete_all_groups_latest_incomplete_items_into_one_undo_step_test() {
  let fixture =
    fixture([
      #("a", "first", False),
      #("b", "second", False),
    ])
  let handles = transport_js.new_cell([])
  let commits = transport_js.new_cell(0)
  let subscription =
    watershed.subscribe_tree_commits(fixture.tree, fn(event) {
      let assert watershed.TreeCommitEvent(_, True, Some(acquire), _) = event
      let assert Ok(handle) = acquire()
      transport_js.set_cell(handles, [handle, ..transport_js.get_cell(handles)])
      transport_js.set_cell(commits, transport_js.get_cell(commits) + 1)
    })

  let assert Ok(True) =
    watershed.tree_transaction(fixture.tree, [], fn(tree) {
      shared_tree_checklist_lustre.complete_all(tree)
    })
  let assert 1 = transport_js.get_cell(commits)
  let assert 1 = transport_js.get_cell(fixture.submissions)
  let assert Ok(Some(snapshot)) = watershed.tree_get(fixture.tree, [])
  let assert Ok(checklist.Checklist(
    items: [
      checklist.Item("a", "first", True),
      checklist.Item("b", "second", True),
    ],
    ..,
  )) = checklist.decode(snapshot)

  let assert Ok(False) =
    watershed.tree_transaction(fixture.tree, [], fn(tree) {
      shared_tree_checklist_lustre.complete_all(tree)
    })
  let assert 1 = transport_js.get_cell(commits)
  let assert 1 = transport_js.get_cell(fixture.submissions)

  let assert [handle] = transport_js.get_cell(handles)
  let assert Ok(Nil) = watershed.tree_revert(handle, True)
  let assert Ok(Some(restored)) = watershed.tree_get(fixture.tree, [])
  let assert Ok(checklist.Checklist(
    items: [
      checklist.Item("a", "first", False),
      checklist.Item("b", "second", False),
    ],
    ..,
  )) = checklist.decode(restored)

  watershed.unsubscribe(subscription)
  watershed.close(fixture.document)
}

fn fixture(items: List(#(String, String, Bool))) -> Fixture(root) {
  let stored = document_schema.stored()
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(view_id) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(summary) =
    fluid_document.initial_tree(
      stored,
      Some(document_schema.checklist_value(items)),
      session,
      view_id,
    )
  let assert Ok(seed) = runtime_core.document_seed(summary)
  let callbacks: transport_js.Cell(Option(runtime.TransportCallbacks)) =
    transport_js.new_cell(None)
  let submissions = transport_js.new_cell(0)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "checklist",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, _payload) {
            case event {
              "submitOp" ->
                transport_js.set_cell(
                  submissions,
                  transport_js.get_cell(submissions) + 1,
                )
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
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "checklist",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> stringify,
  )
  let assert Ok(root) = watershed.resolve_root(document)
  let assert Ok(marker) = watershed.get(root, "tree")
  let assert Ok(view) =
    schema.view_from_json(schema.stored_to_json(document_schema.stored()))
  let assert Ok(tree) = watershed.resolve_tree(document, marker, view)
  Fixture(document:, tree:, submissions:)
}

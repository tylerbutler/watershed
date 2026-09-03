import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleeunit/should

import watershed
import watershed/component
import watershed/port
import watershed/sluice_js
import watershed/transport_js

import project_room_lustre/checklist
import project_room_lustre/tally_payload

type Root

fn new_subtree(
  name: String,
) -> #(watershed.Document(Root), watershed.SharedMap) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let assert Ok(subtree) = watershed.create_map(document)
  #(document, subtree)
}

fn start(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
) -> checklist.Running {
  let outcome = transport_js.new_cell(None)
  checklist.start(
    document,
    subtree,
    fn() { Nil },
    checklist.Config(title: "Launch"),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

pub fn config_round_trips_test() -> Nil {
  let config = checklist.Config(title: "Launch")
  json.parse(
    json.to_string(checklist.encode_config(config)),
    checklist.config_decoder(),
  )
  |> should.equal(Ok(config))
}

pub fn bootstrap_twice_adopts_the_same_channels_test() -> Nil {
  let #(document, subtree) = new_subtree("checklist-bootstrap")
  let first = start(document, subtree)
  let second = start(document, subtree)
  checklist.items(first) |> should.equal([])
  checklist.items(second) |> should.equal([])
  checklist.stop(first) |> should.equal(Ok(Nil))
  checklist.stop(second) |> should.equal(Ok(Nil))
}

pub fn commands_change_items_and_completion_test() -> Nil {
  let #(document, subtree) = new_subtree("checklist-commands")
  let running = start(document, subtree)
  let #(running, _) = checklist.set_draft(running, "Security review")
  let assert Ok(#(running, [])) = checklist.add(running)
  let assert [item] = checklist.items(running)
  item.label |> should.equal("Security review")

  let assert Ok(#(running, [event])) = checklist.complete(running, item.id)
  component.output_id(event) |> should.equal("item_completed")
  port.decode(tally_payload.add(), component.output_payload(event))
  |> should.equal(Ok(1))
  checklist.completed(running, item.id) |> should.be_true

  let assert Ok(#(running, [])) = checklist.reopen(running, item.id)
  checklist.completed(running, item.id) |> should.be_false
  let assert Ok(#(running, [])) =
    checklist.rename(running, item.id, "Threat model")
  checklist.items(running)
  |> should.equal([checklist.Item(item.id, "Threat model")])
  let assert Ok(#(_, [])) = checklist.remove(running, item.id)
  checklist.items(running) |> should.equal([])
}

pub fn complete_rejects_missing_and_duplicate_items_test() -> Nil {
  let #(document, subtree) = new_subtree("checklist-invalid")
  let running = start(document, subtree)
  checklist.complete(running, "missing")
  |> should.equal(Error("checklist item does not exist"))

  let #(running, _) = checklist.set_draft(running, "   ")
  checklist.add(running) |> result.is_error |> should.be_true

  let #(running, _) = checklist.set_draft(running, "Review")
  let assert Ok(#(running, [])) = checklist.add(running)
  let assert [item] = checklist.items(running)
  let assert Ok(handle) = watershed.get(subtree, "items")
  let assert Ok(sequence) = watershed.resolve_sequence(document, handle)
  let assert [encoded] = watershed.sequence_values(sequence)
  let assert Ok(Nil) = watershed.sequence_insert(sequence, 1, encoded)
  let assert Ok(Nil) =
    watershed.sequence_insert(
      sequence,
      2,
      json.object([
        #("version", json.int(2)),
        #("id", json.string("ignored")),
        #("label", json.string("Ignored")),
      ]),
    )
  checklist.items(running) |> should.equal([item])

  let assert Ok(#(running, [_])) = checklist.complete(running, item.id)
  checklist.complete(running, item.id)
  |> should.equal(Ok(#(running, [])))
  checklist.rename(running, item.id, "   ")
  |> result.is_error
  |> should.be_true
  let assert Ok(#(_, [])) = checklist.remove(running, item.id)
  watershed.sequence_values(sequence)
  |> should.equal([
    json.object([
      #("version", json.int(2)),
      #("id", json.string("ignored")),
      #("label", json.string("Ignored")),
    ]),
  ])
}

pub fn concurrent_complete_and_remove_converge_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "checklist-convergence")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(subtree_a) = watershed.create_map(document_a)
  checklist.initialize(document_a, subtree_a) |> should.equal(Ok(Nil))
  watershed.set(
    watershed.root(document_a),
    "shared",
    watershed.handle_of(subtree_a),
  )
  sluice_js.settle(sluice)
  let assert Ok(handle) = watershed.get(watershed.root(document_b), "shared")
  let assert Ok(subtree_b) = watershed.resolve(document_b, handle)

  let running_a = start(document_a, subtree_a)
  let running_b = start(document_b, subtree_b)
  let #(running_a, _) = checklist.set_draft(running_a, "Security review")
  let assert Ok(#(running_a, [])) = checklist.add(running_a)
  sluice_js.settle(sluice)
  let assert [item] = checklist.items(running_b)

  let assert Ok(#(running_a, [_])) = checklist.complete(running_a, item.id)
  let assert Ok(#(running_b, [])) = checklist.remove(running_b, item.id)
  sluice_js.settle(sluice)

  checklist.items(running_a) |> should.equal([])
  checklist.items(running_b) |> should.equal([])
  checklist.completed(running_a, item.id) |> should.be_true
  checklist.completed(running_b, item.id) |> should.be_true
}

pub fn stop_and_restart_preserves_shared_state_and_clears_draft_test() -> Nil {
  let #(document, subtree) = new_subtree("checklist-restart")
  let running = start(document, subtree)
  let #(running, _) = checklist.set_draft(running, "Security review")
  let assert Ok(#(running, [])) = checklist.add(running)
  let assert [item] = checklist.items(running)
  let assert Ok(#(running, [_])) = checklist.complete(running, item.id)
  let #(running, _) = checklist.set_draft(running, "Local draft")
  checklist.stop(running) |> should.equal(Ok(Nil))

  let restarted = start(document, subtree)
  checklist.items(restarted) |> should.equal([item])
  checklist.completed(restarted, item.id) |> should.be_true
  checklist.draft(restarted) |> should.equal("")
}

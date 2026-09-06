import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleeunit/should

import watershed
import watershed/component
import watershed/sluice_js
import watershed/transport_js

import project_room_lustre/component_event
import project_room_lustre/room_agreement

type Root

fn document(name: String) -> #(sluice_js.Sluice, watershed.Document(Root)) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  #(sluice, document)
}

fn new_subtree(document: watershed.Document(Root)) -> watershed.SharedMap {
  let assert Ok(subtree) = watershed.create_map(document)
  subtree
}

fn attach_subtree(
  sluice: sluice_js.Sluice,
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
) -> Nil {
  watershed.set(
    watershed.root(document),
    "agreement-subtree",
    watershed.handle_of(subtree),
  )
  sluice_js.settle(sluice)
}

fn start(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
  instance_id: String,
  invalidations: transport_js.Cell(Int),
) -> room_agreement.Running {
  let outcome = transport_js.new_cell(None)
  room_agreement.start(
    document,
    subtree,
    instance_id,
    fn() {
      transport_js.set_cell(
        invalidations,
        transport_js.get_cell(invalidations) + 1,
      )
    },
    room_agreement.Config(title: "Working agreement"),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

fn proposal(
  id: String,
  proposer_id: String,
  text: String,
) -> room_agreement.Proposal {
  room_agreement.Proposal(id:, proposer_id:, text:)
}

type ThreeClients {
  ThreeClients(
    sluice: sluice_js.Sluice,
    document_a: watershed.Document(Root),
    document_b: watershed.Document(Root),
    document_c: watershed.Document(Root),
    subtree_a: watershed.SharedMap,
    subtree_b: watershed.SharedMap,
    subtree_c: watershed.SharedMap,
  )
}

fn three_clients(name: String) -> ThreeClients {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  let document_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)
  let subtree_a = new_subtree(document_a)
  room_agreement.initialize(document_a, subtree_a) |> should.equal(Ok(Nil))
  attach_subtree(sluice, document_a, subtree_a)
  let assert Ok(subtree_handle_b) =
    watershed.get(watershed.root(document_b), "agreement-subtree")
  let assert Ok(subtree_handle_c) =
    watershed.get(watershed.root(document_c), "agreement-subtree")
  let assert Ok(subtree_b) = watershed.resolve(document_b, subtree_handle_b)
  let assert Ok(subtree_c) = watershed.resolve(document_c, subtree_handle_c)
  ThreeClients(
    sluice:,
    document_a:,
    document_b:,
    document_c:,
    subtree_a:,
    subtree_b:,
    subtree_c:,
  )
}

fn start_three(
  clients: ThreeClients,
) -> #(room_agreement.Running, room_agreement.Running, room_agreement.Running) {
  #(
    start(
      clients.document_a,
      clients.subtree_a,
      "agreement-a",
      transport_js.new_cell(0),
    ),
    start(
      clients.document_b,
      clients.subtree_b,
      "agreement-b",
      transport_js.new_cell(0),
    ),
    start(
      clients.document_c,
      clients.subtree_c,
      "agreement-c",
      transport_js.new_cell(0),
    ),
  )
}

fn propose_text(
  running: room_agreement.Running,
  text: String,
) -> room_agreement.Running {
  let running = room_agreement.set_draft(running, text)
  let assert Ok(running) = room_agreement.propose(running)
  running
}

fn event_action(event: component.OutputEvent) -> component_event.Event {
  let assert Ok(decoded) =
    json.parse(
      json.to_string(component.output_payload(event)),
      component_event.decoder(),
    )
  decoded
}

pub fn config_round_trips_test() -> Nil {
  let config = room_agreement.Config(title: "Working agreement")
  json.parse(
    json.to_string(room_agreement.encode_config(config)),
    room_agreement.config_decoder(),
  )
  |> should.equal(Ok(config))
}

pub fn proposal_round_trips_test() -> Nil {
  let proposal =
    room_agreement.Proposal(
      id: "proposal-17",
      proposer_id: "client-4",
      text: "Ship on Tuesday",
    )

  json.parse(
    json.to_string(room_agreement.encode_proposal(proposal)),
    room_agreement.proposal_decoder(),
  )
  |> should.equal(Ok(proposal))
}

pub fn proposal_rejects_unknown_or_malformed_json_test() -> Nil {
  [
    "null",
    "17",
    "\"agreement\"",
    "{}",
    "{\"id\":\"proposal-17\",\"proposerId\":\"client-4\"}",
    "{\"id\":17,\"proposerId\":\"client-4\",\"text\":\"Ship\"}",
    "{\"id\":\"proposal-17\",\"proposerId\":4,\"text\":\"Ship\"}",
    "{\"id\":\"proposal-17\",\"proposerId\":\"client-4\",\"text\":false}",
  ]
  |> list.each(fn(encoded) {
    json.parse(encoded, room_agreement.proposal_decoder())
    |> result.is_error
    |> should.be_true
  })
}

pub fn initialize_attaches_empty_pact_map_to_detached_subtree_test() -> Nil {
  let #(_sluice, document) = document("room-agreement-initialize")
  let subtree = new_subtree(document)

  room_agreement.initialize(document, subtree) |> should.equal(Ok(Nil))

  let assert Ok(handle) = watershed.get(subtree, "agreements")
  let assert Ok(pact_map) = watershed.resolve_pact_map(document, handle)
  watershed.pact_map_get(pact_map, "agreement")
  |> should.equal(Error(Nil))
  watershed.pact_map_is_pending(pact_map, "agreement")
  |> should.be_false
}

pub fn start_after_attachment_adopts_existing_handle_and_refreshes_test() -> Nil {
  let #(sluice, document) = document("room-agreement-existing")
  let subtree = new_subtree(document)
  let assert Ok(pact_map) = watershed.create_pact_map(document)
  watershed.set(subtree, "agreements", watershed.pact_map_handle_of(pact_map))
  attach_subtree(sluice, document, subtree)
  let running =
    start(document, subtree, "agreement-1", transport_js.new_cell(0))
  let accepted = proposal("proposal-1", "client-1", "Keep decisions reversible")

  watershed.pact_map_set(
    pact_map,
    "agreement",
    room_agreement.encode_proposal(accepted),
  )
  sluice_js.settle(sluice)
  let #(running, events) = room_agreement.refresh(running)

  events |> should.equal([])
  room_agreement.accepted(running) |> should.equal(Some(accepted))
  room_agreement.pending(running) |> should.equal(None)
  room_agreement.pending_signoffs(running) |> should.equal(0)
  room_agreement.stop(running) |> should.equal(Ok(Nil))
}

pub fn start_is_idempotent_for_one_attached_subtree_test() -> Nil {
  let #(sluice, document) = document("room-agreement-idempotent")
  let subtree = new_subtree(document)
  room_agreement.initialize(document, subtree) |> should.equal(Ok(Nil))
  attach_subtree(sluice, document, subtree)
  let first = start(document, subtree, "agreement-1", transport_js.new_cell(0))
  let second = start(document, subtree, "agreement-2", transport_js.new_cell(0))
  let assert Ok(handle) = watershed.get(subtree, "agreements")
  let assert Ok(pact_map) = watershed.resolve_pact_map(document, handle)
  let accepted = proposal("proposal-2", "client-1", "Write decisions down")

  watershed.pact_map_set(
    pact_map,
    "agreement",
    room_agreement.encode_proposal(accepted),
  )
  sluice_js.settle(sluice)
  let #(first, _) = room_agreement.refresh(first)
  let #(second, _) = room_agreement.refresh(second)

  room_agreement.accepted(first) |> should.equal(Some(accepted))
  room_agreement.accepted(second) |> should.equal(Some(accepted))
  watershed.get(subtree, "agreements") |> should.equal(Ok(handle))
  room_agreement.stop(first) |> should.equal(Ok(Nil))
  room_agreement.stop(second) |> should.equal(Ok(Nil))
}

pub fn replacing_agreements_field_rebinds_and_ignores_old_pact_map_test() -> Nil {
  let #(sluice, document) = document("room-agreement-rebind")
  let subtree = new_subtree(document)
  room_agreement.initialize(document, subtree) |> should.equal(Ok(Nil))
  attach_subtree(sluice, document, subtree)
  let invalidations = transport_js.new_cell(0)
  let running = start(document, subtree, "agreement-1", invalidations)
  let assert Ok(old_handle) = watershed.get(subtree, "agreements")
  let assert Ok(old_pact_map) = watershed.resolve_pact_map(document, old_handle)
  let assert Ok(replacement) = watershed.create_pact_map(document)

  watershed.set(
    subtree,
    "agreements",
    watershed.pact_map_handle_of(replacement),
  )
  let after_rebind = transport_js.get_cell(invalidations)
  let replacement_value =
    proposal("proposal-new", "client-1", "Use the replacement")
  watershed.pact_map_set(
    replacement,
    "agreement",
    room_agreement.encode_proposal(replacement_value),
  )
  sluice_js.settle(sluice)
  let #(running, _) = room_agreement.refresh(running)
  room_agreement.accepted(running) |> should.equal(Some(replacement_value))

  let old_value = proposal("proposal-old", "client-1", "Ignore the old map")
  watershed.pact_map_set(
    old_pact_map,
    "agreement",
    room_agreement.encode_proposal(old_value),
  )
  sluice_js.settle(sluice)
  let #(running, _) = room_agreement.refresh(running)

  room_agreement.accepted(running) |> should.equal(Some(replacement_value))
  transport_js.get_cell(invalidations)
  |> should.equal(after_rebind + 2)
  room_agreement.stop(running) |> should.equal(Ok(Nil))
}

pub fn draft_is_local_state_test() -> Nil {
  let #(sluice, document) = document("room-agreement-draft")
  let subtree = new_subtree(document)
  room_agreement.initialize(document, subtree) |> should.equal(Ok(Nil))
  attach_subtree(sluice, document, subtree)
  let running =
    start(document, subtree, "agreement-1", transport_js.new_cell(0))

  room_agreement.draft(running) |> should.equal("")
  let running = room_agreement.set_draft(running, "Prefer small changes")
  room_agreement.draft(running) |> should.equal("Prefer small changes")
  room_agreement.stop(running) |> should.equal(Ok(Nil))
}

pub fn stop_unsubscribes_pact_map_and_subtree_once_test() -> Nil {
  let #(sluice, document) = document("room-agreement-stop")
  let subtree = new_subtree(document)
  room_agreement.initialize(document, subtree) |> should.equal(Ok(Nil))
  attach_subtree(sluice, document, subtree)
  let invalidations = transport_js.new_cell(0)
  let running = start(document, subtree, "agreement-1", invalidations)
  let assert Ok(handle) = watershed.get(subtree, "agreements")
  let assert Ok(pact_map) = watershed.resolve_pact_map(document, handle)
  room_agreement.stop(running) |> should.equal(Ok(Nil))
  room_agreement.stop(running) |> should.equal(Ok(Nil))
  let after_stop = transport_js.get_cell(invalidations)

  watershed.pact_map_set(
    pact_map,
    "agreement",
    room_agreement.encode_proposal(proposal(
      "proposal-late",
      "client-1",
      "Late value",
    )),
  )
  let assert Ok(replacement) = watershed.create_pact_map(document)
  watershed.set(
    subtree,
    "agreements",
    watershed.pact_map_handle_of(replacement),
  )
  sluice_js.settle(sluice)

  transport_js.get_cell(invalidations) |> should.equal(after_stop)
}

pub fn malformed_stored_values_are_omitted_from_effective_state_test() -> Nil {
  let #(sluice, document) = document("room-agreement-malformed")
  let subtree = new_subtree(document)
  room_agreement.initialize(document, subtree) |> should.equal(Ok(Nil))
  attach_subtree(sluice, document, subtree)
  let running =
    start(document, subtree, "agreement-1", transport_js.new_cell(0))
  let assert Ok(handle) = watershed.get(subtree, "agreements")
  let assert Ok(pact_map) = watershed.resolve_pact_map(document, handle)

  watershed.pact_map_set(
    pact_map,
    "agreement",
    json.object([#("unknown", json.string("value"))]),
  )
  sluice_js.settle(sluice)
  let #(running, events) = room_agreement.refresh(running)

  events |> should.equal([])
  room_agreement.accepted(running) |> should.equal(None)
  room_agreement.pending(running) |> should.equal(None)
  room_agreement.stop(running) |> should.equal(Ok(Nil))
}

pub fn accepted_stays_stable_until_paused_client_resumes_test() -> Nil {
  let clients = three_clients("room-agreement-resume")
  let #(running_a, running_b, running_c) = start_three(clients)
  let assert Some(client_a) = watershed.client_id(clients.document_a)
  let first = proposal("proposal-first", client_a, "Write decisions down")
  let assert Ok(handle) = watershed.get(clients.subtree_a, "agreements")
  let assert Ok(pact_map) =
    watershed.resolve_pact_map(clients.document_a, handle)
  watershed.pact_map_set(
    pact_map,
    "agreement",
    room_agreement.encode_proposal(first),
  )
  sluice_js.settle(clients.sluice)
  let #(running_a, _) = room_agreement.refresh(running_a)

  sluice_js.pause(clients.sluice, clients.document_c)
  let running_a = propose_text(running_a, "Prefer reversible decisions")
  sluice_js.settle(clients.sluice)
  let #(running_a, _) = room_agreement.refresh(running_a)
  let #(running_b, _) = room_agreement.refresh(running_b)
  let assert Some(waiting) = room_agreement.pending(running_a)

  room_agreement.accepted(running_a) |> should.equal(Some(first))
  room_agreement.accepted(running_b) |> should.equal(Some(first))
  waiting.text |> should.equal("Prefer reversible decisions")
  waiting.proposer_id |> should.equal(client_a)
  { waiting.id == first.id } |> should.be_false
  room_agreement.pending_signoffs(running_a) |> should.equal(1)
  room_agreement.pending_signoffs(running_b) |> should.equal(1)

  sluice_js.resume(clients.sluice, clients.document_c)
  sluice_js.settle(clients.sluice)
  let #(running_a, _) = room_agreement.refresh(running_a)
  let #(running_b, _) = room_agreement.refresh(running_b)
  let #(running_c, _) = room_agreement.refresh(running_c)

  room_agreement.accepted(running_a) |> should.equal(Some(waiting))
  room_agreement.accepted(running_b) |> should.equal(Some(waiting))
  room_agreement.accepted(running_c) |> should.equal(Some(waiting))
  room_agreement.pending(running_a) |> should.equal(None)
  room_agreement.pending_signoffs(running_a) |> should.equal(0)
  room_agreement.stop(running_a) |> should.equal(Ok(Nil))
  room_agreement.stop(running_b) |> should.equal(Ok(Nil))
  room_agreement.stop(running_c) |> should.equal(Ok(Nil))
}

pub fn outstanding_client_leave_settles_pending_proposal_test() -> Nil {
  let clients = three_clients("room-agreement-leave")
  let #(running_a, running_b, running_c) = start_three(clients)
  sluice_js.pause(clients.sluice, clients.document_c)
  let running_a = propose_text(running_a, "Keep meetings short")
  sluice_js.settle(clients.sluice)
  let #(running_a, _) = room_agreement.refresh(running_a)
  let assert Some(waiting) = room_agreement.pending(running_a)
  room_agreement.pending_signoffs(running_a) |> should.equal(1)

  sluice_js.disconnect(clients.sluice, clients.document_c)
  sluice_js.settle(clients.sluice)
  let #(running_a, _) = room_agreement.refresh(running_a)
  let #(running_b, _) = room_agreement.refresh(running_b)

  room_agreement.accepted(running_a) |> should.equal(Some(waiting))
  room_agreement.accepted(running_b) |> should.equal(Some(waiting))
  room_agreement.pending(running_a) |> should.equal(None)
  room_agreement.stop(running_a) |> should.equal(Ok(Nil))
  room_agreement.stop(running_b) |> should.equal(Ok(Nil))
  room_agreement.stop(running_c) |> should.equal(Ok(Nil))
}

pub fn competing_proposal_loses_to_first_sequenced_and_clears_local_state_test() -> Nil {
  let clients = three_clients("room-agreement-competing")
  let #(running_a, running_b, running_c) = start_three(clients)
  sluice_js.pause(clients.sluice, clients.document_c)
  let running_a = propose_text(running_a, "First proposal")
  let running_b = propose_text(running_b, "Competing proposal")

  sluice_js.settle(clients.sluice)
  let #(running_a, _) = room_agreement.refresh(running_a)
  let #(running_b, _) = room_agreement.refresh(running_b)
  let assert Some(first_pending) = room_agreement.pending(running_a)
  let assert Some(client_a) = watershed.client_id(clients.document_a)

  room_agreement.pending(running_b) |> should.equal(Some(first_pending))
  first_pending.text |> should.equal("First proposal")
  first_pending.proposer_id |> should.equal(client_a)
  room_agreement.set_draft(running_b, "Blocked while visible")
  |> room_agreement.propose
  |> result.is_error
  |> should.be_true

  sluice_js.resume(clients.sluice, clients.document_c)
  sluice_js.settle(clients.sluice)
  let #(running_a, _) = room_agreement.refresh(running_a)
  let #(running_b, _) = room_agreement.refresh(running_b)
  let #(running_c, _) = room_agreement.refresh(running_c)

  room_agreement.accepted(running_a) |> should.equal(Some(first_pending))
  room_agreement.accepted(running_b) |> should.equal(Some(first_pending))
  room_agreement.set_draft(running_b, "Next proposal")
  |> room_agreement.propose
  |> result.is_ok
  |> should.be_true
  room_agreement.stop(running_a) |> should.equal(Ok(Nil))
  room_agreement.stop(running_b) |> should.equal(Ok(Nil))
  room_agreement.stop(running_c) |> should.equal(Ok(Nil))
}

pub fn blank_and_visible_pending_proposals_are_rejected_test() -> Nil {
  let clients = three_clients("room-agreement-reject")
  let #(running_a, running_b, running_c) = start_three(clients)

  room_agreement.set_draft(running_a, "   ")
  |> room_agreement.propose
  |> result.is_error
  |> should.be_true

  sluice_js.pause(clients.sluice, clients.document_c)
  let running_a = propose_text(running_a, "Visible pending proposal")
  sluice_js.settle(clients.sluice)
  let #(running_b, _) = room_agreement.refresh(running_b)

  room_agreement.set_draft(running_b, "Must wait")
  |> room_agreement.propose
  |> result.is_error
  |> should.be_true
  room_agreement.stop(running_a) |> should.equal(Ok(Nil))
  room_agreement.stop(running_b) |> should.equal(Ok(Nil))
  room_agreement.stop(running_c) |> should.equal(Ok(Nil))
}

pub fn late_joiner_reads_accepted_value_without_phantom_pending_test() -> Nil {
  let clients = three_clients("room-agreement-late-join")
  let #(running_a, running_b, running_c) = start_three(clients)
  let running_a = propose_text(running_a, "Document important decisions")
  sluice_js.settle(clients.sluice)
  let #(running_a, _) = room_agreement.refresh(running_a)
  let assert Some(accepted) = room_agreement.accepted(running_a)

  let document_d = sluice_js.connect(clients.sluice, "user-d")
  sluice_js.settle(clients.sluice)
  let assert Ok(subtree_handle) =
    watershed.get(watershed.root(document_d), "agreement-subtree")
  let assert Ok(subtree_d) = watershed.resolve(document_d, subtree_handle)
  let running_d =
    start(document_d, subtree_d, "agreement-d", transport_js.new_cell(0))
  let #(running_d, events) = room_agreement.refresh(running_d)

  events |> should.equal([])
  room_agreement.accepted(running_d) |> should.equal(Some(accepted))
  room_agreement.pending(running_d) |> should.equal(None)
  room_agreement.pending_signoffs(running_d) |> should.equal(0)
  room_agreement.stop(running_a) |> should.equal(Ok(Nil))
  room_agreement.stop(running_b) |> should.equal(Ok(Nil))
  room_agreement.stop(running_c) |> should.equal(Ok(Nil))
  room_agreement.stop(running_d) |> should.equal(Ok(Nil))
}

pub fn only_matching_winning_proposer_emits_acceptance_once_test() -> Nil {
  let clients = three_clients("room-agreement-emission")
  let #(running_a, running_b, running_c) = start_three(clients)
  sluice_js.pause(clients.sluice, clients.document_c)
  let running_a = propose_text(running_a, "First proposal")
  let running_b = propose_text(running_b, "Competing proposal")
  sluice_js.settle(clients.sluice)
  let #(running_a, pending_events_a) = room_agreement.refresh(running_a)
  let #(running_b, pending_events_b) = room_agreement.refresh(running_b)
  let assert Some(winner) = room_agreement.pending(running_a)

  pending_events_a |> should.equal([])
  pending_events_b |> should.equal([])
  room_agreement.pending(running_b) |> should.equal(Some(winner))

  sluice_js.resume(clients.sluice, clients.document_c)
  sluice_js.settle(clients.sluice)
  let #(running_b, losing_events) = room_agreement.refresh(running_b)
  let #(running_c, replicated_events) = room_agreement.refresh(running_c)
  let assert #(running_a, [accepted_event]) = room_agreement.refresh(running_a)

  losing_events |> should.equal([])
  replicated_events |> should.equal([])
  event_action(accepted_event)
  |> should.equal(component_event.Event(
    source_instance_id: "agreement-a",
    source_kind: "project-room/room-agreement",
    source_title: "Working agreement",
    action: component_event.AgreementAccepted,
    detail: "Accepted agreement: First proposal",
  ))
  room_agreement.accepted(running_a) |> should.equal(Some(winner))
  let #(running_a, repeated_events) = room_agreement.refresh(running_a)
  repeated_events |> should.equal([])
  let #(running_b, repeated_peer_events) = room_agreement.refresh(running_b)
  repeated_peer_events |> should.equal([])
  room_agreement.stop(running_a) |> should.equal(Ok(Nil))
  room_agreement.stop(running_b) |> should.equal(Ok(Nil))
  room_agreement.stop(running_c) |> should.equal(Ok(Nil))
}

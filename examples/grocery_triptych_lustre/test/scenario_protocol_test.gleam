import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

import scenario_protocol

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn invitation_round_trip_accepts_stripped_outer_type_test() {
  let inbound =
    scenario_protocol.decode(
      None,
      to_dynamic(invitation_payload()),
      Some("peer-1"),
    )

  inbound
  |> should.equal(
    Some(scenario_protocol.Inbound(
      from_peer: "peer-1",
      message: scenario_protocol.Invitation("run-1"),
    )),
  )
}

pub fn status_round_trip_accepts_matching_outer_type_test() {
  let inbound =
    scenario_protocol.decode(
      Some(scenario_protocol.ripple_type),
      to_dynamic(status_payload()),
      Some("peer-1"),
    )

  inbound
  |> should.equal(
    Some(scenario_protocol.Inbound(
      from_peer: "peer-1",
      message: scenario_protocol.Status(
        run_id: "run-2",
        target_peer: "peer-2",
        status: scenario_protocol.VerifiedExpectedOutcome,
      ),
    )),
  )
}

pub fn mismatching_outer_type_is_dropped_test() {
  scenario_protocol.decode(
    Some("presence"),
    to_dynamic(invitation_payload()),
    Some("peer-1"),
  )
  |> should.equal(None)
}

pub fn missing_or_foreign_content_kind_is_dropped_test() {
  [
    scenario_protocol.decode(
      Some(scenario_protocol.ripple_type),
      to_dynamic(invitation_payload_without_kind()),
      Some("peer-1"),
    ),
    scenario_protocol.decode(
      None,
      to_dynamic(invitation_payload_without_kind()),
      Some("peer-1"),
    ),
    scenario_protocol.decode(
      Some(scenario_protocol.ripple_type),
      to_dynamic(invitation_payload_with_kind("presence")),
      Some("peer-1"),
    ),
    scenario_protocol.decode(
      None,
      to_dynamic(invitation_payload_with_kind("presence")),
      Some("peer-1"),
    ),
  ]
  |> should.equal([None, None, None, None])
}

pub fn sender_client_id_and_phase_fields_are_required_test() {
  [
    scenario_protocol.decode(None, to_dynamic(invitation_payload()), None),
    scenario_protocol.decode(
      None,
      to_dynamic(invitation_payload_with_run_id("")),
      Some("peer-1"),
    ),
    scenario_protocol.decode(
      None,
      to_dynamic(go_payload_without_target_peer()),
      Some("peer-1"),
    ),
    scenario_protocol.decode(None, to_dynamic(go_payload("")), Some("peer-1")),
    scenario_protocol.decode(
      None,
      to_dynamic(status_payload_with_status("bogus")),
      Some("peer-1"),
    ),
  ]
  |> should.equal([None, None, None, None, None])
}

pub fn should_acknowledge_requires_ready_idle_foreign_invitation_test() {
  let invite = inbound("peer-1", scenario_protocol.Invitation("run-1"))

  scenario_protocol.should_acknowledge("self", True, False, False, invite)
  |> should.equal(True)

  scenario_protocol.should_acknowledge("self", False, False, False, invite)
  |> should.equal(False)

  scenario_protocol.should_acknowledge("self", True, True, False, invite)
  |> should.equal(False)

  scenario_protocol.should_acknowledge("peer-1", True, False, False, invite)
  |> should.equal(False)

  scenario_protocol.should_acknowledge("self", True, False, True, invite)
  |> should.equal(False)
}

pub fn run_id_filtering_and_first_ack_selection_test() {
  let ack = inbound("peer-2", scenario_protocol.Acknowledgement("run-1"))
  let other = inbound("peer-3", scenario_protocol.Acknowledgement("run-2"))

  scenario_protocol.matches_run("run-1", ack)
  |> should.equal(True)

  scenario_protocol.matches_run("run-1", other)
  |> should.equal(False)

  scenario_protocol.select_first_ack("self", "run-1", None, ack)
  |> should.equal(Some("peer-2"))

  scenario_protocol.select_first_ack(
    "self",
    "run-1",
    Some("peer-2"),
    inbound("peer-4", scenario_protocol.Acknowledgement("run-1")),
  )
  |> should.equal(None)
}

pub fn go_requires_the_selected_target_and_initiator_test() {
  let go_self = inbound("initiator", scenario_protocol.Go("run-1", "peer-a"))
  let go_other = inbound("initiator", scenario_protocol.Go("run-1", "peer-b"))
  let go_wrong_sender =
    inbound("intruder", scenario_protocol.Go("run-1", "peer-a"))

  scenario_protocol.classify_go("peer-a", "run-1", "initiator", False, go_self)
  |> should.equal(scenario_protocol.ApplyGo)

  scenario_protocol.classify_go("peer-a", "run-1", "initiator", True, go_self)
  |> should.equal(scenario_protocol.Ignore)

  scenario_protocol.classify_go("peer-a", "run-1", "initiator", False, go_other)
  |> should.equal(scenario_protocol.Ignore)

  scenario_protocol.classify_go(
    "peer-a",
    "run-1",
    "initiator",
    False,
    go_wrong_sender,
  )
  |> should.equal(scenario_protocol.Ignore)
}

pub fn targeted_status_requires_the_expected_sender_test() {
  let status =
    inbound(
      "selected-peer",
      scenario_protocol.Status(
        run_id: "run-1",
        target_peer: "peer-a",
        status: scenario_protocol.VerificationTimedOut,
      ),
    )

  scenario_protocol.should_accept_status(
    "peer-a",
    "run-1",
    "selected-peer",
    status,
  )
  |> should.equal(Some(scenario_protocol.VerificationTimedOut))

  scenario_protocol.should_accept_status(
    "peer-b",
    "run-1",
    "selected-peer",
    status,
  )
  |> should.equal(None)

  scenario_protocol.should_accept_status("peer-a", "run-1", "intruder", status)
  |> should.equal(None)
}

fn inbound(
  from_peer: String,
  message: scenario_protocol.Message,
) -> scenario_protocol.Inbound {
  scenario_protocol.Inbound(from_peer:, message:)
}

fn to_dynamic(payload: json.Json) -> Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  dynamic
}

fn invitation_payload() -> json.Json {
  scenario_protocol.encode(scenario_protocol.Invitation("run-1"))
}

fn invitation_payload_with_run_id(run_id: String) -> json.Json {
  json.object([
    #("kind", json.string(scenario_protocol.ripple_type)),
    #("phase", json.string("invitation")),
    #("run_id", json.string(run_id)),
  ])
}

fn invitation_payload_without_kind() -> json.Json {
  json.object([
    #("phase", json.string("invitation")),
    #("run_id", json.string("run-1")),
  ])
}

fn invitation_payload_with_kind(kind: String) -> json.Json {
  json.object([
    #("kind", json.string(kind)),
    #("phase", json.string("invitation")),
    #("run_id", json.string("run-1")),
  ])
}

fn go_payload(target_peer: String) -> json.Json {
  json.object([
    #("kind", json.string(scenario_protocol.ripple_type)),
    #("phase", json.string("go")),
    #("run_id", json.string("run-1")),
    #("target_peer", json.string(target_peer)),
  ])
}

fn go_payload_without_target_peer() -> json.Json {
  json.object([
    #("kind", json.string(scenario_protocol.ripple_type)),
    #("phase", json.string("go")),
    #("run_id", json.string("run-1")),
  ])
}

fn status_payload() -> json.Json {
  scenario_protocol.encode(scenario_protocol.Status(
    run_id: "run-2",
    target_peer: "peer-2",
    status: scenario_protocol.VerifiedExpectedOutcome,
  ))
}

fn status_payload_with_status(status: String) -> json.Json {
  json.object([
    #("kind", json.string(scenario_protocol.ripple_type)),
    #("phase", json.string("status")),
    #("run_id", json.string("run-1")),
    #("target_peer", json.string("peer-2")),
    #("status", json.string(status)),
  ])
}

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

pub fn invitation_round_trip_test() {
  let inbound =
    scenario_protocol.decode(
      Some(scenario_protocol.ripple_type),
      to_dynamic(
        scenario_protocol.encode(scenario_protocol.Invitation("run-1")),
      ),
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

pub fn status_round_trip_test() {
  let inbound =
    scenario_protocol.decode(
      Some(scenario_protocol.ripple_type),
      to_dynamic(
        scenario_protocol.encode(scenario_protocol.Status(
          run_id: "run-2",
          target_peer: "peer-2",
          status: scenario_protocol.VerifiedExpectedOutcome,
        )),
      ),
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

pub fn foreign_and_malformed_messages_are_dropped_test() {
  scenario_protocol.decode(
    Some("presence"),
    to_dynamic(json.object([#("phase", json.string("invitation"))])),
    Some("peer-1"),
  )
  |> should.equal(None)

  scenario_protocol.decode(
    Some(scenario_protocol.ripple_type),
    to_dynamic(json.object([#("phase", json.string("go"))])),
    Some("peer-1"),
  )
  |> should.equal(None)
}

pub fn should_acknowledge_requires_ready_idle_foreign_invitation_test() {
  let invite = inbound("peer-1", scenario_protocol.Invitation("run-1"))

  scenario_protocol.should_acknowledge("self", True, False, invite)
  |> should.equal(True)

  scenario_protocol.should_acknowledge("self", False, False, invite)
  |> should.equal(False)

  scenario_protocol.should_acknowledge("self", True, True, invite)
  |> should.equal(False)

  scenario_protocol.should_acknowledge("peer-1", True, False, invite)
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

pub fn duplicate_and_targeted_go_behavior_test() {
  let go_self = inbound("initiator", scenario_protocol.Go("run-1", "peer-a"))
  let go_other = inbound("initiator", scenario_protocol.Go("run-1", "peer-b"))

  scenario_protocol.classify_go("peer-a", "run-1", False, go_self)
  |> should.equal(scenario_protocol.ApplyGo)

  scenario_protocol.classify_go("peer-a", "run-1", True, go_self)
  |> should.equal(scenario_protocol.Ignore)

  scenario_protocol.classify_go("peer-a", "run-1", False, go_other)
  |> should.equal(scenario_protocol.StandDown)
}

pub fn targeted_status_only_reaches_the_named_peer_test() {
  let status =
    inbound(
      "initiator",
      scenario_protocol.Status(
        run_id: "run-1",
        target_peer: "peer-a",
        status: scenario_protocol.VerificationTimedOut,
      ),
    )

  scenario_protocol.should_accept_status("peer-a", "run-1", status)
  |> should.equal(Some(scenario_protocol.VerificationTimedOut))

  scenario_protocol.should_accept_status("peer-b", "run-1", status)
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

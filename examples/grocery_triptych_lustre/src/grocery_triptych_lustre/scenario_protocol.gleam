import gleam/dynamic/decode as dyn_decode
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub const ripple_type = "grocery-triptych-scenario"

pub type Status {
  PeerAppliedAdd
  VerifiedExpectedOutcome
  VerificationTimedOut
}

pub type Message {
  Invitation(run_id: String)
  Acknowledgement(run_id: String)
  Go(run_id: String, target_peer: String)
  Status(run_id: String, target_peer: String, status: Status)
}

pub type Inbound {
  Inbound(from_peer: String, message: Message)
}

pub type GoDecision {
  ApplyGo
  Ignore
}

pub fn encode(message: Message) -> Json {
  case message {
    Invitation(run_id) ->
      encode_envelope([
        #("phase", json.string("invitation")),
        #("run_id", json.string(run_id)),
      ])

    Acknowledgement(run_id) ->
      encode_envelope([
        #("phase", json.string("acknowledgement")),
        #("run_id", json.string(run_id)),
      ])

    Go(run_id, target_peer) ->
      encode_envelope([
        #("phase", json.string("go")),
        #("run_id", json.string(run_id)),
        #("target_peer", json.string(target_peer)),
      ])

    Status(run_id, target_peer, status) ->
      encode_envelope([
        #("phase", json.string("status")),
        #("run_id", json.string(run_id)),
        #("target_peer", json.string(target_peer)),
        #("status", json.string(status_to_string(status))),
      ])
  }
}

pub fn decode(
  signal_type: Option(String),
  content: Json,
  sender: Option(String),
) -> Result(Inbound, Nil) {
  case sender {
    Some(from_peer) ->
      case advisory_signal_type_ok(signal_type) {
        True ->
          case json.parse(json.to_string(content), envelope_decoder()) {
            Ok(message) -> Ok(Inbound(from_peer:, message:))
            Error(_) -> Error(Nil)
          }

        False -> Error(Nil)
      }

    None -> Error(Nil)
  }
}

pub fn run_id(message: Message) -> String {
  case message {
    Invitation(run_id) -> run_id
    Acknowledgement(run_id) -> run_id
    Go(run_id, _) -> run_id
    Status(run_id, _, _) -> run_id
  }
}

// docs:snippet-start practice-protocol-matches-run
pub fn matches_run(expected_run_id: String, inbound: Inbound) -> Bool {
  run_id(inbound.message) == expected_run_id
}

// docs:snippet-end practice-protocol-matches-run

// docs:snippet-start practice-protocol-from-self
pub fn from_self(self_id: String, inbound: Inbound) -> Bool {
  inbound.from_peer == self_id
}

// docs:snippet-end practice-protocol-from-self

// docs:snippet-start practice-protocol-should-acknowledge
pub fn should_acknowledge(
  self_id: String,
  ready: Bool,
  busy: Bool,
  already_seen: Bool,
  inbound: Inbound,
) -> Bool {
  case inbound.message {
    Invitation(_) ->
      ready && !busy && !already_seen && !from_self(self_id, inbound)
    Acknowledgement(_) -> False
    Go(_, _) -> False
    Status(_, _, _) -> False
  }
}

// docs:snippet-end practice-protocol-should-acknowledge

pub fn select_first_ack(
  self_id: String,
  run_id: String,
  selected_peer: Option(String),
  inbound: Inbound,
) -> Result(String, Nil) {
  case selected_peer {
    None ->
      case inbound.message {
        Acknowledgement(inbound_run) ->
          case inbound_run == run_id && !from_self(self_id, inbound) {
            True -> Ok(inbound.from_peer)
            False -> Error(Nil)
          }

        Invitation(_) -> Error(Nil)
        Go(_, _) -> Error(Nil)
        Status(_, _, _) -> Error(Nil)
      }

    Some(_) -> Error(Nil)
  }
}

pub fn classify_go(
  self_id: String,
  run_id: String,
  expected_sender: String,
  already_started: Bool,
  inbound: Inbound,
) -> GoDecision {
  case inbound.message {
    Go(inbound_run, target_peer) ->
      case
        inbound_run == run_id
        && target_peer == self_id
        && inbound.from_peer == expected_sender
        && !from_self(self_id, inbound)
      {
        True ->
          case already_started {
            False -> ApplyGo
            True -> Ignore
          }

        False -> Ignore
      }

    Invitation(_) -> Ignore
    Acknowledgement(_) -> Ignore
    Status(_, _, _) -> Ignore
  }
}

pub fn should_accept_status(
  self_id: String,
  run_id: String,
  expected_sender: String,
  inbound: Inbound,
) -> Option(Status) {
  case inbound.message {
    Status(inbound_run, target_peer, status) ->
      case
        inbound_run == run_id
        && target_peer == self_id
        && inbound.from_peer == expected_sender
        && !from_self(self_id, inbound)
      {
        True -> Some(status)
        False -> None
      }

    Invitation(_) -> None
    Acknowledgement(_) -> None
    Go(_, _) -> None
  }
}

pub fn status_to_string(status: Status) -> String {
  case status {
    PeerAppliedAdd -> "peer-applied-add"
    VerifiedExpectedOutcome -> "verified-expected-outcome"
    VerificationTimedOut -> "verification-timed-out"
  }
}

fn encode_envelope(fields: List(#(String, Json))) -> Json {
  json.object([#("kind", json.string(ripple_type)), ..fields])
}

fn advisory_signal_type_ok(signal_type: Option(String)) -> Bool {
  case signal_type {
    Some(kind) -> kind == ripple_type
    None -> True
  }
}

fn envelope_decoder() -> dyn_decode.Decoder(Message) {
  use kind <- dyn_decode.field("kind", non_empty_string("kind"))
  use message <- dyn_decode.then(message_decoder())
  case kind == ripple_type {
    True -> dyn_decode.success(message)
    False -> dyn_decode.failure(message, "ScenarioEnvelope")
  }
}

fn message_decoder() -> dyn_decode.Decoder(Message) {
  use phase <- dyn_decode.field("phase", non_empty_string("phase"))
  use run_id <- dyn_decode.field("run_id", non_empty_string("run_id"))

  case phase {
    "invitation" -> dyn_decode.success(Invitation(run_id))
    "acknowledgement" -> dyn_decode.success(Acknowledgement(run_id))
    "go" -> {
      use target_peer <- dyn_decode.field(
        "target_peer",
        non_empty_string("target_peer"),
      )
      dyn_decode.success(Go(run_id, target_peer))
    }
    "status" -> {
      use target_peer <- dyn_decode.field(
        "target_peer",
        non_empty_string("target_peer"),
      )
      use status <- dyn_decode.field("status", status_decoder())
      dyn_decode.success(Status(run_id, target_peer, status))
    }
    _ -> dyn_decode.failure(Invitation(""), "ScenarioMessage")
  }
}

fn status_decoder() -> dyn_decode.Decoder(Status) {
  non_empty_string("status")
  |> dyn_decode.then(fn(raw) {
    case raw {
      "peer-applied-add" -> dyn_decode.success(PeerAppliedAdd)
      "verified-expected-outcome" -> dyn_decode.success(VerifiedExpectedOutcome)
      "verification-timed-out" -> dyn_decode.success(VerificationTimedOut)
      _ -> dyn_decode.failure(PeerAppliedAdd, "ScenarioStatus")
    }
  })
}

fn non_empty_string(name: String) -> dyn_decode.Decoder(String) {
  dyn_decode.string
  |> dyn_decode.then(fn(value) {
    case value == "" {
      True -> dyn_decode.failure("", name)
      False -> dyn_decode.success(value)
    }
  })
}

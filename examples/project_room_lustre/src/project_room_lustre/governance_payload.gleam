//// Governance payloads and typed ports for the project room components.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

import watershed/port

/// A participant identity supplied by the host application.
pub type Identity {
  Identity(id: String, label: String)
}

/// A change to one participant's approval.
pub type VoteChanged {
  VoteChanged(
    choice_id: String,
    choice_label: String,
    participant_id: String,
    approved: Bool,
  )
}

/// The first accepted threshold crossing for a poll choice.
pub type ThresholdReached {
  ThresholdReached(
    choice_id: String,
    choice_label: String,
    approvals: Int,
    threshold: Int,
  )
}

/// A local results-panel command.
pub type ResultsCommand {
  ShowResults
  HideResults
}

/// A collaborative poll lifecycle command.
pub type PollLifecycleCommand {
  OpenPoll
  ClosePoll
}

/// An ownership operation submitted by the local participant.
pub type SlotOperation {
  ClaimSlot
  ReleaseSlot
  HandoffSlot(target: Identity)
}

/// A command for one ownership slot.
pub type SlotCommand {
  SlotCommand(slot_id: String, operation: SlotOperation)
}

/// A submitted ownership attempt.
pub type ClaimAttempted {
  ClaimAttempted(slot_id: String, operation: SlotOperation)
}

/// The outcome of an ownership attempt.
pub type Resolution {
  Accepted
  Lost
  Aborted
}

/// A resolved ownership attempt.
pub type ClaimResolved {
  ClaimResolved(
    slot_id: String,
    operation: SlotOperation,
    resolution: Resolution,
    owner: Option(Identity),
  )
}

/// An accepted ownership change.
pub type OwnershipChanged {
  OwnershipChanged(
    slot_id: String,
    slot_label: String,
    previous_owner: Option(Identity),
    owner: Option(Identity),
  )
}

pub const vote_changed_schema_id = "project-room/vote-changed@1"

pub const threshold_reached_schema_id = "project-room/threshold-reached@1"

pub const results_command_schema_id = "project-room/results-command@1"

pub const poll_lifecycle_schema_id = "project-room/poll-lifecycle@1"

pub const slot_command_schema_id = "project-room/slot-command@1"

pub const claim_attempted_schema_id = "project-room/claim-attempted@1"

pub const claim_resolved_schema_id = "project-room/claim-resolved@1"

pub const ownership_changed_schema_id = "project-room/ownership-changed@1"

pub const vote_changed_port_id = "vote_changed"

pub const threshold_reached_port_id = "threshold_reached"

pub const show_results_port_id = "show_results"

pub const open_poll_port_id = "open_poll"

pub const close_poll_port_id = "close_poll"

pub const claim_slot_port_id = "claim_slot"

pub const release_slot_port_id = "release_slot"

pub const handoff_slot_port_id = "handoff_slot"

pub const reveal_owner_port_id = "reveal_owner"

pub const claim_attempted_port_id = "claim_attempted"

pub const claim_resolved_port_id = "claim_resolved"

pub const ownership_changed_port_id = "ownership_changed"

pub const append_poll_threshold_port_id = "append_poll_threshold"

pub const append_ownership_change_port_id = "append_ownership_change"

pub fn encode_identity(identity: Identity) -> Json {
  json.object([
    #("id", json.string(identity.id)),
    #("label", json.string(identity.label)),
  ])
}

pub fn identity_decoder() -> Decoder(Identity) {
  use id <- decode.field("id", decode.string)
  use label <- decode.field("label", decode.string)
  decode.success(Identity(id:, label:))
}

pub fn encode_vote_changed(value: VoteChanged) -> Json {
  json.object([
    #("type", json.string("vote_changed")),
    #("choiceId", json.string(value.choice_id)),
    #("choiceLabel", json.string(value.choice_label)),
    #("participantId", json.string(value.participant_id)),
    #("approved", json.bool(value.approved)),
  ])
}

pub fn vote_changed_decoder() -> Decoder(VoteChanged) {
  use tag <- decode.field("type", decode.string)
  use choice_id <- decode.field("choiceId", decode.string)
  use choice_label <- decode.field("choiceLabel", decode.string)
  use participant_id <- decode.field("participantId", decode.string)
  use approved <- decode.field("approved", decode.bool)
  case tag {
    "vote_changed" ->
      decode.success(VoteChanged(
        choice_id:,
        choice_label:,
        participant_id:,
        approved:,
      ))
    _ ->
      decode.failure(
        VoteChanged(choice_id, choice_label, participant_id, approved),
        "VoteChanged",
      )
  }
}

pub fn encode_threshold_reached(value: ThresholdReached) -> Json {
  json.object([
    #("type", json.string("threshold_reached")),
    #("choiceId", json.string(value.choice_id)),
    #("choiceLabel", json.string(value.choice_label)),
    #("approvals", json.int(value.approvals)),
    #("threshold", json.int(value.threshold)),
  ])
}

pub fn threshold_reached_decoder() -> Decoder(ThresholdReached) {
  use tag <- decode.field("type", decode.string)
  use choice_id <- decode.field("choiceId", decode.string)
  use choice_label <- decode.field("choiceLabel", decode.string)
  use approvals <- decode.field("approvals", decode.int)
  use threshold <- decode.field("threshold", decode.int)
  case tag {
    "threshold_reached" ->
      decode.success(ThresholdReached(
        choice_id:,
        choice_label:,
        approvals:,
        threshold:,
      ))
    _ ->
      decode.failure(
        ThresholdReached(choice_id, choice_label, approvals, threshold),
        "ThresholdReached",
      )
  }
}

pub fn encode_results_command(value: ResultsCommand) -> Json {
  json.object([
    #(
      "type",
      json.string(case value {
        ShowResults -> "show_results"
        HideResults -> "hide_results"
      }),
    ),
  ])
}

pub fn results_command_decoder() -> Decoder(ResultsCommand) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "show_results" -> decode.success(ShowResults)
    "hide_results" -> decode.success(HideResults)
    _ -> decode.failure(ShowResults, "ResultsCommand")
  }
}

pub fn encode_poll_lifecycle(value: PollLifecycleCommand) -> Json {
  json.object([
    #(
      "type",
      json.string(case value {
        OpenPoll -> "open_poll"
        ClosePoll -> "close_poll"
      }),
    ),
  ])
}

pub fn poll_lifecycle_decoder() -> Decoder(PollLifecycleCommand) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "open_poll" -> decode.success(OpenPoll)
    "close_poll" -> decode.success(ClosePoll)
    _ -> decode.failure(OpenPoll, "PollLifecycleCommand")
  }
}

pub fn encode_slot_operation(operation: SlotOperation) -> Json {
  case operation {
    ClaimSlot -> json.object([#("type", json.string("claim"))])
    ReleaseSlot -> json.object([#("type", json.string("release"))])
    HandoffSlot(target) ->
      json.object([
        #("type", json.string("handoff")),
        #("target", encode_identity(target)),
      ])
  }
}

pub fn slot_operation_decoder() -> Decoder(SlotOperation) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "claim" -> decode.success(ClaimSlot)
    "release" -> decode.success(ReleaseSlot)
    "handoff" -> {
      use target <- decode.field("target", identity_decoder())
      decode.success(HandoffSlot(target))
    }
    _ -> decode.failure(ClaimSlot, "SlotOperation")
  }
}

pub fn encode_slot_command(value: SlotCommand) -> Json {
  json.object([
    #("type", json.string("slot_command")),
    #("slotId", json.string(value.slot_id)),
    #("operation", encode_slot_operation(value.operation)),
  ])
}

pub fn slot_command_decoder() -> Decoder(SlotCommand) {
  use tag <- decode.field("type", decode.string)
  use slot_id <- decode.field("slotId", decode.string)
  use operation <- decode.field("operation", slot_operation_decoder())
  case tag {
    "slot_command" -> decode.success(SlotCommand(slot_id:, operation:))
    _ -> decode.failure(SlotCommand(slot_id, operation), "SlotCommand")
  }
}

pub fn encode_claim_attempted(value: ClaimAttempted) -> Json {
  json.object([
    #("type", json.string("claim_attempted")),
    #("slotId", json.string(value.slot_id)),
    #("operation", encode_slot_operation(value.operation)),
  ])
}

pub fn claim_attempted_decoder() -> Decoder(ClaimAttempted) {
  use tag <- decode.field("type", decode.string)
  use slot_id <- decode.field("slotId", decode.string)
  use operation <- decode.field("operation", slot_operation_decoder())
  case tag {
    "claim_attempted" -> decode.success(ClaimAttempted(slot_id:, operation:))
    _ -> decode.failure(ClaimAttempted(slot_id, operation), "ClaimAttempted")
  }
}

pub fn encode_resolution(value: Resolution) -> Json {
  json.string(case value {
    Accepted -> "accepted"
    Lost -> "lost"
    Aborted -> "aborted"
  })
}

pub fn resolution_decoder() -> Decoder(Resolution) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "accepted" -> decode.success(Accepted)
      "lost" -> decode.success(Lost)
      "aborted" -> decode.success(Aborted)
      _ -> decode.failure(Aborted, "Resolution")
    }
  })
}

fn encode_optional_identity(value: Option(Identity)) -> Json {
  case value {
    Some(identity) -> encode_identity(identity)
    None -> json.null()
  }
}

pub fn encode_claim_resolved(value: ClaimResolved) -> Json {
  json.object([
    #("type", json.string("claim_resolved")),
    #("slotId", json.string(value.slot_id)),
    #("operation", encode_slot_operation(value.operation)),
    #("resolution", encode_resolution(value.resolution)),
    #("owner", encode_optional_identity(value.owner)),
  ])
}

pub fn claim_resolved_decoder() -> Decoder(ClaimResolved) {
  use tag <- decode.field("type", decode.string)
  use slot_id <- decode.field("slotId", decode.string)
  use operation <- decode.field("operation", slot_operation_decoder())
  use resolution <- decode.field("resolution", resolution_decoder())
  use owner <- decode.field("owner", decode.optional(identity_decoder()))
  case tag {
    "claim_resolved" ->
      decode.success(ClaimResolved(slot_id:, operation:, resolution:, owner:))
    _ ->
      decode.failure(
        ClaimResolved(slot_id, operation, resolution, owner),
        "ClaimResolved",
      )
  }
}

pub fn encode_ownership_changed(value: OwnershipChanged) -> Json {
  json.object([
    #("type", json.string("ownership_changed")),
    #("slotId", json.string(value.slot_id)),
    #("slotLabel", json.string(value.slot_label)),
    #("previousOwner", encode_optional_identity(value.previous_owner)),
    #("owner", encode_optional_identity(value.owner)),
  ])
}

pub fn ownership_changed_decoder() -> Decoder(OwnershipChanged) {
  use tag <- decode.field("type", decode.string)
  use slot_id <- decode.field("slotId", decode.string)
  use slot_label <- decode.field("slotLabel", decode.string)
  use previous_owner <- decode.field(
    "previousOwner",
    decode.optional(identity_decoder()),
  )
  use owner <- decode.field("owner", decode.optional(identity_decoder()))
  case tag {
    "ownership_changed" ->
      decode.success(OwnershipChanged(
        slot_id:,
        slot_label:,
        previous_owner:,
        owner:,
      ))
    _ ->
      decode.failure(
        OwnershipChanged(slot_id, slot_label, previous_owner, owner),
        "OwnershipChanged",
      )
  }
}

pub fn decode_threshold_reached(
  value: Json,
) -> Result(ThresholdReached, json.DecodeError) {
  json.parse(json.to_string(value), threshold_reached_decoder())
}

pub fn decode_ownership_changed(
  value: Json,
) -> Result(OwnershipChanged, json.DecodeError) {
  json.parse(json.to_string(value), ownership_changed_decoder())
}

pub fn vote_changed() -> port.Output(VoteChanged) {
  port.output(vote_changed_port_id, vote_changed_schema_id, encode_vote_changed)
}

pub fn threshold_reached() -> port.Output(ThresholdReached) {
  port.output(
    threshold_reached_port_id,
    threshold_reached_schema_id,
    encode_threshold_reached,
  )
}

pub fn show_results() -> port.Input(ResultsCommand) {
  port.local_input(
    show_results_port_id,
    results_command_schema_id,
    results_command_decoder(),
  )
}

pub fn open_poll() -> port.Input(PollLifecycleCommand) {
  port.collaborative_input(
    open_poll_port_id,
    poll_lifecycle_schema_id,
    poll_lifecycle_decoder(),
    ["map:set"],
  )
}

pub fn close_poll() -> port.Input(PollLifecycleCommand) {
  port.collaborative_input(
    close_poll_port_id,
    poll_lifecycle_schema_id,
    poll_lifecycle_decoder(),
    ["map:set"],
  )
}

pub fn claim_slot() -> port.Input(SlotCommand) {
  port.collaborative_input(
    claim_slot_port_id,
    slot_command_schema_id,
    slot_command_decoder(),
    ["claims:claim_once", "claims:compare_and_set"],
  )
}

pub fn release_slot() -> port.Input(SlotCommand) {
  port.collaborative_input(
    release_slot_port_id,
    slot_command_schema_id,
    slot_command_decoder(),
    ["claims:compare_and_set"],
  )
}

pub fn handoff_slot() -> port.Input(SlotCommand) {
  port.collaborative_input(
    handoff_slot_port_id,
    slot_command_schema_id,
    slot_command_decoder(),
    ["claims:compare_and_set"],
  )
}

pub fn reveal_owner() -> port.Input(SlotCommand) {
  port.local_input(
    reveal_owner_port_id,
    slot_command_schema_id,
    slot_command_decoder(),
  )
}

pub fn claim_attempted() -> port.Output(ClaimAttempted) {
  port.output(
    claim_attempted_port_id,
    claim_attempted_schema_id,
    encode_claim_attempted,
  )
}

pub fn claim_resolved() -> port.Output(ClaimResolved) {
  port.output(
    claim_resolved_port_id,
    claim_resolved_schema_id,
    encode_claim_resolved,
  )
}

pub fn ownership_changed() -> port.Output(OwnershipChanged) {
  port.output(
    ownership_changed_port_id,
    ownership_changed_schema_id,
    encode_ownership_changed,
  )
}

pub fn append_poll_threshold() -> port.Input(ThresholdReached) {
  port.collaborative_input(
    append_poll_threshold_port_id,
    threshold_reached_schema_id,
    threshold_reached_decoder(),
    ["sequence:insert"],
  )
}

pub fn append_ownership_change() -> port.Input(OwnershipChanged) {
  port.collaborative_input(
    append_ownership_change_port_id,
    ownership_changed_schema_id,
    ownership_changed_decoder(),
    ["sequence:insert"],
  )
}

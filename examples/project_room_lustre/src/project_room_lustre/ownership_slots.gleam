//// Headless first-writer-wins ownership slots for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import watershed
import watershed/claim_outcome_js
import watershed/claims_kernel
import watershed/component
import watershed/runtime
import watershed/schema
import watershed/transport_js

import project_room_lustre/governance_payload

type OwnershipSchema

/// One fixed ownership slot.
pub type Slot {
  Slot(id: String, label: String)
}

/// The static ownership configuration.
pub type Config {
  Config(title: String, slots: List(Slot))
}

type PendingAttempt {
  PendingAttempt(
    token: Int,
    slot_id: String,
    operation: governance_payload.SlotOperation,
    previous_owner: Option(governance_payload.Identity),
  )
}

/// The running ownership state.
pub opaque type Running {
  Running(
    config: Config,
    participant: governance_payload.Identity,
    claims: transport_js.Cell(watershed.Claims),
    claims_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
    pending: transport_js.Cell(List(PendingAttempt)),
    last_resolutions: transport_js.Cell(
      List(#(String, governance_payload.ClaimResolved)),
    ),
    reveal_details: transport_js.Cell(Bool),
    next_token: transport_js.Cell(Int),
    stopped: transport_js.Cell(Bool),
    emitter: component.OutputEmitter,
    invalidate: fn() -> Nil,
  )
}

fn claims_field() -> schema.ChannelField(OwnershipSchema, schema.ClaimsChannel) {
  schema.channel_field("owners")
}

fn slot_decoder() -> Decoder(Slot) {
  use id <- decode.field("id", decode.string)
  use label <- decode.field("label", decode.string)
  decode.success(Slot(id:, label:))
}

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  use slots <- decode.field("slots", decode.list(slot_decoder()))
  let config = Config(title:, slots:)
  case validate_config(config) {
    Ok(Nil) -> decode.success(config)
    Error(reason) -> decode.failure(config, reason)
  }
}

fn validate_config(config: Config) -> Result(Nil, String) {
  let ids = list.map(config.slots, fn(slot) { slot.id })
  case config.slots != [], list.unique(ids) == ids {
    False, _ -> Error("ownership must have at least one slot")
    _, False -> Error("ownership slot IDs must be unique")
    True, True -> Ok(Nil)
  }
}

pub fn encode_config(config: Config) -> Json {
  json.object([
    #("title", json.string(config.title)),
    #(
      "slots",
      json.array(config.slots, fn(slot) {
        json.object([
          #("id", json.string(slot.id)),
          #("label", json.string(slot.label)),
        ])
      }),
    ),
  ])
}

/// Attach the Claims channel while a new instance subtree is detached.
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(OwnershipSchema) =
    watershed.typed(subtree)
  use claims <- result.try(watershed.create_claims(document))
  watershed.set_claims_field(typed_subtree, claims_field(), claims)
  Ok(Nil)
}

pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  invalidate: fn() -> Nil,
  emitter: component.OutputEmitter,
  participant: governance_payload.Identity,
  config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  let typed_subtree: watershed.TypedMap(OwnershipSchema) =
    watershed.typed(subtree)
  watershed.ensure_claims(document, typed_subtree, claims_field(), fn(result) {
    case result {
      Error(reason) -> done(Error("ownership bootstrap failed: " <> reason))
      Ok(claims) -> {
        let running_cell = transport_js.new_cell(None)
        let claims_subscription =
          transport_js.new_cell(
            watershed.subscribe_claims(claims, fn(_) { invalidate() }),
          )
        let subtree_subscription =
          watershed.subscribe(subtree, fn(_) {
            case transport_js.get_cell(running_cell) {
              Some(running) -> rebind(document, typed_subtree, running)
              None -> Nil
            }
          })
        let running =
          Running(
            config:,
            participant:,
            claims: transport_js.new_cell(claims),
            claims_subscription:,
            subtree_subscription:,
            pending: transport_js.new_cell([]),
            last_resolutions: transport_js.new_cell([]),
            reveal_details: transport_js.new_cell(False),
            next_token: transport_js.new_cell(0),
            stopped: transport_js.new_cell(False),
            emitter:,
            invalidate:,
          )
        transport_js.set_cell(running_cell, Some(running))
        done(Ok(running))
      }
    }
  })
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(OwnershipSchema),
  running: Running,
) -> Nil {
  case watershed.resolve_claims_field(document, subtree, claims_field()) {
    Ok(Some(current)) -> {
      case
        watershed.claims_handle_of(current)
        == watershed.claims_handle_of(claims(running))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(
            running.claims_subscription,
          ))
          transport_js.set_cell(running.claims, current)
          transport_js.set_cell(
            running.claims_subscription,
            watershed.subscribe_claims(current, fn(_) { running.invalidate() }),
          )
          abort_pending_after_rebind(running)
          running.invalidate()
        }
      }
    }
    _ -> Nil
  }
}

fn abort_pending_after_rebind(running: Running) -> Nil {
  let pending = transport_js.get_cell(running.pending)
  transport_js.set_cell(running.pending, [])
  let resolutions =
    list.map(pending, fn(attempt) {
      governance_payload.ClaimResolved(
        slot_id: attempt.slot_id,
        operation: attempt.operation,
        resolution: governance_payload.Aborted,
        owner: owner(running, attempt.slot_id),
      )
    })
  let last =
    list.fold(
      resolutions,
      transport_js.get_cell(running.last_resolutions),
      fn(entries, resolved) {
        [
          #(resolved.slot_id, resolved),
          ..list.filter(entries, fn(entry) { entry.0 != resolved.slot_id })
        ]
      },
    )
  transport_js.set_cell(running.last_resolutions, last)
  case resolutions {
    [] -> Nil
    _ ->
      component.publish(
        running.emitter,
        list.map(resolutions, fn(resolved) {
          component.emit(governance_payload.claim_resolved(), resolved)
        }),
      )
  }
}

pub fn config(running: Running) -> Config {
  running.config
}

pub fn claims(running: Running) -> watershed.Claims {
  transport_js.get_cell(running.claims)
}

pub fn owner(
  running: Running,
  slot_id: String,
) -> Option(governance_payload.Identity) {
  case watershed.get_claim(claims(running), slot_id) {
    Error(Nil) -> None
    Ok(value) ->
      json.parse(
        json.to_string(value),
        decode.optional(governance_payload.identity_decoder()),
      )
      |> result.unwrap(None)
  }
}

pub fn pending(running: Running, slot_id: String) -> Bool {
  transport_js.get_cell(running.pending)
  |> list.any(fn(attempt) { attempt.slot_id == slot_id })
}

pub fn last_resolution(
  running: Running,
  slot_id: String,
) -> Option(governance_payload.ClaimResolved) {
  transport_js.get_cell(running.last_resolutions)
  |> list.find(fn(entry) { entry.0 == slot_id })
  |> option_from_result
  |> option_map(fn(entry) { entry.1 })
}

pub fn details_revealed(running: Running) -> Bool {
  transport_js.get_cell(running.reveal_details)
}

pub fn toggle_details(
  running: Running,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  transport_js.set_cell(
    running.reveal_details,
    !transport_js.get_cell(running.reveal_details),
  )
  running.invalidate()
  Ok(#(running, []))
}

pub fn submit(
  running: Running,
  command: governance_payload.SlotCommand,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  use slot <- result.try(
    find_slot(running.config, command.slot_id)
    |> result.map_error(fn(_) { "ownership slot does not exist" }),
  )
  case pending(running, slot.id) {
    True -> Error("ownership operation is already pending")
    False ->
      case command.operation {
        governance_payload.ClaimSlot -> claim(running, slot)
        governance_payload.ReleaseSlot -> release(running, slot)
        governance_payload.HandoffSlot(target) -> handoff(running, slot, target)
      }
  }
}

fn claim(
  running: Running,
  slot: Slot,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  case owner(running, slot.id) {
    Some(_) -> Error("ownership slot is occupied")
    None ->
      begin_attempt(running, slot, governance_payload.ClaimSlot, None, fn() {
        case watershed.has_claim(claims(running), slot.id) {
          False ->
            watershed.claim_once(
              claims(running),
              slot.id,
              governance_payload.encode_identity(running.participant),
            )
          True ->
            watershed.compare_and_set_claim(
              claims(running),
              slot.id,
              governance_payload.encode_identity(running.participant),
            )
        }
      })
  }
}

fn release(
  running: Running,
  slot: Slot,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  case owner(running, slot.id) {
    Some(current) if current.id == running.participant.id ->
      begin_attempt(
        running,
        slot,
        governance_payload.ReleaseSlot,
        Some(current),
        fn() {
          watershed.compare_and_set_claim(claims(running), slot.id, json.null())
        },
      )
    Some(_) -> Error("only the current owner can release this slot")
    None -> Error("ownership slot is vacant")
  }
}

fn handoff(
  running: Running,
  slot: Slot,
  target: governance_payload.Identity,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  case target.id == "", target.id == running.participant.id {
    True, _ -> Error("handoff target must have an ID")
    _, True -> Error("handoff target must be a different participant")
    False, False ->
      case owner(running, slot.id) {
        Some(current) if current.id == running.participant.id ->
          begin_attempt(
            running,
            slot,
            governance_payload.HandoffSlot(target),
            Some(current),
            fn() {
              watershed.compare_and_set_claim(
                claims(running),
                slot.id,
                governance_payload.encode_identity(target),
              )
            },
          )
        Some(_) -> Error("only the current owner can hand off this slot")
        None -> Error("ownership slot is vacant")
      }
  }
}

fn begin_attempt(
  running: Running,
  slot: Slot,
  operation: governance_payload.SlotOperation,
  previous_owner: Option(governance_payload.Identity),
  submit_claim: fn() -> runtime.ClaimSubmitReply,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  let token = transport_js.get_cell(running.next_token) + 1
  transport_js.set_cell(running.next_token, token)
  let attempt = PendingAttempt(token, slot.id, operation, previous_owner)
  transport_js.set_cell(running.pending, [
    attempt,
    ..transport_js.get_cell(running.pending)
  ])
  running.invalidate()
  claim_outcome_js.observe(submit_claim(), fn(outcome) {
    resolve_attempt(running, slot, attempt, outcome)
  })
  Ok(
    #(running, [
      component.emit(
        governance_payload.claim_attempted(),
        governance_payload.ClaimAttempted(
          slot_id: slot.id,
          operation: operation,
        ),
      ),
    ]),
  )
}

fn resolve_attempt(
  running: Running,
  slot: Slot,
  attempt: PendingAttempt,
  outcome: claims_kernel.ClaimOutcome,
) -> Nil {
  case
    transport_js.get_cell(running.stopped),
    current_attempt(running, attempt)
  {
    True, _ | _, None -> Nil
    False, Some(_) -> {
      transport_js.set_cell(
        running.pending,
        list.filter(transport_js.get_cell(running.pending), fn(candidate) {
          candidate.slot_id != attempt.slot_id
          || candidate.token != attempt.token
        }),
      )
      let committed_owner = owner(running, slot.id)
      let resolution = case outcome {
        claims_kernel.Accepted(_) -> governance_payload.Accepted
        claims_kernel.Lost(_) -> governance_payload.Lost
        claims_kernel.Aborted -> governance_payload.Aborted
      }
      let resolved =
        governance_payload.ClaimResolved(
          slot_id: slot.id,
          operation: attempt.operation,
          resolution:,
          owner: committed_owner,
        )
      transport_js.set_cell(running.last_resolutions, [
        #(slot.id, resolved),
        ..list.filter(
          transport_js.get_cell(running.last_resolutions),
          fn(entry) { entry.0 != slot.id },
        )
      ])
      let events = [
        component.emit(governance_payload.claim_resolved(), resolved),
      ]
      let events = case outcome {
        claims_kernel.Accepted(_) ->
          list.append(events, [
            component.emit(
              governance_payload.ownership_changed(),
              governance_payload.OwnershipChanged(
                slot_id: slot.id,
                slot_label: slot.label,
                previous_owner: attempt.previous_owner,
                owner: committed_owner,
              ),
            ),
          ])
        claims_kernel.Lost(_) | claims_kernel.Aborted -> events
      }
      component.publish(running.emitter, events)
      running.invalidate()
    }
  }
}

fn current_attempt(
  running: Running,
  expected: PendingAttempt,
) -> Option(PendingAttempt) {
  transport_js.get_cell(running.pending)
  |> list.find(fn(candidate) {
    candidate.slot_id == expected.slot_id && candidate.token == expected.token
  })
  |> option_from_result
}

fn find_slot(config: Config, slot_id: String) -> Result(Slot, Nil) {
  list.find(config.slots, fn(slot) { slot.id == slot_id })
}

fn option_from_result(value: Result(a, Nil)) -> Option(a) {
  case value {
    Ok(found) -> Some(found)
    Error(Nil) -> None
  }
}

fn option_map(value: Option(a), transform: fn(a) -> b) -> Option(b) {
  case value {
    Some(found) -> Some(transform(found))
    None -> None
  }
}

pub fn stop(running: Running) -> Result(Nil, String) {
  transport_js.set_cell(running.stopped, True)
  watershed.unsubscribe(transport_js.get_cell(running.claims_subscription))
  watershed.unsubscribe(running.subtree_subscription)
  Ok(Nil)
}

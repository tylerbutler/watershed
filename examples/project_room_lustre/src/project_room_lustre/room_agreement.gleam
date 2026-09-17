//// Headless PactMap-backed room agreement for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import watershed
import watershed/component
import watershed/id
import watershed/pact_map_kernel
import watershed/schema
import watershed/transport_js

import project_room_lustre/component_event

type RoomAgreementSchema

const agreement_key = "agreement"

pub type Config {
  Config(title: String)
}

pub type Proposal {
  Proposal(id: String, proposer_id: String, text: String)
}

type Attempt {
  Attempt(proposal: Proposal, accepted_before: Option(Proposal))
}

pub opaque type Running {
  Running(
    instance_id: String,
    config: Config,
    pact_map: transport_js.Cell(watershed.PactMap),
    pact_map_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
    accepted: transport_js.Cell(Option(Proposal)),
    pending: transport_js.Cell(Option(Proposal)),
    pending_signoffs: transport_js.Cell(Int),
    draft: transport_js.Cell(String),
    attempt: transport_js.Cell(Option(Attempt)),
    emitted_proposal_id: transport_js.Cell(Option(String)),
    participant_id: fn() -> Option(String),
    stopped: transport_js.Cell(Bool),
    invalidate: fn() -> Nil,
  )
}

fn agreements_field() -> schema.ChannelField(
  RoomAgreementSchema,
  schema.PactMapChannel,
) {
  schema.channel_field("agreements")
}

pub fn encode_config(config: Config) -> Json {
  json.object([#("title", json.string(config.title))])
}

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  decode.success(Config(title:))
}

pub fn encode_proposal(proposal: Proposal) -> Json {
  json.object([
    #("id", json.string(proposal.id)),
    #("proposerId", json.string(proposal.proposer_id)),
    #("text", json.string(proposal.text)),
  ])
}

pub fn proposal_decoder() -> Decoder(Proposal) {
  use id <- decode.field("id", decode.string)
  use proposer_id <- decode.field("proposerId", decode.string)
  use text <- decode.field("text", decode.string)
  decode.success(Proposal(id:, proposer_id:, text:))
}

pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(RoomAgreementSchema) =
    watershed.typed(subtree)
  use pact_map <- result.try(watershed.create_pact_map(document))
  watershed.set_pact_map_field(typed_subtree, agreements_field(), pact_map)
  Ok(Nil)
}

pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  instance_id: String,
  invalidate: fn() -> Nil,
  config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  let typed_subtree: watershed.TypedMap(RoomAgreementSchema) =
    watershed.typed(subtree)
  watershed.ensure_pact_map(
    document,
    typed_subtree,
    agreements_field(),
    fn(result) {
      case result {
        Error(reason) ->
          done(Error("room agreement bootstrap failed: " <> reason))
        Ok(pact_map) -> {
          let stopped = transport_js.new_cell(False)
          let pact_map_cell = transport_js.new_cell(pact_map)
          let pact_map_subscription =
            transport_js.new_cell(subscribe_pact_map(
              pact_map,
              stopped,
              invalidate,
            ))
          let running_cell = transport_js.new_cell(None)
          let subtree_subscription =
            watershed.subscribe(subtree, fn(_) {
              case transport_js.get_cell(running_cell) {
                Some(running) -> rebind(document, typed_subtree, running)
                None -> Nil
              }
            })
          let running =
            Running(
              instance_id:,
              config:,
              pact_map: pact_map_cell,
              pact_map_subscription:,
              subtree_subscription:,
              accepted: transport_js.new_cell(None),
              pending: transport_js.new_cell(None),
              pending_signoffs: transport_js.new_cell(0),
              draft: transport_js.new_cell(""),
              attempt: transport_js.new_cell(None),
              emitted_proposal_id: transport_js.new_cell(None),
              participant_id: fn() { watershed.client_id(document) },
              stopped:,
              invalidate:,
            )
          transport_js.set_cell(running_cell, Some(running))
          refresh_state(running)
          rebind(document, typed_subtree, running)
          done(Ok(running))
        }
      }
    },
  )
}

fn subscribe_pact_map(
  pact_map: watershed.PactMap,
  stopped: transport_js.Cell(Bool),
  invalidate: fn() -> Nil,
) -> watershed.SubscriptionToken {
  watershed.subscribe_pact_map(pact_map, fn(_) {
    case transport_js.get_cell(stopped) {
      True -> Nil
      False -> invalidate()
    }
  })
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(RoomAgreementSchema),
  running: Running,
) -> Nil {
  case transport_js.get_cell(running.stopped) {
    True -> Nil
    False ->
      case
        watershed.resolve_pact_map_field(document, subtree, agreements_field())
      {
        Ok(Some(current)) -> {
          case
            watershed.pact_map_handle_of(current)
            == watershed.pact_map_handle_of(current_pact_map(running))
          {
            True -> Nil
            False -> {
              watershed.unsubscribe(transport_js.get_cell(
                running.pact_map_subscription,
              ))
              transport_js.set_cell(running.pact_map, current)
              transport_js.set_cell(running.attempt, None)
              transport_js.set_cell(running.emitted_proposal_id, None)
              transport_js.set_cell(
                running.pact_map_subscription,
                subscribe_pact_map(current, running.stopped, running.invalidate),
              )
              refresh_state(running)
              running.invalidate()
            }
          }
        }
        Ok(None) -> Nil
        Error(_) -> Nil
      }
  }
}

fn current_pact_map(running: Running) -> watershed.PactMap {
  transport_js.get_cell(running.pact_map)
}

fn decode_proposal(value: Json) -> Option(Proposal) {
  case json.parse(json.to_string(value), proposal_decoder()) {
    Ok(proposal) -> Some(proposal)
    Error(_) -> None
  }
}

fn read_accepted(pact_map: watershed.PactMap) -> Option(Proposal) {
  case watershed.pact_map_get(pact_map, agreement_key) {
    Ok(value) -> decode_proposal(value)
    Error(Nil) -> None
  }
}

fn read_pending(pact_map: watershed.PactMap) -> Option(Proposal) {
  case watershed.pact_map_pending(pact_map, agreement_key) {
    Ok(pact_map_kernel.Pending(Some(value), _)) -> decode_proposal(value)
    Ok(pact_map_kernel.Pending(None, _)) | Error(Nil) -> None
  }
}

fn read_pending_signoffs(pact_map: watershed.PactMap) -> Int {
  case watershed.pact_map_pending_signoffs(pact_map, agreement_key) {
    Ok(signoffs) -> list.length(signoffs)
    Error(Nil) -> 0
  }
}

fn same_proposal_identity(a: Proposal, b: Proposal) -> Bool {
  a.id == b.id && a.proposer_id == b.proposer_id
}

fn refresh_state(running: Running) -> Nil {
  let pact_map = current_pact_map(running)
  let accepted = read_accepted(pact_map)
  let pending = read_pending(pact_map)
  let is_pending = watershed.pact_map_is_pending(pact_map, agreement_key)
  transport_js.set_cell(running.accepted, accepted)
  transport_js.set_cell(running.pending, pending)
  transport_js.set_cell(
    running.pending_signoffs,
    read_pending_signoffs(pact_map),
  )
  case transport_js.get_cell(running.attempt) {
    None -> Nil
    Some(Attempt(proposal, accepted_before)) ->
      case pending, is_pending {
        Some(visible), _ if visible.id == proposal.id -> Nil
        Some(_), _ | None, True -> transport_js.set_cell(running.attempt, None)
        None, False ->
          case accepted {
            Some(current) ->
              case
                same_proposal_identity(current, proposal)
                || accepted == accepted_before
              {
                True -> Nil
                False -> transport_js.set_cell(running.attempt, None)
              }
            None ->
              case accepted_before {
                None -> Nil
                Some(_) -> transport_js.set_cell(running.attempt, None)
              }
          }
      }
  }
}

pub fn accepted(running: Running) -> Option(Proposal) {
  transport_js.get_cell(running.accepted)
}

pub fn pending(running: Running) -> Option(Proposal) {
  transport_js.get_cell(running.pending)
}

pub fn pending_signoffs(running: Running) -> Int {
  transport_js.get_cell(running.pending_signoffs)
}

pub fn draft(running: Running) -> String {
  transport_js.get_cell(running.draft)
}

pub fn config(running: Running) -> Config {
  running.config
}

pub fn set_draft(running: Running, draft: String) -> Running {
  transport_js.set_cell(running.draft, draft)
  running
}

pub fn propose(running: Running) -> Result(Running, String) {
  case transport_js.get_cell(running.stopped) {
    True -> Error("room agreement is stopped")
    False -> {
      let text = string.trim(draft(running))
      case text {
        "" -> Error("agreement text cannot be blank")
        _ ->
          case
            transport_js.get_cell(running.attempt),
            watershed.pact_map_is_pending(
              current_pact_map(running),
              agreement_key,
            )
          {
            Some(_), _ | None, True ->
              Error("an agreement proposal is already pending")
            None, False ->
              case running.participant_id() {
                None -> Error("room agreement participant is unavailable")
                Some(proposer_id) -> {
                  let proposal = Proposal(id: id.uuid_v4(), proposer_id:, text:)
                  let accepted_before =
                    current_pact_map(running)
                    |> read_accepted
                  transport_js.set_cell(
                    running.attempt,
                    Some(Attempt(proposal, accepted_before)),
                  )
                  watershed.pact_map_set(
                    current_pact_map(running),
                    agreement_key,
                    encode_proposal(proposal),
                  )
                  Ok(running)
                }
              }
          }
      }
    }
  }
}

pub fn refresh(running: Running) -> #(Running, List(component.OutputEvent)) {
  refresh_state(running)
  #(running, acceptance_events(running))
}

fn acceptance_events(running: Running) -> List(component.OutputEvent) {
  case transport_js.get_cell(running.attempt) {
    None -> []
    Some(Attempt(local, _)) ->
      case accepted(running) {
        None -> []
        Some(current) ->
          case same_proposal_identity(local, current) {
            False -> []
            True -> {
              transport_js.set_cell(running.attempt, None)
              case transport_js.get_cell(running.emitted_proposal_id) {
                Some(id) if id == current.id -> []
                Some(_) | None -> {
                  transport_js.set_cell(
                    running.emitted_proposal_id,
                    Some(current.id),
                  )
                  [
                    component.emit(
                      component_event.emitted(),
                      component_event.Event(
                        source_instance_id: running.instance_id,
                        source_kind: "project-room/room-agreement",
                        source_title: running.config.title,
                        action: component_event.AgreementAccepted,
                        detail: "Accepted agreement: " <> current.text,
                      ),
                    ),
                  ]
                }
              }
            }
          }
      }
  }
}

pub fn stop(running: Running) -> Result(Nil, String) {
  case transport_js.get_cell(running.stopped) {
    True -> Ok(Nil)
    False -> {
      transport_js.set_cell(running.stopped, True)
      watershed.unsubscribe(transport_js.get_cell(running.pact_map_subscription))
      watershed.unsubscribe(running.subtree_subscription)
      Ok(Nil)
    }
  }
}

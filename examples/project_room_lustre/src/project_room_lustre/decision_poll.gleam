//// Headless approval poll for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import watershed
import watershed/claim_outcome_js
import watershed/claims_kernel
import watershed/component
import watershed/schema
import watershed/transport_js

import project_room_lustre/governance_payload

type PollSchema

/// One fixed poll choice.
pub type Choice {
  Choice(id: String, label: String)
}

/// The static poll configuration.
pub type Config {
  Config(title: String, question: String, choices: List(Choice), threshold: Int)
}

type Ballot {
  Ballot(choice_id: String, participant_id: String)
}

/// The running poll state.
pub opaque type Running {
  Running(
    config: Config,
    participant: governance_payload.Identity,
    ballots: transport_js.Cell(watershed.OrSet),
    lifecycle: transport_js.Cell(watershed.SharedMap),
    thresholds: transport_js.Cell(watershed.Claims),
    ballots_subscription: transport_js.Cell(watershed.SubscriptionToken),
    lifecycle_subscription: transport_js.Cell(watershed.SubscriptionToken),
    thresholds_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
    results_visible: transport_js.Cell(Bool),
    pending_thresholds: transport_js.Cell(List(String)),
    threshold_generation: transport_js.Cell(Int),
    local_error: transport_js.Cell(Option(String)),
    stopped: transport_js.Cell(Bool),
    emitter: component.OutputEmitter,
    invalidate: fn() -> Nil,
  )
}

const lifecycle_key = "open"

fn ballots_field() -> schema.ChannelField(PollSchema, schema.OrSetChannel) {
  schema.channel_field("ballots")
}

fn lifecycle_field() -> schema.ChannelField(PollSchema, schema.MapChannel) {
  schema.channel_field("lifecycle")
}

fn thresholds_field() -> schema.ChannelField(PollSchema, schema.ClaimsChannel) {
  schema.channel_field("thresholds")
}

fn choice_decoder() -> Decoder(Choice) {
  use id <- decode.field("id", decode.string)
  use label <- decode.field("label", decode.string)
  decode.success(Choice(id:, label:))
}

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  use question <- decode.field("question", decode.string)
  use choices <- decode.field("choices", decode.list(choice_decoder()))
  use threshold <- decode.field("threshold", decode.int)
  let config = Config(title:, question:, choices:, threshold:)
  case validate_config(config) {
    Ok(Nil) -> decode.success(config)
    Error(reason) -> decode.failure(config, reason)
  }
}

fn validate_config(config: Config) -> Result(Nil, String) {
  let ids = list.map(config.choices, fn(choice) { choice.id })
  case config.threshold > 0, config.choices != [], list.unique(ids) == ids {
    False, _, _ -> Error("poll threshold must be positive")
    _, False, _ -> Error("poll must have at least one choice")
    _, _, False -> Error("poll choice IDs must be unique")
    True, True, True -> Ok(Nil)
  }
}

pub fn encode_config(config: Config) -> Json {
  json.object([
    #("title", json.string(config.title)),
    #("question", json.string(config.question)),
    #(
      "choices",
      json.array(config.choices, fn(choice) {
        json.object([
          #("id", json.string(choice.id)),
          #("label", json.string(choice.label)),
        ])
      }),
    ),
    #("threshold", json.int(config.threshold)),
  ])
}

/// Attach all owned channels while a new instance subtree is detached.
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(PollSchema) = watershed.typed(subtree)
  use ballots <- result.try(watershed.create_or_set(document))
  use lifecycle <- result.try(watershed.create_map(document))
  use thresholds <- result.try(watershed.create_claims(document))
  watershed.set_or_set_field(typed_subtree, ballots_field(), ballots)
  watershed.set_map_field(typed_subtree, lifecycle_field(), lifecycle)
  watershed.set_claims_field(typed_subtree, thresholds_field(), thresholds)
  watershed.set(lifecycle, lifecycle_key, json.bool(True))
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
  let typed_subtree: watershed.TypedMap(PollSchema) = watershed.typed(subtree)
  watershed.ensure_or_set(
    document,
    typed_subtree,
    ballots_field(),
    fn(ballots_result) {
      case ballots_result {
        Error(reason) -> done(Error("poll ballot bootstrap failed: " <> reason))
        Ok(ballots) ->
          watershed.ensure_map(
            document,
            typed_subtree,
            lifecycle_field(),
            fn(lifecycle_result) {
              case lifecycle_result {
                Error(reason) ->
                  done(Error("poll lifecycle bootstrap failed: " <> reason))
                Ok(lifecycle) ->
                  watershed.ensure_claims(
                    document,
                    typed_subtree,
                    thresholds_field(),
                    fn(thresholds_result) {
                      case thresholds_result {
                        Error(reason) ->
                          done(Error(
                            "poll threshold bootstrap failed: " <> reason,
                          ))
                        Ok(thresholds) -> {
                          case watershed.has(lifecycle, lifecycle_key) {
                            True -> Nil
                            False ->
                              watershed.set(
                                lifecycle,
                                lifecycle_key,
                                json.bool(True),
                              )
                          }
                          let ballots_cell = transport_js.new_cell(ballots)
                          let lifecycle_cell = transport_js.new_cell(lifecycle)
                          let thresholds_cell =
                            transport_js.new_cell(thresholds)
                          let pending = transport_js.new_cell([])
                          let stopped = transport_js.new_cell(False)
                          let ballots_subscription =
                            transport_js.new_cell(
                              watershed.subscribe_or_set(ballots, fn(_) {
                                invalidate()
                              }),
                            )
                          let lifecycle_subscription =
                            transport_js.new_cell(
                              watershed.subscribe(lifecycle, fn(_) {
                                invalidate()
                              }),
                            )
                          let thresholds_subscription =
                            transport_js.new_cell(
                              watershed.subscribe_claims(thresholds, fn(_) {
                                invalidate()
                              }),
                            )
                          let running_cell = transport_js.new_cell(None)
                          let subtree_subscription =
                            watershed.subscribe(subtree, fn(_) {
                              case transport_js.get_cell(running_cell) {
                                Some(running) ->
                                  rebind(document, typed_subtree, running)
                                None -> Nil
                              }
                            })
                          let running =
                            Running(
                              config:,
                              participant:,
                              ballots: ballots_cell,
                              lifecycle: lifecycle_cell,
                              thresholds: thresholds_cell,
                              ballots_subscription:,
                              lifecycle_subscription:,
                              thresholds_subscription:,
                              subtree_subscription:,
                              results_visible: transport_js.new_cell(False),
                              pending_thresholds: pending,
                              threshold_generation: transport_js.new_cell(0),
                              local_error: transport_js.new_cell(None),
                              stopped:,
                              emitter:,
                              invalidate:,
                            )
                          transport_js.set_cell(running_cell, Some(running))
                          replace_ballot_subscription(running, ballots)
                          check_thresholds(running)
                          done(Ok(running))
                        }
                      }
                    },
                  )
              }
            },
          )
      }
    },
  )
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(PollSchema),
  running: Running,
) -> Nil {
  case watershed.resolve_or_set_field(document, subtree, ballots_field()) {
    Ok(Some(current)) -> {
      case
        watershed.or_set_handle_of(current)
        == watershed.or_set_handle_of(ballots(running))
      {
        True -> Nil
        False -> {
          transport_js.set_cell(running.ballots, current)
          replace_ballot_subscription(running, current)
          check_thresholds(running)
        }
      }
    }
    _ -> Nil
  }
  case watershed.resolve_map_field(document, subtree, lifecycle_field()) {
    Ok(Some(current)) -> {
      case
        watershed.handle_of(current) == watershed.handle_of(lifecycle(running))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(
            running.lifecycle_subscription,
          ))
          transport_js.set_cell(running.lifecycle, current)
          transport_js.set_cell(
            running.lifecycle_subscription,
            watershed.subscribe(current, fn(_) { running.invalidate() }),
          )
          running.invalidate()
        }
      }
    }
    _ -> Nil
  }
  case watershed.resolve_claims_field(document, subtree, thresholds_field()) {
    Ok(Some(current)) -> {
      case
        watershed.claims_handle_of(current)
        == watershed.claims_handle_of(thresholds(running))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(
            running.thresholds_subscription,
          ))
          let had_pending =
            transport_js.get_cell(running.pending_thresholds) != []
          transport_js.set_cell(running.pending_thresholds, [])
          transport_js.set_cell(
            running.threshold_generation,
            transport_js.get_cell(running.threshold_generation) + 1,
          )
          transport_js.set_cell(running.thresholds, current)
          transport_js.set_cell(
            running.thresholds_subscription,
            watershed.subscribe_claims(current, fn(_) { running.invalidate() }),
          )
          case had_pending {
            True ->
              transport_js.set_cell(
                running.local_error,
                Some("threshold channel changed while a claim was pending"),
              )
            False -> Nil
          }
          check_thresholds(running)
        }
      }
    }
    _ -> Nil
  }
}

fn replace_ballot_subscription(
  running: Running,
  current: watershed.OrSet,
) -> Nil {
  watershed.unsubscribe(transport_js.get_cell(running.ballots_subscription))
  transport_js.set_cell(
    running.ballots_subscription,
    watershed.subscribe_or_set(current, fn(_) {
      check_thresholds(running)
      running.invalidate()
    }),
  )
  running.invalidate()
}

pub fn config(running: Running) -> Config {
  running.config
}

pub fn ballots(running: Running) -> watershed.OrSet {
  transport_js.get_cell(running.ballots)
}

pub fn lifecycle(running: Running) -> watershed.SharedMap {
  transport_js.get_cell(running.lifecycle)
}

pub fn thresholds(running: Running) -> watershed.Claims {
  transport_js.get_cell(running.thresholds)
}

pub fn is_open(running: Running) -> Bool {
  case watershed.get(lifecycle(running), lifecycle_key) {
    Ok(value) ->
      json.parse(json.to_string(value), decode.bool)
      |> result.unwrap(False)
    Error(Nil) -> False
  }
}

pub fn results_visible(running: Running) -> Bool {
  transport_js.get_cell(running.results_visible)
}

pub fn pending_threshold(running: Running, choice_id: String) -> Bool {
  list.contains(transport_js.get_cell(running.pending_thresholds), choice_id)
}

pub fn local_error(running: Running) -> Option(String) {
  transport_js.get_cell(running.local_error)
}

pub fn approved_by_local(running: Running, choice_id: String) -> Bool {
  watershed.or_set_contains(
    ballots(running),
    encode_ballot(Ballot(choice_id, running.participant.id)),
  )
}

pub fn approval_count(running: Running, choice_id: String) -> Int {
  watershed.or_set_values(ballots(running))
  |> list.filter_map(fn(encoded) {
    case decode_ballot(encoded) {
      Ok(Ballot(found_choice, participant_id)) if found_choice == choice_id ->
        case has_choice(running.config, found_choice) {
          True -> Ok(participant_id)
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
  |> list.unique
  |> list.length
}

pub fn threshold_reached(running: Running, choice_id: String) -> Bool {
  watershed.has_claim(thresholds(running), choice_id)
}

pub fn vote(
  running: Running,
  choice_id: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  use choice <- result.try(
    find_choice(running.config, choice_id)
    |> result.map_error(fn(_) { "poll choice does not exist" }),
  )
  case is_open(running) {
    False -> Error("poll is closed")
    True -> {
      let encoded = encode_ballot(Ballot(choice_id, running.participant.id))
      let approved = !watershed.or_set_contains(ballots(running), encoded)
      case approved {
        True -> watershed.or_set_add(ballots(running), encoded)
        False -> watershed.or_set_remove(ballots(running), encoded)
      }
      Ok(
        #(running, [
          component.emit(
            governance_payload.vote_changed(),
            governance_payload.VoteChanged(
              choice_id:,
              choice_label: choice.label,
              participant_id: running.participant.id,
              approved:,
            ),
          ),
        ]),
      )
    }
  }
}

pub fn set_results_visibility(
  running: Running,
  command: governance_payload.ResultsCommand,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  transport_js.set_cell(
    running.results_visible,
    command == governance_payload.ShowResults,
  )
  running.invalidate()
  Ok(#(running, []))
}

pub fn set_lifecycle(
  running: Running,
  command: governance_payload.PollLifecycleCommand,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  watershed.set(
    lifecycle(running),
    lifecycle_key,
    json.bool(command == governance_payload.OpenPoll),
  )
  Ok(#(running, []))
}

fn check_thresholds(running: Running) -> Nil {
  case transport_js.get_cell(running.stopped) {
    True -> Nil
    False ->
      list.each(running.config.choices, fn(choice) {
        let count = approval_count(running, choice.id)
        let pending = pending_threshold(running, choice.id)
        case
          count >= running.config.threshold,
          threshold_reached(running, choice.id),
          pending
        {
          True, False, False -> claim_threshold(running, choice, count)
          _, _, _ -> Nil
        }
      })
  }
}

fn claim_threshold(running: Running, choice: Choice, approvals: Int) -> Nil {
  let generation = transport_js.get_cell(running.threshold_generation)
  transport_js.set_cell(running.pending_thresholds, [
    choice.id,
    ..transport_js.get_cell(running.pending_thresholds)
  ])
  let reply =
    watershed.claim_once(
      thresholds(running),
      choice.id,
      governance_payload.encode_threshold_reached(
        governance_payload.ThresholdReached(
          choice_id: choice.id,
          choice_label: choice.label,
          approvals:,
          threshold: running.config.threshold,
        ),
      ),
    )
  claim_outcome_js.observe(reply, fn(outcome) {
    case
      transport_js.get_cell(running.stopped),
      transport_js.get_cell(running.threshold_generation) == generation,
      pending_threshold(running, choice.id)
    {
      True, _, _ | _, False, _ | _, _, False -> Nil
      False, True, True -> {
        transport_js.set_cell(
          running.pending_thresholds,
          list.filter(transport_js.get_cell(running.pending_thresholds), fn(id) {
            id != choice.id
          }),
        )
        case outcome {
          claims_kernel.Accepted(_) ->
            component.publish(running.emitter, [
              component.emit(
                governance_payload.threshold_reached(),
                governance_payload.ThresholdReached(
                  choice_id: choice.id,
                  choice_label: choice.label,
                  approvals:,
                  threshold: running.config.threshold,
                ),
              ),
            ])
          claims_kernel.Lost(_) -> Nil
          claims_kernel.Aborted ->
            transport_js.set_cell(
              running.local_error,
              Some("threshold claim aborted for " <> choice.label),
            )
        }
        running.invalidate()
      }
    }
  })
}

fn has_choice(config: Config, choice_id: String) -> Bool {
  result.is_ok(find_choice(config, choice_id))
}

fn find_choice(config: Config, choice_id: String) -> Result(Choice, Nil) {
  list.find(config.choices, fn(choice) { choice.id == choice_id })
}

fn encode_ballot(ballot: Ballot) -> String {
  json.object([
    #("choiceId", json.string(ballot.choice_id)),
    #("participantId", json.string(ballot.participant_id)),
  ])
  |> json.to_string
}

fn ballot_decoder() -> Decoder(Ballot) {
  use choice_id <- decode.field("choiceId", decode.string)
  use participant_id <- decode.field("participantId", decode.string)
  decode.success(Ballot(choice_id:, participant_id:))
}

fn decode_ballot(encoded: String) -> Result(Ballot, json.DecodeError) {
  json.parse(encoded, ballot_decoder())
}

pub fn stop(running: Running) -> Result(Nil, String) {
  transport_js.set_cell(running.stopped, True)
  watershed.unsubscribe(transport_js.get_cell(running.ballots_subscription))
  watershed.unsubscribe(transport_js.get_cell(running.lifecycle_subscription))
  watershed.unsubscribe(transport_js.get_cell(running.thresholds_subscription))
  watershed.unsubscribe(running.subtree_subscription)
  Ok(Nil)
}

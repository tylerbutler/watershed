//// Headless tally for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{None, Some}
import gleam/result

import watershed
import watershed/claim_outcome_js
import watershed/claims_kernel
import watershed/component
import watershed/schema
import watershed/transport_js

import project_room_lustre/tally_payload

type TallySchema

/// The static tally configuration.
pub type Config {
  Config(title: String, target: Int)
}

/// The running tally state.
pub opaque type Running {
  Running(
    config: Config,
    counter: transport_js.Cell(watershed.PnCounter),
    target: transport_js.Cell(watershed.Claims),
    counter_subscription: transport_js.Cell(watershed.SubscriptionToken),
    target_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
    pending: transport_js.Cell(Bool),
    generation: transport_js.Cell(Int),
    stopped: transport_js.Cell(Bool),
    emitter: component.OutputEmitter,
    invalidate: fn() -> Nil,
  )
}

fn counter_field() -> schema.ChannelField(TallySchema, schema.PnCounterChannel) {
  schema.channel_field("counter")
}

fn target_field() -> schema.ChannelField(TallySchema, schema.ClaimsChannel) {
  schema.channel_field("target")
}

const target_key = "reached"

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  use target <- decode.field("target", decode.int)
  let config = Config(title:, target:)
  case target > 0 {
    True -> decode.success(config)
    False -> decode.failure(config, "tally target must be positive")
  }
}

pub fn encode_config(config: Config) -> Json {
  json.object([
    #("title", json.string(config.title)),
    #("target", json.int(config.target)),
  ])
}

/// Attach the owned channels while a new instance subtree is detached.
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(TallySchema) = watershed.typed(subtree)
  use counter <- result.try(watershed.create_pn_counter(document))
  use target <- result.try(watershed.create_claims(document))
  watershed.set_pn_counter_field(typed_subtree, counter_field(), counter)
  watershed.set_claims_field(typed_subtree, target_field(), target)
  Ok(Nil)
}

pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  invalidate: fn() -> Nil,
  emitter: component.OutputEmitter,
  config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  let typed_subtree: watershed.TypedMap(TallySchema) = watershed.typed(subtree)
  watershed.ensure_pn_counter(
    document,
    typed_subtree,
    counter_field(),
    fn(counter_result) {
      case counter_result {
        Error(reason) ->
          done(Error("tally counter bootstrap failed: " <> reason))
        Ok(counter) ->
          watershed.ensure_claims(
            document,
            typed_subtree,
            target_field(),
            fn(target_result) {
              case target_result {
                Error(reason) ->
                  done(Error("tally target bootstrap failed: " <> reason))
                Ok(target) -> {
                  let counter_cell = transport_js.new_cell(counter)
                  let target_cell = transport_js.new_cell(target)
                  let counter_subscription =
                    transport_js.new_cell(
                      watershed.subscribe_pn_counter(counter, fn(_) {
                        invalidate()
                      }),
                    )
                  let target_subscription =
                    transport_js.new_cell(
                      watershed.subscribe_claims(target, fn(_) { invalidate() }),
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
                      counter: counter_cell,
                      target: target_cell,
                      counter_subscription:,
                      target_subscription:,
                      subtree_subscription:,
                      pending: transport_js.new_cell(False),
                      generation: transport_js.new_cell(0),
                      stopped: transport_js.new_cell(False),
                      emitter:,
                      invalidate:,
                    )
                  transport_js.set_cell(running_cell, Some(running))
                  replace_counter_subscription(running, counter)
                  check_target(running)
                  done(Ok(running))
                }
              }
            },
          )
      }
    },
  )
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(TallySchema),
  running: Running,
) -> Nil {
  case watershed.resolve_pn_counter_field(document, subtree, counter_field()) {
    Ok(Some(current)) -> {
      case
        watershed.pn_counter_handle_of(current)
        == watershed.pn_counter_handle_of(counter(running))
      {
        True -> Nil
        False -> {
          transport_js.set_cell(running.counter, current)
          replace_counter_subscription(running, current)
          check_target(running)
        }
      }
    }
    _ -> Nil
  }
  case watershed.resolve_claims_field(document, subtree, target_field()) {
    Ok(Some(current)) -> {
      case
        watershed.claims_handle_of(current)
        == watershed.claims_handle_of(claims(running))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(
            running.target_subscription,
          ))
          transport_js.set_cell(running.pending, False)
          transport_js.set_cell(
            running.generation,
            transport_js.get_cell(running.generation) + 1,
          )
          transport_js.set_cell(running.target, current)
          transport_js.set_cell(
            running.target_subscription,
            watershed.subscribe_claims(current, fn(_) { running.invalidate() }),
          )
          check_target(running)
          running.invalidate()
        }
      }
    }
    _ -> Nil
  }
}

fn replace_counter_subscription(
  running: Running,
  current: watershed.PnCounter,
) -> Nil {
  watershed.unsubscribe(transport_js.get_cell(running.counter_subscription))
  transport_js.set_cell(
    running.counter_subscription,
    watershed.subscribe_pn_counter(current, fn(_) {
      check_target(running)
      running.invalidate()
    }),
  )
  running.invalidate()
}

pub fn config(running: Running) -> Config {
  running.config
}

pub fn value(running: Running) -> Int {
  watershed.pn_counter_value(counter(running))
  |> result.unwrap(0)
}

pub fn target_reached(running: Running) -> Bool {
  watershed.has_claim(claims(running), target_key)
}

pub fn pending_target(running: Running) -> Bool {
  transport_js.get_cell(running.pending)
}

pub fn add(
  running: Running,
  amount: Int,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  case amount {
    0 -> Error("tally delta must not be zero")
    _ -> {
      watershed.pn_counter_update(counter(running), amount)
      check_target(running)
      Ok(#(running, []))
    }
  }
}

fn check_target(running: Running) -> Nil {
  case
    transport_js.get_cell(running.stopped),
    value(running) >= running.config.target,
    target_reached(running),
    transport_js.get_cell(running.pending)
  {
    False, True, False, False -> claim_target(running)
    _, _, _, _ -> Nil
  }
}

fn claim_target(running: Running) -> Nil {
  let generation = transport_js.get_cell(running.generation)
  let claimed_value = value(running)
  transport_js.set_cell(running.pending, True)
  let reply =
    watershed.claim_once(claims(running), target_key, json.int(value(running)))
  claim_outcome_js.observe(reply, fn(outcome) {
    case
      transport_js.get_cell(running.stopped),
      transport_js.get_cell(running.generation) == generation,
      transport_js.get_cell(running.pending)
    {
      True, _, _ | _, False, _ | _, _, False -> Nil
      False, True, True -> {
        transport_js.set_cell(running.pending, False)
        case outcome {
          claims_kernel.Accepted(_) ->
            component.publish(running.emitter, [
              component.emit(tally_payload.target_reached(), claimed_value),
            ])
          claims_kernel.Lost(_) | claims_kernel.Aborted -> Nil
        }
        running.invalidate()
      }
    }
  })
}

pub fn stop(running: Running) -> Result(Nil, String) {
  transport_js.set_cell(running.stopped, True)
  watershed.unsubscribe(transport_js.get_cell(running.counter_subscription))
  watershed.unsubscribe(transport_js.get_cell(running.target_subscription))
  watershed.unsubscribe(running.subtree_subscription)
  Ok(Nil)
}

fn counter(running: Running) -> watershed.PnCounter {
  transport_js.get_cell(running.counter)
}

fn claims(running: Running) -> watershed.Claims {
  transport_js.get_cell(running.target)
}

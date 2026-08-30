//// Fuzz coverage for PactMap's quorum protocol: set fan-out accepts and
//// membership leaves both settle pending proposals through the shared harness.

import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  ClientOperation, Deliver, Disconnect, Sequence, Synchronize,
}
import watershed/fuzz/pact_map_model.{CommandSet}
import watershed/fuzz/script_gen

const client_count = 3

fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    add_client: 2,
    reconnect: 0,
    rollback_operation: 0,
    stashed_operation: 0,
  )
}

pub fn converges_and_matches_oracle_test() -> Nil {
  let model = pact_map_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_environment(),
    client_count,
    script_gen.script_generator(model.gen_operation, client_count, weights()),
  )
}

pub fn set_fans_out_accepts_and_settles_test() -> Nil {
  let script = [
    ClientOperation(1, CommandSet("a", Some(json.int(1)), 0)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(pact_map_model.model(), client_count, script)
  |> expect.to_be_ok
}

pub fn leave_can_settle_pending_proposal_test() -> Nil {
  let script = [
    ClientOperation(1, CommandSet("a", Some(json.int(1)), 0)),
    Sequence(1),
    Deliver(0, 1),
    Deliver(1, 1),
    Disconnect(2),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(pact_map_model.model(), client_count, script)
  |> expect.to_be_ok
}

pub fn operation_json_round_trips_test() -> Nil {
  let model = pact_map_model.model()
  [
    CommandSet("a", Some(json.int(1)), 7),
    CommandSet("b", None, 8),
  ]
  |> list.each(fn(command) {
    let assert Ok(decoded) =
      json.parse(
        json.to_string(model.operation_to_json(command)),
        model.operation_decoder,
      )
    decoded |> expect.to_equal(command)
  })
}

//// Fuzz coverage for PactMap's quorum protocol: set fan-out accepts and
//// membership leaves both settle pending proposals through the shared harness.

import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  ClientOp, Deliver, Disconnect, Sequence, Synchronize,
}
import watershed/fuzz/pact_map_model.{CmdSet}
import watershed/fuzz/script_gen

const client_count = 3

fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    add_client: 2,
    reconnect: 0,
    rollback_op: 0,
    stashed_op: 0,
  )
}

pub fn converges_and_matches_oracle_test() {
  let model = pact_map_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_op, client_count, weights()),
  )
}

pub fn set_fans_out_accepts_and_settles_test() {
  let script = [
    ClientOp(1, CmdSet("a", Some(json.int(1)), 0)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(pact_map_model.model(), client_count, script)
  |> expect.to_be_ok
}

pub fn leave_can_settle_pending_proposal_test() {
  let script = [
    ClientOp(1, CmdSet("a", Some(json.int(1)), 0)),
    Sequence(1),
    Deliver(0, 1),
    Deliver(1, 1),
    Disconnect(2),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(pact_map_model.model(), client_count, script)
  |> expect.to_be_ok
}

pub fn op_json_round_trips_test() {
  let model = pact_map_model.model()
  [
    CmdSet("a", Some(json.int(1)), 7),
    CmdSet("b", None, 8),
  ]
  |> list.each(fn(cmd) {
    let assert Ok(decoded) =
      json.parse(json.to_string(model.op_to_json(cmd)), model.op_decoder)
    decoded |> expect.to_equal(cmd)
  })
}

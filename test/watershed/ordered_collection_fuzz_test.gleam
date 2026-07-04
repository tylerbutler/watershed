//// Fuzz coverage for the ordered collection kernel. The model exercises the
//// consensus-harness extensions: local acquire reactions emit complete/release,
//// and disconnects sequence membership leaves that re-release held jobs.

import gleam/json
import gleam/list
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  AddClient, ClientOp, Deliver, Disconnect, Sequence, Synchronize,
}
import watershed/fuzz/ordered_collection_model.{
  CmdAcquire, CmdAdd, CompleteAfterAcquire, ReleaseAfterAcquire,
}
import watershed/fuzz/script_gen

const client_count = 3

fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    add_client: 2,
    rollback_op: 3,
    stashed_op: 3,
  )
}

pub fn converges_and_matches_oracle_test() {
  let model = ordered_collection_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_op, client_count, weights()),
  )
}

pub fn acquire_complete_reaction_converges_test() {
  let script = [
    ClientOp(1, CmdAdd(1, 0)),
    Synchronize,
    ClientOp(1, CmdAcquire(1, "", CompleteAfterAcquire)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    ordered_collection_model.model(),
    client_count,
    script,
  )
  |> expect.to_be_ok
}

pub fn acquire_release_reaction_returns_item_test() {
  let script = [
    ClientOp(1, CmdAdd(1, 0)),
    Synchronize,
    ClientOp(1, CmdAcquire(1, "", ReleaseAfterAcquire)),
    Synchronize,
    ClientOp(2, CmdAcquire(2, "", CompleteAfterAcquire)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    ordered_collection_model.model(),
    client_count,
    script,
  )
  |> expect.to_be_ok
}

pub fn disconnect_rereleases_held_item_test() {
  let script = [
    ClientOp(1, CmdAdd(1, 0)),
    Synchronize,
    ClientOp(1, CmdAcquire(1, "", CompleteAfterAcquire)),
    Sequence(1),
    Deliver(1, 1),
    Disconnect(1),
    Synchronize,
    ClientOp(2, CmdAcquire(2, "", CompleteAfterAcquire)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    ordered_collection_model.model(),
    client_count,
    script,
  )
  |> expect.to_be_ok
}

pub fn add_client_summary_round_trip_preserves_observed_state_test() {
  let script = [
    ClientOp(1, CmdAdd(1, 0)),
    Synchronize,
    AddClient,
    ClientOp(2, CmdAcquire(2, "", CompleteAfterAcquire)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    ordered_collection_model.model(),
    client_count,
    script,
  )
  |> expect.to_be_ok
}

pub fn op_json_round_trips_test() {
  let model = ordered_collection_model.model()
  [
    CmdAdd(1, 1001),
    CmdAcquire(2, "1:2", CompleteAfterAcquire),
    CmdAcquire(3, "1:3", ReleaseAfterAcquire),
  ]
  |> list.each(fn(cmd) {
    let assert Ok(decoded) =
      json.parse(json.to_string(model.op_to_json(cmd)), model.op_decoder)
    decoded |> expect.to_equal(cmd)
  })
}

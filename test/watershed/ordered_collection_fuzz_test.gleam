//// Fuzz coverage for the ordered collection kernel. The model exercises the
//// consensus-harness extensions: local acquire reactions emit complete/release,
//// and disconnects sequence membership leaves that re-release held jobs.

import gleam/json
import gleam/list
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  AddClient, ClientOperation, Deliver, Disconnect, Sequence, Synchronize,
}
import watershed/fuzz/ordered_collection_model.{
  CommandAcquire, CommandAdd, CompleteAfterAcquire, ReleaseAfterAcquire,
}
import watershed/fuzz/script_gen

const client_count = 3

fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    add_client: 2,
    rollback_operation: 3,
    stashed_operation: 3,
  )
}

pub fn converges_and_matches_oracle_test() -> Nil {
  let model = ordered_collection_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_operation, client_count, weights()),
  )
}

pub fn acquire_complete_reaction_converges_test() -> Nil {
  let script = [
    ClientOperation(1, CommandAdd(1, 0)),
    Synchronize,
    ClientOperation(1, CommandAcquire(1, "", CompleteAfterAcquire)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    ordered_collection_model.model(),
    client_count,
    script,
  )
  |> expect.to_be_ok
}

pub fn acquire_release_reaction_returns_item_test() -> Nil {
  let script = [
    ClientOperation(1, CommandAdd(1, 0)),
    Synchronize,
    ClientOperation(1, CommandAcquire(1, "", ReleaseAfterAcquire)),
    Synchronize,
    ClientOperation(2, CommandAcquire(2, "", CompleteAfterAcquire)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    ordered_collection_model.model(),
    client_count,
    script,
  )
  |> expect.to_be_ok
}

pub fn disconnect_rereleases_held_item_test() -> Nil {
  let script = [
    ClientOperation(1, CommandAdd(1, 0)),
    Synchronize,
    ClientOperation(1, CommandAcquire(1, "", CompleteAfterAcquire)),
    Sequence(1),
    Deliver(1, 1),
    Disconnect(1),
    Synchronize,
    ClientOperation(2, CommandAcquire(2, "", CompleteAfterAcquire)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    ordered_collection_model.model(),
    client_count,
    script,
  )
  |> expect.to_be_ok
}

pub fn add_client_summary_round_trip_preserves_observed_state_test() -> Nil {
  let script = [
    ClientOperation(1, CommandAdd(1, 0)),
    Synchronize,
    AddClient,
    ClientOperation(2, CommandAcquire(2, "", CompleteAfterAcquire)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    ordered_collection_model.model(),
    client_count,
    script,
  )
  |> expect.to_be_ok
}

pub fn operation_json_round_trips_test() -> Nil {
  let model = ordered_collection_model.model()
  [
    CommandAdd(1, 1001),
    CommandAcquire(2, "1:2", CompleteAfterAcquire),
    CommandAcquire(3, "1:3", ReleaseAfterAcquire),
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

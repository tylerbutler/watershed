//// Unit tests for `script_gen` (F1): proves the generated command scripts
//// respect the binding design invariant that client 0 never authors ops
//// ("Client 0 never authors ops; it doubles as the observer and the
//// summary source for `AddClient`" — see the plan's steal table).

import gleam/list
import qcheck
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  AddClient, ClientOp, Disconnect, Reconnect, RollbackOp, StashedOp,
}
import watershed/fuzz/script_gen.{Weights}

fn config() -> qcheck.Config {
  qcheck.default_config() |> qcheck.with_test_count(500)
}

/// `AddClient` (F2) is one of the command kinds `command_generator` can
/// produce: with all weight on `add_client`, every draw must be `AddClient`.
pub fn command_generator_can_produce_add_client_test() {
  let op_generator = qcheck.bounded_int(from: -5, to: 5)
  let weights =
    Weights(
      client_op: 0,
      sequence: 0,
      deliver: 0,
      synchronize: 0,
      add_client: 1,
      disconnect: 0,
      reconnect: 0,
      rollback_op: 0,
      stashed_op: 0,
    )

  qcheck.run(
    config(),
    script_gen.command_generator(op_generator, 2, weights),
    fn(command) { command |> expect.to_equal(AddClient) },
  )
}

/// No generated `ClientOp`/`Disconnect`/`Reconnect`/`RollbackOp`/`StashedOp`
/// ever names client 0, for any supported client_count (>= 2, the minimum
/// needed for client 0 to have someone to observe). Uses non-default
/// weights so `rollback_op`/`stashed_op` (0 by default) are actually
/// exercised by this check.
pub fn generated_scripts_never_author_from_client_zero_test() {
  let op_generator = qcheck.bounded_int(from: -5, to: 5)
  let weights =
    Weights(..script_gen.default_weights(), rollback_op: 10, stashed_op: 10)

  list.each([2, 3, 5], fn(client_count) {
    qcheck.run(
      config(),
      script_gen.script_generator(op_generator, client_count, weights),
      fn(script) {
        list.each(script, fn(command) {
          case command {
            ClientOp(0, _) ->
              panic as "generated script authored an op from client 0"
            Disconnect(0) -> panic as "generated script disconnected client 0"
            Reconnect(0) -> panic as "generated script reconnected client 0"
            RollbackOp(0, _) ->
              panic as "generated script rolled back an op from client 0"
            StashedOp(0, _) ->
              panic as "generated script stashed an op from client 0"
            _ -> Nil
          }
        })
      },
    )
  })
}

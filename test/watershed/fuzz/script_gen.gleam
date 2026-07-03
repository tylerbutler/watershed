//// Command-script generators for the fuzz harness, with one weight config
//// record per suite. Scripts are lists of `Command` values built from small
//// ints so qcheck shrinks them like any other data: a failing 80-command
//// script minimizes to the shortest prefix/subset that still fails.

import qcheck
import watershed/fuzz/kernel_fuzz.{
  type Command, AddClient, ClientOp, Deliver, Disconnect, Reconnect, RollbackOp,
  Sequence, StashedOp, Synchronize,
}

/// Relative weights for each command kind. Op-heavy, sync ~5%, mirroring
/// upstream's default `probability: 0.05` for a full sync. `add_client` is
/// kept small: joining a client is rare relative to steady-state op
/// traffic. `rollback_op`/`stashed_op` default to 0: they require
/// capabilities (`counter` has both, `map` has neither today), so a suite
/// must opt in explicitly rather than the harness silently generating
/// commands a model can't service.
pub type Weights {
  Weights(
    client_op: Int,
    sequence: Int,
    deliver: Int,
    synchronize: Int,
    add_client: Int,
    disconnect: Int,
    reconnect: Int,
    rollback_op: Int,
    stashed_op: Int,
  )
}

pub fn default_weights() -> Weights {
  Weights(
    client_op: 70,
    sequence: 15,
    deliver: 15,
    synchronize: 5,
    add_client: 3,
    disconnect: 4,
    reconnect: 4,
    rollback_op: 0,
    stashed_op: 0,
  )
}

/// The max ops moved inbox → log or delivered to one client in a single
/// `Sequence`/`Deliver` command. Kept small so the interpreter takes many
/// commands to catch up fully, which is what makes the inbox/log window
/// (and its bugs) reachable.
const max_batch = 4

/// Client 0 never authors ops: it's the read-only observer and the
/// summary source for `AddClient` (F2). `ClientOp` is only ever generated
/// for clients 1..client_count - 1, which is why `script_generator`
/// requires `client_count >= 2` — otherwise there would be no authoring
/// client left to generate. Any `Int` the shrinker tries still lands in
/// range via modulo, same trick as `client_index` in the interpreter.
fn client_op_generator(
  op_generator: qcheck.Generator(op),
  client_count: Int,
) -> qcheck.Generator(Command(op)) {
  qcheck.tuple2(qcheck.small_non_negative_int(), op_generator)
  |> qcheck.map(fn(pair) { ClientOp(1 + pair.0 % { client_count - 1 }, pair.1) })
}

fn sequence_generator() -> qcheck.Generator(Command(op)) {
  qcheck.bounded_int(from: 0, to: max_batch) |> qcheck.map(Sequence)
}

fn deliver_generator(client_count: Int) -> qcheck.Generator(Command(op)) {
  qcheck.tuple2(
    qcheck.small_non_negative_int(),
    qcheck.bounded_int(from: 0, to: max_batch),
  )
  |> qcheck.map(fn(pair) { Deliver(pair.0 % client_count, pair.1) })
}

/// Client index generator shared by `Disconnect`/`Reconnect` — same
/// non-authoring-client-0 convention as `client_op_generator`, since
/// client 0 must stay a connected, always-available summary source for
/// `AddClient`.
fn client_index_generator(client_count: Int) -> qcheck.Generator(Int) {
  qcheck.small_non_negative_int()
  |> qcheck.map(fn(n) { 1 + n % { client_count - 1 } })
}

fn disconnect_generator(client_count: Int) -> qcheck.Generator(Command(op)) {
  client_index_generator(client_count) |> qcheck.map(Disconnect)
}

fn reconnect_generator(client_count: Int) -> qcheck.Generator(Command(op)) {
  client_index_generator(client_count) |> qcheck.map(Reconnect)
}

fn rollback_op_generator(
  op_generator: qcheck.Generator(op),
  client_count: Int,
) -> qcheck.Generator(Command(op)) {
  qcheck.tuple2(client_index_generator(client_count), op_generator)
  |> qcheck.map(fn(pair) { RollbackOp(pair.0, pair.1) })
}

fn stashed_op_generator(
  op_generator: qcheck.Generator(op),
  client_count: Int,
) -> qcheck.Generator(Command(op)) {
  qcheck.tuple2(client_index_generator(client_count), op_generator)
  |> qcheck.map(fn(pair) { StashedOp(pair.0, pair.1) })
}

/// A single-command generator drawing from all F1/F2/F3 command kinds,
/// weighted per `weights`. Requires `client_count >= 2`: client 0 never
/// authors ops (see `client_op_generator`), so at least one other client
/// must exist to generate `ClientOp`/`Disconnect`/`Reconnect`/`RollbackOp`/
/// `StashedOp` commands from. A model without `rollback`/`apply_stashed`
/// capabilities should be wired with `rollback_op: 0`/`stashed_op: 0`
/// (see `default_weights`) rather than relying on the interpreter's error
/// path to no-op a generated-but-unsupported command.
pub fn command_generator(
  op_generator: qcheck.Generator(op),
  client_count: Int,
  weights: Weights,
) -> qcheck.Generator(Command(op)) {
  qcheck.from_weighted_generators(
    #(weights.client_op, client_op_generator(op_generator, client_count)),
    [
      #(weights.sequence, sequence_generator()),
      #(weights.deliver, deliver_generator(client_count)),
      #(weights.synchronize, qcheck.constant(Synchronize)),
      #(weights.add_client, qcheck.constant(AddClient)),
      #(weights.disconnect, disconnect_generator(client_count)),
      #(weights.reconnect, reconnect_generator(client_count)),
      #(weights.rollback_op, rollback_op_generator(op_generator, client_count)),
      #(weights.stashed_op, stashed_op_generator(op_generator, client_count)),
    ],
  )
}

/// A full script generator: a list of commands drawn from `command_generator`.
/// `client_count` must be >= 2 (client 0 is a non-authoring observer).
pub fn script_generator(
  op_generator: qcheck.Generator(op),
  client_count: Int,
  weights: Weights,
) -> qcheck.Generator(List(Command(op))) {
  qcheck.generic_list(
    command_generator(op_generator, client_count, weights),
    qcheck.small_non_negative_int(),
  )
}

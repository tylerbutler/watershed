import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  type Command, type KernelModel, AddClient, Capabilities, ClientOperation,
  Deliver, Disconnect, KernelModel, LeaveEntry, OperationEntry, Reconnect,
  RollbackOperation, Sequence, StashedOperation, SubmitMeta, Synchronize,
}
import watershed/fuzz/lww_register_model.{
  type LwwCommand, type Observation, LwwCommand, Observation,
}
import watershed/fuzz/script_gen
import watershed/lww_register_kernel as kernel

type Model =
  KernelModel(kernel.LwwRegisterState, LwwCommand, Observation)

const client_count = 3

fn write(value: String, wall_clock: Int) -> LwwCommand {
  LwwCommand(value, wall_clock, None, None)
}

fn captured_write(
  model: Model,
  client: Int,
  value: String,
  wall_clock: Int,
) -> LwwCommand {
  let #(_, routed) =
    model.submit(
      model.init(client),
      write(value, wall_clock),
      SubmitMeta(client, 0),
    )
  let assert Some(command) = routed
  command
}

pub fn lww_register_generated_convergence_test() -> Nil {
  let model = lww_register_model.model()
  let weights =
    script_gen.Weights(
      ..script_gen.default_weights(),
      rollback_operation: 8,
      stashed_operation: 8,
    )
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_environment(),
    client_count,
    script_gen.script_generator(model.gen_operation, client_count, weights),
  )
}

pub fn lww_register_operation_json_round_trip_test() -> Nil {
  let model = lww_register_model.model()
  let assert Ok(#(_, _, kernel.Set(value, timestamp, delta), _)) =
    kernel.set(kernel.new(replica_id.new("client-1")), "ready", 7)

  [
    write("", 0),
    LwwCommand(value, 7, Some(timestamp), Some(delta)),
    LwwCommand(value, 0, Some(timestamp), Some(delta)),
  ]
  |> list.each(fn(command) {
    json.parse(
      model.operation_to_json(command) |> json.to_string,
      model.operation_decoder,
    )
    |> expect.to_equal(Ok(command))
  })
}

pub fn lww_register_operation_json_rejects_invalid_slots_test() -> Nil {
  let model = lww_register_model.model()
  [
    "{\"value\":\"x\",\"wall_clock\":0,\"timestamp\":1,\"delta\":\"not json\"}",
    "{\"value\":\"x\",\"wall_clock\":0,\"timestamp\":1,\"delta\":\"{}\"}",
    "{\"value\":\"x\",\"wall_clock\":0,\"timestamp\":1,\"delta\":null}",
    "{\"value\":\"x\",\"wall_clock\":0,\"timestamp\":null,\"delta\":\"{}\"}",
  ]
  |> list.each(fn(encoded) {
    json.parse(encoded, model.operation_decoder)
    |> result.is_error
    |> expect.to_be_true()
  })
  let filled = captured_write(model, 1, "x", 0)
  [
    LwwCommand(..filled, timestamp: None),
    LwwCommand(..filled, delta: None),
  ]
  |> list.each(fn(command) {
    json.parse(
      model.operation_to_json(command) |> json.to_string,
      model.operation_decoder,
    )
    |> result.is_error
    |> expect.to_be_true()
  })
}

pub fn lww_register_observation_includes_pending_metadata_test() -> Nil {
  let model = lww_register_model.model()
  model.observe(model.init(1)) |> expect.to_equal(Observation("", 0, ""))
  let assert Ok(#(state, events, _, _)) = kernel.set(model.init(1), "", 0)
  events |> expect.to_equal([])
  model.observe(state) |> expect.to_equal(Observation("", 1, "client-1"))
}

pub fn lww_register_oracle_tracks_metadata_only_writes_test() -> Nil {
  let model = lww_register_model.model()
  let assert Some(oracle) = model.capabilities.oracle
  // No delta is available to this oracle. Log authors supply the tie-breaker.
  let first = OperationEntry(2, LwwCommand("same", 99, Some(7), None), [])
  let second = OperationEntry(1, LwwCommand("same", 0, Some(8), None), [])
  let tied = OperationEntry(2, LwwCommand("same", 0, Some(8), None), [])
  oracle([]) |> expect.to_equal(Observation("", 0, ""))
  oracle([first]) |> expect.to_equal(Observation("same", 7, "client-2"))
  oracle([first, second])
  |> expect.to_equal(Observation("same", 8, "client-1"))
  [first, second, tied, LeaveEntry(2)]
  |> list.permutations
  |> list.each(fn(entries) {
    oracle(entries) |> expect.to_equal(Observation("same", 8, "client-2"))
  })
  // Replica IDs compare as strings, not as client index numbers.
  oracle([
    OperationEntry(10, LwwCommand("ten", 0, Some(8), None), []),
    tied,
  ])
  |> expect.to_equal(Observation("same", 8, "client-2"))
}

pub fn lww_register_value_only_observation_fails_the_oracle_test() -> Nil {
  let model = lww_register_model.model()
  let script = [
    ClientOperation(1, write("", 0)),
    ClientOperation(2, write("", 0)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(model, client_count, script)
  |> expect.to_equal(Ok(Nil))
  let buggy =
    KernelModel(..model, observe: fn(state) {
      Observation(kernel.value(state), 0, "")
    })
  let assert Error(detail) =
    kernel_fuzz.try_run_script(buggy, client_count, script)
  string.contains(detail, "oracle mismatch") |> expect.to_be_true()
}

/// A literal final observation also detects causal errors that converge.
/// These scripts have no intermediate Synchronize command.
fn with_final_observation(model: Model, expected: Observation) -> Model {
  KernelModel(
    ..model,
    capabilities: Capabilities(
      ..model.capabilities,
      oracle: Some(fn(_) { expected }),
    ),
  )
}

fn expect_script(
  model: Model,
  script: List(Command(LwwCommand)),
  expected: Observation,
) -> Nil {
  kernel_fuzz.try_run_script(model, client_count, script)
  |> expect.to_equal(Ok(Nil))
  kernel_fuzz.try_run_script(
    with_final_observation(model, expected),
    client_count,
    script,
  )
  |> expect.to_equal(Ok(Nil))
}

/// AddClient joins are read-only in the harness. Reload an active writer
/// through the same capability to test its first write after a summary load.
fn reload_second_writer(model: Model) -> Model {
  let assert Some(load) = model.capabilities.load_from_synced
  KernelModel(..model, submit: fn(state, command, meta: kernel_fuzz.SubmitMeta) {
    let state = case meta.client_id {
      2 -> load(state, 2)
      _ -> state
    }
    model.submit(state, command, meta)
  })
}

fn reload_script() -> List(Command(LwwCommand)) {
  [
    ClientOperation(1, write("before", 100)),
    Sequence(1),
    Deliver(0, 1),
    Deliver(1, 1),
    Deliver(2, 1),
    AddClient,
    ClientOperation(2, write("after", 0)),
  ]
}

pub fn lww_register_causal_scripts_test() -> Nil {
  let model = lww_register_model.model()
  let replay = captured_write(model, 1, "old", 7)
  [
    #(
      [
        ClientOperation(1, write("a", 7)),
        ClientOperation(2, write("b", 7)),
        Sequence(2),
        Deliver(1, 2),
        Deliver(2, 2),
      ],
      Observation("b", 7, "client-2"),
    ),
    #(
      [
        ClientOperation(2, write("b", 7)),
        ClientOperation(1, write("a", 7)),
        Sequence(2),
        Deliver(2, 2),
        Deliver(1, 2),
      ],
      Observation("b", 7, "client-2"),
    ),
    #(
      [
        ClientOperation(1, write("same", 7)),
        ClientOperation(1, write("same", 7)),
      ],
      Observation("same", 8, "client-1"),
    ),
    #(
      [
        ClientOperation(1, write("pending", 1)),
        RollbackOperation(1, write("discarded", 100)),
        ClientOperation(1, write("after", 0)),
      ],
      Observation("after", 101, "client-1"),
    ),
    #(
      [
        ClientOperation(1, write("new", 100)),
        StashedOperation(1, replay),
      ],
      Observation("new", 100, "client-1"),
    ),
    #(
      [
        ClientOperation(1, write("new", 100)),
        StashedOperation(1, write("old", 7)),
      ],
      Observation("new", 100, "client-1"),
    ),
    #(
      [
        StashedOperation(1, replay),
        ClientOperation(1, write("after", 0)),
      ],
      Observation("after", 8, "client-1"),
    ),
    #(
      [
        StashedOperation(1, write("", 0)),
        StashedOperation(1, write("", 0)),
      ],
      Observation("", 0, "client-1"),
    ),
    #(
      [
        ClientOperation(1, write("in-flight", 7)),
        Disconnect(1),
        ClientOperation(1, write("offline", 0)),
        ClientOperation(2, write("online", 100)),
        Sequence(1),
        Deliver(1, 1),
        Reconnect(1),
      ],
      Observation("online", 100, "client-2"),
    ),
    #(
      [
        ClientOperation(1, write("confirmed", 7)),
        Sequence(1),
        AddClient,
        ClientOperation(2, write("later", 8)),
        AddClient,
      ],
      Observation("later", 8, "client-2"),
    ),
    #(
      [StashedOperation(1, replay), StashedOperation(1, replay)],
      Observation("old", 7, "client-1"),
    ),
  ]
  |> list.each(fn(test_case) { expect_script(model, test_case.0, test_case.1) })
  expect_script(
    reload_second_writer(model),
    reload_script(),
    Observation("after", 101, "client-2"),
  )
}

pub fn lww_register_generated_stash_preserves_captured_timestamp_test() -> Nil {
  let model = lww_register_model.model()
  let assert Some(apply_stashed) = model.capabilities.apply_stashed
  [7, 0]
  |> list.each(fn(captured_timestamp) {
    let generated = write("old", captured_timestamp)
    let #(state, _) =
      model.submit(model.init(1), write("new", 100), SubmitMeta(1, 0))
    state.last_seen |> expect.to_equal(100)

    let #(state, routed) = apply_stashed(state, generated, SubmitMeta(1, 0))
    routed.timestamp |> expect.to_equal(Some(captured_timestamp))
    routed.wall_clock |> expect.to_equal(captured_timestamp)
    routed.value |> expect.to_equal("old")
    let assert Some(delta) = routed.delta
    let assert Ok(original) =
      kernel.from_sequenced(delta, replica_id.new("observer"))
    model.observe(original)
    |> expect.to_equal(Observation("old", captured_timestamp, "client-1"))
    let assert Ok(pending) = list.last(state.pending)
    pending.operation
    |> expect.to_equal(kernel.Set("old", captured_timestamp, delta))
    list.length(state.pending) |> expect.to_equal(2)
    state.last_seen |> expect.to_equal(100)
    model.observe(state)
    |> expect.to_equal(Observation("new", 100, "client-1"))
    json.parse(
      model.operation_to_json(routed) |> json.to_string,
      model.operation_decoder,
    )
    |> expect.to_equal(Ok(routed))
  })
}

pub fn lww_register_stash_replays_the_original_command_test() -> Nil {
  let model = lww_register_model.model()
  let assert Some(apply_stashed) = model.capabilities.apply_stashed
  let original = LwwCommand(..captured_write(model, 1, "old", 7), wall_clock: 0)
  let #(state, _) =
    model.submit(model.init(1), write("new", 100), SubmitMeta(1, 0))
  let #(state, replayed) = apply_stashed(state, original, SubmitMeta(1, 0))
  replayed |> expect.to_equal(original)
  state.last_seen |> expect.to_equal(100)
  let assert Ok(pending) = list.last(state.pending)
  pending.operation.timestamp |> expect.to_equal(7)
  model.observe(state) |> expect.to_equal(Observation("new", 100, "client-1"))
}

pub fn lww_register_script_json_round_trip_test() -> Nil {
  let model = lww_register_model.model()
  let script = [
    StashedOperation(1, captured_write(model, 1, "old", 7)),
    StashedOperation(1, write("generated", 3)),
    ClientOperation(2, write("new", 0)),
    Disconnect(1),
    Reconnect(1),
    Sequence(2),
    Deliver(0, 1),
    RollbackOperation(2, write("discarded", 100)),
    AddClient,
    Synchronize,
  ]
  let assert Ok(decoded) =
    json.parse(
      kernel_fuzz.script_to_json(model.operation_to_json, script)
        |> json.to_string,
      kernel_fuzz.script_decoder(model.operation_decoder),
    )
  decoded |> expect.to_equal(script)
  kernel_fuzz.try_run_script(model, client_count, decoded)
  |> expect.to_equal(Ok(Nil))
}

pub fn lww_register_winner_author_reuse_fails_the_harness_test() -> Nil {
  let model = lww_register_model.model()
  let buggy =
    KernelModel(
      ..model,
      capabilities: Capabilities(
        ..model.capabilities,
        load_from_synced: Some(fn(state, _) {
          let assert Ok(loaded) =
            kernel.from_summary(
              kernel.summary(state) |> json.to_string,
              replica_id.new(model.observe(state).author),
            )
          loaded
        }),
      ),
    )
  let script = reload_script()
  expect_script(
    reload_second_writer(model),
    script,
    Observation("after", 101, "client-2"),
  )
  let assert Error(detail) =
    kernel_fuzz.try_run_script(
      reload_second_writer(buggy),
      client_count,
      script,
    )
  string.contains(detail, "oracle mismatch") |> expect.to_be_true()
}

pub fn lww_register_clock_reset_fails_the_harness_test() -> Nil {
  let model = lww_register_model.model()
  let assert Some(load) = model.capabilities.load_from_synced
  let buggy =
    KernelModel(
      ..model,
      capabilities: Capabilities(
        ..model.capabilities,
        load_from_synced: Some(fn(state, id) {
          kernel.LwwRegisterState(..load(state, id), last_seen: 0)
        }),
      ),
    )
  let expected = Observation("after", 101, "client-2")
  let script = reload_script()
  expect_script(reload_second_writer(model), script, expected)
  // A stale timestamp can lose on every replica and still match the log
  // oracle. The causal script must require the imported clock to advance.
  let assert Error(detail) =
    kernel_fuzz.try_run_script(
      with_final_observation(reload_second_writer(buggy), expected),
      client_count,
      script,
    )
  string.contains(detail, "oracle mismatch") |> expect.to_be_true()
}

import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_maps/lww_map
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  type Command, type KernelModel, AddClient, Capabilities, ClientOperation,
  Deliver, Disconnect, KernelModel, OperationEntry, Reconnect, RollbackOperation,
  Sequence, StashedOperation, SubmitMeta, Synchronize,
}
import watershed/fuzz/lww_map_model.{type MapCommand, MapCommand}
import watershed/fuzz/script_gen
import watershed/lww_map_kernel as kernel

type Observation =
  List(#(String, Option(String), Int))

type Model =
  KernelModel(kernel.LwwMapState, MapCommand, Observation)

fn edit(key: String, value: Option(String), wall_clock: Int) -> MapCommand {
  MapCommand(key, value, wall_clock, None, None)
}

fn with_expected(model: Model, expected: Observation) -> Model {
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
  script: List(Command(MapCommand)),
  expected: Observation,
) -> Nil {
  kernel_fuzz.try_run_script(model, 3, script)
  |> expect.to_equal(Ok(Nil))
  kernel_fuzz.try_run_script(with_expected(model, expected), 3, script)
  |> expect.to_equal(Ok(Nil))
}

pub fn lww_map_oracle_uses_intent_not_lattice_merge_test() -> Nil {
  let assert Some(oracle) = lww_map_model.model().capabilities.oracle
  let a = OperationEntry(1, MapCommand("k", Some("a"), 0, Some(10), None), [])
  let b = OperationEntry(2, MapCommand("k", Some("b"), 0, Some(10), None), [])
  let removed = OperationEntry(1, MapCommand("k", None, 0, Some(10), None), [])
  oracle([]) |> expect.to_equal([])
  [a, b]
  |> list.permutations
  |> list.each(fn(entries) {
    oracle(entries) |> expect.to_equal([#("k", Some("b"), 10)])
  })
  [a, b, removed, removed]
  |> list.permutations
  |> list.each(fn(entries) {
    oracle(entries) |> expect.to_equal([#("k", None, 10)])
  })
  oracle([
    removed,
    OperationEntry(2, MapCommand("k", Some(""), 0, Some(11), None), []),
    OperationEntry(1, MapCommand("a", None, 0, Some(1), None), []),
  ])
  |> expect.to_equal([#("a", None, 1), #("k", Some(""), 11)])
}

pub fn lww_map_observation_includes_pending_tombstones_test() -> Nil {
  let model = lww_map_model.model()
  let assert Ok(#(state, events, _, _)) =
    kernel.remove(model.init(1), "missing", 7)
  events |> expect.to_equal([])
  model.observe(state) |> expect.to_equal([#("missing", None, 7)])
  kernel.sequenced_entries(state) |> expect.to_equal([])
}

pub fn lww_map_oracle_unicode_order_is_target_independent_test() -> Nil {
  let assert Some(oracle) = lww_map_model.model().capabilities.oracle
  let a =
    OperationEntry(1, MapCommand("k", Some("\u{e000}"), 0, Some(10), None), [])
  let b =
    OperationEntry(2, MapCommand("k", Some("\u{10000}"), 0, Some(10), None), [])
  oracle([a, b]) |> expect.to_equal([#("k", Some("\u{10000}"), 10)])
  oracle([b, a]) |> expect.to_equal([#("k", Some("\u{10000}"), 10)])
}

pub fn lww_map_generated_convergence_test() -> Nil {
  let model = lww_map_model.model()
  let weights =
    script_gen.Weights(
      ..script_gen.default_weights(),
      rollback_operation: 8,
      stashed_operation: 8,
    )
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_environment(),
    3,
    script_gen.script_generator(model.gen_operation, 3, weights),
  )
}

pub fn lww_map_causal_scripts_test() -> Nil {
  let model = lww_map_model.model()
  [
    #(
      [
        ClientOperation(1, edit("k", Some("open"), 8)),
        ClientOperation(2, edit("k", Some("closed"), 7)),
        Sequence(2),
        Deliver(1, 2),
        Deliver(2, 2),
      ],
      [#("k", Some("open"), 8)],
    ),
    #(
      [
        ClientOperation(1, edit("k", None, 7)),
        ClientOperation(2, edit("k", Some("open"), 7)),
      ],
      [#("k", None, 7)],
    ),
    #(
      [
        ClientOperation(1, edit("k", Some("same"), 7)),
        ClientOperation(1, edit("k", Some("same"), 0)),
      ],
      [#("k", Some("same"), 8)],
    ),
    #(
      [
        ClientOperation(1, edit("k", Some("pending"), 7)),
        RollbackOperation(1, edit("k", None, 100)),
        ClientOperation(1, edit("k", Some("after"), 0)),
        ClientOperation(1, edit("a", Some("independent"), 0)),
      ],
      [#("a", Some("independent"), 1), #("k", Some("after"), 101)],
    ),
    #(
      [
        ClientOperation(1, edit("k", Some("new"), 100)),
        StashedOperation(1, edit("k", None, 7)),
        StashedOperation(1, edit("k", None, 7)),
      ],
      [#("k", Some("new"), 100)],
    ),
    #(
      [
        StashedOperation(1, edit("k", None, 7)),
        ClientOperation(1, edit("k", Some("restored"), 0)),
      ],
      [#("k", Some("restored"), 8)],
    ),
    #(
      [
        ClientOperation(1, edit("k", Some("in-flight"), 7)),
        Disconnect(1),
        ClientOperation(1, edit("k", Some("offline"), 0)),
        ClientOperation(2, edit("k", None, 100)),
        Sequence(1),
        Deliver(1, 1),
        Reconnect(1),
        AddClient,
      ],
      [#("k", None, 100)],
    ),
  ]
  |> list.each(fn(example) { expect_script(model, example.0, example.1) })
}

pub fn lww_map_stash_retains_captured_time_test() -> Nil {
  let model = lww_map_model.model()
  let assert Some(stash) = model.capabilities.apply_stashed
  let #(state, _) =
    model.submit(model.init(1), edit("k", Some("new"), 100), SubmitMeta(1, 0))
  let #(state, routed) = stash(state, edit("k", None, 7), SubmitMeta(1, 0))
  routed.timestamp |> expect.to_equal(Some(7))
  model.observe(state) |> expect.to_equal([#("k", Some("new"), 100)])
  dict.get(state.last_seen, "k") |> expect.to_equal(Ok(100))
  let #(state, replayed) =
    stash(state, MapCommand(..routed, wall_clock: 0), SubmitMeta(1, 0))
  replayed.timestamp |> expect.to_equal(Some(7))
  model.observe(state) |> expect.to_equal([#("k", Some("new"), 100)])
}

pub fn lww_map_command_and_script_json_round_trip_test() -> Nil {
  let model = lww_map_model.model()
  let #(_, captured) =
    model.submit(model.init(1), edit("k", None, 7), SubmitMeta(1, 0))
  let assert Some(captured) = captured
  let script = [
    StashedOperation(1, captured),
    ClientOperation(2, edit("k", Some(""), 0)),
    RollbackOperation(2, edit("a", None, 100)),
    Disconnect(1),
    Reconnect(1),
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
  kernel_fuzz.try_run_script(model, 3, decoded)
  |> expect.to_equal(Ok(Nil))
  [
    MapCommand(..captured, timestamp: None),
    MapCommand(..captured, delta: None),
    MapCommand(..captured, key: "different"),
    MapCommand(..captured, value: Some("not removed")),
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

pub fn lww_map_left_biased_merge_fault_is_detected_test() -> Nil {
  let model = lww_map_model.model()
  let buggy =
    KernelModel(
      ..model,
      apply_remote: fn(state: kernel.LwwMapState, command: MapCommand, meta) {
        case dict.get(state.last_seen, command.key), command.timestamp {
          Ok(seen), Some(timestamp) if seen == timestamp -> Ok(state)
          _, _ -> model.apply_remote(state, command, meta)
        }
      },
    )
  let script = [
    ClientOperation(1, edit("k", Some("open"), 7)),
    ClientOperation(2, edit("k", Some("closed"), 7)),
    Synchronize,
  ]
  expect_script(model, script, [#("k", Some("open"), 7)])
  let assert Error(detail) = kernel_fuzz.try_run_script(buggy, 3, script)
  string.contains(detail, "convergence violated") |> expect.to_be_true()
}

pub fn lww_map_dropped_tombstone_on_reload_is_detected_test() -> Nil {
  let model = lww_map_model.model()
  let buggy =
    KernelModel(
      ..model,
      capabilities: Capabilities(
        ..model.capabilities,
        load_from_synced: Some(fn(state, _) {
          let visible =
            model.observe(state)
            |> list.fold(lww_map.new(), fn(map, entry) {
              case entry.1 {
                None -> map
                Some(value) -> lww_map.set(map, entry.0, value, entry.2)
              }
            })
          let assert Ok(loaded) =
            kernel.from_sequenced(visible, replica_id.new("reloaded"))
          loaded
        }),
      ),
    )
  let script = [
    ClientOperation(1, edit("k", None, 7)),
    Sequence(1),
    Deliver(0, 1),
    AddClient,
    Synchronize,
  ]
  expect_script(model, script, [#("k", None, 7)])
  let assert Error(detail) = kernel_fuzz.try_run_script(buggy, 3, script)
  string.contains(detail, "convergence violated") |> expect.to_be_true()
}

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

pub fn lww_map_reload_observes_tombstone_clock_test() -> Nil {
  let model = lww_map_model.model()
  let script = [
    ClientOperation(1, edit("k", None, 100)),
    Sequence(1),
    Deliver(0, 1),
    Deliver(1, 1),
    Deliver(2, 1),
    AddClient,
    ClientOperation(2, edit("k", Some("restored"), 0)),
  ]
  let expected = [#("k", Some("restored"), 101)]
  expect_script(reload_second_writer(model), script, expected)
  let assert Some(load) = model.capabilities.load_from_synced
  let buggy =
    KernelModel(
      ..model,
      capabilities: Capabilities(
        ..model.capabilities,
        load_from_synced: Some(fn(state, id) {
          kernel.LwwMapState(..load(state, id), last_seen: dict.new())
        }),
      ),
    )
  let assert Error(detail) =
    kernel_fuzz.try_run_script(
      with_expected(reload_second_writer(buggy), expected),
      3,
      script,
    )
  string.contains(detail, "oracle mismatch") |> expect.to_be_true()
}

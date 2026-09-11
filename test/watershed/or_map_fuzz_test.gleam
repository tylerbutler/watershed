//// Fuzz coverage for the tally and MV-register OR-map modes.
//// RegisterMode uses wall-clock LWW timestamps in the runtime layer, so a
//// deterministic fuzz model would need synthetic timestamp plumbing.

import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  type LogEntry, AddClient, Capabilities, ClientOperation, Deliver, Disconnect,
  KernelModel, OperationEntry, Reconnect, RollbackOperation, Sequence,
  StashedOperation, SubmitMeta, Synchronize,
}
import watershed/fuzz/or_map_model.{
  type OrMapCommand, CommandIncrement, CommandRemove,
}
import watershed/fuzz/or_map_mv_register_model.{CommandWrite}
import watershed/fuzz/script_gen
import watershed/or_map_kernel.{Increment, TallyMode}

const client_count = 3

fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    rollback_operation: 8,
    stashed_operation: 8,
  )
}

pub fn converges_and_matches_oracle_test() -> Nil {
  let model = or_map_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_environment(),
    client_count,
    script_gen.script_generator(model.gen_operation, client_count, weights()),
  )
}

pub fn operation_json_round_trips_with_and_without_delta_test() -> Nil {
  let model = or_map_model.model()
  let assert Ok(#(_state, _events, operation, _message_id)) =
    or_map_kernel.increment(
      or_map_kernel.new(replica_id.new("a"), TallyMode),
      "a",
      6,
    )
  let assert Increment(key, amount, delta) = operation

  [CommandIncrement("a", 3, None), CommandIncrement(key, amount, Some(delta))]
  |> list.each(fn(command) {
    let assert Ok(decoded) =
      json.parse(
        json.to_string(model.operation_to_json(command)),
        model.operation_decoder,
      )
    decoded |> expect.to_equal(command)
  })
}

fn authorless_remove_oracle(
  entries: List(LogEntry(OrMapCommand)),
) -> List(#(String, Int)) {
  let #(dots, tallies) =
    kernel_fuzz.log_operations(entries)
    |> list.index_map(fn(entry, i) { #(i + 1, entry) })
    |> list.fold(#(dict.new(), dict.new()), fn(state, item) {
      let #(dots, tallies) = state
      let #(sequence_number, #(_author, command)) = item
      case command {
        CommandIncrement(key, amount, _) -> {
          let existing = dict.get(dots, key) |> result.unwrap([])
          let tally = dict.get(tallies, key) |> result.unwrap(0)
          #(
            dict.insert(dots, key, list.append(existing, [sequence_number])),
            dict.insert(tallies, key, tally + amount),
          )
        }
        CommandRemove(key, reference_sequence_number, _) -> {
          let remaining =
            dict.get(dots, key)
            |> result.unwrap([])
            |> list.filter(fn(dot_sequence_number) {
              dot_sequence_number > reference_sequence_number
            })
          let dots = case remaining {
            [] -> dict.delete(dots, key)
            _ -> dict.insert(dots, key, remaining)
          }
          #(dots, tallies)
        }
      }
    })

  dict.keys(dots)
  |> list.sort(by: string.compare)
  |> list.filter_map(fn(key) {
    case dict.get(dots, key) {
      Ok([_, ..]) -> Ok(#(key, dict.get(tallies, key) |> result.unwrap(0)))
      _ -> Error(Nil)
    }
  })
}

pub fn oracle_author_clause_is_load_bearing_test() -> Nil {
  let model = or_map_model.model()
  let script = [
    ClientOperation(1, CommandIncrement("a", 5, None)),
    ClientOperation(1, CommandRemove("a", 0, None)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(model, client_count, script) |> expect.to_be_ok

  let buggy =
    KernelModel(
      ..model,
      capabilities: Capabilities(
        ..model.capabilities,
        oracle: Some(authorless_remove_oracle),
      ),
    )
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected an oracle without the remover-author clause to diverge"
  }
}

pub fn shared_replica_id_loses_increments_test() -> Nil {
  let model = or_map_model.model()
  let buggy =
    KernelModel(..model, init: fn(_id) {
      or_map_kernel.new(replica_id.new("client-0"), TallyMode)
    })
  let script = [
    ClientOperation(1, CommandIncrement("a", 3, None)),
    ClientOperation(2, CommandIncrement("a", 5, None)),
    Synchronize,
  ]
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected a shared replica id to lose an increment and fail the oracle"
  }
}

pub fn mv_register_generated_lifecycle_test() -> Nil {
  let model = or_map_mv_register_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_environment(),
    client_count,
    script_gen.script_generator(model.gen_operation, client_count, weights()),
  )
}

pub fn mv_register_lifecycle_corpus_test() -> Nil {
  let model = or_map_mv_register_model.model()
  let first = CommandWrite("a", "same", None)
  let second = CommandWrite("a", "other", None)
  let resolve = CommandWrite("a", "resolved", None)
  let remove = or_map_mv_register_model.CommandRemove("a", 0, None)
  [
    [ClientOperation(1, first), ClientOperation(2, first), Synchronize],
    [ClientOperation(1, first), ClientOperation(1, remove), Synchronize],
    [
      ClientOperation(1, first),
      ClientOperation(2, second),
      Synchronize,
      ClientOperation(1, resolve),
      Synchronize,
    ],
    [
      ClientOperation(1, first),
      Synchronize,
      ClientOperation(1, remove),
      ClientOperation(2, second),
      Synchronize,
      ClientOperation(2, remove),
      Synchronize,
      ClientOperation(1, resolve),
      Synchronize,
    ],
    [
      ClientOperation(1, first),
      Sequence(1),
      Deliver(2, 1),
      RollbackOperation(2, second),
      ClientOperation(2, resolve),
      Synchronize,
    ],
    [
      Disconnect(1),
      ClientOperation(1, first),
      ClientOperation(2, second),
      Synchronize,
      Reconnect(1),
      Synchronize,
      StashedOperation(1, resolve),
      Synchronize,
    ],
    [
      ClientOperation(1, first),
      Synchronize,
      ClientOperation(1, remove),
      Synchronize,
      AddClient,
      ClientOperation(3, second),
      Synchronize,
    ],
  ]
  |> list.each(fn(script) {
    case kernel_fuzz.try_run_script(model, client_count, script) {
      Ok(_) -> Nil
      Error(detail) -> panic as detail
    }
  })
}

pub fn mv_register_model_replays_stashed_deltas_verbatim_test() -> Nil {
  let model = or_map_mv_register_model.model()
  let meta = SubmitMeta(1, 0)
  let assert #(state, Some(old)) =
    model.submit(model.init(1), CommandWrite("a", "old", None), meta)
  let assert Some(rollback) = model.capabilities.rollback
  let state = rollback(state, old)
  let assert #(state, Some(new)) =
    model.submit(state, CommandWrite("a", "new", None), meta)
  let assert Some(apply_stashed) = model.capabilities.apply_stashed
  let #(state, replayed) = apply_stashed(state, old, meta)
  replayed |> expect.to_equal(old)
  model.observe(state) |> expect.to_equal([#("a", ["new"])])
  let assert Some(oracle) = model.capabilities.oracle
  oracle([
    OperationEntry(1, new, [0, 1, 2]),
    OperationEntry(1, replayed, [0, 1, 2]),
  ])
  |> expect.to_equal([#("a", ["new"])])
}

pub fn mv_register_model_reordered_duplicate_delivery_test() -> Nil {
  let model = or_map_mv_register_model.model()
  let assert #(a, Some(first)) =
    model.submit(
      model.init(1),
      CommandWrite("a", "same", None),
      SubmitMeta(1, 0),
    )
  let assert #(_, Some(second)) =
    model.submit(
      model.init(2),
      CommandWrite("a", "same", None),
      SubmitMeta(2, 0),
    )
  let meta = kernel_fuzz.SequencedMeta(0, 1, 1, 0, [0, 1, 2])
  let assert Ok(a) = model.apply_remote(a, second, meta)
  let assert #(_, Some(resolved)) =
    model.submit(a, CommandWrite("a", "resolved", None), SubmitMeta(1, 0))
  let assert Some(oracle) = model.capabilities.oracle
  oracle([
    OperationEntry(1, first, [0, 1, 2]),
    OperationEntry(2, second, [0, 1, 2]),
    OperationEntry(1, resolved, [0, 1, 2]),
  ])
  |> expect.to_equal([#("a", ["resolved"])])
  [
    [first, second, resolved],
    [resolved, second, first],
    [second, first, resolved, second, resolved, first],
  ]
  |> list.each(fn(commands) {
    let state =
      list.fold(commands, model.init(0), fn(state, command) {
        let assert Ok(next) = model.apply_remote(state, command, meta)
        next
      })
    model.observe(state) |> expect.to_equal([#("a", ["resolved"])])
  })
  oracle([
    OperationEntry(1, first, [0, 1, 2]),
    OperationEntry(2, second, [0, 1, 2]),
  ])
  |> expect.to_equal([#("a", ["same", "same"])])
}

pub fn mv_register_model_detach_attach_and_summary_restart_test() -> Nil {
  let model = or_map_mv_register_model.model()
  let assert #(detached, Some(old)) =
    model.submit(
      model.init(1),
      CommandWrite("a", "old", None),
      SubmitMeta(1, 0),
    )
  let attached = or_map_kernel.promote_attach(detached)
  attached.pending |> expect.to_equal([])
  let assert Some(load) = model.capabilities.load_from_synced
  let loaded = load(attached, 2)
  let assert #(loaded, Some(new)) =
    model.submit(loaded, CommandWrite("a", "new", None), SubmitMeta(2, 1))
  let meta = kernel_fuzz.SequencedMeta(2, 2, 2, 0, [0, 1, 2])
  let assert Ok(loaded) = model.ack_local(loaded, new, meta)
  let restarted = load(loaded, 2)
  let assert Ok(restarted) = model.apply_remote(restarted, old, meta)
  model.observe(restarted) |> expect.to_equal([#("a", ["new"])])
  let #(restarted, _) =
    model.submit(restarted, CommandWrite("a", "latest", None), SubmitMeta(2, 2))
  model.observe(restarted) |> expect.to_equal([#("a", ["latest"])])
}

pub fn mv_register_model_command_json_round_trip_test() -> Nil {
  let model = or_map_mv_register_model.model()
  let raw_write = CommandWrite("a", "same", None)
  let raw_remove = or_map_mv_register_model.CommandRemove("a", 0, None)
  let assert #(state, Some(written)) =
    model.submit(model.init(1), raw_write, SubmitMeta(1, 0))
  let assert #(_, Some(removed)) =
    model.submit(state, raw_remove, SubmitMeta(1, 0))
  [raw_write, raw_remove, written, removed]
  |> list.each(fn(command) {
    json.parse(
      model.operation_to_json(command) |> json.to_string,
      model.operation_decoder,
    )
    |> expect.to_equal(Ok(command))
  })
}

pub fn mv_register_oracle_catches_dropped_alternatives_test() -> Nil {
  let model = or_map_mv_register_model.model()
  let buggy =
    KernelModel(..model, observe: fn(state) {
      model.observe(state)
      |> list.map(fn(entry) { #(entry.0, list.unique(entry.1)) })
    })
  let script = [
    ClientOperation(1, CommandWrite("a", "same", None)),
    ClientOperation(2, CommandWrite("a", "same", None)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(buggy, client_count, script)
  |> result.is_error
  |> expect.to_be_true()
  let without_oracle =
    KernelModel(
      ..buggy,
      capabilities: Capabilities(..buggy.capabilities, oracle: None),
    )
  kernel_fuzz.try_run_script(without_oracle, client_count, script)
  |> expect.to_be_ok()
}

pub fn mv_register_kernel_rejects_key_tag_collisions_without_oracle_test() -> Nil {
  let model = or_map_mv_register_model.model()
  let buggy = KernelModel(..model, init: fn(_id) { model.init(0) })
  let script = [
    ClientOperation(1, CommandWrite("a", "first", None)),
    ClientOperation(2, CommandWrite("b", "second", None)),
    Synchronize,
    ClientOperation(1, or_map_mv_register_model.CommandRemove("a", 0, None)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(model, client_count, script)
  |> expect.to_be_ok()
  kernel_fuzz.try_run_script(buggy, client_count, script)
  |> expect.to_be_error()
  let without_oracle =
    KernelModel(
      ..buggy,
      capabilities: Capabilities(..buggy.capabilities, oracle: None),
    )
  kernel_fuzz.try_run_script(without_oracle, client_count, script)
  |> expect.to_be_error()
  Nil
}

pub fn mv_register_model_replayed_remove_keeps_readd_test() -> Nil {
  let model = or_map_mv_register_model.model()
  let meta = SubmitMeta(1, 0)
  let assert #(state, Some(old)) =
    model.submit(model.init(1), CommandWrite("a", "old", None), meta)
  let assert #(state, Some(removed)) =
    model.submit(
      state,
      or_map_mv_register_model.CommandRemove("a", 0, None),
      meta,
    )
  let assert #(_, Some(fresh)) =
    model.submit(state, CommandWrite("a", "fresh", None), meta)
  let assert Some(oracle) = model.capabilities.oracle
  oracle([
    OperationEntry(1, old, [0, 1, 2]),
    OperationEntry(1, removed, [0, 1, 2]),
    OperationEntry(1, fresh, [0, 1, 2]),
  ])
  |> expect.to_equal([#("a", ["fresh"])])
  let delivery = kernel_fuzz.SequencedMeta(0, 1, 1, 0, [0, 1, 2])
  [[old, removed, fresh, removed], [fresh, removed, old, removed]]
  |> list.each(fn(commands) {
    let state =
      list.fold(commands, model.init(0), fn(state, command) {
        let assert Ok(state) = model.apply_remote(state, command, delivery)
        state
      })
    model.observe(state) |> expect.to_equal([#("a", ["fresh"])])
  })
}

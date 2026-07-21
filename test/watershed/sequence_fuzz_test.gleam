import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  Capabilities, ClientOp, KernelModel, Synchronize,
}
import watershed/fuzz/script_gen
import watershed/fuzz/sequence_model
import watershed/sequence_kernel

const client_count = 3

fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    rollback_op: 8,
    stashed_op: 8,
  )
}

pub fn converges_and_preserves_cache_invariant_test() {
  let model = sequence_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_op, client_count, weights()),
  )
}

pub fn command_json_round_trips_with_and_without_delta_test() {
  let model = sequence_model.model()
  let raw_value = "quoted \"value\" with \\ slash and\nnewline"
  let assert Ok(#(_, _, insert_op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("a")),
      0,
      json.string(raw_value),
    )
  let assert sequence_kernel.Insert(insert_index, insert_value, insert_delta) =
    insert_op

  let assert Ok(#(delete_state, _, _, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("delete")),
      0,
      json.string("delete"),
    )
  let assert Ok(#(_, _, delete_op, _)) = sequence_kernel.delete(delete_state, 0)
  let assert sequence_kernel.Delete(delete_index, delete_delta) = delete_op

  let assert Ok(#(move_state, _, _, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("move")),
      0,
      json.string("first"),
    )
  let assert Ok(#(move_state, _, _, _)) =
    sequence_kernel.insert(move_state, 1, json.string("second"))
  let assert Ok(#(_, _, move_op, _)) = sequence_kernel.move(move_state, 1, 0)
  let assert sequence_kernel.Move(move_from, move_to, move_delta) = move_op

  let replace_value = "replacement \"value\" with \\ slash and\nnewline"
  let assert Ok(#(replace_state, _, _, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("replace")),
      0,
      json.string("old"),
    )
  let assert Ok(#(_, _, replace_op, _)) =
    sequence_kernel.replace(replace_state, 0, json.string(replace_value))
  let assert sequence_kernel.Replace(
    replace_index,
    replace_json_value,
    replace_delta,
  ) = replace_op

  let commands = [
    sequence_model.InsertCmd(9, raw_value, None),
    sequence_model.InsertCmd(
      insert_index,
      json.to_string(insert_value),
      Some(insert_delta),
    ),
    sequence_model.DeleteCmd(8, None),
    sequence_model.DeleteCmd(delete_index, Some(delete_delta)),
    sequence_model.MoveCmd(7, 6, None),
    sequence_model.MoveCmd(move_from, move_to, Some(move_delta)),
    sequence_model.ReplaceCmd(5, replace_value, None),
    sequence_model.ReplaceCmd(
      replace_index,
      json.to_string(replace_json_value),
      Some(replace_delta),
    ),
  ]
  list.each(commands, fn(command) {
    let assert Ok(decoded) =
      json.parse(json.to_string(model.op_to_json(command)), model.op_decoder)
    decoded |> expect.to_equal(command)
  })
}

pub fn apply_stashed_preserves_persisted_delta_and_routes_generated_command_test() {
  let model = sequence_model.model()
  let assert Some(apply_stashed) = model.capabilities.apply_stashed
  let assert Ok(#(_, _, persisted_op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("persisted")),
      0,
      json.string("persisted"),
    )
  let assert sequence_kernel.Insert(index, value, delta) = persisted_op
  let persisted =
    sequence_model.InsertCmd(index, json.to_string(value), Some(delta))
  let #(state, routed) =
    apply_stashed(
      sequence_kernel.new(replica_id.new("stashed-client")),
      persisted,
      kernel_fuzz.SubmitMeta(1, 0),
    )
  routed |> expect.to_equal(persisted)
  state.pending |> expect.to_equal([sequence_kernel.PendingOp(persisted_op, 0)])
  let assert Ok(_) = sequence_kernel.ack_local(state, persisted_op)

  let generated = sequence_model.InsertCmd(9, "generated \"value\"", None)
  let #(state, routed) =
    apply_stashed(
      sequence_kernel.new(replica_id.new("generated-client")),
      generated,
      kernel_fuzz.SubmitMeta(1, 0),
    )
  let assert sequence_model.InsertCmd(0, encoded, Some(delta)) = routed
  encoded |> expect.to_equal(json.to_string(json.string("generated \"value\"")))
  let routed_op =
    sequence_kernel.Insert(0, json.string("generated \"value\""), delta)
  state.pending |> expect.to_equal([sequence_kernel.PendingOp(routed_op, 0)])
  let assert Ok(_) = sequence_kernel.ack_local(state, routed_op)
  Nil
}

pub fn model_summary_load_rebrands_and_can_ack_test() {
  let model = sequence_model.model()
  let assert Some(load_from_synced) = model.capabilities.load_from_synced
  let assert Ok(#(source, _, confirmed_op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("source")),
      0,
      json.string("confirmed"),
    )
  let assert Ok(source) = sequence_kernel.ack_local(source, confirmed_op)
  let loaded = load_from_synced(source, 7)
  loaded.replica_id |> expect.to_equal(replica_id.new("client-7"))
  let assert Ok(summary_self_id) =
    json.parse(
      json.to_string(sequence_kernel.summary(loaded)),
      decode.at(["state", "self_id"], replica_id.decoder()),
    )
  summary_self_id |> expect.to_equal(replica_id.new("client-7"))

  let assert Ok(#(loaded, _, new_op, message_id)) =
    sequence_kernel.insert(loaded, 1, json.string("new"))
  message_id |> expect.to_equal(0)
  let assert Ok(loaded) = sequence_kernel.ack_local(loaded, new_op)
  sequence_kernel.values(loaded)
  |> expect.to_equal([json.string("confirmed"), json.string("new")])
}

pub fn shared_replica_id_is_caught_test() {
  let model = sequence_model.model()
  let script = [
    ClientOp(1, sequence_model.InsertCmd(0, "a", None)),
    ClientOp(2, sequence_model.InsertCmd(0, "b", None)),
    Synchronize,
  ]
  // The production model intentionally has no index-based list oracle. This
  // focused witness only verifies that two concurrently created items survive.
  let capabilities =
    Capabilities(
      ..model.capabilities,
      oracle: Some(fn(_entries) { [json.string("a"), json.string("b")] }),
    )
  let strict = KernelModel(..model, capabilities: capabilities)
  kernel_fuzz.try_run_script(strict, client_count, script)
  |> expect.to_be_ok

  let buggy =
    KernelModel(
      ..model,
      init: fn(_id) { sequence_kernel.new(replica_id.new("client-0")) },
      capabilities: capabilities,
    )
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected duplicate sequence replica ids to fail"
  }
}

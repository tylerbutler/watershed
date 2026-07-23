import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  Capabilities, ClientOp, KernelModel, Synchronize,
}
import watershed/fuzz/script_gen
import watershed/fuzz/text_model
import watershed/text_kernel

const client_count = 3

fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    rollback_op: 8,
    stashed_op: 8,
  )
}

/// F1-F4 exit criterion for `text`: every connected client converges to the
/// same visible optimistic string, the per-client optimistic-cache
/// coherence invariant (`sequenced + pending == optimistic`) holds after
/// every command, and every command generated over the grapheme-heavy
/// alphabet (ASCII, combining clusters, ZWJ emoji, flags, mixed scripts,
/// and the empty string for no-op coverage) round-trips through sequencing,
/// duplicate delivery, rollback, disconnect/reconnect/resubmit, stash
/// replay, and summary reload (`AddClient`) — all exercised generically by
/// `kernel_fuzz.run`/`script_gen`.
pub fn converges_and_preserves_cache_invariant_test() {
  let model = text_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_op, client_count, weights()),
  )
}

pub fn command_json_round_trips_with_and_without_delta_test() {
  let model = text_model.model()

  let assert Ok(#(_, _, Some(text_kernel.Submission(insert_op, _)))) =
    text_kernel.insert(text_kernel.new(replica_id.new("a")), 0, "e\u{0301}👍")
  let assert text_kernel.Insert(insert_index, insert_value, insert_delta) =
    insert_op

  let assert Ok(#(delete_state, _, Some(_))) =
    text_kernel.insert(text_kernel.new(replica_id.new("delete")), 0, "delete")
  let assert Ok(#(_, _, Some(text_kernel.Submission(delete_op, _)))) =
    text_kernel.delete_range(delete_state, 1, 4)
  let assert text_kernel.DeleteRange(delete_start, delete_end, delete_delta) =
    delete_op

  let assert Ok(#(replace_state, _, Some(_))) =
    text_kernel.insert(text_kernel.new(replica_id.new("replace")), 0, "old")
  let assert Ok(#(_, _, Some(text_kernel.Submission(replace_op, _)))) =
    text_kernel.replace_range(replace_state, 0, 3, "new 👨‍👩‍👧‍👦")
  let assert text_kernel.ReplaceRange(
    replace_start,
    replace_end,
    replace_value,
    replace_delta,
  ) = replace_op

  let assert #(_, _, Some(text_kernel.Submission(append_op, _))) =
    text_kernel.append(text_kernel.new(replica_id.new("append")), "日д")
  let assert text_kernel.Append(append_value, append_delta) = append_op

  let commands = [
    text_model.InsertCmd(9, "generated \"value\"", None),
    text_model.InsertCmd(insert_index, insert_value, Some(insert_delta)),
    text_model.DeleteRangeCmd(8, 3, None),
    text_model.DeleteRangeCmd(delete_start, delete_end, Some(delete_delta)),
    text_model.ReplaceRangeCmd(7, 6, "value", None),
    text_model.ReplaceRangeCmd(
      replace_start,
      replace_end,
      replace_value,
      Some(replace_delta),
    ),
    text_model.AppendCmd("appended \"value\"", None),
    text_model.AppendCmd(append_value, Some(append_delta)),
  ]
  list.each(commands, fn(command) {
    let assert Ok(decoded) =
      json.parse(json.to_string(model.op_to_json(command)), model.op_decoder)
    decoded |> expect.to_equal(command)
  })
}

pub fn apply_stashed_preserves_persisted_delta_and_routes_generated_command_test() {
  let model = text_model.model()
  let assert Some(apply_stashed) = model.capabilities.apply_stashed
  let assert Ok(#(_, _, Some(text_kernel.Submission(persisted_op, _)))) =
    text_kernel.insert(
      text_kernel.new(replica_id.new("persisted")),
      0,
      "persisted 👍",
    )
  let assert text_kernel.Insert(index, value, delta) = persisted_op
  let persisted = text_model.InsertCmd(index, value, Some(delta))
  let #(state, routed) =
    apply_stashed(
      text_kernel.new(replica_id.new("stashed-client")),
      persisted,
      kernel_fuzz.SubmitMeta(1, 0),
    )
  routed |> expect.to_equal(persisted)
  state.pending |> expect.to_equal([text_kernel.PendingOp(persisted_op, 0)])
  let assert Ok(_) = text_kernel.ack_local(state, persisted_op)

  let generated = text_model.InsertCmd(9, "generated \"value\"", None)
  let #(state, routed) =
    apply_stashed(
      text_kernel.new(replica_id.new("generated-client")),
      generated,
      kernel_fuzz.SubmitMeta(1, 0),
    )
  let assert text_model.InsertCmd(0, "generated \"value\"", Some(delta)) =
    routed
  let routed_op = text_kernel.Insert(0, "generated \"value\"", delta)
  state.pending |> expect.to_equal([text_kernel.PendingOp(routed_op, 0)])
  let assert Ok(_) = text_kernel.ack_local(state, routed_op)
  Nil
}

/// A generated command that happens to be a synchronous no-op (an empty
/// insert here) must still route *something* through `apply_stashed`: a
/// stash always holds a previously-decided real edit, so the model falls
/// back to a guaranteed non-empty append rather than routing nothing.
pub fn apply_stashed_routes_a_fallback_for_a_no_op_generated_command_test() {
  let model = text_model.model()
  let assert Some(apply_stashed) = model.capabilities.apply_stashed
  let no_op_generated = text_model.InsertCmd(0, "", None)
  let #(state, routed) =
    apply_stashed(
      text_kernel.new(replica_id.new("no-op-client")),
      no_op_generated,
      kernel_fuzz.SubmitMeta(1, 0),
    )
  let assert text_model.AppendCmd(value, Some(delta)) = routed
  state.pending
  |> expect.to_equal([
    text_kernel.PendingOp(text_kernel.Append(value, delta), 0),
  ])
}

pub fn model_summary_load_rebrands_and_can_ack_test() {
  let model = text_model.model()
  let assert Some(load_from_synced) = model.capabilities.load_from_synced
  let assert Ok(#(source, _, Some(text_kernel.Submission(confirmed_op, _)))) =
    text_kernel.insert(
      text_kernel.new(replica_id.new("source")),
      0,
      "confirmed 🎉",
    )
  let assert Ok(source) = text_kernel.ack_local(source, confirmed_op)
  let loaded = load_from_synced(source, 7)
  loaded.replica_id |> expect.to_equal(replica_id.new("client-7"))
  let assert Ok(summary_self_id) =
    json.parse(
      json.to_string(text_kernel.summary(loaded)),
      decode.at(["state", "self_id"], replica_id.decoder()),
    )
  summary_self_id |> expect.to_equal(replica_id.new("client-7"))

  let assert #(loaded, _, Some(text_kernel.Submission(new_op, message_id))) =
    text_kernel.append(loaded, " new")
  message_id |> expect.to_equal(0)
  let assert Ok(loaded) = text_kernel.ack_local(loaded, new_op)
  text_kernel.value(loaded) |> expect.to_equal("confirmed 🎉 new")
}

/// Deterministic replay of a small planted script: two clients concurrently
/// insert at index 0, a third overlapping delete-range/replace-range races,
/// and an append races a concurrent insert — every scenario the design doc
/// calls out for convergence — then a summary-loaded late joiner (`AddClient`)
/// must land on the exact same string. Fixed indices (no qcheck) make this
/// reproducible byte-for-byte on every run, independent of any fuzzer seed.
pub fn planted_concurrent_edit_script_converges_deterministically_test() {
  let model = text_model.model()
  let script = [
    ClientOp(1, text_model.InsertCmd(0, "hello", None)),
    Synchronize,
    ClientOp(1, text_model.InsertCmd(5, " world", None)),
    ClientOp(2, text_model.InsertCmd(5, " there", None)),
    Synchronize,
    ClientOp(1, text_model.DeleteRangeCmd(0, 5, None)),
    ClientOp(2, text_model.ReplaceRangeCmd(2, 8, "XY", None)),
    Synchronize,
    ClientOp(1, text_model.AppendCmd("!!!", None)),
    ClientOp(2, text_model.InsertCmd(0, ">>", None)),
    Synchronize,
    kernel_fuzz.AddClient,
    Synchronize,
  ]
  kernel_fuzz.try_run_script(model, client_count, script)
  |> expect.to_be_ok
}

/// The production text model intentionally has no oracle (concurrent-insert
/// tie-break order is a CRDT implementation detail, not something the model
/// should hard-code). This focused witness only proves that two
/// concurrently inserted graphemes both survive a merge and that the harness
/// still fails loudly when two clients are wired to the same replica id —
/// mirroring `sequence_model`'s identical witness, since text shares the
/// same replica-identified-CRDT shape.
pub fn shared_replica_id_is_caught_test() {
  let model = text_model.model()
  let script = [
    ClientOp(1, text_model.InsertCmd(0, "a", None)),
    ClientOp(2, text_model.InsertCmd(0, "b", None)),
    Synchronize,
  ]
  let capabilities =
    Capabilities(..model.capabilities, oracle: Some(fn(_entries) { True }))
  let contains_both =
    KernelModel(
      name: model.name,
      init: model.init,
      submit: model.submit,
      apply_remote: model.apply_remote,
      ack_local: model.ack_local,
      observe: fn(state) {
        let value = text_kernel.value(state)
        string.contains(value, "a") && string.contains(value, "b")
      },
      gen_op: model.gen_op,
      check: model.check,
      canonicalize: None,
      ack_preserves_view: model.ack_preserves_view,
      op_to_json: model.op_to_json,
      op_decoder: model.op_decoder,
      capabilities: capabilities,
    )
  kernel_fuzz.try_run_script(contains_both, client_count, script)
  |> expect.to_be_ok

  let buggy =
    KernelModel(..contains_both, init: fn(_id) {
      text_kernel.new(replica_id.new("client-0"))
    })
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected duplicate text replica ids to fail"
  }
}

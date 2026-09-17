import gleam/json
import gleam/list
import gleam/result
import lattice_core/replica_id
import lattice_registers/lww_register
import startest/expect
import watershed/lww_clock
import watershed/lww_register_kernel as kernel

fn state(id: String) -> kernel.LwwRegisterState {
  kernel.new(replica_id.new(id))
}

pub fn unsafe_local_clock_returns_clock_error_test() -> Nil {
  let original = state("a")
  let unsafe = lww_clock.max_safe_timestamp + 1
  kernel.set(original, "invalid", unsafe)
  |> expect.to_equal(Error(kernel.Clock(lww_clock.InvalidTimestamp(unsafe))))
  kernel.p2p_set(original, "invalid", unsafe)
  |> expect.to_equal(Error(kernel.Clock(lww_clock.InvalidTimestamp(unsafe))))
}

pub fn local_write_uses_local_author_after_reload_test() -> Nil {
  let remote = lww_register.new("remote", 100, replica_id.new("z"))
  let assert Ok(local) =
    kernel.from_summary(
      json.to_string(lww_register.to_json(remote)),
      replica_id.new("a"),
    )
  let assert Ok(#(_, _, kernel.Set(_, timestamp, delta), _)) =
    kernel.set(local, "local", 1)
  timestamp |> expect.to_equal(101)
  delta
  |> expect.to_equal(lww_register.new("local", 101, replica_id.new("a")))
}

pub fn equal_time_writers_use_replica_id_as_tie_breaker_test() -> Nil {
  let assert Ok(#(a, _, write_a)) = kernel.p2p_set(state("a"), "a", 10)
  let assert Ok(#(_, _, write_b)) = kernel.p2p_set(state("b"), "b", 10)
  let assert Ok(#(a, events)) = kernel.apply_remote(a, write_b)
  events |> expect.to_equal([kernel.Changed("a", "b")])
  kernel.value(a) |> expect.to_equal("b")
  let assert Ok(#(b, events)) = kernel.apply_remote(state("b"), write_a)
  events |> expect.to_equal([kernel.Changed("", "a")])
  kernel.value(b) |> expect.to_equal("a")
  let assert Ok(#(b, events)) = kernel.apply_remote(b, write_b)
  events |> expect.to_equal([kernel.Changed("a", "b")])
  kernel.value(b) |> expect.to_equal("b")
}

pub fn same_value_write_advances_causality_without_event_test() -> Nil {
  let assert Ok(#(a, events, first, first_id)) =
    kernel.set(state("a"), "same", 10)
  events |> expect.to_equal([kernel.Changed("", "same")])
  let assert Ok(a) = kernel.ack_local_with_message_id(a, first, first_id)
  let before = kernel.summary(a) |> json.to_string
  let assert Ok(#(a, events, second, second_id)) = kernel.set(a, "same", 10)
  events |> expect.to_equal([])
  let assert Ok(a) = kernel.ack_local_with_message_id(a, second, second_id)
  kernel.summary(a) |> json.to_string |> expect.to_not_equal(before)
}

pub fn rollback_keeps_the_clock_high_water_mark_test() -> Nil {
  let assert Ok(#(a, _, old, old_id)) = kernel.set(state("a"), "old", 100)
  let assert Ok(#(a, events)) = kernel.rollback(a, old, old_id)
  events |> expect.to_equal([kernel.Changed("old", "")])
  let assert Ok(#(_, _, kernel.Set(_, timestamp, _), _)) =
    kernel.set(a, "next", 1)
  timestamp |> expect.to_equal(101)
}

pub fn ack_and_rollback_require_fifo_and_lifo_metadata_test() -> Nil {
  let assert Ok(#(a, _, first, first_id)) = kernel.set(state("a"), "first", 1)
  let assert Ok(#(a, _, second, second_id)) = kernel.set(a, "second", 1)
  kernel.ack_local_with_message_id(a, second, first_id)
  |> result.is_error
  |> expect.to_be_true()
  kernel.rollback(a, first, first_id) |> result.is_error |> expect.to_be_true()
  let assert Ok(#(a, _)) = kernel.rollback(a, second, second_id)
  let assert Ok(a) = kernel.ack_local_with_message_id(a, first, first_id)
  kernel.value(a) |> expect.to_equal("first")
}

pub fn summary_excludes_pending_and_stash_preserves_timestamp_test() -> Nil {
  let assert Ok(#(a, _, original, _)) = kernel.set(state("a"), "pending", 10)
  let assert Ok(loaded) =
    kernel.from_summary(
      kernel.summary(a) |> json.to_string,
      replica_id.new("b"),
    )
  kernel.value(loaded) |> expect.to_equal("")
  let assert Ok(#(loaded, _, replayed, id)) =
    kernel.apply_stashed_operation(loaded, original)
  replayed |> expect.to_equal(original)
  let assert Ok(loaded) = kernel.ack_local_with_message_id(loaded, replayed, id)
  kernel.value(loaded) |> expect.to_equal("pending")
  kernel.pending_timestamp(replayed) |> expect.to_equal(10)
}

pub fn duplicate_remote_replay_is_idempotent_test() -> Nil {
  let assert Ok(#(_, _, write)) = kernel.p2p_set(state("a"), "value", 5)
  let assert Ok(#(b, first_events)) = kernel.apply_remote(state("b"), write)
  let assert Ok(#(b, second_events)) = kernel.apply_remote(b, write)
  first_events |> expect.to_equal([kernel.Changed("", "value")])
  second_events |> expect.to_equal([])
  kernel.check_cache_coherence(b) |> expect.to_equal(Ok(Nil))
}

pub fn lower_wall_clock_after_import_still_wins_test() -> Nil {
  let remote = lww_register.new("remote", 100, replica_id.new("z"))
  let assert Ok(local) = kernel.from_sequenced(remote, replica_id.new("a"))
  let assert Ok(#(local, _, write, _)) = kernel.set(local, "local", 1)
  let assert Ok(#(local, _)) = kernel.apply_remote(local, write)
  kernel.value(local) |> expect.to_equal("local")
}

pub fn empty_registers_have_identical_replicated_state_test() -> Nil {
  let a = kernel.new(replica_id.new("a"))
  let b = kernel.new(replica_id.new("b"))
  kernel.summary(a)
  |> json.to_string
  |> expect.to_equal(kernel.summary(b) |> json.to_string)
}

pub fn malformed_summary_is_rejected_test() -> Nil {
  kernel.from_summary("{\"type\":\"other\",\"v\":1}", replica_id.new("a"))
  |> result.is_error
  |> expect.to_be_true()
}

pub fn p2p_and_sequenced_values_converge_test() -> Nil {
  let assert Ok(#(a, _, write)) = kernel.p2p_set(state("a"), "shared", 3)
  let assert Ok(#(b, _)) = kernel.apply_remote(state("b"), write)
  kernel.value(a) |> expect.to_equal(kernel.value(b))
  kernel.sequenced_value(a) |> expect.to_equal("shared")
  list.length(a.pending) |> expect.to_equal(0)
}

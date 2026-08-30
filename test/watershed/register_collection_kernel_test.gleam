//// Unit suite for `register_collection_kernel`, ported from the
//// ConsensusRegisterCollection behaviors into explicit pure-kernel steps.

import gleam/json.{type Json}
import startest/expect
import watershed/register_collection_kernel.{
  type Register, type RegisterEvent, type RegisterState, type WriteOperation,
  Atomic, AtomicChanged, Lww, Register, VersionChanged, VersionedValue, Write,
}

fn string_value(value: String) -> Json {
  json.string(value)
}

fn ack(
  state: RegisterState,
  operation: WriteOperation,
  seq: Int,
) -> #(RegisterState, List(RegisterEvent), Bool) {
  register_collection_kernel.ack_local(state, operation, seq)
}

fn summary(value: Json, seq: Int) -> Register {
  let version = VersionedValue(value, seq)
  Register(atomic: version, versions: [version])
}

pub fn new_state_reads_are_empty_test() -> Nil {
  let state = register_collection_kernel.new()
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Error(Nil))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Error(Nil))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Error(Nil))
  register_collection_kernel.keys(state) |> expect.to_equal([])
}

pub fn write_detached_is_visible_immediately_test() -> Nil {
  let #(state, events) =
    register_collection_kernel.write_detached(
      register_collection_kernel.new(),
      "k",
      string_value("v"),
    )
  events
  |> expect.to_equal([
    AtomicChanged("k", string_value("v"), True),
    VersionChanged("k", string_value("v"), True),
  ])
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(string_value("v")))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Ok(string_value("v")))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Ok([string_value("v")]))
}

pub fn detached_summary_persists_seq_zero_test() -> Nil {
  let #(state, _events) =
    register_collection_kernel.write_detached(
      register_collection_kernel.new(),
      "k",
      string_value("v"),
    )
  register_collection_kernel.summary_registers(state)
  |> expect.to_equal([#("k", summary(string_value("v"), 0))])
}

pub fn submit_is_not_optimistically_visible_test() -> Nil {
  let state = register_collection_kernel.new()
  let operation =
    register_collection_kernel.write(state, "k", string_value("v"), 0)
  operation |> expect.to_equal(Write("k", string_value("v"), 0))
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Error(Nil))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Error(Nil))
}

pub fn ack_commits_winner_and_emits_local_events_test() -> Nil {
  let state = register_collection_kernel.new()
  let operation =
    register_collection_kernel.write(state, "k", string_value("v"), 0)
  let #(state, events, is_winner) = ack(state, operation, 1)
  is_winner |> expect.to_be_true()
  events
  |> expect.to_equal([
    AtomicChanged("k", string_value("v"), True),
    VersionChanged("k", string_value("v"), True),
  ])
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(string_value("v")))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Ok(string_value("v")))
}

pub fn concurrent_loser_appends_version_but_does_not_change_atomic_test() -> Nil {
  let state_a = register_collection_kernel.new()
  let state_b = register_collection_kernel.new()
  let operation_a =
    register_collection_kernel.write(state_a, "k", string_value("A"), 0)
  let operation_b =
    register_collection_kernel.write(state_b, "k", string_value("B"), 0)

  let #(state_a, _events, outcome_a) = ack(state_a, operation_a, 1)
  outcome_a |> expect.to_be_true()
  let #(state_a, events_a2) =
    register_collection_kernel.apply_remote(state_a, operation_b, 2)
  events_a2 |> expect.to_equal([VersionChanged("k", string_value("B"), False)])

  let #(state_b, _events_b1) =
    register_collection_kernel.apply_remote(state_b, operation_a, 1)
  let #(state_b, events_b2, outcome_b) = ack(state_b, operation_b, 2)
  outcome_b |> expect.to_be_false()
  events_b2 |> expect.to_equal([VersionChanged("k", string_value("B"), True)])

  register_collection_kernel.read(state_a, "k", Atomic)
  |> expect.to_equal(Ok(string_value("A")))
  register_collection_kernel.read(state_b, "k", Atomic)
  |> expect.to_equal(Ok(string_value("A")))
  register_collection_kernel.read(state_a, "k", Lww)
  |> expect.to_equal(Ok(string_value("B")))
  register_collection_kernel.read_versions(state_a, "k")
  |> expect.to_equal(Ok([string_value("A"), string_value("B")]))
}

pub fn atomic_and_lww_can_diverge_across_three_write_schedule_test() -> Nil {
  let state =
    register_collection_kernel.from_summary([
      #("k", summary(string_value("0"), 1)),
    ])
  let operation_a = Write("k", string_value("A"), 1)
  let operation_b = Write("k", string_value("B"), 1)
  let #(state, _events) =
    register_collection_kernel.apply_remote(state, operation_a, 2)
  let #(state, _events) =
    register_collection_kernel.apply_remote(state, operation_b, 3)

  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(string_value("A")))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Ok(string_value("B")))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Ok([string_value("A"), string_value("B")]))
}

pub fn non_concurrent_write_prunes_known_versions_test() -> Nil {
  let state = register_collection_kernel.new()
  let #(state, _events) =
    register_collection_kernel.apply_remote(
      state,
      Write("k", string_value("A"), 0),
      1,
    )
  let #(state, _events) =
    register_collection_kernel.apply_remote(
      state,
      Write("k", string_value("B"), 0),
      2,
    )
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Ok([string_value("A"), string_value("B")]))

  let #(state, _events) =
    register_collection_kernel.apply_remote(
      state,
      Write("k", string_value("C"), 2),
      3,
    )
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(string_value("C")))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Ok([string_value("C")]))
}

pub fn prune_boundary_includes_equal_sequence_number_test() -> Nil {
  let state =
    register_collection_kernel.from_summary([
      #(
        "k",
        Register(atomic: VersionedValue(string_value("A"), 1), versions: [
          VersionedValue(string_value("A"), 1),
          VersionedValue(string_value("B"), 2),
        ]),
      ),
    ])
  let #(state, _events) =
    register_collection_kernel.apply_remote(
      state,
      Write("k", string_value("C"), 1),
      3,
    )
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Ok([string_value("B"), string_value("C")]))
}

pub fn ref_seq_equal_to_atomic_sequence_wins_test() -> Nil {
  let state =
    register_collection_kernel.from_summary([
      #("k", summary(string_value("A"), 1)),
    ])
  let #(state, events) =
    register_collection_kernel.apply_remote(
      state,
      Write("k", string_value("B"), 1),
      2,
    )
  events
  |> expect.to_equal([
    AtomicChanged("k", string_value("B"), False),
    VersionChanged("k", string_value("B"), False),
  ])
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(string_value("B")))
}

pub fn ref_seq_less_than_atomic_sequence_loses_test() -> Nil {
  let state =
    register_collection_kernel.from_summary([
      #("k", summary(string_value("A"), 2)),
    ])
  let #(state, events) =
    register_collection_kernel.apply_remote(
      state,
      Write("k", string_value("B"), 1),
      3,
    )
  events |> expect.to_equal([VersionChanged("k", string_value("B"), False)])
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(string_value("A")))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Ok(string_value("B")))
}

pub fn keys_are_sorted_and_never_deleted_test() -> Nil {
  let #(state, _events) =
    register_collection_kernel.apply_remote(
      register_collection_kernel.new(),
      Write("b", string_value("B"), 0),
      1,
    )
  let #(state, _events) =
    register_collection_kernel.apply_remote(
      state,
      Write("a", string_value("A"), 1),
      2,
    )
  register_collection_kernel.keys(state) |> expect.to_equal(["a", "b"])
}

pub fn rollback_leaves_state_unchanged_and_returns_false_test() -> Nil {
  let state =
    register_collection_kernel.from_summary([
      #("k", summary(string_value("A"), 1)),
    ])
  let #(after, outcome) =
    register_collection_kernel.rollback(state, Write("k", string_value("B"), 1))
  outcome |> expect.to_be_false()
  after |> expect.to_equal(state)
}

pub fn stashed_operation_returns_operation_verbatim_and_applies_normally_test() -> Nil {
  let operation = Write("k", string_value("v"), 7)
  let #(state, resubmit) =
    register_collection_kernel.apply_stashed_operation(
      register_collection_kernel.new(),
      operation,
    )
  resubmit |> expect.to_equal(operation)
  let #(state, _events, outcome) = ack(state, resubmit, 8)
  outcome |> expect.to_be_true()
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(string_value("v")))
}

pub fn summary_round_trips_atomic_versions_and_sequence_numbers_test() -> Nil {
  let original =
    Register(atomic: VersionedValue(string_value("A"), 2), versions: [
      VersionedValue(string_value("A"), 2),
      VersionedValue(string_value("B"), 3),
    ])
  let state = register_collection_kernel.from_summary([#("k", original)])
  let entries = register_collection_kernel.summary_registers(state)
  entries |> expect.to_equal([#("k", original)])
  let loaded = register_collection_kernel.from_summary(entries)
  register_collection_kernel.summary_registers(loaded)
  |> expect.to_equal([#("k", original)])
}

pub fn loaded_sequence_numbers_drive_future_cas_and_pruning_test() -> Nil {
  let state =
    register_collection_kernel.from_summary([
      #(
        "k",
        Register(atomic: VersionedValue(string_value("A"), 5), versions: [
          VersionedValue(string_value("A"), 5),
          VersionedValue(string_value("B"), 6),
        ]),
      ),
    ])
  let #(state, _events, outcome) =
    ack(state, Write("k", string_value("C"), 6), 7)
  outcome |> expect.to_be_true()
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(string_value("C")))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Ok([string_value("C")]))
}

pub fn json_null_round_trips_test() -> Nil {
  let #(state, _events, outcome) =
    ack(register_collection_kernel.new(), Write("k", json.null(), 0), 1)
  outcome |> expect.to_be_true()
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Ok(json.null()))
  let loaded =
    register_collection_kernel.from_summary(
      register_collection_kernel.summary_registers(state),
    )
  register_collection_kernel.read(loaded, "k", Atomic)
  |> expect.to_equal(Ok(json.null()))
}

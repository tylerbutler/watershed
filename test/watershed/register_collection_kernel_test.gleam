//// Unit suite for `register_collection_kernel`, ported from the
//// ConsensusRegisterCollection behaviors into explicit pure-kernel steps.

import gleam/json.{type Json}
import gleam/option.{None, Some}
import startest/expect
import watershed/register_collection_kernel.{
  type Register, type RegisterEvent, type RegisterState, type WriteOp, Atomic,
  AtomicChanged, Lww, Register, VersionChanged, VersionedValue, Write,
}

fn s(value: String) -> Json {
  json.string(value)
}

fn ack(
  state: RegisterState,
  op: WriteOp,
  seq: Int,
) -> #(RegisterState, List(RegisterEvent), Bool) {
  register_collection_kernel.ack_local(state, op, seq)
}

fn summary(value: Json, seq: Int) -> Register {
  let version = VersionedValue(value, seq)
  Register(atomic: version, versions: [version])
}

pub fn new_state_reads_are_empty_test() {
  let state = register_collection_kernel.new()
  register_collection_kernel.read(state, "k", Atomic) |> expect.to_equal(None)
  register_collection_kernel.read(state, "k", Lww) |> expect.to_equal(None)
  register_collection_kernel.read_versions(state, "k") |> expect.to_equal(None)
  register_collection_kernel.keys(state) |> expect.to_equal([])
}

pub fn write_detached_is_visible_immediately_test() {
  let #(state, events) =
    register_collection_kernel.write_detached(
      register_collection_kernel.new(),
      "k",
      s("v"),
    )
  events
  |> expect.to_equal([
    AtomicChanged("k", s("v"), True),
    VersionChanged("k", s("v"), True),
  ])
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(s("v")))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Some(s("v")))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Some([s("v")]))
}

pub fn detached_summary_persists_seq_zero_test() {
  let #(state, _events) =
    register_collection_kernel.write_detached(
      register_collection_kernel.new(),
      "k",
      s("v"),
    )
  register_collection_kernel.summary_registers(state)
  |> expect.to_equal([#("k", summary(s("v"), 0))])
}

pub fn submit_is_not_optimistically_visible_test() {
  let state = register_collection_kernel.new()
  let op = register_collection_kernel.write(state, "k", s("v"), 0)
  op |> expect.to_equal(Write("k", s("v"), 0))
  register_collection_kernel.read(state, "k", Atomic) |> expect.to_equal(None)
  register_collection_kernel.read(state, "k", Lww) |> expect.to_equal(None)
}

pub fn ack_commits_winner_and_emits_local_events_test() {
  let state = register_collection_kernel.new()
  let op = register_collection_kernel.write(state, "k", s("v"), 0)
  let #(state, events, is_winner) = ack(state, op, 1)
  is_winner |> expect.to_be_true()
  events
  |> expect.to_equal([
    AtomicChanged("k", s("v"), True),
    VersionChanged("k", s("v"), True),
  ])
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(s("v")))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Some(s("v")))
}

pub fn concurrent_loser_appends_version_but_does_not_change_atomic_test() {
  let state_a = register_collection_kernel.new()
  let state_b = register_collection_kernel.new()
  let op_a = register_collection_kernel.write(state_a, "k", s("A"), 0)
  let op_b = register_collection_kernel.write(state_b, "k", s("B"), 0)

  let #(state_a, _events, outcome_a) = ack(state_a, op_a, 1)
  outcome_a |> expect.to_be_true()
  let #(state_a, events_a2) =
    register_collection_kernel.apply_remote(state_a, op_b, 2)
  events_a2 |> expect.to_equal([VersionChanged("k", s("B"), False)])

  let #(state_b, _events_b1) =
    register_collection_kernel.apply_remote(state_b, op_a, 1)
  let #(state_b, events_b2, outcome_b) = ack(state_b, op_b, 2)
  outcome_b |> expect.to_be_false()
  events_b2 |> expect.to_equal([VersionChanged("k", s("B"), True)])

  register_collection_kernel.read(state_a, "k", Atomic)
  |> expect.to_equal(Some(s("A")))
  register_collection_kernel.read(state_b, "k", Atomic)
  |> expect.to_equal(Some(s("A")))
  register_collection_kernel.read(state_a, "k", Lww)
  |> expect.to_equal(Some(s("B")))
  register_collection_kernel.read_versions(state_a, "k")
  |> expect.to_equal(Some([s("A"), s("B")]))
}

pub fn atomic_and_lww_can_diverge_across_three_write_schedule_test() {
  let state =
    register_collection_kernel.from_summary([#("k", summary(s("0"), 1))])
  let op_a = Write("k", s("A"), 1)
  let op_b = Write("k", s("B"), 1)
  let #(state, _events) =
    register_collection_kernel.apply_remote(state, op_a, 2)
  let #(state, _events) =
    register_collection_kernel.apply_remote(state, op_b, 3)

  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(s("A")))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Some(s("B")))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Some([s("A"), s("B")]))
}

pub fn non_concurrent_write_prunes_known_versions_test() {
  let state = register_collection_kernel.new()
  let #(state, _events) =
    register_collection_kernel.apply_remote(state, Write("k", s("A"), 0), 1)
  let #(state, _events) =
    register_collection_kernel.apply_remote(state, Write("k", s("B"), 0), 2)
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Some([s("A"), s("B")]))

  let #(state, _events) =
    register_collection_kernel.apply_remote(state, Write("k", s("C"), 2), 3)
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(s("C")))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Some([s("C")]))
}

pub fn prune_boundary_includes_equal_sequence_number_test() {
  let state =
    register_collection_kernel.from_summary([
      #(
        "k",
        Register(atomic: VersionedValue(s("A"), 1), versions: [
          VersionedValue(s("A"), 1),
          VersionedValue(s("B"), 2),
        ]),
      ),
    ])
  let #(state, _events) =
    register_collection_kernel.apply_remote(state, Write("k", s("C"), 1), 3)
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Some([s("B"), s("C")]))
}

pub fn ref_seq_equal_to_atomic_sequence_wins_test() {
  let state =
    register_collection_kernel.from_summary([#("k", summary(s("A"), 1))])
  let #(state, events) =
    register_collection_kernel.apply_remote(state, Write("k", s("B"), 1), 2)
  events
  |> expect.to_equal([
    AtomicChanged("k", s("B"), False),
    VersionChanged("k", s("B"), False),
  ])
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(s("B")))
}

pub fn ref_seq_less_than_atomic_sequence_loses_test() {
  let state =
    register_collection_kernel.from_summary([#("k", summary(s("A"), 2))])
  let #(state, events) =
    register_collection_kernel.apply_remote(state, Write("k", s("B"), 1), 3)
  events |> expect.to_equal([VersionChanged("k", s("B"), False)])
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(s("A")))
  register_collection_kernel.read(state, "k", Lww)
  |> expect.to_equal(Some(s("B")))
}

pub fn keys_are_sorted_and_never_deleted_test() {
  let #(state, _events) =
    register_collection_kernel.apply_remote(
      register_collection_kernel.new(),
      Write("b", s("B"), 0),
      1,
    )
  let #(state, _events) =
    register_collection_kernel.apply_remote(state, Write("a", s("A"), 1), 2)
  register_collection_kernel.keys(state) |> expect.to_equal(["a", "b"])
}

pub fn rollback_leaves_state_unchanged_and_returns_false_test() {
  let state =
    register_collection_kernel.from_summary([#("k", summary(s("A"), 1))])
  let #(after, outcome) =
    register_collection_kernel.rollback(state, Write("k", s("B"), 1))
  outcome |> expect.to_be_false()
  after |> expect.to_equal(state)
}

pub fn stashed_op_returns_op_verbatim_and_applies_normally_test() {
  let op = Write("k", s("v"), 7)
  let #(state, resubmit) =
    register_collection_kernel.apply_stashed_op(
      register_collection_kernel.new(),
      op,
    )
  resubmit |> expect.to_equal(op)
  let #(state, _events, outcome) = ack(state, resubmit, 8)
  outcome |> expect.to_be_true()
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(s("v")))
}

pub fn summary_round_trips_atomic_versions_and_sequence_numbers_test() {
  let original =
    Register(atomic: VersionedValue(s("A"), 2), versions: [
      VersionedValue(s("A"), 2),
      VersionedValue(s("B"), 3),
    ])
  let state = register_collection_kernel.from_summary([#("k", original)])
  let entries = register_collection_kernel.summary_registers(state)
  entries |> expect.to_equal([#("k", original)])
  let loaded = register_collection_kernel.from_summary(entries)
  register_collection_kernel.summary_registers(loaded)
  |> expect.to_equal([#("k", original)])
}

pub fn loaded_sequence_numbers_drive_future_cas_and_pruning_test() {
  let state =
    register_collection_kernel.from_summary([
      #(
        "k",
        Register(atomic: VersionedValue(s("A"), 5), versions: [
          VersionedValue(s("A"), 5),
          VersionedValue(s("B"), 6),
        ]),
      ),
    ])
  let #(state, _events, outcome) = ack(state, Write("k", s("C"), 6), 7)
  outcome |> expect.to_be_true()
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(s("C")))
  register_collection_kernel.read_versions(state, "k")
  |> expect.to_equal(Some([s("C")]))
}

pub fn json_null_round_trips_test() {
  let #(state, _events, outcome) =
    ack(register_collection_kernel.new(), Write("k", json.null(), 0), 1)
  outcome |> expect.to_be_true()
  register_collection_kernel.read(state, "k", Atomic)
  |> expect.to_equal(Some(json.null()))
  let loaded =
    register_collection_kernel.from_summary(
      register_collection_kernel.summary_registers(state),
    )
  register_collection_kernel.read(loaded, "k", Atomic)
  |> expect.to_equal(Some(json.null()))
}

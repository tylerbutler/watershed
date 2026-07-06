import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/directory_kernel.{
  type DirectoryEvent, type DirectoryOp, type DirectoryState,
  type SequencedMeta, Cleared, CreateSubDirectory, Delete, DeleteSubDirectory,
  Disposed, SequencedMeta, Set, SubDirectoryCreated, SubDirectoryDeleted,
  Undisposed, ValueChanged,
}

// ─── helpers ─────────────────────────────────────────────────────────────────

// Case-based helpers instead of `let assert`: startest's rescue mechanism
// wraps `let assert` values in `Ok()`, breaking error-variant destructuring.

fn local(
  r: Result(
    #(DirectoryState, List(DirectoryEvent), DirectoryOp, Int),
    directory_kernel.KernelError,
  ),
) -> #(DirectoryState, List(DirectoryEvent), Int) {
  case r {
    Ok(#(state, events, _op, id)) -> #(state, events, id)
    Error(_) -> panic as "expected local op to succeed"
  }
}

fn local_sub(
  r: Result(
    #(DirectoryState, List(DirectoryEvent), option.Option(DirectoryOp), Int),
    directory_kernel.KernelError,
  ),
) -> #(DirectoryState, List(DirectoryEvent), option.Option(DirectoryOp), Int) {
  case r {
    Ok(tuple) -> tuple
    Error(_) -> panic as "expected subdir op to succeed"
  }
}

fn ack(
  state: DirectoryState,
  op: DirectoryOp,
  meta: SequencedMeta,
) -> DirectoryState {
  case directory_kernel.ack_local(state, op, meta) {
    Ok(s) -> s
    Error(_) -> panic as "expected ack to succeed"
  }
}

fn meta(author: Int, seq: Int, ref: Int, cseq: Int) -> SequencedMeta {
  SequencedMeta(
    author: author,
    sequence_number: seq,
    reference_sequence_number: ref,
    client_sequence_number: cseq,
  )
}

fn set(state: DirectoryState, path: String, key: String, value: Int) {
  local(directory_kernel.set(state, path, key, json.int(value)))
}

fn create_sub(state: DirectoryState, path: String, name: String) {
  local_sub(directory_kernel.create_subdirectory(state, path, name))
}

// ─── basic storage ───────────────────────────────────────────────────────────

pub fn new_directory_is_empty_test() {
  let state = directory_kernel.new()
  directory_kernel.entries(state, "/") |> expect.to_equal([])
  directory_kernel.get(state, "/", "k") |> expect.to_equal(None)
  directory_kernel.subdirectories(state, "/") |> expect.to_equal([])
}

pub fn root_set_is_optimistically_visible_test() {
  let #(state, events, _) = set(directory_kernel.new(), "/", "k", 1)
  directory_kernel.get(state, "/", "k") |> expect.to_equal(Some(json.int(1)))
  events |> expect.to_equal([ValueChanged("/", "k", None, True)])
}

pub fn set_carries_previous_optimistic_value_test() {
  let #(state, _, _) = set(directory_kernel.new(), "/", "k", 1)
  let #(_, events, _) = set(state, "/", "k", 2)
  events |> expect.to_equal([ValueChanged("/", "k", Some(json.int(1)), True)])
}

pub fn delete_hides_key_test() {
  let #(state, _, _) = set(directory_kernel.new(), "/", "k", 1)
  let #(state, events, _) = local(directory_kernel.delete(state, "/", "k"))
  directory_kernel.get(state, "/", "k") |> expect.to_equal(None)
  events |> expect.to_equal([ValueChanged("/", "k", Some(json.int(1)), True)])
}

pub fn clear_removes_all_and_emits_test() {
  let #(state, _, _) = set(directory_kernel.new(), "/", "a", 1)
  let #(state, _, _) = set(state, "/", "b", 2)
  let #(state, events, _) = local(directory_kernel.clear(state, "/"))
  directory_kernel.entries(state, "/") |> expect.to_equal([])
  events
  |> expect.to_equal([
    Cleared("/", True),
    ValueChanged("/", "a", Some(json.int(1)), True),
    ValueChanged("/", "b", Some(json.int(2)), True),
  ])
}

pub fn set_to_missing_path_errors_test() {
  case directory_kernel.set(directory_kernel.new(), "/nope", "k", json.int(1)) {
    Error(directory_kernel.PathNotFound("/nope")) -> Nil
    _ -> panic as "expected PathNotFound"
  }
}

// ─── ack transparency ────────────────────────────────────────────────────────

pub fn ack_local_set_preserves_view_test() {
  let #(state, _, _) = set(directory_kernel.new(), "/", "k", 1)
  let before = directory_kernel.entries(state, "/")
  let state = ack(state, Set("/", "k", json.int(1)), meta(0, 1, 0, 0))
  directory_kernel.entries(state, "/") |> expect.to_equal(before)
  // After ack the value is sequenced.
  directory_kernel.summary_tree(state).storage
  |> expect.to_equal([#("k", json.int(1))])
}

pub fn ack_out_of_order_errors_test() {
  let #(state, _, _) = set(directory_kernel.new(), "/", "k", 1)
  case directory_kernel.ack_local(state, Delete("/", "k"), meta(0, 1, 0, 0)) {
    Error(directory_kernel.UnexpectedAck(_, _)) -> Nil
    _ -> panic as "expected UnexpectedAck"
  }
}

// ─── remote suppression ──────────────────────────────────────────────────────

pub fn remote_set_emits_when_no_pending_test() {
  let #(state, events) =
    directory_kernel.apply_remote(
      directory_kernel.new(),
      Set("/", "k", json.int(9)),
      meta(1, 1, 0, 0),
    )
  events |> expect.to_equal([ValueChanged("/", "k", None, False)])
  directory_kernel.get(state, "/", "k") |> expect.to_equal(Some(json.int(9)))
}

pub fn remote_set_suppressed_when_pending_masks_test() {
  let #(state, _, _) = set(directory_kernel.new(), "/", "k", 1)
  let #(_, events) =
    directory_kernel.apply_remote(state, Set("/", "k", json.int(9)), meta(1, 1, 0, 0))
  events |> expect.to_equal([])
}

// ─── subdirectory lifecycle ──────────────────────────────────────────────────

pub fn create_subdirectory_visible_immediately_test() {
  let #(state, events, op, _) = create_sub(directory_kernel.new(), "/", "a")
  op |> expect.to_equal(Some(CreateSubDirectory("/", "a")))
  events |> expect.to_equal([SubDirectoryCreated("/a", True)])
  directory_kernel.subdirectories(state, "/") |> expect.to_equal(["a"])
  directory_kernel.has_subdirectory(state, "/", "a") |> expect.to_be_true()
}

pub fn nested_storage_test() {
  let #(state, _, _, _) = create_sub(directory_kernel.new(), "/", "a")
  let #(state, _, _) = set(state, "/a", "k", 7)
  directory_kernel.get(state, "/a", "k") |> expect.to_equal(Some(json.int(7)))
  // Root storage is unaffected.
  directory_kernel.get(state, "/", "k") |> expect.to_equal(None)
}

pub fn duplicate_create_does_not_duplicate_test() {
  let #(state, _, _, _) = create_sub(directory_kernel.new(), "/", "a")
  let #(state, events, op, _) = create_sub(state, "/", "a")
  op |> expect.to_equal(None)
  events |> expect.to_equal([])
  directory_kernel.subdirectories(state, "/") |> expect.to_equal(["a"])
}

pub fn invalid_subdir_name_errors_test() {
  case directory_kernel.create_subdirectory(directory_kernel.new(), "/", "a/b") {
    Error(directory_kernel.InvalidName("a/b")) -> Nil
    _ -> panic as "expected InvalidName"
  }
}

pub fn local_delete_subdirectory_hides_and_disposes_test() {
  let #(state, _, _, _) = create_sub(directory_kernel.new(), "/", "a")
  // ack the create so it is sequenced
  let state = ack(state, CreateSubDirectory("/", "a"), meta(0, 1, 0, 0))
  let #(state, events, op, _) =
    local_sub(directory_kernel.delete_subdirectory(state, "/", "a"))
  op |> expect.to_equal(Some(DeleteSubDirectory("/", "a")))
  expect.to_be_true(list.contains(events, SubDirectoryDeleted("/a", True)))
  expect.to_be_true(list.contains(events, Disposed("/a")))
  directory_kernel.has_subdirectory(state, "/", "a") |> expect.to_be_false()
}

pub fn remote_create_subdirectory_test() {
  let #(state, events) =
    directory_kernel.apply_remote(
      directory_kernel.new(),
      CreateSubDirectory("/", "b"),
      meta(1, 1, 0, 0),
    )
  events |> expect.to_equal([SubDirectoryCreated("/b", False)])
  directory_kernel.subdirectories(state, "/") |> expect.to_equal(["b"])
}

pub fn remote_delete_disposes_and_clears_test() {
  let #(state, _) =
    directory_kernel.apply_remote(
      directory_kernel.new(),
      CreateSubDirectory("/", "b"),
      meta(1, 1, 0, 0),
    )
  let #(state, _) =
    directory_kernel.apply_remote(state, Set("/b", "k", json.int(1)), meta(1, 2, 1, 0))
  let #(state, events) =
    directory_kernel.apply_remote(state, DeleteSubDirectory("/", "b"), meta(1, 3, 2, 0))
  events |> expect.to_equal([SubDirectoryDeleted("/b", False)])
  directory_kernel.has_subdirectory(state, "/", "b") |> expect.to_be_false()
}

// ─── ordering ────────────────────────────────────────────────────────────────

pub fn acknowledged_children_before_unacked_local_test() {
  // Remote create of "z" (acked, seq 1); local create of "a" (unacked seq -1).
  let #(state, _) =
    directory_kernel.apply_remote(
      directory_kernel.new(),
      CreateSubDirectory("/", "z"),
      meta(1, 1, 0, 0),
    )
  let #(state, _, _, _) = create_sub(state, "/", "a")
  // Acknowledged "z" sorts before unacked-local "a" despite name order.
  directory_kernel.subdirectories(state, "/") |> expect.to_equal(["z", "a"])
}

pub fn lower_seq_first_test() {
  let #(state, _) =
    directory_kernel.apply_remote(
      directory_kernel.new(),
      CreateSubDirectory("/", "y"),
      meta(1, 2, 0, 0),
    )
  let #(state, _) =
    directory_kernel.apply_remote(state, CreateSubDirectory("/", "x"), meta(1, 1, 0, 0))
  // x has lower seq (1) than y (2), so it sorts first.
  directory_kernel.subdirectories(state, "/") |> expect.to_equal(["x", "y"])
}

// ─── summary round-trip ──────────────────────────────────────────────────────

pub fn summary_round_trip_test() {
  let state = directory_kernel.new()
  let #(state, _) =
    directory_kernel.apply_remote(state, Set("/", "k", json.int(1)), meta(1, 1, 0, 0))
  let #(state, _) =
    directory_kernel.apply_remote(state, CreateSubDirectory("/", "a"), meta(1, 2, 0, 0))
  let #(state, _) =
    directory_kernel.apply_remote(state, Set("/a", "n", json.int(5)), meta(1, 3, 2, 0))

  let loaded = directory_kernel.from_summary(directory_kernel.summary_tree(state))
  directory_kernel.get(loaded, "/", "k") |> expect.to_equal(Some(json.int(1)))
  directory_kernel.get(loaded, "/a", "n") |> expect.to_equal(Some(json.int(5)))
  directory_kernel.subdirectories(loaded, "/") |> expect.to_equal(["a"])
}

// ─── stale instance filter (D12) ─────────────────────────────────────────────

pub fn stale_op_ignored_after_delete_recreate_test() {
  // Client sees: create /a (seq1 by client 1), then it is deleted (seq2),
  // then recreated (seq3 by client 2). A late set op authored by client 1
  // with refSeq=1 (before the recreate at seq3) targets the OLD instance and
  // must be ignored.
  let state = directory_kernel.new()
  let #(state, _) =
    directory_kernel.apply_remote(state, CreateSubDirectory("/", "a"), meta(1, 1, 0, 0))
  let #(state, _) =
    directory_kernel.apply_remote(state, DeleteSubDirectory("/", "a"), meta(1, 2, 1, 0))
  let #(state, _) =
    directory_kernel.apply_remote(state, CreateSubDirectory("/", "a"), meta(2, 3, 0, 0))
  // Stale set: author 1 (not a creator of the new instance), refSeq 1 < 3.
  let #(state, events) =
    directory_kernel.apply_remote(state, Set("/a", "k", json.int(99)), meta(1, 4, 1, 0))
  events |> expect.to_equal([])
  directory_kernel.get(state, "/a", "k") |> expect.to_equal(None)
}

pub fn fresh_op_applies_after_recreate_test() {
  let state = directory_kernel.new()
  let #(state, _) =
    directory_kernel.apply_remote(state, CreateSubDirectory("/", "a"), meta(1, 1, 0, 0))
  let #(state, _) =
    directory_kernel.apply_remote(state, DeleteSubDirectory("/", "a"), meta(1, 2, 1, 0))
  let #(state, _) =
    directory_kernel.apply_remote(state, CreateSubDirectory("/", "a"), meta(2, 3, 0, 0))
  // Fresh set: refSeq 3 >= create seq 3, so it applies even from a non-creator.
  let #(state, _) =
    directory_kernel.apply_remote(state, Set("/a", "k", json.int(99)), meta(1, 4, 3, 0))
  directory_kernel.get(state, "/a", "k") |> expect.to_equal(Some(json.int(99)))
}

// ─── rollback ────────────────────────────────────────────────────────────────

pub fn rollback_set_reverts_test() {
  let #(state, _, id) = set(directory_kernel.new(), "/", "k", 1)
  case directory_kernel.rollback(state, Set("/", "k", json.int(1)), id) {
    Ok(#(state, _events)) ->
      directory_kernel.get(state, "/", "k") |> expect.to_equal(None)
    Error(_) -> panic as "rollback should succeed"
  }
}

pub fn rollback_create_disposes_test() {
  let #(state, _, _, id) = create_sub(directory_kernel.new(), "/", "a")
  case directory_kernel.rollback(state, CreateSubDirectory("/", "a"), id) {
    Ok(#(state, events)) -> {
      directory_kernel.has_subdirectory(state, "/", "a") |> expect.to_be_false()
      expect.to_be_true(list.contains(events, Disposed("/a")))
    }
    Error(_) -> panic as "rollback should succeed"
  }
}

pub fn rollback_delete_reexposes_tree_test() {
  let #(state, _, _, _) = create_sub(directory_kernel.new(), "/", "a")
  let state = ack(state, CreateSubDirectory("/", "a"), meta(0, 1, 0, 0))
  let #(state, _, _) = set(state, "/a", "k", 3)
  let state = ack(state, Set("/a", "k", json.int(3)), meta(0, 2, 1, 0))
  let #(state, _, _, id) =
    local_sub(directory_kernel.delete_subdirectory(state, "/", "a"))
  directory_kernel.has_subdirectory(state, "/", "a") |> expect.to_be_false()
  case directory_kernel.rollback(state, DeleteSubDirectory("/", "a"), id) {
    Ok(#(state, events)) -> {
      directory_kernel.has_subdirectory(state, "/", "a") |> expect.to_be_true()
      directory_kernel.get(state, "/a", "k") |> expect.to_equal(Some(json.int(3)))
      expect.to_be_true(list.contains(events, Undisposed("/a")))
    }
    Error(_) -> panic as "rollback should succeed"
  }
}

// ─── invariants ──────────────────────────────────────────────────────────────

pub fn invariants_hold_after_ops_test() {
  let #(state, _, _, _) = create_sub(directory_kernel.new(), "/", "a")
  let #(state, _, _) = set(state, "/a", "k", 1)
  let #(state, _, _, _) = create_sub(state, "/a", "b")
  directory_kernel.check_invariants(state) |> expect.to_equal(Ok(Nil))
}

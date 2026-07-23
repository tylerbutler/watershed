# Collaborative Text DDS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a convergent `SharedText` DDS for collaborative plain-text editing, backed by the `lattice_text` CRDT (Hex 1.0.0) with grapheme-based indexing and cursor anchors.

**Architecture:** A pure `text_kernel` will keep sequenced, optimistic, and pending CRDT state, mirroring the sequence kernel. The closed channel sums, wire codecs, runtime core, Erlang and JavaScript runtimes, and public facades will expose insert, delete-range, replace-range, append, value, length, substring, anchors, handles, typed fields, and subscriptions. Empty edits validate their indexes and then succeed as no-ops without producing channel ops.

**Tech Stack:** Gleam, `lattice_text`, `lattice_sequence` (anchor types), `gleam_json`, startest, qcheck, Watershed runtime core, Sluice in-memory integration tests.

**Prerequisite:** The collaborative sequence DDS plan
(`docs/superpowers/plans/2026-07-20-collaborative-sequence-dds.md`) is fully
implemented. That plan establishes the kernel, channel, wire, runtime, and
fuzz patterns this plan extends. `lattice_text` resolves from Hex as version
`1.0.0` (`gleam.toml`: `lattice_text = ">= 1.0.0 and < 2.0.0"`), not a local
path dependency. Verify before starting:

```bash
rg 'lattice_text' gleam.toml manifest.toml
gleam test sequence_kernel
```

Expected: `lattice_text` resolves from Hex at `1.0.0` and the sequence
kernel tests pass.

---

## File Structure

**Create**

- `src/watershed/text_kernel.gleam` — pure optimistic text kernel, lifecycle, and anchors.
- `test/watershed/text_kernel_test.gleam` — mutation, lifecycle, anchor, and convergence tests.
- `test/watershed/text_channel_test.gleam` — channel summary, attach, and runtime-core tests.
- `test/watershed/fuzz/text_model.gleam` — shared fuzz-harness adapter.
- `test/watershed/text_fuzz_test.gleam` — text property and planted-bug tests.

**Modify**

- `src/watershed/channel.gleam` — closed channel sums and dispatch.
- `src/watershed/wire.gleam` — text channel type tag.
- `src/watershed/wire/ops.gleam` — text op codecs.
- `src/watershed/runtime_core.gleam` — text mutations, reads, anchors, errors, and event routing.
- `src/watershed/runtime.gleam` — Erlang actor messages and result-returning edits.
- `src/watershed/runtime_js.gleam` — JavaScript runtime operations.
- `src/watershed/schema.gleam` — `TextChannel` phantom kind.
- `src/watershed.gleam` — Erlang `SharedText` public facade.
- `src/watershed_js.gleam` — JavaScript `SharedText` public facade.
- `test/watershed/wire_test.gleam` — text wire round trips and malformed input.
- `test/watershed/schema_test.gleam` — typed text field.
- `test/watershed/sluice/driver_test.gleam` — Erlang end-to-end convergence.
- `test/watershed/sluice/driver_js_test.gleam` — JavaScript end-to-end convergence.
- `README.md` — supported DDS and API example.

## Task 1: Implement Basic Text Mutations

**Files:**

- Create: `src/watershed/text_kernel.gleam`
- Create: `test/watershed/text_kernel_test.gleam`

- [ ] **Step 1: Write failing mutation, no-op, and error tests**

Create `test/watershed/text_kernel_test.gleam` with:

```gleam
import gleam/list
import gleam/option.{None, Some}
import lattice_core/replica_id
import startest/expect
import watershed/text_kernel

fn new_a() -> text_kernel.TextState {
  text_kernel.new(replica_id.new("a"))
}

pub fn insert_delete_replace_append_are_optimistic_test() {
  let assert Ok(#(state, _, Some(_))) = text_kernel.insert(new_a(), 0, "héllo")
  let assert Ok(#(state, _, Some(_))) = text_kernel.insert(state, 5, " 👍")
  text_kernel.value(state) |> expect.to_equal("héllo 👍")
  text_kernel.length(state) |> expect.to_equal(7)

  let assert Ok(#(state, events, Some(_))) =
    text_kernel.replace_range(state, 0, 1, "H")
  events |> expect.to_equal([text_kernel.TextChanged("Héllo 👍")])

  let assert Ok(#(state, _, Some(_))) = text_kernel.delete_range(state, 5, 7)
  let assert #(state, _, Some(_)) = text_kernel.append(state, "!")
  text_kernel.value(state) |> expect.to_equal("Héllo!")
  text_kernel.sequenced_value(state) |> expect.to_equal("")
  text_kernel.substring(state, 1, 5) |> expect.to_equal(Ok("éllo"))
}

pub fn empty_edits_are_successful_no_ops_test() {
  let assert Ok(#(state, _, Some(_))) = text_kernel.insert(new_a(), 0, "ab")
  let assert Ok(#(state, [], None)) = text_kernel.insert(state, 1, "")
  let assert Ok(#(state, [], None)) = text_kernel.delete_range(state, 1, 1)
  let assert Ok(#(state, [], None)) = text_kernel.replace_range(state, 2, 2, "")
  let assert #(state, [], None) = text_kernel.append(state, "")
  text_kernel.value(state) |> expect.to_equal("ab")
  state.pending |> list.length |> expect.to_equal(1)
}

pub fn invalid_indexes_return_edit_errors_test() {
  text_kernel.insert(new_a(), 1, "a")
  |> expect.to_equal(Error(text_kernel.InsertOutOfBounds(1, 0)))

  text_kernel.insert(new_a(), 1, "")
  |> expect.to_equal(Error(text_kernel.InsertOutOfBounds(1, 0)))

  text_kernel.delete_range(new_a(), 0, 1)
  |> expect.to_equal(Error(text_kernel.DeleteRangeOutOfBounds(0, 1, 0)))

  text_kernel.replace_range(new_a(), 0, 1, "x")
  |> expect.to_equal(Error(text_kernel.ReplaceRangeOutOfBounds(0, 1, 0)))

  text_kernel.substring(new_a(), 0, 1)
  |> expect.to_equal(Error(text_kernel.SubstringOutOfBounds(0, 1, 0)))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test text_kernel
```

Expected: compilation fails because `watershed/text_kernel` does not exist.

- [ ] **Step 3: Add the kernel types, reads, and mutations**

Create `src/watershed/text_kernel.gleam` with these public types:

```gleam
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_sequence/sequence
import lattice_text/text.{type Text}

pub type TextState {
  TextState(
    replica_id: ReplicaId,
    sequenced: Text,
    optimistic: Text,
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: TextOp, message_id: Int)
}

pub type TextOp {
  Insert(index: Int, value: String, delta: Text)
  DeleteRange(start: Int, end: Int, delta: Text)
  ReplaceRange(start: Int, end: Int, value: String, delta: Text)
  Append(value: String, delta: Text)
}

pub type TextEvent {
  TextChanged(value: String)
}

pub type EditError {
  InsertOutOfBounds(index: Int, length: Int)
  DeleteRangeOutOfBounds(start: Int, end: Int, length: Int)
  ReplaceRangeOutOfBounds(start: Int, end: Int, length: Int)
  SubstringOutOfBounds(start: Int, end: Int, length: Int)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
}

/// The result of a successful local mutation. `None` in the third position
/// marks a validated empty edit: no pending entry, no event, no channel op.
pub type Applied =
  #(TextState, List(TextEvent), Option(#(TextOp, Int)))
```

Add constructors and reads:

```gleam
pub fn new(replica_id: ReplicaId) -> TextState {
  let empty = text.new(replica_id)
  TextState(
    replica_id: replica_id,
    sequenced: empty,
    optimistic: empty,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn value(state: TextState) -> String {
  text.value(state.optimistic)
}

pub fn sequenced_value(state: TextState) -> String {
  text.value(state.sequenced)
}

pub fn length(state: TextState) -> Int {
  text.length(state.optimistic)
}

pub fn substring(
  state: TextState,
  start: Int,
  end: Int,
) -> Result(String, EditError) {
  case text.try_substring(state.optimistic, start, end) {
    Ok(value) -> Ok(value)
    Error(text.RangeOutOfBounds(start, end, length)) ->
      Error(SubstringOutOfBounds(start, end, length))
  }
}
```

Use this common finisher:

```gleam
fn finish_local(state: TextState, optimistic: Text, op: TextOp) -> Applied {
  let before = value(state)
  let message_id = state.next_pending_message_id
  let state =
    TextState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, changed_event(before, value(state)), Some(#(op, message_id)))
}

fn changed_event(before: String, after: String) -> List(TextEvent) {
  case before == after {
    True -> []
    False -> [TextChanged(after)]
  }
}
```

Implement the mutations with lattice's fallible API. Validate empty edits
before short-circuiting them to `#(state, [], None)`:

```gleam
pub fn insert(
  state: TextState,
  index: Int,
  value: String,
) -> Result(Applied, EditError) {
  let visible_length = length(state)
  case value {
    "" ->
      case 0 <= index && index <= visible_length {
        True -> Ok(#(state, [], None))
        False -> Error(InsertOutOfBounds(index, visible_length))
      }
    _ ->
      case text.try_insert_with_delta(state.optimistic, index, value) {
        Ok(#(optimistic, delta)) ->
          Ok(finish_local(state, optimistic, Insert(index, value, delta)))
        Error(sequence.IndexOutOfBounds(index, length)) ->
          Error(InsertOutOfBounds(index, length))
      }
  }
}

pub fn delete_range(
  state: TextState,
  start: Int,
  end: Int,
) -> Result(Applied, EditError) {
  case text.try_delete_range_with_delta(state.optimistic, start, end) {
    Error(text.RangeOutOfBounds(start, end, length)) ->
      Error(DeleteRangeOutOfBounds(start, end, length))
    Ok(#(optimistic, delta)) ->
      case start == end {
        True -> Ok(#(state, [], None))
        False ->
          Ok(finish_local(state, optimistic, DeleteRange(start, end, delta)))
      }
  }
}

pub fn replace_range(
  state: TextState,
  start: Int,
  end: Int,
  value: String,
) -> Result(Applied, EditError) {
  case text.try_replace_range_with_delta(state.optimistic, start, end, value) {
    Error(text.RangeOutOfBounds(start, end, length)) ->
      Error(ReplaceRangeOutOfBounds(start, end, length))
    Ok(#(optimistic, delta)) ->
      case start == end && value == "" {
        True -> Ok(#(state, [], None))
        False ->
          Ok(finish_local(
            state,
            optimistic,
            ReplaceRange(start, end, value, delta),
          ))
      }
  }
}

pub fn append(state: TextState, value: String) -> Applied {
  case value {
    "" -> #(state, [], None)
    _ -> {
      let #(optimistic, delta) = text.append_with_delta(state.optimistic, value)
      finish_local(state, optimistic, Append(value, delta))
    }
  }
}
```

Add a stable error formatter for runtime callers:

```gleam
pub fn edit_error_detail(error: EditError) -> String {
  case error {
    InsertOutOfBounds(index, length) ->
      "insert index " <> int.to_string(index) <> " outside 0.."
      <> int.to_string(length)
    DeleteRangeOutOfBounds(start, end, length) ->
      "delete range " <> int.to_string(start) <> ".." <> int.to_string(end)
      <> " invalid for length " <> int.to_string(length)
    ReplaceRangeOutOfBounds(start, end, length) ->
      "replace range " <> int.to_string(start) <> ".." <> int.to_string(end)
      <> " invalid for length " <> int.to_string(length)
    SubstringOutOfBounds(start, end, length) ->
      "substring range " <> int.to_string(start) <> ".." <> int.to_string(end)
      <> " invalid for length " <> int.to_string(length)
  }
}
```

- [ ] **Step 4: Run the focused test**

Run:

```bash
gleam test text_kernel
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/watershed/text_kernel.gleam test/watershed/text_kernel_test.gleam
git commit -m "feat(text): add optimistic mutations"
```

## Task 2: Add Text Lifecycle, Anchors, and Convergence

**Files:**

- Modify: `src/watershed/text_kernel.gleam`
- Modify: `test/watershed/text_kernel_test.gleam`

- [ ] **Step 1: Write failing lifecycle, anchor, and convergence tests**

Append to `test/watershed/text_kernel_test.gleam` (add imports for
`gleam/json`, `lattice_sequence/sequence`, and `lattice_text/text`):

```gleam
fn ack(
  state: text_kernel.TextState,
  op: text_kernel.TextOp,
) -> text_kernel.TextState {
  let assert Ok(state) = text_kernel.ack_local(state, op)
  state
}

pub fn ack_is_view_transparent_and_remote_merge_is_idempotent_test() {
  let assert Ok(#(state_a, _, Some(#(op, _)))) =
    text_kernel.insert(new_a(), 0, "a")
  let before_ack = text_kernel.value(state_a)
  let state_a = ack(state_a, op)
  text_kernel.value(state_a) |> expect.to_equal(before_ack)

  let state_b = text_kernel.new(replica_id.new("b"))
  let #(state_b, first_events) = text_kernel.apply_remote(state_b, op)
  let #(state_b, second_events) = text_kernel.apply_remote(state_b, op)
  text_kernel.value(state_b) |> expect.to_equal("a")
  first_events |> expect.to_equal([text_kernel.TextChanged("a")])
  second_events |> expect.to_equal([])
}

pub fn rollback_replays_remaining_pending_test() {
  let assert Ok(#(state, _, Some(#(first, _)))) =
    text_kernel.insert(new_a(), 0, "a")
  let assert Ok(#(state, _, Some(#(second, second_id)))) =
    text_kernel.insert(state, 1, "b")
  let assert Ok(#(state, events)) =
    text_kernel.rollback(state, second, second_id)

  text_kernel.value(state) |> expect.to_equal("a")
  events |> expect.to_equal([text_kernel.TextChanged("a")])
  ack(state, first)
  |> text_kernel.sequenced_value
  |> expect.to_equal("a")
}

pub fn summary_round_trips_and_rebrands_test() {
  let assert Ok(#(state, _, Some(#(op, _)))) =
    text_kernel.insert(new_a(), 0, "a")
  let state = ack(state, op)
  let raw = json.to_string(text_kernel.summary(state))
  let assert Ok(loaded) = text_kernel.from_summary(raw, replica_id.new("c"))

  let assert Ok(#(loaded, _, Some(#(op_c, _)))) =
    text_kernel.insert(loaded, 1, "c")
  ack(loaded, op_c)
  |> text_kernel.sequenced_value
  |> expect.to_equal("ac")
}

pub fn attach_promotion_and_stash_replay_test() {
  let assert Ok(#(state, _, Some(#(op, _)))) =
    text_kernel.insert(new_a(), 0, "draft")
  let promoted = text_kernel.promote_attach(state)
  text_kernel.sequenced_value(promoted) |> expect.to_equal("draft")
  promoted.pending |> expect.to_equal([])

  let #(stashed, events, replayed, _message_id) =
    text_kernel.apply_stashed_op(text_kernel.new(replica_id.new("c")), op)
  replayed |> expect.to_equal(op)
  text_kernel.value(stashed) |> expect.to_equal("draft")
  events |> expect.to_equal([text_kernel.TextChanged("draft")])
}

pub fn concurrent_edits_converge_test() {
  let state_a = new_a()
  let state_b = text_kernel.new(replica_id.new("b"))
  let assert Ok(#(state_a, _, Some(#(insert_a, _)))) =
    text_kernel.insert(state_a, 0, "a")
  let assert Ok(#(state_b, _, Some(#(insert_b, _)))) =
    text_kernel.insert(state_b, 0, "b")

  let #(state_a, _) =
    text_kernel.apply_remote(ack(state_a, insert_a), insert_b)
  let #(state_b, _) =
    text_kernel.apply_remote(ack(state_b, insert_b), insert_a)
  text_kernel.value(state_a) |> expect.to_equal(text_kernel.value(state_b))
  text_kernel.length(state_a) |> expect.to_equal(2)

  let assert Ok(#(state_a, _, Some(#(replace_a, _)))) =
    text_kernel.replace_range(state_a, 0, 2, "X")
  let assert Ok(#(state_b, _, Some(#(delete_b, _)))) =
    text_kernel.delete_range(state_b, 1, 2)
  let #(state_a, _) =
    text_kernel.apply_remote(ack(state_a, replace_a), delete_b)
  let #(state_b, _) =
    text_kernel.apply_remote(ack(state_b, delete_b), replace_a)
  text_kernel.value(state_a) |> expect.to_equal(text_kernel.value(state_b))

  let assert Ok(#(state_a, _, Some(#(insert_a2, _)))) =
    text_kernel.insert(state_a, 0, "1")
  let assert #(state_b, _, Some(#(append_b, _))) =
    text_kernel.append(state_b, "2")
  let #(state_a, _) =
    text_kernel.apply_remote(ack(state_a, insert_a2), append_b)
  let #(state_b, _) =
    text_kernel.apply_remote(ack(state_b, append_b), insert_a2)
  text_kernel.value(state_a) |> expect.to_equal(text_kernel.value(state_b))
}

pub fn anchors_survive_concurrent_edits_test() {
  let assert Ok(#(state_a, _, Some(#(op_a, _)))) =
    text_kernel.insert(new_a(), 0, "abc")
  let state_a = ack(state_a, op_a)
  let assert Ok(anchor) = text_kernel.anchor_at(state_a, 2, sequence.Before)

  let state_b = text_kernel.new(replica_id.new("b"))
  let #(state_b, _) = text_kernel.apply_remote(state_b, op_a)
  let assert Ok(#(_, _, Some(#(op_b, _)))) =
    text_kernel.insert(state_b, 0, "xy")
  let #(state_a, _) = text_kernel.apply_remote(state_a, op_b)

  text_kernel.value(state_a) |> expect.to_equal("xyabc")
  text_kernel.resolve_anchor(state_a, anchor) |> expect.to_equal(Ok(4))

  let assert Ok(round_tripped) =
    text.anchor_from_json(json.to_string(text.anchor_to_json(anchor)))
  text_kernel.resolve_anchor(state_a, round_tripped)
  |> expect.to_equal(Ok(4))

  text_kernel.resolve_anchor(state_a, text_kernel.start_anchor())
  |> expect.to_equal(Ok(0))
  text_kernel.resolve_anchor(state_a, text_kernel.end_anchor())
  |> expect.to_equal(Ok(5))
  text_kernel.anchor_at(state_a, 99, sequence.Before)
  |> expect.to_equal(Error(text_kernel.AnchorOutOfBounds(99, 5)))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test text_kernel
```

Expected: compilation fails on missing lifecycle and anchor functions.

- [ ] **Step 3: Implement lifecycle operations**

Add to `src/watershed/text_kernel.gleam`:

```gleam
import gleam/json.{type Json}

pub fn apply_remote(
  state: TextState,
  op: TextOp,
) -> #(TextState, List(TextEvent)) {
  let before = value(state)
  let sequenced = text.merge(state.sequenced, op_delta(op))
  let optimistic = replay_pending(sequenced, state.pending)
  let state = TextState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, changed_event(before, value(state)))
}

pub fn ack_local(
  state: TextState,
  op: TextOp,
) -> Result(TextState, KernelError) {
  do_ack(state, op, None)
}

pub fn ack_local_with_message_id(
  state: TextState,
  op: TextOp,
  message_id: Int,
) -> Result(TextState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: TextState,
  op: TextOp,
  expected_message_id: Option(Int),
) -> Result(TextState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOp(pending_op, pending_message_id), ..rest] -> {
      let id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_op == op && id_matches {
        True ->
          Ok(TextState(
            ..state,
            sequenced: text.merge(state.sequenced, op_delta(op)),
            pending: rest,
          ))
        False ->
          Error(UnexpectedAck(
            "expected pending message " <> int.to_string(pending_message_id),
          ))
      }
    }
  }
}

pub fn rollback(
  state: TextState,
  op: TextOp,
  message_id: Int,
) -> Result(#(TextState, List(TextEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback("pending queue is empty"))
    Ok(#(PendingOp(pending_op, pending_message_id), rest)) ->
      case pending_op == op && pending_message_id == message_id {
        False ->
          Error(UnexpectedRollback(
            "expected newest pending message "
            <> int.to_string(pending_message_id),
          ))
        True -> {
          let before = value(state)
          let optimistic = replay_pending(state.sequenced, rest)
          let state =
            TextState(..state, optimistic: optimistic, pending: rest)
          Ok(#(state, changed_event(before, value(state))))
        }
      }
  }
}

pub fn apply_stashed_op(
  state: TextState,
  op: TextOp,
) -> #(TextState, List(TextEvent), TextOp, Int) {
  let optimistic = text.merge(state.optimistic, op_delta(op))
  let #(state, events, submission) = finish_local(state, optimistic, op)
  let assert Some(#(op, message_id)) = submission
  #(state, events, op, message_id)
}

pub fn promote_attach(state: TextState) -> TextState {
  TextState(..state, sequenced: state.optimistic, pending: [])
}
```

Add summary and invariant helpers:

```gleam
pub fn summary(state: TextState) -> Json {
  text.to_json(state.sequenced)
}

pub fn from_summary(
  summary_json: String,
  replica_id: ReplicaId,
) -> Result(TextState, json.DecodeError) {
  case text.from_json(summary_json) {
    Ok(parsed) -> Ok(from_sequenced(parsed, replica_id))
    Error(error) -> Error(error)
  }
}

pub fn from_sequenced(sequenced: Text, replica_id: ReplicaId) -> TextState {
  let rebranded = text.merge(text.new(replica_id), sequenced)
  TextState(
    replica_id: replica_id,
    sequenced: rebranded,
    optimistic: rebranded,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn check_cache_coherence(state: TextState) -> Result(Nil, String) {
  case replay_pending(state.sequenced, state.pending) == state.optimistic {
    True -> Ok(Nil)
    False -> Error("optimistic cache diverged from sequenced + pending")
  }
}

fn op_delta(op: TextOp) -> Text {
  case op {
    Insert(_, _, delta)
    | DeleteRange(_, _, delta)
    | ReplaceRange(_, _, _, delta)
    | Append(_, delta) -> delta
  }
}

fn replay_pending(sequenced: Text, pending: List(PendingOp)) -> Text {
  list.fold(pending, sequenced, fn(acc, pending) {
    text.merge(acc, op_delta(pending.op))
  })
}

fn pop_last(items: List(a)) -> Result(#(a, List(a)), Nil) {
  case items {
    [] -> Error(Nil)
    [only] -> Ok(#(only, []))
    [first, ..rest] ->
      case pop_last(rest) {
        Ok(#(last, remaining)) -> Ok(#(last, [first, ..remaining]))
        Error(_) -> Error(Nil)
      }
  }
}
```

- [ ] **Step 4: Implement anchors**

Add:

```gleam
pub type AnchorError {
  AnchorOutOfBounds(index: Int, length: Int)
  UnknownAnchor
}

pub fn anchor_at(
  state: TextState,
  index: Int,
  bias: sequence.Bias,
) -> Result(sequence.Anchor, AnchorError) {
  case text.try_anchor_at(state.optimistic, index, bias) {
    Ok(anchor) -> Ok(anchor)
    Error(sequence.AnchorIndexOutOfBounds(index, length)) ->
      Error(AnchorOutOfBounds(index, length))
    Error(sequence.UnknownAnchorTarget) -> Error(UnknownAnchor)
  }
}

pub fn resolve_anchor(
  state: TextState,
  anchor: sequence.Anchor,
) -> Result(Int, AnchorError) {
  case text.try_resolve_anchor(state.optimistic, anchor) {
    Ok(index) -> Ok(index)
    Error(sequence.AnchorIndexOutOfBounds(index, length)) ->
      Error(AnchorOutOfBounds(index, length))
    Error(sequence.UnknownAnchorTarget) -> Error(UnknownAnchor)
  }
}

pub fn start_anchor() -> sequence.Anchor {
  text.start_anchor()
}

pub fn end_anchor() -> sequence.Anchor {
  text.end_anchor()
}

pub fn anchor_error_detail(error: AnchorError) -> String {
  case error {
    AnchorOutOfBounds(index, length) ->
      "anchor index " <> int.to_string(index) <> " outside 0.."
      <> int.to_string(length)
    UnknownAnchor -> "anchor target is unknown; create a new anchor"
  }
}
```

- [ ] **Step 5: Run the focused tests**

Run:

```bash
gleam test text_kernel
```

Expected: all text kernel tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/watershed/text_kernel.gleam test/watershed/text_kernel_test.gleam
git commit -m "feat(text): add CRDT lifecycle and anchors"
```

## Task 3: Integrate Text into the Channel Sum

**Files:**

- Modify: `src/watershed/channel.gleam`
- Create: `test/watershed/text_channel_test.gleam`

- [ ] **Step 1: Write failing channel summary and handle tests**

Create `test/watershed/text_channel_test.gleam`:

```gleam
import gleam/json
import gleam/option.{None, Some}
import lattice_core/replica_id
import startest/expect
import watershed/channel
import watershed/text_kernel

pub fn text_summary_round_trips_test() {
  let assert Ok(#(state, _, Some(#(op, _)))) =
    text_kernel.insert(text_kernel.new(replica_id.new("a")), 0, "hi 👋")
  let assert Ok(state) = text_kernel.ack_local(state, op)
  let summary = channel.TextSummary(state.sequenced)
  let encoded = channel.encode_snapshot(summary)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.TextChannel),
    )

  channel.same_snapshot(summary, decoded) |> expect.to_be_true()
}

pub fn text_has_no_nested_handles_test() {
  let assert Ok(#(state, _, _)) =
    text_kernel.insert(text_kernel.new(replica_id.new("a")), 0, "handle-free")
  channel.handle_addresses(channel.TextState(state)) |> expect.to_equal([])
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test text_channel
```

Expected: compilation fails on missing Text channel variants.

- [ ] **Step 3: Add imports and closed-sum variants**

In `channel.gleam`, import:

```gleam
import lattice_text/text.{type Text}
import watershed/text_kernel
```

Add:

```gleam
// ChannelType
TextChannel

// ChannelInit
InitText

// ChannelState
TextState(text_kernel.TextState)

// ChannelOp
TextOp(text_kernel.TextOp)

// ChannelEvent
TextEvent(text_kernel.TextEvent)

// Snapshot
TextSummary(state: Text)

// LocalOpMeta
TextMeta(message_id: Int)
```

Map `TextChannel` to a new `wire.channel_type_text` constant in
`type_to_string` and `type_from_string`, and map `InitText` in `init_type`.

- [ ] **Step 4: Extend construction, summary, attach, and apply dispatch**

Add these cases:

```gleam
// new
InitText -> TextState(text_kernel.new(replica_id.new(replica)))

// from_snapshot
TextSummary(state) ->
  TextState(text_kernel.from_sequenced(state, replica_id.new(replica)))

// snapshot
TextState(kernel) -> TextSummary(kernel.sequenced)

// attach_snapshot
TextState(kernel) -> TextSummary(kernel.optimistic)

// attach_state
TextState(kernel) -> TextState(text_kernel.promote_attach(kernel))

// apply_remote
TextState(kernel), TextOp(op) -> {
  let #(kernel, events) = text_kernel.apply_remote(kernel, op)
  Ok(#(TextState(kernel), list.map(events, TextEvent), []))
}
```

Add the corresponding `TextState`, `TextOp`, or `TextSummary` cases to every
exhaustive dispatch function the sequence variants extend: `channel_type`,
`snapshot_type`, `new`, `from_snapshot`, `snapshot`, `attach_snapshot`,
`attach_state`, `apply_remote`, `same_shape`, `same_snapshot`,
`handle_addresses`, `encode_snapshot`, `snapshot_decoder`, plus the
stash-replay, rollback, pending-inspection, and cache-check dispatchers. The
stash branch mirrors the `SequenceState`/`SequenceOp` branch: call
`text_kernel.apply_stashed_op`, then return the replayed `TextOp(op)` with
`TextMeta(message_id)`. The rollback branch calls `text_kernel.rollback` with
the message ID from `TextMeta`. The cache-check branch calls
`text_kernel.check_cache_coherence`.

- [ ] **Step 5: Extend acknowledgement and shape checks**

Add a `TextState`/`TextOp` branch to `ack_local`:

```gleam
TextState(kernel), TextOp(op) ->
  case local {
    TextMeta(message_id) ->
      case text_kernel.ack_local_with_message_id(kernel, op, message_id) {
        Ok(kernel) -> Ok(#(TextState(kernel), [], None))
        Error(text_kernel.UnexpectedAck(detail))
        | Error(text_kernel.UnexpectedRollback(detail)) ->
          Error(UnexpectedAck(detail))
      }
    _ -> Error(UnexpectedAck("text ack is missing its local message id"))
  }
```

Add `TextMeta(_)` to every non-text metadata rejection branch so the sum
remains exhaustive.

Add:

```gleam
fn same_text_shape(
  ours: text_kernel.TextOp,
  echoed: text_kernel.TextOp,
) -> Bool {
  case ours, echoed {
    text_kernel.Insert(i, value, _), text_kernel.Insert(i2, value2, _) ->
      i == i2 && value == value2
    text_kernel.DeleteRange(s, e, _), text_kernel.DeleteRange(s2, e2, _) ->
      s == s2 && e == e2
    text_kernel.ReplaceRange(s, e, value, _),
      text_kernel.ReplaceRange(s2, e2, value2, _)
    -> s == s2 && e == e2 && value == value2
    text_kernel.Append(value, _), text_kernel.Append(value2, _) ->
      value == value2
    _, _ -> False
  }
}
```

Route `TextOp` through `same_shape`. Compare text summaries through their
canonical encoded form:

```gleam
TextSummary(ours), TextSummary(echoed) ->
  json.to_string(text.to_json(ours)) == json.to_string(text.to_json(echoed))
```

- [ ] **Step 6: Add handle discovery and summary codecs**

Add to `handle_addresses`:

```gleam
TextState(_) -> []
```

Add to `encode_snapshot`:

```gleam
TextSummary(state) -> text.to_json(state)
```

Add to `snapshot_decoder`:

```gleam
TextChannel -> text_summary_decoder()
```

Implement:

```gleam
fn text_summary_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  case text.from_json(json.to_string(value)) {
    Ok(state) -> decode.success(TextSummary(state))
    Error(_) -> decode.failure(MapSnapshot([]), "TextSummary")
  }
}
```

- [ ] **Step 7: Run the focused tests**

Run:

```bash
gleam test text_channel
```

Expected: 2 tests pass.

- [ ] **Step 8: Commit**

```bash
git add src/watershed/channel.gleam test/watershed/text_channel_test.gleam
git commit -m "feat(text): register channel lifecycle"
```

## Task 4: Add Text Wire Codecs

**Files:**

- Modify: `src/watershed/wire.gleam`
- Modify: `src/watershed/wire/ops.gleam`
- Modify: `test/watershed/wire_test.gleam`

- [ ] **Step 1: Write failing op round-trip and malformed-delta tests**

Append to `test/watershed/wire_test.gleam` (add imports for
`watershed/text_kernel` and `gleam/option.{Some}` if not already present):

```gleam
fn sample_text_op() -> text_kernel.TextOp {
  let assert Ok(#(_, _, Some(#(op, _)))) =
    text_kernel.insert(
      text_kernel.new(replica_id.new("client-a")),
      0,
      "Ada 👩‍💻",
    )
  op
}

pub fn text_channel_op_round_trips_test() {
  let op = sample_text_op()
  let encoded =
    ops.encode_channel_envelope("notes", channel.TextOp(op))
    |> json.to_string
  let dynamic = parse(encoded, decode.dynamic)
  let assert Ok(ops.ChannelOp("notes", payload)) =
    ops.decode_op_contents(dynamic)

  decode.run(payload, ops.channel_op_decoder(channel.TextChannel))
  |> expect.to_equal(Ok(channel.TextOp(op)))
}

pub fn text_decoder_rejects_malformed_delta_test() {
  let dynamic =
    parse(
      "{\"type\":\"textAppend\",\"value\":\"x\",\"delta\":\"not-json\"}",
      decode.dynamic,
    )
  decode.run(dynamic, ops.text_op_decoder()) |> expect.to_be_error()
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test wire
```

Expected: compilation fails on missing text wire functions.

- [ ] **Step 3: Add channel tag and dispatch**

In `wire.gleam`:

```gleam
pub const channel_type_text = "text"
```

In `wire/ops.gleam`, import:

```gleam
import lattice_text/text
import watershed/text_kernel.{type TextOp}
```

Add:

```gleam
channel.TextOp(op) -> encode_text_op(op)
```

and:

```gleam
channel.TextChannel -> text_op_decoder() |> decode.map(channel.TextOp)
```

- [ ] **Step 4: Implement encoder and decoder**

Add:

```gleam
pub fn encode_text_op(op: TextOp) -> Json {
  case op {
    text_kernel.Insert(index, value, delta) ->
      json.object([
        #("type", json.string("textInsert")),
        #("index", json.int(index)),
        #("value", json.string(value)),
        #("delta", text_delta_json(delta)),
      ])
    text_kernel.DeleteRange(start, end, delta) ->
      json.object([
        #("type", json.string("textDeleteRange")),
        #("start", json.int(start)),
        #("end", json.int(end)),
        #("delta", text_delta_json(delta)),
      ])
    text_kernel.ReplaceRange(start, end, value, delta) ->
      json.object([
        #("type", json.string("textReplaceRange")),
        #("start", json.int(start)),
        #("end", json.int(end)),
        #("value", json.string(value)),
        #("delta", text_delta_json(delta)),
      ])
    text_kernel.Append(value, delta) ->
      json.object([
        #("type", json.string("textAppend")),
        #("value", json.string(value)),
        #("delta", text_delta_json(delta)),
      ])
  }
}

fn text_delta_json(delta: text.Text) -> Json {
  json.string(json.to_string(text.to_json(delta)))
}
```

Implement:

```gleam
pub fn text_op_decoder() -> Decoder(TextOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "textInsert" -> {
      use index <- decode.field("index", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", text_delta_decoder())
      decode.success(text_kernel.Insert(index, value, delta))
    }
    "textDeleteRange" -> {
      use start <- decode.field("start", decode.int)
      use end <- decode.field("end", decode.int)
      use delta <- decode.field("delta", text_delta_decoder())
      decode.success(text_kernel.DeleteRange(start, end, delta))
    }
    "textReplaceRange" -> {
      use start <- decode.field("start", decode.int)
      use end <- decode.field("end", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", text_delta_decoder())
      decode.success(text_kernel.ReplaceRange(start, end, value, delta))
    }
    "textAppend" -> {
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", text_delta_decoder())
      decode.success(text_kernel.Append(value, delta))
    }
    _ ->
      decode.failure(
        text_kernel.Append("", default_text_delta()),
        "TextOp",
      )
  }
}

fn text_delta_decoder() -> Decoder(text.Text) {
  use encoded <- decode.then(decode.string)
  case text.from_json(encoded) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_text_delta(), "TextDelta")
  }
}

fn default_text_delta() -> text.Text {
  text.new(replica_id.new(""))
}
```

- [ ] **Step 5: Run wire tests**

Run:

```bash
gleam test wire
```

Expected: all wire tests pass, including the new text tests.

- [ ] **Step 6: Commit**

```bash
git add src/watershed/wire.gleam src/watershed/wire/ops.gleam test/watershed/wire_test.gleam
git commit -m "feat(text): add wire codecs"
```

## Task 5: Add Runtime-Core Mutations, Reads, and Anchors

**Files:**

- Modify: `src/watershed/runtime_core.gleam`
- Modify: `test/watershed/text_channel_test.gleam`

- [ ] **Step 1: Write failing detached, attached, read, no-op, and error tests**

Extend `text_channel_test.gleam` using the bootstrap helper from
`or_set_channel_test.gleam`. Add imports for `gleam/list`, `gleam/string`,
`lattice_sequence/sequence`, `watershed/handle`, and `watershed/runtime_core`.
Add:

```gleam
pub fn detached_text_attaches_then_emits_ops_test() {
  let address = "text-1"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitText)

  let assert Ok(#(core, events, outbound)) =
    runtime_core.text_insert(core, address, 0, "a")
  outbound |> expect.to_equal([])
  events
  |> expect.to_equal([
    #(address, channel.TextEvent(text_kernel.TextChanged("a"))),
  ])

  let assert Ok(#(core, _, attach_outbound)) =
    runtime_core.set(core, "root", "notes", handle.encode_handle(address))
  list.length(attach_outbound) |> expect.to_equal(2)

  let assert Ok(#(core, _, [op])) =
    runtime_core.text_replace_range(core, address, 0, 1, "A")
  json.to_string(op.contents)
  |> string.contains("\"type\":\"textReplaceRange\"")
  |> expect.to_be_true()
  runtime_core.text_value(core, address) |> expect.to_equal("A")
  runtime_core.text_length(core, address) |> expect.to_equal(1)
  runtime_core.text_substring(core, address, 0, 1)
  |> expect.to_equal(Ok("A"))

  let assert Ok(anchor) =
    runtime_core.text_anchor_at(core, address, 1, sequence.After)
  runtime_core.text_resolve_anchor(core, address, anchor)
  |> expect.to_equal(Ok(1))
}

pub fn text_empty_edit_is_a_successful_no_op_test() {
  let core =
    bootstrap()
    |> runtime_core.create_detached("text-1", channel.InitText)

  let assert Ok(#(core, events, outbound)) =
    runtime_core.text_insert(core, "text-1", 0, "")
  events |> expect.to_equal([])
  outbound |> expect.to_equal([])
  runtime_core.text_value(core, "text-1") |> expect.to_equal("")
}

pub fn text_invalid_range_is_explicit_core_error_test() {
  let core =
    bootstrap()
    |> runtime_core.create_detached("text-1", channel.InitText)

  runtime_core.text_delete_range(core, "text-1", 0, 1)
  |> expect.to_equal(Error(runtime_core.TextOpFailed(
    "text-1",
    "delete range 0..1 invalid for length 0",
  )))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test text_channel
```

Expected: compilation fails on missing runtime-core text functions.

- [ ] **Step 3: Add the core error and generic mutation helper**

Import `watershed/text_kernel` and `lattice_sequence/sequence` in
`runtime_core.gleam` and add to `CoreError`:

```gleam
TextOpFailed(address: String, detail: String)
```

Add:

```gleam
fn mutate_text(
  core: Core,
  address: String,
  mutate: fn(text_kernel.TextState) ->
    Result(text_kernel.Applied, text_kernel.EditError),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_text(core, address) {
    Error(error) -> Error(error)
    Ok(Detached(kernel)) ->
      case mutate(kernel) {
        Error(error) ->
          Error(TextOpFailed(address, text_kernel.edit_error_detail(error)))
        Ok(#(_kernel, _events, option.None)) -> Ok(#(core, [], []))
        Ok(#(kernel, events, option.Some(_))) ->
          Ok(#(
            put_detached_channel(core, address, channel.TextState(kernel)),
            tag_text_events(address, events),
            [],
          ))
      }
    Ok(Attached(kernel)) ->
      case mutate(kernel) {
        Error(error) ->
          Error(TextOpFailed(address, text_kernel.edit_error_detail(error)))
        Ok(#(_kernel, _events, option.None)) -> Ok(#(core, [], []))
        Ok(#(kernel, events, option.Some(#(op, message_id)))) ->
          Ok(stamp_attached(
            core,
            address,
            channel.TextState(kernel),
            tag_text_events(address, events),
            channel.TextOp(op),
            channel.TextMeta(message_id),
          ))
      }
  }
}

fn locate_text(
  core: Core,
  address: String,
) -> Result(Located(text_kernel.TextState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.TextState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.TextState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.TextChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn tag_text_events(
  address: String,
  events: List(text_kernel.TextEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.TextEvent(event)) })
}
```

A validated empty edit returns `option.None`; the kernel state is unchanged,
so return the core untouched with no events and no outbound ops.

- [ ] **Step 4: Add public mutation, read, and anchor functions**

```gleam
pub fn text_insert(
  core: Core,
  address: String,
  index: Int,
  value: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  mutate_text(core, address, text_kernel.insert(_, index, value))
}

pub fn text_delete_range(
  core: Core,
  address: String,
  start: Int,
  end: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  mutate_text(core, address, text_kernel.delete_range(_, start, end))
}

pub fn text_replace_range(
  core: Core,
  address: String,
  start: Int,
  end: Int,
  value: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  mutate_text(core, address, text_kernel.replace_range(_, start, end, value))
}

pub fn text_append(
  core: Core,
  address: String,
  value: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  mutate_text(core, address, fn(kernel) {
    Ok(text_kernel.append(kernel, value))
  })
}

pub fn text_value(core: Core, address: String) -> String {
  case find_channel(core, address) {
    Some(channel.TextState(kernel)) -> text_kernel.value(kernel)
    _ -> ""
  }
}

pub fn text_length(core: Core, address: String) -> Int {
  case find_channel(core, address) {
    Some(channel.TextState(kernel)) -> text_kernel.length(kernel)
    _ -> 0
  }
}

pub fn text_substring(
  core: Core,
  address: String,
  start: Int,
  end: Int,
) -> Result(String, CoreError) {
  case find_channel(core, address) {
    Some(channel.TextState(kernel)) ->
      case text_kernel.substring(kernel, start, end) {
        Ok(value) -> Ok(value)
        Error(error) ->
          Error(TextOpFailed(address, text_kernel.edit_error_detail(error)))
      }
    _ ->
      case start == 0 && end == 0 {
        True -> Ok("")
        False ->
          Error(TextOpFailed(
            address,
            text_kernel.edit_error_detail(
              text_kernel.SubstringOutOfBounds(start, end, 0),
            ),
          ))
      }
  }
}

pub fn text_anchor_at(
  core: Core,
  address: String,
  index: Int,
  bias: sequence.Bias,
) -> Result(sequence.Anchor, CoreError) {
  case find_channel(core, address) {
    Some(channel.TextState(kernel)) ->
      case text_kernel.anchor_at(kernel, index, bias) {
        Ok(anchor) -> Ok(anchor)
        Error(error) ->
          Error(TextOpFailed(address, text_kernel.anchor_error_detail(error)))
      }
    _ -> Error(TextOpFailed(address, "text channel not found"))
  }
}

pub fn text_resolve_anchor(
  core: Core,
  address: String,
  anchor: sequence.Anchor,
) -> Result(Int, CoreError) {
  case find_channel(core, address) {
    Some(channel.TextState(kernel)) ->
      case text_kernel.resolve_anchor(kernel, anchor) {
        Ok(index) -> Ok(index)
        Error(error) ->
          Error(TextOpFailed(address, text_kernel.anchor_error_detail(error)))
      }
    _ -> Error(TextOpFailed(address, "text channel not found"))
  }
}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
gleam test text_channel
```

Expected: all text channel tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/watershed/runtime_core.gleam test/watershed/text_channel_test.gleam
git commit -m "feat(text): add runtime core operations"
```

## Task 6: Expose Erlang and JavaScript Public APIs

**Files:**

- Modify: `src/watershed/runtime.gleam`
- Modify: `src/watershed/runtime_js.gleam`
- Modify: `src/watershed/schema.gleam`
- Modify: `src/watershed.gleam`
- Modify: `src/watershed_js.gleam`
- Modify: `test/watershed/schema_test.gleam`
- Modify: `test/watershed/sluice/driver_test.gleam`
- Modify: `test/watershed/sluice/driver_js_test.gleam`

- [ ] **Step 1: Write failing schema and Erlang Sluice tests**

Append to `schema_test.gleam`:

```gleam
pub fn text_channel_field_test() {
  let notes: schema.ChannelField(Player, schema.TextChannel) =
    schema.channel_field("notes")
  schema.channel_field_key(notes) |> expect.to_equal("notes")
}
```

Append to `sluice/driver_test.gleam`:

```gleam
@target(erlang)
pub fn shared_text_converges_test() {
  let sluice = start("shared-text")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(text_a) = watershed.create_text(doc_a)
  let assert Ok(Nil) = watershed.text_insert(text_a, 0, "hello")
  watershed.set(
    watershed.root(doc_a),
    "notes",
    watershed.text_handle_of(text_a),
  )
  sluice.settle(sluice)

  let assert Some(text_handle) = watershed.get(watershed.root(doc_b), "notes")
  let assert Ok(text_b) = watershed.resolve_text(doc_b, text_handle)

  let assert Ok(Nil) = watershed.text_insert(text_a, 5, " 👋")
  let assert Ok(Nil) = watershed.text_append(text_b, "!")
  sluice.settle(sluice)
  watershed.text_value(text_a)
  |> expect.to_equal(watershed.text_value(text_b))

  let assert Ok(Nil) = watershed.text_replace_range(text_a, 0, 1, "H")
  let assert Ok(Nil) = watershed.text_delete_range(text_b, 1, 2)
  sluice.settle(sluice)
  watershed.text_value(text_a)
  |> expect.to_equal(watershed.text_value(text_b))

  let assert Ok(anchor) = watershed.text_anchor_at(text_a, 0, watershed.Before)
  watershed.text_resolve_anchor(text_a, anchor) |> expect.to_equal(Ok(0))
  watershed.text_resolve_anchor(text_a, watershed.text_end_anchor())
  |> expect.to_equal(Ok(watershed.text_length(text_a)))

  watershed.text_delete_range(text_a, 0, 99) |> expect.to_be_error()
}
```

- [ ] **Step 2: Write the JavaScript Sluice mirror**

Append to `sluice/driver_js_test.gleam`:

```gleam
@target(javascript)
pub fn shared_text_converges_test() {
  let sluice = sluice_js.start(tenant: "default", document: "shared-text-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(text_a) = watershed_js.create_text(doc_a)
  let assert Ok(Nil) = watershed_js.text_insert(text_a, 0, "hello")
  watershed_js.set(
    watershed_js.root(doc_a),
    "notes",
    watershed_js.text_handle_of(text_a),
  )
  sluice_js.settle(sluice)

  let assert Some(text_handle) =
    watershed_js.get(watershed_js.root(doc_b), "notes")
  let assert Ok(text_b) = watershed_js.resolve_text(doc_b, text_handle)

  let assert Ok(Nil) = watershed_js.text_insert(text_a, 5, " 👋")
  let assert Ok(Nil) = watershed_js.text_append(text_b, "!")
  sluice_js.settle(sluice)
  watershed_js.text_value(text_a)
  |> expect.to_equal(watershed_js.text_value(text_b))

  let assert Ok(anchor) =
    watershed_js.text_anchor_at(text_a, 0, watershed_js.Before)
  watershed_js.text_resolve_anchor(text_a, anchor) |> expect.to_equal(Ok(0))

  watershed_js.text_delete_range(text_a, 0, 99) |> expect.to_be_error()
}
```

- [ ] **Step 3: Run the facade tests and verify they fail**

Run:

```bash
gleam test schema
gleam test sluice/driver
gleam test --target javascript sluice/driver_js
```

Expected: compilation fails on missing Text public APIs and schema kind.

- [ ] **Step 4: Add runtime messages and result-returning edit handling**

In `runtime.gleam`, add `InitText` to the channel imports, import
`lattice_sequence/sequence`, and add messages:

```gleam
InsertText(
  address: String,
  index: Int,
  value: String,
  reply: Subject(Result(Nil, String)),
)
DeleteTextRange(
  address: String,
  start: Int,
  end: Int,
  reply: Subject(Result(Nil, String)),
)
ReplaceTextRange(
  address: String,
  start: Int,
  end: Int,
  value: String,
  reply: Subject(Result(Nil, String)),
)
AppendText(address: String, value: String, reply: Subject(Result(Nil, String)))
CreateText(reply: Subject(Result(String, String)))
GetTextValue(address: String, reply: Subject(String))
GetTextLength(address: String, reply: Subject(Int))
GetTextSubstring(
  address: String,
  start: Int,
  end: Int,
  reply: Subject(Result(String, String)),
)
AnchorTextAt(
  address: String,
  index: Int,
  bias: sequence.Bias,
  reply: Subject(Result(sequence.Anchor, String)),
)
ResolveTextAnchor(
  address: String,
  anchor: sequence.Anchor,
  reply: Subject(Result(Int, String)),
)
```

Handle `CreateText`, `GetTextValue`, and `GetTextLength` exactly like their
sequence counterparts (`CreateSequence`, `GetSequenceValues`,
`GetSequenceLength`), swapping in `channel.InitText`,
`runtime_core.text_value`, and `runtime_core.text_length`.

Reuse `edit_sequence_with_result` for the four text edit messages by widening
its error match in both the `Ready` and `Reconnecting` branches:

```gleam
Error(runtime_core.SequenceOpFailed(_, detail))
| Error(runtime_core.TextOpFailed(_, detail)) -> {
  process.send(reply, Error(detail))
  actor.continue(state)
}
```

The helper now serves both DDS types; each text edit message calls it with the
matching `runtime_core.text_*` callback and a verb such as `"text insert"`.

Handle the Result-returning reads without going through the edit path. Follow
the same phase access as `GetSequenceValues`: when the phase is `Ready` or
`Reconnecting`, send the mapped core result; in any other phase, send
`Error("substring before the document connection is ready")` (or the
anchor-specific wording below). With a core in hand, `GetTextSubstring`
sends:

```gleam
process.send(
  reply,
  map_text_read(runtime_core.text_substring(core, address, start, end)),
)
```

Add one shared mapper and use it for substring, anchor-at, and resolve-anchor:

```gleam
fn map_text_read(result: Result(a, runtime_core.CoreError)) -> Result(a, String) {
  case result {
    Ok(value) -> Ok(value)
    Error(runtime_core.TextOpFailed(_, detail)) -> Error(detail)
    Error(error) -> Error(string.inspect(error))
  }
}
```

`AnchorTextAt` and `ResolveTextAnchor` follow the same shape with
`runtime_core.text_anchor_at` and `runtime_core.text_resolve_anchor`, sending
`Error("anchor before the document connection is ready")` when no core is
available.

- [ ] **Step 5: Add JavaScript runtime operations**

In `runtime_js.gleam`, import `lattice_sequence/sequence` and add:

```gleam
pub fn text_insert(
  runtime: Runtime,
  address: String,
  index: Int,
  value: String,
) -> Result(Nil, String)

pub fn text_delete_range(
  runtime: Runtime,
  address: String,
  start: Int,
  end: Int,
) -> Result(Nil, String)

pub fn text_replace_range(
  runtime: Runtime,
  address: String,
  start: Int,
  end: Int,
  value: String,
) -> Result(Nil, String)

pub fn text_append(
  runtime: Runtime,
  address: String,
  value: String,
) -> Result(Nil, String)

pub fn text_value(runtime: Runtime, address: String) -> String
pub fn text_length(runtime: Runtime, address: String) -> Int

pub fn text_substring(
  runtime: Runtime,
  address: String,
  start: Int,
  end: Int,
) -> Result(String, String)

pub fn text_anchor_at(
  runtime: Runtime,
  address: String,
  index: Int,
  bias: sequence.Bias,
) -> Result(sequence.Anchor, String)

pub fn text_resolve_anchor(
  runtime: Runtime,
  address: String,
  anchor: sequence.Anchor,
) -> Result(Int, String)

pub fn create_text(runtime: Runtime) -> Result(String, String)
```

Widen the JavaScript `edit_sequence_with_result` error match the same way as
the Erlang helper:

```gleam
Error(runtime_core.SequenceOpFailed(_, detail))
| Error(runtime_core.TextOpFailed(_, detail)) -> Error(detail)
```

The four text edit functions destructure `Runtime(cell)` and pass `cell` plus
the matching `runtime_core.text_*` callback to that helper. `text_value` and
`text_length` mirror `sequence_values` and `sequence_length` over the current
cell state, defaulting to `""` and `0` before ready. `text_substring`,
`text_anchor_at`, and `text_resolve_anchor` read the current core the same
way, map `TextOpFailed(_, detail)` to `Error(detail)`, map other core errors
through `string.inspect`, and return
`Error("text read before the document connection is ready")` when no core is
available. `create_text` mirrors `create_sequence` with `channel.InitText`.

- [ ] **Step 6: Add the schema kind and top-level opaque types**

In `schema.gleam`:

```gleam
/// A collaborative grapheme-indexed plain-text document.
pub type TextChannel
```

In both `watershed.gleam` and `watershed_js.gleam`, import
`watershed/text_kernel`, `lattice_sequence/sequence`, and
`lattice_text/text`, then add the target-specific definitions:

```gleam
// watershed.gleam
pub opaque type SharedText {
  SharedText(runtime: Subject(runtime.Msg), address: String)
}

// watershed_js.gleam
pub opaque type SharedText {
  SharedText(runtime: runtime_js.Runtime, address: String)
}
```

Add to both facades the shared anchor types:

```gleam
pub opaque type TextAnchor {
  TextAnchor(anchor: sequence.Anchor)
}

pub type AnchorBias {
  Before
  After
}

fn to_bias(bias: AnchorBias) -> sequence.Bias {
  case bias {
    Before -> sequence.Before
    After -> sequence.After
  }
}
```

- [ ] **Step 7: Add public create, handle, resolve, edit, read, anchor, and subscribe APIs**

Expose the same surface on both targets:

```gleam
pub fn create_text(document: Document) -> Result(SharedText, String)
pub fn text_handle_of(text: SharedText) -> Json
pub fn resolve_text(
  document: Document,
  value: Json,
) -> Result(SharedText, String)
pub fn text_insert(
  text: SharedText,
  index: Int,
  value: String,
) -> Result(Nil, String)
pub fn text_delete_range(
  text: SharedText,
  start: Int,
  end: Int,
) -> Result(Nil, String)
pub fn text_replace_range(
  text: SharedText,
  start: Int,
  end: Int,
  value: String,
) -> Result(Nil, String)
pub fn text_append(text: SharedText, value: String) -> Result(Nil, String)
pub fn text_value(text: SharedText) -> String
pub fn text_length(text: SharedText) -> Int
pub fn text_substring(
  text: SharedText,
  start: Int,
  end: Int,
) -> Result(String, String)
pub fn text_anchor_at(
  text: SharedText,
  index: Int,
  bias: AnchorBias,
) -> Result(TextAnchor, String)
pub fn text_resolve_anchor(
  text: SharedText,
  anchor: TextAnchor,
) -> Result(Int, String)
pub fn text_start_anchor() -> TextAnchor
pub fn text_end_anchor() -> TextAnchor
pub fn text_anchor_to_json(anchor: TextAnchor) -> Json
pub fn text_anchor_from_json(encoded: String) -> Result(TextAnchor, String)
```

The anchor codecs are pure and identical on both targets:

```gleam
pub fn text_start_anchor() -> TextAnchor {
  TextAnchor(text_kernel.start_anchor())
}

pub fn text_end_anchor() -> TextAnchor {
  TextAnchor(text_kernel.end_anchor())
}

pub fn text_anchor_to_json(anchor: TextAnchor) -> Json {
  let TextAnchor(inner) = anchor
  text.anchor_to_json(inner)
}

pub fn text_anchor_from_json(encoded: String) -> Result(TextAnchor, String) {
  case text.anchor_from_json(encoded) {
    Ok(anchor) -> Ok(TextAnchor(anchor))
    Error(_) -> Error("invalid text anchor JSON")
  }
}
```

`text_anchor_at` unwraps `to_bias(bias)`, calls the runtime operation, and
wraps the result in `TextAnchor`. `text_resolve_anchor` unwraps the
`TextAnchor` before calling the runtime operation. The remaining functions
mirror their `SharedSequence` counterparts, swapping in the text runtime
messages and `runtime_js.text_*` operations.

Erlang subscriptions return:

```gleam
pub fn subscribe_text(text: SharedText) -> Subject(text_kernel.TextEvent)
```

JavaScript subscriptions accept:

```gleam
pub fn subscribe_text(
  text: SharedText,
  handler: fn(text_kernel.TextEvent) -> Nil,
) -> Nil
```

Narrow `channel.TextEvent(inner)` in both implementations.

- [ ] **Step 8: Add typed-field helpers**

Add to both public facades:

```gleam
pub fn set_text_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
  text: SharedText,
) -> Nil

pub fn resolve_text_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
) -> Result(Option(SharedText), String)
```

Add Erlang:

```gleam
pub fn ensure_text(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
) -> Result(SharedText, String)
```

Add the JavaScript callback form:

```gleam
pub fn ensure_text(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
  done: fn(Result(SharedText, String)) -> Nil,
) -> Nil
```

Use the existing generic `put_channel_field`, `get_channel_field`, and
`ensure_channel` helpers.

- [ ] **Step 9: Run schema and end-to-end tests**

Run:

```bash
gleam test schema
gleam test sluice/driver
gleam test --target javascript sluice/driver_js
```

Expected: all targeted tests pass.

- [ ] **Step 10: Commit**

```bash
git add src/watershed/runtime.gleam src/watershed/runtime_js.gleam src/watershed/schema.gleam src/watershed.gleam src/watershed_js.gleam test/watershed/schema_test.gleam test/watershed/sluice/driver_test.gleam test/watershed/sluice/driver_js_test.gleam
git commit -m "feat(text): expose public facades"
```

## Task 7: Add Model-Based Fuzz Coverage

**Files:**

- Create: `test/watershed/fuzz/text_model.gleam`
- Create: `test/watershed/text_fuzz_test.gleam`

- [ ] **Step 1: Write the failing fuzz test**

Create `test/watershed/text_fuzz_test.gleam`:

```gleam
import gleam/list
import gleam/json
import gleam/option.{None, Some}
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{ClientOp, KernelModel, Synchronize}
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
  let assert Ok(#(_, _, Some(#(op, _)))) =
    text_kernel.insert(text_kernel.new(replica_id.new("a")), 0, "x👍")
  let assert text_kernel.Insert(index, value, delta) = op
  let commands = [
    text_model.InsertCmd(0, "x👍", None),
    text_model.InsertCmd(index, value, Some(delta)),
  ]
  list.each(commands, fn(command) {
    let assert Ok(decoded) =
      json.parse(json.to_string(model.op_to_json(command)), model.op_decoder)
    decoded |> expect.to_equal(command)
  })
}

pub fn shared_replica_id_is_caught_test() {
  let model = text_model.model()
  let buggy =
    KernelModel(..model, init: fn(_id) {
      text_kernel.new(replica_id.new("client-0"))
    })
  let script = [
    ClientOp(1, text_model.InsertCmd(0, "a", None)),
    ClientOp(2, text_model.InsertCmd(0, "b", None)),
    Synchronize,
  ]
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected duplicate text replica ids to fail"
  }
}
```

- [ ] **Step 2: Run the focused fuzz test and verify it fails**

Run:

```bash
gleam test text_fuzz
```

Expected: compilation fails because `text_model` does not exist.

- [ ] **Step 3: Define commands, generator, and JSON codecs**

Create `test/watershed/fuzz/text_model.gleam` with:

```gleam
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id
import lattice_text/text.{type Text}
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, Capabilities, KernelModel,
}
import watershed/text_kernel

pub type TextCommand {
  InsertCmd(index_seed: Int, value: String, delta: Option(Text))
  DeleteRangeCmd(start_seed: Int, end_seed: Int, delta: Option(Text))
  ReplaceRangeCmd(
    start_seed: Int,
    end_seed: Int,
    value: String,
    delta: Option(Text),
  )
  AppendCmd(value: String, delta: Option(Text))
}
```

Generate commands from four small non-negative integers with a
grapheme-heavy value pool:

```gleam
fn value_pool(seed: Int) -> String {
  case seed % 5 {
    0 -> "a"
    1 -> "bé"
    2 -> "👍"
    3 -> "e\u{0301}"
    _ -> "水水"
  }
}

fn op_generator() -> qcheck.Generator(TextCommand) {
  qcheck.tuple4(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(parts) {
    let value = value_pool(parts.3)
    case parts.0 % 4 {
      0 -> InsertCmd(parts.1, value, None)
      1 -> DeleteRangeCmd(parts.1, parts.2, None)
      2 -> ReplaceRangeCmd(parts.1, parts.2, value, None)
      _ -> AppendCmd(value, None)
    }
  })
}
```

Add JSON codecs. Encode `delta` as `null` or a JSON string containing
`text.to_json(delta)`; decode with `text.from_json`:

```gleam
fn delta_to_json(delta: Option(Text)) -> json.Json {
  case delta {
    None -> json.null()
    Some(delta) -> json.string(json.to_string(text.to_json(delta)))
  }
}

fn delta_decoder() -> decode.Decoder(Option(Text)) {
  use encoded <- decode.then(decode.optional(decode.string))
  case encoded {
    None -> decode.success(None)
    Some(encoded) ->
      case text.from_json(encoded) {
        Ok(delta) -> decode.success(Some(delta))
        Error(_) -> decode.failure(None, "TextDelta")
      }
  }
}

pub fn op_to_json(command: TextCommand) -> json.Json {
  case command {
    InsertCmd(index, value, delta) ->
      json.object([
        #("tag", json.string("insert")),
        #("index", json.int(index)),
        #("value", json.string(value)),
        #("delta", delta_to_json(delta)),
      ])
    DeleteRangeCmd(start, end, delta) ->
      json.object([
        #("tag", json.string("deleteRange")),
        #("start", json.int(start)),
        #("end", json.int(end)),
        #("delta", delta_to_json(delta)),
      ])
    ReplaceRangeCmd(start, end, value, delta) ->
      json.object([
        #("tag", json.string("replaceRange")),
        #("start", json.int(start)),
        #("end", json.int(end)),
        #("value", json.string(value)),
        #("delta", delta_to_json(delta)),
      ])
    AppendCmd(value, delta) ->
      json.object([
        #("tag", json.string("append")),
        #("value", json.string(value)),
        #("delta", delta_to_json(delta)),
      ])
  }
}

pub fn op_decoder() -> decode.Decoder(TextCommand) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "insert" -> {
      use index <- decode.field("index", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(InsertCmd(index, value, delta))
    }
    "deleteRange" -> {
      use start <- decode.field("start", decode.int)
      use end <- decode.field("end", decode.int)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(DeleteRangeCmd(start, end, delta))
    }
    "replaceRange" -> {
      use start <- decode.field("start", decode.int)
      use end <- decode.field("end", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(ReplaceRangeCmd(start, end, value, delta))
    }
    "append" -> {
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(AppendCmd(value, delta))
    }
    _ -> decode.failure(AppendCmd("", None), "TextCommand")
  }
}
```

- [ ] **Step 4: Normalize generated commands and route kernel deltas**

Implement `submit` so every generated command becomes valid and non-empty for
the current state. Range commands on empty text reroute to an insert:

```gleam
fn submit(
  state: text_kernel.TextState,
  command: TextCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(text_kernel.TextState, Option(TextCommand)) {
  let visible_length = text_kernel.length(state)
  case command {
    InsertCmd(seed, value, _) -> {
      let index = seed % { visible_length + 1 }
      let assert Ok(#(state, _, Some(#(op, _)))) =
        text_kernel.insert(state, index, value)
      let assert text_kernel.Insert(_, actual, delta) = op
      #(state, Some(InsertCmd(index, actual, Some(delta))))
    }
    DeleteRangeCmd(start_seed, end_seed, _) if visible_length > 0 -> {
      let start = start_seed % visible_length
      let end = start + 1 + { end_seed % { visible_length - start } }
      let assert Ok(#(state, _, Some(#(op, _)))) =
        text_kernel.delete_range(state, start, end)
      let assert text_kernel.DeleteRange(_, _, delta) = op
      #(state, Some(DeleteRangeCmd(start, end, Some(delta))))
    }
    ReplaceRangeCmd(start_seed, end_seed, value, _) if visible_length > 0 -> {
      let start = start_seed % visible_length
      let end = start + 1 + { end_seed % { visible_length - start } }
      let assert Ok(#(state, _, Some(#(op, _)))) =
        text_kernel.replace_range(state, start, end, value)
      let assert text_kernel.ReplaceRange(_, _, actual, delta) = op
      #(state, Some(ReplaceRangeCmd(start, end, actual, Some(delta))))
    }
    AppendCmd(value, _) -> {
      let assert #(state, _, Some(#(op, _))) = text_kernel.append(state, value)
      let assert text_kernel.Append(actual, delta) = op
      #(state, Some(AppendCmd(actual, Some(delta))))
    }
    DeleteRangeCmd(seed, _, _) | ReplaceRangeCmd(seed, _, _, _) ->
      submit(state, InsertCmd(seed, "seed", None), meta)
  }
}
```

Convert routed commands back to `text_kernel.TextOp`; panic if a routed
command still has `delta: None`:

```gleam
fn to_kernel_op(command: TextCommand, context: String) -> text_kernel.TextOp {
  case command {
    InsertCmd(index, value, Some(delta)) ->
      text_kernel.Insert(index, value, delta)
    DeleteRangeCmd(start, end, Some(delta)) ->
      text_kernel.DeleteRange(start, end, delta)
    ReplaceRangeCmd(start, end, value, Some(delta)) ->
      text_kernel.ReplaceRange(start, end, value, delta)
    AppendCmd(value, Some(delta)) -> text_kernel.Append(value, delta)
    _ -> panic as { "text command missing delta in " <> context }
  }
}
```

- [ ] **Step 5: Implement model lifecycle, summary loading, and checks**

Use:

```gleam
fn apply_remote(state, command, _meta) {
  let #(state, _) =
    text_kernel.apply_remote(state, to_kernel_op(command, "apply_remote"))
  Ok(state)
}

fn ack_local(state, command, _meta) {
  case text_kernel.ack_local(state, to_kernel_op(command, "ack_local")) {
    Ok(state) -> Ok(state)
    Error(text_kernel.UnexpectedAck(detail))
    | Error(text_kernel.UnexpectedRollback(detail)) -> Error(detail)
  }
}

fn rollback(state, command) {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(text_kernel.PendingOp(_, message_id)) ->
      case
        text_kernel.rollback(state, to_kernel_op(command, "rollback"), message_id)
      {
        Ok(#(state, _)) -> state
        Error(_) -> state
      }
  }
}

fn apply_stashed(state, command, meta) {
  let #(state, routed) = submit(state, command, meta)
  let assert Some(routed) = routed
  #(state, routed)
}

fn load_from_synced(state, id) {
  let raw = json.to_string(text_kernel.summary(state))
  let assert Ok(loaded) =
    text_kernel.from_summary(
      raw,
      replica_id.new("client-" <> int.to_string(id)),
    )
  loaded
}
```

Build the model:

```gleam
pub fn model() -> KernelModel(text_kernel.TextState, TextCommand, String) {
  KernelModel(
    name: "text",
    init: fn(id) {
      text_kernel.new(replica_id.new("client-" <> int.to_string(id)))
    },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: text_kernel.value,
    gen_op: op_generator(),
    check: Some(text_kernel.check_cache_coherence),
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: None,
      rollback: Some(rollback),
      resubmit: None,
      apply_stashed: Some(apply_stashed),
      react: None,
      remove_member: None,
    ),
  )
}
```

The text model intentionally uses convergence plus cache coherence instead of
a log oracle: author-local indexes cannot be replayed independently as one
global string under concurrency. The deterministic kernel tests pin specific
conflict semantics; this fuzz model explores delivery, rollback, stash, and
summary schedules over grapheme-heavy content.

- [ ] **Step 6: Run focused and deeper text fuzzing**

Run:

```bash
gleam test text_fuzz
FUZZ_ITERATIONS=1000 gleam test text_fuzz
```

Expected: all text fuzz tests pass.

- [ ] **Step 7: Commit**

```bash
git add test/watershed/fuzz/text_model.gleam test/watershed/text_fuzz_test.gleam
git commit -m "test(text): add model fuzz coverage"
```

## Task 8: Document and Validate the Complete DDS

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Update the README**

Add `SharedText` to the supported DDS summary. Add `text_kernel` to the
target-agnostic pure-core list. Add this short public API example:

```gleam
let assert Ok(notes) = watershed.create_text(doc)
let assert Ok(Nil) = watershed.text_insert(notes, 0, "hello")
let assert Ok(Nil) = watershed.text_append(notes, " 👋")
watershed.text_value(notes)
```

State that all indexes are grapheme indexes, so emoji and combining sequences
count as one unit. Mention cursor anchors: stable positions that survive
concurrent edits, created with `text_anchor_at` and resolved with
`text_resolve_anchor`. State that empty edits validate their indexes and then
succeed without producing ops.

- [ ] **Step 2: Format and inspect the diff**

Run:

```bash
gleam format
git diff --no-ext-diff --check
```

Expected: formatting succeeds and the diff has no whitespace errors.

- [ ] **Step 3: Run targeted text verification**

Run:

```bash
gleam test text_kernel
gleam test text_channel
gleam test wire
gleam test schema
gleam test text_fuzz
gleam test sluice/driver
gleam test --target javascript sluice/driver_js
```

Expected: every targeted test passes.

- [ ] **Step 4: Run repository validation**

Run:

```bash
just test
just build
just lint
just fuzz
```

Expected: the full test suite, Erlang and JavaScript builds, formatting check,
and 5,000-iteration fuzz sweep all pass.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(text): document SharedText"
```

- [ ] **Step 6: Review the final branch diff**

Run:

```bash
git status --short
git log --oneline --decorate -10
git diff --no-ext-diff main...HEAD --stat
```

Expected: the worktree is clean, the text work is split into the planned
commits, and only the files listed in this plan changed.

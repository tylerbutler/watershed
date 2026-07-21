# Collaborative Sequence DDS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a convergent Array-like `SharedSequence` DDS for arbitrary JSON values, backed by the local `lattice_sequence` CRDT.

**Architecture:** A pure `sequence_kernel` will keep sequenced, optimistic, and pending CRDT state, following Watershed's existing lattice-backed kernels. The closed channel sums, wire codecs, runtime core, Erlang and JavaScript runtimes, and public facades will expose insert, delete, move, replace, values, length, handles, typed fields, and subscriptions. `lattice_text` will be linked for the next text-specific phase but will not be used by this DDS.

**Tech Stack:** Gleam, `lattice_sequence`, `lattice_core`, `gleam_json`, startest, qcheck, Watershed runtime core, Sluice in-memory integration tests.

---

## File Structure

**Create**

- `src/watershed/sequence_kernel.gleam` — pure optimistic sequence kernel and lifecycle.
- `test/watershed/sequence_kernel_test.gleam` — mutation, lifecycle, and convergence tests.
- `test/watershed/sequence_channel_test.gleam` — channel summary, attach, handle, and runtime-core tests.
- `test/watershed/fuzz/sequence_model.gleam` — shared fuzz-harness adapter.
- `test/watershed/sequence_fuzz_test.gleam` — sequence property and planted-bug tests.

**Modify**

- `gleam.toml` — local lattice dependency paths.
- `manifest.toml` — regenerated dependency lock data.
- `src/watershed/channel.gleam` — closed channel sums and dispatch.
- `src/watershed/wire.gleam` — sequence channel type tag.
- `src/watershed/wire/ops.gleam` — sequence op codecs.
- `src/watershed/runtime_core.gleam` — sequence mutations, reads, errors, and event routing.
- `src/watershed/runtime.gleam` — Erlang actor messages and result-returning edits.
- `src/watershed/runtime_js.gleam` — JavaScript runtime operations.
- `src/watershed/schema.gleam` — `SequenceChannel` phantom kind.
- `src/watershed.gleam` — Erlang `SharedSequence` public facade.
- `src/watershed_js.gleam` — JavaScript `SharedSequence` public facade.
- `test/watershed/wire_test.gleam` — sequence wire round trips and malformed input.
- `test/watershed/schema_test.gleam` — typed sequence field.
- `test/watershed/sluice/driver_test.gleam` — Erlang end-to-end convergence.
- `test/watershed/sluice/driver_js_test.gleam` — JavaScript end-to-end convergence.
- `README.md` — supported DDS and API example.

## Task 1: Link the Local Sequence and Text Packages

**Files:**

- Modify: `gleam.toml:19-25`
- Regenerate: `manifest.toml`

- [ ] **Step 1: Replace only `lattice_core` and add the new local packages**

Change the lattice section in `gleam.toml` to:

```toml
lattice_core = { path = "../lattice/packages/lattice_core" }
lattice_counters = ">= 1.1.0 and < 2.0.0"
lattice_maps = ">= 1.1.0 and < 2.0.0"
lattice_registers = ">= 1.1.0 and < 2.0.0"
lattice_sets = ">= 1.1.0 and < 2.0.0"
lattice_sequence = { path = "../lattice/packages/lattice_sequence" }
lattice_text_core = { path = "../lattice/packages/lattice_text_core" }
lattice_text = { path = "../lattice/packages/lattice_text" }
```

Do not add `lattice_fugue` or `lattice_text_fugue`.

- [ ] **Step 2: Regenerate the manifest**

Run:

```bash
gleam deps download
```

Expected: success, with `manifest.toml` entries using `source = "local"` for
`lattice_core`, `lattice_sequence`, `lattice_text_core`, and `lattice_text`.
The counters, maps, registers, and sets entries must remain `source = "hex"`.

- [ ] **Step 3: Verify both targets resolve the mixed local/Hex graph**

Run:

```bash
gleam build --target erlang
gleam build --target javascript
```

Expected: both builds succeed.

- [ ] **Step 4: Commit**

```bash
git add gleam.toml manifest.toml
git commit -m "build: link local lattice sequence packages"
```

## Task 2: Implement Basic Sequence Mutations

**Files:**

- Create: `src/watershed/sequence_kernel.gleam`
- Create: `test/watershed/sequence_kernel_test.gleam`

- [ ] **Step 1: Write failing mutation and error tests**

Create `test/watershed/sequence_kernel_test.gleam` with:

```gleam
import gleam/json
import lattice_core/replica_id
import startest/expect
import watershed/sequence_kernel

fn new_a() -> sequence_kernel.SequenceState {
  sequence_kernel.new(replica_id.new("a"))
}

pub fn insert_delete_move_replace_are_optimistic_test() {
  let assert Ok(#(state, _, _, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let assert Ok(#(state, _, _, _)) =
    sequence_kernel.insert(state, 1, json.string("b"))
  let assert Ok(#(state, _, _, _)) = sequence_kernel.move(state, 1, 0)
  let assert Ok(#(state, events, _, _)) =
    sequence_kernel.replace(state, 1, json.int(9))

  events
  |> expect.to_equal([
    sequence_kernel.SequenceChanged([json.string("b"), json.int(9)]),
  ])

  let assert Ok(#(state, _, _, _)) = sequence_kernel.delete(state, 0)
  sequence_kernel.values(state) |> expect.to_equal([json.int(9)])
  sequence_kernel.sequenced_values(state) |> expect.to_equal([])
  sequence_kernel.length(state) |> expect.to_equal(1)
}

pub fn invalid_indexes_return_edit_errors_test() {
  sequence_kernel.insert(new_a(), 1, json.null())
  |> expect.to_equal(Error(sequence_kernel.InsertOutOfBounds(1, 0)))

  sequence_kernel.delete(new_a(), 0)
  |> expect.to_equal(Error(sequence_kernel.DeleteOutOfBounds(0, 0)))

  sequence_kernel.move(new_a(), 0, 0)
  |> expect.to_equal(Error(sequence_kernel.MoveFromOutOfBounds(0, 0)))

  sequence_kernel.replace(new_a(), 0, json.null())
  |> expect.to_equal(Error(sequence_kernel.ReplaceOutOfBounds(0, 0)))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test sequence_kernel
```

Expected: compilation fails because `watershed/sequence_kernel` does not exist.

- [ ] **Step 3: Add the kernel types, reads, and mutations**

Create `src/watershed/sequence_kernel.gleam` with these public types:

```gleam
import gleam/int
import gleam/json.{type Json}
import gleam/list
import lattice_core/replica_id.{type ReplicaId}
import lattice_sequence/sequence.{type Sequence}

pub type SequenceState {
  SequenceState(
    replica_id: ReplicaId,
    sequenced: Sequence(Json),
    optimistic: Sequence(Json),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: SequenceOp, message_id: Int)
}

pub type SequenceOp {
  Insert(index: Int, value: Json, delta: Sequence(Json))
  Delete(index: Int, delta: Sequence(Json))
  Move(from_index: Int, to_index: Int, delta: Sequence(Json))
  Replace(index: Int, value: Json, delta: Sequence(Json))
}

pub type SequenceEvent {
  SequenceChanged(values: List(Json))
}

pub type EditError {
  InsertOutOfBounds(index: Int, length: Int)
  DeleteOutOfBounds(index: Int, length: Int)
  MoveFromOutOfBounds(index: Int, length: Int)
  MoveToOutOfBounds(index: Int, length_after_removal: Int)
  ReplaceOutOfBounds(index: Int, length: Int)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
}
```

Add constructors and reads:

```gleam
pub fn new(replica_id: ReplicaId) -> SequenceState {
  let empty = sequence.new(replica_id)
  SequenceState(
    replica_id: replica_id,
    sequenced: empty,
    optimistic: empty,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn values(state: SequenceState) -> List(Json) {
  sequence.values(state.optimistic)
}

pub fn sequenced_values(state: SequenceState) -> List(Json) {
  sequence.values(state.sequenced)
}

pub fn length(state: SequenceState) -> Int {
  sequence.length(state.optimistic)
}
```

Implement each mutation with lattice's fallible API. Use this common finisher:

```gleam
fn finish_local(
  state: SequenceState,
  optimistic: Sequence(Json),
  op: SequenceOp,
) -> #(SequenceState, List(SequenceEvent), SequenceOp, Int) {
  let before = values(state)
  let message_id = state.next_pending_message_id
  let state =
    SequenceState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, changed_event(before, values(state)), op, message_id)
}

fn changed_event(before: List(Json), after: List(Json)) -> List(SequenceEvent) {
  case before == after {
    True -> []
    False -> [SequenceChanged(after)]
  }
}
```

Map lattice errors explicitly:

```gleam
pub fn insert(
  state: SequenceState,
  index: Int,
  value: Json,
) -> Result(
  #(SequenceState, List(SequenceEvent), SequenceOp, Int),
  EditError,
) {
  case sequence.try_insert_with_delta(state.optimistic, index, value) {
    Ok(#(optimistic, delta)) ->
      Ok(finish_local(state, optimistic, Insert(index, value, delta)))
    Error(sequence.IndexOutOfBounds(index, length)) ->
      Error(InsertOutOfBounds(index, length))
  }
}

pub fn delete(
  state: SequenceState,
  index: Int,
) -> Result(
  #(SequenceState, List(SequenceEvent), SequenceOp, Int),
  EditError,
) {
  case sequence.try_delete_with_delta(state.optimistic, index) {
    Ok(#(optimistic, delta)) ->
      Ok(finish_local(state, optimistic, Delete(index, delta)))
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(DeleteOutOfBounds(index, length))
  }
}

pub fn move(
  state: SequenceState,
  from_index: Int,
  to_index: Int,
) -> Result(
  #(SequenceState, List(SequenceEvent), SequenceOp, Int),
  EditError,
) {
  case sequence.try_move_with_delta(state.optimistic, from_index, to_index) {
    Ok(#(optimistic, delta)) ->
      Ok(finish_local(
        state,
        optimistic,
        Move(from_index, to_index, delta),
      ))
    Error(sequence.MoveFromIndexOutOfBounds(index, length)) ->
      Error(MoveFromOutOfBounds(index, length))
    Error(sequence.MoveToIndexOutOfBounds(index, length_after_removal)) ->
      Error(MoveToOutOfBounds(index, length_after_removal))
  }
}

pub fn replace(
  state: SequenceState,
  index: Int,
  value: Json,
) -> Result(
  #(SequenceState, List(SequenceEvent), SequenceOp, Int),
  EditError,
) {
  case sequence.try_delete_with_delta(state.optimistic, index) {
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(ReplaceOutOfBounds(index, length))
    Ok(#(after_delete, delete_delta)) ->
      case sequence.try_insert_with_delta(after_delete, index, value) {
        Error(sequence.IndexOutOfBounds(_, length)) ->
          Error(ReplaceOutOfBounds(index, length))
        Ok(#(optimistic, insert_delta)) -> {
          let delta = sequence.merge(delete_delta, insert_delta)
          Ok(finish_local(state, optimistic, Replace(index, value, delta)))
        }
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
    DeleteOutOfBounds(index, length) ->
      "delete index " <> int.to_string(index) <> " invalid for length "
      <> int.to_string(length)
    MoveFromOutOfBounds(index, length) ->
      "move source index " <> int.to_string(index) <> " invalid for length "
      <> int.to_string(length)
    MoveToOutOfBounds(index, length_after_removal) ->
      "move destination index " <> int.to_string(index) <> " outside 0.."
      <> int.to_string(length_after_removal)
    ReplaceOutOfBounds(index, length) ->
      "replace index " <> int.to_string(index) <> " invalid for length "
      <> int.to_string(length)
  }
}
```

- [ ] **Step 4: Run the focused test**

Run:

```bash
gleam test sequence_kernel
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/watershed/sequence_kernel.gleam test/watershed/sequence_kernel_test.gleam
git commit -m "feat(sequence): add optimistic mutations"
```

## Task 3: Add Sequence Lifecycle and Convergence

**Files:**

- Modify: `src/watershed/sequence_kernel.gleam`
- Modify: `test/watershed/sequence_kernel_test.gleam`

- [ ] **Step 1: Write failing lifecycle tests**

Append tests that cover acknowledgement, idempotent remote merge, rollback,
summary rebranding, attach promotion, and concurrent convergence:

```gleam
fn ack(
  state: sequence_kernel.SequenceState,
  op: sequence_kernel.SequenceOp,
) -> sequence_kernel.SequenceState {
  let assert Ok(state) = sequence_kernel.ack_local(state, op)
  state
}

pub fn ack_is_view_transparent_and_remote_merge_is_idempotent_test() {
  let assert Ok(#(state_a, _, op, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let before_ack = sequence_kernel.values(state_a)
  let state_a = ack(state_a, op)
  sequence_kernel.values(state_a) |> expect.to_equal(before_ack)

  let state_b = sequence_kernel.new(replica_id.new("b"))
  let #(state_b, first_events) = sequence_kernel.apply_remote(state_b, op)
  let #(state_b, second_events) = sequence_kernel.apply_remote(state_b, op)
  sequence_kernel.values(state_b) |> expect.to_equal([json.string("a")])
  first_events
  |> expect.to_equal([sequence_kernel.SequenceChanged([json.string("a")])])
  second_events |> expect.to_equal([])
}

pub fn rollback_replays_remaining_pending_test() {
  let assert Ok(#(state, _, first, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let assert Ok(#(state, _, second, second_id)) =
    sequence_kernel.insert(state, 1, json.string("b"))
  let assert Ok(#(state, events)) =
    sequence_kernel.rollback(state, second, second_id)

  sequence_kernel.values(state) |> expect.to_equal([json.string("a")])
  events
  |> expect.to_equal([
    sequence_kernel.SequenceChanged([json.string("a")]),
  ])
  ack(state, first)
  |> sequence_kernel.sequenced_values
  |> expect.to_equal([json.string("a")])
}

pub fn summary_round_trips_and_rebrands_test() {
  let assert Ok(#(state, _, op, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let state = ack(state, op)
  let raw = json.to_string(sequence_kernel.summary(state))
  let assert Ok(loaded) =
    sequence_kernel.from_summary(raw, replica_id.new("c"))

  let assert Ok(#(loaded, _, op_c, _)) =
    sequence_kernel.insert(loaded, 1, json.string("c"))
  ack(loaded, op_c)
  |> sequence_kernel.sequenced_values
  |> expect.to_equal([json.string("a"), json.string("c")])
}

pub fn concurrent_inserts_and_replace_delete_move_converge_test() {
  let state_a = new_a()
  let state_b = sequence_kernel.new(replica_id.new("b"))
  let assert Ok(#(state_a, _, insert_a, _)) =
    sequence_kernel.insert(state_a, 0, json.string("a"))
  let assert Ok(#(state_b, _, insert_b, _)) =
    sequence_kernel.insert(state_b, 0, json.string("b"))

  let #(state_a, _) = sequence_kernel.apply_remote(ack(state_a, insert_a), insert_b)
  let #(state_b, _) = sequence_kernel.apply_remote(ack(state_b, insert_b), insert_a)
  sequence_kernel.values(state_a) |> expect.to_equal(sequence_kernel.values(state_b))

  let assert Ok(#(state_a, _, replace_a, _)) =
    sequence_kernel.replace(state_a, 0, json.string("A"))
  let assert Ok(#(state_b, _, move_b, _)) =
    sequence_kernel.move(state_b, 0, 1)
  let #(state_a, _) = sequence_kernel.apply_remote(ack(state_a, replace_a), move_b)
  let #(state_b, _) = sequence_kernel.apply_remote(ack(state_b, move_b), replace_a)
  sequence_kernel.values(state_a) |> expect.to_equal(sequence_kernel.values(state_b))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test sequence_kernel
```

Expected: compilation fails on missing lifecycle functions.

- [ ] **Step 3: Implement lifecycle operations**

Add:

```gleam
import gleam/option.{type Option, None, Some}

pub fn apply_remote(
  state: SequenceState,
  op: SequenceOp,
) -> #(SequenceState, List(SequenceEvent)) {
  let before = values(state)
  let sequenced = sequence.merge(state.sequenced, op_delta(op))
  let optimistic = replay_pending(sequenced, state.pending)
  let state =
    SequenceState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, changed_event(before, values(state)))
}

pub fn ack_local(
  state: SequenceState,
  op: SequenceOp,
) -> Result(SequenceState, KernelError) {
  do_ack(state, op, None)
}

pub fn ack_local_with_message_id(
  state: SequenceState,
  op: SequenceOp,
  message_id: Int,
) -> Result(SequenceState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: SequenceState,
  op: SequenceOp,
  expected_message_id: Option(Int),
) -> Result(SequenceState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOp(pending_op, pending_message_id), ..rest] -> {
      let id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_op == op && id_matches {
        True ->
          Ok(SequenceState(
            ..state,
            sequenced: sequence.merge(state.sequenced, op_delta(op)),
            pending: rest,
          ))
        False ->
          Error(UnexpectedAck(
            "expected pending message "
            <> int.to_string(pending_message_id),
          ))
      }
    }
  }
}

pub fn rollback(
  state: SequenceState,
  op: SequenceOp,
  message_id: Int,
) -> Result(#(SequenceState, List(SequenceEvent)), KernelError) {
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
          let before = values(state)
          let optimistic = replay_pending(state.sequenced, rest)
          let state =
            SequenceState(..state, optimistic: optimistic, pending: rest)
          Ok(#(state, changed_event(before, values(state))))
        }
      }
  }
}

pub fn apply_stashed_op(
  state: SequenceState,
  op: SequenceOp,
) -> #(SequenceState, List(SequenceEvent), SequenceOp, Int) {
  let optimistic = sequence.merge(state.optimistic, op_delta(op))
  finish_local(state, optimistic, op)
}

pub fn promote_attach(state: SequenceState) -> SequenceState {
  SequenceState(..state, sequenced: state.optimistic, pending: [])
}
```

Add summary and invariant helpers:

```gleam
pub fn summary(state: SequenceState) -> Json {
  sequence.to_json(state.sequenced, fn(value) { value })
}

pub fn from_summary(
  summary_json: String,
  replica_id: ReplicaId,
) -> Result(SequenceState, json.DecodeError) {
  case sequence.from_json(summary_json, wire.json_value_decoder()) {
    Ok(parsed) -> Ok(from_sequenced(parsed, replica_id))
    Error(error) -> Error(error)
  }
}

pub fn from_sequenced(
  sequenced: Sequence(Json),
  replica_id: ReplicaId,
) -> SequenceState {
  let rebranded = sequence.merge(sequence.new(replica_id), sequenced)
  SequenceState(
    replica_id: replica_id,
    sequenced: rebranded,
    optimistic: rebranded,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn check_cache_coherence(state: SequenceState) -> Result(Nil, String) {
  case replay_pending(state.sequenced, state.pending) == state.optimistic {
    True -> Ok(Nil)
    False -> Error("optimistic cache diverged from sequenced + pending")
  }
}

fn op_delta(op: SequenceOp) -> Sequence(Json) {
  case op {
    Insert(_, _, delta)
    | Delete(_, delta)
    | Move(_, _, delta)
    | Replace(_, _, delta) -> delta
  }
}

fn replay_pending(
  sequenced: Sequence(Json),
  pending: List(PendingOp),
) -> Sequence(Json) {
  list.fold(pending, sequenced, fn(acc, pending) {
    sequence.merge(acc, op_delta(pending.op))
  })
}
```

Import `watershed/wire`; `wire.json_value_decoder()` is the repository's
canonical decoder for opaque `gleam/json.Json` values and `wire.gleam` does not
import the sequence kernel.

Add a recursive `pop_last` matching the OR-set kernel's implementation.

- [ ] **Step 4: Run the focused tests**

Run:

```bash
gleam test sequence_kernel
```

Expected: all sequence kernel tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/watershed/sequence_kernel.gleam test/watershed/sequence_kernel_test.gleam
git commit -m "feat(sequence): add CRDT lifecycle"
```

## Task 4: Integrate Sequence into the Channel Sum

**Files:**

- Modify: `src/watershed/channel.gleam:22-247`
- Modify: `src/watershed/channel.gleam:279-560`
- Modify: `src/watershed/channel.gleam:709-1252`
- Modify: `src/watershed/channel.gleam:1255-1650`
- Create: `test/watershed/sequence_channel_test.gleam`

- [ ] **Step 1: Write failing channel summary and handle tests**

Create `test/watershed/sequence_channel_test.gleam`:

```gleam
import gleam/json
import lattice_core/replica_id
import startest/expect
import watershed/channel
import watershed/handle
import watershed/sequence_kernel

pub fn sequence_summary_round_trips_test() {
  let assert Ok(#(state, _, op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("a")),
      0,
      json.string("a"),
    )
  let assert Ok(state) = sequence_kernel.ack_local(state, op)
  let summary = channel.SequenceSummary(state.sequenced)
  let encoded = channel.encode_snapshot(summary)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.SequenceChannel),
    )

  channel.same_snapshot(summary, decoded) |> expect.to_be_true()
}

pub fn sequence_discovers_nested_handles_test() {
  let assert Ok(#(state, _, _, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("a")),
      0,
      handle.encode_handle("child"),
    )
  channel.handle_addresses(channel.SequenceState(state))
  |> expect.to_equal(["child"])
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test sequence_channel
```

Expected: compilation fails on missing Sequence channel variants.

- [ ] **Step 3: Add imports and closed-sum variants**

In `channel.gleam`, import:

```gleam
import lattice_sequence/sequence.{type Sequence}
import watershed/sequence_kernel
```

Add:

```gleam
// ChannelType
SequenceChannel

// ChannelInit
InitSequence

// ChannelState
SequenceState(sequence_kernel.SequenceState)

// ChannelOp
SequenceOp(sequence_kernel.SequenceOp)

// ChannelEvent
SequenceEvent(sequence_kernel.SequenceEvent)

// Snapshot
SequenceSummary(state: Sequence(Json))

// LocalOpMeta
SequenceMeta(message_id: Int)
```

Map `SequenceChannel` to a new `wire.channel_type_sequence` constant in
`type_to_string` and `type_from_string`, and map `InitSequence` in `init_type`.

- [ ] **Step 4: Extend construction, summary, attach, and apply dispatch**

Add these cases:

```gleam
// new
InitSequence ->
  SequenceState(sequence_kernel.new(replica_id.new(replica)))

// from_snapshot
SequenceSummary(state) ->
  SequenceState(sequence_kernel.from_sequenced(state, replica_id.new(replica)))

// snapshot
SequenceState(kernel) -> SequenceSummary(kernel.sequenced)

// attach_snapshot
SequenceState(kernel) -> SequenceSummary(kernel.optimistic)

// attach_state
SequenceState(kernel) ->
  SequenceState(sequence_kernel.promote_attach(kernel))

// apply_remote
SequenceState(kernel), SequenceOp(op) -> {
  let #(kernel, events) = sequence_kernel.apply_remote(kernel, op)
  Ok(#(SequenceState(kernel), list.map(events, SequenceEvent), []))
}
```

Add the corresponding `SequenceState` or `SequenceSummary` cases to these
existing exhaustive dispatch functions: `channel_type`, `snapshot_type`,
`new`, `from_snapshot`, `snapshot`, `attach_snapshot`, `attach_state`,
`apply_remote`, `same_shape`, `same_snapshot`, `handle_addresses`,
`encode_snapshot`, and `snapshot_decoder`.

- [ ] **Step 5: Extend acknowledgement and shape checks**

Add a `SequenceState`/`SequenceOp` branch to `ack_local`:

```gleam
SequenceState(kernel), SequenceOp(op) ->
  case local {
    SequenceMeta(message_id) ->
      case sequence_kernel.ack_local_with_message_id(kernel, op, message_id) {
        Ok(kernel) -> Ok(#(SequenceState(kernel), [], None))
        Error(sequence_kernel.UnexpectedAck(detail))
        | Error(sequence_kernel.UnexpectedRollback(detail)) ->
          Error(UnexpectedAck(detail))
      }
    _ -> Error(UnexpectedAck(
      "sequence ack is missing its local message id",
    ))
  }
```

Add `SequenceMeta(_)` to every non-sequence metadata rejection branch so the
sum remains exhaustive.

Add:

```gleam
fn same_sequence_shape(
  ours: sequence_kernel.SequenceOp,
  echoed: sequence_kernel.SequenceOp,
) -> Bool {
  case ours, echoed {
    sequence_kernel.Insert(i, value, _),
      sequence_kernel.Insert(i2, value2, _)
    -> i == i2 && same_json_value(value, value2)
    sequence_kernel.Delete(i, _), sequence_kernel.Delete(i2, _) -> i == i2
    sequence_kernel.Move(from, to, _),
      sequence_kernel.Move(from2, to2, _)
    -> from == from2 && to == to2
    sequence_kernel.Replace(i, value, _),
      sequence_kernel.Replace(i2, value2, _)
    -> i == i2 && same_json_value(value, value2)
    _, _ -> False
  }
}
```

Route `SequenceOp` through `same_shape`. Compare sequence summaries through
their canonical encoded form:

```gleam
SequenceSummary(ours), SequenceSummary(echoed) ->
  json.to_string(sequence.to_json(ours, fn(value) { value }))
  == json.to_string(sequence.to_json(echoed, fn(value) { value }))
```

- [ ] **Step 6: Add handle discovery and summary codecs**

Add to `handle_addresses`:

```gleam
SequenceState(kernel) ->
  sequence_kernel.values(kernel)
  |> list.flat_map(handle.collect_handle_addresses)
  |> list.unique
```

Add to `encode_snapshot`:

```gleam
SequenceSummary(state) ->
  sequence.to_json(state, fn(value) { value })
```

Add to `snapshot_decoder`:

```gleam
SequenceChannel -> sequence_summary_decoder()
```

Implement:

```gleam
fn sequence_summary_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  let encoded = json.to_string(value)
  case sequence.from_json(encoded, wire.json_value_decoder()) {
    Ok(state) -> decode.success(SequenceSummary(state))
    Error(_) -> decode.failure(MapSnapshot([]), "SequenceSummary")
  }
}
```

- [ ] **Step 7: Run the focused tests**

Run:

```bash
gleam test sequence_channel
```

Expected: 2 tests pass.

- [ ] **Step 8: Commit**

```bash
git add src/watershed/channel.gleam test/watershed/sequence_channel_test.gleam
git commit -m "feat(sequence): register channel lifecycle"
```

## Task 5: Add Sequence Wire Codecs

**Files:**

- Modify: `src/watershed/wire.gleam:33-63`
- Modify: `src/watershed/wire/ops.gleam:21-180`
- Modify: `src/watershed/wire/ops.gleam:285-360`
- Modify: `src/watershed/wire/ops.gleam:680-710`
- Modify: `src/watershed/wire/ops.gleam:810-990`
- Modify: `test/watershed/wire_test.gleam`

- [ ] **Step 1: Write failing op round-trip and malformed-delta tests**

Append to `test/watershed/wire_test.gleam`:

```gleam
fn sample_sequence_op() -> sequence_kernel.SequenceOp {
  let assert Ok(#(_, _, op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("client-a")),
      0,
      json.object([#("name", json.string("Ada"))]),
    )
  op
}

pub fn sequence_channel_op_round_trips_test() {
  let op = sample_sequence_op()
  let encoded =
    ops.encode_channel_envelope("items", channel.SequenceOp(op))
    |> json.to_string
  let dynamic = parse(encoded, decode.dynamic)
  let assert Ok(ops.ChannelOp("items", payload)) =
    ops.decode_op_contents(dynamic)

  decode.run(payload, ops.channel_op_decoder(channel.SequenceChannel))
  |> expect.to_equal(Ok(channel.SequenceOp(op)))
}

pub fn sequence_decoder_rejects_malformed_delta_test() {
  let dynamic =
    parse(
      "{\"type\":\"sequenceDelete\",\"index\":0,\"delta\":\"not-json\"}",
      decode.dynamic,
    )
  decode.run(dynamic, ops.sequence_op_decoder()) |> expect.to_be_error()
}
```

Add imports for `watershed/sequence_kernel`.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test wire
```

Expected: compilation fails on missing sequence wire functions.

- [ ] **Step 3: Add channel tag and dispatch**

In `wire.gleam`:

```gleam
pub const channel_type_sequence = "sequence"
```

In `wire/ops.gleam`, import:

```gleam
import lattice_sequence/sequence
import watershed/sequence_kernel.{type SequenceOp}
```

Add:

```gleam
channel.SequenceOp(op) -> encode_sequence_op(op)
```

and:

```gleam
channel.SequenceChannel ->
  sequence_op_decoder() |> decode.map(channel.SequenceOp)
```

- [ ] **Step 4: Implement encoder and decoder**

Add:

```gleam
pub fn encode_sequence_op(op: SequenceOp) -> Json {
  case op {
    sequence_kernel.Insert(index, value, delta) ->
      json.object([
        #("type", json.string("sequenceInsert")),
        #("index", json.int(index)),
        #("value", value),
        #("delta", sequence_delta_json(delta)),
      ])
    sequence_kernel.Delete(index, delta) ->
      json.object([
        #("type", json.string("sequenceDelete")),
        #("index", json.int(index)),
        #("delta", sequence_delta_json(delta)),
      ])
    sequence_kernel.Move(from_index, to_index, delta) ->
      json.object([
        #("type", json.string("sequenceMove")),
        #("fromIndex", json.int(from_index)),
        #("toIndex", json.int(to_index)),
        #("delta", sequence_delta_json(delta)),
      ])
    sequence_kernel.Replace(index, value, delta) ->
      json.object([
        #("type", json.string("sequenceReplace")),
        #("index", json.int(index)),
        #("value", value),
        #("delta", sequence_delta_json(delta)),
      ])
  }
}

fn sequence_delta_json(delta: sequence.Sequence(Json)) -> Json {
  json.string(json.to_string(sequence.to_json(delta, fn(value) { value })))
}
```

Implement:

```gleam
pub fn sequence_op_decoder() -> Decoder(SequenceOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "sequenceInsert" -> {
      use index <- decode.field("index", decode.int)
      use value <- decode.field("value", wire.json_value_decoder())
      use delta <- decode.field("delta", sequence_delta_decoder())
      decode.success(sequence_kernel.Insert(index, value, delta))
    }
    "sequenceDelete" -> {
      use index <- decode.field("index", decode.int)
      use delta <- decode.field("delta", sequence_delta_decoder())
      decode.success(sequence_kernel.Delete(index, delta))
    }
    "sequenceMove" -> {
      use from_index <- decode.field("fromIndex", decode.int)
      use to_index <- decode.field("toIndex", decode.int)
      use delta <- decode.field("delta", sequence_delta_decoder())
      decode.success(sequence_kernel.Move(from_index, to_index, delta))
    }
    "sequenceReplace" -> {
      use index <- decode.field("index", decode.int)
      use value <- decode.field("value", wire.json_value_decoder())
      use delta <- decode.field("delta", sequence_delta_decoder())
      decode.success(sequence_kernel.Replace(index, value, delta))
    }
    _ ->
      decode.failure(
        sequence_kernel.Delete(0, default_sequence_delta()),
        "SequenceOp",
      )
  }
}

fn sequence_delta_decoder() -> Decoder(sequence.Sequence(Json)) {
  use encoded <- decode.then(decode.string)
  case sequence.from_json(encoded, wire.json_value_decoder()) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_sequence_delta(), "SequenceDelta")
  }
}

fn default_sequence_delta() -> sequence.Sequence(Json) {
  sequence.new(replica_id.new(""))
}
```

- [ ] **Step 5: Run wire tests**

Run:

```bash
gleam test wire
```

Expected: all wire tests pass, including the new sequence tests.

- [ ] **Step 6: Commit**

```bash
git add src/watershed/wire.gleam src/watershed/wire/ops.gleam test/watershed/wire_test.gleam
git commit -m "feat(sequence): add wire codecs"
```

## Task 6: Add Runtime-Core Mutations and Reads

**Files:**

- Modify: `src/watershed/runtime_core.gleam:24-103`
- Modify: `src/watershed/runtime_core.gleam:1840-2050`
- Modify: `src/watershed/runtime_core.gleam:2480-2550`
- Modify: `src/watershed/runtime_core.gleam:2835-2880`
- Modify: `src/watershed/runtime_core.gleam:3030-3090`
- Modify: `test/watershed/sequence_channel_test.gleam`

- [ ] **Step 1: Write failing detached, attached, read, and error tests**

Extend `sequence_channel_test.gleam` using the bootstrap helper from
`or_set_channel_test.gleam`. Add:

```gleam
pub fn detached_sequence_attaches_then_emits_ops_test() {
  let address = "sequence-1"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitSequence)

  let assert Ok(#(core, events, outbound)) =
    runtime_core.sequence_insert(core, address, 0, json.string("a"))
  outbound |> expect.to_equal([])
  events
  |> expect.to_equal([
    #(
      address,
      channel.SequenceEvent(
        sequence_kernel.SequenceChanged([json.string("a")]),
      ),
    ),
  ])

  let assert Ok(#(core, _, attach_outbound)) =
    runtime_core.set(core, "root", "items", handle.encode_handle(address))
  list.length(attach_outbound) |> expect.to_equal(2)

  let assert Ok(#(core, _, [op])) =
    runtime_core.sequence_replace(core, address, 0, json.string("A"))
  json.to_string(op.contents)
  |> string.contains("\"type\":\"sequenceReplace\"")
  |> expect.to_be_true()
  runtime_core.sequence_values(core, address)
  |> expect.to_equal([json.string("A")])
  runtime_core.sequence_length(core, address) |> expect.to_equal(1)
}

pub fn sequence_invalid_index_is_explicit_core_error_test() {
  let core =
    bootstrap()
    |> runtime_core.create_detached("sequence-1", channel.InitSequence)

  runtime_core.sequence_delete(core, "sequence-1", 0)
  |> expect.to_equal(Error(runtime_core.SequenceOpFailed(
    "sequence-1",
    "delete index 0 invalid for length 0",
  )))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
gleam test sequence_channel
```

Expected: compilation fails on missing runtime-core sequence functions.

- [ ] **Step 3: Add the core error and generic mutation helper**

Import `watershed/sequence_kernel` and add:

```gleam
SequenceOpFailed(address: String, detail: String)
```

Add:

```gleam
fn mutate_sequence(
  core: Core,
  address: String,
  mutate: fn(sequence_kernel.SequenceState) ->
    Result(
      #(
        sequence_kernel.SequenceState,
        List(sequence_kernel.SequenceEvent),
        sequence_kernel.SequenceOp,
        Int,
      ),
      sequence_kernel.EditError,
    ),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_sequence(core, address) {
    Error(error) -> Error(error)
    Ok(Detached(kernel)) ->
      case mutate(kernel) {
        Error(error) ->
          Error(SequenceOpFailed(
            address,
            sequence_kernel.edit_error_detail(error),
          ))
        Ok(#(kernel, events, _op, _message_id)) ->
          Ok(#(
            put_detached_channel(core, address, channel.SequenceState(kernel)),
            tag_sequence_events(address, events),
            [],
          ))
      }
    Ok(Attached(kernel)) ->
      case mutate(kernel) {
        Error(error) ->
          Error(SequenceOpFailed(
            address,
            sequence_kernel.edit_error_detail(error),
          ))
        Ok(#(kernel, events, op, message_id)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.SequenceState(kernel),
            tag_sequence_events(address, events),
            channel.SequenceOp(op),
            channel.SequenceMeta(message_id),
          ))
      }
  }
}
```

- [ ] **Step 4: Add public mutation and read functions**

```gleam
pub fn sequence_insert(
  core: Core,
  address: String,
  index: Int,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  mutate_sequence(core, address, sequence_kernel.insert(_, index, value))
}

pub fn sequence_delete(
  core: Core,
  address: String,
  index: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  mutate_sequence(core, address, sequence_kernel.delete(_, index))
}

pub fn sequence_move(
  core: Core,
  address: String,
  from_index: Int,
  to_index: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  mutate_sequence(
    core,
    address,
    sequence_kernel.move(_, from_index, to_index),
  )
}

pub fn sequence_replace(
  core: Core,
  address: String,
  index: Int,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  mutate_sequence(core, address, sequence_kernel.replace(_, index, value))
}

pub fn sequence_values(core: Core, address: String) -> List(Json) {
  case find_channel(core, address) {
    Some(channel.SequenceState(kernel)) -> sequence_kernel.values(kernel)
    _ -> []
  }
}

pub fn sequence_length(core: Core, address: String) -> Int {
  case find_channel(core, address) {
    Some(channel.SequenceState(kernel)) -> sequence_kernel.length(kernel)
    _ -> 0
  }
}
```

Add:

```gleam
fn locate_sequence(
  core: Core,
  address: String,
) -> Result(Located(sequence_kernel.SequenceState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.SequenceState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.SequenceState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.SequenceChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn tag_sequence_events(
  address: String,
  events: List(sequence_kernel.SequenceEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.SequenceEvent(event)) })
}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
gleam test sequence_channel
```

Expected: all sequence channel tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/watershed/runtime_core.gleam test/watershed/sequence_channel_test.gleam
git commit -m "feat(sequence): add runtime core operations"
```

## Task 7: Expose Erlang and JavaScript Public APIs

**Files:**

- Modify: `src/watershed/runtime.gleam`
- Modify: `src/watershed/runtime_js.gleam`
- Modify: `src/watershed/schema.gleam:99-143`
- Modify: `src/watershed.gleam`
- Modify: `src/watershed_js.gleam`
- Modify: `test/watershed/schema_test.gleam`
- Modify: `test/watershed/sluice/driver_test.gleam`
- Modify: `test/watershed/sluice/driver_js_test.gleam`

- [ ] **Step 1: Write failing schema and Erlang Sluice tests**

Append to `schema_test.gleam`:

```gleam
pub fn sequence_channel_field_test() {
  let items: schema.ChannelField(Player, schema.SequenceChannel) =
    schema.channel_field("items")
  schema.channel_field_key(items) |> expect.to_equal("items")
}
```

Append to `sluice/driver_test.gleam`:

```gleam
@target(erlang)
pub fn shared_sequence_converges_test() {
  let sluice = start("shared-sequence")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(sequence_a) = watershed.create_sequence(doc_a)
  let assert Ok(Nil) =
    watershed.sequence_insert(sequence_a, 0, json.string("base"))
  watershed.set(
    watershed.root(doc_a),
    "items",
    watershed.sequence_handle_of(sequence_a),
  )
  sluice.settle(sluice)

  let assert Some(sequence_handle) =
    watershed.get(watershed.root(doc_b), "items")
  let assert Ok(sequence_b) =
    watershed.resolve_sequence(doc_b, sequence_handle)

  let assert Ok(Nil) =
    watershed.sequence_insert(sequence_a, 1, json.string("a"))
  let assert Ok(Nil) =
    watershed.sequence_insert(sequence_b, 1, json.string("b"))
  sluice.settle(sluice)

  watershed.sequence_values(sequence_a)
  |> expect.to_equal(watershed.sequence_values(sequence_b))

  let assert Ok(Nil) = watershed.sequence_move(sequence_a, 0, 2)
  let assert Ok(Nil) =
    watershed.sequence_replace(sequence_b, 0, json.string("B"))
  sluice.settle(sluice)
  watershed.sequence_values(sequence_a)
  |> expect.to_equal(watershed.sequence_values(sequence_b))

  watershed.sequence_delete(sequence_a, 99) |> expect.to_be_error()
}
```

- [ ] **Step 2: Write the JavaScript Sluice mirror**

Append to `sluice/driver_js_test.gleam`:

```gleam
@target(javascript)
pub fn shared_sequence_converges_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "shared-sequence-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(sequence_a) = watershed_js.create_sequence(doc_a)
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_a, 0, json.string("base"))
  watershed_js.set(
    watershed_js.root(doc_a),
    "items",
    watershed_js.sequence_handle_of(sequence_a),
  )
  sluice_js.settle(sluice)

  let assert Some(sequence_handle) =
    watershed_js.get(watershed_js.root(doc_b), "items")
  let assert Ok(sequence_b) =
    watershed_js.resolve_sequence(doc_b, sequence_handle)

  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_a, 1, json.string("a"))
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_b, 1, json.string("b"))
  sluice_js.settle(sluice)

  watershed_js.sequence_values(sequence_a)
  |> expect.to_equal(watershed_js.sequence_values(sequence_b))
  watershed_js.sequence_delete(sequence_a, 99) |> expect.to_be_error()
}
```

- [ ] **Step 3: Run the facade tests and verify they fail**

Run:

```bash
gleam test schema
gleam test sluice/driver
gleam test --target javascript sluice/driver_js
```

Expected: compilation fails on missing Sequence public APIs and schema kind.

- [ ] **Step 4: Add runtime messages and result-returning edit handling**

In `runtime.gleam`, add `InitSequence` to the channel imports and add messages:

```gleam
InsertSequenceItem(
  address: String,
  index: Int,
  value: Json,
  reply: Subject(Result(Nil, String)),
)
DeleteSequenceItem(
  address: String,
  index: Int,
  reply: Subject(Result(Nil, String)),
)
MoveSequenceItem(
  address: String,
  from_index: Int,
  to_index: Int,
  reply: Subject(Result(Nil, String)),
)
ReplaceSequenceItem(
  address: String,
  index: Int,
  value: Json,
  reply: Subject(Result(Nil, String)),
)
CreateSequence(reply: Subject(Result(String, String)))
GetSequenceValues(address: String, reply: Subject(List(Json)))
GetSequenceLength(address: String, reply: Subject(Int))
```

Handle create and reads through existing helpers. Handle edits through a new
`edit_sequence_with_result` helper that:

1. calls the supplied runtime-core function in `Ready` or `Reconnecting`;
2. sends `Error(sequence_kernel.edit_error_detail)` for
   `SequenceOpFailed`;
3. sends `Error(string.inspect(core_error))` for other explicit core errors;
4. sends outbound ops and fans out events on success;
5. returns `Error("<verb> requires a ready document connection")` before ready.

Do not route sequence edits through `edit`, because `edit` panics on
caller-provided invalid indexes.

Use this helper shape in `runtime.gleam`:

```gleam
fn edit_sequence_with_result(
  state: State,
  reply: Subject(Result(Nil, String)),
  operate: fn(runtime_core.Core) -> Result(
    #(
      runtime_core.Core,
      List(#(String, ChannelEvent)),
      List(wire.OutboundOp),
    ),
    runtime_core.CoreError,
  ),
  verb: String,
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) ->
      case operate(core) {
        Ok(#(core, events, outbound)) -> {
          process.send(reply, Ok(Nil))
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
        Error(runtime_core.SequenceOpFailed(_, detail)) -> {
          process.send(reply, Error(detail))
          actor.continue(state)
        }
        Error(error) -> {
          process.send(reply, Error(verb <> " failed: " <> string.inspect(error)))
          actor.continue(state)
        }
      }
    Reconnecting(core) ->
      case operate(core) {
        Ok(#(core, events, _outbound)) -> {
          process.send(reply, Ok(Nil))
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
        Error(runtime_core.SequenceOpFailed(_, detail)) -> {
          process.send(reply, Error(detail))
          actor.continue(state)
        }
        Error(error) -> {
          process.send(reply, Error(verb <> " failed: " <> string.inspect(error)))
          actor.continue(state)
        }
      }
    _ -> {
      process.send(
        reply,
        Error(verb <> " before the document connection is ready"),
      )
      actor.continue(state)
    }
  }
}
```

In `runtime_js.gleam`, add:

```gleam
pub fn sequence_insert(
  runtime: Runtime,
  address: String,
  index: Int,
  value: Json,
) -> Result(Nil, String)

pub fn sequence_delete(
  runtime: Runtime,
  address: String,
  index: Int,
) -> Result(Nil, String)

pub fn sequence_move(
  runtime: Runtime,
  address: String,
  from_index: Int,
  to_index: Int,
) -> Result(Nil, String)

pub fn sequence_replace(
  runtime: Runtime,
  address: String,
  index: Int,
  value: Json,
) -> Result(Nil, String)

pub fn sequence_values(runtime: Runtime, address: String) -> List(Json)
pub fn sequence_length(runtime: Runtime, address: String) -> Int
pub fn create_sequence(runtime: Runtime) -> Result(String, String)
```

Implement a JavaScript `edit_sequence_with_result` with the same error mapping
and state/outbound/event behavior as `edit`, but return `Result(Nil, String)`:

```gleam
fn edit_sequence_with_result(
  cell: Cell(State),
  operate: fn(runtime_core.Core) -> Result(
    #(
      runtime_core.Core,
      List(#(String, ChannelEvent)),
      List(wire.OutboundOp),
    ),
    runtime_core.CoreError,
  ),
) -> Result(Nil, String) {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case operate(core) {
        Ok(#(core, events, outbound)) -> {
          cell_set(cell, State(..state, phase: Ready(core, resubmit_at)))
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            Some(_) -> Nil
          }
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
        Error(runtime_core.SequenceOpFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    Reconnecting(core) ->
      case operate(core) {
        Ok(#(core, events, _outbound)) -> {
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
        Error(runtime_core.SequenceOpFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    _ -> Error("sequence edit before the document connection is ready")
  }
}
```

The public JavaScript mutation functions destructure `Runtime(cell)` and pass
`cell` plus the corresponding `runtime_core.sequence_*` callback to this
helper.

- [ ] **Step 5: Add the schema kind and top-level opaque types**

In `schema.gleam`:

```gleam
/// A collaborative ordered sequence of arbitrary JSON values.
pub type SequenceChannel
```

In both `watershed.gleam` and `watershed_js.gleam`, import
`watershed/sequence_kernel` and add the target-specific definitions:

```gleam
// watershed.gleam
pub opaque type SharedSequence {
  SharedSequence(runtime: Subject(runtime.Msg), address: String)
}

// watershed_js.gleam
pub opaque type SharedSequence {
  SharedSequence(runtime: runtime_js.Runtime, address: String)
}
```

- [ ] **Step 6: Add public create, handle, resolve, edit, read, and subscribe APIs**

Expose the same surface on both targets:

```gleam
pub fn create_sequence(document: Document) -> Result(SharedSequence, String)
pub fn sequence_handle_of(sequence: SharedSequence) -> Json
pub fn resolve_sequence(
  document: Document,
  value: Json,
) -> Result(SharedSequence, String)
pub fn sequence_insert(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String)
pub fn sequence_delete(
  sequence: SharedSequence,
  index: Int,
) -> Result(Nil, String)
pub fn sequence_move(
  sequence: SharedSequence,
  from_index: Int,
  to_index: Int,
) -> Result(Nil, String)
pub fn sequence_replace(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String)
pub fn sequence_values(sequence: SharedSequence) -> List(Json)
pub fn sequence_length(sequence: SharedSequence) -> Int
```

Erlang subscriptions return:

```gleam
pub fn subscribe_sequence(
  sequence: SharedSequence,
) -> Subject(sequence_kernel.SequenceEvent)
```

JavaScript subscriptions accept:

```gleam
pub fn subscribe_sequence(
  sequence: SharedSequence,
  handler: fn(sequence_kernel.SequenceEvent) -> Nil,
) -> Nil
```

Narrow `channel.SequenceEvent(inner)` in both implementations.

- [ ] **Step 7: Add typed-field helpers**

Add to both public facades:

```gleam
pub fn set_sequence_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
  sequence: SharedSequence,
) -> Nil

pub fn resolve_sequence_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
) -> Result(Option(SharedSequence), String)
```

Add Erlang:

```gleam
pub fn ensure_sequence(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
) -> Result(SharedSequence, String)
```

Add the JavaScript callback form:

```gleam
pub fn ensure_sequence(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
  done: fn(Result(SharedSequence, String)) -> Nil,
) -> Nil
```

Use the existing generic `put_channel_field`, `get_channel_field`, and
`ensure_channel` helpers.

- [ ] **Step 8: Run schema and end-to-end tests**

Run:

```bash
gleam test schema
gleam test sluice/driver
gleam test --target javascript sluice/driver_js
```

Expected: all targeted tests pass.

- [ ] **Step 9: Commit**

```bash
git add src/watershed/runtime.gleam src/watershed/runtime_js.gleam src/watershed/schema.gleam src/watershed.gleam src/watershed_js.gleam test/watershed/schema_test.gleam test/watershed/sluice/driver_test.gleam test/watershed/sluice/driver_js_test.gleam
git commit -m "feat(sequence): expose public facades"
```

## Task 8: Add Model-Based Fuzz Coverage

**Files:**

- Create: `test/watershed/fuzz/sequence_model.gleam`
- Create: `test/watershed/sequence_fuzz_test.gleam`

- [ ] **Step 1: Write the failing fuzz test**

Create `test/watershed/sequence_fuzz_test.gleam`:

```gleam
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{ClientOp, KernelModel, Synchronize}
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
  let assert Ok(#(_, _, op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("a")),
      0,
      json.string("x"),
    )
  let sequence_kernel.Insert(index, value, delta) = op
  let commands = [
    sequence_model.InsertCmd(0, "x", None),
    sequence_model.InsertCmd(index, json.to_string(value), Some(delta)),
  ]
  list.each(commands, fn(command) {
    let assert Ok(decoded) =
      json.parse(json.to_string(model.op_to_json(command)), model.op_decoder)
    decoded |> expect.to_equal(command)
  })
}

pub fn shared_replica_id_is_caught_test() {
  let model = sequence_model.model()
  let buggy =
    KernelModel(..model, init: fn(_id) {
      sequence_kernel.new(replica_id.new("client-0"))
    })
  let script = [
    ClientOp(1, sequence_model.InsertCmd(0, "a", None)),
    ClientOp(2, sequence_model.InsertCmd(0, "b", None)),
    Synchronize,
  ]
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected duplicate sequence replica ids to fail"
  }
}
```

- [ ] **Step 2: Run the focused fuzz test and verify it fails**

Run:

```bash
gleam test sequence_fuzz
```

Expected: compilation fails because `sequence_model` does not exist.

- [ ] **Step 3: Define commands and JSON codecs**

Create `test/watershed/fuzz/sequence_model.gleam` with:

```gleam
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id
import lattice_sequence/sequence.{type Sequence}
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, Capabilities, KernelModel,
}
import watershed/sequence_kernel

pub type SequenceCommand {
  InsertCmd(index_seed: Int, value: String, delta: Option(Sequence(json.Json)))
  DeleteCmd(index_seed: Int, delta: Option(Sequence(json.Json)))
  MoveCmd(
    from_seed: Int,
    to_seed: Int,
    delta: Option(Sequence(json.Json)),
  )
  ReplaceCmd(index_seed: Int, value: String, delta: Option(Sequence(json.Json)))
}
```

Encode `delta` as `null` or a JSON string containing
`sequence.to_json(delta, fn(value) { value })`. Decode it with
`sequence.from_json(encoded, wire.json_value_decoder())`. Encode every command
with a stable `"tag"` plus its seeds/value/delta.

Generate commands from four small non-negative integers:

```gleam
fn op_generator() -> qcheck.Generator(SequenceCommand) {
  qcheck.tuple4(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(parts) {
    let value = "v" <> int.to_string(parts.2 % 5)
    case parts.0 % 4 {
      0 -> InsertCmd(parts.1, value, None)
      1 -> DeleteCmd(parts.1, None)
      2 -> MoveCmd(parts.1, parts.2, None)
      _ -> ReplaceCmd(parts.1, value, None)
    }
  })
}
```

- [ ] **Step 4: Normalize generated commands and route kernel deltas**

Implement `submit` so every generated command becomes valid for the current
state:

```gleam
fn submit(
  state: sequence_kernel.SequenceState,
  command: SequenceCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(sequence_kernel.SequenceState, Option(SequenceCommand)) {
  let length = sequence_kernel.length(state)
  case command {
    InsertCmd(seed, value, _) -> {
      let index = seed % { length + 1 }
      let assert Ok(#(state, _, op, _)) =
        sequence_kernel.insert(state, index, json.string(value))
      let sequence_kernel.Insert(_, actual, delta) = op
      #(state, Some(InsertCmd(index, json.to_string(actual), Some(delta))))
    }
    DeleteCmd(seed, _) if length > 0 -> {
      let index = seed % length
      let assert Ok(#(state, _, op, _)) =
        sequence_kernel.delete(state, index)
      let sequence_kernel.Delete(_, delta) = op
      #(state, Some(DeleteCmd(index, Some(delta))))
    }
    MoveCmd(from_seed, to_seed, _) if length > 0 -> {
      let from_index = from_seed % length
      let to_index = to_seed % length
      let assert Ok(#(state, _, op, _)) =
        sequence_kernel.move(state, from_index, to_index)
      let sequence_kernel.Move(_, _, delta) = op
      #(state, Some(MoveCmd(from_index, to_index, Some(delta))))
    }
    ReplaceCmd(seed, value, _) if length > 0 -> {
      let index = seed % length
      let assert Ok(#(state, _, op, _)) =
        sequence_kernel.replace(state, index, json.string(value))
      let sequence_kernel.Replace(_, actual, delta) = op
      #(state, Some(ReplaceCmd(
        index,
        json.to_string(actual),
        Some(delta),
      )))
    }
    DeleteCmd(seed, _) | MoveCmd(seed, _, _) | ReplaceCmd(seed, _, _) ->
      submit(state, InsertCmd(seed, "seed", None), _meta)
  }
}
```

Convert routed commands back to `sequence_kernel.SequenceOp`; panic if a
routed command still has `delta: None`.

- [ ] **Step 5: Implement model lifecycle, summary loading, and checks**

Use:

```gleam
fn apply_remote(state, command, _meta) {
  let #(state, _) =
    sequence_kernel.apply_remote(state, to_kernel_op(command, "apply_remote"))
  Ok(state)
}

fn ack_local(state, command, _meta) {
  case sequence_kernel.ack_local(state, to_kernel_op(command, "ack_local")) {
    Ok(state) -> Ok(state)
    Error(sequence_kernel.UnexpectedAck(detail))
    | Error(sequence_kernel.UnexpectedRollback(detail)) -> Error(detail)
  }
}

fn rollback(state, command) {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(sequence_kernel.PendingOp(_, message_id)) ->
      case sequence_kernel.rollback(
        state,
        to_kernel_op(command, "rollback"),
        message_id,
      ) {
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
  let raw = json.to_string(sequence_kernel.summary(state))
  let assert Ok(loaded) =
    sequence_kernel.from_summary(
      raw,
      replica_id.new("client-" <> int.to_string(id)),
    )
  loaded
}
```

Build the model:

```gleam
pub fn model() -> KernelModel(
  sequence_kernel.SequenceState,
  SequenceCommand,
  List(json.Json),
) {
  KernelModel(
    name: "sequence",
    init: fn(id) {
      sequence_kernel.new(
        replica_id.new("client-" <> int.to_string(id)),
      )
    },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: sequence_kernel.values,
    gen_op: op_generator(),
    check: Some(sequence_kernel.check_cache_coherence),
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

The sequence model intentionally uses convergence plus cache coherence instead
of a log oracle: author-local indexes cannot be replayed independently as one
global list under concurrency. The deterministic kernel tests pin specific
conflict semantics; this fuzz model explores delivery, rollback, stash, and
summary schedules.

- [ ] **Step 6: Run focused and deeper sequence fuzzing**

Run:

```bash
gleam test sequence_fuzz
FUZZ_ITERATIONS=1000 gleam test sequence_fuzz
```

Expected: all sequence fuzz tests pass.

- [ ] **Step 7: Commit**

```bash
git add test/watershed/fuzz/sequence_model.gleam test/watershed/sequence_fuzz_test.gleam
git commit -m "test(sequence): add model fuzz coverage"
```

## Task 9: Document and Validate the Complete DDS

**Files:**

- Modify: `README.md:3-8`
- Modify: `README.md:51-74`
- Modify: `README.md:76-112`

- [ ] **Step 1: Update the README**

Add `SharedSequence` to the supported DDS summary. Add
`sequence_kernel` to the target-agnostic pure-core list. Add this short public
API example:

```gleam
let assert Ok(items) = watershed.create_sequence(doc)
let assert Ok(Nil) = watershed.sequence_insert(items, 0, json.string("first"))
let assert Ok(Nil) = watershed.sequence_move(items, 0, 0)
watershed.sequence_values(items)
```

State that sequence values are arbitrary JSON and that move destinations are
interpreted after removal. Describe `replace` as one Watershed op composed from
lattice delete and insert deltas. Do not describe replace as a native lattice
primitive.

- [ ] **Step 2: Format and inspect the diff**

Run:

```bash
gleam format
git diff --no-ext-diff --check
```

Expected: formatting succeeds and the diff has no whitespace errors.

- [ ] **Step 3: Run targeted sequence verification**

Run:

```bash
gleam test sequence_kernel
gleam test sequence_channel
gleam test wire
gleam test schema
gleam test sequence_fuzz
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
git commit -m "docs(sequence): document SharedSequence"
```

- [ ] **Step 6: Review the final branch diff**

Run:

```bash
git status --short
git log --oneline --decorate -10
git diff --no-ext-diff main...HEAD --stat
```

Expected: the worktree is clean, the sequence work is split into the planned
commits, and only the files listed in this plan changed.

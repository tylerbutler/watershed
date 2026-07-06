//// `KernelModel` for the directory kernel (SharedDirectory port).
////
//// ## Op wrapper
////
//// The harness `SequencedMeta` carries author + sequence number but not the
//// author's reference sequence number or client sequence number, which the
//// directory kernel needs (D12 stale-instance filter, create-info stamping).
//// So the wire op is a `DirCommand` that captures `ref_seq` (= the author's
//// delivered cursor at submit) and `client_seq` (= the local message id the
//// submit assigned) — mirroring `or_map_model`'s `CmdRemove(..., ref_seq)`.
////
//// ## Oracle soundness
////
//// The oracle folds the sequenced op log through `apply_remote` alone, from a
//// fresh directory, assigning 1-based sequence numbers exactly as the harness
//// does (`client.delivered + 1`). This is the same pure-remote computation a
//// read-only observer performs, independent of the incremental
//// sequenced/pending split every authoring client runs through submit → ack,
//// so a convergence bug that "agrees on the wrong answer" is still caught.
////
//// ## Observe / convergence
////
//// `observe` renders the sequenced tree (`summary_tree`) as canonical JSON:
//// per-node storage in insertion order, subdirs in `seqData` order, plus
//// create info, detached flag, and the creator set (sorted, since concurrent
//// same-name creates merge creators in author-delivery order and so may differ
//// only in list order between clients).

import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import qcheck
import watershed/directory_kernel.{
  type DirectoryOp, type DirectoryState, type SequencedMeta, Clear,
  CreateSubDirectory, Delete, DeleteSubDirectory, SequencedMeta, Set,
}
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}

/// The wire op: a directory op plus the submit-time metadata the kernel's
/// `SequencedMeta` needs but the harness one does not carry.
pub type DirCommand {
  DirCommand(op: DirectoryOp, ref_seq: Int, client_seq: Int)
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON round-trip (F4 failure fixtures)
// ─────────────────────────────────────────────────────────────────────────────

fn op_payload_to_json(op: DirectoryOp) -> Json {
  case op {
    Set(path, key, value) ->
      json.object([
        #("tag", json.string("Set")),
        #("path", json.string(path)),
        #("key", json.string(key)),
        #("value", value),
      ])
    Delete(path, key) ->
      json.object([
        #("tag", json.string("Delete")),
        #("path", json.string(path)),
        #("key", json.string(key)),
      ])
    Clear(path) ->
      json.object([#("tag", json.string("Clear")), #("path", json.string(path))])
    CreateSubDirectory(path, name) ->
      json.object([
        #("tag", json.string("CreateSubDirectory")),
        #("path", json.string(path)),
        #("name", json.string(name)),
      ])
    DeleteSubDirectory(path, name) ->
      json.object([
        #("tag", json.string("DeleteSubDirectory")),
        #("path", json.string(path)),
        #("name", json.string(name)),
      ])
  }
}

pub fn op_to_json(cmd: DirCommand) -> Json {
  json.object([
    #("op", op_payload_to_json(cmd.op)),
    #("ref_seq", json.int(cmd.ref_seq)),
    #("client_seq", json.int(cmd.client_seq)),
  ])
}

fn op_payload_decoder() -> decode.Decoder(DirectoryOp) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "Set" -> {
      use path <- decode.field("path", decode.string)
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", decode.int)
      decode.success(Set(path, key, json.int(value)))
    }
    "Delete" -> {
      use path <- decode.field("path", decode.string)
      use key <- decode.field("key", decode.string)
      decode.success(Delete(path, key))
    }
    "Clear" -> {
      use path <- decode.field("path", decode.string)
      decode.success(Clear(path))
    }
    "CreateSubDirectory" -> {
      use path <- decode.field("path", decode.string)
      use name <- decode.field("name", decode.string)
      decode.success(CreateSubDirectory(path, name))
    }
    _ -> {
      use path <- decode.field("path", decode.string)
      use name <- decode.field("name", decode.string)
      decode.success(DeleteSubDirectory(path, name))
    }
  }
}

pub fn op_decoder() -> decode.Decoder(DirCommand) {
  use op <- decode.field("op", op_payload_decoder())
  use ref_seq <- decode.field("ref_seq", decode.int)
  use client_seq <- decode.field("client_seq", decode.int)
  decode.success(DirCommand(op, ref_seq, client_seq))
}

// ─────────────────────────────────────────────────────────────────────────────
// Op generation (bounded path/key space so ops actually collide)
// ─────────────────────────────────────────────────────────────────────────────

fn path_from_int(n: Int) -> String {
  case n % 5 {
    0 -> "/"
    1 -> "/a"
    2 -> "/b"
    3 -> "/a/x"
    _ -> "/b/y"
  }
}

fn key_from_int(n: Int) -> String {
  "k" <> int.to_string(n % 4)
}

/// The parent/name pairs whose creation makes the deeper storage paths
/// reachable: `/a`, `/b`, `/a/x`, `/b/y`.
fn pair_from_int(n: Int) -> #(String, String) {
  case n % 4 {
    0 -> #("/", "a")
    1 -> #("/", "b")
    2 -> #("/a", "x")
    _ -> #("/b", "y")
  }
}

fn op_from_ints(kind: Int, a: Int, b: Int, c: Int) -> DirCommand {
  let op = case kind % 12 {
    0 | 1 | 2 | 3 | 4 ->
      Set(path_from_int(a), key_from_int(b), json.int(c % 100))
    5 | 6 -> Delete(path_from_int(a), key_from_int(b))
    7 -> Clear(path_from_int(a))
    8 | 9 -> {
      let #(parent, name) = pair_from_int(a)
      CreateSubDirectory(parent, name)
    }
    _ -> {
      let #(parent, name) = pair_from_int(a)
      DeleteSubDirectory(parent, name)
    }
  }
  DirCommand(op, 0, 0)
}

fn op_generator() -> qcheck.Generator(DirCommand) {
  qcheck.tuple4(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(ints) { op_from_ints(ints.0, ints.1, ints.2, ints.3) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Model callbacks
// ─────────────────────────────────────────────────────────────────────────────

fn submit(
  state: DirectoryState,
  cmd: DirCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(DirectoryState, Option(DirCommand)) {
  let ref_seq = meta.last_seen_seq
  case cmd.op {
    Set(path, key, value) ->
      case directory_kernel.set(state, path, key, value) {
        Ok(#(state, _events, op, mid)) -> #(
          state,
          Some(DirCommand(op, ref_seq, mid)),
        )
        Error(_) -> #(state, None)
      }
    Delete(path, key) ->
      case directory_kernel.delete(state, path, key) {
        Ok(#(state, _events, op, mid)) -> #(
          state,
          Some(DirCommand(op, ref_seq, mid)),
        )
        Error(_) -> #(state, None)
      }
    Clear(path) ->
      case directory_kernel.clear(state, path) {
        Ok(#(state, _events, op, mid)) -> #(
          state,
          Some(DirCommand(op, ref_seq, mid)),
        )
        Error(_) -> #(state, None)
      }
    CreateSubDirectory(path, name) ->
      case
        directory_kernel.create_subdirectory(state, path, name, meta.client_id)
      {
        Ok(#(state, _events, Some(op), mid)) -> #(
          state,
          Some(DirCommand(op, ref_seq, mid)),
        )
        Ok(#(state, _events, None, _mid)) -> #(state, None)
        Error(_) -> #(state, None)
      }
    DeleteSubDirectory(path, name) ->
      case directory_kernel.delete_subdirectory(state, path, name) {
        Ok(#(state, _events, Some(op), mid)) -> #(
          state,
          Some(DirCommand(op, ref_seq, mid)),
        )
        Ok(#(state, _events, None, _mid)) -> #(state, None)
        Error(_) -> #(state, None)
      }
  }
}

fn kernel_meta(
  cmd: DirCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> SequencedMeta {
  SequencedMeta(
    author: meta.client_id,
    sequence_number: meta.sequence_number,
    reference_sequence_number: cmd.ref_seq,
    client_sequence_number: cmd.client_seq,
  )
}

fn apply_remote(
  state: DirectoryState,
  cmd: DirCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(DirectoryState, String) {
  let #(state, _events) =
    directory_kernel.apply_remote(state, cmd.op, kernel_meta(cmd, meta))
  Ok(state)
}

fn ack_local(
  state: DirectoryState,
  cmd: DirCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(DirectoryState, String) {
  case directory_kernel.ack_local(state, cmd.op, kernel_meta(cmd, meta)) {
    Ok(state) -> Ok(state)
    Error(err) -> Error(string.inspect(err))
  }
}

fn rollback(state: DirectoryState, cmd: DirCommand) -> DirectoryState {
  case directory_kernel.last_pending_message_id(state) {
    None -> state
    Some(message_id) ->
      case directory_kernel.rollback(state, cmd.op, message_id) {
        Ok(#(state, _events)) -> state
        Error(_) -> state
      }
  }
}

/// Mirror a `SharedDirectory`'s `reSubmitCore`: when a reconnecting client
/// resends a queued op, drop it if its pending edit no longer exists (its
/// target subdirectory was deleted while offline) and otherwise re-stamp its
/// reference sequence number to the client's current cursor, exactly as the
/// Fluid runtime does on every resend. Without this the harness would resend
/// with a stale `ref_seq`, making the kernel's instance-identity check resolve
/// differently across clients and diverge.
fn resubmit(
  state: DirectoryState,
  cmd: DirCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> Option(DirCommand) {
  case directory_kernel.resubmit(state, cmd.op, cmd.client_seq) {
    Ok(Some(op)) -> Some(DirCommand(op, meta.last_seen_seq, cmd.client_seq))
    _ -> None
  }
}

fn apply_stashed(
  state: DirectoryState,
  cmd: DirCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(DirectoryState, DirCommand) {
  case directory_kernel.apply_stashed_op(state, cmd.op, meta.client_id) {
    Ok(#(state, _events, Some(op), mid)) -> #(
      state,
      DirCommand(op, meta.last_seen_seq, mid),
    )
    // The stashed op was a local no-op (its target path wasn't reachable, or a
    // create/delete that dedups against existing state), so `submit` would have
    // routed nothing. The harness always routes what `apply_stashed` returns,
    // so route a guaranteed global no-op (deleting a name no `gen_op` ever
    // produces) rather than a phantom op that would appear only on ack.
    Ok(#(state, _events, None, _mid)) -> #(state, nop_command(meta))
    Error(_) -> #(state, nop_command(meta))
  }
}

/// A wire op that is a no-op on every client: deleting a subdirectory whose name
/// is never generated, so it exists nowhere. `apply_remote` and `ack_local`
/// both treat a delete of an absent subdir as a no-op, leaving `observe`
/// unchanged everywhere.
fn nop_command(meta: kernel_fuzz.SubmitMeta) -> DirCommand {
  DirCommand(DeleteSubDirectory("/", "\u{1}nop"), meta.last_seen_seq, 0)
}

// ─────────────────────────────────────────────────────────────────────────────
// Observe / oracle / check
// ─────────────────────────────────────────────────────────────────────────────

/// Join a parent path and child name (root has no trailing slash to double up).
fn child_path(path: String, name: String) -> String {
  case path {
    "/" -> "/" <> name
    _ -> path <> "/" <> name
  }
}

/// Encode the *optimistic* view rooted at `path`: visible storage (insertion
/// order) plus visible subdirectories (`seqData` order), recursively. Using the
/// optimistic view keeps `ack_local` transparent (a pending value is visible
/// both before and after its ack); after a `Synchronize` drains all pending,
/// this equals the sequenced tree the oracle computes.
/// A structured view of the optimistic tree. Storage/subdirs preserve their
/// visible order so convergence checks that ordering agrees after sync; the
/// `canonicalize` hook sorts them for the ack-transparency check alone (acking
/// a pending storage entry moves it from the pending bucket to the sequenced
/// bucket, reordering `entries()` without changing content — see `map_model`).
pub type Tree {
  Tree(storage: List(#(String, Json)), subdirs: List(#(String, Tree)))
}

fn observe_node(state: DirectoryState, path: String) -> Tree {
  Tree(
    storage: directory_kernel.entries(state, path),
    subdirs: list.map(directory_kernel.subdirectories(state, path), fn(name) {
      #(name, observe_node(state, child_path(path, name)))
    }),
  )
}

fn observe(state: DirectoryState) -> Tree {
  observe_node(state, "/")
}

fn canonicalize(tree: Tree) -> Tree {
  Tree(
    storage: list.sort(tree.storage, fn(a, b) { string.compare(a.0, b.0) }),
    subdirs: list.sort(tree.subdirs, fn(a, b) { string.compare(a.0, b.0) })
      |> list.map(fn(kv) { #(kv.0, canonicalize(kv.1)) }),
  )
}

fn oracle(entries: List(LogEntry(DirCommand))) -> Tree {
  let #(state, _seq) =
    list.fold(
      kernel_fuzz.log_ops(entries),
      #(directory_kernel.new(), 1),
      fn(acc, item) {
        let #(state, seq) = acc
        let #(author, cmd) = item
        let meta =
          SequencedMeta(
            author: author,
            sequence_number: seq,
            reference_sequence_number: cmd.ref_seq,
            client_sequence_number: cmd.client_seq,
          )
        let #(state, _events) =
          directory_kernel.apply_remote(state, cmd.op, meta)
        #(state, seq + 1)
      },
    )
  observe(state)
}

fn check(state: DirectoryState) -> Result(Nil, String) {
  case directory_kernel.check_invariants(state) {
    Ok(Nil) -> Ok(Nil)
    Error(err) -> Error(string.inspect(err))
  }
}

/// Summary round-trip: a joining client loads client 0's caught-up sequenced
/// tree (pending local edits never carry over; client 0 never authors).
fn load_from_synced(state: DirectoryState, _id: Int) -> DirectoryState {
  directory_kernel.from_summary(directory_kernel.summary_tree(state))
}

pub fn model() -> KernelModel(DirectoryState, DirCommand, Tree) {
  KernelModel(
    name: "directory",
    init: fn(_id) { directory_kernel.new() },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: observe,
    gen_op: op_generator(),
    check: Some(check),
    canonicalize: Some(canonicalize),
    // A local ack can legitimately change this client's own view: when our
    // subdirectory-create op is acked after a concurrent remote delete has
    // already disposed that instance, sequencing our create *behind* the
    // delete removes the subtree we had shown optimistically (a "presence
    // flip"). This mirrors `SharedDirectory` and the claims/register kernels,
    // which likewise opt out of ack-view transparency.
    ack_preserves_view: False,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: Some(rollback),
      apply_stashed: Some(apply_stashed),
      resubmit: Some(resubmit),
      react: None,
      remove_member: None,
    ),
  )
}

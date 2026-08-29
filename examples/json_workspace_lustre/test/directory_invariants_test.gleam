//// A pure-kernel pin for the recreate-while-held race this example's README
//// documents: an op addressed to a path is filtered by that path's live
//// *instance*, not only its string. Modeled directly on `directory_kernel`,
//// the same seam `directory_kernel_test.gleam`'s
//// `stale_op_ignored_after_delete_recreate_test` uses in the root package,
//// because the facade intentionally does not expose a live channel's
//// internal `DirectoryState` for a test to call `check_invariants` on.
//// `test/convergence_test.gleam` pins the same race through the public
//// facade and a real client-offline window; this file pins it at the level
//// the invariant checker can actually run at.

import gleam/json
import gleeunit/should

import watershed/directory_kernel.{
  type DirectoryOp, type DirectoryState, type SequencedMeta, CreateSubDirectory,
  DeleteSubDirectory, SequencedMeta, Set,
}

fn meta(author: Int, seq: Int, ref_seq: Int, cseq: Int) -> SequencedMeta {
  SequencedMeta(
    author: author,
    sequence_number: seq,
    reference_sequence_number: ref_seq,
    client_sequence_number: cseq,
  )
}

/// Apply one op as a remote client would see it sequenced by the server —
/// the room's shared log, not a particular author's optimistic view.
fn remote(
  state: DirectoryState,
  op: DirectoryOp,
  m: SequencedMeta,
) -> DirectoryState {
  let #(state, _events) = directory_kernel.apply_remote(state, op, m, 0)
  state
}

pub fn a_stale_write_queued_before_a_delete_and_recreate_is_dropped_test() -> Nil {
  // The room's server log, as every client eventually sees it: client 1
  // creates "/specs" (seq 1), deletes it (seq 2), and client 2 recreates it
  // (seq 3) — all before client 1's queued write is sequenced.
  let state =
    directory_kernel.new()
    |> remote(CreateSubDirectory("/", "specs"), meta(1, 1, 0, 0))
    |> remote(DeleteSubDirectory("/", "specs"), meta(1, 2, 1, 0))
    |> remote(CreateSubDirectory("/", "specs"), meta(2, 3, 0, 0))

  // Client 1 queued this write against the instance it last saw live — the
  // one that died at seq 2 — while it was offline. Its reference sequence
  // number (1) predates the recreate (seq 3), so the write targets a dead
  // instance and must not land on the live one.
  let state =
    remote(
      state,
      Set("/specs", "draft", json.string("stale")),
      meta(1, 4, 1, 0),
    )

  directory_kernel.has_subdirectory(state, "/", "specs") |> should.be_true()
  directory_kernel.get(state, "/specs", "draft") |> should.equal(Error(Nil))
  directory_kernel.check_invariants(state) |> should.equal(Ok(Nil))
}

pub fn a_write_sequenced_after_the_recreate_applies_test() -> Nil {
  let state =
    directory_kernel.new()
    |> remote(CreateSubDirectory("/", "specs"), meta(1, 1, 0, 0))
    |> remote(DeleteSubDirectory("/", "specs"), meta(1, 2, 1, 0))
    |> remote(CreateSubDirectory("/", "specs"), meta(2, 3, 0, 0))

  // A write whose reference sequence number is at or past the recreate's own
  // sequence number targets the live instance, even from a client that did
  // not create it.
  let state =
    remote(
      state,
      Set("/specs", "draft", json.string("fresh")),
      meta(1, 4, 3, 0),
    )

  directory_kernel.get(state, "/specs", "draft")
  |> should.equal(Ok(json.string("fresh")))
  directory_kernel.check_invariants(state) |> should.equal(Ok(Nil))
}

pub fn invariants_hold_after_a_nested_folder_and_document_scenario_test() -> Nil {
  let state =
    directory_kernel.new()
    |> remote(CreateSubDirectory("/", "specs"), meta(1, 1, 0, 0))
    |> remote(Set("/specs", "api", json.string("handle-1")), meta(1, 2, 1, 0))
    |> remote(CreateSubDirectory("/specs", "drafts"), meta(2, 3, 2, 0))
    |> remote(DeleteSubDirectory("/", "specs"), meta(1, 4, 3, 0))

  directory_kernel.check_invariants(state) |> should.equal(Ok(Nil))
}

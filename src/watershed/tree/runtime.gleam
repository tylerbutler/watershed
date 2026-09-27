//// Contextual SharedTree wire and kernel operations. The document owns the compressor.

import gleam/bool
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{type Edit, type SequencePoint, type TreeError}
import watershed/tree_kernel

pub fn restore(
  snapshot: tree_kernel.TreeSnapshot,
  view_id: fluid_ids.StableId,
  view: schema.ViewSchema,
  compressor: fluid_ids.Compressor,
) -> Result(tree_kernel.TreeState, TreeError) {
  use state <- result.try(tree_kernel.restore(
    snapshot,
    view_id,
    fluid_ids.local_session(compressor),
    view,
  ))
  rebind_state(state, compressor)
}

fn rebind_state(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(tree_kernel.TreeState, TreeError) {
  use order <- result.try(codec.identity_order(
    tree_kernel.identity_revisions(state),
    compressor,
    "tree history identity order",
  ))
  tree_kernel.rebind_identity_order(state, order)
}

pub fn wire_to_commit(
  wire: codec.WireCommit,
) -> Result(history.Commit, TreeError) {
  let codec.WireCommit(revision, originator, changes, _) = wire
  use decoded <- result.try(shared_change.from_changes(changes))
  Ok(history.Commit(revision, originator, decoded))
}

pub fn decode_message(
  raw: String,
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(#(history.Commit, codec.TreeMessage), TreeError) {
  use message <- result.try(codec.decode_message_with_schema(
    raw,
    codec.DecodeContext(codec.Fluid310, compressor),
    tree_kernel.stored_schema(state),
  ))
  use commit <- result.try(wire_to_commit(message.commit))
  use _ <- result.try(identity_order(state, commit, compressor))
  Ok(#(commit, message))
}

pub fn decode_sequenced_message(
  raw: String,
  state: tree_kernel.TreeState,
  reference_sequence_number: Int,
  compressor: fluid_ids.Compressor,
) -> Result(#(history.Commit, codec.TreeMessage), TreeError) {
  use originator <- result.try(codec.decode_message_originator(raw))
  use stored <- result.try(tree_kernel.authoring_schema(
    state,
    originator,
    reference_sequence_number,
  ))
  use message <- result.try(codec.decode_message_with_schema_state(
    raw,
    codec.DecodeContext(codec.Fluid310, compressor),
    stored,
  ))
  use commit <- result.try(wire_to_commit(message.commit))
  use _ <- result.try(identity_order(state, commit, compressor))
  Ok(#(commit, message))
}

pub fn encode_commit(
  commit: history.Commit,
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  codec.encode_message(
    codec.TreeMessage(
      codec.WireCommit(
        commit.revision,
        commit.originator,
        shared_change.to_changes(commit.change),
        None,
      ),
      [],
    ),
    codec.EncodeContext(
      codec.Fluid310,
      compressor,
      Some(tree_kernel.stored_schema(state)),
    ),
  )
}

pub fn identity_order(
  state: tree_kernel.TreeState,
  commit: history.Commit,
  compressor: fluid_ids.Compressor,
) -> Result(change.IdentityOrder, TreeError) {
  codec.identity_order(
    [
      commit.revision,
      ..list.append(
        shared_change.identity_revisions(commit.change),
        tree_kernel.identity_revisions(state),
      )
    ],
    compressor,
    "tree commit identity order",
  )
}

pub fn receive_commit(
  state: tree_kernel.TreeState,
  commit: history.Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  minimum_sequence_number: Int,
  compressor: fluid_ids.Compressor,
) -> Result(
  #(tree_kernel.TreeState, tree_kernel.ChangeEvents, fluid_ids.Compressor),
  TreeError,
) {
  let revisions = [
    commit.revision,
    ..list.append(
      shared_change.identity_revisions(commit.change),
      tree_kernel.identity_revisions(state),
    )
  ]
  use order <- result.try(codec.identity_order(
    revisions,
    compressor,
    "tree commit identity order",
  ))
  tree_kernel.receive_ordered(
    state,
    commit,
    order,
    point,
    reference_sequence_number,
    minimum_sequence_number,
    compressor,
    fn(current) { mint_revision(current, revisions) },
  )
}

pub fn advance_document(
  state: tree_kernel.TreeState,
  sequence_number: Int,
  minimum_sequence_number: Int,
  compressor: fluid_ids.Compressor,
) -> Result(#(tree_kernel.TreeState, fluid_ids.Compressor), TreeError) {
  use state <- result.try(rebind_state(state, compressor))
  let revisions = tree_kernel.identity_revisions(state)
  tree_kernel.advance_document(
    state,
    sequence_number,
    minimum_sequence_number,
    compressor,
    fn(current) { mint_revision(current, revisions) },
  )
}

/// Valid empty array edits return no commit and preserve the compressor.
pub fn author_edit(
  state: tree_kernel.TreeState,
  edit: Edit,
  compressor: fluid_ids.Compressor,
) -> Result(
  #(
    tree_kernel.TreeState,
    Option(history.Commit),
    tree_kernel.ChangeEvents,
    fluid_ids.Compressor,
  ),
  TreeError,
) {
  use _ <- result.try(tree_kernel.validate_edit(state, edit))
  let empty = case edit {
    types.ArrayInsert(_, _, []) -> True
    types.ArrayRemove(_, start, end) | types.ArrayMove(_, start, end, _, _) ->
      start == end
    _ -> False
  }
  use <- bool.guard(
    empty,
    Ok(#(state, None, tree_kernel.ChangeEvents([], False), compressor)),
  )
  use #(compressor, id) <- result.try(
    fluid_ids.generate(compressor)
    |> result.map_error(fn(error) {
      types.CorruptData("tree revision allocation", string.inspect(error))
    }),
  )
  use revision <- result.try(
    fluid_ids.decompress(compressor, id)
    |> result.map_error(fn(error) {
      types.CorruptData("tree revision allocation", string.inspect(error))
    }),
  )
  use order <- result.try(codec.identity_order(
    [revision, ..tree_kernel.identity_revisions(state)],
    compressor,
    "tree author identity order",
  ))
  use #(state, commit, events) <- result.try(tree_kernel.apply_local(
    state,
    revision,
    order,
    edit,
  ))
  Ok(#(state, Some(commit), events, compressor))
}

fn mint_revision(
  compressor: fluid_ids.Compressor,
  revisions: List(fluid_ids.StableId),
) -> Result(
  #(fluid_ids.StableId, change.IdentityOrder, fluid_ids.Compressor),
  TreeError,
) {
  use #(compressor, id) <- result.try(
    fluid_ids.generate(compressor)
    |> result.map_error(fn(error) {
      types.CorruptData("tree rollback allocation", string.inspect(error))
    }),
  )
  use revision <- result.try(
    fluid_ids.decompress(compressor, id)
    |> result.map_error(fn(error) {
      types.CorruptData("tree rollback allocation", string.inspect(error))
    }),
  )
  use order <- result.try(codec.identity_order(
    [revision, ..revisions],
    compressor,
    "tree rollback identity order",
  ))
  Ok(#(revision, order, compressor))
}

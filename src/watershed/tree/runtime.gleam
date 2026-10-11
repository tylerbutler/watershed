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
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/identifier
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{
  type Edit, type SequencePoint, type TreeError, type TreeValue, InvalidHistory,
}
import watershed/tree_kernel

pub fn create_detached(
  stored: schema.StoredSchema,
  initial_root: Option(TreeValue),
  view_id: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(#(tree_kernel.TreeState, fluid_ids.Compressor), TreeError) {
  use #(state, compressor, _) <- result.try(create_detached_with_commit(
    stored,
    initial_root,
    view_id,
    compressor,
    sequence_number,
    minimum_sequence_number,
  ))
  Ok(#(state, compressor))
}

pub fn create_detached_with_commit(
  stored: schema.StoredSchema,
  initial_root: Option(TreeValue),
  view_id: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(
  #(tree_kernel.TreeState, fluid_ids.Compressor, history.Commit),
  TreeError,
) {
  use _ <- result.try(schema.validate_root_construction(stored, initial_root))
  use #(compressor, id) <- result.try(
    fluid_ids.generate(compressor)
    |> result.map_error(fn(error) { InvalidHistory(string.inspect(error)) }),
  )
  use revision <- result.try(
    fluid_ids.decompress(compressor, id)
    |> result.map_error(fn(error) { InvalidHistory(string.inspect(error)) }),
  )
  use #(initial_root, compressor) <- result.try(case initial_root {
    None -> Ok(#(None, compressor))
    Some(value) ->
      identifier.materialize_value(stored, value, compressor)
      |> result.map(fn(value) { #(Some(value.0), value.1) })
  })
  use _ <- result.try(schema.validate_root_field(stored, initial_root))
  use order <- result.try(codec.identity_order(
    [revision],
    compressor,
    "tree initialization",
  ))
  use outer <- result.try(initialization_change(
    stored,
    initial_root,
    revision,
    order,
  ))
  let commit =
    history.Commit(revision, fluid_ids.local_session(compressor), outer)
  use snapshot <- result.try(tree_kernel.snapshot_from_parts(
    view_id,
    stored,
    forest.ForestData(initial_root, [], 1),
    history.HistorySnapshot(
      history.InitialBase,
      [
        history.SequencedCommit(
          commit,
          types.SequencePoint(-9_007_199_254_740_990, 0),
        ),
      ],
      [],
      sequence_number,
      minimum_sequence_number,
      [],
    ),
  ))
  use state <- result.try(restore_unviewed(snapshot, view_id, compressor))
  Ok(#(state, compressor, commit))
}

fn initialization_change(
  stored: schema.StoredSchema,
  initial_root: Option(TreeValue),
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
) -> Result(shared_change.Changeset, TreeError) {
  use intermediate <- result.try(schema.initialization_schema(stored))
  let items = [
    shared_change.SchemaChange(
      schema.EmptySchema,
      schema.FixedSchema(intermediate),
      False,
    ),
  ]
  use data <- result.try(case initial_root {
    None -> Ok([])
    Some(root) -> {
      let detach = types.AtomId(Some(revision), 0)
      let fill = types.AtomId(Some(revision), 1)
      use data <- result.try(change.from_data(
        change.ChangeData(
          ..change.to_data(change.empty()),
          max_local_id: 1,
          revisions: [change.RevisionInfo(revision, None)],
          fields: [
            #(
              "rootFieldKey",
              change.OptionalField(optional_field.set(True, fill, detach)),
            ),
          ],
          builds: [forest.Build(fill, [root])],
        ),
        order,
      ))
      Ok([shared_change.DataChange(data)])
    }
  })
  let finish = case intermediate == stored {
    True -> []
    False -> [
      shared_change.SchemaChange(
        schema.FixedSchema(intermediate),
        schema.FixedSchema(stored),
        False,
      ),
    ]
  }
  shared_change.from_changes(list.append(items, list.append(data, finish)))
}

pub fn snapshot_for_attach(
  state: tree_kernel.TreeState,
  _compressor: fluid_ids.Compressor,
) -> Result(tree_kernel.TreeSnapshot, TreeError) {
  tree_kernel.snapshot_for_attach(state)
}

pub type AuthoredEdit {
  AuthoredEdit(
    state: tree_kernel.TreeState,
    change: shared_change.Changeset,
    events: tree_kernel.ChangeEvents,
    compressor: fluid_ids.Compressor,
  )
}

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

pub fn restore_unviewed(
  snapshot: tree_kernel.TreeSnapshot,
  view_id: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
) -> Result(tree_kernel.TreeState, TreeError) {
  use state <- result.try(tree_kernel.restore_unviewed(
    snapshot,
    view_id,
    fluid_ids.local_session(compressor),
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
  let context = codec.DecodeContext(codec.Fluid310, compressor)
  use #(originator, revision) <- result.try(codec.decode_message_identity(
    raw,
    context,
  ))
  use stored <- result.try(tree_kernel.authoring_schema(
    state,
    originator,
    reference_sequence_number,
    revision,
  ))
  use message <- result.try(codec.decode_message_with_schema_state(
    raw,
    context,
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

pub fn encode_pending_commit(
  commit: history.Commit,
  state: tree_kernel.TreeState,
  reference_sequence_number: Int,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  use start <- result.try(tree_kernel.authoring_schema(
    state,
    commit.originator,
    reference_sequence_number,
    commit.revision,
  ))
  encode_pending_commit_from_schema(commit, start, compressor)
}

pub fn encode_pending_commit_from_schema(
  commit: history.Commit,
  start: schema.SchemaState,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  use finish <- result.try(tree_kernel.advance_authoring_schema(
    start,
    shared_change.to_changes(commit.change),
  ))
  case finish {
    schema.FixedSchema(stored) ->
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
        codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
      )
    schema.EmptySchema ->
      Error(types.UnsupportedFeature(
        "tree.schema",
        "cannot encode a commit with an uninitialized schema",
      ))
  }
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
  use authored <- result.try(author_edit_change(state, edit, compressor))
  case authored {
    None -> Ok(#(state, None, tree_kernel.ChangeEvents([], False), compressor))
    Some(authored) -> {
      use revision <- result.try(authored_revision(authored.change))
      use order <- result.try(identity_order(
        state,
        history.Commit(
          revision,
          fluid_ids.local_session(compressor),
          authored.change,
        ),
        authored.compressor,
      ))
      use #(state, commit, events) <- result.try(tree_kernel.apply_local_change(
        state,
        revision,
        order,
        authored.change,
      ))
      Ok(#(state, Some(commit), events, authored.compressor))
    }
  }
}

pub fn author_edit_change(
  state: tree_kernel.TreeState,
  edit: Edit,
  compressor: fluid_ids.Compressor,
) -> Result(Option(AuthoredEdit), TreeError) {
  author_edit_change_from(state, edit, compressor, None)
}

pub fn allocate_transaction_revision(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(
  #(fluid_ids.StableId, change.IdentityOrder, fluid_ids.Compressor),
  TreeError,
) {
  allocate_revision(state, compressor)
}

pub fn author_transaction_edit_change(
  state: tree_kernel.TreeState,
  edit: Edit,
  compressor: fluid_ids.Compressor,
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
  first_local_id: Int,
) -> Result(Option(AuthoredEdit), TreeError) {
  use #(edit, compressor) <- result.try(identifier.materialize_edit(
    tree_kernel.stored_schema(state),
    edit,
    compressor,
  ))
  use _ <- result.try(tree_kernel.validate_edit(state, edit))
  let empty = case edit {
    types.ArrayInsert(_, _, []) -> True
    types.ArrayRemove(_, start, end) | types.ArrayMove(_, start, end, _, _) ->
      start == end
    _ -> False
  }
  use <- bool.guard(empty, Ok(None))
  use change <- result.try(tree_kernel.author_local_change_from(
    state,
    revision,
    order,
    edit,
    first_local_id,
  ))
  use #(state, events) <- result.try(tree_kernel.apply_local_preview(
    state,
    revision,
    order,
    change,
  ))
  Ok(Some(AuthoredEdit(state, change, events, compressor)))
}

fn author_edit_change_from(
  state: tree_kernel.TreeState,
  edit: Edit,
  compressor: fluid_ids.Compressor,
  first_local_id: Option(Int),
) -> Result(Option(AuthoredEdit), TreeError) {
  use #(edit, compressor) <- result.try(identifier.materialize_edit(
    tree_kernel.stored_schema(state),
    edit,
    compressor,
  ))
  use _ <- result.try(tree_kernel.validate_edit(state, edit))
  let empty = case edit {
    types.ArrayInsert(_, _, []) -> True
    types.ArrayRemove(_, start, end) | types.ArrayMove(_, start, end, _, _) ->
      start == end
    _ -> False
  }
  use <- bool.guard(empty, Ok(None))
  use #(revision, order, compressor) <- result.try(allocate_revision(
    state,
    compressor,
  ))
  use change <- result.try(case first_local_id {
    None -> tree_kernel.author_local_change(state, revision, order, edit)
    Some(first_local_id) ->
      tree_kernel.author_local_change_from(
        state,
        revision,
        order,
        edit,
        first_local_id,
      )
  })
  use #(state, events) <- result.try(tree_kernel.apply_local_preview(
    state,
    revision,
    order,
    change,
  ))
  Ok(Some(AuthoredEdit(state, change, events, compressor)))
}

pub fn author_upgrade(
  state: tree_kernel.TreeState,
  view: schema.ViewSchema,
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
  use target <- result.try(schema.prepare_upgrade(
    tree_kernel.stored_schema(state),
    view,
  ))
  case target {
    None -> Ok(#(state, None, tree_kernel.ChangeEvents([], False), compressor))
    Some(target) -> {
      use #(revision, order, compressor) <- result.try(allocate_revision(
        state,
        compressor,
      ))
      use outer <- result.try(
        shared_change.from_changes([
          shared_change.SchemaChange(
            schema.FixedSchema(tree_kernel.stored_schema(state)),
            schema.FixedSchema(target),
            False,
          ),
        ]),
      )
      use #(state, commit, events) <- result.try(tree_kernel.apply_local_change(
        state,
        revision,
        order,
        outer,
      ))
      Ok(#(state, Some(commit), events, compressor))
    }
  }
}

pub fn author_revert(
  state: tree_kernel.TreeState,
  id: types.RevertibleId,
  compressor: fluid_ids.Compressor,
) -> Result(
  #(
    tree_kernel.TreeState,
    history.Commit,
    types.TreeCommitKind,
    tree_kernel.ChangeEvents,
    fluid_ids.Compressor,
  ),
  TreeError,
) {
  use #(revision, order, compressor) <- result.try(allocate_revision(
    state,
    compressor,
  ))
  use #(state, commit, kind, events) <- result.try(tree_kernel.revert(
    state,
    id,
    revision,
    order,
  ))
  Ok(#(state, commit, kind, events, compressor))
}

pub fn commit_outcome(
  changeset: shared_change.Changeset,
) -> types.TreeCommitOutcome {
  let changes = shared_change.to_changes(changeset)
  case changes {
    [] -> types.FullyDropped
    _ ->
      case
        list.any(changes, fn(item) {
          case item {
            shared_change.DataChange(data) ->
              change.to_data(data).constraint_violation_count > 0
            shared_change.SchemaChange(_, _, _) -> False
          }
        })
      {
        True -> types.NewContentOnly
        False -> types.FullyApplied
      }
  }
}

fn allocate_revision(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(
  #(fluid_ids.StableId, change.IdentityOrder, fluid_ids.Compressor),
  TreeError,
) {
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
  Ok(#(revision, order, compressor))
}

pub fn authored_revision(
  value: shared_change.Changeset,
) -> Result(fluid_ids.StableId, TreeError) {
  case
    shared_change.revision_infos(shared_change.TaggedChange(None, None, value))
  {
    [info] -> Ok(info.revision)
    [] -> Error(types.InvalidHistory("authored edit has no revision"))
    _ -> Error(types.InvalidHistory("authored edit has multiple revisions"))
  }
}

pub fn mint_revision(
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

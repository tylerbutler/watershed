//// Pure modular changes for the fixed SharedTree profile.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import watershed/fluid_ids.{type StableId}
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/schema.{
  type Cardinality, type FieldSchema, type StoredSchema, FieldSchema, Optional,
  Required,
}
import watershed/tree/sequence_field
import watershed/tree/sequence_field/compose as sequence_compose
import watershed/tree/sequence_field/invert as sequence_invert
import watershed/tree/sequence_field/moves
import watershed/tree/sequence_field/rebase as sequence_rebase
import watershed/tree/types.{
  type AtomId, type Edit, type FieldPath, type TreeError, type TreeValue,
  ArrayInsert, ArrayMove, ArrayRemove, AtomId, ClearField, CorruptData,
  InvalidEdit, InvalidHistory, MapDelete, MapSet, ObjectValue, SetField,
}

const max_safe_integer = 9_007_199_254_740_991

pub type RevisionInfo {
  RevisionInfo(revision: StableId, rollback_of: Option(StableId))
}

pub type FieldChange {
  ValueField(optional_field.FieldChange)
  OptionalField(optional_field.FieldChange)
  SequenceField(sequence_field.Changeset)
  GenericField(children: List(#(Int, AtomId)))
}

pub type NodeExistsConstraint {
  NodeExistsConstraint(violated: Bool)
}

pub type ConstraintTarget {
  ConstraintTarget(reference: forest.NodeRef, path: FieldPath)
}

pub type NodeChange {
  NodeChange(
    fields: List(#(String, FieldChange)),
    node_exists_constraint: Option(NodeExistsConstraint),
    node_exists_constraint_on_revert: Option(NodeExistsConstraint),
  )
}

pub type ParentField {
  ParentField(parent: Option(AtomId), field: String)
}

pub type CrossFieldKey {
  CrossFieldKey(key: moves.Key, count: Int, field: moves.FieldId)
}

pub type ChangeData {
  ChangeData(
    max_local_id: Int,
    revisions: List(RevisionInfo),
    fields: List(#(String, FieldChange)),
    nodes: List(#(AtomId, NodeChange)),
    parents: List(#(AtomId, ParentField)),
    aliases: List(#(AtomId, AtomId)),
    builds: List(forest.Build),
    destroys: List(forest.Destroy),
    refreshers: List(forest.Build),
    cross_field_keys: List(CrossFieldKey),
    constraint_violation_count: Int,
  )
}

pub opaque type IdentityOrder {
  IdentityOrder(entries: List(#(StableId, Int)))
}

pub opaque type Changeset {
  Changeset(
    data: ChangeData,
    identity_order: IdentityOrder,
    cross_field_keys: List(CrossFieldKey),
  )
}

pub type TaggedChange {
  TaggedChange(
    revision: Option(StableId),
    rollback_of: Option(StableId),
    change: Changeset,
  )
}

pub opaque type RebaseContext {
  RebaseContext(revisions: List(RevisionInfo))
}

type Ownership {
  Ownership(id: AtomId, parent: ParentField)
}

type Branch {
  Branch(
    field: String,
    index: Int,
    top: AtomId,
    nodes: List(#(AtomId, NodeChange)),
    parents: List(#(AtomId, ParentField)),
    next_id: Int,
  )
}

type DeltaParts {
  DeltaParts(
    fields: List(#(String, forest.FieldDelta)),
    global: List(forest.DetachedChange),
    rename: List(forest.Rename),
  )
}

type ComposeWork {
  ComposeWork(
    source_field: moves.FieldId,
    result_field: moves.FieldId,
    first: sequence_field.Changeset,
    second: sequence_field.Changeset,
  )
}

type ComposeState {
  ComposeState(
    nodes: List(#(AtomId, NodeChange)),
    parents: List(#(AtomId, ParentField)),
    aliases: List(#(AtomId, AtomId)),
    first: ChangeData,
    second: ChangeData,
    pairs: List(#(AtomId, AtomId)),
    pending_pairs: List(#(AtomId, AtomId)),
    algebra: sequence_field.AlgebraContext,
    move_context: moves.Context,
    work: List(ComposeWork),
    field_results: List(#(moves.FieldId, FieldChange)),
    affected_seen: List(moves.Affected),
  )
}

type ReplaceState {
  ReplaceState(
    obsolete: List(Option(StableId)),
    updated: StableId,
    mappings: List(#(AtomId, AtomId)),
    used: List(AtomId),
    max_seen: Int,
  )
}

type PruneState {
  PruneState(
    nodes: List(#(AtomId, NodeChange)),
    parents: List(#(AtomId, ParentField)),
  )
}

type ConstraintState {
  ConstraintState(nodes: List(#(AtomId, NodeChange)), violation_count: Int)
}

type RebaseState {
  RebaseState(
    nodes: List(#(AtomId, NodeChange)),
    parents: List(#(AtomId, ParentField)),
    aliases: List(#(AtomId, AtomId)),
    authored: ChangeData,
    base: ChangeData,
    base_to_rebased: List(#(AtomId, AtomId)),
    pairs: List(#(AtomId, AtomId)),
    pending_pairs: List(#(AtomId, AtomId, optional_field.AttachState)),
    pending_fields: List(RebaseWork),
    algebra: sequence_field.AlgebraContext,
    move_context: moves.Context,
    work: List(RebaseWork),
    field_work: List(RebaseFieldWork),
    field_results: List(#(moves.FieldId, FieldChange)),
  )
}

type RebaseFieldWork {
  RebaseFieldWork(
    source_field: moves.FieldId,
    result_field: moves.FieldId,
    authored: FieldChange,
    base: FieldChange,
  )
}

type RebaseWork {
  RebaseWork(
    source_field: moves.FieldId,
    result_field: moves.FieldId,
    authored: sequence_field.Changeset,
    base: sequence_field.Changeset,
  )
}

type InvertState {
  InvertState(
    aliases: sequence_field.AliasContext,
    move_context: moves.Context,
    watermark: Int,
    work: List(InvertWork),
    field_results: List(#(moves.FieldId, FieldChange)),
  )
}

type InvertWork {
  InvertWork(field: moves.FieldId, change: sequence_field.Changeset)
}

fn node_change(fields: List(#(String, FieldChange))) -> NodeChange {
  NodeChange(
    fields:,
    node_exists_constraint: None,
    node_exists_constraint_on_revert: None,
  )
}

pub fn empty() -> Changeset {
  Changeset(
    ChangeData(
      max_local_id: -1,
      revisions: [],
      fields: [],
      nodes: [],
      parents: [],
      aliases: [],
      builds: [],
      destroys: [],
      refreshers: [],
      cross_field_keys: [],
      constraint_violation_count: 0,
    ),
    IdentityOrder([]),
    [],
  )
}

pub fn resolve_constraint(
  visible: forest.Forest,
  path: FieldPath,
) -> Result(ConstraintTarget, TreeError) {
  use reference <- result.try(forest.locate(visible, path))
  use attached <- result.try(forest.is_attached(visible, reference))
  case attached {
    True -> Ok(ConstraintTarget(reference, path))
    False -> Error(InvalidEdit(path, "constraint node is detached"))
  }
}

pub fn add_node_exists_constraints(
  value: Changeset,
  visible: forest.Forest,
  targets: List(ConstraintTarget),
) -> Result(Changeset, TreeError) {
  list.try_fold(list.unique(targets), value, fn(value, target) {
    let ConstraintTarget(reference, path) = target
    use current <- result.try(forest.locate(visible, path))
    use attached <- result.try(forest.is_attached(visible, reference))
    use _ <- result.try(case attached && current == reference {
      True -> Ok(Nil)
      False -> Error(InvalidEdit(path, "constraint target changed"))
    })
    use steps <- result.try(forest.node_path(visible, path))
    use #(constraint, target_id) <- result.try(constraint_change(
      steps,
      value.data.max_local_id + 1,
      value.identity_order,
    ))
    use merged <- result.try(
      compose([
        TaggedChange(None, None, constraint),
        TaggedChange(None, None, value),
      ]),
    )
    use target_id <- result.try(resolve_alias(target_id, merged.data.aliases))
    use node <- result.try(node_for(target_id, merged.data.nodes))
    let nodes =
      put_pair(
        merged.data.nodes,
        target_id,
        NodeChange(
          ..node,
          node_exists_constraint: Some(NodeExistsConstraint(False)),
        ),
      )
    let data =
      ChangeData(
        ..merged.data,
        nodes: nodes,
        constraint_violation_count: constraint_violation_count(nodes),
      )
    use merged <- result.try(from_data(data, merged.identity_order))
    Ok(merged)
  })
}

fn constraint_change(
  steps: List(forest.FieldStep),
  next_id: Int,
  identity_order: IdentityOrder,
) -> Result(#(Changeset, AtomId), TreeError) {
  let assert [forest.FieldStep(root_field, root_index), ..rest] = steps
  use #(target, next_id) <- result.try(allocate_constraint_id(next_id))
  use #(top, nodes, parents, next_id) <- result.try(
    wrap_constraint_ancestors(
      list.reverse(rest),
      target,
      next_id,
      [
        #(
          target,
          NodeChange(
            fields: [],
            node_exists_constraint: Some(NodeExistsConstraint(False)),
            node_exists_constraint_on_revert: None,
          ),
        ),
      ],
      [],
    ),
  )
  let parents =
    list.append(parents, [
      #(top, ParentField(None, root_field)),
    ])
  use value <- result.try(from_data(
    ChangeData(
      ..empty().data,
      max_local_id: next_id - 1,
      fields: [#(root_field, GenericField([#(root_index, top)]))],
      nodes: nodes,
      parents: parents,
    ),
    identity_order,
  ))
  Ok(#(value, target))
}

fn wrap_constraint_ancestors(
  steps: List(forest.FieldStep),
  child: AtomId,
  next_id: Int,
  nodes: List(#(AtomId, NodeChange)),
  parents: List(#(AtomId, ParentField)),
) -> Result(
  #(AtomId, List(#(AtomId, NodeChange)), List(#(AtomId, ParentField)), Int),
  TreeError,
) {
  case steps {
    [] -> Ok(#(child, nodes, parents, next_id))
    [forest.FieldStep(field, index), ..rest] -> {
      use #(parent, next_id) <- result.try(allocate_constraint_id(next_id))
      wrap_constraint_ancestors(
        rest,
        parent,
        next_id,
        list.append(nodes, [
          #(parent, node_change([#(field, GenericField([#(index, child)]))])),
        ]),
        list.append(parents, [
          #(child, ParentField(Some(parent), field)),
        ]),
      )
    }
  }
}

fn allocate_constraint_id(next_id: Int) -> Result(#(AtomId, Int), TreeError) {
  case next_id >= 0 && next_id <= max_safe_integer {
    True -> Ok(#(AtomId(None, next_id), next_id + 1))
    False -> Error(CorruptData("constraint", "identifiers are exhausted"))
  }
}

fn constraint_violation_count(nodes: List(#(AtomId, NodeChange))) -> Int {
  list.count(nodes, fn(entry) {
    entry.1.node_exists_constraint == Some(NodeExistsConstraint(True))
  })
}

pub fn identity_order(
  entries: List(#(StableId, Int)),
) -> Result(IdentityOrder, TreeError) {
  use _ <- result.try(
    list.try_each(entries, fn(entry) {
      case entry.1 >= -max_safe_integer && entry.1 <= max_safe_integer {
        True -> Ok(Nil)
        False ->
          Error(InvalidHistory(
            "identity order key is outside the safe integer range",
          ))
      }
    }),
  )
  use _ <- result.try(unique_by(
    entries,
    fn(entry) { entry.0 },
    InvalidHistory("identity order contains a duplicate revision"),
  ))
  use _ <- result.try(unique_by(
    entries,
    fn(entry) { entry.1 },
    InvalidHistory("identity order contains a duplicate key"),
  ))
  Ok(IdentityOrder(entries))
}

pub fn from_data(
  data: ChangeData,
  identity_order: IdentityOrder,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_data(data))
  use _ <- result.try(validate_data_identity_order(data, identity_order))
  use data <- result.try(sort_atom_tables(data, identity_order))
  use derived <- result.try(derived_cross_field_keys(data, identity_order))
  use keys <- result.try(case data.cross_field_keys {
    [] -> Ok(derived)
    keys -> {
      use keys <- result.try(sort_cross_field_keys(keys, identity_order))
      use _ <- result.try(validate_owned_fields(keys, data))
      use _ <- result.try(validate_cross_field_ranges(keys))
      use _ <- result.try(validate_cross_field_ownership(
        keys,
        derived,
        data.aliases,
      ))
      Ok(keys)
    }
  })
  Ok(Changeset(ChangeData(..data, cross_field_keys: keys), identity_order, keys))
}

pub fn with_identity_order(
  change: Changeset,
  identity_order: IdentityOrder,
) -> Result(Changeset, TreeError) {
  use identity_order <- result.try(merge_identity_orders(
    change.identity_order,
    identity_order,
  ))
  use rebound <- result.try(from_data(change.data, identity_order))
  Ok(Changeset(..rebound, cross_field_keys: change.cross_field_keys))
}

pub fn rebind_identity_order(
  change: Changeset,
  identity_order: IdentityOrder,
  tagged_revisions: List(StableId),
) -> Result(Changeset, TreeError) {
  let IdentityOrder(entries) = identity_order
  let used = list.append(tagged_revisions, data_identity_revisions(change.data))
  let entries = list.filter(entries, fn(entry) { list.contains(used, entry.0) })
  use rebound <- result.try(from_data(change.data, IdentityOrder(entries)))
  Ok(Changeset(..rebound, cross_field_keys: change.cross_field_keys))
}

pub fn identity_revisions(change: Changeset) -> List(StableId) {
  let IdentityOrder(entries) = change.identity_order
  list.map(entries, fn(entry) { entry.0 })
}

fn data_identity_revisions(data: ChangeData) -> List(StableId) {
  let metadata =
    list.flat_map(data.revisions, fn(info) {
      case info.rollback_of {
        None -> [info.revision]
        Some(original) -> [info.revision, original]
      }
    })
  let fields =
    list.flat_map(data.fields, fn(entry) { field_identity_revisions(entry.1) })
  let nodes =
    list.flat_map(data.nodes, fn(entry) {
      let NodeChange(fields: fields, ..) = entry.1
      list.append(
        atom_identity_revisions(entry.0),
        list.flat_map(fields, fn(field) { field_identity_revisions(field.1) }),
      )
    })
  let parents =
    list.flat_map(data.parents, fn(entry) {
      let ParentField(parent, _) = entry.1
      list.append(atom_identity_revisions(entry.0), case parent {
        None -> []
        Some(parent) -> atom_identity_revisions(parent)
      })
    })
  let aliases =
    list.flat_map(data.aliases, fn(entry) {
      list.append(
        atom_identity_revisions(entry.0),
        atom_identity_revisions(entry.1),
      )
    })
  let builds =
    list.flat_map(list.append(data.builds, data.refreshers), fn(entry) {
      atom_identity_revisions(entry.id)
    })
  let destroys =
    list.flat_map(data.destroys, fn(entry) { atom_identity_revisions(entry.id) })
  let cross_field_keys =
    list.flat_map(data.cross_field_keys, fn(entry) {
      let moves.Key(_, revision, _) = entry.key
      list.append(
        case revision {
          None -> []
          Some(revision) -> [revision]
        },
        case entry.field.parent {
          None -> []
          Some(parent) -> atom_identity_revisions(parent)
        },
      )
    })
  list.unique(
    list.flatten([
      metadata,
      fields,
      nodes,
      parents,
      aliases,
      builds,
      destroys,
      cross_field_keys,
    ]),
  )
}

fn field_identity_revisions(field: FieldChange) -> List(StableId) {
  case field {
    GenericField(children) ->
      list.flat_map(children, fn(child) { atom_identity_revisions(child.1) })
    SequenceField(change) ->
      sequence_field.to_marks(change)
      |> list.flat_map(sequence_mark_identity_revisions)
    ValueField(change) | OptionalField(change) -> {
      let optional_field.FieldChange(moves, children, replacement) = change
      let moves =
        list.flat_map(moves, fn(move) {
          list.append(
            atom_identity_revisions(move.0),
            atom_identity_revisions(move.1),
          )
        })
      let children =
        list.flat_map(children, fn(child) {
          let source = case child.0 {
            optional_field.Active -> []
            optional_field.Detached(id) -> atom_identity_revisions(id)
          }
          list.append(source, atom_identity_revisions(child.1))
        })
      let replacement = case replacement {
        None -> []
        Some(optional_field.Replacement(_, source, detach)) -> {
          let source = case source {
            Some(optional_field.Detached(id)) -> atom_identity_revisions(id)
            _ -> []
          }
          list.append(source, atom_identity_revisions(detach))
        }
      }
      list.flatten([moves, children, replacement])
    }
  }
}

fn sequence_mark_identity_revisions(
  mark: sequence_field.Mark,
) -> List(StableId) {
  let effect = case mark.effect {
    sequence_field.Noop -> []
    sequence_field.Rename(id) -> atom_identity_revisions(id)
    sequence_field.Attach(attach) -> attach_identity_revisions(attach)
    sequence_field.Detach(detach) -> detach_identity_revisions(detach)
    sequence_field.AttachAndDetach(attach, detach) ->
      list.append(
        attach_identity_revisions(attach),
        detach_identity_revisions(detach),
      )
  }
  list.flatten([
    case mark.cell_id {
      None -> []
      Some(id) -> atom_identity_revisions(id)
    },
    effect,
    case mark.child {
      None -> []
      Some(id) -> atom_identity_revisions(id)
    },
  ])
}

fn attach_identity_revisions(attach: sequence_field.Attach) -> List(StableId) {
  case attach {
    sequence_field.Insert(id) -> atom_identity_revisions(id)
    sequence_field.MoveIn(id, endpoint) ->
      list.append(atom_identity_revisions(id), case endpoint {
        None -> []
        Some(id) -> atom_identity_revisions(id)
      })
  }
}

fn detach_identity_revisions(detach: sequence_field.Detach) -> List(StableId) {
  case detach {
    sequence_field.Remove(id, id_override) ->
      list.append(atom_identity_revisions(id), case id_override {
        None -> []
        Some(id) -> atom_identity_revisions(id)
      })
    sequence_field.MoveOut(id, endpoint, id_override) ->
      list.flatten([
        atom_identity_revisions(id),
        case endpoint {
          None -> []
          Some(id) -> atom_identity_revisions(id)
        },
        case id_override {
          None -> []
          Some(id) -> atom_identity_revisions(id)
        },
      ])
  }
}

fn atom_identity_revisions(atom: AtomId) -> List(StableId) {
  case atom.revision {
    None -> []
    Some(revision) -> [revision]
  }
}

pub fn to_data(change: Changeset) -> ChangeData {
  ChangeData(..change.data, cross_field_keys: change.cross_field_keys)
}

pub fn cross_field_keys(
  change: Changeset,
) -> Result(List(CrossFieldKey), TreeError) {
  Ok(change.cross_field_keys)
}

fn derived_cross_field_keys(
  data: ChangeData,
  identity_order: IdentityOrder,
) -> Result(List(CrossFieldKey), TreeError) {
  sorted_derived_cross_field_keys(data, identity_order)
}

fn sorted_derived_cross_field_keys(
  data: ChangeData,
  identity_order: IdentityOrder,
) -> Result(List(CrossFieldKey), TreeError) {
  use root <- result.try(cross_field_keys_from_fields(data.fields, None))
  use nested <- result.try(
    list.try_fold(data.nodes, [], fn(keys, entry) {
      let NodeChange(fields: fields, ..) = entry.1
      use found <- result.try(cross_field_keys_from_fields(
        fields,
        Some(entry.0),
      ))
      Ok(list.append(keys, found))
    }),
  )
  sort_cross_field_keys(list.append(root, nested), identity_order)
}

fn coalesce_cross_field_keys(keys: List(CrossFieldKey)) -> List(CrossFieldKey) {
  case keys {
    [] -> []
    [first] -> [first]
    [first, second, ..rest] -> {
      let CrossFieldKey(first_key, first_count, first_field) = first
      let CrossFieldKey(second_key, second_count, second_field) = second
      let moves.Key(first_side, first_revision, first_local_id) = first_key
      let moves.Key(second_side, second_revision, second_local_id) = second_key
      case
        first_side == second_side
        && first_revision == second_revision
        && first_field == second_field
        && first_local_id + first_count == second_local_id
      {
        True ->
          coalesce_cross_field_keys([
            CrossFieldKey(first_key, first_count + second_count, first_field),
            ..rest
          ])
        False -> [first, ..coalesce_cross_field_keys([second, ..rest])]
      }
    }
  }
}

fn validate_cross_field_ownership(
  keys: List(CrossFieldKey),
  derived: List(CrossFieldKey),
  aliases: List(#(AtomId, AtomId)),
) -> Result(Nil, TreeError) {
  use _ <- result.try(
    list.try_each(keys, fn(entry) {
      check(
        entry.count > 0
          && entry.key.local_id >= 0
          && entry.count - 1 <= max_safe_integer - entry.key.local_id,
        "cross-field ownership",
        "owned range is outside the safe integer range",
      )
    }),
  )
  list.try_each(derived, fn(required) {
    check(
      list.any(keys, fn(actual) {
        cross_field_key_contains(actual, required, aliases)
      }),
      "cross-field ownership",
      "owned ranges do not cover the sequence fields",
    )
  })
}

fn validate_owned_fields(
  keys: List(CrossFieldKey),
  data: ChangeData,
) -> Result(Nil, TreeError) {
  list.try_each(keys, fn(entry) {
    let field = canonical_field(entry.field, data.aliases)
    let fields = case field.parent {
      None -> Ok(data.fields)
      Some(parent) -> {
        use node <- result.try(node_for(parent, data.nodes))
        let NodeChange(fields: fields, ..) = node
        Ok(fields)
      }
    }
    use fields <- result.try(fields)
    case pair_value(fields, field.field) {
      Some(SequenceField(_)) -> Ok(Nil)
      Some(_) ->
        Error(CorruptData(
          "cross-field ownership",
          "owned field is not a sequence",
        ))
      None ->
        Error(CorruptData("cross-field ownership", "owned field is missing"))
    }
  })
}

fn validate_cross_field_ranges(
  keys: List(CrossFieldKey),
) -> Result(Nil, TreeError) {
  case keys {
    [] | [_] -> Ok(Nil)
    [first, second, ..rest] -> {
      let moves.Key(first_side, first_revision, first_start) = first.key
      let moves.Key(second_side, second_revision, second_start) = second.key
      use _ <- result.try(check(
        first_side != second_side
          || first_revision != second_revision
          || first_start + first.count <= second_start,
        "cross-field ownership",
        "owned ranges overlap",
      ))
      validate_cross_field_ranges([second, ..rest])
    }
  }
}

fn canonical_field(
  field: moves.FieldId,
  aliases: List(#(AtomId, AtomId)),
) -> moves.FieldId {
  moves.FieldId(
    option.map(field.parent, canonical_atom(_, aliases)),
    field.field,
  )
}

fn canonical_atom(id: AtomId, aliases: List(#(AtomId, AtomId))) -> AtomId {
  case pair_value(aliases, id) {
    None -> id
    Some(next) -> canonical_atom(next, aliases)
  }
}

fn cross_field_key_contains(
  outer: CrossFieldKey,
  inner: CrossFieldKey,
  aliases: List(#(AtomId, AtomId)),
) -> Bool {
  outer.key.side == inner.key.side
  && outer.key.revision == inner.key.revision
  && canonical_field(outer.field, aliases)
  == canonical_field(inner.field, aliases)
  && outer.key.local_id <= inner.key.local_id
  && outer.key.local_id + outer.count >= inner.key.local_id + inner.count
}

fn cross_field_keys_from_fields(
  fields: List(#(String, FieldChange)),
  parent: Option(AtomId),
) -> Result(List(CrossFieldKey), TreeError) {
  list.try_fold(fields, [], fn(keys, entry) {
    case entry.1 {
      SequenceField(change) ->
        Ok(list.append(
          keys,
          sequence_field.to_marks(change)
            |> list.flat_map(fn(mark) {
              sequence_effect_keys(
                mark.effect,
                mark.count,
                moves.FieldId(parent, entry.0),
              )
            }),
        ))
      _ -> Ok(keys)
    }
  })
}

fn sequence_effect_keys(
  effect: sequence_field.Effect,
  count: Int,
  field: moves.FieldId,
) -> List(CrossFieldKey) {
  case effect {
    sequence_field.Noop
    | sequence_field.Rename(_)
    | sequence_field.Attach(sequence_field.Insert(_)) -> []
    sequence_field.Attach(sequence_field.MoveIn(id, _)) -> [
      CrossFieldKey(
        moves.Key(moves.Destination, id.revision, id.local_id),
        count,
        field,
      ),
    ]
    sequence_field.Detach(sequence_field.MoveOut(id, _, _)) -> [
      CrossFieldKey(
        moves.Key(moves.Source, id.revision, id.local_id),
        count,
        field,
      ),
    ]
    sequence_field.AttachAndDetach(attach, detach) ->
      list.append(
        sequence_effect_keys(sequence_field.Attach(attach), count, field),
        sequence_effect_keys(sequence_field.Detach(detach), count, field),
      )
    // ponytail: Match all variants. This catch-all also takes any new
    // sequence_field Effect, Attach, or Detach variant without a compiler
    // error. Name the remaining variants.
    _ -> []
  }
}

/// Return the ownership ranges that the Sequence codec registers for a field.
pub fn sequence_codec_keys(
  value: sequence_field.Changeset,
  parent: Option(AtomId),
  field: String,
) -> List(CrossFieldKey) {
  sequence_field.to_marks(value)
  |> list.flat_map(fn(mark) {
    sequence_codec_effect_keys(
      mark.effect,
      mark.count,
      moves.FieldId(parent, field),
    )
  })
}

fn sequence_codec_effect_keys(
  effect: sequence_field.Effect,
  count: Int,
  field: moves.FieldId,
) -> List(CrossFieldKey) {
  case effect {
    sequence_field.Noop | sequence_field.Rename(_) -> []
    sequence_field.Attach(sequence_field.Insert(id)) -> [
      CrossFieldKey(
        moves.Key(moves.Source, id.revision, id.local_id),
        count,
        field,
      ),
      CrossFieldKey(
        moves.Key(moves.Destination, id.revision, id.local_id),
        count,
        field,
      ),
    ]
    sequence_field.Attach(sequence_field.MoveIn(id, _)) -> [
      CrossFieldKey(
        moves.Key(moves.Destination, id.revision, id.local_id),
        count,
        field,
      ),
    ]
    sequence_field.Detach(sequence_field.MoveOut(id, _, _)) -> [
      CrossFieldKey(
        moves.Key(moves.Source, id.revision, id.local_id),
        count,
        field,
      ),
    ]
    sequence_field.AttachAndDetach(attach, detach) ->
      list.append(
        sequence_codec_effect_keys(sequence_field.Attach(attach), count, field),
        sequence_codec_effect_keys(sequence_field.Detach(detach), count, field),
      )
    // ponytail: Match all variants. This catch-all also takes any new
    // sequence_field Effect, Attach, or Detach variant without a compiler
    // error. Name the remaining variants.
    _ -> []
  }
}

fn sort_cross_field_keys(
  keys: List(CrossFieldKey),
  identity_order: IdentityOrder,
) -> Result(List(CrossFieldKey), TreeError) {
  list.try_fold(keys, [], fn(sorted, key) {
    insert_cross_field_key(key, sorted, identity_order)
  })
}

fn insert_cross_field_key(
  key: CrossFieldKey,
  keys: List(CrossFieldKey),
  identity_order: IdentityOrder,
) -> Result(List(CrossFieldKey), TreeError) {
  case keys {
    [] -> Ok([key])
    [first, ..rest] -> {
      use compared <- result.try(compare_move_keys(
        key.key,
        first.key,
        identity_order,
      ))
      case compared {
        order.Lt | order.Eq -> Ok([key, ..keys])
        order.Gt -> {
          use rest <- result.try(insert_cross_field_key(
            key,
            rest,
            identity_order,
          ))
          Ok([first, ..rest])
        }
      }
    }
  }
}

fn compare_move_keys(
  left: moves.Key,
  right: moves.Key,
  identity_order: IdentityOrder,
) -> Result(order.Order, TreeError) {
  case left.side, right.side {
    moves.Source, moves.Destination -> Ok(order.Lt)
    moves.Destination, moves.Source -> Ok(order.Gt)
    // ponytail: Match all variants. This catch-all also takes any new
    // moves.Side variant without a compiler error. Name the remaining variants.
    // Match Source, Source and Destination, Destination.
    _, _ ->
      compare_atom(
        AtomId(left.revision, left.local_id),
        AtomId(right.revision, right.local_id),
        identity_order,
      )
  }
}

pub fn revision_infos(change: TaggedChange) -> List(RevisionInfo) {
  tagged_revision_infos(change)
}

pub fn materialize_revision_metadata(
  change: TaggedChange,
) -> Result(Changeset, TreeError) {
  let #(revisions, _) = composition_metadata([change])
  case revisions == change.change.data.revisions {
    True -> Ok(change.change)
    False ->
      from_data(
        ChangeData(..change.change.data, revisions:),
        change.change.identity_order,
      )
  }
}

pub fn max_local_id(change: Changeset) -> Int {
  change.data.max_local_id
}

pub fn rebase_context(
  revisions: List(RevisionInfo),
) -> Result(RebaseContext, TreeError) {
  use _ <- result.try(validate_revisions(revisions))
  Ok(RebaseContext(revisions))
}

fn algebra_context(
  identity_order: IdentityOrder,
  revisions: List(RevisionInfo),
) -> sequence_field.AlgebraContext {
  sequence_field.AlgebraContext(
    compare_atoms: fn(left, right) { compare_atom(left, right, identity_order) },
    revision_index: fn(revision) {
      Ok(revision_position(revisions, revision, 0))
    },
    rollback_of: fn(revision) {
      Ok(
        revision_info(revisions, revision)
        |> option.map(fn(info) { info.rollback_of })
        |> option.flatten,
      )
    },
  )
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn revision_position(
  revisions: List(RevisionInfo),
  revision: StableId,
  index: Int,
) -> Option(Int) {
  case revisions {
    [] -> None
    [info, ..rest] ->
      case info.revision == revision {
        True -> Some(index)
        False -> revision_position(rest, revision, index + 1)
      }
  }
}

pub fn edit(
  schema: StoredSchema,
  forest: forest.Forest,
  revision: StableId,
  operation: Edit,
  identity_order: IdentityOrder,
) -> Result(Changeset, TreeError) {
  edit_from(schema, forest, revision, operation, identity_order, 0)
}

pub fn edit_from(
  schema: StoredSchema,
  forest: forest.Forest,
  revision: StableId,
  operation: Edit,
  identity_order: IdentityOrder,
  first_local_id: Int,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(require_identity_revision(identity_order, revision))
  use _ <- result.try(check(
    first_local_id >= 0 && first_local_id <= max_safe_integer,
    "change allocator",
    "invalid next identifier",
  ))
  case operation {
    ArrayInsert(path, index, values) ->
      author_array_insert(
        schema,
        forest,
        revision,
        path,
        index,
        values,
        identity_order,
        first_local_id,
      )
    ArrayRemove(path, start, end) ->
      author_array_remove(
        schema,
        forest,
        revision,
        path,
        start,
        end,
        identity_order,
        first_local_id,
      )
    ArrayMove(
      source_path,
      source_start,
      source_end,
      destination_path,
      destination_gap,
    ) ->
      author_array_move(
        schema,
        forest,
        revision,
        source_path,
        source_start,
        source_end,
        destination_path,
        destination_gap,
        identity_order,
        first_local_id,
      )
    // ponytail: Match all variants. This catch-all also takes any new Edit
    // variant without a compiler error. Name the remaining variants.
    _ ->
      author_scalar_edit(
        schema,
        forest,
        revision,
        operation,
        identity_order,
        first_local_id,
      )
  }
}

fn author_scalar_edit(
  schema: StoredSchema,
  forest: forest.Forest,
  revision: StableId,
  operation: Edit,
  identity_order: IdentityOrder,
  first_local_id: Int,
) -> Result(Changeset, TreeError) {
  use #(field_schema, parent_path, field, was_empty, value, is_root) <- result.try(
    operation_destination(schema, forest, operation),
  )
  let FieldSchema(cardinality, _) = field_schema
  use #(field_change, builds, next_id) <- result.try(authored_field(
    cardinality,
    was_empty,
    value,
    revision,
    first_local_id,
  ))
  use parent_steps <- result.try(case is_root {
    True -> Ok([])
    False -> forest.node_path(forest, parent_path)
  })
  use #(fields, nodes, parents, max_local_id) <- result.try(wrap_ancestors(
    parent_steps,
    field,
    field_change,
    revision,
    next_id,
  ))
  from_data(
    ChangeData(
      max_local_id: max_local_id,
      revisions: [RevisionInfo(revision, None)],
      fields: fields,
      nodes: nodes,
      parents: parents,
      aliases: [],
      builds: builds,
      destroys: [],
      refreshers: [],
      cross_field_keys: [],
      constraint_violation_count: 0,
    ),
    identity_order,
  )
}

pub fn validate_edit(
  schema: StoredSchema,
  forest: forest.Forest,
  operation: Edit,
) -> Result(Nil, TreeError) {
  use _ <- result.try(case operation {
    ArrayInsert(path, index, values) ->
      validate_array_insert(schema, forest, path, index, values)
    ArrayRemove(path, start, end) ->
      validate_array_remove(forest, path, start, end)
    ArrayMove(
      source_path,
      source_start,
      source_end,
      destination_path,
      destination_gap,
    ) ->
      validate_array_move(
        schema,
        forest,
        source_path,
        source_start,
        source_end,
        destination_path,
        destination_gap,
      )
    // ponytail: Match all variants. This catch-all also takes any new Edit
    // variant without a compiler error. Name the remaining variants.
    _ ->
      operation_destination(schema, forest, operation)
      |> result.map(fn(_) { Nil })
  })
  Ok(Nil)
}

fn operation_destination(
  schema: StoredSchema,
  forest: forest.Forest,
  operation: Edit,
) -> Result(
  #(FieldSchema, FieldPath, String, Bool, Option(TreeValue), Bool),
  TreeError,
) {
  case operation {
    SetField(path, value) -> {
      use #(field_schema, parent_path, field, was_empty) <- result.try(
        edit_destination(schema, forest, path, Some(value)),
      )
      Ok(#(
        field_schema,
        parent_path,
        field,
        was_empty,
        Some(value),
        list.is_empty(path),
      ))
    }
    ClearField(path) -> {
      use #(field_schema, parent_path, field, was_empty) <- result.try(
        edit_destination(schema, forest, path, None),
      )
      Ok(#(
        field_schema,
        parent_path,
        field,
        was_empty,
        None,
        list.is_empty(path),
      ))
    }
    MapSet(path, key, value) -> {
      use #(field_schema, parent_path, field, was_empty) <- result.try(
        map_edit_destination(schema, forest, path, key, Some(value)),
      )
      Ok(#(field_schema, parent_path, field, was_empty, Some(value), False))
    }
    MapDelete(path, key) -> {
      use #(field_schema, parent_path, field, was_empty) <- result.try(
        map_edit_destination(schema, forest, path, key, None),
      )
      Ok(#(field_schema, parent_path, field, was_empty, None, False))
    }
    ArrayInsert(_, _, _) | ArrayRemove(_, _, _) | ArrayMove(_, _, _, _, _) ->
      Error(types.UnsupportedFeature(
        "field edit",
        "array operations are not authored by scalar dispatch",
      ))
  }
}

fn validate_array_insert(
  stored: StoredSchema,
  visible: forest.Forest,
  path: FieldPath,
  index: Int,
  values: List(TreeValue),
) -> Result(Nil, TreeError) {
  use array_type <- result.try(forest.array_type(visible, path))
  use current <- result.try(forest.array_values(visible, path))
  use _ <- result.try(validate_gap(path, index, list.length(current)))
  schema.validate_array_elements(stored, array_type, values)
}

fn validate_array_remove(
  visible: forest.Forest,
  path: FieldPath,
  start: Int,
  end: Int,
) -> Result(Nil, TreeError) {
  use current <- result.try(forest.array_values(visible, path))
  validate_half_open_range(path, start, end, list.length(current))
}

fn validate_array_move(
  stored: StoredSchema,
  visible: forest.Forest,
  source_path: FieldPath,
  source_start: Int,
  source_end: Int,
  destination_path: FieldPath,
  destination_gap: Int,
) -> Result(Nil, TreeError) {
  use source <- result.try(forest.array_values(visible, source_path))
  use _ <- result.try(validate_half_open_range(
    source_path,
    source_start,
    source_end,
    list.length(source),
  ))
  use destination <- result.try(forest.array_values(visible, destination_path))
  use _ <- result.try(validate_gap(
    destination_path,
    destination_gap,
    list.length(destination),
  ))
  let moved =
    source |> list.drop(source_start) |> list.take(source_end - source_start)
  use destination_type <- result.try(forest.array_type(
    visible,
    destination_path,
  ))
  use _ <- result.try(schema.validate_array_elements(
    stored,
    destination_type,
    moved,
  ))
  case source_path == destination_path {
    True -> Ok(Nil)
    False -> {
      use source_steps <- result.try(forest.node_path(visible, source_path))
      use destination_steps <- result.try(forest.node_path(
        visible,
        destination_path,
      ))
      reject_move_cycle(
        source_path,
        source_steps,
        source_start,
        source_end,
        destination_steps,
      )
    }
  }
}

// ponytail: Annotate all module functions. Add the return type Result(Nil,
// TreeError).
fn validate_gap(path: FieldPath, index: Int, length: Int) {
  case index >= 0 && index <= max_safe_integer && index <= length {
    True -> Ok(Nil)
    False -> Error(InvalidEdit(path, "array gap is outside the valid range"))
  }
}

// ponytail: Annotate all module functions. Add the return type Result(Nil,
// TreeError).
fn validate_half_open_range(
  path: FieldPath,
  start: Int,
  end: Int,
  length: Int,
) {
  case
    start >= 0
    && start <= max_safe_integer
    && end >= start
    && end <= max_safe_integer
    && end <= length
  {
    True -> Ok(Nil)
    False -> Error(InvalidEdit(path, "array range is outside the valid range"))
  }
}

fn author_array_insert(
  stored: StoredSchema,
  visible: forest.Forest,
  revision: StableId,
  path: FieldPath,
  index: Int,
  values: List(TreeValue),
  identity_order: IdentityOrder,
  first_local_id: Int,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_array_insert(
    stored,
    visible,
    path,
    index,
    values,
  ))
  let count = list.length(values)
  use #(first, next_id) <- result.try(allocate_range(
    revision,
    first_local_id,
    count,
  ))
  use field <- result.try(sequence_field.insert(
    index,
    count,
    first,
    Some(revision),
  ))
  author_array_field(
    visible,
    path,
    SequenceField(field),
    revision,
    next_id,
    case values {
      [] -> []
      _ -> [forest.Build(first, values)]
    },
    identity_order,
  )
}

fn author_array_remove(
  _stored: StoredSchema,
  visible: forest.Forest,
  revision: StableId,
  path: FieldPath,
  start: Int,
  end: Int,
  identity_order: IdentityOrder,
  first_local_id: Int,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_array_remove(visible, path, start, end))
  let count = end - start
  use #(first, next_id) <- result.try(allocate_range(
    revision,
    first_local_id,
    count,
  ))
  use field <- result.try(sequence_field.remove(start, count, first))
  author_array_field(
    visible,
    path,
    SequenceField(field),
    revision,
    next_id,
    [],
    identity_order,
  )
}

fn author_array_move(
  stored: StoredSchema,
  visible: forest.Forest,
  revision: StableId,
  source_path: FieldPath,
  source_start: Int,
  source_end: Int,
  destination_path: FieldPath,
  destination_gap: Int,
  identity_order: IdentityOrder,
  first_local_id: Int,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_array_move(
    stored,
    visible,
    source_path,
    source_start,
    source_end,
    destination_path,
    destination_gap,
  ))
  let count = source_end - source_start
  case source_path == destination_path {
    False -> {
      use source_steps <- result.try(forest.node_path(visible, source_path))
      use destination_steps <- result.try(forest.node_path(
        visible,
        destination_path,
      ))
      use _ <- result.try(reject_move_cycle(
        source_path,
        source_steps,
        source_start,
        source_end,
        destination_steps,
      ))
      use #(detach, next_id) <- result.try(allocate_range(
        revision,
        first_local_id,
        count,
      ))
      use #(attach, next_id) <- result.try(allocate_range(
        revision,
        next_id,
        count,
      ))
      use source <- result.try(sequence_field.move_out(
        source_start,
        count,
        detach,
      ))
      use destination <- result.try(sequence_field.move_in(
        destination_gap,
        count,
        detach,
        attach,
      ))
      author_cross_array_fields(
        source_steps,
        SequenceField(source),
        destination_steps,
        SequenceField(destination),
        revision,
        next_id,
        identity_order,
      )
    }
    True -> {
      use #(detach, next_id) <- result.try(allocate_range(
        revision,
        first_local_id,
        count,
      ))
      use #(attach, next_id) <- result.try(allocate_range(
        revision,
        next_id,
        count,
      ))
      use field <- result.try(sequence_field.move(
        source_start,
        count,
        destination_gap,
        detach,
        attach,
      ))
      author_array_field(
        visible,
        source_path,
        SequenceField(field),
        revision,
        next_id,
        [],
        identity_order,
      )
    }
  }
}

fn reject_move_cycle(
  source_path: FieldPath,
  source_steps: List(forest.FieldStep),
  source_start: Int,
  source_end: Int,
  destination_steps: List(forest.FieldStep),
) -> Result(Nil, TreeError) {
  case drop_step_prefix(destination_steps, source_steps) {
    Some([forest.FieldStep("", index), ..])
      if index >= source_start && index < source_end
    ->
      Error(InvalidEdit(source_path, "move destination is inside moved content"))
    _ -> Ok(Nil)
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn drop_step_prefix(
  steps: List(forest.FieldStep),
  prefix: List(forest.FieldStep),
) -> Option(List(forest.FieldStep)) {
  case steps, prefix {
    _, [] -> Some(steps)
    [step, ..steps], [expected, ..prefix] if step == expected ->
      drop_step_prefix(steps, prefix)
    _, _ -> None
  }
}

fn author_cross_array_fields(
  source_steps: List(forest.FieldStep),
  source: FieldChange,
  destination_steps: List(forest.FieldStep),
  destination: FieldChange,
  revision: StableId,
  next_id: Int,
  identity_order: IdentityOrder,
) -> Result(Changeset, TreeError) {
  let #(common, source_rest, destination_rest) =
    split_common_steps(source_steps, destination_steps, [])
  case source_rest, destination_rest {
    [], [] ->
      Error(CorruptData("array move", "distinct array paths resolved equally"))
    [_source, ..], [] ->
      author_ancestor_array_fields(
        common,
        destination,
        source_rest,
        source,
        revision,
        next_id,
        identity_order,
      )
    [], [_destination, ..] ->
      author_ancestor_array_fields(
        common,
        source,
        destination_rest,
        destination,
        revision,
        next_id,
        identity_order,
      )
    _, _ ->
      author_sibling_array_fields(
        common,
        source_rest,
        source,
        destination_rest,
        destination,
        revision,
        next_id,
        identity_order,
      )
  }
}

fn author_sibling_array_fields(
  common: List(forest.FieldStep),
  first_steps: List(forest.FieldStep),
  first: FieldChange,
  second_steps: List(forest.FieldStep),
  second: FieldChange,
  revision: StableId,
  next_id: Int,
  identity_order: IdentityOrder,
) -> Result(Changeset, TreeError) {
  use first_branch <- result.try(build_branch(
    first_steps,
    "",
    first,
    revision,
    next_id,
  ))
  use second_branch <- result.try(build_branch(
    second_steps,
    "",
    second,
    revision,
    first_branch.next_id,
  ))
  use branch_fields <- result.try(merge_branch_fields(
    first_branch,
    second_branch,
  ))
  use #(common_id, next_id) <- result.try(allocate(
    revision,
    second_branch.next_id,
  ))
  let nodes =
    list.flatten([
      first_branch.nodes,
      second_branch.nodes,
      [#(common_id, node_change(branch_fields))],
    ])
  let parents =
    list.flatten([
      first_branch.parents,
      second_branch.parents,
      [
        #(first_branch.top, ParentField(Some(common_id), first_branch.field)),
        #(second_branch.top, ParentField(Some(common_id), second_branch.field)),
      ],
    ])
  finish_cross_array_graph(
    common,
    common_id,
    nodes,
    parents,
    revision,
    next_id,
    identity_order,
  )
}

fn author_ancestor_array_fields(
  common: List(forest.FieldStep),
  direct: FieldChange,
  descendant_steps: List(forest.FieldStep),
  descendant: FieldChange,
  revision: StableId,
  next_id: Int,
  identity_order: IdentityOrder,
) -> Result(Changeset, TreeError) {
  use branch <- result.try(build_branch(
    descendant_steps,
    "",
    descendant,
    revision,
    next_id,
  ))
  use direct <- result.try(case direct {
    SequenceField(sequence) if branch.field == "" ->
      sequence_with_child(sequence, branch.index, branch.top)
      |> result.map(SequenceField)
    _ ->
      Error(CorruptData(
        "array move",
        "ancestor array branch is not a sequence child",
      ))
  })
  use #(common_id, next_id) <- result.try(allocate(revision, branch.next_id))
  finish_cross_array_graph(
    common,
    common_id,
    list.append(branch.nodes, [#(common_id, node_change([#("", direct)]))]),
    list.append(branch.parents, [
      #(branch.top, ParentField(Some(common_id), "")),
    ]),
    revision,
    next_id,
    identity_order,
  )
}

fn finish_cross_array_graph(
  common: List(forest.FieldStep),
  common_id: AtomId,
  nodes: List(#(AtomId, NodeChange)),
  parents: List(#(AtomId, ParentField)),
  revision: StableId,
  next_id: Int,
  identity_order: IdentityOrder,
) -> Result(Changeset, TreeError) {
  use #(top, nodes, parents, next_id) <- result.try(wrap_parent_fields(
    list.reverse(common),
    common_id,
    revision,
    next_id,
    nodes,
    parents,
  ))
  // ponytail: Panicking in libraries. This let assert can panic. Match the
  // value and return a TreeError for [].
  let assert [forest.FieldStep(root_field, root_index), ..] = common
  from_data(
    ChangeData(
      max_local_id: next_id - 1,
      revisions: [RevisionInfo(revision, None)],
      fields: [#(root_field, GenericField([#(root_index, top)]))],
      nodes: nodes,
      parents: list.append(parents, [
        #(top, ParentField(None, root_field)),
      ]),
      aliases: [],
      builds: [],
      destroys: [],
      refreshers: [],
      cross_field_keys: [],
      constraint_violation_count: 0,
    ),
    identity_order,
  )
}

fn sequence_with_child(
  change: sequence_field.Changeset,
  index: Int,
  child: AtomId,
) -> Result(sequence_field.Changeset, TreeError) {
  use marks <- result.try(
    add_sequence_child(sequence_field.to_marks(change), index, 0, child, []),
  )
  sequence_field.from_marks(marks)
}

fn add_sequence_child(
  marks: List(sequence_field.Mark),
  index: Int,
  position: Int,
  child: AtomId,
  output: List(sequence_field.Mark),
) -> Result(List(sequence_field.Mark), TreeError) {
  case marks {
    [] -> {
      let output = case index - position {
        0 -> output
        gap -> [
          sequence_field.Mark(gap, None, sequence_field.Noop, None),
          ..output
        ]
      }
      Ok(
        list.reverse([
          sequence_field.Mark(1, None, sequence_field.Noop, Some(child)),
          ..output
        ]),
      )
    }
    [mark, ..rest] -> {
      let length = sequence_field.input_length(mark)
      case length == 0 || index >= position + length {
        True ->
          add_sequence_child(rest, index, position + length, child, [
            mark,
            ..output
          ])
        False ->
          case mark.effect, mark.cell_id, mark.child {
            sequence_field.Noop, None, None -> {
              let before = index - position
              let after = length - before - 1
              let output = case before {
                0 -> output
                _ -> [
                  sequence_field.Mark(before, None, sequence_field.Noop, None),
                  ..output
                ]
              }
              let output = [
                sequence_field.Mark(1, None, sequence_field.Noop, Some(child)),
                ..output
              ]
              let output = case after {
                0 -> output
                _ -> [
                  sequence_field.Mark(after, None, sequence_field.Noop, None),
                  ..output
                ]
              }
              Ok(list.append(list.reverse(output), rest))
            }
            _, _, _ ->
              Error(CorruptData(
                "array move",
                "ancestor child overlaps an effectful sequence mark",
              ))
          }
      }
    }
  }
}

fn split_common_steps(
  left: List(forest.FieldStep),
  right: List(forest.FieldStep),
  common: List(forest.FieldStep),
) -> #(List(forest.FieldStep), List(forest.FieldStep), List(forest.FieldStep)) {
  case left, right {
    [left_step, ..left], [right_step, ..right] if left_step == right_step ->
      split_common_steps(left, right, [left_step, ..common])
    _, _ -> #(list.reverse(common), left, right)
  }
}

fn build_branch(
  steps: List(forest.FieldStep),
  field: String,
  field_change: FieldChange,
  revision: StableId,
  next_id: Int,
) -> Result(Branch, TreeError) {
  // ponytail: Check-then-assert. The caller proves that both paths are not
  // empty, then this line asserts it again. Pass the matched head step to this
  // function.
  let assert [forest.FieldStep(branch_field, branch_index), ..] = steps
  use #(leaf, next_id) <- result.try(allocate(revision, next_id))
  use #(top, nodes, parents, next_id) <- result.try(
    wrap_parent_fields(
      list.reverse(steps),
      leaf,
      revision,
      next_id,
      [#(leaf, node_change([#(field, field_change)]))],
      [],
    ),
  )
  Ok(Branch(branch_field, branch_index, top, nodes, parents, next_id))
}

fn merge_branch_fields(
  first: Branch,
  second: Branch,
) -> Result(List(#(String, FieldChange)), TreeError) {
  case first.field == second.field {
    False ->
      Ok([
        #(first.field, GenericField([#(first.index, first.top)])),
        #(second.field, GenericField([#(second.index, second.top)])),
      ])
    True ->
      case first.index == second.index {
        True ->
          Error(CorruptData("array move", "divergent paths have the same child"))
        False ->
          Ok([
            #(
              first.field,
              GenericField([
                #(first.index, first.top),
                #(second.index, second.top),
              ]),
            ),
          ])
      }
  }
}

fn author_array_field(
  visible: forest.Forest,
  path: FieldPath,
  field_change: FieldChange,
  revision: StableId,
  next_id: Int,
  builds: List(forest.Build),
  identity_order: IdentityOrder,
) -> Result(Changeset, TreeError) {
  use steps <- result.try(forest.node_path(visible, path))
  use #(fields, nodes, parents, max_local_id) <- result.try(wrap_ancestors(
    steps,
    "",
    field_change,
    revision,
    next_id,
  ))
  from_data(
    ChangeData(
      max_local_id: max_local_id,
      revisions: [RevisionInfo(revision, None)],
      fields: fields,
      nodes: nodes,
      parents: parents,
      aliases: [],
      builds: builds,
      destroys: [],
      refreshers: [],
      cross_field_keys: [],
      constraint_violation_count: 0,
    ),
    identity_order,
  )
}

pub fn into_delta(change: TaggedChange) -> Result(forest.Delta, TreeError) {
  let data = change.change.data
  use parts <- result.try(case data.constraint_violation_count > 0 {
    True -> Ok(DeltaParts([], [], []))
    False -> delta_fields(data.fields, data)
  })
  forest.delta(forest.DeltaData(
    latest_revision: change.revision,
    fields: parts.fields,
    build: data.builds,
    refreshers: data.refreshers,
    global: parts.global,
    rename: parts.rename,
    destroy: data.destroys,
  ))
}

pub fn compose(changes: List(TaggedChange)) -> Result(Changeset, TreeError) {
  compose_with_trace(changes) |> result.map(fn(output) { output.0 })
}

pub fn compose_with_trace(
  changes: List(TaggedChange),
) -> Result(#(Changeset, List(moves.TraceEvent)), TreeError) {
  let #(revisions, max_local_id) = composition_metadata(changes)
  use changes <- result.try(bind_composition_identity_order(changes))
  use #(composed, trace) <- result.try(balanced_compose(
    list.map(changes, fn(change) { change.change }),
    revisions,
    max_local_id,
  ))
  let cross_field_keys = composed.cross_field_keys
  use composed <- result.try(from_data(
    ChangeData(
      ..composed.data,
      max_local_id: max_local_id,
      revisions: revisions,
    ),
    composed.identity_order,
  ))
  let composed = Changeset(..composed, cross_field_keys:)
  Ok(#(composed, trace))
}

fn bind_composition_identity_order(
  changes: List(TaggedChange),
) -> Result(List(TaggedChange), TreeError) {
  case changes {
    [] -> Ok([])
    [first, ..rest] -> {
      use identity_order <- result.try(
        list.try_fold(rest, first.change.identity_order, fn(order, tagged) {
          merge_identity_orders(order, tagged.change.identity_order)
        }),
      )
      list.try_map(changes, fn(tagged) {
        use checked <- result.try(from_data(tagged.change.data, identity_order))
        Ok(TaggedChange(..tagged, change: checked))
      })
    }
  }
}

pub fn replace_revisions(
  change: Changeset,
  obsolete: List(Option(StableId)),
  updated: StableId,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(unique_by(
    obsolete,
    fn(revision) { revision },
    InvalidHistory("duplicate obsolete revision"),
  ))
  use state <- result.try(collect_replacements(
    change.data,
    ReplaceState(obsolete, updated, [], [], -1),
  ))
  use fields <- result.try(replace_field_map(change.data.fields, state))
  use nodes <- result.try(
    list.try_map(change.data.nodes, fn(entry) {
      use id <- result.try(replaced_atom(entry.0, state))
      let NodeChange(fields: fields, ..) = entry.1
      use fields <- result.try(replace_field_map(fields, state))
      Ok(#(id, NodeChange(..entry.1, fields:)))
    }),
  )
  use parents <- result.try(
    list.try_map(change.data.parents, fn(entry) {
      use id <- result.try(replaced_atom(entry.0, state))
      use parent <- result.try(normalize_parent(entry.1, change.data.aliases))
      let ParentField(parent_id, field) = parent
      use parent_id <- result.try(case parent_id {
        None -> Ok(None)
        Some(parent_id) -> replaced_atom(parent_id, state) |> result.map(Some)
      })
      Ok(#(id, ParentField(parent_id, field)))
    }),
  )
  use builds <- result.try(replace_builds(change.data.builds, state))
  use destroys <- result.try(
    list.try_map(change.data.destroys, fn(destroy) {
      use id <- result.try(replaced_atom(destroy.id, state))
      Ok(forest.Destroy(id, destroy.count))
    }),
  )
  use refreshers <- result.try(replace_builds(change.data.refreshers, state))
  use cross_field_keys <- result.try(replace_cross_field_keys(
    change.cross_field_keys,
    state,
  ))
  let data =
    ChangeData(
      ..change.data,
      revisions: [RevisionInfo(updated, None)],
      fields: fields,
      nodes: nodes,
      parents: parents,
      aliases: [],
      builds: builds,
      destroys: destroys,
      refreshers: refreshers,
      cross_field_keys: cross_field_keys,
    )
  use replaced <- result.try(from_data(data, change.identity_order))
  Ok(replaced)
}

pub fn prune(change: Changeset) -> Result(Changeset, TreeError) {
  let data = change.data
  use #(fields, state) <- result.try(prune_field_map(
    data.fields,
    PruneState(data.nodes, data.parents),
    data.aliases,
  ))
  use pruned <- result.try(from_data(
    ChangeData(
      ..data,
      fields: fields,
      nodes: state.nodes,
      parents: state.parents,
    ),
    change.identity_order,
  ))
  Ok(Changeset(..pruned, cross_field_keys: change.cross_field_keys))
}

pub fn relevant_removed_roots(
  change: Changeset,
) -> Result(List(AtomId), TreeError) {
  removed_roots_from_fields(change.data.fields, change.data, [])
}

pub fn detached_roots(change: Changeset) -> Result(List(AtomId), TreeError) {
  detached_roots_from_fields(change.data.fields, change.data, [])
}

pub fn update_refreshers(
  change: Changeset,
  roots: List(AtomId),
  repair: List(forest.Build),
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_builds(repair, "repair"))
  use refreshers <- result.try(
    list.try_fold(roots, [], fn(refreshers, root) {
      use _ <- result.try(validate_atom(root, "refreshers"))
      case build_contains(change.data.builds, root) {
        True -> Ok(refreshers)
        False ->
          case tree_from_builds(repair, root) {
            None ->
              Error(CorruptData(
                "refreshers",
                "required repair content is missing",
              ))
            Some(tree) -> Ok(put_build(refreshers, forest.Build(root, [tree])))
          }
      }
    }),
  )
  let data = ChangeData(..change.data, refreshers: refreshers)
  use updated <- result.try(from_data(data, change.identity_order))
  Ok(Changeset(..updated, cross_field_keys: change.cross_field_keys))
}

// ponytail: Replace bools with custom types (suggestion). The is_rollback Bool
// makes call sites unclear. Use a type such as Rollback or Undo.
pub fn invert(
  change: TaggedChange,
  is_rollback: Bool,
  inverse_revision: StableId,
) -> Result(Changeset, TreeError) {
  invert_with_trace(change, is_rollback, inverse_revision)
  |> result.map(fn(output) { output.0 })
}

// ponytail: Replace bools with custom types (suggestion). The is_rollback Bool
// makes call sites unclear. Use a type such as Rollback or Undo.
pub fn invert_with_trace(
  change: TaggedChange,
  is_rollback: Bool,
  inverse_revision: StableId,
) -> Result(#(Changeset, List(moves.TraceEvent)), TreeError) {
  use _ <- result.try(require_identity_revision(
    change.change.identity_order,
    inverse_revision,
  ))
  use _ <- result.try(check(
    list.is_empty(change.change.data.destroys),
    "invert",
    "a destroying change cannot be inverted",
  ))
  let data = effective_data(change.change.data)
  let #(allocation_revisions, _) = composition_metadata([change])
  use watermark <- result.try(reserved_watermark(
    data.max_local_id,
    list.length(allocation_revisions),
  ))
  use aliases <- result.try(
    sequence_field.new_alias_context(
      list.map(allocation_revisions, fn(info) {
        #(Some(info.revision), data.max_local_id)
      }),
    ),
  )
  let state = InvertState(aliases, moves.new(), watermark, [], [])
  use #(fields, state) <- result.try(invert_field_map(
    data.fields,
    None,
    is_rollback,
    inverse_revision,
    state,
  ))
  use #(nodes, state) <- result.try(
    list.try_fold(data.nodes, #([], state), fn(output, entry) {
      let NodeChange(
        fields: fields,
        node_exists_constraint: constraint,
        node_exists_constraint_on_revert: constraint_on_revert,
      ) = entry.1
      use #(fields, state) <- result.try(invert_field_map(
        fields,
        Some(entry.0),
        is_rollback,
        inverse_revision,
        output.1,
      ))
      Ok(#(
        list.append(output.0, [
          #(
            entry.0,
            NodeChange(
              fields: fields,
              node_exists_constraint: constraint_on_revert,
              node_exists_constraint_on_revert: constraint,
            ),
          ),
        ]),
        state,
      ))
    }),
  )
  use state <- result.try(
    invert_invalidated(state, is_rollback, inverse_revision, []),
  )
  let fields = replace_field_results(fields, None, state.field_results)
  let nodes = replace_node_field_results(nodes, state.field_results)
  use constraint_state <- result.try(update_constraint_nodes(
    fields,
    nodes,
    data.aliases,
    0,
  ))
  let nodes = constraint_state.nodes
  use parents <- result.try(rebuild_parents(fields, nodes, data.aliases))
  let destroys = case is_rollback {
    True ->
      list.map(data.builds, fn(build) {
        forest.Destroy(build.id, list.length(build.trees))
      })
    False -> []
  }
  let inverted_data =
    ChangeData(
      max_local_id: int_max(
        state.watermark,
        sequence_field.alias_max_id(state.aliases),
      ),
      revisions: [
        RevisionInfo(inverse_revision, case is_rollback {
          True -> change.revision
          False -> None
        }),
      ],
      fields: fields,
      nodes: nodes,
      parents: parents,
      aliases: data.aliases,
      builds: [],
      destroys: destroys,
      refreshers: [],
      cross_field_keys: [],
      constraint_violation_count: int_max(0, constraint_state.violation_count),
    )
  use cross_field_keys <- result.try(sorted_derived_cross_field_keys(
    inverted_data,
    change.change.identity_order,
  ))
  use inverted <- result.try(from_data(
    ChangeData(..inverted_data, cross_field_keys:),
    change.change.identity_order,
  ))
  Ok(#(
    Changeset(..inverted, cross_field_keys:),
    moves.trace(state.move_context),
  ))
}

pub fn rebase(
  change: TaggedChange,
  over: TaggedChange,
  context: RebaseContext,
) -> Result(Changeset, TreeError) {
  rebase_with_trace(change, over, context)
  |> result.map(fn(output) { output.0 })
}

pub fn rebase_with_trace(
  change: TaggedChange,
  over: TaggedChange,
  context: RebaseContext,
) -> Result(#(Changeset, List(moves.TraceEvent)), TreeError) {
  use _ <- result.try(validate_rebase_inputs(change, over, context))
  use identity_order <- result.try(merge_identity_orders(
    change.change.identity_order,
    over.change.identity_order,
  ))
  let authored = change.change.data
  let base = effective_data(over.change.data)
  use owners <- result.try(owner_ranges(
    base.cross_field_keys,
    moves.BaseOperand,
    base.aliases,
  ))
  let state =
    RebaseState(
      [],
      [],
      authored.aliases,
      authored,
      base,
      [],
      [],
      [],
      [],
      algebra_context(identity_order, context.revisions),
      moves.with_owners(moves.new(), owners),
      [],
      [],
      [],
    )
  use #(fields, state) <- result.try(rebase_field_maps(
    authored.fields,
    base.fields,
    None,
    None,
    state,
  ))
  use state <- result.try(rebase_invalidated(state, []))
  let fields = replace_field_results(fields, None, state.field_results)
  let nodes = replace_node_field_results(state.nodes, state.field_results)
  use constraint_state <- result.try(update_constraint_nodes(
    fields,
    nodes,
    state.aliases,
    authored.constraint_violation_count,
  ))
  let nodes = constraint_state.nodes
  use parents <- result.try(rebuild_parents(fields, nodes, state.aliases))
  use parents <- result.try(apply_rebase_notifications(
    parents,
    state.aliases,
    moves.notifications(state.move_context),
  ))
  use cross_field_keys <- result.try(apply_rebase_key_notifications(
    change.change.cross_field_keys,
    state.aliases,
    moves.notifications(state.move_context),
    identity_order,
  ))
  let revisions = tagged_revision_infos(change)
  let data =
    ChangeData(
      max_local_id: int_max(authored.max_local_id, base.max_local_id),
      revisions: revisions,
      fields: fields,
      nodes: nodes,
      parents: parents,
      aliases: state.aliases,
      builds: authored.builds,
      destroys: authored.destroys,
      refreshers: authored.refreshers,
      cross_field_keys: cross_field_keys,
      constraint_violation_count: int_max(0, constraint_state.violation_count),
    )
  use rebased <- result.try(from_data(data, identity_order))
  use rebased <- result.try(prune(rebased))
  let rebased = Changeset(..rebased, cross_field_keys:)
  Ok(#(rebased, moves.trace(state.move_context)))
}

fn validate_rebase_inputs(
  change: TaggedChange,
  over: TaggedChange,
  context: RebaseContext,
) -> Result(Nil, TreeError) {
  let expected =
    list.append(tagged_revision_infos(change), tagged_revision_infos(over))
  list.try_each(expected, fn(info) {
    case revision_info(context.revisions, info.revision) {
      None -> Error(InvalidHistory("rebase context is missing a revision"))
      Some(actual) ->
        case actual.rollback_of == info.rollback_of {
          True -> Ok(Nil)
          False ->
            Error(InvalidHistory("rebase rollback metadata does not match"))
        }
    }
  })
}

fn rebase_field_maps(
  authored: List(#(String, FieldChange)),
  base: List(#(String, FieldChange)),
  authored_parent: Option(AtomId),
  base_parent: Option(AtomId),
  state: RebaseState,
) -> Result(#(List(#(String, FieldChange)), RebaseState), TreeError) {
  list.try_fold(authored, #([], state), fn(output, entry) {
    case pair_value(base, entry.0) {
      None -> {
        use state <- result.try(copy_field_children(entry.1, output.1))
        Ok(#(list.append(output.0, [entry]), state))
      }
      Some(base_field) -> {
        use #(field, state) <- result.try(rebase_field(
          entry.1,
          base_field,
          moves.FieldId(authored_parent, entry.0),
          moves.FieldId(base_parent, entry.0),
          output.1,
        ))
        let source_field = moves.FieldId(base_parent, entry.0)
        let result_field = moves.FieldId(authored_parent, entry.0)
        let state =
          RebaseState(
            ..state,
            field_work: put_rebase_field_work(
              state.field_work,
              RebaseFieldWork(source_field, result_field, entry.1, base_field),
            ),
          )
        Ok(#(list.append(output.0, [#(entry.0, field)]), state))
      }
    }
  })
}

fn rebase_field(
  authored: FieldChange,
  base: FieldChange,
  field_id: moves.FieldId,
  base_field_id: moves.FieldId,
  state: RebaseState,
) -> Result(#(FieldChange, RebaseState), TreeError) {
  case authored, base {
    GenericField(authored), GenericField(base) -> {
      use #(children, state) <- result.try(rebase_generic(authored, base, state))
      Ok(#(GenericField(children), state))
    }
    SequenceField(authored), SequenceField(base) -> {
      use field_id <- result.try(normalize_field_id(field_id, state.aliases))
      use base_field_id <- result.try(normalize_field_id(
        base_field_id,
        state.base.aliases,
      ))
      let #(_, move_context) =
        moves.take_affected_for(state.move_context, field_id)
      let move_context = moves.enter_field(move_context, "rebase", field_id)
      sequence_rebase.rebase_with_context(
        authored,
        base,
        state,
        rebase_sequence_child,
        state.algebra,
        field_id,
        move_context,
      )
      |> result.map(fn(output) {
        let field = SequenceField(output.0)
        #(
          field,
          RebaseState(
            ..output.1,
            move_context: output.2,
            work: put_rebase_work(
              output.1.work,
              RebaseWork(base_field_id, field_id, authored, base),
            ),
            field_results: put_pair(output.1.field_results, field_id, field),
          ),
        )
      })
    }
    GenericField(authored), SequenceField(base) -> {
      let conversion_field = field_id
      use field_id <- result.try(normalize_field_id(field_id, state.aliases))
      let state =
        RebaseState(
          ..state,
          move_context: moves.record_conversion(
            state.move_context,
            "rebase",
            "generic-left",
            conversion_field,
            authored,
          ),
        )
      use authored <- result.try(generic_as_sequence(authored))
      rebase_field(
        SequenceField(authored),
        SequenceField(base),
        field_id,
        base_field_id,
        state,
      )
    }
    SequenceField(authored), GenericField(base) -> {
      let conversion_field = base_field_id
      use field_id <- result.try(normalize_field_id(field_id, state.aliases))
      let state =
        RebaseState(
          ..state,
          move_context: moves.record_conversion(
            state.move_context,
            "rebase",
            "generic-right",
            conversion_field,
            base,
          ),
        )
      use base <- result.try(generic_as_sequence(base))
      rebase_field(
        SequenceField(authored),
        SequenceField(base),
        field_id,
        base_field_id,
        state,
      )
    }
    ValueField(authored), ValueField(base) ->
      optional_field.rebase(authored, base, state, rebase_child)
      |> result.map(fn(output) { #(ValueField(output.0), output.1) })
    OptionalField(authored), OptionalField(base) ->
      optional_field.rebase(authored, base, state, rebase_child)
      |> result.map(fn(output) { #(OptionalField(output.0), output.1) })
    GenericField(authored), ValueField(base) ->
      optional_field.rebase(
        generic_as_optional(authored),
        base,
        state,
        rebase_child,
      )
      |> result.map(fn(output) { #(ValueField(output.0), output.1) })
    ValueField(authored), GenericField(base) ->
      optional_field.rebase(
        authored,
        generic_as_optional(base),
        state,
        rebase_child,
      )
      |> result.map(fn(output) { #(ValueField(output.0), output.1) })
    GenericField(authored), OptionalField(base) ->
      optional_field.rebase(
        generic_as_optional(authored),
        base,
        state,
        rebase_child,
      )
      |> result.map(fn(output) { #(OptionalField(output.0), output.1) })
    OptionalField(authored), GenericField(base) ->
      optional_field.rebase(
        authored,
        generic_as_optional(base),
        state,
        rebase_child,
      )
      |> result.map(fn(output) { #(OptionalField(output.0), output.1) })
    _, _ -> Error(CorruptData("rebase", "field kinds do not match"))
  }
}

fn rebase_sequence_child(
  authored: Option(AtomId),
  base: Option(AtomId),
  attach: sequence_field.AttachState,
  state: RebaseState,
  move_context: moves.Context,
) -> Result(#(Option(AtomId), RebaseState, moves.Context), TreeError) {
  use #(child, state) <- result.try(rebase_child(
    authored,
    base,
    case attach {
      sequence_field.Attached -> optional_field.Attached
      sequence_field.DetachedNode -> optional_field.DetachedNode
    },
    RebaseState(..state, move_context: move_context),
  ))
  Ok(#(child, state, state.move_context))
}

fn rebase_generic(
  authored: List(#(Int, AtomId)),
  base: List(#(Int, AtomId)),
  state: RebaseState,
) -> Result(#(List(#(Int, AtomId)), RebaseState), TreeError) {
  use #(children, remaining, state) <- result.try(
    list.try_fold(authored, #([], base, state), fn(output, child) {
      let #(base_child, remaining) = take_pair(output.1, child.0)
      use #(rebased, state) <- result.try(rebase_child(
        Some(child.1),
        base_child,
        optional_field.Attached,
        output.2,
      ))
      let children = case rebased {
        None -> output.0
        Some(rebased) -> list.append(output.0, [#(child.0, rebased)])
      }
      Ok(#(children, remaining, state))
    }),
  )
  use #(children, state) <- result.try(
    list.try_fold(remaining, #(children, state), fn(output, child) {
      use #(rebased, state) <- result.try(rebase_child(
        None,
        Some(child.1),
        optional_field.Attached,
        output.1,
      ))
      let children = case rebased {
        None -> output.0
        Some(rebased) -> list.append(output.0, [#(child.0, rebased)])
      }
      Ok(#(children, state))
    }),
  )
  Ok(#(children, state))
}

fn rebase_child(
  authored: Option(AtomId),
  base: Option(AtomId),
  attach: optional_field.AttachState,
  state: RebaseState,
) -> Result(#(Option(AtomId), RebaseState), TreeError) {
  case authored, base {
    Some(authored), Some(base) -> {
      use #(rebased, state) <- result.try(queue_rebase_nodes(
        authored,
        base,
        attach,
        state,
      ))
      Ok(#(Some(rebased), state))
    }
    Some(authored), None -> {
      use #(authored, state) <- result.try(copy_authored_node(authored, state))
      Ok(#(Some(authored), state))
    }
    None, Some(base) -> {
      use base <- result.try(resolve_alias(base, state.base.aliases))
      Ok(#(pair_value(state.base_to_rebased, base), state))
    }
    None, None -> Ok(#(None, state))
  }
}

fn queue_rebase_nodes(
  authored: AtomId,
  base: AtomId,
  attach: optional_field.AttachState,
  state: RebaseState,
) -> Result(#(AtomId, RebaseState), TreeError) {
  use authored <- result.try(resolve_alias(authored, state.authored.aliases))
  use base <- result.try(resolve_alias(base, state.base.aliases))
  case pair_value(state.base_to_rebased, base) {
    Some(existing) -> Ok(#(existing, state))
    None -> {
      let pending = #(authored, base, attach)
      let pending_pairs = case
        list.any(state.pending_pairs, fn(entry) {
          entry.0 == authored && entry.1 == base
        })
      {
        True -> state.pending_pairs
        False -> list.append(state.pending_pairs, [pending])
      }
      Ok(#(authored, RebaseState(..state, pending_pairs:)))
    }
  }
}

fn rebase_nodes(
  authored: AtomId,
  base: AtomId,
  state: RebaseState,
) -> Result(#(AtomId, RebaseState), TreeError) {
  use authored <- result.try(resolve_alias(authored, state.authored.aliases))
  use base <- result.try(resolve_alias(base, state.base.aliases))
  case pair_value(state.base_to_rebased, base) {
    Some(existing) -> Ok(#(existing, state))
    None -> {
      use authored_node <- result.try(node_for(authored, state.authored.nodes))
      use base_node <- result.try(node_for(base, state.base.nodes))
      let NodeChange(fields: authored_fields, ..) = authored_node
      let NodeChange(fields: base_fields, ..) = base_node
      let state =
        RebaseState(
          ..state,
          base_to_rebased: list.append(state.base_to_rebased, [
            #(base, authored),
          ]),
          pairs: [#(authored, base), ..state.pairs],
          move_context: moves.replace_parent(state.move_context, base, authored),
        )
      use #(fields, state) <- result.try(rebase_field_maps(
        authored_fields,
        base_fields,
        Some(authored),
        Some(base),
        state,
      ))
      let nodes =
        put_pair(state.nodes, authored, NodeChange(..authored_node, fields:))
      Ok(#(authored, RebaseState(..state, nodes: nodes)))
    }
  }
}

fn copy_field_children(
  field: FieldChange,
  state: RebaseState,
) -> Result(RebaseState, TreeError) {
  list.try_fold(field_children(field), state, fn(state, child) {
    copy_authored_node(child, state) |> result.map(fn(output) { output.1 })
  })
}

fn copy_authored_node(
  id: AtomId,
  state: RebaseState,
) -> Result(#(AtomId, RebaseState), TreeError) {
  use canonical <- result.try(resolve_alias(id, state.authored.aliases))
  case pair_value(state.nodes, canonical) {
    Some(_) -> Ok(#(canonical, state))
    None -> {
      use node <- result.try(node_for(canonical, state.authored.nodes))
      let NodeChange(fields: fields, ..) = node
      let state =
        RebaseState(..state, nodes: put_pair(state.nodes, canonical, node))
      use state <- result.try(
        list.try_fold(fields, state, fn(state, entry) {
          copy_field_children(entry.1, state)
        }),
      )
      Ok(#(canonical, state))
    }
  }
}

fn update_constraint_nodes(
  fields: List(#(String, FieldChange)),
  nodes: List(#(AtomId, NodeChange)),
  aliases: List(#(AtomId, AtomId)),
  violation_count: Int,
) -> Result(ConstraintState, TreeError) {
  list.try_fold(
    fields,
    ConstraintState(nodes, violation_count),
    fn(state, entry) {
      update_field_constraint_nodes(entry.1, False, state, aliases)
    },
  )
}

fn update_field_constraint_nodes(
  field: FieldChange,
  parent_detached: Bool,
  state: ConstraintState,
  aliases: List(#(AtomId, AtomId)),
) -> Result(ConstraintState, TreeError) {
  case field {
    GenericField(children) ->
      list.try_fold(children, state, fn(state, child) {
        update_constraint_node(child.1, parent_detached, state, aliases)
      })
    SequenceField(change) ->
      list.try_fold(sequence_field.to_marks(change), state, fn(state, mark) {
        case mark.child {
          None -> Ok(state)
          Some(child) ->
            update_constraint_node(
              child,
              parent_detached || sequence_child_is_detached(mark),
              state,
              aliases,
            )
        }
      })
    ValueField(optional_field.FieldChange(_, children, _))
    | OptionalField(optional_field.FieldChange(_, children, _)) ->
      list.try_fold(children, state, fn(state, child) {
        let detached = case child.0 {
          optional_field.Active -> parent_detached
          optional_field.Detached(_) -> True
        }
        update_constraint_node(child.1, detached, state, aliases)
      })
  }
}

fn sequence_child_is_detached(mark: sequence_field.Mark) -> Bool {
  case mark.cell_id, sequence_field.input_length(mark) {
    None, 0 -> True
    Some(_), length if length > 0 -> False
    None, _ -> False
    Some(_), _ -> True
  }
}

fn effective_data(data: ChangeData) -> ChangeData {
  case data.constraint_violation_count > 0 {
    True ->
      ChangeData(
        ..data,
        fields: [],
        nodes: [],
        parents: [],
        aliases: [],
        cross_field_keys: [],
      )
    False -> data
  }
}

fn composition_data(data: ChangeData) -> Result(ChangeData, TreeError) {
  case data.constraint_violation_count > 0 {
    False -> Ok(data)
    True -> {
      use fields <- result.try(mute_field_map(data.fields))
      use nodes <- result.try(
        list.try_map(data.nodes, fn(entry) {
          use fields <- result.try(mute_field_map(entry.1.fields))
          Ok(#(entry.0, NodeChange(..entry.1, fields:)))
        }),
      )
      Ok(ChangeData(..data, fields: fields, nodes: nodes, cross_field_keys: []))
    }
  }
}

fn mute_field_map(
  fields: List(#(String, FieldChange)),
) -> Result(List(#(String, FieldChange)), TreeError) {
  list.try_map(fields, fn(entry) {
    use field <- result.try(mute_field(entry.1))
    Ok(#(entry.0, field))
  })
}

fn mute_field(field: FieldChange) -> Result(FieldChange, TreeError) {
  case field {
    ValueField(optional_field.FieldChange(_, children, _)) ->
      Ok(ValueField(optional_field.FieldChange([], children, None)))
    OptionalField(optional_field.FieldChange(_, children, _)) ->
      Ok(OptionalField(optional_field.FieldChange([], children, None)))
    SequenceField(change) -> {
      use muted <- result.try(
        sequence_field.to_marks(change)
        |> list.map(fn(mark) {
          sequence_field.Mark(..mark, effect: sequence_field.Noop)
        })
        |> sequence_field.from_marks,
      )
      Ok(SequenceField(muted))
    }
    GenericField(_) -> Ok(field)
  }
}

fn update_constraint_node(
  id: AtomId,
  detached: Bool,
  state: ConstraintState,
  aliases: List(#(AtomId, AtomId)),
) -> Result(ConstraintState, TreeError) {
  use canonical <- result.try(resolve_alias(id, aliases))
  use node <- result.try(node_for(canonical, state.nodes))
  let #(constraint, violation_count) = case node.node_exists_constraint {
    None -> #(None, state.violation_count)
    Some(NodeExistsConstraint(was_violated)) -> #(
      Some(NodeExistsConstraint(detached)),
      case was_violated, detached {
        False, True -> state.violation_count + 1
        True, False -> state.violation_count - 1
        _, _ -> state.violation_count
      },
    )
  }
  let node = NodeChange(..node, node_exists_constraint: constraint)
  use state <- result.try(
    list.try_fold(
      node.fields,
      ConstraintState(..state, violation_count:),
      fn(state, entry) {
        update_field_constraint_nodes(entry.1, detached, state, aliases)
      },
    ),
  )
  Ok(ConstraintState(..state, nodes: put_pair(state.nodes, canonical, node)))
}

fn invert_field_map(
  fields: List(#(String, FieldChange)),
  parent: Option(AtomId),
  is_rollback: Bool,
  inverse_revision: StableId,
  state: InvertState,
) -> Result(#(List(#(String, FieldChange)), InvertState), TreeError) {
  list.try_fold(fields, #([], state), fn(output, entry) {
    use #(field, state) <- result.try(invert_field(
      entry.1,
      moves.FieldId(parent, entry.0),
      is_rollback,
      inverse_revision,
      output.1,
    ))
    Ok(#(list.append(output.0, [#(entry.0, field)]), state))
  })
}

fn invert_field(
  field: FieldChange,
  field_id: moves.FieldId,
  is_rollback: Bool,
  inverse_revision: StableId,
  state: InvertState,
) -> Result(#(FieldChange, InvertState), TreeError) {
  case field {
    GenericField(children) -> Ok(#(GenericField(children), state))
    SequenceField(change) -> {
      let move_context =
        moves.enter_field(state.move_context, "invert", field_id)
      sequence_invert.invert(
        change,
        is_rollback,
        state.aliases,
        sequence_field.alias,
        Some(inverse_revision),
        field_id,
        move_context,
      )
      |> result.map(fn(output) {
        let field = SequenceField(output.0)
        #(
          field,
          InvertState(
            ..state,
            aliases: output.1,
            move_context: output.2,
            work: put_invert_work(state.work, InvertWork(field_id, change)),
            field_results: put_pair(state.field_results, field_id, field),
          ),
        )
      })
    }
    ValueField(change) -> {
      use #(change, watermark) <- result.try(optional_field.invert(
        change,
        is_rollback,
        Some(inverse_revision),
        state.watermark,
      ))
      Ok(#(ValueField(change), InvertState(..state, watermark:)))
    }
    OptionalField(change) -> {
      use #(change, watermark) <- result.try(optional_field.invert(
        change,
        is_rollback,
        Some(inverse_revision),
        state.watermark,
      ))
      Ok(#(OptionalField(change), InvertState(..state, watermark:)))
    }
  }
}

fn tagged_revision_infos(change: TaggedChange) -> List(RevisionInfo) {
  case change.change.data.revisions {
    [] ->
      case change.revision {
        None -> []
        Some(revision) -> [RevisionInfo(revision, change.rollback_of)]
      }
    revisions -> revisions
  }
}

fn reserved_watermark(
  max_local_id: Int,
  revision_count: Int,
) -> Result(Int, TreeError) {
  case max_local_id, revision_count {
    -1, _ -> Ok(-1)
    _, 0 -> Ok(max_local_id)
    _, _ -> reserve_ranges(max_local_id, revision_count, -1)
  }
}

fn reserve_ranges(
  original_max: Int,
  count: Int,
  watermark: Int,
) -> Result(Int, TreeError) {
  case count {
    0 -> Ok(watermark)
    _ if watermark == -1 -> reserve_ranges(original_max, count - 1, original_max)
    _ -> {
      use _ <- result.try(check(
        original_max < max_safe_integer
          && original_max + 1 <= max_safe_integer - watermark,
        "invert",
        "identifier reservations overflow",
      ))
      reserve_ranges(original_max, count - 1, watermark + original_max + 1)
    }
  }
}

fn rebuild_parents(
  fields: List(#(String, FieldChange)),
  nodes: List(#(AtomId, NodeChange)),
  aliases: List(#(AtomId, AtomId)),
) -> Result(List(#(AtomId, ParentField)), TreeError) {
  collect_parents(fields, None, nodes, aliases, [], [])
}

fn collect_parents(
  fields: List(#(String, FieldChange)),
  parent: Option(AtomId),
  nodes: List(#(AtomId, NodeChange)),
  aliases: List(#(AtomId, AtomId)),
  parents: List(#(AtomId, ParentField)),
  stack: List(AtomId),
) -> Result(List(#(AtomId, ParentField)), TreeError) {
  list.try_fold(fields, parents, fn(parents, entry) {
    list.try_fold(field_children(entry.1), parents, fn(parents, child) {
      use canonical <- result.try(resolve_alias(child, aliases))
      use _ <- result.try(check(
        !list.contains(stack, canonical),
        "node parents",
        "node ownership contains a cycle",
      ))
      use _ <- result.try(check(
        pair_value(parents, canonical) == None,
        "node parents",
        "node has incompatible ownership",
      ))
      use node <- result.try(node_for(canonical, nodes))
      let NodeChange(fields: child_fields, ..) = node
      collect_parents(
        child_fields,
        Some(canonical),
        nodes,
        aliases,
        list.append(parents, [
          #(canonical, ParentField(parent, entry.0)),
        ]),
        [canonical, ..stack],
      )
    })
  })
}

fn collect_replacements(
  data: ChangeData,
  state: ReplaceState,
) -> Result(ReplaceState, TreeError) {
  use state <- result.try(visit_field_map(data.fields, state))
  use state <- result.try(
    list.try_fold(data.nodes, state, fn(state, entry) {
      use state <- result.try(visit_atom(entry.0, 1, state))
      let NodeChange(fields: fields, ..) = entry.1
      visit_field_map(fields, state)
    }),
  )
  use state <- result.try(
    list.try_fold(data.parents, state, fn(state, entry) {
      use state <- result.try(visit_atom(entry.0, 1, state))
      use parent <- result.try(normalize_parent(entry.1, data.aliases))
      let ParentField(parent, _) = parent
      case parent {
        None -> Ok(state)
        Some(parent) -> visit_atom(parent, 1, state)
      }
    }),
  )
  use state <- result.try(visit_builds(data.builds, state))
  use state <- result.try(
    list.try_fold(data.destroys, state, fn(state, destroy) {
      visit_atom(destroy.id, destroy.count, state)
    }),
  )
  visit_builds(data.refreshers, state)
}

fn visit_field_map(
  fields: List(#(String, FieldChange)),
  state: ReplaceState,
) -> Result(ReplaceState, TreeError) {
  list.try_fold(fields, state, fn(state, entry) { visit_field(entry.1, state) })
}

fn visit_field(
  field: FieldChange,
  state: ReplaceState,
) -> Result(ReplaceState, TreeError) {
  case field {
    GenericField(children) ->
      list.try_fold(children, state, fn(state, child) {
        visit_atom(child.1, 1, state)
      })
    SequenceField(change) ->
      list.try_fold(sequence_field.to_marks(change), state, fn(state, mark) {
        use state <- result.try(case mark.cell_id {
          None -> Ok(state)
          Some(id) -> visit_atom(id, mark.count, state)
        })
        use state <- result.try(visit_sequence_effect(
          mark.effect,
          mark.count,
          state,
        ))
        case mark.child {
          None -> Ok(state)
          Some(id) -> visit_atom(id, 1, state)
        }
      })
    ValueField(change) | OptionalField(change) -> {
      let optional_field.FieldChange(moves, children, replacement) = change
      use state <- result.try(case replacement {
        None -> Ok(state)
        Some(replacement) -> {
          use state <- result.try(visit_atom(replacement.detach_id, 1, state))
          case replacement.source {
            Some(optional_field.Detached(id)) -> visit_atom(id, 1, state)
            _ -> Ok(state)
          }
        }
      })
      use state <- result.try(
        list.try_fold(children, state, fn(state, child) {
          use state <- result.try(case child.0 {
            optional_field.Active -> Ok(state)
            optional_field.Detached(id) -> visit_atom(id, 1, state)
          })
          visit_atom(child.1, 1, state)
        }),
      )
      list.try_fold(moves, state, fn(state, move) {
        use state <- result.try(visit_atom(move.0, 1, state))
        visit_atom(move.1, 1, state)
      })
    }
  }
}

fn visit_sequence_effect(
  effect: sequence_field.Effect,
  count: Int,
  state: ReplaceState,
) -> Result(ReplaceState, TreeError) {
  case effect {
    sequence_field.Noop -> Ok(state)
    sequence_field.Rename(id) -> visit_atom(id, count, state)
    sequence_field.Attach(attach) -> visit_sequence_attach(attach, count, state)
    sequence_field.Detach(detach) -> visit_sequence_detach(detach, count, state)
    sequence_field.AttachAndDetach(attach, detach) -> {
      use state <- result.try(visit_sequence_attach(attach, count, state))
      visit_sequence_detach(detach, count, state)
    }
  }
}

fn visit_sequence_attach(
  attach: sequence_field.Attach,
  count: Int,
  state: ReplaceState,
) -> Result(ReplaceState, TreeError) {
  case attach {
    sequence_field.Insert(id) -> visit_atom(id, count, state)
    sequence_field.MoveIn(id, endpoint) -> {
      use state <- result.try(visit_atom(id, count, state))
      case endpoint {
        None -> Ok(state)
        Some(id) -> visit_atom(id, count, state)
      }
    }
  }
}

fn visit_sequence_detach(
  detach: sequence_field.Detach,
  count: Int,
  state: ReplaceState,
) -> Result(ReplaceState, TreeError) {
  case detach {
    sequence_field.Remove(id, id_override) -> {
      use state <- result.try(visit_atom(id, count, state))
      case id_override {
        None -> Ok(state)
        Some(id) -> visit_atom(id, count, state)
      }
    }
    sequence_field.MoveOut(id, endpoint, id_override) -> {
      use state <- result.try(visit_atom(id, count, state))
      use state <- result.try(case endpoint {
        None -> Ok(state)
        Some(id) -> visit_atom(id, count, state)
      })
      case id_override {
        None -> Ok(state)
        Some(id) -> visit_atom(id, count, state)
      }
    }
  }
}

fn visit_builds(
  builds: List(forest.Build),
  state: ReplaceState,
) -> Result(ReplaceState, TreeError) {
  list.try_fold(builds, state, fn(state, build) {
    visit_atom(build.id, list.length(build.trees), state)
  })
}

fn visit_atom(
  id: AtomId,
  count: Int,
  state: ReplaceState,
) -> Result(ReplaceState, TreeError) {
  case list.contains(state.obsolete, id.revision) {
    False -> Ok(state)
    True -> {
      use _ <- result.try(validate_range(id, count, "revision replacement"))
      let positions = atom_range(id, count, [])
      let existing = indexed_mappings(positions, state.mappings, 0, [])
      let mapped = list.filter(existing, fn(entry) { entry.1 != None })
      use output_start <- result.try(mapped_range_start(mapped, id.local_id))
      let desired =
        atom_range(AtomId(Some(state.updated), output_start), count, [])
      let collision =
        list.fold(zip_atoms(positions, desired, []), False, fn(collision, pair) {
          let existing_input = pair.0
          let output = pair.1
          collision
          || {
            let mapped = mapping_for(state.mappings, existing_input)
            list.contains(state.used, output) && mapped != Some(output)
          }
        })
      use output_start <- result.try(case collision, mapped {
        False, _ -> Ok(output_start)
        True, [] -> {
          use _ <- result.try(check(
            state.max_seen < max_safe_integer,
            "revision replacement",
            "identifiers are exhausted",
          ))
          Ok(state.max_seen + 1)
        }
        True, _ ->
          Error(CorruptData(
            "revision replacement",
            "mapped range cannot remain contiguous",
          ))
      })
      use _ <- result.try(check(
        count - 1 <= max_safe_integer - output_start,
        "revision replacement",
        "identifier range overflows",
      ))
      let outputs =
        atom_range(AtomId(Some(state.updated), output_start), count, [])
      let mappings =
        list.fold(
          zip_atoms(positions, outputs, []),
          state.mappings,
          fn(mappings, pair) {
            let input = pair.0
            case mapping_for(mappings, input) {
              Some(_) -> mappings
              None -> list.append(mappings, [pair])
            }
          },
        )
      let used =
        list.fold(outputs, state.used, fn(used, output) {
          case list.contains(used, output) {
            True -> used
            False -> list.append(used, [output])
          }
        })
      Ok(
        ReplaceState(
          ..state,
          mappings: mappings,
          used: used,
          max_seen: int_max(state.max_seen, output_start + count - 1),
        ),
      )
    }
  }
}

fn atom_range(id: AtomId, count: Int, output: List(AtomId)) -> List(AtomId) {
  case count {
    0 -> list.reverse(output)
    1 -> list.reverse([id, ..output])
    _ ->
      atom_range(AtomId(..id, local_id: id.local_id + 1), count - 1, [
        id,
        ..output
      ])
  }
}

fn mapped_range_start(
  mapped: List(#(Int, Option(AtomId))),
  default: Int,
) -> Result(Int, TreeError) {
  case mapped {
    [] -> Ok(default)
    [#(index, Some(output)), ..rest] -> {
      let start = output.local_id - index
      use _ <- result.try(check(
        start >= 0,
        "revision replacement",
        "mapped range starts below zero",
      ))
      use _ <- result.try(
        list.try_each(rest, fn(entry) {
          case entry {
            #(index, Some(output)) ->
              check(
                output.local_id == start + index,
                "revision replacement",
                "mapped range is not contiguous",
              )
            #(_, None) ->
              Error(CorruptData(
                "revision replacement",
                "mapped identity is missing",
              ))
          }
        }),
      )
      Ok(start)
    }
    [#(_, None), ..] ->
      Error(CorruptData("revision replacement", "mapped identity is missing"))
  }
}

fn indexed_mappings(
  ids: List(AtomId),
  mappings: List(#(AtomId, AtomId)),
  index: Int,
  output: List(#(Int, Option(AtomId))),
) -> List(#(Int, Option(AtomId))) {
  case ids {
    [] -> list.reverse(output)
    [id, ..rest] ->
      indexed_mappings(rest, mappings, index + 1, [
        #(index, mapping_for(mappings, id)),
        ..output
      ])
  }
}

fn zip_atoms(
  first: List(AtomId),
  second: List(AtomId),
  output: List(#(AtomId, AtomId)),
) -> List(#(AtomId, AtomId)) {
  case first, second {
    [], [] -> list.reverse(output)
    [first, ..first_rest], [second, ..second_rest] ->
      zip_atoms(first_rest, second_rest, [#(first, second), ..output])
    _, _ -> list.reverse(output)
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn mapping_for(
  mappings: List(#(AtomId, AtomId)),
  id: AtomId,
) -> Option(AtomId) {
  pair_value(mappings, id)
}

fn replaced_atom(id: AtomId, state: ReplaceState) -> Result(AtomId, TreeError) {
  case list.contains(state.obsolete, id.revision) {
    False -> Ok(id)
    True ->
      case mapping_for(state.mappings, id) {
        Some(updated) -> Ok(updated)
        None ->
          Error(CorruptData("revision replacement", "identity was not visited"))
      }
  }
}

fn replace_cross_field_keys(
  keys: List(CrossFieldKey),
  state: ReplaceState,
) -> Result(List(CrossFieldKey), TreeError) {
  list.try_map(keys, fn(entry) {
    let CrossFieldKey(key, count, field) = entry
    let moves.Key(side, revision, local_id) = key
    use key <- result.try(replaced_atom(AtomId(revision, local_id), state))
    use parent <- result.try(case field.parent {
      None -> Ok(None)
      Some(parent) -> replaced_atom(parent, state) |> result.map(Some)
    })
    Ok(CrossFieldKey(
      moves.Key(side, key.revision, key.local_id),
      count,
      moves.FieldId(parent, field.field),
    ))
  })
}

fn replace_field_map(
  fields: List(#(String, FieldChange)),
  state: ReplaceState,
) -> Result(List(#(String, FieldChange)), TreeError) {
  list.try_map(fields, fn(entry) {
    use field <- result.try(replace_field(entry.1, state))
    Ok(#(entry.0, field))
  })
}

fn replace_field(
  field: FieldChange,
  state: ReplaceState,
) -> Result(FieldChange, TreeError) {
  case field {
    GenericField(children) ->
      list.try_map(children, fn(child) {
        use id <- result.try(replaced_atom(child.1, state))
        Ok(#(child.0, id))
      })
      |> result.map(GenericField)
    SequenceField(change) ->
      sequence_field.replace_revisions(change, fn(id, count) {
        use _ <- result.try(validate_range(id, count, "revision replacement"))
        replaced_atom(id, state)
      })
      |> result.map(SequenceField)
    ValueField(change) ->
      optional_field.replace_revisions(change, fn(id) {
        replaced_atom(id, state)
      })
      |> result.map(ValueField)
    OptionalField(change) ->
      optional_field.replace_revisions(change, fn(id) {
        replaced_atom(id, state)
      })
      |> result.map(OptionalField)
  }
}

fn replace_builds(
  builds: List(forest.Build),
  state: ReplaceState,
) -> Result(List(forest.Build), TreeError) {
  list.try_map(builds, fn(build) {
    use id <- result.try(replaced_atom(build.id, state))
    Ok(forest.Build(id, build.trees))
  })
}

fn prune_field_map(
  fields: List(#(String, FieldChange)),
  state: PruneState,
  aliases: List(#(AtomId, AtomId)),
) -> Result(#(List(#(String, FieldChange)), PruneState), TreeError) {
  list.try_fold(fields, #([], state), fn(output, entry) {
    use #(field, state) <- result.try(prune_field(entry.1, output.1, aliases))
    let fields = case field {
      None -> output.0
      Some(field) -> list.append(output.0, [#(entry.0, field)])
    }
    Ok(#(fields, state))
  })
}

fn prune_field(
  field: FieldChange,
  state: PruneState,
  aliases: List(#(AtomId, AtomId)),
) -> Result(#(Option(FieldChange), PruneState), TreeError) {
  case field {
    GenericField(children) -> {
      use #(children, state) <- result.try(prune_children(
        children,
        state,
        aliases,
      ))
      case children {
        [] -> Ok(#(None, state))
        _ -> Ok(#(Some(GenericField(children)), state))
      }
    }
    SequenceField(change) -> {
      use #(pruned, state) <- result.try(
        sequence_field.prune_with_state(change, state, fn(child, state) {
          prune_node(child, state, aliases)
        }),
      )
      use pruned <- result.try(prune_sequence_context(pruned))
      case
        list.any(sequence_field.to_marks(pruned), fn(mark) {
          mark.effect != sequence_field.Noop || mark.child != None
        })
      {
        False -> Ok(#(None, state))
        True -> Ok(#(Some(SequenceField(pruned)), state))
      }
    }
    ValueField(change) -> prune_concrete(change, state, aliases, True)
    OptionalField(change) -> prune_concrete(change, state, aliases, False)
  }
}

fn prune_sequence_context(
  change: sequence_field.Changeset,
) -> Result(sequence_field.Changeset, TreeError) {
  change
  |> sequence_field.to_marks
  |> list.reverse
  |> drop_trailing_sequence_context
  |> list.reverse
  |> sequence_field.from_marks
}

fn drop_trailing_sequence_context(
  marks: List(sequence_field.Mark),
) -> List(sequence_field.Mark) {
  case marks {
    [sequence_field.Mark(_, None, sequence_field.Noop, None), ..rest] ->
      drop_trailing_sequence_context(rest)
    _ -> marks
  }
}

fn prune_concrete(
  change: optional_field.FieldChange,
  state: PruneState,
  aliases: List(#(AtomId, AtomId)),
  required: Bool,
) -> Result(#(Option(FieldChange), PruneState), TreeError) {
  let optional_field.FieldChange(moves, children, replacement) = change
  use #(children, state) <- result.try(
    list.try_fold(children, #([], state), fn(output, child) {
      use #(node, state) <- result.try(prune_node(child.1, output.1, aliases))
      let children = case node {
        None -> output.0
        Some(node) -> list.append(output.0, [#(child.0, node)])
      }
      Ok(#(children, state))
    }),
  )
  let pruned = optional_field.FieldChange(moves, children, replacement)
  case moves, children, replacement {
    [], [], None -> Ok(#(None, state))
    _, _, _ ->
      case required {
        True -> Ok(#(Some(ValueField(pruned)), state))
        False -> Ok(#(Some(OptionalField(pruned)), state))
      }
  }
}

fn prune_children(
  children: List(#(Int, AtomId)),
  state: PruneState,
  aliases: List(#(AtomId, AtomId)),
) -> Result(#(List(#(Int, AtomId)), PruneState), TreeError) {
  list.try_fold(children, #([], state), fn(output, child) {
    use #(node, state) <- result.try(prune_node(child.1, output.1, aliases))
    let children = case node {
      None -> output.0
      Some(node) -> list.append(output.0, [#(child.0, node)])
    }
    Ok(#(children, state))
  })
}

fn prune_node(
  id: AtomId,
  state: PruneState,
  aliases: List(#(AtomId, AtomId)),
) -> Result(#(Option(AtomId), PruneState), TreeError) {
  use canonical <- result.try(resolve_alias(id, aliases))
  use node <- result.try(node_for(canonical, state.nodes))
  let NodeChange(fields: fields, ..) = node
  use #(fields, state) <- result.try(prune_field_map(fields, state, aliases))
  case
    fields,
    node.node_exists_constraint,
    node.node_exists_constraint_on_revert
  {
    [], None, None ->
      Ok(#(
        None,
        PruneState(
          remove_pair(state.nodes, canonical),
          remove_pair(state.parents, canonical),
        ),
      ))
    _, _, _ ->
      Ok(#(
        Some(id),
        PruneState(
          put_pair(state.nodes, canonical, NodeChange(..node, fields:)),
          state.parents,
        ),
      ))
  }
}

fn removed_roots_from_fields(
  fields: List(#(String, FieldChange)),
  data: ChangeData,
  roots: List(AtomId),
) -> Result(List(AtomId), TreeError) {
  list.try_fold(fields, roots, fn(roots, entry) {
    removed_roots_from_field(entry.1, data, roots)
  })
}

fn removed_roots_from_field(
  field: FieldChange,
  data: ChangeData,
  roots: List(AtomId),
) -> Result(List(AtomId), TreeError) {
  case field {
    GenericField(children) ->
      list.try_fold(children, roots, fn(roots, child) {
        removed_roots_from_child(child.1, data, roots)
      })
    SequenceField(change) ->
      sequence_field.relevant_removed_roots(change, fn(child) {
        removed_roots_from_child(child, data, [])
      })
      |> result.map(fn(found) {
        list.fold(found, roots, fn(roots, root) { append_unique(roots, root) })
      })
    ValueField(change) | OptionalField(change) -> {
      let optional_field.FieldChange(moves, children, replacement) = change
      let roots =
        list.fold(moves, roots, fn(roots, move) { append_unique(roots, move.0) })
      use roots <- result.try(
        list.try_fold(children, roots, fn(roots, child) {
          let roots = case child.0 {
            optional_field.Active -> roots
            optional_field.Detached(id) -> append_unique(roots, id)
          }
          removed_roots_from_child(child.1, data, roots)
        }),
      )
      Ok(case replacement {
        Some(optional_field.Replacement(_, Some(optional_field.Detached(id)), _)) ->
          append_unique(roots, id)
        _ -> roots
      })
    }
  }
}

fn removed_roots_from_child(
  id: AtomId,
  data: ChangeData,
  roots: List(AtomId),
) -> Result(List(AtomId), TreeError) {
  use canonical <- result.try(resolve_alias(id, data.aliases))
  use node <- result.try(node_for(canonical, data.nodes))
  let NodeChange(fields: fields, ..) = node
  removed_roots_from_fields(fields, data, roots)
}

fn detached_roots_from_fields(
  fields: List(#(String, FieldChange)),
  data: ChangeData,
  roots: List(AtomId),
) -> Result(List(AtomId), TreeError) {
  list.try_fold(fields, roots, fn(roots, entry) {
    case entry.1 {
      GenericField(children) ->
        list.try_fold(children, roots, fn(roots, child) {
          detached_roots_from_child(child.1, data, roots)
        })
      SequenceField(change) ->
        sequence_field.relevant_removed_roots(change, fn(child) {
          detached_roots_from_child(child, data, [])
        })
        |> result.map(fn(found) {
          list.fold(found, roots, fn(roots, root) { append_unique(roots, root) })
        })
      ValueField(field) | OptionalField(field) -> {
        let optional_field.FieldChange(_, children, replacement) = field
        let roots = case replacement {
          Some(replacement) -> append_unique(roots, replacement.detach_id)
          None -> roots
        }
        list.try_fold(children, roots, fn(roots, child) {
          detached_roots_from_child(child.1, data, roots)
        })
      }
    }
  })
}

fn detached_roots_from_child(
  id: AtomId,
  data: ChangeData,
  roots: List(AtomId),
) -> Result(List(AtomId), TreeError) {
  use canonical <- result.try(resolve_alias(id, data.aliases))
  use node <- result.try(node_for(canonical, data.nodes))
  let NodeChange(fields: fields, ..) = node
  detached_roots_from_fields(fields, data, roots)
}

fn append_unique(values: List(a), value: a) -> List(a) {
  case list.contains(values, value) {
    True -> values
    False -> list.append(values, [value])
  }
}

fn build_contains(builds: List(forest.Build), id: AtomId) -> Bool {
  case builds {
    [] -> False
    [build, ..rest] ->
      case
        build.id.revision == id.revision
        && id.local_id >= build.id.local_id
        && id.local_id < build.id.local_id + list.length(build.trees)
      {
        True -> True
        False -> build_contains(rest, id)
      }
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn tree_from_builds(
  builds: List(forest.Build),
  id: AtomId,
) -> Option(TreeValue) {
  case builds {
    [] -> None
    [build, ..rest] ->
      case
        build.id.revision == id.revision
        && id.local_id >= build.id.local_id
        && id.local_id < build.id.local_id + list.length(build.trees)
      {
        True -> nth(build.trees, id.local_id - build.id.local_id)
        False -> tree_from_builds(rest, id)
      }
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil). history.item_at is a copy of this
// helper. Use list.drop, then list.first.
fn nth(values: List(a), index: Int) -> Option(a) {
  case values, index {
    [], _ -> None
    [value, ..], 0 -> Some(value)
    [_, ..rest], _ -> nth(rest, index - 1)
  }
}

fn put_build(
  builds: List(forest.Build),
  build: forest.Build,
) -> List(forest.Build) {
  case builds {
    [] -> [build]
    [existing, ..rest] ->
      case existing.id == build.id {
        True -> [build, ..rest]
        False -> [existing, ..put_build(rest, build)]
      }
  }
}

fn composition_metadata(
  changes: List(TaggedChange),
) -> #(List(RevisionInfo), Int) {
  let #(revisions, max_local_id) =
    list.fold(changes, #([], -1), fn(state, tagged) {
      let data = tagged.change.data
      let candidates = tagged_revision_infos(tagged)
      let revisions =
        list.fold(candidates, state.0, fn(revisions, info) {
          case revision_info(revisions, info.revision) {
            Some(_) -> revisions
            None -> list.append(revisions, [info])
          }
        })
      #(revisions, int_max(state.1, data.max_local_id))
    })
  let rollback_revisions =
    revisions
    |> list.fold([], fn(rollbacks, info) {
      case info.rollback_of {
        None -> rollbacks
        Some(revision) -> [revision, ..rollbacks]
      }
    })
  let revisions =
    list.fold(rollback_revisions, revisions, fn(revisions, revision) {
      case revision_info(revisions, revision) {
        Some(_) -> revisions
        None -> list.append(revisions, [RevisionInfo(revision, None)])
      }
    })
  #(revisions, max_local_id)
}

fn balanced_compose(
  changes: List(Changeset),
  revisions: List(RevisionInfo),
  max_local_id: Int,
) -> Result(#(Changeset, List(moves.TraceEvent)), TreeError) {
  case changes {
    [] -> Ok(#(empty(), []))
    [change] -> Ok(#(change, []))
    _ -> {
      let split = list.length(changes) / 2
      let #(left, right) = split_at(changes, split, [])
      use #(left, left_trace) <- result.try(balanced_compose(
        left,
        revisions,
        max_local_id,
      ))
      use #(right, right_trace) <- result.try(balanced_compose(
        right,
        revisions,
        max_local_id,
      ))
      use #(composed, trace) <- result.try(compose_pair(
        left,
        right,
        revisions,
        max_local_id,
      ))
      Ok(#(composed, list.flatten([left_trace, right_trace, trace])))
    }
  }
}

fn split_at(values: List(a), count: Int, left: List(a)) -> #(List(a), List(a)) {
  case count, values {
    0, _ -> #(list.reverse(left), values)
    _, [] -> #(list.reverse(left), [])
    _, [value, ..rest] -> split_at(rest, count - 1, [value, ..left])
  }
}

fn compose_pair(
  first: Changeset,
  second: Changeset,
  revisions: List(RevisionInfo),
  max_local_id: Int,
) -> Result(#(Changeset, List(moves.TraceEvent)), TreeError) {
  use identity_order <- result.try(merge_identity_orders(
    first.identity_order,
    second.identity_order,
  ))
  use first_data <- result.try(composition_data(first.data))
  use second_data <- result.try(composition_data(second.data))
  use aliases <- result.try(merge_aliases(
    first_data.aliases,
    second_data.aliases,
  ))
  let merged_nodes = merge_pairs(first_data.nodes, second_data.nodes)
  let merged_parents = merge_pairs(first_data.parents, second_data.parents)
  use nodes <- result.try(canonicalize_pair_keys(merged_nodes, aliases))
  use parents <- result.try(canonicalize_pair_keys(merged_parents, aliases))
  use first_owners <- result.try(owner_ranges(
    first_data.cross_field_keys,
    moves.FirstOperand,
    first_data.aliases,
  ))
  use second_owners <- result.try(owner_ranges(
    second_data.cross_field_keys,
    moves.SecondOperand,
    second_data.aliases,
  ))
  let state =
    ComposeState(
      nodes,
      parents,
      aliases,
      first_data,
      second_data,
      [],
      [],
      algebra_context(identity_order, revisions),
      moves.with_owners(moves.new(), list.append(first_owners, second_owners)),
      [],
      [],
      [],
    )
  use #(fields, state) <- result.try(compose_field_maps(
    first_data.fields,
    second_data.fields,
    None,
    None,
    state,
  ))
  use state <- result.try(compose_invalidated(state, []))
  let fields = replace_field_results(fields, None, state.field_results)
  let nodes = replace_node_field_results(state.nodes, state.field_results)
  use parents <- result.try(apply_compose_notifications(
    state.parents,
    state.aliases,
    moves.notifications(state.move_context),
  ))
  use #(builds, destroys, refreshers) <- result.try(compose_detached(
    first_data,
    second_data,
  ))
  use cross_field_keys <- result.try(sort_cross_field_keys(
    list.append(first_data.cross_field_keys, second_data.cross_field_keys),
    identity_order,
  ))
  let cross_field_keys = coalesce_cross_field_keys(cross_field_keys)
  use composed <- result.try(from_data(
    ChangeData(
      max_local_id: max_local_id,
      revisions: revisions,
      fields: fields,
      nodes: nodes,
      parents: parents,
      aliases: state.aliases,
      builds: builds,
      destroys: destroys,
      refreshers: refreshers,
      cross_field_keys: cross_field_keys,
      constraint_violation_count: 0,
    ),
    identity_order,
  ))
  Ok(#(composed, moves.trace(state.move_context)))
}

fn canonicalize_pair_keys(
  entries: List(#(AtomId, value)),
  aliases: List(#(AtomId, AtomId)),
) -> Result(List(#(AtomId, value)), TreeError) {
  list.try_fold(entries, [], fn(output, entry) {
    use canonical <- result.try(resolve_alias(entry.0, aliases))
    case canonical != entry.0 && pair_value(entries, canonical) != None {
      True -> Ok(output)
      False ->
        case pair_value(output, canonical) {
          Some(_) -> Ok(output)
          None -> Ok(list.append(output, [#(canonical, entry.1)]))
        }
    }
  })
}

fn compose_field_maps(
  first: List(#(String, FieldChange)),
  second: List(#(String, FieldChange)),
  first_parent: Option(AtomId),
  second_parent: Option(AtomId),
  state: ComposeState,
) -> Result(#(List(#(String, FieldChange)), ComposeState), TreeError) {
  use #(fields, remaining, state) <- result.try(
    list.try_fold(first, #([], second, state), fn(output, entry) {
      let #(other, remaining) = take_pair(output.1, entry.0)
      case other {
        None -> Ok(#(list.append(output.0, [entry]), remaining, output.2))
        Some(other) -> {
          use #(field, state) <- result.try(compose_field(
            entry.1,
            other,
            moves.FieldId(first_parent, entry.0),
            moves.FieldId(second_parent, entry.0),
            output.2,
          ))
          Ok(#(list.append(output.0, [#(entry.0, field)]), remaining, state))
        }
      }
    }),
  )
  Ok(#(list.append(fields, remaining), state))
}

fn compose_field(
  first: FieldChange,
  second: FieldChange,
  field_id: moves.FieldId,
  second_field_id: moves.FieldId,
  state: ComposeState,
) -> Result(#(FieldChange, ComposeState), TreeError) {
  case first, second {
    GenericField(first), GenericField(second) -> {
      use #(children, state) <- result.try(compose_generic(first, second, state))
      Ok(#(GenericField(children), state))
    }
    SequenceField(first), SequenceField(second) -> {
      use first_source <- result.try(normalize_field_id(
        field_id,
        state.first.aliases,
      ))
      use field_id <- result.try(normalize_field_id(field_id, state.aliases))
      let #(_, move_context) =
        moves.take_affected_for(state.move_context, field_id)
      let move_context = moves.enter_field(move_context, "compose", field_id)
      sequence_compose.compose_with_context(
        first,
        second,
        state,
        compose_sequence_child,
        state.algebra,
        field_id,
        move_context,
      )
      |> result.map(fn(output) {
        let field = SequenceField(output.0)
        #(
          field,
          ComposeState(
            ..output.1,
            move_context: output.2,
            work: put_compose_work(
              output.1.work,
              ComposeWork(field_id, field_id, first, second),
            ),
            field_results: put_pair(output.1.field_results, field_id, field),
            affected_seen: [
              moves.Affected(moves.FirstOperand, first_source),
              ..output.1.affected_seen
            ],
          ),
        )
      })
    }
    GenericField(first), SequenceField(second) -> {
      let conversion_field = field_id
      use field_id <- result.try(normalize_field_id(field_id, state.aliases))
      let state =
        ComposeState(
          ..state,
          move_context: moves.record_conversion(
            state.move_context,
            "compose",
            "generic-left",
            conversion_field,
            first,
          ),
        )
      use first <- result.try(generic_as_sequence(first))
      compose_field(
        SequenceField(first),
        SequenceField(second),
        field_id,
        second_field_id,
        state,
      )
    }
    SequenceField(first), GenericField(second) -> {
      let conversion_field = second_field_id
      use field_id <- result.try(normalize_field_id(field_id, state.aliases))
      let state =
        ComposeState(
          ..state,
          move_context: moves.record_conversion(
            state.move_context,
            "compose",
            "generic-right",
            conversion_field,
            second,
          ),
        )
      use second <- result.try(generic_as_sequence(second))
      compose_field(
        SequenceField(first),
        SequenceField(second),
        field_id,
        second_field_id,
        state,
      )
    }
    ValueField(first), ValueField(second) ->
      optional_field.compose(first, second, state, compose_child)
      |> result.map(fn(output) { #(ValueField(output.0), output.1) })
    OptionalField(first), OptionalField(second) ->
      optional_field.compose(first, second, state, compose_child)
      |> result.map(fn(output) { #(OptionalField(output.0), output.1) })
    GenericField(first), ValueField(second) ->
      optional_field.compose(
        generic_as_optional(first),
        second,
        state,
        compose_child,
      )
      |> result.map(fn(output) { #(ValueField(output.0), output.1) })
    ValueField(first), GenericField(second) ->
      optional_field.compose(
        first,
        generic_as_optional(second),
        state,
        compose_child,
      )
      |> result.map(fn(output) { #(ValueField(output.0), output.1) })
    GenericField(first), OptionalField(second) ->
      optional_field.compose(
        generic_as_optional(first),
        second,
        state,
        compose_child,
      )
      |> result.map(fn(output) { #(OptionalField(output.0), output.1) })
    OptionalField(first), GenericField(second) ->
      optional_field.compose(
        first,
        generic_as_optional(second),
        state,
        compose_child,
      )
      |> result.map(fn(output) { #(OptionalField(output.0), output.1) })
    _, _ -> Error(CorruptData("compose", "field kinds do not match"))
  }
}

fn generic_as_optional(
  children: List(#(Int, AtomId)),
) -> optional_field.FieldChange {
  optional_field.FieldChange(
    [],
    list.map(children, fn(child) { #(optional_field.Active, child.1) }),
    None,
  )
}

fn generic_as_sequence(
  children: List(#(Int, AtomId)),
) -> Result(sequence_field.Changeset, TreeError) {
  sequence_field.build_child_changes(children)
}

fn normalize_field_id(
  field: moves.FieldId,
  aliases: List(#(AtomId, AtomId)),
) -> Result(moves.FieldId, TreeError) {
  case field.parent {
    None -> Ok(field)
    Some(parent) ->
      resolve_alias(parent, aliases)
      |> result.map(fn(parent) { moves.FieldId(Some(parent), field.field) })
  }
}

fn put_compose_work(
  work: List(ComposeWork),
  entry: ComposeWork,
) -> List(ComposeWork) {
  let ComposeWork(field, _, _, _) = entry
  case
    list.any(work, fn(existing) {
      let ComposeWork(existing, _, _, _) = existing
      existing == field
    })
  {
    True -> work
    False -> list.append(work, [entry])
  }
}

fn put_rebase_work(
  work: List(RebaseWork),
  entry: RebaseWork,
) -> List(RebaseWork) {
  let RebaseWork(field, _, _, _) = entry
  case
    list.any(work, fn(existing) {
      let RebaseWork(existing, _, _, _) = existing
      existing == field
    })
  {
    True -> work
    False -> list.append(work, [entry])
  }
}

fn put_rebase_field_work(
  work: List(RebaseFieldWork),
  entry: RebaseFieldWork,
) -> List(RebaseFieldWork) {
  let RebaseFieldWork(source, _, _, _) = entry
  case
    list.any(work, fn(existing) {
      let RebaseFieldWork(existing, _, _, _) = existing
      existing == source
    })
  {
    True ->
      list.map(work, fn(existing) {
        let RebaseFieldWork(found, _, _, _) = existing
        case found == source {
          True -> entry
          False -> existing
        }
      })
    False -> list.append(work, [entry])
  }
}

fn put_invert_work(
  work: List(InvertWork),
  entry: InvertWork,
) -> List(InvertWork) {
  let InvertWork(field, _) = entry
  case
    list.any(work, fn(existing) {
      let InvertWork(existing, _) = existing
      existing == field
    })
  {
    True -> work
    False -> list.append(work, [entry])
  }
}

fn compose_affected_work_for(
  state: ComposeState,
  affected: moves.Affected,
) -> Result(ComposeWork, TreeError) {
  let moves.Affected(origin, source) = affected
  use result_field <- result.try(normalize_field_id(source, state.aliases))
  use #(first_field, second_field) <- result.try(compose_operand_fields(
    origin,
    source,
    state,
  ))
  use first <- result.try(optional_sequence_field_for(state.first, first_field))
  use second <- result.try(optional_sequence_field_for(
    state.second,
    second_field,
  ))
  use empty <- result.try(sequence_field.from_marks([]))
  case first, second {
    None, None ->
      Error(CorruptData("compose", "affected sequence field is unknown"))
    _, _ ->
      Ok(ComposeWork(
        source,
        result_field,
        option.unwrap(first, empty),
        option.unwrap(second, empty),
      ))
  }
}

fn compose_operand_fields(
  origin: moves.Origin,
  source: moves.FieldId,
  state: ComposeState,
) -> Result(#(Option(moves.FieldId), Option(moves.FieldId)), TreeError) {
  case origin, source.parent {
    moves.FirstOperand, None -> Ok(#(Some(source), Some(source)))
    moves.SecondOperand, None -> Ok(#(Some(source), Some(source)))
    moves.FirstOperand, Some(parent) -> {
      use parent <- result.try(resolve_alias(parent, state.first.aliases))
      let other =
        list.find(state.pairs, fn(pair) { pair.0 == parent })
        |> result.map(fn(pair) {
          Some(moves.FieldId(Some(pair.1), source.field))
        })
        |> result.unwrap(None)
      Ok(#(Some(source), other))
    }
    moves.SecondOperand, Some(parent) -> {
      use parent <- result.try(resolve_alias(parent, state.second.aliases))
      let other =
        list.find(state.pairs, fn(pair) { pair.1 == parent })
        |> result.map(fn(pair) {
          Some(moves.FieldId(Some(pair.0), source.field))
        })
        |> result.unwrap(None)
      Ok(#(other, Some(source)))
    }
    moves.BaseOperand, _ ->
      Error(CorruptData("compose", "affected field has the wrong origin"))
  }
}

fn optional_sequence_field_for(
  data: ChangeData,
  field: Option(moves.FieldId),
) -> Result(Option(sequence_field.Changeset), TreeError) {
  case field {
    None -> Ok(None)
    Some(field) -> sequence_field_for(data, field)
  }
}

fn rebase_work_for(
  state: RebaseState,
  field: moves.FieldId,
) -> Result(#(Option(RebaseWork), RebaseState), TreeError) {
  case find_rebase_work_by_source(state.work, field) {
    Ok(_) -> Ok(#(None, state))
    Error(_) -> {
      use authored <- result.try(sequence_field_for(state.authored, field))
      use base <- result.try(sequence_field_for(state.base, field))
      use empty <- result.try(sequence_field.from_marks([]))
      case base {
        None ->
          Error(CorruptData("rebase", "affected sequence field is unknown"))
        Some(base) -> {
          use #(result_field, state) <- result.try(rebased_field_id(
            state,
            field,
          ))
          Ok(#(
            Some(RebaseWork(
              field,
              result_field,
              option.unwrap(authored, empty),
              base,
            )),
            state,
          ))
        }
      }
    }
  }
}

fn sequence_field_for(
  data: ChangeData,
  field: moves.FieldId,
) -> Result(Option(sequence_field.Changeset), TreeError) {
  let fields = case field.parent {
    None -> Ok(data.fields)
    Some(parent) -> {
      use parent <- result.try(resolve_alias(parent, data.aliases))
      case pair_value(data.nodes, parent) {
        None -> Ok([])
        Some(NodeChange(fields:, ..)) -> Ok(fields)
      }
    }
  }
  use fields <- result.try(fields)
  case pair_value(fields, field.field) {
    None -> Ok(None)
    Some(SequenceField(change)) -> Ok(Some(change))
    Some(_) ->
      Error(CorruptData("sequence fields", "owned field is not a sequence"))
  }
}

fn owner_ranges(
  keys: List(CrossFieldKey),
  origin: moves.Origin,
  aliases: List(#(AtomId, AtomId)),
) -> Result(List(moves.OwnerRange), TreeError) {
  list.try_map(keys, fn(entry) {
    use field <- result.try(normalize_field_id(entry.field, aliases))
    Ok(moves.OwnerRange(entry.key, entry.count, origin, field, field))
  })
}

fn rebased_field_id(
  state: RebaseState,
  field: moves.FieldId,
) -> Result(#(moves.FieldId, RebaseState), TreeError) {
  case field.parent {
    None -> Ok(#(field, state))
    Some(parent) -> {
      use parent <- result.try(resolve_alias(parent, state.base.aliases))
      use #(parent, state) <- result.try(ensure_rebased_parent(parent, state))
      Ok(#(moves.FieldId(Some(parent), field.field), state))
    }
  }
}

fn ensure_rebased_parent(
  base: AtomId,
  state: RebaseState,
) -> Result(#(AtomId, RebaseState), TreeError) {
  case pair_value(state.base_to_rebased, base) {
    Some(rebased) -> Ok(#(rebased, state))
    None -> {
      use parent <- result.try(parent_for(base, state.base.parents))
      let ParentField(parent_id, field) = parent
      use #(base_parent, rebased_parent, state) <- result.try(case parent_id {
        None -> Ok(#(None, None, state))
        Some(parent_id) -> {
          use parent_id <- result.try(resolve_alias(
            parent_id,
            state.base.aliases,
          ))
          use #(rebased_parent, state) <- result.try(ensure_rebased_parent(
            parent_id,
            state,
          ))
          Ok(#(Some(parent_id), Some(rebased_parent), state))
        }
      })
      let state =
        RebaseState(
          ..state,
          nodes: put_pair(state.nodes, base, node_change([])),
          base_to_rebased: put_pair(state.base_to_rebased, base, base),
        )
      let source_field = moves.FieldId(base_parent, field)
      let result_field = moves.FieldId(rebased_parent, field)
      use #(authored, base_field, result_field) <- result.try(
        rebase_parent_field_work(state, source_field, result_field),
      )
      let field_work =
        put_rebase_field_work(
          state.field_work,
          RebaseFieldWork(source_field, result_field, authored, base_field),
        )
      case authored, base_field {
        SequenceField(authored), SequenceField(base_field) ->
          Ok(#(
            base,
            RebaseState(..state, field_work:, pending_fields: [
              RebaseWork(source_field, result_field, authored, base_field),
              ..state.pending_fields
            ]),
          ))
        _, _ -> {
          use #(rebased_field, state) <- result.try(rebase_field(
            authored,
            base_field,
            result_field,
            source_field,
            state,
          ))
          Ok(#(
            base,
            RebaseState(
              ..state,
              field_work:,
              field_results: put_pair(
                state.field_results,
                result_field,
                rebased_field,
              ),
            ),
          ))
        }
      }
    }
  }
}

fn rebase_parent_field_work(
  state: RebaseState,
  source_field: moves.FieldId,
  result_field: moves.FieldId,
) -> Result(#(FieldChange, FieldChange, moves.FieldId), TreeError) {
  case
    list.find(state.field_work, fn(work) {
      let RebaseFieldWork(source, _, _, _) = work
      source == source_field
    })
  {
    Ok(RebaseFieldWork(_, result, authored, base)) ->
      Ok(#(authored, base, result))
    Error(_) -> {
      use base <- result.try(field_change_for(state.base, source_field))
      use base <- result.try(
        base
        |> option.to_result(CorruptData(
          "rebase",
          "affected child parent field is missing",
        )),
      )
      use authored <- result.try(empty_field_change(base))
      Ok(#(authored, base, result_field))
    }
  }
}

fn field_change_for(
  data: ChangeData,
  field: moves.FieldId,
) -> Result(Option(FieldChange), TreeError) {
  let fields = case field.parent {
    None -> Ok(data.fields)
    Some(parent) -> {
      use parent <- result.try(resolve_alias(parent, data.aliases))
      case pair_value(data.nodes, parent) {
        None -> Ok([])
        Some(NodeChange(fields:, ..)) -> Ok(fields)
      }
    }
  }
  use fields <- result.try(fields)
  Ok(pair_value(fields, field.field))
}

fn empty_field_change(field: FieldChange) -> Result(FieldChange, TreeError) {
  case field {
    GenericField(_) -> Ok(GenericField([]))
    SequenceField(_) -> {
      use empty <- result.try(sequence_field.from_marks([]))
      Ok(SequenceField(empty))
    }
    ValueField(_) -> Ok(ValueField(optional_field.FieldChange([], [], None)))
    OptionalField(_) ->
      Ok(OptionalField(optional_field.FieldChange([], [], None)))
  }
}

fn compose_invalidated(
  state: ComposeState,
  processed: List(#(moves.FieldId, FieldChange, moves.Context)),
) -> Result(ComposeState, TreeError) {
  case state.pending_pairs {
    [pair, ..rest] -> {
      use #(_, state) <- result.try(compose_nodes(
        pair.0,
        pair.1,
        ComposeState(..state, pending_pairs: rest),
      ))
      compose_invalidated(state, processed)
    }
    [] -> compose_field_work(state, processed)
  }
}

fn compose_field_work(
  state: ComposeState,
  processed: List(#(moves.FieldId, FieldChange, moves.Context)),
) -> Result(ComposeState, TreeError) {
  let #(affected, move_context) = moves.take_affected(state.move_context)
  let state = ComposeState(..state, move_context:)
  case affected, moves.invalidated(state.move_context) {
    [affected, ..rest], _ -> {
      let move_context =
        list.fold(rest, move_context, fn(context, affected) {
          moves.queue_affected(context, affected)
        })
      case list.contains(state.affected_seen, affected) {
        True ->
          compose_invalidated(ComposeState(..state, move_context:), processed)
        False -> {
          use work <- result.try(compose_affected_work_for(state, affected))
          let ComposeWork(field, result_field, first, second) = work
          let #(_, move_context) =
            moves.take_invalidated_for(move_context, field)
          let move_context = moves.enter_field(move_context, "compose", field)
          use #(change, next, move_context) <- result.try(
            sequence_compose.compose_with_context(
              first,
              second,
              state,
              compose_sequence_child,
              state.algebra,
              field,
              move_context,
            ),
          )
          let result = SequenceField(change)
          compose_invalidated(
            ComposeState(
              ..next,
              move_context:,
              work: put_compose_work(next.work, work),
              field_results: put_pair(next.field_results, result_field, result),
              affected_seen: [affected, ..next.affected_seen],
            ),
            processed,
          )
        }
      }
    }
    [], [] -> Ok(state)
    [], [field, ..] -> {
      use work <- result.try(find_compose_work(state.work, field))
      let #(found, move_context) =
        moves.take_invalidated_for(state.move_context, field)
      use _ <- result.try(check(
        found,
        "compose",
        "invalidated sequence field has no pending work",
      ))
      let ComposeWork(_, result_field, first, second) = work
      let move_context = moves.enter_field(move_context, "compose", field)
      use #(change, next, move_context) <- result.try(
        sequence_compose.compose_with_context(
          first,
          second,
          state,
          compose_sequence_child,
          state.algebra,
          field,
          move_context,
        ),
      )
      let result = SequenceField(change)
      use _ <- result.try(check(
        !list.any(processed, fn(previous) {
          previous.0 == field
          && previous.1 == result
          && moves.same_work_state(previous.2, move_context)
        }),
        "compose",
        "sequence field reprocessing made no progress",
      ))
      compose_invalidated(
        ComposeState(
          ..next,
          move_context:,
          field_results: put_pair(next.field_results, result_field, result),
        ),
        [#(field, result, move_context), ..processed],
      )
    }
  }
}

fn rebase_invalidated(
  state: RebaseState,
  processed: List(#(moves.FieldId, FieldChange, moves.Context)),
) -> Result(RebaseState, TreeError) {
  case state.pending_pairs {
    [pair, ..rest] -> {
      use #(_, state) <- result.try(rebase_nodes(
        pair.0,
        pair.1,
        RebaseState(..state, pending_pairs: rest),
      ))
      rebase_invalidated(state, processed)
    }
    [] ->
      case state.pending_fields {
        [work, ..rest] -> {
          let RebaseWork(source_field, result_field, authored, base) = work
          let move_context =
            moves.enter_field(state.move_context, "rebase", source_field)
          use #(change, state, move_context) <- result.try(
            sequence_rebase.rebase_with_context(
              authored,
              base,
              RebaseState(..state, pending_fields: rest),
              rebase_sequence_child,
              state.algebra,
              source_field,
              move_context,
            ),
          )
          let result = SequenceField(change)
          rebase_invalidated(
            RebaseState(
              ..state,
              move_context:,
              work: put_rebase_work(state.work, work),
              field_results: put_pair(state.field_results, result_field, result),
            ),
            processed,
          )
        }
        [] -> rebase_field_work(state, processed)
      }
  }
}

fn rebase_field_work(
  state: RebaseState,
  processed: List(#(moves.FieldId, FieldChange, moves.Context)),
) -> Result(RebaseState, TreeError) {
  let #(affected, move_context) = moves.take_affected(state.move_context)
  let state = RebaseState(..state, move_context:)
  case affected, moves.invalidated(state.move_context) {
    [affected, ..rest], _ -> {
      let moves.Affected(_, source_field) = affected
      use #(work, state) <- result.try(rebase_work_for(state, source_field))
      case work {
        None -> {
          let move_context =
            list.fold(rest, state.move_context, fn(context, affected) {
              moves.queue_affected(context, affected)
            })
          rebase_invalidated(
            RebaseState(..state, move_context: move_context),
            processed,
          )
        }
        Some(work) -> {
          let RebaseWork(_, result_field, authored, base) = work
          let #(_, move_context) =
            moves.take_invalidated_for(state.move_context, result_field)
          let move_context =
            moves.enter_field(move_context, "rebase", result_field)
          use #(change, next, move_context) <- result.try(
            sequence_rebase.rebase_with_context(
              authored,
              base,
              state,
              rebase_sequence_child,
              state.algebra,
              result_field,
              move_context,
            ),
          )
          let result = SequenceField(change)
          let move_context =
            list.fold(rest, move_context, fn(context, affected) {
              moves.queue_affected(context, affected)
            })
          rebase_invalidated(
            RebaseState(
              ..next,
              move_context:,
              work: put_rebase_work(next.work, work),
              field_results: put_pair(next.field_results, result_field, result),
            ),
            processed,
          )
        }
      }
    }
    [], [] -> Ok(state)
    [], [field, ..] -> {
      use work <- result.try(find_rebase_work(state.work, field))
      let #(found, move_context) =
        moves.take_invalidated_for(state.move_context, field)
      use _ <- result.try(check(
        found,
        "rebase",
        "invalidated sequence field has no pending work",
      ))
      let RebaseWork(_, result_field, authored, base) = work
      let move_context = moves.enter_field(move_context, "rebase", field)
      use #(change, next, move_context) <- result.try(
        sequence_rebase.rebase_with_context(
          authored,
          base,
          state,
          rebase_sequence_child,
          state.algebra,
          result_field,
          move_context,
        ),
      )
      let result = SequenceField(change)
      use _ <- result.try(check(
        !list.any(processed, fn(previous) {
          previous.0 == field
          && previous.1 == result
          && moves.same_work_state(previous.2, move_context)
        }),
        "rebase",
        "sequence field reprocessing made no progress",
      ))
      rebase_invalidated(
        RebaseState(
          ..next,
          move_context:,
          field_results: put_pair(next.field_results, result_field, result),
        ),
        [#(field, result, move_context), ..processed],
      )
    }
  }
}

fn invert_invalidated(
  state: InvertState,
  is_rollback: Bool,
  inverse_revision: StableId,
  processed: List(#(moves.FieldId, FieldChange, moves.Context)),
) -> Result(InvertState, TreeError) {
  case moves.invalidated(state.move_context) {
    [] -> Ok(state)
    [field, ..] -> {
      use work <- result.try(find_invert_work(state.work, field))
      let #(found, move_context) =
        moves.take_invalidated_for(state.move_context, field)
      use _ <- result.try(check(
        found,
        "invert",
        "invalidated sequence field has no pending work",
      ))
      let InvertWork(_, change) = work
      let move_context = moves.enter_field(move_context, "invert", field)
      use #(change, aliases, move_context) <- result.try(sequence_invert.invert(
        change,
        is_rollback,
        state.aliases,
        sequence_field.alias,
        Some(inverse_revision),
        field,
        move_context,
      ))
      let result = SequenceField(change)
      use _ <- result.try(check(
        !list.any(processed, fn(previous) {
          previous.0 == field
          && previous.1 == result
          && moves.same_work_state(previous.2, move_context)
        }),
        "invert",
        "sequence field reprocessing made no progress",
      ))
      invert_invalidated(
        InvertState(
          ..state,
          aliases:,
          move_context:,
          field_results: put_pair(state.field_results, field, result),
        ),
        is_rollback,
        inverse_revision,
        [#(field, result, move_context), ..processed],
      )
    }
  }
}

fn find_compose_work(
  work: List(ComposeWork),
  field: moves.FieldId,
) -> Result(ComposeWork, TreeError) {
  list.find(work, fn(entry) {
    let ComposeWork(found, _, _, _) = entry
    found == field
  })
  |> result.map_error(fn(_) {
    CorruptData("compose", "invalidated sequence field is unknown")
  })
}

fn find_rebase_work(
  work: List(RebaseWork),
  field: moves.FieldId,
) -> Result(RebaseWork, TreeError) {
  list.find(work, fn(entry) {
    let RebaseWork(_, found, _, _) = entry
    found == field
  })
  |> result.map_error(fn(_) {
    CorruptData("rebase", "invalidated sequence field is unknown")
  })
}

fn find_rebase_work_by_source(
  work: List(RebaseWork),
  field: moves.FieldId,
) -> Result(RebaseWork, Nil) {
  list.find(work, fn(entry) {
    let RebaseWork(found, _, _, _) = entry
    found == field
  })
}

fn find_invert_work(
  work: List(InvertWork),
  field: moves.FieldId,
) -> Result(InvertWork, TreeError) {
  list.find(work, fn(entry) {
    let InvertWork(found, _) = entry
    found == field
  })
  |> result.map_error(fn(_) {
    CorruptData("invert", "invalidated sequence field is unknown")
  })
}

fn replace_field_results(
  fields: List(#(String, FieldChange)),
  parent: Option(AtomId),
  replacements: List(#(moves.FieldId, FieldChange)),
) -> List(#(String, FieldChange)) {
  let replaced =
    list.map(fields, fn(entry) {
      let field = moves.FieldId(parent, entry.0)
      #(entry.0, option.unwrap(pair_value(replacements, field), entry.1))
    })
  list.fold(replacements, replaced, fn(fields, replacement) {
    case
      replacement.0.parent == parent
      && pair_value(fields, replacement.0.field) == None
    {
      True -> list.append(fields, [#(replacement.0.field, replacement.1)])
      False -> fields
    }
  })
}

fn replace_node_field_results(
  nodes: List(#(AtomId, NodeChange)),
  replacements: List(#(moves.FieldId, FieldChange)),
) -> List(#(AtomId, NodeChange)) {
  list.map(nodes, fn(entry) {
    let NodeChange(fields: fields, ..) = entry.1
    #(
      entry.0,
      NodeChange(
        ..entry.1,
        fields: replace_field_results(fields, Some(entry.0), replacements),
      ),
    )
  })
}

fn apply_compose_notifications(
  parents: List(#(AtomId, ParentField)),
  aliases: List(#(AtomId, AtomId)),
  notifications: List(moves.Notification),
) -> Result(List(#(AtomId, ParentField)), TreeError) {
  list.try_fold(notifications, parents, fn(parents, notification) {
    case notification {
      moves.NodeMoved(node, field) -> {
        use node <- result.try(resolve_alias(node, aliases))
        use field <- result.try(normalize_field_id(field, aliases))
        Ok(put_pair(parents, node, ParentField(field.parent, field.field)))
      }
      moves.KeyMoved(_, _, _) ->
        Error(types.UnsupportedFeature("sequence compose", "key relocation"))
    }
  })
}

fn apply_rebase_notifications(
  parents: List(#(AtomId, ParentField)),
  aliases: List(#(AtomId, AtomId)),
  notifications: List(moves.Notification),
) -> Result(List(#(AtomId, ParentField)), TreeError) {
  list.try_fold(notifications, parents, fn(parents, notification) {
    case notification {
      moves.NodeMoved(node, field) -> {
        use node <- result.try(resolve_alias(node, aliases))
        use field <- result.try(normalize_field_id(field, aliases))
        Ok(put_pair(parents, node, ParentField(field.parent, field.field)))
      }
      moves.KeyMoved(_, _, _) -> Ok(parents)
    }
  })
}

fn apply_rebase_key_notifications(
  keys: List(CrossFieldKey),
  aliases: List(#(AtomId, AtomId)),
  notifications: List(moves.Notification),
  identity_order: IdentityOrder,
) -> Result(List(CrossFieldKey), TreeError) {
  use keys <- result.try(
    list.try_fold(notifications, keys, fn(keys, notification) {
      case notification {
        moves.NodeMoved(_, _) -> Ok(keys)
        moves.KeyMoved(key, count, field) -> {
          use field <- result.try(normalize_field_id(field, aliases))
          Ok(move_cross_field_key(keys, key, count, field))
        }
      }
    }),
  )
  use keys <- result.try(sort_cross_field_keys(keys, identity_order))
  Ok(coalesce_cross_field_keys(keys))
}

fn move_cross_field_key(
  keys: List(CrossFieldKey),
  moved: moves.Key,
  count: Int,
  field: moves.FieldId,
) -> List(CrossFieldKey) {
  list.flat_map(keys, fn(entry) {
    let CrossFieldKey(key, entry_count, owner) = entry
    let moves.Key(side, revision, start) = key
    let moves.Key(moved_side, moved_revision, moved_start) = moved
    let entry_end = start + entry_count
    let moved_end = moved_start + count
    case
      side == moved_side
      && revision == moved_revision
      && start < moved_end
      && moved_start < entry_end
    {
      False -> [entry]
      True -> {
        let overlap_start = int.max(start, moved_start)
        let overlap_end = int.min(entry_end, moved_end)
        list.flatten([
          case overlap_start > start {
            True -> [CrossFieldKey(key, overlap_start - start, owner)]
            False -> []
          },
          [
            CrossFieldKey(
              moves.Key(side, revision, overlap_start),
              overlap_end - overlap_start,
              field,
            ),
          ],
          case overlap_end < entry_end {
            True -> [
              CrossFieldKey(
                moves.Key(side, revision, overlap_end),
                entry_end - overlap_end,
                owner,
              ),
            ]
            False -> []
          },
        ])
      }
    }
  })
}

fn compose_generic(
  first: List(#(Int, AtomId)),
  second: List(#(Int, AtomId)),
  state: ComposeState,
) -> Result(#(List(#(Int, AtomId)), ComposeState), TreeError) {
  use #(children, remaining, state) <- result.try(
    list.try_fold(first, #([], second, state), fn(output, child) {
      let #(other, remaining) = take_pair(output.1, child.0)
      use #(id, state) <- result.try(compose_child(
        Some(child.1),
        other,
        output.2,
      ))
      Ok(#(list.append(output.0, [#(child.0, id)]), remaining, state))
    }),
  )
  use #(children, state) <- result.try(
    list.try_fold(remaining, #(children, state), fn(output, child) {
      use #(id, state) <- result.try(compose_child(
        None,
        Some(child.1),
        output.1,
      ))
      Ok(#(list.append(output.0, [#(child.0, id)]), state))
    }),
  )
  Ok(#(children, state))
}

fn compose_child(
  first: Option(AtomId),
  second: Option(AtomId),
  state: ComposeState,
) -> Result(#(AtomId, ComposeState), TreeError) {
  case first, second {
    Some(first), Some(second) -> queue_compose_nodes(first, second, state)
    Some(first), None -> Ok(#(first, state))
    None, Some(second) -> Ok(#(second, state))
    None, None -> Error(CorruptData("compose", "child changes are missing"))
  }
}

fn queue_compose_nodes(
  first: AtomId,
  second: AtomId,
  state: ComposeState,
) -> Result(#(AtomId, ComposeState), TreeError) {
  use first <- result.try(resolve_alias(first, state.first.aliases))
  use second <- result.try(resolve_alias(second, state.second.aliases))
  use canonical <- result.try(resolve_alias(first, state.aliases))
  let pair = #(first, second)
  let pending_pairs = case
    list.contains(state.pairs, pair) || list.contains(state.pending_pairs, pair)
  {
    True -> state.pending_pairs
    False -> list.append(state.pending_pairs, [pair])
  }
  Ok(#(canonical, ComposeState(..state, pending_pairs:)))
}

fn compose_sequence_child(
  first: Option(AtomId),
  second: Option(AtomId),
  state: ComposeState,
  move_context: moves.Context,
) -> Result(#(AtomId, ComposeState, moves.Context), TreeError) {
  case first, second {
    Some(first), Some(second) -> {
      use #(child, state) <- result.try(queue_compose_nodes(
        first,
        second,
        ComposeState(..state, move_context: move_context),
      ))
      Ok(#(child, state, state.move_context))
    }
    Some(first), None ->
      Ok(#(first, ComposeState(..state, move_context:), move_context))
    None, Some(second) ->
      Ok(#(second, ComposeState(..state, move_context:), move_context))
    None, None -> Error(CorruptData("compose", "child changes are missing"))
  }
}

fn compose_nodes(
  first: AtomId,
  second: AtomId,
  state: ComposeState,
) -> Result(#(AtomId, ComposeState), TreeError) {
  use first_id <- result.try(resolve_alias(first, state.first.aliases))
  use second_id <- result.try(resolve_alias(second, state.second.aliases))
  case list.contains(state.pairs, #(first_id, second_id)) {
    True -> {
      use canonical <- result.try(resolve_alias(first_id, state.aliases))
      Ok(#(canonical, state))
    }
    False -> {
      use first_node <- result.try(node_for(first_id, state.first.nodes))
      use second_node <- result.try(node_for(second_id, state.second.nodes))
      let NodeChange(fields: first_fields, ..) = first_node
      let NodeChange(fields: second_fields, ..) = second_node
      use first_canonical <- result.try(resolve_alias(first_id, state.aliases))
      use second_canonical <- result.try(resolve_alias(second_id, state.aliases))
      use #(canonical, aliases) <- result.try(unify_aliases(
        state.aliases,
        second_canonical,
        first_canonical,
      ))
      let move_context =
        moves.replace_parent(state.move_context, second_canonical, canonical)
      let state =
        ComposeState(
          ..state,
          pairs: [#(first_id, second_id), ..state.pairs],
          aliases:,
          move_context:,
        )
      use #(fields, state) <- result.try(compose_field_maps(
        first_fields,
        second_fields,
        Some(first_id),
        Some(second_id),
        state,
      ))
      let node_exists_constraint = case first_node.node_exists_constraint {
        Some(constraint) -> Some(constraint)
        None -> second_node.node_exists_constraint
      }
      let node_exists_constraint_on_revert = case
        first_node.node_exists_constraint_on_revert
      {
        Some(constraint) -> Some(constraint)
        None -> second_node.node_exists_constraint_on_revert
      }
      use parent <- result.try(parent_for(first_id, state.first.parents))
      use parent <- result.try(normalize_parent(parent, aliases))
      let nodes =
        state.nodes
        |> remove_pair(first_canonical)
        |> remove_pair(second_canonical)
        |> put_pair(
          canonical,
          NodeChange(
            fields: fields,
            node_exists_constraint:,
            node_exists_constraint_on_revert:,
          ),
        )
      let parents =
        state.parents
        |> remove_pair(first_canonical)
        |> remove_pair(second_canonical)
        |> put_pair(canonical, parent)
      Ok(#(canonical, ComposeState(..state, nodes: nodes, parents: parents)))
    }
  }
}

fn merge_aliases(
  first: List(#(AtomId, AtomId)),
  second: List(#(AtomId, AtomId)),
) -> Result(List(#(AtomId, AtomId)), TreeError) {
  list.try_fold(second, first, fn(aliases, entry) {
    unify_aliases(aliases, entry.0, entry.1)
    |> result.map(fn(output) { output.1 })
  })
}

fn unify_aliases(
  aliases: List(#(AtomId, AtomId)),
  first: AtomId,
  second: AtomId,
) -> Result(#(AtomId, List(#(AtomId, AtomId))), TreeError) {
  use first <- result.try(resolve_alias(first, aliases))
  use second <- result.try(resolve_alias(second, aliases))
  case first == second {
    True -> Ok(#(second, aliases))
    False -> Ok(#(second, put_pair(aliases, first, second)))
  }
}

fn compose_detached(
  first: ChangeData,
  second: ChangeData,
) -> Result(
  #(List(forest.Build), List(forest.Destroy), List(forest.Build)),
  TreeError,
) {
  let builds = merge_builds(first.builds, second.builds)
  let destroys = merge_destroys(first.destroys, second.destroys)
  let refreshers = merge_builds(first.refreshers, second.refreshers)
  use #(builds, destroys) <- result.try(cancel_destroy_builds(
    first.destroys,
    second.builds,
    builds,
    destroys,
  ))
  use #(builds, destroys) <- result.try(cancel_build_destroys(
    first.builds,
    second.destroys,
    builds,
    destroys,
  ))
  Ok(#(builds, destroys, refreshers))
}

fn cancel_destroy_builds(
  destroys_before: List(forest.Destroy),
  builds_after: List(forest.Build),
  builds: List(forest.Build),
  destroys: List(forest.Destroy),
) -> Result(#(List(forest.Build), List(forest.Destroy)), TreeError) {
  list.try_fold(builds_after, #(builds, destroys), fn(output, build) {
    case destroy_for(destroys_before, build.id) {
      None -> Ok(output)
      Some(destroy) -> {
        use _ <- result.try(check(
          destroy.count == list.length(build.trees),
          "compose",
          "build and destroy lengths do not match",
        ))
        Ok(#(
          remove_build(output.0, build.id),
          remove_destroy(output.1, build.id),
        ))
      }
    }
  })
}

fn cancel_build_destroys(
  builds_before: List(forest.Build),
  destroys_after: List(forest.Destroy),
  builds: List(forest.Build),
  destroys: List(forest.Destroy),
) -> Result(#(List(forest.Build), List(forest.Destroy)), TreeError) {
  list.try_fold(destroys_after, #(builds, destroys), fn(output, destroy) {
    case build_for(builds_before, destroy.id) {
      None -> Ok(output)
      Some(build) -> {
        use _ <- result.try(check(
          destroy.count == list.length(build.trees),
          "compose",
          "build and destroy lengths do not match",
        ))
        Ok(#(
          remove_build(output.0, destroy.id),
          remove_destroy(output.1, destroy.id),
        ))
      }
    }
  })
}

fn merge_builds(
  first: List(forest.Build),
  second: List(forest.Build),
) -> List(forest.Build) {
  list.fold(second, first, fn(builds, build) {
    case build_for(builds, build.id) {
      Some(_) -> builds
      None -> list.append(builds, [build])
    }
  })
}

fn merge_destroys(
  first: List(forest.Destroy),
  second: List(forest.Destroy),
) -> List(forest.Destroy) {
  list.fold(second, first, fn(destroys, destroy) {
    case destroy_for(destroys, destroy.id) {
      Some(_) -> destroys
      None -> list.append(destroys, [destroy])
    }
  })
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn build_for(builds: List(forest.Build), id: AtomId) -> Option(forest.Build) {
  case builds {
    [] -> None
    [build, ..rest] ->
      case build.id == id {
        True -> Some(build)
        False -> build_for(rest, id)
      }
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn destroy_for(
  destroys: List(forest.Destroy),
  id: AtomId,
) -> Option(forest.Destroy) {
  case destroys {
    [] -> None
    [destroy, ..rest] ->
      case destroy.id == id {
        True -> Some(destroy)
        False -> destroy_for(rest, id)
      }
  }
}

fn remove_build(builds: List(forest.Build), id: AtomId) -> List(forest.Build) {
  list.filter(builds, fn(build) { build.id != id })
}

fn remove_destroy(
  destroys: List(forest.Destroy),
  id: AtomId,
) -> List(forest.Destroy) {
  list.filter(destroys, fn(destroy) { destroy.id != id })
}

fn sort_atom_tables(
  data: ChangeData,
  identity_order: IdentityOrder,
) -> Result(ChangeData, TreeError) {
  use nodes <- result.try(sort_by_atom(
    data.nodes,
    fn(entry) { entry.0 },
    identity_order,
  ))
  use parents <- result.try(sort_by_atom(
    data.parents,
    fn(entry) { entry.0 },
    identity_order,
  ))
  use aliases <- result.try(sort_by_atom(
    data.aliases,
    fn(entry) { entry.0 },
    identity_order,
  ))
  use builds <- result.try(sort_by_atom(
    data.builds,
    fn(build) { build.id },
    identity_order,
  ))
  use destroys <- result.try(sort_by_atom(
    data.destroys,
    fn(destroy) { destroy.id },
    identity_order,
  ))
  use refreshers <- result.try(sort_by_atom(
    data.refreshers,
    fn(build) { build.id },
    identity_order,
  ))
  Ok(
    ChangeData(
      ..data,
      nodes: nodes,
      parents: parents,
      aliases: aliases,
      builds: builds,
      destroys: destroys,
      refreshers: refreshers,
    ),
  )
}

fn sort_by_atom(
  entries: List(a),
  atom: fn(a) -> AtomId,
  identity_order: IdentityOrder,
) -> Result(List(a), TreeError) {
  list.try_fold(entries, [], fn(sorted, entry) {
    insert_by_atom(entry, sorted, atom, identity_order)
  })
}

fn insert_by_atom(
  entry: a,
  entries: List(a),
  atom: fn(a) -> AtomId,
  identity_order: IdentityOrder,
) -> Result(List(a), TreeError) {
  case entries {
    [] -> Ok([entry])
    [first, ..rest] -> {
      use ordering <- result.try(compare_atom(
        atom(entry),
        atom(first),
        identity_order,
      ))
      case ordering {
        order.Lt | order.Eq -> Ok([entry, ..entries])
        order.Gt -> {
          use rest <- result.try(insert_by_atom(
            entry,
            rest,
            atom,
            identity_order,
          ))
          Ok([first, ..rest])
        }
      }
    }
  }
}

fn compare_atom(
  left: AtomId,
  right: AtomId,
  identity_order: IdentityOrder,
) -> Result(order.Order, TreeError) {
  use revision_order <- result.try(compare_revision(
    left.revision,
    right.revision,
    identity_order,
  ))
  case revision_order {
    order.Eq -> Ok(int_compare(left.local_id, right.local_id))
    _ -> Ok(revision_order)
  }
}

fn compare_revision(
  left: Option(StableId),
  right: Option(StableId),
  identity_order: IdentityOrder,
) -> Result(order.Order, TreeError) {
  case left, right {
    None, None -> Ok(order.Eq)
    None, Some(_) -> Ok(order.Lt)
    Some(_), None -> Ok(order.Gt)
    Some(left), Some(right) -> {
      use left <- result.try(identity_key(identity_order, left))
      use right <- result.try(identity_key(identity_order, right))
      Ok(int_compare(left, right))
    }
  }
}

fn merge_identity_orders(
  first: IdentityOrder,
  second: IdentityOrder,
) -> Result(IdentityOrder, TreeError) {
  let IdentityOrder(first) = first
  let IdentityOrder(second) = second
  use entries <- result.try(
    list.try_fold(second, first, fn(entries, entry) {
      case pair_value(entries, entry.0) {
        Some(key) ->
          case key == entry.1 {
            True -> Ok(entries)
            False ->
              Error(InvalidHistory(
                "identity orders assign different keys to a revision",
              ))
          }
        None ->
          case revision_for_identity_key(entries, entry.1) {
            Some(_) ->
              Error(InvalidHistory(
                "identity orders assign one key to different revisions",
              ))
            None -> Ok(list.append(entries, [entry]))
          }
      }
    }),
  )
  Ok(IdentityOrder(entries))
}

fn identity_key(
  identity_order: IdentityOrder,
  revision: StableId,
) -> Result(Int, TreeError) {
  let IdentityOrder(entries) = identity_order
  case pair_value(entries, revision) {
    Some(key) -> Ok(key)
    None ->
      Error(InvalidHistory(
        "identity order is missing revision "
        <> fluid_ids.stable_id_to_string(revision),
      ))
  }
}

fn require_identity_revision(
  identity_order: IdentityOrder,
  revision: StableId,
) -> Result(Nil, TreeError) {
  identity_key(identity_order, revision)
  |> result.map(fn(_) { Nil })
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn revision_for_identity_key(
  entries: List(#(StableId, Int)),
  key: Int,
) -> Option(StableId) {
  case entries {
    [] -> None
    [entry, ..rest] ->
      case entry.1 == key {
        True -> Some(entry.0)
        False -> revision_for_identity_key(rest, key)
      }
  }
}

// ponytail: Use the core libraries. This function is a copy of int.compare. Use
// int.compare.
fn int_compare(left: Int, right: Int) -> order.Order {
  case left < right, left > right {
    True, _ -> order.Lt
    _, True -> order.Gt
    _, _ -> order.Eq
  }
}

// ponytail: Use the core libraries. This function is a copy of int.max. Use
// int.max.
fn int_max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
}

fn merge_pairs(first: List(#(a, b)), second: List(#(a, b))) -> List(#(a, b)) {
  list.fold(second, first, fn(entries, entry) {
    case pair_value(entries, entry.0) {
      Some(_) -> entries
      None -> list.append(entries, [entry])
    }
  })
}

fn take_pair(entries: List(#(a, b)), key: a) -> #(Option(b), List(#(a, b))) {
  case entries {
    [] -> #(None, [])
    [entry, ..rest] ->
      case entry.0 == key {
        True -> #(Some(entry.1), rest)
        False -> {
          let #(value, rest) = take_pair(rest, key)
          #(value, [entry, ..rest])
        }
      }
  }
}

fn put_pair(entries: List(#(a, b)), key: a, value: b) -> List(#(a, b)) {
  case entries {
    [] -> [#(key, value)]
    [entry, ..rest] ->
      case entry.0 == key {
        True -> [#(key, value), ..rest]
        False -> [entry, ..put_pair(rest, key, value)]
      }
  }
}

fn remove_pair(entries: List(#(a, b)), key: a) -> List(#(a, b)) {
  list.filter(entries, fn(entry) { entry.0 != key })
}

fn edit_destination(
  schema: StoredSchema,
  forest: forest.Forest,
  path: FieldPath,
  value: Option(TreeValue),
) -> Result(#(FieldSchema, FieldPath, String, Bool), TreeError) {
  case path {
    [] -> {
      use _ <- result.try(schema.validate_root_field(schema, value))
      use current <- result.try(forest.read(forest, []))
      Ok(#(
        schema.root_field_schema(schema),
        [],
        "rootFieldKey",
        current == None,
      ))
    }
    [first, ..rest] -> {
      let #(parent_path, field) = split_last_loop(rest, [], first)
      use parent <- result.try(forest.read(forest, parent_path))
      use parent_type <- result.try(case parent {
        None -> Error(InvalidEdit(path, "parent field is absent"))
        Some(ObjectValue(identifier, _)) -> Ok(identifier)
        Some(types.ArrayValue(_, _)) ->
          Error(InvalidEdit(path, "array slots cannot be assigned"))
        Some(types.MapValue(_, _)) ->
          Error(InvalidEdit(path, "map entries require a map edit"))
        Some(_) -> Error(InvalidEdit(path, "parent schema is a leaf"))
      })
      use definition <- result.try(schema.field_schema(
        schema,
        parent_type,
        field,
      ))
      use _ <- result.try(schema.validate_field(
        schema,
        parent_type,
        field,
        value,
      ))
      use current <- result.try(forest.read(forest, path))
      Ok(#(definition, parent_path, field, current == None))
    }
  }
}

fn map_edit_destination(
  stored: StoredSchema,
  visible: forest.Forest,
  path: FieldPath,
  key: String,
  value: Option(TreeValue),
) -> Result(#(FieldSchema, FieldPath, String, Bool), TreeError) {
  use map_type <- result.try(forest.map_type(visible, path))
  use entry_schema <- result.try(schema.map_entry_schema(stored, map_type))
  use _ <- result.try(schema.validate_map_entry(stored, map_type, key, value))
  use current <- result.try(forest.map_get(visible, path, key))
  Ok(#(entry_schema, path, key, current == None))
}

fn split_last_loop(
  remaining: FieldPath,
  prefix: FieldPath,
  current: String,
) -> #(FieldPath, String) {
  case remaining {
    [] -> #(list.reverse(prefix), current)
    [next, ..rest] -> split_last_loop(rest, [current, ..prefix], next)
  }
}

fn authored_field(
  cardinality: Cardinality,
  was_empty: Bool,
  value: Option(TreeValue),
  revision: StableId,
  first_local_id: Int,
) -> Result(#(FieldChange, List(forest.Build), Int), TreeError) {
  case cardinality, value {
    Required, Some(value) -> {
      use #(fill, next_id) <- result.try(allocate(revision, first_local_id))
      use #(detach, next_id) <- result.try(allocate(revision, next_id))
      Ok(#(
        ValueField(optional_field.set(False, fill, detach)),
        [forest.Build(fill, [value])],
        next_id,
      ))
    }
    Optional, Some(value) -> {
      use #(detach, next_id) <- result.try(allocate(revision, first_local_id))
      use #(fill, next_id) <- result.try(allocate(revision, next_id))
      Ok(#(
        OptionalField(optional_field.set(was_empty, fill, detach)),
        [forest.Build(fill, [value])],
        next_id,
      ))
    }
    Optional, None -> {
      use #(detach, next_id) <- result.try(allocate(revision, first_local_id))
      Ok(#(OptionalField(optional_field.clear(was_empty, detach)), [], next_id))
    }
    Required, None -> Error(InvalidEdit([], "required field is absent"))
    schema.Sequence, _ ->
      Error(types.UnsupportedFeature("field edit", "sequence fields"))
  }
}

fn wrap_ancestors(
  parent_steps: List(forest.FieldStep),
  field: String,
  field_change: FieldChange,
  revision: StableId,
  next_id: Int,
) -> Result(
  #(
    List(#(String, FieldChange)),
    List(#(AtomId, NodeChange)),
    List(#(AtomId, ParentField)),
    Int,
  ),
  TreeError,
) {
  case parent_steps {
    [] -> Ok(#([#(field, field_change)], [], [], next_id - 1))
    _ -> {
      use #(child, next_id) <- result.try(allocate(revision, next_id))
      let nodes = [#(child, node_change([#(field, field_change)]))]
      use #(top, nodes, parents, next_id) <- result.try(
        wrap_parent_fields(
          list.reverse(parent_steps),
          child,
          revision,
          next_id,
          nodes,
          [],
        ),
      )
      // ponytail: Check-then-assert. The case on parent_steps above proves that
      // the list is not empty. Match the head step in that case arm.
      let assert [forest.FieldStep(root_field, root_index), ..] = parent_steps
      Ok(#(
        [#(root_field, GenericField([#(root_index, top)]))],
        nodes,
        list.append(parents, [
          #(top, ParentField(None, root_field)),
        ]),
        next_id - 1,
      ))
    }
  }
}

fn wrap_parent_fields(
  steps: List(forest.FieldStep),
  child: AtomId,
  revision: StableId,
  next_id: Int,
  nodes: List(#(AtomId, NodeChange)),
  parents: List(#(AtomId, ParentField)),
) -> Result(
  #(AtomId, List(#(AtomId, NodeChange)), List(#(AtomId, ParentField)), Int),
  TreeError,
) {
  case steps {
    [] | [_] -> Ok(#(child, nodes, parents, next_id))
    [forest.FieldStep(field, index), ..rest] -> {
      use #(parent, next_id) <- result.try(allocate(revision, next_id))
      wrap_parent_fields(
        rest,
        parent,
        revision,
        next_id,
        list.append(nodes, [
          #(parent, node_change([#(field, GenericField([#(index, child)]))])),
        ]),
        list.append(parents, [
          #(child, ParentField(Some(parent), field)),
        ]),
      )
    }
  }
}

fn allocate(
  revision: StableId,
  next_id: Int,
) -> Result(#(AtomId, Int), TreeError) {
  case next_id >= 0 && next_id <= max_safe_integer {
    True -> Ok(#(AtomId(Some(revision), next_id), next_id + 1))
    False -> Error(CorruptData("change allocator", "identifiers are exhausted"))
  }
}

fn allocate_range(
  revision: StableId,
  next_id: Int,
  count: Int,
) -> Result(#(AtomId, Int), TreeError) {
  use _ <- result.try(check(
    count >= 0
      && count <= max_safe_integer
      && next_id >= 0
      && next_id <= max_safe_integer
      && case count {
      0 -> True
      _ -> count - 1 <= max_safe_integer - next_id
    },
    "change allocator",
    "identifiers are exhausted",
  ))
  Ok(#(AtomId(Some(revision), next_id), next_id + count))
}

fn delta_fields(
  fields: List(#(String, FieldChange)),
  data: ChangeData,
) -> Result(DeltaParts, TreeError) {
  list.try_fold(fields, DeltaParts([], [], []), fn(parts, entry) {
    use field <- result.try(delta_field(entry.1, data))
    let fields = case field.0 {
      None -> parts.fields
      Some(forest.FieldDelta([])) -> parts.fields
      Some(delta) -> list.append(parts.fields, [#(entry.0, delta)])
    }
    Ok(DeltaParts(
      fields,
      list.append(parts.global, field.1),
      list.append(parts.rename, field.2),
    ))
  })
}

fn delta_field(
  field: FieldChange,
  data: ChangeData,
) -> Result(
  #(Option(forest.FieldDelta), List(forest.DetachedChange), List(forest.Rename)),
  TreeError,
) {
  case field {
    GenericField(children) -> {
      use child_parts <- result.try(
        children
        |> list.sort(fn(left, right) { int.compare(left.0, right.0) })
        |> list.try_map(fn(child) {
          delta_child(child.1, data)
          |> result.map(fn(parts) { #(child.0, child.1, parts) })
        }),
      )
      let marks = generic_delta_marks(child_parts, 0, [])
      Ok(#(
        Some(forest.FieldDelta(marks)),
        list.flat_map(child_parts, fn(child) { child.2.global }),
        list.flat_map(child_parts, fn(child) { child.2.rename }),
      ))
    }

    SequenceField(change) -> {
      use child_parts <- result.try(
        list.try_map(field_children(SequenceField(change)), fn(child) {
          delta_child(child, data)
          |> result.map(fn(parts) { #(child, parts) })
        }),
      )
      use delta <- result.try(
        sequence_field.into_delta(change, fn(id) {
          case parts_for(child_parts, id) {
            None -> Error(CorruptData("delta", "child change is missing"))
            Some(parts) -> Ok(parts.fields)
          }
        }),
      )
      Ok(#(
        delta.local,
        list.append(
          list.flat_map(child_parts, fn(child) { child.1.global }),
          delta.global,
        ),
        list.append(
          list.flat_map(child_parts, fn(child) { child.1.rename }),
          delta.rename,
        ),
      ))
    }
    ValueField(change) | OptionalField(change) -> {
      let optional_field.FieldChange(_, children, _) = change
      use child_parts <- result.try(
        list.try_map(children, fn(child) {
          delta_child(child.1, data)
          |> result.map(fn(parts) { #(child.1, parts) })
        }),
      )
      use delta <- result.try(
        optional_field.into_delta(change, fn(id) {
          case parts_for(child_parts, id) {
            None -> Error(CorruptData("delta", "child change is missing"))
            Some(parts) -> Ok(parts.fields)
          }
        }),
      )
      let optional_field.FieldChangeDelta(local, global, rename) = delta
      Ok(#(
        local,
        list.append(
          list.flat_map(child_parts, fn(child) { child.1.global }),
          global,
        ),
        list.append(
          list.flat_map(child_parts, fn(child) { child.1.rename }),
          rename,
        ),
      ))
    }
  }
}

fn generic_delta_marks(
  children: List(#(Int, AtomId, DeltaParts)),
  position: Int,
  marks: List(forest.Mark),
) -> List(forest.Mark) {
  case children {
    [] -> list.reverse(marks)
    [child, ..rest] -> {
      let marks = case child.0 - position {
        0 -> marks
        gap -> [forest.Mark(gap, None, None, []), ..marks]
      }
      generic_delta_marks(rest, child.0 + 1, [
        forest.Mark(1, None, None, child.2.fields),
        ..marks
      ])
    }
  }
}

fn delta_child(id: AtomId, data: ChangeData) -> Result(DeltaParts, TreeError) {
  use canonical <- result.try(resolve_alias(id, data.aliases))
  use node <- result.try(node_for(canonical, data.nodes))
  let NodeChange(fields: fields, ..) = node
  delta_fields(fields, data)
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn parts_for(
  parts: List(#(AtomId, DeltaParts)),
  id: AtomId,
) -> Option(DeltaParts) {
  case parts {
    [] -> None
    [entry, ..rest] ->
      case entry.0 == id {
        True -> Some(entry.1)
        False -> parts_for(rest, id)
      }
  }
}

fn validate_data(data: ChangeData) -> Result(Nil, TreeError) {
  use _ <- result.try(check(
    data.max_local_id >= -1 && data.max_local_id <= max_safe_integer,
    "change",
    "invalid allocation watermark",
  ))
  use _ <- result.try(check(
    data.constraint_violation_count >= 0,
    "change",
    "constraint violation count is negative",
  ))
  use _ <- result.try(validate_revisions(data.revisions))
  use _ <- result.try(unique_pairs(data.fields, "root fields"))
  use _ <- result.try(unique_pairs(data.nodes, "node changes"))
  use _ <- result.try(unique_pairs(data.parents, "node parents"))
  use _ <- result.try(unique_pairs(data.aliases, "node aliases"))
  use _ <- result.try(
    list.try_each(data.aliases, fn(alias) {
      use _ <- result.try(validate_atom(alias.0, "node alias"))
      validate_atom(alias.1, "node alias")
    }),
  )
  use _ <- result.try(
    list.try_each(data.aliases, fn(alias) {
      resolve_alias(alias.0, data.aliases) |> result.map(fn(_) { Nil })
    }),
  )
  use _ <- result.try(validate_field_map(data.fields, "root fields"))
  use _ <- result.try(
    list.try_each(data.nodes, fn(entry) {
      use _ <- result.try(validate_atom(entry.0, "node changes"))
      use _ <- result.try(check(
        pair_value(data.aliases, entry.0) == None,
        "node changes",
        "alias source cannot key a node change",
      ))
      let NodeChange(fields: fields, ..) = entry.1
      use _ <- result.try(unique_pairs(fields, "node fields"))
      validate_field_map(fields, "node fields")
    }),
  )
  use _ <- result.try(
    list.try_each(data.parents, fn(entry) {
      use _ <- result.try(validate_atom(entry.0, "node parents"))
      use _ <- result.try(check(
        pair_value(data.aliases, entry.0) == None,
        "node parents",
        "alias source cannot key a node parent",
      ))
      let ParentField(parent, _) = entry.1
      case parent {
        None -> Ok(Nil)
        Some(parent) -> validate_atom(parent, "node parents")
      }
    }),
  )
  use _ <- result.try(validate_builds(data.builds, "builds"))
  use _ <- result.try(validate_builds(data.refreshers, "refreshers"))
  use _ <- result.try(validate_destroys(data.destroys))
  validate_ownership(data)
}

fn validate_data_identity_order(
  data: ChangeData,
  identity_order: IdentityOrder,
) -> Result(Nil, TreeError) {
  use _ <- result.try(
    list.try_each(data.revisions, fn(info) {
      use _ <- result.try(require_identity_revision(
        identity_order,
        info.revision,
      ))
      case info.rollback_of {
        None -> Ok(Nil)
        Some(revision) -> require_identity_revision(identity_order, revision)
      }
    }),
  )
  use _ <- result.try(validate_field_map_identity_order(
    data.fields,
    identity_order,
  ))
  use _ <- result.try(
    list.try_each(data.nodes, fn(entry) {
      use _ <- result.try(validate_atom_identity_order(entry.0, identity_order))
      let NodeChange(fields: fields, ..) = entry.1
      validate_field_map_identity_order(fields, identity_order)
    }),
  )
  use _ <- result.try(
    list.try_each(data.parents, fn(entry) {
      use _ <- result.try(validate_atom_identity_order(entry.0, identity_order))
      let ParentField(parent, _) = entry.1
      case parent {
        None -> Ok(Nil)
        Some(parent) -> validate_atom_identity_order(parent, identity_order)
      }
    }),
  )
  use _ <- result.try(
    list.try_each(data.aliases, fn(alias) {
      use _ <- result.try(validate_atom_identity_order(alias.0, identity_order))
      validate_atom_identity_order(alias.1, identity_order)
    }),
  )
  use _ <- result.try(
    list.try_each(data.builds, fn(build) {
      validate_atom_identity_order(build.id, identity_order)
    }),
  )
  use _ <- result.try(
    list.try_each(data.destroys, fn(destroy) {
      validate_atom_identity_order(destroy.id, identity_order)
    }),
  )
  list.try_each(data.refreshers, fn(build) {
    validate_atom_identity_order(build.id, identity_order)
  })
}

fn validate_field_map_identity_order(
  fields: List(#(String, FieldChange)),
  identity_order: IdentityOrder,
) -> Result(Nil, TreeError) {
  list.try_each(fields, fn(entry) {
    validate_field_identity_order(entry.1, identity_order)
  })
}

fn validate_field_identity_order(
  field: FieldChange,
  identity_order: IdentityOrder,
) -> Result(Nil, TreeError) {
  case field {
    GenericField(children) ->
      list.try_each(children, fn(child) {
        validate_atom_identity_order(child.1, identity_order)
      })
    SequenceField(change) ->
      sequence_field.to_marks(change)
      |> list.try_each(fn(mark) {
        list.try_each(sequence_mark_atoms(mark), fn(id) {
          validate_atom_identity_order(id, identity_order)
        })
      })
    ValueField(change) | OptionalField(change) -> {
      let optional_field.FieldChange(moves, children, replacement) = change
      use _ <- result.try(
        list.try_each(moves, fn(move) {
          use _ <- result.try(validate_atom_identity_order(
            move.0,
            identity_order,
          ))
          validate_atom_identity_order(move.1, identity_order)
        }),
      )
      use _ <- result.try(
        list.try_each(children, fn(child) {
          use _ <- result.try(case child.0 {
            optional_field.Active -> Ok(Nil)
            optional_field.Detached(id) ->
              validate_atom_identity_order(id, identity_order)
          })
          validate_atom_identity_order(child.1, identity_order)
        }),
      )
      case replacement {
        None -> Ok(Nil)
        Some(optional_field.Replacement(_, source, detach)) -> {
          use _ <- result.try(case source {
            None -> Ok(Nil)
            Some(optional_field.Detached(id)) ->
              validate_atom_identity_order(id, identity_order)
            Some(optional_field.Active) -> Ok(Nil)
          })
          validate_atom_identity_order(detach, identity_order)
        }
      }
    }
  }
}

fn validate_atom_identity_order(
  atom: AtomId,
  identity_order: IdentityOrder,
) -> Result(Nil, TreeError) {
  case atom.revision {
    None -> Ok(Nil)
    Some(revision) -> require_identity_revision(identity_order, revision)
  }
}

fn validate_revisions(revisions: List(RevisionInfo)) -> Result(Nil, TreeError) {
  use _ <- result.try(unique_by(
    revisions,
    fn(info) { info.revision },
    InvalidHistory("duplicate revision metadata"),
  ))
  list.try_each(revisions, fn(info) {
    case info.rollback_of {
      Some(revision) if revision == info.revision ->
        Error(InvalidHistory("a revision cannot roll back itself"))
      _ -> validate_rollback_chain(info.revision, revisions, [])
    }
  })
}

fn validate_rollback_chain(
  revision: StableId,
  revisions: List(RevisionInfo),
  seen: List(StableId),
) -> Result(Nil, TreeError) {
  case list.contains(seen, revision) {
    True -> Error(InvalidHistory("rollback metadata contains a cycle"))
    False ->
      case revision_info(revisions, revision) {
        None -> Ok(Nil)
        Some(RevisionInfo(_, None)) -> Ok(Nil)
        Some(RevisionInfo(_, Some(rollback_of))) ->
          validate_rollback_chain(rollback_of, revisions, [revision, ..seen])
      }
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn revision_info(
  revisions: List(RevisionInfo),
  revision: StableId,
) -> Option(RevisionInfo) {
  case revisions {
    [] -> None
    [info, ..rest] ->
      case info.revision == revision {
        True -> Some(info)
        False -> revision_info(rest, revision)
      }
  }
}

fn validate_field_map(
  fields: List(#(String, FieldChange)),
  location: String,
) -> Result(Nil, TreeError) {
  list.try_each(fields, fn(entry) {
    validate_field(entry.1)
    |> result.map_error(fn(error) {
      CorruptData(location <> "." <> entry.0, string.inspect(error))
    })
  })
}

fn validate_field(field: FieldChange) -> Result(Nil, TreeError) {
  case field {
    ValueField(change) | OptionalField(change) ->
      optional_field.validate(change)
    SequenceField(change) ->
      sequence_field.from_marks(sequence_field.to_marks(change))
      |> result.map(fn(_) { Nil })
    GenericField(children) -> {
      use _ <- result.try(unique_by(
        children,
        fn(child) { child.0 },
        CorruptData("generic field", "duplicate child index"),
      ))
      list.try_each(children, fn(child) {
        use _ <- result.try(check(
          child.0 >= 0 && child.0 <= max_safe_integer,
          "generic field",
          "child index is outside the safe integer range",
        ))
        validate_atom(child.1, "generic field")
      })
    }
  }
}

fn validate_builds(
  builds: List(forest.Build),
  location: String,
) -> Result(Nil, TreeError) {
  use ranges <- result.try(
    list.try_map(builds, fn(build) {
      use _ <- result.try(check(
        !list.is_empty(build.trees),
        location,
        "build content is empty",
      ))
      use _ <- result.try(validate_range(
        build.id,
        list.length(build.trees),
        location,
      ))
      Ok(#(build.id, list.length(build.trees)))
    }),
  )
  validate_nonoverlapping(ranges, location)
}

fn validate_destroys(destroys: List(forest.Destroy)) -> Result(Nil, TreeError) {
  use ranges <- result.try(
    list.try_map(destroys, fn(destroy) {
      use _ <- result.try(validate_range(destroy.id, destroy.count, "destroys"))
      Ok(#(destroy.id, destroy.count))
    }),
  )
  validate_nonoverlapping(ranges, "destroys")
}

fn validate_nonoverlapping(
  ranges: List(#(AtomId, Int)),
  location: String,
) -> Result(Nil, TreeError) {
  use _ <- result.try(unique_by(
    ranges,
    fn(range) { range },
    CorruptData(location, "duplicate identifier range"),
  ))
  list.try_each(ranges, fn(range) {
    list.try_each(ranges, fn(other) {
      case range == other {
        True -> Ok(Nil)
        False ->
          check(
            !ranges_overlap(range, other),
            location,
            "identifier ranges overlap",
          )
      }
    })
  })
}

fn ranges_overlap(left: #(AtomId, Int), right: #(AtomId, Int)) -> Bool {
  left.0.revision == right.0.revision
  && left.0.local_id < right.0.local_id + right.1
  && right.0.local_id < left.0.local_id + left.1
}

fn validate_range(
  id: AtomId,
  count: Int,
  location: String,
) -> Result(Nil, TreeError) {
  check(
    id.local_id >= 0
      && id.local_id <= max_safe_integer
      && count > 0
      && count <= max_safe_integer
      && count - 1 <= max_safe_integer - id.local_id,
    location,
    "invalid identifier range",
  )
}

fn validate_atom(id: AtomId, location: String) -> Result(Nil, TreeError) {
  check(
    id.local_id >= 0 && id.local_id <= max_safe_integer,
    location,
    "invalid atom identifier",
  )
}

fn validate_ownership(data: ChangeData) -> Result(Nil, TreeError) {
  use owners <- result.try(walk_fields(data.fields, None, data, [], []))
  use _ <- result.try(check(
    list.length(owners) == list.length(data.nodes),
    "node changes",
    "unowned node change",
  ))
  use _ <- result.try(check(
    list.length(owners) == list.length(data.parents),
    "node parents",
    "parent table does not match live nodes",
  ))
  list.try_each(owners, fn(owner) {
    use actual <- result.try(parent_for(owner.id, data.parents))
    use expected <- result.try(normalize_parent(owner.parent, data.aliases))
    use actual <- result.try(normalize_parent(actual, data.aliases))
    check(
      actual == expected,
      "node parents",
      "node ownership does not match its field",
    )
  })
}

fn walk_fields(
  fields: List(#(String, FieldChange)),
  parent: Option(AtomId),
  data: ChangeData,
  owners: List(Ownership),
  stack: List(AtomId),
) -> Result(List(Ownership), TreeError) {
  list.try_fold(fields, owners, fn(owners, entry) {
    list.try_fold(field_children(entry.1), owners, fn(owners, child) {
      walk_child(child, ParentField(parent, entry.0), data, owners, stack)
    })
  })
}

fn walk_child(
  child: AtomId,
  parent: ParentField,
  data: ChangeData,
  owners: List(Ownership),
  stack: List(AtomId),
) -> Result(List(Ownership), TreeError) {
  use canonical <- result.try(resolve_alias(child, data.aliases))
  use _ <- result.try(check(
    !list.contains(stack, canonical),
    "node changes",
    "node ownership contains a cycle",
  ))
  use _ <- result.try(check(
    ownership_for(owners, canonical) == None,
    "node changes",
    "node has incompatible ownership",
  ))
  use node <- result.try(node_for(canonical, data.nodes))
  let owner = Ownership(canonical, parent)
  let NodeChange(fields: fields, ..) = node
  walk_fields(fields, Some(canonical), data, list.append(owners, [owner]), [
    canonical,
    ..stack
  ])
}

fn field_children(field: FieldChange) -> List(AtomId) {
  case field {
    GenericField(children) -> list.map(children, fn(child) { child.1 })
    SequenceField(change) ->
      sequence_field.to_marks(change)
      |> list.fold([], fn(children, mark) {
        case mark.child {
          None -> children
          Some(child) -> [child, ..children]
        }
      })
      |> list.reverse
    ValueField(optional_field.FieldChange(_, children, _))
    | OptionalField(optional_field.FieldChange(_, children, _)) ->
      list.map(children, fn(child) { child.1 })
  }
}

fn sequence_mark_atoms(mark: sequence_field.Mark) -> List(AtomId) {
  let effect = case mark.effect {
    sequence_field.Noop -> []
    sequence_field.Rename(id) -> [id]
    sequence_field.Attach(attach) -> sequence_attach_atoms(attach)
    sequence_field.Detach(detach) -> sequence_detach_atoms(detach)
    sequence_field.AttachAndDetach(attach, detach) ->
      list.append(sequence_attach_atoms(attach), sequence_detach_atoms(detach))
  }
  list.flatten([
    case mark.cell_id {
      None -> []
      Some(id) -> [id]
    },
    effect,
    case mark.child {
      None -> []
      Some(id) -> [id]
    },
  ])
}

fn sequence_attach_atoms(attach: sequence_field.Attach) -> List(AtomId) {
  case attach {
    sequence_field.Insert(id) -> [id]
    sequence_field.MoveIn(id, endpoint) -> [
      id,
      ..case endpoint {
        None -> []
        Some(id) -> [id]
      }
    ]
  }
}

fn sequence_detach_atoms(detach: sequence_field.Detach) -> List(AtomId) {
  case detach {
    sequence_field.Remove(id, id_override) -> [
      id,
      ..case id_override {
        None -> []
        Some(id) -> [id]
      }
    ]
    sequence_field.MoveOut(id, endpoint, id_override) ->
      list.flatten([
        [id],
        case endpoint {
          None -> []
          Some(id) -> [id]
        },
        case id_override {
          None -> []
          Some(id) -> [id]
        },
      ])
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn ownership_for(owners: List(Ownership), id: AtomId) -> Option(Ownership) {
  case owners {
    [] -> None
    [owner, ..rest] ->
      case owner.id == id {
        True -> Some(owner)
        False -> ownership_for(rest, id)
      }
  }
}

fn node_for(
  id: AtomId,
  nodes: List(#(AtomId, NodeChange)),
) -> Result(NodeChange, TreeError) {
  case nodes {
    [] -> Error(CorruptData("node changes", "live node change is missing"))
    [entry, ..rest] -> {
      case entry.0 == id {
        True -> Ok(entry.1)
        False -> node_for(id, rest)
      }
    }
  }
}

fn parent_for(
  id: AtomId,
  parents: List(#(AtomId, ParentField)),
) -> Result(ParentField, TreeError) {
  case parents {
    [] -> Error(CorruptData("node parents", "live node parent is missing"))
    [entry, ..rest] -> {
      case entry.0 == id {
        True -> Ok(entry.1)
        False -> parent_for(id, rest)
      }
    }
  }
}

fn normalize_parent(
  parent: ParentField,
  aliases: List(#(AtomId, AtomId)),
) -> Result(ParentField, TreeError) {
  let ParentField(node, field) = parent
  case node {
    None -> Ok(parent)
    Some(node) -> {
      use node <- result.try(resolve_alias(node, aliases))
      Ok(ParentField(Some(node), field))
    }
  }
}

fn resolve_alias(
  id: AtomId,
  aliases: List(#(AtomId, AtomId)),
) -> Result(AtomId, TreeError) {
  resolve_alias_loop(id, aliases, [])
}

fn resolve_alias_loop(
  id: AtomId,
  aliases: List(#(AtomId, AtomId)),
  seen: List(AtomId),
) -> Result(AtomId, TreeError) {
  case list.contains(seen, id) {
    True -> Error(CorruptData("node aliases", "alias cycle"))
    False ->
      case pair_value(aliases, id) {
        None -> Ok(id)
        Some(next) -> resolve_alias_loop(next, aliases, [id, ..seen])
      }
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn pair_value(entries: List(#(a, b)), key: a) -> Option(b) {
  case entries {
    [] -> None
    [entry, ..rest] ->
      case entry.0 == key {
        True -> Some(entry.1)
        False -> pair_value(rest, key)
      }
  }
}

fn unique_pairs(
  entries: List(#(a, b)),
  location: String,
) -> Result(Nil, TreeError) {
  unique_by(
    entries,
    fn(entry) { entry.0 },
    CorruptData(location, "duplicate entry"),
  )
}

fn unique_by(
  values: List(a),
  key: fn(a) -> b,
  error: TreeError,
) -> Result(Nil, TreeError) {
  use _ <- result.try(
    list.try_fold(values, [], fn(seen, value) {
      let key = key(value)
      case list.contains(seen, key) {
        True -> Error(error)
        False -> Ok([key, ..seen])
      }
    }),
  )
  Ok(Nil)
}

fn check(
  valid: Bool,
  location: String,
  detail: String,
) -> Result(Nil, TreeError) {
  case valid {
    True -> Ok(Nil)
    False -> Error(CorruptData(location, detail))
  }
}

//// Pure modular changes for the fixed SharedTree profile.

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
import watershed/tree/types.{
  type AtomId, type Edit, type FieldPath, type TreeError, type TreeValue, AtomId,
  ClearField, CorruptData, InvalidEdit, InvalidHistory, ObjectValue, SetField,
}

const max_safe_integer = 9_007_199_254_740_991

pub type RevisionInfo {
  RevisionInfo(revision: StableId, rollback_of: Option(StableId))
}

pub type FieldChange {
  ValueField(optional_field.FieldChange)
  OptionalField(optional_field.FieldChange)
  GenericField(children: List(#(Int, AtomId)))
}

pub type NodeChange {
  NodeChange(fields: List(#(String, FieldChange)))
}

pub type ParentField {
  ParentField(parent: Option(AtomId), field: String)
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
  )
}

pub opaque type Changeset {
  Changeset(data: ChangeData)
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

type DeltaParts {
  DeltaParts(
    fields: List(#(String, forest.FieldDelta)),
    global: List(forest.DetachedChange),
    rename: List(forest.Rename),
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

type RebaseState {
  RebaseState(
    nodes: List(#(AtomId, NodeChange)),
    parents: List(#(AtomId, ParentField)),
    aliases: List(#(AtomId, AtomId)),
    authored: ChangeData,
    base: ChangeData,
    base_to_rebased: List(#(AtomId, AtomId)),
    pairs: List(#(AtomId, AtomId)),
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
    ),
  )
}

pub fn from_data(data: ChangeData) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_data(data))
  Ok(Changeset(data))
}

pub fn to_data(change: Changeset) -> ChangeData {
  change.data
}

pub fn rebase_context(
  revisions: List(RevisionInfo),
) -> Result(RebaseContext, TreeError) {
  use _ <- result.try(validate_revisions(revisions))
  Ok(RebaseContext(revisions))
}

pub fn edit(
  schema: StoredSchema,
  forest: forest.Forest,
  revision: StableId,
  operation: Edit,
) -> Result(Changeset, TreeError) {
  let #(path, value) = case operation {
    SetField(path, value) -> #(path, Some(value))
    ClearField(path) -> #(path, None)
  }
  use #(field_schema, parent_path, field, was_empty) <- result.try(
    edit_destination(schema, forest, path, value),
  )
  let FieldSchema(cardinality, _) = field_schema
  use #(field_change, builds, next_id) <- result.try(authored_field(
    cardinality,
    was_empty,
    value,
    revision,
  ))
  use #(fields, nodes, parents, max_local_id) <- result.try(wrap_ancestors(
    parent_path,
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
    ),
  )
}

pub fn into_delta(change: TaggedChange) -> Result(forest.Delta, TreeError) {
  let data = change.change.data
  use parts <- result.try(delta_fields(data.fields, data))
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
  let #(revisions, max_local_id) = composition_metadata(changes)
  use composed <- result.try(balanced_compose(
    list.map(changes, fn(change) { change.change }),
    revisions,
    max_local_id,
  ))
  let data = sort_atom_tables(composed.data)
  from_data(
    ChangeData(..data, max_local_id: max_local_id, revisions: revisions),
  )
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
      let NodeChange(fields) = entry.1
      use fields <- result.try(replace_field_map(fields, state))
      Ok(#(id, NodeChange(fields)))
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
    )
    |> sort_atom_tables
  from_data(data)
}

pub fn prune(change: Changeset) -> Result(Changeset, TreeError) {
  let data = change.data
  use #(fields, state) <- result.try(prune_field_map(
    data.fields,
    PruneState(data.nodes, data.parents),
    data.aliases,
  ))
  from_data(
    ChangeData(
      ..data,
      fields: fields,
      nodes: state.nodes,
      parents: state.parents,
    ),
  )
}

pub fn relevant_removed_roots(
  change: Changeset,
) -> Result(List(AtomId), TreeError) {
  removed_roots_from_fields(change.data.fields, change.data, [])
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
  let data =
    ChangeData(..change.data, refreshers: refreshers)
    |> sort_atom_tables
  from_data(data)
}

pub fn invert(
  change: TaggedChange,
  is_rollback: Bool,
  inverse_revision: StableId,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(check(
    list.is_empty(change.change.data.destroys),
    "invert",
    "a destroying change cannot be inverted",
  ))
  let data = change.change.data
  let #(allocation_revisions, _) = composition_metadata([change])
  use watermark <- result.try(reserved_watermark(
    data.max_local_id,
    list.length(allocation_revisions),
  ))
  use #(fields, watermark) <- result.try(invert_field_map(
    data.fields,
    is_rollback,
    inverse_revision,
    watermark,
  ))
  use #(nodes, watermark) <- result.try(
    list.try_fold(data.nodes, #([], watermark), fn(output, entry) {
      let NodeChange(fields) = entry.1
      use #(fields, watermark) <- result.try(invert_field_map(
        fields,
        is_rollback,
        inverse_revision,
        output.1,
      ))
      Ok(#(list.append(output.0, [#(entry.0, NodeChange(fields))]), watermark))
    }),
  )
  use parents <- result.try(rebuild_parents(fields, nodes, data.aliases))
  let destroys = case is_rollback {
    True ->
      list.map(data.builds, fn(build) {
        forest.Destroy(build.id, list.length(build.trees))
      })
    False -> []
  }
  let inverted =
    ChangeData(
      max_local_id: watermark,
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
    )
    |> sort_atom_tables
  from_data(inverted)
}

pub fn rebase(
  change: TaggedChange,
  over: TaggedChange,
  context: RebaseContext,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_rebase_inputs(change, over, context))
  let authored = change.change.data
  let base = over.change.data
  let state = RebaseState([], [], authored.aliases, authored, base, [], [])
  use #(fields, state) <- result.try(rebase_field_maps(
    authored.fields,
    base.fields,
    state,
  ))
  use parents <- result.try(rebuild_parents(fields, state.nodes, state.aliases))
  let revisions = tagged_revision_infos(change)
  let data =
    ChangeData(
      max_local_id: int_max(authored.max_local_id, base.max_local_id),
      revisions: revisions,
      fields: fields,
      nodes: state.nodes,
      parents: parents,
      aliases: state.aliases,
      builds: authored.builds,
      destroys: authored.destroys,
      refreshers: authored.refreshers,
    )
    |> sort_atom_tables
  use rebased <- result.try(from_data(data))
  prune(rebased)
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
          output.1,
        ))
        Ok(#(list.append(output.0, [#(entry.0, field)]), state))
      }
    }
  })
}

fn rebase_field(
  authored: FieldChange,
  base: FieldChange,
  state: RebaseState,
) -> Result(#(FieldChange, RebaseState), TreeError) {
  case authored, base {
    GenericField(authored), GenericField(base) -> {
      use #(children, state) <- result.try(rebase_generic(authored, base, state))
      Ok(#(GenericField(children), state))
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
  _attach: optional_field.AttachState,
  state: RebaseState,
) -> Result(#(Option(AtomId), RebaseState), TreeError) {
  case authored, base {
    Some(authored), Some(base) -> {
      use #(rebased, state) <- result.try(rebase_nodes(authored, base, state))
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
      use authored_node <- result.try(node_for(
        authored,
        state.authored.nodes,
        state.authored.aliases,
      ))
      use base_node <- result.try(node_for(
        base,
        state.base.nodes,
        state.base.aliases,
      ))
      let NodeChange(authored_fields) = authored_node
      let NodeChange(base_fields) = base_node
      let state =
        RebaseState(
          ..state,
          base_to_rebased: list.append(state.base_to_rebased, [
            #(base, authored),
          ]),
          pairs: [#(authored, base), ..state.pairs],
        )
      use #(fields, state) <- result.try(rebase_field_maps(
        authored_fields,
        base_fields,
        state,
      ))
      let nodes = put_pair(state.nodes, authored, NodeChange(fields))
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
      use node <- result.try(node_for(
        canonical,
        state.authored.nodes,
        state.authored.aliases,
      ))
      let NodeChange(fields) = node
      let state =
        RebaseState(
          ..state,
          nodes: put_pair(state.nodes, canonical, NodeChange(fields)),
        )
      use state <- result.try(
        list.try_fold(fields, state, fn(state, entry) {
          copy_field_children(entry.1, state)
        }),
      )
      Ok(#(canonical, state))
    }
  }
}

fn invert_field_map(
  fields: List(#(String, FieldChange)),
  is_rollback: Bool,
  inverse_revision: StableId,
  watermark: Int,
) -> Result(#(List(#(String, FieldChange)), Int), TreeError) {
  list.try_fold(fields, #([], watermark), fn(output, entry) {
    use #(field, watermark) <- result.try(invert_field(
      entry.1,
      is_rollback,
      inverse_revision,
      output.1,
    ))
    Ok(#(list.append(output.0, [#(entry.0, field)]), watermark))
  })
}

fn invert_field(
  field: FieldChange,
  is_rollback: Bool,
  inverse_revision: StableId,
  watermark: Int,
) -> Result(#(FieldChange, Int), TreeError) {
  case field {
    GenericField(children) -> Ok(#(GenericField(children), watermark))
    ValueField(change) ->
      optional_field.invert(
        change,
        is_rollback,
        Some(inverse_revision),
        watermark,
      )
      |> result.map(fn(output) { #(ValueField(output.0), output.1) })
    OptionalField(change) ->
      optional_field.invert(
        change,
        is_rollback,
        Some(inverse_revision),
        watermark,
      )
      |> result.map(fn(output) { #(OptionalField(output.0), output.1) })
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
      use node <- result.try(node_for(canonical, nodes, aliases))
      let NodeChange(child_fields) = node
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
      let NodeChange(fields) = entry.1
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
    ValueField(change) -> prune_concrete(change, state, aliases, True)
    OptionalField(change) -> prune_concrete(change, state, aliases, False)
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
  use node <- result.try(node_for(canonical, state.nodes, aliases))
  let NodeChange(fields) = node
  use #(fields, state) <- result.try(prune_field_map(fields, state, aliases))
  case fields {
    [] ->
      Ok(#(
        None,
        PruneState(
          remove_pair(state.nodes, canonical),
          remove_pair(state.parents, canonical),
        ),
      ))
    _ ->
      Ok(#(
        Some(id),
        PruneState(
          put_pair(state.nodes, canonical, NodeChange(fields)),
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
  use node <- result.try(node_for(canonical, data.nodes, data.aliases))
  let NodeChange(fields) = node
  removed_roots_from_fields(fields, data, roots)
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
      let candidates = case data.revisions {
        [] ->
          case tagged.revision {
            None -> []
            Some(revision) -> [
              RevisionInfo(revision, tagged.rollback_of),
            ]
          }
        revisions -> revisions
      }
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
) -> Result(Changeset, TreeError) {
  case changes {
    [] -> Ok(empty())
    [change] -> Ok(change)
    _ -> {
      let split = list.length(changes) / 2
      let #(left, right) = split_at(changes, split, [])
      use left <- result.try(balanced_compose(left, revisions, max_local_id))
      use right <- result.try(balanced_compose(right, revisions, max_local_id))
      compose_pair(left, right, revisions, max_local_id)
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
) -> Result(Changeset, TreeError) {
  let first_data = first.data
  let second_data = second.data
  use aliases <- result.try(merge_aliases(
    first_data.aliases,
    second_data.aliases,
  ))
  let state =
    ComposeState(
      merge_pairs(first_data.nodes, second_data.nodes),
      merge_pairs(first_data.parents, second_data.parents),
      aliases,
      first_data,
      second_data,
      [],
    )
  use #(fields, state) <- result.try(compose_field_maps(
    first_data.fields,
    second_data.fields,
    state,
  ))
  use #(builds, destroys, refreshers) <- result.try(compose_detached(
    first_data,
    second_data,
  ))
  from_data(ChangeData(
    max_local_id: max_local_id,
    revisions: revisions,
    fields: fields,
    nodes: state.nodes,
    parents: state.parents,
    aliases: state.aliases,
    builds: builds,
    destroys: destroys,
    refreshers: refreshers,
  ))
}

fn compose_field_maps(
  first: List(#(String, FieldChange)),
  second: List(#(String, FieldChange)),
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
  state: ComposeState,
) -> Result(#(FieldChange, ComposeState), TreeError) {
  case first, second {
    GenericField(first), GenericField(second) -> {
      use #(children, state) <- result.try(compose_generic(first, second, state))
      Ok(#(GenericField(children), state))
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
    Some(first), Some(second) -> compose_nodes(first, second, state)
    Some(first), None -> Ok(#(first, state))
    None, Some(second) -> Ok(#(second, state))
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
      use first_node <- result.try(node_for(
        first_id,
        state.first.nodes,
        state.first.aliases,
      ))
      use second_node <- result.try(node_for(
        second_id,
        state.second.nodes,
        state.second.aliases,
      ))
      let NodeChange(first_fields) = first_node
      let NodeChange(second_fields) = second_node
      let state =
        ComposeState(..state, pairs: [#(first_id, second_id), ..state.pairs])
      use #(fields, state) <- result.try(compose_field_maps(
        first_fields,
        second_fields,
        state,
      ))
      use first_canonical <- result.try(resolve_alias(first_id, state.aliases))
      use second_canonical <- result.try(resolve_alias(second_id, state.aliases))
      use #(canonical, aliases) <- result.try(unify_aliases(
        state.aliases,
        second_canonical,
        first_canonical,
      ))
      use parent <- result.try(parent_for(
        first_id,
        state.first.parents,
        state.first.aliases,
      ))
      use parent <- result.try(normalize_parent(parent, aliases))
      let nodes =
        state.nodes
        |> remove_pair(first_canonical)
        |> remove_pair(second_canonical)
        |> put_pair(canonical, NodeChange(fields))
      let parents =
        state.parents
        |> remove_pair(first_canonical)
        |> remove_pair(second_canonical)
        |> put_pair(canonical, parent)
      Ok(#(
        canonical,
        ComposeState(..state, nodes: nodes, parents: parents, aliases: aliases),
      ))
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

fn sort_atom_tables(data: ChangeData) -> ChangeData {
  ChangeData(
    ..data,
    nodes: sort_pairs(data.nodes),
    parents: sort_pairs(data.parents),
    aliases: sort_pairs(data.aliases),
    builds: list.sort(data.builds, fn(left, right) {
      compare_atom(left.id, right.id)
    }),
    destroys: list.sort(data.destroys, fn(left, right) {
      compare_atom(left.id, right.id)
    }),
    refreshers: list.sort(data.refreshers, fn(left, right) {
      compare_atom(left.id, right.id)
    }),
  )
}

fn sort_pairs(entries: List(#(AtomId, a))) -> List(#(AtomId, a)) {
  list.sort(entries, fn(left, right) { compare_atom(left.0, right.0) })
}

fn compare_atom(left: AtomId, right: AtomId) -> order.Order {
  let revision_order = compare_revision(left.revision, right.revision)
  case revision_order {
    order.Eq -> int_compare(left.local_id, right.local_id)
    _ -> revision_order
  }
}

fn compare_revision(
  left: Option(StableId),
  right: Option(StableId),
) -> order.Order {
  case left, right {
    None, None -> order.Eq
    None, Some(_) -> order.Lt
    Some(_), None -> order.Gt
    Some(left), Some(right) ->
      string.compare(
        fluid_ids.stable_id_to_string(left),
        fluid_ids.stable_id_to_string(right),
      )
  }
}

fn int_compare(left: Int, right: Int) -> order.Order {
  case left < right, left > right {
    True, _ -> order.Lt
    _, True -> order.Gt
    _, _ -> order.Eq
  }
}

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
) -> Result(#(FieldChange, List(forest.Build), Int), TreeError) {
  case cardinality, value {
    Required, Some(value) -> {
      let fill = AtomId(Some(revision), 0)
      let detach = AtomId(Some(revision), 1)
      Ok(#(
        ValueField(optional_field.set(False, fill, detach)),
        [forest.Build(fill, [value])],
        2,
      ))
    }
    Optional, Some(value) -> {
      let detach = AtomId(Some(revision), 0)
      let fill = AtomId(Some(revision), 1)
      Ok(#(
        OptionalField(optional_field.set(was_empty, fill, detach)),
        [forest.Build(fill, [value])],
        2,
      ))
    }
    Optional, None -> {
      let detach = AtomId(Some(revision), 0)
      Ok(#(OptionalField(optional_field.clear(was_empty, detach)), [], 1))
    }
    Required, None -> Error(InvalidEdit([], "required field is absent"))
  }
}

fn wrap_ancestors(
  parent_path: FieldPath,
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
  case field == "rootFieldKey" && list.is_empty(parent_path) {
    True -> Ok(#([#(field, field_change)], [], [], next_id - 1))
    False -> {
      use #(child, next_id) <- result.try(allocate(revision, next_id))
      let nodes = [#(child, NodeChange([#(field, field_change)]))]
      use #(top, nodes, parents, next_id) <- result.try(
        wrap_parent_fields(
          list.reverse(parent_path),
          child,
          revision,
          next_id,
          nodes,
          [],
        ),
      )
      Ok(#(
        [#("rootFieldKey", GenericField([#(0, top)]))],
        nodes,
        list.append(parents, [
          #(top, ParentField(None, "rootFieldKey")),
        ]),
        next_id - 1,
      ))
    }
  }
}

fn wrap_parent_fields(
  fields: FieldPath,
  child: AtomId,
  revision: StableId,
  next_id: Int,
  nodes: List(#(AtomId, NodeChange)),
  parents: List(#(AtomId, ParentField)),
) -> Result(
  #(AtomId, List(#(AtomId, NodeChange)), List(#(AtomId, ParentField)), Int),
  TreeError,
) {
  case fields {
    [] -> Ok(#(child, nodes, parents, next_id))
    [field, ..rest] -> {
      use #(parent, next_id) <- result.try(allocate(revision, next_id))
      wrap_parent_fields(
        rest,
        parent,
        revision,
        next_id,
        list.append(nodes, [
          #(parent, NodeChange([#(field, GenericField([#(0, child)]))])),
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
        list.try_map(children, fn(child) {
          delta_child(child.1, data)
          |> result.map(fn(parts) { #(child.1, parts) })
        }),
      )
      let marks =
        list.map(child_parts, fn(child) {
          forest.Mark(1, None, None, child.1.fields)
        })
      Ok(#(
        Some(forest.FieldDelta(marks)),
        list.flat_map(child_parts, fn(child) { child.1.global }),
        list.flat_map(child_parts, fn(child) { child.1.rename }),
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
          global,
          list.flat_map(child_parts, fn(child) { child.1.global }),
        ),
        list.append(
          rename,
          list.flat_map(child_parts, fn(child) { child.1.rename }),
        ),
      ))
    }
  }
}

fn delta_child(id: AtomId, data: ChangeData) -> Result(DeltaParts, TreeError) {
  use canonical <- result.try(resolve_alias(id, data.aliases))
  use node <- result.try(node_for(canonical, data.nodes, data.aliases))
  let NodeChange(fields) = node
  delta_fields(fields, data)
}

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
      let NodeChange(fields) = entry.1
      use _ <- result.try(unique_pairs(fields, "node fields"))
      validate_field_map(fields, "node fields")
    }),
  )
  use _ <- result.try(
    list.try_each(data.parents, fn(entry) {
      use _ <- result.try(validate_atom(entry.0, "node parents"))
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
    GenericField(children) -> {
      use _ <- result.try(unique_by(
        children,
        fn(child) { child.0 },
        CorruptData("generic field", "duplicate child index"),
      ))
      list.try_each(children, fn(child) {
        use _ <- result.try(check(
          child.0 == 0,
          "generic field",
          "only child index zero is supported",
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
    use actual <- result.try(parent_for(owner.id, data.parents, data.aliases))
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
  use node <- result.try(node_for(canonical, data.nodes, data.aliases))
  let owner = Ownership(canonical, parent)
  let NodeChange(fields) = node
  walk_fields(fields, Some(canonical), data, list.append(owners, [owner]), [
    canonical,
    ..stack
  ])
}

fn field_children(field: FieldChange) -> List(AtomId) {
  case field {
    GenericField(children) -> list.map(children, fn(child) { child.1 })
    ValueField(optional_field.FieldChange(_, children, _))
    | OptionalField(optional_field.FieldChange(_, children, _)) ->
      list.map(children, fn(child) { child.1 })
  }
}

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
  aliases: List(#(AtomId, AtomId)),
) -> Result(NodeChange, TreeError) {
  case nodes {
    [] -> Error(CorruptData("node changes", "live node change is missing"))
    [entry, ..rest] -> {
      use key <- result.try(resolve_alias(entry.0, aliases))
      case key == id {
        True -> Ok(entry.1)
        False -> node_for(id, rest, aliases)
      }
    }
  }
}

fn parent_for(
  id: AtomId,
  parents: List(#(AtomId, ParentField)),
  aliases: List(#(AtomId, AtomId)),
) -> Result(ParentField, TreeError) {
  case parents {
    [] -> Error(CorruptData("node parents", "live node parent is missing"))
    [entry, ..rest] -> {
      use key <- result.try(resolve_alias(entry.0, aliases))
      case key == id {
        True -> Ok(entry.1)
        False -> parent_for(id, rest, aliases)
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

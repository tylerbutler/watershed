//// Pure modular changes for the fixed SharedTree profile.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids.{type StableId}
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/types.{
  type AtomId, type TreeError, CorruptData, InvalidHistory,
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

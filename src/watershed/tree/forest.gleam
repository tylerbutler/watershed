//// Persistent content for the fixed SharedTree object profile.
////
//// Supply a fresh view ID for each independent view or import. References
//// belong to one accepted state sequence. Use a new view ID for a fork.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids.{type StableId}
import watershed/tree/schema.{type StoredSchema}
import watershed/tree/types.{
  type AtomId, type FieldPath, type TreeError, type TreeValue, AtomId,
  CorruptData, InvalidEdit, MapValue, ObjectValue,
}

const max_safe_integer = 9_007_199_254_740_991

type Node {
  Leaf(value: TreeValue)
  Object(schema_id: String, fields: List(#(String, List(Int))))
  Map(schema_id: String, entries: List(#(String, List(Int))))
}

pub opaque type NodeRef {
  NodeRef(view_id: StableId, node_id: Int)
}

pub opaque type Forest {
  Forest(
    view_id: StableId,
    schema: StoredSchema,
    root: List(Int),
    nodes: Dict(Int, Node),
    next_node_id: Int,
    detached: DetachedIndex,
  )
}

type DetachedEntry {
  DetachedEntry(
    node_id: Int,
    forest_root_id: Int,
    latest_relevant_revision: Option(StableId),
  )
}

pub opaque type DetachedIndex {
  DetachedIndex(entries: Dict(AtomId, DetachedEntry), next_root_id: Int)
}

pub type FieldDelta {
  FieldDelta(marks: List(Mark))
}

pub type Mark {
  Mark(
    count: Int,
    attach: Option(AtomId),
    detach: Option(AtomId),
    fields: List(#(String, FieldDelta)),
  )
}

pub type Build {
  Build(id: AtomId, trees: List(TreeValue))
}

pub type DetachedChange {
  DetachedChange(id: AtomId, fields: List(#(String, FieldDelta)))
}

pub type Rename {
  Rename(old_id: AtomId, new_id: AtomId, count: Int)
}

pub type Destroy {
  Destroy(id: AtomId, count: Int)
}

pub type DeltaData {
  DeltaData(
    latest_revision: Option(StableId),
    fields: List(#(String, FieldDelta)),
    build: List(Build),
    refreshers: List(Build),
    global: List(DetachedChange),
    rename: List(Rename),
    destroy: List(Destroy),
  )
}

pub opaque type Delta {
  Delta(data: DeltaData)
}

/// Read checked internal delta data.
pub fn delta_data(delta: Delta) -> DeltaData {
  delta.data
}

pub type DetachedTreeData {
  DetachedTreeData(
    id: AtomId,
    forest_root_id: Int,
    latest_relevant_revision: Option(StableId),
    value: TreeValue,
  )
}

pub type ForestData {
  ForestData(
    root: Option(TreeValue),
    detached: List(DetachedTreeData),
    next_detached_root_id: Int,
  )
}

type Parent {
  Root
  Child(id: Int)
}

type Pass {
  Detach
  Attach
}

type Work {
  Work(
    state: Forest,
    revision: Option(StableId),
    refreshers: Dict(AtomId, TreeValue),
    pending: List(#(Int, List(#(String, FieldDelta)))),
  )
}

pub fn new(
  view_id: StableId,
  schema: StoredSchema,
  root: Option(TreeValue),
) -> Result(Forest, TreeError) {
  use _ <- result.try(schema.validate_root_field(schema, root))
  let empty =
    Forest(view_id, schema, [], dict.new(), 0, DetachedIndex(dict.new(), 0))
  case root {
    None -> Ok(empty)
    Some(value) -> {
      use #(state, id) <- result.try(allocate(empty, value))
      Ok(Forest(..state, root: [id]))
    }
  }
}

pub fn locate_detached(
  state: Forest,
  id: AtomId,
) -> Result(NodeRef, TreeError) {
  use entry <- result.try(detached_entry(state, id))
  Ok(NodeRef(state.view_id, entry.node_id))
}

/// Check an internal delta. Application facades must not accept this format.
pub fn delta(data: DeltaData) -> Result(Delta, TreeError) {
  use _ <- result.try(validate_fields(data.fields))
  use _ <- result.try(validate_builds(data.build, "build"))
  use _ <- result.try(validate_builds(data.refreshers, "refreshers"))
  use _ <- result.try(unique(
    list.map(data.global, fn(change) { change.id }),
    "global",
  ))
  use _ <- result.try(
    list.try_each(data.global, fn(change) {
      use _ <- result.try(validate_atom(change.id, 1))
      validate_fields(change.fields)
    }),
  )
  let all_fields =
    list.append(
      data.fields,
      list.flat_map(data.global, fn(change) { change.fields }),
    )
  use _ <- result.try(unique(field_ids(all_fields, True), "attach sources"))
  use _ <- result.try(unique(
    field_ids(all_fields, False),
    "detach destinations",
  ))
  use _ <- result.try(
    list.try_each(data.rename, fn(rename) {
      use _ <- result.try(validate_atom(rename.old_id, rename.count))
      validate_atom(rename.new_id, rename.count)
    }),
  )
  let renames =
    list.filter(data.rename, fn(rename) { rename.old_id != rename.new_id })
  use _ <- result.try(nonoverlapping(
    list.map(renames, fn(rename) { #(rename.old_id, rename.count) }),
    "rename sources",
  ))
  use _ <- result.try(nonoverlapping(
    list.map(renames, fn(rename) { #(rename.new_id, rename.count) }),
    "rename destinations",
  ))
  use _ <- result.try(
    list.try_each(data.destroy, fn(destroy) {
      validate_atom(destroy.id, destroy.count)
    }),
  )
  use _ <- result.try(nonoverlapping(
    list.map(data.destroy, fn(destroy) { #(destroy.id, destroy.count) }),
    "destroy",
  ))
  Ok(Delta(DeltaData(..data, rename: renames)))
}

fn field_ids(
  fields: List(#(String, FieldDelta)),
  attach: Bool,
) -> List(AtomId) {
  list.flat_map(fields, fn(pair) {
    list.flat_map(pair.1.marks, fn(mark) {
      let id = case attach {
        True -> mark.attach
        False -> mark.detach
      }
      let nested = field_ids(mark.fields, attach)
      case id {
        None -> nested
        Some(id) -> [id, ..nested]
      }
    })
  })
}

/// Apply all phases to candidate state. An error leaves the input unchanged.
pub fn apply_delta(state: Forest, delta: Delta) -> Result(Forest, TreeError) {
  let data = delta.data
  use _ <- result.try(validate_applicable_fields(data.fields))
  use _ <- result.try(
    list.try_each(data.global, fn(change) {
      validate_applicable_fields(change.fields)
    }),
  )
  let refreshers =
    list.fold(data.refreshers, dict.new(), fn(acc, build) {
      list.index_fold(build.trees, acc, fn(acc, tree, index) {
        dict.insert(acc, offset(build.id, index), tree)
      })
    })
  let work = Work(state, data.latest_revision, refreshers, [])
  use work <- result.try(
    list.try_fold(data.build, work, fn(work, build) {
      build_trees(work, build.id, build.trees)
    }),
  )
  use #(work, globals) <- result.try(
    list.try_fold(data.global, #(work, []), fn(acc, change) {
      use work <- result.try(ensure_detached(acc.0, change.id))
      use entry <- result.try(detached_entry(work.state, change.id))
      let entry =
        DetachedEntry(..entry, latest_relevant_revision: work.revision)
      let state = put_entry(work.state, change.id, entry)
      let work =
        Work(
          ..work,
          state:,
          pending: list.append(work.pending, [
            #(entry.node_id, change.fields),
          ]),
        )
      Ok(#(work, [#(entry.node_id, change.fields), ..acc.1]))
    }),
  )
  use work <- result.try(visit_fields(work, Root, data.fields, Detach))
  use work <- result.try(
    list.try_fold(list.reverse(globals), work, fn(work, entry) {
      visit_fields(work, Child(entry.0), entry.1, Detach)
    }),
  )
  let transfers =
    list.flat_map(data.rename, fn(rename) {
      case rename.old_id == rename.new_id {
        True -> []
        False -> expand_rename(rename, 0, [])
      }
    })
  use work <- result.try(transfer_roots(work, transfers))
  use work <- result.try(visit_fields(work, Root, data.fields, Attach))
  use work <- result.try(finish_pending(work))
  use state <- result.try(
    list.try_fold(data.destroy, work.state, fn(state, op) {
      destroy_roots(state, op.id, op.count)
    }),
  )
  use _ <- result.try(export_data(state))
  Ok(state)
}

pub fn export_data(state: Forest) -> Result(ForestData, TreeError) {
  use #(root, visited) <- result.try(materialize_field(
    state,
    state.root,
    set.new(),
  ))
  use _ <- result.try(
    schema.validate_root_field(state.schema, root)
    |> result.map_error(fn(error) { contextual("root", error) }),
  )
  let entries =
    dict.to_list(state.detached.entries)
    |> list.sort(fn(left, right) { compare_atom(left.0, right.0) })
  use #(detached, visited) <- result.try(
    list.try_fold(entries, #([], visited), fn(acc, pair) {
      let #(id, entry) = pair
      use #(value, visited) <- result.try(materialize(
        state,
        entry.node_id,
        acc.1,
      ))
      use _ <- result.try(
        schema.validate_subtree(state.schema, value)
        |> result.map_error(fn(error) { contextual(atom_location(id), error) }),
      )
      Ok(#(
        [
          DetachedTreeData(
            id,
            entry.forest_root_id,
            entry.latest_relevant_revision,
            value,
          ),
          ..acc.0
        ],
        visited,
      ))
    }),
  )
  use _ <- result.try(check(
    set.size(visited) == dict.size(state.nodes),
    "forest",
    "unowned nodes remain",
  ))
  Ok(ForestData(root, list.reverse(detached), state.detached.next_root_id))
}

pub fn import_data(
  view_id: StableId,
  schema: StoredSchema,
  data: ForestData,
) -> Result(Forest, TreeError) {
  use _ <- result.try(check(
    data.next_detached_root_id >= 0
      && data.next_detached_root_id <= max_safe_integer,
    "detached index",
    "invalid allocation watermark",
  ))
  use _ <- result.try(unique(
    list.map(data.detached, fn(entry) { entry.id }),
    "detached identities",
  ))
  use _ <- result.try(unique(
    list.map(data.detached, fn(entry) { entry.forest_root_id }),
    "detached roots",
  ))
  use state <- result.try(
    new(view_id, schema, data.root)
    |> result.map_error(fn(error) { contextual("root", error) }),
  )
  use state <- result.try(
    list.try_fold(data.detached, state, fn(state, entry) {
      use _ <- result.try(validate_atom(entry.id, 1))
      use _ <- result.try(check(
        entry.forest_root_id >= 0
          && entry.forest_root_id < data.next_detached_root_id,
        atom_location(entry.id),
        "detached root exceeds allocation watermark",
      ))
      use _ <- result.try(
        schema.validate_subtree(schema, entry.value)
        |> result.map_error(fn(error) {
          contextual(atom_location(entry.id), error)
        }),
      )
      use #(state, node_id) <- result.try(allocate(state, entry.value))
      Ok(put_entry(
        state,
        entry.id,
        DetachedEntry(
          node_id,
          entry.forest_root_id,
          entry.latest_relevant_revision,
        ),
      ))
    }),
  )
  Ok(
    Forest(
      ..state,
      detached: DetachedIndex(
        ..state.detached,
        next_root_id: data.next_detached_root_id,
      ),
    ),
  )
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

fn contextual(location: String, error: TreeError) -> TreeError {
  CorruptData(location, string.inspect(error))
}

fn atom_location(id: AtomId) -> String {
  let revision = case id.revision {
    None -> "anonymous"
    Some(id) -> fluid_ids.stable_id_to_string(id)
  }
  "detached " <> revision <> ":" <> int.to_string(id.local_id)
}

fn compare_atom(left: AtomId, right: AtomId) -> order.Order {
  let major = case left.revision, right.revision {
    None, None -> order.Eq
    None, Some(_) -> order.Lt
    Some(_), None -> order.Gt
    Some(left), Some(right) ->
      canonical_json.compare(
        fluid_ids.stable_id_to_string(left),
        fluid_ids.stable_id_to_string(right),
      )
  }
  case major {
    order.Eq -> int.compare(left.local_id, right.local_id)
    _ -> major
  }
}

fn offset(id: AtomId, amount: Int) -> AtomId {
  AtomId(..id, local_id: id.local_id + amount)
}

fn expand_rename(
  rename: Rename,
  index: Int,
  pairs: List(#(AtomId, AtomId)),
) -> List(#(AtomId, AtomId)) {
  case index == rename.count {
    True -> list.reverse(pairs)
    False ->
      expand_rename(rename, index + 1, [
        #(offset(rename.old_id, index), offset(rename.new_id, index)),
        ..pairs
      ])
  }
}

fn validate_atom(id: AtomId, count: Int) -> Result(Nil, TreeError) {
  check(
    id.local_id >= 0
      && id.local_id <= max_safe_integer
      && count > 0
      && count <= max_safe_integer
      && count - 1 <= max_safe_integer - id.local_id,
    atom_location(id),
    "invalid identifier range",
  )
}

fn unique(values: List(a), location: String) -> Result(Nil, TreeError) {
  use _ <- result.try(
    list.try_fold(values, set.new(), fn(seen, value) {
      use _ <- result.try(check(
        !set.contains(seen, value),
        location,
        "duplicate entry",
      ))
      Ok(set.insert(seen, value))
    }),
  )
  Ok(Nil)
}

fn nonoverlapping(
  ranges: List(#(AtomId, Int)),
  location: String,
) -> Result(Nil, TreeError) {
  case ranges {
    [] -> Ok(Nil)
    [#(id, count), ..rest] -> {
      use _ <- result.try(
        list.try_each(rest, fn(other) {
          let #(other_id, other_count) = other
          check(
            id.revision != other_id.revision
              || id.local_id + count - 1 < other_id.local_id
              || other_id.local_id + other_count - 1 < id.local_id,
            location,
            "overlapping identifier ranges",
          )
        }),
      )
      nonoverlapping(rest, location)
    }
  }
}

fn validate_builds(
  builds: List(Build),
  location: String,
) -> Result(Nil, TreeError) {
  use _ <- result.try(
    list.try_each(builds, fn(build) {
      validate_atom(build.id, int.max(1, list.length(build.trees)))
    }),
  )
  nonoverlapping(
    builds
      |> list.filter(fn(build) { !list.is_empty(build.trees) })
      |> list.map(fn(build) { #(build.id, list.length(build.trees)) }),
    location,
  )
}

fn validate_fields(
  fields: List(#(String, FieldDelta)),
) -> Result(Nil, TreeError) {
  use _ <- result.try(unique(list.map(fields, fn(pair) { pair.0 }), "fields"))
  list.try_each(fields, fn(pair) {
    list.try_each(pair.1.marks, fn(mark) {
      use _ <- result.try(check(
        mark.count == 1,
        pair.0,
        "object field marks must have count one",
      ))
      use _ <- result.try(
        list.try_each([mark.attach, mark.detach], fn(id) {
          case id {
            None -> Ok(Nil)
            Some(id) -> validate_atom(id, mark.count)
          }
        }),
      )
      validate_fields(mark.fields)
    })
  })
}

fn validate_applicable_fields(
  fields: List(#(String, FieldDelta)),
) -> Result(Nil, TreeError) {
  list.try_each(fields, fn(pair) {
    list.try_each(pair.1.marks, fn(mark) {
      use _ <- result.try(check(
        list.is_empty(mark.fields) || mark.attach == None || mark.detach != None,
        pair.0,
        "attach-only mark cannot change an old child",
      ))
      validate_applicable_fields(mark.fields)
    })
  })
}

fn detached_entry(
  state: Forest,
  id: AtomId,
) -> Result(DetachedEntry, TreeError) {
  dict.get(state.detached.entries, id)
  |> result.map_error(fn(_) {
    CorruptData(atom_location(id), "detached source is missing")
  })
}

fn put_entry(state: Forest, id: AtomId, entry: DetachedEntry) -> Forest {
  Forest(
    ..state,
    detached: DetachedIndex(
      ..state.detached,
      entries: dict.insert(state.detached.entries, id, entry),
    ),
  )
}

fn remove_entry(state: Forest, id: AtomId) -> Forest {
  Forest(
    ..state,
    detached: DetachedIndex(
      ..state.detached,
      entries: dict.delete(state.detached.entries, id),
    ),
  )
}

fn register(
  state: Forest,
  id: AtomId,
  node_id: Int,
  revision: Option(StableId),
) -> Result(Forest, TreeError) {
  use _ <- result.try(check(
    !dict.has_key(state.detached.entries, id),
    atom_location(id),
    "detached destination is occupied",
  ))
  let next = state.detached.next_root_id
  use _ <- result.try(check(
    next < max_safe_integer,
    "detached index",
    "root identifiers are exhausted",
  ))
  let state = put_entry(state, id, DetachedEntry(node_id, next, revision))
  Ok(
    Forest(
      ..state,
      detached: DetachedIndex(..state.detached, next_root_id: next + 1),
    ),
  )
}

fn build_trees(
  work: Work,
  id: AtomId,
  trees: List(TreeValue),
) -> Result(Work, TreeError) {
  case trees {
    [] -> Ok(work)
    [tree, ..rest] -> {
      use _ <- result.try(
        schema.validate_subtree(work.state.schema, tree)
        |> result.map_error(fn(error) { contextual(atom_location(id), error) }),
      )
      use #(state, node_id) <- result.try(allocate(work.state, tree))
      use state <- result.try(register(state, id, node_id, work.revision))
      case rest {
        [] -> Ok(Work(..work, state:))
        _ -> build_trees(Work(..work, state:), offset(id, 1), rest)
      }
    }
  }
}

fn ensure_detached(work: Work, id: AtomId) -> Result(Work, TreeError) {
  case dict.has_key(work.state.detached.entries, id) {
    True -> Ok(work)
    False ->
      case dict.get(work.refreshers, id) {
        Ok(tree) -> build_trees(work, id, [tree])
        Error(Nil) ->
          Error(CorruptData(
            atom_location(id),
            "source and refresher are missing",
          ))
      }
  }
}

fn children(
  state: Forest,
  parent: Parent,
  key: String,
) -> Result(List(Int), TreeError) {
  case parent {
    Root ->
      case key {
        "rootFieldKey" -> Ok(state.root)
        _ -> Error(CorruptData(key, "unknown root field"))
      }
    Child(id) -> {
      use node <- result.try(get_node(state, id))
      case node {
        Leaf(_) -> Error(CorruptData(key, "cannot modify a leaf's fields"))
        Object(schema_id, fields) -> {
          use _ <- result.try(
            schema.field_schema(state.schema, schema_id, key)
            |> result.map_error(fn(error) { contextual(key, error) }),
          )
          case list.key_find(fields, key) {
            Ok(children) -> Ok(children)
            Error(Nil) -> Ok([])
          }
        }
        Map(schema_id, entries) -> {
          use _ <- result.try(
            schema.map_entry_schema(state.schema, schema_id)
            |> result.map_error(fn(error) { contextual(key, error) }),
          )
          case list.key_find(entries, key) {
            Ok(children) -> Ok(children)
            Error(Nil) -> Ok([])
          }
        }
      }
    }
  }
}

fn set_children(
  state: Forest,
  parent: Parent,
  key: String,
  children: List(Int),
) -> Result(Forest, TreeError) {
  case parent {
    Root -> Ok(Forest(..state, root: children))
    Child(id) -> {
      use node <- result.try(get_node(state, id))
      case node {
        Leaf(_) -> Error(CorruptData(key, "cannot modify a leaf's fields"))
        Object(schema_id, fields) -> {
          let fields = case children {
            [] ->
              list.map(fields, fn(pair) {
                case pair.0 == key {
                  True -> #(key, [])
                  False -> pair
                }
              })
            _ ->
              case list.key_find(fields, key) {
                Ok(_) ->
                  list.map(fields, fn(pair) {
                    case pair.0 == key {
                      True -> #(key, children)
                      False -> pair
                    }
                  })
                Error(Nil) -> list.append(fields, [#(key, children)])
              }
          }
          Ok(
            Forest(
              ..state,
              nodes: dict.insert(state.nodes, id, Object(schema_id, fields)),
            ),
          )
        }
        Map(schema_id, entries) -> {
          use _ <- result.try(check(
            list.length(children) <= 1,
            key,
            "map entry contains more than one node",
          ))
          let entries = case children {
            [] -> list.filter(entries, fn(pair) { pair.0 != key })
            _ ->
              case list.key_find(entries, key) {
                Ok(_) ->
                  list.map(entries, fn(pair) {
                    case pair.0 == key {
                      True -> #(key, children)
                      False -> pair
                    }
                  })
                Error(Nil) -> list.append(entries, [#(key, children)])
              }
          }
          Ok(
            Forest(
              ..state,
              nodes: dict.insert(state.nodes, id, Map(schema_id, entries)),
            ),
          )
        }
      }
    }
  }
}

fn child_at(
  state: Forest,
  parent: Parent,
  key: String,
  index: Int,
) -> Result(Int, TreeError) {
  use children <- result.try(children(state, parent, key))
  list.drop(children, index)
  |> list.first
  |> result.map_error(fn(_) {
    CorruptData(key, "mark has no pre-existing node")
  })
}

fn visit_fields(
  work: Work,
  parent: Parent,
  fields: List(#(String, FieldDelta)),
  pass: Pass,
) -> Result(Work, TreeError) {
  list.try_fold(fields, work, fn(work, pair) {
    use _ <- result.try(children(work.state, parent, pair.0))
    visit_marks(work, parent, pair.0, pair.1.marks, 0, pass)
  })
}

fn visit_marks(
  work: Work,
  parent: Parent,
  key: String,
  marks: List(Mark),
  index: Int,
  pass: Pass,
) -> Result(Work, TreeError) {
  case marks {
    [] -> Ok(work)
    [mark, ..rest] -> {
      use work <- result.try(case pass {
        Detach -> detach_mark(work, parent, key, mark, index)
        Attach -> attach_mark(work, parent, key, mark, index)
      })
      let advance = case pass, mark.attach, mark.detach {
        Detach, None, None -> 1
        Attach, Some(_), _ -> 1
        Attach, _, None -> 1
        _, _, _ -> 0
      }
      visit_marks(work, parent, key, rest, index + advance, pass)
    }
  }
}

fn detach_mark(
  work: Work,
  parent: Parent,
  key: String,
  mark: Mark,
  index: Int,
) -> Result(Work, TreeError) {
  use work <- result.try(case mark.fields {
    [] -> Ok(work)
    fields -> {
      use id <- result.try(child_at(work.state, parent, key, index))
      visit_fields(work, Child(id), fields, Detach)
    }
  })
  case mark.detach {
    None -> {
      use _ <- result.try(case mark.attach {
        None ->
          child_at(work.state, parent, key, index) |> result.map(fn(_) { Nil })
        Some(_) -> Ok(Nil)
      })
      Ok(work)
    }
    Some(destination) -> {
      use id <- result.try(child_at(work.state, parent, key, index))
      use before <- result.try(children(work.state, parent, key))
      use state <- result.try(set_children(
        work.state,
        parent,
        key,
        list.append(list.take(before, index), list.drop(before, index + 1)),
      ))
      use state <- result.try(register(state, destination, id, work.revision))
      let pending = case mark.fields {
        [] -> work.pending
        fields -> list.append(work.pending, [#(id, fields)])
      }
      Ok(Work(..work, state:, pending:))
    }
  }
}

fn attach_mark(
  work: Work,
  parent: Parent,
  key: String,
  mark: Mark,
  index: Int,
) -> Result(Work, TreeError) {
  use work <- result.try(case mark.attach {
    None -> Ok(work)
    Some(source) -> {
      use work <- result.try(ensure_detached(work, source))
      use entry <- result.try(detached_entry(work.state, source))
      use before <- result.try(children(work.state, parent, key))
      use _ <- result.try(check(
        index <= list.length(before),
        key,
        "attach index is outside the field",
      ))
      use state <- result.try(set_children(
        remove_entry(work.state, source),
        parent,
        key,
        list.append(list.take(before, index), [
          entry.node_id,
          ..list.drop(before, index)
        ]),
      ))
      apply_pending(Work(..work, state:), entry.node_id)
    }
  })
  case mark.detach, mark.fields {
    None, [_, ..] -> {
      use id <- result.try(child_at(work.state, parent, key, index))
      visit_fields(work, Child(id), mark.fields, Attach)
    }
    _, _ -> Ok(work)
  }
}

fn apply_pending(work: Work, id: Int) -> Result(Work, TreeError) {
  case list.key_find(work.pending, id) {
    Error(Nil) -> Ok(work)
    Ok(fields) -> {
      let work =
        Work(
          ..work,
          pending: list.filter(work.pending, fn(pair) { pair.0 != id }),
        )
      visit_fields(work, Child(id), fields, Attach)
    }
  }
}

fn finish_pending(work: Work) -> Result(Work, TreeError) {
  case work.pending {
    [] -> Ok(work)
    [#(id, _), ..] -> {
      use work <- result.try(apply_pending(work, id))
      finish_pending(work)
    }
  }
}

fn transfer_roots(
  work: Work,
  transfers: List(#(AtomId, AtomId)),
) -> Result(Work, TreeError) {
  case transfers {
    [] -> Ok(work)
    _ -> {
      use #(work, delayed) <- result.try(
        list.try_fold(transfers, #(work, []), fn(acc, pair) {
          let #(source, destination) = pair
          let work = acc.0
          use work <- result.try(
            case
              dict.has_key(work.state.detached.entries, source)
              || dict.has_key(work.refreshers, source)
            {
              True -> ensure_detached(work, source)
              False -> Ok(work)
            },
          )
          case
            dict.get(work.state.detached.entries, source),
            dict.has_key(work.state.detached.entries, destination)
          {
            Ok(entry), False -> {
              use state <- result.try(register(
                work.state,
                destination,
                entry.node_id,
                work.revision,
              ))
              let pending = case list.key_find(work.pending, entry.node_id) {
                Error(Nil) -> work.pending
                Ok(fields) ->
                  list.append(
                    list.filter(work.pending, fn(pair) {
                      pair.0 != entry.node_id
                    }),
                    [#(entry.node_id, fields)],
                  )
              }
              Ok(#(
                Work(..work, state: remove_entry(state, source), pending:),
                acc.1,
              ))
            }
            _, _ -> Ok(#(work, [pair, ..acc.1]))
          }
        }),
      )
      use _ <- result.try(check(
        list.length(delayed) < list.length(transfers),
        "rename",
        "sources are missing or destinations form an occupied cycle",
      ))
      transfer_roots(work, list.reverse(delayed))
    }
  }
}

fn destroy_roots(
  state: Forest,
  id: AtomId,
  count: Int,
) -> Result(Forest, TreeError) {
  case count {
    0 -> Ok(state)
    _ -> {
      use entry <- result.try(detached_entry(state, id))
      use #(_, descendants) <- result.try(materialize(
        state,
        entry.node_id,
        set.new(),
      ))
      let state = remove_entry(state, id)
      let state =
        Forest(
          ..state,
          nodes: list.fold(set.to_list(descendants), state.nodes, fn(nodes, id) {
            dict.delete(nodes, id)
          }),
        )
      case count {
        1 -> Ok(state)
        _ -> destroy_roots(state, offset(id, 1), count - 1)
      }
    }
  }
}

fn materialize_field(
  state: Forest,
  children: List(Int),
  visited: Set(Int),
) -> Result(#(Option(TreeValue), Set(Int)), TreeError) {
  case children {
    [] -> Ok(#(None, visited))
    [id] -> {
      use #(value, visited) <- result.try(materialize(state, id, visited))
      Ok(#(Some(value), visited))
    }
    _ -> Error(CorruptData("forest", "field contains more than one node"))
  }
}

pub fn visible_root(state: Forest) -> Result(Option(TreeValue), TreeError) {
  read(state, [])
}

pub fn read(
  state: Forest,
  path: FieldPath,
) -> Result(Option(TreeValue), TreeError) {
  use node <- result.try(walk(state, state.root, path, path))
  case node {
    None -> Ok(None)
    Some(id) ->
      materialize(state, id, set.new())
      |> result.map(fn(pair) { Some(pair.0) })
  }
}

/// Return the schema identifier for a map node.
pub fn map_type(state: Forest, path: FieldPath) -> Result(String, TreeError) {
  use #(schema_id, _) <- result.try(map_node(state, path))
  Ok(schema_id)
}

/// Read one entry from a map node.
pub fn map_get(
  state: Forest,
  path: FieldPath,
  key: String,
) -> Result(Option(TreeValue), TreeError) {
  use #(_, entries) <- result.try(map_node(state, path))
  let children = list.key_find(entries, key) |> result.unwrap([])
  materialize_field(state, children, set.new())
  |> result.map(fn(pair) { pair.0 })
}

/// Read all present entries from a map node in canonical key order.
pub fn map_entries(
  state: Forest,
  path: FieldPath,
) -> Result(List(#(String, TreeValue)), TreeError) {
  use #(_, entries) <- result.try(map_node(state, path))
  use #(values, _) <- result.try(
    list.try_fold(entries, #([], set.new()), fn(acc, entry) {
      use #(value, visited) <- result.try(materialize_field(
        state,
        entry.1,
        acc.1,
      ))
      case value {
        None -> Error(CorruptData(entry.0, "map entry is empty"))
        Some(value) -> Ok(#([#(entry.0, value), ..acc.0], visited))
      }
    }),
  )
  values
  |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
  |> Ok
}

pub fn locate(state: Forest, path: FieldPath) -> Result(NodeRef, TreeError) {
  use node <- result.try(walk(state, state.root, path, path))
  case node {
    None -> Error(InvalidEdit(path, "field is absent"))
    Some(id) -> Ok(NodeRef(state.view_id, id))
  }
}

pub fn read_node(state: Forest, node: NodeRef) -> Result(TreeValue, TreeError) {
  use id <- result.try(reference_id(state, node))
  materialize(state, id, set.new()) |> result.map(fn(pair) { pair.0 })
}

pub fn is_attached(state: Forest, node: NodeRef) -> Result(Bool, TreeError) {
  use id <- result.try(reference_id(state, node))
  use visited <- result.try(
    list.try_fold(state.root, set.new(), fn(visited, root) {
      materialize(state, root, visited) |> result.map(fn(pair) { pair.1 })
    }),
  )
  Ok(set.contains(visited, id))
}

fn reference_id(state: Forest, node: NodeRef) -> Result(Int, TreeError) {
  case node.view_id == state.view_id, dict.has_key(state.nodes, node.node_id) {
    False, _ -> Error(InvalidEdit([], "node reference belongs to another view"))
    True, False -> Error(InvalidEdit([], "node reference is no longer valid"))
    True, True -> Ok(node.node_id)
  }
}

fn map_node(
  state: Forest,
  path: FieldPath,
) -> Result(#(String, List(#(String, List(Int)))), TreeError) {
  use node <- result.try(walk(state, state.root, path, path))
  case node {
    None -> Error(InvalidEdit(path, "field is absent"))
    Some(id) -> {
      use node <- result.try(get_node(state, id))
      case node {
        Map(schema_id, entries) -> Ok(#(schema_id, entries))
        Leaf(_) | Object(_, _) -> Error(InvalidEdit(path, "node is not a map"))
      }
    }
  }
}

fn walk(
  state: Forest,
  children: List(Int),
  path: FieldPath,
  full_path: FieldPath,
) -> Result(Option(Int), TreeError) {
  case children, path {
    [], [] -> Ok(None)
    [], _ -> Error(InvalidEdit(full_path, "parent field is absent"))
    [id], [] -> Ok(Some(id))
    [id], [field, ..rest] -> {
      use node <- result.try(get_node(state, id))
      case node {
        Leaf(_) -> Error(InvalidEdit(full_path, "cannot traverse a leaf"))
        Object(schema_id, fields) ->
          case list.key_find(fields, field) {
            Ok(children) -> walk(state, children, rest, full_path)
            Error(Nil) -> {
              use _ <- result.try(
                schema.validate_field(state.schema, schema_id, field, None)
                |> result.map_error(fn(_) {
                  InvalidEdit(full_path, "field is not an optional field")
                }),
              )
              walk(state, [], rest, full_path)
            }
          }
        Map(_, entries) ->
          case list.key_find(entries, field) {
            Ok(children) -> walk(state, children, rest, full_path)
            Error(Nil) -> walk(state, [], rest, full_path)
          }
      }
    }
    _, _ -> Error(CorruptData("forest", "field contains more than one node"))
  }
}

fn get_node(state: Forest, id: Int) -> Result(Node, TreeError) {
  dict.get(state.nodes, id)
  |> result.map_error(fn(_) {
    CorruptData("forest node " <> int.to_string(id), "node is missing")
  })
}

fn allocate(
  state: Forest,
  value: TreeValue,
) -> Result(#(Forest, Int), TreeError) {
  case state.next_node_id >= max_safe_integer {
    True -> Error(CorruptData("forest", "node identifiers are exhausted"))
    False -> {
      let id = state.next_node_id
      let state = Forest(..state, next_node_id: id + 1)
      use #(state, node) <- result.try(case value {
        ObjectValue(schema_id, fields) -> {
          use #(state, fields) <- result.try(
            list.try_fold(fields, #(state, []), fn(acc, field) {
              use #(state, child) <- result.try(allocate(acc.0, field.1))
              Ok(#(state, [#(field.0, [child]), ..acc.1]))
            }),
          )
          Ok(#(state, Object(schema_id, list.reverse(fields))))
        }
        MapValue(schema_id, entries) -> {
          use #(state, entries) <- result.try(
            list.try_fold(entries, #(state, []), fn(acc, entry) {
              use #(state, child) <- result.try(allocate(acc.0, entry.1))
              Ok(#(state, [#(entry.0, [child]), ..acc.1]))
            }),
          )
          Ok(#(state, Map(schema_id, list.reverse(entries))))
        }
        _ -> Ok(#(state, Leaf(value)))
      })
      Ok(#(Forest(..state, nodes: dict.insert(state.nodes, id, node)), id))
    }
  }
}

fn materialize(
  state: Forest,
  id: Int,
  visited: Set(Int),
) -> Result(#(TreeValue, Set(Int)), TreeError) {
  use _ <- result.try(case set.contains(visited, id) {
    True -> Error(CorruptData("forest", "node has multiple owners or a cycle"))
    False -> Ok(Nil)
  })
  use node <- result.try(get_node(state, id))
  let visited = set.insert(visited, id)
  case node {
    Leaf(value) -> Ok(#(value, visited))
    Object(schema_id, fields) -> {
      use #(values, visited) <- result.try(
        list.try_fold(fields, #([], visited), fn(acc, field) {
          case field.1 {
            [] -> Ok(acc)
            [child] -> {
              use #(value, visited) <- result.try(materialize(
                state,
                child,
                acc.1,
              ))
              Ok(#([#(field.0, value), ..acc.0], visited))
            }
            _ ->
              Error(CorruptData(field.0, "field contains more than one node"))
          }
        }),
      )
      Ok(#(ObjectValue(schema_id, list.reverse(values)), visited))
    }
    Map(schema_id, entries) -> {
      use #(values, visited) <- result.try(
        list.try_fold(entries, #([], visited), fn(acc, entry) {
          case entry.1 {
            [child] -> {
              use #(value, visited) <- result.try(materialize(
                state,
                child,
                acc.1,
              ))
              Ok(#([#(entry.0, value), ..acc.0], visited))
            }
            [] -> Error(CorruptData(entry.0, "map entry is empty"))
            _ ->
              Error(CorruptData(entry.0, "field contains more than one node"))
          }
        }),
      )
      let values =
        values
        |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
      Ok(#(MapValue(schema_id, values), visited))
    }
  }
}

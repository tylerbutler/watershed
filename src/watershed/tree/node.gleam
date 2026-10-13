//// Pure edits that resolve captured node references against current tree state.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/tree/forest
import watershed/tree/types
import watershed/tree_kernel

pub type Edit {
  SetField(key: String, value: types.TreeValue)
  ClearField(key: String)
  MapSet(key: String, value: types.TreeValue)
  MapDelete(key: String)
  ArrayInsert(index: Int, values: List(types.TreeValue))
  ArrayRemove(start: Int, end: Int)
  ArrayMove(
    start: Int,
    end: Int,
    destination: forest.NodeRef,
    destination_gap: Int,
  )
  RemoveNode(child: forest.NodeRef)
  MoveNode(
    child: forest.NodeRef,
    destination: forest.NodeRef,
    before: Option(forest.NodeRef),
  )
}

pub fn resolve(
  state: tree_kernel.TreeState,
  source: forest.NodeRef,
  edit: Edit,
) -> Result(types.Edit, types.TreeError) {
  use path <- result.try(tree_kernel.reference_path(state, source))
  case edit {
    SetField(key, value) -> Ok(types.SetField(list.append(path, [key]), value))
    ClearField(key) -> Ok(types.ClearField(list.append(path, [key])))
    MapSet(key, value) -> Ok(types.MapSet(path, key, value))
    MapDelete(key) -> Ok(types.MapDelete(path, key))
    ArrayInsert(index, values) -> Ok(types.ArrayInsert(path, index, values))
    ArrayRemove(start, end) -> Ok(types.ArrayRemove(path, start, end))
    ArrayMove(start, end, destination, gap) -> {
      use target <- result.try(tree_kernel.reference_path(state, destination))
      Ok(types.ArrayMove(path, start, end, target, gap))
    }
    RemoveNode(child) -> resolve_remove(state, source, child)
    MoveNode(child, destination, before) ->
      resolve_move(state, source, child, destination, before)
  }
}

fn resolve_remove(
  state: tree_kernel.TreeState,
  source: forest.NodeRef,
  child: forest.NodeRef,
) -> Result(types.Edit, types.TreeError) {
  use path <- result.try(tree_kernel.reference_path(state, source))
  use _ <- result.try(tree_kernel.reference_path(state, child))
  use children <- result.try(tree_kernel.array_references(state, source))
  use index <- result.try(direct_child_index(children, child, path))
  Ok(types.ArrayRemove(path, index, index + 1))
}

fn resolve_move(
  state: tree_kernel.TreeState,
  source: forest.NodeRef,
  child: forest.NodeRef,
  destination: forest.NodeRef,
  before: Option(forest.NodeRef),
) -> Result(types.Edit, types.TreeError) {
  use destination_path <- result.try(tree_kernel.reference_path(
    state,
    destination,
  ))
  use destination_children <- result.try(tree_kernel.array_references(
    state,
    destination,
  ))
  use gap <- result.try(case before {
    None -> Ok(list.length(destination_children))
    Some(sibling) -> {
      use _ <- result.try(tree_kernel.reference_path(state, sibling))
      direct_child_index(destination_children, sibling, destination_path)
    }
  })
  use source_path <- result.try(tree_kernel.reference_path(state, source))
  use _ <- result.try(tree_kernel.reference_path(state, child))
  use source_children <- result.try(tree_kernel.array_references(state, source))
  use index <- result.try(direct_child_index(
    source_children,
    child,
    source_path,
  ))
  Ok(types.ArrayMove(source_path, index, index + 1, destination_path, gap))
}

fn direct_child_index(
  children: List(forest.NodeRef),
  child: forest.NodeRef,
  path: types.FieldPath,
) -> Result(Int, types.TreeError) {
  find_child(children, child, 0)
  |> result.map_error(fn(_) {
    types.InvalidEdit(path, "node is not a direct array child")
  })
}

fn find_child(
  children: List(forest.NodeRef),
  child: forest.NodeRef,
  index: Int,
) -> Result(Int, Nil) {
  case children {
    [] -> Error(Nil)
    [candidate, ..rest] ->
      case candidate == child {
        True -> Ok(index)
        False -> find_child(rest, child, index + 1)
      }
  }
}

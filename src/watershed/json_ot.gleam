//// Pure port of `ottypes/json0` (`lib/json0.js`) — the JSON OT algebra:
//// an inspectable JSON value model plus `apply`, `transform` (TP1),
//// `compose`, and `invert`. No process, no state; the stateful client
//// kernel that rides the watershed sequencer lives in `json_ot_kernel`.
////
//// Modeling note: the reference type stores components as JS objects with
//// independent optional fields (`oi`,`od`,`li`,`ld`,`lm`,`na`,`t`/`o`) and
//// the transform matrix branches on which are present (replace = `oi`+`od`,
//// list replace = `li`+`ld`). We mirror that with an optional-field
//// `Component` record rather than a single-edit sum so the port stays
//// mechanical and TP1-faithful.
////
//// Objects are kept sorted by key so structural equality (`==`) is a valid
//// convergence oracle. Legacy `si`/`sd` string ops are not modeled; use the
//// `text0` subtype (`t`/`o`) instead, matching modern json0 usage.

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

// ─────────────────────────────────────────────────────────────────────────────
// JSON value model
// ─────────────────────────────────────────────────────────────────────────────

/// An inspectable JSON value. `VObject` members are always held sorted by
/// key so `==` is canonical (order-independent) equality.
pub type JsonValue {
  VNull
  VBool(Bool)
  VNumber(Num)
  VString(String)
  VArray(List(JsonValue))
  VObject(List(#(String, JsonValue)))
}

/// JSON numbers keep the int/float distinction the wire codec draws.
pub type Num {
  NInt(Int)
  NFloat(Float)
}

/// A JSON pointer step: an object member or an array position.
pub type PathKey {
  Key(String)
  Index(Int)
}

/// A json0 op component: a path plus whichever edit fields are set. At most
/// one "family" is populated per component, except the deliberate combos
/// `oi`+`od` (object replace) and `li`+`ld` (list replace).
pub type Component {
  Component(
    path: List(PathKey),
    oi: Option(JsonValue),
    od: Option(JsonValue),
    li: Option(JsonValue),
    ld: Option(JsonValue),
    lm: Option(Int),
    na: Option(Num),
    subtype: Option(#(String, JsonValue)),
  )
}

/// An op is an ordered list of components.
pub type Op =
  List(Component)

pub type Side {
  Lft
  Rgt
}

pub type OtError {
  BadPath(detail: String)
  BadValue(detail: String)
  UnknownSubtype(name: String)
}

// ─────────────────────────────────────────────────────────────────────────────
// Component constructors (keep call sites readable)
// ─────────────────────────────────────────────────────────────────────────────

fn empty(path: List(PathKey)) -> Component {
  Component(
    path: path,
    oi: None,
    od: None,
    li: None,
    ld: None,
    lm: None,
    na: None,
    subtype: None,
  )
}

pub fn obj_insert(path: List(PathKey), value: JsonValue) -> Component {
  Component(..empty(path), oi: Some(value))
}

pub fn obj_delete(path: List(PathKey), value: JsonValue) -> Component {
  Component(..empty(path), od: Some(value))
}

pub fn obj_replace(
  path: List(PathKey),
  old: JsonValue,
  new: JsonValue,
) -> Component {
  Component(..empty(path), od: Some(old), oi: Some(new))
}

pub fn list_insert(path: List(PathKey), value: JsonValue) -> Component {
  Component(..empty(path), li: Some(value))
}

pub fn list_delete(path: List(PathKey), value: JsonValue) -> Component {
  Component(..empty(path), ld: Some(value))
}

pub fn list_replace(
  path: List(PathKey),
  old: JsonValue,
  new: JsonValue,
) -> Component {
  Component(..empty(path), ld: Some(old), li: Some(new))
}

pub fn list_move(path: List(PathKey), to: Int) -> Component {
  Component(..empty(path), lm: Some(to))
}

pub fn number_add(path: List(PathKey), delta: Num) -> Component {
  Component(..empty(path), na: Some(delta))
}

pub fn subtype_component(
  path: List(PathKey),
  name: String,
  op: JsonValue,
) -> Component {
  Component(..empty(path), subtype: Some(#(name, op)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Object helpers (maintain sorted-by-key invariant)
// ─────────────────────────────────────────────────────────────────────────────

fn obj_get(
  members: List(#(String, JsonValue)),
  key: String,
) -> Option(JsonValue) {
  case list.key_find(members, key) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn obj_set(
  members: List(#(String, JsonValue)),
  key: String,
  value: JsonValue,
) -> List(#(String, JsonValue)) {
  let without = list.filter(members, fn(pair) { pair.0 != key })
  insert_sorted(without, key, value)
}

fn insert_sorted(
  members: List(#(String, JsonValue)),
  key: String,
  value: JsonValue,
) -> List(#(String, JsonValue)) {
  case members {
    [] -> [#(key, value)]
    [first, ..rest] ->
      case string.compare(key, first.0) {
        order.Lt -> [#(key, value), first, ..rest]
        _ -> [first, ..insert_sorted(rest, key, value)]
      }
  }
}

fn obj_remove(
  members: List(#(String, JsonValue)),
  key: String,
) -> List(#(String, JsonValue)) {
  list.filter(members, fn(pair) { pair.0 != key })
}

// ─────────────────────────────────────────────────────────────────────────────
// Number helpers
// ─────────────────────────────────────────────────────────────────────────────

fn num_add(a: Num, b: Num) -> Num {
  case a, b {
    NInt(x), NInt(y) -> NInt(x + y)
    NInt(x), NFloat(y) -> NFloat(int.to_float(x) +. y)
    NFloat(x), NInt(y) -> NFloat(x +. int.to_float(y))
    NFloat(x), NFloat(y) -> NFloat(x +. y)
  }
}

fn num_negate(a: Num) -> Num {
  case a {
    NInt(x) -> NInt(-x)
    NFloat(x) -> NFloat(0.0 -. x)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// apply
// ─────────────────────────────────────────────────────────────────────────────

/// Apply a full op to a document, component by component (json0 `apply`).
pub fn apply(doc: JsonValue, op: Op) -> Result(JsonValue, OtError) {
  list.try_fold(op, doc, apply_component)
}

fn apply_component(
  doc: JsonValue,
  component: Component,
) -> Result(JsonValue, OtError) {
  case component.path {
    [] -> edit_root(doc, component)
    _ -> {
      let #(parent_path, last) = split_last(component.path)
      update_at(doc, parent_path, fn(container) {
        edit_in_container(container, last, component)
      })
    }
  }
}

fn split_last(path: List(PathKey)) -> #(List(PathKey), PathKey) {
  do_split_last(path, [])
}

fn do_split_last(
  path: List(PathKey),
  acc: List(PathKey),
) -> #(List(PathKey), PathKey) {
  case path {
    [] -> panic as "split_last on empty path"
    [only] -> #(list.reverse(acc), only)
    [first, ..rest] -> do_split_last(rest, [first, ..acc])
  }
}

/// Functional update: navigate `path` into `doc` and replace the reached
/// sub-value with `f(sub)`.
fn update_at(
  doc: JsonValue,
  path: List(PathKey),
  f: fn(JsonValue) -> Result(JsonValue, OtError),
) -> Result(JsonValue, OtError) {
  case path {
    [] -> f(doc)
    [Key(key), ..rest] ->
      case doc {
        VObject(members) ->
          case obj_get(members, key) {
            Some(child) ->
              update_at(child, rest, f)
              |> result.map(fn(updated) {
                VObject(obj_set(members, key, updated))
              })
            None -> Error(BadPath("object key not found: " <> key))
          }
        _ -> Error(BadPath("expected object at path step " <> key))
      }
    [Index(index), ..rest] ->
      case doc {
        VArray(items) ->
          case list_at(items, index) {
            Ok(child) ->
              update_at(child, rest, f)
              |> result.map(fn(updated) {
                VArray(list_set(items, index, updated))
              })
            Error(_) ->
              Error(BadPath("list index out of range: " <> int.to_string(index)))
          }
        _ ->
          Error(BadPath("expected array at path step " <> int.to_string(index)))
      }
  }
}

/// Apply an edit whose path is empty — it targets the document root.
fn edit_root(doc: JsonValue, c: Component) -> Result(JsonValue, OtError) {
  case c {
    Component(oi: Some(value), ..) -> Ok(value)
    Component(na: Some(delta), ..) ->
      case doc {
        VNumber(n) -> Ok(VNumber(num_add(n, delta)))
        _ -> Error(BadValue("na target is not a number"))
      }
    Component(subtype: Some(#(name, sub_op)), ..) ->
      apply_subtype(name, doc, sub_op)
    Component(od: Some(_), ..) -> Ok(VNull)
    _ -> Error(BadValue("invalid or missing instruction at root"))
  }
}

/// Apply an edit at `key` within `container` (its parent).
fn edit_in_container(
  container: JsonValue,
  key: PathKey,
  c: Component,
) -> Result(JsonValue, OtError) {
  case key {
    Key(member_key) -> edit_object_member(container, member_key, c)
    Index(index) -> edit_list_element(container, index, c)
  }
}

fn edit_object_member(
  container: JsonValue,
  key: String,
  c: Component,
) -> Result(JsonValue, OtError) {
  case container {
    VObject(members) ->
      case c {
        Component(oi: Some(value), ..) ->
          Ok(VObject(obj_set(members, key, value)))
        Component(od: Some(_), ..) -> Ok(VObject(obj_remove(members, key)))
        Component(na: Some(delta), ..) ->
          edit_member_value(members, key, fn(v) {
            case v {
              VNumber(n) -> Ok(VNumber(num_add(n, delta)))
              _ -> Error(BadValue("na target is not a number"))
            }
          })
        Component(subtype: Some(#(name, sub_op)), ..) ->
          edit_member_value(members, key, fn(v) {
            apply_subtype(name, v, sub_op)
          })
        _ -> Error(BadValue("invalid object edit at key " <> key))
      }
    _ -> Error(BadPath("expected object for key " <> key))
  }
}

fn edit_member_value(
  members: List(#(String, JsonValue)),
  key: String,
  f: fn(JsonValue) -> Result(JsonValue, OtError),
) -> Result(JsonValue, OtError) {
  case obj_get(members, key) {
    Some(value) ->
      f(value)
      |> result.map(fn(updated) { VObject(obj_set(members, key, updated)) })
    None -> Error(BadPath("object key not found: " <> key))
  }
}

fn edit_list_element(
  container: JsonValue,
  index: Int,
  c: Component,
) -> Result(JsonValue, OtError) {
  case container {
    VArray(items) ->
      case c {
        // List replace
        Component(li: Some(value), ld: Some(_), ..) ->
          case list_at(items, index) {
            Ok(_) -> Ok(VArray(list_set(items, index, value)))
            Error(_) -> Error(BadPath("list replace out of range"))
          }
        // List insert
        Component(li: Some(value), ..) ->
          Ok(VArray(list_insert_at(items, index, value)))
        // List delete
        Component(ld: Some(_), ..) ->
          case list_delete_at(items, index) {
            Ok(updated) -> Ok(VArray(updated))
            Error(_) -> Error(BadPath("list delete out of range"))
          }
        // List move
        Component(lm: Some(to), ..) ->
          case list_move_element(items, index, to) {
            Ok(updated) -> Ok(VArray(updated))
            Error(_) -> Error(BadPath("list move out of range"))
          }
        Component(na: Some(delta), ..) ->
          edit_element_value(items, index, fn(v) {
            case v {
              VNumber(n) -> Ok(VNumber(num_add(n, delta)))
              _ -> Error(BadValue("na target is not a number"))
            }
          })
        Component(subtype: Some(#(name, sub_op)), ..) ->
          edit_element_value(items, index, fn(v) {
            apply_subtype(name, v, sub_op)
          })
        _ -> Error(BadValue("invalid list edit"))
      }
    _ -> Error(BadPath("expected array for index"))
  }
}

fn edit_element_value(
  items: List(JsonValue),
  index: Int,
  f: fn(JsonValue) -> Result(JsonValue, OtError),
) -> Result(JsonValue, OtError) {
  case list_at(items, index) {
    Ok(value) ->
      f(value)
      |> result.map(fn(updated) { VArray(list_set(items, index, updated)) })
    Error(_) -> Error(BadPath("list index out of range"))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List helpers
// ─────────────────────────────────────────────────────────────────────────────

fn list_at(items: List(JsonValue), index: Int) -> Result(JsonValue, Nil) {
  case index < 0 {
    True -> Error(Nil)
    False -> do_list_at(items, index)
  }
}

fn do_list_at(items: List(JsonValue), index: Int) -> Result(JsonValue, Nil) {
  case items, index {
    [], _ -> Error(Nil)
    [first, ..], 0 -> Ok(first)
    [_, ..rest], _ -> do_list_at(rest, index - 1)
  }
}

fn list_set(
  items: List(JsonValue),
  index: Int,
  value: JsonValue,
) -> List(JsonValue) {
  list.index_map(items, fn(item, i) {
    case i == index {
      True -> value
      False -> item
    }
  })
}

fn list_insert_at(
  items: List(JsonValue),
  index: Int,
  value: JsonValue,
) -> List(JsonValue) {
  let #(before, after) = list.split(items, index)
  list.append(before, [value, ..after])
}

fn list_delete_at(
  items: List(JsonValue),
  index: Int,
) -> Result(List(JsonValue), Nil) {
  case list_at(items, index) {
    Ok(_) -> {
      let #(before, after) = list.split(items, index)
      case after {
        [_, ..rest] -> Ok(list.append(before, rest))
        [] -> Error(Nil)
      }
    }
    Error(_) -> Error(Nil)
  }
}

fn list_move_element(
  items: List(JsonValue),
  from: Int,
  to: Int,
) -> Result(List(JsonValue), Nil) {
  case from == to {
    True -> Ok(items)
    False ->
      case list_at(items, from) {
        Ok(element) ->
          case list_delete_at(items, from) {
            Ok(without) -> Ok(list_insert_at(without, to, element))
            Error(_) -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Path arithmetic (transform helpers)
// ─────────────────────────────────────────────────────────────────────────────

/// A component's path length adjusted the way json0 does: `na`/subtype ops
/// conceptually reach one step deeper than their explicit path.
fn adj_len(c: Component) -> Int {
  let extra = case c.na, c.subtype {
    None, None -> 0
    _, _ -> 1
  }
  list.length(c.path) + extra
}

/// json0's `commonLengthForOps(a, b)`: the shared operand-prefix length, or
/// `None` (its `null`). `Some(-1)` mirrors the `a` reaches root case.
fn common_length(a: Component, b: Component) -> Option(Int) {
  let alen = adj_len(a)
  let blen = adj_len(b)
  case alen == 0 {
    True -> Some(-1)
    False ->
      case blen == 0 {
        True -> None
        False -> common_loop(a.path, b.path, 0, alen - 1, blen - 1)
      }
  }
}

fn common_loop(
  ap: List(PathKey),
  bp: List(PathKey),
  i: Int,
  alen: Int,
  blen: Int,
) -> Option(Int) {
  case i >= alen {
    True -> Some(alen)
    False ->
      case i >= blen {
        True -> None
        False ->
          case pk_at(ap, i) == pk_at(bp, i) {
            True -> common_loop(ap, bp, i + 1, alen, blen)
            False -> None
          }
      }
  }
}

fn pk_at(path: List(PathKey), i: Int) -> Option(PathKey) {
  case i < 0 {
    True -> None
    False ->
      case list_at_generic(path, i) {
        Ok(pk) -> Some(pk)
        Error(_) -> None
      }
  }
}

fn list_at_generic(items: List(a), index: Int) -> Result(a, Nil) {
  case items, index {
    [], _ -> Error(Nil)
    [first, ..], 0 -> Ok(first)
    [_, ..rest], _ -> list_at_generic(rest, index - 1)
  }
}

/// The numeric index value at position `i` (list branches only). Returns a
/// sentinel for non-index / out-of-range positions, which those branches
/// never actually consume.
fn idx_at(path: List(PathKey), i: Int) -> Int {
  case pk_at(path, i) {
    Some(Index(n)) -> n
    _ -> -999_999
  }
}

fn map_path_at(
  path: List(PathKey),
  i: Int,
  f: fn(PathKey) -> PathKey,
) -> List(PathKey) {
  list.index_map(path, fn(pk, j) {
    case j == i {
      True -> f(pk)
      False -> pk
    }
  })
}

fn bump_idx_at(path: List(PathKey), i: Int, delta: Int) -> List(PathKey) {
  map_path_at(path, i, fn(pk) {
    case pk {
      Index(n) -> Index(n + delta)
      other -> other
    }
  })
}

fn set_idx_at(path: List(PathKey), i: Int, value: Int) -> List(PathKey) {
  map_path_at(path, i, fn(_) { Index(value) })
}

// ─────────────────────────────────────────────────────────────────────────────
// compose-append (json0 `append`): merges adjacent same-path components
// ─────────────────────────────────────────────────────────────────────────────

fn append(dest: Op, c: Component) -> Op {
  case split_last_component(dest) {
    None -> [c]
    Some(#(init, last)) ->
      case last.path == c.path {
        False -> list.append(dest, [c])
        True ->
          case merge_pair(last, c) {
            MergeReplace(new_last) -> list.append(init, [new_last])
            MergeDropBoth -> init
            KeepDest -> dest
            NoMerge -> list.append(dest, [c])
          }
      }
  }
}

type Merge {
  MergeReplace(Component)
  MergeDropBoth
  KeepDest
  NoMerge
}

fn merge_pair(last: Component, c: Component) -> Merge {
  case last, c {
    // na + na compress
    Component(na: Some(a), ..), Component(na: Some(b), ..) ->
      MergeReplace(number_add(last.path, num_add(a, b)))
    // list insert immediately followed by its delete → noop / drop the insert
    Component(li: Some(lv), ..), Component(li: None, ld: Some(cd), ..)
      if cd == lv
    ->
      case last.ld {
        Some(_) -> MergeReplace(Component(..last, li: None))
        None -> MergeDropBoth
      }
    // object delete then insert → replace
    Component(od: Some(_), oi: None, ..), Component(oi: Some(civ), od: None, ..)
    -> MergeReplace(Component(..last, oi: Some(civ)))
    // object insert then delete/replace → merge
    Component(oi: Some(_), ..), Component(od: Some(_), ..) ->
      case c.oi, last.od {
        Some(civ), _ -> MergeReplace(Component(..last, oi: Some(civ)))
        None, Some(_) -> MergeReplace(Component(..last, oi: None))
        None, None -> MergeDropBoth
      }
    // list move onto its own position → drop
    _, Component(lm: Some(target), ..) ->
      case last_index_of(c.path) == Some(target) {
        True -> KeepDest
        False -> NoMerge
      }
    _, _ -> NoMerge
  }
}

fn last_index_of(path: List(PathKey)) -> Option(Int) {
  case list.last(path) {
    Ok(Index(n)) -> Some(n)
    _ -> None
  }
}

fn split_last_component(op: Op) -> Option(#(Op, Component)) {
  case op {
    [] -> None
    _ -> {
      let reversed = list.reverse(op)
      case reversed {
        [last, ..rev_init] -> Some(#(list.reverse(rev_init), last))
        [] -> None
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// transform (TP1) — json0 `transformComponent` + `bootstrapTransform`
// ─────────────────────────────────────────────────────────────────────────────

/// Transform `op` so it applies after `other`, breaking ties by `side`
/// (json0's `left`/`right`). TP1: for any concurrent pair,
/// `apply(apply(d,a), transform(b,a,Rgt)) == apply(apply(d,b), transform(a,b,Lft))`.
pub fn transform(op: Op, other: Op, side: Side) -> Result(Op, OtError) {
  case other {
    [] -> Ok(op)
    _ ->
      case op, other {
        [a], [b] -> transform_component_into([], a, b, side)
        _, _ ->
          case side {
            Lft -> transform_x(op, other) |> result.map(fn(pair) { pair.0 })
            Rgt -> transform_x(other, op) |> result.map(fn(pair) { pair.1 })
          }
      }
  }
}

fn transform_component_into(
  dest: Op,
  c: Component,
  other: Component,
  side: Side,
) -> Result(Op, OtError) {
  use to_append <- result.try(transform_component(c, other, side))
  Ok(list.fold(to_append, dest, append))
}

/// json0 `transformX`: N² cross-transform of two ops, returning
/// `#(leftOp', rightOp')`.
fn transform_x(left_op: Op, right_op: Op) -> Result(#(Op, Op), OtError) {
  do_transform_x(right_op, left_op, [])
}

fn do_transform_x(
  right_op: Op,
  left_op: Op,
  new_right: Op,
) -> Result(#(Op, Op), OtError) {
  case right_op {
    [] -> Ok(#(left_op, new_right))
    [right_c, ..rest_right] -> {
      use #(new_left, new_right2) <- result.try(inner_loop(
        left_op,
        right_c,
        [],
        new_right,
      ))
      do_transform_x(rest_right, new_left, new_right2)
    }
  }
}

fn inner_loop(
  left_remaining: Op,
  right_c: Component,
  new_left: Op,
  new_right: Op,
) -> Result(#(Op, Op), OtError) {
  case left_remaining {
    [] -> Ok(#(new_left, append(new_right, right_c)))
    [l, ..rest] -> {
      use new_left2 <- result.try(transform_component_into(
        new_left,
        l,
        right_c,
        Lft,
      ))
      use next_c <- result.try(transform_component(right_c, l, Rgt))
      case next_c {
        [single] -> inner_loop(rest, single, new_left2, new_right)
        [] -> Ok(#(list.fold(rest, new_left2, append), new_right))
        multi -> {
          use #(p0, p1) <- result.try(transform_x(rest, multi))
          Ok(#(
            list.fold(p0, new_left2, append),
            list.fold(p1, new_right, append),
          ))
        }
      }
    }
  }
}

/// json0 `transformComponent`: transform a single component `c` past a single
/// `other`, returning the (0, 1, or 2) components to append to the result.
fn transform_component(
  c: Component,
  other: Component,
  side: Side,
) -> Result(List(Component), OtError) {
  let cplength = adj_len(c)
  let other_len = adj_len(other)
  let common = common_length(other, c)
  let common2 = common_length(c, other)
  use c <- result.try(apply_preimage(c, other, common2, cplength, other_len))
  case common {
    None -> Ok([c])
    Some(common) ->
      transform_matrix(c, other, side, common, cplength, other_len)
  }
}

/// If `c` deletes a subtree that `other` edits, fold `other`'s edit into the
/// stored pre-image so `invert` stays exact (json0's `common2` block).
fn apply_preimage(
  c: Component,
  other: Component,
  common2: Option(Int),
  cplength: Int,
  other_len: Int,
) -> Result(Component, OtError) {
  case common2 {
    None -> Ok(c)
    Some(k) ->
      case other_len > cplength && pk_at(c.path, k) == pk_at(other.path, k) {
        False -> Ok(c)
        True -> {
          let oc = Component(..other, path: list.drop(other.path, cplength))
          case c.ld, c.od {
            Some(ldv), _ ->
              apply(ldv, [oc])
              |> result.map(fn(v) { Component(..c, ld: Some(v)) })
            None, Some(odv) ->
              apply(odv, [oc])
              |> result.map(fn(v) { Component(..c, od: Some(v)) })
            None, None -> Ok(c)
          }
        }
      }
  }
}

fn transform_matrix(
  c: Component,
  other: Component,
  side: Side,
  common: Int,
  cplength: Int,
  other_len: Int,
) -> Result(List(Component), OtError) {
  let common_operand = cplength == other_len
  case other {
    Component(subtype: Some(#(oname, oop)), ..) ->
      transform_other_subtype(c, oname, oop, side)
    Component(na: Some(_), ..) -> Ok([c])
    Component(li: Some(_), ld: Some(_), ..) ->
      Ok(list_replace_branch(c, other, side, common, common_operand))
    Component(li: Some(_), ..) ->
      Ok(other_li_branch(c, other, common, common_operand, side))
    Component(ld: Some(_), ..) ->
      Ok(other_ld_branch(c, other, common, common_operand, cplength, other_len))
    Component(lm: Some(_), ..) ->
      Ok(other_lm_branch(
        c,
        other,
        common,
        common_operand,
        cplength,
        other_len,
        side,
      ))
    Component(oi: Some(_), od: Some(_), ..) ->
      Ok(other_oreplace_branch(c, other, common, common_operand, side))
    Component(oi: Some(_), ..) -> Ok(other_oi_branch(c, other, common, side))
    Component(od: Some(_), ..) ->
      Ok(other_od_branch(c, other, common, common_operand))
    _ -> Ok([c])
  }
}

fn transform_other_subtype(
  c: Component,
  oname: String,
  oop: JsonValue,
  side: Side,
) -> Result(List(Component), OtError) {
  case is_known_subtype(oname) {
    False -> Ok([c])
    True ->
      case c.subtype {
        Some(#(cname, cop)) if cname == oname -> {
          use res <- result.try(subtype_transform(oname, cop, oop, side))
          case is_empty_subtype_op(res) {
            True -> Ok([])
            False -> Ok([Component(..c, subtype: Some(#(oname, res)))])
          }
        }
        _ -> Ok([c])
      }
  }
}

fn list_replace_branch(
  c: Component,
  other: Component,
  side: Side,
  common: Int,
  common_operand: Bool,
) -> List(Component) {
  case pk_at(other.path, common) == pk_at(c.path, common) {
    False -> [c]
    True ->
      case common_operand {
        False -> []
        True ->
          case c.ld {
            None -> [c]
            Some(_) ->
              case c.li, side {
                Some(_), Lft -> [Component(..c, ld: other.li)]
                _, _ -> []
              }
          }
      }
  }
}

fn other_li_branch(
  c: Component,
  other: Component,
  common: Int,
  common_operand: Bool,
  side: Side,
) -> List(Component) {
  let o_idx = idx_at(other.path, common)
  let c_idx = idx_at(c.path, common)
  let same = pk_at(c.path, common) == pk_at(other.path, common)
  let c1 = case c.li, c.ld, common_operand, same {
    Some(_), None, True, True ->
      case side {
        Rgt -> Component(..c, path: bump_idx_at(c.path, common, 1))
        Lft -> c
      }
    _, _, _, _ ->
      case o_idx <= c_idx {
        True -> Component(..c, path: bump_idx_at(c.path, common, 1))
        False -> c
      }
  }
  let c2 = case c1.lm, common_operand {
    Some(lm), True ->
      case o_idx <= lm {
        True -> Component(..c1, lm: Some(lm + 1))
        False -> c1
      }
    _, _ -> c1
  }
  [c2]
}

fn other_ld_branch(
  c: Component,
  other: Component,
  common: Int,
  common_operand: Bool,
  cplength: Int,
  other_len: Int,
) -> List(Component) {
  let o_idx = idx_at(other.path, common)
  let c_idx = idx_at(c.path, common)
  let same = pk_at(c.path, common) == pk_at(other.path, common)
  let after_lm = case c.lm, common_operand {
    Some(lm), True ->
      case same {
        True -> Error(Nil)
        False -> {
          let dec = case o_idx < lm || { o_idx == lm && c_idx < lm } {
            True -> lm - 1
            False -> lm
          }
          Ok(Component(..c, lm: Some(dec)))
        }
      }
    _, _ -> Ok(c)
  }
  case after_lm {
    Error(_) -> []
    Ok(c) ->
      case o_idx < c_idx {
        True -> [Component(..c, path: bump_idx_at(c.path, common, -1))]
        False ->
          case same {
            False -> [c]
            True ->
              case other_len < cplength {
                True -> []
                False ->
                  case c.ld {
                    None -> [c]
                    Some(_) ->
                      case c.li {
                        Some(_) -> [Component(..c, ld: None)]
                        None -> []
                      }
                  }
              }
          }
      }
  }
}

fn other_oreplace_branch(
  c: Component,
  other: Component,
  common: Int,
  common_operand: Bool,
  side: Side,
) -> List(Component) {
  case pk_at(c.path, common) == pk_at(other.path, common) {
    False -> [c]
    True ->
      case c.oi, common_operand {
        Some(_), True ->
          case side {
            Rgt -> []
            Lft -> [Component(..c, od: other.oi)]
          }
        _, _ -> []
      }
  }
}

fn other_oi_branch(
  c: Component,
  other: Component,
  common: Int,
  side: Side,
) -> List(Component) {
  case c.oi, pk_at(c.path, common) == pk_at(other.path, common) {
    Some(_), True ->
      case side, other.oi {
        Lft, Some(oiv) -> [obj_delete(c.path, oiv), c]
        Rgt, _ -> []
        Lft, None -> [c]
      }
    _, _ -> [c]
  }
}

fn other_od_branch(
  c: Component,
  other: Component,
  common: Int,
  common_operand: Bool,
) -> List(Component) {
  case pk_at(c.path, common) == pk_at(other.path, common) {
    False -> [c]
    True ->
      case common_operand {
        False -> []
        True ->
          case c.oi {
            Some(_) -> [Component(..c, od: None)]
            None -> []
          }
      }
  }
}

fn other_lm_branch(
  c: Component,
  other: Component,
  common: Int,
  common_operand: Bool,
  cplength: Int,
  other_len: Int,
  side: Side,
) -> List(Component) {
  let other_from = idx_at(other.path, common)
  let other_to = case other.lm {
    Some(t) -> t
    None -> -999_999
  }
  case c.lm, cplength == other_len {
    Some(to), True -> {
      let from = idx_at(c.path, common)
      case other_from == other_to {
        True -> [c]
        False -> lm_vs_lm(c, common, from, to, other_from, other_to, side)
      }
    }
    _, _ ->
      case c.li, c.ld, common_operand {
        Some(_), None, True -> {
          let p = idx_at(c.path, common)
          let d1 = case p > other_from {
            True -> -1
            False -> 0
          }
          let d2 = case p > other_to {
            True -> 1
            False -> 0
          }
          [Component(..c, path: bump_idx_at(c.path, common, d1 + d2))]
        }
        _, _, _ -> {
          let p = idx_at(c.path, common)
          case p == other_from {
            True -> [Component(..c, path: set_idx_at(c.path, common, other_to))]
            False -> {
              let d1 = case p > other_from {
                True -> -1
                False -> 0
              }
              let d2 = case p > other_to {
                True -> 1
                False ->
                  case p == other_to && other_from > other_to {
                    True -> 1
                    False -> 0
                  }
              }
              [Component(..c, path: bump_idx_at(c.path, common, d1 + d2))]
            }
          }
        }
      }
  }
}

fn lm_vs_lm(
  c: Component,
  common: Int,
  from: Int,
  to: Int,
  other_from: Int,
  other_to: Int,
  side: Side,
) -> List(Component) {
  case from == other_from {
    True ->
      case side {
        Rgt -> []
        Lft -> {
          let c1 = Component(..c, path: set_idx_at(c.path, common, other_to))
          case from == to {
            True -> [Component(..c1, lm: Some(other_to))]
            False -> [c1]
          }
        }
      }
    False -> {
      // Step 1: adjust the source index (c.p[common]).
      let a = case from > other_from {
        True -> -1
        False -> 0
      }
      let #(b, lm_from_p) = case from > other_to {
        True -> #(1, 0)
        False ->
          case from == other_to && other_from > other_to {
            True ->
              case from == to {
                True -> #(1, 1)
                False -> #(1, 0)
              }
            False -> #(0, 0)
          }
      }
      let p_delta = a + b
      // Step 2: adjust the destination index (c.lm).
      let s1 = case to > other_from {
        True -> -1
        False ->
          case to == other_from && to > from {
            True -> -1
            False -> 0
          }
      }
      let s2 = case to > other_to {
        True -> 1
        False ->
          case to == other_to {
            True -> {
              let cond_a = other_to > other_from && to > from
              let cond_b = other_to < other_from && to < from
              case cond_a || cond_b {
                True ->
                  case side {
                    Rgt -> 1
                    Lft -> 0
                  }
                False ->
                  case to > from {
                    True -> 1
                    False ->
                      case to == other_from {
                        True -> -1
                        False -> 0
                      }
                  }
              }
            }
            False -> 0
          }
      }
      let lm_delta = lm_from_p + s1 + s2
      [
        Component(
          ..c,
          path: bump_idx_at(c.path, common, p_delta),
          lm: Some(to + lm_delta),
        ),
      ]
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// invert (json0 `invert`) — powers rollback
// ─────────────────────────────────────────────────────────────────────────────

/// Invert an op so `apply(apply(doc, op), invert(op)) == doc`. Deletes carry
/// their pre-image, so no external snapshot is needed.
pub fn invert(op: Op) -> Op {
  list.reverse(op) |> list.map(invert_component)
}

fn invert_component(c: Component) -> Component {
  let base =
    Component(
      ..empty(c.path),
      na: option.map(c.na, num_negate),
      oi: c.od,
      od: c.oi,
      li: c.ld,
      ld: c.li,
      subtype: option.map(c.subtype, fn(pair) {
        #(pair.0, invert_subtype(pair.0, pair.1))
      }),
    )
  case c.lm {
    None -> base
    Some(target) -> {
      let #(parent, last) = split_last(c.path)
      let last_idx = case last {
        Index(i) -> i
        Key(_) -> 0
      }
      Component(
        ..base,
        path: list.append(parent, [Index(target)]),
        lm: Some(last_idx),
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subtype registry (only `text0` ships; container stays name-generic)
// ─────────────────────────────────────────────────────────────────────────────

/// Apply a subtype op to a value. Filled in by rung 4 (`text0`); until then
/// unknown subtypes error rather than silently no-op.
pub fn apply_subtype(
  name: String,
  value: JsonValue,
  sub_op: JsonValue,
) -> Result(JsonValue, OtError) {
  case name {
    "text0" -> text0_apply(value, sub_op)
    _ -> Error(UnknownSubtype(name))
  }
}

fn is_known_subtype(name: String) -> Bool {
  name == "text0"
}

/// Transform subtype op `a` past `b`. Filled in by rung 4 (`text0`).
fn subtype_transform(
  name: String,
  a: JsonValue,
  b: JsonValue,
  side: Side,
) -> Result(JsonValue, OtError) {
  case name {
    "text0" -> text0_transform(a, b, side)
    _ -> Error(UnknownSubtype(name))
  }
}

/// A subtype op is empty (drop the component) when it is an empty op list.
fn is_empty_subtype_op(op: JsonValue) -> Bool {
  op == VArray([])
}

/// Invert a subtype op. Identity placeholder until rung 4 wires text0.
fn invert_subtype(name: String, op: JsonValue) -> JsonValue {
  case name {
    "text0" -> text0_invert(op)
    _ -> op
  }
}

fn text0_apply(
  _value: JsonValue,
  _sub_op: JsonValue,
) -> Result(JsonValue, OtError) {
  Error(UnknownSubtype("text0 (not yet implemented)"))
}

fn text0_transform(
  _a: JsonValue,
  _b: JsonValue,
  _side: Side,
) -> Result(JsonValue, OtError) {
  Error(UnknownSubtype("text0 (not yet implemented)"))
}

fn text0_invert(op: JsonValue) -> JsonValue {
  op
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON <-> value conversion (wire + tests)
// ─────────────────────────────────────────────────────────────────────────────

/// Encode a value to `gleam/json` for the wire.
pub fn to_json(value: JsonValue) -> Json {
  case value {
    VNull -> json.null()
    VBool(b) -> json.bool(b)
    VNumber(NInt(i)) -> json.int(i)
    VNumber(NFloat(f)) -> json.float(f)
    VString(s) -> json.string(s)
    VArray(items) -> json.array(items, to_json)
    VObject(members) ->
      json.object(list.map(members, fn(pair) { #(pair.0, to_json(pair.1)) }))
  }
}

/// A decoder for a `JsonValue` from parsed JSON.
pub fn decoder() -> Decoder(JsonValue) {
  let non_null =
    decode.one_of(decode.string |> decode.map(VString), or: [
      decode.bool |> decode.map(VBool),
      decode.int |> decode.map(fn(i) { VNumber(NInt(i)) }),
      decode.float |> decode.map(fn(f) { VNumber(NFloat(f)) }),
      decode.list(decode.recursive(decoder)) |> decode.map(VArray),
      decode.dict(decode.string, decode.recursive(decoder))
        |> decode.map(fn(d) { VObject(dict_to_sorted_list(d)) }),
    ])
  decode.optional(non_null)
  |> decode.map(fn(value) {
    case value {
      Some(inner) -> inner
      None -> VNull
    }
  })
}

fn dict_to_sorted_list(
  d: Dict(String, JsonValue),
) -> List(#(String, JsonValue)) {
  dict.to_list(d)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Parse a JSON string into a `JsonValue` (used by tests and summaries).
pub fn from_json_string(raw: String) -> Result(JsonValue, Nil) {
  case json.parse(raw, decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}

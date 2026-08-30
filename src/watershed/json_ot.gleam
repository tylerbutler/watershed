//// A pure port of `ottypes/json0` (`lib/json0.js`), the JSON operational
//// transform (OT) algebra. It contains an inspectable JSON value model with
//// `apply`, `transform` (TP1), `compose`, and `invert`. There is no process
//// and no state. The stateful client kernel that runs on the watershed
//// sequencer is in `json_ot_kernel`.
////
//// A note on the model: the reference type stores a component as a JavaScript
//// object with independent optional fields (`oi`, `od`, `li`, `ld`, `lm`,
//// `na`, and `t` with `o`). Its transform matrix branches on the fields that
//// are present: a replace is `oi` with `od`, and a list replace is `li` with
//// `ld`. This port uses a `Component` record with optional fields, and not a
//// sum type of one edit each, so that the port stays mechanical and correct
//// for TP1.
////
//// The members of an object stay sorted by key, so structural equality (`==`)
//// is a valid convergence oracle. This port does not model the old `si` and
//// `sd` string ops. Use the `text0` subtype (`t` with `o`) instead, the same
//// as current json0 usage.

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

/// An inspectable JSON value. The members of a `VObject` value always stay
/// sorted by key, so `==` is canonical equality, which does not depend on the
/// order.
pub type JsonValue {
  VNull
  VBool(Bool)
  VNumber(Num)
  VString(String)
  VArray(List(JsonValue))
  VObject(List(#(String, JsonValue)))
}

/// A JSON number keeps the difference between an integer and a float that the
/// wire codec makes.
pub type Num {
  NInt(Int)
  NFloat(Float)
}

/// One step of a JSON pointer: an object member or an array position.
pub type PathKey {
  Key(String)
  Index(Int)
}

/// One component of a json0 op: a path with the edit fields that are set. A
/// component sets one family of fields at most. There are two deliberate
/// exceptions: `oi` with `od` is an object replace, and `li` with `ld` is a
/// list replace.
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

/// Apply a full op to a document, one component at a time. This is the
/// `apply` function of json0.
pub fn apply(doc: JsonValue, op: Op) -> Result(JsonValue, OtError) {
  list.try_fold(op, doc, apply_component)
}

fn apply_component(
  doc: JsonValue,
  component: Component,
) -> Result(JsonValue, OtError) {
  case split_last(component.path) {
    // An empty path names the document itself.
    Error(Nil) -> edit_root(doc, component)
    Ok(#(parent_path, last)) ->
      update_at(doc, parent_path, fn(container) {
        edit_in_container(container, last, component)
      })
  }
}

/// Split the last key from a path. The result is `Error(Nil)` for an empty
/// path, because an empty path has no last key.
fn split_last(path: List(PathKey)) -> Result(#(List(PathKey), PathKey), Nil) {
  case list.reverse(path) {
    [] -> Error(Nil)
    [last, ..reversed_init] -> Ok(#(list.reverse(reversed_init), last))
  }
}

/// A functional update. Follow `path` into `doc`, and replace the sub-value at
/// the end of that path with `f(sub)`.
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
          case list.key_find(members, key) {
            Ok(child) ->
              update_at(child, rest, f)
              |> result.map(fn(updated) {
                VObject(obj_set(members, key, updated))
              })
            Error(Nil) -> Error(BadPath("object key not found: " <> key))
          }
        VNull | VBool(_) | VNumber(_) | VString(_) | VArray(_) ->
          Error(BadPath("expected object at path step " <> key))
      }
    [Index(index), ..rest] ->
      case doc {
        VArray(items) ->
          case element_at(items, index) {
            Ok(child) ->
              update_at(child, rest, f)
              |> result.map(fn(updated) {
                VArray(list_set(items, index, updated))
              })
            Error(_) ->
              Error(BadPath("list index out of range: " <> int.to_string(index)))
          }
        VNull | VBool(_) | VNumber(_) | VString(_) | VObject(_) ->
          Error(BadPath("expected array at path step " <> int.to_string(index)))
      }
  }
}

/// Apply an edit whose path is empty. Such an edit targets the root of the
/// document.
fn edit_root(doc: JsonValue, c: Component) -> Result(JsonValue, OtError) {
  case c {
    Component(oi: Some(value), ..) -> Ok(value)
    Component(na: Some(delta), ..) ->
      case doc {
        VNumber(n) -> Ok(VNumber(num_add(n, delta)))
        VNull | VBool(_) | VString(_) | VArray(_) | VObject(_) ->
          Error(BadValue("na target is not a number"))
      }
    Component(subtype: Some(#(name, sub_op)), ..) ->
      apply_subtype(name, doc, sub_op)
    Component(od: Some(_), ..) -> Ok(VNull)
    Component(oi: None, na: None, subtype: None, od: None, ..) ->
      Error(BadValue("invalid or missing instruction at root"))
  }
}

/// Apply an edit at `key` in `container`, which is the parent of the edit.
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
              VNull | VBool(_) | VString(_) | VArray(_) | VObject(_) ->
                Error(BadValue("na target is not a number"))
            }
          })
        Component(subtype: Some(#(name, sub_op)), ..) ->
          edit_member_value(members, key, fn(v) {
            apply_subtype(name, v, sub_op)
          })
        Component(oi: None, od: None, na: None, subtype: None, ..) ->
          Error(BadValue("invalid object edit at key " <> key))
      }
    VNull | VBool(_) | VNumber(_) | VString(_) | VArray(_) ->
      Error(BadPath("expected object for key " <> key))
  }
}

fn edit_member_value(
  members: List(#(String, JsonValue)),
  key: String,
  f: fn(JsonValue) -> Result(JsonValue, OtError),
) -> Result(JsonValue, OtError) {
  case list.key_find(members, key) {
    Ok(value) ->
      f(value)
      |> result.map(fn(updated) { VObject(obj_set(members, key, updated)) })
    Error(Nil) -> Error(BadPath("object key not found: " <> key))
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
          case element_at(items, index) {
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
              VNull | VBool(_) | VString(_) | VArray(_) | VObject(_) ->
                Error(BadValue("na target is not a number"))
            }
          })
        Component(subtype: Some(#(name, sub_op)), ..) ->
          edit_element_value(items, index, fn(v) {
            apply_subtype(name, v, sub_op)
          })
        Component(li: None, ld: None, lm: None, na: None, subtype: None, ..) ->
          Error(BadValue("invalid list edit"))
      }
    VNull | VBool(_) | VNumber(_) | VString(_) | VObject(_) ->
      Error(BadPath("expected array for index"))
  }
}

fn edit_element_value(
  items: List(JsonValue),
  index: Int,
  f: fn(JsonValue) -> Result(JsonValue, OtError),
) -> Result(JsonValue, OtError) {
  case element_at(items, index) {
    Ok(value) ->
      f(value)
      |> result.map(fn(updated) { VArray(list_set(items, index, updated)) })
    Error(_) -> Error(BadPath("list index out of range"))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List helpers
// ─────────────────────────────────────────────────────────────────────────────

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
  case element_at(items, index) {
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
      case element_at(items, from) {
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

/// The path length of a component, adjusted the same way as in json0. An `na`
/// op and a subtype op both reach one step deeper than their explicit path.
fn adjusted_length(c: Component) -> Int {
  let extra = case c.na, c.subtype {
    None, None -> 0
    _, _ -> 1
  }
  list.length(c.path) + extra
}

/// The `commonLengthForOps(a, b)` function of json0. The result is the length
/// of the shared operand prefix, or `Error(Nil)`, which is `null` in json0.
/// `Ok(-1)` is the case where `a` reaches the root.
fn common_length(a: Component, b: Component) -> Result(Int, Nil) {
  let a_length = adjusted_length(a)
  let b_length = adjusted_length(b)
  case a_length == 0 {
    True -> Ok(-1)
    False ->
      case b_length == 0 {
        True -> Error(Nil)
        False -> common_loop(a.path, b.path, 0, a_length - 1, b_length - 1)
      }
  }
}

fn common_loop(
  a_path: List(PathKey),
  b_path: List(PathKey),
  index: Int,
  a_length: Int,
  b_length: Int,
) -> Result(Int, Nil) {
  case index >= a_length {
    True -> Ok(a_length)
    False ->
      case index >= b_length {
        True -> Error(Nil)
        False ->
          case path_key_at(a_path, index) == path_key_at(b_path, index) {
            True -> common_loop(a_path, b_path, index + 1, a_length, b_length)
            False -> Error(Nil)
          }
      }
  }
}

/// The path key at `index`. The result is `Error(Nil)` for a negative index
/// and for an index past the end of the path.
fn path_key_at(path: List(PathKey), index: Int) -> Result(PathKey, Nil) {
  element_at(path, index)
}

/// The element at `index`. `gleam/list` has no indexed read, so this module
/// walks the list. The result is `Error(Nil)` for a negative index and for an
/// index past the end of the list.
fn element_at(items: List(a), index: Int) -> Result(a, Nil) {
  case items, index {
    _, _ if index < 0 -> Error(Nil)
    [], _ -> Error(Nil)
    [first, ..], 0 -> Ok(first)
    [_, ..rest], _ -> element_at(rest, index - 1)
  }
}

/// The numeric index value at position `i`. The list branches use this
/// function only. It returns a sentinel value for a position that is not an
/// index or is out of range. Those branches never read that sentinel.
fn idx_at(path: List(PathKey), i: Int) -> Int {
  case path_key_at(path, i) {
    Ok(Index(n)) -> n
    Ok(Key(_)) | Error(Nil) -> -999_999
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
    Error(Nil) -> [c]
    Ok(#(init, last)) ->
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
      case last_index_of(c.path) == Ok(target) {
        True -> KeepDest
        False -> NoMerge
      }
    _, _ -> NoMerge
  }
}

fn last_index_of(path: List(PathKey)) -> Result(Int, Nil) {
  case list.last(path) {
    Ok(Index(n)) -> Ok(n)
    Ok(Key(_)) | Error(Nil) -> Error(Nil)
  }
}

fn split_last_component(op: Op) -> Result(#(Op, Component), Nil) {
  case list.reverse(op) {
    [] -> Error(Nil)
    [last, ..reversed_init] -> Ok(#(list.reverse(reversed_init), last))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// transform (TP1) — json0 `transformComponent` + `bootstrapTransform`
// ─────────────────────────────────────────────────────────────────────────────

/// Transform `op` so that it applies after `other`. `side` breaks a tie, and
/// it is the `left` and `right` pair of json0. The TP1 property holds: for any
/// concurrent pair,
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

/// The `transformX` function of json0. It cross-transforms two ops in N²
/// steps, and it returns `#(leftOp', rightOp')`.
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

/// The `transformComponent` function of json0. It transforms one component `c`
/// past one `other` component, and it returns the 0, 1, or 2 components to
/// append to the result.
fn transform_component(
  c: Component,
  other: Component,
  side: Side,
) -> Result(List(Component), OtError) {
  let cplength = adjusted_length(c)
  let other_len = adjusted_length(other)
  let common = common_length(other, c)
  let common2 = common_length(c, other)
  use c <- result.try(apply_preimage(c, other, common2, cplength, other_len))
  case common {
    Error(Nil) -> Ok([c])
    Ok(common) -> transform_matrix(c, other, side, common, cplength, other_len)
  }
}

/// If `c` deletes a subtree that `other` edits, add the edit of `other` to the
/// stored pre-image. `invert` thus stays exact. This is the `common2` block of
/// json0.
fn apply_preimage(
  c: Component,
  other: Component,
  common2: Result(Int, Nil),
  cplength: Int,
  other_len: Int,
) -> Result(Component, OtError) {
  case common2 {
    Error(Nil) -> Ok(c)
    Ok(k) ->
      case
        other_len > cplength
        && path_key_at(c.path, k) == path_key_at(other.path, k)
      {
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
    Component(oi: Some(_), ..) ->
      Ok(other_oi_branch(c, other, common, common_operand, side))
    Component(od: Some(_), ..) ->
      Ok(other_od_branch(c, other, common, common_operand))
    Component(
      subtype: None,
      na: None,
      li: None,
      ld: None,
      lm: None,
      oi: None,
      od: None,
      ..,
    ) -> Ok([c])
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
  case path_key_at(other.path, common) == path_key_at(c.path, common) {
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
  let same = path_key_at(c.path, common) == path_key_at(other.path, common)
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
  let same = path_key_at(c.path, common) == path_key_at(other.path, common)
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
  case path_key_at(c.path, common) == path_key_at(other.path, common) {
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
  common_operand: Bool,
  side: Side,
) -> List(Component) {
  case path_key_at(c.path, common) == path_key_at(other.path, common) {
    False -> [c]
    True ->
      // `other` inserts a value at a strictly-shallower path than `c`: it just
      // (re)created an ancestor of `c`'s operand, so `c`'s deeper edit is stale
      // and must be dropped. This mirrors the `oi+od` (replace) and `od`
      // branches, which both drop `c` when `!common_operand`. Canonical json0
      // omits this guard because it never generates a deeper concurrent edit
      // from a shared base; watershed's optimistic clients can, so we converge
      // it here rather than emit an inapplicable op.
      case common_operand {
        False -> []
        True ->
          case c.oi, side, other.oi {
            Some(_), Lft, Some(oiv) -> [obj_delete(c.path, oiv), c]
            Some(_), Rgt, _ -> []
            _, _, _ -> [c]
          }
      }
  }
}

fn other_od_branch(
  c: Component,
  other: Component,
  common: Int,
  common_operand: Bool,
) -> List(Component) {
  case path_key_at(c.path, common) == path_key_at(other.path, common) {
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

/// Invert an op, so that `apply(apply(doc, op), invert(op)) == doc`. A delete
/// carries its pre-image, so the caller needs no external snapshot.
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
    Some(target) ->
      case split_last(c.path) {
        // A list move always names a position, so its path is never empty.
        // The arm keeps the base component, because a pure module must not
        // panic.
        Error(Nil) -> base
        Ok(#(parent, last)) -> {
          let last_index = case last {
            Index(index) -> index
            Key(_) -> 0
          }
          Component(
            ..base,
            path: list.append(parent, [Index(target)]),
            lm: Some(last_index),
          )
        }
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subtype registry (only `text0` ships; container stays name-generic)
// ─────────────────────────────────────────────────────────────────────────────

/// Apply a subtype op to a value. Rung 4 (`text0`) completes this function.
/// Before that, an unknown subtype gives an error. It does not do nothing.
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

/// Transform the subtype op `a` past `b`. Rung 4 (`text0`) completes this
/// function.
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

/// A subtype op is empty when its op list is empty. Drop the component in that
/// case.
fn is_empty_subtype_op(op: JsonValue) -> Bool {
  op == VArray([])
}

/// Invert a subtype op. This is an identity placeholder until rung 4 adds
/// text0.
fn invert_subtype(name: String, op: JsonValue) -> JsonValue {
  case name {
    "text0" -> text0_invert(op)
    _ -> op
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// text0 subtype — a full port of ottypes/json0's `lib/text0.js` (+ the
// `bootstrapTransform` N² driver). The document is a `VString`; a text0 op is a
// `VArray` of components, each a `VObject` carrying `p` (position) and exactly
// one of `i` (insert) / `d` (delete). Internally we parse to a typed `TextComp`
// list, run the algebra, and serialize back.
// ─────────────────────────────────────────────────────────────────────────────

type TextComp {
  TIns(p: Int, s: String)
  TDel(p: Int, s: String)
}

fn text0_parse_op(op: JsonValue) -> Result(List(TextComp), OtError) {
  case op {
    VArray(items) -> list.try_map(items, text0_parse_component)
    VNull | VBool(_) | VNumber(_) | VString(_) | VObject(_) ->
      Error(BadValue("text0 op must be an array"))
  }
}

fn text0_parse_component(component: JsonValue) -> Result(TextComp, OtError) {
  case component {
    VObject(members) -> {
      let pos = case list.key_find(members, "p") {
        Ok(VNumber(NInt(n))) -> Ok(n)
        Ok(_) -> Error(BadValue("text0 component missing integer position"))
        Error(Nil) ->
          Error(BadValue("text0 component missing integer position"))
      }
      use p <- result.try(pos)
      case p < 0 {
        True -> Error(BadValue("text0 position cannot be negative"))
        False ->
          case list.key_find(members, "i"), list.key_find(members, "d") {
            Ok(VString(s)), Error(_) -> Ok(TIns(p, s))
            Error(_), Ok(VString(s)) -> Ok(TDel(p, s))
            _, _ -> Error(BadValue("text0 component needs an i or d field"))
          }
      }
    }
    VNull | VBool(_) | VNumber(_) | VString(_) | VArray(_) ->
      Error(BadValue("text0 component must be an object"))
  }
}

fn text0_serialize_op(op: List(TextComp)) -> JsonValue {
  VArray(list.map(op, text0_serialize_component))
}

fn text0_serialize_component(component: TextComp) -> JsonValue {
  // Object members are kept key-sorted for canonical equality; "d"/"i" both
  // sort before "p".
  case component {
    TIns(p, s) -> VObject([#("i", VString(s)), #("p", VNumber(NInt(p)))])
    TDel(p, s) -> VObject([#("d", VString(s)), #("p", VNumber(NInt(p)))])
  }
}

/// Insert `s2` into `s1` at `pos`.
fn str_inject(s1: String, pos: Int, s2: String) -> String {
  string.slice(s1, 0, pos) <> s2 <> string.drop_start(s1, pos)
}

fn text0_is_empty_component(component: TextComp) -> Bool {
  case component {
    TIns(_, "") | TDel(_, "") -> True
    TIns(_, _) | TDel(_, _) -> False
  }
}

/// Append `component` to `op`. The function drops a component that does
/// nothing, and it composes two adjacent inserts or two adjacent deletes, the
/// same as the `text._append` function of json0. `op` is in the normal order,
/// which is the execution order.
fn text0_append(op: List(TextComp), component: TextComp) -> List(TextComp) {
  case text0_is_empty_component(component) {
    True -> op
    False ->
      case text0_split_last(op) {
        Error(Nil) -> [component]
        Ok(#(leading, last)) ->
          case text0_merge(last, component) {
            Ok(merged) -> list.append(leading, [merged])
            Error(Nil) -> list.append(op, [component])
          }
      }
  }
}

fn text0_split_last(
  op: List(TextComp),
) -> Result(#(List(TextComp), TextComp), Nil) {
  case list.reverse(op) {
    [] -> Error(Nil)
    [last, ..rest] -> Ok(#(list.reverse(rest), last))
  }
}

/// Compose `component` onto the last component `last`, when the two are
/// adjacent edits of the same kind. That is two overlapping inserts, or two
/// overlapping deletes.
fn text0_merge(last: TextComp, component: TextComp) -> Result(TextComp, Nil) {
  case last, component {
    TIns(lp, li), TIns(cp, ci) ->
      case lp <= cp && cp <= lp + string.length(li) {
        True -> Ok(TIns(lp, str_inject(li, cp - lp, ci)))
        False -> Error(Nil)
      }
    TDel(lp, ld), TDel(cp, cd) ->
      case cp <= lp && lp <= cp + string.length(cd) {
        True -> Ok(TDel(cp, str_inject(cd, lp - cp, ld)))
        False -> Error(Nil)
      }
    TIns(_, _), TDel(_, _) -> Error(Nil)
    TDel(_, _), TIns(_, _) -> Error(Nil)
  }
}

/// Move `pos` for a concurrent `component`. For an insert, `insert_after`
/// decides whether a position exactly at the insert moves past it.
fn text0_transform_position(
  pos: Int,
  component: TextComp,
  insert_after: Bool,
) -> Int {
  case component {
    TIns(cp, cs) ->
      case cp < pos || { cp == pos && insert_after } {
        True -> pos + string.length(cs)
        False -> pos
      }
    TDel(cp, cs) -> {
      let clen = string.length(cs)
      case pos <= cp {
        True -> pos
        False ->
          case pos <= cp + clen {
            True -> cp
            False -> pos - clen
          }
      }
    }
  }
}

/// Transform `component` by `other`, and append each result to `destination`
/// in the normal order. The function is asymmetric. `side` breaks a tie between
/// two inserts.
fn text0_transform_component(
  destination: List(TextComp),
  component: TextComp,
  other: TextComp,
  side: Side,
) -> Result(List(TextComp), OtError) {
  case component {
    TIns(cp, cs) ->
      Ok(text0_append(
        destination,
        TIns(text0_transform_position(cp, other, side == Rgt), cs),
      ))
    TDel(cp, cs) ->
      case other {
        TIns(op, os) -> {
          // Delete vs insert: split the delete around the inserted text.
          let #(destination, remaining) = case cp < op {
            True -> #(
              text0_append(destination, TDel(cp, string.slice(cs, 0, op - cp))),
              string.drop_start(cs, op - cp),
            )
            False -> #(destination, cs)
          }
          case remaining == "" {
            True -> Ok(destination)
            False ->
              Ok(text0_append(
                destination,
                TDel(cp + string.length(os), remaining),
              ))
          }
        }
        TDel(op, os) -> {
          let clen = string.length(cs)
          let olen = string.length(os)
          case cp >= op + olen {
            True -> Ok(text0_append(destination, TDel(cp - olen, cs)))
            False ->
              case cp + clen <= op {
                True -> Ok(text0_append(destination, component))
                False -> {
                  // The deletes overlap: keep only the portions `other` did not
                  // already remove.
                  let part1 = case cp < op {
                    True -> string.slice(cs, 0, op - cp)
                    False -> ""
                  }
                  let part2 = case cp + clen > op + olen {
                    True -> string.drop_start(cs, op + olen - cp)
                    False -> ""
                  }
                  let new_d = part1 <> part2
                  let intersect_start = int.max(cp, op)
                  let intersect_end = int.min(cp + clen, op + olen)
                  let intersect_len = intersect_end - intersect_start
                  let c_intersect =
                    string.slice(cs, intersect_start - cp, intersect_len)
                  let o_intersect =
                    string.slice(os, intersect_start - op, intersect_len)
                  use _ <- result.try(case c_intersect == o_intersect {
                    True -> Ok(Nil)
                    False ->
                      Error(BadValue(
                        "text0 deletes disagree in the overlapping region",
                      ))
                  })
                  case new_d == "" {
                    True -> Ok(destination)
                    False ->
                      Ok(text0_append(
                        destination,
                        TDel(text0_transform_position(cp, other, False), new_d),
                      ))
                  }
                }
              }
          }
        }
      }
  }
}

/// The recursive N² transform driver, which is `bootstrapTransform.transformX`
/// in json0. It returns `#(left', right')`, where each op is transformed past
/// the other.
fn text0_transform_x(
  left_op: List(TextComp),
  right_op: List(TextComp),
) -> Result(#(List(TextComp), List(TextComp)), OtError) {
  text0_tx_outer(left_op, right_op, [])
}

fn text0_tx_outer(
  left_op: List(TextComp),
  right_op: List(TextComp),
  new_right_op: List(TextComp),
) -> Result(#(List(TextComp), List(TextComp)), OtError) {
  case right_op {
    [] -> Ok(#(left_op, new_right_op))
    [right_component, ..right_rest] -> {
      use #(new_left_op, new_right_op) <- result.try(text0_tx_inner(
        left_op,
        right_component,
        [],
        new_right_op,
      ))
      text0_tx_outer(new_left_op, right_rest, new_right_op)
    }
  }
}

/// Compose one `right_component` against the whole remaining left op. This is
/// the inner `while` loop of `transformX`, with its split-and-recurse
/// branch.
fn text0_tx_inner(
  left: List(TextComp),
  right_component: TextComp,
  new_left_op: List(TextComp),
  new_right_op: List(TextComp),
) -> Result(#(List(TextComp), List(TextComp)), OtError) {
  case left {
    [] -> Ok(#(new_left_op, text0_append(new_right_op, right_component)))
    [lc, ..lrest] -> {
      use new_left_op <- result.try(text0_transform_component(
        new_left_op,
        lc,
        right_component,
        Lft,
      ))
      use next_c <- result.try(text0_transform_component(
        [],
        right_component,
        lc,
        Rgt,
      ))
      case next_c {
        [only] -> text0_tx_inner(lrest, only, new_left_op, new_right_op)
        [] -> Ok(#(list.fold(lrest, new_left_op, text0_append), new_right_op))
        _ -> {
          use #(pair_left, pair_right) <- result.try(text0_transform_x(
            lrest,
            next_c,
          ))
          Ok(#(
            list.fold(pair_left, new_left_op, text0_append),
            list.fold(pair_right, new_right_op, text0_append),
          ))
        }
      }
    }
  }
}

fn text0_transform_ops(
  op: List(TextComp),
  other: List(TextComp),
  side: Side,
) -> Result(List(TextComp), OtError) {
  case other, op {
    [], _ -> Ok(op)
    [single_other], [single] ->
      text0_transform_component([], single, single_other, side)
    _, _ ->
      case side {
        Lft -> {
          use #(left, _right) <- result.try(text0_transform_x(op, other))
          Ok(left)
        }
        Rgt -> {
          use #(_left, right) <- result.try(text0_transform_x(other, op))
          Ok(right)
        }
      }
  }
}

fn text0_apply(
  value: JsonValue,
  sub_op: JsonValue,
) -> Result(JsonValue, OtError) {
  case value {
    VString(s) -> {
      use op <- result.try(text0_parse_op(sub_op))
      use result <- result.try(
        list.try_fold(op, s, fn(snapshot, component) {
          case component {
            TIns(p, i) -> Ok(str_inject(snapshot, p, i))
            TDel(p, d) -> {
              let deleted = string.slice(snapshot, p, string.length(d))
              case deleted == d {
                True ->
                  Ok(
                    string.slice(snapshot, 0, p)
                    <> string.drop_start(snapshot, p + string.length(d)),
                  )
                False ->
                  Error(BadValue(
                    "text0 delete does not match the document text",
                  ))
              }
            }
          }
        }),
      )
      Ok(VString(result))
    }
    VNull | VBool(_) | VNumber(_) | VArray(_) | VObject(_) ->
      Error(BadValue("text0 op can only apply to a string"))
  }
}

fn text0_transform(
  a: JsonValue,
  b: JsonValue,
  side: Side,
) -> Result(JsonValue, OtError) {
  use aop <- result.try(text0_parse_op(a))
  use bop <- result.try(text0_parse_op(b))
  use result <- result.try(text0_transform_ops(aop, bop, side))
  Ok(text0_serialize_op(result))
}

fn text0_invert(op: JsonValue) -> JsonValue {
  case text0_parse_op(op) {
    Error(_) -> op
    Ok(components) ->
      components
      |> list.reverse
      |> list.map(fn(c) {
        case c {
          TIns(p, s) -> TDel(p, s)
          TDel(p, s) -> TIns(p, s)
        }
      })
      |> text0_serialize_op
  }
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

/// Parse a JSON string into a `JsonValue`. The tests and the summaries use
/// this function.
pub fn from_json_string(raw: String) -> Result(JsonValue, Nil) {
  case json.parse(raw, decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Op wire codec (json0's on-the-wire component array)
// ─────────────────────────────────────────────────────────────────────────────

/// Encode an op as a json0 component array:
/// `[{p, oi?, od?, li?, ld?, lm?, na?, t?/o?}, …]`. A path is an array of
/// strings, which are object keys, or of integers, which are indices. Each
/// value goes through `to_json` and back. The `#(name, op)` pair of a subtype
/// becomes the `t` and `o` fields.
pub fn op_to_json(op: Op) -> Json {
  json.array(op, component_to_json)
}

fn component_to_json(c: Component) -> Json {
  let fields = [#("p", json.array(c.path, path_key_to_json))]
  let fields = append_field(fields, "oi", c.oi, to_json)
  let fields = append_field(fields, "od", c.od, to_json)
  let fields = append_field(fields, "li", c.li, to_json)
  let fields = append_field(fields, "ld", c.ld, to_json)
  let fields = append_field(fields, "lm", c.lm, json.int)
  let fields = append_field(fields, "na", c.na, num_to_json)
  let fields = case c.subtype {
    None -> fields
    Some(#(name, sub_op)) ->
      list.append(fields, [
        #("t", json.string(name)),
        #("o", to_json(sub_op)),
      ])
  }
  json.object(fields)
}

fn append_field(
  fields: List(#(String, Json)),
  key: String,
  value: Option(a),
  encode: fn(a) -> Json,
) -> List(#(String, Json)) {
  case value {
    None -> fields
    Some(v) -> list.append(fields, [#(key, encode(v))])
  }
}

fn path_key_to_json(key: PathKey) -> Json {
  case key {
    Key(s) -> json.string(s)
    Index(i) -> json.int(i)
  }
}

fn num_to_json(n: Num) -> Json {
  case n {
    NInt(i) -> json.int(i)
    NFloat(f) -> json.float(f)
  }
}

/// The decoder for a json0 op from parsed JSON. It is the inverse of
/// `op_to_json`.
pub fn op_decoder() -> Decoder(Op) {
  decode.list(component_decoder())
}

fn component_decoder() -> Decoder(Component) {
  use path <- decode.field("p", decode.list(path_key_decoder()))
  use oi <- decode.optional_field("oi", None, value_opt_decoder())
  use od <- decode.optional_field("od", None, value_opt_decoder())
  use li <- decode.optional_field("li", None, value_opt_decoder())
  use ld <- decode.optional_field("ld", None, value_opt_decoder())
  use lm <- decode.optional_field("lm", None, decode.map(decode.int, Some))
  use na <- decode.optional_field("na", None, num_opt_decoder())
  use subtype <- decode.optional_field("t", None, subtype_name_opt_decoder())
  use sub_op <- decode.optional_field("o", VNull, decoder())
  let subtype = case subtype {
    Some(name) -> Some(#(name, sub_op))
    None -> None
  }
  decode.success(Component(
    path: path,
    oi: oi,
    od: od,
    li: li,
    ld: ld,
    lm: lm,
    na: na,
    subtype: subtype,
  ))
}

fn value_opt_decoder() -> Decoder(Option(JsonValue)) {
  decode.map(decoder(), Some)
}

fn num_opt_decoder() -> Decoder(Option(Num)) {
  decode.one_of(decode.map(decode.int, fn(i) { Some(NInt(i)) }), or: [
    decode.map(decode.float, fn(f) { Some(NFloat(f)) }),
  ])
}

fn subtype_name_opt_decoder() -> Decoder(Option(String)) {
  decode.map(decode.string, Some)
}

fn path_key_decoder() -> Decoder(PathKey) {
  decode.one_of(decode.map(decode.int, Index), or: [
    decode.map(decode.string, Key),
  ])
}

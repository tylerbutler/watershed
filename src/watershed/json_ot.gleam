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

fn obj_get(members: List(#(String, JsonValue)), key: String) -> Option(JsonValue) {
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
          Error(BadPath(
            "expected array at path step " <> int.to_string(index),
          ))
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
        Component(oi: Some(value), ..) -> Ok(VObject(obj_set(members, key, value)))
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
      f(value) |> result.map(fn(updated) { VObject(obj_set(members, key, updated)) })
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
      f(value) |> result.map(fn(updated) { VArray(list_set(items, index, updated)) })
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

fn text0_apply(
  _value: JsonValue,
  _sub_op: JsonValue,
) -> Result(JsonValue, OtError) {
  Error(UnknownSubtype("text0 (not yet implemented)"))
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

fn dict_to_sorted_list(d: Dict(String, JsonValue)) -> List(#(String, JsonValue)) {
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

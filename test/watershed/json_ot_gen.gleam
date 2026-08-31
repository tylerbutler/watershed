//// Deterministic random JSON document and json0 operation generation, shared
//// by the TP1 property test and the multi-client convergence test. A faithful
//// port of ottypes/json0's `test/json0-generator.coffee`: `generate_operation`
//// emits *valid* random operations for a snapshot (skipping legacy `si`/`sd`
//// string operations, which the text0 subtype covers instead), threading the
//// working document through `json_ot.apply` so later components see earlier
//// mutations.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import watershed/json_ot.{
  type Component, type JsonValue, type PathKey, Index, Key, NInt, VArray, VBool,
  VNull, VNumber, VObject, VString,
}

const random_modulus = 2_147_483_647

pub type Random {
  Random(Int)
}

pub fn new_random(seed: Int) -> Random {
  // Fold the (possibly negative) qcheck seed into 1..modulus-1.
  let s = seed % { random_modulus - 1 }
  let s = case s < 0 {
    True -> s + { random_modulus - 1 }
    False -> s
  }
  Random(s + 1)
}

fn step(random: Random) -> #(Int, Random) {
  let Random(s) = random
  let s2 = { s * 48_271 } % random_modulus
  #(s2, Random(s2))
}

/// Uniform int in `[0, n)`. Returns 0 for non-positive `n`.
pub fn random_int(random: Random, n: Int) -> #(Int, Random) {
  case n <= 0 {
    True -> #(0, random)
    False -> {
      let #(v, random) = step(random)
      #(v % n, random)
    }
  }
}

/// Uniform real in `[0.0, 1.0)`.
pub fn random_real(random: Random) -> #(Float, Random) {
  let #(v, random) = step(random)
  #(int.to_float(v) /. int.to_float(random_modulus), random)
}

fn fold_times(n: Int, init: acc, f: fn(acc) -> acc) -> acc {
  case n <= 0 {
    True -> init
    False -> fold_times(n - 1, f(init), f)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Random value generation
// ─────────────────────────────────────────────────────────────────────────────

const words = ["a", "b", "c", "d", "e", "f", "g", "h"]

fn random_word(random: Random) -> #(String, Random) {
  let #(i, random) = random_int(random, list.length(words))
  let word = case list.drop(words, i) {
    [w, ..] -> w
    [] -> "a"
  }
  #(word, random)
}

/// Build a canonical (key-sorted, de-duplicated) object value.
fn make_object(pairs: List(#(String, JsonValue))) -> JsonValue {
  let sorted =
    pairs
    |> list.fold([], fn(acc, kv) {
      let #(key, v) = kv
      // last write wins on duplicate keys
      let without = list.filter(acc, fn(e: #(String, JsonValue)) { e.0 != key })
      [#(key, v), ..without]
    })
    |> list.sort(fn(x, y) { string.compare(x.0, y.0) })
  VObject(sorted)
}

fn random_thing(random: Random, depth: Int) -> #(JsonValue, Random) {
  let bound = case depth <= 0 {
    True -> 4
    False -> 6
  }
  let #(choice, random) = random_int(random, bound)
  case choice {
    0 -> #(VNull, random)
    1 -> #(VString(""), random)
    2 -> {
      let #(w, random) = random_word(random)
      #(VString(w), random)
    }
    3 -> {
      let #(n, random) = random_int(random, 50)
      #(VNumber(NInt(n)), random)
    }
    4 -> {
      let #(count, random) = random_int(random, 4)
      let #(pairs, random) =
        fold_times(count + 1, #([], random), fn(acc) {
          let #(ps, random) = acc
          let #(key, random) = random_word(random)
          let #(v, random) = random_thing(random, depth - 1)
          #([#(key, v), ..ps], random)
        })
      #(make_object(pairs), random)
    }
    _ -> {
      let #(count, random) = random_int(random, 4)
      let #(items, random) =
        fold_times(count + 1, #([], random), fn(acc) {
          let #(xs, random) = acc
          let #(v, random) = random_thing(random, depth - 1)
          #([v, ..xs], random)
        })
      #(VArray(list.reverse(items)), random)
    }
  }
}

/// A random top-level document. Always a container so operations have somewhere
/// to go.
pub fn random_document(random: Random) -> #(JsonValue, Random) {
  let #(coin, random) = random_real(random)
  case coin <. 0.5 {
    True -> {
      let #(count, random) = random_int(random, 4)
      let #(pairs, random) =
        fold_times(count + 2, #([], random), fn(acc) {
          let #(ps, random) = acc
          let #(key, random) = random_word(random)
          let #(v, random) = random_thing(random, 2)
          #([#(key, v), ..ps], random)
        })
      #(make_object(pairs), random)
    }
    False -> {
      let #(count, random) = random_int(random, 4)
      let #(items, random) =
        fold_times(count + 2, #([], random), fn(acc) {
          let #(xs, random) = acc
          let #(v, random) = random_thing(random, 2)
          #([v, ..xs], random)
        })
      #(VArray(list.reverse(items)), random)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Random operation generation (port of json0-generator.coffee)
// ─────────────────────────────────────────────────────────────────────────────

fn value_at(
  document: JsonValue,
  path: List(PathKey),
) -> Result(JsonValue, Nil) {
  case path {
    [] -> Ok(document)
    [step, ..rest] ->
      case document, step {
        VObject(members), Key(key) ->
          case list.key_find(members, key) {
            Ok(v) -> value_at(v, rest)
            Error(_) -> Error(Nil)
          }
        VArray(items), Index(i) ->
          case list.drop(items, i) {
            [v, ..] if i >= 0 -> value_at(v, rest)
            _ -> Error(Nil)
          }
        VNull, _
        | VBool(_), _
        | VNumber(_), _
        | VString(_), _
        | VArray(_), Key(_)
        | VObject(_), Index(_)
        -> Error(Nil)
      }
  }
}

/// Descend a random path into `document`, mirroring json0's `randomPath`.
fn random_path(
  document: JsonValue,
  random: Random,
) -> #(List(PathKey), Random) {
  random_path_loop(document, random, [])
}

fn random_path_loop(
  data: JsonValue,
  random: Random,
  acc: List(PathKey),
) -> #(List(PathKey), Random) {
  let #(coin, random) = random_real(random)
  case coin >. 0.85 {
    False -> #(list.reverse(acc), random)
    True ->
      case data {
        VObject([]) -> #(list.reverse(acc), random)
        VObject(members) -> {
          let #(index, random) = random_int(random, list.length(members))
          case list.drop(members, index) {
            [#(key, v), ..] -> random_path_loop(v, random, [Key(key), ..acc])
            [] -> #(list.reverse(acc), random)
          }
        }
        VArray([]) -> #(list.reverse(acc), random)
        VArray(items) -> {
          let #(index, random) = random_int(random, list.length(items))
          case list.drop(items, index) {
            [v, ..] -> random_path_loop(v, random, [Index(index), ..acc])
            [] -> #(list.reverse(acc), random)
          }
        }
        VNull | VBool(_) | VNumber(_) | VString(_) -> #(
          list.reverse(acc),
          random,
        )
      }
  }
}

/// Whether the parent container at `path` (given `document`) is a list. `None`
/// means the path is the root (no parent).
fn parent_is_list(path: List(PathKey)) -> Option(Bool) {
  case list.last(path) {
    Ok(Index(_)) -> Some(True)
    Ok(Key(_)) -> Some(False)
    Error(_) -> None
  }
}

fn existing_keys(v: JsonValue) -> List(String) {
  case v {
    VObject(members) -> list.map(members, fn(m) { m.0 })
    VNull | VBool(_) | VNumber(_) | VString(_) | VArray(_) -> []
  }
}

fn random_new_key(v: JsonValue, random: Random) -> #(String, Random) {
  let taken = existing_keys(v)
  random_new_key_loop(taken, random, 0)
}

fn random_new_key_loop(
  taken: List(String),
  random: Random,
  tries: Int,
) -> #(String, Random) {
  let #(w, random) = random_word(random)
  case list.contains(taken, w), tries < 8 {
    True, True -> random_new_key_loop(taken, random, tries + 1)
    True, False -> #(w <> int.to_string(tries), random)
    False, _ -> #(w, random)
  }
}

/// Generate a single valid component for `document`, or `None` if the chosen
/// spot affords no operation we model. String/bool/null leaves are handled via
/// replace.
fn generate_component(
  document: JsonValue,
  random: Random,
) -> #(Option(Component), Random) {
  let #(path, random) = random_path(document, random)
  case value_at(document, path) {
    Error(Nil) -> #(None, random)
    Ok(operand) -> {
      let is_list = parent_is_list(path)
      generate_component_for(document, path, operand, is_list, random)
    }
  }
}

fn generate_component_for(
  document: JsonValue,
  path: List(PathKey),
  operand: JsonValue,
  parent: Option(Bool),
  random: Random,
) -> #(Option(Component), Random) {
  let is_root = parent == None
  let #(r1, random) = random_real(random)
  // List move: only when parent is a list.
  case parent == Some(True) && r1 <. 0.4 {
    True -> {
      // newIndex ranges over the parent list's length.
      let parent_length = case value_at(document, drop_last(path)) {
        Ok(VArray(items)) -> list.length(items)
        Ok(VNull)
        | Ok(VBool(_))
        | Ok(VNumber(_))
        | Ok(VString(_))
        | Ok(VObject(_))
        | Error(Nil) -> 1
      }
      let #(new_index, random) = random_int(random, int_max(1, parent_length))
      #(Some(json_ot.list_move(path, new_index)), random)
    }
    False -> {
      let #(r2, random) = random_real(random)
      let want_replace = { r2 <. 0.3 || operand == VNull } && !is_root
      case want_replace {
        True -> {
          let #(new_value, random) = random_thing(random, 1)
          case parent {
            Some(True) -> #(
              Some(json_ot.list_replace(path, operand, new_value)),
              random,
            )
            Some(False) | None -> #(
              Some(json_ot.object_replace(path, operand, new_value)),
              random,
            )
          }
        }
        False -> generate_structural(path, operand, is_root, parent, random)
      }
    }
  }
}

fn generate_structural(
  path: List(PathKey),
  operand: JsonValue,
  is_root: Bool,
  parent: Option(Bool),
  random: Random,
) -> #(Option(Component), Random) {
  case operand {
    VNumber(_) -> {
      let #(increment, random) = random_int(random, 10)
      let delta = increment - 3
      case delta == 0 {
        True -> #(None, random)
        False -> #(Some(json_ot.number_add(path, NInt(delta))), random)
      }
    }
    VArray(items) -> {
      let length = list.length(items)
      let #(coin, random) = random_real(random)
      case coin >. 0.5 || length == 0 {
        True -> {
          let #(position, random) = random_int(random, length + 1)
          let #(new_value, random) = random_thing(random, 1)
          #(
            Some(json_ot.list_insert(
              list.append(path, [Index(position)]),
              new_value,
            )),
            random,
          )
        }
        False -> {
          let #(position, random) = random_int(random, length)
          case list.drop(items, position) {
            [v, ..] -> #(
              Some(json_ot.list_delete(list.append(path, [Index(position)]), v)),
              random,
            )
            [] -> #(None, random)
          }
        }
      }
    }
    VObject(members) -> {
      let #(coin, random) = random_real(random)
      case coin >. 0.5 || list.is_empty(members) {
        True -> {
          let #(key, random) = random_new_key(operand, random)
          let #(new_value, random) = random_thing(random, 1)
          #(
            Some(json_ot.object_insert(list.append(path, [Key(key)]), new_value)),
            random,
          )
        }
        False -> {
          let #(index, random) = random_int(random, list.length(members))
          case list.drop(members, index) {
            [#(key, v), ..] -> #(
              Some(json_ot.object_delete(list.append(path, [Key(key)]), v)),
              random,
            )
            [] -> #(None, random)
          }
        }
      }
    }
    // Strings: usually an in-place text0 subtype edit, sometimes a full
    // replace. Both need a parent to attach to.
    VString(s) ->
      case is_root {
        True -> #(None, random)
        False -> {
          let #(coin, random) = random_real(random)
          case coin <. 0.6 {
            True -> generate_text0_component(path, s, random)
            False -> generate_leaf_replace(path, operand, parent, random)
          }
        }
      }
    // Bool / Null leaves: replace at parent if we can, else skip.
    VNull | VBool(_) ->
      case is_root {
        True -> #(None, random)
        False -> generate_leaf_replace(path, operand, parent, random)
      }
  }
}

/// Replace a leaf value with a fresh random value, at either a list or object
/// slot depending on the parent.
fn generate_leaf_replace(
  path: List(PathKey),
  operand: JsonValue,
  parent: Option(Bool),
  random: Random,
) -> #(Option(Component), Random) {
  let #(new_value, random) = random_thing(random, 1)
  case parent {
    Some(True) -> #(
      Some(json_ot.list_replace(path, operand, new_value)),
      random,
    )
    Some(False) | None -> #(
      Some(json_ot.object_replace(path, operand, new_value)),
      random,
    )
  }
}

/// A random valid text0 subtype operation over the string `s`: an insert of a
/// word at a random position, or a delete of a real substring. Deletes
/// reference the actual text so they always apply.
fn generate_text0_component(
  path: List(PathKey),
  s: String,
  random: Random,
) -> #(Option(Component), Random) {
  let length = string.length(s)
  let #(coin, random) = random_real(random)
  case coin <. 0.5 || length == 0 {
    True -> {
      let #(position, random) = random_int(random, length + 1)
      let #(w, random) = random_word(random)
      #(
        Some(json_ot.subtype_component(path, "text0", text0_ins(position, w))),
        random,
      )
    }
    False -> {
      let #(position, random) = random_int(random, length)
      let #(count, random) = random_int(random, length - position)
      let delete_length = count + 1
      let removed = string.slice(s, position, delete_length)
      #(
        Some(json_ot.subtype_component(
          path,
          "text0",
          text0_del(position, removed),
        )),
        random,
      )
    }
  }
}

fn text0_ins(position: Int, s: String) -> JsonValue {
  VArray([VObject([#("i", VString(s)), #("p", VNumber(NInt(position)))])])
}

fn text0_del(position: Int, s: String) -> JsonValue {
  VArray([VObject([#("d", VString(s)), #("p", VNumber(NInt(position)))])])
}

fn drop_last(path: List(PathKey)) -> List(PathKey) {
  case list.reverse(path) {
    [_, ..rest] -> list.reverse(rest)
    [] -> []
  }
}

fn int_max(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}

/// Generate a compound operation valid for `document`, threading the working
/// document through `apply` so later components see earlier mutations.
pub fn generate_operation(
  document: JsonValue,
  random: Random,
) -> #(json_ot.Operation, Random) {
  generate_operation_loop(document, random, 0.95, [])
}

fn generate_operation_loop(
  work: JsonValue,
  random: Random,
  pct: Float,
  acc: List(Component),
) -> #(json_ot.Operation, Random) {
  let #(coin, random) = random_real(random)
  case coin <. pct {
    False -> #(list.reverse(acc), random)
    True -> {
      let #(maybe, random) = generate_component(work, random)
      case maybe {
        None -> #(list.reverse(acc), random)
        Some(c) ->
          case json_ot.apply(work, [c]) {
            Ok(work2) ->
              generate_operation_loop(work2, random, pct *. 0.6, [c, ..acc])
            Error(_) -> #(list.reverse(acc), random)
          }
      }
    }
  }
}

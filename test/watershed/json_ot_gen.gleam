//// Deterministic random JSON document and json0 op generation, shared by the
//// TP1 property test and the multi-client convergence test. A faithful port of
//// ottypes/json0's `test/json0-generator.coffee`: `gen_op` emits *valid*
//// random ops for a snapshot (skipping legacy `si`/`sd` string ops, which the
//// text0 subtype covers instead), threading the working document through
//// `json_ot.apply` so later components see earlier mutations.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import watershed/json_ot.{
  type Component, type JsonValue, type PathKey, Index, Key, NInt, VArray, VNull,
  VNumber, VObject, VString,
}

const rng_modulus = 2_147_483_647

pub type Rng {
  Rng(Int)
}

pub fn new_rng(seed: Int) -> Rng {
  // Fold the (possibly negative) qcheck seed into 1..modulus-1.
  let s = seed % { rng_modulus - 1 }
  let s = case s < 0 {
    True -> s + { rng_modulus - 1 }
    False -> s
  }
  Rng(s + 1)
}

fn step(rng: Rng) -> #(Int, Rng) {
  let Rng(s) = rng
  let s2 = { s * 48_271 } % rng_modulus
  #(s2, Rng(s2))
}

/// Uniform int in `[0, n)`. Returns 0 for non-positive `n`.
pub fn rand_int(rng: Rng, n: Int) -> #(Int, Rng) {
  case n <= 0 {
    True -> #(0, rng)
    False -> {
      let #(v, rng) = step(rng)
      #(v % n, rng)
    }
  }
}

/// Uniform real in `[0.0, 1.0)`.
pub fn rand_real(rng: Rng) -> #(Float, Rng) {
  let #(v, rng) = step(rng)
  #(int.to_float(v) /. int.to_float(rng_modulus), rng)
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

fn random_word(rng: Rng) -> #(String, Rng) {
  let #(i, rng) = rand_int(rng, list.length(words))
  let word = case list.drop(words, i) {
    [w, ..] -> w
    [] -> "a"
  }
  #(word, rng)
}

/// Build a canonical (key-sorted, de-duplicated) object value.
fn mk_obj(pairs: List(#(String, JsonValue))) -> JsonValue {
  let sorted =
    pairs
    |> list.fold([], fn(acc, kv) {
      let #(k, v) = kv
      // last write wins on duplicate keys
      let without = list.filter(acc, fn(e: #(String, JsonValue)) { e.0 != k })
      [#(k, v), ..without]
    })
    |> list.sort(fn(x, y) { string.compare(x.0, y.0) })
  VObject(sorted)
}

fn random_thing(rng: Rng, depth: Int) -> #(JsonValue, Rng) {
  let bound = case depth <= 0 {
    True -> 4
    False -> 6
  }
  let #(k, rng) = rand_int(rng, bound)
  case k {
    0 -> #(VNull, rng)
    1 -> #(VString(""), rng)
    2 -> {
      let #(w, rng) = random_word(rng)
      #(VString(w), rng)
    }
    3 -> {
      let #(n, rng) = rand_int(rng, 50)
      #(VNumber(NInt(n)), rng)
    }
    4 -> {
      let #(count, rng) = rand_int(rng, 4)
      let #(pairs, rng) =
        fold_times(count + 1, #([], rng), fn(acc) {
          let #(ps, rng) = acc
          let #(key, rng) = random_word(rng)
          let #(v, rng) = random_thing(rng, depth - 1)
          #([#(key, v), ..ps], rng)
        })
      #(mk_obj(pairs), rng)
    }
    _ -> {
      let #(count, rng) = rand_int(rng, 4)
      let #(items, rng) =
        fold_times(count + 1, #([], rng), fn(acc) {
          let #(xs, rng) = acc
          let #(v, rng) = random_thing(rng, depth - 1)
          #([v, ..xs], rng)
        })
      #(VArray(list.reverse(items)), rng)
    }
  }
}

/// A random top-level document. Always a container so ops have somewhere to go.
pub fn random_doc(rng: Rng) -> #(JsonValue, Rng) {
  let #(coin, rng) = rand_real(rng)
  case coin <. 0.5 {
    True -> {
      let #(count, rng) = rand_int(rng, 4)
      let #(pairs, rng) =
        fold_times(count + 2, #([], rng), fn(acc) {
          let #(ps, rng) = acc
          let #(key, rng) = random_word(rng)
          let #(v, rng) = random_thing(rng, 2)
          #([#(key, v), ..ps], rng)
        })
      #(mk_obj(pairs), rng)
    }
    False -> {
      let #(count, rng) = rand_int(rng, 4)
      let #(items, rng) =
        fold_times(count + 2, #([], rng), fn(acc) {
          let #(xs, rng) = acc
          let #(v, rng) = random_thing(rng, 2)
          #([v, ..xs], rng)
        })
      #(VArray(list.reverse(items)), rng)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Random op generation (port of json0-generator.coffee)
// ─────────────────────────────────────────────────────────────────────────────

fn value_at(doc: JsonValue, path: List(PathKey)) -> Option(JsonValue) {
  case path {
    [] -> Some(doc)
    [step, ..rest] ->
      case doc, step {
        VObject(members), Key(k) ->
          case list.key_find(members, k) {
            Ok(v) -> value_at(v, rest)
            Error(_) -> None
          }
        VArray(items), Index(i) ->
          case list.drop(items, i) {
            [v, ..] if i >= 0 -> value_at(v, rest)
            _ -> None
          }
        _, _ -> None
      }
  }
}

/// Descend a random path into `doc`, mirroring json0's `randomPath`.
fn random_path(doc: JsonValue, rng: Rng) -> #(List(PathKey), Rng) {
  random_path_loop(doc, rng, [])
}

fn random_path_loop(
  data: JsonValue,
  rng: Rng,
  acc: List(PathKey),
) -> #(List(PathKey), Rng) {
  let #(coin, rng) = rand_real(rng)
  case coin >. 0.85 {
    False -> #(list.reverse(acc), rng)
    True ->
      case data {
        VObject([]) -> #(list.reverse(acc), rng)
        VObject(members) -> {
          let #(idx, rng) = rand_int(rng, list.length(members))
          case list.drop(members, idx) {
            [#(k, v), ..] -> random_path_loop(v, rng, [Key(k), ..acc])
            [] -> #(list.reverse(acc), rng)
          }
        }
        VArray([]) -> #(list.reverse(acc), rng)
        VArray(items) -> {
          let #(idx, rng) = rand_int(rng, list.length(items))
          case list.drop(items, idx) {
            [v, ..] -> random_path_loop(v, rng, [Index(idx), ..acc])
            [] -> #(list.reverse(acc), rng)
          }
        }
        _ -> #(list.reverse(acc), rng)
      }
  }
}

/// Whether the parent container at `path` (given `doc`) is a list. `None`
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
    _ -> []
  }
}

fn random_new_key(v: JsonValue, rng: Rng) -> #(String, Rng) {
  let taken = existing_keys(v)
  random_new_key_loop(taken, rng, 0)
}

fn random_new_key_loop(
  taken: List(String),
  rng: Rng,
  tries: Int,
) -> #(String, Rng) {
  let #(w, rng) = random_word(rng)
  case list.contains(taken, w), tries < 8 {
    True, True -> random_new_key_loop(taken, rng, tries + 1)
    True, False -> #(w <> int.to_string(tries), rng)
    False, _ -> #(w, rng)
  }
}

/// Generate a single valid component for `doc`, or `None` if the chosen spot
/// affords no op we model. String/bool/null leaves are handled via replace.
fn gen_component(doc: JsonValue, rng: Rng) -> #(Option(Component), Rng) {
  let #(path, rng) = random_path(doc, rng)
  case value_at(doc, path) {
    None -> #(None, rng)
    Some(operand) -> {
      let is_list = parent_is_list(path)
      gen_component_for(doc, path, operand, is_list, rng)
    }
  }
}

fn gen_component_for(
  doc: JsonValue,
  path: List(PathKey),
  operand: JsonValue,
  parent: Option(Bool),
  rng: Rng,
) -> #(Option(Component), Rng) {
  let is_root = parent == None
  let #(r1, rng) = rand_real(rng)
  // List move: only when parent is a list.
  case parent == Some(True) && r1 <. 0.4 {
    True -> {
      // newIndex ranges over the parent list's length.
      let parent_len = case value_at(doc, drop_last(path)) {
        Some(VArray(items)) -> list.length(items)
        _ -> 1
      }
      let #(new_index, rng) = rand_int(rng, int_max(1, parent_len))
      #(Some(json_ot.list_move(path, new_index)), rng)
    }
    False -> {
      let #(r2, rng) = rand_real(rng)
      let want_replace = { r2 <. 0.3 || operand == VNull } && !is_root
      case want_replace {
        True -> {
          let #(newv, rng) = random_thing(rng, 1)
          case parent {
            Some(True) -> #(
              Some(json_ot.list_replace(path, operand, newv)),
              rng,
            )
            _ -> #(Some(json_ot.obj_replace(path, operand, newv)), rng)
          }
        }
        False -> gen_structural(path, operand, is_root, parent, rng)
      }
    }
  }
}

fn gen_structural(
  path: List(PathKey),
  operand: JsonValue,
  is_root: Bool,
  parent: Option(Bool),
  rng: Rng,
) -> #(Option(Component), Rng) {
  case operand {
    VNumber(_) -> {
      let #(inc, rng) = rand_int(rng, 10)
      let delta = inc - 3
      case delta == 0 {
        True -> #(None, rng)
        False -> #(Some(json_ot.number_add(path, NInt(delta))), rng)
      }
    }
    VArray(items) -> {
      let len = list.length(items)
      let #(coin, rng) = rand_real(rng)
      case coin >. 0.5 || len == 0 {
        True -> {
          let #(pos, rng) = rand_int(rng, len + 1)
          let #(newv, rng) = random_thing(rng, 1)
          #(
            Some(json_ot.list_insert(list.append(path, [Index(pos)]), newv)),
            rng,
          )
        }
        False -> {
          let #(pos, rng) = rand_int(rng, len)
          case list.drop(items, pos) {
            [v, ..] -> #(
              Some(json_ot.list_delete(list.append(path, [Index(pos)]), v)),
              rng,
            )
            [] -> #(None, rng)
          }
        }
      }
    }
    VObject(members) -> {
      let #(coin, rng) = rand_real(rng)
      case coin >. 0.5 || list.is_empty(members) {
        True -> {
          let #(k, rng) = random_new_key(operand, rng)
          let #(newv, rng) = random_thing(rng, 1)
          #(Some(json_ot.obj_insert(list.append(path, [Key(k)]), newv)), rng)
        }
        False -> {
          let #(idx, rng) = rand_int(rng, list.length(members))
          case list.drop(members, idx) {
            [#(k, v), ..] -> #(
              Some(json_ot.obj_delete(list.append(path, [Key(k)]), v)),
              rng,
            )
            [] -> #(None, rng)
          }
        }
      }
    }
    // Strings: usually an in-place text0 subtype edit, sometimes a full
    // replace. Both need a parent to attach to.
    VString(s) ->
      case is_root {
        True -> #(None, rng)
        False -> {
          let #(coin, rng) = rand_real(rng)
          case coin <. 0.6 {
            True -> gen_text0_component(path, s, rng)
            False -> gen_leaf_replace(path, operand, parent, rng)
          }
        }
      }
    // Bool / Null leaves: replace at parent if we can, else skip.
    _ ->
      case is_root {
        True -> #(None, rng)
        False -> gen_leaf_replace(path, operand, parent, rng)
      }
  }
}

/// Replace a leaf value with a fresh random value, at either a list or object
/// slot depending on the parent.
fn gen_leaf_replace(
  path: List(PathKey),
  operand: JsonValue,
  parent: Option(Bool),
  rng: Rng,
) -> #(Option(Component), Rng) {
  let #(newv, rng) = random_thing(rng, 1)
  case parent {
    Some(True) -> #(Some(json_ot.list_replace(path, operand, newv)), rng)
    _ -> #(Some(json_ot.obj_replace(path, operand, newv)), rng)
  }
}

/// A random valid text0 subtype op over the string `s`: an insert of a word at
/// a random position, or a delete of a real substring. Deletes reference the
/// actual text so they always apply.
fn gen_text0_component(
  path: List(PathKey),
  s: String,
  rng: Rng,
) -> #(Option(Component), Rng) {
  let len = string.length(s)
  let #(coin, rng) = rand_real(rng)
  case coin <. 0.5 || len == 0 {
    True -> {
      let #(pos, rng) = rand_int(rng, len + 1)
      let #(w, rng) = random_word(rng)
      #(Some(json_ot.subtype_component(path, "text0", text0_ins(pos, w))), rng)
    }
    False -> {
      let #(pos, rng) = rand_int(rng, len)
      let #(count, rng) = rand_int(rng, len - pos)
      let dlen = count + 1
      let removed = string.slice(s, pos, dlen)
      #(
        Some(json_ot.subtype_component(path, "text0", text0_del(pos, removed))),
        rng,
      )
    }
  }
}

fn text0_ins(pos: Int, s: String) -> JsonValue {
  VArray([VObject([#("i", VString(s)), #("p", VNumber(NInt(pos)))])])
}

fn text0_del(pos: Int, s: String) -> JsonValue {
  VArray([VObject([#("d", VString(s)), #("p", VNumber(NInt(pos)))])])
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

/// Generate a compound op valid for `doc`, threading the working document
/// through `apply` so later components see earlier mutations.
pub fn gen_op(doc: JsonValue, rng: Rng) -> #(json_ot.Op, Rng) {
  gen_op_loop(doc, rng, 0.95, [])
}

fn gen_op_loop(
  work: JsonValue,
  rng: Rng,
  pct: Float,
  acc: List(Component),
) -> #(json_ot.Op, Rng) {
  let #(coin, rng) = rand_real(rng)
  case coin <. pct {
    False -> #(list.reverse(acc), rng)
    True -> {
      let #(maybe, rng) = gen_component(work, rng)
      case maybe {
        None -> #(list.reverse(acc), rng)
        Some(c) ->
          case json_ot.apply(work, [c]) {
            Ok(work2) -> gen_op_loop(work2, rng, pct *. 0.6, [c, ..acc])
            Error(_) -> #(list.reverse(acc), rng)
          }
      }
    }
  }
}

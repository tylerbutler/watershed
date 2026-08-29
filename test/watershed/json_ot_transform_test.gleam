//// Port of the transform assertions in `ottypes/json0`'s `test/json0.coffee`.
//// Legacy `si`/`sd` string-op cases and `text0`/`mock` subtype cases are
//// deferred to the text0 rung; every structural (obj/list/number/move) case
//// is ported here as the TP1 acceptance oracle.

import gleam/list as _
import startest/expect
import watershed/json_ot.{
  type Component, type JsonValue, type Op, Index, Key, Lft, NInt, Rgt, VArray,
  VNull, VNumber, VObject, VString,
}

// ── tiny builders ────────────────────────────────────────────────────────────

fn string_value(value: String) -> JsonValue {
  VString(value)
}

fn number_value(value: Int) -> JsonValue {
  VNumber(NInt(value))
}

fn object(members: List(#(String, JsonValue))) -> JsonValue {
  VObject(members)
}

fn array(items: List(JsonValue)) -> JsonValue {
  VArray(items)
}

fn list_insert(path: List(json_ot.PathKey), value: JsonValue) -> Component {
  json_ot.list_insert(path, value)
}

fn list_delete(path: List(json_ot.PathKey), value: JsonValue) -> Component {
  json_ot.list_delete(path, value)
}

fn list_replace(
  path: List(json_ot.PathKey),
  old_value: JsonValue,
  new_value: JsonValue,
) -> Component {
  json_ot.list_replace(path, old_value, new_value)
}

fn list_move(path: List(json_ot.PathKey), to: Int) -> Component {
  json_ot.list_move(path, to)
}

fn object_insert(path: List(json_ot.PathKey), value: JsonValue) -> Component {
  json_ot.obj_insert(path, value)
}

fn object_delete(path: List(json_ot.PathKey), value: JsonValue) -> Component {
  json_ot.obj_delete(path, value)
}

fn object_replace(
  path: List(json_ot.PathKey),
  old_value: JsonValue,
  new_value: JsonValue,
) -> Component {
  json_ot.obj_replace(path, old_value, new_value)
}

fn number_add(path: List(json_ot.PathKey), delta: Int) -> Component {
  json_ot.number_add(path, NInt(delta))
}

fn transform(op: Op, other: Op, side: json_ot.Side) -> Op {
  let assert Ok(result) = json_ot.transform(op, other, side)
  result
}

// ── list: index bumps, noops, tiebreaks ──────────────────────────────────────

pub fn ld_bumps_past_li_test() -> Nil {
  transform(
    [list_delete([Index(0)], number_value(2))],
    [list_insert([Index(0)], number_value(1))],
    Lft,
  )
  |> expect.to_equal([list_delete([Index(1)], number_value(2))])
  transform(
    [list_delete([Index(0)], number_value(2))],
    [list_insert([Index(0)], number_value(1))],
    Rgt,
  )
  |> expect.to_equal([list_delete([Index(1)], number_value(2))])
}

pub fn ops_on_deleted_elements_become_noops_test() -> Nil {
  transform(
    [list_insert([Index(0)], string_value("x"))],
    [list_delete([Index(0)], string_value("y"))],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(0)], string_value("x"))])
  transform(
    [number_add([Index(0)], -3)],
    [list_delete([Index(0)], number_value(48))],
    Lft,
  )
  |> expect.to_equal([])
}

pub fn ops_on_replaced_elements_become_noops_test() -> Nil {
  transform(
    [list_insert([Index(0)], string_value("hi"))],
    [list_replace([Index(0)], string_value("x"), string_value("y"))],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(0)], string_value("hi"))])
}

pub fn simultaneous_list_inserts_left_first_test() -> Nil {
  transform(
    [list_insert([Index(1)], string_value("a"))],
    [list_insert([Index(1)], string_value("b"))],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(1)], string_value("a"))])
  transform(
    [list_insert([Index(1)], string_value("b"))],
    [list_insert([Index(1)], string_value("a"))],
    Rgt,
  )
  |> expect.to_equal([list_insert([Index(2)], string_value("b"))])
}

pub fn re_delete_list_element_noop_test() -> Nil {
  transform(
    [list_delete([Index(1)], string_value("x"))],
    [list_delete([Index(1)], string_value("x"))],
    Lft,
  )
  |> expect.to_equal([])
  transform(
    [list_delete([Index(1)], string_value("x"))],
    [list_delete([Index(1)], string_value("x"))],
    Rgt,
  )
  |> expect.to_equal([])
}

pub fn replace_null_vs_insert_test() -> Nil {
  transform(
    [list_replace([Index(0)], VNull, string_value("x"))],
    [list_insert([Index(0)], string_value("The"))],
    Rgt,
  )
  |> expect.to_equal([list_replace([Index(1)], VNull, string_value("x"))])
}

// ── list: moves carry ops with the element ────────────────────────────────────

pub fn moves_ops_with_element_test() -> Nil {
  transform(
    [list_delete([Index(4)], string_value("x"))],
    [list_move([Index(4)], 10)],
    Lft,
  )
  |> expect.to_equal([list_delete([Index(10)], string_value("x"))])
  transform(
    [list_insert([Index(4), Index(1)], string_value("a"))],
    [list_move([Index(4)], 10)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(10), Index(1)], string_value("a"))])
  transform(
    [list_replace([Index(4), Index(1)], string_value("b"), string_value("a"))],
    [list_move([Index(4)], 10)],
    Lft,
  )
  |> expect.to_equal([
    list_replace([Index(10), Index(1)], string_value("b"), string_value("a")),
  ])
  transform([list_insert([Index(0)], VNull)], [list_move([Index(0)], 1)], Lft)
  |> expect.to_equal([list_insert([Index(0)], VNull)])
  transform(
    [list_insert([Index(5)], string_value("x"))],
    [list_move([Index(5)], 1)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(6)], string_value("x"))])
  transform(
    [list_delete([Index(5)], number_value(6))],
    [list_move([Index(5)], 1)],
    Lft,
  )
  |> expect.to_equal([list_delete([Index(1)], number_value(6))])
  transform(
    [list_insert([Index(0)], array([]))],
    [list_move([Index(1)], 0)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(0)], array([]))])
  transform(
    [list_insert([Index(2)], string_value("x"))],
    [list_move([Index(0)], 1)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(2)], string_value("x"))])
}

pub fn moves_target_index_on_ld_li_test() -> Nil {
  transform(
    [list_move([Index(0)], 2)],
    [list_delete([Index(1)], string_value("x"))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(0)], 1)])
  transform(
    [list_move([Index(2)], 4)],
    [list_delete([Index(1)], string_value("x"))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(1)], 3)])
  transform(
    [list_move([Index(0)], 2)],
    [list_insert([Index(1)], string_value("x"))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(0)], 3)])
  transform(
    [list_move([Index(2)], 4)],
    [list_insert([Index(1)], string_value("x"))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(3)], 5)])
  transform(
    [list_move([Index(0)], 0)],
    [list_insert([Index(0)], number_value(28))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(1)], 1)])
}

pub fn tiebreaks_lm_vs_ld_li_test() -> Nil {
  transform(
    [list_move([Index(0)], 2)],
    [list_delete([Index(0)], string_value("x"))],
    Lft,
  )
  |> expect.to_equal([])
  transform(
    [list_move([Index(0)], 2)],
    [list_delete([Index(0)], string_value("x"))],
    Rgt,
  )
  |> expect.to_equal([])
  transform(
    [list_move([Index(0)], 2)],
    [list_insert([Index(0)], string_value("x"))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(1)], 3)])
  transform(
    [list_move([Index(0)], 2)],
    [list_insert([Index(0)], string_value("x"))],
    Rgt,
  )
  |> expect.to_equal([list_move([Index(1)], 3)])
}

pub fn list_replacement_vs_deletion_test() -> Nil {
  transform(
    [list_replace([Index(0)], string_value("x"), string_value("y"))],
    [list_delete([Index(0)], string_value("x"))],
    Rgt,
  )
  |> expect.to_equal([list_insert([Index(0)], string_value("y"))])
}

pub fn list_replacement_vs_insertion_test() -> Nil {
  transform(
    [list_replace([Index(0)], object([]), string_value("brillig"))],
    [list_insert([Index(0)], number_value(36))],
    Lft,
  )
  |> expect.to_equal([
    list_replace([Index(1)], object([]), string_value("brillig")),
  ])
}

pub fn list_replacement_vs_replacement_test() -> Nil {
  transform(
    [list_replace([Index(0)], VNull, array([]))],
    [list_replace([Index(0)], VNull, number_value(0))],
    Rgt,
  )
  |> expect.to_equal([])
  transform(
    [list_replace([Index(0)], VNull, number_value(0))],
    [list_replace([Index(0)], VNull, array([]))],
    Lft,
  )
  |> expect.to_equal([list_replace([Index(0)], array([]), number_value(0))])
}

// ── lm vs lm (the full spec table) ────────────────────────────────────────────

pub fn lm_vs_lm_table_test() -> Nil {
  transform([list_move([Index(0)], 2)], [list_move([Index(2)], 1)], Lft)
  |> expect.to_equal([list_move([Index(0)], 2)])
  transform([list_move([Index(3)], 3)], [list_move([Index(5)], 0)], Lft)
  |> expect.to_equal([list_move([Index(4)], 4)])
  transform([list_move([Index(2)], 0)], [list_move([Index(1)], 0)], Lft)
  |> expect.to_equal([list_move([Index(2)], 0)])
  transform([list_move([Index(2)], 0)], [list_move([Index(1)], 0)], Rgt)
  |> expect.to_equal([list_move([Index(2)], 1)])
  transform([list_move([Index(2)], 0)], [list_move([Index(5)], 0)], Rgt)
  |> expect.to_equal([list_move([Index(3)], 1)])
  transform([list_move([Index(2)], 0)], [list_move([Index(5)], 0)], Lft)
  |> expect.to_equal([list_move([Index(3)], 0)])
  transform([list_move([Index(2)], 5)], [list_move([Index(2)], 0)], Lft)
  |> expect.to_equal([list_move([Index(0)], 5)])
  transform([list_move([Index(1)], 0)], [list_move([Index(0)], 5)], Rgt)
  |> expect.to_equal([list_move([Index(0)], 0)])
  transform([list_move([Index(1)], 0)], [list_move([Index(0)], 1)], Rgt)
  |> expect.to_equal([list_move([Index(0)], 0)])
  transform([list_move([Index(0)], 1)], [list_move([Index(1)], 0)], Lft)
  |> expect.to_equal([list_move([Index(1)], 1)])
  transform([list_move([Index(0)], 1)], [list_move([Index(5)], 0)], Rgt)
  |> expect.to_equal([list_move([Index(1)], 2)])
  transform([list_move([Index(2)], 1)], [list_move([Index(5)], 0)], Rgt)
  |> expect.to_equal([list_move([Index(3)], 2)])
  transform([list_move([Index(3)], 1)], [list_move([Index(1)], 3)], Lft)
  |> expect.to_equal([list_move([Index(2)], 1)])
  transform([list_move([Index(1)], 3)], [list_move([Index(3)], 1)], Lft)
  |> expect.to_equal([list_move([Index(2)], 3)])
  transform([list_move([Index(2)], 6)], [list_move([Index(0)], 1)], Lft)
  |> expect.to_equal([list_move([Index(2)], 6)])
  transform([list_move([Index(2)], 6)], [list_move([Index(0)], 1)], Rgt)
  |> expect.to_equal([list_move([Index(2)], 6)])
  transform([list_move([Index(2)], 6)], [list_move([Index(1)], 0)], Lft)
  |> expect.to_equal([list_move([Index(2)], 6)])
  transform([list_move([Index(2)], 6)], [list_move([Index(1)], 0)], Rgt)
  |> expect.to_equal([list_move([Index(2)], 6)])
  transform([list_move([Index(0)], 1)], [list_move([Index(2)], 1)], Lft)
  |> expect.to_equal([list_move([Index(0)], 2)])
  transform([list_move([Index(2)], 1)], [list_move([Index(0)], 1)], Rgt)
  |> expect.to_equal([list_move([Index(2)], 0)])
  transform([list_move([Index(0)], 0)], [list_move([Index(1)], 0)], Lft)
  |> expect.to_equal([list_move([Index(1)], 1)])
  transform([list_move([Index(0)], 1)], [list_move([Index(1)], 3)], Lft)
  |> expect.to_equal([list_move([Index(0)], 0)])
  transform([list_move([Index(2)], 1)], [list_move([Index(3)], 2)], Lft)
  |> expect.to_equal([list_move([Index(3)], 1)])
  transform([list_move([Index(3)], 2)], [list_move([Index(2)], 1)], Lft)
  |> expect.to_equal([list_move([Index(3)], 3)])
}

pub fn indices_around_a_move_test() -> Nil {
  transform(
    [list_insert([Index(0), Index(0)], object([]))],
    [list_move([Index(1)], 0)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(1), Index(0)], object([]))])
  transform(
    [list_move([Index(1)], 0)],
    [list_delete([Index(0)], object([]))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(0)], 0)])
  transform(
    [list_move([Index(0)], 1)],
    [list_delete([Index(1)], object([]))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(0)], 0)])
  transform(
    [list_move([Index(6)], 0)],
    [list_delete([Index(2)], object([]))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(5)], 0)])
  transform(
    [list_move([Index(1)], 0)],
    [list_delete([Index(2)], object([]))],
    Lft,
  )
  |> expect.to_equal([list_move([Index(1)], 0)])
  transform(
    [list_move([Index(2)], 1)],
    [list_delete([Index(1)], number_value(3))],
    Rgt,
  )
  |> expect.to_equal([list_move([Index(1)], 1)])
  transform(
    [list_delete([Index(2)], object([]))],
    [list_move([Index(1)], 2)],
    Rgt,
  )
  |> expect.to_equal([list_delete([Index(1)], object([]))])
  transform(
    [list_delete([Index(1)], object([]))],
    [list_move([Index(2)], 1)],
    Lft,
  )
  |> expect.to_equal([list_delete([Index(2)], object([]))])
  transform(
    [list_delete([Index(1)], object([]))],
    [list_move([Index(0)], 1)],
    Rgt,
  )
  |> expect.to_equal([list_delete([Index(0)], object([]))])
  transform(
    [list_replace([Index(1)], number_value(1), number_value(2))],
    [list_move([Index(1)], 0)],
    Lft,
  )
  |> expect.to_equal([
    list_replace([Index(0)], number_value(1), number_value(2)),
  ])
  transform(
    [list_replace([Index(1)], number_value(2), number_value(3))],
    [list_move([Index(0)], 1)],
    Lft,
  )
  |> expect.to_equal([
    list_replace([Index(0)], number_value(2), number_value(3)),
  ])
  transform(
    [list_replace([Index(0)], number_value(3), number_value(4))],
    [list_move([Index(1)], 0)],
    Lft,
  )
  |> expect.to_equal([
    list_replace([Index(1)], number_value(3), number_value(4)),
  ])
}

pub fn li_vs_lm_table_test() -> Nil {
  transform(
    [list_insert([Index(0)], array([]))],
    [list_move([Index(1)], 3)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(0)], array([]))])
  transform(
    [list_insert([Index(1)], array([]))],
    [list_move([Index(1)], 3)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(1)], array([]))])
  transform(
    [list_insert([Index(2)], array([]))],
    [list_move([Index(1)], 3)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(1)], array([]))])
  transform(
    [list_insert([Index(3)], array([]))],
    [list_move([Index(1)], 3)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(2)], array([]))])
  transform(
    [list_insert([Index(4)], array([]))],
    [list_move([Index(1)], 3)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(4)], array([]))])

  transform(
    [list_move([Index(1)], 3)],
    [list_insert([Index(0)], array([]))],
    Rgt,
  )
  |> expect.to_equal([list_move([Index(2)], 4)])
  transform(
    [list_move([Index(1)], 3)],
    [list_insert([Index(1)], array([]))],
    Rgt,
  )
  |> expect.to_equal([list_move([Index(2)], 4)])
  transform(
    [list_move([Index(1)], 3)],
    [list_insert([Index(2)], array([]))],
    Rgt,
  )
  |> expect.to_equal([list_move([Index(1)], 4)])
  transform(
    [list_move([Index(1)], 3)],
    [list_insert([Index(3)], array([]))],
    Rgt,
  )
  |> expect.to_equal([list_move([Index(1)], 4)])
  transform(
    [list_move([Index(1)], 3)],
    [list_insert([Index(4)], array([]))],
    Rgt,
  )
  |> expect.to_equal([list_move([Index(1)], 3)])

  transform(
    [list_insert([Index(0)], array([]))],
    [list_move([Index(3)], 1)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(0)], array([]))])
  transform(
    [list_insert([Index(2)], array([]))],
    [list_move([Index(3)], 1)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(3)], array([]))])
  transform(
    [list_insert([Index(3)], array([]))],
    [list_move([Index(3)], 1)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(4)], array([]))])
  transform(
    [list_insert([Index(4)], array([]))],
    [list_move([Index(3)], 1)],
    Lft,
  )
  |> expect.to_equal([list_insert([Index(4)], array([]))])
}

// ── object ────────────────────────────────────────────────────────────────────

pub fn simultaneous_object_inserts_left_wins_test() -> Nil {
  transform(
    [object_insert([Index(1)], string_value("a"))],
    [object_insert([Index(1)], string_value("b"))],
    Lft,
  )
  |> expect.to_equal([
    object_replace([Index(1)], string_value("b"), string_value("a")),
  ])
  transform(
    [object_insert([Index(1)], string_value("b"))],
    [object_insert([Index(1)], string_value("a"))],
    Rgt,
  )
  |> expect.to_equal([])
}

pub fn parallel_object_ops_miss_each_other_test() -> Nil {
  transform(
    [object_insert([Key("a")], string_value("x"))],
    [object_insert([Key("b")], string_value("z"))],
    Lft,
  )
  |> expect.to_equal([object_insert([Key("a")], string_value("x"))])
  transform(
    [object_insert([Key("a")], string_value("x"))],
    [object_delete([Key("b")], string_value("z"))],
    Lft,
  )
  |> expect.to_equal([object_insert([Key("a")], string_value("x"))])
  transform(
    [object_insert([Key("in"), Key("he")], object([]))],
    [object_delete([Key("and")], object([]))],
    Rgt,
  )
  |> expect.to_equal([object_insert([Key("in"), Key("he")], object([]))])
}

pub fn object_replacement_vs_deletion_test() -> Nil {
  transform(
    [object_replace([], array([string_value("")]), object([]))],
    [object_delete([], array([string_value("")]))],
    Rgt,
  )
  |> expect.to_equal([object_insert([], object([]))])
}

pub fn object_replacement_vs_replacement_test() -> Nil {
  transform(
    [
      object_delete([], array([string_value("")])),
      object_insert([], object([])),
    ],
    [object_delete([], array([string_value("")])), object_insert([], VNull)],
    Rgt,
  )
  |> expect.to_equal([])
  transform(
    [
      object_delete([], array([string_value("")])),
      object_insert([], object([])),
    ],
    [object_delete([], array([string_value("")])), object_insert([], VNull)],
    Lft,
  )
  |> expect.to_equal([object_replace([], VNull, object([]))])
  transform(
    [object_replace([], array([string_value("")]), object([]))],
    [object_replace([], array([string_value("")]), VNull)],
    Rgt,
  )
  |> expect.to_equal([])
  transform(
    [object_replace([], array([string_value("")]), object([]))],
    [object_replace([], array([string_value("")]), VNull)],
    Lft,
  )
  |> expect.to_equal([object_replace([], VNull, object([]))])
}

pub fn re_delete_key_noop_test() -> Nil {
  transform(
    [object_delete([Key("k")], string_value("x"))],
    [object_delete([Key("k")], string_value("x"))],
    Lft,
  )
  |> expect.to_equal([])
  transform(
    [object_delete([Key("k")], string_value("x"))],
    [object_delete([Key("k")], string_value("x"))],
    Rgt,
  )
  |> expect.to_equal([])
}

pub fn deleted_data_reflects_edits_test() -> Nil {
  transform(
    [object_replace([], number_value(22), array([]))],
    [number_add([], 3)],
    Lft,
  )
  |> expect.to_equal([object_replace([], number_value(25), array([]))])
  transform(
    [object_replace([], object([#("toves", number_value(0))]), number_value(4))],
    [object_replace([Key("toves")], number_value(0), string_value(""))],
    Lft,
  )
  |> expect.to_equal([
    object_replace([], object([#("toves", string_value(""))]), number_value(4)),
  ])
  transform(
    [number_add([Key("bird")], 2)],
    [
      object_replace(
        [],
        object([#("bird", number_value(38))]),
        number_value(20),
      ),
    ],
    Rgt,
  )
  |> expect.to_equal([])
  transform(
    [
      object_replace(
        [],
        object([#("bird", number_value(38))]),
        number_value(20),
      ),
    ],
    [number_add([Key("bird")], 2)],
    Lft,
  )
  |> expect.to_equal([
    object_replace([], object([#("bird", number_value(40))]), number_value(20)),
  ])
  transform(
    [object_delete([Key("He")], array([]))],
    [number_add([Key("The")], -3)],
    Rgt,
  )
  |> expect.to_equal([object_delete([Key("He")], array([]))])
  transform(
    [object_insert([Key("He")], object([]))],
    [object_replace([], object([]), string_value("the"))],
    Lft,
  )
  |> expect.to_equal([])
}

// ── number: transformX keeps na merges intact (diamond) ───────────────────────

pub fn na_merge_diamond_test() -> Nil {
  let right_op = [
    object_replace([], number_value(0), number_value(15)),
    number_add([], 4),
    number_add([], 1),
    number_add([], 1),
  ]
  let left_op = [number_add([], 4), number_add([], -1)]
  let assert Ok(right_) = json_ot.transform(right_op, left_op, Rgt)
  let assert Ok(left_) = json_ot.transform(left_op, right_op, Lft)
  let assert Ok(s_c) = json_ot.apply(number_value(21), left_)
  let assert Ok(c_s) = json_ot.apply(number_value(3), right_)
  s_c |> expect.to_equal(c_s)
}

// ── object insert tie-break interplay with multi-op transformX ────────────────

pub fn object_replacement_diamond_property_test() -> Nil {
  let right_ops = [object_replace([], VNull, object([]))]
  let left_ops = [object_replace([], VNull, string_value(""))]
  let assert Ok(right_has) = json_ot.apply(VNull, right_ops)
  let assert Ok(left_has) = json_ot.apply(VNull, left_ops)
  let assert Ok(left_) = json_ot.transform(left_ops, right_ops, Lft)
  let assert Ok(right_) = json_ot.transform(right_ops, left_ops, Rgt)
  let assert Ok(a) = json_ot.apply(right_has, left_)
  let assert Ok(b) = json_ot.apply(left_has, right_)
  a |> expect.to_equal(left_has)
  b |> expect.to_equal(left_has)
}

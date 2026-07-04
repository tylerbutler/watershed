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

fn s(x: String) -> JsonValue {
  VString(x)
}

fn n(x: Int) -> JsonValue {
  VNumber(NInt(x))
}

fn obj(members: List(#(String, JsonValue))) -> JsonValue {
  VObject(members)
}

fn arr(items: List(JsonValue)) -> JsonValue {
  VArray(items)
}

fn li(path: List(json_ot.PathKey), v: JsonValue) -> Component {
  json_ot.list_insert(path, v)
}

fn ld(path: List(json_ot.PathKey), v: JsonValue) -> Component {
  json_ot.list_delete(path, v)
}

fn lr(path: List(json_ot.PathKey), o: JsonValue, nw: JsonValue) -> Component {
  json_ot.list_replace(path, o, nw)
}

fn lm(path: List(json_ot.PathKey), to: Int) -> Component {
  json_ot.list_move(path, to)
}

fn oi(path: List(json_ot.PathKey), v: JsonValue) -> Component {
  json_ot.obj_insert(path, v)
}

fn od(path: List(json_ot.PathKey), v: JsonValue) -> Component {
  json_ot.obj_delete(path, v)
}

fn orr(path: List(json_ot.PathKey), o: JsonValue, nw: JsonValue) -> Component {
  json_ot.obj_replace(path, o, nw)
}

fn na(path: List(json_ot.PathKey), delta: Int) -> Component {
  json_ot.number_add(path, NInt(delta))
}

fn xf(op: Op, other: Op, side: json_ot.Side) -> Op {
  let assert Ok(result) = json_ot.transform(op, other, side)
  result
}

// ── list: index bumps, noops, tiebreaks ──────────────────────────────────────

pub fn ld_bumps_past_li_test() {
  xf([ld([Index(0)], n(2))], [li([Index(0)], n(1))], Lft)
  |> expect.to_equal([ld([Index(1)], n(2))])
  xf([ld([Index(0)], n(2))], [li([Index(0)], n(1))], Rgt)
  |> expect.to_equal([ld([Index(1)], n(2))])
}

pub fn ops_on_deleted_elements_become_noops_test() {
  xf([li([Index(0)], s("x"))], [ld([Index(0)], s("y"))], Lft)
  |> expect.to_equal([li([Index(0)], s("x"))])
  xf([na([Index(0)], -3)], [ld([Index(0)], n(48))], Lft)
  |> expect.to_equal([])
}

pub fn ops_on_replaced_elements_become_noops_test() {
  xf([li([Index(0)], s("hi"))], [lr([Index(0)], s("x"), s("y"))], Lft)
  |> expect.to_equal([li([Index(0)], s("hi"))])
}

pub fn simultaneous_list_inserts_left_first_test() {
  xf([li([Index(1)], s("a"))], [li([Index(1)], s("b"))], Lft)
  |> expect.to_equal([li([Index(1)], s("a"))])
  xf([li([Index(1)], s("b"))], [li([Index(1)], s("a"))], Rgt)
  |> expect.to_equal([li([Index(2)], s("b"))])
}

pub fn re_delete_list_element_noop_test() {
  xf([ld([Index(1)], s("x"))], [ld([Index(1)], s("x"))], Lft)
  |> expect.to_equal([])
  xf([ld([Index(1)], s("x"))], [ld([Index(1)], s("x"))], Rgt)
  |> expect.to_equal([])
}

pub fn replace_null_vs_insert_test() {
  xf([lr([Index(0)], VNull, s("x"))], [li([Index(0)], s("The"))], Rgt)
  |> expect.to_equal([lr([Index(1)], VNull, s("x"))])
}

// ── list: moves carry ops with the element ────────────────────────────────────

pub fn moves_ops_with_element_test() {
  xf([ld([Index(4)], s("x"))], [lm([Index(4)], 10)], Lft)
  |> expect.to_equal([ld([Index(10)], s("x"))])
  xf([li([Index(4), Index(1)], s("a"))], [lm([Index(4)], 10)], Lft)
  |> expect.to_equal([li([Index(10), Index(1)], s("a"))])
  xf([lr([Index(4), Index(1)], s("b"), s("a"))], [lm([Index(4)], 10)], Lft)
  |> expect.to_equal([lr([Index(10), Index(1)], s("b"), s("a"))])
  xf([li([Index(0)], VNull)], [lm([Index(0)], 1)], Lft)
  |> expect.to_equal([li([Index(0)], VNull)])
  xf([li([Index(5)], s("x"))], [lm([Index(5)], 1)], Lft)
  |> expect.to_equal([li([Index(6)], s("x"))])
  xf([ld([Index(5)], n(6))], [lm([Index(5)], 1)], Lft)
  |> expect.to_equal([ld([Index(1)], n(6))])
  xf([li([Index(0)], arr([]))], [lm([Index(1)], 0)], Lft)
  |> expect.to_equal([li([Index(0)], arr([]))])
  xf([li([Index(2)], s("x"))], [lm([Index(0)], 1)], Lft)
  |> expect.to_equal([li([Index(2)], s("x"))])
}

pub fn moves_target_index_on_ld_li_test() {
  xf([lm([Index(0)], 2)], [ld([Index(1)], s("x"))], Lft)
  |> expect.to_equal([lm([Index(0)], 1)])
  xf([lm([Index(2)], 4)], [ld([Index(1)], s("x"))], Lft)
  |> expect.to_equal([lm([Index(1)], 3)])
  xf([lm([Index(0)], 2)], [li([Index(1)], s("x"))], Lft)
  |> expect.to_equal([lm([Index(0)], 3)])
  xf([lm([Index(2)], 4)], [li([Index(1)], s("x"))], Lft)
  |> expect.to_equal([lm([Index(3)], 5)])
  xf([lm([Index(0)], 0)], [li([Index(0)], n(28))], Lft)
  |> expect.to_equal([lm([Index(1)], 1)])
}

pub fn tiebreaks_lm_vs_ld_li_test() {
  xf([lm([Index(0)], 2)], [ld([Index(0)], s("x"))], Lft)
  |> expect.to_equal([])
  xf([lm([Index(0)], 2)], [ld([Index(0)], s("x"))], Rgt)
  |> expect.to_equal([])
  xf([lm([Index(0)], 2)], [li([Index(0)], s("x"))], Lft)
  |> expect.to_equal([lm([Index(1)], 3)])
  xf([lm([Index(0)], 2)], [li([Index(0)], s("x"))], Rgt)
  |> expect.to_equal([lm([Index(1)], 3)])
}

pub fn list_replacement_vs_deletion_test() {
  xf([lr([Index(0)], s("x"), s("y"))], [ld([Index(0)], s("x"))], Rgt)
  |> expect.to_equal([li([Index(0)], s("y"))])
}

pub fn list_replacement_vs_insertion_test() {
  xf([lr([Index(0)], obj([]), s("brillig"))], [li([Index(0)], n(36))], Lft)
  |> expect.to_equal([lr([Index(1)], obj([]), s("brillig"))])
}

pub fn list_replacement_vs_replacement_test() {
  xf([lr([Index(0)], VNull, arr([]))], [lr([Index(0)], VNull, n(0))], Rgt)
  |> expect.to_equal([])
  xf([lr([Index(0)], VNull, n(0))], [lr([Index(0)], VNull, arr([]))], Lft)
  |> expect.to_equal([lr([Index(0)], arr([]), n(0))])
}

// ── lm vs lm (the full spec table) ────────────────────────────────────────────

pub fn lm_vs_lm_table_test() {
  xf([lm([Index(0)], 2)], [lm([Index(2)], 1)], Lft)
  |> expect.to_equal([lm([Index(0)], 2)])
  xf([lm([Index(3)], 3)], [lm([Index(5)], 0)], Lft)
  |> expect.to_equal([lm([Index(4)], 4)])
  xf([lm([Index(2)], 0)], [lm([Index(1)], 0)], Lft)
  |> expect.to_equal([lm([Index(2)], 0)])
  xf([lm([Index(2)], 0)], [lm([Index(1)], 0)], Rgt)
  |> expect.to_equal([lm([Index(2)], 1)])
  xf([lm([Index(2)], 0)], [lm([Index(5)], 0)], Rgt)
  |> expect.to_equal([lm([Index(3)], 1)])
  xf([lm([Index(2)], 0)], [lm([Index(5)], 0)], Lft)
  |> expect.to_equal([lm([Index(3)], 0)])
  xf([lm([Index(2)], 5)], [lm([Index(2)], 0)], Lft)
  |> expect.to_equal([lm([Index(0)], 5)])
  xf([lm([Index(1)], 0)], [lm([Index(0)], 5)], Rgt)
  |> expect.to_equal([lm([Index(0)], 0)])
  xf([lm([Index(1)], 0)], [lm([Index(0)], 1)], Rgt)
  |> expect.to_equal([lm([Index(0)], 0)])
  xf([lm([Index(0)], 1)], [lm([Index(1)], 0)], Lft)
  |> expect.to_equal([lm([Index(1)], 1)])
  xf([lm([Index(0)], 1)], [lm([Index(5)], 0)], Rgt)
  |> expect.to_equal([lm([Index(1)], 2)])
  xf([lm([Index(2)], 1)], [lm([Index(5)], 0)], Rgt)
  |> expect.to_equal([lm([Index(3)], 2)])
  xf([lm([Index(3)], 1)], [lm([Index(1)], 3)], Lft)
  |> expect.to_equal([lm([Index(2)], 1)])
  xf([lm([Index(1)], 3)], [lm([Index(3)], 1)], Lft)
  |> expect.to_equal([lm([Index(2)], 3)])
  xf([lm([Index(2)], 6)], [lm([Index(0)], 1)], Lft)
  |> expect.to_equal([lm([Index(2)], 6)])
  xf([lm([Index(2)], 6)], [lm([Index(0)], 1)], Rgt)
  |> expect.to_equal([lm([Index(2)], 6)])
  xf([lm([Index(2)], 6)], [lm([Index(1)], 0)], Lft)
  |> expect.to_equal([lm([Index(2)], 6)])
  xf([lm([Index(2)], 6)], [lm([Index(1)], 0)], Rgt)
  |> expect.to_equal([lm([Index(2)], 6)])
  xf([lm([Index(0)], 1)], [lm([Index(2)], 1)], Lft)
  |> expect.to_equal([lm([Index(0)], 2)])
  xf([lm([Index(2)], 1)], [lm([Index(0)], 1)], Rgt)
  |> expect.to_equal([lm([Index(2)], 0)])
  xf([lm([Index(0)], 0)], [lm([Index(1)], 0)], Lft)
  |> expect.to_equal([lm([Index(1)], 1)])
  xf([lm([Index(0)], 1)], [lm([Index(1)], 3)], Lft)
  |> expect.to_equal([lm([Index(0)], 0)])
  xf([lm([Index(2)], 1)], [lm([Index(3)], 2)], Lft)
  |> expect.to_equal([lm([Index(3)], 1)])
  xf([lm([Index(3)], 2)], [lm([Index(2)], 1)], Lft)
  |> expect.to_equal([lm([Index(3)], 3)])
}

pub fn indices_around_a_move_test() {
  xf([li([Index(0), Index(0)], obj([]))], [lm([Index(1)], 0)], Lft)
  |> expect.to_equal([li([Index(1), Index(0)], obj([]))])
  xf([lm([Index(1)], 0)], [ld([Index(0)], obj([]))], Lft)
  |> expect.to_equal([lm([Index(0)], 0)])
  xf([lm([Index(0)], 1)], [ld([Index(1)], obj([]))], Lft)
  |> expect.to_equal([lm([Index(0)], 0)])
  xf([lm([Index(6)], 0)], [ld([Index(2)], obj([]))], Lft)
  |> expect.to_equal([lm([Index(5)], 0)])
  xf([lm([Index(1)], 0)], [ld([Index(2)], obj([]))], Lft)
  |> expect.to_equal([lm([Index(1)], 0)])
  xf([lm([Index(2)], 1)], [ld([Index(1)], n(3))], Rgt)
  |> expect.to_equal([lm([Index(1)], 1)])
  xf([ld([Index(2)], obj([]))], [lm([Index(1)], 2)], Rgt)
  |> expect.to_equal([ld([Index(1)], obj([]))])
  xf([ld([Index(1)], obj([]))], [lm([Index(2)], 1)], Lft)
  |> expect.to_equal([ld([Index(2)], obj([]))])
  xf([ld([Index(1)], obj([]))], [lm([Index(0)], 1)], Rgt)
  |> expect.to_equal([ld([Index(0)], obj([]))])
  xf([lr([Index(1)], n(1), n(2))], [lm([Index(1)], 0)], Lft)
  |> expect.to_equal([lr([Index(0)], n(1), n(2))])
  xf([lr([Index(1)], n(2), n(3))], [lm([Index(0)], 1)], Lft)
  |> expect.to_equal([lr([Index(0)], n(2), n(3))])
  xf([lr([Index(0)], n(3), n(4))], [lm([Index(1)], 0)], Lft)
  |> expect.to_equal([lr([Index(1)], n(3), n(4))])
}

pub fn li_vs_lm_table_test() {
  xf([li([Index(0)], arr([]))], [lm([Index(1)], 3)], Lft)
  |> expect.to_equal([li([Index(0)], arr([]))])
  xf([li([Index(1)], arr([]))], [lm([Index(1)], 3)], Lft)
  |> expect.to_equal([li([Index(1)], arr([]))])
  xf([li([Index(2)], arr([]))], [lm([Index(1)], 3)], Lft)
  |> expect.to_equal([li([Index(1)], arr([]))])
  xf([li([Index(3)], arr([]))], [lm([Index(1)], 3)], Lft)
  |> expect.to_equal([li([Index(2)], arr([]))])
  xf([li([Index(4)], arr([]))], [lm([Index(1)], 3)], Lft)
  |> expect.to_equal([li([Index(4)], arr([]))])

  xf([lm([Index(1)], 3)], [li([Index(0)], arr([]))], Rgt)
  |> expect.to_equal([lm([Index(2)], 4)])
  xf([lm([Index(1)], 3)], [li([Index(1)], arr([]))], Rgt)
  |> expect.to_equal([lm([Index(2)], 4)])
  xf([lm([Index(1)], 3)], [li([Index(2)], arr([]))], Rgt)
  |> expect.to_equal([lm([Index(1)], 4)])
  xf([lm([Index(1)], 3)], [li([Index(3)], arr([]))], Rgt)
  |> expect.to_equal([lm([Index(1)], 4)])
  xf([lm([Index(1)], 3)], [li([Index(4)], arr([]))], Rgt)
  |> expect.to_equal([lm([Index(1)], 3)])

  xf([li([Index(0)], arr([]))], [lm([Index(3)], 1)], Lft)
  |> expect.to_equal([li([Index(0)], arr([]))])
  xf([li([Index(2)], arr([]))], [lm([Index(3)], 1)], Lft)
  |> expect.to_equal([li([Index(3)], arr([]))])
  xf([li([Index(3)], arr([]))], [lm([Index(3)], 1)], Lft)
  |> expect.to_equal([li([Index(4)], arr([]))])
  xf([li([Index(4)], arr([]))], [lm([Index(3)], 1)], Lft)
  |> expect.to_equal([li([Index(4)], arr([]))])
}

// ── object ────────────────────────────────────────────────────────────────────

pub fn simultaneous_object_inserts_left_wins_test() {
  xf([oi([Index(1)], s("a"))], [oi([Index(1)], s("b"))], Lft)
  |> expect.to_equal([orr([Index(1)], s("b"), s("a"))])
  xf([oi([Index(1)], s("b"))], [oi([Index(1)], s("a"))], Rgt)
  |> expect.to_equal([])
}

pub fn parallel_object_ops_miss_each_other_test() {
  xf([oi([Key("a")], s("x"))], [oi([Key("b")], s("z"))], Lft)
  |> expect.to_equal([oi([Key("a")], s("x"))])
  xf([oi([Key("a")], s("x"))], [od([Key("b")], s("z"))], Lft)
  |> expect.to_equal([oi([Key("a")], s("x"))])
  xf([oi([Key("in"), Key("he")], obj([]))], [od([Key("and")], obj([]))], Rgt)
  |> expect.to_equal([oi([Key("in"), Key("he")], obj([]))])
}

pub fn object_replacement_vs_deletion_test() {
  xf([orr([], arr([s("")]), obj([]))], [od([], arr([s("")]))], Rgt)
  |> expect.to_equal([oi([], obj([]))])
}

pub fn object_replacement_vs_replacement_test() {
  xf(
    [od([], arr([s("")])), oi([], obj([]))],
    [od([], arr([s("")])), oi([], VNull)],
    Rgt,
  )
  |> expect.to_equal([])
  xf(
    [od([], arr([s("")])), oi([], obj([]))],
    [od([], arr([s("")])), oi([], VNull)],
    Lft,
  )
  |> expect.to_equal([orr([], VNull, obj([]))])
  xf([orr([], arr([s("")]), obj([]))], [orr([], arr([s("")]), VNull)], Rgt)
  |> expect.to_equal([])
  xf([orr([], arr([s("")]), obj([]))], [orr([], arr([s("")]), VNull)], Lft)
  |> expect.to_equal([orr([], VNull, obj([]))])
}

pub fn re_delete_key_noop_test() {
  xf([od([Key("k")], s("x"))], [od([Key("k")], s("x"))], Lft)
  |> expect.to_equal([])
  xf([od([Key("k")], s("x"))], [od([Key("k")], s("x"))], Rgt)
  |> expect.to_equal([])
}

pub fn deleted_data_reflects_edits_test() {
  xf([orr([], n(22), arr([]))], [na([], 3)], Lft)
  |> expect.to_equal([orr([], n(25), arr([]))])
  xf(
    [orr([], obj([#("toves", n(0))]), n(4))],
    [orr([Key("toves")], n(0), s(""))],
    Lft,
  )
  |> expect.to_equal([orr([], obj([#("toves", s(""))]), n(4))])
  xf([na([Key("bird")], 2)], [orr([], obj([#("bird", n(38))]), n(20))], Rgt)
  |> expect.to_equal([])
  xf([orr([], obj([#("bird", n(38))]), n(20))], [na([Key("bird")], 2)], Lft)
  |> expect.to_equal([orr([], obj([#("bird", n(40))]), n(20))])
  xf([od([Key("He")], arr([]))], [na([Key("The")], -3)], Rgt)
  |> expect.to_equal([od([Key("He")], arr([]))])
  xf([oi([Key("He")], obj([]))], [orr([], obj([]), s("the"))], Lft)
  |> expect.to_equal([])
}

// ── number: transformX keeps na merges intact (diamond) ───────────────────────

pub fn na_merge_diamond_test() {
  let right_op = [
    orr([], n(0), n(15)),
    na([], 4),
    na([], 1),
    na([], 1),
  ]
  let left_op = [na([], 4), na([], -1)]
  let assert Ok(right_) = json_ot.transform(right_op, left_op, Rgt)
  let assert Ok(left_) = json_ot.transform(left_op, right_op, Lft)
  let assert Ok(s_c) = json_ot.apply(n(21), left_)
  let assert Ok(c_s) = json_ot.apply(n(3), right_)
  s_c |> expect.to_equal(c_s)
}

// ── object insert tie-break interplay with multi-op transformX ────────────────

pub fn object_replacement_diamond_property_test() {
  let right_ops = [orr([], VNull, obj([]))]
  let left_ops = [orr([], VNull, s(""))]
  let assert Ok(right_has) = json_ot.apply(VNull, right_ops)
  let assert Ok(left_has) = json_ot.apply(VNull, left_ops)
  let assert Ok(left_) = json_ot.transform(left_ops, right_ops, Lft)
  let assert Ok(right_) = json_ot.transform(right_ops, left_ops, Rgt)
  let assert Ok(a) = json_ot.apply(right_has, left_)
  let assert Ok(b) = json_ot.apply(left_has, right_)
  a |> expect.to_equal(left_has)
  b |> expect.to_equal(left_has)
}

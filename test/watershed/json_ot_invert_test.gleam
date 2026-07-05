//// Rung 6: rollback support. `invert(op)` must produce an op that, applied to
//// `apply(doc, op)`, restores the original `doc`. Deletes carry their
//// pre-image (`od`/`ld`), so invert needs no external snapshot — the property
//// that lets the runtime roll a nacked optimistic op back to its prior state.

import startest/expect
import watershed/json_ot.{
  type JsonValue, Index, Key, NInt, VArray, VNumber, VString,
}

fn parse(raw: String) -> JsonValue {
  let assert Ok(value) = json_ot.from_json_string(raw)
  value
}

/// `apply(apply(doc, op), invert(op)) == doc`.
fn round_trips(doc: JsonValue, op: json_ot.Op) -> Nil {
  let assert Ok(edited) = json_ot.apply(doc, op)
  json_ot.apply(edited, json_ot.invert(op))
  |> expect.to_equal(Ok(doc))
}

pub fn number_add_round_trips_test() {
  round_trips(VNumber(NInt(5)), [json_ot.number_add([], NInt(3))])
}

pub fn object_insert_round_trips_test() {
  round_trips(parse("{\"x\":1}"), [
    json_ot.obj_insert([Key("y")], VString("b")),
  ])
}

pub fn object_delete_round_trips_test() {
  round_trips(parse("{\"x\":1,\"y\":\"b\"}"), [
    json_ot.obj_delete([Key("y")], VString("b")),
  ])
}

pub fn object_replace_round_trips_test() {
  round_trips(parse("{\"x\":\"old\"}"), [
    json_ot.obj_replace([Key("x")], VString("old"), VString("new")),
  ])
}

pub fn list_insert_round_trips_test() {
  round_trips(parse("[1,2,3]"), [
    json_ot.list_insert([Index(1)], VNumber(NInt(9))),
  ])
}

pub fn list_delete_round_trips_test() {
  round_trips(parse("[1,2,3]"), [
    json_ot.list_delete([Index(1)], VNumber(NInt(2))),
  ])
}

pub fn list_move_round_trips_test() {
  round_trips(parse("[\"a\",\"b\",\"c\",\"d\"]"), [
    json_ot.list_move([Index(0)], 2),
  ])
}

pub fn multi_component_round_trips_test() {
  round_trips(parse("{\"n\":1,\"list\":[10,20]}"), [
    json_ot.number_add([Key("n")], NInt(4)),
    json_ot.list_insert([Key("list"), Index(0)], VNumber(NInt(5))),
    json_ot.obj_insert([Key("tag")], VString("x")),
  ])
}

pub fn nested_object_round_trips_test() {
  round_trips(parse("{\"a\":{\"b\":{\"c\":\"z\"}}}"), [
    json_ot.obj_replace(
      [Key("a"), Key("b"), Key("c")],
      VString("z"),
      VString("q"),
    ),
  ])
}

pub fn double_invert_is_identity_test() {
  let op = [
    json_ot.number_add([Key("n")], NInt(7)),
    json_ot.list_delete([Key("l"), Index(0)], VArray([])),
  ]
  json_ot.invert(json_ot.invert(op))
  |> expect.to_equal(op)
}

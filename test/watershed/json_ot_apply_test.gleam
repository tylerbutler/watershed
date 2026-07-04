import startest/expect
import watershed/json_ot.{
  type JsonValue, Index, Key, NInt, VArray, VNumber, VObject, VString,
}

fn parse(raw: String) -> JsonValue {
  let assert Ok(value) = json_ot.from_json_string(raw)
  value
}

fn apply_ok(doc: JsonValue, op: json_ot.Op) -> JsonValue {
  let assert Ok(result) = json_ot.apply(doc, op)
  result
}

// ── number ──────────────────────────────────────────────────────────────────

pub fn number_add_at_root_test() {
  json_ot.apply(VNumber(NInt(1)), [json_ot.number_add([], NInt(2))])
  |> expect.to_equal(Ok(VNumber(NInt(3))))
}

pub fn number_add_in_list_test() {
  apply_ok(parse("[1]"), [json_ot.number_add([Index(0)], NInt(2))])
  |> expect.to_equal(parse("[3]"))
}

pub fn number_add_wrong_type_errors_test() {
  case json_ot.apply(VString("a"), [json_ot.number_add([], NInt(1))]) {
    Error(json_ot.BadValue(_)) -> Nil
    _ -> panic as "expected BadValue"
  }
}

// ── object ──────────────────────────────────────────────────────────────────

pub fn object_insert_test() {
  apply_ok(parse("{\"x\":\"a\"}"), [
    json_ot.obj_insert([Key("y")], VString("b")),
  ])
  |> expect.to_equal(parse("{\"x\":\"a\",\"y\":\"b\"}"))
}

pub fn object_delete_test() {
  apply_ok(parse("{\"x\":\"a\"}"), [json_ot.obj_delete([Key("x")], VString("a"))])
  |> expect.to_equal(parse("{}"))
}

pub fn object_replace_test() {
  apply_ok(parse("{\"x\":\"a\"}"), [
    json_ot.obj_replace([Key("x")], VString("a"), VString("b")),
  ])
  |> expect.to_equal(parse("{\"x\":\"b\"}"))
}

pub fn nested_object_edit_test() {
  apply_ok(parse("{\"a\":{\"b\":1}}"), [
    json_ot.number_add([Key("a"), Key("b")], NInt(4)),
  ])
  |> expect.to_equal(parse("{\"a\":{\"b\":5}}"))
}

// ── list ────────────────────────────────────────────────────────────────────

pub fn list_insert_front_test() {
  apply_ok(parse("[\"b\",\"c\"]"), [json_ot.list_insert([Index(0)], VString("a"))])
  |> expect.to_equal(parse("[\"a\",\"b\",\"c\"]"))
}

pub fn list_insert_middle_test() {
  apply_ok(parse("[\"a\",\"c\"]"), [json_ot.list_insert([Index(1)], VString("b"))])
  |> expect.to_equal(parse("[\"a\",\"b\",\"c\"]"))
}

pub fn list_insert_end_test() {
  apply_ok(parse("[\"a\",\"b\"]"), [json_ot.list_insert([Index(2)], VString("c"))])
  |> expect.to_equal(parse("[\"a\",\"b\",\"c\"]"))
}

pub fn list_delete_test() {
  apply_ok(parse("[\"a\",\"b\",\"c\"]"), [
    json_ot.list_delete([Index(1)], VString("b")),
  ])
  |> expect.to_equal(parse("[\"a\",\"c\"]"))
}

pub fn list_replace_test() {
  apply_ok(parse("[\"a\",\"x\",\"b\"]"), [
    json_ot.list_replace([Index(1)], VString("x"), VString("y")),
  ])
  |> expect.to_equal(parse("[\"a\",\"y\",\"b\"]"))
}

pub fn list_move_backward_test() {
  apply_ok(parse("[\"b\",\"a\",\"c\"]"), [json_ot.list_move([Index(1)], 0)])
  |> expect.to_equal(parse("[\"a\",\"b\",\"c\"]"))
}

pub fn list_move_forward_test() {
  apply_ok(parse("[\"b\",\"a\",\"c\"]"), [json_ot.list_move([Index(0)], 1)])
  |> expect.to_equal(parse("[\"a\",\"b\",\"c\"]"))
}

pub fn multi_component_op_test() {
  apply_ok(parse("{\"x\":1}"), [
    json_ot.number_add([Key("x")], NInt(2)),
    json_ot.obj_insert([Key("y")], VString("hi")),
  ])
  |> expect.to_equal(parse("{\"x\":3,\"y\":\"hi\"}"))
}

pub fn object_keys_are_sorted_test() {
  // Insertion order differs from sorted order; equality must be canonical.
  let a = apply_ok(parse("{}"), [
    json_ot.obj_insert([Key("z")], VNumber(NInt(1))),
    json_ot.obj_insert([Key("a")], VNumber(NInt(2))),
  ])
  let assert VObject([#("a", _), #("z", _)]) = a
  Nil
}

//// Tests for the `text0` subtype: direct apply/invert plus TP1 convergence of
//// concurrent string edits, both standalone and embedded in a json0 document.

import startest/expect
import watershed/json_ot.{
  type JsonValue, type Operation, Key, Lft, NInt, Rgt, VNumber, VObject, VString,
}

fn ins(p: Int, s: String) -> JsonValue {
  VObject([#("i", VString(s)), #("p", VNumber(NInt(p)))])
}

fn del(p: Int, s: String) -> JsonValue {
  VObject([#("d", VString(s)), #("p", VNumber(NInt(p)))])
}

fn t0(components: List(JsonValue)) -> JsonValue {
  json_ot.VArray(components)
}

fn apply0(doc: String, operation: JsonValue) -> JsonValue {
  let assert Ok(result) =
    json_ot.apply_subtype("text0", VString(doc), operation)
  result
}

// ── apply ──────────────────────────────────────────────────────────────────

pub fn text0_apply_insert_test() -> Nil {
  apply0("hello", t0([ins(5, " world")]))
  |> expect.to_equal(VString("hello world"))
}

pub fn text0_apply_delete_test() -> Nil {
  apply0("hello world", t0([del(5, " world")]))
  |> expect.to_equal(VString("hello"))
}

pub fn text0_apply_sequential_components_test() -> Nil {
  // Components execute in order against the running snapshot.
  apply0("ac", t0([ins(1, "b"), ins(3, "d")]))
  |> expect.to_equal(VString("abcd"))
}

pub fn text0_apply_delete_mismatch_errors_test() -> Nil {
  json_ot.apply_subtype("text0", VString("hello"), t0([del(0, "xxx")]))
  |> expect.to_equal(
    Error(json_ot.BadValue("text0 delete does not match the document text")),
  )
}

// ── invert ───────────────────────────────────────────────────────────────────

pub fn text0_invert_round_trips_test() -> Nil {
  let doc = VObject([#("t", VString("hello"))])
  let operation = text_edit(t0([ins(5, " world"), del(0, "he")]))
  let assert Ok(edited) = json_ot.apply(doc, operation)
  let inverse = json_ot.invert(operation)
  let assert Ok(back) = json_ot.apply(edited, inverse)
  back |> expect.to_equal(doc)
}

// ── transform (TP1) ──────────────────────────────────────────────────────────

/// TP1 for the embedded subtype: applying `a` then `b` transformed past `a`
/// must equal applying `b` then `a` transformed past `b`.
fn tp1(doc: JsonValue, a: Operation, b: Operation) -> #(JsonValue, JsonValue) {
  let assert Ok(after_a) = json_ot.apply(doc, a)
  let assert Ok(after_b) = json_ot.apply(doc, b)
  let assert Ok(b_star) = json_ot.transform(b, a, Rgt)
  let assert Ok(a_star) = json_ot.transform(a, b, Lft)
  let assert Ok(left) = json_ot.apply(after_a, b_star)
  let assert Ok(right) = json_ot.apply(after_b, a_star)
  #(left, right)
}

fn text_edit(operation: JsonValue) -> Operation {
  [json_ot.subtype_component([Key("t")], "text0", operation)]
}

pub fn text0_concurrent_inserts_converge_test() -> Nil {
  let doc = VObject([#("t", VString("hello"))])
  let a = text_edit(t0([ins(0, "A")]))
  let b = text_edit(t0([ins(0, "B")]))
  let #(left, right) = tp1(doc, a, b)
  left |> expect.to_equal(right)
}

pub fn text0_insert_vs_delete_converge_test() -> Nil {
  let doc = VObject([#("t", VString("hello world"))])
  let a = text_edit(t0([ins(5, "XYZ")]))
  let b = text_edit(t0([del(0, "hello")]))
  let #(left, right) = tp1(doc, a, b)
  left |> expect.to_equal(right)
}

pub fn text0_overlapping_deletes_converge_test() -> Nil {
  let doc = VObject([#("t", VString("abcdef"))])
  let a = text_edit(t0([del(1, "bcd")]))
  let b = text_edit(t0([del(2, "cde")]))
  let #(left, right) = tp1(doc, a, b)
  left |> expect.to_equal(right)
}

pub fn text0_multi_component_operations_converge_test() -> Nil {
  let doc = VObject([#("t", VString("the quick brown fox"))])
  // a: drop the leading "the ", then append "!" (positions are sequential).
  let a = text_edit(t0([del(0, "the "), ins(15, "!")]))
  // b: prepend ">> ", then drop the now-shifted "the ".
  let b = text_edit(t0([ins(0, ">> "), del(3, "the ")]))
  let #(left, right) = tp1(doc, a, b)
  left |> expect.to_equal(right)
}

/// Insert-at-same-position ties are broken by `side`, so left/right disagree on
/// order but each pair (a then b*) vs (b then a*) still converges — verified
/// above. Here we pin the concrete resolved string for the insert tie.
pub fn text0_insert_tie_resolves_by_side_test() -> Nil {
  let doc = VObject([#("t", VString(""))])
  let a = text_edit(t0([ins(0, "A")]))
  let b = text_edit(t0([ins(0, "B")]))
  let #(left, _right) = tp1(doc, a, b)
  // a is transformed with side Lft (stays put), b with Rgt (pushed after) when
  // applied second, so "A" precedes "B".
  left |> expect.to_equal(VObject([#("t", VString("AB"))]))
}

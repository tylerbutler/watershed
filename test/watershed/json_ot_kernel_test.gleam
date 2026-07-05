//// Focused unit tests for `json_ot_kernel` covering the single-in-flight
//// lifecycle: local submit → ack, remote apply on a fresh doc, the concurrent
//// same-index insert that must converge via `side`, and buffer release on ack.

import gleam/option.{None, Some}
import startest/expect
import watershed/json_ot.{
  type JsonValue, Index, Key, VArray, VObject, VString, list_insert, obj_insert,
}
import watershed/json_ot_kernel.{JsonOtWireOp} as kernel

fn arr(items: List(JsonValue)) -> JsonValue {
  VArray(items)
}

/// A local edit with nothing in flight is emitted as a wire op and shows up in
/// the optimistic view immediately; acking it settles `sequenced`.
pub fn local_edit_then_ack_test() {
  let state = kernel.from_value(0, arr([]))
  let op = [list_insert([Index(0)], VString("a"))]

  let assert Ok(#(state, sent, _events)) = kernel.submit(state, op, 0)
  sent |> expect.to_equal(Some(JsonOtWireOp(0, op)))
  let assert Ok(view) = kernel.view(state)
  view |> expect.to_equal(arr([VString("a")]))
  state.sequenced |> expect.to_equal(arr([]))

  let assert Ok(#(state, _events)) =
    kernel.ack_local(state, JsonOtWireOp(0, op), 1, 0)
  let #(state, released) = kernel.take_outbound(state)
  released |> expect.to_equal(None)
  state.sequenced |> expect.to_equal(arr([VString("a")]))
  state.inflight |> expect.to_equal(None)
}

/// A remote op on a fresh document applies straight to `sequenced`.
pub fn apply_remote_on_empty_test() {
  let state = kernel.from_value(1, VObject([]))
  let op = [obj_insert([Key("x")], VString("y"))]

  let assert Ok(#(state, _events)) =
    kernel.apply_remote(state, JsonOtWireOp(0, op), 1, 0, -1)
  state.sequenced |> expect.to_equal(VObject([#("x", VString("y"))]))
}

/// Two clients concurrently insert at list index 0 against the same empty doc.
/// Because `side` is derived from author id, both replicas order the inserts
/// identically and converge.
pub fn concurrent_same_index_insert_converges_test() {
  let doc = arr([])
  let op0 = [list_insert([Index(0)], VString("a"))]
  let op1 = [list_insert([Index(0)], VString("b"))]

  let c0 = kernel.from_value(0, doc)
  let assert Ok(#(c0, _, _)) = kernel.submit(c0, op0, 0)
  let assert Ok(#(c0, _)) = kernel.ack_local(c0, JsonOtWireOp(0, op0), 1, -1)
  let assert Ok(#(c0, _)) =
    kernel.apply_remote(c0, JsonOtWireOp(0, op1), 2, 1, -1)

  let c1 = kernel.from_value(1, doc)
  let assert Ok(#(c1, _, _)) = kernel.submit(c1, op1, 0)
  let assert Ok(#(c1, _)) =
    kernel.apply_remote(c1, JsonOtWireOp(0, op0), 1, 0, -1)
  let assert Ok(#(c1, _)) = kernel.ack_local(c1, JsonOtWireOp(0, op1), 2, -1)

  c0.sequenced |> expect.to_equal(c1.sequenced)
  c0.sequenced |> expect.to_equal(arr([VString("a"), VString("b")]))
}

/// A second local edit while one is in flight is buffered (nothing sent), then
/// released as the next wire op when the first is acked.
pub fn buffer_release_on_ack_test() {
  let state = kernel.from_value(0, arr([]))
  let op_a = [list_insert([Index(0)], VString("a"))]
  let op_b = [list_insert([Index(1)], VString("b"))]

  let assert Ok(#(state, sent_a, _)) = kernel.submit(state, op_a, 0)
  sent_a |> expect.to_equal(Some(JsonOtWireOp(0, op_a)))

  let assert Ok(#(state, sent_b, _)) = kernel.submit(state, op_b, 0)
  sent_b |> expect.to_equal(None)
  state.buffer |> expect.to_equal(Some(op_b))

  let assert Ok(#(state, _events)) =
    kernel.ack_local(state, JsonOtWireOp(0, op_a), 1, -1)
  let #(state, released) = kernel.take_outbound(state)
  released |> expect.to_equal(Some(JsonOtWireOp(1, op_b)))
  state.inflight |> expect.to_equal(Some(op_b))
  state.buffer |> expect.to_equal(None)
  state.sequenced |> expect.to_equal(arr([VString("a")]))

  let assert Ok(view) = kernel.view(state)
  view |> expect.to_equal(arr([VString("a"), VString("b")]))
}

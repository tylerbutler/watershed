import gleam/json
import gleam/list
import startest/expect

import watershed/handle

pub fn encode_parse_handle_test() {
  let encoded = handle.encode_handle("tree-abc")
  case handle.parse_handle(encoded) {
    Ok(addr) -> addr |> expect.to_equal("tree-abc")
    Error(_) -> panic as "expected parse_handle to succeed"
  }
}

pub fn parse_handle_rejects_multi_segment_test() {
  let multi =
    json.object([
      #("type", json.string(handle.fluid_handle_type)),
      #("url", json.string("/a/b")),
    ])
  case handle.parse_handle(multi) {
    Ok(_) -> panic as "expected multi-segment url to be rejected"
    Error(_) -> Nil
  }
}

pub fn parse_handle_rejects_extra_keys_test() {
  let extra =
    json.object([
      #("type", json.string(handle.fluid_handle_type)),
      #("url", json.string("/a")),
      #("x", json.string("y")),
    ])
  case handle.parse_handle(extra) {
    Ok(_) -> panic as "expected extra keys to cause rejection"
    Error(_) -> Nil
  }
}

pub fn collect_handle_addresses_nested_and_dedup_test() {
  let a = handle.encode_handle("a")
  let b = handle.encode_handle("b")
  let value =
    json.object([
      #("x", a),
      #("y", json.object([#("inner", a), #("other", b)])),
    ])
  let addrs = handle.collect_handle_addresses(value)
  // deduped, order depends on traversal; we expect both present
  list.length(addrs) |> expect.to_equal(2)
  list.any(addrs, fn(x) { x == "a" }) |> expect.to_be_true()
  list.any(addrs, fn(x) { x == "b" }) |> expect.to_be_true()
}

pub fn collect_handle_addresses_ignores_multi_segment_test() {
  let multi = json.object([
    #("h", json.object([#("type", json.string(handle.fluid_handle_type)), #("url", json.string("/a/b"))]))
  ])
  let addrs = handle.collect_handle_addresses(multi)
  list.length(addrs) |> expect.to_equal(0)
}

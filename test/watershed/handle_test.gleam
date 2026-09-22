import gleam/json
import gleam/list
import startest/expect

import watershed/handle

pub fn encode_handle_matches_corpus_marker_test() -> Nil {
  // The exact serialized form the TS oracle emits for a handle (see the
  // handle-* corpus fixtures); wire compatibility freezes this byte shape.
  handle.encode_handle("child-a")
  |> json.to_string
  |> expect.to_equal("{\"type\":\"__fluid_handle__\",\"url\":\"/child-a\"}")
}

pub fn encode_parse_handle_test() -> Nil {
  let encoded = handle.encode_handle("tree-abc")
  case handle.parse_handle(encoded) {
    Ok(addr) -> addr |> expect.to_equal("tree-abc")
    Error(_) -> panic as "expected parse_handle to succeed"
  }
}

pub fn parse_handle_rejects_multi_segment_test() -> Nil {
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

pub fn parse_handle_rejects_extra_keys_test() -> Nil {
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

pub fn collect_handle_addresses_nested_and_dedup_test() -> Nil {
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

pub fn collect_handle_addresses_ignores_multi_segment_test() -> Nil {
  let multi =
    json.object([
      #(
        "h",
        json.object([
          #("type", json.string(handle.fluid_handle_type)),
          #("url", json.string("/a/b")),
        ]),
      ),
    ])
  let addrs = handle.collect_handle_addresses(multi)
  list.length(addrs) |> expect.to_equal(0)
}

pub fn shared_tree_container_handle_keeps_datastore_identity_test() -> Nil {
  let marker =
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("/A/_C")),
    ])
  handle.resolve_path(marker, "/B")
  |> expect.to_equal(Ok("/A/_C"))
}

pub fn shared_tree_container_absolute_handle_ignores_context_test() -> Nil {
  let marker =
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("/A/_C")),
    ])
  handle.resolve_path(marker, "not-an-absolute-context")
  |> expect.to_equal(Ok("/A/_C"))
}

pub fn shared_tree_container_handle_resolves_relative_channel_test() -> Nil {
  let marker =
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("_C")),
      #("harmless", json.bool(True)),
    ])
  handle.resolve_path(marker, "/A") |> expect.to_equal(Ok("/A/_C"))
}

pub fn shared_tree_container_handle_preserves_escaped_components_test() -> Nil {
  let marker =
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("/A%2FB/caf%C3%A9")),
    ])
  handle.resolve_path(marker, "/context")
  |> expect.to_equal(Ok("/A%2FB/caf%C3%A9"))
}

pub fn shared_tree_container_handle_accepts_non_ascii_components_test() -> Nil {
  let marker =
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("/資料/árbol")),
    ])
  handle.resolve_path(marker, "/context")
  |> expect.to_equal(Ok("/資料/árbol"))
}

pub fn shared_tree_container_handle_rejects_external_and_traversal_test() -> Nil {
  let values = [
    "https://example.com/A/_C",
    "//example.com/A/_C",
    "../_C",
    "%2e%2e/_C",
    "/A/../_C",
    "/A/%2F/_C",
  ]
  values
  |> list.each(fn(url) {
    handle.resolve_path(
      json.object([
        #("type", json.string("__fluid_handle__")),
        #("url", json.string(url)),
      ]),
      "/A",
    )
    |> expect.to_be_error()
  })
}

pub fn shared_tree_container_handle_rejects_malformed_escape_test() -> Nil {
  let _ =
    handle.resolve_path(
      json.object([
        #("type", json.string("__fluid_handle__")),
        #("url", json.string("/A/%ZZ")),
      ]),
      "/A",
    )
    |> expect.to_be_error()
  Nil
}

pub fn shared_tree_container_handle_rejects_pending_payload_test() -> Nil {
  handle.resolve_path(
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("/A/_C")),
      #("payloadPending", json.bool(True)),
    ]),
    "/A",
  )
  |> expect.to_equal(Error(handle.UnsupportedHandle("pending handle payload")))
}

pub fn shared_tree_container_handle_rejects_wrong_marker_type_test() -> Nil {
  let _ =
    handle.resolve_path(
      json.object([
        #("type", json.string("not-a-handle")),
        #("url", json.string("/A/_C")),
      ]),
      "/A",
    )
    |> expect.to_be_error()
  Nil
}

pub fn shared_tree_container_handle_encodes_absolute_path_test() -> Nil {
  let assert Ok(encoded) = handle.encode_path("/A/_C")
  json.to_string(encoded)
  |> expect.to_equal("{\"type\":\"__fluid_handle__\",\"url\":\"/A/_C\"}")
  let _ = handle.encode_path("A/_C") |> expect.to_be_error()
  Nil
}

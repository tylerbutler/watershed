import gleam/list
import gleam/string
import startest/expect

import watershed/ids

pub fn uuid_v4_format_test() {
  let id = ids.uuid_v4()
  string.length(id) |> expect.to_equal(36)
  let parts = string.split(id, "-")
  list.map(parts, string.length) |> expect.to_equal([8, 4, 4, 4, 12])
  // Version nibble is always 4.
  string.slice(id, 14, 1) |> expect.to_equal("4")
  // Variant nibble is one of 8, 9, a, b (RFC 4122).
  let variant = string.slice(id, 19, 1)
  list.any(["8", "9", "a", "b"], fn(v) { v == variant })
  |> expect.to_be_true()
  // Lowercase hex only.
  string.lowercase(id) |> expect.to_equal(id)
}

pub fn uuid_v4_unique_test() {
  let ids = list.map(list.repeat(Nil, 100), fn(_) { ids.uuid_v4() })
  list.length(list.unique(ids)) |> expect.to_equal(100)
}

import gleam/list
import gleam/string
import startest/expect

import watershed/id

pub fn uuid_v4_format_test() -> Nil {
  let value = id.uuid_v4()
  string.length(value) |> expect.to_equal(36)
  let parts = string.split(value, "-")
  list.map(parts, string.length) |> expect.to_equal([8, 4, 4, 4, 12])
  // The version nibble is always 4.
  string.slice(value, 14, 1) |> expect.to_equal("4")
  // The variant nibble is 8, 9, a, or b (RFC 4122).
  let variant = string.slice(value, 19, 1)
  list.any(["8", "9", "a", "b"], fn(nibble) { nibble == variant })
  |> expect.to_be_true()
  // The identifier uses lowercase hex only.
  string.lowercase(value) |> expect.to_equal(value)
}

pub fn uuid_v4_unique_test() -> Nil {
  let values = list.map(list.repeat(Nil, 100), fn(_) { id.uuid_v4() })
  list.length(list.unique(values)) |> expect.to_equal(100)
}

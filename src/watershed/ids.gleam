//// Channel address generation. Addresses only need to be unique within a
//// document; UUID v4 makes collisions negligible without any coordination.
////
//// Target-split on purpose: the erlang side uses `gleam/crypto`, but pulling
//// that package into the JavaScript build would drag its FFI's static
//// `node:crypto` import into browser bundles, so the JS side binds directly
//// to `globalThis.crypto.randomUUID` instead.

@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/crypto
@target(erlang)
import gleam/int
@target(erlang)
import gleam/string

/// Generate a random RFC 4122 UUID v4 (lowercase, hyphenated).
pub fn uuid_v4() -> String {
  do_uuid_v4()
}

@target(erlang)
fn do_uuid_v4() -> String {
  let assert <<prefix:bytes-size(6), b6, b7, b8, suffix:bytes-size(7)>> =
    crypto.strong_random_bytes(16)
  let b6 = int.bitwise_or(int.bitwise_and(b6, 0x0f), 0x40)
  let b8 = int.bitwise_or(int.bitwise_and(b8, 0x3f), 0x80)
  bit_array.concat([prefix, <<b6, b7, b8>>, suffix])
  |> bit_array.base16_encode
  |> string.lowercase
  |> hyphenate
}

@target(javascript)
@external(javascript, "./ids_ffi.mjs", "uuidV4")
fn do_uuid_v4() -> String

@target(erlang)
fn hyphenate(hex: String) -> String {
  string.slice(hex, 0, 8)
  <> "-"
  <> string.slice(hex, 8, 4)
  <> "-"
  <> string.slice(hex, 12, 4)
  <> "-"
  <> string.slice(hex, 16, 4)
  <> "-"
  <> string.slice(hex, 20, 12)
}

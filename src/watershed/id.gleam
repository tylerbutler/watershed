//// Channel address generation. An address must be unique in one document only.
//// UUID v4 makes a collision very unlikely, and it needs no coordination.
////
//// This module is target-split on purpose. The Erlang side uses
//// `gleam/crypto`. The JavaScript build cannot use that package, because its
//// FFI has a static import of `node:crypto` that a browser bundle would then
//// include. The JavaScript side binds to `globalThis.crypto.randomUUID`
//// instead.

@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/crypto
@target(erlang)
import gleam/string

/// Generate a random RFC 4122 UUID v4. The result is lowercase and
/// hyphenated.
pub fn uuid_v4() -> String {
  do_uuid_v4()
}

@target(erlang)
fn do_uuid_v4() -> String {
  // Sixteen random bytes make 32 hexadecimal characters. Byte 6 holds the
  // version nibble, and byte 8 holds the variant nibble, so those two nibbles
  // are at index 12 and at index 16. The module writes the two nibbles into
  // the text, and it thus needs no fixed-size bit pattern and no assertion.
  let hexadecimal =
    crypto.strong_random_bytes(16)
    |> bit_array.base16_encode
    |> string.lowercase
  hyphenate(
    string.slice(hexadecimal, 0, 12)
    <> "4"
    <> string.slice(hexadecimal, 13, 3)
    <> variant_nibble(string.slice(hexadecimal, 16, 1))
    <> string.slice(hexadecimal, 17, 15),
  )
}

@target(erlang)
/// The variant nibble of an RFC 4122 UUID. The two highest bits must be `10`,
/// so the result is one of `8`, `9`, `a`, and `b`. The function keeps the two
/// lowest bits of the random nibble, so the result stays random.
fn variant_nibble(nibble: String) -> String {
  case nibble {
    "0" | "4" | "8" | "c" -> "8"
    "1" | "5" | "9" | "d" -> "9"
    "2" | "6" | "a" | "e" -> "a"
    _ -> "b"
  }
}

@target(javascript)
@external(javascript, "./id_ffi.mjs", "uuidV4")
fn do_uuid_v4() -> String

@target(erlang)
fn hyphenate(hexadecimal: String) -> String {
  string.slice(hexadecimal, 0, 8)
  <> "-"
  <> string.slice(hexadecimal, 8, 4)
  <> "-"
  <> string.slice(hexadecimal, 12, 4)
  <> "-"
  <> string.slice(hexadecimal, 16, 4)
  <> "-"
  <> string.slice(hexadecimal, 20, 12)
}

//// SHA-256 as lowercase hex. This module is target-split, so a browser bundle
//// can use it.
////
//// The Erlang side hashes with `gleam/crypto`. The JavaScript side cannot use
//// that package. Its FFI has a static import of `node:crypto`, which breaks
//// every browser bundle that includes it. `ids.gleam` documents the same
//// problem for random bytes.
////
//// Web Crypto is safe in a browser, but `crypto.subtle.digest` is
//// asynchronous. The pure CRDT core hashes synchronously in a total function.
//// Thus the JavaScript side binds a small synchronous SHA-256 in local FFI.
//// Neither target adds a dependency.
////
//// The two targets must give the same bytes. The digest is a wire value, and
//// peers on different targets compare it. Thus `sha256_test` checks known
//// vectors. It does not only compare the two implementations with each
//// other.

@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/crypto
@target(erlang)
import gleam/string

/// The SHA-256 of the UTF-8 bytes of a string, as 64 lowercase hex
/// characters.
pub fn hex(input: String) -> String {
  do_hex(input)
}

@target(erlang)
fn do_hex(input: String) -> String {
  crypto.hash(crypto.Sha256, <<input:utf8>>)
  |> bit_array.base16_encode
  |> string.lowercase
}

@target(javascript)
@external(javascript, "./sha256_ffi.mjs", "hex")
fn do_hex(input: String) -> String

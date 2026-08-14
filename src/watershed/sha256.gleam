//// SHA-256 as lowercase hex, target-split so a browser bundle can reach it.
////
//// The Erlang side hashes with `gleam/crypto`. The JavaScript side cannot:
//// that package's FFI statically imports `node:crypto`, which breaks every
//// browser bundle that pulls it in — the same trap `ids.gleam` documents for
//// random bytes. Web Crypto is the browser-safe alternative but
//// `crypto.subtle.digest` is asynchronous, and the pure CRDT core hashes
//// synchronously inside a total function, so the JS side binds a small
//// synchronous SHA-256 in local FFI instead. No new dependency either way.
////
//// Both targets must agree byte for byte: the digest is a wire value that
//// peers compare across targets, so `sha256_test` pins known vectors rather
//// than only comparing the two implementations to each other.

@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/crypto
@target(erlang)
import gleam/string

/// SHA-256 of a string's UTF-8 bytes, as 64 lowercase hex characters.
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

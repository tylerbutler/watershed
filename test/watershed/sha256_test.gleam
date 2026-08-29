import startest/expect

import watershed/sha256

/// FIPS 180-4 / RFC 6234 vectors, pinned so the Erlang and JavaScript
/// implementations are checked against the standard rather than against each
/// other. Both targets run this file.
pub fn known_vectors_hash_identically_on_every_target_test() -> Nil {
  sha256.hex("")
  |> expect.to_equal(
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  sha256.hex("abc")
  |> expect.to_equal(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
  |> expect.to_equal(
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  sha256.hex(
    "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
  )
  |> expect.to_equal(
    "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
  )
  Nil
}

/// The block-boundary cases a hand-written padding routine gets wrong: 55
/// bytes (length fits the first block), 56 bytes (padding forces a second),
/// and exactly 64 bytes (a whole extra block).
pub fn block_boundaries_hash_correctly_test() -> Nil {
  sha256.hex(repeat("a", 55))
  |> expect.to_equal(
    "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
  )
  sha256.hex(repeat("a", 56))
  |> expect.to_equal(
    "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
  )
  sha256.hex(repeat("a", 64))
  |> expect.to_equal(
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  )
  Nil
}

/// The input is hashed as UTF-8 bytes, not code units, so a multi-byte
/// string agrees across targets too.
pub fn multibyte_input_hashes_as_utf8_test() -> Nil {
  sha256.hex("héllo wörld 🌊")
  |> expect.to_equal(
    "4d089da39539c648089eacae3c223ac37b46b32ad4af5f19490f4da3dcdddcc6",
  )
  Nil
}

fn repeat(fragment: String, times: Int) -> String {
  case times <= 0 {
    True -> ""
    False -> fragment <> repeat(fragment, times - 1)
  }
}

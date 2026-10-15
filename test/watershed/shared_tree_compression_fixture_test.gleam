import gleam/option.{Some}
import startest/expect

import watershed/tree/compression_fixture

pub fn frame_reads_captured_bytes_test() {
  let assert Ok(#(_, _)) = compression_fixture.frame("utf8")
  Nil
}

pub fn shared_tree_compression_preserves_outer_marker_test() -> Nil {
  let assert Ok(messages) =
    compression_fixture.envelopes("default-compressed-singleton")
  let assert [first, ..] = messages
  first.compression |> expect.to_equal(Some("lz4"))
}

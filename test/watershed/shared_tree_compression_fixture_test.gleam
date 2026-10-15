import watershed/tree/compression_fixture

pub fn frame_reads_captured_bytes_test() {
  let assert Ok(#(_, _)) = compression_fixture.frame("utf8")
  Nil
}

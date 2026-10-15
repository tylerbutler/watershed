import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect

import watershed/tree/compression_fixture
import watershed/wire
import watershed/wire/lz4
import watershed/wire/socket

fn physical_message(compression: String) -> String {
  "{
    \"clientId\":\"writer-a\",
    \"sequenceNumber\":9,
    \"minimumSequenceNumber\":3,
    \"clientSequenceNumber\":4,
    \"referenceSequenceNumber\":7,
    \"type\":\"op\",
    \"contents\":{\"packedContents\":\"bytes\"},
    \"metadata\":{\"batch\":true},
    \"serverMetadata\":{\"order\":2},
    \"timestamp\":1700000000009,
    \"data\":\"physical-data\",
    \"compression\":" <> compression <> "
  }"
}

fn frame_from_hex(encoded: String) -> BitArray {
  let assert Ok(frame) = bit_array.base16_decode(encoded)
  frame
}

fn replace_byte(frame: BitArray, offset: Int, byte: Int) -> BitArray {
  let assert Ok(before) = bit_array.slice(frame, 0, offset)
  let assert Ok(after) =
    bit_array.slice(frame, offset + 1, bit_array.byte_size(frame) - offset - 1)
  bit_array.concat([before, <<byte>>, after])
}

pub fn sequenced_envelope_preserves_physical_fields_test() -> Nil {
  let assert Ok(envelope) =
    json.parse(
      physical_message("\"future-codec\""),
      socket.sequenced_envelope_decoder(),
    )
  envelope.compression |> expect.to_equal(Some("future-codec"))
  envelope.message.client_id |> expect.to_equal(Some("writer-a"))
  envelope.message.sequence_number |> expect.to_equal(9)
  envelope.message.minimum_sequence_number |> expect.to_equal(3)
  envelope.message.client_sequence_number |> expect.to_equal(4)
  envelope.message.reference_sequence_number |> expect.to_equal(7)
  envelope.message.message_type |> expect.to_equal("op")
  envelope.message.timestamp |> expect.to_equal(1_700_000_000_009)
  envelope.message.data |> expect.to_equal(Some("physical-data"))
  envelope.message.contents
  |> decode.run(decode.at(["packedContents"], decode.string))
  |> expect.to_equal(Ok("bytes"))
  let assert Some(metadata) = envelope.message.metadata
  metadata
  |> decode.run(decode.at(["batch"], decode.bool))
  |> expect.to_equal(Ok(True))
  let assert Some(server_metadata) = envelope.message.server_metadata
  server_metadata
  |> decode.run(decode.at(["order"], decode.int))
  |> expect.to_equal(Ok(2))
}

pub fn sequenced_envelope_rejects_non_string_compression_test() -> Nil {
  let _ =
    json.parse(physical_message("42"), socket.sequenced_envelope_decoder())
    |> expect.to_be_error()
  Nil
}

pub fn sequenced_envelope_rejects_null_compression_test() -> Nil {
  let _ =
    json.parse(physical_message("null"), socket.sequenced_envelope_decoder())
    |> expect.to_be_error()
  Nil
}

pub fn operation_envelopes_accept_wrapped_and_bare_lists_test() -> Nil {
  let message = physical_message("\"lz4\"")
  let assert Ok(wrapped) =
    json.parse(
      "{\"documentId\":\"doc-1\",\"op\":[" <> message <> "]}",
      socket.operation_envelopes_decoder(),
    )
  let assert Ok(bare) =
    json.parse("[" <> message <> "]", socket.operation_envelopes_decoder())

  wrapped.document_id |> expect.to_equal("doc-1")
  bare.document_id |> expect.to_equal("")
  let assert [wrapped_message] = wrapped.ops
  let assert [bare_message] = bare.ops
  wrapped_message.compression |> expect.to_equal(Some("lz4"))
  bare_message.compression |> expect.to_equal(Some("lz4"))
}

pub fn connection_envelope_owns_initial_messages_once_test() -> Nil {
  let payload = "{
      \"claims\":{\"documentId\":\"doc-1\",\"scopes\":[],\"tenantId\":\"default\",
        \"user\":{\"id\":\"user-1\"},\"iat\":0,\"exp\":0,\"ver\":\"1.0\"},
      \"clientId\":\"reader-1\",
      \"maxMessageSize\":16000,
      \"mode\":\"write\",
      \"serviceConfiguration\":{\"blockSize\":65536,\"maxMessageSize\":16000},
      \"initialMessages\":[" <> physical_message("\"lz4\"") <> "],
      \"version\":\"1.0\"
    }"
  let assert Ok(connection) =
    json.parse(payload, socket.connection_envelope_decoder())

  connection.handshake.initial_messages |> expect.to_equal([])
  let assert [initial] = connection.initial_messages
  initial.compression |> expect.to_equal(Some("lz4"))
}

pub fn strict_plain_decoder_and_envelope_decoder_agree_test() -> Nil {
  let plain =
    string.replace(physical_message("null"), ",\n    \"compression\":null", "")
  let assert Ok(message) =
    json.parse(plain, socket.sequenced_document_message_decoder())
  let assert Ok(envelope) =
    json.parse(plain, socket.sequenced_envelope_decoder())

  envelope |> expect.to_equal(wire.SequencedEnvelope(message, None))
}

pub fn strict_plain_decoders_still_refuse_compression_test() -> Nil {
  let _ =
    json.parse(
      physical_message("\"lz4\""),
      socket.sequenced_document_message_decoder(),
    )
    |> expect.to_be_error()
  Nil
}

pub fn shared_tree_compression_lz4_matches_upstream_test() -> Nil {
  let assert Ok(#(compressed, decoded)) =
    compression_fixture.frame("overlapping-match")
  lz4.decompress(compressed, 16 * 1024 * 1024)
  |> expect.to_equal(Ok(decoded))
}

pub fn shared_tree_compression_lz4_enforces_output_limit_test() -> Nil {
  let assert Ok(#(compressed, decoded)) =
    compression_fixture.frame("overlapping-match")
  lz4.decompress(compressed, bit_array.byte_size(decoded) - 1)
  |> expect.to_equal(Error(lz4.OutputLimitExceeded))
}

pub fn shared_tree_compression_lz4_accepts_exact_output_limit_test() -> Nil {
  let assert Ok(#(compressed, decoded)) =
    compression_fixture.frame("overlapping-match")
  lz4.decompress(compressed, bit_array.byte_size(decoded))
  |> expect.to_equal(Ok(decoded))
}

fn expect_captured_frame(id: String) -> Nil {
  let assert Ok(#(compressed, decoded)) = compression_fixture.frame(id)
  lz4.decompress(compressed, 16 * 1024 * 1024)
  |> expect.to_equal(Ok(decoded))
}

pub fn shared_tree_compression_lz4_matches_literal_frame_test() -> Nil {
  expect_captured_frame("literal-block")
}

pub fn shared_tree_compression_lz4_matches_multi_block_frame_test() -> Nil {
  expect_captured_frame("multi-block-match")
}

pub fn shared_tree_compression_lz4_matches_utf8_frame_test() -> Nil {
  expect_captured_frame("utf8")
}

pub fn shared_tree_compression_lz4_accepts_empty_frame_test() -> Nil {
  frame_from_hex("04224d1860408200000000")
  |> lz4.decompress(0)
  |> expect.to_equal(Ok(<<>>))
}

pub fn shared_tree_compression_lz4_validates_optional_fields_test() -> Nil {
  frame_from_hex(
    "04224d187c4003000000000000007403000080616263ff53d13200000000ff53d132",
  )
  |> lz4.decompress(3)
  |> expect.to_equal(Ok(<<"abc">>))
}

pub fn shared_tree_compression_lz4_supports_linked_block_history_test() -> Nil {
  frame_from_hex("04224d184040c00400008061626364040000000404000000000000")
  |> lz4.decompress(12)
  |> expect.to_equal(Ok(<<"abcdabcdabcd">>))
}

pub fn shared_tree_compression_lz4_resets_independent_block_history_test() -> Nil {
  frame_from_hex("04224d186040820400008061626364040000000404000000000000")
  |> lz4.decompress(12)
  |> expect.to_equal(Error(lz4.InvalidMatch))
}

pub fn shared_tree_compression_lz4_rejects_truncated_input_test() -> Nil {
  [
    <<>>,
    <<4, 34, 77, 24>>,
    frame_from_hex("04224d186040"),
    frame_from_hex("04224d186040820300008061"),
    frame_from_hex("04224d1860408201000000f000000000"),
  ]
  |> list.each(fn(frame) {
    let _ = lz4.decompress(frame, 1024) |> expect.to_be_error()
  })
}

pub fn shared_tree_compression_lz4_rejects_invalid_offsets_test() -> Nil {
  frame_from_hex("04224d18604082040000001061000000000000")
  |> lz4.decompress(1024)
  |> expect.to_equal(Error(lz4.InvalidMatch))
  frame_from_hex("04224d18604082040000001061020000000000")
  |> lz4.decompress(1024)
  |> expect.to_equal(Error(lz4.InvalidMatch))
}

pub fn shared_tree_compression_lz4_rejects_flags_and_dictionary_test() -> Nil {
  let empty = frame_from_hex("04224d1860408200000000")
  replace_byte(empty, 4, 0x42)
  |> lz4.decompress(1024)
  |> expect.to_equal(Error(lz4.InvalidFrame))
  replace_byte(empty, 5, 0x30)
  |> lz4.decompress(1024)
  |> expect.to_equal(Error(lz4.InvalidFrame))
  replace_byte(empty, 4, 0x61)
  |> lz4.decompress(1024)
  |> expect.to_equal(Error(lz4.UnsupportedFrameFeature("dictionary id")))
}

pub fn shared_tree_compression_lz4_rejects_bad_checksums_test() -> Nil {
  let checked =
    frame_from_hex(
      "04224d187c4003000000000000007403000080616263ff53d13200000000ff53d132",
    )
  replace_byte(checked, 14, 0)
  |> lz4.decompress(3)
  |> expect.to_equal(Error(lz4.InvalidChecksum))
  replace_byte(checked, 22, 0)
  |> lz4.decompress(3)
  |> expect.to_equal(Error(lz4.InvalidChecksum))
  replace_byte(checked, 30, 0)
  |> lz4.decompress(3)
  |> expect.to_equal(Error(lz4.InvalidChecksum))
}

pub fn shared_tree_compression_lz4_rejects_invalid_sizes_test() -> Nil {
  frame_from_hex("04224d1868400400000000000000cd0300008061626300000000")
  |> lz4.decompress(4)
  |> expect.to_equal(Error(lz4.InvalidFrame))
  frame_from_hex(
    "04224d187c4003000000000000007403000080616263ff53d13200000000ff53d132",
  )
  |> lz4.decompress(2)
  |> expect.to_equal(Error(lz4.OutputLimitExceeded))
  replace_byte(
    frame_from_hex(
      "04224d187c4003000000000000007403000080616263ff53d13200000000ff53d132",
    ),
    10,
    1,
  )
  |> lz4.decompress(16 * 1024 * 1024)
  |> expect.to_equal(Error(lz4.OutputLimitExceeded))
  frame_from_hex("04224d186040820000008000000000")
  |> lz4.decompress(0)
  |> expect.to_equal(Error(lz4.InvalidFrame))
}

pub fn shared_tree_compression_lz4_checks_limit_before_literal_slice_test() -> Nil {
  frame_from_hex("04224d1860408202000000f00a00000000")
  |> lz4.decompress(0)
  |> expect.to_equal(Error(lz4.OutputLimitExceeded))
}

pub fn shared_tree_compression_lz4_rejects_trailing_input_test() -> Nil {
  let empty = frame_from_hex("04224d1860408200000000")
  bit_array.append(empty, <<0>>)
  |> lz4.decompress(0)
  |> expect.to_equal(Error(lz4.InvalidFrame))
}

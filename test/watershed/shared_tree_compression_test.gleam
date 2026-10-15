import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import spillway/types.{SequencedDocumentMessage}
import startest/expect

import watershed/tree/compression_fixture
import watershed/wire
import watershed/wire/fluid_container.{
  ChannelOperation, ContainerMessage, DecodedBatch, IdAllocation, Route,
}
import watershed/wire/fluid_inbound
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

fn dynamic_json(raw: String) -> Dynamic {
  let assert Ok(value) = json.parse(raw, decode.dynamic)
  value
}

fn plain_operation(sequence: Int) -> wire.SequencedEnvelope {
  let contents =
    dynamic_json(
      "{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"root\",\"contents\":{\"plain\":true}}}}}",
    )
  wire.SequencedEnvelope(
    SequencedDocumentMessage(
      client_id: Some("plain-writer"),
      sequence_number: sequence,
      minimum_sequence_number: 0,
      client_sequence_number: sequence,
      reference_sequence_number: 7,
      message_type: "op",
      contents: contents,
      metadata: None,
      server_metadata: None,
      origin: None,
      traces: None,
      timestamp: 1_700_000_000_000 + sequence,
      data: None,
    ),
    None,
  )
}

fn chunk_from(
  source: wire.SequencedEnvelope,
  id: Int,
  total: Int,
  piece: String,
  final: Bool,
) -> wire.SequencedEnvelope {
  let original_metadata = case source.message.metadata {
    None -> ""
    Some(value) ->
      ",\"originalMetadata\":" <> json.to_string(wire.dynamic_to_json(value))
  }
  let final_fields = case final {
    True ->
      ",\"originalType\":\"component\",\"originalCompression\":\"lz4\""
      <> original_metadata
    False -> ""
  }
  let contents =
    dynamic_json(
      "{\"type\":\"chunkedOp\",\"contents\":{\"chunkId\":"
      <> string.inspect(id)
      <> ",\"totalChunks\":"
      <> string.inspect(total)
      <> ",\"contents\":"
      <> json.to_string(json.string(piece))
      <> final_fields
      <> "}}",
    )
  wire.SequencedEnvelope(
    SequencedDocumentMessage(
      ..source.message,
      sequence_number: id + 90,
      client_sequence_number: id + 80,
      timestamp: 1_700_000_000_090 + id,
      contents: contents,
      metadata: None,
    ),
    None,
  )
}

fn split_compressed(
  source: wire.SequencedEnvelope,
) -> #(wire.SequencedEnvelope, wire.SequencedEnvelope) {
  let packed = json.to_string(wire.dynamic_to_json(source.message.contents))
  let midpoint = string.length(packed) / 2
  #(
    chunk_from(source, 1, 2, string.slice(packed, 0, midpoint), False),
    chunk_from(
      source,
      2,
      2,
      string.slice(packed, midpoint, string.length(packed) - midpoint),
      True,
    ),
  )
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

pub fn shared_tree_compression_prefix_has_no_batch_test() -> Nil {
  let assert Ok([first, ..]) =
    compression_fixture.envelopes("default-chunked-group")
  let assert Ok(fluid_inbound.Step(state, fluid_inbound.Incomplete)) =
    fluid_inbound.step(fluid_inbound.new(fluid_inbound.default_limits()), first)
  fluid_inbound.partial_chunks(state)
  |> list.length
  |> expect.to_equal(1)
}

pub fn shared_tree_compression_completes_profile_batch_test() -> Nil {
  let assert Ok([compressed]) =
    compression_fixture.envelopes("id-allocation-before-tree-use")
  let assert Ok(fluid_inbound.Step(
    _,
    fluid_inbound.Complete(representative, batch),
  )) =
    fluid_inbound.step(
      fluid_inbound.new(fluid_inbound.default_limits()),
      compressed,
    )
  let assert DecodedBatch(
    True,
    metadata,
    [
      ContainerMessage(IdAllocation(_), 0, _),
      ContainerMessage(
        ChannelOperation(
          Route("compression-tree-store", "compression-tree"),
          payload,
        ),
        1,
        _,
      ),
    ],
  ) = batch

  representative.message_type |> expect.to_equal("op")
  representative.sequence_number |> expect.to_equal(1)
  let assert Some(metadata) = metadata
  let assert Some(source_metadata) = compressed.message.metadata
  json.to_string(metadata)
  |> expect.to_equal(json.to_string(wire.dynamic_to_json(source_metadata)))
  json.to_string(payload)
  |> string.contains("\"allocation-before-tree-use\"")
  |> expect.to_be_true()
  let assert Ok(reencoded) = fluid_container.encode_batch(batch)
  wire.json_semantically_equal(
    reencoded,
    wire.dynamic_to_json(representative.contents),
  )
  |> expect.to_be_true()
}

pub fn shared_tree_compression_reassembles_once_with_final_context_test() -> Nil {
  let assert Ok([compressed]) =
    compression_fixture.envelopes("id-allocation-before-tree-use")
  let #(first, final) = split_compressed(compressed)
  let state = fluid_inbound.new(fluid_inbound.default_limits())
  let assert Ok(fluid_inbound.Step(state, fluid_inbound.Incomplete)) =
    fluid_inbound.step(state, first)
  let assert Ok(fluid_inbound.Step(
    state,
    fluid_inbound.Complete(representative, batch),
  )) = fluid_inbound.step(state, final)
  let assert DecodedBatch(True, _, [_, _]) = batch

  fluid_inbound.partial_chunks(state) |> expect.to_equal([])
  representative.message_type |> expect.to_equal("op")
  representative.sequence_number |> expect.to_equal(92)
  representative.client_sequence_number |> expect.to_equal(82)
  representative.timestamp |> expect.to_equal(1_700_000_000_092)
  representative.metadata |> expect.to_equal(compressed.message.metadata)
  let assert Ok(reencoded) = fluid_container.encode_batch(batch)
  wire.json_semantically_equal(
    reencoded,
    wire.dynamic_to_json(representative.contents),
  )
  |> expect.to_be_true()
}

pub fn shared_tree_compression_keeps_interleaved_streams_and_plain_ops_test() -> Nil {
  let assert Ok([a, b, ..]) =
    compression_fixture.envelopes("interleaved-senders")
  let state = fluid_inbound.new(fluid_inbound.default_limits())
  let assert Ok(fluid_inbound.Step(state, fluid_inbound.Incomplete)) =
    fluid_inbound.step(state, a)
  let assert Ok(fluid_inbound.Step(state, fluid_inbound.Incomplete)) =
    fluid_inbound.step(state, b)
  fluid_inbound.partial_chunks(state) |> list.length |> expect.to_equal(2)

  let assert Ok(fluid_inbound.Step(same, fluid_inbound.Complete(_, _))) =
    fluid_inbound.step(state, plain_operation(50))
  fluid_inbound.partial_chunks(same) |> list.length |> expect.to_equal(2)

  let assert Some("sender-a") = a.message.client_id
  let cleaned = fluid_inbound.remove_client(same, "sender-a")
  fluid_inbound.partial_chunks(cleaned) |> list.length |> expect.to_equal(1)
}

pub fn shared_tree_compression_restore_preserves_prefix_shape_test() -> Nil {
  let limits = fluid_inbound.Limits(32, 32, 32, 2, 4)
  let assert Ok(state) =
    fluid_inbound.restore(limits, [
      #("sender-a", ["ab", ""]),
      #("sender-b", ["é"]),
    ])
  fluid_inbound.partial_chunks(state)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> expect.to_equal([
    #("sender-a", ["ab", ""]),
    #("sender-b", ["é"]),
  ])

  fluid_inbound.restore(limits, [#("sender-a", ["a"]), #("sender-a", ["b"])])
  |> expect.to_equal(
    Error(fluid_inbound.InvalidChunk("partial stream has a duplicate sender")),
  )
  let _ =
    fluid_inbound.restore(limits, [#("sender-a", [])])
    |> expect.to_be_error()
  Nil
}

pub fn shared_tree_compression_restore_enforces_exact_limits_test() -> Nil {
  let exact = fluid_inbound.Limits(4, 8, 4, 1, 2)
  let assert Ok(_) = fluid_inbound.restore(exact, [#("sender", ["é", "é"])])
  fluid_inbound.restore(exact, [#("sender", ["é", "éx"])])
  |> expect.to_equal(Error(fluid_inbound.LimitExceeded("packed payload")))
  fluid_inbound.restore(exact, [#("sender", ["a", "b", "c"])])
  |> expect.to_equal(Error(fluid_inbound.LimitExceeded("chunks per stream")))
  fluid_inbound.restore(exact, [
    #("sender-a", ["a"]),
    #("sender-b", ["b"]),
  ])
  |> expect.to_equal(Error(fluid_inbound.LimitExceeded("open chunk streams")))
}

pub fn shared_tree_compression_restored_prefix_learns_total_from_tail_test() -> Nil {
  let assert Ok([compressed]) =
    compression_fixture.envelopes("id-allocation-before-tree-use")
  let packed = json.to_string(wire.dynamic_to_json(compressed.message.contents))
  let first_length = string.length(packed) - 1
  let prefix = string.slice(packed, 0, first_length)
  let tail = string.slice(packed, first_length, 1)
  let assert Some(sender) = compressed.message.client_id
  let assert Ok(state) =
    fluid_inbound.restore(fluid_inbound.default_limits(), [#(sender, [prefix])])
  let final = chunk_from(compressed, 2, 2, tail, True)
  let assert Ok(fluid_inbound.Step(_, fluid_inbound.Complete(_, _))) =
    fluid_inbound.step(state, final)
  Nil
}

pub fn shared_tree_compression_accepts_empty_final_piece_test() -> Nil {
  let assert Ok([compressed]) =
    compression_fixture.envelopes("id-allocation-before-tree-use")
  let packed = json.to_string(wire.dynamic_to_json(compressed.message.contents))
  let first = chunk_from(compressed, 1, 2, packed, False)
  let final = chunk_from(compressed, 2, 2, "", True)
  let state = fluid_inbound.new(fluid_inbound.default_limits())
  let assert Ok(fluid_inbound.Step(state, fluid_inbound.Incomplete)) =
    fluid_inbound.step(state, first)
  let assert Ok(fluid_inbound.Step(_, fluid_inbound.Complete(_, _))) =
    fluid_inbound.step(state, final)
  Nil
}

pub fn shared_tree_compression_counts_utf8_bytes_at_limits_test() -> Nil {
  let limits = fluid_inbound.Limits(4, 32, 4, 1, 2)
  let source = plain_operation(1)
  let exact = chunk_from(source, 1, 2, "éé", False)
  let over = chunk_from(source, 1, 2, "ééx", False)
  let assert Ok(fluid_inbound.Step(_, fluid_inbound.Incomplete)) =
    fluid_inbound.step(fluid_inbound.new(limits), exact)
  fluid_inbound.step(fluid_inbound.new(limits), over)
  |> expect.to_equal(Error(fluid_inbound.LimitExceeded("packed payload")))
}

pub fn shared_tree_compression_rejects_changed_totals_and_original_types_test() -> Nil {
  let source = plain_operation(1)
  let first = chunk_from(source, 1, 3, "a", False)
  let changed = chunk_from(source, 2, 4, "b", False)
  let state = fluid_inbound.new(fluid_inbound.default_limits())
  let assert Ok(fluid_inbound.Step(state, fluid_inbound.Incomplete)) =
    fluid_inbound.step(state, first)
  fluid_inbound.step(state, changed)
  |> expect.to_equal(Error(fluid_inbound.InvalidChunk("chunk total changed")))

  let unsupported = chunk_from(source, 1, 1, "{}", True)
  let unsupported =
    wire.SequencedEnvelope(
      SequencedDocumentMessage(
        ..unsupported.message,
        contents: dynamic_json(
          "{\"type\":\"chunkedOp\",\"contents\":{\"chunkId\":1,\"totalChunks\":1,\"contents\":\"{}\",\"originalType\":\"join\",\"originalCompression\":\"lz4\"}}",
        ),
      ),
      None,
    )
  fluid_inbound.step(
    fluid_inbound.new(fluid_inbound.default_limits()),
    unsupported,
  )
  |> expect.to_equal(
    Error(fluid_inbound.InvalidChunk("unsupported original type: join")),
  )
}

pub fn shared_tree_compression_rejects_invalid_transitions_without_advancing_test() -> Nil {
  let assert Ok([first, second, ..]) =
    compression_fixture.envelopes("default-chunked-group")
  let initial = fluid_inbound.new(fluid_inbound.default_limits())
  let assert Ok(fluid_inbound.Step(state, fluid_inbound.Incomplete)) =
    fluid_inbound.step(initial, first)
  let before = fluid_inbound.partial_chunks(state)
  let _ = fluid_inbound.step(state, first) |> expect.to_be_error()
  let _ =
    fluid_inbound.step(
      state,
      wire.SequencedEnvelope(
        SequencedDocumentMessage(..second.message, client_id: None),
        None,
      ),
    )
    |> expect.to_be_error()
  fluid_inbound.partial_chunks(state) |> expect.to_equal(before)
}

pub fn shared_tree_compression_rejects_profile_exclusions_test() -> Nil {
  let cases = [
    "unmarked-packed-content",
    "unknown-algorithm",
    "multi-message-compressed-array",
    "missing-prefix",
    "malformed-frame",
    "nested-compression",
  ]
  cases
  |> list.each(fn(id) {
    let assert Ok([message, ..]) = compression_fixture.envelopes(id)
    let _ =
      fluid_inbound.step(
        fluid_inbound.new(fluid_inbound.default_limits()),
        message,
      )
      |> expect.to_be_error()
    Nil
  })

  let assert Ok([unknown]) = compression_fixture.envelopes("unknown-algorithm")
  fluid_inbound.step(fluid_inbound.new(fluid_inbound.default_limits()), unknown)
  |> expect.to_equal(Error(fluid_inbound.UnsupportedCompression("brotli")))

  let assert Ok([unmarked]) =
    compression_fixture.envelopes("unmarked-packed-content")
  fluid_inbound.step(
    fluid_inbound.new(fluid_inbound.default_limits()),
    unmarked,
  )
  |> expect.to_equal(
    Error(fluid_inbound.InvalidPackedPayload(
      "packed contents require a compression marker",
    )),
  )
}

pub fn shared_tree_compression_preserves_plain_and_empty_group_forms_test() -> Nil {
  let state = fluid_inbound.new(fluid_inbound.default_limits())
  let assert Ok(fluid_inbound.Step(
    _,
    fluid_inbound.Complete(
      _,
      DecodedBatch(
        False,
        None,
        [ContainerMessage(ChannelOperation(Route("A", "root"), _), 0, None)],
      ),
    ),
  )) = fluid_inbound.step(state, plain_operation(1))

  let assert Ok([empty]) = compression_fixture.envelopes("empty-group")
  let assert Ok(fluid_inbound.Step(
    _,
    fluid_inbound.Complete(_, DecodedBatch(True, _, [])),
  )) = fluid_inbound.step(state, empty)
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

pub fn shared_tree_compression_lz4_retains_maximum_distance_history_test() -> Nil {
  let prefix = bit_array.from_string(string.repeat("a", 65_536))
  let frame =
    bit_array.concat([
      frame_from_hex("04224d184040c000000180"),
      prefix,
      frame_from_hex("0900000004ffff507461696c2100000000"),
    ])
  let expected = bit_array.append(prefix, <<"aaaaaaaatail!">>)
  lz4.decompress(frame, 65_549)
  |> expect.to_equal(Ok(expected))
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

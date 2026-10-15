import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import spillway/types.{type SequencedDocumentMessage, SequencedDocumentMessage}
import startest/expect

import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/sha256
import watershed/tree/compression_fixture
import watershed/tree/runtime_fixture
import watershed/tree/types as tree_types
import watershed/wire
import watershed/wire/fluid_container.{
  type DecodedBatch, ChannelOperation, ContainerMessage, DecodedBatch,
  IdAllocation, Route,
}
import watershed/wire/fluid_document
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

fn compressed_operation(packed: String) -> wire.SequencedEnvelope {
  let source = plain_operation(1)
  wire.SequencedEnvelope(
    SequencedDocumentMessage(
      ..source.message,
      contents: dynamic_json(
        "{\"packedContents\":" <> json.to_string(json.string(packed)) <> "}",
      ),
    ),
    Some("lz4"),
  )
}

fn string_encode_contents(
  envelope: wire.SequencedEnvelope,
) -> wire.SequencedEnvelope {
  let raw = json.to_string(wire.dynamic_to_json(envelope.message.contents))
  wire.SequencedEnvelope(
    SequencedDocumentMessage(
      ..envelope.message,
      contents: dynamic_json(json.to_string(json.string(raw))),
    ),
    envelope.compression,
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

fn normalize_all(
  state: fluid_inbound.State,
  envelopes: List(wire.SequencedEnvelope),
  completions: List(#(SequencedDocumentMessage, DecodedBatch)),
) -> #(fluid_inbound.State, List(#(SequencedDocumentMessage, DecodedBatch))) {
  case envelopes {
    [] -> #(state, list.reverse(completions))
    [envelope, ..rest] -> {
      case fluid_inbound.step(state, envelope) {
        Error(error) -> {
          let reason = "normalization failed: " <> string.inspect(error)
          panic as reason
        }
        Ok(fluid_inbound.Step(next, payload)) ->
          case payload {
            fluid_inbound.Complete(representative, batch) ->
              normalize_all(next, rest, [
                #(representative, batch),
                ..completions
              ])
            _ -> normalize_all(next, rest, completions)
          }
      }
    }
  }
}

fn json_options_equal(
  left: option.Option(json.Json),
  right: option.Option(json.Json),
) -> Bool {
  case left, right {
    None, None -> True
    Some(left), Some(right) -> json.to_string(left) == json.to_string(right)
    _, _ -> False
  }
}

fn expect_captured_completion(
  id: String,
  envelopes: List(wire.SequencedEnvelope),
  initial: fluid_inbound.State,
) -> fluid_inbound.State {
  let compression_fixture.ExpectedCase(expected_grouped, expected) = case
    compression_fixture.expected(id)
  {
    Ok(value) -> value
    Error(error) -> panic as error
  }
  let #(state, completions) = normalize_all(initial, envelopes, [])
  let #(representative, DecodedBatch(actual_grouped, outer_metadata, actual)) = case
    completions
  {
    [completion] -> completion
    _ -> panic as "captured stream did not produce exactly one completion"
  }
  actual_grouped |> expect.to_equal(expected_grouped)
  list.length(actual) |> expect.to_equal(list.length(expected))
  list.zip(actual, expected)
  |> list.index_map(fn(pair, index) { #(pair, index) })
  |> list.each(fn(entry) {
    let #(
      #(
        ContainerMessage(kind, actual_index, actual_metadata),
        compression_fixture.ExpectedMessage(
          expected_contents,
          expected_metadata,
          expected_sequence,
          _,
          expected_reference,
          expected_timestamp,
        ),
      ),
      index,
    ) = entry
    actual_index |> expect.to_equal(index)
    let assert Ok(actual_contents) = fluid_container.encode(kind)
    wire.json_semantically_equal(actual_contents, expected_contents)
    |> expect.to_be_true()
    json_options_equal(actual_metadata, expected_metadata)
    |> expect.to_be_true()
    representative.sequence_number |> expect.to_equal(expected_sequence)
    representative.reference_sequence_number
    |> expect.to_equal(expected_reference)
    representative.timestamp |> expect.to_equal(expected_timestamp)
  })
  let assert [_, ..] = envelopes
  let assert Ok(final) = list.last(envelopes)
  representative.sequence_number
  |> expect.to_equal(final.message.sequence_number)
  representative.client_sequence_number
  |> expect.to_equal(final.message.client_sequence_number)
  representative.reference_sequence_number
  |> expect.to_equal(final.message.reference_sequence_number)
  representative.timestamp |> expect.to_equal(final.message.timestamp)
  case representative.metadata, outer_metadata {
    None, None -> Nil
    Some(representative_metadata), Some(batch_metadata) ->
      wire.dynamic_to_json(representative_metadata)
      |> json.to_string
      |> expect.to_equal(json.to_string(batch_metadata))
    _, _ -> panic as "representative and batch metadata differ"
  }
  let assert Ok(reencoded) =
    fluid_container.encode_batch(DecodedBatch(
      actual_grouped,
      outer_metadata,
      actual,
    ))
  wire.json_semantically_equal(
    reencoded,
    wire.dynamic_to_json(representative.contents),
  )
  |> expect.to_be_true()
  state
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

pub fn shared_tree_compression_partial_advances_only_position_test() -> Nil {
  let #(before, messages) = case
    compression_fixture.core_case("default-chunked-group")
  {
    Ok(value) -> value
    Error(error) -> panic as error
  }
  let assert [first, ..] = messages
  let assert Ok(#(after, ingested)) =
    runtime_core.handle_envelope(before, first)
  after.last_seen_sequence_number
  |> expect.to_equal(first.message.sequence_number)
  ingested.events |> expect.to_equal([])
  ingested.resolutions |> expect.to_equal([])
  after.in_flight |> expect.to_equal(before.in_flight)
}

pub fn shared_tree_compression_complete_applies_once_test() -> Nil {
  let #(before, envelopes) =
    unwrap_core_case(compression_fixture.core_case(
      "partial-summary-prefix-tail",
    ))
  let address = "compression-tree-chunked-store/compression-tree-chunked-tree"
  runtime_core.tree_read(before, address, ["label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("compression-baseline"))))
  let #(after, completions, revisions) =
    list.fold(envelopes, #(before, 0, []), fn(state, envelope) {
      let #(core, ingested) =
        unwrap_ingested(runtime_core.handle_envelope(state.0, envelope))
      case envelope.message.sequence_number < 204 {
        True ->
          runtime_core.tree_read(core, address, ["label"])
          |> expect.to_equal(
            Ok(Some(tree_types.StringValue("compression-baseline"))),
          )
        False -> Nil
      }
      #(
        core,
        state.1
          + case ingested.events {
          [] -> 0
          _ -> 1
        },
        list.append(
          state.2,
          list.filter_map(ingested.events, fn(event) {
            case event {
              #(_, channel.TreeCommitApplied(revision, _, False, False)) ->
                Ok(revision)
              _ -> Error(Nil)
            }
          }),
        ),
      )
    })
  after.last_seen_sequence_number |> expect.to_equal(204)
  fluid_inbound.partial_chunks(after.inbound) |> expect.to_equal([])
  completions |> expect.to_equal(1)
  runtime_core.tree_read(after, address, ["label"])
  |> result.map(fn(value) {
    let assert Some(tree_types.StringValue(label)) = value
    #(string.length(label), sha256.hex(label))
  })
  |> expect.to_equal(
    Ok(#(
      309_336,
      "e361b46a219d786ffb2882059aa7b1a2ca490b0dd1c32663817143e2ca58773b",
    )),
  )
  revisions
  |> list.map(fluid_ids.stable_id_to_string)
  |> expect.to_equal([
    "20000000-0000-4000-8000-000000000004",
    "20000000-0000-4000-8000-000000000005",
  ])
  let assert Ok(final) = list.last(envelopes)
  runtime_core.handle_envelope(after, final)
  |> expect.to_equal(Ok(#(after, runtime_core.Ingested([], [], [], None, []))))
}

pub fn shared_tree_compression_summary_restores_partial_stream_test() -> Nil {
  let #(before, envelopes) =
    unwrap_core_case(compression_fixture.core_case(
      "partial-summary-prefix-tail",
    ))
  let assert [first, ..rest] = envelopes
  let assert Ok(#(partial, _)) = runtime_core.handle_envelope(before, first)
  let assert Ok(summary) = runtime_core.capture_summary(partial)
  let assert Ok(encoded) = fluid_document.encode(summary)
  let assert Ok(session) =
    fluid_ids.session_id("a0000000-0000-4000-8000-00000000000a")
  let assert Ok(restored) =
    fluid_document.decode(
      encoded,
      None,
      session,
      fluid_document.view_id(summary),
    )
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "reloaded",
        [],
        partial.last_seen_sequence_number,
      ),
      restored,
    )
  let final =
    list.fold(rest, core, fn(core, envelope) {
      let #(core, _) =
        unwrap_ingested(runtime_core.handle_envelope(core, envelope))
      core
    })
  final.last_seen_sequence_number |> expect.to_equal(204)
  fluid_inbound.partial_chunks(final.inbound) |> expect.to_equal([])
}

pub fn shared_tree_compression_out_of_order_final_chunk_applies_once_test() -> Nil {
  let #(before, envelopes) =
    unwrap_core_case(compression_fixture.core_case(
      "partial-summary-prefix-tail",
    ))
  let assert [first, second, third, fourth, final] = envelopes
  let #(buffered, first_delivery) =
    unwrap_ingested(runtime_core.handle_envelope(before, final))
  buffered.last_seen_sequence_number
  |> expect.to_equal(before.last_seen_sequence_number)
  first_delivery.events |> expect.to_equal([])
  let #(deduplicated, _) =
    unwrap_ingested(runtime_core.handle_envelope(buffered, final))
  deduplicated |> expect.to_equal(buffered)
  let #(completed, completions) =
    list.fold(
      [first, second, third, fourth],
      #(deduplicated, 0),
      fn(state, envelope) {
        let #(core, ingested) =
          unwrap_ingested(runtime_core.handle_envelope(state.0, envelope))
        #(
          core,
          state.1
            + case ingested.events {
            [] -> 0
            _ -> 1
          },
        )
      },
    )
  completed.last_seen_sequence_number |> expect.to_equal(204)
  fluid_inbound.partial_chunks(completed.inbound) |> expect.to_equal([])
  completions |> expect.to_equal(1)
}

fn unwrap_ingested(
  result: Result(
    #(runtime_core.Core, runtime_core.Ingested),
    runtime_core.CoreError,
  ),
) -> #(runtime_core.Core, runtime_core.Ingested) {
  case result {
    Ok(value) -> value
    Error(error) -> panic as string.inspect(error)
  }
}

fn unwrap_core_case(
  result: Result(#(runtime_core.Core, List(wire.SequencedEnvelope)), String),
) -> #(runtime_core.Core, List(wire.SequencedEnvelope)) {
  case result {
    Ok(value) -> value
    Error(error) -> panic as error
  }
}

pub fn shared_tree_compression_completes_real_default_chunk_stream_test() -> Nil {
  let assert Ok(envelopes) =
    compression_fixture.envelopes("default-chunked-group")
  let final_state =
    expect_captured_completion(
      "default-chunked-group",
      envelopes,
      fluid_inbound.new(fluid_inbound.default_limits()),
    )
  fluid_inbound.partial_chunks(final_state) |> expect.to_equal([])

  let assert Ok(final) = list.last(envelopes)
  let assert Ok(original_metadata) =
    decode.run(
      final.message.contents,
      decode.at(["contents", "originalMetadata"], wire.json_value_decoder()),
    )
  let assert Ok(compression_fixture.ExpectedCase(_, [_, _, _, _])) =
    compression_fixture.expected("default-chunked-group")
  original_metadata
  |> json.to_string
  |> expect.to_equal("{\"groupedOpCount\":4}")
}

pub fn shared_tree_compression_completes_real_default_unchunked_streams_test() -> Nil {
  ["default-compressed-singleton", "default-compressed-group"]
  |> list.each(fn(id) {
    let assert Ok(envelopes) = compression_fixture.envelopes(id)
    let final_state =
      expect_captured_completion(
        id,
        envelopes,
        fluid_inbound.new(fluid_inbound.default_limits()),
      )
    fluid_inbound.partial_chunks(final_state) |> expect.to_equal([])
  })
}

pub fn shared_tree_compression_accepts_service_string_encoded_packed_contents_test() -> Nil {
  let id = "default-compressed-singleton"
  let assert Ok([envelope]) = compression_fixture.envelopes(id)
  let final_state =
    expect_captured_completion(
      id,
      [string_encode_contents(envelope)],
      fluid_inbound.new(fluid_inbound.default_limits()),
    )
  fluid_inbound.partial_chunks(final_state) |> expect.to_equal([])
}

pub fn shared_tree_compression_accepts_service_string_encoded_chunks_test() -> Nil {
  let id = "default-chunked-group"
  let assert Ok(envelopes) = compression_fixture.envelopes(id)
  let final_state =
    expect_captured_completion(
      id,
      list.map(envelopes, string_encode_contents),
      fluid_inbound.new(fluid_inbound.default_limits()),
    )
  fluid_inbound.partial_chunks(final_state) |> expect.to_equal([])
}

pub fn shared_tree_compression_resumes_real_upstream_prefix_and_tail_test() -> Nil {
  let id = "partial-summary-prefix-tail"
  let assert Ok(envelopes) = compression_fixture.envelopes(id)
  let #(summary, prefix_length, tail_length) = case
    compression_fixture.summary_prefix(id)
  {
    Ok(value) -> value
    Error(error) -> panic as error
  }
  let #(prefix, tail) = list.split(envelopes, prefix_length)
  list.length(tail) |> expect.to_equal(tail_length)

  let #(prefix_state, prefix_completions) =
    normalize_all(fluid_inbound.new(fluid_inbound.default_limits()), prefix, [])
  prefix_completions |> expect.to_equal([])
  fluid_inbound.partial_chunks(prefix_state) |> expect.to_equal(summary)

  let assert Ok(restored) =
    fluid_inbound.restore(fluid_inbound.default_limits(), summary)
  let final_state = expect_captured_completion(id, tail, restored)
  fluid_inbound.partial_chunks(final_state) |> expect.to_equal([])
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
          Route("compression-tree-store", "compression-tree-tree"),
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
  |> string.contains("\"compression-baseline\"")
  |> expect.to_be_true()
  let assert Ok(reencoded) = fluid_container.encode_batch(batch)
  wire.json_semantically_equal(
    reencoded,
    wire.dynamic_to_json(representative.contents),
  )
  |> expect.to_be_true()
}

pub fn shared_tree_compression_synthetic_reassembly_keeps_final_context_test() -> Nil {
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

pub fn shared_tree_compression_synthetic_restored_prefix_learns_total_test() -> Nil {
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

pub fn shared_tree_compression_rejects_grouped_runtime_envelope_compression_test() -> Nil {
  [
    // grouped outer
    "BCJNGEBw35UAAADxG1t7InR5cGUiOiJncm91cGVkQmF0Y2giLCJjb21wcmVzc2lvbiI6Imx6NBQA1G50ZW50cyI6W3siY28NAAVDAAA0AFlvbmVudCwAUHsiYWRkSwBLIjoiQRoAA3wAJm9wGAAoIjoxADxyb29OAIx2YWx1ZSI6MaQA8AthcHBsaWNhdGlvbi1kYXRhIn19fX19fV19XQAAAAA=",
    // grouped item
    "BCJNGEBw35UAAAD5KFt7InR5cGUiOiJncm91cGVkQmF0Y2giLCJjb250ZW50cyI6W3siY29tcHJlc3Npb24iOiJsejQhAAVDAAAnAFtvbmVudB8AMGFkZD4ASyI6IkEaAAN8ACZvcBgARiI6eyIxADxyb29OAIB2YWx1ZSI6MaQACJcA8AthcHBsaWNhdGlvbi1kYXRhIn19fX19fV19XQAAAAA=",
    // runtime message
    "BCJNGEBw35QAAAD3Flt7InR5cGUiOiJncm91cGVkQmF0Y2giLCJjb250ZW50cyI6W3sNAAUvAJljb21wb25lbnQsANt7ImFkZHJlc3MiOiJBGgADaAAmb3AYACgiOjEAPHJvb04AgHZhbHVlIjoxkAAgbXBZAPwMaW9uIjoiYXBwbGljYXRpb24tZGF0YSJ9fX19JQCQbHo0In19XX1dAAAAAA==",
    // component datastore wrapper
    "BCJNGEBw35QAAAD3Flt7InR5cGUiOiJncm91cGVkQmF0Y2giLCJjb250ZW50cyI6W3sNAAUvAJljb21wb25lbnQsANt7ImFkZHJlc3MiOiJBGgADaAAmb3AYACgiOjEAPHJvb04AgHZhbHVlIjoxkAAgbXBZAPwLaW9uIjoiYXBwbGljYXRpb24tZGF0YSJ9fX0kAKBsejQifX19XX1dAAAAAA==",
    // datastore channel wrapper
    "BCJNGEBw35QAAAD3Flt7InR5cGUiOiJncm91cGVkQmF0Y2giLCJjb250ZW50cyI6W3sNAAUvAJljb21wb25lbnQsANt7ImFkZHJlc3MiOiJBGgADaAAmb3AYACgiOjEAPHJvb04AgHZhbHVlIjoxkAAgbXBZAPwKaW9uIjoiYXBwbGljYXRpb24tZGF0YSJ9fSMAsGx6NCJ9fX19XX1dAAAAAA==",
    // channel operation wrapper
    "BCJNGEBw35QAAAD3Flt7InR5cGUiOiJncm91cGVkQmF0Y2giLCJjb250ZW50cyI6W3sNAAUvAJljb21wb25lbnQsANt7ImFkZHJlc3MiOiJBGgADaAAmb3AYACgiOjEAPHJvb04AgHZhbHVlIjoxkAAgbXBZAPwJaW9uIjoiYXBwbGljYXRpb24tZGF0YSJ9IgDAbHo0In19fX19XX1dAAAAAA==",
  ]
  |> list.each(fn(packed) {
    fluid_inbound.step(
      fluid_inbound.new(fluid_inbound.default_limits()),
      compressed_operation(packed),
    )
    |> expect.to_equal(
      Error(fluid_inbound.InvalidPackedPayload(
        "nested compression is not supported",
      )),
    )
  })
}

pub fn shared_tree_compression_rejects_malformed_grouped_runtime_marker_test() -> Nil {
  fluid_inbound.step(
    fluid_inbound.new(fluid_inbound.default_limits()),
    compressed_operation(
      "BCJNGEBw35MAAAD3Flt7InR5cGUiOiJncm91cGVkQmF0Y2giLCJjb250ZW50cyI6W3sNAAUvAJljb21wb25lbnQsANt7ImFkZHJlc3MiOiJBGgADaAAmb3AYACgiOjEAPHJvb04AgHZhbHVlIjoxkAAgbXBZAPsMaW9uIjoiYXBwbGljYXRpb24tZGF0YSJ9fX19JQCAMTIzfX1dfV0AAAAA",
    ),
  )
  |> expect.to_equal(
    Error(fluid_inbound.InvalidPackedPayload(
      "invalid nested compression marker",
    )),
  )
}

pub fn shared_tree_compression_keeps_dds_compression_fields_opaque_test() -> Nil {
  let assert Ok(fluid_inbound.Step(
    _,
    fluid_inbound.Complete(
      _,
      DecodedBatch(
        True,
        None,
        [ContainerMessage(ChannelOperation(Route("A", "root"), payload), 0, _)],
      ),
    ),
  )) =
    fluid_inbound.step(
      fluid_inbound.new(fluid_inbound.default_limits()),
      compressed_operation(
        "BCJNGEBw340AAAD3Flt7InR5cGUiOiJncm91cGVkQmF0Y2giLCJjb250ZW50cyI6W3sNAAUvAJljb21wb25lbnQsANt7ImFkZHJlc3MiOiJBGgADaAAmb3AYACgiOjEAPHJvb04AgHZhbHVlIjoxkAAgbXBZAPARaW9uIjoiYXBwbGljYXRpb24tZGF0YSJ9fX19fX1dfV0AAAAA",
      ),
    )
  json.to_string(payload)
  |> string.contains("\"compression\":\"application-data\"")
  |> expect.to_be_true()
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

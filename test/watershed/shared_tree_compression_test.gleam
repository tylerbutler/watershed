import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import startest/expect

import watershed/wire
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

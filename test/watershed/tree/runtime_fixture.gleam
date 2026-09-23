import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import signet/types as token
import spillway/message
import spillway/types.{type SequencedDocumentMessage}
import watershed/fluid_ids
import watershed/tree/codec
import watershed/tree/codec/summary
import watershed/wire
import watershed/wire/fluid_summary
import watershed/wire/socket

pub type RuntimeInput {
  RuntimeInput(
    document: fluid_summary.SummaryEntry,
    tree: summary.TreeSummaryData,
    map_header: Json,
    compressor: fluid_ids.Compressor,
    sequence_number: Int,
    minimum_sequence_number: Int,
    prefix: List(SequencedDocumentMessage),
    operations: List(SequencedDocumentMessage),
  )
}

pub fn connected(
  client_id: String,
  messages: List(SequencedDocumentMessage),
  checkpoint: Int,
) -> message.ConnectedMessage {
  message.ConnectedMessage(
    claims: token.TokenClaims(
      document_id: "tree",
      scopes: [token.DocRead, token.DocWrite],
      tenant_id: "default",
      user: token.User(id: "test", properties: dict.new()),
      issued_at: 0,
      expiration: 0,
      version: "1.0",
      jti: None,
    ),
    client_id: client_id,
    existing: True,
    max_message_size: 16_000,
    mode: types.WriteMode,
    service_configuration: types.ServiceConfiguration(
      block_size: 65_536,
      max_message_size: 16_000,
      noop_time_frequency: None,
      noop_count_frequency: None,
    ),
    initial_clients: [],
    initial_messages: messages,
    initial_signals: [],
    supported_versions: ["^0.1.0"],
    supported_features: dict.new(),
    version: "^0.1.0",
    timestamp: None,
    checkpoint_sequence_number: Some(checkpoint),
    epoch: None,
    relay_service_agent: None,
    summary_context: None,
  )
}

pub fn read(
  input: Json,
  session: fluid_ids.SessionId,
) -> Result(RuntimeInput, String) {
  use decoder_input <- result.try(field(input, "decoderInput"))
  use snapshot <- result.try(field(decoder_input, "initialSnapshot"))
  use encoding <- result.try(read_field(snapshot, "blobEncoding", decode.string))
  use Nil <- result.try(case encoding {
    "base64" -> Ok(Nil)
    _ -> Error("runtime fixture snapshot is not base64")
  })
  use tree_json <- result.try(field(snapshot, "tree"))
  use encoded_blobs <- result.try(read_field(
    snapshot,
    "blobs",
    decode.dict(decode.string, decode.string),
  ))
  use blobs <- result.try(
    encoded_blobs
    |> dict.to_list
    |> list.try_map(fn(entry) {
      use bytes <- result.try(
        bit_array.base64_decode(entry.1)
        |> result.replace_error("runtime fixture has invalid blob bytes"),
      )
      Ok(#(entry.0, bytes))
    }),
  )
  use document <- result.try(
    fluid_summary.from_snapshot(tree_json, dict.from_list(blobs))
    |> result.map_error(string.inspect),
  )
  use attributes <- result.try(blob(document, "/.protocol/attributes"))
  use sequence_number <- result.try(read_field(
    attributes,
    "sequenceNumber",
    decode.int,
  ))
  use minimum_sequence_number <- result.try(read_field(
    attributes,
    "minimumSequenceNumber",
    decode.int,
  ))
  use Nil <- result.try(
    case
      minimum_sequence_number >= 0 && minimum_sequence_number <= sequence_number
    {
      True -> Ok(Nil)
      False -> Error("runtime fixture has invalid snapshot sequence numbers")
    },
  )
  use serialized <- result.try(blob(document, "/.idCompressor"))
  use compressor <- result.try(
    fluid_ids.deserialize(serialized, session)
    |> result.map_error(string.inspect),
  )
  use tree_entry <- result.try(
    fluid_summary.resolve(
      fluid_summary.SummaryHandle(
        "/.channels/A/.channels/_C",
        fluid_summary.TreeHandle,
      ),
      Some(document),
    )
    |> result.map_error(string.inspect),
  )
  use tree_entries <- result.try(case tree_entry {
    fluid_summary.SummaryTree(entries) -> Ok(entries)
    _ -> Error("runtime fixture tree channel is not a summary tree")
  })
  use tree <- result.try(
    summary.decode(
      fluid_summary.SummaryTree(
        list.filter(tree_entries, fn(entry) { entry.0 != ".attributes" }),
      ),
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  use Nil <- result.try(case tree.history {
    summary.EditManagerSummary([], []) -> Ok(Nil)
    _ -> Error("runtime fixture requires an initial empty tree history")
  })
  use map_header <- result.try(blob(
    document,
    "/.channels/A/.channels/root/header",
  ))
  use prefix <- result.try(read_field(
    decoder_input,
    "deliveryPrefix",
    decode.list(socket.sequenced_document_message_decoder()),
  ))
  use operations <- result.try(
    json.parse(json.to_string(decoder_input), {
      decode.one_of(
        decode.at(
          ["groupedWireMessages"],
          decode.list(socket.sequenced_document_message_decoder()),
        ),
        or: [
          decode.at(
            ["bootstrapMessages"],
            decode.list(socket.sequenced_document_message_decoder()),
          ),
        ],
      )
    })
    |> result.map_error(fn(error) {
      "runtime fixture operations: " <> string.inspect(error)
    }),
  )
  use Nil <- result.try(case operations {
    [] -> Error("runtime fixture has no operations")
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    list.try_fold(
      list.append(prefix, operations),
      #(sequence_number, minimum_sequence_number),
      fn(previous, message) {
        case
          message.sequence_number == previous.0 + 1
          && message.minimum_sequence_number >= previous.1
          && message.minimum_sequence_number <= message.sequence_number
          && message.reference_sequence_number <= previous.0
        {
          True ->
            Ok(#(message.sequence_number, message.minimum_sequence_number))
          False -> Error("runtime fixture has an invalid delivery prefix")
        }
      },
    ),
  )
  Ok(RuntimeInput(
    document:,
    tree:,
    map_header:,
    compressor:,
    sequence_number:,
    minimum_sequence_number:,
    prefix:,
    operations:,
  ))
}

fn blob(
  document: fluid_summary.SummaryEntry,
  path: String,
) -> Result(Json, String) {
  use entry <- result.try(
    fluid_summary.resolve(
      fluid_summary.SummaryHandle(path, fluid_summary.BlobHandle),
      Some(document),
    )
    |> result.map_error(string.inspect),
  )
  use bytes <- result.try(case entry {
    fluid_summary.SummaryBlob(bytes) -> Ok(bytes)
    _ -> Error("runtime fixture entry is not a blob: " <> path)
  })
  use raw <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error("runtime fixture blob is not UTF-8: " <> path),
  )
  json.parse(raw, wire.json_value_decoder())
  |> result.map_error(fn(error) {
    "runtime fixture blob is not JSON: "
    <> path
    <> ": "
    <> string.inspect(error)
  })
}

fn field(input: Json, name: String) -> Result(Json, String) {
  read_field(input, name, wire.json_value_decoder())
}

fn read_field(
  input: Json,
  name: String,
  decoder: decode.Decoder(value),
) -> Result(value, String) {
  json.parse(json.to_string(input), decode.at([name], decoder))
  |> result.map_error(fn(error) {
    "runtime fixture field " <> name <> ": " <> string.inspect(error)
  })
}

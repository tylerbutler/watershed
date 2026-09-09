//// Codecs for sequenced summary publication responses.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/result

pub type SummaryResponse {
  Ack(proposal_sequence_number: Int, version_id: String)
  Nack(proposal_sequence_number: Int, reason: String)
}

pub fn decode_message(
  message_type: String,
  contents: Dynamic,
) -> Result(SummaryResponse, Nil) {
  case message_type {
    "summaryAck" ->
      decode.run(contents, ack_decoder()) |> result.replace_error(Nil)
    "summaryNack" ->
      decode.run(contents, nack_decoder()) |> result.replace_error(Nil)
    _ -> Error(Nil)
  }
}

fn ack_decoder() -> decode.Decoder(SummaryResponse) {
  use version_id <- decode.field("handle", decode.string)
  use proposal_sequence_number <- decode.subfield(
    ["summaryProposal", "summarySequenceNumber"],
    decode.int,
  )
  decode.success(Ack(proposal_sequence_number, version_id))
}

fn nack_decoder() -> decode.Decoder(SummaryResponse) {
  use proposal_sequence_number <- decode.subfield(
    ["summaryProposal", "summarySequenceNumber"],
    decode.int,
  )
  use reason <- decode.field("message", decode.string)
  decode.success(Nack(proposal_sequence_number, reason))
}

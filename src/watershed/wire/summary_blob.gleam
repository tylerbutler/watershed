//// The summary snapshot blob (v2): the format `summarize` uploads to levee's
//// git storage and fresh connections bootstrap from. A *storage* format, not
//// a wire format — versioned independently so loaders reject snapshots they
//// don't understand rather than misread them.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}

import watershed/wire

/// Current on-disk format version. Loaders reject anything they don't
/// recognise rather than misread a foreign snapshot.
pub const version = 2

pub type SummaryBlob {
  SummaryBlob(sequence_number: Int, channels: List(ChannelSnapshot))
}

pub type ChannelSnapshot {
  ChannelSnapshot(
    address: String,
    channel_type: String,
    entries: List(#(String, Json)),
  )
}

pub fn encode_channels(
  sequence_number: Int,
  channels: List(#(String, List(#(String, Json)))),
) -> Json {
  json.object([
    #("watershedSummaryVersion", json.int(version)),
    #("sequenceNumber", json.int(sequence_number)),
    #(
      "channels",
      json.array(channels, fn(channel) {
        let #(address, entries) = channel
        json.object([
          #("address", json.string(address)),
          #("type", json.string(wire.channel_type_map)),
          #("entries", wire.encode_entries(entries)),
        ])
      }),
    ),
  ])
}

/// Decode a blob produced by `encode_channels`. Reject unknown versions and
/// unknown channel types.
pub fn decode(raw: String) -> Result(SummaryBlob, json.DecodeError) {
  json.parse(raw, decoder())
}

pub fn decoder() -> Decoder(SummaryBlob) {
  use blob_version <- decode.field("watershedSummaryVersion", decode.int)
  case blob_version == version {
    True -> {
      use sequence_number <- decode.field("sequenceNumber", decode.int)
      use channels <- decode.field(
        "channels",
        decode.list(channel_snapshot_decoder()),
      )
      decode.success(SummaryBlob(
        sequence_number: sequence_number,
        channels: channels,
      ))
    }
    False ->
      decode.failure(
        SummaryBlob(sequence_number: 0, channels: []),
        "watershedSummaryVersion " <> int.to_string(version),
      )
  }
}

fn channel_snapshot_decoder() -> Decoder(ChannelSnapshot) {
  use address <- decode.field("address", decode.string)
  use channel_type <- decode.field("type", decode.string)
  // Only recognize known channel types.
  case channel_type == wire.channel_type_map {
    True -> {
      use entries <- decode.field("entries", decode.list(wire.entry_decoder()))
      decode.success(ChannelSnapshot(
        address: address,
        channel_type: channel_type,
        entries: entries,
      ))
    }
    False ->
      decode.failure(
        ChannelSnapshot(address: "", channel_type: "", entries: []),
        "ChannelType",
      )
  }
}

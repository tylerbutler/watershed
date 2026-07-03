//// The summary snapshot blob (v3): the format `summarize` uploads to levee's
//// git storage and fresh connections bootstrap from. A *storage* format, not
//// a wire format — versioned independently so loaders reject snapshots they
//// don't understand rather than misread them.
////
//// v3 carries one `{address, type, data}` object per channel, `data` being
//// the channel-type-dependent snapshot payload (see `channel.Snapshot`).
//// There is no v2 loader: formats are cut clean while nothing external
//// consumes them, and stored documents are reset rather than migrated.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}

import watershed/channel

/// Current on-disk format version. Loaders reject anything they don't
/// recognise rather than misread a foreign snapshot.
pub const version = 3

pub type SummaryBlob {
  SummaryBlob(sequence_number: Int, channels: List(ChannelSnapshot))
}

pub type ChannelSnapshot {
  ChannelSnapshot(address: String, snapshot: channel.Snapshot)
}

pub fn encode_channels(
  sequence_number: Int,
  channels: List(#(String, channel.Snapshot)),
) -> Json {
  json.object([
    #("watershedSummaryVersion", json.int(version)),
    #("sequenceNumber", json.int(sequence_number)),
    #(
      "channels",
      json.array(channels, fn(entry) {
        let #(address, snapshot) = entry
        json.object([
          #("address", json.string(address)),
          #(
            "type",
            json.string(channel.type_to_string(channel.snapshot_type(snapshot))),
          ),
          #("data", channel.encode_snapshot(snapshot)),
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
  case channel.type_from_string(channel_type) {
    Ok(channel_type) -> {
      use snapshot <- decode.field(
        "data",
        channel.snapshot_decoder(channel_type),
      )
      decode.success(ChannelSnapshot(address: address, snapshot: snapshot))
    }
    Error(_) ->
      decode.failure(
        ChannelSnapshot(address: "", snapshot: channel.MapSnapshot([])),
        "ChannelType",
      )
  }
}

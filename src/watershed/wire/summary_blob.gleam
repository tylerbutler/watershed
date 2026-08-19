//// The summary snapshot blob (v4): the format `summarize` uploads to floodgate's
//// git storage and fresh connections bootstrap from. A *storage* format, not
//// a wire format — versioned independently so loaders reject snapshots they
//// don't understand rather than misread them.
////
//// A blob carries one `{address, type, data}` object per channel, `data` being
//// the channel-type-dependent snapshot payload (see `channel.Snapshot`), plus
//// the connected roster at the captured sequence number.
////
//// v4 adds `members`. Membership is checkpoint state exactly like a kernel
//// snapshot, because the consensus kernels read it: a `PactMap` freezes a
//// signoff list from the roster and `TaskManager` judges a volunteer's
//// authorship against it. Without it, a client bootstrapping from a checkpoint
//// replays every later op against an empty room — which does not report an error,
//// it silently settles pacts the room is still deciding.
////
//// There is no v3 loader, and there was no v2 one: formats are cut clean while
//// nothing external consumes them, and stored documents are reset rather than
//// migrated.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}

import watershed/channel

/// Current on-disk format version. Loaders reject anything they don't
/// recognise rather than misread a foreign snapshot.
pub const version = 4

pub type SummaryBlob {
  SummaryBlob(
    sequence_number: Int,
    /// The connected roster at `sequence_number`, as the kernel-side integer
    /// ids consensus kernels tie-break on — the same derivation
    /// `client_id.to_int` performs, so it matches what a replayed `join`
    /// produces.
    members: List(Int),
    channels: List(ChannelSnapshot),
  )
}

pub type ChannelSnapshot {
  ChannelSnapshot(address: String, snapshot: channel.Snapshot)
}

pub fn encode_channels(
  sequence_number: Int,
  members: List(Int),
  channels: List(#(String, channel.Snapshot)),
) -> Json {
  json.object([
    #("watershedSummaryVersion", json.int(version)),
    #("sequenceNumber", json.int(sequence_number)),
    #("members", json.array(members, json.int)),
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
      use members <- decode.field("members", decode.list(decode.int))
      use channels <- decode.field(
        "channels",
        decode.list(channel_snapshot_decoder()),
      )
      decode.success(SummaryBlob(
        sequence_number: sequence_number,
        members: members,
        channels: channels,
      ))
    }
    False ->
      decode.failure(
        SummaryBlob(sequence_number: 0, members: [], channels: []),
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

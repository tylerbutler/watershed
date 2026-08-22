//// The summary snapshot blob, version 4. `summarize` uploads this format to
//// the git storage of floodgate, and a new connection starts from it. This is
//// a storage format, not a wire format. It has its own version, so a loader
//// can refuse a snapshot that it does not understand instead of reading that
//// snapshot incorrectly.
////
//// A blob carries one `{address, type, data}` object for each channel. The
//// `data` field is the snapshot payload of that channel type. See
//// `channel.Snapshot`. The blob also carries the connected roster at the
//// captured sequence number.
////
//// Version 4 adds `members`. Membership is checkpoint state, the same as a
//// kernel snapshot, because the consensus kernels read it. A `PactMap` freezes
//// a signoff list from the roster, and `TaskManager` checks the authorship of
//// a volunteer against the roster. Without `members`, a client that starts
//// from a checkpoint replays every later op against an empty room. That
//// condition reports no error. It settles pacts that the room is still
//// deciding.
////
//// There is no version 3 loader, and there was no version 2 loader. A format
//// is removed completely while nothing outside the project reads it. Stored
//// documents are reset, not migrated.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}

import watershed/channel

/// The current on-disk format version. A loader refuses a version that it does
/// not recognize. It does not read a foreign snapshot incorrectly.
pub const version = 4

pub type SummaryBlob {
  SummaryBlob(
    sequence_number: Int,
    /// The connected roster at `sequence_number`. Each member is the
    /// kernel-side integer id that the consensus kernels use to tie-break.
    /// `client_id.to_int` performs the same derivation, so this list agrees
    /// with the result of a replayed `join`.
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

/// Decode a blob that `encode_channels` produced. Refuse an unknown version
/// and an unknown channel type.
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

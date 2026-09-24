//// Snapshot inspection of a complete document summary.
////
//// This projection has no compressor, routing, or protocol metadata. Use the
//// full document summary to restore a connection.

import watershed/channel

pub type SummaryBlob {
  SummaryBlob(
    sequence_number: Int,
    members: List(Int),
    channels: List(ChannelSnapshot),
  )
}

pub type ChannelSnapshot {
  ChannelSnapshot(address: String, snapshot: channel.Snapshot)
}

//// Target-independent types and eligibility guards for the CRDT p2p runtime.

import watershed/channel.{type ChannelInit, type ChannelType}
import watershed/or_map_kernel.{type OrMapMode}
import watershed/schema

pub type P2pError {
  UnsupportedChannel(ChannelType)
  RootMismatch(expected: ChannelType, received: ChannelType)
  /// A handle or an imported snapshot entry named an address that is
  /// registered under a different channel type. This error is not
  /// `RootMismatch`, which reports the root of the document only.
  ChannelTypeMismatch(
    address: String,
    expected: ChannelType,
    received: ChannelType,
  )
  /// The caller applied an operation to a document whose connection is
  /// closed. Reads and mutations both refuse. The document can no longer
  /// broadcast, so no result from it would be correct.
  DocumentClosed
  CompatibilityMismatch(expected: String, received: String)
  ProtocolMismatch(expected: Int, received: Int)
  RoomMismatch
  RoomFull(limit: Int)
  SignalingFailed(String)
  SequencerUnavailable(String)
  SequencerUnsupported
  PeerConnectionFailed(peer_id: String, detail: String)
  InvalidEnvelope(peer_id: String, detail: String)
  SnapshotTooLarge(bytes: Int, limit: Int)
  ReplicaCollision(replica_id: String)
}

/// A channel initializer whose phantom type preserves the resulting handle kind.
pub opaque type CrdtKind(kind) {
  CrdtKind(init: ChannelInit)
}

pub fn pn_counter_root() -> CrdtKind(schema.PnCounterChannel) {
  CrdtKind(channel.InitPnCounter)
}

pub fn or_map_root(mode: OrMapMode) -> CrdtKind(schema.OrMapChannel) {
  CrdtKind(channel.InitOrMap(mode))
}

pub fn or_set_root() -> CrdtKind(schema.OrSetChannel) {
  CrdtKind(channel.InitOrSet)
}

pub fn g_set_root() -> CrdtKind(schema.GSetChannel) {
  CrdtKind(channel.InitGSet)
}

pub fn two_p_set_root() -> CrdtKind(schema.TwoPSetChannel) {
  CrdtKind(channel.InitTwoPSet)
}

pub fn sequence_root() -> CrdtKind(schema.SequenceChannel) {
  CrdtKind(channel.InitSequence)
}

pub fn text_root() -> CrdtKind(schema.TextChannel) {
  CrdtKind(channel.InitText)
}

pub fn kind_init(kind: CrdtKind(kind)) -> ChannelInit {
  kind.init
}

pub fn kind_type(kind: CrdtKind(kind)) -> ChannelType {
  channel.init_type(kind.init)
}

/// Refuse a channel type whose kernel cannot run without a sequencer.
pub fn validate(channel_type: ChannelType) -> Result(ChannelType, P2pError) {
  case channel.supports_p2p(channel_type) {
    True -> Ok(channel_type)
    False -> Error(UnsupportedChannel(channel_type))
  }
}

/// `validate` for a channel initializer. It returns the initializer, so a
/// creation site can continue to thread it.
pub fn validate_create(init: ChannelInit) -> Result(ChannelInit, P2pError) {
  case validate(channel.init_type(init)) {
    Ok(_) -> Ok(init)
    Error(error) -> Error(error)
  }
}

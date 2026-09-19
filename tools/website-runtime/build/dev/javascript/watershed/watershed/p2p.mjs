/// <reference types="./p2p.d.mts" />
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";
import * as $channel from "../watershed/channel.mjs";
import * as $or_map_kernel from "../watershed/or_map_kernel.mjs";
import * as $schema from "../watershed/schema.mjs";

export class UnsupportedChannel extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const P2pError$UnsupportedChannel = ($0) => new UnsupportedChannel($0);
export const P2pError$isUnsupportedChannel = (value) =>
  value instanceof UnsupportedChannel;
export const P2pError$UnsupportedChannel$0 = (value) => value[0];

export class RootMismatch extends $CustomType {
  constructor(expected, received) {
    super();
    this.expected = expected;
    this.received = received;
  }
}
export const P2pError$RootMismatch = (expected, received) =>
  new RootMismatch(expected, received);
export const P2pError$isRootMismatch = (value) => value instanceof RootMismatch;
export const P2pError$RootMismatch$expected = (value) => value.expected;
export const P2pError$RootMismatch$0 = (value) => value.expected;
export const P2pError$RootMismatch$received = (value) => value.received;
export const P2pError$RootMismatch$1 = (value) => value.received;

/**
 * A handle or an imported snapshot entry named an address that is
 * registered under a different channel type. This error is not
 * `RootMismatch`, which reports the root of the document only.
 */
export class ChannelTypeMismatch extends $CustomType {
  constructor(address, expected, received) {
    super();
    this.address = address;
    this.expected = expected;
    this.received = received;
  }
}
export const P2pError$ChannelTypeMismatch = (address, expected, received) =>
  new ChannelTypeMismatch(address, expected, received);
export const P2pError$isChannelTypeMismatch = (value) =>
  value instanceof ChannelTypeMismatch;
export const P2pError$ChannelTypeMismatch$address = (value) => value.address;
export const P2pError$ChannelTypeMismatch$0 = (value) => value.address;
export const P2pError$ChannelTypeMismatch$expected = (value) => value.expected;
export const P2pError$ChannelTypeMismatch$1 = (value) => value.expected;
export const P2pError$ChannelTypeMismatch$received = (value) => value.received;
export const P2pError$ChannelTypeMismatch$2 = (value) => value.received;

/**
 * The caller applied an operation to a document whose connection is
 * closed. Reads and mutations both refuse. The document can no longer
 * broadcast, so no result from it would be correct.
 */
export class DocumentClosed extends $CustomType {}
export const P2pError$DocumentClosed$const = new DocumentClosed();
export const P2pError$DocumentClosed = () => P2pError$DocumentClosed$const;
export const P2pError$isDocumentClosed = (value) =>
  value instanceof DocumentClosed;

export class CompatibilityMismatch extends $CustomType {
  constructor(expected, received) {
    super();
    this.expected = expected;
    this.received = received;
  }
}
export const P2pError$CompatibilityMismatch = (expected, received) =>
  new CompatibilityMismatch(expected, received);
export const P2pError$isCompatibilityMismatch = (value) =>
  value instanceof CompatibilityMismatch;
export const P2pError$CompatibilityMismatch$expected = (value) =>
  value.expected;
export const P2pError$CompatibilityMismatch$0 = (value) => value.expected;
export const P2pError$CompatibilityMismatch$received = (value) =>
  value.received;
export const P2pError$CompatibilityMismatch$1 = (value) => value.received;

export class ProtocolMismatch extends $CustomType {
  constructor(expected, received) {
    super();
    this.expected = expected;
    this.received = received;
  }
}
export const P2pError$ProtocolMismatch = (expected, received) =>
  new ProtocolMismatch(expected, received);
export const P2pError$isProtocolMismatch = (value) =>
  value instanceof ProtocolMismatch;
export const P2pError$ProtocolMismatch$expected = (value) => value.expected;
export const P2pError$ProtocolMismatch$0 = (value) => value.expected;
export const P2pError$ProtocolMismatch$received = (value) => value.received;
export const P2pError$ProtocolMismatch$1 = (value) => value.received;

export class RoomMismatch extends $CustomType {}
export const P2pError$RoomMismatch$const = new RoomMismatch();
export const P2pError$RoomMismatch = () => P2pError$RoomMismatch$const;
export const P2pError$isRoomMismatch = (value) => value instanceof RoomMismatch;

export class RoomFull extends $CustomType {
  constructor(limit) {
    super();
    this.limit = limit;
  }
}
export const P2pError$RoomFull = (limit) => new RoomFull(limit);
export const P2pError$isRoomFull = (value) => value instanceof RoomFull;
export const P2pError$RoomFull$limit = (value) => value.limit;
export const P2pError$RoomFull$0 = (value) => value.limit;

export class SignalingFailed extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const P2pError$SignalingFailed = ($0) => new SignalingFailed($0);
export const P2pError$isSignalingFailed = (value) =>
  value instanceof SignalingFailed;
export const P2pError$SignalingFailed$0 = (value) => value[0];

export class SequencerUnavailable extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const P2pError$SequencerUnavailable = ($0) =>
  new SequencerUnavailable($0);
export const P2pError$isSequencerUnavailable = (value) =>
  value instanceof SequencerUnavailable;
export const P2pError$SequencerUnavailable$0 = (value) => value[0];

export class SequencerUnsupported extends $CustomType {}
export const P2pError$SequencerUnsupported$const = new SequencerUnsupported();
export const P2pError$SequencerUnsupported = () =>
  P2pError$SequencerUnsupported$const;
export const P2pError$isSequencerUnsupported = (value) =>
  value instanceof SequencerUnsupported;

export class PeerConnectionFailed extends $CustomType {
  constructor(peer_id, detail) {
    super();
    this.peer_id = peer_id;
    this.detail = detail;
  }
}
export const P2pError$PeerConnectionFailed = (peer_id, detail) =>
  new PeerConnectionFailed(peer_id, detail);
export const P2pError$isPeerConnectionFailed = (value) =>
  value instanceof PeerConnectionFailed;
export const P2pError$PeerConnectionFailed$peer_id = (value) => value.peer_id;
export const P2pError$PeerConnectionFailed$0 = (value) => value.peer_id;
export const P2pError$PeerConnectionFailed$detail = (value) => value.detail;
export const P2pError$PeerConnectionFailed$1 = (value) => value.detail;

export class InvalidEnvelope extends $CustomType {
  constructor(peer_id, detail) {
    super();
    this.peer_id = peer_id;
    this.detail = detail;
  }
}
export const P2pError$InvalidEnvelope = (peer_id, detail) =>
  new InvalidEnvelope(peer_id, detail);
export const P2pError$isInvalidEnvelope = (value) =>
  value instanceof InvalidEnvelope;
export const P2pError$InvalidEnvelope$peer_id = (value) => value.peer_id;
export const P2pError$InvalidEnvelope$0 = (value) => value.peer_id;
export const P2pError$InvalidEnvelope$detail = (value) => value.detail;
export const P2pError$InvalidEnvelope$1 = (value) => value.detail;

export class SnapshotTooLarge extends $CustomType {
  constructor(bytes, limit) {
    super();
    this.bytes = bytes;
    this.limit = limit;
  }
}
export const P2pError$SnapshotTooLarge = (bytes, limit) =>
  new SnapshotTooLarge(bytes, limit);
export const P2pError$isSnapshotTooLarge = (value) =>
  value instanceof SnapshotTooLarge;
export const P2pError$SnapshotTooLarge$bytes = (value) => value.bytes;
export const P2pError$SnapshotTooLarge$0 = (value) => value.bytes;
export const P2pError$SnapshotTooLarge$limit = (value) => value.limit;
export const P2pError$SnapshotTooLarge$1 = (value) => value.limit;

export class ReplicaCollision extends $CustomType {
  constructor(replica_id) {
    super();
    this.replica_id = replica_id;
  }
}
export const P2pError$ReplicaCollision = (replica_id) =>
  new ReplicaCollision(replica_id);
export const P2pError$isReplicaCollision = (value) =>
  value instanceof ReplicaCollision;
export const P2pError$ReplicaCollision$replica_id = (value) => value.replica_id;
export const P2pError$ReplicaCollision$0 = (value) => value.replica_id;

class CrdtKind extends $CustomType {
  constructor(init) {
    super();
    this.init = init;
  }
}

export function pn_counter_root() {
  return new CrdtKind($channel.ChannelInit$InitPnCounter$const);
}

/**
 * The root kind for a peer-to-peer grow-only counter document.
 */
export function g_counter_root() {
  return new CrdtKind($channel.ChannelInit$InitGCounter$const);
}

export function mv_register_root() {
  return new CrdtKind($channel.ChannelInit$InitMvRegister$const);
}

/**
 * The root kind for a peer-to-peer last-writer-wins register document.
 */
export function lww_register_root() {
  return new CrdtKind($channel.ChannelInit$InitLwwRegister$const);
}

/**
 * The root kind for a string-valued peer-to-peer LWW map.
 */
export function lww_map_root() {
  return new CrdtKind($channel.ChannelInit$InitLwwMap$const);
}

export function or_map_root(mode) {
  return new CrdtKind(new $channel.InitOrMap(mode));
}

export function or_set_root() {
  return new CrdtKind($channel.ChannelInit$InitOrSet$const);
}

export function g_set_root() {
  return new CrdtKind($channel.ChannelInit$InitGSet$const);
}

export function two_p_set_root() {
  return new CrdtKind($channel.ChannelInit$InitTwoPSet$const);
}

export function sequence_root() {
  return new CrdtKind($channel.ChannelInit$InitSequence$const);
}

export function text_root() {
  return new CrdtKind($channel.ChannelInit$InitText$const);
}

export function kind_init(kind) {
  return kind.init;
}

export function kind_type(kind) {
  return $channel.init_type(kind.init);
}

/**
 * Refuse a channel type whose kernel cannot run without a sequencer.
 */
export function validate(channel_type) {
  let $ = $channel.supports_p2p(channel_type);
  if ($) {
    return new Ok(channel_type);
  } else {
    return new Error(new UnsupportedChannel(channel_type));
  }
}

/**
 * `validate` for a channel initializer. It returns the initializer, so a
 * creation site can continue to thread it.
 */
export function validate_create(init) {
  let $ = validate($channel.init_type(init));
  if ($ instanceof Ok) {
    return new Ok(init);
  } else {
    return $;
  }
}

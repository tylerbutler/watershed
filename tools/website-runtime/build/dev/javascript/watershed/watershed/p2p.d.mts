import type * as _ from "../gleam.d.mts";
import type * as $channel from "../watershed/channel.d.mts";
import type * as $or_map_kernel from "../watershed/or_map_kernel.d.mts";
import type * as $schema from "../watershed/schema.d.mts";

export class UnsupportedChannel extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $channel.ChannelType$);
  /** @deprecated */
  0: $channel.ChannelType$;
}
export function P2pError$UnsupportedChannel(
  $0: $channel.ChannelType$,
): P2pError$;
export function P2pError$isUnsupportedChannel(value: any): value is P2pError$;
export function P2pError$UnsupportedChannel$0(value: P2pError$): $channel.ChannelType$;

export class RootMismatch extends _.CustomType {
  /** @deprecated */
  constructor(expected: $channel.ChannelType$, received: $channel.ChannelType$);
  /** @deprecated */
  expected: $channel.ChannelType$;
  /** @deprecated */
  received: $channel.ChannelType$;
}
export function P2pError$RootMismatch(
  expected: $channel.ChannelType$,
  received: $channel.ChannelType$,
): P2pError$;
export function P2pError$isRootMismatch(value: any): value is P2pError$;
export function P2pError$RootMismatch$0(value: P2pError$): $channel.ChannelType$;
export function P2pError$RootMismatch$expected(
  value: P2pError$,
): $channel.ChannelType$;
export function P2pError$RootMismatch$1(value: P2pError$): $channel.ChannelType$;
export function P2pError$RootMismatch$received(
  value: P2pError$,
): $channel.ChannelType$;

export class ChannelTypeMismatch extends _.CustomType {
  /** @deprecated */
  constructor(
    address: string,
    expected: $channel.ChannelType$,
    received: $channel.ChannelType$
  );
  /** @deprecated */
  address: string;
  /** @deprecated */
  expected: $channel.ChannelType$;
  /** @deprecated */
  received: $channel.ChannelType$;
}
export function P2pError$ChannelTypeMismatch(
  address: string,
  expected: $channel.ChannelType$,
  received: $channel.ChannelType$,
): P2pError$;
export function P2pError$isChannelTypeMismatch(value: any): value is P2pError$;
export function P2pError$ChannelTypeMismatch$0(value: P2pError$): string;
export function P2pError$ChannelTypeMismatch$address(value: P2pError$): string;
export function P2pError$ChannelTypeMismatch$1(value: P2pError$): $channel.ChannelType$;
export function P2pError$ChannelTypeMismatch$expected(
  value: P2pError$,
): $channel.ChannelType$;
export function P2pError$ChannelTypeMismatch$2(value: P2pError$): $channel.ChannelType$;
export function P2pError$ChannelTypeMismatch$received(
  value: P2pError$,
): $channel.ChannelType$;

export class DocumentClosed extends _.CustomType {}
export function P2pError$DocumentClosed(): P2pError$;
export function P2pError$isDocumentClosed(value: any): value is P2pError$;

export class CompatibilityMismatch extends _.CustomType {
  /** @deprecated */
  constructor(expected: string, received: string);
  /** @deprecated */
  expected: string;
  /** @deprecated */
  received: string;
}
export function P2pError$CompatibilityMismatch(
  expected: string,
  received: string,
): P2pError$;
export function P2pError$isCompatibilityMismatch(
  value: any,
): value is P2pError$;
export function P2pError$CompatibilityMismatch$0(value: P2pError$): string;
export function P2pError$CompatibilityMismatch$expected(value: P2pError$): string;
export function P2pError$CompatibilityMismatch$1(
  value: P2pError$,
): string;
export function P2pError$CompatibilityMismatch$received(value: P2pError$): string;

export class ProtocolMismatch extends _.CustomType {
  /** @deprecated */
  constructor(expected: number, received: number);
  /** @deprecated */
  expected: number;
  /** @deprecated */
  received: number;
}
export function P2pError$ProtocolMismatch(
  expected: number,
  received: number,
): P2pError$;
export function P2pError$isProtocolMismatch(value: any): value is P2pError$;
export function P2pError$ProtocolMismatch$0(value: P2pError$): number;
export function P2pError$ProtocolMismatch$expected(value: P2pError$): number;
export function P2pError$ProtocolMismatch$1(value: P2pError$): number;
export function P2pError$ProtocolMismatch$received(value: P2pError$): number;

export class RoomMismatch extends _.CustomType {}
export function P2pError$RoomMismatch(): P2pError$;
export function P2pError$isRoomMismatch(value: any): value is P2pError$;

export class RoomFull extends _.CustomType {
  /** @deprecated */
  constructor(limit: number);
  /** @deprecated */
  limit: number;
}
export function P2pError$RoomFull(limit: number): P2pError$;
export function P2pError$isRoomFull(value: any): value is P2pError$;
export function P2pError$RoomFull$0(value: P2pError$): number;
export function P2pError$RoomFull$limit(value: P2pError$): number;

export class SignalingFailed extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function P2pError$SignalingFailed($0: string): P2pError$;
export function P2pError$isSignalingFailed(value: any): value is P2pError$;
export function P2pError$SignalingFailed$0(value: P2pError$): string;

export class SequencerUnavailable extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function P2pError$SequencerUnavailable($0: string): P2pError$;
export function P2pError$isSequencerUnavailable(value: any): value is P2pError$;
export function P2pError$SequencerUnavailable$0(value: P2pError$): string;

export class SequencerUnsupported extends _.CustomType {}
export function P2pError$SequencerUnsupported(): P2pError$;
export function P2pError$isSequencerUnsupported(value: any): value is P2pError$;

export class PeerConnectionFailed extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string, detail: string);
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  detail: string;
}
export function P2pError$PeerConnectionFailed(
  peer_id: string,
  detail: string,
): P2pError$;
export function P2pError$isPeerConnectionFailed(value: any): value is P2pError$;
export function P2pError$PeerConnectionFailed$0(value: P2pError$): string;
export function P2pError$PeerConnectionFailed$peer_id(value: P2pError$): string;
export function P2pError$PeerConnectionFailed$1(value: P2pError$): string;
export function P2pError$PeerConnectionFailed$detail(value: P2pError$): string;

export class InvalidEnvelope extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string, detail: string);
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  detail: string;
}
export function P2pError$InvalidEnvelope(
  peer_id: string,
  detail: string,
): P2pError$;
export function P2pError$isInvalidEnvelope(value: any): value is P2pError$;
export function P2pError$InvalidEnvelope$0(value: P2pError$): string;
export function P2pError$InvalidEnvelope$peer_id(value: P2pError$): string;
export function P2pError$InvalidEnvelope$1(value: P2pError$): string;
export function P2pError$InvalidEnvelope$detail(value: P2pError$): string;

export class SnapshotTooLarge extends _.CustomType {
  /** @deprecated */
  constructor(bytes: number, limit: number);
  /** @deprecated */
  bytes: number;
  /** @deprecated */
  limit: number;
}
export function P2pError$SnapshotTooLarge(
  bytes: number,
  limit: number,
): P2pError$;
export function P2pError$isSnapshotTooLarge(value: any): value is P2pError$;
export function P2pError$SnapshotTooLarge$0(value: P2pError$): number;
export function P2pError$SnapshotTooLarge$bytes(value: P2pError$): number;
export function P2pError$SnapshotTooLarge$1(value: P2pError$): number;
export function P2pError$SnapshotTooLarge$limit(value: P2pError$): number;

export class ReplicaCollision extends _.CustomType {
  /** @deprecated */
  constructor(replica_id: string);
  /** @deprecated */
  replica_id: string;
}
export function P2pError$ReplicaCollision(replica_id: string): P2pError$;
export function P2pError$isReplicaCollision(value: any): value is P2pError$;
export function P2pError$ReplicaCollision$0(value: P2pError$): string;
export function P2pError$ReplicaCollision$replica_id(value: P2pError$): string;

export type P2pError$ = UnsupportedChannel | RootMismatch | ChannelTypeMismatch | DocumentClosed | CompatibilityMismatch | ProtocolMismatch | RoomMismatch | RoomFull | SignalingFailed | SequencerUnavailable | SequencerUnsupported | PeerConnectionFailed | InvalidEnvelope | SnapshotTooLarge | ReplicaCollision;

declare class CrdtKind extends _.CustomType {
  /** @deprecated */
  constructor(init: $channel.ChannelInit$);
  /** @deprecated */
  init: $channel.ChannelInit$;
}

export type CrdtKind$<BQMG> = CrdtKind;

export function pn_counter_root(): CrdtKind$<$schema.PnCounterChannel$>;

export function g_counter_root(): CrdtKind$<$schema.GCounterChannel$>;

export function mv_register_root(): CrdtKind$<$schema.MvRegisterChannel$>;

export function lww_register_root(): CrdtKind$<$schema.LwwRegisterChannel$>;

export function lww_map_root(): CrdtKind$<$schema.LwwMapChannel$>;

export function or_map_root(mode: $or_map_kernel.OrMapMode$): CrdtKind$<
  $schema.OrMapChannel$
>;

export function or_set_root(): CrdtKind$<$schema.OrSetChannel$>;

export function g_set_root(): CrdtKind$<$schema.GSetChannel$>;

export function two_p_set_root(): CrdtKind$<$schema.TwoPSetChannel$>;

export function sequence_root(): CrdtKind$<$schema.SequenceChannel$>;

export function text_root(): CrdtKind$<$schema.TextChannel$>;

export function kind_init(kind: CrdtKind$<any>): $channel.ChannelInit$;

export function kind_type(kind: CrdtKind$<any>): $channel.ChannelType$;

export function validate(channel_type: $channel.ChannelType$): _.Result<
  $channel.ChannelType$,
  P2pError$
>;

export function validate_create(init: $channel.ChannelInit$): _.Result<
  $channel.ChannelInit$,
  P2pError$
>;

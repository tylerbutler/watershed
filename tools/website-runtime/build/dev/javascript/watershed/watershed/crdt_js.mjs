/// <reference types="./crdt_js.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.mjs";
import { Bias$Before$const, Bias$After$const } from "../../lattice_sequence/lattice_sequence/sequence.mjs";
import {
  Ok,
  Error,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $channel from "../watershed/channel.mjs";
import * as $crdt_core from "../watershed/crdt_core.mjs";
import * as $crdt_sequencer_js from "../watershed/crdt_sequencer_js.mjs";
import * as $crdt_wire from "../watershed/crdt_wire.mjs";
import * as $g_counter_kernel from "../watershed/g_counter_kernel.mjs";
import * as $g_set_kernel from "../watershed/g_set_kernel.mjs";
import * as $id from "../watershed/id.mjs";
import * as $lww_map_kernel from "../watershed/lww_map_kernel.mjs";
import * as $lww_register_kernel from "../watershed/lww_register_kernel.mjs";
import * as $mv_register_kernel from "../watershed/mv_register_kernel.mjs";
import * as $or_map_kernel from "../watershed/or_map_kernel.mjs";
import * as $or_set_kernel from "../watershed/or_set_kernel.mjs";
import * as $p2p from "../watershed/p2p.mjs";
import * as $p2p_transport_js from "../watershed/p2p_transport_js.mjs";
import * as $pn_counter_kernel from "../watershed/pn_counter_kernel.mjs";
import * as $schema from "../watershed/schema.mjs";
import * as $sequence_kernel from "../watershed/sequence_kernel.mjs";
import * as $text_kernel from "../watershed/text_kernel.mjs";
import * as $timer_js from "../watershed/timer_js.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import * as $two_p_set_kernel from "../watershed/two_p_set_kernel.mjs";
import * as $wire from "../watershed/wire.mjs";
import { guard, sameDocument as same_document } from "./crdt_js_ffi.mjs";

class Config extends $CustomType {
  constructor(room, label, compatibility, root, signaling, ice_servers, policy, sequencer, scheduler, anti_entropy_interval_milliseconds) {
    super();
    this.room = room;
    this.label = label;
    this.compatibility = compatibility;
    this.root = root;
    this.signaling = signaling;
    this.ice_servers = ice_servers;
    this.policy = policy;
    this.sequencer = sequencer;
    this.scheduler = scheduler;
    this.anti_entropy_interval_milliseconds = anti_entropy_interval_milliseconds;
  }
}

/**
 * Both transports, and each one on its own schedule. The mesh starts by
 * itself, and the relay starts by itself. The readiness waits for the mesh
 * only. The relay becomes the durable delta path when it proves that it
 * works, and not before.
 */
export class Auto extends $CustomType {}
export const TransportPolicy$Auto$const = new Auto();
export const TransportPolicy$Auto = () => TransportPolicy$Auto$const;
export const TransportPolicy$isAuto = (value) => value instanceof Auto;

/**
 * The relay only. There is no signaling, no `RTCPeerConnection`, and no
 * data channel. The readiness waits for the relay, under a bounded
 * deadline, because there is no other path to be ready on.
 */
export class SequencedOnly extends $CustomType {}
export const TransportPolicy$SequencedOnly$const = new SequencedOnly();
export const TransportPolicy$SequencedOnly = () =>
  TransportPolicy$SequencedOnly$const;
export const TransportPolicy$isSequencedOnly = (value) =>
  value instanceof SequencedOnly;

/**
 * The mesh only. The module opens no relay, it schedules no reconnect, and
 * it ignores a sequencer that the config names. It does not contact that
 * sequencer.
 */
export class P2pOnly extends $CustomType {}
export const TransportPolicy$P2pOnly$const = new P2pOnly();
export const TransportPolicy$P2pOnly = () => TransportPolicy$P2pOnly$const;
export const TransportPolicy$isP2pOnly = (value) => value instanceof P2pOnly;

/**
 * The deltas go to the mesh. Every document starts on this path, and that
 * includes a document that is about to attach a relay.
 */
export class PeerToPeer extends $CustomType {}
export const TransportPath$PeerToPeer$const = new PeerToPeer();
export const TransportPath$PeerToPeer = () => TransportPath$PeerToPeer$const;
export const TransportPath$isPeerToPeer = (value) =>
  value instanceof PeerToPeer;

/**
 * The deltas go to the relay. That relay is durable, and it reaches a
 * replica that this one has no peer connection to. The mesh stays open
 * below it.
 */
export class Sequenced extends $CustomType {}
export const TransportPath$Sequenced$const = new Sequenced();
export const TransportPath$Sequenced = () => TransportPath$Sequenced$const;
export const TransportPath$isSequenced = (value) => value instanceof Sequenced;

class SequencerConfig extends $CustomType {
  constructor(url, driver, readiness_deadline_milliseconds) {
    super();
    this.url = url;
    this.driver = driver;
    this.readiness_deadline_milliseconds = readiness_deadline_milliseconds;
  }
}

class CrdtDocument extends $CustomType {
  constructor(cell) {
    super();
    this.cell = cell;
  }
}

class Handle extends $CustomType {
  constructor(cell, address) {
    super();
    this.cell = cell;
    this.address = address;
  }
}

class CrdtConnection extends $CustomType {
  constructor(cell) {
    super();
    this.cell = cell;
  }
}

class Subscription extends $CustomType {
  constructor(cell, id) {
    super();
    this.cell = cell;
    this.id = id;
  }
}

class State extends $CustomType {
  constructor(label, signaling, ice_servers, document, transport, peers, subscriptions, next_subscription, on_status, on_ready, readiness, roster, bootstrap, deferred, imported, attached, closed, policy, sequencer, relay, phase, path, published, resyncs, resync_timer, nudge_dirty, nudge_armed, nudge_timer, publish_owed, scheduler, anti_entropy_interval_milliseconds, sync_armed, sync_timer, last_sync_digest, repairs, last_match, digest_cache, deadline, recovered) {
    super();
    this.label = label;
    this.signaling = signaling;
    this.ice_servers = ice_servers;
    this.document = document;
    this.transport = transport;
    this.peers = peers;
    this.subscriptions = subscriptions;
    this.next_subscription = next_subscription;
    this.on_status = on_status;
    this.on_ready = on_ready;
    this.readiness = readiness;
    this.roster = roster;
    this.bootstrap = bootstrap;
    this.deferred = deferred;
    this.imported = imported;
    this.attached = attached;
    this.closed = closed;
    this.policy = policy;
    this.sequencer = sequencer;
    this.relay = relay;
    this.phase = phase;
    this.path = path;
    this.published = published;
    this.resyncs = resyncs;
    this.resync_timer = resync_timer;
    this.nudge_dirty = nudge_dirty;
    this.nudge_armed = nudge_armed;
    this.nudge_timer = nudge_timer;
    this.publish_owed = publish_owed;
    this.scheduler = scheduler;
    this.anti_entropy_interval_milliseconds = anti_entropy_interval_milliseconds;
    this.sync_armed = sync_armed;
    this.sync_timer = sync_timer;
    this.last_sync_digest = last_sync_digest;
    this.repairs = repairs;
    this.last_match = last_match;
    this.digest_cache = digest_cache;
    this.deadline = deadline;
    this.recovered = recovered;
  }
}

class DigestCache extends $CustomType {
  constructor(taken_from, value, computations) {
    super();
    this.taken_from = taken_from;
    this.value = value;
    this.computations = computations;
  }
}

/**
 * There is no relay. The config names none, or the policy refuses one.
 * 
 * @ignore
 */
class RelayOff extends $CustomType {}
const RelayPhase$RelayOff$const = new RelayOff();

/**
 * The lane opens a socket, or it opens one again after a drop.
 * 
 * @ignore
 */
class RelayOpening extends $CustomType {}
const RelayPhase$RelayOpening$const = new RelayOpening();

/**
 * The relay accepted the capability, and the state handshake runs now.
 * 
 * @ignore
 */
class RelaySyncing extends $CustomType {}
const RelayPhase$RelaySyncing$const = new RelaySyncing();

/**
 * The local digest and the relay digest are equal. The relay is the delta
 * path.
 * 
 * @ignore
 */
class RelayPrimaryPhase extends $CustomType {}
const RelayPhase$RelayPrimaryPhase$const = new RelayPrimaryPhase();

/**
 * The endpoint answered, and it does not support `crdt_relay_v1`. This
 * phase is terminal.
 * 
 * @ignore
 */
class RelayUnsupportedPhase extends $CustomType {}
const RelayPhase$RelayUnsupportedPhase$const = new RelayUnsupportedPhase();

class Peer extends $CustomType {
  constructor(id, greeted) {
    super();
    this.id = id;
    this.greeted = greeted;
  }
}

/**
 * The replica joined the room. The roster has not arrived yet, or no peer
 * passed its checks yet.
 */
export class Joining extends $CustomType {}
export const BootstrapState$Joining$const = new Joining();
export const BootstrapState$Joining = () => BootstrapState$Joining$const;
export const BootstrapState$isJoining = (value) => value instanceof Joining;

export class WaitingForState extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const BootstrapState$WaitingForState = (peer_id) =>
  new WaitingForState(peer_id);
export const BootstrapState$isWaitingForState = (value) =>
  value instanceof WaitingForState;
export const BootstrapState$WaitingForState$peer_id = (value) => value.peer_id;
export const BootstrapState$WaitingForState$0 = (value) => value.peer_id;

export class Bootstrapped extends $CustomType {}
export const BootstrapState$Bootstrapped$const = new Bootstrapped();
export const BootstrapState$Bootstrapped = () =>
  BootstrapState$Bootstrapped$const;
export const BootstrapState$isBootstrapped = (value) =>
  value instanceof Bootstrapped;

class DeferredOpen extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}

class DeferredDocument extends $CustomType {
  constructor(peer_id, payload) {
    super();
    this.peer_id = peer_id;
    this.payload = payload;
  }
}

class DeferredClose extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}

class Subscriber extends $CustomType {
  constructor(id, address, handler) {
    super();
    this.id = id;
    this.address = address;
    this.handler = handler;
  }
}

/**
 * A `p2p_transport_js.Status` value, without a change. It reports the
 * signaling membership, the peer connection state, the ICE state, and the
 * number of open peers.
 */
export class Transport extends $CustomType {
  constructor(status) {
    super();
    this.status = status;
  }
}
export const Status$Transport = (status) => new Transport(status);
export const Status$isTransport = (value) => value instanceof Transport;
export const Status$Transport$status = (value) => value.status;
export const Status$Transport$0 = (value) => value.status;

/**
 * A typed error that the transport reported, before that error reached a
 * document.
 */
export class TransportError extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const Status$TransportError = (error) => new TransportError(error);
export const Status$isTransportError = (value) =>
  value instanceof TransportError;
export const Status$TransportError$error = (value) => value.error;
export const Status$TransportError$0 = (value) => value.error;

/**
 * The module asked the signaling service to join. The document exists, and
 * it accepts an edit.
 */
export class Joined extends $CustomType {
  constructor(room, replica) {
    super();
    this.room = room;
    this.replica = replica;
  }
}
export const Status$Joined = (room, replica) => new Joined(room, replica);
export const Status$isJoined = (value) => value instanceof Joined;
export const Status$Joined$room = (value) => value.room;
export const Status$Joined$0 = (value) => value.room;
export const Status$Joined$replica = (value) => value.replica;
export const Status$Joined$1 = (value) => value.replica;

/**
 * The complete membership of the room, as the signaling adapter reported
 * it. A replica is not ready before this status arrives. Before that, an
 * empty peer list means "no client is announced", and it does not mean "no
 * client is here".
 */
export class RosterKnown extends $CustomType {
  constructor(peers) {
    super();
    this.peers = peers;
  }
}
export const Status$RosterKnown = (peers) => new RosterKnown(peers);
export const Status$isRosterKnown = (value) => value instanceof RosterKnown;
export const Status$RosterKnown$peers = (value) => value.peers;
export const Status$RosterKnown$0 = (value) => value.peers;

/**
 * The replica waits for `peer_id` to answer the bootstrap `stateRequest`
 * message.
 */
export class AwaitingState extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const Status$AwaitingState = (peer_id) => new AwaitingState(peer_id);
export const Status$isAwaitingState = (value) => value instanceof AwaitingState;
export const Status$AwaitingState$peer_id = (value) => value.peer_id;
export const Status$AwaitingState$0 = (value) => value.peer_id;

/**
 * The readiness resolved with a success. The module emits this status
 * before `on_ready` runs, and `readiness` already holds the result. A status
 * handler and the readiness callback thus never disagree about the state of
 * the document.
 */
export class Ready extends $CustomType {}
export const Status$Ready$const = new Ready();
export const Status$Ready = () => Status$Ready$const;
export const Status$isReady = (value) => value instanceof Ready;

/**
 * A peer completed the `hello` handshake.
 */
export class PeerReady extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const Status$PeerReady = (peer_id) => new PeerReady(peer_id);
export const Status$isPeerReady = (value) => value instanceof PeerReady;
export const Status$PeerReady$peer_id = (value) => value.peer_id;
export const Status$PeerReady$0 = (value) => value.peer_id;

/**
 * The document channel of a peer closed.
 */
export class PeerGone extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const Status$PeerGone = (peer_id) => new PeerGone(peer_id);
export const Status$isPeerGone = (value) => value instanceof PeerGone;
export const Status$PeerGone$peer_id = (value) => value.peer_id;
export const Status$PeerGone$0 = (value) => value.peer_id;

/**
 * The module closed a peer for the named protocol violation. The local
 * document does not change, and no other peer changes.
 */
export class PeerRejected extends $CustomType {
  constructor(peer_id, error) {
    super();
    this.peer_id = peer_id;
    this.error = error;
  }
}
export const Status$PeerRejected = (peer_id, error) =>
  new PeerRejected(peer_id, error);
export const Status$isPeerRejected = (value) => value instanceof PeerRejected;
export const Status$PeerRejected$peer_id = (value) => value.peer_id;
export const Status$PeerRejected$0 = (value) => value.peer_id;
export const Status$PeerRejected$error = (value) => value.error;
export const Status$PeerRejected$1 = (value) => value.error;

/**
 * A `state` message from `peer_id` merged, with `channels` channels. This
 * status reports the bootstrap transfer, and it reports a later repair.
 */
export class StateMerged extends $CustomType {
  constructor(peer_id, channels) {
    super();
    this.peer_id = peer_id;
    this.channels = channels;
  }
}
export const Status$StateMerged = (peer_id, channels) =>
  new StateMerged(peer_id, channels);
export const Status$isStateMerged = (value) => value instanceof StateMerged;
export const Status$StateMerged$peer_id = (value) => value.peer_id;
export const Status$StateMerged$0 = (value) => value.peer_id;
export const Status$StateMerged$channels = (value) => value.channels;
export const Status$StateMerged$1 = (value) => value.channels;

/**
 * A peer reported that *it* refused something from this replica, with the
 * reason and the detail of the protocol. Nothing local changed. This message
 * is the one message that explains a link that is about to close, so the
 * module reports it and does not drop it.
 */
export class RejectedByPeer extends $CustomType {
  constructor(peer_id, reason, detail) {
    super();
    this.peer_id = peer_id;
    this.reason = reason;
    this.detail = detail;
  }
}
export const Status$RejectedByPeer = (peer_id, reason, detail) =>
  new RejectedByPeer(peer_id, reason, detail);
export const Status$isRejectedByPeer = (value) =>
  value instanceof RejectedByPeer;
export const Status$RejectedByPeer$peer_id = (value) => value.peer_id;
export const Status$RejectedByPeer$0 = (value) => value.peer_id;
export const Status$RejectedByPeer$reason = (value) => value.reason;
export const Status$RejectedByPeer$1 = (value) => value.reason;
export const Status$RejectedByPeer$detail = (value) => value.detail;
export const Status$RejectedByPeer$2 = (value) => value.detail;

/**
 * A local operation failed. The module reports this status with the
 * `Result` value that the caller already has, so a status log gives the
 * whole account.
 */
export class Failed extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const Status$Failed = (error) => new Failed(error);
export const Status$isFailed = (value) => value instanceof Failed;
export const Status$Failed$error = (value) => value.error;
export const Status$Failed$0 = (value) => value.error;

/**
 * A subscriber callback threw an exception. The document and the transport
 * are correct. The module reports that exception, and it does not hide
 * it.
 */
export class SubscriberFailed extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const Status$SubscriberFailed = (address, detail) =>
  new SubscriberFailed(address, detail);
export const Status$isSubscriberFailed = (value) =>
  value instanceof SubscriberFailed;
export const Status$SubscriberFailed$address = (value) => value.address;
export const Status$SubscriberFailed$0 = (value) => value.address;
export const Status$SubscriberFailed$detail = (value) => value.detail;
export const Status$SubscriberFailed$1 = (value) => value.detail;

/**
 * The module opens a relay lane. There is one of these statuses for each
 * attempt, so a reconnect sequence gives one of them for each
 * `RelayRetry`.
 */
export class RelayConnecting extends $CustomType {
  constructor(url) {
    super();
    this.url = url;
  }
}
export const Status$RelayConnecting = (url) => new RelayConnecting(url);
export const Status$isRelayConnecting = (value) =>
  value instanceof RelayConnecting;
export const Status$RelayConnecting$url = (value) => value.url;
export const Status$RelayConnecting$0 = (value) => value.url;

/**
 * The endpoint answered, and it does not support `crdt_relay_v1`. Under
 * `Auto` that is the whole result, and the document stays on WebRTC. Under
 * `SequencedOnly` it is also the failure of the readiness.
 */
export class RelayUnsupported extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const Status$RelayUnsupported = (detail) => new RelayUnsupported(detail);
export const Status$isRelayUnsupported = (value) =>
  value instanceof RelayUnsupported;
export const Status$RelayUnsupported$detail = (value) => value.detail;
export const Status$RelayUnsupported$0 = (value) => value.detail;

/**
 * The relay accepted the capability, and the state handshake runs now. That
 * handshake is a `hello` message, a `stateRequest` message, a merge, a
 * publication, and a digest. The deltas still go to the mesh while it
 * runs.
 */
export class RelaySyncingStatus extends $CustomType {}
export const Status$RelaySyncingStatus$const = new RelaySyncingStatus();
export const Status$RelaySyncingStatus = () => Status$RelaySyncingStatus$const;
export const Status$isRelaySyncingStatus = (value) =>
  value instanceof RelaySyncingStatus;

/**
 * The same handshake, after the relay was already primary one time. A
 * recovery merges the edits of an outage, from both sides, before it can
 * make a claim.
 */
export class RelayRecovering extends $CustomType {}
export const Status$RelayRecovering$const = new RelayRecovering();
export const Status$RelayRecovering = () => Status$RelayRecovering$const;
export const Status$isRelayRecovering = (value) =>
  value instanceof RelayRecovering;

/**
 * The local digest and the relay digest are equal. The relay is now the
 * durable delta path. `path` already reads `Sequenced` when this status
 * arrives.
 */
export class RelayPrimary extends $CustomType {
  constructor(digest) {
    super();
    this.digest = digest;
  }
}
export const Status$RelayPrimary = (digest) => new RelayPrimary(digest);
export const Status$isRelayPrimary = (value) => value instanceof RelayPrimary;
export const Status$RelayPrimary$digest = (value) => value.digest;
export const Status$RelayPrimary$0 = (value) => value.digest;

/**
 * The relay asked this client to checkpoint, because its live log
 * approaches the bound at which it must start to refuse traffic. The answer
 * is a publication of the current merged state, with an attestation of that
 * state. Nothing about the document changes, and no code reads a number that
 * the relay sent. This status carries no such number either.
 */
export class RelayCheckpointRequested extends $CustomType {}
export const Status$RelayCheckpointRequested$const =
  new RelayCheckpointRequested();
export const Status$RelayCheckpointRequested = () =>
  Status$RelayCheckpointRequested$const;
export const Status$isRelayCheckpointRequested = (value) =>
  value instanceof RelayCheckpointRequested;

/**
 * A requested checkpoint completed. The relay echoed the digest of the state
 * that this replica published, so the relay compacted the ordinary history
 * of the room down to that state.
 */
export class RelayCheckpointed extends $CustomType {
  constructor(digest) {
    super();
    this.digest = digest;
  }
}
export const Status$RelayCheckpointed = (digest) =>
  new RelayCheckpointed(digest);
export const Status$isRelayCheckpointed = (value) =>
  value instanceof RelayCheckpointed;
export const Status$RelayCheckpointed$digest = (value) => value.digest;
export const Status$RelayCheckpointed$0 = (value) => value.digest;

/**
 * The relay is gone, and WebRTC is the delta path again. `path` already
 * reads `PeerToPeer` when this status arrives. A mutation that races the
 * drop is thus safe.
 */
export class RelayFallback extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const Status$RelayFallback = (detail) => new RelayFallback(detail);
export const Status$isRelayFallback = (value) => value instanceof RelayFallback;
export const Status$RelayFallback$detail = (value) => value.detail;
export const Status$RelayFallback$0 = (value) => value.detail;

/**
 * The module armed a reconnect, `delay_milliseconds` milliseconds from now.
 */
export class RelayRetry extends $CustomType {
  constructor(delay_milliseconds) {
    super();
    this.delay_milliseconds = delay_milliseconds;
  }
}
export const Status$RelayRetry = (delay_milliseconds) =>
  new RelayRetry(delay_milliseconds);
export const Status$isRelayRetry = (value) => value instanceof RelayRetry;
export const Status$RelayRetry$delay_milliseconds = (value) =>
  value.delay_milliseconds;
export const Status$RelayRetry$0 = (value) => value.delay_milliseconds;

/**
 * The module refused one envelope from the relay, and the local document
 * did not change. One replica that behaves incorrectly does not cost the
 * lane. Unlike a peer, this module cannot close a relay client. To close the
 * relay would remove the lane from every other replica on it.
 */
export class RelayRejected extends $CustomType {
  constructor(from, error) {
    super();
    this.from = from;
    this.error = error;
  }
}
export const Status$RelayRejected = (from, error) =>
  new RelayRejected(from, error);
export const Status$isRelayRejected = (value) => value instanceof RelayRejected;
export const Status$RelayRejected$from = (value) => value.from;
export const Status$RelayRejected$0 = (value) => value.from;
export const Status$RelayRejected$error = (value) => value.error;
export const Status$RelayRejected$1 = (value) => value.error;

/**
 * The relay lane itself failed. That failure is a socket that did not open,
 * a malformed frame, or a refusal from the service.
 */
export class RelayFailed extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const Status$RelayFailed = (error) => new RelayFailed(error);
export const Status$isRelayFailed = (value) => value instanceof RelayFailed;
export const Status$RelayFailed$error = (value) => value.error;
export const Status$RelayFailed$0 = (value) => value.error;

/**
 * How long `SequencedOnly` waits for a relay to become primary, before it
 * stops. The value is generous. It covers a socket handshake, a capability
 * exchange, a state replay, and a digest round trip.
 */
export const default_readiness_deadline_milliseconds = 10_000;

/**
 * The anti-entropy interval, on both lanes.
 *
 * This interval is for **anti-entropy, and not for repair**. While the relay
 * is primary, a new delta goes to the relay, and the peers receive a `digest`
 * message. That digest is how a replica that is not on this relay learns that
 * it is behind.
 *
 * That digest must not arrive before the fan-out of the same delta from the
 * relay. If it does, every peer answers with a `stateRequest` for a digest
 * that it is about to satisfy, and the room pays for a whole-state transfer on
 * every edit. The digest thus waits. The wait is long enough for an ordinary
 * relay round trip to land first, and short enough that a peer that the relay
 * cannot reach learns the change in an interval that a person calls
 * immediate.
 *
 * On the mesh path, the same interval paces the recurring heartbeat. There the
 * interval alone does not keep an idle room quiet. The heartbeat broadcasts
 * only when the digest moves after the last message to the peers. A cadence of
 * one quarter of a second thus costs a quiet mesh nothing, and it gives a mesh
 * that moved a repair in an interval that a person calls immediate.
 *
 * The value is one quarter of a second. A caller can replace it, with
 * `with_anti_entropy_interval_milliseconds`. The scheduler of the document
 * measures it, so a test steps that scheduler and does not wait.
 *
 * A repair after a failover does not use this interval at all. That repair is
 * a `stateRequest` message to every peer, which the module sends with the
 * fallback, and with no delay.
 */
export const default_anti_entropy_milliseconds = 250;

export const bias_before = Bias$Before$const;

export const bias_after = Bias$After$const;

/**
 * A relay at `url`, which uses `crdt_relay_v1` over a real `WebSocket`.
 */
export function sequencer(url) {
  return new SequencerConfig(
    url,
    $crdt_sequencer_js.native_driver(),
    default_readiness_deadline_milliseconds,
  );
}

/**
 * Replace the socket layer. The deterministic tests attach a scripted relay to
 * this seam. It has the same shape as `p2p_transport_js.Rtc`, for the same
 * reason.
 */
export function with_relay_driver(config, driver) {
  return new SequencerConfig(
    config.url,
    driver,
    config.readiness_deadline_milliseconds,
  );
}

/**
 * Change the time that `SequencedOnly` waits. A deadline of zero or less never
 * expires. That value is correct only for a caller that limits the wait
 * itself.
 */
export function with_readiness_deadline_milliseconds(
  config,
  deadline_milliseconds
) {
  return new SequencerConfig(config.url, config.driver, deadline_milliseconds);
}

export function sequencer_url(config) {
  return config.url;
}

/**
 * Configure a document.
 *
 * `room_id` names the signaling room, and the module checks it on every
 * envelope. `replica_label` is a label for a person to read, and nothing else.
 * See the module docs on identity. That label must contain no `:` character,
 * because `:` separates the two halves of a channel address.
 * `compatibility_tag` is the schema version of the application. Two peers
 * whose tags differ refuse each other, and they do not merge two documents
 * that have different meanings.
 */
export function config(
  room_id,
  replica_label,
  compatibility_tag,
  root,
  signaling
) {
  return new Config(
    room_id,
    replica_label,
    compatibility_tag,
    $p2p.kind_init(root),
    signaling,
    $List$Empty$const,
    TransportPolicy$Auto$const,
    Option$None$const,
    $transport_js.real_scheduler(),
    default_anti_entropy_milliseconds,
  );
}

/**
 * Select the transports that this document can use. The default is `Auto`.
 */
export function with_transport_policy(config, policy) {
  return new Config(
    config.room,
    config.label,
    config.compatibility,
    config.root,
    config.signaling,
    config.ice_servers,
    policy,
    config.sequencer,
    config.scheduler,
    config.anti_entropy_interval_milliseconds,
  );
}

/**
 * Attach an optional sequencer relay. The module ignores this relay under
 * `P2pOnly`, and it requires one under `SequencedOnly`. A `SequencedOnly`
 * document with no sequencer fails its readiness one time, with
 * `SequencerUnavailable`. It does not wait for a component that no caller
 * configured.
 */
export function with_sequencer(config, sequencer) {
  return new Config(
    config.room,
    config.label,
    config.compatibility,
    config.root,
    config.signaling,
    config.ice_servers,
    config.policy,
    new Some(sequencer),
    config.scheduler,
    config.anti_entropy_interval_milliseconds,
  );
}

/**
 * Supply the STUN servers and TURN servers that the peer connections are built
 * with. watershed supplies none. An empty list is correct for a LAN and for a
 * same-origin loopback. The application supplies every other server.
 */
export function with_ice_servers(config, servers) {
  return new Config(
    config.room,
    config.label,
    config.compatibility,
    config.root,
    config.signaling,
    servers,
    config.policy,
    config.sequencer,
    config.scheduler,
    config.anti_entropy_interval_milliseconds,
  );
}

/**
 * Replace the clock that measures every delay of this document. Those delays
 * are the mesh heartbeat, the coalescer of the relay, the reconnect and resync
 * backoff of that relay, and the readiness deadline. A test thus steps a
 * logical clock, and it does not wait for the real time.
 */
export function with_scheduler(config, scheduler) {
  return new Config(
    config.room,
    config.label,
    config.compatibility,
    config.root,
    config.signaling,
    config.ice_servers,
    config.policy,
    config.sequencer,
    scheduler,
    config.anti_entropy_interval_milliseconds,
  );
}

/**
 * Change the anti-entropy interval. That interval is the cadence of the mesh
 * heartbeat, and it is the period over which the relay path collects the peer
 * digests while that path is primary. An interval of zero or less still goes
 * through the scheduler, and the module does not send the message
 * immediately.
 */
export function with_anti_entropy_interval_milliseconds(
  config,
  interval_milliseconds
) {
  return new Config(
    config.room,
    config.label,
    config.compatibility,
    config.root,
    config.signaling,
    config.ice_servers,
    config.policy,
    config.sequencer,
    config.scheduler,
    interval_milliseconds,
  );
}

/**
 * The signaling room that this config joins.
 */
export function config_room(config) {
  return config.room;
}

/**
 * The compatibility tag of the application that this config applies.
 */
export function config_compatibility(config) {
  return config.compatibility;
}

/**
 * The canonical digest of this document. The function computes it when the
 * document moved after the last digest, and it reuses the earlier value when
 * the document did not move.
 *
 * Every digest that this facade uses goes through this function: the mesh
 * heartbeat, the coalesced digest of the relay, the comparison against the
 * digest of a peer, the publication with its attestation, and the public
 * `digest` function. There is thus one canonicalization for each document
 * state, whatever number of callers ask for it. The cache uses the document
 * itself as its key, so a state change cannot leave a stale digest. Such a
 * change misses the cache.
 * 
 * @ignore
 */
function document_digest(cell) {
  let state = $transport_js.get_cell(cell);
  let cache = $transport_js.get_cell(state.digest_cache);
  let _block;
  let $ = cache.taken_from;
  if ($ instanceof Some) {
    let document = $[0];
    let $1 = same_document(document, state.document);
    if ($1) {
      _block = new Some(cache.value);
    } else {
      _block = Option$None$const;
    }
  } else {
    _block = $;
  }
  let hit = _block;
  if (hit instanceof Some) {
    let value = hit[0];
    return value;
  } else {
    let value = $crdt_core.digest(state.document);
    $transport_js.set_cell(
      state.digest_cache,
      new DigestCache(new Some(state.document), value, cache.computations + 1),
    );
    return value;
  }
}

/**
 * `crdt_core.digest_message`, from the digest that this document already
 * computed. The message is the same in both routes. This function removes the
 * hash step only.
 * 
 * @ignore
 */
function digest_message(cell) {
  return new $crdt_wire.Digest(document_digest(cell));
}

/**
 * Build the document that a `Config` value describes, and join nothing.
 *
 * The function creates the root from the config, and it never learns that root
 * from a peer. Two replicas that agree on the config thus agree on the root
 * before they exchange a message. Give the result to `attach` to connect
 * it.
 */
export function new_document(config) {
  let session = $id.uuid_v4();
  let replica = (config.label + "-") + session;
  let core = $crdt_core.config(
    config.room,
    config.compatibility,
    replica,
    session,
    config.root,
  );
  return $result.try$(
    $crdt_core.new$(core),
    (document) => {
      return new Ok(
        new CrdtDocument(
          $transport_js.new_cell(
            new State(
              config.label,
              config.signaling,
              config.ice_servers,
              document,
              Option$None$const,
              $dict.new$(),
              $List$Empty$const,
              0,
              (_) => { return undefined; },
              (_) => { return undefined; },
              Option$None$const,
              false,
              BootstrapState$Joining$const,
              $List$Empty$const,
              false,
              false,
              false,
              config.policy,
              config.sequencer,
              Option$None$const,
              RelayPhase$RelayOff$const,
              TransportPath$PeerToPeer$const,
              "",
              0,
              Option$None$const,
              false,
              false,
              Option$None$const,
              false,
              config.scheduler,
              config.anti_entropy_interval_milliseconds,
              false,
              Option$None$const,
              "",
              0,
              Option$None$const,
              $transport_js.new_cell(new DigestCache(Option$None$const, "", 0)),
              Option$None$const,
              false,
            ),
          ),
        ),
      );
    },
  );
}

/**
 * Run one application callback, and do not let an exception from it enter the
 * call stack of the protocol. The contract of this facade is that a callback
 * cannot change what the document does, and cannot change what the transport
 * does.
 * 
 * @ignore
 */
function contained(work) {
  return guard(work, (_) => { return undefined; });
}

/**
 * Report one status. The handler is application code, and this function
 * contains it. An exception from a status handler must not skip a state
 * request, suppress a readiness result, or leave the peers after it. The
 * function does not report that exception again, because the only channel for
 * such a report is the channel that just threw.
 * 
 * @ignore
 */
function emit(cell, status) {
  let state = $transport_js.get_cell(cell);
  return contained(() => { return state.on_status(status); });
}

function cancel(timer) {
  if (timer instanceof Some) {
    let stop = timer[0];
    return stop();
  } else {
    return undefined;
  }
}

/**
 * Stop the heartbeat and clear its flags. The module calls this function when
 * the last validated peer leaves, on a failover to a path where the relay is
 * primary, and on a close.
 * 
 * @ignore
 */
function cancel_sync(cell) {
  let state = $transport_js.get_cell(cell);
  cancel(state.sync_timer);
  return $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      false,
      Option$None$const,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
}

/**
 * The ids of every peer that completed the `hello` handshake, sorted. This
 * function is the one definition of the peers that this document can send
 * to.
 * 
 * @ignore
 */
function greeted_peers(state) {
  let _pipe = state.peers;
  let _pipe$1 = $dict.values(_pipe);
  let _pipe$2 = $list.filter(_pipe$1, (peer) => { return peer.greeted; });
  let _pipe$3 = $list.map(_pipe$2, (peer) => { return peer.id; });
  return $list.sort(_pipe$3, $string.compare);
}

/**
 * Send one message to every peer that completed the handshake.
 *
 * This function is not the broadcast of the transport, and that choice is
 * deliberate. A data channel can be open before the module checks its `hello`
 * message. A peer that has not proved that it agrees about the room, the
 * protocol, the compatibility tag, and the root must not receive the deltas of
 * this document.
 * 
 * @ignore
 */
function peer_broadcast(cell, message) {
  let state = $transport_js.get_cell(cell);
  let $ = state.transport;
  if ($ instanceof Some) {
    let transport = $[0];
    let payload = $crdt_core.encode(state.document, message);
    let _pipe = greeted_peers(state);
    return $list.each(
      _pipe,
      (peer_id) => {
        let $1 = $p2p_transport_js.send(transport, peer_id, payload);
        
        return undefined;
      },
    );
  } else {
    return undefined;
  }
}

/**
 * Send the canonical digest to every validated peer, and record it as the last
 * announced digest. The recurring heartbeat thus sends nothing until the
 * document moves again. Every broadcast of a digest to the whole mesh goes
 * through this function: the broadcast of the heartbeat, the flush of the relay
 * coalescer, and the final push of a failover. One of them thus cannot make the
 * gate incorrect.
 * 
 * @ignore
 */
function broadcast_digest(cell) {
  let digest$1 = document_digest(cell);
  let state = $transport_js.get_cell(cell);
  $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      digest$1,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
  return peer_broadcast(cell, new $crdt_wire.Digest(digest$1));
}

/**
 * The payload of one heartbeat, behind the dirty gate. The function broadcasts
 * the canonical digest only when that digest differs from the last one that the
 * peers received.
 * 
 * @ignore
 */
function sync_digest(cell) {
  let digest$1 = document_digest(cell);
  let state = $transport_js.get_cell(cell);
  let $ = digest$1 === state.last_sync_digest;
  if ($) {
    return undefined;
  } else {
    return broadcast_digest(cell);
  }
}

/**
 * Whether one peer or more completed the `hello` handshake. The module sends
 * the mesh anti-entropy digest to a validated peer only, so this replica sends
 * nothing in a room where no peer is validated.
 * 
 * @ignore
 */
function has_greeted_peer(state) {
  return !(greeted_peers(state) instanceof $Empty);
}

/**
 * Whether the mesh anti-entropy heartbeat must run. Four conditions must hold:
 * the document is open, its delta path is WebRTC, it has a transport, and it
 * has one validated peer or more to send to. `refresh_sync`, `arm_sync`, and
 * `tick_sync` all use this one predicate, so "a peer exists" has one
 * meaning.
 * 
 * @ignore
 */
function should_sync(state) {
  let $ = state.closed;
  let $1 = state.path;
  let $2 = state.transport;
  if ($) {
    if ($1 instanceof PeerToPeer) {
      return false;
    } else {
      return false;
    }
  } else if ($1 instanceof PeerToPeer && $2 instanceof Some) {
    return has_greeted_peer(state);
  } else {
    return false;
  }
}

/**
 * One heartbeat. The function checks again that the document is still
 * eligible, sends the canonical digest to every validated peer, and arms the
 * timer for the next interval. A document that failed back onto a relay, that
 * lost its last peer, or that a caller closed after the timer was set, sends
 * nothing, and the heartbeat then ends.
 *
 * The broadcast has a gate: the digest must have moved after the last
 * broadcast, or a mismatch from a peer must have cleared `last_sync_digest`.
 * The timer recurs, and an idle mesh that converged sends nothing. It does not
 * repeat the same digest in every interval without an end.
 *
 * The function does not arm the timer again when this tick ran *synchronously*
 * from inside `arm_sync`. The function detects that condition because the
 * module has not stored the canceller yet, so `sync_timer` is still `None`. A
 * synchronous scheduler that armed the timer again here would recurse without
 * a bound. To run exactly one time instead is the only behaviour without a
 * loop that a clock which never advances can have. A real asynchronous
 * scheduler, and a logical one, both store the canceller before the tick. The
 * function thus arms the timer again, and the heartbeat recurs.
 * 
 * @ignore
 */
function tick_sync(cell) {
  let state = $transport_js.get_cell(cell);
  let armed_asynchronously = $option.is_some(state.sync_timer);
  $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      false,
      Option$None$const,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
  let $ = should_sync(state);
  if ($) {
    sync_digest(cell);
    if (armed_asynchronously) {
      return arm_sync(cell);
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

/**
 * Anti-entropy for the mesh, while WebRTC is the delta path. This function is
 * the recurring equivalent of `nudge_peers` on the relay path.
 *
 * The canonical state can move with no new broadcast and with no visible
 * event. Three examples: a `state` transfer, a partition that heals on one
 * reconnected edge, and a concurrent OR-Set tag or 2P-Set tombstone that
 * changes the lattice and not the membership that a subscriber sees. None of
 * those changes fans out by itself, so the mesh cannot start a repair from
 * them.
 *
 * Instead, while a validated peer exists, the document checks every
 * `anti_entropy_interval_milliseconds` whether its canonical digest moved
 * after the last message to the peers. It broadcasts that digest when the
 * digest moved. A peer whose digest matches answers nothing. A peer whose
 * digest differs asks for the state, on the existing mismatch path of
 * `crdt_core`, and it also clears its own gate. The side that is ahead thus
 * continues to announce until the room agrees. An idle mesh that converged
 * therefore costs one digest and then nothing, and not one broadcast in every
 * interval.
 *
 * To reconnect one edge between two partitions thus repairs *every* remaining
 * peer, and not the two endpoints only. A quiet mesh that merged a change with
 * no event also converges. Neither condition needs a later edit with an event
 * to start a flush.
 *
 * There is one live timer. `arm_sync` does nothing when a heartbeat is armed
 * already, and `tick_sync` clears the flag before it arms the timer again. The
 * `nudge_*` fields of the relay path are separate, and the module never arms
 * both at the same time. The transport path is one or the other, and a failover
 * cancels the coalescer of the relay before this heartbeat starts.
 * 
 * @ignore
 */
function arm_sync(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = should_sync(state);
  let $1 = state.sync_armed;
  if ($ && !$1) {
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        true,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    return $timer_js.arm(
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      () => { return tick_sync(cell); },
      () => {
        let armed = $transport_js.get_cell(cell);
        return armed.sync_armed && !armed.closed;
      },
      (stop) => {
        let armed = $transport_js.get_cell(cell);
        return $transport_js.set_cell(
          cell,
          new State(
            armed.label,
            armed.signaling,
            armed.ice_servers,
            armed.document,
            armed.transport,
            armed.peers,
            armed.subscriptions,
            armed.next_subscription,
            armed.on_status,
            armed.on_ready,
            armed.readiness,
            armed.roster,
            armed.bootstrap,
            armed.deferred,
            armed.imported,
            armed.attached,
            armed.closed,
            armed.policy,
            armed.sequencer,
            armed.relay,
            armed.phase,
            armed.path,
            armed.published,
            armed.resyncs,
            armed.resync_timer,
            armed.nudge_dirty,
            armed.nudge_armed,
            armed.nudge_timer,
            armed.publish_owed,
            armed.scheduler,
            armed.anti_entropy_interval_milliseconds,
            armed.sync_armed,
            new Some(stop),
            armed.last_sync_digest,
            armed.repairs,
            armed.last_match,
            armed.digest_cache,
            armed.deadline,
            armed.recovered,
          ),
        );
      },
    );
  } else {
    return undefined;
  }
}

/**
 * Reconcile the heartbeat with the current shape of the document. The function
 * arms the heartbeat when that heartbeat must run and does not run. It cancels
 * the heartbeat when that heartbeat runs and must not run. A second call has no
 * more effect. Every lifecycle event that can change `should_sync` thus calls
 * this function, and it needs to know nothing about the earlier state of the
 * timer. Those events are a greeting, a failover to the mesh, and a peer that
 * leaves.
 * 
 * @ignore
 */
function refresh_sync(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = should_sync(state);
  let $1 = state.sync_armed;
  if ($) {
    if ($1) {
      return undefined;
    } else {
      return arm_sync(cell);
    }
  } else if ($1) {
    return cancel_sync(cell);
  } else {
    return undefined;
  }
}

function send(cell, peer_id, message) {
  let state = $transport_js.get_cell(cell);
  let $ = state.transport;
  if ($ instanceof Some) {
    let transport = $[0];
    let payload = $crdt_core.encode(state.document, message);
    let $1 = $p2p_transport_js.send(transport, peer_id, payload);
    
    return undefined;
  } else {
    return undefined;
  }
}

/**
 * Ask every validated peer for its state, so that an outage that started on
 * the relay does not also start with a gap. A merge is idempotent, and a
 * `state` message that changes nothing emits nothing. This function thus costs
 * one round trip, and it costs no correctness.
 * 
 * @ignore
 */
function repair_from_peers(cell) {
  let state = $transport_js.get_cell(cell);
  let _pipe = greeted_peers(state);
  return $list.each(
    _pipe,
    (peer_id) => {
      return send(cell, peer_id, $crdt_core.state_request_message());
    },
  );
}

/**
 * The one digest that a fallback owes the mesh.
 *
 * While the relay is primary, a durable delta goes to the relay and *not* to
 * the peers. Those peers receive a coalesced digest on the anti-entropy
 * interval. Without this function, a drop inside that window would cancel the
 * digest and send a `stateRequest` message only. That message pulls the state
 * of each peer and tells that peer nothing. A peer that never saw the
 * relay-only edits would answer with a state that does not contain them, it
 * would merge nothing, and it would stay behind until the next local
 * mutation. In a room that became quiet, it would stay behind without an
 * end.
 *
 * This function thus flushes a window that is dirty or armed exactly one time,
 * synchronously, before the failover sends its `stateRequest`. The peer
 * compares that digest, finds that it does not match, asks for the state on
 * the existing mismatch path of `crdt_core`, and converges with the fallback.
 * The module already cancelled the timer, so this is one push and not two.
 * 
 * @ignore
 */
function final_nudge(cell, owed) {
  if (owed) {
    return broadcast_digest(cell);
  } else {
    return undefined;
  }
}

/**
 * Disarm the anti-entropy flush. The module is about to send the mesh
 * something larger than a digest, or it just sent that, or there is nothing
 * left to send. An owed publication also goes away. The only caller is a lane
 * that is gone, and a lane that comes back publishes the whole merged state
 * during its handshake.
 * 
 * @ignore
 */
function cancel_nudge(cell) {
  let state = $transport_js.get_cell(cell);
  cancel(state.nudge_timer);
  return $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      false,
      false,
      Option$None$const,
      false,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
}

/**
 * The relay lane is gone.
 *
 * Nothing local stops. The function changes the path to the mesh *before* it
 * emits the fallback status. A mutation from a status handler, and a mutation
 * that was already in flight, thus both go to the peers, and neither one goes
 * into a socket that is not there. The document, its handles, its subscribers,
 * its replica identity, and its message counter all stay the same. A transport
 * changed, and a session did not.
 * 
 * @ignore
 */
function relay_dropped(cell, detail) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return undefined;
  } else {
    let _block;
    let $1 = state.phase;
    if ($1 instanceof RelayOff) {
      _block = false;
    } else if ($1 instanceof RelayOpening) {
      _block = false;
    } else if ($1 instanceof RelaySyncing) {
      _block = true;
    } else if ($1 instanceof RelayPrimaryPhase) {
      _block = true;
    } else {
      _block = false;
    }
    let attached = _block;
    let owed = state.nudge_dirty || state.nudge_armed;
    cancel(state.resync_timer);
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        (() => {
          let $2 = state.phase;
          if ($2 instanceof RelayOff) {
            return RelayPhase$RelayOpening$const;
          } else if ($2 instanceof RelayOpening) {
            return RelayPhase$RelayOpening$const;
          } else if ($2 instanceof RelaySyncing) {
            return RelayPhase$RelayOpening$const;
          } else if ($2 instanceof RelayPrimaryPhase) {
            return RelayPhase$RelayOpening$const;
          } else {
            return $2;
          }
        })(),
        TransportPath$PeerToPeer$const,
        "",
        0,
        Option$None$const,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    cancel_nudge(cell);
    if (attached) {
      emit(cell, new RelayFallback(detail));
      final_nudge(cell, owed);
      repair_from_peers(cell);
    } else {
      undefined;
    }
    return refresh_sync(cell);
  }
}

/**
 * Resolve the readiness one time at most, for the whole life of the
 * connection.
 *
 * The function writes the result and emits the status *before* the application
 * callback runs. `readiness` and the status stream thus already agree with
 * that result before any code observes it. A callback that throws also cannot
 * leave a connection that tries to resolve the readiness a second time,
 * because the module guards both callbacks and neither one runs before the
 * write.
 * 
 * @ignore
 */
function resolve_ready(cell, outcome) {
  let state = $transport_js.get_cell(cell);
  let $ = state.readiness;
  if ($ instanceof Some) {
    return undefined;
  } else {
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        new Some(outcome),
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    if (outcome instanceof Ok) {
      emit(cell, Status$Ready$const);
    } else {
      let error = outcome[0];
      emit(cell, new Failed(error));
    }
    return contained(() => { return state.on_ready(outcome); });
  }
}

function mark_closed(cell) {
  let state = $transport_js.get_cell(cell);
  cancel(state.resync_timer);
  cancel(state.nudge_timer);
  cancel(state.sync_timer);
  cancel(state.deadline);
  return $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      Option$None$const,
      $dict.new$(),
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      true,
      state.policy,
      state.sequencer,
      state.relay,
      RelayPhase$RelayOff$const,
      TransportPath$PeerToPeer$const,
      state.published,
      state.resyncs,
      Option$None$const,
      false,
      false,
      Option$None$const,
      false,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      false,
      Option$None$const,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      Option$None$const,
      state.recovered,
    ),
  );
}

function resolved(state) {
  return !(state.readiness instanceof None);
}

/**
 * Stop with a document that can never become ready. The function resolves the
 * readiness one time, with the reason, and it closes everything that the
 * document holds.
 * 
 * @ignore
 */
function abandon(cell, error) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = resolved(state);
  if ($) {
    return undefined;
  } else if ($1) {
    return undefined;
  } else {
    mark_closed(cell);
    let $2 = state.transport;
    if ($2 instanceof Some) {
      let transport = $2[0];
      $p2p_transport_js.close(transport);
    } else {
      undefined;
    }
    let $3 = state.relay;
    if ($3 instanceof Some) {
      let relay = $3[0];
      $crdt_sequencer_js.close(relay);
    } else {
      undefined;
    }
    return resolve_ready(cell, new Error(error));
  }
}

/**
 * The endpoint is a sequencer without this lane.
 *
 * Under `Auto` that condition is a status and nothing more. The document
 * continues on the mesh, exactly as it would with no sequencer in the config.
 * Under `SequencedOnly` it is the failure of the readiness, because there is
 * no other path to be ready on.
 * 
 * @ignore
 */
function relay_unsupported(cell, detail) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return undefined;
  } else {
    cancel(state.resync_timer);
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        RelayPhase$RelayUnsupportedPhase$const,
        TransportPath$PeerToPeer$const,
        state.published,
        state.resyncs,
        Option$None$const,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    emit(cell, new RelayUnsupported(detail));
    let $1 = state.policy;
    if ($1 instanceof Auto) {
      return undefined;
    } else if ($1 instanceof SequencedOnly) {
      return abandon(cell, $p2p.P2pError$SequencerUnsupported$const);
    } else {
      return undefined;
    }
  }
}

/**
 * Remove an owed publication, because the module just wrote one, or because
 * there is no longer a lane to write it on. A lane that comes back publishes
 * the whole merged state during its handshake, so a fallback that drops this
 * value loses nothing.
 * 
 * @ignore
 */
function clear_publication(cell) {
  let state = $transport_js.get_cell(cell);
  return $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      false,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
}

/**
 * A write that did not reach an open socket. The function retires the lane on
 * the same path as a close that the driver reported. There is thus one
 * fallback sequence, and not two.
 * 
 * @ignore
 */
function relay_unwritable(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.relay;
  if ($ instanceof Some) {
    let relay = $[0];
    return $crdt_sequencer_js.abort(relay, "the relay socket was not writable");
  } else {
    return undefined;
  }
}

/**
 * Write one message to the relay, if a relay exists to write to.
 * 
 * @ignore
 */
function relay_send(cell, message) {
  let state = $transport_js.get_cell(cell);
  let $ = state.relay;
  if ($ instanceof Some) {
    let relay = $[0];
    let _pipe = $crdt_sequencer_js.send_envelope(
      relay,
      $crdt_core.encode(state.document, message),
    );
    return $result.is_ok(_pipe);
  } else {
    return false;
  }
}

/**
 * `relay_send`, and this function handles the failure instead of an ignore.
 *
 * Every write on this lane is one of four things: the `hello` and
 * `stateRequest` messages of the attachment, the published `state` message, a
 * reply to something that the relay carried, or a durable broadcast. A `False`
 * result means the same thing for all four: this socket is gone. The one
 * correct answer is to retire that socket. The function thus changes the path
 * to the mesh, reports the fallback, repairs from the peers, and arms the
 * reconnect of the policy. Every other answer leaves the document in the
 * middle of a handshake, on a socket that will never answer.
 * 
 * @ignore
 */
function relay_write(cell, message) {
  let $ = relay_send(cell, message);
  if ($) {
    return $;
  } else {
    relay_unwritable(cell);
    return false;
  }
}

/**
 * The two frames of a publication, whatever caller asked for it: the whole
 * merged state, and an attestation of the digest that describes that state.
 *
 * This function is separate because three callers owe the relay exactly these
 * two frames, and those callers must not drift apart. They are the attachment
 * handshake, a requested checkpoint, and a merge that this replica learned
 * from a peer while the relay was primary. If either write fails, the function
 * retires the socket. It does not wait for an echo that cannot arrive.
 * 
 * @ignore
 */
function publish(cell, relay, digest, document) {
  let $ = relay_write(cell, $crdt_core.state_message(document));
  if ($) {
    let $1 = $crdt_sequencer_js.attest(relay, digest);
    if ($1 instanceof Ok) {
      return undefined;
    } else {
      return relay_unwritable(cell);
    }
  } else {
    return undefined;
  }
}

/**
 * Publish the current merged state while the relay is *primary*, and attest
 * that state.
 *
 * The function writes the same two frames as the attachment handshake, in the
 * same order, and it records the digest as `published`. The echo of the relay
 * thus completes the checkpoint in the usual way. An echo that matches gives a
 * `RelayCheckpointed` status and a compacted log. An empty echo means that the
 * relay holds traffic that a client published after this state, and the next
 * checkpoint request of that relay asks about it again.
 *
 * Nothing retries from this function. That rule keeps a busy room from a loop
 * of publications.
 *
 * The function reads the document again, and it does not take a snapshot from
 * its caller. A status handler that closed the document, or that dropped the
 * lane, between the decision and this line is owed no frame.
 * 
 * @ignore
 */
function publish_while_primary(cell) {
  let digest$1 = document_digest(cell);
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.relay;
  let $2 = state.phase;
  if ($1 instanceof Some) {
    if ($) {
      return undefined;
    } else if ($2 instanceof RelayOff) {
      return undefined;
    } else if ($2 instanceof RelayOpening) {
      return undefined;
    } else if ($2 instanceof RelaySyncing) {
      return undefined;
    } else if ($2 instanceof RelayPrimaryPhase) {
      let relay = $1[0];
      $transport_js.set_cell(
        cell,
        new State(
          state.label,
          state.signaling,
          state.ice_servers,
          state.document,
          state.transport,
          state.peers,
          state.subscriptions,
          state.next_subscription,
          state.on_status,
          state.on_ready,
          state.readiness,
          state.roster,
          state.bootstrap,
          state.deferred,
          state.imported,
          state.attached,
          state.closed,
          state.policy,
          state.sequencer,
          state.relay,
          state.phase,
          state.path,
          digest$1,
          state.resyncs,
          state.resync_timer,
          state.nudge_dirty,
          state.nudge_armed,
          state.nudge_timer,
          state.publish_owed,
          state.scheduler,
          state.anti_entropy_interval_milliseconds,
          state.sync_armed,
          state.sync_timer,
          state.last_sync_digest,
          state.repairs,
          state.last_match,
          state.digest_cache,
          state.deadline,
          state.recovered,
        ),
      );
      return publish(cell, relay, digest$1, state.document);
    } else {
      return undefined;
    }
  } else if ($) {
    return undefined;
  } else {
    return undefined;
  }
}

/**
 * The relay asked for a checkpoint.
 *
 * The live log of a relay is bounded, and a room that fills that log makes the
 * relay refuse traffic, and that includes the traffic of a correct client. The
 * relay thus asks the clients that understand the request to publish what they
 * hold, before it reaches the bound. A correct client answers with exactly the
 * two frames that it publishes during an attachment: the whole merged state,
 * and an attestation of the digest of that state. The checkpoint of the relay
 * then compacts the ordinary valid history of the room down to that one
 * record. A long editing session thus never reaches the bound.
 *
 * Nothing about the document changes here, and this function reads nothing
 * that the relay sent. The published state is the state of this replica,
 * exactly as it would be at an attachment.
 *
 * There are three conditions, and one of them writes a frame:
 *
 *   * **syncing**: the attachment handshake already publishes and attests, so
 *     the module already answers the request. This function reports the
 *     request and does nothing more.
 *   * **primary**: publish and attest now.
 *   * **every other condition**: there is no lane to answer on.
 * 
 * @ignore
 */
function relay_checkpoint_requested(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.relay;
  let $2 = state.phase;
  if ($) {
    return undefined;
  } else if ($1 instanceof Some) {
    if ($2 instanceof RelayOff) {
      return undefined;
    } else if ($2 instanceof RelayOpening) {
      return undefined;
    } else if ($2 instanceof RelaySyncing) {
      return emit(cell, Status$RelayCheckpointRequested$const);
    } else if ($2 instanceof RelayPrimaryPhase) {
      emit(cell, Status$RelayCheckpointRequested$const);
      publish_while_primary(cell);
      return clear_publication(cell);
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

/**
 * Publish the whole merged local state, and attest its digest in the same
 * step.
 *
 * The two go together on purpose. The digest describes the state that the
 * module just wrote, so the echo of the relay is an acknowledgement of a
 * document that the relay holds. It is not a claim that this replica invented.
 * If either write fails, the function retires the socket. It does not wait for
 * an echo that cannot arrive.
 * 
 * @ignore
 */
function publish_state(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.relay;
  let $2 = state.phase;
  if ($1 instanceof Some) {
    if ($) {
      return undefined;
    } else if ($2 instanceof RelayOff) {
      return undefined;
    } else if ($2 instanceof RelayOpening) {
      return undefined;
    } else if ($2 instanceof RelaySyncing) {
      let relay = $1[0];
      cancel(state.resync_timer);
      let digest$1 = document_digest(cell);
      $transport_js.set_cell(
        cell,
        new State(
          state.label,
          state.signaling,
          state.ice_servers,
          state.document,
          state.transport,
          state.peers,
          state.subscriptions,
          state.next_subscription,
          state.on_status,
          state.on_ready,
          state.readiness,
          state.roster,
          state.bootstrap,
          state.deferred,
          state.imported,
          state.attached,
          state.closed,
          state.policy,
          state.sequencer,
          state.relay,
          state.phase,
          state.path,
          digest$1,
          state.resyncs,
          Option$None$const,
          state.nudge_dirty,
          state.nudge_armed,
          state.nudge_timer,
          state.publish_owed,
          state.scheduler,
          state.anti_entropy_interval_milliseconds,
          state.sync_armed,
          state.sync_timer,
          state.last_sync_digest,
          state.repairs,
          state.last_match,
          state.digest_cache,
          state.deadline,
          state.recovered,
        ),
      );
      return publish(cell, relay, digest$1, state.document);
    } else if ($2 instanceof RelayPrimaryPhase) {
      return undefined;
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

/**
 * Try the publish and attest handshake again, later.
 *
 * The retry has a backoff, and it is not immediate. It is also event-driven,
 * and it does not poll. Two replicas that attach at the same time can each
 * hold something that the other has not merged yet. A pair that retried
 * immediately would invalidate the attestation of the other one, without an
 * end. The delay separates them, and any change to the local document ends the
 * wait early.
 * 
 * @ignore
 */
function schedule_resync(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.phase;
  if ($) {
    return undefined;
  } else if ($1 instanceof RelaySyncing) {
    cancel(state.resync_timer);
    return $timer_js.arm(
      state.scheduler,
      $crdt_sequencer_js.backoff_milliseconds(state.resyncs),
      () => { return publish_state(cell); },
      () => {
        let armed = $transport_js.get_cell(cell);
        return (armed.phase instanceof RelaySyncing) && !armed.closed;
      },
      (stop) => {
        let armed = $transport_js.get_cell(cell);
        return $transport_js.set_cell(
          cell,
          new State(
            armed.label,
            armed.signaling,
            armed.ice_servers,
            armed.document,
            armed.transport,
            armed.peers,
            armed.subscriptions,
            armed.next_subscription,
            armed.on_status,
            armed.on_ready,
            armed.readiness,
            armed.roster,
            armed.bootstrap,
            armed.deferred,
            armed.imported,
            armed.attached,
            armed.closed,
            armed.policy,
            armed.sequencer,
            armed.relay,
            armed.phase,
            armed.path,
            armed.published,
            armed.resyncs + 1,
            new Some(stop),
            armed.nudge_dirty,
            armed.nudge_armed,
            armed.nudge_timer,
            armed.publish_owed,
            armed.scheduler,
            armed.anti_entropy_interval_milliseconds,
            armed.sync_armed,
            armed.sync_timer,
            armed.last_sync_digest,
            armed.repairs,
            armed.last_match,
            armed.digest_cache,
            armed.deadline,
            armed.recovered,
          ),
        );
      },
    );
  } else {
    return undefined;
  }
}

/**
 * Send the collected digest, when the document is still dirty and the relay is
 * still the delta path at the end of the interval. The function also publishes
 * what a peer merged into this document while the relay was primary. That
 * publication is the only route from that state to the relay.
 *
 * A lane that dropped in that interval already sent a `stateRequest` message to
 * its peers, which gives more than the digest, and that lane publishes
 * everything that it holds when it comes back. A document that a caller closed
 * has no peer to tell and no lane to publish on.
 *
 * The function sends to the mesh first. A publication that the module cannot
 * write retires the lane, and the fallback that follows sends a `stateRequest`
 * message to every peer. To send the digest first thus means that the peers
 * receive one message in both conditions, and not two messages or no
 * message.
 * 
 * @ignore
 */
function flush_nudge(cell) {
  let state = $transport_js.get_cell(cell);
  $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      false,
      false,
      Option$None$const,
      false,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
  let $ = state.closed;
  let $1 = state.nudge_dirty;
  if ($) {
    undefined;
  } else if ($1) {
    let $2 = state.path;
    let $3 = state.transport;
    if ($2 instanceof PeerToPeer) {
      undefined;
    } else if ($3 instanceof Some) {
      broadcast_digest(cell);
    } else {
      undefined;
    }
  } else {
    undefined;
  }
  let $2 = state.closed;
  let $3 = state.publish_owed;
  if (!$2 && $3) {
    return publish_while_primary(cell);
  } else {
    return undefined;
  }
}

/**
 * Anti-entropy for the mesh, while the relay carries the durable traffic.
 *
 * The module sends one `digest` message to every validated peer. A peer whose
 * digest matches answers nothing. A peer whose digest differs asks for the
 * state, and this replica serves that request from the same `crdt_core` path
 * as a bootstrap. Three kinds of replica thus converge: a `P2pOnly` replica, a
 * replica whose sequencer does not support this lane, and a replica that is
 * partitioned from the relay. No durable delta is duplicated onto the mesh,
 * and there is no second event, because a merge is idempotent and a `state`
 * message that changes nothing emits nothing.
 *
 * The module collects the digests over a named interval, and it does not send
 * one from inside the mutation that caused it. That choice is deliberate.
 *
 * A digest that arrives before the fan-out of the same delta from the relay
 * tells every peer that it is behind, at the exact moment at which that peer
 * stops being behind. The answer to such a digest is a full `state` transfer
 * across the mesh, for each mutation. A tick with no delay does not solve
 * that. A microtask, and one turn of the task queue, are both much faster than
 * a socket round trip, and either one collects the synchronous mutations
 * only.
 *
 * This function thus marks the document dirty, and it arms one flush
 * `default_anti_entropy_milliseconds` ahead, on the scheduler of the document.
 * That value is 250 ms, and a caller can replace it. Edits across many tasks
 * collect into that flush. The copy of each edit from the relay usually
 * reaches the peers first. A peer that the relay could not reach receives a
 * digest one quarter of a second later, instead of a stale digest immediately.
 * Continuous editing thus costs exactly one digest for each interval.
 *
 * This function is anti-entropy, and it is not repair. A failover does not use
 * it. The failover sends a `stateRequest` message to every peer, with the
 * fallback, and with no delay.
 * 
 * @ignore
 */
function nudge_peers(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.path;
  let $2 = state.transport;
  if ($) {
    if ($1 instanceof PeerToPeer) {
      return undefined;
    } else {
      return undefined;
    }
  } else if ($1 instanceof PeerToPeer) {
    return undefined;
  } else if ($2 instanceof Some) {
    let $3 = state.nudge_armed;
    if ($3) {
      return $transport_js.set_cell(
        cell,
        new State(
          state.label,
          state.signaling,
          state.ice_servers,
          state.document,
          state.transport,
          state.peers,
          state.subscriptions,
          state.next_subscription,
          state.on_status,
          state.on_ready,
          state.readiness,
          state.roster,
          state.bootstrap,
          state.deferred,
          state.imported,
          state.attached,
          state.closed,
          state.policy,
          state.sequencer,
          state.relay,
          state.phase,
          state.path,
          state.published,
          state.resyncs,
          state.resync_timer,
          true,
          state.nudge_armed,
          state.nudge_timer,
          state.publish_owed,
          state.scheduler,
          state.anti_entropy_interval_milliseconds,
          state.sync_armed,
          state.sync_timer,
          state.last_sync_digest,
          state.repairs,
          state.last_match,
          state.digest_cache,
          state.deadline,
          state.recovered,
        ),
      );
    } else {
      $transport_js.set_cell(
        cell,
        new State(
          state.label,
          state.signaling,
          state.ice_servers,
          state.document,
          state.transport,
          state.peers,
          state.subscriptions,
          state.next_subscription,
          state.on_status,
          state.on_ready,
          state.readiness,
          state.roster,
          state.bootstrap,
          state.deferred,
          state.imported,
          state.attached,
          state.closed,
          state.policy,
          state.sequencer,
          state.relay,
          state.phase,
          state.path,
          state.published,
          state.resyncs,
          state.resync_timer,
          true,
          true,
          state.nudge_timer,
          state.publish_owed,
          state.scheduler,
          state.anti_entropy_interval_milliseconds,
          state.sync_armed,
          state.sync_timer,
          state.last_sync_digest,
          state.repairs,
          state.last_match,
          state.digest_cache,
          state.deadline,
          state.recovered,
        ),
      );
      return $timer_js.arm(
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        () => { return flush_nudge(cell); },
        () => {
          let armed = $transport_js.get_cell(cell);
          return armed.nudge_armed && !armed.closed;
        },
        (stop) => {
          let armed = $transport_js.get_cell(cell);
          return $transport_js.set_cell(
            cell,
            new State(
              armed.label,
              armed.signaling,
              armed.ice_servers,
              armed.document,
              armed.transport,
              armed.peers,
              armed.subscriptions,
              armed.next_subscription,
              armed.on_status,
              armed.on_ready,
              armed.readiness,
              armed.roster,
              armed.bootstrap,
              armed.deferred,
              armed.imported,
              armed.attached,
              armed.closed,
              armed.policy,
              armed.sequencer,
              armed.relay,
              armed.phase,
              armed.path,
              armed.published,
              armed.resyncs,
              armed.resync_timer,
              armed.nudge_dirty,
              armed.nudge_armed,
              new Some(stop),
              armed.publish_owed,
              armed.scheduler,
              armed.anti_entropy_interval_milliseconds,
              armed.sync_armed,
              armed.sync_timer,
              armed.last_sync_digest,
              armed.repairs,
              armed.last_match,
              armed.digest_cache,
              armed.deadline,
              armed.recovered,
            ),
          );
        },
      );
    }
  } else {
    return undefined;
  }
}

/**
 * The relay is now the durable delta path.
 *
 * The function changes the path before it emits the status. A handler that
 * reads `effective_path` thus agrees with the status that it just received,
 * and a mutation from that handler takes the new route.
 * 
 * @ignore
 */
function relay_primary(cell, digest) {
  let state = $transport_js.get_cell(cell);
  cancel(state.resync_timer);
  cancel(state.deadline);
  cancel(state.sync_timer);
  $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      RelayPhase$RelayPrimaryPhase$const,
      TransportPath$Sequenced$const,
      state.published,
      0,
      Option$None$const,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      false,
      Option$None$const,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      Option$None$const,
      true,
    ),
  );
  let $ = state.relay;
  if ($ instanceof Some) {
    let relay = $[0];
    $crdt_sequencer_js.healthy(relay);
  } else {
    undefined;
  }
  emit(cell, new RelayPrimary(digest));
  resolve_ready(cell, new Ok(undefined));
  return nudge_peers(cell);
}

/**
 * The answer of the relay to an attestation.
 *
 * An echoed digest means that the whole content of the relay is the state that
 * this replica published. An empty echo means that the relay holds more, for
 * example a concurrent attachment or a delta that raced the publication. The
 * answer to an empty echo is to merge what arrives and to try again. The
 * answer is never to overwrite what the relay holds.
 *
 * While the relay is *primary*, the same echo answers a requested checkpoint.
 * The function reports it and does nothing more. The lane is already primary,
 * the document does not change in either condition, and an empty echo means
 * that the relay holds traffic that this replica published after the state.
 * The next request of the relay, which that same growth arms, asks about it
 * again. To retry here would be a loop of publications, with no bound, against
 * a busy room.
 * 
 * @ignore
 */
function relay_attested(cell, attested) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.phase;
  if ($) {
    return undefined;
  } else if ($1 instanceof RelayOff) {
    return undefined;
  } else if ($1 instanceof RelayOpening) {
    return undefined;
  } else if ($1 instanceof RelaySyncing) {
    let local = document_digest(cell);
    let $2 = (attested !== "") && (attested === state.published);
    let $3 = attested === local;
    if ($2) {
      if ($3) {
        return relay_primary(cell, local);
      } else {
        return publish_state(cell);
      }
    } else {
      return schedule_resync(cell);
    }
  } else if ($1 instanceof RelayPrimaryPhase) {
    let $2 = (attested !== "") && (attested === state.published);
    if ($2) {
      return emit(cell, new RelayCheckpointed(attested));
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

/**
 * Deliver each event to the subscribers of its own address. The function reads
 * the subscriber list again for each event, so a handler that removes its
 * subscription does not receive the next event.
 * 
 * @ignore
 */
function dispatch(cell, events) {
  return $list.each(
    events,
    (entry) => {
      let address$1 = entry[0];
      let event = entry[1];
      let _pipe = $transport_js.get_cell(cell).subscriptions;
      let _pipe$1 = $list.filter(
        _pipe,
        (subscriber) => { return subscriber.address === address$1; },
      );
      return $list.each(
        _pipe$1,
        (subscriber) => {
          return guard(
            () => { return subscriber.handler(event); },
            (detail) => {
              return emit(cell, new SubscriberFailed(address$1, detail));
            },
          );
        },
      );
    },
  );
}

/**
 * Send one message on the path that is durable now.
 *
 * While the relay is primary, that path is the relay. It is durable, and it
 * reaches a replica that this one has no peer connection to. The mesh stays
 * open below it, for the presence, the digests, the repair, and the failover,
 * which needs no negotiation.
 *
 * The module does *not* also push the durable message to the peers. That is
 * the meaning of "one durable path". It does push the digest of that message,
 * so a peer that is not on this relay learns that it is behind.
 *
 * A write that the relay could not make takes the mesh instead. That occurs
 * when the relay dropped between the mutation and this line, and when the
 * socket is no longer open. The module then drops the lane, and it does not
 * leave that lane with the appearance of health. A path that cannot carry a
 * delta is not the delta path.
 * 
 * @ignore
 */
function broadcast(cell, message) {
  let state = $transport_js.get_cell(cell);
  let $ = state.path;
  let $1 = state.relay;
  if ($ instanceof PeerToPeer) {
    return peer_broadcast(cell, message);
  } else if ($1 instanceof Some) {
    let $2 = relay_send(cell, message);
    if ($2) {
      return nudge_peers(cell);
    } else {
      relay_unwritable(cell);
      return peer_broadcast(cell, message);
    }
  } else {
    return peer_broadcast(cell, message);
  }
}

/**
 * `crdt_core.receive`, with the local digest from the cache, for the one
 * message that reads it.
 *
 * The module answers a `Digest` message by a comparison against the digest of
 * this document. The heartbeat makes the same comparison, in both directions.
 * Every other message computes no digest at all. This function reads the
 * document itself, and it does not take that document from its caller. The
 * value that it compares and the value that it compares against thus cannot
 * come from two different states.
 * 
 * @ignore
 */
function receive_envelope(cell, envelope) {
  let document = $transport_js.get_cell(cell).document;
  let $ = envelope.message;
  if ($ instanceof $crdt_wire.Hello) {
    return $crdt_core.receive(document, envelope);
  } else if ($ instanceof $crdt_wire.ChannelAnnounce) {
    return $crdt_core.receive(document, envelope);
  } else if ($ instanceof $crdt_wire.Delta) {
    return $crdt_core.receive(document, envelope);
  } else if ($ instanceof $crdt_wire.StateRequest) {
    return $crdt_core.receive(document, envelope);
  } else if ($ instanceof $crdt_wire.State) {
    return $crdt_core.receive(document, envelope);
  } else if ($ instanceof $crdt_wire.Digest) {
    return $crdt_core.receive_with_digest(
      document,
      envelope,
      document_digest(cell),
    );
  } else {
    return $crdt_core.receive(document, envelope);
  }
}

/**
 * One envelope that the relay carried.
 *
 * The `order` value of the relay never reaches this function. The lane removes
 * it, and what arrives is the encoded envelope of the author. The checks are
 * the same as for a peer, and so is the merge. The message-id window of
 * `crdt_core` suppresses a delta that arrived over WebRTC first, and a delta
 * that arrives here first suppresses the WebRTC copy. A duplicate is thus one
 * state change and one subscriber event, in either order.
 *
 * A refusal costs the envelope of the sender, and nothing else. Unlike a peer,
 * this module cannot close a relay client, and to close the lane would remove
 * that lane from every other replica on it, for one bad frame from one
 * replica. The `False` result of this function stops the high-water mark of
 * the lane from moving past something that this document did not merge. Without
 * that result, a later attestation could tell the relay to retire that
 * entry.
 * 
 * @ignore
 */
function relay_document(cell, raw) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return false;
  } else {
    let $1 = $crdt_wire.decode_envelope(raw, $crdt_core.limits(state.document));
    if ($1 instanceof Ok) {
      let envelope = $1[0];
      let $2 = receive_envelope(cell, envelope);
      if ($2 instanceof Ok) {
        let document = $2[0][0];
        let outcome = $2[0][1];
        let syncing = (state.phase instanceof RelaySyncing) && (state.published !== "");
        let previous = state.published;
        $transport_js.set_cell(
          cell,
          new State(
            state.label,
            state.signaling,
            state.ice_servers,
            document,
            state.transport,
            state.peers,
            state.subscriptions,
            state.next_subscription,
            state.on_status,
            state.on_ready,
            state.readiness,
            state.roster,
            state.bootstrap,
            state.deferred,
            state.imported,
            state.attached,
            state.closed,
            state.policy,
            state.sequencer,
            state.relay,
            state.phase,
            state.path,
            state.published,
            state.resyncs,
            state.resync_timer,
            state.nudge_dirty,
            state.nudge_armed,
            state.nudge_timer,
            state.publish_owed,
            state.scheduler,
            state.anti_entropy_interval_milliseconds,
            state.sync_armed,
            state.sync_timer,
            state.last_sync_digest,
            state.repairs,
            state.last_match,
            state.digest_cache,
            state.deadline,
            state.recovered,
          ),
        );
        $list.each(
          outcome.reply,
          (message) => {
            let $3 = relay_write(cell, message);
            
            return undefined;
          },
        );
        $list.each(
          outcome.broadcast,
          (message) => { return broadcast(cell, message); },
        );
        dispatch(cell, outcome.events);
        let $3 = (!(outcome.events instanceof $Empty)) || (!(outcome.created instanceof $Empty));
        if ($3) {
          nudge_peers(cell);
        } else {
          undefined;
        }
        let $4 = document_digest(cell) !== previous;
        if (syncing && $4) {
          publish_state(cell);
        } else {
          undefined;
        }
        return true;
      } else {
        let error = $2[0];
        emit(cell, new RelayRejected(envelope.from, error));
        return false;
      }
    } else {
      let error = $1[0];
      emit(cell, new RelayRejected("", error));
      return false;
    }
  }
}

/**
 * The relay announced `crdt_relay_v1`. Send the introduction of this replica,
 * and ask for everything that the relay holds. The module publishes nothing
 * until that reply completes, because a publication before it would give the
 * relay a state that did not merge the state of the room.
 *
 * A write that does not reach an open socket ends the attachment at that
 * point. To continue would leave this document in the `RelaySyncing` phase,
 * against a socket that cannot answer. There would then be no `synced`
 * message, no publication, no fallback, and no reconnect. That is the one
 * failure that this lane must never have.
 * 
 * @ignore
 */
function relay_attached(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return undefined;
  } else {
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        RelayPhase$RelaySyncing$const,
        state.path,
        "",
        0,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    emit(
      cell,
      (() => {
        let $1 = state.recovered;
        if ($1) {
          return Status$RelayRecovering$const;
        } else {
          return Status$RelaySyncingStatus$const;
        }
      })(),
    );
    let $1 = relay_write(cell, $crdt_core.hello_message(state.document));
    if ($1) {
      let $2 = state.relay;
      if ($2 instanceof Some) {
        let relay = $2[0];
        let $3 = $crdt_sequencer_js.declare_support(relay);
        
        undefined;
      } else {
        undefined;
      }
      let $3 = relay_write(cell, $crdt_core.state_request_message());
      
      return undefined;
    } else {
      return undefined;
    }
  }
}

/**
 * One relay connection attempt starts. This function runs for every attempt,
 * and not for the first one only. A reconnect sequence thus gives one
 * `RelayConnecting` status for each `RelayRetry` status. The status stream is
 * therefore a complete account of the actions of the lane.
 * 
 * @ignore
 */
function relay_connecting(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.sequencer;
  if ($) {
    return undefined;
  } else if ($1 instanceof Some) {
    let config$1 = $1[0];
    return emit(cell, new RelayConnecting(config$1.url));
  } else {
    return undefined;
  }
}

function relay_events(cell) {
  return new $crdt_sequencer_js.Events(
    () => { return relay_connecting(cell); },
    () => { return relay_attached(cell); },
    (raw) => { return relay_document(cell, raw); },
    () => { return publish_state(cell); },
    (digest) => { return relay_attested(cell, digest); },
    () => { return relay_checkpoint_requested(cell); },
    (detail) => { return relay_unsupported(cell, detail); },
    (detail) => { return relay_dropped(cell, detail); },
    (delay) => { return emit(cell, new RelayRetry(delay)); },
    (error) => { return emit(cell, new RelayFailed(error)); },
  );
}

/**
 * Open the configured relay, if the policy permits one.
 *
 * Nothing in this function can delay the readiness. `Auto` calls it *after*
 * the mesh has its opportunity to settle. The events of the relay resolve the
 * readiness for `SequencedOnly` only, and that policy has no other source.
 * 
 * @ignore
 */
function start_relay(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.policy;
  let $2 = state.sequencer;
  if ($) {
    return undefined;
  } else if ($1 instanceof P2pOnly) {
    return undefined;
  } else if ($2 instanceof Some) {
    let config$1 = $2[0];
    let relay = $crdt_sequencer_js.start(
      config$1.url,
      config$1.driver,
      state.scheduler,
      relay_events(cell),
    );
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        new Some(relay),
        RelayPhase$RelayOpening$const,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    return $crdt_sequencer_js.connect(relay);
  } else {
    return undefined;
  }
}

/**
 * Become ready when nothing remains to wait for. Three conditions must hold:
 * the membership of the room is completely known, no peer is still in a
 * negotiation, and no peer owes this replica a `state` transfer.
 *
 * The roster is the necessary condition. An adapter that learns its room over
 * a network round trip has announced no client when `join` returns. A replica
 * that read that condition as "the room is empty" would call back ready with
 * an empty document, a moment before the state of the room arrived. Every
 * late joiner would see that result.
 * 
 * @ignore
 */
function settle_readiness(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = resolved(state);
  let $1 = state.roster;
  if ($) {
    return undefined;
  } else if ($1) {
    let $2 = state.bootstrap;
    let $3 = state.transport;
    if ($2 instanceof Joining) {
      if ($3 instanceof Some) {
        let transport = $3[0];
        let $4 = $p2p_transport_js.known_peers(transport);
        if ($4 instanceof $Empty) {
          let state$1 = $transport_js.get_cell(cell);
          $transport_js.set_cell(
            cell,
            new State(
              state$1.label,
              state$1.signaling,
              state$1.ice_servers,
              state$1.document,
              state$1.transport,
              state$1.peers,
              state$1.subscriptions,
              state$1.next_subscription,
              state$1.on_status,
              state$1.on_ready,
              state$1.readiness,
              state$1.roster,
              BootstrapState$Bootstrapped$const,
              state$1.deferred,
              state$1.imported,
              state$1.attached,
              state$1.closed,
              state$1.policy,
              state$1.sequencer,
              state$1.relay,
              state$1.phase,
              state$1.path,
              state$1.published,
              state$1.resyncs,
              state$1.resync_timer,
              state$1.nudge_dirty,
              state$1.nudge_armed,
              state$1.nudge_timer,
              state$1.publish_owed,
              state$1.scheduler,
              state$1.anti_entropy_interval_milliseconds,
              state$1.sync_armed,
              state$1.sync_timer,
              state$1.last_sync_digest,
              state$1.repairs,
              state$1.last_match,
              state$1.digest_cache,
              state$1.deadline,
              state$1.recovered,
            ),
          );
          return resolve_ready(cell, new Ok(undefined));
        } else {
          return undefined;
        }
      } else {
        return undefined;
      }
    } else if ($2 instanceof WaitingForState) {
      return undefined;
    } else if ($3 instanceof Some) {
      let transport = $3[0];
      let $4 = $p2p_transport_js.known_peers(transport);
      if ($4 instanceof $Empty) {
        let state$1 = $transport_js.get_cell(cell);
        $transport_js.set_cell(
          cell,
          new State(
            state$1.label,
            state$1.signaling,
            state$1.ice_servers,
            state$1.document,
            state$1.transport,
            state$1.peers,
            state$1.subscriptions,
            state$1.next_subscription,
            state$1.on_status,
            state$1.on_ready,
            state$1.readiness,
            state$1.roster,
            BootstrapState$Bootstrapped$const,
            state$1.deferred,
            state$1.imported,
            state$1.attached,
            state$1.closed,
            state$1.policy,
            state$1.sequencer,
            state$1.relay,
            state$1.phase,
            state$1.path,
            state$1.published,
            state$1.resyncs,
            state$1.resync_timer,
            state$1.nudge_dirty,
            state$1.nudge_armed,
            state$1.nudge_timer,
            state$1.publish_owed,
            state$1.scheduler,
            state$1.anti_entropy_interval_milliseconds,
            state$1.sync_armed,
            state$1.sync_timer,
            state$1.last_sync_digest,
            state$1.repairs,
            state$1.last_match,
            state$1.digest_cache,
            state$1.deadline,
            state$1.recovered,
          ),
        );
        return resolve_ready(cell, new Ok(undefined));
      } else {
        return undefined;
      }
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

function request_state(cell, peer_id) {
  let state = $transport_js.get_cell(cell);
  $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      new WaitingForState(peer_id),
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
  emit(cell, new AwaitingState(peer_id));
  return send(cell, peer_id, $crdt_core.state_request_message());
}

/**
 * A peer that this replica bootstrapped from is gone. Ask the next validated
 * peer instead. If no peer remains, this replica is the whole room, and the
 * document that it already holds is ready.
 * 
 * @ignore
 */
function rebootstrap(cell, lost) {
  let state = $transport_js.get_cell(cell);
  let $ = resolved(state);
  let $1 = state.bootstrap;
  if ($) {
    if ($1 instanceof Joining) {
      return undefined;
    } else if ($1 instanceof WaitingForState) {
      return undefined;
    } else {
      return undefined;
    }
  } else if ($1 instanceof Joining) {
    return settle_readiness(cell);
  } else if ($1 instanceof WaitingForState) {
    let peer_id = $1.peer_id;
    if (peer_id === lost) {
      let $2 = greeted_peers(state);
      if ($2 instanceof $Empty) {
        $transport_js.set_cell(
          cell,
          new State(
            state.label,
            state.signaling,
            state.ice_servers,
            state.document,
            state.transport,
            state.peers,
            state.subscriptions,
            state.next_subscription,
            state.on_status,
            state.on_ready,
            state.readiness,
            state.roster,
            BootstrapState$Joining$const,
            state.deferred,
            state.imported,
            state.attached,
            state.closed,
            state.policy,
            state.sequencer,
            state.relay,
            state.phase,
            state.path,
            state.published,
            state.resyncs,
            state.resync_timer,
            state.nudge_dirty,
            state.nudge_armed,
            state.nudge_timer,
            state.publish_owed,
            state.scheduler,
            state.anti_entropy_interval_milliseconds,
            state.sync_armed,
            state.sync_timer,
            state.last_sync_digest,
            state.repairs,
            state.last_match,
            state.digest_cache,
            state.deadline,
            state.recovered,
          ),
        );
        return settle_readiness(cell);
      } else {
        let peer_id$1 = $2.head;
        return request_state(cell, peer_id$1);
      }
    } else {
      return settle_readiness(cell);
    }
  } else {
    return settle_readiness(cell);
  }
}

/**
 * Retire a peer. A second call has no more effect. Two routes reach this
 * function: the `PeerClosed` status of the transport, which covers every
 * announced peer, and the `on_peer_close` callback of that transport, which
 * covers the peers that opened only. The route that arrives first does the
 * work. The second one finds nothing to report, and it settles the readiness
 * again, which also has no more effect.
 * 
 * @ignore
 */
function handle_peer_close(cell, peer_id) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return undefined;
  } else {
    let $1 = $dict.has_key(state.peers, peer_id);
    if ($1) {
      $transport_js.set_cell(
        cell,
        new State(
          state.label,
          state.signaling,
          state.ice_servers,
          state.document,
          state.transport,
          $dict.delete$(state.peers, peer_id),
          state.subscriptions,
          state.next_subscription,
          state.on_status,
          state.on_ready,
          state.readiness,
          state.roster,
          state.bootstrap,
          state.deferred,
          state.imported,
          state.attached,
          state.closed,
          state.policy,
          state.sequencer,
          state.relay,
          state.phase,
          state.path,
          state.published,
          state.resyncs,
          state.resync_timer,
          state.nudge_dirty,
          state.nudge_armed,
          state.nudge_timer,
          state.publish_owed,
          state.scheduler,
          state.anti_entropy_interval_milliseconds,
          state.sync_armed,
          state.sync_timer,
          state.last_sync_digest,
          state.repairs,
          state.last_match,
          state.digest_cache,
          state.deadline,
          state.recovered,
        ),
      );
      emit(cell, new PeerGone(peer_id));
    } else {
      undefined;
    }
    refresh_sync(cell);
    return rebootstrap(cell, peer_id);
  }
}

/**
 * A peer moved this document while the relay carried its durability. The relay
 * thus needs the merged state.
 *
 * The module collects that publication onto the interval that the relay path
 * already has. It does not publish from inside the merge. A burst on the mesh
 * is thus one publication, and not one for each delta, and the digest for the
 * peers goes out in the same flush.
 *
 * The publication itself is the ordinary one: a `state` frame with an
 * attestation. The relay logs it, sends it to the replicas that this one
 * cannot see, and checkpoints it, exactly as it would for a publication that
 * this replica wrote.
 *
 * A merge that the relay carried does *not* come through this function, and
 * that is deliberate. The relay already holds what it sent, and a second
 * publication of it would make every client answer every publication with
 * another one.
 * 
 * @ignore
 */
function owe_publication(cell) {
  let state = $transport_js.get_cell(cell);
  $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      true,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
  return nudge_peers(cell);
}

/**
 * The `reason` and `detail` pair on the wire, which a refusal to a peer
 * carries. These strings are stable. A peer logs them, and a test asserts on
 * them.
 * 
 * @ignore
 */
function error_parts(error) {
  if (error instanceof $p2p.UnsupportedChannel) {
    let channel_type = error[0];
    return ["unsupportedChannel", $channel.type_to_string(channel_type)];
  } else if (error instanceof $p2p.RootMismatch) {
    let expected = error.expected;
    let received = error.received;
    return [
      "rootMismatch",
      (($channel.type_to_string(expected) + " expected, ") + $channel.type_to_string(
        received,
      )) + " offered",
    ];
  } else if (error instanceof $p2p.ChannelTypeMismatch) {
    let address$1 = error.address;
    let expected = error.expected;
    let received = error.received;
    return [
      "channelTypeMismatch",
      (((address$1 + " is ") + $channel.type_to_string(received)) + ", not ") + $channel.type_to_string(
        expected,
      ),
    ];
  } else if (error instanceof $p2p.DocumentClosed) {
    return ["documentClosed", ""];
  } else if (error instanceof $p2p.CompatibilityMismatch) {
    let expected = error.expected;
    let received = error.received;
    return [
      "compatibilityMismatch",
      ((expected + " expected, ") + received) + " offered",
    ];
  } else if (error instanceof $p2p.ProtocolMismatch) {
    let expected = error.expected;
    let received = error.received;
    return [
      "protocolMismatch",
      (("v" + $int.to_string(expected)) + " expected, v") + $int.to_string(
        received,
      ),
    ];
  } else if (error instanceof $p2p.RoomMismatch) {
    return ["roomMismatch", ""];
  } else if (error instanceof $p2p.RoomFull) {
    let limit = error.limit;
    return ["roomFull", $int.to_string(limit)];
  } else if (error instanceof $p2p.SignalingFailed) {
    let detail = error[0];
    return ["signalingFailed", detail];
  } else if (error instanceof $p2p.SequencerUnavailable) {
    let detail = error[0];
    return ["sequencerUnavailable", detail];
  } else if (error instanceof $p2p.SequencerUnsupported) {
    return ["sequencerUnsupported", ""];
  } else if (error instanceof $p2p.PeerConnectionFailed) {
    let peer_id = error.peer_id;
    let detail = error.detail;
    return ["peerConnectionFailed", (peer_id + ": ") + detail];
  } else if (error instanceof $p2p.InvalidEnvelope) {
    let peer_id = error.peer_id;
    let detail = error.detail;
    return ["invalidEnvelope", (peer_id + ": ") + detail];
  } else if (error instanceof $p2p.SnapshotTooLarge) {
    let bytes = error.bytes;
    let limit = error.limit;
    return [
      "snapshotTooLarge",
      ($int.to_string(bytes) + " bytes, limit ") + $int.to_string(limit),
    ];
  } else {
    let replica = error.replica_id;
    return ["replicaCollision", replica];
  }
}

/**
 * Close one peer for a protocol violation, and tell that peer the reason
 * first. The local document does not change, and every other peer continues. A
 * hostile peer, and a peer that does not match, each cost their own connection
 * and nothing else.
 * 
 * @ignore
 */
function reject_peer(cell, peer_id, error) {
  let $ = error_parts(error);
  let reason = $[0];
  let detail = $[1];
  send(cell, peer_id, $crdt_core.rejection_message(reason, detail));
  let state = $transport_js.get_cell(cell);
  $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      $dict.delete$(state.peers, peer_id),
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
  let $1 = state.transport;
  if ($1 instanceof Some) {
    let transport = $1[0];
    $p2p_transport_js.close_peer(transport, peer_id);
  } else {
    undefined;
  }
  emit(cell, new PeerRejected(peer_id, error));
  refresh_sync(cell);
  return rebootstrap(cell, peer_id);
}

/**
 * Merge one envelope that passed its checks. The function writes the document
 * before it sends anything, and before a subscriber runs. A callback that
 * throws thus cannot leave the document behind the state that its peers
 * believe that it holds.
 *
 * A merge that moves the canonical state while the *relay* is the durable path
 * also owes that state to the relay. No other route carries it. A received
 * message never fills `outcome.broadcast`. A delta or a channel that a
 * `P2pOnly` peer sent over WebRTC would thus converge across the mesh and
 * reach neither the history of the room, nor its checkpoint, nor a replica
 * that talks to the relay only.
 *
 * The function compares the digest across the merge, and it does not read
 * `outcome.events`. A merge can move the lattice with no event at all, for
 * example with an OR-Set tag or a 2P-Set tombstone. A state that the relay
 * does not hold is a state that the relay does not hold, whether or not a
 * subscriber would have seen it.
 * 
 * @ignore
 */
function merge(cell, peer_id, envelope, after) {
  let state = $transport_js.get_cell(cell);
  let durable = (state.path instanceof Sequenced) && (state.phase instanceof RelayPrimaryPhase);
  let _block;
  if (durable) {
    _block = document_digest(cell);
  } else {
    _block = "";
  }
  let before = _block;
  let $ = receive_envelope(cell, envelope);
  if ($ instanceof Ok) {
    let document = $[0][0];
    let outcome = $[0][1];
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    $list.each(
      outcome.reply,
      (message) => { return send(cell, peer_id, message); },
    );
    $list.each(
      outcome.broadcast,
      (message) => { return broadcast(cell, message); },
    );
    dispatch(cell, outcome.events);
    let $1 = durable && (document_digest(cell) !== before);
    if ($1) {
      owe_publication(cell);
    } else {
      undefined;
    }
    return after(outcome);
  } else {
    let error = $[0];
    return reject_peer(cell, peer_id, error);
  }
}

/**
 * Record what the digest of a peer told this replica. An empty outcome is a
 * match, which means that the two already agree, so the module keeps that
 * digest as the last successful comparison. A `stateRequest` reply means that
 * this replica was behind, and `merge` already asked for the state. The module
 * counts the repair when that state arrives and moves the document, and not
 * here. A request that no peer answers thus adds nothing to the count.
 * 
 * @ignore
 */
function record_peer_digest(cell, remote, outcome) {
  let state = $transport_js.get_cell(cell);
  let $ = outcome.reply;
  if ($ instanceof $Empty) {
    return $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        new Some(remote),
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
  } else {
    return $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        "",
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
  }
}

/**
 * A `state` transfer merged.
 *
 * Any such transfer settles a bootstrap that still waits, and not the transfer
 * from the first peer that this replica asked only. The module sends a
 * `stateRequest` message to every peer that greeted it, and every one of those
 * peers answers. A replica that merged the state of a room is thus
 * bootstrapped, whichever answer arrived. To tie the readiness to one peer
 * would let a peer that greets and then sends nothing hold a joining client on
 * its loading screen, while the rest of the room synchronized that client.
 * 
 * @ignore
 */
function state_merged(cell, peer_id, channels) {
  emit(cell, new StateMerged(peer_id, channels));
  let state = $transport_js.get_cell(cell);
  let $ = resolved(state);
  if ($) {
    return undefined;
  } else {
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        BootstrapState$Bootstrapped$const,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    return resolve_ready(cell, new Ok(undefined));
  }
}

/**
 * Count one completed partition repair, which is a catch-up `state` message
 * that changed the canonical state of this replica.
 * 
 * @ignore
 */
function note_repair(cell) {
  let state = $transport_js.get_cell(cell);
  return $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      state.subscriptions,
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs + 1,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
}

function greet(cell, peer_id) {
  let state = $transport_js.get_cell(cell);
  let $ = $dict.get(state.peers, peer_id);
  if ($ instanceof Ok) {
    let peer = $[0];
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        $dict.insert(state.peers, peer_id, new Peer(peer.id, true)),
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    emit(cell, new PeerReady(peer_id));
    let $1 = resolved(state);
    let $2 = state.bootstrap;
    if ($1) {
      if ($2 instanceof Joining) {
        send(cell, peer_id, $crdt_core.state_request_message());
      } else if ($2 instanceof WaitingForState) {
        send(cell, peer_id, $crdt_core.state_request_message());
      } else {
        send(cell, peer_id, $crdt_core.state_request_message());
      }
    } else if ($2 instanceof Joining) {
      request_state(cell, peer_id);
    } else if ($2 instanceof WaitingForState) {
      send(cell, peer_id, $crdt_core.state_request_message());
    } else {
      send(cell, peer_id, $crdt_core.state_request_message());
    }
    let $3 = $transport_js.get_cell(cell).path;
    if ($3 instanceof PeerToPeer) {
      undefined;
    } else {
      send(cell, peer_id, digest_message(cell));
    }
    return refresh_sync(cell);
  } else {
    return undefined;
  }
}

function route(cell, peer, envelope) {
  let $ = envelope.message;
  let $1 = peer.greeted;
  if ($1) {
    if ($ instanceof $crdt_wire.Hello) {
      return undefined;
    } else if ($ instanceof $crdt_wire.State) {
      let entries = $.entries;
      let before = document_digest(cell);
      return merge(
        cell,
        peer.id,
        envelope,
        (_) => {
          let after = document_digest(cell);
          let $2 = before !== after;
          if ($2) {
            note_repair(cell);
          } else {
            undefined;
          }
          return state_merged(cell, peer.id, $list.length(entries));
        },
      );
    } else if ($ instanceof $crdt_wire.Digest) {
      let remote = $.digest;
      return merge(
        cell,
        peer.id,
        envelope,
        (outcome) => { return record_peer_digest(cell, remote, outcome); },
      );
    } else if ($ instanceof $crdt_wire.Rejected) {
      let reason = $.reason;
      let detail = $.detail;
      return merge(
        cell,
        peer.id,
        envelope,
        (_) => {
          return emit(cell, new RejectedByPeer(peer.id, reason, detail));
        },
      );
    } else {
      return merge(cell, peer.id, envelope, (_) => { return undefined; });
    }
  } else if ($ instanceof $crdt_wire.Hello) {
    return merge(
      cell,
      peer.id,
      envelope,
      (_) => { return greet(cell, peer.id); },
    );
  } else {
    return reject_peer(
      cell,
      peer.id,
      new $p2p.InvalidEnvelope(
        peer.id,
        ("sent " + $crdt_wire.message_type(envelope.message)) + " before hello",
      ),
    );
  }
}

/**
 * One payload from the data channel of one peer. Every check that can refuse
 * that payload runs before the module asks `crdt_core` to merge anything.
 * 
 * @ignore
 */
function handle_document(cell, peer_id, raw) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = $dict.get(state.peers, peer_id);
  if ($) {
    return undefined;
  } else if ($1 instanceof Ok) {
    let peer = $1[0];
    let $2 = $crdt_wire.decode_envelope(raw, $crdt_core.limits(state.document));
    if ($2 instanceof Ok) {
      let envelope = $2[0];
      let $3 = envelope.from === peer_id;
      if ($3) {
        return route(cell, peer, envelope);
      } else {
        return reject_peer(
          cell,
          peer_id,
          new $p2p.InvalidEnvelope(
            peer_id,
            "envelope claims to be from " + envelope.from,
          ),
        );
      }
    } else {
      let error = $2[0];
      return reject_peer(cell, peer_id, error);
    }
  } else {
    return undefined;
  }
}

/**
 * The document channel of a peer is open. Send the introduction of this
 * replica. The module can send nothing else until the `hello` message of that
 * peer arrives and passes its checks.
 * 
 * @ignore
 */
function handle_peer_open(cell, peer_id) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return undefined;
  } else {
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        $dict.insert(state.peers, peer_id, new Peer(peer_id, false)),
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    return send(cell, peer_id, $crdt_core.hello_message(state.document));
  }
}

function run_deferred(cell, entry) {
  if (entry instanceof DeferredOpen) {
    let peer_id = entry.peer_id;
    return handle_peer_open(cell, peer_id);
  } else if (entry instanceof DeferredDocument) {
    let peer_id = entry.peer_id;
    let payload = entry.payload;
    return handle_document(cell, peer_id, payload);
  } else {
    let peer_id = entry.peer_id;
    return handle_peer_close(cell, peer_id);
  }
}

/**
 * Remove one attach attempt, and keep the document itself.
 *
 * The local state, the handles, and the subscriptions all stay. The function
 * clears the transport code and the callbacks of that attempt only. A caller
 * can thus continue to edit offline, and it can call `attach` again later.
 * 
 * @ignore
 */
function mark_detached(cell) {
  let state = $transport_js.get_cell(cell);
  cancel(state.resync_timer);
  cancel(state.nudge_timer);
  cancel(state.sync_timer);
  cancel(state.deadline);
  return $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      Option$None$const,
      $dict.new$(),
      state.subscriptions,
      state.next_subscription,
      (_) => { return undefined; },
      (_) => { return undefined; },
      Option$None$const,
      false,
      BootstrapState$Joining$const,
      $List$Empty$const,
      state.imported,
      false,
      state.closed,
      state.policy,
      state.sequencer,
      Option$None$const,
      RelayPhase$RelayOff$const,
      TransportPath$PeerToPeer$const,
      "",
      0,
      Option$None$const,
      false,
      false,
      Option$None$const,
      false,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      false,
      Option$None$const,
      "",
      state.repairs,
      Option$None$const,
      state.digest_cache,
      Option$None$const,
      state.recovered,
    ),
  );
}

/**
 * A synchronous failure at startup ends that attempt only, for a restored
 * snapshot. A document that the module just built keeps the earlier
 * fail-closed behaviour.
 * 
 * @ignore
 */
function fail_attach_attempt(cell, error) {
  let state = $transport_js.get_cell(cell);
  let $ = state.imported;
  if ($) {
    mark_detached(cell);
    contained(() => { return state.on_status(new Failed(error)); });
    return contained(() => { return state.on_ready(new Error(error)); });
  } else {
    mark_closed(cell);
    return resolve_ready(cell, new Error(error));
  }
}

/**
 * Run a transport callback now, or hold it until `attach` stores the transport
 * that the callback needs to answer with. An adapter that opens a channel from
 * inside `join` is unusual, and it is valid. The module must drop nothing that
 * such an adapter delivers.
 * 
 * @ignore
 */
function defer(cell, entry) {
  let state = $transport_js.get_cell(cell);
  let $ = state.transport;
  if ($ instanceof Some) {
    return run_deferred(cell, entry);
  } else {
    return $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        state.roster,
        state.bootstrap,
        listPrepend(entry, state.deferred),
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
  }
}

/**
 * The complete membership of the room arrived. The function records it, and
 * the module has not always stored the transport at that point, because an
 * adapter can report the roster from inside `join`. `attach` then settles the
 * readiness after it stores the transport.
 * 
 * @ignore
 */
function note_roster(cell, peers) {
  let state = $transport_js.get_cell(cell);
  let $ = state.roster;
  if ($) {
    return undefined;
  } else {
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        state.on_status,
        state.on_ready,
        state.readiness,
        true,
        state.bootstrap,
        state.deferred,
        state.imported,
        state.attached,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    emit(cell, new RosterKnown(peers));
    return settle_readiness(cell);
  }
}

function callbacks(cell) {
  return new $p2p_transport_js.Callbacks(
    (peer_id) => { return defer(cell, new DeferredOpen(peer_id)); },
    (peer_id) => { return defer(cell, new DeferredClose(peer_id)); },
    (peer_id, payload) => {
      return defer(cell, new DeferredDocument(peer_id, payload));
    },
    (status) => {
      emit(cell, new Transport(status));
      if (status instanceof $p2p_transport_js.SignalingJoined) {
        return undefined;
      } else if (status instanceof $p2p_transport_js.SignalingRoster) {
        let peers$1 = status.peers;
        return note_roster(cell, peers$1);
      } else if (status instanceof $p2p_transport_js.SignalingLeft) {
        return undefined;
      } else if (status instanceof $p2p_transport_js.PeerConnecting) {
        return undefined;
      } else if (status instanceof $p2p_transport_js.PeerOpen) {
        return undefined;
      } else if (status instanceof $p2p_transport_js.PeerClosed) {
        let peer_id = status.peer_id;
        return defer(cell, new DeferredClose(peer_id));
      } else if (status instanceof $p2p_transport_js.PeerFailed) {
        return undefined;
      } else if (status instanceof $p2p_transport_js.IceState) {
        return undefined;
      } else {
        return undefined;
      }
    },
    (error) => {
      emit(cell, new TransportError(error));
      if (error instanceof $p2p.UnsupportedChannel) {
        return undefined;
      } else if (error instanceof $p2p.RootMismatch) {
        return undefined;
      } else if (error instanceof $p2p.ChannelTypeMismatch) {
        return undefined;
      } else if (error instanceof $p2p.DocumentClosed) {
        return undefined;
      } else if (error instanceof $p2p.CompatibilityMismatch) {
        return undefined;
      } else if (error instanceof $p2p.ProtocolMismatch) {
        return undefined;
      } else if (error instanceof $p2p.RoomMismatch) {
        return undefined;
      } else if (error instanceof $p2p.RoomFull) {
        return undefined;
      } else if (error instanceof $p2p.SignalingFailed) {
        return resolve_ready(cell, new Error(error));
      } else if (error instanceof $p2p.SequencerUnavailable) {
        return undefined;
      } else if (error instanceof $p2p.SequencerUnsupported) {
        return undefined;
      } else if (error instanceof $p2p.PeerConnectionFailed) {
        return undefined;
      } else if (error instanceof $p2p.InvalidEnvelope) {
        return undefined;
      } else if (error instanceof $p2p.SnapshotTooLarge) {
        return undefined;
      } else {
        return undefined;
      }
    },
  );
}

/**
 * Arm the readiness deadline of `SequencedOnly`.
 *
 * The deadline bounds the whole attachment, which is the socket, the
 * capability, the state replay, and the digest. It does not bound one step of
 * that attachment, because a caller that waits on `on_ready` does not need to
 * know which step is slow.
 * 
 * @ignore
 */
function arm_deadline(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.sequencer;
  if ($ instanceof Some) {
    let config$1 = $[0];
    let $1 = config$1.readiness_deadline_milliseconds > 0;
    if ($1) {
      return $timer_js.arm(
        state.scheduler,
        config$1.readiness_deadline_milliseconds,
        () => {
          return abandon(
            cell,
            new $p2p.SequencerUnavailable(
              ("the sequencer did not become the durable path within " + $int.to_string(
                config$1.readiness_deadline_milliseconds,
              )) + "ms",
            ),
          );
        },
        () => {
          let armed = $transport_js.get_cell(cell);
          return !armed.closed && !resolved(armed);
        },
        (stop) => {
          let armed = $transport_js.get_cell(cell);
          return $transport_js.set_cell(
            cell,
            new State(
              armed.label,
              armed.signaling,
              armed.ice_servers,
              armed.document,
              armed.transport,
              armed.peers,
              armed.subscriptions,
              armed.next_subscription,
              armed.on_status,
              armed.on_ready,
              armed.readiness,
              armed.roster,
              armed.bootstrap,
              armed.deferred,
              armed.imported,
              armed.attached,
              armed.closed,
              armed.policy,
              armed.sequencer,
              armed.relay,
              armed.phase,
              armed.path,
              armed.published,
              armed.resyncs,
              armed.resync_timer,
              armed.nudge_dirty,
              armed.nudge_armed,
              armed.nudge_timer,
              armed.publish_owed,
              armed.scheduler,
              armed.anti_entropy_interval_milliseconds,
              armed.sync_armed,
              armed.sync_timer,
              armed.last_sync_digest,
              armed.repairs,
              armed.last_match,
              armed.digest_cache,
              new Some(stop),
              armed.recovered,
            ),
          );
        },
      );
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

/**
 * `attach` against a replacement browser seam. A test can thus drive the
 * bootstrap order, a handshake refusal, and the merge behaviour
 * deterministically, and it needs no browser. This is the same seam that
 * `p2p_transport_js.start_with_rtc` gives, for the same reason.
 */
export function attach_with_rtc(document, on_ready, on_status, rtc) {
  let cell = document.cell;
  let state = $transport_js.get_cell(cell);
  let room$1 = $crdt_core.room(state.document);
  let replica = $crdt_core.replica(state.document);
  let $ = state.closed;
  let $1 = state.attached;
  if ($) {
    contained(
      () => { return on_status(new Failed($p2p.P2pError$DocumentClosed$const)); },
    );
    contained(
      () => { return on_ready(new Error($p2p.P2pError$DocumentClosed$const)); },
    );
    return new CrdtConnection(Option$None$const);
  } else if ($1) {
    let error = new $p2p.InvalidEnvelope(
      replica,
      "document is already attached to a connection",
    );
    contained(() => { return on_status(new Failed(error)); });
    contained(() => { return on_ready(new Error(error)); });
    return new CrdtConnection(Option$None$const);
  } else {
    $transport_js.set_cell(
      cell,
      new State(
        state.label,
        state.signaling,
        state.ice_servers,
        state.document,
        state.transport,
        state.peers,
        state.subscriptions,
        state.next_subscription,
        on_status,
        (outcome) => {
          if (outcome instanceof Ok) {
            return on_ready(new Ok(document));
          } else {
            let error = outcome[0];
            return on_ready(new Error(error));
          }
        },
        state.readiness,
        state.roster,
        state.bootstrap,
        state.deferred,
        state.imported,
        true,
        state.closed,
        state.policy,
        state.sequencer,
        state.relay,
        state.phase,
        state.path,
        state.published,
        state.resyncs,
        state.resync_timer,
        state.nudge_dirty,
        state.nudge_armed,
        state.nudge_timer,
        state.publish_owed,
        state.scheduler,
        state.anti_entropy_interval_milliseconds,
        state.sync_armed,
        state.sync_timer,
        state.last_sync_digest,
        state.repairs,
        state.last_match,
        state.digest_cache,
        state.deadline,
        state.recovered,
      ),
    );
    emit(cell, new Joined(room$1, replica));
    let $2 = state.policy;
    if ($2 instanceof Auto) {
      let $3 = $p2p_transport_js.start_with_rtc(
        room$1,
        replica,
        state.signaling,
        state.ice_servers,
        callbacks(cell),
        rtc,
      );
      if ($3 instanceof Ok) {
        let transport = $3[0];
        let joined = $transport_js.get_cell(cell);
        $transport_js.set_cell(
          cell,
          new State(
            joined.label,
            joined.signaling,
            joined.ice_servers,
            joined.document,
            new Some(transport),
            joined.peers,
            joined.subscriptions,
            joined.next_subscription,
            joined.on_status,
            joined.on_ready,
            joined.readiness,
            joined.roster,
            joined.bootstrap,
            $List$Empty$const,
            joined.imported,
            joined.attached,
            joined.closed,
            joined.policy,
            joined.sequencer,
            joined.relay,
            joined.phase,
            joined.path,
            joined.published,
            joined.resyncs,
            joined.resync_timer,
            joined.nudge_dirty,
            joined.nudge_armed,
            joined.nudge_timer,
            joined.publish_owed,
            joined.scheduler,
            joined.anti_entropy_interval_milliseconds,
            joined.sync_armed,
            joined.sync_timer,
            joined.last_sync_digest,
            joined.repairs,
            joined.last_match,
            joined.digest_cache,
            joined.deadline,
            joined.recovered,
          ),
        );
        $list.each(
          $list.reverse(joined.deferred),
          (entry) => { return run_deferred(cell, entry); },
        );
        settle_readiness(cell);
        start_relay(cell);
        return new CrdtConnection(new Some(cell));
      } else {
        let error = $3[0];
        fail_attach_attempt(cell, error);
        return new CrdtConnection(Option$None$const);
      }
    } else if ($2 instanceof SequencedOnly) {
      let $3 = state.sequencer;
      if ($3 instanceof Some) {
        arm_deadline(cell);
        start_relay(cell);
        return new CrdtConnection(new Some(cell));
      } else {
        let error = new $p2p.SequencerUnavailable(
          "sequencedOnly needs a sequencer, and none was configured",
        );
        fail_attach_attempt(cell, error);
        return new CrdtConnection(Option$None$const);
      }
    } else {
      let $3 = $p2p_transport_js.start_with_rtc(
        room$1,
        replica,
        state.signaling,
        state.ice_servers,
        callbacks(cell),
        rtc,
      );
      if ($3 instanceof Ok) {
        let transport = $3[0];
        let joined = $transport_js.get_cell(cell);
        $transport_js.set_cell(
          cell,
          new State(
            joined.label,
            joined.signaling,
            joined.ice_servers,
            joined.document,
            new Some(transport),
            joined.peers,
            joined.subscriptions,
            joined.next_subscription,
            joined.on_status,
            joined.on_ready,
            joined.readiness,
            joined.roster,
            joined.bootstrap,
            $List$Empty$const,
            joined.imported,
            joined.attached,
            joined.closed,
            joined.policy,
            joined.sequencer,
            joined.relay,
            joined.phase,
            joined.path,
            joined.published,
            joined.resyncs,
            joined.resync_timer,
            joined.nudge_dirty,
            joined.nudge_armed,
            joined.nudge_timer,
            joined.publish_owed,
            joined.scheduler,
            joined.anti_entropy_interval_milliseconds,
            joined.sync_armed,
            joined.sync_timer,
            joined.last_sync_digest,
            joined.repairs,
            joined.last_match,
            joined.digest_cache,
            joined.deadline,
            joined.recovered,
          ),
        );
        $list.each(
          $list.reverse(joined.deferred),
          (entry) => { return run_deferred(cell, entry); },
        );
        settle_readiness(cell);
        start_relay(cell);
        return new CrdtConnection(new Some(cell));
      } else {
        let error = $3[0];
        fail_attach_attempt(cell, error);
        return new CrdtConnection(Option$None$const);
      }
    }
  }
}

/**
 * Join a room with a document that already exists. `connect` uses this
 * function internally, and it is also the way to bring the result of
 * `import_snapshot` online.
 *
 * The document keeps its cell. A handle and a subscription that you took
 * before the attach thus stay valid. The channels of the snapshot go to the
 * peers in the ordinary `state` exchange. A synchronous refusal at startup
 * leaves a restored snapshot detached, so its local state stays editable and
 * the caller can try again.
 */
export function attach(document, on_ready, on_status) {
  return attach_with_rtc(
    document,
    on_ready,
    on_status,
    $p2p_transport_js.real_rtc(),
  );
}

/**
 * Build the configured document and join its room.
 *
 * The function returns after it asks the signaling service to join.
 * `on_ready` runs exactly one time. The module docs describe the conditions.
 * `on_status` runs for the whole life of the connection.
 */
export function connect(config, on_ready, on_status) {
  let $ = new_document(config);
  if ($ instanceof Ok) {
    let document = $[0];
    return attach(document, on_ready, on_status);
  } else {
    let error = $[0];
    contained(() => { return on_status(new Failed(error)); });
    contained(() => { return on_ready(new Error(error)); });
    return new CrdtConnection(Option$None$const);
  }
}

/**
 * Leave the signaling room, close every peer, and stop the document from
 * accepting a read or a write. A second call has no more effect.
 *
 * A close before the readiness resolves `on_ready` one time, with
 * `Error(DocumentClosed)`. A caller that waits on that callback needs an
 * answer, also when the answer is that the module abandoned the document.
 */
export function close(connection) {
  let $ = connection.cell;
  if ($ instanceof Some) {
    let cell = $[0];
    let state = $transport_js.get_cell(cell);
    let $1 = state.closed;
    if ($1) {
      return undefined;
    } else {
      mark_closed(cell);
      let $2 = state.transport;
      if ($2 instanceof Some) {
        let transport = $2[0];
        $p2p_transport_js.close(transport);
      } else {
        undefined;
      }
      let $3 = state.relay;
      if ($3 instanceof Some) {
        let relay = $3[0];
        $crdt_sequencer_js.close(relay);
      } else {
        undefined;
      }
      return resolve_ready(cell, new Error($p2p.P2pError$DocumentClosed$const));
    }
  } else {
    return undefined;
  }
}

/**
 * Subscribe to every event on one channel, of every kind. The typed wrapper of
 * each kind, below, is the usual entry point.
 */
export function subscribe(handle, handler) {
  let cell = handle.cell;
  let state = $transport_js.get_cell(cell);
  let id = state.next_subscription;
  $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      listPrepend(
        new Subscriber(id, handle.address, handler),
        state.subscriptions,
      ),
      id + 1,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
  return new Subscription(cell, id);
}

/**
 * Remove a subscription. A second call has no more effect.
 */
export function unsubscribe(subscription) {
  let cell = subscription.cell;
  let state = $transport_js.get_cell(cell);
  return $transport_js.set_cell(
    cell,
    new State(
      state.label,
      state.signaling,
      state.ice_servers,
      state.document,
      state.transport,
      state.peers,
      $list.filter(
        state.subscriptions,
        (subscriber) => { return subscriber.id !== subscription.id; },
      ),
      state.next_subscription,
      state.on_status,
      state.on_ready,
      state.readiness,
      state.roster,
      state.bootstrap,
      state.deferred,
      state.imported,
      state.attached,
      state.closed,
      state.policy,
      state.sequencer,
      state.relay,
      state.phase,
      state.path,
      state.published,
      state.resyncs,
      state.resync_timer,
      state.nudge_dirty,
      state.nudge_armed,
      state.nudge_timer,
      state.publish_owed,
      state.scheduler,
      state.anti_entropy_interval_milliseconds,
      state.sync_armed,
      state.sync_timer,
      state.last_sync_digest,
      state.repairs,
      state.last_match,
      state.digest_cache,
      state.deadline,
      state.recovered,
    ),
  );
}

function subscribe_narrowed(handle, handler, narrow) {
  return subscribe(
    handle,
    (event) => {
      let $ = narrow(event);
      if ($ instanceof Some) {
        let narrowed = $[0];
        return handler(narrowed);
      } else {
        return undefined;
      }
    },
  );
}

export function subscribe_pn_counter(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function subscribe_or_map(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function subscribe_or_set(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function subscribe_g_set(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function subscribe_two_p_set(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function subscribe_sequence(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function subscribe_text(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        let inner = event[0];
        return new Some(inner);
      }
    },
  );
}

/**
 * The root of the document, typed by the `CrdtKind` value that the config
 * named.
 */
export function root(document) {
  return new Handle(document.cell, $crdt_wire.root_address);
}

/**
 * The channel address of a handle. The value is `root` for the root. For every
 * other channel it is `<replica>:<counter>`, which names the creator of that
 * channel.
 */
export function address(handle) {
  return handle.address;
}

function usable(cell, state) {
  let $ = state.closed;
  if ($) {
    emit(cell, new Failed($p2p.P2pError$DocumentClosed$const));
    return new Error($p2p.P2pError$DocumentClosed$const);
  } else {
    return new Ok(undefined);
  }
}

/**
 * Register a new channel of the kind `kind`, and announce it to every peer.
 * The function checks that kind against the eligibility boundary. A channel
 * that cannot merge without a sequencer is thus refused here, and the replicas
 * do not diverge later.
 */
export function create_channel(document, kind) {
  let cell = document.cell;
  let state = $transport_js.get_cell(cell);
  return $result.try$(
    usable(cell, state),
    (_) => {
      let $ = $crdt_core.create_channel(state.document, $p2p.kind_init(kind));
      if ($ instanceof Ok) {
        let core = $[0][0];
        let outcome = $[0][1];
        $transport_js.set_cell(
          cell,
          new State(
            state.label,
            state.signaling,
            state.ice_servers,
            core,
            state.transport,
            state.peers,
            state.subscriptions,
            state.next_subscription,
            state.on_status,
            state.on_ready,
            state.readiness,
            state.roster,
            state.bootstrap,
            state.deferred,
            state.imported,
            state.attached,
            state.closed,
            state.policy,
            state.sequencer,
            state.relay,
            state.phase,
            state.path,
            state.published,
            state.resyncs,
            state.resync_timer,
            state.nudge_dirty,
            state.nudge_armed,
            state.nudge_timer,
            state.publish_owed,
            state.scheduler,
            state.anti_entropy_interval_milliseconds,
            state.sync_armed,
            state.sync_timer,
            state.last_sync_digest,
            state.repairs,
            state.last_match,
            state.digest_cache,
            state.deadline,
            state.recovered,
          ),
        );
        $list.each(
          outcome.broadcast,
          (message) => { return broadcast(cell, message); },
        );
        let $1 = outcome.created;
        if ($1 instanceof $Empty) {
          let error = new $p2p.InvalidEnvelope(
            $crdt_core.replica(core),
            "channel creation announced no descriptor",
          );
          emit(cell, new Failed(error));
          return new Error(error);
        } else {
          let descriptor = $1.head;
          return new Ok(new Handle(cell, descriptor.address));
        }
      } else {
        let error = $[0];
        emit(cell, new Failed(error));
        return new Error(error);
      }
    },
  );
}

/**
 * Report a local operation that failed, on the status stream, and also return
 * that failure. A status log is thus a complete account of the document.
 * 
 * @ignore
 */
function fail(cell, outcome) {
  if (outcome instanceof Ok) {
    return outcome;
  } else {
    let error = outcome[0];
    emit(cell, new Failed(error));
    return new Error(error);
  }
}

/**
 * Take a typed handle onto a channel that exists. That channel is one that a
 * peer announced, or one that an imported snapshot carried. The address must be
 * registered, and its channel type must be exactly `kind`.
 */
export function resolve_channel(document, kind, address) {
  let cell = document.cell;
  let state = $transport_js.get_cell(cell);
  return $result.try$(
    usable(cell, state),
    (_) => {
      return $result.try$(
        fail(cell, $crdt_core.channel_type(state.document, address)),
        (found) => {
          let expected = $p2p.kind_type(kind);
          let $ = isEqual(found, expected);
          if ($) {
            return new Ok(new Handle(cell, address));
          } else {
            let error = new $p2p.ChannelTypeMismatch(address, expected, found);
            emit(cell, new Failed(error));
            return new Error(error);
          }
        },
      );
    },
  );
}

/**
 * Every channel address that this document holds, in canonical order.
 */
export function addresses(document) {
  let _pipe = $crdt_core.descriptors(
    $transport_js.get_cell(document.cell).document,
  );
  return $list.map(_pipe, (descriptor) => { return descriptor.address; });
}

function read(handle, expected, reader) {
  let cell = handle.cell;
  let state = $transport_js.get_cell(cell);
  return $result.try$(
    usable(cell, state),
    (_) => {
      return $result.try$(
        fail(cell, $crdt_core.channel_state(state.document, handle.address)),
        (channel_state) => {
          let found = $channel.channel_type(channel_state);
          let $ = isEqual(found, expected);
          if ($) {
            return new Ok(reader(channel_state));
          } else {
            let error = new $p2p.ChannelTypeMismatch(
              handle.address,
              expected,
              found,
            );
            emit(cell, new Failed(error));
            return new Error(error);
          }
        },
      );
    },
  );
}

/**
 * Write a local edit. The function merges it into the visible state
 * immediately, broadcasts it to every open peer, and reports it to the
 * subscribers of this address one time.
 * 
 * @ignore
 */
function mutate(handle, edit) {
  let cell = handle.cell;
  let state = $transport_js.get_cell(cell);
  return $result.try$(
    usable(cell, state),
    (_) => {
      return $result.try$(
        fail(cell, $crdt_core.edit(state.document, handle.address, edit)),
        (_use0) => {
          let core = _use0[0];
          let outcome = _use0[1];
          $transport_js.set_cell(
            cell,
            new State(
              state.label,
              state.signaling,
              state.ice_servers,
              core,
              state.transport,
              state.peers,
              state.subscriptions,
              state.next_subscription,
              state.on_status,
              state.on_ready,
              state.readiness,
              state.roster,
              state.bootstrap,
              state.deferred,
              state.imported,
              state.attached,
              state.closed,
              state.policy,
              state.sequencer,
              state.relay,
              state.phase,
              state.path,
              state.published,
              state.resyncs,
              state.resync_timer,
              state.nudge_dirty,
              state.nudge_armed,
              state.nudge_timer,
              state.publish_owed,
              state.scheduler,
              state.anti_entropy_interval_milliseconds,
              state.sync_armed,
              state.sync_timer,
              state.last_sync_digest,
              state.repairs,
              state.last_match,
              state.digest_cache,
              state.deadline,
              state.recovered,
            ),
          );
          $list.each(
            outcome.broadcast,
            (message) => { return broadcast(cell, message); },
          );
          dispatch(cell, outcome.events);
          return new Ok(undefined);
        },
      );
    },
  );
}

export function mv_register_set(handle, value) {
  return mutate(handle, new $channel.MvRegisterEdit(value));
}

export function mv_register_values(handle) {
  let values = read(
    handle,
    $channel.ChannelType$MvRegisterChannel$const,
    (state) => {
      if (state instanceof $channel.MvRegisterState) {
        let kernel = state[0];
        return new Ok($mv_register_kernel.values(kernel));
      } else {
        let other = state;
        return new Error(
          new $p2p.ChannelTypeMismatch(
            handle.address,
            $channel.ChannelType$MvRegisterChannel$const,
            $channel.channel_type(other),
          ),
        );
      }
    },
  );
  return $result.flatten(values);
}

export function subscribe_mv_register(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Set the string with the runtime wall clock and the kernel logical clock.
 */
export function lww_register_set(handle, value) {
  return $result.try$(
    read(
      handle,
      $channel.ChannelType$LwwRegisterChannel$const,
      (_) => { return undefined; },
    ),
    (_) => {
      return mutate(
        handle,
        new $channel.LwwRegisterSetEdit(value, $transport_js.now_milliseconds()),
      );
    },
  );
}

/**
 * The current string of the last-writer-wins register.
 */
export function lww_register_value(handle) {
  let value = read(
    handle,
    $channel.ChannelType$LwwRegisterChannel$const,
    (state) => {
      if (state instanceof $channel.LwwRegisterState) {
        let kernel = state[0];
        return new Ok($lww_register_kernel.value(kernel));
      } else {
        let other = state;
        return new Error(
          new $p2p.ChannelTypeMismatch(
            handle.address,
            $channel.ChannelType$LwwRegisterChannel$const,
            $channel.channel_type(other),
          ),
        );
      }
    },
  );
  return $result.flatten(value);
}

/**
 * Register a callback for visible string changes, not metadata-only writes.
 */
export function subscribe_lww_register(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Set a string with the runtime clock. Return handle and clock errors.
 */
export function lww_map_set(handle, key, value) {
  return $result.try$(
    read(
      handle,
      $channel.ChannelType$LwwMapChannel$const,
      (_) => { return undefined; },
    ),
    (_) => {
      return mutate(
        handle,
        new $channel.LwwMapSetEdit(key, value, $transport_js.now_milliseconds()),
      );
    },
  );
}

/**
 * Retain a tombstone even if the key is absent.
 */
export function lww_map_remove(handle, key) {
  return $result.try$(
    read(
      handle,
      $channel.ChannelType$LwwMapChannel$const,
      (_) => { return undefined; },
    ),
    (_) => {
      return mutate(
        handle,
        new $channel.LwwMapRemoveEdit(key, $transport_js.now_milliseconds()),
      );
    },
  );
}

function read_lww_map(handle, extract) {
  let _pipe = read(
    handle,
    $channel.ChannelType$LwwMapChannel$const,
    (state) => {
      if (state instanceof $channel.LwwMapState) {
        let kernel = state[0];
        return new Ok(extract(kernel));
      } else {
        let other = state;
        return new Error(
          new $p2p.ChannelTypeMismatch(
            handle.address,
            $channel.ChannelType$LwwMapChannel$const,
            $channel.channel_type(other),
          ),
        );
      }
    },
  );
  return $result.flatten(_pipe);
}

/**
 * A missing key is `Ok(Error(Nil))`. Document and handle failures are outer errors.
 */
export function lww_map_get(handle, key) {
  return read_lww_map(
    handle,
    (kernel) => { return $lww_map_kernel.get(kernel, key); },
  );
}

/**
 * Read visible entries in key order.
 */
export function lww_map_entries(handle) {
  return read_lww_map(handle, $lww_map_kernel.entries);
}

export function lww_map_keys(handle) {
  return read_lww_map(handle, $lww_map_kernel.keys);
}

/**
 * Subscribe to visible changes. Metadata-only edits emit no event.
 */
export function subscribe_lww_map(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Add `amount` to the grow-only counter. The amount must not be negative.
 */
export function g_counter_increment(handle, amount) {
  return mutate(handle, new $channel.GCounterIncrementEdit(amount));
}

/**
 * The current value of the grow-only counter.
 */
export function g_counter_value(handle) {
  return read(
    handle,
    $channel.ChannelType$GCounterChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return 0;
      } else if (state instanceof $channel.CounterState) {
        return 0;
      } else if (state instanceof $channel.PnCounterState) {
        return 0;
      } else if (state instanceof $channel.GCounterState) {
        let kernel = state[0];
        return $g_counter_kernel.value(kernel);
      } else if (state instanceof $channel.LwwRegisterState) {
        return 0;
      } else if (state instanceof $channel.LwwMapState) {
        return 0;
      } else if (state instanceof $channel.MvRegisterState) {
        return 0;
      } else if (state instanceof $channel.OrMapState) {
        return 0;
      } else if (state instanceof $channel.OrSetState) {
        return 0;
      } else if (state instanceof $channel.GSetState) {
        return 0;
      } else if (state instanceof $channel.TwoPSetState) {
        return 0;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return 0;
      } else if (state instanceof $channel.ClaimsState) {
        return 0;
      } else if (state instanceof $channel.TaskManagerState) {
        return 0;
      } else if (state instanceof $channel.PactMapState) {
        return 0;
      } else if (state instanceof $channel.JsonOtState) {
        return 0;
      } else if (state instanceof $channel.DirectoryState) {
        return 0;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return 0;
      } else if (state instanceof $channel.SequenceState) {
        return 0;
      } else if (state instanceof $channel.RichTextState) {
        return 0;
      } else {
        return 0;
      }
    },
  );
}

/**
 * Register a callback for every local change and remote change to this
 * grow-only counter.
 */
export function subscribe_g_counter(handle, handler) {
  return subscribe_narrowed(
    handle,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Add `amount` to the counter. A negative amount decrements it.
 */
export function pn_counter_update(handle, amount) {
  return mutate(handle, new $channel.PnCounterEdit(amount));
}

export function pn_counter_increment(handle, amount) {
  return pn_counter_update(handle, amount);
}

export function pn_counter_decrement(handle, amount) {
  return pn_counter_update(handle, - amount);
}

export function pn_counter_value(handle) {
  return read(
    handle,
    $channel.ChannelType$PnCounterChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return 0;
      } else if (state instanceof $channel.CounterState) {
        return 0;
      } else if (state instanceof $channel.PnCounterState) {
        let kernel = state[0];
        return $pn_counter_kernel.value(kernel);
      } else if (state instanceof $channel.GCounterState) {
        return 0;
      } else if (state instanceof $channel.LwwRegisterState) {
        return 0;
      } else if (state instanceof $channel.LwwMapState) {
        return 0;
      } else if (state instanceof $channel.MvRegisterState) {
        return 0;
      } else if (state instanceof $channel.OrMapState) {
        return 0;
      } else if (state instanceof $channel.OrSetState) {
        return 0;
      } else if (state instanceof $channel.GSetState) {
        return 0;
      } else if (state instanceof $channel.TwoPSetState) {
        return 0;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return 0;
      } else if (state instanceof $channel.ClaimsState) {
        return 0;
      } else if (state instanceof $channel.TaskManagerState) {
        return 0;
      } else if (state instanceof $channel.PactMapState) {
        return 0;
      } else if (state instanceof $channel.JsonOtState) {
        return 0;
      } else if (state instanceof $channel.DirectoryState) {
        return 0;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return 0;
      } else if (state instanceof $channel.SequenceState) {
        return 0;
      } else if (state instanceof $channel.RichTextState) {
        return 0;
      } else {
        return 0;
      }
    },
  );
}

/**
 * Write a register value. This function is valid on a `RegisterMode` map only.
 * A tally map returns the mode mismatch error of the kernel.
 */
export function or_map_set(handle, key, value) {
  return mutate(
    handle,
    new $channel.OrMapSetRegisterEdit(
      key,
      value,
      $transport_js.now_milliseconds(),
    ),
  );
}

/**
 * Add to a tally. This function is valid on a `TallyMode` map only.
 */
export function or_map_increment(handle, key, amount) {
  return mutate(handle, new $channel.OrMapIncrementEdit(key, amount));
}

/**
 * Replace the observed alternatives of an MV-register key.
 */
export function or_map_set_mv_register(handle, key, value) {
  return mutate(handle, new $channel.OrMapSetMvRegisterEdit(key, value));
}

export function or_map_value(handle, key) {
  return read(
    handle,
    $channel.ChannelType$OrMapChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return new Error(undefined);
      } else if (state instanceof $channel.CounterState) {
        return new Error(undefined);
      } else if (state instanceof $channel.PnCounterState) {
        return new Error(undefined);
      } else if (state instanceof $channel.GCounterState) {
        return new Error(undefined);
      } else if (state instanceof $channel.LwwRegisterState) {
        return new Error(undefined);
      } else if (state instanceof $channel.LwwMapState) {
        return new Error(undefined);
      } else if (state instanceof $channel.MvRegisterState) {
        return new Error(undefined);
      } else if (state instanceof $channel.OrMapState) {
        let kernel = state[0];
        return $or_map_kernel.get(kernel, key);
      } else if (state instanceof $channel.OrSetState) {
        return new Error(undefined);
      } else if (state instanceof $channel.GSetState) {
        return new Error(undefined);
      } else if (state instanceof $channel.TwoPSetState) {
        return new Error(undefined);
      } else if (state instanceof $channel.RegisterCollectionState) {
        return new Error(undefined);
      } else if (state instanceof $channel.ClaimsState) {
        return new Error(undefined);
      } else if (state instanceof $channel.TaskManagerState) {
        return new Error(undefined);
      } else if (state instanceof $channel.PactMapState) {
        return new Error(undefined);
      } else if (state instanceof $channel.JsonOtState) {
        return new Error(undefined);
      } else if (state instanceof $channel.DirectoryState) {
        return new Error(undefined);
      } else if (state instanceof $channel.OrderedCollectionState) {
        return new Error(undefined);
      } else if (state instanceof $channel.SequenceState) {
        return new Error(undefined);
      } else if (state instanceof $channel.RichTextState) {
        return new Error(undefined);
      } else {
        return new Error(undefined);
      }
    },
  );
}

/**
 * Read alternatives. An absent key or another value mode is an inner error.
 */
export function or_map_values(handle, key) {
  return $result.map(
    or_map_value(handle, key),
    (value) => {
      if (value instanceof Ok) {
        let $ = value[0];
        if ($ instanceof $or_map_kernel.Tally) {
          return new Error(undefined);
        } else if ($ instanceof $or_map_kernel.Register) {
          return new Error(undefined);
        } else if ($ instanceof $or_map_kernel.SetMembers) {
          return new Error(undefined);
        } else {
          let values = $[0];
          return new Ok(values);
        }
      } else {
        return new Error(undefined);
      }
    },
  );
}

export function or_map_remove(handle, key) {
  return mutate(handle, new $channel.OrMapRemoveEdit(key));
}

/**
 * Add a string member in `OrSetMode`. An absent key becomes present.
 * A duplicate add replicates a fresh tag without a visible-value event.
 */
export function or_map_add_member(handle, key, member) {
  return $result.try$(
    read(
      handle,
      $channel.ChannelType$OrMapChannel$const,
      (_) => { return undefined; },
    ),
    (_) => {
      return mutate(handle, new $channel.OrMapAddMemberEdit(key, member));
    },
  );
}

/**
 * Remove observed member tags in `OrSetMode`. An absent member is a no-op.
 * Removing the last member keeps the key present with `SetMembers([])`.
 */
export function or_map_remove_member(handle, key, member) {
  return $result.try$(
    read(
      handle,
      $channel.ChannelType$OrMapChannel$const,
      (_) => { return undefined; },
    ),
    (_) => {
      return mutate(handle, new $channel.OrMapRemoveMemberEdit(key, member));
    },
  );
}

/**
 * Remove a key. In `OrSetMode`, this also clears observed members.
 * Concurrent unobserved additions survive.
 */
export function or_map_remove_key(handle, key) {
  return $result.try$(
    read(
      handle,
      $channel.ChannelType$OrMapChannel$const,
      (_) => { return undefined; },
    ),
    (_) => { return or_map_remove(handle, key); },
  );
}

/**
 * The value of a tally key. The result is zero when the key is absent.
 */
export function or_map_tally(handle, key) {
  return $result.try$(
    or_map_value(handle, key),
    (value) => {
      if (value instanceof Ok) {
        let $ = value[0];
        if ($ instanceof $or_map_kernel.Tally) {
          let tally = $[0];
          return new Ok(tally);
        } else if ($ instanceof $or_map_kernel.Register) {
          return new Error(
            new $p2p.InvalidEnvelope(
              address(handle),
              ("key " + key) + " holds a register, not a tally",
            ),
          );
        } else if ($ instanceof $or_map_kernel.SetMembers) {
          return new Error(
            new $p2p.InvalidEnvelope(
              address(handle),
              ("key " + key) + " holds a set, not a tally",
            ),
          );
        } else {
          return new Error(
            new $p2p.InvalidEnvelope(
              address(handle),
              ("key " + key) + " holds a register, not a tally",
            ),
          );
        }
      } else {
        return new Ok(0);
      }
    },
  );
}

export function or_map_entries(handle) {
  return read(
    handle,
    $channel.ChannelType$OrMapChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.CounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PnCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.MvRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrMapState) {
        let kernel = state[0];
        return $or_map_kernel.entries(kernel);
      } else if (state instanceof $channel.OrSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TwoPSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.ClaimsState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TaskManagerState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PactMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.JsonOtState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.DirectoryState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.SequenceState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.RichTextState) {
        return $List$Empty$const;
      } else {
        return $List$Empty$const;
      }
    },
  );
}

export function or_set_add(handle, element) {
  return mutate(handle, new $channel.OrSetAddEdit(element));
}

export function or_set_remove(handle, element) {
  return mutate(handle, new $channel.OrSetRemoveEdit(element));
}

export function or_set_contains(handle, element) {
  return read(
    handle,
    $channel.ChannelType$OrSetChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return false;
      } else if (state instanceof $channel.CounterState) {
        return false;
      } else if (state instanceof $channel.PnCounterState) {
        return false;
      } else if (state instanceof $channel.GCounterState) {
        return false;
      } else if (state instanceof $channel.LwwRegisterState) {
        return false;
      } else if (state instanceof $channel.LwwMapState) {
        return false;
      } else if (state instanceof $channel.MvRegisterState) {
        return false;
      } else if (state instanceof $channel.OrMapState) {
        return false;
      } else if (state instanceof $channel.OrSetState) {
        let kernel = state[0];
        return $or_set_kernel.contains(kernel, element);
      } else if (state instanceof $channel.GSetState) {
        return false;
      } else if (state instanceof $channel.TwoPSetState) {
        return false;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return false;
      } else if (state instanceof $channel.ClaimsState) {
        return false;
      } else if (state instanceof $channel.TaskManagerState) {
        return false;
      } else if (state instanceof $channel.PactMapState) {
        return false;
      } else if (state instanceof $channel.JsonOtState) {
        return false;
      } else if (state instanceof $channel.DirectoryState) {
        return false;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return false;
      } else if (state instanceof $channel.SequenceState) {
        return false;
      } else if (state instanceof $channel.RichTextState) {
        return false;
      } else {
        return false;
      }
    },
  );
}

export function or_set_values(handle) {
  return read(
    handle,
    $channel.ChannelType$OrSetChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.CounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PnCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.MvRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrSetState) {
        let kernel = state[0];
        return $or_set_kernel.values(kernel);
      } else if (state instanceof $channel.GSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TwoPSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.ClaimsState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TaskManagerState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PactMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.JsonOtState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.DirectoryState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.SequenceState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.RichTextState) {
        return $List$Empty$const;
      } else {
        return $List$Empty$const;
      }
    },
  );
}

export function g_set_add(handle, element) {
  return mutate(handle, new $channel.GSetAddEdit(element));
}

export function g_set_contains(handle, element) {
  return read(
    handle,
    $channel.ChannelType$GSetChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return false;
      } else if (state instanceof $channel.CounterState) {
        return false;
      } else if (state instanceof $channel.PnCounterState) {
        return false;
      } else if (state instanceof $channel.GCounterState) {
        return false;
      } else if (state instanceof $channel.LwwRegisterState) {
        return false;
      } else if (state instanceof $channel.LwwMapState) {
        return false;
      } else if (state instanceof $channel.MvRegisterState) {
        return false;
      } else if (state instanceof $channel.OrMapState) {
        return false;
      } else if (state instanceof $channel.OrSetState) {
        return false;
      } else if (state instanceof $channel.GSetState) {
        let kernel = state[0];
        return $g_set_kernel.contains(kernel, element);
      } else if (state instanceof $channel.TwoPSetState) {
        return false;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return false;
      } else if (state instanceof $channel.ClaimsState) {
        return false;
      } else if (state instanceof $channel.TaskManagerState) {
        return false;
      } else if (state instanceof $channel.PactMapState) {
        return false;
      } else if (state instanceof $channel.JsonOtState) {
        return false;
      } else if (state instanceof $channel.DirectoryState) {
        return false;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return false;
      } else if (state instanceof $channel.SequenceState) {
        return false;
      } else if (state instanceof $channel.RichTextState) {
        return false;
      } else {
        return false;
      }
    },
  );
}

export function g_set_values(handle) {
  return read(
    handle,
    $channel.ChannelType$GSetChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.CounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PnCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.MvRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GSetState) {
        let kernel = state[0];
        return $g_set_kernel.values(kernel);
      } else if (state instanceof $channel.TwoPSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.ClaimsState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TaskManagerState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PactMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.JsonOtState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.DirectoryState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.SequenceState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.RichTextState) {
        return $List$Empty$const;
      } else {
        return $List$Empty$const;
      }
    },
  );
}

export function two_p_set_add(handle, element) {
  return mutate(handle, new $channel.TwoPSetAddEdit(element));
}

export function two_p_set_remove(handle, element) {
  return mutate(handle, new $channel.TwoPSetRemoveEdit(element));
}

export function two_p_set_contains(handle, element) {
  return read(
    handle,
    $channel.ChannelType$TwoPSetChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return false;
      } else if (state instanceof $channel.CounterState) {
        return false;
      } else if (state instanceof $channel.PnCounterState) {
        return false;
      } else if (state instanceof $channel.GCounterState) {
        return false;
      } else if (state instanceof $channel.LwwRegisterState) {
        return false;
      } else if (state instanceof $channel.LwwMapState) {
        return false;
      } else if (state instanceof $channel.MvRegisterState) {
        return false;
      } else if (state instanceof $channel.OrMapState) {
        return false;
      } else if (state instanceof $channel.OrSetState) {
        return false;
      } else if (state instanceof $channel.GSetState) {
        return false;
      } else if (state instanceof $channel.TwoPSetState) {
        let kernel = state[0];
        return $two_p_set_kernel.contains(kernel, element);
      } else if (state instanceof $channel.RegisterCollectionState) {
        return false;
      } else if (state instanceof $channel.ClaimsState) {
        return false;
      } else if (state instanceof $channel.TaskManagerState) {
        return false;
      } else if (state instanceof $channel.PactMapState) {
        return false;
      } else if (state instanceof $channel.JsonOtState) {
        return false;
      } else if (state instanceof $channel.DirectoryState) {
        return false;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return false;
      } else if (state instanceof $channel.SequenceState) {
        return false;
      } else if (state instanceof $channel.RichTextState) {
        return false;
      } else {
        return false;
      }
    },
  );
}

export function two_p_set_values(handle) {
  return read(
    handle,
    $channel.ChannelType$TwoPSetChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.CounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PnCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.MvRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TwoPSetState) {
        let kernel = state[0];
        return $two_p_set_kernel.values(kernel);
      } else if (state instanceof $channel.RegisterCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.ClaimsState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TaskManagerState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PactMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.JsonOtState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.DirectoryState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.SequenceState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.RichTextState) {
        return $List$Empty$const;
      } else {
        return $List$Empty$const;
      }
    },
  );
}

export function sequence_insert(handle, index, value) {
  return mutate(handle, new $channel.SequenceInsertEdit(index, value));
}

export function sequence_delete(handle, index) {
  return mutate(handle, new $channel.SequenceDeleteEdit(index));
}

export function sequence_move(handle, from, to) {
  return mutate(handle, new $channel.SequenceMoveEdit(from, to));
}

export function sequence_replace(handle, index, value) {
  return mutate(handle, new $channel.SequenceReplaceEdit(index, value));
}

export function sequence_values(handle) {
  return read(
    handle,
    $channel.ChannelType$SequenceChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.CounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PnCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GCounterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.LwwMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.MvRegisterState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.GSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TwoPSetState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.ClaimsState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.TaskManagerState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.PactMapState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.JsonOtState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.DirectoryState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return $List$Empty$const;
      } else if (state instanceof $channel.SequenceState) {
        let kernel = state[0];
        return $sequence_kernel.values(kernel);
      } else if (state instanceof $channel.RichTextState) {
        return $List$Empty$const;
      } else {
        return $List$Empty$const;
      }
    },
  );
}

export function text_insert(handle, index, value) {
  return mutate(handle, new $channel.TextInsertEdit(index, value));
}

export function text_delete_range(handle, start, end) {
  return mutate(handle, new $channel.TextDeleteRangeEdit(start, end));
}

export function text_replace_range(handle, start, end, value) {
  return mutate(handle, new $channel.TextReplaceRangeEdit(start, end, value));
}

export function text_append(handle, value) {
  return mutate(handle, new $channel.TextAppendEdit(value));
}

export function text_value(handle) {
  return read(
    handle,
    $channel.ChannelType$TextChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return "";
      } else if (state instanceof $channel.CounterState) {
        return "";
      } else if (state instanceof $channel.PnCounterState) {
        return "";
      } else if (state instanceof $channel.GCounterState) {
        return "";
      } else if (state instanceof $channel.LwwRegisterState) {
        return "";
      } else if (state instanceof $channel.LwwMapState) {
        return "";
      } else if (state instanceof $channel.MvRegisterState) {
        return "";
      } else if (state instanceof $channel.OrMapState) {
        return "";
      } else if (state instanceof $channel.OrSetState) {
        return "";
      } else if (state instanceof $channel.GSetState) {
        return "";
      } else if (state instanceof $channel.TwoPSetState) {
        return "";
      } else if (state instanceof $channel.RegisterCollectionState) {
        return "";
      } else if (state instanceof $channel.ClaimsState) {
        return "";
      } else if (state instanceof $channel.TaskManagerState) {
        return "";
      } else if (state instanceof $channel.PactMapState) {
        return "";
      } else if (state instanceof $channel.JsonOtState) {
        return "";
      } else if (state instanceof $channel.DirectoryState) {
        return "";
      } else if (state instanceof $channel.OrderedCollectionState) {
        return "";
      } else if (state instanceof $channel.SequenceState) {
        return "";
      } else if (state instanceof $channel.RichTextState) {
        return "";
      } else {
        let kernel = state[0];
        return $text_kernel.value(kernel);
      }
    },
  );
}

/**
 * The current optimistic grapheme count of the text.
 */
export function text_length(handle) {
  return read(
    handle,
    $channel.ChannelType$TextChannel$const,
    (state) => {
      if (state instanceof $channel.MapState) {
        return 0;
      } else if (state instanceof $channel.CounterState) {
        return 0;
      } else if (state instanceof $channel.PnCounterState) {
        return 0;
      } else if (state instanceof $channel.GCounterState) {
        return 0;
      } else if (state instanceof $channel.LwwRegisterState) {
        return 0;
      } else if (state instanceof $channel.LwwMapState) {
        return 0;
      } else if (state instanceof $channel.MvRegisterState) {
        return 0;
      } else if (state instanceof $channel.OrMapState) {
        return 0;
      } else if (state instanceof $channel.OrSetState) {
        return 0;
      } else if (state instanceof $channel.GSetState) {
        return 0;
      } else if (state instanceof $channel.TwoPSetState) {
        return 0;
      } else if (state instanceof $channel.RegisterCollectionState) {
        return 0;
      } else if (state instanceof $channel.ClaimsState) {
        return 0;
      } else if (state instanceof $channel.TaskManagerState) {
        return 0;
      } else if (state instanceof $channel.PactMapState) {
        return 0;
      } else if (state instanceof $channel.JsonOtState) {
        return 0;
      } else if (state instanceof $channel.DirectoryState) {
        return 0;
      } else if (state instanceof $channel.OrderedCollectionState) {
        return 0;
      } else if (state instanceof $channel.SequenceState) {
        return 0;
      } else if (state instanceof $channel.RichTextState) {
        return 0;
      } else {
        let kernel = state[0];
        return $text_kernel.length(kernel);
      }
    },
  );
}

/**
 * Create a stable anchor at the gap before the optimistic grapheme at `index`.
 * `bias_before` and `bias_after` set the bias. The result is a typed error when
 * the index is out of bounds.
 */
export function text_anchor_at(handle, index, bias) {
  let $ = read(
    handle,
    $channel.ChannelType$TextChannel$const,
    (state) => { return state; },
  );
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TextState) {
      let kernel = $1[0];
      let _pipe = $text_kernel.anchor_at(kernel, index, bias);
      return $result.map_error(
        _pipe,
        (error) => {
          return new $p2p.InvalidEnvelope(
            address(handle),
            $text_kernel.anchor_error_detail(error),
          );
        },
      );
    } else {
      return new Error(
        new $p2p.InvalidEnvelope(
          address(handle),
          "registered text channel stored a non-text state",
        ),
      );
    }
  } else {
    return $;
  }
}

/**
 * Resolve an anchor to a current optimistic grapheme index. The result is a
 * typed error when the anchor target is stale or unknown.
 */
export function text_resolve_anchor(handle, anchor) {
  let $ = read(
    handle,
    $channel.ChannelType$TextChannel$const,
    (state) => { return state; },
  );
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TextState) {
      let kernel = $1[0];
      let _pipe = $text_kernel.resolve_anchor(kernel, anchor);
      return $result.map_error(
        _pipe,
        (error) => {
          return new $p2p.InvalidEnvelope(
            address(handle),
            $text_kernel.anchor_error_detail(error),
          );
        },
      );
    } else {
      return new Error(
        new $p2p.InvalidEnvelope(
          address(handle),
          "registered text channel stored a non-text state",
        ),
      );
    }
  } else {
    return $;
  }
}

/**
 * An anchor at the start of the text. It always resolves to 0. The function is
 * pure. It needs no handle, because the anchor carries no document state.
 */
export function text_start_anchor() {
  return $text_kernel.start_anchor();
}

/**
 * An anchor at the end of the text. It always resolves to the current grapheme
 * count, and it moves as the text becomes longer. The function is pure, the
 * same as `text_start_anchor`.
 */
export function text_end_anchor() {
  return $text_kernel.end_anchor();
}

/**
 * Encode an anchor as a self-describing JSON value.
 */
export function text_anchor_to_json(anchor) {
  return $text_kernel.anchor_to_json(anchor);
}

function format_json_decode_error(error) {
  if (error instanceof $json.UnexpectedEndOfInput) {
    return "unexpected end of input";
  } else if (error instanceof $json.UnexpectedByte) {
    let byte = error[0];
    return "unexpected byte: " + byte;
  } else if (error instanceof $json.UnexpectedSequence) {
    let bytes = error[0];
    return "unexpected sequence: " + bytes;
  } else {
    let errors = error[0];
    return "unable to decode: " + $string.join(
      $list.map(
        errors,
        (e) => {
          return ((("expected " + e.expected) + ", found ") + e.found) + (() => {
            let $ = e.path;
            if ($ instanceof $Empty) {
              return "";
            } else {
              let path = $;
              return " at " + $string.join(path, ".");
            }
          })();
        },
      ),
      "; ",
    );
  }
}

/**
 * Decode an anchor from a JSON string that `text_anchor_to_json` produced. The
 * result is a typed error for malformed JSON.
 */
export function text_anchor_from_json(json_string) {
  let $ = $text_kernel.anchor_from_json(json_string);
  if ($ instanceof Ok) {
    return $;
  } else {
    let error = $[0];
    return new Error(
      new $p2p.InvalidEnvelope(
        "textAnchor",
        "invalid anchor JSON: " + format_json_decode_error(error),
      ),
    );
  }
}

/**
 * The whole `crdt_core` snapshot that `import_snapshot` can read: the full
 * CRDT state of every channel, with the authoring cursors, in canonical
 * order.
 *
 * The function returns a `Result` value, because every other option is worse.
 * The bytes come from `canonical_json`, and the function reads them again here
 * to reach the value type of `gleam/json`, which has no raw constructor. That
 * read cannot fail for anything that this library emits. But a public function
 * that panicked would be worse, and a public function that quietly returned a
 * snapshot with null in place of the parts that it could not decode would be
 * worse still. No caller could trust such a snapshot.
 */
export function export_snapshot(document) {
  let state = $transport_js.get_cell(document.cell);
  let raw = $crdt_core.canonical_json(state.document);
  let _pipe = $json.parse(raw, $wire.json_value_decoder());
  return $result.replace_error(
    _pipe,
    new $p2p.InvalidEnvelope(
      $crdt_core.replica(state.document),
      "the exported snapshot could not be read back as JSON",
    ),
  );
}

/**
 * Merge an exported snapshot into a live document.
 *
 * This merge is a join, the same as the import in the core. The local channels
 * and the local edits all stay. The subscriber events go out exactly one time.
 * A merged state on an attached document goes to the existing anti-entropy and
 * relay code, and it does not take a new path here.
 */
export function merge_snapshot(document, snapshot) {
  let cell = document.cell;
  let state = $transport_js.get_cell(cell);
  return $result.try$(
    usable(cell, state),
    (_) => {
      let durable = (state.path instanceof Sequenced) && (state.phase instanceof RelayPrimaryPhase);
      let _block;
      if (durable) {
        _block = document_digest(cell);
      } else {
        _block = "";
      }
      let before = _block;
      return $result.try$(
        fail(
          cell,
          $crdt_core.import_snapshot(state.document, $json.to_string(snapshot)),
        ),
        (_use0) => {
          let core = _use0[0];
          let outcome = _use0[1];
          $transport_js.set_cell(
            cell,
            new State(
              state.label,
              state.signaling,
              state.ice_servers,
              core,
              state.transport,
              state.peers,
              state.subscriptions,
              state.next_subscription,
              state.on_status,
              state.on_ready,
              state.readiness,
              state.roster,
              state.bootstrap,
              state.deferred,
              state.imported,
              state.attached,
              state.closed,
              state.policy,
              state.sequencer,
              state.relay,
              state.phase,
              state.path,
              state.published,
              state.resyncs,
              state.resync_timer,
              state.nudge_dirty,
              state.nudge_armed,
              state.nudge_timer,
              state.publish_owed,
              state.scheduler,
              state.anti_entropy_interval_milliseconds,
              state.sync_armed,
              state.sync_timer,
              state.last_sync_digest,
              state.repairs,
              state.last_match,
              state.digest_cache,
              state.deadline,
              state.recovered,
            ),
          );
          dispatch(cell, outcome.events);
          refresh_sync(cell);
          let $ = durable && (document_digest(cell) !== before);
          let $1 = state.transport;
          if ($) {
            if ($1 instanceof Some) {
              owe_publication(cell);
            } else {
              publish_while_primary(cell);
            }
          } else {
            undefined;
          }
          return new Ok(outcome);
        },
      );
    },
  );
}

/**
 * Build a document again from an exported snapshot.
 *
 * The function checks the size, the protocol version, the room, the
 * compatibility tag, the root type, and the eligibility of every channel,
 * before it loads one channel. The result is detached. Give it to `attach` to
 * bring it online.
 */
export function import_snapshot(config, snapshot) {
  return $result.try$(
    new_document(config),
    (document) => {
      let cell = document.cell;
      let state = $transport_js.get_cell(cell);
      return $result.try$(
        $crdt_core.import_snapshot(state.document, $json.to_string(snapshot)),
        (_use0) => {
          let core = _use0[0];
          $transport_js.set_cell(
            cell,
            new State(
              state.label,
              state.signaling,
              state.ice_servers,
              core,
              state.transport,
              state.peers,
              state.subscriptions,
              state.next_subscription,
              state.on_status,
              state.on_ready,
              state.readiness,
              state.roster,
              state.bootstrap,
              state.deferred,
              true,
              state.attached,
              state.closed,
              state.policy,
              state.sequencer,
              state.relay,
              state.phase,
              state.path,
              state.published,
              state.resyncs,
              state.resync_timer,
              state.nudge_dirty,
              state.nudge_armed,
              state.nudge_timer,
              state.publish_owed,
              state.scheduler,
              state.anti_entropy_interval_milliseconds,
              state.sync_armed,
              state.sync_timer,
              state.last_sync_digest,
              state.repairs,
              state.last_match,
              state.digest_cache,
              state.deadline,
              state.recovered,
            ),
          );
          return new Ok(document);
        },
      );
    },
  );
}

export function room(document) {
  return $crdt_core.room($transport_js.get_cell(document.cell).document);
}

/**
 * The signaling room that this document belongs to. This function is another
 * name for `room`, and the name suits a key in persistent storage.
 */
export function room_id(document) {
  return room(document);
}

/**
 * The compatibility tag of the application that this document applies.
 */
export function compatibility_tag(document) {
  return $crdt_core.compatibility(
    $transport_js.get_cell(document.cell).document,
  );
}

/**
 * The authorship identity of this replica: the label from the config, with a
 * random session id for this connection after it.
 */
export function replica_id(document) {
  return $crdt_core.replica($transport_js.get_cell(document.cell).document);
}

/**
 * The label of the application, without the session id.
 */
export function replica_label(document) {
  return $transport_js.get_cell(document.cell).label;
}

/**
 * The canonical digest of the document. Two replicas that hold the same
 * logical state and the same causal state get the same value, on either
 * compile target.
 *
 * The module computes this value one time for each document state, and it
 * reuses that value until the document moves. To read it in a render loop thus
 * costs one comparison, and not a hash of the whole document.
 */
export function digest(document) {
  return document_digest(document.cell);
}

/**
 * The number of times that this document canonicalized and hashed itself.
 *
 * This function is a diagnostic. Every digest that this facade needs comes
 * from one computation for each document state. Those digests are the
 * heartbeat, the comparison against a peer, the publication and the
 * attestation of the relay, and the `digest` function itself. This count
 * reports that fact: it increases when the document moved after the last
 * digest, and it does not increase when the document did not move.
 */
export function digest_computations(document) {
  let state = $transport_js.get_cell(document.cell);
  return $transport_js.get_cell(state.digest_cache).computations;
}

/**
 * The peers that completed the `hello` handshake, sorted.
 */
export function peers(document) {
  return greeted_peers($transport_js.get_cell(document.cell));
}

export function peer_count(document) {
  return $list.length(peers(document));
}

/**
 * The progress of this replica through a join into its room. The value is
 * `Joining` until a peer passes its checks, `WaitingForState` while a bootstrap
 * `stateRequest` message has no answer, and `Bootstrapped` after the state of a
 * room merges. This function is a diagnostic that pairs with `peer_count`.
 */
export function bootstrap_state(document) {
  return $transport_js.get_cell(document.cell).bootstrap;
}

/**
 * The number of times that the anti-entropy digest of a peer told this replica
 * that it was behind, and this replica then asked for the state. That number
 * counts the partition-repair activity of the mesh. It is zero on a document
 * that always agreed with its peers.
 */
export function repair_count(document) {
  return $transport_js.get_cell(document.cell).repairs;
}

/**
 * The last peer digest that equalled the digest of this replica, if one
 * exists. That value is the most recent successful anti-entropy comparison.
 * The result is `None` until a peer confirms that the two agree.
 */
export function last_digest_match(document) {
  return $transport_js.get_cell(document.cell).last_match;
}

/**
 * The readiness result that this connection delivered. The value is `None`
 * while the connection still waits for that result.
 *
 * This function reports all three states correctly, and a plain boolean value
 * cannot do that. A document that failed to join and a document that is still
 * joining are two different conditions, and neither one is ready.
 */
export function readiness(document) {
  return $transport_js.get_cell(document.cell).readiness;
}

/**
 * Whether the readiness resolved at all, in either direction. A closed document
 * gives `True`, because the module delivered its result in both
 * conditions.
 */
export function readiness_resolved(document) {
  return !(readiness(document) instanceof None);
}

export function is_closed(document) {
  return $transport_js.get_cell(document.cell).closed;
}

/**
 * The policy that the config of this document names.
 */
export function policy(document) {
  return $transport_js.get_cell(document.cell).policy;
}

/**
 * The path that the durable traffic takes now.
 *
 * The value is `PeerToPeer` until a relay merges, publishes, and matches the
 * digests. It is `PeerToPeer` again at the moment that a relay drops, before
 * the module emits the fallback status.
 */
export function effective_path(document) {
  return $transport_js.get_cell(document.cell).path;
}

/**
 * Whether the relay is the durable delta path.
 */
export function relay_is_primary(document) {
  return $transport_js.get_cell(document.cell).phase instanceof RelayPrimaryPhase;
}

/**
 * Whether the module opened a relay lane at all. The result is `False` under
 * `P2pOnly`, and under `Auto` with no sequencer in the config.
 */
export function relay_attached_lane(document) {
  return !($transport_js.get_cell(document.cell).relay instanceof None);
}

/**
 * A typed error on one line, for a status line and for a log.
 */
export function describe_error(error) {
  let $ = error_parts(error);
  let reason = $[0];
  let detail = $[1];
  if (detail === "") {
    return reason;
  } else {
    return (reason + " · ") + detail;
  }
}

/// <reference types="./p2p_transport_js.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $crdt_wire from "../watershed/crdt_wire.mjs";
import * as $p2p from "../watershed/p2p.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import {
  newRtc as new_native_rtc,
  open as native_open,
  openChannel as native_open_channel,
  offer as native_offer,
  acceptOffer as native_accept_offer,
  acceptAnswer as native_accept_answer,
  addCandidate as native_add_candidate,
  signalingState as native_signaling_state,
  send as native_send,
  closePeer as native_close,
  diagnostics as native_diagnostics,
} from "./p2p_transport_ffi.mjs";

export class Offer extends $CustomType {
  constructor(sdp) {
    super();
    this.sdp = sdp;
  }
}
export const SignalPayload$Offer = (sdp) => new Offer(sdp);
export const SignalPayload$isOffer = (value) => value instanceof Offer;
export const SignalPayload$Offer$sdp = (value) => value.sdp;
export const SignalPayload$Offer$0 = (value) => value.sdp;

export class Answer extends $CustomType {
  constructor(sdp) {
    super();
    this.sdp = sdp;
  }
}
export const SignalPayload$Answer = (sdp) => new Answer(sdp);
export const SignalPayload$isAnswer = (value) => value instanceof Answer;
export const SignalPayload$Answer$sdp = (value) => value.sdp;
export const SignalPayload$Answer$0 = (value) => value.sdp;

export class Candidate extends $CustomType {
  constructor(candidate) {
    super();
    this.candidate = candidate;
  }
}
export const SignalPayload$Candidate = (candidate) => new Candidate(candidate);
export const SignalPayload$isCandidate = (value) => value instanceof Candidate;
export const SignalPayload$Candidate$candidate = (value) => value.candidate;
export const SignalPayload$Candidate$0 = (value) => value.candidate;

/**
 * The membership of the room at the moment that the service admitted this
 * peer. The list must be *complete*: every id in it is a member, and no
 * member is absent.
 *
 * An adapter must send this one signal exactly one time for each
 * successful `join` call, and that includes a join into an empty room.
 * This signal is the only way for a caller to separate "no client is here"
 * from "no client is announced yet". A document that cannot separate those
 * two conditions either waits without an end, or it declares that it is
 * alone in a room that is not empty. An adapter that knows the membership
 * inside `join` reports it there. An adapter that learns the membership
 * over a round trip reports it when that membership arrives.
 */
export class Roster extends $CustomType {
  constructor(peers) {
    super();
    this.peers = peers;
  }
}
export const Signal$Roster = (peers) => new Roster(peers);
export const Signal$isRoster = (value) => value instanceof Roster;
export const Signal$Roster$peers = (value) => value.peers;
export const Signal$Roster$0 = (value) => value.peers;

export class PeerJoined extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const Signal$PeerJoined = (peer_id) => new PeerJoined(peer_id);
export const Signal$isPeerJoined = (value) => value instanceof PeerJoined;
export const Signal$PeerJoined$peer_id = (value) => value.peer_id;
export const Signal$PeerJoined$0 = (value) => value.peer_id;

export class PeerLeft extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const Signal$PeerLeft = (peer_id) => new PeerLeft(peer_id);
export const Signal$isPeerLeft = (value) => value instanceof PeerLeft;
export const Signal$PeerLeft$peer_id = (value) => value.peer_id;
export const Signal$PeerLeft$0 = (value) => value.peer_id;

export class Message extends $CustomType {
  constructor(from, payload) {
    super();
    this.from = from;
    this.payload = payload;
  }
}
export const Signal$Message = (from, payload) => new Message(from, payload);
export const Signal$isMessage = (value) => value instanceof Message;
export const Signal$Message$from = (value) => value.from;
export const Signal$Message$0 = (value) => value.from;
export const Signal$Message$payload = (value) => value.payload;
export const Signal$Message$1 = (value) => value.payload;

/**
 * Signaling failed *after* `join` returned. The service became
 * unavailable, the socket closed, or the roster never arrived. The
 * transport reports this signal as a typed `SignalingFailed` value,
 * through `Callbacks.on_error`. A caller that still waits for admission
 * thus gets an answer, and it does not wait without an end.
 *
 * This signal does not close the transport. A data channel that is already
 * open continues to work without signaling, and that property is the
 * purpose of a mesh.
 */
export class Failed extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const Signal$Failed = (detail) => new Failed(detail);
export const Signal$isFailed = (value) => value instanceof Failed;
export const Signal$Failed$detail = (value) => value.detail;
export const Signal$Failed$0 = (value) => value.detail;

class SignalingSession extends $CustomType {
  constructor(room, peer_id) {
    super();
    this.room = room;
    this.peer_id = peer_id;
  }
}

export class Signaling extends $CustomType {
  constructor(join, send, leave) {
    super();
    this.join = join;
    this.send = send;
    this.leave = leave;
  }
}
export const Signaling$Signaling = (join, send, leave) =>
  new Signaling(join, send, leave);
export const Signaling$isSignaling = (value) => value instanceof Signaling;
export const Signaling$Signaling$join = (value) => value.join;
export const Signaling$Signaling$0 = (value) => value.join;
export const Signaling$Signaling$send = (value) => value.send;
export const Signaling$Signaling$1 = (value) => value.send;
export const Signaling$Signaling$leave = (value) => value.leave;
export const Signaling$Signaling$2 = (value) => value.leave;

export class IceServer extends $CustomType {
  constructor(urls, username, credential) {
    super();
    this.urls = urls;
    this.username = username;
    this.credential = credential;
  }
}
export const IceServer$IceServer = (urls, username, credential) =>
  new IceServer(urls, username, credential);
export const IceServer$isIceServer = (value) => value instanceof IceServer;
export const IceServer$IceServer$urls = (value) => value.urls;
export const IceServer$IceServer$0 = (value) => value.urls;
export const IceServer$IceServer$username = (value) => value.username;
export const IceServer$IceServer$1 = (value) => value.username;
export const IceServer$IceServer$credential = (value) => value.credential;
export const IceServer$IceServer$2 = (value) => value.credential;

export class SignalingJoined extends $CustomType {
  constructor(room, peer_id) {
    super();
    this.room = room;
    this.peer_id = peer_id;
  }
}
export const Status$SignalingJoined = (room, peer_id) =>
  new SignalingJoined(room, peer_id);
export const Status$isSignalingJoined = (value) =>
  value instanceof SignalingJoined;
export const Status$SignalingJoined$room = (value) => value.room;
export const Status$SignalingJoined$0 = (value) => value.room;
export const Status$SignalingJoined$peer_id = (value) => value.peer_id;
export const Status$SignalingJoined$1 = (value) => value.peer_id;

/**
 * The `Roster` signal of the adapter, after the transport tracks every peer
 * in it. The transport emits this status one time for each join. It is the
 * only status that means that the membership of the room is now completely
 * known. `known_peers` already holds every peer when this status arrives,
 * so a caller can read that list and conclude that it is alone.
 */
export class SignalingRoster extends $CustomType {
  constructor(peers) {
    super();
    this.peers = peers;
  }
}
export const Status$SignalingRoster = (peers) => new SignalingRoster(peers);
export const Status$isSignalingRoster = (value) =>
  value instanceof SignalingRoster;
export const Status$SignalingRoster$peers = (value) => value.peers;
export const Status$SignalingRoster$0 = (value) => value.peers;

export class SignalingLeft extends $CustomType {}
export const Status$SignalingLeft$const = new SignalingLeft();
export const Status$SignalingLeft = () => Status$SignalingLeft$const;
export const Status$isSignalingLeft = (value) => value instanceof SignalingLeft;

export class PeerConnecting extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const Status$PeerConnecting = (peer_id) => new PeerConnecting(peer_id);
export const Status$isPeerConnecting = (value) =>
  value instanceof PeerConnecting;
export const Status$PeerConnecting$peer_id = (value) => value.peer_id;
export const Status$PeerConnecting$0 = (value) => value.peer_id;

export class PeerOpen extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const Status$PeerOpen = (peer_id) => new PeerOpen(peer_id);
export const Status$isPeerOpen = (value) => value instanceof PeerOpen;
export const Status$PeerOpen$peer_id = (value) => value.peer_id;
export const Status$PeerOpen$0 = (value) => value.peer_id;

export class PeerClosed extends $CustomType {
  constructor(peer_id) {
    super();
    this.peer_id = peer_id;
  }
}
export const Status$PeerClosed = (peer_id) => new PeerClosed(peer_id);
export const Status$isPeerClosed = (value) => value instanceof PeerClosed;
export const Status$PeerClosed$peer_id = (value) => value.peer_id;
export const Status$PeerClosed$0 = (value) => value.peer_id;

export class PeerFailed extends $CustomType {
  constructor(peer_id, detail) {
    super();
    this.peer_id = peer_id;
    this.detail = detail;
  }
}
export const Status$PeerFailed = (peer_id, detail) =>
  new PeerFailed(peer_id, detail);
export const Status$isPeerFailed = (value) => value instanceof PeerFailed;
export const Status$PeerFailed$peer_id = (value) => value.peer_id;
export const Status$PeerFailed$0 = (value) => value.peer_id;
export const Status$PeerFailed$detail = (value) => value.detail;
export const Status$PeerFailed$1 = (value) => value.detail;

export class IceState extends $CustomType {
  constructor(peer_id, state) {
    super();
    this.peer_id = peer_id;
    this.state = state;
  }
}
export const Status$IceState = (peer_id, state) => new IceState(peer_id, state);
export const Status$isIceState = (value) => value instanceof IceState;
export const Status$IceState$peer_id = (value) => value.peer_id;
export const Status$IceState$0 = (value) => value.peer_id;
export const Status$IceState$state = (value) => value.state;
export const Status$IceState$1 = (value) => value.state;

export class PeerCount extends $CustomType {
  constructor(open) {
    super();
    this.open = open;
  }
}
export const Status$PeerCount = (open) => new PeerCount(open);
export const Status$isPeerCount = (value) => value instanceof PeerCount;
export const Status$PeerCount$open = (value) => value.open;
export const Status$PeerCount$0 = (value) => value.open;

export class Callbacks extends $CustomType {
  constructor(on_peer_open, on_peer_close, on_document, on_status, on_error) {
    super();
    this.on_peer_open = on_peer_open;
    this.on_peer_close = on_peer_close;
    this.on_document = on_document;
    this.on_status = on_status;
    this.on_error = on_error;
  }
}
export const Callbacks$Callbacks = (on_peer_open, on_peer_close, on_document, on_status, on_error) =>
  new Callbacks(on_peer_open, on_peer_close, on_document, on_status, on_error);
export const Callbacks$isCallbacks = (value) => value instanceof Callbacks;
export const Callbacks$Callbacks$on_peer_open = (value) => value.on_peer_open;
export const Callbacks$Callbacks$0 = (value) => value.on_peer_open;
export const Callbacks$Callbacks$on_peer_close = (value) => value.on_peer_close;
export const Callbacks$Callbacks$1 = (value) => value.on_peer_close;
export const Callbacks$Callbacks$on_document = (value) => value.on_document;
export const Callbacks$Callbacks$2 = (value) => value.on_document;
export const Callbacks$Callbacks$on_status = (value) => value.on_status;
export const Callbacks$Callbacks$3 = (value) => value.on_status;
export const Callbacks$Callbacks$on_error = (value) => value.on_error;
export const Callbacks$Callbacks$4 = (value) => value.on_error;

export class PeerHooks extends $CustomType {
  constructor(on_negotiation_needed, on_description, on_remote_description, on_candidate, on_channel_open, on_channel_close, on_message, on_invalid_message, on_ice_state, on_failure) {
    super();
    this.on_negotiation_needed = on_negotiation_needed;
    this.on_description = on_description;
    this.on_remote_description = on_remote_description;
    this.on_candidate = on_candidate;
    this.on_channel_open = on_channel_open;
    this.on_channel_close = on_channel_close;
    this.on_message = on_message;
    this.on_invalid_message = on_invalid_message;
    this.on_ice_state = on_ice_state;
    this.on_failure = on_failure;
  }
}
export const PeerHooks$PeerHooks = (on_negotiation_needed, on_description, on_remote_description, on_candidate, on_channel_open, on_channel_close, on_message, on_invalid_message, on_ice_state, on_failure) =>
  new PeerHooks(on_negotiation_needed,
  on_description,
  on_remote_description,
  on_candidate,
  on_channel_open,
  on_channel_close,
  on_message,
  on_invalid_message,
  on_ice_state,
  on_failure);
export const PeerHooks$isPeerHooks = (value) => value instanceof PeerHooks;
export const PeerHooks$PeerHooks$on_negotiation_needed = (value) =>
  value.on_negotiation_needed;
export const PeerHooks$PeerHooks$0 = (value) => value.on_negotiation_needed;
export const PeerHooks$PeerHooks$on_description = (value) =>
  value.on_description;
export const PeerHooks$PeerHooks$1 = (value) => value.on_description;
export const PeerHooks$PeerHooks$on_remote_description = (value) =>
  value.on_remote_description;
export const PeerHooks$PeerHooks$2 = (value) => value.on_remote_description;
export const PeerHooks$PeerHooks$on_candidate = (value) => value.on_candidate;
export const PeerHooks$PeerHooks$3 = (value) => value.on_candidate;
export const PeerHooks$PeerHooks$on_channel_open = (value) =>
  value.on_channel_open;
export const PeerHooks$PeerHooks$4 = (value) => value.on_channel_open;
export const PeerHooks$PeerHooks$on_channel_close = (value) =>
  value.on_channel_close;
export const PeerHooks$PeerHooks$5 = (value) => value.on_channel_close;
export const PeerHooks$PeerHooks$on_message = (value) => value.on_message;
export const PeerHooks$PeerHooks$6 = (value) => value.on_message;
export const PeerHooks$PeerHooks$on_invalid_message = (value) =>
  value.on_invalid_message;
export const PeerHooks$PeerHooks$7 = (value) => value.on_invalid_message;
export const PeerHooks$PeerHooks$on_ice_state = (value) => value.on_ice_state;
export const PeerHooks$PeerHooks$8 = (value) => value.on_ice_state;
export const PeerHooks$PeerHooks$on_failure = (value) => value.on_failure;
export const PeerHooks$PeerHooks$9 = (value) => value.on_failure;

export class Rtc extends $CustomType {
  constructor(open, open_channel, offer, accept_offer, accept_answer, add_candidate, signaling_state, send, close, diagnostics) {
    super();
    this.open = open;
    this.open_channel = open_channel;
    this.offer = offer;
    this.accept_offer = accept_offer;
    this.accept_answer = accept_answer;
    this.add_candidate = add_candidate;
    this.signaling_state = signaling_state;
    this.send = send;
    this.close = close;
    this.diagnostics = diagnostics;
  }
}
export const Rtc$Rtc = (open, open_channel, offer, accept_offer, accept_answer, add_candidate, signaling_state, send, close, diagnostics) =>
  new Rtc(open,
  open_channel,
  offer,
  accept_offer,
  accept_answer,
  add_candidate,
  signaling_state,
  send,
  close,
  diagnostics);
export const Rtc$isRtc = (value) => value instanceof Rtc;
export const Rtc$Rtc$open = (value) => value.open;
export const Rtc$Rtc$0 = (value) => value.open;
export const Rtc$Rtc$open_channel = (value) => value.open_channel;
export const Rtc$Rtc$1 = (value) => value.open_channel;
export const Rtc$Rtc$offer = (value) => value.offer;
export const Rtc$Rtc$2 = (value) => value.offer;
export const Rtc$Rtc$accept_offer = (value) => value.accept_offer;
export const Rtc$Rtc$3 = (value) => value.accept_offer;
export const Rtc$Rtc$accept_answer = (value) => value.accept_answer;
export const Rtc$Rtc$4 = (value) => value.accept_answer;
export const Rtc$Rtc$add_candidate = (value) => value.add_candidate;
export const Rtc$Rtc$5 = (value) => value.add_candidate;
export const Rtc$Rtc$signaling_state = (value) => value.signaling_state;
export const Rtc$Rtc$6 = (value) => value.signaling_state;
export const Rtc$Rtc$send = (value) => value.send;
export const Rtc$Rtc$7 = (value) => value.send;
export const Rtc$Rtc$close = (value) => value.close;
export const Rtc$Rtc$8 = (value) => value.close;
export const Rtc$Rtc$diagnostics = (value) => value.diagnostics;
export const Rtc$Rtc$9 = (value) => value.diagnostics;

class Transport extends $CustomType {
  constructor(cell) {
    super();
    this.cell = cell;
  }
}

class State extends $CustomType {
  constructor(room, peer_id, signaling, session, rtc, configuration, callbacks, peers, pending_signals, closed) {
    super();
    this.room = room;
    this.peer_id = peer_id;
    this.signaling = signaling;
    this.session = session;
    this.rtc = rtc;
    this.configuration = configuration;
    this.callbacks = callbacks;
    this.peers = peers;
    this.pending_signals = pending_signals;
    this.closed = closed;
  }
}

class Peer extends $CustomType {
  constructor(id, role, announced, channel_requested, remote_offered, making_offer, ignore_offer, have_remote_description, last_remote_offer, queued_candidates, open) {
    super();
    this.id = id;
    this.role = role;
    this.announced = announced;
    this.channel_requested = channel_requested;
    this.remote_offered = remote_offered;
    this.making_offer = making_offer;
    this.ignore_offer = ignore_offer;
    this.have_remote_description = have_remote_description;
    this.last_remote_offer = last_remote_offer;
    this.queued_candidates = queued_candidates;
    this.open = open;
  }
}

/**
 * This client offers, and it creates the one data channel. It also refuses
 * a colliding remote offer, so its own offer wins.
 * 
 * @ignore
 */
class Offerer extends $CustomType {}
const NegotiationRole$Offerer$const = new Offerer();

/**
 * This client answers, and it yields in a collision.
 * 
 * @ignore
 */
class Answerer extends $CustomType {}
const NegotiationRole$Answerer$const = new Answerer();

export class TransportClosed extends $CustomType {}
export const SendError$TransportClosed$const = new TransportClosed();
export const SendError$TransportClosed = () => SendError$TransportClosed$const;
export const SendError$isTransportClosed = (value) =>
  value instanceof TransportClosed;

export class UnknownPeer extends $CustomType {}
export const SendError$UnknownPeer$const = new UnknownPeer();
export const SendError$UnknownPeer = () => SendError$UnknownPeer$const;
export const SendError$isUnknownPeer = (value) => value instanceof UnknownPeer;

export class ChannelNotOpen extends $CustomType {}
export const SendError$ChannelNotOpen$const = new ChannelNotOpen();
export const SendError$ChannelNotOpen = () => SendError$ChannelNotOpen$const;
export const SendError$isChannelNotOpen = (value) =>
  value instanceof ChannelNotOpen;

export class SendFailed extends $CustomType {}
export const SendError$SendFailed$const = new SendFailed();
export const SendError$SendFailed = () => SendError$SendFailed$const;
export const SendError$isSendFailed = (value) => value instanceof SendFailed;

/**
 * The number of remote candidates that can wait for a remote description. A
 * peer that sends more than this number before it describes itself is flooding
 * the transport, and it is not negotiating.
 * 
 * @ignore
 */
const max_queued_candidates = 128;

/**
 * The label of the document data channel. There is one such channel for each
 * peer, and no other channel.
 */
export const document_channel_label = "watershed-crdt-v1";

export function signaling_session(room, peer_id) {
  return new SignalingSession(room, peer_id);
}

export function session_room(session) {
  return session.room;
}

export function session_peer_id(session) {
  return session.peer_id;
}

/**
 * A credential-free ICE server.
 */
export function ice_server(urls) {
  return new IceServer(urls, Option$None$const, Option$None$const);
}

/**
 * Add TURN credentials to an ICE server.
 */
export function with_credentials(server, username, credential) {
  return new IceServer(server.urls, new Some(username), new Some(credential));
}

/**
 * Free public STUN servers, for a caller that wants NAT traversal and deploys
 * nothing. The list holds the servers of Google and of Cloudflare. Those two
 * operators are independent of each other, and each one publishes these
 * addresses for exactly this use. The servers are free, they need no
 * credentials, and they have been stable for years. A STUN server only tells
 * a peer its own public address, in a few request and response packets for
 * each connection. That small cost is the reason that STUN is free, and STUN
 * is sufficient for most NAT pairs.
 *
 * This preset cannot cover one condition. Two peers behind *symmetric* NATs
 * have no direct path, and they need TURN. A TURN server carries the whole
 * stream, so there is no free public TURN service. A caller that needs those
 * pairs adds its own TURN server, with `ice_server` and `with_credentials`.
 *
 * These are best-effort services from a third party, on the infrastructure of
 * another company. That is the trade of this preset. A deployment that needs
 * a service level runs its own servers instead, for example coturn.
 */
export function public_stun_servers() {
  return toList([
    ice_server(toList(["stun:stun.l.google.com:19302"])),
    ice_server(toList(["stun:stun.cloudflare.com:3478"])),
  ]);
}

function encode_ice_server(server) {
  let base = toList([["urls", $json.array(server.urls, $json.string)]]);
  let _block;
  let $ = server.username;
  if ($ instanceof Some) {
    let username = $[0];
    _block = listPrepend(["username", $json.string(username)], base);
  } else {
    _block = base;
  }
  let with_user = _block;
  let _block$1;
  let $1 = server.credential;
  if ($1 instanceof Some) {
    let credential = $1[0];
    _block$1 = listPrepend(["credential", $json.string(credential)], with_user);
  } else {
    _block$1 = with_user;
  }
  let with_credential = _block$1;
  return $json.object($list.reverse(with_credential));
}

/**
 * The `RTCConfiguration` value that the peer connections are built with, as
 * JSON. This function emits the whole object, and the code does not pass one
 * field at a time. The FFI thus parses one object in the shape that the
 * browser needs, and a test can assert the exact configuration that the ICE
 * servers of a caller produce, with no browser.
 */
export function rtc_configuration_json(servers) {
  let _pipe = $json.object(
    toList([["iceServers", $json.array(servers, encode_ice_server)]]),
  );
  return $json.to_string(_pipe);
}

/**
 * The options of the document channel: unordered and reliable.
 *
 * `ordered: false` proves that the protocol does not depend on the delivery
 * order of one connection. The channel is reliable because the options omit
 * `maxRetransmits` and `maxPacketLifeTime`. To set either one makes a channel
 * lossy, so the correct encoding of "reliable" is the absence of both fields,
 * and not a large value.
 */
export function document_channel_options_json() {
  let _pipe = $json.object(toList([["ordered", $json.bool(false)]]));
  return $json.to_string(_pipe);
}

/**
 * The number of peers that one room permits, and that number includes the
 * local peer. The value comes from the core protocol limits, so the transport
 * and the wire agree by construction.
 */
export function room_limit() {
  return $crdt_wire.default_limits().room_peers;
}

/**
 * The native `RTCPeerConnection` backend. Each call returns a new registry, so
 * two transports on one page never share a connection.
 */
export function real_rtc() {
  let native = new_native_rtc();
  return new Rtc(
    (peer, configuration, hooks) => {
      return native_open(
        native,
        peer,
        configuration,
        hooks.on_negotiation_needed,
        hooks.on_description,
        hooks.on_remote_description,
        hooks.on_candidate,
        hooks.on_channel_open,
        hooks.on_channel_close,
        hooks.on_message,
        hooks.on_invalid_message,
        hooks.on_ice_state,
        hooks.on_failure,
      );
    },
    (peer, label, options) => {
      return native_open_channel(native, peer, label, options);
    },
    (peer) => { return native_offer(native, peer); },
    (peer, sdp) => { return native_accept_offer(native, peer, sdp); },
    (peer, sdp) => { return native_accept_answer(native, peer, sdp); },
    (peer, candidate) => {
      return native_add_candidate(native, peer, candidate);
    },
    (peer) => { return native_signaling_state(native, peer); },
    (peer, payload) => { return native_send(native, peer, payload); },
    (peer) => { return native_close(native, peer); },
    (peer) => { return native_diagnostics(native, peer); },
  );
}

function negotiation_role(local, remote) {
  let $ = $string.compare(local, remote);
  if ($ instanceof $order.Lt) {
    return NegotiationRole$Offerer$const;
  } else if ($ instanceof $order.Eq) {
    return NegotiationRole$Answerer$const;
  } else {
    return NegotiationRole$Answerer$const;
  }
}

function new_peer(local, remote) {
  return new Peer(
    remote,
    negotiation_role(local, remote),
    false,
    false,
    false,
    false,
    false,
    false,
    Option$None$const,
    $List$Empty$const,
    false,
  );
}

/**
 * Signaling failed after `join` returned. The transport reports a typed error
 * and does nothing more. An open data channel needs no signaling, so to close
 * the mesh here would destroy the connectivity that stayed.
 * 
 * @ignore
 */
function signaling_failed(cell, detail) {
  return $transport_js.get_cell(cell).callbacks.on_error(
    new $p2p.SignalingFailed(detail),
  );
}

function update_peer(cell, peer_id, change) {
  let state = $transport_js.get_cell(cell);
  let $ = $dict.get(state.peers, peer_id);
  if ($ instanceof Ok) {
    let peer = $[0];
    return $transport_js.set_cell(
      cell,
      new State(
        state.room,
        state.peer_id,
        state.signaling,
        state.session,
        state.rtc,
        state.configuration,
        state.callbacks,
        $dict.insert(state.peers, peer_id, change(peer)),
        state.pending_signals,
        state.closed,
      ),
    );
  } else {
    return undefined;
  }
}

function emit_peer_count(cell) {
  let state = $transport_js.get_cell(cell);
  let _block;
  let _pipe = state.peers;
  let _pipe$1 = $dict.values(_pipe);
  let _pipe$2 = $list.filter(_pipe$1, (peer) => { return peer.open; });
  _block = $list.length(_pipe$2);
  let open = _block;
  return state.callbacks.on_status(new PeerCount(open));
}

/**
 * The reporting half of a teardown, for a peer that `drop_peer` already
 * removed.
 * 
 * @ignore
 */
function report_teardown(cell, peer, failure) {
  let state = $transport_js.get_cell(cell);
  if (failure instanceof Some) {
    let detail = failure[0];
    state.callbacks.on_status(new PeerFailed(peer.id, detail));
  } else {
    undefined;
  }
  let $ = peer.open || peer.announced;
  if ($) {
    state.callbacks.on_status(new PeerClosed(peer.id));
  } else {
    undefined;
  }
  emit_peer_count(cell);
  if (failure instanceof Some) {
    let detail = failure[0];
    state.callbacks.on_error(new $p2p.PeerConnectionFailed(peer.id, detail));
  } else {
    undefined;
  }
  let $1 = peer.open;
  if ($1) {
    return state.callbacks.on_peer_close(peer.id);
  } else {
    return undefined;
  }
}

/**
 * The half of a teardown that must run before every application callback:
 * remove the peer and close its browser objects. An `Error(Nil)` result means that no
 * such peer existed, so the transport owes no report either.
 *
 * This function is separate because two paths report the event *before* the
 * peer is gone. Those paths are a terminal ICE state and a foreign message. A
 * callback that throws there must not be able to leave a dead connection in
 * the peer set, where `broadcast` can address it and where it holds a place in
 * the room.
 * 
 * @ignore
 */
function drop_peer(cell, peer_id) {
  let state = $transport_js.get_cell(cell);
  let $ = $dict.get(state.peers, peer_id);
  if ($ instanceof Ok) {
    let peer = $[0];
    $transport_js.set_cell(
      cell,
      new State(
        state.room,
        state.peer_id,
        state.signaling,
        state.session,
        state.rtc,
        state.configuration,
        state.callbacks,
        $dict.delete$(state.peers, peer_id),
        state.pending_signals,
        state.closed,
      ),
    );
    state.rtc.close(peer_id);
    return new Ok(peer);
  } else {
    return $;
  }
}

/**
 * Remove one peer. The function removes the record first, then it closes the
 * browser objects, and then it reports. The order makes the function
 * idempotent under a re-entrant callback: a listener that runs while the
 * connection closes finds no peer, and it does nothing.
 *
 * Every peer that the status stream announced as `PeerConnecting` gets a
 * `PeerClosed` status, whether or not it opened. A peer that fails during a
 * negotiation thus cannot leave a facade that renders it as connecting without
 * an end. The `on_peer_close` *callback* stays paired with `on_peer_open`, and
 * it runs only for a peer that opened.
 * 
 * @ignore
 */
function teardown(cell, peer_id, failure) {
  let $ = drop_peer(cell, peer_id);
  if ($ instanceof Ok) {
    let peer = $[0];
    return report_teardown(cell, peer, failure);
  } else {
    return undefined;
  }
}

/**
 * A remote candidate has no use until a remote description exists, and the
 * browser refuses it before that point. Each candidate thus waits in a queue,
 * and the transport applies the queue in arrival order after a description
 * arrives.
 *
 * The function drops a candidate for a peer that the transport does not know,
 * and it does not create that peer. A `PeerJoined` signal and an offer are the
 * two events that introduce a peer. A candidate that arrived before both of
 * them describes a connection that does not exist yet. To let that candidate
 * create a peer would also let a flooding peer return at the moment that its
 * flood closed it.
 * 
 * @ignore
 */
function handle_candidate(cell, from, candidate) {
  let known = $transport_js.get_cell(cell).peers;
  let $ = $dict.get(known, from);
  if ($ instanceof Ok) {
    let peer = $[0];
    let $1 = peer.have_remote_description;
    if ($1) {
      let state = $transport_js.get_cell(cell);
      return state.rtc.add_candidate(from, candidate);
    } else {
      let $2 = $list.contains(peer.queued_candidates, candidate);
      if ($2) {
        return undefined;
      } else {
        let $3 = $list.length(peer.queued_candidates) >= max_queued_candidates;
        if ($3) {
          return teardown(
            cell,
            from,
            new Some(
              ("queued more than " + $int.to_string(max_queued_candidates)) + " ice candidates before describing itself",
            ),
          );
        } else {
          return update_peer(
            cell,
            from,
            (peer) => {
              return new Peer(
                peer.id,
                peer.role,
                peer.announced,
                peer.channel_requested,
                peer.remote_offered,
                peer.making_offer,
                peer.ignore_offer,
                peer.have_remote_description,
                peer.last_remote_offer,
                listPrepend(candidate, peer.queued_candidates),
                peer.open,
              );
            },
          );
        }
      }
    }
  } else {
    return undefined;
  }
}

/**
 * An answer has a meaning only against an outstanding local offer. The
 * function drops every other answer, which is a duplicate, a reordered copy,
 * and an answer to an offer that the browser rolled back. It does not give
 * such an answer to the browser. The browser would refuse it asynchronously,
 * and it would then report a failure that is not a failure.
 * 
 * @ignore
 */
function handle_answer(cell, from, sdp) {
  let state = $transport_js.get_cell(cell);
  let $ = $dict.get(state.peers, from);
  if ($ instanceof Ok) {
    let $1 = state.rtc.signaling_state(from) === "have-local-offer";
    if ($1) {
      return state.rtc.accept_answer(from, sdp);
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

function tracked(cell, peer_id) {
  let $ = $dict.get($transport_js.get_cell(cell).peers, peer_id);
  if ($ instanceof Ok) {
    return true;
  } else {
    return false;
  }
}

/**
 * Remove the records that a failed stage left. The transport thus judges the
 * next signal against the real state of the connection, and not against an
 * attempt that never completed.
 * 
 * @ignore
 */
function clear_negotiation_flags(cell, peer_id, stage) {
  if (stage === "offer") {
    return update_peer(
      cell,
      peer_id,
      (peer) => {
        return new Peer(
          peer.id,
          peer.role,
          peer.announced,
          peer.channel_requested,
          peer.remote_offered,
          false,
          peer.ignore_offer,
          peer.have_remote_description,
          peer.last_remote_offer,
          peer.queued_candidates,
          peer.open,
        );
      },
    );
  } else if (stage === "answer") {
    return update_peer(
      cell,
      peer_id,
      (peer) => {
        return new Peer(
          peer.id,
          peer.role,
          peer.announced,
          peer.channel_requested,
          peer.remote_offered,
          false,
          peer.ignore_offer,
          peer.have_remote_description,
          Option$None$const,
          peer.queued_candidates,
          peer.open,
        );
      },
    );
  } else if (stage === "channel") {
    return update_peer(
      cell,
      peer_id,
      (peer) => {
        return new Peer(
          peer.id,
          peer.role,
          peer.announced,
          false,
          peer.remote_offered,
          peer.making_offer,
          peer.ignore_offer,
          peer.have_remote_description,
          peer.last_remote_offer,
          peer.queued_candidates,
          peer.open,
        );
      },
    );
  } else {
    return undefined;
  }
}

/**
 * Every asynchronous rejection from the browser arrives here, and it leaves as
 * a typed error that names the peer and the stage that failed.
 *
 * A description stage that fails clears the negotiation flags that the attempt
 * set, and it clears them in every condition. Without that step,
 * `making_offer` would stay set after a rejected `setLocalDescription` call. A
 * peer whose `making_offer` flag stays set reads every later remote offer as a
 * collision. When that peer is the impolite side, it refuses every one of
 * them, and the link then never works again.
 *
 * An answer stage that fails also removes the offer that it could not apply. A
 * second copy of that same offer thus gets an answer, and the transport does
 * not drop it as a duplicate.
 *
 * A channel stage that fails removes the request. The transport thus tries the
 * channel again the next time that it observes the peer.
 *
 * There is one exception to the report, and the perfect-negotiation algorithm
 * prescribes it. The browser cannot apply a candidate to a description that
 * this client refused. While `ignore_offer` is set, that one failure is
 * expected, and the transport does not report it. It reports every other
 * candidate failure.
 *
 * Two stages are terminal, and they also close the peer. In the `open` stage
 * the transport never constructed a connection. In the `connection` stage the
 * browser declared that an established connection failed. The transport
 * reports every other stage and changes nothing. A description or a send can
 * fail while the link is still usable, and the facade decides whether to close
 * a peer, after it receives the error.
 * 
 * @ignore
 */
function handle_failure(cell, peer_id, stage, detail) {
  let state = $transport_js.get_cell(cell);
  let $ = $dict.get(state.peers, peer_id);
  if ($ instanceof Ok) {
    let peer = $[0];
    let $1 = (stage === "candidate") && peer.ignore_offer;
    if ($1) {
      return undefined;
    } else {
      clear_negotiation_flags(cell, peer_id, stage);
      let described = (stage + ": ") + detail;
      let $2 = (stage === "open") || (stage === "connection");
      if ($2) {
        return teardown(cell, peer_id, new Some(described));
      } else {
        state.callbacks.on_status(new PeerFailed(peer_id, described));
        return state.callbacks.on_error(
          new $p2p.PeerConnectionFailed(peer_id, described),
        );
      }
    }
  } else {
    return undefined;
  }
}

/**
 * The transport reports the ICE state as a status. The `failed` state and the
 * `closed` state are terminal without a restart, so they also close the peer.
 * To keep such a peer in the peer set would report a mesh that is larger than
 * the real one.
 *
 * A terminal state removes the peer before the transport emits the status, for
 * the same reason as a foreign message. The connection is over, whatever the
 * callback of the application does with the report.
 *
 * The `disconnected` state is not terminal, and that is deliberate. The
 * browser recovers from it by itself, and to treat it as a loss would change
 * the presence on every short network fault.
 * 
 * @ignore
 */
function handle_ice_state(cell, peer_id, ice) {
  let state = $transport_js.get_cell(cell);
  let $ = $dict.get(state.peers, peer_id);
  if ($ instanceof Ok) {
    let $1 = (ice === "failed") || (ice === "closed");
    if ($1) {
      let dropped = drop_peer(cell, peer_id);
      state.callbacks.on_status(new IceState(peer_id, ice));
      if (dropped instanceof Ok) {
        let peer = dropped[0];
        return report_teardown(
          cell,
          peer,
          (() => {
            if (ice === "failed") {
              return new Some("ice connection failed");
            } else {
              return Option$None$const;
            }
          })(),
        );
      } else {
        return undefined;
      }
    } else {
      return state.callbacks.on_status(new IceState(peer_id, ice));
    }
  } else {
    return undefined;
  }
}

/**
 * The document channel carries strings. Every other value comes from a peer
 * that uses a protocol that this transport does not have. The transport thus
 * reports that value and closes the peer, and it does not skip the value.
 *
 * The function removes the peer before it sends the report. A foreign message
 * means that this connection is finished, and an `on_error` callback that
 * throws must not be able to keep that connection alive.
 * 
 * @ignore
 */
function handle_invalid_message(cell, peer_id, detail) {
  let state = $transport_js.get_cell(cell);
  let $ = $dict.get(state.peers, peer_id);
  if ($ instanceof Ok) {
    let dropped = drop_peer(cell, peer_id);
    state.callbacks.on_error(new $p2p.InvalidEnvelope(peer_id, detail));
    if (dropped instanceof Ok) {
      let peer = dropped[0];
      return report_teardown(cell, peer, Option$None$const);
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

/**
 * Run `action` only for a peer that this transport still tracks, and only on a
 * transport that is still open. A hook that runs for a peer that the transport
 * already closed is not an error. The browser can have a callback in flight
 * when `close` runs. There is simply nothing to do.
 * 
 * @ignore
 */
function with_peer(cell, peer_id, action) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = $dict.get(state.peers, peer_id);
  if (!$ && $1 instanceof Ok) {
    let peer = $1[0];
    return action(state, peer);
  } else {
    return undefined;
  }
}

function handle_message(cell, peer_id, data) {
  return with_peer(
    cell,
    peer_id,
    (state, _) => { return state.callbacks.on_document(peer_id, data); },
  );
}

function handle_channel_close(cell, peer_id) {
  return teardown(cell, peer_id, Option$None$const);
}

function handle_channel_open(cell, peer_id) {
  return with_peer(
    cell,
    peer_id,
    (state, peer) => {
      let $ = peer.open;
      if ($) {
        return undefined;
      } else {
        update_peer(
          cell,
          peer_id,
          (peer) => {
            return new Peer(
              peer.id,
              peer.role,
              peer.announced,
              peer.channel_requested,
              peer.remote_offered,
              peer.making_offer,
              peer.ignore_offer,
              peer.have_remote_description,
              peer.last_remote_offer,
              peer.queued_candidates,
              true,
            );
          },
        );
        state.callbacks.on_status(new PeerOpen(peer_id));
        emit_peer_count(cell);
        return state.callbacks.on_peer_open(peer_id);
      }
    },
  );
}

function signal_to(state, peer_id, payload) {
  let $ = state.session;
  if ($ instanceof Some) {
    let session = $[0];
    return state.signaling.send(session, peer_id, payload);
  } else {
    return undefined;
  }
}

function handle_local_candidate(cell, peer_id, candidate) {
  return with_peer(
    cell,
    peer_id,
    (state, _) => { return signal_to(state, peer_id, new Candidate(candidate)); },
  );
}

function handle_remote_description(cell, peer_id) {
  return with_peer(
    cell,
    peer_id,
    (state, peer) => {
      let queued = $list.reverse(peer.queued_candidates);
      update_peer(
        cell,
        peer_id,
        (peer) => {
          return new Peer(
            peer.id,
            peer.role,
            peer.announced,
            peer.channel_requested,
            peer.remote_offered,
            peer.making_offer,
            false,
            true,
            peer.last_remote_offer,
            $List$Empty$const,
            peer.open,
          );
        },
      );
      return $list.each(
        queued,
        (candidate) => { return state.rtc.add_candidate(peer_id, candidate); },
      );
    },
  );
}

function handle_local_description(cell, peer_id, kind, sdp) {
  return with_peer(
    cell,
    peer_id,
    (state, _) => {
      update_peer(
        cell,
        peer_id,
        (peer) => {
          return new Peer(
            peer.id,
            peer.role,
            peer.announced,
            peer.channel_requested,
            peer.remote_offered,
            false,
            peer.ignore_offer,
            peer.have_remote_description,
            peer.last_remote_offer,
            peer.queued_candidates,
            peer.open,
          );
        },
      );
      if (kind === "offer") {
        return signal_to(state, peer_id, new Offer(sdp));
      } else if (kind === "answer") {
        return signal_to(state, peer_id, new Answer(sdp));
      } else {
        let other = kind;
        return state.callbacks.on_error(
          new $p2p.PeerConnectionFailed(
            peer_id,
            "unexpected local description type: " + other,
          ),
        );
      }
    },
  );
}

function handle_negotiation_needed(cell, peer_id) {
  return with_peer(
    cell,
    peer_id,
    (state, _) => {
      update_peer(
        cell,
        peer_id,
        (peer) => {
          return new Peer(
            peer.id,
            peer.role,
            peer.announced,
            peer.channel_requested,
            peer.remote_offered,
            true,
            peer.ignore_offer,
            peer.have_remote_description,
            peer.last_remote_offer,
            peer.queued_candidates,
            peer.open,
          );
        },
      );
      return state.rtc.offer(peer_id);
    },
  );
}

function hooks(cell) {
  return new PeerHooks(
    (peer) => { return handle_negotiation_needed(cell, peer); },
    (peer, kind, sdp) => {
      return handle_local_description(cell, peer, kind, sdp);
    },
    (peer) => { return handle_remote_description(cell, peer); },
    (peer, candidate) => {
      return handle_local_candidate(cell, peer, candidate);
    },
    (peer) => { return handle_channel_open(cell, peer); },
    (peer) => { return handle_channel_close(cell, peer); },
    (peer, data) => { return handle_message(cell, peer, data); },
    (peer, detail) => { return handle_invalid_message(cell, peer, detail); },
    (peer, ice_state) => { return handle_ice_state(cell, peer, ice_state); },
    (peer, stage, detail) => {
      return handle_failure(cell, peer, stage, detail);
    },
  );
}

/**
 * Build the browser connection for a peer that the transport just started to
 * track, and report that peer as connecting. An `Error(Nil)` result means
 * that the peer was torn down before the browser call returned, so the
 * construction never lands.
 * 
 * @ignore
 */
function open_connection(cell, peer_id) {
  let state = $transport_js.get_cell(cell);
  state.rtc.open(peer_id, state.configuration, hooks(cell));
  let $ = tracked(cell, peer_id);
  if ($) {
    update_peer(
      cell,
      peer_id,
      (peer) => {
        return new Peer(
          peer.id,
          peer.role,
          true,
          peer.channel_requested,
          peer.remote_offered,
          peer.making_offer,
          peer.ignore_offer,
          peer.have_remote_description,
          peer.last_remote_offer,
          peer.queued_candidates,
          peer.open,
        );
      },
    );
    state.callbacks.on_status(new PeerConnecting(peer_id));
    return new Ok(undefined);
  } else {
    return new Error(undefined);
  }
}

/**
 * Find a peer, or create one, and report whether the function created it. An
 * `Error(Nil)` result means that the peer must not exist. That occurs when the
 * peer is this client, when this transport is closed, and when the room is
 * full.
 * 
 * @ignore
 */
function ensure_peer(cell, peer_id) {
  let state = $transport_js.get_cell(cell);
  let $ = (state.closed || (peer_id === state.peer_id)) || (peer_id === "");
  if ($) {
    return new Error(undefined);
  } else {
    let $1 = $dict.get(state.peers, peer_id);
    if ($1 instanceof Ok) {
      let peer = $1[0];
      return new Ok([peer, false]);
    } else {
      let limit = room_limit();
      let $2 = ($dict.size(state.peers) + 2) > limit;
      if ($2) {
        state.callbacks.on_error(new $p2p.RoomFull(limit));
        return new Error(undefined);
      } else {
        let peer = new_peer(state.peer_id, peer_id);
        $transport_js.set_cell(
          cell,
          new State(
            state.room,
            state.peer_id,
            state.signaling,
            state.session,
            state.rtc,
            state.configuration,
            state.callbacks,
            $dict.insert(state.peers, peer_id, peer),
            state.pending_signals,
            state.closed,
          ),
        );
        return new Ok([peer, true]);
      }
    }
  }
}

/**
 * Make sure that the peer which an inbound offer names exists, and record that
 * the peer offered.
 *
 * A peer can arrive on this path in two ways: an offer that reached the
 * signaling service before its `PeerJoined` signal, and a member that no
 * adapter announced. Such a peer gets a connection, and it gets no data
 * channel from this client, whichever side it is. An offer carries the channel
 * of the peer that offers, and that channel arrives in band through
 * `ondatachannel`. To create a second channel here would put two channels on
 * one link. A `PeerJoined` signal that arrives after the offer also creates no
 * channel, for the same reason.
 * 
 * @ignore
 */
function ensure_peer_for_offer(cell, peer_id) {
  let _block;
  let $ = ensure_peer(cell, peer_id);
  if ($ instanceof Ok) {
    let $1 = $[0][1];
    if ($1) {
      let peer = $[0][0];
      let $2 = open_connection(cell, peer_id);
      if ($2 instanceof Ok) {
        _block = new Ok(peer);
      } else {
        _block = $2;
      }
    } else {
      let peer = $[0][0];
      _block = new Ok(peer);
    }
  } else {
    _block = $;
  }
  let ensured = _block;
  if (ensured instanceof Ok) {
    let peer = ensured[0];
    update_peer(
      cell,
      peer_id,
      (peer) => {
        return new Peer(
          peer.id,
          peer.role,
          peer.announced,
          peer.channel_requested,
          true,
          peer.making_offer,
          peer.ignore_offer,
          peer.have_remote_description,
          peer.last_remote_offer,
          peer.queued_candidates,
          peer.open,
        );
      },
    );
    return new Ok(peer);
  } else {
    return ensured;
  }
}

/**
 * The collision guard of the perfect-negotiation algorithm.
 *
 * A collision occurs when a remote offer arrives while this client has an
 * offer of its own outstanding. The impolite peer is the peer with the smaller
 * id, in lexicographic order, and that peer is also the only peer that must
 * offer. That peer refuses the remote offer, and it records that refusal, so
 * the candidates of the refused description can fail without a report. The
 * polite peer accepts the remote offer, and the browser rolls its own local
 * offer back as part of that step.
 *
 * This rule also makes a duplicate offer and a reordered offer harmless. The
 * second copy arrives in a stable state, where to apply it again is a
 * renegotiation that changes nothing. Or it arrives in a collision, and the
 * same rule resolves it.
 *
 * ponytail: this collision cannot occur between two *conforming* peers. The
 * deterministic assignment of the roles, where the peer with the smaller id is
 * the only peer that offers, already prevents two simultaneous offers. This
 * collision machinery stays as a protection against a peer that does not
 * conform and offers out of turn. You can delete it if the mesh ever checks
 * conformance at admission.
 * 
 * @ignore
 */
function handle_offer(cell, from, sdp) {
  let $ = ensure_peer_for_offer(cell, from);
  if ($ instanceof Ok) {
    let peer = $[0];
    if (isEqual(peer.last_remote_offer, new Some(sdp))) {
      return undefined;
    } else {
      let peer = $[0];
      let state = $transport_js.get_cell(cell);
      let collision = peer.making_offer || (state.rtc.signaling_state(from) !== "stable");
      let $1 = collision && (peer.role instanceof Offerer);
      if ($1) {
        return update_peer(
          cell,
          from,
          (peer) => {
            return new Peer(
              peer.id,
              peer.role,
              peer.announced,
              peer.channel_requested,
              peer.remote_offered,
              peer.making_offer,
              true,
              peer.have_remote_description,
              peer.last_remote_offer,
              peer.queued_candidates,
              peer.open,
            );
          },
        );
      } else {
        update_peer(
          cell,
          from,
          (peer) => {
            return new Peer(
              peer.id,
              peer.role,
              peer.announced,
              peer.channel_requested,
              peer.remote_offered,
              false,
              false,
              peer.have_remote_description,
              new Some(sdp),
              peer.queued_candidates,
              peer.open,
            );
          },
        );
        return state.rtc.accept_offer(from, sdp);
      }
    }
  } else {
    return undefined;
  }
}

/**
 * Create the one document data channel for a peer that this client offers to,
 * if that peer has no channel yet.
 *
 * The function is idempotent, and the route does not matter. The peer that
 * offers ends with exactly one channel, whichever event first made the remote
 * peer known. That event is a `PeerJoined` for a new peer, a `PeerJoined` for
 * a member that was already in the room, or a repeat of either one. The side
 * that answers receives the channel through `ondatachannel`.
 *
 * The function does nothing for two kinds of peer. A peer that already offered
 * sends its own channel in band, so a second channel here would be one too
 * many. A peer whose channel is already open needs nothing.
 * 
 * @ignore
 */
function ensure_channel(cell, peer_id) {
  return with_peer(
    cell,
    peer_id,
    (state, peer) => {
      let $ = (((peer.role instanceof Offerer) && !peer.channel_requested) && !peer.remote_offered) && !peer.open;
      if ($) {
        update_peer(
          cell,
          peer_id,
          (peer) => {
            return new Peer(
              peer.id,
              peer.role,
              peer.announced,
              true,
              peer.remote_offered,
              peer.making_offer,
              peer.ignore_offer,
              peer.have_remote_description,
              peer.last_remote_offer,
              peer.queued_candidates,
              peer.open,
            );
          },
        );
        return state.rtc.open_channel(
          peer_id,
          document_channel_label,
          document_channel_options_json(),
        );
      } else {
        return undefined;
      }
    },
  );
}

/**
 * Track a peer and create its connection. When this client is the peer that
 * offers, also create the one data channel.
 *
 * The function does not create a peer that it already tracks, and it still
 * checks the channel of that peer. An adapter can report a member that the
 * transport first met as an inbound signal, and it can report a member whose
 * `createDataChannel` call failed. Neither member can stay without the channel
 * that drives the negotiation.
 *
 * The function checks the room limit first. The ninth member of a room gets no
 * `RTCPeerConnection`, and it gets a `RoomFull` error only.
 * 
 * @ignore
 */
function handle_peer_joined(cell, peer_id) {
  let $ = ensure_peer(cell, peer_id);
  if ($ instanceof Ok) {
    let $1 = $[0][1];
    if ($1) {
      let $2 = open_connection(cell, peer_id);
      if ($2 instanceof Ok) {
        return ensure_channel(cell, peer_id);
      } else {
        return undefined;
      }
    } else {
      return ensure_channel(cell, peer_id);
    }
  } else {
    return undefined;
  }
}

function emit(cell, status) {
  return $transport_js.get_cell(cell).callbacks.on_status(status);
}

/**
 * The complete membership of the room. The transport tracks every member in
 * the same way as an announcement of one member at a time, and only then does
 * it report the roster. A caller that reads `known_peers` from the
 * `SignalingRoster` status thus sees the whole room, and an empty roster does
 * mean an empty room.
 * 
 * @ignore
 */
function handle_roster(cell, peers) {
  $list.each(peers, (peer_id) => { return handle_peer_joined(cell, peer_id); });
  return emit(cell, new SignalingRoster(peers));
}

function handle_signal(cell, signal) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.session;
  if ($) {
    return undefined;
  } else if ($1 instanceof Some) {
    if (signal instanceof Roster) {
      let peers = signal.peers;
      return handle_roster(cell, peers);
    } else if (signal instanceof PeerJoined) {
      let peer_id = signal.peer_id;
      return handle_peer_joined(cell, peer_id);
    } else if (signal instanceof PeerLeft) {
      let peer_id = signal.peer_id;
      return teardown(cell, peer_id, Option$None$const);
    } else if (signal instanceof Message) {
      let $2 = signal.payload;
      if ($2 instanceof Offer) {
        let from = signal.from;
        let sdp = $2.sdp;
        return handle_offer(cell, from, sdp);
      } else if ($2 instanceof Answer) {
        let from = signal.from;
        let sdp = $2.sdp;
        return handle_answer(cell, from, sdp);
      } else {
        let from = signal.from;
        let candidate = $2.candidate;
        return handle_candidate(cell, from, candidate);
      }
    } else {
      let detail = signal.detail;
      return signaling_failed(cell, detail);
    }
  } else {
    return $transport_js.set_cell(
      cell,
      new State(
        state.room,
        state.peer_id,
        state.signaling,
        state.session,
        state.rtc,
        state.configuration,
        state.callbacks,
        state.peers,
        listPrepend(signal, state.pending_signals),
        state.closed,
      ),
    );
  }
}

function validate(room, peer_id) {
  if (room === "") {
    return new Error(new $p2p.SignalingFailed("room id must not be empty"));
  } else if (peer_id === "") {
    return new Error(new $p2p.SignalingFailed("peer id must not be empty"));
  } else {
    return new Ok(undefined);
  }
}

/**
 * `start` against a replacement browser seam. A test can thus drive the
 * negotiation, a collision, the candidate queue, and a failure
 * deterministically, and it needs no browser.
 */
export function start_with_rtc(
  room,
  peer_id,
  signaling,
  ice_servers,
  callbacks,
  rtc
) {
  return $result.try$(
    validate(room, peer_id),
    (_) => {
      let cell = $transport_js.new_cell(
        new State(
          room,
          peer_id,
          signaling,
          Option$None$const,
          rtc,
          rtc_configuration_json(ice_servers),
          callbacks,
          $dict.new$(),
          $List$Empty$const,
          false,
        ),
      );
      let $ = signaling.join(
        room,
        peer_id,
        (signal) => { return handle_signal(cell, signal); },
      );
      if ($ instanceof Ok) {
        let session = $[0];
        let state = $transport_js.get_cell(cell);
        let queued = $list.reverse(state.pending_signals);
        $transport_js.set_cell(
          cell,
          new State(
            state.room,
            state.peer_id,
            state.signaling,
            new Some(session),
            state.rtc,
            state.configuration,
            state.callbacks,
            state.peers,
            $List$Empty$const,
            state.closed,
          ),
        );
        emit(cell, new SignalingJoined(room, peer_id));
        $list.each(queued, (signal) => { return handle_signal(cell, signal); });
        return new Ok(new Transport(cell));
      } else {
        let detail = $[0];
        let state = $transport_js.get_cell(cell);
        $transport_js.set_cell(
          cell,
          new State(
            state.room,
            state.peer_id,
            state.signaling,
            state.session,
            state.rtc,
            state.configuration,
            state.callbacks,
            state.peers,
            state.pending_signals,
            true,
          ),
        );
        return new Error(new $p2p.SignalingFailed(detail));
      }
    },
  );
}

/**
 * Join a signaling room over real `RTCPeerConnection` objects.
 *
 * `peer_id` is the session identity of this connection, and a collision
 * between two of them is very unlikely. That id is the signaling address and
 * the tie-break key, so two live members of a room must never share one.
 * `ice_servers` follows the `RTCConfiguration` behaviour of the browser, and
 * the list can be empty. An empty list is correct on a LAN, and for a
 * same-origin loopback.
 */
export function start(room, peer_id, signaling, ice_servers, callbacks) {
  return start_with_rtc(
    room,
    peer_id,
    signaling,
    ice_servers,
    callbacks,
    real_rtc(),
  );
}

/**
 * The local peer id of this transport.
 */
export function local_peer_id(transport) {
  return $transport_js.get_cell(transport.cell).peer_id;
}

/**
 * The room that this transport joined.
 */
export function room(transport) {
  return $transport_js.get_cell(transport.cell).room;
}

/**
 * The peers whose document data channel is open, sorted. This list is the
 * whole of the p2p presence.
 */
export function open_peers(transport) {
  let _pipe = $transport_js.get_cell(transport.cell).peers;
  let _pipe$1 = $dict.values(_pipe);
  let _pipe$2 = $list.filter(_pipe$1, (peer) => { return peer.open; });
  let _pipe$3 = $list.map(_pipe$2, (peer) => { return peer.id; });
  return $list.sort(_pipe$3, $string.compare);
}

/**
 * The number of peers that have an open document data channel.
 */
export function open_peer_count(transport) {
  return $list.length(open_peers(transport));
}

/**
 * Every peer that this transport tracks, open or still in a negotiation.
 */
export function known_peers(transport) {
  let _pipe = $transport_js.get_cell(transport.cell).peers;
  let _pipe$1 = $dict.keys(_pipe);
  return $list.sort(_pipe$1, $string.compare);
}

/**
 * Whether `close` ran.
 */
export function is_closed(transport) {
  return $transport_js.get_cell(transport.cell).closed;
}

/**
 * A JSON description of the channel state and the connection state of one
 * peer.
 */
export function peer_diagnostics(transport, peer_id) {
  let state = $transport_js.get_cell(transport.cell);
  return state.rtc.diagnostics(peer_id);
}

/**
 * Send one encoded document message to one peer. An `Error` result names
 * which of the four ways the payload did not reach the peer. The caller
 * decides whether that condition needs a state exchange later, so this
 * function returns a value and it raises no exception.
 */
export function send(transport, peer_id, payload) {
  let state = $transport_js.get_cell(transport.cell);
  let $ = state.closed;
  let $1 = $dict.get(state.peers, peer_id);
  if ($) {
    return new Error(SendError$TransportClosed$const);
  } else if ($1 instanceof Ok) {
    let peer = $1[0];
    if (peer.open) {
      let $2 = state.rtc.send(peer_id, payload);
      if ($2) {
        return new Ok(undefined);
      } else {
        return new Error(SendError$SendFailed$const);
      }
    } else {
      return new Error(SendError$ChannelNotOpen$const);
    }
  } else {
    return new Error(SendError$UnknownPeer$const);
  }
}

/**
 * Send one encoded document message to every open peer, and return the number
 * of peers that accepted it.
 */
export function broadcast(transport, payload) {
  let _pipe = open_peers(transport);
  return $list.fold(
    _pipe,
    0,
    (sent, peer_id) => {
      let $ = send(transport, peer_id, payload);
      if ($ instanceof Ok) {
        return sent + 1;
      } else {
        return sent;
      }
    },
  );
}

/**
 * Close one peer. A second call has no more effect.
 */
export function close_peer(transport, peer_id) {
  return teardown(transport.cell, peer_id, Option$None$const);
}

/**
 * Close every peer, release the browser objects that the transport holds, and
 * leave the signaling room exactly one time. A second call does nothing, and
 * the transport acts on no signal that arrives after it.
 *
 * The transport releases everything that it owes to the outside world, which
 * is the browser objects and the signaling membership, *before* the first
 * application callback runs. An exception from a status callback or a peer
 * callback thus cannot leave a room joined or a connection open. That
 * exception still goes to the caller of `close`, and it skips the callbacks
 * after it. The transport is fully closed in both conditions.
 */
export function close(transport) {
  let cell = transport.cell;
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return undefined;
  } else {
    let peers = $dict.values(state.peers);
    $transport_js.set_cell(
      cell,
      new State(
        state.room,
        state.peer_id,
        state.signaling,
        Option$None$const,
        state.rtc,
        state.configuration,
        state.callbacks,
        $dict.new$(),
        state.pending_signals,
        true,
      ),
    );
    $list.each(peers, (peer) => { return state.rtc.close(peer.id); });
    let $1 = state.session;
    if ($1 instanceof Some) {
      let session = $1[0];
      state.signaling.leave(session);
    } else {
      undefined;
    }
    $list.each(
      peers,
      (peer) => {
        let $2 = peer.open || peer.announced;
        if ($2) {
          state.callbacks.on_status(new PeerClosed(peer.id));
        } else {
          undefined;
        }
        let $3 = peer.open;
        if ($3) {
          return state.callbacks.on_peer_close(peer.id);
        } else {
          return undefined;
        }
      },
    );
    state.callbacks.on_status(new PeerCount(0));
    return state.callbacks.on_status(Status$SignalingLeft$const);
  }
}

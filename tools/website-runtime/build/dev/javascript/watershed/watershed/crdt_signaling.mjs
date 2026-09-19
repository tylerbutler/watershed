/// <reference types="./crdt_signaling.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  toBitArray,
  stringBits,
} from "../gleam.mjs";
import * as $crdt_wire from "../watershed/crdt_wire.mjs";
import * as $p2p_transport_js from "../watershed/p2p_transport_js.mjs";
import { Answer, Candidate, Offer } from "../watershed/p2p_transport_js.mjs";

export class Join extends $CustomType {
  constructor(room, peer) {
    super();
    this.room = room;
    this.peer = peer;
  }
}
export const ClientFrame$Join = (room, peer) => new Join(room, peer);
export const ClientFrame$isJoin = (value) => value instanceof Join;
export const ClientFrame$Join$room = (value) => value.room;
export const ClientFrame$Join$0 = (value) => value.room;
export const ClientFrame$Join$peer = (value) => value.peer;
export const ClientFrame$Join$1 = (value) => value.peer;

export class Signal extends $CustomType {
  constructor(to, payload) {
    super();
    this.to = to;
    this.payload = payload;
  }
}
export const ClientFrame$Signal = (to, payload) => new Signal(to, payload);
export const ClientFrame$isSignal = (value) => value instanceof Signal;
export const ClientFrame$Signal$to = (value) => value.to;
export const ClientFrame$Signal$0 = (value) => value.to;
export const ClientFrame$Signal$payload = (value) => value.payload;
export const ClientFrame$Signal$1 = (value) => value.payload;

export class Leave extends $CustomType {}
export const ClientFrame$Leave$const = new Leave();
export const ClientFrame$Leave = () => ClientFrame$Leave$const;
export const ClientFrame$isLeave = (value) => value instanceof Leave;

/**
 * The admission of a peer, with the existing members of the room.
 */
export class Joined extends $CustomType {
  constructor(room, peer, peers) {
    super();
    this.room = room;
    this.peer = peer;
    this.peers = peers;
  }
}
export const ServerFrame$Joined = (room, peer, peers) =>
  new Joined(room, peer, peers);
export const ServerFrame$isJoined = (value) => value instanceof Joined;
export const ServerFrame$Joined$room = (value) => value.room;
export const ServerFrame$Joined$0 = (value) => value.room;
export const ServerFrame$Joined$peer = (value) => value.peer;
export const ServerFrame$Joined$1 = (value) => value.peer;
export const ServerFrame$Joined$peers = (value) => value.peers;
export const ServerFrame$Joined$2 = (value) => value.peers;

export class PeerJoined extends $CustomType {
  constructor(peer) {
    super();
    this.peer = peer;
  }
}
export const ServerFrame$PeerJoined = (peer) => new PeerJoined(peer);
export const ServerFrame$isPeerJoined = (value) => value instanceof PeerJoined;
export const ServerFrame$PeerJoined$peer = (value) => value.peer;
export const ServerFrame$PeerJoined$0 = (value) => value.peer;

export class PeerLeft extends $CustomType {
  constructor(peer) {
    super();
    this.peer = peer;
  }
}
export const ServerFrame$PeerLeft = (peer) => new PeerLeft(peer);
export const ServerFrame$isPeerLeft = (value) => value instanceof PeerLeft;
export const ServerFrame$PeerLeft$peer = (value) => value.peer;
export const ServerFrame$PeerLeft$0 = (value) => value.peer;

export class Forwarded extends $CustomType {
  constructor(from, payload) {
    super();
    this.from = from;
    this.payload = payload;
  }
}
export const ServerFrame$Forwarded = (from, payload) =>
  new Forwarded(from, payload);
export const ServerFrame$isForwarded = (value) => value instanceof Forwarded;
export const ServerFrame$Forwarded$from = (value) => value.from;
export const ServerFrame$Forwarded$0 = (value) => value.from;
export const ServerFrame$Forwarded$payload = (value) => value.payload;
export const ServerFrame$Forwarded$1 = (value) => value.payload;

/**
 * A refusal that ends the connection. `reason` is a stable tag for a
 * program to read. `detail` is prose for a person to read.
 */
export class Rejected extends $CustomType {
  constructor(reason, detail) {
    super();
    this.reason = reason;
    this.detail = detail;
  }
}
export const ServerFrame$Rejected = (reason, detail) =>
  new Rejected(reason, detail);
export const ServerFrame$isRejected = (value) => value instanceof Rejected;
export const ServerFrame$Rejected$reason = (value) => value.reason;
export const ServerFrame$Rejected$0 = (value) => value.reason;
export const ServerFrame$Rejected$detail = (value) => value.detail;
export const ServerFrame$Rejected$1 = (value) => value.detail;

/**
 * The service could not deliver one frame, and the connection is correct.
 * One condition produces this frame: a signal addressed to a peer that is
 * no longer in the room. That occurs when a candidate loses a race with a
 * leave, which is usual in a mesh and is not a protocol violation.
 */
export class Dropped extends $CustomType {
  constructor(reason, detail) {
    super();
    this.reason = reason;
    this.detail = detail;
  }
}
export const ServerFrame$Dropped = (reason, detail) =>
  new Dropped(reason, detail);
export const ServerFrame$isDropped = (value) => value instanceof Dropped;
export const ServerFrame$Dropped$reason = (value) => value.reason;
export const ServerFrame$Dropped$0 = (value) => value.reason;
export const ServerFrame$Dropped$detail = (value) => value.detail;
export const ServerFrame$Dropped$1 = (value) => value.detail;

export class Send extends $CustomType {
  constructor(connection, frame) {
    super();
    this.connection = connection;
    this.frame = frame;
  }
}
export const Action$Send = (connection, frame) => new Send(connection, frame);
export const Action$isSend = (value) => value instanceof Send;
export const Action$Send$connection = (value) => value.connection;
export const Action$Send$0 = (value) => value.connection;
export const Action$Send$frame = (value) => value.frame;
export const Action$Send$1 = (value) => value.frame;

/**
 * Close a connection, after every `Send` action that the module already
 * emitted for it.
 */
export class Close extends $CustomType {
  constructor(connection, reason) {
    super();
    this.connection = connection;
    this.reason = reason;
  }
}
export const Action$Close = (connection, reason) =>
  new Close(connection, reason);
export const Action$isClose = (value) => value instanceof Close;
export const Action$Close$connection = (value) => value.connection;
export const Action$Close$0 = (value) => value.connection;
export const Action$Close$reason = (value) => value.reason;
export const Action$Close$1 = (value) => value.reason;

export const Action$connection = (value) => value.connection;

export class FrameTooLarge extends $CustomType {
  constructor(bytes) {
    super();
    this.bytes = bytes;
  }
}
export const Refusal$FrameTooLarge = (bytes) => new FrameTooLarge(bytes);
export const Refusal$isFrameTooLarge = (value) =>
  value instanceof FrameTooLarge;
export const Refusal$FrameTooLarge$bytes = (value) => value.bytes;
export const Refusal$FrameTooLarge$0 = (value) => value.bytes;

export class Malformed extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const Refusal$Malformed = (detail) => new Malformed(detail);
export const Refusal$isMalformed = (value) => value instanceof Malformed;
export const Refusal$Malformed$detail = (value) => value.detail;
export const Refusal$Malformed$0 = (value) => value.detail;

export class NotJoined extends $CustomType {}
export const Refusal$NotJoined$const = new NotJoined();
export const Refusal$NotJoined = () => Refusal$NotJoined$const;
export const Refusal$isNotJoined = (value) => value instanceof NotJoined;

export class AlreadyJoined extends $CustomType {}
export const Refusal$AlreadyJoined$const = new AlreadyJoined();
export const Refusal$AlreadyJoined = () => Refusal$AlreadyJoined$const;
export const Refusal$isAlreadyJoined = (value) =>
  value instanceof AlreadyJoined;

export class DuplicatePeerId extends $CustomType {
  constructor(peer) {
    super();
    this.peer = peer;
  }
}
export const Refusal$DuplicatePeerId = (peer) => new DuplicatePeerId(peer);
export const Refusal$isDuplicatePeerId = (value) =>
  value instanceof DuplicatePeerId;
export const Refusal$DuplicatePeerId$peer = (value) => value.peer;
export const Refusal$DuplicatePeerId$0 = (value) => value.peer;

export class RoomFull extends $CustomType {
  constructor(limit) {
    super();
    this.limit = limit;
  }
}
export const Refusal$RoomFull = (limit) => new RoomFull(limit);
export const Refusal$isRoomFull = (value) => value instanceof RoomFull;
export const Refusal$RoomFull$limit = (value) => value.limit;
export const Refusal$RoomFull$0 = (value) => value.limit;

/**
 * A signal addressed to a peer that is in *another* room. The room is the
 * whole of the addressing, so a name across a room boundary is a
 * violation.
 */
export class CrossRoomTarget extends $CustomType {
  constructor(peer) {
    super();
    this.peer = peer;
  }
}
export const Refusal$CrossRoomTarget = (peer) => new CrossRoomTarget(peer);
export const Refusal$isCrossRoomTarget = (value) =>
  value instanceof CrossRoomTarget;
export const Refusal$CrossRoomTarget$peer = (value) => value.peer;
export const Refusal$CrossRoomTarget$0 = (value) => value.peer;

/**
 * A signal addressed to a peer that is in no room. In almost every case
 * that peer left between the moment at which the sender decided to write
 * and the moment at which the frame arrived. Every mesh runs that race
 * often.
 */
export class UnknownTarget extends $CustomType {
  constructor(peer) {
    super();
    this.peer = peer;
  }
}
export const Refusal$UnknownTarget = (peer) => new UnknownTarget(peer);
export const Refusal$isUnknownTarget = (value) =>
  value instanceof UnknownTarget;
export const Refusal$UnknownTarget$peer = (value) => value.peer;
export const Refusal$UnknownTarget$0 = (value) => value.peer;

export class InvalidId extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const Refusal$InvalidId = (detail) => new InvalidId(detail);
export const Refusal$isInvalidId = (value) => value instanceof InvalidId;
export const Refusal$InvalidId$detail = (value) => value.detail;
export const Refusal$InvalidId$0 = (value) => value.detail;

class Rooms extends $CustomType {
  constructor(rooms, members, occupancy) {
    super();
    this.rooms = rooms;
    this.members = members;
    this.occupancy = occupancy;
  }
}

/**
 * The largest signaling frame that the module accepts, in bytes.
 *
 * An SDP offer with several candidates is a few kilobytes, and this limit is
 * generous for that. It is also much less than the 256 KiB of a document
 * envelope. The size check alone thus refuses anything with the shape of a
 * document, before the module parses it.
 */
export const max_frame_bytes = 16_384;

/**
 * The longest room id or peer id that the module accepts, **in UTF-8 bytes**.
 * The service echoes both to the other peers, so an id with no limit is a way
 * to amplify traffic. The service echoes bytes, and not graphemes. One emoji
 * is four bytes, so a limit on the grapheme count would permit a frame four
 * times the size that the limit states.
 */
export const max_id_bytes = 128;

/**
 * The number of peers that one room permits. The value comes from the core
 * protocol limits, so the service, the transport, and the wire cannot
 * disagree.
 */
export function room_limit() {
  return $crdt_wire.default_limits().room_peers;
}

/**
 * Whether a refusal ends the connection.
 *
 * Every condition that a peer can get *wrong* ends it: a malformed frame, an
 * oversize frame, a signal before a join, a duplicate id, a full room, and a
 * target in another room. A target that left is not one of those conditions.
 * To close the sender for it would let any peer close another peer, by
 * leaving at the correct moment. The `peerLeft` frame that explains the
 * departure is already on its way.
 */
export function is_terminal(refusal) {
  if (refusal instanceof FrameTooLarge) {
    return true;
  } else if (refusal instanceof Malformed) {
    return true;
  } else if (refusal instanceof NotJoined) {
    return true;
  } else if (refusal instanceof AlreadyJoined) {
    return true;
  } else if (refusal instanceof DuplicatePeerId) {
    return true;
  } else if (refusal instanceof RoomFull) {
    return true;
  } else if (refusal instanceof CrossRoomTarget) {
    return true;
  } else if (refusal instanceof UnknownTarget) {
    return false;
  } else {
    return true;
  }
}

export function refusal_parts(refusal) {
  if (refusal instanceof FrameTooLarge) {
    let bytes = refusal.bytes;
    return [
      "frameTooLarge",
      ($int.to_string(bytes) + " bytes, limit ") + $int.to_string(
        max_frame_bytes,
      ),
    ];
  } else if (refusal instanceof Malformed) {
    let detail = refusal.detail;
    return ["malformed", detail];
  } else if (refusal instanceof NotJoined) {
    return ["notJoined", "join before signalling"];
  } else if (refusal instanceof AlreadyJoined) {
    return ["alreadyJoined", "this connection has already joined"];
  } else if (refusal instanceof DuplicatePeerId) {
    let peer = refusal.peer;
    return ["duplicatePeerId", peer];
  } else if (refusal instanceof RoomFull) {
    let limit = refusal.limit;
    return ["roomFull", $int.to_string(limit)];
  } else if (refusal instanceof CrossRoomTarget) {
    let peer = refusal.peer;
    return ["crossRoomTarget", peer];
  } else if (refusal instanceof UnknownTarget) {
    let peer = refusal.peer;
    return ["unknownTarget", peer];
  } else {
    let detail = refusal.detail;
    return ["invalidId", detail];
  }
}

/**
 * The codec for a signal payload. `watershed/nostr_signaling_js` shares it.
 * The two lanes carry the same three WebRTC payloads, so they encode them in
 * the same way.
 */
export function encode_payload(payload) {
  if (payload instanceof Offer) {
    let sdp = payload.sdp;
    return $json.object(
      toList([["t", $json.string("offer")], ["sdp", $json.string(sdp)]]),
    );
  } else if (payload instanceof Answer) {
    let sdp = payload.sdp;
    return $json.object(
      toList([["t", $json.string("answer")], ["sdp", $json.string(sdp)]]),
    );
  } else {
    let candidate = payload.candidate;
    return $json.object(
      toList([
        ["t", $json.string("candidate")],
        ["candidate", $json.string(candidate)],
      ]),
    );
  }
}

export function encode_client(frame) {
  if (frame instanceof Join) {
    let room = frame.room;
    let peer = frame.peer;
    return $json.object(
      toList([
        ["t", $json.string("join")],
        ["room", $json.string(room)],
        ["peer", $json.string(peer)],
      ]),
    );
  } else if (frame instanceof Signal) {
    let to = frame.to;
    let payload = frame.payload;
    return $json.object(
      toList([
        ["t", $json.string("signal")],
        ["to", $json.string(to)],
        ["payload", encode_payload(payload)],
      ]),
    );
  } else {
    return $json.object(toList([["t", $json.string("leave")]]));
  }
}

export function client_to_string(frame) {
  return $json.to_string(encode_client(frame));
}

export function encode_server(frame) {
  if (frame instanceof Joined) {
    let room = frame.room;
    let peer = frame.peer;
    let peers = frame.peers;
    return $json.object(
      toList([
        ["t", $json.string("joined")],
        ["room", $json.string(room)],
        ["peer", $json.string(peer)],
        ["peers", $json.array(peers, $json.string)],
      ]),
    );
  } else if (frame instanceof PeerJoined) {
    let peer = frame.peer;
    return $json.object(
      toList([["t", $json.string("peerJoined")], ["peer", $json.string(peer)]]),
    );
  } else if (frame instanceof PeerLeft) {
    let peer = frame.peer;
    return $json.object(
      toList([["t", $json.string("peerLeft")], ["peer", $json.string(peer)]]),
    );
  } else if (frame instanceof Forwarded) {
    let from = frame.from;
    let payload = frame.payload;
    return $json.object(
      toList([
        ["t", $json.string("signal")],
        ["from", $json.string(from)],
        ["payload", encode_payload(payload)],
      ]),
    );
  } else if (frame instanceof Rejected) {
    let reason = frame.reason;
    let detail = frame.detail;
    return $json.object(
      toList([
        ["t", $json.string("error")],
        ["reason", $json.string(reason)],
        ["detail", $json.string(detail)],
      ]),
    );
  } else {
    let reason = frame.reason;
    let detail = frame.detail;
    return $json.object(
      toList([
        ["t", $json.string("dropped")],
        ["reason", $json.string(reason)],
        ["detail", $json.string(detail)],
      ]),
    );
  }
}

export function server_to_string(frame) {
  return $json.to_string(encode_server(frame));
}

function valid_id(value, what) {
  let $ = value === "";
  let $1 = $bit_array.byte_size(toBitArray([stringBits(value)])) > max_id_bytes;
  if ($) {
    return new Error(new InvalidId(what + " id is empty"));
  } else if ($1) {
    return new Error(
      new InvalidId(
        ((what + " id is longer than ") + $int.to_string(max_id_bytes)) + " bytes",
      ),
    );
  } else {
    return new Ok(undefined);
  }
}

function validate_client(frame) {
  if (frame instanceof Join) {
    let room = frame.room;
    let peer = frame.peer;
    return $result.try$(
      valid_id(room, "room"),
      (_) => {
        return $result.try$(
          valid_id(peer, "peer"),
          (_) => { return new Ok(frame); },
        );
      },
    );
  } else if (frame instanceof Signal) {
    let to = frame.to;
    return $result.try$(
      valid_id(to, "target"),
      (_) => { return new Ok(frame); },
    );
  } else {
    return new Ok(frame);
  }
}

/**
 * The decoder for `encode_payload`. It is public for the same reason.
 */
export function payload_decoder() {
  return $decode.field(
    "t",
    $decode.string,
    (tag) => {
      if (tag === "offer") {
        return $decode.field(
          "sdp",
          $decode.string,
          (sdp) => { return $decode.success(new Offer(sdp)); },
        );
      } else if (tag === "answer") {
        return $decode.field(
          "sdp",
          $decode.string,
          (sdp) => { return $decode.success(new Answer(sdp)); },
        );
      } else if (tag === "candidate") {
        return $decode.field(
          "candidate",
          $decode.string,
          (candidate) => { return $decode.success(new Candidate(candidate)); },
        );
      } else {
        return $decode.failure(new Candidate(""), "signal payload");
      }
    },
  );
}

function client_decoder() {
  return $decode.field(
    "t",
    $decode.string,
    (tag) => {
      if (tag === "join") {
        return $decode.field(
          "room",
          $decode.string,
          (room) => {
            return $decode.field(
              "peer",
              $decode.string,
              (peer) => { return $decode.success(new Join(room, peer)); },
            );
          },
        );
      } else if (tag === "signal") {
        return $decode.field(
          "to",
          $decode.string,
          (to) => {
            return $decode.field(
              "payload",
              payload_decoder(),
              (payload) => { return $decode.success(new Signal(to, payload)); },
            );
          },
        );
      } else if (tag === "leave") {
        return $decode.success(ClientFrame$Leave$const);
      } else {
        return $decode.failure(ClientFrame$Leave$const, "signaling frame");
      }
    },
  );
}

function check_size(raw) {
  let bytes = $bit_array.byte_size(toBitArray([stringBits(raw)]));
  let $ = bytes > max_frame_bytes;
  if ($) {
    return new Error(new FrameTooLarge(bytes));
  } else {
    return new Ok(undefined);
  }
}

/**
 * Decode a client frame. The function is total. It checks the size first,
 * then the JSON, and then the closed set of tags. Every other value is a
 * `Refusal`, and never a routed frame. That includes every shape that a
 * `crdt_wire.Envelope` value can take.
 */
export function decode_client(raw) {
  return $result.try$(
    check_size(raw),
    (_) => {
      return $result.try$(
        (() => {
          let _pipe = $json.parse(raw, client_decoder());
          return $result.replace_error(
            _pipe,
            new Malformed("not a signaling frame"),
          );
        })(),
        (frame) => { return validate_client(frame); },
      );
    },
  );
}

function server_decoder() {
  return $decode.field(
    "t",
    $decode.string,
    (tag) => {
      if (tag === "joined") {
        return $decode.field(
          "room",
          $decode.string,
          (room) => {
            return $decode.field(
              "peer",
              $decode.string,
              (peer) => {
                return $decode.field(
                  "peers",
                  $decode.list($decode.string),
                  (peers) => {
                    return $decode.success(new Joined(room, peer, peers));
                  },
                );
              },
            );
          },
        );
      } else if (tag === "peerJoined") {
        return $decode.field(
          "peer",
          $decode.string,
          (peer) => { return $decode.success(new PeerJoined(peer)); },
        );
      } else if (tag === "peerLeft") {
        return $decode.field(
          "peer",
          $decode.string,
          (peer) => { return $decode.success(new PeerLeft(peer)); },
        );
      } else if (tag === "signal") {
        return $decode.field(
          "from",
          $decode.string,
          (from) => {
            return $decode.field(
              "payload",
              payload_decoder(),
              (payload) => {
                return $decode.success(new Forwarded(from, payload));
              },
            );
          },
        );
      } else if (tag === "error") {
        return $decode.field(
          "reason",
          $decode.string,
          (reason) => {
            return $decode.field(
              "detail",
              $decode.string,
              (detail) => {
                return $decode.success(new Rejected(reason, detail));
              },
            );
          },
        );
      } else if (tag === "dropped") {
        return $decode.field(
          "reason",
          $decode.string,
          (reason) => {
            return $decode.field(
              "detail",
              $decode.string,
              (detail) => {
                return $decode.success(new Dropped(reason, detail));
              },
            );
          },
        );
      } else {
        return $decode.failure(new PeerLeft(""), "signaling frame");
      }
    },
  );
}

/**
 * Decode a server frame, for the browser adapter.
 */
export function decode_server(raw) {
  return $result.try$(
    check_size(raw),
    (_) => {
      let _pipe = $json.parse(raw, server_decoder());
      return $result.replace_error(
        _pipe,
        new Malformed("not a signaling frame"),
      );
    },
  );
}

export function new_rooms() {
  return new Rooms($dict.new$(), $dict.new$(), $dict.new$());
}

/**
 * The peer ids in a room, sorted.
 */
export function members(rooms, room) {
  let $ = $dict.get(rooms.rooms, room);
  if ($ instanceof Ok) {
    let peers = $[0];
    let _pipe = $dict.keys(peers);
    return $list.sort(_pipe, $string.compare);
  } else {
    return $List$Empty$const;
  }
}

/**
 * The room names that the registry holds now, sorted. The registry deletes a
 * room that becomes empty, so a room in this list has one member or more.
 */
export function room_names(rooms) {
  let _pipe = $dict.keys(rooms.rooms);
  return $list.sort(_pipe, $string.compare);
}

/**
 * The room and the peer id that a connection joined with.
 */
export function membership(rooms, connection) {
  return $dict.get(rooms.members, connection);
}

/**
 * Change the room count of a peer id by `delta`, and remove the id at zero.
 * The index thus holds only the ids that are in a room.
 * 
 * @ignore
 */
function adjust(occupancy, peer, delta) {
  let _block;
  let $ = $dict.get(occupancy, peer);
  if ($ instanceof Ok) {
    let count = $[0];
    _block = count;
  } else {
    _block = 0;
  }
  let count = _block;
  let $1 = count + delta;
  let total = $1;
  if (total <= 0) {
    return $dict.delete$(occupancy, peer);
  } else {
    let total = $1;
    return $dict.insert(occupancy, peer, total);
  }
}

/**
 * Remove a connection, tell its room, and delete that room when it becomes
 * empty. A second call has no more effect. A connection that is not a member
 * produces no action.
 */
export function disconnect(rooms, connection) {
  let $ = $dict.get(rooms.members, connection);
  if ($ instanceof Ok) {
    let room = $[0][0];
    let peer = $[0][1];
    let _block;
    let $1 = $dict.get(rooms.rooms, room);
    if ($1 instanceof Ok) {
      let peers = $1[0];
      _block = $dict.delete$(peers, peer);
    } else {
      _block = $dict.new$();
    }
    let occupants = _block;
    let rooms$1 = new Rooms(
      (() => {
        let $2 = $dict.size(occupants);
        if ($2 === 0) {
          return $dict.delete$(rooms.rooms, room);
        } else {
          return $dict.insert(rooms.rooms, room, occupants);
        }
      })(),
      $dict.delete$(rooms.members, connection),
      adjust(rooms.occupancy, peer, -1),
    );
    let _block$1;
    let _pipe = $dict.to_list(occupants);
    let _pipe$1 = $list.sort(
      _pipe,
      (left, right) => { return $string.compare(left[0], right[0]); },
    );
    _block$1 = $list.map(
      _pipe$1,
      (entry) => { return new Send(entry[1], new PeerLeft(peer)); },
    );
    let notices = _block$1;
    return [rooms$1, notices];
  } else {
    return [rooms, $List$Empty$const];
  }
}

function refuse(connection, refusal) {
  let $ = refusal_parts(refusal);
  let reason = $[0];
  let detail = $[1];
  let $1 = is_terminal(refusal);
  if ($1) {
    return toList([
      new Send(connection, new Rejected(reason, detail)),
      new Close(connection, reason),
    ]);
  } else {
    return toList([new Send(connection, new Dropped(reason, detail))]);
  }
}

/**
 * A refusal. Tell the connection the reason, close it if the refusal is
 * terminal, and do not change the registry.
 * 
 * @ignore
 */
function refused(rooms, connection, refusal) {
  return [rooms, refuse(connection, refusal), new Error(refusal)];
}

/**
 * Whether `peer` is a member of a room other than `room`. A caller asks this
 * question only about a peer that the room of the sender does not hold, so any
 * occupancy at all is occupancy in another room.
 * 
 * @ignore
 */
function elsewhere(rooms, room, peer) {
  let _block;
  let $ = $dict.get(rooms.rooms, room);
  if ($ instanceof Ok) {
    let occupants = $[0];
    _block = $dict.has_key(occupants, peer);
  } else {
    _block = false;
  }
  let here = _block;
  let $1 = $dict.get(rooms.occupancy, peer);
  if (here) {
    return false;
  } else if ($1 instanceof Ok) {
    let count = $1[0];
    return count > 0;
  } else {
    return here;
  }
}

/**
 * Route one opaque payload to one named peer in the room of the sender.
 *
 * There are two ways to miss, and they are not the same fault. A target that
 * is a member of another room means that the sender named a peer across a
 * room boundary. That is a violation, and the service closes the sender. A
 * target that is in no room means that the peer left in the middle of the
 * negotiation. The service drops the frame, tells the sender, and does not
 * change the membership of the sender.
 * 
 * @ignore
 */
function forward(rooms, connection, room, peer, to, payload) {
  let _block;
  let $ = $dict.get(rooms.rooms, room);
  if ($ instanceof Ok) {
    let occupants = $[0];
    _block = occupants;
  } else {
    _block = $dict.new$();
  }
  let occupants = _block;
  let $1 = $dict.get(occupants, to);
  if ($1 instanceof Ok) {
    let target = $1[0];
    return [
      rooms,
      toList([new Send(target, new Forwarded(peer, payload))]),
      new Ok(undefined),
    ];
  } else {
    let $2 = elsewhere(rooms, room, to);
    if ($2) {
      return refused(rooms, connection, new CrossRoomTarget(to));
    } else {
      return refused(rooms, connection, new UnknownTarget(to));
    }
  }
}

function join(rooms, connection, room, peer) {
  let _block;
  let $ = $dict.get(rooms.rooms, room);
  if ($ instanceof Ok) {
    let peers = $[0];
    _block = peers;
  } else {
    _block = $dict.new$();
  }
  let occupants = _block;
  let $1 = $dict.has_key(occupants, peer);
  let $2 = $dict.size(occupants) >= room_limit();
  if ($1) {
    return refused(rooms, connection, new DuplicatePeerId(peer));
  } else if ($2) {
    return refused(rooms, connection, new RoomFull(room_limit()));
  } else {
    let _block$1;
    let _pipe = $dict.keys(occupants);
    _block$1 = $list.sort(_pipe, $string.compare);
    let existing = _block$1;
    let rooms$1 = new Rooms(
      $dict.insert(rooms.rooms, room, $dict.insert(occupants, peer, connection)),
      $dict.insert(rooms.members, connection, [room, peer]),
      adjust(rooms.occupancy, peer, 1),
    );
    let _block$2;
    let _pipe$1 = $dict.to_list(occupants);
    let _pipe$2 = $list.sort(
      _pipe$1,
      (left, right) => { return $string.compare(left[0], right[0]); },
    );
    _block$2 = $list.map(
      _pipe$2,
      (entry) => { return new Send(entry[1], new PeerJoined(peer)); },
    );
    let announcements = _block$2;
    return [
      rooms$1,
      listPrepend(
        new Send(connection, new Joined(room, peer, existing)),
        announcements,
      ),
      new Ok(undefined),
    ];
  }
}

/**
 * Apply one decoded frame, and return whether the registry refused it.
 *
 * The function returns the refusal, and a caller does not derive it from the
 * actions. The instrumentation of a service must separate a routed `signal`
 * from a refused one without an examination of either frame. To read the
 * result would mean to read frames that the service must not read.
 * 
 * @ignore
 */
function apply_frame(rooms, connection, frame) {
  let $ = $dict.get(rooms.members, connection);
  if ($ instanceof Ok) {
    if (frame instanceof Join) {
      return refused(rooms, connection, Refusal$AlreadyJoined$const);
    } else if (frame instanceof Signal) {
      let to = frame.to;
      let payload = frame.payload;
      let room = $[0][0];
      let peer = $[0][1];
      return forward(rooms, connection, room, peer, to, payload);
    } else {
      let $1 = disconnect(rooms, connection);
      let rooms$1 = $1[0];
      let actions = $1[1];
      return [rooms$1, actions, new Ok(undefined)];
    }
  } else if (frame instanceof Join) {
    let room = frame.room;
    let peer = frame.peer;
    return join(rooms, connection, room, peer);
  } else if (frame instanceof Signal) {
    return refused(rooms, connection, Refusal$NotJoined$const);
  } else {
    return [rooms, $List$Empty$const, new Ok(undefined)];
  }
}

/**
 * Apply one raw frame from one connection.
 *
 * Every refusal has the same shape: tell the peer the reason, then close the
 * connection. No refusal changes the registry, so a hostile connection cannot
 * change the room that refused it.
 */
export function handle_frame(rooms, connection, raw) {
  let $ = decode_client(raw);
  if ($ instanceof Ok) {
    let frame = $[0];
    let $1 = apply_frame(rooms, connection, frame);
    let rooms$1 = $1[0];
    let actions = $1[1];
    return [rooms$1, actions];
  } else {
    let refusal = $[0];
    return [rooms, refuse(connection, refusal)];
  }
}

/**
 * The actions as `#(connection, payload, close_reason)` triples. A `Send`
 * action carries its encoded frame and an empty close reason. A `Close`
 * action carries an empty payload and its reason. The function keeps the
 * order, so the `Rejected` frame of a refusal always goes out before its
 * `Close` action.
 */
export function render_actions(actions) {
  return $list.map(
    actions,
    (action) => {
      if (action instanceof Send) {
        let connection = action.connection;
        let frame = action.frame;
        return [connection, server_to_string(frame), ""];
      } else {
        let connection = action.connection;
        let reason = action.reason;
        return [connection, "", reason];
      }
    },
  );
}

function refusal_tag(refusal) {
  let _block;
  let $ = is_terminal(refusal);
  if ($) {
    _block = "rejected:";
  } else {
    _block = "dropped:";
  }
  let prefix = _block;
  return prefix + refusal_parts(refusal)[0];
}

function frame_tag(frame) {
  if (frame instanceof Join) {
    return "join";
  } else if (frame instanceof Signal) {
    return "signal";
  } else {
    return "leave";
  }
}

/**
 * `handle_frame` in the shape that a JavaScript service can read without any
 * Gleam value: the new registry, the actions that `render_actions` produced,
 * and the tag of the frame.
 *
 * The tag is the whole instrumentation of a service. It is `join`, `signal`,
 * `leave`, `rejected:<reason>`, or `dropped:<reason>`. It comes from the type
 * of the frame and from whether the protocol refused that frame. It never
 * comes from the contents, so a service can count the frames and read none of
 * them. Every refusal has a tag, from the decoder and from the registry
 * alike. A room that refuses peers thus cannot look like correct traffic. The
 * `dropped:` prefix is separate from `rejected:`, because the one refusal
 * that does not close a connection is also the one that no peer caused: a
 * signal to a peer that left. A document envelope gets `rejected:malformed`,
 * and a test uses that tag to prove that no envelope arrived.
 */
export function serve(rooms, connection, raw) {
  let $ = decode_client(raw);
  if ($ instanceof Ok) {
    let frame = $[0];
    let $1 = apply_frame(rooms, connection, frame);
    let rooms$1 = $1[0];
    let actions = $1[1];
    let outcome = $1[2];
    let _block;
    if (outcome instanceof Ok) {
      _block = frame_tag(frame);
    } else {
      let refusal = outcome[0];
      _block = refusal_tag(refusal);
    }
    let tag = _block;
    return [rooms$1, render_actions(actions), tag];
  } else {
    let refusal = $[0];
    return [
      rooms,
      render_actions(refuse(connection, refusal)),
      refusal_tag(refusal),
    ];
  }
}

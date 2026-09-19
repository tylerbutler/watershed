/// <reference types="./crdt_relay.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
  toBitArray,
  stringBits,
} from "../gleam.mjs";
import * as $crdt_wire from "../watershed/crdt_wire.mjs";

/**
 * The greeting, which the relay writes at the moment that a socket opens.
 * `supports` reports whether that greeting announced the capability of this
 * lane. The wire carries an object of capabilities, and this client reads
 * exactly one entry from that object. One `Bool` value thus survives the
 * decode.
 */
export class Connected extends $CustomType {
  constructor(supports, envelope_bytes) {
    super();
    this.supports = supports;
    this.envelope_bytes = envelope_bytes;
  }
}
export const ServerFrame$Connected = (supports, envelope_bytes) =>
  new Connected(supports, envelope_bytes);
export const ServerFrame$isConnected = (value) => value instanceof Connected;
export const ServerFrame$Connected$supports = (value) => value.supports;
export const ServerFrame$Connected$0 = (value) => value.supports;
export const ServerFrame$Connected$envelope_bytes = (value) =>
  value.envelope_bytes;
export const ServerFrame$Connected$1 = (value) => value.envelope_bytes;

/**
 * One relayed envelope, with the diagnostic order outside it.
 */
export class Frame extends $CustomType {
  constructor(order, envelope) {
    super();
    this.order = order;
    this.envelope = envelope;
  }
}
export const ServerFrame$Frame = (order, envelope) =>
  new Frame(order, envelope);
export const ServerFrame$isFrame = (value) => value instanceof Frame;
export const ServerFrame$Frame$order = (value) => value.order;
export const ServerFrame$Frame$0 = (value) => value.order;
export const ServerFrame$Frame$envelope = (value) => value.envelope;
export const ServerFrame$Frame$1 = (value) => value.envelope;

/**
 * The end of the group of frames that a `stateRequest` produced. Without
 * this frame, a client cannot separate "the relay replayed everything that
 * it holds" from "the next entry has not arrived yet", and it would have to
 * guess the moment at which to publish its merged state.
 */
export class Synced extends $CustomType {
  constructor(order) {
    super();
    this.order = order;
  }
}
export const ServerFrame$Synced = (order) => new Synced(order);
export const ServerFrame$isSynced = (value) => value instanceof Synced;
export const ServerFrame$Synced$order = (value) => value.order;
export const ServerFrame$Synced$0 = (value) => value.order;

/**
 * The answer to an `attest` frame. The value is the digest of the client,
 * echoed back, when the content of the relay is exactly the state that the
 * client published. It is the empty string in every other condition.
 */
export class Attested extends $CustomType {
  constructor(order, digest) {
    super();
    this.order = order;
    this.digest = digest;
  }
}
export const ServerFrame$Attested = (order, digest) =>
  new Attested(order, digest);
export const ServerFrame$isAttested = (value) => value instanceof Attested;
export const ServerFrame$Attested$order = (value) => value.order;
export const ServerFrame$Attested$0 = (value) => value.order;
export const ServerFrame$Attested$digest = (value) => value.digest;
export const ServerFrame$Attested$1 = (value) => value.digest;

/**
 * A request to publish the merged state of the client and to attest it.
 *
 * The relay sends this frame to a connection that declared that it
 * understands one. See `Supports`. It sends the frame only after the live
 * log of a room passes `checkpoint_pressure_records`, and one time for each
 * connection, until that connection publishes a `state` frame or the log
 * grows by another `checkpoint_request_interval`.
 *
 * The frame carries nothing at all: no order, no digest, and no envelope. A
 * client answers it from its *own* state, so nothing that a relay stamped
 * can enter a document through this frame.
 */
export class CheckpointRequest extends $CustomType {}
export const ServerFrame$CheckpointRequest$const = new CheckpointRequest();
export const ServerFrame$CheckpointRequest = () =>
  ServerFrame$CheckpointRequest$const;
export const ServerFrame$isCheckpointRequest = (value) =>
  value instanceof CheckpointRequest;

/**
 * A refusal. This frame is terminal, and the relay closes the connection
 * after it.
 */
export class Refused extends $CustomType {
  constructor(reason, detail) {
    super();
    this.reason = reason;
    this.detail = detail;
  }
}
export const ServerFrame$Refused = (reason, detail) =>
  new Refused(reason, detail);
export const ServerFrame$isRefused = (value) => value instanceof Refused;
export const ServerFrame$Refused$reason = (value) => value.reason;
export const ServerFrame$Refused$0 = (value) => value.reason;
export const ServerFrame$Refused$detail = (value) => value.detail;
export const ServerFrame$Refused$1 = (value) => value.detail;

export class Attest extends $CustomType {
  constructor(digest, up_to) {
    super();
    this.digest = digest;
    this.up_to = up_to;
  }
}
export const ControlFrame$Attest = (digest, up_to) => new Attest(digest, up_to);
export const ControlFrame$isAttest = (value) => value instanceof Attest;
export const ControlFrame$Attest$digest = (value) => value.digest;
export const ControlFrame$Attest$0 = (value) => value.digest;
export const ControlFrame$Attest$up_to = (value) => value.up_to;
export const ControlFrame$Attest$1 = (value) => value.up_to;

/**
 * One delivered order that this client could not process. This frame is
 * never a decision about a document. The relay learns *that* the client
 * refused an entry, and it learns nothing about the reason.
 */
export class Skip extends $CustomType {
  constructor(order) {
    super();
    this.order = order;
  }
}
export const ControlFrame$Skip = (order) => new Skip(order);
export const ControlFrame$isSkip = (value) => value instanceof Skip;
export const ControlFrame$Skip$order = (value) => value.order;
export const ControlFrame$Skip$0 = (value) => value.order;

/**
 * The optional relay control features that this connection understands. The
 * client sends this frame one time, after the `hello` frame that admits the
 * connection.
 *
 * The relay never sends a `CheckpointRequest` frame to a client that does
 * not send this frame. That rule makes the request safe to add to a lane
 * that is already in use. An older client would treat an unknown server
 * frame as a handshake violation, and that client never receives one.
 */
export class Supports extends $CustomType {
  constructor(checkpoint_requests) {
    super();
    this.checkpoint_requests = checkpoint_requests;
  }
}
export const ControlFrame$Supports = (checkpoint_requests) =>
  new Supports(checkpoint_requests);
export const ControlFrame$isSupports = (value) => value instanceof Supports;
export const ControlFrame$Supports$checkpoint_requests = (value) =>
  value.checkpoint_requests;
export const ControlFrame$Supports$0 = (value) => value.checkpoint_requests;

export class Document extends $CustomType {
  constructor(raw, room, from, session, message) {
    super();
    this.raw = raw;
    this.room = room;
    this.from = from;
    this.session = session;
    this.message = message;
  }
}
export const ClientFrame$Document = (raw, room, from, session, message) =>
  new Document(raw, room, from, session, message);
export const ClientFrame$isDocument = (value) => value instanceof Document;
export const ClientFrame$Document$raw = (value) => value.raw;
export const ClientFrame$Document$0 = (value) => value.raw;
export const ClientFrame$Document$room = (value) => value.room;
export const ClientFrame$Document$1 = (value) => value.room;
export const ClientFrame$Document$from = (value) => value.from;
export const ClientFrame$Document$2 = (value) => value.from;
export const ClientFrame$Document$session = (value) => value.session;
export const ClientFrame$Document$3 = (value) => value.session;
export const ClientFrame$Document$message = (value) => value.message;
export const ClientFrame$Document$4 = (value) => value.message;

export class Control extends $CustomType {
  constructor(frame) {
    super();
    this.frame = frame;
  }
}
export const ClientFrame$Control = (frame) => new Control(frame);
export const ClientFrame$isControl = (value) => value instanceof Control;
export const ClientFrame$Control$frame = (value) => value.frame;
export const ClientFrame$Control$0 = (value) => value.frame;

export class HelloMessage extends $CustomType {}
export const MessageKind$HelloMessage$const = new HelloMessage();
export const MessageKind$HelloMessage = () => MessageKind$HelloMessage$const;
export const MessageKind$isHelloMessage = (value) =>
  value instanceof HelloMessage;

export class ChannelMessage extends $CustomType {}
export const MessageKind$ChannelMessage$const = new ChannelMessage();
export const MessageKind$ChannelMessage = () =>
  MessageKind$ChannelMessage$const;
export const MessageKind$isChannelMessage = (value) =>
  value instanceof ChannelMessage;

export class DeltaMessage extends $CustomType {}
export const MessageKind$DeltaMessage$const = new DeltaMessage();
export const MessageKind$DeltaMessage = () => MessageKind$DeltaMessage$const;
export const MessageKind$isDeltaMessage = (value) =>
  value instanceof DeltaMessage;

export class StateRequestMessage extends $CustomType {}
export const MessageKind$StateRequestMessage$const = new StateRequestMessage();
export const MessageKind$StateRequestMessage = () =>
  MessageKind$StateRequestMessage$const;
export const MessageKind$isStateRequestMessage = (value) =>
  value instanceof StateRequestMessage;

export class StateMessage extends $CustomType {}
export const MessageKind$StateMessage$const = new StateMessage();
export const MessageKind$StateMessage = () => MessageKind$StateMessage$const;
export const MessageKind$isStateMessage = (value) =>
  value instanceof StateMessage;

export class DigestMessage extends $CustomType {}
export const MessageKind$DigestMessage$const = new DigestMessage();
export const MessageKind$DigestMessage = () => MessageKind$DigestMessage$const;
export const MessageKind$isDigestMessage = (value) =>
  value instanceof DigestMessage;

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

export class UnsupportedMessage extends $CustomType {
  constructor(tag) {
    super();
    this.tag = tag;
  }
}
export const Refusal$UnsupportedMessage = (tag) => new UnsupportedMessage(tag);
export const Refusal$isUnsupportedMessage = (value) =>
  value instanceof UnsupportedMessage;
export const Refusal$UnsupportedMessage$tag = (value) => value.tag;
export const Refusal$UnsupportedMessage$0 = (value) => value.tag;

/**
 * A document frame that arrived before the `hello` frame that admits the
 * connection.
 */
export class NotAdmitted extends $CustomType {}
export const Refusal$NotAdmitted$const = new NotAdmitted();
export const Refusal$NotAdmitted = () => Refusal$NotAdmitted$const;
export const Refusal$isNotAdmitted = (value) => value instanceof NotAdmitted;

export class InvalidRoom extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const Refusal$InvalidRoom = (detail) => new InvalidRoom(detail);
export const Refusal$isInvalidRoom = (value) => value instanceof InvalidRoom;
export const Refusal$InvalidRoom$detail = (value) => value.detail;
export const Refusal$InvalidRoom$0 = (value) => value.detail;

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
 * A frame whose room, sender, or session is not the one that this
 * connection was admitted with. This refusal isolates a client that speaks
 * to the wrong room.
 */
export class IdentityChanged extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const Refusal$IdentityChanged = (detail) => new IdentityChanged(detail);
export const Refusal$isIdentityChanged = (value) =>
  value instanceof IdentityChanged;
export const Refusal$IdentityChanged$detail = (value) => value.detail;
export const Refusal$IdentityChanged$0 = (value) => value.detail;

export class DuplicateSession extends $CustomType {
  constructor(session) {
    super();
    this.session = session;
  }
}
export const Refusal$DuplicateSession = (session) =>
  new DuplicateSession(session);
export const Refusal$isDuplicateSession = (value) =>
  value instanceof DuplicateSession;
export const Refusal$DuplicateSession$session = (value) => value.session;
export const Refusal$DuplicateSession$0 = (value) => value.session;

/**
 * A connection reported more outstanding skips than the module permits.
 * This limit bounds the memory, and the refusal is terminal for that
 * connection only.
 */
export class TooManySkips extends $CustomType {
  constructor(limit) {
    super();
    this.limit = limit;
  }
}
export const Refusal$TooManySkips = (limit) => new TooManySkips(limit);
export const Refusal$isTooManySkips = (value) => value instanceof TooManySkips;
export const Refusal$TooManySkips$limit = (value) => value.limit;
export const Refusal$TooManySkips$0 = (value) => value.limit;

/**
 * The live log of the room is at `max_room_records`, and this frame would
 * have taken it past that bound. The refusal is terminal for the sender
 * only. The durable records of the room do not change, and every other
 * connection keeps its lane.
 */
export class RoomAtCapacity extends $CustomType {
  constructor(limit) {
    super();
    this.limit = limit;
  }
}
export const Refusal$RoomAtCapacity = (limit) => new RoomAtCapacity(limit);
export const Refusal$isRoomAtCapacity = (value) =>
  value instanceof RoomAtCapacity;
export const Refusal$RoomAtCapacity$limit = (value) => value.limit;
export const Refusal$RoomAtCapacity$0 = (value) => value.limit;

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

/**
 * Append one JSONL line to the log of the room.
 */
export class Append extends $CustomType {
  constructor(room, line) {
    super();
    this.room = room;
    this.line = line;
  }
}
export const Action$Append = (room, line) => new Append(room, line);
export const Action$isAppend = (value) => value instanceof Append;
export const Action$Append$room = (value) => value.room;
export const Action$Append$0 = (value) => value.room;
export const Action$Append$line = (value) => value.line;
export const Action$Append$1 = (value) => value.line;

/**
 * Replace the log of the room with exactly these lines. The module emits
 * this action only after the `Append` action that carries the checkpoint
 * that it keeps.
 */
export class Compact extends $CustomType {
  constructor(room, lines) {
    super();
    this.room = room;
    this.lines = lines;
  }
}
export const Action$Compact = (room, lines) => new Compact(room, lines);
export const Action$isCompact = (value) => value instanceof Compact;
export const Action$Compact$room = (value) => value.room;
export const Action$Compact$0 = (value) => value.room;
export const Action$Compact$lines = (value) => value.lines;
export const Action$Compact$1 = (value) => value.lines;

class Preamble extends $CustomType {
  constructor(version, room, from, session, message_type) {
    super();
    this.version = version;
    this.room = room;
    this.from = from;
    this.session = session;
    this.message_type = message_type;
  }
}

class ServerShape extends $CustomType {
  constructor(kind, order, envelope, digest, reason, detail, capabilities, envelope_bytes) {
    super();
    this.kind = kind;
    this.order = order;
    this.envelope = envelope;
    this.digest = digest;
    this.reason = reason;
    this.detail = detail;
    this.capabilities = capabilities;
    this.envelope_bytes = envelope_bytes;
  }
}

class ControlShape extends $CustomType {
  constructor(kind, digest, up_to, order, checkpoint_requests) {
    super();
    this.kind = kind;
    this.digest = digest;
    this.up_to = up_to;
    this.order = order;
    this.checkpoint_requests = checkpoint_requests;
  }
}

/**
 * A publication of a full state. It becomes a checkpoint after a client
 * attests it.
 */
export class StateRecord extends $CustomType {
  constructor(order, session, envelope) {
    super();
    this.order = order;
    this.session = session;
    this.envelope = envelope;
  }
}
export const LogRecord$StateRecord = (order, session, envelope) =>
  new StateRecord(order, session, envelope);
export const LogRecord$isStateRecord = (value) => value instanceof StateRecord;
export const LogRecord$StateRecord$order = (value) => value.order;
export const LogRecord$StateRecord$0 = (value) => value.order;
export const LogRecord$StateRecord$session = (value) => value.session;
export const LogRecord$StateRecord$1 = (value) => value.session;
export const LogRecord$StateRecord$envelope = (value) => value.envelope;
export const LogRecord$StateRecord$2 = (value) => value.envelope;

/**
 * A channel announcement or a delta.
 */
export class TrafficRecord extends $CustomType {
  constructor(order, session, envelope) {
    super();
    this.order = order;
    this.session = session;
    this.envelope = envelope;
  }
}
export const LogRecord$TrafficRecord = (order, session, envelope) =>
  new TrafficRecord(order, session, envelope);
export const LogRecord$isTrafficRecord = (value) =>
  value instanceof TrafficRecord;
export const LogRecord$TrafficRecord$order = (value) => value.order;
export const LogRecord$TrafficRecord$0 = (value) => value.order;
export const LogRecord$TrafficRecord$session = (value) => value.session;
export const LogRecord$TrafficRecord$1 = (value) => value.session;
export const LogRecord$TrafficRecord$envelope = (value) => value.envelope;
export const LogRecord$TrafficRecord$2 = (value) => value.envelope;

/**
 * The checkpoint marker of the room: the digest that a client attested,
 * with the order of the `state` record that the attestation described.
 *
 * `checkpoint` survives a restart, and it says *which* `state` record of a
 * log is the canonical record of the room. That record is the entry that a
 * `stateRequest` rebuilds from. `digest` is current only while this marker
 * is the newest record in the file. Anything that the relay logs after a
 * checkpoint means that the checkpoint no longer describes the room. A
 * marker that a later compaction rewrites carries `""` to report that, and
 * it still names the canonical entry.
 */
export class DigestRecord extends $CustomType {
  constructor(order, digest, checkpoint) {
    super();
    this.order = order;
    this.digest = digest;
    this.checkpoint = checkpoint;
  }
}
export const LogRecord$DigestRecord = (order, digest, checkpoint) =>
  new DigestRecord(order, digest, checkpoint);
export const LogRecord$isDigestRecord = (value) =>
  value instanceof DigestRecord;
export const LogRecord$DigestRecord$order = (value) => value.order;
export const LogRecord$DigestRecord$0 = (value) => value.order;
export const LogRecord$DigestRecord$digest = (value) => value.digest;
export const LogRecord$DigestRecord$1 = (value) => value.digest;
export const LogRecord$DigestRecord$checkpoint = (value) => value.checkpoint;
export const LogRecord$DigestRecord$2 = (value) => value.checkpoint;

export const LogRecord$order = (value) => value.order;

class RawRecord extends $CustomType {
  constructor(order, kind, session, envelope, digest, checkpoint) {
    super();
    this.order = order;
    this.kind = kind;
    this.session = session;
    this.envelope = envelope;
    this.digest = digest;
    this.checkpoint = checkpoint;
  }
}

class Entry extends $CustomType {
  constructor(order, session, envelope, state, line) {
    super();
    this.order = order;
    this.session = session;
    this.envelope = envelope;
    this.state = state;
    this.line = line;
  }
}

class Client extends $CustomType {
  constructor(from, session, delivered, skipped, supports_checkpoints, checkpoint_requested) {
    super();
    this.from = from;
    this.session = session;
    this.delivered = delivered;
    this.skipped = skipped;
    this.supports_checkpoints = supports_checkpoints;
    this.checkpoint_requested = checkpoint_requested;
  }
}

class Room extends $CustomType {
  constructor(clients, next_order, log, pending, attested, attested_order, checkpoint_order, pressure_at, requests) {
    super();
    this.clients = clients;
    this.next_order = next_order;
    this.log = log;
    this.pending = pending;
    this.attested = attested;
    this.attested_order = attested_order;
    this.checkpoint_order = checkpoint_order;
    this.pressure_at = pressure_at;
    this.requests = requests;
  }
}

/**
 * `connections` maps the id of a socket to the room that the relay admitted
 * it to. Every other fact about that connection is in the `clients` field of
 * that room.
 * 
 * @ignore
 */
class Relay extends $CustomType {
  constructor(rooms, connections) {
    super();
    this.rooms = rooms;
    this.connections = connections;
  }
}

/**
 * The capability that a relay must announce before a client can use it. An
 * endpoint that omits it is a sequencer without this lane. In `Auto` mode that
 * condition is a status, and it is not a failure.
 */
export const capability = "crdt_relay_v1";

/**
 * The longest accepted room name, in UTF-8 bytes.
 */
export const max_room_bytes = 128;

/**
 * The longest session identifier that the module accepts, in UTF-8 bytes. A
 * client supplies the session, the relay holds it for the life of a
 * connection, and the relay writes it into every durable record. It thus has a
 * limit, for the same reason as a room name.
 */
export const max_session_bytes = 128;

/**
 * The growth in the log of a room before that room asks again.
 *
 * A request is idempotent for each connection: a client with one outstanding
 * request does not get a second one. The relay arms the request again only
 * after the log grows by this amount. A room under pressure thus sends
 * `(max_room_records - checkpoint_pressure_records) /
 * checkpoint_request_interval` rounds at most, before it starts to refuse. An
 * attacker thus cannot use a client that ignores those requests to generate
 * traffic.
 */
export const checkpoint_request_interval = 64;

/**
 * The log size at which a room starts to ask for a checkpoint, instead of a
 * wait until it must refuse one. The value is three quarters of
 * `max_room_records`.
 *
 * A room that reaches its hard bound with a correct client attached is a fault
 * of this repository, and not of that client. An ordinary editing session that
 * passes the bound must not stop in the middle of the work. At this mark the
 * relay thus sends a `CheckpointRequest` frame to every attached client that
 * declared that it understands one. A correct client answers with a
 * publication of its merged state and an attestation of that state, and the
 * relay then compacts the ordinary valid history of the room down to that one
 * record. The last quarter is the space in which the client can answer that
 * request.
 */
export const checkpoint_pressure_records = 768;

/**
 * The hard bound on the *active log* of a room. The relay applies it **before**
 * an append, and not after one.
 *
 * An admitted client that is alone in a room can write correct records, and no
 * other client is there to refuse them. 100 000 such records are 100 000 lines
 * on disk and 100 000 entries in the heap of this process, and the relay
 * replays all of them to the next client that attaches. The live log of a room
 * thus stops growing at this bound.
 *
 * Before the log reaches the bound, the relay asks the compatible clients to
 * checkpoint. See `checkpoint_pressure_records`. If the log still reaches the
 * bound, the relay refuses the *sender* of the frame that would cross it, with
 * the reason `roomAtCapacity`, and it closes that connection. The relay
 * changes nothing that is already durable. A refusal at the bound writes
 * nothing and deletes nothing.
 */
export const max_room_records = 1024;

/**
 * The number of clients that one room admits. A relay is not a mesh. It fans
 * out, and it does not connect every client to every other client. This limit
 * is thus much higher than the room limit of WebRTC. It exists to bound the
 * memory, and not to control a topology.
 */
export const max_room_clients = 32;

/**
 * The largest number of skipped orders that one connection can hold at one
 * time. The relay removes from that list every order that the log of the room
 * no longer holds, and it does that every time a skip arrives and every time a
 * checkpoint lands. `max_room_records` also bounds the log itself. This value
 * is thus a backstop, and it is not a rule that a connection must meet. It is
 * `max_room_records` or more, so a client that refuses *every* entry in a
 * completely full room still does not get a closed connection for the number
 * of its claims.
 *
 * It is still a real operational limit. The relay closes a connection that
 * reports more live skips than this number, with the reason `tooManySkips`,
 * and that client must connect again.
 */
export const max_client_skips = 1024;

/**
 * The largest frame that the module accepts, in bytes, in both directions of
 * the lane. This is the same limit as the CRDT envelope itself. A frame that
 * could never hold a valid envelope is thus refused before the module parses
 * it.
 */
export function max_frame_bytes() {
  return $crdt_wire.default_limits().envelope_bytes;
}

export function message_kind_to_string(kind) {
  if (kind instanceof HelloMessage) {
    return "hello";
  } else if (kind instanceof ChannelMessage) {
    return "channel";
  } else if (kind instanceof DeltaMessage) {
    return "delta";
  } else if (kind instanceof StateRequestMessage) {
    return "stateRequest";
  } else if (kind instanceof StateMessage) {
    return "state";
  } else {
    return "digest";
  }
}

function string_to_message_kind(raw) {
  if (raw === "hello") {
    return new Ok(MessageKind$HelloMessage$const);
  } else if (raw === "channel") {
    return new Ok(MessageKind$ChannelMessage$const);
  } else if (raw === "delta") {
    return new Ok(MessageKind$DeltaMessage$const);
  } else if (raw === "stateRequest") {
    return new Ok(MessageKind$StateRequestMessage$const);
  } else if (raw === "state") {
    return new Ok(MessageKind$StateMessage$const);
  } else if (raw === "digest") {
    return new Ok(MessageKind$DigestMessage$const);
  } else {
    return new Error(undefined);
  }
}

export function refusal_parts(refusal) {
  if (refusal instanceof FrameTooLarge) {
    let bytes = refusal.bytes;
    return [
      "frameTooLarge",
      (($int.to_string(bytes) + " bytes exceeds the ") + $int.to_string(
        max_frame_bytes(),
      )) + " byte limit",
    ];
  } else if (refusal instanceof Malformed) {
    let detail = refusal.detail;
    return ["malformed", detail];
  } else if (refusal instanceof UnsupportedMessage) {
    let tag = refusal.tag;
    return ["unsupportedMessage", (tag + " is not carried by ") + capability];
  } else if (refusal instanceof NotAdmitted) {
    return [
      "notAdmitted",
      "the first frame on a relay lane must be a hello envelope",
    ];
  } else if (refusal instanceof InvalidRoom) {
    let detail = refusal.detail;
    return ["invalidRoom", detail];
  } else if (refusal instanceof RoomFull) {
    let limit = refusal.limit;
    return [
      "roomFull",
      ("the room already holds " + $int.to_string(limit)) + " clients",
    ];
  } else if (refusal instanceof IdentityChanged) {
    let detail = refusal.detail;
    return ["identityChanged", detail];
  } else if (refusal instanceof DuplicateSession) {
    let session = refusal.session;
    return ["duplicateSession", session + " is already attached to this room"];
  } else if (refusal instanceof TooManySkips) {
    let limit = refusal.limit;
    return [
      "tooManySkips",
      ("a connection may hold at most " + $int.to_string(limit)) + " skips",
    ];
  } else {
    let limit = refusal.limit;
    return [
      "roomAtCapacity",
      ("the room's live log already holds " + $int.to_string(limit)) + " records",
    ];
  }
}

export function server_to_json(frame) {
  if (frame instanceof Connected) {
    let supports = frame.supports;
    let envelope_bytes = frame.envelope_bytes;
    return $json.object(
      toList([
        ["type", $json.string("connected")],
        [
          "capabilities",
          $json.object(
            (() => {
              if (supports) {
                return toList([[capability, $json.bool(true)]]);
              } else {
                return $List$Empty$const;
              }
            })(),
          ),
        ],
        [
          "limits",
          $json.object(toList([["envelopeBytes", $json.int(envelope_bytes)]])),
        ],
      ]),
    );
  } else if (frame instanceof Frame) {
    let order = frame.order;
    let envelope = frame.envelope;
    return $json.object(
      toList([
        ["type", $json.string("frame")],
        ["order", $json.int(order)],
        ["envelope", $json.string(envelope)],
      ]),
    );
  } else if (frame instanceof Synced) {
    let order = frame.order;
    return $json.object(
      toList([["type", $json.string("synced")], ["order", $json.int(order)]]),
    );
  } else if (frame instanceof Attested) {
    let order = frame.order;
    let digest = frame.digest;
    return $json.object(
      toList([
        ["type", $json.string("attested")],
        ["order", $json.int(order)],
        ["digest", $json.string(digest)],
      ]),
    );
  } else if (frame instanceof CheckpointRequest) {
    return $json.object(toList([["type", $json.string("checkpointRequest")]]));
  } else {
    let reason = frame.reason;
    let detail = frame.detail;
    return $json.object(
      toList([
        ["type", $json.string("error")],
        ["reason", $json.string(reason)],
        ["detail", $json.string(detail)],
      ]),
    );
  }
}

export function server_to_string(frame) {
  return $json.to_string(server_to_json(frame));
}

export function control_to_string(frame) {
  if (frame instanceof Attest) {
    let digest = frame.digest;
    let up_to = frame.up_to;
    return $json.to_string(
      $json.object(
        toList([
          ["type", $json.string("attest")],
          ["digest", $json.string(digest)],
          ["upTo", $json.int(up_to)],
        ]),
      ),
    );
  } else if (frame instanceof Skip) {
    let order = frame.order;
    return $json.to_string(
      $json.object(
        toList([["type", $json.string("skip")], ["order", $json.int(order)]]),
      ),
    );
  } else {
    let checkpoint_requests$1 = frame.checkpoint_requests;
    return $json.to_string(
      $json.object(
        toList([
          ["type", $json.string("supports")],
          ["checkpointRequests", $json.bool(checkpoint_requests$1)],
        ]),
      ),
    );
  }
}

/**
 * The greeting that a compatible relay opens with.
 */
export function connected_frame() {
  return new Connected(true, max_frame_bytes());
}

/**
 * Read the preamble of the envelope only. The decoder reads exactly one field
 * inside `message`, which is its `type` tag, and it never reads the payload of
 * that message. That rule keeps a relay outside the kernels.
 * 
 * @ignore
 */
function preamble_decoder() {
  return $decode.field(
    "v",
    $decode.int,
    (version) => {
      return $decode.field(
        "room",
        $decode.string,
        (room) => {
          return $decode.field(
            "from",
            $decode.string,
            (from) => {
              return $decode.field(
                "session",
                $decode.string,
                (session) => {
                  return $decode.subfield(
                    toList(["message", "type"]),
                    $decode.string,
                    (message_type) => {
                      return $decode.success(
                        new Preamble(version, room, from, session, message_type),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function server_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (kind) => {
      return $decode.optional_field(
        "order",
        0,
        $decode.int,
        (order) => {
          return $decode.optional_field(
            "envelope",
            "",
            $decode.string,
            (envelope) => {
              return $decode.optional_field(
                "digest",
                "",
                $decode.string,
                (digest) => {
                  return $decode.optional_field(
                    "reason",
                    "",
                    $decode.string,
                    (reason) => {
                      return $decode.optional_field(
                        "detail",
                        "",
                        $decode.string,
                        (detail) => {
                          return $decode.optional_field(
                            "capabilities",
                            $dict.new$(),
                            $decode.dict($decode.string, $decode.bool),
                            (capabilities) => {
                              return $decode.optional_field(
                                "limits",
                                0,
                                $decode.optionally_at(
                                  toList(["envelopeBytes"]),
                                  0,
                                  $decode.int,
                                ),
                                (envelope_bytes) => {
                                  return $decode.success(
                                    new ServerShape(
                                      kind,
                                      order,
                                      envelope,
                                      digest,
                                      reason,
                                      detail,
                                      capabilities,
                                      envelope_bytes,
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Read one frame that a relay sent. This is the client half of the codec that
 * the relay encodes with, so the two cannot drift apart.
 *
 * A relay that stamps nothing is valid. The function accepts a frame with no
 * top-level `type` field as a bare envelope, and it reports that frame with the
 * order `0`.
 */
export function decode_server(raw) {
  let $ = $json.parse(raw, server_decoder());
  if ($ instanceof Ok) {
    let shape$1 = $[0];
    let $1 = shape$1.kind;
    if ($1 === "connected") {
      return new Ok(
        new Connected(
          isEqual($dict.get(shape$1.capabilities, capability), new Ok(true)),
          shape$1.envelope_bytes,
        ),
      );
    } else if ($1 === "frame") {
      let $2 = shape$1.envelope;
      if ($2 === "") {
        return new Error("a relay frame carried no envelope");
      } else {
        let envelope = $2;
        return new Ok(new Frame(shape$1.order, envelope));
      }
    } else if ($1 === "synced") {
      return new Ok(new Synced(shape$1.order));
    } else if ($1 === "attested") {
      return new Ok(new Attested(shape$1.order, shape$1.digest));
    } else if ($1 === "checkpointRequest") {
      return new Ok(ServerFrame$CheckpointRequest$const);
    } else if ($1 === "error") {
      return new Ok(new Refused(shape$1.reason, shape$1.detail));
    } else {
      let other = $1;
      return new Error("unknown relay frame " + other);
    }
  } else {
    let $1 = $json.parse(raw, preamble_decoder());
    if ($1 instanceof Ok) {
      return new Ok(new Frame(0, raw));
    } else {
      return new Error("not a relay frame or a CRDT envelope");
    }
  }
}

/**
 * Whether a `connected` frame announces the lane that this client uses.
 */
export function supports_relay(frame) {
  if (frame instanceof Connected) {
    let supports = frame.supports;
    return supports;
  } else if (frame instanceof Frame) {
    return false;
  } else if (frame instanceof Synced) {
    return false;
  } else if (frame instanceof Attested) {
    return false;
  } else if (frame instanceof CheckpointRequest) {
    return false;
  } else {
    return false;
  }
}

function control_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (kind) => {
      return $decode.optional_field(
        "digest",
        "",
        $decode.string,
        (digest) => {
          return $decode.optional_field(
            "upTo",
            0,
            $decode.int,
            (up_to) => {
              return $decode.optional_field(
                "order",
                0,
                $decode.int,
                (order) => {
                  return $decode.optional_field(
                    "checkpointRequests",
                    false,
                    $decode.bool,
                    (checkpoint_requests) => {
                      return $decode.success(
                        new ControlShape(
                          kind,
                          digest,
                          up_to,
                          order,
                          checkpoint_requests,
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function message_id_shape() {
  return $decode.field(
    0,
    $decode.string,
    (replica) => {
      return $decode.field(
        1,
        $decode.int,
        (counter) => { return $decode.success([replica, counter]); },
      );
    },
  );
}

function delta_shape() {
  return $decode.subfield(
    toList(["message", "id"]),
    message_id_shape(),
    (id) => {
      return $decode.subfield(
        toList(["message", "address"]),
        $decode.string,
        (address) => {
          return $decode.subfield(
            toList(["message", "channelType"]),
            $decode.string,
            (channel_type) => {
              return $decode.success([id, address, channel_type]);
            },
          );
        },
      );
    },
  );
}

function shape(raw, decoder, what) {
  let _pipe = $json.parse(raw, decoder);
  return $result.replace_error(
    _pipe,
    new Malformed(("malformed " + what) + " message"),
  );
}

function channel_shape() {
  return $decode.subfield(
    toList(["message", "descriptor", "address"]),
    $decode.string,
    (address) => {
      return $decode.subfield(
        toList(["message", "descriptor", "channelType"]),
        $decode.string,
        (channel_type) => {
          return $decode.subfield(
            toList(["message", "descriptor", "createdBy"]),
            $decode.string,
            (created_by) => {
              return $decode.success([address, channel_type, created_by]);
            },
          );
        },
      );
    },
  );
}

/**
 * The channels of a `state` message must be a list. The content of that list
 * belongs to a kernel. The elements stay dynamic values here, and this module
 * never reads them.
 * 
 * @ignore
 */
function state_shape() {
  return $decode.at(
    toList(["message", "channels"]),
    $decode.list($decode.dynamic),
  );
}

function shaped(raw, decoder, what) {
  let _pipe = shape(raw, decoder, what);
  return $result.replace(_pipe, undefined);
}

function digest_shape() {
  return $decode.at(toList(["message", "digest"]), $decode.string);
}

function hello_shape() {
  return $decode.subfield(
    toList(["message", "compatibility"]),
    $decode.string,
    (compatibility) => {
      return $decode.subfield(
        toList(["message", "root"]),
        $decode.string,
        (root) => { return $decode.success([compatibility, root]); },
      );
    },
  );
}

/**
 * The inexpensive structural checks that a relay can make on a message
 * *without* a decode of a kernel payload.
 *
 * Every check here reads a field that names or addresses a message. Those
 * fields are the id, the address, and the declared channel type of a delta, the
 * descriptor of a channel announcement, and the shape of the channel list of a
 * `state` message. No check here reads a `contents` field or a `snapshot`
 * field. Those two belong to the kernel, and they stay an opaque string all the
 * way to the log.
 *
 * These checks are a *subset* of the checks that the decoder of `crdt_wire`
 * makes, and that is deliberate. A relay thus can never refuse an envelope that
 * a document would have accepted. The checks refuse the cheapest invalid input
 * at the socket, instead of a log, a replay, and a skip by every client
 * without an end. Four examples: a frame with a `delta` tag and no id, an
 * address that names no channel, a descriptor whose `createdBy` field
 * disagrees with its own address, and a `state` whose channels are not a list.
 *
 * These checks do not remove every bad record. A correct delta whose operation
 * has no meaning to any kernel still enters the log, and it always will,
 * because only a merge could detect it.
 * 
 * @ignore
 */
function check_shape(raw, kind) {
  if (kind instanceof HelloMessage) {
    return shaped(raw, hello_shape(), "hello");
  } else if (kind instanceof ChannelMessage) {
    return $result.try$(
      shape(raw, channel_shape(), "channel"),
      (_use0) => {
        let address = _use0[0];
        let channel_type = _use0[1];
        let created_by = _use0[2];
        return $result.try$(
          (() => {
            let _pipe = $crdt_wire.address_creator(address);
            return $result.replace_error(
              _pipe,
              new Malformed("channel names the invalid address " + address),
            );
          })(),
          (creator) => {
            let $ = creator === created_by;
            let $1 = channel_type !== "";
            if ($) {
              if ($1) {
                return new Ok(undefined);
              } else {
                return new Error(
                  new Malformed("channel declares an empty channel type"),
                );
              }
            } else {
              return new Error(
                new Malformed(
                  ("channel " + address) + " claims a creator its address denies",
                ),
              );
            }
          },
        );
      },
    );
  } else if (kind instanceof DeltaMessage) {
    return $result.try$(
      shape(raw, delta_shape(), "delta"),
      (_use0) => {
        let replica;
        let counter;
        let address;
        let channel_type;
        address = _use0[1];
        channel_type = _use0[2];
        replica = _use0[0][0];
        counter = _use0[0][1];
        return $result.try$(
          (() => {
            let _pipe = $crdt_wire.address_creator(address);
            return $result.replace_error(
              _pipe,
              new Malformed("delta names the invalid address " + address),
            );
          })(),
          (_) => {
            let $ = $crdt_wire.valid_replica_id(replica) && (counter >= 0);
            if (!$) {
              return new Error(new Malformed("delta has an invalid message id"));
            } else if (channel_type === "") {
              return new Error(
                new Malformed("delta declares an empty channel type"),
              );
            } else {
              return new Ok(undefined);
            }
          },
        );
      },
    );
  } else if (kind instanceof StateRequestMessage) {
    return new Ok(undefined);
  } else if (kind instanceof StateMessage) {
    return shaped(raw, state_shape(), "state");
  } else {
    return shaped(raw, digest_shape(), "digest");
  }
}

function byte_size(raw) {
  return $bit_array.byte_size(toBitArray([stringBits(raw)]));
}

function check_room(room) {
  let $ = room === "";
  let $1 = byte_size(room) > max_room_bytes;
  if ($) {
    return new Error(new InvalidRoom("room name is empty"));
  } else if ($1) {
    return new Error(
      new InvalidRoom(
        ("room name is longer than " + $int.to_string(max_room_bytes)) + " bytes",
      ),
    );
  } else {
    return new Ok(undefined);
  }
}

function decode_document(raw) {
  return $result.try$(
    (() => {
      let _pipe = $json.parse(raw, preamble_decoder());
      return $result.replace_error(
        _pipe,
        new Malformed("not a v1 CRDT envelope"),
      );
    })(),
    (preamble) => {
      let version = preamble.version;
      let room = preamble.room;
      let from = preamble.from;
      let session = preamble.session;
      let message_type = preamble.message_type;
      return $result.try$(
        (() => {
          let $ = version === $crdt_wire.protocol_version;
          if ($) {
            return new Ok(undefined);
          } else {
            return new Error(
              new Malformed(
                (("envelope is protocol v" + $int.to_string(version)) + ", not v") + $int.to_string(
                  $crdt_wire.protocol_version,
                ),
              ),
            );
          }
        })(),
        (_) => {
          return $result.try$(
            (() => {
              let $ = ($crdt_wire.valid_replica_id(from) && (session !== "")) && (byte_size(
                session,
              ) <= max_session_bytes);
              if ($) {
                return new Ok(undefined);
              } else {
                return new Error(
                  new Malformed("envelope has no usable sender identity"),
                );
              }
            })(),
            (_) => {
              return $result.try$(
                check_room(room),
                (_) => {
                  return $result.try$(
                    (() => {
                      let _pipe = string_to_message_kind(message_type);
                      return $result.replace_error(
                        _pipe,
                        new UnsupportedMessage(message_type),
                      );
                    })(),
                    (kind) => {
                      return $result.try$(
                        check_shape(raw, kind),
                        (_) => {
                          return new Ok(
                            new Document(raw, room, from, session, kind),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Classify one raw inbound frame.
 *
 * A control frame is a JSON object with a top-level `type` field. A document
 * frame is a version 1 CRDT envelope, and it has no such field. That
 * difference is the whole test, and it is the reason that a relay never has to
 * guess.
 */
export function decode_client(raw) {
  return $result.try$(
    (() => {
      let $ = $int.compare(byte_size(raw), max_frame_bytes());
      if ($ instanceof $order.Lt) {
        return new Ok(undefined);
      } else if ($ instanceof $order.Eq) {
        return new Ok(undefined);
      } else {
        return new Error(new FrameTooLarge(byte_size(raw)));
      }
    })(),
    (_) => {
      let $ = $json.parse(raw, control_decoder());
      if ($ instanceof Ok) {
        let $1 = $[0].kind;
        if ($1 === "attest") {
          let digest = $[0].digest;
          let up_to = $[0].up_to;
          return new Ok(new Control(new Attest(digest, up_to)));
        } else if ($1 === "skip") {
          let order = $[0].order;
          return new Ok(new Control(new Skip(order)));
        } else if ($1 === "supports") {
          let checkpoint_requests$1 = $[0].checkpoint_requests;
          return new Ok(new Control(new Supports(checkpoint_requests$1)));
        } else {
          let kind = $1;
          return new Error(new Malformed("unknown control frame " + kind));
        }
      } else {
        return decode_document(raw);
      }
    },
  );
}

export function record_to_string(record) {
  return $json.to_string(
    (() => {
      if (record instanceof StateRecord) {
        let order = record.order;
        let session = record.session;
        let envelope = record.envelope;
        return $json.object(
          toList([
            ["o", $json.int(order)],
            ["k", $json.string("state")],
            ["s", $json.string(session)],
            ["e", $json.string(envelope)],
          ]),
        );
      } else if (record instanceof TrafficRecord) {
        let order = record.order;
        let session = record.session;
        let envelope = record.envelope;
        return $json.object(
          toList([
            ["o", $json.int(order)],
            ["k", $json.string("traffic")],
            ["s", $json.string(session)],
            ["e", $json.string(envelope)],
          ]),
        );
      } else {
        let order = record.order;
        let digest = record.digest;
        let checkpoint = record.checkpoint;
        return $json.object(
          toList([
            ["o", $json.int(order)],
            ["k", $json.string("digest")],
            ["d", $json.string(digest)],
            ["c", $json.int(checkpoint)],
          ]),
        );
      }
    })(),
  );
}

function record_decoder() {
  return $decode.field(
    "o",
    $decode.int,
    (order) => {
      return $decode.field(
        "k",
        $decode.string,
        (kind) => {
          return $decode.optional_field(
            "s",
            "",
            $decode.string,
            (session) => {
              return $decode.optional_field(
                "e",
                "",
                $decode.string,
                (envelope) => {
                  return $decode.optional_field(
                    "d",
                    "",
                    $decode.string,
                    (digest) => {
                      return $decode.optional_field(
                        "c",
                        0,
                        $decode.int,
                        (checkpoint) => {
                          return $decode.success(
                            new RawRecord(
                              order,
                              kind,
                              session,
                              envelope,
                              digest,
                              checkpoint,
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

export function string_to_record(line) {
  let $ = $json.parse(line, record_decoder());
  if ($ instanceof Ok) {
    let $1 = $[0].kind;
    if ($1 === "state") {
      let order = $[0].order;
      let session = $[0].session;
      let envelope = $[0].envelope;
      return new Ok(new StateRecord(order, session, envelope));
    } else if ($1 === "traffic") {
      let order = $[0].order;
      let session = $[0].session;
      let envelope = $[0].envelope;
      return new Ok(new TrafficRecord(order, session, envelope));
    } else if ($1 === "digest") {
      let order = $[0].order;
      let digest = $[0].digest;
      let checkpoint = $[0].checkpoint;
      return new Ok(new DigestRecord(order, digest, checkpoint));
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

function new_room() {
  return new Room(
    $dict.new$(),
    1,
    $List$Empty$const,
    Option$None$const,
    "",
    0,
    0,
    0,
    0,
  );
}

export function new_relay() {
  return new Relay($dict.new$(), $dict.new$());
}

/**
 * The room names that the relay holds now, sorted. A room with a log stays
 * after its last client leaves. That behaviour makes a relay durable, and not
 * a hub.
 */
export function room_names(relay) {
  let _pipe = $dict.keys(relay.rooms);
  return $list.sort(_pipe, $string.compare);
}

/**
 * The connections that the relay admitted to a room, sorted.
 */
export function clients(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    let _pipe = $dict.keys(found.clients);
    return $list.sort(_pipe, $int.compare);
  } else {
    return $List$Empty$const;
  }
}

/**
 * The sessions that the relay admitted to a room, sorted.
 */
export function sessions(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    let _pipe = $dict.values(found.clients);
    let _pipe$1 = $list.map(_pipe, (client) => { return client.session; });
    return $list.sort(_pipe$1, $string.compare);
  } else {
    return $List$Empty$const;
  }
}

/**
 * The next order that a room stamps. The value is one more than the order of
 * the last accepted frame, and it is `1` for a room that has accepted no
 * frame.
 */
export function next_order(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    return found.next_order;
  } else {
    return 1;
  }
}

/**
 * The number of entries in the log of a room. After a successful attestation,
 * that number is the checkpoint with every entry that the attesting connection
 * reported as unreadable. It is `1` in the usual case, where there was no such
 * entry.
 */
export function log_size(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    return $list.length(found.log);
  } else {
    return 0;
  }
}

/**
 * The digest that a client attested for the checkpoint of the room. The value
 * is `""` when the room has never checkpointed, and when the room changed
 * after that checkpoint.
 *
 * The digest describes the checkpoint *entry*, which is not always the whole
 * log. A log that also carries the entries that the attesting client could not
 * read holds more than this digest names, and a client that can read those
 * entries holds more than the digest too. That is the correct reading. The
 * other option is a digest that claims to cover records that no client
 * merged.
 */
export function attested_digest(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    return found.attested;
  } else {
    return "";
  }
}

/**
 * Every envelope that a `stateRequest` would replay, oldest first.
 */
export function replayable(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    return $list.map(found.log, (entry) => { return entry.envelope; });
  } else {
    return $List$Empty$const;
  }
}

function room_of(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    return found;
  } else {
    return new_room();
  }
}

/**
 * The room and the per-room record of an admitted connection. A connection in
 * `connections` is always in the `clients` field of its room, because `admit`
 * inserts both entries and `disconnect` removes both. The inner lookup thus
 * fails only for a broken relay, and it reports `Error(Nil)` for that.
 * 
 * @ignore
 */
function client_of(relay, connection) {
  return $result.try$(
    $dict.get(relay.connections, connection),
    (room) => {
      return $result.try$(
        $dict.get(room_of(relay, room).clients, connection),
        (client) => { return new Ok([room, client]); },
      );
    },
  );
}

/**
 * The orders that one connection reported as unreadable, and that the log of
 * its room still holds, sorted. This function is a diagnostic. A service makes
 * it available, so that an operator can see the exact entries that the relay
 * carries past a checkpoint, and the connection that reported each one. The
 * operator thus does not have to guess at the reason that the log of a room
 * does not become one line.
 */
export function skipped_orders(relay, connection) {
  let $ = client_of(relay, connection);
  if ($ instanceof Ok) {
    let client = $[0][1];
    return $list.sort(client.skipped, $int.compare);
  } else {
    return $List$Empty$const;
  }
}

/**
 * Every order that a connection in this room reported as unreadable, as a set.
 * A flooded room calls this function one time for each refusal, so the function
 * does not scan one list inside another. That choice is deliberate.
 * 
 * @ignore
 */
function claimed_orders(found) {
  return $dict.fold(
    found.clients,
    $set.new$(),
    (carried, _, client) => {
      return $list.fold(
        client.skipped,
        carried,
        (carried, order) => { return $set.insert(carried, order); },
      );
    },
  );
}

function carriage(found) {
  let claimed = claimed_orders(found);
  let _pipe = found.log;
  let _pipe$1 = $list.filter(
    _pipe,
    (entry) => { return $set.contains(claimed, entry.order); },
  );
  let _pipe$2 = $list.map(_pipe$1, (entry) => { return entry.order; });
  return $list.sort(_pipe$2, $int.compare);
}

/**
 * Every order that this room carries now, which means that the log still holds
 * it and that one attached connection or more reported that it cannot merge
 * it. The list is sorted, oldest first, and the log of the room bounds it. This
 * function is a diagnostic. An operator reads it to see the entries that a
 * checkpoint lands around, and the reason that the log of a room does not
 * become one line.
 */
export function carried_orders(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    return carriage(found);
  } else {
    return $List$Empty$const;
  }
}

/**
 * The order of the `state` entry that the checkpoint of this room describes.
 * The value is `0` when the room has never checkpointed. That entry is the
 * canonical state of the room. An operator reads this value to see what a new
 * attachment would rebuild from.
 */
export function checkpoint_order(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    return found.checkpoint_order;
  } else {
    return 0;
  }
}

/**
 * The number of `CheckpointRequest` frames that this room sent after this
 * process started. This function is for metrics. A room whose count grows
 * while its log stays large is a room whose clients do not answer those
 * requests.
 */
export function checkpoint_requests(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    return found.requests;
  } else {
    return 0;
  }
}

/**
 * The connections in this room that have a `CheckpointRequest` frame with no
 * answer, sorted.
 */
export function checkpoints_pending(relay, room) {
  let $ = $dict.get(relay.rooms, room);
  if ($ instanceof Ok) {
    let found = $[0];
    let _pipe = $dict.to_list(found.clients);
    let _pipe$1 = $list.filter(
      _pipe,
      (entry) => { return entry[1].checkpoint_requested; },
    );
    let _pipe$2 = $list.map(_pipe$1, (entry) => { return entry[0]; });
    return $list.sort(_pipe$2, $int.compare);
  } else {
    return $List$Empty$const;
  }
}

/**
 * Whether this connection told the relay that it understands a
 * `CheckpointRequest` frame.
 */
export function supports_checkpoints(relay, connection) {
  let $ = client_of(relay, connection);
  if ($ instanceof Ok) {
    let client = $[0][1];
    return client.supports_checkpoints;
  } else {
    return false;
  }
}

/**
 * The orders that the live log of a room holds, as a set.
 * 
 * @ignore
 */
function log_orders(found) {
  return $list.fold(
    found.log,
    $set.new$(),
    (carried, entry) => { return $set.insert(carried, entry.order); },
  );
}

/**
 * A socket opened. The relay writes first, so the capability negotiation ends
 * before a client sends anything.
 */
export function connect(relay, connection) {
  return [relay, toList([new Send(connection, connected_frame())])];
}

/**
 * A socket closed, for any reason. A second call has no more effect, and the
 * function never changes the log. The durable content of a room outlives every
 * client in that room.
 */
export function disconnect(relay, connection) {
  let $ = $dict.get(relay.connections, connection);
  if ($ instanceof Ok) {
    let room = $[0];
    let _block;
    let $1 = $dict.get(relay.rooms, room);
    if ($1 instanceof Ok) {
      let found = $1[0];
      _block = $dict.insert(
        relay.rooms,
        room,
        new Room(
          $dict.delete$(found.clients, connection),
          found.next_order,
          found.log,
          (() => {
            let $2 = found.pending;
            if ($2 instanceof Some) {
              let owner = $2[0][0];
              if (owner === connection) {
                return Option$None$const;
              } else {
                return $2;
              }
            } else {
              return $2;
            }
          })(),
          found.attested,
          found.attested_order,
          found.checkpoint_order,
          found.pressure_at,
          found.requests,
        ),
      );
    } else {
      _block = relay.rooms;
    }
    let rooms = _block;
    return [
      new Relay(rooms, $dict.delete$(relay.connections, connection)),
      $List$Empty$const,
    ];
  } else {
    return [relay, $List$Empty$const];
  }
}

function fan_out(recipients, order, raw) {
  return $list.map(
    recipients,
    (connection) => { return new Send(connection, new Frame(order, raw)); },
  );
}

/**
 * Record that the relay sent everything up to `order` to these connections.
 * 
 * @ignore
 */
function delivered(room, recipients, order) {
  return new Room(
    $list.fold(
      recipients,
      room.clients,
      (clients, connection) => {
        let $ = $dict.get(clients, connection);
        if ($ instanceof Ok) {
          let client = $[0];
          return $dict.insert(
            clients,
            connection,
            new Client(
              client.from,
              client.session,
              $int.max(client.delivered, order),
              client.skipped,
              client.supports_checkpoints,
              client.checkpoint_requested,
            ),
          );
        } else {
          return clients;
        }
      },
    ),
    room.next_order,
    room.log,
    room.pending,
    room.attested,
    room.attested_order,
    room.checkpoint_order,
    room.pressure_at,
    room.requests,
  );
}

function store(relay, room, found) {
  return new Relay($dict.insert(relay.rooms, room, found), relay.connections);
}

function others(room, sender) {
  let _pipe = $dict.keys(room.clients);
  let _pipe$1 = $list.sort(_pipe, $int.compare);
  return $list.filter(
    _pipe$1,
    (connection) => { return connection !== sender; },
  );
}

/**
 * This connection answered the request that the relay sent to it.
 * 
 * @ignore
 */
function answered(clients, connection) {
  let $ = $dict.get(clients, connection);
  if ($ instanceof Ok) {
    let client = $[0];
    return $dict.insert(
      clients,
      connection,
      new Client(
        client.from,
        client.session,
        client.delivered,
        client.skipped,
        client.supports_checkpoints,
        false,
      ),
    );
  } else {
    return clients;
  }
}

/**
 * Send a `CheckpointRequest` frame to one connection, if that connection is a
 * candidate for one. A candidate declared `Supports(checkpoint_requests)`, and
 * it has no request outstanding. The function does nothing for every other
 * connection, which is a connection that never declared support, and a
 * connection that still owes an answer.
 *
 * The function moves `pressure_at` to the size that it quoted. The next record
 * thus does not evaluate a room that just asked.
 * 
 * @ignore
 */
function send_checkpoint_request(found, size, connection) {
  let $ = $dict.get(found.clients, connection);
  if ($ instanceof Ok) {
    let client = $[0];
    if (client.supports_checkpoints && !client.checkpoint_requested) {
      return [
        new Room(
          $dict.insert(
            found.clients,
            connection,
            new Client(
              client.from,
              client.session,
              client.delivered,
              client.skipped,
              client.supports_checkpoints,
              true,
            ),
          ),
          found.next_order,
          found.log,
          found.pending,
          found.attested,
          found.attested_order,
          found.checkpoint_order,
          $int.max(found.pressure_at, size),
          found.requests + 1,
        ),
        toList([new Send(connection, ServerFrame$CheckpointRequest$const)]),
      ];
    } else {
      return [found, $List$Empty$const];
    }
  } else {
    return [found, $List$Empty$const];
  }
}

/**
 * Ask the attached clients to checkpoint, if the room needs a checkpoint and
 * did not just ask for one.
 *
 * The function is bounded and idempotent, and both properties are deliberate:
 *
 *   * The function asks nothing below `checkpoint_pressure_records`, so an
 *     ordinary room never receives one of these frames.
 *   * The function does not ask a connection that has a request with no
 *     answer, so a client that answers slowly does not receive many requests.
 *   * A room that asked does not ask again until its log grows another
 *     `checkpoint_request_interval`. The hard bound of a flood thus also
 *     bounds the frames that the flood can produce.
 *   * The function asks a connection that declared
 *     `Supports(checkpoint_requests)` only. A client that a developer built
 *     against an earlier version of this lane thus never receives a frame that
 *     it would treat as a violation.
 *
 * The request carries the live log size of the room and a reason, and nothing
 * else. In particular it carries **no order**. A client answers from its own
 * merged state, so there is no path from the diagnostic sequence of a relay
 * into a document through this frame.
 *
 * An append drives this function, in a room whose log still grows toward the
 * bound. A room that is already *at* the bound cannot grow, and this function
 * never asks it. That room still empties, because the ordinary attach flow ends
 * in a publication, and the relay always admits a `state` frame from a client
 * that declared support at the bound. See `room_has_capacity`.
 * 
 * @ignore
 */
function ask_for_checkpoints(found) {
  let size = $list.length(found.log);
  let $ = (size >= checkpoint_pressure_records) && (size >= (found.pressure_at + checkpoint_request_interval));
  if ($) {
    let _block;
    let _pipe = $dict.to_list(found.clients);
    let _pipe$1 = $list.filter(
      _pipe,
      (entry) => {
        return entry[1].supports_checkpoints && !entry[1].checkpoint_requested;
      },
    );
    let _pipe$2 = $list.map(_pipe$1, (entry) => { return entry[0]; });
    _block = $list.sort(_pipe$2, $int.compare);
    let targets = _block;
    return $list.fold(
      targets,
      [
        new Room(
          found.clients,
          found.next_order,
          found.log,
          found.pending,
          found.attested,
          found.attested_order,
          found.checkpoint_order,
          size,
          found.requests,
        ),
        $List$Empty$const,
      ],
      (carried, connection) => {
        let found$1 = carried[0];
        let actions = carried[1];
        let $1 = send_checkpoint_request(found$1, size, connection);
        let found$2 = $1[0];
        let more = $1[1];
        return [found$2, $list.append(actions, more)];
      },
    );
  } else {
    return [found, $List$Empty$const];
  }
}

/**
 * One admitted document frame.
 *
 * The relay answers a `stateRequest` frame from its log, and it does not
 * forward that frame. The relay is the one participant that always has the
 * state of the room, and to ask a client for that state would make every
 * attachment a storm of broadcasts.
 *
 * The relay stamps every other frame, it logs the frame when that frame is
 * durable, and it sends the frame to the other clients in the room. It never
 * sends the frame back to its sender, because that sender already has it.
 *
 * The relay bounds a durable frame **before** it appends that frame. The live
 * log of a room stops at `max_room_records`, whether or not a client reported
 * that it cannot read those records. The half of a flood that no client
 * refused is still a flood. An admitted client that is alone in a room can
 * write correct traffic that no client will skip, and the carriage count,
 * which counts refused records only, would never see it.
 *
 * After the log passes `checkpoint_pressure_records`, the relay asks the
 * compatible clients to checkpoint. At the bound, the relay refuses the sender
 * and closes it, and every record that is already on disk stays exactly as it
 * is.
 * 
 * @ignore
 */
function route(relay, connection, room, session, message, raw) {
  let found = room_of(relay, room);
  if (message instanceof HelloMessage) {
    let order = found.next_order;
    let found$1 = new Room(
      found.clients,
      order + 1,
      found.log,
      found.pending,
      found.attested,
      found.attested_order,
      found.checkpoint_order,
      found.pressure_at,
      found.requests,
    );
    let recipients = others(found$1, connection);
    return [
      store(relay, room, delivered(found$1, recipients, order)),
      fan_out(recipients, order, raw),
    ];
  } else if (message instanceof ChannelMessage) {
    let order = found.next_order;
    let line = record_to_string(new TrafficRecord(order, session, raw));
    let found$1 = new Room(
      found.clients,
      order + 1,
      $list.append(
        found.log,
        toList([new Entry(order, session, raw, false, line)]),
      ),
      Option$None$const,
      "",
      found.attested_order,
      found.checkpoint_order,
      found.pressure_at,
      found.requests,
    );
    let recipients = others(found$1, connection);
    let $ = ask_for_checkpoints(found$1);
    let found$2 = $[0];
    let asked = $[1];
    return [
      store(relay, room, delivered(found$2, recipients, order)),
      listPrepend(
        new Append(room, line),
        $list.append(fan_out(recipients, order, raw), asked),
      ),
    ];
  } else if (message instanceof DeltaMessage) {
    let order = found.next_order;
    let line = record_to_string(new TrafficRecord(order, session, raw));
    let found$1 = new Room(
      found.clients,
      order + 1,
      $list.append(
        found.log,
        toList([new Entry(order, session, raw, false, line)]),
      ),
      Option$None$const,
      "",
      found.attested_order,
      found.checkpoint_order,
      found.pressure_at,
      found.requests,
    );
    let recipients = others(found$1, connection);
    let $ = ask_for_checkpoints(found$1);
    let found$2 = $[0];
    let asked = $[1];
    return [
      store(relay, room, delivered(found$2, recipients, order)),
      listPrepend(
        new Append(room, line),
        $list.append(fan_out(recipients, order, raw), asked),
      ),
    ];
  } else if (message instanceof StateRequestMessage) {
    let high = found.next_order - 1;
    return [
      store(relay, room, delivered(found, toList([connection]), high)),
      $list.append(
        $list.map(
          found.log,
          (entry) => {
            return new Send(connection, new Frame(entry.order, entry.envelope));
          },
        ),
        toList([new Send(connection, new Synced(high))]),
      ),
    ];
  } else if (message instanceof StateMessage) {
    let order = found.next_order;
    let line = record_to_string(new StateRecord(order, session, raw));
    let found$1 = new Room(
      answered(found.clients, connection),
      order + 1,
      $list.append(
        found.log,
        toList([new Entry(order, session, raw, true, line)]),
      ),
      new Some([connection, order]),
      "",
      found.attested_order,
      found.checkpoint_order,
      found.pressure_at,
      found.requests,
    );
    let recipients = others(found$1, connection);
    return [
      store(relay, room, delivered(found$1, recipients, order)),
      listPrepend(new Append(room, line), fan_out(recipients, order, raw)),
    ];
  } else {
    let order = found.next_order;
    let found$1 = new Room(
      found.clients,
      order + 1,
      found.log,
      found.pending,
      found.attested,
      found.attested_order,
      found.checkpoint_order,
      found.pressure_at,
      found.requests,
    );
    let recipients = others(found$1, connection);
    return [
      store(relay, room, delivered(found$1, recipients, order)),
      fan_out(recipients, order, raw),
    ];
  }
}

function refusal_tag(refusal) {
  return "rejected:" + refusal_parts(refusal)[0];
}

function refuse(connection, refusal) {
  let $ = refusal_parts(refusal);
  let reason = $[0];
  let detail = $[1];
  return toList([
    new Send(connection, new Refused(reason, detail)),
    new Close(connection, reason),
  ]);
}

/**
 * Whether this room can append one more durable record for this connection.
 *
 * The bound is on the room, and not on the connection, because the log belongs
 * to the room. There is one exception: a `state` frame from a connection that
 * declared `Supports(checkpoint_requests)`. That frame can compact a full room,
 * and to refuse it would stop exactly the correct client that the checkpoint
 * machinery protects. A client that publishes past the bound and never attests
 * gains nothing more. The relay refuses the next append from that client that
 * is not a `state` frame, at the bound, and it closes that connection.
 * 
 * @ignore
 */
function room_has_capacity(found, connection, message) {
  let $ = $list.length(found.log) < max_room_records;
  if ($) {
    return $;
  } else {
    let $1 = $dict.get(found.clients, connection);
    if ($1 instanceof Ok) {
      if (message instanceof HelloMessage) {
        return false;
      } else if (message instanceof ChannelMessage) {
        return false;
      } else if (message instanceof DeltaMessage) {
        return false;
      } else if (message instanceof StateRequestMessage) {
        return false;
      } else if (message instanceof StateMessage) {
        let client = $1[0];
        return client.supports_checkpoints;
      } else {
        return false;
      }
    } else if (message instanceof HelloMessage) {
      return false;
    } else if (message instanceof ChannelMessage) {
      return false;
    } else if (message instanceof DeltaMessage) {
      return false;
    } else if (message instanceof StateRequestMessage) {
      return false;
    } else if (message instanceof StateMessage) {
      return false;
    } else {
      return false;
    }
  }
}

/**
 * Whether this durable frame fits in the bounded live log of this room.
 *
 * The function checks the three message kinds that the relay logs. It does not
 * check a `hello` frame, a `digest` frame, or a `stateRequest` frame. The relay
 * stamps or answers those three and never appends them. A room at its bound
 * thus still admits a client, still answers a replay, and still carries a
 * digest. A correct client can therefore attach to a full room, refuse what it
 * cannot read, and empty that room.
 * 
 * @ignore
 */
function capacity(relay, connection, room, message) {
  if (message instanceof HelloMessage) {
    return new Ok(undefined);
  } else if (message instanceof ChannelMessage) {
    let $ = room_has_capacity(room_of(relay, room), connection, message);
    if ($) {
      return new Ok(undefined);
    } else {
      return new Error(new RoomAtCapacity(max_room_records));
    }
  } else if (message instanceof DeltaMessage) {
    let $ = room_has_capacity(room_of(relay, room), connection, message);
    if ($) {
      return new Ok(undefined);
    } else {
      return new Error(new RoomAtCapacity(max_room_records));
    }
  } else if (message instanceof StateRequestMessage) {
    return new Ok(undefined);
  } else if (message instanceof StateMessage) {
    let $ = room_has_capacity(room_of(relay, room), connection, message);
    if ($) {
      return new Ok(undefined);
    } else {
      return new Error(new RoomAtCapacity(max_room_records));
    }
  } else {
    return new Ok(undefined);
  }
}

/**
 * Admission, with its one continuing obligation.
 *
 * The first frame must be a `hello` frame, and that frame fixes the room, the
 * sender, and the session for the whole life of the connection. The relay
 * checks every later frame against those three values. A client thus cannot
 * change its room, it cannot forge the identity of another replica, and it
 * cannot use a session that is already attached. One connection has one
 * replica and one room.
 * 
 * @ignore
 */
function admit(relay, connection, room, from, session, message) {
  let $ = $dict.get(relay.connections, connection);
  if ($ instanceof Ok) {
    let admitted_room = $[0];
    return $result.try$(
      (() => {
        let _pipe = $dict.get(room_of(relay, admitted_room).clients, connection);
        return $result.replace_error(
          _pipe,
          new IdentityChanged("the admitted connection has no client record"),
        );
      })(),
      (client) => {
        let $1 = admitted_room === room;
        let $2 = client.from === from;
        let $3 = client.session === session;
        if ($1) {
          if ($2) {
            if ($3) {
              return new Ok(relay);
            } else {
              return new Error(
                new IdentityChanged(
                  (("admitted with session " + client.session) + ", sent a frame for ") + session,
                ),
              );
            }
          } else {
            return new Error(
              new IdentityChanged(
                (("admitted as " + client.from) + ", sent a frame from ") + from,
              ),
            );
          }
        } else {
          return new Error(
            new IdentityChanged(
              (("admitted to " + admitted_room) + ", sent a frame for ") + room,
            ),
          );
        }
      },
    );
  } else if (message instanceof HelloMessage) {
    let _block;
    let $1 = $dict.get(relay.rooms, room);
    if ($1 instanceof Ok) {
      let found = $1[0];
      _block = found;
    } else {
      _block = new_room();
    }
    let found = _block;
    let _block$1;
    let _pipe = $dict.values(found.clients);
    _block$1 = $list.any(
      _pipe,
      (client) => { return client.session === session; },
    );
    let taken = _block$1;
    let $2 = $dict.size(found.clients) >= max_room_clients;
    if (taken) {
      return new Error(new DuplicateSession(session));
    } else if ($2) {
      return new Error(new RoomFull(max_room_clients));
    } else {
      let client = new Client(from, session, 0, $List$Empty$const, false, false);
      return new Ok(
        new Relay(
          $dict.insert(
            relay.rooms,
            room,
            new Room(
              $dict.insert(found.clients, connection, client),
              found.next_order,
              found.log,
              found.pending,
              found.attested,
              found.attested_order,
              found.checkpoint_order,
              found.pressure_at,
              found.requests,
            ),
          ),
          $dict.insert(relay.connections, connection, room),
        ),
      );
    }
  } else {
    return new Error(Refusal$NotAdmitted$const);
  }
}

/**
 * A connection that reports which optional control frames it understands.
 *
 * The relay accepts this frame from an admitted connection only. The frame is a
 * statement about a client in a room, and a connection that did not send
 * `hello` is in no room. The frame stamps no order, it logs nothing, and it
 * broadcasts nothing. To repeat it is to make the same statement two times.
 *
 * A connection that never sends this frame never receives a
 * `CheckpointRequest` frame. At the hard bound, the relay admits a `state`
 * frame only from a client that declared support. See `room_has_capacity`.
 * Such a connection thus also never publishes past that bound.
 * 
 * @ignore
 */
function declare_support(relay, connection, checkpoint_requests) {
  return $result.try$(
    (() => {
      let _pipe = client_of(relay, connection);
      return $result.replace_error(_pipe, Refusal$NotAdmitted$const);
    })(),
    (_use0) => {
      let room = _use0[0];
      let client = _use0[1];
      let found = room_of(relay, room);
      let found$1 = new Room(
        $dict.insert(
          found.clients,
          connection,
          new Client(
            client.from,
            client.session,
            client.delivered,
            client.skipped,
            checkpoint_requests,
            client.checkpoint_requested,
          ),
        ),
        found.next_order,
        found.log,
        found.pending,
        found.attested,
        found.attested_order,
        found.checkpoint_order,
        found.pressure_at,
        found.requests,
      );
      return new Ok([store(relay, room, found$1), $List$Empty$const]);
    },
  );
}

/**
 * One order that this connection could not process.
 *
 * The relay accepts the claim only when it sent that order to *this*
 * connection. A claim about any other order is a claim about an entry that
 * this client has no evidence of, and to act on it would let a client decide
 * the fate of something that it never saw.
 *
 * The relay drops a claim that it does not accept, and that claim is not
 * fatal. A relay that stamps an order that it does not account for is at
 * fault, and the client that speaks to it is not. There is also nothing in the
 * log for such a claim to attach to.
 *
 * A skip is a fact about a delivery, and never about the content. The relay
 * does not learn the reason that the client refused the entry, it does not stop
 * to carry that entry to the other clients, and it never deletes that entry on
 * one claim. The claim buys one thing: the next checkpoint of this connection
 * can land *around* the entry, and the compaction carries that entry beside the
 * checkpoint. Without the claim, that entry would block the checkpoint without
 * an end.
 *
 * A claim that the relay does not accept changes nothing at all. The relay does
 * not accept a claim for an order that it never delivered, for an order outside
 * its range, and for an order that the log no longer holds. A repeated skip is
 * the same claim two times, and it also changes nothing.
 * 
 * @ignore
 */
function skip(relay, connection, order) {
  return $result.try$(
    (() => {
      let _pipe = client_of(relay, connection);
      return $result.replace_error(_pipe, Refusal$NotAdmitted$const);
    })(),
    (_use0) => {
      let room = _use0[0];
      let client = _use0[1];
      let found = room_of(relay, room);
      let $ = (order >= 1) && (order <= client.delivered);
      if ($) {
        let _block;
        let $1 = $list.contains(client.skipped, order);
        if ($1) {
          _block = client.skipped;
        } else {
          _block = listPrepend(order, client.skipped);
        }
        let claimed = _block;
        let live = log_orders(found);
        let skipped = $list.filter(
          claimed,
          (skipped) => { return $set.contains(live, skipped); },
        );
        let $2 = $list.length(skipped) > max_client_skips;
        if ($2) {
          return new Error(new TooManySkips(max_client_skips));
        } else {
          let relay$1 = store(
            relay,
            room,
            new Room(
              $dict.insert(
                found.clients,
                connection,
                new Client(
                  client.from,
                  client.session,
                  client.delivered,
                  skipped,
                  client.supports_checkpoints,
                  client.checkpoint_requested,
                ),
              ),
              found.next_order,
              found.log,
              found.pending,
              found.attested,
              found.attested_order,
              found.checkpoint_order,
              found.pressure_at,
              found.requests,
            ),
          );
          return new Ok([relay$1, $List$Empty$const, true]);
        }
      } else {
        return new Ok([relay, $List$Empty$const, false]);
      }
    },
  );
}

/**
 * Every line that the log file of a room must hold now: its live entries, in
 * order, with the checkpoint marker of that room, if the room has one. A
 * compaction that dropped that marker would make a restart forget the digest
 * that a client attested, and it would also forget *which* `state` record of
 * the log the room rebuilds from.
 *
 * The marker carries `attested`, and that value is `""` after anything arrives
 * after the checkpoint. That is the correct reading: the entry is still the
 * canonical state of the room, and the digest no longer describes the room.
 * 
 * @ignore
 */
function compaction_lines(found) {
  let lines = $list.map(found.log, (entry) => { return entry.line; });
  let $ = (found.checkpoint_order > 0) || (found.attested !== "");
  if ($) {
    return $list.append(
      lines,
      toList([
        record_to_string(
          new DigestRecord(
            $int.max(found.attested_order, found.checkpoint_order),
            found.attested,
            found.checkpoint_order,
          ),
        ),
      ]),
    );
  } else {
    return lines;
  }
}

/**
 * An attestation: the digest of the publisher, with the highest order that the
 * publisher accounted for when it published.
 *
 * The relay cannot check any of that, and it does not claim to. This is the
 * **attestation of a trusted client**, which some component authenticated
 * before it admitted that client. Admission is the trust boundary that this
 * design rests on. The relay applies every rule that it *can* apply. It clamps
 * `upTo` to the orders that it sent to this connection, and the checkpoint of a
 * publisher never retires a record that the same publisher reported as
 * skipped.
 *
 * There are three kinds of entry, and the relay removes one kind only:
 *
 *   * **subsumed**: an entry at the clamped `upTo` or below it, or an entry
 *     that the publisher wrote. The published state *claims to contain* that
 *     entry, so the relay retires it.
 *   * **skipped**: an entry that *this* connection reported as unreadable. The
 *     published state says that it does *not* contain that entry, so the relay
 *     **keeps** it, beside the checkpoint, on disk and in memory.
 *   * **outstanding**: every other entry, for example a concurrent state or a
 *     delta that raced the publication. The client did not account for that
 *     entry, so the echo is empty and the log does not change.
 *
 * A checkpoint thus never makes the history of the room shorter. It replaces
 * the entries that the publisher merged with that merge, and it carries every
 * entry that the publisher did not merge forward, without a change. A later
 * client that *can* read those entries still receives them, and the checkpoint
 * of that client, which has no skip to keep them alive, finally retires
 * them.
 * 
 * @ignore
 */
function attest(relay, connection, frame) {
  return $result.try$(
    (() => {
      if (frame instanceof Attest) {
        let digest = frame.digest;
        let up_to = frame.up_to;
        return new Ok([digest, up_to]);
      } else if (frame instanceof Skip) {
        return new Error(new Malformed("a skip is not an attestation"));
      } else {
        return new Error(new Malformed("a support list is not an attestation"));
      }
    })(),
    (_use0) => {
      let digest = _use0[0];
      let up_to = _use0[1];
      return $result.try$(
        (() => {
          let _pipe = client_of(relay, connection);
          return $result.replace_error(_pipe, Refusal$NotAdmitted$const);
        })(),
        (_use0) => {
          let room = _use0[0];
          let client = _use0[1];
          let found = room_of(relay, room);
          let order = found.next_order;
          let bound = $int.min(up_to, client.delivered);
          let $ = found.pending;
          if ($ instanceof Some) {
            let owner = $[0][0];
            if (owner === connection) {
              let state_order = $[0][1];
              let refused = $set.from_list(client.skipped);
              let preserved = $list.filter(
                found.log,
                (entry) => {
                  return (entry.order !== state_order) && $set.contains(
                    refused,
                    entry.order,
                  );
                },
              );
              let outstanding = $list.filter(
                found.log,
                (entry) => {
                  return (((entry.order !== state_order) && !$set.contains(
                    refused,
                    entry.order,
                  )) && (entry.order > bound)) && (entry.session !== client.session);
                },
              );
              let checkpoint = $list.find(
                found.log,
                (entry) => { return entry.order === state_order; },
              );
              let _block;
              if (checkpoint instanceof Ok) {
                let entry = checkpoint[0];
                let _pipe = $list.append(preserved, toList([entry]));
                _block = $list.sort(
                  _pipe,
                  (left, right) => {
                    return $int.compare(left.order, right.order);
                  },
                );
              } else {
                _block = $List$Empty$const;
              }
              let kept = _block;
              if (outstanding instanceof $Empty && checkpoint instanceof Ok) {
                let found$1 = new Room(
                  (() => {
                    let held = $list.fold(
                      kept,
                      $set.new$(),
                      (carried, entry) => {
                        return $set.insert(carried, entry.order);
                      },
                    );
                    return $dict.insert(
                      found.clients,
                      connection,
                      new Client(
                        client.from,
                        client.session,
                        client.delivered,
                        $list.filter(
                          client.skipped,
                          (skipped) => { return $set.contains(held, skipped); },
                        ),
                        client.supports_checkpoints,
                        client.checkpoint_requested,
                      ),
                    );
                  })(),
                  order + 1,
                  kept,
                  Option$None$const,
                  digest,
                  order,
                  state_order,
                  0,
                  found.requests,
                );
                return new Ok(
                  [
                    store(relay, room, found$1),
                    toList([
                      new Append(
                        room,
                        record_to_string(
                          new DigestRecord(order, digest, state_order),
                        ),
                      ),
                      new Compact(room, compaction_lines(found$1)),
                      new Send(connection, new Attested(order, digest)),
                    ]),
                  ],
                );
              } else {
                let found$1 = new Room(
                  found.clients,
                  order + 1,
                  found.log,
                  found.pending,
                  "",
                  found.attested_order,
                  found.checkpoint_order,
                  found.pressure_at,
                  found.requests,
                );
                return new Ok(
                  [
                    store(relay, room, found$1),
                    toList([new Send(connection, new Attested(order, ""))]),
                  ],
                );
              }
            } else {
              let found$1 = new Room(
                found.clients,
                order + 1,
                found.log,
                found.pending,
                found.attested,
                found.attested_order,
                found.checkpoint_order,
                found.pressure_at,
                found.requests,
              );
              return new Ok(
                [
                  store(relay, room, found$1),
                  toList([new Send(connection, new Attested(order, ""))]),
                ],
              );
            }
          } else {
            let found$1 = new Room(
              found.clients,
              order + 1,
              found.log,
              found.pending,
              found.attested,
              found.attested_order,
              found.checkpoint_order,
              found.pressure_at,
              found.requests,
            );
            return new Ok(
              [
                store(relay, room, found$1),
                toList([new Send(connection, new Attested(order, ""))]),
              ],
            );
          }
        },
      );
    },
  );
}

/**
 * One control frame, with the tag of that frame.
 * 
 * @ignore
 */
function control(relay, connection, frame) {
  if (frame instanceof Attest) {
    return $result.try$(
      attest(relay, connection, frame),
      (_use0) => {
        let relay$1 = _use0[0];
        let actions = _use0[1];
        return new Ok([relay$1, actions, "attest"]);
      },
    );
  } else if (frame instanceof Skip) {
    let order = frame.order;
    return $result.try$(
      skip(relay, connection, order),
      (_use0) => {
        let relay$1 = _use0[0];
        let actions = _use0[1];
        let honoured = _use0[2];
        return new Ok(
          [
            relay$1,
            actions,
            (() => {
              if (honoured) {
                return "skip";
              } else {
                return "skip:undelivered";
              }
            })(),
          ],
        );
      },
    );
  } else {
    let checkpoint_requests$1 = frame.checkpoint_requests;
    return $result.try$(
      declare_support(relay, connection, checkpoint_requests$1),
      (_use0) => {
        let relay$1 = _use0[0];
        let actions = _use0[1];
        return new Ok([relay$1, actions, "supports"]);
      },
    );
  }
}

/**
 * `handle_frame`, with the tag of the frame.
 *
 * The tag is the whole instrumentation of a relay. It is `hello`, `channel`,
 * `delta`, `stateRequest`, `state`, `digest`, `attest`, `skip`,
 * `skip:undelivered`, or `rejected:<reason>`. It comes from the `type` tag of
 * the envelope, and from whether the relay refused the frame. It never comes
 * from a payload.
 */
export function serve(relay, connection, raw) {
  let $ = decode_client(raw);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Document) {
      let raw$1 = $1.raw;
      let room = $1.room;
      let from = $1.from;
      let session = $1.session;
      let message = $1.message;
      let $2 = admit(relay, connection, room, from, session, message);
      if ($2 instanceof Ok) {
        let relay$1 = $2[0];
        let $3 = capacity(relay$1, connection, room, message);
        if ($3 instanceof Ok) {
          let $4 = route(relay$1, connection, room, session, message, raw$1);
          let relay$2 = $4[0];
          let actions = $4[1];
          return [relay$2, actions, message_kind_to_string(message)];
        } else {
          let refusal = $3[0];
          return [relay$1, refuse(connection, refusal), refusal_tag(refusal)];
        }
      } else {
        let refusal = $2[0];
        return [relay, refuse(connection, refusal), refusal_tag(refusal)];
      }
    } else {
      let frame = $1.frame;
      let $2 = control(relay, connection, frame);
      if ($2 instanceof Ok) {
        let relay$1 = $2[0][0];
        let actions = $2[0][1];
        let tag = $2[0][2];
        return [relay$1, actions, tag];
      } else {
        let refusal = $2[0];
        return [relay, refuse(connection, refusal), refusal_tag(refusal)];
      }
    }
  } else {
    let refusal = $[0];
    return [relay, refuse(connection, refusal), refusal_tag(refusal)];
  }
}

/**
 * Apply one raw frame from one connection.
 */
export function handle_frame(relay, connection, raw) {
  let $ = serve(relay, connection, raw);
  let relay$1 = $[0];
  let actions = $[1];
  return [relay$1, actions];
}

function record_order(record) {
  if (record instanceof StateRecord) {
    let order = record.order;
    return order;
  } else if (record instanceof TrafficRecord) {
    let order = record.order;
    return order;
  } else {
    let order = record.order;
    return order;
  }
}

/**
 * Rebuild one room from its durable lines.
 *
 * This function skips a line that it cannot read, and such a line is not
 * fatal. The caller gives this module a list of lines, and the module cannot
 * separate an incomplete tail from a corrupt middle. That decision belongs to
 * the component that read the file. The reference service makes that decision
 * before it calls this function: it removes an incomplete trailing fragment and
 * refuses to start, or it quarantines the file, for every other fault. What
 * arrives here is thus already the log that the service intends to replay.
 *
 * Three properties of a room that is *already* in memory never move backwards
 * when this function reads the lines:
 *
 *   * `next_order` only moves forward, to `max(existing, highest + 1)`. To
 *     reuse an order that the relay already delivered to a live connection
 *     would make the `delivered` clamp of that connection useless, and it
 *     would let a later attestation retire an entry that no client saw.
 *   * The function takes the **attestation** of the room from the disk only
 *     when the disk proves a *current* one, which is a checkpoint marker that
 *     is the newest record in the file. A record that the relay logged after a
 *     checkpoint means that the checkpoint no longer describes the room.
 *   * The function also takes the **canonical checkpoint entry** of the room,
 *     which the marker names in its `c` field. A restart thus cannot leave the
 *     room unable to say which of its `state` records is canonical. For a log
 *     that a relay wrote before a marker named its entry, the function uses
 *     the newest `state` record in that log.
 */
export function replay(relay, room, lines) {
  let read = $list.filter_map(
    lines,
    (line) => {
      let _pipe = string_to_record(line);
      return $result.map(_pipe, (record) => { return [line, record]; });
    },
  );
  let records = $list.map(read, (pair) => { return pair[1]; });
  let log = $list.filter_map(
    read,
    (pair) => {
      let line = pair[0];
      let record = pair[1];
      if (record instanceof StateRecord) {
        let order = record.order;
        let session = record.session;
        let envelope = record.envelope;
        return new Ok(new Entry(order, session, envelope, true, line));
      } else if (record instanceof TrafficRecord) {
        let order = record.order;
        let session = record.session;
        let envelope = record.envelope;
        return new Ok(new Entry(order, session, envelope, false, line));
      } else {
        return new Error(undefined);
      }
    },
  );
  let highest = $list.fold(
    records,
    0,
    (carried, record) => { return $int.max(carried, record_order(record)); },
  );
  let marker = $list.fold(
    records,
    Option$None$const,
    (carried, record) => {
      if (carried instanceof Some) {
        if (record instanceof StateRecord) {
          return carried;
        } else if (record instanceof TrafficRecord) {
          return carried;
        } else {
          let $ = carried[0];
          if ($ instanceof DigestRecord) {
            let order = record.order;
            let held = $.order;
            if (order <= held) {
              return carried;
            } else {
              return new Some(record);
            }
          } else {
            return new Some(record);
          }
        }
      } else if (record instanceof StateRecord) {
        return carried;
      } else if (record instanceof TrafficRecord) {
        return carried;
      } else {
        return new Some(record);
      }
    },
  );
  let _block;
  if (marker instanceof Some) {
    let $1 = marker[0];
    if ($1 instanceof StateRecord) {
      _block = ["", 0, 0];
    } else if ($1 instanceof TrafficRecord) {
      _block = ["", 0, 0];
    } else {
      let order = $1.order;
      if (order === highest) {
        let digest = $1.digest;
        let checkpoint = $1.checkpoint;
        _block = [digest, order, checkpoint];
      } else {
        let order = $1.order;
        let checkpoint = $1.checkpoint;
        _block = ["", order, checkpoint];
      }
    }
  } else {
    _block = ["", 0, 0];
  }
  let $ = _block;
  let attested = $[0];
  let attested_order = $[1];
  let marked = $[2];
  let _block$1;
  let $1 = (marked > 0) && $list.any(
    log,
    (entry) => { return entry.order === marked; },
  );
  if ($1) {
    _block$1 = marked;
  } else {
    let _pipe = log;
    let _pipe$1 = $list.filter(_pipe, (entry) => { return entry.state; });
    _block$1 = $list.fold(
      _pipe$1,
      0,
      (carried, entry) => { return $int.max(carried, entry.order); },
    );
  }
  let checkpoint_order$1 = _block$1;
  let existing = room_of(relay, room);
  return store(
    relay,
    room,
    new Room(
      existing.clients,
      $int.max(existing.next_order, highest + 1),
      log,
      Option$None$const,
      attested,
      attested_order,
      checkpoint_order$1,
      0,
      existing.requests,
    ),
  );
}

/**
 * The socket actions as `#(connection, payload, close_reason)` triples. A
 * `Send` action carries its encoded frame and an empty close reason. A `Close`
 * action carries an empty payload and its reason. The function keeps the order,
 * so the `error` frame of a refusal always goes out before its close.
 */
export function render_sockets(actions) {
  return $list.filter_map(
    actions,
    (action) => {
      if (action instanceof Send) {
        let connection = action.connection;
        let frame = action.frame;
        return new Ok([connection, server_to_string(frame), ""]);
      } else if (action instanceof Close) {
        let connection = action.connection;
        let reason = action.reason;
        return new Ok([connection, "", reason]);
      } else if (action instanceof Append) {
        return new Error(undefined);
      } else {
        return new Error(undefined);
      }
    },
  );
}

/**
 * The storage actions as `#(room, mode, lines)` triples, where `mode` is
 * `append` or `compact`.
 *
 * The function keeps the order, and that order is the guarantee. The append
 * that carries a checkpoint always comes before the compaction that keeps that
 * checkpoint. A service that performs these actions in order, and durably,
 * thus cannot lose a record to a crash between two of them.
 */
export function render_storage(actions) {
  return $list.filter_map(
    actions,
    (action) => {
      if (action instanceof Send) {
        return new Error(undefined);
      } else if (action instanceof Close) {
        return new Error(undefined);
      } else if (action instanceof Append) {
        let room = action.room;
        let line = action.line;
        return new Ok([room, "append", toList([line])]);
      } else {
        let room = action.room;
        let lines = action.lines;
        return new Ok([room, "compact", lines]);
      }
    },
  );
}

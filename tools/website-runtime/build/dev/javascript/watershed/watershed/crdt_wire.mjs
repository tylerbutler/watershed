/// <reference types="./crdt_wire.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  CustomType as $CustomType,
  toBitArray,
  stringBits,
} from "../gleam.mjs";
import * as $canonical_json from "../watershed/canonical_json.mjs";
import * as $channel from "../watershed/channel.mjs";
import * as $p2p from "../watershed/p2p.mjs";
import * as $wire from "../watershed/wire.mjs";
import * as $wire_op from "../watershed/wire/op.mjs";

export class Limits extends $CustomType {
  constructor(room_peers, envelope_bytes, snapshot_bytes, channels, buffered_deltas, recent_message_ids) {
    super();
    this.room_peers = room_peers;
    this.envelope_bytes = envelope_bytes;
    this.snapshot_bytes = snapshot_bytes;
    this.channels = channels;
    this.buffered_deltas = buffered_deltas;
    this.recent_message_ids = recent_message_ids;
  }
}
export const Limits$Limits = (room_peers, envelope_bytes, snapshot_bytes, channels, buffered_deltas, recent_message_ids) =>
  new Limits(room_peers,
  envelope_bytes,
  snapshot_bytes,
  channels,
  buffered_deltas,
  recent_message_ids);
export const Limits$isLimits = (value) => value instanceof Limits;
export const Limits$Limits$room_peers = (value) => value.room_peers;
export const Limits$Limits$0 = (value) => value.room_peers;
export const Limits$Limits$envelope_bytes = (value) => value.envelope_bytes;
export const Limits$Limits$1 = (value) => value.envelope_bytes;
export const Limits$Limits$snapshot_bytes = (value) => value.snapshot_bytes;
export const Limits$Limits$2 = (value) => value.snapshot_bytes;
export const Limits$Limits$channels = (value) => value.channels;
export const Limits$Limits$3 = (value) => value.channels;
export const Limits$Limits$buffered_deltas = (value) => value.buffered_deltas;
export const Limits$Limits$4 = (value) => value.buffered_deltas;
export const Limits$Limits$recent_message_ids = (value) =>
  value.recent_message_ids;
export const Limits$Limits$5 = (value) => value.recent_message_ids;

export class MessageId extends $CustomType {
  constructor(replica, counter) {
    super();
    this.replica = replica;
    this.counter = counter;
  }
}
export const MessageId$MessageId = (replica, counter) =>
  new MessageId(replica, counter);
export const MessageId$isMessageId = (value) => value instanceof MessageId;
export const MessageId$MessageId$replica = (value) => value.replica;
export const MessageId$MessageId$0 = (value) => value.replica;
export const MessageId$MessageId$counter = (value) => value.counter;
export const MessageId$MessageId$1 = (value) => value.counter;

export class ChannelDescriptor extends $CustomType {
  constructor(address, channel_type, created_by) {
    super();
    this.address = address;
    this.channel_type = channel_type;
    this.created_by = created_by;
  }
}
export const ChannelDescriptor$ChannelDescriptor = (address, channel_type, created_by) =>
  new ChannelDescriptor(address, channel_type, created_by);
export const ChannelDescriptor$isChannelDescriptor = (value) =>
  value instanceof ChannelDescriptor;
export const ChannelDescriptor$ChannelDescriptor$address = (value) =>
  value.address;
export const ChannelDescriptor$ChannelDescriptor$0 = (value) => value.address;
export const ChannelDescriptor$ChannelDescriptor$channel_type = (value) =>
  value.channel_type;
export const ChannelDescriptor$ChannelDescriptor$1 = (value) =>
  value.channel_type;
export const ChannelDescriptor$ChannelDescriptor$created_by = (value) =>
  value.created_by;
export const ChannelDescriptor$ChannelDescriptor$2 = (value) =>
  value.created_by;

export class ChannelEntry extends $CustomType {
  constructor(descriptor, snapshot) {
    super();
    this.descriptor = descriptor;
    this.snapshot = snapshot;
  }
}
export const ChannelEntry$ChannelEntry = (descriptor, snapshot) =>
  new ChannelEntry(descriptor, snapshot);
export const ChannelEntry$isChannelEntry = (value) =>
  value instanceof ChannelEntry;
export const ChannelEntry$ChannelEntry$descriptor = (value) => value.descriptor;
export const ChannelEntry$ChannelEntry$0 = (value) => value.descriptor;
export const ChannelEntry$ChannelEntry$snapshot = (value) => value.snapshot;
export const ChannelEntry$ChannelEntry$1 = (value) => value.snapshot;

/**
 * The compatibility handshake: the two facts that a merge cannot
 * reconcile if two peers disagree about them.
 */
export class Hello extends $CustomType {
  constructor(compatibility, root) {
    super();
    this.compatibility = compatibility;
    this.root = root;
  }
}
export const Message$Hello = (compatibility, root) =>
  new Hello(compatibility, root);
export const Message$isHello = (value) => value instanceof Hello;
export const Message$Hello$compatibility = (value) => value.compatibility;
export const Message$Hello$0 = (value) => value.compatibility;
export const Message$Hello$root = (value) => value.root;
export const Message$Hello$1 = (value) => value.root;

/**
 * Announce an immutable channel descriptor with its initial snapshot.
 */
export class ChannelAnnounce extends $CustomType {
  constructor(entry) {
    super();
    this.entry = entry;
  }
}
export const Message$ChannelAnnounce = (entry) => new ChannelAnnounce(entry);
export const Message$isChannelAnnounce = (value) =>
  value instanceof ChannelAnnounce;
export const Message$ChannelAnnounce$entry = (value) => value.entry;
export const Message$ChannelAnnounce$0 = (value) => value.entry;

/**
 * Merge one channel delta.
 */
export class Delta extends $CustomType {
  constructor(id, address, channel_type, operation) {
    super();
    this.id = id;
    this.address = address;
    this.channel_type = channel_type;
    this.operation = operation;
  }
}
export const Message$Delta = (id, address, channel_type, operation) =>
  new Delta(id, address, channel_type, operation);
export const Message$isDelta = (value) => value instanceof Delta;
export const Message$Delta$id = (value) => value.id;
export const Message$Delta$0 = (value) => value.id;
export const Message$Delta$address = (value) => value.address;
export const Message$Delta$1 = (value) => value.address;
export const Message$Delta$channel_type = (value) => value.channel_type;
export const Message$Delta$2 = (value) => value.channel_type;
export const Message$Delta$operation = (value) => value.operation;
export const Message$Delta$3 = (value) => value.operation;

/**
 * Ask a peer for its complete registry and its current snapshots.
 */
export class StateRequest extends $CustomType {}
export const Message$StateRequest$const = new StateRequest();
export const Message$StateRequest = () => Message$StateRequest$const;
export const Message$isStateRequest = (value) => value instanceof StateRequest;

/**
 * A complete document that a peer can merge: every descriptor with its
 * snapshot.
 */
export class State extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}
export const Message$State = (entries) => new State(entries);
export const Message$isState = (value) => value instanceof State;
export const Message$State$entries = (value) => value.entries;
export const Message$State$0 = (value) => value.entries;

/**
 * The canonical document digest, for anti-entropy.
 */
export class Digest extends $CustomType {
  constructor(digest) {
    super();
    this.digest = digest;
  }
}
export const Message$Digest = (digest) => new Digest(digest);
export const Message$isDigest = (value) => value instanceof Digest;
export const Message$Digest$digest = (value) => value.digest;
export const Message$Digest$0 = (value) => value.digest;

/**
 * Report a rejection to the peer that caused it. The name is `Rejected`
 * here, because the wire tag `error` is also a constructor of `Result`.
 */
export class Rejected extends $CustomType {
  constructor(reason, detail) {
    super();
    this.reason = reason;
    this.detail = detail;
  }
}
export const Message$Rejected = (reason, detail) =>
  new Rejected(reason, detail);
export const Message$isRejected = (value) => value instanceof Rejected;
export const Message$Rejected$reason = (value) => value.reason;
export const Message$Rejected$0 = (value) => value.reason;
export const Message$Rejected$detail = (value) => value.detail;
export const Message$Rejected$1 = (value) => value.detail;

export class Envelope extends $CustomType {
  constructor(room, from, session, message) {
    super();
    this.room = room;
    this.from = from;
    this.session = session;
    this.message = message;
  }
}
export const Envelope$Envelope = (room, from, session, message) =>
  new Envelope(room, from, session, message);
export const Envelope$isEnvelope = (value) => value instanceof Envelope;
export const Envelope$Envelope$room = (value) => value.room;
export const Envelope$Envelope$0 = (value) => value.room;
export const Envelope$Envelope$from = (value) => value.from;
export const Envelope$Envelope$1 = (value) => value.from;
export const Envelope$Envelope$session = (value) => value.session;
export const Envelope$Envelope$2 = (value) => value.session;
export const Envelope$Envelope$message = (value) => value.message;
export const Envelope$Envelope$3 = (value) => value.message;

class Preamble extends $CustomType {
  constructor(version, room, from, session, message) {
    super();
    this.version = version;
    this.room = room;
    this.from = from;
    this.session = session;
    this.message = message;
  }
}

class RawHello extends $CustomType {
  constructor(compatibility, root) {
    super();
    this.compatibility = compatibility;
    this.root = root;
  }
}

class RawChannel extends $CustomType {
  constructor(entry) {
    super();
    this.entry = entry;
  }
}

class RawDelta extends $CustomType {
  constructor(replica, counter, address, channel_type, contents) {
    super();
    this.replica = replica;
    this.counter = counter;
    this.address = address;
    this.channel_type = channel_type;
    this.contents = contents;
  }
}

class RawStateRequest extends $CustomType {}
const RawMessage$RawStateRequest$const = new RawStateRequest();

class RawState extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}

class RawDigest extends $CustomType {
  constructor(digest) {
    super();
    this.digest = digest;
  }
}

class RawRejected extends $CustomType {
  constructor(reason, detail) {
    super();
    this.reason = reason;
    this.detail = detail;
  }
}

class RawEntry extends $CustomType {
  constructor(address, channel_type, created_by, snapshot) {
    super();
    this.address = address;
    this.channel_type = channel_type;
    this.created_by = created_by;
    this.snapshot = snapshot;
  }
}

const type_error = "error";

const type_digest = "digest";

const type_state = "state";

const type_state_request = "stateRequest";

const type_delta = "delta";

const type_channel = "channel";

const type_hello = "hello";

/**
 * The reserved root channel address. Every peer derives the root from its own
 * `Config` value, and never from a peer, so no replica owns the root.
 */
export const root_address = "root";

/**
 * The only protocol version that this module uses. A peer that announces any
 * other version gets a `ProtocolMismatch` error, before this module reads its
 * message.
 */
export const protocol_version = 1;

/**
 * The version-1 default limits.
 */
export function default_limits() {
  return new Limits(8, 262_144, 4_194_304, 1024, 256, 4096);
}

/**
 * The wire tag of a message, for diagnostics and for status reports.
 */
export function message_type(message) {
  if (message instanceof Hello) {
    return type_hello;
  } else if (message instanceof ChannelAnnounce) {
    return type_channel;
  } else if (message instanceof Delta) {
    return type_delta;
  } else if (message instanceof StateRequest) {
    return type_state_request;
  } else if (message instanceof State) {
    return type_state;
  } else if (message instanceof Digest) {
    return type_digest;
  } else {
    return type_error;
  }
}

/**
 * The address of the nth channel of a replica. The address contains the
 * replica id, so two replicas cannot produce the same address, and they need
 * no coordination.
 */
export function channel_address(replica, counter) {
  return (replica + ":") + $int.to_string(counter);
}

function positive_counter(raw) {
  let $ = $int.parse(raw);
  if ($ instanceof Ok) {
    let value = $[0];
    return (value > 0) && ($int.to_string(value) === raw);
  } else {
    return false;
  }
}

/**
 * Whether a string can identify a replica. Such a string is not empty, and it
 * contains no `:` character, because `:` separates the two halves of an
 * address.
 */
export function valid_replica_id(replica) {
  return (replica !== "") && !$string.contains(replica, ":");
}

/**
 * The replica that created a channel, read from the address of that channel.
 * The root address gives `""`, because no replica creates the root.
 */
export function address_creator(address) {
  let $ = address === root_address;
  if ($) {
    return new Ok("");
  } else {
    let $1 = $string.split(address, ":");
    if ($1 instanceof $Empty) {
      return new Error(undefined);
    } else {
      let $2 = $1.tail;
      if ($2 instanceof $Empty) {
        return new Error(undefined);
      } else {
        let $3 = $2.tail;
        if ($3 instanceof $Empty) {
          let replica = $1.head;
          let counter = $2.head;
          let $4 = valid_replica_id(replica);
          let $5 = positive_counter(counter);
          if ($4) {
            if ($5) {
              return new Ok(replica);
            } else {
              return new Error(undefined);
            }
          } else if ($5) {
            return new Error(undefined);
          } else {
            return new Error(undefined);
          }
        } else {
          return new Error(undefined);
        }
      }
    }
  }
}

export function encode_descriptor(descriptor) {
  return $json.object(
    toList([
      ["address", $json.string(descriptor.address)],
      [
        "channelType",
        $json.string($channel.type_to_string(descriptor.channel_type)),
      ],
      ["createdBy", $json.string(descriptor.created_by)],
    ]),
  );
}

export function encode_channel_entry(entry) {
  return $json.object(
    toList([
      ["descriptor", encode_descriptor(entry.descriptor)],
      ["snapshot", $channel.encode_snapshot(entry.snapshot)],
    ]),
  );
}

/**
 * The channel entries in canonical order, sorted by address. The insertion
 * order of the registry thus cannot change the encoded bytes.
 *
 * The comparison is `canonical_json.compare`, and not `string.compare`. The
 * digest uses that comparison for the same reason. `string.compare` orders by
 * UTF-8 bytes on Erlang and by UTF-16 code units on JavaScript. A replica id
 * outside the basic plane would thus put the `state` messages of two peers in
 * different orders. The meaning of the message is the same in both orders.
 * The purpose is that one logical state has one encoding on both targets.
 */
export function sort_entries(entries) {
  return $list.sort(
    entries,
    (left, right) => {
      return $canonical_json.compare(
        left.descriptor.address,
        right.descriptor.address,
      );
    },
  );
}

function encode_message_id(id) {
  return $json.preprocessed_array(
    toList([$json.string(id.replica), $json.int(id.counter)]),
  );
}

export function encode_message(message) {
  if (message instanceof Hello) {
    let compatibility = message.compatibility;
    let root = message.root;
    return $json.object(
      toList([
        ["type", $json.string(type_hello)],
        ["compatibility", $json.string(compatibility)],
        ["root", $json.string($channel.type_to_string(root))],
      ]),
    );
  } else if (message instanceof ChannelAnnounce) {
    let entry = message.entry;
    return $json.object(
      toList([
        ["type", $json.string(type_channel)],
        ["descriptor", encode_descriptor(entry.descriptor)],
        ["snapshot", $channel.encode_snapshot(entry.snapshot)],
      ]),
    );
  } else if (message instanceof Delta) {
    let id = message.id;
    let address = message.address;
    let channel_type = message.channel_type;
    let operation = message.operation;
    return $json.object(
      toList([
        ["type", $json.string(type_delta)],
        ["id", encode_message_id(id)],
        ["address", $json.string(address)],
        ["channelType", $json.string($channel.type_to_string(channel_type))],
        ["contents", $wire_op.encode_channel_operation(operation)],
      ]),
    );
  } else if (message instanceof StateRequest) {
    return $json.object(toList([["type", $json.string(type_state_request)]]));
  } else if (message instanceof State) {
    let entries = message.entries;
    return $json.object(
      toList([
        ["type", $json.string(type_state)],
        ["channels", $json.array(sort_entries(entries), encode_channel_entry)],
      ]),
    );
  } else if (message instanceof Digest) {
    let digest = message.digest;
    return $json.object(
      toList([
        ["type", $json.string(type_digest)],
        ["digest", $json.string(digest)],
      ]),
    );
  } else {
    let reason = message.reason;
    let detail = message.detail;
    return $json.object(
      toList([
        ["type", $json.string(type_error)],
        ["reason", $json.string(reason)],
        ["detail", $json.string(detail)],
      ]),
    );
  }
}

/**
 * Encode an envelope. The field order is fixed, so two equal envelopes encode
 * to two equal strings on both targets.
 */
export function encode_envelope(envelope) {
  return $json.object(
    toList([
      ["v", $json.int(protocol_version)],
      ["room", $json.string(envelope.room)],
      ["from", $json.string(envelope.from)],
      ["session", $json.string(envelope.session)],
      ["message", encode_message(envelope.message)],
    ]),
  );
}

export function envelope_to_string(envelope) {
  return $json.to_string(encode_envelope(envelope));
}

function invalid(from, detail) {
  return new $p2p.InvalidEnvelope(from, detail);
}

/**
 * A `state` message that names one address two times has no unambiguous
 * merge, because the two entries can disagree on the type or on the creator.
 * The module thus refuses the whole message. It does not merge the entries in
 * list order.
 * 
 * @ignore
 */
function check_unique_addresses(entries, from) {
  let _block;
  let _pipe = $list.map(
    entries,
    (entry) => { return entry.descriptor.address; },
  );
  _block = $list.sort(_pipe, $canonical_json.compare);
  let addresses = _block;
  let _block$1;
  let _pipe$1 = $list.window_by_2(addresses);
  _block$1 = $list.any(_pipe$1, (pair) => { return pair[0] === pair[1]; });
  let duplicated = _block$1;
  if (duplicated) {
    return new Error(invalid(from, "state repeats a channel address"));
  } else {
    return new Ok(undefined);
  }
}

function byte_size(raw) {
  return $bit_array.byte_size(toBitArray([stringBits(raw)]));
}

function check_size(bytes, limit, to_error) {
  let $ = $int.compare(bytes, limit);
  if ($ instanceof $order.Lt) {
    return new Ok(undefined);
  } else if ($ instanceof $order.Eq) {
    return new Ok(undefined);
  } else {
    return new Error(to_error(bytes, limit));
  }
}

function eligible_type(raw, from) {
  let $ = $channel.string_to_type(raw);
  if ($ instanceof Ok) {
    let channel_type = $[0];
    return $p2p.validate(channel_type);
  } else {
    return new Error(invalid(from, "unknown channel type " + raw));
  }
}

function validate_entry(raw, from, limits) {
  return $result.try$(
    (() => {
      let _pipe = address_creator(raw.address);
      return $result.replace_error(
        _pipe,
        invalid(from, "channel names the invalid address " + raw.address),
      );
    })(),
    (creator) => {
      return $result.try$(
        (() => {
          let $ = creator === raw.created_by;
          if ($) {
            return new Ok(undefined);
          } else {
            return new Error(
              invalid(
                from,
                (((("channel " + raw.address) + " claims creator ") + raw.created_by) + " but its address names ") + creator,
              ),
            );
          }
        })(),
        (_) => {
          return $result.try$(
            eligible_type(raw.channel_type, from),
            (channel_type) => {
              let encoded = $json.to_string(raw.snapshot);
              return $result.try$(
                check_size(
                  byte_size(encoded),
                  limits.snapshot_bytes,
                  (var0, var1) => {
                    return new $p2p.SnapshotTooLarge(var0, var1);
                  },
                ),
                (_) => {
                  return $result.try$(
                    (() => {
                      let _pipe = $json.parse(
                        encoded,
                        $channel.snapshot_decoder(channel_type),
                      );
                      return $result.replace_error(
                        _pipe,
                        invalid(
                          from,
                          (("snapshot for " + raw.address) + " does not match channel type ") + $channel.type_to_string(
                            channel_type,
                          ),
                        ),
                      );
                    })(),
                    (snapshot) => {
                      return new Ok(
                        new ChannelEntry(
                          new ChannelDescriptor(
                            raw.address,
                            channel_type,
                            raw.created_by,
                          ),
                          snapshot,
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

function raw_entry_decoder() {
  return $decode.subfield(
    toList(["descriptor", "address"]),
    $decode.string,
    (address) => {
      return $decode.subfield(
        toList(["descriptor", "channelType"]),
        $decode.string,
        (channel_type) => {
          return $decode.subfield(
            toList(["descriptor", "createdBy"]),
            $decode.string,
            (created_by) => {
              return $decode.field(
                "snapshot",
                $wire.json_value_decoder(),
                (snapshot) => {
                  return $decode.success(
                    new RawEntry(address, channel_type, created_by, snapshot),
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
 * Check one encoded channel entry, which is an element of a `state` message,
 * a `channel` announcement, or a channel of a canonical snapshot. Every
 * caller shares this function, so a snapshot from storage gets the same
 * checks as a snapshot from a peer.
 */
export function decode_channel_entry(value, from, limits) {
  return $result.try$(
    (() => {
      let _pipe = $json.parse($json.to_string(value), raw_entry_decoder());
      return $result.replace_error(
        _pipe,
        invalid(from, "malformed channel entry"),
      );
    })(),
    (raw) => { return validate_entry(raw, from, limits); },
  );
}

function validate_message(raw, from, limits) {
  if (raw instanceof RawHello) {
    let compatibility = raw.compatibility;
    let root = raw.root;
    return $result.try$(
      eligible_type(root, from),
      (root) => { return new Ok(new Hello(compatibility, root)); },
    );
  } else if (raw instanceof RawChannel) {
    let entry = raw.entry;
    return $result.try$(
      validate_entry(entry, from, limits),
      (entry) => { return new Ok(new ChannelAnnounce(entry)); },
    );
  } else if (raw instanceof RawDelta) {
    let replica = raw.replica;
    let counter = raw.counter;
    let address = raw.address;
    let channel_type = raw.channel_type;
    let contents = raw.contents;
    return $result.try$(
      (() => {
        let $ = valid_replica_id(replica) && (counter > 0);
        if ($) {
          return new Ok(undefined);
        } else {
          return new Error(invalid(from, "delta has an invalid message id"));
        }
      })(),
      (_) => {
        return $result.try$(
          (() => {
            let _pipe = address_creator(address);
            return $result.replace_error(
              _pipe,
              invalid(from, "delta names the invalid address " + address),
            );
          })(),
          (_) => {
            return $result.try$(
              eligible_type(channel_type, from),
              (channel_type) => {
                return $result.try$(
                  (() => {
                    let _pipe = $json.parse(
                      $json.to_string(contents),
                      $wire_op.channel_operation_decoder(channel_type),
                    );
                    return $result.replace_error(
                      _pipe,
                      invalid(
                        from,
                        "delta contents do not match channel type " + $channel.type_to_string(
                          channel_type,
                        ),
                      ),
                    );
                  })(),
                  (operation) => {
                    return new Ok(
                      new Delta(
                        new MessageId(replica, counter),
                        address,
                        channel_type,
                        operation,
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
  } else if (raw instanceof RawStateRequest) {
    return new Ok(Message$StateRequest$const);
  } else if (raw instanceof RawState) {
    let entries = raw.entries;
    return $result.try$(
      $list.try_map(
        entries,
        (entry) => { return decode_channel_entry(entry, from, limits); },
      ),
      (entries) => {
        return $result.try$(
          check_unique_addresses(entries, from),
          (_) => { return new Ok(new State(entries)); },
        );
      },
    );
  } else if (raw instanceof RawDigest) {
    let digest = raw.digest;
    return new Ok(new Digest(digest));
  } else {
    let reason = raw.reason;
    let detail = raw.detail;
    return new Ok(new Rejected(reason, detail));
  }
}

function message_id_decoder() {
  return $decode.then$(
    $decode.list($decode.dynamic),
    (elements) => {
      if (elements instanceof $Empty) {
        return $decode.failure(["", 0], "MessageId");
      } else {
        let $ = elements.tail;
        if ($ instanceof $Empty) {
          return $decode.failure(["", 0], "MessageId");
        } else {
          let $1 = $.tail;
          if ($1 instanceof $Empty) {
            return $decode.subfield(
              toList([0]),
              $decode.string,
              (replica) => {
                return $decode.subfield(
                  toList([1]),
                  $decode.int,
                  (counter) => { return $decode.success([replica, counter]); },
                );
              },
            );
          } else {
            return $decode.failure(["", 0], "MessageId");
          }
        }
      }
    },
  );
}

function raw_message_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (tag) => {
      if (tag === "hello") {
        return $decode.field(
          "compatibility",
          $decode.string,
          (compatibility) => {
            return $decode.field(
              "root",
              $decode.string,
              (root) => {
                return $decode.success(new RawHello(compatibility, root));
              },
            );
          },
        );
      } else if (tag === "channel") {
        return $decode.then$(
          raw_entry_decoder(),
          (entry) => { return $decode.success(new RawChannel(entry)); },
        );
      } else if (tag === "delta") {
        return $decode.field(
          "id",
          message_id_decoder(),
          (id) => {
            return $decode.field(
              "address",
              $decode.string,
              (address) => {
                return $decode.field(
                  "channelType",
                  $decode.string,
                  (channel_type) => {
                    return $decode.field(
                      "contents",
                      $wire.json_value_decoder(),
                      (contents) => {
                        let replica = id[0];
                        let counter = id[1];
                        return $decode.success(
                          new RawDelta(
                            replica,
                            counter,
                            address,
                            channel_type,
                            contents,
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
      } else if (tag === "stateRequest") {
        return $decode.success(RawMessage$RawStateRequest$const);
      } else if (tag === "state") {
        return $decode.field(
          "channels",
          $decode.list($wire.json_value_decoder()),
          (entries) => { return $decode.success(new RawState(entries)); },
        );
      } else if (tag === "digest") {
        return $decode.field(
          "digest",
          $decode.string,
          (digest) => { return $decode.success(new RawDigest(digest)); },
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
                return $decode.success(new RawRejected(reason, detail));
              },
            );
          },
        );
      } else {
        return $decode.failure(RawMessage$RawStateRequest$const, "CrdtMessage");
      }
    },
  );
}

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
                  return $decode.field(
                    "message",
                    $wire.json_value_decoder(),
                    (message) => {
                      return $decode.success(
                        new Preamble(version, room, from, session, message),
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
 * Decode one encoded envelope. The function returns a typed error for
 * anything malformed. It checks the size first, then the protocol version,
 * and then the message body. It thus never parses an oversize payload or a
 * wrong-version payload as a message.
 */
export function decode_envelope(raw, limits) {
  return $result.try$(
    check_size(
      byte_size(raw),
      limits.envelope_bytes,
      (bytes, limit) => {
        return invalid(
          "",
          ((("envelope of " + $int.to_string(bytes)) + " bytes exceeds the ") + $int.to_string(
            limit,
          )) + " byte limit",
        );
      },
    ),
    (_) => {
      return $result.try$(
        (() => {
          let _pipe = $json.parse(raw, preamble_decoder());
          return $result.replace_error(
            _pipe,
            invalid("", "envelope is not a v1 CRDT envelope"),
          );
        })(),
        (preamble) => {
          let version = preamble.version;
          let room = preamble.room;
          let from = preamble.from;
          let session = preamble.session;
          let message = preamble.message;
          return $result.try$(
            (() => {
              let $ = version === protocol_version;
              if ($) {
                return new Ok(undefined);
              } else {
                return new Error(
                  new $p2p.ProtocolMismatch(protocol_version, version),
                );
              }
            })(),
            (_) => {
              return $result.try$(
                (() => {
                  let $ = valid_replica_id(from) && (session !== "");
                  if ($) {
                    return new Ok(undefined);
                  } else {
                    return new Error(
                      invalid(from, "envelope has no usable sender identity"),
                    );
                  }
                })(),
                (_) => {
                  return $result.try$(
                    (() => {
                      let _pipe = $json.parse(
                        $json.to_string(message),
                        raw_message_decoder(),
                      );
                      return $result.replace_error(
                        _pipe,
                        invalid(from, "message is not a v1 CRDT message"),
                      );
                    })(),
                    (raw_message) => {
                      return $result.try$(
                        validate_message(raw_message, from, limits),
                        (message) => {
                          return new Ok(
                            new Envelope(room, from, session, message),
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

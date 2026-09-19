/// <reference types="./crdt_core.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
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
import * as $canonical_json from "../watershed/canonical_json.mjs";
import * as $channel from "../watershed/channel.mjs";
import * as $crdt_wire from "../watershed/crdt_wire.mjs";
import { ChannelDescriptor, ChannelEntry, MessageId } from "../watershed/crdt_wire.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";
import * as $p2p from "../watershed/p2p.mjs";
import * as $sha256 from "../watershed/sha256.mjs";
import * as $wire from "../watershed/wire.mjs";

export class Config extends $CustomType {
  constructor(room, compatibility, replica, session, root, limits) {
    super();
    this.room = room;
    this.compatibility = compatibility;
    this.replica = replica;
    this.session = session;
    this.root = root;
    this.limits = limits;
  }
}
export const Config$Config = (room, compatibility, replica, session, root, limits) =>
  new Config(room, compatibility, replica, session, root, limits);
export const Config$isConfig = (value) => value instanceof Config;
export const Config$Config$room = (value) => value.room;
export const Config$Config$0 = (value) => value.room;
export const Config$Config$compatibility = (value) => value.compatibility;
export const Config$Config$1 = (value) => value.compatibility;
export const Config$Config$replica = (value) => value.replica;
export const Config$Config$2 = (value) => value.replica;
export const Config$Config$session = (value) => value.session;
export const Config$Config$3 = (value) => value.session;
export const Config$Config$root = (value) => value.root;
export const Config$Config$4 = (value) => value.root;
export const Config$Config$limits = (value) => value.limits;
export const Config$Config$5 = (value) => value.limits;

class Document extends $CustomType {
  constructor(config, counter, registry, states, buffered, recent) {
    super();
    this.config = config;
    this.counter = counter;
    this.registry = registry;
    this.states = states;
    this.buffered = buffered;
    this.recent = recent;
  }
}

class BufferedDelta extends $CustomType {
  constructor(id, address, channel_type, operation) {
    super();
    this.id = id;
    this.address = address;
    this.channel_type = channel_type;
    this.operation = operation;
  }
}

class Recent extends $CustomType {
  constructor(seen, queue) {
    super();
    this.seen = seen;
    this.queue = queue;
  }
}

class Fifo extends $CustomType {
  constructor(front, back, size) {
    super();
    this.front = front;
    this.back = back;
    this.size = size;
  }
}

export class Outcome extends $CustomType {
  constructor(broadcast, reply, created, events) {
    super();
    this.broadcast = broadcast;
    this.reply = reply;
    this.created = created;
    this.events = events;
  }
}
export const Outcome$Outcome = (broadcast, reply, created, events) =>
  new Outcome(broadcast, reply, created, events);
export const Outcome$isOutcome = (value) => value instanceof Outcome;
export const Outcome$Outcome$broadcast = (value) => value.broadcast;
export const Outcome$Outcome$0 = (value) => value.broadcast;
export const Outcome$Outcome$reply = (value) => value.reply;
export const Outcome$Outcome$1 = (value) => value.reply;
export const Outcome$Outcome$created = (value) => value.created;
export const Outcome$Outcome$2 = (value) => value.created;
export const Outcome$Outcome$events = (value) => value.events;
export const Outcome$Outcome$3 = (value) => value.events;

class CanonicalSnapshot extends $CustomType {
  constructor(version, room, compatibility, root, channels) {
    super();
    this.version = version;
    this.room = room;
    this.compatibility = compatibility;
    this.root = root;
    this.channels = channels;
  }
}

/**
 * A config carrying the version-1 default limits.
 */
export function config(room, compatibility, replica, session, root) {
  return new Config(
    room,
    compatibility,
    replica,
    session,
    root,
    $crdt_wire.default_limits(),
  );
}

function fifo_new() {
  return new Fifo($List$Empty$const, $List$Empty$const, 0);
}

function fifo_from_list(elements) {
  return new Fifo(elements, $List$Empty$const, $list.length(elements));
}

function fifo_to_list(fifo) {
  return $list.append(fifo.front, $list.reverse(fifo.back));
}

function fifo_push(fifo, element) {
  return new Fifo(fifo.front, listPrepend(element, fifo.back), fifo.size + 1);
}

function fifo_pop(loop$fifo) {
  while (true) {
    let fifo = loop$fifo;
    let $ = fifo.front;
    let $1 = fifo.back;
    if ($ instanceof $Empty) {
      if ($1 instanceof $Empty) {
        return new Error(undefined);
      } else {
        let back = $1;
        loop$fifo = new Fifo($list.reverse(back), $List$Empty$const, fifo.size);
      }
    } else {
      let oldest = $.head;
      let front = $.tail;
      return new Ok([oldest, new Fifo(front, fifo.back, fifo.size - 1)]);
    }
  }
}

export function empty_outcome() {
  return new Outcome(
    $List$Empty$const,
    $List$Empty$const,
    $List$Empty$const,
    $List$Empty$const,
  );
}

function empty_recent() {
  return new Recent($dict.new$(), fifo_new());
}

function rejected(from, detail) {
  return new $p2p.InvalidEnvelope(from, detail);
}

function validate_config(config) {
  let limits$1 = config.limits;
  let $ = config.room !== "";
  let $1 = $crdt_wire.valid_replica_id(config.replica);
  let $2 = config.session !== "";
  let $3 = (((((limits$1.channels > 0) && (limits$1.envelope_bytes > 0)) && (limits$1.snapshot_bytes > 0)) && (limits$1.room_peers > 0)) && (limits$1.buffered_deltas >= 0)) && (limits$1.recent_message_ids >= 0);
  if ($) {
    if ($1) {
      if ($2) {
        if ($3) {
          return new Ok(undefined);
        } else {
          return new Error(rejected(config.replica, "limits are not positive"));
        }
      } else {
        return new Error(rejected(config.replica, "session id is empty"));
      }
    } else {
      return new Error(
        rejected(config.replica, "replica id must be non-empty and free of ':'"),
      );
    }
  } else {
    return new Error(rejected(config.replica, "room id is empty"));
  }
}

/**
 * Start a document at the empty root that the config names. Every peer runs
 * this function, and so does the first peer in an empty room. The root comes
 * from `Config`, and never from a peer. Two replicas that agree on the config
 * thus agree on the root, and they exchange no message.
 */
export function new$(config) {
  return $result.try$(
    validate_config(config),
    (_) => {
      return $result.try$(
        $p2p.validate($channel.init_type(config.root)),
        (root_type) => {
          let descriptor$1 = new ChannelDescriptor(
            $crdt_wire.root_address,
            root_type,
            "",
          );
          return new Ok(
            new Document(
              config,
              0,
              $dict.from_list(toList([[$crdt_wire.root_address, descriptor$1]])),
              $dict.from_list(
                toList([
                  [
                    $crdt_wire.root_address,
                    $channel.new$(config.root, config.replica),
                  ],
                ]),
              ),
              fifo_new(),
              empty_recent(),
            ),
          );
        },
      );
    },
  );
}

export function config_of(document) {
  return document.config;
}

export function room(document) {
  return document.config.room;
}

export function compatibility(document) {
  return document.config.compatibility;
}

export function replica(document) {
  return document.config.replica;
}

export function session(document) {
  return document.config.session;
}

export function limits(document) {
  return document.config.limits;
}

export function root_type(document) {
  return $channel.init_type(document.config.root);
}

function entries(document) {
  let _pipe = descriptors(document);
  return $list.filter_map(
    _pipe,
    (descriptor) => {
      let $ = $dict.get(document.states, descriptor.address);
      if ($ instanceof Ok) {
        let state = $[0];
        return new Ok(new ChannelEntry(descriptor, $channel.snapshot(state)));
      } else {
        return new Error(undefined);
      }
    },
  );
}

/**
 * The document as canonical JSON. The field order is fixed, the channels are
 * sorted by address, and the snapshot codec of each channel encodes that
 * channel. Two replicas that reached the same value through different delivery
 * orders produce the same bytes.
 */
export function canonical_json(document) {
  return $json.to_string(
    $json.object(
      toList([
        ["v", $json.int($crdt_wire.protocol_version)],
        ["room", $json.string(document.config.room)],
        ["compatibility", $json.string(document.config.compatibility)],
        ["root", $json.string($channel.type_to_string(root_type(document)))],
        [
          "channels",
          $json.array(entries(document), $crdt_wire.encode_channel_entry),
        ],
      ]),
    ),
  );
}

/**
 * Every registered descriptor, in canonical address order, which is UTF-8 byte
 * order. That order is the same on both targets, and the order of
 * `string.compare` is not.
 */
export function descriptors(document) {
  let _pipe = $dict.values(document.registry);
  return $list.sort(
    _pipe,
    (left, right) => {
      return $canonical_json.compare(left.address, right.address);
    },
  );
}

export function channel_count(document) {
  return $dict.size(document.registry);
}

export function buffered_count(document) {
  return document.buffered.size;
}

/**
 * The number of message ids in the duplicate-suppression window. The value is
 * never more than `limits.recent_message_ids`.
 */
export function recent_count(document) {
  return $dict.size(document.recent.seen);
}

export function seen(document, id) {
  return $dict.has_key(document.recent.seen, id);
}

export function descriptor(document, address) {
  let $ = $dict.get(document.registry, address);
  if ($ instanceof Ok) {
    let descriptor$1 = $[0];
    return $result.try$(
      $p2p.validate(descriptor$1.channel_type),
      (_) => { return new Ok(descriptor$1); },
    );
  } else {
    return new Error(
      rejected(document.config.replica, "no channel registered at " + address),
    );
  }
}

/**
 * The channel type at an address. The function refuses to name a channel whose
 * kernel cannot run without a sequencer.
 */
export function channel_type(document, address) {
  return $result.try$(
    descriptor(document, address),
    (descriptor) => { return new Ok(descriptor.channel_type); },
  );
}

/**
 * The kernel state at an address. The function checks the eligibility of the
 * channel first.
 */
export function channel_state(document, address) {
  return $result.try$(
    descriptor(document, address),
    (_) => {
      let $ = $dict.get(document.states, address);
      if ($ instanceof Ok) {
        return $;
      } else {
        return new Error(
          rejected(document.config.replica, "no channel state at " + address),
        );
      }
    },
  );
}

export function hello_message(document) {
  return new $crdt_wire.Hello(
    document.config.compatibility,
    root_type(document),
  );
}

export function state_request_message() {
  return $crdt_wire.Message$StateRequest$const;
}

/**
 * The whole registry of this document, with its current snapshots, in
 * canonical address order.
 */
export function state_message(document) {
  return new $crdt_wire.State(entries(document));
}

function ordered_by_member(value, name) {
  if (value instanceof $json_ot.VArray) {
    let items = value[0];
    let _pipe = items;
    let _pipe$1 = $list.map(
      _pipe,
      (item) => {
        let _block;
        if (item instanceof $json_ot.VObject) {
          let members = item[0];
          let $ = $list.key_find(members, name);
          if ($ instanceof Ok) {
            let $1 = $[0];
            if ($1 instanceof $json_ot.VString) {
              let key = $1[0];
              _block = key;
            } else {
              let member = $1;
              _block = $canonical_json.to_string(member);
            }
          } else {
            _block = $canonical_json.to_string(item);
          }
        } else {
          _block = $canonical_json.to_string(item);
        }
        let key = _block;
        return [key, item];
      },
    );
    let _pipe$2 = $list.sort(
      _pipe$1,
      (left, right) => { return $canonical_json.compare(left[0], right[0]); },
    );
    let _pipe$3 = $list.map(_pipe$2, (pair) => { return pair[1]; });
    return new $json_ot.VArray(_pipe$3);
  } else {
    return value;
  }
}

function map_member(value, name, transform) {
  if (value instanceof $json_ot.VNull) {
    return value;
  } else if (value instanceof $json_ot.VBool) {
    return value;
  } else if (value instanceof $json_ot.VNumber) {
    return value;
  } else if (value instanceof $json_ot.VString) {
    return value;
  } else if (value instanceof $json_ot.VArray) {
    return value;
  } else {
    let members = value[0];
    return new $json_ot.VObject(
      $list.map(
        members,
        (member) => {
          let $ = member[0] === name;
          if ($) {
            return [member[0], transform(member[1])];
          } else {
            return member;
          }
        },
      ),
    );
  }
}

function map_each(value, transform) {
  if (value instanceof $json_ot.VNull) {
    return value;
  } else if (value instanceof $json_ot.VBool) {
    return value;
  } else if (value instanceof $json_ot.VNumber) {
    return value;
  } else if (value instanceof $json_ot.VString) {
    return value;
  } else if (value instanceof $json_ot.VArray) {
    let items = value[0];
    return new $json_ot.VArray($list.map(items, transform));
  } else {
    let members = value[0];
    return new $json_ot.VObject(
      $list.map(
        members,
        (member) => { return [member[0], transform(member[1])]; },
      ),
    );
  }
}

function without(value, names) {
  if (value instanceof $json_ot.VNull) {
    return value;
  } else if (value instanceof $json_ot.VBool) {
    return value;
  } else if (value instanceof $json_ot.VNumber) {
    return value;
  } else if (value instanceof $json_ot.VString) {
    return value;
  } else if (value instanceof $json_ot.VArray) {
    return value;
  } else {
    let members = value[0];
    return new $json_ot.VObject(
      $list.filter(
        members,
        (member) => { return !$list.contains(names, member[0]); },
      ),
    );
  }
}

/**
 * Order a set-shaped array by the canonical bytes of its elements. Use this
 * function on a field that the CRDT defines as a set or as a map only. Never
 * use it on the segments of a sequence, where the order *is* the state.
 * 
 * @ignore
 */
function ordered(value) {
  if (value instanceof $json_ot.VNull) {
    return value;
  } else if (value instanceof $json_ot.VBool) {
    return value;
  } else if (value instanceof $json_ot.VNumber) {
    return value;
  } else if (value instanceof $json_ot.VString) {
    return value;
  } else if (value instanceof $json_ot.VArray) {
    let items = value[0];
    return new $json_ot.VArray($canonical_json.sorted(items));
  } else {
    return value;
  }
}

function type_tag(value) {
  if (value instanceof $json_ot.VNull) {
    return "";
  } else if (value instanceof $json_ot.VBool) {
    return "";
  } else if (value instanceof $json_ot.VNumber) {
    return "";
  } else if (value instanceof $json_ot.VString) {
    return "";
  } else if (value instanceof $json_ot.VArray) {
    return "";
  } else {
    let members = value[0];
    let $ = $list.key_find(members, "type");
    if ($ instanceof Ok) {
      let $1 = $[0];
      if ($1 instanceof $json_ot.VString) {
        let tag$1 = $1[0];
        return tag$1;
      } else {
        return "";
      }
    } else {
      return "";
    }
  }
}

/**
 * Project a CRDT envelope that another envelope carries as a JSON string, and
 * write it back as a canonical string, so that the shape stays the same. The
 * function does not change a string that is not valid JSON.
 * 
 * @ignore
 */
function inner(value) {
  if (value instanceof $json_ot.VNull) {
    return value;
  } else if (value instanceof $json_ot.VBool) {
    return value;
  } else if (value instanceof $json_ot.VNumber) {
    return value;
  } else if (value instanceof $json_ot.VString) {
    let raw = value[0];
    let $ = $json.parse(raw, $json_ot.decoder());
    if ($ instanceof Ok) {
      let parsed = $[0];
      return new $json_ot.VString(
        $canonical_json.to_string(merge_relevant(parsed)),
      );
    } else {
      return value;
    }
  } else if (value instanceof $json_ot.VArray) {
    return value;
  } else {
    return value;
  }
}

/**
 * Remove the replica-local authoring cursors from one self-describing lattice
 * envelope.
 *
 * The function dispatches on the `type` tag of the envelope, and not on a
 * field path. One function thus handles a channel snapshot and the CRDTs that
 * an OR-map holds inside that snapshot as *stringified* JSON. The function
 * returns a value that it does not recognize without a change, so it compares
 * an unknown encoding in full. It does not weaken that comparison quietly.
 * `lww_register` is in that group on purpose. Its `replica_id` field is the
 * tie-break half of a timestamp, and not an authoring cursor. To remove it
 * would let two different winners produce the same hash.
 * 
 * @ignore
 */
function merge_relevant(value) {
  let $ = type_tag(value);
  if ($ === "lww_map") {
    return map_member(
      value,
      "state",
      (state) => {
        let _pipe = state;
        let _pipe$1 = without(_pipe, toList(["replica_id"]));
        let _pipe$2 = map_member(_pipe$1, "spec", inner);
        return map_member(
          _pipe$2,
          "entries",
          (entries) => {
            let _pipe$3 = entries;
            let _pipe$4 = map_each(
              _pipe$3,
              (_capture) => { return map_member(_capture, "value", inner); },
            );
            return ordered_by_member(_pipe$4, "key");
          },
        );
      },
    );
  } else if ($ === "mv_register") {
    return map_member(
      value,
      "state",
      (state) => {
        let _pipe = state;
        let _pipe$1 = without(_pipe, toList(["replica_id"]));
        return map_member(
          _pipe$1,
          "entries",
          (_capture) => { return ordered_by_member(_capture, "tag"); },
        );
      },
    );
  } else if ($ === "pn_counter") {
    return map_member(
      value,
      "state",
      (state) => {
        let _pipe = state;
        let _pipe$1 = map_member(
          _pipe,
          "positive",
          (_capture) => { return without(_capture, toList(["self_id"])); },
        );
        return map_member(
          _pipe$1,
          "negative",
          (_capture) => { return without(_capture, toList(["self_id"])); },
        );
      },
    );
  } else if ($ === "g_counter") {
    return map_member(
      value,
      "state",
      (_capture) => { return without(_capture, toList(["self_id"])); },
    );
  } else if ($ === "or_set") {
    return map_member(
      value,
      "state",
      (state) => {
        let _pipe = state;
        let _pipe$1 = without(_pipe, toList(["replica_id", "counter"]));
        let _pipe$2 = map_member(
          _pipe$1,
          "entries",
          (entries) => {
            if (entries instanceof $json_ot.VArray) {
              let _pipe$2 = entries;
              let _pipe$3 = map_each(
                _pipe$2,
                (_capture) => { return map_member(_capture, "tags", ordered); },
              );
              return ordered_by_member(_pipe$3, "value");
            } else {
              return map_each(entries, ordered);
            }
          },
        );
        return map_member(_pipe$2, "tombstones", ordered);
      },
    );
  } else if ($ === "g_set") {
    return map_member(
      value,
      "state",
      (_capture) => { return map_member(_capture, "elements", ordered); },
    );
  } else if ($ === "two_p_set") {
    return map_member(
      value,
      "state",
      (state) => {
        let _pipe = state;
        let _pipe$1 = map_member(_pipe, "added", ordered);
        return map_member(_pipe$1, "removed", ordered);
      },
    );
  } else if ($ === "sequence") {
    return map_member(
      value,
      "state",
      (state) => {
        let _pipe = state;
        let _pipe$1 = without(_pipe, toList(["self_id", "counter"]));
        return map_member(_pipe$1, "forwardings", ordered);
      },
    );
  } else if ($ === "or_map") {
    return map_member(
      value,
      "state",
      (state) => {
        let _pipe = state;
        let _pipe$1 = without(_pipe, toList(["replica_id", "clock"]));
        let _pipe$2 = map_member(_pipe$1, "spec", inner);
        return map_member(
          _pipe$2,
          "entries",
          (entries) => {
            let _pipe$3 = entries;
            let _pipe$4 = map_each(
              _pipe$3,
              (entry) => {
                let _pipe$4 = entry;
                let _pipe$5 = map_member(_pipe$4, "membership", inner);
                return map_member(_pipe$5, "value", inner);
              },
            );
            return ordered_by_member(_pipe$4, "key");
          },
        );
      },
    );
  } else {
    return value;
  }
}

function parse_value(raw) {
  let _pipe = $json.parse(raw, $json_ot.decoder());
  return $result.unwrap(_pipe, new $json_ot.VString(raw));
}

function projected(snapshot) {
  let _pipe = $channel.encode_snapshot(snapshot);
  let _pipe$1 = $json.to_string(_pipe);
  let _pipe$2 = parse_value(_pipe$1);
  return merge_relevant(_pipe$2);
}

/**
 * This function builds the entry, and `crdt_wire.encode_descriptor` does not.
 * The digest is a projection of the state, and not a wire message. A new name
 * for an envelope field must not change it.
 * 
 * @ignore
 */
function digest_entry(entry) {
  let $ = entry.descriptor;
  let address = $.address;
  let channel_type$1 = $.channel_type;
  let created_by = $.created_by;
  return new $json_ot.VObject(
    toList([
      [
        "descriptor",
        new $json_ot.VObject(
          toList([
            ["address", new $json_ot.VString(address)],
            [
              "channelType",
              new $json_ot.VString($channel.type_to_string(channel_type$1)),
            ],
            ["createdBy", new $json_ot.VString(created_by)],
          ]),
        ),
      ],
      ["state", projected(entry.snapshot)],
    ]),
  );
}

/**
 * The digest projection: `canonical_json`, with the state of each channel
 * reduced to the part that two replicas with the same logical state *and* the
 * same causal state must agree on.
 *
 * The function removes the authoring cursors of each replica only. Those are
 * the id that the replica stamps its own writes with, and the counter that it
 * stamps them from. The causal metadata, the tombstones, the pruning vectors,
 * the version vectors, the remove bounds, and the LWW timestamps with their
 * replica-id tie-break all stay. This is thus a comparison of state, and not
 * of values. A peer that has seen a removal that its neighbour has not seen
 * fails the comparison, and it receives a repair.
 *
 * The bytes come from `canonical_json`, and not from `gleam/json`. The object
 * keys go out in UTF-8 byte order, a set-shaped array is ordered by the
 * canonical bytes of its elements, and every number has one form. Neither the
 * iteration order of a dictionary nor the compile target can thus move one
 * byte.
 */
export function digest_canonical_json(document) {
  return $canonical_json.to_string(
    new $json_ot.VObject(
      toList([
        [
          "v",
          new $json_ot.VNumber(new $json_ot.NInt($crdt_wire.protocol_version)),
        ],
        ["room", new $json_ot.VString(document.config.room)],
        ["compatibility", new $json_ot.VString(document.config.compatibility)],
        [
          "root",
          new $json_ot.VString($channel.type_to_string(root_type(document))),
        ],
        [
          "channels",
          new $json_ot.VArray($list.map(entries(document), digest_entry)),
        ],
      ]),
    ),
  );
}

/**
 * The SHA-256 of `digest_canonical_json`, as lowercase hex. Two replicas that
 * reached the same state, through any delivery order and on either compile
 * target, get the same value.
 */
export function digest(document) {
  return $sha256.hex(digest_canonical_json(document));
}

export function digest_message(document) {
  return new $crdt_wire.Digest(digest(document));
}

export function rejection_message(reason, detail) {
  return new $crdt_wire.Rejected(reason, detail);
}

/**
 * Put an outbound message in the addressing of this document.
 */
export function envelope(document, message) {
  return new $crdt_wire.Envelope(
    document.config.room,
    document.config.replica,
    document.config.session,
    message,
  );
}

export function encode(document, message) {
  return $crdt_wire.envelope_to_string(envelope(document, message));
}

function check_capacity(document) {
  let $ = $dict.size(document.registry) >= document.config.limits.channels;
  if ($) {
    return new Error(
      rejected(
        document.config.replica,
        ("document already holds its limit of " + $int.to_string(
          document.config.limits.channels,
        )) + " channels",
      ),
    );
  } else {
    return new Ok(undefined);
  }
}

/**
 * Register a new channel under an address that comes from the identity of
 * this replica, and thus cannot collide. Then announce that channel.
 */
export function create_channel(document, init) {
  return $result.try$(
    $p2p.validate_create(init),
    (init) => {
      return $result.try$(
        check_capacity(document),
        (_) => {
          let counter = document.counter + 1;
          let address = $crdt_wire.channel_address(
            document.config.replica,
            counter,
          );
          let descriptor$1 = new ChannelDescriptor(
            address,
            $channel.init_type(init),
            document.config.replica,
          );
          let state = $channel.new$(init, document.config.replica);
          let document$1 = new Document(
            document.config,
            counter,
            $dict.insert(document.registry, address, descriptor$1),
            $dict.insert(document.states, address, state),
            document.buffered,
            document.recent,
          );
          let announce = new $crdt_wire.ChannelAnnounce(
            new ChannelEntry(descriptor$1, $channel.snapshot(state)),
          );
          return new Ok(
            [
              document$1,
              new Outcome(
                toList([announce]),
                $List$Empty$const,
                toList([descriptor$1]),
                $List$Empty$const,
              ),
            ],
          );
        },
      );
    },
  );
}

function tag(address, events) {
  return $list.map(events, (event) => { return [address, event]; });
}

function evict(loop$recent, loop$limit) {
  while (true) {
    let recent = loop$recent;
    let limit = loop$limit;
    let $ = $dict.size(recent.seen) > limit;
    if ($) {
      let $1 = fifo_pop(recent.queue);
      if ($1 instanceof Ok) {
        let oldest = $1[0][0];
        let queue = $1[0][1];
        loop$recent = new Recent($dict.delete$(recent.seen, oldest), queue);
        loop$limit = limit;
      } else {
        return recent;
      }
    } else {
      return recent;
    }
  }
}

/**
 * Record an accepted message id, and remove the oldest id when the window is
 * full. An id that is already in the window does not enter the queue a second
 * time. The dictionary and the FIFO thus hold exactly the same set.
 * 
 * @ignore
 */
function remember(document, id) {
  let limit = document.config.limits.recent_message_ids;
  let recent = document.recent;
  let $ = limit <= 0;
  let $1 = $dict.has_key(recent.seen, id);
  if ($) {
    return empty_recent();
  } else if ($1) {
    return recent;
  } else {
    let _pipe = new Recent(
      $dict.insert(recent.seen, id, undefined),
      fifo_push(recent.queue, id),
    );
    return evict(_pipe, limit);
  }
}

function channel_error_detail(error) {
  if (error instanceof $channel.UnexpectedAck) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $channel.WrongChannelType) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $channel.CorruptRemoteOperation) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $channel.OrMapOperationFailed) {
    let detail = error.detail;
    return detail;
  } else {
    let detail = error.detail;
    return detail;
  }
}

/**
 * Write a local edit. The function merges it into the confirmed state and the
 * visible state in one ack-free transition, and it returns the delta to
 * broadcast.
 */
export function edit(document, address, edit) {
  return $result.try$(
    descriptor(document, address),
    (descriptor) => {
      return $result.try$(
        channel_state(document, address),
        (state) => {
          let $ = $channel.apply_p2p_local(state, edit);
          if ($ instanceof Ok) {
            let state$1 = $[0][0];
            let events = $[0][1];
            let operation = $[0][2];
            let counter = document.counter + 1;
            let id = new MessageId(document.config.replica, counter);
            let document$1 = new Document(
              document.config,
              counter,
              document.registry,
              $dict.insert(document.states, address, state$1),
              document.buffered,
              remember(document, id),
            );
            return new Ok(
              [
                document$1,
                new Outcome(
                  toList([
                    new $crdt_wire.Delta(
                      id,
                      address,
                      descriptor.channel_type,
                      operation,
                    ),
                  ]),
                  $List$Empty$const,
                  $List$Empty$const,
                  tag(address, events),
                ),
              ],
            );
          } else {
            let error = $[0];
            return new Error(
              rejected(document.config.replica, channel_error_detail(error)),
            );
          }
        },
      );
    },
  );
}

function combine(left, right) {
  return new Outcome(
    $list.append(left.broadcast, right.broadcast),
    $list.append(left.reply, right.reply),
    $list.append(left.created, right.created),
    $list.append(left.events, right.events),
  );
}

function merge_operation(document, from, address, operation) {
  return $result.try$(
    channel_state(document, address),
    (state) => {
      let $ = $channel.apply_p2p_remote(state, operation);
      if ($ instanceof Ok) {
        let state$1 = $[0][0];
        let events = $[0][1];
        return new Ok(
          [
            new Document(
              document.config,
              document.counter,
              document.registry,
              $dict.insert(document.states, address, state$1),
              document.buffered,
              document.recent,
            ),
            tag(address, events),
          ],
        );
      } else {
        let error = $[0];
        return new Error(rejected(from, channel_error_detail(error)));
      }
    },
  );
}

/**
 * Apply the deltas that waited on this address, oldest first, and keep only
 * the deltas that can belong to the channel that arrived.
 *
 * To partition on the address alone permitted a denial of service. A forged
 * delta or a stale delta can name an address with no announcement, under the
 * wrong channel type. To merge such a delta into the announced kernel fails.
 * An announcement accepts all of its entries or none of them, so that failure
 * refused the correct `channel` message *and* kept the bad delta in the
 * buffer. Every later announcement and every later `state` transfer that
 * touched that address then failed in the same way, without an end.
 *
 * The module can never apply a buffered delta whose declared type disagrees
 * with the descriptor, so it discards that delta. It also drops a delta that
 * still fails to merge, and it does not forward that delta. The module
 * accepted the delta from a peer that is not the announcer, before it knew the
 * channel, and such a delta must not be able to invalidate the
 * announcement.
 * 
 * @ignore
 */
function flush_buffered(document, from, address, channel_type) {
  let $ = $list.partition(
    fifo_to_list(document.buffered),
    (buffered) => { return buffered.address === address; },
  );
  let ready = $[0];
  let rest = $[1];
  let document$1 = new Document(
    document.config,
    document.counter,
    document.registry,
    document.states,
    fifo_from_list(rest),
    document.recent,
  );
  let _pipe = $list.filter(
    ready,
    (buffered) => { return isEqual(buffered.channel_type, channel_type); },
  );
  return $list.fold(
    _pipe,
    [document$1, $List$Empty$const],
    (acc, buffered) => {
      let document$2 = acc[0];
      let events = acc[1];
      let $1 = merge_operation(document$2, from, address, buffered.operation);
      if ($1 instanceof Ok) {
        let document$3 = $1[0][0];
        let next = $1[0][1];
        return [
          new Document(
            document$3.config,
            document$3.counter,
            document$3.registry,
            document$3.states,
            document$3.buffered,
            remember(document$3, buffered.id),
          ),
          $list.append(events, next),
        ];
      } else {
        return acc;
      }
    },
  );
}

function merge_snapshot(document, from, address, state, snapshot) {
  let $ = $channel.merge_p2p_snapshot(state, snapshot);
  if ($ instanceof Ok) {
    let state$1 = $[0][0];
    let events = $[0][1];
    return new Ok(
      [
        new Document(
          document.config,
          document.counter,
          document.registry,
          $dict.insert(document.states, address, state$1),
          document.buffered,
          document.recent,
        ),
        tag(address, events),
      ],
    );
  } else {
    let error = $[0];
    return new Error(rejected(from, channel_error_detail(error)));
  }
}

/**
 * The initializer that builds an empty channel that can receive this snapshot.
 * An OR-map carries its value mode in the snapshot, so a merge can refuse a
 * mode mismatch, and it does not load the data into the wrong kernel.
 * 
 * @ignore
 */
function init_for(snapshot) {
  if (snapshot instanceof $channel.MapSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.CounterSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.PnCounterSnapshot) {
    return new Ok($channel.ChannelInit$InitPnCounter$const);
  } else if (snapshot instanceof $channel.GCounterSnapshot) {
    return new Ok($channel.ChannelInit$InitGCounter$const);
  } else if (snapshot instanceof $channel.LwwRegisterSnapshot) {
    return new Ok($channel.ChannelInit$InitLwwRegister$const);
  } else if (snapshot instanceof $channel.LwwMapSnapshot) {
    return new Ok($channel.ChannelInit$InitLwwMap$const);
  } else if (snapshot instanceof $channel.MvRegisterSnapshot) {
    return new Ok($channel.ChannelInit$InitMvRegister$const);
  } else if (snapshot instanceof $channel.OrMapSnapshot) {
    let mode = snapshot.mode;
    return new Ok(new $channel.InitOrMap(mode));
  } else if (snapshot instanceof $channel.OrSetSnapshot) {
    return new Ok($channel.ChannelInit$InitOrSet$const);
  } else if (snapshot instanceof $channel.GSetSnapshot) {
    return new Ok($channel.ChannelInit$InitGSet$const);
  } else if (snapshot instanceof $channel.TwoPSetSnapshot) {
    return new Ok($channel.ChannelInit$InitTwoPSet$const);
  } else if (snapshot instanceof $channel.RegisterCollectionSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.ClaimsSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.TaskManagerSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.PactMapSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.JsonOtSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.DirectorySnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.OrderedCollectionSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else if (snapshot instanceof $channel.SequenceSummary) {
    return new Ok($channel.ChannelInit$InitSequence$const);
  } else if (snapshot instanceof $channel.RichTextSnapshot) {
    return new Error(
      new $p2p.UnsupportedChannel($channel.snapshot_type(snapshot)),
    );
  } else {
    return new Ok($channel.ChannelInit$InitText$const);
  }
}

function check_address(address, from) {
  let _pipe = $crdt_wire.address_creator(address);
  return $result.replace_error(
    _pipe,
    rejected(from, "invalid channel address " + address),
  );
}

function merge_entry(document, from, entry) {
  let descriptor$1 = entry.descriptor;
  return $result.try$(
    check_address(descriptor$1.address, from),
    (creator) => {
      return $result.try$(
        (() => {
          let $ = creator === descriptor$1.created_by;
          if ($) {
            return new Ok(undefined);
          } else {
            return new Error(
              rejected(
                from,
                (((("channel " + descriptor$1.address) + " claims creator ") + descriptor$1.created_by) + " but its address names ") + creator,
              ),
            );
          }
        })(),
        (_) => {
          return $result.try$(
            $p2p.validate(descriptor$1.channel_type),
            (_) => {
              return $result.try$(
                (() => {
                  let $ = isEqual(
                    $channel.snapshot_type(entry.snapshot),
                    descriptor$1.channel_type
                  );
                  if ($) {
                    return new Ok(undefined);
                  } else {
                    return new Error(
                      rejected(
                        from,
                        (((("snapshot for " + descriptor$1.address) + " is a ") + $channel.type_to_string(
                          $channel.snapshot_type(entry.snapshot),
                        )) + " but the descriptor declares ") + $channel.type_to_string(
                          descriptor$1.channel_type,
                        ),
                      ),
                    );
                  }
                })(),
                (_) => {
                  let $ = $dict.get(document.registry, descriptor$1.address);
                  if ($ instanceof Ok) {
                    let existing = $[0];
                    if (!isEqual(existing, descriptor$1)) {
                      let $1 = descriptor$1.address === $crdt_wire.root_address;
                      if ($1) {
                        return new Error(
                          new $p2p.RootMismatch(
                            existing.channel_type,
                            descriptor$1.channel_type,
                          ),
                        );
                      } else {
                        return new Error(
                          rejected(
                            from,
                            (((("channel " + descriptor$1.address) + " is already registered as ") + $channel.type_to_string(
                              existing.channel_type,
                            )) + " created by ") + existing.created_by,
                          ),
                        );
                      }
                    } else {
                      return $result.try$(
                        channel_state(document, descriptor$1.address),
                        (state) => {
                          return $result.try$(
                            merge_snapshot(
                              document,
                              from,
                              descriptor$1.address,
                              state,
                              entry.snapshot,
                            ),
                            (_use0) => {
                              let document$1 = _use0[0];
                              let events = _use0[1];
                              return new Ok(
                                [
                                  document$1,
                                  new Outcome(
                                    $List$Empty$const,
                                    $List$Empty$const,
                                    $List$Empty$const,
                                    events,
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    }
                  } else {
                    return $result.try$(
                      check_capacity(document),
                      (_) => {
                        return $result.try$(
                          init_for(entry.snapshot),
                          (init) => {
                            let state = $channel.new$(
                              init,
                              document.config.replica,
                            );
                            return $result.try$(
                              merge_snapshot(
                                document,
                                from,
                                descriptor$1.address,
                                state,
                                entry.snapshot,
                              ),
                              (_use0) => {
                                let document$1 = _use0[0];
                                let events = _use0[1];
                                let document$2 = new Document(
                                  document$1.config,
                                  document$1.counter,
                                  $dict.insert(
                                    document$1.registry,
                                    descriptor$1.address,
                                    descriptor$1,
                                  ),
                                  document$1.states,
                                  document$1.buffered,
                                  document$1.recent,
                                );
                                let $1 = flush_buffered(
                                  document$2,
                                  from,
                                  descriptor$1.address,
                                  descriptor$1.channel_type,
                                );
                                let document$3 = $1[0];
                                let buffered = $1[1];
                                return new Ok(
                                  [
                                    document$3,
                                    new Outcome(
                                      $List$Empty$const,
                                      $List$Empty$const,
                                      toList([descriptor$1]),
                                      $list.append(events, buffered),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  }
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
 * Merge the channels of an announcement or a transfer. The function accepts
 * all of them or none of them. One bad entry refuses the whole message. Every
 * intermediate document is a new value, so the caller keeps the document that
 * it started with.
 * 
 * @ignore
 */
function merge_entries(document, from, entries) {
  return $list.try_fold(
    entries,
    [document, empty_outcome()],
    (acc, entry) => {
      let document$1 = acc[0];
      let outcome = acc[1];
      return $result.try$(
        merge_entry(document$1, from, entry),
        (_use0) => {
          let document$2 = _use0[0];
          let next = _use0[1];
          return new Ok([document$2, combine(outcome, next)]);
        },
      );
    },
  );
}

/**
 * Queue a delta whose channel has no announcement yet.
 *
 * The buffer is a bounded FIFO. When it is full it removes its *oldest*
 * entry, and it does not refuse the newest one. To refuse the newest entry
 * caused a permanent failure. An orphan delta names a channel that no peer
 * ever announces, because the address is forged, or because the peer left
 * before it announced. Such a delta holds its slot forever, so a full buffer
 * would refuse every valid later delta for the rest of the life of the
 * document. To remove the oldest entry limits the same memory without that
 * failure, and it costs nothing in correctness. A delta that the buffer
 * removes is one whose descriptor never arrived, and every peer that still
 * holds that channel carries the same edit in its next `state` transfer.
 *
 * This function does *not* record the message id, and that is deliberate. The
 * module records the id when it applies the delta. A delta that the buffer
 * removed, or that the flush discarded, is thus not suppressed as a duplicate
 * when the sender sends it again after it announces the channel.
 * 
 * @ignore
 */
function buffer_delta(document, id, address, channel_type, operation) {
  let limit = document.config.limits.buffered_deltas;
  let $ = limit <= 0;
  if ($) {
    return [document, empty_outcome()];
  } else {
    let queued = fifo_push(
      document.buffered,
      new BufferedDelta(id, address, channel_type, operation),
    );
    let _block;
    let $1 = queued.size > limit;
    if ($1) {
      let $2 = fifo_pop(queued);
      if ($2 instanceof Ok) {
        let rest = $2[0][1];
        _block = rest;
      } else {
        _block = queued;
      }
    } else {
      _block = queued;
    }
    let buffered = _block;
    return [
      new Document(
        document.config,
        document.counter,
        document.registry,
        document.states,
        buffered,
        document.recent,
      ),
      empty_outcome(),
    ];
  }
}

function apply_delta(document, from, id, address, channel_type, operation) {
  return $result.try$(
    check_address(address, from),
    (_) => {
      return $result.try$(
        $p2p.validate(channel_type),
        (_) => {
          let $ = seen(document, id);
          if ($) {
            return new Ok([document, empty_outcome()]);
          } else {
            let $1 = $dict.get(document.registry, address);
            if ($1 instanceof Ok) {
              let descriptor$1 = $1[0];
              let $2 = isEqual(descriptor$1.channel_type, channel_type);
              if ($2) {
                return $result.try$(
                  merge_operation(document, from, address, operation),
                  (_use0) => {
                    let document$1 = _use0[0];
                    let events = _use0[1];
                    return new Ok(
                      [
                        new Document(
                          document$1.config,
                          document$1.counter,
                          document$1.registry,
                          document$1.states,
                          document$1.buffered,
                          remember(document$1, id),
                        ),
                        new Outcome(
                          $List$Empty$const,
                          $List$Empty$const,
                          $List$Empty$const,
                          events,
                        ),
                      ],
                    );
                  },
                );
              } else {
                return new Error(
                  rejected(
                    from,
                    (((("delta declares " + $channel.type_to_string(
                      channel_type,
                    )) + " but ") + address) + " is registered as ") + $channel.type_to_string(
                      descriptor$1.channel_type,
                    ),
                  ),
                );
              }
            } else {
              return new Ok(
                buffer_delta(document, id, address, channel_type, operation),
              );
            }
          }
        },
      );
    },
  );
}

function apply_message(document, from, message, local) {
  if (message instanceof $crdt_wire.Hello) {
    let compatibility$1 = message.compatibility;
    let root = message.root;
    return $result.try$(
      (() => {
        let $ = compatibility$1 === document.config.compatibility;
        if ($) {
          return new Ok(undefined);
        } else {
          return new Error(
            new $p2p.CompatibilityMismatch(
              document.config.compatibility,
              compatibility$1,
            ),
          );
        }
      })(),
      (_) => {
        return $result.try$(
          (() => {
            let $ = isEqual(root, root_type(document));
            if ($) {
              return new Ok(undefined);
            } else {
              return new Error(new $p2p.RootMismatch(root_type(document), root));
            }
          })(),
          (_) => { return new Ok([document, empty_outcome()]); },
        );
      },
    );
  } else if (message instanceof $crdt_wire.ChannelAnnounce) {
    let entry = message.entry;
    return merge_entries(document, from, toList([entry]));
  } else if (message instanceof $crdt_wire.Delta) {
    let id = message.id;
    let address = message.address;
    let channel_type$1 = message.channel_type;
    let operation = message.operation;
    return apply_delta(document, from, id, address, channel_type$1, operation);
  } else if (message instanceof $crdt_wire.StateRequest) {
    return new Ok(
      [
        document,
        new Outcome(
          $List$Empty$const,
          toList([state_message(document)]),
          $List$Empty$const,
          $List$Empty$const,
        ),
      ],
    );
  } else if (message instanceof $crdt_wire.State) {
    let entries$1 = message.entries;
    return merge_entries(document, from, entries$1);
  } else if (message instanceof $crdt_wire.Digest) {
    let remote = message.digest;
    let $ = remote === $option.lazy_unwrap(
      local,
      () => { return digest(document); },
    );
    if ($) {
      return new Ok([document, empty_outcome()]);
    } else {
      return new Ok(
        [
          document,
          new Outcome(
            $List$Empty$const,
            toList([$crdt_wire.Message$StateRequest$const]),
            $List$Empty$const,
            $List$Empty$const,
          ),
        ],
      );
    }
  } else {
    return new Ok([document, empty_outcome()]);
  }
}

function received(document, envelope, local) {
  return $result.try$(
    (() => {
      let $ = envelope.room === document.config.room;
      if ($) {
        return new Ok(undefined);
      } else {
        return new Error($p2p.P2pError$RoomMismatch$const);
      }
    })(),
    (_) => {
      let $ = envelope.from === document.config.replica;
      let $1 = envelope.session === document.config.session;
      if ($) {
        if ($1) {
          return new Ok([document, empty_outcome()]);
        } else {
          return new Error(new $p2p.ReplicaCollision(envelope.from));
        }
      } else {
        return apply_message(document, envelope.from, envelope.message, local);
      }
    },
  );
}

/**
 * Apply one envelope. A caller that builds an `Envelope` value directly, such
 * as a relay that replays its own log, or a test, gets the same checks as an
 * envelope from the wire. This function checks the descriptors and the channel
 * types again. It does not assume that the decoder ran.
 *
 * The message id of a delta does not have to name the sender, and that is
 * deliberate. A mesh peer and a relay both forward a delta that they did not
 * write. The id identifies the message of the *author*, so the duplicate
 * suppression still works after a message takes two routes.
 */
export function receive(document, envelope) {
  return received(document, envelope, Option$None$const);
}

/**
 * Decode and apply one encoded envelope. The size check, the protocol check,
 * and the shape check all run before the function changes any state.
 */
export function receive_encoded(document, raw) {
  return $result.try$(
    $crdt_wire.decode_envelope(raw, document.config.limits),
    (envelope) => { return receive(document, envelope); },
  );
}

/**
 * `receive`, with the canonical digest that this document already has.
 *
 * `Digest` is the one message whose handler reads the local digest. To compute
 * that digest, the module canonicalizes and hashes the whole document. A
 * transport with a heartbeat sends a message every 250 ms, to every peer, in
 * both directions. It thus pays that cost for each message, also for a
 * document that did not change. A caller that holds a digest cache gives it to
 * this function. Every other message goes to `receive`, and no code computes
 * the digest at all.
 *
 * `local` must be `digest(document)` for *this* document. A stale value would
 * answer an anti-entropy comparison against a state that this replica no
 * longer holds. It would thus suppress a repair that the replica owes, or ask
 * for a repair that it does not need. A cache that supplies this value must
 * thus use the document itself as its key. Do not invalidate that cache by
 * hand.
 */
export function receive_with_digest(document, envelope, local) {
  return received(document, envelope, new Some(local));
}

function eligible_type(raw, from) {
  let $ = $channel.string_to_type(raw);
  if ($ instanceof Ok) {
    let channel_type$1 = $[0];
    return $p2p.validate(channel_type$1);
  } else {
    return new Error(rejected(from, "unknown channel type " + raw));
  }
}

function canonical_decoder() {
  return $decode.field(
    "v",
    $decode.int,
    (version) => {
      return $decode.field(
        "room",
        $decode.string,
        (room) => {
          return $decode.field(
            "compatibility",
            $decode.string,
            (compatibility) => {
              return $decode.field(
                "root",
                $decode.string,
                (root) => {
                  return $decode.field(
                    "channels",
                    $decode.list($wire.json_value_decoder()),
                    (channels) => {
                      return $decode.success(
                        new CanonicalSnapshot(
                          version,
                          room,
                          compatibility,
                          root,
                          channels,
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

/**
 * Refuse an oversize snapshot by its byte length, before the module parses it.
 * A caller that gives the module a hostile file must not be able to run the
 * parser on that file first. `decode_envelope` puts the same check in front of
 * an envelope.
 * 
 * @ignore
 */
function check_snapshot_size(document, raw) {
  let bytes = $bit_array.byte_size(toBitArray([stringBits(raw)]));
  let limit = document.config.limits.snapshot_bytes;
  let $ = bytes > limit;
  if ($) {
    return new Error(new $p2p.SnapshotTooLarge(bytes, limit));
  } else {
    return new Ok(undefined);
  }
}

/**
 * Merge an exported snapshot back into the document. The function checks the
 * size, the room, the protocol, the compatibility, and the root, before it
 * touches one channel. The merge is a join, so the local channels and the
 * local edits all stay.
 */
export function import_snapshot(document, raw) {
  return $result.try$(
    check_snapshot_size(document, raw),
    (_) => {
      let from = document.config.replica;
      return $result.try$(
        (() => {
          let _pipe = $json.parse(raw, canonical_decoder());
          return $result.replace_error(
            _pipe,
            rejected(from, "malformed canonical snapshot"),
          );
        })(),
        (snapshot) => {
          let version = snapshot.version;
          let room$1 = snapshot.room;
          let compatibility$1 = snapshot.compatibility;
          let root = snapshot.root;
          let channels = snapshot.channels;
          return $result.try$(
            (() => {
              let $ = version === $crdt_wire.protocol_version;
              if ($) {
                return new Ok(undefined);
              } else {
                return new Error(
                  new $p2p.ProtocolMismatch(
                    $crdt_wire.protocol_version,
                    version,
                  ),
                );
              }
            })(),
            (_) => {
              return $result.try$(
                (() => {
                  let $ = room$1 === document.config.room;
                  if ($) {
                    return new Ok(undefined);
                  } else {
                    return new Error($p2p.P2pError$RoomMismatch$const);
                  }
                })(),
                (_) => {
                  return $result.try$(
                    (() => {
                      let $ = compatibility$1 === document.config.compatibility;
                      if ($) {
                        return new Ok(undefined);
                      } else {
                        return new Error(
                          new $p2p.CompatibilityMismatch(
                            document.config.compatibility,
                            compatibility$1,
                          ),
                        );
                      }
                    })(),
                    (_) => {
                      return $result.try$(
                        eligible_type(root, from),
                        (root) => {
                          return $result.try$(
                            (() => {
                              let $ = isEqual(root, root_type(document));
                              if ($) {
                                return new Ok(undefined);
                              } else {
                                return new Error(
                                  new $p2p.RootMismatch(
                                    root_type(document),
                                    root,
                                  ),
                                );
                              }
                            })(),
                            (_) => {
                              return $result.try$(
                                $list.try_map(
                                  channels,
                                  (entry) => {
                                    return $crdt_wire.decode_channel_entry(
                                      entry,
                                      from,
                                      document.config.limits,
                                    );
                                  },
                                ),
                                (entries) => {
                                  return merge_entries(document, from, entries);
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

/// <reference types="./presence.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  remainderInt,
  isEqual,
} from "../gleam.mjs";
import * as $wire from "../watershed/wire.mjs";

export class Auto extends $CustomType {}
export const Mode$Auto$const = new Auto();
export const Mode$Auto = () => Mode$Auto$const;
export const Mode$isAuto = (value) => value instanceof Auto;

export class Server extends $CustomType {}
export const Mode$Server$const = new Server();
export const Mode$Server = () => Mode$Server$const;
export const Mode$isServer = (value) => value instanceof Server;

export class Ripple extends $CustomType {}
export const Mode$Ripple$const = new Ripple();
export const Mode$Ripple = () => Mode$Ripple$const;
export const Mode$isRipple = (value) => value instanceof Ripple;

class Config extends $CustomType {
  constructor(encode, decode, mode, heartbeat_milliseconds, ttl_milliseconds) {
    super();
    this.encode = encode;
    this.decode = decode;
    this.mode = mode;
    this.heartbeat_milliseconds = heartbeat_milliseconds;
    this.ttl_milliseconds = ttl_milliseconds;
  }
}

export class PresenceEntry extends $CustomType {
  constructor(session_id, key, meta) {
    super();
    this.session_id = session_id;
    this.key = key;
    this.meta = meta;
  }
}
export const PresenceEntry$PresenceEntry = (session_id, key, meta) =>
  new PresenceEntry(session_id, key, meta);
export const PresenceEntry$isPresenceEntry = (value) =>
  value instanceof PresenceEntry;
export const PresenceEntry$PresenceEntry$session_id = (value) =>
  value.session_id;
export const PresenceEntry$PresenceEntry$0 = (value) => value.session_id;
export const PresenceEntry$PresenceEntry$key = (value) => value.key;
export const PresenceEntry$PresenceEntry$1 = (value) => value.key;
export const PresenceEntry$PresenceEntry$meta = (value) => value.meta;
export const PresenceEntry$PresenceEntry$2 = (value) => value.meta;

class Tracked extends $CustomType {
  constructor(phx_ref, session_id, key, meta) {
    super();
    this.phx_ref = phx_ref;
    this.session_id = session_id;
    this.key = key;
    this.meta = meta;
  }
}

export class Dropped extends $CustomType {
  constructor(key, session_id) {
    super();
    this.key = key;
    this.session_id = session_id;
  }
}
export const Dropped$Dropped = (key, session_id) =>
  new Dropped(key, session_id);
export const Dropped$isDropped = (value) => value instanceof Dropped;
export const Dropped$Dropped$key = (value) => value.key;
export const Dropped$Dropped$0 = (value) => value.key;
export const Dropped$Dropped$session_id = (value) => value.session_id;
export const Dropped$Dropped$1 = (value) => value.session_id;

class Diff extends $CustomType {
  constructor(joins, leaves, dropped) {
    super();
    this.joins = joins;
    this.leaves = leaves;
    this.dropped = dropped;
  }
}

class Snapshot extends $CustomType {
  constructor(entries, dropped) {
    super();
    this.entries = entries;
    this.dropped = dropped;
  }
}

export class State extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}
export const Event$State = (entries) => new State(entries);
export const Event$isState = (value) => value instanceof State;
export const Event$State$entries = (value) => value.entries;
export const Event$State$0 = (value) => value.entries;

export class Changed extends $CustomType {
  constructor(diff, entries) {
    super();
    this.diff = diff;
    this.entries = entries;
  }
}
export const Event$Changed = (diff, entries) => new Changed(diff, entries);
export const Event$isChanged = (value) => value instanceof Changed;
export const Event$Changed$diff = (value) => value.diff;
export const Event$Changed$0 = (value) => value.diff;
export const Event$Changed$entries = (value) => value.entries;
export const Event$Changed$1 = (value) => value.entries;

export class Failed extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const Event$Failed = (error) => new Failed(error);
export const Event$isFailed = (value) => value instanceof Failed;
export const Event$Failed$error = (value) => value.error;
export const Event$Failed$0 = (value) => value.error;

/**
 * The application forced `Mode.Server` against a server that does not
 * announce `presence_v1`.
 */
export class UnsupportedPresence extends $CustomType {}
export const PresenceError$UnsupportedPresence$const =
  new UnsupportedPresence();
export const PresenceError$UnsupportedPresence = () =>
  PresenceError$UnsupportedPresence$const;
export const PresenceError$isUnsupportedPresence = (value) =>
  value instanceof UnsupportedPresence;

/**
 * The server rejected a presence command.
 */
export class Rejected extends $CustomType {
  constructor(code, message) {
    super();
    this.code = code;
    this.message = message;
  }
}
export const PresenceError$Rejected = (code, message) =>
  new Rejected(code, message);
export const PresenceError$isRejected = (value) => value instanceof Rejected;
export const PresenceError$Rejected$code = (value) => value.code;
export const PresenceError$Rejected$0 = (value) => value.code;
export const PresenceError$Rejected$message = (value) => value.message;
export const PresenceError$Rejected$1 = (value) => value.message;

/**
 * The metadata of one peer failed the decoder of the application. This
 * module dropped that entry and kept the rest of the roster.
 */
export class DecodeFailed extends $CustomType {
  constructor(key, session_id) {
    super();
    this.key = key;
    this.session_id = session_id;
  }
}
export const PresenceError$DecodeFailed = (key, session_id) =>
  new DecodeFailed(key, session_id);
export const PresenceError$isDecodeFailed = (value) =>
  value instanceof DecodeFailed;
export const PresenceError$DecodeFailed$key = (value) => value.key;
export const PresenceError$DecodeFailed$0 = (value) => value.key;
export const PresenceError$DecodeFailed$session_id = (value) =>
  value.session_id;
export const PresenceError$DecodeFailed$1 = (value) => value.session_id;

class Tracker extends $CustomType {
  constructor(entries, pending) {
    super();
    this.entries = entries;
    this.pending = pending;
  }
}

class Sessions extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}

class Live extends $CustomType {
  constructor(key, meta, last_seen) {
    super();
    this.key = key;
    this.meta = meta;
    this.last_seen = last_seen;
  }
}

/**
 * The meta fields that the server owns. This module removes them before the
 * decoder of the application runs. An application thus never sees them, and it
 * can never claim one.
 */
export const reserved_meta_fields = /* @__PURE__ */ toList([
  "phx_ref",
  "phx_ref_prev",
  "client_id",
]);

/**
 * The `type` tag of the ripple and the `kind` value of the envelope, for every
 * presence broadcast. floodgate removes the `type` field of a ripple on a
 * broadcast, for compatibility with Fluid. This module thus separates the
 * inbound kinds by the `kind` field of the content envelope. It keeps the
 * `type` stamp for compatibility with a later server only. Several uses of
 * ripples in one document work together, because `kind` separates them.
 */
export const ripple_type = "presence";

/**
 * The event names on the presence lane. A command from the client to the
 * server uses camel case, the same as `submitOp` and `submitSignal`. A frame
 * from the server to the client uses snake case, the same as
 * `connect_document_success`. That difference is the existing wire
 * convention. It is not an error in this module.
 */
export const event_join = "joinPresence";

export const event_update = "updatePresence";

export const event_leave = "leavePresence";

export const event_state = "presence_state";

export const event_diff = "presence_diff";

export const event_error = "presence_error";

/**
 * A presence configuration: a codec for the metadata of the application, in
 * `Auto` mode, with the default ripple interval. The client announces itself
 * again every 2 seconds, and it removes a peer after 6.5 seconds, which is
 * about three missed beats.
 */
export function config(encode, decode) {
  return new Config(encode, decode, Mode$Auto$const, 2000, 6500);
}

export function with_mode(config, mode) {
  return new Config(
    config.encode,
    config.decode,
    mode,
    config.heartbeat_milliseconds,
    config.ttl_milliseconds,
  );
}

/**
 * Replace the ripple heartbeat interval and the liveness window. Server mode
 * ignores both values. It has no heartbeat in the browser at all, because the
 * connection *is* the liveness signal.
 */
export function with_ripple_timing(
  config,
  heartbeat_milliseconds,
  ttl_milliseconds
) {
  return new Config(
    config.encode,
    config.decode,
    config.mode,
    heartbeat_milliseconds,
    ttl_milliseconds,
  );
}

export function config_mode(config) {
  return config.mode;
}

export function config_encode(config) {
  return config.encode;
}

export function config_decoder(config) {
  return config.decode;
}

export function config_heartbeat_milliseconds(config) {
  return config.heartbeat_milliseconds;
}

export function config_ttl_milliseconds(config) {
  return config.ttl_milliseconds;
}

/**
 * Convert the tracked sessions into the public entry list. The function
 * removes `phx_ref`, and it sorts by key and then by session id, so every
 * render uses the same stable order.
 * 
 * @ignore
 */
function public_entries(tracked) {
  let _pipe = tracked;
  let _pipe$1 = $list.map(
    _pipe,
    (one) => { return new PresenceEntry(one.session_id, one.key, one.meta); },
  );
  return $list.sort(
    _pipe$1,
    (left, right) => {
      let $ = $string.compare(left.key, right.key);
      if ($ instanceof $order.Lt) {
        return $;
      } else if ($ instanceof $order.Eq) {
        return $string.compare(left.session_id, right.session_id);
      } else {
        return $;
      }
    },
  );
}

/**
 * The sessions that joined in this change.
 */
export function diff_joins(diff) {
  return public_entries(diff.joins);
}

/**
 * The sessions that left in this change.
 */
export function diff_leaves(diff) {
  return public_entries(diff.leaves);
}

/**
 * Whether this change moves nothing. A ripple heartbeat alone produces such a
 * change.
 */
export function diff_is_empty(diff) {
  return (diff.joins instanceof $Empty) && (diff.leaves instanceof $Empty);
}

/**
 * Every session that is registered under one presence key, which is the set
 * of tabs of one user.
 */
export function by_key(entries, key) {
  return $list.filter(entries, (entry) => { return entry.key === key; });
}

/**
 * Every session except this client. The presence state contains the local
 * session, because a server snapshot and a Phoenix diff both carry it. An
 * interface that renders the peers only thus removes it with this function.
 */
export function remote_entries(entries, local_session) {
  return $list.filter(
    entries,
    (entry) => { return entry.session_id !== local_session; },
  );
}

/**
 * A tracker that waits for its first snapshot.
 */
export function tracker() {
  return new Tracker(Option$None$const, $List$Empty$const);
}

/**
 * Remove everything, including the queued diffs. The function emits no event.
 * A report of an empty roster on every short socket failure would clear the
 * interface for an interval that the next snapshot closes in milliseconds.
 */
export function reset(_) {
  return tracker();
}

/**
 * Whether the tracker has applied an initial snapshot.
 */
export function is_synced(tracker) {
  return !(tracker.entries instanceof None);
}

/**
 * The current roster, sorted by key then session id.
 */
export function tracker_entries(tracker) {
  let $ = tracker.entries;
  if ($ instanceof Some) {
    let entries = $[0];
    return public_entries($dict.values(entries));
  } else {
    return $List$Empty$const;
  }
}

function insert_tracked(entries, tracked) {
  return $list.fold(
    tracked,
    entries,
    (acc, one) => { return $dict.insert(acc, one.phx_ref, one); },
  );
}

function dropped_events(dropped) {
  return $list.map(
    dropped,
    (d) => { return new Failed(new DecodeFailed(d.key, d.session_id)); },
  );
}

/**
 * Apply a change, or queue it when no snapshot has arrived yet.
 *
 * The tracker drops a join for a `phx_ref` that is already present, and a
 * leave for one that is absent. The server can replay a change across a
 * reconnect, and to apply that change two times would count a session two
 * times. A change with nothing left after that filter produces no event.
 */
export function apply_diff(tracker, diff) {
  let $ = tracker.entries;
  if ($ instanceof Some) {
    let entries = $[0];
    let reported = dropped_events(diff.dropped);
    let leaves = $list.filter(
      diff.leaves,
      (t) => { return $dict.has_key(entries, t.phx_ref); },
    );
    let joins = $list.filter(
      diff.joins,
      (t) => { return !$dict.has_key(entries, t.phx_ref); },
    );
    if (leaves instanceof $Empty && joins instanceof $Empty) {
      return [tracker, reported];
    } else {
      let _block;
      let _pipe = entries;
      let _pipe$1 = $dict.drop(
        _pipe,
        $list.map(leaves, (t) => { return t.phx_ref; }),
      );
      _block = insert_tracked(_pipe$1, joins);
      let next = _block;
      let effective = new Diff(joins, leaves, $List$Empty$const);
      return [
        new Tracker(new Some(next), $List$Empty$const),
        $list.append(
          reported,
          toList([new Changed(effective, public_entries($dict.values(next)))]),
        ),
      ];
    }
  } else {
    return [
      new Tracker(
        tracker.entries,
        $list.append(tracker.pending, toList([diff])),
      ),
      $List$Empty$const,
    ];
  }
}

/**
 * Take an initial snapshot, then apply each diff that arrived before it. The
 * tracker ignores a snapshot that arrives while it is already synchronized. A
 * duplicate state is not a resynchronization, and to treat it as one would
 * drop the concurrent diffs.
 */
export function apply_state(tracker, snapshot) {
  let $ = tracker.entries;
  if ($ instanceof Some) {
    return [tracker, $List$Empty$const];
  } else {
    let _block;
    let _pipe = snapshot.entries;
    let _pipe$1 = $list.map(
      _pipe,
      (tracked) => { return [tracked.phx_ref, tracked]; },
    );
    _block = $dict.from_list(_pipe$1);
    let entries = _block;
    let synced = new Tracker(new Some(entries), $List$Empty$const);
    let events = $list.append(
      dropped_events(snapshot.dropped),
      toList([new State(public_entries($dict.values(entries)))]),
    );
    return $list.fold(
      tracker.pending,
      [synced, events],
      (acc, queued) => {
        let current = acc[0];
        let seen = acc[1];
        let $1 = apply_diff(current, queued);
        let next = $1[0];
        let more = $1[1];
        return [next, $list.append(seen, more)];
      },
    );
  }
}

/**
 * An empty ripple roster.
 */
export function sessions() {
  return new Sessions($dict.new$());
}

function empty_diff() {
  return new Diff($List$Empty$const, $List$Empty$const, $List$Empty$const);
}

/**
 * A change that moves nothing. A driver can thus use one code path, whether or
 * not it has something to report.
 */
export function no_change() {
  return empty_diff();
}

/**
 * Record a heartbeat from one session.
 *
 * A session that this module has not seen joins. A repeat of the same metadata
 * moves `last_seen` only and reports nothing, so a heartbeat alone never
 * causes a re-render. Metadata that changed reports a leave and then a join
 * for that session. That is the same shape that server mode produces for an
 * update, and the agreement is deliberate.
 */
export function observe_session(sessions, session_id, key, meta, now) {
  let next = new Sessions(
    $dict.insert(sessions.entries, session_id, new Live(key, meta, now)),
  );
  let joined = new Tracked(session_id, session_id, key, meta);
  let $ = $dict.get(sessions.entries, session_id);
  if ($ instanceof Ok) {
    let previous = $[0];
    let $1 = (previous.key === key) && (isEqual(previous.meta, meta));
    if ($1) {
      return [next, empty_diff()];
    } else {
      return [
        next,
        new Diff(
          toList([joined]),
          toList([
            new Tracked(session_id, session_id, previous.key, previous.meta),
          ]),
          $List$Empty$const,
        ),
      ];
    }
  } else {
    return [
      next,
      new Diff(toList([joined]), $List$Empty$const, $List$Empty$const),
    ];
  }
}

function live_to_tracked(entry) {
  let session_id = entry[0];
  let live = entry[1];
  return new Tracked(session_id, session_id, live.key, live.meta);
}

/**
 * Remove each session whose last heartbeat is older than the time-to-live
 * (TTL). A session exactly at the TTL stays, which is the same boundary as in
 * the old `prune` function.
 */
export function expire_sessions(sessions, ttl_milliseconds, now) {
  let _block;
  let _pipe = sessions.entries;
  let _pipe$1 = $dict.to_list(_pipe);
  _block = $list.partition(
    _pipe$1,
    (entry) => { return (now - entry[1].last_seen) <= ttl_milliseconds; },
  );
  let $ = _block;
  let kept = $[0];
  let expired = $[1];
  if (expired instanceof $Empty) {
    return [sessions, empty_diff()];
  } else {
    return [
      new Sessions($dict.from_list(kept)),
      new Diff(
        $List$Empty$const,
        $list.map(expired, live_to_tracked),
        $List$Empty$const,
      ),
    ];
  }
}

/**
 * Remove one session by its id. Use this function for a local stop, and for a
 * session that gets a new key after a reconnect assigns a new client id.
 */
export function forget_session(sessions, session_id) {
  let $ = $dict.get(sessions.entries, session_id);
  if ($ instanceof Ok) {
    let previous = $[0];
    return [
      new Sessions($dict.delete$(sessions.entries, session_id)),
      new Diff(
        $List$Empty$const,
        toList([
          new Tracked(session_id, session_id, previous.key, previous.meta),
        ]),
        $List$Empty$const,
      ),
    ];
  } else {
    return [sessions, empty_diff()];
  }
}

/**
 * The current ripple roster, sorted by key then session id.
 */
export function session_entries(sessions) {
  let _pipe = sessions.entries;
  let _pipe$1 = $dict.to_list(_pipe);
  let _pipe$2 = $list.map(_pipe$1, live_to_tracked);
  return public_entries(_pipe$2);
}

/**
 * The payload of a `joinPresence` command or an `updatePresence` command. The
 * client never sends `key`, `session_id`, or `phx_ref`. The server derives
 * the identity from the authenticated connection, so a client cannot claim
 * another user or another session.
 */
export function encode_command(encode, meta) {
  return $json.object(toList([["meta", encode(meta)]]));
}

/**
 * The payload of a `leavePresence` command.
 */
export function encode_leave() {
  return $json.object($List$Empty$const);
}

/**
 * Separate the decoded metas into the tracked ones and the dropped ones, and
 * keep the order in which they arrived.
 * 
 * @ignore
 */
function split_outcomes(outcomes) {
  let $ = $list.fold(
    outcomes,
    [$List$Empty$const, $List$Empty$const],
    (acc, outcome) => {
      let tracked = acc[0];
      let dropped = acc[1];
      if (outcome instanceof Ok) {
        let one = outcome[0];
        return [listPrepend(one, tracked), dropped];
      } else {
        let one = outcome[0];
        return [tracked, listPrepend(one, dropped)];
      }
    },
  );
  let tracked = $[0];
  let dropped = $[1];
  return [$list.reverse(tracked), $list.reverse(dropped)];
}

function tracked_decoder(key, meta) {
  return $decode.field(
    "phx_ref",
    $decode.string,
    (phx_ref) => {
      return $decode.optional_field(
        "client_id",
        "",
        $decode.string,
        (session_id) => {
          return $decode.then$(
            $decode.dict($decode.string, $wire.json_value_decoder()),
            (fields) => {
              let _block;
              let _pipe = fields;
              let _pipe$1 = $dict.drop(_pipe, reserved_meta_fields);
              let _pipe$2 = $dict.to_list(_pipe$1);
              let _pipe$3 = $json.object(_pipe$2);
              _block = $json.to_string(_pipe$3);
              let stripped = _block;
              let $ = $json.parse(stripped, meta);
              if ($ instanceof Ok) {
                let decoded = $[0];
                return $decode.success(
                  new Ok(new Tracked(phx_ref, session_id, key, decoded)),
                );
              } else {
                return $decode.success(new Error(new Dropped(key, session_id)));
              }
            },
          );
        },
      );
    },
  );
}

function tracked_from_groups(groups, meta) {
  let _pipe = groups;
  let _pipe$1 = $dict.to_list(_pipe);
  let _pipe$2 = $list.sort(
    _pipe$1,
    (left, right) => { return $string.compare(left[0], right[0]); },
  );
  let _pipe$3 = $list.flat_map(
    _pipe$2,
    (group) => {
      let key = group[0];
      let metas = group[1];
      return $list.map(
        metas,
        (raw) => {
          let $ = $decode.run(raw, tracked_decoder(key, meta));
          if ($ instanceof Ok) {
            let outcome = $[0];
            return outcome;
          } else {
            return new Error(new Dropped(key, ""));
          }
        },
      );
    },
  );
  return split_outcomes(_pipe$3);
}

function metas_decoder() {
  return $decode.optional_field(
    "metas",
    $List$Empty$const,
    $decode.list($decode.dynamic),
    (metas) => { return $decode.success(metas); },
  );
}

/**
 * `{key: {metas: [...]}}`, with each meta as a raw `Dynamic` value. This
 * module can thus drop one meta that it cannot decode, and keep the other
 * metas.
 * 
 * @ignore
 */
function group_decoder() {
  return $decode.dict($decode.string, metas_decoder());
}

/**
 * Decode the Phoenix snapshot
 * `{key: {metas: [{phx_ref, client_id, ...app}]}}`.
 */
export function presence_state_decoder(meta) {
  return $decode.then$(
    group_decoder(),
    (groups) => {
      let $ = tracked_from_groups(groups, meta);
      let entries = $[0];
      let dropped = $[1];
      return $decode.success(new Snapshot(entries, dropped));
    },
  );
}

/**
 * Decode the Phoenix change `{joins: {...}, leaves: {...}}`.
 */
export function presence_diff_decoder(meta) {
  return $decode.optional_field(
    "joins",
    $dict.new$(),
    group_decoder(),
    (joins) => {
      return $decode.optional_field(
        "leaves",
        $dict.new$(),
        group_decoder(),
        (leaves) => {
          let $ = tracked_from_groups(joins, meta);
          let joined = $[0];
          let join_dropped = $[1];
          let $1 = tracked_from_groups(leaves, meta);
          let left = $1[0];
          let leave_dropped = $1[1];
          return $decode.success(
            new Diff(joined, left, $list.append(join_dropped, leave_dropped)),
          );
        },
      );
    },
  );
}

/**
 * Decode a `presence_error` frame.
 */
export function presence_error_decoder() {
  return $decode.optional_field(
    "code",
    "unknown",
    $decode.string,
    (code) => {
      return $decode.optional_field(
        "message",
        "",
        $decode.string,
        (message) => { return $decode.success(new Rejected(code, message)); },
      );
    },
  );
}

/**
 * The envelope of ripple mode:
 * `{"kind": "presence", "key": ..., "meta": ...}`.
 *
 * The envelope carries no session id. The receiver takes that id from the
 * server-stamped client id of the ripple, so a sender cannot select its own
 * session.
 */
export function encode_ripple(key, encode, meta) {
  return $json.object(
    toList([
      ["kind", $json.string(ripple_type)],
      ["key", $json.string(key)],
      ["meta", encode(meta)],
    ]),
  );
}

/**
 * The decoder for an inbound ripple envelope. It gives `#(key, meta)`. It
 * fails for a foreign `kind` value and for malformed metadata. A ripple does
 * not sequence, and the lane accepts invalid input, so a caller drops a
 * failure and does not crash.
 */
export function ripple_decoder(meta) {
  return $decode.field(
    "kind",
    $decode.string,
    (kind) => {
      return $decode.field(
        "key",
        $decode.string,
        (key) => {
          return $decode.field(
            "meta",
            meta,
            (meta) => {
              let $ = kind === ripple_type;
              if ($) {
                return $decode.success([key, meta]);
              } else {
                return $decode.failure([key, meta], "presence envelope");
              }
            },
          );
        },
      );
    },
  );
}

function hash(text) {
  let _pipe = text;
  let _pipe$1 = $string.to_utf_codepoints(_pipe);
  let _pipe$2 = $list.fold(
    _pipe$1,
    0,
    (acc, codepoint) => { return acc + $string.utf_codepoint_to_int(codepoint); },
  );
  return $int.absolute_value(_pipe$2);
}

/**
 * A stable color with high contrast for a user id. The function is
 * deterministic, so every client renders the same peer in the same color, and
 * the clients need no coordination.
 */
export function color_for(user) {
  let palette = toList([
    "#e6194b",
    "#3cb44b",
    "#4363d8",
    "#f58231",
    "#911eb4",
    "#008080",
    "#9a6324",
    "#e6ac00",
    "#46f0f0",
    "#f032e6",
  ]);
  let index = remainderInt(hash(user), $list.length(palette));
  let $ = $list.drop(palette, index);
  if ($ instanceof $Empty) {
    return "#888888";
  } else {
    let color = $.head;
    return color;
  }
}

/**
 * A short display name from the user id. For example, `"web-1234"` gives
 * `"1234"`.
 */
export function short_name(user) {
  let $ = $string.split(user, "-");
  if ($ instanceof $Empty) {
    return user;
  } else {
    let $1 = $.tail;
    if ($1 instanceof $Empty) {
      return user;
    } else {
      let tail = $1.head;
      return tail;
    }
  }
}

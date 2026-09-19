/// <reference types="./nostr_signaling_js.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import { Ok, Error, toList, CustomType as $CustomType } from "../gleam.mjs";
import * as $crdt_signaling from "../watershed/crdt_signaling.mjs";
import * as $p2p_transport_js from "../watershed/p2p_transport_js.mjs";
import { Failed, Message, PeerJoined, PeerLeft, Roster, Signaling } from "../watershed/p2p_transport_js.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import {
  openPool as native_open,
  publish as native_publish,
  closePool as native_close,
} from "./nostr_signaling_ffi.mjs";

class Hello extends $CustomType {
  constructor(from) {
    super();
    this.from = from;
  }
}

class Ack extends $CustomType {
  constructor(from, to) {
    super();
    this.from = from;
    this.to = to;
  }
}

class Bye extends $CustomType {
  constructor(from) {
    super();
    this.from = from;
  }
}

class Forward extends $CustomType {
  constructor(from, to, payload) {
    super();
    this.from = from;
    this.to = to;
    this.payload = payload;
  }
}

class State extends $CustomType {
  constructor(pool, seen, window, backstop, roster, failed, closed) {
    super();
    this.pool = pool;
    this.seen = seen;
    this.window = window;
    this.backstop = backstop;
    this.roster = roster;
    this.failed = failed;
    this.closed = closed;
  }
}

/**
 * How long the relays have to acknowledge a subscription before the join
 * becomes a failure. This is the backstop for a relay that accepts a socket
 * and then sends nothing.
 */
export const default_roster_timeout_milliseconds = 10_000;

/**
 * How long the census listens after the first relay acknowledges the
 * subscription. The window gives one relay round trip for the `ack` of every
 * member. A public relay needs much less time than this.
 */
export const default_roster_window_milliseconds = 1500;

/**
 * Public relays with a record of years of uptime, for a caller with no
 * preference. Any NIP-01 relay list works here, including a private one.
 */
export const default_relays = /* @__PURE__ */ toList([
  "wss://relay.damus.io",
  "wss://nos.lol",
  "wss://relay.nostr.band",
]);

function disarm(timer) {
  if (timer instanceof Some) {
    let timer$1 = timer[0];
    return $transport_js.clear_timer(timer$1);
  } else {
    return undefined;
  }
}

function encode(frame) {
  let version = ["v", $json.int(1)];
  return $json.to_string(
    (() => {
      if (frame instanceof Hello) {
        let from = frame.from;
        return $json.object(
          toList([
            version,
            ["t", $json.string("hello")],
            ["from", $json.string(from)],
          ]),
        );
      } else if (frame instanceof Ack) {
        let from = frame.from;
        let to = frame.to;
        return $json.object(
          toList([
            version,
            ["t", $json.string("ack")],
            ["from", $json.string(from)],
            ["to", $json.string(to)],
          ]),
        );
      } else if (frame instanceof Bye) {
        let from = frame.from;
        return $json.object(
          toList([
            version,
            ["t", $json.string("bye")],
            ["from", $json.string(from)],
          ]),
        );
      } else {
        let from = frame.from;
        let to = frame.to;
        let payload = frame.payload;
        return $json.object(
          toList([
            version,
            ["t", $json.string("signal")],
            ["from", $json.string(from)],
            ["to", $json.string(to)],
            ["payload", $crdt_signaling.encode_payload(payload)],
          ]),
        );
      }
    })(),
  );
}

function write(cell, frame) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.pool;
  if ($) {
    return undefined;
  } else if ($1 instanceof Some) {
    let pool = $1[0];
    return native_publish(pool, encode(frame));
  } else {
    return undefined;
  }
}

function with_current(current, work) {
  let $ = $transport_js.get_cell(current);
  if ($ instanceof Some) {
    let cell = $[0];
    return work(cell);
  } else {
    return undefined;
  }
}

/**
 * Report one failure to the transport and to the application, one time each.
 * The contract is the same as for `crdt_signaling_js.fail`.
 * 
 * @ignore
 */
function fail(cell, detail, on_signal, on_failure) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.failed;
  if ($) {
    return undefined;
  } else if ($1) {
    return undefined;
  } else {
    disarm(state.window);
    disarm(state.backstop);
    $transport_js.set_cell(
      cell,
      new State(
        state.pool,
        state.seen,
        Option$None$const,
        Option$None$const,
        state.roster,
        true,
        state.closed,
      ),
    );
    on_signal(new Failed(detail));
    return on_failure(detail);
  }
}

function arm_backstop(cell, timeout_milliseconds, on_signal, on_failure) {
  let $ = timeout_milliseconds > 0;
  if ($) {
    let timer = $transport_js.set_timer(
      () => {
        let $1 = $transport_js.get_cell(cell).roster;
        if ($1) {
          return undefined;
        } else {
          return fail(
            cell,
            ("no relay acknowledged the subscription within " + $int.to_string(
              timeout_milliseconds,
            )) + "ms",
            on_signal,
            on_failure,
          );
        }
      },
      timeout_milliseconds,
    );
    let state = $transport_js.get_cell(cell);
    let $1 = (state.roster || state.failed) || state.closed;
    if ($1) {
      return $transport_js.clear_timer(timer);
    } else {
      return $transport_js.set_cell(
        cell,
        new State(
          state.pool,
          state.seen,
          state.window,
          new Some(timer),
          state.roster,
          state.failed,
          state.closed,
        ),
      );
    }
  } else {
    return undefined;
  }
}

/**
 * Close the census. The set that the adapter heard is the one roster of this
 * join.
 * 
 * @ignore
 */
function report_roster(cell, on_signal) {
  let state = $transport_js.get_cell(cell);
  let $ = (state.roster || state.failed) || state.closed;
  if ($) {
    return undefined;
  } else {
    disarm(state.backstop);
    $transport_js.set_cell(
      cell,
      new State(
        state.pool,
        state.seen,
        Option$None$const,
        Option$None$const,
        true,
        state.failed,
        state.closed,
      ),
    );
    return on_signal(new Roster($set.to_list(state.seen)));
  }
}

/**
 * The first relay acknowledged the subscription, so the census can start.
 * 
 * @ignore
 */
function open_window(cell, window_milliseconds, on_signal) {
  let $ = window_milliseconds > 0;
  if ($) {
    let timer = $transport_js.set_timer(
      () => { return report_roster(cell, on_signal); },
      window_milliseconds,
    );
    let state = $transport_js.get_cell(cell);
    let $1 = (state.roster || state.failed) || state.closed;
    if ($1) {
      return $transport_js.clear_timer(timer);
    } else {
      return $transport_js.set_cell(
        cell,
        new State(
          state.pool,
          state.seen,
          new Some(timer),
          state.backstop,
          state.roster,
          state.failed,
          state.closed,
        ),
      );
    }
  } else {
    return report_roster(cell, on_signal);
  }
}

function note(cell, peer) {
  let state = $transport_js.get_cell(cell);
  return $transport_js.set_cell(
    cell,
    new State(
      state.pool,
      $set.insert(state.seen, peer),
      state.window,
      state.backstop,
      state.roster,
      state.failed,
      state.closed,
    ),
  );
}

/**
 * A peer that joined and then left inside the census window was a member and
 * is not a member now. The census must not add it again.
 * 
 * @ignore
 */
function forget(cell, peer) {
  let state = $transport_js.get_cell(cell);
  return $transport_js.set_cell(
    cell,
    new State(
      state.pool,
      $set.delete$(state.seen, peer),
      state.window,
      state.backstop,
      state.roster,
      state.failed,
      state.closed,
    ),
  );
}

function deliver(cell, me, frame, on_signal) {
  if (frame instanceof Hello) {
    let from = frame.from;
    note(cell, from);
    on_signal(new PeerJoined(from));
    return write(cell, new Ack(me, from));
  } else if (frame instanceof Ack) {
    let to = frame.to;
    if (to === me) {
      let from = frame.from;
      note(cell, from);
      return on_signal(new PeerJoined(from));
    } else {
      return undefined;
    }
  } else if (frame instanceof Bye) {
    let from = frame.from;
    forget(cell, from);
    return on_signal(new PeerLeft(from));
  } else {
    let to = frame.to;
    if (to === me) {
      let from = frame.from;
      let payload = frame.payload;
      note(cell, from);
      return on_signal(new Message(from, payload));
    } else {
      return undefined;
    }
  }
}

function sender(frame) {
  if (frame instanceof Hello) {
    let from = frame.from;
    return from;
  } else if (frame instanceof Ack) {
    let from = frame.from;
    return from;
  } else if (frame instanceof Bye) {
    let from = frame.from;
    return from;
  } else {
    let from = frame.from;
    return from;
  }
}

function frame_decoder() {
  return $decode.field(
    "v",
    $decode.int,
    (version) => {
      if (version === 1) {
        return $decode.field(
          "t",
          $decode.string,
          (tag) => {
            return $decode.field(
              "from",
              $decode.string,
              (from) => {
                if (tag === "hello") {
                  return $decode.success(new Hello(from));
                } else if (tag === "ack") {
                  return $decode.field(
                    "to",
                    $decode.string,
                    (to) => { return $decode.success(new Ack(from, to)); },
                  );
                } else if (tag === "bye") {
                  return $decode.success(new Bye(from));
                } else if (tag === "signal") {
                  return $decode.field(
                    "to",
                    $decode.string,
                    (to) => {
                      return $decode.field(
                        "payload",
                        $crdt_signaling.payload_decoder(),
                        (payload) => {
                          return $decode.success(new Forward(from, to, payload));
                        },
                      );
                    },
                  );
                } else {
                  return $decode.failure(new Bye(""), "nostr signaling frame");
                }
              },
            );
          },
        );
      } else {
        return $decode.failure(new Bye(""), "nostr signaling frame");
      }
    },
  );
}

function decode(raw) {
  let $ = $json.parse(raw, frame_decoder());
  if ($ instanceof Ok) {
    return $;
  } else {
    return new Error(undefined);
  }
}

/**
 * One decrypted frame from the topic. The function drops traffic that it
 * cannot decode, a frame addressed to another peer, and the echo of a frame
 * that this member sent.
 * 
 * @ignore
 */
function receive(cell, me, raw, on_signal) {
  let $ = $transport_js.get_cell(cell).closed;
  if ($) {
    return undefined;
  } else {
    let $1 = decode(raw);
    if ($1 instanceof Ok) {
      let frame = $1[0];
      let $2 = sender(frame) === me;
      if ($2) {
        return undefined;
      } else {
        return deliver(cell, me, frame, on_signal);
      }
    } else {
      return undefined;
    }
  }
}

/**
 * `nostr_signaling` with an explicit census window and backstop. A backstop
 * of zero or less never expires. A window of zero or less reports the roster
 * when a relay acknowledges, which is correct in a test only.
 */
export function nostr_signaling_with_timing(
  relays,
  on_failure,
  roster_window_milliseconds,
  roster_timeout_milliseconds
) {
  let current = $transport_js.new_cell(Option$None$const);
  return new Signaling(
    (room, peer, on_signal) => {
      let cell = $transport_js.new_cell(
        new State(
          Option$None$const,
          $set.new$(),
          Option$None$const,
          Option$None$const,
          false,
          false,
          false,
        ),
      );
      let $ = native_open(
        relays,
        room,
        (raw) => { return receive(cell, peer, raw, on_signal); },
        () => {
          return open_window(cell, roster_window_milliseconds, on_signal);
        },
        (detail) => { return fail(cell, detail, on_signal, on_failure); },
      );
      if ($ instanceof Ok) {
        let pool = $[0];
        let state = $transport_js.get_cell(cell);
        $transport_js.set_cell(
          cell,
          new State(
            new Some(pool),
            state.seen,
            state.window,
            state.backstop,
            state.roster,
            state.failed,
            state.closed,
          ),
        );
        $transport_js.set_cell(current, new Some(cell));
        write(cell, new Hello(peer));
        arm_backstop(cell, roster_timeout_milliseconds, on_signal, on_failure);
        return new Ok($p2p_transport_js.signaling_session(room, peer));
      } else {
        return $;
      }
    },
    (session, to, payload) => {
      return with_current(
        current,
        (cell) => {
          return write(
            cell,
            new Forward($p2p_transport_js.session_peer_id(session), to, payload),
          );
        },
      );
    },
    (session) => {
      return with_current(
        current,
        (cell) => {
          let state = $transport_js.get_cell(cell);
          let $ = state.closed;
          if ($) {
            return undefined;
          } else {
            write(cell, new Bye($p2p_transport_js.session_peer_id(session)));
            disarm(state.window);
            disarm(state.backstop);
            $transport_js.set_cell(
              cell,
              new State(
                state.pool,
                state.seen,
                Option$None$const,
                Option$None$const,
                state.roster,
                state.failed,
                true,
              ),
            );
            let $1 = state.pool;
            if ($1 instanceof Some) {
              let pool = $1[0];
              return native_close(pool);
            } else {
              return undefined;
            }
          }
        },
      );
    },
  );
}

/**
 * A signaling adapter that meets the peers on `relays`, with the default
 * census window and the default backstop.
 *
 * `on_failure` receives each failure that occurs after `join` returns. Those
 * failures are the loss of every relay, no acknowledgement from any relay,
 * and a crypto environment that does not work. The argument is required, and
 * not optional. An application must always know that the signaling is no
 * longer available.
 */
export function nostr_signaling(relays, on_failure) {
  return nostr_signaling_with_timing(
    relays,
    on_failure,
    default_roster_window_milliseconds,
    default_roster_timeout_milliseconds,
  );
}

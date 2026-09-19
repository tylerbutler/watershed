/// <reference types="./crdt_signaling_js.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import { Ok, CustomType as $CustomType } from "../gleam.mjs";
import * as $crdt_signaling from "../watershed/crdt_signaling.mjs";
import * as $p2p_transport_js from "../watershed/p2p_transport_js.mjs";
import { Failed, Message, PeerJoined, PeerLeft, Roster, Signaling } from "../watershed/p2p_transport_js.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import {
  openSignaling as native_open,
  sendSignaling as native_send,
  close as native_close,
} from "./ws_ffi.mjs";

class State extends $CustomType {
  constructor(socket, deadline, roster, failed, closed) {
    super();
    this.socket = socket;
    this.deadline = deadline;
    this.roster = roster;
    this.failed = failed;
    this.closed = closed;
  }
}

/**
 * The time that a service has to admit this peer before the join becomes a
 * failure. The value is generous. It covers a socket handshake and one round
 * trip. It does not cover a negotiation.
 */
export const default_roster_timeout_milliseconds = 10_000;

function disarm(state) {
  let $ = state.deadline;
  if ($ instanceof Some) {
    let timer = $[0];
    return $transport_js.clear_timer(timer);
  } else {
    return undefined;
  }
}

function write(cell, frame) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.socket;
  if ($) {
    return undefined;
  } else if ($1 instanceof Some) {
    let socket = $1[0];
    return native_send(socket, $crdt_signaling.client_to_string(frame));
  } else {
    return undefined;
  }
}

/**
 * Run `work` on the state of the current join. Do nothing before the first
 * join stores a state.
 * 
 * @ignore
 */
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
 *
 * The report to the transport prevents a document that waits without an end.
 * A `Failed` signal becomes a typed `SignalingFailed` value, which resolves a
 * readiness result that would not arrive. A connection that its owner already
 * closed reports nothing, because the owner asked for that result.
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
    disarm(state);
    $transport_js.set_cell(
      cell,
      new State(
        state.socket,
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

/**
 * Start the roster deadline. The timer reads the cell, and it does not close
 * over the socket. A join that the service already admitted, or that failed,
 * or that left, thus has nothing to report when the timer runs.
 * 
 * @ignore
 */
function arm(cell, timeout_milliseconds, on_signal, on_failure) {
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
            ("the signaling service did not admit this peer within " + $int.to_string(
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
          state.socket,
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

function describe(parts) {
  let $ = parts[1];
  if ($ === "") {
    return parts[0];
  } else {
    return (parts[0] + " · ") + parts[1];
  }
}

function deliver(cell, frame, on_signal, on_failure) {
  if (frame instanceof $crdt_signaling.Joined) {
    let peers = frame.peers;
    let state = $transport_js.get_cell(cell);
    let $ = state.roster;
    if ($) {
      return undefined;
    } else {
      disarm(state);
      $transport_js.set_cell(
        cell,
        new State(
          state.socket,
          Option$None$const,
          true,
          state.failed,
          state.closed,
        ),
      );
      return on_signal(new Roster(peers));
    }
  } else if (frame instanceof $crdt_signaling.PeerJoined) {
    let peer = frame.peer;
    return on_signal(new PeerJoined(peer));
  } else if (frame instanceof $crdt_signaling.PeerLeft) {
    let peer = frame.peer;
    return on_signal(new PeerLeft(peer));
  } else if (frame instanceof $crdt_signaling.Forwarded) {
    let from = frame.from;
    let payload = frame.payload;
    return on_signal(new Message(from, payload));
  } else if (frame instanceof $crdt_signaling.Rejected) {
    let reason = frame.reason;
    let detail = frame.detail;
    return fail(cell, describe([reason, detail]), on_signal, on_failure);
  } else {
    return undefined;
  }
}

/**
 * One frame from the service. The membership frames and the routing frames
 * have a meaning here. A terminal refusal is a failure. A frame that the
 * adapter cannot decode is also a failure. A service that sends frames that
 * this client does not understand is a service to report. Do not guess at
 * what it means.
 * 
 * @ignore
 */
function receive(cell, raw, on_signal, on_failure) {
  let $ = $transport_js.get_cell(cell).closed;
  if ($) {
    return undefined;
  } else {
    let $1 = $crdt_signaling.decode_server(raw);
    if ($1 instanceof Ok) {
      let frame = $1[0];
      return deliver(cell, frame, on_signal, on_failure);
    } else {
      let refusal = $1[0];
      return fail(
        cell,
        describe($crdt_signaling.refusal_parts(refusal)),
        on_signal,
        on_failure,
      );
    }
  }
}

/**
 * `websocket_signaling` with an explicit roster deadline. A timeout of zero
 * or less never expires. That value is correct only for a caller that limits
 * the wait itself.
 */
export function websocket_signaling_with_timeout(
  url,
  on_failure,
  roster_timeout_milliseconds
) {
  let current = $transport_js.new_cell(Option$None$const);
  return new Signaling(
    (room, peer, on_signal) => {
      let cell = $transport_js.new_cell(
        new State(Option$None$const, Option$None$const, false, false, false),
      );
      let $ = native_open(
        url,
        (raw) => { return receive(cell, raw, on_signal, on_failure); },
        (detail) => { return fail(cell, detail, on_signal, on_failure); },
      );
      if ($ instanceof Ok) {
        let socket = $[0];
        let state = $transport_js.get_cell(cell);
        $transport_js.set_cell(
          cell,
          new State(
            new Some(socket),
            state.deadline,
            state.roster,
            state.failed,
            state.closed,
          ),
        );
        $transport_js.set_cell(current, new Some(cell));
        write(cell, new $crdt_signaling.Join(room, peer));
        arm(cell, roster_timeout_milliseconds, on_signal, on_failure);
        return new Ok($p2p_transport_js.signaling_session(room, peer));
      } else {
        return $;
      }
    },
    (_, to, payload) => {
      return with_current(
        current,
        (cell) => {
          return write(cell, new $crdt_signaling.Signal(to, payload));
        },
      );
    },
    (_) => {
      return with_current(
        current,
        (cell) => {
          let state = $transport_js.get_cell(cell);
          let $ = state.closed;
          if ($) {
            return undefined;
          } else {
            write(cell, $crdt_signaling.ClientFrame$Leave$const);
            disarm(state);
            $transport_js.set_cell(
              cell,
              new State(
                state.socket,
                Option$None$const,
                state.roster,
                state.failed,
                true,
              ),
            );
            let $1 = state.socket;
            if ($1 instanceof Some) {
              let socket = $1[0];
              return native_close(socket);
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
 * A signaling adapter that connects to a `crdt_signaling` service at `url`.
 *
 * `on_failure` receives each socket-level failure that occurs after `join`
 * returns. Those failures are an unreachable service, a socket that the
 * service closed, a refusal frame with its reason, and a roster that never
 * arrived. The argument is required, and not optional. An application must
 * always know that a signaling service is no longer available.
 *
 * One adapter drives one membership. The transport calls `join` one time.
 * Each `join` gets its own state cell, and `SignalingSession` thus contains
 * no adapter internals.
 */
export function websocket_signaling(url, on_failure) {
  return websocket_signaling_with_timeout(
    url,
    on_failure,
    default_roster_timeout_milliseconds,
  );
}

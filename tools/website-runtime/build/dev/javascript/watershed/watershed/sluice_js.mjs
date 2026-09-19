/// <reference types="./sluice_js.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import {
  Ok,
  Error,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $watershed from "../watershed.mjs";
import * as $runtime from "../watershed/runtime.mjs";
import * as $core from "../watershed/sluice/core.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import * as $socket from "../watershed/wire/socket.mjs";
import { referenceEquals as reference_equals } from "./sluice_ffi.mjs";

class Sluice extends $CustomType {
  constructor(cell, tenant, document) {
    super();
    this.cell = cell;
    this.tenant = tenant;
    this.document = document;
  }
}

export class Delivery extends $CustomType {
  constructor(to, event, sequence_number, author) {
    super();
    this.to = to;
    this.event = event;
    this.sequence_number = sequence_number;
    this.author = author;
  }
}
export const Delivery$Delivery = (to, event, sequence_number, author) =>
  new Delivery(to, event, sequence_number, author);
export const Delivery$isDelivery = (value) => value instanceof Delivery;
export const Delivery$Delivery$to = (value) => value.to;
export const Delivery$Delivery$0 = (value) => value.to;
export const Delivery$Delivery$event = (value) => value.event;
export const Delivery$Delivery$1 = (value) => value.event;
export const Delivery$Delivery$sequence_number = (value) =>
  value.sequence_number;
export const Delivery$Delivery$2 = (value) => value.sequence_number;
export const Delivery$Delivery$author = (value) => value.author;
export const Delivery$Delivery$3 = (value) => value.author;

class Conn extends $CustomType {
  constructor(on_event, on_join, on_close, current, dropped) {
    super();
    this.on_event = on_event;
    this.on_join = on_join;
    this.on_close = on_close;
    this.current = current;
    this.dropped = dropped;
  }
}

class State extends $CustomType {
  constructor(core, conns, bindings, last_registered, timers, next_timer_id) {
    super();
    this.core = core;
    this.conns = conns;
    this.bindings = bindings;
    this.last_registered = last_registered;
    this.timers = timers;
    this.next_timer_id = next_timer_id;
  }
}

/**
 * Start a sluice for one document.
 */
export function start(tenant, document) {
  return new Sluice(
    $transport_js.new_cell(
      new State(
        $core.new$(tenant, document),
        $List$Empty$const,
        $List$Empty$const,
        Option$None$const,
        $List$Empty$const,
        1,
      ),
    ),
    tenant,
    document,
  );
}

/**
 * The connection that the server knows by `client_id` now. A frame carries the
 * id that the server assigned, so this function searches the `current` field,
 * and not the token that keys the list.
 * 
 * @ignore
 */
function find_conn(conns, client_id) {
  let $ = $list.find(conns, (pair) => { return pair[1].current === client_id; });
  if ($ instanceof Ok) {
    let pair = $[0];
    return new Ok(pair[1]);
  } else {
    return new Error(undefined);
  }
}

function cancel_timer(sluice, id) {
  let state = $transport_js.get_cell(sluice.cell);
  return $transport_js.set_cell(
    sluice.cell,
    new State(
      state.core,
      state.conns,
      state.bindings,
      state.last_registered,
      $list.filter(state.timers, (timer) => { return timer[1] !== id; }),
      state.next_timer_id,
    ),
  );
}

function schedule_timer(sluice, action, milliseconds) {
  let state = $transport_js.get_cell(sluice.cell);
  let id = state.next_timer_id;
  $transport_js.set_cell(
    sluice.cell,
    new State(
      state.core,
      state.conns,
      state.bindings,
      state.last_registered,
      listPrepend(
        [$core.now(state.core) + milliseconds, id, action],
        state.timers,
      ),
      id + 1,
    ),
  );
  return () => { return cancel_timer(sluice, id); };
}

/**
 * A scheduler that uses the logical clock of this sluice. Use it to drive a
 * presence handle, or anything else with a heartbeat, from `advance` instead
 * of from the real elapsed time.
 */
export function scheduler(sluice) {
  return new $transport_js.Scheduler(
    () => { return $core.now($transport_js.get_cell(sluice.cell).core); },
    (action, milliseconds) => {
      return schedule_timer(sluice, action, milliseconds);
    },
  );
}

/**
 * `rejoin`, keyed by transport token. The `resume` function of the handle
 * needs this form. See `drop_token`.
 * 
 * @ignore
 */
function rejoin_token(cell, token) {
  let state = $transport_js.get_cell(cell);
  let $ = $list.key_find(state.conns, token);
  if ($ instanceof Ok) {
    let conn = $[0];
    if (conn.dropped) {
      let $1 = $core.register(state.core);
      let core = $1[0];
      let rejoined = $1[1];
      $transport_js.set_cell(
        cell,
        new State(
          core,
          $list.key_set(
            state.conns,
            token,
            new Conn(
              conn.on_event,
              conn.on_join,
              conn.on_close,
              rejoined,
              false,
            ),
          ),
          state.bindings,
          state.last_registered,
          state.timers,
          state.next_timer_id,
        ),
      );
      return conn.on_join();
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

/**
 * `drop`, keyed by transport token instead of by document.
 *
 * The transport handle closes over its token, and it has no `Sluice` value or
 * `Document` value to give. Its `hold` function thus needs this form.
 * `watershed.go_offline` therefore works against the sluice, and not against
 * a real socket only.
 * 
 * @ignore
 */
function drop_token(cell, token) {
  let state = $transport_js.get_cell(cell);
  let $ = $list.key_find(state.conns, token);
  if ($ instanceof Ok) {
    let conn = $[0];
    $transport_js.set_cell(
      cell,
      new State(
        $core.disconnect(state.core, conn.current),
        $list.key_set(
          state.conns,
          token,
          new Conn(
            conn.on_event,
            conn.on_join,
            conn.on_close,
            conn.current,
            true,
          ),
        ),
        state.bindings,
        state.last_registered,
        state.timers,
        state.next_timer_id,
      ),
    );
    return conn.on_close();
  } else {
    return undefined;
  }
}

/**
 * Serialize a queued `Json` frame and parse it again as `Dynamic`, for
 * `sluice/core.handle`, which decodes an inbound push the same way floodgate
 * would off a real socket.
 * 
 * @ignore
 */
function json_to_dynamic(payload) {
  let $ = $json.parse($json.to_string(payload), $decode.dynamic);
  if ($ instanceof Ok) {
    let value = $[0];
    return value;
  } else {
    return $dynamic.nil();
  }
}

function push(cell, token, event, payload) {
  let state = $transport_js.get_cell(cell);
  let $ = $list.key_find(state.conns, token);
  if ($ instanceof Ok) {
    let conn = $[0];
    return $transport_js.set_cell(
      cell,
      new State(
        $core.handle(state.core, conn.current, event, json_to_dynamic(payload)),
        state.conns,
        state.bindings,
        state.last_registered,
        state.timers,
        state.next_timer_id,
      ),
    );
  } else {
    return undefined;
  }
}

function register(cell, on_event, on_join, on_close) {
  let state = $transport_js.get_cell(cell);
  let $ = $core.register(state.core);
  let core = $[0];
  let client_id$1 = $[1];
  $transport_js.set_cell(
    cell,
    new State(
      core,
      listPrepend(
        [client_id$1, new Conn(on_event, on_join, on_close, client_id$1, false)],
        state.conns,
      ),
      state.bindings,
      new Some(client_id$1),
      state.timers,
      state.next_timer_id,
    ),
  );
  return client_id$1;
}

function make_transport(cell) {
  return new $runtime.Transport(
    (callbacks) => {
      let token = register(
        cell,
        callbacks.on_event,
        callbacks.on_join,
        callbacks.on_close,
      );
      return new $runtime.TransportHandle(
        (event, payload) => { return push(cell, token, event, payload); },
        () => { return undefined; },
        () => { return undefined; },
        () => { return drop_token(cell, token); },
        () => { return rejoin_token(cell, token); },
      );
    },
  );
}

/**
 * Connect a new client and return a real `watershed.Document` value. The
 * handshake completes on the next `settle`, because every delivery is
 * explicit.
 */
export function connect(sluice, user_id) {
  let transport = make_transport(sluice.cell);
  let document = $watershed.connect_via(
    sluice.tenant,
    sluice.document,
    user_id,
    transport,
    (_) => { return undefined; },
  );
  $runtime.set_scheduler($watershed.runtime_of(document), scheduler(sluice));
  let state = $transport_js.get_cell(sluice.cell);
  let $ = state.last_registered;
  if ($ instanceof Some) {
    let client_id$1 = $[0];
    $transport_js.set_cell(
      sluice.cell,
      new State(
        state.core,
        state.conns,
        listPrepend(
          [$watershed.runtime_of(document), client_id$1],
          state.bindings,
        ),
        Option$None$const,
        state.timers,
        state.next_timer_id,
      ),
    );
    let $1 = find_conn(state.conns, client_id$1);
    if ($1 instanceof Ok) {
      let conn = $1[0];
      conn.on_join();
    } else {
      undefined;
    }
  } else {
    undefined;
  }
  return document;
}

/**
 * The connection token that is bound to a runtime.
 * 
 * @ignore
 */
function token_of(bindings, runtime) {
  let $ = $list.find(
    bindings,
    (pair) => { return reference_equals(pair[0], runtime); },
  );
  if ($ instanceof Ok) {
    let pair = $[0];
    return new Ok(pair[1]);
  } else {
    return new Error(undefined);
  }
}

/**
 * The current id that the server assigned to a runtime.
 * 
 * @ignore
 */
function client_id_of(state, runtime) {
  let $ = token_of(state.bindings, runtime);
  if ($ instanceof Ok) {
    let token = $[0];
    let $1 = $list.key_find(state.conns, token);
    if ($1 instanceof Ok) {
      let conn = $1[0];
      return new Ok(conn.current);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

function apply_to_client(sluice, document, change) {
  let state = $transport_js.get_cell(sluice.cell);
  let $ = client_id_of(state, $watershed.runtime_of(document));
  if ($ instanceof Ok) {
    let client_id$1 = $[0];
    return $transport_js.set_cell(
      sluice.cell,
      new State(
        change(state.core, client_id$1),
        state.conns,
        state.bindings,
        state.last_registered,
        state.timers,
        state.next_timer_id,
      ),
    );
  } else {
    return undefined;
  }
}

/**
 * Hold the inbound frames of a client until a `resume` call. The queued frames
 * of that client stay in the queue while the sluice delivers the frames of the
 * other clients, so a test can script a race.
 */
export function pause(sluice, document) {
  return apply_to_client(sluice, document, $core.pause);
}

/**
 * Return the held frames of a paused client to the deliverable queue.
 */
export function resume(sluice, document) {
  return apply_to_client(sluice, document, $core.resume);
}

/**
 * Remove a client from the room, and sequence a `"leave"` message to the
 * clients that remain.
 *
 * This is the path for a departure that is not graceful. It is the only way
 * to test the kernel behaviour that depends on membership: a `TaskManager`
 * role that the kernel releases because its holder left, or a `PactMap`
 * proposal whose signoff list becomes empty because one of the clients that
 * it waited on is no longer in the room. `pause` cannot replace this
 * function. A paused client is still a member, so a pact still waits on it,
 * and that stall is the condition under test.
 */
export function disconnect(sluice, document) {
  return apply_to_client(sluice, document, $core.disconnect);
}

function conn_for(state, runtime) {
  let $ = token_of(state.bindings, runtime);
  if ($ instanceof Ok) {
    let token = $[0];
    let $1 = $list.key_find(state.conns, token);
    if ($1 instanceof Ok) {
      let conn = $1[0];
      return new Ok([token, conn]);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The second half of `reconnect`: let a dropped client return, under a new
 * client id that the server assigns.
 *
 * The function does nothing for a client that `drop` did not remove.
 */
export function rejoin(sluice, document) {
  let state = $transport_js.get_cell(sluice.cell);
  let $ = conn_for(state, $watershed.runtime_of(document));
  if ($ instanceof Ok) {
    let token = $[0][0];
    return rejoin_token(sluice.cell, token);
  } else {
    return undefined;
  }
}

/**
 * The first half of `reconnect`: close the socket and keep it closed.
 *
 * The two halves are separate because the interesting window is *between*
 * them. A client is outside the room from its `leave` until its rejoin. Every
 * operation that sequences in that interval sequenced for a room that did not
 * contain the client. The client must then replay those operations, under an
 * identity that did not exist when other clients made them. To script that
 * sequence, a test must sequence operations while the client is absent, and
 * one atomic reconnect cannot express that.
 *
 * The runtime keeps its core and stays in its reconnecting phase until
 * `rejoin`.
 */
export function drop(sluice, document) {
  let state = $transport_js.get_cell(sluice.cell);
  let $ = conn_for(state, $watershed.runtime_of(document));
  if ($ instanceof Ok) {
    let token = $[0][0];
    return drop_token(sluice.cell, token);
  } else {
    return undefined;
  }
}

/**
 * Close the socket of a client and then let that client return. This is the
 * reconnect that a real client survives. It is not a departure.
 *
 * The difference from `disconnect` is the purpose of this function.
 * `disconnect` removes a client from the room permanently. This function
 * closes the connection below a runtime that keeps its core, which is the
 * kernel state, the pending consensus, and the in-flight queue. The runtime
 * then does the handshake again. The server assigns it a **new client id**,
 * exactly as floodgate does, so the client that returns is a different member
 * of the room than the client that left.
 *
 * Many protocol faults are in that window. An operation that sequenced while
 * the client was absent replays against the room as it was at that time. An
 * edit from the interval gets a new stamp and a resubmission. A consensus
 * kernel can owe signoffs under an identity that no longer exists.
 *
 * Unlike the Erlang driver, this function never runs `Transport.connect`
 * again, because the JavaScript runtime never does that either. Its real
 * transport is a Phoenix socket, which joins again by itself and runs
 * `on_join` again on the same channel. This driver thus models the rejoin
 * where it happens: the connection stays open, and the *server* gives it a
 * new identity.
 *
 * The handshake completes on the next `settle`, the same as for `connect`.
 */
export function reconnect(sluice, document) {
  drop(sluice, document);
  return rejoin(sluice, document);
}

/**
 * Take the next deliverable frame, deliver it, and return it. The result is
 * `Error(Nil)` when there is no such frame. The function commits the take before the
 * delivery, because the reaction of the recipient goes back into the same
 * cell, and the function must not overwrite it.
 * 
 * @ignore
 */
function take_deliver(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = $core.take(state.core);
  let $1 = $[1];
  if ($1 instanceof Ok) {
    let core = $[0];
    let frame = $1[0];
    $transport_js.set_cell(
      cell,
      new State(
        core,
        state.conns,
        state.bindings,
        state.last_registered,
        state.timers,
        state.next_timer_id,
      ),
    );
    let $2 = find_conn(state.conns, frame.client_id);
    if ($2 instanceof Ok) {
      let conn = $2[0];
      conn.on_event(frame.event, $json.to_string(frame.payload));
    } else {
      undefined;
    }
    return new Ok(frame);
  } else {
    let core = $[0];
    $transport_js.set_cell(
      cell,
      new State(
        core,
        state.conns,
        state.bindings,
        state.last_registered,
        state.timers,
        state.next_timer_id,
      ),
    );
    return new Error(undefined);
  }
}

function drain(loop$cell) {
  while (true) {
    let cell = loop$cell;
    let $ = take_deliver(cell);
    if ($ instanceof Ok) {
      loop$cell = cell;
    } else {
      return undefined;
    }
  }
}

/**
 * Deliver the queued frames until the system is quiet. The function is
 * synchronous: the reaction to each delivery goes back into the core before
 * the next iteration.
 */
export function settle(sluice) {
  return drain(sluice.cell);
}

/**
 * Deliver exactly one queued frame, to a client that is not paused. The
 * function returns `False` when it can deliver no frame.
 */
export function step(sluice) {
  return $result.is_ok(take_deliver(sluice.cell));
}

/**
 * Read the sequence number and the author from the payload of an `op`
 * frame, for `step_info`. The result is `0` and `""` for another kind of
 * event.
 * 
 * @ignore
 */
function operation_meta(frame) {
  let $ = frame.event;
  if ($ === "op") {
    let $1 = $json.parse(
      $json.to_string(frame.payload),
      $socket.operation_message_decoder(),
    );
    if ($1 instanceof Ok) {
      let message = $1[0];
      let $2 = message.ops;
      if ($2 instanceof $Empty) {
        return [0, ""];
      } else {
        let operation = $2.head;
        return [
          operation.sequence_number,
          $option.unwrap(operation.client_id, ""),
        ];
      }
    } else {
      return [0, ""];
    }
  } else {
    return [0, ""];
  }
}

/**
 * The same as `step`, but the function reports what it delivered: the target
 * client, the event, and, for an `op` event, the sequence number and
 * the author. The result is `Error(Nil)` when the function can deliver no
 * frame. Use it to drive a live visualization that animates each hop.
 */
export function step_info(sluice) {
  let $ = take_deliver(sluice.cell);
  if ($ instanceof Ok) {
    let frame = $[0];
    let $1 = operation_meta(frame);
    let sequence_number$1 = $1[0];
    let author = $1[1];
    return new Ok(
      new Delivery(frame.client_id, frame.event, sequence_number$1, author),
    );
  } else {
    return $;
  }
}

/**
 * Report the next frame that `step` or `step_info` would deliver, and deliver
 * nothing. A caller can thus collect a whole broadcast group, which is every
 * frame that shares the sequence number of one operation, into one animation
 * step. Every replica then receives the operation together, and not one hop at
 * a time.
 */
export function peek_info(sluice) {
  let $ = $core.peek($transport_js.get_cell(sluice.cell).core);
  if ($ instanceof Ok) {
    let frame = $[0];
    let $1 = operation_meta(frame);
    let sequence_number$1 = $1[0];
    let author = $1[1];
    return new Ok(
      new Delivery(frame.client_id, frame.event, sequence_number$1, author),
    );
  } else {
    return $;
  }
}

/**
 * Whether a frame still waits for delivery to a client that is not paused.
 */
export function pending(sluice) {
  return $core.has_pending($transport_js.get_cell(sluice.cell).core);
}

/**
 * The client id that the sluice assigned to a document. It is the same value
 * as the `to` field and the `author` field of `step_info`. The result is an
 * `Error` if the document is not connected to this sluice.
 */
export function client_id(sluice, document) {
  return client_id_of(
    $transport_js.get_cell(sluice.cell),
    $watershed.runtime_of(document),
  );
}

/**
 * The current server sequence number. An operation sequences synchronously at
 * submit time, so a read immediately after an edit gives the sequence number
 * of that operation.
 */
export function sequence_number(sluice) {
  return $core.sequence_number($transport_js.get_cell(sluice.cell).core);
}

/**
 * Run the earliest timer that is due, then look again. The function recurses,
 * and it does not fold, and that choice is deliberate. Each callback can
 * schedule, cancel, or run more timers, so the function must read the list
 * again in every round.
 * 
 * @ignore
 */
function fire_due(loop$sluice) {
  while (true) {
    let sluice = loop$sluice;
    let state = $transport_js.get_cell(sluice.cell);
    let now = $core.now(state.core);
    let due = $list.filter(state.timers, (timer) => { return timer[0] <= now; });
    let $ = $list.sort(due, (a, b) => { return $int.compare(a[0], b[0]); });
    if ($ instanceof $Empty) {
      return undefined;
    } else {
      let id = $.head[1];
      let action = $.head[2];
      cancel_timer(sluice, id);
      action();
      loop$sluice = sluice;
    }
  }
}

/**
 * Advance the logical clock of the sluice and run every timer that became
 * due. A test can thus check the logic that depends on a time-to-live (TTL) or
 * on a heartbeat, without a wait for the real time.
 *
 * The timers run one at a time, and the function reads the cell again between
 * them. A heartbeat schedules itself again from inside its own callback, and
 * this same `advance` call must not run that replacement.
 */
export function advance(sluice, milliseconds) {
  let state = $transport_js.get_cell(sluice.cell);
  $transport_js.set_cell(
    sluice.cell,
    new State(
      $core.advance(state.core, milliseconds),
      state.conns,
      state.bindings,
      state.last_registered,
      state.timers,
      state.next_timer_id,
    ),
  );
  return fire_due(sluice);
}

/**
 * Remove `presence_v1` from the handshake. A client in `Auto` mode thus
 * selects the ripple fallback, and a client that forces `Server` mode fails.
 * Call this function before `connect`.
 */
export function disable_presence(sluice) {
  let state = $transport_js.get_cell(sluice.cell);
  return $transport_js.set_cell(
    sluice.cell,
    new State(
      $core.set_presence_supported(state.core, false),
      state.conns,
      state.bindings,
      state.last_registered,
      state.timers,
      state.next_timer_id,
    ),
  );
}

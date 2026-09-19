/// <reference types="./crdt_sequencer_js.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import {
  Ok,
  Error,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $crdt_relay from "../watershed/crdt_relay.mjs";
import * as $p2p from "../watershed/p2p.mjs";
import * as $timer_js from "../watershed/timer_js.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import {
  openRelay as native_open,
  sendRelay as native_send,
  close as native_close,
  byteSize as byte_size,
} from "./ws_ffi.mjs";

export class Connection extends $CustomType {
  constructor(send, close) {
    super();
    this.send = send;
    this.close = close;
  }
}
export const Connection$Connection = (send, close) =>
  new Connection(send, close);
export const Connection$isConnection = (value) => value instanceof Connection;
export const Connection$Connection$send = (value) => value.send;
export const Connection$Connection$0 = (value) => value.send;
export const Connection$Connection$close = (value) => value.close;
export const Connection$Connection$1 = (value) => value.close;

export class RelayClosed extends $CustomType {}
export const SendError$RelayClosed$const = new RelayClosed();
export const SendError$RelayClosed = () => SendError$RelayClosed$const;
export const SendError$isRelayClosed = (value) => value instanceof RelayClosed;

export class RelayNotReady extends $CustomType {}
export const SendError$RelayNotReady$const = new RelayNotReady();
export const SendError$RelayNotReady = () => SendError$RelayNotReady$const;
export const SendError$isRelayNotReady = (value) =>
  value instanceof RelayNotReady;

export class SendFailed extends $CustomType {}
export const SendError$SendFailed$const = new SendFailed();
export const SendError$SendFailed = () => SendError$SendFailed$const;
export const SendError$isSendFailed = (value) => value instanceof SendFailed;

export class Handlers extends $CustomType {
  constructor(on_message, on_close) {
    super();
    this.on_message = on_message;
    this.on_close = on_close;
  }
}
export const Handlers$Handlers = (on_message, on_close) =>
  new Handlers(on_message, on_close);
export const Handlers$isHandlers = (value) => value instanceof Handlers;
export const Handlers$Handlers$on_message = (value) => value.on_message;
export const Handlers$Handlers$0 = (value) => value.on_message;
export const Handlers$Handlers$on_close = (value) => value.on_close;
export const Handlers$Handlers$1 = (value) => value.on_close;

export class Driver extends $CustomType {
  constructor(open) {
    super();
    this.open = open;
  }
}
export const Driver$Driver = (open) => new Driver(open);
export const Driver$isDriver = (value) => value instanceof Driver;
export const Driver$Driver$open = (value) => value.open;
export const Driver$Driver$0 = (value) => value.open;

class DriverMessage extends $CustomType {
  constructor(raw) {
    super();
    this.raw = raw;
  }
}

class DriverClosed extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}

export class Events extends $CustomType {
  constructor(on_connecting, on_ready, on_envelope, on_synced, on_attested, on_checkpoint_requested, on_unsupported, on_dropped, on_retry, on_error) {
    super();
    this.on_connecting = on_connecting;
    this.on_ready = on_ready;
    this.on_envelope = on_envelope;
    this.on_synced = on_synced;
    this.on_attested = on_attested;
    this.on_checkpoint_requested = on_checkpoint_requested;
    this.on_unsupported = on_unsupported;
    this.on_dropped = on_dropped;
    this.on_retry = on_retry;
    this.on_error = on_error;
  }
}
export const Events$Events = (on_connecting, on_ready, on_envelope, on_synced, on_attested, on_checkpoint_requested, on_unsupported, on_dropped, on_retry, on_error) =>
  new Events(on_connecting,
  on_ready,
  on_envelope,
  on_synced,
  on_attested,
  on_checkpoint_requested,
  on_unsupported,
  on_dropped,
  on_retry,
  on_error);
export const Events$isEvents = (value) => value instanceof Events;
export const Events$Events$on_connecting = (value) => value.on_connecting;
export const Events$Events$0 = (value) => value.on_connecting;
export const Events$Events$on_ready = (value) => value.on_ready;
export const Events$Events$1 = (value) => value.on_ready;
export const Events$Events$on_envelope = (value) => value.on_envelope;
export const Events$Events$2 = (value) => value.on_envelope;
export const Events$Events$on_synced = (value) => value.on_synced;
export const Events$Events$3 = (value) => value.on_synced;
export const Events$Events$on_attested = (value) => value.on_attested;
export const Events$Events$4 = (value) => value.on_attested;
export const Events$Events$on_checkpoint_requested = (value) =>
  value.on_checkpoint_requested;
export const Events$Events$5 = (value) => value.on_checkpoint_requested;
export const Events$Events$on_unsupported = (value) => value.on_unsupported;
export const Events$Events$6 = (value) => value.on_unsupported;
export const Events$Events$on_dropped = (value) => value.on_dropped;
export const Events$Events$7 = (value) => value.on_dropped;
export const Events$Events$on_retry = (value) => value.on_retry;
export const Events$Events$8 = (value) => value.on_retry;
export const Events$Events$on_error = (value) => value.on_error;
export const Events$Events$9 = (value) => value.on_error;

class State extends $CustomType {
  constructor(url, driver, scheduler, retry, events, connection, generation, attempt, pending, ready, order, stalled, skipped, skips, closed) {
    super();
    this.url = url;
    this.driver = driver;
    this.scheduler = scheduler;
    this.retry = retry;
    this.events = events;
    this.connection = connection;
    this.generation = generation;
    this.attempt = attempt;
    this.pending = pending;
    this.ready = ready;
    this.order = order;
    this.stalled = stalled;
    this.skipped = skipped;
    this.skips = skips;
    this.closed = closed;
  }
}

class Relay extends $CustomType {
  constructor(cell) {
    super();
    this.cell = cell;
  }
}

/**
 * The number of refused orders that this client keeps for diagnostics, for
 * each socket. The relay holds the authoritative claims. This list exists so
 * that a test or an operator can see what a lane refused. It has a limit, so
 * that a room full of unreadable records cannot make a diagnostic use
 * unbounded memory in a browser tab.
 */
export const max_reported_skips = 64;

/**
 * A real browser `WebSocket`. The function reads it from `globalThis` at call
 * time, so a bundle that configures no sequencer pays no cost for this
 * module.
 */
export function native_driver() {
  return new Driver(
    (url, handlers) => {
      let $ = native_open(url, handlers.on_message, handlers.on_close);
      if ($ instanceof Ok) {
        let socket = $[0];
        return new Ok(
          new Connection(
            (payload) => { return native_send(socket, payload); },
            () => { return native_close(socket); },
          ),
        );
      } else {
        return $;
      }
    },
  );
}

/**
 * The reconnect delay for the nth consecutive failure, counted from zero. The
 * delays are 250 ms, 500 ms, 1 s, 2 s, and then 5 s for every later
 * attempt.
 */
export function backoff_milliseconds(attempt) {
  if (attempt === 0) {
    return 250;
  } else if (attempt === 1) {
    return 500;
  } else if (attempt === 2) {
    return 1000;
  } else if (attempt === 3) {
    return 2000;
  } else {
    return 5000;
  }
}

/**
 * Build a relay lane. The function opens nothing until you call `connect`.
 *
 * A dropped socket always schedules another attempt, until a `close` call, or
 * until an endpoint shows that it does not support this lane at all.
 */
export function start(url, driver, scheduler, events) {
  let relay = new Relay(
    $transport_js.new_cell(
      new State(
        url,
        driver,
        scheduler,
        true,
        events,
        Option$None$const,
        0,
        0,
        Option$None$const,
        false,
        0,
        false,
        $List$Empty$const,
        0,
        false,
      ),
    ),
  );
  return relay;
}

function current(cell, generation) {
  let state = $transport_js.get_cell(cell);
  return !state.closed && (state.generation === generation);
}

function emit_error(cell, error) {
  return $transport_js.get_cell(cell).events.on_error(error);
}

/**
 * The diagnostic order. The module records it, and it never falls below the
 * order that the client already processed. This value leaves the module inside
 * an attestation only.
 * 
 * @ignore
 */
function note_order(cell, order) {
  let state = $transport_js.get_cell(cell);
  let $ = !state.stalled && (order > state.order);
  if ($) {
    return $transport_js.set_cell(
      cell,
      new State(
        state.url,
        state.driver,
        state.scheduler,
        state.retry,
        state.events,
        state.connection,
        state.generation,
        state.attempt,
        state.pending,
        state.ready,
        order,
        state.stalled,
        state.skipped,
        state.skips,
        state.closed,
      ),
    );
  } else {
    return undefined;
  }
}

/**
 * A gap that this client cannot account for. Freeze the high-water mark. From
 * this point, the socket cannot correctly claim that it holds everything up to
 * a later order.
 * 
 * @ignore
 */
function stall(cell) {
  let state = $transport_js.get_cell(cell);
  return $transport_js.set_cell(
    cell,
    new State(
      state.url,
      state.driver,
      state.scheduler,
      state.retry,
      state.events,
      state.connection,
      state.generation,
      state.attempt,
      state.pending,
      state.ready,
      state.order,
      true,
      state.skipped,
      state.skips,
      state.closed,
    ),
  );
}

function oversize(raw) {
  return byte_size(raw) > $crdt_relay.max_frame_bytes();
}

/**
 * Arm the next attempt, if the policy permits one.
 * 
 * @ignore
 */
function schedule(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.retry;
  if ($) {
    return undefined;
  } else if ($1) {
    let delay = backoff_milliseconds(state.attempt);
    let generation = state.generation;
    return $timer_js.arm(
      state.scheduler,
      delay,
      () => {
        let armed = $transport_js.get_cell(cell);
        let $2 = armed.closed;
        let $3 = armed.generation === generation;
        if (!$2 && $3) {
          $transport_js.set_cell(
            cell,
            new State(
              armed.url,
              armed.driver,
              armed.scheduler,
              armed.retry,
              armed.events,
              armed.connection,
              armed.generation,
              armed.attempt,
              Option$None$const,
              armed.ready,
              armed.order,
              armed.stalled,
              armed.skipped,
              armed.skips,
              armed.closed,
            ),
          );
          return open(cell);
        } else {
          return undefined;
        }
      },
      () => {
        let armed = $transport_js.get_cell(cell);
        return (armed.generation === generation) && !armed.closed;
      },
      (cancel) => {
        let armed = $transport_js.get_cell(cell);
        $transport_js.set_cell(
          cell,
          new State(
            armed.url,
            armed.driver,
            armed.scheduler,
            armed.retry,
            armed.events,
            armed.connection,
            armed.generation,
            armed.attempt + 1,
            new Some(cancel),
            armed.ready,
            armed.order,
            armed.stalled,
            armed.skipped,
            armed.skips,
            armed.closed,
          ),
        );
        return armed.events.on_retry(delay);
      },
    );
  } else {
    return undefined;
  }
}

/**
 * The socket of this generation closed. The function advances the generation
 * first, so a driver that calls back two times cannot schedule two
 * reconnects.
 * 
 * @ignore
 */
function dropped(cell, generation, detail) {
  let $ = current(cell, generation);
  if ($) {
    let state = $transport_js.get_cell(cell);
    $transport_js.set_cell(
      cell,
      new State(
        state.url,
        state.driver,
        state.scheduler,
        state.retry,
        state.events,
        Option$None$const,
        state.generation + 1,
        state.attempt,
        state.pending,
        false,
        0,
        false,
        $List$Empty$const,
        0,
        state.closed,
      ),
    );
    state.events.on_dropped(detail);
    return schedule(cell);
  } else {
    return undefined;
  }
}

/**
 * Close the socket of this generation and retire it. The `on_close` callback
 * of the driver can follow, or it can not follow. In both conditions `dropped`
 * runs exactly one time for this generation, because the second caller finds a
 * stale generation.
 * 
 * @ignore
 */
function hang_up(cell, generation, detail) {
  let state = $transport_js.get_cell(cell);
  let $ = state.connection;
  if ($ instanceof Some) {
    let connection = $[0];
    connection.close();
  } else {
    undefined;
  }
  return dropped(cell, generation, detail);
}

/**
 * Something arrived that this document will not merge.
 *
 * The module reports it to the relay as a `skip` frame that names the exact
 * order. The relay can thus keep the entry for a client that *can* merge it,
 * keep it through the checkpoints of this client, and still accept those
 * checkpoints. The high-water mark can move past that entry only after the
 * skip is on the wire. An entry that a client refuses without a report is an
 * entry that a later attestation would claim to have accounted for, and no
 * client said so.
 *
 * A relay that stamped no order, which is the value `0`, gave this client
 * nothing to name. There is thus nothing to report, and the mark freezes
 * instead.
 *
 * A skip that the module could not *write* is a different condition. The
 * socket is gone, so the module retires it here. It does not leave the socket
 * with the appearance of health and a frozen mark that it can never move
 * again.
 * 
 * @ignore
 */
function refused(cell, generation, order) {
  let state = $transport_js.get_cell(cell);
  let $ = (order > 0) && !state.stalled;
  if ($) {
    let $1 = state.closed;
    let $2 = state.ready;
    let $3 = state.connection;
    if (!$1 && $2 && $3 instanceof Some) {
      let connection = $3[0];
      let $4 = connection.send(
        $crdt_relay.control_to_string(new $crdt_relay.Skip(order)),
      );
      if ($4) {
        let current$1 = $transport_js.get_cell(cell);
        $transport_js.set_cell(
          cell,
          new State(
            current$1.url,
            current$1.driver,
            current$1.scheduler,
            current$1.retry,
            current$1.events,
            current$1.connection,
            current$1.generation,
            current$1.attempt,
            current$1.pending,
            current$1.ready,
            current$1.order,
            current$1.stalled,
            $list.take(
              listPrepend(order, current$1.skipped),
              max_reported_skips,
            ),
            current$1.skips + 1,
            current$1.closed,
          ),
        );
        return note_order(cell, order);
      } else {
        stall(cell);
        return hang_up(cell, generation, "the relay socket was not writable");
      }
    } else {
      return stall(cell);
    }
  } else {
    return stall(cell);
  }
}

/**
 * The endpoint is a sequencer without this lane. The module reports that one
 * time and stops the relay. A retry would ask the same question without an
 * end.
 * 
 * @ignore
 */
function unsupported(cell, generation) {
  let state = $transport_js.get_cell(cell);
  $transport_js.set_cell(
    cell,
    new State(
      state.url,
      state.driver,
      state.scheduler,
      false,
      state.events,
      state.connection,
      state.generation,
      state.attempt,
      state.pending,
      state.ready,
      state.order,
      state.stalled,
      state.skipped,
      state.skips,
      state.closed,
    ),
  );
  state.events.on_unsupported(
    "the sequencer does not advertise " + $crdt_relay.capability,
  );
  return hang_up(
    cell,
    generation,
    ("capability " + $crdt_relay.capability) + " absent",
  );
}

function deliver(cell, generation, frame) {
  let state = $transport_js.get_cell(cell);
  let $ = state.ready;
  if (frame instanceof $crdt_relay.Connected) {
    let $1 = $crdt_relay.supports_relay(frame);
    if ($1) {
      $transport_js.set_cell(
        cell,
        new State(
          state.url,
          state.driver,
          state.scheduler,
          state.retry,
          state.events,
          state.connection,
          state.generation,
          state.attempt,
          state.pending,
          true,
          state.order,
          state.stalled,
          state.skipped,
          state.skips,
          state.closed,
        ),
      );
      return state.events.on_ready();
    } else {
      return unsupported(cell, generation);
    }
  } else if (frame instanceof $crdt_relay.Frame) {
    if ($) {
      let order = frame.order;
      let envelope = frame.envelope;
      let $1 = state.events.on_envelope(envelope);
      if ($1) {
        return note_order(cell, order);
      } else {
        return refused(cell, generation, order);
      }
    } else {
      emit_error(
        cell,
        new $p2p.InvalidEnvelope(
          "sequencer",
          "the relay sent traffic before advertising " + $crdt_relay.capability,
        ),
      );
      return hang_up(cell, generation, "relay handshake violated");
    }
  } else if (frame instanceof $crdt_relay.Synced) {
    if ($) {
      let order = frame.order;
      note_order(cell, order);
      return state.events.on_synced();
    } else {
      emit_error(
        cell,
        new $p2p.InvalidEnvelope(
          "sequencer",
          "the relay sent traffic before advertising " + $crdt_relay.capability,
        ),
      );
      return hang_up(cell, generation, "relay handshake violated");
    }
  } else if (frame instanceof $crdt_relay.Attested) {
    if ($) {
      let order = frame.order;
      let digest = frame.digest;
      note_order(cell, order);
      return state.events.on_attested(digest);
    } else {
      emit_error(
        cell,
        new $p2p.InvalidEnvelope(
          "sequencer",
          "the relay sent traffic before advertising " + $crdt_relay.capability,
        ),
      );
      return hang_up(cell, generation, "relay handshake violated");
    }
  } else if (frame instanceof $crdt_relay.CheckpointRequest) {
    if ($) {
      return state.events.on_checkpoint_requested();
    } else {
      emit_error(
        cell,
        new $p2p.InvalidEnvelope(
          "sequencer",
          "the relay sent traffic before advertising " + $crdt_relay.capability,
        ),
      );
      return hang_up(cell, generation, "relay handshake violated");
    }
  } else if ($) {
    let reason = frame.reason;
    let detail = frame.detail;
    emit_error(
      cell,
      new $p2p.SequencerUnavailable(
        (() => {
          if (detail === "") {
            return reason;
          } else {
            return (reason + ": ") + detail;
          }
        })(),
      ),
    );
    return hang_up(cell, generation, reason);
  } else {
    emit_error(
      cell,
      new $p2p.InvalidEnvelope(
        "sequencer",
        "the relay sent traffic before advertising " + $crdt_relay.capability,
      ),
    );
    return hang_up(cell, generation, "relay handshake violated");
  }
}

/**
 * One frame from the relay, under the generation that requested it.
 * 
 * @ignore
 */
function receive(cell, generation, raw) {
  let $ = current(cell, generation);
  if ($) {
    let $1 = oversize(raw);
    if ($1) {
      emit_error(
        cell,
        new $p2p.InvalidEnvelope(
          "sequencer",
          ((("relay frame of " + $int.to_string(byte_size(raw))) + " bytes exceeds the ") + $int.to_string(
            $crdt_relay.max_frame_bytes(),
          )) + " byte limit",
        ),
      );
      return hang_up(cell, generation, "oversize relay frame");
    } else {
      let $2 = $crdt_relay.decode_server(raw);
      if ($2 instanceof Ok) {
        let frame = $2[0];
        return deliver(cell, generation, frame);
      } else {
        let detail = $2[0];
        emit_error(cell, new $p2p.InvalidEnvelope("sequencer", detail));
        return hang_up(cell, generation, "malformed relay frame");
      }
    }
  } else {
    return undefined;
  }
}

function deliver_driver_event(cell, generation, event, constructing) {
  let $ = current(cell, generation);
  if ($) {
    if (event instanceof DriverMessage) {
      let raw = event.raw;
      return receive(cell, generation, raw);
    } else {
      let detail = event.detail;
      if (constructing) {
        return hang_up(cell, generation, detail);
      } else {
        return dropped(cell, generation, detail);
      }
    }
  } else {
    return undefined;
  }
}

function drain_driver_start(loop$cell, loop$generation, loop$constructing) {
  while (true) {
    let cell = loop$cell;
    let generation = loop$generation;
    let constructing = loop$constructing;
    let $ = $transport_js.get_cell(constructing);
    if ($ instanceof Some) {
      let $1 = $[0];
      if ($1 instanceof $Empty) {
        return $transport_js.set_cell(constructing, Option$None$const);
      } else {
        let events = $1;
        $transport_js.set_cell(constructing, new Some($List$Empty$const));
        let _pipe = events;
        let _pipe$1 = $list.reverse(_pipe);
        $list.each(
          _pipe$1,
          (event) => {
            return deliver_driver_event(cell, generation, event, true);
          },
        );
        loop$cell = cell;
        loop$generation = generation;
        loop$constructing = constructing;
      }
    } else {
      return undefined;
    }
  }
}

function driver_event(cell, generation, constructing, event) {
  let $ = $transport_js.get_cell(constructing);
  if ($ instanceof Some) {
    let events = $[0];
    return $transport_js.set_cell(
      constructing,
      new Some(listPrepend(event, events)),
    );
  } else {
    return deliver_driver_event(cell, generation, event, false);
  }
}

/**
 * Start one connection attempt, under a new generation.
 * 
 * @ignore
 */
function open(cell) {
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return undefined;
  } else {
    let generation = state.generation + 1;
    $transport_js.set_cell(
      cell,
      new State(
        state.url,
        state.driver,
        state.scheduler,
        state.retry,
        state.events,
        Option$None$const,
        generation,
        state.attempt,
        Option$None$const,
        false,
        0,
        false,
        $List$Empty$const,
        0,
        state.closed,
      ),
    );
    state.events.on_connecting();
    let announced = $transport_js.get_cell(cell);
    let $1 = announced.closed || (announced.generation !== generation);
    if ($1) {
      return undefined;
    } else {
      let constructing = $transport_js.new_cell(new Some($List$Empty$const));
      let handlers = new Handlers(
        (raw) => {
          return driver_event(
            cell,
            generation,
            constructing,
            new DriverMessage(raw),
          );
        },
        (detail) => {
          return driver_event(
            cell,
            generation,
            constructing,
            new DriverClosed(detail),
          );
        },
      );
      let $2 = state.driver.open(state.url, handlers);
      if ($2 instanceof Ok) {
        let connection = $2[0];
        let opened = $transport_js.get_cell(cell);
        let $3 = (opened.generation === generation) && !opened.closed;
        if ($3) {
          $transport_js.set_cell(
            cell,
            new State(
              opened.url,
              opened.driver,
              opened.scheduler,
              opened.retry,
              opened.events,
              new Some(connection),
              opened.generation,
              opened.attempt,
              opened.pending,
              opened.ready,
              opened.order,
              opened.stalled,
              opened.skipped,
              opened.skips,
              opened.closed,
            ),
          );
          return drain_driver_start(cell, generation, constructing);
        } else {
          $transport_js.set_cell(constructing, Option$None$const);
          return connection.close();
        }
      } else {
        let detail = $2[0];
        $transport_js.set_cell(constructing, Option$None$const);
        let $3 = current(cell, generation);
        if ($3) {
          emit_error(cell, new $p2p.SequencerUnavailable(detail));
          return dropped(cell, generation, detail);
        } else {
          return undefined;
        }
      }
    }
  }
}

/**
 * Start to connect.
 *
 * This function is separate from `start` on purpose. A driver can deliver its
 * whole conversation from inside `open`. A substitute driver does that, and so
 * does a socket that fails synchronously. An owner that had not stored the
 * relay yet would thus miss every event of the first generation. Store the
 * relay first, and connect second.
 */
export function connect(relay) {
  return open(relay.cell);
}

/**
 * Stop permanently. A second call has no more effect. The function cancels a
 * pending reconnect and the live socket, so a closed relay schedules
 * nothing.
 */
export function close(relay) {
  let cell = relay.cell;
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  if ($) {
    return undefined;
  } else {
    $transport_js.set_cell(
      cell,
      new State(
        state.url,
        state.driver,
        state.scheduler,
        state.retry,
        state.events,
        Option$None$const,
        state.generation,
        state.attempt,
        Option$None$const,
        false,
        state.order,
        state.stalled,
        state.skipped,
        state.skips,
        true,
      ),
    );
    let $1 = state.pending;
    if ($1 instanceof Some) {
      let cancel = $1[0];
      cancel();
    } else {
      undefined;
    }
    let $2 = state.connection;
    if ($2 instanceof Some) {
      let connection = $2[0];
      return connection.close();
    } else {
      return undefined;
    }
  }
}

/**
 * Report that the current session worked. The next drop thus starts the
 * backoff sequence again, and it does not continue the earlier sequence.
 */
export function healthy(relay) {
  let state = $transport_js.get_cell(relay.cell);
  return $transport_js.set_cell(
    relay.cell,
    new State(
      state.url,
      state.driver,
      state.scheduler,
      state.retry,
      state.events,
      state.connection,
      state.generation,
      0,
      state.pending,
      state.ready,
      state.order,
      state.stalled,
      state.skipped,
      state.skips,
      state.closed,
    ),
  );
}

function write(relay, payload) {
  let state = $transport_js.get_cell(relay.cell);
  let $ = state.closed;
  let $1 = state.ready;
  let $2 = state.connection;
  if ($) {
    return new Error(SendError$RelayClosed$const);
  } else if ($1) {
    if ($2 instanceof Some) {
      let connection = $2[0];
      let $3 = connection.send(payload);
      if ($3) {
        return new Ok(undefined);
      } else {
        return new Error(SendError$SendFailed$const);
      }
    } else {
      return new Error(SendError$RelayNotReady$const);
    }
  } else {
    return new Error(SendError$RelayNotReady$const);
  }
}

/**
 * Write one encoded envelope, without a change. A relay that is not ready
 * drops it. The caller is on another path, and a queue here would deliver the
 * history of a document in the wrong order after a reconnect.
 *
 * An `Error` result means that the string did not reach an open socket. The
 * `SendError` names which of the three ways that happened. The caller must
 * act on that result immediately, because this module never writes again.
 */
export function send_envelope(relay, payload) {
  return write(relay, payload);
}

/**
 * Attest a digest for the state that this client published, and quote the
 * highest order that this client accounted for, which it processed or reported
 * as skipped. The relay answers on `on_attested`.
 */
export function attest(relay, digest) {
  let state = $transport_js.get_cell(relay.cell);
  return write(
    relay,
    $crdt_relay.control_to_string(new $crdt_relay.Attest(digest, state.order)),
  );
}

/**
 * Tell the relay which optional control frames this client understands.
 *
 * The client sends this frame after the `hello` frame that admits the
 * connection. The first frame of a relay must be an envelope, so this frame
 * cannot come before it. This frame is the only reason for a relay to send a
 * `CheckpointRequest` frame. A client that never calls this function receives
 * the same treatment as a client that a developer built before the frame
 * existed: the relay never sends it one.
 */
export function declare_support(relay) {
  return write(
    relay,
    $crdt_relay.control_to_string(new $crdt_relay.Supports(true)),
  );
}

/**
 * Drop the current socket, and keep the lane.
 *
 * Use this function when an owner found that the socket was gone by a write to
 * it. The module retires the generation, runs `on_dropped`, and schedules the
 * reconnect of the policy, exactly as it would for a close that the driver
 * reported. The function does not change a relay that is already closed, or a
 * relay that has no socket.
 */
export function abort(relay, detail) {
  let cell = relay.cell;
  let state = $transport_js.get_cell(cell);
  let $ = state.closed;
  let $1 = state.connection;
  if ($) {
    return undefined;
  } else if ($1 instanceof Some) {
    return hang_up(cell, state.generation, detail);
  } else {
    return undefined;
  }
}

/**
 * Whether the capability handshake has completed on the current socket.
 */
export function is_ready(relay) {
  return $transport_js.get_cell(relay.cell).ready;
}

export function is_closed(relay) {
  return $transport_js.get_cell(relay.cell).closed;
}

/**
 * The highest diagnostic order processed on this lane.
 */
export function last_order(relay) {
  return $transport_js.get_cell(relay.cell).order;
}

/**
 * The most recent orders that this socket reported as skipped, oldest first.
 * There are `max_reported_skips` of them at most. `skip_count` gives the
 * number that the socket reported.
 */
export function skipped_orders(relay) {
  return $list.reverse($transport_js.get_cell(relay.cell).skipped);
}

/**
 * The number of refusals that this socket reported, whether or not they are
 * still in `skipped_orders`.
 */
export function skip_count(relay) {
  return $transport_js.get_cell(relay.cell).skips;
}

/**
 * The number of consecutive failed attempts after the last `healthy` call.
 */
export function attempts(relay) {
  return $transport_js.get_cell(relay.cell).attempt;
}

/**
 * Whether a reconnect is armed.
 */
export function is_retrying(relay) {
  return !($transport_js.get_cell(relay.cell).pending instanceof None);
}

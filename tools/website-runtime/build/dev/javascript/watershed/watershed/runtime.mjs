/// <reference types="./runtime.d.mts" />
import * as $promise from "../../gleam_javascript/gleam/javascript/promise.mjs";
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bool from "../../gleam_stdlib/gleam/bool.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $uri from "../../gleam_stdlib/gleam/uri.mjs";
import * as $message from "../../spillway/spillway/message.mjs";
import * as $nack from "../../spillway/spillway/nack.mjs";
import * as $types from "../../spillway/spillway/types.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  makeError,
  isEqual,
} from "../gleam.mjs";
import * as $callback_js from "../watershed/callback_js.mjs";
import * as $channel from "../watershed/channel.mjs";
import { AcquireResolved, ClaimResolved } from "../watershed/channel.mjs";
import * as $claims_kernel from "../watershed/claims_kernel.mjs";
import * as $git_storage from "../watershed/git_storage.mjs";
import * as $id from "../watershed/id.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";
import * as $or_map_kernel from "../watershed/or_map_kernel.mjs";
import * as $ordered_collection_kernel from "../watershed/ordered_collection_kernel.mjs";
import * as $pact_map_kernel from "../watershed/pact_map_kernel.mjs";
import * as $register_collection_kernel from "../watershed/register_collection_kernel.mjs";
import * as $rich_text from "../watershed/rich_text.mjs";
import * as $runtime_core from "../watershed/runtime_core.mjs";
import * as $summary_policy from "../watershed/summary_policy.mjs";
import * as $task_manager_kernel from "../watershed/task_manager_kernel.mjs";
import * as $text_kernel from "../watershed/text_kernel.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import * as $wire from "../watershed/wire.mjs";
import * as $socket from "../watershed/wire/socket.mjs";
import * as $summary_blob from "../watershed/wire/summary_blob.mjs";
import { byteSize as payload_byte_size } from "./ws_ffi.mjs";

const FILEPATH = "src/watershed/runtime.gleam";

export class TransportHandle extends $CustomType {
  constructor(push, close, drop, hold, resume) {
    super();
    this.push = push;
    this.close = close;
    this.drop = drop;
    this.hold = hold;
    this.resume = resume;
  }
}
export const TransportHandle$TransportHandle = (push, close, drop, hold, resume) =>
  new TransportHandle(push, close, drop, hold, resume);
export const TransportHandle$isTransportHandle = (value) =>
  value instanceof TransportHandle;
export const TransportHandle$TransportHandle$push = (value) => value.push;
export const TransportHandle$TransportHandle$0 = (value) => value.push;
export const TransportHandle$TransportHandle$close = (value) => value.close;
export const TransportHandle$TransportHandle$1 = (value) => value.close;
export const TransportHandle$TransportHandle$drop = (value) => value.drop;
export const TransportHandle$TransportHandle$2 = (value) => value.drop;
export const TransportHandle$TransportHandle$hold = (value) => value.hold;
export const TransportHandle$TransportHandle$3 = (value) => value.hold;
export const TransportHandle$TransportHandle$resume = (value) => value.resume;
export const TransportHandle$TransportHandle$4 = (value) => value.resume;

export class TransportCallbacks extends $CustomType {
  constructor(on_event, on_join, on_close) {
    super();
    this.on_event = on_event;
    this.on_join = on_join;
    this.on_close = on_close;
  }
}
export const TransportCallbacks$TransportCallbacks = (on_event, on_join, on_close) =>
  new TransportCallbacks(on_event, on_join, on_close);
export const TransportCallbacks$isTransportCallbacks = (value) =>
  value instanceof TransportCallbacks;
export const TransportCallbacks$TransportCallbacks$on_event = (value) =>
  value.on_event;
export const TransportCallbacks$TransportCallbacks$0 = (value) =>
  value.on_event;
export const TransportCallbacks$TransportCallbacks$on_join = (value) =>
  value.on_join;
export const TransportCallbacks$TransportCallbacks$1 = (value) => value.on_join;
export const TransportCallbacks$TransportCallbacks$on_close = (value) =>
  value.on_close;
export const TransportCallbacks$TransportCallbacks$2 = (value) =>
  value.on_close;

export class Transport extends $CustomType {
  constructor(connect) {
    super();
    this.connect = connect;
  }
}
export const Transport$Transport = (connect) => new Transport(connect);
export const Transport$isTransport = (value) => value instanceof Transport;
export const Transport$Transport$connect = (value) => value.connect;
export const Transport$Transport$0 = (value) => value.connect;

class TransportJoined extends $CustomType {}
const TransportEvent$TransportJoined$const = new TransportJoined();

class TransportClosed extends $CustomType {}
const TransportEvent$TransportClosed$const = new TransportClosed();

class TransportReceived extends $CustomType {
  constructor(event, payload) {
    super();
    this.event = event;
    this.payload = payload;
  }
}

export class Pending extends $CustomType {
  constructor(outcome) {
    super();
    this.outcome = outcome;
  }
}
export const ClaimSubmitReply$Pending = (outcome) => new Pending(outcome);
export const ClaimSubmitReply$isPending = (value) => value instanceof Pending;
export const ClaimSubmitReply$Pending$outcome = (value) => value.outcome;
export const ClaimSubmitReply$Pending$0 = (value) => value.outcome;

export class AlreadyClaimed extends $CustomType {
  constructor(current_value) {
    super();
    this.current_value = current_value;
  }
}
export const ClaimSubmitReply$AlreadyClaimed = (current_value) =>
  new AlreadyClaimed(current_value);
export const ClaimSubmitReply$isAlreadyClaimed = (value) =>
  value instanceof AlreadyClaimed;
export const ClaimSubmitReply$AlreadyClaimed$current_value = (value) =>
  value.current_value;
export const ClaimSubmitReply$AlreadyClaimed$0 = (value) => value.current_value;

export class AlreadyPendingLocally extends $CustomType {}
export const ClaimSubmitReply$AlreadyPendingLocally$const =
  new AlreadyPendingLocally();
export const ClaimSubmitReply$AlreadyPendingLocally = () =>
  ClaimSubmitReply$AlreadyPendingLocally$const;
export const ClaimSubmitReply$isAlreadyPendingLocally = (value) =>
  value instanceof AlreadyPendingLocally;

export class WrongChannelType extends $CustomType {}
export const ClaimSubmitReply$WrongChannelType$const = new WrongChannelType();
export const ClaimSubmitReply$WrongChannelType = () =>
  ClaimSubmitReply$WrongChannelType$const;
export const ClaimSubmitReply$isWrongChannelType = (value) =>
  value instanceof WrongChannelType;

/**
 * A `presence_state` snapshot, which the runtime does not decode. The
 * runtime has no decoder for the metadata of the application, and the
 * operation lane does have one. The payload is the raw event JSON, a typed
 * boundary the typed driver decodes with its own `presence.config_decoder`.
 */
export class PresenceState extends $CustomType {
  constructor(payload) {
    super();
    this.payload = payload;
  }
}
export const PresenceFrame$PresenceState = (payload) =>
  new PresenceState(payload);
export const PresenceFrame$isPresenceState = (value) =>
  value instanceof PresenceState;
export const PresenceFrame$PresenceState$payload = (value) => value.payload;
export const PresenceFrame$PresenceState$0 = (value) => value.payload;

export class PresenceDiff extends $CustomType {
  constructor(payload) {
    super();
    this.payload = payload;
  }
}
export const PresenceFrame$PresenceDiff = (payload) =>
  new PresenceDiff(payload);
export const PresenceFrame$isPresenceDiff = (value) =>
  value instanceof PresenceDiff;
export const PresenceFrame$PresenceDiff$payload = (value) => value.payload;
export const PresenceFrame$PresenceDiff$0 = (value) => value.payload;

export class PresenceError extends $CustomType {
  constructor(payload) {
    super();
    this.payload = payload;
  }
}
export const PresenceFrame$PresenceError = (payload) =>
  new PresenceError(payload);
export const PresenceFrame$isPresenceError = (value) =>
  value instanceof PresenceError;
export const PresenceFrame$PresenceError$payload = (value) => value.payload;
export const PresenceFrame$PresenceError$0 = (value) => value.payload;

/**
 * A new document session settled. The frame carries a new client id from
 * the server, and the features that this handshake negotiated. The runtime
 * sends it after the first handshake and after every reconnect, and a
 * driver rejoins on it.
 */
export class PresenceSession extends $CustomType {
  constructor(client_id, presence_v1) {
    super();
    this.client_id = client_id;
    this.presence_v1 = presence_v1;
  }
}
export const PresenceFrame$PresenceSession = (client_id, presence_v1) =>
  new PresenceSession(client_id, presence_v1);
export const PresenceFrame$isPresenceSession = (value) =>
  value instanceof PresenceSession;
export const PresenceFrame$PresenceSession$client_id = (value) =>
  value.client_id;
export const PresenceFrame$PresenceSession$0 = (value) => value.client_id;
export const PresenceFrame$PresenceSession$presence_v1 = (value) =>
  value.presence_v1;
export const PresenceFrame$PresenceSession$1 = (value) => value.presence_v1;

/**
 * The session ended. Every presence that the server held for it is gone.
 */
export class PresenceSessionLost extends $CustomType {}
export const PresenceFrame$PresenceSessionLost$const =
  new PresenceSessionLost();
export const PresenceFrame$PresenceSessionLost = () =>
  PresenceFrame$PresenceSessionLost$const;
export const PresenceFrame$isPresenceSessionLost = (value) =>
  value instanceof PresenceSessionLost;

class Subscriber extends $CustomType {
  constructor(id, address, handler) {
    super();
    this.id = id;
    this.address = address;
    this.handler = handler;
  }
}

class Connecting extends $CustomType {}
const Phase$Connecting$const = new Connecting();

/**
 * The socket is closed and the runtime is doing the handshake again. This
 * state holds the core from before the reconnect.
 * 
 * @ignore
 */
class Reconnecting extends $CustomType {
  constructor(core) {
    super();
    this.core = core;
  }
}

/**
 * The runtime is connected. `resubmit_at` is `Some(checkpoint)` while a
 * reconnect still catches up to the point at which the runtime can resubmit
 * the operations with no ack. It is `None` after the runtime is
 * synchronized.
 * 
 * @ignore
 */
class Ready extends $CustomType {
  constructor(core, resubmit_at) {
    super();
    this.core = core;
    this.resubmit_at = resubmit_at;
  }
}

class Failed extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}

class PendingSummary extends $CustomType {
  constructor(tree_id, client_sequence_number, proposal_sequence_number, resolve) {
    super();
    this.tree_id = tree_id;
    this.client_sequence_number = client_sequence_number;
    this.proposal_sequence_number = proposal_sequence_number;
    this.resolve = resolve;
  }
}

class State extends $CustomType {
  constructor(connect_message, http_base_url, channel, phase, subscribers, ripple_subscribers, presence_subscribers, supported_features, claim_waiters, acquire_waiters, on_ready, ready_fired, bootstrap_generation, bootstrap, auto_summary, summary_armed, pending_summary, scheduler) {
    super();
    this.connect_message = connect_message;
    this.http_base_url = http_base_url;
    this.channel = channel;
    this.phase = phase;
    this.subscribers = subscribers;
    this.ripple_subscribers = ripple_subscribers;
    this.presence_subscribers = presence_subscribers;
    this.supported_features = supported_features;
    this.claim_waiters = claim_waiters;
    this.acquire_waiters = acquire_waiters;
    this.on_ready = on_ready;
    this.ready_fired = ready_fired;
    this.bootstrap_generation = bootstrap_generation;
    this.bootstrap = bootstrap;
    this.auto_summary = auto_summary;
    this.summary_armed = summary_armed;
    this.pending_summary = pending_summary;
    this.scheduler = scheduler;
  }
}

class Bootstrap extends $CustomType {
  constructor(batches, operation_count, payload_bytes, draining) {
    super();
    this.batches = batches;
    this.operation_count = operation_count;
    this.payload_bytes = payload_bytes;
    this.draining = draining;
  }
}

class Runtime extends $CustomType {
  constructor(cell) {
    super();
    this.cell = cell;
  }
}

class SubscriptionToken extends $CustomType {
  constructor(runtime, id) {
    super();
    this.runtime = runtime;
    this.id = id;
  }
}

export class Diagnostics extends $CustomType {
  constructor(phase, client_id, last_seen_sequence_number, next_client_sequence_number, in_flight_count, buffered_out_of_order_count, resubmit_checkpoint, synced, operations_since_summary, summary_pending) {
    super();
    this.phase = phase;
    this.client_id = client_id;
    this.last_seen_sequence_number = last_seen_sequence_number;
    this.next_client_sequence_number = next_client_sequence_number;
    this.in_flight_count = in_flight_count;
    this.buffered_out_of_order_count = buffered_out_of_order_count;
    this.resubmit_checkpoint = resubmit_checkpoint;
    this.synced = synced;
    this.operations_since_summary = operations_since_summary;
    this.summary_pending = summary_pending;
  }
}
export const Diagnostics$Diagnostics = (phase, client_id, last_seen_sequence_number, next_client_sequence_number, in_flight_count, buffered_out_of_order_count, resubmit_checkpoint, synced, operations_since_summary, summary_pending) =>
  new Diagnostics(phase,
  client_id,
  last_seen_sequence_number,
  next_client_sequence_number,
  in_flight_count,
  buffered_out_of_order_count,
  resubmit_checkpoint,
  synced,
  operations_since_summary,
  summary_pending);
export const Diagnostics$isDiagnostics = (value) =>
  value instanceof Diagnostics;
export const Diagnostics$Diagnostics$phase = (value) => value.phase;
export const Diagnostics$Diagnostics$0 = (value) => value.phase;
export const Diagnostics$Diagnostics$client_id = (value) => value.client_id;
export const Diagnostics$Diagnostics$1 = (value) => value.client_id;
export const Diagnostics$Diagnostics$last_seen_sequence_number = (value) =>
  value.last_seen_sequence_number;
export const Diagnostics$Diagnostics$2 = (value) =>
  value.last_seen_sequence_number;
export const Diagnostics$Diagnostics$next_client_sequence_number = (value) =>
  value.next_client_sequence_number;
export const Diagnostics$Diagnostics$3 = (value) =>
  value.next_client_sequence_number;
export const Diagnostics$Diagnostics$in_flight_count = (value) =>
  value.in_flight_count;
export const Diagnostics$Diagnostics$4 = (value) => value.in_flight_count;
export const Diagnostics$Diagnostics$buffered_out_of_order_count = (value) =>
  value.buffered_out_of_order_count;
export const Diagnostics$Diagnostics$5 = (value) =>
  value.buffered_out_of_order_count;
export const Diagnostics$Diagnostics$resubmit_checkpoint = (value) =>
  value.resubmit_checkpoint;
export const Diagnostics$Diagnostics$6 = (value) => value.resubmit_checkpoint;
export const Diagnostics$Diagnostics$synced = (value) => value.synced;
export const Diagnostics$Diagnostics$7 = (value) => value.synced;
export const Diagnostics$Diagnostics$operations_since_summary = (value) =>
  value.operations_since_summary;
export const Diagnostics$Diagnostics$8 = (value) =>
  value.operations_since_summary;
export const Diagnostics$Diagnostics$summary_pending = (value) =>
  value.summary_pending;
export const Diagnostics$Diagnostics$9 = (value) => value.summary_pending;

/**
 * The server nacks a submission of more than 100 operations. Split a resubmit
 * into chunks to stay below that limit.
 * 
 * @ignore
 */
const max_operations_per_submission = 100;

/**
 * The default transport: a Phoenix socket over `transport_js`. Phoenix joins
 * again by itself after a socket drop, and it runs `on_join` again. The runtime
 * thus never calls `connect` a second time.
 * 
 * @ignore
 */
function phoenix_transport(url, topic, join_payload) {
  return new Transport(
    (callbacks) => {
      let channel = $transport_js.connect(
        url,
        topic,
        $json.to_string(join_payload),
        callbacks.on_event,
        callbacks.on_join,
        callbacks.on_close,
      );
      return new TransportHandle(
        (event, payload) => {
          return $transport_js.push(channel, event, $json.to_string(payload));
        },
        () => { return $transport_js.close(channel); },
        () => { return $transport_js.drop_socket(channel); },
        () => { return $transport_js.hold_socket(channel); },
        () => { return $transport_js.resume_socket(channel); },
      );
    },
  );
}

/**
 * Derive the base HTTP or HTTPS URL for the git-storage calls, from the
 * Phoenix socket URL. For example,
 * `ws://localhost:4000/socket/websocket?vsn=2.0.0` gives
 * `http://localhost:4000`. A `wss` scheme gives `https`, and every other
 * scheme gives `http`.
 * 
 * @ignore
 */
function http_base_from_socket_url(url) {
  let $ = $uri.parse(url);
  if ($ instanceof Ok) {
    let parsed = $[0];
    let _block;
    let $1 = parsed.scheme;
    if ($1 instanceof Some) {
      let $2 = $1[0];
      if ($2 === "wss") {
        _block = "https";
      } else if ($2 === "https") {
        _block = "https";
      } else {
        _block = "http";
      }
    } else {
      _block = "http";
    }
    let scheme = _block;
    let host = $option.unwrap(parsed.host, "localhost");
    let _block$1;
    let $2 = parsed.port;
    if ($2 instanceof Some) {
      let p = $2[0];
      _block$1 = ":" + $int.to_string(p);
    } else {
      _block$1 = "";
    }
    let port = _block$1;
    return ((scheme + "://") + host) + port;
  } else {
    return url;
  }
}

function observe(context, callback) {
  let $ = $callback_js.capture(callback);
  if ($ instanceof Ok) {
    return undefined;
  } else {
    let reason = $[0];
    return $callback_js.report(
      (("sequenced runtime " + context) + ": ") + reason,
    );
  }
}

function cell_get(cell) {
  return $transport_js.get_cell(cell);
}

function notify_presence(cell, frame) {
  let state = cell_get(cell);
  return $list.each(
    state.presence_subscribers,
    (handler) => {
      return observe("presence subscriber", () => { return handler(frame); });
    },
  );
}

/**
 * Send an inbound ephemeral `signal` broadcast to the ripple subscribers. The
 * wire event is the `"signal"` event of Fluid, and watershed calls it a
 * *ripple*. The function drops a malformed payload and reports nothing,
 * because a ripple is best-effort.
 * 
 * @ignore
 */
function on_ripple(cell, payload) {
  let $ = $json.parse(payload, $socket.ripple_message_decoder());
  if ($ instanceof Ok) {
    let ripple = $[0];
    let state = cell_get(cell);
    return $list.each(
      state.ripple_subscribers,
      (handler) => {
        return observe("ripple subscriber", () => { return handler(ripple); });
      },
    );
  } else {
    return undefined;
  }
}

/**
 * Announce that a live session ended, and only when one was live. A socket
 * that never reached `Ready`, and a socket that the runtime already knows is
 * closed, both hold no presence. The runtime must not report a lost presence
 * two times.
 * 
 * @ignore
 */
function notify_session_lost(cell, previous) {
  if (previous instanceof Connecting) {
    return undefined;
  } else if (previous instanceof Reconnecting) {
    return undefined;
  } else if (previous instanceof Ready) {
    return notify_presence(cell, PresenceFrame$PresenceSessionLost$const);
  } else {
    return undefined;
  }
}

function cell_set(cell, state) {
  return $transport_js.set_cell(cell, state);
}

/**
 * Run the `on_ready` callback exactly one time.
 * 
 * @ignore
 */
function fire_ready(cell, result) {
  let state = cell_get(cell);
  let $ = state.ready_fired;
  if ($) {
    return undefined;
  } else {
    cell_set(
      cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        state.phase,
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        state.acquire_waiters,
        state.on_ready,
        true,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        state.pending_summary,
        state.scheduler,
      ),
    );
    return observe("on_ready", () => { return state.on_ready(result); });
  }
}

function abort_pending_summary(state) {
  let $ = state.pending_summary;
  if ($ instanceof Some) {
    let pending = $[0];
    return observe(
      "summary publication",
      () => {
        return pending.resolve(new Error("summary publication was interrupted"));
      },
    );
  } else {
    return undefined;
  }
}

function abort_outcome_waiters(state) {
  let _pipe = $dict.values(state.claim_waiters);
  $list.each(
    _pipe,
    (resolve_outcome) => {
      return observe(
        "claim aborted",
        () => {
          return resolve_outcome($claims_kernel.ClaimOutcome$Aborted$const);
        },
      );
    },
  );
  let _pipe$1 = $dict.values(state.acquire_waiters);
  return $list.each(
    _pipe$1,
    (resolve_outcome) => {
      return observe(
        "acquire aborted",
        () => {
          return resolve_outcome(
            $ordered_collection_kernel.AcquireOutcome$Aborted$const,
          );
        },
      );
    },
  );
}

function fail(cell, reason) {
  let state = cell_get(cell);
  cell_set(
    cell,
    new State(
      state.connect_message,
      state.http_base_url,
      state.channel,
      new Failed(reason),
      state.subscribers,
      state.ripple_subscribers,
      state.presence_subscribers,
      state.supported_features,
      $dict.new$(),
      $dict.new$(),
      state.on_ready,
      state.ready_fired,
      state.bootstrap_generation + 1,
      Option$None$const,
      state.auto_summary,
      state.summary_armed,
      Option$None$const,
      state.scheduler,
    ),
  );
  abort_outcome_waiters(state);
  abort_pending_summary(state);
  fire_ready(cell, new Error(reason));
  return notify_session_lost(cell, state.phase);
}

function nack_is_fatal(item) {
  let $ = item.content.error_type;
  if ($ instanceof $nack.ThrottlingError) {
    return item.content.code === 413;
  } else if ($ instanceof $nack.InvalidScopeError) {
    return true;
  } else if ($ instanceof $nack.BadRequestError) {
    return item.content.code === 413;
  } else {
    return true;
  }
}

function on_nack(cell, payload) {
  let $ = $json.parse(payload, $socket.nacks_decoder());
  if ($ instanceof Ok) {
    let nacks = $[0];
    let $1 = $list.any(nacks, nack_is_fatal);
    if ($1) {
      return fail(cell, "fatal nack from server");
    } else {
      let state = cell_get(cell);
      let $2 = state.phase;
      let $3 = state.channel;
      if ($3 instanceof Some) {
        if ($2 instanceof Connecting) {
          return undefined;
        } else if ($2 instanceof Reconnecting) {
          return undefined;
        } else if ($2 instanceof Ready) {
          let channel = $3[0];
          let core = $2.core;
          cell_set(
            cell,
            new State(
              state.connect_message,
              state.http_base_url,
              state.channel,
              new Reconnecting(core),
              state.subscribers,
              state.ripple_subscribers,
              state.presence_subscribers,
              state.supported_features,
              state.claim_waiters,
              state.acquire_waiters,
              state.on_ready,
              state.ready_fired,
              state.bootstrap_generation,
              state.bootstrap,
              state.auto_summary,
              state.summary_armed,
              state.pending_summary,
              state.scheduler,
            ),
          );
          notify_session_lost(cell, state.phase);
          return channel.drop();
        } else {
          return undefined;
        }
      } else if ($2 instanceof Connecting) {
        return undefined;
      } else if ($2 instanceof Reconnecting) {
        return undefined;
      } else if ($2 instanceof Ready) {
        return undefined;
      } else {
        return undefined;
      }
    }
  } else {
    return fail(cell, "malformed nack payload");
  }
}

function resolve_pending_summary(cell, outcome) {
  let state = cell_get(cell);
  let $ = state.pending_summary;
  if ($ instanceof Some) {
    let pending = $[0];
    cell_set(
      cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        state.phase,
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        state.acquire_waiters,
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        Option$None$const,
        state.scheduler,
      ),
    );
    return observe(
      "summary publication",
      () => { return pending.resolve(outcome); },
    );
  } else {
    return undefined;
  }
}

function push_json(channel, event, payload) {
  return channel.push(event, payload);
}

/**
 * Stamp the summarize operation that references the uploaded snapshot tree,
 * and push it. The function reads the live state again, so it builds the
 * operation from the current core. The client sequence number of that
 * operation thus stays above the number of every edit that arrived during the
 * asynchronous upload.
 * 
 * @ignore
 */
function finish_summarize(cell, tree_sha) {
  let state = cell_get(cell);
  let $ = state.phase;
  let $1 = state.channel;
  let $2 = state.pending_summary;
  if ($1 instanceof Some) {
    if ($2 instanceof Some) {
      if ($ instanceof Connecting) {
        return resolve_pending_summary(
          cell,
          new Error("summary publication was interrupted"),
        );
      } else if ($ instanceof Reconnecting) {
        return resolve_pending_summary(
          cell,
          new Error("summary publication was interrupted"),
        );
      } else if ($ instanceof Ready) {
        let $3 = $.resubmit_at;
        if ($3 instanceof Some) {
          return resolve_pending_summary(
            cell,
            new Error("summary publication was interrupted"),
          );
        } else {
          let channel = $1[0];
          let pending = $2[0];
          let core = $.core;
          let $4 = $runtime_core.build_summarize(
            core,
            tree_sha,
            "watershed summary",
          );
          let core$1 = $4[0];
          let outbound = $4[1];
          cell_set(
            cell,
            new State(
              state.connect_message,
              state.http_base_url,
              state.channel,
              new Ready(core$1, Option$None$const),
              state.subscribers,
              state.ripple_subscribers,
              state.presence_subscribers,
              state.supported_features,
              state.claim_waiters,
              state.acquire_waiters,
              state.on_ready,
              state.ready_fired,
              state.bootstrap_generation,
              state.bootstrap,
              state.auto_summary,
              state.summary_armed,
              new Some(
                new PendingSummary(
                  tree_sha,
                  outbound.client_sequence_number,
                  pending.proposal_sequence_number,
                  pending.resolve,
                ),
              ),
              state.scheduler,
            ),
          );
          return push_json(
            channel,
            "submitOp",
            $socket.encode_submit_operation(
              core$1.client_id,
              toList([toList([outbound])]),
            ),
          );
        }
      } else {
        return resolve_pending_summary(
          cell,
          new Error("summary publication was interrupted"),
        );
      }
    } else if ($ instanceof Connecting) {
      return resolve_pending_summary(
        cell,
        new Error("summary publication was interrupted"),
      );
    } else if ($ instanceof Reconnecting) {
      return resolve_pending_summary(
        cell,
        new Error("summary publication was interrupted"),
      );
    } else if ($ instanceof Ready) {
      let $3 = $.resubmit_at;
      if ($3 instanceof Some) {
        return resolve_pending_summary(
          cell,
          new Error("summary publication was interrupted"),
        );
      } else {
        return undefined;
      }
    } else {
      return resolve_pending_summary(
        cell,
        new Error("summary publication was interrupted"),
      );
    }
  } else if ($ instanceof Connecting) {
    return resolve_pending_summary(
      cell,
      new Error("summary publication was interrupted"),
    );
  } else if ($ instanceof Reconnecting) {
    return resolve_pending_summary(
      cell,
      new Error("summary publication was interrupted"),
    );
  } else if ($ instanceof Ready) {
    let $3 = $.resubmit_at;
    if ($3 instanceof Some) {
      return resolve_pending_summary(
        cell,
        new Error("summary publication was interrupted"),
      );
    } else {
      return resolve_pending_summary(
        cell,
        new Error("summary publication was interrupted"),
      );
    }
  } else {
    return resolve_pending_summary(
      cell,
      new Error("summary publication was interrupted"),
    );
  }
}

/**
 * Summarize the current confirmed state of the document to the storage of
 * floodgate. A later client can then start from that snapshot, and it does not
 * replay the full operation history. The promise resolves after `summaryAck`
 * with the published Git commit ID. The connection must be synchronized, and
 * the token must carry the `summary:write` scope.
 *
 * The upload is asynchronous. The sequence number
 * of that operation comes from the live core at push time, and not at the
 * start of the upload, so a concurrent local edit cannot collide with it.
 */
export function summarize(runtime) {
  let cell = runtime.cell;
  let state = cell_get(cell);
  let $ = state.pending_summary;
  if ($ instanceof Some) {
    return $promise.resolve(
      new Error("a summary publication is already pending"),
    );
  } else {
    let $1 = state.phase;
    let $2 = state.channel;
    if ($2 instanceof Some) {
      if ($1 instanceof Connecting) {
        return $promise.resolve(
          new Error(
            "summarize is only available once the connection is fully synced",
          ),
        );
      } else if ($1 instanceof Reconnecting) {
        return $promise.resolve(
          new Error(
            "summarize is only available once the connection is fully synced",
          ),
        );
      } else if ($1 instanceof Ready) {
        let $3 = $1.resubmit_at;
        if ($3 instanceof Some) {
          return $promise.resolve(
            new Error(
              "summarize is only available once the connection is fully synced",
            ),
          );
        } else {
          let core = $1.core;
          let $4 = state.connect_message.token;
          if ($4 instanceof Some) {
            let token = $4[0];
            let $5 = $runtime_core.is_synced(core);
            if ($5) {
              let $6 = $promise.start();
              let published = $6[0];
              let resolve = $6[1];
              cell_set(
                cell,
                new State(
                  state.connect_message,
                  state.http_base_url,
                  state.channel,
                  state.phase,
                  state.subscribers,
                  state.ripple_subscribers,
                  state.presence_subscribers,
                  state.supported_features,
                  state.claim_waiters,
                  state.acquire_waiters,
                  state.on_ready,
                  state.ready_fired,
                  state.bootstrap_generation,
                  state.bootstrap,
                  state.auto_summary,
                  state.summary_armed,
                  new Some(
                    new PendingSummary("", -1, Option$None$const, resolve),
                  ),
                  state.scheduler,
                ),
              );
              let _block;
              let _pipe = $git_storage.upload_summary(
                state.http_base_url,
                state.connect_message.tenant_id,
                token,
                core.last_seen_sequence_number,
                $runtime_core.summary_members(core),
                $runtime_core.summary_channels(core),
              );
              _block = $promise.map(
                _pipe,
                (result) => {
                  if (result instanceof Ok) {
                    let tree_sha = result[0];
                    return finish_summarize(cell, tree_sha);
                  } else {
                    let error = result[0];
                    return resolve_pending_summary(
                      cell,
                      new Error($git_storage.error_to_string(error)),
                    );
                  }
                },
              );
              let $7 = _block;
              
              return published;
            } else {
              return $promise.resolve(
                new Error(
                  "summarize requires the client to be caught up; retry once " + "in-flight edits have been acknowledged",
                ),
              );
            }
          } else {
            return $promise.resolve(
              new Error("summarize requires an auth token"),
            );
          }
        }
      } else {
        return $promise.resolve(
          new Error(
            "summarize is only available once the connection is fully synced",
          ),
        );
      }
    } else if ($1 instanceof Connecting) {
      return $promise.resolve(
        new Error(
          "summarize is only available once the connection is fully synced",
        ),
      );
    } else if ($1 instanceof Reconnecting) {
      return $promise.resolve(
        new Error(
          "summarize is only available once the connection is fully synced",
        ),
      );
    } else if ($1 instanceof Ready) {
      let $3 = $1.resubmit_at;
      if ($3 instanceof Some) {
        return $promise.resolve(
          new Error(
            "summarize is only available once the connection is fully synced",
          ),
        );
      } else {
        return $promise.resolve(
          new Error(
            "summarize is only available once the connection is fully synced",
          ),
        );
      }
    } else {
      return $promise.resolve(
        new Error(
          "summarize is only available once the connection is fully synced",
        ),
      );
    }
  }
}

/**
 * The wake-up of the policy. The function makes the decision again against the
 * core as it is now, because a summary from a peer that arrives in the delay
 * window is the condition that this wake-up looks for.
 * 
 * @ignore
 */
function attempt_summary(cell) {
  let state = cell_get(cell);
  cell_set(
    cell,
    new State(
      state.connect_message,
      state.http_base_url,
      state.channel,
      state.phase,
      state.subscribers,
      state.ripple_subscribers,
      state.presence_subscribers,
      state.supported_features,
      state.claim_waiters,
      state.acquire_waiters,
      state.on_ready,
      state.ready_fired,
      state.bootstrap_generation,
      state.bootstrap,
      state.auto_summary,
      false,
      state.pending_summary,
      state.scheduler,
    ),
  );
  let $ = state.phase;
  let $1 = state.auto_summary;
  let $2 = state.pending_summary;
  if ($1 instanceof Some) {
    if ($2 instanceof Some) {
      if ($ instanceof Connecting) {
        return undefined;
      } else if ($ instanceof Reconnecting) {
        return undefined;
      } else if ($ instanceof Ready) {
        let $3 = $.resubmit_at;
        if ($3 instanceof Some) {
          return undefined;
        } else {
          return undefined;
        }
      } else {
        return undefined;
      }
    } else if ($ instanceof Connecting) {
      return undefined;
    } else if ($ instanceof Reconnecting) {
      return undefined;
    } else if ($ instanceof Ready) {
      let $3 = $.resubmit_at;
      if ($3 instanceof Some) {
        return undefined;
      } else {
        let policy = $1[0];
        let core = $.core;
        let $4 = $runtime_core.wants_summary(core, policy);
        if ($4) {
          let $5 = summarize(new Runtime(cell));
          
          return undefined;
        } else {
          return undefined;
        }
      }
    } else {
      return undefined;
    }
  } else if ($ instanceof Connecting) {
    return undefined;
  } else if ($ instanceof Reconnecting) {
    return undefined;
  } else if ($ instanceof Ready) {
    let $3 = $.resubmit_at;
    if ($3 instanceof Some) {
      return undefined;
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

/**
 * Schedule an attempt to summarize, if the policy asks for one and no attempt
 * is pending.
 *
 * The delay keeps the cost of a room low. Every client crosses the threshold
 * on the same operation. Each client then waits for a different interval,
 * which comes from its id. The first published summary advances
 * `last_summary_sequence_number` on every client. The rest of the room checks
 * again on its wake-up and stops. A lost race costs one unnecessary
 * upload, and nothing more.
 * 
 * @ignore
 */
function arm_summary(cell, core) {
  let state = cell_get(cell);
  let $ = state.auto_summary;
  let $1 = state.summary_armed;
  let $2 = state.pending_summary;
  if ($ instanceof Some && !$1 && $2 instanceof None) {
    let policy = $[0];
    let $3 = $runtime_core.wants_summary(core, policy);
    if ($3) {
      cell_set(
        cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          state.phase,
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          true,
          state.pending_summary,
          state.scheduler,
        ),
      );
      let $4 = state.scheduler.schedule(
        () => { return attempt_summary(cell); },
        $runtime_core.summary_jitter_milliseconds(core, policy),
      );
      
      return undefined;
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

function send_outbound(channel, client_id, outbound) {
  if (outbound instanceof $Empty) {
    return undefined;
  } else if (channel instanceof Some) {
    let channel$1 = channel[0];
    return $list.each(
      $list.sized_chunk(outbound, max_operations_per_submission),
      (chunk) => {
        return push_json(
          channel$1,
          "submitOp",
          $socket.encode_submit_operation(client_id, toList([chunk])),
        );
      },
    );
  } else {
    return undefined;
  }
}

function session_current(cell, generation) {
  let state = cell_get(cell);
  let $ = state.phase;
  if ($ instanceof Ready) {
    return state.bootstrap_generation === generation;
  } else {
    return false;
  }
}

function maybe_request_operations(channel, request_from) {
  if (channel instanceof Some && request_from instanceof Some) {
    let channel$1 = channel[0];
    let from = request_from[0];
    return push_json(
      channel$1,
      "requestOps",
      $socket.encode_request_operations(from),
    );
  } else {
    return undefined;
  }
}

/**
 * Route each event to the subscribers that registered for the channel address
 * on that event.
 *
 * The contract for a caller: write the new core into the cell before this
 * fan-out. A handler that reads the map during the event thus sees the state
 * that the runtime applied. That rule holds for a local edit, a remote
 * operation, and a reconnect.
 *
 * The `subscribers` argument is one snapshot. A callback can unsubscribe
 * itself, or another callback, during the fan-out. That change affects the
 * next fan-out only.
 * 
 * @ignore
 */
function fan_out(subscribers, events) {
  return $list.each(
    events,
    (event) => {
      let address = event[0];
      let event$1 = event[1];
      return $list.each(
        subscribers,
        (subscriber) => {
          let $ = subscriber.address === address;
          if ($) {
            return observe(
              (("subscriber " + subscriber.id) + " at ") + address,
              () => { return subscriber.handler(event$1); },
            );
          } else {
            return undefined;
          }
        },
      );
    },
  );
}

function settle_reconnect(cell, core, checkpoint) {
  let state = cell_get(cell);
  let $ = core.last_seen_sequence_number >= checkpoint;
  if ($) {
    let $1 = $runtime_core.resubmit($runtime_core.go_live(core));
    let core$1 = $1[0];
    let outbound = $1[1];
    cell_set(
      cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        new Ready(core$1, Option$None$const),
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        state.acquire_waiters,
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        state.pending_summary,
        state.scheduler,
      ),
    );
    return send_outbound(state.channel, core$1.client_id, outbound);
  } else {
    return cell_set(
      cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        new Ready(core, new Some(checkpoint)),
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        state.acquire_waiters,
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        state.pending_summary,
        state.scheduler,
      ),
    );
  }
}

function take_summary_outcomes(state, events) {
  return $list.fold(
    events,
    [state, $List$Empty$const],
    (acc, event) => {
      let state$1 = acc[0];
      let outcomes = acc[1];
      let $ = state$1.pending_summary;
      if ($ instanceof Some) {
        if (event instanceof $runtime_core.SummaryProposalSequenced) {
          let pending = $[0];
          let client_sequence_number = event.client_sequence_number;
          if (client_sequence_number === pending.client_sequence_number) {
            let sequence_number = event.sequence_number;
            return [
              new State(
                state$1.connect_message,
                state$1.http_base_url,
                state$1.channel,
                state$1.phase,
                state$1.subscribers,
                state$1.ripple_subscribers,
                state$1.presence_subscribers,
                state$1.supported_features,
                state$1.claim_waiters,
                state$1.acquire_waiters,
                state$1.on_ready,
                state$1.ready_fired,
                state$1.bootstrap_generation,
                state$1.bootstrap,
                state$1.auto_summary,
                state$1.summary_armed,
                new Some(
                  new PendingSummary(
                    pending.tree_id,
                    pending.client_sequence_number,
                    new Some(sequence_number),
                    pending.resolve,
                  ),
                ),
                state$1.scheduler,
              ),
              outcomes,
            ];
          } else {
            return [state$1, outcomes];
          }
        } else if (event instanceof $runtime_core.SummaryPublished) {
          let pending = $[0];
          let sequence_number = event.proposal_sequence_number;
          if (
            isEqual(pending.proposal_sequence_number, new Some(sequence_number))
          ) {
            let version_id = event.version_id;
            return [
              new State(
                state$1.connect_message,
                state$1.http_base_url,
                state$1.channel,
                state$1.phase,
                state$1.subscribers,
                state$1.ripple_subscribers,
                state$1.presence_subscribers,
                state$1.supported_features,
                state$1.claim_waiters,
                state$1.acquire_waiters,
                state$1.on_ready,
                state$1.ready_fired,
                state$1.bootstrap_generation,
                state$1.bootstrap,
                state$1.auto_summary,
                state$1.summary_armed,
                Option$None$const,
                state$1.scheduler,
              ),
              listPrepend(
                () => { return pending.resolve(new Ok(version_id)); },
                outcomes,
              ),
            ];
          } else {
            return [state$1, outcomes];
          }
        } else {
          let pending = $[0];
          let sequence_number = event.proposal_sequence_number;
          if (
            isEqual(pending.proposal_sequence_number, new Some(sequence_number))
          ) {
            let reason = event.reason;
            return [
              new State(
                state$1.connect_message,
                state$1.http_base_url,
                state$1.channel,
                state$1.phase,
                state$1.subscribers,
                state$1.ripple_subscribers,
                state$1.presence_subscribers,
                state$1.supported_features,
                state$1.claim_waiters,
                state$1.acquire_waiters,
                state$1.on_ready,
                state$1.ready_fired,
                state$1.bootstrap_generation,
                state$1.bootstrap,
                state$1.auto_summary,
                state$1.summary_armed,
                Option$None$const,
                state$1.scheduler,
              ),
              listPrepend(
                () => { return pending.resolve(new Error(reason)); },
                outcomes,
              ),
            ];
          } else {
            return [state$1, outcomes];
          }
        }
      } else {
        return [state$1, outcomes];
      }
    },
  );
}

function take_outcome_waiters(state, resolutions) {
  let $ = $list.fold(
    resolutions,
    [state, $List$Empty$const],
    (acc, item) => {
      let state$1 = acc[0];
      let callbacks = acc[1];
      let address = item[0];
      let resolution = item[1];
      if (resolution instanceof ClaimResolved) {
        let key = resolution.key;
        let outcome = resolution.outcome;
        let $1 = $dict.get(state$1.claim_waiters, [address, key]);
        if ($1 instanceof Ok) {
          let resolve_outcome = $1[0];
          return [
            new State(
              state$1.connect_message,
              state$1.http_base_url,
              state$1.channel,
              state$1.phase,
              state$1.subscribers,
              state$1.ripple_subscribers,
              state$1.presence_subscribers,
              state$1.supported_features,
              $dict.delete$(state$1.claim_waiters, [address, key]),
              state$1.acquire_waiters,
              state$1.on_ready,
              state$1.ready_fired,
              state$1.bootstrap_generation,
              state$1.bootstrap,
              state$1.auto_summary,
              state$1.summary_armed,
              state$1.pending_summary,
              state$1.scheduler,
            ),
            listPrepend(() => { return resolve_outcome(outcome); }, callbacks),
          ];
        } else {
          return acc;
        }
      } else {
        let acquire_id = resolution.acquire_id;
        let outcome = resolution.outcome;
        let $1 = $dict.get(state$1.acquire_waiters, [address, acquire_id]);
        if ($1 instanceof Ok) {
          let resolve_outcome = $1[0];
          return [
            new State(
              state$1.connect_message,
              state$1.http_base_url,
              state$1.channel,
              state$1.phase,
              state$1.subscribers,
              state$1.ripple_subscribers,
              state$1.presence_subscribers,
              state$1.supported_features,
              state$1.claim_waiters,
              $dict.delete$(state$1.acquire_waiters, [address, acquire_id]),
              state$1.on_ready,
              state$1.ready_fired,
              state$1.bootstrap_generation,
              state$1.bootstrap,
              state$1.auto_summary,
              state$1.summary_armed,
              state$1.pending_summary,
              state$1.scheduler,
            ),
            listPrepend(() => { return resolve_outcome(outcome); }, callbacks),
          ];
        } else {
          return acc;
        }
      }
    },
  );
  let state$1 = $[0];
  let callbacks = $[1];
  return [state$1, $list.reverse(callbacks)];
}

function do_apply_operations(
  loop$core,
  loop$operations,
  loop$events,
  loop$resolutions,
  loop$summary_events,
  loop$request_from,
  loop$released
) {
  while (true) {
    let core = loop$core;
    let operations = loop$operations;
    let events = loop$events;
    let resolutions = loop$resolutions;
    let summary_events = loop$summary_events;
    let request_from = loop$request_from;
    let released = loop$released;
    if (operations instanceof $Empty) {
      return new Ok(
        [
          core,
          (() => {
            let _pipe = $list.reverse(events);
            return $list.flatten(_pipe);
          })(),
          (() => {
            let _pipe = $list.reverse(resolutions);
            return $list.flatten(_pipe);
          })(),
          (() => {
            let _pipe = $list.reverse(summary_events);
            return $list.flatten(_pipe);
          })(),
          request_from,
          released,
        ],
      );
    } else {
      let operation = operations.head;
      let rest = operations.tail;
      let $ = $runtime_core.handle_sequenced(core, operation);
      if ($ instanceof Ok) {
        let core$1 = $[0][0];
        let ingested = $[0][1];
        loop$core = core$1;
        loop$operations = rest;
        loop$events = listPrepend(ingested.events, events);
        loop$resolutions = listPrepend(ingested.resolutions, resolutions);
        loop$summary_events = listPrepend(
          ingested.summary_events,
          summary_events,
        );
        loop$request_from = $option.or(
          request_from,
          ingested.request_operations_from,
        );
        loop$released = $list.append(released, ingested.outbound);
      } else {
        return $;
      }
    }
  }
}

function apply_operations(core, operations) {
  return do_apply_operations(
    core,
    operations,
    $List$Empty$const,
    $List$Empty$const,
    $List$Empty$const,
    Option$None$const,
    $List$Empty$const,
  );
}

function apply_received_operations(cell, operations) {
  let state = cell_get(cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return undefined;
  } else if ($ instanceof Reconnecting) {
    return undefined;
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let $1 = apply_operations(core, operations);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let resolutions = $1[0][2];
      let summary_events = $1[0][3];
      let request_from = $1[0][4];
      let released = $1[0][5];
      let $2 = take_outcome_waiters(state, resolutions);
      let state$1 = $2[0];
      let outcomes = $2[1];
      let $3 = take_summary_outcomes(state$1, summary_events);
      let state$2 = $3[0];
      let summary_outcomes = $3[1];
      if (resubmit_at instanceof Some) {
        let checkpoint = resubmit_at[0];
        cell_set(cell, state$2);
        settle_reconnect(cell, core$1, checkpoint);
      } else {
        cell_set(
          cell,
          new State(
            state$2.connect_message,
            state$2.http_base_url,
            state$2.channel,
            new Ready(core$1, Option$None$const),
            state$2.subscribers,
            state$2.ripple_subscribers,
            state$2.presence_subscribers,
            state$2.supported_features,
            state$2.claim_waiters,
            state$2.acquire_waiters,
            state$2.on_ready,
            state$2.ready_fired,
            state$2.bootstrap_generation,
            state$2.bootstrap,
            state$2.auto_summary,
            state$2.summary_armed,
            state$2.pending_summary,
            state$2.scheduler,
          ),
        );
      }
      $list.each(
        outcomes,
        (outcome) => { return observe("operation outcome", outcome); },
      );
      $list.each(
        summary_outcomes,
        (outcome) => { return observe("summary publication", outcome); },
      );
      fan_out(state$2.subscribers, events);
      return $bool.guard(
        !session_current(cell, state$2.bootstrap_generation),
        undefined,
        () => {
          maybe_request_operations(state$2.channel, request_from);
          return $bool.guard(
            !session_current(cell, state$2.bootstrap_generation),
            undefined,
            () => {
              if (resubmit_at instanceof Some) {
                undefined;
              } else {
                send_outbound(state$2.channel, core$1.client_id, released);
              }
              if (resubmit_at instanceof Some) {
                return undefined;
              } else {
                let $4 = cell_get(cell).phase;
                if ($4 instanceof Ready) {
                  let current = $4.core;
                  return arm_summary(cell, current);
                } else {
                  return undefined;
                }
              }
            },
          );
        },
      );
    } else {
      let core_error = $1[0];
      return fail(
        cell,
        "sequenced op processing failed: " + $string.inspect(core_error),
      );
    }
  } else {
    return undefined;
  }
}

/**
 * Announce a handshake that settled. The message carries the id and the
 * capability that a driver needs to join.
 * 
 * @ignore
 */
function notify_presence_session(cell, core) {
  let state = cell_get(cell);
  return notify_presence(
    cell,
    new PresenceSession(
      core.client_id,
      $socket.supports_feature(
        state.supported_features,
        $socket.feature_presence_v1,
      ),
    ),
  );
}

function bootstrap_current(cell, generation) {
  let state = cell_get(cell);
  return (state.bootstrap_generation === generation) && (!(state.bootstrap instanceof None));
}

function drain_bootstrap(cell, generation) {
  return $bool.guard(
    !bootstrap_current(cell, generation),
    undefined,
    () => {
      let state = cell_get(cell);
      let $ = state.bootstrap;
      let $1 = state.phase;
      if ($ instanceof Some && $1 instanceof Ready) {
        let bootstrap = $[0];
        if (!bootstrap.draining) {
          cell_set(
            cell,
            new State(
              state.connect_message,
              state.http_base_url,
              state.channel,
              state.phase,
              state.subscribers,
              state.ripple_subscribers,
              state.presence_subscribers,
              state.supported_features,
              state.claim_waiters,
              state.acquire_waiters,
              state.on_ready,
              state.ready_fired,
              state.bootstrap_generation,
              new Some(
                new Bootstrap(
                  $List$Empty$const,
                  bootstrap.operation_count,
                  bootstrap.payload_bytes,
                  true,
                ),
              ),
              state.auto_summary,
              state.summary_armed,
              state.pending_summary,
              state.scheduler,
            ),
          );
          let _pipe = bootstrap.batches;
          let _pipe$1 = $list.reverse(_pipe);
          $list.each(
            _pipe$1,
            (operations) => {
              return $bool.guard(
                !bootstrap_current(cell, generation),
                undefined,
                () => { return apply_received_operations(cell, operations); },
              );
            },
          );
          return $bool.guard(
            !bootstrap_current(cell, generation),
            undefined,
            () => {
              let state$1 = cell_get(cell);
              let $2 = state$1.bootstrap;
              let bootstrap$1;
              if ($2 instanceof Some) {
                bootstrap$1 = $2[0];
              } else {
                throw makeError(
                  "let_assert",
                  FILEPATH,
                  "watershed/runtime",
                  2913,
                  "drain_bootstrap",
                  "Pattern match failed, no pattern matched the value.",
                  {
                    value: $2,
                    start: 92575,
                    end: 92619,
                    pattern_start: 92586,
                    pattern_end: 92601
                  }
                )
              }
              cell_set(
                cell,
                new State(
                  state$1.connect_message,
                  state$1.http_base_url,
                  state$1.channel,
                  state$1.phase,
                  state$1.subscribers,
                  state$1.ripple_subscribers,
                  state$1.presence_subscribers,
                  state$1.supported_features,
                  state$1.claim_waiters,
                  state$1.acquire_waiters,
                  state$1.on_ready,
                  state$1.ready_fired,
                  state$1.bootstrap_generation,
                  new Some(
                    new Bootstrap(
                      bootstrap$1.batches,
                      bootstrap$1.operation_count,
                      bootstrap$1.payload_bytes,
                      false,
                    ),
                  ),
                  state$1.auto_summary,
                  state$1.summary_armed,
                  state$1.pending_summary,
                  state$1.scheduler,
                ),
              );
              let $3 = bootstrap$1.batches;
              let $4 = state$1.phase;
              if ($3 instanceof $Empty) {
                if ($4 instanceof Ready) {
                  let core = $4.core;
                  let $5 = core.out_of_order;
                  if ($5 instanceof $Empty) {
                    cell_set(
                      cell,
                      (() => {
                        let _record = cell_get(cell);
                        return new State(
                          _record.connect_message,
                          _record.http_base_url,
                          _record.channel,
                          _record.phase,
                          _record.subscribers,
                          _record.ripple_subscribers,
                          _record.presence_subscribers,
                          _record.supported_features,
                          _record.claim_waiters,
                          _record.acquire_waiters,
                          _record.on_ready,
                          _record.ready_fired,
                          _record.bootstrap_generation,
                          Option$None$const,
                          _record.auto_summary,
                          _record.summary_armed,
                          _record.pending_summary,
                          _record.scheduler,
                        );
                      })(),
                    );
                    fire_ready(cell, new Ok(undefined));
                    let current = cell_get(cell);
                    let $6 = current.phase;
                    if (
                      $6 instanceof Ready &&
                      current.bootstrap_generation === generation
                    ) {
                      let core$1 = $6.core;
                      return notify_presence_session(cell, core$1);
                    } else {
                      return undefined;
                    }
                  } else {
                    return undefined;
                  }
                } else {
                  return undefined;
                }
              } else {
                return drain_bootstrap(cell, generation);
              }
            },
          );
        } else {
          return undefined;
        }
      } else {
        return undefined;
      }
    },
  );
}

function buffer_bootstrap(cell, state, bootstrap, payload) {
  let bytes = bootstrap.payload_bytes + payload_byte_size(payload);
  let $ = bytes > 16 * 1024 * 1024;
  if ($) {
    return fail(cell, "bootstrap payload byte limit exceeded");
  } else {
    let $1 = $json.parse(payload, $socket.operation_message_decoder());
    if ($1 instanceof Ok) {
      let message = $1[0];
      let count = bootstrap.operation_count + $list.length(message.ops);
      let $2 = count > 10_000;
      if ($2) {
        return fail(cell, "bootstrap operation limit exceeded");
      } else {
        cell_set(
          cell,
          new State(
            state.connect_message,
            state.http_base_url,
            state.channel,
            state.phase,
            state.subscribers,
            state.ripple_subscribers,
            state.presence_subscribers,
            state.supported_features,
            state.claim_waiters,
            state.acquire_waiters,
            state.on_ready,
            state.ready_fired,
            state.bootstrap_generation,
            new Some(
              new Bootstrap(
                listPrepend(message.ops, bootstrap.batches),
                count,
                bytes,
                bootstrap.draining,
              ),
            ),
            state.auto_summary,
            state.summary_armed,
            state.pending_summary,
            state.scheduler,
          ),
        );
        return drain_bootstrap(cell, state.bootstrap_generation);
      }
    } else {
      return fail(cell, "malformed op payload");
    }
  }
}

function on_operation(cell, payload) {
  let state = cell_get(cell);
  let $ = state.bootstrap;
  if ($ instanceof Some) {
    let bootstrap = $[0];
    return buffer_bootstrap(cell, state, bootstrap, payload);
  } else {
    let $1 = state.phase;
    if ($1 instanceof Connecting) {
      return undefined;
    } else if ($1 instanceof Reconnecting) {
      return undefined;
    } else if ($1 instanceof Ready) {
      let $2 = $json.parse(payload, $socket.operation_message_decoder());
      if ($2 instanceof Ok) {
        let message = $2[0];
        return apply_received_operations(cell, message.ops);
      } else {
        return fail(cell, "malformed op payload");
      }
    } else {
      return undefined;
    }
  }
}

function on_connect_error(cell, payload) {
  let $ = $json.parse(payload, $socket.connect_error_decoder());
  if ($ instanceof Ok) {
    let error = $[0];
    return fail(cell, error.message);
  } else {
    return fail(cell, "connect_document_error");
  }
}

/**
 * Complete one bootstrap step. The function makes the document ready, or it
 * reads the missing prefix of the history from the deltas REST endpoint and
 * continues. That read is asynchronous, and it can need several rounds. A
 * bootstrap must not complete on a history with a gap, so every failure here
 * moves the cell to `Failed`.
 * 
 * @ignore
 */
function continue_bootstrap(cell, bootstrapped, generation) {
  return $bool.guard(
    !bootstrap_current(cell, generation),
    undefined,
    () => {
      if (bootstrapped instanceof $runtime_core.Complete) {
        let core = bootstrapped.core;
        cell_set(
          cell,
          (() => {
            let _record = cell_get(cell);
            return new State(
              _record.connect_message,
              _record.http_base_url,
              _record.channel,
              new Ready(core, Option$None$const),
              _record.subscribers,
              _record.ripple_subscribers,
              _record.presence_subscribers,
              _record.supported_features,
              _record.claim_waiters,
              _record.acquire_waiters,
              _record.on_ready,
              _record.ready_fired,
              _record.bootstrap_generation,
              _record.bootstrap,
              _record.auto_summary,
              _record.summary_armed,
              _record.pending_summary,
              _record.scheduler,
            );
          })(),
        );
        return drain_bootstrap(cell, generation);
      } else {
        let core = bootstrapped.core;
        let checkpoint = bootstrapped.checkpoint;
        let from = bootstrapped.from;
        let to = bootstrapped.to;
        let state = cell_get(cell);
        let $ = state.connect_message.token;
        if ($ instanceof Some) {
          let token = $[0];
          let _block;
          let _pipe = $git_storage.fetch_deltas(
            state.http_base_url,
            state.connect_message.tenant_id,
            token,
            state.connect_message.document_id,
            from,
            to,
          );
          _block = $promise.map(
            _pipe,
            (result) => {
              return $bool.guard(
                !bootstrap_current(cell, generation),
                undefined,
                () => {
                  if (result instanceof Ok) {
                    let deltas = result[0];
                    let $2 = $runtime_core.resume_bootstrap(
                      core,
                      checkpoint,
                      deltas,
                    );
                    if ($2 instanceof Ok) {
                      let next = $2[0];
                      return continue_bootstrap(cell, next, generation);
                    } else {
                      let error = $2[0];
                      return fail(
                        cell,
                        "bootstrap failed: " + $string.inspect(error),
                      );
                    }
                  } else {
                    let error = result[0];
                    return fail(
                      cell,
                      "history catch-up failed: " + $git_storage.error_to_string(
                        error,
                      ),
                    );
                  }
                },
              );
            },
          );
          let $1 = _block;
          
          return undefined;
        } else {
          return fail(cell, "history catch-up requires an auth token");
        }
      }
    },
  );
}

/**
 * Bootstrap the core, from a summary if one exists, and then run `on_ready`.
 * 
 * @ignore
 */
function finish_bootstrap(cell, connected, summary, generation) {
  return $bool.guard(
    !bootstrap_current(cell, generation),
    undefined,
    () => {
      let $ = $runtime_core.bootstrap(connected, summary);
      if ($ instanceof Ok) {
        let bootstrapped = $[0];
        return continue_bootstrap(cell, bootstrapped, generation);
      } else {
        let error = $[0];
        return fail(cell, "bootstrap failed: " + $string.inspect(error));
      }
    },
  );
}

/**
 * Fetch the summary under the current bootstrap generation. Live operations
 * remain buffered until the summary and all prefix pages have loaded.
 * 
 * @ignore
 */
function load_summary_then_bootstrap(
  cell,
  state,
  connected,
  context,
  generation
) {
  let $ = state.connect_message.token;
  if ($ instanceof Some) {
    let token = $[0];
    let _block;
    let _pipe = $git_storage.fetch_summary(
      state.http_base_url,
      state.connect_message.tenant_id,
      token,
      context.handle,
    );
    _block = $promise.map(
      _pipe,
      (result) => {
        return $bool.guard(
          !bootstrap_current(cell, generation),
          undefined,
          () => {
            if (result instanceof Ok) {
              let blob = result[0];
              return finish_bootstrap(
                cell,
                connected,
                new Some($runtime_core.summary_from_blob(blob)),
                generation,
              );
            } else {
              let error = result[0];
              return fail(
                cell,
                "summary load failed: " + $git_storage.error_to_string(error),
              );
            }
          },
        );
      },
    );
    let $1 = _block;
    
    return undefined;
  } else {
    return fail(cell, "loading a summarized document requires an auth token");
  }
}

function begin_bootstrap(cell, connected) {
  let state = cell_get(cell);
  let generation = state.bootstrap_generation + 1;
  let state$1 = new State(
    state.connect_message,
    state.http_base_url,
    state.channel,
    Phase$Connecting$const,
    state.subscribers,
    state.ripple_subscribers,
    state.presence_subscribers,
    state.supported_features,
    state.claim_waiters,
    state.acquire_waiters,
    state.on_ready,
    state.ready_fired,
    generation,
    new Some(new Bootstrap($List$Empty$const, 0, 0, false)),
    state.auto_summary,
    state.summary_armed,
    state.pending_summary,
    state.scheduler,
  );
  cell_set(cell, state$1);
  let $ = connected.summary_context;
  if ($ instanceof Some) {
    let context = $[0];
    return load_summary_then_bootstrap(
      cell,
      state$1,
      connected,
      context,
      generation,
    );
  } else {
    return finish_bootstrap(cell, connected, Option$None$const, generation);
  }
}

function on_connect_success(cell, payload) {
  let $ = $json.parse(payload, $socket.connected_message_decoder());
  if ($ instanceof Ok) {
    let connected = $[0];
    cell_set(
      cell,
      (() => {
        let _record = cell_get(cell);
        return new State(
          _record.connect_message,
          _record.http_base_url,
          _record.channel,
          _record.phase,
          _record.subscribers,
          _record.ripple_subscribers,
          _record.presence_subscribers,
          connected.supported_features,
          _record.claim_waiters,
          _record.acquire_waiters,
          _record.on_ready,
          _record.ready_fired,
          _record.bootstrap_generation,
          _record.bootstrap,
          _record.auto_summary,
          _record.summary_armed,
          _record.pending_summary,
          _record.scheduler,
        );
      })(),
    );
    let state = cell_get(cell);
    let $1 = state.phase;
    if ($1 instanceof Connecting) {
      return begin_bootstrap(cell, connected);
    } else if ($1 instanceof Reconnecting) {
      let core = $1.core;
      let core$1 = $runtime_core.adopt_reconnect(core, connected);
      let checkpoint = $option.unwrap(
        connected.checkpoint_sequence_number,
        core$1.last_seen_sequence_number,
      );
      settle_reconnect(cell, core$1, checkpoint);
      maybe_request_operations(
        state.channel,
        $runtime_core.catch_up_from(core$1, checkpoint),
      );
      let $2 = session_current(cell, state.bootstrap_generation);
      if ($2) {
        return notify_presence_session(cell, core$1);
      } else {
        return undefined;
      }
    } else if ($1 instanceof Ready) {
      let $2 = state.bootstrap;
      if ($2 instanceof Some) {
        return begin_bootstrap(cell, connected);
      } else {
        return undefined;
      }
    } else {
      return undefined;
    }
  } else {
    return fail(cell, "malformed connect_document_success payload");
  }
}

function on_event(cell, event, payload) {
  if (event === "connect_document_success") {
    return on_connect_success(cell, payload);
  } else if (event === "connect_document_error") {
    return on_connect_error(cell, payload);
  } else if (event === "op") {
    return on_operation(cell, payload);
  } else if (event === "nack") {
    return on_nack(cell, payload);
  } else if (event === "signal") {
    return on_ripple(cell, payload);
  } else if (event === "presence_state") {
    return notify_presence(cell, new PresenceState(payload));
  } else if (event === "presence_diff") {
    return notify_presence(cell, new PresenceDiff(payload));
  } else if (event === "presence_error") {
    return notify_presence(cell, new PresenceError(payload));
  } else {
    return undefined;
  }
}

function invalidate_bootstrap(cell) {
  let state = cell_get(cell);
  let _block;
  let $ = state.bootstrap;
  let $1 = state.phase;
  if ($ instanceof Some && $1 instanceof Ready) {
    _block = Phase$Connecting$const;
  } else {
    _block = $1;
  }
  let phase = _block;
  return cell_set(
    cell,
    new State(
      state.connect_message,
      state.http_base_url,
      state.channel,
      phase,
      state.subscribers,
      state.ripple_subscribers,
      state.presence_subscribers,
      state.supported_features,
      state.claim_waiters,
      state.acquire_waiters,
      state.on_ready,
      state.ready_fired,
      state.bootstrap_generation + 1,
      Option$None$const,
      state.auto_summary,
      state.summary_armed,
      state.pending_summary,
      state.scheduler,
    ),
  );
}

function on_close(cell) {
  invalidate_bootstrap(cell);
  let state = cell_get(cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return undefined;
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    cell_set(
      cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        new Reconnecting(core),
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        state.acquire_waiters,
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        Option$None$const,
        state.scheduler,
      ),
    );
    abort_pending_summary(state);
    return notify_session_lost(cell, state.phase);
  } else if ($ instanceof Ready) {
    let core = $.core;
    cell_set(
      cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        new Reconnecting(core),
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        state.acquire_waiters,
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        Option$None$const,
        state.scheduler,
      ),
    );
    abort_pending_summary(state);
    return notify_session_lost(cell, state.phase);
  } else {
    return undefined;
  }
}

function push_connect(channel, connect_message, last_seen) {
  return push_json(
    channel,
    "connect_document",
    $socket.encode_connect_document(connect_message, last_seen),
  );
}

/**
 * A join succeeded, so send `connect_document`. On the first join that message
 * starts the handshake. On a rejoin that Phoenix performed by itself, it
 * starts the handshake again, with the last sequence number that this client
 * saw, so the server pushes the delta only.
 * 
 * @ignore
 */
function on_join(cell) {
  invalidate_bootstrap(cell);
  let state = cell_get(cell);
  let $ = state.channel;
  if ($ instanceof Some) {
    let channel = $[0];
    let $1 = state.phase;
    if ($1 instanceof Connecting) {
      return push_connect(channel, state.connect_message, Option$None$const);
    } else if ($1 instanceof Reconnecting) {
      let core = $1.core;
      return push_connect(
        channel,
        state.connect_message,
        new Some(core.last_seen_sequence_number),
      );
    } else if ($1 instanceof Ready) {
      let core = $1.core;
      cell_set(
        cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      notify_session_lost(cell, state.phase);
      let current = cell_get(cell);
      return $bool.guard(
        current.bootstrap_generation !== state.bootstrap_generation,
        undefined,
        () => {
          return push_connect(
            channel,
            state.connect_message,
            new Some(core.last_seen_sequence_number),
          );
        },
      );
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

function deliver_transport_event(cell, event) {
  let $ = cell_get(cell).phase;
  if ($ instanceof Failed) {
    return undefined;
  } else {
    if (event instanceof TransportJoined) {
      return on_join(cell);
    } else if (event instanceof TransportClosed) {
      return on_close(cell);
    } else {
      let event$1 = event.event;
      let payload = event.payload;
      return on_event(cell, event$1, payload);
    }
  }
}

function drain_transport_start(loop$cell, loop$constructing) {
  while (true) {
    let cell = loop$cell;
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
          (event) => { return deliver_transport_event(cell, event); },
        );
        loop$cell = cell;
        loop$constructing = constructing;
      }
    } else {
      return undefined;
    }
  }
}

function transport_event(cell, constructing, event) {
  let $ = $transport_js.get_cell(constructing);
  if ($ instanceof Some) {
    let events = $[0];
    return $transport_js.set_cell(
      constructing,
      new Some(listPrepend(event, events)),
    );
  } else {
    return deliver_transport_event(cell, event);
  }
}

/**
 * Start a runtime against any transport. The live `start` function, which uses
 * Phoenix, calls this function, and so does the in-memory hub test driver.
 * `http_base_url` supplies the REST summary API only. A transport that serves
 * no such API can pass any value.
 */
export function start_with_transport(
  http_base_url,
  connect_message,
  transport,
  on_ready
) {
  let cell = $transport_js.new_cell(
    new State(
      connect_message,
      http_base_url,
      Option$None$const,
      Phase$Connecting$const,
      $List$Empty$const,
      $List$Empty$const,
      $List$Empty$const,
      $dict.new$(),
      $dict.new$(),
      $dict.new$(),
      on_ready,
      false,
      0,
      Option$None$const,
      new Some($summary_policy.policy()),
      false,
      Option$None$const,
      $transport_js.real_scheduler(),
    ),
  );
  let constructing = $transport_js.new_cell(new Some($List$Empty$const));
  let handle = transport.connect(
    new TransportCallbacks(
      (event, payload) => {
        return transport_event(
          cell,
          constructing,
          new TransportReceived(event, payload),
        );
      },
      () => {
        return transport_event(
          cell,
          constructing,
          TransportEvent$TransportJoined$const,
        );
      },
      () => {
        return transport_event(
          cell,
          constructing,
          TransportEvent$TransportClosed$const,
        );
      },
    ),
  );
  cell_set(
    cell,
    (() => {
      let _record = cell_get(cell);
      return new State(
        _record.connect_message,
        _record.http_base_url,
        new Some(handle),
        _record.phase,
        _record.subscribers,
        _record.ripple_subscribers,
        _record.presence_subscribers,
        _record.supported_features,
        _record.claim_waiters,
        _record.acquire_waiters,
        _record.on_ready,
        _record.ready_fired,
        _record.bootstrap_generation,
        _record.bootstrap,
        _record.auto_summary,
        _record.summary_armed,
        _record.pending_summary,
        _record.scheduler,
      );
    })(),
  );
  drain_transport_start(cell, constructing);
  return new Runtime(cell);
}

/**
 * Start a runtime. The function opens the Phoenix socket, joins the topic, and
 * starts the handshake. `on_ready` runs one time. It gives `Ok(Nil)` after the
 * document bootstraps, or `Error(reason)` when the server refuses the
 * connection.
 */
export function start(url, topic, connect_message, on_ready) {
  let _block;
  let $ = connect_message.token;
  if ($ instanceof Some) {
    let token = $[0];
    _block = $json.object(toList([["token", $json.string(token)]]));
  } else {
    _block = $json.object($List$Empty$const);
  }
  let join_payload = _block;
  return start_with_transport(
    http_base_from_socket_url(url),
    connect_message,
    phoenix_transport(url, topic, join_payload),
    on_ready,
  );
}

function edit(cell, operate) {
  let state = cell_get(cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return undefined;
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = operate(core);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      cell_set(
        cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core$1),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      return fan_out(state.subscribers, events);
    } else {
      return undefined;
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let $1 = operate(core);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let outbound = $1[0][2];
      cell_set(
        cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Ready(core$1, resubmit_at),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      if (resubmit_at instanceof Some) {
        undefined;
      } else {
        send_outbound(state.channel, core$1.client_id, outbound);
      }
      return fan_out(state.subscribers, events);
    } else {
      return undefined;
    }
  } else {
    return undefined;
  }
}

export function set(runtime, address, key, value) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.set(core, address, key, value); },
  );
}

export function delete$(runtime, address, key) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.delete$(core, address, key); },
  );
}

export function clear(runtime, address) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.clear(core, address); },
  );
}

function read(cell, default$, extract) {
  let $ = cell_get(cell).phase;
  if ($ instanceof Connecting) {
    return default$;
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    return extract(core);
  } else if ($ instanceof Ready) {
    let core = $.core;
    return extract(core);
  } else {
    return default$;
  }
}

export function get(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.get(_capture, address, key); },
  );
}

export function entries(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.entries(_capture, address); },
  );
}

export function keys(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.keys(_capture, address); },
  );
}

export function size(runtime, address) {
  return read(
    runtime.cell,
    0,
    (_capture) => { return $runtime_core.size(_capture, address); },
  );
}

export function has(runtime, address, key) {
  return $result.is_ok(get(runtime, address, key));
}

/**
 * Increment the counter at `address` optimistically. A negative amount
 * decrements it.
 */
export function increment(runtime, address, amount) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.increment(core, address, amount); },
  );
}

/**
 * The optimistic value of the counter. The result is `Error(Nil)` when the address
 * does not exist, and when it does not name a counter channel.
 */
export function counter_value(runtime, address) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.counter_value(_capture, address); },
  );
}

/**
 * Apply a signed update to the PN-counter at `address` optimistically. A
 * negative amount decrements it.
 */
export function pn_counter_update(runtime, address, amount) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.pn_counter_update(core, address, amount); },
  );
}

/**
 * The optimistic value of the PN-counter. The result is `Error(Nil)` when the
 * address does not exist, and when it does not name a PN-counter channel.
 */
export function pn_counter_value(runtime, address) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.pn_counter_value(_capture, address); },
  );
}

function edit_sequence_with_result(cell, operate) {
  let state = cell_get(cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return new Error("sequence edit before the document connection is ready");
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = operate(core);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      cell_set(
        cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core$1),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      fan_out(state.subscribers, events);
      return new Ok(undefined);
    } else {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.SequenceOperationFailed) {
        let detail = $2.detail;
        return new Error(detail);
      } else if ($2 instanceof $runtime_core.GCounterOperationFailed) {
        let detail = $2.detail;
        return new Error(detail);
      } else {
        let error = $2;
        return new Error($string.inspect(error));
      }
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let $1 = operate(core);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let outbound = $1[0][2];
      cell_set(
        cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Ready(core$1, resubmit_at),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      if (resubmit_at instanceof Some) {
        undefined;
      } else {
        send_outbound(state.channel, core$1.client_id, outbound);
      }
      fan_out(state.subscribers, events);
      return new Ok(undefined);
    } else {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.SequenceOperationFailed) {
        let detail = $2.detail;
        return new Error(detail);
      } else if ($2 instanceof $runtime_core.GCounterOperationFailed) {
        let detail = $2.detail;
        return new Error(detail);
      } else {
        let error = $2;
        return new Error($string.inspect(error));
      }
    }
  } else {
    return new Error("sequence edit before the document connection is ready");
  }
}

/**
 * Add `amount` to the grow-only counter at `address`. The result is an error
 * with a description when the amount is negative.
 */
export function g_counter_increment(runtime, address, amount) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.g_counter_increment(core, address, amount);
    },
  );
}

/**
 * The optimistic value of the grow-only counter. The result is `Error(Nil)`
 * when the address does not exist, and when it does not name a GCounter
 * channel.
 */
export function g_counter_value(runtime, address) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.g_counter_value(_capture, address); },
  );
}

/**
 * Set the register with the runtime wall clock. Return channel and clock
 * failures to the caller.
 */
export function lww_register_set(runtime, address, value) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.lww_register_set(
        core,
        address,
        value,
        $transport_js.now_milliseconds(),
      );
    },
  );
}

/**
 * Read the optimistic value. Return `Error(Nil)` if the address does not
 * name an LWW-register channel.
 */
export function lww_register_value(runtime, address) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.lww_register_value(_capture, address); },
  );
}

function create_channel(runtime, init, verb) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return new Error(verb + " requires a ready document connection");
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let address = $id.uuid_v4();
    let core$1 = $runtime_core.create_detached(core, address, init);
    cell_set(
      runtime.cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        new Reconnecting(core$1),
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        state.acquire_waiters,
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        state.pending_summary,
        state.scheduler,
      ),
    );
    return new Ok(address);
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let address = $id.uuid_v4();
    let core$1 = $runtime_core.create_detached(core, address, init);
    cell_set(
      runtime.cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        new Ready(core$1, resubmit_at),
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        state.acquire_waiters,
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        state.pending_summary,
        state.scheduler,
      ),
    );
    return new Ok(address);
  } else {
    return new Error(verb + " requires a ready document connection");
  }
}

export function create_lww_map(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitLwwMap$const,
    "create_lww_map",
  );
}

export function lww_map_set(runtime, address, key, value) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.lww_map_set(
        core,
        address,
        key,
        value,
        $transport_js.now_milliseconds(),
      );
    },
  );
}

export function lww_map_remove(runtime, address, key) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.lww_map_remove(
        core,
        address,
        key,
        $transport_js.now_milliseconds(),
      );
    },
  );
}

export function lww_map_get(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.lww_map_get(_capture, address, key); },
  );
}

export function lww_map_entries(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.lww_map_entries(_capture, address); },
  );
}

export function lww_map_keys(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.lww_map_keys(_capture, address); },
  );
}

/**
 * Propose `value` for `key` in the PactMap at `address`. This write is a
 * consensus write, and it is not optimistic. The value takes effect only after
 * the `Set` operation sequences, and after the `Accept` operation that follows
 * it settles the quorum.
 */
export function pact_map_set(runtime, address, key, value) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.pact_map_set(core, address, key, value); },
  );
}

/**
 * Propose a delete for `key` in the PactMap at `address`. A delete writes a
 * tombstone.
 */
export function pact_map_delete(runtime, address, key) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.pact_map_delete(core, address, key); },
  );
}

/**
 * The accepted value of the PactMap for `key`. The result is `Error(Nil)` when the
 * value is pending, when the key is absent, and when the address does not name
 * a PactMap channel.
 */
export function pact_map_get(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.pact_map_get(_capture, address, key); },
  );
}

/**
 * Every key with an accepted pact or a pending pact, in the PactMap at
 * `address`.
 */
export function pact_map_keys(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.pact_map_keys(_capture, address); },
  );
}

/**
 * Whether `key` has a pending value, which a client proposed and no room has
 * accepted yet.
 */
export function pact_map_is_pending(runtime, address, key) {
  return read(
    runtime.cell,
    false,
    (_capture) => {
      return $runtime_core.pact_map_is_pending(_capture, address, key);
    },
  );
}

/**
 * The pending proposal for `key`, which is the value with the signoff list that
 * it waits on. The result is `Error(Nil)` when nothing is pending.
 */
export function pact_map_pending(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => {
      return $runtime_core.pact_map_pending(_capture, address, key);
    },
  );
}

/**
 * The accepted entry for `key`, which is the value with its sequence number.
 * The result is `Error(Nil)` when the key has no accepted value.
 */
export function pact_map_get_with_details(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => {
      return $runtime_core.pact_map_get_with_details(_capture, address, key);
    },
  );
}

/**
 * Append `value` to the ordered collection at `address`. An attached channel
 * is not optimistic, and the value takes effect when the operation sequences.
 * A detached channel adds the value immediately.
 */
export function ordered_add(runtime, address, value) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.ordered_add(core, address, value); },
  );
}

/**
 * Acquire the head of the ordered collection at `address`, and return the new
 * acquire id for a later `ordered_complete` or `ordered_release` call. The
 * acquired item arrives in the `Acquired` event, because the queue is not
 * optimistic.
 */
export function ordered_acquire(runtime, address) {
  let acquire_id = $id.uuid_v4();
  edit(
    runtime.cell,
    (core) => {
      return $runtime_core.ordered_acquire(core, address, acquire_id);
    },
  );
  return acquire_id;
}

function register_acquire_waiter(
  cell,
  address,
  acquire_id,
  resolve_outcome,
  immediate_outcome
) {
  let state = cell_get(cell);
  if (immediate_outcome instanceof Some) {
    let outcome = immediate_outcome[0];
    return observe(
      "acquire outcome",
      () => { return resolve_outcome(outcome); },
    );
  } else {
    return cell_set(
      cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        state.phase,
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        state.claim_waiters,
        $dict.insert(
          state.acquire_waiters,
          [address, acquire_id],
          resolve_outcome,
        ),
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        state.pending_summary,
        state.scheduler,
      ),
    );
  }
}

/**
 * The same as `ordered_acquire`, and the function also reports the consensus
 * outcome of the acquire.
 *
 * `on_outcome` runs exactly one time. It gives `AcquiredItem` when this client
 * won the head. It gives `QueueEmpty` when the queue became empty before the
 * operation sequenced. An acquire that loses emits no event, so `QueueEmpty`
 * is the only signal that a loser receives. It gives `Aborted` when the
 * document closes while the acquire is still in flight. A detached channel
 * resolves immediately.
 */
export function ordered_acquire_with_outcome(runtime, address, on_outcome) {
  let acquire_id = $id.uuid_v4();
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    observe(
      "acquire outcome",
      () => {
        return on_outcome(
          $ordered_collection_kernel.AcquireOutcome$Aborted$const,
        );
      },
    );
    return acquire_id;
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = $runtime_core.ordered_acquire_submit(core, address, acquire_id);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let immediate_outcome = $1[0][3];
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core$1),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      register_acquire_waiter(
        runtime.cell,
        address,
        acquire_id,
        on_outcome,
        immediate_outcome,
      );
      fan_out(state.subscribers, events);
      return acquire_id;
    } else {
      observe(
        "acquire outcome",
        () => {
          return on_outcome(
            $ordered_collection_kernel.AcquireOutcome$Aborted$const,
          );
        },
      );
      return acquire_id;
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let $1 = $runtime_core.ordered_acquire_submit(core, address, acquire_id);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let outbound = $1[0][2];
      let immediate_outcome = $1[0][3];
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Ready(core$1, resubmit_at),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      register_acquire_waiter(
        runtime.cell,
        address,
        acquire_id,
        on_outcome,
        immediate_outcome,
      );
      if (resubmit_at instanceof Some) {
        undefined;
      } else {
        send_outbound(state.channel, core$1.client_id, outbound);
      }
      fan_out(state.subscribers, events);
      return acquire_id;
    } else {
      observe(
        "acquire outcome",
        () => {
          return on_outcome(
            $ordered_collection_kernel.AcquireOutcome$Aborted$const,
          );
        },
      );
      return acquire_id;
    }
  } else {
    observe(
      "acquire outcome",
      () => {
        return on_outcome(
          $ordered_collection_kernel.AcquireOutcome$Aborted$const,
        );
      },
    );
    return acquire_id;
  }
}

/**
 * Complete the held job `acquire_id` in the ordered collection at `address`.
 */
export function ordered_complete(runtime, address, acquire_id) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.ordered_complete(core, address, acquire_id);
    },
  );
}

/**
 * Release the held job `acquire_id` back to the ordered collection at
 * `address`.
 */
export function ordered_release(runtime, address, acquire_id) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.ordered_release(core, address, acquire_id);
    },
  );
}

/**
 * The number of items in the queue at `address`, which are the items that no
 * client acquired yet. The result is `Error(Nil)` when the address does not exist,
 * and when it does not name an ordered-collection channel.
 */
export function ordered_size(runtime, address) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.ordered_size(_capture, address); },
  );
}

/**
 * The values in the queue at `address`, which no client acquired yet, front
 * first.
 */
export function ordered_queue(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.ordered_queue(_capture, address); },
  );
}

/**
 * The jobs that clients hold at `address` now, keyed by acquire id and sorted
 * by that id.
 */
export function ordered_jobs(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.ordered_jobs(_capture, address); },
  );
}

/**
 * Submit a json0 operation to the channel at `address`, optimistically.
 */
export function submit_json_ot(runtime, address, components) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.submit_json_ot(core, address, components); },
  );
}

/**
 * The optimistic document of the json0 channel. The result is `Error(Nil)` when the
 * address does not exist, and when it does not name a json0 channel.
 */
export function json_ot_view(runtime, address) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.json_ot_view(_capture, address); },
  );
}

/**
 * Submit a rich-text delta to the channel at `address`, optimistically.
 */
export function submit_rich_text(runtime, address, delta) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.submit_rich_text(core, address, delta); },
  );
}

/**
 * The optimistic document of the rich-text channel. The result is `Error(Nil)` when
 * the address does not exist, and when it does not name a rich-text
 * channel.
 */
export function rich_text_view(runtime, address) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.rich_text_view(_capture, address); },
  );
}

export function or_map_increment(runtime, address, key, amount) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.or_map_increment(core, address, key, amount);
    },
  );
}

export function or_map_set(runtime, address, key, value) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.or_map_set(
        core,
        address,
        key,
        value,
        $transport_js.now_milliseconds(),
      );
    },
  );
}

export function or_map_remove(runtime, address, key) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.or_map_remove(core, address, key); },
  );
}

export function or_map_add_member(runtime, address, key, member) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.or_map_add_member(core, address, key, member);
    },
  );
}

export function or_map_set_mv_register(runtime, address, key, value) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.or_map_set_mv_register(core, address, key, value);
    },
  );
}

export function or_map_remove_member(runtime, address, key, member) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.or_map_remove_member(core, address, key, member);
    },
  );
}

export function or_map_remove_key(runtime, address, key) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => { return $runtime_core.or_map_remove(core, address, key); },
  );
}

export function or_map_values(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.or_map_values(_capture, address, key); },
  );
}

export function or_map_value(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.or_map_value(_capture, address, key); },
  );
}

export function or_map_entries(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.or_map_entries(_capture, address); },
  );
}

export function or_map_keys(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.or_map_keys(_capture, address); },
  );
}

export function or_set_add(runtime, address, element) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.or_set_add(core, address, element); },
  );
}

export function or_set_remove(runtime, address, element) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.or_set_remove(core, address, element); },
  );
}

export function or_set_contains(runtime, address, element) {
  return read(
    runtime.cell,
    false,
    (_capture) => {
      return $runtime_core.or_set_contains(_capture, address, element);
    },
  );
}

export function or_set_values(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.or_set_values(_capture, address); },
  );
}

export function g_set_add(runtime, address, element) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.g_set_add(core, address, element); },
  );
}

export function g_set_contains(runtime, address, element) {
  return read(
    runtime.cell,
    false,
    (_capture) => {
      return $runtime_core.g_set_contains(_capture, address, element);
    },
  );
}

export function g_set_values(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.g_set_values(_capture, address); },
  );
}

export function sequence_insert(runtime, address, index, value) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.sequence_insert(core, address, index, value);
    },
  );
}

export function sequence_delete(runtime, address, index) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => { return $runtime_core.sequence_delete(core, address, index); },
  );
}

export function sequence_move(runtime, address, from_index, to_index) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.sequence_move(core, address, from_index, to_index);
    },
  );
}

export function sequence_replace(runtime, address, index, value) {
  return edit_sequence_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.sequence_replace(core, address, index, value);
    },
  );
}

export function sequence_values(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.sequence_values(_capture, address); },
  );
}

export function sequence_length(runtime, address) {
  return read(
    runtime.cell,
    0,
    (_capture) => { return $runtime_core.sequence_length(_capture, address); },
  );
}

function edit_text_with_result(cell, operate) {
  let state = cell_get(cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return new Error("text edit before the document connection is ready");
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = operate(core);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      cell_set(
        cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core$1),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      fan_out(state.subscribers, events);
      return new Ok(undefined);
    } else {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.TextOperationFailed) {
        let detail = $2.detail;
        return new Error(detail);
      } else {
        let error = $2;
        return new Error($string.inspect(error));
      }
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let $1 = operate(core);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let outbound = $1[0][2];
      cell_set(
        cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Ready(core$1, resubmit_at),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      if (resubmit_at instanceof Some) {
        undefined;
      } else {
        send_outbound(state.channel, core$1.client_id, outbound);
      }
      fan_out(state.subscribers, events);
      return new Ok(undefined);
    } else {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.TextOperationFailed) {
        let detail = $2.detail;
        return new Error(detail);
      } else {
        let error = $2;
        return new Error($string.inspect(error));
      }
    }
  } else {
    return new Error("text edit before the document connection is ready");
  }
}

/**
 * Insert `value` at the optimistic grapheme `index`. An empty `value` at a
 * valid index changes nothing. The result is `Ok(Nil)`, and the runtime sends
 * no operation. See the module docs of `text_kernel`.
 */
export function text_insert(runtime, address, index, value) {
  return edit_text_with_result(
    runtime.cell,
    (core) => { return $runtime_core.text_insert(core, address, index, value); },
  );
}

/**
 * Delete the graphemes in `[start, end)`. An empty range with valid bounds
 * changes nothing.
 */
export function text_delete_range(runtime, address, start, end) {
  return edit_text_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.text_delete_range(core, address, start, end);
    },
  );
}

/**
 * Replace the graphemes in `[start, end)` with `value`. Only an empty range
 * that you replace with `""` changes nothing.
 */
export function text_replace_range(runtime, address, start, end, value) {
  return edit_text_with_result(
    runtime.cell,
    (core) => {
      return $runtime_core.text_replace_range(core, address, start, end, value);
    },
  );
}

/**
 * Insert `value` at the end of the text. An empty `value` changes nothing.
 */
export function text_append(runtime, address, value) {
  return edit_text_with_result(
    runtime.cell,
    (core) => { return $runtime_core.text_append(core, address, value); },
  );
}

/**
 * The current visible optimistic string of the text channel. The result is
 * `""` when the address does not exist, and when it does not name a text
 * channel.
 */
export function text_value(runtime, address) {
  return read(
    runtime.cell,
    "",
    (_capture) => { return $runtime_core.text_value(_capture, address); },
  );
}

/**
 * The current optimistic grapheme count of the text channel. The result is `0`
 * when the address does not exist, and when it does not name a text
 * channel.
 */
export function text_length(runtime, address) {
  return read(
    runtime.cell,
    0,
    (_capture) => { return $runtime_core.text_length(_capture, address); },
  );
}

/**
 * The graphemes in `[start, end)` of the optimistic string of the text
 * channel.
 */
export function text_substring(runtime, address, start, end) {
  return read(
    runtime.cell,
    new Error("text_substring requires a ready document connection"),
    (_capture) => {
      return $runtime_core.text_substring(_capture, address, start, end);
    },
  );
}

/**
 * Create a stable anchor at the gap at `index`. `bias` selects the adjacent
 * grapheme that the anchor binds to. `Before` binds it to the grapheme after
 * the gap, and `After` binds it to the grapheme before the gap.
 */
export function text_anchor_at(runtime, address, index, bias) {
  return read(
    runtime.cell,
    new Error("text_anchor_at requires a ready document connection"),
    (_capture) => {
      return $runtime_core.text_anchor_at(_capture, address, index, bias);
    },
  );
}

/**
 * Resolve an anchor to a current optimistic grapheme index.
 */
export function text_resolve_anchor(runtime, address, anchor) {
  return read(
    runtime.cell,
    new Error("text_resolve_anchor requires a ready document connection"),
    (_capture) => {
      return $runtime_core.text_resolve_anchor(_capture, address, anchor);
    },
  );
}

/**
 * An anchor at the start of the text. It always resolves to 0. The function is
 * pure. It needs no `Runtime` value and no address, because the anchor carries
 * no document state.
 */
export function text_start_anchor() {
  return $runtime_core.text_start_anchor();
}

/**
 * An anchor at the end of the text. It always resolves to the current grapheme
 * count, and it moves as the text becomes longer. The function is pure, the
 * same as `text_start_anchor`.
 */
export function text_end_anchor() {
  return $runtime_core.text_end_anchor();
}

/**
 * Encode an anchor as a self-describing JSON value, for example to send it
 * through presence for a shared cursor.
 */
export function text_anchor_to_json(anchor) {
  return $runtime_core.text_anchor_to_json(anchor);
}

/**
 * Decode an anchor from a JSON string produced by `text_anchor_to_json`.
 */
export function text_anchor_from_json(json_string) {
  return $runtime_core.text_anchor_from_json(json_string);
}

export function create_directory(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitDirectory$const,
    "create_directory",
  );
}

export function directory_set(runtime, address, path, key, value) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.directory_set(core, address, path, key, value);
    },
  );
}

export function directory_delete(runtime, address, path, key) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.directory_delete(core, address, path, key);
    },
  );
}

export function directory_clear(runtime, address, path) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.directory_clear(core, address, path); },
  );
}

export function directory_create_subdirectory(runtime, address, path, name) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.directory_create_subdirectory(
        core,
        address,
        path,
        name,
      );
    },
  );
}

export function directory_delete_subdirectory(runtime, address, path, name) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.directory_delete_subdirectory(
        core,
        address,
        path,
        name,
      );
    },
  );
}

export function directory_get(runtime, address, path, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => {
      return $runtime_core.directory_get(_capture, address, path, key);
    },
  );
}

export function directory_entries(runtime, address, path) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => {
      return $runtime_core.directory_entries(_capture, address, path);
    },
  );
}

export function directory_subdirectories(runtime, address, path) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => {
      return $runtime_core.directory_subdirectories(_capture, address, path);
    },
  );
}

export function directory_has_subdirectory(runtime, address, path, name) {
  return read(
    runtime.cell,
    false,
    (_capture) => {
      return $runtime_core.directory_has_subdirectory(
        _capture,
        address,
        path,
        name,
      );
    },
  );
}

export function two_p_set_add(runtime, address, element) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.two_p_set_add(core, address, element); },
  );
}

export function two_p_set_remove(runtime, address, element) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.two_p_set_remove(core, address, element); },
  );
}

export function two_p_set_contains(runtime, address, element) {
  return read(
    runtime.cell,
    false,
    (_capture) => {
      return $runtime_core.two_p_set_contains(_capture, address, element);
    },
  );
}

export function two_p_set_values(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.two_p_set_values(_capture, address); },
  );
}

export function register_write(runtime, address, key, value) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.register_write(core, address, key, value); },
  );
}

export function register_read(runtime, address, key, policy) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => {
      return $runtime_core.register_read(_capture, address, key, policy);
    },
  );
}

export function register_versions(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => {
      return $runtime_core.register_versions(_capture, address, key);
    },
  );
}

export function register_keys(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => { return $runtime_core.register_keys(_capture, address); },
  );
}

export function get_claim(runtime, address, key) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.get_claim(_capture, address, key); },
  );
}

export function has_claim(runtime, address, key) {
  return read(
    runtime.cell,
    false,
    (_capture) => { return $runtime_core.has_claim(_capture, address, key); },
  );
}

function register_claim_waiter(
  cell,
  address,
  key,
  resolve_outcome,
  immediate_outcome
) {
  let state = cell_get(cell);
  if (immediate_outcome instanceof Some) {
    let outcome = immediate_outcome[0];
    return observe("claim outcome", () => { return resolve_outcome(outcome); });
  } else {
    return cell_set(
      cell,
      new State(
        state.connect_message,
        state.http_base_url,
        state.channel,
        state.phase,
        state.subscribers,
        state.ripple_subscribers,
        state.presence_subscribers,
        state.supported_features,
        $dict.insert(state.claim_waiters, [address, key], resolve_outcome),
        state.acquire_waiters,
        state.on_ready,
        state.ready_fired,
        state.bootstrap_generation,
        state.bootstrap,
        state.auto_summary,
        state.summary_armed,
        state.pending_summary,
        state.scheduler,
      ),
    );
  }
}

function claim_submit(cell, address, key, operate) {
  let state = cell_get(cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return ClaimSubmitReply$WrongChannelType$const;
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = operate(core);
    if ($1 instanceof Ok) {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.ClaimPending) {
        let core$1 = $2.core;
        let immediate_outcome = $2.immediate_outcome;
        let $3 = $promise.start();
        let promise_outcome = $3[0];
        let resolve_outcome = $3[1];
        cell_set(
          cell,
          new State(
            state.connect_message,
            state.http_base_url,
            state.channel,
            new Reconnecting(core$1),
            state.subscribers,
            state.ripple_subscribers,
            state.presence_subscribers,
            state.supported_features,
            state.claim_waiters,
            state.acquire_waiters,
            state.on_ready,
            state.ready_fired,
            state.bootstrap_generation,
            state.bootstrap,
            state.auto_summary,
            state.summary_armed,
            state.pending_summary,
            state.scheduler,
          ),
        );
        register_claim_waiter(
          cell,
          address,
          key,
          resolve_outcome,
          immediate_outcome,
        );
        return new Pending(promise_outcome);
      } else if ($2 instanceof $runtime_core.ClaimAlreadyClaimed) {
        let current_value = $2.current_value;
        return new AlreadyClaimed(current_value);
      } else {
        return ClaimSubmitReply$AlreadyPendingLocally$const;
      }
    } else {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.WrongChannelType) {
        return ClaimSubmitReply$WrongChannelType$const;
      } else {
        return ClaimSubmitReply$WrongChannelType$const;
      }
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let $1 = operate(core);
    if ($1 instanceof Ok) {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.ClaimPending) {
        let core$1 = $2.core;
        let outbound = $2.outbound;
        let immediate_outcome = $2.immediate_outcome;
        let $3 = $promise.start();
        let promise_outcome = $3[0];
        let resolve_outcome = $3[1];
        cell_set(
          cell,
          new State(
            state.connect_message,
            state.http_base_url,
            state.channel,
            new Ready(core$1, resubmit_at),
            state.subscribers,
            state.ripple_subscribers,
            state.presence_subscribers,
            state.supported_features,
            state.claim_waiters,
            state.acquire_waiters,
            state.on_ready,
            state.ready_fired,
            state.bootstrap_generation,
            state.bootstrap,
            state.auto_summary,
            state.summary_armed,
            state.pending_summary,
            state.scheduler,
          ),
        );
        register_claim_waiter(
          cell,
          address,
          key,
          resolve_outcome,
          immediate_outcome,
        );
        if (resubmit_at instanceof Some) {
          undefined;
        } else {
          send_outbound(state.channel, core$1.client_id, outbound);
        }
        return new Pending(promise_outcome);
      } else if ($2 instanceof $runtime_core.ClaimAlreadyClaimed) {
        let current_value = $2.current_value;
        return new AlreadyClaimed(current_value);
      } else {
        return ClaimSubmitReply$AlreadyPendingLocally$const;
      }
    } else {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.WrongChannelType) {
        return ClaimSubmitReply$WrongChannelType$const;
      } else {
        return ClaimSubmitReply$WrongChannelType$const;
      }
    }
  } else {
    return ClaimSubmitReply$WrongChannelType$const;
  }
}

export function claim_once(runtime, address, key, value) {
  return claim_submit(
    runtime.cell,
    address,
    key,
    (core) => { return $runtime_core.claim_once(core, address, key, value); },
  );
}

export function compare_and_set_claim(runtime, address, key, value) {
  return claim_submit(
    runtime.cell,
    address,
    key,
    (core) => {
      return $runtime_core.compare_and_set_claim(core, address, key, value);
    },
  );
}

export function task_manager_volunteer(runtime, address, task_id) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return $task_manager_kernel.VolunteerOutcome$DisconnectedBeforeAssignment$const;
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = $runtime_core.task_manager_volunteer(core, address, task_id);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let outcome = $1[0][3];
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core$1),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      fan_out(state.subscribers, events);
      return outcome;
    } else {
      return $task_manager_kernel.VolunteerOutcome$DisconnectedBeforeAssignment$const;
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let $1 = $runtime_core.task_manager_volunteer(core, address, task_id);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let outbound = $1[0][2];
      let outcome = $1[0][3];
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Ready(core$1, resubmit_at),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      if (resubmit_at instanceof Some) {
        undefined;
      } else {
        send_outbound(state.channel, core$1.client_id, outbound);
      }
      fan_out(state.subscribers, events);
      return outcome;
    } else {
      return $task_manager_kernel.VolunteerOutcome$DisconnectedBeforeAssignment$const;
    }
  } else {
    return $task_manager_kernel.VolunteerOutcome$DisconnectedBeforeAssignment$const;
  }
}

export function task_manager_abandon(runtime, address, task_id) {
  return edit(
    runtime.cell,
    (core) => {
      return $runtime_core.task_manager_abandon(core, address, task_id);
    },
  );
}

export function task_manager_complete(runtime, address, task_id) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return new Error("complete_task requires a ready document connection");
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = $runtime_core.task_manager_complete(core, address, task_id);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core$1),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      fan_out(state.subscribers, events);
      return new Ok(undefined);
    } else {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.TaskNotAssigned) {
        let task_id$1 = $2.task_id;
        return new Error("task is not assigned: " + task_id$1);
      } else {
        let core_error = $2;
        return new Error("complete_task failed: " + $string.inspect(core_error));
      }
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let resubmit_at = $.resubmit_at;
    let $1 = $runtime_core.task_manager_complete(core, address, task_id);
    if ($1 instanceof Ok) {
      let core$1 = $1[0][0];
      let events = $1[0][1];
      let outbound = $1[0][2];
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Ready(core$1, resubmit_at),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      if (resubmit_at instanceof Some) {
        undefined;
      } else {
        send_outbound(state.channel, core$1.client_id, outbound);
      }
      fan_out(state.subscribers, events);
      return new Ok(undefined);
    } else {
      let $2 = $1[0];
      if ($2 instanceof $runtime_core.TaskNotAssigned) {
        let task_id$1 = $2.task_id;
        return new Error("task is not assigned: " + task_id$1);
      } else {
        let core_error = $2;
        return new Error("complete_task failed: " + $string.inspect(core_error));
      }
    }
  } else {
    return new Error("complete_task requires a ready document connection");
  }
}

export function task_manager_assigned(runtime, address, task_id) {
  return read(
    runtime.cell,
    false,
    (_capture) => {
      return $runtime_core.task_manager_assigned(_capture, address, task_id);
    },
  );
}

export function task_manager_queued(runtime, address, task_id) {
  return read(
    runtime.cell,
    false,
    (_capture) => {
      return $runtime_core.task_manager_queued(_capture, address, task_id);
    },
  );
}

export function task_manager_queues(runtime, address) {
  return read(
    runtime.cell,
    $List$Empty$const,
    (_capture) => {
      return $runtime_core.task_manager_queues(_capture, address);
    },
  );
}

/**
 * Create a new detached map channel. It is local only, until a caller stores
 * its handle into an attached map. The function returns the address that the
 * runtime generated.
 */
export function create_map(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitMap$const,
    "create_map",
  );
}

/**
 * Create a new detached counter channel. The lifecycle is the same as for
 * `create_map`.
 */
export function create_counter(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitCounter$const,
    "create_counter",
  );
}

/**
 * Create a new detached PN-counter channel. The lifecycle is the same as for
 * `create_map`.
 */
export function create_pn_counter(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitPnCounter$const,
    "create_pn_counter",
  );
}

/**
 * Create a new detached grow-only counter channel. The lifecycle is the same
 * as for `create_map`.
 */
export function create_g_counter(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitGCounter$const,
    "create_g_counter",
  );
}

/**
 * Create a detached LWW-register channel. The lifecycle is the same as for
 * `create_map`.
 */
export function create_lww_register(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitLwwRegister$const,
    "create_lww_register",
  );
}

/**
 * Create a new detached PactMap channel, which is a consensus map. The
 * lifecycle is the same as for `create_map`.
 */
export function create_pact_map(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitPactMap$const,
    "create_pact_map",
  );
}

/**
 * Create a new detached ConsensusOrderedCollection channel. The lifecycle is
 * the same as for `create_map`.
 */
export function create_ordered_collection(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitOrderedCollection$const,
    "create_ordered_collection",
  );
}

export function create_or_map(runtime, mode) {
  return create_channel(runtime, new $channel.InitOrMap(mode), "create_or_map");
}

export function create_or_set(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitOrSet$const,
    "create_or_set",
  );
}

export function create_g_set(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitGSet$const,
    "create_g_set",
  );
}

export function create_sequence(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitSequence$const,
    "create_sequence",
  );
}

/**
 * Create a new detached text channel. The lifecycle is the same as for
 * `create_map`.
 */
export function create_text(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitText$const,
    "create_text",
  );
}

export function create_two_p_set(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitTwoPSet$const,
    "create_two_p_set",
  );
}

export function create_register_collection(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitRegisterCollection$const,
    "create_register_collection",
  );
}

export function create_claims(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitClaims$const,
    "create_claims",
  );
}

/**
 * Create a new detached json0 channel. The lifecycle is the same as for
 * `create_map`.
 */
export function create_json_ot(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitJsonOt$const,
    "create_json_ot",
  );
}

/**
 * Create a new detached rich-text channel. The lifecycle is the same as for
 * `create_map`.
 */
export function create_rich_text(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitRichText$const,
    "create_rich_text",
  );
}

export function create_task_manager(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitTaskManager$const,
    "create_task_manager",
  );
}

/**
 * Whether a channel exists at `address`, attached or detached. A caller can
 * retry after an error, because an attach from another client can still be in
 * flight.
 */
export function resolve_address(runtime, address) {
  let $ = read(
    runtime.cell,
    false,
    (_capture) => { return $runtime_core.has_channel(_capture, address); },
  );
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(
      ("unresolved handle: no channel at address " + address) + " (a foreign attach may still be in flight; retry)",
    );
  }
}

export function resolve_sequence(runtime, address) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return new Error("resolve_sequence requires a ready document connection");
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = $runtime_core.require_channel_type(
      core,
      address,
      $channel.ChannelType$SequenceChannel$const,
    );
    if ($1 instanceof Ok) {
      return $1;
    } else {
      let error = $1[0];
      return new Error($string.inspect(error));
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let $1 = $runtime_core.require_channel_type(
      core,
      address,
      $channel.ChannelType$SequenceChannel$const,
    );
    if ($1 instanceof Ok) {
      return $1;
    } else {
      let error = $1[0];
      return new Error($string.inspect(error));
    }
  } else {
    return new Error("resolve_sequence requires a ready document connection");
  }
}

export function resolve_text(runtime, address) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return new Error("resolve_text requires a ready document connection");
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    let $1 = $runtime_core.require_channel_type(
      core,
      address,
      $channel.ChannelType$TextChannel$const,
    );
    if ($1 instanceof Ok) {
      return $1;
    } else {
      let error = $1[0];
      return new Error($string.inspect(error));
    }
  } else if ($ instanceof Ready) {
    let core = $.core;
    let $1 = $runtime_core.require_channel_type(
      core,
      address,
      $channel.ChannelType$TextChannel$const,
    );
    if ($1 instanceof Ok) {
      return $1;
    } else {
      let error = $1[0];
      return new Error($string.inspect(error));
    }
  } else {
    return new Error("resolve_text requires a ready document connection");
  }
}

/**
 * Register a callback that the runtime calls for every local event and remote
 * event on the channel at `address`.
 */
export function subscribe(runtime, address, handler) {
  let state = cell_get(runtime.cell);
  let token_id = $id.uuid_v4();
  cell_set(
    runtime.cell,
    new State(
      state.connect_message,
      state.http_base_url,
      state.channel,
      state.phase,
      listPrepend(new Subscriber(token_id, address, handler), state.subscribers),
      state.ripple_subscribers,
      state.presence_subscribers,
      state.supported_features,
      state.claim_waiters,
      state.acquire_waiters,
      state.on_ready,
      state.ready_fired,
      state.bootstrap_generation,
      state.bootstrap,
      state.auto_summary,
      state.summary_armed,
      state.pending_summary,
      state.scheduler,
    ),
  );
  return new SubscriptionToken(runtime, token_id);
}

/**
 * Remove a channel subscription. A second call has no more effect.
 */
export function unsubscribe(token) {
  let runtime = token.runtime;
  let state = cell_get(runtime.cell);
  return cell_set(
    runtime.cell,
    new State(
      state.connect_message,
      state.http_base_url,
      state.channel,
      state.phase,
      $list.filter(
        state.subscribers,
        (subscriber) => { return subscriber.id !== token.id; },
      ),
      state.ripple_subscribers,
      state.presence_subscribers,
      state.supported_features,
      state.claim_waiters,
      state.acquire_waiters,
      state.on_ready,
      state.ready_fired,
      state.bootstrap_generation,
      state.bootstrap,
      state.auto_summary,
      state.summary_armed,
      state.pending_summary,
      state.scheduler,
    ),
  );
}

function client_id_of(state) {
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return Option$None$const;
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    return new Some(core.client_id);
  } else if ($ instanceof Ready) {
    let core = $.core;
    return new Some(core.client_id);
  } else {
    return Option$None$const;
  }
}

/**
 * The client id that the server assigned to this connection. The result is
 * `None` before the first handshake completes.
 *
 * A reconnect does not keep the value. There is always *a* current id, and
 * `adopt_reconnect` replaces it with the id that the new handshake assigns.
 * That id can differ from the previous one. A caller that holds the id across
 * a disconnect must read it again. It must not use a cached value.
 */
export function client_id(runtime) {
  return client_id_of(cell_get(runtime.cell));
}

/**
 * Broadcast an ephemeral ripple to this document, with a `type` field and any
 * JSON `content`. A ripple does not sequence and no server stores it. It
 * expects no reply, and it has no ack, no resubmit, and no catch-up. The
 * function does nothing until the server assigns a client id, which is until
 * the first handshake completes.
 */
export function send_ripple(runtime, ripple_type, content) {
  let state = cell_get(runtime.cell);
  let $ = state.channel;
  let $1 = client_id_of(state);
  if ($ instanceof Some && $1 instanceof Some) {
    let channel = $[0];
    let client_id$1 = $1[0];
    return push_json(
      channel,
      "submitSignal",
      $socket.encode_submit_ripple(client_id$1, ripple_type, content),
    );
  } else {
    return undefined;
  }
}

/**
 * Register a callback that the runtime calls for every inbound ephemeral
 * ripple on the document. The content stays a `Dynamic` value, for the caller
 * to decode.
 */
export function subscribe_ripples(runtime, handler) {
  let state = cell_get(runtime.cell);
  return cell_set(
    runtime.cell,
    new State(
      state.connect_message,
      state.http_base_url,
      state.channel,
      state.phase,
      state.subscribers,
      listPrepend(handler, state.ripple_subscribers),
      state.presence_subscribers,
      state.supported_features,
      state.claim_waiters,
      state.acquire_waiters,
      state.on_ready,
      state.ready_fired,
      state.bootstrap_generation,
      state.bootstrap,
      state.auto_summary,
      state.summary_armed,
      state.pending_summary,
      state.scheduler,
    ),
  );
}

/**
 * Push a command on the presence lane, which is `joinPresence`,
 * `updatePresence`, or `leavePresence`. The function does nothing before the
 * channel exists.
 *
 * Unlike `send_ripple`, this function does not wait for a client id. A
 * presence payload carries no identity at all, because the server derives the
 * key and the session from the authenticated connection.
 */
export function send_presence(runtime, event, payload) {
  let $ = cell_get(runtime.cell).channel;
  if ($ instanceof Some) {
    let channel = $[0];
    return push_json(channel, event, payload);
  } else {
    return undefined;
  }
}

/**
 * Register a callback for every frame on the presence lane, both a data frame
 * and a lifecycle frame. Each data-frame payload stays the raw event JSON, as
 * a `String`, for the typed driver to decode with its own decoder.
 */
export function subscribe_presence(runtime, handler) {
  let state = cell_get(runtime.cell);
  return cell_set(
    runtime.cell,
    new State(
      state.connect_message,
      state.http_base_url,
      state.channel,
      state.phase,
      state.subscribers,
      state.ripple_subscribers,
      listPrepend(handler, state.presence_subscribers),
      state.supported_features,
      state.claim_waiters,
      state.acquire_waiters,
      state.on_ready,
      state.ready_fired,
      state.bootstrap_generation,
      state.bootstrap,
      state.auto_summary,
      state.summary_armed,
      state.pending_summary,
      state.scheduler,
    ),
  );
}

/**
 * Whether the handshake of the *current* connection announced `presence_v1`.
 * The result is `False` before the first handshake settles.
 */
export function supports_presence(runtime) {
  return $socket.supports_feature(
    cell_get(runtime.cell).supported_features,
    $socket.feature_presence_v1,
  );
}

/**
 * The authenticated user id that this runtime connected with. Server presence
 * derives its presence key from the same value. Ripple mode reads that value
 * here, so the two implementations use the same key for their rosters.
 */
export function user_id(runtime) {
  return cell_get(runtime.cell).connect_message.client.user.id;
}

/**
 * A hook that injects a fault. It closes the socket, so that the runtime runs
 * its reconnect and reconcile path.
 */
export function force_reconnect(runtime) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  let $1 = state.channel;
  if ($1 instanceof Some) {
    if ($ instanceof Connecting) {
      return undefined;
    } else if ($ instanceof Reconnecting) {
      return undefined;
    } else if ($ instanceof Ready) {
      let channel = $1[0];
      let core = $.core;
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      notify_session_lost(runtime.cell, state.phase);
      return channel.drop();
    } else {
      return undefined;
    }
  } else if ($ instanceof Connecting) {
    return undefined;
  } else if ($ instanceof Reconnecting) {
    return undefined;
  } else if ($ instanceof Ready) {
    return undefined;
  } else {
    return undefined;
  }
}

/**
 * Go offline and stay offline. The function holds the connection closed, and
 * the document continues to accept local edits. `go_online` opens the
 * connection again.
 *
 * The phase stays at `Reconnecting`, which is a state that the runtime already
 * serves in full. A read and an edit both work, the edits collect as pending
 * entries, and the rejoin handshake carries `last_seen` and sends them. This
 * function adds no state machine. The one new behaviour is that the socket
 * does not open again by itself.
 *
 * An offline toggle needs this function, and neither of the two similar hooks
 * gives it. `force_reconnect` goes away and comes back with no interval
 * between. `close` is terminal, and to reconnect after it means a new runtime,
 * whose empty core holds none of the edits from that interval.
 */
export function go_offline(runtime) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  let $1 = state.channel;
  if ($1 instanceof Some) {
    if ($ instanceof Connecting) {
      return undefined;
    } else if ($ instanceof Reconnecting) {
      return undefined;
    } else if ($ instanceof Ready) {
      let channel = $1[0];
      let core = $.core;
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          state.channel,
          new Reconnecting(core),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          state.claim_waiters,
          state.acquire_waiters,
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation,
          state.bootstrap,
          state.auto_summary,
          state.summary_armed,
          state.pending_summary,
          state.scheduler,
        ),
      );
      notify_session_lost(runtime.cell, state.phase);
      return channel.hold();
    } else {
      return undefined;
    }
  } else if ($ instanceof Connecting) {
    return undefined;
  } else if ($ instanceof Reconnecting) {
    return undefined;
  } else if ($ instanceof Ready) {
    return undefined;
  } else {
    return undefined;
  }
}

/**
 * Return from `go_offline`. The function does nothing unless the connection is
 * held, so an interface can bind it to a toggle and does not have to track the
 * phase.
 */
export function go_online(runtime) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  let $1 = state.channel;
  if ($1 instanceof Some) {
    if ($ instanceof Connecting) {
      return undefined;
    } else if ($ instanceof Reconnecting) {
      let channel = $1[0];
      return channel.resume();
    } else if ($ instanceof Ready) {
      return undefined;
    } else {
      return undefined;
    }
  } else if ($ instanceof Connecting) {
    return undefined;
  } else if ($ instanceof Reconnecting) {
    return undefined;
  } else if ($ instanceof Ready) {
    return undefined;
  } else {
    return undefined;
  }
}

export function close(runtime) {
  let state = cell_get(runtime.cell);
  return $bool.guard(
    state.channel instanceof None,
    undefined,
    () => {
      cell_set(
        runtime.cell,
        new State(
          state.connect_message,
          state.http_base_url,
          Option$None$const,
          new Failed("runtime closed"),
          state.subscribers,
          state.ripple_subscribers,
          state.presence_subscribers,
          state.supported_features,
          $dict.new$(),
          $dict.new$(),
          state.on_ready,
          state.ready_fired,
          state.bootstrap_generation + 1,
          Option$None$const,
          state.auto_summary,
          state.summary_armed,
          Option$None$const,
          state.scheduler,
        ),
      );
      abort_outcome_waiters(state);
      abort_pending_summary(state);
      notify_session_lost(runtime.cell, state.phase);
      let $ = state.channel;
      if ($ instanceof Some) {
        let channel = $[0];
        return channel.close();
      } else {
        return undefined;
      }
    },
  );
}

/**
 * Whether the document is caught up, which is true when the server acked every
 * local edit. The confirmed state is then complete and stable.
 */
export function is_synced(runtime) {
  let state = cell_get(runtime.cell);
  return $bool.guard(
    !(state.bootstrap instanceof None),
    false,
    () => {
      let $ = state.phase;
      if ($ instanceof Connecting) {
        return false;
      } else if ($ instanceof Reconnecting) {
        return false;
      } else if ($ instanceof Ready) {
        let $1 = $.resubmit_at;
        if ($1 instanceof Some) {
          return false;
        } else {
          let core = $.core;
          return $runtime_core.is_synced(core);
        }
      } else {
        return false;
      }
    },
  );
}

function diagnostics_from_core(core, phase, checkpoint, synced, state) {
  return new Diagnostics(
    phase,
    new Some(core.client_id),
    new Some(core.last_seen_sequence_number),
    new Some(core.next_client_sequence_number),
    $list.length(core.in_flight),
    $list.length(core.out_of_order),
    checkpoint,
    synced,
    $runtime_core.operations_since_summary(core),
    state.summary_armed || (!(state.pending_summary instanceof None)),
  );
}

/**
 * Take a snapshot of the connection state and the sequencing state, for
 * diagnostics. The function does not change the runtime, and a debug interface
 * can call it repeatedly.
 */
export function diagnostics(runtime) {
  let state = cell_get(runtime.cell);
  let $ = state.phase;
  if ($ instanceof Connecting) {
    return new Diagnostics(
      "connecting",
      Option$None$const,
      Option$None$const,
      Option$None$const,
      0,
      0,
      Option$None$const,
      false,
      0,
      false,
    );
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    return diagnostics_from_core(
      core,
      "reconnecting",
      Option$None$const,
      false,
      state,
    );
  } else if ($ instanceof Ready) {
    let $1 = $.resubmit_at;
    if ($1 instanceof Some) {
      let core = $.core;
      let checkpoint = $1[0];
      return diagnostics_from_core(
        core,
        "catching-up",
        new Some(checkpoint),
        false,
        state,
      );
    } else {
      let core = $.core;
      let $2 = state.bootstrap;
      if ($2 instanceof Some) {
        return diagnostics_from_core(
          core,
          "catching-up",
          Option$None$const,
          false,
          state,
        );
      } else {
        return diagnostics_from_core(
          core,
          "ready",
          Option$None$const,
          $runtime_core.is_synced(core),
          state,
        );
      }
    }
  } else {
    let reason = $.reason;
    return new Diagnostics(
      "failed: " + reason,
      Option$None$const,
      Option$None$const,
      Option$None$const,
      0,
      0,
      Option$None$const,
      false,
      0,
      false,
    );
  }
}

/**
 * Replace the scheduler of the runtime. This is a test seam for the in-memory
 * hub, which binds the delayed work to its logical clock. A production runtime
 * keeps the real `setTimeout` function that it started with. You can call this
 * function before the first delayed operation is scheduled.
 */
export function set_scheduler(runtime, scheduler) {
  return cell_set(
    runtime.cell,
    (() => {
      let _record = cell_get(runtime.cell);
      return new State(
        _record.connect_message,
        _record.http_base_url,
        _record.channel,
        _record.phase,
        _record.subscribers,
        _record.ripple_subscribers,
        _record.presence_subscribers,
        _record.supported_features,
        _record.claim_waiters,
        _record.acquire_waiters,
        _record.on_ready,
        _record.ready_fired,
        _record.bootstrap_generation,
        _record.bootstrap,
        _record.auto_summary,
        _record.summary_armed,
        _record.pending_summary,
        scheduler,
      );
    })(),
  );
}

/**
 * Schedule delayed work with the runtime clock.
 */
export function schedule(runtime, action, milliseconds) {
  let $ = cell_get(runtime.cell).scheduler.schedule(action, milliseconds);
  
  return undefined;
}

/**
 * Install the automatic summarization policy. A value of `None` clears it.
 */
export function auto_summarize(runtime, policy) {
  return cell_set(
    runtime.cell,
    (() => {
      let _record = cell_get(runtime.cell);
      return new State(
        _record.connect_message,
        _record.http_base_url,
        _record.channel,
        _record.phase,
        _record.subscribers,
        _record.ripple_subscribers,
        _record.presence_subscribers,
        _record.supported_features,
        _record.claim_waiters,
        _record.acquire_waiters,
        _record.on_ready,
        _record.ready_fired,
        _record.bootstrap_generation,
        _record.bootstrap,
        policy,
        _record.summary_armed,
        _record.pending_summary,
        _record.scheduler,
      );
    })(),
  );
}

/**
 * How far the document moved past the newest checkpoint that this client knows
 * about. The result is zero before the first handshake.
 */
export function operations_since_summary(runtime) {
  let $ = cell_get(runtime.cell).phase;
  if ($ instanceof Connecting) {
    return 0;
  } else if ($ instanceof Reconnecting) {
    let core = $.core;
    return $runtime_core.operations_since_summary(core);
  } else if ($ instanceof Ready) {
    let core = $.core;
    return $runtime_core.operations_since_summary(core);
  } else {
    return 0;
  }
}

/**
 * List the stored summary versions of the document, newest first. This is the
 * client half of the `getVersions` function of Fluid. The token must carry the
 * `doc:read` scope.
 */
export function get_versions(runtime, count) {
  let state = cell_get(runtime.cell);
  let $ = state.connect_message.token;
  if ($ instanceof Some) {
    let token = $[0];
    let _pipe = $git_storage.fetch_versions(
      state.http_base_url,
      state.connect_message.tenant_id,
      token,
      state.connect_message.document_id,
      count,
    );
    return $promise.map(
      _pipe,
      (_capture) => {
        return $result.map_error(_capture, $git_storage.error_to_string);
      },
    );
  } else {
    return $promise.resolve(
      new Error("listing versions requires an auth token"),
    );
  }
}

/**
 * Read the snapshot that a published summary commit captured.
 * `get_versions` and the resolution of `summarize` both give the commit ID.
 * The function does not change the live document. It reads the stored
 * blob at one point in time.
 */
export function load_version(runtime, handle) {
  let state = cell_get(runtime.cell);
  let $ = state.connect_message.token;
  if ($ instanceof Some) {
    let token = $[0];
    let _pipe = $git_storage.fetch_summary(
      state.http_base_url,
      state.connect_message.tenant_id,
      token,
      handle,
    );
    return $promise.map(
      _pipe,
      (_capture) => {
        return $result.map_error(_capture, $git_storage.error_to_string);
      },
    );
  } else {
    return $promise.resolve(
      new Error("loading a version requires an auth token"),
    );
  }
}

export function create_mv_register(runtime) {
  return create_channel(
    runtime,
    $channel.ChannelInit$InitMvRegister$const,
    "create_mv_register",
  );
}

export function mv_register_set(runtime, address, value) {
  return edit(
    runtime.cell,
    (core) => { return $runtime_core.mv_register_set(core, address, value); },
  );
}

export function mv_register_values(runtime, address) {
  return read(
    runtime.cell,
    new Error(undefined),
    (_capture) => { return $runtime_core.mv_register_values(_capture, address); },
  );
}

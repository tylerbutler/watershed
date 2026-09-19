/// <reference types="./core.d.mts" />
import * as $json from "../../../gleam_json/gleam/json.mjs";
import * as $dict from "../../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.mjs";
import * as $int from "../../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../../gleam_stdlib/gleam/set.mjs";
import * as $string from "../../../gleam_stdlib/gleam/string.mjs";
import * as $sequencing from "../../../spillway/spillway/sequencing.mjs";
import * as $types from "../../../spillway/spillway/types.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../../gleam.mjs";
import * as $frame from "../../watershed/sluice/frame.mjs";
import { Sequenced } from "../../watershed/sluice/frame.mjs";

export class Outbound extends $CustomType {
  constructor(client_id, event, payload) {
    super();
    this.client_id = client_id;
    this.event = event;
    this.payload = payload;
  }
}
export const Outbound$Outbound = (client_id, event, payload) =>
  new Outbound(client_id, event, payload);
export const Outbound$isOutbound = (value) => value instanceof Outbound;
export const Outbound$Outbound$client_id = (value) => value.client_id;
export const Outbound$Outbound$0 = (value) => value.client_id;
export const Outbound$Outbound$event = (value) => value.event;
export const Outbound$Outbound$1 = (value) => value.event;
export const Outbound$Outbound$payload = (value) => value.payload;
export const Outbound$Outbound$2 = (value) => value.payload;

class ClientEntry extends $CustomType {
  constructor(client, scopes) {
    super();
    this.client = client;
    this.scopes = scopes;
  }
}

class Sluice extends $CustomType {
  constructor(document_id, tenant_id, sequence_state, log, clients, presence, next_presence_ref, presence_supported, paused, next_client_number, now_milliseconds, outbox) {
    super();
    this.document_id = document_id;
    this.tenant_id = tenant_id;
    this.sequence_state = sequence_state;
    this.log = log;
    this.clients = clients;
    this.presence = presence;
    this.next_presence_ref = next_presence_ref;
    this.presence_supported = presence_supported;
    this.paused = paused;
    this.next_client_number = next_client_number;
    this.now_milliseconds = now_milliseconds;
    this.outbox = outbox;
  }
}

/**
 * A new sluice for one document. `now_milliseconds` starts at 0, and only
 * `advance` moves it. The timestamps on the protocol frames thus stay
 * deterministic in a test.
 */
export function new$(tenant_id, document_id) {
  return new Sluice(
    document_id,
    tenant_id,
    $sequencing.new$(),
    $List$Empty$const,
    $dict.new$(),
    $dict.new$(),
    1,
    true,
    $set.new$(),
    1,
    0,
    $List$Empty$const,
  );
}

/**
 * Remove `presence_v1` from the handshake. A client in `Auto` mode thus
 * selects the ripple fallback, and a client that forces `Server` mode fails.
 * Call this function before `connect`.
 */
export function set_presence_supported(sluice, supported) {
  return new Sluice(
    sluice.document_id,
    sluice.tenant_id,
    sluice.sequence_state,
    sluice.log,
    sluice.clients,
    sluice.presence,
    sluice.next_presence_ref,
    supported,
    sluice.paused,
    sluice.next_client_number,
    sluice.now_milliseconds,
    sluice.outbox,
  );
}

/**
 * The logical wall clock of the sluice, in milliseconds. Only `advance` moves
 * it.
 */
export function now(sluice) {
  return sluice.now_milliseconds;
}

/**
 * Advance the logical clock used for protocol frame timestamps.
 */
export function advance(sluice, milliseconds) {
  return new Sluice(
    sluice.document_id,
    sluice.tenant_id,
    sluice.sequence_state,
    sluice.log,
    sluice.clients,
    sluice.presence,
    sluice.next_presence_ref,
    sluice.presence_supported,
    sluice.paused,
    sluice.next_client_number,
    sluice.now_milliseconds + milliseconds,
    sluice.outbox,
  );
}

/**
 * Reserve a client id for a connection that just opened. The sequencer learns
 * about the client only when its `connect_document` message arrives, in
 * `handle`. This function thus creates the id that the driver uses as the key
 * of the link, and it does nothing else.
 */
export function register(sluice) {
  let client_id = "sluice-client-" + $int.to_string(sluice.next_client_number);
  return [
    new Sluice(
      sluice.document_id,
      sluice.tenant_id,
      sluice.sequence_state,
      sluice.log,
      sluice.clients,
      sluice.presence,
      sluice.next_presence_ref,
      sluice.presence_supported,
      sluice.paused,
      sluice.next_client_number + 1,
      sluice.now_milliseconds,
      sluice.outbox,
    ),
    client_id,
  ];
}

function enqueue(sluice, client_id, event, payload) {
  return new Sluice(
    sluice.document_id,
    sluice.tenant_id,
    sluice.sequence_state,
    sluice.log,
    sluice.clients,
    sluice.presence,
    sluice.next_presence_ref,
    sluice.presence_supported,
    sluice.paused,
    sluice.next_client_number,
    sluice.now_milliseconds,
    $list.append(
      sluice.outbox,
      toList([new Outbound(client_id, event, payload)]),
    ),
  );
}

/**
 * The connected clients, in a stable order, sorted by id.
 */
export function connected_ids(sluice) {
  let _pipe = sluice.clients;
  let _pipe$1 = $dict.keys(_pipe);
  return $list.sort(_pipe$1, $string.compare);
}

/**
 * Queue one frame for every connected client. The operation echoes and the
 * broadcasts use this function.
 * 
 * @ignore
 */
function broadcast(sluice, event, payload) {
  let _pipe = connected_ids(sluice);
  return $list.fold(
    _pipe,
    sluice,
    (sluice, id) => { return enqueue(sluice, id, event, payload); },
  );
}

/**
 * Give the next sequence number to a system message, which is a `"join"` or a
 * `"leave"`, and append that message to the log. The function returns the
 * message, for the caller to route.
 *
 * A system message uses a sequence number, the same as an operation. Every
 * replica thus agrees on the position in the stream at which the membership
 * changed. That order is the purpose of the message, because a consensus
 * kernel settles its pending state at exactly that sequence point. `client_id`
 * is null and `contents` is null. The payload is in `data`.
 * 
 * @ignore
 */
function sequence_system(sluice, message_type, data) {
  let sequence_number$1 = $sequencing.current_sn(sluice.sequence_state) + 1;
  let _block;
  let _record = sluice.sequence_state;
  _block = new $sequencing.SequenceState(
    sequence_number$1,
    _record.minimum_sequence_number,
    _record.client_states,
  );
  let sequence_state = _block;
  let message = new Sequenced(
    Option$None$const,
    sequence_number$1,
    $sequencing.current_msn(sequence_state),
    -1,
    sequence_number$1 - 1,
    message_type,
    $json.null$(),
    Option$None$const,
    sluice.now_milliseconds,
    new Some(data),
  );
  return [
    new Sluice(
      sluice.document_id,
      sluice.tenant_id,
      sequence_state,
      listPrepend(message, sluice.log),
      sluice.clients,
      sluice.presence,
      sluice.next_presence_ref,
      sluice.presence_supported,
      sluice.paused,
      sluice.next_client_number,
      sluice.now_milliseconds,
      sluice.outbox,
    ),
    message,
  ];
}

/**
 * Broadcast a presence change to **every** connected client, and to the
 * joiner too. This differs from `on_signal`, which excludes the author, and
 * the difference is deliberate. Phoenix presence covers the whole topic, and
 * a joiner that never received its own join would hold a roster without
 * itself in it.
 * 
 * @ignore
 */
function broadcast_presence(sluice, joins, leaves) {
  return broadcast(
    sluice,
    "presence_diff",
    $frame.encode_presence_diff(joins, leaves),
  );
}

/**
 * Remove the presence of this connection. If the connection has no presence,
 * the function does nothing and reports nothing. A duplicate leave, or a
 * leave that races the cleanup of the socket, must not give an error.
 * 
 * @ignore
 */
function on_leave_presence(sluice, client_id) {
  let $ = $dict.get(sluice.presence, client_id);
  if ($ instanceof Ok) {
    let previous = $[0];
    let _pipe = new Sluice(
      sluice.document_id,
      sluice.tenant_id,
      sluice.sequence_state,
      sluice.log,
      sluice.clients,
      $dict.delete$(sluice.presence, client_id),
      sluice.next_presence_ref,
      sluice.presence_supported,
      sluice.paused,
      sluice.next_client_number,
      sluice.now_milliseconds,
      sluice.outbox,
    );
    return broadcast_presence(
      _pipe,
      $List$Empty$const,
      toList([[client_id, previous]]),
    );
  } else {
    return sluice;
  }
}

/**
 * Remove a client. The function sequences a `"leave"` message for the clients
 * that remain, and it removes the client from the MSN calculation of the
 * sequencer and from the paused set. `take` discards each queued frame that
 * the client did not receive.
 *
 * The leave settles the per-client kernel state on every replica that
 * remains, at one agreed sequence point. It releases the queue jobs of that
 * client and removes it from the consensus signoffs. A client that did not
 * complete `connect_document` is not in the roster, so its disconnect
 * sequences nothing.
 */
export function disconnect(sluice, client_id) {
  let known = $dict.has_key(sluice.clients, client_id);
  let sluice$1 = new Sluice(
    sluice.document_id,
    sluice.tenant_id,
    $sequencing.client_leave(sluice.sequence_state, client_id),
    sluice.log,
    $dict.delete$(sluice.clients, client_id),
    sluice.presence,
    sluice.next_presence_ref,
    sluice.presence_supported,
    $set.delete$(sluice.paused, client_id),
    sluice.next_client_number,
    sluice.now_milliseconds,
    sluice.outbox,
  );
  let sluice$2 = on_leave_presence(sluice$1, client_id);
  if (known) {
    let $ = sequence_system(
      sluice$2,
      "leave",
      $frame.system_leave_data(client_id),
    );
    let sluice$3 = $[0];
    let leave = $[1];
    return broadcast(
      sluice$3,
      "op",
      $frame.encode_operation_event(toList([leave])),
    );
  } else {
    return sluice$2;
  }
}

/**
 * Hold the inbound frames of a client. They stay in the queue until a
 * `resume` call. A test can thus deliver the operation of one peer before the
 * operation of another peer.
 */
export function pause(sluice, client_id) {
  return new Sluice(
    sluice.document_id,
    sluice.tenant_id,
    sluice.sequence_state,
    sluice.log,
    sluice.clients,
    sluice.presence,
    sluice.next_presence_ref,
    sluice.presence_supported,
    $set.insert(sluice.paused, client_id),
    sluice.next_client_number,
    sluice.now_milliseconds,
    sluice.outbox,
  );
}

/**
 * Return the held frames of a paused client to the deliverable queue.
 */
export function resume(sluice, client_id) {
  return new Sluice(
    sluice.document_id,
    sluice.tenant_id,
    sluice.sequence_state,
    sluice.log,
    sluice.clients,
    sluice.presence,
    sluice.next_presence_ref,
    sluice.presence_supported,
    $set.delete$(sluice.paused, client_id),
    sluice.next_client_number,
    sluice.now_milliseconds,
    sluice.outbox,
  );
}

/**
 * Create a `phx_ref` value and pair it with the metadata that it stamps.
 * 
 * @ignore
 */
function track(sluice, key, fields) {
  let phx_ref = "ref-" + $int.to_string(sluice.next_presence_ref);
  return [
    new Sluice(
      sluice.document_id,
      sluice.tenant_id,
      sluice.sequence_state,
      sluice.log,
      sluice.clients,
      sluice.presence,
      sluice.next_presence_ref + 1,
      sluice.presence_supported,
      sluice.paused,
      sluice.next_client_number,
      sluice.now_milliseconds,
      sluice.outbox,
    ),
    new $frame.PresenceMeta(key, phx_ref, fields),
  ];
}

/**
 * Read the metadata of a presence command, and refuse an attempt to claim a
 * field that the server owns. The function removes a reserved key *inside*
 * `meta`, and it does not refuse the command. See
 * `frame.decode_presence_meta`. A reserved key at the top level is a claim
 * of identity, and it deserves an explicit error.
 * 
 * @ignore
 */
function read_meta(payload) {
  let $ = $frame.names_reserved_field(payload);
  if ($) {
    return new Error(
      $frame.encode_presence_error(
        "invalid_meta",
        "the server owns key, session, and ref; a client cannot set them",
      ),
    );
  } else {
    let _pipe = $frame.decode_presence_meta(payload);
    return $result.map_error(
      _pipe,
      (_) => {
        return $frame.encode_presence_error(
          "invalid_meta",
          "presence metadata must be a JSON object",
        );
      },
    );
  }
}

/**
 * Replace the metadata of this connection.
 *
 * The core emits one diff, which carries a leave of the old `phx_ref` and a
 * join of the new one. Phoenix emits the same pair, and an untrack followed
 * by a track on the server produces it too. A Phoenix client thus already
 * understands the sequence.
 * 
 * @ignore
 */
function on_update_presence(sluice, client_id, payload) {
  let $ = $dict.get(sluice.presence, client_id);
  if ($ instanceof Ok) {
    let previous = $[0];
    let $1 = read_meta(payload);
    if ($1 instanceof Ok) {
      let fields = $1[0];
      let $2 = track(sluice, previous.key, fields);
      let sluice$1 = $2[0];
      let meta = $2[1];
      let _pipe = new Sluice(
        sluice$1.document_id,
        sluice$1.tenant_id,
        sluice$1.sequence_state,
        sluice$1.log,
        sluice$1.clients,
        $dict.insert(sluice$1.presence, client_id, meta),
        sluice$1.next_presence_ref,
        sluice$1.presence_supported,
        sluice$1.paused,
        sluice$1.next_client_number,
        sluice$1.now_milliseconds,
        sluice$1.outbox,
      );
      return broadcast_presence(
        _pipe,
        toList([[client_id, meta]]),
        toList([[client_id, previous]]),
      );
    } else {
      let frame = $1[0];
      return enqueue(sluice, client_id, "presence_error", frame);
    }
  } else {
    return enqueue(
      sluice,
      client_id,
      "presence_error",
      $frame.encode_presence_error(
        "not_joined",
        "this connection has no presence to update",
      ),
    );
  }
}

/**
 * The presence key of a connection, which is its authenticated user id.
 *
 * A connection that did not complete `connect_document` is not in `clients`,
 * and it has no authenticated identity to derive a key from. The function
 * thus refuses it. A presence must never come from a socket that no server
 * authenticated.
 * 
 * @ignore
 */
function authenticated_key(sluice, client_id) {
  let $ = $dict.get(sluice.clients, client_id);
  if ($ instanceof Ok) {
    let entry = $[0];
    return new Ok(entry.client.user.id);
  } else {
    return new Error(
      $frame.encode_presence_error(
        "unauthenticated",
        "presence requires a completed document connection",
      ),
    );
  }
}

/**
 * Register the presence of this connection.
 *
 * The order here is the state-plus-diff synchronization of Phoenix, and it
 * lets a joiner converge without a lock on the topic. Take a snapshot of the
 * roster, send that snapshot to the joiner alone, and *then* track the join
 * and broadcast it. The joiner thus learns about its own session from the
 * diff, and not from the snapshot. A remote change that races the snapshot is
 * a diff that the client queues.
 * 
 * @ignore
 */
function on_join_presence(sluice, client_id, payload) {
  let $ = authenticated_key(sluice, client_id);
  if ($ instanceof Ok) {
    let key = $[0];
    let $1 = read_meta(payload);
    if ($1 instanceof Ok) {
      let fields = $1[0];
      let snapshot = enqueue(
        sluice,
        client_id,
        "presence_state",
        $frame.encode_presence_state($dict.to_list(sluice.presence)),
      );
      let $2 = track(snapshot, key, fields);
      let snapshot$1 = $2[0];
      let meta = $2[1];
      let _pipe = new Sluice(
        snapshot$1.document_id,
        snapshot$1.tenant_id,
        snapshot$1.sequence_state,
        snapshot$1.log,
        snapshot$1.clients,
        $dict.insert(snapshot$1.presence, client_id, meta),
        snapshot$1.next_presence_ref,
        snapshot$1.presence_supported,
        snapshot$1.paused,
        snapshot$1.next_client_number,
        snapshot$1.now_milliseconds,
        snapshot$1.outbox,
      );
      return broadcast_presence(
        _pipe,
        toList([[client_id, meta]]),
        $List$Empty$const,
      );
    } else {
      let frame = $1[0];
      return enqueue(sluice, client_id, "presence_error", frame);
    }
  } else {
    let frame = $[0];
    return enqueue(sluice, client_id, "presence_error", frame);
  }
}

function on_signal(sluice, payload) {
  let $ = $frame.decode_submit_signal(payload);
  if ($ instanceof Ok) {
    let signal = $[0];
    let frame = $frame.encode_signal(signal.client_id, signal.content);
    let _pipe = connected_ids(sluice);
    let _pipe$1 = $list.filter(
      _pipe,
      (id) => { return id !== signal.client_id; },
    );
    return $list.fold(
      _pipe$1,
      sluice,
      (sluice, id) => { return enqueue(sluice, id, "signal", frame); },
    );
  } else {
    return sluice;
  }
}

function on_noop(sluice, payload) {
  let $ = $frame.decode_noop(payload);
  if ($ instanceof Ok) {
    let client_id = $[0][0];
    let reference_sequence_number = $[0][1];
    let $1 = $sequencing.update_client_rsn(
      sluice.sequence_state,
      client_id,
      reference_sequence_number,
    );
    if ($1 instanceof Ok) {
      let sequence_state = $1[0];
      return new Sluice(
        sluice.document_id,
        sluice.tenant_id,
        sequence_state,
        sluice.log,
        sluice.clients,
        sluice.presence,
        sluice.next_presence_ref,
        sluice.presence_supported,
        sluice.paused,
        sluice.next_client_number,
        sluice.now_milliseconds,
        sluice.outbox,
      );
    } else {
      return sluice;
    }
  } else {
    return sluice;
  }
}

/**
 * The operations whose sequence number is more than `after`, in ascending
 * order.
 * 
 * @ignore
 */
function log_since(log, after) {
  let _pipe = log;
  let _pipe$1 = $list.reverse(_pipe);
  return $list.filter(
    _pipe$1,
    (operation) => { return operation.sequence_number > after; },
  );
}

function on_request_operations(sluice, client_id, payload) {
  let $ = $frame.decode_request_operations(payload);
  if ($ instanceof Ok) {
    let from = $[0];
    let operations = log_since(sluice.log, from);
    if (operations instanceof $Empty) {
      return sluice;
    } else {
      return enqueue(
        sluice,
        client_id,
        "op",
        $frame.encode_operation_event(operations),
      );
    }
  } else {
    return sluice;
  }
}

/**
 * Give a sequence number to one operation and broadcast that operation to
 * every connected client. The broadcast includes the author, because that echo
 * is the ack that the kernel of the author waits for.
 * 
 * @ignore
 */
function sequence_operation(sluice, client_id, operation) {
  let $ = $sequencing.assign_sequence_number(
    sluice.sequence_state,
    client_id,
    operation.client_sequence_number,
    operation.reference_sequence_number,
  );
  if ($ instanceof $sequencing.SequenceOk) {
    let sequence_state = $.state;
    let sequence_number$1 = $.assigned_sn;
    let minimum_sequence_number = $.msn;
    let sequenced = new Sequenced(
      new Some(client_id),
      sequence_number$1,
      minimum_sequence_number,
      operation.client_sequence_number,
      operation.reference_sequence_number,
      operation.operation_type,
      operation.contents,
      operation.metadata,
      sluice.now_milliseconds,
      Option$None$const,
    );
    let event = $frame.encode_operation_event(toList([sequenced]));
    let _pipe = new Sluice(
      sluice.document_id,
      sluice.tenant_id,
      sequence_state,
      listPrepend(sequenced, sluice.log),
      sluice.clients,
      sluice.presence,
      sluice.next_presence_ref,
      sluice.presence_supported,
      sluice.paused,
      sluice.next_client_number,
      sluice.now_milliseconds,
      sluice.outbox,
    );
    return broadcast(_pipe, "op", event);
  } else {
    return sluice;
  }
}

function on_submit_operation(sluice, payload) {
  let $ = $frame.decode_submit_operation(payload);
  if ($ instanceof Ok) {
    let submit = $[0];
    let _pipe = $list.flatten(submit.batches);
    return $list.fold(
      _pipe,
      sluice,
      (sluice, operation) => {
        return sequence_operation(sluice, submit.client_id, operation);
      },
    );
  } else {
    return sluice;
  }
}

function on_connect_document(sluice, client_id, payload) {
  let $ = $frame.decode_connect_document(payload);
  if ($ instanceof Ok) {
    let request = $[0];
    let current = $sequencing.current_sn(sluice.sequence_state);
    let sequence_state = $sequencing.client_join(
      sluice.sequence_state,
      client_id,
      current,
    );
    let _block;
    let _pipe = new Sluice(
      sluice.document_id,
      sluice.tenant_id,
      sequence_state,
      sluice.log,
      sluice.clients,
      sluice.presence,
      sluice.next_presence_ref,
      sluice.presence_supported,
      sluice.paused,
      sluice.next_client_number,
      sluice.now_milliseconds,
      sluice.outbox,
    );
    _block = sequence_system(_pipe, "join", $frame.system_join_data(client_id));
    let $1 = _block;
    let sluice$1 = $1[0];
    let join = $1[1];
    let sluice$2 = broadcast(
      sluice$1,
      "op",
      $frame.encode_operation_event(toList([join])),
    );
    let clients = $dict.insert(
      sluice$2.clients,
      client_id,
      new ClientEntry(request.client, request.client.scopes),
    );
    let sluice$3 = new Sluice(
      sluice$2.document_id,
      sluice$2.tenant_id,
      sluice$2.sequence_state,
      sluice$2.log,
      clients,
      sluice$2.presence,
      sluice$2.next_presence_ref,
      sluice$2.presence_supported,
      sluice$2.paused,
      sluice$2.next_client_number,
      sluice$2.now_milliseconds,
      sluice$2.outbox,
    );
    let connected = $frame.encode_connected(
      client_id,
      sluice$3.tenant_id,
      sluice$3.document_id,
      request.client.scopes,
      $sequencing.current_sn(sluice$3.sequence_state),
      connected_ids(sluice$3),
      log_since(sluice$3.log, 0),
      sluice$3.now_milliseconds,
      sluice$3.presence_supported,
    );
    return enqueue(sluice$3, client_id, "connect_document_success", connected);
  } else {
    return sluice;
  }
}

/**
 * Process one push from a client to the server, keyed by the client id that
 * the connection received. The function sequences the operations, appends them
 * to the log, and queues the frames that result. It ignores a malformed frame
 * and a frame that the protocol does not permit, because a correct runtime
 * never sends one.
 */
export function handle(sluice, client_id, event, payload) {
  if (event === "connect_document") {
    return on_connect_document(sluice, client_id, payload);
  } else if (event === "submitOp") {
    return on_submit_operation(sluice, payload);
  } else if (event === "requestOps") {
    return on_request_operations(sluice, client_id, payload);
  } else if (event === "noop") {
    return on_noop(sluice, payload);
  } else if (event === "submitSignal") {
    return on_signal(sluice, payload);
  } else if (event === "joinPresence") {
    return on_join_presence(sluice, client_id, payload);
  } else if (event === "updatePresence") {
    return on_update_presence(sluice, client_id, payload);
  } else if (event === "leavePresence") {
    return on_leave_presence(sluice, client_id);
  } else {
    return sluice;
  }
}

/**
 * Take the first frame whose client is not paused, and keep the queue order of
 * the frames that remain. `skipped` collects the frames of the paused clients
 * that the function passed over, so that the caller can put them back before
 * `rest`.
 * 
 * @ignore
 */
function pop_deliverable(loop$remaining, loop$paused, loop$skipped) {
  while (true) {
    let remaining = loop$remaining;
    let paused = loop$paused;
    let skipped = loop$skipped;
    if (remaining instanceof $Empty) {
      return new Error(undefined);
    } else {
      let frame = remaining.head;
      let rest = remaining.tail;
      let $ = $set.contains(paused, frame.client_id);
      if ($) {
        loop$remaining = rest;
        loop$paused = paused;
        loop$skipped = listPrepend(frame, skipped);
      } else {
        return new Ok([frame, $list.append($list.reverse(skipped), rest)]);
      }
    }
  }
}

/**
 * Deliver the oldest frame that the core owes to a client that is not paused,
 * and remove that frame from the queue. The result is `Error(Nil)` when the
 * core can deliver no frame, which occurs when the queue is empty and when
 * every pending frame belongs to a paused client.
 */
export function take(sluice) {
  let $ = pop_deliverable(sluice.outbox, sluice.paused, $List$Empty$const);
  if ($ instanceof Ok) {
    let frame = $[0][0];
    let rest = $[0][1];
    return [
      new Sluice(
        sluice.document_id,
        sluice.tenant_id,
        sluice.sequence_state,
        sluice.log,
        sluice.clients,
        sluice.presence,
        sluice.next_presence_ref,
        sluice.presence_supported,
        sluice.paused,
        sluice.next_client_number,
        sluice.now_milliseconds,
        rest,
      ),
      new Ok(frame),
    ];
  } else {
    return [sluice, new Error(undefined)];
  }
}

/**
 * The next frame that `take` would deliver, without a removal. The result is
 * `Error(Nil)` when the core can deliver no frame. A caller can thus collect
 * a whole broadcast group, which is the set of frames that share the sequence
 * number of one operation, before it delivers that group.
 */
export function peek(sluice) {
  let $ = pop_deliverable(sluice.outbox, sluice.paused, $List$Empty$const);
  if ($ instanceof Ok) {
    let frame = $[0][0];
    return new Ok(frame);
  } else {
    return $;
  }
}

/**
 * Whether the core can deliver a frame now, which is true when it owes a
 * frame to a client that is not paused.
 */
export function has_pending(sluice) {
  return $list.any(
    sluice.outbox,
    (frame) => { return !$set.contains(sluice.paused, frame.client_id); },
  );
}

/**
 * Every frame in the queue now, oldest first, for a paused client and for a
 * client that is not paused. Use this function for assertions and for
 * diagnostics.
 */
export function outbox(sluice) {
  return sluice.outbox;
}

/**
 * The current server sequence number.
 */
export function sequence_number(sluice) {
  return $sequencing.current_sn(sluice.sequence_state);
}

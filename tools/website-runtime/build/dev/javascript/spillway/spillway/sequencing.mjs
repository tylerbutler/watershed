/// <reference types="./sequencing.d.mts" />
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";

export class ClientSequenceState extends $CustomType {
  constructor(last_csn, last_rsn) {
    super();
    this.last_csn = last_csn;
    this.last_rsn = last_rsn;
  }
}
export const ClientSequenceState$ClientSequenceState = (last_csn, last_rsn) =>
  new ClientSequenceState(last_csn, last_rsn);
export const ClientSequenceState$isClientSequenceState = (value) =>
  value instanceof ClientSequenceState;
export const ClientSequenceState$ClientSequenceState$last_csn = (value) =>
  value.last_csn;
export const ClientSequenceState$ClientSequenceState$0 = (value) =>
  value.last_csn;
export const ClientSequenceState$ClientSequenceState$last_rsn = (value) =>
  value.last_rsn;
export const ClientSequenceState$ClientSequenceState$1 = (value) =>
  value.last_rsn;

export class SequenceState extends $CustomType {
  constructor(sequence_number, minimum_sequence_number, client_states) {
    super();
    this.sequence_number = sequence_number;
    this.minimum_sequence_number = minimum_sequence_number;
    this.client_states = client_states;
  }
}
export const SequenceState$SequenceState = (sequence_number, minimum_sequence_number, client_states) =>
  new SequenceState(sequence_number, minimum_sequence_number, client_states);
export const SequenceState$isSequenceState = (value) =>
  value instanceof SequenceState;
export const SequenceState$SequenceState$sequence_number = (value) =>
  value.sequence_number;
export const SequenceState$SequenceState$0 = (value) => value.sequence_number;
export const SequenceState$SequenceState$minimum_sequence_number = (value) =>
  value.minimum_sequence_number;
export const SequenceState$SequenceState$1 = (value) =>
  value.minimum_sequence_number;
export const SequenceState$SequenceState$client_states = (value) =>
  value.client_states;
export const SequenceState$SequenceState$2 = (value) => value.client_states;

export class SequenceOk extends $CustomType {
  constructor(state, assigned_sn, msn) {
    super();
    this.state = state;
    this.assigned_sn = assigned_sn;
    this.msn = msn;
  }
}
export const SequenceResult$SequenceOk = (state, assigned_sn, msn) =>
  new SequenceOk(state, assigned_sn, msn);
export const SequenceResult$isSequenceOk = (value) =>
  value instanceof SequenceOk;
export const SequenceResult$SequenceOk$state = (value) => value.state;
export const SequenceResult$SequenceOk$0 = (value) => value.state;
export const SequenceResult$SequenceOk$assigned_sn = (value) =>
  value.assigned_sn;
export const SequenceResult$SequenceOk$1 = (value) => value.assigned_sn;
export const SequenceResult$SequenceOk$msn = (value) => value.msn;
export const SequenceResult$SequenceOk$2 = (value) => value.msn;

export class SequenceError extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const SequenceResult$SequenceError = (reason) =>
  new SequenceError(reason);
export const SequenceResult$isSequenceError = (value) =>
  value instanceof SequenceError;
export const SequenceResult$SequenceError$reason = (value) => value.reason;
export const SequenceResult$SequenceError$0 = (value) => value.reason;

/**
 * CSN is not greater than last received
 */
export class InvalidCsn extends $CustomType {
  constructor(expected_greater_than, received) {
    super();
    this.expected_greater_than = expected_greater_than;
    this.received = received;
  }
}
export const SequenceError$InvalidCsn = (expected_greater_than, received) =>
  new InvalidCsn(expected_greater_than, received);
export const SequenceError$isInvalidCsn = (value) =>
  value instanceof InvalidCsn;
export const SequenceError$InvalidCsn$expected_greater_than = (value) =>
  value.expected_greater_than;
export const SequenceError$InvalidCsn$0 = (value) =>
  value.expected_greater_than;
export const SequenceError$InvalidCsn$received = (value) => value.received;
export const SequenceError$InvalidCsn$1 = (value) => value.received;

/**
 * RSN is greater than current SN (impossible)
 */
export class InvalidRsn extends $CustomType {
  constructor(current_sn, received_rsn) {
    super();
    this.current_sn = current_sn;
    this.received_rsn = received_rsn;
  }
}
export const SequenceError$InvalidRsn = (current_sn, received_rsn) =>
  new InvalidRsn(current_sn, received_rsn);
export const SequenceError$isInvalidRsn = (value) =>
  value instanceof InvalidRsn;
export const SequenceError$InvalidRsn$current_sn = (value) => value.current_sn;
export const SequenceError$InvalidRsn$0 = (value) => value.current_sn;
export const SequenceError$InvalidRsn$received_rsn = (value) =>
  value.received_rsn;
export const SequenceError$InvalidRsn$1 = (value) => value.received_rsn;

/**
 * Unknown client (not joined)
 */
export class UnknownClient extends $CustomType {
  constructor(client_id) {
    super();
    this.client_id = client_id;
  }
}
export const SequenceError$UnknownClient = (client_id) =>
  new UnknownClient(client_id);
export const SequenceError$isUnknownClient = (value) =>
  value instanceof UnknownClient;
export const SequenceError$UnknownClient$client_id = (value) => value.client_id;
export const SequenceError$UnknownClient$0 = (value) => value.client_id;

/**
 * Create initial sequence state for a new document
 */
export function new$() {
  return new SequenceState(0, 0, $dict.new$());
}

/**
 * Create sequence state from existing document state
 */
export function from_checkpoint(sn, msn) {
  return new SequenceState(sn, msn, $dict.new$());
}

/**
 * Calculate MSN from current client states
 *
 * MSN = min(last_rsn of all connected clients)
 * MSN can only increase, never decrease
 * 
 * @ignore
 */
function calculate_msn(client_states, current_msn) {
  let _block;
  let _pipe = client_states;
  let _pipe$1 = $dict.values(_pipe);
  _block = $list.map(_pipe$1, (cs) => { return cs.last_rsn; });
  let rsns = _block;
  let $ = $list.reduce(rsns, $int.min);
  if ($ instanceof Ok) {
    let min_rsn = $[0];
    return $int.max(min_rsn, current_msn);
  } else {
    return current_msn;
  }
}

/**
 * Register a new client joining the session
 *
 * The client's initial RSN is set from the current SN
 */
export function client_join(state, client_id, join_rsn) {
  let client_state = new ClientSequenceState(0, join_rsn);
  let new_clients = $dict.insert(state.client_states, client_id, client_state);
  let new_msn = calculate_msn(new_clients, state.minimum_sequence_number);
  return new SequenceState(state.sequence_number, new_msn, new_clients);
}

/**
 * Remove a client from the session
 *
 * The client is removed from MSN calculation
 */
export function client_leave(state, client_id) {
  let new_clients = $dict.delete$(state.client_states, client_id);
  let new_msn = calculate_msn(new_clients, state.minimum_sequence_number);
  return new SequenceState(state.sequence_number, new_msn, new_clients);
}

/**
 * Assign a sequence number to an incoming operation
 *
 * Validates:
 * - Client is known (has joined)
 * - CSN is monotonically increasing for this client
 * - RSN is not greater than current SN
 */
export function assign_sequence_number(state, client_id, csn, rsn) {
  let $ = $dict.get(state.client_states, client_id);
  if ($ instanceof Ok) {
    let client_state = $[0];
    let $1 = csn > client_state.last_csn;
    if ($1) {
      let $2 = rsn > state.sequence_number;
      if ($2) {
        return new SequenceError(new InvalidRsn(state.sequence_number, rsn));
      } else {
        let new_sn = state.sequence_number + 1;
        let new_client_state = new ClientSequenceState(csn, rsn);
        let new_clients = $dict.insert(
          state.client_states,
          client_id,
          new_client_state,
        );
        let new_msn = calculate_msn(new_clients, state.minimum_sequence_number);
        let new_state = new SequenceState(new_sn, new_msn, new_clients);
        return new SequenceOk(new_state, new_sn, new_msn);
      }
    } else {
      return new SequenceError(new InvalidCsn(client_state.last_csn, csn));
    }
  } else {
    return new SequenceError(new UnknownClient(client_id));
  }
}

/**
 * Update a client's RSN without submitting an op (e.g., from NoOp)
 */
export function update_client_rsn(state, client_id, new_rsn) {
  let $ = $dict.get(state.client_states, client_id);
  if ($ instanceof Ok) {
    let client_state = $[0];
    let updated_rsn = $int.max(client_state.last_rsn, new_rsn);
    let new_client_state = new ClientSequenceState(
      client_state.last_csn,
      updated_rsn,
    );
    let new_clients = $dict.insert(
      state.client_states,
      client_id,
      new_client_state,
    );
    let new_msn = calculate_msn(new_clients, state.minimum_sequence_number);
    return new Ok(
      new SequenceState(state.sequence_number, new_msn, new_clients),
    );
  } else {
    return new Error(new UnknownClient(client_id));
  }
}

/**
 * Reserve a sequence number for a server-generated system message
 *
 * Some system messages (e.g. a `summaryAck`) are minted by the server itself
 * rather than assigned from an inbound client op. They still consume a real
 * sequence number, so the sequencer must advance to avoid handing the same SN
 * to the next client op. This bumps `sequence_number` by 1 and returns the new
 * state together with the reserved SN.
 */
export function reserve_sequence_number(state) {
  let reserved_sn = state.sequence_number + 1;
  let new_msn = calculate_msn(
    state.client_states,
    state.minimum_sequence_number,
  );
  let new_state = new SequenceState(reserved_sn, new_msn, state.client_states);
  return [new_state, reserved_sn];
}

/**
 * Get the current sequence number
 */
export function current_sn(state) {
  return state.sequence_number;
}

/**
 * Get the current minimum sequence number
 */
export function current_msn(state) {
  return state.minimum_sequence_number;
}

/**
 * Get the number of connected clients
 */
export function client_count(state) {
  return $dict.size(state.client_states);
}

/**
 * Check if a client is connected
 */
export function is_client_connected(state, client_id) {
  return $dict.has_key(state.client_states, client_id);
}

/**
 * Get all connected client IDs
 */
export function connected_clients(state) {
  return $dict.keys(state.client_states);
}

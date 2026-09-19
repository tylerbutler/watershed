/// <reference types="./spillway.d.mts" />
import * as $dict from "../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../gleam_stdlib/gleam/dynamic.mjs";
import * as $option from "../gleam_stdlib/gleam/option.mjs";
import * as $jwt from "../signet/signet/jwt.mjs";
import { Ok, Error } from "./gleam.mjs";
import * as $message from "./spillway/message.mjs";
import * as $nack from "./spillway/nack.mjs";
import * as $sequencing from "./spillway/sequencing.mjs";
import * as $session_logic from "./spillway/session_logic.mjs";
import * as $summary from "./spillway/summary.mjs";
import * as $types from "./spillway/types.mjs";
import * as $validation from "./spillway/validation.mjs";

/**
 * Standard permission scopes (wire strings, for the Elixir interop layer)
 */
export const jwt_scope_doc_read = "doc:read";

export const jwt_scope_doc_write = "doc:write";

export const jwt_scope_summary_write = "summary:write";

/**
 * Create a new sequence state for a document
 */
export function new_sequence_state() {
  return $sequencing.new$();
}

/**
 * Create sequence state from checkpoint
 */
export function sequence_state_from_checkpoint(sn, msn) {
  return $sequencing.from_checkpoint(sn, msn);
}

/**
 * Register a client joining the session
 */
export function client_join(state, client_id, join_rsn) {
  return $sequencing.client_join(state, client_id, join_rsn);
}

/**
 * Remove a client from the session
 */
export function client_leave(state, client_id) {
  return $sequencing.client_leave(state, client_id);
}

/**
 * Assign a sequence number to an operation
 */
export function assign_sequence_number(state, client_id, csn, rsn) {
  return $sequencing.assign_sequence_number(state, client_id, csn, rsn);
}

/**
 * Get current sequence number
 */
export function current_sn(state) {
  return $sequencing.current_sn(state);
}

/**
 * Reserve a sequence number for a server-minted system message (e.g. summaryAck)
 *
 * Returns the advanced sequence state together with the reserved SN so the next
 * client op is assigned a fresh, non-colliding sequence number.
 */
export function reserve_sequence_number(state) {
  return $sequencing.reserve_sequence_number(state);
}

/**
 * Get current minimum sequence number
 */
export function current_msn(state) {
  return $sequencing.current_msn(state);
}

/**
 * Get count of connected clients
 */
export function client_count(state) {
  return $sequencing.client_count(state);
}

/**
 * Check if client is connected
 */
export function is_client_connected(state, client_id) {
  return $sequencing.is_client_connected(state, client_id);
}

/**
 * Get list of connected client IDs
 */
export function connected_clients(state) {
  return $sequencing.connected_clients(state);
}

/**
 * Create a bad request nack
 */
export function nack_bad_request(message, op) {
  return $nack.bad_request(message, op);
}

/**
 * Create an invalid scope nack
 */
export function nack_invalid_scope(required_scope, op) {
  return $nack.invalid_scope(required_scope, op);
}

/**
 * Create a throttled nack
 */
export function nack_throttled(retry_after, op) {
  return $nack.throttled(retry_after, op);
}

/**
 * Create a read-only client nack
 */
export function nack_read_only_client(op) {
  return $nack.read_only_client(op);
}

/**
 * Create an unknown client nack
 */
export function nack_unknown_client(client_id) {
  return $nack.unknown_client(client_id);
}

/**
 * Create an invalid CSN nack
 */
export function nack_invalid_csn(expected, received, op) {
  return $nack.invalid_csn(expected, received, op);
}

/**
 * Create an invalid RSN nack
 */
export function nack_invalid_rsn(current_sn, received_rsn, op) {
  return $nack.invalid_rsn(current_sn, received_rsn, op);
}

/**
 * Validate message size
 */
export function validate_message_size(message_bytes, max_size) {
  return $validation.validate_message_size(message_bytes, max_size);
}

/**
 * Validate write mode
 */
export function validate_write_mode(mode) {
  return $validation.validate_write_mode(mode);
}

/**
 * Validate token has required scope
 */
export function validate_scope(claims, required_scope) {
  return $validation.validate_scope(claims, required_scope);
}

/**
 * Validate token expiration
 */
export function validate_token_expiration(claims, current_time_seconds) {
  return $validation.validate_token_expiration(claims, current_time_seconds);
}

/**
 * Format validation error as string
 */
export function format_validation_error(error) {
  return $validation.format_error(error);
}

/**
 * Convert message type to string
 */
export function message_type_to_string(mt) {
  return $message.message_type_to_string(mt);
}

/**
 * Parse message type from string
 */
export function message_type_from_string(s) {
  return $message.message_type_from_string(s);
}

export function write_mode() {
  return $types.ConnectionMode$WriteMode$const;
}

export function read_mode() {
  return $types.ConnectionMode$ReadMode$const;
}

export function nack_error_throttling() {
  return $nack.NackErrorType$ThrottlingError$const;
}

export function nack_error_invalid_scope() {
  return $nack.NackErrorType$InvalidScopeError$const;
}

export function nack_error_bad_request() {
  return $nack.NackErrorType$BadRequestError$const;
}

export function nack_error_limit_exceeded() {
  return $nack.NackErrorType$LimitExceededError$const;
}

/**
 * Validate that the token has not expired
 */
export function jwt_validate_expiration(claims, current_time_seconds) {
  return $jwt.validate_expiration(claims, current_time_seconds);
}

/**
 * Validate that the token tenant matches the request tenant
 */
export function jwt_validate_tenant(claims, request_tenant_id) {
  return $jwt.validate_tenant(claims, request_tenant_id);
}

/**
 * Validate that the token document matches the request document
 */
export function jwt_validate_document(claims, request_document_id) {
  return $jwt.validate_document(claims, request_document_id);
}

/**
 * Validate that the token has the required scope. Accepts the wire string for
 * the Elixir interop layer, converting to a typed `Scope`.
 */
export function jwt_validate_scope(claims, required_scope) {
  let $ = $types.scope_from_string(required_scope);
  if ($ instanceof Ok) {
    let scope = $[0];
    return $jwt.validate_scope(claims, scope);
  } else {
    return new Error(
      new $jwt.InvalidClaim("scope", "unknown scope: " + required_scope),
    );
  }
}

/**
 * Check if token has a specific scope (returns Bool). Accepts the wire string.
 */
export function jwt_has_scope(claims, scope) {
  let $ = $types.scope_from_string(scope);
  if ($ instanceof Ok) {
    let parsed = $[0];
    return $jwt.has_scope(claims, parsed);
  } else {
    return false;
  }
}

/**
 * Check if token has read permission
 */
export function jwt_has_read_scope(claims) {
  return $jwt.has_read_scope(claims);
}

/**
 * Check if token has write permission
 */
export function jwt_has_write_scope(claims) {
  return $jwt.has_write_scope(claims);
}

/**
 * Check if token has summary write permission
 */
export function jwt_has_summary_write_scope(claims) {
  return $jwt.has_summary_write_scope(claims);
}

/**
 * Validate all claims for a document connection
 */
export function jwt_validate_connection_claims(
  claims,
  tenant_id,
  document_id,
  current_time_seconds
) {
  return $jwt.validate_connection_claims(
    claims,
    tenant_id,
    document_id,
    current_time_seconds,
  );
}

/**
 * Validate claims for read access
 */
export function jwt_validate_read_access(
  claims,
  tenant_id,
  document_id,
  current_time_seconds
) {
  return $jwt.validate_read_access(
    claims,
    tenant_id,
    document_id,
    current_time_seconds,
  );
}

/**
 * Validate claims for write access
 */
export function jwt_validate_write_access(
  claims,
  tenant_id,
  document_id,
  current_time_seconds
) {
  return $jwt.validate_write_access(
    claims,
    tenant_id,
    document_id,
    current_time_seconds,
  );
}

/**
 * Validate claims for summary write access
 */
export function jwt_validate_summary_access(
  claims,
  tenant_id,
  document_id,
  current_time_seconds
) {
  return $jwt.validate_summary_access(
    claims,
    tenant_id,
    document_id,
    current_time_seconds,
  );
}

/**
 * Format JWT validation error as human-readable message
 */
export function jwt_format_error(error) {
  return $jwt.format_error(error);
}

/**
 * Get HTTP status code for JWT validation error
 */
export function jwt_error_to_http_code(error) {
  return $jwt.error_to_http_code(error);
}

/**
 * Create an empty summary tree
 */
export function empty_summary_tree() {
  return $summary.empty_summary_tree();
}

/**
 * Create a summary tree with entries
 */
export function new_summary_tree(entries) {
  return $summary.new_summary_tree(entries);
}

/**
 * Add an entry to a summary tree
 */
export function add_to_summary_tree(tree, path, object) {
  return $summary.add_to_summary_tree(tree, path, object);
}

/**
 * Get an entry from a summary tree
 */
export function get_from_summary_tree(tree, path) {
  return $summary.get_from_summary_tree(tree, path);
}

/**
 * Create a SummaryAck
 */
export function create_summary_ack(handle, sequence_number) {
  return $summary.create_summary_ack(handle, sequence_number);
}

/**
 * Create a SummaryNack with error message
 */
export function create_summary_nack(sequence_number, code, message) {
  return $summary.create_summary_nack(sequence_number, code, message);
}

/**
 * Create a SummaryContext for document open response
 */
export function create_summary_context(handle, sequence_number) {
  return $summary.create_summary_context(handle, sequence_number);
}

/**
 * Convert SummaryType to string
 */
export function summary_type_to_string(st) {
  return $summary.summary_type_to_string(st);
}

/**
 * Parse SummaryType from string
 */
export function summary_type_from_string(s) {
  return $summary.summary_type_from_string(s);
}

/**
 * Convert SummaryType to numeric code
 */
export function summary_type_to_code(st) {
  return $summary.summary_type_to_code(st);
}

/**
 * Parse SummaryType from numeric code
 */
export function summary_type_from_code(code) {
  return $summary.summary_type_from_code(code);
}

/**
 * Summary type constructors
 */
export function summary_type_tree() {
  return $summary.SummaryType$Tree$const;
}

export function summary_type_blob() {
  return $summary.SummaryType$Blob$const;
}

export function summary_type_attachment() {
  return $summary.SummaryType$Attachment$const;
}

/**
 * Summary object constructors
 */
export function summary_blob(content) {
  return new $summary.SummaryBlob(content);
}

export function summary_handle(handle, handle_type) {
  return new $summary.SummaryHandle(handle, handle_type);
}

export function summary_attachment(id) {
  return new $summary.SummaryAttachment(id);
}

/**
 * Negotiate features between server and client
 */
export function negotiate_features(server_features, client_features) {
  return $session_logic.negotiate_features(server_features, client_features);
}

/**
 * Negotiate protocol version
 */
export function negotiate_version(supported_versions, client_versions) {
  return $session_logic.negotiate_version(supported_versions, client_versions);
}

/**
 * Validate summarize contents
 */
export function validate_summarize_contents(contents) {
  return $session_logic.validate_summarize_contents(contents);
}

/**
 * Determine signal recipients based on targeting rules
 */
export function determine_signal_recipients(
  sender_client_id,
  targeted_clients,
  ignored_clients,
  single_target,
  all_client_ids
) {
  return $session_logic.determine_signal_recipients(
    sender_client_id,
    targeted_clients,
    ignored_clients,
    single_target,
    all_client_ids,
  );
}

/**
 * Add op to history with max size trimming
 */
export function add_to_history(op, history, max_size) {
  return $session_logic.add_to_history(op, history, max_size);
}

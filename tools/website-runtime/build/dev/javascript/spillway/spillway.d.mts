import type * as $dict from "../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../gleam_stdlib/gleam/option.d.mts";
import type * as $jwt from "../signet/signet/jwt.d.mts";
import type * as $types from "../signet/signet/types.d.mts";
import type * as _ from "./gleam.d.mts";
import type * as $message from "./spillway/message.d.mts";
import type * as $nack from "./spillway/nack.d.mts";
import type * as $sequencing from "./spillway/sequencing.d.mts";
import type * as $session_logic from "./spillway/session_logic.d.mts";
import type * as $summary from "./spillway/summary.d.mts";
import type * as $types from "./spillway/types.d.mts";
import type * as $validation from "./spillway/validation.d.mts";

export type ConnectionMode = $types.ConnectionMode$;

export type User = $types.User$;

export type Client = $types.Client$;

export type TokenClaims = $types.TokenClaims$;

export type DocumentMessage = $types.DocumentMessage$;

export type SequencedDocumentMessage = $types.SequencedDocumentMessage$;

export type ServiceConfiguration = $types.ServiceConfiguration$;

export type SequenceState = $sequencing.SequenceState$;

export type SequenceResult = $sequencing.SequenceResult$;

export type SequenceError = $sequencing.SequenceError$;

export type Nack = $nack.Nack$;

export type NackErrorType = $nack.NackErrorType$;

export type NackContent = $nack.NackContent$;

export type ConnectMessage = $message.ConnectMessage$;

export type ConnectedMessage = $message.ConnectedMessage$;

export type ConnectError = $message.ConnectError$;

export type SignalMessage = $message.SignalMessage$;

export type MessageType = $message.MessageType$;

export type ValidationError = $validation.ValidationError$;

export type SummaryTree = $summary.SummaryTree$;

export type SummaryObject = $summary.SummaryObject$;

export type SummaryType = $summary.SummaryType$;

export type SummaryOp = $summary.SummaryOp$;

export type SummaryAck = $summary.SummaryAck$;

export type SummaryNack = $summary.SummaryNack$;

export type SummaryContext = $summary.SummaryContext$;

export type JwtValidationError = $jwt.JwtValidationError$;

export type SequencedOpParams = $session_logic.SequencedOpParams$;

export const jwt_scope_doc_read: string;

export const jwt_scope_doc_write: string;

export const jwt_scope_summary_write: string;

export function new_sequence_state(): $sequencing.SequenceState$;

export function sequence_state_from_checkpoint(sn: number, msn: number): $sequencing.SequenceState$;

export function client_join(
  state: $sequencing.SequenceState$,
  client_id: string,
  join_rsn: number
): $sequencing.SequenceState$;

export function client_leave(
  state: $sequencing.SequenceState$,
  client_id: string
): $sequencing.SequenceState$;

export function assign_sequence_number(
  state: $sequencing.SequenceState$,
  client_id: string,
  csn: number,
  rsn: number
): $sequencing.SequenceResult$;

export function current_sn(state: $sequencing.SequenceState$): number;

export function reserve_sequence_number(state: $sequencing.SequenceState$): [
  $sequencing.SequenceState$,
  number
];

export function current_msn(state: $sequencing.SequenceState$): number;

export function client_count(state: $sequencing.SequenceState$): number;

export function is_client_connected(
  state: $sequencing.SequenceState$,
  client_id: string
): boolean;

export function connected_clients(state: $sequencing.SequenceState$): _.List<
  string
>;

export function nack_bad_request(
  message: string,
  op: $option.Option$<$types.DocumentMessage$>
): $nack.Nack$;

export function nack_invalid_scope(
  required_scope: string,
  op: $option.Option$<$types.DocumentMessage$>
): $nack.Nack$;

export function nack_throttled(
  retry_after: number,
  op: $option.Option$<$types.DocumentMessage$>
): $nack.Nack$;

export function nack_read_only_client(
  op: $option.Option$<$types.DocumentMessage$>
): $nack.Nack$;

export function nack_unknown_client(client_id: string): $nack.Nack$;

export function nack_invalid_csn(
  expected: number,
  received: number,
  op: $option.Option$<$types.DocumentMessage$>
): $nack.Nack$;

export function nack_invalid_rsn(
  current_sn: number,
  received_rsn: number,
  op: $option.Option$<$types.DocumentMessage$>
): $nack.Nack$;

export function validate_message_size(message_bytes: number, max_size: number): _.Result<
  undefined,
  $validation.ValidationError$
>;

export function validate_write_mode(mode: $types.ConnectionMode$): _.Result<
  undefined,
  $validation.ValidationError$
>;

export function validate_scope(
  claims: $types.TokenClaims$,
  required_scope: string
): _.Result<undefined, $validation.ValidationError$>;

export function validate_token_expiration(
  claims: $types.TokenClaims$,
  current_time_seconds: number
): _.Result<undefined, $validation.ValidationError$>;

export function format_validation_error(error: $validation.ValidationError$): string;

export function message_type_to_string(mt: $message.MessageType$): string;

export function message_type_from_string(s: string): _.Result<
  $message.MessageType$,
  undefined
>;

export function write_mode(): $types.ConnectionMode$;

export function read_mode(): $types.ConnectionMode$;

export function nack_error_throttling(): $nack.NackErrorType$;

export function nack_error_invalid_scope(): $nack.NackErrorType$;

export function nack_error_bad_request(): $nack.NackErrorType$;

export function nack_error_limit_exceeded(): $nack.NackErrorType$;

export function jwt_validate_expiration(
  claims: $types.TokenClaims$,
  current_time_seconds: number
): _.Result<undefined, $jwt.JwtValidationError$>;

export function jwt_validate_tenant(
  claims: $types.TokenClaims$,
  request_tenant_id: string
): _.Result<undefined, $jwt.JwtValidationError$>;

export function jwt_validate_document(
  claims: $types.TokenClaims$,
  request_document_id: string
): _.Result<undefined, $jwt.JwtValidationError$>;

export function jwt_validate_scope(
  claims: $types.TokenClaims$,
  required_scope: string
): _.Result<undefined, $jwt.JwtValidationError$>;

export function jwt_has_scope(claims: $types.TokenClaims$, scope: string): boolean;

export function jwt_has_read_scope(claims: $types.TokenClaims$): boolean;

export function jwt_has_write_scope(claims: $types.TokenClaims$): boolean;

export function jwt_has_summary_write_scope(claims: $types.TokenClaims$): boolean;

export function jwt_validate_connection_claims(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string,
  current_time_seconds: number
): _.Result<undefined, $jwt.JwtValidationError$>;

export function jwt_validate_read_access(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string,
  current_time_seconds: number
): _.Result<undefined, $jwt.JwtValidationError$>;

export function jwt_validate_write_access(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string,
  current_time_seconds: number
): _.Result<undefined, $jwt.JwtValidationError$>;

export function jwt_validate_summary_access(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string,
  current_time_seconds: number
): _.Result<undefined, $jwt.JwtValidationError$>;

export function jwt_format_error(error: $jwt.JwtValidationError$): string;

export function jwt_error_to_http_code(error: $jwt.JwtValidationError$): number;

export function empty_summary_tree(): $summary.SummaryTree$;

export function new_summary_tree(
  entries: _.List<[string, $summary.SummaryObject$]>
): $summary.SummaryTree$;

export function add_to_summary_tree(
  tree: $summary.SummaryTree$,
  path: string,
  object: $summary.SummaryObject$
): $summary.SummaryTree$;

export function get_from_summary_tree(tree: $summary.SummaryTree$, path: string): _.Result<
  $summary.SummaryObject$,
  undefined
>;

export function create_summary_ack(handle: string, sequence_number: number): $summary.SummaryAck$;

export function create_summary_nack(
  sequence_number: number,
  code: $option.Option$<number>,
  message: $option.Option$<string>
): $summary.SummaryNack$;

export function create_summary_context(handle: string, sequence_number: number): $summary.SummaryContext$;

export function summary_type_to_string(st: $summary.SummaryType$): string;

export function summary_type_from_string(s: string): _.Result<
  $summary.SummaryType$,
  undefined
>;

export function summary_type_to_code(st: $summary.SummaryType$): number;

export function summary_type_from_code(code: number): _.Result<
  $summary.SummaryType$,
  undefined
>;

export function summary_type_tree(): $summary.SummaryType$;

export function summary_type_blob(): $summary.SummaryType$;

export function summary_type_attachment(): $summary.SummaryType$;

export function summary_blob(content: string): $summary.SummaryObject$;

export function summary_handle(
  handle: string,
  handle_type: $summary.SummaryType$
): $summary.SummaryObject$;

export function summary_attachment(id: string): $summary.SummaryObject$;

export function negotiate_features(
  server_features: $dict.Dict$<string, boolean>,
  client_features: $dict.Dict$<string, boolean>
): $dict.Dict$<string, boolean>;

export function negotiate_version(
  supported_versions: _.List<string>,
  client_versions: _.List<string>
): string;

export function validate_summarize_contents(
  contents: $dict.Dict$<string, $dynamic.Dynamic$>
): _.Result<undefined, string>;

export function determine_signal_recipients(
  sender_client_id: string,
  targeted_clients: $option.Option$<_.List<string>>,
  ignored_clients: $option.Option$<_.List<string>>,
  single_target: $option.Option$<string>,
  all_client_ids: _.List<string>
): _.List<string>;

export function add_to_history<ADQM>(
  op: ADQM,
  history: _.List<ADQM>,
  max_size: number
): _.List<ADQM>;

export function build_sequenced_op(params: $session_logic.SequencedOpParams$): _.List<
  [string, $dynamic.Dynamic$]
>;

export function build_summary_ack(
  handle: string,
  sn: number,
  msn: number,
  timestamp: number
): _.List<[string, $dynamic.Dynamic$]>;

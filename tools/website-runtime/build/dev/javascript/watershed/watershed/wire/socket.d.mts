import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as $types from "../../../signet/signet/types.d.mts";
import type * as $message from "../../../spillway/spillway/message.d.mts";
import type * as $nack from "../../../spillway/spillway/nack.d.mts";
import type * as $types from "../../../spillway/spillway/types.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $wire from "../../watershed/wire.d.mts";

export const feature_presence_v1: string;

export function encode_client(client: $types.Client$): $json.Json$;

export function encode_connect_document(
  message: $message.ConnectMessage$,
  last_seen_sequence_number: $option.Option$<number>
): $json.Json$;

export function encode_submit_operation(
  client_id: string,
  batches: _.List<_.List<$wire.OutboundOperation$>>
): $json.Json$;

export function encode_request_operations(from: number): $json.Json$;

export function encode_submit_ripple(
  client_id: string,
  ripple_type: string,
  content: $json.Json$
): $json.Json$;

export function encode_noop(
  client_id: string,
  reference_sequence_number: number
): $json.Json$;

export function summary_context_decoder(): $decode.Decoder$<
  $message.SummaryContext$
>;

export function ripple_message_decoder(): $decode.Decoder$<
  $message.SignalMessage$
>;

export function sequenced_document_message_decoder(): $decode.Decoder$<
  $types.SequencedDocumentMessage$
>;

export function client_decoder(): $decode.Decoder$<$types.Client$>;

export function token_claims_decoder(): $decode.Decoder$<$token.TokenClaims$>;

export function connected_message_decoder(): $decode.Decoder$<
  $message.ConnectedMessage$
>;

export function supports_feature(
  features: $dict.Dict$<string, $dynamic.Dynamic$>,
  feature: string
): boolean;

export function connect_error_decoder(): $decode.Decoder$<
  $message.ConnectError$
>;

export function operation_message_decoder(): $decode.Decoder$<
  $message.OpMessage$
>;

export function document_message_decoder(): $decode.Decoder$<
  $types.DocumentMessage$
>;

export function nacks_decoder(): $decode.Decoder$<_.List<$nack.Nack$>>;

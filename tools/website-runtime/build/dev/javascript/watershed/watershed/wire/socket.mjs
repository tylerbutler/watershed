/// <reference types="./socket.d.mts" />
import * as $json from "../../../gleam_json/gleam/json.mjs";
import * as $dict from "../../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $list from "../../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../../gleam_stdlib/gleam/option.mjs";
import * as $token from "../../../signet/signet/types.mjs";
import * as $message from "../../../spillway/spillway/message.mjs";
import {
  ConnectError,
  ConnectedMessage,
  OpMessage,
  SignalMessage,
  SummaryContext,
} from "../../../spillway/spillway/message.mjs";
import * as $nack from "../../../spillway/spillway/nack.mjs";
import { Nack, NackContent } from "../../../spillway/spillway/nack.mjs";
import * as $types from "../../../spillway/spillway/types.mjs";
import {
  Client,
  ClientCapabilities,
  ClientDetails,
  DocumentMessage,
  SequencedDocumentMessage,
  ServiceConfiguration,
  SignalClient,
  WriteMode,
  ConnectionMode$ReadMode$const,
  ConnectionMode$WriteMode$const,
} from "../../../spillway/spillway/types.mjs";
import {
  Ok,
  toList,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  isEqual,
} from "../../gleam.mjs";
import * as $wire from "../../watershed/wire.mjs";

/**
 * The `supportedFeatures` key that a server sets to announce the presence
 * lane.
 */
export const feature_presence_v1 = "presence_v1";

function optional_field(key, value, encode) {
  if (value instanceof Some) {
    let inner = value[0];
    return toList([[key, encode(inner)]]);
  } else {
    return $List$Empty$const;
  }
}

function encode_dynamic_dict(values) {
  return $json.object(
    $list.map(
      $dict.to_list(values),
      (pair) => { return [pair[0], $wire.dynamic_to_json(pair[1])]; },
    ),
  );
}

function mode_to_string(mode) {
  if (mode instanceof WriteMode) {
    return "write";
  } else {
    return "read";
  }
}

function encode_user(user) {
  return $json.object(
    listPrepend(
      ["id", $json.string(user.id)],
      $list.map(
        $dict.to_list(user.properties),
        (property) => {
          return [property[0], $wire.dynamic_to_json(property[1])];
        },
      ),
    ),
  );
}

function encode_client_details(details) {
  return $json.object(
    $list.flatten(
      toList([
        toList([
          [
            "capabilities",
            $json.object(
              toList([
                ["interactive", $json.bool(details.capabilities.interactive)],
              ]),
            ),
          ],
        ]),
        optional_field("type", details.client_type, $json.string),
        optional_field("environment", details.environment, $json.string),
        optional_field("device", details.device, $json.string),
      ]),
    ),
  );
}

export function encode_client(client) {
  return $json.object(
    $list.flatten(
      toList([
        toList([
          ["mode", $json.string(mode_to_string(client.mode))],
          ["details", encode_client_details(client.details)],
          ["permission", $json.array(client.permission, $json.string)],
          ["user", encode_user(client.user)],
          ["scopes", $json.array(client.scopes, $json.string)],
        ]),
        optional_field("timestamp", client.timestamp, $json.int),
      ]),
    ),
  );
}

/**
 * The `connect_document` payload. The server requires `tenantId`, `id`,
 * `client`, `mode`, and `token`. `versions` controls the protocol
 * negotiation.
 *
 * `last_seen_sequence_number` is **advisory**, and no server uses it. This
 * documentation gave a different promise before: an automatic delta catch-up,
 * pushed as a usual `op` event. floodgate does not do that. It does not
 * read the field, and it answers a reconnect with the same full bootstrap that
 * it gives a cold join. That incorrect promise made a reconnecting client wait
 * for a delta that no server sent. The client must do its own catch-up with
 * `requestOps`. See `runtime_core.catch_up_from`. The client still sends the
 * field, because the field costs nothing and a server that did use it would
 * need it.
 */
export function encode_connect_document(message, last_seen_sequence_number) {
  return $json.object(
    $list.flatten(
      toList([
        toList([
          ["tenantId", $json.string(message.tenant_id)],
          ["id", $json.string(message.document_id)],
          ["token", $json.nullable(message.token, $json.string)],
          ["client", encode_client(message.client)],
          ["mode", $json.string(mode_to_string(message.mode))],
          ["versions", $json.array(message.versions, $json.string)],
        ]),
        optional_field("driverVersion", message.driver_version, $json.string),
        optional_field("nonce", message.nonce, $json.string),
        optional_field("epoch", message.epoch, $json.string),
        (() => {
          let $ = message.supported_features;
          if ($ instanceof Some) {
            let features = $[0];
            return toList([["supportedFeatures", encode_dynamic_dict(features)]]);
          } else {
            return $List$Empty$const;
          }
        })(),
        optional_field("relayUserAgent", message.relay_user_agent, $json.string),
        optional_field(
          "lastSeenSequenceNumber",
          last_seen_sequence_number,
          $json.int,
        ),
      ]),
    ),
  );
}

function encode_outbound_operation(operation) {
  return $json.object(
    $list.flatten(
      toList([
        toList([
          ["type", $json.string(operation.operation_type)],
          ["contents", operation.contents],
          ["clientSequenceNumber", $json.int(operation.client_sequence_number)],
          [
            "referenceSequenceNumber",
            $json.int(operation.reference_sequence_number),
          ],
        ]),
        optional_field(
          "metadata",
          operation.metadata,
          (metadata) => { return metadata; },
        ),
      ]),
    ),
  );
}

/**
 * The `submitOp` payload: `{clientId, messageBatches}`. The server nacks a
 * submission of more than 100 operations in total. The runtime applies that
 * limit.
 */
export function encode_submit_operation(client_id, batches) {
  return $json.object(
    toList([
      ["clientId", $json.string(client_id)],
      [
        "messageBatches",
        $json.array(
          batches,
          (batch) => { return $json.array(batch, encode_outbound_operation); },
        ),
      ],
    ]),
  );
}

/**
 * The `requestOps` payload, for an in-band delta catch-up. The response
 * arrives as a usual `op` event.
 */
export function encode_request_operations(from) {
  return $json.object(toList([["from", $json.int(from)]]));
}

/**
 * The `submitSignal` payload, for an ephemeral ripple that does not sequence.
 * It uses the V2 format that the `normalize_signal` function of levee needs:
 * a `contentBatches` list with one entry. That entry carries the application
 * `content`, which is any JSON, and a `type` tag. A ripple has no sequencing,
 * no persistence, no ack, and no catch-up.
 */
export function encode_submit_ripple(client_id, ripple_type, content) {
  return $json.object(
    toList([
      ["clientId", $json.string(client_id)],
      [
        "contentBatches",
        $json.preprocessed_array(
          toList([
            $json.object(
              toList([["content", content], ["type", $json.string(ripple_type)]]),
            ),
          ]),
        ),
      ],
    ]),
  );
}

/**
 * The `noop` heartbeat payload. It advances the MSN of the server while the
 * client is idle.
 */
export function encode_noop(client_id, reference_sequence_number) {
  return $json.object(
    toList([
      ["clientId", $json.string(client_id)],
      ["referenceSequenceNumber", $json.int(reference_sequence_number)],
    ]),
  );
}

function mode_decoder() {
  let _pipe = $decode.string;
  return $decode.then$(
    _pipe,
    (mode) => {
      if (mode === "write") {
        return $decode.success(ConnectionMode$WriteMode$const);
      } else if (mode === "read") {
        return $decode.success(ConnectionMode$ReadMode$const);
      } else {
        return $decode.failure(ConnectionMode$WriteMode$const, "ConnectionMode");
      }
    },
  );
}

function resolve_summary_context(nested, flat_handle, flat_sequence_number) {
  if (nested instanceof Some) {
    let context = nested[0];
    return $decode.success(new Some(context));
  } else if (flat_handle instanceof Some) {
    if (flat_sequence_number instanceof Some) {
      let $ = flat_handle[0];
      if ($ === "") {
        let $1 = flat_sequence_number[0];
        if ($1 === 0) {
          return $decode.success(Option$None$const);
        } else {
          let handle = $;
          let sequence_number = $1;
          return $decode.success(
            new Some(new SummaryContext(handle, sequence_number)),
          );
        }
      } else {
        let handle = $;
        let sequence_number = flat_sequence_number[0];
        return $decode.success(
          new Some(new SummaryContext(handle, sequence_number)),
        );
      }
    } else {
      return $decode.failure(Option$None$const, "complete summary fields");
    }
  } else if (flat_sequence_number instanceof None) {
    return $decode.success(Option$None$const);
  } else {
    return $decode.failure(Option$None$const, "complete summary fields");
  }
}

/**
 * The `summaryContext` sub-object of `connect_document_success`:
 * `{handle, sequenceNumber}`.
 */
export function summary_context_decoder() {
  return $decode.field(
    "handle",
    $decode.string,
    (handle) => {
      return $decode.field(
        "sequenceNumber",
        $decode.int,
        (sequence_number) => {
          return $decode.success(new SummaryContext(handle, sequence_number));
        },
      );
    },
  );
}

/**
 * The decoder for an inbound `ripple` broadcast, which is a `SignalMessage`.
 * A ripple is ephemeral: the server does not sequence it, store it, or ack
 * it. `content` stays `Dynamic`, for the application to decode.
 */
export function ripple_message_decoder() {
  return $decode.optional_field(
    "clientId",
    Option$None$const,
    $decode.optional($decode.string),
    (client_id) => {
      return $decode.field(
        "content",
        $decode.dynamic,
        (content) => {
          return $decode.optional_field(
            "type",
            Option$None$const,
            $decode.optional($decode.string),
            (ripple_type) => {
              return $decode.optional_field(
                "clientConnectionNumber",
                Option$None$const,
                $decode.optional($decode.int),
                (client_connection_number) => {
                  return $decode.optional_field(
                    "referenceSequenceNumber",
                    Option$None$const,
                    $decode.optional($decode.int),
                    (reference_sequence_number) => {
                      return $decode.optional_field(
                        "targetClientId",
                        Option$None$const,
                        $decode.optional($decode.string),
                        (target_client_id) => {
                          return $decode.success(
                            new SignalMessage(
                              client_id,
                              content,
                              ripple_type,
                              client_connection_number,
                              reference_sequence_number,
                              target_client_id,
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * One sequenced message, as the `session_logic.build_sequenced_op` function
 * of spillway builds it. `clientId` is null for a system message, which is a
 * join, a leave, or a summary message.
 */
export function sequenced_document_message_decoder() {
  return $decode.field(
    "clientId",
    $decode.optional($decode.string),
    (client_id) => {
      return $decode.field(
        "sequenceNumber",
        $decode.int,
        (sequence_number) => {
          return $decode.field(
            "minimumSequenceNumber",
            $decode.int,
            (minimum_sequence_number) => {
              return $decode.field(
                "clientSequenceNumber",
                $decode.int,
                (client_sequence_number) => {
                  return $decode.field(
                    "referenceSequenceNumber",
                    $decode.int,
                    (reference_sequence_number) => {
                      return $decode.field(
                        "type",
                        $decode.string,
                        (message_type) => {
                          return $decode.field(
                            "contents",
                            $decode.dynamic,
                            (contents) => {
                              return $decode.optional_field(
                                "metadata",
                                Option$None$const,
                                $decode.optional($decode.dynamic),
                                (metadata) => {
                                  return $decode.optional_field(
                                    "serverMetadata",
                                    Option$None$const,
                                    $decode.optional($decode.dynamic),
                                    (server_metadata) => {
                                      return $decode.field(
                                        "timestamp",
                                        $decode.int,
                                        (timestamp) => {
                                          return $decode.optional_field(
                                            "data",
                                            Option$None$const,
                                            $decode.optional($decode.string),
                                            (data) => {
                                              return $decode.success(
                                                new SequencedDocumentMessage(
                                                  client_id,
                                                  sequence_number,
                                                  minimum_sequence_number,
                                                  client_sequence_number,
                                                  reference_sequence_number,
                                                  message_type,
                                                  contents,
                                                  metadata,
                                                  server_metadata,
                                                  Option$None$const,
                                                  Option$None$const,
                                                  timestamp,
                                                  data,
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function user_decoder() {
  return $decode.field(
    "id",
    $decode.string,
    (id) => {
      return $decode.then$(
        $decode.dict($decode.string, $decode.dynamic),
        (all_fields) => {
          return $decode.success(
            new $token.User(id, $dict.delete$(all_fields, "id")),
          );
        },
      );
    },
  );
}

function client_details_decoder() {
  return $decode.optional_field(
    "capabilities",
    true,
    $decode.field("interactive", $decode.bool, $decode.success),
    (interactive) => {
      return $decode.optional_field(
        "type",
        Option$None$const,
        $decode.optional($decode.string),
        (client_type) => {
          return $decode.optional_field(
            "environment",
            Option$None$const,
            $decode.optional($decode.string),
            (environment) => {
              return $decode.optional_field(
                "device",
                Option$None$const,
                $decode.optional($decode.string),
                (device) => {
                  return $decode.success(
                    new ClientDetails(
                      new ClientCapabilities(interactive),
                      client_type,
                      environment,
                      device,
                    ),
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function default_client_details() {
  return new ClientDetails(
    new ClientCapabilities(true),
    Option$None$const,
    Option$None$const,
    Option$None$const,
  );
}

/**
 * A permissive `Client` decoder. The server echoes back the same structure
 * that the joining client sent, so a missing field takes a default value.
 */
export function client_decoder() {
  return $decode.optional_field(
    "mode",
    ConnectionMode$WriteMode$const,
    mode_decoder(),
    (mode) => {
      return $decode.optional_field(
        "details",
        default_client_details(),
        client_details_decoder(),
        (details) => {
          return $decode.optional_field(
            "permission",
            $List$Empty$const,
            $decode.list($decode.string),
            (permission) => {
              return $decode.optional_field(
                "user",
                new $token.User("", $dict.new$()),
                user_decoder(),
                (user) => {
                  return $decode.optional_field(
                    "scopes",
                    $List$Empty$const,
                    $decode.list($decode.string),
                    (scopes) => {
                      return $decode.optional_field(
                        "timestamp",
                        Option$None$const,
                        $decode.optional($decode.int),
                        (timestamp) => {
                          return $decode.success(
                            new Client(
                              mode,
                              details,
                              permission,
                              user,
                              scopes,
                              timestamp,
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function ripple_client_decoder() {
  return $decode.field(
    "clientId",
    $decode.string,
    (client_id) => {
      return $decode.field(
        "client",
        client_decoder(),
        (client) => {
          return $decode.optional_field(
            "clientConnectionNumber",
            Option$None$const,
            $decode.optional($decode.int),
            (client_connection_number) => {
              return $decode.optional_field(
                "referenceSequenceNumber",
                Option$None$const,
                $decode.optional($decode.int),
                (reference_sequence_number) => {
                  return $decode.success(
                    new SignalClient(
                      client_id,
                      client,
                      client_connection_number,
                      reference_sequence_number,
                    ),
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function service_configuration_decoder() {
  return $decode.field(
    "blockSize",
    $decode.int,
    (block_size) => {
      return $decode.field(
        "maxMessageSize",
        $decode.int,
        (max_message_size) => {
          return $decode.optional_field(
            "noopTimeFrequency",
            Option$None$const,
            $decode.optional($decode.int),
            (noop_time_frequency) => {
              return $decode.optional_field(
                "noopCountFrequency",
                Option$None$const,
                $decode.optional($decode.int),
                (noop_count_frequency) => {
                  return $decode.success(
                    new ServiceConfiguration(
                      block_size,
                      max_message_size,
                      noop_time_frequency,
                      noop_count_frequency,
                    ),
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function scope_decoder() {
  return $decode.then$(
    $decode.string,
    (value) => {
      let $ = $token.scope_from_string(value);
      if ($ instanceof Ok) {
        let scope = $[0];
        return $decode.success(scope);
      } else {
        return $decode.failure($token.Scope$DocRead$const, "Scope");
      }
    },
  );
}

export function token_claims_decoder() {
  return $decode.field(
    "documentId",
    $decode.string,
    (document_id) => {
      return $decode.field(
        "scopes",
        $decode.list(scope_decoder()),
        (scopes) => {
          return $decode.field(
            "tenantId",
            $decode.string,
            (tenant_id) => {
              return $decode.field(
                "user",
                user_decoder(),
                (user) => {
                  return $decode.field(
                    "iat",
                    $decode.int,
                    (issued_at) => {
                      return $decode.field(
                        "exp",
                        $decode.int,
                        (expiration) => {
                          return $decode.field(
                            "ver",
                            $decode.string,
                            (version) => {
                              return $decode.optional_field(
                                "jti",
                                Option$None$const,
                                $decode.optional($decode.string),
                                (jti) => {
                                  return $decode.success(
                                    new $token.TokenClaims(
                                      document_id,
                                      scopes,
                                      tenant_id,
                                      user,
                                      issued_at,
                                      expiration,
                                      version,
                                      jti,
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * The `connect_document_success` payload.
 */
export function connected_message_decoder() {
  return $decode.field(
    "claims",
    token_claims_decoder(),
    (claims) => {
      return $decode.field(
        "clientId",
        $decode.string,
        (client_id) => {
          return $decode.optional_field(
            "existing",
            true,
            $decode.bool,
            (existing) => {
              return $decode.field(
                "maxMessageSize",
                $decode.int,
                (max_message_size) => {
                  return $decode.field(
                    "mode",
                    mode_decoder(),
                    (mode) => {
                      return $decode.field(
                        "serviceConfiguration",
                        service_configuration_decoder(),
                        (service_configuration) => {
                          return $decode.optional_field(
                            "initialClients",
                            $List$Empty$const,
                            $decode.list(ripple_client_decoder()),
                            (initial_clients) => {
                              return $decode.optional_field(
                                "initialMessages",
                                $List$Empty$const,
                                $decode.list(
                                  sequenced_document_message_decoder(),
                                ),
                                (initial_messages) => {
                                  return $decode.optional_field(
                                    "initialSignals",
                                    $List$Empty$const,
                                    $decode.list(ripple_message_decoder()),
                                    (initial_signals) => {
                                      return $decode.optional_field(
                                        "supportedVersions",
                                        $List$Empty$const,
                                        $decode.list($decode.string),
                                        (supported_versions) => {
                                          return $decode.optional_field(
                                            "supportedFeatures",
                                            $dict.new$(),
                                            $decode.dict(
                                              $decode.string,
                                              $decode.dynamic,
                                            ),
                                            (supported_features) => {
                                              return $decode.field(
                                                "version",
                                                $decode.string,
                                                (version) => {
                                                  return $decode.optional_field(
                                                    "timestamp",
                                                    Option$None$const,
                                                    $decode.optional(
                                                      $decode.int,
                                                    ),
                                                    (timestamp) => {
                                                      return $decode.optional_field(
                                                        "checkpointSequenceNumber",
                                                        Option$None$const,
                                                        $decode.optional(
                                                          $decode.int,
                                                        ),
                                                        (
                                                            checkpoint_sequence_number
                                                          ) => {
                                                          return $decode.optional_field(
                                                            "epoch",
                                                            Option$None$const,
                                                            $decode.optional(
                                                              $decode.string,
                                                            ),
                                                            (epoch) => {
                                                              return $decode.optional_field(
                                                                "relayServiceAgent",
                                                                Option$None$const,
                                                                $decode.optional(
                                                                  $decode.string,
                                                                ),
                                                                (
                                                                    relay_service_agent
                                                                  ) => {
                                                                  return $decode.optional_field(
                                                                    "summaryContext",
                                                                    Option$None$const,
                                                                    $decode.optional(
                                                                      summary_context_decoder(),
                                                                    ),
                                                                    (
                                                                        nested_summary_context
                                                                      ) => {
                                                                      return $decode.optional_field(
                                                                        "summaryHandle",
                                                                        Option$None$const,
                                                                        $decode.optional(
                                                                          $decode.string,
                                                                        ),
                                                                        (
                                                                            summary_handle
                                                                          ) => {
                                                                          return $decode.optional_field(
                                                                            "summarySequenceNumber",
                                                                            Option$None$const,
                                                                            $decode.optional(
                                                                              $decode.int,
                                                                            ),
                                                                            (
                                                                                summary_sequence_number
                                                                              ) => {
                                                                              return $decode.then$(
                                                                                resolve_summary_context(
                                                                                  nested_summary_context,
                                                                                  summary_handle,
                                                                                  summary_sequence_number,
                                                                                ),
                                                                                (
                                                                                    summary_context
                                                                                  ) => {
                                                                                  return $decode.success(
                                                                                    new ConnectedMessage(
                                                                                      claims,
                                                                                      client_id,
                                                                                      existing,
                                                                                      max_message_size,
                                                                                      mode,
                                                                                      service_configuration,
                                                                                      initial_clients,
                                                                                      initial_messages,
                                                                                      initial_signals,
                                                                                      supported_versions,
                                                                                      supported_features,
                                                                                      version,
                                                                                      timestamp,
                                                                                      checkpoint_sequence_number,
                                                                                      epoch,
                                                                                      relay_service_agent,
                                                                                      summary_context,
                                                                                    ),
                                                                                  );
                                                                                },
                                                                              );
                                                                            },
                                                                          );
                                                                        },
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          );
                                                        },
                                                      );
                                                    },
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Whether the `supportedFeatures` field of a `connect_document_success`
 * message announces `feature`. The function takes the dict, and not the whole
 * message, so a runtime can answer the same question from the value that it
 * stored at handshake time.
 *
 * The test is strict on purpose. The key must be present, *and* it must decode
 * as `True`. A server that does not know a feature omits the key. If this
 * function accepted a value that it cannot decode, the client would send that
 * server traffic that the server cannot answer.
 */
export function supports_feature(features, feature) {
  let $ = $dict.get(features, feature);
  if ($ instanceof Ok) {
    let value = $[0];
    return isEqual($decode.run(value, $decode.bool), new Ok(true));
  } else {
    return false;
  }
}

/**
 * The `connect_document_error` payload, in the HTTP form `{code, message}`.
 */
export function connect_error_decoder() {
  return $decode.field(
    "code",
    $decode.int,
    (code) => {
      return $decode.field(
        "message",
        $decode.string,
        (error_message) => {
          return $decode.success(new ConnectError(code, error_message));
        },
      );
    },
  );
}

function bare_operation_message_decoder() {
  return $decode.then$(
    $decode.list(sequenced_document_message_decoder()),
    (operations) => { return $decode.success(new OpMessage("", operations)); },
  );
}

function wrapped_operation_message_decoder() {
  return $decode.field(
    "documentId",
    $decode.string,
    (document_id) => {
      return $decode.field(
        "op",
        $decode.list(sequenced_document_message_decoder()),
        (operations) => {
          return $decode.success(new OpMessage(document_id, operations));
        },
      );
    },
  );
}

/**
 * The `op` event payload, in the two shapes that a server can send.
 *
 * levee wraps the messages: `{documentId, operation:
 * [SequencedDocumentMessage]}`. floodgate pushes the bare
 * `[SequencedDocumentMessage]` on every operation path: submit, join, leave,
 * `requestOps`, and summary. It omits the document id, which the channel topic
 * already gives. This decoder accepts both shapes, so one client works with
 * either server. `document_id` is `""` for the bare shape, and no caller reads
 * it.
 */
export function operation_message_decoder() {
  return $decode.one_of(
    wrapped_operation_message_decoder(),
    toList([bare_operation_message_decoder()]),
  );
}

function nack_error_type_decoder() {
  let _pipe = $decode.string;
  return $decode.then$(
    _pipe,
    (text) => {
      let $ = $nack.nack_error_type_from_string(text);
      if ($ instanceof Ok) {
        let error_type = $[0];
        return $decode.success(error_type);
      } else {
        return $decode.failure(
          $nack.NackErrorType$BadRequestError$const,
          "NackErrorType",
        );
      }
    },
  );
}

function nack_content_decoder() {
  return $decode.field(
    "code",
    $decode.int,
    (code) => {
      return $decode.field(
        "type",
        nack_error_type_decoder(),
        (error_type) => {
          return $decode.field(
            "message",
            $decode.string,
            (nack_message) => {
              return $decode.optional_field(
                "retryAfter",
                Option$None$const,
                $decode.optional($decode.int),
                (retry_after) => {
                  return $decode.success(
                    new NackContent(code, error_type, nack_message, retry_after),
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * An operation that a client wrote, as a nack echoes it back.
 */
export function document_message_decoder() {
  return $decode.field(
    "clientSequenceNumber",
    $decode.int,
    (client_sequence_number) => {
      return $decode.field(
        "referenceSequenceNumber",
        $decode.int,
        (reference_sequence_number) => {
          return $decode.field(
            "type",
            $decode.string,
            (message_type) => {
              return $decode.field(
                "contents",
                $decode.dynamic,
                (contents) => {
                  return $decode.optional_field(
                    "metadata",
                    Option$None$const,
                    $decode.optional($decode.dynamic),
                    (metadata) => {
                      return $decode.optional_field(
                        "serverMetadata",
                        Option$None$const,
                        $decode.optional($decode.dynamic),
                        (server_metadata) => {
                          return $decode.optional_field(
                            "compression",
                            Option$None$const,
                            $decode.optional($decode.string),
                            (compression) => {
                              return $decode.success(
                                new DocumentMessage(
                                  client_sequence_number,
                                  reference_sequence_number,
                                  message_type,
                                  contents,
                                  metadata,
                                  server_metadata,
                                  Option$None$const,
                                  compression,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function nack_decoder() {
  return $decode.optional_field(
    "operation",
    Option$None$const,
    $decode.optional(document_message_decoder()),
    (operation) => {
      return $decode.field(
        "sequenceNumber",
        $decode.int,
        (sequence_number) => {
          return $decode.field(
            "content",
            nack_content_decoder(),
            (content) => {
              return $decode.success(
                new Nack(operation, sequence_number, content),
              );
            },
          );
        },
      );
    },
  );
}

/**
 * The `nack` event payload: `{clientId, nacks}`. This decoder reads the nack
 * list only.
 */
export function nacks_decoder() {
  return $decode.field(
    "nacks",
    $decode.list(nack_decoder()),
    (nacks) => { return $decode.success(nacks); },
  );
}

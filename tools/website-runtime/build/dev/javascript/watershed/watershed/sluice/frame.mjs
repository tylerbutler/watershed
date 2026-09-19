/// <reference types="./frame.d.mts" />
import * as $json from "../../../gleam_json/gleam/json.mjs";
import * as $dict from "../../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $list from "../../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../../gleam_stdlib/gleam/string.mjs";
import * as $types from "../../../spillway/spillway/types.mjs";
import {
  Ok,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../../gleam.mjs";
import * as $presence from "../../watershed/presence.mjs";
import * as $wire from "../../watershed/wire.mjs";
import * as $socket from "../../watershed/wire/socket.mjs";

export class Sequenced extends $CustomType {
  constructor(client_id, sequence_number, minimum_sequence_number, client_sequence_number, reference_sequence_number, operation_type, contents, metadata, timestamp, data) {
    super();
    this.client_id = client_id;
    this.sequence_number = sequence_number;
    this.minimum_sequence_number = minimum_sequence_number;
    this.client_sequence_number = client_sequence_number;
    this.reference_sequence_number = reference_sequence_number;
    this.operation_type = operation_type;
    this.contents = contents;
    this.metadata = metadata;
    this.timestamp = timestamp;
    this.data = data;
  }
}
export const Sequenced$Sequenced = (client_id, sequence_number, minimum_sequence_number, client_sequence_number, reference_sequence_number, operation_type, contents, metadata, timestamp, data) =>
  new Sequenced(client_id,
  sequence_number,
  minimum_sequence_number,
  client_sequence_number,
  reference_sequence_number,
  operation_type,
  contents,
  metadata,
  timestamp,
  data);
export const Sequenced$isSequenced = (value) => value instanceof Sequenced;
export const Sequenced$Sequenced$client_id = (value) => value.client_id;
export const Sequenced$Sequenced$0 = (value) => value.client_id;
export const Sequenced$Sequenced$sequence_number = (value) =>
  value.sequence_number;
export const Sequenced$Sequenced$1 = (value) => value.sequence_number;
export const Sequenced$Sequenced$minimum_sequence_number = (value) =>
  value.minimum_sequence_number;
export const Sequenced$Sequenced$2 = (value) => value.minimum_sequence_number;
export const Sequenced$Sequenced$client_sequence_number = (value) =>
  value.client_sequence_number;
export const Sequenced$Sequenced$3 = (value) => value.client_sequence_number;
export const Sequenced$Sequenced$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const Sequenced$Sequenced$4 = (value) => value.reference_sequence_number;
export const Sequenced$Sequenced$operation_type = (value) =>
  value.operation_type;
export const Sequenced$Sequenced$5 = (value) => value.operation_type;
export const Sequenced$Sequenced$contents = (value) => value.contents;
export const Sequenced$Sequenced$6 = (value) => value.contents;
export const Sequenced$Sequenced$metadata = (value) => value.metadata;
export const Sequenced$Sequenced$7 = (value) => value.metadata;
export const Sequenced$Sequenced$timestamp = (value) => value.timestamp;
export const Sequenced$Sequenced$8 = (value) => value.timestamp;
export const Sequenced$Sequenced$data = (value) => value.data;
export const Sequenced$Sequenced$9 = (value) => value.data;

export class ConnectRequest extends $CustomType {
  constructor(tenant_id, document_id, client, last_seen_sequence_number) {
    super();
    this.tenant_id = tenant_id;
    this.document_id = document_id;
    this.client = client;
    this.last_seen_sequence_number = last_seen_sequence_number;
  }
}
export const ConnectRequest$ConnectRequest = (tenant_id, document_id, client, last_seen_sequence_number) =>
  new ConnectRequest(tenant_id, document_id, client, last_seen_sequence_number);
export const ConnectRequest$isConnectRequest = (value) =>
  value instanceof ConnectRequest;
export const ConnectRequest$ConnectRequest$tenant_id = (value) =>
  value.tenant_id;
export const ConnectRequest$ConnectRequest$0 = (value) => value.tenant_id;
export const ConnectRequest$ConnectRequest$document_id = (value) =>
  value.document_id;
export const ConnectRequest$ConnectRequest$1 = (value) => value.document_id;
export const ConnectRequest$ConnectRequest$client = (value) => value.client;
export const ConnectRequest$ConnectRequest$2 = (value) => value.client;
export const ConnectRequest$ConnectRequest$last_seen_sequence_number = (value) =>
  value.last_seen_sequence_number;
export const ConnectRequest$ConnectRequest$3 = (value) =>
  value.last_seen_sequence_number;

export class SubmittedOperation extends $CustomType {
  constructor(operation_type, contents, client_sequence_number, reference_sequence_number, metadata) {
    super();
    this.operation_type = operation_type;
    this.contents = contents;
    this.client_sequence_number = client_sequence_number;
    this.reference_sequence_number = reference_sequence_number;
    this.metadata = metadata;
  }
}
export const SubmittedOperation$SubmittedOperation = (operation_type, contents, client_sequence_number, reference_sequence_number, metadata) =>
  new SubmittedOperation(operation_type,
  contents,
  client_sequence_number,
  reference_sequence_number,
  metadata);
export const SubmittedOperation$isSubmittedOperation = (value) =>
  value instanceof SubmittedOperation;
export const SubmittedOperation$SubmittedOperation$operation_type = (value) =>
  value.operation_type;
export const SubmittedOperation$SubmittedOperation$0 = (value) =>
  value.operation_type;
export const SubmittedOperation$SubmittedOperation$contents = (value) =>
  value.contents;
export const SubmittedOperation$SubmittedOperation$1 = (value) =>
  value.contents;
export const SubmittedOperation$SubmittedOperation$client_sequence_number = (value) =>
  value.client_sequence_number;
export const SubmittedOperation$SubmittedOperation$2 = (value) =>
  value.client_sequence_number;
export const SubmittedOperation$SubmittedOperation$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SubmittedOperation$SubmittedOperation$3 = (value) =>
  value.reference_sequence_number;
export const SubmittedOperation$SubmittedOperation$metadata = (value) =>
  value.metadata;
export const SubmittedOperation$SubmittedOperation$4 = (value) =>
  value.metadata;

export class SubmitOperation extends $CustomType {
  constructor(client_id, batches) {
    super();
    this.client_id = client_id;
    this.batches = batches;
  }
}
export const SubmitOperation$SubmitOperation = (client_id, batches) =>
  new SubmitOperation(client_id, batches);
export const SubmitOperation$isSubmitOperation = (value) =>
  value instanceof SubmitOperation;
export const SubmitOperation$SubmitOperation$client_id = (value) =>
  value.client_id;
export const SubmitOperation$SubmitOperation$0 = (value) => value.client_id;
export const SubmitOperation$SubmitOperation$batches = (value) => value.batches;
export const SubmitOperation$SubmitOperation$1 = (value) => value.batches;

export class SignalSubmission extends $CustomType {
  constructor(client_id, content, signal_type) {
    super();
    this.client_id = client_id;
    this.content = content;
    this.signal_type = signal_type;
  }
}
export const SignalSubmission$SignalSubmission = (client_id, content, signal_type) =>
  new SignalSubmission(client_id, content, signal_type);
export const SignalSubmission$isSignalSubmission = (value) =>
  value instanceof SignalSubmission;
export const SignalSubmission$SignalSubmission$client_id = (value) =>
  value.client_id;
export const SignalSubmission$SignalSubmission$0 = (value) => value.client_id;
export const SignalSubmission$SignalSubmission$content = (value) =>
  value.content;
export const SignalSubmission$SignalSubmission$1 = (value) => value.content;
export const SignalSubmission$SignalSubmission$signal_type = (value) =>
  value.signal_type;
export const SignalSubmission$SignalSubmission$2 = (value) => value.signal_type;

export class PresenceMeta extends $CustomType {
  constructor(key, phx_ref, fields) {
    super();
    this.key = key;
    this.phx_ref = phx_ref;
    this.fields = fields;
  }
}
export const PresenceMeta$PresenceMeta = (key, phx_ref, fields) =>
  new PresenceMeta(key, phx_ref, fields);
export const PresenceMeta$isPresenceMeta = (value) =>
  value instanceof PresenceMeta;
export const PresenceMeta$PresenceMeta$key = (value) => value.key;
export const PresenceMeta$PresenceMeta$0 = (value) => value.key;
export const PresenceMeta$PresenceMeta$phx_ref = (value) => value.phx_ref;
export const PresenceMeta$PresenceMeta$1 = (value) => value.phx_ref;
export const PresenceMeta$PresenceMeta$fields = (value) => value.fields;
export const PresenceMeta$PresenceMeta$2 = (value) => value.fields;

const max_message_size = 16_384;

/**
 * The development defaults of floodgate. The client needs these values to be
 * present and more than zero, and nothing else.
 * 
 * @ignore
 */
const block_size = 65_536;

function connect_document_decoder() {
  return $decode.field(
    "tenantId",
    $decode.string,
    (tenant_id) => {
      return $decode.field(
        "id",
        $decode.string,
        (document_id) => {
          return $decode.field(
            "client",
            $socket.client_decoder(),
            (client) => {
              return $decode.optional_field(
                "lastSeenSequenceNumber",
                Option$None$const,
                $decode.optional($decode.int),
                (last_seen) => {
                  return $decode.success(
                    new ConnectRequest(
                      tenant_id,
                      document_id,
                      client,
                      last_seen,
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

function run(payload, decoder, what) {
  let _pipe = $decode.run(payload, decoder);
  return $result.map_error(_pipe, (_) => { return "malformed " + what; });
}

/**
 * Decode a `connect_document` payload. This is the inverse of
 * `socket.encode_connect_document`.
 */
export function decode_connect_document(payload) {
  return run(payload, connect_document_decoder(), "connect_document payload");
}

function submitted_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      return $decode.field(
        "contents",
        $wire.json_value_decoder(),
        (contents) => {
          return $decode.field(
            "clientSequenceNumber",
            $decode.int,
            (client_sequence_number) => {
              return $decode.field(
                "referenceSequenceNumber",
                $decode.int,
                (reference_sequence_number) => {
                  return $decode.optional_field(
                    "metadata",
                    Option$None$const,
                    $decode.optional($wire.json_value_decoder()),
                    (metadata) => {
                      return $decode.success(
                        new SubmittedOperation(
                          operation_type,
                          contents,
                          client_sequence_number,
                          reference_sequence_number,
                          metadata,
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
}

function submit_operation_decoder() {
  return $decode.field(
    "clientId",
    $decode.string,
    (client_id) => {
      return $decode.field(
        "messageBatches",
        $decode.list($decode.list(submitted_operation_decoder())),
        (batches) => {
          return $decode.success(new SubmitOperation(client_id, batches));
        },
      );
    },
  );
}

/**
 * Decode a `submitOp` payload. This is the inverse of
 * `socket.encode_submit_operation`.
 */
export function decode_submit_operation(payload) {
  return run(payload, submit_operation_decoder(), "submitOp payload");
}

/**
 * Decode a `requestOps` payload and return the `from` sequence number. This
 * is the inverse of `socket.encode_request_operations`.
 */
export function decode_request_operations(payload) {
  return run(
    payload,
    $decode.field("from", $decode.int, $decode.success),
    "requestOps",
  );
}

function noop_decoder() {
  return $decode.field(
    "clientId",
    $decode.string,
    (client_id) => {
      return $decode.field(
        "referenceSequenceNumber",
        $decode.int,
        (reference_sequence_number) => {
          return $decode.success([client_id, reference_sequence_number]);
        },
      );
    },
  );
}

/**
 * Decode a `noop` heartbeat and return `(clientId, referenceSequenceNumber)`.
 * This is the inverse of `socket.encode_noop`.
 */
export function decode_noop(payload) {
  return run(payload, noop_decoder(), "noop payload");
}

function signal_entry_decoder() {
  return $decode.field(
    "content",
    $wire.json_value_decoder(),
    (content) => {
      return $decode.optional_field(
        "type",
        Option$None$const,
        $decode.optional($decode.string),
        (signal_type) => { return $decode.success([content, signal_type]); },
      );
    },
  );
}

function submit_signal_decoder() {
  return $decode.field(
    "clientId",
    $decode.string,
    (client_id) => {
      return $decode.field(
        "contentBatches",
        $decode.list(signal_entry_decoder()),
        (entries) => {
          if (entries instanceof $Empty) {
            return $decode.failure(
              new SignalSubmission(client_id, $json.null$(), Option$None$const),
              "signal",
            );
          } else {
            let first = entries.head;
            return $decode.success(
              new SignalSubmission(client_id, first[0], first[1]),
            );
          }
        },
      );
    },
  );
}

/**
 * Decode a `submitSignal` payload and reduce it to its first content batch
 * entry. This is the inverse of `socket.encode_submit_ripple`.
 */
export function decode_submit_signal(payload) {
  return run(payload, submit_signal_decoder(), "submitSignal payload");
}

/**
 * Encode one sequenced operation, in the shape that
 * `socket.sequenced_document_message_decoder` accepts.
 */
export function encode_sequenced(operation) {
  return $json.object(
    $list.flatten(
      toList([
        toList([
          ["clientId", $json.nullable(operation.client_id, $json.string)],
          ["sequenceNumber", $json.int(operation.sequence_number)],
          [
            "minimumSequenceNumber",
            $json.int(operation.minimum_sequence_number),
          ],
          ["clientSequenceNumber", $json.int(operation.client_sequence_number)],
          [
            "referenceSequenceNumber",
            $json.int(operation.reference_sequence_number),
          ],
          ["type", $json.string(operation.operation_type)],
          ["contents", operation.contents],
          ["timestamp", $json.int(operation.timestamp)],
        ]),
        (() => {
          let $ = operation.metadata;
          if ($ instanceof Some) {
            let metadata = $[0];
            return toList([["metadata", metadata]]);
          } else {
            return $List$Empty$const;
          }
        })(),
        (() => {
          let $ = operation.data;
          if ($ instanceof Some) {
            let data = $[0];
            return toList([["data", $json.string(data)]]);
          } else {
            return $List$Empty$const;
          }
        })(),
      ]),
    ),
  );
}

/**
 * One `initialClients` entry. Every field of the nested `client` record is
 * optional to the decoder of the client, so the roster must carry the
 * identity only.
 * 
 * @ignore
 */
function encode_roster_entry(client_id) {
  return $json.object(
    toList([
      ["clientId", $json.string(client_id)],
      ["client", $json.object(toList([["mode", $json.string("write")]]))],
    ]),
  );
}

/**
 * Build a `connect_document_success` payload that the
 * `socket.connected_message_decoder` function of the client accepts. It
 * carries the assigned client id, the connected roster, the catch-up
 * `initial_messages`, and the current sequence checkpoint. The sluice serves
 * no summary, which is plan decision 5, so the payload omits
 * `summaryContext`.
 *
 * `initial_clients` fills the membership roster of a client, and thus the
 * quorum that its consensus kernels freeze a signoff list from. An empty
 * roster here reports no error. It makes every pact a one-member pact that
 * accepts immediately.
 */
export function encode_connected(
  client_id,
  tenant_id,
  document_id,
  scopes,
  checkpoint_sequence_number,
  initial_clients,
  initial_messages,
  timestamp,
  presence_v1
) {
  return $json.object(
    toList([
      [
        "claims",
        $json.object(
          toList([
            ["documentId", $json.string(document_id)],
            ["scopes", $json.array(scopes, $json.string)],
            ["tenantId", $json.string(tenant_id)],
            ["user", $json.object(toList([["id", $json.string(client_id)]]))],
            ["iat", $json.int(timestamp)],
            ["exp", $json.int(timestamp + 3600)],
            ["ver", $json.string("1.0")],
          ]),
        ),
      ],
      ["clientId", $json.string(client_id)],
      ["existing", $json.bool(true)],
      ["maxMessageSize", $json.int(max_message_size)],
      ["mode", $json.string("write")],
      [
        "serviceConfiguration",
        $json.object(
          toList([
            ["blockSize", $json.int(block_size)],
            ["maxMessageSize", $json.int(max_message_size)],
          ]),
        ),
      ],
      ["initialClients", $json.array(initial_clients, encode_roster_entry)],
      ["initialMessages", $json.array(initial_messages, encode_sequenced)],
      ["initialSignals", $json.preprocessed_array($List$Empty$const)],
      ["supportedVersions", $json.array(toList(["1.0"]), $json.string)],
      [
        "supportedFeatures",
        $json.object(
          toList([[$socket.feature_presence_v1, $json.bool(presence_v1)]]),
        ),
      ],
      ["version", $json.string("1.0")],
      ["checkpointSequenceNumber", $json.int(checkpoint_sequence_number)],
    ]),
  );
}

/**
 * Build an `op` event payload: the bare `[Sequenced...]` array. This is
 * the inverse of `socket.operation_message_decoder`.
 *
 * floodgate pushes this shape on every operation path. levee wrapped the
 * messages in `{documentId, operation: [...]}`. The channel topic already
 * gives the document id, and the sluice models the server that watershed
 * connects to.
 */
export function encode_operation_event(operations) {
  return $json.array(operations, encode_sequenced);
}

/**
 * The payload of a sequenced `"join"` message: an object that names the
 * client that arrived, serialized to JSON text. On a real server, `detail` is
 * the client record. No reader of the sluice needs that record, so the field
 * stays empty.
 */
export function system_join_data(client_id) {
  let _pipe = $json.object(
    toList([
      ["clientId", $json.string(client_id)],
      ["detail", $json.object($List$Empty$const)],
    ]),
  );
  return $json.to_string(_pipe);
}

/**
 * The payload of a sequenced `"leave"` message: the id of the client that
 * left, as a bare JSON string, serialized to JSON text. The shape differs
 * from `system_join_data` on purpose. That difference comes from the server,
 * and the client decodes each shape correctly.
 */
export function system_leave_data(client_id) {
  let _pipe = $json.string(client_id);
  return $json.to_string(_pipe);
}

/**
 * Build a `signal` broadcast. This is the inverse of
 * `socket.ripple_message_decoder`. floodgate removes the `type` field of a
 * ripple on a broadcast, for compatibility with Fluid, so this function omits
 * that field on purpose. A consumer separates the kinds by the content
 * envelope.
 */
export function encode_signal(from_client, content) {
  return $json.object(
    toList([["clientId", $json.string(from_client)], ["content", content]]),
  );
}

function is_reserved_meta_field(name) {
  return (($list.contains($presence.reserved_meta_fields, name) || (name === "key")) || (name === "session_id")) || (name === "clientId");
}

function presence_meta_decoder() {
  return $decode.field(
    "meta",
    $decode.dict($decode.string, $wire.json_value_decoder()),
    (fields) => { return $decode.success($dict.to_list(fields)); },
  );
}

/**
 * Read the `meta` object from a `joinPresence` push or an `updatePresence`
 * push.
 *
 * The metadata must be a JSON *object*. The Phoenix `metas` shape puts
 * `phx_ref` and `client_id` beside the fields of the application, and a scalar
 * or an array has no position for them. The function drops each key that the
 * server owns, and it does not trust such a key. A client cannot select its
 * own reference_sequence_number, session, or presence key.
 */
export function decode_presence_meta(payload) {
  return $result.try$(
    run(payload, presence_meta_decoder(), "presence command"),
    (fields) => {
      return new Ok(
        $list.filter(
          fields,
          (field) => { return !is_reserved_meta_field(field[0]); },
        ),
      );
    },
  );
}

/**
 * Whether a key that a client supplied at the top level of a presence command
 * is a key that the server owns. The sluice uses this function to refuse a
 * spoofing attempt, and not to ignore it quietly.
 */
export function names_reserved_field(payload) {
  let $ = $decode.run(payload, $decode.dict($decode.string, $decode.dynamic));
  if ($ instanceof Ok) {
    let fields = $[0];
    return $list.any(
      $dict.keys(fields),
      (name) => { return is_reserved_meta_field(name) || (name === "key"); },
    );
  } else {
    return false;
  }
}

/**
 * Group the tracked presences into `{key: {metas: [...]}}`, and add the
 * server-owned `phx_ref` and `client_id` to each meta. The entries arrive
 * keyed by session id. Several sessions can share one presence key, which is
 * how two tabs of one user appear.
 * 
 * @ignore
 */
function encode_metas_by_key(entries) {
  let _pipe = entries;
  let _pipe$1 = $list.fold(
    _pipe,
    $dict.new$(),
    (grouped, entry) => {
      let session_id = entry[0];
      let meta = entry[1];
      let stamped = $json.object(
        listPrepend(
          ["phx_ref", $json.string(meta.phx_ref)],
          listPrepend(["client_id", $json.string(session_id)], meta.fields),
        ),
      );
      return $dict.upsert(
        grouped,
        meta.key,
        (existing) => {
          if (existing instanceof Some) {
            let metas = existing[0];
            return listPrepend(stamped, metas);
          } else {
            return toList([stamped]);
          }
        },
      );
    },
  );
  let _pipe$2 = $dict.to_list(_pipe$1);
  let _pipe$3 = $list.sort(
    _pipe$2,
    (left, right) => { return $string.compare(left[0], right[0]); },
  );
  let _pipe$4 = $list.map(
    _pipe$3,
    (group) => {
      return [
        group[0],
        $json.object(
          toList([["metas", $json.preprocessed_array($list.reverse(group[1]))]]),
        ),
      ];
    },
  );
  return $json.object(_pipe$4);
}

/**
 * A `presence_state` snapshot: `{key: {metas: [...]}}`. The keys are sorted,
 * so a test can compare two frames without a normalization step.
 */
export function encode_presence_state(entries) {
  return encode_metas_by_key(entries);
}

/**
 * A `presence_diff`: `{joins: {...}, leaves: {...}}`.
 */
export function encode_presence_diff(joins, leaves) {
  return $json.object(
    toList([
      ["joins", encode_metas_by_key(joins)],
      ["leaves", encode_metas_by_key(leaves)],
    ]),
  );
}

/**
 * A `presence_error`, which is the only failure channel of the presence lane.
 * A presence command is a push with no reply, so a rejection must arrive as
 * its own frame.
 */
export function encode_presence_error(code, message) {
  return $json.object(
    toList([["code", $json.string(code)], ["message", $json.string(message)]]),
  );
}

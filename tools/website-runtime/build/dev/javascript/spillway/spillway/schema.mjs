/// <reference types="./schema.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import { toList } from "../gleam.mjs";

function string_type() {
  return $json.object(toList([["type", $json.string("string")]]));
}

function int_type() {
  return $json.object(toList([["type", $json.string("integer")]]));
}

function bool_type() {
  return $json.object(toList([["type", $json.string("boolean")]]));
}

function any_type() {
  return $json.bool(true);
}

function nullable_string() {
  return $json.object(
    toList([
      [
        "type",
        $json.preprocessed_array(
          toList([$json.string("string"), $json.string("null")]),
        ),
      ],
    ]),
  );
}

function string_array() {
  return $json.object(
    toList([["type", $json.string("array")], ["items", string_type()]]),
  );
}

function array_of(items) {
  return $json.object(
    toList([["type", $json.string("array")], ["items", items]]),
  );
}

function ref(name) {
  return $json.object(toList([["$ref", $json.string("#/$defs/" + name)]]));
}

function string_enum(values) {
  return $json.object(
    toList([
      ["type", $json.string("string")],
      ["enum", $json.array(values, $json.string)],
    ]),
  );
}

function object_schema(properties, required) {
  return $json.object(
    toList([
      ["type", $json.string("object")],
      ["properties", $json.object(properties)],
      ["required", $json.array(required, $json.string)],
      ["additionalProperties", $json.bool(false)],
    ]),
  );
}

function connection_mode_schema() {
  return string_enum(toList(["write", "read"]));
}

function scope_schema() {
  return string_enum(
    toList(["doc:read", "doc:write", "summary:read", "summary:write"]),
  );
}

function user_schema() {
  return object_schema(
    toList([
      ["id", string_type()],
      [
        "properties",
        $json.object(
          toList([
            ["type", $json.string("object")],
            ["additionalProperties", any_type()],
          ]),
        ),
      ],
    ]),
    toList(["id", "properties"]),
  );
}

function client_capabilities_schema() {
  return object_schema(
    toList([["interactive", bool_type()]]),
    toList(["interactive"]),
  );
}

function client_details_schema() {
  return object_schema(
    toList([
      ["capabilities", ref("ClientCapabilities")],
      ["client_type", string_type()],
      ["environment", string_type()],
      ["device", string_type()],
    ]),
    toList(["capabilities"]),
  );
}

function client_schema() {
  return object_schema(
    toList([
      ["mode", connection_mode_schema()],
      ["details", ref("ClientDetails")],
      ["permission", string_array()],
      ["user", ref("User")],
      ["scopes", string_array()],
      ["timestamp", int_type()],
    ]),
    toList(["mode", "details", "permission", "user", "scopes"]),
  );
}

function sequenced_client_schema() {
  return object_schema(
    toList([["client", ref("Client")], ["sequence_number", int_type()]]),
    toList(["client", "sequence_number"]),
  );
}

function signal_client_schema() {
  return object_schema(
    toList([
      ["client_id", string_type()],
      ["client", ref("Client")],
      ["client_connection_number", int_type()],
      ["reference_sequence_number", int_type()],
    ]),
    toList(["client_id", "client"]),
  );
}

function service_configuration_schema() {
  return object_schema(
    toList([
      ["block_size", int_type()],
      ["max_message_size", int_type()],
      ["noop_time_frequency", int_type()],
      ["noop_count_frequency", int_type()],
    ]),
    toList(["block_size", "max_message_size"]),
  );
}

function trace_schema() {
  return object_schema(
    toList([
      ["service", string_type()],
      ["action", string_type()],
      ["timestamp", int_type()],
    ]),
    toList(["service", "action", "timestamp"]),
  );
}

function message_origin_schema() {
  return object_schema(
    toList([
      ["id", string_type()],
      ["sequence_number", int_type()],
      ["minimum_sequence_number", int_type()],
    ]),
    toList(["id", "sequence_number", "minimum_sequence_number"]),
  );
}

function document_message_schema() {
  return object_schema(
    toList([
      ["client_sequence_number", int_type()],
      ["reference_sequence_number", int_type()],
      ["message_type", string_type()],
      ["contents", any_type()],
      ["metadata", any_type()],
      ["server_metadata", any_type()],
      ["traces", array_of(ref("Trace"))],
      ["compression", string_type()],
    ]),
    toList([
      "client_sequence_number",
      "reference_sequence_number",
      "message_type",
      "contents",
    ]),
  );
}

function sequenced_document_message_schema() {
  return object_schema(
    toList([
      ["client_id", nullable_string()],
      ["sequence_number", int_type()],
      ["minimum_sequence_number", int_type()],
      ["client_sequence_number", int_type()],
      ["reference_sequence_number", int_type()],
      ["message_type", string_type()],
      ["contents", any_type()],
      ["metadata", any_type()],
      ["server_metadata", any_type()],
      ["origin", ref("MessageOrigin")],
      ["traces", array_of(ref("Trace"))],
      ["timestamp", int_type()],
      ["data", string_type()],
    ]),
    toList([
      "sequence_number",
      "minimum_sequence_number",
      "client_sequence_number",
      "reference_sequence_number",
      "message_type",
      "contents",
      "timestamp",
    ]),
  );
}

function token_claims_schema() {
  return object_schema(
    toList([
      ["document_id", string_type()],
      ["scopes", string_array()],
      ["tenant_id", string_type()],
      ["user", ref("User")],
      ["issued_at", int_type()],
      ["expiration", int_type()],
      ["version", string_type()],
      ["jti", string_type()],
    ]),
    toList([
      "document_id",
      "scopes",
      "tenant_id",
      "user",
      "issued_at",
      "expiration",
      "version",
    ]),
  );
}

/**
 * Generate JSON schema for all protocol types as a combined schema
 */
export function generate_protocol_schema() {
  let defs = toList([
    ["ConnectionMode", connection_mode_schema()],
    ["User", user_schema()],
    ["ClientCapabilities", client_capabilities_schema()],
    ["ClientDetails", client_details_schema()],
    ["Client", client_schema()],
    ["SequencedClient", sequenced_client_schema()],
    ["SignalClient", signal_client_schema()],
    ["ServiceConfiguration", service_configuration_schema()],
    ["Trace", trace_schema()],
    ["MessageOrigin", message_origin_schema()],
    ["DocumentMessage", document_message_schema()],
    ["SequencedDocumentMessage", sequenced_document_message_schema()],
    ["Scope", scope_schema()],
    ["TokenClaims", token_claims_schema()],
  ]);
  let root_props = toList([
    ["ConnectionMode", ref("ConnectionMode")],
    ["User", ref("User")],
    ["ClientCapabilities", ref("ClientCapabilities")],
    ["ClientDetails", ref("ClientDetails")],
    ["Client", ref("Client")],
    ["SequencedClient", ref("SequencedClient")],
    ["SignalClient", ref("SignalClient")],
    ["ServiceConfiguration", ref("ServiceConfiguration")],
    ["Trace", ref("Trace")],
    ["MessageOrigin", ref("MessageOrigin")],
    ["DocumentMessage", ref("DocumentMessage")],
    ["SequencedDocumentMessage", ref("SequencedDocumentMessage")],
    ["Scope", ref("Scope")],
    ["TokenClaims", ref("TokenClaims")],
  ]);
  return $json.object(
    toList([
      ["$schema", $json.string("http://json-schema.org/draft-07/schema#")],
      ["type", $json.string("object")],
      ["additionalProperties", $json.bool(false)],
      ["properties", $json.object(root_props)],
      ["$defs", $json.object(defs)],
    ]),
  );
}

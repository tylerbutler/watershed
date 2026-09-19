/// <reference types="./types.d.mts" />
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import * as $token from "../../signet/signet/types.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

export class WriteMode extends $CustomType {}
export const ConnectionMode$WriteMode$const = new WriteMode();
export const ConnectionMode$WriteMode = () => ConnectionMode$WriteMode$const;
export const ConnectionMode$isWriteMode = (value) => value instanceof WriteMode;

export class ReadMode extends $CustomType {}
export const ConnectionMode$ReadMode$const = new ReadMode();
export const ConnectionMode$ReadMode = () => ConnectionMode$ReadMode$const;
export const ConnectionMode$isReadMode = (value) => value instanceof ReadMode;

export class ClientCapabilities extends $CustomType {
  constructor(interactive) {
    super();
    this.interactive = interactive;
  }
}
export const ClientCapabilities$ClientCapabilities = (interactive) =>
  new ClientCapabilities(interactive);
export const ClientCapabilities$isClientCapabilities = (value) =>
  value instanceof ClientCapabilities;
export const ClientCapabilities$ClientCapabilities$interactive = (value) =>
  value.interactive;
export const ClientCapabilities$ClientCapabilities$0 = (value) =>
  value.interactive;

export class ClientDetails extends $CustomType {
  constructor(capabilities, client_type, environment, device) {
    super();
    this.capabilities = capabilities;
    this.client_type = client_type;
    this.environment = environment;
    this.device = device;
  }
}
export const ClientDetails$ClientDetails = (capabilities, client_type, environment, device) =>
  new ClientDetails(capabilities, client_type, environment, device);
export const ClientDetails$isClientDetails = (value) =>
  value instanceof ClientDetails;
export const ClientDetails$ClientDetails$capabilities = (value) =>
  value.capabilities;
export const ClientDetails$ClientDetails$0 = (value) => value.capabilities;
export const ClientDetails$ClientDetails$client_type = (value) =>
  value.client_type;
export const ClientDetails$ClientDetails$1 = (value) => value.client_type;
export const ClientDetails$ClientDetails$environment = (value) =>
  value.environment;
export const ClientDetails$ClientDetails$2 = (value) => value.environment;
export const ClientDetails$ClientDetails$device = (value) => value.device;
export const ClientDetails$ClientDetails$3 = (value) => value.device;

export class Client extends $CustomType {
  constructor(mode, details, permission, user, scopes, timestamp) {
    super();
    this.mode = mode;
    this.details = details;
    this.permission = permission;
    this.user = user;
    this.scopes = scopes;
    this.timestamp = timestamp;
  }
}
export const Client$Client = (mode, details, permission, user, scopes, timestamp) =>
  new Client(mode, details, permission, user, scopes, timestamp);
export const Client$isClient = (value) => value instanceof Client;
export const Client$Client$mode = (value) => value.mode;
export const Client$Client$0 = (value) => value.mode;
export const Client$Client$details = (value) => value.details;
export const Client$Client$1 = (value) => value.details;
export const Client$Client$permission = (value) => value.permission;
export const Client$Client$2 = (value) => value.permission;
export const Client$Client$user = (value) => value.user;
export const Client$Client$3 = (value) => value.user;
export const Client$Client$scopes = (value) => value.scopes;
export const Client$Client$4 = (value) => value.scopes;
export const Client$Client$timestamp = (value) => value.timestamp;
export const Client$Client$5 = (value) => value.timestamp;

export class SequencedClient extends $CustomType {
  constructor(client, sequence_number) {
    super();
    this.client = client;
    this.sequence_number = sequence_number;
  }
}
export const SequencedClient$SequencedClient = (client, sequence_number) =>
  new SequencedClient(client, sequence_number);
export const SequencedClient$isSequencedClient = (value) =>
  value instanceof SequencedClient;
export const SequencedClient$SequencedClient$client = (value) => value.client;
export const SequencedClient$SequencedClient$0 = (value) => value.client;
export const SequencedClient$SequencedClient$sequence_number = (value) =>
  value.sequence_number;
export const SequencedClient$SequencedClient$1 = (value) =>
  value.sequence_number;

export class SignalClient extends $CustomType {
  constructor(client_id, client, client_connection_number, reference_sequence_number) {
    super();
    this.client_id = client_id;
    this.client = client;
    this.client_connection_number = client_connection_number;
    this.reference_sequence_number = reference_sequence_number;
  }
}
export const SignalClient$SignalClient = (client_id, client, client_connection_number, reference_sequence_number) =>
  new SignalClient(client_id,
  client,
  client_connection_number,
  reference_sequence_number);
export const SignalClient$isSignalClient = (value) =>
  value instanceof SignalClient;
export const SignalClient$SignalClient$client_id = (value) => value.client_id;
export const SignalClient$SignalClient$0 = (value) => value.client_id;
export const SignalClient$SignalClient$client = (value) => value.client;
export const SignalClient$SignalClient$1 = (value) => value.client;
export const SignalClient$SignalClient$client_connection_number = (value) =>
  value.client_connection_number;
export const SignalClient$SignalClient$2 = (value) =>
  value.client_connection_number;
export const SignalClient$SignalClient$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SignalClient$SignalClient$3 = (value) =>
  value.reference_sequence_number;

export class ServiceConfiguration extends $CustomType {
  constructor(block_size, max_message_size, noop_time_frequency, noop_count_frequency) {
    super();
    this.block_size = block_size;
    this.max_message_size = max_message_size;
    this.noop_time_frequency = noop_time_frequency;
    this.noop_count_frequency = noop_count_frequency;
  }
}
export const ServiceConfiguration$ServiceConfiguration = (block_size, max_message_size, noop_time_frequency, noop_count_frequency) =>
  new ServiceConfiguration(block_size,
  max_message_size,
  noop_time_frequency,
  noop_count_frequency);
export const ServiceConfiguration$isServiceConfiguration = (value) =>
  value instanceof ServiceConfiguration;
export const ServiceConfiguration$ServiceConfiguration$block_size = (value) =>
  value.block_size;
export const ServiceConfiguration$ServiceConfiguration$0 = (value) =>
  value.block_size;
export const ServiceConfiguration$ServiceConfiguration$max_message_size = (value) =>
  value.max_message_size;
export const ServiceConfiguration$ServiceConfiguration$1 = (value) =>
  value.max_message_size;
export const ServiceConfiguration$ServiceConfiguration$noop_time_frequency = (value) =>
  value.noop_time_frequency;
export const ServiceConfiguration$ServiceConfiguration$2 = (value) =>
  value.noop_time_frequency;
export const ServiceConfiguration$ServiceConfiguration$noop_count_frequency = (value) =>
  value.noop_count_frequency;
export const ServiceConfiguration$ServiceConfiguration$3 = (value) =>
  value.noop_count_frequency;

export class Trace extends $CustomType {
  constructor(service, action, timestamp) {
    super();
    this.service = service;
    this.action = action;
    this.timestamp = timestamp;
  }
}
export const Trace$Trace = (service, action, timestamp) =>
  new Trace(service, action, timestamp);
export const Trace$isTrace = (value) => value instanceof Trace;
export const Trace$Trace$service = (value) => value.service;
export const Trace$Trace$0 = (value) => value.service;
export const Trace$Trace$action = (value) => value.action;
export const Trace$Trace$1 = (value) => value.action;
export const Trace$Trace$timestamp = (value) => value.timestamp;
export const Trace$Trace$2 = (value) => value.timestamp;

export class DocumentMessage extends $CustomType {
  constructor(client_sequence_number, reference_sequence_number, message_type, contents, metadata, server_metadata, traces, compression) {
    super();
    this.client_sequence_number = client_sequence_number;
    this.reference_sequence_number = reference_sequence_number;
    this.message_type = message_type;
    this.contents = contents;
    this.metadata = metadata;
    this.server_metadata = server_metadata;
    this.traces = traces;
    this.compression = compression;
  }
}
export const DocumentMessage$DocumentMessage = (client_sequence_number, reference_sequence_number, message_type, contents, metadata, server_metadata, traces, compression) =>
  new DocumentMessage(client_sequence_number,
  reference_sequence_number,
  message_type,
  contents,
  metadata,
  server_metadata,
  traces,
  compression);
export const DocumentMessage$isDocumentMessage = (value) =>
  value instanceof DocumentMessage;
export const DocumentMessage$DocumentMessage$client_sequence_number = (value) =>
  value.client_sequence_number;
export const DocumentMessage$DocumentMessage$0 = (value) =>
  value.client_sequence_number;
export const DocumentMessage$DocumentMessage$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const DocumentMessage$DocumentMessage$1 = (value) =>
  value.reference_sequence_number;
export const DocumentMessage$DocumentMessage$message_type = (value) =>
  value.message_type;
export const DocumentMessage$DocumentMessage$2 = (value) => value.message_type;
export const DocumentMessage$DocumentMessage$contents = (value) =>
  value.contents;
export const DocumentMessage$DocumentMessage$3 = (value) => value.contents;
export const DocumentMessage$DocumentMessage$metadata = (value) =>
  value.metadata;
export const DocumentMessage$DocumentMessage$4 = (value) => value.metadata;
export const DocumentMessage$DocumentMessage$server_metadata = (value) =>
  value.server_metadata;
export const DocumentMessage$DocumentMessage$5 = (value) =>
  value.server_metadata;
export const DocumentMessage$DocumentMessage$traces = (value) => value.traces;
export const DocumentMessage$DocumentMessage$6 = (value) => value.traces;
export const DocumentMessage$DocumentMessage$compression = (value) =>
  value.compression;
export const DocumentMessage$DocumentMessage$7 = (value) => value.compression;

export class SequencedDocumentMessage extends $CustomType {
  constructor(client_id, sequence_number, minimum_sequence_number, client_sequence_number, reference_sequence_number, message_type, contents, metadata, server_metadata, origin, traces, timestamp, data) {
    super();
    this.client_id = client_id;
    this.sequence_number = sequence_number;
    this.minimum_sequence_number = minimum_sequence_number;
    this.client_sequence_number = client_sequence_number;
    this.reference_sequence_number = reference_sequence_number;
    this.message_type = message_type;
    this.contents = contents;
    this.metadata = metadata;
    this.server_metadata = server_metadata;
    this.origin = origin;
    this.traces = traces;
    this.timestamp = timestamp;
    this.data = data;
  }
}
export const SequencedDocumentMessage$SequencedDocumentMessage = (client_id, sequence_number, minimum_sequence_number, client_sequence_number, reference_sequence_number, message_type, contents, metadata, server_metadata, origin, traces, timestamp, data) =>
  new SequencedDocumentMessage(client_id,
  sequence_number,
  minimum_sequence_number,
  client_sequence_number,
  reference_sequence_number,
  message_type,
  contents,
  metadata,
  server_metadata,
  origin,
  traces,
  timestamp,
  data);
export const SequencedDocumentMessage$isSequencedDocumentMessage = (value) =>
  value instanceof SequencedDocumentMessage;
export const SequencedDocumentMessage$SequencedDocumentMessage$client_id = (value) =>
  value.client_id;
export const SequencedDocumentMessage$SequencedDocumentMessage$0 = (value) =>
  value.client_id;
export const SequencedDocumentMessage$SequencedDocumentMessage$sequence_number = (value) =>
  value.sequence_number;
export const SequencedDocumentMessage$SequencedDocumentMessage$1 = (value) =>
  value.sequence_number;
export const SequencedDocumentMessage$SequencedDocumentMessage$minimum_sequence_number = (value) =>
  value.minimum_sequence_number;
export const SequencedDocumentMessage$SequencedDocumentMessage$2 = (value) =>
  value.minimum_sequence_number;
export const SequencedDocumentMessage$SequencedDocumentMessage$client_sequence_number = (value) =>
  value.client_sequence_number;
export const SequencedDocumentMessage$SequencedDocumentMessage$3 = (value) =>
  value.client_sequence_number;
export const SequencedDocumentMessage$SequencedDocumentMessage$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SequencedDocumentMessage$SequencedDocumentMessage$4 = (value) =>
  value.reference_sequence_number;
export const SequencedDocumentMessage$SequencedDocumentMessage$message_type = (value) =>
  value.message_type;
export const SequencedDocumentMessage$SequencedDocumentMessage$5 = (value) =>
  value.message_type;
export const SequencedDocumentMessage$SequencedDocumentMessage$contents = (value) =>
  value.contents;
export const SequencedDocumentMessage$SequencedDocumentMessage$6 = (value) =>
  value.contents;
export const SequencedDocumentMessage$SequencedDocumentMessage$metadata = (value) =>
  value.metadata;
export const SequencedDocumentMessage$SequencedDocumentMessage$7 = (value) =>
  value.metadata;
export const SequencedDocumentMessage$SequencedDocumentMessage$server_metadata = (value) =>
  value.server_metadata;
export const SequencedDocumentMessage$SequencedDocumentMessage$8 = (value) =>
  value.server_metadata;
export const SequencedDocumentMessage$SequencedDocumentMessage$origin = (value) =>
  value.origin;
export const SequencedDocumentMessage$SequencedDocumentMessage$9 = (value) =>
  value.origin;
export const SequencedDocumentMessage$SequencedDocumentMessage$traces = (value) =>
  value.traces;
export const SequencedDocumentMessage$SequencedDocumentMessage$10 = (value) =>
  value.traces;
export const SequencedDocumentMessage$SequencedDocumentMessage$timestamp = (value) =>
  value.timestamp;
export const SequencedDocumentMessage$SequencedDocumentMessage$11 = (value) =>
  value.timestamp;
export const SequencedDocumentMessage$SequencedDocumentMessage$data = (value) =>
  value.data;
export const SequencedDocumentMessage$SequencedDocumentMessage$12 = (value) =>
  value.data;

export class MessageOrigin extends $CustomType {
  constructor(id, sequence_number, minimum_sequence_number) {
    super();
    this.id = id;
    this.sequence_number = sequence_number;
    this.minimum_sequence_number = minimum_sequence_number;
  }
}
export const MessageOrigin$MessageOrigin = (id, sequence_number, minimum_sequence_number) =>
  new MessageOrigin(id, sequence_number, minimum_sequence_number);
export const MessageOrigin$isMessageOrigin = (value) =>
  value instanceof MessageOrigin;
export const MessageOrigin$MessageOrigin$id = (value) => value.id;
export const MessageOrigin$MessageOrigin$0 = (value) => value.id;
export const MessageOrigin$MessageOrigin$sequence_number = (value) =>
  value.sequence_number;
export const MessageOrigin$MessageOrigin$1 = (value) => value.sequence_number;
export const MessageOrigin$MessageOrigin$minimum_sequence_number = (value) =>
  value.minimum_sequence_number;
export const MessageOrigin$MessageOrigin$2 = (value) =>
  value.minimum_sequence_number;

/**
 * Convert scope to string
 */
export function scope_to_string(scope) {
  return $token.scope_to_string(scope);
}

/**
 * Parse scope from string
 */
export function scope_from_string(value) {
  return $token.scope_from_string(value);
}

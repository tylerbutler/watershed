/// <reference types="./message.d.mts" />
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";
import * as $types from "../spillway/types.mjs";

export class ConnectMessage extends $CustomType {
  constructor(tenant_id, document_id, token, client, versions, driver_version, mode, nonce, epoch, supported_features, relay_user_agent) {
    super();
    this.tenant_id = tenant_id;
    this.document_id = document_id;
    this.token = token;
    this.client = client;
    this.versions = versions;
    this.driver_version = driver_version;
    this.mode = mode;
    this.nonce = nonce;
    this.epoch = epoch;
    this.supported_features = supported_features;
    this.relay_user_agent = relay_user_agent;
  }
}
export const ConnectMessage$ConnectMessage = (tenant_id, document_id, token, client, versions, driver_version, mode, nonce, epoch, supported_features, relay_user_agent) =>
  new ConnectMessage(tenant_id,
  document_id,
  token,
  client,
  versions,
  driver_version,
  mode,
  nonce,
  epoch,
  supported_features,
  relay_user_agent);
export const ConnectMessage$isConnectMessage = (value) =>
  value instanceof ConnectMessage;
export const ConnectMessage$ConnectMessage$tenant_id = (value) =>
  value.tenant_id;
export const ConnectMessage$ConnectMessage$0 = (value) => value.tenant_id;
export const ConnectMessage$ConnectMessage$document_id = (value) =>
  value.document_id;
export const ConnectMessage$ConnectMessage$1 = (value) => value.document_id;
export const ConnectMessage$ConnectMessage$token = (value) => value.token;
export const ConnectMessage$ConnectMessage$2 = (value) => value.token;
export const ConnectMessage$ConnectMessage$client = (value) => value.client;
export const ConnectMessage$ConnectMessage$3 = (value) => value.client;
export const ConnectMessage$ConnectMessage$versions = (value) => value.versions;
export const ConnectMessage$ConnectMessage$4 = (value) => value.versions;
export const ConnectMessage$ConnectMessage$driver_version = (value) =>
  value.driver_version;
export const ConnectMessage$ConnectMessage$5 = (value) => value.driver_version;
export const ConnectMessage$ConnectMessage$mode = (value) => value.mode;
export const ConnectMessage$ConnectMessage$6 = (value) => value.mode;
export const ConnectMessage$ConnectMessage$nonce = (value) => value.nonce;
export const ConnectMessage$ConnectMessage$7 = (value) => value.nonce;
export const ConnectMessage$ConnectMessage$epoch = (value) => value.epoch;
export const ConnectMessage$ConnectMessage$8 = (value) => value.epoch;
export const ConnectMessage$ConnectMessage$supported_features = (value) =>
  value.supported_features;
export const ConnectMessage$ConnectMessage$9 = (value) =>
  value.supported_features;
export const ConnectMessage$ConnectMessage$relay_user_agent = (value) =>
  value.relay_user_agent;
export const ConnectMessage$ConnectMessage$10 = (value) =>
  value.relay_user_agent;

export class ConnectedMessage extends $CustomType {
  constructor(claims, client_id, existing, max_message_size, mode, service_configuration, initial_clients, initial_messages, initial_signals, supported_versions, supported_features, version, timestamp, checkpoint_sequence_number, epoch, relay_service_agent, summary_context) {
    super();
    this.claims = claims;
    this.client_id = client_id;
    this.existing = existing;
    this.max_message_size = max_message_size;
    this.mode = mode;
    this.service_configuration = service_configuration;
    this.initial_clients = initial_clients;
    this.initial_messages = initial_messages;
    this.initial_signals = initial_signals;
    this.supported_versions = supported_versions;
    this.supported_features = supported_features;
    this.version = version;
    this.timestamp = timestamp;
    this.checkpoint_sequence_number = checkpoint_sequence_number;
    this.epoch = epoch;
    this.relay_service_agent = relay_service_agent;
    this.summary_context = summary_context;
  }
}
export const ConnectedMessage$ConnectedMessage = (claims, client_id, existing, max_message_size, mode, service_configuration, initial_clients, initial_messages, initial_signals, supported_versions, supported_features, version, timestamp, checkpoint_sequence_number, epoch, relay_service_agent, summary_context) =>
  new ConnectedMessage(claims,
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
  summary_context);
export const ConnectedMessage$isConnectedMessage = (value) =>
  value instanceof ConnectedMessage;
export const ConnectedMessage$ConnectedMessage$claims = (value) => value.claims;
export const ConnectedMessage$ConnectedMessage$0 = (value) => value.claims;
export const ConnectedMessage$ConnectedMessage$client_id = (value) =>
  value.client_id;
export const ConnectedMessage$ConnectedMessage$1 = (value) => value.client_id;
export const ConnectedMessage$ConnectedMessage$existing = (value) =>
  value.existing;
export const ConnectedMessage$ConnectedMessage$2 = (value) => value.existing;
export const ConnectedMessage$ConnectedMessage$max_message_size = (value) =>
  value.max_message_size;
export const ConnectedMessage$ConnectedMessage$3 = (value) =>
  value.max_message_size;
export const ConnectedMessage$ConnectedMessage$mode = (value) => value.mode;
export const ConnectedMessage$ConnectedMessage$4 = (value) => value.mode;
export const ConnectedMessage$ConnectedMessage$service_configuration = (value) =>
  value.service_configuration;
export const ConnectedMessage$ConnectedMessage$5 = (value) =>
  value.service_configuration;
export const ConnectedMessage$ConnectedMessage$initial_clients = (value) =>
  value.initial_clients;
export const ConnectedMessage$ConnectedMessage$6 = (value) =>
  value.initial_clients;
export const ConnectedMessage$ConnectedMessage$initial_messages = (value) =>
  value.initial_messages;
export const ConnectedMessage$ConnectedMessage$7 = (value) =>
  value.initial_messages;
export const ConnectedMessage$ConnectedMessage$initial_signals = (value) =>
  value.initial_signals;
export const ConnectedMessage$ConnectedMessage$8 = (value) =>
  value.initial_signals;
export const ConnectedMessage$ConnectedMessage$supported_versions = (value) =>
  value.supported_versions;
export const ConnectedMessage$ConnectedMessage$9 = (value) =>
  value.supported_versions;
export const ConnectedMessage$ConnectedMessage$supported_features = (value) =>
  value.supported_features;
export const ConnectedMessage$ConnectedMessage$10 = (value) =>
  value.supported_features;
export const ConnectedMessage$ConnectedMessage$version = (value) =>
  value.version;
export const ConnectedMessage$ConnectedMessage$11 = (value) => value.version;
export const ConnectedMessage$ConnectedMessage$timestamp = (value) =>
  value.timestamp;
export const ConnectedMessage$ConnectedMessage$12 = (value) => value.timestamp;
export const ConnectedMessage$ConnectedMessage$checkpoint_sequence_number = (value) =>
  value.checkpoint_sequence_number;
export const ConnectedMessage$ConnectedMessage$13 = (value) =>
  value.checkpoint_sequence_number;
export const ConnectedMessage$ConnectedMessage$epoch = (value) => value.epoch;
export const ConnectedMessage$ConnectedMessage$14 = (value) => value.epoch;
export const ConnectedMessage$ConnectedMessage$relay_service_agent = (value) =>
  value.relay_service_agent;
export const ConnectedMessage$ConnectedMessage$15 = (value) =>
  value.relay_service_agent;
export const ConnectedMessage$ConnectedMessage$summary_context = (value) =>
  value.summary_context;
export const ConnectedMessage$ConnectedMessage$16 = (value) =>
  value.summary_context;

export class SummaryContext extends $CustomType {
  constructor(handle, sequence_number) {
    super();
    this.handle = handle;
    this.sequence_number = sequence_number;
  }
}
export const SummaryContext$SummaryContext = (handle, sequence_number) =>
  new SummaryContext(handle, sequence_number);
export const SummaryContext$isSummaryContext = (value) =>
  value instanceof SummaryContext;
export const SummaryContext$SummaryContext$handle = (value) => value.handle;
export const SummaryContext$SummaryContext$0 = (value) => value.handle;
export const SummaryContext$SummaryContext$sequence_number = (value) =>
  value.sequence_number;
export const SummaryContext$SummaryContext$1 = (value) => value.sequence_number;

export class ConnectError extends $CustomType {
  constructor(code, message) {
    super();
    this.code = code;
    this.message = message;
  }
}
export const ConnectError$ConnectError = (code, message) =>
  new ConnectError(code, message);
export const ConnectError$isConnectError = (value) =>
  value instanceof ConnectError;
export const ConnectError$ConnectError$code = (value) => value.code;
export const ConnectError$ConnectError$0 = (value) => value.code;
export const ConnectError$ConnectError$message = (value) => value.message;
export const ConnectError$ConnectError$1 = (value) => value.message;

export class SignalMessage extends $CustomType {
  constructor(client_id, content, signal_type, client_connection_number, reference_sequence_number, target_client_id) {
    super();
    this.client_id = client_id;
    this.content = content;
    this.signal_type = signal_type;
    this.client_connection_number = client_connection_number;
    this.reference_sequence_number = reference_sequence_number;
    this.target_client_id = target_client_id;
  }
}
export const SignalMessage$SignalMessage = (client_id, content, signal_type, client_connection_number, reference_sequence_number, target_client_id) =>
  new SignalMessage(client_id,
  content,
  signal_type,
  client_connection_number,
  reference_sequence_number,
  target_client_id);
export const SignalMessage$isSignalMessage = (value) =>
  value instanceof SignalMessage;
export const SignalMessage$SignalMessage$client_id = (value) => value.client_id;
export const SignalMessage$SignalMessage$0 = (value) => value.client_id;
export const SignalMessage$SignalMessage$content = (value) => value.content;
export const SignalMessage$SignalMessage$1 = (value) => value.content;
export const SignalMessage$SignalMessage$signal_type = (value) =>
  value.signal_type;
export const SignalMessage$SignalMessage$2 = (value) => value.signal_type;
export const SignalMessage$SignalMessage$client_connection_number = (value) =>
  value.client_connection_number;
export const SignalMessage$SignalMessage$3 = (value) =>
  value.client_connection_number;
export const SignalMessage$SignalMessage$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SignalMessage$SignalMessage$4 = (value) =>
  value.reference_sequence_number;
export const SignalMessage$SignalMessage$target_client_id = (value) =>
  value.target_client_id;
export const SignalMessage$SignalMessage$5 = (value) => value.target_client_id;

export class SentSignalMessage extends $CustomType {
  constructor(content, signal_type, client_connection_number, reference_sequence_number, target_client_id) {
    super();
    this.content = content;
    this.signal_type = signal_type;
    this.client_connection_number = client_connection_number;
    this.reference_sequence_number = reference_sequence_number;
    this.target_client_id = target_client_id;
  }
}
export const SentSignalMessage$SentSignalMessage = (content, signal_type, client_connection_number, reference_sequence_number, target_client_id) =>
  new SentSignalMessage(content,
  signal_type,
  client_connection_number,
  reference_sequence_number,
  target_client_id);
export const SentSignalMessage$isSentSignalMessage = (value) =>
  value instanceof SentSignalMessage;
export const SentSignalMessage$SentSignalMessage$content = (value) =>
  value.content;
export const SentSignalMessage$SentSignalMessage$0 = (value) => value.content;
export const SentSignalMessage$SentSignalMessage$signal_type = (value) =>
  value.signal_type;
export const SentSignalMessage$SentSignalMessage$1 = (value) =>
  value.signal_type;
export const SentSignalMessage$SentSignalMessage$client_connection_number = (value) =>
  value.client_connection_number;
export const SentSignalMessage$SentSignalMessage$2 = (value) =>
  value.client_connection_number;
export const SentSignalMessage$SentSignalMessage$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SentSignalMessage$SentSignalMessage$3 = (value) =>
  value.reference_sequence_number;
export const SentSignalMessage$SentSignalMessage$target_client_id = (value) =>
  value.target_client_id;
export const SentSignalMessage$SentSignalMessage$4 = (value) =>
  value.target_client_id;

export class OpMessage extends $CustomType {
  constructor(document_id, ops) {
    super();
    this.document_id = document_id;
    this.ops = ops;
  }
}
export const OpMessage$OpMessage = (document_id, ops) =>
  new OpMessage(document_id, ops);
export const OpMessage$isOpMessage = (value) => value instanceof OpMessage;
export const OpMessage$OpMessage$document_id = (value) => value.document_id;
export const OpMessage$OpMessage$0 = (value) => value.document_id;
export const OpMessage$OpMessage$ops = (value) => value.ops;
export const OpMessage$OpMessage$1 = (value) => value.ops;

export class NoOp extends $CustomType {}
export const MessageType$NoOp$const = new NoOp();
export const MessageType$NoOp = () => MessageType$NoOp$const;
export const MessageType$isNoOp = (value) => value instanceof NoOp;

export class ClientJoin extends $CustomType {}
export const MessageType$ClientJoin$const = new ClientJoin();
export const MessageType$ClientJoin = () => MessageType$ClientJoin$const;
export const MessageType$isClientJoin = (value) => value instanceof ClientJoin;

export class ClientLeave extends $CustomType {}
export const MessageType$ClientLeave$const = new ClientLeave();
export const MessageType$ClientLeave = () => MessageType$ClientLeave$const;
export const MessageType$isClientLeave = (value) =>
  value instanceof ClientLeave;

export class Propose extends $CustomType {}
export const MessageType$Propose$const = new Propose();
export const MessageType$Propose = () => MessageType$Propose$const;
export const MessageType$isPropose = (value) => value instanceof Propose;

export class Reject extends $CustomType {}
export const MessageType$Reject$const = new Reject();
export const MessageType$Reject = () => MessageType$Reject$const;
export const MessageType$isReject = (value) => value instanceof Reject;

export class Accept extends $CustomType {}
export const MessageType$Accept$const = new Accept();
export const MessageType$Accept = () => MessageType$Accept$const;
export const MessageType$isAccept = (value) => value instanceof Accept;

export class Summarize extends $CustomType {}
export const MessageType$Summarize$const = new Summarize();
export const MessageType$Summarize = () => MessageType$Summarize$const;
export const MessageType$isSummarize = (value) => value instanceof Summarize;

export class SummaryAck extends $CustomType {}
export const MessageType$SummaryAck$const = new SummaryAck();
export const MessageType$SummaryAck = () => MessageType$SummaryAck$const;
export const MessageType$isSummaryAck = (value) => value instanceof SummaryAck;

export class SummaryNack extends $CustomType {}
export const MessageType$SummaryNack$const = new SummaryNack();
export const MessageType$SummaryNack = () => MessageType$SummaryNack$const;
export const MessageType$isSummaryNack = (value) =>
  value instanceof SummaryNack;

export class Operation extends $CustomType {}
export const MessageType$Operation$const = new Operation();
export const MessageType$Operation = () => MessageType$Operation$const;
export const MessageType$isOperation = (value) => value instanceof Operation;

export class NoClient extends $CustomType {}
export const MessageType$NoClient$const = new NoClient();
export const MessageType$NoClient = () => MessageType$NoClient$const;
export const MessageType$isNoClient = (value) => value instanceof NoClient;

export class RoundTrip extends $CustomType {}
export const MessageType$RoundTrip$const = new RoundTrip();
export const MessageType$RoundTrip = () => MessageType$RoundTrip$const;
export const MessageType$isRoundTrip = (value) => value instanceof RoundTrip;

export class Control extends $CustomType {}
export const MessageType$Control$const = new Control();
export const MessageType$Control = () => MessageType$Control$const;
export const MessageType$isControl = (value) => value instanceof Control;

/**
 * Convert message type to wire format string
 */
export function message_type_to_string(mt) {
  if (mt instanceof NoOp) {
    return "noop";
  } else if (mt instanceof ClientJoin) {
    return "join";
  } else if (mt instanceof ClientLeave) {
    return "leave";
  } else if (mt instanceof Propose) {
    return "propose";
  } else if (mt instanceof Reject) {
    return "reject";
  } else if (mt instanceof Accept) {
    return "accept";
  } else if (mt instanceof Summarize) {
    return "summarize";
  } else if (mt instanceof SummaryAck) {
    return "summaryAck";
  } else if (mt instanceof SummaryNack) {
    return "summaryNack";
  } else if (mt instanceof Operation) {
    return "op";
  } else if (mt instanceof NoClient) {
    return "noClient";
  } else if (mt instanceof RoundTrip) {
    return "tripComplete";
  } else {
    return "control";
  }
}

/**
 * Parse message type from wire format string
 */
export function message_type_from_string(s) {
  if (s === "noop") {
    return new Ok(MessageType$NoOp$const);
  } else if (s === "join") {
    return new Ok(MessageType$ClientJoin$const);
  } else if (s === "leave") {
    return new Ok(MessageType$ClientLeave$const);
  } else if (s === "propose") {
    return new Ok(MessageType$Propose$const);
  } else if (s === "reject") {
    return new Ok(MessageType$Reject$const);
  } else if (s === "accept") {
    return new Ok(MessageType$Accept$const);
  } else if (s === "summarize") {
    return new Ok(MessageType$Summarize$const);
  } else if (s === "summaryAck") {
    return new Ok(MessageType$SummaryAck$const);
  } else if (s === "summaryNack") {
    return new Ok(MessageType$SummaryNack$const);
  } else if (s === "op") {
    return new Ok(MessageType$Operation$const);
  } else if (s === "noClient") {
    return new Ok(MessageType$NoClient$const);
  } else if (s === "tripComplete") {
    return new Ok(MessageType$RoundTrip$const);
  } else if (s === "control") {
    return new Ok(MessageType$Control$const);
  } else {
    return new Error(undefined);
  }
}

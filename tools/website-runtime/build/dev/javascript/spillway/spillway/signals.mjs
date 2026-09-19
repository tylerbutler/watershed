/// <reference types="./signals.d.mts" />
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import { Ok, CustomType as $CustomType } from "../gleam.mjs";
import * as $types from "../spillway/types.mjs";

/**
 * Client joined the session
 */
export class ClientJoinSignal extends $CustomType {}
export const SystemSignalType$ClientJoinSignal$const = new ClientJoinSignal();
export const SystemSignalType$ClientJoinSignal = () =>
  SystemSignalType$ClientJoinSignal$const;
export const SystemSignalType$isClientJoinSignal = (value) =>
  value instanceof ClientJoinSignal;

/**
 * Client left the session
 */
export class ClientLeaveSignal extends $CustomType {}
export const SystemSignalType$ClientLeaveSignal$const = new ClientLeaveSignal();
export const SystemSignalType$ClientLeaveSignal = () =>
  SystemSignalType$ClientLeaveSignal$const;
export const SystemSignalType$isClientLeaveSignal = (value) =>
  value instanceof ClientLeaveSignal;

export class ClientJoinContent extends $CustomType {
  constructor(client_id, client) {
    super();
    this.client_id = client_id;
    this.client = client;
  }
}
export const ClientJoinContent$ClientJoinContent = (client_id, client) =>
  new ClientJoinContent(client_id, client);
export const ClientJoinContent$isClientJoinContent = (value) =>
  value instanceof ClientJoinContent;
export const ClientJoinContent$ClientJoinContent$client_id = (value) =>
  value.client_id;
export const ClientJoinContent$ClientJoinContent$0 = (value) => value.client_id;
export const ClientJoinContent$ClientJoinContent$client = (value) =>
  value.client;
export const ClientJoinContent$ClientJoinContent$1 = (value) => value.client;

export class ClientLeaveContent extends $CustomType {
  constructor(client_id) {
    super();
    this.client_id = client_id;
  }
}
export const ClientLeaveContent$ClientLeaveContent = (client_id) =>
  new ClientLeaveContent(client_id);
export const ClientLeaveContent$isClientLeaveContent = (value) =>
  value instanceof ClientLeaveContent;
export const ClientLeaveContent$ClientLeaveContent$client_id = (value) =>
  value.client_id;
export const ClientLeaveContent$ClientLeaveContent$0 = (value) =>
  value.client_id;

export class JoinSignal extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const SystemSignal$JoinSignal = ($0) => new JoinSignal($0);
export const SystemSignal$isJoinSignal = (value) => value instanceof JoinSignal;
export const SystemSignal$JoinSignal$0 = (value) => value[0];

export class LeaveSignal extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const SystemSignal$LeaveSignal = ($0) => new LeaveSignal($0);
export const SystemSignal$isLeaveSignal = (value) =>
  value instanceof LeaveSignal;
export const SystemSignal$LeaveSignal$0 = (value) => value[0];

/**
 * Broadcast to all clients
 */
export class BroadcastAddress extends $CustomType {}
export const SignalAddress$BroadcastAddress$const = new BroadcastAddress();
export const SignalAddress$BroadcastAddress = () =>
  SignalAddress$BroadcastAddress$const;
export const SignalAddress$isBroadcastAddress = (value) =>
  value instanceof BroadcastAddress;

/**
 * Target specific container (path-based)
 */
export class ContainerAddress extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const SignalAddress$ContainerAddress = ($0) => new ContainerAddress($0);
export const SignalAddress$isContainerAddress = (value) =>
  value instanceof ContainerAddress;
export const SignalAddress$ContainerAddress$0 = (value) => value[0];

export class SignalV1Envelope extends $CustomType {
  constructor(address, contents, client_broadcast_signal_sequence_number) {
    super();
    this.address = address;
    this.contents = contents;
    this.client_broadcast_signal_sequence_number = client_broadcast_signal_sequence_number;
  }
}
export const SignalV1Envelope$SignalV1Envelope = (address, contents, client_broadcast_signal_sequence_number) =>
  new SignalV1Envelope(address,
  contents,
  client_broadcast_signal_sequence_number);
export const SignalV1Envelope$isSignalV1Envelope = (value) =>
  value instanceof SignalV1Envelope;
export const SignalV1Envelope$SignalV1Envelope$address = (value) =>
  value.address;
export const SignalV1Envelope$SignalV1Envelope$0 = (value) => value.address;
export const SignalV1Envelope$SignalV1Envelope$contents = (value) =>
  value.contents;
export const SignalV1Envelope$SignalV1Envelope$1 = (value) => value.contents;
export const SignalV1Envelope$SignalV1Envelope$client_broadcast_signal_sequence_number = (value) =>
  value.client_broadcast_signal_sequence_number;
export const SignalV1Envelope$SignalV1Envelope$2 = (value) =>
  value.client_broadcast_signal_sequence_number;

export class SignalV1Contents extends $CustomType {
  constructor(signal_type, content) {
    super();
    this.signal_type = signal_type;
    this.content = content;
  }
}
export const SignalV1Contents$SignalV1Contents = (signal_type, content) =>
  new SignalV1Contents(signal_type, content);
export const SignalV1Contents$isSignalV1Contents = (value) =>
  value instanceof SignalV1Contents;
export const SignalV1Contents$SignalV1Contents$signal_type = (value) =>
  value.signal_type;
export const SignalV1Contents$SignalV1Contents$0 = (value) => value.signal_type;
export const SignalV1Contents$SignalV1Contents$content = (value) =>
  value.content;
export const SignalV1Contents$SignalV1Contents$1 = (value) => value.content;

export class NormalizedSignal extends $CustomType {
  constructor(content, signal_type, client_connection_number, reference_sequence_number, target_client_id, targeted_clients, ignored_clients) {
    super();
    this.content = content;
    this.signal_type = signal_type;
    this.client_connection_number = client_connection_number;
    this.reference_sequence_number = reference_sequence_number;
    this.target_client_id = target_client_id;
    this.targeted_clients = targeted_clients;
    this.ignored_clients = ignored_clients;
  }
}
export const NormalizedSignal$NormalizedSignal = (content, signal_type, client_connection_number, reference_sequence_number, target_client_id, targeted_clients, ignored_clients) =>
  new NormalizedSignal(content,
  signal_type,
  client_connection_number,
  reference_sequence_number,
  target_client_id,
  targeted_clients,
  ignored_clients);
export const NormalizedSignal$isNormalizedSignal = (value) =>
  value instanceof NormalizedSignal;
export const NormalizedSignal$NormalizedSignal$content = (value) =>
  value.content;
export const NormalizedSignal$NormalizedSignal$0 = (value) => value.content;
export const NormalizedSignal$NormalizedSignal$signal_type = (value) =>
  value.signal_type;
export const NormalizedSignal$NormalizedSignal$1 = (value) => value.signal_type;
export const NormalizedSignal$NormalizedSignal$client_connection_number = (value) =>
  value.client_connection_number;
export const NormalizedSignal$NormalizedSignal$2 = (value) =>
  value.client_connection_number;
export const NormalizedSignal$NormalizedSignal$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const NormalizedSignal$NormalizedSignal$3 = (value) =>
  value.reference_sequence_number;
export const NormalizedSignal$NormalizedSignal$target_client_id = (value) =>
  value.target_client_id;
export const NormalizedSignal$NormalizedSignal$4 = (value) =>
  value.target_client_id;
export const NormalizedSignal$NormalizedSignal$targeted_clients = (value) =>
  value.targeted_clients;
export const NormalizedSignal$NormalizedSignal$5 = (value) =>
  value.targeted_clients;
export const NormalizedSignal$NormalizedSignal$ignored_clients = (value) =>
  value.ignored_clients;
export const NormalizedSignal$NormalizedSignal$6 = (value) =>
  value.ignored_clients;

export class SignalV2 extends $CustomType {
  constructor(content, signal_type, client_connection_number, reference_sequence_number, target_client_id) {
    super();
    this.content = content;
    this.signal_type = signal_type;
    this.client_connection_number = client_connection_number;
    this.reference_sequence_number = reference_sequence_number;
    this.target_client_id = target_client_id;
  }
}
export const SignalV2$SignalV2 = (content, signal_type, client_connection_number, reference_sequence_number, target_client_id) =>
  new SignalV2(content,
  signal_type,
  client_connection_number,
  reference_sequence_number,
  target_client_id);
export const SignalV2$isSignalV2 = (value) => value instanceof SignalV2;
export const SignalV2$SignalV2$content = (value) => value.content;
export const SignalV2$SignalV2$0 = (value) => value.content;
export const SignalV2$SignalV2$signal_type = (value) => value.signal_type;
export const SignalV2$SignalV2$1 = (value) => value.signal_type;
export const SignalV2$SignalV2$client_connection_number = (value) =>
  value.client_connection_number;
export const SignalV2$SignalV2$2 = (value) => value.client_connection_number;
export const SignalV2$SignalV2$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SignalV2$SignalV2$3 = (value) => value.reference_sequence_number;
export const SignalV2$SignalV2$target_client_id = (value) =>
  value.target_client_id;
export const SignalV2$SignalV2$4 = (value) => value.target_client_id;

export class ClientBroadcastSignalEnvelope extends $CustomType {
  constructor(signal, targeted_clients, ignored_clients) {
    super();
    this.signal = signal;
    this.targeted_clients = targeted_clients;
    this.ignored_clients = ignored_clients;
  }
}
export const ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope = (signal, targeted_clients, ignored_clients) =>
  new ClientBroadcastSignalEnvelope(signal, targeted_clients, ignored_clients);
export const ClientBroadcastSignalEnvelope$isClientBroadcastSignalEnvelope = (value) =>
  value instanceof ClientBroadcastSignalEnvelope;
export const ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$signal = (value) =>
  value.signal;
export const ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$0 = (value) =>
  value.signal;
export const ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$targeted_clients = (value) =>
  value.targeted_clients;
export const ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$1 = (value) =>
  value.targeted_clients;
export const ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$ignored_clients = (value) =>
  value.ignored_clients;
export const ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$2 = (value) =>
  value.ignored_clients;

export class InvalidFormat extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const SignalParseError$InvalidFormat = ($0) => new InvalidFormat($0);
export const SignalParseError$isInvalidFormat = (value) =>
  value instanceof InvalidFormat;
export const SignalParseError$InvalidFormat$0 = (value) => value[0];

export class MissingField extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const SignalParseError$MissingField = ($0) => new MissingField($0);
export const SignalParseError$isMissingField = (value) =>
  value instanceof MissingField;
export const SignalParseError$MissingField$0 = (value) => value[0];

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

/**
 * Legacy v1 format with envelope wrapper
 */
export class V1Format extends $CustomType {}
export const SignalVersion$V1Format$const = new V1Format();
export const SignalVersion$V1Format = () => SignalVersion$V1Format$const;
export const SignalVersion$isV1Format = (value) => value instanceof V1Format;

/**
 * Current v2 format with targeting support
 */
export class V2Format extends $CustomType {}
export const SignalVersion$V2Format$const = new V2Format();
export const SignalVersion$V2Format = () => SignalVersion$V2Format$const;
export const SignalVersion$isV2Format = (value) => value instanceof V2Format;

/**
 * Unknown/invalid format
 */
export class UnknownFormat extends $CustomType {}
export const SignalVersion$UnknownFormat$const = new UnknownFormat();
export const SignalVersion$UnknownFormat = () =>
  SignalVersion$UnknownFormat$const;
export const SignalVersion$isUnknownFormat = (value) =>
  value instanceof UnknownFormat;

/**
 * Create a system signal for client join
 */
export function client_join_signal(client_id, client) {
  return new JoinSignal(new ClientJoinContent(client_id, client));
}

/**
 * Create a system signal for client leave
 */
export function client_leave_signal(client_id) {
  return new LeaveSignal(new ClientLeaveContent(client_id));
}

function decode_string_keyed_map() {
  return $decode.dict($decode.string, $decode.dynamic);
}

function decode_map(d) {
  let $ = $decode.run(d, decode_string_keyed_map());
  if ($ instanceof Ok) {
    let m = $[0];
    return m;
  } else {
    return $dict.new$();
  }
}

function decode_optional_string_list(d) {
  let $ = $decode.run(d, $decode.list($decode.string));
  if ($ instanceof Ok) {
    let l = $[0];
    return new Some(l);
  } else {
    return Option$None$const;
  }
}

function decode_optional_string(d) {
  let $ = $decode.run(d, $decode.string);
  if ($ instanceof Ok) {
    let s = $[0];
    return new Some(s);
  } else {
    return Option$None$const;
  }
}

function decode_optional_int(d) {
  let $ = $decode.run(d, $decode.int);
  if ($ instanceof Ok) {
    let n = $[0];
    return new Some(n);
  } else {
    return Option$None$const;
  }
}

/**
 * Check if a signal is targeted at a specific client
 */
export function is_targeted(signal) {
  return $option.is_some(signal.target_client_id);
}

/**
 * Check if a signal should be received by a specific client (v2 single-target)
 */
export function should_receive(signal, client_id) {
  let $ = signal.target_client_id;
  if ($ instanceof Some) {
    let target = $[0];
    return target === client_id;
  } else {
    return true;
  }
}

/**
 * Determine the target recipients for a v2 signal envelope
 * Returns the list of client IDs that should receive the signal
 */
export function get_signal_recipients(envelope, all_clients, sender_client_id) {
  let $ = envelope.targeted_clients;
  let $1 = envelope.ignored_clients;
  if ($ instanceof Some) {
    let targets = $[0];
    let _pipe = targets;
    return $list.filter(_pipe, (c) => { return c !== sender_client_id; });
  } else if ($1 instanceof Some) {
    let ignored = $1[0];
    let _pipe = all_clients;
    return $list.filter(
      _pipe,
      (c) => { return (c !== sender_client_id) && !$list.contains(ignored, c); },
    );
  } else {
    let _pipe = all_clients;
    return $list.filter(_pipe, (c) => { return c !== sender_client_id; });
  }
}

/**
 * Check if a client should receive a signal based on targeting rules
 */
export function should_client_receive_signal(
  envelope,
  client_id,
  sender_client_id
) {
  let $ = client_id === sender_client_id;
  if ($) {
    return false;
  } else {
    let $1 = envelope.targeted_clients;
    let $2 = envelope.ignored_clients;
    if ($1 instanceof Some) {
      let targets = $1[0];
      return $list.contains(targets, client_id);
    } else if ($2 instanceof Some) {
      let ignored = $2[0];
      return !$list.contains(ignored, client_id);
    } else {
      return true;
    }
  }
}

/**
 * Create a broadcast signal (v2) - sent to all clients
 */
export function broadcast(content, signal_type, connection_number, rsn) {
  return new SignalV2(
    content,
    signal_type,
    connection_number,
    rsn,
    Option$None$const,
  );
}

/**
 * Create a targeted signal (v2) - sent to a single specific client
 */
export function targeted(
  content,
  target_client_id,
  signal_type,
  connection_number,
  rsn
) {
  return new SignalV2(
    content,
    signal_type,
    connection_number,
    rsn,
    new Some(target_client_id),
  );
}

/**
 * Create a v2 signal envelope for broadcast
 */
export function broadcast_envelope(signal) {
  return new ClientBroadcastSignalEnvelope(
    signal,
    Option$None$const,
    Option$None$const,
  );
}

/**
 * Create a v2 signal envelope with targeted clients
 */
export function targeted_envelope(signal, targets) {
  return new ClientBroadcastSignalEnvelope(
    signal,
    new Some(targets),
    Option$None$const,
  );
}

/**
 * Create a v2 signal envelope with ignored clients
 */
export function ignored_envelope(signal, ignored) {
  return new ClientBroadcastSignalEnvelope(
    signal,
    Option$None$const,
    new Some(ignored),
  );
}

/**
 * Create a signal message from a v2 signal
 */
export function signal_message_from_v2(sender_client_id, signal) {
  return new SignalMessage(
    new Some(sender_client_id),
    signal.content,
    signal.signal_type,
    signal.client_connection_number,
    signal.reference_sequence_number,
    signal.target_client_id,
  );
}

/**
 * Create a system signal message (for join/leave)
 */
export function system_signal_message(content, signal_type) {
  return new SignalMessage(
    Option$None$const,
    content,
    new Some(signal_type),
    Option$None$const,
    Option$None$const,
    Option$None$const,
  );
}

/**
 * Heuristic to detect signal format version
 * V1 signals typically have: address, contents, clientBroadcastSignalSequenceNumber
 * V2 signals typically have: content, type, clientConnectionNumber, referenceSequenceNumber
 * V2 with targeting has: targetedClients or ignoredClients
 */
export function detect_signal_version(
  has_address,
  has_targeted_clients,
  has_ignored_clients
) {
  let $ = has_targeted_clients || has_ignored_clients;
  if ($) {
    return SignalVersion$V2Format$const;
  } else if (has_address) {
    return SignalVersion$V1Format$const;
  } else {
    return SignalVersion$V2Format$const;
  }
}

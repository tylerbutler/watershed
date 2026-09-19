/// <reference types="./runtime_core.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $message from "../../spillway/spillway/message.mjs";
import * as $types from "../../spillway/spillway/types.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  remainderInt,
  isEqual,
} from "../gleam.mjs";
import * as $channel from "../watershed/channel.mjs";
import { SequencedMeta } from "../watershed/channel.mjs";
import * as $claims_kernel from "../watershed/claims_kernel.mjs";
import * as $client_id from "../watershed/client_id.mjs";
import * as $counter_kernel from "../watershed/counter_kernel.mjs";
import * as $directory_kernel from "../watershed/directory_kernel.mjs";
import * as $g_counter_kernel from "../watershed/g_counter_kernel.mjs";
import * as $g_set_kernel from "../watershed/g_set_kernel.mjs";
import * as $handle from "../watershed/handle.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";
import * as $json_ot_kernel from "../watershed/json_ot_kernel.mjs";
import * as $lww_map_kernel from "../watershed/lww_map_kernel.mjs";
import * as $lww_register_kernel from "../watershed/lww_register_kernel.mjs";
import * as $map_kernel from "../watershed/map_kernel.mjs";
import * as $mv_register_kernel from "../watershed/mv_register_kernel.mjs";
import * as $or_map_kernel from "../watershed/or_map_kernel.mjs";
import * as $or_set_kernel from "../watershed/or_set_kernel.mjs";
import * as $ordered_collection_kernel from "../watershed/ordered_collection_kernel.mjs";
import * as $pact_map_kernel from "../watershed/pact_map_kernel.mjs";
import * as $pn_counter_kernel from "../watershed/pn_counter_kernel.mjs";
import * as $register_collection_kernel from "../watershed/register_collection_kernel.mjs";
import * as $rich_text from "../watershed/rich_text.mjs";
import * as $rich_text_kernel from "../watershed/rich_text_kernel.mjs";
import * as $sequence_kernel from "../watershed/sequence_kernel.mjs";
import * as $summary_policy from "../watershed/summary_policy.mjs";
import * as $task_manager_kernel from "../watershed/task_manager_kernel.mjs";
import * as $text_kernel from "../watershed/text_kernel.mjs";
import * as $two_p_set_kernel from "../watershed/two_p_set_kernel.mjs";
import * as $wire from "../watershed/wire.mjs";
import * as $wire_op from "../watershed/wire/op.mjs";
import * as $wire_summary from "../watershed/wire/summary.mjs";
import * as $summary_blob from "../watershed/wire/summary_blob.mjs";

/**
 * The core folds historical messages at a past sequence point.
 */
export class Replaying extends $CustomType {}
export const IngestPosition$Replaying$const = new Replaying();
export const IngestPosition$Replaying = () => IngestPosition$Replaying$const;
export const IngestPosition$isReplaying = (value) => value instanceof Replaying;

/**
 * The core reads the live lane at the newest sequence point.
 */
export class Live extends $CustomType {}
export const IngestPosition$Live$const = new Live();
export const IngestPosition$Live = () => IngestPosition$Live$const;
export const IngestPosition$isLive = (value) => value instanceof Live;

export class Core extends $CustomType {
  constructor(client_id, channels, channel_order, detached, next_client_sequence_number, last_seen_sequence_number, in_flight, out_of_order, members, live_members, ingest, last_summary_sequence_number, summary_head, owed) {
    super();
    this.client_id = client_id;
    this.channels = channels;
    this.channel_order = channel_order;
    this.detached = detached;
    this.next_client_sequence_number = next_client_sequence_number;
    this.last_seen_sequence_number = last_seen_sequence_number;
    this.in_flight = in_flight;
    this.out_of_order = out_of_order;
    this.members = members;
    this.live_members = live_members;
    this.ingest = ingest;
    this.last_summary_sequence_number = last_summary_sequence_number;
    this.summary_head = summary_head;
    this.owed = owed;
  }
}
export const Core$Core = (client_id, channels, channel_order, detached, next_client_sequence_number, last_seen_sequence_number, in_flight, out_of_order, members, live_members, ingest, last_summary_sequence_number, summary_head, owed) =>
  new Core(client_id,
  channels,
  channel_order,
  detached,
  next_client_sequence_number,
  last_seen_sequence_number,
  in_flight,
  out_of_order,
  members,
  live_members,
  ingest,
  last_summary_sequence_number,
  summary_head,
  owed);
export const Core$isCore = (value) => value instanceof Core;
export const Core$Core$client_id = (value) => value.client_id;
export const Core$Core$0 = (value) => value.client_id;
export const Core$Core$channels = (value) => value.channels;
export const Core$Core$1 = (value) => value.channels;
export const Core$Core$channel_order = (value) => value.channel_order;
export const Core$Core$2 = (value) => value.channel_order;
export const Core$Core$detached = (value) => value.detached;
export const Core$Core$3 = (value) => value.detached;
export const Core$Core$next_client_sequence_number = (value) =>
  value.next_client_sequence_number;
export const Core$Core$4 = (value) => value.next_client_sequence_number;
export const Core$Core$last_seen_sequence_number = (value) =>
  value.last_seen_sequence_number;
export const Core$Core$5 = (value) => value.last_seen_sequence_number;
export const Core$Core$in_flight = (value) => value.in_flight;
export const Core$Core$6 = (value) => value.in_flight;
export const Core$Core$out_of_order = (value) => value.out_of_order;
export const Core$Core$7 = (value) => value.out_of_order;
export const Core$Core$members = (value) => value.members;
export const Core$Core$8 = (value) => value.members;
export const Core$Core$live_members = (value) => value.live_members;
export const Core$Core$9 = (value) => value.live_members;
export const Core$Core$ingest = (value) => value.ingest;
export const Core$Core$10 = (value) => value.ingest;
export const Core$Core$last_summary_sequence_number = (value) =>
  value.last_summary_sequence_number;
export const Core$Core$11 = (value) => value.last_summary_sequence_number;
export const Core$Core$summary_head = (value) => value.summary_head;
export const Core$Core$12 = (value) => value.summary_head;
export const Core$Core$owed = (value) => value.owed;
export const Core$Core$13 = (value) => value.owed;

export class InFlightOperation extends $CustomType {
  constructor(client_id, client_sequence_number, address, operation, meta) {
    super();
    this.client_id = client_id;
    this.client_sequence_number = client_sequence_number;
    this.address = address;
    this.operation = operation;
    this.meta = meta;
  }
}
export const InFlight$InFlightOperation = (client_id, client_sequence_number, address, operation, meta) =>
  new InFlightOperation(client_id,
  client_sequence_number,
  address,
  operation,
  meta);
export const InFlight$isInFlightOperation = (value) =>
  value instanceof InFlightOperation;
export const InFlight$InFlightOperation$client_id = (value) => value.client_id;
export const InFlight$InFlightOperation$0 = (value) => value.client_id;
export const InFlight$InFlightOperation$client_sequence_number = (value) =>
  value.client_sequence_number;
export const InFlight$InFlightOperation$1 = (value) =>
  value.client_sequence_number;
export const InFlight$InFlightOperation$address = (value) => value.address;
export const InFlight$InFlightOperation$2 = (value) => value.address;
export const InFlight$InFlightOperation$operation = (value) => value.operation;
export const InFlight$InFlightOperation$3 = (value) => value.operation;
export const InFlight$InFlightOperation$meta = (value) => value.meta;
export const InFlight$InFlightOperation$4 = (value) => value.meta;

export class InFlightAttach extends $CustomType {
  constructor(client_id, client_sequence_number, address, snapshot) {
    super();
    this.client_id = client_id;
    this.client_sequence_number = client_sequence_number;
    this.address = address;
    this.snapshot = snapshot;
  }
}
export const InFlight$InFlightAttach = (client_id, client_sequence_number, address, snapshot) =>
  new InFlightAttach(client_id, client_sequence_number, address, snapshot);
export const InFlight$isInFlightAttach = (value) =>
  value instanceof InFlightAttach;
export const InFlight$InFlightAttach$client_id = (value) => value.client_id;
export const InFlight$InFlightAttach$0 = (value) => value.client_id;
export const InFlight$InFlightAttach$client_sequence_number = (value) =>
  value.client_sequence_number;
export const InFlight$InFlightAttach$1 = (value) =>
  value.client_sequence_number;
export const InFlight$InFlightAttach$address = (value) => value.address;
export const InFlight$InFlightAttach$2 = (value) => value.address;
export const InFlight$InFlightAttach$snapshot = (value) => value.snapshot;
export const InFlight$InFlightAttach$3 = (value) => value.snapshot;

export const InFlight$address = (value) => value.address;
export const InFlight$client_id = (value) => value.client_id;
export const InFlight$client_sequence_number = (value) =>
  value.client_sequence_number;

export class AckMismatch extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const CoreError$AckMismatch = (detail) => new AckMismatch(detail);
export const CoreError$isAckMismatch = (value) => value instanceof AckMismatch;
export const CoreError$AckMismatch$detail = (value) => value.detail;
export const CoreError$AckMismatch$0 = (value) => value.detail;

export class BadOperationContents extends $CustomType {
  constructor(sequence_number) {
    super();
    this.sequence_number = sequence_number;
  }
}
export const CoreError$BadOperationContents = (sequence_number) =>
  new BadOperationContents(sequence_number);
export const CoreError$isBadOperationContents = (value) =>
  value instanceof BadOperationContents;
export const CoreError$BadOperationContents$sequence_number = (value) =>
  value.sequence_number;
export const CoreError$BadOperationContents$0 = (value) =>
  value.sequence_number;

export class HistoryGap extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const CoreError$HistoryGap = (detail) => new HistoryGap(detail);
export const CoreError$isHistoryGap = (value) => value instanceof HistoryGap;
export const CoreError$HistoryGap$detail = (value) => value.detail;
export const CoreError$HistoryGap$0 = (value) => value.detail;

export class UnknownChannel extends $CustomType {
  constructor(address, sequence_number) {
    super();
    this.address = address;
    this.sequence_number = sequence_number;
  }
}
export const CoreError$UnknownChannel = (address, sequence_number) =>
  new UnknownChannel(address, sequence_number);
export const CoreError$isUnknownChannel = (value) =>
  value instanceof UnknownChannel;
export const CoreError$UnknownChannel$address = (value) => value.address;
export const CoreError$UnknownChannel$0 = (value) => value.address;
export const CoreError$UnknownChannel$sequence_number = (value) =>
  value.sequence_number;
export const CoreError$UnknownChannel$1 = (value) => value.sequence_number;

export class DuplicateAttach extends $CustomType {
  constructor(address, sequence_number) {
    super();
    this.address = address;
    this.sequence_number = sequence_number;
  }
}
export const CoreError$DuplicateAttach = (address, sequence_number) =>
  new DuplicateAttach(address, sequence_number);
export const CoreError$isDuplicateAttach = (value) =>
  value instanceof DuplicateAttach;
export const CoreError$DuplicateAttach$address = (value) => value.address;
export const CoreError$DuplicateAttach$0 = (value) => value.address;
export const CoreError$DuplicateAttach$sequence_number = (value) =>
  value.sequence_number;
export const CoreError$DuplicateAttach$1 = (value) => value.sequence_number;

/**
 * A local edit used an operation of one channel type on a channel of
 * another type, for example a `set` on a counter. This is incorrect use of
 * the API, and the caller can retry. The document is not corrupt.
 */
export class WrongChannelType extends $CustomType {
  constructor(address, expected, actual) {
    super();
    this.address = address;
    this.expected = expected;
    this.actual = actual;
  }
}
export const CoreError$WrongChannelType = (address, expected, actual) =>
  new WrongChannelType(address, expected, actual);
export const CoreError$isWrongChannelType = (value) =>
  value instanceof WrongChannelType;
export const CoreError$WrongChannelType$address = (value) => value.address;
export const CoreError$WrongChannelType$0 = (value) => value.address;
export const CoreError$WrongChannelType$expected = (value) => value.expected;
export const CoreError$WrongChannelType$1 = (value) => value.expected;
export const CoreError$WrongChannelType$actual = (value) => value.actual;
export const CoreError$WrongChannelType$2 = (value) => value.actual;

export class OrMapModeMismatch extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$OrMapModeMismatch = (address, detail) =>
  new OrMapModeMismatch(address, detail);
export const CoreError$isOrMapModeMismatch = (value) =>
  value instanceof OrMapModeMismatch;
export const CoreError$OrMapModeMismatch$address = (value) => value.address;
export const CoreError$OrMapModeMismatch$0 = (value) => value.address;
export const CoreError$OrMapModeMismatch$detail = (value) => value.detail;
export const CoreError$OrMapModeMismatch$1 = (value) => value.detail;

export class OrMapOperationFailed extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$OrMapOperationFailed = (address, detail) =>
  new OrMapOperationFailed(address, detail);
export const CoreError$isOrMapOperationFailed = (value) =>
  value instanceof OrMapOperationFailed;
export const CoreError$OrMapOperationFailed$address = (value) => value.address;
export const CoreError$OrMapOperationFailed$0 = (value) => value.address;
export const CoreError$OrMapOperationFailed$detail = (value) => value.detail;
export const CoreError$OrMapOperationFailed$1 = (value) => value.detail;

export class TaskNotAssigned extends $CustomType {
  constructor(address, task_id) {
    super();
    this.address = address;
    this.task_id = task_id;
  }
}
export const CoreError$TaskNotAssigned = (address, task_id) =>
  new TaskNotAssigned(address, task_id);
export const CoreError$isTaskNotAssigned = (value) =>
  value instanceof TaskNotAssigned;
export const CoreError$TaskNotAssigned$address = (value) => value.address;
export const CoreError$TaskNotAssigned$0 = (value) => value.address;
export const CoreError$TaskNotAssigned$task_id = (value) => value.task_id;
export const CoreError$TaskNotAssigned$1 = (value) => value.task_id;

/**
 * The kernel refused a directory edit, because the path is unknown or the
 * subdirectory name is invalid. This is incorrect use of the API, and the
 * caller can retry. The document is not corrupt.
 */
export class DirectoryOperationFailed extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$DirectoryOperationFailed = (address, detail) =>
  new DirectoryOperationFailed(address, detail);
export const CoreError$isDirectoryOperationFailed = (value) =>
  value instanceof DirectoryOperationFailed;
export const CoreError$DirectoryOperationFailed$address = (value) =>
  value.address;
export const CoreError$DirectoryOperationFailed$0 = (value) => value.address;
export const CoreError$DirectoryOperationFailed$detail = (value) =>
  value.detail;
export const CoreError$DirectoryOperationFailed$1 = (value) => value.detail;

export class SequenceOperationFailed extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$SequenceOperationFailed = (address, detail) =>
  new SequenceOperationFailed(address, detail);
export const CoreError$isSequenceOperationFailed = (value) =>
  value instanceof SequenceOperationFailed;
export const CoreError$SequenceOperationFailed$address = (value) =>
  value.address;
export const CoreError$SequenceOperationFailed$0 = (value) => value.address;
export const CoreError$SequenceOperationFailed$detail = (value) => value.detail;
export const CoreError$SequenceOperationFailed$1 = (value) => value.detail;

/**
 * The kernel refused a local grow-only counter edit, because the amount is
 * negative. This is incorrect use of the API, and the caller can retry. The
 * document is not corrupt, and no operation goes out.
 */
export class GCounterOperationFailed extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$GCounterOperationFailed = (address, detail) =>
  new GCounterOperationFailed(address, detail);
export const CoreError$isGCounterOperationFailed = (value) =>
  value instanceof GCounterOperationFailed;
export const CoreError$GCounterOperationFailed$address = (value) =>
  value.address;
export const CoreError$GCounterOperationFailed$0 = (value) => value.address;
export const CoreError$GCounterOperationFailed$detail = (value) => value.detail;
export const CoreError$GCounterOperationFailed$1 = (value) => value.detail;

export class LwwRegisterOperationFailed extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$LwwRegisterOperationFailed = (address, detail) =>
  new LwwRegisterOperationFailed(address, detail);
export const CoreError$isLwwRegisterOperationFailed = (value) =>
  value instanceof LwwRegisterOperationFailed;
export const CoreError$LwwRegisterOperationFailed$address = (value) =>
  value.address;
export const CoreError$LwwRegisterOperationFailed$0 = (value) => value.address;
export const CoreError$LwwRegisterOperationFailed$detail = (value) =>
  value.detail;
export const CoreError$LwwRegisterOperationFailed$1 = (value) => value.detail;

export class LwwMapOperationFailed extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$LwwMapOperationFailed = (address, detail) =>
  new LwwMapOperationFailed(address, detail);
export const CoreError$isLwwMapOperationFailed = (value) =>
  value instanceof LwwMapOperationFailed;
export const CoreError$LwwMapOperationFailed$address = (value) => value.address;
export const CoreError$LwwMapOperationFailed$0 = (value) => value.address;
export const CoreError$LwwMapOperationFailed$detail = (value) => value.detail;
export const CoreError$LwwMapOperationFailed$1 = (value) => value.detail;

/**
 * The kernel refused a local text edit, because the insert index is out of
 * bounds, or the delete range or replace range is invalid. This is
 * incorrect use of the API, and the caller can retry. The document is not
 * corrupt. A valid empty edit never reaches this path. The kernel reports
 * such an edit as a success that changes nothing. See `text_kernel`.
 */
export class TextOperationFailed extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$TextOperationFailed = (address, detail) =>
  new TextOperationFailed(address, detail);
export const CoreError$isTextOperationFailed = (value) =>
  value instanceof TextOperationFailed;
export const CoreError$TextOperationFailed$address = (value) => value.address;
export const CoreError$TextOperationFailed$0 = (value) => value.address;
export const CoreError$TextOperationFailed$detail = (value) => value.detail;
export const CoreError$TextOperationFailed$1 = (value) => value.detail;

/**
 * A channel snapshot in the summary does not describe a channel that this
 * client can build. The document cannot start from that summary.
 */
export class BadSummaryChannel extends $CustomType {
  constructor(address, detail) {
    super();
    this.address = address;
    this.detail = detail;
  }
}
export const CoreError$BadSummaryChannel = (address, detail) =>
  new BadSummaryChannel(address, detail);
export const CoreError$isBadSummaryChannel = (value) =>
  value instanceof BadSummaryChannel;
export const CoreError$BadSummaryChannel$address = (value) => value.address;
export const CoreError$BadSummaryChannel$0 = (value) => value.address;
export const CoreError$BadSummaryChannel$detail = (value) => value.detail;
export const CoreError$BadSummaryChannel$1 = (value) => value.detail;

export class Complete extends $CustomType {
  constructor(core) {
    super();
    this.core = core;
  }
}
export const Bootstrapped$Complete = (core) => new Complete(core);
export const Bootstrapped$isComplete = (value) => value instanceof Complete;
export const Bootstrapped$Complete$core = (value) => value.core;
export const Bootstrapped$Complete$0 = (value) => value.core;

export class MissingPrefix extends $CustomType {
  constructor(core, checkpoint, from, to) {
    super();
    this.core = core;
    this.checkpoint = checkpoint;
    this.from = from;
    this.to = to;
  }
}
export const Bootstrapped$MissingPrefix = (core, checkpoint, from, to) =>
  new MissingPrefix(core, checkpoint, from, to);
export const Bootstrapped$isMissingPrefix = (value) =>
  value instanceof MissingPrefix;
export const Bootstrapped$MissingPrefix$core = (value) => value.core;
export const Bootstrapped$MissingPrefix$0 = (value) => value.core;
export const Bootstrapped$MissingPrefix$checkpoint = (value) =>
  value.checkpoint;
export const Bootstrapped$MissingPrefix$1 = (value) => value.checkpoint;
export const Bootstrapped$MissingPrefix$from = (value) => value.from;
export const Bootstrapped$MissingPrefix$2 = (value) => value.from;
export const Bootstrapped$MissingPrefix$to = (value) => value.to;
export const Bootstrapped$MissingPrefix$3 = (value) => value.to;

export const Bootstrapped$core = (value) => value.core;

export class SummaryProposalSequenced extends $CustomType {
  constructor(client_id, client_sequence_number, sequence_number) {
    super();
    this.client_id = client_id;
    this.client_sequence_number = client_sequence_number;
    this.sequence_number = sequence_number;
  }
}
export const SummaryEvent$SummaryProposalSequenced = (client_id, client_sequence_number, sequence_number) =>
  new SummaryProposalSequenced(client_id,
  client_sequence_number,
  sequence_number);
export const SummaryEvent$isSummaryProposalSequenced = (value) =>
  value instanceof SummaryProposalSequenced;
export const SummaryEvent$SummaryProposalSequenced$client_id = (value) =>
  value.client_id;
export const SummaryEvent$SummaryProposalSequenced$0 = (value) =>
  value.client_id;
export const SummaryEvent$SummaryProposalSequenced$client_sequence_number = (value) =>
  value.client_sequence_number;
export const SummaryEvent$SummaryProposalSequenced$1 = (value) =>
  value.client_sequence_number;
export const SummaryEvent$SummaryProposalSequenced$sequence_number = (value) =>
  value.sequence_number;
export const SummaryEvent$SummaryProposalSequenced$2 = (value) =>
  value.sequence_number;

export class SummaryPublished extends $CustomType {
  constructor(proposal_sequence_number, version_id) {
    super();
    this.proposal_sequence_number = proposal_sequence_number;
    this.version_id = version_id;
  }
}
export const SummaryEvent$SummaryPublished = (proposal_sequence_number, version_id) =>
  new SummaryPublished(proposal_sequence_number, version_id);
export const SummaryEvent$isSummaryPublished = (value) =>
  value instanceof SummaryPublished;
export const SummaryEvent$SummaryPublished$proposal_sequence_number = (value) =>
  value.proposal_sequence_number;
export const SummaryEvent$SummaryPublished$0 = (value) =>
  value.proposal_sequence_number;
export const SummaryEvent$SummaryPublished$version_id = (value) =>
  value.version_id;
export const SummaryEvent$SummaryPublished$1 = (value) => value.version_id;

export class SummaryRejected extends $CustomType {
  constructor(proposal_sequence_number, reason) {
    super();
    this.proposal_sequence_number = proposal_sequence_number;
    this.reason = reason;
  }
}
export const SummaryEvent$SummaryRejected = (proposal_sequence_number, reason) =>
  new SummaryRejected(proposal_sequence_number, reason);
export const SummaryEvent$isSummaryRejected = (value) =>
  value instanceof SummaryRejected;
export const SummaryEvent$SummaryRejected$proposal_sequence_number = (value) =>
  value.proposal_sequence_number;
export const SummaryEvent$SummaryRejected$0 = (value) =>
  value.proposal_sequence_number;
export const SummaryEvent$SummaryRejected$reason = (value) => value.reason;
export const SummaryEvent$SummaryRejected$1 = (value) => value.reason;

export class Ingested extends $CustomType {
  constructor(events, resolutions, summary_events, request_operations_from, outbound) {
    super();
    this.events = events;
    this.resolutions = resolutions;
    this.summary_events = summary_events;
    this.request_operations_from = request_operations_from;
    this.outbound = outbound;
  }
}
export const Ingested$Ingested = (events, resolutions, summary_events, request_operations_from, outbound) =>
  new Ingested(events,
  resolutions,
  summary_events,
  request_operations_from,
  outbound);
export const Ingested$isIngested = (value) => value instanceof Ingested;
export const Ingested$Ingested$events = (value) => value.events;
export const Ingested$Ingested$0 = (value) => value.events;
export const Ingested$Ingested$resolutions = (value) => value.resolutions;
export const Ingested$Ingested$1 = (value) => value.resolutions;
export const Ingested$Ingested$summary_events = (value) => value.summary_events;
export const Ingested$Ingested$2 = (value) => value.summary_events;
export const Ingested$Ingested$request_operations_from = (value) =>
  value.request_operations_from;
export const Ingested$Ingested$3 = (value) => value.request_operations_from;
export const Ingested$Ingested$outbound = (value) => value.outbound;
export const Ingested$Ingested$4 = (value) => value.outbound;

export class Summary extends $CustomType {
  constructor(sequence_number, channels, members) {
    super();
    this.sequence_number = sequence_number;
    this.channels = channels;
    this.members = members;
  }
}
export const Summary$Summary = (sequence_number, channels, members) =>
  new Summary(sequence_number, channels, members);
export const Summary$isSummary = (value) => value instanceof Summary;
export const Summary$Summary$sequence_number = (value) => value.sequence_number;
export const Summary$Summary$0 = (value) => value.sequence_number;
export const Summary$Summary$channels = (value) => value.channels;
export const Summary$Summary$1 = (value) => value.channels;
export const Summary$Summary$members = (value) => value.members;
export const Summary$Summary$2 = (value) => value.members;

export class ClaimPending extends $CustomType {
  constructor(core, outbound, immediate_outcome) {
    super();
    this.core = core;
    this.outbound = outbound;
    this.immediate_outcome = immediate_outcome;
  }
}
export const ClaimSubmitResult$ClaimPending = (core, outbound, immediate_outcome) =>
  new ClaimPending(core, outbound, immediate_outcome);
export const ClaimSubmitResult$isClaimPending = (value) =>
  value instanceof ClaimPending;
export const ClaimSubmitResult$ClaimPending$core = (value) => value.core;
export const ClaimSubmitResult$ClaimPending$0 = (value) => value.core;
export const ClaimSubmitResult$ClaimPending$outbound = (value) =>
  value.outbound;
export const ClaimSubmitResult$ClaimPending$1 = (value) => value.outbound;
export const ClaimSubmitResult$ClaimPending$immediate_outcome = (value) =>
  value.immediate_outcome;
export const ClaimSubmitResult$ClaimPending$2 = (value) =>
  value.immediate_outcome;

export class ClaimAlreadyClaimed extends $CustomType {
  constructor(current_value) {
    super();
    this.current_value = current_value;
  }
}
export const ClaimSubmitResult$ClaimAlreadyClaimed = (current_value) =>
  new ClaimAlreadyClaimed(current_value);
export const ClaimSubmitResult$isClaimAlreadyClaimed = (value) =>
  value instanceof ClaimAlreadyClaimed;
export const ClaimSubmitResult$ClaimAlreadyClaimed$current_value = (value) =>
  value.current_value;
export const ClaimSubmitResult$ClaimAlreadyClaimed$0 = (value) =>
  value.current_value;

export class ClaimAlreadyPendingLocally extends $CustomType {}
export const ClaimSubmitResult$ClaimAlreadyPendingLocally$const =
  new ClaimAlreadyPendingLocally();
export const ClaimSubmitResult$ClaimAlreadyPendingLocally = () =>
  ClaimSubmitResult$ClaimAlreadyPendingLocally$const;
export const ClaimSubmitResult$isClaimAlreadyPendingLocally = (value) =>
  value instanceof ClaimAlreadyPendingLocally;

class Detached extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Attached extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

const root_address = "root";

/**
 * The bootstrap seed that a fetched summary blob describes.
 *
 * The load point comes from the blob, and from the blob *only*. This function
 * thus takes no `SummaryContext` value. The context of the server reports the
 * sequence number of the summarize operation, which the server assigned when
 * it sequenced that operation, after the writer captured and uploaded the
 * blob. Every operation that a peer got sequenced in that interval falls
 * between the two numbers. To seed from the context thus claims that the
 * seeded state is newer than it is, and no client replays the operations
 * between the two numbers. The served history starts after the number of the
 * context, it appears contiguous, and nothing reports a gap.
 *
 * To seed from the number of the blob cannot lose those operations. When the
 * two numbers agree, the result is the same. When they differ, the interval
 * appears as a missing prefix, and `resume_bootstrap` reads it from storage.
 * The context still locates the blob, because `handle` is the tree SHA. It
 * does not describe the contents of that blob.
 */
export function summary_from_blob(blob) {
  return new Summary(
    blob.sequence_number,
    $list.map(blob.channels, (ch) => { return [ch.address, ch.snapshot]; }),
    blob.members,
  );
}

/**
 * The hand-off from the replay to the live traffic.
 *
 * `Complete` is the only outcome that ends a bootstrap. `MissingPrefix` asks
 * for another page, and it returns through `resume_bootstrap`. This function
 * is thus the one place that can take the roster of the handshake, exactly one
 * time, whatever number of pages the history needed.
 *
 * The reconstruction before this point is exact in both routes. From sequence
 * number zero, the `join` and `leave` messages build the roster from nothing.
 * From a checkpoint, they advance the roster that the blob recorded. This
 * function is thus not a correction. It is the hand-off itself. A replay
 * reasons about the room at each historical sequence point, and after this
 * point only the current sequence point matters.
 * 
 * @ignore
 */
function settle_bootstrap(core, checkpoint) {
  let $ = core.out_of_order;
  if ($ instanceof $Empty) {
    return new Complete(
      new Core(
        core.client_id,
        core.channels,
        core.channel_order,
        core.detached,
        core.next_client_sequence_number,
        $int.max(core.last_seen_sequence_number, checkpoint),
        core.in_flight,
        core.out_of_order,
        core.live_members,
        core.live_members,
        core.ingest,
        core.last_summary_sequence_number,
        core.summary_head,
        core.owed,
      ),
    );
  } else {
    let head = $.head;
    return new MissingPrefix(
      core,
      checkpoint,
      core.last_seen_sequence_number,
      head.sequence_number - 1,
    );
  }
}

/**
 * Give a released operation a new CSN, record an in-flight entry so that the
 * usual ack path reclaims it, and build its outbound wire operation.
 * 
 * @ignore
 */
function stamp_outbound(core, address, operation) {
  let client_sequence_number = core.next_client_sequence_number;
  let outbound = $wire_op.outbound_channel_operation(
    address,
    client_sequence_number,
    core.last_seen_sequence_number,
    operation,
  );
  let core$1 = new Core(
    core.client_id,
    core.channels,
    core.channel_order,
    core.detached,
    client_sequence_number + 1,
    core.last_seen_sequence_number,
    $list.append(
      core.in_flight,
      toList([
        new InFlightOperation(
          core.client_id,
          client_sequence_number,
          address,
          operation,
          $channel.LocalOperationMeta$NoMeta$const,
        ),
      ]),
    ),
    core.out_of_order,
    core.members,
    core.live_members,
    core.ingest,
    core.last_summary_sequence_number,
    core.summary_head,
    core.owed,
  );
  return [core$1, outbound];
}

/**
 * Take the promoted buffer of a one-operation-in-flight kernel, for one
 * channel, and stamp the operation.
 * 
 * @ignore
 */
function drain_kernel_outbound(core, address) {
  let $ = $dict.get(core.channels, address);
  if ($ instanceof Ok) {
    let state = $[0];
    let $1 = $channel.take_outbound(state);
    let $2 = $1[1];
    if ($2 instanceof Some) {
      let state$1 = $1[0];
      let operation = $2[0];
      let core$1 = new Core(
        core.client_id,
        $dict.insert(core.channels, address, state$1),
        core.channel_order,
        core.detached,
        core.next_client_sequence_number,
        core.last_seen_sequence_number,
        core.in_flight,
        core.out_of_order,
        core.members,
        core.live_members,
        core.ingest,
        core.last_summary_sequence_number,
        core.summary_head,
        core.owed,
      );
      let $3 = stamp_outbound(core$1, address, operation);
      let core$2 = $3[0];
      let out = $3[1];
      return [core$2, toList([out])];
    } else {
      return [core, $List$Empty$const];
    }
  } else {
    return [core, $List$Empty$const];
  }
}

/**
 * Take every operation from the `owed` buffer of one channel, and stamp each
 * one.
 * 
 * @ignore
 */
function drain_owed(core, address) {
  let $ = $dict.get(core.owed, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $Empty) {
      return [core, $List$Empty$const];
    } else {
      let operations = $1;
      let core$1 = new Core(
        core.client_id,
        core.channels,
        core.channel_order,
        core.detached,
        core.next_client_sequence_number,
        core.last_seen_sequence_number,
        core.in_flight,
        core.out_of_order,
        core.members,
        core.live_members,
        core.ingest,
        core.last_summary_sequence_number,
        core.summary_head,
        $dict.delete$(core.owed, address),
      );
      return $list.fold(
        operations,
        [core$1, $List$Empty$const],
        (acc, operation) => {
          let core$2 = acc[0];
          let outs = acc[1];
          let $2 = stamp_outbound(core$2, address, operation);
          let core$3 = $2[0];
          let out = $2[1];
          return [core$3, $list.append(outs, toList([out]))];
        },
      );
    }
  } else {
    return [core, $List$Empty$const];
  }
}

/**
 * After a sequenced batch, take every follow-up operation that a channel
 * released for the actor loop to submit. The function gives each operation a
 * new CSN and an in-flight entry, so that the usual ack path reclaims it. Two
 * sources fill this list:
 *
 *   1. The `owed` buffer of each channel, which any branch of
 *      `channel.apply_remote` can fill by returning owed operations. One
 *      example is a consensus `Accept` operation.
 *   2. The buffer promotion of the one-operation-in-flight kernels, which are
 *      json0 and rich text. `channel.take_outbound` gives those operations.
 *
 * The function returns the stamped outbound operations in channel order. In
 * each channel, the owed operations come before the operations from the kernel
 * buffer.
 * 
 * @ignore
 */
function collect_released_operations(core) {
  return $list.fold(
    core.channel_order,
    [core, $List$Empty$const],
    (acc, address) => {
      let core$1 = acc[0];
      let outs = acc[1];
      let $ = drain_owed(core$1, address);
      let core$2 = $[0];
      let owed_outs = $[1];
      let $1 = drain_kernel_outbound(core$2, address);
      let core$3 = $1[0];
      let kernel_outs = $1[1];
      return [core$3, $list.append(outs, $list.append(owed_outs, kernel_outs))];
    },
  );
}

function apply_summary_response(core, msg) {
  let $ = $wire_summary.decode_message(msg.message_type, msg.contents);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $wire_summary.Ack) {
      let proposal_sequence_number = $1.proposal_sequence_number;
      let version_id = $1.version_id;
      let _block;
      let $2 = proposal_sequence_number >= core.last_summary_sequence_number;
      if ($2) {
        _block = new Core(
          core.client_id,
          core.channels,
          core.channel_order,
          core.detached,
          core.next_client_sequence_number,
          core.last_seen_sequence_number,
          core.in_flight,
          core.out_of_order,
          core.members,
          core.live_members,
          core.ingest,
          proposal_sequence_number,
          new Some(version_id),
          core.owed,
        );
      } else {
        _block = core;
      }
      let core$1 = _block;
      return new Ok(
        [
          core$1,
          $List$Empty$const,
          $List$Empty$const,
          toList([new SummaryPublished(proposal_sequence_number, version_id)]),
        ],
      );
    } else {
      let proposal_sequence_number = $1.proposal_sequence_number;
      let reason = $1.reason;
      return new Ok(
        [
          core,
          $List$Empty$const,
          $List$Empty$const,
          toList([new SummaryRejected(proposal_sequence_number, reason)]),
        ],
      );
    }
  } else {
    return new Error(new BadOperationContents(msg.sequence_number));
  }
}

function tag_events(address, events) {
  return $list.map(events, (event) => { return [address, event]; });
}

function put_attached_channel(core, address, state) {
  return new Core(
    core.client_id,
    $dict.insert(core.channels, address, state),
    core.channel_order,
    core.detached,
    core.next_client_sequence_number,
    core.last_seen_sequence_number,
    core.in_flight,
    core.out_of_order,
    core.members,
    core.live_members,
    core.ingest,
    core.last_summary_sequence_number,
    core.summary_head,
    core.owed,
  );
}

function tag_map_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.MapEvent(event)]; },
  );
}

function stamp_attached(core, address, state, events, operation, meta) {
  let client_sequence_number = core.next_client_sequence_number;
  let outbound = $wire_op.outbound_channel_operation(
    address,
    client_sequence_number,
    core.last_seen_sequence_number,
    operation,
  );
  let core$1 = new Core(
    core.client_id,
    $dict.insert(core.channels, address, state),
    core.channel_order,
    core.detached,
    client_sequence_number + 1,
    core.last_seen_sequence_number,
    $list.append(
      core.in_flight,
      toList([
        new InFlightOperation(
          core.client_id,
          client_sequence_number,
          address,
          operation,
          meta,
        ),
      ]),
    ),
    core.out_of_order,
    core.members,
    core.live_members,
    core.ingest,
    core.last_summary_sequence_number,
    core.summary_head,
    core.owed,
  );
  return [core$1, events, toList([outbound])];
}

function locate_channel(core, address) {
  let $ = $dict.get(core.detached, address);
  if ($ instanceof Ok) {
    let state = $[0];
    return new Ok(new Detached(state));
  } else {
    let $1 = $dict.get(core.channels, address);
    if ($1 instanceof Ok) {
      let state = $1[0];
      return new Ok(new Attached(state));
    } else {
      return new Error(
        new UnknownChannel(address, core.last_seen_sequence_number),
      );
    }
  }
}

function locate_map(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.MapState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$MapChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.MapState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$MapChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

function submit_attaches(core, addresses) {
  return $list.fold(
    addresses,
    [core, $List$Empty$const],
    (acc, address) => {
      let core$1 = acc[0];
      let outbound = acc[1];
      let $ = $dict.get(core$1.detached, address);
      if ($ instanceof Ok) {
        let state = $[0];
        let snapshot = $channel.attach_snapshot(state);
        let client_sequence_number = core$1.next_client_sequence_number;
        let outbound_operation = $wire_op.outbound_attach_operation(
          address,
          client_sequence_number,
          core$1.last_seen_sequence_number,
          snapshot,
        );
        let core$2 = new Core(
          core$1.client_id,
          $dict.insert(
            core$1.channels,
            address,
            $channel.attach_state(state, core$1.client_id),
          ),
          $list.unique($list.append(core$1.channel_order, toList([address]))),
          $dict.delete$(core$1.detached, address),
          client_sequence_number + 1,
          core$1.last_seen_sequence_number,
          $list.append(
            core$1.in_flight,
            toList([
              new InFlightAttach(
                core$1.client_id,
                client_sequence_number,
                address,
                snapshot,
              ),
            ]),
          ),
          core$1.out_of_order,
          core$1.members,
          core$1.live_members,
          core$1.ingest,
          core$1.last_summary_sequence_number,
          core$1.summary_head,
          core$1.owed,
        );
        return [core$2, $list.append(outbound, toList([outbound_operation]))];
      } else {
        return [core$1, outbound];
      }
    },
  );
}

function collect_attach_for(core, address, visited) {
  let $ = $list.any(visited, (seen) => { return seen === address; });
  if ($) {
    return [$List$Empty$const, visited];
  } else {
    let visited$1 = listPrepend(address, visited);
    let $1 = $dict.get(core.detached, address);
    if ($1 instanceof Ok) {
      let state = $1[0];
      let deps = $channel.handle_addresses(state);
      let $2 = collect_attach_order(core, deps, visited$1);
      let order = $2[0];
      let visited$2 = $2[1];
      return [$list.append(order, toList([address])), visited$2];
    } else {
      return [$List$Empty$const, visited$1];
    }
  }
}

function collect_attach_order(core, addresses, visited) {
  return $list.fold(
    addresses,
    [$List$Empty$const, visited],
    (acc, address) => {
      let order = acc[0];
      let visited$1 = acc[1];
      let $ = collect_attach_for(core, address, visited$1);
      let next = $[0];
      let visited$2 = $[1];
      return [$list.append(order, next), visited$2];
    },
  );
}

function attach_dependencies(core, value) {
  let $ = collect_attach_order(
    core,
    $handle.collect_handle_addresses(value),
    $List$Empty$const,
  );
  let order = $[0];
  return submit_attaches(core, order);
}

function put_detached_channel(core, address, state) {
  return new Core(
    core.client_id,
    core.channels,
    core.channel_order,
    $dict.insert(core.detached, address, state),
    core.next_client_sequence_number,
    core.last_seen_sequence_number,
    core.in_flight,
    core.out_of_order,
    core.members,
    core.live_members,
    core.ingest,
    core.last_summary_sequence_number,
    core.summary_head,
    core.owed,
  );
}

export function set(core, address, key, value) {
  let $ = locate_map(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $map_kernel.set(kernel, key, value);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(core, address, new $channel.MapState(kernel$1)),
          tag_map_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let $2 = attach_dependencies(core, value);
      let core$1 = $2[0];
      let attach_outbound = $2[1];
      return $result.try$(
        locate_map(core$1, address),
        (located) => {
          let _block;
          if (located instanceof Detached) {
            let kernel = located[0];
            _block = kernel;
          } else {
            let kernel = located[0];
            _block = kernel;
          }
          let kernel = _block;
          let $3 = $map_kernel.set(kernel, key, value);
          let kernel$1 = $3[0];
          let events = $3[1];
          let operation = $3[2];
          let $4 = stamp_attached(
            core$1,
            address,
            new $channel.MapState(kernel$1),
            tag_map_events(address, events),
            new $channel.MapOperation(operation),
            $channel.LocalOperationMeta$NoMeta$const,
          );
          let core$2 = $4[0];
          let events$1 = $4[1];
          let outbound = $4[2];
          return new Ok(
            [core$2, events$1, $list.append(attach_outbound, outbound)],
          );
        },
      );
    }
  } else {
    return $;
  }
}

function client_id_to_int(client_id) {
  return $client_id.to_int(client_id);
}

/**
 * Decode the payload of a system message. The server carries such a payload in
 * `data`, as JSON *text*, and `contents` is null on those messages. This
 * function thus parses the string, and it does not read the dynamic value. To
 * read `contents` here fails the decode against every real server, and that
 * failure reports nothing, because a malformed payload changes nothing on
 * purpose.
 * 
 * @ignore
 */
function system_payload(data, decoder) {
  if (data instanceof Some) {
    let text = data[0];
    let _pipe = $json.parse(text, decoder);
    return $result.replace_error(_pipe, undefined);
  } else {
    return new Error(undefined);
  }
}

/**
 * Apply a sequenced membership leave, which is a `"leave"` system message, by
 * sending the client that left to every attached channel. The server gives the
 * leave a sequence number and carries the id of that client in `data`. Every
 * replica thus settles the per-client kernel state deterministically at the
 * same `leave_sequence_number` value. That state is the queue jobs that a
 * kernel releases again, and the consensus signoffs that it removes. A channel
 * with no membership behaviour does nothing. The function ignores a malformed
 * payload, and it does not fail the whole batch.
 * 
 * @ignore
 */
function handle_leave(core, msg) {
  let $ = system_payload(msg.data, $decode.string);
  if ($ instanceof Ok) {
    let leaving_client_id = $[0];
    let client_int = client_id_to_int(leaving_client_id);
    let core$1 = new Core(
      core.client_id,
      core.channels,
      core.channel_order,
      core.detached,
      core.next_client_sequence_number,
      core.last_seen_sequence_number,
      core.in_flight,
      core.out_of_order,
      $set.delete$(core.members, client_int),
      core.live_members,
      core.ingest,
      core.last_summary_sequence_number,
      core.summary_head,
      core.owed,
    );
    let $1 = $list.fold(
      core$1.channel_order,
      [core$1, $List$Empty$const],
      (acc, address) => {
        let core$2 = acc[0];
        let events = acc[1];
        let $2 = $dict.get(core$2.channels, address);
        if ($2 instanceof Ok) {
          let state = $2[0];
          let $3 = $channel.on_leave(state, client_int, msg.sequence_number);
          let state$1 = $3[0];
          let channel_events = $3[1];
          return [
            put_attached_channel(core$2, address, state$1),
            $list.append(events, tag_events(address, channel_events)),
          ];
        } else {
          return acc;
        }
      },
    );
    let core$2 = $1[0];
    let events = $1[1];
    return new Ok([core$2, events, $List$Empty$const]);
  } else {
    return new Ok([core, $List$Empty$const, $List$Empty$const]);
  }
}

function without_summary_events(outcome) {
  return $result.map(
    outcome,
    (outcome) => {
      let core = outcome[0];
      let events = outcome[1];
      let resolutions = outcome[2];
      return [core, events, resolutions, $List$Empty$const];
    },
  );
}

/**
 * Apply a sequenced membership join, which is a `"join"` system message, by
 * adding the client that arrived to the roster. No kernel needs this message,
 * and a `"leave"` message differs there. A join only makes the quorum larger,
 * for the operations that sequence *after* it, and a pact that is already
 * pending froze its signoff list when it sequenced.
 *
 * The payload of a join is an object, `{"clientId": …, "detail": {…}}`. The
 * payload of a leave is a bare string. The two system messages do not share one
 * shape.
 * 
 * @ignore
 */
function handle_join(core, msg) {
  let $ = system_payload(
    msg.data,
    $decode.at(toList(["clientId"]), $decode.string),
  );
  if ($ instanceof Ok) {
    let joining_client_id = $[0];
    return new Ok(
      [
        new Core(
          core.client_id,
          core.channels,
          core.channel_order,
          core.detached,
          core.next_client_sequence_number,
          core.last_seen_sequence_number,
          core.in_flight,
          core.out_of_order,
          $set.insert(core.members, client_id_to_int(joining_client_id)),
          core.live_members,
          core.ingest,
          core.last_summary_sequence_number,
          core.summary_head,
          core.owed,
        ),
        $List$Empty$const,
        $List$Empty$const,
      ],
    );
  } else {
    return new Ok([core, $List$Empty$const, $List$Empty$const]);
  }
}

/**
 * Add the owed follow-up operations that a kernel released while it applied a
 * sequenced operation, keyed by channel address. `collect_released_operations`
 * then stamps them and submits them after the current batch. This function is
 * public, so that a test can fill the buffer without a kernel that produces
 * operations.
 */
export function enqueue_owed(core, address, owed) {
  if (owed instanceof $Empty) {
    return core;
  } else {
    let _block;
    let _pipe = $dict.get(core.owed, address);
    _block = $result.unwrap(_pipe, $List$Empty$const);
    let existing = _block;
    return new Core(
      core.client_id,
      core.channels,
      core.channel_order,
      core.detached,
      core.next_client_sequence_number,
      core.last_seen_sequence_number,
      core.in_flight,
      core.out_of_order,
      core.members,
      core.live_members,
      core.ingest,
      core.last_summary_sequence_number,
      core.summary_head,
      $dict.insert(core.owed, address, $list.append(existing, owed)),
    );
  }
}

function quorum_with_live_defences(core, author) {
  let _pipe = core.members;
  let _pipe$1 = $set.insert(_pipe, client_id_to_int(core.client_id));
  let _pipe$2 = ((members) => {
    if (author instanceof Some) {
      let id = author[0];
      return $set.insert(members, client_id_to_int(id));
    } else {
      return members;
    }
  })(_pipe$1);
  return $set.to_list(_pipe$2);
}

/**
 * The quorum that the core judges a sequenced operation against: the roster at
 * the sequence point of that operation, and, for a live operation only, this
 * client and the author of the operation.
 *
 * The function adds those two as a protection. It does not assume that they are
 * present. A quorum without a connected client accepts too early. That was the
 * fault that this code replaced, which used a fixed `[self, author]` list and
 * never read the room. But a quorum that names a client outside the room can
 * never become empty, and the pact then never completes. This client and the
 * author are the two clients that the core knows are live: one of them is this
 * client, and the other one just had an operation sequenced. To include them
 * thus cannot stop a pact, and it covers a join message that the client lost,
 * or that arrived after the operation that follows it.
 *
 * **That reasoning holds on the live path only.** A replay reads a complete,
 * ordered log, in which no join can be absent. "This client is live" is then a
 * false premise. For an operation that sequenced before this client joined,
 * the client was not in the room, and to add it to the quorum puts it in a
 * quorum that it was never part of. A settled consensus proposal then rebuilds
 * as pending on this client, and it never completes. The protections are thus
 * for the live path only.
 *
 * An author of `None` is a system message, and not the client `0`. The earlier
 * code converted it to `0` and added a member that never signs off.
 * 
 * @ignore
 */
function quorum_of(core, author) {
  let $ = core.ingest;
  if ($ instanceof Replaying) {
    let _pipe = core.members;
    return $set.to_list(_pipe);
  } else {
    return quorum_with_live_defences(core, author);
  }
}

function apply_remote_channel(
  core,
  message_client_id,
  sequence_number,
  minimum_sequence_number,
  reference_sequence_number,
  address,
  state,
  operation
) {
  let meta = new SequencedMeta(
    sequence_number,
    core.last_seen_sequence_number,
    minimum_sequence_number,
    (() => {
      let _pipe = $option.map(message_client_id, client_id_to_int);
      return $option.unwrap(_pipe, 0);
    })(),
    client_id_to_int(core.client_id),
    quorum_of(core, message_client_id),
    $set.to_list(core.members),
    reference_sequence_number,
  );
  let $ = $channel.apply_remote(state, operation, meta);
  if ($ instanceof Ok) {
    let state$1 = $[0][0];
    let events = $[0][1];
    let owed = $[0][2];
    return new Ok(
      [
        enqueue_owed(
          put_attached_channel(core, address, state$1),
          address,
          owed,
        ),
        tag_events(address, events),
        $List$Empty$const,
      ],
    );
  } else {
    let $1 = $[0];
    if ($1 instanceof $channel.UnexpectedAck) {
      let detail = $1.detail;
      return new Error(new AckMismatch(detail));
    } else if ($1 instanceof $channel.WrongChannelType) {
      let detail = $1.detail;
      return new Error(new AckMismatch(detail));
    } else if ($1 instanceof $channel.CorruptRemoteOperation) {
      let detail = $1.detail;
      return new Error(new AckMismatch(detail));
    } else if ($1 instanceof $channel.OrMapOperationFailed) {
      let detail = $1.detail;
      return new Error(new OrMapOperationFailed(address, detail));
    } else {
      let detail = $1.detail;
      return new Error(new AckMismatch(detail));
    }
  }
}

function tag_resolution(address, resolution) {
  if (resolution instanceof Some) {
    let resolution$1 = resolution[0];
    return toList([[address, resolution$1]]);
  } else {
    return $List$Empty$const;
  }
}

function ack_own_operation(
  core,
  message_client_id,
  client_sequence_number,
  address,
  state,
  echoed,
  sequence_number,
  minimum_sequence_number
) {
  let $ = core.in_flight;
  if ($ instanceof $Empty) {
    return new Error(
      new AckMismatch(
        ("own op sequenced with csn " + $int.to_string(client_sequence_number)) + " but in-flight queue is empty",
      ),
    );
  } else {
    let head = $.head;
    let rest = $.tail;
    if (head instanceof InFlightOperation) {
      let client_id = head.client_id;
      let head_client_sequence_number = head.client_sequence_number;
      let head_address = head.address;
      let operation = head.operation;
      let meta = head.meta;
      let $1 = (((isEqual(new Some(client_id), message_client_id)) && (head_client_sequence_number === client_sequence_number)) && (head_address === address)) && $channel.same_shape(
        operation,
        echoed,
      );
      if ($1) {
        let sequenced_meta = new SequencedMeta(
          sequence_number,
          core.last_seen_sequence_number,
          minimum_sequence_number,
          client_id_to_int(core.client_id),
          client_id_to_int(core.client_id),
          quorum_of(core, new Some(core.client_id)),
          $set.to_list(core.members),
          core.last_seen_sequence_number,
        );
        let $2 = $channel.applies_own_on_sequence(state);
        if ($2) {
          let $3 = $channel.apply_remote(state, operation, sequenced_meta);
          if ($3 instanceof Ok) {
            let state$1 = $3[0][0];
            let events = $3[0][1];
            let owed = $3[0][2];
            return new Ok(
              [
                enqueue_owed(
                  new Core(
                    core.client_id,
                    $dict.insert(core.channels, address, state$1),
                    core.channel_order,
                    core.detached,
                    core.next_client_sequence_number,
                    core.last_seen_sequence_number,
                    rest,
                    core.out_of_order,
                    core.members,
                    core.live_members,
                    core.ingest,
                    core.last_summary_sequence_number,
                    core.summary_head,
                    core.owed,
                  ),
                  address,
                  owed,
                ),
                tag_events(address, events),
                $List$Empty$const,
              ],
            );
          } else {
            let $4 = $3[0];
            if ($4 instanceof $channel.UnexpectedAck) {
              let detail = $4.detail;
              return new Error(new AckMismatch(detail));
            } else if ($4 instanceof $channel.WrongChannelType) {
              let detail = $4.detail;
              return new Error(new AckMismatch(detail));
            } else if ($4 instanceof $channel.CorruptRemoteOperation) {
              let detail = $4.detail;
              return new Error(new AckMismatch(detail));
            } else if ($4 instanceof $channel.OrMapOperationFailed) {
              let detail = $4.detail;
              return new Error(new OrMapOperationFailed(address, detail));
            } else {
              let detail = $4.detail;
              return new Error(new AckMismatch(detail));
            }
          }
        } else {
          let $3 = $channel.ack_local(state, operation, meta, sequenced_meta);
          if ($3 instanceof Ok) {
            let state$1 = $3[0][0];
            let events = $3[0][1];
            let resolution = $3[0][2];
            return new Ok(
              [
                new Core(
                  core.client_id,
                  $dict.insert(core.channels, address, state$1),
                  core.channel_order,
                  core.detached,
                  core.next_client_sequence_number,
                  core.last_seen_sequence_number,
                  rest,
                  core.out_of_order,
                  core.members,
                  core.live_members,
                  core.ingest,
                  core.last_summary_sequence_number,
                  core.summary_head,
                  core.owed,
                ),
                tag_events(address, events),
                tag_resolution(address, resolution),
              ],
            );
          } else {
            let $4 = $3[0];
            if ($4 instanceof $channel.UnexpectedAck) {
              let detail = $4.detail;
              return new Error(new AckMismatch(detail));
            } else if ($4 instanceof $channel.WrongChannelType) {
              let detail = $4.detail;
              return new Error(new AckMismatch(detail));
            } else if ($4 instanceof $channel.CorruptRemoteOperation) {
              let detail = $4.detail;
              return new Error(new AckMismatch(detail));
            } else if ($4 instanceof $channel.OrMapOperationFailed) {
              let detail = $4.detail;
              return new Error(new OrMapOperationFailed(address, detail));
            } else {
              let detail = $4.detail;
              return new Error(new AckMismatch(detail));
            }
          }
        }
      } else {
        return new Error(
          new AckMismatch(
            (("expected ack for csn " + $int.to_string(
              head_client_sequence_number,
            )) + ", got csn ") + $int.to_string(client_sequence_number),
          ),
        );
      }
    } else {
      let head_client_sequence_number = head.client_sequence_number;
      return new Error(
        new AckMismatch(
          (("expected attach ack for csn " + $int.to_string(
            head_client_sequence_number,
          )) + ", got channel op ack for csn ") + $int.to_string(
            client_sequence_number,
          ),
        ),
      );
    }
  }
}

function in_flight_client_id(entry) {
  if (entry instanceof InFlightOperation) {
    let client_id = entry.client_id;
    return client_id;
  } else {
    let client_id = entry.client_id;
    return client_id;
  }
}

function is_own_operation(core, message_client_id) {
  if (message_client_id instanceof Some) {
    let cid = message_client_id[0];
    return (cid === core.client_id) || (() => {
      let $ = core.in_flight;
      if ($ instanceof $Empty) {
        return false;
      } else {
        let head = $.head;
        return in_flight_client_id(head) === cid;
      }
    })();
  } else {
    return false;
  }
}

function add_attached_channel(core, address, state) {
  return new Core(
    core.client_id,
    $dict.insert(core.channels, address, state),
    $list.unique($list.append(core.channel_order, toList([address]))),
    core.detached,
    core.next_client_sequence_number,
    core.last_seen_sequence_number,
    core.in_flight,
    core.out_of_order,
    core.members,
    core.live_members,
    core.ingest,
    core.last_summary_sequence_number,
    core.summary_head,
    core.owed,
  );
}

export function has_channel(core, address) {
  return $dict.has_key(core.channels, address) || $dict.has_key(
    core.detached,
    address,
  );
}

function remote_attach(core, sequence_number, address, snapshot) {
  let $ = has_channel(core, address);
  if ($) {
    return new Error(new DuplicateAttach(address, sequence_number));
  } else {
    return $result.try$(
      (() => {
        let _pipe = $channel.from_snapshot(snapshot, core.client_id);
        return $result.map_error(
          _pipe,
          (detail) => { return new BadSummaryChannel(address, detail); },
        );
      })(),
      (state) => {
        return new Ok(
          [
            add_attached_channel(core, address, state),
            $List$Empty$const,
            $List$Empty$const,
          ],
        );
      },
    );
  }
}

function ack_own_attach(
  core,
  message_client_id,
  client_sequence_number,
  address,
  echoed
) {
  let $ = core.in_flight;
  if ($ instanceof $Empty) {
    return new Error(
      new AckMismatch(
        ("own attach sequenced with csn " + $int.to_string(
          client_sequence_number,
        )) + " but in-flight queue is empty",
      ),
    );
  } else {
    let head = $.head;
    let rest = $.tail;
    if (head instanceof InFlightOperation) {
      let head_client_sequence_number = head.client_sequence_number;
      return new Error(
        new AckMismatch(
          (("expected channel op ack for csn " + $int.to_string(
            head_client_sequence_number,
          )) + ", got attach ack for csn ") + $int.to_string(
            client_sequence_number,
          ),
        ),
      );
    } else {
      let client_id = head.client_id;
      let head_client_sequence_number = head.client_sequence_number;
      let head_address = head.address;
      let snapshot = head.snapshot;
      let $1 = (((isEqual(new Some(client_id), message_client_id)) && (head_client_sequence_number === client_sequence_number)) && (head_address === address)) && $channel.same_snapshot(
        snapshot,
        echoed,
      );
      if ($1) {
        return new Ok(
          [
            new Core(
              core.client_id,
              core.channels,
              core.channel_order,
              core.detached,
              core.next_client_sequence_number,
              core.last_seen_sequence_number,
              rest,
              core.out_of_order,
              core.members,
              core.live_members,
              core.ingest,
              core.last_summary_sequence_number,
              core.summary_head,
              core.owed,
            ),
            $List$Empty$const,
            $List$Empty$const,
          ],
        );
      } else {
        return new Error(
          new AckMismatch(
            (("expected attach ack for csn " + $int.to_string(
              head_client_sequence_number,
            )) + ", got csn ") + $int.to_string(client_sequence_number),
          ),
        );
      }
    }
  }
}

function handle_operation(core, msg) {
  let $ = $wire_op.decode_operation_contents(msg.contents);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $wire_op.ChannelOperation) {
      let address = $1.address;
      let raw_contents = $1.contents;
      let $2 = $dict.get(core.channels, address);
      if ($2 instanceof Ok) {
        let state = $2[0];
        let $3 = $decode.run(
          raw_contents,
          $wire_op.channel_operation_decoder($channel.channel_type(state)),
        );
        if ($3 instanceof Ok) {
          let operation = $3[0];
          let $4 = is_own_operation(core, msg.client_id);
          if ($4) {
            return ack_own_operation(
              core,
              msg.client_id,
              msg.client_sequence_number,
              address,
              state,
              operation,
              msg.sequence_number,
              msg.minimum_sequence_number,
            );
          } else {
            return apply_remote_channel(
              core,
              msg.client_id,
              msg.sequence_number,
              msg.minimum_sequence_number,
              msg.reference_sequence_number,
              address,
              state,
              operation,
            );
          }
        } else {
          return new Error(new BadOperationContents(msg.sequence_number));
        }
      } else {
        return new Error(new UnknownChannel(address, msg.sequence_number));
      }
    } else {
      let address = $1.address;
      let snapshot = $1.snapshot;
      let $2 = is_own_operation(core, msg.client_id);
      if ($2) {
        return ack_own_attach(
          core,
          msg.client_id,
          msg.client_sequence_number,
          address,
          snapshot,
        );
      } else {
        return remote_attach(core, msg.sequence_number, address, snapshot);
      }
    }
  } else {
    return new Error(new BadOperationContents(msg.sequence_number));
  }
}

function apply_one(core, msg) {
  let core$1 = new Core(
    core.client_id,
    core.channels,
    core.channel_order,
    core.detached,
    core.next_client_sequence_number,
    msg.sequence_number,
    core.in_flight,
    core.out_of_order,
    core.members,
    core.live_members,
    core.ingest,
    core.last_summary_sequence_number,
    core.summary_head,
    core.owed,
  );
  let $ = msg.message_type;
  if ($ === "op") {
    return without_summary_events(handle_operation(core$1, msg));
  } else if ($ === "join") {
    return without_summary_events(handle_join(core$1, msg));
  } else if ($ === "leave") {
    return without_summary_events(handle_leave(core$1, msg));
  } else if ($ === "summarize") {
    return new Ok(
      [
        core$1,
        $List$Empty$const,
        $List$Empty$const,
        toList([
          new SummaryProposalSequenced(
            msg.client_id,
            msg.client_sequence_number,
            msg.sequence_number,
          ),
        ]),
      ],
    );
  } else if ($ === "summaryAck") {
    return apply_summary_response(core$1, msg);
  } else if ($ === "summaryNack") {
    return apply_summary_response(core$1, msg);
  } else {
    return new Ok(
      [core$1, $List$Empty$const, $List$Empty$const, $List$Empty$const],
    );
  }
}

function drain_buffer(loop$core) {
  while (true) {
    let core = loop$core;
    let $ = core.out_of_order;
    if ($ instanceof $Empty) {
      return new Ok(
        [core, $List$Empty$const, $List$Empty$const, $List$Empty$const],
      );
    } else {
      let head = $.head;
      if (head.sequence_number <= core.last_seen_sequence_number) {
        let rest = $.tail;
        loop$core = new Core(
          core.client_id,
          core.channels,
          core.channel_order,
          core.detached,
          core.next_client_sequence_number,
          core.last_seen_sequence_number,
          core.in_flight,
          rest,
          core.members,
          core.live_members,
          core.ingest,
          core.last_summary_sequence_number,
          core.summary_head,
          core.owed,
        );
      } else {
        let head = $.head;
        if (head.sequence_number === (core.last_seen_sequence_number + 1)) {
          let rest = $.tail;
          return $result.try$(
            apply_one(
              new Core(
                core.client_id,
                core.channels,
                core.channel_order,
                core.detached,
                core.next_client_sequence_number,
                core.last_seen_sequence_number,
                core.in_flight,
                rest,
                core.members,
                core.live_members,
                core.ingest,
                core.last_summary_sequence_number,
                core.summary_head,
                core.owed,
              ),
              head,
            ),
            (_use0) => {
              let core$1 = _use0[0];
              let events = _use0[1];
              let resolutions = _use0[2];
              let summary_events = _use0[3];
              return $result.try$(
                drain_buffer(core$1),
                (_use0) => {
                  let core$2 = _use0[0];
                  let more = _use0[1];
                  let more_resolutions = _use0[2];
                  let more_summary_events = _use0[3];
                  return new Ok(
                    [
                      core$2,
                      $list.append(events, more),
                      $list.append(resolutions, more_resolutions),
                      $list.append(summary_events, more_summary_events),
                    ],
                  );
                },
              );
            },
          );
        } else {
          return new Ok(
            [core, $List$Empty$const, $List$Empty$const, $List$Empty$const],
          );
        }
      }
    }
  }
}

function buffer_insert(buffer, msg) {
  if (buffer instanceof $Empty) {
    return toList([msg]);
  } else {
    let head = buffer.head;
    let rest = buffer.tail;
    let $ = $int.compare(msg.sequence_number, head.sequence_number);
    if ($ instanceof $order.Lt) {
      return listPrepend(msg, buffer);
    } else if ($ instanceof $order.Eq) {
      return buffer;
    } else {
      return listPrepend(head, buffer_insert(rest, msg));
    }
  }
}

export function handle_sequenced(core, msg) {
  let next = core.last_seen_sequence_number + 1;
  let $ = msg.sequence_number;
  let sequence_number = $;
  if (sequence_number < next) {
    return new Ok(
      [
        core,
        new Ingested(
          $List$Empty$const,
          $List$Empty$const,
          $List$Empty$const,
          Option$None$const,
          $List$Empty$const,
        ),
      ],
    );
  } else {
    let sequence_number = $;
    if (sequence_number > next) {
      let _block;
      let $1 = core.out_of_order;
      if ($1 instanceof $Empty) {
        _block = new Some(core.last_seen_sequence_number);
      } else {
        _block = Option$None$const;
      }
      let request = _block;
      let core$1 = new Core(
        core.client_id,
        core.channels,
        core.channel_order,
        core.detached,
        core.next_client_sequence_number,
        core.last_seen_sequence_number,
        core.in_flight,
        buffer_insert(core.out_of_order, msg),
        core.members,
        core.live_members,
        core.ingest,
        core.last_summary_sequence_number,
        core.summary_head,
        core.owed,
      );
      return new Ok(
        [
          core$1,
          new Ingested(
            $List$Empty$const,
            $List$Empty$const,
            $List$Empty$const,
            request,
            $List$Empty$const,
          ),
        ],
      );
    } else {
      return $result.try$(
        apply_one(core, msg),
        (_use0) => {
          let core$1 = _use0[0];
          let events = _use0[1];
          let resolutions = _use0[2];
          let summary_events = _use0[3];
          return $result.try$(
            drain_buffer(core$1),
            (_use0) => {
              let core$2 = _use0[0];
              let drained = _use0[1];
              let drained_resolutions = _use0[2];
              let drained_summary_events = _use0[3];
              let $1 = collect_released_operations(core$2);
              let core$3 = $1[0];
              let outbound = $1[1];
              return new Ok(
                [
                  core$3,
                  new Ingested(
                    $list.append(events, drained),
                    $list.append(resolutions, drained_resolutions),
                    $list.append(summary_events, drained_summary_events),
                    Option$None$const,
                    outbound,
                  ),
                ],
              );
            },
          );
        },
      );
    }
  }
}

/**
 * Fold the historical messages into the core, with `ingest` at `Replaying` for
 * the length of the fold.
 *
 * The position moves here, and not across a whole bootstrap, because
 * `Replaying` turns off the safety protections. The reconnect path reaches
 * `Ready` by a route that never passes through `settle_bootstrap`. A position
 * that a hand-off had to reset would thus stay at `Replaying` on that route,
 * and it would disable `quorum_of` for the rest of the session. To move the
 * position around the fold only makes that fault impossible: nothing outside
 * a replay can observe `Replaying`.
 * 
 * @ignore
 */
function replay(core, messages) {
  return $result.map(
    $list.try_fold(
      messages,
      new Core(
        core.client_id,
        core.channels,
        core.channel_order,
        core.detached,
        core.next_client_sequence_number,
        core.last_seen_sequence_number,
        core.in_flight,
        core.out_of_order,
        core.members,
        core.live_members,
        IngestPosition$Replaying$const,
        core.last_summary_sequence_number,
        core.summary_head,
        core.owed,
      ),
      (core, msg) => {
        let _pipe = handle_sequenced(core, msg);
        return $result.map(_pipe, (outcome) => { return outcome[0]; });
      },
    ),
    (core) => {
      return new Core(
        core.client_id,
        core.channels,
        core.channel_order,
        core.detached,
        core.next_client_sequence_number,
        core.last_seen_sequence_number,
        core.in_flight,
        core.out_of_order,
        core.members,
        core.live_members,
        IngestPosition$Live$const,
        core.last_summary_sequence_number,
        core.summary_head,
        core.owed,
      );
    },
  );
}

/**
 * The connected roster that a handshake carries, as kernel-side integer ids.
 * The function adds this client, because the server builds `initialClients`
 * from the presence map of the document, and that map does not have to contain
 * the client that the server answers.
 * 
 * @ignore
 */
function roster_of(connected) {
  let _pipe = connected.initial_clients;
  let _pipe$1 = $list.map(
    _pipe,
    (client) => { return client_id_to_int(client.client_id); },
  );
  let _pipe$2 = $set.from_list(_pipe$1);
  return $set.insert(_pipe$2, client_id_to_int(connected.client_id));
}

function seed_channels(seeded, replica) {
  return $result.try$(
    $list.try_fold(
      seeded,
      [$dict.new$(), $List$Empty$const],
      (acc, entry) => {
        let channels = acc[0];
        let channel_order = acc[1];
        let address = entry[0];
        let snapshot = entry[1];
        return $result.try$(
          (() => {
            let _pipe = $channel.from_snapshot(snapshot, replica);
            return $result.map_error(
              _pipe,
              (detail) => { return new BadSummaryChannel(address, detail); },
            );
          })(),
          (state) => {
            return new Ok(
              [
                $dict.insert(channels, address, state),
                $list.unique($list.append(channel_order, toList([address]))),
              ],
            );
          },
        );
      },
    ),
    (_use0) => {
      let channels = _use0[0];
      let channel_order = _use0[1];
      let $ = $dict.has_key(channels, root_address);
      if ($) {
        return new Ok([channels, channel_order]);
      } else {
        return new Ok(
          [
            $dict.insert(
              channels,
              root_address,
              $channel.new$($channel.ChannelInit$InitMap$const, replica),
            ),
            listPrepend(root_address, channel_order),
          ],
        );
      }
    },
  );
}

export function bootstrap(connected, summary) {
  let $ = $option.unwrap(
    summary,
    new Summary(0, $List$Empty$const, $List$Empty$const),
  );
  let last_seen = $.sequence_number;
  let seeded = $.channels;
  let seed_members = $.members;
  return $result.try$(
    seed_channels(seeded, connected.client_id),
    (_use0) => {
      let channels = _use0[0];
      let channel_order = _use0[1];
      let core = new Core(
        connected.client_id,
        channels,
        channel_order,
        $dict.new$(),
        1,
        last_seen,
        $List$Empty$const,
        $List$Empty$const,
        $set.from_list(seed_members),
        roster_of(connected),
        IngestPosition$Replaying$const,
        (() => {
          let $1 = connected.summary_context;
          if ($1 instanceof Some) {
            let context = $1[0];
            return context.sequence_number;
          } else {
            return last_seen;
          }
        })(),
        (() => {
          let $1 = connected.summary_context;
          if ($1 instanceof Some) {
            let context = $1[0];
            return new Some(context.handle);
          } else {
            return $1;
          }
        })(),
        $dict.new$(),
      );
      return $result.try$(
        replay(core, connected.initial_messages),
        (core) => {
          let checkpoint = $option.unwrap(
            connected.checkpoint_sequence_number,
            core.last_seen_sequence_number,
          );
          return new Ok(settle_bootstrap(core, checkpoint));
        },
      );
    },
  );
}

export function resume_bootstrap(core, checkpoint, deltas) {
  let before = core.last_seen_sequence_number;
  return $result.try$(
    replay(core, deltas),
    (core) => {
      let $ = (!(core.out_of_order instanceof $Empty)) && (core.last_seen_sequence_number === before);
      if ($) {
        return new Error(
          new HistoryGap(
            ("history catch-up made no progress past sequence number " + $int.to_string(
              before,
            )) + " (server storage is missing the range)",
          ),
        );
      } else {
        return new Ok(settle_bootstrap(core, checkpoint));
      }
    },
  );
}

/**
 * The roster to record in a summary, as kernel-side integer ids.
 *
 * `summarize` runs on a synchronized client only. At that moment
 * `core.members` *is* the roster at `core.last_seen_sequence_number`, which is
 * the sequence number that the blob records. That pair makes the checkpoint
 * roster meaningful, and it is the reason that the client captures the two
 * values together.
 */
export function summary_members(core) {
  let _pipe = core.members;
  let _pipe$1 = $set.to_list(_pipe);
  return $list.sort(_pipe$1, $int.compare);
}

export function summary_channels(core) {
  return $list.filter_map(
    core.channel_order,
    (address) => {
      let $ = $dict.get(core.channels, address);
      if ($ instanceof Ok) {
        let state = $[0];
        return new Ok([address, $channel.snapshot(state)]);
      } else {
        return new Error(undefined);
      }
    },
  );
}

export function is_synced(core) {
  return core.in_flight instanceof $Empty;
}

/**
 * How far the document moved past the newest checkpoint that this client knows
 * about. The automatic policy compares this number with its threshold, and a
 * diagnostic view can show it. On a document that no client has summarized,
 * this number is the full length of the log, which is the cost that every
 * client that joins pays.
 *
 * The count is in **sequenced messages**, and not in edits. A server sequences
 * a batch of submitted operations as one message, so a burst of writes moves
 * this number much less than the number of writes. Messages are the correct
 * unit, because a client that joins replays messages.
 */
export function operations_since_summary(core) {
  return $int.max(
    0,
    core.last_seen_sequence_number - core.last_summary_sequence_number,
  );
}

/**
 * Whether this client must summarize now, under `policy`.
 *
 * This test is stricter than `is_synced`, and that is deliberate. `is_synced`
 * reports only that there is no local edit without an ack. A summary is a
 * claim about the confirmed state at one sequence point, so every condition
 * that puts the core away from that point refuses the summary:
 *
 *   - `Replaying`: the core is at a historical position, and the roster that
 *     it would record is the room at the checkpoint, and not the room now.
 *   - `in_flight`: there is a local edit that the blob would omit, and it
 *     would report nothing. `summarize` refuses in this state, so the policy
 *     must not ask.
 *   - `out_of_order`: a `requestOps` round is open, so the confirmed state is
 *     a prefix of the state that the server already sequenced.
 */
export function wants_summary(core, policy) {
  return (((core.ingest instanceof Live) && (core.in_flight instanceof $Empty)) && (core.out_of_order instanceof $Empty)) && (operations_since_summary(
    core,
  ) >= $summary_policy.policy_threshold(policy));
}

/**
 * How long this client waits before it acts on `wants_summary`.
 *
 * The delay comes from the client id, and not from a random source. Every
 * client in the room crosses the threshold on the same operation. A derived
 * delay thus spreads the clients deterministically. A test can reproduce it,
 * and neither target needs a random number generator. The first summary that
 * sequences advances the `last_summary_sequence_number` value of every other
 * client, so the rest of the room checks again and stops.
 *
 * The multiplication does necessary work. A server gives out the client ids in
 * sequence, so `id % window` puts a whole room within a few milliseconds of
 * each other. That result is deterministic, and it spreads nothing. To scramble
 * the id first turns two adjacent ids into two distant delays, which is the
 * purpose of the window. The `% 100_003` operation keeps the product inside the
 * range of integers that JavaScript represents exactly.
 */
export function summary_jitter_milliseconds(core, policy) {
  let $ = $summary_policy.policy_jitter_milliseconds(policy);
  let window = $;
  if (window <= 0) {
    return 0;
  } else {
    let window = $;
    let id = $int.absolute_value(client_id_to_int(core.client_id)) % 100_003;
    return remainderInt(id * 2_654_435_761, window);
  }
}

export function build_summarize(core, handle, message) {
  let client_sequence_number = core.next_client_sequence_number;
  let _block;
  let $ = core.summary_head;
  if ($ instanceof Some) {
    let head = $[0];
    _block = head;
  } else {
    _block = "";
  }
  let head = _block;
  let outbound = $wire_op.outbound_summarize_operation(
    client_sequence_number,
    core.last_seen_sequence_number,
    handle,
    message,
    (() => {
      let $1 = core.summary_head;
      if ($1 instanceof Some) {
        let head$1 = $1[0];
        return toList([head$1]);
      } else {
        return $List$Empty$const;
      }
    })(),
    head,
  );
  return [
    new Core(
      core.client_id,
      core.channels,
      core.channel_order,
      core.detached,
      client_sequence_number + 1,
      core.last_seen_sequence_number,
      core.in_flight,
      core.out_of_order,
      core.members,
      core.live_members,
      core.ingest,
      core.last_summary_sequence_number,
      core.summary_head,
      core.owed,
    ),
    outbound,
  ];
}

/**
 * Enter the reconnect state. Keep the roster that the core holds, and return
 * to the replaying state.
 *
 * The function does **not** replace the roster with the roster of the new
 * handshake yet, and that is deliberate. `resume_bootstrap` replays the
 * operations that sequenced while the client was absent, and the core must
 * judge those operations against the room at *that* time. That room is the
 * last roster that the client knew, advanced by the `join` and `leave`
 * messages inside the gap that it replays. To take `initialClients` here would
 * apply the room after the reconnect to the operations from before the
 * reconnect. That is the same shift in time that breaks a cold join, over a
 * shorter interval. `settle_bootstrap` takes the new roster after the gap
 * closes.
 */
export function adopt_reconnect(core, connected) {
  return new Core(
    connected.client_id,
    core.channels,
    core.channel_order,
    core.detached,
    core.next_client_sequence_number,
    core.last_seen_sequence_number,
    core.in_flight,
    core.out_of_order,
    core.members,
    roster_of(connected),
    IngestPosition$Replaying$const,
    core.last_summary_sequence_number,
    core.summary_head,
    core.owed,
  );
}

/**
 * The sequence number that a reconnect must send `requestOps` from. The result
 * is `None` when the handshake left nothing to catch up on.
 *
 * A reconnect must ask for its own gap. `adopt_reconnect` does not replay
 * `initial_messages`, and that is deliberate. Only an inbound sequenced
 * operation can thus move `last_seen_sequence_number` up to the checkpoint of
 * the handshake, and no server sends one without a request. floodgate ignores
 * `lastSeenSequenceNumber` completely, and it removes the joining client from
 * the broadcast of the *own* join operation of that client. A client that
 * rejoins a room where no other client writes thus receives nothing at all. To
 * wait for the next edit of a peer is not a catch-up plan. It is a chance, and
 * a quiet room never gives it.
 *
 * The result is `last_seen_sequence_number`, and not
 * `last_seen_sequence_number + 1`. `requestOps` excludes `from` on both
 * servers, and this value agrees with what `handle_sequenced` already asks for
 * when a live operation shows a gap.
 *
 * The checkpoint is almost always ahead on a write reconnect, because floodgate
 * sequences the `join` operation of the rejoining client and reports *that*
 * operation as the checkpoint. This function thus returns `Some` also for a
 * reconnect that missed no application traffic.
 */
export function catch_up_from(core, checkpoint) {
  let $ = checkpoint > core.last_seen_sequence_number;
  if ($) {
    return new Some(core.last_seen_sequence_number);
  } else {
    return Option$None$const;
  }
}

/**
 * The hand-off from the catch-up of a reconnect to the live traffic.
 *
 * This function is the equivalent of `settle_bootstrap`, for the route that
 * never passes through it. It exists so that exactly one place on this path
 * puts `ingest` back at `Live`. The replay position thus cannot outlast the
 * gap and disable `quorum_of` for the rest of the session.
 */
export function go_live(core) {
  return new Core(
    core.client_id,
    core.channels,
    core.channel_order,
    core.detached,
    core.next_client_sequence_number,
    core.last_seen_sequence_number,
    core.in_flight,
    core.out_of_order,
    core.members,
    core.live_members,
    IngestPosition$Live$const,
    core.last_summary_sequence_number,
    core.summary_head,
    core.owed,
  );
}

/**
 * Stamp a directory operation again on a reconnect.
 * `directory_kernel.resubmit` filters the operation against the current live
 * instance of its target path. A `Some` result means that the runtime sends
 * the operation again, and the kernel can have rewritten it, because a
 * resubmit of a create adds the creator id of this client again. A `None`
 * result means that the target instance no longer exists. The runtime drops
 * the operation, and the kernel removes its pending entry.
 * 
 * @ignore
 */
function restamp_directory(
  core,
  address,
  operation,
  message_id,
  client_sequence_number
) {
  let $ = $dict.get(core.channels, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.DirectoryState) {
      let kernel = $1[0];
      let self = client_id_to_int(core.client_id);
      let $2 = $directory_kernel.resubmit(kernel, operation, message_id, self);
      let kernel$1 = $2[0];
      let maybe_operation = $2[1];
      let core$1 = put_attached_channel(
        core,
        address,
        new $channel.DirectoryState(kernel$1),
      );
      if (maybe_operation instanceof Some) {
        let next_operation = maybe_operation[0];
        let next_channel_operation = new $channel.DirectoryOperation(
          next_operation,
          message_id,
        );
        return [
          core$1,
          client_sequence_number + 1,
          toList([
            new InFlightOperation(
              core$1.client_id,
              client_sequence_number,
              address,
              next_channel_operation,
              new $channel.DirectoryMeta(message_id),
            ),
          ]),
          toList([
            $wire_op.outbound_channel_operation(
              address,
              client_sequence_number,
              core$1.last_seen_sequence_number,
              next_channel_operation,
            ),
          ]),
        ];
      } else {
        return [
          core$1,
          client_sequence_number,
          $List$Empty$const,
          $List$Empty$const,
        ];
      }
    } else {
      return [
        core,
        client_sequence_number,
        $List$Empty$const,
        $List$Empty$const,
      ];
    }
  } else {
    return [core, client_sequence_number, $List$Empty$const, $List$Empty$const];
  }
}

function restamp_task_manager(
  core,
  address,
  operation,
  meta,
  client_sequence_number
) {
  let $ = $dict.get(core.channels, address);
  if ($ instanceof Ok && meta instanceof $channel.TaskManagerMeta) {
    let $1 = $[0];
    if ($1 instanceof $channel.TaskManagerState) {
      let message_id = meta.message_id;
      let kernel = $1[0];
      let $2 = $task_manager_kernel.resubmit(
        kernel,
        operation,
        message_id,
        client_sequence_number,
      );
      if ($2 instanceof Ok) {
        let $3 = $2[0][1];
        if ($3 instanceof Some) {
          let $4 = $2[0][2];
          if ($4 instanceof Some) {
            let kernel$1 = $2[0][0];
            let next_operation = $3[0];
            let pending = $4[0];
            let next_channel_operation = new $channel.TaskManagerOperation(
              next_operation,
            );
            let next_meta = new $channel.TaskManagerMeta(pending.message_id);
            let core$1 = put_attached_channel(
              core,
              address,
              new $channel.TaskManagerState(kernel$1),
            );
            return [
              core$1,
              client_sequence_number + 1,
              toList([
                new InFlightOperation(
                  core$1.client_id,
                  client_sequence_number,
                  address,
                  next_channel_operation,
                  next_meta,
                ),
              ]),
              toList([
                $wire_op.outbound_channel_operation(
                  address,
                  client_sequence_number,
                  core$1.last_seen_sequence_number,
                  next_channel_operation,
                ),
              ]),
            ];
          } else {
            return [
              core,
              client_sequence_number,
              $List$Empty$const,
              $List$Empty$const,
            ];
          }
        } else {
          let $4 = $2[0][2];
          if ($4 instanceof None) {
            let kernel$1 = $2[0][0];
            let core$1 = put_attached_channel(
              core,
              address,
              new $channel.TaskManagerState(kernel$1),
            );
            return [
              core$1,
              client_sequence_number,
              $List$Empty$const,
              $List$Empty$const,
            ];
          } else {
            return [
              core,
              client_sequence_number,
              $List$Empty$const,
              $List$Empty$const,
            ];
          }
        }
      } else {
        return [
          core,
          client_sequence_number,
          $List$Empty$const,
          $List$Empty$const,
        ];
      }
    } else {
      return [
        core,
        client_sequence_number,
        $List$Empty$const,
        $List$Empty$const,
      ];
    }
  } else {
    return [core, client_sequence_number, $List$Empty$const, $List$Empty$const];
  }
}

function restamp_in_flight(core, entry, client_sequence_number) {
  if (entry instanceof InFlightOperation) {
    let $ = entry.operation;
    if ($ instanceof $channel.TaskManagerOperation) {
      let address = entry.address;
      let meta = entry.meta;
      let operation = $[0];
      return restamp_task_manager(
        core,
        address,
        operation,
        meta,
        client_sequence_number,
      );
    } else if ($ instanceof $channel.DirectoryOperation) {
      let address = entry.address;
      let operation = $.operation;
      let message_id = $.message_id;
      return restamp_directory(
        core,
        address,
        operation,
        message_id,
        client_sequence_number,
      );
    } else {
      let address = entry.address;
      let operation = $;
      let meta = entry.meta;
      return [
        core,
        client_sequence_number + 1,
        toList([
          new InFlightOperation(
            core.client_id,
            client_sequence_number,
            address,
            operation,
            meta,
          ),
        ]),
        toList([
          $wire_op.outbound_channel_operation(
            address,
            client_sequence_number,
            core.last_seen_sequence_number,
            operation,
          ),
        ]),
      ];
    }
  } else {
    let address = entry.address;
    let snapshot = entry.snapshot;
    return [
      core,
      client_sequence_number + 1,
      toList([
        new InFlightAttach(
          core.client_id,
          client_sequence_number,
          address,
          snapshot,
        ),
      ]),
      toList([
        $wire_op.outbound_attach_operation(
          address,
          client_sequence_number,
          core.last_seen_sequence_number,
          snapshot,
        ),
      ]),
    ];
  }
}

export function resubmit(core) {
  let $ = $list.fold(
    core.in_flight,
    [
      core,
      core.next_client_sequence_number,
      $List$Empty$const,
      $List$Empty$const,
    ],
    (acc, entry) => {
      let core$1 = acc[0];
      let client_sequence_number = acc[1];
      let entries$1 = acc[2];
      let outbounds = acc[3];
      let $1 = restamp_in_flight(core$1, entry, client_sequence_number);
      let core$2 = $1[0];
      let next_client_sequence_number = $1[1];
      let restamped = $1[2];
      let outbound = $1[3];
      return [
        core$2,
        next_client_sequence_number,
        $list.append(entries$1, restamped),
        $list.append(outbounds, outbound),
      ];
    },
  );
  let core$1 = $[0];
  let next_client_sequence_number = $[1];
  let new_in_flight = $[2];
  let outbound = $[3];
  return [
    new Core(
      core$1.client_id,
      core$1.channels,
      core$1.channel_order,
      core$1.detached,
      next_client_sequence_number,
      core$1.last_seen_sequence_number,
      new_in_flight,
      core$1.out_of_order,
      core$1.members,
      core$1.live_members,
      core$1.ingest,
      core$1.last_summary_sequence_number,
      core$1.summary_head,
      core$1.owed,
    ),
    outbound,
  ];
}

export function create_detached(core, address, init) {
  let $ = (address === root_address) || has_channel(core, address);
  if ($) {
    return core;
  } else {
    return new Core(
      core.client_id,
      core.channels,
      core.channel_order,
      $dict.insert(core.detached, address, $channel.new$(init, core.client_id)),
      core.next_client_sequence_number,
      core.last_seen_sequence_number,
      core.in_flight,
      core.out_of_order,
      core.members,
      core.live_members,
      core.ingest,
      core.last_summary_sequence_number,
      core.summary_head,
      core.owed,
    );
  }
}

export function delete$(core, address, key) {
  let $ = locate_map(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $map_kernel.delete$(kernel, key);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(core, address, new $channel.MapState(kernel$1)),
          tag_map_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $map_kernel.delete$(kernel, key);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.MapState(kernel$1),
          tag_map_events(address, events),
          new $channel.MapOperation(operation),
          $channel.LocalOperationMeta$NoMeta$const,
        ),
      );
    }
  } else {
    return $;
  }
}

export function clear(core, address) {
  let $ = locate_map(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $map_kernel.clear(kernel);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(core, address, new $channel.MapState(kernel$1)),
          tag_map_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $map_kernel.clear(kernel);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.MapState(kernel$1),
          tag_map_events(address, events),
          new $channel.MapOperation(operation),
          $channel.LocalOperationMeta$NoMeta$const,
        ),
      );
    }
  } else {
    return $;
  }
}

function tag_counter_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.CounterEvent(event)]; },
  );
}

function locate_counter(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.CounterState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$CounterChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.CounterState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$CounterChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

export function increment(core, address, amount) {
  let $ = locate_counter(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $counter_kernel.increment(kernel, amount);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.CounterState(kernel$1),
          ),
          tag_counter_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $counter_kernel.increment(kernel, amount);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      let message_id = $2[3];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.CounterState(kernel$1),
          tag_counter_events(address, events),
          new $channel.CounterOperation(operation),
          new $channel.CounterMeta(message_id),
        ),
      );
    }
  } else {
    return $;
  }
}

function tag_pn_counter_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.PnCounterEvent(event)]; },
  );
}

function locate_pn_counter(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.PnCounterState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$PnCounterChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.PnCounterState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$PnCounterChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

/**
 * Apply a signed update to the PN-counter at `address` optimistically. That
 * update is an increment or a decrement. The optimistic lifecycle is the same
 * as for `increment`.
 */
export function pn_counter_update(core, address, amount) {
  let $ = locate_pn_counter(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $pn_counter_kernel.update(kernel, amount);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.PnCounterState(kernel$1),
          ),
          tag_pn_counter_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $pn_counter_kernel.update(kernel, amount);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      let message_id = $2[3];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.PnCounterState(kernel$1),
          tag_pn_counter_events(address, events),
          new $channel.PnCounterOperation(operation),
          new $channel.PnCounterMeta(message_id),
        ),
      );
    }
  } else {
    return $;
  }
}

function tag_g_counter_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.GCounterEvent(event)]; },
  );
}

function locate_g_counter(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.GCounterState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$GCounterChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.GCounterState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$GCounterChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

/**
 * Increment the grow-only counter at `address` optimistically. The amount
 * must not be negative. A refused edit changes nothing and sends nothing.
 */
export function g_counter_increment(core, address, amount) {
  return $result.try$(
    locate_g_counter(core, address),
    (located) => {
      if (located instanceof Detached) {
        let kernel = located[0];
        return $result.try$(
          (() => {
            let _pipe = $g_counter_kernel.increment(kernel, amount);
            return $result.map_error(
              _pipe,
              (error) => {
                return new GCounterOperationFailed(
                  address,
                  $g_counter_kernel.edit_error_text(error),
                );
              },
            );
          })(),
          (_use0) => {
            let kernel$1 = _use0[0];
            let events = _use0[1];
            return new Ok(
              [
                put_detached_channel(
                  core,
                  address,
                  new $channel.GCounterState(kernel$1),
                ),
                tag_g_counter_events(address, events),
                $List$Empty$const,
              ],
            );
          },
        );
      } else {
        let kernel = located[0];
        return $result.try$(
          (() => {
            let _pipe = $g_counter_kernel.increment(kernel, amount);
            return $result.map_error(
              _pipe,
              (error) => {
                return new GCounterOperationFailed(
                  address,
                  $g_counter_kernel.edit_error_text(error),
                );
              },
            );
          })(),
          (_use0) => {
            let kernel$1 = _use0[0];
            let events = _use0[1];
            let operation = _use0[2];
            let message_id = _use0[3];
            return new Ok(
              stamp_attached(
                core,
                address,
                new $channel.GCounterState(kernel$1),
                tag_g_counter_events(address, events),
                new $channel.GCounterOperation(operation),
                new $channel.GCounterMeta(message_id),
              ),
            );
          },
        );
      }
    },
  );
}

/**
 * Set the register optimistically. The timestamp is a wall-clock input;
 * the kernel advances it past every timestamp that this writer has seen.
 */
export function lww_register_set(core, address, value, timestamp) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      let _block;
      if (located instanceof Detached) {
        let state = located[0];
        _block = state;
      } else {
        let state = located[0];
        _block = state;
      }
      let state = _block;
      return $result.try$(
        (() => {
          if (state instanceof $channel.LwwRegisterState) {
            let kernel = state[0];
            return new Ok(kernel);
          } else {
            let other = state;
            return new Error(
              new WrongChannelType(
                address,
                $channel.ChannelType$LwwRegisterChannel$const,
                $channel.channel_type(other),
              ),
            );
          }
        })(),
        (kernel) => {
          return $result.try$(
            (() => {
              let _pipe = $lww_register_kernel.set(kernel, value, timestamp);
              return $result.map_error(
                _pipe,
                (error) => {
                  return new LwwRegisterOperationFailed(
                    address,
                    $channel.lww_register_error_detail(error),
                  );
                },
              );
            })(),
            (_use0) => {
              let kernel$1 = _use0[0];
              let events = _use0[1];
              let operation = _use0[2];
              let message_id = _use0[3];
              let state$1 = new $channel.LwwRegisterState(kernel$1);
              let events$1 = $list.map(
                events,
                (event) => {
                  return [address, new $channel.LwwRegisterEvent(event)];
                },
              );
              if (located instanceof Detached) {
                return new Ok(
                  [
                    put_detached_channel(core, address, state$1),
                    events$1,
                    $List$Empty$const,
                  ],
                );
              } else {
                return new Ok(
                  stamp_attached(
                    core,
                    address,
                    state$1,
                    events$1,
                    new $channel.LwwRegisterOperation(operation),
                    new $channel.LwwRegisterMeta(message_id),
                  ),
                );
              }
            },
          );
        },
      );
    },
  );
}

function find_channel(core, address) {
  let _pipe = $dict.get(core.channels, address);
  return $result.lazy_or(
    _pipe,
    () => { return $dict.get(core.detached, address); },
  );
}

export function lww_register_value(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.LwwRegisterState) {
      let kernel = $1[0];
      return new Ok($lww_register_kernel.value(kernel));
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

function edit_lww_map(core, address, edit) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      let _block;
      if (located instanceof Detached) {
        let state = located[0];
        _block = state;
      } else {
        let state = located[0];
        _block = state;
      }
      let state = _block;
      return $result.try$(
        (() => {
          if (state instanceof $channel.LwwMapState) {
            let kernel = state[0];
            return new Ok(kernel);
          } else {
            let other = state;
            return new Error(
              new WrongChannelType(
                address,
                $channel.ChannelType$LwwMapChannel$const,
                $channel.channel_type(other),
              ),
            );
          }
        })(),
        (kernel) => {
          return $result.try$(
            (() => {
              let _pipe = edit(kernel);
              return $result.map_error(
                _pipe,
                (error) => {
                  return new LwwMapOperationFailed(
                    address,
                    $channel.lww_map_error_detail(error),
                  );
                },
              );
            })(),
            (_use0) => {
              let kernel$1 = _use0[0];
              let events = _use0[1];
              let operation = _use0[2];
              let message_id = _use0[3];
              let state$1 = new $channel.LwwMapState(kernel$1);
              let events$1 = $list.map(
                events,
                (event) => { return [address, new $channel.LwwMapEvent(event)]; },
              );
              if (located instanceof Detached) {
                return new Ok(
                  [
                    put_detached_channel(core, address, state$1),
                    events$1,
                    $List$Empty$const,
                  ],
                );
              } else {
                return new Ok(
                  stamp_attached(
                    core,
                    address,
                    state$1,
                    events$1,
                    new $channel.LwwMapOperation(operation),
                    new $channel.LwwMapMeta(message_id),
                  ),
                );
              }
            },
          );
        },
      );
    },
  );
}

export function lww_map_set(core, address, key, value, timestamp) {
  return edit_lww_map(
    core,
    address,
    (kernel) => { return $lww_map_kernel.set(kernel, key, value, timestamp); },
  );
}

export function lww_map_remove(core, address, key, timestamp) {
  return edit_lww_map(
    core,
    address,
    (kernel) => { return $lww_map_kernel.remove(kernel, key, timestamp); },
  );
}

export function lww_map_get(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.LwwMapState) {
      let kernel = $1[0];
      return $lww_map_kernel.get(kernel, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function lww_map_entries(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.LwwMapState) {
      let kernel = $1[0];
      return $lww_map_kernel.entries(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function lww_map_keys(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.LwwMapState) {
      let kernel = $1[0];
      return $lww_map_kernel.keys(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function mv_register_set(core, address, value) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.MvRegisterState) {
          let kernel = $[0];
          let $1 = $mv_register_kernel.set(kernel, value);
          let kernel$1 = $1[0];
          let events = $1[1];
          return new Ok(
            [
              put_detached_channel(
                core,
                address,
                new $channel.MvRegisterState(kernel$1),
              ),
              $list.map(
                events,
                (event) => {
                  return [address, new $channel.MvRegisterEvent(event)];
                },
              ),
              $List$Empty$const,
            ],
          );
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$MvRegisterChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.MvRegisterState) {
          let kernel = $[0];
          let $1 = $mv_register_kernel.set(kernel, value);
          let kernel$1 = $1[0];
          let events = $1[1];
          let operation = $1[2];
          let message_id = $1[3];
          return new Ok(
            stamp_attached(
              core,
              address,
              new $channel.MvRegisterState(kernel$1),
              $list.map(
                events,
                (event) => {
                  return [address, new $channel.MvRegisterEvent(event)];
                },
              ),
              new $channel.MvRegisterOperation(operation),
              new $channel.MvRegisterMeta(message_id),
            ),
          );
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$MvRegisterChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

export function mv_register_values(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.MvRegisterState) {
      let kernel = $1[0];
      return new Ok($mv_register_kernel.values(kernel));
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

function locate_pact_map(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.PactMapState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$PactMapChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.PactMapState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$PactMapChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

function pact_map_submit(core, address, produce) {
  let $ = locate_pact_map(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      return new Ok([core, $List$Empty$const, $List$Empty$const]);
    } else {
      let kernel = $1[0];
      let $2 = produce(kernel);
      if ($2 instanceof Ok) {
        let operation = $2[0];
        return new Ok(
          stamp_attached(
            core,
            address,
            new $channel.PactMapState(kernel),
            $List$Empty$const,
            new $channel.PactMapOperation(operation),
            $channel.LocalOperationMeta$NoMeta$const,
          ),
        );
      } else {
        return new Ok([core, $List$Empty$const, $List$Empty$const]);
      }
    }
  } else {
    return $;
  }
}

/**
 * Propose `value` for `key` in the PactMap at `address`. `value` is a JSON
 * payload, or `None` for a delete. Unlike an optimistic kernel, a consensus
 * PactMap does **not** apply the value locally. The kernel returns the
 * operation to submit, or a `ProposeError` value when a value is already
 * pending for the key, which changes nothing. The value takes effect when the
 * `Set` operation sequences. The released-operations loop emits the `Accept`
 * operation of the setter by itself.
 */
export function pact_map_set(core, address, key, value) {
  return pact_map_submit(
    core,
    address,
    (kernel) => {
      return $pact_map_kernel.set(
        kernel,
        key,
        new Some(value),
        core.last_seen_sequence_number,
      );
    },
  );
}

/**
 * Propose a delete for `key` in the PactMap at `address`. A delete writes a
 * tombstone. This function submits an operation only, the same as
 * `pact_map_set`, and the delete takes effect when that operation sequences. A
 * `ProposeError` value from the kernel changes nothing. The kernel gives that
 * result when a value is already pending, when the key is absent, and when the
 * key already holds a tombstone.
 */
export function pact_map_delete(core, address, key) {
  return pact_map_submit(
    core,
    address,
    (kernel) => {
      return $pact_map_kernel.delete$(
        kernel,
        key,
        core.last_seen_sequence_number,
      );
    },
  );
}

function tag_ordered_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.OrderedCollectionEvent(event)]; },
  );
}

function locate_ordered(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.OrderedCollectionState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$OrderedCollectionChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.OrderedCollectionState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$OrderedCollectionChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

/**
 * Append `value` to the queue at `address`. An attached channel is not
 * optimistic, and the value takes effect when the operation sequences, through
 * the ack of that operation. A detached channel applies the value immediately,
 * and its attach carries the add.
 */
export function ordered_add(core, address, value) {
  let $ = locate_ordered(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $ordered_collection_kernel.add_detached(kernel, value);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.OrderedCollectionState(kernel$1),
          ),
          tag_ordered_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let operation = $ordered_collection_kernel.add(kernel, value);
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.OrderedCollectionState(kernel),
          $List$Empty$const,
          new $channel.OrderedCollectionOperation(operation),
          $channel.LocalOperationMeta$NoMeta$const,
        ),
      );
    }
  } else {
    return $;
  }
}

/**
 * The same as `ordered_acquire`, and the function also reports the immediate
 * outcome. The result is `Some` for a detached channel, where the acquire took
 * effect in this call. The result is `None` for an attached channel. There the
 * outcome arrives as an `AcquireResolved` resolution when the operation
 * sequences, keyed by `acquire_id`.
 */
export function ordered_acquire_submit(core, address, acquire_id) {
  let $ = locate_ordered(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $ordered_collection_kernel.acquire_detached(kernel, acquire_id);
      let kernel$1 = $2[0];
      let events = $2[1];
      let outcome = $2[2];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.OrderedCollectionState(kernel$1),
          ),
          tag_ordered_events(address, events),
          $List$Empty$const,
          new Some(outcome),
        ],
      );
    } else {
      let kernel = $1[0];
      let operation = $ordered_collection_kernel.acquire(acquire_id);
      let $2 = stamp_attached(
        core,
        address,
        new $channel.OrderedCollectionState(kernel),
        $List$Empty$const,
        new $channel.OrderedCollectionOperation(operation),
        $channel.LocalOperationMeta$NoMeta$const,
      );
      let core$1 = $2[0];
      let events = $2[1];
      let outbound = $2[2];
      return new Ok([core$1, events, outbound, Option$None$const]);
    }
  } else {
    return $;
  }
}

/**
 * Acquire the head of the queue at `address`, under the `acquire_id` value that
 * the caller supplies. Create that id in the runtime layer, with
 * `id.uuid_v4`. An attached channel is not optimistic. The kernel removes the
 * item when the operation sequences, and the `Acquired` event delivers it. The
 * `acquire_id` value is the key of the later `complete` or `release` call. A
 * detached channel acquires the item immediately.
 */
export function ordered_acquire(core, address, acquire_id) {
  let _pipe = ordered_acquire_submit(core, address, acquire_id);
  return $result.map(
    _pipe,
    (submitted) => { return [submitted[0], submitted[1], submitted[2]]; },
  );
}

function ordered_submit(core, address, operation) {
  let $ = locate_ordered(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      return new Ok([core, $List$Empty$const, $List$Empty$const]);
    } else {
      let kernel = $1[0];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.OrderedCollectionState(kernel),
          $List$Empty$const,
          new $channel.OrderedCollectionOperation(operation),
          $channel.LocalOperationMeta$NoMeta$const,
        ),
      );
    }
  } else {
    return $;
  }
}

/**
 * Complete the held job `acquire_id` in the queue at `address`, which removes
 * it. The function does nothing on a detached channel, because there is nothing
 * to complete without a sequencer.
 */
export function ordered_complete(core, address, acquire_id) {
  return ordered_submit(
    core,
    address,
    $ordered_collection_kernel.complete(acquire_id),
  );
}

/**
 * Release the held job `acquire_id` in the queue at `address` back to the end
 * of that queue. The function does nothing on a detached channel.
 */
export function ordered_release(core, address, acquire_id) {
  return ordered_submit(
    core,
    address,
    $ordered_collection_kernel.release(acquire_id),
  );
}

function directory_detail(error) {
  if (error instanceof $directory_kernel.UnexpectedAck) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $directory_kernel.UnexpectedRollback) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $directory_kernel.PathNotFound) {
    let path = error.path;
    return "path not found: " + path;
  } else if (error instanceof $directory_kernel.InvalidName) {
    let name = error.name;
    return "invalid subdirectory name: " + name;
  } else {
    let detail = error.detail;
    return detail;
  }
}

function tag_directory_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.DirectoryEvent(event)]; },
  );
}

function locate_directory(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.DirectoryState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$DirectoryChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.DirectoryState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$DirectoryChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

/**
 * A storage operation, which is a `set`, a `delete`, or a `clear`, always
 * produces an outbound operation on an attached channel. The kernel returns
 * the state, the events, the operation, and the message id.
 * 
 * @ignore
 */
function directory_storage_edit(core, address, dependency_value, run) {
  let $ = locate_directory(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = run(kernel);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.DirectoryState(kernel$1),
            ),
            tag_directory_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(
          new DirectoryOperationFailed(address, directory_detail(error)),
        );
      }
    } else {
      let kernel = $1[0];
      let $2 = run(kernel);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        let operation = $2[0][2];
        let message_id = $2[0][3];
        let _block;
        if (dependency_value instanceof Some) {
          let value = dependency_value[0];
          _block = attach_dependencies(core, value);
        } else {
          _block = [core, $List$Empty$const];
        }
        let $3 = _block;
        let core$1 = $3[0];
        let attach_outbound = $3[1];
        let $4 = stamp_attached(
          core$1,
          address,
          new $channel.DirectoryState(kernel$1),
          tag_directory_events(address, events),
          new $channel.DirectoryOperation(operation, message_id),
          new $channel.DirectoryMeta(message_id),
        );
        let core$2 = $4[0];
        let events$1 = $4[1];
        let outbound = $4[2];
        return new Ok(
          [core$2, events$1, $list.append(attach_outbound, outbound)],
        );
      } else {
        let error = $2[0];
        return new Error(
          new DirectoryOperationFailed(address, directory_detail(error)),
        );
      }
    }
  } else {
    return $;
  }
}

/**
 * Set `key` to `value` in the directory at `path`. The write is optimistic. The
 * local value appears immediately, and the operation sequences and receives an
 * ack, the same as any other operation.
 */
export function directory_set(core, address, path, key, value) {
  return directory_storage_edit(
    core,
    address,
    new Some(value),
    (kernel) => { return $directory_kernel.set(kernel, path, key, value); },
  );
}

export function directory_delete(core, address, path, key) {
  return directory_storage_edit(
    core,
    address,
    Option$None$const,
    (kernel) => { return $directory_kernel.delete$(kernel, path, key); },
  );
}

export function directory_clear(core, address, path) {
  return directory_storage_edit(
    core,
    address,
    Option$None$const,
    (kernel) => { return $directory_kernel.clear(kernel, path); },
  );
}

/**
 * A subdirectory operation, which is a `create` or a `delete`, can produce no
 * outbound operation. A duplicate create, and a delete of a child that the
 * optimistic view does not contain, both update the local state and emit
 * events, and they send nothing.
 * 
 * @ignore
 */
function directory_subdirectory_edit(core, address, run) {
  let $ = locate_directory(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = run(kernel);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.DirectoryState(kernel$1),
            ),
            tag_directory_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(
          new DirectoryOperationFailed(address, directory_detail(error)),
        );
      }
    } else {
      let kernel = $1[0];
      let $2 = run(kernel);
      if ($2 instanceof Ok) {
        let $3 = $2[0][2];
        if ($3 instanceof Some) {
          let kernel$1 = $2[0][0];
          let events = $2[0][1];
          let message_id = $2[0][3];
          let operation = $3[0];
          return new Ok(
            stamp_attached(
              core,
              address,
              new $channel.DirectoryState(kernel$1),
              tag_directory_events(address, events),
              new $channel.DirectoryOperation(operation, message_id),
              new $channel.DirectoryMeta(message_id),
            ),
          );
        } else {
          let kernel$1 = $2[0][0];
          let events = $2[0][1];
          return new Ok(
            [
              put_attached_channel(
                core,
                address,
                new $channel.DirectoryState(kernel$1),
              ),
              tag_directory_events(address, events),
              $List$Empty$const,
            ],
          );
        }
      } else {
        let error = $2[0];
        return new Error(
          new DirectoryOperationFailed(address, directory_detail(error)),
        );
      }
    }
  } else {
    return $;
  }
}

export function directory_create_subdirectory(core, address, path, name) {
  let self = client_id_to_int(core.client_id);
  return directory_subdirectory_edit(
    core,
    address,
    (kernel) => {
      return $directory_kernel.create_subdirectory(kernel, path, name, self);
    },
  );
}

export function directory_delete_subdirectory(core, address, path, name) {
  return directory_subdirectory_edit(
    core,
    address,
    (kernel) => {
      return $directory_kernel.delete_subdirectory(kernel, path, name);
    },
  );
}

function json_ot_kernel_error_detail(error) {
  if (error instanceof $json_ot_kernel.UnexpectedAck) {
    let detail = error.detail;
    return detail;
  } else {
    let ot = error.error;
    if (ot instanceof $json_ot.BadPath) {
      let detail = ot.detail;
      return "json0 bad path: " + detail;
    } else if (ot instanceof $json_ot.BadValue) {
      let detail = ot.detail;
      return "json0 bad value: " + detail;
    } else {
      let name = ot.name;
      return "json0 unknown subtype: " + name;
    }
  }
}

function tag_json_ot_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.JsonOtEvent(event)]; },
  );
}

function locate_json_ot(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.JsonOtState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$JsonOtChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.JsonOtState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$JsonOtChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

/**
 * Submit a json0 operation that the client wrote against the current
 * optimistic view of the channel. The one-operation-in-flight kernel sends the
 * operation immediately when no operation is in flight. If one is in flight,
 * the kernel composes the new operation into the buffer and releases it on the
 * next ack, in `collect_released_operations`. One operation is thus on the
 * wire at a time, at most.
 */
export function submit_json_ot(core, address, components) {
  let $ = locate_json_ot(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $json_ot_kernel.submit(
        kernel,
        components,
        core.last_seen_sequence_number,
      );
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][2];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.JsonOtState(kernel$1),
            ),
            tag_json_ot_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(new AckMismatch(json_ot_kernel_error_detail(error)));
      }
    } else {
      let kernel = $1[0];
      let $2 = $json_ot_kernel.submit(
        kernel,
        components,
        core.last_seen_sequence_number,
      );
      if ($2 instanceof Ok) {
        let $3 = $2[0][1];
        if ($3 instanceof Some) {
          let kernel$1 = $2[0][0];
          let events = $2[0][2];
          let wire = $3[0];
          return new Ok(
            stamp_attached(
              core,
              address,
              new $channel.JsonOtState(kernel$1),
              tag_json_ot_events(address, events),
              new $channel.JsonOtOperation(wire),
              $channel.LocalOperationMeta$NoMeta$const,
            ),
          );
        } else {
          let kernel$1 = $2[0][0];
          let events = $2[0][2];
          return new Ok(
            [
              put_attached_channel(
                core,
                address,
                new $channel.JsonOtState(kernel$1),
              ),
              tag_json_ot_events(address, events),
              $List$Empty$const,
            ],
          );
        }
      } else {
        let error = $2[0];
        return new Error(new AckMismatch(json_ot_kernel_error_detail(error)));
      }
    }
  } else {
    return $;
  }
}

/**
 * The current optimistic json0 document of the channel. The result is `Error(Nil)`
 * when the address does not name a json0 channel, and when the core cannot
 * compute the view.
 */
export function json_ot_view(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.JsonOtState) {
      let kernel = $1[0];
      let _pipe = $json_ot_kernel.view(kernel);
      return $result.replace_error(_pipe, undefined);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

function rich_text_kernel_error_detail(error) {
  if (error instanceof $rich_text_kernel.UnexpectedAck) {
    let detail = error.detail;
    return detail;
  } else {
    let algebra = error.error;
    if (algebra instanceof $rich_text.Malformed) {
      let component = algebra.component;
      let reason = algebra.reason;
      return (("rich-text malformed " + component) + ": ") + reason;
    } else if (algebra instanceof $rich_text.InvalidApply) {
      let reason = algebra.reason;
      return "rich-text invalid apply: " + reason;
    } else {
      let offset = algebra.offset;
      return "rich-text invalid boundary at offset " + $int.to_string(offset);
    }
  }
}

function tag_rich_text_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.RichTextEvent(event)]; },
  );
}

function locate_rich_text(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.RichTextState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$RichTextChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.RichTextState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$RichTextChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

/**
 * Submit a rich-text delta that the client wrote against the current optimistic
 * document of the channel. The behaviour is the same as for json0. The kernel
 * sends one delta immediately, and it buffers each later delta until
 * `collect_released_operations` takes the promoted outbound operation of the
 * kernel.
 */
export function submit_rich_text(core, address, delta) {
  let $ = locate_rich_text(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $rich_text_kernel.submit(
        kernel,
        delta,
        core.last_seen_sequence_number,
      );
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][2];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.RichTextState(kernel$1),
            ),
            tag_rich_text_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(new AckMismatch(rich_text_kernel_error_detail(error)));
      }
    } else {
      let kernel = $1[0];
      let $2 = $rich_text_kernel.submit(
        kernel,
        delta,
        core.last_seen_sequence_number,
      );
      if ($2 instanceof Ok) {
        let $3 = $2[0][1];
        if ($3 instanceof Some) {
          let kernel$1 = $2[0][0];
          let events = $2[0][2];
          let wire = $3[0];
          return new Ok(
            stamp_attached(
              core,
              address,
              new $channel.RichTextState(kernel$1),
              tag_rich_text_events(address, events),
              new $channel.RichTextOperation(wire),
              $channel.LocalOperationMeta$NoMeta$const,
            ),
          );
        } else {
          let kernel$1 = $2[0][0];
          let events = $2[0][2];
          return new Ok(
            [
              put_attached_channel(
                core,
                address,
                new $channel.RichTextState(kernel$1),
              ),
              tag_rich_text_events(address, events),
              $List$Empty$const,
            ],
          );
        }
      } else {
        let error = $2[0];
        return new Error(new AckMismatch(rich_text_kernel_error_detail(error)));
      }
    }
  } else {
    return $;
  }
}

/**
 * The current optimistic rich-text document of the channel. The result is
 * `Error(Nil)` when the address does not name a rich-text channel, and when the core
 * cannot compute the view.
 */
export function rich_text_view(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.RichTextState) {
      let kernel = $1[0];
      let _pipe = $rich_text_kernel.view(kernel);
      return $result.replace_error(_pipe, undefined);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * Convert an error of the or-map kernel into a `CoreError` value. A mode
 * mismatch is incorrect use of the API. Set-state and clock failures retain
 * the channel address. Legacy errors retain their existing mapping.
 * 
 * @ignore
 */
function or_map_kernel_error(address, error) {
  if (error instanceof $or_map_kernel.UnexpectedAck) {
    let detail = error.detail;
    return new AckMismatch(detail);
  } else if (error instanceof $or_map_kernel.UnexpectedRollback) {
    let detail = error.detail;
    return new AckMismatch(detail);
  } else if (error instanceof $or_map_kernel.ModeMismatch) {
    let detail = error.detail;
    return new OrMapModeMismatch(address, detail);
  } else if (error instanceof $or_map_kernel.CorruptDelta) {
    let detail = error.detail;
    return new AckMismatch(detail);
  } else if (error instanceof $or_map_kernel.InvalidSetState) {
    let detail = error.detail;
    return new OrMapOperationFailed(address, detail);
  } else if (error instanceof $or_map_kernel.CounterExhausted) {
    let detail = error.detail;
    return new OrMapOperationFailed(address, detail);
  } else {
    let detail = error.detail;
    return new AckMismatch(detail);
  }
}

function tag_or_map_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.OrMapEvent(event)]; },
  );
}

function locate_or_map(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.OrMapState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$OrMapChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.OrMapState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$OrMapChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

export function or_map_increment(core, address, key, amount) {
  let $ = locate_or_map(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $or_map_kernel.increment(kernel, key, amount);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.OrMapState(kernel$1),
            ),
            tag_or_map_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(or_map_kernel_error(address, error));
      }
    } else {
      let kernel = $1[0];
      let $2 = $or_map_kernel.increment(kernel, key, amount);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        let operation = $2[0][2];
        let message_id = $2[0][3];
        return new Ok(
          stamp_attached(
            core,
            address,
            new $channel.OrMapState(kernel$1),
            tag_or_map_events(address, events),
            new $channel.OrMapOperation(operation),
            new $channel.OrMapMeta(message_id),
          ),
        );
      } else {
        let error = $2[0];
        return new Error(or_map_kernel_error(address, error));
      }
    }
  } else {
    return $;
  }
}

function attach_dependencies_from_register_string(core, value) {
  let $ = $json.parse(value, $wire.json_value_decoder());
  if ($ instanceof Ok) {
    let json_value = $[0];
    return attach_dependencies(core, json_value);
  } else {
    return [core, $List$Empty$const];
  }
}

export function or_map_set(core, address, key, value, timestamp) {
  let $ = locate_or_map(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $or_map_kernel.set_register(kernel, key, value, timestamp);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.OrMapState(kernel$1),
            ),
            tag_or_map_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(or_map_kernel_error(address, error));
      }
    } else {
      let $2 = attach_dependencies_from_register_string(core, value);
      let core$1 = $2[0];
      let attach_outbound = $2[1];
      return $result.try$(
        locate_or_map(core$1, address),
        (located) => {
          let _block;
          if (located instanceof Detached) {
            let kernel = located[0];
            _block = kernel;
          } else {
            let kernel = located[0];
            _block = kernel;
          }
          let kernel = _block;
          let $3 = $or_map_kernel.set_register(kernel, key, value, timestamp);
          if ($3 instanceof Ok) {
            let kernel$1 = $3[0][0];
            let events = $3[0][1];
            let operation = $3[0][2];
            let message_id = $3[0][3];
            let $4 = stamp_attached(
              core$1,
              address,
              new $channel.OrMapState(kernel$1),
              tag_or_map_events(address, events),
              new $channel.OrMapOperation(operation),
              new $channel.OrMapMeta(message_id),
            );
            let core$2 = $4[0];
            let events$1 = $4[1];
            let outbound = $4[2];
            return new Ok(
              [core$2, events$1, $list.append(attach_outbound, outbound)],
            );
          } else {
            let error = $3[0];
            return new Error(or_map_kernel_error(address, error));
          }
        },
      );
    }
  } else {
    return $;
  }
}

function edit_or_map(core, address, edit) {
  return $result.try$(
    locate_or_map(core, address),
    (located) => {
      let _block;
      if (located instanceof Detached) {
        let kernel = located[0];
        _block = kernel;
      } else {
        let kernel = located[0];
        _block = kernel;
      }
      let kernel = _block;
      return $result.try$(
        (() => {
          let _pipe = edit(kernel);
          return $result.map_error(
            _pipe,
            (_capture) => { return or_map_kernel_error(address, _capture); },
          );
        })(),
        (_use0) => {
          let kernel$1 = _use0[0];
          let events = _use0[1];
          let operation = _use0[2];
          let message_id = _use0[3];
          let state = new $channel.OrMapState(kernel$1);
          let events$1 = tag_or_map_events(address, events);
          if (located instanceof Detached) {
            return new Ok(
              [
                put_detached_channel(core, address, state),
                events$1,
                $List$Empty$const,
              ],
            );
          } else {
            return new Ok(
              stamp_attached(
                core,
                address,
                state,
                events$1,
                new $channel.OrMapOperation(operation),
                new $channel.OrMapMeta(message_id),
              ),
            );
          }
        },
      );
    },
  );
}

export function or_map_add_member(core, address, key, member) {
  return edit_or_map(
    core,
    address,
    (_capture) => { return $or_map_kernel.add_member(_capture, key, member); },
  );
}

export function or_map_remove_member(core, address, key, member) {
  return edit_or_map(
    core,
    address,
    (_capture) => { return $or_map_kernel.remove_member(_capture, key, member); },
  );
}

export function or_map_set_mv_register(core, address, key, value) {
  return edit_or_map(
    core,
    address,
    (_capture) => {
      return $or_map_kernel.set_mv_register(_capture, key, value);
    },
  );
}

export function or_map_remove(core, address, key) {
  let $ = locate_or_map(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $or_map_kernel.remove(kernel, key);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.OrMapState(kernel$1),
            ),
            tag_or_map_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(or_map_kernel_error(address, error));
      }
    } else {
      let kernel = $1[0];
      let $2 = $or_map_kernel.remove(kernel, key);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        let operation = $2[0][2];
        let message_id = $2[0][3];
        return new Ok(
          stamp_attached(
            core,
            address,
            new $channel.OrMapState(kernel$1),
            tag_or_map_events(address, events),
            new $channel.OrMapOperation(operation),
            new $channel.OrMapMeta(message_id),
          ),
        );
      } else {
        let error = $2[0];
        return new Error(or_map_kernel_error(address, error));
      }
    }
  } else {
    return $;
  }
}

function tag_or_set_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.OrSetEvent(event)]; },
  );
}

function locate_or_set(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.OrSetState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$OrSetChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.OrSetState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$OrSetChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

export function or_set_add(core, address, element) {
  let $ = locate_or_set(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $or_set_kernel.add(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(core, address, new $channel.OrSetState(kernel$1)),
          tag_or_set_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $or_set_kernel.add(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      let message_id = $2[3];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.OrSetState(kernel$1),
          tag_or_set_events(address, events),
          new $channel.OrSetOperation(operation),
          new $channel.OrSetMeta(message_id),
        ),
      );
    }
  } else {
    return $;
  }
}

export function or_set_remove(core, address, element) {
  let $ = locate_or_set(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $or_set_kernel.remove(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(core, address, new $channel.OrSetState(kernel$1)),
          tag_or_set_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $or_set_kernel.remove(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      let message_id = $2[3];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.OrSetState(kernel$1),
          tag_or_set_events(address, events),
          new $channel.OrSetOperation(operation),
          new $channel.OrSetMeta(message_id),
        ),
      );
    }
  } else {
    return $;
  }
}

function tag_sequence_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.SequenceEvent(event)]; },
  );
}

function locate_sequence(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.SequenceState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$SequenceChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.SequenceState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$SequenceChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

function mutate_sequence(core, address, dependencies, mutate) {
  let $ = locate_sequence(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = mutate(kernel);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.SequenceState(kernel$1),
            ),
            tag_sequence_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(
          new SequenceOperationFailed(
            address,
            $sequence_kernel.edit_error_detail(error),
          ),
        );
      }
    } else {
      let kernel = $1[0];
      let $2 = mutate(kernel);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        let operation = $2[0][2];
        let message_id = $2[0][3];
        let _block;
        if (dependencies instanceof Some) {
          let value = dependencies[0];
          _block = attach_dependencies(core, value);
        } else {
          _block = [core, $List$Empty$const];
        }
        let $3 = _block;
        let core$1 = $3[0];
        let attach_outbound = $3[1];
        let $4 = stamp_attached(
          core$1,
          address,
          new $channel.SequenceState(kernel$1),
          tag_sequence_events(address, events),
          new $channel.SequenceOperation(operation),
          new $channel.SequenceMeta(message_id),
        );
        let core$2 = $4[0];
        let events$1 = $4[1];
        let outbound = $4[2];
        return new Ok(
          [core$2, events$1, $list.append(attach_outbound, outbound)],
        );
      } else {
        let error = $2[0];
        return new Error(
          new SequenceOperationFailed(
            address,
            $sequence_kernel.edit_error_detail(error),
          ),
        );
      }
    }
  } else {
    return $;
  }
}

export function sequence_insert(core, address, index, value) {
  return mutate_sequence(
    core,
    address,
    new Some(value),
    (_capture) => { return $sequence_kernel.insert(_capture, index, value); },
  );
}

export function sequence_delete(core, address, index) {
  return mutate_sequence(
    core,
    address,
    Option$None$const,
    (_capture) => { return $sequence_kernel.delete$(_capture, index); },
  );
}

export function sequence_move(core, address, from_index, to_index) {
  return mutate_sequence(
    core,
    address,
    Option$None$const,
    (_capture) => {
      return $sequence_kernel.move(_capture, from_index, to_index);
    },
  );
}

export function sequence_replace(core, address, index, value) {
  return mutate_sequence(
    core,
    address,
    new Some(value),
    (_capture) => { return $sequence_kernel.replace(_capture, index, value); },
  );
}

function tag_text_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.TextEvent(event)]; },
  );
}

function locate_text(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.TextState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$TextChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.TextState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$TextChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

/**
 * A text mutation returns an `Option(text_kernel.Submission)` value, and it
 * does not always produce an operation. A valid empty edit changes nothing.
 * See the module docs of `text_kernel`. A `Some` result updates the state,
 * emits the events, and, on an attached channel, stamps and submits one
 * channel operation. A `None` result changes no state and no submission
 * counter of the runtime, and it produces no event and no outbound operation.
 * 
 * @ignore
 */
function mutate_text(core, address, mutate) {
  let $ = locate_text(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = mutate(kernel);
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let events = $2[0][1];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.TextState(kernel$1),
            ),
            tag_text_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $2[0];
        return new Error(
          new TextOperationFailed(
            address,
            $text_kernel.edit_error_detail(error),
          ),
        );
      }
    } else {
      let kernel = $1[0];
      let $2 = mutate(kernel);
      if ($2 instanceof Ok) {
        let $3 = $2[0][2];
        if ($3 instanceof Some) {
          let kernel$1 = $2[0][0];
          let events = $2[0][1];
          let operation = $3[0].operation;
          let message_id = $3[0].message_id;
          return new Ok(
            stamp_attached(
              core,
              address,
              new $channel.TextState(kernel$1),
              tag_text_events(address, events),
              new $channel.TextOperation(operation),
              new $channel.TextMeta(message_id),
            ),
          );
        } else {
          let kernel$1 = $2[0][0];
          let events = $2[0][1];
          return new Ok(
            [
              put_attached_channel(
                core,
                address,
                new $channel.TextState(kernel$1),
              ),
              tag_text_events(address, events),
              $List$Empty$const,
            ],
          );
        }
      } else {
        let error = $2[0];
        return new Error(
          new TextOperationFailed(
            address,
            $text_kernel.edit_error_detail(error),
          ),
        );
      }
    }
  } else {
    return $;
  }
}

export function text_insert(core, address, index, value) {
  return mutate_text(
    core,
    address,
    (_capture) => { return $text_kernel.insert(_capture, index, value); },
  );
}

export function text_delete_range(core, address, start, end) {
  return mutate_text(
    core,
    address,
    (_capture) => { return $text_kernel.delete_range(_capture, start, end); },
  );
}

export function text_replace_range(core, address, start, end, value) {
  return mutate_text(
    core,
    address,
    (_capture) => {
      return $text_kernel.replace_range(_capture, start, end, value);
    },
  );
}

export function text_append(core, address, value) {
  return mutate_text(
    core,
    address,
    (kernel) => { return new Ok($text_kernel.append(kernel, value)); },
  );
}

function tag_g_set_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.GSetEvent(event)]; },
  );
}

function locate_g_set(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.GSetState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$GSetChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.GSetState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$GSetChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

export function g_set_add(core, address, element) {
  let $ = locate_g_set(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $g_set_kernel.add(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(core, address, new $channel.GSetState(kernel$1)),
          tag_g_set_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $g_set_kernel.add(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      let message_id = $2[3];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.GSetState(kernel$1),
          tag_g_set_events(address, events),
          new $channel.GSetOperation(operation),
          new $channel.GSetMeta(message_id),
        ),
      );
    }
  } else {
    return $;
  }
}

function tag_two_p_set_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.TwoPSetEvent(event)]; },
  );
}

function locate_two_p_set(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.TwoPSetState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$TwoPSetChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.TwoPSetState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$TwoPSetChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

export function two_p_set_add(core, address, element) {
  let $ = locate_two_p_set(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $two_p_set_kernel.add(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.TwoPSetState(kernel$1),
          ),
          tag_two_p_set_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $two_p_set_kernel.add(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      let message_id = $2[3];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.TwoPSetState(kernel$1),
          tag_two_p_set_events(address, events),
          new $channel.TwoPSetOperation(operation),
          new $channel.TwoPSetMeta(message_id),
        ),
      );
    }
  } else {
    return $;
  }
}

export function two_p_set_remove(core, address, element) {
  let $ = locate_two_p_set(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $two_p_set_kernel.remove(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.TwoPSetState(kernel$1),
          ),
          tag_two_p_set_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let $2 = $two_p_set_kernel.remove(kernel, element);
      let kernel$1 = $2[0];
      let events = $2[1];
      let operation = $2[2];
      let message_id = $2[3];
      return new Ok(
        stamp_attached(
          core,
          address,
          new $channel.TwoPSetState(kernel$1),
          tag_two_p_set_events(address, events),
          new $channel.TwoPSetOperation(operation),
          new $channel.TwoPSetMeta(message_id),
        ),
      );
    }
  } else {
    return $;
  }
}

function locate_register_collection(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.RegisterCollectionState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$RegisterCollectionChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.RegisterCollectionState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$RegisterCollectionChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

function tag_register_collection_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.RegisterCollectionEvent(event)]; },
  );
}

export function register_write(core, address, key, value) {
  let $ = locate_register_collection(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $register_collection_kernel.write_detached(kernel, key, value);
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.RegisterCollectionState(kernel$1),
          ),
          tag_register_collection_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let $2 = attach_dependencies(core, value);
      let core$1 = $2[0];
      let attach_outbound = $2[1];
      return $result.try$(
        locate_register_collection(core$1, address),
        (located) => {
          let _block;
          if (located instanceof Detached) {
            let kernel = located[0];
            _block = kernel;
          } else {
            let kernel = located[0];
            _block = kernel;
          }
          let kernel = _block;
          let operation = $register_collection_kernel.write(
            kernel,
            key,
            value,
            core$1.last_seen_sequence_number,
          );
          let $3 = stamp_attached(
            core$1,
            address,
            new $channel.RegisterCollectionState(kernel),
            $List$Empty$const,
            new $channel.RegisterCollectionOperation(operation),
            $channel.LocalOperationMeta$NoMeta$const,
          );
          let core$2 = $3[0];
          let events = $3[1];
          let outbound = $3[2];
          return new Ok(
            [core$2, events, $list.append(attach_outbound, outbound)],
          );
        },
      );
    }
  } else {
    return $;
  }
}

function locate_claims(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.ClaimsState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$ClaimsChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.ClaimsState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$ClaimsChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

export function claim_once(core, address, key, value) {
  let $ = locate_claims(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $claims_kernel.get(kernel, key);
      if ($2 instanceof Ok) {
        let current_value = $2[0];
        return new Ok(new ClaimAlreadyClaimed(current_value));
      } else {
        let kernel$1 = $claims_kernel.set_detached(kernel, key, value);
        let core$1 = put_detached_channel(
          core,
          address,
          new $channel.ClaimsState(kernel$1),
        );
        return new Ok(
          new ClaimPending(
            core$1,
            $List$Empty$const,
            new Some(new $claims_kernel.Accepted(value)),
          ),
        );
      }
    } else {
      let kernel = $1[0];
      let $2 = $claims_kernel.claim_once(
        kernel,
        key,
        value,
        core.last_seen_sequence_number,
      );
      if ($2 instanceof Ok) {
        let $3 = $2[0];
        if ($3 instanceof $claims_kernel.Submitted) {
          let kernel$1 = $3.state;
          let operation = $3.operation;
          let $4 = attach_dependencies(core, value);
          let core$1 = $4[0];
          let attach_outbound = $4[1];
          let $5 = stamp_attached(
            core$1,
            address,
            new $channel.ClaimsState(kernel$1),
            $List$Empty$const,
            new $channel.ClaimsOperation(operation),
            $channel.LocalOperationMeta$NoMeta$const,
          );
          let core$2 = $5[0];
          let outbound = $5[2];
          return new Ok(
            new ClaimPending(
              core$2,
              $list.append(attach_outbound, outbound),
              Option$None$const,
            ),
          );
        } else {
          let current_value = $3.current_value;
          return new Ok(new ClaimAlreadyClaimed(current_value));
        }
      } else {
        let $3 = $2[0];
        if ($3 instanceof $claims_kernel.AlreadyPendingLocally) {
          return new Ok(ClaimSubmitResult$ClaimAlreadyPendingLocally$const);
        } else if ($3 instanceof $claims_kernel.UnexpectedAck) {
          let detail = $3.detail;
          return new Error(new AckMismatch(detail));
        } else {
          let detail = $3.detail;
          return new Error(new AckMismatch(detail));
        }
      }
    }
  } else {
    return $;
  }
}

export function compare_and_set_claim(core, address, key, value) {
  let $ = locate_claims(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let kernel$1 = $claims_kernel.set_detached(kernel, key, value);
      let core$1 = put_detached_channel(
        core,
        address,
        new $channel.ClaimsState(kernel$1),
      );
      return new Ok(
        new ClaimPending(
          core$1,
          $List$Empty$const,
          new Some(new $claims_kernel.Accepted(value)),
        ),
      );
    } else {
      let kernel = $1[0];
      let $2 = $claims_kernel.compare_and_set_claim(
        kernel,
        key,
        value,
        core.last_seen_sequence_number,
      );
      if ($2 instanceof Ok) {
        let $3 = $2[0];
        if ($3 instanceof $claims_kernel.Submitted) {
          let kernel$1 = $3.state;
          let operation = $3.operation;
          let $4 = attach_dependencies(core, value);
          let core$1 = $4[0];
          let attach_outbound = $4[1];
          let $5 = stamp_attached(
            core$1,
            address,
            new $channel.ClaimsState(kernel$1),
            $List$Empty$const,
            new $channel.ClaimsOperation(operation),
            $channel.LocalOperationMeta$NoMeta$const,
          );
          let core$2 = $5[0];
          let outbound = $5[2];
          return new Ok(
            new ClaimPending(
              core$2,
              $list.append(attach_outbound, outbound),
              Option$None$const,
            ),
          );
        } else {
          let current_value = $3.current_value;
          return new Ok(new ClaimAlreadyClaimed(current_value));
        }
      } else {
        let $3 = $2[0];
        if ($3 instanceof $claims_kernel.AlreadyPendingLocally) {
          return new Ok(ClaimSubmitResult$ClaimAlreadyPendingLocally$const);
        } else if ($3 instanceof $claims_kernel.UnexpectedAck) {
          let detail = $3.detail;
          return new Error(new AckMismatch(detail));
        } else {
          let detail = $3.detail;
          return new Error(new AckMismatch(detail));
        }
      }
    }
  } else {
    return $;
  }
}

function tag_task_manager_events(address, events) {
  return $list.map(
    events,
    (event) => { return [address, new $channel.TaskManagerEvent(event)]; },
  );
}

function locate_task_manager(core, address) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      if (located instanceof Detached) {
        let $ = located[0];
        if ($ instanceof $channel.TaskManagerState) {
          let kernel = $[0];
          return new Ok(new Detached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$TaskManagerChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      } else {
        let $ = located[0];
        if ($ instanceof $channel.TaskManagerState) {
          let kernel = $[0];
          return new Ok(new Attached(kernel));
        } else {
          let other = $;
          return new Error(
            new WrongChannelType(
              address,
              $channel.ChannelType$TaskManagerChannel$const,
              $channel.channel_type(other),
            ),
          );
        }
      }
    },
  );
}

export function task_manager_volunteer(core, address, task_id) {
  let $ = locate_task_manager(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $task_manager_kernel.volunteer_detached(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
      );
      let kernel$1 = $2[0];
      let events = $2[1];
      let outcome = $2[2];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.TaskManagerState(kernel$1),
          ),
          tag_task_manager_events(address, events),
          $List$Empty$const,
          outcome,
        ],
      );
    } else {
      let kernel = $1[0];
      let message_id = core.next_client_sequence_number;
      let $2 = $task_manager_kernel.volunteer(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        message_id,
      );
      let kernel$1 = $2[0];
      let operation = $2[1];
      let outcome = $2[2];
      if (operation instanceof Some) {
        let operation$1 = operation[0];
        let $3 = stamp_attached(
          core,
          address,
          new $channel.TaskManagerState(kernel$1),
          $List$Empty$const,
          new $channel.TaskManagerOperation(operation$1),
          new $channel.TaskManagerMeta(message_id),
        );
        let core$1 = $3[0];
        let events = $3[1];
        let outbound = $3[2];
        return new Ok([core$1, events, outbound, outcome]);
      } else {
        return new Ok(
          [
            put_attached_channel(
              core,
              address,
              new $channel.TaskManagerState(kernel$1),
            ),
            $List$Empty$const,
            $List$Empty$const,
            outcome,
          ],
        );
      }
    }
  } else {
    return $;
  }
}

export function task_manager_abandon(core, address, task_id) {
  let $ = locate_task_manager(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $task_manager_kernel.abandon_detached(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
      );
      let kernel$1 = $2[0];
      let events = $2[1];
      return new Ok(
        [
          put_detached_channel(
            core,
            address,
            new $channel.TaskManagerState(kernel$1),
          ),
          tag_task_manager_events(address, events),
          $List$Empty$const,
        ],
      );
    } else {
      let kernel = $1[0];
      let message_id = core.next_client_sequence_number;
      let $2 = $task_manager_kernel.abandon(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        message_id,
      );
      let kernel$1 = $2[0];
      let operation = $2[1];
      let events = $2[2];
      if (operation instanceof Some) {
        let operation$1 = operation[0];
        return new Ok(
          stamp_attached(
            core,
            address,
            new $channel.TaskManagerState(kernel$1),
            tag_task_manager_events(address, events),
            new $channel.TaskManagerOperation(operation$1),
            new $channel.TaskManagerMeta(message_id),
          ),
        );
      } else {
        return new Ok(
          [
            put_attached_channel(
              core,
              address,
              new $channel.TaskManagerState(kernel$1),
            ),
            tag_task_manager_events(address, events),
            $List$Empty$const,
          ],
        );
      }
    }
  } else {
    return $;
  }
}

export function task_manager_complete(core, address, task_id) {
  let $ = locate_task_manager(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Detached) {
      let kernel = $1[0];
      let $2 = $task_manager_kernel.assigned(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        true,
      );
      if ($2) {
        let $3 = $task_manager_kernel.complete_detached(kernel, task_id);
        let kernel$1 = $3[0];
        let events = $3[1];
        return new Ok(
          [
            put_detached_channel(
              core,
              address,
              new $channel.TaskManagerState(kernel$1),
            ),
            tag_task_manager_events(address, events),
            $List$Empty$const,
          ],
        );
      } else {
        return new Error(new TaskNotAssigned(address, task_id));
      }
    } else {
      let kernel = $1[0];
      let message_id = core.next_client_sequence_number;
      let $2 = $task_manager_kernel.complete(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        message_id,
      );
      if ($2 instanceof Ok) {
        let kernel$1 = $2[0][0];
        let operation = $2[0][1];
        return new Ok(
          stamp_attached(
            core,
            address,
            new $channel.TaskManagerState(kernel$1),
            $List$Empty$const,
            new $channel.TaskManagerOperation(operation),
            new $channel.TaskManagerMeta(message_id),
          ),
        );
      } else {
        let $3 = $2[0];
        if ($3 instanceof $task_manager_kernel.NotAssigned) {
          return new Error(new TaskNotAssigned(address, task_id));
        } else if ($3 instanceof $task_manager_kernel.UnexpectedAck) {
          let detail = $3.detail;
          return new Error(new AckMismatch(detail));
        } else if ($3 instanceof $task_manager_kernel.UnexpectedRollback) {
          let detail = $3.detail;
          return new Error(new AckMismatch(detail));
        } else {
          let detail = $3.detail;
          return new Error(new AckMismatch(detail));
        }
      }
    }
  } else {
    return $;
  }
}

/**
 * Check that `address` resolves to the channel type that the caller
 * requested.
 */
export function require_channel_type(core, address, expected) {
  return $result.try$(
    locate_channel(core, address),
    (located) => {
      let _block;
      if (located instanceof Detached) {
        let state = located[0];
        _block = state;
      } else {
        let state = located[0];
        _block = state;
      }
      let state = _block;
      let actual = $channel.channel_type(state);
      let $ = isEqual(actual, expected);
      if ($) {
        return new Ok(undefined);
      } else {
        return new Error(new WrongChannelType(address, expected, actual));
      }
    },
  );
}

export function get(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.MapState) {
      let kernel = $1[0];
      return $map_kernel.get(kernel, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function has(core, address, key) {
  return $result.is_ok(get(core, address, key));
}

export function size(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.MapState) {
      let kernel = $1[0];
      return $map_kernel.size(kernel);
    } else {
      return 0;
    }
  } else {
    return 0;
  }
}

export function keys(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.MapState) {
      let kernel = $1[0];
      return $map_kernel.keys(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function entries(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.MapState) {
      let kernel = $1[0];
      return $map_kernel.entries(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

/**
 * The current optimistic value of the counter. The result is `Error(Nil)` when the
 * address does not exist, and when it does not name a counter channel.
 */
export function counter_value(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.CounterState) {
      let kernel = $1[0];
      return new Ok(kernel.value);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The current optimistic value of the PN-counter. The result is `Error(Nil)` when the
 * address does not exist, and when it does not name a PN-counter channel.
 */
export function pn_counter_value(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.PnCounterState) {
      let kernel = $1[0];
      return new Ok($pn_counter_kernel.value(kernel));
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The current optimistic value of the grow-only counter. The result is
 * `Error(Nil)` when the address does not exist, and when it does not name a
 * GCounter channel.
 */
export function g_counter_value(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.GCounterState) {
      let kernel = $1[0];
      return new Ok($g_counter_kernel.value(kernel));
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The accepted value for `key` in the PactMap at `address`. The result is
 * `Error(Nil)` when the key has no accepted value, because it is still pending or it
 * is absent, and when the address does not name a PactMap channel.
 */
export function pact_map_get(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.PactMapState) {
      let kernel = $1[0];
      return $pact_map_kernel.get(kernel, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The accepted entry for `key`, which is the value with its sequence number.
 * The result is `Error(Nil)` when the key is absent.
 */
export function pact_map_get_with_details(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.PactMapState) {
      let kernel = $1[0];
      return $pact_map_kernel.get_with_details(kernel, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The pending proposal for `key`, which is its value with the signoff list that
 * it still waits on. The result is `Error(Nil)` when nothing is pending, and when the
 * address does not name a PactMap.
 *
 * The kernel freezes the signoff list from the connected roster when the `Set`
 * operation sequences. That list thus names the room at that moment, and not
 * the room now.
 */
export function pact_map_pending(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.PactMapState) {
      let kernel = $1[0];
      return $pact_map_kernel.pending(kernel, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * Whether `key` has a pending value now, which a client proposed and no room
 * has accepted yet.
 */
export function pact_map_is_pending(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.PactMapState) {
      let kernel = $1[0];
      return $pact_map_kernel.is_pending(kernel, key);
    } else {
      return false;
    }
  } else {
    return false;
  }
}

/**
 * Every key with an accepted pact or a pending pact, sorted.
 */
export function pact_map_keys(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.PactMapState) {
      let kernel = $1[0];
      return $pact_map_kernel.keys(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

/**
 * The number of items that wait in the queue at `address`. The count does not
 * include an acquired job. The result is `Error(Nil)` when the address does not
 * exist, and when it does not name an ordered collection.
 */
export function ordered_size(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.OrderedCollectionState) {
      let kernel = $1[0];
      return new Ok($ordered_collection_kernel.size(kernel));
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The values in the queue at `address`, which no client acquired yet, front
 * first.
 */
export function ordered_queue(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.OrderedCollectionState) {
      let kernel = $1[0];
      return $ordered_collection_kernel.summary_queue(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

/**
 * The jobs that clients hold at `address` now, keyed by acquire id and sorted
 * by that id.
 */
export function ordered_jobs(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.OrderedCollectionState) {
      let kernel = $1[0];
      return $ordered_collection_kernel.summary_jobs(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function or_map_value(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.OrMapState) {
      let kernel = $1[0];
      return $or_map_kernel.get(kernel, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function or_map_values(core, address, key) {
  let $ = or_map_value(core, address, key);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $or_map_kernel.Tally) {
      return new Error(undefined);
    } else if ($1 instanceof $or_map_kernel.Register) {
      return new Error(undefined);
    } else if ($1 instanceof $or_map_kernel.SetMembers) {
      return new Error(undefined);
    } else {
      let values = $1[0];
      return new Ok(values);
    }
  } else {
    return new Error(undefined);
  }
}

export function or_map_keys(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.OrMapState) {
      let kernel = $1[0];
      return $or_map_kernel.keys(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function or_map_entries(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.OrMapState) {
      let kernel = $1[0];
      return $or_map_kernel.entries(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function or_set_contains(core, address, element) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.OrSetState) {
      let kernel = $1[0];
      return $or_set_kernel.contains(kernel, element);
    } else {
      return false;
    }
  } else {
    return false;
  }
}

export function or_set_values(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.OrSetState) {
      let kernel = $1[0];
      return $or_set_kernel.values(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function sequence_values(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.SequenceState) {
      let kernel = $1[0];
      return $sequence_kernel.values(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function sequence_length(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.SequenceState) {
      let kernel = $1[0];
      return $sequence_kernel.length(kernel);
    } else {
      return 0;
    }
  } else {
    return 0;
  }
}

/**
 * The current visible optimistic string of the text channel. The result is `""`
 * when the address does not exist, and when it does not name a text
 * channel.
 */
export function text_value(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TextState) {
      let kernel = $1[0];
      return $text_kernel.value(kernel);
    } else {
      return "";
    }
  } else {
    return "";
  }
}

/**
 * The current optimistic grapheme count of the text channel. The result is `0`
 * when the address does not exist, and when it does not name a text
 * channel.
 */
export function text_length(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TextState) {
      let kernel = $1[0];
      return $text_kernel.length(kernel);
    } else {
      return 0;
    }
  } else {
    return 0;
  }
}

/**
 * The graphemes in `[start, end)` of the optimistic string of the text channel.
 * The result is an error string when the range `start..end` is invalid, when
 * the address does not exist, and when the address does not name a text
 * channel.
 */
export function text_substring(core, address, start, end) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TextState) {
      let kernel = $1[0];
      let $2 = $text_kernel.substring(kernel, start, end);
      if ($2 instanceof Ok) {
        return $2;
      } else {
        let error = $2[0];
        return new Error($text_kernel.edit_error_detail(error));
      }
    } else {
      return new Error(
        ("text substring requires a text channel at " + address) + ", found none",
      );
    }
  } else {
    return new Error(
      ("text substring requires a text channel at " + address) + ", found none",
    );
  }
}

/**
 * Create a stable anchor at the gap at `index`. `bias` selects the adjacent
 * grapheme that the anchor binds to. `Before` binds it to the grapheme after
 * the gap, and `After` binds it to the grapheme before the gap. See
 * `text_kernel.Bias`. The result is an error string when the index is out of
 * bounds, when the address does not exist, and when the address does not name a
 * text channel.
 */
export function text_anchor_at(core, address, index, bias) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TextState) {
      let kernel = $1[0];
      let $2 = $text_kernel.anchor_at(kernel, index, bias);
      if ($2 instanceof Ok) {
        return $2;
      } else {
        let error = $2[0];
        return new Error($text_kernel.anchor_error_detail(error));
      }
    } else {
      return new Error(
        ("text anchor_at requires a text channel at " + address) + ", found none",
      );
    }
  } else {
    return new Error(
      ("text anchor_at requires a text channel at " + address) + ", found none",
    );
  }
}

/**
 * Resolve an anchor to a current optimistic grapheme index. The result is an
 * error string when the anchor target is stale or unknown, when the address
 * does not exist, and when the address does not name a text channel.
 */
export function text_resolve_anchor(core, address, anchor) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TextState) {
      let kernel = $1[0];
      let $2 = $text_kernel.resolve_anchor(kernel, anchor);
      if ($2 instanceof Ok) {
        return $2;
      } else {
        let error = $2[0];
        return new Error($text_kernel.anchor_error_detail(error));
      }
    } else {
      return new Error(
        ("text resolve_anchor requires a text channel at " + address) + ", found none",
      );
    }
  } else {
    return new Error(
      ("text resolve_anchor requires a text channel at " + address) + ", found none",
    );
  }
}

/**
 * An anchor at the start of the text. It always resolves to 0. The function is
 * pure. It needs no `Core` value and no address, because the anchor carries no
 * document state.
 */
export function text_start_anchor() {
  return $text_kernel.start_anchor();
}

/**
 * An anchor at the end of the text. It always resolves to the current grapheme
 * count, and it moves as the text becomes longer. The function is pure, the
 * same as `text_start_anchor`.
 */
export function text_end_anchor() {
  return $text_kernel.end_anchor();
}

/**
 * Encode an anchor as a self-describing JSON value, for example to send it
 * through presence for a shared cursor.
 */
export function text_anchor_to_json(anchor) {
  return $text_kernel.anchor_to_json(anchor);
}

/**
 * Format a `json.DecodeError` value as a string for a person to read. The
 * function follows the variant pattern of `roost/frame.gleam`.
 * 
 * @ignore
 */
function format_json_decode_error(error) {
  if (error instanceof $json.UnexpectedEndOfInput) {
    return "unexpected end of input";
  } else if (error instanceof $json.UnexpectedByte) {
    let byte = error[0];
    return "unexpected byte: " + byte;
  } else if (error instanceof $json.UnexpectedSequence) {
    let bytes = error[0];
    return "unexpected sequence: " + bytes;
  } else {
    let errors = error[0];
    return "unable to decode: " + $string.join(
      $list.map(
        errors,
        (e) => {
          return ((("expected " + e.expected) + ", found ") + e.found) + (() => {
            let $ = e.path;
            if ($ instanceof $Empty) {
              return "";
            } else {
              let path = $;
              return " at " + $string.join(path, ".");
            }
          })();
        },
      ),
      "; ",
    );
  }
}

/**
 * Decode an anchor from a JSON string that `text_anchor_to_json` produced. The
 * result is an error string for malformed JSON.
 */
export function text_anchor_from_json(json_string) {
  let $ = $text_kernel.anchor_from_json(json_string);
  if ($ instanceof Ok) {
    return $;
  } else {
    let error = $[0];
    return new Error("invalid anchor JSON: " + format_json_decode_error(error));
  }
}

export function g_set_contains(core, address, element) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.GSetState) {
      let kernel = $1[0];
      return $g_set_kernel.contains(kernel, element);
    } else {
      return false;
    }
  } else {
    return false;
  }
}

export function g_set_values(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.GSetState) {
      let kernel = $1[0];
      return $g_set_kernel.values(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function two_p_set_contains(core, address, element) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TwoPSetState) {
      let kernel = $1[0];
      return $two_p_set_kernel.contains(kernel, element);
    } else {
      return false;
    }
  } else {
    return false;
  }
}

export function two_p_set_values(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TwoPSetState) {
      let kernel = $1[0];
      return $two_p_set_kernel.values(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

/**
 * An optimistic read of a directory key at `path`, with the pending edits
 * applied.
 */
export function directory_get(core, address, path, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.DirectoryState) {
      let kernel = $1[0];
      return $directory_kernel.get(kernel, path, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The optimistic `#(key, value)` entries of the directory at `path`, in
 * order.
 */
export function directory_entries(core, address, path) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.DirectoryState) {
      let kernel = $1[0];
      return $directory_kernel.entries(kernel, path);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

/**
 * The names of the optimistic child directories of the directory at `path`, in
 * order.
 */
export function directory_subdirectories(core, address, path) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.DirectoryState) {
      let kernel = $1[0];
      return $directory_kernel.subdirectories(kernel, path);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function directory_has_subdirectory(core, address, path, name) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.DirectoryState) {
      let kernel = $1[0];
      return $directory_kernel.has_subdirectory(kernel, path, name);
    } else {
      return false;
    }
  } else {
    return false;
  }
}

export function register_read(core, address, key, policy) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.RegisterCollectionState) {
      let kernel = $1[0];
      return $register_collection_kernel.read(kernel, key, policy);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function register_versions(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.RegisterCollectionState) {
      let kernel = $1[0];
      return $register_collection_kernel.read_versions(kernel, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function register_keys(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.RegisterCollectionState) {
      let kernel = $1[0];
      return $register_collection_kernel.keys(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

export function get_claim(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.ClaimsState) {
      let kernel = $1[0];
      return $claims_kernel.get(kernel, key);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function has_claim(core, address, key) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.ClaimsState) {
      let kernel = $1[0];
      return $claims_kernel.has(kernel, key);
    } else {
      return false;
    }
  } else {
    return false;
  }
}

export function task_manager_assigned(core, address, task_id) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TaskManagerState) {
      let kernel = $1[0];
      return $task_manager_kernel.assigned(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        true,
      );
    } else {
      return false;
    }
  } else {
    return false;
  }
}

export function task_manager_queued(core, address, task_id) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TaskManagerState) {
      let kernel = $1[0];
      return $task_manager_kernel.queued(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        true,
      );
    } else {
      return false;
    }
  } else {
    return false;
  }
}

export function task_manager_queues(core, address) {
  let $ = find_channel(core, address);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $channel.TaskManagerState) {
      let kernel = $1[0];
      return $task_manager_kernel.summary_queues(kernel);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $List$Empty$const;
  }
}

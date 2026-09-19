import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $set from "../../gleam_stdlib/gleam/set.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as $message from "../../spillway/spillway/message.d.mts";
import type * as $types from "../../spillway/spillway/types.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $channel from "../watershed/channel.d.mts";
import type * as $claims_kernel from "../watershed/claims_kernel.d.mts";
import type * as $counter_kernel from "../watershed/counter_kernel.d.mts";
import type * as $directory_kernel from "../watershed/directory_kernel.d.mts";
import type * as $g_counter_kernel from "../watershed/g_counter_kernel.d.mts";
import type * as $g_set_kernel from "../watershed/g_set_kernel.d.mts";
import type * as $json_ot from "../watershed/json_ot.d.mts";
import type * as $json_ot_kernel from "../watershed/json_ot_kernel.d.mts";
import type * as $lww_map_kernel from "../watershed/lww_map_kernel.d.mts";
import type * as $map_kernel from "../watershed/map_kernel.d.mts";
import type * as $or_map_kernel from "../watershed/or_map_kernel.d.mts";
import type * as $or_set_kernel from "../watershed/or_set_kernel.d.mts";
import type * as $ordered_collection_kernel from "../watershed/ordered_collection_kernel.d.mts";
import type * as $pact_map_kernel from "../watershed/pact_map_kernel.d.mts";
import type * as $pn_counter_kernel from "../watershed/pn_counter_kernel.d.mts";
import type * as $register_collection_kernel from "../watershed/register_collection_kernel.d.mts";
import type * as $rich_text from "../watershed/rich_text.d.mts";
import type * as $rich_text_kernel from "../watershed/rich_text_kernel.d.mts";
import type * as $sequence_kernel from "../watershed/sequence_kernel.d.mts";
import type * as $summary_policy from "../watershed/summary_policy.d.mts";
import type * as $task_manager_kernel from "../watershed/task_manager_kernel.d.mts";
import type * as $text_kernel from "../watershed/text_kernel.d.mts";
import type * as $two_p_set_kernel from "../watershed/two_p_set_kernel.d.mts";
import type * as $wire from "../watershed/wire.d.mts";
import type * as $summary_blob from "../watershed/wire/summary_blob.d.mts";

export class Replaying extends _.CustomType {}
export function IngestPosition$Replaying(): IngestPosition$;
export function IngestPosition$isReplaying(
  value: any,
): value is IngestPosition$;

export class Live extends _.CustomType {}
export function IngestPosition$Live(): IngestPosition$;
export function IngestPosition$isLive(value: any): value is IngestPosition$;

export type IngestPosition$ = Replaying | Live;

export class Core extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: string,
    channels: $dict.Dict$<string, $channel.ChannelState$>,
    channel_order: _.List<string>,
    detached: $dict.Dict$<string, $channel.ChannelState$>,
    next_client_sequence_number: number,
    last_seen_sequence_number: number,
    in_flight: _.List<InFlight$>,
    out_of_order: _.List<$types.SequencedDocumentMessage$>,
    members: $set.Set$<number>,
    live_members: $set.Set$<number>,
    ingest: IngestPosition$,
    last_summary_sequence_number: number,
    summary_head: $option.Option$<string>,
    owed: $dict.Dict$<string, _.List<$channel.ChannelOperation$>>
  );
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  channels: $dict.Dict$<string, $channel.ChannelState$>;
  /** @deprecated */
  channel_order: _.List<string>;
  /** @deprecated */
  detached: $dict.Dict$<string, $channel.ChannelState$>;
  /** @deprecated */
  next_client_sequence_number: number;
  /** @deprecated */
  last_seen_sequence_number: number;
  /** @deprecated */
  in_flight: _.List<InFlight$>;
  /** @deprecated */
  out_of_order: _.List<$types.SequencedDocumentMessage$>;
  /** @deprecated */
  members: $set.Set$<number>;
  /** @deprecated */
  live_members: $set.Set$<number>;
  /** @deprecated */
  ingest: IngestPosition$;
  /** @deprecated */
  last_summary_sequence_number: number;
  /** @deprecated */
  summary_head: $option.Option$<string>;
  /** @deprecated */
  owed: $dict.Dict$<string, _.List<$channel.ChannelOperation$>>;
}
export function Core$Core(
  client_id: string,
  channels: $dict.Dict$<string, $channel.ChannelState$>,
  channel_order: _.List<string>,
  detached: $dict.Dict$<string, $channel.ChannelState$>,
  next_client_sequence_number: number,
  last_seen_sequence_number: number,
  in_flight: _.List<InFlight$>,
  out_of_order: _.List<$types.SequencedDocumentMessage$>,
  members: $set.Set$<number>,
  live_members: $set.Set$<number>,
  ingest: IngestPosition$,
  last_summary_sequence_number: number,
  summary_head: $option.Option$<string>,
  owed: $dict.Dict$<string, _.List<$channel.ChannelOperation$>>,
): Core$;
export function Core$isCore(value: any): value is Core$;
export function Core$Core$0(value: Core$): string;
export function Core$Core$client_id(value: Core$): string;
export function Core$Core$1(value: Core$): $dict.Dict$<
  string,
  $channel.ChannelState$
>;
export function Core$Core$channels(value: Core$): $dict.Dict$<
  string,
  $channel.ChannelState$
>;
export function Core$Core$2(value: Core$): _.List<string>;
export function Core$Core$channel_order(value: Core$): _.List<string>;
export function Core$Core$3(value: Core$): $dict.Dict$<
  string,
  $channel.ChannelState$
>;
export function Core$Core$detached(value: Core$): $dict.Dict$<
  string,
  $channel.ChannelState$
>;
export function Core$Core$4(value: Core$): number;
export function Core$Core$next_client_sequence_number(value: Core$): number;
export function Core$Core$5(value: Core$): number;
export function Core$Core$last_seen_sequence_number(value: Core$): number;
export function Core$Core$6(value: Core$): _.List<InFlight$>;
export function Core$Core$in_flight(value: Core$): _.List<InFlight$>;
export function Core$Core$7(value: Core$): _.List<
  $types.SequencedDocumentMessage$
>;
export function Core$Core$out_of_order(value: Core$): _.List<
  $types.SequencedDocumentMessage$
>;
export function Core$Core$8(value: Core$): $set.Set$<number>;
export function Core$Core$members(value: Core$): $set.Set$<number>;
export function Core$Core$9(value: Core$): $set.Set$<number>;
export function Core$Core$live_members(value: Core$): $set.Set$<number>;
export function Core$Core$10(value: Core$): IngestPosition$;
export function Core$Core$ingest(value: Core$): IngestPosition$;
export function Core$Core$11(value: Core$): number;
export function Core$Core$last_summary_sequence_number(value: Core$): number;
export function Core$Core$12(value: Core$): $option.Option$<string>;
export function Core$Core$summary_head(value: Core$): $option.Option$<string>;
export function Core$Core$13(value: Core$): $dict.Dict$<
  string,
  _.List<$channel.ChannelOperation$>
>;
export function Core$Core$owed(value: Core$): $dict.Dict$<
  string,
  _.List<$channel.ChannelOperation$>
>;

export type Core$ = Core;

export class InFlightOperation extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: string,
    client_sequence_number: number,
    address: string,
    operation: $channel.ChannelOperation$,
    meta: $channel.LocalOperationMeta$
  );
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  address: string;
  /** @deprecated */
  operation: $channel.ChannelOperation$;
  /** @deprecated */
  meta: $channel.LocalOperationMeta$;
}
export function InFlight$InFlightOperation(
  client_id: string,
  client_sequence_number: number,
  address: string,
  operation: $channel.ChannelOperation$,
  meta: $channel.LocalOperationMeta$,
): InFlight$;
export function InFlight$isInFlightOperation(value: any): value is InFlight$;
export function InFlight$InFlightOperation$0(value: InFlight$): string;
export function InFlight$InFlightOperation$client_id(value: InFlight$): string;
export function InFlight$InFlightOperation$1(value: InFlight$): number;
export function InFlight$InFlightOperation$client_sequence_number(value: InFlight$): number;
export function InFlight$InFlightOperation$2(
  value: InFlight$,
): string;
export function InFlight$InFlightOperation$address(value: InFlight$): string;
export function InFlight$InFlightOperation$3(value: InFlight$): $channel.ChannelOperation$;
export function InFlight$InFlightOperation$operation(
  value: InFlight$,
): $channel.ChannelOperation$;
export function InFlight$InFlightOperation$4(value: InFlight$): $channel.LocalOperationMeta$;
export function InFlight$InFlightOperation$meta(
  value: InFlight$,
): $channel.LocalOperationMeta$;

export class InFlightAttach extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: string,
    client_sequence_number: number,
    address: string,
    snapshot: $channel.Snapshot$
  );
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  address: string;
  /** @deprecated */
  snapshot: $channel.Snapshot$;
}
export function InFlight$InFlightAttach(
  client_id: string,
  client_sequence_number: number,
  address: string,
  snapshot: $channel.Snapshot$,
): InFlight$;
export function InFlight$isInFlightAttach(value: any): value is InFlight$;
export function InFlight$InFlightAttach$0(value: InFlight$): string;
export function InFlight$InFlightAttach$client_id(value: InFlight$): string;
export function InFlight$InFlightAttach$1(value: InFlight$): number;
export function InFlight$InFlightAttach$client_sequence_number(value: InFlight$): number;
export function InFlight$InFlightAttach$2(
  value: InFlight$,
): string;
export function InFlight$InFlightAttach$address(value: InFlight$): string;
export function InFlight$InFlightAttach$3(value: InFlight$): $channel.Snapshot$;
export function InFlight$InFlightAttach$snapshot(value: InFlight$): $channel.Snapshot$;

export type InFlight$ = InFlightOperation | InFlightAttach;

export function InFlight$address(value: InFlight$): string;
export function InFlight$client_id(value: InFlight$): string;
export function InFlight$client_sequence_number(value: InFlight$): number;

export class AckMismatch extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function CoreError$AckMismatch(detail: string): CoreError$;
export function CoreError$isAckMismatch(value: any): value is CoreError$;
export function CoreError$AckMismatch$0(value: CoreError$): string;
export function CoreError$AckMismatch$detail(value: CoreError$): string;

export class BadOperationContents extends _.CustomType {
  /** @deprecated */
  constructor(sequence_number: number);
  /** @deprecated */
  sequence_number: number;
}
export function CoreError$BadOperationContents(
  sequence_number: number,
): CoreError$;
export function CoreError$isBadOperationContents(
  value: any,
): value is CoreError$;
export function CoreError$BadOperationContents$0(value: CoreError$): number;
export function CoreError$BadOperationContents$sequence_number(value: CoreError$): number;

export class HistoryGap extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function CoreError$HistoryGap(detail: string): CoreError$;
export function CoreError$isHistoryGap(value: any): value is CoreError$;
export function CoreError$HistoryGap$0(value: CoreError$): string;
export function CoreError$HistoryGap$detail(value: CoreError$): string;

export class UnknownChannel extends _.CustomType {
  /** @deprecated */
  constructor(address: string, sequence_number: number);
  /** @deprecated */
  address: string;
  /** @deprecated */
  sequence_number: number;
}
export function CoreError$UnknownChannel(
  address: string,
  sequence_number: number,
): CoreError$;
export function CoreError$isUnknownChannel(value: any): value is CoreError$;
export function CoreError$UnknownChannel$0(value: CoreError$): string;
export function CoreError$UnknownChannel$address(value: CoreError$): string;
export function CoreError$UnknownChannel$1(value: CoreError$): number;
export function CoreError$UnknownChannel$sequence_number(value: CoreError$): number;

export class DuplicateAttach extends _.CustomType {
  /** @deprecated */
  constructor(address: string, sequence_number: number);
  /** @deprecated */
  address: string;
  /** @deprecated */
  sequence_number: number;
}
export function CoreError$DuplicateAttach(
  address: string,
  sequence_number: number,
): CoreError$;
export function CoreError$isDuplicateAttach(value: any): value is CoreError$;
export function CoreError$DuplicateAttach$0(value: CoreError$): string;
export function CoreError$DuplicateAttach$address(value: CoreError$): string;
export function CoreError$DuplicateAttach$1(value: CoreError$): number;
export function CoreError$DuplicateAttach$sequence_number(value: CoreError$): number;

export class WrongChannelType extends _.CustomType {
  /** @deprecated */
  constructor(
    address: string,
    expected: $channel.ChannelType$,
    actual: $channel.ChannelType$
  );
  /** @deprecated */
  address: string;
  /** @deprecated */
  expected: $channel.ChannelType$;
  /** @deprecated */
  actual: $channel.ChannelType$;
}
export function CoreError$WrongChannelType(
  address: string,
  expected: $channel.ChannelType$,
  actual: $channel.ChannelType$,
): CoreError$;
export function CoreError$isWrongChannelType(value: any): value is CoreError$;
export function CoreError$WrongChannelType$0(value: CoreError$): string;
export function CoreError$WrongChannelType$address(value: CoreError$): string;
export function CoreError$WrongChannelType$1(value: CoreError$): $channel.ChannelType$;
export function CoreError$WrongChannelType$expected(
  value: CoreError$,
): $channel.ChannelType$;
export function CoreError$WrongChannelType$2(value: CoreError$): $channel.ChannelType$;
export function CoreError$WrongChannelType$actual(
  value: CoreError$,
): $channel.ChannelType$;

export class OrMapModeMismatch extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$OrMapModeMismatch(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isOrMapModeMismatch(value: any): value is CoreError$;
export function CoreError$OrMapModeMismatch$0(value: CoreError$): string;
export function CoreError$OrMapModeMismatch$address(value: CoreError$): string;
export function CoreError$OrMapModeMismatch$1(value: CoreError$): string;
export function CoreError$OrMapModeMismatch$detail(value: CoreError$): string;

export class OrMapOperationFailed extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$OrMapOperationFailed(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isOrMapOperationFailed(
  value: any,
): value is CoreError$;
export function CoreError$OrMapOperationFailed$0(value: CoreError$): string;
export function CoreError$OrMapOperationFailed$address(value: CoreError$): string;
export function CoreError$OrMapOperationFailed$1(
  value: CoreError$,
): string;
export function CoreError$OrMapOperationFailed$detail(value: CoreError$): string;

export class TaskNotAssigned extends _.CustomType {
  /** @deprecated */
  constructor(address: string, task_id: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  task_id: string;
}
export function CoreError$TaskNotAssigned(
  address: string,
  task_id: string,
): CoreError$;
export function CoreError$isTaskNotAssigned(value: any): value is CoreError$;
export function CoreError$TaskNotAssigned$0(value: CoreError$): string;
export function CoreError$TaskNotAssigned$address(value: CoreError$): string;
export function CoreError$TaskNotAssigned$1(value: CoreError$): string;
export function CoreError$TaskNotAssigned$task_id(value: CoreError$): string;

export class DirectoryOperationFailed extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$DirectoryOperationFailed(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isDirectoryOperationFailed(
  value: any,
): value is CoreError$;
export function CoreError$DirectoryOperationFailed$0(value: CoreError$): string;
export function CoreError$DirectoryOperationFailed$address(value: CoreError$): string;
export function CoreError$DirectoryOperationFailed$1(
  value: CoreError$,
): string;
export function CoreError$DirectoryOperationFailed$detail(value: CoreError$): string;

export class SequenceOperationFailed extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$SequenceOperationFailed(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isSequenceOperationFailed(
  value: any,
): value is CoreError$;
export function CoreError$SequenceOperationFailed$0(value: CoreError$): string;
export function CoreError$SequenceOperationFailed$address(value: CoreError$): string;
export function CoreError$SequenceOperationFailed$1(
  value: CoreError$,
): string;
export function CoreError$SequenceOperationFailed$detail(value: CoreError$): string;

export class GCounterOperationFailed extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$GCounterOperationFailed(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isGCounterOperationFailed(
  value: any,
): value is CoreError$;
export function CoreError$GCounterOperationFailed$0(value: CoreError$): string;
export function CoreError$GCounterOperationFailed$address(value: CoreError$): string;
export function CoreError$GCounterOperationFailed$1(
  value: CoreError$,
): string;
export function CoreError$GCounterOperationFailed$detail(value: CoreError$): string;

export class LwwRegisterOperationFailed extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$LwwRegisterOperationFailed(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isLwwRegisterOperationFailed(
  value: any,
): value is CoreError$;
export function CoreError$LwwRegisterOperationFailed$0(value: CoreError$): string;
export function CoreError$LwwRegisterOperationFailed$address(
  value: CoreError$,
): string;
export function CoreError$LwwRegisterOperationFailed$1(value: CoreError$): string;
export function CoreError$LwwRegisterOperationFailed$detail(
  value: CoreError$,
): string;

export class LwwMapOperationFailed extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$LwwMapOperationFailed(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isLwwMapOperationFailed(
  value: any,
): value is CoreError$;
export function CoreError$LwwMapOperationFailed$0(value: CoreError$): string;
export function CoreError$LwwMapOperationFailed$address(value: CoreError$): string;
export function CoreError$LwwMapOperationFailed$1(
  value: CoreError$,
): string;
export function CoreError$LwwMapOperationFailed$detail(value: CoreError$): string;

export class TextOperationFailed extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$TextOperationFailed(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isTextOperationFailed(
  value: any,
): value is CoreError$;
export function CoreError$TextOperationFailed$0(value: CoreError$): string;
export function CoreError$TextOperationFailed$address(value: CoreError$): string;
export function CoreError$TextOperationFailed$1(
  value: CoreError$,
): string;
export function CoreError$TextOperationFailed$detail(value: CoreError$): string;

export class BadSummaryChannel extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function CoreError$BadSummaryChannel(
  address: string,
  detail: string,
): CoreError$;
export function CoreError$isBadSummaryChannel(value: any): value is CoreError$;
export function CoreError$BadSummaryChannel$0(value: CoreError$): string;
export function CoreError$BadSummaryChannel$address(value: CoreError$): string;
export function CoreError$BadSummaryChannel$1(value: CoreError$): string;
export function CoreError$BadSummaryChannel$detail(value: CoreError$): string;

export type CoreError$ = AckMismatch | BadOperationContents | HistoryGap | UnknownChannel | DuplicateAttach | WrongChannelType | OrMapModeMismatch | OrMapOperationFailed | TaskNotAssigned | DirectoryOperationFailed | SequenceOperationFailed | GCounterOperationFailed | LwwRegisterOperationFailed | LwwMapOperationFailed | TextOperationFailed | BadSummaryChannel;

export class Complete extends _.CustomType {
  /** @deprecated */
  constructor(core: Core$);
  /** @deprecated */
  core: Core$;
}
export function Bootstrapped$Complete(core: Core$): Bootstrapped$;
export function Bootstrapped$isComplete(value: any): value is Bootstrapped$;
export function Bootstrapped$Complete$0(value: Bootstrapped$): Core$;
export function Bootstrapped$Complete$core(value: Bootstrapped$): Core$;

export class MissingPrefix extends _.CustomType {
  /** @deprecated */
  constructor(core: Core$, checkpoint: number, from: number, to: number);
  /** @deprecated */
  core: Core$;
  /** @deprecated */
  checkpoint: number;
  /** @deprecated */
  from: number;
  /** @deprecated */
  to: number;
}
export function Bootstrapped$MissingPrefix(
  core: Core$,
  checkpoint: number,
  from: number,
  to: number,
): Bootstrapped$;
export function Bootstrapped$isMissingPrefix(
  value: any,
): value is Bootstrapped$;
export function Bootstrapped$MissingPrefix$0(value: Bootstrapped$): Core$;
export function Bootstrapped$MissingPrefix$core(value: Bootstrapped$): Core$;
export function Bootstrapped$MissingPrefix$1(value: Bootstrapped$): number;
export function Bootstrapped$MissingPrefix$checkpoint(value: Bootstrapped$): number;
export function Bootstrapped$MissingPrefix$2(
  value: Bootstrapped$,
): number;
export function Bootstrapped$MissingPrefix$from(value: Bootstrapped$): number;
export function Bootstrapped$MissingPrefix$3(value: Bootstrapped$): number;
export function Bootstrapped$MissingPrefix$to(value: Bootstrapped$): number;

export type Bootstrapped$ = Complete | MissingPrefix;

export function Bootstrapped$core(value: Bootstrapped$): Core$;

export class SummaryProposalSequenced extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: $option.Option$<string>,
    client_sequence_number: number,
    sequence_number: number
  );
  /** @deprecated */
  client_id: $option.Option$<string>;
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  sequence_number: number;
}
export function SummaryEvent$SummaryProposalSequenced(
  client_id: $option.Option$<string>,
  client_sequence_number: number,
  sequence_number: number,
): SummaryEvent$;
export function SummaryEvent$isSummaryProposalSequenced(
  value: any,
): value is SummaryEvent$;
export function SummaryEvent$SummaryProposalSequenced$0(value: SummaryEvent$): $option.Option$<
  string
>;
export function SummaryEvent$SummaryProposalSequenced$client_id(value: SummaryEvent$): $option.Option$<
  string
>;
export function SummaryEvent$SummaryProposalSequenced$1(value: SummaryEvent$): number;
export function SummaryEvent$SummaryProposalSequenced$client_sequence_number(
  value: SummaryEvent$,
): number;
export function SummaryEvent$SummaryProposalSequenced$2(value: SummaryEvent$): number;
export function SummaryEvent$SummaryProposalSequenced$sequence_number(
  value: SummaryEvent$,
): number;

export class SummaryPublished extends _.CustomType {
  /** @deprecated */
  constructor(proposal_sequence_number: number, version_id: string);
  /** @deprecated */
  proposal_sequence_number: number;
  /** @deprecated */
  version_id: string;
}
export function SummaryEvent$SummaryPublished(
  proposal_sequence_number: number,
  version_id: string,
): SummaryEvent$;
export function SummaryEvent$isSummaryPublished(
  value: any,
): value is SummaryEvent$;
export function SummaryEvent$SummaryPublished$0(value: SummaryEvent$): number;
export function SummaryEvent$SummaryPublished$proposal_sequence_number(value: SummaryEvent$): number;
export function SummaryEvent$SummaryPublished$1(
  value: SummaryEvent$,
): string;
export function SummaryEvent$SummaryPublished$version_id(value: SummaryEvent$): string;

export class SummaryRejected extends _.CustomType {
  /** @deprecated */
  constructor(proposal_sequence_number: number, reason: string);
  /** @deprecated */
  proposal_sequence_number: number;
  /** @deprecated */
  reason: string;
}
export function SummaryEvent$SummaryRejected(
  proposal_sequence_number: number,
  reason: string,
): SummaryEvent$;
export function SummaryEvent$isSummaryRejected(
  value: any,
): value is SummaryEvent$;
export function SummaryEvent$SummaryRejected$0(value: SummaryEvent$): number;
export function SummaryEvent$SummaryRejected$proposal_sequence_number(value: SummaryEvent$): number;
export function SummaryEvent$SummaryRejected$1(
  value: SummaryEvent$,
): string;
export function SummaryEvent$SummaryRejected$reason(value: SummaryEvent$): string;

export type SummaryEvent$ = SummaryProposalSequenced | SummaryPublished | SummaryRejected;

export class Ingested extends _.CustomType {
  /** @deprecated */
  constructor(
    events: _.List<[string, $channel.ChannelEvent$]>,
    resolutions: _.List<[string, $channel.Resolution$]>,
    summary_events: _.List<SummaryEvent$>,
    request_operations_from: $option.Option$<number>,
    outbound: _.List<$wire.OutboundOperation$>
  );
  /** @deprecated */
  events: _.List<[string, $channel.ChannelEvent$]>;
  /** @deprecated */
  resolutions: _.List<[string, $channel.Resolution$]>;
  /** @deprecated */
  summary_events: _.List<SummaryEvent$>;
  /** @deprecated */
  request_operations_from: $option.Option$<number>;
  /** @deprecated */
  outbound: _.List<$wire.OutboundOperation$>;
}
export function Ingested$Ingested(
  events: _.List<[string, $channel.ChannelEvent$]>,
  resolutions: _.List<[string, $channel.Resolution$]>,
  summary_events: _.List<SummaryEvent$>,
  request_operations_from: $option.Option$<number>,
  outbound: _.List<$wire.OutboundOperation$>,
): Ingested$;
export function Ingested$isIngested(value: any): value is Ingested$;
export function Ingested$Ingested$0(value: Ingested$): _.List<
  [string, $channel.ChannelEvent$]
>;
export function Ingested$Ingested$events(value: Ingested$): _.List<
  [string, $channel.ChannelEvent$]
>;
export function Ingested$Ingested$1(value: Ingested$): _.List<
  [string, $channel.Resolution$]
>;
export function Ingested$Ingested$resolutions(value: Ingested$): _.List<
  [string, $channel.Resolution$]
>;
export function Ingested$Ingested$2(value: Ingested$): _.List<SummaryEvent$>;
export function Ingested$Ingested$summary_events(value: Ingested$): _.List<
  SummaryEvent$
>;
export function Ingested$Ingested$3(value: Ingested$): $option.Option$<number>;
export function Ingested$Ingested$request_operations_from(value: Ingested$): $option.Option$<
  number
>;
export function Ingested$Ingested$4(value: Ingested$): _.List<
  $wire.OutboundOperation$
>;
export function Ingested$Ingested$outbound(value: Ingested$): _.List<
  $wire.OutboundOperation$
>;

export type Ingested$ = Ingested;

export class Summary extends _.CustomType {
  /** @deprecated */
  constructor(
    sequence_number: number,
    channels: _.List<[string, $channel.Snapshot$]>,
    members: _.List<number>
  );
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  channels: _.List<[string, $channel.Snapshot$]>;
  /** @deprecated */
  members: _.List<number>;
}
export function Summary$Summary(
  sequence_number: number,
  channels: _.List<[string, $channel.Snapshot$]>,
  members: _.List<number>,
): Summary$;
export function Summary$isSummary(value: any): value is Summary$;
export function Summary$Summary$0(value: Summary$): number;
export function Summary$Summary$sequence_number(value: Summary$): number;
export function Summary$Summary$1(value: Summary$): _.List<
  [string, $channel.Snapshot$]
>;
export function Summary$Summary$channels(value: Summary$): _.List<
  [string, $channel.Snapshot$]
>;
export function Summary$Summary$2(value: Summary$): _.List<number>;
export function Summary$Summary$members(value: Summary$): _.List<number>;

export type Summary$ = Summary;

export class ClaimPending extends _.CustomType {
  /** @deprecated */
  constructor(
    core: Core$,
    outbound: _.List<$wire.OutboundOperation$>,
    immediate_outcome: $option.Option$<$claims_kernel.ClaimOutcome$>
  );
  /** @deprecated */
  core: Core$;
  /** @deprecated */
  outbound: _.List<$wire.OutboundOperation$>;
  /** @deprecated */
  immediate_outcome: $option.Option$<$claims_kernel.ClaimOutcome$>;
}
export function ClaimSubmitResult$ClaimPending(
  core: Core$,
  outbound: _.List<$wire.OutboundOperation$>,
  immediate_outcome: $option.Option$<$claims_kernel.ClaimOutcome$>,
): ClaimSubmitResult$;
export function ClaimSubmitResult$isClaimPending(
  value: any,
): value is ClaimSubmitResult$;
export function ClaimSubmitResult$ClaimPending$0(value: ClaimSubmitResult$): Core$;
export function ClaimSubmitResult$ClaimPending$core(
  value: ClaimSubmitResult$,
): Core$;
export function ClaimSubmitResult$ClaimPending$1(value: ClaimSubmitResult$): _.List<
  $wire.OutboundOperation$
>;
export function ClaimSubmitResult$ClaimPending$outbound(value: ClaimSubmitResult$): _.List<
  $wire.OutboundOperation$
>;
export function ClaimSubmitResult$ClaimPending$2(value: ClaimSubmitResult$): $option.Option$<
  $claims_kernel.ClaimOutcome$
>;
export function ClaimSubmitResult$ClaimPending$immediate_outcome(value: ClaimSubmitResult$): $option.Option$<
  $claims_kernel.ClaimOutcome$
>;

export class ClaimAlreadyClaimed extends _.CustomType {
  /** @deprecated */
  constructor(current_value: $json.Json$);
  /** @deprecated */
  current_value: $json.Json$;
}
export function ClaimSubmitResult$ClaimAlreadyClaimed(
  current_value: $json.Json$,
): ClaimSubmitResult$;
export function ClaimSubmitResult$isClaimAlreadyClaimed(
  value: any,
): value is ClaimSubmitResult$;
export function ClaimSubmitResult$ClaimAlreadyClaimed$0(value: ClaimSubmitResult$): $json.Json$;
export function ClaimSubmitResult$ClaimAlreadyClaimed$current_value(
  value: ClaimSubmitResult$,
): $json.Json$;

export class ClaimAlreadyPendingLocally extends _.CustomType {}
export function ClaimSubmitResult$ClaimAlreadyPendingLocally(
  
): ClaimSubmitResult$;
export function ClaimSubmitResult$isClaimAlreadyPendingLocally(
  value: any,
): value is ClaimSubmitResult$;

export type ClaimSubmitResult$ = ClaimPending | ClaimAlreadyClaimed | ClaimAlreadyPendingLocally;

declare class Detached<AZAR> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: AZAR);
  /** @deprecated */
  0: AZAR;
}

declare class Attached<AZAR> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: AZAR);
  /** @deprecated */
  0: AZAR;
}

type Located$<AZAR> = Detached<AZAR> | Attached<AZAR>;

export function summary_from_blob(blob: $summary_blob.SummaryBlob$): Summary$;

export function set(
  core: Core$,
  address: string,
  key: string,
  value: $json.Json$
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function enqueue_owed(
  core: Core$,
  address: string,
  owed: _.List<$channel.ChannelOperation$>
): Core$;

export function has_channel(core: Core$, address: string): boolean;

export function handle_sequenced(
  core: Core$,
  msg: $types.SequencedDocumentMessage$
): _.Result<[Core$, Ingested$], CoreError$>;

export function bootstrap(
  connected: $message.ConnectedMessage$,
  summary: $option.Option$<Summary$>
): _.Result<Bootstrapped$, CoreError$>;

export function resume_bootstrap(
  core: Core$,
  checkpoint: number,
  deltas: _.List<$types.SequencedDocumentMessage$>
): _.Result<Bootstrapped$, CoreError$>;

export function summary_members(core: Core$): _.List<number>;

export function summary_channels(core: Core$): _.List<
  [string, $channel.Snapshot$]
>;

export function is_synced(core: Core$): boolean;

export function operations_since_summary(core: Core$): number;

export function wants_summary(core: Core$, policy: $summary_policy.Policy$): boolean;

export function summary_jitter_milliseconds(
  core: Core$,
  policy: $summary_policy.Policy$
): number;

export function build_summarize(core: Core$, handle: string, message: string): [
  Core$,
  $wire.OutboundOperation$
];

export function adopt_reconnect(
  core: Core$,
  connected: $message.ConnectedMessage$
): Core$;

export function catch_up_from(core: Core$, checkpoint: number): $option.Option$<
  number
>;

export function go_live(core: Core$): Core$;

export function resubmit(core: Core$): [Core$, _.List<$wire.OutboundOperation$>];

export function create_detached(
  core: Core$,
  address: string,
  init: $channel.ChannelInit$
): Core$;

export function delete$(core: Core$, address: string, key: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function clear(core: Core$, address: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function increment(core: Core$, address: string, amount: number): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function pn_counter_update(core: Core$, address: string, amount: number): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function g_counter_increment(
  core: Core$,
  address: string,
  amount: number
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function lww_register_set(
  core: Core$,
  address: string,
  value: string,
  timestamp: number
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function lww_register_value(core: Core$, address: string): _.Result<
  string,
  undefined
>;

export function lww_map_set(
  core: Core$,
  address: string,
  key: string,
  value: string,
  timestamp: number
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function lww_map_remove(
  core: Core$,
  address: string,
  key: string,
  timestamp: number
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function lww_map_get(core: Core$, address: string, key: string): _.Result<
  string,
  undefined
>;

export function lww_map_entries(core: Core$, address: string): _.List<
  [string, string]
>;

export function lww_map_keys(core: Core$, address: string): _.List<string>;

export function mv_register_set(core: Core$, address: string, value: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function mv_register_values(core: Core$, address: string): _.Result<
  _.List<string>,
  undefined
>;

export function pact_map_set(
  core: Core$,
  address: string,
  key: string,
  value: $json.Json$
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function pact_map_delete(core: Core$, address: string, key: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function ordered_add(core: Core$, address: string, value: $json.Json$): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function ordered_acquire_submit(
  core: Core$,
  address: string,
  acquire_id: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>,
    $option.Option$<$ordered_collection_kernel.AcquireOutcome$>
  ],
  CoreError$
>;

export function ordered_acquire(
  core: Core$,
  address: string,
  acquire_id: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function ordered_complete(
  core: Core$,
  address: string,
  acquire_id: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function ordered_release(
  core: Core$,
  address: string,
  acquire_id: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function directory_set(
  core: Core$,
  address: string,
  path: string,
  key: string,
  value: $json.Json$
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function directory_delete(
  core: Core$,
  address: string,
  path: string,
  key: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function directory_clear(core: Core$, address: string, path: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function directory_create_subdirectory(
  core: Core$,
  address: string,
  path: string,
  name: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function directory_delete_subdirectory(
  core: Core$,
  address: string,
  path: string,
  name: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function submit_json_ot(
  core: Core$,
  address: string,
  components: _.List<$json_ot.Component$>
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function json_ot_view(core: Core$, address: string): _.Result<
  $json_ot.JsonValue$,
  undefined
>;

export function submit_rich_text(
  core: Core$,
  address: string,
  delta: $rich_text.Delta$
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function rich_text_view(core: Core$, address: string): _.Result<
  $rich_text.Document$,
  undefined
>;

export function or_map_increment(
  core: Core$,
  address: string,
  key: string,
  amount: number
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function or_map_set(
  core: Core$,
  address: string,
  key: string,
  value: string,
  timestamp: number
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function or_map_add_member(
  core: Core$,
  address: string,
  key: string,
  member: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function or_map_remove_member(
  core: Core$,
  address: string,
  key: string,
  member: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function or_map_set_mv_register(
  core: Core$,
  address: string,
  key: string,
  value: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function or_map_remove(core: Core$, address: string, key: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function or_set_add(core: Core$, address: string, element: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function or_set_remove(core: Core$, address: string, element: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function sequence_insert(
  core: Core$,
  address: string,
  index: number,
  value: $json.Json$
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function sequence_delete(core: Core$, address: string, index: number): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function sequence_move(
  core: Core$,
  address: string,
  from_index: number,
  to_index: number
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function sequence_replace(
  core: Core$,
  address: string,
  index: number,
  value: $json.Json$
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function text_insert(
  core: Core$,
  address: string,
  index: number,
  value: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function text_delete_range(
  core: Core$,
  address: string,
  start: number,
  end: number
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function text_replace_range(
  core: Core$,
  address: string,
  start: number,
  end: number,
  value: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function text_append(core: Core$, address: string, value: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function g_set_add(core: Core$, address: string, element: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function two_p_set_add(core: Core$, address: string, element: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function two_p_set_remove(core: Core$, address: string, element: string): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function register_write(
  core: Core$,
  address: string,
  key: string,
  value: $json.Json$
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function claim_once(
  core: Core$,
  address: string,
  key: string,
  value: $json.Json$
): _.Result<ClaimSubmitResult$, CoreError$>;

export function compare_and_set_claim(
  core: Core$,
  address: string,
  key: string,
  value: $json.Json$
): _.Result<ClaimSubmitResult$, CoreError$>;

export function task_manager_volunteer(
  core: Core$,
  address: string,
  task_id: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>,
    $task_manager_kernel.VolunteerOutcome$
  ],
  CoreError$
>;

export function task_manager_abandon(
  core: Core$,
  address: string,
  task_id: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function task_manager_complete(
  core: Core$,
  address: string,
  task_id: string
): _.Result<
  [
    Core$,
    _.List<[string, $channel.ChannelEvent$]>,
    _.List<$wire.OutboundOperation$>
  ],
  CoreError$
>;

export function require_channel_type(
  core: Core$,
  address: string,
  expected: $channel.ChannelType$
): _.Result<undefined, CoreError$>;

export function get(core: Core$, address: string, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function has(core: Core$, address: string, key: string): boolean;

export function size(core: Core$, address: string): number;

export function keys(core: Core$, address: string): _.List<string>;

export function entries(core: Core$, address: string): _.List<
  [string, $json.Json$]
>;

export function counter_value(core: Core$, address: string): _.Result<
  number,
  undefined
>;

export function pn_counter_value(core: Core$, address: string): _.Result<
  number,
  undefined
>;

export function g_counter_value(core: Core$, address: string): _.Result<
  number,
  undefined
>;

export function pact_map_get(core: Core$, address: string, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function pact_map_get_with_details(
  core: Core$,
  address: string,
  key: string
): _.Result<$pact_map_kernel.Accepted$, undefined>;

export function pact_map_pending(core: Core$, address: string, key: string): _.Result<
  $pact_map_kernel.Pending$,
  undefined
>;

export function pact_map_is_pending(core: Core$, address: string, key: string): boolean;

export function pact_map_keys(core: Core$, address: string): _.List<string>;

export function ordered_size(core: Core$, address: string): _.Result<
  number,
  undefined
>;

export function ordered_queue(core: Core$, address: string): _.List<$json.Json$>;

export function ordered_jobs(core: Core$, address: string): _.List<
  [string, $ordered_collection_kernel.JobEntry$]
>;

export function or_map_value(core: Core$, address: string, key: string): _.Result<
  $or_map_kernel.OrMapValue$,
  undefined
>;

export function or_map_values(core: Core$, address: string, key: string): _.Result<
  _.List<string>,
  undefined
>;

export function or_map_keys(core: Core$, address: string): _.List<string>;

export function or_map_entries(core: Core$, address: string): _.List<
  [string, $or_map_kernel.OrMapValue$]
>;

export function or_set_contains(core: Core$, address: string, element: string): boolean;

export function or_set_values(core: Core$, address: string): _.List<string>;

export function sequence_values(core: Core$, address: string): _.List<
  $json.Json$
>;

export function sequence_length(core: Core$, address: string): number;

export function text_value(core: Core$, address: string): string;

export function text_length(core: Core$, address: string): number;

export function text_substring(
  core: Core$,
  address: string,
  start: number,
  end: number
): _.Result<string, string>;

export function text_anchor_at(
  core: Core$,
  address: string,
  index: number,
  bias: $sequence.Bias$
): _.Result<$text_kernel.TextAnchor$, string>;

export function text_resolve_anchor(
  core: Core$,
  address: string,
  anchor: $text_kernel.TextAnchor$
): _.Result<number, string>;

export function text_start_anchor(): $text_kernel.TextAnchor$;

export function text_end_anchor(): $text_kernel.TextAnchor$;

export function text_anchor_to_json(anchor: $text_kernel.TextAnchor$): $json.Json$;

export function text_anchor_from_json(json_string: string): _.Result<
  $text_kernel.TextAnchor$,
  string
>;

export function g_set_contains(core: Core$, address: string, element: string): boolean;

export function g_set_values(core: Core$, address: string): _.List<string>;

export function two_p_set_contains(
  core: Core$,
  address: string,
  element: string
): boolean;

export function two_p_set_values(core: Core$, address: string): _.List<string>;

export function directory_get(
  core: Core$,
  address: string,
  path: string,
  key: string
): _.Result<$json.Json$, undefined>;

export function directory_entries(core: Core$, address: string, path: string): _.List<
  [string, $json.Json$]
>;

export function directory_subdirectories(
  core: Core$,
  address: string,
  path: string
): _.List<string>;

export function directory_has_subdirectory(
  core: Core$,
  address: string,
  path: string,
  name: string
): boolean;

export function register_read(
  core: Core$,
  address: string,
  key: string,
  policy: $register_collection_kernel.ReadPolicy$
): _.Result<$json.Json$, undefined>;

export function register_versions(core: Core$, address: string, key: string): _.Result<
  _.List<$json.Json$>,
  undefined
>;

export function register_keys(core: Core$, address: string): _.List<string>;

export function get_claim(core: Core$, address: string, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function has_claim(core: Core$, address: string, key: string): boolean;

export function task_manager_assigned(
  core: Core$,
  address: string,
  task_id: string
): boolean;

export function task_manager_queued(
  core: Core$,
  address: string,
  task_id: string
): boolean;

export function task_manager_queues(core: Core$, address: string): _.List<
  [string, _.List<number>]
>;

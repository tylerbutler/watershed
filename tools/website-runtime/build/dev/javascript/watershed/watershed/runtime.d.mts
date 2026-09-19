import type * as $promise from "../../gleam_javascript/gleam/javascript/promise.d.mts";
import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as $message from "../../spillway/spillway/message.d.mts";
import type * as $nack from "../../spillway/spillway/nack.d.mts";
import type * as $types from "../../spillway/spillway/types.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $channel from "../watershed/channel.d.mts";
import type * as $claims_kernel from "../watershed/claims_kernel.d.mts";
import type * as $git_storage from "../watershed/git_storage.d.mts";
import type * as $json_ot from "../watershed/json_ot.d.mts";
import type * as $or_map_kernel from "../watershed/or_map_kernel.d.mts";
import type * as $ordered_collection_kernel from "../watershed/ordered_collection_kernel.d.mts";
import type * as $pact_map_kernel from "../watershed/pact_map_kernel.d.mts";
import type * as $register_collection_kernel from "../watershed/register_collection_kernel.d.mts";
import type * as $rich_text from "../watershed/rich_text.d.mts";
import type * as $runtime_core from "../watershed/runtime_core.d.mts";
import type * as $summary_policy from "../watershed/summary_policy.d.mts";
import type * as $task_manager_kernel from "../watershed/task_manager_kernel.d.mts";
import type * as $text_kernel from "../watershed/text_kernel.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";
import type * as $wire from "../watershed/wire.d.mts";
import type * as $summary_blob from "../watershed/wire/summary_blob.d.mts";

export class TransportHandle extends _.CustomType {
  /** @deprecated */
  constructor(
    push: (x0: string, x1: $json.Json$) => undefined,
    close: () => undefined,
    drop: () => undefined,
    hold: () => undefined,
    resume: () => undefined
  );
  /** @deprecated */
  push: (x0: string, x1: $json.Json$) => undefined;
  /** @deprecated */
  close: () => undefined;
  /** @deprecated */
  drop: () => undefined;
  /** @deprecated */
  hold: () => undefined;
  /** @deprecated */
  resume: () => undefined;
}
export function TransportHandle$TransportHandle(
  push: (x0: string, x1: $json.Json$) => undefined,
  close: () => undefined,
  drop: () => undefined,
  hold: () => undefined,
  resume: () => undefined,
): TransportHandle$;
export function TransportHandle$isTransportHandle(
  value: any,
): value is TransportHandle$;
export function TransportHandle$TransportHandle$0(value: TransportHandle$): (
  x0: string,
  x1: $json.Json$
) => undefined;
export function TransportHandle$TransportHandle$push(value: TransportHandle$): (
  x0: string,
  x1: $json.Json$
) => undefined;
export function TransportHandle$TransportHandle$1(value: TransportHandle$): () => undefined;
export function TransportHandle$TransportHandle$close(
  value: TransportHandle$,
): () => undefined;
export function TransportHandle$TransportHandle$2(value: TransportHandle$): () => undefined;
export function TransportHandle$TransportHandle$drop(
  value: TransportHandle$,
): () => undefined;
export function TransportHandle$TransportHandle$3(value: TransportHandle$): () => undefined;
export function TransportHandle$TransportHandle$hold(
  value: TransportHandle$,
): () => undefined;
export function TransportHandle$TransportHandle$4(value: TransportHandle$): () => undefined;
export function TransportHandle$TransportHandle$resume(
  value: TransportHandle$,
): () => undefined;

export type TransportHandle$ = TransportHandle;

export class TransportCallbacks extends _.CustomType {
  /** @deprecated */
  constructor(
    on_event: (x0: string, x1: string) => undefined,
    on_join: () => undefined,
    on_close: () => undefined
  );
  /** @deprecated */
  on_event: (x0: string, x1: string) => undefined;
  /** @deprecated */
  on_join: () => undefined;
  /** @deprecated */
  on_close: () => undefined;
}
export function TransportCallbacks$TransportCallbacks(
  on_event: (x0: string, x1: string) => undefined,
  on_join: () => undefined,
  on_close: () => undefined,
): TransportCallbacks$;
export function TransportCallbacks$isTransportCallbacks(
  value: any,
): value is TransportCallbacks$;
export function TransportCallbacks$TransportCallbacks$0(value: TransportCallbacks$): (
  x0: string,
  x1: string
) => undefined;
export function TransportCallbacks$TransportCallbacks$on_event(value: TransportCallbacks$): (
  x0: string,
  x1: string
) => undefined;
export function TransportCallbacks$TransportCallbacks$1(value: TransportCallbacks$): (
  
) => undefined;
export function TransportCallbacks$TransportCallbacks$on_join(value: TransportCallbacks$): (
  
) => undefined;
export function TransportCallbacks$TransportCallbacks$2(value: TransportCallbacks$): (
  
) => undefined;
export function TransportCallbacks$TransportCallbacks$on_close(value: TransportCallbacks$): (
  
) => undefined;

export type TransportCallbacks$ = TransportCallbacks;

export class Transport extends _.CustomType {
  /** @deprecated */
  constructor(connect: (x0: TransportCallbacks$) => TransportHandle$);
  /** @deprecated */
  connect: (x0: TransportCallbacks$) => TransportHandle$;
}
export function Transport$Transport(
  connect: (x0: TransportCallbacks$) => TransportHandle$,
): Transport$;
export function Transport$isTransport(value: any): value is Transport$;
export function Transport$Transport$0(value: Transport$): (
  x0: TransportCallbacks$
) => TransportHandle$;
export function Transport$Transport$connect(value: Transport$): (
  x0: TransportCallbacks$
) => TransportHandle$;

export type Transport$ = Transport;

declare class TransportJoined extends _.CustomType {}

declare class TransportClosed extends _.CustomType {}

declare class TransportReceived extends _.CustomType {
  /** @deprecated */
  constructor(event: string, payload: string);
  /** @deprecated */
  event: string;
  /** @deprecated */
  payload: string;
}

type TransportEvent$ = TransportJoined | TransportClosed | TransportReceived;

export class Pending extends _.CustomType {
  /** @deprecated */
  constructor(outcome: $promise.Promise$<$claims_kernel.ClaimOutcome$>);
  /** @deprecated */
  outcome: $promise.Promise$<$claims_kernel.ClaimOutcome$>;
}
export function ClaimSubmitReply$Pending(
  outcome: $promise.Promise$<$claims_kernel.ClaimOutcome$>,
): ClaimSubmitReply$;
export function ClaimSubmitReply$isPending(
  value: any,
): value is ClaimSubmitReply$;
export function ClaimSubmitReply$Pending$0(value: ClaimSubmitReply$): $promise.Promise$<
  $claims_kernel.ClaimOutcome$
>;
export function ClaimSubmitReply$Pending$outcome(value: ClaimSubmitReply$): $promise.Promise$<
  $claims_kernel.ClaimOutcome$
>;

export class AlreadyClaimed extends _.CustomType {
  /** @deprecated */
  constructor(current_value: $json.Json$);
  /** @deprecated */
  current_value: $json.Json$;
}
export function ClaimSubmitReply$AlreadyClaimed(
  current_value: $json.Json$,
): ClaimSubmitReply$;
export function ClaimSubmitReply$isAlreadyClaimed(
  value: any,
): value is ClaimSubmitReply$;
export function ClaimSubmitReply$AlreadyClaimed$0(value: ClaimSubmitReply$): $json.Json$;
export function ClaimSubmitReply$AlreadyClaimed$current_value(
  value: ClaimSubmitReply$,
): $json.Json$;

export class AlreadyPendingLocally extends _.CustomType {}
export function ClaimSubmitReply$AlreadyPendingLocally(): ClaimSubmitReply$;
export function ClaimSubmitReply$isAlreadyPendingLocally(
  value: any,
): value is ClaimSubmitReply$;

export class WrongChannelType extends _.CustomType {}
export function ClaimSubmitReply$WrongChannelType(): ClaimSubmitReply$;
export function ClaimSubmitReply$isWrongChannelType(
  value: any,
): value is ClaimSubmitReply$;

export type ClaimSubmitReply$ = Pending | AlreadyClaimed | AlreadyPendingLocally | WrongChannelType;

export class PresenceState extends _.CustomType {
  /** @deprecated */
  constructor(payload: string);
  /** @deprecated */
  payload: string;
}
export function PresenceFrame$PresenceState(payload: string): PresenceFrame$;
export function PresenceFrame$isPresenceState(
  value: any,
): value is PresenceFrame$;
export function PresenceFrame$PresenceState$0(value: PresenceFrame$): string;
export function PresenceFrame$PresenceState$payload(value: PresenceFrame$): string;

export class PresenceDiff extends _.CustomType {
  /** @deprecated */
  constructor(payload: string);
  /** @deprecated */
  payload: string;
}
export function PresenceFrame$PresenceDiff(payload: string): PresenceFrame$;
export function PresenceFrame$isPresenceDiff(
  value: any,
): value is PresenceFrame$;
export function PresenceFrame$PresenceDiff$0(value: PresenceFrame$): string;
export function PresenceFrame$PresenceDiff$payload(value: PresenceFrame$): string;

export class PresenceError extends _.CustomType {
  /** @deprecated */
  constructor(payload: string);
  /** @deprecated */
  payload: string;
}
export function PresenceFrame$PresenceError(payload: string): PresenceFrame$;
export function PresenceFrame$isPresenceError(
  value: any,
): value is PresenceFrame$;
export function PresenceFrame$PresenceError$0(value: PresenceFrame$): string;
export function PresenceFrame$PresenceError$payload(value: PresenceFrame$): string;

export class PresenceSession extends _.CustomType {
  /** @deprecated */
  constructor(client_id: string, presence_v1: boolean);
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  presence_v1: boolean;
}
export function PresenceFrame$PresenceSession(
  client_id: string,
  presence_v1: boolean,
): PresenceFrame$;
export function PresenceFrame$isPresenceSession(
  value: any,
): value is PresenceFrame$;
export function PresenceFrame$PresenceSession$0(value: PresenceFrame$): string;
export function PresenceFrame$PresenceSession$client_id(value: PresenceFrame$): string;
export function PresenceFrame$PresenceSession$1(
  value: PresenceFrame$,
): boolean;
export function PresenceFrame$PresenceSession$presence_v1(value: PresenceFrame$): boolean;

export class PresenceSessionLost extends _.CustomType {}
export function PresenceFrame$PresenceSessionLost(): PresenceFrame$;
export function PresenceFrame$isPresenceSessionLost(
  value: any,
): value is PresenceFrame$;

export type PresenceFrame$ = PresenceState | PresenceDiff | PresenceError | PresenceSession | PresenceSessionLost;

declare class Subscriber extends _.CustomType {
  /** @deprecated */
  constructor(
    id: string,
    address: string,
    handler: (x0: $channel.ChannelEvent$) => undefined
  );
  /** @deprecated */
  id: string;
  /** @deprecated */
  address: string;
  /** @deprecated */
  handler: (x0: $channel.ChannelEvent$) => undefined;
}

type Subscriber$ = Subscriber;

declare class Connecting extends _.CustomType {}

declare class Reconnecting extends _.CustomType {
  /** @deprecated */
  constructor(core: $runtime_core.Core$);
  /** @deprecated */
  core: $runtime_core.Core$;
}

declare class Ready extends _.CustomType {
  /** @deprecated */
  constructor(core: $runtime_core.Core$, resubmit_at: $option.Option$<number>);
  /** @deprecated */
  core: $runtime_core.Core$;
  /** @deprecated */
  resubmit_at: $option.Option$<number>;
}

declare class Failed extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}

type Phase$ = Connecting | Reconnecting | Ready | Failed;

declare class PendingSummary extends _.CustomType {
  /** @deprecated */
  constructor(
    tree_id: string,
    client_sequence_number: number,
    proposal_sequence_number: $option.Option$<number>,
    resolve: (x0: _.Result<string, string>) => undefined
  );
  /** @deprecated */
  tree_id: string;
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  proposal_sequence_number: $option.Option$<number>;
  /** @deprecated */
  resolve: (x0: _.Result<string, string>) => undefined;
}

type PendingSummary$ = PendingSummary;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    connect_message: $message.ConnectMessage$,
    http_base_url: string,
    channel: $option.Option$<TransportHandle$>,
    phase: Phase$,
    subscribers: _.List<Subscriber$>,
    ripple_subscribers: _.List<(x0: $message.SignalMessage$) => undefined>,
    presence_subscribers: _.List<(x0: PresenceFrame$) => undefined>,
    supported_features: $dict.Dict$<string, $dynamic.Dynamic$>,
    claim_waiters: $dict.Dict$<
      [string, string],
      (x0: $claims_kernel.ClaimOutcome$) => undefined
    >,
    acquire_waiters: $dict.Dict$<
      [string, string],
      (x0: $ordered_collection_kernel.AcquireOutcome$) => undefined
    >,
    on_ready: (x0: _.Result<undefined, string>) => undefined,
    ready_fired: boolean,
    bootstrap_generation: number,
    bootstrap: $option.Option$<Bootstrap$>,
    auto_summary: $option.Option$<$summary_policy.Policy$>,
    summary_armed: boolean,
    pending_summary: $option.Option$<PendingSummary$>,
    scheduler: $transport_js.Scheduler$
  );
  /** @deprecated */
  connect_message: $message.ConnectMessage$;
  /** @deprecated */
  http_base_url: string;
  /** @deprecated */
  channel: $option.Option$<TransportHandle$>;
  /** @deprecated */
  phase: Phase$;
  /** @deprecated */
  subscribers: _.List<Subscriber$>;
  /** @deprecated */
  ripple_subscribers: _.List<(x0: $message.SignalMessage$) => undefined>;
  /** @deprecated */
  presence_subscribers: _.List<(x0: PresenceFrame$) => undefined>;
  /** @deprecated */
  supported_features: $dict.Dict$<string, $dynamic.Dynamic$>;
  /** @deprecated */
  claim_waiters: $dict.Dict$<
    [string, string],
    (x0: $claims_kernel.ClaimOutcome$) => undefined
  >;
  /** @deprecated */
  acquire_waiters: $dict.Dict$<
    [string, string],
    (x0: $ordered_collection_kernel.AcquireOutcome$) => undefined
  >;
  /** @deprecated */
  on_ready: (x0: _.Result<undefined, string>) => undefined;
  /** @deprecated */
  ready_fired: boolean;
  /** @deprecated */
  bootstrap_generation: number;
  /** @deprecated */
  bootstrap: $option.Option$<Bootstrap$>;
  /** @deprecated */
  auto_summary: $option.Option$<$summary_policy.Policy$>;
  /** @deprecated */
  summary_armed: boolean;
  /** @deprecated */
  pending_summary: $option.Option$<PendingSummary$>;
  /** @deprecated */
  scheduler: $transport_js.Scheduler$;
}

type State$ = State;

declare class Bootstrap extends _.CustomType {
  /** @deprecated */
  constructor(
    batches: _.List<_.List<$types.SequencedDocumentMessage$>>,
    operation_count: number,
    payload_bytes: number,
    draining: boolean
  );
  /** @deprecated */
  batches: _.List<_.List<$types.SequencedDocumentMessage$>>;
  /** @deprecated */
  operation_count: number;
  /** @deprecated */
  payload_bytes: number;
  /** @deprecated */
  draining: boolean;
}

type Bootstrap$ = Bootstrap;

declare class Runtime extends _.CustomType {
  /** @deprecated */
  constructor(cell: $transport_js.Cell$<State$>);
  /** @deprecated */
  cell: $transport_js.Cell$<State$>;
}

export type Runtime$ = Runtime;

declare class SubscriptionToken extends _.CustomType {
  /** @deprecated */
  constructor(runtime: Runtime$, id: string);
  /** @deprecated */
  runtime: Runtime$;
  /** @deprecated */
  id: string;
}

export type SubscriptionToken$ = SubscriptionToken;

export class Diagnostics extends _.CustomType {
  /** @deprecated */
  constructor(
    phase: string,
    client_id: $option.Option$<string>,
    last_seen_sequence_number: $option.Option$<number>,
    next_client_sequence_number: $option.Option$<number>,
    in_flight_count: number,
    buffered_out_of_order_count: number,
    resubmit_checkpoint: $option.Option$<number>,
    synced: boolean,
    operations_since_summary: number,
    summary_pending: boolean
  );
  /** @deprecated */
  phase: string;
  /** @deprecated */
  client_id: $option.Option$<string>;
  /** @deprecated */
  last_seen_sequence_number: $option.Option$<number>;
  /** @deprecated */
  next_client_sequence_number: $option.Option$<number>;
  /** @deprecated */
  in_flight_count: number;
  /** @deprecated */
  buffered_out_of_order_count: number;
  /** @deprecated */
  resubmit_checkpoint: $option.Option$<number>;
  /** @deprecated */
  synced: boolean;
  /** @deprecated */
  operations_since_summary: number;
  /** @deprecated */
  summary_pending: boolean;
}
export function Diagnostics$Diagnostics(
  phase: string,
  client_id: $option.Option$<string>,
  last_seen_sequence_number: $option.Option$<number>,
  next_client_sequence_number: $option.Option$<number>,
  in_flight_count: number,
  buffered_out_of_order_count: number,
  resubmit_checkpoint: $option.Option$<number>,
  synced: boolean,
  operations_since_summary: number,
  summary_pending: boolean,
): Diagnostics$;
export function Diagnostics$isDiagnostics(value: any): value is Diagnostics$;
export function Diagnostics$Diagnostics$0(value: Diagnostics$): string;
export function Diagnostics$Diagnostics$phase(value: Diagnostics$): string;
export function Diagnostics$Diagnostics$1(value: Diagnostics$): $option.Option$<
  string
>;
export function Diagnostics$Diagnostics$client_id(value: Diagnostics$): $option.Option$<
  string
>;
export function Diagnostics$Diagnostics$2(value: Diagnostics$): $option.Option$<
  number
>;
export function Diagnostics$Diagnostics$last_seen_sequence_number(value: Diagnostics$): $option.Option$<
  number
>;
export function Diagnostics$Diagnostics$3(value: Diagnostics$): $option.Option$<
  number
>;
export function Diagnostics$Diagnostics$next_client_sequence_number(value: Diagnostics$): $option.Option$<
  number
>;
export function Diagnostics$Diagnostics$4(value: Diagnostics$): number;
export function Diagnostics$Diagnostics$in_flight_count(value: Diagnostics$): number;
export function Diagnostics$Diagnostics$5(
  value: Diagnostics$,
): number;
export function Diagnostics$Diagnostics$buffered_out_of_order_count(value: Diagnostics$): number;
export function Diagnostics$Diagnostics$6(
  value: Diagnostics$,
): $option.Option$<number>;
export function Diagnostics$Diagnostics$resubmit_checkpoint(value: Diagnostics$): $option.Option$<
  number
>;
export function Diagnostics$Diagnostics$7(value: Diagnostics$): boolean;
export function Diagnostics$Diagnostics$synced(value: Diagnostics$): boolean;
export function Diagnostics$Diagnostics$8(value: Diagnostics$): number;
export function Diagnostics$Diagnostics$operations_since_summary(value: Diagnostics$): number;
export function Diagnostics$Diagnostics$9(
  value: Diagnostics$,
): boolean;
export function Diagnostics$Diagnostics$summary_pending(value: Diagnostics$): boolean;

export type Diagnostics$ = Diagnostics;

export function summarize(runtime: Runtime$): $promise.Promise$<
  _.Result<string, string>
>;

export function start_with_transport(
  http_base_url: string,
  connect_message: $message.ConnectMessage$,
  transport: Transport$,
  on_ready: (x0: _.Result<undefined, string>) => undefined
): Runtime$;

export function start(
  url: string,
  topic: string,
  connect_message: $message.ConnectMessage$,
  on_ready: (x0: _.Result<undefined, string>) => undefined
): Runtime$;

export function set(
  runtime: Runtime$,
  address: string,
  key: string,
  value: $json.Json$
): undefined;

export function delete$(runtime: Runtime$, address: string, key: string): undefined;

export function clear(runtime: Runtime$, address: string): undefined;

export function get(runtime: Runtime$, address: string, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function entries(runtime: Runtime$, address: string): _.List<
  [string, $json.Json$]
>;

export function keys(runtime: Runtime$, address: string): _.List<string>;

export function size(runtime: Runtime$, address: string): number;

export function has(runtime: Runtime$, address: string, key: string): boolean;

export function increment(runtime: Runtime$, address: string, amount: number): undefined;

export function counter_value(runtime: Runtime$, address: string): _.Result<
  number,
  undefined
>;

export function pn_counter_update(
  runtime: Runtime$,
  address: string,
  amount: number
): undefined;

export function pn_counter_value(runtime: Runtime$, address: string): _.Result<
  number,
  undefined
>;

export function g_counter_increment(
  runtime: Runtime$,
  address: string,
  amount: number
): _.Result<undefined, string>;

export function g_counter_value(runtime: Runtime$, address: string): _.Result<
  number,
  undefined
>;

export function lww_register_set(
  runtime: Runtime$,
  address: string,
  value: string
): _.Result<undefined, string>;

export function lww_register_value(runtime: Runtime$, address: string): _.Result<
  string,
  undefined
>;

export function create_lww_map(runtime: Runtime$): _.Result<string, string>;

export function lww_map_set(
  runtime: Runtime$,
  address: string,
  key: string,
  value: string
): _.Result<undefined, string>;

export function lww_map_remove(runtime: Runtime$, address: string, key: string): _.Result<
  undefined,
  string
>;

export function lww_map_get(runtime: Runtime$, address: string, key: string): _.Result<
  string,
  undefined
>;

export function lww_map_entries(runtime: Runtime$, address: string): _.List<
  [string, string]
>;

export function lww_map_keys(runtime: Runtime$, address: string): _.List<string>;

export function pact_map_set(
  runtime: Runtime$,
  address: string,
  key: string,
  value: $json.Json$
): undefined;

export function pact_map_delete(runtime: Runtime$, address: string, key: string): undefined;

export function pact_map_get(runtime: Runtime$, address: string, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function pact_map_keys(runtime: Runtime$, address: string): _.List<
  string
>;

export function pact_map_is_pending(
  runtime: Runtime$,
  address: string,
  key: string
): boolean;

export function pact_map_pending(
  runtime: Runtime$,
  address: string,
  key: string
): _.Result<$pact_map_kernel.Pending$, undefined>;

export function pact_map_get_with_details(
  runtime: Runtime$,
  address: string,
  key: string
): _.Result<$pact_map_kernel.Accepted$, undefined>;

export function ordered_add(
  runtime: Runtime$,
  address: string,
  value: $json.Json$
): undefined;

export function ordered_acquire(runtime: Runtime$, address: string): string;

export function ordered_acquire_with_outcome(
  runtime: Runtime$,
  address: string,
  on_outcome: (x0: $ordered_collection_kernel.AcquireOutcome$) => undefined
): string;

export function ordered_complete(
  runtime: Runtime$,
  address: string,
  acquire_id: string
): undefined;

export function ordered_release(
  runtime: Runtime$,
  address: string,
  acquire_id: string
): undefined;

export function ordered_size(runtime: Runtime$, address: string): _.Result<
  number,
  undefined
>;

export function ordered_queue(runtime: Runtime$, address: string): _.List<
  $json.Json$
>;

export function ordered_jobs(runtime: Runtime$, address: string): _.List<
  [string, $ordered_collection_kernel.JobEntry$]
>;

export function submit_json_ot(
  runtime: Runtime$,
  address: string,
  components: _.List<$json_ot.Component$>
): undefined;

export function json_ot_view(runtime: Runtime$, address: string): _.Result<
  $json_ot.JsonValue$,
  undefined
>;

export function submit_rich_text(
  runtime: Runtime$,
  address: string,
  delta: $rich_text.Delta$
): undefined;

export function rich_text_view(runtime: Runtime$, address: string): _.Result<
  $rich_text.Document$,
  undefined
>;

export function or_map_increment(
  runtime: Runtime$,
  address: string,
  key: string,
  amount: number
): undefined;

export function or_map_set(
  runtime: Runtime$,
  address: string,
  key: string,
  value: string
): undefined;

export function or_map_remove(runtime: Runtime$, address: string, key: string): undefined;

export function or_map_add_member(
  runtime: Runtime$,
  address: string,
  key: string,
  member: string
): _.Result<undefined, string>;

export function or_map_set_mv_register(
  runtime: Runtime$,
  address: string,
  key: string,
  value: string
): undefined;

export function or_map_remove_member(
  runtime: Runtime$,
  address: string,
  key: string,
  member: string
): _.Result<undefined, string>;

export function or_map_remove_key(
  runtime: Runtime$,
  address: string,
  key: string
): _.Result<undefined, string>;

export function or_map_values(runtime: Runtime$, address: string, key: string): _.Result<
  _.List<string>,
  undefined
>;

export function or_map_value(runtime: Runtime$, address: string, key: string): _.Result<
  $or_map_kernel.OrMapValue$,
  undefined
>;

export function or_map_entries(runtime: Runtime$, address: string): _.List<
  [string, $or_map_kernel.OrMapValue$]
>;

export function or_map_keys(runtime: Runtime$, address: string): _.List<string>;

export function or_set_add(runtime: Runtime$, address: string, element: string): undefined;

export function or_set_remove(
  runtime: Runtime$,
  address: string,
  element: string
): undefined;

export function or_set_contains(
  runtime: Runtime$,
  address: string,
  element: string
): boolean;

export function or_set_values(runtime: Runtime$, address: string): _.List<
  string
>;

export function g_set_add(runtime: Runtime$, address: string, element: string): undefined;

export function g_set_contains(
  runtime: Runtime$,
  address: string,
  element: string
): boolean;

export function g_set_values(runtime: Runtime$, address: string): _.List<string>;

export function sequence_insert(
  runtime: Runtime$,
  address: string,
  index: number,
  value: $json.Json$
): _.Result<undefined, string>;

export function sequence_delete(
  runtime: Runtime$,
  address: string,
  index: number
): _.Result<undefined, string>;

export function sequence_move(
  runtime: Runtime$,
  address: string,
  from_index: number,
  to_index: number
): _.Result<undefined, string>;

export function sequence_replace(
  runtime: Runtime$,
  address: string,
  index: number,
  value: $json.Json$
): _.Result<undefined, string>;

export function sequence_values(runtime: Runtime$, address: string): _.List<
  $json.Json$
>;

export function sequence_length(runtime: Runtime$, address: string): number;

export function text_insert(
  runtime: Runtime$,
  address: string,
  index: number,
  value: string
): _.Result<undefined, string>;

export function text_delete_range(
  runtime: Runtime$,
  address: string,
  start: number,
  end: number
): _.Result<undefined, string>;

export function text_replace_range(
  runtime: Runtime$,
  address: string,
  start: number,
  end: number,
  value: string
): _.Result<undefined, string>;

export function text_append(runtime: Runtime$, address: string, value: string): _.Result<
  undefined,
  string
>;

export function text_value(runtime: Runtime$, address: string): string;

export function text_length(runtime: Runtime$, address: string): number;

export function text_substring(
  runtime: Runtime$,
  address: string,
  start: number,
  end: number
): _.Result<string, string>;

export function text_anchor_at(
  runtime: Runtime$,
  address: string,
  index: number,
  bias: $sequence.Bias$
): _.Result<$text_kernel.TextAnchor$, string>;

export function text_resolve_anchor(
  runtime: Runtime$,
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

export function create_directory(runtime: Runtime$): _.Result<string, string>;

export function directory_set(
  runtime: Runtime$,
  address: string,
  path: string,
  key: string,
  value: $json.Json$
): undefined;

export function directory_delete(
  runtime: Runtime$,
  address: string,
  path: string,
  key: string
): undefined;

export function directory_clear(
  runtime: Runtime$,
  address: string,
  path: string
): undefined;

export function directory_create_subdirectory(
  runtime: Runtime$,
  address: string,
  path: string,
  name: string
): undefined;

export function directory_delete_subdirectory(
  runtime: Runtime$,
  address: string,
  path: string,
  name: string
): undefined;

export function directory_get(
  runtime: Runtime$,
  address: string,
  path: string,
  key: string
): _.Result<$json.Json$, undefined>;

export function directory_entries(
  runtime: Runtime$,
  address: string,
  path: string
): _.List<[string, $json.Json$]>;

export function directory_subdirectories(
  runtime: Runtime$,
  address: string,
  path: string
): _.List<string>;

export function directory_has_subdirectory(
  runtime: Runtime$,
  address: string,
  path: string,
  name: string
): boolean;

export function two_p_set_add(
  runtime: Runtime$,
  address: string,
  element: string
): undefined;

export function two_p_set_remove(
  runtime: Runtime$,
  address: string,
  element: string
): undefined;

export function two_p_set_contains(
  runtime: Runtime$,
  address: string,
  element: string
): boolean;

export function two_p_set_values(runtime: Runtime$, address: string): _.List<
  string
>;

export function register_write(
  runtime: Runtime$,
  address: string,
  key: string,
  value: $json.Json$
): undefined;

export function register_read(
  runtime: Runtime$,
  address: string,
  key: string,
  policy: $register_collection_kernel.ReadPolicy$
): _.Result<$json.Json$, undefined>;

export function register_versions(
  runtime: Runtime$,
  address: string,
  key: string
): _.Result<_.List<$json.Json$>, undefined>;

export function register_keys(runtime: Runtime$, address: string): _.List<
  string
>;

export function get_claim(runtime: Runtime$, address: string, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function has_claim(runtime: Runtime$, address: string, key: string): boolean;

export function claim_once(
  runtime: Runtime$,
  address: string,
  key: string,
  value: $json.Json$
): ClaimSubmitReply$;

export function compare_and_set_claim(
  runtime: Runtime$,
  address: string,
  key: string,
  value: $json.Json$
): ClaimSubmitReply$;

export function task_manager_volunteer(
  runtime: Runtime$,
  address: string,
  task_id: string
): $task_manager_kernel.VolunteerOutcome$;

export function task_manager_abandon(
  runtime: Runtime$,
  address: string,
  task_id: string
): undefined;

export function task_manager_complete(
  runtime: Runtime$,
  address: string,
  task_id: string
): _.Result<undefined, string>;

export function task_manager_assigned(
  runtime: Runtime$,
  address: string,
  task_id: string
): boolean;

export function task_manager_queued(
  runtime: Runtime$,
  address: string,
  task_id: string
): boolean;

export function task_manager_queues(runtime: Runtime$, address: string): _.List<
  [string, _.List<number>]
>;

export function create_map(runtime: Runtime$): _.Result<string, string>;

export function create_counter(runtime: Runtime$): _.Result<string, string>;

export function create_pn_counter(runtime: Runtime$): _.Result<string, string>;

export function create_g_counter(runtime: Runtime$): _.Result<string, string>;

export function create_lww_register(runtime: Runtime$): _.Result<string, string>;

export function create_pact_map(runtime: Runtime$): _.Result<string, string>;

export function create_ordered_collection(runtime: Runtime$): _.Result<
  string,
  string
>;

export function create_or_map(
  runtime: Runtime$,
  mode: $or_map_kernel.OrMapMode$
): _.Result<string, string>;

export function create_or_set(runtime: Runtime$): _.Result<string, string>;

export function create_g_set(runtime: Runtime$): _.Result<string, string>;

export function create_sequence(runtime: Runtime$): _.Result<string, string>;

export function create_text(runtime: Runtime$): _.Result<string, string>;

export function create_two_p_set(runtime: Runtime$): _.Result<string, string>;

export function create_register_collection(runtime: Runtime$): _.Result<
  string,
  string
>;

export function create_claims(runtime: Runtime$): _.Result<string, string>;

export function create_json_ot(runtime: Runtime$): _.Result<string, string>;

export function create_rich_text(runtime: Runtime$): _.Result<string, string>;

export function create_task_manager(runtime: Runtime$): _.Result<string, string>;

export function resolve_address(runtime: Runtime$, address: string): _.Result<
  undefined,
  string
>;

export function resolve_sequence(runtime: Runtime$, address: string): _.Result<
  undefined,
  string
>;

export function resolve_text(runtime: Runtime$, address: string): _.Result<
  undefined,
  string
>;

export function subscribe(
  runtime: Runtime$,
  address: string,
  handler: (x0: $channel.ChannelEvent$) => undefined
): SubscriptionToken$;

export function unsubscribe(token: SubscriptionToken$): undefined;

export function client_id(runtime: Runtime$): $option.Option$<string>;

export function send_ripple(
  runtime: Runtime$,
  ripple_type: string,
  content: $json.Json$
): undefined;

export function subscribe_ripples(
  runtime: Runtime$,
  handler: (x0: $message.SignalMessage$) => undefined
): undefined;

export function send_presence(
  runtime: Runtime$,
  event: string,
  payload: $json.Json$
): undefined;

export function subscribe_presence(
  runtime: Runtime$,
  handler: (x0: PresenceFrame$) => undefined
): undefined;

export function supports_presence(runtime: Runtime$): boolean;

export function user_id(runtime: Runtime$): string;

export function force_reconnect(runtime: Runtime$): undefined;

export function go_offline(runtime: Runtime$): undefined;

export function go_online(runtime: Runtime$): undefined;

export function close(runtime: Runtime$): undefined;

export function is_synced(runtime: Runtime$): boolean;

export function diagnostics(runtime: Runtime$): Diagnostics$;

export function set_scheduler(
  runtime: Runtime$,
  scheduler: $transport_js.Scheduler$
): undefined;

export function schedule(
  runtime: Runtime$,
  action: () => undefined,
  milliseconds: number
): undefined;

export function auto_summarize(
  runtime: Runtime$,
  policy: $option.Option$<$summary_policy.Policy$>
): undefined;

export function operations_since_summary(runtime: Runtime$): number;

export function get_versions(runtime: Runtime$, count: number): $promise.Promise$<
  _.Result<_.List<$git_storage.SummaryVersion$>, string>
>;

export function load_version(runtime: Runtime$, handle: string): $promise.Promise$<
  _.Result<$summary_blob.SummaryBlob$, string>
>;

export function create_mv_register(runtime: Runtime$): _.Result<string, string>;

export function mv_register_set(
  runtime: Runtime$,
  address: string,
  value: string
): undefined;

export function mv_register_values(runtime: Runtime$, address: string): _.Result<
  _.List<string>,
  undefined
>;

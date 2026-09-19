import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as $g_counter from "../../../lattice_counters/lattice_counters/g_counter.d.mts";
import type * as $pn_counter from "../../../lattice_counters/lattice_counters/pn_counter.d.mts";
import type * as $crdt from "../../../lattice_maps/lattice_maps/crdt.d.mts";
import type * as $sequence from "../../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as $g_set from "../../../lattice_sets/lattice_sets/g_set.d.mts";
import type * as $or_set from "../../../lattice_sets/lattice_sets/or_set.d.mts";
import type * as $two_p_set from "../../../lattice_sets/lattice_sets/two_p_set.d.mts";
import type * as $text from "../../../lattice_text/lattice_text/text.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $channel from "../../watershed/channel.d.mts";
import type * as $claims_kernel from "../../watershed/claims_kernel.d.mts";
import type * as $counter_kernel from "../../watershed/counter_kernel.d.mts";
import type * as $directory_kernel from "../../watershed/directory_kernel.d.mts";
import type * as $g_counter_kernel from "../../watershed/g_counter_kernel.d.mts";
import type * as $g_set_kernel from "../../watershed/g_set_kernel.d.mts";
import type * as $json_ot_kernel from "../../watershed/json_ot_kernel.d.mts";
import type * as $lww_map_kernel from "../../watershed/lww_map_kernel.d.mts";
import type * as $lww_register_kernel from "../../watershed/lww_register_kernel.d.mts";
import type * as $map_kernel from "../../watershed/map_kernel.d.mts";
import type * as $mv_register_kernel from "../../watershed/mv_register_kernel.d.mts";
import type * as $or_map_kernel from "../../watershed/or_map_kernel.d.mts";
import type * as $or_set_kernel from "../../watershed/or_set_kernel.d.mts";
import type * as $ordered_collection_kernel from "../../watershed/ordered_collection_kernel.d.mts";
import type * as $pact_map_kernel from "../../watershed/pact_map_kernel.d.mts";
import type * as $pn_counter_kernel from "../../watershed/pn_counter_kernel.d.mts";
import type * as $register_collection_kernel from "../../watershed/register_collection_kernel.d.mts";
import type * as $rich_text from "../../watershed/rich_text.d.mts";
import type * as $rich_text_kernel from "../../watershed/rich_text_kernel.d.mts";
import type * as $sequence_kernel from "../../watershed/sequence_kernel.d.mts";
import type * as $task_manager_kernel from "../../watershed/task_manager_kernel.d.mts";
import type * as $text_kernel from "../../watershed/text_kernel.d.mts";
import type * as $two_p_set_kernel from "../../watershed/two_p_set_kernel.d.mts";
import type * as $wire from "../../watershed/wire.d.mts";

export class ChannelOperation extends _.CustomType {
  /** @deprecated */
  constructor(address: string, contents: $dynamic.Dynamic$);
  /** @deprecated */
  address: string;
  /** @deprecated */
  contents: $dynamic.Dynamic$;
}
export function OperationContents$ChannelOperation(
  address: string,
  contents: $dynamic.Dynamic$,
): OperationContents$;
export function OperationContents$isChannelOperation(
  value: any,
): value is OperationContents$;
export function OperationContents$ChannelOperation$0(value: OperationContents$): string;
export function OperationContents$ChannelOperation$address(
  value: OperationContents$,
): string;
export function OperationContents$ChannelOperation$1(value: OperationContents$): $dynamic.Dynamic$;
export function OperationContents$ChannelOperation$contents(
  value: OperationContents$,
): $dynamic.Dynamic$;

export class AttachOperation extends _.CustomType {
  /** @deprecated */
  constructor(address: string, snapshot: $channel.Snapshot$);
  /** @deprecated */
  address: string;
  /** @deprecated */
  snapshot: $channel.Snapshot$;
}
export function OperationContents$AttachOperation(
  address: string,
  snapshot: $channel.Snapshot$,
): OperationContents$;
export function OperationContents$isAttachOperation(
  value: any,
): value is OperationContents$;
export function OperationContents$AttachOperation$0(value: OperationContents$): string;
export function OperationContents$AttachOperation$address(
  value: OperationContents$,
): string;
export function OperationContents$AttachOperation$1(value: OperationContents$): $channel.Snapshot$;
export function OperationContents$AttachOperation$snapshot(
  value: OperationContents$,
): $channel.Snapshot$;

export type OperationContents$ = ChannelOperation | AttachOperation;

export function OperationContents$address(value: OperationContents$): string;

export function encode_text_operation(operation: $text_kernel.TextOperation$): $json.Json$;

export function encode_rich_text_operation(
  operation: $rich_text_kernel.RichTextWireOperation$
): $json.Json$;

export function encode_sequence_operation(
  operation: $sequence_kernel.SequenceOperation$
): $json.Json$;

export function encode_ordered_operation(
  operation: $ordered_collection_kernel.OrderedOperation$
): $json.Json$;

export function encode_pact_map_operation(
  operation: $pact_map_kernel.PactMapOperation$
): $json.Json$;

export function encode_directory_operation(
  operation: $directory_kernel.DirectoryOperation$,
  message_id: number
): $json.Json$;

export function encode_json_ot_operation(
  operation: $json_ot_kernel.JsonOtWireOperation$
): $json.Json$;

export function encode_task_manager_operation(
  operation: $task_manager_kernel.TaskManagerOperation$
): $json.Json$;

export function encode_claim_operation(
  operation: $claims_kernel.ClaimOperation$
): $json.Json$;

export function encode_register_collection_operation(
  operation: $register_collection_kernel.WriteOperation$
): $json.Json$;

export function encode_two_p_set_operation(
  operation: $two_p_set_kernel.TwoPSetOperation$
): $json.Json$;

export function encode_g_set_operation(operation: $g_set_kernel.GSetOperation$): $json.Json$;

export function encode_or_set_operation(
  operation: $or_set_kernel.OrSetOperation$
): $json.Json$;

export function encode_or_map_operation(
  operation: $or_map_kernel.OrMapOperation$
): $json.Json$;

export function encode_lww_map_operation(
  operation: $lww_map_kernel.LwwMapOperation$
): $json.Json$;

export function encode_lww_register_operation(
  operation: $lww_register_kernel.LwwRegisterOperation$
): $json.Json$;

export function encode_mv_register_operation(
  operation: $mv_register_kernel.MvRegisterOperation$
): $json.Json$;

export function encode_g_counter_operation(
  operation: $g_counter_kernel.GCounterOperation$
): $json.Json$;

export function encode_pn_counter_operation(
  operation: $pn_counter_kernel.PnCounterOperation$
): $json.Json$;

export function encode_counter_operation(
  operation: $counter_kernel.CounterOperation$
): $json.Json$;

export function encode_map_operation(operation: $map_kernel.MapOperation$): $json.Json$;

export function encode_channel_operation(operation: $channel.ChannelOperation$): $json.Json$;

export function encode_channel_envelope(
  address: string,
  operation: $channel.ChannelOperation$
): $json.Json$;

export function outbound_channel_operation(
  address: string,
  client_sequence_number: number,
  reference_sequence_number: number,
  operation: $channel.ChannelOperation$
): $wire.OutboundOperation$;

export function encode_attach(address: string, snapshot: $channel.Snapshot$): $json.Json$;

export function outbound_attach_operation(
  address: string,
  client_sequence_number: number,
  reference_sequence_number: number,
  snapshot: $channel.Snapshot$
): $wire.OutboundOperation$;

export function outbound_summarize_operation(
  client_sequence_number: number,
  reference_sequence_number: number,
  handle: string,
  message: string,
  parents: _.List<string>,
  head: string
): $wire.OutboundOperation$;

export function text_operation_decoder(): $decode.Decoder$<
  $text_kernel.TextOperation$
>;

export function rich_text_operation_decoder(): $decode.Decoder$<
  $rich_text_kernel.RichTextWireOperation$
>;

export function sequence_operation_decoder(): $decode.Decoder$<
  $sequence_kernel.SequenceOperation$
>;

export function ordered_operation_decoder(): $decode.Decoder$<
  $ordered_collection_kernel.OrderedOperation$
>;

export function pact_map_operation_decoder(): $decode.Decoder$<
  $pact_map_kernel.PactMapOperation$
>;

export function json_ot_operation_decoder(): $decode.Decoder$<
  $json_ot_kernel.JsonOtWireOperation$
>;

export function task_manager_operation_decoder(): $decode.Decoder$<
  $task_manager_kernel.TaskManagerOperation$
>;

export function claim_operation_decoder(): $decode.Decoder$<
  $claims_kernel.ClaimOperation$
>;

export function register_collection_operation_decoder(): $decode.Decoder$<
  $register_collection_kernel.WriteOperation$
>;

export function two_p_set_operation_decoder(): $decode.Decoder$<
  $two_p_set_kernel.TwoPSetOperation$
>;

export function g_set_operation_decoder(): $decode.Decoder$<
  $g_set_kernel.GSetOperation$
>;

export function or_set_operation_decoder(): $decode.Decoder$<
  $or_set_kernel.OrSetOperation$
>;

export function or_map_operation_decoder(): $decode.Decoder$<
  $or_map_kernel.OrMapOperation$
>;

export function lww_map_operation_decoder(): $decode.Decoder$<
  $lww_map_kernel.LwwMapOperation$
>;

export function lww_register_operation_decoder(): $decode.Decoder$<
  $lww_register_kernel.LwwRegisterOperation$
>;

export function mv_register_operation_decoder(): $decode.Decoder$<
  $mv_register_kernel.MvRegisterOperation$
>;

export function g_counter_operation_decoder(): $decode.Decoder$<
  $g_counter_kernel.GCounterOperation$
>;

export function pn_counter_operation_decoder(): $decode.Decoder$<
  $pn_counter_kernel.PnCounterOperation$
>;

export function counter_operation_decoder(): $decode.Decoder$<
  $counter_kernel.CounterOperation$
>;

export function map_operation_decoder(): $decode.Decoder$<
  $map_kernel.MapOperation$
>;

export function channel_operation_decoder(channel_type: $channel.ChannelType$): $decode.Decoder$<
  $channel.ChannelOperation$
>;

export function encode_map_envelope(
  address: string,
  operation: $map_kernel.MapOperation$
): $json.Json$;

export function encode_counter_envelope(
  address: string,
  operation: $counter_kernel.CounterOperation$
): $json.Json$;

export function encode_pn_counter_envelope(
  address: string,
  operation: $pn_counter_kernel.PnCounterOperation$
): $json.Json$;

export function encode_g_counter_envelope(
  address: string,
  operation: $g_counter_kernel.GCounterOperation$
): $json.Json$;

export function encode_lww_register_envelope(
  address: string,
  operation: $lww_register_kernel.LwwRegisterOperation$
): $json.Json$;

export function encode_lww_map_envelope(
  address: string,
  operation: $lww_map_kernel.LwwMapOperation$
): $json.Json$;

export function lww_map_envelope_decoder(): $decode.Decoder$<
  [string, $lww_map_kernel.LwwMapOperation$]
>;

export function decode_lww_map_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $lww_map_kernel.LwwMapOperation$],
  _.List<$decode.DecodeError$>
>;

export function lww_register_envelope_decoder(): $decode.Decoder$<
  [string, $lww_register_kernel.LwwRegisterOperation$]
>;

export function decode_lww_register_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $lww_register_kernel.LwwRegisterOperation$],
  _.List<$decode.DecodeError$>
>;

export function encode_mv_register_envelope(
  address: string,
  operation: $mv_register_kernel.MvRegisterOperation$
): $json.Json$;

export function mv_register_envelope_decoder(): $decode.Decoder$<
  [string, $mv_register_kernel.MvRegisterOperation$]
>;

export function decode_mv_register_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $mv_register_kernel.MvRegisterOperation$],
  _.List<$decode.DecodeError$>
>;

export function encode_or_map_envelope(
  address: string,
  operation: $or_map_kernel.OrMapOperation$
): $json.Json$;

export function encode_or_set_envelope(
  address: string,
  operation: $or_set_kernel.OrSetOperation$
): $json.Json$;

export function encode_g_set_envelope(
  address: string,
  operation: $g_set_kernel.GSetOperation$
): $json.Json$;

export function encode_two_p_set_envelope(
  address: string,
  operation: $two_p_set_kernel.TwoPSetOperation$
): $json.Json$;

export function encode_register_collection_envelope(
  address: string,
  operation: $register_collection_kernel.WriteOperation$
): $json.Json$;

export function encode_claim_envelope(
  address: string,
  operation: $claims_kernel.ClaimOperation$
): $json.Json$;

export function encode_task_manager_envelope(
  address: string,
  operation: $task_manager_kernel.TaskManagerOperation$
): $json.Json$;

export function encode_pact_map_envelope(
  address: string,
  operation: $pact_map_kernel.PactMapOperation$
): $json.Json$;

export function pact_map_envelope_decoder(): $decode.Decoder$<
  [string, $pact_map_kernel.PactMapOperation$]
>;

export function decode_pact_map_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $pact_map_kernel.PactMapOperation$],
  _.List<$decode.DecodeError$>
>;

export function encode_ordered_envelope(
  address: string,
  operation: $ordered_collection_kernel.OrderedOperation$
): $json.Json$;

export function ordered_envelope_decoder(): $decode.Decoder$<
  [string, $ordered_collection_kernel.OrderedOperation$]
>;

export function decode_ordered_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $ordered_collection_kernel.OrderedOperation$],
  _.List<$decode.DecodeError$>
>;

export function map_envelope_decoder(): $decode.Decoder$<
  [string, $map_kernel.MapOperation$]
>;

export function decode_map_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $map_kernel.MapOperation$],
  _.List<$decode.DecodeError$>
>;

export function counter_envelope_decoder(): $decode.Decoder$<
  [string, $counter_kernel.CounterOperation$]
>;

export function decode_counter_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $counter_kernel.CounterOperation$],
  _.List<$decode.DecodeError$>
>;

export function pn_counter_envelope_decoder(): $decode.Decoder$<
  [string, $pn_counter_kernel.PnCounterOperation$]
>;

export function decode_pn_counter_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $pn_counter_kernel.PnCounterOperation$],
  _.List<$decode.DecodeError$>
>;

export function g_counter_envelope_decoder(): $decode.Decoder$<
  [string, $g_counter_kernel.GCounterOperation$]
>;

export function decode_g_counter_envelope(contents: $dynamic.Dynamic$): _.Result<
  [string, $g_counter_kernel.GCounterOperation$],
  _.List<$decode.DecodeError$>
>;

export function attach_envelope_decoder(): $decode.Decoder$<OperationContents$>;

export function decode_operation_contents(contents: $dynamic.Dynamic$): _.Result<
  OperationContents$,
  _.List<$decode.DecodeError$>
>;

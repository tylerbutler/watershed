import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $g_counter from "../../lattice_counters/lattice_counters/g_counter.d.mts";
import type * as $pn_counter from "../../lattice_counters/lattice_counters/pn_counter.d.mts";
import type * as $crdt from "../../lattice_maps/lattice_maps/crdt.d.mts";
import type * as $lww_register from "../../lattice_registers/lattice_registers/lww_register.d.mts";
import type * as $mv_register from "../../lattice_registers/lattice_registers/mv_register.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as $g_set from "../../lattice_sets/lattice_sets/g_set.d.mts";
import type * as $or_set from "../../lattice_sets/lattice_sets/or_set.d.mts";
import type * as $two_p_set from "../../lattice_sets/lattice_sets/two_p_set.d.mts";
import type * as $text from "../../lattice_text/lattice_text/text.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $claims_kernel from "../watershed/claims_kernel.d.mts";
import type * as $counter_kernel from "../watershed/counter_kernel.d.mts";
import type * as $directory_kernel from "../watershed/directory_kernel.d.mts";
import type * as $g_counter_kernel from "../watershed/g_counter_kernel.d.mts";
import type * as $g_set_kernel from "../watershed/g_set_kernel.d.mts";
import type * as $json_ot from "../watershed/json_ot.d.mts";
import type * as $json_ot_kernel from "../watershed/json_ot_kernel.d.mts";
import type * as $lww_map_kernel from "../watershed/lww_map_kernel.d.mts";
import type * as $lww_register_kernel from "../watershed/lww_register_kernel.d.mts";
import type * as $map_kernel from "../watershed/map_kernel.d.mts";
import type * as $mv_register_kernel from "../watershed/mv_register_kernel.d.mts";
import type * as $or_map_kernel from "../watershed/or_map_kernel.d.mts";
import type * as $or_set_kernel from "../watershed/or_set_kernel.d.mts";
import type * as $ordered_collection_kernel from "../watershed/ordered_collection_kernel.d.mts";
import type * as $pact_map_kernel from "../watershed/pact_map_kernel.d.mts";
import type * as $pn_counter_kernel from "../watershed/pn_counter_kernel.d.mts";
import type * as $register_collection_kernel from "../watershed/register_collection_kernel.d.mts";
import type * as $rich_text from "../watershed/rich_text.d.mts";
import type * as $rich_text_kernel from "../watershed/rich_text_kernel.d.mts";
import type * as $sequence_kernel from "../watershed/sequence_kernel.d.mts";
import type * as $task_manager_kernel from "../watershed/task_manager_kernel.d.mts";
import type * as $text_kernel from "../watershed/text_kernel.d.mts";
import type * as $two_p_set_kernel from "../watershed/two_p_set_kernel.d.mts";

export class MapChannel extends _.CustomType {}
export function ChannelType$MapChannel(): ChannelType$;
export function ChannelType$isMapChannel(value: any): value is ChannelType$;

export class CounterChannel extends _.CustomType {}
export function ChannelType$CounterChannel(): ChannelType$;
export function ChannelType$isCounterChannel(value: any): value is ChannelType$;

export class PnCounterChannel extends _.CustomType {}
export function ChannelType$PnCounterChannel(): ChannelType$;
export function ChannelType$isPnCounterChannel(
  value: any,
): value is ChannelType$;

export class GCounterChannel extends _.CustomType {}
export function ChannelType$GCounterChannel(): ChannelType$;
export function ChannelType$isGCounterChannel(
  value: any,
): value is ChannelType$;

export class LwwRegisterChannel extends _.CustomType {}
export function ChannelType$LwwRegisterChannel(): ChannelType$;
export function ChannelType$isLwwRegisterChannel(
  value: any,
): value is ChannelType$;

export class LwwMapChannel extends _.CustomType {}
export function ChannelType$LwwMapChannel(): ChannelType$;
export function ChannelType$isLwwMapChannel(value: any): value is ChannelType$;

export class MvRegisterChannel extends _.CustomType {}
export function ChannelType$MvRegisterChannel(): ChannelType$;
export function ChannelType$isMvRegisterChannel(
  value: any,
): value is ChannelType$;

export class OrMapChannel extends _.CustomType {}
export function ChannelType$OrMapChannel(): ChannelType$;
export function ChannelType$isOrMapChannel(value: any): value is ChannelType$;

export class OrSetChannel extends _.CustomType {}
export function ChannelType$OrSetChannel(): ChannelType$;
export function ChannelType$isOrSetChannel(value: any): value is ChannelType$;

export class GSetChannel extends _.CustomType {}
export function ChannelType$GSetChannel(): ChannelType$;
export function ChannelType$isGSetChannel(value: any): value is ChannelType$;

export class TwoPSetChannel extends _.CustomType {}
export function ChannelType$TwoPSetChannel(): ChannelType$;
export function ChannelType$isTwoPSetChannel(value: any): value is ChannelType$;

export class RegisterCollectionChannel extends _.CustomType {}
export function ChannelType$RegisterCollectionChannel(): ChannelType$;
export function ChannelType$isRegisterCollectionChannel(
  value: any,
): value is ChannelType$;

export class ClaimsChannel extends _.CustomType {}
export function ChannelType$ClaimsChannel(): ChannelType$;
export function ChannelType$isClaimsChannel(value: any): value is ChannelType$;

export class TaskManagerChannel extends _.CustomType {}
export function ChannelType$TaskManagerChannel(): ChannelType$;
export function ChannelType$isTaskManagerChannel(
  value: any,
): value is ChannelType$;

export class PactMapChannel extends _.CustomType {}
export function ChannelType$PactMapChannel(): ChannelType$;
export function ChannelType$isPactMapChannel(value: any): value is ChannelType$;

export class JsonOtChannel extends _.CustomType {}
export function ChannelType$JsonOtChannel(): ChannelType$;
export function ChannelType$isJsonOtChannel(value: any): value is ChannelType$;

export class DirectoryChannel extends _.CustomType {}
export function ChannelType$DirectoryChannel(): ChannelType$;
export function ChannelType$isDirectoryChannel(
  value: any,
): value is ChannelType$;

export class OrderedCollectionChannel extends _.CustomType {}
export function ChannelType$OrderedCollectionChannel(): ChannelType$;
export function ChannelType$isOrderedCollectionChannel(
  value: any,
): value is ChannelType$;

export class SequenceChannel extends _.CustomType {}
export function ChannelType$SequenceChannel(): ChannelType$;
export function ChannelType$isSequenceChannel(
  value: any,
): value is ChannelType$;

export class RichTextChannel extends _.CustomType {}
export function ChannelType$RichTextChannel(): ChannelType$;
export function ChannelType$isRichTextChannel(
  value: any,
): value is ChannelType$;

export class TextChannel extends _.CustomType {}
export function ChannelType$TextChannel(): ChannelType$;
export function ChannelType$isTextChannel(value: any): value is ChannelType$;

export type ChannelType$ = MapChannel | CounterChannel | PnCounterChannel | GCounterChannel | LwwRegisterChannel | LwwMapChannel | MvRegisterChannel | OrMapChannel | OrSetChannel | GSetChannel | TwoPSetChannel | RegisterCollectionChannel | ClaimsChannel | TaskManagerChannel | PactMapChannel | JsonOtChannel | DirectoryChannel | OrderedCollectionChannel | SequenceChannel | RichTextChannel | TextChannel;

export class InitMap extends _.CustomType {}
export function ChannelInit$InitMap(): ChannelInit$;
export function ChannelInit$isInitMap(value: any): value is ChannelInit$;

export class InitCounter extends _.CustomType {}
export function ChannelInit$InitCounter(): ChannelInit$;
export function ChannelInit$isInitCounter(value: any): value is ChannelInit$;

export class InitPnCounter extends _.CustomType {}
export function ChannelInit$InitPnCounter(): ChannelInit$;
export function ChannelInit$isInitPnCounter(value: any): value is ChannelInit$;

export class InitGCounter extends _.CustomType {}
export function ChannelInit$InitGCounter(): ChannelInit$;
export function ChannelInit$isInitGCounter(value: any): value is ChannelInit$;

export class InitLwwRegister extends _.CustomType {}
export function ChannelInit$InitLwwRegister(): ChannelInit$;
export function ChannelInit$isInitLwwRegister(
  value: any,
): value is ChannelInit$;

export class InitLwwMap extends _.CustomType {}
export function ChannelInit$InitLwwMap(): ChannelInit$;
export function ChannelInit$isInitLwwMap(value: any): value is ChannelInit$;

export class InitMvRegister extends _.CustomType {}
export function ChannelInit$InitMvRegister(): ChannelInit$;
export function ChannelInit$isInitMvRegister(value: any): value is ChannelInit$;

export class InitOrMap extends _.CustomType {
  /** @deprecated */
  constructor(mode: $or_map_kernel.OrMapMode$);
  /** @deprecated */
  mode: $or_map_kernel.OrMapMode$;
}
export function ChannelInit$InitOrMap(
  mode: $or_map_kernel.OrMapMode$,
): ChannelInit$;
export function ChannelInit$isInitOrMap(value: any): value is ChannelInit$;
export function ChannelInit$InitOrMap$0(value: ChannelInit$): $or_map_kernel.OrMapMode$;
export function ChannelInit$InitOrMap$mode(
  value: ChannelInit$,
): $or_map_kernel.OrMapMode$;

export class InitOrSet extends _.CustomType {}
export function ChannelInit$InitOrSet(): ChannelInit$;
export function ChannelInit$isInitOrSet(value: any): value is ChannelInit$;

export class InitGSet extends _.CustomType {}
export function ChannelInit$InitGSet(): ChannelInit$;
export function ChannelInit$isInitGSet(value: any): value is ChannelInit$;

export class InitTwoPSet extends _.CustomType {}
export function ChannelInit$InitTwoPSet(): ChannelInit$;
export function ChannelInit$isInitTwoPSet(value: any): value is ChannelInit$;

export class InitRegisterCollection extends _.CustomType {}
export function ChannelInit$InitRegisterCollection(): ChannelInit$;
export function ChannelInit$isInitRegisterCollection(
  value: any,
): value is ChannelInit$;

export class InitClaims extends _.CustomType {}
export function ChannelInit$InitClaims(): ChannelInit$;
export function ChannelInit$isInitClaims(value: any): value is ChannelInit$;

export class InitTaskManager extends _.CustomType {}
export function ChannelInit$InitTaskManager(): ChannelInit$;
export function ChannelInit$isInitTaskManager(
  value: any,
): value is ChannelInit$;

export class InitPactMap extends _.CustomType {}
export function ChannelInit$InitPactMap(): ChannelInit$;
export function ChannelInit$isInitPactMap(value: any): value is ChannelInit$;

export class InitJsonOt extends _.CustomType {}
export function ChannelInit$InitJsonOt(): ChannelInit$;
export function ChannelInit$isInitJsonOt(value: any): value is ChannelInit$;

export class InitDirectory extends _.CustomType {}
export function ChannelInit$InitDirectory(): ChannelInit$;
export function ChannelInit$isInitDirectory(value: any): value is ChannelInit$;

export class InitOrderedCollection extends _.CustomType {}
export function ChannelInit$InitOrderedCollection(): ChannelInit$;
export function ChannelInit$isInitOrderedCollection(
  value: any,
): value is ChannelInit$;

export class InitSequence extends _.CustomType {}
export function ChannelInit$InitSequence(): ChannelInit$;
export function ChannelInit$isInitSequence(value: any): value is ChannelInit$;

export class InitRichText extends _.CustomType {}
export function ChannelInit$InitRichText(): ChannelInit$;
export function ChannelInit$isInitRichText(value: any): value is ChannelInit$;

export class InitText extends _.CustomType {}
export function ChannelInit$InitText(): ChannelInit$;
export function ChannelInit$isInitText(value: any): value is ChannelInit$;

export type ChannelInit$ = InitMap | InitCounter | InitPnCounter | InitGCounter | InitLwwRegister | InitLwwMap | InitMvRegister | InitOrMap | InitOrSet | InitGSet | InitTwoPSet | InitRegisterCollection | InitClaims | InitTaskManager | InitPactMap | InitJsonOt | InitDirectory | InitOrderedCollection | InitSequence | InitRichText | InitText;

export class MapState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $map_kernel.MapState$);
  /** @deprecated */
  0: $map_kernel.MapState$;
}
export function ChannelState$MapState($0: $map_kernel.MapState$): ChannelState$;
export function ChannelState$isMapState(value: any): value is ChannelState$;
export function ChannelState$MapState$0(value: ChannelState$): $map_kernel.MapState$;

export class CounterState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $counter_kernel.CounterState$);
  /** @deprecated */
  0: $counter_kernel.CounterState$;
}
export function ChannelState$CounterState(
  $0: $counter_kernel.CounterState$,
): ChannelState$;
export function ChannelState$isCounterState(value: any): value is ChannelState$;
export function ChannelState$CounterState$0(value: ChannelState$): $counter_kernel.CounterState$;

export class PnCounterState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $pn_counter_kernel.PnCounterState$);
  /** @deprecated */
  0: $pn_counter_kernel.PnCounterState$;
}
export function ChannelState$PnCounterState(
  $0: $pn_counter_kernel.PnCounterState$,
): ChannelState$;
export function ChannelState$isPnCounterState(
  value: any,
): value is ChannelState$;
export function ChannelState$PnCounterState$0(value: ChannelState$): $pn_counter_kernel.PnCounterState$;

export class GCounterState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $g_counter_kernel.GCounterState$);
  /** @deprecated */
  0: $g_counter_kernel.GCounterState$;
}
export function ChannelState$GCounterState(
  $0: $g_counter_kernel.GCounterState$,
): ChannelState$;
export function ChannelState$isGCounterState(
  value: any,
): value is ChannelState$;
export function ChannelState$GCounterState$0(value: ChannelState$): $g_counter_kernel.GCounterState$;

export class LwwRegisterState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $lww_register_kernel.LwwRegisterState$);
  /** @deprecated */
  0: $lww_register_kernel.LwwRegisterState$;
}
export function ChannelState$LwwRegisterState(
  $0: $lww_register_kernel.LwwRegisterState$,
): ChannelState$;
export function ChannelState$isLwwRegisterState(
  value: any,
): value is ChannelState$;
export function ChannelState$LwwRegisterState$0(value: ChannelState$): $lww_register_kernel.LwwRegisterState$;

export class LwwMapState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $lww_map_kernel.LwwMapState$);
  /** @deprecated */
  0: $lww_map_kernel.LwwMapState$;
}
export function ChannelState$LwwMapState(
  $0: $lww_map_kernel.LwwMapState$,
): ChannelState$;
export function ChannelState$isLwwMapState(value: any): value is ChannelState$;
export function ChannelState$LwwMapState$0(value: ChannelState$): $lww_map_kernel.LwwMapState$;

export class MvRegisterState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $mv_register_kernel.MvRegisterState$);
  /** @deprecated */
  0: $mv_register_kernel.MvRegisterState$;
}
export function ChannelState$MvRegisterState(
  $0: $mv_register_kernel.MvRegisterState$,
): ChannelState$;
export function ChannelState$isMvRegisterState(
  value: any,
): value is ChannelState$;
export function ChannelState$MvRegisterState$0(value: ChannelState$): $mv_register_kernel.MvRegisterState$;

export class OrMapState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $or_map_kernel.OrMapState$);
  /** @deprecated */
  0: $or_map_kernel.OrMapState$;
}
export function ChannelState$OrMapState(
  $0: $or_map_kernel.OrMapState$,
): ChannelState$;
export function ChannelState$isOrMapState(value: any): value is ChannelState$;
export function ChannelState$OrMapState$0(value: ChannelState$): $or_map_kernel.OrMapState$;

export class OrSetState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $or_set_kernel.OrSetState$);
  /** @deprecated */
  0: $or_set_kernel.OrSetState$;
}
export function ChannelState$OrSetState(
  $0: $or_set_kernel.OrSetState$,
): ChannelState$;
export function ChannelState$isOrSetState(value: any): value is ChannelState$;
export function ChannelState$OrSetState$0(value: ChannelState$): $or_set_kernel.OrSetState$;

export class GSetState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $g_set_kernel.GSetState$);
  /** @deprecated */
  0: $g_set_kernel.GSetState$;
}
export function ChannelState$GSetState(
  $0: $g_set_kernel.GSetState$,
): ChannelState$;
export function ChannelState$isGSetState(value: any): value is ChannelState$;
export function ChannelState$GSetState$0(value: ChannelState$): $g_set_kernel.GSetState$;

export class TwoPSetState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $two_p_set_kernel.TwoPSetState$);
  /** @deprecated */
  0: $two_p_set_kernel.TwoPSetState$;
}
export function ChannelState$TwoPSetState(
  $0: $two_p_set_kernel.TwoPSetState$,
): ChannelState$;
export function ChannelState$isTwoPSetState(value: any): value is ChannelState$;
export function ChannelState$TwoPSetState$0(value: ChannelState$): $two_p_set_kernel.TwoPSetState$;

export class RegisterCollectionState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $register_collection_kernel.RegisterState$);
  /** @deprecated */
  0: $register_collection_kernel.RegisterState$;
}
export function ChannelState$RegisterCollectionState(
  $0: $register_collection_kernel.RegisterState$,
): ChannelState$;
export function ChannelState$isRegisterCollectionState(
  value: any,
): value is ChannelState$;
export function ChannelState$RegisterCollectionState$0(value: ChannelState$): $register_collection_kernel.RegisterState$;

export class ClaimsState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $claims_kernel.ClaimsState$);
  /** @deprecated */
  0: $claims_kernel.ClaimsState$;
}
export function ChannelState$ClaimsState(
  $0: $claims_kernel.ClaimsState$,
): ChannelState$;
export function ChannelState$isClaimsState(value: any): value is ChannelState$;
export function ChannelState$ClaimsState$0(value: ChannelState$): $claims_kernel.ClaimsState$;

export class TaskManagerState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $task_manager_kernel.TaskManagerState$);
  /** @deprecated */
  0: $task_manager_kernel.TaskManagerState$;
}
export function ChannelState$TaskManagerState(
  $0: $task_manager_kernel.TaskManagerState$,
): ChannelState$;
export function ChannelState$isTaskManagerState(
  value: any,
): value is ChannelState$;
export function ChannelState$TaskManagerState$0(value: ChannelState$): $task_manager_kernel.TaskManagerState$;

export class PactMapState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $pact_map_kernel.PactMapState$);
  /** @deprecated */
  0: $pact_map_kernel.PactMapState$;
}
export function ChannelState$PactMapState(
  $0: $pact_map_kernel.PactMapState$,
): ChannelState$;
export function ChannelState$isPactMapState(value: any): value is ChannelState$;
export function ChannelState$PactMapState$0(value: ChannelState$): $pact_map_kernel.PactMapState$;

export class JsonOtState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $json_ot_kernel.JsonOtState$);
  /** @deprecated */
  0: $json_ot_kernel.JsonOtState$;
}
export function ChannelState$JsonOtState(
  $0: $json_ot_kernel.JsonOtState$,
): ChannelState$;
export function ChannelState$isJsonOtState(value: any): value is ChannelState$;
export function ChannelState$JsonOtState$0(value: ChannelState$): $json_ot_kernel.JsonOtState$;

export class DirectoryState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $directory_kernel.DirectoryState$);
  /** @deprecated */
  0: $directory_kernel.DirectoryState$;
}
export function ChannelState$DirectoryState(
  $0: $directory_kernel.DirectoryState$,
): ChannelState$;
export function ChannelState$isDirectoryState(
  value: any,
): value is ChannelState$;
export function ChannelState$DirectoryState$0(value: ChannelState$): $directory_kernel.DirectoryState$;

export class OrderedCollectionState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $ordered_collection_kernel.OrderedState$);
  /** @deprecated */
  0: $ordered_collection_kernel.OrderedState$;
}
export function ChannelState$OrderedCollectionState(
  $0: $ordered_collection_kernel.OrderedState$,
): ChannelState$;
export function ChannelState$isOrderedCollectionState(
  value: any,
): value is ChannelState$;
export function ChannelState$OrderedCollectionState$0(value: ChannelState$): $ordered_collection_kernel.OrderedState$;

export class SequenceState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $sequence_kernel.SequenceState$);
  /** @deprecated */
  0: $sequence_kernel.SequenceState$;
}
export function ChannelState$SequenceState(
  $0: $sequence_kernel.SequenceState$,
): ChannelState$;
export function ChannelState$isSequenceState(
  value: any,
): value is ChannelState$;
export function ChannelState$SequenceState$0(value: ChannelState$): $sequence_kernel.SequenceState$;

export class RichTextState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $rich_text_kernel.RichTextState$);
  /** @deprecated */
  0: $rich_text_kernel.RichTextState$;
}
export function ChannelState$RichTextState(
  $0: $rich_text_kernel.RichTextState$,
): ChannelState$;
export function ChannelState$isRichTextState(
  value: any,
): value is ChannelState$;
export function ChannelState$RichTextState$0(value: ChannelState$): $rich_text_kernel.RichTextState$;

export class TextState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $text_kernel.TextState$);
  /** @deprecated */
  0: $text_kernel.TextState$;
}
export function ChannelState$TextState(
  $0: $text_kernel.TextState$,
): ChannelState$;
export function ChannelState$isTextState(value: any): value is ChannelState$;
export function ChannelState$TextState$0(value: ChannelState$): $text_kernel.TextState$;

export type ChannelState$ = MapState | CounterState | PnCounterState | GCounterState | LwwRegisterState | LwwMapState | MvRegisterState | OrMapState | OrSetState | GSetState | TwoPSetState | RegisterCollectionState | ClaimsState | TaskManagerState | PactMapState | JsonOtState | DirectoryState | OrderedCollectionState | SequenceState | RichTextState | TextState;

export class MapOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $map_kernel.MapOperation$);
  /** @deprecated */
  0: $map_kernel.MapOperation$;
}
export function ChannelOperation$MapOperation(
  $0: $map_kernel.MapOperation$,
): ChannelOperation$;
export function ChannelOperation$isMapOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$MapOperation$0(value: ChannelOperation$): $map_kernel.MapOperation$;

export class CounterOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $counter_kernel.CounterOperation$);
  /** @deprecated */
  0: $counter_kernel.CounterOperation$;
}
export function ChannelOperation$CounterOperation(
  $0: $counter_kernel.CounterOperation$,
): ChannelOperation$;
export function ChannelOperation$isCounterOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$CounterOperation$0(value: ChannelOperation$): $counter_kernel.CounterOperation$;

export class PnCounterOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $pn_counter_kernel.PnCounterOperation$);
  /** @deprecated */
  0: $pn_counter_kernel.PnCounterOperation$;
}
export function ChannelOperation$PnCounterOperation(
  $0: $pn_counter_kernel.PnCounterOperation$,
): ChannelOperation$;
export function ChannelOperation$isPnCounterOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$PnCounterOperation$0(value: ChannelOperation$): $pn_counter_kernel.PnCounterOperation$;

export class GCounterOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $g_counter_kernel.GCounterOperation$);
  /** @deprecated */
  0: $g_counter_kernel.GCounterOperation$;
}
export function ChannelOperation$GCounterOperation(
  $0: $g_counter_kernel.GCounterOperation$,
): ChannelOperation$;
export function ChannelOperation$isGCounterOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$GCounterOperation$0(value: ChannelOperation$): $g_counter_kernel.GCounterOperation$;

export class LwwRegisterOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $lww_register_kernel.LwwRegisterOperation$);
  /** @deprecated */
  0: $lww_register_kernel.LwwRegisterOperation$;
}
export function ChannelOperation$LwwRegisterOperation(
  $0: $lww_register_kernel.LwwRegisterOperation$,
): ChannelOperation$;
export function ChannelOperation$isLwwRegisterOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$LwwRegisterOperation$0(value: ChannelOperation$): $lww_register_kernel.LwwRegisterOperation$;

export class LwwMapOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $lww_map_kernel.LwwMapOperation$);
  /** @deprecated */
  0: $lww_map_kernel.LwwMapOperation$;
}
export function ChannelOperation$LwwMapOperation(
  $0: $lww_map_kernel.LwwMapOperation$,
): ChannelOperation$;
export function ChannelOperation$isLwwMapOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$LwwMapOperation$0(value: ChannelOperation$): $lww_map_kernel.LwwMapOperation$;

export class MvRegisterOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $mv_register_kernel.MvRegisterOperation$);
  /** @deprecated */
  0: $mv_register_kernel.MvRegisterOperation$;
}
export function ChannelOperation$MvRegisterOperation(
  $0: $mv_register_kernel.MvRegisterOperation$,
): ChannelOperation$;
export function ChannelOperation$isMvRegisterOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$MvRegisterOperation$0(value: ChannelOperation$): $mv_register_kernel.MvRegisterOperation$;

export class OrMapOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $or_map_kernel.OrMapOperation$);
  /** @deprecated */
  0: $or_map_kernel.OrMapOperation$;
}
export function ChannelOperation$OrMapOperation(
  $0: $or_map_kernel.OrMapOperation$,
): ChannelOperation$;
export function ChannelOperation$isOrMapOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$OrMapOperation$0(value: ChannelOperation$): $or_map_kernel.OrMapOperation$;

export class OrSetOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $or_set_kernel.OrSetOperation$);
  /** @deprecated */
  0: $or_set_kernel.OrSetOperation$;
}
export function ChannelOperation$OrSetOperation(
  $0: $or_set_kernel.OrSetOperation$,
): ChannelOperation$;
export function ChannelOperation$isOrSetOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$OrSetOperation$0(value: ChannelOperation$): $or_set_kernel.OrSetOperation$;

export class GSetOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $g_set_kernel.GSetOperation$);
  /** @deprecated */
  0: $g_set_kernel.GSetOperation$;
}
export function ChannelOperation$GSetOperation(
  $0: $g_set_kernel.GSetOperation$,
): ChannelOperation$;
export function ChannelOperation$isGSetOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$GSetOperation$0(value: ChannelOperation$): $g_set_kernel.GSetOperation$;

export class TwoPSetOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $two_p_set_kernel.TwoPSetOperation$);
  /** @deprecated */
  0: $two_p_set_kernel.TwoPSetOperation$;
}
export function ChannelOperation$TwoPSetOperation(
  $0: $two_p_set_kernel.TwoPSetOperation$,
): ChannelOperation$;
export function ChannelOperation$isTwoPSetOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$TwoPSetOperation$0(value: ChannelOperation$): $two_p_set_kernel.TwoPSetOperation$;

export class RegisterCollectionOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $register_collection_kernel.WriteOperation$);
  /** @deprecated */
  0: $register_collection_kernel.WriteOperation$;
}
export function ChannelOperation$RegisterCollectionOperation(
  $0: $register_collection_kernel.WriteOperation$,
): ChannelOperation$;
export function ChannelOperation$isRegisterCollectionOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$RegisterCollectionOperation$0(value: ChannelOperation$): $register_collection_kernel.WriteOperation$;

export class ClaimsOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $claims_kernel.ClaimOperation$);
  /** @deprecated */
  0: $claims_kernel.ClaimOperation$;
}
export function ChannelOperation$ClaimsOperation(
  $0: $claims_kernel.ClaimOperation$,
): ChannelOperation$;
export function ChannelOperation$isClaimsOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$ClaimsOperation$0(value: ChannelOperation$): $claims_kernel.ClaimOperation$;

export class TaskManagerOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $task_manager_kernel.TaskManagerOperation$);
  /** @deprecated */
  0: $task_manager_kernel.TaskManagerOperation$;
}
export function ChannelOperation$TaskManagerOperation(
  $0: $task_manager_kernel.TaskManagerOperation$,
): ChannelOperation$;
export function ChannelOperation$isTaskManagerOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$TaskManagerOperation$0(value: ChannelOperation$): $task_manager_kernel.TaskManagerOperation$;

export class PactMapOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $pact_map_kernel.PactMapOperation$);
  /** @deprecated */
  0: $pact_map_kernel.PactMapOperation$;
}
export function ChannelOperation$PactMapOperation(
  $0: $pact_map_kernel.PactMapOperation$,
): ChannelOperation$;
export function ChannelOperation$isPactMapOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$PactMapOperation$0(value: ChannelOperation$): $pact_map_kernel.PactMapOperation$;

export class JsonOtOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $json_ot_kernel.JsonOtWireOperation$);
  /** @deprecated */
  0: $json_ot_kernel.JsonOtWireOperation$;
}
export function ChannelOperation$JsonOtOperation(
  $0: $json_ot_kernel.JsonOtWireOperation$,
): ChannelOperation$;
export function ChannelOperation$isJsonOtOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$JsonOtOperation$0(value: ChannelOperation$): $json_ot_kernel.JsonOtWireOperation$;

export class DirectoryOperation extends _.CustomType {
  /** @deprecated */
  constructor(
    operation: $directory_kernel.DirectoryOperation$,
    message_id: number
  );
  /** @deprecated */
  operation: $directory_kernel.DirectoryOperation$;
  /** @deprecated */
  message_id: number;
}
export function ChannelOperation$DirectoryOperation(
  operation: $directory_kernel.DirectoryOperation$,
  message_id: number,
): ChannelOperation$;
export function ChannelOperation$isDirectoryOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$DirectoryOperation$0(value: ChannelOperation$): $directory_kernel.DirectoryOperation$;
export function ChannelOperation$DirectoryOperation$operation(
  value: ChannelOperation$,
): $directory_kernel.DirectoryOperation$;
export function ChannelOperation$DirectoryOperation$1(value: ChannelOperation$): number;
export function ChannelOperation$DirectoryOperation$message_id(
  value: ChannelOperation$,
): number;

export class OrderedCollectionOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $ordered_collection_kernel.OrderedOperation$);
  /** @deprecated */
  0: $ordered_collection_kernel.OrderedOperation$;
}
export function ChannelOperation$OrderedCollectionOperation(
  $0: $ordered_collection_kernel.OrderedOperation$,
): ChannelOperation$;
export function ChannelOperation$isOrderedCollectionOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$OrderedCollectionOperation$0(value: ChannelOperation$): $ordered_collection_kernel.OrderedOperation$;

export class SequenceOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $sequence_kernel.SequenceOperation$);
  /** @deprecated */
  0: $sequence_kernel.SequenceOperation$;
}
export function ChannelOperation$SequenceOperation(
  $0: $sequence_kernel.SequenceOperation$,
): ChannelOperation$;
export function ChannelOperation$isSequenceOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$SequenceOperation$0(value: ChannelOperation$): $sequence_kernel.SequenceOperation$;

export class RichTextOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $rich_text_kernel.RichTextWireOperation$);
  /** @deprecated */
  0: $rich_text_kernel.RichTextWireOperation$;
}
export function ChannelOperation$RichTextOperation(
  $0: $rich_text_kernel.RichTextWireOperation$,
): ChannelOperation$;
export function ChannelOperation$isRichTextOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$RichTextOperation$0(value: ChannelOperation$): $rich_text_kernel.RichTextWireOperation$;

export class TextOperation extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $text_kernel.TextOperation$);
  /** @deprecated */
  0: $text_kernel.TextOperation$;
}
export function ChannelOperation$TextOperation(
  $0: $text_kernel.TextOperation$,
): ChannelOperation$;
export function ChannelOperation$isTextOperation(
  value: any,
): value is ChannelOperation$;
export function ChannelOperation$TextOperation$0(value: ChannelOperation$): $text_kernel.TextOperation$;

export type ChannelOperation$ = MapOperation | CounterOperation | PnCounterOperation | GCounterOperation | LwwRegisterOperation | LwwMapOperation | MvRegisterOperation | OrMapOperation | OrSetOperation | GSetOperation | TwoPSetOperation | RegisterCollectionOperation | ClaimsOperation | TaskManagerOperation | PactMapOperation | JsonOtOperation | DirectoryOperation | OrderedCollectionOperation | SequenceOperation | RichTextOperation | TextOperation;

export class PnCounterEdit extends _.CustomType {
  /** @deprecated */
  constructor(amount: number);
  /** @deprecated */
  amount: number;
}
export function P2pEdit$PnCounterEdit(amount: number): P2pEdit$;
export function P2pEdit$isPnCounterEdit(value: any): value is P2pEdit$;
export function P2pEdit$PnCounterEdit$0(value: P2pEdit$): number;
export function P2pEdit$PnCounterEdit$amount(value: P2pEdit$): number;

export class GCounterIncrementEdit extends _.CustomType {
  /** @deprecated */
  constructor(amount: number);
  /** @deprecated */
  amount: number;
}
export function P2pEdit$GCounterIncrementEdit(amount: number): P2pEdit$;
export function P2pEdit$isGCounterIncrementEdit(value: any): value is P2pEdit$;
export function P2pEdit$GCounterIncrementEdit$0(value: P2pEdit$): number;
export function P2pEdit$GCounterIncrementEdit$amount(value: P2pEdit$): number;

export class LwwRegisterSetEdit extends _.CustomType {
  /** @deprecated */
  constructor(value: string, timestamp: number);
  /** @deprecated */
  value: string;
  /** @deprecated */
  timestamp: number;
}
export function P2pEdit$LwwRegisterSetEdit(
  value: string,
  timestamp: number,
): P2pEdit$;
export function P2pEdit$isLwwRegisterSetEdit(value: any): value is P2pEdit$;
export function P2pEdit$LwwRegisterSetEdit$0(value: P2pEdit$): string;
export function P2pEdit$LwwRegisterSetEdit$value(value: P2pEdit$): string;
export function P2pEdit$LwwRegisterSetEdit$1(value: P2pEdit$): number;
export function P2pEdit$LwwRegisterSetEdit$timestamp(value: P2pEdit$): number;

export class LwwMapSetEdit extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: string, timestamp: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: string;
  /** @deprecated */
  timestamp: number;
}
export function P2pEdit$LwwMapSetEdit(
  key: string,
  value: string,
  timestamp: number,
): P2pEdit$;
export function P2pEdit$isLwwMapSetEdit(value: any): value is P2pEdit$;
export function P2pEdit$LwwMapSetEdit$0(value: P2pEdit$): string;
export function P2pEdit$LwwMapSetEdit$key(value: P2pEdit$): string;
export function P2pEdit$LwwMapSetEdit$1(value: P2pEdit$): string;
export function P2pEdit$LwwMapSetEdit$value(value: P2pEdit$): string;
export function P2pEdit$LwwMapSetEdit$2(value: P2pEdit$): number;
export function P2pEdit$LwwMapSetEdit$timestamp(value: P2pEdit$): number;

export class LwwMapRemoveEdit extends _.CustomType {
  /** @deprecated */
  constructor(key: string, timestamp: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  timestamp: number;
}
export function P2pEdit$LwwMapRemoveEdit(
  key: string,
  timestamp: number,
): P2pEdit$;
export function P2pEdit$isLwwMapRemoveEdit(value: any): value is P2pEdit$;
export function P2pEdit$LwwMapRemoveEdit$0(value: P2pEdit$): string;
export function P2pEdit$LwwMapRemoveEdit$key(value: P2pEdit$): string;
export function P2pEdit$LwwMapRemoveEdit$1(value: P2pEdit$): number;
export function P2pEdit$LwwMapRemoveEdit$timestamp(value: P2pEdit$): number;

export class MvRegisterEdit extends _.CustomType {
  /** @deprecated */
  constructor(value: string);
  /** @deprecated */
  value: string;
}
export function P2pEdit$MvRegisterEdit(value: string): P2pEdit$;
export function P2pEdit$isMvRegisterEdit(value: any): value is P2pEdit$;
export function P2pEdit$MvRegisterEdit$0(value: P2pEdit$): string;
export function P2pEdit$MvRegisterEdit$value(value: P2pEdit$): string;

export class OrMapIncrementEdit extends _.CustomType {
  /** @deprecated */
  constructor(key: string, amount: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  amount: number;
}
export function P2pEdit$OrMapIncrementEdit(
  key: string,
  amount: number,
): P2pEdit$;
export function P2pEdit$isOrMapIncrementEdit(value: any): value is P2pEdit$;
export function P2pEdit$OrMapIncrementEdit$0(value: P2pEdit$): string;
export function P2pEdit$OrMapIncrementEdit$key(value: P2pEdit$): string;
export function P2pEdit$OrMapIncrementEdit$1(value: P2pEdit$): number;
export function P2pEdit$OrMapIncrementEdit$amount(value: P2pEdit$): number;

export class OrMapSetRegisterEdit extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: string, timestamp: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: string;
  /** @deprecated */
  timestamp: number;
}
export function P2pEdit$OrMapSetRegisterEdit(
  key: string,
  value: string,
  timestamp: number,
): P2pEdit$;
export function P2pEdit$isOrMapSetRegisterEdit(value: any): value is P2pEdit$;
export function P2pEdit$OrMapSetRegisterEdit$0(value: P2pEdit$): string;
export function P2pEdit$OrMapSetRegisterEdit$key(value: P2pEdit$): string;
export function P2pEdit$OrMapSetRegisterEdit$1(value: P2pEdit$): string;
export function P2pEdit$OrMapSetRegisterEdit$value(value: P2pEdit$): string;
export function P2pEdit$OrMapSetRegisterEdit$2(value: P2pEdit$): number;
export function P2pEdit$OrMapSetRegisterEdit$timestamp(value: P2pEdit$): number;

export class OrMapSetMvRegisterEdit extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: string);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: string;
}
export function P2pEdit$OrMapSetMvRegisterEdit(
  key: string,
  value: string,
): P2pEdit$;
export function P2pEdit$isOrMapSetMvRegisterEdit(value: any): value is P2pEdit$;
export function P2pEdit$OrMapSetMvRegisterEdit$0(value: P2pEdit$): string;
export function P2pEdit$OrMapSetMvRegisterEdit$key(value: P2pEdit$): string;
export function P2pEdit$OrMapSetMvRegisterEdit$1(value: P2pEdit$): string;
export function P2pEdit$OrMapSetMvRegisterEdit$value(value: P2pEdit$): string;

export class OrMapRemoveEdit extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function P2pEdit$OrMapRemoveEdit(key: string): P2pEdit$;
export function P2pEdit$isOrMapRemoveEdit(value: any): value is P2pEdit$;
export function P2pEdit$OrMapRemoveEdit$0(value: P2pEdit$): string;
export function P2pEdit$OrMapRemoveEdit$key(value: P2pEdit$): string;

export class OrMapAddMemberEdit extends _.CustomType {
  /** @deprecated */
  constructor(key: string, member: string);
  /** @deprecated */
  key: string;
  /** @deprecated */
  member: string;
}
export function P2pEdit$OrMapAddMemberEdit(
  key: string,
  member: string,
): P2pEdit$;
export function P2pEdit$isOrMapAddMemberEdit(value: any): value is P2pEdit$;
export function P2pEdit$OrMapAddMemberEdit$0(value: P2pEdit$): string;
export function P2pEdit$OrMapAddMemberEdit$key(value: P2pEdit$): string;
export function P2pEdit$OrMapAddMemberEdit$1(value: P2pEdit$): string;
export function P2pEdit$OrMapAddMemberEdit$member(value: P2pEdit$): string;

export class OrMapRemoveMemberEdit extends _.CustomType {
  /** @deprecated */
  constructor(key: string, member: string);
  /** @deprecated */
  key: string;
  /** @deprecated */
  member: string;
}
export function P2pEdit$OrMapRemoveMemberEdit(
  key: string,
  member: string,
): P2pEdit$;
export function P2pEdit$isOrMapRemoveMemberEdit(value: any): value is P2pEdit$;
export function P2pEdit$OrMapRemoveMemberEdit$0(value: P2pEdit$): string;
export function P2pEdit$OrMapRemoveMemberEdit$key(value: P2pEdit$): string;
export function P2pEdit$OrMapRemoveMemberEdit$1(value: P2pEdit$): string;
export function P2pEdit$OrMapRemoveMemberEdit$member(value: P2pEdit$): string;

export class OrSetAddEdit extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function P2pEdit$OrSetAddEdit(element: string): P2pEdit$;
export function P2pEdit$isOrSetAddEdit(value: any): value is P2pEdit$;
export function P2pEdit$OrSetAddEdit$0(value: P2pEdit$): string;
export function P2pEdit$OrSetAddEdit$element(value: P2pEdit$): string;

export class OrSetRemoveEdit extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function P2pEdit$OrSetRemoveEdit(element: string): P2pEdit$;
export function P2pEdit$isOrSetRemoveEdit(value: any): value is P2pEdit$;
export function P2pEdit$OrSetRemoveEdit$0(value: P2pEdit$): string;
export function P2pEdit$OrSetRemoveEdit$element(value: P2pEdit$): string;

export class GSetAddEdit extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function P2pEdit$GSetAddEdit(element: string): P2pEdit$;
export function P2pEdit$isGSetAddEdit(value: any): value is P2pEdit$;
export function P2pEdit$GSetAddEdit$0(value: P2pEdit$): string;
export function P2pEdit$GSetAddEdit$element(value: P2pEdit$): string;

export class TwoPSetAddEdit extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function P2pEdit$TwoPSetAddEdit(element: string): P2pEdit$;
export function P2pEdit$isTwoPSetAddEdit(value: any): value is P2pEdit$;
export function P2pEdit$TwoPSetAddEdit$0(value: P2pEdit$): string;
export function P2pEdit$TwoPSetAddEdit$element(value: P2pEdit$): string;

export class TwoPSetRemoveEdit extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function P2pEdit$TwoPSetRemoveEdit(element: string): P2pEdit$;
export function P2pEdit$isTwoPSetRemoveEdit(value: any): value is P2pEdit$;
export function P2pEdit$TwoPSetRemoveEdit$0(value: P2pEdit$): string;
export function P2pEdit$TwoPSetRemoveEdit$element(value: P2pEdit$): string;

export class SequenceInsertEdit extends _.CustomType {
  /** @deprecated */
  constructor(index: number, value: $json.Json$);
  /** @deprecated */
  index: number;
  /** @deprecated */
  value: $json.Json$;
}
export function P2pEdit$SequenceInsertEdit(
  index: number,
  value: $json.Json$,
): P2pEdit$;
export function P2pEdit$isSequenceInsertEdit(value: any): value is P2pEdit$;
export function P2pEdit$SequenceInsertEdit$0(value: P2pEdit$): number;
export function P2pEdit$SequenceInsertEdit$index(value: P2pEdit$): number;
export function P2pEdit$SequenceInsertEdit$1(value: P2pEdit$): $json.Json$;
export function P2pEdit$SequenceInsertEdit$value(value: P2pEdit$): $json.Json$;

export class SequenceDeleteEdit extends _.CustomType {
  /** @deprecated */
  constructor(index: number);
  /** @deprecated */
  index: number;
}
export function P2pEdit$SequenceDeleteEdit(index: number): P2pEdit$;
export function P2pEdit$isSequenceDeleteEdit(value: any): value is P2pEdit$;
export function P2pEdit$SequenceDeleteEdit$0(value: P2pEdit$): number;
export function P2pEdit$SequenceDeleteEdit$index(value: P2pEdit$): number;

export class SequenceMoveEdit extends _.CustomType {
  /** @deprecated */
  constructor(from_index: number, to_index: number);
  /** @deprecated */
  from_index: number;
  /** @deprecated */
  to_index: number;
}
export function P2pEdit$SequenceMoveEdit(
  from_index: number,
  to_index: number,
): P2pEdit$;
export function P2pEdit$isSequenceMoveEdit(value: any): value is P2pEdit$;
export function P2pEdit$SequenceMoveEdit$0(value: P2pEdit$): number;
export function P2pEdit$SequenceMoveEdit$from_index(value: P2pEdit$): number;
export function P2pEdit$SequenceMoveEdit$1(value: P2pEdit$): number;
export function P2pEdit$SequenceMoveEdit$to_index(value: P2pEdit$): number;

export class SequenceReplaceEdit extends _.CustomType {
  /** @deprecated */
  constructor(index: number, value: $json.Json$);
  /** @deprecated */
  index: number;
  /** @deprecated */
  value: $json.Json$;
}
export function P2pEdit$SequenceReplaceEdit(
  index: number,
  value: $json.Json$,
): P2pEdit$;
export function P2pEdit$isSequenceReplaceEdit(value: any): value is P2pEdit$;
export function P2pEdit$SequenceReplaceEdit$0(value: P2pEdit$): number;
export function P2pEdit$SequenceReplaceEdit$index(value: P2pEdit$): number;
export function P2pEdit$SequenceReplaceEdit$1(value: P2pEdit$): $json.Json$;
export function P2pEdit$SequenceReplaceEdit$value(value: P2pEdit$): $json.Json$;

export class TextInsertEdit extends _.CustomType {
  /** @deprecated */
  constructor(index: number, value: string);
  /** @deprecated */
  index: number;
  /** @deprecated */
  value: string;
}
export function P2pEdit$TextInsertEdit(index: number, value: string): P2pEdit$;
export function P2pEdit$isTextInsertEdit(value: any): value is P2pEdit$;
export function P2pEdit$TextInsertEdit$0(value: P2pEdit$): number;
export function P2pEdit$TextInsertEdit$index(value: P2pEdit$): number;
export function P2pEdit$TextInsertEdit$1(value: P2pEdit$): string;
export function P2pEdit$TextInsertEdit$value(value: P2pEdit$): string;

export class TextDeleteRangeEdit extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
}
export function P2pEdit$TextDeleteRangeEdit(
  start: number,
  end: number,
): P2pEdit$;
export function P2pEdit$isTextDeleteRangeEdit(value: any): value is P2pEdit$;
export function P2pEdit$TextDeleteRangeEdit$0(value: P2pEdit$): number;
export function P2pEdit$TextDeleteRangeEdit$start(value: P2pEdit$): number;
export function P2pEdit$TextDeleteRangeEdit$1(value: P2pEdit$): number;
export function P2pEdit$TextDeleteRangeEdit$end(value: P2pEdit$): number;

export class TextReplaceRangeEdit extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, value: string);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  value: string;
}
export function P2pEdit$TextReplaceRangeEdit(
  start: number,
  end: number,
  value: string,
): P2pEdit$;
export function P2pEdit$isTextReplaceRangeEdit(value: any): value is P2pEdit$;
export function P2pEdit$TextReplaceRangeEdit$0(value: P2pEdit$): number;
export function P2pEdit$TextReplaceRangeEdit$start(value: P2pEdit$): number;
export function P2pEdit$TextReplaceRangeEdit$1(value: P2pEdit$): number;
export function P2pEdit$TextReplaceRangeEdit$end(value: P2pEdit$): number;
export function P2pEdit$TextReplaceRangeEdit$2(value: P2pEdit$): string;
export function P2pEdit$TextReplaceRangeEdit$value(value: P2pEdit$): string;

export class TextAppendEdit extends _.CustomType {
  /** @deprecated */
  constructor(value: string);
  /** @deprecated */
  value: string;
}
export function P2pEdit$TextAppendEdit(value: string): P2pEdit$;
export function P2pEdit$isTextAppendEdit(value: any): value is P2pEdit$;
export function P2pEdit$TextAppendEdit$0(value: P2pEdit$): string;
export function P2pEdit$TextAppendEdit$value(value: P2pEdit$): string;

export type P2pEdit$ = PnCounterEdit | GCounterIncrementEdit | LwwRegisterSetEdit | LwwMapSetEdit | LwwMapRemoveEdit | MvRegisterEdit | OrMapIncrementEdit | OrMapSetRegisterEdit | OrMapSetMvRegisterEdit | OrMapRemoveEdit | OrMapAddMemberEdit | OrMapRemoveMemberEdit | OrSetAddEdit | OrSetRemoveEdit | GSetAddEdit | TwoPSetAddEdit | TwoPSetRemoveEdit | SequenceInsertEdit | SequenceDeleteEdit | SequenceMoveEdit | SequenceReplaceEdit | TextInsertEdit | TextDeleteRangeEdit | TextReplaceRangeEdit | TextAppendEdit;

export class MapEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $map_kernel.MapEvent$);
  /** @deprecated */
  0: $map_kernel.MapEvent$;
}
export function ChannelEvent$MapEvent($0: $map_kernel.MapEvent$): ChannelEvent$;
export function ChannelEvent$isMapEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$MapEvent$0(value: ChannelEvent$): $map_kernel.MapEvent$;

export class CounterEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $counter_kernel.CounterEvent$);
  /** @deprecated */
  0: $counter_kernel.CounterEvent$;
}
export function ChannelEvent$CounterEvent(
  $0: $counter_kernel.CounterEvent$,
): ChannelEvent$;
export function ChannelEvent$isCounterEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$CounterEvent$0(value: ChannelEvent$): $counter_kernel.CounterEvent$;

export class PnCounterEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $pn_counter_kernel.PnCounterEvent$);
  /** @deprecated */
  0: $pn_counter_kernel.PnCounterEvent$;
}
export function ChannelEvent$PnCounterEvent(
  $0: $pn_counter_kernel.PnCounterEvent$,
): ChannelEvent$;
export function ChannelEvent$isPnCounterEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$PnCounterEvent$0(value: ChannelEvent$): $pn_counter_kernel.PnCounterEvent$;

export class GCounterEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $g_counter_kernel.GCounterEvent$);
  /** @deprecated */
  0: $g_counter_kernel.GCounterEvent$;
}
export function ChannelEvent$GCounterEvent(
  $0: $g_counter_kernel.GCounterEvent$,
): ChannelEvent$;
export function ChannelEvent$isGCounterEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$GCounterEvent$0(value: ChannelEvent$): $g_counter_kernel.GCounterEvent$;

export class LwwRegisterEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $lww_register_kernel.LwwRegisterEvent$);
  /** @deprecated */
  0: $lww_register_kernel.LwwRegisterEvent$;
}
export function ChannelEvent$LwwRegisterEvent(
  $0: $lww_register_kernel.LwwRegisterEvent$,
): ChannelEvent$;
export function ChannelEvent$isLwwRegisterEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$LwwRegisterEvent$0(value: ChannelEvent$): $lww_register_kernel.LwwRegisterEvent$;

export class LwwMapEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $lww_map_kernel.LwwMapEvent$);
  /** @deprecated */
  0: $lww_map_kernel.LwwMapEvent$;
}
export function ChannelEvent$LwwMapEvent(
  $0: $lww_map_kernel.LwwMapEvent$,
): ChannelEvent$;
export function ChannelEvent$isLwwMapEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$LwwMapEvent$0(value: ChannelEvent$): $lww_map_kernel.LwwMapEvent$;

export class MvRegisterEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $mv_register_kernel.MvRegisterEvent$);
  /** @deprecated */
  0: $mv_register_kernel.MvRegisterEvent$;
}
export function ChannelEvent$MvRegisterEvent(
  $0: $mv_register_kernel.MvRegisterEvent$,
): ChannelEvent$;
export function ChannelEvent$isMvRegisterEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$MvRegisterEvent$0(value: ChannelEvent$): $mv_register_kernel.MvRegisterEvent$;

export class OrMapEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $or_map_kernel.OrMapEvent$);
  /** @deprecated */
  0: $or_map_kernel.OrMapEvent$;
}
export function ChannelEvent$OrMapEvent(
  $0: $or_map_kernel.OrMapEvent$,
): ChannelEvent$;
export function ChannelEvent$isOrMapEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$OrMapEvent$0(value: ChannelEvent$): $or_map_kernel.OrMapEvent$;

export class OrSetEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $or_set_kernel.OrSetEvent$);
  /** @deprecated */
  0: $or_set_kernel.OrSetEvent$;
}
export function ChannelEvent$OrSetEvent(
  $0: $or_set_kernel.OrSetEvent$,
): ChannelEvent$;
export function ChannelEvent$isOrSetEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$OrSetEvent$0(value: ChannelEvent$): $or_set_kernel.OrSetEvent$;

export class GSetEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $g_set_kernel.GSetEvent$);
  /** @deprecated */
  0: $g_set_kernel.GSetEvent$;
}
export function ChannelEvent$GSetEvent(
  $0: $g_set_kernel.GSetEvent$,
): ChannelEvent$;
export function ChannelEvent$isGSetEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$GSetEvent$0(value: ChannelEvent$): $g_set_kernel.GSetEvent$;

export class TwoPSetEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $two_p_set_kernel.TwoPSetEvent$);
  /** @deprecated */
  0: $two_p_set_kernel.TwoPSetEvent$;
}
export function ChannelEvent$TwoPSetEvent(
  $0: $two_p_set_kernel.TwoPSetEvent$,
): ChannelEvent$;
export function ChannelEvent$isTwoPSetEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$TwoPSetEvent$0(value: ChannelEvent$): $two_p_set_kernel.TwoPSetEvent$;

export class RegisterCollectionEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $register_collection_kernel.RegisterEvent$);
  /** @deprecated */
  0: $register_collection_kernel.RegisterEvent$;
}
export function ChannelEvent$RegisterCollectionEvent(
  $0: $register_collection_kernel.RegisterEvent$,
): ChannelEvent$;
export function ChannelEvent$isRegisterCollectionEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$RegisterCollectionEvent$0(value: ChannelEvent$): $register_collection_kernel.RegisterEvent$;

export class ClaimsEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $claims_kernel.ClaimEvent$);
  /** @deprecated */
  0: $claims_kernel.ClaimEvent$;
}
export function ChannelEvent$ClaimsEvent(
  $0: $claims_kernel.ClaimEvent$,
): ChannelEvent$;
export function ChannelEvent$isClaimsEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$ClaimsEvent$0(value: ChannelEvent$): $claims_kernel.ClaimEvent$;

export class TaskManagerEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $task_manager_kernel.TaskManagerEvent$);
  /** @deprecated */
  0: $task_manager_kernel.TaskManagerEvent$;
}
export function ChannelEvent$TaskManagerEvent(
  $0: $task_manager_kernel.TaskManagerEvent$,
): ChannelEvent$;
export function ChannelEvent$isTaskManagerEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$TaskManagerEvent$0(value: ChannelEvent$): $task_manager_kernel.TaskManagerEvent$;

export class PactMapEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $pact_map_kernel.PactMapEvent$);
  /** @deprecated */
  0: $pact_map_kernel.PactMapEvent$;
}
export function ChannelEvent$PactMapEvent(
  $0: $pact_map_kernel.PactMapEvent$,
): ChannelEvent$;
export function ChannelEvent$isPactMapEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$PactMapEvent$0(value: ChannelEvent$): $pact_map_kernel.PactMapEvent$;

export class JsonOtEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $json_ot_kernel.JsonOtEvent$);
  /** @deprecated */
  0: $json_ot_kernel.JsonOtEvent$;
}
export function ChannelEvent$JsonOtEvent(
  $0: $json_ot_kernel.JsonOtEvent$,
): ChannelEvent$;
export function ChannelEvent$isJsonOtEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$JsonOtEvent$0(value: ChannelEvent$): $json_ot_kernel.JsonOtEvent$;

export class DirectoryEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $directory_kernel.DirectoryEvent$);
  /** @deprecated */
  0: $directory_kernel.DirectoryEvent$;
}
export function ChannelEvent$DirectoryEvent(
  $0: $directory_kernel.DirectoryEvent$,
): ChannelEvent$;
export function ChannelEvent$isDirectoryEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$DirectoryEvent$0(value: ChannelEvent$): $directory_kernel.DirectoryEvent$;

export class OrderedCollectionEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $ordered_collection_kernel.OrderedEvent$);
  /** @deprecated */
  0: $ordered_collection_kernel.OrderedEvent$;
}
export function ChannelEvent$OrderedCollectionEvent(
  $0: $ordered_collection_kernel.OrderedEvent$,
): ChannelEvent$;
export function ChannelEvent$isOrderedCollectionEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$OrderedCollectionEvent$0(value: ChannelEvent$): $ordered_collection_kernel.OrderedEvent$;

export class SequenceEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $sequence_kernel.SequenceEvent$);
  /** @deprecated */
  0: $sequence_kernel.SequenceEvent$;
}
export function ChannelEvent$SequenceEvent(
  $0: $sequence_kernel.SequenceEvent$,
): ChannelEvent$;
export function ChannelEvent$isSequenceEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$SequenceEvent$0(value: ChannelEvent$): $sequence_kernel.SequenceEvent$;

export class RichTextEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $rich_text_kernel.RichTextEvent$);
  /** @deprecated */
  0: $rich_text_kernel.RichTextEvent$;
}
export function ChannelEvent$RichTextEvent(
  $0: $rich_text_kernel.RichTextEvent$,
): ChannelEvent$;
export function ChannelEvent$isRichTextEvent(
  value: any,
): value is ChannelEvent$;
export function ChannelEvent$RichTextEvent$0(value: ChannelEvent$): $rich_text_kernel.RichTextEvent$;

export class TextEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $text_kernel.TextEvent$);
  /** @deprecated */
  0: $text_kernel.TextEvent$;
}
export function ChannelEvent$TextEvent(
  $0: $text_kernel.TextEvent$,
): ChannelEvent$;
export function ChannelEvent$isTextEvent(value: any): value is ChannelEvent$;
export function ChannelEvent$TextEvent$0(value: ChannelEvent$): $text_kernel.TextEvent$;

export type ChannelEvent$ = MapEvent | CounterEvent | PnCounterEvent | GCounterEvent | LwwRegisterEvent | LwwMapEvent | MvRegisterEvent | OrMapEvent | OrSetEvent | GSetEvent | TwoPSetEvent | RegisterCollectionEvent | ClaimsEvent | TaskManagerEvent | PactMapEvent | JsonOtEvent | DirectoryEvent | OrderedCollectionEvent | SequenceEvent | RichTextEvent | TextEvent;

export class MapSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(entries: _.List<[string, $json.Json$]>);
  /** @deprecated */
  entries: _.List<[string, $json.Json$]>;
}
export function Snapshot$MapSnapshot(
  entries: _.List<[string, $json.Json$]>,
): Snapshot$;
export function Snapshot$isMapSnapshot(value: any): value is Snapshot$;
export function Snapshot$MapSnapshot$0(value: Snapshot$): _.List<
  [string, $json.Json$]
>;
export function Snapshot$MapSnapshot$entries(value: Snapshot$): _.List<
  [string, $json.Json$]
>;

export class CounterSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(value: number);
  /** @deprecated */
  value: number;
}
export function Snapshot$CounterSnapshot(value: number): Snapshot$;
export function Snapshot$isCounterSnapshot(value: any): value is Snapshot$;
export function Snapshot$CounterSnapshot$0(value: Snapshot$): number;
export function Snapshot$CounterSnapshot$value(value: Snapshot$): number;

export class PnCounterSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(state: $pn_counter.PNCounter$);
  /** @deprecated */
  state: $pn_counter.PNCounter$;
}
export function Snapshot$PnCounterSnapshot(
  state: $pn_counter.PNCounter$,
): Snapshot$;
export function Snapshot$isPnCounterSnapshot(value: any): value is Snapshot$;
export function Snapshot$PnCounterSnapshot$0(value: Snapshot$): $pn_counter.PNCounter$;
export function Snapshot$PnCounterSnapshot$state(
  value: Snapshot$,
): $pn_counter.PNCounter$;

export class GCounterSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(state: $g_counter.GCounter$);
  /** @deprecated */
  state: $g_counter.GCounter$;
}
export function Snapshot$GCounterSnapshot(
  state: $g_counter.GCounter$,
): Snapshot$;
export function Snapshot$isGCounterSnapshot(value: any): value is Snapshot$;
export function Snapshot$GCounterSnapshot$0(value: Snapshot$): $g_counter.GCounter$;
export function Snapshot$GCounterSnapshot$state(
  value: Snapshot$,
): $g_counter.GCounter$;

export class LwwRegisterSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(state: $lww_register.LWWRegister$<string>);
  /** @deprecated */
  state: $lww_register.LWWRegister$<string>;
}
export function Snapshot$LwwRegisterSnapshot(
  state: $lww_register.LWWRegister$<string>,
): Snapshot$;
export function Snapshot$isLwwRegisterSnapshot(value: any): value is Snapshot$;
export function Snapshot$LwwRegisterSnapshot$0(value: Snapshot$): $lww_register.LWWRegister$<
  string
>;
export function Snapshot$LwwRegisterSnapshot$state(value: Snapshot$): $lww_register.LWWRegister$<
  string
>;

export class LwwMapSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(state: $crdt.LWWMap$<string>);
  /** @deprecated */
  state: $crdt.LWWMap$<string>;
}
export function Snapshot$LwwMapSnapshot(
  state: $crdt.LWWMap$<string>,
): Snapshot$;
export function Snapshot$isLwwMapSnapshot(value: any): value is Snapshot$;
export function Snapshot$LwwMapSnapshot$0(value: Snapshot$): $crdt.LWWMap$<
  string
>;
export function Snapshot$LwwMapSnapshot$state(value: Snapshot$): $crdt.LWWMap$<
  string
>;

export class MvRegisterSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(state: $mv_register.MVRegister$<string>);
  /** @deprecated */
  state: $mv_register.MVRegister$<string>;
}
export function Snapshot$MvRegisterSnapshot(
  state: $mv_register.MVRegister$<string>,
): Snapshot$;
export function Snapshot$isMvRegisterSnapshot(value: any): value is Snapshot$;
export function Snapshot$MvRegisterSnapshot$0(value: Snapshot$): $mv_register.MVRegister$<
  string
>;
export function Snapshot$MvRegisterSnapshot$state(value: Snapshot$): $mv_register.MVRegister$<
  string
>;

export class OrMapSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(mode: $or_map_kernel.OrMapMode$, state: $crdt.ORMap$<string>);
  /** @deprecated */
  mode: $or_map_kernel.OrMapMode$;
  /** @deprecated */
  state: $crdt.ORMap$<string>;
}
export function Snapshot$OrMapSnapshot(
  mode: $or_map_kernel.OrMapMode$,
  state: $crdt.ORMap$<string>,
): Snapshot$;
export function Snapshot$isOrMapSnapshot(value: any): value is Snapshot$;
export function Snapshot$OrMapSnapshot$0(value: Snapshot$): $or_map_kernel.OrMapMode$;
export function Snapshot$OrMapSnapshot$mode(
  value: Snapshot$,
): $or_map_kernel.OrMapMode$;
export function Snapshot$OrMapSnapshot$1(value: Snapshot$): $crdt.ORMap$<string>;
export function Snapshot$OrMapSnapshot$state(
  value: Snapshot$,
): $crdt.ORMap$<string>;

export class OrSetSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(state: $or_set.ORSet$<string>);
  /** @deprecated */
  state: $or_set.ORSet$<string>;
}
export function Snapshot$OrSetSnapshot(
  state: $or_set.ORSet$<string>,
): Snapshot$;
export function Snapshot$isOrSetSnapshot(value: any): value is Snapshot$;
export function Snapshot$OrSetSnapshot$0(value: Snapshot$): $or_set.ORSet$<
  string
>;
export function Snapshot$OrSetSnapshot$state(value: Snapshot$): $or_set.ORSet$<
  string
>;

export class GSetSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(state: $g_set.GSet$<string>);
  /** @deprecated */
  state: $g_set.GSet$<string>;
}
export function Snapshot$GSetSnapshot(state: $g_set.GSet$<string>): Snapshot$;
export function Snapshot$isGSetSnapshot(value: any): value is Snapshot$;
export function Snapshot$GSetSnapshot$0(value: Snapshot$): $g_set.GSet$<string>;
export function Snapshot$GSetSnapshot$state(value: Snapshot$): $g_set.GSet$<
  string
>;

export class TwoPSetSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(state: $two_p_set.TwoPSet$<string>);
  /** @deprecated */
  state: $two_p_set.TwoPSet$<string>;
}
export function Snapshot$TwoPSetSnapshot(
  state: $two_p_set.TwoPSet$<string>,
): Snapshot$;
export function Snapshot$isTwoPSetSnapshot(value: any): value is Snapshot$;
export function Snapshot$TwoPSetSnapshot$0(value: Snapshot$): $two_p_set.TwoPSet$<
  string
>;
export function Snapshot$TwoPSetSnapshot$state(value: Snapshot$): $two_p_set.TwoPSet$<
  string
>;

export class RegisterCollectionSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(
    registers: _.List<[string, $register_collection_kernel.Register$]>
  );
  /** @deprecated */
  registers: _.List<[string, $register_collection_kernel.Register$]>;
}
export function Snapshot$RegisterCollectionSnapshot(
  registers: _.List<[string, $register_collection_kernel.Register$]>,
): Snapshot$;
export function Snapshot$isRegisterCollectionSnapshot(
  value: any,
): value is Snapshot$;
export function Snapshot$RegisterCollectionSnapshot$0(value: Snapshot$): _.List<
  [string, $register_collection_kernel.Register$]
>;
export function Snapshot$RegisterCollectionSnapshot$registers(value: Snapshot$): _.List<
  [string, $register_collection_kernel.Register$]
>;

export class ClaimsSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(entries: _.List<[string, $json.Json$, number]>);
  /** @deprecated */
  entries: _.List<[string, $json.Json$, number]>;
}
export function Snapshot$ClaimsSnapshot(
  entries: _.List<[string, $json.Json$, number]>,
): Snapshot$;
export function Snapshot$isClaimsSnapshot(value: any): value is Snapshot$;
export function Snapshot$ClaimsSnapshot$0(value: Snapshot$): _.List<
  [string, $json.Json$, number]
>;
export function Snapshot$ClaimsSnapshot$entries(value: Snapshot$): _.List<
  [string, $json.Json$, number]
>;

export class TaskManagerSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(queues: _.List<[string, _.List<number>]>);
  /** @deprecated */
  queues: _.List<[string, _.List<number>]>;
}
export function Snapshot$TaskManagerSnapshot(
  queues: _.List<[string, _.List<number>]>,
): Snapshot$;
export function Snapshot$isTaskManagerSnapshot(value: any): value is Snapshot$;
export function Snapshot$TaskManagerSnapshot$0(value: Snapshot$): _.List<
  [string, _.List<number>]
>;
export function Snapshot$TaskManagerSnapshot$queues(value: Snapshot$): _.List<
  [string, _.List<number>]
>;

export class PactMapSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(entries: _.List<[string, $pact_map_kernel.Pact$]>);
  /** @deprecated */
  entries: _.List<[string, $pact_map_kernel.Pact$]>;
}
export function Snapshot$PactMapSnapshot(
  entries: _.List<[string, $pact_map_kernel.Pact$]>,
): Snapshot$;
export function Snapshot$isPactMapSnapshot(value: any): value is Snapshot$;
export function Snapshot$PactMapSnapshot$0(value: Snapshot$): _.List<
  [string, $pact_map_kernel.Pact$]
>;
export function Snapshot$PactMapSnapshot$entries(value: Snapshot$): _.List<
  [string, $pact_map_kernel.Pact$]
>;

export class JsonOtSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(document: $json_ot.JsonValue$);
  /** @deprecated */
  document: $json_ot.JsonValue$;
}
export function Snapshot$JsonOtSnapshot(
  document: $json_ot.JsonValue$,
): Snapshot$;
export function Snapshot$isJsonOtSnapshot(value: any): value is Snapshot$;
export function Snapshot$JsonOtSnapshot$0(value: Snapshot$): $json_ot.JsonValue$;
export function Snapshot$JsonOtSnapshot$document(
  value: Snapshot$,
): $json_ot.JsonValue$;

export class DirectorySnapshot extends _.CustomType {
  /** @deprecated */
  constructor(summary: $directory_kernel.DirectorySummary$);
  /** @deprecated */
  summary: $directory_kernel.DirectorySummary$;
}
export function Snapshot$DirectorySnapshot(
  summary: $directory_kernel.DirectorySummary$,
): Snapshot$;
export function Snapshot$isDirectorySnapshot(value: any): value is Snapshot$;
export function Snapshot$DirectorySnapshot$0(value: Snapshot$): $directory_kernel.DirectorySummary$;
export function Snapshot$DirectorySnapshot$summary(
  value: Snapshot$,
): $directory_kernel.DirectorySummary$;

export class OrderedCollectionSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(
    queue: _.List<$json.Json$>,
    jobs: _.List<[string, $ordered_collection_kernel.JobEntry$]>
  );
  /** @deprecated */
  queue: _.List<$json.Json$>;
  /** @deprecated */
  jobs: _.List<[string, $ordered_collection_kernel.JobEntry$]>;
}
export function Snapshot$OrderedCollectionSnapshot(
  queue: _.List<$json.Json$>,
  jobs: _.List<[string, $ordered_collection_kernel.JobEntry$]>,
): Snapshot$;
export function Snapshot$isOrderedCollectionSnapshot(
  value: any,
): value is Snapshot$;
export function Snapshot$OrderedCollectionSnapshot$0(value: Snapshot$): _.List<
  $json.Json$
>;
export function Snapshot$OrderedCollectionSnapshot$queue(value: Snapshot$): _.List<
  $json.Json$
>;
export function Snapshot$OrderedCollectionSnapshot$1(value: Snapshot$): _.List<
  [string, $ordered_collection_kernel.JobEntry$]
>;
export function Snapshot$OrderedCollectionSnapshot$jobs(value: Snapshot$): _.List<
  [string, $ordered_collection_kernel.JobEntry$]
>;

export class SequenceSummary extends _.CustomType {
  /** @deprecated */
  constructor(state: $sequence.Sequence$<$json.Json$>);
  /** @deprecated */
  state: $sequence.Sequence$<$json.Json$>;
}
export function Snapshot$SequenceSummary(
  state: $sequence.Sequence$<$json.Json$>,
): Snapshot$;
export function Snapshot$isSequenceSummary(value: any): value is Snapshot$;
export function Snapshot$SequenceSummary$0(value: Snapshot$): $sequence.Sequence$<
  $json.Json$
>;
export function Snapshot$SequenceSummary$state(value: Snapshot$): $sequence.Sequence$<
  $json.Json$
>;

export class RichTextSnapshot extends _.CustomType {
  /** @deprecated */
  constructor(document: $rich_text.Document$);
  /** @deprecated */
  document: $rich_text.Document$;
}
export function Snapshot$RichTextSnapshot(
  document: $rich_text.Document$,
): Snapshot$;
export function Snapshot$isRichTextSnapshot(value: any): value is Snapshot$;
export function Snapshot$RichTextSnapshot$0(value: Snapshot$): $rich_text.Document$;
export function Snapshot$RichTextSnapshot$document(
  value: Snapshot$,
): $rich_text.Document$;

export class TextSummary extends _.CustomType {
  /** @deprecated */
  constructor(state: $text.Text$);
  /** @deprecated */
  state: $text.Text$;
}
export function Snapshot$TextSummary(state: $text.Text$): Snapshot$;
export function Snapshot$isTextSummary(value: any): value is Snapshot$;
export function Snapshot$TextSummary$0(value: Snapshot$): $text.Text$;
export function Snapshot$TextSummary$state(value: Snapshot$): $text.Text$;

export type Snapshot$ = MapSnapshot | CounterSnapshot | PnCounterSnapshot | GCounterSnapshot | LwwRegisterSnapshot | LwwMapSnapshot | MvRegisterSnapshot | OrMapSnapshot | OrSetSnapshot | GSetSnapshot | TwoPSetSnapshot | RegisterCollectionSnapshot | ClaimsSnapshot | TaskManagerSnapshot | PactMapSnapshot | JsonOtSnapshot | DirectorySnapshot | OrderedCollectionSnapshot | SequenceSummary | RichTextSnapshot | TextSummary;

export class ClaimResolved extends _.CustomType {
  /** @deprecated */
  constructor(key: string, outcome: $claims_kernel.ClaimOutcome$);
  /** @deprecated */
  key: string;
  /** @deprecated */
  outcome: $claims_kernel.ClaimOutcome$;
}
export function Resolution$ClaimResolved(
  key: string,
  outcome: $claims_kernel.ClaimOutcome$,
): Resolution$;
export function Resolution$isClaimResolved(value: any): value is Resolution$;
export function Resolution$ClaimResolved$0(value: Resolution$): string;
export function Resolution$ClaimResolved$key(value: Resolution$): string;
export function Resolution$ClaimResolved$1(value: Resolution$): $claims_kernel.ClaimOutcome$;
export function Resolution$ClaimResolved$outcome(
  value: Resolution$,
): $claims_kernel.ClaimOutcome$;

export class AcquireResolved extends _.CustomType {
  /** @deprecated */
  constructor(
    acquire_id: string,
    outcome: $ordered_collection_kernel.AcquireOutcome$
  );
  /** @deprecated */
  acquire_id: string;
  /** @deprecated */
  outcome: $ordered_collection_kernel.AcquireOutcome$;
}
export function Resolution$AcquireResolved(
  acquire_id: string,
  outcome: $ordered_collection_kernel.AcquireOutcome$,
): Resolution$;
export function Resolution$isAcquireResolved(value: any): value is Resolution$;
export function Resolution$AcquireResolved$0(value: Resolution$): string;
export function Resolution$AcquireResolved$acquire_id(value: Resolution$): string;
export function Resolution$AcquireResolved$1(
  value: Resolution$,
): $ordered_collection_kernel.AcquireOutcome$;
export function Resolution$AcquireResolved$outcome(value: Resolution$): $ordered_collection_kernel.AcquireOutcome$;

export type Resolution$ = ClaimResolved | AcquireResolved;

export class NoMeta extends _.CustomType {}
export function LocalOperationMeta$NoMeta(): LocalOperationMeta$;
export function LocalOperationMeta$isNoMeta(
  value: any,
): value is LocalOperationMeta$;

export class CounterMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$CounterMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isCounterMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$CounterMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$CounterMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class PnCounterMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$PnCounterMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isPnCounterMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$PnCounterMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$PnCounterMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class GCounterMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$GCounterMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isGCounterMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$GCounterMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$GCounterMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class LwwRegisterMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$LwwRegisterMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isLwwRegisterMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$LwwRegisterMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$LwwRegisterMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class LwwMapMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$LwwMapMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isLwwMapMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$LwwMapMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$LwwMapMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class MvRegisterMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$MvRegisterMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isMvRegisterMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$MvRegisterMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$MvRegisterMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class OrMapMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$OrMapMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isOrMapMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$OrMapMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$OrMapMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class OrSetMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$OrSetMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isOrSetMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$OrSetMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$OrSetMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class GSetMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$GSetMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isGSetMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$GSetMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$GSetMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class TwoPSetMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$TwoPSetMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isTwoPSetMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$TwoPSetMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$TwoPSetMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class TaskManagerMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$TaskManagerMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isTaskManagerMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$TaskManagerMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$TaskManagerMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class DirectoryMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$DirectoryMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isDirectoryMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$DirectoryMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$DirectoryMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class SequenceMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$SequenceMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isSequenceMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$SequenceMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$SequenceMeta$message_id(
  value: LocalOperationMeta$,
): number;

export class TextMeta extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function LocalOperationMeta$TextMeta(
  message_id: number,
): LocalOperationMeta$;
export function LocalOperationMeta$isTextMeta(
  value: any,
): value is LocalOperationMeta$;
export function LocalOperationMeta$TextMeta$0(value: LocalOperationMeta$): number;
export function LocalOperationMeta$TextMeta$message_id(
  value: LocalOperationMeta$,
): number;

export type LocalOperationMeta$ = NoMeta | CounterMeta | PnCounterMeta | GCounterMeta | LwwRegisterMeta | LwwMapMeta | MvRegisterMeta | OrMapMeta | OrSetMeta | GSetMeta | TwoPSetMeta | TaskManagerMeta | DirectoryMeta | SequenceMeta | TextMeta;

export class SequencedMeta extends _.CustomType {
  /** @deprecated */
  constructor(
    sequence_number: number,
    last_seen_sequence_number: number,
    minimum_sequence_number: number,
    author: number,
    self: number,
    quorum: _.List<number>,
    roster: _.List<number>,
    reference_sequence_number: number
  );
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  last_seen_sequence_number: number;
  /** @deprecated */
  minimum_sequence_number: number;
  /** @deprecated */
  author: number;
  /** @deprecated */
  self: number;
  /** @deprecated */
  quorum: _.List<number>;
  /** @deprecated */
  roster: _.List<number>;
  /** @deprecated */
  reference_sequence_number: number;
}
export function SequencedMeta$SequencedMeta(
  sequence_number: number,
  last_seen_sequence_number: number,
  minimum_sequence_number: number,
  author: number,
  self: number,
  quorum: _.List<number>,
  roster: _.List<number>,
  reference_sequence_number: number,
): SequencedMeta$;
export function SequencedMeta$isSequencedMeta(
  value: any,
): value is SequencedMeta$;
export function SequencedMeta$SequencedMeta$0(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$sequence_number(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$1(
  value: SequencedMeta$,
): number;
export function SequencedMeta$SequencedMeta$last_seen_sequence_number(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$2(
  value: SequencedMeta$,
): number;
export function SequencedMeta$SequencedMeta$minimum_sequence_number(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$3(
  value: SequencedMeta$,
): number;
export function SequencedMeta$SequencedMeta$author(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$4(
  value: SequencedMeta$,
): number;
export function SequencedMeta$SequencedMeta$self(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$5(value: SequencedMeta$): _.List<
  number
>;
export function SequencedMeta$SequencedMeta$quorum(value: SequencedMeta$): _.List<
  number
>;
export function SequencedMeta$SequencedMeta$6(value: SequencedMeta$): _.List<
  number
>;
export function SequencedMeta$SequencedMeta$roster(value: SequencedMeta$): _.List<
  number
>;
export function SequencedMeta$SequencedMeta$7(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$reference_sequence_number(value: SequencedMeta$): number;

export type SequencedMeta$ = SequencedMeta;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function ChannelError$UnexpectedAck(detail: string): ChannelError$;
export function ChannelError$isUnexpectedAck(
  value: any,
): value is ChannelError$;
export function ChannelError$UnexpectedAck$0(value: ChannelError$): string;
export function ChannelError$UnexpectedAck$detail(value: ChannelError$): string;

export class WrongChannelType extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function ChannelError$WrongChannelType(detail: string): ChannelError$;
export function ChannelError$isWrongChannelType(
  value: any,
): value is ChannelError$;
export function ChannelError$WrongChannelType$0(value: ChannelError$): string;
export function ChannelError$WrongChannelType$detail(value: ChannelError$): string;

export class CorruptRemoteOperation extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function ChannelError$CorruptRemoteOperation(
  detail: string,
): ChannelError$;
export function ChannelError$isCorruptRemoteOperation(
  value: any,
): value is ChannelError$;
export function ChannelError$CorruptRemoteOperation$0(value: ChannelError$): string;
export function ChannelError$CorruptRemoteOperation$detail(
  value: ChannelError$,
): string;

export class OrMapOperationFailed extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function ChannelError$OrMapOperationFailed(
  detail: string,
): ChannelError$;
export function ChannelError$isOrMapOperationFailed(
  value: any,
): value is ChannelError$;
export function ChannelError$OrMapOperationFailed$0(value: ChannelError$): string;
export function ChannelError$OrMapOperationFailed$detail(
  value: ChannelError$,
): string;

export class UnsupportedP2p extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function ChannelError$UnsupportedP2p(detail: string): ChannelError$;
export function ChannelError$isUnsupportedP2p(
  value: any,
): value is ChannelError$;
export function ChannelError$UnsupportedP2p$0(value: ChannelError$): string;
export function ChannelError$UnsupportedP2p$detail(value: ChannelError$): string;

export type ChannelError$ = UnexpectedAck | WrongChannelType | CorruptRemoteOperation | OrMapOperationFailed | UnsupportedP2p;

export function ChannelError$detail(value: ChannelError$): string;

export function type_to_string(channel_type: ChannelType$): string;

export function string_to_type(raw: string): _.Result<ChannelType$, undefined>;

export function init_type(init: ChannelInit$): ChannelType$;

export function supports_p2p(channel_type: ChannelType$): boolean;

export function channel_type(state: ChannelState$): ChannelType$;

export function snapshot_type(snapshot: Snapshot$): ChannelType$;

export function new$(init: ChannelInit$, replica: string): ChannelState$;

export function lww_map_error_detail(error: $lww_map_kernel.KernelError$): string;

export function lww_register_error_detail(
  error: $lww_register_kernel.KernelError$
): string;

export function from_snapshot(snapshot: Snapshot$, replica: string): _.Result<
  ChannelState$,
  string
>;

export function snapshot(state: ChannelState$): Snapshot$;

export function attach_snapshot(state: ChannelState$): Snapshot$;

export function attach_state(state: ChannelState$, replica: string): ChannelState$;

export function apply_remote(
  state: ChannelState$,
  operation: ChannelOperation$,
  meta: SequencedMeta$
): _.Result<
  [ChannelState$, _.List<ChannelEvent$>, _.List<ChannelOperation$>],
  ChannelError$
>;

export function applies_own_on_sequence(state: ChannelState$): boolean;

export function on_leave(
  state: ChannelState$,
  client_id: number,
  leave_sequence_number: number
): [ChannelState$, _.List<ChannelEvent$>];

export function ack_local(
  state: ChannelState$,
  operation: ChannelOperation$,
  local: LocalOperationMeta$,
  meta: SequencedMeta$
): _.Result<
  [ChannelState$, _.List<ChannelEvent$>, $option.Option$<Resolution$>],
  ChannelError$
>;

export function apply_p2p_local(state: ChannelState$, edit: P2pEdit$): _.Result<
  [ChannelState$, _.List<ChannelEvent$>, ChannelOperation$],
  ChannelError$
>;

export function apply_p2p_remote(
  state: ChannelState$,
  operation: ChannelOperation$
): _.Result<[ChannelState$, _.List<ChannelEvent$>], ChannelError$>;

export function merge_p2p_snapshot(state: ChannelState$, snapshot: Snapshot$): _.Result<
  [ChannelState$, _.List<ChannelEvent$>],
  ChannelError$
>;

export function take_outbound(state: ChannelState$): [
  ChannelState$,
  $option.Option$<ChannelOperation$>
];

export function same_shape(ours: ChannelOperation$, echoed: ChannelOperation$): boolean;

export function same_snapshot(ours: Snapshot$, echoed: Snapshot$): boolean;

export function handle_addresses(state: ChannelState$): _.List<string>;

export function encode_snapshot(snapshot: Snapshot$): $json.Json$;

export function lww_register_decoder(): $decode.Decoder$<
  $lww_register.LWWRegister$<string>
>;

export function snapshot_decoder(channel_type: ChannelType$): $decode.Decoder$<
  Snapshot$
>;

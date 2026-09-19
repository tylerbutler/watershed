import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $order from "../../gleam_stdlib/gleam/order.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $version_vector from "../../lattice_core/lattice_core/version_vector.d.mts";
import type * as _ from "../gleam.d.mts";

declare class ItemId extends _.CustomType {
  /** @deprecated */
  constructor(replica_id: $replica_id.ReplicaId$, counter: number);
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  counter: number;
}

export type ItemId$ = ItemId;

declare class OpId extends _.CustomType {
  /** @deprecated */
  constructor(replica_id: $replica_id.ReplicaId$, counter: number);
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  counter: number;
}

type OpId$ = OpId;

declare class Move extends _.CustomType {
  /** @deprecated */
  constructor(
    op_id: OpId$,
    origin_left: $option.Option$<ItemId$>,
    origin_right: $option.Option$<ItemId$>
  );
  /** @deprecated */
  op_id: OpId$;
  /** @deprecated */
  origin_left: $option.Option$<ItemId$>;
  /** @deprecated */
  origin_right: $option.Option$<ItemId$>;
}

type Move$ = Move;

declare class Item<KGF> extends _.CustomType {
  /** @deprecated */
  constructor(
    id: ItemId$,
    origin_left: $option.Option$<ItemId$>,
    origin_right: $option.Option$<ItemId$>,
    value: KGF,
    deleted: $option.Option$<OpId$>,
    move: $option.Option$<Move$>
  );
  /** @deprecated */
  id: ItemId$;
  /** @deprecated */
  origin_left: $option.Option$<ItemId$>;
  /** @deprecated */
  origin_right: $option.Option$<ItemId$>;
  /** @deprecated */
  value: KGF;
  /** @deprecated */
  deleted: $option.Option$<OpId$>;
  /** @deprecated */
  move: $option.Option$<Move$>;
}

type Item$<KGF> = Item<KGF>;

declare class Block<KGG> extends _.CustomType {
  /** @deprecated */
  constructor(first_id: ItemId$, values: _.List<KGG>);
  /** @deprecated */
  first_id: ItemId$;
  /** @deprecated */
  values: _.List<KGG>;
}

declare class Live<KGG> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Item$<KGG>);
  /** @deprecated */
  0: Item$<KGG>;
}

type Segment$<KGG> = Block<KGG> | Live<KGG>;

declare class Stable<KGH> extends _.CustomType {
  /** @deprecated */
  constructor(id: ItemId$, value: KGH);
  /** @deprecated */
  id: ItemId$;
  /** @deprecated */
  value: KGH;
}

declare class LiveEl<KGH> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Item$<KGH>);
  /** @deprecated */
  0: Item$<KGH>;
}

type Element$<KGH> = Stable<KGH> | LiveEl<KGH>;

declare class Forwarding extends _.CustomType {
  /** @deprecated */
  constructor(left: $option.Option$<ItemId$>, right: $option.Option$<ItemId$>);
  /** @deprecated */
  left: $option.Option$<ItemId$>;
  /** @deprecated */
  right: $option.Option$<ItemId$>;
}

type Forwarding$ = Forwarding;

declare class ForwardingMap extends _.CustomType {
  /** @deprecated */
  constructor(entries: $dict.Dict$<ItemId$, Forwarding$>);
  /** @deprecated */
  entries: $dict.Dict$<ItemId$, Forwarding$>;
}

export type ForwardingMap$ = ForwardingMap;

declare class Sequence<KGI> extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    counter: number,
    segments: _.List<Segment$<KGI>>,
    forwardings: $dict.Dict$<ItemId$, Forwarding$>,
    frontier: $version_vector.VersionVector$
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  counter: number;
  /** @deprecated */
  segments: _.List<Segment$<KGI>>;
  /** @deprecated */
  forwardings: $dict.Dict$<ItemId$, Forwarding$>;
  /** @deprecated */
  frontier: $version_vector.VersionVector$;
}

export type Sequence$<KGI> = Sequence<KGI>;

export class IndexOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function InsertError$IndexOutOfBounds(
  index: number,
  length: number,
): InsertError$;
export function InsertError$isIndexOutOfBounds(
  value: any,
): value is InsertError$;
export function InsertError$IndexOutOfBounds$0(value: InsertError$): number;
export function InsertError$IndexOutOfBounds$index(value: InsertError$): number;
export function InsertError$IndexOutOfBounds$1(value: InsertError$): number;
export function InsertError$IndexOutOfBounds$length(value: InsertError$): number;

export type InsertError$ = IndexOutOfBounds;

export class DeleteIndexOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function DeleteError$DeleteIndexOutOfBounds(
  index: number,
  length: number,
): DeleteError$;
export function DeleteError$isDeleteIndexOutOfBounds(
  value: any,
): value is DeleteError$;
export function DeleteError$DeleteIndexOutOfBounds$0(value: DeleteError$): number;
export function DeleteError$DeleteIndexOutOfBounds$index(
  value: DeleteError$,
): number;
export function DeleteError$DeleteIndexOutOfBounds$1(value: DeleteError$): number;
export function DeleteError$DeleteIndexOutOfBounds$length(
  value: DeleteError$,
): number;

export type DeleteError$ = DeleteIndexOutOfBounds;

export class MoveFromIndexOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function MoveError$MoveFromIndexOutOfBounds(
  index: number,
  length: number,
): MoveError$;
export function MoveError$isMoveFromIndexOutOfBounds(
  value: any,
): value is MoveError$;
export function MoveError$MoveFromIndexOutOfBounds$0(value: MoveError$): number;
export function MoveError$MoveFromIndexOutOfBounds$index(value: MoveError$): number;
export function MoveError$MoveFromIndexOutOfBounds$1(
  value: MoveError$,
): number;
export function MoveError$MoveFromIndexOutOfBounds$length(value: MoveError$): number;

export class MoveToIndexOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length_after_removal: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length_after_removal: number;
}
export function MoveError$MoveToIndexOutOfBounds(
  index: number,
  length_after_removal: number,
): MoveError$;
export function MoveError$isMoveToIndexOutOfBounds(
  value: any,
): value is MoveError$;
export function MoveError$MoveToIndexOutOfBounds$0(value: MoveError$): number;
export function MoveError$MoveToIndexOutOfBounds$index(value: MoveError$): number;
export function MoveError$MoveToIndexOutOfBounds$1(
  value: MoveError$,
): number;
export function MoveError$MoveToIndexOutOfBounds$length_after_removal(value: MoveError$): number;

export type MoveError$ = MoveFromIndexOutOfBounds | MoveToIndexOutOfBounds;

export function MoveError$index(value: MoveError$): number;

export class UnknownOriginTarget extends _.CustomType {}
export function TranslateError$UnknownOriginTarget(): TranslateError$;
export function TranslateError$isUnknownOriginTarget(
  value: any,
): value is TranslateError$;

export type TranslateError$ = UnknownOriginTarget;

export class Before extends _.CustomType {}
export function Bias$Before(): Bias$;
export function Bias$isBefore(value: any): value is Bias$;

export class After extends _.CustomType {}
export function Bias$After(): Bias$;
export function Bias$isAfter(value: any): value is Bias$;

export type Bias$ = Before | After;

declare class Start extends _.CustomType {}

declare class End extends _.CustomType {}

declare class AtItem extends _.CustomType {
  /** @deprecated */
  constructor(id: ItemId$, bias: Bias$);
  /** @deprecated */
  id: ItemId$;
  /** @deprecated */
  bias: Bias$;
}

export type Anchor$ = Start | End | AtItem;

export class AnchorIndexOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function AnchorError$AnchorIndexOutOfBounds(
  index: number,
  length: number,
): AnchorError$;
export function AnchorError$isAnchorIndexOutOfBounds(
  value: any,
): value is AnchorError$;
export function AnchorError$AnchorIndexOutOfBounds$0(value: AnchorError$): number;
export function AnchorError$AnchorIndexOutOfBounds$index(
  value: AnchorError$,
): number;
export function AnchorError$AnchorIndexOutOfBounds$1(value: AnchorError$): number;
export function AnchorError$AnchorIndexOutOfBounds$length(
  value: AnchorError$,
): number;

export class UnknownAnchorTarget extends _.CustomType {}
export function AnchorError$UnknownAnchorTarget(): AnchorError$;
export function AnchorError$isUnknownAnchorTarget(
  value: any,
): value is AnchorError$;

export type AnchorError$ = AnchorIndexOutOfBounds | UnknownAnchorTarget;

declare class BeforeElement extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: ItemId$);
  /** @deprecated */
  0: ItemId$;
}

declare class AfterGap extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $option.Option$<ItemId$>);
  /** @deprecated */
  0: $option.Option$<ItemId$>;
}

declare class AtEnd extends _.CustomType {}

type MoveTarget$ = BeforeElement | AfterGap | AtEnd;

declare class Retained<KGJ> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Element$<KGJ>);
  /** @deprecated */
  0: Element$<KGJ>;
}

declare class Dropped extends _.CustomType {
  /** @deprecated */
  constructor(id: ItemId$);
  /** @deprecated */
  id: ItemId$;
}

type Classified$<KGJ> = Retained<KGJ> | Dropped;

declare class DropTombstone extends _.CustomType {}

declare class ToStable extends _.CustomType {}

declare class KeepLive extends _.CustomType {}

type Stability$ = DropTombstone | ToStable | KeepLive;

declare class ScanEntry extends _.CustomType {
  /** @deprecated */
  constructor(
    id: ItemId$,
    left: $option.Option$<ItemId$>,
    right: $option.Option$<ItemId$>,
    stable: boolean
  );
  /** @deprecated */
  id: ItemId$;
  /** @deprecated */
  left: $option.Option$<ItemId$>;
  /** @deprecated */
  right: $option.Option$<ItemId$>;
  /** @deprecated */
  stable: boolean;
}

type ScanEntry$ = ScanEntry;

declare class StopScan extends _.CustomType {}

declare class TakeAsLeft extends _.CustomType {}

declare class AdvancePast extends _.CustomType {}

type ScanStep$ = StopScan | TakeAsLeft | AdvancePast;

export function new$(replica_id: $replica_id.ReplicaId$): Sequence$<any>;

export function replica_id(sequence: Sequence$<any>): $replica_id.ReplicaId$;

export function insert_many_with_delta<KHD>(
  sequence: Sequence$<KHD>,
  index: number,
  values: _.List<KHD>
): _.Result<[Sequence$<KHD>, Sequence$<KHD>], InsertError$>;

export function insert_with_delta<KGR>(
  sequence: Sequence$<KGR>,
  index: number,
  value: KGR
): _.Result<[Sequence$<KGR>, Sequence$<KGR>], InsertError$>;

export function insert<KGM>(sequence: Sequence$<KGM>, index: number, value: KGM): _.Result<
  Sequence$<KGM>,
  InsertError$
>;

export function insert_many<KGX>(
  sequence: Sequence$<KGX>,
  index: number,
  values: _.List<KGX>
): _.Result<Sequence$<KGX>, InsertError$>;

export function delete_with_delta<KIM>(sequence: Sequence$<KIM>, index: number): _.Result<
  [Sequence$<KIM>, Sequence$<KIM>],
  DeleteError$
>;

export function delete$<KIH>(sequence: Sequence$<KIH>, index: number): _.Result<
  Sequence$<KIH>,
  DeleteError$
>;

export function move_with_delta<KIX>(
  sequence: Sequence$<KIX>,
  from_index: number,
  to_index: number
): _.Result<[Sequence$<KIX>, Sequence$<KIX>], MoveError$>;

export function move<KIS>(
  sequence: Sequence$<KIS>,
  from_index: number,
  to_index: number
): _.Result<Sequence$<KIS>, MoveError$>;

export function start_anchor(): Anchor$;

export function end_anchor(): Anchor$;

export function anchor_at(sequence: Sequence$<any>, index: number, bias: Bias$): _.Result<
  Anchor$,
  AnchorError$
>;

export function resolve(sequence: Sequence$<any>, anchor: Anchor$): _.Result<
  number,
  AnchorError$
>;

export function anchor_to_json(anchor: Anchor$): $json.Json$;

export function anchor_from_json(json_string: string): _.Result<
  Anchor$,
  $json.DecodeError$
>;

export function values<KKJ>(sequence: Sequence$<KKJ>): _.List<KKJ>;

export function bind<KKO>(
  sequence: Sequence$<KKO>,
  replica: $replica_id.ReplicaId$
): Sequence$<KKO>;

export function length(sequence: Sequence$<any>): number;

export function frontier(sequence: Sequence$<any>): $version_vector.VersionVector$;

export function forwarding_size(map: ForwardingMap$): number;

export function remove_forwardings<KKV>(
  sequence: Sequence$<KKV>,
  map: ForwardingMap$
): Sequence$<KKV>;

export function merge<KKY>(
  a: Sequence$<KKY>,
  b: Sequence$<KKY>,
  replica: $replica_id.ReplicaId$
): Sequence$<KKY>;

export function merge_as<KLC>(
  a: Sequence$<KLC>,
  b: Sequence$<KLC>,
  replica: $replica_id.ReplicaId$
): Sequence$<KLC>;

export function compact<KPF>(
  sequence: Sequence$<KPF>,
  stable: $version_vector.VersionVector$
): [Sequence$<KPF>, ForwardingMap$];

export function translate_origins<KQN>(
  delta: Sequence$<KQN>,
  onto: Sequence$<KQN>
): _.Result<Sequence$<KQN>, TranslateError$>;

export function to_json<KRO>(
  sequence: Sequence$<KRO>,
  encode_value: (x0: KRO) => $json.Json$
): $json.Json$;

export function from_json<KRQ>(
  json_string: string,
  value_decoder: $decode.Decoder$<KRQ>
): _.Result<Sequence$<KRQ>, $json.DecodeError$>;

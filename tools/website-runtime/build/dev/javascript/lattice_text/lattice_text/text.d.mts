import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $version_vector from "../../lattice_core/lattice_core/version_vector.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as _ from "../gleam.d.mts";

declare class Text extends _.CustomType {
  /** @deprecated */
  constructor(sequence: $sequence.Sequence$<string>);
  /** @deprecated */
  sequence: $sequence.Sequence$<string>;
}

export type Text$ = Text;

export class RangeOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, length: number);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  length: number;
}
export function RangeError$RangeOutOfBounds(
  start: number,
  end: number,
  length: number,
): RangeError$;
export function RangeError$isRangeOutOfBounds(value: any): value is RangeError$;
export function RangeError$RangeOutOfBounds$0(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$start(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$1(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$end(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$2(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$length(value: RangeError$): number;

export type RangeError$ = RangeOutOfBounds;

export function new$(replica_id: $replica_id.ReplicaId$): Text$;

export function insert_with_delta(text: Text$, index: number, value: string): _.Result<
  [Text$, Text$],
  $sequence.InsertError$
>;

export function insert(text: Text$, index: number, value: string): _.Result<
  Text$,
  $sequence.InsertError$
>;

export function delete_with_delta(text: Text$, index: number): _.Result<
  [Text$, Text$],
  $sequence.DeleteError$
>;

export function delete$(text: Text$, index: number): _.Result<
  Text$,
  $sequence.DeleteError$
>;

export function values(text: Text$): _.List<string>;

export function value(text: Text$): string;

export function length(text: Text$): number;

export function substring(text: Text$, start: number, end: number): string;

export function try_substring(text: Text$, start: number, end: number): _.Result<
  string,
  RangeError$
>;

export function delete_range_with_delta(text: Text$, start: number, end: number): _.Result<
  [Text$, Text$],
  RangeError$
>;

export function delete_range(text: Text$, start: number, end: number): _.Result<
  Text$,
  RangeError$
>;

export function replace_range_with_delta(
  text: Text$,
  start: number,
  end: number,
  value: string
): _.Result<[Text$, Text$], RangeError$>;

export function replace_range(
  text: Text$,
  start: number,
  end: number,
  value: string
): _.Result<Text$, RangeError$>;

export function move_with_delta(
  text: Text$,
  from_index: number,
  to_index: number
): _.Result<[Text$, Text$], $sequence.MoveError$>;

export function move(text: Text$, from_index: number, to_index: number): _.Result<
  Text$,
  $sequence.MoveError$
>;

export function start_anchor(): $sequence.Anchor$;

export function end_anchor(): $sequence.Anchor$;

export function anchor_at(text: Text$, index: number, bias: $sequence.Bias$): _.Result<
  $sequence.Anchor$,
  $sequence.AnchorError$
>;

export function resolve_anchor(text: Text$, anchor: $sequence.Anchor$): _.Result<
  number,
  $sequence.AnchorError$
>;

export function anchor_to_json(anchor: $sequence.Anchor$): $json.Json$;

export function anchor_from_json(json_string: string): _.Result<
  $sequence.Anchor$,
  $json.DecodeError$
>;

export function append_with_delta(text: Text$, value: string): _.Result<
  [Text$, Text$],
  $sequence.InsertError$
>;

export function append(text: Text$, value: string): _.Result<
  Text$,
  $sequence.InsertError$
>;

export function compact(text: Text$, stable: $version_vector.VersionVector$): [
  Text$,
  $sequence.ForwardingMap$
];

export function remove_forwardings(text: Text$, map: $sequence.ForwardingMap$): Text$;

export function frontier(text: Text$): $version_vector.VersionVector$;

export function bind(text: Text$, replica: $replica_id.ReplicaId$): Text$;

export function merge(a: Text$, b: Text$, replica: $replica_id.ReplicaId$): Text$;

export function merge_as(a: Text$, b: Text$, replica: $replica_id.ReplicaId$): Text$;

export function to_json(text: Text$): $json.Json$;

export function from_json(json_string: string): _.Result<
  Text$,
  $json.DecodeError$
>;

import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class VNull extends _.CustomType {}
export function JsonValue$VNull(): JsonValue$;
export function JsonValue$isVNull(value: any): value is JsonValue$;

export class VBool extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: boolean);
  /** @deprecated */
  0: boolean;
}
export function JsonValue$VBool($0: boolean): JsonValue$;
export function JsonValue$isVBool(value: any): value is JsonValue$;
export function JsonValue$VBool$0(value: JsonValue$): boolean;

export class VNumber extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Number$);
  /** @deprecated */
  0: Number$;
}
export function JsonValue$VNumber($0: Number$): JsonValue$;
export function JsonValue$isVNumber(value: any): value is JsonValue$;
export function JsonValue$VNumber$0(value: JsonValue$): Number$;

export class VString extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function JsonValue$VString($0: string): JsonValue$;
export function JsonValue$isVString(value: any): value is JsonValue$;
export function JsonValue$VString$0(value: JsonValue$): string;

export class VArray extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<JsonValue$>);
  /** @deprecated */
  0: _.List<JsonValue$>;
}
export function JsonValue$VArray($0: _.List<JsonValue$>): JsonValue$;
export function JsonValue$isVArray(value: any): value is JsonValue$;
export function JsonValue$VArray$0(value: JsonValue$): _.List<JsonValue$>;

export class VObject extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<[string, JsonValue$]>);
  /** @deprecated */
  0: _.List<[string, JsonValue$]>;
}
export function JsonValue$VObject($0: _.List<[string, JsonValue$]>): JsonValue$;
export function JsonValue$isVObject(value: any): value is JsonValue$;
export function JsonValue$VObject$0(value: JsonValue$): _.List<
  [string, JsonValue$]
>;

export type JsonValue$ = VNull | VBool | VNumber | VString | VArray | VObject;

export class NInt extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}
export function Number$NInt($0: number): Number$;
export function Number$isNInt(value: any): value is Number$;
export function Number$NInt$0(value: Number$): number;

export class NFloat extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}
export function Number$NFloat($0: number): Number$;
export function Number$isNFloat(value: any): value is Number$;
export function Number$NFloat$0(value: Number$): number;

export type Number$ = NInt | NFloat;

export class Key extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function PathKey$Key($0: string): PathKey$;
export function PathKey$isKey(value: any): value is PathKey$;
export function PathKey$Key$0(value: PathKey$): string;

export class Index extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}
export function PathKey$Index($0: number): PathKey$;
export function PathKey$isIndex(value: any): value is PathKey$;
export function PathKey$Index$0(value: PathKey$): number;

export type PathKey$ = Key | Index;

export class Component extends _.CustomType {
  /** @deprecated */
  constructor(
    path: _.List<PathKey$>,
    object_insert: $option.Option$<JsonValue$>,
    object_delete: $option.Option$<JsonValue$>,
    list_insert: $option.Option$<JsonValue$>,
    list_delete: $option.Option$<JsonValue$>,
    list_move: $option.Option$<number>,
    na: $option.Option$<Number$>,
    subtype: $option.Option$<[string, JsonValue$]>
  );
  /** @deprecated */
  path: _.List<PathKey$>;
  /** @deprecated */
  object_insert: $option.Option$<JsonValue$>;
  /** @deprecated */
  object_delete: $option.Option$<JsonValue$>;
  /** @deprecated */
  list_insert: $option.Option$<JsonValue$>;
  /** @deprecated */
  list_delete: $option.Option$<JsonValue$>;
  /** @deprecated */
  list_move: $option.Option$<number>;
  /** @deprecated */
  na: $option.Option$<Number$>;
  /** @deprecated */
  subtype: $option.Option$<[string, JsonValue$]>;
}
export function Component$Component(
  path: _.List<PathKey$>,
  object_insert: $option.Option$<JsonValue$>,
  object_delete: $option.Option$<JsonValue$>,
  list_insert: $option.Option$<JsonValue$>,
  list_delete: $option.Option$<JsonValue$>,
  list_move: $option.Option$<number>,
  na: $option.Option$<Number$>,
  subtype: $option.Option$<[string, JsonValue$]>,
): Component$;
export function Component$isComponent(value: any): value is Component$;
export function Component$Component$0(value: Component$): _.List<PathKey$>;
export function Component$Component$path(value: Component$): _.List<PathKey$>;
export function Component$Component$1(value: Component$): $option.Option$<
  JsonValue$
>;
export function Component$Component$object_insert(value: Component$): $option.Option$<
  JsonValue$
>;
export function Component$Component$2(value: Component$): $option.Option$<
  JsonValue$
>;
export function Component$Component$object_delete(value: Component$): $option.Option$<
  JsonValue$
>;
export function Component$Component$3(value: Component$): $option.Option$<
  JsonValue$
>;
export function Component$Component$list_insert(value: Component$): $option.Option$<
  JsonValue$
>;
export function Component$Component$4(value: Component$): $option.Option$<
  JsonValue$
>;
export function Component$Component$list_delete(value: Component$): $option.Option$<
  JsonValue$
>;
export function Component$Component$5(value: Component$): $option.Option$<
  number
>;
export function Component$Component$list_move(value: Component$): $option.Option$<
  number
>;
export function Component$Component$6(value: Component$): $option.Option$<
  Number$
>;
export function Component$Component$na(value: Component$): $option.Option$<
  Number$
>;
export function Component$Component$7(value: Component$): $option.Option$<
  [string, JsonValue$]
>;
export function Component$Component$subtype(value: Component$): $option.Option$<
  [string, JsonValue$]
>;

export type Component$ = Component;

export class Lft extends _.CustomType {}
export function Side$Lft(): Side$;
export function Side$isLft(value: any): value is Side$;

export class Rgt extends _.CustomType {}
export function Side$Rgt(): Side$;
export function Side$isRgt(value: any): value is Side$;

export type Side$ = Lft | Rgt;

export class BadPath extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function OtError$BadPath(detail: string): OtError$;
export function OtError$isBadPath(value: any): value is OtError$;
export function OtError$BadPath$0(value: OtError$): string;
export function OtError$BadPath$detail(value: OtError$): string;

export class BadValue extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function OtError$BadValue(detail: string): OtError$;
export function OtError$isBadValue(value: any): value is OtError$;
export function OtError$BadValue$0(value: OtError$): string;
export function OtError$BadValue$detail(value: OtError$): string;

export class UnknownSubtype extends _.CustomType {
  /** @deprecated */
  constructor(name: string);
  /** @deprecated */
  name: string;
}
export function OtError$UnknownSubtype(name: string): OtError$;
export function OtError$isUnknownSubtype(value: any): value is OtError$;
export function OtError$UnknownSubtype$0(value: OtError$): string;
export function OtError$UnknownSubtype$name(value: OtError$): string;

export type OtError$ = BadPath | BadValue | UnknownSubtype;

declare class MergeReplace extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Component$);
  /** @deprecated */
  0: Component$;
}

declare class MergeDropBoth extends _.CustomType {}

declare class KeepDest extends _.CustomType {}

declare class NoMerge extends _.CustomType {}

type Merge$ = MergeReplace | MergeDropBoth | KeepDest | NoMerge;

declare class TextInsert extends _.CustomType {
  /** @deprecated */
  constructor(p: number, s: string);
  /** @deprecated */
  p: number;
  /** @deprecated */
  s: string;
}

declare class TextDelete extends _.CustomType {
  /** @deprecated */
  constructor(p: number, s: string);
  /** @deprecated */
  p: number;
  /** @deprecated */
  s: string;
}

type TextComp$ = TextInsert | TextDelete;

export type Operation = _.List<Component$>;

export function object_insert(path: _.List<PathKey$>, value: JsonValue$): Component$;

export function object_delete(path: _.List<PathKey$>, value: JsonValue$): Component$;

export function object_replace(
  path: _.List<PathKey$>,
  old: JsonValue$,
  new$: JsonValue$
): Component$;

export function list_insert(path: _.List<PathKey$>, value: JsonValue$): Component$;

export function list_delete(path: _.List<PathKey$>, value: JsonValue$): Component$;

export function list_replace(
  path: _.List<PathKey$>,
  old: JsonValue$,
  new$: JsonValue$
): Component$;

export function list_move(path: _.List<PathKey$>, to: number): Component$;

export function number_add(path: _.List<PathKey$>, delta: Number$): Component$;

export function subtype_component(
  path: _.List<PathKey$>,
  name: string,
  operation: JsonValue$
): Component$;

export function apply_subtype(
  name: string,
  value: JsonValue$,
  sub_operation: JsonValue$
): _.Result<JsonValue$, OtError$>;

export function apply(document: JsonValue$, operation: _.List<Component$>): _.Result<
  JsonValue$,
  OtError$
>;

export function transform(
  operation: _.List<Component$>,
  other: _.List<Component$>,
  side: Side$
): _.Result<_.List<Component$>, OtError$>;

export function invert(operation: _.List<Component$>): _.List<Component$>;

export function to_json(value: JsonValue$): $json.Json$;

export function decoder(): $decode.Decoder$<JsonValue$>;

export function parse_json(raw: string): _.Result<JsonValue$, undefined>;

export function operation_to_json(operation: _.List<Component$>): $json.Json$;

export function operation_decoder(): $decode.Decoder$<_.List<Component$>>;

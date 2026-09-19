import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $json_ot from "../watershed/json_ot.d.mts";
import type * as $attribute_map from "../watershed/rich_text/attribute_map.d.mts";
import type * as $operation_iterator from "../watershed/rich_text/operation_iterator.d.mts";

declare class Document extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<$operation_iterator.Operation$>);
  /** @deprecated */
  0: _.List<$operation_iterator.Operation$>;
}

export type Document$ = Document;

declare class Delta extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<$operation_iterator.Operation$>);
  /** @deprecated */
  0: _.List<$operation_iterator.Operation$>;
}

export type Delta$ = Delta;

export class Left extends _.CustomType {}
export function Side$Left(): Side$;
export function Side$isLeft(value: any): value is Side$;

export class Right extends _.CustomType {}
export function Side$Right(): Side$;
export function Side$isRight(value: any): value is Side$;

export type Side$ = Left | Right;

export class Selection extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function Selection$Selection(index: number, length: number): Selection$;
export function Selection$isSelection(value: any): value is Selection$;
export function Selection$Selection$0(value: Selection$): number;
export function Selection$Selection$index(value: Selection$): number;
export function Selection$Selection$1(value: Selection$): number;
export function Selection$Selection$length(value: Selection$): number;

export type Selection$ = Selection;

export class Malformed extends _.CustomType {
  /** @deprecated */
  constructor(component: string, reason: string);
  /** @deprecated */
  component: string;
  /** @deprecated */
  reason: string;
}
export function Error$Malformed(component: string, reason: string): Error$;
export function Error$isMalformed(value: any): value is Error$;
export function Error$Malformed$0(value: Error$): string;
export function Error$Malformed$component(value: Error$): string;
export function Error$Malformed$1(value: Error$): string;
export function Error$Malformed$reason(value: Error$): string;

export class InvalidApply extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function Error$InvalidApply(reason: string): Error$;
export function Error$isInvalidApply(value: any): value is Error$;
export function Error$InvalidApply$0(value: Error$): string;
export function Error$InvalidApply$reason(value: Error$): string;

export class InvalidBoundary extends _.CustomType {
  /** @deprecated */
  constructor(offset: number);
  /** @deprecated */
  offset: number;
}
export function Error$InvalidBoundary(offset: number): Error$;
export function Error$isInvalidBoundary(value: any): value is Error$;
export function Error$InvalidBoundary$0(value: Error$): number;
export function Error$InvalidBoundary$offset(value: Error$): number;

export type Error$ = Malformed | InvalidApply | InvalidBoundary;

export function empty_document(): Document$;

export function empty_delta(): Delta$;

export function attributes(entries: _.List<[string, $json_ot.JsonValue$]>): $attribute_map.Attributes$;

export function document_operations(document: Document$): _.Result<
  Document$,
  Error$
>;

export function document_insert_text(
  document: Document$,
  text: string,
  attributes: $attribute_map.Attributes$
): _.Result<Document$, Error$>;

export function document_insert_embed(
  document: Document$,
  embed: $json_ot.JsonValue$,
  attributes: $attribute_map.Attributes$
): _.Result<Document$, Error$>;

export function delta_insert_text(
  delta: Delta$,
  text: string,
  attributes: $attribute_map.Attributes$
): _.Result<Delta$, Error$>;

export function delta_insert_embed(
  delta: Delta$,
  embed: $json_ot.JsonValue$,
  attributes: $attribute_map.Attributes$
): _.Result<Delta$, Error$>;

export function delta_delete(delta: Delta$, amount: number): _.Result<
  Delta$,
  Error$
>;

export function delta_retain(
  delta: Delta$,
  amount: number,
  attributes: $attribute_map.Attributes$
): _.Result<Delta$, Error$>;

export function delta_operations(delta: Delta$): _.Result<Delta$, Error$>;

export function insert_text(
  text: string,
  attributes: $attribute_map.Attributes$
): $operation_iterator.Operation$;

export function insert_embed(
  embed: $json_ot.JsonValue$,
  attributes: $attribute_map.Attributes$
): $operation_iterator.Operation$;

export function delete$(amount: number): $operation_iterator.Operation$;

export function retain(amount: number, attributes: $attribute_map.Attributes$): $operation_iterator.Operation$;

export function document_to_operations(document: Document$): _.List<
  $operation_iterator.Operation$
>;

export function delta_to_operations(delta: Delta$): _.List<
  $operation_iterator.Operation$
>;

export function document_length(document: Document$): number;

export function length(delta: Delta$): number;

export function change_length(delta: Delta$): number;

export function normalize(delta: Delta$): Delta$;

export function compose(a: Delta$, b: Delta$): _.Result<Delta$, Error$>;

export function apply(document: Document$, delta: Delta$): _.Result<
  Document$,
  Error$
>;

export function transform(a: Delta$, b: Delta$, side: Side$): _.Result<
  Delta$,
  Error$
>;

export function invert(delta: Delta$, base: Document$): _.Result<Delta$, Error$>;

export function transform_position(
  delta: Delta$,
  index: number,
  is_own_operation: boolean
): _.Result<number, Error$>;

export function transform_selection(
  delta: Delta$,
  selection: Selection$,
  is_own_operation: boolean
): _.Result<Selection$, Error$>;

export function selection(index: number, length: number): _.Result<
  Selection$,
  Error$
>;

export function selection_index(selection: Selection$): number;

export function selection_length(selection: Selection$): number;

export function document_to_json(document: Document$): $json.Json$;

export function delta_to_json(delta: Delta$): $json.Json$;

export function document_from_json(value: $json_ot.JsonValue$): _.Result<
  Document$,
  Error$
>;

export function delta_from_json(value: $json_ot.JsonValue$): _.Result<
  Delta$,
  Error$
>;

export function parse_document(raw: string): _.Result<Document$, Error$>;

export function parse_delta(raw: string): _.Result<Delta$, Error$>;

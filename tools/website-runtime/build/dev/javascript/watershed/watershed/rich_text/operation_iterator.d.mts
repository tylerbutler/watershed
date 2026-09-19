import type * as _ from "../../gleam.d.mts";
import type * as $json_ot from "../../watershed/json_ot.d.mts";
import type * as $attribute_map from "../../watershed/rich_text/attribute_map.d.mts";

export class InsertText extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string, argument$1: $attribute_map.Attributes$);
  /** @deprecated */
  0: string;
  /** @deprecated */
  1: $attribute_map.Attributes$;
}
export function Operation$InsertText(
  $0: string,
  $1: $attribute_map.Attributes$,
): Operation$;
export function Operation$isInsertText(value: any): value is Operation$;
export function Operation$InsertText$0(value: Operation$): string;
export function Operation$InsertText$1(value: Operation$): $attribute_map.Attributes$;

export class InsertEmbed extends _.CustomType {
  /** @deprecated */
  constructor(
    argument$0: $json_ot.JsonValue$,
    argument$1: $attribute_map.Attributes$
  );
  /** @deprecated */
  0: $json_ot.JsonValue$;
  /** @deprecated */
  1: $attribute_map.Attributes$;
}
export function Operation$InsertEmbed(
  $0: $json_ot.JsonValue$,
  $1: $attribute_map.Attributes$,
): Operation$;
export function Operation$isInsertEmbed(value: any): value is Operation$;
export function Operation$InsertEmbed$0(value: Operation$): $json_ot.JsonValue$;
export function Operation$InsertEmbed$1(value: Operation$): $attribute_map.Attributes$;

export class Delete extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}
export function Operation$Delete($0: number): Operation$;
export function Operation$isDelete(value: any): value is Operation$;
export function Operation$Delete$0(value: Operation$): number;

export class Retain extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number, argument$1: $attribute_map.Attributes$);
  /** @deprecated */
  0: number;
  /** @deprecated */
  1: $attribute_map.Attributes$;
}
export function Operation$Retain(
  $0: number,
  $1: $attribute_map.Attributes$,
): Operation$;
export function Operation$isRetain(value: any): value is Operation$;
export function Operation$Retain$0(value: Operation$): number;
export function Operation$Retain$1(value: Operation$): $attribute_map.Attributes$;

export type Operation$ = InsertText | InsertEmbed | Delete | Retain;

export class Insert extends _.CustomType {}
export function Kind$Insert(): Kind$;
export function Kind$isInsert(value: any): value is Kind$;

export class DeleteKind extends _.CustomType {}
export function Kind$DeleteKind(): Kind$;
export function Kind$isDeleteKind(value: any): value is Kind$;

export class RetainKind extends _.CustomType {}
export function Kind$RetainKind(): Kind$;
export function Kind$isRetainKind(value: any): value is Kind$;

export type Kind$ = Insert | DeleteKind | RetainKind;

export class SplitBoundary extends _.CustomType {
  /** @deprecated */
  constructor(offset: number);
  /** @deprecated */
  offset: number;
}
export function IteratorError$SplitBoundary(offset: number): IteratorError$;
export function IteratorError$isSplitBoundary(
  value: any,
): value is IteratorError$;
export function IteratorError$SplitBoundary$0(value: IteratorError$): number;
export function IteratorError$SplitBoundary$offset(value: IteratorError$): number;

export type IteratorError$ = SplitBoundary;

export class Iterator extends _.CustomType {
  /** @deprecated */
  constructor(operations: _.List<Operation$>, offset: number);
  /** @deprecated */
  operations: _.List<Operation$>;
  /** @deprecated */
  offset: number;
}
export function Iterator$Iterator(
  operations: _.List<Operation$>,
  offset: number,
): Iterator$;
export function Iterator$isIterator(value: any): value is Iterator$;
export function Iterator$Iterator$0(value: Iterator$): _.List<Operation$>;
export function Iterator$Iterator$operations(value: Iterator$): _.List<
  Operation$
>;
export function Iterator$Iterator$1(value: Iterator$): number;
export function Iterator$Iterator$offset(value: Iterator$): number;

export type Iterator$ = Iterator;

export function new$(operations: _.List<Operation$>): Iterator$;

export function has_next(iterator: Iterator$): boolean;

export function peek_kind(iterator: Iterator$): Kind$;

export function length(operation: Operation$): number;

export function peek_length(iterator: Iterator$): _.Result<number, undefined>;

export function take(iterator: Iterator$, requested: number): _.Result<
  [Operation$, Iterator$],
  IteratorError$
>;

export function attributes(operation: Operation$): $attribute_map.Attributes$;

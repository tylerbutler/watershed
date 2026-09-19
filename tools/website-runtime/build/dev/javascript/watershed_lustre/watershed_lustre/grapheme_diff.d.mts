import type * as _ from "../gleam.d.mts";

export class NoChange extends _.CustomType {}
export function Edit$NoChange(): Edit$;
export function Edit$isNoChange(value: any): value is Edit$;

export class Insert extends _.CustomType {
  /** @deprecated */
  constructor(index: number, value: string);
  /** @deprecated */
  index: number;
  /** @deprecated */
  value: string;
}
export function Edit$Insert(index: number, value: string): Edit$;
export function Edit$isInsert(value: any): value is Edit$;
export function Edit$Insert$0(value: Edit$): number;
export function Edit$Insert$index(value: Edit$): number;
export function Edit$Insert$1(value: Edit$): string;
export function Edit$Insert$value(value: Edit$): string;

export class Delete extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
}
export function Edit$Delete(start: number, end: number): Edit$;
export function Edit$isDelete(value: any): value is Edit$;
export function Edit$Delete$0(value: Edit$): number;
export function Edit$Delete$start(value: Edit$): number;
export function Edit$Delete$1(value: Edit$): number;
export function Edit$Delete$end(value: Edit$): number;

export class Replace extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, value: string);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  value: string;
}
export function Edit$Replace(start: number, end: number, value: string): Edit$;
export function Edit$isReplace(value: any): value is Edit$;
export function Edit$Replace$0(value: Edit$): number;
export function Edit$Replace$start(value: Edit$): number;
export function Edit$Replace$1(value: Edit$): number;
export function Edit$Replace$end(value: Edit$): number;
export function Edit$Replace$2(value: Edit$): string;
export function Edit$Replace$value(value: Edit$): string;

export type Edit$ = NoChange | Insert | Delete | Replace;

export function diff(old: string, new$: string): Edit$;

export function shift(edit: Edit$, amount: number): Edit$;

export function replacement(old: string, new$: string, region: [number, number]): _.Result<
  string,
  undefined
>;

export function splice(start: number, end: number, value: string): Edit$;

import type * as _ from "../../gleam.d.mts";

export function length(value: string): number;

export function valid(value: string): boolean;

export function boundary(value: string, offset: number): boolean;

export function slice(value: string, start: number, size: number): _.Result<
  string,
  undefined
>;

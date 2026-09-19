import type * as _ from "../../gleam.d.mts";

export type Symbol$ = any;

export function new$(description: string): Symbol$;

export function get_or_create_global(key: string): Symbol$;

export function description(symbol: Symbol$): _.Result<string, undefined>;

import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../../gleam.d.mts";

export type Atom$ = any;

export function get(a: string): _.Result<Atom$, undefined>;

export function create(a: string): Atom$;

export function to_string(a: Atom$): string;

export function to_dynamic(a: Atom$): $dynamic.Dynamic$;

export function cast_from_dynamic(a: $dynamic.Dynamic$): Atom$;

export function decoder(): $decode.Decoder$<Atom$>;

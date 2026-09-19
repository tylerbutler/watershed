import type * as $promise from "../../../gleam_javascript/gleam/javascript/promise.d.mts";
import type * as _ from "../../gleam.d.mts";

export type FormData$ = any;

export function new$(): FormData$;

export function append(form_data: FormData$, key: string, value: string): FormData$;

export function append_bits(
  form_data: FormData$,
  key: string,
  value: _.BitArray
): FormData$;

export function set(form_data: FormData$, key: string, value: string): FormData$;

export function set_bits(form_data: FormData$, key: string, value: _.BitArray): FormData$;

export function delete$(form_data: FormData$, key: string): FormData$;

export function get(form_data: FormData$, key: string): _.List<string>;

export function get_bits(form_data: FormData$, key: string): $promise.Promise$<
  _.List<_.BitArray>
>;

export function contains(form_data: FormData$, key: string): boolean;

export function keys(form_data: FormData$): _.List<string>;

import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as _ from "../../gleam.d.mts";

export type Builder = _.List<[string, $json.Json$]>;

export function new$(): _.List<[string, $json.Json$]>;

export function json(
  entries: _.List<[string, $json.Json$]>,
  key: string,
  value: $json.Json$
): _.List<[string, $json.Json$]>;

export function tagged(kind: number): _.List<[string, $json.Json$]>;

export function build(entries: _.List<[string, $json.Json$]>): $json.Json$;

export function string(
  entries: _.List<[string, $json.Json$]>,
  key: string,
  value: string
): _.List<[string, $json.Json$]>;

export function int(
  entries: _.List<[string, $json.Json$]>,
  key: string,
  value: number
): _.List<[string, $json.Json$]>;

export function bool(
  entries: _.List<[string, $json.Json$]>,
  key: string,
  value: boolean
): _.List<[string, $json.Json$]>;

export function list<TDI>(
  entries: _.List<[string, $json.Json$]>,
  key: string,
  values: _.List<TDI>,
  to_json: (x0: TDI) => $json.Json$
): _.List<[string, $json.Json$]>;

export function object(
  entries: _.List<[string, $json.Json$]>,
  key: string,
  nested: _.List<[string, $json.Json$]>
): _.List<[string, $json.Json$]>;

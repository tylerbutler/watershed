import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";

export const fluid_handle_type: string;

export function handle_url(address: string): string;

export function encode_handle(address: string): $json.Json$;

export function parse_handle(value: $json.Json$): _.Result<string, undefined>;

export function collect_handle_addresses(value: $json.Json$): _.List<string>;

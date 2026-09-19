/// <reference types="./schema_cli.d.mts" />
import * as $json from "../gleam_json/gleam/json.mjs";
import * as $io from "../gleam_stdlib/gleam/io.mjs";
import * as $schema from "./spillway/schema.mjs";

export function main() {
  let _pipe = $schema.generate_protocol_schema();
  let _pipe$1 = $json.to_string(_pipe);
  return $io.println(_pipe$1);
}

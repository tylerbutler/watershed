/// <reference types="./client_id.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok } from "../gleam.mjs";

function stable_hash(client_id) {
  let _pipe = $string.to_utf_codepoints(client_id);
  return $list.fold(
    _pipe,
    216_613_626,
    (acc, codepoint) => {
      let next = (acc * 16_777_619 + $string.utf_codepoint_to_int(codepoint)) % 2_147_483_647;
      let $ = next < 0;
      if ($) {
        return 0 - next;
      } else {
        return next;
      }
    },
  );
}

/**
 * Derive the integer id of a client. If the string has a numeric suffix after
 * the last `_`, use that suffix. Fluid client ids have the form
 * `<prefix>_<n>`. If there is no such suffix, use a stable hash of the whole
 * string.
 */
export function to_int(client_id) {
  let $ = (() => {
    let _pipe = $string.split(client_id, "_");
    return $list.last(_pipe);
  })();
  if ($ instanceof Ok) {
    let raw = $[0];
    let $1 = $int.parse(raw);
    if ($1 instanceof Ok) {
      let parsed = $1[0];
      return parsed;
    } else {
      return stable_hash(client_id);
    }
  } else {
    return stable_hash(client_id);
  }
}

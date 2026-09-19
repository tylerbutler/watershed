/// <reference types="./handle.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, Error, toList, List$Empty$const as $List$Empty$const } from "../gleam.mjs";

export const fluid_handle_type = "__fluid_handle__";

export function handle_url(address) {
  return "/" + address;
}

export function encode_handle(address) {
  return $json.object(
    toList([
      ["type", $json.string(fluid_handle_type)],
      ["url", $json.string(handle_url(address))],
    ]),
  );
}

/**
 * The one path segment of a handle URL. The result is `Error(Nil)` for a URL
 * that is not exactly `"/address"`.
 * 
 * @ignore
 */
function single_segment_url(url) {
  let length = $string.length(url);
  let $ = ((length > 1) && ($string.slice(url, 0, 1) === "/")) && !$string.contains(
    $string.slice(url, 1, length),
    "/",
  );
  if ($) {
    return new Ok($string.slice(url, 1, length));
  } else {
    return new Error(undefined);
  }
}

/**
 * Decode a handle marker to its address. A marker is exactly
 * `{type: fluid_handle_type, url: "/address"}`. The url must have one segment,
 * and the object must have no other keys.
 * 
 * @ignore
 */
function marker_decoder() {
  return $decode.then$(
    $decode.dict($decode.string, $decode.string),
    (object) => {
      let _block;
      let $ = $dict.size(object) === 2;
      if ($) {
        let $1 = $dict.get(object, "type");
        let $2 = $dict.get(object, "url");
        if ($1 instanceof Ok && $2 instanceof Ok) {
          let marker_type = $1[0];
          if (marker_type === "__fluid_handle__") {
            let url = $2[0];
            _block = single_segment_url(url);
          } else {
            _block = new Error(undefined);
          }
        } else {
          _block = new Error(undefined);
        }
      } else {
        _block = new Error(undefined);
      }
      let address = _block;
      if (address instanceof Ok) {
        let address$1 = address[0];
        return $decode.success(address$1);
      } else {
        return $decode.failure("", "HandleMarker");
      }
    },
  );
}

export function parse_handle(value) {
  let _pipe = $json.parse($json.to_string(value), marker_decoder());
  return $result.replace_error(_pipe, undefined);
}

function collect_decoder() {
  let non_null = $decode.one_of(
    (() => {
      let _pipe = marker_decoder();
      return $decode.map(_pipe, (address) => { return toList([address]); });
    })(),
    toList([
      (() => {
        let _pipe = $decode.string;
        return $decode.map(_pipe, (_) => { return $List$Empty$const; });
      })(),
      (() => {
        let _pipe = $decode.bool;
        return $decode.map(_pipe, (_) => { return $List$Empty$const; });
      })(),
      (() => {
        let _pipe = $decode.int;
        return $decode.map(_pipe, (_) => { return $List$Empty$const; });
      })(),
      (() => {
        let _pipe = $decode.float;
        return $decode.map(_pipe, (_) => { return $List$Empty$const; });
      })(),
      (() => {
        let _pipe = $decode.list($decode.recursive(collect_decoder));
        return $decode.map(_pipe, $list.flatten);
      })(),
      (() => {
        let _pipe = $decode.dict(
          $decode.string,
          $decode.recursive(collect_decoder),
        );
        return $decode.map(
          _pipe,
          (object) => {
            let _pipe$1 = $dict.values(object);
            return $list.flatten(_pipe$1);
          },
        );
      })(),
    ]),
  );
  let _pipe = $decode.optional(non_null);
  return $decode.map(
    _pipe,
    (_capture) => { return $option.unwrap(_capture, $List$Empty$const); },
  );
}

export function collect_handle_addresses(value) {
  let $ = $json.parse($json.to_string(value), collect_decoder());
  if ($ instanceof Ok) {
    let addresses = $[0];
    return $list.unique(addresses);
  } else {
    return $List$Empty$const;
  }
}

/// <reference types="./wire.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some } from "../../gleam_stdlib/gleam/option.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, toList, CustomType as $CustomType, isEqual } from "../gleam.mjs";

export class OutboundOperation extends $CustomType {
  constructor(client_sequence_number, reference_sequence_number, operation_type, contents, metadata) {
    super();
    this.client_sequence_number = client_sequence_number;
    this.reference_sequence_number = reference_sequence_number;
    this.operation_type = operation_type;
    this.contents = contents;
    this.metadata = metadata;
  }
}
export const OutboundOperation$OutboundOperation = (client_sequence_number, reference_sequence_number, operation_type, contents, metadata) =>
  new OutboundOperation(client_sequence_number,
  reference_sequence_number,
  operation_type,
  contents,
  metadata);
export const OutboundOperation$isOutboundOperation = (value) =>
  value instanceof OutboundOperation;
export const OutboundOperation$OutboundOperation$client_sequence_number = (value) =>
  value.client_sequence_number;
export const OutboundOperation$OutboundOperation$0 = (value) =>
  value.client_sequence_number;
export const OutboundOperation$OutboundOperation$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const OutboundOperation$OutboundOperation$1 = (value) =>
  value.reference_sequence_number;
export const OutboundOperation$OutboundOperation$operation_type = (value) =>
  value.operation_type;
export const OutboundOperation$OutboundOperation$2 = (value) =>
  value.operation_type;
export const OutboundOperation$OutboundOperation$contents = (value) =>
  value.contents;
export const OutboundOperation$OutboundOperation$3 = (value) => value.contents;
export const OutboundOperation$OutboundOperation$metadata = (value) =>
  value.metadata;
export const OutboundOperation$OutboundOperation$4 = (value) => value.metadata;

class ComparableNull extends $CustomType {}
const ComparableJson$ComparableNull$const = new ComparableNull();

class ComparableBool extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class ComparableString extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class ComparableNumber extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class ComparableInteger extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class ComparableArray extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class ComparableObject extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

const max_safe_json_integer = 9_007_199_254_740_991;

const min_safe_json_integer = -9_007_199_254_740_991;

/**
 * The wire names of the channel types that watershed uses. These are the
 * `channelType` field of the attach envelope and the `type` field of the
 * summary blob. The map tag is one member of that set.
 */
export const channel_type_map = "map";

export const channel_type_counter = "counter";

export const channel_type_pn_counter = "pnCounter";

export const channel_type_g_counter = "gCounter";

export const channel_type_lww_register = "lwwRegister";

export const channel_type_lww_map = "lwwMap";

export const channel_type_mv_register = "mv-register";

export const channel_type_or_map = "ormap";

export const channel_type_or_set = "orset";

export const channel_type_g_set = "g-set";

export const channel_type_two_p_set = "two-p-set";

export const channel_type_register_collection = "registerCollection";

export const channel_type_claims = "claims";

export const channel_type_task_manager = "taskManager";

export const channel_type_pact_map = "pactMap";

export const channel_type_ordered_collection = "orderedCollection";

export const channel_type_json_ot = "json0";

export const channel_type_directory = "directory";

export const channel_type_sequence = "sequence";

export const channel_type_rich_text = "richText";

export const channel_type_text = "text";

/**
 * Encode the map entries as the ordered `[{key, value}]` array. An attach
 * snapshot and a summary blob channel both use that array.
 */
export function encode_entries(entries) {
  return $json.array(
    entries,
    (entry) => {
      return $json.object(
        toList([["key", $json.string(entry[0])], ["value", entry[1]]]),
      );
    },
  );
}

/**
 * Decode a parsed-JSON `Dynamic` value back into a `Json` value. The decoded
 * operation contents can then go into the kernel, which stores each value as
 * `Json`.
 */
export function json_value_decoder() {
  let non_null = $decode.one_of(
    (() => {
      let _pipe = $decode.string;
      return $decode.map(_pipe, $json.string);
    })(),
    toList([
      (() => {
        let _pipe = $decode.bool;
        return $decode.map(_pipe, $json.bool);
      })(),
      (() => {
        let _pipe = $decode.int;
        return $decode.map(_pipe, $json.int);
      })(),
      (() => {
        let _pipe = $decode.float;
        return $decode.map(_pipe, $json.float);
      })(),
      (() => {
        let _pipe = $decode.list($decode.recursive(json_value_decoder));
        return $decode.map(_pipe, $json.preprocessed_array);
      })(),
      (() => {
        let _pipe = $decode.dict(
          $decode.string,
          $decode.recursive(json_value_decoder),
        );
        return $decode.map(
          _pipe,
          (object) => { return $json.object($dict.to_list(object)); },
        );
      })(),
    ]),
  );
  let _pipe = $decode.optional(non_null);
  return $decode.map(
    _pipe,
    (value) => {
      if (value instanceof Some) {
        let inner = value[0];
        return inner;
      } else {
        return $json.null$();
      }
    },
  );
}

/**
 * Decode one `{key, value}` map entry.
 */
export function entry_decoder() {
  return $decode.field(
    "key",
    $decode.string,
    (key) => {
      return $decode.field(
        "value",
        json_value_decoder(),
        (value) => { return $decode.success([key, value]); },
      );
    },
  );
}

/**
 * `json_value_decoder` as a plain function. A value that the decoder cannot
 * read becomes null.
 */
export function dynamic_to_json(value) {
  let $ = $decode.run(value, json_value_decoder());
  if ($ instanceof Ok) {
    let decoded = $[0];
    return decoded;
  } else {
    return $json.null$();
  }
}

function comparable_json_decoder() {
  let non_null = $decode.one_of(
    (() => {
      let _pipe = $decode.string;
      return $decode.map(
        _pipe,
        (var0) => { return new ComparableString(var0); },
      );
    })(),
    toList([
      (() => {
        let _pipe = $decode.bool;
        return $decode.map(
          _pipe,
          (var0) => { return new ComparableBool(var0); },
        );
      })(),
      (() => {
        let _pipe = $decode.int;
        return $decode.map(
          _pipe,
          (value) => {
            let $ = (value >= min_safe_json_integer) && (value <= max_safe_json_integer);
            if ($) {
              return new ComparableNumber($int.to_float(value));
            } else {
              return new ComparableInteger(value);
            }
          },
        );
      })(),
      (() => {
        let _pipe = $decode.float;
        return $decode.map(
          _pipe,
          (var0) => { return new ComparableNumber(var0); },
        );
      })(),
      (() => {
        let _pipe = $decode.list($decode.recursive(comparable_json_decoder));
        return $decode.map(
          _pipe,
          (var0) => { return new ComparableArray(var0); },
        );
      })(),
      (() => {
        let _pipe = $decode.dict(
          $decode.string,
          $decode.recursive(comparable_json_decoder),
        );
        return $decode.map(
          _pipe,
          (object) => {
            return new ComparableObject(
              (() => {
                let _pipe$1 = object;
                let _pipe$2 = $dict.to_list(_pipe$1);
                return $list.sort(
                  _pipe$2,
                  (a, b) => { return $string.compare(a[0], b[0]); },
                );
              })(),
            );
          },
        );
      })(),
    ]),
  );
  let _pipe = $decode.optional(non_null);
  return $decode.map(
    _pipe,
    (value) => {
      if (value instanceof Some) {
        let inner = value[0];
        return inner;
      } else {
        return ComparableJson$ComparableNull$const;
      }
    },
  );
}

/**
 * Compare two JSON values by their data, and not by their encoded text. The
 * comparison ignores the object key order. A safe integral float is equal to
 * the same integer, so the number normalization of JavaScript cannot break an
 * echo.
 */
export function json_semantically_equal(ours, echoed) {
  let $ = $json.parse($json.to_string(ours), comparable_json_decoder());
  let $1 = $json.parse($json.to_string(echoed), comparable_json_decoder());
  if ($ instanceof Ok && $1 instanceof Ok) {
    let ours$1 = $[0];
    let echoed$1 = $1[0];
    return isEqual(ours$1, echoed$1);
  } else {
    return false;
  }
}

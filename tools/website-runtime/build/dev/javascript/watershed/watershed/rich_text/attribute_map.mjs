/// <reference types="./attribute_map.d.mts" />
import * as $list from "../../../gleam_stdlib/gleam/list.mjs";
import * as $order from "../../../gleam_stdlib/gleam/order.mjs";
import * as $string from "../../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../../gleam.mjs";
import * as $json_ot from "../../watershed/json_ot.mjs";
import { VNull, JsonValue$VNull$const } from "../../watershed/json_ot.mjs";

class Attributes extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

export function empty() {
  return new Attributes($List$Empty$const);
}

function insert_sorted(entries, entry) {
  if (entries instanceof $Empty) {
    return toList([entry]);
  } else {
    let first = entries.head;
    let rest = entries.tail;
    let $ = $string.compare(entry[0], first[0]);
    if ($ instanceof $order.Lt) {
      return listPrepend(entry, listPrepend(first, rest));
    } else {
      return listPrepend(first, insert_sorted(rest, entry));
    }
  }
}

function put(entries, entry) {
  let without = $list.filter(
    entries,
    (current) => { return current[0] !== entry[0]; },
  );
  return insert_sorted(without, entry);
}

export function from_list(entries) {
  return new Attributes(
    (() => {
      let _pipe = entries;
      return $list.fold(_pipe, $List$Empty$const, put);
    })(),
  );
}

export function to_list(attributes) {
  let entries = attributes[0];
  return entries;
}

export function is_empty(attributes) {
  let entries = attributes[0];
  return entries instanceof $Empty;
}

export function get(attributes, key) {
  let entries = attributes[0];
  return $list.key_find(entries, key);
}

export function without_nulls(attributes) {
  let entries = attributes[0];
  return new Attributes(
    $list.filter(entries, (entry) => { return !(entry[1] instanceof VNull); }),
  );
}

/**
 * Quill `AttributeMap.compose`. This function keeps a null value for a
 * retain patch only.
 */
export function compose(a, b, keep_null) {
  let left = a[0];
  let right = b[0];
  let _block;
  if (keep_null) {
    _block = right;
  } else {
    _block = $list.filter(
      right,
      (entry) => { return !(entry[1] instanceof VNull); },
    );
  }
  let seeded = _block;
  return new Attributes(
    (() => {
      let _pipe = left;
      return $list.fold(
        _pipe,
        seeded,
        (acc, entry) => {
          let $ = get(new Attributes(right), entry[0]);
          if ($ instanceof Ok) {
            return acc;
          } else {
            return put(acc, entry);
          }
        },
      );
    })(),
  );
}

/**
 * The attribute changes that restore `base` after you apply `patch`.
 */
export function invert(patch, base) {
  let patch_entries = patch[0];
  let base_entries = base[0];
  let _block;
  let _pipe = base_entries;
  _block = $list.fold(
    _pipe,
    $List$Empty$const,
    (acc, entry) => {
      let $ = get(new Attributes(patch_entries), entry[0]);
      if ($ instanceof Ok) {
        let value = $[0];
        if (!isEqual(value, entry[1])) {
          return put(acc, entry);
        } else {
          return acc;
        }
      } else {
        return acc;
      }
    },
  );
  let restored = _block;
  return new Attributes(
    (() => {
      let _pipe$1 = patch_entries;
      return $list.fold(
        _pipe$1,
        restored,
        (acc, entry) => {
          let $ = get(new Attributes(base_entries), entry[0]);
          if ($ instanceof Ok) {
            return acc;
          } else {
            return put(acc, [entry[0], JsonValue$VNull$const]);
          }
        },
      );
    })(),
  );
}

/**
 * Transform the `other` attributes through `base`. This function uses the
 * Quill priority rules.
 */
export function transform(base, other, priority) {
  if (priority) {
    let entries = other[0];
    return new Attributes(
      (() => {
        let _pipe = entries;
        return $list.fold(
          _pipe,
          $List$Empty$const,
          (acc, entry) => {
            let $ = get(base, entry[0]);
            if ($ instanceof Ok) {
              return acc;
            } else {
              return put(acc, entry);
            }
          },
        );
      })(),
    );
  } else {
    return other;
  }
}

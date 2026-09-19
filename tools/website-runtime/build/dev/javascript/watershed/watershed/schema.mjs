/// <reference types="./schema.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import { Ok, Error, toList, Empty as $Empty, CustomType as $CustomType } from "../gleam.mjs";

class Field extends $CustomType {
  constructor(key, encode, decode) {
    super();
    this.key = key;
    this.encode = encode;
    this.decode = decode;
  }
}

class ChildField extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}

export class Missing extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const FieldError$Missing = (key) => new Missing(key);
export const FieldError$isMissing = (value) => value instanceof Missing;
export const FieldError$Missing$key = (value) => value.key;
export const FieldError$Missing$0 = (value) => value.key;

export class Invalid extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const FieldError$Invalid = (reason) => new Invalid(reason);
export const FieldError$isInvalid = (value) => value instanceof Invalid;
export const FieldError$Invalid$reason = (value) => value.reason;
export const FieldError$Invalid$0 = (value) => value.reason;

export class UnknownKeys extends $CustomType {
  constructor(keys) {
    super();
    this.keys = keys;
  }
}
export const FieldError$UnknownKeys = (keys) => new UnknownKeys(keys);
export const FieldError$isUnknownKeys = (value) => value instanceof UnknownKeys;
export const FieldError$UnknownKeys$keys = (value) => value.keys;
export const FieldError$UnknownKeys$0 = (value) => value.keys;

export class SchemaMismatch extends $CustomType {
  constructor(expected, found) {
    super();
    this.expected = expected;
    this.found = found;
  }
}
export const FieldError$SchemaMismatch = (expected, found) =>
  new SchemaMismatch(expected, found);
export const FieldError$isSchemaMismatch = (value) =>
  value instanceof SchemaMismatch;
export const FieldError$SchemaMismatch$expected = (value) => value.expected;
export const FieldError$SchemaMismatch$0 = (value) => value.expected;
export const FieldError$SchemaMismatch$found = (value) => value.found;
export const FieldError$SchemaMismatch$1 = (value) => value.found;

class ChannelField extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}

export class FieldChange extends $CustomType {
  constructor(value, previous, local) {
    super();
    this.value = value;
    this.previous = previous;
    this.local = local;
  }
}
export const FieldChange$FieldChange = (value, previous, local) =>
  new FieldChange(value, previous, local);
export const FieldChange$isFieldChange = (value) =>
  value instanceof FieldChange;
export const FieldChange$FieldChange$value = (value) => value.value;
export const FieldChange$FieldChange$0 = (value) => value.value;
export const FieldChange$FieldChange$previous = (value) => value.previous;
export const FieldChange$FieldChange$1 = (value) => value.previous;
export const FieldChange$FieldChange$local = (value) => value.local;
export const FieldChange$FieldChange$2 = (value) => value.local;

export class Put extends $CustomType {
  constructor(key, value) {
    super();
    this.key = key;
    this.value = value;
  }
}
export const WriteOperation$Put = (key, value) => new Put(key, value);
export const WriteOperation$isPut = (value) => value instanceof Put;
export const WriteOperation$Put$key = (value) => value.key;
export const WriteOperation$Put$0 = (value) => value.key;
export const WriteOperation$Put$value = (value) => value.value;
export const WriteOperation$Put$1 = (value) => value.value;

export class Delete extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const WriteOperation$Delete = (key) => new Delete(key);
export const WriteOperation$isDelete = (value) => value instanceof Delete;
export const WriteOperation$Delete$key = (value) => value.key;
export const WriteOperation$Delete$0 = (value) => value.key;

export const WriteOperation$key = (value) => value.key;

class Schema extends $CustomType {
  constructor(decode, to_operations, known_keys, version, declared_keys) {
    super();
    this.decode = decode;
    this.to_operations = to_operations;
    this.known_keys = known_keys;
    this.version = version;
    this.declared_keys = declared_keys;
  }
}

class Prop extends $CustomType {
  constructor(key, decoder, fallback, write) {
    super();
    this.key = key;
    this.decoder = decoder;
    this.fallback = fallback;
    this.write = write;
  }
}

/**
 * The reserved key that a `versioned` schema stores its version under. The
 * `sealed` unknown-key check permits it, and a record decoder ignores it.
 */
export const version_key = "__schema";

/**
 * Define a typed field.
 */
export function field(key, encode, decode) {
  return new Field(key, encode, decode);
}

/**
 * Define a typed nested-map field.
 */
export function child_field(key) {
  return new ChildField(key);
}

/**
 * Define a typed channel field. Write the kind in an annotation, or let the
 * inference find it:
 * `let notes: ChannelField(Document, OrSetChannel) = channel_field("notes")`.
 */
export function channel_field(key) {
  return new ChannelField(key);
}

/**
 * The key of the channel field.
 */
export function channel_field_key(field) {
  return field.key;
}

/**
 * The key of the field.
 */
export function field_key(field) {
  return field.key;
}

/**
 * The key of the child field.
 */
export function child_key(field) {
  return field.key;
}

/**
 * Encode a value for storage under `field`.
 */
export function encode_value(field, value) {
  return field.encode(value);
}

/**
 * Decode a stored `Json` value that a read gave for `field`. The function goes
 * through the JSON string form and back, the same as the decode pattern in
 * the rest of watershed. See `channel.gleam`.
 */
export function decode_value(field, stored) {
  let $ = $json.parse($json.to_string(stored), field.decode);
  if ($ instanceof Ok) {
    return $;
  } else {
    let reason = $[0];
    return new Error(new Invalid(reason));
  }
}

/**
 * Decode an optional stored value for `field`, in the form that the event
 * fan-out delivers. An absent value, which is `None`, decodes to `Ok(None)`. A
 * present value decodes to `Ok(Some(_))`, or to `Error(Invalid)` when it does
 * not match the field type.
 */
export function decode_optional(field, stored) {
  if (stored instanceof Some) {
    let json = stored[0];
    let _pipe = decode_value(field, json);
    return $result.map(_pipe, (var0) => { return new Some(var0); });
  } else {
    return new Ok(Option$None$const);
  }
}

/**
 * Define a whole-map schema from a record decoder and a record encoder. The
 * schema is open, so it permits unknown keys, and it has no version. Add
 * `sealed` or `versioned` to change that. The function writes each entry as a
 * `Put` operation. Prefer the `record1` to `record9` builders, which derive
 * both directions from one list of props.
 */
export function schema(decode, to_entries) {
  return new Schema(
    decode,
    (value) => {
      return $list.map(
        to_entries(value),
        (entry) => { return new Put(entry[0], entry[1]); },
      );
    },
    Option$None$const,
    Option$None$const,
    Option$None$const,
  );
}

/**
 * Refuse a read whose map holds a key that is not in `keys`. The reserved
 * version key is always permitted. This function makes the schema a closed
 * set.
 */
export function sealed(schema, keys) {
  return new Schema(
    schema.decode,
    schema.to_operations,
    new Some(keys),
    schema.version,
    schema.declared_keys,
  );
}

/**
 * Seal a record-builder schema to exactly the keys that its props declare.
 * The reserved version key is always permitted. You repeat no key list by
 * hand, so no list can drift out of agreement.
 *
 * The result is `Error(Nil)` for a schema that you built with `schema(...)`,
 * because such a schema does not declare its keys. Use `sealed(keys)` for
 * that schema instead.
 */
export function sealed_known(schema) {
  let $ = schema.declared_keys;
  if ($ instanceof Some) {
    let keys = $[0];
    return new Ok(sealed(schema, keys));
  } else {
    return new Error(undefined);
  }
}

/**
 * Stamp and check an integer schema version. `stamp` writes the version.
 * `read` fails with `SchemaMismatch` when the stored version differs.
 */
export function versioned(schema, version) {
  return new Schema(
    schema.decode,
    schema.to_operations,
    schema.known_keys,
    new Some(version),
    schema.declared_keys,
  );
}

function check_sealed(schema, entries) {
  let $ = schema.known_keys;
  if ($ instanceof Some) {
    let keys = $[0];
    let _block;
    let _pipe = entries;
    let _pipe$1 = $list.map(_pipe, (entry) => { return entry[0]; });
    _block = $list.filter(
      _pipe$1,
      (key) => { return (key !== version_key) && !$list.contains(keys, key); },
    );
    let extra = _block;
    if (extra instanceof $Empty) {
      return new Ok(undefined);
    } else {
      return new Error(new UnknownKeys(extra));
    }
  } else {
    return new Ok(undefined);
  }
}

function check_version(schema, entries) {
  let $ = schema.version;
  if ($ instanceof Some) {
    let expected = $[0];
    let $1 = $list.key_find(entries, version_key);
    if ($1 instanceof Ok) {
      let stored = $1[0];
      let $2 = $json.parse($json.to_string(stored), $decode.int);
      if ($2 instanceof Ok) {
        let found = $2[0];
        if (found === expected) {
          return new Ok(undefined);
        } else {
          let found = $2[0];
          return new Error(new SchemaMismatch(expected, found));
        }
      } else {
        return new Ok(undefined);
      }
    } else {
      return new Ok(undefined);
    }
  } else {
    return new Ok(undefined);
  }
}

/**
 * Decode a record from the `entries` of a map, after the version check and
 * the seal check. The `read` function of the backend calls this function with
 * the current entries of the map.
 */
export function decode_entries(schema, entries) {
  return $result.try$(
    check_version(schema, entries),
    (_) => {
      return $result.try$(
        check_sealed(schema, entries),
        (_) => {
          let _pipe = $json.object(entries);
          let _pipe$1 = $json.to_string(_pipe);
          let _pipe$2 = $json.parse(_pipe$1, schema.decode);
          return $result.map_error(
            _pipe$2,
            (var0) => { return new Invalid(var0); },
          );
        },
      );
    },
  );
}

/**
 * The write operation for each key of `value`. The `write` function of the
 * backend applies each operation separately: a `Put` as a set, and a `Delete`
 * as a delete. The per-key merge thus stays correct.
 */
export function encode_operations(schema, value) {
  return schema.to_operations(value);
}

/**
 * The version key and value to stamp, if the schema has a version. The `stamp`
 * function of the backend writes it one time, at creation, and not on every
 * `write`.
 */
export function stamp_entry(schema) {
  let $ = schema.version;
  if ($ instanceof Some) {
    let version = $[0];
    return new Some([version_key, $json.int(version)]);
  } else {
    return $;
  }
}

/**
 * A required property. The decode fails when the key is absent, and the
 * encode writes a `Put` operation.
 */
export function prop(field, get) {
  return new Prop(
    field.key,
    field.decode,
    Option$None$const,
    (value) => { return new Put(field.key, field.encode(get(value))); },
  );
}

/**
 * An optional property. An absent key decodes as `None`, and so does a stored
 * JSON null, which an old writer or a foreign writer can produce. A value of
 * `None` writes a `Delete` operation, so a read never gives a stale `Some`.
 * See `WriteOperation`.
 */
export function optional_prop(field, get) {
  return new Prop(
    field.key,
    $decode.optional(field.decode),
    new Some(Option$None$const),
    (value) => {
      let $ = get(value);
      if ($ instanceof Some) {
        let inner = $[0];
        return new Put(field.key, field.encode(inner));
      } else {
        return new Delete(field.key);
      }
    },
  );
}

/**
 * Decode one prop and then continue. The builders chain this step with
 * `use`.
 * 
 * @ignore
 */
function prop_step(prop, next) {
  let $ = prop.fallback;
  if ($ instanceof Some) {
    let default$ = $[0];
    return $decode.optional_field(prop.key, default$, prop.decoder, next);
  } else {
    return $decode.field(prop.key, prop.decoder, next);
  }
}

function from_props(decoder, props) {
  return new Schema(
    decoder,
    (value) => { return $list.map(props, (prop) => { return prop[1](value); }); },
    Option$None$const,
    Option$None$const,
    new Some($list.map(props, (prop) => { return prop[0]; })),
  );
}

export function record1(ctor, p1) {
  let decoder = prop_step(p1, (v1) => { return $decode.success(ctor(v1)); });
  return from_props(decoder, toList([[p1.key, p1.write]]));
}

export function record2(ctor, p1, p2) {
  let decoder = prop_step(
    p1,
    (v1) => {
      return prop_step(p2, (v2) => { return $decode.success(ctor(v1, v2)); });
    },
  );
  return from_props(decoder, toList([[p1.key, p1.write], [p2.key, p2.write]]));
}

export function record3(ctor, p1, p2, p3) {
  let decoder = prop_step(
    p1,
    (v1) => {
      return prop_step(
        p2,
        (v2) => {
          return prop_step(
            p3,
            (v3) => { return $decode.success(ctor(v1, v2, v3)); },
          );
        },
      );
    },
  );
  return from_props(
    decoder,
    toList([[p1.key, p1.write], [p2.key, p2.write], [p3.key, p3.write]]),
  );
}

export function record4(ctor, p1, p2, p3, p4) {
  let decoder = prop_step(
    p1,
    (v1) => {
      return prop_step(
        p2,
        (v2) => {
          return prop_step(
            p3,
            (v3) => {
              return prop_step(
                p4,
                (v4) => { return $decode.success(ctor(v1, v2, v3, v4)); },
              );
            },
          );
        },
      );
    },
  );
  return from_props(
    decoder,
    toList([
      [p1.key, p1.write],
      [p2.key, p2.write],
      [p3.key, p3.write],
      [p4.key, p4.write],
    ]),
  );
}

export function record5(ctor, p1, p2, p3, p4, p5) {
  let decoder = prop_step(
    p1,
    (v1) => {
      return prop_step(
        p2,
        (v2) => {
          return prop_step(
            p3,
            (v3) => {
              return prop_step(
                p4,
                (v4) => {
                  return prop_step(
                    p5,
                    (v5) => { return $decode.success(ctor(v1, v2, v3, v4, v5)); },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
  return from_props(
    decoder,
    toList([
      [p1.key, p1.write],
      [p2.key, p2.write],
      [p3.key, p3.write],
      [p4.key, p4.write],
      [p5.key, p5.write],
    ]),
  );
}

export function record6(ctor, p1, p2, p3, p4, p5, p6) {
  let decoder = prop_step(
    p1,
    (v1) => {
      return prop_step(
        p2,
        (v2) => {
          return prop_step(
            p3,
            (v3) => {
              return prop_step(
                p4,
                (v4) => {
                  return prop_step(
                    p5,
                    (v5) => {
                      return prop_step(
                        p6,
                        (v6) => {
                          return $decode.success(ctor(v1, v2, v3, v4, v5, v6));
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
  return from_props(
    decoder,
    toList([
      [p1.key, p1.write],
      [p2.key, p2.write],
      [p3.key, p3.write],
      [p4.key, p4.write],
      [p5.key, p5.write],
      [p6.key, p6.write],
    ]),
  );
}

export function record7(ctor, p1, p2, p3, p4, p5, p6, p7) {
  let decoder = prop_step(
    p1,
    (v1) => {
      return prop_step(
        p2,
        (v2) => {
          return prop_step(
            p3,
            (v3) => {
              return prop_step(
                p4,
                (v4) => {
                  return prop_step(
                    p5,
                    (v5) => {
                      return prop_step(
                        p6,
                        (v6) => {
                          return prop_step(
                            p7,
                            (v7) => {
                              return $decode.success(
                                ctor(v1, v2, v3, v4, v5, v6, v7),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
  return from_props(
    decoder,
    toList([
      [p1.key, p1.write],
      [p2.key, p2.write],
      [p3.key, p3.write],
      [p4.key, p4.write],
      [p5.key, p5.write],
      [p6.key, p6.write],
      [p7.key, p7.write],
    ]),
  );
}

export function record8(ctor, p1, p2, p3, p4, p5, p6, p7, p8) {
  let decoder = prop_step(
    p1,
    (v1) => {
      return prop_step(
        p2,
        (v2) => {
          return prop_step(
            p3,
            (v3) => {
              return prop_step(
                p4,
                (v4) => {
                  return prop_step(
                    p5,
                    (v5) => {
                      return prop_step(
                        p6,
                        (v6) => {
                          return prop_step(
                            p7,
                            (v7) => {
                              return prop_step(
                                p8,
                                (v8) => {
                                  return $decode.success(
                                    ctor(v1, v2, v3, v4, v5, v6, v7, v8),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
  return from_props(
    decoder,
    toList([
      [p1.key, p1.write],
      [p2.key, p2.write],
      [p3.key, p3.write],
      [p4.key, p4.write],
      [p5.key, p5.write],
      [p6.key, p6.write],
      [p7.key, p7.write],
      [p8.key, p8.write],
    ]),
  );
}

export function record9(ctor, p1, p2, p3, p4, p5, p6, p7, p8, p9) {
  let decoder = prop_step(
    p1,
    (v1) => {
      return prop_step(
        p2,
        (v2) => {
          return prop_step(
            p3,
            (v3) => {
              return prop_step(
                p4,
                (v4) => {
                  return prop_step(
                    p5,
                    (v5) => {
                      return prop_step(
                        p6,
                        (v6) => {
                          return prop_step(
                            p7,
                            (v7) => {
                              return prop_step(
                                p8,
                                (v8) => {
                                  return prop_step(
                                    p9,
                                    (v9) => {
                                      return $decode.success(
                                        ctor(v1, v2, v3, v4, v5, v6, v7, v8, v9),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
  return from_props(
    decoder,
    toList([
      [p1.key, p1.write],
      [p2.key, p2.write],
      [p3.key, p3.write],
      [p4.key, p4.write],
      [p5.key, p5.write],
      [p6.key, p6.write],
      [p7.key, p7.write],
      [p8.key, p8.write],
      [p9.key, p9.write],
    ]),
  );
}

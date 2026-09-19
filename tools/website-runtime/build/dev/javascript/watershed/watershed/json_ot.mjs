/// <reference types="./json_ot.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";

export class VNull extends $CustomType {}
export const JsonValue$VNull$const = new VNull();
export const JsonValue$VNull = () => JsonValue$VNull$const;
export const JsonValue$isVNull = (value) => value instanceof VNull;

export class VBool extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const JsonValue$VBool = ($0) => new VBool($0);
export const JsonValue$isVBool = (value) => value instanceof VBool;
export const JsonValue$VBool$0 = (value) => value[0];

export class VNumber extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const JsonValue$VNumber = ($0) => new VNumber($0);
export const JsonValue$isVNumber = (value) => value instanceof VNumber;
export const JsonValue$VNumber$0 = (value) => value[0];

export class VString extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const JsonValue$VString = ($0) => new VString($0);
export const JsonValue$isVString = (value) => value instanceof VString;
export const JsonValue$VString$0 = (value) => value[0];

export class VArray extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const JsonValue$VArray = ($0) => new VArray($0);
export const JsonValue$isVArray = (value) => value instanceof VArray;
export const JsonValue$VArray$0 = (value) => value[0];

export class VObject extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const JsonValue$VObject = ($0) => new VObject($0);
export const JsonValue$isVObject = (value) => value instanceof VObject;
export const JsonValue$VObject$0 = (value) => value[0];

export class NInt extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Number$NInt = ($0) => new NInt($0);
export const Number$isNInt = (value) => value instanceof NInt;
export const Number$NInt$0 = (value) => value[0];

export class NFloat extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Number$NFloat = ($0) => new NFloat($0);
export const Number$isNFloat = (value) => value instanceof NFloat;
export const Number$NFloat$0 = (value) => value[0];

export class Key extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const PathKey$Key = ($0) => new Key($0);
export const PathKey$isKey = (value) => value instanceof Key;
export const PathKey$Key$0 = (value) => value[0];

export class Index extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const PathKey$Index = ($0) => new Index($0);
export const PathKey$isIndex = (value) => value instanceof Index;
export const PathKey$Index$0 = (value) => value[0];

export class Component extends $CustomType {
  constructor(path, object_insert, object_delete, list_insert, list_delete, list_move, na, subtype) {
    super();
    this.path = path;
    this.object_insert = object_insert;
    this.object_delete = object_delete;
    this.list_insert = list_insert;
    this.list_delete = list_delete;
    this.list_move = list_move;
    this.na = na;
    this.subtype = subtype;
  }
}
export const Component$Component = (path, object_insert, object_delete, list_insert, list_delete, list_move, na, subtype) =>
  new Component(path,
  object_insert,
  object_delete,
  list_insert,
  list_delete,
  list_move,
  na,
  subtype);
export const Component$isComponent = (value) => value instanceof Component;
export const Component$Component$path = (value) => value.path;
export const Component$Component$0 = (value) => value.path;
export const Component$Component$object_insert = (value) => value.object_insert;
export const Component$Component$1 = (value) => value.object_insert;
export const Component$Component$object_delete = (value) => value.object_delete;
export const Component$Component$2 = (value) => value.object_delete;
export const Component$Component$list_insert = (value) => value.list_insert;
export const Component$Component$3 = (value) => value.list_insert;
export const Component$Component$list_delete = (value) => value.list_delete;
export const Component$Component$4 = (value) => value.list_delete;
export const Component$Component$list_move = (value) => value.list_move;
export const Component$Component$5 = (value) => value.list_move;
export const Component$Component$na = (value) => value.na;
export const Component$Component$6 = (value) => value.na;
export const Component$Component$subtype = (value) => value.subtype;
export const Component$Component$7 = (value) => value.subtype;

export class Lft extends $CustomType {}
export const Side$Lft$const = new Lft();
export const Side$Lft = () => Side$Lft$const;
export const Side$isLft = (value) => value instanceof Lft;

export class Rgt extends $CustomType {}
export const Side$Rgt$const = new Rgt();
export const Side$Rgt = () => Side$Rgt$const;
export const Side$isRgt = (value) => value instanceof Rgt;

export class BadPath extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const OtError$BadPath = (detail) => new BadPath(detail);
export const OtError$isBadPath = (value) => value instanceof BadPath;
export const OtError$BadPath$detail = (value) => value.detail;
export const OtError$BadPath$0 = (value) => value.detail;

export class BadValue extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const OtError$BadValue = (detail) => new BadValue(detail);
export const OtError$isBadValue = (value) => value instanceof BadValue;
export const OtError$BadValue$detail = (value) => value.detail;
export const OtError$BadValue$0 = (value) => value.detail;

export class UnknownSubtype extends $CustomType {
  constructor(name) {
    super();
    this.name = name;
  }
}
export const OtError$UnknownSubtype = (name) => new UnknownSubtype(name);
export const OtError$isUnknownSubtype = (value) =>
  value instanceof UnknownSubtype;
export const OtError$UnknownSubtype$name = (value) => value.name;
export const OtError$UnknownSubtype$0 = (value) => value.name;

class MergeReplace extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class MergeDropBoth extends $CustomType {}
const Merge$MergeDropBoth$const = new MergeDropBoth();

class KeepDest extends $CustomType {}
const Merge$KeepDest$const = new KeepDest();

class NoMerge extends $CustomType {}
const Merge$NoMerge$const = new NoMerge();

class TextInsert extends $CustomType {
  constructor(p, s) {
    super();
    this.p = p;
    this.s = s;
  }
}

class TextDelete extends $CustomType {
  constructor(p, s) {
    super();
    this.p = p;
    this.s = s;
  }
}

function empty(path) {
  return new Component(
    path,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
  );
}

export function object_insert(path, value) {
  let _record = empty(path);
  return new Component(
    _record.path,
    new Some(value),
    _record.object_delete,
    _record.list_insert,
    _record.list_delete,
    _record.list_move,
    _record.na,
    _record.subtype,
  );
}

export function object_delete(path, value) {
  let _record = empty(path);
  return new Component(
    _record.path,
    _record.object_insert,
    new Some(value),
    _record.list_insert,
    _record.list_delete,
    _record.list_move,
    _record.na,
    _record.subtype,
  );
}

export function object_replace(path, old, new$) {
  let _record = empty(path);
  return new Component(
    _record.path,
    new Some(new$),
    new Some(old),
    _record.list_insert,
    _record.list_delete,
    _record.list_move,
    _record.na,
    _record.subtype,
  );
}

export function list_insert(path, value) {
  let _record = empty(path);
  return new Component(
    _record.path,
    _record.object_insert,
    _record.object_delete,
    new Some(value),
    _record.list_delete,
    _record.list_move,
    _record.na,
    _record.subtype,
  );
}

export function list_delete(path, value) {
  let _record = empty(path);
  return new Component(
    _record.path,
    _record.object_insert,
    _record.object_delete,
    _record.list_insert,
    new Some(value),
    _record.list_move,
    _record.na,
    _record.subtype,
  );
}

export function list_replace(path, old, new$) {
  let _record = empty(path);
  return new Component(
    _record.path,
    _record.object_insert,
    _record.object_delete,
    new Some(new$),
    new Some(old),
    _record.list_move,
    _record.na,
    _record.subtype,
  );
}

export function list_move(path, to) {
  let _record = empty(path);
  return new Component(
    _record.path,
    _record.object_insert,
    _record.object_delete,
    _record.list_insert,
    _record.list_delete,
    new Some(to),
    _record.na,
    _record.subtype,
  );
}

export function number_add(path, delta) {
  let _record = empty(path);
  return new Component(
    _record.path,
    _record.object_insert,
    _record.object_delete,
    _record.list_insert,
    _record.list_delete,
    _record.list_move,
    new Some(delta),
    _record.subtype,
  );
}

export function subtype_component(path, name, operation) {
  let _record = empty(path);
  return new Component(
    _record.path,
    _record.object_insert,
    _record.object_delete,
    _record.list_insert,
    _record.list_delete,
    _record.list_move,
    _record.na,
    new Some([name, operation]),
  );
}

function insert_sorted(members, key, value) {
  if (members instanceof $Empty) {
    return toList([[key, value]]);
  } else {
    let first = members.head;
    let rest = members.tail;
    let $ = $string.compare(key, first[0]);
    if ($ instanceof $order.Lt) {
      return listPrepend([key, value], listPrepend(first, rest));
    } else {
      return listPrepend(first, insert_sorted(rest, key, value));
    }
  }
}

function object_set(members, key, value) {
  let without = $list.filter(members, (pair) => { return pair[0] !== key; });
  return insert_sorted(without, key, value);
}

function object_remove(members, key) {
  return $list.filter(members, (pair) => { return pair[0] !== key; });
}

function num_add(a, b) {
  if (a instanceof NInt) {
    if (b instanceof NInt) {
      let x = a[0];
      let y = b[0];
      return new NInt(x + y);
    } else {
      let x = a[0];
      let y = b[0];
      return new NFloat($int.to_float(x) + y);
    }
  } else if (b instanceof NInt) {
    let x = a[0];
    let y = b[0];
    return new NFloat(x + $int.to_float(y));
  } else {
    let x = a[0];
    let y = b[0];
    return new NFloat(x + y);
  }
}

function num_negate(a) {
  if (a instanceof NInt) {
    let x = a[0];
    return new NInt(- x);
  } else {
    let x = a[0];
    return new NFloat(0.0 - x);
  }
}

/**
 * Insert `s2` into `s1` at `position`.
 * 
 * @ignore
 */
function string_inject(s1, position, s2) {
  return ($string.slice(s1, 0, position) + s2) + $string.drop_start(
    s1,
    position,
  );
}

function text0_parse_component(component) {
  if (component instanceof VNull) {
    return new Error(new BadValue("text0 component must be an object"));
  } else if (component instanceof VBool) {
    return new Error(new BadValue("text0 component must be an object"));
  } else if (component instanceof VNumber) {
    return new Error(new BadValue("text0 component must be an object"));
  } else if (component instanceof VString) {
    return new Error(new BadValue("text0 component must be an object"));
  } else if (component instanceof VArray) {
    return new Error(new BadValue("text0 component must be an object"));
  } else {
    let members = component[0];
    let _block;
    let $ = $list.key_find(members, "p");
    if ($ instanceof Ok) {
      let $1 = $[0];
      if ($1 instanceof VNumber) {
        let $2 = $1[0];
        if ($2 instanceof NInt) {
          let n = $2[0];
          _block = new Ok(n);
        } else {
          _block = new Error(
            new BadValue("text0 component missing integer position"),
          );
        }
      } else {
        _block = new Error(
          new BadValue("text0 component missing integer position"),
        );
      }
    } else {
      _block = new Error(
        new BadValue("text0 component missing integer position"),
      );
    }
    let position = _block;
    return $result.try$(
      position,
      (p) => {
        let $1 = p < 0;
        if ($1) {
          return new Error(new BadValue("text0 position cannot be negative"));
        } else {
          let $2 = $list.key_find(members, "i");
          let $3 = $list.key_find(members, "d");
          if ($2 instanceof Ok) {
            if ($3 instanceof Error) {
              let $4 = $2[0];
              if ($4 instanceof VString) {
                let s = $4[0];
                return new Ok(new TextInsert(p, s));
              } else {
                return new Error(
                  new BadValue("text0 component needs an i or d field"),
                );
              }
            } else {
              return new Error(
                new BadValue("text0 component needs an i or d field"),
              );
            }
          } else if ($3 instanceof Ok) {
            let $4 = $3[0];
            if ($4 instanceof VString) {
              let s = $4[0];
              return new Ok(new TextDelete(p, s));
            } else {
              return new Error(
                new BadValue("text0 component needs an i or d field"),
              );
            }
          } else {
            return new Error(
              new BadValue("text0 component needs an i or d field"),
            );
          }
        }
      },
    );
  }
}

function text0_parse_operation(operation) {
  if (operation instanceof VNull) {
    return new Error(new BadValue("text0 op must be an array"));
  } else if (operation instanceof VBool) {
    return new Error(new BadValue("text0 op must be an array"));
  } else if (operation instanceof VNumber) {
    return new Error(new BadValue("text0 op must be an array"));
  } else if (operation instanceof VString) {
    return new Error(new BadValue("text0 op must be an array"));
  } else if (operation instanceof VArray) {
    let items = operation[0];
    return $list.try_map(items, text0_parse_component);
  } else {
    return new Error(new BadValue("text0 op must be an array"));
  }
}

function text0_apply(value, sub_operation) {
  if (value instanceof VNull) {
    return new Error(new BadValue("text0 op can only apply to a string"));
  } else if (value instanceof VBool) {
    return new Error(new BadValue("text0 op can only apply to a string"));
  } else if (value instanceof VNumber) {
    return new Error(new BadValue("text0 op can only apply to a string"));
  } else if (value instanceof VString) {
    let s = value[0];
    return $result.try$(
      text0_parse_operation(sub_operation),
      (operation) => {
        return $result.try$(
          $list.try_fold(
            operation,
            s,
            (snapshot, component) => {
              if (component instanceof TextInsert) {
                let p = component.p;
                let i = component.s;
                return new Ok(string_inject(snapshot, p, i));
              } else {
                let p = component.p;
                let d = component.s;
                let deleted = $string.slice(snapshot, p, $string.length(d));
                let $ = deleted === d;
                if ($) {
                  return new Ok(
                    $string.slice(snapshot, 0, p) + $string.drop_start(
                      snapshot,
                      p + $string.length(d),
                    ),
                  );
                } else {
                  return new Error(
                    new BadValue(
                      "text0 delete does not match the document text",
                    ),
                  );
                }
              }
            },
          ),
          (result) => { return new Ok(new VString(result)); },
        );
      },
    );
  } else if (value instanceof VArray) {
    return new Error(new BadValue("text0 op can only apply to a string"));
  } else {
    return new Error(new BadValue("text0 op can only apply to a string"));
  }
}

/**
 * Apply a subtype operation to a value. Rung 4 (`text0`) completes this
 * function. Before that, an unknown subtype gives an error. It does not do
 * nothing.
 */
export function apply_subtype(name, value, sub_operation) {
  if (name === "text0") {
    return text0_apply(value, sub_operation);
  } else {
    return new Error(new UnknownSubtype(name));
  }
}

function list_set(items, index, value) {
  return $list.index_map(
    items,
    (item, i) => {
      let $ = i === index;
      if ($) {
        return value;
      } else {
        return item;
      }
    },
  );
}

/**
 * The element at `index`. `gleam/list` has no indexed read, so this module
 * walks the list. The result is `Error(Nil)` for a negative index and for an
 * index past the end of the list.
 * 
 * @ignore
 */
function element_at(loop$items, loop$index) {
  while (true) {
    let items = loop$items;
    let index = loop$index;
    if (index < 0) {
      return new Error(undefined);
    } else if (items instanceof $Empty) {
      return new Error(undefined);
    } else if (index === 0) {
      let first = items.head;
      return new Ok(first);
    } else {
      let rest = items.tail;
      loop$items = rest;
      loop$index = index - 1;
    }
  }
}

function edit_element_value(items, index, f) {
  let $ = element_at(items, index);
  if ($ instanceof Ok) {
    let value = $[0];
    let _pipe = f(value);
    return $result.map(
      _pipe,
      (updated) => { return new VArray(list_set(items, index, updated)); },
    );
  } else {
    return new Error(new BadPath("list index out of range"));
  }
}

function list_insert_at(items, index, value) {
  let $ = $list.split(items, index);
  let before = $[0];
  let after = $[1];
  return $list.append(before, listPrepend(value, after));
}

function list_delete_at(items, index) {
  let $ = element_at(items, index);
  if ($ instanceof Ok) {
    let $1 = $list.split(items, index);
    let before = $1[0];
    let after = $1[1];
    if (after instanceof $Empty) {
      return new Error(undefined);
    } else {
      let rest = after.tail;
      return new Ok($list.append(before, rest));
    }
  } else {
    return new Error(undefined);
  }
}

function list_move_element(items, from, to) {
  let $ = from === to;
  if ($) {
    return new Ok(items);
  } else {
    let $1 = element_at(items, from);
    if ($1 instanceof Ok) {
      let element = $1[0];
      let $2 = list_delete_at(items, from);
      if ($2 instanceof Ok) {
        let without = $2[0];
        return new Ok(list_insert_at(without, to, element));
      } else {
        return new Error(undefined);
      }
    } else {
      return new Error(undefined);
    }
  }
}

function edit_list_element(container, index, c) {
  if (container instanceof VNull) {
    return new Error(new BadPath("expected array for index"));
  } else if (container instanceof VBool) {
    return new Error(new BadPath("expected array for index"));
  } else if (container instanceof VNumber) {
    return new Error(new BadPath("expected array for index"));
  } else if (container instanceof VString) {
    return new Error(new BadPath("expected array for index"));
  } else if (container instanceof VArray) {
    let items = container[0];
    let $ = c.list_insert;
    if ($ instanceof Some) {
      let $1 = c.list_delete;
      if ($1 instanceof Some) {
        let value = $[0];
        let $2 = element_at(items, index);
        if ($2 instanceof Ok) {
          return new Ok(new VArray(list_set(items, index, value)));
        } else {
          return new Error(new BadPath("list replace out of range"));
        }
      } else {
        let value = $[0];
        return new Ok(new VArray(list_insert_at(items, index, value)));
      }
    } else {
      let $1 = c.list_delete;
      if ($1 instanceof Some) {
        let $2 = list_delete_at(items, index);
        if ($2 instanceof Ok) {
          let updated = $2[0];
          return new Ok(new VArray(updated));
        } else {
          return new Error(new BadPath("list delete out of range"));
        }
      } else {
        let $2 = c.list_move;
        if ($2 instanceof Some) {
          let to = $2[0];
          let $3 = list_move_element(items, index, to);
          if ($3 instanceof Ok) {
            let updated = $3[0];
            return new Ok(new VArray(updated));
          } else {
            return new Error(new BadPath("list move out of range"));
          }
        } else {
          let $3 = c.na;
          if ($3 instanceof Some) {
            let delta = $3[0];
            return edit_element_value(
              items,
              index,
              (v) => {
                if (v instanceof VNull) {
                  return new Error(new BadValue("na target is not a number"));
                } else if (v instanceof VBool) {
                  return new Error(new BadValue("na target is not a number"));
                } else if (v instanceof VNumber) {
                  let n = v[0];
                  return new Ok(new VNumber(num_add(n, delta)));
                } else if (v instanceof VString) {
                  return new Error(new BadValue("na target is not a number"));
                } else if (v instanceof VArray) {
                  return new Error(new BadValue("na target is not a number"));
                } else {
                  return new Error(new BadValue("na target is not a number"));
                }
              },
            );
          } else {
            let $4 = c.subtype;
            if ($4 instanceof Some) {
              let name = $4[0][0];
              let sub_operation = $4[0][1];
              return edit_element_value(
                items,
                index,
                (v) => { return apply_subtype(name, v, sub_operation); },
              );
            } else {
              return new Error(new BadValue("invalid list edit"));
            }
          }
        }
      }
    }
  } else {
    return new Error(new BadPath("expected array for index"));
  }
}

function edit_member_value(members, key, f) {
  let $ = $list.key_find(members, key);
  if ($ instanceof Ok) {
    let value = $[0];
    let _pipe = f(value);
    return $result.map(
      _pipe,
      (updated) => { return new VObject(object_set(members, key, updated)); },
    );
  } else {
    return new Error(new BadPath("object key not found: " + key));
  }
}

function edit_object_member(container, key, c) {
  if (container instanceof VNull) {
    return new Error(new BadPath("expected object for key " + key));
  } else if (container instanceof VBool) {
    return new Error(new BadPath("expected object for key " + key));
  } else if (container instanceof VNumber) {
    return new Error(new BadPath("expected object for key " + key));
  } else if (container instanceof VString) {
    return new Error(new BadPath("expected object for key " + key));
  } else if (container instanceof VArray) {
    return new Error(new BadPath("expected object for key " + key));
  } else {
    let members = container[0];
    let $ = c.object_insert;
    if ($ instanceof Some) {
      let value = $[0];
      return new Ok(new VObject(object_set(members, key, value)));
    } else {
      let $1 = c.object_delete;
      if ($1 instanceof Some) {
        return new Ok(new VObject(object_remove(members, key)));
      } else {
        let $2 = c.na;
        if ($2 instanceof Some) {
          let delta = $2[0];
          return edit_member_value(
            members,
            key,
            (v) => {
              if (v instanceof VNull) {
                return new Error(new BadValue("na target is not a number"));
              } else if (v instanceof VBool) {
                return new Error(new BadValue("na target is not a number"));
              } else if (v instanceof VNumber) {
                let n = v[0];
                return new Ok(new VNumber(num_add(n, delta)));
              } else if (v instanceof VString) {
                return new Error(new BadValue("na target is not a number"));
              } else if (v instanceof VArray) {
                return new Error(new BadValue("na target is not a number"));
              } else {
                return new Error(new BadValue("na target is not a number"));
              }
            },
          );
        } else {
          let $3 = c.subtype;
          if ($3 instanceof Some) {
            let name = $3[0][0];
            let sub_operation = $3[0][1];
            return edit_member_value(
              members,
              key,
              (v) => { return apply_subtype(name, v, sub_operation); },
            );
          } else {
            return new Error(new BadValue("invalid object edit at key " + key));
          }
        }
      }
    }
  }
}

/**
 * Apply an edit at `key` in `container`, which is the parent of the edit.
 * 
 * @ignore
 */
function edit_in_container(container, key, c) {
  if (key instanceof Key) {
    let member_key = key[0];
    return edit_object_member(container, member_key, c);
  } else {
    let index = key[0];
    return edit_list_element(container, index, c);
  }
}

/**
 * A functional update. Follow `path` into `document`, and replace the
 * sub-value at the end of that path with `f(sub)`.
 * 
 * @ignore
 */
function update_at(document, path, f) {
  if (path instanceof $Empty) {
    return f(document);
  } else {
    let $ = path.head;
    if ($ instanceof Key) {
      let rest = path.tail;
      let key = $[0];
      if (document instanceof VNull) {
        return new Error(new BadPath("expected object at path step " + key));
      } else if (document instanceof VBool) {
        return new Error(new BadPath("expected object at path step " + key));
      } else if (document instanceof VNumber) {
        return new Error(new BadPath("expected object at path step " + key));
      } else if (document instanceof VString) {
        return new Error(new BadPath("expected object at path step " + key));
      } else if (document instanceof VArray) {
        return new Error(new BadPath("expected object at path step " + key));
      } else {
        let members = document[0];
        let $1 = $list.key_find(members, key);
        if ($1 instanceof Ok) {
          let child = $1[0];
          let _pipe = update_at(child, rest, f);
          return $result.map(
            _pipe,
            (updated) => {
              return new VObject(object_set(members, key, updated));
            },
          );
        } else {
          return new Error(new BadPath("object key not found: " + key));
        }
      }
    } else {
      let rest = path.tail;
      let index = $[0];
      if (document instanceof VNull) {
        return new Error(
          new BadPath("expected array at path step " + $int.to_string(index)),
        );
      } else if (document instanceof VBool) {
        return new Error(
          new BadPath("expected array at path step " + $int.to_string(index)),
        );
      } else if (document instanceof VNumber) {
        return new Error(
          new BadPath("expected array at path step " + $int.to_string(index)),
        );
      } else if (document instanceof VString) {
        return new Error(
          new BadPath("expected array at path step " + $int.to_string(index)),
        );
      } else if (document instanceof VArray) {
        let items = document[0];
        let $1 = element_at(items, index);
        if ($1 instanceof Ok) {
          let child = $1[0];
          let _pipe = update_at(child, rest, f);
          return $result.map(
            _pipe,
            (updated) => { return new VArray(list_set(items, index, updated)); },
          );
        } else {
          return new Error(
            new BadPath("list index out of range: " + $int.to_string(index)),
          );
        }
      } else {
        return new Error(
          new BadPath("expected array at path step " + $int.to_string(index)),
        );
      }
    }
  }
}

/**
 * Apply an edit whose path is empty. Such an edit targets the root of the
 * document.
 * 
 * @ignore
 */
function edit_root(document, c) {
  let $ = c.object_insert;
  if ($ instanceof Some) {
    let value = $[0];
    return new Ok(value);
  } else {
    let $1 = c.na;
    if ($1 instanceof Some) {
      let delta = $1[0];
      if (document instanceof VNull) {
        return new Error(new BadValue("na target is not a number"));
      } else if (document instanceof VBool) {
        return new Error(new BadValue("na target is not a number"));
      } else if (document instanceof VNumber) {
        let n = document[0];
        return new Ok(new VNumber(num_add(n, delta)));
      } else if (document instanceof VString) {
        return new Error(new BadValue("na target is not a number"));
      } else if (document instanceof VArray) {
        return new Error(new BadValue("na target is not a number"));
      } else {
        return new Error(new BadValue("na target is not a number"));
      }
    } else {
      let $2 = c.subtype;
      if ($2 instanceof Some) {
        let name = $2[0][0];
        let sub_operation = $2[0][1];
        return apply_subtype(name, document, sub_operation);
      } else {
        let $3 = c.object_delete;
        if ($3 instanceof Some) {
          return new Ok(JsonValue$VNull$const);
        } else {
          return new Error(
            new BadValue("invalid or missing instruction at root"),
          );
        }
      }
    }
  }
}

/**
 * Split the last key from a path. The result is `Error(Nil)` for an empty
 * path, because an empty path has no last key.
 * 
 * @ignore
 */
function split_last(path) {
  let $ = $list.reverse(path);
  if ($ instanceof $Empty) {
    return new Error(undefined);
  } else {
    let last = $.head;
    let reversed_init = $.tail;
    return new Ok([$list.reverse(reversed_init), last]);
  }
}

function apply_component(document, component) {
  let $ = split_last(component.path);
  if ($ instanceof Ok) {
    let parent_path = $[0][0];
    let last = $[0][1];
    return update_at(
      document,
      parent_path,
      (container) => { return edit_in_container(container, last, component); },
    );
  } else {
    return edit_root(document, component);
  }
}

/**
 * Apply a full operation to a document, one component at a time. This is the
 * `apply` function of json0.
 */
export function apply(document, operation) {
  return $list.try_fold(operation, document, apply_component);
}

/**
 * The path length of a component, adjusted the same way as in json0. An `na`
 * operation and a subtype operation both reach one step deeper than their
 * explicit path.
 * 
 * @ignore
 */
function adjusted_length(c) {
  let _block;
  let $ = c.na;
  let $1 = c.subtype;
  if ($ instanceof None && $1 instanceof None) {
    _block = 0;
  } else {
    _block = 1;
  }
  let extra = _block;
  return $list.length(c.path) + extra;
}

/**
 * The path key at `index`. The result is `Error(Nil)` for a negative index
 * and for an index past the end of the path.
 * 
 * @ignore
 */
function path_key_at(path, index) {
  return element_at(path, index);
}

function common_loop(
  loop$a_path,
  loop$b_path,
  loop$index,
  loop$a_length,
  loop$b_length
) {
  while (true) {
    let a_path = loop$a_path;
    let b_path = loop$b_path;
    let index = loop$index;
    let a_length = loop$a_length;
    let b_length = loop$b_length;
    let $ = index >= a_length;
    if ($) {
      return new Ok(a_length);
    } else {
      let $1 = index >= b_length;
      if ($1) {
        return new Error(undefined);
      } else {
        let $2 = isEqual(path_key_at(a_path, index), path_key_at(b_path, index));
        if ($2) {
          loop$a_path = a_path;
          loop$b_path = b_path;
          loop$index = index + 1;
          loop$a_length = a_length;
          loop$b_length = b_length;
        } else {
          return new Error(undefined);
        }
      }
    }
  }
}

/**
 * The `commonLengthForOps(a, b)` function of json0. The result is the length
 * of the shared operand prefix, or `Error(Nil)`, which is `null` in json0.
 * `Ok(-1)` is the case where `a` reaches the root.
 * 
 * @ignore
 */
function common_length(a, b) {
  let a_length = adjusted_length(a);
  let b_length = adjusted_length(b);
  let $ = a_length === 0;
  if ($) {
    return new Ok(-1);
  } else {
    let $1 = b_length === 0;
    if ($1) {
      return new Error(undefined);
    } else {
      return common_loop(a.path, b.path, 0, a_length - 1, b_length - 1);
    }
  }
}

/**
 * The numeric index value at position `i`. The list branches use this
 * function only. It returns a sentinel value for a position that is not an
 * index or is out of range. Those branches never read that sentinel.
 * 
 * @ignore
 */
function index_at(path, i) {
  let $ = path_key_at(path, i);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Key) {
      return -999_999;
    } else {
      let n = $1[0];
      return n;
    }
  } else {
    return -999_999;
  }
}

function map_path_at(path, i, f) {
  return $list.index_map(
    path,
    (pk, j) => {
      let $ = j === i;
      if ($) {
        return f(pk);
      } else {
        return pk;
      }
    },
  );
}

function bump_index_at(path, i, delta) {
  return map_path_at(
    path,
    i,
    (pk) => {
      if (pk instanceof Key) {
        return pk;
      } else {
        let n = pk[0];
        return new Index(n + delta);
      }
    },
  );
}

function set_index_at(path, i, value) {
  return map_path_at(path, i, (_) => { return new Index(value); });
}

function last_index_of(path) {
  let $ = $list.last(path);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Key) {
      return new Error(undefined);
    } else {
      let n = $1[0];
      return new Ok(n);
    }
  } else {
    return new Error(undefined);
  }
}

function merge_pair(last, c) {
  let $ = c.na;
  if ($ instanceof Some) {
    let $1 = last.na;
    if ($1 instanceof Some) {
      let b = $[0];
      let a = $1[0];
      return new MergeReplace(number_add(last.path, num_add(a, b)));
    } else {
      let $2 = c.list_insert;
      if ($2 instanceof None) {
        let $3 = c.list_delete;
        if ($3 instanceof Some) {
          let $4 = last.list_insert;
          if ($4 instanceof Some) {
            let component_delete = $3[0];
            let last_value = $4[0];
            if (isEqual(component_delete, last_value)) {
              let $5 = last.list_delete;
              if ($5 instanceof Some) {
                return new MergeReplace(
                  new Component(
                    last.path,
                    last.object_insert,
                    last.object_delete,
                    Option$None$const,
                    last.list_delete,
                    last.list_move,
                    last.na,
                    last.subtype,
                  ),
                );
              } else {
                return Merge$MergeDropBoth$const;
              }
            } else {
              let $5 = c.object_delete;
              if ($5 instanceof Some) {
                let $6 = last.object_insert;
                if ($6 instanceof Some) {
                  let $7 = c.object_insert;
                  let $8 = last.object_delete;
                  if ($7 instanceof Some) {
                    let component_insert_value = $7[0];
                    return new MergeReplace(
                      new Component(
                        last.path,
                        new Some(component_insert_value),
                        last.object_delete,
                        last.list_insert,
                        last.list_delete,
                        last.list_move,
                        last.na,
                        last.subtype,
                      ),
                    );
                  } else if ($8 instanceof Some) {
                    return new MergeReplace(
                      new Component(
                        last.path,
                        Option$None$const,
                        last.object_delete,
                        last.list_insert,
                        last.list_delete,
                        last.list_move,
                        last.na,
                        last.subtype,
                      ),
                    );
                  } else {
                    return Merge$MergeDropBoth$const;
                  }
                } else {
                  let $7 = c.list_move;
                  if ($7 instanceof Some) {
                    let target = $7[0];
                    let $8 = isEqual(last_index_of(c.path), new Ok(target));
                    if ($8) {
                      return Merge$KeepDest$const;
                    } else {
                      return Merge$NoMerge$const;
                    }
                  } else {
                    return Merge$NoMerge$const;
                  }
                }
              } else {
                let $6 = c.object_insert;
                if ($6 instanceof Some) {
                  let $7 = last.object_insert;
                  if ($7 instanceof None) {
                    let $8 = last.object_delete;
                    if ($8 instanceof Some) {
                      let component_insert_value = $6[0];
                      return new MergeReplace(
                        new Component(
                          last.path,
                          new Some(component_insert_value),
                          last.object_delete,
                          last.list_insert,
                          last.list_delete,
                          last.list_move,
                          last.na,
                          last.subtype,
                        ),
                      );
                    } else {
                      let $9 = c.list_move;
                      if ($9 instanceof Some) {
                        let target = $9[0];
                        let $10 = isEqual(last_index_of(c.path), new Ok(target));
                        if ($10) {
                          return Merge$KeepDest$const;
                        } else {
                          return Merge$NoMerge$const;
                        }
                      } else {
                        return Merge$NoMerge$const;
                      }
                    }
                  } else {
                    let $8 = c.list_move;
                    if ($8 instanceof Some) {
                      let target = $8[0];
                      let $9 = isEqual(last_index_of(c.path), new Ok(target));
                      if ($9) {
                        return Merge$KeepDest$const;
                      } else {
                        return Merge$NoMerge$const;
                      }
                    } else {
                      return Merge$NoMerge$const;
                    }
                  }
                } else {
                  let $7 = c.list_move;
                  if ($7 instanceof Some) {
                    let target = $7[0];
                    let $8 = isEqual(last_index_of(c.path), new Ok(target));
                    if ($8) {
                      return Merge$KeepDest$const;
                    } else {
                      return Merge$NoMerge$const;
                    }
                  } else {
                    return Merge$NoMerge$const;
                  }
                }
              }
            }
          } else {
            let $5 = c.object_delete;
            if ($5 instanceof Some) {
              let $6 = last.object_insert;
              if ($6 instanceof Some) {
                let $7 = c.object_insert;
                let $8 = last.object_delete;
                if ($7 instanceof Some) {
                  let component_insert_value = $7[0];
                  return new MergeReplace(
                    new Component(
                      last.path,
                      new Some(component_insert_value),
                      last.object_delete,
                      last.list_insert,
                      last.list_delete,
                      last.list_move,
                      last.na,
                      last.subtype,
                    ),
                  );
                } else if ($8 instanceof Some) {
                  return new MergeReplace(
                    new Component(
                      last.path,
                      Option$None$const,
                      last.object_delete,
                      last.list_insert,
                      last.list_delete,
                      last.list_move,
                      last.na,
                      last.subtype,
                    ),
                  );
                } else {
                  return Merge$MergeDropBoth$const;
                }
              } else {
                let $7 = c.list_move;
                if ($7 instanceof Some) {
                  let target = $7[0];
                  let $8 = isEqual(last_index_of(c.path), new Ok(target));
                  if ($8) {
                    return Merge$KeepDest$const;
                  } else {
                    return Merge$NoMerge$const;
                  }
                } else {
                  return Merge$NoMerge$const;
                }
              }
            } else {
              let $6 = c.object_insert;
              if ($6 instanceof Some) {
                let $7 = last.object_insert;
                if ($7 instanceof None) {
                  let $8 = last.object_delete;
                  if ($8 instanceof Some) {
                    let component_insert_value = $6[0];
                    return new MergeReplace(
                      new Component(
                        last.path,
                        new Some(component_insert_value),
                        last.object_delete,
                        last.list_insert,
                        last.list_delete,
                        last.list_move,
                        last.na,
                        last.subtype,
                      ),
                    );
                  } else {
                    let $9 = c.list_move;
                    if ($9 instanceof Some) {
                      let target = $9[0];
                      let $10 = isEqual(last_index_of(c.path), new Ok(target));
                      if ($10) {
                        return Merge$KeepDest$const;
                      } else {
                        return Merge$NoMerge$const;
                      }
                    } else {
                      return Merge$NoMerge$const;
                    }
                  }
                } else {
                  let $8 = c.list_move;
                  if ($8 instanceof Some) {
                    let target = $8[0];
                    let $9 = isEqual(last_index_of(c.path), new Ok(target));
                    if ($9) {
                      return Merge$KeepDest$const;
                    } else {
                      return Merge$NoMerge$const;
                    }
                  } else {
                    return Merge$NoMerge$const;
                  }
                }
              } else {
                let $7 = c.list_move;
                if ($7 instanceof Some) {
                  let target = $7[0];
                  let $8 = isEqual(last_index_of(c.path), new Ok(target));
                  if ($8) {
                    return Merge$KeepDest$const;
                  } else {
                    return Merge$NoMerge$const;
                  }
                } else {
                  return Merge$NoMerge$const;
                }
              }
            }
          }
        } else {
          let $4 = c.object_delete;
          if ($4 instanceof Some) {
            let $5 = last.object_insert;
            if ($5 instanceof Some) {
              let $6 = c.object_insert;
              let $7 = last.object_delete;
              if ($6 instanceof Some) {
                let component_insert_value = $6[0];
                return new MergeReplace(
                  new Component(
                    last.path,
                    new Some(component_insert_value),
                    last.object_delete,
                    last.list_insert,
                    last.list_delete,
                    last.list_move,
                    last.na,
                    last.subtype,
                  ),
                );
              } else if ($7 instanceof Some) {
                return new MergeReplace(
                  new Component(
                    last.path,
                    Option$None$const,
                    last.object_delete,
                    last.list_insert,
                    last.list_delete,
                    last.list_move,
                    last.na,
                    last.subtype,
                  ),
                );
              } else {
                return Merge$MergeDropBoth$const;
              }
            } else {
              let $6 = c.list_move;
              if ($6 instanceof Some) {
                let target = $6[0];
                let $7 = isEqual(last_index_of(c.path), new Ok(target));
                if ($7) {
                  return Merge$KeepDest$const;
                } else {
                  return Merge$NoMerge$const;
                }
              } else {
                return Merge$NoMerge$const;
              }
            }
          } else {
            let $5 = c.object_insert;
            if ($5 instanceof Some) {
              let $6 = last.object_insert;
              if ($6 instanceof None) {
                let $7 = last.object_delete;
                if ($7 instanceof Some) {
                  let component_insert_value = $5[0];
                  return new MergeReplace(
                    new Component(
                      last.path,
                      new Some(component_insert_value),
                      last.object_delete,
                      last.list_insert,
                      last.list_delete,
                      last.list_move,
                      last.na,
                      last.subtype,
                    ),
                  );
                } else {
                  let $8 = c.list_move;
                  if ($8 instanceof Some) {
                    let target = $8[0];
                    let $9 = isEqual(last_index_of(c.path), new Ok(target));
                    if ($9) {
                      return Merge$KeepDest$const;
                    } else {
                      return Merge$NoMerge$const;
                    }
                  } else {
                    return Merge$NoMerge$const;
                  }
                }
              } else {
                let $7 = c.list_move;
                if ($7 instanceof Some) {
                  let target = $7[0];
                  let $8 = isEqual(last_index_of(c.path), new Ok(target));
                  if ($8) {
                    return Merge$KeepDest$const;
                  } else {
                    return Merge$NoMerge$const;
                  }
                } else {
                  return Merge$NoMerge$const;
                }
              }
            } else {
              let $6 = c.list_move;
              if ($6 instanceof Some) {
                let target = $6[0];
                let $7 = isEqual(last_index_of(c.path), new Ok(target));
                if ($7) {
                  return Merge$KeepDest$const;
                } else {
                  return Merge$NoMerge$const;
                }
              } else {
                return Merge$NoMerge$const;
              }
            }
          }
        }
      } else {
        let $3 = c.object_delete;
        if ($3 instanceof Some) {
          let $4 = last.object_insert;
          if ($4 instanceof Some) {
            let $5 = c.object_insert;
            let $6 = last.object_delete;
            if ($5 instanceof Some) {
              let component_insert_value = $5[0];
              return new MergeReplace(
                new Component(
                  last.path,
                  new Some(component_insert_value),
                  last.object_delete,
                  last.list_insert,
                  last.list_delete,
                  last.list_move,
                  last.na,
                  last.subtype,
                ),
              );
            } else if ($6 instanceof Some) {
              return new MergeReplace(
                new Component(
                  last.path,
                  Option$None$const,
                  last.object_delete,
                  last.list_insert,
                  last.list_delete,
                  last.list_move,
                  last.na,
                  last.subtype,
                ),
              );
            } else {
              return Merge$MergeDropBoth$const;
            }
          } else {
            let $5 = c.list_move;
            if ($5 instanceof Some) {
              let target = $5[0];
              let $6 = isEqual(last_index_of(c.path), new Ok(target));
              if ($6) {
                return Merge$KeepDest$const;
              } else {
                return Merge$NoMerge$const;
              }
            } else {
              return Merge$NoMerge$const;
            }
          }
        } else {
          let $4 = c.object_insert;
          if ($4 instanceof Some) {
            let $5 = last.object_insert;
            if ($5 instanceof None) {
              let $6 = last.object_delete;
              if ($6 instanceof Some) {
                let component_insert_value = $4[0];
                return new MergeReplace(
                  new Component(
                    last.path,
                    new Some(component_insert_value),
                    last.object_delete,
                    last.list_insert,
                    last.list_delete,
                    last.list_move,
                    last.na,
                    last.subtype,
                  ),
                );
              } else {
                let $7 = c.list_move;
                if ($7 instanceof Some) {
                  let target = $7[0];
                  let $8 = isEqual(last_index_of(c.path), new Ok(target));
                  if ($8) {
                    return Merge$KeepDest$const;
                  } else {
                    return Merge$NoMerge$const;
                  }
                } else {
                  return Merge$NoMerge$const;
                }
              }
            } else {
              let $6 = c.list_move;
              if ($6 instanceof Some) {
                let target = $6[0];
                let $7 = isEqual(last_index_of(c.path), new Ok(target));
                if ($7) {
                  return Merge$KeepDest$const;
                } else {
                  return Merge$NoMerge$const;
                }
              } else {
                return Merge$NoMerge$const;
              }
            }
          } else {
            let $5 = c.list_move;
            if ($5 instanceof Some) {
              let target = $5[0];
              let $6 = isEqual(last_index_of(c.path), new Ok(target));
              if ($6) {
                return Merge$KeepDest$const;
              } else {
                return Merge$NoMerge$const;
              }
            } else {
              return Merge$NoMerge$const;
            }
          }
        }
      }
    }
  } else {
    let $1 = c.list_insert;
    if ($1 instanceof None) {
      let $2 = c.list_delete;
      if ($2 instanceof Some) {
        let $3 = last.list_insert;
        if ($3 instanceof Some) {
          let component_delete = $2[0];
          let last_value = $3[0];
          if (isEqual(component_delete, last_value)) {
            let $4 = last.list_delete;
            if ($4 instanceof Some) {
              return new MergeReplace(
                new Component(
                  last.path,
                  last.object_insert,
                  last.object_delete,
                  Option$None$const,
                  last.list_delete,
                  last.list_move,
                  last.na,
                  last.subtype,
                ),
              );
            } else {
              return Merge$MergeDropBoth$const;
            }
          } else {
            let $4 = c.object_delete;
            if ($4 instanceof Some) {
              let $5 = last.object_insert;
              if ($5 instanceof Some) {
                let $6 = c.object_insert;
                let $7 = last.object_delete;
                if ($6 instanceof Some) {
                  let component_insert_value = $6[0];
                  return new MergeReplace(
                    new Component(
                      last.path,
                      new Some(component_insert_value),
                      last.object_delete,
                      last.list_insert,
                      last.list_delete,
                      last.list_move,
                      last.na,
                      last.subtype,
                    ),
                  );
                } else if ($7 instanceof Some) {
                  return new MergeReplace(
                    new Component(
                      last.path,
                      Option$None$const,
                      last.object_delete,
                      last.list_insert,
                      last.list_delete,
                      last.list_move,
                      last.na,
                      last.subtype,
                    ),
                  );
                } else {
                  return Merge$MergeDropBoth$const;
                }
              } else {
                let $6 = c.list_move;
                if ($6 instanceof Some) {
                  let target = $6[0];
                  let $7 = isEqual(last_index_of(c.path), new Ok(target));
                  if ($7) {
                    return Merge$KeepDest$const;
                  } else {
                    return Merge$NoMerge$const;
                  }
                } else {
                  return Merge$NoMerge$const;
                }
              }
            } else {
              let $5 = c.object_insert;
              if ($5 instanceof Some) {
                let $6 = last.object_insert;
                if ($6 instanceof None) {
                  let $7 = last.object_delete;
                  if ($7 instanceof Some) {
                    let component_insert_value = $5[0];
                    return new MergeReplace(
                      new Component(
                        last.path,
                        new Some(component_insert_value),
                        last.object_delete,
                        last.list_insert,
                        last.list_delete,
                        last.list_move,
                        last.na,
                        last.subtype,
                      ),
                    );
                  } else {
                    let $8 = c.list_move;
                    if ($8 instanceof Some) {
                      let target = $8[0];
                      let $9 = isEqual(last_index_of(c.path), new Ok(target));
                      if ($9) {
                        return Merge$KeepDest$const;
                      } else {
                        return Merge$NoMerge$const;
                      }
                    } else {
                      return Merge$NoMerge$const;
                    }
                  }
                } else {
                  let $7 = c.list_move;
                  if ($7 instanceof Some) {
                    let target = $7[0];
                    let $8 = isEqual(last_index_of(c.path), new Ok(target));
                    if ($8) {
                      return Merge$KeepDest$const;
                    } else {
                      return Merge$NoMerge$const;
                    }
                  } else {
                    return Merge$NoMerge$const;
                  }
                }
              } else {
                let $6 = c.list_move;
                if ($6 instanceof Some) {
                  let target = $6[0];
                  let $7 = isEqual(last_index_of(c.path), new Ok(target));
                  if ($7) {
                    return Merge$KeepDest$const;
                  } else {
                    return Merge$NoMerge$const;
                  }
                } else {
                  return Merge$NoMerge$const;
                }
              }
            }
          }
        } else {
          let $4 = c.object_delete;
          if ($4 instanceof Some) {
            let $5 = last.object_insert;
            if ($5 instanceof Some) {
              let $6 = c.object_insert;
              let $7 = last.object_delete;
              if ($6 instanceof Some) {
                let component_insert_value = $6[0];
                return new MergeReplace(
                  new Component(
                    last.path,
                    new Some(component_insert_value),
                    last.object_delete,
                    last.list_insert,
                    last.list_delete,
                    last.list_move,
                    last.na,
                    last.subtype,
                  ),
                );
              } else if ($7 instanceof Some) {
                return new MergeReplace(
                  new Component(
                    last.path,
                    Option$None$const,
                    last.object_delete,
                    last.list_insert,
                    last.list_delete,
                    last.list_move,
                    last.na,
                    last.subtype,
                  ),
                );
              } else {
                return Merge$MergeDropBoth$const;
              }
            } else {
              let $6 = c.list_move;
              if ($6 instanceof Some) {
                let target = $6[0];
                let $7 = isEqual(last_index_of(c.path), new Ok(target));
                if ($7) {
                  return Merge$KeepDest$const;
                } else {
                  return Merge$NoMerge$const;
                }
              } else {
                return Merge$NoMerge$const;
              }
            }
          } else {
            let $5 = c.object_insert;
            if ($5 instanceof Some) {
              let $6 = last.object_insert;
              if ($6 instanceof None) {
                let $7 = last.object_delete;
                if ($7 instanceof Some) {
                  let component_insert_value = $5[0];
                  return new MergeReplace(
                    new Component(
                      last.path,
                      new Some(component_insert_value),
                      last.object_delete,
                      last.list_insert,
                      last.list_delete,
                      last.list_move,
                      last.na,
                      last.subtype,
                    ),
                  );
                } else {
                  let $8 = c.list_move;
                  if ($8 instanceof Some) {
                    let target = $8[0];
                    let $9 = isEqual(last_index_of(c.path), new Ok(target));
                    if ($9) {
                      return Merge$KeepDest$const;
                    } else {
                      return Merge$NoMerge$const;
                    }
                  } else {
                    return Merge$NoMerge$const;
                  }
                }
              } else {
                let $7 = c.list_move;
                if ($7 instanceof Some) {
                  let target = $7[0];
                  let $8 = isEqual(last_index_of(c.path), new Ok(target));
                  if ($8) {
                    return Merge$KeepDest$const;
                  } else {
                    return Merge$NoMerge$const;
                  }
                } else {
                  return Merge$NoMerge$const;
                }
              }
            } else {
              let $6 = c.list_move;
              if ($6 instanceof Some) {
                let target = $6[0];
                let $7 = isEqual(last_index_of(c.path), new Ok(target));
                if ($7) {
                  return Merge$KeepDest$const;
                } else {
                  return Merge$NoMerge$const;
                }
              } else {
                return Merge$NoMerge$const;
              }
            }
          }
        }
      } else {
        let $3 = c.object_delete;
        if ($3 instanceof Some) {
          let $4 = last.object_insert;
          if ($4 instanceof Some) {
            let $5 = c.object_insert;
            let $6 = last.object_delete;
            if ($5 instanceof Some) {
              let component_insert_value = $5[0];
              return new MergeReplace(
                new Component(
                  last.path,
                  new Some(component_insert_value),
                  last.object_delete,
                  last.list_insert,
                  last.list_delete,
                  last.list_move,
                  last.na,
                  last.subtype,
                ),
              );
            } else if ($6 instanceof Some) {
              return new MergeReplace(
                new Component(
                  last.path,
                  Option$None$const,
                  last.object_delete,
                  last.list_insert,
                  last.list_delete,
                  last.list_move,
                  last.na,
                  last.subtype,
                ),
              );
            } else {
              return Merge$MergeDropBoth$const;
            }
          } else {
            let $5 = c.list_move;
            if ($5 instanceof Some) {
              let target = $5[0];
              let $6 = isEqual(last_index_of(c.path), new Ok(target));
              if ($6) {
                return Merge$KeepDest$const;
              } else {
                return Merge$NoMerge$const;
              }
            } else {
              return Merge$NoMerge$const;
            }
          }
        } else {
          let $4 = c.object_insert;
          if ($4 instanceof Some) {
            let $5 = last.object_insert;
            if ($5 instanceof None) {
              let $6 = last.object_delete;
              if ($6 instanceof Some) {
                let component_insert_value = $4[0];
                return new MergeReplace(
                  new Component(
                    last.path,
                    new Some(component_insert_value),
                    last.object_delete,
                    last.list_insert,
                    last.list_delete,
                    last.list_move,
                    last.na,
                    last.subtype,
                  ),
                );
              } else {
                let $7 = c.list_move;
                if ($7 instanceof Some) {
                  let target = $7[0];
                  let $8 = isEqual(last_index_of(c.path), new Ok(target));
                  if ($8) {
                    return Merge$KeepDest$const;
                  } else {
                    return Merge$NoMerge$const;
                  }
                } else {
                  return Merge$NoMerge$const;
                }
              }
            } else {
              let $6 = c.list_move;
              if ($6 instanceof Some) {
                let target = $6[0];
                let $7 = isEqual(last_index_of(c.path), new Ok(target));
                if ($7) {
                  return Merge$KeepDest$const;
                } else {
                  return Merge$NoMerge$const;
                }
              } else {
                return Merge$NoMerge$const;
              }
            }
          } else {
            let $5 = c.list_move;
            if ($5 instanceof Some) {
              let target = $5[0];
              let $6 = isEqual(last_index_of(c.path), new Ok(target));
              if ($6) {
                return Merge$KeepDest$const;
              } else {
                return Merge$NoMerge$const;
              }
            } else {
              return Merge$NoMerge$const;
            }
          }
        }
      }
    } else {
      let $2 = c.object_delete;
      if ($2 instanceof Some) {
        let $3 = last.object_insert;
        if ($3 instanceof Some) {
          let $4 = c.object_insert;
          let $5 = last.object_delete;
          if ($4 instanceof Some) {
            let component_insert_value = $4[0];
            return new MergeReplace(
              new Component(
                last.path,
                new Some(component_insert_value),
                last.object_delete,
                last.list_insert,
                last.list_delete,
                last.list_move,
                last.na,
                last.subtype,
              ),
            );
          } else if ($5 instanceof Some) {
            return new MergeReplace(
              new Component(
                last.path,
                Option$None$const,
                last.object_delete,
                last.list_insert,
                last.list_delete,
                last.list_move,
                last.na,
                last.subtype,
              ),
            );
          } else {
            return Merge$MergeDropBoth$const;
          }
        } else {
          let $4 = c.list_move;
          if ($4 instanceof Some) {
            let target = $4[0];
            let $5 = isEqual(last_index_of(c.path), new Ok(target));
            if ($5) {
              return Merge$KeepDest$const;
            } else {
              return Merge$NoMerge$const;
            }
          } else {
            return Merge$NoMerge$const;
          }
        }
      } else {
        let $3 = c.object_insert;
        if ($3 instanceof Some) {
          let $4 = last.object_insert;
          if ($4 instanceof None) {
            let $5 = last.object_delete;
            if ($5 instanceof Some) {
              let component_insert_value = $3[0];
              return new MergeReplace(
                new Component(
                  last.path,
                  new Some(component_insert_value),
                  last.object_delete,
                  last.list_insert,
                  last.list_delete,
                  last.list_move,
                  last.na,
                  last.subtype,
                ),
              );
            } else {
              let $6 = c.list_move;
              if ($6 instanceof Some) {
                let target = $6[0];
                let $7 = isEqual(last_index_of(c.path), new Ok(target));
                if ($7) {
                  return Merge$KeepDest$const;
                } else {
                  return Merge$NoMerge$const;
                }
              } else {
                return Merge$NoMerge$const;
              }
            }
          } else {
            let $5 = c.list_move;
            if ($5 instanceof Some) {
              let target = $5[0];
              let $6 = isEqual(last_index_of(c.path), new Ok(target));
              if ($6) {
                return Merge$KeepDest$const;
              } else {
                return Merge$NoMerge$const;
              }
            } else {
              return Merge$NoMerge$const;
            }
          }
        } else {
          let $4 = c.list_move;
          if ($4 instanceof Some) {
            let target = $4[0];
            let $5 = isEqual(last_index_of(c.path), new Ok(target));
            if ($5) {
              return Merge$KeepDest$const;
            } else {
              return Merge$NoMerge$const;
            }
          } else {
            return Merge$NoMerge$const;
          }
        }
      }
    }
  }
}

function split_last_component(operation) {
  let $ = $list.reverse(operation);
  if ($ instanceof $Empty) {
    return new Error(undefined);
  } else {
    let last = $.head;
    let reversed_init = $.tail;
    return new Ok([$list.reverse(reversed_init), last]);
  }
}

function append(dest, c) {
  let $ = split_last_component(dest);
  if ($ instanceof Ok) {
    let init = $[0][0];
    let last = $[0][1];
    let $1 = isEqual(last.path, c.path);
    if ($1) {
      let $2 = merge_pair(last, c);
      if ($2 instanceof MergeReplace) {
        let new_last = $2[0];
        return $list.append(init, toList([new_last]));
      } else if ($2 instanceof MergeDropBoth) {
        return init;
      } else if ($2 instanceof KeepDest) {
        return dest;
      } else {
        return $list.append(dest, toList([c]));
      }
    } else {
      return $list.append(dest, toList([c]));
    }
  } else {
    return toList([c]);
  }
}

function other_od_branch(c, other, common, common_operand) {
  let $ = isEqual(path_key_at(c.path, common), path_key_at(other.path, common));
  if ($) {
    if (common_operand) {
      let $1 = c.object_insert;
      if ($1 instanceof Some) {
        return toList([
          new Component(
            c.path,
            c.object_insert,
            Option$None$const,
            c.list_insert,
            c.list_delete,
            c.list_move,
            c.na,
            c.subtype,
          ),
        ]);
      } else {
        return $List$Empty$const;
      }
    } else {
      return $List$Empty$const;
    }
  } else {
    return toList([c]);
  }
}

function other_oi_branch(c, other, common, common_operand, side) {
  let $ = isEqual(path_key_at(c.path, common), path_key_at(other.path, common));
  if ($) {
    if (common_operand) {
      let $1 = c.object_insert;
      let $2 = other.object_insert;
      if ($1 instanceof Some) {
        if (side instanceof Lft) {
          if ($2 instanceof Some) {
            let oiv = $2[0];
            return toList([object_delete(c.path, oiv), c]);
          } else {
            return toList([c]);
          }
        } else {
          return $List$Empty$const;
        }
      } else {
        return toList([c]);
      }
    } else {
      return $List$Empty$const;
    }
  } else {
    return toList([c]);
  }
}

function other_oreplace_branch(c, other, common, common_operand, side) {
  let $ = isEqual(path_key_at(c.path, common), path_key_at(other.path, common));
  if ($) {
    let $1 = c.object_insert;
    if ($1 instanceof Some && common_operand) {
      if (side instanceof Lft) {
        return toList([
          new Component(
            c.path,
            c.object_insert,
            other.object_insert,
            c.list_insert,
            c.list_delete,
            c.list_move,
            c.na,
            c.subtype,
          ),
        ]);
      } else {
        return $List$Empty$const;
      }
    } else {
      return $List$Empty$const;
    }
  } else {
    return toList([c]);
  }
}

function lm_vs_lm(c, common, from, to, other_from, other_to, side) {
  let $ = from === other_from;
  if ($) {
    if (side instanceof Lft) {
      let c1 = new Component(
        set_index_at(c.path, common, other_to),
        c.object_insert,
        c.object_delete,
        c.list_insert,
        c.list_delete,
        c.list_move,
        c.na,
        c.subtype,
      );
      let $1 = from === to;
      if ($1) {
        return toList([
          new Component(
            c1.path,
            c1.object_insert,
            c1.object_delete,
            c1.list_insert,
            c1.list_delete,
            new Some(other_to),
            c1.na,
            c1.subtype,
          ),
        ]);
      } else {
        return toList([c1]);
      }
    } else {
      return $List$Empty$const;
    }
  } else {
    let _block;
    let $1 = from > other_from;
    if ($1) {
      _block = -1;
    } else {
      _block = 0;
    }
    let a = _block;
    let _block$1;
    let $3 = from > other_to;
    if ($3) {
      _block$1 = [1, 0];
    } else {
      let $4 = (from === other_to) && (other_from > other_to);
      if ($4) {
        let $5 = from === to;
        if ($5) {
          _block$1 = [1, 1];
        } else {
          _block$1 = [1, 0];
        }
      } else {
        _block$1 = [0, 0];
      }
    }
    let $2 = _block$1;
    let b = $2[0];
    let lm_from_p = $2[1];
    let p_delta = a + b;
    let _block$2;
    let $4 = to > other_from;
    if ($4) {
      _block$2 = -1;
    } else {
      let $5 = (to === other_from) && (to > from);
      if ($5) {
        _block$2 = -1;
      } else {
        _block$2 = 0;
      }
    }
    let s1 = _block$2;
    let _block$3;
    let $5 = to > other_to;
    if ($5) {
      _block$3 = 1;
    } else {
      let $6 = to === other_to;
      if ($6) {
        let cond_a = (other_to > other_from) && (to > from);
        let cond_b = (other_to < other_from) && (to < from);
        let $7 = cond_a || cond_b;
        if ($7) {
          if (side instanceof Lft) {
            _block$3 = 0;
          } else {
            _block$3 = 1;
          }
        } else {
          let $8 = to > from;
          if ($8) {
            _block$3 = 1;
          } else {
            let $9 = to === other_from;
            if ($9) {
              _block$3 = -1;
            } else {
              _block$3 = 0;
            }
          }
        }
      } else {
        _block$3 = 0;
      }
    }
    let s2 = _block$3;
    let lm_delta = (lm_from_p + s1) + s2;
    return toList([
      new Component(
        bump_index_at(c.path, common, p_delta),
        c.object_insert,
        c.object_delete,
        c.list_insert,
        c.list_delete,
        new Some(to + lm_delta),
        c.na,
        c.subtype,
      ),
    ]);
  }
}

function other_lm_branch(
  c,
  other,
  common,
  common_operand,
  c_path_length,
  other_len,
  side
) {
  let other_from = index_at(other.path, common);
  let _block;
  let $ = other.list_move;
  if ($ instanceof Some) {
    let t = $[0];
    _block = t;
  } else {
    _block = -999_999;
  }
  let other_to = _block;
  let $1 = c.list_move;
  let $2 = c_path_length === other_len;
  if ($1 instanceof Some && $2) {
    let to = $1[0];
    let from = index_at(c.path, common);
    let $3 = other_from === other_to;
    if ($3) {
      return toList([c]);
    } else {
      return lm_vs_lm(c, common, from, to, other_from, other_to, side);
    }
  } else {
    let $3 = c.list_insert;
    let $4 = c.list_delete;
    if ($3 instanceof Some && $4 instanceof None && common_operand) {
      let p = index_at(c.path, common);
      let _block$1;
      let $5 = p > other_from;
      if ($5) {
        _block$1 = -1;
      } else {
        _block$1 = 0;
      }
      let d1 = _block$1;
      let _block$2;
      let $6 = p > other_to;
      if ($6) {
        _block$2 = 1;
      } else {
        _block$2 = 0;
      }
      let d2 = _block$2;
      return toList([
        new Component(
          bump_index_at(c.path, common, d1 + d2),
          c.object_insert,
          c.object_delete,
          c.list_insert,
          c.list_delete,
          c.list_move,
          c.na,
          c.subtype,
        ),
      ]);
    } else {
      let p = index_at(c.path, common);
      let $5 = p === other_from;
      if ($5) {
        return toList([
          new Component(
            set_index_at(c.path, common, other_to),
            c.object_insert,
            c.object_delete,
            c.list_insert,
            c.list_delete,
            c.list_move,
            c.na,
            c.subtype,
          ),
        ]);
      } else {
        let _block$1;
        let $6 = p > other_from;
        if ($6) {
          _block$1 = -1;
        } else {
          _block$1 = 0;
        }
        let d1 = _block$1;
        let _block$2;
        let $7 = p > other_to;
        if ($7) {
          _block$2 = 1;
        } else {
          let $8 = (p === other_to) && (other_from > other_to);
          if ($8) {
            _block$2 = 1;
          } else {
            _block$2 = 0;
          }
        }
        let d2 = _block$2;
        return toList([
          new Component(
            bump_index_at(c.path, common, d1 + d2),
            c.object_insert,
            c.object_delete,
            c.list_insert,
            c.list_delete,
            c.list_move,
            c.na,
            c.subtype,
          ),
        ]);
      }
    }
  }
}

function other_ld_branch(
  c,
  other,
  common,
  common_operand,
  c_path_length,
  other_len
) {
  let o_idx = index_at(other.path, common);
  let c_idx = index_at(c.path, common);
  let same = isEqual(
    path_key_at(c.path, common),
    path_key_at(other.path, common)
  );
  let _block;
  let $ = c.list_move;
  if ($ instanceof Some && common_operand) {
    let list_move$1 = $[0];
    if (same) {
      _block = new Error(undefined);
    } else {
      let _block$1;
      let $1 = (o_idx < list_move$1) || ((o_idx === list_move$1) && (c_idx < list_move$1));
      if ($1) {
        _block$1 = list_move$1 - 1;
      } else {
        _block$1 = list_move$1;
      }
      let decremented = _block$1;
      _block = new Ok(
        new Component(
          c.path,
          c.object_insert,
          c.object_delete,
          c.list_insert,
          c.list_delete,
          new Some(decremented),
          c.na,
          c.subtype,
        ),
      );
    }
  } else {
    _block = new Ok(c);
  }
  let after_lm = _block;
  if (after_lm instanceof Ok) {
    let c$1 = after_lm[0];
    let $1 = o_idx < c_idx;
    if ($1) {
      return toList([
        new Component(
          bump_index_at(c$1.path, common, -1),
          c$1.object_insert,
          c$1.object_delete,
          c$1.list_insert,
          c$1.list_delete,
          c$1.list_move,
          c$1.na,
          c$1.subtype,
        ),
      ]);
    } else {
      if (same) {
        let $2 = other_len < c_path_length;
        if ($2) {
          return $List$Empty$const;
        } else {
          let $3 = c$1.list_delete;
          if ($3 instanceof Some) {
            let $4 = c$1.list_insert;
            if ($4 instanceof Some) {
              return toList([
                new Component(
                  c$1.path,
                  c$1.object_insert,
                  c$1.object_delete,
                  c$1.list_insert,
                  Option$None$const,
                  c$1.list_move,
                  c$1.na,
                  c$1.subtype,
                ),
              ]);
            } else {
              return $List$Empty$const;
            }
          } else {
            return toList([c$1]);
          }
        }
      } else {
        return toList([c$1]);
      }
    }
  } else {
    return $List$Empty$const;
  }
}

function other_li_branch(c, other, common, common_operand, side) {
  let o_idx = index_at(other.path, common);
  let c_idx = index_at(c.path, common);
  let same = isEqual(
    path_key_at(c.path, common),
    path_key_at(other.path, common)
  );
  let _block;
  let $ = c.list_insert;
  let $1 = c.list_delete;
  if ($ instanceof Some && $1 instanceof None && common_operand && same) {
    if (side instanceof Lft) {
      _block = c;
    } else {
      _block = new Component(
        bump_index_at(c.path, common, 1),
        c.object_insert,
        c.object_delete,
        c.list_insert,
        c.list_delete,
        c.list_move,
        c.na,
        c.subtype,
      );
    }
  } else {
    let $2 = o_idx <= c_idx;
    if ($2) {
      _block = new Component(
        bump_index_at(c.path, common, 1),
        c.object_insert,
        c.object_delete,
        c.list_insert,
        c.list_delete,
        c.list_move,
        c.na,
        c.subtype,
      );
    } else {
      _block = c;
    }
  }
  let c1 = _block;
  let _block$1;
  let $2 = c1.list_move;
  if ($2 instanceof Some && common_operand) {
    let list_move$1 = $2[0];
    let $3 = o_idx <= list_move$1;
    if ($3) {
      _block$1 = new Component(
        c1.path,
        c1.object_insert,
        c1.object_delete,
        c1.list_insert,
        c1.list_delete,
        new Some(list_move$1 + 1),
        c1.na,
        c1.subtype,
      );
    } else {
      _block$1 = c1;
    }
  } else {
    _block$1 = c1;
  }
  let c2 = _block$1;
  return toList([c2]);
}

function list_replace_branch(c, other, side, common, common_operand) {
  let $ = isEqual(path_key_at(other.path, common), path_key_at(c.path, common));
  if ($) {
    if (common_operand) {
      let $1 = c.list_delete;
      if ($1 instanceof Some) {
        let $2 = c.list_insert;
        if ($2 instanceof Some && side instanceof Lft) {
          return toList([
            new Component(
              c.path,
              c.object_insert,
              c.object_delete,
              c.list_insert,
              other.list_insert,
              c.list_move,
              c.na,
              c.subtype,
            ),
          ]);
        } else {
          return $List$Empty$const;
        }
      } else {
        return toList([c]);
      }
    } else {
      return $List$Empty$const;
    }
  } else {
    return toList([c]);
  }
}

/**
 * A subtype operation is empty when its operation list is empty. Drop the
 * component in that case.
 * 
 * @ignore
 */
function is_empty_subtype_operation(operation) {
  return isEqual(operation, new VArray($List$Empty$const));
}

function text0_serialize_component(component) {
  if (component instanceof TextInsert) {
    let p = component.p;
    let s = component.s;
    return new VObject(
      toList([["i", new VString(s)], ["p", new VNumber(new NInt(p))]]),
    );
  } else {
    let p = component.p;
    let s = component.s;
    return new VObject(
      toList([["d", new VString(s)], ["p", new VNumber(new NInt(p))]]),
    );
  }
}

function text0_serialize_operation(operation) {
  return new VArray($list.map(operation, text0_serialize_component));
}

/**
 * Compose `component` onto the last component `last`, when the two are
 * adjacent edits of the same kind. That is two overlapping inserts, or two
 * overlapping deletes.
 * 
 * @ignore
 */
function text0_merge(last, component) {
  if (last instanceof TextInsert) {
    if (component instanceof TextInsert) {
      let last_position = last.p;
      let last_insert = last.s;
      let component_position = component.p;
      let component_insert = component.s;
      let $ = (last_position <= component_position) && (component_position <= (last_position + $string.length(
        last_insert,
      )));
      if ($) {
        return new Ok(
          new TextInsert(
            last_position,
            string_inject(
              last_insert,
              component_position - last_position,
              component_insert,
            ),
          ),
        );
      } else {
        return new Error(undefined);
      }
    } else {
      return new Error(undefined);
    }
  } else if (component instanceof TextInsert) {
    return new Error(undefined);
  } else {
    let last_position = last.p;
    let last_delete = last.s;
    let component_position = component.p;
    let component_delete = component.s;
    let $ = (component_position <= last_position) && (last_position <= (component_position + $string.length(
      component_delete,
    )));
    if ($) {
      return new Ok(
        new TextDelete(
          component_position,
          string_inject(
            component_delete,
            last_position - component_position,
            last_delete,
          ),
        ),
      );
    } else {
      return new Error(undefined);
    }
  }
}

function text0_split_last(operation) {
  let $ = $list.reverse(operation);
  if ($ instanceof $Empty) {
    return new Error(undefined);
  } else {
    let last = $.head;
    let rest = $.tail;
    return new Ok([$list.reverse(rest), last]);
  }
}

function text0_is_empty_component(component) {
  if (component instanceof TextInsert) {
    let $ = component.s;
    if ($ === "") {
      return true;
    } else {
      return false;
    }
  } else {
    let $ = component.s;
    if ($ === "") {
      return true;
    } else {
      return false;
    }
  }
}

/**
 * Append `component` to `operation`. The function drops a component that does
 * nothing, and it composes two adjacent inserts or two adjacent deletes, the
 * same as the `text._append` function of json0. `operation` is in the normal
 * order, which is the execution order.
 * 
 * @ignore
 */
function text0_append(operation, component) {
  let $ = text0_is_empty_component(component);
  if ($) {
    return operation;
  } else {
    let $1 = text0_split_last(operation);
    if ($1 instanceof Ok) {
      let leading = $1[0][0];
      let last = $1[0][1];
      let $2 = text0_merge(last, component);
      if ($2 instanceof Ok) {
        let merged = $2[0];
        return $list.append(leading, toList([merged]));
      } else {
        return $list.append(operation, toList([component]));
      }
    } else {
      return toList([component]);
    }
  }
}

/**
 * Move `position` for a concurrent `component`. For an insert, `insert_after`
 * decides whether a position exactly at the insert moves past it.
 * 
 * @ignore
 */
function text0_transform_position(position, component, insert_after) {
  if (component instanceof TextInsert) {
    let component_position = component.p;
    let component_text = component.s;
    let $ = (component_position < position) || ((component_position === position) && insert_after);
    if ($) {
      return position + $string.length(component_text);
    } else {
      return position;
    }
  } else {
    let component_position = component.p;
    let component_text = component.s;
    let component_length = $string.length(component_text);
    let $ = position <= component_position;
    if ($) {
      return position;
    } else {
      let $1 = position <= (component_position + component_length);
      if ($1) {
        return component_position;
      } else {
        return position - component_length;
      }
    }
  }
}

/**
 * Transform `component` by `other`, and append each result to `destination`
 * in the normal order. The function is asymmetric. `side` breaks a tie between
 * two inserts.
 * 
 * @ignore
 */
function text0_transform_component(destination, component, other, side) {
  if (component instanceof TextInsert) {
    let component_position = component.p;
    let component_text = component.s;
    return new Ok(
      text0_append(
        destination,
        new TextInsert(
          text0_transform_position(
            component_position,
            other,
            side instanceof Rgt,
          ),
          component_text,
        ),
      ),
    );
  } else {
    let component_position = component.p;
    let component_text = component.s;
    if (other instanceof TextInsert) {
      let other_position = other.p;
      let other_text = other.s;
      let _block;
      let $1 = component_position < other_position;
      if ($1) {
        _block = [
          text0_append(
            destination,
            new TextDelete(
              component_position,
              $string.slice(
                component_text,
                0,
                other_position - component_position,
              ),
            ),
          ),
          $string.drop_start(
            component_text,
            other_position - component_position,
          ),
        ];
      } else {
        _block = [destination, component_text];
      }
      let $ = _block;
      let destination$1 = $[0];
      let remaining = $[1];
      let $2 = remaining === "";
      if ($2) {
        return new Ok(destination$1);
      } else {
        return new Ok(
          text0_append(
            destination$1,
            new TextDelete(
              component_position + $string.length(other_text),
              remaining,
            ),
          ),
        );
      }
    } else {
      let other_position = other.p;
      let other_text = other.s;
      let component_length = $string.length(component_text);
      let other_length = $string.length(other_text);
      let $ = component_position >= (other_position + other_length);
      if ($) {
        return new Ok(
          text0_append(
            destination,
            new TextDelete(component_position - other_length, component_text),
          ),
        );
      } else {
        let $1 = (component_position + component_length) <= other_position;
        if ($1) {
          return new Ok(text0_append(destination, component));
        } else {
          let _block;
          let $2 = component_position < other_position;
          if ($2) {
            _block = $string.slice(
              component_text,
              0,
              other_position - component_position,
            );
          } else {
            _block = "";
          }
          let part1 = _block;
          let _block$1;
          let $3 = (component_position + component_length) > (other_position + other_length);
          if ($3) {
            _block$1 = $string.drop_start(
              component_text,
              (other_position + other_length) - component_position,
            );
          } else {
            _block$1 = "";
          }
          let part2 = _block$1;
          let new_d = part1 + part2;
          let intersect_start = $int.max(component_position, other_position);
          let intersect_end = $int.min(
            component_position + component_length,
            other_position + other_length,
          );
          let intersect_len = intersect_end - intersect_start;
          let c_intersect = $string.slice(
            component_text,
            intersect_start - component_position,
            intersect_len,
          );
          let o_intersect = $string.slice(
            other_text,
            intersect_start - other_position,
            intersect_len,
          );
          return $result.try$(
            (() => {
              let $4 = c_intersect === o_intersect;
              if ($4) {
                return new Ok(undefined);
              } else {
                return new Error(
                  new BadValue(
                    "text0 deletes disagree in the overlapping region",
                  ),
                );
              }
            })(),
            (_) => {
              let $4 = new_d === "";
              if ($4) {
                return new Ok(destination);
              } else {
                return new Ok(
                  text0_append(
                    destination,
                    new TextDelete(
                      text0_transform_position(component_position, other, false),
                      new_d,
                    ),
                  ),
                );
              }
            },
          );
        }
      }
    }
  }
}

/**
 * Compose one `right_component` against the whole remaining left operation.
 * This is the inner `while` loop of `transformX`, with its split-and-recurse
 * branch.
 * 
 * @ignore
 */
function text0_tx_inner(
  left,
  right_component,
  new_left_operation,
  new_right_operation
) {
  if (left instanceof $Empty) {
    return new Ok(
      [new_left_operation, text0_append(new_right_operation, right_component)],
    );
  } else {
    let lc = left.head;
    let lrest = left.tail;
    return $result.try$(
      text0_transform_component(
        new_left_operation,
        lc,
        right_component,
        Side$Lft$const,
      ),
      (new_left_operation) => {
        return $result.try$(
          text0_transform_component(
            $List$Empty$const,
            right_component,
            lc,
            Side$Rgt$const,
          ),
          (next_c) => {
            if (next_c instanceof $Empty) {
              return new Ok(
                [
                  $list.fold(lrest, new_left_operation, text0_append),
                  new_right_operation,
                ],
              );
            } else {
              let $ = next_c.tail;
              if ($ instanceof $Empty) {
                let only = next_c.head;
                return text0_tx_inner(
                  lrest,
                  only,
                  new_left_operation,
                  new_right_operation,
                );
              } else {
                return $result.try$(
                  text0_transform_x(lrest, next_c),
                  (_use0) => {
                    let pair_left = _use0[0];
                    let pair_right = _use0[1];
                    return new Ok(
                      [
                        $list.fold(pair_left, new_left_operation, text0_append),
                        $list.fold(
                          pair_right,
                          new_right_operation,
                          text0_append,
                        ),
                      ],
                    );
                  },
                );
              }
            }
          },
        );
      },
    );
  }
}

function text0_tx_outer(left_operation, right_operation, new_right_operation) {
  if (right_operation instanceof $Empty) {
    return new Ok([left_operation, new_right_operation]);
  } else {
    let right_component = right_operation.head;
    let right_rest = right_operation.tail;
    return $result.try$(
      text0_tx_inner(
        left_operation,
        right_component,
        $List$Empty$const,
        new_right_operation,
      ),
      (_use0) => {
        let new_left_operation = _use0[0];
        let new_right_operation$1 = _use0[1];
        return text0_tx_outer(
          new_left_operation,
          right_rest,
          new_right_operation$1,
        );
      },
    );
  }
}

/**
 * The recursive N² transform driver, which is `bootstrapTransform.transformX`
 * in json0. It returns `#(left', right')`, where each operation is transformed
 * past the other.
 * 
 * @ignore
 */
function text0_transform_x(left_operation, right_operation) {
  return text0_tx_outer(left_operation, right_operation, $List$Empty$const);
}

function text0_transform_operations(operation, other, side) {
  if (other instanceof $Empty) {
    return new Ok(operation);
  } else if (operation instanceof $Empty) {
    if (side instanceof Lft) {
      return $result.try$(
        text0_transform_x(operation, other),
        (_use0) => {
          let left = _use0[0];
          return new Ok(left);
        },
      );
    } else {
      return $result.try$(
        text0_transform_x(other, operation),
        (_use0) => {
          let right = _use0[1];
          return new Ok(right);
        },
      );
    }
  } else {
    let $ = other.tail;
    if ($ instanceof $Empty) {
      let $1 = operation.tail;
      if ($1 instanceof $Empty) {
        let single_other = other.head;
        let single = operation.head;
        return text0_transform_component(
          $List$Empty$const,
          single,
          single_other,
          side,
        );
      } else {
        if (side instanceof Lft) {
          return $result.try$(
            text0_transform_x(operation, other),
            (_use0) => {
              let left = _use0[0];
              return new Ok(left);
            },
          );
        } else {
          return $result.try$(
            text0_transform_x(other, operation),
            (_use0) => {
              let right = _use0[1];
              return new Ok(right);
            },
          );
        }
      }
    } else {
      if (side instanceof Lft) {
        return $result.try$(
          text0_transform_x(operation, other),
          (_use0) => {
            let left = _use0[0];
            return new Ok(left);
          },
        );
      } else {
        return $result.try$(
          text0_transform_x(other, operation),
          (_use0) => {
            let right = _use0[1];
            return new Ok(right);
          },
        );
      }
    }
  }
}

function text0_transform(a, b, side) {
  return $result.try$(
    text0_parse_operation(a),
    (aop) => {
      return $result.try$(
        text0_parse_operation(b),
        (bop) => {
          return $result.try$(
            text0_transform_operations(aop, bop, side),
            (result) => { return new Ok(text0_serialize_operation(result)); },
          );
        },
      );
    },
  );
}

/**
 * Transform the subtype operation `a` past `b`. Rung 4 (`text0`) completes
 * this function.
 * 
 * @ignore
 */
function subtype_transform(name, a, b, side) {
  if (name === "text0") {
    return text0_transform(a, b, side);
  } else {
    return new Error(new UnknownSubtype(name));
  }
}

function is_known_subtype(name) {
  return name === "text0";
}

function transform_other_subtype(c, oname, other_operation, side) {
  let $ = is_known_subtype(oname);
  if ($) {
    let $1 = c.subtype;
    if ($1 instanceof Some) {
      let cname = $1[0][0];
      if (cname === oname) {
        let component_operation = $1[0][1];
        return $result.try$(
          subtype_transform(oname, component_operation, other_operation, side),
          (transformed) => {
            let $2 = is_empty_subtype_operation(transformed);
            if ($2) {
              return new Ok($List$Empty$const);
            } else {
              return new Ok(
                toList([
                  new Component(
                    c.path,
                    c.object_insert,
                    c.object_delete,
                    c.list_insert,
                    c.list_delete,
                    c.list_move,
                    c.na,
                    new Some([oname, transformed]),
                  ),
                ]),
              );
            }
          },
        );
      } else {
        return new Ok(toList([c]));
      }
    } else {
      return new Ok(toList([c]));
    }
  } else {
    return new Ok(toList([c]));
  }
}

function transform_matrix(c, other, side, common, c_path_length, other_len) {
  let common_operand = c_path_length === other_len;
  let $ = other.subtype;
  if ($ instanceof Some) {
    let oname = $[0][0];
    let other_operation = $[0][1];
    return transform_other_subtype(c, oname, other_operation, side);
  } else {
    let $1 = other.na;
    if ($1 instanceof Some) {
      return new Ok(toList([c]));
    } else {
      let $2 = other.list_insert;
      if ($2 instanceof Some) {
        let $3 = other.list_delete;
        if ($3 instanceof Some) {
          return new Ok(
            list_replace_branch(c, other, side, common, common_operand),
          );
        } else {
          return new Ok(other_li_branch(c, other, common, common_operand, side));
        }
      } else {
        let $3 = other.list_delete;
        if ($3 instanceof Some) {
          return new Ok(
            other_ld_branch(
              c,
              other,
              common,
              common_operand,
              c_path_length,
              other_len,
            ),
          );
        } else {
          let $4 = other.list_move;
          if ($4 instanceof Some) {
            return new Ok(
              other_lm_branch(
                c,
                other,
                common,
                common_operand,
                c_path_length,
                other_len,
                side,
              ),
            );
          } else {
            let $5 = other.object_insert;
            if ($5 instanceof Some) {
              let $6 = other.object_delete;
              if ($6 instanceof Some) {
                return new Ok(
                  other_oreplace_branch(c, other, common, common_operand, side),
                );
              } else {
                return new Ok(
                  other_oi_branch(c, other, common, common_operand, side),
                );
              }
            } else {
              let $6 = other.object_delete;
              if ($6 instanceof Some) {
                return new Ok(other_od_branch(c, other, common, common_operand));
              } else {
                return new Ok(toList([c]));
              }
            }
          }
        }
      }
    }
  }
}

/**
 * If `c` deletes a subtree that `other` edits, add the edit of `other` to the
 * stored pre-image. `invert` thus stays exact. This is the `common2` block of
 * json0.
 * 
 * @ignore
 */
function apply_preimage(c, other, common2, c_path_length, other_len) {
  if (common2 instanceof Ok) {
    let k = common2[0];
    let $ = (other_len > c_path_length) && (isEqual(
      path_key_at(c.path, k),
      path_key_at(other.path, k)
    ));
    if ($) {
      let oc = new Component(
        $list.drop(other.path, c_path_length),
        other.object_insert,
        other.object_delete,
        other.list_insert,
        other.list_delete,
        other.list_move,
        other.na,
        other.subtype,
      );
      let $1 = c.list_delete;
      let $2 = c.object_delete;
      if ($1 instanceof Some) {
        let ldv = $1[0];
        let _pipe = apply(ldv, toList([oc]));
        return $result.map(
          _pipe,
          (v) => {
            return new Component(
              c.path,
              c.object_insert,
              c.object_delete,
              c.list_insert,
              new Some(v),
              c.list_move,
              c.na,
              c.subtype,
            );
          },
        );
      } else if ($2 instanceof Some) {
        let odv = $2[0];
        let _pipe = apply(odv, toList([oc]));
        return $result.map(
          _pipe,
          (v) => {
            return new Component(
              c.path,
              c.object_insert,
              new Some(v),
              c.list_insert,
              c.list_delete,
              c.list_move,
              c.na,
              c.subtype,
            );
          },
        );
      } else {
        return new Ok(c);
      }
    } else {
      return new Ok(c);
    }
  } else {
    return new Ok(c);
  }
}

/**
 * The `transformComponent` function of json0. It transforms one component `c`
 * past one `other` component, and it returns the 0, 1, or 2 components to
 * append to the result.
 * 
 * @ignore
 */
function transform_component(c, other, side) {
  let c_path_length = adjusted_length(c);
  let other_len = adjusted_length(other);
  let common = common_length(other, c);
  let common2 = common_length(c, other);
  return $result.try$(
    apply_preimage(c, other, common2, c_path_length, other_len),
    (c) => {
      if (common instanceof Ok) {
        let common$1 = common[0];
        return transform_matrix(
          c,
          other,
          side,
          common$1,
          c_path_length,
          other_len,
        );
      } else {
        return new Ok(toList([c]));
      }
    },
  );
}

function transform_component_into(dest, c, other, side) {
  return $result.try$(
    transform_component(c, other, side),
    (to_append) => { return new Ok($list.fold(to_append, dest, append)); },
  );
}

function inner_loop(left_remaining, right_c, new_left, new_right) {
  if (left_remaining instanceof $Empty) {
    return new Ok([new_left, append(new_right, right_c)]);
  } else {
    let l = left_remaining.head;
    let rest = left_remaining.tail;
    return $result.try$(
      transform_component_into(new_left, l, right_c, Side$Lft$const),
      (new_left2) => {
        return $result.try$(
          transform_component(right_c, l, Side$Rgt$const),
          (next_c) => {
            if (next_c instanceof $Empty) {
              return new Ok([$list.fold(rest, new_left2, append), new_right]);
            } else {
              let $ = next_c.tail;
              if ($ instanceof $Empty) {
                let single = next_c.head;
                return inner_loop(rest, single, new_left2, new_right);
              } else {
                let multi = next_c;
                return $result.try$(
                  transform_x(rest, multi),
                  (_use0) => {
                    let p0 = _use0[0];
                    let p1 = _use0[1];
                    return new Ok(
                      [
                        $list.fold(p0, new_left2, append),
                        $list.fold(p1, new_right, append),
                      ],
                    );
                  },
                );
              }
            }
          },
        );
      },
    );
  }
}

function do_transform_x(right_operation, left_operation, new_right) {
  if (right_operation instanceof $Empty) {
    return new Ok([left_operation, new_right]);
  } else {
    let right_c = right_operation.head;
    let rest_right = right_operation.tail;
    return $result.try$(
      inner_loop(left_operation, right_c, $List$Empty$const, new_right),
      (_use0) => {
        let new_left = _use0[0];
        let new_right2 = _use0[1];
        return do_transform_x(rest_right, new_left, new_right2);
      },
    );
  }
}

/**
 * The `transformX` function of json0. It cross-transforms two operations in N²
 * steps, and it returns `#(leftOp', rightOp')`.
 * 
 * @ignore
 */
function transform_x(left_operation, right_operation) {
  return do_transform_x(right_operation, left_operation, $List$Empty$const);
}

/**
 * Transform `operation` so that it applies after `other`. `side` breaks a tie,
 * and it is the `left` and `right` pair of json0. The TP1 property holds: for
 * any concurrent pair, `apply(apply(d,a), transform(b,a,Rgt)) ==
 * apply(apply(d,b), transform(a,b,Lft))`.
 */
export function transform(operation, other, side) {
  if (other instanceof $Empty) {
    return new Ok(operation);
  } else {
    if (operation instanceof $Empty) {
      if (side instanceof Lft) {
        let _pipe = transform_x(operation, other);
        return $result.map(_pipe, (pair) => { return pair[0]; });
      } else {
        let _pipe = transform_x(other, operation);
        return $result.map(_pipe, (pair) => { return pair[1]; });
      }
    } else if (other instanceof $Empty) {
      if (side instanceof Lft) {
        let _pipe = transform_x(operation, other);
        return $result.map(_pipe, (pair) => { return pair[0]; });
      } else {
        let _pipe = transform_x(other, operation);
        return $result.map(_pipe, (pair) => { return pair[1]; });
      }
    } else {
      let $ = operation.tail;
      if ($ instanceof $Empty) {
        let $1 = other.tail;
        if ($1 instanceof $Empty) {
          let a = operation.head;
          let b = other.head;
          return transform_component_into($List$Empty$const, a, b, side);
        } else {
          if (side instanceof Lft) {
            let _pipe = transform_x(operation, other);
            return $result.map(_pipe, (pair) => { return pair[0]; });
          } else {
            let _pipe = transform_x(other, operation);
            return $result.map(_pipe, (pair) => { return pair[1]; });
          }
        }
      } else {
        if (side instanceof Lft) {
          let _pipe = transform_x(operation, other);
          return $result.map(_pipe, (pair) => { return pair[0]; });
        } else {
          let _pipe = transform_x(other, operation);
          return $result.map(_pipe, (pair) => { return pair[1]; });
        }
      }
    }
  }
}

function text0_invert(operation) {
  let $ = text0_parse_operation(operation);
  if ($ instanceof Ok) {
    let components = $[0];
    let _pipe = components;
    let _pipe$1 = $list.reverse(_pipe);
    let _pipe$2 = $list.map(
      _pipe$1,
      (c) => {
        if (c instanceof TextInsert) {
          let p = c.p;
          let s = c.s;
          return new TextDelete(p, s);
        } else {
          let p = c.p;
          let s = c.s;
          return new TextInsert(p, s);
        }
      },
    );
    return text0_serialize_operation(_pipe$2);
  } else {
    return operation;
  }
}

/**
 * Invert a subtype operation. This is an identity placeholder until rung 4
 * adds text0.
 * 
 * @ignore
 */
function invert_subtype(name, operation) {
  if (name === "text0") {
    return text0_invert(operation);
  } else {
    return operation;
  }
}

function invert_component(c) {
  let _block;
  let _record = empty(c.path);
  _block = new Component(
    _record.path,
    c.object_delete,
    c.object_insert,
    c.list_delete,
    c.list_insert,
    _record.list_move,
    $option.map(c.na, num_negate),
    $option.map(
      c.subtype,
      (pair) => { return [pair[0], invert_subtype(pair[0], pair[1])]; },
    ),
  );
  let base = _block;
  let $ = c.list_move;
  if ($ instanceof Some) {
    let target = $[0];
    let $1 = split_last(c.path);
    if ($1 instanceof Ok) {
      let parent = $1[0][0];
      let last = $1[0][1];
      let _block$1;
      if (last instanceof Key) {
        _block$1 = 0;
      } else {
        let index = last[0];
        _block$1 = index;
      }
      let last_index = _block$1;
      return new Component(
        $list.append(parent, toList([new Index(target)])),
        base.object_insert,
        base.object_delete,
        base.list_insert,
        base.list_delete,
        new Some(last_index),
        base.na,
        base.subtype,
      );
    } else {
      return base;
    }
  } else {
    return base;
  }
}

/**
 * Invert an operation, so that `apply(apply(document, operation),
 * invert(operation)) == document`. A delete carries its pre-image, so the
 * caller needs no external snapshot.
 */
export function invert(operation) {
  let _pipe = $list.reverse(operation);
  return $list.map(_pipe, invert_component);
}

/**
 * Encode a value to `gleam/json` for the wire.
 */
export function to_json(value) {
  if (value instanceof VNull) {
    return $json.null$();
  } else if (value instanceof VBool) {
    let b = value[0];
    return $json.bool(b);
  } else if (value instanceof VNumber) {
    let $ = value[0];
    if ($ instanceof NInt) {
      let i = $[0];
      return $json.int(i);
    } else {
      let f = $[0];
      return $json.float(f);
    }
  } else if (value instanceof VString) {
    let s = value[0];
    return $json.string(s);
  } else if (value instanceof VArray) {
    let items = value[0];
    return $json.array(items, to_json);
  } else {
    let members = value[0];
    return $json.object(
      $list.map(members, (pair) => { return [pair[0], to_json(pair[1])]; }),
    );
  }
}

function dict_to_sorted_list(d) {
  let _pipe = $dict.to_list(d);
  return $list.sort(_pipe, (a, b) => { return $string.compare(a[0], b[0]); });
}

/**
 * A decoder for a `JsonValue` from parsed JSON.
 */
export function decoder() {
  let non_null = $decode.one_of(
    (() => {
      let _pipe = $decode.string;
      return $decode.map(_pipe, (var0) => { return new VString(var0); });
    })(),
    toList([
      (() => {
        let _pipe = $decode.bool;
        return $decode.map(_pipe, (var0) => { return new VBool(var0); });
      })(),
      (() => {
        let _pipe = $decode.int;
        return $decode.map(_pipe, (i) => { return new VNumber(new NInt(i)); });
      })(),
      (() => {
        let _pipe = $decode.float;
        return $decode.map(_pipe, (f) => { return new VNumber(new NFloat(f)); });
      })(),
      (() => {
        let _pipe = $decode.list($decode.recursive(decoder));
        return $decode.map(_pipe, (var0) => { return new VArray(var0); });
      })(),
      (() => {
        let _pipe = $decode.dict($decode.string, $decode.recursive(decoder));
        return $decode.map(
          _pipe,
          (d) => { return new VObject(dict_to_sorted_list(d)); },
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
        return JsonValue$VNull$const;
      }
    },
  );
}

/**
 * Parse a JSON string into a `JsonValue`. The tests and the summaries use
 * this function.
 */
export function parse_json(raw) {
  let $ = $json.parse(raw, decoder());
  if ($ instanceof Ok) {
    return $;
  } else {
    return new Error(undefined);
  }
}

function num_to_json(n) {
  if (n instanceof NInt) {
    let i = n[0];
    return $json.int(i);
  } else {
    let f = n[0];
    return $json.float(f);
  }
}

function append_field(fields, key, value, encode) {
  if (value instanceof Some) {
    let v = value[0];
    return $list.append(fields, toList([[key, encode(v)]]));
  } else {
    return fields;
  }
}

function path_key_to_json(key) {
  if (key instanceof Key) {
    let s = key[0];
    return $json.string(s);
  } else {
    let i = key[0];
    return $json.int(i);
  }
}

function component_to_json(c) {
  let fields = toList([["p", $json.array(c.path, path_key_to_json)]]);
  let fields$1 = append_field(fields, "oi", c.object_insert, to_json);
  let fields$2 = append_field(fields$1, "od", c.object_delete, to_json);
  let fields$3 = append_field(fields$2, "li", c.list_insert, to_json);
  let fields$4 = append_field(fields$3, "ld", c.list_delete, to_json);
  let fields$5 = append_field(fields$4, "lm", c.list_move, $json.int);
  let fields$6 = append_field(fields$5, "na", c.na, num_to_json);
  let _block;
  let $ = c.subtype;
  if ($ instanceof Some) {
    let name = $[0][0];
    let sub_operation = $[0][1];
    _block = $list.append(
      fields$6,
      toList([["t", $json.string(name)], ["o", to_json(sub_operation)]]),
    );
  } else {
    _block = fields$6;
  }
  let fields$7 = _block;
  return $json.object(fields$7);
}

/**
 * Encode an operation as a json0 component array:
 * `[{p, oi?, od?, li?, ld?, lm?, na?, t?/o?}, …]`. A path is an array of
 * strings, which are object keys, or of integers, which are indices. Each
 * value goes through `to_json` and back. The `#(name, operation)` pair of a
 * subtype becomes the `t` and `o` fields.
 */
export function operation_to_json(operation) {
  return $json.array(operation, component_to_json);
}

function subtype_name_opt_decoder() {
  return $decode.map($decode.string, (var0) => { return new Some(var0); });
}

function num_opt_decoder() {
  return $decode.one_of(
    $decode.map($decode.int, (i) => { return new Some(new NInt(i)); }),
    toList([
      $decode.map($decode.float, (f) => { return new Some(new NFloat(f)); }),
    ]),
  );
}

function value_opt_decoder() {
  return $decode.map(decoder(), (var0) => { return new Some(var0); });
}

function path_key_decoder() {
  return $decode.one_of(
    $decode.map($decode.int, (var0) => { return new Index(var0); }),
    toList([$decode.map($decode.string, (var0) => { return new Key(var0); })]),
  );
}

function component_decoder() {
  return $decode.field(
    "p",
    $decode.list(path_key_decoder()),
    (path) => {
      return $decode.optional_field(
        "oi",
        Option$None$const,
        value_opt_decoder(),
        (object_insert) => {
          return $decode.optional_field(
            "od",
            Option$None$const,
            value_opt_decoder(),
            (object_delete) => {
              return $decode.optional_field(
                "li",
                Option$None$const,
                value_opt_decoder(),
                (list_insert) => {
                  return $decode.optional_field(
                    "ld",
                    Option$None$const,
                    value_opt_decoder(),
                    (list_delete) => {
                      return $decode.optional_field(
                        "lm",
                        Option$None$const,
                        $decode.map(
                          $decode.int,
                          (var0) => { return new Some(var0); },
                        ),
                        (list_move) => {
                          return $decode.optional_field(
                            "na",
                            Option$None$const,
                            num_opt_decoder(),
                            (na) => {
                              return $decode.optional_field(
                                "t",
                                Option$None$const,
                                subtype_name_opt_decoder(),
                                (subtype) => {
                                  return $decode.optional_field(
                                    "o",
                                    JsonValue$VNull$const,
                                    decoder(),
                                    (sub_operation) => {
                                      let _block;
                                      if (subtype instanceof Some) {
                                        let name = subtype[0];
                                        _block = new Some([name, sub_operation]);
                                      } else {
                                        _block = subtype;
                                      }
                                      let subtype$1 = _block;
                                      return $decode.success(
                                        new Component(
                                          path,
                                          object_insert,
                                          object_delete,
                                          list_insert,
                                          list_delete,
                                          list_move,
                                          na,
                                          subtype$1,
                                        ),
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
}

/**
 * The decoder for a json0 operation from parsed JSON. It is the inverse of
 * `operation_to_json`.
 */
export function operation_decoder() {
  return $decode.list(component_decoder());
}

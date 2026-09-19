/// <reference types="./map_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../gleam.mjs";

export class MapState extends $CustomType {
  constructor(sequenced, insertion_order, pending) {
    super();
    this.sequenced = sequenced;
    this.insertion_order = insertion_order;
    this.pending = pending;
  }
}
export const MapState$MapState = (sequenced, insertion_order, pending) =>
  new MapState(sequenced, insertion_order, pending);
export const MapState$isMapState = (value) => value instanceof MapState;
export const MapState$MapState$sequenced = (value) => value.sequenced;
export const MapState$MapState$0 = (value) => value.sequenced;
export const MapState$MapState$insertion_order = (value) =>
  value.insertion_order;
export const MapState$MapState$1 = (value) => value.insertion_order;
export const MapState$MapState$pending = (value) => value.pending;
export const MapState$MapState$2 = (value) => value.pending;

/**
 * One or more consecutive local sets to one key, oldest first. A delete or
 * a clear ends the lifetime. A later set starts a new lifetime.
 */
export class PendingLifetime extends $CustomType {
  constructor(key, sets) {
    super();
    this.key = key;
    this.sets = sets;
  }
}
export const PendingEntry$PendingLifetime = (key, sets) =>
  new PendingLifetime(key, sets);
export const PendingEntry$isPendingLifetime = (value) =>
  value instanceof PendingLifetime;
export const PendingEntry$PendingLifetime$key = (value) => value.key;
export const PendingEntry$PendingLifetime$0 = (value) => value.key;
export const PendingEntry$PendingLifetime$sets = (value) => value.sets;
export const PendingEntry$PendingLifetime$1 = (value) => value.sets;

export class PendingDelete extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const PendingEntry$PendingDelete = (key) => new PendingDelete(key);
export const PendingEntry$isPendingDelete = (value) =>
  value instanceof PendingDelete;
export const PendingEntry$PendingDelete$key = (value) => value.key;
export const PendingEntry$PendingDelete$0 = (value) => value.key;

export class PendingClear extends $CustomType {}
export const PendingEntry$PendingClear$const = new PendingClear();
export const PendingEntry$PendingClear = () => PendingEntry$PendingClear$const;
export const PendingEntry$isPendingClear = (value) =>
  value instanceof PendingClear;

export class Set extends $CustomType {
  constructor(key, value) {
    super();
    this.key = key;
    this.value = value;
  }
}
export const MapOperation$Set = (key, value) => new Set(key, value);
export const MapOperation$isSet = (value) => value instanceof Set;
export const MapOperation$Set$key = (value) => value.key;
export const MapOperation$Set$0 = (value) => value.key;
export const MapOperation$Set$value = (value) => value.value;
export const MapOperation$Set$1 = (value) => value.value;

export class Delete extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const MapOperation$Delete = (key) => new Delete(key);
export const MapOperation$isDelete = (value) => value instanceof Delete;
export const MapOperation$Delete$key = (value) => value.key;
export const MapOperation$Delete$0 = (value) => value.key;

export class Clear extends $CustomType {}
export const MapOperation$Clear$const = new Clear();
export const MapOperation$Clear = () => MapOperation$Clear$const;
export const MapOperation$isClear = (value) => value instanceof Clear;

/**
 * `value: None` means that a delete or a clear removed the key.
 */
export class ValueChanged extends $CustomType {
  constructor(key, previous_value, value, local) {
    super();
    this.key = key;
    this.previous_value = previous_value;
    this.value = value;
    this.local = local;
  }
}
export const MapEvent$ValueChanged = (key, previous_value, value, local) =>
  new ValueChanged(key, previous_value, value, local);
export const MapEvent$isValueChanged = (value) => value instanceof ValueChanged;
export const MapEvent$ValueChanged$key = (value) => value.key;
export const MapEvent$ValueChanged$0 = (value) => value.key;
export const MapEvent$ValueChanged$previous_value = (value) =>
  value.previous_value;
export const MapEvent$ValueChanged$1 = (value) => value.previous_value;
export const MapEvent$ValueChanged$value = (value) => value.value;
export const MapEvent$ValueChanged$2 = (value) => value.value;
export const MapEvent$ValueChanged$local = (value) => value.local;
export const MapEvent$ValueChanged$3 = (value) => value.local;

export class Cleared extends $CustomType {
  constructor(local) {
    super();
    this.local = local;
  }
}
export const MapEvent$Cleared = (local) => new Cleared(local);
export const MapEvent$isCleared = (value) => value instanceof Cleared;
export const MapEvent$Cleared$local = (value) => value.local;
export const MapEvent$Cleared$0 = (value) => value.local;

export class UnexpectedAck extends $CustomType {
  constructor(operation, detail) {
    super();
    this.operation = operation;
    this.detail = detail;
  }
}
export const KernelError$UnexpectedAck = (operation, detail) =>
  new UnexpectedAck(operation, detail);
export const KernelError$isUnexpectedAck = (value) =>
  value instanceof UnexpectedAck;
export const KernelError$UnexpectedAck$operation = (value) => value.operation;
export const KernelError$UnexpectedAck$0 = (value) => value.operation;
export const KernelError$UnexpectedAck$detail = (value) => value.detail;
export const KernelError$UnexpectedAck$1 = (value) => value.detail;

export function new$() {
  return new MapState($dict.new$(), $List$Empty$const, $List$Empty$const);
}

/**
 * Build a state that contains sequenced data only, from the summary snapshot
 * entries. The function keeps the supplied insertion order. Use it to start a
 * connection from a stored summary, before you replay the deltas that follow
 * that summary. A snapshot that you load has no pending local edits.
 */
export function from_sequenced(entries) {
  let $ = $list.fold(
    entries,
    [$dict.new$(), $List$Empty$const],
    (acc, entry) => {
      let sequenced = acc[0];
      let order = acc[1];
      let key = entry[0];
      let value = entry[1];
      let _block;
      let $1 = $dict.has_key(sequenced, key);
      if ($1) {
        _block = order;
      } else {
        _block = listPrepend(key, order);
      }
      let order$1 = _block;
      return [$dict.insert(sequenced, key, value), order$1];
    },
  );
  let sequenced = $[0];
  let order = $[1];
  return new MapState(sequenced, $list.reverse(order), $List$Empty$const);
}

/**
 * The sequenced entries in insertion order. This function ignores the pending
 * local edits. A summary snapshot captures this confirmed state.
 */
export function sequenced_entries(state) {
  return $list.filter_map(
    state.insertion_order,
    (key) => {
      let $ = $dict.get(state.sequenced, key);
      if ($ instanceof Ok) {
        let value = $[0];
        return new Ok([key, value]);
      } else {
        return new Error(undefined);
      }
    },
  );
}

function pending_matches_key(entry, key) {
  if (entry instanceof PendingLifetime) {
    let k = entry.key;
    return k === key;
  } else if (entry instanceof PendingDelete) {
    let k = entry.key;
    return k === key;
  } else {
    return true;
  }
}

/**
 * The most recent pending entry that affects `key`. That entry is a lifetime
 * of the key, a delete of the key, or a clear. The TypeScript kernel uses
 * `findLast` with the same predicate.
 * 
 * @ignore
 */
function latest_pending_for(pending, key) {
  let _pipe = $list.reverse(pending);
  return $list.find(
    _pipe,
    (entry) => { return pending_matches_key(entry, key); },
  );
}

/**
 * An optimistic read: the sequenced data with the pending local changes over
 * it. The result is `Error(Nil)` when the map holds no value for the key.
 */
export function get(state, key) {
  let $ = latest_pending_for(state.pending, key);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof PendingLifetime) {
      let sets = $1.sets;
      return $list.last(sets);
    } else if ($1 instanceof PendingDelete) {
      return new Error(undefined);
    } else {
      return new Error(undefined);
    }
  } else {
    return $dict.get(state.sequenced, key);
  }
}

export function has(state, key) {
  return $result.is_ok(get(state, key));
}

function last_delete_or_clear_index(indexed, key) {
  return $list.fold(
    indexed,
    -1,
    (acc, pair) => {
      let $ = pair[1];
      if ($ instanceof PendingLifetime) {
        return acc;
      } else if ($ instanceof PendingDelete) {
        let k = $.key;
        if (k === key) {
          return pair[0];
        } else {
          return acc;
        }
      } else {
        return pair[0];
      }
    },
  );
}

function has_pending_delete_or_clear(pending, key) {
  return $list.any(
    pending,
    (entry) => {
      if (entry instanceof PendingLifetime) {
        return false;
      } else if (entry instanceof PendingDelete) {
        let k = entry.key;
        return k === key;
      } else {
        return true;
      }
    },
  );
}

/**
 * The entries that are observable optimistically, in the order of the
 * TypeScript iterator. The sequenced keys come first, in insertion order, and
 * the function skips each key that has a pending delete or clear. The pending
 * lifetimes come after, and the function keeps only those that a later delete
 * or clear does not remove.
 */
export function entries(state) {
  let sequenced_phase = $list.filter_map(
    state.insertion_order,
    (key) => {
      let $ = has_pending_delete_or_clear(state.pending, key);
      if ($) {
        return new Error(undefined);
      } else {
        let _pipe = get(state, key);
        return $result.map(_pipe, (value) => { return [key, value]; });
      }
    },
  );
  let indexed = $list.index_map(
    state.pending,
    (entry, i) => { return [i, entry]; },
  );
  let pending_phase = $list.filter_map(
    indexed,
    (pair) => {
      let index = pair[0];
      let entry = pair[1];
      if (entry instanceof PendingLifetime) {
        let key = entry.key;
        let sets = entry.sets;
        let last_dc = last_delete_or_clear_index(indexed, key);
        let survives = index > last_dc;
        let already_iterated = $dict.has_key(state.sequenced, key) && (last_dc === -1);
        let $ = survives && !already_iterated;
        if ($) {
          let _pipe = $list.last(sets);
          return $result.map(_pipe, (value) => { return [key, value]; });
        } else {
          return new Error(undefined);
        }
      } else if (entry instanceof PendingDelete) {
        return new Error(undefined);
      } else {
        return new Error(undefined);
      }
    },
  );
  return $list.append(sequenced_phase, pending_phase);
}

export function size(state) {
  return $list.length(entries(state));
}

export function keys(state) {
  let _pipe = entries(state);
  return $list.map(_pipe, (entry) => { return entry[0]; });
}

function do_append_to_first_lifetime(reversed, key, value) {
  if (reversed instanceof $Empty) {
    return reversed;
  } else {
    let $ = reversed.head;
    if ($ instanceof PendingLifetime) {
      let k = $.key;
      if (k === key) {
        let rest = reversed.tail;
        let sets = $.sets;
        return listPrepend(
          new PendingLifetime(k, $list.append(sets, toList([value]))),
          rest,
        );
      } else {
        let entry = $;
        let rest = reversed.tail;
        return listPrepend(entry, do_append_to_first_lifetime(rest, key, value));
      }
    } else {
      let entry = $;
      let rest = reversed.tail;
      return listPrepend(entry, do_append_to_first_lifetime(rest, key, value));
    }
  }
}

/**
 * Append a set to the most recent pending entry for `key`. The caller must
 * have confirmed that the entry is a lifetime.
 * 
 * @ignore
 */
function append_to_latest_lifetime(pending, key, value) {
  let _pipe = $list.reverse(pending);
  let _pipe$1 = do_append_to_first_lifetime(_pipe, key, value);
  return $list.reverse(_pipe$1);
}

export function set(state, key, value) {
  let previous = get(state, key);
  let _block;
  let $ = latest_pending_for(state.pending, key);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof PendingLifetime) {
      _block = append_to_latest_lifetime(state.pending, key, value);
    } else if ($1 instanceof PendingDelete) {
      _block = $list.append(
        state.pending,
        toList([new PendingLifetime(key, toList([value]))]),
      );
    } else {
      _block = $list.append(
        state.pending,
        toList([new PendingLifetime(key, toList([value]))]),
      );
    }
  } else {
    _block = $list.append(
      state.pending,
      toList([new PendingLifetime(key, toList([value]))]),
    );
  }
  let pending = _block;
  return [
    new MapState(state.sequenced, state.insertion_order, pending),
    toList([
      new ValueChanged(
        key,
        $option.from_result(previous),
        new Some(value),
        true,
      ),
    ]),
    new Set(key, value),
  ];
}

export function delete$(state, key) {
  let previous = get(state, key);
  let pending = $list.append(state.pending, toList([new PendingDelete(key)]));
  let _block;
  if (previous instanceof Ok) {
    let value = previous[0];
    _block = toList([
      new ValueChanged(key, new Some(value), Option$None$const, true),
    ]);
  } else {
    _block = $List$Empty$const;
  }
  let events = _block;
  return [
    new MapState(state.sequenced, state.insertion_order, pending),
    events,
    new Delete(key),
  ];
}

export function clear(state) {
  let visible = entries(state);
  let pending = $list.append(
    state.pending,
    toList([PendingEntry$PendingClear$const]),
  );
  let events = listPrepend(
    new Cleared(true),
    $list.map(
      visible,
      (entry) => {
        return new ValueChanged(
          entry[0],
          new Some(entry[1]),
          Option$None$const,
          true,
        );
      },
    ),
  );
  return [
    new MapState(state.sequenced, state.insertion_order, pending),
    events,
    MapOperation$Clear$const,
  ];
}

function has_pending_entry_for_key(pending, key) {
  return $list.any(
    pending,
    (entry) => {
      if (entry instanceof PendingLifetime) {
        let k = entry.key;
        return k === key;
      } else if (entry instanceof PendingDelete) {
        let k = entry.key;
        return k === key;
      } else {
        return false;
      }
    },
  );
}

function has_pending_for(pending, key) {
  return $list.any(
    pending,
    (entry) => { return pending_matches_key(entry, key); },
  );
}

/**
 * Apply a sequenced operation from another client. The kernel suppresses the
 * events when the pending local changes hide the remote change in the
 * optimistic view.
 */
export function apply_remote(state, operation) {
  if (operation instanceof Set) {
    let key = operation.key;
    let value = operation.value;
    let _block;
    let _pipe = $dict.get(state.sequenced, key);
    _block = $option.from_result(_pipe);
    let previous = _block;
    let _block$1;
    let $ = $dict.has_key(state.sequenced, key);
    if ($) {
      _block$1 = state.insertion_order;
    } else {
      _block$1 = $list.append(state.insertion_order, toList([key]));
    }
    let insertion_order = _block$1;
    let sequenced = $dict.insert(state.sequenced, key, value);
    let _block$2;
    let $1 = has_pending_for(state.pending, key);
    if ($1) {
      _block$2 = $List$Empty$const;
    } else {
      _block$2 = toList([
        new ValueChanged(key, previous, new Some(value), false),
      ]);
    }
    let events = _block$2;
    return [new MapState(sequenced, insertion_order, state.pending), events];
  } else if (operation instanceof Delete) {
    let key = operation.key;
    let _block;
    let _pipe = $dict.get(state.sequenced, key);
    _block = $option.from_result(_pipe);
    let previous = _block;
    let sequenced = $dict.delete$(state.sequenced, key);
    let insertion_order = $list.filter(
      state.insertion_order,
      (k) => { return k !== key; },
    );
    let _block$1;
    let $ = has_pending_for(state.pending, key);
    if ($) {
      _block$1 = $List$Empty$const;
    } else {
      _block$1 = toList([
        new ValueChanged(key, previous, Option$None$const, false),
      ]);
    }
    let events = _block$1;
    return [new MapState(sequenced, insertion_order, state.pending), events];
  } else {
    let deleted = $list.filter_map(
      state.insertion_order,
      (key) => {
        let $ = has_pending_entry_for_key(state.pending, key);
        if ($) {
          return new Error(undefined);
        } else {
          let _pipe = $dict.get(state.sequenced, key);
          return $result.map(_pipe, (value) => { return [key, value]; });
        }
      },
    );
    let has_pending_clear = $list.any(
      state.pending,
      (entry) => { return entry instanceof PendingClear; },
    );
    let _block;
    if (has_pending_clear) {
      _block = $List$Empty$const;
    } else {
      _block = listPrepend(
        new Cleared(false),
        $list.map(
          deleted,
          (entry) => {
            return new ValueChanged(
              entry[0],
              new Some(entry[1]),
              Option$None$const,
              false,
            );
          },
        ),
      );
    }
    let events = _block;
    return [
      new MapState($dict.new$(), $List$Empty$const, state.pending),
      events,
    ];
  }
}

function do_split_at_first_for_key(loop$pending, loop$key, loop$seen) {
  while (true) {
    let pending = loop$pending;
    let key = loop$key;
    let seen = loop$seen;
    if (pending instanceof $Empty) {
      return new Error(undefined);
    } else {
      let $ = pending.head;
      if ($ instanceof PendingLifetime) {
        let k = $.key;
        if (k === key) {
          let entry = $;
          let rest = pending.tail;
          return new Ok([$list.reverse(seen), entry, rest]);
        } else {
          let entry = $;
          let rest = pending.tail;
          loop$pending = rest;
          loop$key = key;
          loop$seen = listPrepend(entry, seen);
        }
      } else if ($ instanceof PendingDelete) {
        let k = $.key;
        if (k === key) {
          let entry = $;
          let rest = pending.tail;
          return new Ok([$list.reverse(seen), entry, rest]);
        } else {
          let entry = $;
          let rest = pending.tail;
          loop$pending = rest;
          loop$key = key;
          loop$seen = listPrepend(entry, seen);
        }
      } else {
        let entry = $;
        let rest = pending.tail;
        loop$pending = rest;
        loop$key = key;
        loop$seen = listPrepend(entry, seen);
      }
    }
  }
}

/**
 * Split the pending queue at the first entry for `key` that is not a clear.
 * The TypeScript kernel uses `findIndex` in its local ack handlers.
 * 
 * @ignore
 */
function split_at_first_for_key(pending, key) {
  return do_split_at_first_for_key(pending, key, $List$Empty$const);
}

/**
 * Commit an acked local operation, which moves it from `pending` to
 * `sequenced`. The acks must arrive in submission order. A mismatch means that
 * the runtime routed an ack for an operation that the kernel never submitted,
 * or that it routed the acks out of order. Either condition is fatal.
 *
 * An ack never emits an event. The optimistic view already showed the
 * operation at submit time.
 */
export function ack_local(state, operation) {
  if (operation instanceof Set) {
    let key = operation.key;
    let $ = split_at_first_for_key(state.pending, key);
    if ($ instanceof Ok) {
      let $1 = $[0][1];
      if ($1 instanceof PendingLifetime) {
        let $2 = $1.sets;
        if ($2 instanceof $Empty) {
          return new Error(
            new UnexpectedAck(
              operation,
              "expected pending lifetime for key " + key,
            ),
          );
        } else {
          let before = $[0][0];
          let after = $[0][2];
          let acked_value = $2.head;
          let remaining_sets = $2.tail;
          let _block;
          if (remaining_sets instanceof $Empty) {
            _block = $list.append(before, after);
          } else {
            _block = $list.append(
              before,
              listPrepend(new PendingLifetime(key, remaining_sets), after),
            );
          }
          let pending = _block;
          let _block$1;
          let $3 = $dict.has_key(state.sequenced, key);
          if ($3) {
            _block$1 = state.insertion_order;
          } else {
            _block$1 = $list.append(state.insertion_order, toList([key]));
          }
          let insertion_order = _block$1;
          return new Ok(
            new MapState(
              $dict.insert(state.sequenced, key, acked_value),
              insertion_order,
              pending,
            ),
          );
        }
      } else if ($1 instanceof PendingDelete) {
        return new Error(
          new UnexpectedAck(
            operation,
            "expected pending lifetime for key " + key,
          ),
        );
      } else {
        return new Error(
          new UnexpectedAck(
            operation,
            "expected pending lifetime for key " + key,
          ),
        );
      }
    } else {
      return new Error(
        new UnexpectedAck(operation, "expected pending lifetime for key " + key),
      );
    }
  } else if (operation instanceof Delete) {
    let key = operation.key;
    let $ = split_at_first_for_key(state.pending, key);
    if ($ instanceof Ok) {
      let $1 = $[0][1];
      if ($1 instanceof PendingLifetime) {
        return new Error(
          new UnexpectedAck(operation, "expected pending delete for key " + key),
        );
      } else if ($1 instanceof PendingDelete) {
        let before = $[0][0];
        let after = $[0][2];
        return new Ok(
          new MapState(
            $dict.delete$(state.sequenced, key),
            $list.filter(state.insertion_order, (k) => { return k !== key; }),
            $list.append(before, after),
          ),
        );
      } else {
        return new Error(
          new UnexpectedAck(operation, "expected pending delete for key " + key),
        );
      }
    } else {
      return new Error(
        new UnexpectedAck(operation, "expected pending delete for key " + key),
      );
    }
  } else {
    let $ = state.pending;
    if ($ instanceof $Empty) {
      return new Error(
        new UnexpectedAck(operation, "expected pending clear at queue head"),
      );
    } else {
      let $1 = $.head;
      if ($1 instanceof PendingClear) {
        let rest = $.tail;
        return new Ok(new MapState($dict.new$(), $List$Empty$const, rest));
      } else {
        return new Error(
          new UnexpectedAck(operation, "expected pending clear at queue head"),
        );
      }
    }
  }
}

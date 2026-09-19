/// <reference types="./or_map_engine.d.mts" />
import * as $dict from "../../../gleam_stdlib/gleam/dict.mjs";
import * as $int from "../../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../../gleam_stdlib/gleam/option.mjs";
import { Option$None$const } from "../../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../../gleam_stdlib/gleam/order.mjs";
import { Eq, Lt, Order$Lt$const, Order$Eq$const, Order$Gt$const } from "../../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../../lattice_core/lattice_core/version_vector.mjs";
import * as $or_set from "../../../lattice_sets/lattice_sets/or_set.mjs";
import { Ok, toList, CustomType as $CustomType } from "../../gleam.mjs";

export class Initial extends $CustomType {}
export const Generation$Initial$const = new Initial();
export const Generation$Initial = () => Generation$Initial$const;
export const Generation$isInitial = (value) => value instanceof Initial;

export class Generation extends $CustomType {
  constructor(clock, creator) {
    super();
    this.clock = clock;
    this.creator = creator;
  }
}
export const Generation$Generation = (clock, creator) =>
  new Generation(clock, creator);
export const Generation$isGeneration = (value) => value instanceof Generation;
export const Generation$Generation$clock = (value) => value.clock;
export const Generation$Generation$0 = (value) => value.clock;
export const Generation$Generation$creator = (value) => value.creator;
export const Generation$Generation$1 = (value) => value.creator;

export class Entry extends $CustomType {
  constructor(generation, membership, value) {
    super();
    this.generation = generation;
    this.membership = membership;
    this.value = value;
  }
}
export const Entry$Entry = (generation, membership, value) =>
  new Entry(generation, membership, value);
export const Entry$isEntry = (value) => value instanceof Entry;
export const Entry$Entry$generation = (value) => value.generation;
export const Entry$Entry$0 = (value) => value.generation;
export const Entry$Entry$membership = (value) => value.membership;
export const Entry$Entry$1 = (value) => value.membership;
export const Entry$Entry$value = (value) => value.value;
export const Entry$Entry$2 = (value) => value.value;

export class State extends $CustomType {
  constructor(clock, entries) {
    super();
    this.clock = clock;
    this.entries = entries;
  }
}
export const State$State = (clock, entries) => new State(clock, entries);
export const State$isState = (value) => value instanceof State;
export const State$State$clock = (value) => value.clock;
export const State$State$0 = (value) => value.clock;
export const State$State$entries = (value) => value.entries;
export const State$State$1 = (value) => value.entries;

export function new$() {
  return new State(0, $dict.new$());
}

export function compare(a, b) {
  if (a instanceof Initial) {
    if (b instanceof Initial) {
      return Order$Eq$const;
    } else {
      return Order$Lt$const;
    }
  } else if (b instanceof Initial) {
    return Order$Gt$const;
  } else {
    let ac = a.clock;
    let ar = a.creator;
    let bc = b.clock;
    let br = b.creator;
    let $ = $int.compare(ac, bc);
    if ($ instanceof Eq) {
      return $replica_id.compare(ar, br);
    } else {
      return $;
    }
  }
}

export function clock(generation) {
  if (generation instanceof Initial) {
    return 0;
  } else {
    let clock$1 = generation.clock;
    return clock$1;
  }
}

export function active(entry, key) {
  return $or_set.contains(entry.membership, key);
}

export function prepare(state, key, writer) {
  let $ = $dict.get(state.entries, key);
  if ($ instanceof Ok) {
    let entry = $[0];
    let $1 = active(entry, key);
    if ($1) {
      return new Entry(
        entry.generation,
        $or_set.merge($or_set.new$(writer), entry.membership),
        entry.value,
      );
    } else {
      return new Entry(
        new Generation(state.clock + 1, writer),
        $or_set.new$(writer),
        Option$None$const,
      );
    }
  } else {
    return new Entry(
      Generation$Initial$const,
      $or_set.new$(writer),
      Option$None$const,
    );
  }
}

export function singleton(key, entry, high_water) {
  return new State(
    $int.max(high_water, clock(entry.generation)),
    $dict.from_list(toList([[key, entry]])),
  );
}

export function remove(state, key) {
  let $ = $dict.get(state.entries, key);
  if ($ instanceof Ok) {
    let entry = $[0];
    let $1 = $or_set.remove_with_delta(entry.membership, key);
    let membership = $1[0];
    let delta = $1[1];
    return [
      new State(
        state.clock,
        $dict.insert(
          state.entries,
          key,
          new Entry(entry.generation, membership, entry.value),
        ),
      ),
      singleton(
        key,
        new Entry(entry.generation, delta, Option$None$const),
        state.clock,
      ),
    ];
  } else {
    return [state, new$()];
  }
}

/**
 * Select generations before joining values. Absence is never an older baseline.
 */
export function join(a, b, combine) {
  let _block;
  let _pipe = $dict.to_list(a.entries);
  _block = $list.map(
    _pipe,
    (pair) => { return [pair[0], pair[1], $dict.get(b.entries, pair[0])]; },
  );
  let entries = _block;
  let _block$1;
  let _pipe$1 = $dict.to_list(b.entries);
  _block$1 = $list.filter(
    _pipe$1,
    (pair) => { return !$dict.has_key(a.entries, pair[0]); },
  );
  let only_b = _block$1;
  return $result.try$(
    $list.try_fold(
      entries,
      $dict.new$(),
      (entries, pair) => {
        let key = pair[0];
        let a$1 = pair[1];
        let b$1 = pair[2];
        let _block$2;
        if (b$1 instanceof Ok) {
          let b$2 = b$1[0];
          let $1 = compare(a$1.generation, b$2.generation);
          if ($1 instanceof Lt) {
            _block$2 = [
              b$2.generation,
              b$2.membership,
              Option$None$const,
              b$2.value,
            ];
          } else if ($1 instanceof Eq) {
            _block$2 = [
              a$1.generation,
              $or_set.merge(a$1.membership, b$2.membership),
              a$1.value,
              b$2.value,
            ];
          } else {
            _block$2 = [
              a$1.generation,
              a$1.membership,
              a$1.value,
              Option$None$const,
            ];
          }
        } else {
          _block$2 = [
            a$1.generation,
            a$1.membership,
            a$1.value,
            Option$None$const,
          ];
        }
        let $ = _block$2;
        let generation = $[0];
        let membership = $[1];
        let left = $[2];
        let right = $[3];
        return $result.try$(
          combine(key, generation, left, right),
          (value) => {
            return new Ok(
              $dict.insert(
                entries,
                key,
                new Entry(generation, membership, value),
              ),
            );
          },
        );
      },
    ),
    (entries) => {
      return $result.try$(
        $list.try_fold(
          only_b,
          entries,
          (entries, pair) => {
            let key = pair[0];
            let entry = pair[1];
            return $result.try$(
              combine(key, entry.generation, Option$None$const, entry.value),
              (value) => {
                return new Ok(
                  $dict.insert(
                    entries,
                    key,
                    new Entry(entry.generation, entry.membership, value),
                  ),
                );
              },
            );
          },
        ),
        (entries) => {
          return new Ok(new State($int.max(a.clock, b.clock), entries));
        },
      );
    },
  );
}

export function prune(state, stable) {
  return new State(
    state.clock,
    $dict.map_values(
      state.entries,
      (_, entry) => {
        return new Entry(
          entry.generation,
          $or_set.prune(entry.membership, stable),
          entry.value,
        );
      },
    ),
  );
}

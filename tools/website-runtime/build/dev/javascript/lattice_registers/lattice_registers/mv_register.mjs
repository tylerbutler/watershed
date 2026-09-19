/// <reference types="./mv_register.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../lattice_core/lattice_core/version_vector.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";

class Tag extends $CustomType {
  constructor(replica_id, counter) {
    super();
    this.replica_id = replica_id;
    this.counter = counter;
  }
}

class MVRegister extends $CustomType {
  constructor(replica_id, entries, vclock) {
    super();
    this.replica_id = replica_id;
    this.entries = entries;
    this.vclock = vclock;
  }
}

/**
 * Create a new empty MV-Register for the given replica.
 *
 * Returns a register with no entries and an empty version vector.
 * `replica_id` identifies this node and is used when writing new values.
 */
export function new$(replica_id) {
  return new MVRegister(replica_id, $dict.new$(), $version_vector.new$());
}

/**
 * Write a new value and return both the new state and a delta.
 *
 * The returned delta is an `MVRegister` whose `entries` contains only the
 * new tag→value pair, but whose `vclock` is the **full new vclock** of the
 * writing replica. The vclock is essential: it encodes the causal context
 * the local write supersedes, so that on merge into a remote replica every
 * dominated tag (whether at the writer or any other replica observed by
 * the writer) is correctly retracted.
 *
 * Merging the delta into a remote via `merge` produces the same result as
 * merging the full new state, but is much smaller when the local register
 * holds many concurrent values being collapsed by this write.
 */
export function set_with_delta(register, val) {
  let new_vclock = $version_vector.increment(
    register.vclock,
    register.replica_id,
  );
  let new_counter = $version_vector.get(new_vclock, register.replica_id);
  let tag = new Tag(register.replica_id, new_counter);
  let new_state = new MVRegister(
    register.replica_id,
    $dict.insert($dict.new$(), tag, val),
    new_vclock,
  );
  return [new_state, new_state];
}

/**
 * Write a new value to the register.
 *
 * Increments this replica's logical clock, creates a fresh tag for the write,
 * clears all prior entries (this write causally supersedes everything in the
 * current vclock), and inserts the new tag-value pair. After a `set`, calling
 * `value` returns a single-element list containing `val`.
 *
 * See `set_with_delta` for the delta-state variant that also returns a
 * small payload suitable for incremental sync (e.g. over websockets).
 */
export function set(register, val) {
  let $ = set_with_delta(register, val);
  let updated = $[0];
  return updated;
}

/**
 * Return all concurrent values in the register.
 *
 * Returns a list of all surviving values. An empty list means the register
 * has never been written. A single-element list is the common case after a
 * `set`. Multiple values indicate concurrent writes from different replicas
 * that have not yet been causally superseded — the application must decide
 * how to resolve them (e.g., pick one, merge, or surface the conflict).
 */
export function value(register) {
  return $dict.values(register.entries);
}

/**
 * Merge two MV-Registers.
 *
 * An entry survives the merge if it is not dominated by the other register's
 * version vector, or if both registers share the same entry (handles
 * self-merge idempotency):
 *
 * - Entry `Tag(rid, counter)` from `a` survives if `b.vclock[rid] < counter`
 *   OR `b.entries` also contains that tag.
 * - Entry `Tag(rid, counter)` from `b` survives if `a.vclock[rid] < counter`
 *   OR `a.entries` also contains that tag.
 *
 * The merged vclock is the pairwise maximum of both vclocks.
 * The result's `replica_id` is taken from `a`.
 *
 * This operation is commutative, associative, and idempotent.
 */
export function merge(a, b) {
  let surviving_from_a = $dict.filter(
    a.entries,
    (tag, _) => {
      return ($version_vector.get(b.vclock, tag.replica_id) < tag.counter) || $dict.has_key(
        b.entries,
        tag,
      );
    },
  );
  let surviving_from_b = $dict.filter(
    b.entries,
    (tag, _) => {
      return ($version_vector.get(a.vclock, tag.replica_id) < tag.counter) || $dict.has_key(
        a.entries,
        tag,
      );
    },
  );
  let merged_entries = $dict.merge(surviving_from_a, surviving_from_b);
  return new MVRegister(
    a.replica_id,
    merged_entries,
    $version_vector.merge(a.vclock, b.vclock),
  );
}

/**
 * Encode generic values, write tags, and the full causal clock.
 *
 * Uses the same v1 envelope as `to_json`.
 *
 * ## Examples
 *
 * ```gleam
 * let register = mv_register.new(replica_id.new("A")) |> mv_register.set(42)
 * mv_register.to_json_with(register, json.int)
 * ```
 */
export function to_json_with(register, encode) {
  let rid = register.replica_id;
  let entries = register.entries;
  let vclock = register.vclock;
  let entries_json = $json.array(
    $dict.to_list(entries),
    (pair) => {
      let tag_rid;
      let counter;
      let value$1;
      value$1 = pair[1];
      tag_rid = pair[0].replica_id;
      counter = pair[0].counter;
      return $json.object(
        toList([
          [
            "tag",
            $json.object(
              toList([
                ["r", $json.string($replica_id.to_string(tag_rid))],
                ["c", $json.int(counter)],
              ]),
            ),
          ],
          ["value", encode(value$1)],
        ]),
      );
    },
  );
  let vclock_dict = $version_vector.to_dict(vclock);
  return $json.object(
    toList([
      ["type", $json.string("mv_register")],
      ["v", $json.int(1)],
      [
        "state",
        $json.object(
          toList([
            ["replica_id", $json.string($replica_id.to_string(rid))],
            ["entries", entries_json],
            [
              "vclock",
              $json.dict(vclock_dict, $replica_id.to_string, $json.int),
            ],
          ]),
        ),
      ],
    ]),
  );
}

/**
 * Encode a MVRegister(String) as a self-describing JSON value.
 *
 * Entries are serialized as an array of tag+value objects because `Tag` is a
 * custom type that cannot serve as a JSON dictionary key.
 * Format: `{"type": "mv_register", "v": 1, "state": {"replica_id": "...", "entries": [...], "vclock": {...}}}`
 *
 * Use `from_json` to decode the result back into a `MVRegister(String)`.
 */
export function to_json(register) {
  return to_json_with(register, $json.string);
}

/**
 * Decode generic values and validate their write tags against the causal clock.
 *
 * Accepts the v1 envelope. Invalid payloads or causal metadata return `Error`.
 *
 * ## Examples
 *
 * ```gleam
 * let register = mv_register.new(replica_id.new("A")) |> mv_register.set(42)
 * let encoded = mv_register.to_json_with(register, json.int) |> json.to_string
 * mv_register.from_json_with(encoded, decode.int)  // -> Ok(register)
 * ```
 */
export function from_json_with(json_string, decoder) {
  let entry_decoder = $decode.field(
    "tag",
    $decode.field(
      "r",
      $decode.string,
      (r) => {
        return $decode.field(
          "c",
          $decode.int,
          (c) => { return $decode.success(new Tag($replica_id.new$(r), c)); },
        );
      },
    ),
    (tag) => {
      return $decode.field(
        "value",
        decoder,
        (value) => { return $decode.success([tag, value]); },
      );
    },
  );
  let state_decoder = $decode.field(
    "state",
    $decode.field(
      "replica_id",
      $decode.string,
      (rid_str) => {
        return $decode.field(
          "entries",
          $decode.list(entry_decoder),
          (entries_list) => {
            return $decode.field(
              "vclock",
              $decode.dict($decode.string, $decode.int),
              (vclock_dict) => {
                let entries = $dict.from_list(entries_list);
                let vclock_rid_dict = $dict.fold(
                  vclock_dict,
                  $dict.new$(),
                  (acc, k, v) => {
                    return $dict.insert(acc, $replica_id.new$(k), v);
                  },
                );
                let vclock = $version_vector.from_dict(vclock_rid_dict);
                let is_valid = (($dict.size(entries) === $list.length(
                  entries_list,
                )) && $list.all(
                  $dict.values(vclock_dict),
                  (counter) => { return counter >= 0; },
                )) && $list.all(
                  entries_list,
                  (pair) => {
                    let rid;
                    let c;
                    rid = pair[0].replica_id;
                    c = pair[0].counter;
                    let is_positive = c > 0;
                    let vclock_counter = $version_vector.get(vclock, rid);
                    let is_causal = c <= vclock_counter;
                    return is_positive && is_causal;
                  },
                );
                let mvr = new MVRegister(
                  $replica_id.new$(rid_str),
                  entries,
                  vclock,
                );
                if (is_valid) {
                  return $decode.success(mvr);
                } else {
                  return $decode.failure(
                    mvr,
                    "unique causally consistent entries and non-negative clocks with positive tag counters",
                  );
                }
              },
            );
          },
        );
      },
    ),
    (state) => { return $decode.success(state); },
  );
  let envelope_decoder = $decode.field(
    "type",
    $decode.string,
    (type_tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => { return $decode.success([type_tag, version]); },
      );
    },
  );
  let $ = $json.parse(json_string, envelope_decoder);
  if ($ instanceof Ok) {
    let type_tag = $[0][0];
    let version = $[0][1];
    let $1 = (type_tag === "mv_register") && (version === 1);
    if ($1) {
      return $json.parse(json_string, state_decoder);
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=mv_register and v=1",
              (type_tag + " v=") + $int.to_string(version),
              $List$Empty$const,
            ),
          ]),
        ),
      );
    }
  } else {
    return $;
  }
}

/**
 * Decode a MVRegister(String) from a JSON string produced by `to_json`.
 *
 * Returns `Ok(MVRegister(String))` on success, or `Error(json.DecodeError)`
 * if the input is not a valid MV-Register JSON envelope.
 */
export function from_json(json_string) {
  return from_json_with(json_string, $decode.string);
}

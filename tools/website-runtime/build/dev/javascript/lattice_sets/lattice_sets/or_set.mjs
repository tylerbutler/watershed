/// <reference types="./or_set.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
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

class ORSet extends $CustomType {
  constructor(replica_id, counter, entries, tombstones, pruned) {
    super();
    this.replica_id = replica_id;
    this.counter = counter;
    this.entries = entries;
    this.tombstones = tombstones;
    this.pruned = pruned;
  }
}

export class Diff extends $CustomType {
  constructor(added, removed) {
    super();
    this.added = added;
    this.removed = removed;
  }
}
export const Diff$Diff = (added, removed) => new Diff(added, removed);
export const Diff$isDiff = (value) => value instanceof Diff;
export const Diff$Diff$added = (value) => value.added;
export const Diff$Diff$0 = (value) => value.added;
export const Diff$Diff$removed = (value) => value.removed;
export const Diff$Diff$1 = (value) => value.removed;

/**
 * Create a new empty OR-Set for the given replica.
 *
 * Each replica should have a unique `replica_id` to ensure that tags
 * generated on different replicas never collide.
 */
export function new$(replica_id) {
  return new ORSet(
    replica_id,
    0,
    $dict.new$(),
    $set.new$(),
    $version_vector.new$(),
  );
}

/**
 * Add an element and return both the new state and a delta.
 *
 * The returned delta is an `ORSet` whose `entries` contains only the newly
 * inserted element with its single fresh tag, with empty tombstones and
 * pruned vector. Merging the delta into a remote via `merge` adds the new
 * tag to the remote's entry for `element` (creating it if necessary),
 * producing the same observable result as merging the full new state.
 *
 * The delta carries this replica's `replica_id` and the post-mutation
 * `counter`, so successive deltas remain causally distinguishable.
 */
export function add_with_delta(orset, element) {
  let new_counter = orset.counter + 1;
  let tag = new Tag(orset.replica_id, new_counter);
  let existing_tags = $result.unwrap(
    $dict.get(orset.entries, element),
    $set.new$(),
  );
  let new_tags = $set.insert(existing_tags, tag);
  let updated = new ORSet(
    orset.replica_id,
    new_counter,
    $dict.insert(orset.entries, element, new_tags),
    orset.tombstones,
    orset.pruned,
  );
  let delta = new ORSet(
    orset.replica_id,
    new_counter,
    $dict.from_list(toList([[element, $set.from_list(toList([tag]))]])),
    $set.new$(),
    $version_vector.new$(),
  );
  return [updated, delta];
}

/**
 * Add an element to the set.
 *
 * Creates a fresh unique tag for this add operation using the replica's
 * monotonically-increasing counter. The element may already be present;
 * in that case a new tag is added alongside existing ones.
 *
 * See `add_with_delta` for the delta-state variant that also returns a
 * small payload suitable for incremental sync (e.g. over websockets).
 */
export function add(orset, element) {
  let $ = add_with_delta(orset, element);
  let updated = $[0];
  return updated;
}

/**
 * Remove an element and return both the new state and a delta.
 *
 * The returned delta is an `ORSet` whose `tombstones` contains exactly the
 * tags that were live for `element` at the time of the remove, with empty
 * entries and pruned vector. Merging the delta into a remote via `merge`
 * retracts those tags from the remote's entry for `element`. Tags that the
 * remote has but the delta source had not yet observed (concurrent adds)
 * survive — preserving the add-wins property of OR-Set.
 */
export function remove_with_delta(orset, element) {
  let removed_tags = $result.unwrap(
    $dict.get(orset.entries, element),
    $set.new$(),
  );
  let updated = new ORSet(
    orset.replica_id,
    orset.counter,
    $dict.delete$(orset.entries, element),
    $set.union(orset.tombstones, removed_tags),
    orset.pruned,
  );
  let delta = new ORSet(
    orset.replica_id,
    orset.counter,
    $dict.new$(),
    removed_tags,
    $version_vector.new$(),
  );
  return [updated, delta];
}

/**
 * Remove an element from the set.
 *
 * Removes all currently observed tags for the element (observed-remove
 * semantics). Any concurrent add on another replica that created a new tag
 * not yet observed here will survive this remove after merging.
 *
 * See `remove_with_delta` for the delta-state variant.
 */
export function remove(orset, element) {
  let $ = remove_with_delta(orset, element);
  let updated = $[0];
  return updated;
}

/**
 * Remove each element in `elements` using observed-remove semantics.
 *
 * Missing elements are ignored, matching `remove`.
 */
export function remove_all(orset, elements) {
  return $list.fold(
    elements,
    orset,
    (acc, element) => { return remove(acc, element); },
  );
}

/**
 * Return the set of all elements currently in the OR-Set.
 *
 * An element is included only when its tag set is non-empty.
 */
export function value(orset) {
  let _pipe = $dict.keys(orset.entries);
  return $set.from_list(_pipe);
}

/**
 * Remove every currently observable element matching `predicate`.
 *
 * The predicate is evaluated against `value(orset)`, then each matching value
 * is removed with normal observed-remove semantics.
 */
export function remove_where(orset, predicate) {
  let _block;
  let _pipe = value(orset);
  let _pipe$1 = $set.to_list(_pipe);
  _block = $list.filter(_pipe$1, predicate);
  let elements = _block;
  return remove_all(orset, elements);
}

/**
 * Check if the set contains the given element.
 *
 * Returns `True` if the element has at least one live tag (i.e., it has
 * been added and not yet removed on this replica, or a concurrent add
 * survived a remove after merging).
 */
export function contains(orset, element) {
  let $ = $dict.get(orset.entries, element);
  if ($ instanceof Ok) {
    let tags = $[0];
    return !$set.is_empty(tags);
  } else {
    return false;
  }
}

/**
 * Compare the observable values of two OR-Sets.
 *
 * `added` contains values present in `after` but not `before`.
 * `removed` contains values present in `before` but not `after`.
 */
export function diff(before, after) {
  let before_values = value(before);
  let after_values = value(after);
  return new Diff(
    $set.difference(after_values, before_values),
    $set.difference(before_values, after_values),
  );
}

function pruned_on_side_without_live_tag(tag, live_tags, pruned) {
  let replica = tag.replica_id;
  let counter = tag.counter;
  return ($version_vector.get(pruned, replica) >= counter) && !$set.contains(
    live_tags,
    tag,
  );
}

function is_pruned_zombie(tag, a_tags, a_pruned, b_tags, b_pruned) {
  return pruned_on_side_without_live_tag(tag, a_tags, a_pruned) || pruned_on_side_without_live_tag(
    tag,
    b_tags,
    b_pruned,
  );
}

function counter_with_pruned_floor(counter, pruned) {
  let _pipe = pruned;
  let _pipe$1 = $version_vector.to_dict(_pipe);
  let _pipe$2 = $dict.values(_pipe$1);
  return $list.fold(_pipe$2, counter, $int.max);
}

function not_dominated(tag, pruned) {
  let replica = tag.replica_id;
  let counter = tag.counter;
  return $version_vector.get(pruned, replica) < counter;
}

/**
 * Merge two OR-Sets.
 *
 * For each element, the merged tag set is the union of both sides' tags,
 * minus merged tombstones, and minus any tags dominated by the merged
 * pruned vector that are not live on the side that pruned them (zombie
 * detection). An element is present if it has at least one surviving tag.
 *
 * The merged counter covers both sides and the merged pruning frontier,
 * ensuring future adds remain above retained allocation history.
 *
 * Merge is commutative, associative, and idempotent (a valid CRDT join).
 */
export function merge(a, b) {
  let merged_pruned = $version_vector.merge(a.pruned, b.pruned);
  let _block;
  let _pipe = $set.union(a.tombstones, b.tombstones);
  _block = $set.filter(
    _pipe,
    (tag) => { return not_dominated(tag, merged_pruned); },
  );
  let merged_tombstones = _block;
  let merged_counter = counter_with_pruned_floor(
    $int.max(a.counter, b.counter),
    merged_pruned,
  );
  let a_keys = $dict.keys(a.entries);
  let b_keys = $dict.keys(b.entries);
  let all_keys = $list.unique($list.append(a_keys, b_keys));
  let merged_entries = $list.fold(
    all_keys,
    $dict.new$(),
    (acc, element) => {
      let a_tags = $result.unwrap($dict.get(a.entries, element), $set.new$());
      let b_tags = $result.unwrap($dict.get(b.entries, element), $set.new$());
      let _block$1;
      let _pipe$1 = $set.union(a_tags, b_tags);
      _block$1 = $set.filter(
        _pipe$1,
        (tag) => {
          return !$set.contains(merged_tombstones, tag) && !is_pruned_zombie(
            tag,
            a_tags,
            a.pruned,
            b_tags,
            b.pruned,
          );
        },
      );
      let combined = _block$1;
      let $ = $set.is_empty(combined);
      if ($) {
        return acc;
      } else {
        return $dict.insert(acc, element, combined);
      }
    },
  );
  return new ORSet(
    a.replica_id,
    merged_counter,
    merged_entries,
    merged_tombstones,
    merged_pruned,
  );
}

/**
 * Merge two OR-Sets and report observable value changes from `local`.
 *
 * The returned OR-Set is exactly the same as `merge(local, remote)`. The
 * diff compares `value(local)` with `value(merged)`, so it reports only
 * externally visible additions and removals.
 */
export function merge_with_diff(local, remote) {
  let merged = merge(local, remote);
  return [merged, diff(local, merged)];
}

function tags_to_bound(tags) {
  return $set.fold(
    tags,
    $version_vector.new$(),
    (bound, tag) => {
      let replica = tag.replica_id;
      let counter = tag.counter;
      return $version_vector.set_max(bound, replica, counter);
    },
  );
}

/**
 * Remove an element and return a causal bound for the removed tags.
 *
 * Behaves identically to `remove` but also returns a `VersionVector`
 * representing the maximum counter per replica across all tags that were
 * live for the element. This bound can be compared against a pruned vector
 * to determine when the removal is causally stable.
 *
 * Returns an empty `VersionVector` if the element had no live tags.
 */
export function remove_with_bound(orset, element) {
  let removed_tags = $result.unwrap(
    $dict.get(orset.entries, element),
    $set.new$(),
  );
  let bound = tags_to_bound(removed_tags);
  let updated = new ORSet(
    orset.replica_id,
    orset.counter,
    $dict.delete$(orset.entries, element),
    $set.union(orset.tombstones, removed_tags),
    orset.pruned,
  );
  return [updated, bound];
}

/**
 * Return the pruned version vector.
 *
 * This is the causal horizon below which tombstones have been garbage
 * collected. Useful for determining whether a remove bound is fully
 * dominated (causally stable).
 */
export function pruned_vv(orset) {
  return orset.pruned;
}

/**
 * Prune tombstones based on a stable version vector.
 *
 * Updates the `pruned` vector by merging it with `stable_vv`. Any tombstones
 * dominated by the new `pruned` vector are removed. This function should only
 * be called with a version vector representing events that have been seen by
 * all replicas (causally stable), otherwise "zombie" updates might be
 * incorrectly ignored.
 */
export function prune(orset, stable_vv) {
  let new_pruned = $version_vector.merge(orset.pruned, stable_vv);
  let pruned_tombstones = $set.filter(
    orset.tombstones,
    (tag) => { return not_dominated(tag, new_pruned); },
  );
  return new ORSet(
    orset.replica_id,
    counter_with_pruned_floor(orset.counter, new_pruned),
    orset.entries,
    pruned_tombstones,
    new_pruned,
  );
}

function encode_tag(tag) {
  let replica = tag.replica_id;
  let counter = tag.counter;
  return $json.object(
    toList([
      ["r", $json.string($replica_id.to_string(replica))],
      ["c", $json.int(counter)],
    ]),
  );
}

function encode_envelope(orset, version, entries) {
  return $json.object(
    toList([
      ["type", $json.string("or_set")],
      ["v", $json.int(version)],
      [
        "state",
        $json.object(
          toList([
            ["replica_id", $replica_id.to_json(orset.replica_id)],
            ["counter", $json.int(orset.counter)],
            ["entries", entries],
            [
              "tombstones",
              $json.array($set.to_list(orset.tombstones), encode_tag),
            ],
            ["pruned", $version_vector.to_json(orset.pruned)],
          ]),
        ),
      ],
    ]),
  );
}

/**
 * Encode an `ORSet(String)` as a self-describing JSON value.
 *
 * Entries are encoded as a JSON dict where values are arrays of tag objects
 * `{"r": replica_id, "c": counter}`. Removed tags are encoded separately in
 * `tombstones`. The `pruned` version vector tracks garbage-collected causal
 * history.
 *
 * Format: `{"type": "or_set", "v": 2, "state": {"replica_id": "...", "counter": N, "entries": {...}, "tombstones": [...], "pruned": {...}}}`
 *
 * The encoded value can be restored with `from_json`.
 */
export function to_json(orset) {
  return encode_envelope(
    orset,
    2,
    $json.dict(
      orset.entries,
      (k) => { return k; },
      (tags) => { return $json.array($set.to_list(tags), encode_tag); },
    ),
  );
}

/**
 * Encode generic elements and all causal metadata in a v3 envelope.
 *
 * `entries` is an array of `{"value": ..., "tags": [...]}` objects, so
 * elements need not be JSON object keys. String `to_json` continues to
 * write the legacy v2 object representation.
 *
 * ## Examples
 *
 * ```gleam
 * let set = or_set.new(replica_id.new("A")) |> or_set.add(42)
 * or_set.to_json_with(set, json.int)
 * ```
 */
export function to_json_with(orset, encode) {
  return encode_envelope(
    orset,
    3,
    $json.array(
      $dict.to_list(orset.entries),
      (entry) => {
        let value$1 = entry[0];
        let tags = entry[1];
        return $json.object(
          toList([
            ["value", encode(value$1)],
            ["tags", $json.array($set.to_list(tags), encode_tag)],
          ]),
        );
      },
    ),
  );
}

/**
 * Decode an `ORSet(String)` from a JSON string produced by `to_json`.
 *
 * Supports both v1 (no pruned field) and v2 formats. Returns `Error` if the
 * string is not valid JSON or does not match the expected format.
 */
export function from_json(json_string) {
  let tag_decoder = $decode.field(
    "r",
    $replica_id.decoder(),
    (r) => {
      return $decode.field(
        "c",
        $decode.int,
        (c) => { return $decode.success(new Tag(r, c)); },
      );
    },
  );
  let tag_set_decoder = $decode.map($decode.list(tag_decoder), $set.from_list);
  let v1_state_decoder = $decode.field(
    "state",
    $decode.field(
      "replica_id",
      $replica_id.decoder(),
      (replica_id) => {
        return $decode.field(
          "counter",
          $decode.int,
          (counter) => {
            return $decode.field(
              "entries",
              $decode.dict($decode.string, tag_set_decoder),
              (entries) => {
                return $decode.optional_field(
                  "tombstones",
                  $List$Empty$const,
                  $decode.list(tag_decoder),
                  (tombstones) => {
                    return $decode.success(
                      new ORSet(
                        replica_id,
                        counter,
                        entries,
                        $set.from_list(tombstones),
                        $version_vector.new$(),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    ),
    (state) => { return $decode.success(state); },
  );
  let v2_state_decoder = $decode.field(
    "state",
    $decode.field(
      "replica_id",
      $replica_id.decoder(),
      (replica_id) => {
        return $decode.field(
          "counter",
          $decode.int,
          (counter) => {
            return $decode.field(
              "entries",
              $decode.dict($decode.string, tag_set_decoder),
              (entries) => {
                return $decode.field(
                  "tombstones",
                  tag_set_decoder,
                  (tombstones) => {
                    return $decode.field(
                      "pruned",
                      $version_vector.decoder(),
                      (pruned) => {
                        return $decode.success(
                          new ORSet(
                            replica_id,
                            counter,
                            entries,
                            tombstones,
                            pruned,
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
    let $1 = type_tag === "or_set";
    if ($1) {
      if (version === 1) {
        return $json.parse(json_string, v1_state_decoder);
      } else if (version === 2) {
        return $json.parse(json_string, v2_state_decoder);
      } else {
        return new Error(
          new $json.UnableToDecode(
            toList([
              new $decode.DecodeError(
                "v=1 or v=2",
                $int.to_string(version),
                toList(["v"]),
              ),
            ]),
          ),
        );
      }
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError("type=or_set", type_tag, $List$Empty$const),
          ]),
        ),
      );
    }
  } else {
    return $;
  }
}

/**
 * Decode generic elements and all causal metadata from a v3 envelope.
 *
 * Rejects non-positive tags, repeated elements or live tags, and tags that
 * are both live and tombstoned. The allocation counter is raised when
 * retained tags or pruned clocks prove that higher counters were used.
 * This prevents ID reuse after loading or rebinding a snapshot.
 * Use String `from_json` to read legacy v1/v2 object-key envelopes.
 *
 * ## Examples
 *
 * ```gleam
 * let set = or_set.new(replica_id.new("A")) |> or_set.add(42)
 * let encoded = or_set.to_json_with(set, json.int) |> json.to_string
 * or_set.from_json_with(encoded, decode.int)  // -> Ok(set)
 * ```
 */
export function from_json_with(json_string, decoder) {
  let tag_decoder = $decode.field(
    "r",
    $replica_id.decoder(),
    (r) => {
      return $decode.field(
        "c",
        $decode.int,
        (c) => {
          let tag = new Tag(r, c);
          let $ = c > 0;
          if ($) {
            return $decode.success(tag);
          } else {
            return $decode.failure(tag, "a positive tag counter");
          }
        },
      );
    },
  );
  let entry_decoder = $decode.field(
    "value",
    decoder,
    (value) => {
      return $decode.field(
        "tags",
        $decode.list(tag_decoder),
        (tags) => { return $decode.success([value, tags]); },
      );
    },
  );
  let envelope_decoder = $decode.field(
    "type",
    $decode.string,
    (type_tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => {
          let $ = (type_tag === "or_set") && (version === 3);
          if ($) {
            return $decode.success(undefined);
          } else {
            return $decode.failure(undefined, "type=or_set and v=3");
          }
        },
      );
    },
  );
  return $result.try$(
    $json.parse(json_string, envelope_decoder),
    (_) => {
      return $json.parse(
        json_string,
        $decode.field(
          "state",
          $decode.field(
            "replica_id",
            $replica_id.decoder(),
            (rid) => {
              return $decode.field(
                "counter",
                $decode.int,
                (counter) => {
                  return $decode.field(
                    "entries",
                    $decode.list(entry_decoder),
                    (entries_list) => {
                      return $decode.field(
                        "tombstones",
                        $decode.list(tag_decoder),
                        (tombstone_list) => {
                          return $decode.field(
                            "pruned",
                            $decode.field(
                              "type",
                              $decode.string,
                              (type_tag) => {
                                return $decode.field(
                                  "v",
                                  $decode.int,
                                  (version) => {
                                    let $ = (type_tag === "version_vector") && (version === 1);
                                    if ($) {
                                      return $version_vector.decoder();
                                    } else {
                                      return $decode.failure(
                                        $version_vector.new$(),
                                        "type=version_vector and v=1",
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                            (pruned) => {
                              let live_tags = $list.flat_map(
                                entries_list,
                                (entry) => { return entry[1]; },
                              );
                              let tombstones = $set.from_list(tombstone_list);
                              let _block;
                              let _pipe = entries_list;
                              let _pipe$1 = $list.map(
                                _pipe,
                                (entry) => {
                                  return [entry[0], $set.from_list(entry[1])];
                                },
                              );
                              _block = $dict.from_list(_pipe$1);
                              let entries = _block;
                              let _block$1;
                              let _pipe$2 = $version_vector.to_dict(pruned);
                              _block$1 = $dict.values(_pipe$2);
                              let clocks = _block$1;
                              let allocated = $list.fold(
                                $list.append(live_tags, tombstone_list),
                                counter,
                                (max, tag) => {
                                  return $int.max(max, tag.counter);
                                },
                              );
                              let state = new ORSet(
                                rid,
                                counter_with_pruned_floor(allocated, pruned),
                                entries,
                                tombstones,
                                pruned,
                              );
                              let valid = (((((counter >= 0) && $list.all(
                                clocks,
                                (clock) => { return clock >= 0; },
                              )) && ($dict.size(entries) === $list.length(
                                entries_list,
                              ))) && $list.all(
                                entries_list,
                                (entry) => { return !$list.is_empty(entry[1]); },
                              )) && ($set.size($set.from_list(live_tags)) === $list.length(
                                live_tags,
                              ))) && $list.all(
                                live_tags,
                                (tag) => {
                                  return !$set.contains(tombstones, tag);
                                },
                              );
                              if (valid) {
                                return $decode.success(state);
                              } else {
                                return $decode.failure(
                                  state,
                                  "non-negative clocks, unique non-empty entries, and disjoint live and removed tags",
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
          (state) => { return $decode.success(state); },
        ),
      );
    },
  );
}

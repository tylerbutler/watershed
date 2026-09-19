/// <reference types="./text.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bool from "../../gleam_stdlib/gleam/bool.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../lattice_core/lattice_core/version_vector.mjs";
import * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.mjs";
import * as $grapheme from "../../lattice_text_core/lattice_text_core/grapheme.mjs";
import { Ok, Error, Empty as $Empty, CustomType as $CustomType } from "../gleam.mjs";

class Text extends $CustomType {
  constructor(sequence) {
    super();
    this.sequence = sequence;
  }
}

export class RangeOutOfBounds extends $CustomType {
  constructor(start, end, length) {
    super();
    this.start = start;
    this.end = end;
    this.length = length;
  }
}
export const RangeError$RangeOutOfBounds = (start, end, length) =>
  new RangeOutOfBounds(start, end, length);
export const RangeError$isRangeOutOfBounds = (value) =>
  value instanceof RangeOutOfBounds;
export const RangeError$RangeOutOfBounds$start = (value) => value.start;
export const RangeError$RangeOutOfBounds$0 = (value) => value.start;
export const RangeError$RangeOutOfBounds$end = (value) => value.end;
export const RangeError$RangeOutOfBounds$1 = (value) => value.end;
export const RangeError$RangeOutOfBounds$length = (value) => value.length;
export const RangeError$RangeOutOfBounds$2 = (value) => value.length;

/**
 * Create an empty text CRDT for a replica.
 */
export function new$(replica_id) {
  return new Text($sequence.new$(replica_id));
}

function insert_graphemes_with_delta(graphemes, seq, index) {
  return $grapheme.insert_graphemes(
    graphemes,
    seq,
    index,
    $sequence.length,
    $sequence.insert_many_with_delta,
    (var0, var1) => { return new $sequence.IndexOutOfBounds(var0, var1); },
  );
}

/**
 * Insert a value and return both the updated text and insertion delta.
 *
 * Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.
 */
export function insert_with_delta(text, index, value) {
  let seq = text.sequence;
  let _pipe = value;
  let _pipe$1 = $string.to_graphemes(_pipe);
  let _pipe$2 = insert_graphemes_with_delta(_pipe$1, seq, index);
  return $result.map(
    _pipe$2,
    (pair) => {
      let updated = pair[0];
      let delta = pair[1];
      return [new Text(updated), new Text(delta)];
    },
  );
}

/**
 * Insert a value at the visible character index.
 *
 * Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.
 */
export function insert(text, index, value) {
  let _pipe = insert_with_delta(text, index, value);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Delete a value and return both the updated text and deletion delta.
 *
 * Returns `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.
 */
export function delete_with_delta(text, index) {
  let seq = text.sequence;
  let $ = $sequence.delete_with_delta(seq, index);
  if ($ instanceof Ok) {
    let updated = $[0][0];
    let delta = $[0][1];
    return new Ok([new Text(updated), new Text(delta)]);
  } else {
    return $;
  }
}

/**
 * Delete the value at the visible character index.
 *
 * Returns `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.
 */
export function delete$(text, index) {
  let _pipe = delete_with_delta(text, index);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Return the visible graphemes as a list.
 */
export function values(text) {
  let seq = text.sequence;
  return $sequence.values(seq);
}

/**
 * Return the visible text as a single string.
 */
export function value(text) {
  let _pipe = text;
  let _pipe$1 = values(_pipe);
  return $string.concat(_pipe$1);
}

/**
 * Count the visible graphemes in the text.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(doc) = text.insert(text.new(replica_id.new("A")), 0, "a👍")
 * text.length(doc)
 * // -> 2
 * ```
 */
export function length(text) {
  let seq = text.sequence;
  return $sequence.length(seq);
}

function slice_values(text, start, end) {
  return $grapheme.slice(values(text), start, end);
}

/**
 * Return the graphemes in `[start, end)`, clamping both indexes to the
 * text bounds. An empty range (including `start > end`) yields `""`.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(doc) = text.insert(text.new(replica_id.new("A")), 0, "abcd")
 * text.substring(doc, 1, 3)
 * // -> "bc"
 * ```
 */
export function substring(text, start, end) {
  let len = length(text);
  return slice_values(text, $int.clamp(start, 0, len), $int.clamp(end, 0, len));
}

function validate_range(start, end, length) {
  let _pipe = $grapheme.validate_range(start, end, length);
  return $result.map_error(
    _pipe,
    (error) => {
      let start$1 = error.start;
      let end$1 = error.end;
      let length$1 = error.length;
      return new RangeOutOfBounds(start$1, end$1, length$1);
    },
  );
}

/**
 * Return the graphemes in `[start, end)`, or an error when the range does
 * not satisfy `0 <= start <= end <= length`.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(doc) = text.insert(text.new(replica_id.new("A")), 0, "abc")
 * text.try_substring(doc, 0, 4)
 * // -> Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3))
 * ```
 */
export function try_substring(text, start, end) {
  return $result.try$(
    validate_range(start, end, length(text)),
    (_use0) => {
      
      return new Ok(slice_values(text, start, end));
    },
  );
}

function delete_grapheme(seq, index) {
  let $ = $sequence.delete_with_delta(seq, index);
  if ($ instanceof Ok) {
    return $;
  } else {
    let index$1 = $[0].index;
    let length$1 = $[0].length;
    return new Error(new RangeOutOfBounds(index$1, index$1, length$1));
  }
}

function empty_sequence_delta(seq) {
  return $sequence.new$($sequence.replica_id(seq));
}

function delete_graphemes_with_delta(seq, start, end) {
  return $bool.guard(
    start === end,
    new Ok([seq, empty_sequence_delta(seq)]),
    () => {
      let replica = $sequence.replica_id(seq);
      return $grapheme.delete_graphemes(
        seq,
        start,
        end,
        delete_grapheme,
        (a, b) => { return $sequence.merge(a, b, replica); },
      );
    },
  );
}

/**
 * Delete a grapheme range and return both the updated text and deletion
 * delta.
 *
 * Returns `RangeOutOfBounds` when the range is outside `[0, length]`
 * or `start > end`.
 */
export function delete_range_with_delta(text, start, end) {
  let seq = text.sequence;
  return $result.try$(
    validate_range(start, end, $sequence.length(seq)),
    (_use0) => {
      
      let _pipe = delete_graphemes_with_delta(seq, start, end);
      return $result.map(
        _pipe,
        (pair) => {
          let updated = pair[0];
          let delta = pair[1];
          return [new Text(updated), new Text(delta)];
        },
      );
    },
  );
}

/**
 * Delete the graphemes in `[start, end)`.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(doc) = text.insert(text.new(replica_id.new("A")), 0, "abcd")
 * let assert Ok(doc) = text.delete_range(doc, 1, 3)
 * text.value(doc)
 * // -> "ad"
 * ```
 *
 * Returns `RangeOutOfBounds` when the range is outside `[0, length]`
 * or `start > end`.
 */
export function delete_range(text, start, end) {
  let _pipe = delete_range_with_delta(text, start, end);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

function insert_error_to_range_error(error) {
  let index = error.index;
  let length$1 = error.length;
  return new RangeOutOfBounds(index, index, length$1);
}

/**
 * Replace a grapheme range and return both the updated text and
 * replacement delta.
 *
 * Returns `RangeOutOfBounds` when the range is outside `[0, length]`
 * or `start > end`.
 */
export function replace_range_with_delta(text, start, end, value) {
  let seq = text.sequence;
  let replica = $sequence.replica_id(seq);
  return $result.try$(
    validate_range(start, end, $sequence.length(seq)),
    (_use0) => {
      
      return $result.try$(
        delete_graphemes_with_delta(seq, start, end),
        (_use0) => {
          let deleted = _use0[0];
          let delete_delta = _use0[1];
          let graphemes = $string.to_graphemes(value);
          return $result.try$(
            (() => {
              let _pipe = insert_graphemes_with_delta(graphemes, deleted, start);
              return $result.map_error(_pipe, insert_error_to_range_error);
            })(),
            (_use0) => {
              let updated = _use0[0];
              let insert_delta = _use0[1];
              let _block;
              let $ = start === end;
              if ($) {
                _block = insert_delta;
              } else if (graphemes instanceof $Empty) {
                _block = delete_delta;
              } else {
                _block = $sequence.merge(delete_delta, insert_delta, replica);
              }
              let delta = _block;
              return new Ok([new Text(updated), new Text(delta)]);
            },
          );
        },
      );
    },
  );
}

/**
 * Replace the graphemes in `[start, end)` with a value.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(doc) = text.insert(text.new(replica_id.new("A")), 0, "abcd")
 * let assert Ok(doc) = text.replace_range(doc, 1, 3, "XY")
 * text.value(doc)
 * // -> "aXYd"
 * ```
 *
 * Returns `RangeOutOfBounds` when the range is outside `[0, length]`
 * or `start > end`.
 */
export function replace_range(text, start, end, value) {
  let _pipe = replace_range_with_delta(text, start, end, value);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Move a grapheme and return both the updated text and move delta.
 *
 * Returns a `MoveError` when either index is out of bounds.
 *
 * The `to_index` is interpreted after removing the grapheme from
 * `from_index`.
 */
export function move_with_delta(text, from_index, to_index) {
  let seq = text.sequence;
  let $ = $sequence.move_with_delta(seq, from_index, to_index);
  if ($ instanceof Ok) {
    let updated = $[0][0];
    let delta = $[0][1];
    return new Ok([new Text(updated), new Text(delta)]);
  } else {
    return $;
  }
}

/**
 * Move the grapheme at `from_index` to `to_index`.
 *
 * The `to_index` is interpreted after removing the grapheme from
 * `from_index`.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(doc) = text.insert(text.new(replica_id.new("A")), 0, "abc")
 * let assert Ok(doc) = text.move(doc, 0, 2)
 * text.value(doc)
 * // -> "bca"
 * ```
 *
 * Returns a `MoveError` when either index is out of bounds.
 */
export function move(text, from_index, to_index) {
  let _pipe = move_with_delta(text, from_index, to_index);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Create an anchor at the start of the text. Always resolves to 0.
 */
export function start_anchor() {
  return $sequence.start_anchor();
}

/**
 * Create an anchor at the end of the text. Always resolves to the current
 * grapheme length, tracking growth.
 */
export function end_anchor() {
  return $sequence.end_anchor();
}

/**
 * Create an anchor at the gap before the grapheme at `index`.
 *
 * Anchors are stable positions that survive concurrent edits and merges:
 * resolve one back to a current grapheme index with `resolve_anchor`.
 * `Before` bias glues the anchor to the grapheme at `index`, so inserts at
 * the gap push it right; `After` bias glues it to the grapheme at
 * `index - 1`, so inserts at the gap land after it.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(doc) = text.insert(text.new(replica_id.new("A")), 0, "hello")
 * let assert Ok(cursor) = text.anchor_at(doc, 5, sequence.After)
 * let assert Ok(doc) = text.insert(doc, 0, "say ")
 * text.resolve_anchor(doc, cursor)  // -> Ok(9)
 * ```
 */
export function anchor_at(text, index, bias) {
  let seq = text.sequence;
  return $sequence.anchor_at(seq, index, bias);
}

/**
 * Resolve an anchor to a current grapheme index in `[0, length]`.
 *
 * Anchors on deleted graphemes still resolve: they collapse to the gap
 * where the grapheme used to be. Anchors follow moved graphemes.
 *
 * Anchors to compacted graphemes resolve through the forwarding map to the
 * gap the grapheme left behind — semantically the same as tombstone
 * collapse.
 *
 * Returns `Error(UnknownAnchorTarget)` when the anchor references a
 * grapheme this replica has never seen (created remotely and not yet
 * merged), or one that was compacted away and whose forwarding entry has
 * since been removed by the host's retention policy. Either way the anchor
 * is unusable and the holder should re-anchor.
 */
export function resolve_anchor(text, anchor) {
  let seq = text.sequence;
  return $sequence.resolve(seq, anchor);
}

/**
 * Encode an anchor as a self-describing JSON value.
 */
export function anchor_to_json(anchor) {
  return $sequence.anchor_to_json(anchor);
}

/**
 * Decode an anchor from a JSON string produced by `anchor_to_json`.
 */
export function anchor_from_json(json_string) {
  return $sequence.anchor_from_json(json_string);
}

/**
 * Append a value and return both the updated text and insertion delta.
 */
export function append_with_delta(text, value) {
  return insert_with_delta(text, length(text), value);
}

/**
 * Insert a value at the end of the text.
 *
 * Returns the insertion result, like `insert`.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(doc) = text.insert(text.new(replica_id.new("A")), 0, "ab")
 * let assert Ok(doc) = text.append(doc, "cd")
 * text.value(doc)
 * // -> "abcd"
 * ```
 */
export function append(text, value) {
  let _pipe = append_with_delta(text, value);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Compact everything at or below a stability frontier.
 *
 * Delegates to `sequence.compact`: stable tombstones are dropped, runs of
 * stable graphemes are merged into compact blocks, and every dropped ID
 * gets a forwarding entry so anchors and rebased operations still resolve.
 * See `lattice_sequence/sequence.compact` for the stability contract.
 */
export function compact(text, stable) {
  let seq = text.sequence;
  let $ = $sequence.compact(seq, stable);
  let compacted = $[0];
  let forwardings = $[1];
  return [new Text(compacted), forwardings];
}

/**
 * Remove previously emitted forwarding entries from the text.
 *
 * Forwardings are bounded by the host's retention policy: keep the map
 * returned by each `compact` round and expire old rounds by passing them
 * here.
 */
export function remove_forwardings(text, map) {
  let seq = text.sequence;
  return new Text($sequence.remove_forwardings(seq, map));
}

/**
 * The stability frontier this text was last compacted at.
 */
export function frontier(text) {
  let seq = text.sequence;
  return $sequence.frontier(seq);
}

/**
 * Select the local editor without rebuilding the underlying sequence.
 *
 * Preserves historical item IDs, counters, and compaction metadata.
 * Independent writers must use distinct replica IDs.
 *
 * ## Examples
 *
 * ```gleam
 * let assert Ok(remote) = text.insert(text.new(replica_id.new("A")), 0, "hello")
 * text.bind(remote, replica_id.new("B")) |> text.value()
 * // -> "hello"
 * ```
 */
export function bind(text, replica) {
  let seq = text.sequence;
  return new Text($sequence.bind(seq, replica));
}

/**
 * Merge two text CRDT states.
 *
 * Pass the identity used for subsequent local edits. Operand order does not
 * select the identity. Deltas and decoded snapshots retain their sender's
 * identity; merge them under your local identity before editing. Independent
 * writers must use distinct replica IDs.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * text.merge(text.new(local), text.new(replica_id.new("B")), local)
 * |> text.value()
 * // -> ""
 * ```
 */
export function merge(a, b, replica) {
  let a_seq = a.sequence;
  let b_seq = b.sequence;
  return new Text($sequence.merge(a_seq, b_seq, replica));
}

/**
 * Alias for `merge`, with the same explicit output replica identity.
 *
 * ## Examples
 *
 * ```gleam
 * text.merge_as(a, b, local) == text.merge(a, b, local)
 * // -> True
 * ```
 */
export function merge_as(a, b, replica) {
  return merge(a, b, replica);
}

/**
 * Encode text using the canonical sequence JSON envelope.
 */
export function to_json(text) {
  let seq = text.sequence;
  return $sequence.to_json(seq, $json.string);
}

/**
 * Decode text from the canonical sequence JSON envelope.
 *
 * Retains historical IDs and raises an understated allocation counter to
 * cover retained IDs and the compaction frontier, as `sequence.from_json`
 * does. Use `bind` with the local identity before editing an adopted state.
 */
export function from_json(json_string) {
  let $ = $sequence.from_json(json_string, $decode.string);
  if ($ instanceof Ok) {
    let seq = $[0];
    return new Ok(new Text(seq));
  } else {
    return $;
  }
}

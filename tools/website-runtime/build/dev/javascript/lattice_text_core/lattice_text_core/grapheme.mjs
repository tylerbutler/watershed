/// <reference types="./grapheme.d.mts" />
import * as $bool from "../../gleam_stdlib/gleam/bool.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";

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
 * Validate that `[start, end)` is a range within `[0, length]`.
 *
 * ## Examples
 *
 * ```gleam
 * validate_range(1, 3, 4)
 * // -> Ok(Nil)
 * validate_range(0, 5, 3)
 * // -> Error(RangeOutOfBounds(start: 0, end: 5, length: 3))
 * ```
 */
export function validate_range(start, end, length) {
  return $bool.guard(
    ((start < 0) || (end > length)) || (start > end),
    new Error(new RangeOutOfBounds(start, end, length)),
    () => { return new Ok(undefined); },
  );
}

/**
 * Concatenate a list of graphemes into a single string.
 */
export function value(graphemes) {
  return $string.concat(graphemes);
}

/**
 * Return the graphemes in `[start, end)` as a string.
 *
 * Indexes are used as-is (no clamping); callers that need clamping or
 * validation should apply it first with `validate_range`.
 */
export function slice(graphemes, start, end) {
  let _pipe = graphemes;
  let _pipe$1 = $list.drop(_pipe, start);
  let _pipe$2 = $list.take(_pipe$1, end - start);
  return $string.concat(_pipe$2);
}

/**
 * Insert a list of graphemes at `index` as a single batched operation,
 * returning the updated state and one delta covering every inserted node.
 *
 * Generic over the backend state `s` and insert-error `e`:
 * - `length` reports the backend's current visible length.
 * - `insert_many` inserts the whole grapheme run starting at `index`,
 *   returning the updated state and its combined delta, or a backend error.
 * - `index_out_of_bounds` builds the backend error for an invalid `index`.
 *
 * Returns `Error` (via `index_out_of_bounds`) when `index` is outside
 * `[0, length]`, mirroring the backend's own bounds contract even when the
 * grapheme list is empty. An empty grapheme list at a valid index is passed
 * to `insert_many`, allowing the backend to return its neutral delta.
 */
export function insert_graphemes(
  graphemes,
  state,
  index,
  length,
  insert_many,
  index_out_of_bounds
) {
  let len = length(state);
  let $ = (index < 0) || (index > len);
  if ($) {
    return new Error(index_out_of_bounds(index, len));
  } else {
    return insert_many(state, index, graphemes);
  }
}

/**
 * Delete the graphemes in `[start, end)` one at a time, threading a merged
 * delta of every deletion.
 *
 * Generic over the backend state `s` and delete-error `e`:
 * - `delete` deletes the single grapheme at an index, returning the updated
 *   state and its delta, or the backend's own error.
 * - `merge` joins two deltas.
 *
 * Repeatedly deletes at `start`, since each deletion shifts the following
 * graphemes left. An empty range is a no-op whose delta is the unchanged
 * state.
 */
export function delete_graphemes(state, start, end, delete$, merge) {
  let $ = end - start;
  let count = $;
  if (count <= 0) {
    return new Ok([state, state]);
  } else {
    let count = $;
    return $result.try$(
      delete$(state, start),
      (_use0) => {
        let first_state = _use0[0];
        let first_delta = _use0[1];
        let _pipe = $list.repeat(undefined, count - 1);
        return $list.try_fold(
          _pipe,
          [first_state, first_delta],
          (acc, _) => {
            let current = acc[0];
            let delta = acc[1];
            return $result.try$(
              delete$(current, start),
              (_use0) => {
                let updated = _use0[0];
                let next_delta = _use0[1];
                return new Ok([updated, merge(delta, next_delta)]);
              },
            );
          },
        );
      },
    );
  }
}

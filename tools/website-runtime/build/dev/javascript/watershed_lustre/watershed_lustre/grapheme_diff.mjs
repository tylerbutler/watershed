/// <reference types="./grapheme_diff.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, Error, Empty as $Empty, CustomType as $CustomType, isEqual } from "../gleam.mjs";

/**
 * The two strings are the same. Emit no CRDT operation.
 */
export class NoChange extends $CustomType {}
export const Edit$NoChange$const = new NoChange();
export const Edit$NoChange = () => Edit$NoChange$const;
export const Edit$isNoChange = (value) => value instanceof NoChange;

/**
 * Insert `value` at the grapheme `index`, in the range `0..old_length`.
 */
export class Insert extends $CustomType {
  constructor(index, value) {
    super();
    this.index = index;
    this.value = value;
  }
}
export const Edit$Insert = (index, value) => new Insert(index, value);
export const Edit$isInsert = (value) => value instanceof Insert;
export const Edit$Insert$index = (value) => value.index;
export const Edit$Insert$0 = (value) => value.index;
export const Edit$Insert$value = (value) => value.value;
export const Edit$Insert$1 = (value) => value.value;

/**
 * Delete the graphemes in `[start, end)`.
 */
export class Delete extends $CustomType {
  constructor(start, end) {
    super();
    this.start = start;
    this.end = end;
  }
}
export const Edit$Delete = (start, end) => new Delete(start, end);
export const Edit$isDelete = (value) => value instanceof Delete;
export const Edit$Delete$start = (value) => value.start;
export const Edit$Delete$0 = (value) => value.start;
export const Edit$Delete$end = (value) => value.end;
export const Edit$Delete$1 = (value) => value.end;

/**
 * Replace the graphemes in `[start, end)` with `value`.
 */
export class Replace extends $CustomType {
  constructor(start, end, value) {
    super();
    this.start = start;
    this.end = end;
    this.value = value;
  }
}
export const Edit$Replace = (start, end, value) =>
  new Replace(start, end, value);
export const Edit$isReplace = (value) => value instanceof Replace;
export const Edit$Replace$start = (value) => value.start;
export const Edit$Replace$0 = (value) => value.start;
export const Edit$Replace$end = (value) => value.end;
export const Edit$Replace$1 = (value) => value.end;
export const Edit$Replace$value = (value) => value.value;
export const Edit$Replace$2 = (value) => value.value;

function common_prefix_length(loop$a, loop$b, loop$acc) {
  while (true) {
    let a = loop$a;
    let b = loop$b;
    let acc = loop$acc;
    if (a instanceof $Empty) {
      return acc;
    } else if (b instanceof $Empty) {
      return acc;
    } else {
      let x = a.head;
      let y = b.head;
      if (x === y) {
        let xs = a.tail;
        let ys = b.tail;
        loop$a = xs;
        loop$b = ys;
        loop$acc = acc + 1;
      } else {
        return acc;
      }
    }
  }
}

/**
 * Derive the minimal `Edit` value from `old` to `new`. The function segments
 * both strings into extended grapheme clusters. It is pure and total. It uses
 * no CRDT and no browser offset.
 */
export function diff(old, new$) {
  let $ = old === new$;
  if ($) {
    return Edit$NoChange$const;
  } else {
    let old_graphemes = $string.to_graphemes(old);
    let new_graphemes = $string.to_graphemes(new$);
    let old_length = $list.length(old_graphemes);
    let new_length = $list.length(new_graphemes);
    let prefix = common_prefix_length(old_graphemes, new_graphemes, 0);
    let max_suffix = $int.min(old_length - prefix, new_length - prefix);
    let _block;
    let _pipe = common_prefix_length(
      $list.reverse(old_graphemes),
      $list.reverse(new_graphemes),
      0,
    );
    _block = $int.min(_pipe, max_suffix);
    let suffix = _block;
    let removed_start = prefix;
    let removed_end = old_length - suffix;
    let _block$1;
    let _pipe$1 = new_graphemes;
    let _pipe$2 = $list.drop(_pipe$1, prefix);
    let _pipe$3 = $list.take(_pipe$2, (new_length - suffix) - prefix);
    _block$1 = $string.join(_pipe$3, "");
    let inserted = _block$1;
    let $1 = removed_start === removed_end;
    if ($1) {
      if (inserted === "") {
        return Edit$NoChange$const;
      } else {
        let value = inserted;
        return new Insert(removed_start, value);
      }
    } else if (inserted === "") {
      return new Delete(removed_start, removed_end);
    } else {
      let value = inserted;
      return new Replace(removed_start, removed_end, value);
    }
  }
}

function nudge(index, amount) {
  let $ = (index + amount) < 0;
  if ($) {
    return 0;
  } else {
    return index + amount;
  }
}

/**
 * Re-address an edit, so that it applies to text that moved below it. Every
 * index moves by `by`, and the inserted content does not change.
 *
 * An input method editor (IME) composition needs this function. The component
 * recovers the edit of a composition against the value that the element held
 * when the session opened. The edit thus arrives in the coordinates of a
 * string that can be several remote keystrokes out of date. A `TextAnchor` on
 * the composition site gives the distance that the site moved, and this
 * function moves the edit by that distance.
 *
 * One distance describes the move only while the composed-over region stayed
 * complete. The component thus prefers [`replacement`](#replacement) and
 * [`splice`](#splice), because a resolved span says where *both* ends moved.
 * The component uses this function only when it cannot read the session as one
 * region that changed.
 *
 * An index clamps at zero. A peer can delete more text before the site than
 * the offset of the site, and index 0 is a position that exists, where a
 * negative index is not. The two ends of a range move together, so
 * `start <= end` stays true. Nothing clamps at the upper end. An index after
 * the end of the text is a rejection that the runtime must report. It is not a
 * rejection to move quietly.
 */
export function shift(edit, amount) {
  if (edit instanceof NoChange) {
    return edit;
  } else if (edit instanceof Insert) {
    let index = edit.index;
    let value = edit.value;
    return new Insert(nudge(index, amount), value);
  } else if (edit instanceof Delete) {
    let start = edit.start;
    let end = edit.end;
    return new Delete(nudge(start, amount), nudge(end, amount));
  } else {
    let start = edit.start;
    let end = edit.end;
    let value = edit.value;
    return new Replace(nudge(start, amount), nudge(end, amount), value);
  }
}

/**
 * Recover the text that replaced a known region of `old`.
 *
 * [`diff`](#diff) *infers* the extent of an edit from two strings, which is
 * all that a keystroke gives you. An IME session gives more. It knows the
 * region that it opened over, which is the selection that the user composes
 * across. The extent is thus known, and only the content is in question.
 *
 * That difference is important. Inference cannot separate "the user replaced
 * these five graphemes" from "the user replaced the three of them that
 * changed". Only the first statement can be re-addressed against a document
 * that a peer edited in the same interval.
 *
 * `region` is a half-open grapheme range into `old`. The result is the
 * graphemes of `new` that are now between the same surrounding text.
 *
 * The result is `Error(Nil)` when `new` is not `old` with that region
 * replaced. That occurs when the region is out of bounds or inverted, when
 * `new` is too short to hold the surrounding text, or when the text outside
 * the region moved. This function cannot answer those conditions. The caller
 * must then infer the edit with `diff`.
 */
export function replacement(old, new$, region) {
  let start = region[0];
  let end = region[1];
  let old_graphemes = $string.to_graphemes(old);
  let new_graphemes = $string.to_graphemes(new$);
  let old_length = $list.length(old_graphemes);
  let new_length = $list.length(new_graphemes);
  let tail = old_length - end;
  let $ = (((start < 0) || (end < start)) || (tail < 0)) || ((new_length - tail) < start);
  if ($) {
    return new Error(undefined);
  } else {
    let $1 = isEqual(
      $list.take(old_graphemes, start),
      $list.take(new_graphemes, start)
    );
    let $2 = isEqual(
      $list.drop(old_graphemes, end),
      $list.drop(new_graphemes, (new_length - tail))
    );
    if ($1) {
      if ($2) {
        return new Ok(
          (() => {
            let _pipe = new_graphemes;
            let _pipe$1 = $list.drop(_pipe, start);
            let _pipe$2 = $list.take(_pipe$1, (new_length - tail) - start);
            return $string.join(_pipe$2, "");
          })(),
        );
      } else {
        return new Error(undefined);
      }
    } else if ($2) {
      return new Error(undefined);
    } else {
      return new Error(undefined);
    }
  }
}

/**
 * The edit that puts `value` in place of the graphemes in `[start, end)`,
 * with the most specific constructor that gives the same result.
 *
 * This function is the counterpart of [`replacement`](#replacement). After a
 * caller knows the region and its new content, the operation needs no
 * inference. A caller that has two strings only must use [`diff`](#diff)
 * instead. This function emits an operation that is wider than the change when
 * you ask it to. That result is correct when the *user* selected that extent,
 * and incorrect when a diff only failed to make the extent smaller.
 */
export function splice(start, end, value) {
  let $ = start >= end;
  if ($) {
    if (value === "") {
      return Edit$NoChange$const;
    } else {
      return new Insert(start, value);
    }
  } else if (value === "") {
    return new Delete(start, end);
  } else {
    return new Replace(start, end, value);
  }
}

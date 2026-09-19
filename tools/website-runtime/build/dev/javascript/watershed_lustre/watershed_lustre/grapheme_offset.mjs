/// <reference types="./grapheme_offset.d.mts" />
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $utf16 from "../../watershed/watershed/rich_text/utf16.mjs";
import { Empty as $Empty } from "../gleam.mjs";

/**
 * The UTF-16 offset of the grapheme at `index`. This is where the browser
 * must put a caret that the CRDT calls `index`.
 */
export function to_utf16(text, index) {
  let $ = index <= 0;
  if ($) {
    return 0;
  } else {
    let _pipe = text;
    let _pipe$1 = $string.to_graphemes(_pipe);
    let _pipe$2 = $list.take(_pipe$1, index);
    let _pipe$3 = $string.join(_pipe$2, "");
    return $utf16.length(_pipe$3);
  }
}

function walk(loop$graphemes, loop$offset, loop$consumed, loop$index) {
  while (true) {
    let graphemes = loop$graphemes;
    let offset = loop$offset;
    let consumed = loop$consumed;
    let index = loop$index;
    if (graphemes instanceof $Empty) {
      return index;
    } else {
      let grapheme = graphemes.head;
      let rest = graphemes.tail;
      let next = consumed + $utf16.length(grapheme);
      let $ = next <= offset;
      if ($) {
        loop$graphemes = rest;
        loop$offset = offset;
        loop$consumed = next;
        loop$index = index + 1;
      } else {
        return index;
      }
    }
  }
}

/**
 * The grapheme index that contains the UTF-16 `offset`. This is the name that
 * the CRDT must use for a caret that the browser reported at `offset`.
 */
export function from_utf16(text, offset) {
  let $ = offset <= 0;
  if ($) {
    return 0;
  } else {
    return walk($string.to_graphemes(text), offset, 0, 0);
  }
}

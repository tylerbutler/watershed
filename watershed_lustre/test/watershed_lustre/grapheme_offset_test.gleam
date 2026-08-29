import gleam/list
import gleam/string

import watershed/rich_text/utf16

import watershed_lustre/grapheme_offset

const family = "👩\u{200D}👩\u{200D}👧"

// ── grapheme index → UTF-16 offset ───────────────────────────────────────────

pub fn to_utf16_walks_past_whole_clusters_test() -> Nil {
  assert grapheme_offset.to_utf16("a🌊b", 0) == 0
  assert grapheme_offset.to_utf16("a🌊b", 1) == 1
  assert grapheme_offset.to_utf16("a🌊b", 2) == 3
  assert grapheme_offset.to_utf16("a🌊b", 3) == 4
}

pub fn to_utf16_counts_every_codepoint_of_a_cluster_test() -> Nil {
  // "e" + combining acute is one grapheme, two code units.
  assert grapheme_offset.to_utf16("e\u{0301}x", 1) == 2
  // 👩 ZWJ 👩 ZWJ 👧: one grapheme, three surrogate pairs plus two ZWJs.
  assert grapheme_offset.to_utf16(family <> "x", 1) == 8
}

pub fn to_utf16_clamps_test() -> Nil {
  assert grapheme_offset.to_utf16("abc", -1) == 0
  assert grapheme_offset.to_utf16("abc", 99) == 3
  assert grapheme_offset.to_utf16("", 0) == 0
  assert grapheme_offset.to_utf16("", 5) == 0
}

// ── UTF-16 offset → grapheme index ───────────────────────────────────────────

pub fn from_utf16_maps_cluster_boundaries_test() -> Nil {
  assert grapheme_offset.from_utf16("a🌊b", 0) == 0
  assert grapheme_offset.from_utf16("a🌊b", 1) == 1
  assert grapheme_offset.from_utf16("a🌊b", 3) == 2
  assert grapheme_offset.from_utf16("a🌊b", 4) == 3
}

pub fn an_offset_inside_a_cluster_snaps_backwards_test() -> Nil {
  // Offset 2 sits between the surrogate halves of 🌊 — an index the CRDT has no
  // name for. Snapping back to the cluster's start is the safe direction: the
  // caret lands on a boundary that exists.
  assert grapheme_offset.from_utf16("a🌊b", 2) == 1
  // Same for the interior of a ZWJ sequence.
  assert grapheme_offset.from_utf16(family, 4) == 0
  assert grapheme_offset.from_utf16(family, 8) == 1
}

pub fn from_utf16_clamps_test() -> Nil {
  assert grapheme_offset.from_utf16("abc", -1) == 0
  assert grapheme_offset.from_utf16("abc", 99) == 3
  assert grapheme_offset.from_utf16("", 0) == 0
  assert grapheme_offset.from_utf16("", 5) == 0
}

// ── Round trips ──────────────────────────────────────────────────────────────

pub fn grapheme_index_round_trips_through_utf16_test() -> Nil {
  ["", "hello", "a🌊b", "e\u{0301}x", family, "🌊" <> family <> "é"]
  |> list.each(fn(text) {
    indices(string.length(text))
    |> list.each(fn(index) {
      let offset = grapheme_offset.to_utf16(text, index)
      assert grapheme_offset.from_utf16(text, offset) == index
    })
  })
}

/// Every caret position in a string of `count` graphemes: `0..count`
/// inclusive — one past the last grapheme is where a caret at the end sits.
fn indices(count: Int) -> List(Int) {
  case count <= 0 {
    True -> [0]
    False -> [count, ..indices(count - 1)]
  }
}

pub fn the_end_index_maps_to_the_string_length_test() -> Nil {
  ["", "hello", "a🌊b", family]
  |> list.each(fn(text) {
    assert grapheme_offset.to_utf16(text, string.length(text))
      == utf16.length(text)
  })
}

//// The one presence payload, round-tripped.
////
//// The roster is the showcase's most legible claim — "Dana is in the sudoku
//// panel" — and it rests entirely on this codec: the shell filters peers into
//// panels by pattern-matching `Where`, so a variant that does not survive the
//// wire is a peer who silently vanishes from one panel and appears in none.
////
//// The negative case is the one worth having. Every presence driver in a
//// document broadcasts under the same ripple kind, so a foreign payload is
//// rejected by the *decoder* or not at all. A decoder lenient enough to accept
//// one would invent a peer standing nowhere, which is exactly the failure the
//// single-driver design exists to prevent.

import gleam/json
import gleam/option.{None, Some}
import gleeunit/should

import showcase_lustre/roster.{type ShowcasePresence, ShowcasePresence}
import sudoku_lustre/component as sudoku_panel

fn round_trip(
  payload: ShowcasePresence,
) -> Result(ShowcasePresence, json.DecodeError) {
  roster.encode(payload)
  |> json.to_string
  |> json.parse(roster.decoder())
}

pub fn playlist_presence_round_trips_test() -> Nil {
  let payload =
    ShowcasePresence(name: "dana", color: "#0090ff", where: roster.InPlaylist)

  round_trip(payload)
  |> should.equal(Ok(payload))
}

pub fn sudoku_presence_round_trips_test() -> Nil {
  let payload =
    ShowcasePresence(
      name: "tyler",
      color: "#e5484d",
      where: roster.InSudoku(sudoku_panel.Cursor(
        cell: Some("r3c4"),
        editing: True,
      )),
    )

  round_trip(payload)
  |> should.equal(Ok(payload))
}

pub fn canvas_presence_round_trips_test() -> Nil {
  let payload =
    ShowcasePresence(
      name: "sam",
      color: "#30a46c",
      where: roster.InCanvas(Some("12,7")),
    )

  round_trip(payload)
  |> should.equal(Ok(payload))
}

/// A peer who has not moved yet is still a peer.
pub fn empty_positions_round_trip_test() -> Nil {
  let payload =
    ShowcasePresence(
      name: "sam",
      color: "#30a46c",
      where: roster.InCanvas(None),
    )

  round_trip(payload)
  |> should.equal(Ok(payload))
}

/// The panel label is what the roster chip renders, so it is worth pinning.
pub fn panel_labels_are_stable_test() -> Nil {
  roster.panel_label(roster.InText(None)) |> should.equal("text")
  roster.panel_label(roster.InPlaylist) |> should.equal("playlist")
  roster.panel_label(roster.InCanvas(None)) |> should.equal("canvas")
  roster.panel_label(
    roster.InSudoku(sudoku_panel.Cursor(cell: None, editing: False)),
  )
  |> should.equal("sudoku")
}

/// A foreign payload — another app's presence on the same ripple kind — must
/// not decode into a phantom peer.
pub fn a_foreign_payload_does_not_decode_test() -> Nil {
  let foreign =
    json.object([
      #("cursor", json.string("wherever")),
      #("editing", json.bool(True)),
    ])
    |> json.to_string

  json.parse(foreign, roster.decoder())
  |> should.be_error
  Nil
}

/// A peer running a build with a fifth panel still appears in the roster.
///
/// Dropping the entry would be the worse failure: the client is genuinely
/// there, and a roster that hides them is wrong in a way a slightly imprecise
/// label is not.
pub fn an_unknown_panel_still_yields_a_peer_test() -> Nil {
  let newer =
    json.object([
      #("name", json.string("ada")),
      #("color", json.string("#8e4ec6")),
      #("panel", json.string("spreadsheet")),
      #("at", json.string("B12")),
    ])
    |> json.to_string

  json.parse(newer, roster.decoder())
  |> should.equal(
    Ok(ShowcasePresence(name: "ada", color: "#8e4ec6", where: roster.InPlaylist)),
  )
}

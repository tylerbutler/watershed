//// The showcase's presence payload: one shape for the whole document.
////
//// **Why one.** `watershed_lustre.presence` takes a `Document` and a single
//// payload codec, with no topic parameter, and every driver broadcasts under
//// the one global `presence.ripple_type`. Two panels each starting a driver
//// would therefore receive each other's envelopes: the `kind` check passes,
//// because the constant is shared, and only the payload decoder rejects them —
//// silently. Best case each panel sees a partial roster; worst case a lenient
//// decoder accepts a foreign payload and invents a peer.
////
//// So there is one driver, owned by the shell, and one payload type. Identity
//// — the name and colour of a client — sits at the top level, because it is
//// true of the client no matter which panel they are looking at. What they are
//// *doing* is a [`Where`](#Where), one variant per panel, carrying whatever
//// that panel needs to draw a peer.
////
//// That shape is what makes the showcase's one legible claim sayable: "Tyler
//// is in the sudoku panel" needs a roster that spans panels, and four separate
//// apps cannot produce one.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

import watershed_lustre/textarea

import sudoku_lustre/component as sudoku_panel

/// Where a client is, and what they are doing there.
///
/// A variant per panel. The unit variants are not placeholders — a playlist has
/// no per-peer cursor to draw, so "in the playlist" is the whole of what there
/// is to say.
pub type Where {
  InText(cursor: Option(textarea.Cursor))
  InPlaylist
  InSudoku(cursor: sudoku_panel.Cursor)
  InCanvas(cell: Option(String))
}

/// One peer's presence: who they are, and where.
pub type ShowcasePresence {
  ShowcasePresence(name: String, color: String, where: Where)
}

/// The panel label shown in the roster chip.
pub fn panel_label(where: Where) -> String {
  case where {
    InText(_) -> "text"
    InPlaylist -> "playlist"
    InSudoku(_) -> "sudoku"
    InCanvas(_) -> "canvas"
  }
}

pub fn encode(p: ShowcasePresence) -> Json {
  json.object([
    #("name", json.string(p.name)),
    #("color", json.string(p.color)),
    #("panel", json.string(panel_label(p.where))),
    #("at", encode_where(p.where)),
  ])
}

fn encode_where(where: Where) -> Json {
  case where {
    InText(cursor) ->
      case cursor {
        Some(cursor) -> textarea.cursor_to_json(cursor)
        None -> json.null()
      }
    InPlaylist -> json.null()
    InSudoku(cursor) -> sudoku_panel.encode_cursor(cursor)
    InCanvas(cell) ->
      case cell {
        Some(cell) -> json.string(cell)
        None -> json.null()
      }
  }
}

/// Decode a peer's payload.
///
/// The `panel` tag picks the `at` decoder, and an unrecognised tag decodes to
/// `InPlaylist`-shaped nothing rather than failing the whole entry: a peer
/// running a newer build with a fifth panel should still appear in the roster
/// as *somebody*, just not somewhere this build can draw.
pub fn decoder() -> Decoder(ShowcasePresence) {
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.string)
  use panel <- decode.field("panel", decode.string)
  use where <- decode.then(where_decoder(panel))
  decode.success(ShowcasePresence(name:, color:, where:))
}

fn where_decoder(panel: String) -> Decoder(Where) {
  case panel {
    "text" -> {
      use cursor <- decode.optional_field(
        "at",
        None,
        decode.optional(textarea.cursor_decoder()),
      )
      decode.success(InText(cursor))
    }
    "sudoku" -> {
      use cursor <- decode.optional_field(
        "at",
        sudoku_panel.Cursor(cell: None, editing: False),
        sudoku_panel.cursor_decoder(),
      )
      decode.success(InSudoku(cursor))
    }
    "canvas" -> {
      use cell <- decode.optional_field(
        "at",
        None,
        decode.optional(decode.string),
      )
      decode.success(InCanvas(cell))
    }
    _ -> decode.success(InPlaylist)
  }
}

//// Typed schema for the showcase's root document.
////
//// Every key is a `ChildField`: a handle to a nested typed map carrying a
//// *different* phantom tag. That is the whole composition mechanism. Each
//// panel's own `doc_schema` was always scoped to its own tag rather than to
//// "the root", so those schemas work unchanged against a child map — nothing
//// in `text_lustre/doc_schema` knows or cares that its map is now one level
//// down.
////
//// The rule this file exists to enforce: **only this schema may touch the root
//// map.** A panel that reaches for `root_typed` shares the root's key
//// namespace with three other panels, silently. `Document(root)` makes the tag
//// checkable — a `Document(Showcase)` will not hand out a `TypedMap(TextDoc)`
//// for its root — and `showcase_test`'s root-purity assertion is the mechanical
//// detector for a regression.
////
//// Note the root cannot be described by a record `Schema`: `schema.prop` takes
//// a `Field(s, a)` and there is no `ChildField` equivalent, so `sealed_known`
//// is unavailable here. With every key a child field there is no record to
//// describe in the first place.

import watershed/schema.{type ChildField}

import pixel_canvas_lustre/doc_schema as canvas_schema
import playlist_lustre/doc_schema as playlist_schema
import sudoku_lustre/doc_schema as sudoku_schema
import text_lustre/doc_schema as text_schema

/// Phantom tag for the root map. Only the fields below may be read from it.
pub type Showcase

/// The plain-text editor's sub-document.
pub fn text() -> ChildField(Showcase, text_schema.TextDoc) {
  schema.child_field("text")
}

/// The playlist's sub-document.
pub fn playlist() -> ChildField(Showcase, playlist_schema.PlaylistDoc) {
  schema.child_field("playlist")
}

/// The sudoku board's sub-document.
pub fn sudoku() -> ChildField(Showcase, sudoku_schema.SudokuDoc) {
  schema.child_field("sudoku")
}

/// The pixel canvas's sub-document.
pub fn canvas() -> ChildField(Showcase, canvas_schema.CanvasDoc) {
  schema.child_field("canvas")
}

/// Every key this schema declares, in panel order.
///
/// The root-purity test compares `entries(root)` against exactly this list, so
/// adding a panel means adding it here and nowhere else.
pub fn keys() -> List(String) {
  ["text", "playlist", "sudoku", "canvas"]
}

//// A fixture that must NOT compile.
////
//// `just test-compile-fail` builds this package and fails if the build
//// *succeeds*. It is the executable form of the one guarantee `Document(root)`
//// exists to give: a document admits exactly one root schema.
////
//// Nothing else in the repo can assert this. Every other test proves that
//// correct code compiles; only a fixture like this proves that incorrect code
//// does not — and the failure it guards against, two apps quietly sharing the
//// root map's key namespace, is invisible at runtime until their keys collide.
////
//// The recipe greps for the expected type error rather than merely checking
//// the exit code, so a typo cannot make this fixture "pass" for the wrong
//// reason.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{type Field}
import watershed.{type Document}

/// Two unrelated apps' root schemas.
pub type Playlist

pub type Sudoku

pub fn playlist_title() -> Field(Playlist, String) {
  schema.field("title", json.string, decode.string)
}

pub fn sudoku_title() -> Field(Sudoku, String) {
  schema.field("title", json.string, decode.string)
}

/// The document is pinned to `Playlist` by this annotation, so the second read
/// below cannot typecheck.
pub fn read_both(doc: Document(Playlist)) {
  let root = watershed.root_typed(doc)
  let as_playlist = watershed.get_field(root, playlist_title())

  // Expected error: `root_typed` returns `TypedMap(Playlist)`, so a
  // `Field(Sudoku, _)` cannot be read against it.
  let as_sudoku = watershed.get_field(root, sudoku_title())

  #(as_playlist, as_sudoku)
}

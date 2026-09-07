import gleam/list
import gleam/string
import gleeunit/should
import watershed_site/content
import watershed_site/route
import watershed_site/snippet

pub fn connect_page_contains_the_complete_guide_test() {
  let assert Ok(source) = content.load(route.guide_connect())
  source.metadata.description
  |> should.equal(
    "Step one of the watershed build guide: connect the tutorial retro board to a live document, wait for it to finish catching up before you build on it, and set up its two maps with ensure_or_map before the first render.",
  )
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  content.validate_snippets(source.document, manifest, source.path)
  |> should.be_ok()
  [
    "Connect to a live document",
    "Connecting is a declared effect, not a callback",
    "The handle and the handshake are two different events",
    "Define the board's fields",
    "Create the shared maps",
    "Build the board only when both channels are ready",
    "Deepening: the same thing on the BEAM",
    "Run it",
    "connected · board ready · 0 notes",
  ]
  |> list.each(fn(text) {
    string.contains(source.body, text) |> should.be_true()
  })
  [
    "guide-connect-dev-constants",
    "guide-connect-main",
    "guide-connect-init",
    "guide-connect-readiness",
    "guide-connect-bootstrap",
    "guide-connect-schema",
    "guide-connect-assemble",
    "guide-connect-gleam-toml",
  ]
  |> list.each(fn(id) {
    string.contains(source.body, "data-snippet=\"" <> id <> "\"")
    |> should.be_true()
  })
  [
    "ffi-surface",
    "claims-seeding",
    "shared-core-two-runtimes",
  ]
  |> list.each(fn(id) {
    string.contains(source.body, "data-practice=\"" <> id <> "\"")
    |> should.be_true()
  })
  [
    "data-source-label=\"watershed_beam (comparison)\"",
    "data-source-label=\"examples/retro_tutorial_lustre/\"",
    "data-source-label=\"(shell)\"",
    "document_on_navigate reads %3Fdocument%3D from the URL",
    "watershed_beam · for comparison only, the tutorial stays in the browser",
  ]
  |> list.each(fn(text) {
    string.contains(source.body, text) |> should.be_true()
  })
}

pub fn notes_page_contains_the_complete_guide_test() {
  let assert Ok(source) = content.load(route.guide_notes())
  source.metadata.description
  |> should.equal(
    "Step two of the watershed build guide: add a note to the board, keyed by its own id in a register OR-map, stored as one JSON value, and read back through a decoder that shows a broken note instead of crashing the board.",
  )
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  content.validate_snippets(source.document, manifest, source.path)
  |> should.be_ok()
  [
    "Each note gets its own id",
    "The whole note is one register",
    "Adding a note is one map write",
    "Reading back: entries in, board out",
    "Deepening: the column you don't recognise",
    "Open the board in two tabs",
  ]
  |> list.each(fn(text) {
    string.contains(source.body, text) |> should.be_true()
  })
  [
    "guide-notes-note-record",
    "guide-notes-codec",
    "guide-notes-add-note",
    "guide-notes-note-entries",
    "guide-notes-ordering",
    "guide-notes-unfiled",
    "guide-notes-add-clicked",
  ]
  |> list.each(fn(id) {
    string.contains(source.body, "data-snippet=\"" <> id <> "\"")
    |> should.be_true()
  })
  ["authoritative-channel", "stamp-schema"]
  |> list.each(fn(id) {
    string.contains(source.body, "data-practice=\"" <> id <> "\"")
    |> should.be_true()
  })
}

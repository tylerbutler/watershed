import gleam/list
import gleam/string
import gleeunit/should
import support
import watershed_site/content
import watershed_site/snippet

pub fn connect_page_contains_the_complete_guide_test() {
  let assert Ok(source) = content.load(support.route("/guide/connect"))
  source.metadata.description
  |> should.equal(
    "Step one of the watershed build guide: connect the tutorial retro board to a live document, wait for it to finish catching up before you build on it, and set up its two maps with ensure_or_map before the first render.",
  )
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
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
  let assert Ok(source) = content.load(support.route("/guide/notes"))
  source.metadata.description
  |> should.equal(
    "Step two of the watershed build guide: add a note to the board, keyed by its own id in a register OR-map, stored as one JSON value, and read back through a decoder that shows a broken note instead of crashing the board.",
  )
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
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

pub fn votes_page_contains_the_complete_guide_test() {
  let assert Ok(source) = content.load(support.route("/guide/votes"))
  source.metadata.description
  |> should.equal(
    "Step four of the watershed build guide: store vote totals in a map where each key adds up changes instead of overwriting them, so votes cast at the same instant sum correctly instead of clobbering each other.",
  )
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
  content.validate_snippets(source.document, manifest, source.path)
  |> should.be_ok()
  [
    "a counter per key",
    "Why not read, add one, write back?",
    "Two channels, one board",
    "Deepening: what a tally deliberately can't do",
    "Open two tabs, hammer",
  ]
  |> list.each(fn(text) {
    string.contains(source.body, text) |> should.be_true()
  })
  [
    "guide-votes-vote-ops",
    "guide-votes-vote-entries",
    "guide-votes-card",
    "guide-votes-vote-clicks",
    "guide-votes-orphan-test",
  ]
  |> list.each(fn(id) {
    string.contains(source.body, "data-snippet=\"" <> id <> "\"")
    |> should.be_true()
  })
  [
    "data-source-label=\"(illustrative — not in the tutorial source)\"",
    "the tally for a note that isn't there renders nowhere and breaks nothing",
    "data-practice=\"unsettled-writes\"",
  ]
  |> list.each(fn(text) {
    string.contains(source.body, text) |> should.be_true()
  })
}

pub fn presence_page_contains_the_complete_guide_test() {
  let assert Ok(source) = content.load(support.route("/guide/presence"))
  source.metadata.description
  |> should.equal(
    "Step five of the watershed build guide: publish the note a teammate is reading through presence, a roster that clears itself out when someone leaves, instead of storing it in the document where it would stick around forever.",
  )
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
  content.validate_snippets(source.document, manifest, source.path)
  |> should.be_ok()
  [
    "Some facts should be allowed to expire",
    "Declare what a teammate broadcasts",
    "One effect handles all of it",
    "Publishing a change is republishing the whole payload",
    "The roster arrives as events, including the bad ones",
    "Deepening: one highlight, built from two systems",
    "Click *Focus* in one tab",
  ]
  |> list.each(fn(text) {
    string.contains(source.body, text) |> should.be_true()
  })
  [
    "guide-presence-payload",
    "guide-presence-effect",
    "guide-presence-announce",
    "guide-presence-focus-clicked",
    "guide-presence-events",
    "guide-presence-remote-peers",
    "guide-presence-focus-names",
  ]
  |> list.each(fn(id) {
    string.contains(source.body, "data-snippet=\"" <> id <> "\"")
    |> should.be_true()
  })
  ["presence-idiom", "protocol-on-ripples"]
  |> list.each(fn(id) {
    string.contains(source.body, "data-practice=\"" <> id <> "\"")
    |> should.be_true()
  })
}

pub fn testing_page_contains_the_complete_guide_test() {
  let assert Ok(source) = content.load(support.route("/guide/testing"))
  source.metadata.description
  |> should.equal(
    "Step six of the watershed build guide: run two clients in one Gleam test and control when each message arrives.",
  )
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
  content.validate_snippets(source.document, manifest, source.path)
  |> should.be_ok()
  [
    "Run two clients in one test",
    "Choose when messages arrive",
    "Assert on the board, not on the map",
    "Both races, written as tests",
    "Deepening: script the intermediate state",
    "The finished project",
    "Where to go when this board gets too small",
    "Run `gleam test` and get a clean pass",
  ]
  |> list.each(fn(text) {
    string.contains(source.body, text) |> should.be_true()
  })
  [
    "guide-testing-room",
    "guide-testing-board-of",
    "guide-testing-add-race",
    "guide-testing-vote-race",
  ]
  |> list.each(fn(id) {
    string.contains(source.body, "data-snippet=\"" <> id <> "\"")
    |> should.be_true()
  })
  [
    "data-source-label=\"(illustrative — scripted delivery)\"",
    "data-source-label=\"examples/retro_tutorial_lustre/\"",
    "data-source-label=\"(shell)\"",
    "data-practice=\"pure-modules\"",
    "data-practice=\"deterministic-death\"",
  ]
  |> list.each(fn(text) {
    string.contains(source.body, text) |> should.be_true()
  })
}

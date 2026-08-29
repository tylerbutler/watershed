//// Four apps in one document, asserted rather than eyeballed.
////
//// The showcase's claims are structural — that the root holds exactly four
//// child handles, that every client agrees which four, that a panel's state
//// converges from inside a child map the same way it did from a root, and that
//// the connection they share is genuinely shared. All four are checkable
//// without a server or a browser: the in-memory `sluice_js` delivers every
//// frame explicitly, so `settle` drains the room before the assertions read it
//// and there is nothing to wait for.
////
//// What is *not* here: the pixels themselves and the rendered DOM. The FFI
//// owns the canvas surface, so "the picture is right" is not assertable from a
//// test — what the tests can assert is the OR-map behind it, which is what the
//// convergence cases below do.

import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

import watershed.{type Document, type TypedMap}
import watershed/or_map_kernel
import watershed/schema.{type ChildField}
import watershed/sluice_js.{type Sluice}

import pixel_canvas_lustre/doc_schema as canvas_schema
import pixel_canvas_lustre/grid
import playlist_lustre/doc_schema as playlist_schema
import showcase_lustre/doc_schema
import sudoku_lustre/doc_schema as sudoku_schema
import text_lustre/doc_schema as text_schema

// ── Harness ──────────────────────────────────────────────────────────────────

/// A room with the four child maps seeded, exactly as the shell's bootstrap
/// batch would leave it.
///
/// The shell uses `ensure_child`, which resolves through a retry loop on a
/// timer. That is right in a browser and wrong here — the sluice's whole point
/// is synchronous, deterministic delivery — so this seeds the handles directly
/// and keeps the assertions free of waiting.
fn room(name: String) -> #(Sluice, Document(doc_schema.Showcase)) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  seed_children(doc)
  sluice_js.settle(sluice)
  #(sluice, doc)
}

/// Seed one child map per declared key, the way `bootstrap_effect` does.
fn seed_children(doc: Document(doc_schema.Showcase)) -> Nil {
  let root = watershed.root_typed(doc)
  seed_child(doc, root, doc_schema.text())
  seed_child(doc, root, doc_schema.playlist())
  seed_child(doc, root, doc_schema.sudoku())
  seed_child(doc, root, doc_schema.canvas())
}

fn seed_child(
  doc: Document(doc_schema.Showcase),
  root: TypedMap(doc_schema.Showcase),
  field: ChildField(doc_schema.Showcase, c),
) -> Nil {
  let assert Ok(child) = watershed.create_map(doc)
  watershed.set_child(root, field, watershed.typed(child))
}

/// The root's keys, sorted — what the root-purity assertion compares.
fn root_keys(doc: Document(doc_schema.Showcase)) -> List(String) {
  watershed.keys(watershed.root(doc)) |> list.sort(string.compare)
}

/// The root's handles, keyed, so two clients can be compared handle for handle.
fn root_handles(doc: Document(doc_schema.Showcase)) -> List(#(String, String)) {
  watershed.entries(watershed.root(doc))
  |> list.map(fn(entry) { #(entry.0, json.to_string(entry.1)) })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

// ── Root purity ──────────────────────────────────────────────────────────────

/// The mechanical detector for the showcase's central rule: only the showcase
/// schema touches the root map.
///
/// This is the test that fails the day someone reaches for `root_typed` inside
/// a panel — a stray `title` or `pixels` key at the root shows up here as an
/// extra entry, whatever else still works.
pub fn root_holds_exactly_the_declared_children_test() -> Nil {
  let #(_sluice, doc) = room("purity")

  root_keys(doc)
  |> should.equal(list.sort(doc_schema.keys(), string.compare))
}

/// Every declared key resolves to a map, not to a leftover scalar.
pub fn every_child_key_resolves_to_a_map_test() -> Nil {
  let #(_sluice, doc) = room("purity-resolves")
  let root = watershed.root_typed(doc)

  let assert Ok(Some(_)) = watershed.resolve_child(doc, root, doc_schema.text())
  let assert Ok(Some(_)) =
    watershed.resolve_child(doc, root, doc_schema.playlist())
  let assert Ok(Some(_)) =
    watershed.resolve_child(doc, root, doc_schema.sudoku())
  let assert Ok(Some(_)) =
    watershed.resolve_child(doc, root, doc_schema.canvas())
  Nil
}

/// A panel's own keys live in its own map, and are invisible from the root.
///
/// This is the property that makes four schemas safe in one document: the text
/// panel's `title` and the sudoku panel's `title` are different keys in
/// different maps, and neither is a root key at all.
pub fn panel_keys_do_not_leak_into_the_root_test() -> Nil {
  let #(sluice, doc) = room("no-leak")
  let root = watershed.root_typed(doc)

  let assert Ok(Some(text_map)) =
    watershed.resolve_child(doc, root, doc_schema.text())
  let assert Ok(Some(sudoku_map)) =
    watershed.resolve_child(doc, root, doc_schema.sudoku())

  watershed.set_field(text_map, text_schema.title(), "a document")
  watershed.set_field(sudoku_map, sudoku_schema.title(), "a puzzle")
  sluice_js.settle(sluice)

  // Both panels wrote a key called `title`. Neither reached the root, and
  // neither overwrote the other.
  root_keys(doc)
  |> should.equal(list.sort(doc_schema.keys(), string.compare))
  watershed.get_field(text_map, text_schema.title())
  |> should.equal(Ok(Some("a document")))
  watershed.get_field(sudoku_map, sudoku_schema.title())
  |> should.equal(Ok(Some("a puzzle")))
}

// ── The cold-document race ───────────────────────────────────────────────────

/// Two clients bootstrapping a brand-new document at the same time converge on
/// the *same* four child handles.
///
/// `ensure_child` checks for the key and, if absent, creates and sets — so two
/// clients opening a cold document both create a map and LWW settles a single
/// handle, orphaning the loser. That race predates the showcase; what is new is
/// running it four times per cold start instead of once. It converges, and the
/// loss window is before anybody has interacted, so the plan accepts it — but
/// "they converge" is exactly the kind of claim that should be a test rather
/// than a paragraph.
pub fn racing_clients_agree_on_one_set_of_children_test() -> Nil {
  let sluice = sluice_js.start(tenant: "default", document: "cold-race")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  // Both clients bootstrap before either has seen the other's writes.
  seed_children(doc_a)
  seed_children(doc_b)
  sluice_js.settle(sluice)

  root_keys(doc_a)
  |> should.equal(list.sort(doc_schema.keys(), string.compare))
  root_handles(doc_a)
  |> should.equal(root_handles(doc_b))
}

// ── Per-panel convergence, from inside a child map ───────────────────────────

/// The playlist converges when it is a child rather than a root.
///
/// This is the same claim `playlist_lustre` already makes standalone, run
/// against the nested map — the point being that nesting changed nothing.
pub fn playlist_converges_inside_its_child_map_test() -> Nil {
  let #(sluice, doc_a, doc_b) = two_client_room("playlist-nested")
  let #(tracks_a, tracks_b) = playlist_channels(sluice, doc_a, doc_b)

  let assert Ok(_) =
    watershed.sequence_insert(tracks_a, 0, json.string("first"))
  let assert Ok(_) =
    watershed.sequence_insert(tracks_b, 0, json.string("second"))
  sluice_js.settle(sluice)

  watershed.sequence_values(tracks_a)
  |> list.map(json.to_string)
  |> should.equal(
    watershed.sequence_values(tracks_b) |> list.map(json.to_string),
  )
}

/// The canvas converges when it is a child, including across a partition.
///
/// The partition half is the shell's offline control asserted: `go_offline`
/// takes the *document*, so this is also the setup for
/// `offline_partitions_every_panel_test` below.
pub fn canvas_converges_inside_its_child_map_test() -> Nil {
  let #(sluice, doc_a, doc_b) = two_client_room("canvas-nested")
  let #(pixels_a, pixels_b) = canvas_channels(sluice, doc_a, doc_b)

  watershed.or_map_set(pixels_a, grid.encode(1, 1), "3")
  watershed.or_map_set(pixels_b, grid.encode(2, 2), "4")
  sluice_js.settle(sluice)

  picture(pixels_a) |> should.equal(picture(pixels_b))
  picture(pixels_a)
  |> list.length
  |> should.equal(2)
}

// ── The promoted offline control ─────────────────────────────────────────────

/// Taking the document offline stops *every* panel, and coming back converges
/// every panel.
///
/// This is the assertion behind promoting the toggle into the chrome. It fails
/// if someone re-scopes the control to a panel — the whole point being that it
/// cannot be scoped, because the connection is per-document. It also covers the
/// join the canvas exists to demonstrate: the offline client's cells are not
/// replayed on return, the two states join.
pub fn offline_partitions_every_panel_test() -> Nil {
  let #(sluice, doc_a, doc_b) = two_client_room("partition")
  let #(pixels_a, pixels_b) = canvas_channels(sluice, doc_a, doc_b)
  let #(tracks_a, tracks_b) = playlist_channels(sluice, doc_a, doc_b)

  watershed.go_offline(doc_a)

  // A writes to two different panels while partitioned; B writes to both too.
  watershed.or_map_set(pixels_a, grid.encode(5, 5), "7")
  let assert Ok(_) =
    watershed.sequence_insert(tracks_a, 0, json.string("offline-track"))
  watershed.or_map_set(pixels_b, grid.encode(9, 9), "2")
  let assert Ok(_) =
    watershed.sequence_insert(tracks_b, 0, json.string("online-track"))
  sluice_js.settle(sluice)

  // The partition is document-wide: neither panel saw the other side. Each
  // client's *own* write is asserted first, so a lookup failing for some
  // unrelated reason — an empty map, a mis-encoded key — cannot pass this.
  picture(pixels_a)
  |> list.key_find(grid.encode(5, 5))
  |> should.equal(Ok("7"))
  picture(pixels_a)
  |> list.key_find(grid.encode(9, 9))
  |> should.be_error
  picture(pixels_b)
  |> list.key_find(grid.encode(9, 9))
  |> should.equal(Ok("2"))
  picture(pixels_b)
  |> list.key_find(grid.encode(5, 5))
  |> should.be_error
  // Same for the playlist: A holds only its own row while partitioned.
  watershed.sequence_values(tracks_a)
  |> list.length
  |> should.equal(1)

  watershed.go_online(doc_a)
  sluice_js.settle(sluice)

  // And so is the reconciliation: every panel converges, in one reconnect.
  picture(pixels_a) |> should.equal(picture(pixels_b))
  picture(pixels_a) |> list.length |> should.equal(2)
  watershed.sequence_values(tracks_a)
  |> list.map(json.to_string)
  |> should.equal(
    watershed.sequence_values(tracks_b) |> list.map(json.to_string),
  )
}

// ── Shared harness ───────────────────────────────────────────────────────────

fn two_client_room(
  name: String,
) -> #(Sluice, Document(doc_schema.Showcase), Document(doc_schema.Showcase)) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)
  seed_children(doc_a)
  sluice_js.settle(sluice)
  #(sluice, doc_a, doc_b)
}

fn canvas_channels(
  sluice: Sluice,
  doc_a: Document(doc_schema.Showcase),
  doc_b: Document(doc_schema.Showcase),
) -> #(watershed.OrMap, watershed.OrMap) {
  let assert Ok(Some(map_a)) =
    watershed.resolve_child(
      doc_a,
      watershed.root_typed(doc_a),
      doc_schema.canvas(),
    )
  let assert Ok(Some(map_b)) =
    watershed.resolve_child(
      doc_b,
      watershed.root_typed(doc_b),
      doc_schema.canvas(),
    )
  let assert Ok(seed) =
    watershed.create_or_map(doc_a, or_map_kernel.RegisterMode)
  watershed.set(
    watershed.untyped(map_a),
    "pixels",
    watershed.or_map_handle_of(seed),
  )
  sluice_js.settle(sluice)
  #(or_map_of(doc_a, map_a), or_map_of(doc_b, map_b))
}

fn or_map_of(
  doc: Document(doc_schema.Showcase),
  map: TypedMap(canvas_schema.CanvasDoc),
) -> watershed.OrMap {
  let assert Ok(handle) = watershed.get(watershed.untyped(map), "pixels")
  let assert Ok(pixels) = watershed.resolve_or_map(doc, handle)
  pixels
}

fn playlist_channels(
  sluice: Sluice,
  doc_a: Document(doc_schema.Showcase),
  doc_b: Document(doc_schema.Showcase),
) -> #(watershed.SharedSequence, watershed.SharedSequence) {
  let assert Ok(Some(map_a)) =
    watershed.resolve_child(
      doc_a,
      watershed.root_typed(doc_a),
      doc_schema.playlist(),
    )
  let assert Ok(Some(map_b)) =
    watershed.resolve_child(
      doc_b,
      watershed.root_typed(doc_b),
      doc_schema.playlist(),
    )
  let assert Ok(seed) = watershed.create_sequence(doc_a)
  watershed.set(
    watershed.untyped(map_a),
    "tracks",
    watershed.sequence_handle_of(seed),
  )
  sluice_js.settle(sluice)
  #(sequence_of(doc_a, map_a), sequence_of(doc_b, map_b))
}

fn sequence_of(
  doc: Document(doc_schema.Showcase),
  map: TypedMap(playlist_schema.PlaylistDoc),
) -> watershed.SharedSequence {
  let assert Ok(handle) = watershed.get(watershed.untyped(map), "tracks")
  let assert Ok(sequence) = watershed.resolve_sequence(doc, handle)
  sequence
}

/// The whole picture, sorted — the comparison the demo makes by eye.
fn picture(pixels: watershed.OrMap) -> List(#(String, String)) {
  watershed.or_map_entries(pixels)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Register(value) -> Ok(#(entry.0, value))
      or_map_kernel.Tally(_) -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

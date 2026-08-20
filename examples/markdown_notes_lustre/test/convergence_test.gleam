//// The demo's races, executed: two clients over the in-memory sluice.
////
//// The app bootstraps its channels with `ensure_*`, which resolves through a
//// retry loop on a timer. That is right in a browser and wrong here — the
//// sluice's whole point is synchronous, deterministic delivery — so the
//// harness seeds the three handles directly and keeps the assertions free of
//// waiting.
////
//// Register values are wall-clock LWW tie-broken by replica id, so no test
//// asserts *which* handle wins a concurrent create — only that the room
//// agrees on one.

import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

import markdown_notes_lustre/note_handle
import watershed/or_map_kernel
import watershed/sluice_js.{type Sluice}
import watershed_js.{type Document, type SharedText}

import doc_schema

// ── Harness ──────────────────────────────────────────────────────────────────

/// One client's view of the three channels, mirroring the app's `SharedState`.
type Channels {
  Channels(
    notes: watershed_js.OrMap,
    tags: watershed_js.OrSet,
    order: watershed_js.SharedSequence,
  )
}

/// A room with all three channels seeded on client A and resolved on both.
fn room(
  name: String,
) -> #(
  Sluice,
  Document(doc_schema.Notebook),
  Document(doc_schema.Notebook),
  Channels,
  Channels,
) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let root = watershed_js.root(doc_a)
  let assert Ok(notes) =
    watershed_js.create_or_map(doc_a, or_map_kernel.RegisterMode)
  watershed_js.set(root, "notes", watershed_js.or_map_handle_of(notes))
  let assert Ok(tags) = watershed_js.create_or_set(doc_a)
  watershed_js.set(root, "tags", watershed_js.or_set_handle_of(tags))
  let assert Ok(order) = watershed_js.create_sequence(doc_a)
  watershed_js.set(root, "order", watershed_js.sequence_handle_of(order))
  sluice_js.settle(sluice)

  #(sluice, doc_a, doc_b, channels_of(doc_a), channels_of(doc_b))
}

fn channels_of(doc: Document(doc_schema.Notebook)) -> Channels {
  let root = watershed_js.root(doc)
  let assert Some(notes_handle) = watershed_js.get(root, "notes")
  let assert Ok(notes) = watershed_js.resolve_or_map(doc, notes_handle)
  let assert Some(tags_handle) = watershed_js.get(root, "tags")
  let assert Ok(tags) = watershed_js.resolve_or_set(doc, tags_handle)
  let assert Some(order_handle) = watershed_js.get(root, "order")
  let assert Ok(order) = watershed_js.resolve_sequence(doc, order_handle)
  Channels(notes:, tags:, order:)
}

/// Create a note exactly as the app does: a fresh detached text channel, the
/// seed line, then the handle into the notes map (which attaches it).
fn create_note(
  doc: Document(doc_schema.Notebook),
  channels: Channels,
  name: String,
) -> SharedText {
  let assert Ok(text) = watershed_js.create_text(doc)
  let assert Ok(Nil) = watershed_js.text_append(text, "# " <> name <> "\n")
  watershed_js.or_map_set_json(
    channels.notes,
    name,
    watershed_js.text_handle_of(text),
  )
  text
}

/// Open a note exactly as the app does: register string → handle marker →
/// resolved channel.
fn open_note(
  doc: Document(doc_schema.Notebook),
  channels: Channels,
  name: String,
) -> SharedText {
  let assert Some(or_map_kernel.Register(register)) =
    watershed_js.or_map_value(channels.notes, name)
  let assert Ok(handle) = note_handle.parse(register)
  let assert Ok(text) = watershed_js.resolve_text(doc, handle)
  text
}

fn note_names(channels: Channels) -> List(String) {
  watershed_js.or_map_entries(channels.notes)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Register(_) -> Ok(entry.0)
      or_map_kernel.Tally(_) -> Error(Nil)
    }
  })
  |> list.sort(by: string.compare)
}

// ── MN2: the handle-in-register round trip ───────────────────────────────────

/// The novel claim this example makes: a `SharedText` handle stored as an
/// OR-map register value resolves on a client that has never seen the
/// channel, with the seed content intact.
pub fn created_note_opens_identically_on_the_other_client_test() {
  let #(sluice, doc_a, doc_b, channels_a, channels_b) = room("mn2-round-trip")

  let text_a = create_note(doc_a, channels_a, "meeting notes")
  sluice_js.settle(sluice)

  note_names(channels_b) |> should.equal(["meeting notes"])
  let text_b = open_note(doc_b, channels_b, "meeting notes")
  watershed_js.text_value(text_b)
  |> should.equal(watershed_js.text_value(text_a))
  watershed_js.text_value(text_b) |> should.equal("# meeting notes\n")
}

// ── MN3: concurrent typing in one note ───────────────────────────────────────

/// Two clients type in the same note concurrently — the ops the textarea
/// component itself would submit — and converge on the same bytes.
pub fn concurrent_typing_in_one_note_converges_test() {
  let #(sluice, doc_a, doc_b, channels_a, channels_b) = room("mn3-typing")

  let text_a = create_note(doc_a, channels_a, "draft")
  sluice_js.settle(sluice)
  let text_b = open_note(doc_b, channels_b, "draft")

  // Concurrent: both edit before either delivery. A appends a line while B
  // inserts inside the heading.
  let assert Ok(Nil) = watershed_js.text_append(text_a, "alpha from a\n")
  let assert Ok(Nil) = watershed_js.text_insert(text_b, 2, "shared ")
  sluice_js.settle(sluice)

  watershed_js.text_value(text_a)
  |> should.equal(watershed_js.text_value(text_b))
  watershed_js.text_value(text_a)
  |> should.equal("# shared draft\nalpha from a\n")
}

/// Race 3: both clients create the same name concurrently. The registers
/// converge on one handle; both clients open the same channel and see the
/// same bytes (the survivor's seed). The loser's channel becomes unreachable
/// garbage — harmless — and neither creator sees an error.
pub fn concurrent_create_same_name_converges_on_one_handle_test() {
  let #(sluice, doc_a, doc_b, channels_a, channels_b) = room("mn2-create-race")

  let _ = create_note(doc_a, channels_a, "shared")
  let _ = create_note(doc_b, channels_b, "shared")
  sluice_js.settle(sluice)

  // One name, one register, on both clients.
  note_names(channels_a) |> should.equal(["shared"])
  note_names(channels_b) |> should.equal(["shared"])
  let assert Some(or_map_kernel.Register(register_a)) =
    watershed_js.or_map_value(channels_a.notes, "shared")
  let assert Some(or_map_kernel.Register(register_b)) =
    watershed_js.or_map_value(channels_b.notes, "shared")
  register_a |> should.equal(register_b)

  // Both resolve it, and the room agrees on the content.
  let text_a = open_note(doc_a, channels_a, "shared")
  let text_b = open_note(doc_b, channels_b, "shared")
  watershed_js.text_value(text_a)
  |> should.equal(watershed_js.text_value(text_b))
  watershed_js.text_value(text_a) |> should.equal("# shared\n")
}

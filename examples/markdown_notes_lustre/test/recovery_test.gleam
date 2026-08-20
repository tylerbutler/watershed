@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleeunit/should
@target(javascript)
import lustre/dev/query
@target(javascript)
import lustre/dev/simulate

@target(javascript)
import doc_schema
@target(javascript)
import markdown_notes_lustre
@target(javascript)
import markdown_notes_lustre/p2p_fake
@target(javascript)
import watershed/crdt_js.{type CrdtDocument, type Handle}
@target(javascript)
import watershed/persist_controller_js
@target(javascript)
import watershed/persist_js
@target(javascript)
import watershed/schema.{
  type OrMapChannel, type OrSetChannel, type SequenceChannel, type TextChannel,
}
@target(javascript)
import watershed_lustre/crdt

type Channels {
  Channels(
    root: Handle(OrMapChannel),
    tags: Handle(OrSetChannel),
    order: Handle(SequenceChannel),
  )
}

fn simulation_with_open_note() {
  let #(document, channels) = seeded_document()
  let simulation =
    simulate.application(
      init: markdown_notes_lustre.init,
      update: markdown_notes_lustre.update,
      view: markdown_notes_lustre.view,
    )
    |> simulate.start("recovery-test-room")
    |> simulate.message(markdown_notes_lustre.Connected(Ok(document)))
    |> simulate.message(markdown_notes_lustre.OpenClicked("field notes"))
  #(simulation, document, channels)
}

fn seeded_document() -> #(CrdtDocument(OrMapChannel), Channels) {
  let config =
    crdt_js.config(
      room_id: "recovery-test-room",
      replica_label: "recovery-test",
      compatibility_tag: "markdown-notes/v2",
      root: doc_schema.root(),
      signaling: p2p_fake.signaling(p2p_fake.new_world()),
    )
  let assert Ok(document) = crdt_js.new_document(config)
  let channels = bootstrap(document)
  let _ = create_note(document, channels, "field notes", "# field notes\nhello\n")
  #(document, channels)
}

fn bootstrap(document: CrdtDocument(OrMapChannel)) -> Channels {
  let root = crdt_js.root(document)
  let assert Ok(tags) = crdt_js.create_channel(document, doc_schema.tags_kind())
  let assert Ok(Nil) =
    crdt_js.or_map_set(
      root,
      key: doc_schema.tags_key(),
      value: crdt_js.address(tags),
    )
  let assert Ok(order) =
    crdt_js.create_channel(document, doc_schema.order_kind())
  let assert Ok(Nil) =
    crdt_js.or_map_set(
      root,
      key: doc_schema.order_key(),
      value: crdt_js.address(order),
    )
  Channels(root:, tags:, order:)
}

fn create_note(
  document: CrdtDocument(OrMapChannel),
  channels: Channels,
  name: String,
  body: String,
) -> Handle(TextChannel) {
  let assert Ok(text) = crdt_js.create_channel(document, doc_schema.text_kind())
  let assert Ok(Nil) = crdt_js.text_append(text, body)
  let assert Ok(Nil) =
    crdt_js.or_map_set(channels.root, key: name, value: crdt_js.address(text))
  let assert Ok(values) = crdt_js.sequence_values(channels.order)
  let assert Ok(Nil) =
    crdt_js.sequence_insert(
      channels.order,
      index: list.length(values),
      value: json.string(name),
    )
  text
}

fn smoke(name: String) {
  query.element(matching: query.data("smoke", name))
}

fn note_button(name: String) {
  query.element(
    matching:
      query.data("smoke", "note-open")
      |> query.and(query.data("note-name", name)),
  )
}

fn find(view, selector) {
  query.find(in: view, matching: selector) |> should.be_ok
}

fn should_be_disabled(element) {
  query.matches(target: element, selector: query.attribute("disabled", ""))
  |> should.be_true
}

fn should_be_enabled(element) {
  query.matches(target: element, selector: query.attribute("disabled", ""))
  |> should.be_false
}

pub fn save_failure_locks_mutations_but_keeps_remote_rendering_test() {
  let #(simulation, document, channels) = simulation_with_open_note()

  let gated =
    simulation
    |> simulate.message(markdown_notes_lustre.PersistenceStatusChanged(
      persist_controller_js.SaveFailed(
        persist_js.StorageFailure("IndexedDB write failed"),
      ),
    ))

  let view = simulate.view(gated)
  view |> find(smoke("create-note-input")) |> should_be_disabled
  view |> find(smoke("note-delete")) |> should_be_disabled
  view |> find(smoke("tag-input")) |> should_be_disabled
  view |> find(smoke("format-button")) |> should_be_disabled
  view
  |> find(smoke("editor"))
  |> query.matches(selector: query.attribute("readonly", ""))
  |> should.be_true
  view |> find(smoke("recovery-replace")) |> should_be_enabled

  let _ = create_note(document, channels, "remote", "# remote\n")
  let refreshed =
    gated |> simulate.message(markdown_notes_lustre.RootChanged)

  let _ = simulate.view(refreshed) |> find(note_button("remote"))
  Nil
}

pub fn recovery_success_clears_the_gate_and_marks_saved_test() {
  let #(simulation, _, _) = simulation_with_open_note()

  let recovered =
    simulation
    |> simulate.message(markdown_notes_lustre.LocalPersistence(
      crdt.PersistenceFailed(
        persist_js.SnapshotDecodeFailure("stored snapshot is not valid JSON"),
      ),
    ))
    |> simulate.message(markdown_notes_lustre.RecoveryReplaceFinished(
      Ok("digest-123"),
    ))

  let view = simulate.view(recovered)
  case query.find(in: view, matching: smoke("recovery-banner")) {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
  view |> find(smoke("create-note-input")) |> should_be_enabled
  view |> find(smoke("note-delete")) |> should_be_enabled
  view |> find(smoke("tag-input")) |> should_be_enabled
  view |> find(smoke("format-button")) |> should_be_enabled
  view
  |> find(smoke("editor"))
  |> query.matches(selector: query.attribute("readonly", ""))
  |> should.be_false
  view
  |> find(smoke("save-status"))
  |> query.has(matching: query.text("local save · saved"))
  |> should.be_true
}

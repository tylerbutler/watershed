//// The things the app tells a person about their own work: that a delete is
//// about to happen, that one dead service is one error rather than three, and
//// that a failure names the address it could not reach.

@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleeunit/should
@target(javascript)
import lustre/dev/query.{type Query}
@target(javascript)
import lustre/dev/simulate.{type Simulation}
@target(javascript)
import lustre/element.{type Element}

@target(javascript)
import markdown_notes_lustre
@target(javascript)
import markdown_notes_lustre/doc_schema
@target(javascript)
import markdown_notes_lustre/p2p_fake
@target(javascript)
import watershed/crdt_js.{type CrdtDocument, type Handle}
@target(javascript)
import watershed/schema.{
  type OrMapChannel, type OrSetChannel, type SequenceChannel, type TextChannel,
}

fn started() -> Simulation(
  markdown_notes_lustre.Model,
  markdown_notes_lustre.Msg,
) {
  simulate.application(
    init: markdown_notes_lustre.init,
    update: markdown_notes_lustre.update,
    view: markdown_notes_lustre.view,
  )
  |> simulate.start("safety-test-room")
}

fn smoke(name: String) -> Query {
  query.element(matching: query.data("smoke", name))
}

fn find(
  view: Element(markdown_notes_lustre.Msg),
  selector: Query,
) -> Element(markdown_notes_lustre.Msg) {
  query.find(in: view, matching: selector) |> should.be_ok
}

fn should_read(
  view: Element(markdown_notes_lustre.Msg),
  name: String,
  text: String,
) -> Nil {
  view
  |> find(smoke(name))
  |> query.has(matching: query.text(text))
  |> should.be_true
}

fn should_be_missing(
  view: Element(markdown_notes_lustre.Msg),
  name: String,
) -> Nil {
  query.find(in: view, matching: smoke(name)) |> should.be_error
}

/// One unreachable signaling service reports through several channels. Three
/// copies of one line used to crowd out the four other slots.
pub fn a_repeated_error_is_recorded_once_test() -> Nil {
  started()
  |> simulate.message(markdown_notes_lustre.SignalingFailed("did not answer"))
  |> simulate.message(markdown_notes_lustre.SignalingFailed("did not answer"))
  |> simulate.message(markdown_notes_lustre.SignalingFailed("did not answer"))
  |> simulate.view
  |> should_read("system-errors", "1 system error")
}

pub fn distinct_errors_are_all_kept_test() -> Nil {
  started()
  |> simulate.message(markdown_notes_lustre.SignalingFailed("did not answer"))
  |> simulate.message(markdown_notes_lustre.SignalingFailed("closed the socket"))
  |> simulate.view
  |> should_read("system-errors", "2 system errors")
}

/// `describe_error` prefixes some failures with the bare variant name. It is a
/// Gleam implementation detail and does not belong in the sidebar.
pub fn the_error_variant_name_is_not_shown_test() -> Nil {
  let view =
    started()
    |> simulate.message(markdown_notes_lustre.SignalingFailed(
      "signalingFailed · the service did not admit this peer",
    ))
    |> simulate.view

  view
  |> should_read(
    "system-errors",
    "signaling · the service did not admit this peer",
  )
}

/// The real double-report a live run produced: one dead signaling service
/// arrives from `apply_status` as a bare sentence and from the socket callback
/// under a `signaling · ` prefix. Same failure, two slots, until the compare
/// stopped being a plain string equality.
pub fn one_failure_reported_by_two_paths_is_recorded_once_test() -> Nil {
  started()
  |> simulate.message(
    markdown_notes_lustre.StatusChanged(crdt_js.SubscriberFailed(
      "root",
      "the signaling socket closed (1006)",
    )),
  )
  |> simulate.message(markdown_notes_lustre.SignalingFailed(
    "the signaling socket closed (1006)",
  ))
  |> simulate.view
  |> should_read("system-errors", "1 system error")
}

/// Deleting replicates to every peer and the OR-map has no undo operation, so
/// the ✕ arms the delete and a second, named button commits it. The note is
/// still listed while the confirmation is showing.
pub fn deleting_a_note_asks_before_it_happens_test() -> Nil {
  let view =
    with_notes()
    |> simulate.message(markdown_notes_lustre.RequestDeleteClicked(
      "field notes",
    ))
    |> simulate.view

  view |> should_read("note-delete-confirm", "Delete")
  // Only the armed row loses its ✕; the other note is untouched.
  query.find(in: view, matching: delete_button("field notes"))
  |> should.be_error
  query.find(in: view, matching: delete_button("second")) |> should.be_ok
  query.find(in: view, matching: note_button("field notes")) |> should.be_ok
  Nil
}

fn delete_button(name: String) -> Query {
  query.element(matching: query.attribute("aria-label", "delete " <> name))
}

pub fn an_armed_delete_can_be_called_off_test() -> Nil {
  let view =
    with_notes()
    |> simulate.message(markdown_notes_lustre.RequestDeleteClicked(
      "field notes",
    ))
    |> simulate.message(markdown_notes_lustre.CancelDeleteClicked)
    |> simulate.view

  view |> should_be_missing("note-delete-confirm")
  query.find(in: view, matching: smoke("note-delete")) |> should.be_ok
  Nil
}

/// Alt+Arrow reorders through the same operation a drag produces, so a keyboard
/// user is not locked out of a feature the mouse has.
pub fn a_note_can_be_moved_by_keyboard_test() -> Nil {
  let view =
    with_notes()
    |> simulate.message(markdown_notes_lustre.MoveNote("second", -1))
    |> simulate.view

  view |> first_note_should_be("second")
}

pub fn moving_past_the_end_does_nothing_test() -> Nil {
  let view =
    with_notes()
    |> simulate.message(markdown_notes_lustre.MoveNote("field notes", -1))
    |> simulate.view

  view |> first_note_should_be("field notes")
}

fn first_note_should_be(
  view: Element(markdown_notes_lustre.Msg),
  name: String,
) -> Nil {
  let assert Ok(first) =
    query.find_all(
      in: view,
      matching: query.element(matching: query.data("smoke", "note-open")),
    )
    |> list.first
  first
  |> query.has(matching: query.text(name))
  |> should.be_true
}

fn note_button(name: String) -> Query {
  query.element(
    matching: query.data("smoke", "note-open")
    |> query.and(query.data("note-name", name)),
  )
}

type Channels {
  Channels(
    root: Handle(OrMapChannel),
    tags: Handle(OrSetChannel),
    order: Handle(SequenceChannel),
  )
}

fn with_notes() -> Simulation(
  markdown_notes_lustre.Model,
  markdown_notes_lustre.Msg,
) {
  let #(document, _channels) = seeded_document()
  simulate.application(
    init: markdown_notes_lustre.init,
    update: markdown_notes_lustre.update,
    view: markdown_notes_lustre.view,
  )
  |> simulate.start("safety-test-room")
  |> simulate.message(markdown_notes_lustre.Connected(Ok(document)))
}

fn seeded_document() -> #(CrdtDocument(OrMapChannel), Channels) {
  let config =
    crdt_js.config(
      room_id: "safety-test-room",
      replica_label: "safety-test",
      compatibility_tag: "markdown-notes/v2",
      root: doc_schema.root(),
      signaling: p2p_fake.signaling(p2p_fake.new_world()),
    )
  let assert Ok(document) = crdt_js.new_document(config)
  let channels = bootstrap(document)
  let _ = create_note(document, channels, "field notes", "# field notes\n")
  let _ = create_note(document, channels, "second", "# second\n")
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

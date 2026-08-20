//// Offline-first markdown notes — a minimal Obsidian on CRDT-only kinds.
////
//// A note list beside a plain-markdown editor, where several people type in
//// the same note at once. Four kinds, each present because its merge rule is
//// the honest model for the feature:
////
//// - `notes` — an OR-map of note name → serialized `SharedText` handle.
////   Concurrent set beats concurrent remove, so a note someone is
////   re-registering survives a delete, and a deleted name can be cleanly
////   re-created.
//// - one `SharedText` per note body — markdown formatting is characters in
////   the document, so the file round-trips as a plain `.md` string.
//// - `tags` — one document-wide OR-set of `"<note>\t<tag>"` pairs.
//// - `order` — a SharedSequence of note names, the sidebar order.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import doc_schema
import markdown_notes_lustre/note_handle
import watershed/browser
import watershed/or_map_kernel
import watershed_js.{
  type Document, type OrMap, type OrSet, type SharedSequence, type SharedText,
}
import watershed_lustre

// ── Dev config for the floodgate dev server (`just integration-up`) ──────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

pub fn main() {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("markdown-notes")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

/// The seed line a fresh note starts with, matching its name.
pub fn seed_body(name: String) -> String {
  "# " <> name <> "\n"
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type SharedState {
  SharedState(notes: OrMap, tags: OrSet, order: SharedSequence)
}

/// The nested channels as they resolve during bootstrap. Each `ensure_*`
/// effect fills one slot; when all three are present they assemble into
/// `SharedState`.
type PendingShared {
  PendingShared(
    notes: Option(OrMap),
    tags: Option(OrSet),
    order: Option(SharedSequence),
  )
}

/// The note currently open in the editor. `deleted` mirrors whether its name
/// is still a key in the notes map — the channel keeps working either way, so
/// a peer's delete puts a banner over the editor instead of losing work
/// mid-keystroke.
type OpenNote {
  OpenNote(name: String, text: SharedText, body: String, deleted: Bool)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(doc_schema.Notebook)),
    shared: Option(SharedState),
    pending: PendingShared,
    user_id: String,
    /// Note names, read from the OR-map. Only registers count; a `Tally`
    /// value in the notes map is corrupt and is dropped rather than guessed
    /// at.
    note_names: List(String),
    open: Option(OpenNote),
    /// A note we tried to open whose handle did not resolve yet — a remote
    /// create's attach op can still be in flight, so resolution retries on
    /// the next notes event instead of failing hard.
    pending_open: Option(String),
    draft_name: String,
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.Notebook))
  Connected(Result(Nil, String))
  EnsuredNotes(Result(OrMap, String))
  EnsuredTags(Result(OrSet, String))
  EnsuredOrder(Result(SharedSequence, String))
  NotesChanged
  BodyChanged
  DraftNameChanged(String)
  CreateClicked
  OpenClicked(String)
  DeleteClicked(String)
  ReconnectClicked
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so two tabs are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      shared: None,
      pending: PendingShared(None, None, None),
      user_id: user_id,
      note_names: [],
      open: None,
      pending_open: None,
      draft_name: "",
      error: None,
    )
  #(
    model,
    watershed_lustre.connect_dev(
      url: socket_url,
      tenant: tenant,
      secret: tenant_secret,
      document: document,
      user_id: user_id,
      got_document: GotHandle,
      connected: Connected,
    ),
  )
}

/// Adopt-or-seed each nested channel as one batch of effects. `ensure_*`
/// seeds a channel only into an empty slot, so every client runs this
/// unconditionally without racing to a duplicate — but seeding needs a ready
/// connection, so this must not run before the handshake completes (the
/// seed-before-handshake defect bites brand-new documents exactly like this
/// one). Both the `GotHandle` and `Connected(Ok)` arms call this; whichever
/// lands second fires it, and the `shared: None` guard keeps a reconnect from
/// double-bootstrapping.
fn bootstrap_effect(doc: Document(doc_schema.Notebook)) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
  effect.batch([
    watershed_lustre.ensure_or_map(
      doc,
      root,
      doc_schema.notes(),
      or_map_kernel.RegisterMode,
      EnsuredNotes,
    ),
    watershed_lustre.ensure_or_set(doc, root, doc_schema.tags(), EnsuredTags),
    watershed_lustre.ensure_sequence(
      doc,
      root,
      doc_schema.order(),
      EnsuredOrder,
    ),
  ])
}

/// Assemble `SharedState` once all three nested channels have resolved, do
/// the initial reads, and start the per-channel subscriptions. A no-op until
/// the last channel arrives or once already assembled.
fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, model.pending {
    None, PendingShared(Some(notes), Some(tags), Some(order)) -> {
      let shared = SharedState(notes:, tags:, order:)
      let model =
        Model(..model, shared: Some(shared), error: None)
        |> read_notes(shared)
      #(
        model,
        watershed_lustre.subscribe_or_map(shared.notes, fn(_event) {
          NotesChanged
        }),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotHandle(doc) -> {
      let model = Model(..model, doc: Some(doc))
      case model.status, model.shared {
        Ready, None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.doc, model.shared {
        Some(doc), None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    EnsuredNotes(Ok(notes)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, notes: Some(notes)),
        ),
      )
    EnsuredNotes(Error(reason)) -> #(ensure_failed(model, reason), effect.none())

    EnsuredTags(Ok(tags)) ->
      assemble(
        Model(..model, pending: PendingShared(..model.pending, tags: Some(tags))),
      )
    EnsuredTags(Error(reason)) -> #(ensure_failed(model, reason), effect.none())

    EnsuredOrder(Ok(order)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, order: Some(order)),
        ),
      )
    EnsuredOrder(Error(reason)) -> #(ensure_failed(model, reason), effect.none())

    // The notes map changed (any client). Re-read the list, retry a pending
    // open — the attach op we were waiting on may have landed — and keep the
    // open note's deleted flag honest.
    NotesChanged ->
      case model.shared {
        Some(shared) -> {
          let model = read_notes(model, shared) |> mark_open_deleted
          case model.pending_open, model.doc {
            Some(name), Some(doc) -> try_open(model, shared, doc, name)
            _, _ -> #(model, effect.none())
          }
        }
        None -> #(model, effect.none())
      }

    BodyChanged -> #(refresh_body(model), effect.none())

    DraftNameChanged(raw) -> #(Model(..model, draft_name: raw), effect.none())

    CreateClicked ->
      case model.status, model.shared, model.doc {
        Ready, Some(shared), Some(doc) ->
          create_note(model, shared, doc, string.trim(model.draft_name))
        _, _, _ -> #(model, effect.none())
      }

    OpenClicked(name) ->
      case model.shared, model.doc {
        Some(shared), Some(doc) -> try_open(model, shared, doc, name)
        _, _ -> #(model, effect.none())
      }

    DeleteClicked(name) -> {
      case model.shared {
        Some(shared) -> watershed_js.or_map_remove(shared.notes, name)
        None -> Nil
      }
      // The subscription's NotesChanged re-reads the list and flips the open
      // note's banner; nothing else to do here.
      #(model, effect.none())
    }

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(model, watershed_lustre.force_reconnect(doc))
        None -> #(model, effect.none())
      }
  }
}

// ── Note lifecycle ───────────────────────────────────────────────────────────

/// Create a note: a fresh detached text channel, the seed line, then the
/// handle into the notes map — storing the handle is what attaches the
/// channel, seed line and all. The creator opens it directly; everyone else
/// resolves it out of the register.
fn create_note(
  model: Model,
  shared: SharedState,
  doc: Document(doc_schema.Notebook),
  name: String,
) -> #(Model, Effect(Msg)) {
  case validate_name(model, name) {
    Error(reason) -> #(Model(..model, error: Some(reason)), effect.none())
    Ok(Nil) ->
      case watershed_js.create_text(doc) {
        Error(reason) -> #(
          Model(..model, error: Some("create failed: " <> reason)),
          effect.none(),
        )
        Ok(text) -> {
          let assert Ok(Nil) = watershed_js.text_append(text, seed_body(name))
          watershed_js.or_map_set_json(
            shared.notes,
            name,
            watershed_js.text_handle_of(text),
          )
          let model = Model(..model, draft_name: "", error: None)
          open_resolved(model, name, text)
        }
      }
  }
}

fn validate_name(model: Model, name: String) -> Result(Nil, String) {
  case name, string.contains(name, "\t") {
    "", _ -> Error("A note needs a name.")
    _, True -> Error("Note names cannot contain a tab.")
    _, False ->
      case list.contains(model.note_names, name) {
        True -> Error("A note with that name already exists.")
        False -> Ok(Nil)
      }
  }
}

/// Open a note out of the notes map. A register that is not a handle marker
/// (or a `Tally` value) is corrupt and reported as such; a handle that does
/// not resolve is *retryable* — the creator's attach op can still be in
/// flight — so it parks in `pending_open` and retries on the next notes
/// event.
fn try_open(
  model: Model,
  shared: SharedState,
  doc: Document(doc_schema.Notebook),
  name: String,
) -> #(Model, Effect(Msg)) {
  case watershed_js.or_map_value(shared.notes, name) {
    None -> #(
      Model(..model, pending_open: None, error: Some("No note named " <> name)),
      effect.none(),
    )
    Some(or_map_kernel.Tally(_)) -> #(corrupt(model, name), effect.none())
    Some(or_map_kernel.Register(register)) ->
      case note_handle.parse(register) {
        Error(Nil) -> #(corrupt(model, name), effect.none())
        Ok(handle) ->
          case watershed_js.resolve_text(doc, handle) {
            Ok(text) ->
              open_resolved(Model(..model, error: None), name, text)
            Error(_) -> #(
              Model(..model, pending_open: Some(name)),
              effect.none(),
            )
          }
      }
  }
}

fn open_resolved(
  model: Model,
  name: String,
  text: SharedText,
) -> #(Model, Effect(Msg)) {
  let open =
    OpenNote(name:, text:, body: watershed_js.text_value(text), deleted: False)
  #(
    Model(..model, open: Some(open), pending_open: None),
    watershed_lustre.subscribe_text(text, fn(_event) { BodyChanged }),
  )
}

fn corrupt(model: Model, name: String) -> Model {
  Model(
    ..model,
    pending_open: None,
    error: Some("The entry for " <> name <> " is not a note handle."),
  )
}

/// Re-read the open note's body from its channel. Old channels' subscriptions
/// keep firing after a switch; re-reading the *current* channel makes those
/// stale events harmless.
fn refresh_body(model: Model) -> Model {
  case model.open {
    Some(open) ->
      Model(
        ..model,
        open: Some(
          OpenNote(..open, body: watershed_js.text_value(open.text)),
        ),
      )
    None -> model
  }
}

/// Keep the open note's banner honest against the note list: gone from the
/// map means deleted, back in the map (a concurrent re-set beat the remove)
/// means not.
fn mark_open_deleted(model: Model) -> Model {
  case model.open {
    Some(open) ->
      Model(
        ..model,
        open: Some(
          OpenNote(..open, deleted: !list.contains(model.note_names, open.name)),
        ),
      )
    None -> model
  }
}

/// Re-read the note names from the OR-map. A `Tally` value is corrupt in a
/// register-mode notes map and is dropped rather than guessed at.
fn read_notes(model: Model, shared: SharedState) -> Model {
  let names =
    watershed_js.or_map_entries(shared.notes)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        or_map_kernel.Register(_) -> Ok(entry.0)
        or_map_kernel.Tally(_) -> Error(Nil)
      }
    })
  Model(..model, note_names: names)
}

fn ensure_failed(model: Model, reason: String) -> Model {
  Model(..model, error: Some(reason))
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.div([class("app")], [sidebar_view(model), main_view(model)])
}

fn sidebar_view(model: Model) -> Element(Msg) {
  html.nav([class("sidebar")], [
    html.h1([], [html.text("Markdown notes")]),
    status_view(model),
    compose_view(model),
    note_list_view(model),
    error_view(model.error),
  ])
}

fn status_view(model: Model) -> Element(Msg) {
  html.p([class("status")], [
    html.text(case model.status {
      Connecting -> "Connecting…"
      Ready -> "Connected as " <> model.user_id
      Failed(reason) -> "Disconnected: " <> reason
    }),
  ])
}

fn compose_view(model: Model) -> Element(Msg) {
  html.div([class("compose")], [
    html.input([
      attribute.placeholder("New note name"),
      attribute.value(model.draft_name),
      attribute.attribute("aria-label", "new note name"),
      event.on_input(DraftNameChanged),
    ]),
    html.button(
      [
        event.on_click(CreateClicked),
        attribute.disabled(
          model.shared == None || string.trim(model.draft_name) == "",
        ),
      ],
      [html.text("Create")],
    ),
  ])
}

fn note_list_view(model: Model) -> Element(Msg) {
  case model.shared, model.note_names {
    None, _ -> html.p([class("hint")], [html.text("Loading notes…")])
    Some(_), [] -> html.p([class("hint")], [html.text("No notes yet.")])
    Some(_), names ->
      html.ul(
        [class("note-list")],
        list.map(names, fn(name) { note_item_view(model, name) }),
      )
  }
}

fn note_item_view(model: Model, name: String) -> Element(Msg) {
  let is_open = case model.open {
    Some(open) -> open.name == name && !open.deleted
    None -> False
  }
  html.li([class("note-item")], [
    html.button(
      [
        attribute.classes([#("note-open", True), #("open", is_open)]),
        event.on_click(OpenClicked(name)),
      ],
      [html.text(name)],
    ),
    html.button(
      [
        class("note-delete"),
        attribute.attribute("aria-label", "delete " <> name),
        event.on_click(DeleteClicked(name)),
      ],
      [html.text("✕")],
    ),
  ])
}

fn main_view(model: Model) -> Element(Msg) {
  html.main([class("main")], [
    case model.open, model.pending_open {
      _, Some(name) ->
        html.p([class("hint")], [html.text("Opening " <> name <> "…")])
      Some(open), None -> open_note_view(open)
      None, None ->
        html.p([class("hint")], [
          html.text("Select or create a note to start editing."),
        ])
    },
    html.div([class("offline-bar")], [
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
  ])
}

fn open_note_view(open: OpenNote) -> Element(Msg) {
  html.div([class("editor-wrap")], [
    html.h2([], [html.text(open.name)]),
    case open.deleted {
      True ->
        html.p([class("banner"), attribute.attribute("role", "alert")], [
          html.text(
            "This note was deleted by another client. Your edits still apply "
            <> "to its text, but it is no longer in the note list.",
          ),
        ])
      False -> html.text("")
    },
    html.pre([class("editor")], [html.text(open.body)]),
  ])
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) -> html.p([class("error")], [html.text(reason)])
    None -> html.text("")
  }
}

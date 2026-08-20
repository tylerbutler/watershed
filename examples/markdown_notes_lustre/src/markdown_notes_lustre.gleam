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

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
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
import markdown_notes_lustre/toolbar
import watershed/browser
import watershed/or_map_kernel
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed_js.{
  type Document, type OrMap, type OrSet, type SharedSequence, type SharedText,
}
import watershed_lustre
import watershed_lustre/textarea

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

// ── Presence payload: which note everyone is in, and where their caret is ────
//
// The cursor is a pair of anchors, not indices — an index means nothing to a
// peer whose replica has moved on. The note name rides along so a peer's
// caret is only drawn in the editor it actually belongs to.

type Editing {
  Editing(note: Option(String), cursor: Option(textarea.Cursor))
}

fn encode_editing(editing: Editing) -> Json {
  json.object([
    #("note", case editing.note {
      Some(name) -> json.string(name)
      None -> json.null()
    }),
    #("cursor", case editing.cursor {
      Some(cursor) -> textarea.cursor_to_json(cursor)
      None -> json.null()
    }),
  ])
}

fn editing_decoder() -> Decoder(Editing) {
  use note <- decode.field("note", decode.optional(decode.string))
  use cursor <- decode.field(
    "cursor",
    decode.optional(textarea.cursor_decoder()),
  )
  decode.success(Editing(note:, cursor:))
}

/// A stable colour per user, so a peer keeps the same one across a session.
fn colour_for(user_id: String) -> String {
  let palette = [
    "#e5484d", "#0090ff", "#30a46c", "#f76b15", "#8e4ec6", "#e93d82",
  ]
  let index =
    user_id
    |> string.to_utf_codepoints
    |> list.fold(0, fn(total, point) {
      total + string.utf_codepoint_to_int(point)
    })
  let count = list.length(palette)
  case list.drop(palette, index % count) {
    [colour, ..] -> colour
    [] -> "#0090ff"
  }
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
  OpenNote(name: String, editor: textarea.Model, deleted: Bool)
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
    /// The presence driver, once started, and the last payload announced
    /// through it — kept so a re-announce only fires when something moved.
    presence: Option(Handle(Editing)),
    announced: Editing,
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
  Editor(textarea.Msg)
  FormatClicked(toolbar.Action)
  DraftNameChanged(String)
  CreateClicked
  OpenClicked(String)
  DeleteClicked(String)
  PresenceStarted(Handle(Editing))
  PresenceEvent(presence.Event(Editing))
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
      presence: None,
      announced: Editing(note: None, cursor: None),
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
      let presence_effect = case model.doc, model.presence {
        Some(doc), None ->
          watershed_lustre.presence(
            document: doc,
            config: presence.config(encode_editing, editing_decoder()),
            initial: Editing(note: None, cursor: None),
            started: PresenceStarted,
            on_event: PresenceEvent,
          )
        _, _ -> effect.none()
      }
      case model.doc, model.shared {
        Some(doc), None -> #(
          model,
          effect.batch([bootstrap_effect(doc), presence_effect]),
        )
        _, _ -> #(model, presence_effect)
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

    // Every editor message routes through here — the textarea owns the diff,
    // the minimal op, and the rejected-index banner — and this is also where
    // the app notices the caret may have moved.
    Editor(inner) ->
      case model.open {
        None -> #(model, effect.none())
        Some(open) -> {
          let #(editor, editor_effect) = textarea.update(open.editor, inner)
          let model = Model(..model, open: Some(OpenNote(..open, editor:)))
          let #(model, announce) = announce_presence(model)
          #(model, effect.batch([effect.map(editor_effect, Editor), announce]))
        }
      }

    // Selection surgery through the same facade as remote edits: pure
    // helpers compute the insert list against the textarea's grapheme
    // selection, and each insert goes down the channel. The component
    // re-reads on its own subscription, so toolbar edits render through the
    // same path as a peer's keystrokes with zero new plumbing.
    FormatClicked(action) ->
      case model.open {
        None -> #(model, effect.none())
        Some(open) -> {
          let text = textarea.channel(open.editor)
          let length = textarea.length(open.editor)
          let selection =
            option.unwrap(textarea.selection(open.editor), #(length, length))
          let result =
            toolbar.edits(action, textarea.value(open.editor), selection)
            |> list.try_each(fn(edit) {
              watershed_js.text_insert(text, edit.0, edit.1)
            })
          case result {
            Ok(Nil) -> #(model, effect.none())
            Error(reason) -> #(
              Model(
                ..model,
                error: Some(toolbar.describe(action) <> " failed: " <> reason),
              ),
              effect.none(),
            )
          }
        }
      }

    PresenceStarted(handle) ->
      announce_presence(Model(..model, presence: Some(handle)))

    // The roster changed. Rebuild the open editor's peer list from it — only
    // carets that are in *this* note, keyed by session id so two tabs from
    // one person are two carets.
    PresenceEvent(event) ->
      case event {
        presence.Failed(_) -> #(model, effect.none())
        presence.State(entries) | presence.Changed(_, entries) ->
          case model.open {
            None -> #(model, effect.none())
            Some(open) -> {
              let cursors =
                remote_entries(model, entries)
                |> list.filter_map(fn(peer) {
                  case peer.meta.note == Some(open.name), peer.meta.cursor {
                    True, Some(cursor) ->
                      Ok(textarea.peer(
                        id: peer.session_id,
                        label: peer.key,
                        colour: colour_for(peer.key),
                        cursor: cursor,
                      ))
                    _, _ -> Error(Nil)
                  }
                })
              let #(editor, editor_effect) =
                textarea.set_peers(open.editor, cursors)
              #(
                Model(..model, open: Some(OpenNote(..open, editor:))),
                effect.map(editor_effect, Editor),
              )
            }
          }
      }

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

/// Mount the editor on a live, resolved channel — never an `Option` one —
/// and tell the room which note this client is now in.
fn open_resolved(
  model: Model,
  name: String,
  text: SharedText,
) -> #(Model, Effect(Msg)) {
  let #(editor, editor_effect) = textarea.init(text)
  let open = OpenNote(name:, editor:, deleted: False)
  let #(model, announce) =
    announce_presence(Model(..model, open: Some(open), pending_open: None))
  #(model, effect.batch([effect.map(editor_effect, Editor), announce]))
}

/// Broadcast this client's note and caret, but only when they actually
/// changed. Anchors are value-comparable and re-anchoring after a remote edit
/// yields the same anchors whenever the caret tracked the same content, so
/// this stays quiet through a peer's typing.
fn announce_presence(model: Model) -> #(Model, Effect(Msg)) {
  let current = case model.open {
    Some(open) ->
      Editing(note: Some(open.name), cursor: textarea.cursor(open.editor))
    None -> Editing(note: None, cursor: None)
  }
  case model.presence, current == model.announced {
    _, True -> #(model, effect.none())
    None, _ -> #(Model(..model, announced: current), effect.none())
    Some(handle), False -> #(
      Model(..model, announced: current),
      watershed_lustre.update_presence(handle, current),
    )
  }
}

/// Everyone but this tab — a client must not draw a caret for itself.
fn remote_entries(
  model: Model,
  entries: List(presence.PresenceEntry(Editing)),
) -> List(presence.PresenceEntry(Editing)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

fn corrupt(model: Model, name: String) -> Model {
  Model(
    ..model,
    pending_open: None,
    error: Some("The entry for " <> name <> " is not a note handle."),
  )
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
    toolbar_view(),
    textarea.view(open.editor, [
      class("editor"),
      attribute.rows(20),
      attribute.placeholder("Write markdown…"),
      attribute.attribute("aria-label", "note body: " <> open.name),
    ])
      |> element.map(Editor),
    case textarea.error(open.editor) {
      Some(reason) -> html.p([class("error")], [html.text(reason)])
      None -> html.text("")
    },
  ])
}

fn toolbar_view() -> Element(Msg) {
  html.div(
    [class("toolbar"), attribute.role("toolbar")],
    list.map(toolbar.all(), fn(action) {
      html.button(
        [
          event.on_click(FormatClicked(action)),
          attribute.attribute("aria-label", toolbar.describe(action)),
          attribute.title(toolbar.describe(action)),
        ],
        [html.text(toolbar.label(action))],
      )
    }),
  )
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) -> html.p([class("error")], [html.text(reason)])
    None -> html.text("")
  }
}

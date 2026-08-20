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

import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import doc_schema
import watershed/browser
import watershed/or_map_kernel
import watershed_js.{type Document, type OrMap, type OrSet, type SharedSequence}
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

    NotesChanged ->
      case model.shared {
        Some(shared) -> #(read_notes(model, shared), effect.none())
        None -> #(model, effect.none())
      }

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(model, watershed_lustre.force_reconnect(doc))
        None -> #(model, effect.none())
      }
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

fn note_list_view(model: Model) -> Element(Msg) {
  case model.shared, model.note_names {
    None, _ -> html.p([class("hint")], [html.text("Loading notes…")])
    Some(_), [] -> html.p([class("hint")], [html.text("No notes yet.")])
    Some(_), names ->
      html.ul(
        [class("note-list")],
        list.map(names, fn(name) {
          html.li([class("note-item")], [
            html.span([class("note-open")], [html.text(name)]),
          ])
        }),
      )
  }
}

fn main_view(_model: Model) -> Element(Msg) {
  html.main([class("main")], [
    html.p([class("hint")], [
      html.text("Select or create a note to start editing."),
    ]),
    html.div([class("offline-bar")], [
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
  ])
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) -> html.p([class("error")], [html.text(reason)])
    None -> html.text("")
  }
}

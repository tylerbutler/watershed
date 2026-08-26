//// Peer-to-peer markdown notes with disk-first persistence.
////
//// The document root is a register-mode OR-map. Note names map directly to
//// text channel addresses; two tab-prefixed reserved keys store the shared tags
//// and sidebar-order channel addresses.

import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event

import doc_schema
import markdown_notes_lustre/sidebar
import markdown_notes_lustre/toolbar
import watershed/browser
import watershed/crdt_js.{type CrdtDocument, type Handle}
import watershed/crdt_signaling_js
import watershed/nostr_signaling_js
import watershed/or_map_kernel
import watershed/p2p.{type P2pError}
import watershed/p2p_transport_js
import watershed/persist_controller_js
import watershed/persist_js
import watershed/schema.{
  type OrMapChannel, type OrSetChannel, type SequenceChannel, type TextChannel,
}
import watershed_lustre
import watershed_lustre/crdt
import watershed_lustre/textarea

const compatibility = "markdown-notes/v2"

/// Signaling defaults to public Nostr relays — nothing to deploy, nothing
/// to start. `?signaling=ws://…` points at a `crdt_signaling` service
/// instead; this is the address the reference one runs at, and naming it
/// exactly is what earns the copy-paste command in the offline banner.
const reference_signaling = "ws://localhost:4400/"

/// The sentinel `?signaling=` value (and default) for the Nostr lane, and
/// the display name the banner uses for it.
const nostr_signaling = "nostr"

const nostr_display = "the public Nostr relays"

const relay_param = "relay"

const retry_ms = 50

pub fn main() {
  let app = lustre.application(init, update, view)
  let room = browser.document_on_navigate("markdown-notes")
  let assert Ok(_) = lustre.start(app, "#app", room)
  Nil
}

/// The seed line a fresh note starts with, matching its name.
pub fn seed_body(name: String) -> String {
  "# " <> name <> "\n"
}

// ── Model ────────────────────────────────────────────────────────────────────

type Phase {
  Opening
  Ready
  Failed(detail: String)
}

type LocalSnapshot {
  OpeningLocalSnapshot
  NoLocalSnapshot
  LoadedLocalSnapshot
  LocalSnapshotFailed(detail: String)
}

type SaveState {
  WaitingForDocument
  Watching
  Saving
  Saved
  SaveFailed(detail: String)
}

type RecoveryState {
  NoRecovery
  RecoveryRequired(detail: String)
  ReplacingLocalSnapshot
}

type SharedState {
  SharedState(
    root: Handle(OrMapChannel),
    tags: Handle(OrSetChannel),
    order: Handle(SequenceChannel),
  )
}

type PendingShared {
  PendingShared(
    tags: Option(Handle(OrSetChannel)),
    order: Option(Handle(SequenceChannel)),
  )
}

type OpenNote {
  OpenNote(
    name: String,
    text: Handle(TextChannel),
    editor: textarea.CrdtModel,
    deleted: Bool,
  )
}

pub opaque type Model {
  Model(
    room: String,
    phase: Phase,
    bootstrap: String,
    relay: String,
    document: Option(CrdtDocument(OrMapChannel)),
    shared: Option(SharedState),
    pending: PendingShared,
    controller: Option(persist_controller_js.Controller(OrMapChannel)),
    recovery: RecoveryState,
    local_snapshot: LocalSnapshot,
    save_state: SaveState,
    saved_digest: String,
    durable: Option(Bool),
    note_names: List(String),
    open: Option(OpenNote),
    pending_open: Option(String),
    draft_name: String,
    order_entries: List(String),
    drag: Option(String),
    tag_pairs: List(String),
    tag_filter: Option(String),
    draft_tag: String,
    errors: List(String),
    error: Option(String),
    /// The signaling service this tab was pointed at. Kept on the model so a
    /// connection failure can name the address that did not answer instead of
    /// blaming the peers.
    signaling: String,
    /// The note whose delete is armed and awaiting confirmation. Deleting is
    /// replicated and has no compensating op, so it takes two deliberate acts.
    pending_delete: Option(String),
    invite_copied: Bool,
  )
}

pub type Msg {
  Ignored
  Connected(Result(CrdtDocument(OrMapChannel), P2pError))
  StatusChanged(crdt_js.Status)
  SignalingFailed(String)
  StorageDurability(Bool)
  LocalPersistence(crdt.PersistenceStatus)
  PersistenceStarted(persist_controller_js.Controller(OrMapChannel))
  PersistenceStatusChanged(persist_controller_js.Status)
  RecoveryReplaceClicked
  RecoveryReplaceFinished(Result(String, persist_js.PersistenceError))
  RootChanged
  TagsChanged
  OrderChanged
  RetryShared
  RetryOpen
  DragStarted(String)
  DragEnded
  DroppedOn(Option(String))
  NoOp
  Editor(textarea.Msg)
  FormatClicked(toolbar.Action)
  DraftTagChanged(String)
  AddTagClicked
  RemoveTagClicked(String)
  FilterClicked(Option(String))
  DraftNameChanged(String)
  CreateClicked
  OpenClicked(String)
  RequestDeleteClicked(String)
  CancelDeleteClicked
  DeleteClicked(String)
  MoveNote(String, Int)
  Shortcut(String, String)
  DownloadCopyClicked
  SnapshotExported(Result(json.Json, P2pError))
  CopyInviteClicked
  InviteCopyReset
}

pub fn init(room: String) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      room: room,
      phase: Opening,
      bootstrap: "joining",
      relay: case query(relay_param, "") {
        "" -> ""
        _ -> "connecting"
      },
      document: None,
      shared: None,
      pending: PendingShared(None, None),
      controller: None,
      recovery: NoRecovery,
      local_snapshot: OpeningLocalSnapshot,
      save_state: WaitingForDocument,
      saved_digest: "",
      durable: None,
      note_names: [],
      open: None,
      pending_open: None,
      draft_name: "",
      order_entries: [],
      drag: None,
      tag_pairs: [],
      tag_filter: None,
      draft_tag: "",
      errors: [],
      error: None,
      signaling: signaling_display(),
      pending_delete: None,
      invite_copied: False,
    )
  #(
    model,
    effect.batch([
      watch_signaling(),
      watch_shortcuts(),
      request_durable_storage(),
      open_room(room),
    ]),
  )
}

/// One document-level key listener, rather than a handler per control: the
/// editor is a mapped child element, so it cannot dispatch this module's `Msg`
/// from its own attributes. The FFI decides what was pressed and over which
/// note, and calls preventDefault only when it recognised the chord.
fn watch_shortcuts() -> Effect(Msg) {
  use dispatch <- effect.from
  set_shortcut_sink(fn(action, argument) {
    dispatch(Shortcut(action, argument))
  })
}

/// The signaling socket fails on its own callback, outside the dispatch loop,
/// so the sink is installed on an effect that has `dispatch` and read back by
/// `open_room`'s `on_failure`. Batched before it, so it is in place first.
fn watch_signaling() -> Effect(Msg) {
  use dispatch <- effect.from
  set_signaling_sink(fn(detail) { dispatch(SignalingFailed(detail)) })
}

/// Ask the browser to exempt this origin's IndexedDB from eviction. A refusal
/// is not an error — the app still saves, it just says the snapshot is
/// evictable rather than claiming a durability it does not have.
fn request_durable_storage() -> Effect(Msg) {
  use dispatch <- effect.from
  request_persistent_storage()
  |> promise.map(fn(granted) { dispatch(StorageDurability(granted)) })
  Nil
}

fn open_room(room: String) -> Effect(Msg) {
  let signaling = case query("signaling", nostr_signaling) {
    "nostr" ->
      nostr_signaling_js.nostr_signaling(
        relays: relays(),
        on_failure: report_signaling_failure,
      )
    url ->
      crdt_signaling_js.websocket_signaling(
        url: url,
        on_failure: report_signaling_failure,
      )
  }
  let config =
    crdt_js.config(
      room_id: room,
      replica_label: "tab",
      compatibility_tag: compatibility,
      root: doc_schema.root(),
      signaling: signaling,
    )
    |> crdt_js.with_ice_servers(ice_servers())
    |> with_relay

  crdt.open(
    persist_js.indexed_db(),
    config,
    connection: fn(_connection) { Ignored },
    ready: Connected,
    status: StatusChanged,
    persistence: LocalPersistence,
  )
}

fn with_relay(config) {
  case query(relay_param, "") {
    "" -> config
    url -> crdt_js.with_sequencer(config, crdt_js.sequencer(url))
  }
}

/// What the banner and sidebar name when signaling fails: the service URL
/// this tab was pointed at, or the Nostr lane's display name.
fn signaling_display() -> String {
  case query("signaling", nostr_signaling) {
    "nostr" -> nostr_display
    url -> url
  }
}

/// The Nostr relays to meet on: `?relays=wss://a,wss://b`, or the
/// adapter's public defaults.
fn relays() -> List(String) {
  case split_list(query("relays", "")) {
    [] -> nostr_signaling_js.default_relays
    urls -> urls
  }
}

fn split_list(raw: String) -> List(String) {
  string.split(raw, ",")
  |> list.map(string.trim)
  |> list.filter(fn(entry) { entry != "" })
}

fn ice_servers() {
  case
    split_list(query("ice", "")),
    query("iceUser", ""),
    query("icePass", "")
  {
    // NAT traversal with nothing deployed, to match the signaling default.
    [], _, _ -> p2p_transport_js.public_stun_servers()
    urls, "", _ -> [p2p_transport_js.ice_server(urls: urls)]
    urls, user, password -> [
      p2p_transport_js.ice_server(urls: urls)
      |> p2p_transport_js.with_credentials(username: user, credential: password),
    ]
  }
}

@external(javascript, "./app_ffi.mjs", "queryParam")
fn query(name: String, fallback: String) -> String

@external(javascript, "./app_ffi.mjs", "setSignalingSink")
fn set_signaling_sink(sink: fn(String) -> Nil) -> Nil

@external(javascript, "./app_ffi.mjs", "reportSignalingFailure")
fn report_signaling_failure(detail: String) -> Nil

@external(javascript, "./app_ffi.mjs", "requestPersistentStorage")
fn request_persistent_storage() -> Promise(Bool)

@external(javascript, "./app_ffi.mjs", "setShortcutSink")
fn set_shortcut_sink(sink: fn(String, String) -> Nil) -> Nil

@external(javascript, "./app_ffi.mjs", "downloadJson")
fn download_json(filename: String, contents: String) -> Nil

@external(javascript, "./app_ffi.mjs", "focusNoteButton")
fn focus_note_button(name: String) -> Nil

@external(javascript, "./app_ffi.mjs", "copyCurrentUrl")
fn copy_current_url() -> Nil

@external(javascript, "./app_ffi.mjs", "afterMs")
fn after_ms(delay: Int, run: fn() -> Nil) -> Nil

// ── Update ───────────────────────────────────────────────────────────────────

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Ignored -> #(model, effect.none())

    Connected(Ok(document)) -> {
      let model =
        Model(..model, phase: Ready, document: Some(document), error: None)
      let #(model, refresh) = refresh_from_root(model)
      let root = crdt_js.root(document)
      let persist = start_persistence_if_allowed(model, document)
      #(
        model,
        effect.batch([
          crdt.subscribe_or_map(
            root,
            subscribed: fn(_subscription) { Ignored },
            event: fn(_event) { RootChanged },
          ),
          persist,
          refresh,
        ]),
      )
    }

    Connected(Error(error)) -> #(
      Model(..model, phase: Failed(crdt_js.describe_error(error))),
      effect.none(),
    )

    StatusChanged(status) -> #(apply_status(model, status), effect.none())

    SignalingFailed(detail) -> #(
      note_system(model, "signaling · " <> without_variant(detail)),
      effect.none(),
    )

    StorageDurability(granted) -> #(
      Model(..model, durable: Some(granted)),
      effect.none(),
    )

    LocalPersistence(status) ->
      case status {
        crdt.NoLocalSnapshot -> #(
          Model(..model, local_snapshot: NoLocalSnapshot),
          effect.none(),
        )

        crdt.LocalSnapshotReady -> #(
          Model(..model, local_snapshot: LoadedLocalSnapshot),
          effect.none(),
        )

        crdt.PersistenceFailed(error) -> {
          let detail = persist_js.describe_error(error)
          enter_recovery(
            Model(..model, local_snapshot: LocalSnapshotFailed(detail)),
            detail,
          )
        }
      }

    PersistenceStarted(controller) -> #(
      Model(
        ..model,
        controller: Some(controller),
        save_state: case model.save_state {
          Saved -> Saved
          _ -> Watching
        },
      ),
      effect.none(),
    )

    PersistenceStatusChanged(status) ->
      case status {
        persist_controller_js.Saving -> #(
          Model(..model, save_state: Saving),
          effect.none(),
        )

        persist_controller_js.Saved(digest) -> #(
          Model(..model, save_state: Saved, saved_digest: digest),
          effect.none(),
        )

        persist_controller_js.SaveFailed(error) -> {
          let detail = persist_js.describe_error(error)
          enter_recovery(Model(..model, save_state: SaveFailed(detail)), detail)
        }
      }

    RecoveryReplaceClicked ->
      case model.recovery, model.document {
        RecoveryRequired(_), Some(document) -> #(
          Model(..model, recovery: ReplacingLocalSnapshot, save_state: Saving),
          replace_local_snapshot(document),
        )
        _, _ -> #(model, effect.none())
      }

    RecoveryReplaceFinished(result) ->
      case result {
        Ok(saved_digest) -> {
          let model =
            Model(
              ..model,
              recovery: NoRecovery,
              local_snapshot: LoadedLocalSnapshot,
              save_state: Saved,
              saved_digest: saved_digest,
            )
          let restart = case model.document {
            Some(document) -> start_persistence_if_allowed(model, document)
            None -> effect.none()
          }
          #(model, restart)
        }

        Error(error) -> {
          let detail = persist_js.describe_error(error)
          enter_recovery(Model(..model, save_state: SaveFailed(detail)), detail)
        }
      }

    RootChanged -> refresh_from_root(model)

    RetryShared -> refresh_from_root(model)

    RetryOpen ->
      case model.pending_open, model.document {
        Some(name), Some(_document) -> try_open(model, name)
        _, _ -> #(model, effect.none())
      }

    TagsChanged ->
      case model.shared {
        Some(shared) -> #(read_tags(model, shared), effect.none())
        None -> #(model, effect.none())
      }

    OrderChanged ->
      case model.shared {
        Some(shared) -> #(read_order(model, shared), effect.none())
        None -> #(model, effect.none())
      }

    DragStarted(name) ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False -> #(Model(..model, drag: Some(name)), effect.none())
      }

    DragEnded -> #(Model(..model, drag: None), effect.none())

    DroppedOn(target) ->
      case mutations_locked(model) {
        True -> #(Model(..model, drag: None), effect.none())
        False ->
          case model.shared, model.drag {
            Some(shared), Some(dragged) -> {
              let result = apply_drop(shared, dragged, target)
              let model = case result {
                Ok(Nil) ->
                  read_order(Model(..model, drag: None, error: None), shared)
                Error(reason) -> Model(..model, drag: None, error: Some(reason))
              }
              #(model, mark_dirty(model))
            }
            _, _ -> #(Model(..model, drag: None), effect.none())
          }
      }

    NoOp -> #(model, effect.none())

    Editor(inner) ->
      case mutations_locked(model) && textarea.mutates_document(inner) {
        True -> #(model, effect.none())
        False ->
          case model.open {
            None -> #(model, effect.none())
            Some(open) -> {
              let #(editor, editor_effect) = textarea.update(open.editor, inner)
              let model = Model(..model, open: Some(OpenNote(..open, editor:)))
              #(
                model,
                effect.batch([
                  effect.map(editor_effect, Editor),
                  mark_dirty(model),
                ]),
              )
            }
          }
      }

    FormatClicked(action) ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False ->
          case model.open {
            None -> #(model, effect.none())
            Some(open) -> {
              let length = textarea.length(open.editor)
              let selection =
                option.unwrap(textarea.selection(open.editor), #(length, length))
              let result =
                toolbar.edits(action, textarea.value(open.editor), selection)
                |> list.try_each(fn(edit) {
                  crdt_js.text_insert(open.text, edit.0, edit.1)
                })
              case result {
                Ok(Nil) -> #(Model(..model, error: None), mark_dirty(model))
                Error(error) -> #(
                  Model(
                    ..model,
                    error: Some(
                      toolbar.describe(action)
                      <> " failed: "
                      <> crdt_js.describe_error(error),
                    ),
                  ),
                  mark_dirty(model),
                )
              }
            }
          }
      }

    DraftTagChanged(raw) ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False -> #(Model(..model, draft_tag: raw), effect.none())
      }

    AddTagClicked ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False ->
          case model.shared, model.open, string.trim(model.draft_tag) {
            _, _, "" -> #(model, effect.none())
            Some(shared), Some(open), tag ->
              case string.contains(tag, "\t") {
                True -> #(
                  Model(..model, error: Some("Tags cannot contain a tab.")),
                  effect.none(),
                )
                False ->
                  case
                    crdt_js.or_set_add(
                      shared.tags,
                      sidebar.pair(open.name, tag),
                    )
                  {
                    Ok(Nil) -> {
                      let model =
                        read_tags(
                          Model(..model, draft_tag: "", error: None),
                          shared,
                        )
                      #(model, mark_dirty(model))
                    }
                    Error(error) -> #(
                      Model(
                        ..model,
                        error: Some(
                          "tag failed: " <> crdt_js.describe_error(error),
                        ),
                      ),
                      mark_dirty(model),
                    )
                  }
              }
            _, _, _ -> #(model, effect.none())
          }
      }

    RemoveTagClicked(tag) ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False ->
          case model.shared, model.open {
            Some(shared), Some(open) ->
              case
                crdt_js.or_set_remove(shared.tags, sidebar.pair(open.name, tag))
              {
                Ok(Nil) -> {
                  let model = read_tags(Model(..model, error: None), shared)
                  #(model, mark_dirty(model))
                }
                Error(error) -> #(
                  Model(
                    ..model,
                    error: Some(
                      "untag failed: " <> crdt_js.describe_error(error),
                    ),
                  ),
                  mark_dirty(model),
                )
              }
            _, _ -> #(model, effect.none())
          }
      }

    FilterClicked(filter) -> #(
      Model(..model, tag_filter: filter),
      effect.none(),
    )

    DraftNameChanged(raw) ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False -> #(Model(..model, draft_name: raw), effect.none())
      }

    CreateClicked ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False ->
          case model.shared, model.document {
            Some(shared), Some(document) ->
              create_note(
                model,
                shared,
                document,
                string.trim(model.draft_name),
              )
            _, _ -> #(model, effect.none())
          }
      }

    OpenClicked(name) -> try_open(model, name)

    RequestDeleteClicked(name) ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False -> #(Model(..model, pending_delete: Some(name)), effect.none())
      }

    CancelDeleteClicked -> #(
      Model(..model, pending_delete: None),
      effect.none(),
    )

    DeleteClicked(name) ->
      case mutations_locked(model) {
        True -> #(model, effect.none())
        False ->
          case model.shared {
            Some(shared) -> {
              let model = Model(..model, pending_delete: None)
              let removed = crdt_js.or_map_remove(shared.root, key: name)
              let sequence = case sequence_index_of(shared, name) {
                Some(index) ->
                  crdt_js.sequence_delete(shared.order, index: index)
                None -> Ok(Nil)
              }
              let model = case removed {
                Ok(Nil) ->
                  read_order(
                    read_notes(Model(..model, error: None), shared.root)
                      |> mark_open_deleted,
                    shared,
                  )
                Error(error) ->
                  Model(
                    ..model,
                    error: Some(
                      "delete failed: " <> crdt_js.describe_error(error),
                    ),
                  )
              }
              let model = case sequence {
                Ok(Nil) -> model
                Error(error) ->
                  note_system(
                    model,
                    "order cleanup failed: " <> crdt_js.describe_error(error),
                  )
              }
              #(model, mark_dirty(model))
            }
            None -> #(model, effect.none())
          }
      }

    MoveNote(name, delta) ->
      case mutations_locked(model), model.shared {
        False, Some(shared) ->
          case move_target(visible_names(model), name, delta) {
            Error(Nil) -> #(model, effect.none())
            Ok(target) -> {
              let model = case apply_drop(shared, name, target) {
                Ok(Nil) -> read_order(Model(..model, error: None), shared)
                Error(reason) -> Model(..model, error: Some(reason))
              }
              #(model, effect.batch([mark_dirty(model), focus_note(name)]))
            }
          }
        _, _ -> #(model, effect.none())
      }

    Shortcut(action, argument) ->
      case action {
        "bold" -> update(model, FormatClicked(toolbar.Bold))
        "italic" -> update(model, FormatClicked(toolbar.Italic))
        "code" -> update(model, FormatClicked(toolbar.Code))
        "move-up" -> update(model, MoveNote(argument, -1))
        "move-down" -> update(model, MoveNote(argument, 1))
        _ -> #(model, effect.none())
      }

    DownloadCopyClicked ->
      case model.document {
        Some(document) -> #(
          model,
          crdt.export_snapshot(document, exported: SnapshotExported),
        )
        None -> #(model, effect.none())
      }

    SnapshotExported(Ok(snapshot)) -> #(
      model,
      download_snapshot(model.room, json.to_string(snapshot)),
    )

    CopyInviteClicked -> #(
      Model(..model, invite_copied: True),
      effect.batch([copy_invite(), reset_invite_label()]),
    )

    InviteCopyReset -> #(Model(..model, invite_copied: False), effect.none())

    SnapshotExported(Error(error)) -> #(
      note_system(
        model,
        "could not export a copy · " <> crdt_js.describe_error(error),
      ),
      effect.none(),
    )
  }
}

/// The note this move should land in front of, in the same vocabulary
/// `apply_drop` already speaks, so a keyboard move and a drag produce
/// identical ops. `Error(Nil)` means the note is already at that end.
fn move_target(
  names: List(String),
  name: String,
  delta: Int,
) -> Result(Option(String), Nil) {
  let count = list.length(names)
  use from <- result.try(option.to_result(index_of(names, name), Nil))
  let to = from + delta
  case to < 0 || to >= count {
    True -> Error(Nil)
    // Moving down means landing in front of whatever follows the neighbour;
    // past the end that is `None`, which `apply_drop` reads as "append".
    False ->
      Ok(case delta < 0 {
        True -> at(names, to)
        False -> at(names, to + 1)
      })
  }
}

fn index_of(names: List(String), name: String) -> Option(Int) {
  list.index_fold(names, None, fn(found, candidate, index) {
    case found, candidate == name {
      None, True -> Some(index)
      _, _ -> found
    }
  })
}

fn at(names: List(String), index: Int) -> Option(String) {
  case list.drop(names, index) {
    [name, ..] -> Some(name)
    [] -> None
  }
}

/// Keyboard reordering moves the button the user is standing on, so focus has
/// to be put back after the list re-renders.
fn focus_note(name: String) -> Effect(Msg) {
  use _dispatch <- effect.from
  focus_note_button(name)
}

fn copy_invite() -> Effect(Msg) {
  use _dispatch <- effect.from
  copy_current_url()
}

/// The confirmation is the only feedback the copy gives, so it has to expire
/// on its own or it reads as a permanent state.
fn reset_invite_label() -> Effect(Msg) {
  use dispatch <- effect.from
  after_ms(2000, fn() { dispatch(InviteCopyReset) })
}

fn download_snapshot(room: String, contents: String) -> Effect(Msg) {
  use _dispatch <- effect.from
  download_json("watershed-notes-" <> room <> ".json", contents)
}

// ── Bootstrap & persistence ──────────────────────────────────────────────────

fn refresh_from_root(model: Model) -> #(Model, Effect(Msg)) {
  case model.document {
    None -> #(model, effect.none())
    Some(document) -> {
      let root = crdt_js.root(document)
      let model = read_notes(model, root) |> mark_open_deleted
      let #(model, retry_shared) =
        ensure_shared(
          model,
          document,
          root,
          create_missing: !mutations_locked(model),
        )
      let #(model, shared_effect) = assemble(model, root)
      let #(model, open_effect) = retry_pending_open(model)
      let retry_effect = case retry_shared {
        True -> watershed_lustre.after(retry_ms, RetryShared)
        False -> effect.none()
      }
      #(model, effect.batch([shared_effect, open_effect, retry_effect]))
    }
  }
}

fn ensure_shared(
  model: Model,
  document: CrdtDocument(OrMapChannel),
  root: Handle(OrMapChannel),
  create_missing create_missing: Bool,
) -> #(Model, Bool) {
  let #(model, retry_tags) = ensure_tags(model, document, root, create_missing:)
  let #(model, retry_order) =
    ensure_order(model, document, root, create_missing:)
  #(model, retry_tags || retry_order)
}

fn ensure_tags(
  model: Model,
  document: CrdtDocument(OrMapChannel),
  root: Handle(OrMapChannel),
  create_missing create_missing: Bool,
) -> #(Model, Bool) {
  case crdt_js.or_map_value(root, key: doc_schema.tags_key()) {
    Error(error) -> #(
      note_system(
        model,
        "tags channel failed: " <> crdt_js.describe_error(error),
      ),
      False,
    )
    Ok(None) if !create_missing -> #(
      Model(..model, pending: PendingShared(None, model.pending.order)),
      False,
    )
    Ok(None) ->
      case crdt_js.create_channel(document, doc_schema.tags_kind()) {
        Error(error) -> #(
          note_system(
            model,
            "tags channel failed: " <> crdt_js.describe_error(error),
          ),
          False,
        )
        Ok(tags) ->
          case
            crdt_js.or_map_set(
              root,
              key: doc_schema.tags_key(),
              value: crdt_js.address(tags),
            )
          {
            Ok(Nil) -> #(
              Model(
                ..model,
                pending: PendingShared(Some(tags), model.pending.order),
              ),
              False,
            )
            Error(error) -> #(
              note_system(
                model,
                "tags address failed: " <> crdt_js.describe_error(error),
              ),
              False,
            )
          }
      }
    Ok(Some(or_map_kernel.Tally(_))) -> #(
      note_system(model, "The stored tags channel address is corrupt."),
      False,
    )
    Ok(Some(or_map_kernel.Register(address))) ->
      case
        crdt_js.resolve_channel(
          document,
          doc_schema.tags_kind(),
          address: address,
        )
      {
        Ok(tags) -> #(
          Model(
            ..model,
            pending: PendingShared(Some(tags), model.pending.order),
          ),
          False,
        )
        Error(error) ->
          case retryable_missing_channel(error) {
            True -> #(
              Model(..model, pending: PendingShared(None, model.pending.order)),
              True,
            )
            False -> #(
              note_system(
                model,
                "tags channel failed: " <> crdt_js.describe_error(error),
              ),
              False,
            )
          }
      }
  }
}

fn ensure_order(
  model: Model,
  document: CrdtDocument(OrMapChannel),
  root: Handle(OrMapChannel),
  create_missing create_missing: Bool,
) -> #(Model, Bool) {
  case crdt_js.or_map_value(root, key: doc_schema.order_key()) {
    Error(error) -> #(
      note_system(
        model,
        "order channel failed: " <> crdt_js.describe_error(error),
      ),
      False,
    )
    Ok(None) if !create_missing -> #(
      Model(..model, pending: PendingShared(model.pending.tags, None)),
      False,
    )
    Ok(None) ->
      case crdt_js.create_channel(document, doc_schema.order_kind()) {
        Error(error) -> #(
          note_system(
            model,
            "order channel failed: " <> crdt_js.describe_error(error),
          ),
          False,
        )
        Ok(order) ->
          case
            crdt_js.or_map_set(
              root,
              key: doc_schema.order_key(),
              value: crdt_js.address(order),
            )
          {
            Ok(Nil) -> #(
              Model(
                ..model,
                pending: PendingShared(model.pending.tags, Some(order)),
              ),
              False,
            )
            Error(error) -> #(
              note_system(
                model,
                "order address failed: " <> crdt_js.describe_error(error),
              ),
              False,
            )
          }
      }
    Ok(Some(or_map_kernel.Tally(_))) -> #(
      note_system(model, "The stored order channel address is corrupt."),
      False,
    )
    Ok(Some(or_map_kernel.Register(address))) ->
      case
        crdt_js.resolve_channel(
          document,
          doc_schema.order_kind(),
          address: address,
        )
      {
        Ok(order) -> #(
          Model(
            ..model,
            pending: PendingShared(model.pending.tags, Some(order)),
          ),
          False,
        )
        Error(error) ->
          case retryable_missing_channel(error) {
            True -> #(
              Model(..model, pending: PendingShared(model.pending.tags, None)),
              True,
            )
            False -> #(
              note_system(
                model,
                "order channel failed: " <> crdt_js.describe_error(error),
              ),
              False,
            )
          }
      }
  }
}

fn assemble(model: Model, root: Handle(OrMapChannel)) -> #(Model, Effect(Msg)) {
  case model.pending {
    PendingShared(Some(tags), Some(order)) -> {
      let shared = SharedState(root:, tags:, order:)
      let changed = shared_changed(model.shared, shared)
      let model =
        Model(..model, shared: Some(shared))
        |> read_tags(shared)
        |> read_order(shared)
      let subscriptions = case changed {
        True ->
          effect.batch([
            crdt.subscribe_or_set(
              shared.tags,
              subscribed: fn(_subscription) { Ignored },
              event: fn(_event) { TagsChanged },
            ),
            crdt.subscribe_sequence(
              shared.order,
              subscribed: fn(_subscription) { Ignored },
              event: fn(_event) { OrderChanged },
            ),
          ])
        False -> effect.none()
      }
      #(model, subscriptions)
    }
    _ -> #(model, effect.none())
  }
}

fn shared_changed(current: Option(SharedState), next: SharedState) -> Bool {
  case current {
    None -> True
    Some(shared) ->
      crdt_js.address(shared.tags) != crdt_js.address(next.tags)
      || crdt_js.address(shared.order) != crdt_js.address(next.order)
  }
}

fn retry_pending_open(model: Model) -> #(Model, Effect(Msg)) {
  case model.pending_open {
    Some(name) -> try_open(model, name)
    None -> #(model, effect.none())
  }
}

fn mutations_locked(model: Model) -> Bool {
  case model.recovery {
    NoRecovery -> False
    RecoveryRequired(_) | ReplacingLocalSnapshot -> True
  }
}

fn start_persistence_if_allowed(
  model: Model,
  document: CrdtDocument(OrMapChannel),
) -> Effect(Msg) {
  case model.controller, model.recovery {
    Some(_), _ -> effect.none()
    None, NoRecovery ->
      crdt.start_persistence(
        persist_js.indexed_db(),
        document,
        PersistenceStarted,
        PersistenceStatusChanged,
      )
    None, RecoveryRequired(_) -> effect.none()
    None, ReplacingLocalSnapshot -> effect.none()
  }
}

fn stop_persistence(model: Model) -> Effect(Msg) {
  case model.controller {
    Some(controller) -> crdt.stop_persistence(controller)
    None -> effect.none()
  }
}

fn enter_recovery(model: Model, detail: String) -> #(Model, Effect(Msg)) {
  #(
    Model(
      ..model,
      controller: None,
      recovery: RecoveryRequired(detail),
      drag: None,
    ),
    stop_persistence(model),
  )
}

fn replace_local_snapshot(document: CrdtDocument(OrMapChannel)) -> Effect(Msg) {
  use dispatch <- effect.from
  persist_js.replace(persist_js.indexed_db(), document, fn(outcome) {
    dispatch(RecoveryReplaceFinished(outcome))
  })
}

fn mark_dirty(model: Model) -> Effect(Msg) {
  case model.controller {
    Some(controller) -> crdt.persistence_changed(controller)
    None -> effect.none()
  }
}

fn retryable_missing_channel(error: P2pError) -> Bool {
  case error {
    p2p.InvalidEnvelope(_, detail) ->
      string.starts_with(detail, "no channel registered at ")
    _ -> False
  }
}

// ── Note lifecycle ───────────────────────────────────────────────────────────

fn create_note(
  model: Model,
  shared: SharedState,
  document: CrdtDocument(OrMapChannel),
  name: String,
) -> #(Model, Effect(Msg)) {
  case validate_name(model, name) {
    Error(reason) -> #(Model(..model, error: Some(reason)), effect.none())
    Ok(Nil) ->
      case crdt_js.create_channel(document, doc_schema.text_kind()) {
        Error(error) -> #(
          Model(
            ..model,
            error: Some("create failed: " <> crdt_js.describe_error(error)),
          ),
          effect.none(),
        )
        Ok(text) ->
          case crdt_js.text_append(text, seed_body(name)) {
            Error(error) -> #(
              Model(
                ..model,
                error: Some("create failed: " <> crdt_js.describe_error(error)),
              ),
              mark_dirty(model),
            )
            Ok(Nil) ->
              case
                crdt_js.or_map_set(
                  shared.root,
                  key: name,
                  value: crdt_js.address(text),
                )
              {
                Error(error) -> #(
                  Model(
                    ..model,
                    error: Some(
                      "create failed: " <> crdt_js.describe_error(error),
                    ),
                  ),
                  mark_dirty(model),
                )
                Ok(Nil) -> {
                  let order_result =
                    crdt_js.sequence_insert(
                      shared.order,
                      index: raw_sequence_length(
                        shared.order,
                        model.order_entries,
                      ),
                      value: json.string(name),
                    )
                  let model =
                    read_notes(
                      Model(..model, draft_name: "", error: None),
                      shared.root,
                    )
                  let model = case order_result {
                    Ok(Nil) -> read_order(model, shared)
                    Error(error) ->
                      note_system(
                        read_order(model, shared),
                        "order update failed: " <> crdt_js.describe_error(error),
                      )
                  }
                  let #(model, editor_effect) = open_resolved(model, name, text)
                  #(model, effect.batch([editor_effect, mark_dirty(model)]))
                }
              }
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

fn try_open(model: Model, name: String) -> #(Model, Effect(Msg)) {
  case model.document {
    None -> #(model, effect.none())
    Some(document) -> {
      let root = crdt_js.root(document)
      case crdt_js.or_map_value(root, key: name) {
        Error(error) -> #(
          Model(
            ..model,
            pending_open: None,
            error: Some("open failed: " <> crdt_js.describe_error(error)),
          ),
          effect.none(),
        )
        Ok(None) -> #(
          Model(
            ..model,
            pending_open: None,
            error: Some("No note named " <> name),
          ),
          effect.none(),
        )
        Ok(Some(or_map_kernel.Tally(_))) -> #(
          Model(
            ..model,
            pending_open: None,
            error: Some("The entry for " <> name <> " is not a note address."),
          ),
          effect.none(),
        )
        Ok(Some(or_map_kernel.Register(address))) ->
          case
            crdt_js.resolve_channel(
              document,
              doc_schema.text_kind(),
              address: address,
            )
          {
            Ok(text) -> open_resolved(Model(..model, error: None), name, text)
            Error(error) ->
              case retryable_missing_channel(error) {
                True -> #(
                  Model(..model, pending_open: Some(name)),
                  watershed_lustre.after(retry_ms, RetryOpen),
                )
                False -> #(
                  Model(
                    ..model,
                    pending_open: None,
                    error: Some(
                      "open failed: " <> crdt_js.describe_error(error),
                    ),
                  ),
                  effect.none(),
                )
              }
          }
      }
    }
  }
}

fn open_resolved(
  model: Model,
  name: String,
  text: Handle(TextChannel),
) -> #(Model, Effect(Msg)) {
  let #(editor, editor_effect) = textarea.init_crdt(text)
  let open =
    OpenNote(
      name: name,
      text: text,
      editor: editor,
      deleted: !list.contains(model.note_names, name),
    )
  #(
    Model(..model, open: Some(open), pending_open: None),
    effect.map(editor_effect, Editor),
  )
}

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

// ── Reads ────────────────────────────────────────────────────────────────────

fn read_notes(model: Model, root: Handle(OrMapChannel)) -> Model {
  case crdt_js.or_map_entries(root) {
    Error(error) -> note_system(model, crdt_js.describe_error(error))
    Ok(entries) ->
      Model(
        ..model,
        note_names: entries
          |> list.filter_map(fn(entry) {
            case doc_schema.is_reserved(entry.0), entry.1 {
              True, _ -> Error(Nil)
              False, or_map_kernel.Register(_) -> Ok(entry.0)
              False, or_map_kernel.Tally(_) -> Error(Nil)
            }
          }),
      )
  }
}

fn read_tags(model: Model, shared: SharedState) -> Model {
  case crdt_js.or_set_values(shared.tags) {
    Ok(values) -> Model(..model, tag_pairs: values)
    Error(error) -> note_system(model, crdt_js.describe_error(error))
  }
}

fn read_order(model: Model, shared: SharedState) -> Model {
  case crdt_js.sequence_values(shared.order) {
    Ok(values) ->
      Model(
        ..model,
        order_entries: values
          |> list.filter_map(fn(value) {
            json.parse(json.to_string(value), decode.string)
            |> result.replace_error(Nil)
          }),
      )
    Error(error) -> note_system(model, crdt_js.describe_error(error))
  }
}

fn raw_sequence_length(
  order: Handle(SequenceChannel),
  fallback: List(a),
) -> Int {
  case crdt_js.sequence_values(order) {
    Ok(values) -> list.length(values)
    Error(_) -> list.length(fallback)
  }
}

fn sequence_index_of(shared: SharedState, name: String) -> Option(Int) {
  let target = json.to_string(json.string(name))
  case crdt_js.sequence_values(shared.order) {
    Error(_) -> None
    Ok(values) ->
      values
      |> list.index_fold(None, fn(found, value, index) {
        case found, json.to_string(value) == target {
          None, True -> Some(index)
          _, _ -> found
        }
      })
  }
}

// ── Reordering ───────────────────────────────────────────────────────────────

fn apply_drop(
  shared: SharedState,
  dragged: String,
  target: Option(String),
) -> Result(Nil, String) {
  let length = raw_sequence_length(shared.order, [])
  let to = case target {
    Some(name) -> sequence_index_of(shared, name) |> option.unwrap(length)
    None -> length
  }

  let result = case sequence_index_of(shared, dragged) {
    None ->
      crdt_js.sequence_insert(
        shared.order,
        index: to,
        value: json.string(dragged),
      )
    Some(from) if from == to -> Ok(Nil)
    Some(from) -> {
      let destination = case from < to {
        True -> to - 1
        False -> to
      }
      crdt_js.sequence_move(shared.order, from: from, to: destination)
    }
  }

  result |> result.map_error(crdt_js.describe_error)
}

// ── Connection status ────────────────────────────────────────────────────────

fn apply_status(model: Model, status: crdt_js.Status) -> Model {
  case status {
    crdt_js.Joined(_, _) -> Model(..model, bootstrap: "joined")
    crdt_js.RosterKnown([]) -> Model(..model, bootstrap: "alone")
    crdt_js.RosterKnown(_) -> Model(..model, bootstrap: "syncing")
    crdt_js.AwaitingState(_) -> Model(..model, bootstrap: "syncing")
    crdt_js.Ready | crdt_js.StateMerged(_, _) ->
      Model(..model, bootstrap: "ready")
    crdt_js.PeerRejected(peer, error) ->
      note_system(
        model,
        "peer " <> short(peer) <> " · " <> crdt_js.describe_error(error),
      )
    crdt_js.Failed(error) -> note_system(model, crdt_js.describe_error(error))
    crdt_js.TransportError(error) ->
      note_system(model, crdt_js.describe_error(error))
    crdt_js.SubscriberFailed(_, detail) -> note_system(model, detail)
    crdt_js.RejectedByPeer(peer, reason, detail) ->
      note_system(
        model,
        "peer " <> short(peer) <> " refused us · " <> reason <> " " <> detail,
      )
    crdt_js.RelayConnecting(_)
    | crdt_js.RelaySyncingStatus
    | crdt_js.RelayRecovering
    | crdt_js.RelayRetry(_) -> Model(..model, relay: "syncing")
    crdt_js.RelayPrimary(_)
    | crdt_js.RelayCheckpointRequested
    | crdt_js.RelayCheckpointed(_) -> Model(..model, relay: "durable")
    crdt_js.RelayFallback(_) | crdt_js.RelayUnsupported(_) ->
      Model(..model, relay: "offline · peer-to-peer")
    crdt_js.RelayFailed(error) ->
      note_system(
        Model(..model, relay: "offline"),
        crdt_js.describe_error(error),
      )
    crdt_js.RelayRejected(who, error) ->
      note_system(
        model,
        "relay peer " <> short(who) <> " · " <> crdt_js.describe_error(error),
      )
    crdt_js.PeerReady(_) | crdt_js.PeerGone(_) | crdt_js.Transport(_) -> model
  }
}

/// Newest first, and never the same line twice in a row: one unreachable
/// signaling service reports through several channels, and three copies of one
/// failure crowd out the four other things that went wrong.
fn note_system(model: Model, error: String) -> Model {
  // Stripped here rather than at each call site: one dead signaling service
  // reports through both `apply_status` and the socket's own callback, and
  // those two paths used to differ only by the variant prefix — which is
  // exactly enough to defeat a string comparison and print it twice.
  let error = without_variant(error)
  case list.any(model.errors, same_failure(_, error)) {
    True -> model
    False -> Model(..model, errors: list.take([error, ..model.errors], 5))
  }
}

/// Two reports are the same failure when one ends with the other: a dead
/// signaling service arrives once from `apply_status` as a bare sentence and
/// once from the socket callback under a `signaling · ` prefix, and printing
/// both spends two of five slots saying one thing.
fn same_failure(seen: String, incoming: String) -> Bool {
  seen == incoming
  || string.ends_with(seen, incoming)
  || string.ends_with(incoming, seen)
}

/// `describe_error` prefixes some failures with the bare variant name
/// (`signalingFailed · the service did not answer`). That token is a Gleam
/// implementation detail; the sentence after it is the part a reader needs.
fn without_variant(detail: String) -> String {
  case string.split_once(detail, " · ") {
    // A variant name is one word carrying an uppercase letter (`signalingFailed`).
    // A plain lowercase word is one of this app's own labels — `signaling · …` —
    // and stripping that would be eating our own prefix.
    Ok(#(head, rest)) ->
      case
        head != "",
        !string.contains(head, " "),
        head != string.lowercase(head)
      {
        True, True, True -> rest
        _, _, _ -> detail
      }
    Error(Nil) -> detail
  }
}

fn short(replica: String) -> String {
  case string.split(replica, "-") {
    [_label, head, ..] -> head
    _ -> replica
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.classes([
        #("app", True),
        #("recovery-required", mutations_locked(model)),
      ]),
      attribute.data("safety", safety_token(model)),
      attribute.data("smoke-phase", phase_token(model)),
      attribute.data("smoke-shared", shared_token(model)),
      attribute.data("smoke-storage", storage_token(model)),
      attribute.data("smoke-save", save_token(model)),
      attribute.data("smoke-recovery", recovery_token(model)),
      attribute.data("smoke-saved-digest", model.saved_digest),
      attribute.data("smoke-peers", peer_count_token(model)),
      attribute.data(
        "smoke-note-count",
        int.to_string(list.length(model.note_names)),
      ),
      attribute.data("smoke-open-note", open_note_token(model)),
    ],
    [sidebar_view(model), main_view(model)],
  )
}

fn sidebar_view(model: Model) -> Element(Msg) {
  html.nav([attribute.class("sidebar")], [
    html.h1([], [html.text("Markdown notes")]),
    room_view(model),
    status_view(model),
    compose_view(model),
    tag_filter_view(model),
    note_list_view(model),
    system_errors_view(model.errors),
    error_view(model.error),
  ])
}

/// One authored cross at a single stroke weight, rather than a Unicode glyph
/// standing in for an icon system. Used for both "delete note" and
/// "remove tag", so the two crosses are the same drawing at two sizes.
fn cross_icon() -> Element(Msg) {
  svg.svg(
    [
      attribute.attribute("viewBox", "0 0 16 16"),
      attribute.attribute("width", "1em"),
      attribute.attribute("height", "1em"),
      attribute.attribute("fill", "none"),
      attribute.attribute("stroke", "currentColor"),
      attribute.attribute("stroke-width", "1.6"),
      attribute.attribute("stroke-linecap", "square"),
      attribute.attribute("aria-hidden", "true"),
      attribute.attribute("focusable", "false"),
    ],
    [
      svg.line([
        attribute.attribute("x1", "4"),
        attribute.attribute("y1", "4"),
        attribute.attribute("x2", "12"),
        attribute.attribute("y2", "12"),
      ]),
      svg.line([
        attribute.attribute("x1", "12"),
        attribute.attribute("y1", "4"),
        attribute.attribute("x2", "4"),
        attribute.attribute("y2", "12"),
      ]),
    ],
  )
}

/// The whole document is keyed on the room id, and collaborating means
/// somebody else opening this exact URL — which the app used to mention once,
/// in a hint that disappeared the moment the room opened.
fn room_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("room")], [
    html.span([attribute.class("room-id"), attribute.title(model.room)], [
      html.text(model.room),
    ]),
    html.button(
      [
        attribute.class("room-copy"),
        attribute.data("smoke", "copy-invite"),
        event.on_click(CopyInviteClicked),
      ],
      [
        html.text(case model.invite_copied {
          True -> "Link copied"
          False -> "Copy invite link"
        }),
      ],
    ),
  ])
}

/// Every line here changes without the user acting, so the stack is a live
/// region. The save line escalates to `alert` when it is reporting a failure —
/// that is the one status change nobody should have to notice on their own.
fn status_view(model: Model) -> Element(Msg) {
  let saving_failed = case model.recovery, model.save_state {
    NoRecovery, SaveFailed(_) -> True
    NoRecovery, _ -> False
    _, _ -> True
  }

  html.div(
    [
      attribute.class("status-stack"),
      attribute.role("status"),
      attribute.attribute("aria-live", "polite"),
    ],
    [
      html.p([attribute.class("status headline")], [
        html.text(safety_headline(model)),
      ]),
      html.p(
        [
          attribute.class("status " <> network_lamp(model)),
          attribute.data("smoke", "network-status"),
        ],
        [html.text(network_status(model))],
      ),
      html.p(
        [
          attribute.class("status " <> storage_lamp(model)),
          attribute.data("smoke", "storage-status"),
        ],
        [html.text(storage_status(model))],
      ),
      html.p(
        [
          attribute.class(
            "status "
            <> save_lamp(model)
            <> case saving_failed {
              True -> " status-failed"
              False -> ""
            },
          ),
          attribute.data("smoke", "save-status"),
          attribute.role(case saving_failed {
            True -> "alert"
            False -> "none"
          }),
        ],
        [html.text(save_status(model))],
      ),
    ],
  )
}

/// Lamp semantics are strict and shared across the panel: amber is local or
/// in flight, green is on disk or converged, red is at risk. Each lamp only
/// repeats what its own line already says in words.
fn network_lamp(model: Model) -> String {
  case model.phase {
    Failed(_) -> "lamp-armed"
    Opening -> "lamp-live"
    Ready -> "lamp-safe"
  }
}

fn storage_lamp(model: Model) -> String {
  case model.local_snapshot, model.durable {
    LocalSnapshotFailed(_), _ -> "lamp-armed"
    LoadedLocalSnapshot, Some(True) -> "lamp-safe"
    LoadedLocalSnapshot, _ -> "lamp-live"
    _, _ -> "lamp-live"
  }
}

fn save_lamp(model: Model) -> String {
  case model.recovery, model.save_state {
    NoRecovery, Saved -> "lamp-safe"
    NoRecovery, SaveFailed(_) -> "lamp-armed"
    NoRecovery, _ -> "lamp-live"
    _, _ -> "lamp-armed"
  }
}

/// The three lines below answer three different questions; this one answers
/// the only question a person writing a note actually has.
fn safety_headline(model: Model) -> String {
  let peers = case model.document {
    Some(document) -> crdt_js.peer_count(document)
    None -> 0
  }
  let elsewhere = case peers {
    0 -> ""
    1 -> " and on 1 peer"
    count -> " and on " <> int.to_string(count) <> " peers"
  }
  let notes = case list.length(model.note_names) {
    1 -> "1 note"
    count -> int.to_string(count) <> " notes"
  }

  case model.recovery, model.save_state {
    NoRecovery, Saved -> "Safe · " <> notes <> " on disk" <> elsewhere
    NoRecovery, Saving -> "Saving " <> notes <> "…"
    NoRecovery, SaveFailed(_) -> "At risk · this browser cannot save"
    NoRecovery, _ ->
      case peers {
        0 -> "Not saved yet · " <> notes <> " in this tab only"
        _ -> "Not saved yet · " <> notes <> elsewhere
      }
    _, _ -> "At risk · this browser cannot save"
  }
}

/// Drives the master lamp. The headline sentence beside it carries the same
/// fact in words, so the colour is never the only channel.
fn safety_token(model: Model) -> String {
  case model.recovery, model.save_state {
    NoRecovery, Saved -> "safe"
    NoRecovery, Saving -> "saving"
    NoRecovery, SaveFailed(_) -> "at-risk"
    NoRecovery, _ -> "pending"
    _, _ -> "at-risk"
  }
}

fn phase_token(model: Model) -> String {
  case model.phase {
    Opening -> "opening"
    Ready -> "ready"
    Failed(_) -> "failed"
  }
}

fn shared_token(model: Model) -> String {
  case model.shared {
    Some(_) -> "ready"
    None -> "pending"
  }
}

fn storage_token(model: Model) -> String {
  case model.local_snapshot {
    OpeningLocalSnapshot -> "opening"
    NoLocalSnapshot -> "none"
    LoadedLocalSnapshot -> "loaded"
    LocalSnapshotFailed(_) -> "failed"
  }
}

fn save_token(model: Model) -> String {
  case model.recovery {
    NoRecovery ->
      case model.save_state {
        WaitingForDocument -> "waiting"
        Watching -> "watching"
        Saving -> "saving"
        Saved -> "saved"
        SaveFailed(_) -> "failed"
      }
    RecoveryRequired(_) -> "recovery"
    ReplacingLocalSnapshot -> "replacing"
  }
}

fn recovery_token(model: Model) -> String {
  case model.recovery {
    NoRecovery -> "none"
    RecoveryRequired(_) -> "required"
    ReplacingLocalSnapshot -> "replacing"
  }
}

fn peer_count_token(model: Model) -> String {
  case model.document {
    Some(document) -> int.to_string(crdt_js.peer_count(document))
    None -> "0"
  }
}

fn open_note_token(model: Model) -> String {
  case model.open {
    Some(open) -> open.name
    None -> ""
  }
}

fn network_status(model: Model) -> String {
  let connection = case model.phase {
    Opening -> "opening…"
    Ready -> model.bootstrap
    Failed(detail) -> "offline · " <> without_variant(detail)
  }
  let relay = case model.relay {
    "" -> ""
    state -> " · relay " <> state
  }
  // "alone" already says nobody else is here; printing "0 peers" after it is
  // the same fact twice.
  case model.bootstrap == "alone" && model.phase == Ready {
    True -> connection <> relay
    False -> connection <> " · " <> peer_count(model) <> relay
  }
}

fn peer_count(model: Model) -> String {
  case model.document {
    Some(document) ->
      case crdt_js.peer_count(document) {
        1 -> "1 peer"
        count -> int.to_string(count) <> " peers"
      }
    None -> "0 peers"
  }
}

fn storage_status(model: Model) -> String {
  let snapshot = case model.local_snapshot {
    OpeningLocalSnapshot -> "storage · opening local snapshot…"
    NoLocalSnapshot -> "storage · no local snapshot yet"
    LoadedLocalSnapshot -> "storage · local snapshot loaded"
    LocalSnapshotFailed(detail) -> "storage · " <> detail
  }
  case model.durable {
    None -> snapshot
    Some(True) -> snapshot <> " · durable"
    Some(False) -> snapshot <> " · evictable"
  }
}

fn save_status(model: Model) -> String {
  case model.recovery {
    NoRecovery ->
      case model.save_state {
        WaitingForDocument -> "local save · waiting for document"
        Watching -> "local save · watching for edits"
        Saving -> "local save · saving…"
        Saved -> "local save · saved"
        SaveFailed(detail) -> "local save · " <> detail
      }
    RecoveryRequired(_) -> "local save · recovery required"
    ReplacingLocalSnapshot ->
      "local save · replacing the broken local snapshot…"
  }
}

fn compose_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("compose")], [
    html.input([
      attribute.data("smoke", "create-note-input"),
      attribute.placeholder("New note name"),
      attribute.value(model.draft_name),
      attribute.aria_label("new note name"),
      attribute.disabled(mutations_locked(model)),
      event.on_input(DraftNameChanged),
      event.on_keydown(fn(key) {
        case key {
          "Enter" -> CreateClicked
          _ -> NoOp
        }
      }),
    ]),
    html.button(
      [
        attribute.data("smoke", "create-note"),
        event.on_click(CreateClicked),
        attribute.disabled(
          mutations_locked(model)
          || model.shared == None
          || string.trim(model.draft_name) == "",
        ),
      ],
      [html.text("Create")],
    ),
  ])
}

fn tag_filter_view(model: Model) -> Element(Msg) {
  case sidebar.all_tags(model.tag_pairs, model.note_names) {
    [] -> html.text("")
    tags ->
      html.div([attribute.class("tag-filter"), attribute.role("group")], [
        html.button(
          [
            attribute.classes([#("active", model.tag_filter == None)]),
            event.on_click(FilterClicked(None)),
          ],
          [html.text("all")],
        ),
        ..list.map(tags, fn(tag) {
          html.button(
            [
              attribute.classes([#("active", model.tag_filter == Some(tag))]),
              event.on_click(FilterClicked(Some(tag))),
            ],
            [html.text(tag)],
          )
        })
      ])
  }
}

fn visible_names(model: Model) -> List(String) {
  let ordered = sidebar.display_order(model.note_names, model.order_entries)
  case model.tag_filter {
    None -> ordered
    Some(tag) -> {
      let tagged = sidebar.notes_with_tag(model.tag_pairs, tag)
      list.filter(ordered, list.contains(tagged, _))
    }
  }
}

fn note_list_view(model: Model) -> Element(Msg) {
  case model.shared, visible_names(model) {
    // Saying "Loading notes…" under a line that already says "offline" is two
    // claims about the same fact. When the room never opened, the main pane
    // carries the whole story and the list says nothing.
    None, _ ->
      case model.phase {
        Failed(_) -> html.text("")
        _ -> html.p([attribute.class("hint")], [html.text("Loading notes…")])
      }
    Some(_), [] ->
      html.p([attribute.class("hint")], [html.text("No notes here.")])
    Some(_), names ->
      html.ul(
        [attribute.class("note-list"), attribute.data("smoke", "note-list")],
        list.append(list.map(names, fn(name) { note_item_view(model, name) }), [
          html.li(
            [
              attribute.class("drop-end"),
              // A drop target with no content: keyboard reordering covers the
              // same move, so hiding it stops a one-note list announcing two.
              attribute.attribute("aria-hidden", "true"),
              event.on("dragover", decode.success(NoOp))
                |> event.prevent_default,
              event.on("drop", decode.success(DroppedOn(None)))
                |> event.prevent_default,
            ],
            [],
          ),
        ]),
      )
  }
}

fn note_item_view(model: Model, name: String) -> Element(Msg) {
  let is_open = case model.open {
    Some(open) -> open.name == name && !open.deleted
    None -> False
  }

  html.li(
    [
      attribute.classes([
        #("note-item", True),
        #("dragging", model.drag == Some(name)),
      ]),
      attribute.draggable(!mutations_locked(model)),
      event.on("dragstart", decode.success(DragStarted(name))),
      event.on("dragend", decode.success(DragEnded)),
      event.on("dragover", decode.success(NoOp)) |> event.prevent_default,
      event.on("drop", decode.success(DroppedOn(Some(name))))
        |> event.prevent_default,
    ],
    [
      html.button(
        [
          attribute.data("smoke", "note-open"),
          attribute.data("note-name", name),
          attribute.class(
            "note-open "
            <> save_lamp(model)
            <> case is_open {
              True -> " open"
              False -> ""
            },
          ),
          event.on_click(OpenClicked(name)),
        ],
        [html.span([attribute.class("note-name")], [html.text(name)])],
      ),
      ..case model.pending_delete == Some(name) {
        // Deleting replicates to every peer and the OR-map has no undo op, so
        // the ✕ arms the action and a second, named button commits it.
        True -> [
          html.button(
            [
              attribute.data("smoke", "note-delete-confirm"),
              attribute.class("note-confirm"),
              attribute.aria_label("confirm deleting " <> name),
              attribute.disabled(mutations_locked(model)),
              event.on_click(DeleteClicked(name)),
            ],
            [html.text("Delete")],
          ),
          html.button(
            [
              attribute.data("smoke", "note-delete-cancel"),
              attribute.class("note-cancel"),
              attribute.aria_label("keep " <> name),
              event.on_click(CancelDeleteClicked),
            ],
            [html.text("Keep")],
          ),
        ]
        False -> [
          html.button(
            [
              attribute.data("smoke", "note-delete"),
              attribute.class("note-delete"),
              attribute.aria_label("delete " <> name),
              attribute.disabled(mutations_locked(model)),
              event.on_click(RequestDeleteClicked(name)),
            ],
            [cross_icon()],
          ),
        ]
      }
    ],
  )
}

fn main_view(model: Model) -> Element(Msg) {
  let panel = case
    model.pending_open,
    model.open,
    model.document,
    model.shared
  {
    Some(name), _, _, _ ->
      html.p([attribute.class("hint")], [html.text("Opening " <> name <> "…")])
    _, Some(open), _, _ -> open_note_view(model, open)
    _, None, None, _ ->
      case model.phase {
        // The sidebar knows which address failed; the banner used to blame the
        // peers instead of naming it.
        Failed(detail) ->
          html.div(
            [
              attribute.class("banner"),
              attribute.role("status"),
              attribute.data("smoke", "offline-banner"),
            ],
            [
              html.p([], [
                html.text(
                  "Can't reach "
                  <> case model.signaling == nostr_display {
                    True -> model.signaling
                    False -> "the signaling service at " <> model.signaling
                  }
                  <> " — "
                  <> without_variant(detail)
                  <> ".",
                ),
              ]),
              html.p([attribute.class("hint")], [
                html.text(
                  "This browser has no saved copy of this room, so there is "
                  <> "nothing to open offline. "
                  <> case model.signaling == nostr_display {
                    // Public relays are not something the reader can start;
                    // the network between here and them is what failed.
                    True -> "Check the connection, then reload."
                    False -> "Start the service, then reload."
                  },
                ),
              ]),
              // Only offer the exact command when this tab named the
              // reference address; a custom `?signaling=` makes the port a
              // guess, and the Nostr default has no service to start.
              case model.signaling == reference_signaling {
                True ->
                  html.pre([attribute.class("banner-command")], [
                    html.text("node tools/signaling/server.mjs --port 4400"),
                  ])
                False -> html.text("")
              },
            ],
          )
        _ ->
          html.p([attribute.class("hint")], [
            html.text("Open this URL in another tab to join the same room."),
          ])
      }
    _, None, Some(_), None ->
      html.p([attribute.class("hint")], [html.text("Loading note channels…")])
    _, None, Some(_), Some(_) ->
      html.p([attribute.class("hint")], [
        html.text("Select or create a note to start editing."),
      ])
  }

  html.main(
    [attribute.class("main")],
    list.append(recovery_banner(model), [panel]),
  )
}

/// Where the user's work actually is right now, in one sentence, before the
/// banner asks them to press anything.
fn recovery_reassurance(model: Model) -> String {
  let notes = case list.length(model.note_names) {
    1 -> "Your 1 note is"
    count -> "Your " <> int.to_string(count) <> " notes are"
  }
  let peers = case model.document {
    Some(document) -> crdt_js.peer_count(document)
    None -> 0
  }
  case peers {
    0 -> notes <> " open in this tab. Nothing has been lost."
    1 -> notes <> " open here and shared with 1 peer."
    count ->
      notes
      <> " open here and shared with "
      <> int.to_string(count)
      <> " peers."
  }
}

fn recovery_banner(model: Model) -> List(Element(Msg)) {
  let button_disabled = model.document == None
  case model.recovery {
    NoRecovery -> []

    RecoveryRequired(detail) -> [
      html.section(
        [
          attribute.class("recovery"),
          attribute.role("alert"),
          attribute.data("smoke", "recovery-banner"),
        ],
        [
          html.h2([], [html.text("This browser can't save to disk")]),
          // Lead with what is still safe. The old copy opened on the mechanism
          // and never told the user where their work was.
          html.p([attribute.class("recovery-safe")], [
            html.text(recovery_reassurance(model)),
          ]),
          html.p([attribute.data("smoke", "recovery-status")], [
            html.text("What failed: " <> detail <> "."),
          ]),
          html.p([attribute.class("hint")], [
            html.text(
              "Editing is locked here so nothing new is written on top of a "
              <> "copy this browser can't read. Notes from other peers still "
              <> "arrive.",
            ),
          ]),
          html.p([attribute.class("hint")], [
            html.text(
              "Overwriting discards the unreadable saved copy — including "
              <> "anything written offline in an earlier session that never "
              <> "loaded. Download a copy first if this browser has been used "
              <> "offline.",
            ),
          ]),
          html.div([attribute.class("recovery-actions")], [
            html.button(
              [
                attribute.data("smoke", "recovery-download"),
                attribute.class("secondary"),
                attribute.disabled(button_disabled),
                event.on_click(DownloadCopyClicked),
              ],
              [html.text("Download a copy")],
            ),
            html.button(
              [
                attribute.data("smoke", "recovery-replace"),
                attribute.class("destructive"),
                attribute.disabled(button_disabled),
                event.on_click(RecoveryReplaceClicked),
              ],
              [
                html.text(case button_disabled {
                  True -> "Waiting for the current document…"
                  False -> "Overwrite the local snapshot"
                }),
              ],
            ),
          ]),
        ],
      ),
    ]

    ReplacingLocalSnapshot -> [
      html.section(
        [
          attribute.class("recovery"),
          attribute.role("status"),
          attribute.data("smoke", "recovery-banner"),
        ],
        [
          html.h2([], [html.text("This browser can't save to disk")]),
          html.p([attribute.data("smoke", "recovery-status")], [
            html.text(
              "Replacing the broken local snapshot with the current document…",
            ),
          ]),
          html.button(
            [
              attribute.data("smoke", "recovery-replace"),
              attribute.disabled(True),
            ],
            [html.text("Replacing local snapshot…")],
          ),
        ],
      ),
    ]
  }
}

fn open_note_view(model: Model, open: OpenNote) -> Element(Msg) {
  html.div([attribute.class("editor-wrap")], [
    html.h2([attribute.data("smoke", "open-note-title")], [html.text(open.name)]),
    case open.deleted {
      True ->
        html.p([attribute.class("banner"), attribute.role("alert")], [
          html.text(
            "This note was deleted by another client. Your edits still apply "
            <> "to its text, but it is no longer in the note list.",
          ),
        ])
      False -> html.text("")
    },
    toolbar_view(model),
    textarea.view(open.editor, [
      attribute.classes([
        #("editor", True),
        #("readonly", mutations_locked(model)),
      ]),
      attribute.data("smoke", "editor"),
      attribute.data("note-name", open.name),
      attribute.rows(20),
      attribute.placeholder("Write markdown…"),
      attribute.aria_label("note body: " <> open.name),
      attribute.readonly(mutations_locked(model)),
      attribute.aria_readonly(mutations_locked(model)),
    ])
      |> element.map(Editor),
    case textarea.error(open.editor) {
      Some(reason) -> html.p([attribute.class("error")], [html.text(reason)])
      None -> html.text("")
    },
    // Tagging is filing, not writing: it sat above the editor and interrupted
    // the writing surface every time a note was opened.
    tags_view(model, open),
  ])
}

fn tags_view(model: Model, open: OpenNote) -> Element(Msg) {
  let tags = sidebar.tags_of(model.tag_pairs, open.name)
  html.div([attribute.class("tags")], [
    // An empty chip row used to render as a nested, zero-height `.tags` inside
    // `.tags` on every untagged note.
    case tags {
      [] -> html.text("")
      tags ->
        html.div(
          [attribute.class("tag-chips")],
          list.map(tags, fn(tag) {
            html.span([attribute.class("tag-chip")], [
              html.text(tag),
              html.button(
                [
                  attribute.aria_label("remove tag " <> tag),
                  attribute.disabled(mutations_locked(model)),
                  event.on_click(RemoveTagClicked(tag)),
                ],
                [html.text("✕")],
              ),
            ])
          }),
        )
    },
    html.input([
      attribute.data("smoke", "tag-input"),
      attribute.placeholder("Add tag"),
      attribute.value(model.draft_tag),
      attribute.aria_label("add tag to " <> open.name),
      attribute.disabled(mutations_locked(model)),
      event.on_input(DraftTagChanged),
      event.on_keydown(fn(key) {
        case key {
          "Enter" -> AddTagClicked
          _ -> NoOp
        }
      }),
    ]),
    html.button(
      [
        attribute.data("smoke", "add-tag"),
        event.on_click(AddTagClicked),
        attribute.disabled(
          mutations_locked(model) || string.trim(model.draft_tag) == "",
        ),
      ],
      [html.text("Tag")],
    ),
  ])
}

fn toolbar_view(model: Model) -> Element(Msg) {
  html.div(
    [attribute.class("toolbar"), attribute.role("toolbar")],
    list.map(toolbar.all(), fn(action) {
      html.button(
        [
          attribute.data("smoke", "format-button"),
          event.on_click(FormatClicked(action)),
          attribute.aria_label(toolbar.describe(action)),
          attribute.disabled(mutations_locked(model)),
          attribute.title(case toolbar.shortcut(action) {
            "" -> toolbar.describe(action)
            chord -> toolbar.describe(action) <> " · " <> chord
          }),
        ],
        [html.text(toolbar.label(action))],
      )
    }),
  )
}

/// Newest first and under a real heading. `clap_counter_lustre` heads its
/// error block; an unlabelled `<pre>` in the corner was a regression against
/// the incumbent, and this is the thing the README promises you cannot miss.
fn system_errors_view(errors: List(String)) -> Element(Msg) {
  case errors {
    [] -> html.text("")
    errors ->
      html.section(
        [
          attribute.class("errors"),
          attribute.aria_label("system errors"),
          attribute.data("smoke", "system-errors"),
        ],
        [
          html.h2([], [
            html.text(case list.length(errors) {
              1 -> "1 system error"
              count -> int.to_string(count) <> " system errors"
            }),
          ]),
          html.ul(
            [],
            list.map(errors, fn(error) { html.li([], [html.text(error)]) }),
          ),
        ],
      )
  }
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) -> html.p([attribute.class("error")], [html.text(reason)])
    None -> html.text("")
  }
}

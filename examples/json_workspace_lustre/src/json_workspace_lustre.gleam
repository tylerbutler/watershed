//// A collaborative workspace for live JSON documents.
////
//// One `SharedDirectory` stores the folder tree. Each directory value is a
//// handle to a separate `JsonOt` channel. A same-name create uses the
//// directory key's last-write-wins rule. Folder deletion removes the handle
//// from the tree but does not delete the channel. A recreated folder is a new
//// directory instance.
////
//// The editor changes objects and scalar values. Arrays are read-only.
//// Presence reports the open document path.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document, type JsonOt, type SharedDirectory}
import watershed/browser
import watershed/directory_kernel
import watershed/json_ot.{type JsonValue, type PathKey, Key}
import watershed/json_ot_kernel
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed_lustre

import json_workspace_lustre/doc_schema
import json_workspace_lustre/tree

// ── Dev config for the floodgate dev server (`just integration-up`) ────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("json-workspace")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// ── Presence payload ─────────────────────────────────────────────────────
//
// Identity (colour, name) plus the one ephemeral fact this app tracks: which
// document, if any, this client has open. Never the tree, never a document's
// content — presence is roster and chips only.

pub type WorkspacePresence {
  WorkspacePresence(color: String, name: String, open_path: Option(String))
}

fn encode_presence(presence: WorkspacePresence) -> Json {
  json.object([
    #("color", json.string(presence.color)),
    #("name", json.string(presence.name)),
    #("open_path", case presence.open_path {
      Some(path) -> json.string(path)
      None -> json.null()
    }),
  ])
}

fn presence_decoder() -> decode.Decoder(WorkspacePresence) {
  use color <- decode.field("color", decode.string)
  use name <- decode.field("name", decode.string)
  use open_path <- decode.field("open_path", decode.optional(decode.string))
  decode.success(WorkspacePresence(color:, name:, open_path:))
}

// ── Model ────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

/// A document open in the editor: its full path, the folder it was opened
/// from, the live channel, and the current view of it. `folder_deleted`
/// tracks the one-way transition from "this folder exists" to "it does not
/// any more" — see the doc comment's second behaviour.
type OpenDoc {
  OpenDoc(
    path: String,
    folder: String,
    name: String,
    channel: JsonOt,
    value: JsonValue,
    folder_deleted: Bool,
  )
}

/// The one add-key form visible at a time, scoped to the object node it was
/// opened on. `at` is that object's path; `[]` is the document root.
type AddForm {
  AddForm(at: List(PathKey), key: String, value: String, as_number: Bool)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(doc_schema.Workspace)),
    directory: Option(SharedDirectory),
    user_id: String,
    color: String,
    /// The folder currently browsed, `"/"` at the root.
    path: String,
    subdirectories: List(String),
    entries: List(#(String, Json)),
    new_folder_draft: String,
    new_doc_draft: String,
    open: Option(OpenDoc),
    /// In-flight text per editable leaf. The JSON path is the key.
    scalar_drafts: Dict(List(PathKey), String),
    /// Channel handles that already have a subscription.
    subscribed: List(String),
    add_form: Option(AddForm),
    offline: Bool,
    presence: Option(Handle(WorkspacePresence)),
    /// The open path last announced to presence, so a re-render that
    /// changes nothing does not resend it.
    announced_open: Option(String),
    peers: List(presence.PresenceEntry(WorkspacePresence)),
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.Workspace))
  Connected(Result(Nil, String))
  EnsuredTree(Result(SharedDirectory, String))
  DirectoryChanged(directory_kernel.DirectoryEvent)
  NavigateTo(String)
  NewFolderDrafted(String)
  CreateFolderClicked
  DeleteFolderClicked(String)
  NewDocDrafted(String)
  CreateDocClicked
  OpenDocClicked(String)
  CloseDocClicked
  JsonOtChanged(json_ot_kernel.JsonOtEvent)
  ScalarDrafted(path: List(PathKey), text: String)
  ScalarCommitted(path: List(PathKey), old: JsonValue)
  BoolToggled(path: List(PathKey), old: Bool)
  NumberIncremented(path: List(PathKey), delta: Int)
  DeleteKeyClicked(path: List(PathKey), old: JsonValue)
  AddFormOpened(at: List(PathKey))
  AddFormClosed
  AddKeyDrafted(String)
  AddValueDrafted(String)
  AddAsNumberToggled(Bool)
  AddKeyConfirmed
  ToggledOffline(Bool)
  ReconnectClicked
  PresenceStarted(Handle(WorkspacePresence))
  PresenceEvent(presence.Event(WorkspacePresence))
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      directory: None,
      user_id: user_id,
      color: presence.color_for(user_id),
      path: tree.root_path,
      subdirectories: [],
      entries: [],
      new_folder_draft: "",
      new_doc_draft: "",
      open: None,
      scalar_drafts: dict.new(),
      subscribed: [],
      add_form: None,
      offline: False,
      presence: None,
      announced_open: None,
      peers: [],
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

// ── Bootstrap ────────────────────────────────────────────────────────────

/// Seed or adopt the one root channel, `tree`, from the `Connected(Ok(_))`
/// arm only — never from `GotHandle`. `ensure_directory` seeds a candidate
/// channel and waits for the server to confirm it exists before the app
/// treats it as real, and seeding one before the handshake completes races
/// the connection's own handshake-arm bootstrap
/// (`docs/plans/2026-08-09-ensure-channel-seed-needs-a-ready-connection.md`).
/// `GotHandle` arrives first and only stashes the handle; this function does
/// not run from it.
fn bootstrap_effect(doc: Document(doc_schema.Workspace)) -> Effect(Msg) {
  watershed_lustre.ensure_directory(
    doc,
    watershed.root_typed(doc),
    doc_schema.tree(),
    EnsuredTree,
  )
}

// ── Update ───────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotHandle(doc) -> {
      let model = Model(..model, doc: Some(doc))
      #(model, presence_effect(model, doc))
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.doc, model.directory {
        Some(doc), None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    EnsuredTree(Ok(directory)) -> {
      let model = Model(..model, directory: Some(directory), error: None)
      let model = refresh_listing(model, directory)
      #(
        model,
        watershed_lustre.subscribe_directory(directory, DirectoryChanged),
      )
    }
    EnsuredTree(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    DirectoryChanged(event) -> #(
      handle_directory_event(model, event),
      effect.none(),
    )

    NavigateTo(path) ->
      case model.directory {
        Some(directory) -> #(
          refresh_listing(Model(..model, path: path), directory),
          effect.none(),
        )
        None -> #(model, effect.none())
      }

    NewFolderDrafted(text) -> #(
      Model(..model, new_folder_draft: text),
      effect.none(),
    )

    CreateFolderClicked ->
      case model.directory, string.trim(model.new_folder_draft) {
        Some(directory), name ->
          case tree.valid_name(name) {
            True -> {
              watershed.directory_create_subdirectory(
                directory,
                model.path,
                name,
              )
              #(
                refresh_listing(Model(..model, new_folder_draft: ""), directory),
                effect.none(),
              )
            }
            False -> #(
              Model(
                ..model,
                error: Some("folder names cannot be empty or contain /"),
              ),
              effect.none(),
            )
          }
        _, _ -> #(model, effect.none())
      }

    DeleteFolderClicked(name) ->
      case model.directory {
        Some(directory) -> {
          watershed.directory_delete_subdirectory(directory, model.path, name)
          #(refresh_listing(model, directory), effect.none())
        }
        None -> #(model, effect.none())
      }

    NewDocDrafted(text) -> #(Model(..model, new_doc_draft: text), effect.none())

    CreateDocClicked ->
      case model.directory, model.doc, string.trim(model.new_doc_draft) {
        Some(directory), Some(doc), name ->
          case tree.valid_name(name) {
            False -> #(
              Model(
                ..model,
                error: Some("document names cannot be empty or contain /"),
              ),
              effect.none(),
            )
            True ->
              case watershed.create_json_ot(doc) {
                Ok(channel) -> {
                  watershed.directory_set(
                    directory,
                    model.path,
                    name,
                    watershed.json_ot_handle_of(channel),
                  )
                  let folder = model.path
                  let model =
                    refresh_listing(
                      Model(..model, new_doc_draft: ""),
                      directory,
                    )
                  open_channel(
                    model,
                    tree.join_path(folder, name),
                    folder,
                    name,
                    channel,
                  )
                }
                Error(reason) -> #(
                  Model(..model, error: Some(reason)),
                  effect.none(),
                )
              }
          }
        _, _, _ -> #(model, effect.none())
      }

    OpenDocClicked(name) ->
      case model.directory, model.doc {
        Some(directory), Some(doc) ->
          case watershed.directory_get(directory, model.path, name) {
            Error(Nil) -> #(
              Model(..model, error: Some("no such document: " <> name)),
              effect.none(),
            )
            Ok(value) ->
              case watershed.resolve_json_ot(doc, value) {
                Ok(channel) ->
                  open_channel(
                    model,
                    tree.join_path(model.path, name),
                    model.path,
                    name,
                    channel,
                  )
                Error(reason) -> #(
                  Model(..model, error: Some(reason)),
                  effect.none(),
                )
              }
          }
        _, _ -> #(model, effect.none())
      }

    CloseDocClicked -> {
      let model =
        Model(
          ..model,
          open: None,
          scalar_drafts: dict.new(),
          add_form: None,
          error: None,
        )
      sync_presence(model)
    }

    JsonOtChanged(_event) ->
      case model.open {
        Some(open) -> #(
          Model(..model, open: Some(refresh_open(open))),
          effect.none(),
        )
        None -> #(model, effect.none())
      }

    ScalarDrafted(path, text) -> #(
      Model(
        ..model,
        scalar_drafts: dict.insert(model.scalar_drafts, path, text),
      ),
      effect.none(),
    )

    ScalarCommitted(path, old) -> {
      case
        model.open,
        current_at(model.open, path),
        scalar_from_text(
          old,
          dict.get(model.scalar_drafts, path)
            |> result.unwrap(scalar_text(old)),
        )
      {
        Some(open), Ok(current), Ok(new_value)
          if current == old && new_value != old
        -> {
          watershed.submit_json_ot(open.channel, [
            json_ot.obj_replace(path, old, new_value),
          ])
          #(
            Model(
              ..model,
              scalar_drafts: dict.delete(model.scalar_drafts, path),
              error: None,
            ),
            effect.none(),
          )
        }
        Some(_), Ok(current), Ok(_) if current == old -> #(
          Model(
            ..model,
            scalar_drafts: dict.delete(model.scalar_drafts, path),
            error: None,
          ),
          effect.none(),
        )
        Some(_), _, Error(_) -> #(
          Model(..model, error: Some("the value has the wrong scalar type")),
          effect.none(),
        )
        Some(_), _, Ok(_) -> stale_edit(model)
        None, _, _ -> #(model, effect.none())
      }
    }

    BoolToggled(path, old) ->
      case model.open, current_at(model.open, path) {
        Some(open), Ok(json_ot.VBool(current)) if current == old -> {
          watershed.submit_json_ot(open.channel, [
            json_ot.obj_replace(path, json_ot.VBool(old), json_ot.VBool(!old)),
          ])
          #(Model(..model, error: None), effect.none())
        }
        Some(_), _ -> stale_edit(model)
        None, _ -> #(model, effect.none())
      }

    NumberIncremented(path, delta) ->
      case model.open, current_at(model.open, path) {
        Some(open), Ok(json_ot.VNumber(_)) -> {
          watershed.submit_json_ot(open.channel, [
            json_ot.number_add(path, json_ot.NInt(delta)),
          ])
          #(Model(..model, error: None), effect.none())
        }
        Some(_), _ -> stale_edit(model)
        None, _ -> #(model, effect.none())
      }

    DeleteKeyClicked(path, old) ->
      case model.open, current_at(model.open, path) {
        Some(open), Ok(current) if current == old -> {
          watershed.submit_json_ot(open.channel, [json_ot.obj_delete(path, old)])
          #(Model(..model, error: None), effect.none())
        }
        Some(_), _ -> stale_edit(model)
        None, _ -> #(model, effect.none())
      }

    AddFormOpened(at) -> #(
      Model(
        ..model,
        add_form: Some(AddForm(at:, key: "", value: "", as_number: False)),
      ),
      effect.none(),
    )

    AddFormClosed -> #(Model(..model, add_form: None), effect.none())

    AddKeyDrafted(text) ->
      case model.add_form {
        Some(form) -> #(
          Model(..model, add_form: Some(AddForm(..form, key: text))),
          effect.none(),
        )
        None -> #(model, effect.none())
      }

    AddValueDrafted(text) ->
      case model.add_form {
        Some(form) -> #(
          Model(..model, add_form: Some(AddForm(..form, value: text))),
          effect.none(),
        )
        None -> #(model, effect.none())
      }

    AddAsNumberToggled(as_number) ->
      case model.add_form {
        Some(form) -> #(
          Model(..model, add_form: Some(AddForm(..form, as_number:))),
          effect.none(),
        )
        None -> #(model, effect.none())
      }

    AddKeyConfirmed ->
      case model.open, model.add_form {
        Some(open), Some(form) if form.key != "" -> {
          case current_at(model.open, form.at), add_form_value(form) {
            Ok(json_ot.VObject(members)), Ok(value) ->
              case object_has_key(members, form.key) {
                True -> #(
                  Model(
                    ..model,
                    error: Some("that object already has this key"),
                  ),
                  effect.none(),
                )
                False -> {
                  let path = list.append(form.at, [Key(form.key)])
                  watershed.submit_json_ot(open.channel, [
                    json_ot.obj_insert(path, value),
                  ])
                  #(Model(..model, add_form: None, error: None), effect.none())
                }
              }
            Error(Nil), _ | Ok(_), Ok(_) -> stale_edit(model)
            _, Error(reason) -> #(
              Model(..model, error: Some(reason)),
              effect.none(),
            )
          }
        }
        _, _ -> #(model, effect.none())
      }

    ToggledOffline(offline) ->
      case model.doc {
        Some(doc) -> #(Model(..model, offline: offline), case offline {
          True -> watershed_lustre.go_offline(doc)
          False -> watershed_lustre.go_online(doc)
        })
        None -> #(model, effect.none())
      }

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(model, watershed_lustre.force_reconnect(doc))
        None -> #(model, effect.none())
      }

    PresenceStarted(handle) ->
      sync_presence(Model(..model, presence: Some(handle)))

    PresenceEvent(event) ->
      case event {
        presence.State(entries) | presence.Changed(_, entries) -> #(
          Model(..model, peers: remote_peers(model, entries)),
          effect.none(),
        )
        presence.Failed(presence.DecodeFailed(_, _)) -> #(
          Model(..model, error: Some("a peer sent invalid presence metadata")),
          effect.none(),
        )
        presence.Failed(presence.UnsupportedPresence) -> #(
          Model(..model, error: Some("presence unavailable on this server")),
          effect.none(),
        )
        presence.Failed(presence.Rejected(_, message)) -> #(
          Model(..model, error: Some("presence rejected: " <> message)),
          effect.none(),
        )
      }
  }
}

/// Open `channel` in the editor, subscribe to it, and announce the new path
/// to presence — the one place every "a document is now showing" path
/// (create, open, and a stale-race re-open) has to converge on.
fn open_channel(
  model: Model,
  path: String,
  folder: String,
  name: String,
  channel: JsonOt,
) -> #(Model, Effect(Msg)) {
  let value =
    result.unwrap(watershed.json_ot_view(channel), json_ot.VObject([]))
  let open =
    OpenDoc(path:, folder:, name:, channel:, value:, folder_deleted: False)
  let channel_id = json.to_string(watershed.json_ot_handle_of(channel))
  let #(subscribed, subscription_effect) = case
    list.contains(model.subscribed, channel_id)
  {
    True -> #(model.subscribed, effect.none())
    False -> #(
      [channel_id, ..model.subscribed],
      watershed_lustre.subscribe_json_ot(channel, JsonOtChanged),
    )
  }
  let model =
    Model(
      ..model,
      open: Some(open),
      scalar_drafts: dict.new(),
      subscribed: subscribed,
      add_form: None,
      error: None,
    )
  let #(model, presence_effect) = sync_presence(model)
  #(
    model,
    effect.batch([
      subscription_effect,
      presence_effect,
    ]),
  )
}

fn refresh_open(open: OpenDoc) -> OpenDoc {
  OpenDoc(
    ..open,
    value: result.unwrap(watershed.json_ot_view(open.channel), open.value),
  )
}

fn current_at(
  open: Option(OpenDoc),
  path: List(PathKey),
) -> Result(JsonValue, Nil) {
  case open {
    None -> Error(Nil)
    Some(open) ->
      case watershed.json_ot_view(open.channel) {
        Ok(value) -> tree.value_at(value, path)
        Error(Nil) -> Error(Nil)
      }
  }
}

fn stale_edit(model: Model) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, error: Some("the document changed before this edit applied")),
    effect.none(),
  )
}

fn object_has_key(members: List(#(String, JsonValue)), key: String) -> Bool {
  list.any(members, fn(pair) { pair.0 == key })
}

fn refresh_listing(model: Model, directory: SharedDirectory) -> Model {
  Model(
    ..model,
    subdirectories: watershed.directory_subdirectories(directory, model.path),
    entries: watershed.directory_entries(directory, model.path),
  )
}

/// Every directory event, local or remote, refreshes the current listing —
/// simple and correct: an event at an unrelated path leaves the read at
/// `model.path` unchanged, so over-refreshing costs a redundant read and
/// nothing else. A `SubDirectoryDeleted` additionally checks two independent,
/// narrower things: whether it covers the path being browsed (bounce to the
/// root), and whether it covers the open document's folder (raise the
/// banner).
fn handle_directory_event(
  model: Model,
  event: directory_kernel.DirectoryEvent,
) -> Model {
  case model.directory {
    None -> model
    Some(directory) -> {
      let model = case event {
        directory_kernel.SubDirectoryDeleted(deleted, _) ->
          case tree.path_covers(deleted, model.path) {
            True -> Model(..model, path: tree.root_path)
            False -> model
          }
        directory_kernel.ValueChanged(_, _, _, _)
        | directory_kernel.Cleared(_, _)
        | directory_kernel.SubDirectoryCreated(_, _)
        | directory_kernel.Disposed(_)
        | directory_kernel.Undisposed(_) -> model
      }
      let model = refresh_listing(model, directory)
      case event {
        directory_kernel.SubDirectoryDeleted(deleted, _) ->
          mark_deleted_if_covered(model, deleted)
        directory_kernel.ValueChanged(_, _, _, _)
        | directory_kernel.Cleared(_, _)
        | directory_kernel.SubDirectoryCreated(_, _)
        | directory_kernel.Disposed(_)
        | directory_kernel.Undisposed(_) -> model
      }
    }
  }
}

fn mark_deleted_if_covered(model: Model, deleted_path: String) -> Model {
  case model.open {
    Some(open) if !open.folder_deleted ->
      case tree.path_covers(deleted_path, open.folder) {
        True ->
          Model(..model, open: Some(OpenDoc(..open, folder_deleted: True)))
        False -> model
      }
    _ -> model
  }
}

// ── Presence ─────────────────────────────────────────────────────────────

fn presence_effect(
  model: Model,
  doc: Document(doc_schema.Workspace),
) -> Effect(Msg) {
  watershed_lustre.presence(
    document: doc,
    config: presence.config(encode_presence, presence_decoder()),
    initial: current_presence(model),
    started: PresenceStarted,
    on_event: PresenceEvent,
  )
}

/// Re-announce presence only when the open path actually changed, the same
/// submit-once-per-change discipline `sudoku_lustre`'s cursor uses.
fn sync_presence(model: Model) -> #(Model, Effect(Msg)) {
  let current = option.map(model.open, fn(open) { open.path })
  case model.presence, current == model.announced_open {
    _, True -> #(model, effect.none())
    None, _ -> #(model, effect.none())
    Some(handle), False -> #(
      Model(..model, announced_open: current),
      watershed_lustre.update_presence(handle, current_presence(model)),
    )
  }
}

fn current_presence(model: Model) -> WorkspacePresence {
  WorkspacePresence(
    color: model.color,
    name: presence.short_name(model.user_id),
    open_path: option.map(model.open, fn(open) { open.path }),
  )
}

/// Everyone but this tab. Presence state includes the local session by
/// design, so the roster is filtered here rather than in the driver.
fn remote_peers(
  model: Model,
  entries: List(presence.PresenceEntry(WorkspacePresence)),
) -> List(presence.PresenceEntry(WorkspacePresence)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

/// The connected peers who currently have `path` open, for the tree row's
/// chip strip.
fn peers_at(
  model: Model,
  path: String,
) -> List(presence.PresenceEntry(WorkspacePresence)) {
  list.filter(model.peers, fn(peer) { peer.meta.open_path == Some(path) })
}

// ── Scalar (de)serialization ────────────────────────────────────────────

fn scalar_text(value: JsonValue) -> String {
  case value {
    json_ot.VString(text) -> text
    json_ot.VNumber(json_ot.NInt(integer)) -> int.to_string(integer)
    json_ot.VNumber(json_ot.NFloat(float_value)) -> float.to_string(float_value)
    json_ot.VBool(flag) -> bool_to_string(flag)
    json_ot.VNull -> ""
    json_ot.VObject(_) | json_ot.VArray(_) -> ""
  }
}

/// Parse a committed leaf edit back into `old`'s shape. `VNull` is the one
/// case that changes shape: the only way to give a null leaf a value at all
/// is to type one, and it becomes a string. Every other leaf keeps its type —
/// a number field that fails to parse is left unchanged, not coerced to a
/// string.
fn scalar_from_text(old: JsonValue, text: String) -> Result(JsonValue, Nil) {
  case old {
    json_ot.VString(_) -> Ok(json_ot.VString(text))
    json_ot.VNumber(json_ot.NInt(_)) ->
      int.parse(text) |> result.map(json_ot.NInt) |> result.map(json_ot.VNumber)
    json_ot.VNumber(json_ot.NFloat(_)) ->
      case float.parse(text) {
        Ok(float_value) -> Ok(json_ot.VNumber(json_ot.NFloat(float_value)))
        Error(_) ->
          int.parse(text)
          |> result.map(fn(integer_value) {
            json_ot.VNumber(json_ot.NFloat(int.to_float(integer_value)))
          })
      }
    json_ot.VNull ->
      case text {
        "" -> Error(Nil)
        _ -> Ok(json_ot.VString(text))
      }
    json_ot.VBool(_) | json_ot.VObject(_) | json_ot.VArray(_) -> Error(Nil)
  }
}

fn add_form_value(form: AddForm) -> Result(JsonValue, String) {
  case form.as_number {
    False -> Ok(json_ot.VString(form.value))
    True ->
      int.parse(form.value)
      |> result.map(fn(value) { json_ot.VNumber(json_ot.NInt(value)) })
      |> result.replace_error("the new value is not an integer")
  }
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

// ── View ─────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("workspace")], [
    html.h1([], [html.text("watershed · JSON workspace")]),
    status_line(model),
    roster_view(model),
    breadcrumbs_view(model),
    tree_view(model),
    create_row_view(model),
    editor_view(model),
    html.div([attribute.class("toolbar")], [
      html.button(
        [
          event.on_click(ToggledOffline(!model.offline)),
          attribute.aria_pressed(bool_to_string(model.offline)),
          attribute.disabled(model.doc == None),
        ],
        [
          html.text(case model.offline {
            True -> "Go online"
            False -> "Go offline"
          }),
        ],
      ),
      html.button(
        [
          event.on_click(ReconnectClicked),
          attribute.disabled(model.doc == None),
        ],
        [html.text("Force reconnect")],
      ),
    ]),
    error_view(model.error),
    html.p([attribute.class("hint")], [
      html.text(
        "Open a second tab on the same document to build the tree together. Client: "
        <> model.user_id,
      ),
    ]),
  ])
}

fn status_line(model: Model) -> Element(Msg) {
  let text = case model.status {
    Connecting -> "connecting…"
    Ready ->
      case model.directory {
        Some(_) ->
          case model.offline {
            True -> "offline · edits queue locally"
            False -> "connected · synced"
          }
        None -> "connected · bootstrapping the tree…"
      }
    Failed(reason) -> "failed: " <> reason
  }
  html.p([attribute.class("status")], [html.text(text)])
}

fn roster_view(model: Model) -> Element(Msg) {
  let self_chip =
    chip(presence.short_name(model.user_id) <> " (you)", model.color)
  let peer_chips =
    list.map(model.peers, fn(peer) { chip(peer.meta.name, peer.meta.color) })
  html.div(
    [attribute.class("roster"), attribute.aria_label("Connected clients")],
    [self_chip, ..peer_chips],
  )
}

fn chip(name: String, color: String) -> Element(Msg) {
  html.span(
    [
      attribute.class("chip"),
      attribute.style("border-color", color),
      attribute.style("color", color),
    ],
    [
      html.span(
        [attribute.class("dot"), attribute.style("background", color)],
        [],
      ),
      html.text(name),
    ],
  )
}

fn breadcrumbs_view(model: Model) -> Element(Msg) {
  html.nav(
    [attribute.class("breadcrumbs"), attribute.aria_label("Folder path")],
    list.map(tree.breadcrumbs(model.path), fn(crumb) {
      let #(label, path) = crumb
      html.button(
        [
          event.on_click(NavigateTo(path)),
          attribute.disabled(path == model.path),
        ],
        [html.text(label)],
      )
    }),
  )
}

fn tree_view(model: Model) -> Element(Msg) {
  let rows = tree.rows(model.path, model.subdirectories, model.entries)
  html.ul(
    [attribute.class("tree-rows")],
    list.map(rows, fn(row) { tree_row_view(model, row) }),
  )
}

fn tree_row_view(model: Model, row: tree.Row) -> Element(Msg) {
  case row {
    tree.FolderRow(name, path) ->
      html.li([attribute.class("tree-row")], [
        html.button(
          [attribute.class("name"), event.on_click(NavigateTo(path))],
          [
            html.text("📁 " <> name),
          ],
        ),
        html.button(
          [
            event.on_click(DeleteFolderClicked(name)),
            attribute.aria_label("Delete folder " <> name),
          ],
          [html.text("Delete")],
        ),
      ])
    tree.DocRow(name, path, corrupt) ->
      html.li(
        [attribute.classes([#("tree-row", True), #("corrupt", corrupt)])],
        [
          case corrupt {
            True ->
              html.span([attribute.class("name")], [
                html.text("⚠ " <> name <> " — not a JSON document"),
              ])
            False ->
              html.button(
                [attribute.class("name"), event.on_click(OpenDocClicked(name))],
                [
                  html.text("📄 " <> name),
                ],
              )
          },
          ..list.map(peers_at(model, path), fn(peer) {
            chip(peer.meta.name, peer.meta.color)
          })
        ],
      )
  }
}

fn create_row_view(model: Model) -> Element(Msg) {
  html.div([], [
    html.div([attribute.class("create-row")], [
      html.input([
        attribute.placeholder("new folder"),
        attribute.value(model.new_folder_draft),
        event.on_input(NewFolderDrafted),
      ]),
      html.button(
        [
          event.on_click(CreateFolderClicked),
          attribute.disabled(
            model.directory == None || !tree.valid_name(model.new_folder_draft),
          ),
        ],
        [html.text("New folder")],
      ),
    ]),
    html.div([attribute.class("create-row")], [
      html.input([
        attribute.placeholder("new document"),
        attribute.value(model.new_doc_draft),
        event.on_input(NewDocDrafted),
      ]),
      html.button(
        [
          event.on_click(CreateDocClicked),
          attribute.disabled(
            model.directory == None
            || model.doc == None
            || !tree.valid_name(model.new_doc_draft),
          ),
        ],
        [html.text("New document")],
      ),
    ]),
  ])
}

fn editor_view(model: Model) -> Element(Msg) {
  case model.open {
    None -> html.text("")
    Some(open) ->
      html.section([attribute.class("editor")], [
        html.div([attribute.class("toolbar")], [
          html.strong([], [html.text(open.path)]),
          html.button([event.on_click(CloseDocClicked)], [html.text("Close")]),
        ]),
        case open.folder_deleted {
          True ->
            html.p([attribute.class("banner")], [
              html.text(
                "This document's folder ("
                <> open.folder
                <> ") was deleted. The document is unaffected — the channel"
                <> " keeps working — but it is no longer reachable from the tree.",
              ),
            ])
          False -> html.text("")
        },
        render_node(model, [], open.value),
      ])
  }
}

/// The editable tree for a document node at `path`. Objects recurse and get
/// add/delete-key controls; a scalar leaf edits in place; an array renders
/// fully read-only, itself and everything nested inside it.
fn render_node(
  model: Model,
  path: List(PathKey),
  value: JsonValue,
) -> Element(Msg) {
  case value {
    json_ot.VObject(members) -> render_object(model, path, members)
    json_ot.VArray(items) -> render_readonly(json_ot.VArray(items))
    json_ot.VBool(value) -> render_bool_leaf(path, value)
    json_ot.VNumber(_) -> render_number_leaf(model, path, value)
    json_ot.VString(_) | json_ot.VNull -> render_text_leaf(model, path, value)
  }
}

fn render_object(
  model: Model,
  path: List(PathKey),
  members: List(#(String, JsonValue)),
) -> Element(Msg) {
  html.div([attribute.class("json-object")], [
    html.ul(
      [attribute.class("json-members")],
      list.map(members, fn(pair) {
        let #(key, value) = pair
        let child_path = list.append(path, [Key(key)])
        html.li([attribute.class("json-member")], [
          html.span([attribute.class("json-key")], [html.text(key)]),
          render_node(model, child_path, value),
          html.button(
            [
              event.on_click(DeleteKeyClicked(child_path, value)),
              attribute.aria_label("Delete " <> key),
            ],
            [html.text("×")],
          ),
        ])
      }),
    ),
    add_form_view(model, path),
  ])
}

/// A leaf or a nested value inside an array, rendered without a single
/// control. Arrays are display-only in this editor (see the module doc
/// comment), and that has to hold all the way down: an object nested inside
/// an array must not suddenly grow add/delete controls just because it is,
/// itself, an object.
fn render_readonly(value: JsonValue) -> Element(Msg) {
  case value {
    json_ot.VObject(members) ->
      html.ul(
        [attribute.class("json-members readonly")],
        list.map(members, fn(pair) {
          let #(key, value) = pair
          html.li([], [
            html.span([attribute.class("json-key")], [html.text(key)]),
            render_readonly(value),
          ])
        }),
      )
    json_ot.VArray(items) ->
      html.ol(
        [
          attribute.class("json-array readonly"),
          attribute.aria_label("Read-only list"),
        ],
        list.map(items, fn(value) { html.li([], [render_readonly(value)]) }),
      )
    json_ot.VNull
    | json_ot.VBool(_)
    | json_ot.VNumber(_)
    | json_ot.VString(_) ->
      html.span([attribute.class("json-scalar readonly")], [
        html.text(scalar_text(value)),
      ])
  }
}

fn render_text_leaf(
  model: Model,
  path: List(PathKey),
  value: JsonValue,
) -> Element(Msg) {
  let draft =
    dict.get(model.scalar_drafts, path) |> result.unwrap(scalar_text(value))
  html.input([
    attribute.class("json-scalar-input"),
    attribute.value(draft),
    attribute.placeholder(case value {
      json_ot.VNull -> "null"
      json_ot.VBool(_)
      | json_ot.VNumber(_)
      | json_ot.VString(_)
      | json_ot.VArray(_)
      | json_ot.VObject(_) -> ""
    }),
    event.on_input(fn(text) { ScalarDrafted(path, text) }),
    event.on_change(fn(_raw) { ScalarCommitted(path, value) }),
  ])
}

fn render_number_leaf(
  model: Model,
  path: List(PathKey),
  value: JsonValue,
) -> Element(Msg) {
  let draft =
    dict.get(model.scalar_drafts, path) |> result.unwrap(scalar_text(value))
  html.span([attribute.class("json-number")], [
    html.input([
      attribute.class("json-scalar-input"),
      attribute.value(draft),
      event.on_input(fn(text) { ScalarDrafted(path, text) }),
      event.on_change(fn(_raw) { ScalarCommitted(path, value) }),
    ]),
    html.button(
      [
        event.on_click(NumberIncremented(path, -1)),
        attribute.aria_label("Decrement"),
      ],
      [html.text("−1")],
    ),
    html.button(
      [
        event.on_click(NumberIncremented(path, 1)),
        attribute.aria_label("Increment"),
      ],
      [html.text("+1")],
    ),
  ])
}

fn render_bool_leaf(path: List(PathKey), value: Bool) -> Element(Msg) {
  html.button(
    [
      attribute.class("json-bool"),
      event.on_click(BoolToggled(path, value)),
      attribute.aria_pressed(bool_to_string(value)),
    ],
    [html.text(bool_to_string(value))],
  )
}

fn add_form_view(model: Model, at: List(PathKey)) -> Element(Msg) {
  case model.add_form {
    Some(form) if form.at == at ->
      html.div([attribute.class("add-key-form")], [
        html.input([
          attribute.placeholder("key"),
          attribute.value(form.key),
          event.on_input(AddKeyDrafted),
        ]),
        html.input([
          attribute.placeholder("value"),
          attribute.value(form.value),
          event.on_input(AddValueDrafted),
        ]),
        html.label([], [
          html.input([
            attribute.type_("checkbox"),
            attribute.checked(form.as_number),
            event.on_check(AddAsNumberToggled),
          ]),
          html.text(" number"),
        ]),
        html.button([event.on_click(AddKeyConfirmed)], [html.text("Add")]),
        html.button([event.on_click(AddFormClosed)], [html.text("Cancel")]),
      ])
    _ ->
      html.button([event.on_click(AddFormOpened(at))], [html.text("+ add key")])
  }
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) ->
      html.p([attribute.class("error")], [html.text("Error: " <> reason)])
    None -> html.text("")
  }
}

//// Collaborative retro board — add-wins notes and conflict-free tallies.
////
//// A sticky-note wall is the canonical "many people editing at once" app, and
//// this example is built around the two moments where naive implementations
//// lose data:
////
//// - **Concurrent add.** Two people add a card in the same instant. Under an
////   add-wins OR-map keyed by note id, both survive.
//// - **Concurrent vote.** Two upvotes and a downvote land on +1, not on
////   whatever `get → +1 → set` happens to interleave. Votes are per-key
////   PN-counter leaves in a single `TallyMode` OR-map channel.
////
//// The document is five channels behind one root map: `notes` (RegisterMode
//// OR-map, note id → JSON note), `votes` (TallyMode OR-map, note id → tally),
//// and one `SharedSequence` per column for display order. The split of modes
//// across the two OR-maps happens only in `bootstrap_effect` below.
////
//// Open two browser tabs against the same `?document=` to watch the board
//// converge (server via `just integration-up`).

import dnd/groups
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/io
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
import lustre/event

import watershed.{type Document, type OrMap, type SharedSequence}
import watershed/browser
import watershed/or_map_kernel
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed/summary_policy
import watershed_lustre

import retro_board_lustre/board.{type NoteCard}
import retro_board_lustre/column.{type Column}
import retro_board_lustre/doc_schema
import retro_board_lustre/note.{type Note, Note}

@external(javascript, "./board_ffi.mjs", "now_ms")
fn now_ms() -> Int

// ── Dev config for `just integration-up` (levee/floodgate dev mode) ──────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

/// Advisory only, and deliberately **not** in the document. A shared budget is
/// a coordination problem — two clients concurrently spending the last vote
/// both succeed — and solving it properly means `Claims` or `PactMap`, which
/// is a different demo. The tally is the only thing that converges.
const vote_budget = 5

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("retro")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// ── Presence payload ─────────────────────────────────────────────────────────

/// This app's per-peer presence payload — everything but the user id, which
/// the library's envelope carries. Static per tab, so it is announced once at
/// start and never updated; liveness/roster/TTL are the driver's job.
pub type BoardPresence {
  BoardPresence(color: String, name: String)
}

fn encode_presence(p: BoardPresence) -> json.Json {
  json.object([
    #("color", json.string(p.color)),
    #("name", json.string(p.name)),
  ])
}

fn presence_decoder() -> decode.Decoder(BoardPresence) {
  use color <- decode.field("color", decode.string)
  use name <- decode.field("name", decode.string)
  decode.success(BoardPresence(color:, name:))
}

// ── Drag and drop (the `dnd` package, groups module) ─────────────────────────

/// What the drag system sees: the rendered cards plus one footer drop target
/// per column (so empty columns and "drop at the end" are reachable).
///
/// The system's item list is a throwaway projection of the rendered board.
/// Both operations in `dnd_config` are `Unaltered`, so the library never
/// reorders it — it only runs the gesture (mousedown → ghost → mouseover
/// tracking → mouseup) and reports the endpoints via `info`. The completed
/// drag is applied to the CRDT channels in `apply_drop`, through the same
/// code path as the "→ column" buttons.
type DragItem {
  DragCard(column: Column, note_id: String)
  ColumnFooter(column: Column)
}

/// Where a drag endpoint landed, recovered from the element id the view
/// registered. Ids are used instead of the library's indices because a remote
/// edit can reflow the board mid-drag, and ids stay valid where indices go
/// stale.
type DropTarget {
  OnCard(note_id: String)
  AtColumnEnd(column: Column)
}

fn drag_item_column(item: DragItem) -> Column {
  case item {
    DragCard(column, _) -> column
    ColumnFooter(column) -> column
  }
}

fn card_element_id(note_id: String) -> String {
  "card:" <> note_id
}

fn footer_element_id(column: Column) -> String {
  "footer:" <> column.id(column)
}

fn parse_drop_target(element_id: String) -> Result(DropTarget, Nil) {
  case string.split_once(element_id, ":") {
    Ok(#("card", note_id)) -> Ok(OnCard(note_id))
    Ok(#("footer", column_id)) ->
      column.from_id(column_id) |> result.map(AtColumnEnd)
    _ -> Error(Nil)
  }
}

fn dnd_config() -> groups.Config(DragItem) {
  groups.Config(
    before_update: fn(_, _, items) { items },
    movement: groups.Free,
    // `Unaltered` twice over: the list is a projection, and the CRDT channels
    // are the only thing that moves. The comparator still tells the system
    // whether a drag crossed columns; the setter is never reached.
    listen: groups.OnDrop,
    operation: groups.Unaltered,
    groups: groups.GroupsConfig(
      listen: groups.OnDrop,
      operation: groups.Unaltered,
      comparator: fn(a, b) { drag_item_column(a) == drag_item_column(b) },
      setter: fn(_target, drag) { drag },
    ),
    // Mouse only for now: the package's touch mode is a two-tap pattern that
    // needs its own drop-zone UI, and the ↑/↓/→ buttons already cover touch.
    mode: groups.MouseOnly,
    touch_timeout_ms: 5000,
    touch_scroll_threshold: 10,
    touch_hold_duration_ms: 200,
    touch_drop_cooldown_ms: 500,
  )
}

/// The flat projection handed to the drag system on every step: each column's
/// rendered cards, then its footer. Unfiled cards are not draggable.
fn drag_items(model: Model) -> List(DragItem) {
  column.all()
  |> list.flat_map(fn(column) {
    list.append(
      board.cards_for(model.board, column)
        |> list.map(fn(card) { DragCard(column, card.id) }),
      [ColumnFooter(column)],
    )
  })
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

/// All five nested channels, resolved. Built by `assemble` once the last
/// `Ensured*` message lands; the app never touches a channel before then.
type SharedState {
  SharedState(
    notes: OrMap,
    votes: OrMap,
    went_well: SharedSequence,
    to_improve: SharedSequence,
    action_items: SharedSequence,
  )
}

type PendingShared {
  PendingShared(
    notes: Option(OrMap),
    votes: Option(OrMap),
    went_well: Option(SharedSequence),
    to_improve: Option(SharedSequence),
    action_items: Option(SharedSequence),
  )
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(doc_schema.BoardDoc)),
    shared: Option(SharedState),
    pending: PendingShared,
    user_id: String,
    color: String,
    presence: Option(Handle(BoardPresence)),
    peers: List(presence.PresenceEntry(BoardPresence)),
    board: board.RenderedBoard,
    drafts: Dict(String, String),
    /// `Some(#(note_id, draft_text))` while a card is being edited inline.
    editing: Option(#(String, String)),
    /// The `dnd` package's gesture system. It tracks the drag and positions
    /// the ghost; it never reorders anything — see `dnd_config`.
    dnd: groups.System(DragItem, Msg),
    votes_remaining: Int,
    last_error: Option(String),
    log: List(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.BoardDoc))
  Connected(Result(Nil, String))
  EnsuredNotes(Result(OrMap, String))
  EnsuredVotes(Result(OrMap, String))
  EnsuredWentWell(Result(SharedSequence, String))
  EnsuredToImprove(Result(SharedSequence, String))
  EnsuredActionItems(Result(SharedSequence, String))
  SharedChanged
  DraftChanged(Column, String)
  AddClicked(Column)
  MoveUpClicked(Column, String)
  MoveDownClicked(Column, String)
  MoveToColumnClicked(String, Column)
  UpvoteClicked(String)
  DownvoteClicked(String)
  EditClicked(String)
  EditDraftChanged(String)
  EditSaved
  EditCancelled
  DeleteClicked(String)
  DndStep(groups.DndMsg)
  PresenceStarted(Handle(BoardPresence))
  PresenceEvent(presence.Event(BoardPresence))
  ReconnectClicked
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      shared: None,
      pending: PendingShared(None, None, None, None, None),
      user_id: user_id,
      color: presence.color_for(user_id),
      presence: None,
      peers: [],
      board: board.empty(),
      drafts: dict.new(),
      editing: None,
      dnd: groups.create(dnd_config(), DndStep),
      votes_remaining: vote_budget,
      last_error: None,
      log: [],
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

/// Bootstrap the document declaratively once the handshake completes: seed the
/// title, adopt-or-seed all five nested channels, and start auto-summaries.
///
/// This is the only place the two OR-map modes are named. `notes` MUST be
/// RegisterMode and `votes` MUST be TallyMode — the schema cannot enforce it
/// (both fields are `ChannelField(BoardDoc, OrMapChannel)`), and a client that
/// passes the wrong mode silently adopts whatever the channel was created
/// with, surfacing only later as a runtime ModeMismatch.
fn bootstrap_effect(doc: Document(doc_schema.BoardDoc)) -> Effect(Msg) {
  let root = watershed.root_typed(doc)
  effect.batch([
    // A retro writes many small operations (a card, a vote apiece); summarizing
    // keeps a late joiner's catch-up in band instead of replaying the whole
    // log.
    watershed_lustre.auto_summarize(
      document: doc,
      policy: summary_policy.policy() |> summary_policy.with_threshold(200),
    ),
    watershed_lustre.ensure_field(root, doc_schema.title(), "Sprint retro"),
    watershed_lustre.ensure_or_map(
      doc,
      root,
      doc_schema.notes(),
      or_map_kernel.RegisterMode,
      EnsuredNotes,
    ),
    watershed_lustre.ensure_or_map(
      doc,
      root,
      doc_schema.votes(),
      or_map_kernel.TallyMode,
      EnsuredVotes,
    ),
    watershed_lustre.ensure_sequence(
      doc,
      root,
      doc_schema.went_well(),
      EnsuredWentWell,
    ),
    watershed_lustre.ensure_sequence(
      doc,
      root,
      doc_schema.to_improve(),
      EnsuredToImprove,
    ),
    watershed_lustre.ensure_sequence(
      doc,
      root,
      doc_schema.action_items(),
      EnsuredActionItems,
    ),
  ])
}

/// Assemble `SharedState` once all five nested channels have resolved, take a
/// first snapshot, and start the per-channel subscriptions. A no-operation
/// until the last channel arrives or once already assembled.
fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, model.pending {
    None,
      PendingShared(
        Some(notes),
        Some(votes),
        Some(went_well),
        Some(to_improve),
        Some(action_items),
      )
    -> {
      let shared =
        SharedState(notes:, votes:, went_well:, to_improve:, action_items:)
      let model =
        snapshot(Model(..model, shared: Some(shared)))
        |> log_line("board ready · all five channels resolved")
      #(model, subscribe_shared_effect(shared))
    }
    _, _ -> #(model, effect.none())
  }
}

/// Every channel event — local or remote, any of the five channels — collapses
/// to one `SharedChanged`, and the handler re-reads the world. A remote
/// cross-column move is three operations across three channels in no particular
/// order; re-reading current optimistic state on each event renders every
/// interleaving sensibly without patching logic.
fn subscribe_shared_effect(shared: SharedState) -> Effect(Msg) {
  effect.batch([
    watershed_lustre.subscribe_or_map(shared.notes, fn(_) { SharedChanged }),
    watershed_lustre.subscribe_or_map(shared.votes, fn(_) { SharedChanged }),
    watershed_lustre.subscribe_sequence(shared.went_well, fn(_) {
      SharedChanged
    }),
    watershed_lustre.subscribe_sequence(shared.to_improve, fn(_) {
      SharedChanged
    }),
    watershed_lustre.subscribe_sequence(shared.action_items, fn(_) {
      SharedChanged
    }),
  ])
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The handle arrives before the handshake completes; hold it and bootstrap
    // once `Connected` has made us Ready.
    GotHandle(doc) -> {
      let model =
        Model(..model, doc: Some(doc))
        |> log_line("document handle acquired")
      // Presence only needs the doc, so it starts now; the channel bootstrap
      // waits for the handshake.
      let presence_start =
        watershed_lustre.presence(
          document: doc,
          config: presence.config(encode_presence, presence_decoder()),
          initial: BoardPresence(
            color: model.color,
            name: presence.short_name(model.user_id),
          ),
          started: PresenceStarted,
          on_event: PresenceEvent,
        )
      case model.status, model.shared {
        Ready, None -> #(
          model,
          effect.batch([bootstrap_effect(doc), presence_start]),
        )
        _, _ -> #(model, presence_start)
      }
    }

    Connected(Ok(_)) -> {
      let model =
        Model(..model, status: Ready)
        |> log_line("initial handshake complete")
      case model.doc, model.shared {
        Some(doc), None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }
    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), last_error: Some(reason))
        |> log_line("connection failed · " <> reason),
      effect.none(),
    )

    EnsuredNotes(Ok(notes)) ->
      Model(
        ..model,
        pending: PendingShared(..model.pending, notes: Some(notes)),
      )
      |> log_line("notes channel ready (RegisterMode)")
      |> assemble
    EnsuredNotes(Error(reason)) -> #(
      ensure_failed(model, "notes", reason),
      effect.none(),
    )

    EnsuredVotes(Ok(votes)) ->
      Model(
        ..model,
        pending: PendingShared(..model.pending, votes: Some(votes)),
      )
      |> log_line("votes channel ready (TallyMode)")
      |> assemble
    EnsuredVotes(Error(reason)) -> #(
      ensure_failed(model, "votes", reason),
      effect.none(),
    )

    EnsuredWentWell(Ok(sequence)) ->
      Model(
        ..model,
        pending: PendingShared(..model.pending, went_well: Some(sequence)),
      )
      |> log_line("went_well sequence ready")
      |> assemble
    EnsuredWentWell(Error(reason)) -> #(
      ensure_failed(model, "went_well", reason),
      effect.none(),
    )

    EnsuredToImprove(Ok(sequence)) ->
      Model(
        ..model,
        pending: PendingShared(..model.pending, to_improve: Some(sequence)),
      )
      |> log_line("to_improve sequence ready")
      |> assemble
    EnsuredToImprove(Error(reason)) -> #(
      ensure_failed(model, "to_improve", reason),
      effect.none(),
    )

    EnsuredActionItems(Ok(sequence)) ->
      Model(
        ..model,
        pending: PendingShared(..model.pending, action_items: Some(sequence)),
      )
      |> log_line("action_items sequence ready")
      |> assemble
    EnsuredActionItems(Error(reason)) -> #(
      ensure_failed(model, "action_items", reason),
      effect.none(),
    )

    SharedChanged -> #(snapshot(model), effect.none())

    DraftChanged(column, text) -> #(
      Model(..model, drafts: dict.insert(model.drafts, column.id(column), text)),
      effect.none(),
    )

    // A new card is one register write keyed by a fresh note id. Two tabs
    // adding in the same instant write two different keys, and the OR-map
    // keeps both — that is the add-wins headline. (The column sequences join
    // in a later rung; until then order within a column is `(created, id)`.)
    AddClicked(column) -> {
      let text = string.trim(draft_for(model, column))
      case text, model.shared {
        "", _ -> #(model, effect.none())
        _, None -> #(model, effect.none())
        _, Some(shared) -> {
          let created = now_ms()
          let id =
            "note-"
            <> model.user_id
            <> "-"
            <> int.to_string(created)
            <> "-"
            <> int.to_string(int.random(10_000))
          let entry =
            Note(
              text: text,
              column: column.id(column),
              author: model.user_id,
              created: created,
            )
          watershed.or_map_set_json(shared.notes, id, note.to_json(entry))
          let sequence = sequence_for(shared, column)
          let result =
            watershed.sequence_insert(
              sequence,
              watershed.sequence_length(sequence),
              json.string(id),
            )
          let model =
            Model(..model, drafts: dict.delete(model.drafts, column.id(column)))
            |> record(result, "insert")
          #(snapshot(model), effect.none())
        }
      }
    }

    MoveUpClicked(column, id) -> #(
      snapshot(move_within(model, column, id, -1)),
      effect.none(),
    )
    MoveDownClicked(column, id) -> #(
      snapshot(move_within(model, column, id, 1)),
      effect.none(),
    )

    // The demo's honest limitation, exercised: a cross-column move is three
    // operations across two channel kinds with no transaction spanning them.
    // Under concurrent moves the sequences can disagree with the register; the
    // render rule (see `board.gleam`) keeps every reachable state sensible, and
    // the register write is the authoritative one. Sweeping the id out of
    // *every* sequence (not just the source) doubles as opportunistic repair of
    // garbage left by earlier races.
    MoveToColumnClicked(id, destination) ->
      case model.shared {
        None -> #(model, effect.none())
        Some(shared) -> #(
          snapshot(apply_card_drop(model, shared, id, AtColumnEnd(destination))),
          effect.none(),
        )
      }

    // Votes are increments against per-key PN-counter leaves — never
    // `get → +1 → set`. Two concurrent upvotes sum to 2; a concurrent up and
    // down land on 0. The budget is local, advisory UI: the increment goes
    // through regardless, and a downvote takes a spent vote back.
    UpvoteClicked(id) ->
      case model.shared {
        None -> #(model, effect.none())
        Some(shared) -> {
          watershed.or_map_increment(shared.votes, id, 1)
          let model =
            Model(
              ..model,
              votes_remaining: int.max(0, model.votes_remaining - 1),
            )
          #(snapshot(model), effect.none())
        }
      }

    DownvoteClicked(id) ->
      case model.shared {
        None -> #(model, effect.none())
        Some(shared) -> {
          watershed.or_map_increment(shared.votes, id, -1)
          let model =
            Model(
              ..model,
              votes_remaining: int.min(vote_budget, model.votes_remaining + 1),
            )
          #(snapshot(model), effect.none())
        }
      }

    EditClicked(id) -> {
      let current = case model.shared {
        Some(shared) ->
          case watershed.or_map_value(shared.notes, id) {
            Ok(or_map_kernel.Register(value)) ->
              Some(note.from_register(value).text)
            _ -> None
          }
        None -> None
      }
      case current {
        Some(text) -> #(
          Model(..model, editing: Some(#(id, text))),
          effect.none(),
        )
        None -> #(model, effect.none())
      }
    }

    EditDraftChanged(text) ->
      case model.editing {
        Some(#(id, _)) -> #(
          Model(..model, editing: Some(#(id, text))),
          effect.none(),
        )
        None -> #(model, effect.none())
      }

    // Saving re-reads the register at save time and rewrites only the text, so
    // a concurrent move's column rewrite is not clobbered by a stale copy held
    // since the edit began.
    EditSaved ->
      case model.editing, model.shared {
        Some(#(id, text)), Some(shared) -> {
          case watershed.or_map_value(shared.notes, id) {
            Ok(or_map_kernel.Register(value)) -> {
              let edited = Note(..note.from_register(value), text: text)
              watershed.or_map_set_json(shared.notes, id, note.to_json(edited))
              Nil
            }
            // The note was deleted while this tab was editing. Saving anyway
            // would resurrect it (add-wins); the button path chooses not to,
            // and the convergence suite pins what happens when a save *does*
            // race a delete in flight.
            _ -> Nil
          }
          #(snapshot(Model(..model, editing: None)), effect.none())
        }
        _, _ -> #(Model(..model, editing: None), effect.none())
      }

    EditCancelled -> #(Model(..model, editing: None), effect.none())

    // Delete is the OR-map's observed remove, plus the sequence sweep. The
    // note's tally is deliberately left behind: it is unreachable (the render
    // rule never looks up votes for a missing note) and removing it would add
    // a second cross-channel race for no visible benefit.
    DeleteClicked(id) ->
      case model.shared {
        None -> #(model, effect.none())
        Some(shared) -> {
          watershed.or_map_remove(shared.notes, id)
          list.each(column.all(), fn(column) {
            remove_from_sequence(sequence_for(shared, column), id)
          })
          let editing = case model.editing {
            Some(#(editing_id, _)) if editing_id == id -> None
            other -> other
          }
          #(snapshot(Model(..model, editing: editing)), effect.none())
        }
      }

    DndStep(dnd_msg) -> {
      // A completed drag is applied BEFORE the library's update clears its
      // drag state — `info` is only readable while the drag is live.
      let model = case dnd_msg {
        groups.DragEnd -> snapshot(apply_drop(model))
        _ -> model
      }
      let #(dnd_model, _unaltered) =
        model.dnd.update(dnd_msg, model.dnd.model, drag_items(model))
      #(
        Model(..model, dnd: groups.System(..model.dnd, model: dnd_model)),
        effect.none(),
      )
    }

    PresenceStarted(handle) -> #(
      Model(..model, presence: Some(handle)),
      effect.none(),
    )

    PresenceEvent(event) ->
      case event {
        presence.State(entries) | presence.Changed(_, entries) -> #(
          Model(..model, peers: remote_peers(model, entries)),
          effect.none(),
        )
        // A peer whose metadata we cannot read is dropped by the driver; the
        // two loud failures are worth a banner, since presence silently not
        // working is the failure mode this model exists to avoid.
        presence.Failed(presence.DecodeFailed(_, _)) -> #(model, effect.none())
        presence.Failed(presence.UnsupportedPresence) -> #(
          Model(
            ..model,
            last_error: Some("presence unavailable on this server"),
          ),
          effect.none(),
        )
        presence.Failed(presence.Rejected(_, message)) -> #(
          Model(..model, last_error: Some("presence rejected: " <> message)),
          effect.none(),
        )
      }

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(
          log_line(model, "force reconnect requested"),
          watershed_lustre.force_reconnect(doc),
        )
        None -> #(model, effect.none())
      }
  }
}

/// Everyone but this tab. Presence state includes the local session by
/// design, so the roster is filtered here rather than in the driver.
fn remote_peers(
  model: Model,
  entries: List(presence.PresenceEntry(BoardPresence)),
) -> List(presence.PresenceEntry(BoardPresence)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

fn sequence_for(shared: SharedState, column: Column) -> SharedSequence {
  case column {
    column.WentWell -> shared.went_well
    column.ToImprove -> shared.to_improve
    column.ActionItems -> shared.action_items
  }
}

/// Swap a card with its rendered neighbour (`step` is -1 for ↑, 1 for ↓).
///
/// Rendered position is not sequence position — the render rule skips garbage
/// entries, so every sequence operation here uses the cards' **raw**
/// `sequence_index`. `sequence_move` interprets the destination after the
/// source is removed, which makes the neighbour's raw index the correct
/// destination in both directions (up: the neighbour has not shifted; down: it
/// has shifted into the slot just before where the moved card must land).
///
/// A card that is not in the sequence at all (rendered from its register via
/// the `created` tiebreaker) gets an explicit repair on ↑/↓: its id is
/// inserted at the start or end of the sequence.
fn move_within(model: Model, column: Column, id: String, step: Int) -> Model {
  case model.shared {
    None -> model
    Some(shared) -> {
      let sequence = sequence_for(shared, column)
      let cards = board.cards_for(model.board, column)
      let position =
        list.index_map(cards, fn(card, index) { #(card, index) })
        |> list.find(fn(entry) { { entry.0 }.id == id })
      case position {
        Error(Nil) -> model
        Ok(#(card, index)) -> {
          let neighbour =
            cards
            |> list.drop(int.max(0, index + step))
            |> list.first
            |> result.replace_error(Nil)
          case index + step < 0, card.sequence_index, neighbour {
            True, _, _ -> model
            _, Some(from), Ok(to_card) ->
              case to_card.sequence_index {
                Some(to) ->
                  record(
                    model,
                    watershed.sequence_move(sequence, from, to),
                    "move",
                  )
                // The neighbour is an unsequenced tail card; there is no
                // sequence position to swap with.
                None -> model
              }
            _, None, _ -> {
              let at = case step < 0 {
                True -> 0
                False -> watershed.sequence_length(sequence)
              }
              record(
                model,
                watershed.sequence_insert(sequence, at, json.string(id)),
                "repair insert",
              )
            }
            _, Some(_), Error(Nil) -> model
          }
        }
      }
    }
  }
}

/// A completed drag, read from the drag system's `info` and translated into
/// channel operations. No-operations when nothing meaningful was dragged or
/// dropped.
fn apply_drop(model: Model) -> Model {
  case model.dnd.info(model.dnd.model), model.shared {
    Some(info), Some(shared) if info.drag_element_id != info.drop_element_id ->
      case
        parse_drop_target(info.drag_element_id),
        parse_drop_target(info.drop_element_id)
      {
        Ok(OnCard(id)), Ok(target) -> apply_card_drop(model, shared, id, target)
        _, _ -> model
      }
    _, _ -> model
  }
}

/// Move a note: remove its id from every sequence that contains it, insert it
/// at the target position, and — only if the column actually changed —
/// rewrite its `column` register, last, because it is the one the render rule
/// treats as authoritative. The register write is conditional on purpose: the
/// note record is whole-record LWW, so rewriting it on a same-column reorder
/// would clobber a concurrent text edit for no reason.
fn apply_card_drop(
  model: Model,
  shared: SharedState,
  id: String,
  target: DropTarget,
) -> Model {
  case watershed.or_map_value(shared.notes, id) {
    Ok(or_map_kernel.Register(value)) -> {
      let dragged = note.from_register(value)
      let destination = case target {
        AtColumnEnd(column) -> Ok(column)
        // Dropping on a card lands in the column that card's *register* puts
        // it in — the same authority the render rule uses.
        OnCard(target_id) if target_id != id ->
          case watershed.or_map_value(shared.notes, target_id) {
            Ok(or_map_kernel.Register(target_value)) ->
              column.from_id(note.from_register(target_value).column)
            _ -> Error(Nil)
          }
        OnCard(_) -> Error(Nil)
      }
      case destination {
        Error(Nil) -> model
        Ok(destination_column) -> {
          list.each(column.all(), fn(column) {
            remove_from_sequence(sequence_for(shared, column), id)
          })
          let sequence = sequence_for(shared, destination_column)
          let at = case target {
            AtColumnEnd(_) -> watershed.sequence_length(sequence)
            OnCard(target_id) ->
              index_of_id(sequence, target_id)
              |> result.unwrap(watershed.sequence_length(sequence))
          }
          let result = watershed.sequence_insert(sequence, at, json.string(id))
          case dragged.column == column.id(destination_column) {
            True -> Nil
            False -> {
              let moved = Note(..dragged, column: column.id(destination_column))
              watershed.or_map_set_json(shared.notes, id, note.to_json(moved))
            }
          }
          record(model, result, "move to " <> column.label(destination_column))
        }
      }
    }
    // The note vanished (a peer deleted it) between render and drop.
    _ -> model
  }
}

/// The raw index of a note id in a sequence, garbage entries included.
fn index_of_id(sequence: SharedSequence, id: String) -> Result(Int, Nil) {
  watershed.sequence_values(sequence)
  |> list.index_map(fn(value, index) { #(value, index) })
  |> list.find(fn(entry) {
    json.parse(json.to_string(entry.0), decode.string) == Ok(id)
  })
  |> result.map(fn(entry) { entry.1 })
}

/// Delete every occurrence of a note id from a sequence, by raw index.
fn remove_from_sequence(sequence: SharedSequence, id: String) -> Nil {
  case index_of_id(sequence, id) {
    Ok(index) -> {
      let _ = watershed.sequence_delete(sequence, index)
      remove_from_sequence(sequence, id)
    }
    Error(Nil) -> Nil
  }
}

/// Fold an edit result into the model: clear the banner on success, surface
/// the runtime's own message on failure. A stale index is a legitimate
/// outcome — a peer can delete a card between render and click.
fn record(model: Model, result: Result(Nil, String), verb: String) -> Model {
  case result {
    Ok(Nil) -> Model(..model, last_error: None)
    Error(reason) ->
      Model(..model, last_error: Some(verb <> " failed: " <> reason))
      |> log_line(verb <> " rejected · " <> reason)
  }
}

fn ensure_failed(model: Model, channel: String, reason: String) -> Model {
  Model(..model, last_error: Some(channel <> " channel failed: " <> reason))
  |> log_line(channel <> " channel failed · " <> reason)
}

/// Re-read the optimistic state of all five channels and re-run the render
/// rule. Event payloads are deliberately ignored (see `subscribe_shared_effect`).
fn snapshot(model: Model) -> Model {
  case model.shared {
    None -> model
    Some(shared) ->
      Model(
        ..model,
        board: board.render(
          note_entries(shared.notes),
          vote_entries(shared.votes),
          [
            #(column.WentWell, sequence_ids(shared.went_well)),
            #(column.ToImprove, sequence_ids(shared.to_improve)),
            #(column.ActionItems, sequence_ids(shared.action_items)),
          ],
        ),
      )
  }
}

fn note_entries(notes: OrMap) -> List(#(String, Note)) {
  watershed.or_map_entries(notes)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Register(value) -> Ok(#(entry.0, note.from_register(value)))
      or_map_kernel.Tally(_) -> Error(Nil)
    }
  })
}

fn vote_entries(votes: OrMap) -> List(#(String, Int)) {
  watershed.or_map_entries(votes)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Tally(count) -> Ok(#(entry.0, count))
      or_map_kernel.Register(_) -> Error(Nil)
    }
  })
}

/// A column sequence holds JSON-encoded note ids; skip anything else.
fn sequence_ids(sequence: SharedSequence) -> List(String) {
  watershed.sequence_values(sequence)
  |> list.filter_map(fn(value) {
    json.parse(json.to_string(value), decode.string)
    |> result.replace_error(Nil)
  })
}

fn draft_for(model: Model, column: Column) -> String {
  dict.get(model.drafts, column.id(column)) |> result.unwrap("")
}

fn log_line(model: Model, line: String) -> Model {
  let tagged = "[" <> model.user_id <> "] " <> line
  io.println(tagged)
  Model(..model, log: list.take([tagged, ..model.log], 40))
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  // While a drag is live, the container carries the global mouse listeners
  // the drag system needs (it registers none of its own), and text selection
  // is suppressed so the drag doesn't paint selections across the board.
  let drag_listeners = case model.dnd.info(model.dnd.model) {
    Some(_) -> [
      attribute.class("dragging-active"),
      event.on("mousemove", {
        use client_x <- decode.field("clientX", decode.float)
        use client_y <- decode.field("clientY", decode.float)
        decode.success(
          DndStep(groups.Drag(groups.Position(client_x, client_y))),
        )
      }),
      event.on("mouseup", decode.success(DndStep(groups.DragEnd))),
      event.on("mouseleave", decode.success(DndStep(groups.DragEnd))),
    ]
    None -> []
  }
  html.main([attribute.class("wrap"), ..drag_listeners], [
    ghost_view(model),
    html.header([attribute.class("board-header")], [
      html.h1([], [html.text("watershed · retro board")]),
      status_line(model),
      html.span([attribute.class("budget")], [
        html.text(int.to_string(model.votes_remaining) <> " votes left"),
      ]),
      roster_view(model),
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
    error_view(model),
    html.div(
      [attribute.class("board")],
      list.map(column.all(), fn(column) { column_view(model, column) }),
    ),
    unfiled_view(model),
    html.p([attribute.class("hint")], [
      html.text(
        "Open a second tab on the same document and edit from both — "
        <> "concurrent adds and votes converge. Client: "
        <> model.user_id,
      ),
    ]),
  ])
}

fn status_line(model: Model) -> Element(Msg) {
  let connection = case model.status {
    Connecting -> "connecting…"
    Ready -> "connected"
    Failed(reason) -> "failed: " <> reason
  }
  let channels = case model.shared {
    Some(_) -> "board ready"
    None -> "channels " <> int.to_string(pending_count(model.pending)) <> "/5"
  }
  let notes =
    [
      model.board.went_well,
      model.board.to_improve,
      model.board.action_items,
      model.board.unfiled,
    ]
    |> list.flatten
    |> list.length
  html.p([attribute.class("status")], [
    html.text(
      connection
      <> " · "
      <> channels
      <> " · "
      <> int.to_string(notes)
      <> " notes",
    ),
  ])
}

fn pending_count(pending: PendingShared) -> Int {
  [
    option.is_some(pending.notes),
    option.is_some(pending.votes),
    option.is_some(pending.went_well),
    option.is_some(pending.to_improve),
    option.is_some(pending.action_items),
  ]
  |> list.count(fn(ready) { ready })
}

/// The live-presence roster: self plus every peer seen within the TTL.
/// Derived entirely from the ephemeral driver, so it self-heals when a tab
/// goes away.
fn roster_view(model: Model) -> Element(Msg) {
  let self_chip =
    chip(presence.short_name(model.user_id) <> " (you)", model.color)
  let peer_chips =
    model.peers
    |> list.map(fn(peer) { chip(peer.meta.name, peer.meta.color) })
  html.div(
    [attribute.class("roster"), attribute.aria_label("Participants online")],
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

fn error_view(model: Model) -> Element(Msg) {
  html.p([attribute.class("error")], [
    html.text(option.unwrap(model.last_error, "")),
  ])
}

fn column_view(model: Model, column: Column) -> Element(Msg) {
  let cards = board.cards_for(model.board, column)
  let last = list.length(cards) - 1
  let offset = column_offset(model, column)
  let card_list = case cards {
    [] -> html.p([attribute.class("empty")], [html.text("(no cards yet)")])
    cards ->
      html.ul(
        [attribute.class("cards")],
        list.index_map(cards, fn(entry, index) {
          card_view(model, entry, Some(#(column, index, last, offset + index)))
        }),
      )
  }
  let highlight = case drop_column(model) {
    Ok(target) if target == column -> " drop-target"
    _ -> ""
  }
  // The footer is the "drop at the end" target — it also makes an empty
  // column droppable at all. Only a live drop target while dragging.
  let footer_id = footer_element_id(column)
  let footer_events = case model.dnd.info(model.dnd.model) {
    Some(_) -> model.dnd.drop_events(offset + list.length(cards), footer_id)
    None -> []
  }
  html.section([attribute.class("column" <> highlight)], [
    html.h2([], [html.text(column.label(column))]),
    compose_view(model, column),
    card_list,
    html.div(
      [
        attribute.class("column-footer"),
        attribute.id(footer_id),
        ..footer_events
      ],
      [],
    ),
  ])
}

/// This column's first flat index in `drag_items`' projection.
fn column_offset(model: Model, column: Column) -> Int {
  column.all()
  |> list.take_while(fn(other) { other != column })
  |> list.fold(0, fn(acc, other) {
    acc + list.length(board.cards_for(model.board, other)) + 1
  })
}

/// The column the pointer is over mid-drag, for the drop-target highlight.
fn drop_column(model: Model) -> Result(Column, Nil) {
  case model.dnd.info(model.dnd.model) {
    Some(info) ->
      case parse_drop_target(info.drop_element_id) {
        Ok(AtColumnEnd(column)) -> Ok(column)
        Ok(OnCard(id)) ->
          column.all()
          |> list.find(fn(column) {
            board.cards_for(model.board, column)
            |> list.any(fn(card) { card.id == id })
          })
        Error(Nil) -> Error(Nil)
      }
    None -> Error(Nil)
  }
}

/// The floating copy of the dragged card that follows the pointer.
fn ghost_view(model: Model) -> Element(Msg) {
  let dragged = case model.dnd.info(model.dnd.model) {
    Some(info) ->
      case parse_drop_target(info.drag_element_id) {
        Ok(OnCard(id)) -> card_by_id(model, id)
        Ok(AtColumnEnd(_)) -> Error(Nil)
        Error(Nil) -> Error(Nil)
      }
    None -> Error(Nil)
  }
  case dragged {
    Ok(card) ->
      html.div(
        [
          attribute.class("card ghost"),
          ..model.dnd.ghost_styles(model.dnd.model)
        ],
        [html.div([attribute.class("card-text")], [html.text(card.note.text)])],
      )
    Error(Nil) -> html.text("")
  }
}

fn card_by_id(model: Model, id: String) -> Result(NoteCard, Nil) {
  [
    model.board.went_well,
    model.board.to_improve,
    model.board.action_items,
    model.board.unfiled,
  ]
  |> list.flatten
  |> list.find(fn(card) { card.id == id })
}

fn compose_view(model: Model, column: Column) -> Element(Msg) {
  let draft = draft_for(model, column)
  html.div([attribute.class("compose")], [
    html.input([
      attribute.placeholder("Add a card…"),
      attribute.value(draft),
      event.on_input(fn(text) { DraftChanged(column, text) }),
    ]),
    html.button(
      [
        event.on_click(AddClicked(column)),
        attribute.disabled(string.trim(draft) == ""),
      ],
      [html.text("Add")],
    ),
  ])
}

fn card_view(
  model: Model,
  entry: NoteCard,
  place: Option(#(Column, Int, Int, Int)),
) -> Element(Msg) {
  let element_id = card_element_id(entry.id)
  let is_dragging = case model.dnd.info(model.dnd.model) {
    Some(info) -> info.drag_element_id == element_id
    None -> False
  }
  let move_controls = case place {
    Some(#(column, index, last, _)) ->
      list.append(
        [
          html.button(
            [
              event.on_click(MoveUpClicked(column, entry.id)),
              attribute.disabled(index == 0),
            ],
            [html.text("↑")],
          ),
          html.button(
            [
              event.on_click(MoveDownClicked(column, entry.id)),
              attribute.disabled(index == last),
            ],
            [html.text("↓")],
          ),
        ],
        column.all()
          |> list.filter(fn(other) { other != column })
          |> list.map(fn(other) {
            html.button([event.on_click(MoveToColumnClicked(entry.id, other))], [
              html.text("→ " <> column.label(other)),
            ])
          }),
      )
    None -> []
  }
  let text_or_editor = case model.editing {
    Some(#(editing_id, draft)) if editing_id == entry.id ->
      html.div([attribute.class("compose")], [
        html.input([attribute.value(draft), event.on_input(EditDraftChanged)]),
        html.button([event.on_click(EditSaved)], [html.text("Save")]),
        html.button([event.on_click(EditCancelled)], [html.text("Cancel")]),
      ])
    _ -> html.div([attribute.class("card-text")], [html.text(entry.note.text)])
  }
  // Idle: the grip arms the drag system. Dragging: every card (except the
  // one in flight) is a drop target. Mirrors the vendor's groups example —
  // attaching drop listeners only mid-drag keeps idle hovers free of
  // dispatches.
  let #(grip, drop_attrs) = case place, model.dnd.info(model.dnd.model) {
    Some(#(_, _, _, flat_index)), None -> #(
      [
        html.span(
          [
            attribute.class("grip"),
            ..model.dnd.drag_events(flat_index, element_id)
          ],
          [html.text("⠿")],
        ),
      ],
      [],
    )
    Some(#(_, _, _, flat_index)), Some(_) -> #([], case is_dragging {
      True -> []
      False -> model.dnd.drop_events(flat_index, element_id)
    })
    None, _ -> #([], [])
  }
  let dragging_class = case is_dragging {
    True -> " dragging"
    False -> ""
  }
  html.li(
    [
      attribute.class("card" <> dragging_class),
      attribute.id(element_id),
      ..drop_attrs
    ],
    [
      text_or_editor,
      html.div(
        [attribute.class("card-meta")],
        list.flatten([
          grip,
          [
            html.span([attribute.class("author")], [
              html.text(entry.note.author),
            ]),
            html.span([attribute.class("tally")], [
              html.text(int.to_string(entry.votes)),
            ]),
            html.button(
              [
                event.on_click(UpvoteClicked(entry.id)),
                attribute.disabled(model.votes_remaining <= 0),
              ],
              [html.text("▲")],
            ),
            html.button([event.on_click(DownvoteClicked(entry.id))], [
              html.text("▼"),
            ]),
            html.button([event.on_click(EditClicked(entry.id))], [
              html.text("✎"),
            ]),
            html.button([event.on_click(DeleteClicked(entry.id))], [
              html.text("✕"),
            ]),
          ],
          move_controls,
        ]),
      ),
    ],
  )
}

fn unfiled_view(model: Model) -> Element(Msg) {
  case model.board.unfiled {
    [] -> html.text("")
    cards ->
      html.section([attribute.class("unfiled")], [
        html.h2([], [html.text("Unfiled")]),
        html.ul(
          [attribute.class("cards")],
          list.map(cards, fn(entry) { card_view(model, entry, None) }),
        ),
      ])
  }
}

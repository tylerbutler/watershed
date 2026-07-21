//// Collaborative reorderable playlist — a `SharedSequence` demo.
////
//// Where `dice_lustre` edits one key on a map and `sudoku_lustre` fans out
//// across four nested channels, this example exercises the one thing no other
//// watershed DDS offers: **`move`**, an ordered-list reorder that converges
//// under concurrency. Two tabs dragging the same track to different positions
//// land on the same order rather than duplicating or dropping it.
////
//// Op coverage, all against a single sequence:
////
//// - `sequence_insert` — append a track (index == current length)
//// - `sequence_move`   — the ↑/↓ buttons; **destination is interpreted after
////                       the element is removed**, so moving down one is
////                       `to = from + 1` and moving up one is `to = from - 1`
//// - `sequence_replace`— rename a track in place
//// - `sequence_delete` — drop a track
////
//// Every mutation returns `Result(Nil, String)`: unlike map `set`, a sequence
//// edit can legitimately fail when an index is stale — a peer may have deleted
//// the row out from under this tab between render and click. The app surfaces
//// that error instead of asserting, which is the honest shape for index-
//// addressed ops on a shared list.
////
//// Open two browser tabs against the same `just server` document to watch
//// reorders converge.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute.{class, disabled, placeholder, value}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/sequence_kernel
import watershed_js.{type Document, type SharedSequence}
import watershed_lustre

import doc_schema
import track.{type Track, Track}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "playlist"

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document),
    tracks_channel: Option(SharedSequence),
    user_id: String,
    tracks: List(Track),
    draft_title: String,
    draft_artist: String,
    last_error: Option(String),
    diagnostics: Option(watershed_js.Diagnostics),
    diagnostic_log: List(String),
  )
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  EnsuredTracks(Result(SharedSequence, String))
  TracksChanged(sequence_kernel.SequenceEvent)
  DiagnosticsTick
  DraftTitleChanged(String)
  DraftArtistChanged(String)
  AddClicked
  MoveUpClicked(Int)
  MoveDownClicked(Int)
  RenameClicked(Int)
  RemoveClicked(Int)
  ReconnectClicked
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      tracks_channel: None,
      user_id: user_id,
      tracks: [],
      draft_title: "",
      draft_artist: "",
      last_error: None,
      diagnostics: None,
      diagnostic_log: [],
    )
  #(
    model,
    watershed_lustre.connect_dev(
      url: socket_url,
      tenant: tenant,
      secret: tenant_secret,
      document: document_id,
      user_id: user_id,
      got_document: GotHandle,
      connected: Connected,
    ),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The handle is ready: seed the title and bootstrap the tracks sequence.
    // `ensure_sequence` creates and attaches one only if the slot is empty, so
    // every tab can run this unconditionally without racing to a duplicate.
    GotHandle(doc) -> {
      let diagnostics = watershed_js.diagnostics(doc)
      let root = watershed_js.root_typed(doc)
      let model =
        Model(..model, doc: Some(doc), diagnostics: Some(diagnostics))
        |> add_diagnostic(
          "document handle acquired · " <> diagnostic_line(diagnostics),
        )
      #(
        model,
        effect.batch([
          watershed_lustre.ensure_field(
            root,
            doc_schema.title(),
            "watershed shared playlist",
          ),
          watershed_lustre.ensure_sequence(
            doc,
            root,
            doc_schema.tracks(),
            EnsuredTracks,
          ),
          watershed_lustre.after(250, DiagnosticsTick),
        ]),
      )
    }

    Connected(Ok(_)) -> {
      let model =
        snapshot(Model(..model, status: Ready))
        |> add_diagnostic("initial handshake complete")
      #(model, effect.none())
    }
    Connected(Error(reason)) -> {
      let model =
        Model(..model, status: Failed(reason))
        |> add_diagnostic("connection failed · " <> reason)
      #(model, effect.none())
    }

    // The sequence resolved: subscribe, then take a first snapshot so a tab
    // joining an existing playlist renders it without waiting for an edit.
    EnsuredTracks(Ok(sequence)) -> {
      let model =
        snapshot(Model(..model, tracks_channel: Some(sequence)))
        |> add_diagnostic("tracks sequence ready")
      #(model, watershed_lustre.subscribe_sequence(sequence, TracksChanged))
    }
    EnsuredTracks(Error(reason)) -> {
      let model = add_diagnostic(model, "tracks sequence failed · " <> reason)
      #(Model(..model, last_error: Some(reason)), effect.none())
    }

    // A sequence event fired (local or remote). `SequenceChanged` carries the
    // full post-edit value list, but we re-read the channel anyway so the
    // rendered list always reflects committed optimistic state.
    TracksChanged(event) -> {
      let diagnostics = case model.doc {
        Some(doc) -> Some(watershed_js.diagnostics(doc))
        None -> None
      }
      let detail = case diagnostics {
        Some(diagnostics) ->
          event_line(event) <> " · " <> diagnostic_line(diagnostics)
        None -> event_line(event)
      }
      let model =
        snapshot(Model(..model, diagnostics: diagnostics))
        |> add_diagnostic(detail)
      #(model, effect.none())
    }

    DiagnosticsTick -> {
      let next = case model.doc {
        Some(doc) -> Some(watershed_js.diagnostics(doc))
        None -> None
      }
      let model = case next, model.diagnostics {
        Some(current), Some(previous) if current != previous ->
          Model(..model, diagnostics: next)
          |> add_diagnostic("runtime · " <> diagnostic_line(current))
        _, _ -> Model(..model, diagnostics: next)
      }
      #(model, watershed_lustre.after(250, DiagnosticsTick))
    }

    DraftTitleChanged(text) -> #(
      Model(..model, draft_title: text),
      effect.none(),
    )
    DraftArtistChanged(text) -> #(
      Model(..model, draft_artist: text),
      effect.none(),
    )

    // Append at the end: the insert index may equal the length (0..length),
    // which is what makes "add to the bottom" expressible at all.
    AddClicked -> {
      let title = string.trim(model.draft_title)
      case title, model.tracks_channel {
        "", _ -> #(model, effect.none())
        _, None -> #(model, effect.none())
        _, Some(sequence) -> {
          let artist = case string.trim(model.draft_artist) {
            "" -> "unknown"
            artist -> artist
          }
          let entry =
            Track(title: title, artist: artist, added_by: model.user_id)
          let result =
            watershed_js.sequence_insert(
              sequence,
              watershed_js.sequence_length(sequence),
              track.to_json(entry),
            )
          let model =
            Model(..model, draft_title: "", draft_artist: "")
            |> record(result, "insert")
          #(model, effect.none())
        }
      }
    }

    // Move destinations are interpreted *after* the element is lifted out, so
    // one step up is `from - 1` and one step down is `from + 1`. The buttons
    // are disabled at the ends, but a concurrent delete can still invalidate
    // the index between render and click — hence the Result.
    MoveUpClicked(index) -> #(
      mutate(model, "move", fn(seq) {
        watershed_js.sequence_move(seq, index, index - 1)
      }),
      effect.none(),
    )

    MoveDownClicked(index) -> #(
      mutate(model, "move", fn(seq) {
        watershed_js.sequence_move(seq, index, index + 1)
      }),
      effect.none(),
    )

    // Replace swaps the value at an index in place, keeping its position. It is
    // one watershed op composed from a lattice delete + insert delta, not a
    // native lattice primitive.
    RenameClicked(index) ->
      case list_at(model.tracks, index) {
        None -> #(model, effect.none())
        Some(existing) -> {
          let renamed = Track(..existing, title: bump_title(existing.title))
          #(
            mutate(model, "replace", fn(seq) {
              watershed_js.sequence_replace(seq, index, track.to_json(renamed))
            }),
            effect.none(),
          )
        }
      }

    RemoveClicked(index) -> #(
      mutate(model, "delete", fn(seq) {
        watershed_js.sequence_delete(seq, index)
      }),
      effect.none(),
    )

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(
          add_diagnostic(model, "force reconnect requested"),
          watershed_lustre.force_reconnect(doc),
        )
        None -> #(model, effect.none())
      }
  }
}

/// Run a sequence edit against the resolved channel, recording any index error.
fn mutate(
  model: Model,
  verb: String,
  edit: fn(SharedSequence) -> Result(Nil, String),
) -> Model {
  case model.tracks_channel {
    None -> model
    Some(sequence) -> record(model, edit(sequence), verb)
  }
}

/// Fold an edit result into the model: clear the banner on success, surface the
/// runtime's own message on failure.
fn record(model: Model, result: Result(Nil, String), verb: String) -> Model {
  case result {
    Ok(Nil) -> Model(..model, last_error: None)
    Error(reason) ->
      Model(..model, last_error: Some(verb <> " failed: " <> reason))
      |> add_diagnostic(verb <> " rejected · " <> reason)
  }
}

/// Re-read the optimistic sequence state into the model for rendering.
fn snapshot(model: Model) -> Model {
  case model.tracks_channel {
    None -> model
    Some(sequence) ->
      Model(
        ..model,
        tracks: watershed_js.sequence_values(sequence)
          |> list.map(track.from_json),
      )
  }
}

/// Cycle a title through a "(take N)" suffix so the rename button has something
/// deterministic to write without prompting for input.
fn bump_title(title: String) -> String {
  case string.split(title, " (take ") {
    [stem, rest] ->
      case int.parse(string.replace(rest, ")", "")) {
        Ok(take) -> stem <> " (take " <> int.to_string(take + 1) <> ")"
        Error(_) -> title <> " (take 2)"
      }
    _ -> title <> " (take 2)"
  }
}

fn list_at(items: List(a), index: Int) -> Option(a) {
  case items, index {
    [], _ -> None
    _, index if index < 0 -> None
    [first, ..], 0 -> Some(first)
    [_, ..rest], _ -> list_at(rest, index - 1)
  }
}

fn add_diagnostic(model: Model, line: String) -> Model {
  let tagged = "[" <> model.user_id <> "] " <> line
  io.println(tagged)
  Model(..model, diagnostic_log: take([tagged, ..model.diagnostic_log], 40))
}

fn take(items: List(a), count: Int) -> List(a) {
  case items, count {
    _, count if count <= 0 -> []
    [], _ -> []
    [first, ..rest], _ -> [first, ..take(rest, count - 1)]
  }
}

fn event_line(event: sequence_kernel.SequenceEvent) -> String {
  case event {
    sequence_kernel.SequenceChanged(values) ->
      "sequenceChanged length="
      <> int.to_string(list.length(values))
      <> " ["
      <> {
        values
        |> list.map(fn(value) { track.from_json(value).title })
        |> string.join(", ")
      }
      <> "]"
  }
}

fn diagnostic_line(diagnostics: watershed_js.Diagnostics) -> String {
  "phase="
  <> diagnostics.phase
  <> " client="
  <> option.unwrap(diagnostics.client_id, "none")
  <> " sn="
  <> option_int(diagnostics.last_seen_sequence_number)
  <> " next_csn="
  <> option_int(diagnostics.next_client_sequence_number)
  <> " in_flight="
  <> int.to_string(diagnostics.in_flight_count)
  <> " buffered="
  <> int.to_string(diagnostics.buffered_out_of_order_count)
  <> " resubmit_at="
  <> option_int(diagnostics.resubmit_checkpoint)
  <> " synced="
  <> bool_string(diagnostics.synced)
}

fn option_int(value: Option(Int)) -> String {
  value
  |> option.map(int.to_string)
  |> option.unwrap("none")
}

fn bool_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([class("wrap")], [
    html.h1([], [html.text("watershed · collaborative playlist")]),
    status_line(model),
    compose_view(model),
    error_view(model),
    tracks_view(model),
    diagnostics_view(model),
    html.p([class("hint")], [
      html.text(
        "Open a second tab on the same document and reorder from both — "
        <> "concurrent moves converge on one order. Client: "
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
  let runtime = case model.diagnostics {
    Some(diagnostics) -> " · " <> diagnostics.phase
    None -> ""
  }
  html.p([class("status")], [
    html.text(
      connection
      <> runtime
      <> " · "
      <> int.to_string(list.length(model.tracks))
      <> " tracks",
    ),
  ])
}

fn compose_view(model: Model) -> Element(Msg) {
  html.div([class("compose")], [
    html.input([
      placeholder("Track title"),
      value(model.draft_title),
      event.on_input(DraftTitleChanged),
    ]),
    html.input([
      placeholder("Artist"),
      value(model.draft_artist),
      event.on_input(DraftArtistChanged),
    ]),
    html.button(
      [
        event.on_click(AddClicked),
        disabled(string.trim(model.draft_title) == ""),
      ],
      [html.text("Add")],
    ),
    html.button([event.on_click(ReconnectClicked)], [
      html.text("Force reconnect"),
    ]),
  ])
}

fn error_view(model: Model) -> Element(Msg) {
  html.p([class("error")], [
    html.text(option.unwrap(model.last_error, "")),
  ])
}

fn tracks_view(model: Model) -> Element(Msg) {
  case model.tracks {
    [] -> html.p([class("empty")], [html.text("(playlist is empty)")])
    tracks -> {
      let last = list.length(tracks) - 1
      html.ul(
        [class("tracks")],
        list.index_map(tracks, fn(entry, index) {
          track_row(entry, index, last)
        }),
      )
    }
  }
}

fn track_row(entry: Track, index: Int, last: Int) -> Element(Msg) {
  html.li([class("track")], [
    html.span([class("ordinal")], [html.text(int.to_string(index + 1) <> ".")]),
    html.div([class("track-body")], [
      html.div([class("track-title")], [html.text(entry.title)]),
      html.div([class("track-artist")], [
        html.text(entry.artist <> " · added by " <> entry.added_by),
      ]),
    ]),
    html.div([class("track-controls")], [
      html.button([event.on_click(MoveUpClicked(index)), disabled(index == 0)], [
        html.text("↑"),
      ]),
      html.button(
        [event.on_click(MoveDownClicked(index)), disabled(index == last)],
        [html.text("↓")],
      ),
      html.button([event.on_click(RenameClicked(index))], [html.text("Rename")]),
      html.button([event.on_click(RemoveClicked(index))], [html.text("✕")]),
    ]),
  ])
}

fn diagnostics_view(model: Model) -> Element(Msg) {
  let current = case model.diagnostics {
    Some(diagnostics) -> diagnostic_line(diagnostics)
    None -> "runtime diagnostics unavailable"
  }
  let log = model.diagnostic_log |> string.join("\n")
  html.section([class("diagnostics")], [
    html.h2([], [html.text("Diagnostics")]),
    html.p([], [
      html.text(
        "Compare this panel across tabs. Browser DevTools receives the same trace.",
      ),
    ]),
    html.pre([class("diagnostic-current")], [html.text(current)]),
    html.pre([class("diagnostic-log")], [html.text(log)]),
  ])
}

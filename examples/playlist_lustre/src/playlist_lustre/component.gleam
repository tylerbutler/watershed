//// The collaborative playlist as a nested MVU triple.
////
//// Everything here is addressed against one `SharedSequence`: append, the ↑/↓
//// reorder, rename in place, delete. What is *not* here is anything that takes
//// a `Document` rather than a channel — the connection, diagnostics, and force
//// reconnect stay with whoever owns the document, because those are
//// document-wide no matter which panel calls them.
////
//// Same contract as `text_lustre/component`, with one addition: `init` takes
//// the client's user id, because a track records who added it. A panel may ask
//// for whatever identity it needs; what it may not ask for is the root.
////
//// ```gleam
//// let #(panel, fx) = component.init(doc, playlist_map, user_id)
//// let #(panel, fx) = component.update(panel, inner)
//// component.view(panel) |> element.map(PlaylistMsg)
//// ```

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document, type SharedSequence, type TypedMap}
import watershed/sequence_kernel
import watershed_lustre

import playlist_lustre/doc_schema
import playlist_lustre/track.{type Track, Track}

// ── Model ────────────────────────────────────────────────────────────────────

pub opaque type Model {
  Model(
    tracks_channel: Option(SharedSequence),
    user_id: String,
    tracks: List(Track),
    draft_title: String,
    draft_artist: String,
    last_error: Option(String),
  )
}

pub opaque type Msg {
  EnsuredTracks(Result(SharedSequence, String))
  TracksChanged(sequence_kernel.SequenceEvent)
  DraftTitleChanged(String)
  DraftArtistChanged(String)
  AddClicked
  MoveUpClicked(Int)
  MoveDownClicked(Int)
  RenameClicked(Int)
  RemoveClicked(Int)
}

/// Seed the title and bootstrap the tracks sequence under `map`.
///
/// Attaching a channel needs a ready connection, so the caller must not call
/// this before its handshake completes.
pub fn init(
  document: Document(root),
  map: TypedMap(doc_schema.PlaylistDoc),
  user_id: String,
) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      tracks_channel: None,
      user_id: user_id,
      tracks: [],
      draft_title: "",
      draft_artist: "",
      last_error: None,
    )
  #(
    model,
    effect.batch([
      watershed_lustre.ensure_field(
        map,
        doc_schema.title(),
        "watershed shared playlist",
      ),
      watershed_lustre.ensure_sequence(
        document,
        map,
        doc_schema.tracks(),
        EnsuredTracks,
      ),
    ]),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The sequence resolved: subscribe, then take a first snapshot so a client
    // joining an existing playlist renders it without waiting for an edit.
    EnsuredTracks(Ok(sequence)) -> {
      let model = snapshot(Model(..model, tracks_channel: Some(sequence)))
      #(model, watershed_lustre.subscribe_sequence(sequence, TracksChanged))
    }
    EnsuredTracks(Error(reason)) -> #(
      Model(..model, last_error: Some(reason)),
      effect.none(),
    )

    // A sequence event fired (local or remote). `SequenceChanged` carries the
    // full post-edit value list, but we re-read the channel anyway so the
    // rendered list always reflects committed optimistic state.
    TracksChanged(_) -> #(snapshot(model), effect.none())

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
            watershed.sequence_insert(
              sequence,
              watershed.sequence_length(sequence),
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
        watershed.sequence_move(seq, index, index - 1)
      }),
      effect.none(),
    )

    MoveDownClicked(index) -> #(
      mutate(model, "move", fn(seq) {
        watershed.sequence_move(seq, index, index + 1)
      }),
      effect.none(),
    )

    // Replace swaps the value at an index in place, keeping its position. It is
    // one watershed op composed from a lattice delete + insert delta, not a
    // native lattice primitive.
    RenameClicked(index) ->
      case list_at(model.tracks, index) {
        Error(Nil) -> #(model, effect.none())
        Ok(existing) -> {
          let renamed = Track(..existing, title: bump_title(existing.title))
          #(
            mutate(model, "replace", fn(seq) {
              watershed.sequence_replace(seq, index, track.to_json(renamed))
            }),
            effect.none(),
          )
        }
      }

    RemoveClicked(index) -> #(
      mutate(model, "delete", fn(seq) { watershed.sequence_delete(seq, index) }),
      effect.none(),
    )
  }
}

/// How many tracks are in the rendered list.
pub fn track_count(model: Model) -> Int {
  list.length(model.tracks)
}

/// The last rejected edit, if any — an index can go stale when a peer deletes
/// the row out from under this client between render and click.
pub fn error(model: Model) -> Option(String) {
  model.last_error
}

/// The live channel, once it exists — for an owner that wants its own
/// subscription to the same events.
pub fn channel(model: Model) -> Option(SharedSequence) {
  model.tracks_channel
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
  }
}

/// Re-read the optimistic sequence state into the model for rendering.
fn snapshot(model: Model) -> Model {
  case model.tracks_channel {
    None -> model
    Some(sequence) ->
      Model(
        ..model,
        tracks: watershed.sequence_values(sequence)
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

fn list_at(items: List(a), index: Int) -> Result(a, Nil) {
  case items, index {
    [], _ -> Error(Nil)
    _, index if index < 0 -> Error(Nil)
    [first, ..], 0 -> Ok(first)
    [_, ..rest], _ -> list_at(rest, index - 1)
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("playlist-panel")], [
    compose_view(model),
    error_view(model),
    tracks_view(model),
  ])
}

fn compose_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("compose")], [
    html.input([
      attribute.placeholder("Track title"),
      attribute.value(model.draft_title),
      event.on_input(DraftTitleChanged),
    ]),
    html.input([
      attribute.placeholder("Artist"),
      attribute.value(model.draft_artist),
      event.on_input(DraftArtistChanged),
    ]),
    html.button(
      [
        event.on_click(AddClicked),
        attribute.disabled(string.trim(model.draft_title) == ""),
      ],
      [html.text("Add")],
    ),
  ])
}

fn error_view(model: Model) -> Element(Msg) {
  html.p([attribute.class("error")], [
    html.text(option.unwrap(model.last_error, "")),
  ])
}

fn tracks_view(model: Model) -> Element(Msg) {
  case model.tracks {
    [] -> html.p([attribute.class("empty")], [html.text("(playlist is empty)")])
    tracks -> {
      let last = list.length(tracks) - 1
      html.ul(
        [attribute.class("tracks")],
        list.index_map(tracks, fn(entry, index) {
          track_row(entry, index, last)
        }),
      )
    }
  }
}

fn track_row(entry: Track, index: Int, last: Int) -> Element(Msg) {
  html.li([attribute.class("track")], [
    html.span([attribute.class("ordinal")], [
      html.text(int.to_string(index + 1) <> "."),
    ]),
    html.div([attribute.class("track-body")], [
      html.div([attribute.class("track-title")], [html.text(entry.title)]),
      html.div([attribute.class("track-artist")], [
        html.text(entry.artist <> " · added by " <> entry.added_by),
      ]),
    ]),
    html.div([attribute.class("track-controls")], [
      html.button(
        [event.on_click(MoveUpClicked(index)), attribute.disabled(index == 0)],
        [
          html.text("↑"),
        ],
      ),
      html.button(
        [
          event.on_click(MoveDownClicked(index)),
          attribute.disabled(index == last),
        ],
        [html.text("↓")],
      ),
      html.button([event.on_click(RenameClicked(index))], [html.text("Rename")]),
      html.button([event.on_click(RemoveClicked(index))], [html.text("✕")]),
    ]),
  ])
}

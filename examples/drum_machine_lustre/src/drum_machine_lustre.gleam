//// Collaborative drum machine — a 4×16 step sequencer on watershed.
////
//// Every other example in `examples/` *renders* convergence. This one plays
//// it: open two tabs against the same document, toggle steps, and both
//// browsers land on the same pattern.
////
//// The pattern is four OR-sets, one per track, holding the enabled step
//// indices as decimal strings. Add-wins is the correct rule — two people
//// enabling the same step is not a conflict, and toggling a step off and back
//// on has to work.
////
//// Tempo is deliberately different. It lives on a `PactMap`, so changing it
//// requires the room to sign off first (DM6). That contrast is the point:
//// everything you can hear is uncoordinated and fast, and the one setting that
//// would make the room lurch is slow and agreed.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute.{
  aria_label, aria_pressed, class, classes, role, tabindex,
}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import doc_schema
import watershed_js.{type Document, type OrSet, type PactMap}
import watershed_lustre

// ── Dev config for the floodgate dev server (`just integration-up`) ──────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "drum-machine"

/// Steps per bar. Sixteen 16th notes, the TR-808 grid everyone already knows.
const step_count = 16

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// ── Tracks ───────────────────────────────────────────────────────────────────

pub type Track {
  Kick
  Snare
  Hat
  Clap
}

fn tracks() -> List(Track) {
  [Kick, Snare, Hat, Clap]
}

fn track_name(track: Track) -> String {
  case track {
    Kick -> "Kick"
    Snare -> "Snare"
    Hat -> "Hat"
    Clap -> "Clap"
  }
}

/// The OR-set backing one track.
fn track_set(shared: SharedState, track: Track) -> OrSet {
  case track {
    Kick -> shared.kick
    Snare -> shared.snare
    Hat -> shared.hat
    Clap -> shared.clap
  }
}

/// The enabled steps of one track, as read into the model.
fn track_steps(pattern: Pattern, track: Track) -> List(String) {
  case track {
    Kick -> pattern.kick
    Snare -> pattern.snare
    Hat -> pattern.hat
    Clap -> pattern.clap
  }
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type SharedState {
  SharedState(
    kick: OrSet,
    snare: OrSet,
    hat: OrSet,
    clap: OrSet,
    settings: PactMap,
  )
}

/// The nested channels as they resolve during bootstrap. Each `ensure_*` effect
/// fills one slot; when all five are present they assemble into `SharedState`.
type PendingShared {
  PendingShared(
    kick: Option(OrSet),
    snare: Option(OrSet),
    hat: Option(OrSet),
    clap: Option(OrSet),
    settings: Option(PactMap),
  )
}

/// The pattern as rendered — one list of enabled step indices per track.
type Pattern {
  Pattern(
    kick: List(String),
    snare: List(String),
    hat: List(String),
    clap: List(String),
  )
}

fn empty_pattern() -> Pattern {
  Pattern(kick: [], snare: [], hat: [], clap: [])
}

type Model {
  Model(
    status: Status,
    doc: Option(Document),
    shared: Option(SharedState),
    pending: PendingShared,
    user_id: String,
    pattern: Pattern,
    /// Keyboard cursor over the grid, as `#(track index, step index)`. The grid
    /// is a single tab stop; the arrow keys move within it.
    cursor: #(Int, Int),
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  EnsuredKick(Result(OrSet, String))
  EnsuredSnare(Result(OrSet, String))
  EnsuredHat(Result(OrSet, String))
  EnsuredClap(Result(OrSet, String))
  EnsuredSettings(Result(PactMap, String))
  SharedChanged
  StepClicked(Int, Int)
  KeyPressed(String)
  ReconnectClicked
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      shared: None,
      pending: PendingShared(None, None, None, None, None),
      user_id: user_id,
      pattern: empty_pattern(),
      cursor: #(0, 0),
      error: None,
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

/// Bootstrap the document declaratively: seed the title, adopt-or-seed each
/// nested channel, and watch the root — all as one batch of effects. Each
/// `ensure_*` dispatches its channel back as an `Ensured*` message; they
/// assemble into `SharedState` once all five have arrived.
fn bootstrap_effect(doc: Document) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
  effect.batch([
    watershed_lustre.ensure_field(root, doc_schema.title(), "Drum machine"),
    watershed_lustre.ensure_or_set(doc, root, doc_schema.kick(), EnsuredKick),
    watershed_lustre.ensure_or_set(doc, root, doc_schema.snare(), EnsuredSnare),
    watershed_lustre.ensure_or_set(doc, root, doc_schema.hat(), EnsuredHat),
    watershed_lustre.ensure_or_set(doc, root, doc_schema.clap(), EnsuredClap),
    watershed_lustre.ensure_pact_map(
      doc,
      root,
      doc_schema.settings(),
      EnsuredSettings,
    ),
    watershed_lustre.subscribe(watershed_js.root(doc), fn(_event) {
      SharedChanged
    }),
  ])
}

/// Assemble `SharedState` once all five nested channels have resolved, and
/// start the per-channel subscriptions. A no-op until the last channel arrives
/// or once already assembled.
fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, model.pending {
    None,
      PendingShared(
        Some(kick),
        Some(snare),
        Some(hat),
        Some(clap),
        Some(settings),
      )
    -> {
      let shared = SharedState(kick:, snare:, hat:, clap:, settings:)
      #(
        snapshot(Model(..model, shared: Some(shared), error: None)),
        subscribe_shared_effect(shared),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

/// The narrowed per-kind subscriptions as one batch. A 4×16 grid is cheap
/// enough that every handler just re-reads the whole pattern.
fn subscribe_shared_effect(shared: SharedState) -> Effect(Msg) {
  effect.batch([
    watershed_lustre.subscribe_or_set(shared.kick, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_or_set(shared.snare, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_or_set(shared.hat, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_or_set(shared.clap, fn(_event) { SharedChanged }),
  ])
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
        _, _ -> #(snapshot(model), effect.none())
      }
    }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    EnsuredKick(Ok(set)) ->
      assemble(
        Model(..model, pending: PendingShared(..model.pending, kick: Some(set))),
      )
    EnsuredKick(Error(reason)) -> #(ensure_failed(model, reason), effect.none())

    EnsuredSnare(Ok(set)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, snare: Some(set)),
        ),
      )
    EnsuredSnare(Error(reason)) -> #(
      ensure_failed(model, reason),
      effect.none(),
    )

    EnsuredHat(Ok(set)) ->
      assemble(
        Model(..model, pending: PendingShared(..model.pending, hat: Some(set))),
      )
    EnsuredHat(Error(reason)) -> #(ensure_failed(model, reason), effect.none())

    EnsuredClap(Ok(set)) ->
      assemble(
        Model(..model, pending: PendingShared(..model.pending, clap: Some(set))),
      )
    EnsuredClap(Error(reason)) -> #(ensure_failed(model, reason), effect.none())

    EnsuredSettings(Ok(pact)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, settings: Some(pact)),
        ),
      )
    EnsuredSettings(Error(reason)) -> #(
      ensure_failed(model, reason),
      effect.none(),
    )

    SharedChanged -> #(snapshot(model), effect.none())

    StepClicked(track_index, step) -> {
      let model = Model(..model, cursor: #(track_index, step))
      toggle_at(model, track_index, step)
      #(snapshot(model), effect.none())
    }

    KeyPressed(key) -> handle_key(model, key)

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(model, watershed_lustre.force_reconnect(doc))
        None -> #(model, effect.none())
      }
  }
}

fn ensure_failed(model: Model, reason: String) -> Model {
  Model(..model, error: Some(reason))
}

/// Arrow keys move the cursor; space or enter toggles the step under it. The
/// grid is one tab stop, so this is the whole keyboard surface.
fn handle_key(model: Model, key: String) -> #(Model, Effect(Msg)) {
  let #(track_index, step) = model.cursor
  case key {
    "ArrowLeft" -> #(
      Model(..model, cursor: #(track_index, wrap(step - 1, step_count))),
      effect.none(),
    )
    "ArrowRight" -> #(
      Model(..model, cursor: #(track_index, wrap(step + 1, step_count))),
      effect.none(),
    )
    "ArrowUp" -> #(
      Model(..model, cursor: #(wrap(track_index - 1, 4), step)),
      effect.none(),
    )
    "ArrowDown" -> #(
      Model(..model, cursor: #(wrap(track_index + 1, 4), step)),
      effect.none(),
    )
    " " | "Enter" -> {
      toggle_at(model, track_index, step)
      #(snapshot(model), effect.none())
    }
    _ -> #(model, effect.none())
  }
}

fn wrap(value: Int, modulus: Int) -> Int {
  case value < 0 {
    True -> modulus - 1
    False ->
      case value >= modulus {
        True -> 0
        False -> value
      }
  }
}

/// Toggle one step. `or_set_contains` reads the optimistic local state, so the
/// toggle is decided against what the user can currently see.
fn toggle_at(model: Model, track_index: Int, step: Int) -> Nil {
  case model.shared, track_at(track_index) {
    Some(shared), Some(track) -> {
      let set = track_set(shared, track)
      let key = int.to_string(step)
      case watershed_js.or_set_contains(set, key) {
        True -> watershed_js.or_set_remove(set, key)
        False -> watershed_js.or_set_add(set, key)
      }
    }
    _, _ -> Nil
  }
}

fn track_at(index: Int) -> Option(Track) {
  case list.drop(tracks(), index) {
    [track, ..] -> Some(track)
    [] -> None
  }
}

/// Re-read optimistic shared state into the model for rendering.
fn snapshot(model: Model) -> Model {
  case model.shared {
    Some(shared) ->
      Model(
        ..model,
        pattern: Pattern(
          kick: watershed_js.or_set_values(shared.kick),
          snare: watershed_js.or_set_values(shared.snare),
          hat: watershed_js.or_set_values(shared.hat),
          clap: watershed_js.or_set_values(shared.clap),
        ),
      )
    None -> model
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.div([class("machine")], [
    html.h1([], [html.text("Collaborative drum machine")]),
    status_view(model),
    grid(model),
    toolbar(model),
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

fn toolbar(model: Model) -> Element(Msg) {
  html.div([class("toolbar")], [
    html.span([class("hint")], [
      html.text("Arrow keys move, space toggles."),
    ]),
    html.button([event.on_click(ReconnectClicked)], [
      html.text("Force reconnect"),
    ]),
    html.text(case model.shared {
      Some(_) -> ""
      None -> " · loading pattern…"
    }),
  ])
}

fn grid(model: Model) -> Element(Msg) {
  html.div(
    [
      class("grid"),
      role("grid"),
      tabindex(0),
      aria_label("Drum machine pattern, 4 tracks by 16 steps"),
      event.on_keydown(KeyPressed),
    ],
    tracks()
      |> list.index_map(fn(track, track_index) {
        track_row(model, track, track_index)
      }),
  )
}

fn track_row(model: Model, track: Track, track_index: Int) -> Element(Msg) {
  html.div([class("row"), role("row")], [
    html.span([class("track-name")], [html.text(track_name(track))]),
    ..range(0, step_count)
    |> list.map(fn(step) { step_view(model, track, track_index, step) })
  ])
}

fn step_view(
  model: Model,
  track: Track,
  track_index: Int,
  step: Int,
) -> Element(Msg) {
  let on = list.contains(track_steps(model.pattern, track), int.to_string(step))
  let focused = model.cursor == #(track_index, step)
  // Every fourth step starts a beat — the standard 808 grouping, and the only
  // way a 16-step row stays readable.
  let downbeat = step % 4 == 0

  html.button(
    [
      classes([
        #("step", True),
        #("on", on),
        #("focused", focused),
        #("downbeat", downbeat),
      ]),
      role("gridcell"),
      aria_pressed(bool_string(on)),
      aria_label(
        track_name(track)
        <> " step "
        <> int.to_string(step + 1)
        <> case on {
          True -> ", on"
          False -> ", off"
        },
      ),
      event.on_click(StepClicked(track_index, step)),
    ],
    [],
  )
}

/// `from` up to but excluding `to`. `gleam/list` has no `range`, and the
/// sibling examples carry this same three-line helper.
fn range(from: Int, to: Int) -> List(Int) {
  int.range(from: from, to: to, with: [], run: fn(acc, i) { [i, ..acc] })
  |> list.reverse
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) -> html.p([class("error")], [html.text(reason)])
    None -> html.text("")
  }
}

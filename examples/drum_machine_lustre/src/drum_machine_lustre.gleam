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

import gleam/dynamic/decode
import gleam/int
import gleam/javascript/array.{type Array}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute.{
  aria_label, aria_pressed, class, classes, id, role, tabindex, type_, value,
}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import audio
import doc_schema
import watershed/client_id
import watershed/pact_map_kernel
import watershed_js.{type Document, type OrSet, type PactMap}
import watershed_lustre

// ── Dev config for the floodgate dev server (`just integration-up`) ──────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "drum-machine"

/// Steps per bar. Sixteen 16th notes, the TR-808 grid everyone already knows.
const step_count = 16

/// The tempo before anyone has agreed one. Also the floor and ceiling of the
/// slider — 40–240 is the range the engine clamps to.
const default_bpm = 120

const min_bpm = 40

const max_bpm = 240

/// The single key in the quorum-gated settings pact.
const bpm_key = "bpm"

/// How often to re-read a pending proposal's signoff list. The kernel emits an
/// event when a pact goes pending and when it is accepted, but nothing in
/// between, so watching the list drain means asking.
const signoff_poll_ms = 250

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

/// A tempo change the room has not finished agreeing to.
///
/// `PactMap` freezes a signoff list from the connected roster the moment a
/// proposal is sequenced, and the value is not accepted until every client on
/// that list has acknowledged it — or has left the room. `waiting` is what is
/// left of that list; `quorum` is how long it was when the proposal landed, so
/// the UI can say "1 of 3" instead of a bare count with no denominator.
///
/// Nothing here is a vote. `pact_map_kernel` emits `OweAccept` and the runtime
/// auto-submits it: signing off means "this client has seen the proposal", not
/// "this client agrees". The UI must never render an agree/reject affordance,
/// because there is nothing behind it.
type Proposal {
  Proposal(bpm: Int, waiting: List(Int), quorum: Int)
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
    /// The Web Audio scheduler. Constructed once at `init` and mutated in
    /// place from then on — an `AudioContext` is not created until the user
    /// gesture that resumes it, so holding this costs nothing before then.
    engine: audio.Engine,
    /// Whether the `AudioContext` is running. Until it is, the app is silent
    /// and says so; browsers refuse to start audio without a user gesture.
    audio_ready: Bool,
    playing: Bool,
    /// The tempo the sequencer is running at: the *accepted* value of the
    /// `"bpm"` pact, or `default_bpm` until the room has agreed one.
    bpm: Int,
    /// Where the slider currently sits. Diverges from `bpm` while the user is
    /// dragging, and while a proposal is in flight.
    bpm_draft: Int,
    /// The tempo proposal the room is currently signing off on, if any.
    proposal: Option(Proposal),
    /// True between calling `pact_map_set` and learning what the room made of
    /// it. `pact_map_set` is consensus, not optimistic: nothing is pending
    /// until the server sequences the proposal, and for that one round trip
    /// the app knows a proposal is in flight and the kernel does not. Without
    /// this the slider stays live in that window, and a second drag would be
    /// dropped by `apply_set` with nothing on screen to explain why.
    proposing: Bool,
    /// Local listener preferences, deliberately *not* in the document: muting
    /// a track is a choice about your own speakers, and putting it in the
    /// document would mean one person muting the room.
    muted: List(Int),
    volume: Int,
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
  EnableAudioClicked
  AudioResumed(Bool)
  TransportToggled
  BpmDrafted(String)
  BpmCommitted
  MuteToggled(Int)
  VolumeChanged(String)
  SettingsChanged(pact_map_kernel.PactMapEvent)
  PollSignoffs
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let engine = audio.create()
  let model =
    Model(
      status: Connecting,
      doc: None,
      shared: None,
      pending: PendingShared(None, None, None, None, None),
      user_id: user_id,
      pattern: empty_pattern(),
      cursor: #(0, 0),
      engine: engine,
      audio_ready: False,
      playing: False,
      bpm: default_bpm,
      bpm_draft: default_bpm,
      proposal: None,
      proposing: False,
      muted: [],
      volume: 80,
      error: None,
    )
  #(
    model,
    effect.batch([
      watershed_lustre.connect_dev(
        url: socket_url,
        tenant: tenant,
        secret: tenant_secret,
        document: document_id,
        user_id: user_id,
        got_document: GotHandle,
        connected: Connected,
      ),
      // Safe to start before `#playhead` is in the DOM: the loop looks the
      // element up every frame and no-ops until it appears.
      audio.start_playhead(engine),
    ]),
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
      let model = Model(..model, shared: Some(shared), error: None)
      // Adopt whatever tempo the room already agreed before we arrived, and
      // pick up a proposal that was already in flight when we joined.
      let #(model, poll) = read_tempo(model, shared)
      #(snapshot(model), effect.batch([subscribe_shared_effect(shared), poll]))
    }
    _, _ -> #(model, effect.none())
  }
}

/// The narrowed per-kind subscriptions as one batch. A 4×16 grid is cheap
/// enough that every handler just re-reads the whole pattern.
///
/// The `PactMap` subscription is the one that is not optional: `WentPending`
/// and `WentAccepted` *are* the consensus protocol, and without them a client
/// can propose and read but never learn that a peer's proposal landed.
fn subscribe_shared_effect(shared: SharedState) -> Effect(Msg) {
  effect.batch([
    watershed_lustre.subscribe_or_set(shared.kick, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_or_set(shared.snare, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_or_set(shared.hat, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_or_set(shared.clap, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_pact_map(shared.settings, SettingsChanged),
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

    EnableAudioClicked -> #(model, audio.resume(model.engine, AudioResumed))

    AudioResumed(True) -> {
      // Push the current tempo, volume, mutes, and pattern into an engine that
      // only now has an `AudioContext` to apply them to.
      audio.set_bpm(model.engine, model.bpm)
      audio.set_volume(model.engine, model.volume)
      push_mutes(model)
      push_pattern(model.engine, model.pattern)
      #(Model(..model, audio_ready: True), effect.none())
    }

    AudioResumed(False) -> #(
      Model(
        ..model,
        audio_ready: False,
        error: Some("This browser would not start an AudioContext."),
      ),
      effect.none(),
    )

    TransportToggled -> {
      let playing = !model.playing
      case playing {
        True -> audio.start(model.engine)
        False -> audio.stop(model.engine)
      }
      #(Model(..model, playing: playing), effect.none())
    }

    BpmDrafted(raw) -> #(
      Model(..model, bpm_draft: parse_bpm(raw, model.bpm_draft)),
      effect.none(),
    )

    // Propose on release, never per pointer move. A `pact_map_set` per frame
    // would flood the protocol with proposals that invalidate each other —
    // `apply_set` rejects a proposal made while one is pending — so a dragged
    // slider would land on whichever frame happened to arrive between pacts.
    BpmCommitted ->
      case model.shared, tempo_locked(model), model.bpm_draft == model.bpm {
        Some(shared), False, False -> {
          watershed_js.pact_map_set(
            shared.settings,
            bpm_key,
            json.int(model.bpm_draft),
          )
          // Poll rather than wait for an event, because a proposal the kernel
          // *rejects* — one made while a peer's is already pending — emits
          // nothing at all. Without this tick the control would stay disabled
          // forever on a rejection.
          #(
            Model(..model, proposing: True),
            watershed_lustre.after(signoff_poll_ms, PollSignoffs),
          )
        }
        _, _, _ -> #(model, effect.none())
      }

    // `WentPending` and `WentAccepted` are the only two transitions the kernel
    // reports, and both mean the same thing here: re-read the pact.
    SettingsChanged(_event) ->
      case model.shared {
        Some(shared) -> read_tempo(model, shared)
        None -> #(model, effect.none())
      }

    PollSignoffs ->
      case model.shared {
        Some(shared) -> read_tempo(model, shared)
        None -> #(model, effect.none())
      }

    MuteToggled(track_index) -> {
      let muted = case list.contains(model.muted, track_index) {
        True -> list.filter(model.muted, fn(i) { i != track_index })
        False -> [track_index, ..model.muted]
      }
      let model = Model(..model, muted: muted)
      push_mutes(model)
      #(model, effect.none())
    }

    VolumeChanged(raw) -> {
      let volume = parse_bpm(raw, model.volume)
      audio.set_volume(model.engine, volume)
      #(Model(..model, volume: volume), effect.none())
    }
  }
}

/// Re-read the `"bpm"` pact: the accepted tempo, and the proposal still being
/// signed off, if any.
///
/// Returns a poll timer alongside the model because the kernel reports only the
/// two ends of the protocol. A signoff list draining from three names to two
/// emits nothing — `apply_accept` only produces an event when the list empties
/// — so a UI that says *who* it is waiting on has to look. The poll is armed
/// only while something is pending and stops as soon as it is not.
fn read_tempo(model: Model, shared: SharedState) -> #(Model, Effect(Msg)) {
  let accepted =
    watershed_js.pact_map_get(shared.settings, bpm_key)
    |> option.then(decode_bpm)
    |> option.unwrap(default_bpm)

  let proposal =
    watershed_js.pact_map_pending(shared.settings, bpm_key)
    |> option.then(fn(pending: pact_map_kernel.Pending) {
      case pending.value |> option.then(decode_bpm) {
        Some(bpm) ->
          Some(Proposal(
            bpm: bpm,
            waiting: pending.expected_signoffs,
            // The quorum is the list at its longest. Once it starts draining
            // the original size is unrecoverable, so hold on to the widest
            // reading we have seen for this proposal.
            quorum: quorum_of(model.proposal, bpm, pending.expected_signoffs),
          ))
        None -> None
      }
    })

  case accepted != model.bpm {
    True -> audio.set_bpm(model.engine, accepted)
    False -> Nil
  }

  let model =
    Model(
      ..model,
      bpm: accepted,
      proposal: proposal,
      // Whatever the pact says now is the answer to any proposal of ours that
      // was in flight — including "the kernel rejected it", which arrives as
      // silence and leaves nothing pending.
      proposing: False,
      bpm_draft: case proposal {
        // While a proposal is in flight the slider shows it, so the ghost
        // value and the handle agree; otherwise it tracks the live tempo.
        Some(p) -> p.bpm
        None -> accepted
      },
    )

  #(model, case proposal {
    Some(_) -> watershed_lustre.after(signoff_poll_ms, PollSignoffs)
    None -> effect.none()
  })
}

/// A signoff list holds the integer ids the kernels tie-break on, derived from
/// the server's client id strings — for floodgate ids that is a stable hash,
/// so it is a long opaque number rather than anything a reader recognises.
///
/// The one entry a reader *can* place is their own, and it is the one that
/// changes what they do: "the room is waiting on you" is actionable, "the room
/// is waiting on client 274880073" is trivia. `watershed_js.client_id` plus
/// `client_id.to_int` is the same derivation the runtime and the kernels use,
/// so the comparison is exact rather than a guess.
///
/// Re-read per render rather than cached in the model: a reconnect can assign
/// a different id, and a stale one would quietly stop matching — the roster
/// would simply never say "you" again, which reads as a rendering bug.
fn client_label(model: Model, id: Int) -> String {
  case own_client_id(model) == Some(id) {
    True -> "you"
    False -> "client " <> int.to_string(id)
  }
}

fn own_client_id(model: Model) -> Option(Int) {
  model.doc
  |> option.then(watershed_js.client_id)
  |> option.map(client_id.to_int)
}

/// Whether the tempo control should refuse a new proposal: one is pending, or
/// one of ours is in flight and we have not yet learned its fate.
fn tempo_locked(model: Model) -> Bool {
  model.proposing || option.is_some(model.proposal)
}

fn quorum_of(previous: Option(Proposal), bpm: Int, waiting: List(Int)) -> Int {
  let seen = list.length(waiting)
  case previous {
    Some(p) if p.bpm == bpm -> int.max(p.quorum, seen)
    _ -> seen
  }
}

fn decode_bpm(value: Json) -> Option(Int) {
  case json.parse(json.to_string(value), decode.int) {
    Ok(bpm) -> Some(bpm)
    Error(_) -> None
  }
}

/// A slider's `value` arrives as a string. A malformed one keeps the previous
/// setting rather than snapping the tempo to zero.
fn parse_bpm(raw: String, fallback: Int) -> Int {
  case int.parse(raw) {
    Ok(value) -> value
    Error(_) -> fallback
  }
}

fn push_mutes(model: Model) -> Nil {
  let _ =
    tracks()
    |> list.index_map(fn(_track, index) {
      audio.set_mute(model.engine, index, list.contains(model.muted, index))
    })
  Nil
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

/// Re-read optimistic shared state into the model for rendering, and refresh
/// the snapshot the audio scheduler reads.
///
/// This is the only place the two halves of the app meet. The scheduler never
/// reaches back into watershed; it reads a plain array that this function
/// overwrites whenever a channel event lands, so document latency can never
/// show up as an audio glitch.
fn snapshot(model: Model) -> Model {
  case model.shared {
    Some(shared) -> {
      let pattern =
        Pattern(
          kick: watershed_js.or_set_values(shared.kick),
          snare: watershed_js.or_set_values(shared.snare),
          hat: watershed_js.or_set_values(shared.hat),
          clap: watershed_js.or_set_values(shared.clap),
        )
      push_pattern(model.engine, pattern)
      Model(..model, pattern: pattern)
    }
    None -> model
  }
}

fn push_pattern(engine: audio.Engine, pattern: Pattern) -> Nil {
  let _ =
    tracks()
    |> list.index_map(fn(track, index) {
      audio.set_track(engine, index, steps_array(track_steps(pattern, track)))
    })
  Nil
}

/// OR-set elements are step indices as decimal strings. Anything that is not
/// one is dropped rather than guessed at — a peer running a future version of
/// this demo could legitimately be storing something else.
fn steps_array(steps: List(String)) -> Array(Int) {
  steps
  |> list.filter_map(int.parse)
  |> array.from_list
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.div([class("machine")], [
    html.h1([], [html.text("Collaborative drum machine")]),
    status_view(model),
    audio_gate(model),
    playhead(),
    grid(model),
    transport(model),
    mixer(model),
    phase_caveat(),
    toolbar(model),
    error_view(model.error),
  ])
}

/// Browsers will not start an `AudioContext` without a user gesture, so the
/// app is silent until this is clicked. A silent demo with no explanation
/// reads as broken, which is the failure this banner exists to prevent.
///
/// It is a banner rather than a modal scrim on purpose: the grid is fully
/// usable — and worth using in two tabs — before anyone turns the sound on,
/// and a scrim would take the keyboard grid away to prevent nothing.
fn audio_gate(model: Model) -> Element(Msg) {
  case model.audio_ready {
    True -> html.text("")
    False ->
      html.div([class("gate")], [
        html.button([event.on_click(EnableAudioClicked)], [
          html.text("Enable audio"),
        ]),
        html.span([class("hint")], [
          html.text(
            "Your browser blocks sound until you interact with the page. "
            <> "The grid works without it.",
          ),
        ]),
      ])
  }
}

/// Rendered empty, and it must stay empty: `audio_ffi.mjs` builds and owns the
/// cells inside it, and drives them from `requestAnimationFrame`. Lustre has
/// no children here to diff, so it never patches the subtree out from under
/// the animation. A playhead dispatched as a message per step would be ~9 full
/// grid diffs a second at 140 BPM for a highlight that moves two elements.
fn playhead() -> Element(Msg) {
  html.div([class("playhead"), id("playhead")], [])
}

fn transport(model: Model) -> Element(Msg) {
  html.div([class("transport")], [
    html.button(
      [
        event.on_click(TransportToggled),
        attribute.disabled(!model.audio_ready),
        aria_pressed(bool_string(model.playing)),
      ],
      [
        html.text(case model.playing {
          True -> "Stop"
          False -> "Play"
        }),
      ],
    ),
    tempo_view(model),
  ])
}

/// The one control in this app that is *not* uncoordinated.
///
/// Everything you can hear — every step on every track — is a fast, add-wins
/// edit that nobody has to agree to. Tempo is the exception, because it is the
/// one setting where two people dragging in opposite directions makes the room
/// lurch. So it lives on a `PactMap`: a change is proposed, the room signs off,
/// and only then does the sequencer follow it. The contrast is the demo.
fn tempo_view(model: Model) -> Element(Msg) {
  let pending = tempo_locked(model)
  html.div([class("tempo-block")], [
    html.label([class("tempo")], [
      html.span([], [html.text("Tempo")]),
      html.input([
        type_("range"),
        attribute.min(int.to_string(min_bpm)),
        attribute.max(int.to_string(max_bpm)),
        attribute.step("1"),
        value(int.to_string(model.bpm_draft)),
        // A second proposal while one is in flight is rejected by the kernel,
        // so the control says so rather than silently dropping the drag.
        attribute.disabled(pending),
        aria_label("Tempo in beats per minute"),
        event.on_input(BpmDrafted),
        event.on_change(fn(_raw) { BpmCommitted }),
      ]),
      html.span([classes([#("bpm", True), #("ghost", pending)])], [
        html.text(int.to_string(model.bpm_draft) <> " BPM"),
      ]),
    ]),
    proposal_view(model),
  ])
}

fn proposal_view(model: Model) -> Element(Msg) {
  case model.proposal {
    None -> html.text("")
    Some(proposal) -> {
      let remaining = list.length(proposal.waiting)
      html.p([class("proposal"), role("status")], [
        html.text(
          int.to_string(proposal.bpm)
          <> " BPM pending — waiting on "
          <> int.to_string(remaining)
          <> " of "
          <> int.to_string(proposal.quorum)
          // The noun agrees with the room, not with what is left of it:
          // "waiting on 1 of 3 clients", never "1 of 3 client".
          <> case proposal.quorum {
            1 -> " client"
            _ -> " clients"
          },
        ),
        html.span([class("signoffs")], [
          html.text(
            " · "
            <> case proposal.waiting {
              [] -> "settling"
              ids ->
                "not yet acknowledged: "
                <> string.join(
                  list.map(ids, fn(id) { client_label(model, id) }),
                  ", ",
                )
            },
          ),
        ]),
        // Said out loud because the obvious reading of a pending bar is a vote,
        // and it is not one. Nobody is deciding; the runtime auto-submits each
        // client's acknowledgement the moment it sees the proposal.
        html.span([class("hint")], [
          html.text(
            " Signing off means a client has seen the change, not that it "
            <> "agreed to it — there is nothing to agree to and no way to "
            <> "refuse.",
          ),
        ]),
      ])
    }
  }
}

/// Mute and volume are per-client and never leave the browser. They are
/// listener preferences, not shared composition state.
fn mixer(model: Model) -> Element(Msg) {
  html.div([class("mixer")], [
    html.span([class("hint")], [html.text("Local mix")]),
    ..list.append(
      tracks()
        |> list.index_map(fn(track, index) {
          let muted = list.contains(model.muted, index)
          html.button(
            [
              classes([#("mute", True), #("muted", muted)]),
              aria_pressed(bool_string(muted)),
              aria_label("Mute " <> track_name(track)),
              event.on_click(MuteToggled(index)),
            ],
            [html.text(track_name(track))],
          )
        }),
      [
        html.label([class("volume")], [
          html.span([], [html.text("Volume")]),
          html.input([
            type_("range"),
            attribute.min("0"),
            attribute.max("100"),
            value(int.to_string(model.volume)),
            aria_label("Output volume"),
            event.on_input(VolumeChanged),
          ]),
        ]),
      ],
    )
  ])
}

/// The limitation that has to be stated rather than hidden: watershed
/// converges *state*, not *time*. Two browsers holding the same pattern at the
/// same tempo still run their loops out of phase, because their audio clocks
/// started at different moments, and nothing in a CRDT fixes that.
fn phase_caveat() -> Element(Msg) {
  html.p([class("caveat")], [
    html.text(
      "Each client runs its own clock: the pattern and the tempo converge, "
      <> "the phase does not. Two tabs play the same loop, not the same beat.",
    ),
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

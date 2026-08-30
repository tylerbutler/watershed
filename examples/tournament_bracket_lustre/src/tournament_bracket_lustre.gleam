//// Collaborative single-elimination tournament bracket — `RegisterCollection`.
////
//// Every other example either has no arbitration story (`OrMap`, `GSet`),
//// arbitrates by quorum (`PactMap`), or arbitrates by ordering
//// (`OrderedCollection`). `RegisterCollection` is the one kind whose entire
//// reason to exist is **linearizable CAS per key with retained history of
//// losers** — the atomic slot only advances to a write that knew the current
//// atomic version, and every sequenced write is kept as a version even when
//// it loses (`src/watershed/register_collection_kernel.gleam:1-6`).
////
//// The document has one channel: `matches`, a register per bracket match
//// (`bracket.gleam`), keyed `"r1m1"` .. `"r3m1"`. Anyone connected can report
//// any match — there is no referee assignment, no `Claims` lock. That is
//// deliberate: the CAS is the coordination, not an app-level permission
//// check. Reporting the *same* match from two tabs with two different
//// results and watching both converge on the same official winner, with the
//// loser's submission still visible in the version log, is the demo's
//// payoff moment.
////
//// Reads use the `Atomic` policy (the linearizable winner) — `Lww` would
//// make this indistinguishable from an `OrMap` register.
////
//// Writes are **non-optimistic**: a submitted result does not appear as the
//// official winner until its `AtomicChanged` event arrives, unlike every
//// other example here (`register_collection_kernel`'s docstring: "local
//// writes are not visible until their op sequences"). The UI shows a
//// "submitted…" state for the gap rather than assuming the write already won.
////
//// Open two browser tabs against the same `?document=` to watch the bracket
//// converge (server via `just integration-up`).

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document, type RegisterCollection}
import watershed/browser
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed/register_collection_kernel.{
  type RegisterEvent, AtomicChanged, VersionChanged,
}
import watershed_lustre

import tournament_bracket_lustre/bracket.{
  type MatchId, type MatchResult, type Slot, MatchResult,
}
import tournament_bracket_lustre/doc_schema

// ── Dev config for `just integration-up` (levee/floodgate dev mode) ──────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("bracket")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// ── Presence payload ─────────────────────────────────────────────────────────

/// Static per tab, announced once at start — just enough for a "who's here"
/// roster. No per-match claim tracking: reporting is unrestricted by design.
pub type BracketPresence {
  BracketPresence(color: String, name: String)
}

fn encode_presence(p: BracketPresence) -> json.Json {
  json.object([
    #("color", json.string(p.color)),
    #("name", json.string(p.name)),
  ])
}

fn presence_decoder() -> decode.Decoder(BracketPresence) {
  use color <- decode.field("color", decode.string)
  use name <- decode.field("name", decode.string)
  decode.success(BracketPresence(color:, name:))
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(String)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(BracketDoc)),
    matches: Option(RegisterCollection),
    /// The `Atomic` (official) result per match key, once reported.
    results: Dict(String, MatchResult),
    /// Every sequenced value per match key, oldest first — including
    /// concurrent losers that the atomic slot never adopted. This is what
    /// makes retained-but-superseded writes visible rather than silently
    /// discarded.
    versions: Dict(String, List(MatchResult)),
    /// Match keys with a write submitted locally but not yet confirmed by an
    /// `AtomicChanged`/`VersionChanged` event — the non-optimistic gap.
    pending: Set(String),
    /// Score text field per match key, cleared once a report is submitted.
    score_drafts: Dict(String, String),
    user_id: String,
    color: String,
    presence: Option(Handle(BracketPresence)),
    peers: List(presence.PresenceEntry(BracketPresence)),
    last_error: Option(String),
    log: List(String),
  )
}

type Msg {
  GotHandle(Document(BracketDoc))
  Connected(Result(Nil, String))
  EnsuredMatches(Result(RegisterCollection, String))
  MatchesChanged(RegisterEvent)
  ScoreDraftChanged(String, String)
  ReportClicked(match_key: String, winner: String)
  PresenceStarted(Handle(BracketPresence))
  PresenceEvent(presence.Event(BracketPresence))
  ReconnectClicked
}

/// The root document's phantom schema type lives in `doc_schema`, but this
/// module only ever holds one channel field off it, so a local alias keeps
/// every signature below from spelling out the import.
type BracketDoc =
  doc_schema.BracketDoc

fn init(document: String) -> #(Model, Effect(Msg)) {
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      matches: None,
      results: dict.new(),
      versions: dict.new(),
      pending: set.new(),
      score_drafts: dict.new(),
      user_id: user_id,
      color: presence.color_for(user_id),
      presence: None,
      peers: [],
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

/// Bootstrap the one channel this document needs. Unlike the other examples,
/// there is nothing to seed: an empty register collection *is* the correct
/// starting state — no match has a result until someone reports one.
fn bootstrap_effect(doc: Document(BracketDoc)) -> Effect(Msg) {
  let root = watershed.root_typed(doc)
  watershed_lustre.ensure_register_collection(
    doc,
    root,
    doc_schema.matches(),
    EnsuredMatches,
  )
}

fn subscribe_matches_effect(matches: RegisterCollection) -> Effect(Msg) {
  watershed_lustre.subscribe_register_collection(matches, MatchesChanged)
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotHandle(doc) -> {
      let model =
        Model(..model, doc: Some(doc)) |> log_line("document handle acquired")
      let presence_start =
        watershed_lustre.presence(
          document: doc,
          config: presence.config(encode_presence, presence_decoder()),
          initial: BracketPresence(
            color: model.color,
            name: presence.short_name(model.user_id),
          ),
          started: PresenceStarted,
          on_event: PresenceEvent,
        )
      case model.status, model.matches {
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
      case model.doc, model.matches {
        Some(doc), None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }
    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), last_error: Some(reason))
        |> log_line("connection failed · " <> reason),
      effect.none(),
    )

    EnsuredMatches(Ok(matches)) -> {
      let model =
        Model(..model, matches: Some(matches))
        |> log_line("matches channel ready")
      #(model, subscribe_matches_effect(matches))
    }
    EnsuredMatches(Error(reason)) -> #(
      Model(..model, last_error: Some("could not ensure matches: " <> reason))
        |> log_line("matches channel failed · " <> reason),
      effect.none(),
    )

    MatchesChanged(event) -> #(
      apply_register_event(model, event),
      effect.none(),
    )

    ScoreDraftChanged(key, text) -> #(
      Model(..model, score_drafts: dict.insert(model.score_drafts, key, text)),
      effect.none(),
    )

    ReportClicked(match_key, winner) ->
      case model.matches {
        None -> #(model, effect.none())
        Some(matches) -> {
          let score =
            dict.get(model.score_drafts, match_key)
            |> option.from_result
            |> option.unwrap("")
          let value = bracket.to_json(MatchResult(winner:, score:))
          watershed.register_write(matches, match_key, value)
          #(
            Model(..model, pending: set.insert(model.pending, match_key))
              |> log_line(
                match_key <> " submitted: " <> winner <> " (" <> score <> ")",
              ),
            effect.none(),
          )
        }
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

/// `VersionChanged` fires for every sequenced write (winners and losers) and
/// is the sole source for the version log; `AtomicChanged` fires only for the
/// write that won the CAS and is the sole source for `results`. A winning
/// write emits both events with the same key/value, so `results` never
/// double-updates and `versions` never double-appends.
fn apply_register_event(model: Model, event: RegisterEvent) -> Model {
  case event {
    AtomicChanged(key, value, _local) -> {
      let result = bracket.from_json(value)
      Model(
        ..model,
        results: dict.insert(model.results, key, result),
        pending: set.delete(model.pending, key),
      )
      |> log_line(key <> " official result: " <> result.winner)
    }
    VersionChanged(key, value, _local) -> {
      let result = bracket.from_json(value)
      let existing = dict.get(model.versions, key) |> option.from_result
      let updated = case existing {
        Some(existing_versions) -> list.append(existing_versions, [result])
        None -> [result]
      }
      Model(
        ..model,
        versions: dict.insert(model.versions, key, updated),
        pending: set.delete(model.pending, key),
      )
    }
  }
}

/// Everyone but this tab — presence state includes the local session, so the
/// roster is filtered here rather than in the driver.
fn remote_peers(
  model: Model,
  entries: List(presence.PresenceEntry(BracketPresence)),
) -> List(presence.PresenceEntry(BracketPresence)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

fn log_line(model: Model, line: String) -> Model {
  Model(..model, log: list.take([line, ..model.log], 40))
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("wrap")], [
    html.div([attribute.class("bracket-header")], [
      html.h1([], [html.text("Tournament bracket")]),
      html.p([attribute.class("status")], [
        html.text(status_to_string(model.status)),
      ]),
      roster_view(model),
    ]),
    error_view(model),
    champion_view(model),
    html.div(
      [attribute.class("rounds")],
      list.map(
        [
          #(bracket.Quarterfinal, bracket.quarterfinals),
          #(bracket.Semifinal, bracket.semifinals),
          #(bracket.Final, [bracket.final]),
        ],
        fn(entry) {
          let #(round, ids) = entry
          round_view(model, round, ids)
        },
      ),
    ),
    diagnostics_view(model),
  ])
}

fn status_to_string(status: Status) -> String {
  case status {
    Connecting -> "connecting…"
    Ready -> "connected"
    Failed(reason) -> "connection failed: " <> reason
  }
}

fn error_view(model: Model) -> Element(Msg) {
  html.p([attribute.class("error")], [
    html.text(option.unwrap(model.last_error, "")),
  ])
}

fn champion_view(model: Model) -> Element(Msg) {
  case bracket.champion(model.results) {
    Ok(name) ->
      html.p([attribute.class("champion")], [html.text("🏆 Champion: " <> name)])
    Error(Nil) -> element.none()
  }
}

fn round_view(
  model: Model,
  round: bracket.Round,
  ids: List(MatchId),
) -> Element(Msg) {
  html.div([attribute.class("round")], [
    html.h2([], [html.text(bracket.round_label(round))]),
    html.div(
      [attribute.class("matches")],
      list.map(ids, fn(id) { match_view(model, id) }),
    ),
  ])
}

fn match_view(model: Model, id: MatchId) -> Element(Msg) {
  let key = bracket.match_key(id)
  let #(slot_a, slot_b) = bracket.slots_for(id, model.results)
  let is_pending = set.contains(model.pending, key)
  let card_body = case dict.get(model.results, key) {
    Ok(result) -> reported_view(model, key, result)
    Error(_) ->
      case is_pending {
        True -> pending_view(slot_a, slot_b)
        False ->
          case bracket.is_reportable(id, model.results) {
            True -> reportable_view(model, key, slot_a, slot_b)
            False -> undecided_view(slot_a, slot_b)
          }
      }
  }
  html.div([attribute.class("match"), attribute.attribute("data-match", key)], [
    html.p([attribute.class("match-id")], [html.text(key)]),
    card_body,
  ])
}

fn slot_row(slot: Slot) -> Element(Msg) {
  html.p([attribute.class("slot")], [html.text(bracket.slot_label(slot))])
}

fn undecided_view(slot_a: Slot, slot_b: Slot) -> Element(Msg) {
  html.div([attribute.class("slots")], [slot_row(slot_a), slot_row(slot_b)])
}

fn pending_view(slot_a: Slot, slot_b: Slot) -> Element(Msg) {
  html.div([attribute.class("slots pending")], [
    slot_row(slot_a),
    slot_row(slot_b),
    html.p([attribute.class("hint")], [
      html.text("submitted, awaiting confirmation…"),
    ]),
  ])
}

fn reportable_view(
  model: Model,
  key: String,
  slot_a: Slot,
  slot_b: Slot,
) -> Element(Msg) {
  let name_a = bracket.slot_label(slot_a)
  let name_b = bracket.slot_label(slot_b)
  let score =
    dict.get(model.score_drafts, key) |> option.from_result |> option.unwrap("")
  html.div([attribute.class("slots reportable")], [
    html.div([attribute.class("report-row")], [
      html.button([event.on_click(ReportClicked(key, name_a))], [
        html.text(name_a <> " wins"),
      ]),
      html.input([
        attribute.class("score-input"),
        attribute.placeholder("score, e.g. 3-1"),
        attribute.value(score),
        event.on_input(fn(text) { ScoreDraftChanged(key, text) }),
      ]),
      html.button([event.on_click(ReportClicked(key, name_b))], [
        html.text(name_b <> " wins"),
      ]),
    ]),
  ])
}

fn reported_view(
  model: Model,
  key: String,
  result: MatchResult,
) -> Element(Msg) {
  let also_reported =
    dict.get(model.versions, key)
    |> option.from_result
    |> option.unwrap([])
    |> list.filter(fn(version) { version != result })
  html.div([attribute.class("slots reported")], [
    html.p([attribute.class("winner")], [
      html.text(result.winner <> " — " <> result.score),
    ]),
    version_log_view(also_reported),
  ])
}

fn version_log_view(also_reported: List(MatchResult)) -> Element(Msg) {
  case also_reported {
    [] -> element.none()
    entries ->
      html.details([attribute.class("version-log")], [
        html.summary([], [
          html.text(
            int.to_string(list.length(entries)) <> " other report(s) received",
          ),
        ]),
        html.ul(
          [],
          list.map(entries, fn(entry) {
            html.li([], [html.text(entry.winner <> " — " <> entry.score)])
          }),
        ),
      ])
  }
}

fn roster_view(model: Model) -> Element(Msg) {
  let self_chip =
    chip(presence.short_name(model.user_id) <> " (you)", model.color)
  let peer_chips =
    model.peers |> list.map(fn(peer) { chip(peer.meta.name, peer.meta.color) })
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

fn diagnostics_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("diagnostics")], [
    html.h2([], [html.text("Diagnostics")]),
    html.p([], [
      html.text(
        "user " <> model.user_id <> " · reconnect to replay the summary",
      ),
    ]),
    html.button([event.on_click(ReconnectClicked)], [
      html.text("force reconnect"),
    ]),
    html.pre([attribute.class("diagnostic-log")], [
      html.text(string.join(list.reverse(model.log), "\n")),
    ]),
  ])
}

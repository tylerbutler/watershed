//// Erlang-target multi-player dice scoreboard, built on watershed's *typed*
//// map API (`watershed/schema` + `TypedMap`). Where `dice_cli` uses a single
//// key on the root map, this example exercises typed nested maps: the root
//// map holds plain typed values plus a typed handle to a *roster* map, and
//// every player owns a typed map with several fields of its own.
////
//// ```text
//// root ─┬─ "game"      = "watershed dice scores"   (Field(GameRoot, String))
////       ├─ "die_sides" = 6                          (Field(GameRoot, Int))
////       └─ "players"   = handle ──▶ roster          (ChildField(GameRoot, Roster))
////                                     └─ "player-1234" = handle ──▶ player map
////
//// player map ─┬─ "name" ─┬─ "last_roll" ─┬─ "total" ─┬─ "rolls"
//// ```
////
//// The schema (phantom tags `GameRoot`/`Roster`/`Player` plus field
//// definitions) makes reads and writes type-checked and removes the
//// `json.to_string` boilerplate the untyped API required; typed nested
//// handles (`set_child`/`resolve_child`) replace the manual
//// `handle_of`/`resolve` plumbing.
////
//// Run several instances against `just server` in the levee repo:
////
//// ```sh
//// gleam run          # each run joins as a new player and rolls periodically
//// ```

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import watershed/map_kernel.{type MapEvent, Cleared, ValueChanged}
import watershed/schema.{type ChildField, type Field}
import watershed_beam

// ── Schema ────────────────────────────────────────────────────────────────────
//
// Phantom tags (`GameRoot`/`Roster`/`Player`) are never constructed — they only
// scope `TypedMap`/`Field`/`Schema` to one map shape.
//
// The root map mixes plain typed fields with a child handle, so it uses
// individual `Field`s. A player map is record-shaped, so it uses a whole-map
// `Schema`: one decoder reads every key into a `PlayerState`, and one encoder
// writes it back per key. Gleam constants can't hold function calls, so each
// definition is a zero-argument function.

type GameRoot

type Roster

type Player

fn game() -> Field(GameRoot, String) {
  schema.field("game", json.string, decode.string)
}

fn die_sides() -> Field(GameRoot, Int) {
  schema.field("die_sides", json.int, decode.int)
}

fn players() -> ChildField(GameRoot, Roster) {
  schema.child_field("players")
}

/// A player's slot in the roster, keyed by player id.
fn player_slot(player_id: String) -> ChildField(Roster, Player) {
  schema.child_field(player_id)
}

/// One player's whole state, read/written as a single record.
type PlayerState {
  PlayerState(name: String, last_roll: Option(Int), total: Int, rolls: Int)
}

/// The player-map schema. `record4` derives the decoder *and* the per-key
/// encoder from a single prop list, so they can never drift; `sealed_known`
/// seals it to exactly those declared keys (no hand-repeated list); `versioned`
/// marks a version so a read can reject a mismatched stored version. One
/// declaration replaces the old decoder / encoder / seal-list trio.
fn player_schema() -> Result(schema.Schema(Player, PlayerState), Nil) {
  schema.record4(
    PlayerState,
    schema.prop(player_name(), fn(p: PlayerState) { p.name }),
    schema.optional_prop(player_last_roll(), fn(p: PlayerState) { p.last_roll }),
    schema.prop(player_total(), fn(p: PlayerState) { p.total }),
    schema.prop(player_rolls(), fn(p: PlayerState) { p.rolls }),
  )
  |> schema.versioned(1)
  |> schema.sealed_known
}

fn player_name() -> Field(Player, String) {
  schema.field("name", json.string, decode.string)
}

fn player_last_roll() -> Field(Player, Int) {
  schema.field("last_roll", json.int, decode.int)
}

fn player_total() -> Field(Player, Int) {
  schema.field("total", json.int, decode.int)
}

fn player_rolls() -> Field(Player, Int) {
  schema.field("rolls", json.int, decode.int)
}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

/// IPv4 loopback literal — do NOT use "localhost".  Erlang's inet resolver
/// stalls ~8 s on the AAAA lookup, long enough for levee to drop the socket.
const host = "127.0.0.1"

const port = 4000

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "dice-scores"

const face_count = 6

const first_roll_delay_milliseconds = 1000

const roll_interval_milliseconds = 5000

/// A handle read from a remote value can be transiently unresolvable while
/// the referenced channel's attach operation is still in flight, so resolves
/// retry.
const resolve_retry_milliseconds = 200

const resolve_attempts = 25

type Msg {
  /// The roster map changed: a player joined (or re-registered). Narrowed to
  /// `MapEvent` by `watershed_beam.subscribe` — no 14-variant channel union.
  RosterChanged(MapEvent)
  /// Some player's own map changed: a roll landed.
  ScoreChanged(MapEvent)
  RollDue
}

type State {
  State(
    document: watershed_beam.Document(GameRoot),
    my_id: String,
    me: watershed_beam.TypedMap(Player),
    roster: watershed_beam.TypedMap(Roster),
    /// Every player map we have resolved and subscribed to, by player id.
    known: Dict(String, watershed_beam.TypedMap(Player)),
    selector: process.Selector(Msg),
    roll_due: process.Subject(Nil),
    total: Int,
    rolls: Int,
  )
}

// ── Entry point ───────────────────────────────────────────────────────────────

pub fn main() -> Nil {
  let player_id = "player-" <> int.to_string(int.random(9000) + 1000)
  let token =
    watershed_beam.dev_token(
      secret: tenant_secret,
      tenant: tenant,
      document: document_id,
      user_id: player_id,
    )

  io.println(
    "Joining "
    <> document_id
    <> " on "
    <> host
    <> ":"
    <> int.to_string(port)
    <> " as "
    <> player_id
    <> "…",
  )

  case
    watershed_beam.connect(
      host: host,
      port: port,
      tenant: tenant,
      document: document_id,
      token: token,
      user_id: player_id,
    )
  {
    Error(reason) -> {
      io.println("Connection failed: " <> reason)
    }
    Ok(document) -> {
      case start(document, player_id) {
        Ok(Nil) -> Nil
        Error(reason) -> io.println("Setup failed: " <> reason)
      }
    }
  }
}

// ── Post-connect setup ────────────────────────────────────────────────────────

fn start(
  document: watershed_beam.Document(GameRoot),
  player_id: String,
) -> Result(Nil, String) {
  let root: watershed_beam.TypedMap(GameRoot) =
    watershed_beam.root_typed(document)

  // The root map carries plain typed values alongside the roster handle.
  case watershed_beam.get_field(root, game()) {
    Ok(Some(_)) -> Nil
    Ok(None) -> {
      watershed_beam.set_field(root, game(), "watershed dice scores")
      watershed_beam.set_field(root, die_sides(), face_count)
    }
    Error(_) -> {
      watershed_beam.set_field(root, game(), "watershed dice scores")
      watershed_beam.set_field(root, die_sides(), face_count)
    }
  }

  use roster <- result.try(ensure_roster(document, root))
  use me <- result.try(watershed_beam.create_typed_map(document))
  use schema <- result.try(
    player_schema() |> result.map_error(fn(_) { "Schema build failed" }),
  )

  // Our own player map: populated while detached (local-only), then
  // attached — snapshot and all — by storing its handle in the roster.
  // A single `write` fills every key; `stamp` records the schema version.
  watershed_beam.write(
    me,
    schema,
    PlayerState(name: player_id, last_roll: None, total: 0, rolls: 0),
  )
  watershed_beam.stamp(me, schema)
  watershed_beam.set_child(roster, player_slot(player_id), me)

  let roll_due = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select_map(watershed_beam.subscribe_typed(roster), RosterChanged)
    |> process.select_map(watershed_beam.subscribe_typed(me), ScoreChanged)
    |> process.select_map(roll_due, fn(_) { RollDue })

  let state =
    State(
      document: document,
      my_id: player_id,
      me: me,
      roster: roster,
      known: dict.from_list([#(player_id, me)]),
      selector: selector,
      roll_due: roll_due,
      total: 0,
      rolls: 0,
    )

  // Resolve and watch every player already registered in the roster.
  // `typed_children` resolves each roster handle to a typed player map in
  // one pass — the typed view of a dynamic (id-keyed) collection.
  let state =
    watershed_beam.typed_children(document, roster)
    |> list.fold(state, fn(state, child) {
      case child.1 {
        Ok(map) -> adopt_player(state, child.0, map)
        Error(_) -> state
      }
    })
  print_scoreboard(state)

  io.println(
    "Rolling every "
    <> int.to_string(roll_interval_milliseconds / 1000)
    <> "s; press Ctrl+C to stop.",
  )
  schedule_roll(roll_due, first_roll_delay_milliseconds)
  event_loop(state)

  Ok(Nil)
}

// ── Event loop ────────────────────────────────────────────────────────────────

fn event_loop(state: State) -> Nil {
  case process.selector_receive_forever(state.selector) {
    RollDue -> {
      let roll = int.random(face_count) + 1
      let new_total = state.total + roll
      let new_rolls = state.rolls + 1
      io.println("You rolled a " <> int.to_string(roll) <> ".")
      case player_schema() {
        Ok(schema) ->
          watershed_beam.write(
            state.me,
            schema,
            PlayerState(
              name: state.my_id,
              last_roll: Some(roll),
              total: new_total,
              rolls: new_rolls,
            ),
          )
        Error(_) -> Nil
      }
      let state = State(..state, total: new_total, rolls: new_rolls)
      print_scoreboard(state)
      schedule_roll(state.roll_due, roll_interval_milliseconds)
      event_loop(state)
    }
    RosterChanged(ValueChanged(key: player_id, ..)) -> {
      let new_state = watch_player(state, player_id)
      case dict.size(new_state.known) > dict.size(state.known) {
        True -> print_scoreboard(new_state)
        False -> Nil
      }
      event_loop(new_state)
    }
    RosterChanged(Cleared(..)) -> {
      event_loop(state)
    }
    ScoreChanged(event) -> {
      // A remote roll rewrites the player's keys ("name", "last_roll",
      // "total", "rolls" — in that order); reprint once, on the final write.
      // Local writes already print above.
      case event {
        ValueChanged(key: "rolls", local: False, ..) | Cleared(local: False) ->
          print_scoreboard(state)
        ValueChanged(..) | Cleared(..) -> Nil
      }
      event_loop(state)
    }
  }
}

// ── Roster handling ───────────────────────────────────────────────────────────

/// Resolve the shared roster map from the root, creating it on first join.
/// Concurrent first joins race on the `players` field; last write wins, so
/// after writing we wait for our operation to be sequenced and adopt whichever
/// handle the field holds.
fn ensure_roster(
  document: watershed_beam.Document(GameRoot),
  root: watershed_beam.TypedMap(GameRoot),
) -> Result(watershed_beam.TypedMap(Roster), String) {
  case resolve_child_retry(document, root, players(), resolve_attempts) {
    Ok(Some(roster)) -> Ok(roster)
    _ -> {
      case watershed_beam.create_typed_map(document) {
        Error(reason) -> Error("Roster map creation failed: " <> reason)
        Ok(created) -> {
          watershed_beam.set_child(root, players(), created)
          wait_synced(document)
          case
            resolve_child_retry(document, root, players(), resolve_attempts)
          {
            Ok(Some(roster)) -> Ok(roster)
            _ -> Error("Failed to resolve roster after creation")
          }
        }
      }
    }
  }
}

/// Resolve `player_id`'s map from the roster and add its events to the
/// selector. A no-operation for players we already watch (including ourselves).
fn watch_player(state: State, player_id: String) -> State {
  case dict.has_key(state.known, player_id) {
    True -> state
    False ->
      case
        resolve_child_retry(
          state.document,
          state.roster,
          player_slot(player_id),
          resolve_attempts,
        )
      {
        Error(reason) -> {
          io.println("Could not resolve " <> player_id <> ": " <> reason)
          state
        }
        Ok(None) -> state
        Ok(Some(map)) -> adopt_player(state, player_id, map)
      }
  }
}

/// Add a resolved player map to the watch set and event selector, printing a
/// join notice. Idempotent — a no-operation for a player we already know.
fn adopt_player(
  state: State,
  player_id: String,
  map: watershed_beam.TypedMap(Player),
) -> State {
  case dict.has_key(state.known, player_id) {
    True -> state
    False -> {
      io.println(player_id <> " joined the game.")
      let selector =
        process.select_map(
          state.selector,
          watershed_beam.subscribe_typed(map),
          ScoreChanged,
        )
      State(
        ..state,
        known: dict.insert(state.known, player_id, map),
        selector: selector,
      )
    }
  }
}

/// Resolve a child map, retrying transient not-yet-attached errors. `Ok(None)`
/// (the key is simply absent) is returned immediately, not retried.
fn resolve_child_retry(
  document: watershed_beam.Document(GameRoot),
  parent: watershed_beam.TypedMap(s),
  field: ChildField(s, c),
  attempts: Int,
) -> Result(Option(watershed_beam.TypedMap(c)), String) {
  case watershed_beam.resolve_child(document, parent, field) {
    Ok(value) -> Ok(value)
    Error(reason) ->
      case attempts <= 1 {
        True -> Error(reason)
        False -> {
          process.sleep(resolve_retry_milliseconds)
          resolve_child_retry(document, parent, field, attempts - 1)
        }
      }
  }
}

fn wait_synced(document: watershed_beam.Document(GameRoot)) -> Nil {
  case watershed_beam.is_synced(document) {
    True -> Nil
    False -> {
      process.sleep(100)
      wait_synced(document)
    }
  }
}

// ── Output ────────────────────────────────────────────────────────────────────

fn print_scoreboard(state: State) -> Nil {
  io.println("── Scoreboard ─────────────────────────")
  state.known
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.each(fn(entry) {
    let #(player_id, map) = entry
    let marker = case player_id == state.my_id {
      True -> " (you)"
      False -> ""
    }
    io.println("  " <> player_id <> marker <> "  " <> player_line(map))
  })
}

/// One player's stats, read from the map as a single typed record.
fn player_line(map: watershed_beam.TypedMap(Player)) -> String {
  case player_schema() {
    Error(_) -> "(schema error)"
    Ok(schema) ->
      case watershed_beam.read(map, schema) {
        Ok(player) ->
          "total="
          <> int.to_string(player.total)
          <> "  rolls="
          <> int.to_string(player.rolls)
          <> "  last="
          <> option.unwrap(option.map(player.last_roll, int.to_string), "-")
        Error(_) -> "(loading…)"
      }
  }
}

fn schedule_roll(
  roll_due: process.Subject(Nil),
  delay_milliseconds: Int,
) -> Nil {
  let _timer = process.send_after(roll_due, delay_milliseconds, Nil)
  Nil
}

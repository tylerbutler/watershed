//// Erlang-target multi-player dice scoreboard. Where `dice_cli` uses a
//// single key on the root map, this example exercises the nested-map API:
//// the root map holds plain values plus a handle to a *roster* map, and every
//// player owns a nested map with several keys of its own.
////
//// ```text
//// root ─┬─ "game"      = "watershed dice scores"
////       ├─ "die_sides" = 6
////       └─ "players"   = handle ──▶ roster ─┬─ "player-1234" = handle ──▶ map
////                                           └─ "player-5678" = handle ──▶ map
////
//// player map ─┬─ "name" ─┬─ "last_roll" ─┬─ "total" ─┬─ "rolls"
//// ```
////
//// Run several instances against `just server` in the levee repo:
////
//// ```sh
//// gleam run          # each run joins as a new player and rolls periodically
//// ```

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

import watershed
import watershed/channel.{type ChannelEvent}
import watershed/map_kernel.{Cleared, ValueChanged}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

/// IPv4 loopback literal — do NOT use "localhost".  Erlang's inet resolver
/// stalls ~8 s on the AAAA lookup, long enough for levee to drop the socket.
const host = "127.0.0.1"

const port = 4000

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "dice-scores"

/// Root-map key holding the handle to the roster map.
const players_key = "players"

const die_sides = 6

const first_roll_delay_ms = 1000

const roll_interval_ms = 5000

/// A handle read from a remote value can be transiently unresolvable while
/// the referenced channel's attach op is still in flight, so resolves retry.
const resolve_retry_ms = 200

const resolve_attempts = 25

type Msg {
  /// The roster map changed: a player joined (or re-registered).
  RosterChanged(ChannelEvent)
  /// Some player's own map changed: a roll landed.
  ScoreChanged(ChannelEvent)
  RollDue
}

type State {
  State(
    doc: watershed.Document,
    my_id: String,
    me: watershed.SharedMap,
    roster: watershed.SharedMap,
    /// Every player map we have resolved and subscribed to, by player id.
    known: Dict(String, watershed.SharedMap),
    selector: process.Selector(Msg),
    roll_due: process.Subject(Nil),
    total: Int,
    rolls: Int,
  )
}

// ── Entry point ───────────────────────────────────────────────────────────────

pub fn main() {
  let player_id = "player-" <> int.to_string(int.random(9000) + 1000)
  let token =
    watershed.dev_token(
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
    watershed.connect(
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
    Ok(doc) -> {
      let root = watershed.root(doc)

      // The root map carries plain values alongside the roster handle.
      case watershed.get(root, "game") {
        Some(_) -> Nil
        None -> {
          watershed.set(root, "game", json.string("watershed dice scores"))
          watershed.set(root, "die_sides", json.int(die_sides))
        }
      }

      let roster = ensure_roster(doc, root)

      // Our own player map: populated while detached (local-only), then
      // attached — snapshot and all — by storing its handle in the roster.
      let assert Ok(me) = watershed.create_map(doc)
      watershed.set(me, "name", json.string(player_id))
      watershed.set(me, "last_roll", json.null())
      watershed.set(me, "total", json.int(0))
      watershed.set(me, "rolls", json.int(0))
      watershed.set(roster, player_id, watershed.handle_of(me))

      let roll_due = process.new_subject()
      let selector =
        process.new_selector()
        |> process.select_map(watershed.subscribe(roster), RosterChanged)
        |> process.select_map(watershed.subscribe(me), ScoreChanged)
        |> process.select_map(roll_due, fn(_) { RollDue })

      let state =
        State(
          doc: doc,
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
      let state =
        list.fold(watershed.entries(roster), state, fn(state, entry) {
          watch_player(state, entry.0)
        })
      print_scoreboard(state)

      io.println(
        "Rolling every "
        <> int.to_string(roll_interval_ms / 1000)
        <> "s; press Ctrl+C to stop.",
      )
      schedule_roll(roll_due, first_roll_delay_ms)
      event_loop(state)
    }
  }
}

// ── Event loop ────────────────────────────────────────────────────────────────

fn event_loop(state: State) -> Nil {
  case process.selector_receive_forever(state.selector) {
    RollDue -> {
      let roll = int.random(die_sides) + 1
      let total = state.total + roll
      let rolls = state.rolls + 1
      io.println("You rolled a " <> int.to_string(roll) <> ".")
      watershed.set(state.me, "last_roll", json.int(roll))
      watershed.set(state.me, "total", json.int(total))
      watershed.set(state.me, "rolls", json.int(rolls))
      let state = State(..state, total: total, rolls: rolls)
      print_scoreboard(state)
      schedule_roll(state.roll_due, roll_interval_ms)
      event_loop(state)
    }
    RosterChanged(channel.MapEvent(ValueChanged(key: player_id, ..))) -> {
      let new_state = watch_player(state, player_id)
      case dict.size(new_state.known) > dict.size(state.known) {
        True -> print_scoreboard(new_state)
        False -> Nil
      }
      event_loop(new_state)
    }
    RosterChanged(channel.MapEvent(Cleared(..))) -> {
      event_loop(state)
    }
    ScoreChanged(event) -> {
      // A remote roll writes three keys ("last_roll", "total", "rolls");
      // reprint once, on the final write. Local writes already print above.
      case event {
        channel.MapEvent(ValueChanged(key: "rolls", local: False, ..))
        | channel.MapEvent(Cleared(local: False)) -> print_scoreboard(state)
        _ -> Nil
      }
      event_loop(state)
    }
  }
}

// ── Roster handling ───────────────────────────────────────────────────────────

/// Resolve the shared roster map from the root, creating it on first join.
/// Concurrent first joins race on `players_key`; last write wins, so after
/// writing we wait for our op to be sequenced and adopt whichever handle the
/// key holds.
fn ensure_roster(
  doc: watershed.Document,
  root: watershed.SharedMap,
) -> watershed.SharedMap {
  case watershed.get(root, players_key) {
    Some(value) -> resolve_or_panic(doc, value)
    None -> {
      let assert Ok(created) = watershed.create_map(doc)
      watershed.set(root, players_key, watershed.handle_of(created))
      wait_synced(doc)
      let assert Some(value) = watershed.get(root, players_key)
      resolve_or_panic(doc, value)
    }
  }
}

/// Resolve `player_id`'s map from the roster and add its events to the
/// selector. A no-op for players we already watch (including ourselves).
fn watch_player(state: State, player_id: String) -> State {
  case dict.has_key(state.known, player_id) {
    True -> state
    False ->
      case watershed.get(state.roster, player_id) {
        None -> state
        Some(value) ->
          case resolve_with_retry(state.doc, value, resolve_attempts) {
            Error(reason) -> {
              io.println("Could not resolve " <> player_id <> ": " <> reason)
              state
            }
            Ok(map) -> {
              io.println(player_id <> " joined the game.")
              let selector =
                process.select_map(
                  state.selector,
                  watershed.subscribe(map),
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
  }
}

fn resolve_with_retry(
  doc: watershed.Document,
  value: Json,
  attempts: Int,
) -> Result(watershed.SharedMap, String) {
  case watershed.resolve(doc, value) {
    Ok(map) -> Ok(map)
    Error(reason) ->
      case attempts <= 1 {
        True -> Error(reason)
        False -> {
          process.sleep(resolve_retry_ms)
          resolve_with_retry(doc, value, attempts - 1)
        }
      }
  }
}

fn resolve_or_panic(
  doc: watershed.Document,
  value: Json,
) -> watershed.SharedMap {
  case resolve_with_retry(doc, value, resolve_attempts) {
    Ok(map) -> map
    Error(reason) -> panic as { "failed to resolve roster: " <> reason }
  }
}

fn wait_synced(doc: watershed.Document) -> Nil {
  case watershed.is_synced(doc) {
    True -> Nil
    False -> {
      process.sleep(100)
      wait_synced(doc)
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
    io.println(
      "  "
      <> player_id
      <> marker
      <> "  total="
      <> show(map, "total")
      <> "  rolls="
      <> show(map, "rolls")
      <> "  last="
      <> show(map, "last_roll"),
    )
  })
}

fn show(map: watershed.SharedMap, key: String) -> String {
  case watershed.get(map, key) {
    None -> "-"
    Some(value) -> json.to_string(value)
  }
}

fn schedule_roll(roll_due: process.Subject(Nil), delay_ms: Int) -> Nil {
  let _timer = process.send_after(roll_due, delay_ms, Nil)
  Nil
}

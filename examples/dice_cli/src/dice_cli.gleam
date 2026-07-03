//// Erlang-target CLI dice roller that joins the same levee document as the
//// `dice_lustre` browser app. Demonstrates the watershed OTP client API:
//// connect → root → subscribe → loop on process.receive while rolling dice.
////
//// Run against `just server` in the levee repo:
////
//// ```sh
//// gleam run          # keep running, roll periodically, print events
//// ```
////
//// With a `dice_lustre` tab open you will see the roll converge in the
//// browser and vice-versa (remote rolls appear via the events Subject).

import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string

import watershed
import watershed/map_kernel.{type MapEvent, ValueChanged}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

/// IPv4 loopback literal — do NOT use "localhost".  Erlang's inet resolver
/// stalls ~8 s on the AAAA lookup, long enough for levee to drop the socket.
const host = "127.0.0.1"

const port = 4000

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "dice"

const die_key = "die"

const user_id = "dice-cli-user"

const first_roll_delay_ms = 1000

const roll_interval_ms = 5000

type CliMsg {
  MapChanged(MapEvent)
  RollDue
}

// ── Entry point ───────────────────────────────────────────────────────────────

pub fn main() {
  let token =
    watershed.dev_token(
      secret: tenant_secret,
      tenant: tenant,
      document: document_id,
      user_id: user_id,
    )

  io.println("Connecting to " <> host <> ":" <> int.to_string(port) <> "…")

  case
    watershed.connect(
      host: host,
      port: port,
      tenant: tenant,
      document: document_id,
      token: token,
      user_id: user_id,
    )
  {
    Error(reason) -> {
      io.println("Connection failed: " <> reason)
    }
    Ok(doc) -> {
      io.println("Connected. Subscribing to events…")
      let map = watershed.root(doc)
      let events = watershed.subscribe(map)

      // Print current state
      let current = watershed.entries(map)
      case current {
        [] -> io.println("Document is empty.")
        entries -> {
          io.println("Current entries:")
          list.each(entries, fn(entry) {
            let #(k, v) = entry
            io.println("  " <> k <> " = " <> json.to_string(v))
          })
        }
      }

      // Roll a die
      let roll_due = process.new_subject()
      let selector =
        process.new_selector()
        |> process.select_map(events, MapChanged)
        |> process.select_map(roll_due, fn(_) { RollDue })

      io.println(
        "Rolling every "
        <> int.to_string(roll_interval_ms / 1000)
        <> "s; press Ctrl+C to stop.",
      )
      schedule_roll(roll_due, first_roll_delay_ms)
      event_loop(map, selector, roll_due)
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn event_loop(
  map: watershed.SharedMap,
  selector: process.Selector(CliMsg),
  roll_due: process.Subject(Nil),
) -> Nil {
  case process.selector_receive_forever(selector) {
    MapChanged(event) -> {
      print_event(event)
      print_snapshot(map)
      event_loop(map, selector, roll_due)
    }
    RollDue -> {
      roll(map)
      schedule_roll(roll_due, roll_interval_ms)
      event_loop(map, selector, roll_due)
    }
  }
}

fn roll(map: watershed.SharedMap) -> Nil {
  let roll = int.random(6) + 1
  io.println("CLI roll: " <> int.to_string(roll))
  // Exercise both edit paths the public API exposes for the example.
  watershed.delete(map, die_key)
  watershed.set(map, die_key, json.int(roll))
  print_die("Optimistic die", map)
}

fn schedule_roll(roll_due: process.Subject(Nil), delay_ms: Int) -> Nil {
  let _timer = process.send_after(roll_due, delay_ms, Nil)
  Nil
}

fn print_snapshot(map: watershed.SharedMap) -> Nil {
  print_die("Current die", map)
  let entries = watershed.entries(map)
  case entries {
    [] -> io.println("  entries: (empty)")
    _ -> {
      io.println("  entries:")
      list.each(entries, fn(entry) {
        let #(k, v) = entry
        io.println("    " <> k <> " = " <> json.to_string(v))
      })
    }
  }
}

fn print_die(label: String, map: watershed.SharedMap) -> Nil {
  case watershed.get(map, die_key) {
    None -> io.println(label <> ": (missing)")
    Some(v) -> io.println(label <> ": " <> json.to_string(v))
  }
}

fn print_event(event: MapEvent) -> Nil {
  case event {
    ValueChanged(key: k, ..) -> io.println("  event: changed key " <> k)
    _ -> io.println("  event: " <> string.inspect(event))
  }
}

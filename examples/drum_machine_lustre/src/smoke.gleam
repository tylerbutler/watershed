//// Headless smoke test: drive two `watershed` clients against a live
//// floodgate dev server (`just integration-up`) from Node and assert that the
//// pattern converges — the OR-set kernel, the OR-set wire codecs, the JS
//// runtime, the Phoenix FFI transport, and the pure core, end to end.
////
//// There is deliberately no audio here. The scheduler is a Web Audio concern
//// with no collaborative content, and it does not run under Node; the
//// convergence claim is what a smoke test can actually check.
////
//// The interesting assertion is the last one. Two clients toggling the same
//// step in opposite directions with no coordination must not lose the enable:
//// a last-writer-wins map would settle either way, and only an add-wins set
//// guarantees the step everyone can see stays on.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string

import doc_schema
import watershed/summary_policy
import watershed.{type Document, type OrSet, WatershedConfig}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.Machine)) {
  use token <- promise.map(watershed.dev_token(
    secret,
    tenant,
    document,
    user,
  ))
  watershed.connect(
    WatershedConfig(
      url: url,
      tenant: tenant,
      document: document,
      token: token,
      user_id: user,
    ),
    on_ready: fn(result) {
      case result {
        Ok(_) -> log("  " <> user <> " ready")
        Error(reason) -> log("  " <> user <> " FAILED: " <> reason)
      }
    },
  )
}

pub fn main() {
  let document = "drum-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn run_scenario(
  doc_a: Document(doc_schema.Machine),
  doc_b: Document(doc_schema.Machine),
) -> Nil {
  // Let both handshakes land before anyone attaches a channel.
  use <- delay(2000)

  // The app installs the same policy, at the shipped threshold. Here it is low
  // enough that the handful of ops below crosses it, so the run exercises the
  // whole path — upload, summarize op, checkpoint — rather than just the
  // arming. Nothing below calls `summarize`.
  let policy =
    summary_policy.policy()
    |> summary_policy.with_threshold(6)
    |> summary_policy.with_jitter_ms(0)
  watershed.auto_summarize(doc_a, policy)
  watershed.auto_summarize(doc_b, policy)

  log("smoke: ensuring the kick track on A")

  watershed.ensure_or_set(
    doc_a,
    watershed.root_typed(doc_a),
    doc_schema.kick(),
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: A could not ensure the kick track: " <> reason)
          exit(1)
        }
        Ok(kick_a) -> adopt_on_b(doc_a, doc_b, kick_a)
      }
    },
  )
}

fn adopt_on_b(
  doc_a: Document(doc_schema.Machine),
  doc_b: Document(doc_schema.Machine),
  kick_a: OrSet,
) -> Nil {
  // B adopts the same channel rather than creating its own — `ensure_or_set`
  // resolves the handle A just published.
  use <- delay(1500)
  watershed.ensure_or_set(
    doc_b,
    watershed.root_typed(doc_b),
    doc_schema.kick(),
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: B could not adopt the kick track: " <> reason)
          exit(1)
        }
        Ok(kick_b) -> toggle_scenario(doc_a, kick_a, kick_b)
      }
    },
  )
}

fn toggle_scenario(
  doc_a: Document(doc_schema.Machine),
  kick_a: OrSet,
  kick_b: OrSet,
) -> Nil {
  log("smoke: A programs four-on-the-floor")
  list.each(["0", "4", "8", "12"], fn(step) {
    watershed.or_set_add(kick_a, step)
  })

  use <- delay(1500)
  let seeded = steps(kick_b) == ["0", "12", "4", "8"]
  log("  B sees " <> string.join(steps(kick_b), ","))

  // B removes a step it can see; A concurrently re-enables the same step. The
  // enable must survive.
  log("smoke: B disables step 4 while A re-enables it")
  watershed.or_set_remove(kick_b, "4")
  watershed.or_set_add(kick_a, "4")

  use <- delay(1500)
  let converged = steps(kick_a) == steps(kick_b)
  let add_won = list.contains(steps(kick_a), "4")

  // And a plain toggle round-trips through the server, which is the one thing
  // every tab in the demo depends on.
  log("smoke: A toggles step 2 on, then off")
  watershed.or_set_add(kick_a, "2")
  use <- delay(1000)
  let on = list.contains(steps(kick_b), "2")
  watershed.or_set_remove(kick_a, "2")
  use <- delay(1000)
  let off = !list.contains(steps(kick_b), "2")

  // A reconnect must not resurrect or drop anything: the pattern after the
  // handshake replays is the pattern before it.
  let before = steps(kick_a)
  watershed.force_reconnect(doc_a)
  use <- delay(2500)
  let survived_reconnect = steps(kick_a) == before && steps(kick_b) == before

  // By now the room is well past the threshold, so a checkpoint should have
  // been written without anything here asking for one. The observable is the
  // client's own drift falling back below the ops it has authored.
  use <- delay(1500)
  let summarized = watershed.ops_since_summary(doc_a) < 6

  case
    seeded
    && converged
    && add_won
    && on
    && off
    && survived_reconnect
    && summarized
  {
    True -> {
      log(
        "SMOKE PASS: the pattern converged, the enable won, and the room summarized itself",
      )
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: seeded="
        <> bool_str(seeded)
        <> " converged="
        <> bool_str(converged)
        <> " add_won="
        <> bool_str(add_won)
        <> " toggle_on="
        <> bool_str(on)
        <> " toggle_off="
        <> bool_str(off)
        <> " survived_reconnect="
        <> bool_str(survived_reconnect)
        <> " summarized="
        <> bool_str(summarized)
        <> " (A="
        <> string.join(steps(kick_a), ",")
        <> " B="
        <> string.join(steps(kick_b), ",")
        <> ")",
      )
      exit(1)
    }
  }
}

/// Sorted, because an OR-set's read order carries no meaning.
fn steps(set: OrSet) -> List(String) {
  watershed.or_set_values(set) |> list.sort(string.compare)
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

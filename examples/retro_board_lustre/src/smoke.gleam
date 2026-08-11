//// Headless smoke test: two `watershed_js` clients against a live floodgate
//// dev server (`just integration-up`) from Node, asserting that the demo's
//// two headline conflicts converge over the real transport — concurrent adds
//// both survive, concurrent upvotes sum. This exercises the OR-map kernel in
//// both value modes, the sequence channel, the wire codecs, the Phoenix FFI
//// transport, and the summarize path.
////
//// Cross-column moves and edit-vs-delete are deliberately not re-run here:
//// the sluice convergence suite pins them deterministically. The smoke
//// exists to prove wire + auth + summarize, not to re-run the suite slowly.
////
//// Run via `pnpm run smoke`, which bundles this and supplies a WebSocket
//// global through `smoke/run.mjs`.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option
import gleam/string

import watershed/or_map_kernel
import watershed/summary_policy
import watershed_js.{type Document, type OrMap, WatershedConfig}

import column
import doc_schema
import note.{Note}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(document: String, user: String) -> Promise(Document) {
  use token <- promise.map(watershed_js.dev_token(
    secret,
    tenant,
    document,
    user,
  ))
  watershed_js.connect(
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
  let document = "retro-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn run_scenario(doc_a: Document, doc_b: Document) -> Nil {
  // Let both handshakes land before anyone attaches a channel.
  use <- delay(2000)

  // The app installs the same policy at a shipped threshold of 200; here it
  // is low enough that the handful of ops below crosses it, so the run
  // exercises the whole summarize path rather than just the arming.
  let policy =
    summary_policy.policy()
    |> summary_policy.with_threshold(6)
    |> summary_policy.with_jitter_ms(0)
  watershed_js.auto_summarize(doc_a, policy)
  watershed_js.auto_summarize(doc_b, policy)

  log("smoke: ensuring notes, votes, and went_well on A")
  let root_a = watershed_js.root_typed(doc_a)
  watershed_js.ensure_or_map(
    doc_a,
    root_a,
    doc_schema.notes(),
    or_map_kernel.RegisterMode,
    fn(result) {
      case result {
        Error(reason) -> fail("A could not ensure notes: " <> reason)
        Ok(notes_a) ->
          watershed_js.ensure_or_map(
            doc_a,
            root_a,
            doc_schema.votes(),
            or_map_kernel.TallyMode,
            fn(result) {
              case result {
                Error(reason) -> fail("A could not ensure votes: " <> reason)
                Ok(votes_a) ->
                  watershed_js.ensure_sequence(
                    doc_a,
                    root_a,
                    doc_schema.went_well(),
                    fn(result) {
                      case result {
                        Error(reason) ->
                          fail("A could not ensure went_well: " <> reason)
                        Ok(seq_a) ->
                          seed_then_resolve(doc_b, notes_a, votes_a, seq_a)
                      }
                    },
                  )
              }
            },
          )
      }
    },
  )
}

/// A seeds one card, then B resolves the same channels from its own root —
/// proving adoption rather than duplicate creation.
fn seed_then_resolve(
  doc_b: Document,
  notes_a: OrMap,
  votes_a: OrMap,
  seq_a: watershed_js.SharedSequence,
) -> Nil {
  log("smoke: seeding one card from A")
  add_card(notes_a, seq_a, "note-seed", "user-a", "ship week went smoothly")

  use <- delay(2000)
  let root_b = watershed_js.root_typed(doc_b)
  watershed_js.ensure_or_map(
    doc_b,
    root_b,
    doc_schema.notes(),
    or_map_kernel.RegisterMode,
    fn(result) {
      case result {
        Error(reason) -> fail("B could not resolve notes: " <> reason)
        Ok(notes_b) ->
          watershed_js.ensure_or_map(
            doc_b,
            root_b,
            doc_schema.votes(),
            or_map_kernel.TallyMode,
            fn(result) {
              case result {
                Error(reason) -> fail("B could not resolve votes: " <> reason)
                Ok(votes_b) ->
                  watershed_js.ensure_sequence(
                    doc_b,
                    root_b,
                    doc_schema.went_well(),
                    fn(result) {
                      case result {
                        Error(reason) ->
                          fail("B could not resolve went_well: " <> reason)
                        Ok(seq_b) ->
                          concurrent_phase(
                            notes_a,
                            votes_a,
                            seq_a,
                            notes_b,
                            votes_b,
                            seq_b,
                          )
                      }
                    },
                  )
              }
            },
          )
      }
    },
  )
}

/// The real test: both clients add a card and upvote the seeded card in the
/// same tick, with no coordination.
fn concurrent_phase(
  notes_a: OrMap,
  votes_a: OrMap,
  seq_a: watershed_js.SharedSequence,
  notes_b: OrMap,
  votes_b: OrMap,
  seq_b: watershed_js.SharedSequence,
) -> Nil {
  use <- delay(500)
  log("smoke: concurrent adds and votes from A and B")
  add_card(notes_a, seq_a, "note-a", "user-a", "deploys got faster")
  add_card(notes_b, seq_b, "note-b", "user-b", "standup stayed short")
  watershed_js.or_map_increment(votes_a, "note-seed", 1)
  watershed_js.or_map_increment(votes_b, "note-seed", 1)

  use <- delay(3000)
  let keys_a = watershed_js.or_map_keys(notes_a) |> list.sort(string.compare)
  let keys_b = watershed_js.or_map_keys(notes_b) |> list.sort(string.compare)
  log("smoke: final notes A = " <> string.join(keys_a, ", "))
  log("smoke: final notes B = " <> string.join(keys_b, ", "))

  let both_adds_survived = keys_a == ["note-a", "note-b", "note-seed"]
  let converged = keys_a == keys_b
  let tally_a = tally(votes_a, "note-seed")
  let tally_b = tally(votes_b, "note-seed")
  let votes_summed = tally_a == 2 && tally_b == 2
  let order_agreed =
    watershed_js.sequence_values(seq_a) == watershed_js.sequence_values(seq_b)

  case both_adds_survived && converged && votes_summed && order_agreed {
    True -> {
      log("SMOKE PASS: concurrent adds survived and concurrent votes summed")
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: both_adds_survived="
        <> bool_str(both_adds_survived)
        <> " converged="
        <> bool_str(converged)
        <> " votes_summed="
        <> bool_str(votes_summed)
        <> " (A="
        <> int.to_string(tally_a)
        <> ", B="
        <> int.to_string(tally_b)
        <> ") order_agreed="
        <> bool_str(order_agreed),
      )
      exit(1)
    }
  }
}

fn add_card(
  notes: OrMap,
  sequence: watershed_js.SharedSequence,
  id: String,
  author: String,
  text: String,
) -> Nil {
  let entry =
    Note(
      text: text,
      column: column.id(column.WentWell),
      author: author,
      created: 1000,
    )
  watershed_js.or_map_set_json(notes, id, note.to_json(entry))
  case
    watershed_js.sequence_insert(
      sequence,
      watershed_js.sequence_length(sequence),
      json.string(id),
    )
  {
    Ok(Nil) -> Nil
    Error(reason) -> log("  insert " <> id <> " failed: " <> reason)
  }
}

fn tally(votes: OrMap, id: String) -> Int {
  case watershed_js.or_map_value(votes, id) {
    option.Some(or_map_kernel.Tally(count)) -> count
    _ -> 0
  }
}

fn fail(message: String) -> Nil {
  log("SMOKE FAIL: " <> message)
  exit(1)
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

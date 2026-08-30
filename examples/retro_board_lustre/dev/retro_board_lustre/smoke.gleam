//// Headless smoke test: two `watershed` clients against a live floodgate
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
import gleam/string

import watershed.{type Document, type OrMap, WatershedConfig}
import watershed/or_map_kernel
import watershed/summary_policy

import retro_board_lustre/column
import retro_board_lustre/doc_schema
import retro_board_lustre/note.{Note}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, callback: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.BoardDoc)) {
  use token <- promise.map(watershed.dev_token(secret, tenant, document, user))
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

pub fn main() -> Nil {
  let document = "retro-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn run_scenario(
  doc_a: Document(doc_schema.BoardDoc),
  doc_b: Document(doc_schema.BoardDoc),
) -> Nil {
  // Let both handshakes land before anyone attaches a channel.
  use <- delay(2000)

  // The app installs the same policy at a shipped threshold of 200; here it
  // is low enough that the handful of operations below crosses it, so the run
  // exercises the whole summarize path rather than just the arming.
  let policy =
    summary_policy.policy()
    |> summary_policy.with_threshold(6)
    |> summary_policy.with_jitter_ms(0)
  watershed.auto_summarize(doc_a, policy)
  watershed.auto_summarize(doc_b, policy)

  log("smoke: ensuring notes, votes, and went_well on A")
  let root_a = watershed.root_typed(doc_a)
  watershed.ensure_or_map(
    doc_a,
    root_a,
    doc_schema.notes(),
    or_map_kernel.RegisterMode,
    fn(result) {
      case result {
        Error(reason) -> fail("A could not ensure notes: " <> reason)
        Ok(notes_a) ->
          watershed.ensure_or_map(
            doc_a,
            root_a,
            doc_schema.votes(),
            or_map_kernel.TallyMode,
            fn(result) {
              case result {
                Error(reason) -> fail("A could not ensure votes: " <> reason)
                Ok(votes_a) ->
                  watershed.ensure_sequence(
                    doc_a,
                    root_a,
                    doc_schema.went_well(),
                    fn(result) {
                      case result {
                        Error(reason) ->
                          fail("A could not ensure went_well: " <> reason)
                        Ok(sequence_a) ->
                          seed_then_resolve(doc_b, notes_a, votes_a, sequence_a)
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
  doc_b: Document(doc_schema.BoardDoc),
  notes_a: OrMap,
  votes_a: OrMap,
  sequence_a: watershed.SharedSequence,
) -> Nil {
  log("smoke: seeding one card from A")
  add_card(
    notes_a,
    sequence_a,
    "note-seed",
    "user-a",
    "ship week went smoothly",
  )

  use <- delay(2000)
  let root_b = watershed.root_typed(doc_b)
  watershed.ensure_or_map(
    doc_b,
    root_b,
    doc_schema.notes(),
    or_map_kernel.RegisterMode,
    fn(result) {
      case result {
        Error(reason) -> fail("B could not resolve notes: " <> reason)
        Ok(notes_b) ->
          watershed.ensure_or_map(
            doc_b,
            root_b,
            doc_schema.votes(),
            or_map_kernel.TallyMode,
            fn(result) {
              case result {
                Error(reason) -> fail("B could not resolve votes: " <> reason)
                Ok(votes_b) ->
                  watershed.ensure_sequence(
                    doc_b,
                    root_b,
                    doc_schema.went_well(),
                    fn(result) {
                      case result {
                        Error(reason) ->
                          fail("B could not resolve went_well: " <> reason)
                        Ok(sequence_b) ->
                          concurrent_phase(
                            notes_a,
                            votes_a,
                            sequence_a,
                            notes_b,
                            votes_b,
                            sequence_b,
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
  sequence_a: watershed.SharedSequence,
  notes_b: OrMap,
  votes_b: OrMap,
  sequence_b: watershed.SharedSequence,
) -> Nil {
  use <- delay(500)
  log("smoke: concurrent adds and votes from A and B")
  add_card(notes_a, sequence_a, "note-a", "user-a", "deploys got faster")
  add_card(notes_b, sequence_b, "note-b", "user-b", "standup stayed short")
  watershed.or_map_increment(votes_a, "note-seed", 1)
  watershed.or_map_increment(votes_b, "note-seed", 1)

  use <- delay(3000)
  let keys_a = watershed.or_map_keys(notes_a) |> list.sort(string.compare)
  let keys_b = watershed.or_map_keys(notes_b) |> list.sort(string.compare)
  log("smoke: final notes A = " <> string.join(keys_a, ", "))
  log("smoke: final notes B = " <> string.join(keys_b, ", "))

  let both_adds_survived = keys_a == ["note-a", "note-b", "note-seed"]
  let converged = keys_a == keys_b
  let tally_a = tally(votes_a, "note-seed")
  let tally_b = tally(votes_b, "note-seed")
  let votes_summed = tally_a == 2 && tally_b == 2
  let order_agreed =
    watershed.sequence_values(sequence_a)
    == watershed.sequence_values(sequence_b)

  case both_adds_survived && converged && votes_summed && order_agreed {
    True -> {
      log("SMOKE PASS: concurrent adds survived and concurrent votes summed")
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: both_adds_survived="
        <> bool_to_string(both_adds_survived)
        <> " converged="
        <> bool_to_string(converged)
        <> " votes_summed="
        <> bool_to_string(votes_summed)
        <> " (A="
        <> int.to_string(tally_a)
        <> ", B="
        <> int.to_string(tally_b)
        <> ") order_agreed="
        <> bool_to_string(order_agreed),
      )
      exit(1)
    }
  }
}

fn add_card(
  notes: OrMap,
  sequence: watershed.SharedSequence,
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
  watershed.or_map_set_json(notes, id, note.to_json(entry))
  case
    watershed.sequence_insert(
      sequence,
      watershed.sequence_length(sequence),
      json.string(id),
    )
  {
    Ok(Nil) -> Nil
    Error(reason) -> log("  insert " <> id <> " failed: " <> reason)
  }
}

fn tally(votes: OrMap, id: String) -> Int {
  case watershed.or_map_value(votes, id) {
    Ok(or_map_kernel.Tally(count)) -> count
    _ -> 0
  }
}

fn fail(message: String) -> Nil {
  log("SMOKE FAIL: " <> message)
  exit(1)
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

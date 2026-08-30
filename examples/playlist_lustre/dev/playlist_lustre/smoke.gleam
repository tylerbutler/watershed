//// Headless smoke test: drive two `watershed` SharedSequence clients
//// against a live levee dev server (`just server`) from Node, asserting that
//// concurrent reorders converge. This exercises the sequence kernel, the
//// sequence wire codecs, the JS runtime, the Phoenix FFI transport, and the
//// pure core — the whole JS stack, for the one DDS whose operations are
//// ordered.
////
//// The interesting assertion is the concurrent one: A moves a track while B
//// replaces a different track, with no coordination. A last-writer-wins map
//// would be enough for the replace; only a convergent sequence keeps both
//// clients on the *same order* afterwards.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/list
import gleam/string

import watershed.{type Document, type SharedSequence, WatershedConfig}

import playlist_lustre/doc_schema
import playlist_lustre/track.{Track}

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
) -> Promise(Document(doc_schema.PlaylistDoc)) {
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
  let document = "seq-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn run_scenario(
  doc_a: Document(doc_schema.PlaylistDoc),
  doc_b: Document(doc_schema.PlaylistDoc),
) -> Nil {
  // Let both handshakes land before anyone attaches a channel.
  use <- delay(2000)
  log("smoke: ensuring the tracks sequence on A")

  watershed.ensure_sequence(
    doc_a,
    watershed.root_typed(doc_a),
    doc_schema.tracks(),
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: A could not ensure the sequence: " <> reason)
          exit(1)
        }
        Ok(sequence_a) -> seed_then_resolve(doc_b, sequence_a)
      }
    },
  )
}

/// A seeds three tracks, then B resolves the same sequence from the root map.
fn seed_then_resolve(
  doc_b: Document(doc_schema.PlaylistDoc),
  sequence_a: SharedSequence,
) -> Nil {
  log("smoke: seeding three tracks from A")
  insert_track(sequence_a, "Windowlicker", "Aphex Twin")
  insert_track(sequence_a, "Xtal", "Aphex Twin")
  insert_track(sequence_a, "Alberto Balsalm", "Aphex Twin")

  // Wait for A's attach + inserts to reach B, then resolve on B.
  use <- delay(2000)
  watershed.ensure_sequence(
    doc_b,
    watershed.root_typed(doc_b),
    doc_schema.tracks(),
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: B could not resolve the sequence: " <> reason)
          exit(1)
        }
        Ok(sequence_b) -> concurrent_phase(sequence_a, sequence_b)
      }
    },
  )
}

/// The real test: a move on A racing a replace on B, with no coordination.
fn concurrent_phase(
  sequence_a: SharedSequence,
  sequence_b: SharedSequence,
) -> Nil {
  use <- delay(500)
  let seeded_a = titles(sequence_a)
  let seeded_b = titles(sequence_b)
  log("smoke: seeded A = " <> string.join(seeded_a, ", "))
  log("smoke: seeded B = " <> string.join(seeded_b, ", "))

  // Both clients edit in the same tick, before either operation is sequenced.
  // A lifts track 0 to the end; destinations are interpreted after removal,
  // so index 2 is the tail of the 2-element list left behind.
  log("smoke: concurrent move on A, replace on B")
  let move_result = watershed.sequence_move(sequence_a, 0, 2)
  let replace_result =
    watershed.sequence_replace(
      sequence_b,
      1,
      track.to_json(Track(
        title: "Xtal (remaster)",
        artist: "Aphex Twin",
        added_by: "user-b",
      )),
    )

  // An index past the end must be refused rather than silently clamped.
  let out_of_bounds = watershed.sequence_delete(sequence_a, 99)

  use <- delay(3000)
  let final_a = titles(sequence_a)
  let final_b = titles(sequence_b)
  log("smoke: final A = " <> string.join(final_a, ", "))
  log("smoke: final B = " <> string.join(final_b, ", "))

  let seeded_ok = list.length(seeded_a) == 3 && seeded_a == seeded_b
  let converged = final_a == final_b && list.length(final_a) == 3
  let move_ok = move_result == Ok(Nil)
  let replace_ok = replace_result == Ok(Nil)
  let rejected_ok = case out_of_bounds {
    Error(_) -> True
    Ok(Nil) -> False
  }
  // The replace must survive the concurrent move rather than being lost.
  let replace_survived = list.contains(final_a, "Xtal (remaster)")
  // A move reorders, it does not duplicate: every title stays unique.
  let no_duplicates = list.unique(final_a) == final_a

  case
    seeded_ok
    && converged
    && move_ok
    && replace_ok
    && rejected_ok
    && replace_survived
    && no_duplicates
  {
    True -> {
      log("SMOKE PASS: concurrent move and replace converged")
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: seeded="
        <> bool_to_string(seeded_ok)
        <> " converged="
        <> bool_to_string(converged)
        <> " move_ok="
        <> bool_to_string(move_ok)
        <> " replace_ok="
        <> bool_to_string(replace_ok)
        <> " out_of_bounds_rejected="
        <> bool_to_string(rejected_ok)
        <> " replace_survived="
        <> bool_to_string(replace_survived)
        <> " no_duplicates="
        <> bool_to_string(no_duplicates),
      )
      exit(1)
    }
  }
}

fn insert_track(
  sequence: SharedSequence,
  title: String,
  artist: String,
) -> Nil {
  let entry = Track(title: title, artist: artist, added_by: "user-a")
  case
    watershed.sequence_insert(
      sequence,
      watershed.sequence_length(sequence),
      track.to_json(entry),
    )
  {
    Ok(Nil) -> Nil
    Error(reason) -> log("  insert " <> title <> " failed: " <> reason)
  }
}

fn titles(sequence: SharedSequence) -> List(String) {
  watershed.sequence_values(sequence)
  |> list.map(fn(value: Json) { track.from_json(value).title })
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

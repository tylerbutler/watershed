//// Headless smoke test: drive two `watershed_js` SharedText clients against a
//// live levee dev server (`just server`) from Node, asserting that concurrent
//// grapheme-indexed edits converge. This exercises the text kernel, the text
//// wire codecs, the JS runtime, the Phoenix FFI transport, and the pure core —
//// the whole JS stack, for the one DDS addressed by grapheme index into a live
//// string.
////
//// The interesting assertions are the concurrent ones: A inserts an emoji at
//// the head while B inserts a combining sequence at the tail, with no
//// coordination. Both clients must land on the *same* string afterwards, an
//// append must survive the race, an out-of-bounds index must be refused rather
//// than clamped, and a pinned anchor must track the content it was anchored
//// after.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string

import watershed_js.{type Document, type SharedText, WatershedConfig}

import doc_schema

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

const seed_text = "Hello, world"

// An emoji (one grapheme, several code units) inserted at the head.
const head_insert = "🌊 "

// "e" + combining acute accent: one grapheme, two code points. Inserting this
// at the tail proves the CRDT never splits a grapheme cluster.
const tail_insert = "e\u{301}"

const append_text = " ✨"

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
  let document = "text-smoke-" <> int.to_string(100_000 + int.random(900_000))
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
  log("smoke: ensuring the body text on A")

  watershed_js.ensure_text(
    doc_a,
    watershed_js.root_typed(doc_a),
    doc_schema.body(),
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: A could not ensure the text: " <> reason)
          exit(1)
        }
        Ok(text_a) -> seed_then_resolve(doc_b, text_a)
      }
    },
  )
}

/// A seeds the document, then B resolves the same text from the root map.
fn seed_then_resolve(doc_b: Document, text_a: SharedText) -> Nil {
  log("smoke: seeding text from A")
  case watershed_js.text_insert(text_a, 0, seed_text) {
    Ok(Nil) -> Nil
    Error(reason) -> log("  seed insert failed: " <> reason)
  }

  // Wait for A's attach + insert to reach B, then resolve on B.
  use <- delay(2000)
  watershed_js.ensure_text(
    doc_b,
    watershed_js.root_typed(doc_b),
    doc_schema.body(),
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: B could not resolve the text: " <> reason)
          exit(1)
        }
        Ok(text_b) -> concurrent_phase(text_a, text_b)
      }
    },
  )
}

/// The real test: an emoji insert at the head on A racing a combining-mark
/// insert at the tail on B, plus an append, an out-of-bounds rejection, and a
/// pinned anchor that must track content inserted before it.
fn concurrent_phase(text_a: SharedText, text_b: SharedText) -> Nil {
  use <- delay(500)
  let seeded_a = watershed_js.text_value(text_a)
  let seeded_b = watershed_js.text_value(text_b)
  log("smoke: seeded A = " <> seeded_a)
  log("smoke: seeded B = " <> seeded_b)

  // Pin an anchor on A at grapheme 5 (inside "Hello, world") before any edit,
  // then race concurrent inserts around it.
  let anchor = watershed_js.text_anchor_at(text_a, 5, watershed_js.bias_before)
  let old_pos = case anchor {
    Ok(a) ->
      case watershed_js.text_resolve_anchor(text_a, a) {
        Ok(pos) -> pos
        Error(_) -> -1
      }
    Error(_) -> -1
  }
  log("smoke: anchor pinned, resolves to " <> int.to_string(old_pos))

  // Both clients edit in the same tick, before either op is sequenced.
  log("smoke: concurrent emoji-head on A, combining-tail on B")
  let insert_a = watershed_js.text_insert(text_a, 0, head_insert)
  let insert_b =
    watershed_js.text_insert(
      text_b,
      watershed_js.text_length(text_b),
      tail_insert,
    )

  // Exercise the append family and prove it survives the concurrent race.
  let append_result = watershed_js.text_append(text_a, append_text)

  // An index past the end must be refused rather than silently clamped.
  let out_of_bounds = watershed_js.text_insert(text_a, 9999, "x")

  use <- delay(3000)
  let final_a = watershed_js.text_value(text_a)
  let final_b = watershed_js.text_value(text_b)
  log("smoke: final A = " <> final_a)
  log("smoke: final B = " <> final_b)

  let new_pos = case anchor {
    Ok(a) ->
      case watershed_js.text_resolve_anchor(text_a, a) {
        Ok(pos) -> pos
        Error(_) -> -1
      }
    Error(_) -> -1
  }
  log("smoke: anchor now resolves to " <> int.to_string(new_pos))

  let seeded_ok = seeded_a == seed_text && seeded_a == seeded_b
  let converged = final_a == final_b && final_a != ""
  let insert_ok = insert_a == Ok(Nil)
  let insert_b_ok = insert_b == Ok(Nil)
  let append_ok = append_result == Ok(Nil)
  let rejected_ok = case out_of_bounds {
    Error(_) -> True
    Ok(Nil) -> False
  }
  // Each concurrent edit must survive the other, grapheme-for-grapheme.
  let emoji_survived = string.contains(final_a, "🌊")
  let combining_survived = string.contains(final_a, tail_insert)
  let append_survived = string.contains(final_a, "✨")
  // The anchor was pinned at 5, then A inserted 2 graphemes before it, so its
  // resolved position must have moved right.
  let anchor_moved = old_pos == 5 && new_pos > old_pos

  case
    seeded_ok
    && converged
    && insert_ok
    && insert_b_ok
    && append_ok
    && rejected_ok
    && emoji_survived
    && combining_survived
    && append_survived
    && anchor_moved
  {
    True -> {
      log("SMOKE PASS: concurrent grapheme edits converged")
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: seeded="
        <> bool_str(seeded_ok)
        <> " converged="
        <> bool_str(converged)
        <> " insert_a="
        <> bool_str(insert_ok)
        <> " insert_b="
        <> bool_str(insert_b_ok)
        <> " append="
        <> bool_str(append_ok)
        <> " out_of_bounds_rejected="
        <> bool_str(rejected_ok)
        <> " emoji_survived="
        <> bool_str(emoji_survived)
        <> " combining_survived="
        <> bool_str(combining_survived)
        <> " append_survived="
        <> bool_str(append_survived)
        <> " anchor_moved="
        <> bool_str(anchor_moved),
      )
      exit(1)
    }
  }
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

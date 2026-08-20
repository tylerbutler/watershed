//// Headless smoke test: drive two `watershed_js` clients against a live
//// floodgate dev server (`just integration-up`) from Node and assert the
//// app's two headline claims end to end:
////
//// 1. The handle-in-register round trip — a note created on A opens on B by
////    parsing the OR-map register back to a handle and resolving it.
//// 2. Race 2, the headline offline claim — both clients go offline, edit
////    different paragraphs of the same note, reconnect, and every edit
////    survives on both.
////
//// The deterministic race timing lives in `test/convergence_test.gleam`
//// against the in-memory sluice; this test only has wall-clock delays, so it
//// exercises what a live server actually round-trips through.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/option.{Some}
import gleam/string

import doc_schema
import markdown_notes_lustre/note_handle
import watershed/or_map_kernel
import watershed_js.{
  type Document, type OrMap, type OrSet, type SharedSequence, type SharedText,
  WatershedConfig,
}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

const note_name = "field notes"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.Notebook)) {
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
  let document =
    "mdnotes-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    start(doc_a, doc_b)
  }
  Nil
}

/// The three resolved channels one client needs, mirroring the app's
/// `SharedState`.
type Handles {
  Handles(notes: OrMap, tags: OrSet, order: SharedSequence)
}

/// Ensure (and, for the first caller, seed) all three channels on `doc`, in
/// the same order `markdown_notes_lustre.bootstrap_effect` does.
fn bootstrap(
  doc: Document(doc_schema.Notebook),
  label: String,
  on_ready: fn(Handles) -> Nil,
) -> Nil {
  let root = watershed_js.root_typed(doc)
  watershed_js.ensure_or_map(
    doc,
    root,
    doc_schema.notes(),
    or_map_kernel.RegisterMode,
    fn(result) {
      case result {
        Error(reason) -> fail(label <> " could not ensure notes: " <> reason)
        Ok(notes) ->
          watershed_js.ensure_or_set(doc, root, doc_schema.tags(), fn(result) {
            case result {
              Error(reason) ->
                fail(label <> " could not ensure tags: " <> reason)
              Ok(tags) ->
                watershed_js.ensure_sequence(
                  doc,
                  root,
                  doc_schema.order(),
                  fn(result) {
                    case result {
                      Error(reason) ->
                        fail(label <> " could not ensure order: " <> reason)
                      Ok(order) -> on_ready(Handles(notes:, tags:, order:))
                    }
                  },
                )
            }
          })
      }
    },
  )
}

fn fail(reason: String) -> Nil {
  log("SMOKE FAIL: " <> reason)
  exit(1)
}

fn start(
  doc_a: Document(doc_schema.Notebook),
  doc_b: Document(doc_schema.Notebook),
) -> Nil {
  // Let both handshakes land before anyone attaches a channel.
  use <- delay(2000)

  log("smoke: A seeds notes/tags/order")
  bootstrap(doc_a, "A", fn(a) {
    use <- delay(1500)
    log("smoke: B adopts notes/tags/order")
    bootstrap(doc_b, "B", fn(b) { create_and_open(doc_a, doc_b, a, b) })
  })
}

/// Claim 1: A creates the note; B opens it out of the register.
fn create_and_open(
  doc_a: Document(doc_schema.Notebook),
  doc_b: Document(doc_schema.Notebook),
  a: Handles,
  b: Handles,
) -> Nil {
  log("smoke: A creates \"" <> note_name <> "\"")
  let assert Ok(text_a) = watershed_js.create_text(doc_a)
  let assert Ok(Nil) =
    watershed_js.text_append(
      text_a,
      "# " <> note_name <> "\nfirst paragraph\n\nsecond paragraph\n",
    )
  watershed_js.or_map_set_json(
    a.notes,
    note_name,
    watershed_js.text_handle_of(text_a),
  )

  use <- delay(1500)
  log("smoke: B opens it out of the register")
  case open_note(doc_b, b) {
    Error(reason) -> fail("B could not open the note: " <> reason)
    Ok(text_b) -> {
      let round_trip =
        watershed_js.text_value(text_b) == watershed_js.text_value(text_a)
      log("  round trip converged: " <> bool_str(round_trip))
      case round_trip {
        False -> fail("round trip diverged")
        True -> offline_race(doc_a, doc_b, text_a, text_b)
      }
    }
  }
}

fn open_note(
  doc: Document(doc_schema.Notebook),
  handles: Handles,
) -> Result(SharedText, String) {
  case watershed_js.or_map_value(handles.notes, note_name) {
    Some(or_map_kernel.Register(register)) ->
      case note_handle.parse(register) {
        Ok(handle) -> watershed_js.resolve_text(doc, handle)
        Error(Nil) -> Error("register is not a handle marker")
      }
    _ -> Error("no register for " <> note_name)
  }
}

/// Claim 2 — race 2, the headline offline assertion: divergent offline edits
/// to one note reconverge losslessly on reconnect.
fn offline_race(
  doc_a: Document(doc_schema.Notebook),
  doc_b: Document(doc_schema.Notebook),
  text_a: SharedText,
  text_b: SharedText,
) -> Nil {
  log("smoke: both clients go offline and edit different paragraphs")
  watershed_js.go_offline(doc_a)
  watershed_js.go_offline(doc_b)

  // "# field notes\n" is 14 graphemes; "first paragraph" ends at 29.
  let assert Ok(Nil) = watershed_js.text_insert(text_a, 29, " (checked)")
  let assert Ok(Nil) = watershed_js.text_append(text_b, "\nthird, from b\n")

  use <- delay(1000)
  log("smoke: both reconnect")
  watershed_js.go_online(doc_a)
  watershed_js.go_online(doc_b)

  use <- delay(2500)
  let value_a = watershed_js.text_value(text_a)
  let value_b = watershed_js.text_value(text_b)
  let converged = value_a == value_b
  let a_survived = string.contains(value_a, "(checked)")
  let b_survived = string.contains(value_a, "third, from b")
  log("  converged=" <> bool_str(converged))
  log("  A's offline edit survived=" <> bool_str(a_survived))
  log("  B's offline edit survived=" <> bool_str(b_survived))

  case converged && a_survived && b_survived {
    True -> {
      log("SMOKE PASS: the note round-tripped and offline edits reconverged")
      exit(0)
    }
    False -> {
      log("SMOKE FAIL: a=" <> value_a <> " b=" <> value_b)
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

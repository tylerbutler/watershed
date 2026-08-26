//// The workspace's collaboration claims, pinned against the in-memory
//// `sluice_js` — no server, no browser. `sluice_js.settle` drains every
//// queued frame before an assertion reads the result, and
//// `watershed.go_offline`/`go_online` is the same toggle the app's button
//// calls, so an offline window here is the same offline window the demo
//// shows.
////
//// Each test here is a claim this example's README repeats. Per the plan
//// this package implements
//// (`docs/plans/2026-08-19-json-workspace-demo-plan.md`), the discipline is:
//// observe the behaviour here first, then describe it — never the reverse.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should

import doc_schema
import watershed.{type Document, type JsonOt, type SharedDirectory}
import watershed/json_ot.{type JsonValue, Key}
import watershed/sluice_js.{type Sluice}

// ── Harness ──────────────────────────────────────────────────────────────

/// A room with the workspace's one directory channel already seeded, and
/// both clients holding resolved handles to it.
///
/// The app bootstraps `tree` with `ensure_directory`, which resolves through
/// a retry loop on a timer — right in a browser, wrong here, since the
/// sluice's whole point is synchronous, deterministic delivery. The test
/// seeds the handle directly and keeps every assertion free of waiting.
fn room(
  name: String,
) -> #(
  Sluice,
  Document(doc_schema.Workspace),
  Document(doc_schema.Workspace),
  SharedDirectory,
  SharedDirectory,
) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(seed) = watershed.create_directory(doc_a)
  watershed.set_directory_field(
    watershed.root_typed(doc_a),
    doc_schema.tree(),
    seed,
  )
  sluice_js.settle(sluice)

  #(sluice, doc_a, doc_b, tree_of(doc_a), tree_of(doc_b))
}

fn tree_of(doc: Document(doc_schema.Workspace)) -> SharedDirectory {
  let assert Ok(Some(dir)) =
    watershed.resolve_directory_field(
      doc,
      watershed.root_typed(doc),
      doc_schema.tree(),
    )
  dir
}

/// Create a document exactly as the app does: create a fresh `JsonOt`, then
/// store its handle in the directory. The directory write attaches the
/// channel before it submits the value.
fn create_doc(
  doc: Document(doc_schema.Workspace),
  dir: SharedDirectory,
  path: String,
  name: String,
) -> JsonOt {
  let assert Ok(channel) = watershed.create_json_ot(doc)
  watershed.directory_set(dir, path, name, watershed.json_ot_handle_of(channel))
  channel
}

/// Open a document exactly as the app does: read the directory value, and
/// resolve it.
fn open_doc(
  doc: Document(doc_schema.Workspace),
  dir: SharedDirectory,
  path: String,
  name: String,
) -> JsonOt {
  let assert Some(value) = watershed.directory_get(dir, path, name)
  let assert Ok(channel) = watershed.resolve_json_ot(doc, value)
  channel
}

fn view(channel: JsonOt) -> JsonValue {
  option.unwrap(watershed.json_ot_view(channel), json_ot.VObject([]))
}

fn member(value: JsonValue, key: String) -> Option(JsonValue) {
  case value {
    json_ot.VObject(members) ->
      case list.key_find(members, key) {
        Ok(v) -> Some(v)
        Error(_) -> None
      }
    _ -> None
  }
}

// ── Divergent edits, one document ───────────────────────────────────────

pub fn divergent_edits_on_different_keys_converge_across_reconnect_test() {
  let #(sluice, doc_a, doc_b, dir_a, dir_b) = room("jw-divergent-edits")
  let a = create_doc(doc_a, dir_a, "/", "config")
  sluice_js.settle(sluice)
  let b = open_doc(doc_b, dir_b, "/", "config")
  sluice_js.settle(sluice)

  watershed.go_offline(doc_a)
  watershed.go_offline(doc_b)

  // Neither client can see the other's edit yet — that is what makes the two
  // writes concurrent, not merely sequential.
  watershed.submit_json_ot(a, [
    json_ot.obj_insert([Key("title")], json_ot.VString("field notes")),
  ])
  watershed.submit_json_ot(b, [
    json_ot.obj_insert([Key("version")], json_ot.VNumber(json_ot.NInt(1))),
  ])

  watershed.go_online(doc_a)
  watershed.go_online(doc_b)
  sluice_js.settle(sluice)

  // Both edits present on both clients — a register-valued map would have
  // kept one whole document and dropped the other; a JSON-OT document
  // merges the two properties instead.
  let expected =
    json_ot.VObject([
      #("title", json_ot.VString("field notes")),
      #("version", json_ot.VNumber(json_ot.NInt(1))),
    ])
  view(a) |> should.equal(expected)
  view(b) |> should.equal(expected)
}

pub fn concurrent_same_path_replacements_converge_test() {
  let #(sluice, doc_a, doc_b, dir_a, dir_b) = room("jw-same-path-replace")
  let a = create_doc(doc_a, dir_a, "/", "config")
  watershed.submit_json_ot(a, [
    json_ot.obj_insert([Key("title")], json_ot.VString("draft")),
  ])
  sluice_js.settle(sluice)
  let b = open_doc(doc_b, dir_b, "/", "config")
  sluice_js.settle(sluice)

  watershed.go_offline(doc_a)
  watershed.go_offline(doc_b)
  watershed.submit_json_ot(a, [
    json_ot.obj_replace(
      [Key("title")],
      json_ot.VString("draft"),
      json_ot.VString("from-a"),
    ),
  ])
  watershed.submit_json_ot(b, [
    json_ot.obj_replace(
      [Key("title")],
      json_ot.VString("draft"),
      json_ot.VString("from-b"),
    ),
  ])
  watershed.go_online(doc_a)
  watershed.go_online(doc_b)
  sluice_js.settle(sluice)

  view(a) |> should.equal(view(b))
  member(view(a), "title") |> should.equal(Some(json_ot.VString("from-a")))
}

// ── Concurrent increments ────────────────────────────────────────────────

pub fn concurrent_increments_land_on_the_sum_test() {
  let #(sluice, doc_a, doc_b, dir_a, dir_b) = room("jw-increments")
  let a = create_doc(doc_a, dir_a, "/", "counter")
  watershed.submit_json_ot(a, [
    json_ot.obj_insert([Key("count")], json_ot.VNumber(json_ot.NInt(0))),
  ])
  sluice_js.settle(sluice)
  let b = open_doc(doc_b, dir_b, "/", "counter")
  sluice_js.settle(sluice)

  watershed.go_offline(doc_a)
  watershed.go_offline(doc_b)
  // Two concurrent +1s, neither a read of the other's write — the read-
  // modify-write race a last-write-wins register would lose.
  watershed.submit_json_ot(a, [
    json_ot.number_add([Key("count")], json_ot.NInt(1)),
  ])
  watershed.submit_json_ot(b, [
    json_ot.number_add([Key("count")], json_ot.NInt(1)),
  ])
  watershed.go_online(doc_a)
  watershed.go_online(doc_b)
  sluice_js.settle(sluice)

  let expected = Some(json_ot.VNumber(json_ot.NInt(2)))
  member(view(a), "count") |> should.equal(expected)
  member(view(b), "count") |> should.equal(expected)
}

// ── Same-name document creation ─────────────────────────────────────────

pub fn concurrent_same_name_document_creation_converges_on_one_handle_test() {
  let #(sluice, doc_a, doc_b, dir_a, dir_b) = room("jw-same-name-create")

  watershed.go_offline(doc_a)
  watershed.go_offline(doc_b)
  let a = create_doc(doc_a, dir_a, "/", "config")
  watershed.submit_json_ot(a, [
    json_ot.obj_insert([Key("owner")], json_ot.VString("a")),
  ])
  let b = create_doc(doc_b, dir_b, "/", "config")
  watershed.submit_json_ot(b, [
    json_ot.obj_insert([Key("owner")], json_ot.VString("b")),
  ])
  watershed.go_online(doc_a)
  watershed.go_online(doc_b)
  sluice_js.settle(sluice)

  // Exactly one handle survives at the directory key, and both clients agree
  // on which.
  let assert Some(value_a) = watershed.directory_get(dir_a, "/", "config")
  let assert Some(value_b) = watershed.directory_get(dir_b, "/", "config")
  value_a |> should.equal(value_b)

  let assert Ok(winner_from_a) = watershed.resolve_json_ot(doc_a, value_a)
  let owner = member(view(winner_from_a), "owner")
  should.be_true(
    owner == Some(json_ot.VString("a")) || owner == Some(json_ot.VString("b")),
  )

  // The loser's channel is not deleted, only unreachable from the tree — its
  // creator's own handle still reads whatever it wrote.
  case owner {
    Some(json_ot.VString("a")) ->
      member(view(b), "owner") |> should.equal(Some(json_ot.VString("b")))
    _ -> member(view(a), "owner") |> should.equal(Some(json_ot.VString("a")))
  }
}

// ── Folder delete/recreate ──────────────────────────────────────────────

pub fn deleting_a_folder_does_not_break_an_already_open_document_test() {
  let #(sluice, doc_a, doc_b, dir_a, dir_b) = room("jw-delete-open")
  watershed.directory_create_subdirectory(dir_a, "/", "specs")
  sluice_js.settle(sluice)
  let a = create_doc(doc_a, dir_a, "/specs", "api")
  sluice_js.settle(sluice)
  let b = open_doc(doc_b, dir_b, "/specs", "api")
  sluice_js.settle(sluice)

  // B deletes the folder while A's document is open in an editor.
  watershed.directory_delete_subdirectory(dir_b, "/", "specs")
  sluice_js.settle(sluice)
  watershed.directory_has_subdirectory(dir_a, "/", "specs")
  |> should.be_false()

  // The channel keeps working on both sides: deleting the folder removed
  // reachability, not the document.
  watershed.submit_json_ot(a, [
    json_ot.obj_insert([Key("still")], json_ot.VString("alive")),
  ])
  sluice_js.settle(sluice)
  member(view(a), "still") |> should.equal(Some(json_ot.VString("alive")))
  member(view(b), "still") |> should.equal(Some(json_ot.VString("alive")))
}

pub fn a_stale_write_queued_before_a_delete_and_recreate_is_dropped_test() {
  let #(sluice, _doc_a, doc_b, dir_a, dir_b) = room("jw-recreate-while-held")
  watershed.directory_create_subdirectory(dir_a, "/", "specs")
  sluice_js.settle(sluice)
  watershed.directory_has_subdirectory(dir_b, "/", "specs") |> should.be_true()

  // B goes offline holding the live "/specs" and queues a write to it.
  watershed.go_offline(doc_b)
  watershed.directory_set(
    dir_b,
    "/specs",
    "draft",
    json.string("b's stale write"),
  )

  // A deletes and recreates "/specs" while B is offline — a new instance
  // under the same path.
  watershed.directory_delete_subdirectory(dir_a, "/", "specs")
  watershed.directory_create_subdirectory(dir_a, "/", "specs")
  sluice_js.settle(sluice)

  // B reconnects; its queued write targeted the instance that died while it
  // was gone, and must not graft onto the new one.
  watershed.go_online(doc_b)
  sluice_js.settle(sluice)

  watershed.directory_has_subdirectory(dir_a, "/", "specs") |> should.be_true()
  watershed.directory_get(dir_a, "/specs", "draft") |> should.equal(None)
  watershed.directory_get(dir_b, "/specs", "draft") |> should.equal(None)
}

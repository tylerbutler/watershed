//// Controller-only persistence tests.
////
//// The save seam is injected, so an in-flight write can be released when the
//// test chooses. That makes the `pagehide` follow-up path deterministic
//// without depending on browser storage timing.
////
//// JavaScript target only.

@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import startest/expect

@target(javascript)
import watershed/channel
@target(javascript)
import watershed/crdt_core
@target(javascript)
import watershed/crdt_js.{type Config, type CrdtDocument}
@target(javascript)
import watershed/or_map_kernel
@target(javascript)
import watershed/p2p
@target(javascript)
import watershed/p2p_fake
@target(javascript)
import watershed/persist_controller_js
@target(javascript)
import watershed/persist_js
@target(javascript)
import watershed/relay_fake
@target(javascript)
import watershed/schema.{type GSetChannel}
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/wire

const room = "persist-controller-room"

const compatibility = "persist-controller-test/v1"

@target(javascript)
pub fn set_map_controller_saves_eventless_metadata_and_stops_test() -> Nil {
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "set-map-controller",
      compatibility_tag: compatibility,
      root: p2p.or_map_root(or_map_kernel.OrSetMode),
      signaling: p2p_fake.signaling(p2p_fake.new_world()),
    ))
  let map = crdt_js.root(document)
  crdt_js.or_map_add_member(map, "doc", "draft") |> expect.to_equal(Ok(Nil))
  let assert Ok(initial) = crdt_js.export_snapshot(document)
  let snapshots = transport_js.new_cell([])
  let events = transport_js.new_cell([])
  let subscription =
    crdt_js.subscribe_or_map(map, fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  let clock = relay_fake.new_clock()
  let removed_listener = transport_js.new_cell(False)
  let controller =
    persist_controller_js.start_with_save(
      document,
      fn(_) { Nil },
      relay_fake.scheduler(clock),
      fn(_) { fn() { transport_js.set_cell(removed_listener, True) } },
      fn(document, done) {
        let assert Ok(snapshot) = crdt_js.export_snapshot(document)
        transport_js.set_cell(snapshots, [
          snapshot,
          ..transport_js.get_cell(snapshots)
        ])
        done(Ok(crdt_js.digest(document)))
      },
    )
  relay_fake.advance(clock, 500)
  transport_js.get_cell(snapshots) |> expect.to_equal([initial])
  let before = crdt_js.digest(document)
  crdt_js.or_map_add_member(map, "doc", "draft") |> expect.to_equal(Ok(Nil))
  crdt_js.digest(document) |> expect.to_not_equal(before)
  transport_js.get_cell(events) |> expect.to_equal([])
  let assert Ok(updated) = crdt_js.export_snapshot(document)
  // No visible callback calls changed; the digest sweep must find the tag.
  relay_fake.advance(clock, 5000)
  transport_js.get_cell(snapshots) |> expect.to_equal([updated, initial])
  crdt_js.or_map_remove_member(map, "missing", "draft")
  |> expect.to_equal(Ok(Nil))
  persist_controller_js.changed(controller)
  relay_fake.advance(clock, 500)
  transport_js.get_cell(snapshots) |> expect.to_equal([updated, initial])
  persist_controller_js.stop(controller)
  transport_js.get_cell(removed_listener) |> expect.to_be_true()
  crdt_js.or_map_remove_key(map, "doc") |> expect.to_equal(Ok(Nil))
  relay_fake.advance(clock, 10_000)
  transport_js.get_cell(snapshots) |> expect.to_equal([updated, initial])
  crdt_js.unsubscribe(subscription)
}

@target(javascript)
type Attempt {
  Attempt(values: List(String))
}

@target(javascript)
type Pending {
  Pending(
    digest: String,
    done: fn(Result(String, persist_js.PersistenceError)) -> Nil,
  )
}

@target(javascript)
type DeferredSave {
  DeferredSave(
    attempts: transport_js.Cell(List(Attempt)),
    pending: transport_js.Cell(List(Pending)),
  )
}

@target(javascript)
type Harness {
  Harness(
    controller: persist_controller_js.Controller(GSetChannel),
    clock: relay_fake.Clock,
    pagehide: transport_js.Cell(fn() -> Nil),
    statuses: transport_js.Cell(List(String)),
  )
}

@target(javascript)
fn config() -> Config(GSetChannel) {
  crdt_js.config(
    room_id: room,
    replica_label: "persist-controller-test",
    compatibility_tag: compatibility,
    root: p2p.g_set_root(),
    signaling: p2p_fake.signaling(p2p_fake.new_world()),
  )
}

@target(javascript)
fn new_document() -> CrdtDocument(GSetChannel) {
  let assert Ok(document) = crdt_js.new_document(config())
  document
}

@target(javascript)
fn deferred_save() -> DeferredSave {
  DeferredSave(
    attempts: transport_js.new_cell([]),
    pending: transport_js.new_cell([]),
  )
}

@target(javascript)
fn save_driver(
  deferred: DeferredSave,
) -> fn(
  CrdtDocument(GSetChannel),
  fn(Result(String, persist_js.PersistenceError)) -> Nil,
) -> Nil {
  fn(document, done) {
    let assert Ok(values) = crdt_js.g_set_values(crdt_js.root(document))
    let DeferredSave(attempts:, pending:) = deferred
    transport_js.set_cell(attempts, [
      Attempt(values:),
      ..transport_js.get_cell(attempts)
    ])
    transport_js.set_cell(pending, [
      Pending(digest: crdt_js.digest(document), done:),
      ..transport_js.get_cell(pending)
    ])
  }
}

@target(javascript)
fn start_harness(
  document: CrdtDocument(GSetChannel),
  deferred: DeferredSave,
) -> Harness {
  let clock = relay_fake.new_clock()
  let pagehide = transport_js.new_cell(fn() { Nil })
  let statuses = transport_js.new_cell([])
  let controller =
    persist_controller_js.start_with_save(
      document,
      fn(status) {
        transport_js.set_cell(statuses, [
          status_name(status),
          ..transport_js.get_cell(statuses)
        ])
      },
      relay_fake.scheduler(clock),
      fn(action) {
        transport_js.set_cell(pagehide, action)
        fn() { Nil }
      },
      save_driver(deferred),
    )
  Harness(controller:, clock:, pagehide:, statuses:)
}

@target(javascript)
fn attempts(deferred: DeferredSave) -> List(List(String)) {
  let DeferredSave(attempts:, ..) = deferred
  transport_js.get_cell(attempts)
  |> list.reverse
  |> list.map(fn(attempt) { attempt.values })
}

@target(javascript)
fn pending_count(deferred: DeferredSave) -> Int {
  let DeferredSave(pending:, ..) = deferred
  transport_js.get_cell(pending) |> list.length
}

@target(javascript)
fn release_saved(deferred: DeferredSave) -> Nil {
  let DeferredSave(pending:, ..) = deferred
  let assert [Pending(digest:, done: done), ..rest] =
    transport_js.get_cell(pending)
  transport_js.set_cell(pending, rest)
  done(Ok(digest))
}

@target(javascript)
fn statuses(harness: Harness) -> List(String) {
  transport_js.get_cell(harness.statuses) |> list.reverse
}

@target(javascript)
fn status_name(status: persist_controller_js.Status) -> String {
  case status {
    persist_controller_js.Saving -> "saving"
    persist_controller_js.Saved(_) -> "saved"
    persist_controller_js.SaveFailed(_) -> "failed"
  }
}

@target(javascript)
pub fn pagehide_during_an_active_save_runs_an_immediate_followup_test() -> Nil {
  let document = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "first")
  let deferred = deferred_save()
  let harness = start_harness(document, deferred)

  relay_fake.advance(harness.clock, 500)
  attempts(deferred) |> expect.to_equal([["first"]])
  pending_count(deferred) |> expect.to_equal(1)
  statuses(harness) |> expect.to_equal(["saving"])

  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "second")
  persist_controller_js.changed(harness.controller)
  transport_js.get_cell(harness.pagehide)()

  attempts(deferred) |> expect.to_equal([["first"]])
  pending_count(deferred) |> expect.to_equal(1)

  release_saved(deferred)

  attempts(deferred)
  |> expect.to_equal([["first"], ["first", "second"]])
  pending_count(deferred) |> expect.to_equal(1)
  statuses(harness) |> expect.to_equal(["saving", "saved", "saving"])

  release_saved(deferred)

  pending_count(deferred) |> expect.to_equal(0)
  statuses(harness) |> expect.to_equal(["saving", "saved", "saving", "saved"])
}

@target(javascript)
pub fn pagehide_during_an_active_save_skips_a_redundant_followup_test() -> Nil {
  let document = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "only")
  let deferred = deferred_save()
  let harness = start_harness(document, deferred)

  relay_fake.advance(harness.clock, 500)
  attempts(deferred) |> expect.to_equal([["only"]])
  pending_count(deferred) |> expect.to_equal(1)

  transport_js.get_cell(harness.pagehide)()
  release_saved(deferred)

  attempts(deferred) |> expect.to_equal([["only"]])
  pending_count(deferred) |> expect.to_equal(0)
  statuses(harness) |> expect.to_equal(["saving", "saved"])
}

@target(javascript)
pub fn lww_map_metadata_only_remote_merge_is_saved_by_digest_sweep_test() -> Nil {
  let document = new_document()
  let assert Ok(source) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: compatibility,
      replica: "source",
      session: "source-session",
      root: channel.InitGSet,
    ))
  let assert Ok(#(source, created)) =
    crdt_core.create_channel(source, channel.InitLwwMap)
  let assert [descriptor] = created.created
  let assert Ok(#(source, _)) =
    crdt_core.edit(
      source,
      descriptor.address,
      channel.LwwMapRemoveEdit("gone", 100),
    )
  let assert Ok(snapshot) =
    json.parse(crdt_core.canonical_json(source), wire.json_value_decoder())
  let assert Ok(_) = crdt_js.merge_snapshot(document, snapshot)
  let deferred = deferred_save()
  let harness = start_harness(document, deferred)
  relay_fake.advance(harness.clock, 500)
  release_saved(deferred)
  let before = crdt_js.digest(document)
  let assert Ok(#(source, _)) =
    crdt_core.edit(
      source,
      descriptor.address,
      channel.LwwMapRemoveEdit("gone", 200),
    )
  let assert Ok(snapshot) =
    json.parse(crdt_core.canonical_json(source), wire.json_value_decoder())
  let assert Ok(outcome) = crdt_js.merge_snapshot(document, snapshot)
  outcome.events |> expect.to_equal([])
  crdt_js.digest(document) |> expect.to_not_equal(before)
  // No event calls `changed`; the periodic digest sweep must find this edit.
  relay_fake.advance(harness.clock, 5000)
  attempts(deferred) |> expect.to_equal([[], []])
  let DeferredSave(pending:, ..) = deferred
  let assert [Pending(digest:, ..)] = transport_js.get_cell(pending)
  digest |> expect.to_equal(crdt_js.digest(document))
  release_saved(deferred)
  persist_controller_js.stop(harness.controller)
}

@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import startest/expect

@target(javascript)
import watershed/crdt_js.{type Config, type CrdtDocument}
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
import watershed/transport_js.{type Cell}

@target(javascript)
const room = "persist-room"

@target(javascript)
const compatibility = "persist-test/v1"

@target(javascript)
type UpdateMode {
  RunImmediately
  QueueManually
}

@target(javascript)
type PendingUpdate {
  PendingUpdate(run: fn() -> Nil)
}

@target(javascript)
type UpdateDecision {
  WriteSnapshot(String)
  AbortUpdate
  NoDecision
}

@target(javascript)
type Memory {
  Memory(
    value: Cell(Option(String)),
    fail_write: Bool,
    mode: UpdateMode,
    pending_updates: Cell(List(PendingUpdate)),
  )
}

@target(javascript)
fn memory(initial: Option(String), fail_write: Bool) -> Memory {
  Memory(
    value: transport_js.new_cell(initial),
    fail_write: fail_write,
    mode: RunImmediately,
    pending_updates: transport_js.new_cell([]),
  )
}

@target(javascript)
fn queued_memory(initial: Option(String)) -> Memory {
  Memory(
    value: transport_js.new_cell(initial),
    fail_write: False,
    mode: QueueManually,
    pending_updates: transport_js.new_cell([]),
  )
}

@target(javascript)
fn memory_storage(memory: Memory) -> persist_js.Storage {
  persist_js.storage(
    get: fn(_key, done) {
      let Memory(value:, ..) = memory
      done(Ok(transport_js.get_cell(value)))
    },
    update: fn(_key, transform, on_ok, on_abort, on_error) {
      let Memory(mode:, pending_updates:, ..) = memory
      let update =
        PendingUpdate(run: fn() {
          run_update(memory, transform, on_ok, on_abort, on_error)
        })
      case mode {
        RunImmediately -> {
          let PendingUpdate(run:) = update
          run()
        }
        QueueManually ->
          transport_js.set_cell(
            pending_updates,
            list.append(transport_js.get_cell(pending_updates), [update]),
          )
      }
    },
  )
}

@target(javascript)
fn run_update(
  memory: Memory,
  transform: fn(Bool, String, fn(String) -> Nil, fn() -> Nil) -> Nil,
  on_ok: fn() -> Nil,
  on_abort: fn() -> Nil,
  on_error: fn(String) -> Nil,
) -> Nil {
  let Memory(value:, fail_write:, ..) = memory
  let current = transport_js.get_cell(value)
  let decision = transport_js.new_cell(NoDecision)
  transform(
    case current {
      Some(_) -> True
      None -> False
    },
    case current {
      Some(raw) -> raw
      None -> ""
    },
    fn(snapshot) { decide(decision, WriteSnapshot(snapshot)) },
    fn() { decide(decision, AbortUpdate) },
  )
  case transport_js.get_cell(decision) {
    WriteSnapshot(snapshot) ->
      case fail_write {
        True -> on_error("quota exceeded")
        False -> {
          transport_js.set_cell(value, Some(snapshot))
          on_ok()
        }
      }
    AbortUpdate -> on_abort()
    NoDecision -> on_error("memory storage update did not write or abort")
  }
}

@target(javascript)
fn decide(decision: Cell(UpdateDecision), next: UpdateDecision) -> Nil {
  case transport_js.get_cell(decision) {
    NoDecision -> transport_js.set_cell(decision, next)
    WriteSnapshot(_) | AbortUpdate -> Nil
  }
}

@target(javascript)
fn run_next_update(memory: Memory) -> Nil {
  let Memory(pending_updates:, ..) = memory
  case transport_js.get_cell(pending_updates) {
    [] -> Nil
    [PendingUpdate(run: run), ..rest] -> {
      transport_js.set_cell(pending_updates, rest)
      run()
    }
  }
}

@target(javascript)
fn config() -> Config(GSetChannel) {
  crdt_js.config(
    room_id: room,
    replica_label: "persist-test",
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
pub fn an_empty_store_loads_none_test() -> Nil {
  let store = memory(None, False)
  let seen = transport_js.new_cell(None)
  persist_js.load(memory_storage(store), config(), fn(result) {
    transport_js.set_cell(seen, Some(result))
  })
  transport_js.get_cell(seen) |> expect.to_equal(Some(Ok(None)))
}

@target(javascript)
pub fn a_snapshot_saves_and_loads_test() -> Nil {
  let store = memory(None, False)
  let document = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "local")
  let saved = transport_js.new_cell(None)
  persist_js.save(memory_storage(store), document, fn(result) {
    transport_js.set_cell(saved, Some(result))
  })
  let assert Some(Ok(_digest)) = transport_js.get_cell(saved)

  let loaded = transport_js.new_cell(None)
  persist_js.load(memory_storage(store), config(), fn(result) {
    transport_js.set_cell(loaded, Some(result))
  })
  let assert Some(Ok(Some(restored))) = transport_js.get_cell(loaded)
  crdt_js.g_set_values(crdt_js.root(restored))
  |> expect.to_equal(Ok(["local"]))
}

@target(javascript)
pub fn save_joins_the_latest_disk_snapshot_test() -> Nil {
  let store = memory(None, False)
  let first = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(first), "first")
  persist_js.save(memory_storage(store), first, fn(_) { Nil })

  let second = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(second), "second")
  persist_js.save(memory_storage(store), second, fn(_) { Nil })

  let loaded = transport_js.new_cell(None)
  persist_js.load(memory_storage(store), config(), fn(result) {
    transport_js.set_cell(loaded, Some(result))
  })
  let assert Some(Ok(Some(restored))) = transport_js.get_cell(loaded)
  crdt_js.g_set_values(crdt_js.root(restored))
  |> expect.to_equal(Ok(["first", "second"]))
}

@target(javascript)
pub fn concurrent_saves_share_the_latest_snapshot_test() -> Nil {
  let store = queued_memory(None)
  let first = new_document()
  let second = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(first), "first")
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(second), "second")

  let first_saved = transport_js.new_cell(None)
  let second_saved = transport_js.new_cell(None)
  persist_js.save(memory_storage(store), first, fn(result) {
    transport_js.set_cell(first_saved, Some(result))
  })
  persist_js.save(memory_storage(store), second, fn(result) {
    transport_js.set_cell(second_saved, Some(result))
  })

  transport_js.get_cell(first_saved) |> expect.to_equal(None)
  transport_js.get_cell(second_saved) |> expect.to_equal(None)

  run_next_update(store)
  let assert Some(Ok(_)) = transport_js.get_cell(first_saved)
  transport_js.get_cell(second_saved) |> expect.to_equal(None)

  run_next_update(store)
  let assert Some(Ok(_)) = transport_js.get_cell(second_saved)

  let loaded = transport_js.new_cell(None)
  persist_js.load(memory_storage(store), config(), fn(result) {
    transport_js.set_cell(loaded, Some(result))
  })
  let assert Some(Ok(Some(restored))) = transport_js.get_cell(loaded)
  crdt_js.g_set_values(crdt_js.root(restored))
  |> expect.to_equal(Ok(["first", "second"]))
}

@target(javascript)
pub fn corrupt_bytes_are_reported_and_retained_test() -> Nil {
  let store = memory(Some("{not-json"), False)
  let seen = transport_js.new_cell(None)
  persist_js.load(memory_storage(store), config(), fn(result) {
    transport_js.set_cell(seen, Some(result))
  })
  let assert Some(Error(persist_js.SnapshotDecodeFailure(_))) =
    transport_js.get_cell(seen)
  let Memory(value:, ..) = store
  transport_js.get_cell(value) |> expect.to_equal(Some("{not-json"))
}

@target(javascript)
pub fn save_against_corrupt_bytes_fails_and_retains_existing_bytes_test() -> Nil {
  let store = memory(Some("{not-json"), False)
  let document = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "local")
  let seen = transport_js.new_cell(None)
  persist_js.save(memory_storage(store), document, fn(result) {
    transport_js.set_cell(seen, Some(result))
  })
  let assert Some(Error(persist_js.SnapshotDecodeFailure(_))) =
    transport_js.get_cell(seen)
  let Memory(value:, ..) = store
  transport_js.get_cell(value) |> expect.to_equal(Some("{not-json"))
}

@target(javascript)
pub fn replace_succeeds_against_corrupt_bytes_and_loads_the_current_state_test() -> Nil {
  let store = memory(Some("{not-json"), False)
  let document = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "local")

  let saved = transport_js.new_cell(None)
  persist_js.replace(memory_storage(store), document, fn(result) {
    transport_js.set_cell(saved, Some(result))
  })
  let assert Some(Ok(_digest)) = transport_js.get_cell(saved)

  let loaded = transport_js.new_cell(None)
  persist_js.load(memory_storage(store), config(), fn(result) {
    transport_js.set_cell(loaded, Some(result))
  })
  let assert Some(Ok(Some(restored))) = transport_js.get_cell(loaded)
  crdt_js.g_set_values(crdt_js.root(restored))
  |> expect.to_equal(Ok(["local"]))
}

@target(javascript)
pub fn a_failed_write_is_not_reported_as_saved_test() -> Nil {
  let store = memory(None, True)
  let seen = transport_js.new_cell(None)
  persist_js.save(memory_storage(store), new_document(), fn(result) {
    transport_js.set_cell(seen, Some(result))
  })
  let assert Some(Error(persist_js.StorageFailure("quota exceeded"))) =
    transport_js.get_cell(seen)
  Nil
}

@target(javascript)
pub fn replace_write_failures_still_surface_test() -> Nil {
  let store = memory(Some("{not-json"), True)
  let document = new_document()
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "local")
  let seen = transport_js.new_cell(None)
  persist_js.replace(memory_storage(store), document, fn(result) {
    transport_js.set_cell(seen, Some(result))
  })
  let assert Some(Error(persist_js.StorageFailure("quota exceeded"))) =
    transport_js.get_cell(seen)
  let Memory(value:, ..) = store
  transport_js.get_cell(value) |> expect.to_equal(Some("{not-json"))
}

@target(javascript)
pub fn the_controller_debounces_and_sweeps_remote_changes_test() -> Nil {
  let store = memory(None, False)
  let document = new_document()
  let clock = relay_fake.new_clock()
  let statuses = transport_js.new_cell([])
  let pagehide = transport_js.new_cell(fn() { Nil })
  let _controller =
    persist_controller_js.start_with(
      memory_storage(store),
      document,
      fn(status) {
        transport_js.set_cell(statuses, [
          case status {
            persist_controller_js.Saving -> "saving"
            persist_controller_js.Saved(_) -> "saved"
            persist_controller_js.SaveFailed(_) -> "failed"
          },
          ..transport_js.get_cell(statuses)
        ])
      },
      relay_fake.scheduler(clock),
      fn(action) {
        transport_js.set_cell(pagehide, action)
        fn() { Nil }
      },
    )

  relay_fake.advance(clock, 499)
  let Memory(value:, ..) = store
  transport_js.get_cell(value) |> expect.to_equal(None)
  relay_fake.advance(clock, 1)
  transport_js.get_cell(value) |> expect.to_not_equal(None)

  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "remote")
  relay_fake.advance(clock, 5000)
  list.reverse(transport_js.get_cell(statuses))
  |> expect.to_equal(["saving", "saved", "saving", "saved"])
}

@target(javascript)
pub fn pagehide_attempts_the_last_changed_snapshot_test() -> Nil {
  let store = memory(None, False)
  let document = new_document()
  let clock = relay_fake.new_clock()
  let pagehide = transport_js.new_cell(fn() { Nil })
  let controller =
    persist_controller_js.start_with(
      memory_storage(store),
      document,
      fn(_) { Nil },
      relay_fake.scheduler(clock),
      fn(action) {
        transport_js.set_cell(pagehide, action)
        fn() { Nil }
      },
    )
  relay_fake.advance(clock, 500)
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(document), "last")
  persist_controller_js.changed(controller)
  transport_js.get_cell(pagehide)()

  let Memory(value:, ..) = store
  transport_js.get_cell(value) |> expect.to_not_equal(None)
}

//// Headless smoke test: drive two `watershed` clients against a live
//// floodgate dev server (`just integration-up`) from Node and assert the two
//// claims the dispatch board stands on, end to end through the real server:
////
//// 1. A claim resolves through consensus — B acquires the job A dispatched,
////    completes it, and both replicas agree the board is clear.
//// 2. A dying client cannot take its work with it — A acquires a job and
////    holds the dispatcher role, then its socket is torn down without a
////    goodbye. The server's sequenced `"leave"` must return the job to the
////    queue *and* pass the role to B, with no client code participating.
////
//// The second phase is the payload: it is the one behaviour that cannot be
//// proven by the in-process tests, because it depends on floodgate actually
//// emitting the leave for a vanished socket.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/list

import watershed.{
  type Document, type OrderedCollection, type TaskManager, WatershedConfig,
}
import watershed/ordered_collection_kernel.{AcquiredItem}
import watershed/transport_js

import work_queue_lustre/document_schema

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

const role = "dispatcher"

/// Matches the ~100 × 250 ms budget the repo's own integration suite gives the
/// server to sequence a leave after an ungraceful close.
const leave_poll_attempts = 100

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(milliseconds: Int, callback: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(document_schema.Dispatch)) {
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
  let document = "wq-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use document_a <- promise.await(connect_client(document, "user-a"))
    use document_b <- promise.map(connect_client(document, "user-b"))
    bootstrap(document_a, document_b)
  }
  Nil
}

/// A ensures both consensus channels; B adopts the handles A published.
fn bootstrap(
  document_a: Document(document_schema.Dispatch),
  document_b: Document(document_schema.Dispatch),
) -> Nil {
  use <- delay(2000)
  log("smoke: ensuring the queue and roles channels on A")
  use queue_a <- ensure_queue(document_a, "A")
  use roles_a <- ensure_roles(document_a, "A")
  use <- delay(1500)
  use queue_b <- ensure_queue(document_b, "B")
  use roles_b <- ensure_roles(document_b, "B")
  dispatch_phase(document_a, queue_a, roles_a, queue_b, roles_b)
}

/// Phase 1: A takes the dispatcher role and dispatches a job; B claims it
/// through consensus and completes it.
fn dispatch_phase(
  document_a: Document(document_schema.Dispatch),
  queue_a: OrderedCollection,
  roles_a: TaskManager,
  queue_b: OrderedCollection,
  roles_b: TaskManager,
) -> Nil {
  log("smoke: A volunteers as dispatcher and adds a job")
  let _ = watershed.volunteer_for_task(roles_a, role)
  watershed.ordered_add(queue_a, job("job-1"))

  use seeded <- wait_until(20, fn() {
    watershed.ordered_queue(queue_b) == [job("job-1")]
    && watershed.task_assigned(roles_a, role)
  })
  case seeded {
    False -> fail("B never saw the dispatched job")
    True -> {
      log("smoke: B claims the job")
      let outcomes = transport_js.new_cell([])
      let _id =
        watershed.ordered_acquire_with_outcome(queue_b, fn(outcome) {
          transport_js.set_cell(outcomes, [outcome])
        })
      use claimed <- wait_until(20, fn() {
        case transport_js.get_cell(outcomes) {
          [AcquiredItem(acquire_id, _)] -> {
            watershed.ordered_complete(queue_b, acquire_id)
            True
          }
          _ -> False
        }
      })
      case claimed {
        False -> fail("B's claim never resolved to AcquiredItem")
        True -> {
          use cleared <- wait_until(20, fn() {
            watershed.ordered_size(queue_a) == Ok(0)
            && watershed.ordered_jobs(queue_a) == []
            && watershed.ordered_jobs(queue_b) == []
          })
          case cleared {
            False -> fail("the completed job never left both replicas")
            True -> kill_phase(document_a, queue_a, roles_a, queue_b, roles_b)
          }
        }
      }
    }
  }
}

/// Phase 2: B queues as backup dispatcher; A acquires a job and then its
/// socket is torn down without a goodbye. The server's sequenced leave must
/// return the job and hand over the role.
fn kill_phase(
  document_a: Document(document_schema.Dispatch),
  queue_a: OrderedCollection,
  roles_a: TaskManager,
  queue_b: OrderedCollection,
  roles_b: TaskManager,
) -> Nil {
  log("smoke: B queues as backup; A takes a job and dies mid-work")
  let _ = watershed.volunteer_for_task(roles_b, role)
  watershed.ordered_add(queue_a, job("job-2"))
  let _id = watershed.ordered_acquire(queue_a)

  use held <- wait_until(20, fn() {
    watershed.ordered_jobs(queue_b) != []
    && watershed.task_queued(roles_b, role)
  })
  case held {
    False -> fail("A never held job-2 in B's replica")
    True -> {
      // Tear the socket down and keep it down — an ungraceful death, not a
      // clean leave. Everything after this is the server's doing.
      watershed.force_reconnect(document_a)
      watershed.close(document_a)
      let _ = roles_a
      let _ = queue_a

      use recovered <- wait_until(leave_poll_attempts, fn() {
        watershed.ordered_queue(queue_b) == [job("job-2")]
        && watershed.ordered_jobs(queue_b) == []
        && watershed.task_assigned(roles_b, role)
      })
      case recovered {
        False ->
          fail(
            "the server's leave never returned the job and the role to B "
            <> "(queue="
            <> int.to_string(list.length(watershed.ordered_queue(queue_b)))
            <> " jobs="
            <> int.to_string(list.length(watershed.ordered_jobs(queue_b)))
            <> " dispatcher="
            <> bool_to_string(watershed.task_assigned(roles_b, role))
            <> ")",
          )
        True -> {
          log(
            "SMOKE PASS: the claim resolved through consensus, and the dead "
            <> "client's job and role both came back on their own",
          )
          exit(0)
        }
      }
    }
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn ensure_queue(
  document: Document(document_schema.Dispatch),
  who: String,
  then: fn(OrderedCollection) -> Nil,
) -> Nil {
  watershed.ensure_ordered_collection(
    document,
    watershed.root_typed(document),
    document_schema.queue(),
    fn(result) {
      case result {
        Ok(queue) -> then(queue)
        Error(reason) -> fail(who <> " could not ensure the queue: " <> reason)
      }
    },
  )
}

fn ensure_roles(
  document: Document(document_schema.Dispatch),
  who: String,
  then: fn(TaskManager) -> Nil,
) -> Nil {
  watershed.ensure_task_manager(
    document,
    watershed.root_typed(document),
    document_schema.roles(),
    fn(result) {
      case result {
        Ok(roles) -> then(roles)
        Error(reason) ->
          fail(who <> " could not ensure the roles channel: " <> reason)
      }
    },
  )
}

/// Poll `check` every 250 ms up to `attempts` times, then hand the verdict on.
fn wait_until(
  attempts: Int,
  check: fn() -> Bool,
  then: fn(Bool) -> Nil,
) -> Nil {
  case check() {
    True -> then(True)
    False ->
      case attempts <= 0 {
        True -> then(False)
        False -> {
          use <- delay(250)
          wait_until(attempts - 1, check, then)
        }
      }
  }
}

fn job(id: String) -> Json {
  json.object([
    #("id", json.string(id)),
    #("label", json.string(id)),
    #("created_by", json.string("smoke")),
  ])
}

fn fail(reason: String) -> Nil {
  log("SMOKE FAIL: " <> reason)
  exit(1)
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

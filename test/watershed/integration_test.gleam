//// Live integration test against a floodgate dev server (M3 exit criterion:
//// two Gleam clients converge on concurrent edits).
////
//// Gated behind `WATERSHED_INTEGRATION=1` so the suite stays green without
//// a server. Start the server from `docker-compose.yml`, which seeds the
//// `tenant` / `tenant_secret` pair below:
////
//// ```sh
//// just integration-up
//// WATERSHED_INTEGRATION=1 gleam test
//// ```
////
//// Or `just integration` for the whole cycle, teardown included.

@target(erlang)
import envoy
@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/crypto
@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/charlist.{type Charlist}
@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/int
@target(erlang)
import gleam/io
@target(erlang)
import gleam/json.{type Json}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/string
@target(erlang)
import startest/expect

@target(erlang)
import watershed
@target(erlang)
import watershed/channel
@target(erlang)
import watershed/claims_kernel
@target(erlang)
import watershed/client_id
@target(erlang)
import watershed/counter_kernel
@target(erlang)
import watershed/git_storage
@target(erlang)
import watershed/handle
@target(erlang)
import watershed/json_ot
@target(erlang)
import watershed/map_kernel
@target(erlang)
import watershed/or_map_kernel.{Register, RegisterMode, Tally, TallyMode}
@target(erlang)
import watershed/pact_map_kernel
@target(erlang)
import watershed/pn_counter_kernel
@target(erlang)
import watershed/rich_text
@target(erlang)
import watershed/runtime
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/summary_policy

@target(erlang)
const tenant = "dev-tenant"

@target(erlang)
const tenant_secret = "levee-dev-secret-change-in-production"

// Use the IPv4 loopback literal, not "localhost". Erlang's inet resolver
// (httpc/gun default to the `inet6fb4` family) stalls ~8s resolving AAAA for
// "localhost" before falling back to IPv4, which would block the runtime actor
// long enough for the server to drop the socket as idle.
@target(erlang)
const host = "127.0.0.1"

@target(erlang)
const port = 4000

@target(erlang)
pub fn two_clients_converge_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_convergence_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Quorum exit criterion: a `PactMap` set must stay pending until every
/// connected client signs off — including a third client that neither proposed
/// nor is the local replica.
///
/// Three clients, not two. With two, a quorum that ignores the roster and names
/// only `[self, author]` is indistinguishable from a correct one, because self
/// and author are the whole room; the bug this pins passed a two-client test.
pub fn pact_map_quorum_spans_the_room_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_pact_map_quorum_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// The failure mode that decides whether this protocol is usable in
/// production: a client in the signoff list vanishes without a clean leave. Its
/// signoff can never arrive, so the pending entry must drain via the server's
/// sequenced `"leave"` rather than wedging forever.
pub fn pact_map_pending_drains_on_ungraceful_disconnect_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_pact_map_disconnect_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// The client half of levee#85: every `join` in the durable op log must end up
/// with a matching `leave`, or a client that reconstructs membership by
/// replaying the log derives a roster containing clients that are not there and
/// never will be — and a `PactMap` proposal frozen against that roster waits
/// forever on signoffs that can never arrive.
///
/// The server's own tests cover the repair; they cannot cover what a
/// *replaying client* derives from the repaired log, which is the half that
/// lives here.
///
/// Gated separately from `WATERSHED_INTEGRATION` because it needs the durable
/// storage backend: under the default in-memory backend a restart discards the
/// document, so there is no log to replay and the test would pass without
/// testing anything. See `docker-compose.persistent.yml`, or run
/// `just integration-restart`.
pub fn ghost_members_do_not_survive_a_server_restart_test() {
  case envoy.get("WATERSHED_INTEGRATION_RESTART") {
    Ok("1") -> run_restart_ghost_test()
    _ ->
      io.println(
        "  (skipped: set WATERSHED_INTEGRATION_RESTART=1 and use the"
        <> " persistent backend to run live)",
      )
  }
}

@target(erlang)
/// M4 exit criterion: drop a client's channel mid-burst and assert both
/// clients still converge with no lost or duplicated ops.
pub fn reconnect_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_reconnect_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Reconnect into a room where nobody writes afterwards.
///
/// The distinction from `reconnect_converges_test` is the *absence* of traffic
/// after the drop: that test has B editing and C joining once A is back, either
/// of which supplies the out-of-order op that drives the reactive catch-up.
///
/// **This does not gate the catch-up fix, and it is worth knowing why.** Both
/// this and `reconnect_with_nothing_missed_settles_test` pass against floodgate
/// with the handshake's `requestOps` removed — verified, not assumed. The BEAM
/// transport rebuilds its socket immediately, so A is back before the server
/// has finished tearing the old one down, and the `leave` floodgate then
/// sequences for A's *previous* identity is broadcast to the whole topic — A's
/// new socket included. That is the only sequenced op in flight here, so it is
/// necessarily what advances `last_seen` to the checkpoint. The JS transport
/// rejoins on Phoenix's backoff instead, which opens a gap wide enough that the
/// `leave` is sequenced and gone before the client is listening again, which is
/// why `test/live_js.gleam` fails without the fix and this does not.
///
/// It is kept for the shape, not the gate: a laptop lid closed and reopened on
/// a quiet document is what a real app hits constantly, and nothing else here
/// covers it. The gate for this defect is `test/live_js.gleam` live, and the
/// sluice reconnect tests offline.
pub fn reconnect_into_a_quiet_room_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_reconnect_quiet_room_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// The same shape with an empty gap: reconnect, and let *nothing at all* happen.
///
/// Floodgate sequences the rejoining client's own `join` and reports that SN as
/// the handshake checkpoint, so a reconnect is behind its checkpoint even when
/// it missed no application traffic — an empty gap that still has to be closed.
/// On JS this wedges without the fix; see the note on
/// `reconnect_into_a_quiet_room_test` for why BEAM recovers here regardless.
pub fn reconnect_with_nothing_missed_settles_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_reconnect_nothing_missed_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Summaries exit criterion: a client summarizes the map, then a fresh client
/// bootstraps from the summary (its history starts above SN 1) and converges.
pub fn summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// SB4 exit criterion: with a policy installed, a checkpoint is written with
/// nothing in the application calling `summarize`, and a fresh client
/// bootstraps from it.
pub fn auto_summary_writes_without_an_explicit_call_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_auto_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A peer's summary is announced to the room, which is what lets the jitter
/// window *cancel* rather than merely stagger.
///
/// The policy spreads a room's attempts over a window on the bet that the first
/// summary sequenced will stand the others down — and that only works if the
/// summarize op comes back identified as one. It does: floodgate sequences and
/// broadcasts it, and `runtime_core` records its sequence number as the
/// checkpoint. So a room writes one summary per crossing, not one per client.
///
/// If this ever fails, the policy still works; it just costs N summaries per
/// crossing instead of one.
pub fn a_peers_summary_resets_the_local_threshold_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_peer_summary_visibility_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Pagination exit criterion: a document with more ops than the server's
/// in-band history window (1000 messages) serves `initialMessages` missing
/// its prefix, so a fresh client must page the gap from the deltas REST
/// endpoint during bootstrap.
pub fn large_history_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_large_history_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// getVersions exit criterion: every summarize stores a version; the client
/// lists them newest first and reads any historical snapshot back by handle.
pub fn summary_versions_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_versions_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// M7 exit criterion: a client stores a handle to a freshly created map, a
/// peer resolves it, and both converge on edits to the *child* map.
pub fn nested_map_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_nested_map_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// R2 exit criterion: a root map holds a handle to a counter channel; two
/// clients converge on concurrent increments, and a fresh client bootstraps
/// the mixed-channel document from a summary.
pub fn mixed_counter_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_mixed_counter_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// R3 exit criterion: two runtimes race on one claim key; loser resolves Lost.
pub fn claims_race_outcome_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_claims_race_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// M7: two mutually-referencing detached maps attach as one closure when
/// either handle is stored; a peer resolves them transitively.
pub fn recursive_attach_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_recursive_attach_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// M7: a handle stored while the client is reconnecting rides the resubmit
/// queue (`InFlightAttach`); the peer still sees the attach + edits.
pub fn reconnect_mid_attach_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_reconnect_mid_attach_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// M7: a fresh client bootstraps nested maps from a summary blob alone
/// (the attach op predates its history) and resolves the child.
pub fn summary_nested_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_summary_nested_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// M7: `load_version` returns the multi-channel blob, child address included.
pub fn load_version_multichannel_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_load_version_multichannel_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_nested_map_test() -> Nil {
  let document = "watershed-nm-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Establish the session.
  watershed.set(map_a, "title", json.string("nested demo"))
  wait_until(50, fn() { watershed.size(map_b) == 1 }) |> expect.to_be_true()

  // Create a detached map and edit it: local-only, so no ops go out (the
  // in-flight queue stays empty) and B sees nothing.
  let child_a = case watershed.create_map(doc_a) {
    Ok(child) -> child
    Error(reason) -> panic as { "create_map failed: " <> reason }
  }
  watershed.set(child_a, "die", json.int(3))
  watershed.set(child_a, "note", json.string("hi"))
  watershed.is_synced(doc_a) |> expect.to_be_true()
  watershed.size(map_b) |> expect.to_equal(1)

  // Storing the handle attaches the child (snapshot included) and syncs it.
  watershed.set(map_a, "child", watershed.handle_of(child_a))

  // B resolves the handle and sees the detached-phase snapshot.
  let child_b = resolve_key_or_panic(doc_b, map_b, "child")
  wait_until(50, fn() {
    watershed.entries(child_b) == watershed.entries(child_a)
  })
  |> expect.to_be_true()
  watershed.get(child_b, "die") |> expect.to_equal(Some(json.int(3)))

  // Both clients edit the child concurrently, including a same-key race.
  watershed.set(child_a, "die", json.int(6))
  watershed.set(child_b, "from-b", json.bool(True))
  watershed.set(child_a, "raced", json.string("from-a"))
  watershed.set(child_b, "raced", json.string("from-b"))

  wait_until(50, fn() {
    let entries_a = watershed.entries(child_a)
    entries_a != []
    && same_entries(entries_a, watershed.entries(child_b))
    && watershed.get(child_a, "from-b") == Some(json.bool(True))
    && watershed.get(child_b, "die") == Some(json.int(6))
  })
  |> expect.to_be_true()
  watershed.get(child_a, "raced")
  |> expect.to_equal(watershed.get(child_b, "raced"))

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_mixed_counter_test() -> Nil {
  let document = "watershed-cnt-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Establish the session.
  watershed.set(map_a, "title", json.string("scoreboard"))
  wait_until(50, fn() { watershed.size(map_b) == 1 }) |> expect.to_be_true()

  // Detached counter: local increments produce no ops.
  let assert Ok(counter_a) = watershed.create_counter(doc_a)
  watershed.increment(counter_a, 2)
  watershed.is_synced(doc_a) |> expect.to_be_true()
  watershed.counter_value(counter_a) |> expect.to_equal(Some(2))

  // Storing the handle attaches the counter with its optimistic value.
  watershed.set(map_a, "tally", watershed.counter_handle_of(counter_a))

  // B resolves the handle and sees the detached-phase value.
  let counter_b = resolve_counter_key_or_panic(doc_b, map_b, "tally")
  wait_until(50, fn() { watershed.counter_value(counter_b) == Some(2) })
  |> expect.to_be_true()

  // Concurrent increments from both sides commute.
  watershed.increment(counter_a, 5)
  watershed.increment(counter_b, -1)
  wait_until(50, fn() {
    watershed.counter_value(counter_a) == Some(6)
    && watershed.counter_value(counter_b) == Some(6)
  })
  |> expect.to_be_true()

  // A mixed-channel summary bootstraps a fresh client.
  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }
  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let counter_c = resolve_counter_key_or_panic(doc_c, map_c, "tally")
  wait_until(50, fn() { watershed.counter_value(counter_c) == Some(6) })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
  watershed.close(doc_c)
}

@target(erlang)
fn run_claims_race_test() -> Nil {
  let document = "watershed-clm-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(claims_a) = watershed.create_claims(doc_a)
  watershed.set(map_a, "locks", watershed.claims_handle_of(claims_a))

  let claims_b = resolve_claims_key_or_panic(doc_b, map_b, "locks")
  wait_until(50, fn() {
    watershed.has_claim(claims_a, "owner") == False
    && watershed.has_claim(claims_b, "owner") == False
  })
  |> expect.to_be_true()

  // Submit both claims optimistically *before* awaiting either outcome. Both
  // return `Pending` synchronously (the barrier above guarantees neither key is
  // committed yet), so both ops reach the server and it sequences the race.
  // Awaiting A first would let A's committed claim broadcast to B before B
  // submits, and try_set_claim is write-once: B would get `AlreadyClaimed`
  // instead of racing.
  let reply_a = watershed.try_set_claim(claims_a, "owner", json.string("A"))
  let reply_b = watershed.try_set_claim(claims_b, "owner", json.string("B"))
  let outcome_a = await_claim_reply_or_panic(reply_a, "A")
  let outcome_b = await_claim_reply_or_panic(reply_b, "B")

  let winner = case outcome_a, outcome_b {
    claims_kernel.Accepted(value), claims_kernel.Lost(Some(current)) -> {
      current |> expect.to_equal(value)
      value
    }
    claims_kernel.Lost(Some(current)), claims_kernel.Accepted(value) -> {
      current |> expect.to_equal(value)
      value
    }
    _, _ -> panic as "expected one Accepted and one Lost claim outcome"
  }

  wait_until(50, fn() {
    watershed.get_claim(claims_a, "owner") == Some(winner)
    && watershed.get_claim(claims_b, "owner") == Some(winner)
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn await_claim_reply_or_panic(
  reply: runtime.ClaimSubmitReply,
  label: String,
) -> claims_kernel.ClaimOutcome {
  case reply {
    runtime.Pending(outcome_subject) ->
      case process.receive(from: outcome_subject, within: 5000) {
        Ok(outcome) -> outcome
        Error(_) ->
          panic as { "timed out waiting for claim outcome from " <> label }
      }
    runtime.AlreadyClaimed(current) ->
      panic as {
        "expected pending claim for "
        <> label
        <> ", got AlreadyClaimed("
        <> json.to_string(current)
        <> ")"
      }
    runtime.AlreadyPendingLocally ->
      panic as { "unexpected AlreadyPendingLocally for " <> label }
    runtime.WrongChannelType ->
      panic as { "unexpected WrongChannelType for " <> label }
  }
}

@target(erlang)
fn resolve_claims_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.Claims {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_claims(doc, value)
      }
    })
  case resolved {
    Ok(claims) -> claims
    Error(reason) ->
      panic as { "resolving claims at key " <> key <> " failed: " <> reason }
  }
}

@target(erlang)
fn resolve_counter_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.SharedCounter {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_counter(doc, value)
      }
    })
  case resolved {
    Ok(counter) -> counter
    Error(reason) ->
      panic as { "resolving counter at key " <> key <> " failed: " <> reason }
  }
}

@target(erlang)
fn run_recursive_attach_test() -> Nil {
  let document = "watershed-ra-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Two detached maps referencing each other (a cycle).
  let assert Ok(m1_a) = watershed.create_map(doc_a)
  let assert Ok(m2_a) = watershed.create_map(doc_a)
  watershed.set(m1_a, "name", json.string("m1"))
  watershed.set(m1_a, "peer", watershed.handle_of(m2_a))
  watershed.set(m2_a, "name", json.string("m2"))
  watershed.set(m2_a, "peer", watershed.handle_of(m1_a))
  watershed.is_synced(doc_a) |> expect.to_be_true()

  // Storing one handle attaches the whole reachable closure.
  watershed.set(map_a, "m1", watershed.handle_of(m1_a))

  // B resolves transitively: root -> m1 -> m2 -> back to m1.
  let m1_b = resolve_key_or_panic(doc_b, map_b, "m1")
  let m2_b = resolve_key_or_panic(doc_b, m1_b, "peer")
  wait_until(50, fn() { watershed.get(m2_b, "name") == Some(json.string("m2")) })
  |> expect.to_be_true()
  let m1_again = resolve_key_or_panic(doc_b, m2_b, "peer")
  watershed.get(m1_again, "name") |> expect.to_equal(Some(json.string("m1")))

  // Edits through the cycle converge.
  watershed.set(m2_b, "from-b", json.int(2))
  wait_until(50, fn() { watershed.get(m2_a, "from-b") == Some(json.int(2)) })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_reconnect_quiet_room_test() -> Nil {
  let document = "watershed-rq-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Establish the session and confirm both sides are live.
  watershed.set(map_a, "k1", json.int(1))
  wait_until(50, fn() { watershed.get(map_b, "k1") == Some(json.int(1)) })
  |> expect.to_be_true()

  // Drop A with nothing in flight, and let the socket actually go down before
  // B writes. The sleep is load-bearing: `force_reconnect` is a cast, so
  // without it B's edit races the teardown and may be delivered live, which
  // would leave A nothing to catch up on and quietly void the test.
  watershed.force_reconnect(doc_a)
  process.sleep(500)

  // The only write in the whole scenario, and it lands squarely in A's gap.
  watershed.set(map_b, "from-b", json.bool(True))

  // Nothing else happens — no edit from A, no third client, no further traffic
  // from B. A has to ask for what it missed or it never sees this at all.
  wait_until(100, fn() {
    watershed.get(map_a, "from-b") == Some(json.bool(True))
  })
  |> expect.to_be_true()

  // And A is genuinely live again, not merely caught up: an edit made now must
  // reach the wire, which it cannot do from the catching-up holding state.
  watershed.set(map_a, "after", json.string("live"))
  wait_until(100, fn() {
    watershed.get(map_b, "after") == Some(json.string("live"))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_reconnect_nothing_missed_test() -> Nil {
  let document = "watershed-rn-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  watershed.set(map_a, "k1", json.int(1))
  wait_until(50, fn() { watershed.get(map_b, "k1") == Some(json.int(1)) })
  |> expect.to_be_true()

  // Reconnect into total silence. Nobody writes during the gap, so the only op
  // sequenced across it is A's own rejoin — which floodgate reports as the
  // handshake checkpoint and pointedly does not send to A.
  watershed.force_reconnect(doc_a)
  process.sleep(500)

  // A's first edit after coming back is the whole assertion: while catching up
  // every edit is withheld from the wire, so if the empty gap never closed this
  // never arrives. Note A cannot rescue itself here — a withheld edit generates
  // no traffic, so there is no op to discover the gap with.
  watershed.set(map_a, "after", json.string("live"))
  wait_until(100, fn() {
    watershed.get(map_b, "after") == Some(json.string("live"))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_reconnect_mid_attach_test() -> Nil {
  let document = "watershed-rma-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Establish the session.
  watershed.set(map_a, "k", json.int(1))
  wait_until(50, fn() { watershed.size(map_b) == 1 }) |> expect.to_be_true()

  // Detached edits, then drop the channel. The attach triggered while
  // reconnecting must survive as in-flight state and resubmit.
  let assert Ok(child_a) = watershed.create_map(doc_a)
  watershed.set(child_a, "die", json.int(5))
  watershed.force_reconnect(doc_a)
  watershed.set(map_a, "child", watershed.handle_of(child_a))
  watershed.set(child_a, "during", json.string("reconnect"))

  // B converges on the attach and both edits once A is back.
  let child_b = resolve_key_or_panic(doc_b, map_b, "child")
  wait_until(100, fn() {
    watershed.entries(child_b) == watershed.entries(child_a)
    && watershed.get(child_b, "during") == Some(json.string("reconnect"))
  })
  |> expect.to_be_true()
  watershed.get(child_b, "die") |> expect.to_equal(Some(json.int(5)))

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_summary_nested_test() -> Nil {
  let document = "watershed-s2-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  // Nested state: root -> child, both with confirmed entries.
  let assert Ok(child_a) = watershed.create_map(doc_a)
  watershed.set(child_a, "die", json.int(3))
  watershed.set(map_a, "title", json.string("doc"))
  watershed.set(map_a, "child", watershed.handle_of(child_a))
  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()

  let handle = case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(handle) -> handle
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }
  { handle != "" } |> expect.to_be_true()

  // A post-summary delta on the *child* channel: a fresh client can only
  // apply it if the summary taught it that channel.
  watershed.set(child_a, "post", json.bool(True))
  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()

  // Fresh client: bootstraps from the summary blob (the attach op predates
  // its post-summary history), resolves the child, sees everything.
  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  wait_until(50, fn() {
    same_entries(watershed.entries(map_c), watershed.entries(map_a))
  })
  |> expect.to_be_true()
  let child_c = resolve_key_or_panic(doc_c, map_c, "child")
  wait_until(50, fn() {
    same_entries(watershed.entries(child_c), watershed.entries(child_a))
  })
  |> expect.to_be_true()
  watershed.get(child_c, "post") |> expect.to_equal(Some(json.bool(True)))

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn run_load_version_multichannel_test() -> Nil {
  let document = "watershed-lvm-" <> int.to_string(system_time(Second))

  let doc = connect_or_panic(document, "user-a")
  let map = watershed.root(doc)

  let assert Ok(child) = watershed.create_map(doc)
  watershed.set(child, "die", json.int(4))
  watershed.set(map, "child", watershed.handle_of(child))
  wait_until(50, fn() { watershed.is_synced(doc) }) |> expect.to_be_true()

  let tree_sha = case wait_until_ok(50, fn() { watershed.summarize(doc) }) {
    Ok(tree_sha) -> tree_sha
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  // The stored blob is multi-channel: root first, then the child address the
  // root's handle value points at, with the child's captured entries.
  let assert Ok(blob) = watershed.load_version(doc, handle: tree_sha)
  let assert Some(handle_value) = watershed.get(map, "child")
  let assert Ok(child_address) = handle.parse_handle(handle_value)
  case blob.channels {
    [root_channel, child_channel] -> {
      root_channel.address |> expect.to_equal("root")
      snapshot_entries(root_channel.snapshot)
      |> expect.to_equal([#("child", handle_value)])
      child_channel.address |> expect.to_equal(child_address)
      snapshot_entries(child_channel.snapshot)
      |> expect.to_equal([#("die", json.int(4))])
    }
    _ -> panic as "expected exactly two channels in the summary blob"
  }

  watershed.close(doc)
}

@target(erlang)
/// Wait until `key` on `map` holds a resolvable handle, then resolve it.
/// Retries both the read (the set may not have arrived) and the resolve
/// (the referenced channel's attach may still be in flight).
fn resolve_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.SharedMap {
  case try_resolve_key(50, doc, map, key) {
    Ok(child) -> child
    Error(reason) ->
      panic as { "resolving handle at key " <> key <> " failed: " <> reason }
  }
}

@target(erlang)
fn try_resolve_key(
  attempts: Int,
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> Result(watershed.SharedMap, String) {
  let attempt = case watershed.get(map, key) {
    None -> Error("key absent")
    Some(value) ->
      case watershed.is_handle(value) {
        False -> Error("value is not a handle")
        True -> watershed.resolve(doc, value)
      }
  }
  case attempt {
    Ok(child) -> Ok(child)
    Error(reason) ->
      case attempts {
        0 -> Error(reason)
        _ -> {
          process.sleep(100)
          try_resolve_key(attempts - 1, doc, map, key)
        }
      }
  }
}

@target(erlang)
fn run_versions_test() -> Nil {
  let document = "watershed-ver-" <> int.to_string(system_time(Second))

  let doc = connect_or_panic(document, "user-a")
  let map = watershed.root(doc)

  // A document with no summaries yet lists no versions.
  watershed.get_versions(doc, count: 10) |> expect.to_equal(Ok([]))

  // First snapshot: {die: 4, color: blue}.
  watershed.set(map, "die", json.int(4))
  watershed.set(map, "color", json.string("blue"))
  wait_until(50, fn() { watershed.is_synced(doc) }) |> expect.to_be_true()
  let handle_1 = case wait_until_ok(50, fn() { watershed.summarize(doc) }) {
    Ok(handle) -> handle
    Error(reason) -> panic as { "first summarize failed: " <> reason }
  }

  // Second snapshot: color changed and a key added.
  watershed.set(map, "color", json.string("green"))
  watershed.set(map, "post", json.bool(True))
  wait_until(50, fn() { watershed.is_synced(doc) }) |> expect.to_be_true()
  let handle_2 = case wait_until_ok(50, fn() { watershed.summarize(doc) }) {
    Ok(handle) -> handle
    Error(reason) -> panic as { "second summarize failed: " <> reason }
  }

  // The server registers a version per summarize op (async relative to the
  // summarize reply), newest first.
  wait_until(50, fn() {
    case watershed.get_versions(doc, count: 10) {
      Ok(versions) ->
        list.map(versions, fn(v: git_storage.SummaryVersion) { v.handle })
        == [handle_2, handle_1]
      Error(_) -> False
    }
  })
  |> expect.to_be_true()

  let assert Ok([latest, previous]) = watershed.get_versions(doc, count: 10)
  { latest.sequence_number > previous.sequence_number } |> expect.to_be_true()

  // `count` keeps only the newest versions.
  let assert Ok([only]) = watershed.get_versions(doc, count: 1)
  only.handle |> expect.to_equal(handle_2)

  // Historical snapshot reads by handle: each version returns exactly the
  // confirmed state it captured, without affecting the live document.
  let assert Ok(blob_1) = watershed.load_version(doc, handle: handle_1)
  let entries_1 =
    list.flatten(
      list.map(blob_1.channels, fn(ch) { snapshot_entries(ch.snapshot) }),
    )
  entries_1
  |> expect.to_equal([
    #("die", json.int(4)),
    #("color", json.string("blue")),
  ])
  let assert Ok(blob_2) = watershed.load_version(doc, handle: handle_2)
  let entries_2 =
    list.flatten(
      list.map(blob_2.channels, fn(ch) { snapshot_entries(ch.snapshot) }),
    )
  entries_2
  |> expect.to_equal([
    #("die", json.int(4)),
    #("color", json.string("green")),
    #("post", json.bool(True)),
  ])
  { blob_2.sequence_number > blob_1.sequence_number } |> expect.to_be_true()

  // The live document still reflects the latest state.
  watershed.get(map, "color") |> expect.to_equal(Some(json.string("green")))

  watershed.close(doc)
}

@target(erlang)
fn run_large_history_test() -> Nil {
  let document = "watershed-lh-" <> int.to_string(system_time(Second))
  let op_count = 1050

  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  // Write more distinct keys than the history window holds. The earliest
  // sets (k1, k2, ...) age out of the server's in-memory op history, so a
  // later bootstrap can only recover them via the deltas REST endpoint.
  write_keys(map_a, 1, op_count)
  wait_until(600, fn() { watershed.is_synced(doc_a) })
  |> expect.to_be_true()

  // A fresh client's initialMessages are missing the prefix; bootstrap must
  // page it in and converge on the full map.
  let doc_b = connect_or_panic(document, "user-b")
  let map_b = watershed.root(doc_b)
  wait_until(100, fn() {
    watershed.size(map_b) == op_count
    && same_entries(watershed.entries(map_b), watershed.entries(map_a))
  })
  |> expect.to_be_true()

  // Spot-check keys that only exist in the aged-out prefix.
  watershed.get(map_b, "k1") |> expect.to_equal(Some(json.int(1)))
  watershed.get(map_b, "k25") |> expect.to_equal(Some(json.int(25)))

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
/// `write_keys`, but waiting for each write to be acknowledged before the next.
/// Floodgate sequences a submitted batch as a single message, so writes issued
/// back to back advance the document's sequence number by far less than their
/// count — draining is how a test produces one message per write.
fn write_keys_drained(
  document: watershed.Document,
  map: watershed.SharedMap,
  from: Int,
  to: Int,
) -> Nil {
  case from > to {
    True -> Nil
    False -> {
      watershed.set(map, "k" <> int.to_string(from), json.int(from))
      wait_until(50, fn() { watershed.is_synced(document) })
      |> expect.to_be_true()
      write_keys_drained(document, map, from + 1, to)
    }
  }
}

@target(erlang)
fn write_keys(map: watershed.SharedMap, from: Int, to: Int) -> Nil {
  case from > to {
    True -> Nil
    False -> {
      watershed.set(map, "k" <> int.to_string(from), json.int(from))
      write_keys(map, from + 1, to)
    }
  }
}

@target(erlang)
fn run_summary_test() -> Nil {
  let document = "watershed-sum-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  // Build up some confirmed state.
  watershed.set(map_a, "die", json.int(4))
  watershed.set(map_a, "color", json.string("blue"))
  watershed.set(map_a, "count", json.int(9))
  watershed.delete(map_a, "count")
  // Wait until every edit is acknowledged (in-flight drained) so the summary
  // captures the complete confirmed state.
  wait_until(50, fn() { watershed.is_synced(doc_a) })
  |> expect.to_be_true()

  // Summarize once the client is caught up. Retrying is safe: attempts made
  // before the client is synced reply Error and submit nothing; only the
  // successful attempt uploads and submits the summarize op.
  let handle = case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(handle) -> handle
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }
  { handle != "" } |> expect.to_be_true()

  // Make a post-summary edit so the fresh client must replay a delta on top of
  // the summary (history above SN 1), and wait until it too is sequenced so it
  // is guaranteed to appear in the fresh client's post-summary history.
  watershed.set(map_a, "post", json.string("after-summary"))
  wait_until(50, fn() { watershed.is_synced(doc_a) })
  |> expect.to_be_true()

  // A fresh client connects; the server serves the summaryContext + only the
  // post-summary deltas, so watershed must load the summary and apply the
  // delta rather than fail with a HistoryGap.
  let doc_b = connect_or_panic(document, "user-b")
  let map_b = watershed.root(doc_b)
  let converged =
    wait_until(50, fn() {
      same_entries(watershed.entries(map_b), watershed.entries(map_a))
    })
  converged
  |> expect.to_be_true()

  // The summarized keys and the post-summary delta all made it across.
  watershed.get(map_b, "die") |> expect.to_equal(Some(json.int(4)))
  watershed.get(map_b, "color") |> expect.to_equal(Some(json.string("blue")))
  watershed.get(map_b, "count") |> expect.to_equal(None)
  watershed.get(map_b, "post")
  |> expect.to_equal(Some(json.string("after-summary")))

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_auto_summary_test() -> Nil {
  let document = "watershed-auto-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  watershed.auto_summarize(
    doc_a,
    summary_policy.policy()
      |> summary_policy.with_threshold(4)
      |> summary_policy.with_jitter_ms(0),
  )

  // Nothing here calls `summarize`. The drift falling back under the threshold
  // is the observable: only a checkpoint moves it.
  //
  // Written as traffic-until-it-happens rather than write-then-wait, because
  // the policy arms on a sequenced message. A document that falls quiet just
  // over the threshold stays there until the next one arrives — correct, and
  // invisible in an app, but a test that stopped writing could wait forever.
  summarizes_within(doc_a, map_a, 20, 4) |> expect.to_be_true()

  // A post-checkpoint edit, so the fresh client has to apply a delta on top of
  // the summary rather than landing on it exactly.
  watershed.set(map_a, "post", json.string("after-summary"))
  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()

  // The fresh client bootstraps from a summary nobody asked for.
  let doc_b = connect_or_panic(document, "user-b")
  let map_b = watershed.root(doc_b)
  wait_until(50, fn() {
    same_entries(watershed.entries(map_b), watershed.entries(map_a))
  })
  |> expect.to_be_true()
  watershed.get(map_b, "post")
  |> expect.to_equal(Some(json.string("after-summary")))

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
/// Write a key, wait for it to sequence, and check whether the drift has fallen
/// under `threshold` — up to `attempts` times. Each write is the sequenced
/// message the policy needs to arm on.
fn summarizes_within(
  document: watershed.Document,
  map: watershed.SharedMap,
  attempts: Int,
  threshold: Int,
) -> Bool {
  case watershed.ops_since_summary(document) < threshold, attempts {
    True, _ -> True
    False, 0 -> False
    False, _ -> {
      watershed.set(map, "tick" <> int.to_string(attempts), json.int(attempts))
      wait_until(50, fn() { watershed.is_synced(document) })
      |> expect.to_be_true()
      process.sleep(100)
      summarizes_within(document, map, attempts - 1, threshold)
    }
  }
}

@target(erlang)
fn run_peer_summary_visibility_test() -> Nil {
  let document = "watershed-peersum-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)

  write_keys_drained(doc_a, map_a, 1, 5)
  // B has seen A's ops, so its drift is the whole log and nothing has
  // summarized.
  wait_until(50, fn() { watershed.ops_since_summary(doc_b) > 3 })
  |> expect.to_be_true()
  let drift_before = watershed.ops_since_summary(doc_b)

  // Only A summarizes, by hand — this is about what B observes, not about the
  // policy's own trigger.
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }
  watershed.ops_since_summary(doc_a) |> expect.to_equal(0)

  // B never called `summarize` and never will — its checkpoint can only move
  // because the room was told. Compared against `drift_before`, since both
  // clients keep counting the messages that follow the checkpoint (the
  // summarize op itself among them).
  wait_until(50, fn() { watershed.ops_since_summary(doc_b) < drift_before })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_reconnect_test() -> Nil {
  let document = "watershed-rc-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Establish the session and confirm both sides are live.
  watershed.set(map_a, "k1", json.int(1))
  wait_until(50, fn() { watershed.get(map_b, "k1") == Some(json.int(1)) })
  |> expect.to_be_true()

  // Burst several edits from A, then yank its channel mid-flight so some ops
  // are in flight (possibly sequenced-but-unacked) when the socket drops.
  watershed.set(map_a, "k2", json.int(2))
  watershed.set(map_a, "k3", json.int(3))
  watershed.set(map_a, "k4", json.int(4))
  watershed.set(map_a, "k5", json.int(5))
  watershed.force_reconnect(doc_a)

  // Edits issued while A is reconnecting must be preserved and resubmitted.
  watershed.set(map_a, "k6", json.string("after-drop"))
  watershed.delete(map_a, "k2")

  // Meanwhile B keeps editing so the reconnect must also merge the delta A
  // missed while offline.
  watershed.set(map_b, "from-b", json.bool(True))

  let expected_a = Some(json.string("after-drop"))
  let converged =
    wait_until(100, fn() {
      let entries_a = watershed.entries(map_a)
      let entries_b = watershed.entries(map_b)
      entries_a != []
      && same_entries(entries_a, entries_b)
      && watershed.get(map_a, "k6") == expected_a
      && watershed.get(map_a, "from-b") == Some(json.bool(True))
      && watershed.get(map_a, "k2") == None
    })
  converged |> expect.to_be_true()

  // No op was lost: every surviving key made it across the reconnect.
  watershed.get(map_b, "k3") |> expect.to_equal(Some(json.int(3)))
  watershed.get(map_b, "k5") |> expect.to_equal(Some(json.int(5)))
  watershed.get(map_b, "k6") |> expect.to_equal(expected_a)
  // The delete issued during reconnect converged too (no duplicate re-add).
  watershed.get(map_b, "k2") |> expect.to_equal(None)

  // A fresh client bootstrapping from history sees the identical converged map.
  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  wait_until(50, fn() {
    same_entries(watershed.entries(map_c), watershed.entries(map_a))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
  watershed.close(doc_c)
}

@target(erlang)
fn run_pact_map_quorum_test() -> Nil {
  let document = "watershed-it-quorum-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let doc_c = connect_or_panic(document, "user-c")

  let assert Ok(pact_a) = watershed.create_pact_map(doc_a)
  watershed.set(
    watershed.root(doc_a),
    "tempo",
    watershed.pact_map_handle_of(pact_a),
  )

  let assert Ok(pact_b) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_b), "tempo") {
        None -> Error("handle not replicated to B")
        Some(handle) -> watershed.resolve_pact_map(doc_b, handle)
      }
    })
  let assert Ok(pact_c) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_c), "tempo") {
        None -> Error("handle not replicated to C")
        Some(handle) -> watershed.resolve_pact_map(doc_c, handle)
      }
    })

  // A proposes. Against a real three-client room this is where the fabricated
  // `[self, author]` quorum did not merely accept early — it *panicked* the
  // runtime actor with `AckMismatch("client was not expected to sign off")`,
  // because C's accept arrived for a pact whose frozen signoff list never named
  // it. So reaching the end of this test at all is the discriminating result;
  // the exact signoff membership is pinned deterministically by
  // `pact_map_pends_until_the_whole_room_signs_off_test` on the sluice, where
  // a paused client makes the outstanding list exact rather than a race.
  watershed.pact_map_set(pact_a, "bpm", json.int(120))

  // Whatever the timing, it must settle at all three replicas and agree.
  let accepted =
    wait_until(50, fn() {
      watershed.pact_map_get(pact_a, "bpm") == Some(json.int(120))
      && watershed.pact_map_get(pact_b, "bpm") == Some(json.int(120))
      && watershed.pact_map_get(pact_c, "bpm") == Some(json.int(120))
    })
  accepted |> expect.to_be_true()

  watershed.pact_map_is_pending(pact_a, "bpm") |> expect.to_be_false()
  watershed.pact_map_is_pending(pact_b, "bpm") |> expect.to_be_false()
  watershed.pact_map_is_pending(pact_c, "bpm") |> expect.to_be_false()

  watershed.close(doc_a)
  watershed.close(doc_b)
  watershed.close(doc_c)
}

@target(erlang)
fn run_pact_map_disconnect_test() -> Nil {
  let document = "watershed-it-drain-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let doc_c = connect_or_panic(document, "user-c")

  let assert Ok(pact_a) = watershed.create_pact_map(doc_a)
  watershed.set(
    watershed.root(doc_a),
    "tempo",
    watershed.pact_map_handle_of(pact_a),
  )
  let assert Ok(pact_b) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_b), "tempo") {
        None -> Error("handle not replicated to B")
        Some(handle) -> watershed.resolve_pact_map(doc_b, handle)
      }
    })
  // C resolves too, so it is a full participant rather than a passive reader.
  let assert Ok(_pact_c) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_c), "tempo") {
        None -> Error("handle not replicated to C")
        Some(handle) -> watershed.resolve_pact_map(doc_c, handle)
      }
    })

  // Propose, then drop C without a clean close — the signoff it owes can never
  // arrive. The pact must still settle, draining via the server's sequenced
  // `"leave"`. Wedging here is the failure this test exists to catch, and it is
  // the question that decides whether the protocol is usable in production.
  watershed.pact_map_set(pact_a, "bpm", json.int(90))
  watershed.force_reconnect(doc_c)
  watershed.close(doc_c)

  let settled =
    wait_until(100, fn() {
      watershed.pact_map_get(pact_a, "bpm") == Some(json.int(90))
      && watershed.pact_map_get(pact_b, "bpm") == Some(json.int(90))
    })
  settled |> expect.to_be_true()

  watershed.pact_map_is_pending(pact_a, "bpm") |> expect.to_be_false()
  watershed.pact_map_pending_signoffs(pact_a, "bpm") |> expect.to_equal(None)

  // The room still works after the departure: a second proposal settles between
  // the two survivors, proving the roster narrowed rather than went stale.
  watershed.pact_map_set(pact_a, "bpm", json.int(140))
  let resettled =
    wait_until(100, fn() {
      watershed.pact_map_get(pact_a, "bpm") == Some(json.int(140))
      && watershed.pact_map_get(pact_b, "bpm") == Some(json.int(140))
    })
  resettled |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_convergence_test() -> Nil {
  let document = "watershed-it-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Concurrent edits from both clients, including a same-key race that
  // server sequencing must resolve identically on both sides.
  watershed.set(map_a, "die", json.int(4))
  watershed.set(map_b, "color", json.string("blue"))
  watershed.set(map_a, "shared", json.string("from-a"))
  watershed.set(map_b, "shared", json.string("from-b"))
  watershed.delete(map_a, "die")
  watershed.set(map_a, "die", json.int(6))

  let converged =
    wait_until(50, fn() {
      let entries_a = watershed.entries(map_a)
      let entries_b = watershed.entries(map_b)
      entries_a != []
      && same_entries(entries_a, entries_b)
      && watershed.get(map_a, "die") == Some(json.int(6))
      && watershed.get(map_a, "color") == Some(json.string("blue"))
    })
  converged |> expect.to_be_true()

  // Both clients must agree on the LWW winner for the raced key.
  watershed.get(map_a, "shared")
  |> expect.to_equal(watershed.get(map_b, "shared"))

  // A third client bootstrapping from history alone must see the same map.
  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  same_entries(watershed.entries(map_c), watershed.entries(map_a))
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
  watershed.close(doc_c)
}

@target(erlang)
fn run_restart_ghost_test() -> Nil {
  let document = "watershed-it-restart-" <> int.to_string(system_time(Second))

  // Three write-mode clients, so three sequenced joins land in the durable log.
  // A `PactMap` is created and agreed before the restart, which is what makes
  // the post-restart replay non-trivial: the joiner has a settled pact to
  // reconstruct as well as a roster.
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let doc_c = connect_or_panic(document, "user-c")

  let assert Ok(pact_a) = watershed.create_pact_map(doc_a)
  watershed.set(
    watershed.root(doc_a),
    "tempo",
    watershed.pact_map_handle_of(pact_a),
  )
  let assert Ok(pact_b) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_b), "tempo") {
        None -> Error("handle not replicated to B")
        Some(handle) -> watershed.resolve_pact_map(doc_b, handle)
      }
    })
  let assert Ok(_) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_c), "tempo") {
        None -> Error("handle not replicated to C")
        Some(handle) -> watershed.resolve_pact_map(doc_c, handle)
      }
    })

  watershed.pact_map_set(pact_a, "bpm", json.int(120))
  wait_until(50, fn() {
    watershed.pact_map_get(pact_b, "bpm") == Some(json.int(120))
  })
  |> expect.to_be_true()

  // A `TaskManager` role, held by A with B and C queued behind it. None of the
  // three ever releases: the restart is what takes them away, so their claims
  // on the role are only ever answered by a sequenced `leave`.
  let assert Ok(tasks_a) = watershed.create_task_manager(doc_a)
  watershed.set(
    watershed.root(doc_a),
    "tasks",
    watershed.task_manager_handle_of(tasks_a),
  )
  let assert Ok(tasks_b) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_b), "tasks") {
        None -> Error("task manager handle not replicated to B")
        Some(handle) -> watershed.resolve_task_manager(doc_b, handle)
      }
    })
  let assert Ok(tasks_c) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_c), "tasks") {
        None -> Error("task manager handle not replicated to C")
        Some(handle) -> watershed.resolve_task_manager(doc_c, handle)
      }
    })
  watershed.volunteer_for_task(tasks_a, "summarizer")
  wait_until(50, fn() { watershed.task_assigned(tasks_a, "summarizer") })
  |> expect.to_be_true()
  watershed.volunteer_for_task(tasks_b, "summarizer")
  watershed.volunteer_for_task(tasks_c, "summarizer")
  wait_until(50, fn() { watershed.task_queued(tasks_b, "summarizer") })
  |> expect.to_be_true()

  // The ids that must not survive in any replayed queue.
  let pre_restart_ids =
    [doc_a, doc_b, doc_c]
    |> list.filter_map(fn(doc) {
      watershed.client_id(doc) |> option.to_result(Nil)
    })
    |> list.map(client_id.to_int)
  list.length(pre_restart_ids) |> expect.to_equal(3)

  // Kill the server out from under all three. No `leave` is sent for any of
  // them, so their joins are exactly the unmatched ones the issue describes.
  restart_floodgate()

  // Tear the three down without letting them re-establish. Their joins stay
  // unanswered in the durable log, which is the whole point: the only thing
  // that can close them is the server's repair on rehydrate. Leaving them to
  // reconnect instead would both mask that — a reconnected client re-joins
  // under a fresh id — and drag in an unrelated defect; see
  // `docs/plans/2026-08-09-summary-bootstrap-plan.md`.
  watershed.close(doc_a)
  watershed.close(doc_b)
  watershed.close(doc_c)

  // Two fresh clients, both of which reconstruct the room by replaying a log
  // that contains three joins from before the restart.
  let doc_d = connect_or_panic(document, "user-d")
  let doc_e = connect_or_panic(document, "user-e")

  // The settled pact replays intact — the state half of the bootstrap.
  let assert Ok(pact_d) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_d), "tempo") {
        None -> Error("handle not replicated to D")
        Some(handle) -> watershed.resolve_pact_map(doc_d, handle)
      }
    })
  watershed.pact_map_get(pact_d, "bpm") |> expect.to_equal(Some(json.int(120)))
  watershed.pact_map_is_pending(pact_d, "bpm") |> expect.to_be_false()

  // The discriminating assertion, and the one the issue names outright: "a
  // ghost at the head of a `TaskManager` queue holds that role permanently."
  //
  // It has to be the queue rather than a fresh `PactMap` proposal. A proposal
  // D makes *now* freezes its signoff list from D's live roster, which
  // `settle_bootstrap` already replaced with the handshake's — so ghosts do not
  // reach it and it would settle either way. The queue is different: it is
  // reconstructed purely by replaying the log, so a `volunteer` with no
  // matching `leave` sits in it forever and every later volunteer, D's
  // included, queues behind a client that cannot release.
  let assert Ok(tasks_d) =
    wait_until_ok(50, fn() {
      case watershed.get(watershed.root(doc_d), "tasks") {
        None -> Error("task manager handle not replicated to D")
        Some(handle) -> watershed.resolve_task_manager(doc_d, handle)
      }
    })

  // No pre-restart client appears anywhere in the reconstructed queues.
  let ghosts =
    list.flat_map(watershed.task_queues(tasks_d), fn(entry) { entry.1 })
    |> list.filter(list.contains(pre_restart_ids, _))
  ghosts |> expect.to_equal([])

  // And the role is actually acquirable, which is what "not wedged" means.
  watershed.volunteer_for_task(tasks_d, "summarizer")
  let assigned =
    wait_until(50, fn() { watershed.task_assigned(tasks_d, "summarizer") })
  assigned |> expect.to_be_true()

  watershed.close(doc_d)
  watershed.close(doc_e)
}

@target(erlang)
/// Restart the floodgate container and wait for it to report healthy again.
///
/// Shelling out rather than asking the server to restart itself: the point is
/// an abrupt process loss with no chance to sequence leaves, which is exactly
/// what a crash looks like and what a graceful shutdown hook would hide.
fn restart_floodgate() -> Nil {
  let _ =
    shell(
      "docker compose -f docker-compose.yml -f docker-compose.persistent.yml"
      <> " restart floodgate",
    )
  let healthy =
    wait_until(100, fn() {
      shell(
        "curl -s -o /dev/null -w '%{http_code}' http://"
        <> host
        <> ":"
        <> int.to_string(port)
        <> "/health",
      )
      == "200"
    })
  case healthy {
    True -> Nil
    False -> panic as "floodgate did not come back healthy after restart"
  }
}

@target(erlang)
fn shell(command: String) -> String {
  command
  |> charlist.from_string
  |> os_cmd
  |> charlist.to_string
  |> string.trim
}

@target(erlang)
@external(erlang, "os", "cmd")
fn os_cmd(command: Charlist) -> Charlist

@target(erlang)
fn connect_or_panic(document: String, user_id: String) -> watershed.Document {
  let token = mint_token(tenant, document, user_id)
  case
    watershed.connect(
      host: host,
      port: port,
      tenant: tenant,
      document: document,
      token: token,
      user_id: user_id,
    )
  {
    Ok(doc) -> doc
    Error(reason) -> panic as { "connect failed: " <> reason }
  }
}

@target(erlang)
/// The map entries a summary blob channel captured. Every channel in these
/// tests is a map.
fn snapshot_entries(snapshot: channel.Snapshot) -> List(#(String, Json)) {
  let assert channel.MapSnapshot(entries) = snapshot
  entries
}

@target(erlang)
/// Converged clients must agree on values AND iteration order, since both
/// derive insertion order from the same sequenced op stream.
fn same_entries(
  left: List(#(String, Json)),
  right: List(#(String, Json)),
) -> Bool {
  left == right
}

@target(erlang)
fn wait_until(attempts: Int, check: fn() -> Bool) -> Bool {
  case check() {
    True -> True
    False ->
      case attempts {
        0 -> False
        _ -> {
          process.sleep(100)
          wait_until(attempts - 1, check)
        }
      }
  }
}

@target(erlang)
/// Retry `check` until it returns `Ok`, polling every 100ms. Returns the last
/// result (the successful `Ok`, or the final `Error` once attempts run out).
fn wait_until_ok(attempts: Int, check: fn() -> Result(a, b)) -> Result(a, b) {
  case check() {
    Ok(value) -> Ok(value)
    Error(err) ->
      case attempts {
        0 -> Error(err)
        _ -> {
          process.sleep(100)
          wait_until_ok(attempts - 1, check)
        }
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dev JWT minting (HS256, matching the server's JWT verification)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn mint_token(tenant: String, document: String, user_id: String) -> String {
  let now = system_time(Second)
  let header =
    json.object([
      #("alg", json.string("HS256")),
      #("typ", json.string("JWT")),
    ])
  let payload =
    json.object([
      #("documentId", json.string(document)),
      #("tenantId", json.string(tenant)),
      #(
        "scopes",
        json.array(["doc:read", "doc:write", "summary:write"], json.string),
      ),
      #("user", json.object([#("id", json.string(user_id))])),
      #("iat", json.int(now)),
      #("exp", json.int(now + 3600)),
      #("ver", json.string("1.0")),
    ])
  let signing_input =
    base64url(<<json.to_string(header):utf8>>)
    <> "."
    <> base64url(<<json.to_string(payload):utf8>>)
  let signature =
    crypto.hmac(<<signing_input:utf8>>, crypto.Sha256, <<tenant_secret:utf8>>)
  signing_input <> "." <> base64url(signature)
}

@target(erlang)
fn base64url(data: BitArray) -> String {
  bit_array.base64_url_encode(data, False)
}

@target(erlang)
type TimeUnit {
  Second
}

@target(erlang)
@external(erlang, "os", "system_time")
fn system_time(unit: TimeUnit) -> Int

// ─────────────────────────────────────────────────────────────────────────────
// JSON-OT (json0) live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Two clients converge on concurrent json0 inserts at distinct keys.
pub fn json_ot_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_json_ot_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Concurrent number_add ops on the same field commute to the sum.
pub fn json_ot_concurrent_conflict_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_json_ot_conflict_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A fresh client bootstraps a json0 child from a summary and reads the doc.
pub fn json_ot_summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_json_ot_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_json_ot_converge_test() -> Nil {
  let document = "ws-jot-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(jot_a) = watershed.create_json_ot(doc_a)
  watershed.set(map_a, "doc", watershed.json_ot_handle_of(jot_a))
  let jot_b = resolve_json_ot_key_or_panic(doc_b, map_b, "doc")

  watershed.submit_json_ot(jot_a, [
    json_ot.obj_insert([json_ot.Key("a")], json_ot.VString("from-a")),
  ])
  watershed.submit_json_ot(jot_b, [
    json_ot.obj_insert([json_ot.Key("b")], json_ot.VString("from-b")),
  ])

  let expected =
    Some(
      json_ot.VObject([
        #("a", json_ot.VString("from-a")),
        #("b", json_ot.VString("from-b")),
      ]),
    )
  wait_until(50, fn() {
    watershed.json_ot_view(jot_a) == watershed.json_ot_view(jot_b)
    && watershed.json_ot_view(jot_a) == expected
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_json_ot_conflict_test() -> Nil {
  let document = "ws-jot-cf-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(jot_a) = watershed.create_json_ot(doc_a)
  watershed.set(map_a, "doc", watershed.json_ot_handle_of(jot_a))
  let jot_b = resolve_json_ot_key_or_panic(doc_b, map_b, "doc")

  // Seed a numeric field and wait for both sides to see it.
  watershed.submit_json_ot(jot_a, [
    json_ot.obj_insert([json_ot.Key("n")], json_ot.VNumber(json_ot.NInt(0))),
  ])
  let seeded = Some(json_ot.VObject([#("n", json_ot.VNumber(json_ot.NInt(0)))]))
  wait_until(50, fn() { watershed.json_ot_view(jot_b) == seeded })
  |> expect.to_be_true()

  // Concurrent increments to the same field commute to the sum.
  watershed.submit_json_ot(jot_a, [
    json_ot.number_add([json_ot.Key("n")], json_ot.NInt(3)),
  ])
  watershed.submit_json_ot(jot_b, [
    json_ot.number_add([json_ot.Key("n")], json_ot.NInt(4)),
  ])

  let expected =
    Some(json_ot.VObject([#("n", json_ot.VNumber(json_ot.NInt(7)))]))
  wait_until(50, fn() {
    watershed.json_ot_view(jot_a) == watershed.json_ot_view(jot_b)
    && watershed.json_ot_view(jot_a) == expected
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_json_ot_summary_test() -> Nil {
  let document = "ws-jot-sm-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(jot_a) = watershed.create_json_ot(doc_a)
  watershed.submit_json_ot(jot_a, [
    json_ot.obj_insert([json_ot.Key("title")], json_ot.VString("hello")),
  ])
  watershed.set(map_a, "doc", watershed.json_ot_handle_of(jot_a))

  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let jot_c = resolve_json_ot_key_or_panic(doc_c, map_c, "doc")
  let expected = Some(json_ot.VObject([#("title", json_ot.VString("hello"))]))
  wait_until(50, fn() { watershed.json_ot_view(jot_c) == expected })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn resolve_json_ot_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.JsonOt {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_json_ot(doc, value)
      }
    })
  case resolved {
    Ok(jot) -> jot
    Error(reason) ->
      panic as { "resolving json_ot at key " <> key <> " failed: " <> reason }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SharedRichText live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Two clients converge on concurrent SharedRichText edits over the
/// `richText` wire channel: client A creates the channel and stores its
/// handle on the root map (the normal detached create/attach lifecycle),
/// client B resolves it from that handle, and both submit non-overlapping
/// concurrent edits — A bolds a text prefix, B appends emoji text — that
/// must transform against each other and land in the same optimistic
/// document on both sides regardless of author tie-break order.
pub fn rich_text_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_rich_text_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_rich_text_converge_test() -> Nil {
  let document = "ws-rt-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(rt_a) = watershed.create_rich_text(doc_a)
  watershed.set(map_a, "doc", watershed.rich_text_handle_of(rt_a))
  let rt_b = resolve_rich_text_key_or_panic(doc_b, map_b, "doc")

  // Seed plain text and wait for both sides to see it before diverging.
  let assert Ok(seed) =
    rich_text.delta_from_json_string("[{\"insert\":\"Hello World\"}]")
  watershed.submit_rich_text(rt_a, seed)
  let assert Ok(seeded) =
    rich_text.document_from_json_string("[{\"insert\":\"Hello World\"}]")
  wait_until(50, fn() { watershed.rich_text_view(rt_b) == Some(seeded) })
  |> expect.to_be_true()

  // A bolds "Hello" (the first 5 UTF-16 code units); B concurrently appends
  // an emoji after "World". The two edits' ranges never overlap, so both the
  // formatting and the inserted emoji text survive OT transform on both
  // sides no matter which author the server treats as lower priority.
  let assert Ok(a_edit) =
    rich_text.delta_retain(
      rich_text.empty_delta(),
      5,
      rich_text.attributes([#("bold", json_ot.VBool(True))]),
    )
  watershed.submit_rich_text(rt_a, a_edit)

  let assert Ok(b_retain) =
    rich_text.delta_retain(
      rich_text.empty_delta(),
      11,
      rich_text.attributes([]),
    )
  let assert Ok(b_edit) =
    rich_text.delta_insert_text(b_retain, " 😀", rich_text.attributes([]))
  watershed.submit_rich_text(rt_b, b_edit)

  let assert Ok(expected) =
    rich_text.document_from_json_string(
      "[{\"insert\":\"Hello\",\"attributes\":{\"bold\":true}},{\"insert\":\" World 😀\"}]",
    )
  wait_until(50, fn() {
    watershed.rich_text_view(rt_a) == watershed.rich_text_view(rt_b)
    && watershed.rich_text_view(rt_a) == Some(expected)
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn resolve_rich_text_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.SharedRichText {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_rich_text(doc, value)
      }
    })
  case resolved {
    Ok(rt) -> rt
    Error(reason) ->
      panic as { "resolving rich_text at key " <> key <> " failed: " <> reason }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OR-map live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Tally-mode OR-map: concurrent increments from both clients sum.
pub fn or_map_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_or_map_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Register-mode OR-map: concurrent sets to one key converge to one value.
pub fn or_map_concurrent_conflict_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_or_map_conflict_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A fresh client bootstraps a tally OR-map child from a summary.
pub fn or_map_summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_or_map_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_or_map_converge_test() -> Nil {
  let document = "ws-orm-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(om_a) = watershed.create_or_map(doc_a, TallyMode)
  watershed.or_map_increment(om_a, "score", 2)
  watershed.set(map_a, "board", watershed.or_map_handle_of(om_a))
  let om_b = resolve_or_map_key_or_panic(doc_b, map_b, "board")
  wait_until(50, fn() {
    watershed.or_map_value(om_b, "score") == Some(Tally(2))
  })
  |> expect.to_be_true()

  watershed.or_map_increment(om_a, "score", 5)
  watershed.or_map_increment(om_b, "score", -1)
  wait_until(50, fn() {
    watershed.or_map_value(om_a, "score") == Some(Tally(6))
    && watershed.or_map_value(om_b, "score") == Some(Tally(6))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_or_map_conflict_test() -> Nil {
  let document = "ws-orm-cf-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(om_a) = watershed.create_or_map(doc_a, RegisterMode)
  watershed.set(map_a, "reg", watershed.or_map_handle_of(om_a))
  let om_b = resolve_or_map_key_or_panic(doc_b, map_b, "reg")

  // Concurrent register writes to the same key: the CRDT picks a deterministic
  // winner, so both clients must converge on the same register value.
  watershed.or_map_set(om_a, "owner", "from-a")
  watershed.or_map_set(om_b, "owner", "from-b")

  wait_until(50, fn() {
    let value_a = watershed.or_map_value(om_a, "owner")
    let value_b = watershed.or_map_value(om_b, "owner")
    value_a == value_b && is_register(value_a)
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_or_map_summary_test() -> Nil {
  let document = "ws-orm-sm-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(om_a) = watershed.create_or_map(doc_a, TallyMode)
  watershed.or_map_increment(om_a, "score", 9)
  watershed.set(map_a, "board", watershed.or_map_handle_of(om_a))

  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let om_c = resolve_or_map_key_or_panic(doc_c, map_c, "board")
  wait_until(50, fn() {
    watershed.or_map_value(om_c, "score") == Some(Tally(9))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn is_register(value: Option(or_map_kernel.OrMapValue)) -> Bool {
  case value {
    Some(Register(_)) -> True
    _ -> False
  }
}

@target(erlang)
fn resolve_or_map_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.OrMap {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_or_map(doc, value)
      }
    })
  case resolved {
    Ok(om) -> om
    Error(reason) ->
      panic as { "resolving or_map at key " <> key <> " failed: " <> reason }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OR-set live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Two clients converge on concurrent adds of distinct elements.
pub fn or_set_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_or_set_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Add-wins: a concurrent remove and re-add of one element keeps it present.
pub fn or_set_concurrent_conflict_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_or_set_conflict_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A fresh client bootstraps an OR-set child from a summary.
pub fn or_set_summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_or_set_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_or_set_converge_test() -> Nil {
  let document = "ws-ors-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(os_a) = watershed.create_or_set(doc_a)
  watershed.or_set_add(os_a, "alpha")
  watershed.set(map_a, "set", watershed.or_set_handle_of(os_a))
  let os_b = resolve_or_set_key_or_panic(doc_b, map_b, "set")
  wait_until(50, fn() { watershed.or_set_contains(os_b, "alpha") })
  |> expect.to_be_true()

  watershed.or_set_add(os_a, "beta")
  watershed.or_set_add(os_b, "gamma")
  wait_until(50, fn() { or_set_has_all(os_a) && or_set_has_all(os_b) })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn or_set_has_all(os: watershed.OrSet) -> Bool {
  watershed.or_set_contains(os, "alpha")
  && watershed.or_set_contains(os, "beta")
  && watershed.or_set_contains(os, "gamma")
  && list.length(watershed.or_set_values(os)) == 3
}

@target(erlang)
fn run_or_set_conflict_test() -> Nil {
  let document = "ws-ors-cf-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(os_a) = watershed.create_or_set(doc_a)
  watershed.or_set_add(os_a, "x")
  watershed.set(map_a, "set", watershed.or_set_handle_of(os_a))
  let os_b = resolve_or_set_key_or_panic(doc_b, map_b, "set")
  wait_until(50, fn() { watershed.or_set_contains(os_b, "x") })
  |> expect.to_be_true()

  // A removes the element while B concurrently re-adds it: add wins, so the
  // element survives on both replicas.
  watershed.or_set_remove(os_a, "x")
  watershed.or_set_add(os_b, "x")
  wait_until(50, fn() {
    watershed.or_set_contains(os_a, "x") && watershed.or_set_contains(os_b, "x")
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_or_set_summary_test() -> Nil {
  let document = "ws-ors-sm-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(os_a) = watershed.create_or_set(doc_a)
  watershed.or_set_add(os_a, "one")
  watershed.or_set_add(os_a, "two")
  watershed.set(map_a, "set", watershed.or_set_handle_of(os_a))

  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let os_c = resolve_or_set_key_or_panic(doc_c, map_c, "set")
  wait_until(50, fn() {
    watershed.or_set_contains(os_c, "one")
    && watershed.or_set_contains(os_c, "two")
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn resolve_or_set_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.OrSet {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_or_set(doc, value)
      }
    })
  case resolved {
    Ok(os) -> os
    Error(reason) ->
      panic as { "resolving or_set at key " <> key <> " failed: " <> reason }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register-collection live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Two clients see each other's writes to distinct keys.
pub fn register_collection_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_register_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Concurrent writes to one key converge to a single atomic value on both.
pub fn register_collection_concurrent_conflict_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_register_conflict_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A fresh client bootstraps a register collection from a summary.
pub fn register_collection_summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_register_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_register_converge_test() -> Nil {
  let document = "ws-reg-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(reg_a) = watershed.create_register_collection(doc_a)
  watershed.register_write(reg_a, "k1", json.string("v1"))
  watershed.set(map_a, "reg", watershed.register_collection_handle_of(reg_a))
  let reg_b = resolve_register_key_or_panic(doc_b, map_b, "reg")
  wait_until(50, fn() {
    watershed.register_get(reg_b, "k1") == Some(json.string("v1"))
  })
  |> expect.to_be_true()

  watershed.register_write(reg_b, "k2", json.string("v2"))
  wait_until(50, fn() {
    watershed.register_get(reg_a, "k2") == Some(json.string("v2"))
    && watershed.register_get(reg_b, "k1") == Some(json.string("v1"))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_register_conflict_test() -> Nil {
  let document = "ws-reg-cf-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(reg_a) = watershed.create_register_collection(doc_a)
  watershed.set(map_a, "reg", watershed.register_collection_handle_of(reg_a))
  let reg_b = resolve_register_key_or_panic(doc_b, map_b, "reg")

  // Concurrent writes to the same key: the consensus register resolves to a
  // single atomic value, so both clients must agree on the read.
  watershed.register_write(reg_a, "shared", json.string("from-a"))
  watershed.register_write(reg_b, "shared", json.string("from-b"))

  wait_until(50, fn() {
    let atomic_a = watershed.register_get(reg_a, "shared")
    let atomic_b = watershed.register_get(reg_b, "shared")
    atomic_a == atomic_b
    && atomic_a != None
    && watershed.register_versions(reg_a, "shared")
    == watershed.register_versions(reg_b, "shared")
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_register_summary_test() -> Nil {
  let document = "ws-reg-sm-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(reg_a) = watershed.create_register_collection(doc_a)
  watershed.register_write(reg_a, "persisted", json.string("kept"))
  watershed.set(map_a, "reg", watershed.register_collection_handle_of(reg_a))

  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let reg_c = resolve_register_key_or_panic(doc_c, map_c, "reg")
  wait_until(50, fn() {
    watershed.register_get(reg_c, "persisted") == Some(json.string("kept"))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn resolve_register_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.RegisterCollection {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_register_collection(doc, value)
      }
    })
  case resolved {
    Ok(reg) -> reg
    Error(reason) ->
      panic as { "resolving register at key " <> key <> " failed: " <> reason }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task-manager live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// A lone volunteer is assigned the task; the peer sees the same queue.
pub fn task_manager_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_task_manager_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Two clients race to volunteer: one is assigned, the other waits, and
/// completing the task reassigns it to the waiter.
pub fn task_manager_race_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_task_manager_race_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A fresh client bootstraps a task manager child from a summary.
pub fn task_manager_summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_task_manager_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_task_manager_converge_test() -> Nil {
  let document = "ws-tsk-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(tm_a) = watershed.create_task_manager(doc_a)
  watershed.set(map_a, "tasks", watershed.task_manager_handle_of(tm_a))
  let tm_b = resolve_task_manager_key_or_panic(doc_b, map_b, "tasks")

  // The optimistic outcome is Waiting; assignment is decided once the volunteer
  // op sequences, so poll task_assigned rather than trusting the return value.
  let _ = watershed.volunteer_for_task(tm_a, "t1")
  wait_until(50, fn() {
    watershed.task_assigned(tm_a, "t1")
    && watershed.task_assigned(tm_b, "t1") == False
    && watershed.task_queues(tm_a) == watershed.task_queues(tm_b)
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_task_manager_race_test() -> Nil {
  let document = "ws-tsk-rc-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(tm_a) = watershed.create_task_manager(doc_a)
  watershed.set(map_a, "tasks", watershed.task_manager_handle_of(tm_a))
  let tm_b = resolve_task_manager_key_or_panic(doc_b, map_b, "tasks")

  // Both volunteer for the same task; the server sequences the queue so exactly
  // one becomes the assignee.
  let _ = watershed.volunteer_for_task(tm_a, "t2")
  let _ = watershed.volunteer_for_task(tm_b, "t2")
  wait_until(50, fn() {
    watershed.task_assigned(tm_a, "t2") != watershed.task_assigned(tm_b, "t2")
    && watershed.task_queues(tm_a) == watershed.task_queues(tm_b)
  })
  |> expect.to_be_true()

  // The assignee abandons the task; the waiter is promoted to assignee.
  case watershed.task_assigned(tm_a, "t2") {
    True -> {
      watershed.abandon_task(tm_a, "t2")
      wait_until(50, fn() { watershed.task_assigned(tm_b, "t2") })
      |> expect.to_be_true()
    }
    False -> {
      watershed.abandon_task(tm_b, "t2")
      wait_until(50, fn() { watershed.task_assigned(tm_a, "t2") })
      |> expect.to_be_true()
    }
  }

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_task_manager_summary_test() -> Nil {
  let document = "ws-tsk-sm-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(tm_a) = watershed.create_task_manager(doc_a)
  watershed.set(map_a, "tasks", watershed.task_manager_handle_of(tm_a))
  let _ = watershed.volunteer_for_task(tm_a, "t1")
  wait_until(50, fn() { watershed.task_assigned(tm_a, "t1") })
  |> expect.to_be_true()

  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let tm_c = resolve_task_manager_key_or_panic(doc_c, map_c, "tasks")
  // The fresh client is not the assignee, but it sees the same task queue.
  wait_until(50, fn() {
    watershed.task_assigned(tm_c, "t1") == False
    && watershed.task_queues(tm_c) == watershed.task_queues(tm_a)
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn resolve_task_manager_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.TaskManager {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_task_manager(doc, value)
      }
    })
  case resolved {
    Ok(tm) -> tm
    Error(reason) ->
      panic as {
        "resolving task_manager at key " <> key <> " failed: " <> reason
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// G-Set live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Concurrent adds from both clients converge to the union.
pub fn g_set_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_g_set_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Adding the same element from both clients is idempotent: it appears once.
pub fn g_set_concurrent_conflict_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_g_set_conflict_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A fresh client bootstraps a g-set child from a summary and reads it.
pub fn g_set_summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_g_set_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_g_set_converge_test() -> Nil {
  let document = "ws-gst-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(set_a) = watershed.create_g_set(doc_a)
  watershed.set(map_a, "set", watershed.g_set_handle_of(set_a))
  let set_b = resolve_g_set_key_or_panic(doc_b, map_b, "set")

  watershed.g_set_add(set_a, "alpha")
  watershed.g_set_add(set_b, "beta")

  wait_until(50, fn() {
    strings_eq(watershed.g_set_values(set_a), ["alpha", "beta"])
    && strings_eq(watershed.g_set_values(set_b), ["alpha", "beta"])
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_g_set_conflict_test() -> Nil {
  let document = "ws-gst-cf-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(set_a) = watershed.create_g_set(doc_a)
  watershed.set(map_a, "set", watershed.g_set_handle_of(set_a))
  let set_b = resolve_g_set_key_or_panic(doc_b, map_b, "set")

  // Both add the shared element concurrently, plus one distinct element each.
  watershed.g_set_add(set_a, "shared")
  watershed.g_set_add(set_a, "only-a")
  watershed.g_set_add(set_b, "shared")
  watershed.g_set_add(set_b, "only-b")

  wait_until(50, fn() {
    strings_eq(watershed.g_set_values(set_a), ["shared", "only-a", "only-b"])
    && strings_eq(watershed.g_set_values(set_b), ["shared", "only-a", "only-b"])
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_g_set_summary_test() -> Nil {
  let document = "ws-gst-sm-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(set_a) = watershed.create_g_set(doc_a)
  watershed.g_set_add(set_a, "one")
  watershed.g_set_add(set_a, "two")
  watershed.set(map_a, "set", watershed.g_set_handle_of(set_a))

  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let set_c = resolve_g_set_key_or_panic(doc_c, map_c, "set")
  wait_until(50, fn() {
    strings_eq(watershed.g_set_values(set_c), ["one", "two"])
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn resolve_g_set_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.GSet {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_g_set(doc, value)
      }
    })
  case resolved {
    Ok(set) -> set
    Error(reason) ->
      panic as { "resolving g_set at key " <> key <> " failed: " <> reason }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2P-Set live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Concurrent adds from both clients converge to the union.
pub fn two_p_set_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_two_p_set_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A concurrent remove wins over a re-add: the tombstone is permanent.
pub fn two_p_set_remove_wins_conflict_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_two_p_set_conflict_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A fresh client bootstraps a 2P-set child from a summary and reads it.
pub fn two_p_set_summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_two_p_set_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_two_p_set_converge_test() -> Nil {
  let document = "ws-tps-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(set_a) = watershed.create_two_p_set(doc_a)
  watershed.set(map_a, "set", watershed.two_p_set_handle_of(set_a))
  let set_b = resolve_two_p_set_key_or_panic(doc_b, map_b, "set")

  watershed.two_p_set_add(set_a, "alpha")
  watershed.two_p_set_add(set_a, "beta")
  watershed.two_p_set_add(set_b, "gamma")

  wait_until(50, fn() {
    strings_eq(watershed.two_p_set_values(set_a), ["alpha", "beta", "gamma"])
    && strings_eq(watershed.two_p_set_values(set_b), ["alpha", "beta", "gamma"])
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_two_p_set_conflict_test() -> Nil {
  let document = "ws-tps-cf-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(set_a) = watershed.create_two_p_set(doc_a)
  watershed.set(map_a, "set", watershed.two_p_set_handle_of(set_a))
  let set_b = resolve_two_p_set_key_or_panic(doc_b, map_b, "set")

  // Seed the element and wait for both sides to see it.
  watershed.two_p_set_add(set_a, "x")
  wait_until(50, fn() { watershed.two_p_set_contains(set_b, "x") })
  |> expect.to_be_true()

  // A removes it while B re-adds it concurrently; the tombstone wins.
  watershed.two_p_set_remove(set_a, "x")
  watershed.two_p_set_add(set_b, "x")

  wait_until(50, fn() {
    watershed.two_p_set_contains(set_a, "x") == False
    && watershed.two_p_set_contains(set_b, "x") == False
    && watershed.two_p_set_values(set_a) == watershed.two_p_set_values(set_b)
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_two_p_set_summary_test() -> Nil {
  let document = "ws-tps-sm-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(set_a) = watershed.create_two_p_set(doc_a)
  watershed.two_p_set_add(set_a, "keep")
  watershed.two_p_set_add(set_a, "drop")
  watershed.two_p_set_remove(set_a, "drop")
  watershed.set(map_a, "set", watershed.two_p_set_handle_of(set_a))

  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let set_c = resolve_two_p_set_key_or_panic(doc_c, map_c, "set")
  wait_until(50, fn() {
    strings_eq(watershed.two_p_set_values(set_c), ["keep"])
    && watershed.two_p_set_contains(set_c, "drop") == False
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn resolve_two_p_set_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.TwoPSet {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_two_p_set(doc, value)
      }
    })
  case resolved {
    Ok(set) -> set
    Error(reason) ->
      panic as { "resolving two_p_set at key " <> key <> " failed: " <> reason }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Directory live tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Concurrent root writes from both clients converge to the merged entries.
pub fn directory_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_directory_converge_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Both clients create the same subdirectory and write distinct keys into it;
/// they converge to one subdirectory holding both keys.
pub fn directory_nested_subdir_conflict_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_directory_conflict_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// A fresh client bootstraps a directory child from a summary and reads its
/// nested structure.
pub fn directory_summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_directory_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_directory_converge_test() -> Nil {
  let document = "ws-dir-cv-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(dir_a) = watershed.create_directory(doc_a)
  watershed.set(map_a, "dir", watershed.directory_handle_of(dir_a))
  let dir_b = resolve_directory_key_or_panic(doc_b, map_b, "dir")

  watershed.directory_set(dir_a, "/", "from-a", json.string("a"))
  watershed.directory_set(dir_b, "/", "from-b", json.string("b"))

  let expected = [#("from-a", json.string("a")), #("from-b", json.string("b"))]
  wait_until(50, fn() {
    entries_eq(watershed.directory_entries(dir_a, "/"), expected)
    && entries_eq(watershed.directory_entries(dir_b, "/"), expected)
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_directory_conflict_test() -> Nil {
  let document = "ws-dir-cf-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  let assert Ok(dir_a) = watershed.create_directory(doc_a)
  watershed.set(map_a, "dir", watershed.directory_handle_of(dir_a))
  let dir_b = resolve_directory_key_or_panic(doc_b, map_b, "dir")

  // Both create the "plans" subdirectory and write a distinct key into it.
  watershed.directory_create_subdirectory(dir_a, "/", "plans")
  watershed.directory_set(dir_a, "/plans", "from-a", json.string("a"))
  watershed.directory_create_subdirectory(dir_b, "/", "plans")
  watershed.directory_set(dir_b, "/plans", "from-b", json.string("b"))

  let expected = [#("from-a", json.string("a")), #("from-b", json.string("b"))]
  wait_until(50, fn() {
    watershed.directory_subdirectories(dir_a, "/") == ["plans"]
    && watershed.directory_subdirectories(dir_b, "/") == ["plans"]
    && entries_eq(watershed.directory_entries(dir_a, "/plans"), expected)
    && entries_eq(watershed.directory_entries(dir_b, "/plans"), expected)
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_directory_summary_test() -> Nil {
  let document = "ws-dir-sm-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(dir_a) = watershed.create_directory(doc_a)
  watershed.set(map_a, "dir", watershed.directory_handle_of(dir_a))
  watershed.directory_set(dir_a, "/", "title", json.string("hello"))
  watershed.directory_create_subdirectory(dir_a, "/", "child")
  watershed.directory_set(dir_a, "/child", "note", json.string("nested"))

  wait_until(50, fn() { watershed.is_synced(doc_a) }) |> expect.to_be_true()
  case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(_) -> Nil
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }

  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  let dir_c = resolve_directory_key_or_panic(doc_c, map_c, "dir")
  wait_until(50, fn() {
    watershed.directory_get(dir_c, "/", "title") == Some(json.string("hello"))
    && watershed.directory_has_subdirectory(dir_c, "/", "child")
    && watershed.directory_get(dir_c, "/child", "note")
    == Some(json.string("nested"))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_c)
}

@target(erlang)
fn resolve_directory_key_or_panic(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.SharedDirectory {
  let resolved =
    wait_until_ok(50, fn() {
      case watershed.get(map, key) {
        None -> Error("key absent")
        Some(value) -> watershed.resolve_directory(doc, value)
      }
    })
  case resolved {
    Ok(dir) -> dir
    Error(reason) ->
      panic as { "resolving directory at key " <> key <> " failed: " <> reason }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order-independent collection comparison helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Two string lists hold the same elements, ignoring order.
fn strings_eq(left: List(String), right: List(String)) -> Bool {
  list.length(left) == list.length(right)
  && list.all(left, fn(x) { list.contains(right, x) })
}

@target(erlang)
/// Two entry lists hold the same #(key, value) pairs, ignoring order.
fn entries_eq(
  left: List(#(String, Json)),
  right: List(#(String, Json)),
) -> Bool {
  list.length(left) == list.length(right)
  && list.all(left, fn(x) { list.contains(right, x) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Typed channel fields (TX2)
// ─────────────────────────────────────────────────────────────────────────────

/// Schema tag for the typed-channel-field round-trip test.
type FieldDoc

@target(erlang)
/// TX2 exit criterion: every channel kind round-trips through its typed
/// `set_*_field` / `resolve_*_field` pair across two live clients, and an
/// absent key resolves to `Ok(None)`.
pub fn typed_channel_fields_round_trip_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_typed_channel_fields_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Poll until the field resolves to `Ok(Some(_))` on the remote client.
fn expect_resolves(check: fn() -> Result(Option(a), String)) -> Nil {
  wait_until(50, fn() {
    case check() {
      Ok(Some(_)) -> True
      _ -> False
    }
  })
  |> expect.to_be_true()
}

@target(erlang)
fn run_typed_channel_fields_test() -> Nil {
  let document = "watershed-tcf-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let root_a: watershed.TypedMap(FieldDoc) =
    watershed.typed(watershed.root(doc_a))
  let root_b: watershed.TypedMap(FieldDoc) =
    watershed.typed(watershed.root(doc_b))

  // One field per channel kind.
  let map_f: schema.ChannelField(FieldDoc, schema.MapChannel) =
    schema.channel_field("map")
  let counter_f: schema.ChannelField(FieldDoc, schema.CounterChannel) =
    schema.channel_field("counter")
  let json_ot_f: schema.ChannelField(FieldDoc, schema.JsonOtChannel) =
    schema.channel_field("json_ot")
  let or_map_f: schema.ChannelField(FieldDoc, schema.OrMapChannel) =
    schema.channel_field("or_map")
  let or_set_f: schema.ChannelField(FieldDoc, schema.OrSetChannel) =
    schema.channel_field("or_set")
  let registers_f: schema.ChannelField(
    FieldDoc,
    schema.RegisterCollectionChannel,
  ) = schema.channel_field("registers")
  let claims_f: schema.ChannelField(FieldDoc, schema.ClaimsChannel) =
    schema.channel_field("claims")
  let tasks_f: schema.ChannelField(FieldDoc, schema.TaskManagerChannel) =
    schema.channel_field("tasks")
  let g_set_f: schema.ChannelField(FieldDoc, schema.GSetChannel) =
    schema.channel_field("g_set")
  let two_p_set_f: schema.ChannelField(FieldDoc, schema.TwoPSetChannel) =
    schema.channel_field("two_p_set")
  let directory_f: schema.ChannelField(FieldDoc, schema.DirectoryChannel) =
    schema.channel_field("directory")
  let pn_counter_f: schema.ChannelField(FieldDoc, schema.PnCounterChannel) =
    schema.channel_field("pn_counter")
  let pact_map_f: schema.ChannelField(FieldDoc, schema.PactMapChannel) =
    schema.channel_field("pact_map")
  let ordered_f: schema.ChannelField(FieldDoc, schema.OrderedCollectionChannel) =
    schema.channel_field("ordered")

  // A creates one channel of every kind and stores each typed handle.
  let assert Ok(child_map) = watershed.create_map(doc_a)
  watershed.set_map_field(root_a, map_f, child_map)
  let assert Ok(counter) = watershed.create_counter(doc_a)
  watershed.set_counter_field(root_a, counter_f, counter)
  let assert Ok(json_ot) = watershed.create_json_ot(doc_a)
  watershed.set_json_ot_field(root_a, json_ot_f, json_ot)
  let assert Ok(or_map) = watershed.create_or_map(doc_a, RegisterMode)
  watershed.set_or_map_field(root_a, or_map_f, or_map)
  let assert Ok(or_set) = watershed.create_or_set(doc_a)
  watershed.set_or_set_field(root_a, or_set_f, or_set)
  let assert Ok(registers) = watershed.create_register_collection(doc_a)
  watershed.set_register_collection_field(root_a, registers_f, registers)
  let assert Ok(claims) = watershed.create_claims(doc_a)
  watershed.set_claims_field(root_a, claims_f, claims)
  let assert Ok(tasks) = watershed.create_task_manager(doc_a)
  watershed.set_task_manager_field(root_a, tasks_f, tasks)
  let assert Ok(g_set) = watershed.create_g_set(doc_a)
  watershed.set_g_set_field(root_a, g_set_f, g_set)
  let assert Ok(two_p_set) = watershed.create_two_p_set(doc_a)
  watershed.set_two_p_set_field(root_a, two_p_set_f, two_p_set)
  let assert Ok(directory) = watershed.create_directory(doc_a)
  watershed.set_directory_field(root_a, directory_f, directory)
  let assert Ok(pn_counter) = watershed.create_pn_counter(doc_a)
  watershed.set_pn_counter_field(root_a, pn_counter_f, pn_counter)
  let assert Ok(pact_map) = watershed.create_pact_map(doc_a)
  watershed.set_pact_map_field(root_a, pact_map_f, pact_map)
  let assert Ok(ordered) = watershed.create_ordered_collection(doc_a)
  watershed.set_ordered_collection_field(root_a, ordered_f, ordered)

  // B resolves every kind once the handles arrive.
  expect_resolves(fn() { watershed.resolve_map_field(doc_b, root_b, map_f) })
  expect_resolves(fn() {
    watershed.resolve_counter_field(doc_b, root_b, counter_f)
  })
  expect_resolves(fn() {
    watershed.resolve_json_ot_field(doc_b, root_b, json_ot_f)
  })
  expect_resolves(fn() {
    watershed.resolve_or_map_field(doc_b, root_b, or_map_f)
  })
  expect_resolves(fn() {
    watershed.resolve_or_set_field(doc_b, root_b, or_set_f)
  })
  expect_resolves(fn() {
    watershed.resolve_register_collection_field(doc_b, root_b, registers_f)
  })
  expect_resolves(fn() {
    watershed.resolve_claims_field(doc_b, root_b, claims_f)
  })
  expect_resolves(fn() {
    watershed.resolve_task_manager_field(doc_b, root_b, tasks_f)
  })
  expect_resolves(fn() { watershed.resolve_g_set_field(doc_b, root_b, g_set_f) })
  expect_resolves(fn() {
    watershed.resolve_two_p_set_field(doc_b, root_b, two_p_set_f)
  })
  expect_resolves(fn() {
    watershed.resolve_directory_field(doc_b, root_b, directory_f)
  })
  expect_resolves(fn() {
    watershed.resolve_pn_counter_field(doc_b, root_b, pn_counter_f)
  })
  expect_resolves(fn() {
    watershed.resolve_pact_map_field(doc_b, root_b, pact_map_f)
  })
  expect_resolves(fn() {
    watershed.resolve_ordered_collection_field(doc_b, root_b, ordered_f)
  })

  // An absent key is Ok(None), not an error.
  let missing: schema.ChannelField(FieldDoc, schema.CounterChannel) =
    schema.channel_field("missing")
  watershed.resolve_counter_field(doc_b, root_b, missing)
  |> expect.to_equal(Ok(None))

  // The resolved channel is live: an increment on A converges on B.
  watershed.increment(counter, 5)
  let assert Ok(Some(counter_b)) =
    watershed.resolve_counter_field(doc_b, root_b, counter_f)
  wait_until(50, fn() { watershed.counter_value(counter_b) == Some(5) })
  |> expect.to_be_true()

  // The new kinds are equally live: a PN-counter delta on A converges on B.
  watershed.pn_counter_update(pn_counter, 3)
  let assert Ok(Some(pn_counter_b)) =
    watershed.resolve_pn_counter_field(doc_b, root_b, pn_counter_f)
  wait_until(50, fn() { watershed.pn_counter_value(pn_counter_b) == Some(3) })
  |> expect.to_be_true()

  // An enqueue on the ordered collection is observed by B.
  watershed.ordered_add(ordered, json.string("job-1"))
  let assert Ok(Some(ordered_b)) =
    watershed.resolve_ordered_collection_field(doc_b, root_b, ordered_f)
  wait_until(50, fn() { watershed.ordered_size(ordered_b) == Some(1) })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
/// TX3 exit criterion: `subscribe_field` decodes both sides of a change,
/// filters writes to other keys, and reports `Invalid` on a type-confused
/// write.
pub fn typed_field_subscription_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_typed_field_subscription_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn receive_field_change(
  changes: process.Subject(schema.FieldChange(a)),
) -> schema.FieldChange(a) {
  case process.receive(from: changes, within: 5000) {
    Ok(change) -> change
    Error(_) -> panic as "timed out waiting for a field change"
  }
}

@target(erlang)
fn run_typed_field_subscription_test() -> Nil {
  let document = "watershed-fld-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let root_a: watershed.TypedMap(FieldDoc) =
    watershed.typed(watershed.root(doc_a))
  let raw_a = watershed.root(doc_a)
  let score: schema.Field(FieldDoc, Int) =
    schema.field("score", json.int, decode.int)

  let changes = watershed.subscribe_field(root_a, score)

  // The first write to the field has no previous value; both sides decode.
  watershed.set_field(root_a, score, 7)
  receive_field_change(changes)
  |> expect.to_equal(schema.FieldChange(
    value: Ok(Some(7)),
    previous: Ok(None),
    local: True,
  ))

  // A second write carries the previous value.
  watershed.set_field(root_a, score, 9)
  receive_field_change(changes)
  |> expect.to_equal(schema.FieldChange(
    value: Ok(Some(9)),
    previous: Ok(Some(9 - 2)),
    local: True,
  ))

  // A write to a different key must not reach this subscription: it produces
  // no `FieldChange`, so the next delivered change is the type-confused write
  // below — never the foreign key.
  watershed.set(raw_a, "other", json.string("ignored"))

  // A type-confused write (a String where the field expects an Int, as a peer
  // could send through the untyped API) is delivered with an `Invalid` value
  // rather than crashing the fan-out; the previous value still decodes.
  watershed.set(raw_a, "score", json.string("nope"))
  let change = receive_field_change(changes)
  case change.value {
    Error(schema.Invalid(_)) -> Nil
    other -> panic as { "expected Invalid value, got " <> string.inspect(other) }
  }
  change.previous |> expect.to_equal(Ok(Some(9)))
  change.local |> expect.to_be_true()

  watershed.close(doc_a)
}

@target(erlang)
/// `subscribe_typed` watches a whole typed map's events without dropping to the
/// untyped API, and — like `subscribe` — narrows to `map_kernel.MapEvent`.
pub fn typed_map_subscription_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_typed_map_subscription_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_typed_map_subscription_test() -> Nil {
  let document = "watershed-tms-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let root_a: watershed.TypedMap(FieldDoc) =
    watershed.typed(watershed.root(doc_a))
  let score: schema.Field(FieldDoc, Int) =
    schema.field("score", json.int, decode.int)

  let events = watershed.subscribe_typed(root_a)

  // A typed write surfaces as a narrowed map event on the whole-map subject —
  // no `watershed.untyped(...)` escape needed at the call site. Decode the
  // event's raw value through the field to compare robustly.
  watershed.set_field(root_a, score, 7)
  case process.receive(from: events, within: 5000) {
    Ok(map_kernel.ValueChanged(key: "score", value: value, ..)) ->
      schema.decode_optional(score, value) |> expect.to_equal(Ok(Some(7)))
    Ok(other) -> panic as { "unexpected map event: " <> string.inspect(other) }
    Error(_) -> panic as "timed out waiting for a typed-map event"
  }

  watershed.close(doc_a)
}

@target(erlang)
/// TX3 exit criterion: `subscribe_counter` yields a subject narrowed to
/// `counter_kernel.CounterEvent`. The `case` below is exhaustive over the
/// counter event type alone — a `channel.MapEvent` arm here would not compile,
/// which is how a counter subscriber is kept from ever seeing map events.
pub fn narrowed_counter_subscription_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_narrowed_counter_subscription_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_narrowed_counter_subscription_test() -> Nil {
  let document = "watershed-ncs-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  let assert Ok(counter) = watershed.create_counter(doc_a)
  watershed.set(map_a, "tally", watershed.counter_handle_of(counter))

  let events = watershed.subscribe_counter(counter)
  watershed.increment(counter, 3)
  case process.receive(from: events, within: 5000) {
    Ok(counter_kernel.Incremented(increment_amount: amount, new_value: value)) -> {
      amount |> expect.to_equal(3)
      value |> expect.to_equal(3)
    }
    Error(_) -> panic as "timed out waiting for a counter event"
  }

  watershed.close(doc_a)
}

@target(erlang)
/// FP3 exit criterion: the three kinds that had no subscription at all now
/// deliver a *peer's* mutation as a narrowed event on each facade. Before this
/// they were write-and-poll — an app could mutate and read, but had no way to
/// learn that anyone else had.
pub fn narrowed_subscriptions_observe_peer_mutations_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_narrowed_subscriptions_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_narrowed_subscriptions_test() -> Nil {
  let document = "watershed-sub3-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")

  let assert Ok(counter_a) = watershed.create_pn_counter(doc_a)
  watershed.set(
    watershed.root(doc_a),
    "votes",
    watershed.pn_counter_handle_of(counter_a),
  )
  let assert Ok(queue_a) = watershed.create_ordered_collection(doc_a)
  watershed.set(
    watershed.root(doc_a),
    "jobs",
    watershed.ordered_collection_handle_of(queue_a),
  )
  let assert Ok(pact_a) = watershed.create_pact_map(doc_a)
  watershed.set(
    watershed.root(doc_a),
    "tempo",
    watershed.pact_map_handle_of(pact_a),
  )

  // B resolves each kind, then subscribes *before* A mutates.
  let assert Ok(counter_b) =
    wait_until_ok(50, fn() { resolve_at(doc_b, "votes", resolve_pn_counter) })
  let assert Ok(queue_b) =
    wait_until_ok(50, fn() {
      resolve_at(doc_b, "jobs", watershed.resolve_ordered_collection)
    })
  let assert Ok(pact_b) =
    wait_until_ok(50, fn() { resolve_at(doc_b, "tempo", resolve_pact_map) })

  let counter_events = watershed.subscribe_pn_counter(counter_b)
  let queue_events = watershed.subscribe_ordered_collection(queue_b)
  let pact_events = watershed.subscribe_pact_map(pact_b)

  watershed.pn_counter_update(counter_a, -3)
  watershed.ordered_add(queue_a, json.string("job1"))
  watershed.pact_map_set(pact_a, "bpm", json.int(120))

  // Each `case` is exhaustive over its own kernel's event type alone, which is
  // what "narrowed" buys: a subscriber cannot be handed another kind's event.
  case process.receive(from: counter_events, within: 5000) {
    Ok(pn_counter_kernel.Updated(applied: applied, new_value: value)) -> {
      applied |> expect.to_equal(-3)
      value |> expect.to_equal(-3)
    }
    Error(_) -> panic as "timed out waiting for a pn-counter event"
  }

  case process.receive(from: queue_events, within: 5000) {
    Ok(_event) -> Nil
    Error(_) -> panic as "timed out waiting for an ordered-collection event"
  }

  // The PactMap transitions are the protocol: pending on sequencing, accepted
  // once the signoff list drains.
  case process.receive(from: pact_events, within: 5000) {
    Ok(pact_map_kernel.WentPending("bpm")) -> Nil
    Ok(other) ->
      panic as { "unexpected pact-map event: " <> string.inspect(other) }
    Error(_) -> panic as "timed out waiting for a pact-map pending event"
  }
  case process.receive(from: pact_events, within: 5000) {
    Ok(pact_map_kernel.WentAccepted("bpm")) -> Nil
    Ok(other) ->
      panic as { "unexpected pact-map event: " <> string.inspect(other) }
    Error(_) -> panic as "timed out waiting for a pact-map accepted event"
  }

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
/// Resolve a channel stored under `key` on the root map, retrying while the
/// handle is still replicating.
fn resolve_at(
  document: watershed.Document,
  key: String,
  resolver: fn(watershed.Document, Json) -> Result(a, String),
) -> Result(a, String) {
  case watershed.get(watershed.root(document), key) {
    None -> Error("handle for " <> key <> " has not replicated yet")
    Some(handle) -> resolver(document, handle)
  }
}

@target(erlang)
fn resolve_pn_counter(
  document: watershed.Document,
  value: Json,
) -> Result(watershed.PnCounter, String) {
  watershed.resolve_pn_counter(document, value)
}

@target(erlang)
fn resolve_pact_map(
  document: watershed.Document,
  value: Json,
) -> Result(watershed.PactMap, String) {
  watershed.resolve_pact_map(document, value)
}

@target(erlang)
/// TX4 exit criterion: two clients bootstrap the same empty document with
/// `ensure_*` and adopt the same sequenced channel; `ensure_field` set-if-
/// absent converges under a race; a late joiner resolves without re-seeding.
pub fn ensure_bootstrap_race_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_ensure_bootstrap_race_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_ensure_bootstrap_race_test() -> Nil {
  let document = "watershed-ens-" <> int.to_string(system_time(Second))
  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let root_a: watershed.TypedMap(FieldDoc) =
    watershed.typed(watershed.root(doc_a))
  let root_b: watershed.TypedMap(FieldDoc) =
    watershed.typed(watershed.root(doc_b))

  let tally_f: schema.ChannelField(FieldDoc, schema.CounterChannel) =
    schema.channel_field("tally")
  let title_f: schema.Field(FieldDoc, String) =
    schema.field("title", json.string, decode.string)

  // Both clients ensure the same slot on an empty document. Whoever seeds
  // first wins the root key; the other adopts that handle.
  let assert Ok(counter_a) = watershed.ensure_counter(doc_a, root_a, tally_f)
  let assert Ok(counter_b) = watershed.ensure_counter(doc_b, root_b, tally_f)

  // Adopting the same channel means an increment on A is seen through B.
  watershed.increment(counter_a, 4)
  wait_until(50, fn() { watershed.counter_value(counter_b) == Some(4) })
  |> expect.to_be_true()

  // ensure_field is set-if-absent: both racers set, last-writer-wins settles
  // one value both clients converge on.
  watershed.ensure_field(root_a, title_f, "from-a")
  watershed.ensure_field(root_b, title_f, "from-b")
  wait_until(50, fn() {
    case
      watershed.get_field(root_a, title_f),
      watershed.get_field(root_b, title_f)
    {
      Ok(Some(a)), Ok(Some(b)) -> a == b
      _, _ -> False
    }
  })
  |> expect.to_be_true()

  // A late joiner resolves the existing channel without seeding a new one.
  let doc_c = connect_or_panic(document, "user-c")
  let root_c: watershed.TypedMap(FieldDoc) =
    watershed.typed(watershed.root(doc_c))
  let assert Ok(counter_c) = watershed.ensure_counter(doc_c, root_c, tally_f)
  wait_until(50, fn() { watershed.counter_value(counter_c) == Some(4) })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
  watershed.close(doc_c)
}

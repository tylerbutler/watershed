# Summary bootstrap plan — making join cost proportional to recent history, not to all of it

**Date:** 2026-08-09
**Builds on:** `2026-08-09-consensus-replay-quorum-plan.md` (the replay-membership fix this depends on, and whose two open pieces are folded in here), `tylerbutler/levee#85` (the floodgate half).
**Benchmark:** Fluid Framework's summarizer. Fluid elects a dedicated summarizer client and has the server prompt it; the design question below is how much of that we want.
**Status:** SB1, SB2, SB3, SB4, SB7 shipped. Documents now summarize themselves when asked to — the policy exists, both runtimes drive it, and it is on in the drum machine. What is left is turning it on by default (SB6) and the docs (SB8). SB5 is an unimplemented server feature, not a broken test. Rungs below carry their outcomes.

## Why

A document accumulates ops forever. Replaying all of them on every join makes a document slower to enter the older it gets, and there is no point at which that stops — a year-old document is a year of ops to anyone who opens it.

This is the only statement of the goal anywhere in the repo, and until now it lived in user-facing prose rather than in a plan: `website/src/pages/runtime/reconnect.astro:22-28`. Everything the last two weeks of consensus work unblocked was in service of it.

**Summary bootstrap makes joining cost proportional to ops-since-checkpoint instead of ops-ever.** That is the whole goal. This plan is about turning it on.

## Where it actually stands

The surprising part, and the reason this plan exists rather than a one-line ticket: **the machinery is built and nothing uses it.**

| Piece | State |
|---|---|
| `summarize` on both facades | ✅ `watershed.gleam:3087`, `watershed_js.gleam:2911` |
| Blob format + upload | ✅ `wire/summary_blob.gleam` (v3), `git_storage.upload_summary` |
| Server records the pointer | ✅ floodgate `SubmitSummary` → `store.put_summary` (`session.gleam:1133-1147`) |
| Handshake offers it | ✅ `summaryContext` → `load_summary_then_bootstrap` (`runtime_js.gleam:1782`, `runtime.gleam:2439`) |
| Replay membership from the log | ✅ commit `0d94d7a` |
| **Anything that calls `summarize`** | ✅ SB3 — `auto_summarize` installs a policy; the runtime decides |
| Checkpoint roster in the blob | ✅ blob v4, SB2 |
| Load point matches the blob | ✅ SB1 |
| Durable log with matched join/leave | ✅ floodgate `0b24bbd`, levee#85 closed |
| `get_versions` / `load_version` | ❌ no server implements `/versions` — see SB5 |

*(Written when `summarize` had no caller in `src/`, `examples/`, `website/`, or any test outside the gated ones — so every document replayed from sequence number zero, paging through `fetch_deltas` past floodgate's 1000-op `initialMessages` cap. That is what SB3 closed. Floodgate still never asks for a summary: there is no summarizer election and no nack prompting one — it accepts summarize ops, stores what it is given, and broadcasts the op to the room.)*

## Decisions already made (flagged — confirm before SB1)

1. **Clients summarize; the server never does.** The blob is authored client-side and is opaque to floodgate — `initial_summary.persist` stores a client-supplied payload rather than authoring one. Keeping it that way means the summary format stays a watershed concern and can be versioned without a server release. *Rejected:* server-side summarization, which would require floodgate to link a Gleam kernel implementation and would make every kernel change a server deploy.
2. **The checkpoint roster goes in the blob, not on the ops.** Membership at the checkpoint is the same kind of state as a kernel snapshot at the checkpoint, so it belongs in the same object. See the replay plan's "Options considered" for why per-op roster stamping was rejected.
3. **Summarization is a policy, not an API change.** `summarize` already does the right thing; what is missing is anything deciding *when*. That decision is the substance of this plan.
4. **No format migration.** Blob v3 → v4 is a clean cut: loaders reject versions they do not recognise (`summary_blob.gleam:60-78`), stored documents are reset rather than migrated, and nothing external consumes the format.

## Verify first: does the load point match the blob?

**This is flagged as SB1 because it invalidates the rest of the plan if it is real.**

The blob records the sequence number its state was captured at (`summary_blob.encode_channels`), but both runtimes deliberately discard it:

```gleam
// The blob records the SN it was captured at, but the
// authoritative load point is the server's summaryContext.
sequence_number: ctx.sequence_number,
```

And the server's number is the **summarize op's own** sequence number (`put_summary(storage, t, handle, summary_sn)`), assigned when the op is sequenced. The summarize op carries `handle`, `message`, `parents`, `head` — and no sequence number (`wire/ops.gleam:118-138`), so floodgate has nothing else to use.

Uploading is asynchronous and `summarize`'s own docstring says the op's SN is drawn at push time rather than at upload start. If a peer sequences an op during the upload window, the blob captures state at `X` while the pointer records `X + k`. A loading client then seeds channel state from `X`, sets `last_seen_sn` to `X + k`, and **never replays the ops in between**.

If that is right it is silent state loss, it predates everything in this plan, and it applies to the roster identically — a roster captured at `X` presented as the roster at `X + k` is stale by whatever joined or left in the window.

*(Correction, on execution: the area is better covered than this said. Roughly a dozen gated tests in `integration_test.gleam` exercise summarize→bootstrap, not just `summary_versions_test`; all of them pass. See "How SB1 was actually settled".)*

Three candidate fixes, if confirmed:

- **Carry the captured SN in the summarize op** and have floodgate record that instead of the op's SN. Most correct; needs a floodgate change and a wire addition.
- **Trust the blob's own `sequenceNumber` on load** rather than `summaryContext`. Purely client-side. Requires the pointer to still be usable for *fetching*, which it is — the handle is the tree SHA.
- **Refuse to push the summarize op if the core advanced during upload**, and retry. Cheapest and safest, at the cost of livelock under constant traffic.

The second is probably right, and it is client-only, but confirm the hazard before choosing.

## The open question: who summarizes, and when

Nothing decides this today. Three shapes:

**(a) Every client, on a threshold, with jitter.** Each client summarizes when it is synced and more than *N* ops have been sequenced since the current summary. Concurrent summaries are harmless — both upload, both push, the later `put_summary` wins — so the cost of a race is one redundant blob upload. Zero coordination, zero server change, self-healing: any connected client will eventually do it.

**(b) An elected summarizer, via `TaskManager`.** Exactly what `TaskManager` is for, and it would be the kind's first real use in the codebase. One client holds the `"summarizer"` role and does the work; the role releases automatically when it disconnects. Costs a coordination dependency, and a document whose only write client is idle never summarizes.

**(c) Server-prompted**, the Fluid model. Floodgate signals when a document is due. Best global knowledge, and the only option that needs a levee change on top of levee#85.

**Build (a).** The waste is one upload per race and the failure mode is "summarized twice", which is benign. (b) is worth revisiting once there is evidence the redundancy costs anything real, and it is a much better demo of `TaskManager` than a plan justification. (c) should not be entered into before there is a reason floodgate needs an opinion.

Threshold, jitter window, and whether it is opt-in are configuration, not architecture — pick them in SB3 and expect to tune them.

## Data model

Blob v4 adds one field:

```gleam
pub const version = 4

json.object([
  #("watershedSummaryVersion", json.int(version)),
  #("sequenceNumber", json.int(sequence_number)),
  #("members", json.array(members, json.int)),   // new
  #("channels", json.array(channels, ...)),
])
```

`members` is the connected roster at `sequenceNumber`, as the kernel-side integer ids consensus kernels tie-break on — the same derivation `watershed/client_id.to_int` performs, so it matches what a replayed `join` produces. `runtime_core.Summary.members` already exists to receive it (`runtime_core.gleam:163`); both runtimes currently pass `[]` and this is what fills them.

`summarize` runs only on a synced client, so `core.members` at that moment *is* the roster at `last_seen_sn` — subject to SB1.

## Rungs

- **SB1 — ✅ done.** Settled by construction rather than by proving the race: `runtime_core.summary_from_blob` now takes the load point from the blob's own `sequenceNumber`, and both runtimes call it. Correct either way — when the two numbers agree it is identical, and when they differ the window surfaces as a `MissingPrefix` that the existing `fetch_deltas` → `resume_bootstrap` path fills. See "How SB1 was actually settled" below.
- **SB2 — ✅ done.** Blob v4 carries `members`; `git_storage.upload_summary` takes it, `runtime_core.summary_members` supplies it, both load points seed from it. v3 and a v4 without `members` are both refused rather than read as an empty room. Gate met in `roster_test`: a proposal sequenced after the checkpoint reconstructs the signoff list a present client froze, and the same test fails with an empty checkpoint roster.
- **SB3 — ✅ done.** `watershed/summary_policy` carries the knobs (threshold 500, jitter 3000ms), `runtime_core` carries the decision (`last_summary_sn`, `ops_since_summary`, `wants_summary`, `summary_jitter_ms`), and both runtimes arm a wake-up from their sequenced-op path and re-take the decision on arrival. Off unless `auto_summarize` installs a policy. Two departures from the plan as written, both recorded below: the trigger is not *only* threshold + jitter, and the knob is not a connect option.
- **SB4 — ✅ done, with one leg failing on the server it was run against.** The policy is on in the live suites (`auto_summary_writes_without_an_explicit_call_test`, `a_peers_summary_resets_the_local_threshold_test`, a fourth `live_js` scenario) and in the drum machine, app and smoke. Verified live: a document summarizes itself with nothing calling `summarize`, on both targets. **Not** verified: a fresh client joining that document applies the post-checkpoint delta — see "The joiner leg" below, which is a pre-existing failure, not this work's.
- **SB5 — ⛔ rescoped: not a broken test, an unimplemented feature.** See "What SB5 turned out to be" below.
- **SB6 — enable by default. Unblocked:** levee#85 is closed by floodgate `0b24bbd`, which sequences durable leaves for unmatched joins before the first post-restart connection. The client half is pinned by `ghost_members_do_not_survive_a_server_restart_test` (`WATERSHED_INTEGRATION_RESTART=1`, `just integration-restart`), verified to fail against floodgate at `63a1996` with the three pre-restart ids still in the reconstructed `TaskManager` queue. What remains in SB6 is the default flip itself, which depends on SB3.
- **SB7 — ✅ done.** `adopt_reconnect` now keeps `members` at `last_seen_sn` and defers the handshake roster to `live_members`, which `settle_bootstrap` already adopts when the gap closes. The gap's own `join`/`leave` messages — including the leave for the dropped id and the join for the new one — walk the roster to the post-reconnect room. Gate met in `roster_test`.
- **SB8 — docs.** Update `website/src/pages/runtime/reconnect.astro` from "an application can explicitly call" to whatever SB3 makes true, and say what the checkpoint boundary guarantees.

**Remaining: SB6's default flip, SB8.** SB5 stays unimplemented (server-side). Before SB6, settle "The joiner leg" below against floodgate — turning summaries on by default while a post-checkpoint delta can be dropped would make that defect everyone's.

## What SB3 changed about its own design

**A peer's summary is visible, and that is what makes the jitter window work.**
The plan budgeted for redundant uploads because it assumed each client would
find out about a summary only at its next handshake. It does better than that:
floodgate broadcasts the sequenced summarize op, and `apply_one` now records its
sequence number. So the window is not just a stagger — it is a *cancel*. The
first client to summarize advances everyone else's `last_summary_sn`, and their
wake-ups find nothing to do. Confirmed live by
`a_peers_summary_resets_the_local_threshold_test`, which is the test that would
have told us we were in the other world.

This is why the arm/fire split matters: the decision is re-taken on wake against
the core as it is *then*, never carried in the timer.

**The jitter has to be scrambled, not modular.** `id % window` was the obvious
formula and it is nearly useless: a server hands out client ids in sequence, so
a whole room lands within a few milliseconds of itself and every client
summarizes anyway. `summary_jitter_ms` multiplies by a large odd constant first;
`consecutive_client_ids_spread_across_the_window_test` pins the property.

**The knob is a post-connect call, not a connect option.** There was nowhere to
put it: the BEAM `connect` takes six required labelled arguments, and JS
`WatershedConfig` is a public non-opaque record built positionally at every call
site including raw JS (`examples/text_lustre/element_host.mjs`). A sixth field
would be a source break everywhere. `auto_summarize(document, policy)` follows
`presence_js.start` instead, and `summary_policy.Policy` copies
`presence.Config`'s opaque-record + `with_*` + accessor shape. SB6's default flip
becomes a one-line change to the runtime's initial `auto_summary`.

**The BEAM upload still blocks the actor**, deliberately (the plan's decision,
confirmed on execution). One bounded stall per summary, no new concurrency, and
the same path manual `summarize` has always taken.

## The joiner leg: a post-checkpoint delta is lost on bootstrap

Found while running SB4's gate, and **not caused by it** — `git stash` and the
same suite reproduces it.

A client that bootstraps from a summary lands on the summary's state and misses
the ops sequenced after it. In `auto_summary_writes_without_an_explicit_call_test`
the joiner has 12 of the author's 13 keys, and the missing one is exactly the
post-checkpoint write. Its drift matches the author's, so it is not replaying
from zero — it seeded from the blob, then advanced `last_seen` past the delta
without applying it.

Two pre-existing tests fail the same way and for the same reason:
`summary_bootstrap_test` (whose `get(map_b, "post")` assertion is this defect,
stated) and `summary_nested_bootstrap_test`. `summary_versions_test` fails
separately with the 404 SB5 already documents.

**Caveat on the environment, which may be the whole explanation.** These runs
went against `ghcr.io/tylerbutler/levee:latest` on port 4000, not the floodgate
build `just integration-up` produces — the port was already occupied. Floodgate
and levee differ in exactly the area implicated (what `put_summary` records and
where `initial_messages` starts). Re-run against floodgate before treating this
as a client bug: if it reproduces there, it is the server half of the SB1 family
and belongs in its own plan; if it does not, the note to keep is that the summary
suite is silently server-specific.

## How SB1 was actually settled

The plan called for proving the race in `sluice`. That is not possible as written, and the reason is worth recording: **the sluice deliberately serves no summaries** (`sluice/frames.gleam:215`, `sluice/core.gleam:50`), and `git_storage` is a direct module dependency of both runtimes with no seam to stub. Building a deterministic harness would have meant introducing a storage abstraction first — its own project, and a much larger change than the fix.

The hazard is real, and wider on the JS target than this plan first assumed. On Erlang the actor blocks for the whole upload, so only server-side sequencing contributes. On JS `finish_summarize` deliberately re-reads the cell after the async upload (to keep the client sequence number monotonic), so the core can advance client-side too, before floodgate stamps anything.

Rather than reproduce it, the fix removes the possibility: the blob is self-describing, so the load point comes from the blob. The decision was extracted into a pure function precisely so it could be tested without a server.

## What SB5 turned out to be

`summary_versions_test` does not fail because of the checkpoint boundary. It fails because **`GET /versions/:tenant/:document` does not exist on any server** — it 404s on floodgate, while `/repos/:tenant/commits` and `/deltas/...` 401 (present, auth required). That is why it failed against levee too.

There is no small fix, because there is nothing to list:

- Floodgate stores exactly **one** summary pointer per document (`doc_state.Doc.summary: #(String, Int)`, a single overwritten key). No history is retained.
- The endpoint that *does* exist, `GET /repos/:tenant/commits?sha=&count=`, walks a git commit chain. Watershed's `upload_summary` posts a blob and a tree and never a commit, and `outbound_summarize_op` always sends `parents: []`. So there is no chain to walk.

Closing this means choosing a direction and implementing it end to end — either watershed starts writing real git commits so version history falls out of the commit chain (changing what `handle` means, and touching `fetch_summary`), or floodgate grows a versions endpoint over retained pointers (changing what it stores). Both are cross-repo feature work, not a repair, and neither belongs in a correctness pass. `get_versions` / `load_version` should be treated as unimplemented until then.

## Found on the way: reconnect after a server restart — both fixed

Neither symptom was caused by anything in this plan — both reproduced with the SB7 change reverted. The repro is a floodgate restart under clients holding a `PactMap`, with the survivors auto-reconnecting while a fresh client connects. Give the reconnects a few seconds to settle first and neither appears; it is a concurrency window, not a restart consequence. A plain map write over the same restart is clean, so both are specific to the consensus path — which follows, since only the consensus kernels put ops on the wire without the application asking.

**Symptom 1 — fixed.** `AckMismatch("expected ack for csn 3, got csn 2")`. Ops a kernel *released* (a `PactMap` `Accept` owed in response to a peer's `Set`) were sent unconditionally on the sequenced-op path, including while `resubmit_at` was still `Some`. `settle_reconnect` then restamped the whole in-flight queue with fresh client sequence numbers and sent it again, so the server sequenced two copies and the FIFO ack match failed on the stale one. Every other submit path already gated on `resubmit_at`. Both runtimes had it; on JS it was unconditional rather than racy, because `settle_reconnect` runs first there.

**Symptom 2 — fixed.** `AckMismatch("client was not expected to sign off")`. The reconnect gap was applied through the *live* path: gap ops arrive as ordinary `op` frames and go straight to `handle_sequenced`, never through `replay`, so `replaying` was false and `quorum_of` armed the live-only defences that union `self` and the author. A client returning under a fresh id therefore claimed a signoff on a proposal sequenced before that id existed, while no other replica agreed; it sent an `Accept` the room never expected, and any replica still waiting on that pact rejected it — fatally for the connection that sent it.

The defences exist for a hazard that cannot occur here (a `join` lost or reordered against the op after it), and the gap is a complete ordered log exactly like a bootstrap replay. `adopt_reconnect` now sets `replaying`, and `go_live` clears it where the gap closes — one place on this path, mirroring `settle_bootstrap` on the other, so the flag cannot leak past the catch-up.

Two earlier suspicions were wrong and are recorded so they are not re-run: it is not `settle_bootstrap`'s adoption of `live_members` (removing that changes nothing either way), and it is not the SB7 change.

**The prerequisite is built, and both symptoms are closed.** Both sluice drivers now have `reconnect(sluice, document)` — and `drop`/`rejoin`, its two halves, because the interesting window is *between* them: a client is out of the room from its leave until its rejoin, and what gets sequenced in that gap is precisely what it then has to replay under an identity that did not exist at the time. An atomic reconnect cannot express that, and symptom 2 was not reproducible without it.

Both are pinned deterministically, in-memory, on both targets:

- `a_released_accept_is_not_sent_twice_across_a_reconnect_test` (erlang) — symptom 1.
- `a_proposal_made_while_away_does_not_gain_the_returning_client_test` (both) — symptom 2.

Each fails with its fix reverted. The live floodgate restart race, which previously killed two or three runtimes on every run, now completes clean across repeated trials with the post-restart proposal settling correctly.

One detail worth keeping: a pact that has already *settled* ignores a stray `Accept`, so symptom 2 is only observable while a proposal is still outstanding. Both tests hold one client back with `pause` for that reason — without it the scenario passes while still being wrong.

Two things the primitive exposed on the way in, both worth knowing:

- **The sluice was not serving a joiner its own join as an op.** It only appeared in `initial_messages`, but floodgate also pushes it separately (which is why `runtime_core` has a test for deduping that push). A reconnecting runtime ignores `initial_messages`, so without that push it never reached the handshake checkpoint, never left its post-reconnect holding state, and silently kept every later edit in its in-flight queue. Fixed in `sluice/core`.
- **The JS double-send is not observable through the driver.** The same defect and the same fix are present in `runtime_js`, but no scripting of that window has made a duplicate visible — partly because the JS runtime reports core errors by failing the connection rather than crashing, so a dead client still reads correct state. The erlang test is the regression guard for the family.

`ghost_members_do_not_survive_a_server_restart_test` sidesteps both by tearing the pre-restart clients down instead of letting them re-establish — which is also the sharper test, since their joins then stay unmatched and only the server's repair can close them.

## Testing strategy

- **Determinism over a live server.** ~~`sluice` delivers explicitly, so a summarize/bootstrap race is scriptable.~~ The sluice serves no summaries and there is no seam to stub `git_storage`, so summary-path determinism lives at the `runtime_core` level instead — which is where it belongs, since that is the layer the decisions are in. The live suite covers the storage round trip.
- **The assertion that matters** is not "a summary was written" but "a client bootstrapping from a summary reaches the same state as one replaying from zero." Write it as an equivalence: run both, compare `entries` across every channel plus each consensus kernel's pending state.
- **Membership specifically**, since it is the piece with no coverage today: bootstrap from a checkpoint, replay a proposal sequenced after it, and assert the signoff list names the same clients a present client froze.
- **A ghost-member test** — done, and it asserts on the `TaskManager` queue rather than a fresh `PactMap` proposal. That distinction was not obvious: a proposal made after bootstrap freezes its signoff list from the *live* roster, which `settle_bootstrap` has already replaced with the handshake's, so ghosts never reach it and such a test passes either way. The queue is rebuilt purely by replaying the log, so an unmatched volunteer stays in it. Confirmed discriminating against floodgate at `63a1996`.
- **No test asserts a summary is small or fast.** Those are the motivation, not the contract, and a size assertion would break on every kernel change.

## Risks

- **SB1 may be a real bug in shipped behaviour.** If the checkpoint boundary is wrong, every summary ever written is subtly wrong, and the fix may be a wire change. That is why it is first and why nothing else should start until it is settled.
- **Turning summaries on changes what "the log" means.** Today a document's full history is always replayable; after this, joining clients see only the tail. Anything that quietly depended on full replay — and the consensus kernels did, until `0d94d7a` — will surface here. Expect at least one more bug of that family.
- **The threshold is a tuning knob with a bad failure mode in one direction.** Too high and the goal is not met; too low and every document churns blobs. Start conservative and measure before tightening.
- ~~**`summary:write` scope.**~~ Checked: both facades already mint it by default (`watershed.gleam:289`, `watershed_js.gleam:276`, `transport_ffi.mjs:120`), so an automatic policy needs no new scope.

## What this does not do

No garbage collection of old summaries or ops. Once bootstrap stops needing the full history, the history becomes deletable — and that is a genuinely separate project with its own failure modes (a client resuming from a sequence number that no longer exists). Worth a plan of its own, and not worth entangling with this one.

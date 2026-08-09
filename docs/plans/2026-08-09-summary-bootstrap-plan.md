# Summary bootstrap plan — making join cost proportional to recent history, not to all of it

**Date:** 2026-08-09
**Builds on:** `2026-08-09-consensus-replay-quorum-plan.md` (the replay-membership fix this depends on, and whose two open pieces are folded in here), `tylerbutler/levee#85` (the floodgate half).
**Benchmark:** Fluid Framework's summarizer. Fluid elects a dedicated summarizer client and has the server prompt it; the design question below is how much of that we want.

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
| **Anything that calls `summarize`** | ❌ **nothing, anywhere** |
| Checkpoint roster in the blob | ❌ `Summary.members` plumbed, both runtimes pass `[]` |
| Durable log with matched join/leave | ❌ floodgate — levee#85 |

`summarize` has no caller in `src/`, `examples/`, `website/`, or any test outside the env-gated `summary_versions_test`. Floodgate never asks for one either: there is no summarizer election and no nack prompting a client to summarize — it accepts summarize ops and stores what it is given.

So today every document replays from sequence number zero. Floodgate caps `initialMessages` at 1000 ops (`doc_state.max_history_size`) and watershed pages the rest through `fetch_deltas`, which works and is exactly the unbounded growth the goal exists to stop.

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

If that is right it is silent state loss, it predates everything in this plan, and it applies to the roster identically — a roster captured at `X` presented as the roster at `X + k` is stale by whatever joined or left in the window. The area is under-exercised: `summary_versions_test` is the only live coverage and it currently fails against both servers (known, not a regression).

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

- **SB1 — confirm or refute the load-point hazard.** A test that summarizes while a peer op is in flight, then bootstraps a fresh client and asserts it sees the peer's op. Use `sluice` for determinism. Gate: either the hazard is disproved and this rung closes with a comment explaining why, or it is fixed by one of the three options above. **Do not build on top of an unverified checkpoint boundary.**
- **SB2 — blob v4 with `members`.** Bump the version, write `core.members` on summarize, seed from it on load, drop the `[]` placeholders in both runtimes. Gate: a client that bootstraps from a summary and then replays a `PactMap` proposal sequenced after the checkpoint reconstructs the same signoff list as a client that was present — the assertion the replay plan could not make.
- **SB3 — the summarization policy.** Threshold + jitter per decision (a), off by default behind explicit configuration. Gate: two clients on a busy document produce at most a small constant number of redundant summaries, and a document past the threshold reliably acquires one.
- **SB4 — exercise it.** Turn the policy on in the integration suite and in one example (the drum machine is the natural choice — it has three-client tests and a `PactMap`). Gate: a document summarized mid-session is joinable by a fresh client that never sees the pre-checkpoint ops.
- **SB5 — fix `summary_versions_test`.** It is the only live coverage of this path and it currently fails against both servers. Whatever SB1 turns up probably explains it. Gate: green under `just integration`.
- **SB6 — enable by default. Blocked on levee#85.** A log containing a `join` with no matching `leave` gives every replaying client a ghost member, which wedges `PactMap` quorums and `TaskManager` queues permanently. SB2's roster does not help — the ghost is *in* the reconstructed roster, correctly, because the log says so. Gate: the three-client restart scenario from levee#85 converges.
- **SB7 — close the reconnect gap.** `adopt_reconnect` still replaces the roster immediately, so gap ops replay against the post-reconnect room. It needs the roster at `last_seen_sn`, which after SB2 a client already holds. Gate: an op sequenced during a disconnect is judged against the room as it was then.
- **SB8 — docs.** Update `website/src/pages/runtime/reconnect.astro` from "an application can explicitly call" to whatever SB3 makes true, and say what the checkpoint boundary guarantees.

SB1–SB5 and SB7 are unblocked today. Only SB6 waits on levee.

## Testing strategy

- **Determinism over a live server.** `sluice` delivers explicitly, so a summarize/bootstrap race is scriptable rather than timing-dependent. The live integration suite is for the storage round trip, which the sluice does not model.
- **The assertion that matters** is not "a summary was written" but "a client bootstrapping from a summary reaches the same state as one replaying from zero." Write it as an equivalence: run both, compare `entries` across every channel plus each consensus kernel's pending state.
- **Membership specifically**, since it is the piece with no coverage today: bootstrap from a checkpoint, replay a proposal sequenced after it, and assert the signoff list names the same clients a present client froze.
- **A ghost-member test**, red until levee#85 lands, pinned the way the replay bug was: sequence a `join` with no `leave`, then assert what a joiner reconstructs. It should be the thing that goes green when the server is fixed.
- **No test asserts a summary is small or fast.** Those are the motivation, not the contract, and a size assertion would break on every kernel change.

## Risks

- **SB1 may be a real bug in shipped behaviour.** If the checkpoint boundary is wrong, every summary ever written is subtly wrong, and the fix may be a wire change. That is why it is first and why nothing else should start until it is settled.
- **Turning summaries on changes what "the log" means.** Today a document's full history is always replayable; after this, joining clients see only the tail. Anything that quietly depended on full replay — and the consensus kernels did, until `0d94d7a` — will surface here. Expect at least one more bug of that family.
- **The threshold is a tuning knob with a bad failure mode in one direction.** Too high and the goal is not met; too low and every document churns blobs. Start conservative and measure before tightening.
- **`summary:write` scope.** `summarize` requires it; a policy that runs automatically means ordinary clients now need a scope they may not have been issued. Check the token minting path before SB3 rather than discovering it in SB4.

## What this does not do

No garbage collection of old summaries or ops. Once bootstrap stops needing the full history, the history becomes deletable — and that is a genuinely separate project with its own failure modes (a client resuming from a sequence number that no longer exists). Worth a plan of its own, and not worth entangling with this one.

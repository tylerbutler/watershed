# watershed release checklist — a captain, a checklist, a target

A small "go/no-go" release room as a [Lustre](https://lustre.build)
single-page app. Open two or three tabs, tick off the fixed release gates from
whichever tab is convenient, have one tab claim the captain seat, and once
every gate is checked let the captain publish a release target that the whole
room signs off on before it becomes real.

Three channels, three different consistency rules, deliberately side by side:

## What it demonstrates

| Concern | Structure | Encoding |
| --- | --- | --- |
| Completed release gates | `OrSet` | gate id, e.g. `"tests_passing"` — add-wins |
| The release captain seat | `Claims` | `"captain"` → the claiming client's user id, first-writer-wins + CAS take-over |
| The release target | `PactMap` | `"target"` → JSON string, accepted only by quorum |
| The fixed gate list itself | *not shared* | app-local constants (`gates` in `release_checklist_lustre.gleam`) — only completed ids go on the wire |

### Why the checklist is an OR-set

Add-wins is the correct rule here, for exactly the reason it is in the drum
machine's step grid:

- Two people ticking the same gate concurrently is **not a conflict** — they
  agree, and the gate reads complete.
- Reopening a gate and re-completing it has to work, so a remove-wins
  `TwoPSet` is the wrong structure — it would tombstone the gate on the first
  reopen and refuse to let anyone complete it again.
- A concurrent completion beats a concurrent reopen. If one person reopens a
  gate while someone else, who hasn't seen the reopen yet, ticks it again, the
  gate ends up complete — the same "the thing people can see happened wins"
  rule the drum machine's steps rely on.

The fixed list of gates — their ids and the labels shown next to them — never
touches the document. Only the ids of the gates someone has completed do. A
real release checklist's *questions* change slowly and by code review, not by
runtime negotiation; what changes at runtime is who has answered them.

### Why the captain seat is a Claims channel — and why it isn't an ACL

`Claims` gives the room first-writer-wins election on `"captain"`, plus
compare-and-set take-over: whoever holds the seat can be replaced, but only by
a client that observed the currently committed holder, so two concurrent
take-over attempts still resolve to exactly one winner. `captain_test.gleam`
exercises the first-claim race with three contending clients and the
take-over race with two — a third, already-committed holder they are both
racing to replace — and asserts every replica converges on the same winner
either way. Both winner/loser identities feed straight into
`release_readiness.can_propose`, not just `is_captain`, since that is the
function the release-form UI actually gates on.

**Say this out loud, because the UI has to say it too: this is collaborative
coordination, not an authorization boundary.** Nothing in watershed stops any
client from calling `pact_map_set` on the release target directly, captain or
not — the "only the captain publishes" rule is enforced the same way every
other rule in this app is, by the UI declining to offer the control to anyone
else. A production release process that actually needs to *enforce* who may
ship would check that server-side; this demo is about who the room has agreed
should hold the pen, not about stopping someone who ignores that agreement.

Claims reads are **not optimistic** — `get_claim` only ever returns committed
state, never a local guess — so the app tracks its own
`captain_claim_pending` flag and shows "Claiming captain…" for the one round
trip between calling `claim_once`/`compare_and_set_claim` and learning the
outcome.

### Why the release target is a PactMap

Publishing a release target is state where uncoordinated last-write-wins is
genuinely bad, for the same reason the drum machine's tempo is: this mirrors
that example's `PactMap` pattern directly, `"target"` in place of `"bpm"`. A
proposal freezes a signoff list from the connected roster the instant it is
sequenced, and the value does not become live until every client on that list
has acknowledged it — or has left the room.

**Signing off is not approving, and the UI never implies otherwise.** The
kernel emits `OweAccept` and the runtime auto-submits it; nobody chooses to
agree, and there is no control to refuse. The pending line reads *"waiting on
1 of 3 clients"*, never *"1 of 3 approved"*.

Only the committed captain sees the release-target form at all, and only once
`release_readiness.can_propose` says every fixed gate is complete, the draft
text is non-blank, and no proposal is already pending or mid-submit. If a gate
is reopened *after* a target has been accepted, the accepted target stays
exactly as it was — reopening does not retract a shipped release — but the
room is not ready to publish a *different* one until every gate is complete
again.

Two behaviours worth staging with three tabs open, exactly as with the drum
machine's tempo:

- **The stall.** Publish a target, then background one tab before it
  acknowledges. The proposal visibly stops, naming the client it is waiting
  on. Bring the tab back and the target lands.
- **The drain.** Do the same, then *close* that tab instead. The signoff list
  drains as the leave is sequenced and the target lands anyway. A pending
  pact is not a deadlock.

A tab that joins after the room already agreed a target reads that target
directly, with no phantom pending proposal — a pact's signoff list is rebuilt
from the roster its proposal was sequenced against, not the joiner's
present-day roster. `a_late_joiner_reads_the_accepted_target_without_a_false_pending_test`
is the guard.

## Tests

```sh
gleam test            # convergence + captain + quorum, no server and no browser
pnpm run smoke         # the same claims against a live floodgate server
```

- `test/readiness_test.gleam` — the pure captain/readiness rules
  (`release_readiness.gleam`) in isolation: who counts as captain, when every
  gate is complete, and when a proposal is allowed. No channel, no Lustre
  effect, no sluice.
- `test/convergence_test.gleam` — two clients over the in-memory `sluice`:
  checklist convergence, a concurrent completion surviving a reopen, and a
  gate toggling off and back on.
- `test/captain_test.gleam` — first-writer-wins claiming, a rejected
  second claim, concurrent claims from three contenders converging on one
  winner, compare-and-set take-over, and a two-way take-over race against an
  already-committed holder — each cross-checked against
  `release_readiness.is_captain` and, for the two convergence races,
  `can_propose` as well.
- `test/quorum_test.gleam` — **three** clients, for the same reason the drum
  machine's does: a two-client room cannot distinguish a correct signoff
  roster from a hardcoded `[self, author]` guess. Covers the stall, the drain
  on a silent disconnect, a colliding second proposal, a late joiner reading
  the accepted target without a false pending quorum, and a reopened gate
  leaving an already-accepted target untouched.

`dev/release_checklist_lustre/smoke.gleam` drives three real `watershed` clients
against a live floodgate server end to end: bootstraps all three channels on
each client,
completes the checklist across two of them, has one claim the captain seat,
publishes a release target, and asserts every client converges on the same
accepted target. The deterministic pause/resume/disconnect timing that
actually exercises the quorum edge cases lives in `test/quorum_test.gleam`
against the sluice — the smoke test only has wall-clock delays to work with,
so it exercises the happy path a live server actually round-trips through.

## Run it

Start a floodgate dev server from the repository root:

```sh
just integration-up   # seeds tenant "dev-tenant", listens on :4000
```

Then, in this directory:

```sh
pnpm install          # phoenix + esbuild
pnpm run build        # gleam build --target javascript, then esbuild bundle
pnpm run serve        # serves index.html on http://localhost:8080
```

Open two or three browser tabs on <http://localhost:8080> — all against the
same document, either by leaving the URL as-is or by sharing a
`?document=...` query string across tabs. Tick a few gates from different
tabs, claim the captain seat from one, finish the checklist, and publish a
release target once the form appears. Try backgrounding the captain's tab (or
a peer's) mid-proposal to see the pending line stall, then bring it back.

> The demo mints an HS256 dev JWT in the browser using the server's dev secret.
> This is for local dev only; a real deployment issues tokens from a backend
> and never ships the tenant secret to the client.

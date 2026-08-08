# Drum machine demo plan — audible convergence, and a quorum worth waiting for

**Date:** 2026-08-08
**Builds on:** `docs/plans/2026-08-08-facade-parity-sweep-plan.md` (**FP1, FP3, FP4 — hard blockers, see below**), `2026-07-06-lustre-integration-plan.md`.
**Benchmark:** the Roland TR-808 grid, and every browser step sequencer since. The interaction is universally understood, which lets the demo spend all of its explanation budget on the collaborative behaviour.

## Blocked — do not start before the parity plan lands

This demo's `PactMap` half is currently **unbuildable honestly**:

- **FP1 — `PactMap` quorum is a placeholder.** `runtime_core.gleam:815–818` fabricates the signoff list as `[self, author]`; there is no membership roster, and the handshake's `initial_clients` is decoded and never read. With three clients connected, the third is never in the signoff list. A "the room must agree" demo built on this would be **showing the audience something that is not happening** — the worst possible outcome for a project whose pitch is "show, don't claim".
- **FP3 — no `subscribe_pact_map`** on either facade. `WentPending` → `WentAccepted` is the entire protocol and it is currently unobservable.
- **FP4 — `Pending.expected_signoffs` is not reachable**, so a UI cannot say who it is waiting for.

The `OrSet` half (steps, the audible part) is buildable today and does not depend on any of that. The rungs are ordered so DM1–DM5 ship a complete, honest demo with a plain local tempo control, and the `PactMap` tempo lands later as DM6–DM7 once FP1/FP3/FP4 are in. **Do not invert that order to get the quorum story sooner.**

## Decisions already made (flagged — confirm before DM1)

1. **Steps are `OrSet`s of step indices, one channel per track.** Four tracks (kick, snare, hat, clap), 16 steps. `or_set_add("7")` / `or_set_remove("7")`. Add-wins is right: two people enabling the same step concurrently is not a conflict, and toggling off then on again must work — which is exactly what `TwoPSet` would break (see the grocery triptych). Four channels rather than one `OrMap` keyed `"track:step"` because per-track subscriptions map cleanly onto per-track UI rows and per-track mute.
2. **Tempo is a `PactMap` key, and quorum is the *point*, not decoration.** Tempo is the one piece of state where uncoordinated LWW is genuinely bad: two people dragging a BPM slider in opposite directions produces a room that lurches. Requiring the room to sign off before the tempo changes is the correct engineering choice *and* the only honest `PactMap` demo on the roadmap. Everything else in the app is deliberately uncoordinated so the contrast lands.
3. **Acceptance is automatic, not a user vote — and the UI must not imply otherwise.** `pact_map_kernel` emits `OweAccept` and `channel.gleam:726` turns it into an auto-submitted op. No client ever *chooses* to agree; signoff means "this client has seen and acknowledged the proposal". The UI therefore reads **"waiting on 1 of 3 clients"**, never "2 of 3 voted yes". An agree/reject button would be a lie about the protocol. This is the single easiest mistake to make when building this screen.
4. **Clients are not phase-locked, and the README says so.** See "The honesty problem" below. This is the biggest design risk in the demo and it is a presentation problem, not a watershed problem.
5. **Synthesised sounds, no audio assets.** Kick, snare, hat, and clap from oscillators and filtered noise — a few dozen lines of Web Audio. Keeps the example self-contained, keeps the repo free of binaries, and removes an asset-loading failure mode that would look like a sync bug.

## Why this demo

Every other demo in `examples/` renders convergence. This one **plays** it. A reader who hears four browsers land on the same pattern has a different kind of conviction than one who reads matching numbers, and it is the only demo that can be understood from across a room — which matters for the conference-talk context `PRODUCT.md` names as an entry point.

It is also the only place `PactMap` makes sense. The kind has sat unused because most collaborative state wants speed over agreement; tempo is the rare inversion, and building the demo forces FP1's correctness bug into the open where it belongs.

## The honesty problem — phase alignment

**watershed converges state, not time.** Two browsers holding the same pattern and the same BPM will still run their loops out of phase, because they started their audio clocks at different moments. Nothing in the toolkit fixes this, and no amount of CRDT correctness will.

Three options, and the choice shapes the demo:

- **(a) Per-client phase, stated plainly.** Each client loops independently. Everyone hears the same *pattern* at the same *tempo*, not the same *beat* at the same *instant*. Zero extra machinery, zero risk of over-claiming. In one room over speakers this sounds like four sequencers playing together slightly out of phase — musically fine, and arguably a nicer texture.
- **(b) Shared start timestamp + clock estimation.** Store a loop origin in the document; each client estimates its offset against a reference and schedules to the shared grid. This can align to roughly network-jitter accuracy, which is audibly imperfect at 128 BPM (a 30ms skew is clearly hearable on a hat). It is real work, it will be blamed for sync bugs it did not cause, and it is not a watershed feature.
- **(c) One client is the audio source.** The dispatcher pattern — only the tab holding a `TaskManager` role plays sound. Perfectly aligned by construction, but then the room is listening to one browser and the demo stops demonstrating anything about distribution.

**Build (a).** State the limitation in the UI itself — a line under the transport reading "each client runs its own clock; patterns converge, phase does not" — and in the README. Do not attempt (b) unless someone specifically wants a clock-sync demo, which is a different project. (c) is worth one sentence in the README as the technique real products use, since it is genuinely the right answer for production audio.

## Data model

```gleam
pub type Machine

pub const kick:     ChannelField(Machine, schema.OrSetChannel) = ...
pub const snare:    ChannelField(Machine, schema.OrSetChannel) = ...
pub const hat:      ChannelField(Machine, schema.OrSetChannel) = ...
pub const clap:     ChannelField(Machine, schema.OrSetChannel) = ...
pub const settings: ChannelField(Machine, schema.PactMapChannel) = ...
```

Step elements are the index as a decimal string, `"0"`–`"15"`. `settings` holds one key, `"bpm"`, as a JSON number. A second key, `"swing"`, is an easy addition once the pending UI exists and gives the quorum path a second exercise without new concepts — worth it only if DM6 lands cheaply.

Mute and volume are **local, per-client, and not in the document**. They are listener preferences, not shared composition state, and putting them in the document would mean one person muting everyone.

## Audio architecture

A lookahead scheduler, standard Web Audio practice, in a single FFI module:

- A `setInterval` at ~25ms wakes and schedules every step falling within the next ~100ms against `audioContext.currentTime`. Never schedule from the event loop directly; timer jitter at 16th notes is audible.
- The scheduler reads the pattern from a plain JS array that Gleam refreshes whenever a channel event lands. **The scheduler never calls into Gleam** — it reads a mutable snapshot. Crossing the FFI boundary inside the audio callback would couple sync latency to audio timing, which is how a sync demo acquires an audio glitch it gets blamed for.
- Voices are synthesised per hit: kick as a pitch-swept sine, snare and clap as filtered noise bursts with different envelopes, hat as a short high-passed noise burst.
- `AudioContext` starts suspended and resumes on the first user gesture — browsers require this, and a silent demo with no explanation is a failure mode worth an explicit "click to start" overlay.

The Lustre app owns pattern state, the grid, the transport, and the pending-tempo UI; the FFI owns the clock and the voices. The playhead indicator is driven by a `requestAnimationFrame` read of the scheduler's current step, **not** by dispatching a Lustre message per step — 16th notes at 140 BPM is ~9 messages/sec of vdom churn for a moving highlight.

## The tempo screen (DM6–DM7)

```
 Tempo   [ ──────●─────── ] 124 BPM
         ⏳ 132 BPM pending — waiting on 1 of 3 clients
            signed off: you, client-4a2
```

- Dragging the slider proposes on release, not per-frame — a `pact_map_set` per pointer move would flood the quorum protocol with proposals that invalidate each other.
- While pending, the slider shows the proposed value as a ghost and the live value stays authoritative; the sequencer keeps running at the accepted tempo until `WentAccepted`.
- A proposal made while another is pending is rejected by the kernel (`apply_set` treats a pact with `pending: Some(_)` as invalid). Render that as "a tempo change is already in flight", disabled — do not silently drop it.
- The waiting-on list comes from FP4's signoff accessor. If FP4 slips, degrade to "waiting for the room to acknowledge" with no count rather than inventing one.

**The scenario worth staging:** three tabs, propose a tempo change, and *background one tab before it acknowledges*. The pending state visibly stalls. Close that tab; the leave path drains the signoff list and the tempo lands. That is `PactMap`'s real behaviour, it is genuinely interesting, and it is only true once FP1 ships.

## Rungs

- **DM1 — scaffold + connect.** `examples/drum_machine_lustre/` on the `playlist_lustre` template; `justfile` stanzas; four `ensure_or_set` + `subscribe_or_set`. Gate: two tabs render an empty 4×16 grid.
- **DM2 — the grid.** Toggle steps, optimistic + remote paths, per-track rows. No audio. Gate: toggling in one tab updates the other.
- **DM3 — audio.** Scheduler FFI, four synthesised voices, start/stop transport, click-to-start overlay. Gate: a pattern plays and is stable over several minutes with no drift within a single client.
- **DM4 — playhead + local tempo.** `requestAnimationFrame` playhead, local-only BPM control, local mute/volume. Gate: two tabs at the same manually-set BPM play the same pattern; the phase-difference caveat is visible in the UI.
- **DM5 — README + smoke test.** Ships a complete, honest demo. **Stop here if the parity plan has not landed.**
- **DM6 — quorum tempo.** Requires FP1 + FP3. Replace the local BPM control with the `PactMap` proposal flow and the pending UI. Gate: three tabs; a proposal is visibly pending until all three acknowledge, and the pending window is genuinely observable rather than instantaneous — **if it accepts instantly with three clients, FP1 is not actually fixed.**
- **DM7 — signoff detail + the stall scenario.** Requires FP4. The waiting-on list, and the background-a-tab scenario from above. Gate: the stall is reproducible and the leave-drain resolves it.

## Testing strategy

- **Convergence tests** (two in-process `sluice` clients): concurrent toggles of the same step; toggle-off-then-on against a peer's concurrent toggle-on (the add-wins case); all four tracks independently.
- **Quorum test (DM6):** three clients, propose, assert pending at all three, assert accepted only after all three acknowledge. This is FP1c's test from the parity plan, and this demo is its most demanding consumer — a two-client version of this test passes today against broken code, which is precisely why it must be three.
- **Stall/drain test (DM7):** three clients, propose, one disconnects ungracefully, assert the pact drains and accepts.
- **No automated audio testing.** Verify by ear; a scheduler test that asserts step timings against a mocked clock tests the mock. Note in the README that audio correctness is manually verified.
- **Smoke test** on the `sudoku_lustre` pattern — connect, toggle a step, read it back. No audio in the smoke path.

## Risks

- **Audio bugs will be read as sync bugs.** A scheduling glitch looks exactly like a convergence failure to anyone who is not reading the code, and this demo's whole purpose is building trust. Mitigation: DM3 gates on stable playback *before* any collaborative audio behaviour is demonstrated, and the README says plainly which parts are Web Audio's problem.
- **DM6 depends on a fix that may itself be blocked.** FP1 may turn out to need floodgate-side join messages, in which case it becomes a server plan and DM6/DM7 wait indefinitely. DM1–DM5 must stand alone as a shipped demo, which is why the local tempo control in DM4 is real work and not a placeholder.

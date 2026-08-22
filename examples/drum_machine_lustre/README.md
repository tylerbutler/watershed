# watershed drum machine — convergence you can hear

A 4×16 step sequencer as a [Lustre](https://lustre.build) single-page app.
Every other example in `examples/` *renders* convergence. This one plays it:
open two tabs, program a beat in one, and the other starts playing it.

It is also the only demo where two kinds of collaboration sit side by side and
the difference is audible. The pattern is uncoordinated — anyone can toggle any
step and it lands immediately. The tempo is not: changing it requires the room
to sign off first.

## What it demonstrates

| Concern | Structure | Encoding |
| --- | --- | --- |
| Enabled steps, one channel per track | `OrSet` ×4 | step index as a decimal string, `"0"`–`"15"` |
| Room tempo | `PactMap` | `"bpm"` → JSON number, accepted only by quorum |
| Mute, volume | *not shared* | local listener preferences, deliberately outside the document |

### Why the steps are OR-sets

Add-wins is the correct rule for a step grid, and the alternatives are visibly
wrong:

- Two people enabling the same step is **not a conflict** — they wanted the
  same thing, and the result is that the step is on.
- Turning a step off and on again has to work. A `TwoPSet` would tombstone the
  step on the first removal and refuse to let anyone enable it again, which in
  a sequencer means a hole in the bar that nobody can fill.
- A concurrent enable beats a concurrent disable. If you can see a step lit and
  you leave it alone while someone else turns it off and a third person turns
  it on, the step is on.

Four channels rather than one map keyed `"track:step"`, because per-track
subscriptions map onto per-track UI rows and per-track mute without filtering.

### Why the tempo is a PactMap

Tempo is the one piece of state here where uncoordinated last-write-wins is
genuinely bad. Two people dragging a BPM slider in opposite directions with LWW
produces a room that lurches between their values. A `PactMap` key is *proposed*
rather than set: the proposal freezes a signoff list from the connected roster,
and the value does not become live until every client on that list has
acknowledged it — or has left the room.

**Signing off is not voting, and the UI never pretends otherwise.** The kernel
emits `OweAccept` and the runtime auto-submits it; no client ever chooses to
agree, and there is no way to refuse. So the pending line reads *"waiting on 1
of 3 clients"* and never *"2 of 3 agreed"*. An agree/reject button would be a
lie about the protocol.

Two behaviours worth staging with three tabs open:

- **The stall.** Propose a tempo change, then background one tab before it
  acknowledges. The proposal visibly stops, naming the client it is waiting on.
  Bring the tab back and the tempo lands.
- **The drain.** Do the same, then *close* that tab instead. The signoff list
  drains as the leave is sequenced and the tempo lands anyway. A pending pact
  is not a deadlock.

While a proposal is in flight the slider is disabled. That is not decoration: a
second proposal made while one is pending is rejected outright by the kernel
(`apply_set` treats a pact with `pending: Some(_)` as invalid), and a live
slider would let a drag disappear with nothing on screen to explain it.

The pending line names the clients it is waiting on, and marks the one that is
**you** — `watershed.client_id` gives the connection's own id, and
`watershed/client_id.to_int` converts it with the same derivation the kernels
use, so the match is exact. The other entries stay opaque numbers, which is
honest: nothing in the document says who a peer is.

A client joining after a tempo has been agreed reads that tempo, not the
default: a pact's signoff list is rebuilt from the roster its proposal was
sequenced against, not the joiner's present-day roster.
`a_late_joiner_reads_the_agreed_tempo_test` is the guard.

## What watershed does not do: phase

**watershed converges state, not time.** Two browsers holding the same pattern
at the same tempo still run their loops out of phase, because their audio
clocks started at different moments. No amount of CRDT correctness fixes this,
and this demo does not pretend to — the app says so under the transport, and
each client simply runs its own clock. Over speakers in one room that sounds
like several sequencers playing together slightly out of phase, which is
musically fine and arguably a nicer texture than a single grid.

The technique real products use is to make one client the audio source — elect
a holder with a `TaskManager` role and let only that tab make sound. It is
perfectly aligned by construction, but then the room is listening to one
browser, and the demo would stop demonstrating anything about distribution.

## Audio

Synthesised, not sampled: kick is a pitch-swept sine, snare and clap are
filtered noise bursts with different envelopes, hat is a short high-passed
burst. No binaries in the repo, and no asset-loading failure mode that would
look like a sync bug.

The scheduler (`src/audio_ffi.mjs`) is a standard Web Audio lookahead: a 25ms
interval schedules every step falling inside the next 100ms against
`audioContext.currentTime`. Two properties matter for a *sync* demo:

- **The scheduler never calls into Gleam.** It reads a plain 4×16 array that
  Gleam overwrites whenever a channel event lands. If it had to ask watershed
  for the pattern, document latency would become audio jitter — and an audio
  glitch in this demo gets blamed on the sync.
- **The playhead is driven from `requestAnimationFrame`, not from Lustre.** At
  140 BPM a 16th-note playhead would be ~9 messages a second, each a full grid
  diff, for a highlight that moves two elements. The app renders
  `<div id="playhead">` empty and the FFI owns the subtree.

Browsers refuse to start an `AudioContext` without a user gesture, so the page
opens silent behind an **Enable audio** button. The grid works before you press
it.

**Audio correctness is verified by ear.** There is no automated audio test: a
test asserting step timings against a mocked clock tests the mock.

## Tests

```sh
gleam test            # convergence + quorum, no server and no browser
pnpm run smoke        # the same claims against a live floodgate server
```

`test/convergence_test.gleam` runs two clients over the in-memory `sluice`,
where delivery is explicit and synchronous, and asserts the pattern claims
above — including the add-wins case and the off-then-on toggle.

`test/quorum_test.gleam` runs **three**. That is not a stylistic choice: a
two-client room cannot distinguish a correct signoff roster from `[self,
author]`, so quorum bugs only show up at three. Don't reduce it to two.

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

Open **three** browser tabs on <http://localhost:8080> and press **Enable
audio** in each. Toggle steps in one and hear them appear in the others. Then
drag the tempo slider and watch the proposal sign off across all three — and
try backgrounding a tab first.

> The demo mints an HS256 dev JWT in the browser using the server's dev secret.
> This is for local dev only; a real deployment issues tokens from a backend and
> never ships the tenant secret to the client.

# watershed clap counter — peer-to-peer collaborative claps

A [Lustre](https://lustre.build) single-page app with **no server behind it**.
The document's root is a `PnCounter`, and `watershed/crdt_js` connects it
directly to the other tabs in the room over WebRTC data channels. Nothing
sequences the claps and nothing acknowledges them: two tabs clapping at the
same instant both land, because the value is a state-based CRDT merge rather
than a serialized last-write-wins.

The app drives the document through the `watershed_lustre/crdt` bindings, which
own the effect scheduling and defer every callback — connect, subscribe, and
the clap mutation are each one binding call. The `CrdtConnection` and
`Subscription` handles the bindings deliver are deliberately discarded: the app
lives exactly as long as its page, so nothing ever closes or unsubscribes.

This is the p2p demo. There is no floodgate server, no tenant, no JWT, and no
dev secret in the browser — the previous version of this example had all four.

## Why `PnCounter` and not something grow-only

Claps only ever go up, so a dedicated grow-only counter (a G-Counter) would be
the more honest primitive. Watershed doesn't have one: the vendored
`lattice_counters` package ships `g_counter.gleam`, but nothing in
`src/watershed/` wires it up — no kernel, no facade type, no `CrdtKind`. This
example uses `PnCounter` and simply never calls its decrement path. See
`docs/demo-ideas.md` for the note tracking the gap.

## Run it

Start the reference signaling service from the repository root. It introduces
peers to each other and carries offers, answers, and ICE candidates — it
cannot route document data, by protocol shape (see
`src/watershed/crdt_signaling.gleam`):

```sh
gleam build --target javascript          # builds the protocol module it runs
node tools/signaling/server.mjs --port 4400
```

Then, in this directory:

```sh
pnpm install          # esbuild (and phoenix, which the shared transport FFI resolves)
pnpm run build        # gleam build --target javascript, then esbuild bundle
pnpm run serve        # serves index.html on http://localhost:8080
```

From the repository root the install/build portion is `just deps` and
`just build`, and the signaling service is `just signaling`.

Open **two** browser tabs on <http://localhost:8080>. The first tab puts a
`?document=` room id in the URL; copy that whole URL into the second tab so
both join the same room. Hold the clap button down in both — the count only
goes up, and both tabs converge on the same total with no server involved.

The second tab shows `syncing` until the first tab's total has arrived, and
only then reports itself ready: a late joiner is never handed an empty
document that is about to jump. The status line says `alone` when the room's
roster came back empty, which is the other way a tab becomes ready.

## Configuration

Everything is a query parameter, because watershed ships no defaults for any
of it:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `document` | generated | The room id. Added to the URL on first load. |
| `signaling` | `ws://localhost:4400/` | The signaling service to join through. |
| `ice` | none | Comma-separated STUN/TURN URLs, e.g. `stun:stun.example:3478`. |
| `iceUser` / `icePass` | none | A TURN credential, applied to the `ice` entry. |
| `relay` | none | An optional `crdt_relay_v1` sequencer relay, e.g. `ws://localhost:4500/`. Without one the app is exactly as it was. |

## What this demo does not ship

- **No STUN or TURN.** Two tabs on one machine, or two machines on one LAN,
  connect on host candidates alone. Anything across a NAT needs ICE servers,
  and they are yours to supply — watershed ships no servers and no credentials.
- **No durable signaling.** The reference service holds rooms in memory.
  Restart it and every room is gone; the tabs already connected keep working,
  because signaling is only used to introduce peers.
- **No room persistence at all, unless you point it at a relay.** The document
  lives in the tabs, and when the last one closes the claps are gone —
  `crdt_js.export_snapshot` exists for exactly this, and this app deliberately
  does not call it. Pass `?relay=` and the room survives instead; see below.
- **Eight peers per room.** The mesh is full: every peer holds a connection to
  every other one, and the ninth peer to join is refused with `roomFull`.
- **No authentication.** The reference service admits anyone who names a room
  and an unused peer id. It is a reference, not a deployment.

## Optional: a durable relay

Everything above works with no server at all. If you want the room to outlive
its tabs, start the reference relay from the repository root and pass its URL:

```sh
just relay                       # node tools/relay/server.mjs --port 4500 --data ./relay-data
```

then open <http://localhost:8080/?relay=ws://localhost:4500/>.

The status line gains a `relay` field. It reads `syncing` while the tab merges
what the relay holds and publishes its own state back, `durable` once the two
digests match, and `offline · peer-to-peer` if the relay goes away — at which
point the tabs keep clapping over WebRTC and merge the outage's claps back when
it returns. Readiness never waits for any of it: the policy is `Auto`, so a
relay that is down costs a status line and no claps.

The contract the relay implements is `docs/crdt-relay-v1.md`.

## Tests

The example has no suite of its own. What covers it is:

```sh
node tools/signaling/test.mjs   # the signaling service, over real sockets
node tools/relay/test.mjs       # the relay service, over real sockets and a real disk
gleam test --target javascript  # crdt_js, the signaling protocol, the relay protocol
just p2p-clap                   # two real browsers, this app's document shape
```

`just p2p-clap` is the gate: two headless browser pages join a room through
the real signaling process, clap concurrently, and must converge on the same
total *and* the same canonical digest — with the late page asserted to have
become ready only after merging the room's state — while the signaling
process is asserted to have received nothing but `join`, `signal`, and
`leave` frames.

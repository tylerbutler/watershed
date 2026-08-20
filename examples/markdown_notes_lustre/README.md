# markdown_notes_lustre

Peer-to-peer markdown notes with disk-first persistence: a note list beside a
plain-markdown editor, where several people can type in the same note at once
and a saved snapshot reopens before networking catches up.

The root document is a **register-mode OR-map**:

| Root key | Value | Why |
| --- | --- | --- |
| `<note name>` | `TextChannel` address | note bodies are plain shared text; the address is stored directly |
| `"\ttags"` | OR-set address | note/tag pairs live in one shared set |
| `"\torder"` | sequence address | sidebar order is one shared sequence |

Note names reject tabs, so the tab-prefixed reserved keys cannot collide with
user content.

## Run it

Start the reference signaling service from the repository root:

```sh
gleam build --target javascript
node tools/signaling/server.mjs --port 4400
```

Then, in this directory:

```sh
pnpm install
pnpm run build
pnpm run serve
```

Open the page in one tab, then reuse the full URL in another tab so both tabs
join the same `?document=` room.

### Optional relay / ICE

This example follows the same query-driven configuration as
`clap_counter_lustre`:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `document` | generated | room id shared between tabs |
| `signaling` | `ws://localhost:4400/` | signaling service |
| `ice` | none | comma-separated STUN/TURN URLs |
| `iceUser` / `icePass` | none | TURN credentials for `ice` |
| `relay` | none | optional sequencer relay (`crdt_relay_v1`) |

Without `?relay=` the app is still fully peer-to-peer; with it, the relay
becomes the durable delta path once digests match.

## Persistence

`watershed_lustre/crdt.open` loads IndexedDB first. If this browser already has
an on-disk snapshot for the room, the notes open immediately and networking is
an enhancement. `persist_controller_js` then watches local edits and saves the
joined document back to IndexedDB.

The app asks the browser for persistent storage on startup
(`navigator.storage.persist()`). A grant exempts this origin's IndexedDB from
eviction under storage pressure; a refusal is not an error — saving still
works, and the storage line says `evictable` rather than claiming a durability
the app does not have.

Signaling failures after the document is open — an unreachable service, a
socket the service closed, a roster that never came — are reported in the
sidebar's system-error list. A signaling service that has gone away is not
something this app lets you not notice.

The UI reports three things separately:

- network / peer / relay state
- whether a local snapshot was opened, and whether it is durable or evictable
- whether local saving is watching, saving, saved, or failed

If opening the local snapshot fails, or if a later save fails, the app stops
accepting new local edits silently. It enters a visible recovery-required
read-only mode: the editor and every mutation control are locked, remote note
and subscription updates still render, and the only way to overwrite the broken
local bytes is an explicit **Replace local snapshot with current document**
button. A successful replace clears the gate, updates the saved digest/status,
and resumes ordinary editing; a failed replace leaves the gate in place.

## Tests

```sh
gleam test            # unit rules + deterministic p2p convergence tests
pnpm run smoke        # real-browser IndexedDB/service-worker/recovery smoke
```

The convergence suite keeps the six race assertions from the sequenced version
and adds a save → drop → load → edit → attach persistence convergence test.
The browser smoke now also corrupts IndexedDB on purpose to prove the
recovery-required gate and the explicit replace flow.

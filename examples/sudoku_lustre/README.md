# watershed Sudoku — Gleam-end-to-end collaborative puzzle

A [Lustre](https://lustre.build) single-page app whose **entire client is
Gleam** compiled to JavaScript: UI, collaborative Sudoku state, optimistic DDS
edits, ephemeral presence, wire codecs, and the reconnect state machine. It
follows the `dice_lustre` browser-SPA structure while combining **several
watershed data structures at once**, plus **ripples** for transient presence.

## What it demonstrates

The board is bootstrapped from handles stored on the document's root
`SharedMap`, so multiple DDS work together in one document:

| Concern | Structure | Encoding |
| --- | --- | --- |
| Cell values (player entries) | `SharedMap` | `r{r}c{c}` → digit, last-write-wins |
| Pencil-mark candidates | `OrSet` | `r{r}c{c}={d}` add/remove notes |
| Puzzle givens (agreed clues) | `Claims` | consensus per cell — every client converges on the same puzzle |
| Shared mistakes tally | `SharedCounter` | `increment` on a wrong entry |

**Ephemeral presence** — who's online, each player's selected cell, and a
"typing" indicator — rides watershed's presence tier, *not* a DDS: it is never
sequenced, persisted, or replayed. Where the server offers connection-backed
presence, it tracks each socket, so a player joining late sees the whole room at
once and a closed tab vanishes immediately. Where it does not, presence falls
back to broadcasting over **ripples** (`"signal"` on the Fluid wire) every 2s and
expiring a peer after ~6.5s of silence. Either way the lifecycle lives in the
library (`watershed/presence` + `watershed/presence_js`); this app keeps only its
`SudokuPresence` metadata type and the rendering. Two tabs opened by the same
player are two sessions under one key, so they appear separately.

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

Open **two** browser tabs on <http://localhost:8080>. Select a cell, type 1–9,
toggle notes mode for pencil marks, and watch both tabs converge — including
each other's live cursor and typing indicator in the roster. Hit **Force
reconnect** and keep solving — pending edits are preserved and presence rejoins
with the new session, carrying whatever you selected while it was down.

> The demo mints an HS256 dev JWT in the browser using the server's dev secret. This
> is for local dev only; a real deployment issues tokens from a backend and
> never ships the tenant secret to the client.

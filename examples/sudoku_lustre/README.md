# watershed Sudoku — Gleam-end-to-end collaborative puzzle

A [Lustre](https://lustre.build) single-page app whose **entire client is
Gleam** compiled to JavaScript: UI, collaborative Sudoku state, optimistic DDS
edits, ephemeral presence, wire codecs, and the reconnect state machine. It
follows the `dice_lustre` browser-SPA structure while combining **several
watershed data structures at once**, plus **signals** for transient presence.

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
"typing" indicator — rides on watershed **signals**, *not* a DDS. Signals are
non-sequenced and non-persisted (fire-and-forget), so presence is never
replayed or stored; a peer that goes silent simply expires via a heartbeat +
TTL. Each client re-announces itself every 2s and is dropped after ~6.5s of
silence. See [`src/presence.gleam`](src/presence.gleam).

## Run it

Start a levee dev server in the `levee` repo:

```sh
just server   # registers tenant "dev-tenant" in dev mode, listens on :4000
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
reconnect** and keep solving — pending edits are preserved and presence
re-establishes on the next heartbeat.

> The demo mints an HS256 dev JWT in the browser using levee's dev secret. This
> is for local dev only; a real deployment issues tokens from a backend and
> never ships the tenant secret to the client.

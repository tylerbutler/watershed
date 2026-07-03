# watershed scoreboard CLI — nested SharedMaps demo

An Erlang-target multi-player dice scoreboard. Where [`dice_cli`](../dice_cli)
edits a single key on the root map, this example exercises **multiple keys and
multiple maps**: the root map holds plain values plus a handle to a shared
*roster* map, and every player owns a nested map with several keys of its own.

## Map topology

```text
root ─┬─ "game"      = "watershed dice scores"
      ├─ "die_sides" = 6
      └─ "players"   = handle ──▶ roster ─┬─ "player-1234" = handle ──▶ player map
                                          └─ "player-5678" = handle ──▶ player map

player map ─┬─ "name"
            ├─ "last_roll"
            ├─ "total"
            └─ "rolls"
```

API surface demonstrated on top of what `dice_cli` covers:

- `watershed.create_map` — detached maps, populated locally before attach
- `watershed.handle_of` — storing a map handle as a value in another map
- `watershed.resolve` — turning a handle read from a peer back into a
  `SharedMap` (with retries, since a remote handle can be transiently
  unresolvable while its attach op is in flight)
- One selector fanning in events from *many* subscriptions: the roster map
  plus every player map, growing as players join

## Prerequisites

Start a levee dev server from the `levee` repo:

```sh
just server   # registers tenant "dev-tenant", listens on :4000
```

## Run it

Open two or more terminals and run in each:

```sh
cd examples/scoreboard_cli
gleam run
```

Each instance:

1. Joins document `dice-scores` as a fresh `player-XXXX` id.
2. Seeds the root map's plain keys (`game`, `die_sides`) on first join.
3. Resolves the roster map from the root's `players` handle — creating and
   attaching it if this is the first join ever.
4. Creates its own player map, populates `name`/`last_roll`/`total`/`rolls`
   **while detached**, then attaches it by storing its handle in the roster.
5. Subscribes to the roster and to every player map (existing and
   newly-joining), folding all events into one selector.
6. Rolls every 5 seconds, updating three keys on its own map, and reprints the
   scoreboard whenever a *remote* roll lands.

Kill an instance with Ctrl+C; its rows persist in the document, so restarting
later joins as a new player alongside the old scores.

## First-join race

If two instances create the very first roster concurrently, both write a
handle to `root["players"]` and last-write-wins picks one. Each client waits
for its write to be sequenced (`is_synced`) and then adopts whichever handle
the key holds, so in practice both converge on the winner. This is a demo-level
strategy — a production app would reserve such keys via a single initializer.

## IPv4 literal

Like `dice_cli`, this uses `host = "127.0.0.1"`, **not** `"localhost"`:
Erlang's default `inet6fb4` resolver stalls ~8 s on the AAAA lookup, long
enough for levee to drop the socket as idle.

## Build check

```sh
gleam build --target erlang   # from this directory
```

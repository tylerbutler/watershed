# tournament_bracket_lustre: register collections settle disputes, not just wins

An 8-player single-elimination bracket, 7 matches, one channel — a
`RegisterCollection` keyed by match id. Anyone connected can report any match.
There is no referee lock, no `Claims`. The interesting behavior comes entirely
from the register collection's atomic CAS, not from app-level permission
checks.

## Why `RegisterCollection`, and not something else

Every other example in this repo has a different arbitration story:
`OrMap`/`GSet` have none (last write or grow-only wins), `PactMap` arbitrates
by quorum (a set of clients must sign off), `OrderedCollection` arbitrates by
FIFO order. `RegisterCollection` is the one kind whose entire reason to exist
is **linearizable CAS per key, with every sequenced write retained as a
version even when it loses**
(`src/watershed/register_collection_kernel.gleam:1-6`). A match result — one
official winner, but every submission worth keeping around — is the one
domain on the demo backlog where that is the honest model rather than a
contrivance.

## Data model

One channel, `matches` (a `RegisterCollectionChannel`), with one register per
match:

| Key | Round | Fixed seeds / feeders |
| --- | --- | --- |
| `r1m1` .. `r1m4` | Quarterfinal | Adjacent seed pairs (1v2, 3v4, 5v6, 7v8) |
| `r2m1`, `r2m2` | Semifinal | Winners of `r1m1`/`r1m2`, `r1m3`/`r1m4` |
| `r3m1` | Final | Winners of `r2m1`/`r2m2` |

Each register's value is one JSON object, `{"winner": ..., "score": ...}`
(`match_result.gleam`) — both fields always change together in a single
`register_write`, so there is no window where a winner is recorded without a
score. Bracket topology and advancement (`bracket.gleam`) are plain data, not
watershed state: the document only ever needs to carry *who won each match*.

## Reads use `Atomic`, not `Lww`

`register_get`/`register_read(..., Atomic)` returns the linearizable CAS
winner — the write whose `reference_sequence_number` matched the register's
current atomic version when it sequenced. `Lww` (last write by sequence
order) would make this indistinguishable from an `OrMap` register in
`RegisterMode`, which is exactly what this demo exists to *not* be.
`register_versions` retrieves every sequenced write, oldest first, including
CAS losers — the "N other report(s) received" detail on a reported match
card.

## Writes are non-optimistic

Unlike every other example here, a submitted result is **not** shown as the
official winner immediately. `register_collection_kernel`'s docstring: "local
writes are not visible until their op sequences." The UI shows a "submitted,
awaiting confirmation…" state for the gap between clicking a winner button and
the `AtomicChanged` event that confirms it — worth noticing, because it is the
opposite of the optimistic-write pattern the other examples establish.

## The payoff scenario

Report the *same* unreported match from two tabs, with two different winners,
before either tab has seen the other's write. Both tabs converge on the same
official winner — whichever write the CAS settles — and the loser's
submission is still visible under "other report(s) received", not silently
discarded. `test/convergence_test.gleam`'s
`concurrent_conflicting_reports_converge_on_one_official_winner_test` is this
scenario as an assertion; try it by hand in two browser tabs to see it live.

## Run it

From the repository root:

```sh
just integration-up   # floodgate dev server on :4000
```

From this directory:

```sh
pnpm install
pnpm run build
pnpm run serve        # http://localhost:8080
```

Loading the page without `?document=` creates a new room and adds the query
parameter. Reuse that full URL in another tab or browser to join the same
room. Change or remove `?document=` for a fresh bracket.

## Checks

```sh
gleam test --target javascript   # in-process convergence + pure advancement tests
pnpm run smoke                   # live floodgate smoke: a reported match converges
```

# Typed-layer DX plan — from decode boundary to declared documents

**Date:** 2026-07-06
**Builds on:** commit `fb46d8a` (`feat(schema): add typed SharedMap layer with whole-map schemas`), `2026-07-01-gleam-sharedmap-client-plan.md` (facade shape), `2026-07-02-m7-handle-support-plan.md` (handle/resolve machinery the child fields ride on).
**Benchmark:** Fluid Framework 2.x — not legacy `SharedMap.get<T>()` (an unchecked cast; watershed's decode boundary is already sounder), but **SharedTree `SchemaFactory` + `ContainerSchema.initialObjects` + `Tree.on`**: declare schema once, get static types, guaranteed root objects, and per-node invalidation.

**Decisions already made (flagged — confirm before TX1):**

1. **Optional record props: `None` writes a delete, not a skip.** The whole-record round-trip law `read(write(r)) == Ok(r)` only holds if absent optionals remove the key; skipping leaves a stale value that reads back as `Some`. Consequence: `Schema`'s encode side generalizes from `List(#(String, Json))` to `List(WriteOp)` (`Put(key, Json)` | `Delete(key)`).
2. **`map_kernel.ValueChanged` gains the new value**: `ValueChanged(key, previous_value: Option(Json), value: Option(Json), local: Bool)` (`value: None` = deleted). Kernel-level breaking change, allowed under the no-external-consumers policy; every event consumer today discards the payload and re-reads, so migration is mechanical.
3. **Erlang runtime fan-out generalizes from `List(Subject(ChannelEvent))` to `List(fn(ChannelEvent) -> Nil)`.** This is what lets facades hand out *narrowed* subjects (`Subject(CounterEvent)`, `Subject(FieldChange(a))`): the facade creates the subject in the caller's process and registers a closure that pattern-matches, decodes, and forwards. The JS facade is already callback-based, so both targets converge on one subscription shape.
4. **`ensure_*` race semantics: everyone seeds, the sequenced winner is adopted.** Concurrent first joiners each create-and-attach a candidate channel; after sync each re-reads the root key and adopts whichever handle the sequencer ordered first (LWW on the root key — last writer's handle wins; all clients converge on the same one). Losing channels stay attached but unreferenced — orphan GC is out of scope, same as today's hand-rolled seeding in `sudoku_lustre`.
5. **Record builders go to arity 9** (`record1`..`record9`), the stdlib `decode.decodeN` precedent. Wider records nest a child map or fall back to the raw `schema(decoder, to_entries)` constructor, which stays.

## Why this rung

The typed layer landed in `fb46d8a` but the flagship JS example doesn't use it, and the one example that does exposes the gaps. Verified pain, file by file:

- **`examples/sudoku_lustre/src/sudoku_lustre.gleam`** spends ~130 lines on bootstrap (`bootstrap_document`, `seed_document`, `wait_synced`, `resolve_shared_with_retry`, `require_value`, plus `resolve_retry_ms`/`resolve_attempts` constants and six raw key constants). Every watershed app re-writes this; Fluid apps write `initialObjects: {...}` once.
- **The root map holds handles to a counter, an OR-set, and a claims channel — none expressible in the typed layer.** `ChildField` only supports nested `TypedMap`s, so the sudoku root *cannot* be schema'd today. This is the blocker that kept the example untyped.
- **`examples/scoreboard_cli/src/scoreboard_cli.gleam:84-133`** hand-writes `player_decoder()` and `player_entries` as a pair the compiler cannot keep in sync — drop a field from `player_entries` and writes silently lose it — and repeats the field list a third time in `sealed(["name", "last_roll", "total", "rolls"])`.
- **Events are untyped and coarse.** Every subscriber receives the 14-variant `channel.ChannelEvent` union — a `SharedCounter` subscriber must pattern-match 13 impossible arms — and `scoreboard_cli` must drop to `subscribe(untyped(map))` from inside the typed API. Sudoku's response is `SharedChanged -> snapshot(model)`: discard the event, re-read *all five* channels.
- **`versioned` fails closed.** `SchemaMismatch` is a dead end; there is no upgrade path (Fluid: `canView`/`upgradeSchema`).

The rungs below fix these in dependency order: drift-proof codecs (TX1) → channel-kind fields (TX2) → typed events (TX3) → declarative bootstrap built on all three (TX4) → example rewrites as the proof (TX5) → migrations (TX6).

### Fluid parity scorecard (after this plan)

| Fluid capability | Watershed today | After |
|---|---|---|
| Schema declared once, types derived | decoder + encoder + seal list by hand ×3 | `record N` builder, single declaration (TX1) |
| `initialObjects` (guaranteed typed roots) | ~130 lines/app of seed + retry | `ensure_*` per slot (TX4) |
| Typed handles to any DDS | maps only | all channel kinds (TX2) |
| Per-node `Tree.on` invalidation | 14-arm union, re-read the world | `subscribe_field` + narrowed per-kind events (TX3) |
| `upgradeSchema` | `SchemaMismatch` dead end | entries-level migrations + explicit `upgrade` (TX6) |
| `Tree.runTransaction` atomicity | per-key ops, partial records observable | **deferred** (wire-level batched op; see out-of-scope) |

## TX1 — bidirectional record codecs (`schema.gleam`, target-agnostic)

A `Prop` pairs a `Field` with a getter; each field is declared **once** and both directions derive from it, so encoder/decoder drift becomes unrepresentable.

```gleam
pub opaque type Prop(s, record, a) {
  Required(field: Field(s, a), get: fn(record) -> a)
  Optional(field: Field(s, a), get: fn(record) -> Option(a))
}
pub fn prop(field: Field(s, a), get: fn(record) -> a) -> Prop(s, record, a)
pub fn optional_prop(field: Field(s, a), get: fn(record) -> Option(a)) -> Prop(s, record, a)

pub fn record3(
  ctor: fn(a, b, c) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
  p3: Prop(s, record, c),
) -> Schema(s, record)                       // record1..record9 (decision 5)
```

- Decode side: `Required` → `decode.field(key, d)`; `Optional` → `decode.optional_field(key, None, decode.map(d, Some))`.
- Encode side: `Schema.to_entries` generalizes to `to_ops: fn(record) -> List(WriteOp)`; `Optional` with `None` emits `Delete(key)` (decision 1). The existing `schema(decoder, to_entries)` constructor wraps its entries as `Put`s — hand-rolled schemas keep working; backends' `write` maps `Put`→`set`, `Delete`→`delete`.
- **`sealed_known(schema)`**: builders know every prop key, so sealing needs no hand-repeated list (kills the scoreboard triple-declaration). Explicit `sealed(keys)` stays for the raw constructor.

Tests (`test/watershed/schema_test.gleam`): round-trip law `decode_entries(s, ops_as_entries(encode(r))) == Ok(r)` across required/optional/None cases; `None` produces `Delete`; `sealed_known` rejects an undeclared key and admits `version_key`; arity spot-checks at 1 and 9.

## TX2 — channel-kind fields (schema + both facades)

`schema.gleam` stays target-agnostic: phantom kind tags plus one opaque key-carrier.

```gleam
pub type MapChannel   pub type CounterChannel   pub type OrMapChannel
pub type OrSetChannel pub type ClaimsChannel    pub type RegisterCollectionChannel
pub type TaskManagerChannel                     // + erlang-only kinds as they gain JS facades

pub opaque type ChannelField(s, kind) { ChannelField(key: String) }
pub fn channel_field(key: String) -> ChannelField(s, kind)
```

Facades add per-kind pairs (dispatch must be per-kind anyway — `resolve_counter` and `resolve_or_set` are different runtime calls with different return types):

```gleam
pub fn set_counter_field(tm: TypedMap(s), field: ChannelField(s, CounterChannel), counter: SharedCounter) -> Nil
pub fn resolve_counter_field(doc: Document, tm: TypedMap(s), field: ChannelField(s, CounterChannel))
  -> Result(Option(SharedCounter), String)   // Ok(None) = key absent; resolve errors stay retryable
```

`ChildField(s, child)` remains the nested-*typed-map* special case (it carries the child schema tag, which `ChannelField` cannot). Mechanical but wide: 2 functions × 7 kinds × 2 facades; the counter block in each facade is the template. Erlang facade covers its extra kinds (GSet, TwoPSet, Directory, JsonOt) in the same sweep.

Tests: facade-level set/resolve round trip per kind against a live runtime (gated like the existing integration tests); a `channel_field` used with the wrong resolver is a **compile error** — pin with a comment in the test, not a runtime case.

## TX3 — typed events

Three layers, one commit:

1. **Kernel** (decision 2): `ValueChanged` carries `value: Option(Json)`. Update `map_kernel`, its unit tests, and the website demo's `describeOp`/render paths that pattern-match the event.
2. **Runtime fan-out** (decision 3): subscribers become `fn(ChannelEvent) -> Nil` on both targets. Erlang facade `subscribe` re-creates today's behavior in one line (closure sends to a caller-owned subject) — no observable change for existing callers.
3. **Facades**:

```gleam
// per-kind narrowing — a counter subscriber sees only counter events
pub fn subscribe_counter(counter: SharedCounter) -> Subject(counter_kernel.CounterEvent)   // erlang
pub fn subscribe_counter(counter: SharedCounter, handler: fn(CounterEvent) -> Nil) -> Nil  // js
// ... same treatment for every kind; `subscribe` on SharedMap narrows to map_kernel.MapEvent

// typed field subscription — filter by key, decode both sides at the boundary
pub type FieldChange(a) {
  FieldChange(value: Result(Option(a), FieldError), previous: Result(Option(a), FieldError), local: Bool)
}
pub fn subscribe_field(tm: TypedMap(s), field: Field(s, a)) -> Subject(FieldChange(a))     // erlang
pub fn subscribe_field(tm, field, handler: fn(FieldChange(a)) -> Nil) -> Nil               // js
```

`Cleared` carries no per-key detail, so it fans out through `subscribe_field` as `FieldChange(value: Ok(None), previous: Ok(None), local:)` — the docstring states that clears do not report per-key previous values. Pin in a test.

Tests: kernel event payload; narrowing (counter subject never sees map events); `subscribe_field` decodes, filters foreign keys, reports `Invalid` on a type-confused remote write (write raw JSON through the untyped API in the test).

## TX4 — declarative bootstrap (`ensure_*`)

Per-slot primitives that compose, rather than a heterogeneous document record Gleam can't type. Each subsumes seed + race + retry:

```gleam
// erlang (blocking, like connect); js takes done: fn(Result(..., String)) -> Nil
pub fn ensure_counter(doc: Document, tm: TypedMap(s), field: ChannelField(s, CounterChannel))
  -> Result(SharedCounter, String)
// ... per kind, + ensure_child for nested TypedMaps, +
pub fn ensure_field(tm: TypedMap(s), field: Field(s, a), default: a) -> Nil   // set-if-absent; LWW settles races
```

Semantics (decision 4): read key → if absent, create channel + `set_*_field` → **wait synced** → re-read → resolve with bounded internal retry (the `resolve_retry_ms`/`resolve_attempts` loop moves from example code into the facade, as constants with a config escape hatch only if a second consumer needs one). Requires promoting wait-for-sync into both facades: JS has `is_synced` (poll via a small library-owned timer ffi — the example's `set_timeout` ffi moves into `watershed_js`); erlang adds the matching `runtime.await_synced` blocking call.

App-level seeding of *content* (sudoku's `seed_givens`) stays app code, run after `ensure_claims` on the channel it returns — first-writer-wins claims make concurrent seeders converge, and that stays documented at the call site.

Tests: gated integration — two clients race `ensure_*` on an empty document and adopt the same address; a third joins late and resolves without creating; `ensure_field` set-if-absent under a race converges.

## TX5 — example rewrites (the proof)

- **`sudoku_lustre`**: a `doc_schema.gleam` module declaring the six root fields (`puzzle`, `title` as `Field`s; `cells` as `ChildField`; `notes`/`givens`/`mistakes` as `ChannelField`s); bootstrap collapses to five `ensure_*` calls; `SharedChanged`-re-reads-the-world becomes per-channel narrowed subscriptions (whole-model snapshot can stay where it's genuinely cheapest — the point is the *option*). Expected: the six key constants, `require_value`, `resolve_shared_with_retry`, `wait_synced`, and `seed_document`'s handle plumbing all delete; behavior parity via the existing `smoke.gleam` script.
- **`scoreboard_cli`**: `player_schema()` moves to `record4` + `sealed_known` (three declarations become one); roster/player subscriptions drop their `untyped(...)` escapes for narrowed `subscribe`.
- **`dice_lustre`**: minimal touch — adopt `ensure_field`/narrowed subscribe only if it stays a diff-positive simplification.

This rung is the acceptance test for the plan: if the rewrites don't obviously pay, the API is wrong — stop and revisit rather than ship.

## TX6 — schema evolution

Entries-level migrations (JSON-native, no old-schema types to keep alive):

```gleam
pub fn versioned_with_migrations(
  schema: Schema(s, record), version: Int,
  migrations: List(#(Int, fn(List(#(String, Json))) -> List(#(String, Json)))),  // from-version → rewrite
) -> Schema(s, record)
```

- `decode_entries`: stored version < current → fold applicable migrations in order, then decode; stored version > current → `SchemaMismatch` (fail closed forward, open backward).
- Reads stay pure (no write-on-read). An explicit `upgrade(tm, schema) -> Result(Nil, FieldError)` — read via migrations, write the migrated record back, re-stamp — mirrors Fluid's `upgradeSchema` as a deliberate act.
- Unstamped maps keep today's accepted-as-is behavior (schema.gleam:207).

Tests: v1 entries read through a v2 schema with a migration; forward mismatch still errors; `upgrade` round-trips and re-stamps; migration chain (v1→v2→v3) folds in order.

## Deferred / out of scope (recorded so they aren't re-litigated)

- **Atomic multi-record writes** — `write` stays per-key ops; peers can observe partial records. Fixing it is a wire-format change (batched multi-set map op) worthy of its own plan once a real consumer hurts.
- **Typed OR-map values / OR-set element codecs** — after the OR-map kernel plan lands; same `Field`-style codec applies.
- **Typed signals/presence** — promote sudoku's `presence.gleam` + a `Field`-style signal schema; small standalone plan (Fluid comparison: `@fluidframework/presence`).
- **Server-side schema enforcement** — typing stays a client decode boundary by design; levee is Fluid-compatible and content-agnostic.
- **Generated TS `.d.ts` for JS consumers** — no external JS consumers exist.

## Milestones (one commit each)

| # | Milestone | Exit gate | Commit |
|---|---|---|---|
| TX0 | Plan doc | — | `docs: typed-layer DX plan` |
| TX1 | Record codec builder (`Prop`, `record1..9`, `WriteOp`, `sealed_known`) | schema tests + round-trip law green, both targets build | `feat(schema): bidirectional record codecs` |
| TX2 | Channel-kind fields, both facades | per-kind round trips green | `feat(schema): typed channel fields for every channel kind` |
| TX3 | Event value + closure fan-out + narrowed/per-field subscriptions | kernel/runtime/facade tests; website demo still renders events | `feat(runtime): typed per-kind and per-field event subscriptions` |
| TX4 | `ensure_*` bootstrap + `await_synced` on both targets | gated two-client race integration test | `feat(runtime): declarative ensure bootstrap for typed documents` |
| TX5 | Example rewrites | sudoku smoke parity; scoreboard manual script; net-negative diff in app code | `refactor(examples): move examples onto the typed layer` |
| TX6 | Migrations + `upgrade` | schema tests incl. chain fold | `feat(schema): versioned schema migrations with explicit upgrade` |
| TX7 | Docs sweep (module docs, README typed example, stale "typed maps are map-only" language) | — | `docs: document the typed document layer` |

Ordering constraints: TX1→TX2 independent of TX3; TX4 needs TX2 (+ TX3 only for its tests' subscriptions); TX5 needs TX1–TX4. TX6 is independent after TX1 and can land any time.

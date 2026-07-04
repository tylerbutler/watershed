# OR-Map kernel plan — second lattice-backed kernel, first as a runtime channel

**Date:** 2026-07-03
**Builds on:** `2026-07-03-pn-counter-kernel-plan.md` (lattice-kernel shape, re-brand idiom, double-encoded-JSON workaround, oracle soundness style), `2026-07-03-runtime-generalization-plan.md` (the authoritative "add a channel" spec), `2026-07-03-kernel-fuzz-harness-plan.md` (harness contract).
**Reference source:** *not* a Fluid TS file. Semantics come from the lattice library's ORMap (`../lattice/packages/lattice_maps/src/lattice_maps/or_map.gleam` + `crdt.gleam`, consumed as the hex release `lattice_maps` 1.1.0) with behavioral parity to `src/watershed/pn_counter_kernel.gleam` for the pending/ack/rollback lifecycle.

**Decisions already made (flagged — confirm before OM1):**

1. **`CrdtSpec` is chosen at map creation**, exposed as two modes: `TallyMode` (`PnCounterSpec` — named signed tallies; the demo) and `RegisterMode` (`LwwRegisterSpec` — String payloads). Motivated by "can ORMap store a DDS?": not directly (the lattice `Crdt` union is leaf CRDTs only — counters, registers, sets; maps are excluded to avoid circularity), but RegisterMode strings holding encoded handles give **DDS-by-handle**, with `channel.handle_addresses` parsing them for attach ordering — the exact `map_kernel` precedent. The other five specs are rejected for v1: no verb could touch such values, so they'd be dead weight in snapshots.
2. **Resurrection semantics**: remove hides a key, it does not erase its tally; re-adding resurrects it (`+12, remove, re-add +5 → 17` everywhere). This is honest OR-map-without-prune behavior (see Finding B); prune/GC is out of scope. The demo copy leans into it.

## Why this rung

The PN counter proved a state-based delta CRDT can back a kernel (idempotent merge ⇒ trivially safe ack/reconnect/duplicate paths, mergeable summaries) — but it was deliberately scoped pure: it never became a runtime channel, and the runtime today hosts only identity-free kernels (map, counter). This rung buys three new things:

1. **First lattice-backed kernel through the full runtime path** — channel sums, wire codecs, runtime_core verbs, both actors, both facades — extrapolating the counter's R2 template to a replica-identified kernel.
2. **Replica identity threading in the runtime** (OM3): `channel.new`/`from_snapshot` gain a replica argument. Every future lattice kernel reuses this, exactly as PN0's harness identity threading is reused here.
3. **A composite CRDT with observed-remove semantics** — the fuzz oracle must model causal concurrency (add-wins) from a linearized log, which forces the `ref_seq` op-rewrite pattern (claims precedent) into a CRDT setting, plus one harness extension (H3).

## Two lattice findings that drive the kernel design (verified in or_map.gleam)

- **Finding A — local/remote divergence.** `update_with_delta` *replaces* the author's local value (`put_value` → `dict.insert`, or_map.gleam:610-623) while receivers *merge* the delta (`apply_delta` → `dict.combine` + `crdt.merge`, :683). After remove→re-add, the author's replaced value (fresh counter) and a peer's merged value (retained old ⊔ fresh) diverge. **Discipline: the kernel never keeps the map returned by `update_with_delta`/`remove_with_delta`** — mutations only *produce deltas*; the kernel applies each delta to its own state via `apply_delta`. State = join of deltas, identical on author and peers. (File as an upstream lattice issue.)
- **Finding B — max-merge swallowing.** `remove_with_delta` leaves `map.values` untouched (values are retained until `prune`, which this runtime never calls — no stable-VV plumbing). An increment on a removed-but-retained key computed off `default_crdt` (cumulative = amount) would be silently swallowed by max-merge against the retained higher cumulative. **Fix: the kernel keeps `own_tallies: Dict(String, #(Int, Int))`** — its own per-key pos/neg cumulative ledger, never reset by removes — and builds each increment's value CRDT as its replica's full cumulative counter (the update fn ignores the current value entirely). Consequences: increments are never lost; deltas stay minimal (author's entry only); the fuzz value-oracle collapses to "Σ of all update amounts per key"; and resurrection semantics (decision 2) follow.

## Kernel design — `src/watershed/or_map_kernel.gleam`

Pure; mirrors `pn_counter_kernel.gleam` (sequenced/optimistic pair, FIFO pending, LIFO rollback, coherence check).

```gleam
pub type OrMapMode { TallyMode RegisterMode }        // to_spec/from_spec helpers
pub type OrMapValue { Tally(Int) Register(String) }

pub type OrMapState {
  OrMapState(
    replica_id: ReplicaId,
    mode: OrMapMode,                         // explicit: unrecoverable from opaque ORMap
    sequenced: ORMap,                        // join of sequenced deltas; what summaries persist
    optimistic: ORMap,                       // sequenced ⊔ pending deltas (cached)
    own_tallies: Dict(String, #(Int, Int)),  // TallyMode: pos/neg cumulative, never reset
    pending: List(PendingOp),                // FIFO
    next_pending_message_id: Int,
  )
}
pub type PendingOp { PendingOp(op: OrMapOp, message_id: Int) }

pub type OrMapOp {
  Increment(key: String, amount: Int, delta: ORMapDelta)
  SetRegister(key: String, value: String, timestamp: Int, delta: ORMapDelta)
  Remove(key: String, delta: ORMapDelta)
}
// delta is authoritative for state; intent fields serve ack/rollback validation,
// events, oracle independence, and dump readability (pn precedent).

pub type OrMapEvent {
  TallyUpdated(key: String, applied: Int, new_value: Int)
  RegisterUpdated(key: String, value: String)
  KeyRemoved(key: String)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
  ModeMismatch(detail: String)   // increment on RegisterMode, set on TallyMode
  CorruptDelta(detail: String)   // lattice TypeMismatch on remote input
}
```

API surface (pn parity unless noted):

| Function | Notes |
|---|---|
| `new(ReplicaId, OrMapMode)` | |
| `increment(state, key, amount) -> Result(#(state, events, op, message_id), KernelError)` | TallyMode only. Bump the `own_tallies` half; rebuild own counter `pn_counter.new(rid) \|> try_increment(pos') \|> try_decrement(neg')` (`let assert Ok` — non-negative by construction); `update_with_delta(optimistic, key, fn(_) { CrdtPnCounter(own) })` **only to produce the delta**, then `apply_delta(optimistic, delta)` (Finding A; `let assert Ok` — own lineage). Append pending, emit `TallyUpdated`. |
| `set_register(state, key, value, timestamp) -> Result(...)` | RegisterMode only. `fn(_) { CrdtLwwRegister(lww_register.new(value, timestamp, rid)) }`; same delta-then-apply_delta discipline. Timestamp is caller-supplied — the kernel stays pure. |
| `remove(state, key) -> #(state, events, op, message_id)` | Mode-agnostic, infallible. `remove_with_delta(optimistic, key)` — tombstones over dots observed in *optimistic* (delivered + own pending; this is what makes the fuzz `ref_seq` rule sound). `own_tallies` untouched (Finding B). Remove of an absent key yields an empty delta — still routed, harmless. |
| `keys` / `get` / `entries` (+ `sequenced_entries`) | Optimistic reads; `entries -> List(#(String, OrMapValue))` **sorted by key** — also the fuzz `observe` and the diffing base for remote events. |
| `apply_remote(state, op) -> Result(#(state, events), KernelError)` | `apply_delta` into both sequenced and optimistic (delta laws make ordering vs pending irrelevant). Events = diff of sorted entries before/after; silent on no-op merges. Lattice `TypeMismatch` → `CorruptDelta` — kernels never panic on remote input; `let assert` is reserved for own-lineage merges with unreachability comments. |
| `ack_local` / `ack_local_with_message_id` | Pop FIFO head, validate op equality (+ message id); merge the delta into `sequenced` only — ack transparency. |
| `rollback(state, op, message_id)` | Pop newest pending (LIFO), validate; recompute `optimistic = fold(apply_delta, sequenced, remaining pending deltas)`; **revert `own_tallies`** for a rolled-back Increment; compensating diff events. LIFO guarantees a pending remove pops before the update whose dot it tombstones. |
| `apply_stashed_op(state, op)` | pn idiom: re-merge the op's original delta (idempotent), re-pend, return the same op. Documented limitation: does not update `own_tallies` — safe when the stashed delta belongs to a retired identity (reload path) or was fabricated through mutation verbs (fuzz path); the runtime has no stash path today. |
| `summary(state) -> Json` | `or_map.to_json(sequenced)` — the spec is embedded (`state.crdt_spec`, verified). |
| `from_summary(json_string, ReplicaId)` | Parse; decode `["state","crdt_spec"]` → mode (own small decoder — lattice's mapper is private; unsupported spec → decode error); re-brand `let assert Ok = or_map.merge(or_map.new(rid, spec), parsed)` (merge keeps a's id — PN5 idiom); `own_tallies` empty. |
| `from_sequenced(ORMap, OrMapMode, ReplicaId)` | Same re-brand from an already-parsed map — used by `channel.from_snapshot`. |
| `check_cache_coherence` | `optimistic == fold(apply_delta, sequenced, pending)` structurally; if ORMap equality proves target-flaky, compare `to_json` strings. |

Unit suite `test/watershed/or_map_kernel_test.gleam`: counter-parity groups (optimistic visibility, FIFO ack + transparency, LIFO rollback across interleaved remotes, message-id validation, empty-queue errors) plus OR-map groups — add-wins race in both delivery orders (A removes k while B increments concurrently → key survives with full tally), duplicate-delivery idempotency, remove/re-add resurrection pin (`+12, remove, re-add +5 → 17`), **Finding-A divergence pin** (author state ≡ peer state after remove→re-add; fails if anyone "simplifies" back to keeping `update_with_delta`'s map), mode guards, summary round-trip + re-branding (loaded client's next delta lands under its own replica key), summary-excludes-pending, coherence across a scripted sequence, register LWW (higher timestamp wins; equal-timestamp replica-id tiebreak pinned — lww_register.gleam:103-119).

## Fuzz — harness change H3 + observed-remove oracle

### H3 (`test/watershed/fuzz/kernel_fuzz.gleam`)

```gleam
apply_stashed: Option(fn(state, op) -> #(state, op))             // before
apply_stashed: Option(fn(state, op, SubmitMeta) -> #(state, op)) // after
```

`stashed_op` passes `SubmitMeta(client.delivered)`. Rationale: stash mirrors submit (H2 precedent); kernels whose ops embed submit-time metadata (claims `ref_seq`, or-map remove `ref_seq`) need the meta on the stash path or a re-generated remove's tombstones and its declared `ref_seq` disagree and the oracle diverges. Mechanical updates: `counter_model.gleam`, `pn_counter_model.gleam` (add `_meta`), `rollback_stash_test.gleam` toy closure. One new harness test: `apply_stashed` receives the client's delivered cursor.

### Model — `test/watershed/fuzz/or_map_model.gleam` (TallyMode only; RegisterMode excluded — wall-clock LWW is non-deterministic; optional follow-up with synthetic timestamps)

```gleam
pub type OrMapCommand {
  CmdIncrement(key: String, amount: Int, delta: Option(ORMapDelta))
  CmdRemove(key: String, ref_seq: Int, delta: Option(ORMapDelta))
}
```

- `gen_op`: keys `{"a","b"}` (races stay frequent), amounts `n % 21 - 10`, ~1 in 4 removes; `delta: None`, `ref_seq: 0` — slot-filling ops (pn/claims precedent).
- `submit`: increments via `kernel.increment` → rewrite with delta; removes via `kernel.remove` → rewrite with delta **and `ref_seq = meta.last_seen_seq`**. Never `None`.
- `apply_stashed` (H3): fabricate through the same mutation verbs (maintains `own_tallies`), set the remove's `ref_seq` from the meta.
- `observe`: sorted `List(#(String, Int))`; `canonicalize: None`; `ack_preserves_view: True`; `check: Some(check_cache_coherence)`.
- Op JSON: tagged objects; delta double-encoded as a JSON string via `delta_to_json`/`delta_from_json` (string-in only — pn precedent).

**Oracle (independent — never calls the CRDT's merge):** fold the sequenced log with

```
dots:    Dict(key, List(#(author: Int, seq: Int)))   // seq = 1-based log position
tallies: Dict(key, Int)

CmdIncrement(key, amount, _) by a at seq s -> add dot #(a, s); tallies[key] += amount
CmdRemove(key, ref_seq, _)   by c          -> dots[key] = filter(dots[key],
                                               fn(d) { d.seq > ref_seq && d.author != c })
view: keys with live dots, value = tallies[key], sorted
```

*Why `ref_seq` + author suffices:* a remove's tombstones cover exactly the dots in the remover's **optimistic** key-set at submit time = (i) delivered ops, `seq <= last_seen_seq = ref_seq`, plus (ii) the remover's own pending ops. Per-client order is FIFO through inbox → resend → log, so own-pending-at-submit ops are precisely the remover's own ops appearing earlier in the log — the `author == c` clause; own ops submitted after the remove are untouched. This generalizes the claims `ref_seq` answer; the author clause is new because a remover observes its own unacked adds. *Why values never reset:* Finding B — `own_tallies` makes every routed delta's per-replica cumulative monotone and computed off all prior routed deltas, so at full sync `value(key) = Σ over replicas of max cumulative = Σ of all sequenced amounts for that key`, removes notwithstanding. Both arguments go in the module doc verbatim.

Fuzz entry `test/watershed/or_map_fuzz_test.gleam` (client_count 3; rollback/stash weights like pn) + a `fuzz_replay_test.gleam` arm. Mutation checks (plant → confirm caught → revert; keep one shrunk fixture):

| # | Mutation | Caught by |
|---|---|---|
| M1 | ack skips merging into `sequenced` | check hook; AddClient joins from an undercounted summary |
| M2 | apply_remote skips `optimistic` | check hook |
| M3 | rollback skips recompute or `own_tallies` revert | oracle (next increment swallowed) / convergence |
| M4 | increment built off current-value default instead of `own_tallies` (Finding B bug) | oracle mismatch after remove/re-add |
| M5 | local state kept from `update_with_delta` instead of `apply_delta` (Finding A bug) | convergence failure after remove/re-add |
| M6 | drop the oracle's author clause (planted in an oracle test to prove it load-bearing) | oracle mismatch when a client removes with own pending adds |
| M7 | `init` ignores identity (shared replica id) | oracle/convergence — dot + tally collision; keep as a permanent test (pn M5 pattern) |

## Runtime wiring

### Replica identity (OM3, zero behavior change)

Verified: channels are only creatable in `Ready`/`Reconnecting` phases and every `channel.new`/`from_snapshot` call site has a client id in scope (`bootstrap`/`seed_channels` via `connected.client_id`; `remote_attach`/`submit_attaches`/`create_detached` via `core.client_id`) — no pre-connect identity gap. Thread it as arguments:

```gleam
// channel.gleam — creation params are not the type
pub type ChannelInit { InitMap  InitCounter  InitOrMap(mode: or_map_kernel.OrMapMode) }
pub fn init_type(init: ChannelInit) -> ChannelType
pub fn new(init: ChannelInit, replica replica: String) -> ChannelState
pub fn from_snapshot(snapshot: Snapshot, replica replica: String) -> ChannelState
```

Map/counter ignore `replica`. Document on `ChannelInit`: (a) reconnect keeps the kernel's original `ReplicaId` while `core.client_id` changes — correct, server-issued ids are never reused and cumulative deltas continue monotone under the retired id; (b) a joiner loading a summary re-brands under its own id via `from_sequenced` (the snapshot's embedded replica id is the summarizer's).

### channel.gleam additions (compiler-flagged)

- `ChannelType.OrMapChannel` ↔ new `wire.channel_type_or_map = "ormap"`.
- `ChannelState`/`ChannelOp`/`ChannelEvent` wrapper variants.
- `Snapshot.OrMapSnapshot(mode, state: or_map.ORMap)`; `encode_snapshot` → `or_map.to_json` (spec self-describing; **no summary-blob version bump** — v3's `data` is already type-dependent). `snapshot_decoder(OrMapChannel)`: `decode.at(["state","crdt_spec"], decode.string)` → mode (reject unsupported specs), then `wire.json_value_decoder()` → `json.to_string` → `or_map.from_json` (composable workaround for the string-only `from_json`).
- `LocalOpMeta.OrMapMeta(message_id: Int)` (counter pattern).
- `apply_remote`/`ack_local` arms; kernel `CorruptDelta` → new `ChannelError.CorruptRemoteOp(detail)` (fatal, unlike retryable `WrongChannelType`).
- `same_shape`: constructor + key + intent fields (not the delta — the byte-precise check stays in kernel ack). `same_snapshot`: mode + ORMap structural equality (pin the decode round trip in wire_test; fallback: compare `to_json` strings).
- `handle_addresses`: RegisterMode → parse each value string with `wire.json_value_decoder()` → `handle.collect_handle_addresses`, unparseable values skipped; TallyMode → `[]`. This makes register-mode DDS-by-handle attach-order correctly.

### Non-compiler-flagged sites (the channel.gleam module-doc checklist)

1. **`wire/ops.gleam`** — envelopes `{"type":"orMapIncrement","key","amount","delta"}`, `{"type":"orMapSet","key","value","timestamp","delta"}`, `{"type":"orMapRemove","key","delta"}`; delta double-encoded (string), decoded via `decode.string |> decode.then(delta_from_json …)`; arm in `channel_op_decoder`.
2. **`runtime_core.gleam`** — `locate_or_map` (mirrors `locate_counter`); verbs `or_map_increment`/`or_map_set`/`or_map_remove` with the Detached/Attached split and `OrMapMeta` stamping; **`or_map_set` runs `attach_dependencies` on the parsed value** (mirror `set`) so a handle stored in a register attaches its target first; reads `or_map_entries`/`or_map_value`/`or_map_keys`; new `CoreError.OrMapModeMismatch(address, detail)` (retryable API misuse, like `WrongChannelType`).
3. **Both actors** (`runtime.gleam`, `runtime_js.gleam`) — `CreateOrMap(mode, reply)`, `IncrementOrMapKey`, `SetOrMapKey`, `RemoveOrMapKey`, `GetOrMapEntries`/`GetOrMapValue`/`GetOrMapKeys`. The `SetOrMapKey` timestamp source lives here: erlang `os:system_time(millisecond)` external; JS `Date.now()` external (add to an existing ffi module).
4. **Both facades** (`watershed.gleam`, `watershed_js.gleam`; counter block as template) — `pub opaque type SharedOrMap`, `create_or_map(document, mode)`, `or_map_handle_of`, `resolve_or_map`, `or_map_increment`, `or_map_set` (signed by wall clock inside the actor), `or_map_remove`, `or_map_entries`, `or_map_value`, `or_map_keys`, `subscribe_or_map`.

### Runtime tests

- `runtime_core_test.gleam`: create/attach/increment→ack round trip; remote apply; core-level add-wins (remove sequenced after a concurrent increment leaves the key live); mode-mismatch error; detached edits produce no ops; resubmit restamps or-map ops.
- `wire_test.gleam`: all three op codecs round-trip (incl. delta equality after decode — the `same_shape`/ack gate); attach envelope with `channelType:"ormap"`; summary blob v3 with a mixed map+counter+ormap channel list; unsupported-spec snapshot rejected.
- `integration_test.gleam`: `mixed_or_map_converges_test` (env-gated like `mixed_counter_converges_test`): root map holds an or-map handle; A strikes a stockpile while B logs into it; both converge on the surviving tally; a third client bootstraps from a summary and sees it; plus a RegisterMode variant storing a counter handle in a register and resolving it (the DDS-by-handle proof).

## Website demo — 4th picker cell

**Concept:** *stockpile & borrow-pit ledger*. Keys = named stockpiles (`spoil-north`, `borrow-pit-7`, `wash-fill`), values = signed yd³ tallies. Hero moment = the add-wins race: **A strikes a stockpile while B concurrently logs material into it → after sync the row survives, with every logged yard** (explicit contrast with the map cell's LWW race). Secondary beat: strike then re-open resurrects the tally — "removal hides, it doesn't erase."

- **`website/src/components/Demo.astro`**: 4th radio in `[data-dds-picker]` (`value="ormap"`, label "OR-map"); per-client `.dds-ormap` ledger table (row per stockpile: key, tabular-nums yd³, `+2/+6` log buttons, strike `✕`; struck rows strikethrough/muted with a re-open button submitting `+0`); `[data-merge-rule="ormap"]` copy — *"Merge rule — add-wins, observed-remove. A strike only removes what the striker had seen. Race a strike against a concurrent delivery and the stockpile survives — with every logged yard. Re-opening a struck pile brings its ledger back."*; extend the `.rig[data-dds=…]` display matrix to 4; update head paragraph + `<noscript>` kernel lists. 1px `--ink` linework, pending magenta per DESIGN.md conventions.
- **`website/src/scripts/demo.js`**: import `or_map_kernel.mjs` from the compiled build; baseline TallyMode kernel under `survey-baseline` replica → clients boot via `from_summary` under `client-a`/`client-b` (the `pnBaselineSummary` pattern); `deliver()` gains the ormap branch; `localOrMapLog`/`localOrMapStrike` mirror `localPnUpdate`; `describeOp` labels (`log +6 yd³ → spoil-north`, `strike spoil-north`, `re-open spoil-north`); `renderOrMap` from `kernel.entries` against the fixed roster (struck = absent from entries); race label "Race a strike against a delivery" (strike on A + log on B in one latency window); reset = re-open struck piles then compensating increments. Optional: extend the PN-only "Re-deliver last delta" idempotency button to ormap (`!["pn","ormap"].includes(activeDds)`).
- **`DESIGN.md`**: extend the demo-conventions bullets (import list, "hosts all four DDSes", OR-map cell framing).

## Milestones (one commit each)

| # | Milestone | Exit gate | Commit |
|---|---|---|---|
| OM0 | Plan doc + H3 | `just test` green; new harness meta test; existing fixtures replay | `docs:` + `test(fuzz): thread SubmitMeta through apply_stashed` |
| OM1 | Dep + kernel core + unit suite | unit groups green; `just build` both targets (proves lattice_maps compiles to JS) | `feat: add or_map_kernel, a lattice-backed observed-remove map` |
| OM2 | Fuzz model + mutations M1–M7 | `just fuzz` (5000 iter) green; each mutation caught; one fixture kept | `test(fuzz): or_map model with observed-remove oracle` |
| OM3 | Identity threading refactor | **zero behavior change**; full suite green, type-level updates only | `refactor(runtime): thread replica identity into channel construction` |
| OM4 | Channel onboarding (channel/wire/core/actors/facades + tests) | runtime_core/wire tests green; gated integration race passes against live levee | `feat(runtime): or-map channel across wire, core, actors, and facades` |
| OM5 | Website demo | `pnpm dev` manual script | `feat(website): or-map stockpile ledger demo cell` |
| OM6 | Docs sweep (channel.gleam checklist, DESIGN.md, stale "three kernels" docs) | — | `docs: document the or-map channel and demo conventions` |

Dependency step (OM1): `gleam.toml` `lattice_maps = ">= 1.1.0 and < 2.0.0"` (hex; pulls `lattice_registers`/`lattice_sets` transitively); `just deps` regenerates `manifest.toml` + the dice_lustre lockfile.

## Verification

```sh
just deps && just ci                            # format + lint + fast-fuzz test + both-target build
just fuzz                                       # FUZZ_ITERATIONS=5000 deep run
FUZZ_ITERATIONS=1000 FUZZ_SEED=42 gleam test    # pinned reproducible run
# integration: env-gated, needs a live levee (same gate as mixed_counter)
cd website && pnpm dev
# manual: switch to OR-map · log into two piles on both clients · strike-vs-delivery race
# → row survives with full tally · strike then re-open → tally resurrects · reset ·
# reduced-motion pass · picker keyboard nav
```

Mutation verification per the OM2 table: plant, confirm the named check catches it and the shrunk fixture lands in `test/fixtures/fuzz_failures/`, revert, confirm green.

## Risks / open items

1. **The two flagged decisions** (spec-at-creation + two-mode facade; resurrection semantics) were made while the user was AFK — confirm before OM1, including whether RegisterMode ships in v1 or trails as a follow-up commit.
2. **`own_tallies`** duplicates per-replica cumulative state the opaque CRDT holds internally; disciplined by unit tests + mutations M3/M4, not directly coherence-checkable (no lattice accessor).
3. **Upstream lattice issues to file** (non-blocking): Finding A; no embeddable `Decoder` values; no spec/replica accessors on opaque types; consider exposing per-replica counter reads.
4. **LWW timestamps are wall-clock** (actor-supplied ms; lattice tiebreaks equal stamps by replica id). Inherent to LWW; register mode therefore excluded from fuzz.
5. **ORMap/ORMapDelta structural equality after JSON round trip** gates kernel ack validation, `same_snapshot`, and the coherence check — pin with wire_test round-trip equality on both targets; fallback is string-comparing `to_json`.
6. **OM3 ripples** through every `channel.new`/`from_snapshot` call site incl. tests — mechanical; isolated as its own zero-behavior-change commit.

## Out of scope

- Prune/GC (needs stable-VV / min-seq plumbing; `SequencedMeta.min_sequence_number` already threads in the fuzz harness for later).
- The other five `CrdtSpec`s (MvRegister, sets, GCounter) as facade modes.
- RegisterMode fuzz model (possible follow-up with synthetic timestamps).
- Ordered iteration / richer read API.
- Upstream lattice changes (issues filed, not blocked on).

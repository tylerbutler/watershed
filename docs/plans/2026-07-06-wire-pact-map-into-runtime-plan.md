# Plan: Wire `pact_map_kernel` into the runtime

**Date:** 2026-07-06
**Status:** 📋 Proposed — not started. Blocked on a design decision
(reaction-submit infrastructure) called out below.
**Repo:** `claude-workspace/watershed`
**Companion docs:**
`2026-07-03-pact-map-kernel-plan.md` (the kernel itself),
`2026-07-06-wire-pn-counter-into-runtime-plan.md` (the mechanical template),
`2026-07-06-runtime-kernel-wiring-order.md` (sequencing).

## Context

`pact_map_kernel` (`src/watershed/pact_map_kernel.gleam`, fully read) is a
**quorum / consensus** map: a `set` first goes *pending* with a frozen signoff
list captured from the connected quorum at sequencing time, then becomes
*accepted* once every expected client has sent an `Accept` (or left). It has
kernel unit + fuzz tests but **zero references outside its own file**.

It is **architecturally unlike** the plain optimistic kernels
(`map`, `counter`, `pn_counter`, `or_*`, `g_set`, `two_p_set`):

- **No optimistic lifecycle.** There is no `apply_remote`/`ack_local`/
  `rollback`/`apply_stashed_op`. `set`/`delete` return an
  `Option(PactMapOp)` and do **not** mutate local state — nothing takes effect
  until the op is *sequenced* via `apply_set`, and acceptance completes via
  `apply_accept`.
- **Reactive follow-up op.** `apply_set(state, op, seq, connected, self_id)`
  returns `#(state, events, SetReaction)` where
  `SetReaction = OweAccept(op) | NoReaction`. When this client is in the
  signoff list, the kernel *owes* an `Accept(key)` op that must be submitted to
  the server as a fresh outbound op. **The runtime has no vehicle for
  auto-submitting a kernel-produced follow-up op except json0's
  `take_outbound`/`collect_released_ops` loop** (`channel.gleam:788`,
  `runtime_core.gleam:487`), which today only handles `JsonOtState`.

### Public API (verified)

| Fn | Signature (abridged) | Notes |
|----|----------------------|-------|
| `new` / `from_summary` | `List(#(String, Pact))` | summary is a list of key→Pact |
| `summary_entries` | `-> List(#(String, Pact))` | key-sorted |
| `get` | `-> Option(Json)` | accepted value only |
| `get_with_details` | `-> Option(Accepted)` | value + accept seq |
| `is_pending` / `get_pending` | | pending inspection |
| `keys` | `-> List(String)` | |
| `set` | `(key, value, last_seen_seq) -> Option(PactMapOp)` | **no local apply**; `None` if already pending |
| `delete` | `(key, last_seen_seq) -> Option(PactMapOp)` | emits `Set(key, None, _)` |
| `apply_set` | `(op, seq, connected, self_id) -> #(state, events, SetReaction)` | the sequenced-Set path |
| `apply_accept` | `(key, from_client, seq) -> Result(#(state, events), KernelError)` | the sequenced-Accept path |
| `remove_member` | `(client_id, leave_seq) -> #(state, events)` | drains signoffs on leave |

`PactMapOp = Set(key, value: Option(Json), ref_seq) | Accept(key)`.
`PactMapEvent = WentPending(key) | WentAccepted(key)`.

### The existing consensus template: `task_manager`

`task_manager_kernel` is **already wired** and is a consensus kernel that reads
`meta.quorum` / `meta.author` in `channel.apply_remote`/`ack_local`
(`channel.gleam:483,718`). It proves the quorum-meta plumbing works:
`apply_remote_channel` (`runtime_core.gleam:703`) already builds
`SequencedMeta{ seq, author, self, quorum:[self, author], min_seq, ... }`.
**Reuse this meta.** The 2-element `quorum` is the existing runtime
approximation; `pact_map` will use `meta.self` for `self_id` and `meta.quorum`
(or a richer membership list if introduced) for `connected`.

> ⚠️ Note: `task_manager` is wired for its *optimistic* ops but its own
> `remove_client`/`on_disconnect` are **also never called** — the disconnect
> gap (below) is repo-wide, not pact_map-specific.

## Key design decision (must resolve before coding)

**How does the `OweAccept` reaction reach the wire?** Options:

- **(A) Extend the `take_outbound` buffer to all kernels.** Give
  `channel.gleam` a generic per-channel "owed outbound ops" queue in
  `ChannelState` (or a small wrapper), have the `PactMap` `apply_remote` arm
  push the `Accept` op onto it, and generalize `channel.take_outbound` to drain
  it (not just json0). `collect_released_ops` already stamps CSN + in-flight
  and submits — **no runtime.gleam change needed for the submit itself.**
  *Recommended:* smallest blast radius, reuses a proven loop, keeps the kernel
  pure (buffer lives in the channel wrapper, not kernel state).
- **(B) Return the reaction up through `apply_remote`'s result type.** Change
  `channel.apply_remote` to return an optional follow-up op and thread it
  through `apply_remote_channel` → the actor loop. More invasive (touches a
  shared signature used by every kernel) and re-implements what
  `collect_released_ops` already does.
- **(C) Kernel-owned owed buffer.** Add an `owed: List(PactMapOp)` field to
  `PactMapState` and expose `take_owed`. Keeps everything in the kernel but
  mutates the pure-port state shape (diverges from the FluidFramework port and
  the fuzz model).

**Recommendation: Option (A).** Introduce a generic released-ops buffer at the
channel-wrapper layer and route pact_map's `OweAccept` through it.

## Wiring surface (mirrors the pn_counter checklist, plus reactions)

1. **`wire.gleam`** — `pub const channel_type_pact_map = "pactMap"`.
2. **`channel.gleam`**
   - Add `PactMap*` to `ChannelType`/`Init`/`State`/`Op`/`Event`/`Snapshot`
     (`PactMapSnapshot(entries: List(#(String, Pact)))`). No `LocalOpMeta`
     variant is strictly needed if `set`/`delete` produce ops with no ack-time
     metadata — but decide how own-op echoes are recognized (see below).
   - `apply_remote` arm: dispatch `Set → apply_set(op, meta.seq, meta.quorum,
     meta.self)` and `Accept → apply_accept(key, meta.author, meta.seq)`.
     On `OweAccept(accept_op)`, push it onto the released-ops buffer chosen in
     Option (A).
   - **Own-op path.** Because there is no optimistic pre-apply, a client's own
     `Set`/`Accept` should be applied when it sequences, *not* pre-acked.
     Decide whether own ops route through `ack_own_op` (FIFO echo check via
     `same_shape`) then also run `apply_set`/`apply_accept`, or through
     `apply_remote_channel` directly. The FluidFramework PactMap applies on
     sequencing regardless of author — favor routing **both** own and remote
     Set/Accept through the same `apply_set`/`apply_accept` call, using
     `is_own_op` only to reclaim the in-flight entry. This needs a small change
     to how `handle_op` (`runtime_core.gleam:590`) treats consensus channels.
   - `same_shape` / `same_pact_map_shape` for the echo sanity check.
   - `snapshot`/`from_snapshot`/`attach_snapshot`/`encode_snapshot`/
     `snapshot_decoder` over `summary_entries` (needs a `Pact` JSON codec:
     `accepted: {value, sequence_number}` + `pending: {value,
     expected_signoffs}`).
   - `handle_addresses` (no handle values expected; return `[]`).
3. **`wire/ops.gleam`** — encode/decode `PactMapOp`:
   `Set → {type:"pactMapSet", key, value:Option(Json), refSeq:Int}`,
   `Accept → {type:"pactMapAccept", key}`. Extend `encode_channel_op` +
   `channel_op_decoder`; add `encode_pact_map_envelope`/`decode_*`.
4. **`runtime_core.gleam`** — `pub fn pact_map_set`, `pact_map_delete`
   (submit the `Option(PactMapOp)` from the kernel; `None` = no-op),
   `locate_pact_map`, `tag_pact_map_events`, and reads `pact_map_get`,
   `pact_map_keys`, `pact_map_is_pending`, `pact_map_get_with_details`. The
   `Accept` follow-up is submitted automatically via the released-ops loop —
   **no explicit accept verb is exposed to callers.**
5. **`runtime.gleam`** — `Msg`: `CreatePactMap`, `SetPactMap(addr,key,val)`,
   `DeletePactMap(addr,key)`, `GetPactMapValue`, `GetPactMapKeys`,
   `GetPactMapPending` + handlers + `InitPactMap` import.
6. **`runtime_js.gleam`** — `create_pact_map`, `pact_map_set`,
   `pact_map_delete`, `pact_map_get`, `pact_map_keys`, `pact_map_is_pending`.
7. **Tests** — `pact_map_channel_test.gleam`: two-client convergence
   (set → pending → accept → accepted), snapshot round-trip, `same_shape` echo,
   and a **reaction test** asserting that a sequenced `Set` naming this client
   in the quorum produces an auto-submitted `Accept` outbound op via
   `collect_released_ops`. Extend `wire_test.gleam` with Set/Accept envelope
   round-trips. Kernel fuzz (`pact_map_model`, has a `remove_member` capability
   + reactive Accept via `last_reaction`) already exists; no runtime-fuzz layer.

## Out of scope for this plan (tracked separately)

- **Client-leave / `remove_member`.** `apply_set` freezes the signoff list at
  sequencing time; a pending value only settles when every signer accepts *or
  leaves*. Without leave wiring, a value can hang pending forever if a signer
  disconnects before accepting. See the disconnect section of
  `2026-07-06-wire-ordered-collection-into-runtime-plan.md` and the ordering
  doc — the leave hook is shared infrastructure and is sequenced **after** the
  optimistic-path wiring. Ship pact_map's sequenced Set/Accept path first;
  connect `remove_member` when the shared leave hook lands.

## Validation gates

`gleam build` (both targets), `just lint`, `just test`, `just fuzz`
(FUZZ_ITERATIONS=5000). New reaction test must show the auto-Accept actually
reaching the outbound list.

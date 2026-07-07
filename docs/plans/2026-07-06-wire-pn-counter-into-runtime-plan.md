# Plan: Wire `pn_counter_kernel` into the runtime

**Date:** 2026-07-06
**Status:** ✅ Complete (this pass). Documented here for the record and as the
template the other two wiring plans mirror.
**Repo:** `claude-workspace/watershed`
**Companion docs:**
`2026-07-03-pn-counter-kernel-plan.md` (the kernel itself),
`2026-07-06-wire-pact-map-into-runtime-plan.md`,
`2026-07-06-wire-ordered-collection-into-runtime-plan.md`,
`2026-07-06-runtime-kernel-wiring-order.md` (sequencing).

## Context

`pn_counter_kernel` is a PN-counter (signed increment/decrement),
replica-identified like `or_map`/`or_set`. It has the full optimistic
lifecycle (`new`, `from_summary`, `apply_remote`, `ack_local`, `rollback`,
`apply_stashed_op`, `summary`) and complete kernel unit + fuzz tests, but was
never referenced outside its own file. This slice wired it end-to-end through
both runtimes.

Because it is a **plain optimistic kernel with no reactions and no
disconnect semantics**, it fit the existing "add a kernel" checklist with zero
new infrastructure. It is therefore the canonical template for the mechanical
parts of the two harder kernels.

## What shipped

1. **`pn_counter_kernel.gleam`** — added
   `from_sequenced(state: PNCounter, replica_id: ReplicaId) -> PnCounterState`
   (mirrors `or_set_kernel`), so a snapshot holding a bare `PNCounter` can be
   reconstructed into kernel state on attach/bootstrap.
2. **`wire.gleam`** — `pub const channel_type_pn_counter = "pnCounter"`.
3. **`channel.gleam`** — added the `PnCounter*` variant to every parallel sum
   (`ChannelType`, `ChannelInit`, `ChannelState`, `ChannelOp`, `ChannelEvent`,
   `Snapshot` as `PnCounterSnapshot(state: PNCounter)`, `LocalOpMeta` as
   `PnCounterMeta(message_id: Int)`) and extended every dispatch fn:
   `type_to_string`, `type_from_string`, `init_type`, `channel_type`,
   `snapshot_type`, `new`, `from_snapshot`, `snapshot`, `attach_snapshot`,
   `apply_remote`, `ack_local`, `same_shape`, `same_snapshot`,
   `handle_addresses`, `encode_snapshot`, `snapshot_decoder`
   (+ `pn_counter_snapshot_decoder`).
   - **Gotcha (recorded for the other kernels):** adding a `LocalOpMeta`
     variant breaks the exhaustive `NoMeta | CounterMeta(_) | ...` lists in the
     `or_set`/`g_set`/`two_p_set` ack arms — each needs `PnCounterMeta(_)`
     appended. Compiler-guided.
4. **`wire/ops.gleam`** — op codec. Wire shape:
   `{type:"pnCounterUpdate", amount:Int, delta:<json-string of PNCounter>}`.
   Added `encode_pn_counter_envelope`/`decode_pn_counter_envelope` and the
   delta helpers; extended `encode_channel_op` + `channel_op_decoder`.
5. **`runtime_core.gleam`** — `pub fn pn_counter_update`, `fn locate_pn_counter`,
   `fn tag_pn_counter_events`, `pub fn pn_counter_value`.
6. **`runtime.gleam`** — `Msg` variants `CreatePnCounter`, `UpdatePnCounter`,
   `GetPnCounterValue` + handlers + `InitPnCounter` import.
7. **`runtime_js.gleam`** — `create_pn_counter`, `pn_counter_update`,
   `pn_counter_value`.
8. **Tests** — `pn_counter_channel_test.gleam` (5 tests: detached update/emit,
   snapshot round-trip, channel-type round-trip, attach preserves optimistic
   value) + `wire_test.gleam` op envelope round-trips (increment + decrement).

## Validation

- `gleam build` (erlang) + `gleam build --target javascript` — both green.
- `gleam test` — 546 pass (was 544; +net new tests).
- Deep fuzz already covered at the kernel level by the existing
  `pn_counter_model` + `pn_counter_fuzz_test`; no runtime-fuzz layer exists, so
  no new fuzz work was required.

## Lessons that feed the harder two

- The mechanical "add a kernel" checklist is well-trodden and low-risk for a
  plain optimistic kernel.
- The runtime has **no reaction-submit path** other than json0's
  `take_outbound`/`collect_released_ops`, and **no client-leave/disconnect
  path at all**. `pn_counter` needed neither; `pact_map` needs the former and
  `ordered_collection` needs the latter (see their plans).

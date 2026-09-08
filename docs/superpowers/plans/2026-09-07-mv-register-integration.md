# MV Register Integration Implementation Plan

> **For agentic workers:** Use `executing-plans` to implement this plan task by task. Execute directly, without subagents. Steps use checkbox (`- [ ]`) syntax for tracking. This document is a plan, not an implementation record.

**Goal:** Add a string-valued MV-register channel to the sequenced and CRDT runtimes, expose its typed APIs and Lustre effects, and demonstrate concurrent writes and causal resolution on the website.

**Architecture:** Wrap the existing `lattice_registers/mv_register` implementation in a Watershed kernel. Reuse channel dispatch, snapshots, the sequenced runtime, CRDT anti-entropy, and the website's shared demo. Keep causal metadata in operations and storage; derive visible values from that state.

**Tech Stack:** Gleam on Erlang and JavaScript; existing `lattice_registers`, `lattice_core`, startest, qcheck, gleeunit, Astro, Node test runner, and puppeteer-core dependencies. No new dependencies.

**Spec:** [Lattice CRDT integration, Plan 1](../../plans/2026-07-04-lattice-crdt-integration-plan.md#plan-1-mv-register), revised by the decisions below. That July outline predates the CRDT runtime and names obsolete runtime and wire files. This document is the execution plan for its remaining MV-register work; the G-set and 2P-set work is already shipped.

**Planning baseline:** `ce9be06` on `main`, 2026-09-07. Recheck paths and signatures at execution time. The scheduler correction in that commit is a prerequisite for deterministic `ensure_*` tests.

## Global constraints

- Implement only `MVRegister(String)`. Do not add generic JSON values, keyed registers, deletion, a special resolution protocol, or an application plug-in system.
- Cover the sequenced runtime on both targets and the JavaScript CRDT facade. The CRDT core remains dual-target; this does not add a BEAM P2P transport or BEAM component execution host.
- Use `src/watershed/runtime.gleam` for the JavaScript runtime, `runtime_beam.gleam` for the BEAM actor, and `wire/op.gleam` for channel operation codecs. Do not recreate `runtime_js.gleam`.
- Preserve existing API conventions, typed errors, FIFO acknowledgements, LIFO rollback, detached attachment, and generation/lifetime guards. Do not add success-shaped defaults to new branches.
- Keep the current summary and CRDT envelope versions. Add a channel kind within those envelopes; older clients must reject an unsupported kind, not reinterpret it. Do not change existing kinds' encodings or digests.
- Use the existing replica identity allocation. Rebrand loaded state with the receiving replica's identity, never the snapshot writer's identity.
- Read `AGENTS.md` and `.github/instructions/website-copy.instructions.md` before edits. STE applies to Gleam comments and error strings, not website or Markdown prose. Preserve the site's protected names.
- Source-backed website code must come from markers and `website/snippets.json`, through `sourceSnippet` and `SnippetBlock`. Never commit or edit the generated manifest; never introduce `?raw` source imports.
- Run the smallest relevant existing commands during each task. Add regressions to the existing runners, not new testing infrastructure. Commit each completed task on `main`; do not add Co-authored-by trailers.
- Do not expand this work into summary version history, GCounter integration, a new example app, or a general demo framework.

## Design decisions

### One cell, with causal alternatives

Public name: `MvRegister`. Schema marker: `schema.MvRegisterChannel`.
Wire channel type: `"mv-register"`. Operation type: `"mvRegisterSet"`.
Website view and anchor: `"mv-register"`.

The register starts empty. A local `set` replaces everything that author has
observed. Concurrent writes survive together; a write made after observing both
replaces both. Server order alone does not select a winner. A third, unseen
concurrent write can survive an attempted resolution.

`values` returns strings sorted with `gleam/string.compare`, retaining duplicate
strings from distinct concurrent writes. Do not silently deduplicate them:
`["same", "same"]` represents two surviving writes. Sorting is for a stable
public presentation, not a replacement for causal state.

There is no `resolve_conflict` or `clear` operation. Resolution is another
ordinary `set`; `set("")` writes an empty string and does not empty the register.
This differs from `RegisterCollection`, which offers sequenced per-owner
versions and read policies, and from `PactMap`, which waits for protocol
acknowledgements.

### State, events, and persistence

Use the PN-counter kernel's state split: local replica identity, confirmed
`sequenced` state, cached `optimistic` state, FIFO pending operations, and a
monotonic local message ID. Each operation carries its original MV-register
delta, including the **full version vector** that records what it supersedes.
Do not regenerate a delta from its text during resend or stash replay.

`ValuesChanged(values: List(String))` reports a change to the sorted visible
list. A same-text write to a singleton register still creates a fresh causal
write and an outbound operation, even when it emits no visible-value event.
A correct ack emits no second event. Rollback and remote merge compare before
and after values instead of inventing an event for a no-op.

Summaries contain confirmed state only. Detached attachment captures optimistic
state. CRDT/P2P edits confirm immediately, without a pending ack queue. Snapshot
reload must preserve the full version vector and surviving tagged entries.
Loading under a new writer uses `merge(new(receiver_id), decoded_state)`.

The digest projection removes only `state.replica_id`, the local authoring
identity, and orders the set-shaped `state.entries` array. It retains entry
tags and the entire `state.vclock`. Equal displayed values are not sufficient
for equal digests or a decision to skip persistence/anti-entropy.

### Wire contract

Use the existing PN-counter stringified-delta convention:

```json
{
  "type": "mvRegisterSet",
  "value": "raise crest",
  "delta": "<JSON string containing the lattice mv_register v1 envelope>"
}
```

The enclosing document operation retains the existing `address` and `contents`
shape. `Set(value, delta)` must describe one write: the delta has exactly one
tagged entry with that value. An ordinary snapshot may have zero or more entries.
`channel.encode_snapshot` emits the lattice JSON object, not an extra string
layer; its decoder follows the other lattice snapshot decoders.

Keep one shared decoder in `mv_register_kernel` for kernel reload, snapshots,
and wire deltas. Reuse `mv_register.from_json` for the CRDT representation, with
envelope validation for malformed causal metadata it does not reject itself:
negative vector counters, duplicate entry tags, and entry counters that are
nonpositive or exceed their vector component. Accept an empty register and
causal vectors containing retired writes. A malformed state returns an error;
it must never become an empty register. Apply the singleton/value check only
to wire operations, not snapshots.

### Website delivery

Add MV register to the existing maps family and shared picker. Keep the
`/structures/maps` URL; explain that the family includes a conflict-preserving
cell alongside keyed maps. Add `/mv-register` as a focused sheet using the same
`Demo` component with `views={["mv-register"]}`, not a second implementation.
Leave the homepage's focused SharedMap demo unchanged.

The demonstration is a **revision slate**: baseline `"Survey datum"`, concurrent
notes `"raise crest"` and `"arm pump"`, then `"raise crest + arm pump"` written
after a client has observed both. Show confirmed and optimistic alternatives
separately. Two confirmed alternatives mean **converged with a conflict**, not
"still waiting for the network."

Use the existing latency, link-cut, redelivery, reset, flow, and field-notes
controls. Reset creates a fresh demonstration epoch and baseline; it is not a
register deletion API. Reject old queued work from the previous epoch.

## File map

| Area | Create | Modify / reference |
|---|---|---|
| Kernel | `src/watershed/mv_register_kernel.gleam`, `test/watershed/mv_register_kernel_test.gleam` | Reference `pn_counter_kernel.gleam`; read installed `lattice_registers/mv_register.gleam` and `lattice_core/version_vector.gleam` |
| Channel and wire | `test/watershed/mv_register_channel_test.gleam` | `src/watershed/channel.gleam`, `wire.gleam`, `wire/op.gleam`, `schema.gleam`, `test/watershed/wire_test.gleam` |
| Sequenced runtime | `test/watershed/sluice/mv_register_test.gleam`, `test/watershed/sluice/mv_register_js_test.gleam` | `runtime_core.gleam`, `runtime.gleam`, `runtime_beam.gleam`, `src/watershed.gleam`, `src/watershed_beam.gleam`, `test/watershed/facade_parity_test.gleam` |
| CRDT runtime | MV cases in existing suites | `src/watershed/p2p.gleam`, `crdt_core.gleam`, `crdt_js.gleam`; `test/watershed/p2p_test.gleam`, `crdt_core_test.gleam`, `crdt_wire_test.gleam`, `crdt_js_test.gleam`, `persist_js_test.gleam`, `crdt_relay_lifecycle_test.gleam` |
| Fuzz model | `test/watershed/fuzz/mv_register_model.gleam`, `test/watershed/mv_register_fuzz_test.gleam` | Reference `test/watershed/fuzz/pn_counter_model.gleam`, `kernel_fuzz.gleam`, and `README.md` |
| Lustre | `watershed_lustre/test/watershed_lustre/mv_register_test.gleam` | `watershed_lustre/src/watershed_lustre.gleam`, `watershed_lustre/src/watershed_lustre/crdt.gleam`; reference `watershed_lustre/test/watershed_lustre/crdt_test.gleam` and `claims_test.gleam` |
| Interactive website | `website/src/pages/mv-register.astro`, `website/scripts/mv-register-demo.test.mjs` | `website/src/components/Demo.astro`, `website/src/components/StructureCategory.astro`, `website/src/scripts/demo.js`, `website/src/scripts/tutorial.js`, `website/src/data/structures.ts`, `website/package.json`; reference `demo/boot.test.mjs`, `demo/sequencer.ts`, `demo/controls.ts`, `smoke/cdp.mjs` |
| Snippets and docs | `tools/website-samples/src/website_samples/mv_register_sample.gleam` | `website/snippets.json`, `website/src/data/standalone-snippets.ts`, its tests and snippet inventory tests, `website/src/pages/runtime/p2p.astro`, `README.md`, `watershed_lustre/README.md`, `docs/demo-ideas.md`, the July integration plan |

Adding a union variant also requires exhaustive branches in existing subscriber
filters, test renderers, and mismatch handlers. Use compiler diagnostics plus a
repository-wide inventory of `PnCounter` branches to find them. Keep those
mechanical updates in the commit that introduces the variant; do not hide them
behind catch-all patterns. No new protocol-specific handling belongs in the
opaque Node relay.

## Task 1: Implement the MV-register kernel and causal contract

**Consumes:** `mv_register.new`, `set_with_delta`, `value`, `merge`, `to_json`,
and `from_json`; the sibling kernel's ack/rollback pattern.

**Produces:** `MvRegisterState`, `PendingOp`, `MvRegisterOperation`,
`MvRegisterEvent`, `KernelError`, and these interfaces:

```gleam
pub type MvRegisterOperation {
  Set(value: String, delta: MVRegister(String))
}

pub type MvRegisterEvent {
  ValuesChanged(values: List(String))
}
```

| Function | Result |
|---|---|
| `new(ReplicaId)` | `MvRegisterState` |
| `values(MvRegisterState)`, `sequenced_values(MvRegisterState)` | `List(String)` |
| `set(MvRegisterState, String)` | `#(MvRegisterState, List(MvRegisterEvent), MvRegisterOperation, Int)` |
| `apply_remote(MvRegisterState, MvRegisterOperation)` | `#(MvRegisterState, List(MvRegisterEvent))` |
| `ack_local(MvRegisterState, MvRegisterOperation)` | `Result(MvRegisterState, KernelError)` |
| `ack_local_with_message_id(MvRegisterState, MvRegisterOperation, Int)` | `Result(MvRegisterState, KernelError)` |
| `rollback(MvRegisterState, MvRegisterOperation, Int)` | `Result(#(MvRegisterState, List(MvRegisterEvent)), KernelError)` |
| `apply_stashed_operation(MvRegisterState, MvRegisterOperation)` | Same tuple as `set`, preserving the input operation |
| `p2p_set(MvRegisterState, String)` | `#(MvRegisterState, List(MvRegisterEvent), MvRegisterOperation)` |
| `p2p_merge(MvRegisterState, MVRegister(String))` | `#(MvRegisterState, List(MvRegisterEvent))` |
| `summary(MvRegisterState)` | `json.Json` |
| `decode_crdt(String)` | `Result(MVRegister(String), json.DecodeError)` |
| `from_summary(String, ReplicaId)` | `Result(MvRegisterState, json.DecodeError)` |
| `from_sequenced(MVRegister(String), ReplicaId)` | `MvRegisterState` |
| `check_cache_coherence(MvRegisterState)` | `Result(Nil, String)` |

- [ ] Read the installed lattice implementation in full. Confirm that `set_with_delta` carries the full new vector and that `merge(a, b)` retains `a`'s writer identity. Do not duplicate its merge algorithm.
- [ ] Start with a failing kernel regression using real kernels:

```gleam
import lattice_core/replica_id
import startest/expect
import watershed/mv_register_kernel as mv

pub fn concurrent_writes_survive_until_observed_resolution_test() -> Nil {
  let #(a, _, write_a, id_a) = mv.set(mv.new(replica_id.new("a")), "raise crest")
  let #(b, _, write_b, id_b) = mv.set(mv.new(replica_id.new("b")), "arm pump")
  let assert Ok(a) = mv.ack_local_with_message_id(a, write_a, id_a)
  let assert Ok(b) = mv.ack_local_with_message_id(b, write_b, id_b)
  let #(a, _) = mv.apply_remote(a, write_b)
  let #(b, _) = mv.apply_remote(b, write_a)
  mv.values(a) |> expect.to_equal(["arm pump", "raise crest"])
  mv.values(b) |> expect.to_equal(["arm pump", "raise crest"])

  let #(a, _, resolved, resolved_id) = mv.set(a, "raise crest + arm pump")
  let assert Ok(a) = mv.ack_local_with_message_id(a, resolved, resolved_id)
  let #(b, _) = mv.apply_remote(b, resolved)
  mv.values(a) |> expect.to_equal(["raise crest + arm pump"])
  mv.values(b) |> expect.to_equal(["raise crest + arm pump"])
}
```

- [ ] Run `gleam test --target javascript -- mv_register_kernel` before implementation. Missing module/API is the initial red result; subsequent regressions must fail on their stated behavior.
- [ ] Implement optimistic writes and remote joins, then FIFO ack, LIFO rollback, stash replay, snapshots, and ack-free operations. Store `PendingOp(operation, message_id)` so identity checks include the full delta and text.
- [ ] Add table-driven regressions for empty state, empty text, Unicode sorting, sequential supersession, duplicate delivery, concurrent identical text, and same-text singleton writes that change causal state without a visible event.
- [ ] Exercise pending-local plus remote-write merges; ack the local write without a second event. Reject wrong message IDs, wrong deltas with the same text, out-of-order acks, non-newest rollbacks, and ack/rollback on empty queues.
- [ ] Roll back a never-delivered local write, then write again and deliver it. Check cache coherence and convergence. Separately replay the original stashed delta after summary load; do not create a new causal write.
- [ ] Prove that a partial resolution leaves an unseen third writer's value alive. Prove that replay of a superseded delta cannot resurrect it.
- [ ] Test snapshot rebranding: load A's summary as B, make concurrent A/B writes, and retain both. Check that snapshots omit pending edits while detached-state capture can retain them.
- [ ] Test invalid envelopes, versions, types, negative vector counters, duplicate tags, out-of-vector tags, and valid empty/retired causal states through the shared decoder.
- [ ] Run the kernel selector on both targets and format the new files. Commit `feat: add causal MV-register kernel`.

**Acceptance:** The kernel preserves concurrent alternatives and original causal
operations across ack, rollback, reload, and replay without an independent merge
implementation or a value-only snapshot.

## Task 2: Wire channel kinds, snapshots, operations, and sequenced core

**Consumes:** Task 1's kernel.

**Produces:** `MvRegisterChannel`, `InitMvRegister`, `MvRegisterState`,
`MvRegisterOperation`, `MvRegisterEdit(value)`, `MvRegisterEvent`,
`MvRegisterSnapshot(MVRegister(String))`, and `MvRegisterMeta(message_id)` in
their corresponding channel unions; `wire.channel_type_mv_register`;
`schema.MvRegisterChannel`.

```gleam
// runtime_core.gleam
pub fn mv_register_set(core: Core, address: String, value: String)
  -> Result(
    #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
    CoreError,
  )

pub fn mv_register_values(core: Core, address: String)
  -> Result(List(String), Nil)
```

- [ ] Copy only the connection fixture from `pn_counter_channel_test.gleam` into the new channel test. Add failing detached-write, attach, attached-outbound, read, snapshot, and channel-type round-trip cases using the MV names above.
- [ ] Add operation encode/decode tests in `wire_test.gleam`, including the literal `"mvRegisterSet"` tag, text, and stringified delta. Reject zero-entry/multi-entry deltas, mismatched text, malformed metadata, and operations for the wrong channel.
- [ ] Register the type, initializer, state, snapshot, edit, event, and local metadata throughout `channel.gleam`. Implement `new`, `from_snapshot`, `snapshot`, `attach_snapshot`, remote application, ack, `same_shape`, `same_snapshot`, handle discovery, and encode/decode branches. MV strings contain no nested channel handles.
- [ ] Wire `p2p_edit` and `p2p_merge` to the tested kernel functions, but leave `supports_p2p(MvRegisterChannel)` false until Task 4 provides digest support. Keep `p2p.validate` refusing it at this checkpoint.
- [ ] Add `encode_mv_register_operation`, `encode_mv_register_envelope`, `mv_register_operation_decoder`, `mv_register_envelope_decoder`, and `decode_mv_register_envelope` beside the PN-counter codecs. Route generic operation dispatch through them.
- [ ] Implement the sequenced core's locate/tag/read/mutate path. Detached sets change only local state; attachment sends the optimistic snapshot; attached sets use `stamp_attached` with `MvRegisterMeta`.
- [ ] Follow the actual generic reconnect/resubmit path. Preserve the original delta, reference metadata, and message identity where the existing path requires it. Do not introduce a second resend queue.
- [ ] Compile both targets and update exhaustive matches in runtime/facade filters and test renderers. New mismatched variants must follow the existing typed-error path.
- [ ] Prove two concurrent writes survive both server orders; a causally later write replaces both; duplicate delivery and a stale echo after reload do not resurrect old text. Verify summary/bootstrap excludes pending state and applies post-checkpoint writes.
- [ ] Run `gleam test --target erlang -- mv_register wire runtime_core` and `gleam test --target javascript -- mv_register wire runtime_core`. Commit `feat: wire MV-register channels and operations`.

**Acceptance:** The sequenced core can create, attach, mutate, encode, reload,
acknowledge, and resubmit the channel. Existing channels retain their wire format
and error behavior.

## Task 3: Expose typed JavaScript and BEAM facades

**Consumes:** Task 2's channel/core interfaces and the existing runtime scheduler.

**Produces:** An opaque `MvRegister` handle in each facade and the following
surface. `Field` below means `ChannelField(s, schema.MvRegisterChannel)`;
these are signature descriptions, not new type aliases.

| API | JavaScript (`watershed`) | BEAM (`watershed_beam`) |
|---|---|---|
| `create_mv_register(document)` | `Result(MvRegister, String)` | Same |
| `mv_register_handle_of(register)` | `Json` | Same |
| `resolve_mv_register(document, handle)` | `Result(MvRegister, String)` | Same |
| `set_mv_register_field(map, field, register)` | `Nil` | Same |
| `resolve_mv_register_field(document, map, field)` | `Result(Option(MvRegister), String)` | Same |
| `ensure_mv_register(document, map, field, done)` | Callback receives `Result(MvRegister, String)` | No callback; returns that result |
| `mv_register_set(register, value)` | `Nil` | Same |
| `mv_register_values(register)` | `Result(List(String), Nil)` | Same |
| `subscribe_mv_register(register, handler)` | Returns `SubscriptionToken` | No handler; returns `Subject(MvRegisterEvent)` |

- [ ] Add failing public two-client tests in the target-specific sluice files. Create/share/resolve a register through a typed field, subscribe, author concurrent writes before delivery, settle, then resolve through an observed write.
- [ ] Keep the existing cross-target facade export comparison passing as both facades grow. Add the explicit MV kind row in Task 5 together with its Lustre bindings: `kinds()` drives all three facades, and `lustre_gaps` must stay empty.
- [ ] Add JavaScript runtime `create_mv_register`, `mv_register_set`, and `mv_register_values` via existing create/edit/read helpers.
- [ ] Add BEAM actor messages `CreateMvRegister`, `SetMvRegister`, and `GetMvRegisterValues` using the reply and mutation conventions of the PN counter. Forward to the same pure core.
- [ ] Add opaque facade handles, type-checked resolution, typed fields, initialization, mutation/read forwarding, and narrowed subscriptions. Reuse shared `ensure_channel`; never poll with a separate real-time FFI.
- [ ] In JS readiness tests use `sluice_js.settle` for frames and `sluice_js.advance` for timers. In BEAM use the existing worker/reply plus `settle_until` pattern, since a blocking ensure cannot acknowledge its own pending writes without another process driving delivery.
- [ ] Cover fresh ensure, adopting an existing register, simultaneous first-use creation, wrong-kind handles, unsubscribe, ack event silence, summary-loaded state, disconnected local edits, and reconnect resubmission. Concurrent ensure may choose one handle by the map field's existing LWW rule; it does not merge two separately created channels.
- [ ] Run `gleam test --target erlang -- mv_register ensure facade_parity` and `gleam test --target javascript -- mv_register ensure facade_parity`. Commit `feat: expose MV-register typed facades`.

**Acceptance:** Public users can exercise the register without importing a
kernel. Readiness, error shapes, and subscriptions match sibling channels on
both targets.

## Task 4: Enable CRDT/P2P operation, digest repair, and persistence

**Consumes:** Ack-free kernel operations, typed channel variants, existing CRDT
snapshot/anti-entropy machinery.

**Produces:**

```gleam
// p2p.gleam
pub fn mv_register_root() -> CrdtKind(schema.MvRegisterChannel)

// crdt_js.gleam
pub fn mv_register_set(
  handle: Handle(schema.MvRegisterChannel),
  value: String,
) -> Result(Nil, P2pError)

pub fn mv_register_values(
  handle: Handle(schema.MvRegisterChannel),
) -> Result(List(String), P2pError)

pub fn subscribe_mv_register(
  handle: Handle(schema.MvRegisterChannel),
  handler: fn(mv_register_kernel.MvRegisterEvent) -> Nil,
) -> Subscription
```

- [ ] Add failing `p2p_test` eligibility cases and CRDT core tests with `root: channel.InitMvRegister`. Use real `crdt_core.edit` and `crdt_sim` delivery, not a replacement merge.
- [ ] Add snapshot-to-initializer support in `crdt_core`, enable `channel.supports_p2p`, and provide `p2p.mv_register_root`.
- [ ] Extend `merge_relevant` with the lattice `"mv_register"` envelope. Use existing helpers to remove only the writer cursor and sort entries:

```gleam
"mv_register" ->
  map_member(value, "state", fn(state) {
    state
    |> without(["replica_id"])
    |> map_member("entries", ordered)
  })
```

- [ ] Prove merged A/B documents have equal digests despite distinct writer IDs and insertion order. Pin the projection's bytes on both compile targets. Preserve all existing digest fixtures.
- [ ] Add a pair with equal visible values but different causal history and assert different digests before repair. After repair assert equal digests and correct behavior when an old, superseded delta arrives. Include a merge that updates causal state without emitting `ValuesChanged`.
- [ ] Add the typed CRDT facade methods using existing `mutate`, `read`, and narrowed-subscription helpers. Return the existing error for closed documents and wrong-kind handles; never substitute `[]` for a failure.
- [ ] Use the fake-RTC suite to exercise concurrent writes, a dropped delta repaired by anti-entropy, a three-peer sparse mesh, duplicate/out-of-order delivery, late joining, and local same-value edits. Ensure sync scheduling depends on state change, not only event count.
- [ ] Add an MV snapshot save/load/merge case to `persist_js_test`: save a conflict, load under a fresh writer, edit offline, merge with a peer, and confirm the original causal context still suppresses old values. Exercise a causal-only change so an event-less merge does not disappear from the next saved snapshot.
- [ ] Add one generic relay lifecycle case carrying an MV register through checkpoint/replay. The relay remains opaque; no MV-specific merge code or new endpoint belongs in `tools/relay`.
- [ ] Run `gleam test --target javascript -- p2p crdt persist` and `gleam test --target erlang -- p2p crdt_core crdt_wire`. Commit `feat: support MV registers in CRDT documents`.

**Acceptance:** Partitioned replicas preserve alternatives, late peers and
restored snapshots converge on causal state, and repair works even when the UI
has no new text to display.

## Task 5: Add Lustre effects and lock facade coverage

**Consumes:** The public handles and events from Tasks 3 and 4.

**Produces:** `watershed_lustre.ensure_mv_register` and
`watershed_lustre.subscribe_mv_register`, plus
`watershed_lustre/crdt.subscribe_mv_register`. Use the existing generic
`crdt.perform` for writes and `crdt.read` for reads; do not add duplicate
per-operation effect wrappers.

```gleam
// Sequenced binding
pub fn ensure_mv_register(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MvRegisterChannel),
  to_msg to_msg: fn(Result(MvRegister, String)) -> msg,
) -> Effect(msg)

pub fn subscribe_mv_register(
  register: MvRegister,
  to_msg to_msg: fn(mv_register_kernel.MvRegisterEvent) -> msg,
) -> Effect(msg)

// CRDT binding
pub fn subscribe_mv_register(
  handle: Handle(schema.MvRegisterChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(mv_register_kernel.MvRegisterEvent) -> msg,
) -> Effect(msg)
```

- [ ] Add failing tests in `watershed_lustre/test/watershed_lustre/mv_register_test.gleam`, following `crdt_test.gleam` and `claims_test.gleam`. Async gleeunit cases return `Promise(Nil)` and flush deferred delivery with the existing promise pattern. Keep the package's `main` entrypoint unchanged. Constructing an effect must not mutate or subscribe; performing it must do the work, with dispatch deferred through `queue_microtask`.
- [ ] Implement the sequenced wrappers beside `ensure_pn_counter` and `subscribe_pn_counter`. Use the existing CRDT subscription helper for the narrowed binding.
- [ ] Check that success and failure results reach the application unchanged. Test local and remote events, no duplicate event on ack, and CRDT subscription-token delivery and unsubscribe.
- [ ] Add the new `Kind("mv_register", ...)` row in `facade_parity_test.gleam`: lifecycle names `create_mv_register`, `ensure_mv_register`, `resolve_mv_register`, `resolve_mv_register_field`, `set_mv_register_field`, `mv_register_handle_of`; operations `mv_register_set`, `mv_register_values`; subscription `subscribe_mv_register`. Keep `lustre_gaps` empty. The source-inventory check supplements the behavioral tests; it does not replace them.
- [ ] Run `(cd watershed_lustre && gleam test)` and `gleam test --target javascript -- facade_parity`. Commit `feat: add MV-register Lustre effects`.

**Acceptance:** Lustre users can bootstrap and observe the sequenced register,
or use CRDT handles with existing generic effects, without introducing
synchronous dispatch into an update.

## Task 6: Add a causal fuzz model

**Consumes:** The tested kernel and existing `KernelModel`/qcheck harness.

**Produces:** `mv_register_model.model()` and `mv_register_fuzz_test.gleam`,
using the harness's existing seeded, replayable scripts.

- [ ] Define generated commands as text plus an optional routed delta. Populate the delta only when the real kernel submits it; preserve it on stash/replay. Fail loudly if a routed command lacks its delta.
- [ ] Implement an independent oracle over tagged writes and their observed version vectors. For the unique writes present in the log, keep a write iff no different write's causal context dominates its tag. Sort the surviving texts, preserving duplicates. Do not call `mv_register.merge` or the production projection to calculate the expected result.
- [ ] Start with these deterministic scripts as regressions: A/B concurrent writes; A/B conflict then A resolves; A resolves without seeing C; duplicate replay after resolution; rollback of an unrouted local write followed by a new write; snapshot join with pending local edits; identical text under different tags.
- [ ] Enable only capabilities the model implements. Use the existing cache-coherence hook after transitions, and compare both visible values and retained causal state at convergence.
- [ ] Follow `pn_counter_fuzz_test.gleam` for fixed seeds and generated runs. Add the model to the fuzz README's inventory; do not add another runner.
- [ ] Run `gleam test --target erlang -- mv_register_fuzz` and `gleam test --target javascript -- mv_register_fuzz`. Then run `FUZZ_ITERATIONS=5000 gleam test --target erlang -- mv_register_fuzz` and `FUZZ_ITERATIONS=5000 gleam test --target javascript -- mv_register_fuzz` before accepting the model. Commit `test: fuzz MV-register causal convergence`.

**Acceptance:** The oracle can catch a dropped alternative, incorrect
supersession, delta regeneration, and stale-value resurrection without sharing
the implementation's merge logic.

## Task 7: Add the website's conflict and resolution demonstrations

**Consumes:** The compiled kernel, existing `Demo` component, sequencer, latency
controls, field notes, and catalog-driven structure pages.

**Produces:** A shared `"mv-register"` view on `/structures/maps` and a focused
`/mv-register` page using that same view.

- [ ] Extend the existing `demo/boot.test.mjs` with baseline load/rebrand and concurrent-write/resolution cases against the compiled kernel. Add a browser regression at `website/scripts/mv-register-demo.test.mjs` using Node's test runner and the installed puppeteer-core.
- [ ] For the browser test, accept a `WATERSHED_WEBSITE_URL` (default `http://127.0.0.1:4321`). Import `findBrowser` from `../../smoke/cdp.mjs`; it honors `WATERSHED_CHROME`. Pass the discovered path to puppeteer-core rather than adding a browser installer. Absence of Chromium is an explicit failure for this opt-in command, not a success.
- [ ] Add the baseline, picker entry, merge-rule text, and per-client value controls in `Demo.astro`. Use `data-mv-register-values`, `data-mv-register-confirmed`, `data-mv-register-input`, `data-mv-register-write`, and `data-mv-register-resolve` selectors. Render arbitrary strings with `textContent`, not interpolated HTML.
- [ ] Wire initialization, optimistic write, local ack metadata, remote delivery, rendering, pending detection, convergence, redelivery, link-cut/resubmit, race, and reset in `demo.js`. Reuse existing sequencer callbacks; keep the actual operation from `mv_register_kernel.set`. Do not implement an MV-register in JavaScript.
- [ ] Make the race button author A's and B's writes before either delivery. The resolve button writes from a client after it has observed the conflict; do not merge strings or select a winner in the delivery handler.
- [ ] Keep confirmed alternatives in ink and optimistic state in magenta. Distinguish "converged with 2 alternatives" from queued delivery. A singleton result may still be locally pending.
- [ ] Enable duplicate redelivery only after an MV delta has sequenced. Re-deliver the original delta, including after a resolving write, and show no resurrected text.
- [ ] Give reset a fresh MV epoch, clear local pending state, and drop delayed/held MV work from the old epoch. Reuse the existing per-kind reset pattern rather than changing reset behavior for other structures.
- [ ] Add field-note captions and selectors in `tutorial.js` and the matching `FIELD_FLASH` set. Update race/reset descriptions and accessible labels. Respect reduced motion and keyboard navigation.
- [ ] Add the `MvRegister` catalog entry to the maps family with `onHomepage: true`; it then participates in the existing field sheets. Do not set `demoHref` on this entry, because `StructureCategory` excludes such entries from the shared picker. In `StructureCategory.astro`, add an `s.id === "mv-register"` link to `/mv-register` beside the existing structure-specific demo links.
- [ ] Create the focused page with the existing `Sheet` layout and `<Demo views={["mv-register"]} showPicker={false} />`. Do not instantiate two shared demos on the same page; the shared rig uses document-level selectors.
- [ ] Add `test:mv-register-demo` to `website/package.json` as `node --test scripts/mv-register-demo.test.mjs`. Keep this live-browser command separate from `just test`; run it against the built site in the final gate.
- [ ] Browser assertions: controls enable after boot; race settles to `["arm pump", "raise crest"]` on all three clients; resolution leaves one combined value; old-delta redelivery does not resurrect alternatives; link-cut edits converge on restore; reset during pending work discards the old epoch; picker changes preserve state; no uncaught page errors occur.
- [ ] Use DOM state predicates with bounded timeouts, not arbitrary sleeps. Exercise both `/structures/maps` and `/mv-register`, including reduced-motion mode and keyboard controls.
- [ ] Run `pnpm --dir website test:demo-boot` and `pnpm --dir website build`. Start `pnpm --dir website preview --host 127.0.0.1 --port 4321`, confirm `/mv-register` responds, and run `pnpm --dir website test:mv-register-demo`. Stop the preview process started for this task. Commit `feat(website): demonstrate MV-register conflicts`.

**Acceptance:** A reader can create a conflict, see all clients agree on that
conflict, resolve the alternatives, and verify that replay does not undo the
resolution. Both pages run the same compiled kernel.

## Task 8: Publish source-backed documentation and complete the integration

**Consumes:** The finished APIs and demonstrations. Do not describe planned
support as available before the preceding tasks land.

**Produces:** Compiled website examples, accurate capability guidance, and
updated plan/backlog status.

- [ ] Add `website_samples/mv_register_sample.gleam` with a typed field, a sequenced ensure/write/read example, and a CRDT root/write/read example. Make the exported sample functions take real typed arguments so `gleam build` checks their signatures.
- [ ] Mark the source ranges `mv-register-sequenced` and `mv-register-p2p`; declare them in `website/snippets.json` and load them through `standalone-snippets.ts`. Quote the actual concurrent-resolution regression under a third marker, `mv-register-concurrent-resolution`, so the focused page's merge example is executable source.
- [ ] Render these samples with `SnippetBlock` on `/mv-register`. Explain the list return value, duplicate strings from distinct writes, ordinary-set resolution, unseen writers, empty-string behavior, and readiness before seeding. Link to `/structures/maps#mv-register` and contrast `RegisterCollection` and `PactMap` without calling acknowledgements user approval.
- [ ] Update the maps family lede/rules and the P2P eligibility list at `website/src/pages/runtime/p2p.astro`. Explain that full causal metadata persists even when no visible-value event fires. Do not broaden unrelated persistence documentation.
- [ ] Update the root README's channel/API inventory and the Lustre README's ensure/subscription and CRDT sections. Show CRDT mutation as a thunk passed to `crdt.perform`, not an eager mutation during update.
- [ ] Update snippet registry and inventory expectations to account for the three new source-backed snippets. Keep existing drift gates meaningful; do not allowlist handwritten Gleam to avoid compilation.
- [ ] Update `docs/demo-ideas.md` and the July integration plan to mark MV register shipped only after the final gates. Link to this execution record. Do not mark GCounter, RFC Room, BEAM host parity, or summary version history complete.
- [ ] Run `just snippets`, `(cd tools/website-samples && gleam build)`, the website snippet/drift/copy commands through `just _test-website-snippets`, and `pnpm --dir website build`. Confirm generated files remain ignored.
- [ ] Run final `just test`, `just build`, and `just lint`. Run the opt-in MV browser command against the freshly built site and the targeted deep-fuzz commands from Task 6. Stop only processes started for this work.
- [ ] Record the implementation commits and outcomes below. State any unexecuted browser or live-service gate plainly rather than claiming full completion. Commit `docs: explain MV-register conflicts and resolution`.

**Acceptance:** Website samples compile against the public APIs, all claimed
runtime support is implemented, the demos expose the documented behavior, and
no generated source or unrelated backlog item enters the change.

## Review checkpoints and execution record

Review each task before its commit. Task 2 is the exhaustive-wiring checkpoint;
Task 4 is the causal-digest and persistence checkpoint; Task 7 is the browser
behavior checkpoint. Do not accept visible-value equality as a substitute for
causal convergence at any checkpoint.

| Task | Status at planning time | Commit / outcome |
|---|---|---|
| 1. Kernel | Not started | No implementation in this planning change |
| 2. Channel, wire, core | Not started | Depends on 1 |
| 3. Sequenced facades | Not started | Depends on 2 |
| 4. CRDT/P2P and persistence | Not started | Depends on 2 |
| 5. Lustre | Not started | Depends on 3 and 4 |
| 6. Fuzz model | Not started | Depends on 1; complete before final acceptance |
| 7. Website demonstrations | Not started | Depends on 1-5 |
| 8. Documentation and final gates | Not started | Depends on 1-7 |

# M7 — Handle support / nested SharedMaps (watershed)

**Date:** 2026-07-02
**Status:** Planned, not started. Companion to
`2026-07-01-gleam-sharedmap-client-plan.md` (whose M7 section this supersedes
in detail — notably its `{"type":"Shared"}` sketch and the "value type can no
longer be bare Json" assumption).

## Context

Watershed values today are opaque `Plain` JSON: a value can be an inert object
but never a *collaborative* nested map. M7 adds Fluid-compatible handle values
so a SharedMap key can reference another SharedMap, unlocking nested/sibling
collaborative structures. Verified against the FluidFramework checkout
(`feat/map-corpus-harness`): modern TS serializes a handle as a **`Plain`
value containing the nested object `{"type":"__fluid_handle__","url":"/<path>"}`**
(the legacy `"Shared"` value type is deprecated/read-only — never emit it),
and the TS kernel is completely handle-agnostic. So `map_kernel.gleam` needs
**zero changes**; the real work is multi-channel support in `runtime_core` +
an attach protocol.

**Decisions locked (2026-07-02):**

- **Opaque JSON value model** — handles are just JSON markers; no
  `Plain | Handle` ADT. Kernel, corpus, and wire `Plain` codec stay
  byte-identical to TS.
- **Explicit watershed attach op** — a newly created map is *detached*
  (local-only, edits produce no ops) until its handle is first stored into an
  attached map; the runtime then submits an attach op
  `{address, type, snapshot}` before the referencing set.
- **Multi-DDS-ready protocol** — more DDS types are expected later. Wire
  formats carry a channel `type` tag now (attach op + summary v2); handle
  logic lives in a DDS-agnostic module; `runtime_core` keeps the map-specific
  part a narrow seam. Rule: *protocol generalizes now, code generalizes when
  the second DDS exists.*

## Key design decisions

| Decision | Resolution |
|---|---|
| Handle detection | Full-tree scan of the value at submit time (`json.to_string` → `json.parse` with a recursive collector decoder) — TS-faithful; handles may nest anywhere inside a Plain value |
| Handle url | `"/" <> address` (single segment; watershed has one envelope level). Multi-segment urls are ignored by the scanner (future Fluid interop concern) |
| Attach envelope | DocumentMessage stays `type:"op"`; contents `{"type":"attach","address":a,"channelType":"map","snapshot":[{key,value},…]}`. Discriminated from channel ops' `{address, contents}` by the top-level `"type"` key. Zero levee/spillway change — contents are sequenced opaquely |
| Unknown channelType on decode | Fatal (fail loudly — an old client cannot interpret a future DDS) |
| Op for unknown address | Fatal `UnknownChannel` error (attach always precedes channel ops in sequence order, so this is corruption). Replaces today's silent drop of foreign addresses |
| Kernel transition at attach | **Freeze-and-rebase at attach-submit**: snapshot = optimistic `entries(kernel)`, kernel replaced by `from_sequenced(snapshot)`. Correct because a detached kernel is 100% local and peers can only learn the address from ops sequenced after our attach. Own-attach ack pops in-flight with no kernel mutation; edits between attach-submit and ack are ordinary pending ops FIFO-behind the `InFlightAttach` |
| Attach graph | Post-order DFS over detached maps reachable via handles (dependencies first), visited-set for cycles (A↔B fine); all attaches + triggering set in one submit batch |
| Events | Core returns `List(#(String, MapEvent))` (address, event) — kernel `MapEvent` and corpus stay untouched |
| `resolve` unknown address | Error `"unresolved handle"` (retryable — foreign attach may be in flight). No lazy-empty materialization |
| Summary blob | v2 `{watershedSummaryVersion:2, sequenceNumber, channels:[{address, type:"map", entries}]}`; loader accepts v1 (→ single `"map"` channel). Root first, then attach order |
| Address generation | UUID v4 from `gleam/crypto.strong_random_bytes(16)` (cross-target; promote `gleam_crypto` from dev-deps to deps). Generated in the runtimes — core stays pure |

## Slice M7a — Multi-channel pure core + wire (cross-target, no runtime changes)

**New `src/watershed/handle.gleam`** (DDS-agnostic, per multi-DDS requirement):

```gleam
pub const fluid_handle_type = "__fluid_handle__"
pub fn handle_url(address: String) -> String                    // "/" <> address
pub fn encode_handle(address: String) -> Json                   // the marker object
pub fn parse_handle(value: Json) -> Result(String, Nil)         // top-level marker → address
pub fn collect_handle_addresses(value: Json) -> List(String)    // full-tree scan, deduped
```

**`src/watershed/wire.gleam`:**

- `pub const channel_type_map = "map"`.
- `pub type OpContents { ChannelOp(address, op: MapOp)  AttachOp(address, channel_type: String, snapshot: List(#(String, Json))) }`
- `encode_attach`, `outbound_attach_op(address:, client_sequence_number:,
  reference_sequence_number:, snapshot:)` (stamps `channelType: channel_type_map`).
- `decode_op_contents(Dynamic) -> Result(OpContents, …)` —
  `decode.one_of([attach, map_envelope → ChannelOp])`; keep
  `decode_map_envelope` (wire_test uses it). Snapshot entries reuse
  `summary_entry_decoder`.
- Summary blob v2: `SummaryBlob(sequence_number, channels: List(ChannelSnapshot))`,
  `ChannelSnapshot(address, channel_type, entries)`; encoder writes v2; decoder
  branches on version, v1 → single `"map"` channel, unknown version/channel
  type → failure. Fix the stale `plain_value_decoder` doc comment
  (`wire.gleam:765`) — handle markers ride inside Plain opaquely.

**`src/watershed/runtime_core.gleam`** (map-specific seam = op decode + kernel
application only; routing/in-flight/CSN/attach machinery stays type-agnostic):

```gleam
pub type Core { Core(
  client_id: String,
  channels: Dict(String, map_kernel.MapState),   // attached; "root" always present
  channel_order: List(String),                   // attach order, root first (Dict is unordered; drives summaries)
  detached: Dict(String, map_kernel.MapState),   // local-only kernels
  next_csn: Int, last_seen_sn: Int,
  in_flight: List(InFlight),
  out_of_order: List(SequencedDocumentMessage),
)}
pub type InFlight {
  InFlightOp(client_id, csn, address, op: MapOp)
  InFlightAttach(client_id, csn, address, snapshot: List(#(String, Json)))
}
// CoreError += UnknownChannel(address, sn), DuplicateAttach(address, sn)
```

- `bootstrap(connected, summary:)` — drops the `address` arg; seeds channels
  from `Summary(sequence_number, channels)` (insert empty root if absent),
  else `{"root": new()}`. Replay materializes channels from attach ops.
  `resume_bootstrap`/`settle_bootstrap` unchanged in shape.
- `create_detached(core, address)`, `has_channel(core, address)`.
- Edits become
  `set(core, address, key, value) -> Result(#(Core, List(#(String, MapEvent)), List(wire.OutboundOp)), CoreError)`
  (same for delete/clear). Attached: compute attach closure from
  `handle.collect_handle_addresses(value)` ∩ detached (recursing into
  snapshots, post-order, visited-set), move each kernel `detached → channels`
  as `from_sequenced(entries)`, stamp `InFlightAttach` + emit attach
  outbounds, then the normal set. Detached: mutate detached kernel, events
  only, `[]` outbound, no in-flight.
- Inbound: `handle_op` uses `decode_op_contents`. Remote attach → create
  channel `from_sequenced(snapshot)` (duplicate → `DuplicateAttach`), no
  events. Remote channel op → apply to `channels[address]` or
  `UnknownChannel`. `ack_own` matches head variant: `InFlightOp`↔`ChannelOp`
  (client_id+csn+address+`same_shape`), `InFlightAttach`↔`AttachOp`
  (client_id+csn+address+snapshot keys in order; values by key only — JSON
  key order doesn't survive the wire); attach ack mutates nothing.
- `resubmit` re-stamps both variants preserving order (attach re-encoded from
  stored snapshot). `adopt_reconnect` unchanged.
- `summary_channels(core) -> List(#(String, List(#(String, Json))))` in
  channel_order. Reads gain an `address` param; unknown address → empty
  defaults.

**Tests (update `runtime_core_test` mechanically for new signatures, then
add):** wire: attach codec round-trip, `decode_op_contents` discrimination,
collector on nested/array/dedup/multi-segment-ignored, blob v2 round-trip +
v1 fallback + unknown version/type rejected. Core: remote attach creates
channel + subsequent ops apply with tagged events; unknown-address fatal;
duplicate attach fatal; detached edits produce no outbound; handle set emits
`[attach…, set]` post-order (incl. recursive + cycle cases); edits between
attach-submit/ack queue FIFO; attach ack pops with no events; attach ack
mismatch; reconnect resubmit of interleaved attach+op queue; bootstrap from
multi-channel Summary + attach replay; bootstrap from bare attach history.

**Exit:** `gleam test` green on erlang and javascript targets.

## Slice M7b — Runtimes + public API (both targets)

- **New `src/watershed/ids.gleam`**: `uuid_v4()` via
  `crypto.strong_random_bytes(16)` + version/variant bits; `gleam.toml`:
  `gleam_crypto` → `[dependencies]`.
- **`runtime.gleam` / `runtime_js.gleam`** (kept mirrored): subscribers become
  `List(#(String, Subject(MapEvent)))` (JS: callbacks); `fan_out` routes by
  address. Msg surface gains `address` on
  Put/Remove/RemoveAll/GetValue/GetEntries/GetKeys/GetSize/Subscribe; new
  `CreateMap(reply)` (generates uuid, `create_detached`, replies address;
  valid in Ready/Reconnecting) and `ResolveAddress(address, reply)` (Ok iff
  attached or detached, else retryable error). `edit` generalizes to multi-op
  outbound: in `Ready(_, None)` send all ops in one `submitOp` batch (keep
  `max_ops_per_submission` chunking); in `Reconnecting`/`Ready(_, Some(_))`
  apply and defer (in-flight incl. attaches ride the existing resubmit);
  `Error(UnknownChannel)` → panic (API misuse). Bootstrap loses the
  `address:` arg; `fetch_summary` maps blob channels →
  `runtime_core.Summary`; `handle_summarize` uploads `summary_channels(core)`.
- **`git_storage.gleam`**: only `upload_summary` body changes (takes
  `sequence_number` + channels, builds the v2 blob); tree layout/endpoints
  unchanged; `fetch_summary` follows new `SummaryBlob`.
- **`watershed.gleam` / `watershed_js.gleam`**: `SharedMap` gains an `address`
  field (`root` = `"root"`, unchanged signature; all existing map fns pass
  `map.address` through). New:

```gleam
pub fn create_map(document) -> Result(SharedMap, String)
pub fn handle_of(map) -> Json          // handle.encode_handle(map.address)
pub fn is_handle(value: Json) -> Bool
pub fn resolve(document, value: Json) -> Result(SharedMap, String)
```

JS mirrors 1:1 (sync Results; `create_map`/`resolve` require `on_ready`).

**Exit:** build + tests green on both targets; `examples/dice_lustre` (incl.
`smoke.gleam`) compiles **unchanged** (uses only
connect/root/set/get/subscribe/dev_token).

## Slice M7c — Corpus parity + integration

- **TS oracle** (FluidFramework checkout,
  `packages/dds/map/src/test/mocha/corpusScenarios.ts`): add kernel-level
  handle scenarios — `handle-set`, `handle-nested` (marker buried in
  object-in-array), `handle-overwrite` (LWW race handle↔plain),
  `handle-delete`/`handle-clear` incl. pending-masking,
  `handle-iteration-order`. Regenerate into `test/fixtures/corpus/`. Expected
  Gleam diff: none (proves opacity). **Verify from the first fixture that the
  marker is exactly `{type,url}`** before freezing `encode_handle` (attach is
  runtime-level — out of corpus scope).
- **Integration** (`integration_test.gleam`, gated `WATERSHED_INTEGRATION=1`,
  `127.0.0.1`, against `just server`):
  1. Nested convergence: A `create_map` → detached edits (assert no ops /
     `is_synced`) → set handle on root; B resolves, both edit child, converge.
  2. Recursive attach: two mutually-referencing detached maps; B resolves
     transitively.
  3. Reconnect mid-attach: detached edits + `force_reconnect` + set handle
     while reconnecting → `InFlightAttach` resubmits; B converges.
  4. Summary v2 bootstrap: nested maps → `summarize` → fresh client C
     bootstraps from blob, resolves child without attach-history replay.
  5. `load_version` returns the multi-channel blob (child address present).
- **No levee change needed** (attach rides an opaque `"op"`; blob format is
  client-owned) — confirm once manually via server logs during test 1.
- **Update `2026-07-01-gleam-sharedmap-client-plan.md`**: record M7 status as
  slices land.

## Files to modify

`src/watershed/{handle.gleam (new), ids.gleam (new), wire.gleam,
runtime_core.gleam, runtime.gleam, runtime_js.gleam, git_storage.gleam}`,
`src/{watershed,watershed_js}.gleam`, `gleam.toml`,
`test/watershed/{wire_test,runtime_core_test,integration_test}.gleam`,
`test/fixtures/corpus/*` + FluidFramework `corpusScenarios.ts`, this plan +
the 2026-07-01 plan doc. **Untouched:** `map_kernel.gleam`,
kernel/property/corpus tests (fixtures aside), `examples/dice_lustre`.

## Risks

- **History aging vs attach replay**: an aged-out attach op only bites if
  server *storage* loses ops (deltas REST pages full persisted history) —
  same failure class as today's `HistoryGap`; recommend summarizing after
  creating channels.
- **Resolve race**: transiently unresolved between a foreign attach and its
  dependents sequencing — documented retryable; single-batch submission keeps
  the window intra-batch.
- **`SummaryBlob` shape break** for `load_version` consumers (pre-1.0,
  acceptable).
- **UUID collision** → `DuplicateAttach` crash/resync, not silent divergence
  (negligible probability).

## Verification

1. Per slice: `gleam test` (erlang) and `gleam build --target javascript` +
   JS tests.
2. M7c corpus: regenerate fixtures in the FluidFramework checkout, replay
   green on both targets.
3. `WATERSHED_INTEGRATION=1 gleam test` against `just server` — all five
   scenarios above, repeated runs for stability (matching the M4 bar).
4. Manual end-to-end: dice_lustre still works against the new library
   unchanged.

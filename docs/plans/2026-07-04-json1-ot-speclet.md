# JSON-OT json1 speclet (future extension)

**Date:** 2026-07-04
**Status:** Speclet — not scheduled. Expand only if json0's limits bite.
**Prerequisite:** `2026-07-04-json-ot-kernel-plan.md` shipped and stable
(json0 `json_ot_kernel.gleam`, wire/channel/runtime integration, TP1 + convergence
fuzz all green). This plan assumes that kernel exists and reuses its scaffolding.
**Reference source:** `ottypes/json1` (`json1.js`, `json1.spec.js`) and
`text-unicode` as the embedded string subtype.

## Why a json1 successor might be wanted

json0 (the shipped kernel) is TP1-only client-transform and covers object/list/
number edits plus a `text0` subtype. Three json0 limitations would justify
json1:

1. **No real subtree moves.** json0's move is list-index-only (`lm`). Moving a
   value between arbitrary locations — object→array, reparenting, key rename —
   is not expressible. json1's pick-up / drop-down model handles arbitrary
   moves natively.
2. **Delete pre-images on the wire.** json0 `od`/`ld` carry the deleted value so
   `invert` stays document-free (plan design-decision #3). json1 ops are
   invertible by construction with a cleaner encoding.
3. **Conflict opacity.** json1 surfaces structured conflicts; json0 silently
   resolves via `side`.

If none of these bite in practice, **do not build this** — json0 is less code,
more battle-tested, and satisfies the same TP1 sequencer contract.

## What carries over unchanged from json0

The whole runtime substrate is reused as-is:

- **Sequencer contract.** Central total order, SN/CSN/**RSN**/MSN — identical.
  json1 is also TP1-only; no TP2, no server changes.
- **Kernel shape.** `sequenced`/`pending` split, transform-remote-past-pending,
  pop-on-ack, reconnect rebase past `(RSN, head]`. Same state machine as json0.
- **Integration checklist** (`channel.gleam` header): a new channel type +
  wire codec + runtime verbs + fuzz model. Same steps as json0.
- **Test strategy.** Port `json1.spec.js` as the TP1 oracle; reuse the TP1
  property fuzz and multi-client convergence fuzz harness verbatim.

## What changes vs json0 (the whole delta)

| Area | json0 (shipped) | json1 (this speclet) |
|---|---|---|
| Op model | flat `List(Component)` with `p` path + `Edit` | pick-up / drop-down **cursor tree**: a `p`(pick) slot, a `d`(drop) slot, and an embedded-edit slot, walked as a tree |
| Moves | `lm` (list index only) | arbitrary subtree move via matched pick/drop |
| Deletes | carry pre-image value for invert | invertible by construction; no external snapshot |
| `transform` | `transformComponent` over component lists | cursor-tree transform (subtler; the real cost) |
| `invert` / `rollback` | needs delete pre-images | document-free |
| Subtype | `text0` | `text-unicode` |
| Conflicts | resolved by `side` | structured conflict surfacing |

Everything else (submit/apply/ack flow, event emission, summary round-trip) is a
rename of the json0 kernel's plumbing.

## Sketch: kernel types

New module `src/watershed/json1_kernel.gleam` (or a `variant` of the json0
kernel behind a channel-init flag). Pure, runtime-unaware.

```gleam
pub type Json1State {
  Json1State(sequenced: json.Json, pending: List(Json1Op))
}

/// A json1 op is a tree, not a flat list. Each node addresses one child key
/// and may pick, drop, and/or embed-edit at that position.
pub type Json1Op {
  Json1Op(root: Node)
}

pub type Node {
  Node(
    /// Child edits keyed by path segment (object key or array index).
    children: List(#(PathKey, Node)),
    /// Pick this subtree up to a numbered slot (move source), if any.
    pick: Option(Int),
    /// Drop a picked slot (or a literal insert) here, if any.
    drop: Option(Drop),
    /// Embedded subtype edit at this position (e.g. text-unicode), if any.
    edit: Option(Subtype),
  )
}

pub type Drop {
  DropSlot(slot: Int)         // land a picked-up subtree
  DropInsert(value: json.Json) // literal insert
  DropRemove                   // delete (invertible; value recovered on invert)
}

pub type Subtype { Subtype(name: String, op: json.Json) }
```

`PathKey`, `Side`, events, and `KernelError` are reused from the json0 kernel.

## API surface (delta only)

Same function names/signatures as the json0 kernel — `new`, `from_summary`,
`summary`, `apply_op`, `transform`, `local_edit`, `apply_remote`, `ack_local`,
`compose`, `invert`, `rollback`, subtype hooks. Only the internals differ:

- `apply_op` walks the pick/drop tree in two passes (pick phase collects
  subtrees into a slot map; drop phase re-inserts), then applies embedded edits.
- `transform` is the json1 cursor-tree transform — port directly from
  `json1.js`; do not derive.
- `invert` needs no pre-image (design-decision #3 from the json0 plan is
  dropped here).

## Effort

Assuming json0 is done, this is **mostly rung 2 again**: the cursor-tree
`transform` and `apply_op` are the entire cost. Rungs 1/3/5/6 from the json0
plan collapse to renames because the runtime substrate already exists.

| Rung | Work | Size |
|---|---|---|
| 1 | pick/drop `apply_op` (two-pass) | medium |
| 2 | cursor-tree `transform` + `json1.spec` port + TP1 fuzz | **large — the cost** |
| 3 | wrapper reuse (rename json0 flow) | small |
| 4 | `text-unicode` subtype | small–medium |
| 5 | channel/wire/runtime/fuzz variant | small |

## Decision gate

Build json1 only when a concrete requirement needs subtree moves or
document-free invert that json0 cannot express. Until then this stays a
speclet. Revisit if/when the json0 kernel accrues move-emulation hacks or the
delete-pre-image wire cost becomes a problem.

## Non-goals (inherited from the json0 plan)

- TP2 / decentralized OT — the central sequencer makes it unnecessary.
- Server-side transform in levee.
- Wire interop with ShareDB's json1 encoding unless a concrete integration
  requires it (open question #1 in the json0 plan applies here too).

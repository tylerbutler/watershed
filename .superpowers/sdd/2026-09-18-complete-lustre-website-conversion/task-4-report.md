# Task 4 report

## Status

Complete.

The JSON OT and SharedSequence demos now run as typed, page-scoped Lustre
applications. Their models own replica projections, pending operations,
sequencing state, reset generations, controls, and visible errors. Kernel
creation, mutation, and delivery run through deferred effects. The legacy
TypeScript entry points and their demo-specific FFI modules are no longer
imported by production code.

## Changes

- Added typed JSON OT and sequence runtimes backed by the real watershed
  kernels and in-memory sluice.
- Replaced static-only demo markup with one model-driven view per demo plus a
  static rendering entry point.
- Replaced the client shims with Lustre applications mounted at page-scoped
  roots.
- Removed `json_ot_ffi.mjs` and `sequence_ffi.mjs`.
- Added runtime coverage for convergence, transformed positions,
  remove/insert interaction, pending state, reset generations, and visible
  failures.
- Updated the sequence browser suite to wait for Lustre's rendered selection
  state before asserting it.

## Verification

- `cd website_lustre && gleam test --target javascript -- json_ot_runtime`
  — 160 passed.
- `cd website_lustre && gleam test --target javascript -- sequence_runtime`
  — 160 passed.
- `just website-lustre` — passed.
- `CI=1 node website_lustre/test/browser/json-ot.mjs` — passed.
- `CI=1 node website_lustre/test/browser/sequence.mjs` — passed.

## Concerns

The website build still reports existing dependency deprecation warnings and
existing warnings in unrelated watershed tests. Chromium also requires
`CI=1` in this environment so Puppeteer launches with `--no-sandbox`.

An additional `just test` run completed all 1,827 core tests, then failed in
the unrelated `smoke/runtime_bootstrap.mjs` check with `Missing HTTP request
/trees/`. Running that smoke test alone reproduces the same failure. No files
in that smoke path changed in this task.

## Fix round 1

Resolved all seven review findings.

- `RaceInsert` now calculates and validates B and C insertion positions from
  their own optimistic routes.
- Rapid concurrent allocation uses the original disjoint name classes and
  collision-safe numeric suffixes after a class is exhausted.
- JSON OT and sequence delivery each drain one sequence-number broadcast group,
  log that operation, and leave later groups scheduled.
- Playback speed now scales delivery delays inversely, so `2×` is faster and
  `0.5×` is slower.
- Deferred sequence completion reconciles station selection changes made while
  work was outstanding.
- Sequence routes render the river SVG and key station nodes by stable waypoint
  identity.
- Field notes restore the full caption plus transient local, sequenced, and
  newest-log annotations, with all annotation state and transitions in Gleam.

### Regression evidence

- Short-route crowd inserts cover independently calculated B/C indices.
- Three rapid crowd inserts cover cross-replica name uniqueness.
- JSON OT and sequence tests cover one log entry and one remaining pending
  group after a single delivery.
- Shared timing tests cover `2×`, `1×`, and `0.5×` delivery direction.
- Deferred completion covers selection changes interleaved with outstanding
  sequence work.
- The sequence browser suite checks all three river paths and verifies that a
  moved waypoint keeps the same DOM node.
- The sequence browser suite checks the full field-note caption, local and
  sequenced station flashes, and the newest-log box.

### Verification

- `cd website_lustre && gleam test --target javascript -- demo_timing` —
  166 passed.
- `cd website_lustre && gleam test --target javascript -- json_ot_runtime` —
  166 passed.
- `cd website_lustre && gleam test --target javascript -- sequence_runtime` —
  166 passed.
- `just website-lustre` — passed.
- `CI=1 node website_lustre/test/browser/json-ot.mjs` — passed.
- `CI=1 node website_lustre/test/browser/sequence.mjs` — passed.

The build continues to report the pre-existing dependency deprecation and
unrelated test-source warnings listed above.

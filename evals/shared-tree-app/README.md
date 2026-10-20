# SharedTree agent eval

A portable Vally benchmark for implementing a collaborative incident-response
board with Watershed SharedTree or Fluid Framework SharedTree.

The comparison uses native Gleam/Lustre and TypeScript/React starters. It
measures agent effectiveness with each API ecosystem, including language and
tooling differences.

## Current status

The shared [task](task.md), [required-check contract](contract.json), report
validation/aggregation, native app shells, and local service tooling are
implemented. The agent-visible native models remain unfinished on purpose.
Maintainer-only reference implementations and native inspection probes now
exercise actual SDK schemas, native references across moves/removal, cleanup,
and visible create/open failures without retrying rejected creation. Shared
browser scenarios cover every non-integrity check, including live remote edits,
verified concurrent submissions, late join, and delivered-state reopen.
Lifecycle schedules include Close during held initialization and bounded
observation for delayed creation retries. Native SDK summary uploads are not
counted as document-creation attempts.
Protected-file hashing, candidate-only overlays, and native SDK materialization
are implemented. Portable agent-workspace preparation, the grading CLI,
isolated agent execution, and the comparison
runner are not implemented yet. This directory does not yet provide a runnable
agent eval.

The design and implementation sequence are in:

- [Design spec](../../docs/superpowers/specs/2026-10-19-shared-tree-agent-eval-design.md)
- [Implementation plan](../../docs/superpowers/plans/2026-10-19-shared-tree-agent-eval.md)

## Foundation checks

Use Node >=22.14.0 and pnpm:

```sh
pnpm --dir evals/shared-tree-app install --frozen-lockfile
pnpm --dir evals/shared-tree-app test
```

The package pins Vally core and CLI to 0.19.0. Its pnpm build policy permits
Koffi's native build and disables the optional device-ID package's build.

`lib/contract.mjs` validates the required-check manifest.
`lib/report.mjs` validates complete per-trial reports and computes verdicts
and per-SDK rates. A failed required check fails the trial. Infrastructure
outcomes remain invalid and do not enter agent pass-rate denominators.
Missing valid observations produce `null` rates, not a success or a zero.
Duplicate run IDs and incomplete or malformed reports raise explicit errors.

These checks do not run an agent or measure agent performance.

## Native shells

`watershed/` contains the Gleam/Lustre starter. `fluid/` contains the
TypeScript/React starter. Both render incident and step controls with stable
ID-based selectors. They forward typed actions to the candidate model and
display readiness and errors. `globalThis.__incidentEval` exposes read-only
snapshots, action/Close dispatch, and the current native model/session for
acceptance tooling. It does not translate or serialize tree operations.
Their unfinished models must build but must not claim readiness.

Gleam manifests use `.in` templates so Trellis does not discover unfinished
eval packages. Workspace preparation must materialize their manifests and
stage the selected SDK at the declared dependency paths. SDK selection and
agent-workspace preparation are not wired together yet.

With Chromium installed, run the separate integration suite:

```sh
pnpm --dir evals/shared-tree-app/fluid install --frozen-lockfile
pnpm --dir evals/shared-tree-app/watershed install --frozen-lockfile
pnpm --dir evals/shared-tree-app test:integration
```

Set `WATERSHED_CHROME` if automatic browser discovery cannot locate your
executable. Missing tools or services fail these checks instead of skipping.
Integration files run serially to avoid competing native compilers and Chromium
instances starving the browser command deadlines. Each collaboration scenario
still uses independent, simultaneously connected clients.
Headless contexts emulate page focus so inactive clients continue to render;
browser action deadlines do not depend on which context Chromium made visible.
The shell fixtures test real native framework rendering and action forwarding
without a SharedTree implementation. They are test-only assets; never stage
`test/fixtures/` for an evaluated agent.

`test/integration/native.test.mjs` overlays private models from
`validation/solutions/` and bundles the SDK-specific `graders/*/native.mjs`
probe only in its validation workspace. Probes inspect actual SDK objects and
captured native references, not candidate-generated pass/fail diagnostics.
Never stage either directory in the agent role. Watershed validation uses an
allowlisted Git archive of a full commit, so unrelated uncommitted host edits
cannot change the selected SDK.

Validation caches only compiler-generated local dependency fingerprints, keyed
by the Gleam version and exact dependency manifests. This avoids re-resolving
unchanged locked Hex dependencies for each fresh workspace. It does not cache
candidate code or native build outputs.

`graders/scenarios.mjs` runs the shared browser checks. Normal actions use DOM
controls; malformed, stale, and self-targeted actions use the shell's public
action adapter. Native inspection remains a separate assertion layer.
`lib/barrier.mjs` classifies the actual Phoenix and Socket.IO operation frames
observed from the pinned SDKs. It forwards submissions and connection controls
unchanged, holds incoming operations, requires submissions from both connected
clients, and rejects a dropped client or delivery that escapes the hold.
Evidence contains counts and proxy client IDs, never authentication frames or
operation bodies.

`public/serve.mjs` serves a built workspace and starts its development service:

```sh
node evals/shared-tree-app/public/serve.mjs --sdk fluid --root /absolute/prepared-workspace
node evals/shared-tree-app/public/smoke.mjs 'PRINTED_APP_URL'
```

Use `--sdk watershed` for the native Watershed starter. The development host
prints the configured app URL and cleans up its own service on SIGINT/SIGTERM.
The public smoke check checks creation and a title edit through the UI and
reads the resulting model snapshot, not just the input's DOM value. It rejects
the unfinished models. Hidden native-state and collaboration grading will
supply the stronger correctness checks.

## Container runtime

Use Podman for the local container engine. A working Podman machine and Compose
provider are prerequisites for the later native service and isolation checks:

```sh
podman info
podman compose version
```

Vally calls its container backend `docker` and invokes a `docker` executable,
including `docker context inspect`. Podman's running Docker-compatible socket
alone does not provide that executable. A Docker CLI connected to the Podman
socket and a discoverable Compose plugin are required for that backend. The
service host uses `podman compose` and an isolated credential-free client
configuration instead of the host's Docker Desktop credential settings.

The Watershed service configuration pins Floodgate to commit
`21faeaa4867127cdf437d21c9b5cafc8f027d42d`; its first start builds the image.
Each invocation uses a unique Compose project and a fresh memory backend.
Service diagnostics include the resolved source revision and image content ID.
Fluid uses the pinned local-service package, a unique port, and private storage
under its workspace. No Podman/Vally end-to-end trial claim is made yet.

Do not mount the host checkout, host home, or container-engine socket into an
evaluated agent's workspace. Keep hidden graders and validation solutions
outside agent-visible staging roots.

`lib/staging.mjs` hashes protected files and checks the candidate submission
before copying only the two model/schema files and candidate-owned `test/`
files into a separate trusted workspace. It rejects unexpected sources,
symlinks, protected-file edits, missing model sources, and overlapping task
and grading roots. Generated build output and installed dependencies are
never copied from the candidate. This is submission validation, not a
container isolation boundary.

`lib/sdk.mjs` resolves explicit full commit IDs and selects source/API-doc
allowlists. Watershed inputs come from the immutable commit, not the host's
working files. Fluid builds require checked-out HEAD to match, clean tracked
inputs, a single client-package version, and a complete workspace dependency
closure. Untracked runtime source is rejected; untracked SDK tests are not
selected for staging. Registry service dependencies with different release
lines are not selected as unrelated local packages.
`lib/sdk-build.mjs` materializes that selection. Fluid is rebuilt as ESM from
a fresh, private Git archive with its pinned package manager and locked
dependency closure; it does not reuse the host's compiled SDK output. Public
runtime files, generated declarations, and the local-service entry point are
selected from real package-manager pack output. SDK tests, examples, source
maps, and repository history are excluded. The builder returns provenance and
raw build logs for later grading artifacts.

`test/integration/sdk.test.mjs` builds the actual local Fluid SDK at
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`, installs its local packages with
parent-scoped dependency overrides, rejects registry fallback for those
versions, and runs every shared behavioral check against the reference app.
Set `SHARED_TREE_FLUID_SOURCE` to use another location for that exact checkout.
This adds a fresh SDK build to the integration suite. Portable agent-workspace
preparation remains pending.

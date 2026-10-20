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
and visible create/open failures without retrying rejected creation. The shared
collaboration grader, isolated agent execution, and comparison runner are not
implemented yet. This directory does not yet provide a runnable agent eval.

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
agent-workspace preparation are not implemented yet.

With Chromium installed, run the separate integration suite:

```sh
pnpm --dir evals/shared-tree-app/fluid install --frozen-lockfile
pnpm --dir evals/shared-tree-app/watershed install --frozen-lockfile
pnpm --dir evals/shared-tree-app test:integration
```

Set `WATERSHED_CHROME` if automatic browser discovery cannot locate your
executable. Missing tools or services fail these checks instead of skipping.
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

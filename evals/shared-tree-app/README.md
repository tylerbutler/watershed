# SharedTree agent eval

A portable Vally benchmark for implementing a collaborative incident-response
board with Watershed SharedTree or Fluid Framework SharedTree.

The comparison uses native Gleam/Lustre and TypeScript/React starters. It
measures agent effectiveness with each API ecosystem, including language and
tooling differences.

## Current status

The shared [task](task.md), [required-check contract](contract.json), and report
validation/aggregation are implemented. The native starters, hidden graders,
isolated execution, and comparison runner are not implemented yet. This
directory does not yet provide a runnable agent eval.

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

## Container runtime

Use Podman for the local container engine. A working Podman machine and Compose
provider are prerequisites for the later native service and isolation checks:

```sh
podman info
podman compose version
```

Vally calls its container backend `docker` and invokes a `docker` executable,
including `docker context inspect`. Podman's running Docker-compatible socket
alone does not provide that executable. Verify client compatibility before
using this backend; no Podman/Vally end-to-end compatibility claim is made yet.

Do not mount the host checkout, host home, or container-engine socket into an
evaluated agent's workspace. Keep hidden graders and validation solutions
outside agent-visible staging roots.

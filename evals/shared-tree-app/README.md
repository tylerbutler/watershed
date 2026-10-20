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
Protected-file hashing, candidate-only overlays, native SDK materialization,
portable workspace preparation, and the trusted grading CLI are implemented.
Both SDKs now pass a no-model Vally task-to-grading run through isolated Podman
containers. The matched comparison runner, operator budget inputs, and remaining
fault-injection acceptance checks are still pending. Do not use this checkpoint
for a paid agent comparison.

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
A committed pnpm patch replaces unsupported Podman tmpfs ownership options with
a sticky writable grading-home mount inside the private container. It also
enables Compose profiles when capturing service logs; Vally otherwise writes
empty logs for its profiled services. Task and grading processes still run as
UID 1000. Frozen installs apply this patch on the host and in both images.

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
eval packages. Preparation materializes them with relative dependencies inside
the agent root, including the nested `watershed_lustre` package.

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
After checking Close behavior and page errors, the grader closes finished tabs
to release their renderers. The reopen check closes the original tabs before
opening the document in another browser context.
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
under its workspace.

For externally managed support services, set `SHARED_TREE_SERVICE_URL` to the
service's HTTP origin. The app host verifies readiness and proxies native traffic
without starting a local service or invoking the container engine. Closing the
app host stops only its proxy; the external service's owner must stop the service.
`SHARED_TREE_APP_PORT` selects a fixed loopback port when a service needs a known
public URL (the default is ephemeral). `SHARED_TREE_SERVICE_STATE_ROOT` selects an
existing directory for temporary host state outside the submitted workspace.
The isolated Vally roles use these options to reach their own support service
without access to an engine socket.

`lib/images.mjs` builds separate non-root Linux task and grade images from a
prepared baseline. The task image includes public tooling and its selected SDK,
not hidden graders or validation solutions. The grade image adds a separate
trusted root at `/opt/shared-tree/grading`. Builds pin Node 24.21.0, Gleam 1.18.1,
pnpm 12.13.0, and Vally core/CLI 0.19.0; image manifests record content IDs,
architecture, the package registry, the Vally patch hash, and observed tool versions. Gleam downloads
are checked against their published checksum. Dependencies are installed with
frozen lockfiles before isolation, without rewriting registry URLs.
The builder also builds Floodgate from its pinned source revision and records
the service image's content ID. Fluid's service uses the public task image's
locked local-service package. No pre-existing service image tag is required.

The starters disable pnpm's automatic pre-script dependency installation.
Its saved workspace identity contains absolute paths, so relocation would
otherwise trigger downloads. Frozen installs and protected-input checks remain
required; build scripts use the already-installed dependencies.

The Watershed image integration runs an offline build and Chromium on an
internal Podman network while Floodgate remains reachable. It also exercises
the real Copilot SDK against a local streaming provider fixture through
`docker/gateway.mjs`, with external downloads blocked. The gateway permits only
the selected model's chat-completion route, rejects tunnels and redirects, and
keeps upstream authentication out of client requests and provider error bodies.
No real provider or paid model is used. The gateway accepts text-only messages
and standard chat-completion fields; it rejects provider extensions, remote
image inputs, and native search tools. Select a text chat-completions model
without provider-side browsing.

`lib/isolation.mjs` writes trial-specific Compose configuration. The task and
grade roles use an internal network and separate support-service projects.
Only the task's provider gateway joins an outbound network. Supply
`SHARED_TREE_PROVIDER_URL`, `SHARED_TREE_PROVIDER_API_KEY`, and
`SHARED_TREE_PROVIDER_MODEL` to the controller process; Compose passes them
only to the gateway. Generated Compose files contain variable references,
not credential values. The task's executor must use the gateway's
`http://provider-gateway:8080/v1` endpoint with placeholder client authentication.

The grading role alone mounts a fresh generated report directory at
`/eval-results`. The trusted CLI writes its complete report and build log there
before emitting its success marker. These files survive Vally's grading-project
teardown without relying on console-output limits. The mount exposes only that
generated output directory, never host source, home, or an engine socket.
Offline setup uses Node's file copier to preserve relative dependency symlinks
without copying SELinux labels that would prevent the grading role from reading
the task workspace.

Run the no-model end-to-end validation with:

```sh
node --test evals/shared-tree-app/test/integration/vally.test.mjs
```

It builds each SDK's images, overlays private references into validation-only
candidate inputs, runs Vally's built-in `mock` executor, and executes the native
grader against a fresh service. It checks task input exclusion, blocked external
downloads, credential absence in task environment and saved artifacts, teardown
ordering, and persisted passing reports with all 35 required checks. Production
image baselines retain the unfinished models. These are harness checks, not
measurements of agent performance.

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

`test/integration/sdk.test.mjs` prepares the actual local Watershed SDK and
builds the actual local Fluid SDK at
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`, installs its local packages with
parent-scoped dependency overrides, rejects registry fallback for those
versions, and runs every shared behavioral check against the reference app.
Set `SHARED_TREE_FLUID_SOURCE` to use another location for that exact checkout.
This adds a fresh SDK build to the integration suite. Standalone relocation is
exercised with a fake Watershed checkout and the actual Fluid checkout.

## Prepare a workspace

Run from any directory, using absolute paths and a full commit ID:

```sh
node /absolute/shared-tree-app/prepare.mjs \
  --sdk watershed --source /absolute/watershed \
  --revision FULL_COMMIT_SHA --out /absolute/new-output-directory
```

Use `--sdk fluid` and the Fluid checkout for the other SDK. The output directory
must not already exist. Preparation creates `agent/` and `grading/`; it does not
start an agent. Only `agent/` belongs in the task role. The grading root holds
an independent baseline, native probes, manifests, and SDK build logs.
It never contains reference implementations.

Neither root includes the other starter or its SDK source. Fluid dependencies use
local package directories and parent-scoped overrides so unrelated service
release lines remain intact. Preparation generates the Fluid lockfile; subsequent
installs use `--frozen-lockfile`. The roots contain source and SDK build packages,
not host-installed app dependencies. Linux task/grading images must install their
own native dependencies before a trial. Container isolation is still pending.

## Grade a submission

Install the prepared grading baseline's dependencies before grading, then use
its entry point with the separate submitted workspace:

```sh
pnpm --dir /absolute/prepared/grading/workspace install --frozen-lockfile
node /absolute/prepared/grading/graders/main.mjs \
  --sdk watershed --workspace /absolute/prepared/agent \
  --run-id watershed-validation --output /absolute/results/report.json
```

Use `--sdk fluid` for a Fluid preparation. The trusted baseline must check and
build, its native service must be healthy, and Chromium must start before a
candidate build is graded. Only permitted candidate source files are overlaid;
candidate build scripts and generated bundles are never executed.

Every graded trial produces all 35 required checks, including checks not reached
after a failure. Exit codes are `0` for passed, `1` for agent failure, and `2`
for invalid infrastructure or configuration. The success marker is printed only
after the complete validated report is saved. Reports are published atomically
without replacing existing output; choose a fresh report path for each trial.
The adjacent `.build.log` preserves trusted check/build output.

Actual prepared-SDK integration checks require both reference models to pass,
then introduce a model syntax error and require a complete failing report.
They also poison candidate-generated bundles to prove grading rebuilds from
trusted inputs. These are harness checks, not agent-performance measurements.

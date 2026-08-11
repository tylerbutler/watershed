# Gleam DDS client toolkit for Erlang and JavaScript runtimes

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias l := lint
alias c := clean

# Default recipe
default:
    @just --list

# === STANDARD RECIPES ===

# Compile the project
build: _build-gleam _build-bundles

# `trellis run` fans the Gleam compile across every member in dependency order.
# Only `watershed` belongs to both target families, so each target is its own
# task with its own exclusions — see `[tools.trellis.exclude]` in gleam.toml.
# A new package under examples/ is picked up here for free.
_build-gleam:
    trellis run build-erlang
    trellis run build-javascript

# The browser bundles. These are pnpm scripts (esbuild), not Gleam builds, and
# each example is a self-contained pnpm workspace with its own lockfile — the
# root `pnpm-workspace.yaml` deliberately declares `packages: []` so `pnpm -r`
# will not reach down here. Hence the glob rather than trellis or pnpm recursion.
_build-bundles:
    for d in examples/*/package.json; do pnpm --dir "$(dirname "$d")" run build; done

# Run tests
test: _test-gleam _test-js

# Every member with a `test/` directory, each on the target its own gleam.toml
# pins. This covers the Lustre bindings package (grapheme diff, UTF-16 offset
# conversion — gleeunit, because startest pins gleam_stdlib < 1.0 while lustre
# is on 1.x) and the app-level example suites, which are gleeunit on the JS
# target driven by the in-memory sluice, so they need no server and no browser.
# Suite-less packages are excluded in gleam.toml; everything else is automatic.
_test-gleam:
    trellis run test

# The JS-target suite for `watershed` itself. `gleam.toml` pins
# `target = "erlang"`, so the `@target(javascript)` tests — chiefly the sluice
# driver suite — only run when the target is named explicitly. They are a
# separate suite, not a re-run: neither target sees the other's tests.
_test-js:
    trellis run test --target javascript watershed

# Deep kernel-fuzz run: overrides FUZZ_ITERATIONS for a much larger,
# CI/nightly-grade sweep than the fast profile plain `gleam test` uses by
# default (see test/watershed/fuzz/README.md). Set FUZZ_SEED to pin a
# specific seed for a reproducible deep run.
fuzz:
    FUZZ_ITERATIONS=5000 gleam test

# === INTEGRATION (live floodgate server) ===

# Start a floodgate dev server in Docker, built from the levee repo's
# `floodgate` branch on GitHub (no clone needed; first build takes a few
# minutes)
integration-up:
    docker compose up -d --wait --build

# Start a floodgate dev server built from a local ../levee checkout, to test
# uncommitted server changes
integration-up-local:
    docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --wait --build

# Stop and remove the floodgate dev server
integration-down:
    docker compose down

# Run the test suite with the live integration tests enabled (assumes a
# floodgate server is already up on 127.0.0.1:4000)
integration-run:
    WATERSHED_INTEGRATION=1 gleam test

# Run the live suite for the *JavaScript* runtime (assumes a floodgate server is
# already up on 127.0.0.1:4000, and `pnpm install` has been run at the root).
#
# Not part of `integration-run`: that is `gleam test`, whose runner has nowhere
# to return a promise, so an async live suite cannot be a test case in it. See
# the header of `test/live_js.gleam`. The `gleam test` here is the build step
# for the test modules — the live scenarios run from `smoke/run.mjs` after it.
integration-run-js:
    WATERSHED_INTEGRATION=1 gleam test --target javascript
    WATERSHED_INTEGRATION=1 node smoke/run.mjs

# Full live integration cycle: start server, run both suites, tear down
integration:
    docker compose up -d --wait --build
    WATERSHED_INTEGRATION=1 gleam test && WATERSHED_INTEGRATION=1 gleam test --target javascript && WATERSHED_INTEGRATION=1 node smoke/run.mjs; status=$?; docker compose down; exit $status

# Start floodgate on the durable (DETS) backend, which the restart test needs —
# the default in-memory backend loses the document on restart, leaving nothing
# to replay
integration-up-persistent:
    docker compose -f docker-compose.yml -f docker-compose.persistent.yml up -d --wait --build

# Full restart-scenario cycle: durable server, suite with the restart test
# enabled, then tear down *including the volume* — a log left over from a
# previous run is indistinguishable from the one the test just wrote
integration-restart:
    docker compose -f docker-compose.yml -f docker-compose.persistent.yml down -v
    docker compose -f docker-compose.yml -f docker-compose.persistent.yml up -d --wait --build
    WATERSHED_INTEGRATION=1 WATERSHED_INTEGRATION_RESTART=1 gleam test; status=$?; docker compose -f docker-compose.yml -f docker-compose.persistent.yml down -v; exit $status

# Format code
format:
    gleam format

# Run linter
lint:
    gleam format --check

# Remove build artifacts, in every member rather than just the root package
clean:
    trellis run clean

# Full validation workflow
ci: format lint test build

alias pr := ci

# === DEPENDENCIES ===

# Install dependencies
deps: _deps-gleam _deps-live-js _deps-bundles

# `gleam deps download` in every member — each example carries its own manifest,
# which is why this cannot be a single root-level download.
_deps-gleam:
    trellis run deps

# phoenix + ws, for the live JS integration suite only
_deps-live-js:
    pnpm install

# npm deps for the browser examples; see `_build-bundles` for why this is a glob.
_deps-bundles:
    for d in examples/*/package.json; do pnpm --dir "$(dirname "$d")" install; done

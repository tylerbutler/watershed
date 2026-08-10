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
build: _build-erlang _build-javascript _build-lustre _build-dice _build-sudoku _build-playlist _build-grocery _build-text _build-drum _build-pixel _build-work-queue

# Run tests
test: _test-gleam _test-js _test-lustre _test-examples

_test-gleam:
    gleam test

# The JS-target suite. `gleam.toml` pins `target = "erlang"`, so the
# `@target(javascript)` tests — chiefly the sluice driver suite — only run when
# the target is named explicitly. They are a separate suite, not a re-run:
# neither target sees the other's tests.
_test-js:
    gleam test --target javascript

# Unit tests for the Lustre bindings package. Its pure modules (grapheme diff,
# UTF-16 offset conversion) have their own gleeunit suite — startest cannot be
# shared here, it pins gleam_stdlib < 1.0 while lustre is on 1.x.
_test-lustre:
    cd watershed_lustre && gleam test

# The app-level suites that live in the example packages. These are gleeunit on
# the JS target, driven by the in-memory sluice, so they need no server and no
# browser — they are the closest thing here to testing watershed the way an app
# author would. Only the examples that have a `test/` directory are listed.
_test-examples:
    cd examples/sudoku_lustre && gleam test
    cd examples/drum_machine_lustre && gleam test
    cd examples/pixel_canvas_lustre && gleam test

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

# Remove build artifacts
clean:
    gleam clean

# Full validation workflow
ci: format lint test build

alias pr := ci

# === DEPENDENCIES ===

# Install dependencies
deps: _deps-gleam _deps-live-js _deps-dice _deps-sudoku _deps-playlist _deps-grocery _deps-text _deps-drum _deps-pixel _deps-work-queue

_deps-gleam:
    gleam deps download

# phoenix + ws, for the live JS integration suite only
_deps-live-js:
    pnpm install

_deps-dice:
    pnpm --dir examples/dice_lustre install

_deps-sudoku:
    pnpm --dir examples/sudoku_lustre install

_deps-playlist:
    pnpm --dir examples/playlist_lustre install

_deps-grocery:
    pnpm --dir examples/grocery_triptych_lustre install

_deps-text:
    pnpm --dir examples/text_lustre install

_deps-drum:
    pnpm --dir examples/drum_machine_lustre install

_deps-pixel:
    pnpm --dir examples/pixel_canvas_lustre install

_deps-work-queue:
    pnpm --dir examples/work_queue_lustre install

_build-erlang:
    gleam build --target erlang

_build-javascript:
    gleam build --target javascript

# Build the Lustre effect bindings on their own (examples build it
# transitively, but this typechecks the package standalone).
_build-lustre:
    cd watershed_lustre && gleam build --target javascript

_build-dice:
    pnpm --dir examples/dice_lustre run build

_build-sudoku:
    pnpm --dir examples/sudoku_lustre run build

_build-playlist:
    pnpm --dir examples/playlist_lustre run build

_build-grocery:
    pnpm --dir examples/grocery_triptych_lustre run build

_build-text:
    pnpm --dir examples/text_lustre run build

_build-drum:
    pnpm --dir examples/drum_machine_lustre run build

_build-pixel:
    pnpm --dir examples/pixel_canvas_lustre run build

_build-work-queue:
    pnpm --dir examples/work_queue_lustre run build

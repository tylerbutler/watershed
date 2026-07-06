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
build: _build-erlang _build-javascript _build-dice

# Run tests
test:
    gleam test

# Deep kernel-fuzz run: overrides FUZZ_ITERATIONS for a much larger,
# CI/nightly-grade sweep than the fast profile plain `gleam test` uses by
# default (see test/watershed/fuzz/README.md). Set FUZZ_SEED to pin a
# specific seed for a reproducible deep run.
fuzz:
    FUZZ_ITERATIONS=5000 gleam test

# === INTEGRATION (live levee server) ===

# Start a levee dev server in Docker (published GHCR image, no clone needed)
integration-up:
    docker compose up -d --wait

# Start a levee dev server built from the levee `gleam` branch source
integration-up-build:
    docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --wait --build

# Stop and remove the levee dev server
integration-down:
    docker compose down

# Run the test suite with the live integration tests enabled (assumes a
# levee server is already up on 127.0.0.1:4000)
integration-run:
    WATERSHED_INTEGRATION=1 gleam test

# Full live integration cycle: start server, run suite, tear down
integration:
    docker compose up -d --wait
    WATERSHED_INTEGRATION=1 gleam test; status=$?; docker compose down; exit $status

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
deps: _deps-gleam _deps-dice

_deps-gleam:
    gleam deps download

_deps-dice:
    pnpm --dir examples/dice_lustre install

_build-erlang:
    gleam build --target erlang

_build-javascript:
    gleam build --target javascript

_build-dice:
    pnpm --dir examples/dice_lustre run build

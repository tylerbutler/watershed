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

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

# The browser bundles. Trellis runs the pnpm script from each example's own
# directory, so pnpm uses that example's workspace and lockfile.
_build-bundles:
    trellis run bundle --serial

# Run tests
test: _test-gleam _test-js _test-compile-fail _test-website-snippets

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

# The one guarantee no ordinary test can make: that *wrong* code is rejected.
# `tools/compile-fail/two_root_tags` views one document's root through two
# schemas, which `Document(root)` exists to forbid. Trellis never builds the
# fixture (see [tools.trellis.exclude]); this recipe is the only thing that
# does, and passing means the build failed *with the stated type error* — the
# grep is what stops a typo from making this green for the wrong cause.
_test-compile-fail:
    #!/usr/bin/env bash
    set -uo pipefail
    out=$(cd tools/compile-fail/two_root_tags && gleam build --target javascript 2>&1)
    if [ $? -eq 0 ]; then
      echo "FAIL: two_root_tags compiled. A document now admits two root schemas."
      exit 1
    fi
    if ! grep -q 'Field(Sudoku, String)' <<<"$out"; then
      echo "FAIL: two_root_tags failed to build, but not with the expected type error:"
      echo "$out"
      exit 1
    fi
    echo "ok  two_root_tags is rejected, as it must be"

# Source-backed snippet drift gates — the website test suite that enforces
# every rendered snippet id is declared and generated, marker IDs are unique
# and quoted, literal Gleam is allowlisted, only SnippetBlock renders code,
# and only the loader reads the generated manifest. Regenerates the manifest
# first, then runs the drift gate suite plus every targeted snippet test from
# the website package, and the global-stylesheet test that keeps the
# source-path chip keyboard-focusable — a snippet's citation is a link, so
# losing its focus ring is a drift of the same system.
_test-website-snippets: website-snippets
    cd website && pnpm test:snippet && pnpm test:snippet-manifest && pnpm test:practice-snippets && pnpm test:standalone-snippets && pnpm test:drift-gates && pnpm test:copy-gates && pnpm test:global-styles

# Generate the website's snippet manifest from `website/snippets.json`.
# The output, `website/src/generated/snippets.json`, is ignored rather than
# committed: it is derived from the marked sources and the configuration, so
# a checked-in copy could only ever disagree with them. `pnpm build` and
# `pnpm dev` run this too, so the website never reads a stale manifest.
website-snippets:
    cd tools/source-snippets && gleam run -m source_snippets/cli -- ../../website/snippets.json ../../website/src/generated/snippets.json

# Deep kernel-fuzz run: overrides FUZZ_ITERATIONS for a much larger,
# CI/nightly-grade sweep than the fast profile plain `gleam test` uses by
# default (see test/watershed/fuzz/README.md). Set FUZZ_SEED to pin a
# specific seed for a reproducible deep run.
fuzz:
    FUZZ_ITERATIONS=5000 gleam test

# Real-browser WebRTC smoke: two `crdt_core` peers connect over an actual
# `RTCPeerConnection` data channel through an in-memory signaling adapter and
# converge, with no server of any kind. Not part of `just test`: it needs a
# browser, and it is a promise-driven scenario with nowhere to return from a
# startest case (same reason as the live JS suite). The deterministic
# fake-RTCPeerConnection tests that *are* in the suite cover the same
# transport; this proves the FFI against a real one. `gleam test` here is the
# build step for the harness module. Skips with an explicit message, and exit
# 0, on a machine with no Chromium — set WATERSHED_CHROME to point at one.
p2p-smoke:
    gleam test --target javascript
    node smoke/p2p_browser.mjs

# The reference WebRTC signaling service, for the p2p examples. It introduces
# peers and carries offers, answers, and ICE candidates; by protocol shape it
# cannot route document data (`src/watershed/crdt_signaling.gleam`). In-memory,
# unauthenticated, and a reference rather than a deployment.
signaling:
    gleam build --target javascript
    node tools/signaling/server.mjs --port 4400

# The signaling service's own tests: room membership, routing, the eight-peer
# cap, malformed/oversize/cross-room refusals, a signal to a departed peer
# being dropped rather than fatal, the browser adapter's roster/timeout/
# failure behaviour, and — the point — that a document envelope is rejected
# rather than routed. Real sockets, so this is a node script rather than a
# `gleam test` case; the pure protocol underneath it is covered by
# `test/watershed/crdt_signaling_test.gleam` in the JS suite.
signaling-test:
    gleam build --target javascript
    node tools/signaling/test.mjs

# The serverless signaling adapter's own tests: census roster and mutual
# discovery over gossip, routing and room isolation via derived topics,
# cross-relay dedupe, failure reporting, and — the point of the encrypted
# lane — that a relay never holds a legible byte. Driven against an
# in-process NIP-01 relay stub (`watershed/nostr_signaling_js` needs no
# deployed service; public Nostr relays play the signaler). Real sockets,
# so this is a node script rather than a `gleam test` case.
nostr-test:
    gleam build --target javascript
    node tools/nostr/test.mjs

# The reference relay: a durable `crdt_relay_v1` fan-out point for CRDT
# documents. It stamps a diagnostic order, keeps an append-only log it can
# replay, and broadcasts what it accepts — it merges nothing and decodes no
# kernel payload (`src/watershed/crdt_relay.gleam`). Optional: a p2p document
# works without one, and `Auto` never waits for it.
relay:
    gleam build --target javascript
    node tools/relay/server.mjs --port 4500 --data ./relay-data

# What each room's log and checkpoint hold on disk. Read-only: it takes no
# lock, repairs nothing, and is safe to run beside a live service — see
# `docs/crdt-relay-v1.md`, *One writer per data directory*, for what the
# numbers mean.
relay-inspect data="./relay-data":
    gleam build --target javascript
    node tools/relay/server.mjs --data {{data}} --inspect

# The relay's own tests: admission, room isolation, frame limits, and — the
# point — the whole absent → attach → checkpoint → outage edits → restart →
# converge lifecycle against the real process, with its data directory in a
# fresh temp dir that is removed afterwards. Real sockets and a real disk, so
# this is a node script rather than a `gleam test` case; the pure protocol
# underneath it is covered by `test/watershed/crdt_relay_test.gleam` on both
# targets, and the client and facade by the JS suite.
relay-test:
    gleam test --target javascript
    node tools/relay/test.mjs

# The p2p gate: two *real* browser pages join a room through the real
# signaling process, clap concurrently, and must converge on the same total
# and the same canonical digest — with the late page ready only after its
# state merge, and the signaling process asserted to have carried no document
# data. Not part of `just test`: it needs a browser.
# Skips with an explicit message, and exit 0, on a machine with no Chromium.
p2p-clap:
    gleam test --target javascript
    node smoke/p2p_clap.mjs

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

# === P2P (reference signaling + coturn TURN/STUN) ===

# Start the reference signaling service and a coturn TURN/STUN server in
# Docker, for exercising watershed's WebRTC transport across a NAT — see
# docker-compose.p2p.yml for the credentials and example URL
p2p-up:
    docker compose -f docker-compose.p2p.yml up -d --wait --build

# Start the signaling service, coturn, and the optional durable relay
# (an alternative sequencer to floodgate; `watershed/crdt_relay`)
p2p-up-relay:
    docker compose -f docker-compose.p2p.yml --profile relay up -d --wait --build

# Stop and remove the p2p reference stack
p2p-down:
    docker compose -f docker-compose.p2p.yml --profile relay down

# Format code. `trellis run` fans `gleam format` across every member, so the
# examples and the website fixture under tools/ are formatted by the same
# command as the root package rather than only when someone remembers to cd.
format:
    trellis run format

# Run linter — the same fan-out, in check mode. A member left unformatted
# fails here, which is how `tools/website-samples` is kept honest: the website
# quotes its source verbatim, so its formatting is published prose.
lint:
    trellis run format --check

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

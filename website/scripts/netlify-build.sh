#!/usr/bin/env bash
# Netlify build script: installs the Gleam compiler (not in Netlify's build
# image), verifies the Erlang toolchain the image is expected to supply, then
# runs the normal site build.
#
# `pnpm build` triggers the `prebuild` hook, which:
#   1. Compiles the Gleam kernel to JavaScript for the live demo.
#   2. Generates the source-snippet manifest (`pnpm generate:snippets`) by running
#      tools/source-snippets — an Erlang-target Gleam CLI that needs
#      escript and erlc.
set -euo pipefail

GLEAM_VERSION="${GLEAM_VERSION:-1.16.0}"

if ! command -v gleam >/dev/null 2>&1; then
  echo "Installing gleam v${GLEAM_VERSION}..."
  install_dir="${HOME}/.gleam-bin"
  mkdir -p "${install_dir}"
  curl -fsSL "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz -C "${install_dir}"
  export PATH="${install_dir}:${PATH}"
fi

# ── Toolchain check ──────────────────────────────────────────────────────
# The source-snippet generator targets Erlang: Gleam compiles to .erl, erlc
# compiles to .beam, and escript runs the result. Both must be present
# before the prebuild hook. Netlify's Ubuntu build image ships esl-erlang,
# which provides them, so this check should never fire — it exists to turn a
# change of build image into a one-line diagnosis instead of a confusing
# Gleam compile failure deep in the prebuild.
missing=()
for cmd in escript erlc; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done
if (( ${#missing[@]} )); then
  echo "ERROR: missing Erlang toolchain commands: ${missing[*]}" >&2
  echo "The source-snippet prebuild needs escript and erlc." >&2
  echo "The Netlify build image is expected to supply them (it installs esl-erlang)." >&2
  echo "If the image no longer does, install Erlang here before running the build." >&2
  exit 1
fi
# ─────────────────────────────────────────────────────────────────────────

gleam --version
pnpm build

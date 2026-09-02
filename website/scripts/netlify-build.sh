#!/usr/bin/env bash
# Netlify build script: installs the Gleam compiler (not in Netlify's build
# image), verifies the Erlang toolchain (installed via Aptfile by
# netlify-plugin-apt), then runs the normal site build.
#
# `pnpm build` triggers the `prebuild` hook, which:
#   1. Compiles the Gleam kernel to JavaScript for the live demo.
#   2. Generates the source-snippet manifest (`pnpm snippets`) by running
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
# compiles to .beam, and escript runs the result. All three must be present
# before the prebuild hook. If they are missing the Aptfile was not
# honoured — check that netlify-plugin-apt is configured in netlify.toml and
# that website/Aptfile lists erlang-base (or an equivalent).
missing=()
for cmd in escript erlc; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done
if (( ${#missing[@]} )); then
  echo "ERROR: missing Erlang toolchain commands: ${missing[*]}" >&2
  echo "The source-snippet prebuild needs escript and erlc." >&2
  echo "Ensure netlify-plugin-apt is enabled and website/Aptfile lists erlang-base." >&2
  exit 1
fi
# ─────────────────────────────────────────────────────────────────────────

gleam --version
pnpm build

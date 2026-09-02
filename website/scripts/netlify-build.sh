#!/usr/bin/env bash
# Netlify build script: installs the Gleam compiler, which is the one thing
# the build image does not already have, then runs the normal site build.
#
# `pnpm build` triggers the `prebuild` hook, which:
#   1. Compiles the Gleam kernel to JavaScript for the live demo.
#   2. Generates the source-snippet manifest (`pnpm generate:snippets`) by
#      running tools/source-snippets, a JavaScript-target Gleam CLI. It
#      compiles to plain ES modules and runs on the Node the image supplies,
#      so this deploy needs no second language runtime.
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

if ! command -v gleam >/dev/null 2>&1; then
  echo "ERROR: gleam is still not on PATH after the install step." >&2
  echo "The site build compiles Gleam to JavaScript and cannot continue." >&2
  echo "Check the download URL for v${GLEAM_VERSION} and the ${HOME}/.gleam-bin directory." >&2
  exit 1
fi

gleam --version
pnpm build

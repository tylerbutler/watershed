#!/usr/bin/env bash
# Workers Builds supplies Node, but not Gleam. Install the compiler before
# pnpm's prebuild compiles the runtime, samples, and snippet generator.
set -euo pipefail

GLEAM_VERSION="${GLEAM_VERSION:-1.18.1}"

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

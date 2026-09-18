#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

GLEAM_VERSION="${GLEAM_VERSION:-1.18.1}"
PNPM_VERSION="${PNPM_VERSION:-11.13.1}"

if ! command -v gleam >/dev/null 2>&1 || [ "$(gleam --version)" != "gleam ${GLEAM_VERSION}" ]; then
  install_dir="${HOME}/.gleam-bin"
  mkdir -p "${install_dir}"
  curl -fsSL "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz -C "${install_dir}"
  export PATH="${install_dir}:${PATH}"
fi

if command -v corepack >/dev/null 2>&1; then
  run_pnpm() {
    corepack "pnpm@${PNPM_VERSION}" "$@"
  }
elif command -v pnpm >/dev/null 2>&1 && [ "$(pnpm --version)" = "${PNPM_VERSION}" ]; then
  run_pnpm() {
    pnpm "$@"
  }
else
  echo "ERROR: corepack or pnpm ${PNPM_VERSION} is required." >&2
  exit 1
fi

gleam --version
run_pnpm --version

run_pnpm --dir website install --frozen-lockfile
PUPPETEER_SKIP_DOWNLOAD=true run_pnpm --dir website_lustre install --frozen-lockfile

gleam deps download
(cd watershed_lustre && gleam deps download)
(cd tools/source-snippets && gleam deps download)
(cd tools/website-lustre-build && gleam deps download)
(cd website_lustre && gleam deps download)

./tools/build-website-lustre.sh

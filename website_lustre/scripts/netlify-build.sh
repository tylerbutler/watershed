#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

GLEAM_VERSION="${GLEAM_VERSION:-1.18.1}"
OTP_VERSION="${OTP_VERSION:-28.5}"
PNPM_VERSION="${PNPM_VERSION:-11.13.1}"

otp_install_dir="${HOME}/.otp/${OTP_VERSION}"
if [ ! -f "${otp_install_dir}/.installed" ]; then
  # Hex publishes the same prebuilt OTP archives used by setup-beam.
  source /etc/os-release
  case "${ID:-}-${VERSION_ID:-}" in
    ubuntu-22.04 | ubuntu-24.04)
      otp_platform="ubuntu-${VERSION_ID}"
      ;;
    *)
      echo "ERROR: No prebuilt OTP ${OTP_VERSION} archive for ${ID:-unknown} ${VERSION_ID:-unknown}." >&2
      exit 1
      ;;
  esac
  rm -rf "${otp_install_dir}"
  mkdir -p "$(dirname "${otp_install_dir}")"
  archive_dir="$(mktemp -d)"
  trap 'rm -rf "${archive_dir}"' EXIT
  curl -fsSL "https://builds.hex.pm/builds/otp/${otp_platform}/OTP-${OTP_VERSION}.tar.gz" \
    | tar -xz -C "${archive_dir}"
  mv "${archive_dir}/OTP-${OTP_VERSION}" "${otp_install_dir}"
  (
    cd "${otp_install_dir}"
    ./Install -minimal "${otp_install_dir}"
  )
  touch "${otp_install_dir}/.installed"
fi
export PATH="${otp_install_dir}/bin:${PATH}"

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

otp_release="$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().')"
if [ "${otp_release}" != "${OTP_VERSION%%.*}" ]; then
  echo "ERROR: OTP ${OTP_VERSION} is required, found ${otp_release}." >&2
  exit 1
fi

erl -version
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

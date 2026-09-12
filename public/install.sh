#!/bin/sh
# dbpod installer — https://dbpod.io
#
# Usage:  curl -fsSL https://dbpod.io/install.sh | sh
#
# Downloads the dbpod binary for your platform from GitHub Releases and
# installs it into ~/.local/bin (override with DBPOD_INSTALL_DIR).
#
# Asset naming expected from the release pipeline (dbpod-io/dbpod):
#   dbpod-{os}-{arch}.tar.gz     os: darwin | linux      arch: amd64 | arm64

set -eu

REPO="dbpod-io/dbpod"
BIN_NAME="dbpod"

log() { printf 'info: %s\n' "$1"; }
err() { printf 'error: %s\n' "$1" >&2; exit 1; }

# --- resolve version -----------------------------------------------------
DBPOD_VERSION="${DBPOD_INSTALL_VERSION:-latest}"

# --- detect platform -----------------------------------------------------
os="$(uname -s)"
case "$os" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) err "unsupported operating system: $os (dbpod supports macOS and Linux; on Windows use WSL or grab the release archive manually)" ;;
esac

arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64) arch="amd64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *) err "unsupported architecture: $arch" ;;
esac

asset="dbpod-${os}-${arch}.tar.gz"

if [ "$DBPOD_VERSION" = "latest" ]; then
  url="https://github.com/${REPO}/releases/latest/download/${asset}"
else
  url="https://github.com/${REPO}/releases/download/${DBPOD_VERSION}/${asset}"
fi

# --- download ------------------------------------------------------------
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
log "downloading ${asset} ..."

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$url" -o "${tmp_dir}/${asset}" || err "download failed: ${url}"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${tmp_dir}/${asset}" "$url" || err "download failed: ${url}"
else
  err "need curl or wget to download"
fi

tar -xzf "${tmp_dir}/${asset}" -C "$tmp_dir"

# --- install -------------------------------------------------------------
install_dir="${DBPOD_INSTALL_DIR:-${HOME}/.local/bin}"
mkdir -p "$install_dir"

if [ -f "${tmp_dir}/${BIN_NAME}" ]; then
  mv "${tmp_dir}/${BIN_NAME}" "${install_dir}/${BIN_NAME}"
else
  err "archive did not contain a ${BIN_NAME} binary — asset layout mismatch?"
fi
chmod +x "${install_dir}/${BIN_NAME}"

case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *)
    log "note: ${install_dir} is not in your PATH"
    log "add it:  export PATH=\"${install_dir}:\$PATH\""
    ;;
esac

printf '\n%s\n' "dbpod installed → ${install_dir}/${BIN_NAME}"
printf '%s\n' "get started:  ${BIN_NAME} engine install mysql@8.0"

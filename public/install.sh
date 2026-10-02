#!/bin/sh
# dbpod installer — https://dbpod.io
#
# CLI only:
#   curl -fsSL https://dbpod.io/install.sh | sh
#
# CLI + database engine(s) in one shot:
#   curl -fsSL https://dbpod.io/install.sh | sh -s -- --engine mysql@8.0
#   curl -fsSL https://dbpod.io/install.sh | sh -s -- --engine mysql@8.0 --engine postgres@17
#
# Pin the CLI version:
#   curl -fsSL https://dbpod.io/install.sh | sh -s -- --version v0.1.0
#
# Env-var equivalents (handy when piping):
#   DBPOD_VERSION=v0.1.0 DBPOD_ENGINES="mysql@8.0 postgres@17" sh
#
# Downloads the dbpod binary for your platform from GitHub Releases, verifies
# it against the release checksums, and installs it into ~/.local/bin
# (override with DBPOD_INSTALL_DIR or --install-dir).
#
# Asset naming expected from the release pipeline (dbpod-io/dbpod):
#   dbpod-{os}-{arch}.tar.gz     os: darwin | linux      arch: amd64 | arm64
#   checksums.txt                one sha256 line per release asset

set -eu

REPO="dbpod-io/dbpod"
BIN_NAME="dbpod"
RELEASES="https://github.com/${REPO}/releases"

log() { printf 'info: %s\n' "$1"; }
err() { printf 'error: %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<EOF
dbpod installer

usage: curl -fsSL https://dbpod.io/install.sh | sh -s -- [options]

options:
  --engine <engine@version>  also install a database engine (repeatable)
  --version <v>              pin the dbpod CLI version (default: latest)
  --install-dir <dir>        install location (default: ~/.local/bin)
  -h, --help                 show this help

environment:
  DBPOD_VERSION        same as --version
  DBPOD_ENGINES        comma/space-separated engine refs, same as --engine
  DBPOD_INSTALL_DIR    same as --install-dir
EOF
}

# --- options ---------------------------------------------------------------
DBPOD_VERSION="${DBPOD_VERSION:-${DBPOD_INSTALL_VERSION:-latest}}"
ENGINES="${DBPOD_ENGINES:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --engine)
      [ $# -ge 2 ] || err "--engine needs a value (e.g. mysql@8.0)"
      ENGINES="$ENGINES $2"; shift 2
      ;;
    --engine=*)
      ENGINES="$ENGINES ${1#*=}"; shift
      ;;
    --version)
      [ $# -ge 2 ] || err "--version needs a value"
      DBPOD_VERSION="$2"; shift 2
      ;;
    --version=*)
      DBPOD_VERSION="${1#*=}"; shift
      ;;
    --install-dir)
      [ $# -ge 2 ] || err "--install-dir needs a value"
      DBPOD_INSTALL_DIR="$2"; shift 2
      ;;
    --install-dir=*)
      DBPOD_INSTALL_DIR="${1#*=}"; shift
      ;;
    -h | --help)
      usage; exit 0
      ;;
    *)
      err "unknown argument: $1 (try --help)"
      ;;
  esac
done

ENGINES="$(printf '%s' "$ENGINES" | tr ',' ' ')"
for e in $ENGINES; do
  case "$e" in
    *@*) ;;
    *) err "engine ref must look like <engine>@<version> (e.g. mysql@8.0), got: $e" ;;
  esac
done

# --- detect platform -------------------------------------------------------
os="$(uname -s)"
case "$os" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) err "unsupported operating system: $os (dbpod supports macOS and Linux; on Windows use: irm https://dbpod.io/install.ps1 | iex)" ;;
esac

arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64) arch="amd64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *) err "unsupported architecture: $arch" ;;
esac

asset="dbpod-${os}-${arch}.tar.gz"

if [ "$DBPOD_VERSION" = "latest" ]; then
  base_url="${RELEASES}/latest/download"
else
  base_url="${RELEASES}/download/${DBPOD_VERSION}"
fi

# --- download helpers ------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  # retries cover transient network errors; 404s still fail fast
  fetch() { curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" --tries=3 --waitretry=2 "$1"; }
else
  err "need curl or wget to download"
fi

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    return 1
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log "downloading ${asset} ..."
fetch "${base_url}/${asset}" "${tmp_dir}/${asset}" || err "download failed: ${base_url}/${asset} (if you need a proxy, set HTTPS_PROXY)"

# --- verify checksum -------------------------------------------------------
got=""
if fetch "${base_url}/checksums.txt" "${tmp_dir}/checksums.txt" 2>/dev/null; then
  asset_pat="$(printf '%s' "$asset" | sed 's/\./\\./g')"
  want="$(grep -E "^[0-9a-fA-F]{64}[[:space:]]+${asset_pat}[[:space:]]*$" "${tmp_dir}/checksums.txt" | awk '{print $1}')"
  if [ -z "$want" ]; then
    err "checksum for ${asset} not found in checksums.txt"
  fi
  got="$(sha256 "${tmp_dir}/${asset}" || true)"
  if [ -n "$got" ]; then
    [ "$got" = "$want" ] || err "checksum mismatch for ${asset}: got ${got}, want ${want}"
    log "checksum ok (${got})"
  else
    log "no sha256 tool found; skipping checksum verification"
  fi
else
  log "checksums.txt unavailable; skipping checksum verification"
fi

# --- install ---------------------------------------------------------------
tar -xzf "${tmp_dir}/${asset}" -C "$tmp_dir"

install_dir="${DBPOD_INSTALL_DIR:-${HOME}/.local/bin}"
mkdir -p "$install_dir"

if [ -f "${tmp_dir}/${BIN_NAME}" ]; then
  mv "${tmp_dir}/${BIN_NAME}" "${install_dir}/${BIN_NAME}"
else
  err "archive did not contain a ${BIN_NAME} binary — asset layout mismatch?"
fi
chmod +x "${install_dir}/${BIN_NAME}"

# --- install requested engines ---------------------------------------------
for e in $ENGINES; do
  log "installing engine ${e} ..."
  "${install_dir}/${BIN_NAME}" engine install "$e" || err "engine install failed: ${e}"
done

case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *)
    log "note: ${install_dir} is not in your PATH"
    log "add it:  export PATH=\"${install_dir}:\$PATH\""
    ;;
esac

printf '\n%s\n' "dbpod installed -> ${install_dir}/${BIN_NAME}"
"$install_dir/${BIN_NAME}" version || true

first_engine=""
for e in $ENGINES; do
  [ -n "$first_engine" ] || first_engine="$e"
done
if [ -n "$first_engine" ]; then
  printf '%s\n' "get started:  dbpod run --name dev --engine ${first_engine}"
else
  printf '%s\n' "get started:  dbpod engine install mysql@8.0"
fi

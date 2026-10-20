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
# Downloads the dbpod binary for your platform from GitHub Releases (with
# automatic fallback to the dl.dbpod.io mirror when github.com is unreachable),
# verifies it against the release checksums, and installs it into ~/.local/bin
# (override with DBPOD_INSTALL_DIR or --install-dir).
#
# Asset naming expected from the release pipeline (dbpod-io/dbpod):
#   dbpod-{os}-{arch}.tar.gz     os: darwin | linux      arch: amd64 | arm64
#   checksums.txt                one sha256 line per release asset

set -eu

REPO="dbpod-io/dbpod"
BIN_NAME="dbpod"
GITHUB_RELEASES="https://github.com/${REPO}/releases"
MIRROR="https://dl.dbpod.io"

# Download sources, tried in order until one serves the asset; the binary and
# its checksums always come from the same origin. The download attempt itself
# is the network probe - no separate reachability check, because release
# assets are served from a different CDN than the github.com page anyway.
# Layouts: g = GitHub (.../latest/download/<f>, .../download/<tag>/<f>),
#          d = dl.dbpod.io (.../latest/<f>, .../<tag>/<f>).
# DBPOD_DOWNLOAD_BASE pins one g-layout source (e.g. a release proxy) and
# disables the fallback.
if [ -n "${DBPOD_DOWNLOAD_BASE:-}" ]; then
  SOURCES="${DBPOD_DOWNLOAD_BASE} g"
else
  SOURCES="${GITHUB_RELEASES} g
${MIRROR} d"
fi

src_file_url() {
  # $1 = base, $2 = layout, $3 = file
  if [ "$2" = g ]; then
    if [ "$DBPOD_VERSION" = "latest" ]; then
      printf '%s/latest/download/%s\n' "$1" "$3"
    else
      printf '%s/download/%s/%s\n' "$1" "$DBPOD_VERSION" "$3"
    fi
  else
    if [ "$DBPOD_VERSION" = "latest" ]; then
      printf '%s/latest/%s\n' "$1" "$3"
    else
      printf '%s/%s/%s\n' "$1" "$DBPOD_VERSION" "$3"
    fi
  fi
}

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
  DBPOD_DOWNLOAD_BASE  replace the GitHub download base with a mirror URL
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

# --- download helpers ------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  # retries cover transient network errors; 404s still fail fast
  fetch() { curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 10 --max-time 300 "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" --tries=3 --waitretry=2 -T 30 "$1"; }
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
src_base=""
src_layout=""
while read -r base layout; do
  [ -n "$base" ] || continue
  if fetch "$(src_file_url "$base" "$layout" "$asset")" "${tmp_dir}/${asset}"; then
    src_base="$base"
    src_layout="$layout"
    break
  fi
  log "source ${base} unavailable, trying next source ..."
done <<EOF
$SOURCES
EOF
if [ -z "$src_base" ]; then
  err "download failed for ${asset} from all sources (set HTTPS_PROXY for a proxy, or DBPOD_DOWNLOAD_BASE to pin a mirror)"
fi

# reject soft-404 hosts that answer with an HTML page: a real asset starts
# with the zip (PK) or gzip magic bytes
magic="$(head -c 4 "${tmp_dir}/${asset}" | od -An -tx1 | tr -d ' \n')"
case "$magic" in
  504b0304 | 1f8b*) ;;
  *) err "${asset} from ${src_base} is not a binary archive - the source served something else (misconfigured mirror?)" ;;
esac

# --- verify checksum -------------------------------------------------------
got=""
if fetch "$(src_file_url "$src_base" "$src_layout" checksums.txt)" "${tmp_dir}/checksums.txt" 2>/dev/null; then
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
  # replacing a running binary is fine on unix, but an mv across a filesystem
  # boundary (e.g. tmpfs /tmp -> disk home) would truncate it in place and hit
  # ETXTBSY - unlink the destination first so the move is always a fresh file
  if [ -e "${install_dir}/${BIN_NAME}" ]; then
    log "replacing existing ${install_dir}/${BIN_NAME}"
    rm -f "${install_dir}/${BIN_NAME}"
  fi
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

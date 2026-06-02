#!/usr/bin/env bash
# Download and extract the AOSP toolchain (clang-r450784e + build-tools + binutils).
# Idempotent: skips download and extract if already present.

set -euo pipefail

# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

if [[ -x "${CLANG_BIN}/clang" ]]; then
  ok "Toolchain already present: ${CLANG_BIN}"
  exit 0
fi

mkdir -p "${TOOLCHAIN_ROOT}"
cd "${PROJECT_ROOT}"

log "Downloading toolchain (3 parts, ~2-3 GB total)..."
for url in "${TOOLCHAIN_URLS[@]}"; do
  name="${TOOLCHAIN_ROOT}/$(basename "$url")"
  if [[ -f "$name" ]]; then
    log "  already downloaded: $(basename "$name")"
  else
    log "  fetching $(basename "$name")"
    curl -fL --retry 3 -o "$name" "$url"
  fi
done

# The tar.gz contains "prebuilts/..." at its top level, so we extract
# from PROJECT_ROOT to land the contents directly under prebuilts/.
log "Concatenating and extracting (split parts are pieces of one tar.gz)..."
cat "${TOOLCHAIN_ROOT}"/toolchain_part_aa.tar.gz \
    "${TOOLCHAIN_ROOT}"/toolchain_part_ab.tar.gz \
    "${TOOLCHAIN_ROOT}"/toolchain_part_ac.tar.gz | tar -xzf -

# Cleanup AppleDouble metadata files and downloaded chunks.
find "${TOOLCHAIN_ROOT}" -maxdepth 1 -name '._*' -delete 2>/dev/null || true
rm -f "${TOOLCHAIN_ROOT}"/toolchain_part_*.tar.gz

if [[ ! -x "${CLANG_BIN}/clang" ]]; then
  die "Extraction finished but clang not found at expected path: ${CLANG_BIN}"
fi

ok "Toolchain ready at ${CLANG_BIN}"
"${CLANG_BIN}/clang" --version | head -1

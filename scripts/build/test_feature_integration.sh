#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPLY="$ROOT/scripts/build/apply_features.sh"
BUILD="$ROOT/scripts/build/build.sh"
COMMON="$ROOT/scripts/build/common.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_grep() {
  local pattern="$1" file="$2" label="$3"
  grep -Eq "$pattern" "$file" || fail "$label"
}

reject_grep() {
  local pattern="$1" file="$2" label="$3"
  ! grep -Eq "$pattern" "$file" || fail "$label"
}

require_grep 'SUPER_BUILDERS_REMOTE=.*Enginex0/Super-Builders' "$COMMON" \
  "common.sh must define Super-Builders as the ZeroMount source"
require_grep 'SUPER_BUILDERS_REMOTE' "$APPLY" \
  "apply_features.sh must fetch Super-Builders for ZeroMount patches"
require_grep '60_zeromount-android13-5\.15\.patch' "$APPLY" \
  "resukisu mode must apply the ZeroMount kernel patch"
reject_grep '51_enhanced_susfs-android13-5\.15\.patch' "$APPLY" \
  "apply_features.sh must not force Super-Builders enhanced SUSFS over ShirkNeko SUSFS tip"
require_grep 'ZeroMount.*lkm' "$APPLY" \
  "lkm mode must explicitly skip ZeroMount"

require_grep 'ZEROMOUNT' "$BUILD" \
  "build.sh must enable/report CONFIG_ZEROMOUNT in resukisu mode"
require_grep 'disable KSU.*disable KSU_SUSFS.*disable ZEROMOUNT|--disable KSU .*--disable KSU_SUSFS .*--disable ZEROMOUNT' "$BUILD" \
  "build.sh must explicitly disable CONFIG_ZEROMOUNT in lkm mode"

reject_grep 'fake_status.*NULL|ksu_selinux_hide_enabled\\).*&& 0|!ksu_selinux_hide_running/1|initialize_fake_status\\(\\);/\\(void\\)0' "$APPLY" \
  "apply_features.sh must not neutralise ReSukiSU/SUSFS SELinux hide"

echo "feature integration checks passed"

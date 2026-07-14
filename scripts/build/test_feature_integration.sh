#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPLY="$ROOT/scripts/build/apply_features.sh"
BUILD="$ROOT/scripts/build/build.sh"
COMMON="$ROOT/scripts/build/common.sh"
WAKELOCK="$ROOT/kernel/power/wakelock.c"
WAKEUP="$ROOT/drivers/base/power/wakeup.c"
WILD_PIN="35fac8ee31035fb73a8b9301b50c2bdb4ff7feb7"

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

reject_grep '^[[:space:]]+(add_timeout_wakelocks_globally|avoid_extra_s2idle_wake_attempts)\.patch$' "$APPLY" \
  "Wild perf must preserve Samsung/GKI wakelock and s2idle wake semantics"
require_grep "WILD_PATCHES_PIN=.*${WILD_PIN}" "$COMMON" \
  "Wild patch source is pinned"
require_grep 'fetch --quiet --depth=1 origin' "$APPLY" \
  "Wild patch pin is fetched explicitly"
require_grep 'checkout --quiet --detach FETCH_HEAD' "$APPLY" \
  "Wild patch checkout is detached from the fetched pin"
reject_grep 'reset --hard origin/HEAD|git clone --depth=1 https://github\.com/WildKernels/kernel_patches\.git' "$APPLY" \
  "Wild patch preparation must not follow a moving branch head"
require_grep '__pm_stay_awake\(wl->ws\);' "$WAKELOCK" \
  "indefinite wakelock semantics remain in the kernel source"
reject_grep '__pm_wakeup_event\(wl->ws, 500\);' "$WAKELOCK" \
  "wakelocks are not truncated to 500 ms"
require_grep 'atomic_inc\(&pm_abort_suspend\);' "$WAKEUP" \
  "every suspend-abort event reaches the s2idle wake path"
reject_grep 'atomic_inc_return_relaxed\(&pm_abort_suspend\)' "$WAKEUP" \
  "later suspend-abort events are not suppressed"

require_grep 'SUPER_BUILDERS_REMOTE=.*Enginex0/Super-Builders' "$COMMON" \
  "common.sh must define Super-Builders as the ZeroMount source"
require_grep 'SUPER_BUILDERS_REMOTE' "$APPLY" \
  "apply_features.sh must fetch Super-Builders for ZeroMount patches"
require_grep '60_zeromount-android13-5\.15\.patch' "$APPLY" \
  "resukisu mode must apply the ZeroMount kernel patch"
require_grep 'fix_zeromount_task_mmu' "$APPLY" \
  "ZeroMount integration must fix task_mmu metadata hook placement"
require_grep '/usr/bin/patch -p1 -F3 -s --no-backup-if-mismatch < "\$\{patch\}"' "$APPLY" \
  "ZeroMount integration must use GNU patch, not PATH-shadowed toybox patch"
reject_grep '51_enhanced_susfs-android13-5\.15\.patch' "$APPLY" \
  "apply_features.sh must not force Super-Builders enhanced SUSFS over ShirkNeko SUSFS tip"
require_grep 'ZeroMount.*lkm' "$APPLY" \
  "lkm mode must explicitly skip ZeroMount"

require_grep 'ZEROMOUNT' "$BUILD" \
  "build.sh must enable/report CONFIG_ZEROMOUNT in resukisu mode"
require_grep 'disable KSU.*disable KSU_SUSFS.*disable ZEROMOUNT|--disable KSU .*--disable KSU_SUSFS .*--disable ZEROMOUNT' "$BUILD" \
  "build.sh must explicitly disable CONFIG_ZEROMOUNT in lkm mode"
require_grep 'git rev-parse --short=7 HEAD' "$BUILD" \
  "build.sh must derive the default build id from the source commit"
require_grep '\$\{KERNEL_TAG\}-\$\{BUILD_ID\}-\$\{PAGE_SIZE_TAG\}' "$BUILD" \
  "kernel localversion must use the short commit build id"
reject_grep 'shuf -i|abogki' "$BUILD" \
  "build.sh must not use random abogki build numbers"
reject_grep 'abogki' "$COMMON" \
  "common.sh naming comments must document the short commit build id"

reject_grep 'fake_status.*NULL|ksu_selinux_hide_enabled\\).*&& 0|!ksu_selinux_hide_running/1|initialize_fake_status\\(\\);/\\(void\\)0' "$APPLY" \
  "apply_features.sh must not neutralise ReSukiSU/SUSFS SELinux hide"

echo "feature integration checks passed"

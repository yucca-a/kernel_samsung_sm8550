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

require_grep 'git rev-parse --short=7 HEAD' "$BUILD" \
  "build.sh must derive the default build id from the source commit"
require_grep '\$\{KERNEL_TAG\}-\$\{BUILD_ID\}-\$\{PAGE_SIZE_TAG\}' "$BUILD" \
  "kernel localversion must use the short commit build id"
reject_grep 'shuf -i|abogki' "$BUILD" \
  "build.sh must not use random abogki build numbers"
reject_grep 'abogki' "$COMMON" \
  "common.sh naming comments must document the short commit build id"

# Performance tuning must not be reintroduced through the build-time patch list.
reject_grep 'apply_wild_perf|APPLY_WILD_PERF|for p in silence_irq_cpu_logspam' "$APPLY" \
  "Wild performance injection is removed"
require_grep 'apply_ptrace_fix' "$APPLY" \
  "the upstream ptrace fix is retained independently of Wild performance tuning"

require_grep '\-e NETFILTER_XT_SET' "$BUILD" \
  "both modes must build the iptables set match into the kernel"
require_grep "CONFIG_NETFILTER_XT_SET=y" "$BUILD" \
  "build.sh must reject an incomplete IP_SET configuration"

require_grep '\-d REKERNEL_LEGACY_NETLINK' "$BUILD" \
  "both modes must explicitly disable legacy ReKernel transport"
reject_grep '\-e REKERNEL_LEGACY_NETLINK' "$BUILD" \
  "build.sh must not force legacy ReKernel transport"
legacy_default=$(sed -n '/^config REKERNEL_LEGACY_NETLINK/,/^endmenu/p' \
  "$ROOT/drivers/rekernel/Kconfig" | grep -E '^[[:space:]]*default ')
[[ "$legacy_default" =~ default[[:space:]]+n$ ]] || fail "ReKernel must default to Generic Netlink"
require_grep 'REKERNEL_MAJOR_VERSION[[:space:]]+"11\.6"' "$ROOT/drivers/rekernel/rekernel.h" \
  "ReKernel must remain on official 11.6"
# The build must never stage a root implementation into this source tree.
python3 "$ROOT/scripts/check_lkm.py" source "$ROOT"
if grep -Eq 'ReSukiSU/|susfs4ksu|Super-Builders|fetch_kernelsu.sh' "$APPLY" "$BUILD"; then
  fail "retired root dependency is still reachable from the build"
fi

echo "feature integration checks passed (LKM only)"

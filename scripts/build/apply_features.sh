#!/usr/bin/env bash
# Apply Root-independent features for the LKM-only kernel.
# Feature flags: APPLY_BBG, APPLY_ZRAM, APPLY_BBR, APPLY_PTRACE_FIX,
# APPLY_UNICODE_FIX, APPLY_NTSYNC, APPLY_DROIDSPACES, APPLY_IPV6_NAT_FIX,
# APPLY_DISABLE_SAMSUNG_SEC (each defaults to 1).

set -euo pipefail

# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

APPLY_BBG="${APPLY_BBG:-1}"
APPLY_ZRAM="${APPLY_ZRAM:-1}"
APPLY_BBR="${APPLY_BBR:-1}"
APPLY_PTRACE_FIX="${APPLY_PTRACE_FIX:-1}"
APPLY_UNICODE_FIX="${APPLY_UNICODE_FIX:-1}"
APPLY_NTSYNC="${APPLY_NTSYNC:-1}"
APPLY_DROIDSPACES="${APPLY_DROIDSPACES:-1}"
APPLY_IPV6_NAT_FIX="${APPLY_IPV6_NAT_FIX:-1}"
APPLY_DISABLE_SAMSUNG_SEC="${APPLY_DISABLE_SAMSUNG_SEC:-1}"

[[ ${MODE:-lkm} == lkm ]] || die "Only lkm is maintained."
[[ ${APPLY_SUSFS:-0} == 0 && ${APPLY_ZEROMOUNT:-0} == 0 ]] || die "Built-in root features have been retired."
python3 "${PROJECT_ROOT}/scripts/check_lkm.py" source "${PROJECT_ROOT}"
cd "${PROJECT_ROOT}"

CACHE_DIR="${PROJECT_ROOT}/.features_cache"
WILD_PATCHES_DIR="${CACHE_DIR}/wild_kernel_patches"
mkdir -p "${CACHE_DIR}"

# ---------- BBG (Baseband-guard) ----------
apply_bbg() {
  log "BBG: running upstream setup.sh in project root..."
  pushd "${PROJECT_ROOT}" >/dev/null
  # BBG setup.sh calls 'realpath --relative-to=...' which the toybox
  # build under prebuilts/build-tools/path does not support; with the
  # build's PATH that toybox shadows GNU coreutils, the realpath call
  # silently returns empty and 'ln -sfn "" ...' fails. Run BBG with the
  # system PATH first so the GNU realpath wins.
  local setup
  setup=$(/usr/bin/mktemp "${CACHE_DIR}/baseband-guard.XXXXXX.sh")
  curl -fLSs --retry 3 -o "${setup}" https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh
  ( export PATH="/usr/bin:/bin:${PATH}"; bash "${setup}" )
  rm -f -- "${setup}"
  popd >/dev/null

  # BBG's Makefile aborts unless 'baseband_guard' is in CONFIG_LSM.
  # The upstream setup.sh only prints the required CONFIG_LSM and does
  # not edit defconfig; do it ourselves.
  local defconfig="${PROJECT_ROOT}/arch/arm64/configs/gki_defconfig"
  if grep -q '^CONFIG_LSM=.*baseband_guard' "${defconfig}"; then
    warn "BBG: baseband_guard already in CONFIG_LSM."
  else
    log "BBG: appending baseband_guard to CONFIG_LSM in gki_defconfig..."
    sed -i 's/^\(CONFIG_LSM="[^"]*\)"$/\1,baseband_guard"/' "${defconfig}"
    grep -q '^CONFIG_LSM=.*baseband_guard' "${defconfig}" \
      || die "BBG: failed to patch CONFIG_LSM (regex did not match)"
  fi
  ok "BBG applied."
}

# ---------- zram default compressor -> lz4 ----------
# Samsung's gki_defconfig sets the zram default compressor to lzo-rle.
# Switch it to lz4: on ARM lz4 has comparable ratio and noticeably
# lower CPU cost, which translates to better foreground responsiveness
# under memory pressure on phones.
#
# Note on naming: the function used to be apply_zram_lz4_neon and tried
# to set CONFIG_CRYPTO_LZ4_NEON=y (Wild Kernels mention NEON LZ4 in
# their README), but that Kconfig symbol does not exist in Samsung
# android13-5.15 -- the kernel has no LZ4 NEON implementation here.
# The kconfig parser silently drops the unknown symbol from .config.
# CRYPTO_LZ4 itself is already enabled (line ~6401 of gki_defconfig),
# so flipping ZRAM_DEF_COMP to "lz4" is the real, working knob.
# The env var name APPLY_ZRAM is kept for backward compatibility.
apply_zram_lz4_neon() {
  local defconfig="${PROJECT_ROOT}/arch/arm64/configs/gki_defconfig"
  if grep -q '^CONFIG_ZRAM_DEF_COMP_LZ4=y' "${defconfig}"; then
    warn "zram LZ4: default compressor already lz4."
    return
  fi
  log "zram: switching default compressor lzo-rle -> lz4..."
  # Disable the old default; enable lz4; and update the string knob.
  sed -i 's|^CONFIG_ZRAM_DEF_COMP_LZORLE=y$|# CONFIG_ZRAM_DEF_COMP_LZORLE is not set|' "${defconfig}"
  if grep -q '^# CONFIG_ZRAM_DEF_COMP_LZ4 is not set$' "${defconfig}"; then
    sed -i 's|^# CONFIG_ZRAM_DEF_COMP_LZ4 is not set$|CONFIG_ZRAM_DEF_COMP_LZ4=y|' "${defconfig}"
  elif ! grep -q '^CONFIG_ZRAM_DEF_COMP_LZ4=y' "${defconfig}"; then
    # Insert next to the (now-disabled) LZORLE marker for tidiness.
    sed -i '/^# CONFIG_ZRAM_DEF_COMP_LZORLE is not set$/a CONFIG_ZRAM_DEF_COMP_LZ4=y' "${defconfig}"
  fi
  sed -i 's|^CONFIG_ZRAM_DEF_COMP="lzo-rle"$|CONFIG_ZRAM_DEF_COMP="lz4"|' "${defconfig}"
  ok "zram: default compressor set to lz4."
}

# ---------- BBR v1 TCP congestion control ----------
apply_bbr() {
  local defconfig="${PROJECT_ROOT}/arch/arm64/configs/gki_defconfig"
  if grep -q '^CONFIG_DEFAULT_BBR=y' "${defconfig}"; then
    warn "BBR already enabled."
    return
  fi
  log "BBR: appending BBR configs to gki_defconfig..."
  cat >> "${defconfig}" <<'EOF'

# Wild Kernels: BBR v1 TCP congestion control
CONFIG_NET_SCH_FQ=y
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR=y
CONFIG_TCP_CONG_CUBIC=y
CONFIG_DEFAULT_BBR=y
# CONFIG_TCP_CONG_BIC is not set
# CONFIG_TCP_CONG_WESTWOOD is not set
# CONFIG_TCP_CONG_HTCP is not set
EOF
  ok "BBR enabled."
}

# ---------- Wild Kernels patch source ----------
prepare_wild_patches() {
  log "Wild patches: fetching kernel_patches @ ${WILD_PATCHES_PIN}..."
  if [[ -d "${WILD_PATCHES_DIR}/.git" ]]; then
    if git -C "${WILD_PATCHES_DIR}" remote get-url origin >/dev/null 2>&1; then
      git -C "${WILD_PATCHES_DIR}" remote set-url origin \
        https://github.com/WildKernels/kernel_patches.git
    else
      git -C "${WILD_PATCHES_DIR}" remote add origin \
        https://github.com/WildKernels/kernel_patches.git
    fi
  else
    mkdir -p "${WILD_PATCHES_DIR}"
    git -C "${WILD_PATCHES_DIR}" init --quiet
    git -C "${WILD_PATCHES_DIR}" remote add origin \
      https://github.com/WildKernels/kernel_patches.git
  fi

  git -C "${WILD_PATCHES_DIR}" fetch --quiet --depth=1 origin \
    "${WILD_PATCHES_PIN}" \
    || die "Wild patches: cannot fetch pin ${WILD_PATCHES_PIN}"
  git -C "${WILD_PATCHES_DIR}" checkout --quiet --detach FETCH_HEAD \
    || die "Wild patches: cannot checkout pin ${WILD_PATCHES_PIN}"

  local resolved
  resolved="$(git -C "${WILD_PATCHES_DIR}" rev-parse HEAD)"
  [[ "${resolved}" == "${WILD_PATCHES_PIN}" ]] \
    || die "Wild patches: resolved ${resolved}, expected ${WILD_PATCHES_PIN}"
  ok "Wild patches: pinned at ${resolved}."
}

# ---------- Upstream ptrace hardening ----------
apply_ptrace_fix() {
  pushd "${PROJECT_ROOT}" >/dev/null
  # Ptrace hardening for 5.15: upstream ~5.16 ptrace-message threading + our
  # ptrace_message zeroing. Vendored in-repo (no Wild dependency for this one).
  local pf="${SCRIPT_DIR}/features/ptrace/gki_ptrace.patch"
  if [[ -f "${pf}" ]]; then
    if patch -p1 -R --dry-run -F3 -s -f --no-backup-if-mismatch < "${pf}" >/dev/null 2>&1; then
      warn "  ↺ already applied: gki_ptrace.patch"
    elif patch -p1 -F3 -s --no-backup-if-mismatch < "${pf}" >/dev/null 2>&1; then
      ok "  + applied: gki_ptrace.patch (ptrace leak fix)"
    else
      warn "  ! skip (does not apply): gki_ptrace.patch"
    fi
  else
    warn "  missing: gki_ptrace.patch"
  fi
  popd >/dev/null
  ok "Ptrace hardening done."
}

# ---------- Wild Kernels: Unicode bypass fix ----------
# Patch path-name handling so non-printable Unicode codepoints can't
# be used to mask /sbin/su etc. against root detectors. Pairs nicely
# with an external root implementation.
apply_unicode_fix() {
  local kv_major kv_minor variant
  kv_major=$(awk '/^VERSION = / {print $3}' "${PROJECT_ROOT}/Makefile")
  kv_minor=$(awk '/^PATCHLEVEL = / {print $3}' "${PROJECT_ROOT}/Makefile")
  if (( kv_major > 6 || (kv_major == 6 && kv_minor >= 1) )); then
    variant="unicode_bypass_fix_6.1+.patch"
  else
    variant="unicode_bypass_fix_6.1-.patch"
  fi
  local file="${WILD_PATCHES_DIR}/common/${variant}"
  [[ -f "${file}" ]] || { warn "Unicode fix: ${variant} missing"; return; }

  pushd "${PROJECT_ROOT}" >/dev/null
  if patch -p1 -R --dry-run -F3 -s -f --no-backup-if-mismatch < "${file}" >/dev/null 2>&1; then
    warn "Unicode fix: already applied."
  elif patch -p1 -F3 -s --no-backup-if-mismatch < "${file}" >/dev/null 2>&1; then
    ok "Unicode fix: ${variant} applied."
  else
    warn "Unicode fix: ${variant} does not apply; skipping."
  fi
  popd >/dev/null
}

# ---------- NTSync (Wine / Proton sync primitives) ----------
# Adds the NTSync subsystem that provides Windows NT-style sync
# objects (semaphore, mutex, event) over a /dev/ntsync chardev.
# Useful for Wine/Proton/Box86 etc. LKM-friendly; no KSU needed.
apply_ntsync() {
  local src="${SCRIPT_DIR}/features/ntsync"
  [[ -f "${src}/ntsync.c" && -f "${src}/ntsync.h" ]] \
    || { warn "NTSync: vendored sources missing in ${src}; skipping"; return; }
  log "NTSync: copying vendored upstream driver from ${src} ..."
  cp -f "${src}/ntsync.c" "${PROJECT_ROOT}/drivers/misc/ntsync.c"
  cp -f "${src}/ntsync.h" "${PROJECT_ROOT}/include/uapi/linux/ntsync.h"

  local misc_kc="${PROJECT_ROOT}/drivers/misc/Kconfig"
  local misc_mk="${PROJECT_ROOT}/drivers/misc/Makefile"

  if ! grep -q '^config NTSYNC' "${misc_kc}"; then
    log "NTSync: inserting Kconfig stanza..."
    python3 - "${misc_kc}" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
stanza = '''
config NTSYNC
\ttristate "NT synchronization primitive emulation"
\tdefault\tm
\thelp
\t  This module provides kernel support for emulation of Windows NT
\t  synchronization primitives. It is not a hardware driver.

\t  To compile this driver as a module, choose M here: the
\t  module will be called ntsync.

\t  If unsure, say N.

'''
# Insert before the final 'endmenu' (or at the end if no endmenu).
idx = src.rfind('\nendmenu')
if idx < 0:
    p.write_text(src + stanza)
else:
    p.write_text(src[:idx] + stanza + src[idx:])
print('  + Kconfig stanza inserted')
PY
  else
    warn "NTSync: Kconfig stanza already present."
  fi

  if ! grep -q '^obj-\$(CONFIG_NTSYNC)' "${misc_mk}"; then
    log "NTSync: adding obj line to drivers/misc/Makefile..."
    printf '\nobj-$(CONFIG_NTSYNC)\t\t+= ntsync.o\n' >> "${misc_mk}"
    ok "  + Makefile obj line appended"
  else
    warn "NTSync: Makefile obj line already present."
  fi

  local defconfig="${PROJECT_ROOT}/arch/arm64/configs/gki_defconfig"
  if ! grep -q '^CONFIG_NTSYNC=y' "${defconfig}"; then
    printf '\n# NTSync (vendored upstream; Wine/Proton sync primitives)\nCONFIG_NTSYNC=y\n' >> "${defconfig}"
    ok "NTSync: CONFIG_NTSYNC=y appended to gki_defconfig."
  fi
}

# ---------- Droidspaces (Linux containers / chroot environments) ----------
# Adds the IPC / namespace / netfilter knobs that allow proper Linux
# container userspaces (Termux Linux, chroot Ubuntu, Docker stub) to
# run inside Android, and applies the ABI-padding patch required by
# CONFIG_SYSVIPC=y on a GKI tree. LKM-friendly.
apply_droidspaces() {
  local kabi="${WILD_PATCHES_DIR}/common/droidspaces/fix_sysvipc_kabi_6_7_8.patch"
  [[ -f "${kabi}" ]] || { warn "Droidspaces: kabi patch missing"; return; }

  pushd "${PROJECT_ROOT}" >/dev/null
  log "Droidspaces: applying fix_sysvipc_kabi patch..."
  if patch -p1 -R --dry-run -F3 -s -f --no-backup-if-mismatch < "${kabi}" >/dev/null 2>&1; then
    warn "  ↺ already applied: fix_sysvipc_kabi_6_7_8.patch"
  elif patch -p1 -F3 -s --no-backup-if-mismatch < "${kabi}" >/dev/null 2>&1; then
    ok "  + applied: fix_sysvipc_kabi_6_7_8.patch"
  else
    warn "  ! skip (does not apply): fix_sysvipc_kabi_6_7_8.patch"
  fi
  popd >/dev/null

  local defconfig="${PROJECT_ROOT}/arch/arm64/configs/gki_defconfig"
  if grep -q '^CONFIG_SYSVIPC=y' "${defconfig}"; then
    warn "Droidspaces: SYSVIPC already enabled, skipping defconfig append."
    return
  fi
  cat >> "${defconfig}" <<'EOF'

# Wild Kernels: Droidspaces (Linux container support)
# IPC
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
# Namespaces
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
# Devtmpfs for hw access in containers
CONFIG_DEVTMPFS=y
# Docker NAT / UFW / Fail2Ban netfilter knobs
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y
EOF
  ok "Droidspaces: configs appended to gki_defconfig."
}

# ---------- IPv6 NAT Fix (Wild Kernels, ported for Samsung) ----------
# Same idea as common/IPv6_NAT_FIX.patch from WildKernels: at build
# time post-process kernel/config_data so /proc/config.gz reports
# CONFIG_IP6_NF_NAT=n even though the running kernel has IPv6 NAT
# enabled. Defeats root-detection scripts that scrape /proc/config.gz.
#
# Wild's upstream patch assumes the GKI 'config_data' rule depends on
# $(KCONFIG_CONFIG); Samsung's sm8550 fork changed it to depend on
# gki_defconfig-stock, so the upstream patch context fails. We do the
# equivalent inline edit (sed insert) directly. Independent of KSU.
apply_ipv6_nat_fix() {
  local mk="${PROJECT_ROOT}/kernel/Makefile"
  [[ -f "${mk}" ]] || { warn "IPv6 NAT Fix: kernel/Makefile missing"; return; }
  if grep -q 'IP6_NF_NAT_FIX_MARKER' "${mk}"; then
    warn "IPv6 NAT Fix: already applied."
    return
  fi

  log "IPv6 NAT Fix: editing kernel/Makefile (Samsung port)..."

  # 1) Insert the config_fix define right after the 'filechk_cat = cat $<' line.
  python3 - "${mk}" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
define_block = '''
# IP6_NF_NAT_FIX_MARKER (Universal kernel)
define config_fix
\techo "kernel: Checking config_data for CONFIG_IP6_NF_NAT..."; \\
\tif grep -q '^CONFIG_IP6_NF_NAT=y' $@; then \\
\t\tsed -i 's/^CONFIG_IP6_NF_NAT=y$$/CONFIG_IP6_NF_NAT=n/' $@; \\
\t\techo "kernel: Hid CONFIG_IP6_NF_NAT (real value still =y at runtime)"; \\
\tfi
endef
'''
needle = 'filechk_cat = cat $<\n'
i = src.find(needle)
if i < 0:
    sys.exit('IPv6 NAT Fix: needle "filechk_cat = cat $<" not found in kernel/Makefile')
ins = i + len(needle)
new = src[:ins] + define_block + src[ins:]

# 2) Append $(Q)$(config_fix) to the config_data recipe.
needle2 = '$(obj)/config_data: arch/arm64/configs/gki_defconfig-stock FORCE\n\t$(call filechk,cat)\n'
if needle2 not in new:
    sys.exit('IPv6 NAT Fix: Samsung config_data rule not found verbatim')
new = new.replace(
    needle2,
    needle2 + '\t$(Q)$(config_fix)\n',
    1,
)
p.write_text(new)
print('IPv6 NAT Fix: inline edit applied')
PY
  ok "IPv6 NAT Fix: applied (Samsung port)."
}

# ---------- Disable Samsung Security Stack ----------
# Append overrides to gki_defconfig disabling Samsung-specific
# anti-root protections plus TRIM_UNUSED_KSYMS (so KSU/other modules
# get the exports they need). Kconfig honours the LAST occurrence so
# appending wins over upstream defaults. Independent of KSU.
apply_disable_samsung_security() {
  local defconfig="${PROJECT_ROOT}/arch/arm64/configs/gki_defconfig"
  local marker='# Universal kernel: disable Samsung security & trim'
  if grep -qF "${marker}" "${defconfig}"; then
    warn "disable Samsung sec: already appended."
    return
  fi
  log "disable Samsung sec: appending overrides to gki_defconfig..."
  cat >> "${defconfig}" <<EOF

${marker}
# CONFIG_UH is not set
# CONFIG_RKP is not set
# CONFIG_KDP is not set
# CONFIG_SECURITY_DEFEX is not set
# CONFIG_INTEGRITY is not set
# CONFIG_FIVE is not set
# CONFIG_TRIM_UNUSED_KSYMS is not set
EOF
  ok "disable Samsung sec: 7 configs disabled."
}

main() {
  log "Applying features (BBG=${APPLY_BBG} zram=${APPLY_ZRAM} BBR=${APPLY_BBR} PtraceFix=${APPLY_PTRACE_FIX} Unicode=${APPLY_UNICODE_FIX} NTSync=${APPLY_NTSYNC} Droidspaces=${APPLY_DROIDSPACES} IPv6NATFix=${APPLY_IPV6_NAT_FIX} DisableSamsungSec=${APPLY_DISABLE_SAMSUNG_SEC})"
  if [[ "${APPLY_UNICODE_FIX}" == "1" ||
        "${APPLY_DROIDSPACES}" == "1" ]]; then
    prepare_wild_patches
  fi
  [[ "${APPLY_BBG}" == "1" ]] && apply_bbg
  [[ "${APPLY_ZRAM}" == "1" ]] && apply_zram_lz4_neon
  [[ "${APPLY_BBR}" == "1" ]] && apply_bbr
  [[ "${APPLY_PTRACE_FIX}" == "1" ]] && apply_ptrace_fix
  [[ "${APPLY_UNICODE_FIX}" == "1" ]] && apply_unicode_fix
  [[ "${APPLY_NTSYNC}" == "1" ]] && apply_ntsync
  [[ "${APPLY_DROIDSPACES}" == "1" ]] && apply_droidspaces
  [[ "${APPLY_IPV6_NAT_FIX}" == "1" ]] && apply_ipv6_nat_fix
  [[ "${APPLY_DISABLE_SAMSUNG_SEC}" == "1" ]] && apply_disable_samsung_security
  ok "All requested features applied."
}

main "$@"

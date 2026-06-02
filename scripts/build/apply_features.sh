#!/usr/bin/env bash
# Apply optional feature patches.
#
# Default is 1 (on) for every flag. SuSFS is the only one that the
# top-level build.sh forces off in lkm mode -- all others are equally
# useful whether KSU is compiled in (resukisu mode) or loaded later
# as a kernel module via init_boot (lkm mode).
#
#   APPLY_SUSFS=1     SuSFS VFS hiding hooks.
#                     NEEDS CONFIG_KSU=y. fs/susfs.c hardcodes 'extern
#                     struct cred *ksu_cred' and other KSU symbols on
#                     hot paths, so the kernel link fails or NULL-derefs
#                     on early VFS calls if KSU is a module.
#   APPLY_BBG=1       Baseband-guard LSM. Independent of KSU. Protects
#                     modem / vbmeta / dtbo from any root user.
#   APPLY_ZRAM=1      Flip zram default compressor lzo-rle -> lz4
#                     (defconfig only). LZ4 NEON in Wild's docs is a
#                     misnomer; we use plain LZ4 which already runs
#                     on ARM NEON code paths.
#   APPLY_BBR=1       BBRv1 TCP congestion control (defconfig only).
#   APPLY_WILD_PERF=1 Wild Kernels common performance / logspam patches.
#                     Independent of KSU.
#   APPLY_UNICODE_FIX=1
#                     fs/unicode/utf8-norm.c bug fix that prevents
#                     non-printable codepoints from being used to
#                     disguise su paths. Independent of KSU.
#   APPLY_NTSYNC=1    Windows NT-style sync primitives for Wine / Proton.
#                     Independent of KSU.
#   APPLY_DROIDSPACES=1
#                     IPC / NS / netfilter knobs for Linux containers.
#                     Independent of KSU.
#
# Re-running the script is safe: each step checks whether the patch
# was already applied before re-applying.

set -euo pipefail

# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

APPLY_SUSFS="${APPLY_SUSFS:-1}"
APPLY_BBG="${APPLY_BBG:-1}"
APPLY_ZRAM="${APPLY_ZRAM:-1}"
APPLY_BBR="${APPLY_BBR:-1}"
APPLY_WILD_PERF="${APPLY_WILD_PERF:-1}"
APPLY_UNICODE_FIX="${APPLY_UNICODE_FIX:-1}"
APPLY_NTSYNC="${APPLY_NTSYNC:-1}"
APPLY_DROIDSPACES="${APPLY_DROIDSPACES:-1}"
APPLY_IPV6_NAT_FIX="${APPLY_IPV6_NAT_FIX:-1}"
APPLY_DISABLE_SAMSUNG_SEC="${APPLY_DISABLE_SAMSUNG_SEC:-1}"

CACHE_DIR="${PROJECT_ROOT}/.features_cache"
SUSFS_REPO_DIR="${CACHE_DIR}/susfs4ksu"
WILD_PATCHES_DIR="${CACHE_DIR}/wild_kernel_patches"
mkdir -p "${CACHE_DIR}"

# ---------- SuSFS ----------
# Converged onto the sm8650/sm8750 approach: pin a susfs4ksu commit, copy the
# fs/ + include/linux/ source drops, then apply the main patch *tolerantly*
# (/usr/bin/patch --forward --fuzz=3) rather than the old strict `git apply`
# which died on any context skew against Samsung's tree. Hunks that the patch
# cannot place are handled by the targeted fixups below; remaining rejects are
# logged (not fatal) so they can be folded into fixups on the next iteration.
apply_susfs() {
  # SuSFS upstream is gitlab.com/simonpunk; we use the GitHub mirror
  # ShirkNeko/susfs4ksu (lockstep with upstream) since gitlab is often
  # unreachable from CN networks. Remote/branch/pin come from common.sh.
  log "SuSFS: clone ${SUSFS_BRANCH} @ ${SUSFS_PIN} from ${SUSFS_REMOTE}..."
  if [[ -d "${SUSFS_REPO_DIR}/.git" ]]; then
    git -C "${SUSFS_REPO_DIR}" remote set-url origin "${SUSFS_REMOTE}"
    git -C "${SUSFS_REPO_DIR}" fetch --quiet --all --prune || true
  else
    git clone --quiet --branch "${SUSFS_BRANCH}" "${SUSFS_REMOTE}" "${SUSFS_REPO_DIR}"
  fi
  git -C "${SUSFS_REPO_DIR}" checkout --quiet "${SUSFS_PIN}" 2>/dev/null \
    || git -C "${SUSFS_REPO_DIR}" checkout --quiet "${SUSFS_BRANCH}"

  local kp="${SUSFS_REPO_DIR}/kernel_patches"
  local patch="${kp}/50_add_susfs_in_gki-android13-5.15.patch"
  [[ -f "${patch}" ]] || die "SuSFS patch missing: ${patch}"

  log "SuSFS: copying fs/ and include/linux/ source drops..."
  cp -rf "${kp}/fs/." "${PROJECT_ROOT}/fs/"
  cp -rf "${kp}/include/linux/." "${PROJECT_ROOT}/include/linux/"

  log "SuSFS: applying main patch (tolerant: --forward --fuzz=3)..."
  ( cd "${PROJECT_ROOT}" && /usr/bin/patch -p1 --forward --fuzz=3 --no-backup-if-mismatch < "${patch}" ) \
    || warn "  some SuSFS hunks did not place cleanly; fixups + reject log below"

  # --- targeted fixups for hunks the patch can't place against Samsung's tree ---
  # (ported from the sm8650/sm8750 trees; refine per build feedback)
  # 1) fs/namespace.c include-area skew: ensure the susfs_def.h include is present.
  if [[ -f "${PROJECT_ROOT}/fs/namespace.c" ]] && ! grep -q "linux/susfs_def.h" "${PROJECT_ROOT}/fs/namespace.c"; then
    perl -0pi -e 's{#include <linux/mnt_idmapping.h>\n}{#include <linux/mnt_idmapping.h>\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux/susfs_def.h>\n#endif\n}' "${PROJECT_ROOT}/fs/namespace.c" || true
  fi
  # 2) selinuxfs: ReSukiSU dropped the fake-selinux-status spoof symbols the
  #    susfs hunk references; neutralise the refs (plain passthrough).
  if [[ -f "${PROJECT_ROOT}/security/selinux/selinuxfs.c" ]]; then
    perl -0pi -e 's/&& ksu_selinux_hide_enabled\)/&& 0)/g; s/data = fake_status;/data = NULL;/g; s/initialize_fake_status\(\);/(void)0;/g' "${PROJECT_ROOT}/security/selinux/selinuxfs.c" || true
  fi

  # Report rejects (non-fatal) so the next iteration can add fixups, then clean.
  local rej; rej=$(find "${PROJECT_ROOT}" -name '*.rej' 2>/dev/null | wc -l)
  if [[ "${rej}" -gt 0 ]]; then
    warn "SuSFS: ${rej} reject(s) remain -- dumping (first 40 lines each):"
    find "${PROJECT_ROOT}" -name '*.rej' -print -exec sed -n '1,40p' {} \; 2>/dev/null || true
  else
    ok "SuSFS: main patch placed with no rejects."
  fi
  log "  setresuid hook present: $(grep -c ksu_handle_setresuid "${PROJECT_ROOT}/kernel/sys.c" 2>/dev/null || echo 0)"
  find "${PROJECT_ROOT}" -name '*.rej' -delete 2>/dev/null || true
  find "${PROJECT_ROOT}" -name '*.orig' -delete 2>/dev/null || true
}

# ---------- BBG (Baseband-guard) ----------
apply_bbg() {
  log "BBG: running upstream setup.sh in project root..."
  pushd "${PROJECT_ROOT}" >/dev/null
  # BBG setup.sh calls 'realpath --relative-to=...' which the toybox
  # build under prebuilts/build-tools/path does not support; with the
  # build's PATH that toybox shadows GNU coreutils, the realpath call
  # silently returns empty and 'ln -sfn "" ...' fails. Run BBG with the
  # system PATH first so the GNU realpath wins.
  local saved_path="${PATH}"
  export PATH="/usr/bin:/bin:${PATH}"
  curl -fsSL https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash
  export PATH="${saved_path}"
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

# ---------- Wild Kernels: common perf + logspam patches ----------
apply_wild_perf() {
  log "Wild perf: cloning kernel_patches from WildKernels GitHub..."
  if [[ -d "${WILD_PATCHES_DIR}/.git" ]]; then
    git -C "${WILD_PATCHES_DIR}" fetch --all --prune
    git -C "${WILD_PATCHES_DIR}" reset --hard origin/HEAD
  else
    git clone --depth=1 https://github.com/WildKernels/kernel_patches.git "${WILD_PATCHES_DIR}"
  fi

  # Curated patch set validated against Samsung android13-5.15.
  # Skipped on purpose:
  #   silence_system_logspam.patch       printk.c fuzz mismatch
  #   IPv6_NAT_FIX.patch                 conflict; we have qlenlen's
  #                                      IPv6 NAT defconfig already
  #   optimise_memcmp.patch              Hunk #2 fails on Samsung's
  #                                      arch/arm64/lib/memcmp.S
  #   re_write_limitation_scaling_min_freq.patch  superseded
  #   use_unlikely_wrap_cpufreq.patch    cpufreq core differs in 5.15
  local patches=(
    # logspam
    silence_irq_cpu_logspam.patch
    # F2FS tuning
    f2fs_enlarge_min_fsync_blocks.patch
    f2fs_reduce_congestion.patch
    reduce_gc_thread_sleep_time.patch
    # ext4 tuning
    increase_ext4_default_commit_age.patch
    # mm / mem operations
    clear_page_16bytes_align.patch
    file_struct_8bytes_align.patch
    disable_cache_hot_buddy.patch
    reduce_cache_pressure.patch
    mem_opt_prefetch.patch
    optimized_mem_operations.patch
    int_sqrt.patch
    # CPU / scheduling
    #   add_limitation_scaling_min_freq.patch  — skip: references
    #   cpu_lp_mask / cpu_perf_mask which only exist on OnePlus
    #   kernels (Samsung has no Little/Big CPU mask split).
    # power management
    add_timeout_wakelocks_globally.patch
    avoid_extra_s2idle_wake_attempts.patch
    minimise_wakeup_time.patch
    reduce_freeze_timeout.patch
    reduce_pci_pme_wakeups.patch
    # network
    increase_sk_mem_packets.patch
    force_tcp_nodelay.patch
  )

  pushd "${PROJECT_ROOT}" >/dev/null
  for p in "${patches[@]}"; do
    local file="${WILD_PATCHES_DIR}/common/${p}"
    [[ -f "${file}" ]] || { warn "  missing: ${p}"; continue; }
    # Reverse check first to know if already applied.
    if patch -p1 -R --dry-run -F3 -s -f --no-backup-if-mismatch < "${file}" >/dev/null 2>&1; then
      warn "  ↺ already applied: ${p}"
      continue
    fi
    if patch -p1 -F3 -s --no-backup-if-mismatch < "${file}" >/dev/null 2>&1; then
      ok "  + applied: ${p}"
    else
      warn "  ! skip (does not apply): ${p}"
    fi
  done
  popd >/dev/null
  ok "Wild perf patches done."
}

# ---------- Wild Kernels: Unicode bypass fix ----------
# Patch path-name handling so non-printable Unicode codepoints can't
# be used to mask /sbin/su etc. against root detectors. Pairs nicely
# with SuSFS.
apply_unicode_fix() {
  if [[ ! -d "${WILD_PATCHES_DIR}/.git" ]]; then
    log "Unicode fix: cloning kernel_patches..."
    git clone --depth=1 https://github.com/WildKernels/kernel_patches.git "${WILD_PATCHES_DIR}"
  fi

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
  if [[ ! -d "${WILD_PATCHES_DIR}/.git" ]]; then
    log "NTSync: cloning kernel_patches..."
    git clone --depth=1 https://github.com/WildKernels/kernel_patches.git "${WILD_PATCHES_DIR}"
  fi
  local base="${WILD_PATCHES_DIR}/common/ntsync/ntsync_base.patch"
  local compat="${WILD_PATCHES_DIR}/common/ntsync/ntsync_compat_android13-5.15.patch"
  [[ -f "${base}" && -f "${compat}" ]] || { warn "NTSync: patches missing"; return; }

  log "NTSync: extracting source files and wiring Kconfig/Makefile..."
  # 'patch -N' for new-file patches in our chain has been flaky --
  # rc varies between runs and the apply silently splits between
  # "file created" and "Kconfig/Makefile not updated", which leaves
  # ntsync.c as an orphan. Avoid the patch tool entirely:
  #   1. extract the new files directly from the unified diffs
  #   2. inline-edit drivers/misc/Kconfig and drivers/misc/Makefile
  #      via sed / Python so the result is deterministic
  python3 - "${base}" "${PROJECT_ROOT}" <<'PY'
import sys, pathlib, re
patch_file = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
text = patch_file.read_text()
# split by "diff --git ..." headers
hunks = re.split(r'(?m)^diff --git ', text)[1:]
for h in hunks:
    head, *rest = h.splitlines()
    m = re.match(r'a/(\S+) b/(\S+)', head)
    if not m:
        continue
    target = root / m.group(2)
    if target.exists() and target.stat().st_size > 0:
        print(f"  -> exists: {target.relative_to(root)} (skip)")
        continue
    # find the '@@ ... @@' marker and take everything after it
    content_lines = []
    in_body = False
    for ln in rest:
        if ln.startswith('@@'):
            in_body = True
            continue
        if in_body:
            if ln.startswith('+'):
                content_lines.append(ln[1:])
            elif ln.startswith(' '):
                content_lines.append(ln[1:])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('\n'.join(content_lines) + '\n')
    print(f"  + wrote: {target.relative_to(root)} ({target.stat().st_size} bytes)")
PY

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
    printf '\n# Wild Kernels: NTSync (Wine/Proton sync primitives)\nCONFIG_NTSYNC=y\n' >> "${defconfig}"
    ok "NTSync: CONFIG_NTSYNC=y appended to gki_defconfig."
  fi
}

# ---------- Droidspaces (Linux containers / chroot environments) ----------
# Adds the IPC / namespace / netfilter knobs that allow proper Linux
# container userspaces (Termux Linux, chroot Ubuntu, Docker stub) to
# run inside Android, and applies the ABI-padding patch required by
# CONFIG_SYSVIPC=y on a GKI tree. LKM-friendly.
apply_droidspaces() {
  if [[ ! -d "${WILD_PATCHES_DIR}/.git" ]]; then
    log "Droidspaces: cloning kernel_patches..."
    git clone --depth=1 https://github.com/WildKernels/kernel_patches.git "${WILD_PATCHES_DIR}"
  fi
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
  log "Applying features (SuSFS=${APPLY_SUSFS} BBG=${APPLY_BBG} zram=${APPLY_ZRAM} BBR=${APPLY_BBR} WildPerf=${APPLY_WILD_PERF} Unicode=${APPLY_UNICODE_FIX} NTSync=${APPLY_NTSYNC} Droidspaces=${APPLY_DROIDSPACES} IPv6NATFix=${APPLY_IPV6_NAT_FIX} DisableSamsungSec=${APPLY_DISABLE_SAMSUNG_SEC})"
  [[ "${APPLY_SUSFS}" == "1" ]] && apply_susfs
  [[ "${APPLY_BBG}" == "1" ]] && apply_bbg
  [[ "${APPLY_ZRAM}" == "1" ]] && apply_zram_lz4_neon
  [[ "${APPLY_BBR}" == "1" ]] && apply_bbr
  [[ "${APPLY_WILD_PERF}" == "1" ]] && apply_wild_perf
  [[ "${APPLY_UNICODE_FIX}" == "1" ]] && apply_unicode_fix
  [[ "${APPLY_NTSYNC}" == "1" ]] && apply_ntsync
  [[ "${APPLY_DROIDSPACES}" == "1" ]] && apply_droidspaces
  [[ "${APPLY_IPV6_NAT_FIX}" == "1" ]] && apply_ipv6_nat_fix
  [[ "${APPLY_DISABLE_SAMSUNG_SEC}" == "1" ]] && apply_disable_samsung_security
  ok "All requested features applied."
}

main "$@"

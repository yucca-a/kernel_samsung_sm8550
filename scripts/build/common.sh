#!/usr/bin/env bash
# Shared variables and helpers for build scripts.
# Do not run directly; source it.

set -euo pipefail

# Resolve project root from this script's location.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd)"

# ---- naming ----
# Kernel localversion follows the same scheme as the sm8650/sm8750 trees:
#   -android<aosp>-<kmi_gen>-<tag>-abogki<buildnum>-4k
# android13-5.15 == KMI generation 5. The random abogki build number is
# generated per build in build.sh (override with BUILD_NUM). Override
# KERNEL_TAG to change the tag (default YuccaA), e.g. the banner becomes
# Linux version 5.15.207-android13-5-YuccaA-abogki123456789-4k ...
KERNEL_TAG="${KERNEL_TAG:-YuccaA}"
ANDROID_BASE="android13"
KMI_GENERATION="5"        # android13-5.15 == KMI generation 5
PAGE_SIZE_TAG="4k"        # SM8550 is 4 KB page-size only

# AnyKernel3 zip prefix. One Image flashes every SM8550 device, so the
# zip keeps the Universal label rather than a single marketing name.
ZIP_PREFIX="SM8550"

# Full list of SM8550 codenames covered by a single Image. AnyKernel3
# accepts unlimited device.nameN entries; this list is rendered into
# anykernel.sh by pack_anykernel.sh and gates do.devicecheck.
SM8550_CODENAMES=(
  # Galaxy S23 family
  dm1q              # S23   (SM-S911)
  dm2q              # S23+  (SM-S916)
  dm3q              # S23U  (SM-S918)
  # Galaxy Z foldables
  q5q               # Z Fold5 (SM-F946)
  b5q               # Z Flip5 (SM-F731)
  # Galaxy Tab S9 family. Samsung uses abbreviated codenames (gts9p/gts9u,
  # NOT gts9plus/gts9ultra) -- the spelled-out forms do not exist and made
  # AnyKernel's do.devicecheck reject Tab S9+/Ultra with "unsupported device".
  gts9              # Tab S9       5G   (SM-X716)
  gts9wifi          # Tab S9       WiFi (SM-X710)
  gts9p             # Tab S9+      5G   (SM-X816)
  gts9pwifi         # Tab S9+      WiFi (SM-X810)
  gts9u             # Tab S9 Ultra 5G   (SM-X916)
  gts9uwifi         # Tab S9 Ultra WiFi (SM-X910)
)

# ---- toolchain configuration ----
# Build with Samsung's own clang-r450784e (the toolchain android13-5.15 shipped
# with; the newer sm8750 clang-r510928 compiles but does NOT boot). Under CI,
# kernel_ci_center fetches our clean repackaging (yucca-a/sm8550-toolchain) and
# exports TOOLCHAIN_DIR -> we use that. Standalone, setup_toolchain.sh
# self-downloads r450784e (3-part split) into ${PROJECT_ROOT}/prebuilts.
TOOLCHAIN_URLS=(
  "https://github.com/YuzakiKokuban/android_kernel_samsung_sm8550_S23/releases/download/toolchain/toolchain_part_aa.tar.gz"
  "https://github.com/YuzakiKokuban/android_kernel_samsung_sm8550_S23/releases/download/toolchain/toolchain_part_ab.tar.gz"
  "https://github.com/YuzakiKokuban/android_kernel_samsung_sm8550_S23/releases/download/toolchain/toolchain_part_ac.tar.gz"
)
TOOLCHAIN_ROOT="${TOOLCHAIN_DIR:-${PROJECT_ROOT}/prebuilts}"
# Auto-detect the clang version dir (CI-provided r450784e prebuilts or the
# self-downloaded one); fall back to the r450784e path before it exists.
_sm8550_clang_dirs=( "${TOOLCHAIN_ROOT}"/clang/host/linux-x86/clang-*/bin )
if [[ -x "${_sm8550_clang_dirs[0]}/clang" ]]; then
  CLANG_BIN="${_sm8550_clang_dirs[0]}"
else
  CLANG_BIN="${TOOLCHAIN_ROOT}/clang/host/linux-x86/clang-r450784e/bin"
fi
BUILDTOOLS_BIN="${TOOLCHAIN_ROOT}/build-tools/linux-x86/bin"
BUILDTOOLS_PATH_BIN="${TOOLCHAIN_ROOT}/build-tools/path/linux-x86"
# kernel-build-tools provides pahole, depmod, mkbootimg, etc. that the
# kernel build expects to find on PATH.
KERNEL_BUILD_TOOLS_BIN="${TOOLCHAIN_ROOT}/kernel-build-tools/linux-x86/bin"

# ---- ReSukiSU (KernelSU) configuration ----
# Use the UPSTREAM ReSukiSU/ReSukiSU setup.sh, tracking main -- same source
# and mechanism as the sm8650/sm8750 trees (we previously pulled the
# YuzakiKokuban fork at a pinned PR commit, which was inconsistent). setup.sh
# clones ReSukiSU into KernelSU/ and wires drivers/kernelsu + Kconfig/Makefile
# (those entries are already committed here, and setup.sh is idempotent).
RESUKISU_SETUP="${RESUKISU_SETUP:-https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh}"
RESUKISU_REF="${RESUKISU_REF:-main}"
KSU_DIR="${PROJECT_ROOT}/KernelSU"

# ---- SuSFS configuration ----
# Pin a known susfs4ksu commit (matches the sm8650/sm8750 approach) instead of
# tracking the moving branch HEAD.
SUSFS_REMOTE="${SUSFS_REMOTE_OVERRIDE:-https://github.com/ShirkNeko/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android13-5.15}"
SUSFS_PIN="${SUSFS_PIN:-cb79a8b35e2387a98645024f432b8d0c7cab6625}"  # susfs4ksu gki-android13-5.15 tip (bumped 2026-06-03: SUS_PATH errno + mnt_id defaults)

# ---- helpers ----
log()  { printf "\e[1;36m[*]\e[0m %s\n" "$*"; }
ok()   { printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[!]\e[0m %s\n" "$*"; }
die()  { printf "\e[1;31m[x]\e[0m %s\n" "$*" >&2; exit 1; }


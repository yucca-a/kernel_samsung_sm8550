#!/usr/bin/env bash
# Shared CLI for the three Samsung trees. Keep this file identical in all three.
# Sourced by the platform build script; init exits early for --help / --check.
kernel_entry_error() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
kernel_entry_usage() {
  cat <<HELP
Usage: ./build.sh [lkm] [options]

  --mode MODE           lkm only (default: lkm)
  --jobs N, -j N        parallel jobs (default: JOBS or 16)
  --pack / --no-pack    build Image with / without AnyKernel3 zip (default: no zip)
  --out-dir DIR         output directory (default: out/<mode>)
  --toolchain-dir DIR   Samsung prebuilts directory
  --anykernel-dir DIR   AnyKernel3 template, needed only with --pack
  --check               validate local prerequisites; no downloads or source edits
  --help, -h            show this help

Relative paths are resolved against the repository root, regardless of cwd.
Environment: MODE, JOBS, OUT_DIR, TOOLCHAIN_DIR, ANYKERNEL_DIR, USE_CCACHE,
CCACHE_DIR, CCACHE_MAXSIZE. CLI options override environment values.
PACK and ZIP_AFTER remain aliases; conflicting values are rejected unless
--pack / --no-pack is supplied. Legacy PACK=1 also copies the zip to ../ for CI.
Set CI_ARTIFACT_DIR to override that copy destination (empty disables copying).
Builds a kernel compatible with external KernelSU LKM; no Root module is bundled.
HELP
}
kernel_entry_init() {
  KROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  source "$KROOT/scripts/build_profile.sh"
  local mode="${MODE:-$BUILD_DEFAULT_MODE}" jobs="${JOBS:-16}"
  local out="${OUT_DIR:-}" tc="${TOOLCHAIN_DIR:-}" ak="${ANYKERNEL_DIR:-}"
  local pack='' mode_seen=0 check=0 legacy_pack="${PACK:-}" arg
  while (( $# )); do
    arg=$1
    case "$arg" in
      --help|-h) kernel_entry_usage; exit 0 ;;
      --check) check=1; shift ;;
      --pack) pack=1; shift ;;
      --no-pack) pack=0; shift ;;
      lkm|resukisu)
        (( mode_seen == 0 )) || kernel_entry_error 'Specify the mode only once.'
        mode=$arg; mode_seen=1; shift ;;
      --mode|--jobs|-j|--out-dir|--toolchain-dir|--anykernel-dir)
        (( $# >= 2 )) && [[ -n $2 && $2 != --* ]] || kernel_entry_error "Missing value for $arg"
        case "$arg" in
          --mode)
            (( mode_seen == 0 )) || kernel_entry_error 'Specify the mode only once.'
            mode=$2; mode_seen=1 ;;
          --jobs|-j) jobs=$2 ;;
          --out-dir) out=$2 ;;
          --toolchain-dir) tc=$2 ;;
          --anykernel-dir) ak=$2 ;;
        esac
        shift 2 ;;
      *) kernel_entry_error "Unknown argument: $arg (see --help)" ;;
    esac
  done
  [[ $mode == lkm ]] || kernel_entry_error "Only lkm is maintained; built-in Root mode '$mode' has been retired."
  [[ ${APPLY_SUSFS:-0} == 0 && ${APPLY_ZEROMOUNT:-0} == 0 ]] ||
    kernel_entry_error 'SUSFS/ZeroMount built-in integration has been retired.'
  [[ $jobs =~ ^[1-9][0-9]*$ ]] || kernel_entry_error 'JOBS must be a positive integer.'
  if [[ -z $pack ]]; then
    if [[ -n ${PACK:-} && -n ${ZIP_AFTER:-} && $PACK != "$ZIP_AFTER" ]]; then
      kernel_entry_error 'PACK and ZIP_AFTER disagree; use --pack or --no-pack.'
    fi
    pack="${PACK:-${ZIP_AFTER:-0}}"
  fi
  [[ $pack == 0 || $pack == 1 ]] || kernel_entry_error 'PACK / ZIP_AFTER must be 0 or 1.'
  [[ ${USE_CCACHE:-1} == 0 || ${USE_CCACHE:-1} == 1 ]] || kernel_entry_error 'USE_CCACHE must be 0 or 1.'
  # Resolve all paths before cd; a repository can be invoked from any directory.
  cd "$KROOT"
  command -v realpath >/dev/null || kernel_entry_error 'Missing realpath (coreutils).'
  if [[ -z $tc ]]; then
    tc="$KROOT/../$BUILD_TOOLCHAIN_REPO/kernel_platform/prebuilts"
    if [[ ! -d $tc && $BUILD_SOC == sm8550 && -d $KROOT/prebuilts ]]; then
      tc="$KROOT/prebuilts"
    fi
  fi
  ak="${ak:-$KROOT/../$BUILD_ANYKERNEL}"
  export MODE="$mode" JOBS="$jobs" PACK="$pack" ZIP_AFTER="$pack"
  export OUT_DIR="$(realpath -m -- "${out:-$KROOT/out/$mode}")"
  export TOOLCHAIN_DIR="$(realpath -m -- "$tc")"
  export ANYKERNEL_DIR="$(realpath -m -- "$ak")"
  export CCACHE_DIR="$(realpath -m -- "${CCACHE_DIR:-${KERNEL_CACHE_ROOT:-$KROOT/.ccache}/$mode}")"
  export CCACHE_BASEDIR="$KROOT" CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-20G}"
  export USE_CCACHE="${USE_CCACHE:-1}"
  # Preserve central CI's explicit PACK=1 contract, without an extra copy for --pack.
  if [[ ! ${CI_ARTIFACT_DIR+x} ]]; then
    CI_ARTIFACT_DIR=''
    [[ $legacy_pack != 1 ]] || CI_ARTIFACT_DIR="$KROOT/.."
  fi
  if [[ -n $CI_ARTIFACT_DIR ]]; then CI_ARTIFACT_DIR="$(realpath -m -- "$CI_ARTIFACT_DIR")"; fi
  export CI_ARTIFACT_DIR
  local cmd clang_bin="$TOOLCHAIN_DIR/clang/host/linux-x86/$BUILD_CLANG/bin"
  for cmd in git make python3 bc bison flex perl patch rsync openssl sha256sum flock; do
    command -v "$cmd" >/dev/null || kernel_entry_error "Missing build dependency: $cmd"
  done
  [[ -x $clang_bin/clang && -x $clang_bin/ld.lld ]] ||
    kernel_entry_error "Missing $BUILD_CLANG at $clang_bin; set --toolchain-dir to installed prebuilts."
  [[ -f $KROOT/arch/arm64/configs/$BUILD_DEFCONFIG ]] || kernel_entry_error "Missing $BUILD_DEFCONFIG"
  if [[ $pack == 1 ]]; then
    command -v zip >/dev/null || kernel_entry_error 'Missing zip.'
    [[ -f $ANYKERNEL_DIR/anykernel.sh && -f $ANYKERNEL_DIR/tools/ak3-core.sh ]] ||
      kernel_entry_error "Invalid AnyKernel3 template: $ANYKERNEL_DIR"
  fi
  # Kbuild must not write into a source directory (or a parent of the source tree).
  python3 - "$KROOT" "$OUT_DIR" <<'PYPATH'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
if out == root or out in root.parents or (root in out.parents and root / 'out' not in out.parents):
    raise SystemExit('Output must be outside the source tree or inside out/<directory>.')
PYPATH
  local state lock previous='' output_identity="$BUILD_SOC $MODE $KROOT"
  state="$(git rev-parse --git-path kernel-source-mode)"
  lock="$(git rev-parse --git-path kernel-build.lock)"
  # --check never creates locks, output directories, cache or mode markers.
  if [[ $check == 0 ]]; then
    exec 9>"$lock"
    flock -n 9 || kernel_entry_error 'Another build is using this source worktree.'
  fi
  if [[ -f $state ]]; then previous=$(cat "$state"); fi
  if [[ -n $previous && $previous != "$MODE" ]]; then
    kernel_entry_error "This source worktree was prepared for $previous. Use a separate clean worktree for $MODE."
  fi
  python3 "$KROOT/scripts/check_lkm.py" source "$KROOT"
  if [[ -f $OUT_DIR/.kernel-build-source && $(cat "$OUT_DIR/.kernel-build-source") != "$output_identity" ]]; then
    kernel_entry_error 'Output directory belongs to another source worktree or mode; choose a different --out-dir.'
  fi
  printf 'Device: %s\nMode: %s\nDefconfig: %s\nToolchain: %s\nJobs: %s\nPack: %s\nOutput: %s\nImage: %s/arch/arm64/boot/Image\n' \
    "$BUILD_SOC" "$MODE" "$BUILD_DEFCONFIG" "$TOOLCHAIN_DIR" "$JOBS" "$PACK" "$OUT_DIR" "$OUT_DIR"
  if [[ $PACK == 1 ]]; then printf 'AnyKernel3: %s\nZip directory: %s\n' "$ANYKERNEL_DIR" "$OUT_DIR"; fi
  "$clang_bin/clang" --version
  "$clang_bin/ld.lld" --version
  if [[ $check == 1 ]]; then echo 'Environment check passed; no build started.'; exit 0; fi
  mkdir -p "$OUT_DIR"
  exec 8>"$OUT_DIR/.kernel-build.lock"
  flock -n 8 || kernel_entry_error 'Another build is using this output directory.'
  # Recheck after locking to prevent two worktrees racing for a fresh output dir.
  if [[ -f $OUT_DIR/.kernel-build-source && $(cat "$OUT_DIR/.kernel-build-source") != "$output_identity" ]]; then
    kernel_entry_error 'Output directory belongs to another source worktree or mode.'
  fi
  printf '%s\n' "$output_identity" > "$OUT_DIR/.kernel-build-source"
  printf '%s\n' "$MODE" > "$state"
}
kernel_publish_zip() {
  local zip=$1
  if [[ -n ${CI_ARTIFACT_DIR:-} ]]; then
    mkdir -p "$CI_ARTIFACT_DIR"
    if [[ $(realpath -m -- "$zip") != "$(realpath -m -- "$CI_ARTIFACT_DIR/$(basename -- "$zip")")" ]]; then
      cp -f -- "$zip" "$CI_ARTIFACT_DIR/"
    fi
    printf 'CI artifact: %s/%s\n' "$CI_ARTIFACT_DIR" "$(basename -- "$zip")"
  fi
}

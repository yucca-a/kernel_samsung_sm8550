#!/usr/bin/env bash
# Source from build.sh; log/warn/die are provided by common.sh.
build_kernel_image() (
  set -euo pipefail
  local out_dir="$1"
  shift
  local image="$out_dir/arch/arm64/boot/Image"
  local attempt build_log real_errors
  local -a status
  for ((attempt=1; attempt<=5; attempt++)); do
    build_log="$out_dir/.make.attempt${attempt}.log"
    # An earlier or partially written Image must never authorize packaging.
    rm -f -- "$image" || return 1
    if make "$@" Image 2>&1 | tee "$build_log"; then
      status=("${PIPESTATUS[@]}")
    else
      status=("${PIPESTATUS[@]}")
    fi
    [[ ${status[1]} -eq 0 ]] || die "Cannot write build log: $build_log"
    if [[ ${status[0]} -eq 0 ]]; then
      python3 - "$image" <<'PYIMAGE' || return 1
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f"Image missing after successful make: {path}")
with path.open('rb') as stream:
    header = stream.read(64)
if len(header) != 64 or header[56:60] != b'ARM\x64':
    raise SystemExit(f"Invalid arm64 Image header: {path}")
PYIMAGE
      log "Build succeeded: $image (attempt $attempt)"
      return 0
    fi
    # Retry only the known temporary-file rename failure, never arbitrary errors.
    real_errors=$(grep 'error:' "$build_log" | grep -vc 'error: unable to rename temporary' || true)
    if (( attempt == 5 || real_errors > 0 )) ||
       ! grep -q 'error: unable to rename temporary' "$build_log"; then
      die "make Image failed (exit ${status[0]}); see $build_log"
    fi
    warn "Temporary-file rename failure on attempt $attempt; retrying..."
  done
)

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/build_profile.sh"
exec bash "$ROOT/$BUILD_NATIVE" "$@"

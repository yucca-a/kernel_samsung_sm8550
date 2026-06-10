#!/usr/bin/env bash
# Set up ReSukiSU (KernelSU) from the UPSTREAM ReSukiSU/ReSukiSU repo via its
# own kernel/setup.sh, tracking the configured ref (default: main). This is the
# same source and mechanism the sm8650/sm8750 trees use. setup.sh clones
# ReSukiSU into KernelSU/, checks out the ref, creates the drivers/kernelsu
# symlink, and adds the Kconfig/Makefile entries (idempotent -- the entries are
# already committed in this tree). KSU sources must resolve at Kconfig-parse
# time even in lkm mode (CONFIG_KSU is only disabled later in .config).

set -euo pipefail

# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

cd "${PROJECT_ROOT}"

log "Setting up ReSukiSU (upstream ReSukiSU/ReSukiSU @ ${RESUKISU_REF}) via setup.sh..."
curl -LSs "${RESUKISU_SETUP}" | bash -s "${RESUKISU_REF}"

# Sanity: the drivers/kernelsu symlink must resolve to a real KernelSU tree.
if [[ ! -e "${PROJECT_ROOT}/drivers/kernelsu/Kconfig" ]]; then
  die "drivers/kernelsu/Kconfig not present after setup.sh (KSU sources missing)"
fi

ok "ReSukiSU staged (KernelSU/ @ ${RESUKISU_REF})"

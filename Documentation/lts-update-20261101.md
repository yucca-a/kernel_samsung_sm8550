# SM8550 Linux 5.15.224 LTS integration (2026-11-01)

Status: **local build and scoped vendor ABI validation passed**.
Merged locally into `codex/build-reliability-netlink-permissions`; published maintenance branch: `main`.
The integration branch is `codex/lts-5.15.224-candidate`. LKM-only maintenance
and the pre-existing local feature/build changes are preserved.

## Source and compatibility

Applied kernel.org incremental patches from 5.15.220 to 5.15.224 using three-way
merges against pristine upstream files. SHA-256 checksums were verified;
OpenPGP signatures were not verified. Exact source URLs and hashes are in
`Documentation/lts-sources-20261101.json`.

Core-owned state uses private allocations or Android KABI reserve slots.
Legacy exports and callback signatures use typed adapters where necessary.
Symbol CRCs are generated normally; module version checks stay enabled.
Implementation details and encoding/lifetime limits are in
`scripts/build/LTS_ABI_20261101.txt`.

Bluetooth inquiry timestamps retain full-width jiffies in private/reserved storage. The ptrace feature patch preserves event messages until the proper stop/resume transition.

This Samsung/Android tree is not byte-identical to vanilla Linux, and these
results do not establish complete upstream CVE coverage.

## Validation results

- Independent fresh worktree, production arm64 defconfig and configured Samsung
  toolchain, `./build.sh lkm`, `PACK=0 ZIP_AFTER=0 USE_CCACHE=0`: **passed**.
- Pre-update local snapshot rebuilt with the corresponding LKM configuration.
- Union of available Android/Galaxy/QCOM symbol lists, restricted to exports
  present in that baseline: **0 differing/missing CRCs of 2978 symbols**.
- Explicit `scripts/build/vendor_abi_types.txt` profile: **0 layout changes across
  85 types** (size, old member offsets and bitfield widths).
- Two feature-preparation runs after the successful build: both passed and
  neither changed the built source fingerprint.
- Root-source guard, shell syntax and `git diff --check`: passed.
- Complete-image inventory still contains 23 changed/missing types
  and 12 differing/missing CRCs of 15562 exports outside the
  selected symbol gate. These are recorded, not hidden or treated as a global
  ABI guarantee. Internal types can change independently of the KMI profile.

The checker does not prove every C member type or runtime behavior. Actual
vendor-module binaries, device boot, storage/display/radio, suspend/resume,
other architectures and allmodconfig were not tested. No AnyKernel package
was produced and no phone was flashed. Compiler/configuration warnings remain
in the complete logs; the build is successful, not claimed warning-free.

## Reproduction and retained evidence

Baseline snapshot: `da2fbd7ce24b20e5cf594660182c98bd8380b308`
(`refs/codex/lts-merge-20261101/sm8550`), including earlier local LKM work.
Validated source snapshot: `c27690e99cb1182fdba7caf7935360b86f511aa0`;
source tree: `6297a5190301519f3ed914956728f157a9be3d60`. That ABI validation predates the README/release metadata update. Release builds are independently rebuilt from the published source commit; see the Release build/ABI manifests.

Artifacts and logs: `/home/yucca/kernels/local-build/lts-merge-20261101`.
Final build: `sm8550-final-build.json` and `sm8550-final-build.log`.
ABI gate: `sm8550-final-vendor-validation.json` (commands and artifact hashes).
Feature stability: `sm8550-final-features.json`.
Whole-image inventory: `sm8550-final-abi-inventory.json`.
Image: `/home/yucca/kernels/local-build/lts-merge-20261101/sm8550-final/out/lkm/arch/arm64/boot/Image`.
The Image's generated version suffix identifies the validated source snapshot.

```sh
./build.sh --check
MODE=lkm PACK=0 ZIP_AFTER=0 USE_CCACHE=0 ./build.sh lkm
symbols=()
for f in android/abi_gki_aarch64 android/abi_gki_aarch64_galaxy \
         android/abi_gki_aarch64_galaxy_grey \
         android/abi_gki_aarch64_galaxy_presubmit android/abi_gki_aarch64_qcom; do
    [ ! -f "$f" ] || symbols+=("$f")
done
python3 scripts/build/check_vendor_abi.py BASELINE_OUT CURRENT_OUT \
  --types-file scripts/build/vendor_abi_types.txt --symbols "${symbols[@]}"
```

Reproduction requires the same feature-cache revisions and toolchain as the
retained final worktree. The feature-prepared build worktree is separate from
the clean source committed to the maintenance branch.

## Publication identity

The three unpublished integration commits were re-attributed to `yucca-a`
using the account-linked GitHub noreply address before publication. Their
source trees are unchanged. Original validation snapshot IDs remain local
evidence; the baseline commit above is the corresponding published tree.

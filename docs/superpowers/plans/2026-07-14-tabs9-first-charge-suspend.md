# Tab S9 First-Charge Suspend Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan.

**Goal:** Preserve Samsung/GKI wakelock and s2idle wake semantics by excluding two high-risk Wild PM patches, make Wild patch inputs reproducible, and verify both supported build modes.

**Architecture:** Keep the shared Samsung SM8550 kernel source and all existing device targets unchanged. Centralize preparation of the Wild patch repository at one immutable commit, then let the existing feature functions consume that prepared tree. Guard the policy at both the build-script layer and the resulting kernel-source layer so a future patch-list edit cannot silently reintroduce the wakeup changes.

**Tech Stack:** Bash build scripts, Git, Linux kernel 5.15.207, Clang r450784e, existing static integration test.

## Global Constraints

- Keep one shared kernel image for S23, Z5, and Tab S9 families.
- Do not change DTB/DTBO, charger drivers, vendor modules, Kconfig defaults, or the kernel version.
- Remove only `add_timeout_wakelocks_globally.patch` and `avoid_extra_s2idle_wake_attempts.patch` from the active Wild performance list.
- Keep `minimise_wakeup_time.patch`, `reduce_freeze_timeout.patch`, and `reduce_pci_pme_wakeups.patch` active.
- Pin Wild patches to `35fac8ee31035fb73a8b9301b50c2bdb4ff7feb7`; abort if that exact object cannot be fetched or checked out.
- Static and build validation cannot replace a fresh-install Tab S9 charge/suspend test; do not describe this as device-proven until that test is performed.

### Task 1: Add failing regression guards

**Files:**
- Modify: `scripts/build/test_feature_integration.sh`
- Test: `scripts/build/test_feature_integration.sh`

**Step 1: Add source paths and policy assertions**

Add these variables below the existing script path variables:

```bash
COMMON="${ROOT}/scripts/build/common.sh"
WAKELOCK="${ROOT}/kernel/power/wakelock.c"
WAKEUP="${ROOT}/drivers/base/power/wakeup.c"
WILD_PIN="35fac8ee31035fb73a8b9301b50c2bdb4ff7feb7"
```

Add these checks before the final success message:

```bash
reject_grep '^[[:space:]]+(add_timeout_wakelocks_globally|avoid_extra_s2idle_wake_attempts)\.patch$' "${APPLY}" \
  "Wild perf must preserve Samsung/GKI wakelock and s2idle wake semantics"
require_grep "WILD_PATCHES_PIN=.*${WILD_PIN}" "${COMMON}" \
  "Wild patch source is pinned"
require_grep 'fetch --quiet --depth=1 origin.*WILD_PATCHES_PIN|fetch --quiet --depth=1 origin[[:space:]]*$' "${APPLY}" \
  "Wild patch pin is fetched explicitly"
require_grep 'checkout --quiet --detach FETCH_HEAD' "${APPLY}" \
  "Wild patch checkout is detached from the fetched pin"
reject_grep 'reset --hard origin/HEAD|git clone --depth=1 https://github\.com/WildKernels/kernel_patches\.git' "${APPLY}" \
  "Wild patch preparation must not follow a moving branch head"
require_grep '__pm_stay_awake\(wl->ws\);' "${WAKELOCK}" \
  "indefinite wakelock semantics remain in the kernel source"
reject_grep '__pm_wakeup_event\(wl->ws, 500\);' "${WAKELOCK}" \
  "wakelocks are not truncated to 500 ms"
require_grep 'atomic_inc\(&pm_abort_suspend\);' "${WAKEUP}" \
  "every suspend-abort event reaches the s2idle wake path"
reject_grep 'atomic_inc_return_relaxed\(&pm_abort_suspend\)' "${WAKEUP}" \
  "later suspend-abort events are not suppressed"
```

Keep the two excluded patch names in comments in `apply_features.sh`; the anchored expression above rejects only active list entries.

**Step 2: Run the regression test and confirm it fails for the current tree**

Run:

```bash
./scripts/build/test_feature_integration.sh
```

Expected: non-zero exit with `FAIL: Wild perf must preserve Samsung/GKI wakelock and s2idle wake semantics`.

### Task 2: Implement the pinned Wild policy and remove the risky patches

**Files:**
- Modify: `scripts/build/common.sh`
- Modify: `scripts/build/apply_features.sh`
- Test: `scripts/build/test_feature_integration.sh`

**Step 1: Define the immutable Wild revision**

Add this configuration block in `common.sh` after the ZeroMount configuration:

```bash
# ---- Wild Kernels patch configuration ----
WILD_PATCHES_PIN="${WILD_PATCHES_PIN:-35fac8ee31035fb73a8b9301b50c2bdb4ff7feb7}"
```

**Step 2: Prepare the Wild repository once at the exact pin**

Add this function before `apply_wild_perf()`:

```bash
prepare_wild_patches() {
  log "Wild patches: fetching kernel_patches @ ${WILD_PATCHES_PIN}..."
  if [[ -d "${WILD_PATCHES_DIR}/.git" ]]; then
    git -C "${WILD_PATCHES_DIR}" remote set-url origin \
      https://github.com/WildKernels/kernel_patches.git
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
```

Remove the independent clone/update blocks from `apply_wild_perf()`, `apply_unicode_fix()`, and `apply_droidspaces()`. In `main()`, call `prepare_wild_patches` once when any of `APPLY_WILD_PERF`, `APPLY_UNICODE_FIX`, or `APPLY_DROIDSPACES` is enabled:

```bash
if [[ "${APPLY_WILD_PERF}" == "1" ||
      "${APPLY_UNICODE_FIX}" == "1" ||
      "${APPLY_DROIDSPACES}" == "1" ]]; then
  prepare_wild_patches
fi
```

**Step 3: Remove the two active list entries and document why**

Delete these entries from the Wild performance patch array:

```text
add_timeout_wakelocks_globally.patch
avoid_extra_s2idle_wake_attempts.patch
```

Add them to the adjacent skip-policy comments:

```bash
#   add_timeout_wakelocks_globally.patch   truncates indefinite wakelocks to 500 ms
#   avoid_extra_s2idle_wake_attempts.patch can suppress later Samsung wake events
```

Leave the following entries active:

```text
minimise_wakeup_time.patch
reduce_freeze_timeout.patch
reduce_pci_pme_wakeups.patch
```

**Step 4: Run focused verification**

Run:

```bash
./scripts/build/test_feature_integration.sh
bash -n scripts/build/common.sh scripts/build/apply_features.sh scripts/build/test_feature_integration.sh
git diff --check
```

Expected: `feature integration checks passed`; the syntax and whitespace checks print no errors.

**Step 5: Commit the implementation**

```bash
git add scripts/build/common.sh scripts/build/apply_features.sh scripts/build/test_feature_integration.sh
git commit -m "fix: preserve Samsung wakeup semantics"
```

### Task 3: Correct lineage and feature documentation

**Files:**
- Modify: `README.md`
- Modify: `CREDITS-LINEAGE.md`

**Step 1: Describe the Wild set as curated**

In both Chinese and English sections, replace claims that the full Wild set or Wild wakeup/power optimization is used with wording that says the set is curated and preserves Samsung/GKI wakelock and s2idle wake semantics. Update the feature table and environment-variable descriptions consistently.

Canonical Chinese sentence:

```text
⚡ **Wild 精选性能补丁** — F2FS/ext4 调优、内存与调度优化及日志降噪；保留三星/GKI 原生 wakelock 与 s2idle 唤醒语义。
```

Canonical English sentence:

```text
⚡ **Curated Wild performance patches** — F2FS/ext4 tuning, memory and scheduler tweaks, and logspam reduction while preserving Samsung/GKI wakelock and s2idle wake semantics.
```

**Step 2: Correct the actual Samsung base commit**

Change the recorded base from `18af2328f923` to `26ae68f5ff6f12d396b3b26d4ab5ef72e7332514`, which matches the current source snapshot and Makefile blob.

**Step 3: Verify the documentation**

Run:

```bash
grep -nE 'Wild (全套|full)|wakeup/power optimizations|18af2328f923' README.md CREDITS-LINEAGE.md
git diff --check
```

Expected: the first command returns no matches and `git diff --check` prints no errors.

**Step 4: Commit the documentation**

```bash
git add README.md CREDITS-LINEAGE.md
git commit -m "docs: document pinned Wild PM policy"
```

### Task 4: Validate clean feature injection for both supported modes

**Files:**
- Verify generated source only; do not commit generated patch state.

**Step 1: Create clean detached verification worktrees**

Use two clean worktrees so `lkm` and `resukisu` patch application cannot contaminate each other:

```bash
git worktree add --detach /home/yucca/.codex/worktrees/sm8550-tabs9-lkm-verify HEAD
git worktree add --detach /home/yucca/.codex/worktrees/sm8550-tabs9-resukisu-verify HEAD
```

**Step 2: Apply features without compiling**

Run in the corresponding worktree:

```bash
./scripts/build/apply_features.sh lkm
./scripts/build/test_feature_integration.sh
```

and:

```bash
./scripts/build/apply_features.sh resukisu
./scripts/build/test_feature_integration.sh
```

Expected for both: exact Wild pin is logged, every configured patch applies successfully, and `feature integration checks passed`.

**Step 3: Confirm resulting PM source semantics**

In each worktree, run:

```bash
grep -n '__pm_stay_awake(wl->ws);' kernel/power/wakelock.c
grep -n 'atomic_inc(&pm_abort_suspend);' drivers/base/power/wakeup.c
! grep -n '__pm_wakeup_event(wl->ws, 500);' kernel/power/wakelock.c
! grep -n 'atomic_inc_return_relaxed(&pm_abort_suspend)' drivers/base/power/wakeup.c
```

Expected: the two stock calls are found and the two high-risk replacements are absent.

### Task 5: Compile both modes and integrate

**Files:**
- Build outputs: `out/lkm/arch/arm64/boot/Image`
- Build outputs: `out/resukisu/arch/arm64/boot/Image`

**Step 1: Build `lkm` in its clean worktree**

```bash
ZIP_AFTER=0 USE_CCACHE=0 ./scripts/build/build.sh lkm
test -s out/lkm/arch/arm64/boot/Image
```

Expected: Clang r450784e is provisioned if absent, the kernel build exits zero, and the Image exists and is non-empty.

**Step 2: Build `resukisu` in its clean worktree**

```bash
ZIP_AFTER=0 USE_CCACHE=0 ./scripts/build/build.sh resukisu
test -s out/resukisu/arch/arm64/boot/Image
```

Expected: the kernel build exits zero and the Image exists and is non-empty.

**Step 3: Final repository verification**

In the implementation worktree, run:

```bash
./scripts/build/test_feature_integration.sh
bash -n scripts/build/common.sh scripts/build/apply_features.sh scripts/build/test_feature_integration.sh
git diff --check
git status --short
```

Expected: tests pass, syntax/whitespace checks report no errors, and the working tree is clean.

**Step 4: Fast-forward and push the authorized update**

From the original `main` worktree:

```bash
git merge --ff-only codex/tabs9-wakeup-fix
git push origin main
```

Expected: `main` fast-forwards to the verified implementation and the remote push succeeds. Report static/build evidence separately from the still-required fresh-install Tab S9 charging test.

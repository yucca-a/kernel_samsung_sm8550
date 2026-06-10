# CREDITS-LINEAGE.md

This file records the full provenance of every component in this
kernel tree. We did **not** press GitHub's "Fork" button on any
upstream repository; this tree was assembled by hand from public
GPL-2.0 (or compatible) sources, with every original copyright
header preserved in the files that were copied or adapted.

Each project below remains the property of its original authors and
is used under its own licence terms.

---

## 1. Kernel base

| Source repository                                                                       | Licence  | What we took                                  |
|-----------------------------------------------------------------------------------------|----------|-----------------------------------------------|
| [samsung-sm8550/kernel_samsung_sm8550-common](https://github.com/samsung-sm8550/kernel_samsung_sm8550-common) (branch `android13-5.15`) | GPL-2.0  | The entire kernel source tree as the initial snapshot. |

The base snapshot was taken at upstream commit
`18af2328f923 ("Merge branch 'android13-5.15-lts' of https://android.googlesource.com/kernel/common")`.

---

## 2. Feature additions

| Component                       | Source repository                                                                                              | Licence  | What we took                                                                                |
|---------------------------------|----------------------------------------------------------------------------------------------------------------|----------|---------------------------------------------------------------------------------------------|
| `drivers/rekernel/`             | [qlenlen/android_kernel_samsung_sm8550](https://github.com/qlenlen/android_kernel_samsung_sm8550) (`ksu`)      | GPL-2.0  | Re:Kernel module (Sakion Team) — binder/signal/network hooks for background app survival.   |
| `drivers/hook_temp/`            | qlenlen/android_kernel_samsung_sm8550                                                                          | GPL-2.0  | kprobe-based battery temperature spoof, default `n`.                                        |
| `mm/memfd-ashmem-shim*`         | qlenlen/android_kernel_samsung_sm8550                                                                          | GPL-2.0  | ashmem ioctl compatibility shim over memfd.                                                 |
| Netfilter/IP_SET defconfig deltas | qlenlen/android_kernel_samsung_sm8550                                                                        | GPL-2.0  | `CONFIG_IP_SET=y` (full family), `CONFIG_IP6_NF_NAT=y`, `CONFIG_IP6_NF_TARGET_MASQUERADE=y`, `CONFIG_NETFILTER_XT_SET=y`. |
| `drivers/knox/` (NGKSM)         | [YuzakiKokuban/android_kernel_samsung_sm8550_S23](https://github.com/YuzakiKokuban/android_kernel_samsung_sm8550_S23) | GPL-2.0  | Samsung Next-Generation Knox Security Manager subsystem.                                    |
| `drivers/kernelsu` symlink + wiring | YuzakiKokuban/android_kernel_samsung_sm8550_S23                                                            | GPL-2.0  | The symlink convention and the corresponding `drivers/Kconfig` + `drivers/Makefile` hooks.  |
| `KERNELSU_VERSION.txt`          | YuzakiKokuban/android_kernel_samsung_sm8550_S23                                                                | GPL-2.0  | The pinned ReSukiSU commit SHA.                                                             |

The build-mode model (`main` = LKM, `resukisu` = ReSukiSU + extras)
follows YuzakiKokuban's design but is implemented independently in
`scripts/build/`.

---

## 3. Runtime-fetched components

These are **not** committed to this repository. Their sources are
downloaded fresh at build time by `scripts/build/`.

| Component   | Source                                                                                                          | Licence    | Purpose                                                  |
|-------------|-----------------------------------------------------------------------------------------------------------------|------------|----------------------------------------------------------|
| ReSukiSU    | [YuzakiKokuban/ReSukiSU](https://github.com/YuzakiKokuban/ReSukiSU)                                             | GPL-2.0    | The KernelSU implementation that `drivers/kernelsu` points to. |
| SuSFS       | [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (`gki-android13-5.15`)                            | GPL-2.0    | Filesystem-level hiding to defeat root detection.        |
| Baseband-guard | [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard)                                 | GPL-2.0    | Carrier-modem leakage protection.                        |
| AOSP toolchain | clang-r450784e + build-tools, [hosted by YuzakiKokuban](https://github.com/YuzakiKokuban/android_kernel_samsung_sm8550_S23/releases/tag/toolchain) | Apache-2.0 | Cross-compilation toolchain matched to Samsung's GKI.    |
| AnyKernel3  | (To be wired up; uses [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3))                              | MIT        | Flashable-zip packaging.                                 |

---

## 4. Optional / referenced

These projects are referenced in design or by name; we have **not**
imported their code into this tree but they are listed for full
disclosure.

| Component  | Source                                                                  | Why mentioned                                                                                       |
|------------|-------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| HymoFS     | [YuzakiKokuban/HymoFS](https://github.com/YuzakiKokuban/HymoFS)         | A kernel-level path-hiding framework. Currently targets `android15-6.6`; backporting to `android13-5.15` is a known follow-up. |
| Kokuban_Kernel_CI_Center | [YuzakiKokuban/Kokuban_Kernel_CI_Center](https://github.com/YuzakiKokuban/Kokuban_Kernel_CI_Center) | The reference CI-driven build orchestrator that informed our `scripts/build/` design. |

---

## Licence summary

- The Linux kernel as a whole (and the entirety of this tree) is
  **GPL-2.0**. Original copyright headers are preserved in every
  imported file.
- Wherever we modified an existing kernel file (`drivers/Kconfig`,
  `drivers/Makefile`, `mm/Kconfig`, `mm/Makefile`,
  `arch/arm64/configs/gki_defconfig`), the modifications consist
  solely of additions and are made under the same GPL-2.0 licence.
- Build scripts under `scripts/build/` are original work, licensed
  GPL-2.0 to match the kernel.
- See each individual file for the authoritative SPDX header.

If you believe attribution is missing or incorrect, please open an
issue.

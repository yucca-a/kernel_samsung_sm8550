# kernel_samsung_sm8550

A unified Linux kernel tree for **all Samsung Galaxy devices on the
SM8550 (Snapdragon 8 Gen 2 "Kalama") platform**, supporting Android 13
and based on Samsung's `kernel_samsung_sm8550-common` (android13-5.15).

**One Image, one zip, every SM8550 device.** The compiled `Image` is
byte-identical regardless of target device; the AnyKernel3 zip lists
every codename below so a single flash works on any of them.

| Device family               | Codenames                                          |
|-----------------------------|----------------------------------------------------|
| Galaxy S23 / S23+ / S23U    | `dm1q`, `dm2q`, `dm3q`                             |
| Galaxy Z Fold5 / Z Flip5    | `q5q`, `b5q`                                       |
| Galaxy Tab S9 series        | `gts9`, `gts9wifi`, `gts9p`, `gts9pwifi`, `gts9u`, `gts9uwifi` |

`do.devicecheck=1` stays on so the zip refuses to flash on a non-SM8550
device (e.g. S24, A55), but accepts any SM8550 in the list.

---

## Branches

This repository maintains two long-lived branches:

| Branch        | Default mode  | Notes                                                                                                                                   |
|---------------|---------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| `main`        | **LKM**       | No root preinstalled. The KernelSU LKM (`.ko`) is built but you decide separately whether to load it. You can still apply root later via the official KernelSU Manager `init_boot` patch flow. |
| `resukisu`    | **ReSukiSU**  | Built-in root via [ReSukiSU](https://github.com/YuzakiKokuban/ReSukiSU), plus **SuSFS** (root hiding), **BBG** (Baseband-guard) and zram LZ4 NEON enabled by default. |

The mode default is taken from the `.kernel_build_mode` marker file in
the working tree; you can always override on the command line.

---

## Quick start

```bash
git clone <this-repo> kernel_samsung_sm8550
cd kernel_samsung_sm8550

# Build the kernel in the branch's default mode and auto-pack a zip.
./scripts/build/build.sh

# Pick the mode explicitly. Either mode works on either branch.
./scripts/build/build.sh lkm
./scripts/build/build.sh resukisu

# Skip toolchain re-download once you have prebuilts/ extracted.
SKIP_TOOLCHAIN_SETUP=1 ./scripts/build/build.sh

# Turn individual features off.
APPLY_BBG=0  ./scripts/build/build.sh resukisu
APPLY_ZRAM=0 ./scripts/build/build.sh

# Stop after Image without packaging.
ZIP_AFTER=0 ./scripts/build/build.sh

# Custom banner tag (default YuccaA).
KERNEL_TAG=YuccaB ./scripts/build/build.sh
```

Outputs:

```
out/<mode>/arch/arm64/boot/Image
out/<mode>/SM8550_<tag>_<base-version>_<MMDD>.zip
```

Flash the zip from any TWRP/OrangeFox on any listed SM8550 device, or
drop the raw `Image` into your stock `boot.img` (e.g. with magiskboot).
DTBs and the dtbo overlay come from the device's existing partitions;
this tree does not regenerate them.

---

## Build prerequisites

- A reasonably current Linux (Ubuntu 22.04+ tested; WSL2 works).
- ~10 GB free disk for sources + toolchain + build output.
- Network access; the toolchain (`prebuilts/`), ReSukiSU (`KernelSU/`),
  SuSFS and BBG patches are all downloaded on demand.
- Standard kernel build deps:

  ```bash
  sudo apt install -y build-essential bc bison flex libssl-dev \
      libelf-dev libncurses5-dev zip curl python3 git ccache \
      libfdt-dev cpio rsync zstd
  ```

The build scripts pull a Samsung-compatible AOSP toolchain
(`clang-r450784e` + `build-tools` + `binutils`) automatically.

---

## Source layout

```
kernel_samsung_sm8550/
├── (Samsung sm8550-common source tree, android13-5.15)
├── drivers/
│   ├── rekernel/     ← Re:Kernel, from qlenlen/android_kernel_samsung_sm8550
│   ├── hook_temp/    ← battery temp spoof module (default n)
│   ├── knox/         ← Samsung NGKSM, from YuzakiKokuban's S23 tree
│   └── kernelsu →    ← symlink to ../KernelSU/kernel (fetched at build time)
├── mm/
│   └── memfd-ashmem-shim*  ← ashmem ioctl shim over memfd
├── KERNELSU_VERSION.txt    ← pinned ReSukiSU SHA
├── .kernel_build_mode      ← branch-default mode marker
├── scripts/build/
│   ├── build.sh            ← main entrypoint
│   ├── common.sh           ← shared variables / device table
│   ├── setup_toolchain.sh
│   ├── fetch_kernelsu.sh
│   └── apply_features.sh   ← SuSFS / BBG / zram LZ4 NEON
├── CREDITS-LINEAGE.md      ← full upstream attribution
└── README.md
```

---

## Optional features (resukisu mode)

| Variable      | Default on `resukisu` | Effect                                                                          |
|---------------|-----------------------|---------------------------------------------------------------------------------|
| `APPLY_SUSFS` | 1                     | Adds [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) hooks to hide KSU from detection. Only sensible with KSU enabled. |
| `APPLY_BBG`   | 1                     | Installs [Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) to keep root state out of carrier modem reports. |
| `APPLY_ZRAM`  | 1                     | Enables `CONFIG_CRYPTO_LZ4_NEON=y` for faster zram on ARM.                      |

LKM mode (`main`) defaults: `APPLY_SUSFS=0`, the others remain on.

---

## Hardening notes

- `CONFIG_HOOK_TEMP` (battery temperature spoof) is included as source
  but defaults to **n**. Enabling it lets the kernel feed a fixed
  temperature reading to userspace; that can defeat thermal protection,
  so leave it off unless you know exactly what you're doing.
- The Samsung Knox security stack (UH / RKP / KDP / SECURITY_DEFEX /
  INTEGRITY / FIVE) is **disabled** in `resukisu` builds because those
  modules actively fight kernel-level root. Re-enable them only when
  building a non-rooted kernel.

---

## Licence and attribution

Everything in this tree inherits the licence of its upstream source.
The Linux kernel and Samsung's contributions are **GPL-2.0**; we keep
every original copyright header intact, and `CREDITS-LINEAGE.md`
records the full chain of provenance.

This is an **independent fork-free downstream** — we have not pressed
GitHub's "Fork" button on any source repository, but each component
remains subject to its own licence. See [`CREDITS-LINEAGE.md`](CREDITS-LINEAGE.md).

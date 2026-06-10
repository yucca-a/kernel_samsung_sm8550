<a id="中文"></a>

**简体中文** · [English ↓](#english)

# kernel_samsung_sm8550

> 一套镜像通刷所有骁龙 8 Gen 2（SM8550 "Kalama"）三星设备的自定义 Android 内核。

![SoC](https://img.shields.io/badge/SoC-Snapdragon_8_Gen_2-0a7bbb)
![Android](https://img.shields.io/badge/Android-13-3ddc84)
![Kernel](https://img.shields.io/badge/Linux-5.15.207-f6a500)
![KMI](https://img.shields.io/badge/KMI-android13--5-9aa0a6)
![Root](https://img.shields.io/badge/Root-ReSukiSU%20%2B%20SUSFS-c2185b)
![License](https://img.shields.io/badge/License-GPL--2.0-2962ff)

基于三星 `kernel_samsung_sm8550-common`（android13-5.15）的统一内核树，面向 **SM8550 平台的全部三星 Galaxy 设备**，搭载 Android 13、Linux 5.15.207。

**一份镜像、一个 zip、通刷每一台 Samsung SM8550 设备。** 编译出的 `Image` 与目标机型无关、逐字节一致；AnyKernel3 zip 内置下方所有 codename，单个 zip 即可刷入列表内任意机型。

> **定位**：本树主要面向 **Samsung 设备**，也只在 Samsung 机型上测试与发布。因为合并了上游 LTS，它理论上也能跑在同 SoC 的其他设备上，但这一点不作保证。

---

## ✨ 特性亮点

> 三仓（sm8550 / sm8650 / sm8750）共享同一套特性集，下面这些是开箱即得的核心能力。

- 🔓 **内置 Root** — ReSukiSU（KernelSU）直接编译进内核（`resukisu` 模式），刷完即 root；另有 `lkm` 纯净模式，root 留到刷入时再注入。
- 🫥 **SUSFS 隐藏** — 把 root、挂载、路径从各类检测中隐藏起来。
- 🧩 **KPM 内核模块** — 支持 SukiSU KPM（管理器里的"核心"），可加载内核态补丁模块。
- 📡 **Baseband-guard** — LSM 级保护 modem / vbmeta / dtbo，任何 root 用户都改不动。
- 🔔 **Re:Kernel** — 内置，提供前后台 / 网络事件通知，便于省电与后台管控。
- ⚡ **Wild 全套性能补丁** — F2FS/ext4 调优、内存与调度优化、唤醒/功耗优化、日志降噪一整套。
- 🎮 **NTSync** — Windows NT 风格同步原语，跑 Wine / Proton 游戏更顺。
- 📦 **Droidspaces 容器** — SYSVIPC / 命名空间 / netfilter 开关，可在 Android 里跑 Linux 容器、chroot。
- 💾 **NTFS3 读写** — OTG 上的 NTFS 盘可读写（含 LZX/XPRESS 压缩）。
- 🗜️ **zram lz4 + BBR** — zram 默认换 lz4（ARM 上更省 CPU），TCP 默认 FQ + BBR。
- 📁 **完整 tmpfs** — POSIX ACL / XATTR / INODE64 全开。
- 🕵️ **IPv6 NAT 隐藏** — 构建期抹掉 `/proc/config.gz` 里的痕迹，绕过基于配置的 root 检测。
- 🛡️ **三星安全栈禁用** — 关闭 UH / RKP / KDP / DEFEX / INTEGRITY / FIVE 等反 root 机制。
- 🚀 **ccache 加速** — 增量编译提速约 60–80%。

### 🔱 SM8550 独有

- 🧷 **One-Image 通刷** — 编译产物逐字节一致，一个 zip 覆盖全部 SM8550 机型（见下表）。

---

## 📱 支持设备

| 设备系列 | Codename |
|---|---|
| Galaxy S23 / S23+ / S23 Ultra | `dm1q`(S911) · `dm2q`(S916) · `dm3q`(S918) |
| Galaxy Z Fold5 / Z Flip5 | `q5q`(F946) · `b5q`(F731) |
| Galaxy Tab S9 / S9+ / S9 Ultra | `gts9`·`gts9wifi`(X716/X710) · `gts9p`·`gts9pwifi`(X816/X810) · `gts9u`·`gts9uwifi`(X916/X910) |

AnyKernel3 zip 保持 `do.devicecheck=1`：拒绝刷入非 SM8550 机型（如 S24、A55），但接受列表内任意 SM8550。

---

## 🌿 分支与模式

仓库维护两条长期分支，模式默认值取自工作区的 `.kernel_build_mode` 标记，命令行可随时覆盖。

| 分支 | 默认模式 | 说明 |
|---|---|---|
| `main` | **LKM** | 不预置 root。KernelSU LKM（`.ko`）会编译出来，但是否加载由你决定；后续也可走官方 KernelSU 管理器的 `init_boot` 补丁流程上 root。 |
| `resukisu` | **ReSukiSU** | 通过 [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) 内置 root，并默认开启 SUSFS、KPM、Baseband-guard 等全套特性。 |

> 两种模式在两条分支上都能用 —— 分支只决定默认值。

---

## 🧩 完整特性一览

| 特性 | resukisu | lkm | 来源 |
|---|:---:|:---:|---|
| ReSukiSU（KernelSU） | 内置 | 刷入时注入 | [ReSukiSU/ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) |
| SUSFS | ✅ | ❌¹ | [ShirkNeko/susfs4ksu](https://github.com/ShirkNeko/susfs4ksu)（`gki-android13-5.15`） |
| KPM（SukiSU 补丁模块） | ✅ | ❌² | 内置 `patch_linux` |
| Baseband-guard | ✅ | ✅ | [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) |
| Re:Kernel | ✅ | ✅ | 内置 `drivers/rekernel` |
| Wild 性能补丁 | ✅ | ✅ | [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches) |
| NTSync（Wine/Proton） | ✅ | ✅ | Linux mainline ³ |
| Droidspaces（容器） | ✅ | ✅ | mainline 配置 + KABI 补丁 ³ |
| Unicode 绕过修复 | ✅ | ✅ | WildKernels |
| NTFS3（+LZX/XPRESS） | ✅ | ✅ | mainline |
| zram 默认 lz4 | ✅ | ✅ | defconfig |
| FQ + BBR | ✅ | ✅ | defconfig |
| 完整 tmpfs（ACL/XATTR/INODE64） | ✅ | ✅ | config |
| IPv6 NAT 隐藏 | ✅ | ✅ | 内置 `config_data` 钩子 |
| 三星安全栈禁用 | ✅ | ✅ | defconfig 覆盖 |
| `gki_ptrace` 信息泄漏修复 | ✅ | ✅ | upstream 修复 ³ |

¹ `lkm` 模式关闭 SUSFS：`fs/susfs.c` 引用了仅在 `CONFIG_KSU=y` 时才链接的 `ksu_*` 符号。
² `KPM` 依赖 KSU，纯 `lkm` 内核无法启用。
³ 标 mainline/upstream 的特性源自 Linux 上游，并非 Wild 首创；构建时我们从 [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches) 取**已适配到本 GKI 版本**的 backport，省去自行回合的工作。真正属于 Wild 的是上面「Wild 性能补丁」那一行（其自有的性能/降噪调优集）。

> `lkm` 模式产出的 `Image` 是真正干净的（零 `ksu_` 字符串）；KernelSU 管理器在刷入时给 `init_boot` 打补丁，运行时用 kprobes/kallsyms 注入未改动的 vmlinux。

---

## 🚀 编译

```bash
git clone <this-repo> kernel_samsung_sm8550
cd kernel_samsung_sm8550

# 按分支默认模式编译，并自动打包 AnyKernel3 zip
./scripts/build/build.sh

# 显式指定模式（两个分支都支持两种模式）
./scripts/build/build.sh lkm
./scripts/build/build.sh resukisu

# 已解压好 prebuilts/ 时，跳过工具链下载
SKIP_TOOLCHAIN_SETUP=1 ./scripts/build/build.sh

# 只编 Image，不打包
ZIP_AFTER=0 ./scripts/build/build.sh

# 自定义 banner 标签（默认 YuccaA）
KERNEL_TAG=YuccaB ./scripts/build/build.sh
```

产物：

```
out/<mode>/arch/arm64/boot/Image          # 内核镜像
AnyKernel3 zip（由 scripts/build/pack_anykernel.sh 生成，命名 SM8550_<tag>_<版本>_<MMDD>.zip）
```

版本号形如 `5.15.207-android13-5-YuccaA-abogki<9位随机>-4k`。

> ⚠️ **工具链与 LTO 不能乱换。** SM8550 必须用三星 `clang-r450784e`（android13-5.15 配套的那版）—— 新的 `clang-r510928` 能编过但**不开机**。LTO 必须用 **ThinLTO**：FULL LTO 会把 16G 的 CI runner OOM 掉，而完全关 LTO 会连带丢掉 CFI、同样产出**不开机**的镜像。脚本已自动选好，独立编译时也会自动下载 r450784e。

### 编译前置

- 较新的 Linux（Ubuntu 22.04+ 实测；WSL2 可用）。
- 约 10 GB 空闲磁盘（源码 + 工具链 + 产物）。
- 联网：工具链（`prebuilts/`）、ReSukiSU、SUSFS、Wild 补丁等均按需下载。
- 标准内核编译依赖：

  ```bash
  sudo apt install -y build-essential bc bison flex libssl-dev \
      libelf-dev libncurses5-dev zip curl python3 git ccache \
      libfdt-dev cpio rsync zstd
  ```

---

## ⚙️ 构建开关（环境变量）

| 变量 | 默认 | 作用 |
|---|---|---|
| `KERNEL_TAG` | `YuccaA` | banner 标签后缀 |
| `JOBS` | `nproc` | 并行编译任务数 |
| `SKIP_TOOLCHAIN_SETUP` | `0` | 设 `1` 信任现有 `prebuilts/`，跳过下载 |
| `ZIP_AFTER` | `1` | 设 `0` 只编 Image 不打包 |
| `USE_CCACHE` | `1` | 设 `0` 关闭 ccache |
| `BUILD_NUM` | 随机 | 固定版本号里的 `abogki` 编号（复现某次发布） |
| `APPLY_SUSFS` | `1`（lkm 强制 `0`） | SUSFS 隐藏钩子（需 KSU） |
| `APPLY_BBG` | `1` | Baseband-guard |
| `APPLY_ZRAM` | `1` | zram 默认压缩器切 lz4 |
| `APPLY_BBR` | `1` | BBR 拥塞控制 |
| `APPLY_WILD_PERF` | `1` | Wild 性能/降噪补丁 |
| `APPLY_UNICODE_FIX` | `1` | Unicode 路径绕过修复 |
| `APPLY_NTSYNC` | `1` | NTSync |
| `APPLY_DROIDSPACES` | `1` | Linux 容器开关 |
| `APPLY_IPV6_NAT_FIX` | `1` | IPv6 NAT 隐藏 |
| `APPLY_DISABLE_SAMSUNG_SEC` | `1` | 禁用三星安全栈 |

---

## 🔐 安全与硬化

- `resukisu` 构建会**禁用**三星 Knox 安全栈（UH / RKP / KDP / DEFEX / INTEGRITY / FIVE），因为它们会主动对抗内核级 root。仅在编译**非 root** 内核时才应重新启用。
- 与 sm8650/sm8750 不同，SM8550 **保留** `HUGEPAGE_POOL` 开启：三星 5.15 的 `mm/kzerod.c` 在 `-Werror` 下依赖它，关掉会因未用函数报错。
- SUSFS / Unicode 修复 / IPv6 NAT 隐藏共同压制常见的 root 检测面。

---

## 📦 刷入

从任意 SM8550 机型的 TWRP / OrangeFox 刷入 zip；或用 magiskboot 把裸 `Image` 塞进你 stock 的 `boot.img`。DTB 与 dtbo 取自设备现有分区，本树不重新生成。

---

## 📜 血统与许可

GPL-2.0。本树派生自：

- **三星** `kernel_samsung_sm8550-common`（android13-5.15）—— 全部三星驱动/HAL 版权归三星所有，GPL-2.0。
- **ReSukiSU / KernelSU**、**SukiSU KPM**、**SUSFS**（ShirkNeko）、**WildKernels** 补丁集、**Baseband-guard**（vc-teahouse）、**Re:Kernel** —— 各自遵循其许可。

本仓库自身的贡献是 mode-driven 构建系统、特性集成与 SM8550 全机型适配。完整溯源见 [`CREDITS-LINEAGE.md`](CREDITS-LINEAGE.md)。这是一个**不点 Fork 按钮的下游树**，每个组件仍受其自身许可约束。

---
---

<a id="english"></a>

[简体中文 ↑](#中文) · **English**

# kernel_samsung_sm8550

> One image flashes every Snapdragon 8 Gen 2 (SM8550 "Kalama") Samsung device.

A unified Linux kernel tree for **all Samsung Galaxy devices on the SM8550 platform**, running Android 13 on Linux 5.15.207, based on Samsung's `kernel_samsung_sm8550-common` (android13-5.15).

**One image, one zip, every Samsung SM8550 device.** The compiled `Image` is byte-identical regardless of target device; the AnyKernel3 zip lists every codename below, so a single zip flashes any of them.

> **Scope:** primarily for **Samsung devices**, and tested/released on Samsung models only. Because it merges upstream LTS it can in principle run on other same-SoC devices too, but that is not guaranteed.

## ✨ Highlights

> All three trees (sm8550 / sm8650 / sm8750) share one feature set — these are available out of the box.

- 🔓 **Built-in root** — ReSukiSU (KernelSU) compiled into the kernel (`resukisu` mode); or a clean `lkm` mode where root is injected at flash time.
- 🫥 **SUSFS hiding** — hides root / mounts / paths from detection.
- 🧩 **KPM** — SukiSU kernel patch module ("核心") support.
- 📡 **Baseband-guard** — LSM-level protection of modem / vbmeta / dtbo from any root user.
- 🔔 **Re:Kernel** — built in; foreground/background and network event notifications.
- ⚡ **Full Wild performance patch set** — F2FS/ext4 tuning, mm & scheduler tweaks, wakeup/power optimizations, logspam silencing.
- 🎮 **NTSync** — Windows NT-style sync primitives for Wine / Proton.
- 📦 **Droidspaces** — IPC / namespace / netfilter knobs for Linux containers & chroots.
- 💾 **NTFS3** — read/write NTFS (OTG), incl. LZX/XPRESS.
- 🗜️ **zram lz4 + BBR** — lz4 default zram compressor, FQ + BBR by default.
- 📁 **Full tmpfs** — POSIX ACL / XATTR / INODE64.
- 🕵️ **IPv6 NAT hidden** — scrubbed from `/proc/config.gz` to defeat config-based root detection.
- 🛡️ **Samsung security stack disabled** — UH / RKP / KDP / DEFEX / INTEGRITY / FIVE off.
- 🚀 **ccache** — ~60–80% faster incremental rebuilds.

**SM8550-only:** byte-identical **One-Image** for the whole SM8550 family.

## 📱 Supported devices

| Family | Codenames |
|---|---|
| Galaxy S23 / S23+ / S23 Ultra | `dm1q` · `dm2q` · `dm3q` |
| Galaxy Z Fold5 / Z Flip5 | `q5q` · `b5q` |
| Galaxy Tab S9 / S9+ / S9 Ultra | `gts9`·`gts9wifi` · `gts9p`·`gts9pwifi` · `gts9u`·`gts9uwifi` |

`do.devicecheck=1` stays on: the zip refuses non-SM8550 devices but accepts any SM8550 in the list.

## 🌿 Branches & modes

| Branch | Default | Notes |
|---|---|---|
| `main` | **LKM** | No preinstalled root; the KernelSU LKM is built but you decide whether to load it. |
| `resukisu` | **ReSukiSU** | Built-in root via [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU), with SUSFS / KPM / Baseband-guard and the full set on by default. |

Either mode works on either branch — the branch only sets the default. The default comes from the `.kernel_build_mode` marker and can be overridden on the command line.

## 🧩 Feature matrix

| Feature | resukisu | lkm | Source |
|---|:---:|:---:|---|
| ReSukiSU (KernelSU) | built-in | flash-time | ReSukiSU/ReSukiSU |
| SUSFS | ✅ | ❌¹ | ShirkNeko/susfs4ksu (`gki-android13-5.15`) |
| KPM | ✅ | ❌² | bundled `patch_linux` |
| Baseband-guard | ✅ | ✅ | vc-teahouse/Baseband-guard |
| Re:Kernel | ✅ | ✅ | in-tree `drivers/rekernel` |
| Wild perf patches | ✅ | ✅ | WildKernels/kernel_patches |
| NTSync | ✅ | ✅ | Linux mainline ³ |
| Droidspaces | ✅ | ✅ | mainline configs + KABI shim ³ |
| Unicode bypass fix | ✅ | ✅ | WildKernels |
| NTFS3 (+LZX/XPRESS) | ✅ | ✅ | mainline |
| zram default lz4 | ✅ | ✅ | config |
| FQ + BBR | ✅ | ✅ | config |
| Full tmpfs (ACL/XATTR/INODE64) | ✅ | ✅ | config |
| IPv6 NAT hidden | ✅ | ✅ | in-tree `config_data` hook |
| Samsung security stack disabled | ✅ | ✅ | defconfig override |
| `gki_ptrace` info-leak fix | ✅ | ✅ | upstream fix ³ |

¹ SUSFS is off in `lkm`: `fs/susfs.c` references `ksu_*` symbols that only link with `CONFIG_KSU=y`.
² `KPM` depends on KSU, so it cannot be enabled in a pure `lkm` kernel.
³ Features marked mainline/upstream originate in upstream Linux, not Wild. At build time we fetch versions **already backported to this GKI tree** from [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches) to avoid re-doing the backport. What is genuinely Wild's is the "Wild perf patches" row (their curated performance/logspam set).

## 🚀 Build

```bash
./scripts/build/build.sh            # branch-default mode + auto-pack zip
./scripts/build/build.sh lkm        # explicit mode
./scripts/build/build.sh resukisu
SKIP_TOOLCHAIN_SETUP=1 ./scripts/build/build.sh   # reuse prebuilts/
ZIP_AFTER=0 ./scripts/build/build.sh              # Image only
KERNEL_TAG=YuccaB ./scripts/build/build.sh        # custom banner tag
```

Output: `out/<mode>/arch/arm64/boot/Image`, plus `SM8550_<tag>_<ver>_<MMDD>.zip` from `pack_anykernel.sh`. Release string: `5.15.207-android13-5-YuccaA-abogki<random>-4k`.

> ⚠️ **Do not swap the toolchain or LTO.** SM8550 needs Samsung `clang-r450784e` — the newer `clang-r510928` compiles but does **not boot**. LTO must be **ThinLTO**: FULL LTO OOM-kills a 16 GB CI runner, and turning LTO fully off silently drops CFI and also yields a non-booting image. The scripts pick this automatically.

Prereqs: a recent Linux (Ubuntu 22.04+/WSL2), ~10 GB free disk, network on first build, and the standard kernel build deps (`build-essential bc bison flex libssl-dev libelf-dev libncurses5-dev zip curl python3 git ccache libfdt-dev cpio rsync zstd`).

## ⚙️ Build switches

Per-feature env toggles (all default `1`, SuSFS forced `0` in lkm): `APPLY_SUSFS`, `APPLY_BBG`, `APPLY_ZRAM`, `APPLY_BBR`, `APPLY_WILD_PERF`, `APPLY_UNICODE_FIX`, `APPLY_NTSYNC`, `APPLY_DROIDSPACES`, `APPLY_IPV6_NAT_FIX`, `APPLY_DISABLE_SAMSUNG_SEC`. Plus `KERNEL_TAG`, `JOBS`, `SKIP_TOOLCHAIN_SETUP`, `ZIP_AFTER`, `USE_CCACHE`, `BUILD_NUM`.

## 🔐 Security & hardening

- `resukisu` builds **disable** Samsung's Knox stack (UH / RKP / KDP / DEFEX / INTEGRITY / FIVE), which actively fights kernel-level root. Re-enable only for a non-rooted build.
- Unlike sm8650/sm8750, SM8550 **keeps** `HUGEPAGE_POOL` on: Samsung's 5.15 `mm/kzerod.c` needs it under `-Werror`.

## 📦 Flashing

Flash the zip from any SM8550 TWRP/OrangeFox, or drop the raw `Image` into your stock `boot.img` with magiskboot. DTB/dtbo come from the device's existing partitions; this tree does not regenerate them.

## 📜 Lineage & license

GPL-2.0, derived from Samsung's `kernel_samsung_sm8550-common` (android13-5.15) plus ReSukiSU/KernelSU, SukiSU KPM, SUSFS (ShirkNeko), WildKernels, Baseband-guard (vc-teahouse) and Re:Kernel — each under its own license. This repo's own contribution is the mode-driven build system, feature integration and full-SM8550 device coverage. Full provenance: [`CREDITS-LINEAGE.md`](CREDITS-LINEAGE.md).

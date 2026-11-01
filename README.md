# kernel_samsung_sm8550

> 2026-11-01 LTS 候选：厂商 ABI 检查尚未通过，不能作为可刷机发布版。原维护分支保留更新前状态。详见 [LTS 更新记录](Documentation/lts-update-20261101.md)。

**维护策略：仅维护 LKM 兼容内核，以 KernelSU 官方 LKM 为适配目标。**

本仓库构建 Samsung SM8550 的自定义内核，基线为 Linux 5.15.224 / Android 13 / KMI 5。
内核不内置 Root 实现，也不生成或附带 `kernelsu.ko`；Root 需要用户另行安装匹配的官方 KernelSU 模块。
LKM 是加载方式，其他 KernelSU 分支也可能提供 LKM；本项目的主要适配目标是官方实现。
实际设备的模块加载、KMI 与启动兼容性仍需验证。

从 2026-11-01 起停止构建 ReSukiSU，移除它的源码下载、Kconfig/Makefile 接入以及 SUSFS、ZeroMount、KPM 的专用集成。
`resukisu` 参数和启用旧特性的环境变量会报错，避免生成与调用者预期不同的镜像。
旧版本说明保留在 [UPDATE-20260909.md](UPDATE-20260909.md) 和 Git 历史中，不代表当前构建功能或验证结果。

## 支持设备

| 设备系列 | Codename |
|---|---|
| Galaxy S23 / S23+ / S23 Ultra | `dm1q`(S911) · `dm2q`(S916) · `dm3q`(S918) |
| Galaxy Z Fold5 / Z Flip5 | `q5q`(F946) · `b5q`(F731) |
| Galaxy Tab S9 / S9+ / S9 Ultra | `gts9`·`gts9wifi`(X716/X710) · `gts9p`·`gts9pwifi`(X816/X810) · `gts9u`·`gts9uwifi`(X916/X910) |

AnyKernel3 zip 保持 `do.devicecheck=1`：拒绝刷入非 SM8550 机型（如 S24、A55），但接受列表内任意 SM8550。

## 保留功能

- Re:Kernel 11.6，使用 Generic Netlink；监控操作和事件订阅要求 `CAP_NET_ADMIN`。
- Baseband-guard LSM。
- NTSync、Droidspaces 容器配置及相关 KABI 修复。
- NTFS3、zram LZ4、FQ + BBR。
- tmpfs 扩展、ipset / `xt_set`、TTL target。
- Unicode 修复、现有 IPv6 NAT 配置处理、三星安全栈配置调整。
- ccache、短提交版本号、平台专用工具链与配置。

这些是内核功能；已移除的 SUSFS / ZeroMount 能力不会由选择 LKM 自动恢复。

## 构建

```bash
./build.sh --check               # 只检查环境，不下载或修改源码
./build.sh --jobs 16             # 默认 lkm，只编 Image
./build.sh --pack                # 编译并生成 AnyKernel3 zip
./build.sh lkm --pack            # 兼容显式 lkm 参数
./build.sh --help
```

配置：`gki_defconfig`；工具链：Samsung `clang-r450784e`。
默认工具链目录：`../toolchain_samsung_sm8550/kernel_platform/prebuilts`。
默认 AnyKernel3 模板：`../AnyKernel3_sm8550`，仅打包时需要。
SM8550 保持 **ThinLTO + CFI**。首次正式构建生成 `.yucca_token`，它需要与配套 ROM 保持一致；更换工作区时应安全沿用同一 ROM 的 token。环境检查不会创建 token。

先安装内核编译依赖与 prebuilts，`--check` 会报告缺失项。独立特性仍按脚本获取 Baseband-guard 和固定版本的 Wild 修复；
构建不再访问 ReSukiSU/BakaSU、susfs4ksu 或 Super-Builders。

| 参数 | 默认 / 作用 |
|---|---|
| `--mode lkm` | 唯一支持的模式，可省略 |
| `--jobs N` / `-j N` | 默认 16 |
| `--pack` / `--no-pack` | 默认不打包 |
| `--out-dir DIR` | 默认 `out/lkm`；可指定仓库外或 `out/` 下的目录 |
| `--toolchain-dir DIR` | Samsung prebuilts |
| `--anykernel-dir DIR` | AnyKernel3 模板 |
| `--check` | 只检查环境及旧 Root 源码残留 |

命令行优先于 `MODE`、`JOBS`、`OUT_DIR`、`TOOLCHAIN_DIR`、`ANYKERNEL_DIR` 环境变量。
相对路径以仓库根目录为基准。`BUILD_ID`（兼容别名 `BUILD_NUM`）控制版本号中的构建标识，默认源码短提交。
`USE_CCACHE=0` 可关闭缓存；默认缓存为 `.ccache/lkm`、上限 `20G`，可通过 `CCACHE_DIR` / `CCACHE_MAXSIZE` 覆盖。

`PACK=1` / `ZIP_AFTER=1` 保留为打包别名；二者冲突时需明确传 `--pack` 或 `--no-pack`。
`PACK=1` 额外复制 zip 到仓库父目录以兼容集中 CI；`CI_ARTIFACT_DIR` 可以指定位置，设空关闭额外复制。
普通 `--pack` 只在输出目录生成 zip。旧脚本路径也使用同一套参数处理。

产物：

```text
out/lkm/arch/arm64/boot/Image
out/lkm/SM8550_LKM_<version>_<MMDD>.zip
```

入口会锁定源码和输出目录。旧工作区如已应用内置 Root 补丁，会要求使用干净 worktree，
不会自动 reset 用户源码；新 worktree 从提交创建，不会带入尚未提交的修改。
最终配置必须启用模块加载和必要的探针/符号支持，并拒绝内置 KSU、SUSFS、ZeroMount、KPM 与强制模块签名配置。
这些检查不能替代完整 Image、ABI 和真机验证。

## 验证

```bash
python3 scripts/test_build_entry.py
bash scripts/build/test_feature_integration.sh
```

入口测试使用模拟 make/编译器并运行真实打包脚本；验证参数、失败退出、旧模式拒绝、锁及配置保护。
`python3 scripts/check_lkm.py source .` 可检查旧源码接入，`config <文件>` 可检查最终配置。

## 来源与许可

GPL-2.0。三星驱动和内核、Re:Kernel、NTSync、Wild 修复、Baseband-guard 等继续保留各自的版权及许可。
历史分支中的 ReSukiSU/KernelSU、SUSFS、ZeroMount 贡献可在 Git 历史和旧版文档中追溯；移除构建依赖不改变这些历史归属。
详细历史来源见 [CREDITS-LINEAGE.md](CREDITS-LINEAGE.md)。

## English

Only the **LKM-compatible kernel** is maintained. Official KernelSU LKM is the primary compatibility target;
this tree contains no built-in Root implementation and does not build or bundle `kernelsu.ko`.
Install a matching external module separately and validate it on the target Samsung firmware.

Use `./build.sh --check`, `./build.sh --jobs 16`, or `./build.sh --pack`.
The optional `lkm` argument remains supported; `resukisu` and retired feature enable flags are rejected.
Outputs are `out/lkm/arch/arm64/boot/Image` and `out/lkm/SM8550_LKM_*.zip`.
CLI paths resolve against the repository root. Toolchain: `clang-r450784e`; defconfig: `gki_defconfig`.
Re:Kernel, Baseband-guard, NTSync, container support and existing independent features remain.
SUSFS/ZeroMount are no longer integrated. Historical documentation describes earlier builds only.

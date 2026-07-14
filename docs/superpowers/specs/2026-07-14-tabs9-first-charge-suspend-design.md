# Tab S9 首次充电休眠修复设计

## 背景

当前统一 SM8550 内核在 Galaxy S23、Z5 和 Tab S9 系列上均可启动，但 Tab S9 在首次刷入后的充电休眠过程中曾出现一次无法唤醒屏幕的问题。该现象同时发生于 `lkm` 和 `resukisu` 模式，之后无法稳定复现。

源码对照确认：

- 当前树的实际三星基线是 `samsung-sm8550/kernel_samsung_sm8550-common` 提交 `26ae68f5ff6f12d396b3b26d4ab5ef72e7332514`，Linux 5.15.207。
- Tab S9 参考树基于 Linux 5.15.178，并保留三星/GKI 原始的 wakelock 与 s2idle 唤醒语义。
- 当前 5.15.207 基线在构建前也保留相同语义；差异由构建阶段默认应用的 Wild PM 补丁引入。
- 2026-06-22 构建所取得的 Wild 提交中，两个相关补丁与当前版本逐字节一致。

## 根因假设

问题是由两个构建期 PM 优化共同扩大休眠竞态窗口造成的：

1. `add_timeout_wakelocks_globally.patch` 把没有显式超时的 wakelock 从 `__pm_stay_awake()` 改成固定 500 ms 的 `__pm_wakeup_event()`。这破坏了调用方“保持到显式释放”的契约，可能让首次启动或充电初始化尚未完成时系统提前进入休眠。
2. `avoid_extra_s2idle_wake_attempts.patch` 只在 `pm_abort_suspend` 从 0 增至 1 时调用 `s2idle_wake()`。若第一次事件发生在 s2idle 尚未进入等待阶段的窄窗口内，后续充电或按键事件只增加计数而不再次执行唤醒，可能造成丢失唤醒。

该问题不要求每次必现。内核代码虽然没有变化，但首次刷入后的 I/O、服务初始化、缓存状态、调度延迟和充电中断顺序与后续启动不同。两个补丁把原本由正确 wakelock 和重复唤醒语义覆盖的时序差异变成竞态，因此一次失败后无法复现不代表潜在错误已经消失。

由于没有处于原始状态的 Tab S9 可进行 A/B，以上结论属于由源码对照支持的高置信度根因假设，而不是真机复现证明。

## 选定方案

恢复已知良好的三星/GKI 行为，只移除下列两个高风险 Wild 补丁：

- `add_timeout_wakelocks_globally.patch`
- `avoid_extra_s2idle_wake_attempts.patch`

保留 alarmtimer、freezer 和 PCI PME 的其他 Wild 功耗调优，因为现有证据未显示它们会丢失唤醒或改变无限期 wakelock 契约。

同时固定 Wild 补丁仓库到提交 `35fac8ee31035fb73a8b9301b50c2bdb4ff7feb7`。该提交是当前源码最后更新时间之前实际可取得的版本，可让后续构建使用相同输入，避免 `origin/HEAD` 漂移重新改变 PM 行为。

## 代码改动

### `scripts/build/common.sh`

- 定义默认的 `WILD_PATCHES_PIN=35fac8ee31035fb73a8b9301b50c2bdb4ff7feb7`，允许通过同名环境变量显式覆盖。

### `scripts/build/apply_features.sh`

- Wild 仓库存在时 fetch 指定提交；不存在时创建浅克隆并取得指定提交。
- 必须检出 `WILD_PATCHES_PIN`；无法取得时终止构建，不回退到移动的 `origin/HEAD`。
- 从 curated patch list 删除两个高风险补丁，并在“有意跳过”注释中说明三星/GKI 兼容性原因。
- 不直接修改 `kernel/power/wakelock.c` 或 `drivers/base/power/wakeup.c`；修复发生在产生问题的构建输入层。

### `scripts/build/test_feature_integration.sh`

- 先加入会在当前实现上失败的检查：两个高风险补丁不得出现在应用列表中。
- 检查 `common.sh` 定义 Wild 固定提交，且 `apply_features.sh` 使用它执行 checkout。
- 检查构建脚本不存在无法取得固定提交时回退到 `origin/HEAD` 的路径。

### 文档

- 把内核基线说明从错误的 `18af2328f923` 修正为实际的 `26ae68f5ff6f`。
- 将 Wild 功耗优化描述限定为仍保留的安全子集，不再声称应用全套 wakeup 优化。

## 验证

1. 修改测试前运行 `scripts/build/test_feature_integration.sh`，确认新增检查因两个补丁仍在列表中或缺少 pin 而失败。
2. 实施修改后再次运行该测试，确认通过。
3. 对改动的 shell 脚本运行 `bash -n`；若环境提供 ShellCheck，再运行 ShellCheck。
4. 在隔离工作树执行 Wild 特性注入，确认：
   - `kernel/power/wakelock.c` 对无显式超时请求仍调用 `__pm_stay_awake()`；
   - `drivers/base/power/wakeup.c` 中 `pm_system_wakeup()` 每次均调用 `s2idle_wake()`；
   - 两个高风险补丁没有出现在最终源码差异中。
5. 分别构建 `lkm` 和 `resukisu` Image，确认两个共享构建路径均成功。
6. 检查最终 Git diff，只包含本设计列出的构建脚本、测试和相关文档。

## 验收边界

静态检查与两个模式的完整构建可以证明危险补丁已从产物中移除，并恢复参考树的关键 PM 语义。由于当前没有可恢复到首次状态的 Tab S9，本次工作不能宣称已通过真机复现证明；下一台首次刷入的 Tab S9 仍应作为最终现场验证。

## 非目标

- 不回退 Linux 5.15.207 LTS 更新。
- 不移除其余三个 Wild PM 调优。
- 不为 Tab S9 添加运行时机型分支，继续保持单一 SM8550 Image。
- 不修改三星 vendor 模块、DTBO、vendor_boot 或用户数据。

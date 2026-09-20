# Endfield_FineTuning

[English](README.md)

本仓库接续 [**stoicswe/Endfield_FineWine**](https://github.com/stoicswe/Endfield_FineWine) —— 那个项目
通过打补丁的 CrossOver,让《明日方舟:终末地》在 Apple Silicon 上越过 ACE 反作弊进入游戏。

本仓库在此基础上做了:

- **DualSense 显示 PS 按键图标,且按键功能正确** —— 两个新的 `winebus.sys` 补丁
- **针对 CrossOver 26.3 编译**(Wine 11.0),而非 26.2
- **实现了 `PsGetProcessExitStatus`** —— 上游保留为 stub,导致 ACE 线程每次运行都 abort
- **一套不随机卡死的图形配置** —— 用 DXMT 替代 D3DMetal,以及真正起作用的那几个 Unity 参数
- **探测工具** —— 不启动游戏就能回答手柄相关问题
- **免 Homebrew、免 `sudo`、免完整 Xcode 的编译方案**

> **这是什么:** 针对 CrossOver(LGPL)Wine 的补丁,加上脚本和文档。**不包含也不分发** CrossOver、
> Wine、Apple 的 Game Porting Toolkit 或游戏本体。

**上游是前置依赖。** 让游戏能跑起来的是上游那 23 个补丁,本仓库不替代它们。

---

## 范围与风险

- **请拥有正版。** 本项目假定你已通过官方启动器安装了正版游戏。
- **这是兼容性工作,不是作弊。** 补丁只是让游戏在非受支持硬件上**能启动**、让手柄**如实报告自己的型号**。
  不提供任何游戏内优势,不修改游戏逻辑,不影响其他玩家。
- **不涉及 DRM 破解。**
- **风险自负。** 在非受支持的配置下运行游戏可能违反其服务条款,是否这样做由你自己决定。见 [LICENSE](LICENSE)。
- **无隶属关系** —— 与鹰角网络/Gryphline、腾讯、CodeWeavers、Apple、索尼、Guavaman Enterprises 均无关联。

**测试环境:** Apple M5 Pro,macOS 27.0,CrossOver 26.3.0,DualSense Edge(`054C:0DF2`)蓝牙连接。

---

## 手柄问题,一段话说清

**在真正的 Windows 上,DualSense 根本不是 XInput 设备** —— XInput 只支持 Xbox 系手柄,DS5Windows、
ViGEm 这类工具存在的理由正是如此。而 Wine 的 SDL 后端会把**任何**手柄标记为 XInput 设备,加上
`&IG_00` / `&XI_00` 后缀。`IG_` 是微软定义的标记,含义是"在 DirectInput 里跳过它、改用 XInput";
按 Rewired 官方文档,所有 XInput 设备会**一律**套用 Xbox 360 映射,且无法回溯到底层 HID 身份。

所以游戏的行为和它在 Windows 上完全一致 —— 只是 Wine 递给它的前提是假的。

补丁一:不再给索尼手柄打这个标记。补丁二:让 SDL 后端输出 DualSense 原生 HID 布局 —— 因为一旦被认成
DualSense,游戏就会按原生布局解析数据。完整过程(含四种**失败**的配置)见
**[docs/03-gamepad-dualsense.md](docs/03-gamepad-dualsense.md)**。

## 目录结构

```
patches/     四个补丁脚本(基于锚点、幂等、不受行号漂移影响)
scripts/     模块替换 / 回滚 / 容器创建,以及启动器
patcher-app/ 图形界面打补丁工具,把你自己的 CrossOver 复制一份并打好补丁
tools/       DirectInput / Raw Input 探针(dienum、padwatch、rawinput)
upstream/    同样的修复,整理成 git 格式补丁,用于提交给 Wine
docs/        编译环境、图形、手柄、踩坑记录
```

## 快速开始

只想玩的话:从 **[Releases](https://github.com/Rarashiken/Endfield_FineTuning/releases/latest)** 下载 **Endfield Patcher**,让它指向你自己的
`CrossOver.app`,它会复制一份并打好补丁 —— 原来那份不会被动。
(源码与自行构建说明在 **[patcher-app/](patcher-app/)**。)

它同时支持 **CrossOver 26.3** 和 **CrossOver Preview 20260821**。有 preview 的话它是更好的基底:
它自带 D3DMetal 4.0b2,游戏内的 DLSS 选项开箱可用,不必手动安装 Apple 的 GPTK4。
preview 需要用它自己建的容器 —— 见 **[scripts/make-preview-bottle.sh](scripts/make-preview-bottle.sh)**。

想自己从头编译:

1. 对与你所装版本匹配的 CrossOver 源码,应用上游的 23 个补丁;
2. 应用本仓库的 `patches/01` 到 `04`;
3. 编译 —— 见 **[docs/01-build-environment.md](docs/01-build-environment.md)**;
4. 用 `scripts/swap-built-modules.sh` 装机,用 `scripts/rollback-modules.sh` 回滚;
5. 用 `scripts/launch-endfield.command` 启动。

启动器选项(每一项都会从容器**回读验证**,而不是只打印意图):

```bash
GFXAPI=d3d11|vulkan   BACKEND=dxmt|d3dmetal   PADMODE=ps|xinput   RETINA=y|n
MSYNC=0|1             NVEXT=0|1               MTL4=0|1            METALFX=0|1
HUD=0|1               GPUSPOOF=0|1|"RTX 4060" CXAPP=/path/to.app  BOTTLE=...
ARGS="..."            LOG=0
```

`HUD=1` 打开性能浮层(需要 `MTL_HUD_ENABLED` 和 `D3DM_SHOW_HUD_STATS` 两个变量,只开一个什么都不显示)。
`GPUSPOOF` 向游戏谎报显卡型号 —— 留着是为了不必重做这个实验,但它掉帧且在这里解锁不了任何东西。

跑完会打印**游戏自己记录的结果** —— 它实际选了哪个渲染器、Metal 4 有没有真的启用 ——
而不是把传进去的参数原样回显。

`PADMODE=ps` 是 DualSense 方案;`PADMODE=xinput` 回到原始行为(手柄可用,图标是 Xbox)。

## 现状

| | |
|---|---|
| ACE 反作弊、进入游戏 | ✅(上游) |
| 针对 26.3 编译 | ✅ |
| `PsGetProcessExitStatus` abort | ✅ 已消除 |
| DualSense 图标 + 按键 | ✅ |
| 高分辨率模式 | ✅ |
| DLSS | ❌ DXMT 的 NVAPI 路径不完整,请用 TAAU 或 FSR |
| DX12 | ❌ 该 Unity 构建里没有 `force-d3d12` |
| 间歇性卡死(约 30%) | ⚠️ 未解决 —— 见 [docs/02](docs/02-graphics-and-stability.md) |
| hidraw 后端的手柄为何游戏读不到 | ⚠️ 未解释 —— 三个假设均已被实测排除,见 [upstream/](upstream/) |

## 致谢

本项目建立在他人的工作之上 —— 见 **[CREDITS.md](CREDITS.md)**。特别感谢
[stoicswe/Endfield_FineWine](https://github.com/stoicswe/Endfield_FineWine)、
[MacGamePadFix](https://github.com/MathiasKowoll/MacGamePadFix)、
[Nicholas Tay 的 DualSense/hidraw 指南](https://nick.tay.blue/2024/01/21/wine-dualsense/),
以及 [Guavaman 的 Rewired 文档](https://guavaman.com/projects/rewired/docs/KnownIssues.html)。

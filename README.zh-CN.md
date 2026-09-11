<div align="center">

# Mac Duo

**合上你的 MacBook，屏幕跟着一起折起来。**

真实铰链角度 → 真实透视 → 真实渐进模糊。
原生实现，GPU 渲染，最高 120 Hz，零第三方依赖。

[English](README.md) · **简体中文** · [日本語](README.ja.md) · [한국어](README.ko.md)

<img src="docs/images/demo.gif" width="720" alt="Mac Duo —— 屏幕随开合在透视中折叠并渐进模糊">

<sub>合成渲染扫帧，开合度 0 % → 100 % · 乒乓循环，画面为合成内容（不含任何个人桌面）</sub>

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20Apple%20Silicon-black?logo=apple&logoColor=white)](#环境要求)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](#代码结构)
[![Metal](https://img.shields.io/badge/Metal-MPS%20Gaussian-5C54E8?logo=metal&logoColor=white)](#工作原理)
[![Dependencies](https://img.shields.io/badge/dependencies-none-3fb950)](#环境要求)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[![Download](https://img.shields.io/github/v/release/Toketec/mac-duo?label=download&color=2ea44f&logo=apple&logoColor=white)](https://github.com/Toketec/mac-duo/releases/latest)
[![Stars](https://img.shields.io/github/stars/Toketec/mac-duo?style=flat&color=f0c419)](https://github.com/Toketec/mac-duo/stargazers)

</div>

---

如果你玩过折叠屏手机的开合动效，并且希望自己的笔记本也能这样：这就是那件事，而且是认真做的版本。它读取 MacBook 的**真实铰链角度**，把桌面按"你坐着没动"的固定视点重新投影到正在旋转的屏幕上，在面板远离视线的方向叠加**具有物理依据的渐进模糊**，然后在屏幕摊开的那一刻彻底让路。

没有任何定时器假装角度，也没有滑块假装开合。屏幕转一度，画面就跟着转一度。

> **说清楚边界：** 这是一个受折叠屏开合动效启发、针对 MacBook 底部铰链重新实现的独立作品，**不是**任何 iOS 动画的逐像素移植；不包含任何 Apple 素材、固件或私有框架，并使用了一个**未文档化**的 Apple HID 传感器（见[边界与实话](#边界与实话)）。

## 目录

- [亮点](#亮点)
- [工作原理](#工作原理)
- [控制面板](#控制面板)
- [角度映射](#角度映射)
- [环境要求](#环境要求)
- [构建与运行](#构建与运行)
- [验证与性能测试](#验证与性能测试)
- [性能数据](#性能数据)
- [隐私](#隐私)
- [代码结构](#代码结构)
- [常见问题](#常见问题)
- [边界与实话](#边界与实话)
- [致谢](#致谢)
- [许可](#许可)

## 亮点

| | |
|---|---|
| 🔗 **真实角度跟随** | 运动中以 **8 ms**、静止时以 **33 ms** 采样屏幕铰链角度，按时间做平滑，无过冲。 |
| 📐 **固定视点投影** | 视点钉在键盘所在的空间里，面板旋转时内容顶部保持原有物理高度——你看到的是"折叠"，不是"拉伸"。 |
| 🌫️ **真高斯模糊** | 1 → 1/2 → 1/4 → 1/8 的 Metal Performance Shaders 高斯金字塔，按半径连续混合，是景深而不是一层不透明度。 |
| ⚡ **120 Hz，常驻 GPU** | CADisplayLink 跟随内置屏刷新；透视与模糊全部在 GPU 完成并写入可复用的共享缓冲，没有逐帧 `malloc`，没有 CPU 全图复制。 |
| 🪟 **原生菜单栏应用** | 以 accessory 应用运行，面板是 popover。覆盖层穿透鼠标，永不抢键盘焦点。 |
| 🔒 **零依赖** | 只用 Apple Command Line Tools 与系统框架，无包管理、无下载、无网络。 |
| 🙈 **数据不出本机** | 仅在屏幕运动时抓帧，全程内存中处理，不落盘、不上传。 |

## 工作原理

```
┌──────────────┐   HID 特征报告    ┌──────────────────┐   Metal + MPS    ┌──────────────┐
│ 铰链传感器    │ ───────────────► │ FoldState        │ ───────────────► │ 覆盖层        │
│ （只读）      │  8 ms / 33 ms    │ 映射·平滑·预览    │  透视 + 高斯 + 暗化│ 仅内置屏      │
└──────────────┘                  └──────────────────┘                  └──────────────┘
```

1. **采样。** 通过只读的 IOKit HID 特征报告取得当前铰链角度。读取器从不写入报告，也从不触碰传感器校准。轮询频率随运动自适应（运动时 8 ms，静止 33 ms），报告中断时自动断开重连。
2. **映射。** `FoldMath.openness` 把角度映射为进度，区间可校准。`FoldMath.referenceUV` 用一个**固定视点**做射线／平面求交，重新投影每个像素：视点在面板前方 `2.4 ×` 面板长度处，高度对齐完全展开时面板顶部的世界高度。面板旋转时这个高度保持不变——这正是动作看起来像"折"而不是"压扁"的原因。铰链边是固定轴，上方多出的区域留黑，投影超出物理屏幕的部分直接裁切而不是拉伸。
3. **渲染。** 投影结果经过多级高斯金字塔并按半径连续混合，再向铰链方向叠加暗化。成品由 GPU 写入可复用的共享缓冲，交给原生 AppKit 视图绘制——刻意避开透明菜单栏应用中 `CAMetalLayer` 的呈现故障。

各层时序彼此独立：几何跟随 display link（最高 120 Hz），桌面源抓取最高 60 Hz，传感器轮询最高 125 Hz。`FoldState` 用指数逼近做平滑（时间常数 45 ms，无过冲），45° 以下保持收拢终态，不会在不可见的角度区间消耗过渡进度。

## 控制面板

<div align="center">
<img src="docs/images/control-panel.png" width="420" alt="Mac Duo 控制面板：实时铰链角度、动画区间与状态">

<sub>实时铰链角度、可校准的动画区间、一键预览、授权状态，全在菜单栏 popover 里。</sub>
</div>

面板刻意采用不透明底色，按钮在按下、选中、失焦时都保持明确的文字对比度。它浮在动画覆盖层**之上**，所以你可以一边调参数一边看背后的效果；面板本身始终清晰，开合效果不会作用在自己身上。

## 角度映射

<div align="center">
<table>
<tr>
<td><img src="docs/images/fold-0.png" width="180" alt="开合度 0%"></td>
<td><img src="docs/images/fold-25.png" width="180" alt="开合度 25%"></td>
<td><img src="docs/images/fold-50.png" width="180" alt="开合度 50%"></td>
<td><img src="docs/images/fold-75.png" width="180" alt="开合度 75%"></td>
<td><img src="docs/images/fold-100.png" width="180" alt="开合度 100%"></td>
</tr>
<tr align="center">
<td><sub>收拢</sub></td>
<td><sub>25 %</sub></td>
<td><sub>50 %</sub></td>
<td><sub>75 %</sub></td>
<td><sub>恢复桌面</sub></td>
</tr>
</table>
</div>

| 铰链角度 | 你看到什么 |
|---|---|
| **≥ 上限**（默认 **135°**） | 效果关闭——你的真实桌面，零开销。 |
| **上限 → 45°** | 连续折叠：透视、渐进模糊、铰链暗化实时跟随开合。 |
| **≤ 45°** | 保持收拢终态——真正不可见的区间不做动画。 |
| **校准** | 把屏幕停在你希望"完全清晰"的角度，点「以当前角度校准」（限制在 65°–135°）。不修改硬件，只调整映射。 |
| **传感器丢失／完全合盖** | 自动回到清晰桌面；读取器自行重连。 |

## 环境要求

- Apple Silicon Mac（本仓库在 M2 Max 上构建与实测）
- macOS 14 或更新版本
- Apple Command Line Tools（`xcode-select --install`）——不需要 Xcode 工程，也不需要包管理器
- 屏幕录制权限（完整桌面效果需要）——*可选，但这里最容易踩坑：* 未授权时应用会回退成暗色模糊／变暗覆盖层，看起来就是**黑屏**（见[构建与运行](#构建与运行)里的说明）。

## 构建与运行

### 预编译产物（最快上手）

**⬇️ [下载最新 Release](https://github.com/Toketec/mac-duo/releases/latest)** 直接获取二进制；仓库内的 `dist/` 目录也提供可直接运行的 **`Mac Duo.app`** 以及 `MacDuo-1.2.0-arm64.zip`——Apple Silicon、macOS 14+、ad-hoc 签名。

```sh
git clone https://github.com/Toketec/mac-duo.git
cd mac-duo
xattr -dr com.apple.quarantine 'dist/Mac Duo.app'   # 清除下载隔离标记
open 'dist/Mac Duo.app'
```

因为是 ad-hoc 签名，首次启动时 Gatekeeper 会询问（右键 →「打开」同样可行）。想跑最新代码，仍建议按下文从源码构建。

### 从源码构建

```sh
git clone https://github.com/Toketec/mac-duo.git
cd mac-duo

./scripts/build.sh      # 产物：build/Mac Duo.app
./scripts/run.sh        # 必要时先构建，然后启动
```

构建采用本机 ad-hoc 签名，无需付费开发者证书；由于每次重编译都会重新签名，macOS 可能要求你重新确认屏幕录制权限。然后：

1. 点击菜单栏的笔记本图标 → 「启用真实桌面效果」。
2. 在 *系统设置 → 隐私与安全性 → 屏幕与系统音频录制* 中允许 **Mac Duo**（系统可能要求退出并重新打开）。
3. 缓慢合下屏幕再打开，动画连续跟随；也可以点「预览展开动画」，不用移动屏幕就能体验。

> [!IMPORTANT]
> **打开后是黑屏、看不到自己的桌面？** 这是应用的**基础模式**——抓不到屏幕画面时的暗色模糊／变暗回退。黑屏基本等同于**屏幕录制权限缺失或已失效**。
> 1. 打开 *系统设置 → 隐私与安全性 → 屏幕与系统音频录制*，把 **Mac Duo** 打开，然后按系统提示退出并重新打开应用。
> 2. **已经打开了还是黑屏？** 说明这条权限记录已经失效——每次重新编译都会重新签名，很容易出现。在同一个列表里选中 **Mac Duo**，点 **−** 移除，**彻底退出 Mac Duo**，再用 **＋** 把它加回来（选择 `dist/Mac Duo.app`，或把应用直接拖进列表）并打开开关。**「移除后重新添加」才是有效的步骤**，仅在旧记录上重新勾选通常没用。
> 3. 重新启动应用并点「预览展开动画」确认：应该看到自己的桌面在折叠，而不是一片黑。

快捷键与生命周期：**⌃⌥⌘D** 全局暂停／恢复；菜单栏可取消角度跟随；睡眠与锁屏时覆盖层自动隐藏，唤醒／解锁后恢复。退出应用即彻底停止——没有登录自启，也没有后台守护进程。

## 验证与性能测试

```sh
./scripts/test.sh              # 逻辑与边界测试、diagnose、预览渲染、签名校验
./scripts/test-native.sh       # 约 2 秒真实窗口：CVPixelBuffer → Metal → AppKit 绘制
./scripts/test-performance.sh  # 约 6 秒全屏合成负载，结果写入 build/performance/result.json
```

状态测试覆盖传感器报告解码、45°/90°/135° 边界、最大角度下的投影恒等关系、铰链固定、观察射线不随实体屏幕转动偏移、失联恢复、暂停、预览结束、唤醒与无过冲平滑。

GPU 检查渲染合成画面与三种面板状态，完全不接触个人桌面。额外的入口：

```sh
'build/Mac Duo.app/Contents/MacOS/MacDuo' --diagnose
'build/Mac Duo.app/Contents/MacOS/MacDuo' --render-previews build/previews            # 5 级开合度
'build/Mac Duo.app/Contents/MacOS/MacDuo' --render-previews build/sweep --sweep 41    # 密集扫帧，用于做 GIF
```

`--sweep N` 渲染 `N` 个等距开合度（`fold-000.png` … `fold-100.png`）——本页顶部的动画就是这么生成的：

```sh
ffmpeg -framerate 16 -i build/sweep/f%04d.png \
  -vf "scale=640:-1,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse" \
  -loop 0 docs/images/demo.gif
```

默认的 5 级渲染行为保持不变，`scripts/test.sh` 的输出不受影响。

## 性能数据

使用 `./scripts/test-performance.sh` 在 M2 Max、1512×982 桌面源、60 Hz 源更新、120 Hz 几何请求下测得：

| 渲染器 | 绘制次数／秒 | 帧间隔 P95 | 渲染耗时 P95 |
|---|---|---|---|
| **当前**（display link + 共享缓冲） | ~120 | 8.56 ms | 7.07 ms |
| 旧版（60 Hz `Timer`） | ~103 | 16.85 ms | 9.99 ms |

原始 JSON 保存在 `build/performance/result.json`。这是合成负载结果，不代表任何桌面负载与任何物理开合动作下都保证 120 fps。

实时诊断写入 `~/Library/Application Support/MacDuo/status.json`（进程号、角度、授权、GPU 提交／完成／呈现帧数、渲染与 GPU 毫秒、帧时钟），**不包含任何桌面画面**。通过终端运行 `--diagnose` 时，权限读数属于该诊断进程——读取状态文件时请核对进程号与更新时间。

## 隐私

- 只在屏幕**运动时**抓帧（`ScreenCaptureKit`，并排除本应用避免画面反馈），全程由 GPU 在内存中处理。
- 不保存、不上传，应用从不建立网络连接。开发期的参考检索均走本地代理；正式应用对外网络访问为零。
- 上述状态文件只有数字。

## 代码结构

```
Sources/MacDuo/
├── LidSensor.swift      只读 IOKit HID 角度采样（自适应 8/33 ms）
├── FoldState.swift      角度 → 开合度映射、平滑、预览、失联回退
├── DesktopCapture.swift 按需 ScreenCaptureKit 捕获（排除本应用）
├── FoldRenderer.swift   固定视点重投影、MPS 高斯金字塔、连续混合与暗化
├── Overlay.swift        仅内置屏的 AppKit 图像覆盖层与基础模式
├── ControlPanel.swift   菜单栏 popover 界面、校准、实时读数
├── App.swift            状态栏项、全局快捷键、display link、睡眠/锁屏生命周期
└── main.swift           入口、--diagnose、--render-previews [--sweep N]
Resources/Fold.metal     投影与多级高斯着色
Tests/                   状态测试 · 原生窗口测试 · 性能测试框架
scripts/                 构建、运行与三个测试入口
docs/images/             README 素材（仅合成内容）
dist/                    预编译 Mac Duo.app 与 zip（ad-hoc 签名，Apple Silicon）
```

## 常见问题

**为什么效果运行时是黑屏／看不到自己的桌面？** 因为应用进入了回退的**基础模式**：抓不到屏幕画面时它会显示暗色模糊／变暗覆盖层，而不是你的桌面。所以黑屏基本等于屏幕录制权限缺失或已失效。到 *系统设置 → 隐私与安全性 → 屏幕与系统音频录制* 授权后退出并重新打开应用；若开关已经是打开的，请**把 Mac Duo 从该列表中移除后重新添加**，再重启应用。详见[构建与运行](#构建与运行)中的重要提示。

**会改我的合盖睡眠设置吗？** 不会。合盖照常睡眠，只是屏幕关闭期间没有可见动画。

**为什么开始的一瞬间是基础模式？** 屏幕捕获首帧需要一点时间。在首帧到达前使用随角度模糊／变暗的基础模式，随后自动切换到完整效果。

**为什么透视错觉和我实际坐姿不完全贴合？** 视点是键盘空间中的一个固定点，没有用摄像头跟踪眼睛，实际坐姿会影响贴合程度。

**能在 Intel Mac 或外接屏上用吗？** 效果仅作用于内置屏，传感器接口属于 Apple Silicon 时代。只对实测过的机器做承诺。

**用了私有 API 吗？** 使用了一个**未文档化但只读**的 HID 传感器接口（Apple 厂商，usage page `0x20`，usage `0x8A`，特征报告 1）。不调用私有框架，不改固件，不写入任何数据。

## 边界与实话

- 这是受折叠屏开合动效启发、适配 MacBook 底部铰链的独立近似实现，不是任何 iOS 动画的逐像素复刻。
- HID 角度接口未文档化，已在本仓库对应的机器上验证，**不宣称适用于所有 Mac**。
- 锁屏界面与完全合盖状态由 macOS 管理；解锁后效果自动恢复。
- 传感器断连时自动回到清晰桌面，不会崩溃，也不会残留一层假的"折痕"。

## 致谢

- 只读 HID 传感器／报告配对方式对照 [ResetPower26/LidSense](https://github.com/ResetPower26/LidSense) 验证（MIT）。
- 最初的空间模糊研究参考 [chuspeeism/iphone-duo](https://github.com/chuspeeism/iphone-duo)（MIT）。
- 本仓库的固定视点射线／平面投影与 MPS 高斯管线为原创实现。

完整声明见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

实机演示录像：[实机开合演示](https://www.bilibili.com/video/BV1Q5Ya6ZEB8/) · [展开与渐变演示](https://www.bilibili.com/video/BV1cXYb6KEA4/)——仅用于分析与对照，未打包进应用。

## 许可

[MIT](LICENSE) © 2026 Tony Wang（王圣滔）

<div align="center">
<br>
<b>如果它让你的笔记本好玩了一点点，点个 ⭐ 能让更多人看到。</b>
<br><br>
<a href="https://star-history.com/#Toketec/mac-duo&Date">
<img src="https://api.star-history.com/svg?repos=Toketec/mac-duo&type=Date" width="600" alt="Star 趋势">
</a>
</div>

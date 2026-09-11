<div align="center">

# Mac Duo

**Fold your MacBook. The screen folds with it.**

Real hinge angle → real perspective → real progressive blur.
Native, GPU-accelerated, 120 Hz. No third-party dependencies.

**English** · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

<img src="docs/images/demo.gif" width="720" alt="Mac Duo — the desktop folding in perspective with progressive blur as the lid closes">

<sub>Render sweep, 0 % → 100 % openness · ping-pong loop, synthetic content (no personal desktop shown)</sub>

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20Apple%20Silicon-black?logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](#project-layout)
[![Metal](https://img.shields.io/badge/Metal-MPS%20Gaussian-5C54E8?logo=metal&logoColor=white)](#how-it-works)
[![Dependencies](https://img.shields.io/badge/dependencies-none-3fb950)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[![Stars](https://img.shields.io/github/stars/Toketec/mac-duo?style=flat&color=f0c419)](https://github.com/Toketec/mac-duo/stargazers)

</div>

---

If you ever played with the fold animation on a folding phone and wished your laptop did that: this is that, done properly. It reads the **real hinge angle** of your MacBook, re-projects your desktop onto the rotating panel as if you were sitting still, adds **physically-motivated progressive blur** where the panel bends away from your eye line — and gets out of the way the moment the lid is open.

Nothing is faked with a timer or an angle slider. Move the lid one degree and the image moves one degree.

> **Scope, honestly:** this is an independent implementation inspired by the fold transition of folding phones, adapted to the MacBook's bottom-hinge geometry. It is **not** a pixel-identical port of any iOS animation, it ships no Apple artwork, firmware or private frameworks, and it uses an **undocumented** Apple HID sensor (see [Limitations](#limitations-and-honest-notes)).

## Table of contents

- [Highlights](#highlights)
- [How it works](#how-it-works)
- [The control panel](#the-control-panel)
- [Angle map](#angle-map)
- [Requirements](#requirements)
- [Build and run](#build-and-run)
- [Verify and benchmark](#verify-and-benchmark)
- [Performance](#performance)
- [Privacy](#privacy)
- [Project layout](#project-layout)
- [FAQ](#faq)
- [Limitations and honest notes](#limitations-and-honest-notes)
- [Credits](#credits)
- [License](#license)

## Highlights

| | |
|---|---|
| 🔗 **True angle tracking** | Reads the MacBook lid sensor at **8 ms** while moving, **33 ms** when idle, with time-based smoothing and no overshoot. |
| 📐 **Fixed-observer projection** | The eye point is pinned in keyboard space, so the top of the page keeps its physical height while the panel rotates — you see a fold, not a stretch. |
| 🌫️ **Real Gaussian blur** | A 1 → 1/2 → 1/4 → 1/8 pyramid of Metal Performance Shaders Gaussians, continuously blended by radius — depth-of-field, not a flat opacity fade. |
| ⚡ **120 Hz, GPU-resident** | CADisplayLink follows the built-in display; perspective and blur run on the GPU into a reusable shared buffer. No per-frame `malloc`, no CPU full-frame copies. |
| 🪟 **Menu bar native** | Runs as an accessory app with a popover panel. The overlay is click-through and never steals keyboard focus. |
| 🔒 **Zero dependencies** | Built with Apple Command Line Tools and system frameworks only. No packages, no downloads, no network. |
| 🙈 **Nothing leaves the machine** | Frames are captured only while the lid is moving, processed in memory, never written and never uploaded. |

## How it works

```
┌──────────────┐   HID feature report    ┌──────────────────┐   Metal + MPS    ┌──────────────┐
│ lid sensor   │ ──────────────────────► │ FoldState        │ ───────────────► │ overlay      │
│ (read-only)  │   8 ms / 33 ms adaptive │ mapping·smoothing│  perspective +   │ built-in     │
└──────────────┘                         │ preview·fallback │  Gaussian + dim  │ display only │
                                         └──────────────────┘                  └──────────────┘
```

1. **Sense.** A read-only IOKit HID feature report yields the current hinge angle. The reader never writes a report and never touches sensor calibration. The poll rate adapts to motion (8 ms while the lid moves, 33 ms when it doesn't) and the sensor disconnects/reconnects on its own if reports stop.
2. **Map.** `FoldMath.openness` maps angle → progress over a calibratable range. `FoldMath.referenceUV` re-projects every pixel with a ray/plane intersection from a **fixed observer**: the eye sits `2.4 ×` the panel length in front, at the world height of the fully-open panel top. That height stays put while the panel rotates, which is what makes the motion read as a fold instead of a squash. The hinge edge is the fixed axis; the overshoot is black; anything projected outside the physical panel is clipped rather than stretched.
3. **Render.** The projected image goes through a multi-level Gaussian pyramid and is blended continuously by radius, then darkened toward the hinge. The finished frame is written by the GPU into a reusable shared buffer and handed to a native AppKit view — deliberately avoiding `CAMetalLayer` presentation glitches inside a transparent menu-bar app.

Timing layers are independent: geometry follows the display link (up to 120 Hz), the desktop source is captured at up to 60 Hz, the sensor is polled at up to 125 Hz. `FoldState` smooths with an exponential approach (45 ms time constant, no overshoot) and holds the collapsed terminal state below 45°, so no transition progress is burned in the invisible range.

## The control panel

<div align="center">
<img src="docs/images/control-panel.png" width="420" alt="Mac Duo control panel showing live hinge angle, animation range and status">

<sub>Live hinge angle, calibratable animation range, one-click preview, permission state — all in the menu bar popover.</sub>
</div>

The panel is opaque on purpose and keeps text contrast in every state (pressed, checked, unfocused). It floats **above** the animation overlay, so you can adjust settings while watching the effect behind it. It stays crisp at all times — the folding effect never applies to the panel itself.

## Angle map

<div align="center">
<table>
<tr>
<td><img src="docs/images/fold-0.png" width="180" alt="0% openness"></td>
<td><img src="docs/images/fold-25.png" width="180" alt="25% openness"></td>
<td><img src="docs/images/fold-50.png" width="180" alt="50% openness"></td>
<td><img src="docs/images/fold-75.png" width="180" alt="75% openness"></td>
<td><img src="docs/images/fold-100.png" width="180" alt="100% openness"></td>
</tr>
<tr align="center">
<td><sub>collapsed</sub></td>
<td><sub>25 %</sub></td>
<td><sub>50 %</sub></td>
<td><sub>75 %</sub></td>
<td><sub>desktop restored</sub></td>
</tr>
</table>
</div>

| Hinge angle | What you see |
|---|---|
| **≥ full angle** (default **135°**) | Effect off — your real desktop, untouched, zero overhead. |
| **full angle → 45°** | Continuous fold: perspective, progressive blur and hinge darkening follow the lid in real time. |
| **≤ 45°** | Held at the collapsed terminal state — the truly invisible range is not animated. |
| **Calibration** | Park the lid at the angle you want to be "fully open" and hit **Calibrate to current angle** (clamped to 65°–135°). Hardware is never modified, only the mapping. |
| **Sensor lost / lid fully closed** | Falls back to a sharp desktop automatically; the reader reconnects by itself. |

## Requirements

- Apple Silicon Mac (built and measured on an M2 Max)
- macOS 14 or newer
- Apple Command Line Tools (`xcode-select --install`) — no Xcode project, no package manager
- *Optional:* Screen Recording permission for the full desktop effect. Without it the app still runs in a basic mode (angle-driven blur and dimming).

## Build and run

### Prebuilt binary (fastest)

`dist/` ships a ready-to-run **`Mac Duo.app`** plus `MacDuo-1.2.0-arm64.zip` — Apple Silicon, macOS 14+, ad-hoc signed.

```sh
git clone https://github.com/Toketec/mac-duo.git
cd mac-duo
xattr -dr com.apple.quarantine 'dist/Mac Duo.app'   # clear the download flag
open 'dist/Mac Duo.app'
```

The signature is ad-hoc, so Gatekeeper will ask before the first launch (right-click → **Open** works too). Building from source below is still the cleanest way to run the newest code.

### Build from source

```sh
git clone https://github.com/Toketec/mac-duo.git
cd mac-duo

./scripts/build.sh      # → build/Mac Duo.app
./scripts/run.sh        # build if needed, then launch
```

The build is an ad-hoc local signature — no paid developer certificate required. Because the binary is re-signed on every rebuild, macOS may ask you to re-confirm Screen Recording permission after rebuilding. Then:

1. Click the laptop icon in the menu bar → **Enable real desktop effect**.
2. Allow **Mac Duo** under *System Settings → Privacy & Security → Screen & System Audio Recording* (macOS may ask you to quit and reopen).
3. Slowly close the lid and open it again — the animation follows continuously. Or press **Preview unfold** to feel it without moving the screen.

Shortcuts and lifecycle: **⌃⌥⌘D** globally pauses/resumes; the menu bar toggle disables angle tracking; the overlay hides itself on sleep and lock and comes back after wake/unlock. Quitting the app stops everything — there is no login item and no background daemon.

## Verify and benchmark

```sh
./scripts/test.sh              # logic + boundary tests, diagnose, preview render, signature check
./scripts/test-native.sh       # ~2 s real window: CVPixelBuffer → Metal → AppKit drawing
./scripts/test-performance.sh  # ~6 s full-screen synthetic load, writes build/performance/result.json
```

The state tests cover sensor report decoding, the 45°/90°/135° boundaries, the projection identity at maximum angle, the fixed hinge, observer rays that don't drift with the physical panel, sensor loss recovery, pause, preview end, wake and overshoot-free smoothing.

The GPU check renders synthetic frames and three panel states without ever touching a personal desktop. Extra entry points:

```sh
'build/Mac Duo.app/Contents/MacOS/MacDuo' --diagnose
'build/Mac Duo.app/Contents/MacOS/MacDuo' --render-previews build/previews            # 5 openness steps
'build/Mac Duo.app/Contents/MacOS/MacDuo' --render-previews build/sweep --sweep 41    # dense sweep, for GIFs
```

`--sweep N` renders `N` equally spaced openness steps (`fold-000.png` … `fold-100.png`) — that is exactly how the animation at the top of this page was produced:

```sh
ffmpeg -framerate 16 -i build/sweep/f%04d.png \
  -vf "scale=640:-1,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse" \
  -loop 0 docs/images/demo.gif
```

The default 5-step render is unchanged, so `scripts/test.sh` keeps its original output.

## Performance

Measured with `./scripts/test-performance.sh` on an M2 Max, 1512×982 desktop source, 60 Hz source updates, 120 Hz geometry requests:

| Renderer | Draws / s | Frame interval P95 | Render time P95 |
|---|---|---|---|
| **Current** (display link + shared buffer) | ~120 | 8.56 ms | 7.07 ms |
| Previous (60 Hz `Timer`) | ~103 | 16.85 ms | 9.99 ms |

Raw JSON is written to `build/performance/result.json`. This is a synthetic-load result — it does not promise 120 fps for every desktop workload or every physical lid motion.

Live diagnostics are written to `~/Library/Application Support/MacDuo/status.json` (process id, angle, authorization, submitted/completed/presented GPU frames, render and GPU milliseconds, frame clock). It contains **no desktop imagery**. When you run `--diagnose` from a terminal, the permission reading belongs to that diagnostic process — always cross-check the PID and timestamp of the status file.

## Privacy

- Screen frames are captured **only while the lid is moving** (`ScreenCaptureKit`, this app excluded to avoid feedback), and processed in memory by the GPU.
- Nothing is saved, nothing is uploaded, and the app never opens a network connection. All development-time reference lookups went through a local proxy; the shipping app's network access is zero.
- The status file above holds numbers only.

## Project layout

```
Sources/MacDuo/
├── LidSensor.swift      read-only IOKit HID angle sampling (adaptive 8/33 ms)
├── FoldState.swift      angle → openness mapping, smoothing, preview, loss fallback
├── DesktopCapture.swift on-demand ScreenCaptureKit capture (self excluded)
├── FoldRenderer.swift   fixed-observer reprojection, MPS Gaussian pyramid, blend + dim
├── Overlay.swift        built-in-display-only AppKit image overlay, basic mode
├── ControlPanel.swift   menu bar popover UI, calibration, live readout
├── App.swift            status item, hotkey, display link, sleep/lock lifecycle
└── main.swift           entry point, --diagnose, --render-previews [--sweep N]
Resources/Fold.metal     projection + multi-level Gaussian shading
Tests/                   state tests · native window test · performance harness
scripts/                 build, run, and the three test entry points
docs/images/             README assets (synthetic content only)
dist/                    prebuilt Mac Duo.app + zip (ad-hoc signed, Apple Silicon)
```

## FAQ

**Does it change my sleep settings?** No. Closing the lid still sleeps the Mac exactly as before; there is simply no visible animation while the display is off.

**Why is the first frame in basic mode?** Screen capture takes a moment to deliver its first frame. Until then you get the angle-driven blur/dim mode, then it switches to the full desktop effect automatically.

**Why does it look slightly different from my seating position?** The observer is a fixed point in keyboard space — the app does not track your eyes with a camera. Real posture changes how convincing the perspective illusion is.

**Will it work on an Intel Mac or an external display?** The effect is limited to the built-in display, and the sensor interface is Apple Silicon-era. Only the machine it was measured on is claimed.

**Is it using a private API?** It uses an **undocumented but read-only** HID sensor interface (Apple vendor, usage page `0x20`, usage `0x8A`, feature report 1). No private framework calls, no firmware changes, no writes.

## Limitations and honest notes

- An independent approximation of a folding-phone fold, adapted to the MacBook bottom hinge — not a pixel-by-pixel reproduction of an iOS animation.
- The HID angle interface is undocumented. It has been verified on the machine in this repository and is **not claimed to work on every Mac**.
- The status lights, the lock screen and the fully closed state remain under macOS control; the effect resumes after unlock.
- Sensor disconnection restores a sharp desktop automatically; there is no crash, and no drop shadow of a fake "fold" is left behind.

## Credits

- Read-only HID sensor/report pairing was verified against [ResetPower26/LidSense](https://github.com/ResetPower26/LidSense) (MIT).
- The initial spatial blur study was informed by [chuspeeism/iphone-duo](https://github.com/chuspeeism/iphone-duo) (MIT).
- The fixed-observer ray/plane projection and the MPS Gaussian pipeline in this repository are original.

Full notices: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Demo video recordings: [real hinge sweep](https://www.bilibili.com/video/BV1Q5Ya6ZEB8/) · [unfold and gradient](https://www.bilibili.com/video/BV1cXYb6KEA4/) — reference material for analysis only, not bundled with the app.

## License

[MIT](LICENSE) © 2026 Tony Wang (王圣滔)

<div align="center">
<br>
<b>If this made your laptop slightly more fun, a ⭐ helps other people find it.</b>
<br><br>
<a href="https://star-history.com/#Toketec/mac-duo&Date">
<img src="https://api.star-history.com/svg?repos=Toketec/mac-duo&type=Date" width="600" alt="Star history">
</a>
</div>

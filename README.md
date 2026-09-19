# Endfield_FineTuning

[中文版](README.zh-CN.md)

Continues [**stoicswe/Endfield_FineWine**](https://github.com/stoicswe/Endfield_FineWine), which got
**Arknights: Endfield** past its ACE anti-cheat and into gameplay on Apple Silicon via a patched CrossOver.

This repository picks up from there:

- **DualSense shows PlayStation glyphs, with correct buttons** — two new `winebus.sys` patches
- **Built against CrossOver 26.3** (Wine 11.0), not 26.2
- **`PsGetProcessExitStatus` implemented** — upstream leaves it a stub and the ACE thread aborts every run
- **A graphics configuration that does not randomly freeze** — DXMT instead of D3DMetal, plus the Unity flags that matter
- **Probe tools** that answer gamepad questions without launching the game
- **A build recipe with no Homebrew, no `sudo`, and no full Xcode**

> **What this is:** patches to CrossOver's (LGPL) Wine, plus scripts and documentation. It does **not**
> contain or redistribute CrossOver, Wine, Apple's Game Porting Toolkit, or the game.

**Upstream is a prerequisite.** Its 23 patches are what make the game run at all; nothing here replaces them.

---

## Scope and risk

- **Own the game.** This assumes a legitimate copy installed through the official launcher.
- **Compatibility work, not cheating.** These patches make the game *launch* and make a gamepad *report itself
  accurately* on unsupported hardware. No in-game advantage, no game logic touched, no other players affected.
- **No DRM circumvention.**
- **Your risk.** Running a game in an unsupported configuration may violate its Terms of Service. That is your
  decision. See [LICENSE](LICENSE).
- **Not affiliated** with Gryphline/Hypergryph, Tencent, CodeWeavers, Apple, Sony, or Guavaman Enterprises.

**Tested on:** Apple M5 Pro, macOS 27.0, CrossOver 26.3.0, DualSense Edge (`054C:0DF2`) over Bluetooth.

---

## The gamepad fix, in one paragraph

On real Windows a DualSense is **not** an XInput device — XInput only supports Xbox pads, which is why
DS5Windows and ViGEm exist. Wine's SDL backend marks *every* controller as XInput-capable, adding the
`&IG_00` / `&XI_00` suffixes. `IG_` is Microsoft's marker for "skip this in DirectInput, use XInput," and per
Rewired's documentation every XInput device is then given the Xbox 360 map, with no way to recover the HID
identity. The game behaves exactly as it does on Windows — Wine just hands it a false premise. Patch 1 stops
marking Sony pads. Patch 2 makes the SDL backend emit the native DualSense HID layout, because once the pad
is identified as a DualSense the game parses it that way. Full story, including four configurations that did
**not** work: **[docs/03-gamepad-dualsense.md](docs/03-gamepad-dualsense.md)**.

## Layout

```
patches/     four patch scripts (anchor-based, idempotent, survive line drift)
scripts/     module swap / rollback / bottle setup, and the launcher
patcher-app/ a GUI patcher that turns a copy of your CrossOver into the patched build
tools/       DirectInput / Raw Input probes (dienum, padwatch, rawinput)
upstream/    the same fixes as git-format patches, for submission to Wine
docs/        build environment, graphics, gamepad, pitfalls
```

## Quick start

If you just want to play, download **Endfield Patcher** from **[Releases](https://github.com/Rarashiken/Endfield_FineTuning/releases/latest)**, point it at your
own `CrossOver.app`, and it produces a patched copy — your original install is left alone. (Source
and build instructions: **[patcher-app/](patcher-app/)**.)

To build everything yourself:

1. Apply upstream's 23 patches to CrossOver source matching your installed version.
2. Apply `patches/01` through `04`.
3. Build — see **[docs/01-build-environment.md](docs/01-build-environment.md)**.
4. Install with `scripts/swap-built-modules.sh`; roll back with `scripts/rollback-modules.sh`.
5. Launch with `scripts/launch-endfield.command`.

Launcher options (all read back and verified against the bottle, never just echoed):

```bash
PADMODE=ps|xinput   BACKEND=dxmt|d3dmetal   RETINA=y|n   MSYNC=0|1   NVEXT=0|1
ARGS="..."          BOTTLE=...              LOG=0
```

`PADMODE=ps` is the DualSense path; `PADMODE=xinput` restores stock behaviour (working pad, Xbox glyphs).

## Status

| | |
|---|---|
| ACE anti-cheat, gameplay | ✅ (upstream) |
| Built against 26.3 | ✅ |
| `PsGetProcessExitStatus` abort | ✅ gone |
| DualSense glyphs + buttons | ✅ |
| High-resolution mode | ✅ |
| DLSS | ❌ DXMT's NVAPI path is incomplete; use TAAU or FSR |
| DX12 | ❌ no `force-d3d12` in this Unity build |
| Intermittent freezes (~30 %) | ⚠️ unsolved — see [docs/02](docs/02-graphics-and-stability.md) |
| Why hidraw-backed pads are unusable by this game | ⚠️ unexplained — three hypotheses eliminated by measurement, see [upstream/](upstream/) |

## Credits

Built on other people's work — see **[CREDITS.md](CREDITS.md)**. Particular thanks to
[stoicswe/Endfield_FineWine](https://github.com/stoicswe/Endfield_FineWine),
[MacGamePadFix](https://github.com/MathiasKowoll/MacGamePadFix),
[Nicholas Tay's DualSense/hidraw guide](https://nick.tay.blue/2024/01/21/wine-dualsense/),
and [Guavaman's Rewired documentation](https://guavaman.com/projects/rewired/docs/KnownIssues.html).

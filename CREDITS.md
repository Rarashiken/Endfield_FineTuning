# Credits & references

This repository builds directly on other people's work. Nothing here would exist without it.

## Foundation

- **[stoicswe/Endfield_FineWine](https://github.com/stoicswe/Endfield_FineWine)** — the project this one continues.
  It found the two Rosetta 2 bugs (multi-byte `0F 1F` NOP misreported as an illegal instruction; `mov reg,cr3`
  delivered as invalid-opcode instead of `#GP`) and ported the dw-proton anti-cheat patches, getting Endfield
  past ACE and into gameplay on CrossOver 26.2. **All 23 of those patches are a prerequisite here** — this
  repository only adds what comes after them.
- **[dw-proton](https://github.com/Frogging-Family/wine-tkg-git)** and the Proton/Wine-TkG community — the
  original Linux-side anti-cheat compatibility work that upstream ported.
- **[Wine](https://www.winehq.org/)** (LGPL-2.1+) and **CodeWeavers CrossOver** — the Wine source these patches
  modify. Neither is redistributed here.
- **Apple Game Porting Toolkit / D3DMetal**, and CrossOver's **DXMT** — the graphics translation layers.

## Gamepad investigation

The DualSense work leaned on several sources, each of which supplied a piece:

- **[MacGamePadFix](https://github.com/MathiasKowoll/MacGamePadFix)** by Mathias Kowoll — same platform
  (CrossOver / macOS / Bluetooth DualSense). Documented that a DualSense needs output report `0x31`
  (78 bytes + CRC) over Bluetooth versus `0x02` over USB, and that the pad silently ignores the wrong one.
  Also states plainly that the button-glyph problem cannot be solved while the game uses XInput — which is
  correct for their approach, and is precisely the constraint the patches here remove.
- **[Wine + 'proper' DualSense (PS5) controller support via hidraw](https://nick.tay.blue/2024/01/21/wine-dualsense/)**
  by Nicholas Tay — the `DisableHidraw=0` recipe, and confirmation that Wine exposing a DualSense natively
  yields PlayStation prompts in games that support them.
- **[Rewired documentation](https://guavaman.com/projects/rewired/docs/KnownIssues.html)** by Guavaman —
  states that with *Use XInput* enabled, **all** XInput devices use the Xbox 360 controller map, and that
  there is no way to associate an XInput id with the matching HID device. This is why marking a DualSense
  as XInput-capable is enough, by itself, to force Xbox glyphs.
- **[DualShock 4 (bluetooth) XInput not recognized](https://forum.winehq.org/viewtopic.php?p=144894)** —
  WineHQ forum thread on the hidraw/XInput tradeoff.
- **[soju issue #42](https://github.com/BCD1210/soju/issues/42)** — the reminder that stale `wineserver`
  and `winedevice` processes make registry changes look like they did not apply.
- **[DirectInput and XUSB Devices](https://learn.microsoft.com/en-us/windows/win32/xinput/directinput-and-xusb-devices)** —
  Microsoft's `IG_` convention, the mechanism every input library uses to skip XInput-capable devices in DirectInput.

## Patcher app

- **[dazi2011/crossover-patcher](https://github.com/dazi2011/crossover-patcher)** — the reference for the idea
  of shipping a GUI patcher that users point at their own CrossOver install, rather than distributing a
  patched CrossOver. No code was taken from it; `patcher-app/` is an independent AppKit implementation, and it
  deliberately differs on one point: it re-signs the copied bundle and gives it its own `CFBundleIdentifier`
  instead of stripping `_CodeSignature/`, because on macOS 27 a stripped seal is reported as a damaged
  application. See [patcher-app/README.md](patcher-app/README.md).

## Toolchain

- **[llvm-mingw](https://github.com/mstorsjo/llvm-mingw)** by Martin Storsjö — the PE cross-compiler, as a
  macOS universal binary, which is what makes a Homebrew-free build possible.
- **[GNU bison](https://www.gnu.org/software/bison/)** — macOS ships bison 2.3; Wine needs ≥ 3.0.
- **[SDL](https://github.com/libsdl-org/SDL)** — headers only, to compile `winebus.so` with SDL support.

## How this was built

The work in this repository was done in sessions with an AI assistant (Claude). The
division of labour: problems were identified on real hardware and every change was
tested and verified by the repository owner, who also rejected a number of approaches
that turned out to be wrong; the code and documentation are largely the model's output.

This is stated because it affects what can be done with the work — **WineHQ does not
accept LLM-generated code**, so the patches in [upstream/](upstream/) have not been
submitted to Wine on that basis. See [upstream/README.md](upstream/README.md).

## Not affiliated

This project is not affiliated with or endorsed by Gryphline / Hypergryph, Tencent, CodeWeavers, Apple,
Sony Interactive Entertainment, or Guavaman Enterprises.

# Endfield Patcher.app

A small macOS app that turns a copy of **CrossOver 26.3.0** into the patched build that runs
**Arknights: Endfield** on Apple Silicon — and that shows a DualSense as a DualSense. It is the
GUI equivalent of [`scripts/swap-built-modules.sh`](../scripts/swap-built-modules.sh):

1. Identifies which CrossOver it is, by reading the Wine version string out of the target's own
   `ntdll.so` — not `CFBundleShortVersionString`, because releases version as `26.3` while Preview
   versions by date (`20260821`), and because the Wine version is what actually decides ABI
   compatibility. An unrecognised version is **refused**, not warned about: Wine modules built
   against a different Wine crash rather than merely misbehave.
2. Copies your `CrossOver.app` with `ditto`. **The original is never touched.**
3. Installs the five pre-built patched Wine modules for that flavour
   (`ntdll.so`, `winebus.so`, `winebus.sys`, `ntoskrnl.exe`, `kernel32.dll`).
4. Gives the copy its own `CFBundleIdentifier`, so LaunchServices can tell the two apps apart.
5. **Re-signs** the whole bundle ad-hoc, carrying the original entitlements over, and clears
   quarantine.
6. Verifies the result: module sizes, `codesign --verify` on `ntdll.so` and `winebus.so`, and the
   rpaths that D3DMetal and the SDL controller backend need — which differ per flavour.

Steps 3 and 4 are where this differs from [crossover-patcher](https://github.com/dazi2011/crossover-patcher),
which strips `_CodeSignature/` instead. Stripping the seal leaves an invalid signature, and recent
macOS reports that as *"CrossOver is damaged and can't be opened"* — see
[docs/04-pitfalls.md](../docs/04-pitfalls.md).

Out of scope by design: the optional GPTK4 / MoltenVK graphics upgrades (Apple's GPTK may not be
redistributed) — see the [main README](../README.md) for those.

**End users need no developer tools.** The `lib64` rpaths are baked into the payload at app-build
time, so patching only uses `codesign`, `xattr`, `cp` and `PlistBuddy`, all of which ship with macOS.

## Using it

Open the app, pick your `CrossOver.app`, press **Patch**, choose where the patched copy goes.
It never proposes a destination that already exists.

There is also a headless mode, which runs the exact same code path — useful for scripting and for
testing a build without clicking through the window:

```bash
"Endfield Patcher.app/Contents/MacOS/EndfieldPatcher" \
    --patch /Applications/CrossOver.app /Applications/CrossOver-Endfield.app
```

## Two payloads, one app

Wine modules are ABI-bound to the Wine they were compiled from, so the app carries one payload per
CrossOver flavour and picks by what it finds in the target:

| | Wine | Libraries in | rpaths baked into the payload |
|---|---|---|---|
| CrossOver 26.3 | 11.0 | `lib64/` | `@loader_path/../../../lib64` (+ `../lib64` for winebus) |
| CrossOver Preview 20260821 | 11.15 | `lib/x86_64/` | `@loader_path/../../../lib/x86_64` (+ `../lib/x86_64`) |

Preview is worth supporting because it ships **D3DMetal 4.0b2** where 26.3 ships 3.0 — so a
Preview-based install has working DLSS without anyone hand-installing Apple's GPTK4, which cannot be
redistributed. Note that Preview also needs its **own bottle**: a bottle created by 26.3 fails
*silently* under Preview (zero-byte log, no error at all). See
[docs/01-build-environment.md](../docs/01-build-environment.md).

## Building the app

Requires the Xcode Command Line Tools only — **no Xcode**. (That constraint is why the UI is
AppKit and not SwiftUI: the SwiftUI macro plugins ship with full Xcode only.)

```bash
# 1. Build the patched Wine first (once) — see docs/01-build-environment.md.
#    It produces a wine-build64 tree containing the five modules.

# 2. Build the app around it
PAYLOAD_DIR=/path/to/wine-build64 ./patcher-app/scripts/build-app.sh
open "patcher-app/build/Endfield Patcher.app"
```

```bash
PAYLOAD_DIR_RELEASE=/path/to/26.3/wine-build64 \
PAYLOAD_DIR_PREVIEW=/path/to/11.15/wine-build64 \
  ./patcher-app/scripts/build-app.sh
```

Either may be omitted — the app then simply refuses the flavour it has no modules for, naming what it
does carry. `PAYLOAD_DIR` is accepted as an alias for `PAYLOAD_DIR_RELEASE`. `CODESIGN_ID` sets a real
signing identity (default: ad-hoc). `ALLOW_MISSING_PAYLOAD=1` produces a payload-less smoke-test build
that refuses to patch.

### App icon

`build-app.sh` bakes in `Resources/AppIcon.icns` (a committed file). To regenerate it after changing
the source art, run `scripts/make-appicon.sh` — it renders the full macOS size set from
`Resources/appicon/appicon-source.png` with Apple tools only (`swift` + `iconutil`, no third-party
image libraries), centering the artwork on a transparent square with a 6% margin (`MARGIN=…` to
change). If `AppIcon.icns` is absent, the app simply builds without a custom icon.

## Licensing (important if you distribute the built app)

- **The app itself** (Swift sources, UI, this directory): [MIT](../LICENSE).
- **The bundled payload** (the five Wine modules): **LGPL-2.1-or-later** — they are Wine, built from
  CodeWeavers' freely published
  [CrossOver 26.3 Wine source](https://www.codeweavers.com/crossover/source) with this repo's
  [patches](../patches/) applied (which include the [dw-proton](https://dawn.wine/) anti-cheat
  patches — see [patches/README.md](../patches/README.md) for authorship).
- The app's **Licenses…** window shows all of this, with the full license texts, offline.

If you publish a built `Endfield Patcher.app` (e.g. a GitHub Release), LGPL-2.1 requires you to
make the **complete corresponding source** of the payload available: this repository's patches +
the exact `crossover-sources-26.3.0` archive from
[media.codeweavers.com/pub/crossover/source](https://media.codeweavers.com/pub/crossover/source/).
Best practice: mirror the exact source tarball you built from in the release, so your source offer
doesn't depend on a third-party URL staying alive.

The app never contains or redistributes CrossOver itself, Apple's Game Porting Toolkit, MoltenVK, or
the game. It requires the user's own licensed CrossOver install as input.

## Layout

```
Package.swift                      SwiftPM manifest (macOS 13+)
Sources/EndfieldPatcher/
  main.swift                       entry point; dispatches --patch before touching NSApplication
  MainWindow.swift                 the AppKit window (source picker, progress, log)
  PatcherEngine.swift              the patch steps themselves
  PatcherCLI.swift                 headless --patch mode
  Licenses.swift                   the Licenses window + component metadata
Resources/licenses/                license texts bundled into the app
Resources/AppIcon.icns             the app icon (committed; regenerate with make-appicon.sh)
Resources/appicon/                 the icon source art
scripts/build-app.sh               compile + assemble + payload staging + rpaths + signing
scripts/make-appicon.sh            regenerate AppIcon.icns from the source art
scripts/make-appicon.swift         the icon renderer (ImageIO/Core Graphics)
build/                             (gitignored) the assembled .app
```

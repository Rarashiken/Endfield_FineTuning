# Patches for Wine upstream

The two gamepad patches, rebased against **Wine master** (`gitlab.winehq.org/wine/wine`) and formatted
for submission. They are not Endfield-specific — they affect any DualShock 4 or DualSense under Wine.

```
0001-winebus.sys-Don-t-advertise-XInput-compatibility-for.patch
0002-winebus.sys-Report-the-native-DualSense-HID-layout-o.patch
```

`3 files changed, 109 insertions(+), 5 deletions(-)` — `dlls/winebus.sys/{main.c,bus_sdl.c,unixlib.h}`.

Verified to apply to a current master snapshot of those files. The equivalent change also applies to
CrossOver's tree, where `unixlib.c` carries an extra WoW64 thunk that upstream does not have; the scripts in
[`../patches/`](../patches/) handle both.

## How to submit

Wine does **not** accept GitHub pull requests. Either:

- **Merge request** on <https://gitlab.winehq.org/wine/wine> (needs a WineHQ GitLab account), or
- **Bugzilla** at <https://bugs.winehq.org> with the patches attached, or
- the **wine-devel** mailing list.

## Expect discussion

Worth saying plainly rather than discovering it in review:

- Patch 0001 changes how a device is advertised. Applied unconditionally it would break XInput-only titles
  that currently work with a DualSense through Wine's XInput translation — which is why it is behind a
  registry value with the old behaviour as the default. Wine is nonetheless reluctant to add new registry
  knobs, so this is the part most likely to be contested.
- A maintainer may reasonably answer "use the hidraw path" — upstream already sets `prefer_hidraw` for
  DualSense, and that path reports the native layout without either patch. On macOS that path does not work:
  the device enumerates, `DirectInput` reads it correctly (see [`../tools/`](../tools/)), but games that read
  the SDL-backed device fine get nothing from it. That looks like a Raw Input issue rather than a winebus
  one, and it is **inferred, not proven** — no Raw Input probe was written to confirm it. It probably
  deserves a separate bug report, with that measurement done first.

## Supporting measurements

Everything in the commit messages was measured with the probes in [`../tools/`](../tools/), not inferred:
`dienum.exe` for what DirectInput enumerates, `padwatch.exe` for which index each physical button reports.
Method and full results: [`../docs/03-gamepad-dualsense.md`](../docs/03-gamepad-dualsense.md).

# Patches

Apply **after** the 23 upstream patches from
[stoicswe/Endfield_FineWine](https://github.com/stoicswe/Endfield_FineWine).

```bash
patches/01-psgetprocessexitstatus.sh  path/to/wine-src
patches/02-sony-no-xinput.sh          path/to/wine-src
patches/03-ds5-native-layout.sh       path/to/wine-src
```

These are **scripts, not context diffs.** They locate anchors in the source and rewrite them, so they survive
the line-number drift between CrossOver releases. Each is idempotent and refuses to apply twice.

| | File | Registry switch | Effect |
|---|---|---|---|
| 01 | `dlls/ntoskrnl.exe/{pnp.c,ntoskrnl.exe.spec}` | — | Implements `PsGetProcessExitStatus`, removing the ACE thread abort logged on every run |
| 02 | `dlls/winebus.sys/main.c` | `"Sony XInput" = 0` | Stops marking DualSense / DualShock 4 as XInput-capable, matching real Windows |
| 03 | `dlls/winebus.sys/{bus_sdl.c,main.c,unixlib.h,unixlib.c}` | (tied to 02) | Makes the SDL backend emit the native DualSense HID layout for Sony pads |

Both gamepad patches are controlled by one value:

```
HKLM\System\CurrentControlSet\Services\winebus   "Sony XInput" = dword:0
```

Note that `winebus` reads its **service key directly** — values under `...\winebus\Parameters` are silently
ignored.

**03 depends on 02 being off.** In the default mode `winexinput.sys` translates the standard XUSB-shaped
descriptor into XInput state; changing the layout unconditionally would break the fallback path. The patch
wires this up as `options.sony_native_layout = !sony_xinput_enabled`.

Patch 03 requires `winebus.so` to be built with SDL support, which needs SDL2 headers — see
[docs/01-build-environment.md](../docs/01-build-environment.md).

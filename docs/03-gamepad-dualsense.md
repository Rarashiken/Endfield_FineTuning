# DualSense: PlayStation glyphs and correct buttons

**Problem.** A DualSense (here a DualSense Edge, `054C:0DF2`, over Bluetooth) works in Endfield under
CrossOver, but the game draws Xbox button prompts. macOS identifies the pad correctly. Windows and iPadOS
show PlayStation prompts. Only the CrossOver bottle gets it wrong.

**Root cause.** Wine marks the pad as XInput-capable. Real Windows never does.

**Fix.** Two patches to `winebus.sys`, both gated behind one registry switch.

---

## Why Wine's behaviour differs from Windows

On Windows, XInput only supports XUSB devices — Xbox pads. A DualSense is exposed as a plain HID /
DirectInput / WGI device carrying Sony's `054C:0DF2`. Tools like DS5Windows, ViGEm and HidHide exist
*precisely because* Windows offers no native way to present a DualSense as an XInput device. So an input
library sees a DualSense, matches it by VID/PID, and draws PlayStation glyphs.

Wine's SDL backend sets `is_gamepad = TRUE` for *any* controller. `get_compatible_ids()` then appends
`WINEBUS\WINE_COMP_XINPUT`, and `winexinput.sys` creates two child devices with `&IG_00` and `&XI_00`
hardware-ID suffixes.

`IG_` is Microsoft's documented marker for "this device is XInput-capable." Every input library —
Rewired included — skips such devices in DirectInput and uses XInput instead. And per Rewired's own
documentation, with *Use XInput* enabled **all** XInput devices are given the Xbox 360 controller map,
with no way to recover the underlying HID identity.

So the game is behaving exactly as it does on Windows. Wine simply hands it a false premise.

## Patch 1 — do not mark Sony pads as XInput-capable

`patches/02-sony-no-xinput.sh`, in `dlls/winebus.sys/main.c`:

```c
want_xinput = ext->desc.is_gamepad;
if (want_xinput && !sony_xinput_enabled &&
    (is_dualsense_gamepad(ext->desc.vid, ext->desc.pid) ||
     is_dualshock4_gamepad(ext->desc.vid, ext->desc.pid)))
    want_xinput = FALSE;
```

Controlled by a registry value so it can be toggled and A/B-tested without rebuilding:

```
HKLM\System\CurrentControlSet\Services\winebus   "Sony XInput" = dword:0
```

Verified by clearing `Enum\HID\VID_054C*` and re-enumerating: `&IG_00` and `&XI_00` disappear, leaving a
single plain HID gamepad with Sony's real VID/PID — exactly what Windows presents.

**Result:** PlayStation glyphs appear. Sticks respond. Face buttons do nothing.

## Patch 2 — emit the native DualSense HID layout

With the pad identified as a DualSense, Rewired parses it using the **native DS5 layout**. But Wine's SDL
backend builds a fixed XUSB-shaped descriptor via `hid_device_add_gamepad()`. The identity is right and the
data layout is wrong.

Measured with `tools/padwatch.exe` — no game launch required:

| Button | Wine SDL (before) | Native IOHID | DualSense native |
|---|---|---|---|
| ✕ | #0 | #1 | 1 |
| ○ | #1 | #2 | 2 |
| □ | #2 | **#0** | 0 |
| △ | #3 | #3 | 3 |
| L1 / R1 | #4 / #5 | #4 / #5 | 4 / 5 |
| L2 / R2 | *axes only, no button* | **#6 / #7** | 6 / 7 |
| Create / Options | #6 / #7 | #8 / #9 | 8 / 9 |
| D-pad | #10–13 **and** the POV hat | POV hat only | POV hat only |

Axes were shifted too. Wine fills `LX→X, LY→Y, RX→Z, RY→Rx, L2→Ry, R2→Rz`; a DualSense reports
`RY→Rz, L2→Rx, R2→Ry`. The left stick happens to line up, which is why sticks "seemed to work."

`patches/03-ds5-native-layout.sh` adds, for Sony pads only:

- `hid_device_add_ds5_gamepad()` — axes `X Y Z Rz Rx Ry`, one hat, 14 buttons
- `ds5_button_from_sdl()` — the button order above; D-pad drives the hat only
- L2 / R2 derived as digital buttons 6 / 7 from the trigger axes (threshold 1000 ≈ 3 %)
- no Y-axis inversion (Wine inverts to match the XUSB convention; a DualSense does not)

**This patch is deliberately tied to patch 1** (`options.sony_native_layout = !sony_xinput_enabled`).
In the default mode `winexinput.sys` translates the standard XUSB-shaped descriptor into XInput state;
changing the layout unconditionally would break the fallback path.

**Result:** PlayStation glyphs *and* correct buttons.

## What did not work, and why

Recorded so nobody repeats them.

| Configuration | Outcome |
|---|---|
| `DisableHidraw=0` + `Enable SDL=0` (native IOHID device only) | Correct native layout, but **the game cannot read the device at all** |
| `DisableHidraw=0` + `Enable SDL=1` | Native and SDL devices coexist; the game still prefers the XInput one |
| `Map Controllers=0` | Still XInput-marked (`is_gamepad` falls back to an axis/button-count heuristic), and yields 21 buttons with no POV — further from a DualSense, not closer |
| Disabling the xinput DLLs for the game via `DllOverrides` | The pad goes completely dead — this game's Rewired build consumes XInput and, apparently, Raw Input, but not DirectInput |

That last row is the interesting one, and it is still unexplained. Three hypotheses were tested and all
three were **eliminated by measurement**:

| Hypothesis | Test | Result |
|---|---|---|
| DirectInput does not see the hidraw device | `tools/dienum.exe`, `tools/padwatch.exe` | Sees it, reads button presses correctly, `6 axes / 14 buttons / 1 POV` |
| Raw Input does not deliver `WM_INPUT` for it | `tools/rawinput.exe`, 30 s of input | **1971 reports** delivered (SDL backend: 2679) — works fine |
| The instance ID is malformed and gets rejected | `patches/04`, then re-test | ID valid afterwards, game still gets nothing |

The third one deserves a note of its own. The IOHID backend takes the serial number from
`kIOHIDSerialNumberKey`, which over Bluetooth is the MAC address **with colons**, and `get_instance_id()`
interpolates it straight into the device instance ID:

```
HID\VID_054C&PID_0DF2\256&E8:47:3A:B4:1C:0B&3AB41C0B&0&0
```

A device instance ID may not contain `< > : " / \ | ? *`. That is a genuine Wine bug — `patches/04` fixes
it, and it is worth submitting on its own — but fixing it did **not** fix this.

So the cause remains unidentified. The remaining structural difference is the `is_hidraw` flag itself, which
on the PE side gates only `HIDRAW_FIXUP_DUALSENSE_BT` and the hidraw/non-hidraw dedup filter. The working
fix therefore keeps the SDL backend, which the game demonstrably reads, and changes the layout it emits.

## Also worth knowing

- **USB is worse than Bluetooth here.** With `DisableHidraw=0` and the pad on USB, winebus enumerated no
  `VID_054C` device at all — macOS appears to claim it. On Bluetooth the native device appears normally.
  An early conclusion drawn from a USB test was wrong for this reason.
- **`Enum` registry keys persist.** A device that is gone still has entries. Any enumeration comparison must
  delete `Enum\HID\VID_054C*` and `Enum\WINEBUS\VID_054C*` first, then re-enumerate.
- **`bus_xbox360.c` is a CrossOver addition** for the proprietary USB Xbox 360 protocol, and it is disabled
  on macOS Sequoia and later (`IOUSBDeviceInterface` access was restricted). It is unrelated to this problem,
  despite looking relevant.

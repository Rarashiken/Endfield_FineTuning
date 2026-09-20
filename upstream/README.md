# Patches for Wine upstream

Rebased against **Wine master** (`gitlab.winehq.org/wine/wine`) and formatted for submission. None of them
are Endfield-specific.

| | Patch | Scope |
|---|---|---|
| 0001 | Don't advertise XInput compatibility for Sony gamepads | any DualShock 4 / DualSense |
| 0002 | Report the native DualSense HID layout on the SDL backend | any DualSense |
| 0003 | Don't put disallowed characters in device instance IDs | any device whose serial contains them |

0001 and 0002 belong together. **0003 is independent** and can be submitted on its own.

## How to submit

**Merge requests on <https://gitlab.winehq.org/wine/wine>.** Wine retired the patch tracker and no
longer takes patches by email — the wine-devel mailing list still carries the discussion, because
GitLab mirrors merge requests and comments to it, but submission itself goes through GitLab. The
forum at forum.winehq.org is user support, not development; bugs.winehq.org is for bug reports.

It needs a **WineHQ GitLab account**, which is separate from a forum or Bugzilla account.

Project rules that matter for these: keep each MR small, few patches per MR, and **every commit needs
`Signed-off-by`** (already present in the `.patch` files here).

Suggested split — they are independent, and one is far less contentious than the others:

| MR | Patches | |
|---|---|---|
| first | `0003` | a plain correctness fix, no behaviour choice to argue about |
| later | `0001` + `0002` | a deliberate behaviour change; expect discussion (see below) |

The `Signed-off-by` lines currently use a GitHub `users.noreply.github.com` address. That works
mechanically, but a reachable address is better for a project that may want to ask questions about a
patch months later — worth changing before submitting.


## 0003 — device instance IDs

`get_instance_id()` interpolates `desc.serialnumber` straight into the device instance ID. The IOHID backend
takes that serial from `kIOHIDSerialNumberKey`, which for a Bluetooth device is the MAC address **with
colons**:

```
HID\VID_054C&PID_0DF2\256&E8:47:3A:B4:1C:0B&3AB41C0B&0&0
```

A device instance ID may not contain `< > : " / \ | ? *` or control characters. Every input API still reads
the device correctly, which is why this is easy to miss.

This is a real bug and the patch is small and obviously correct. It is worth saying that **fixing it did not
fix the problem that led to finding it** — see below.

## 0001 / 0002 — expect discussion

- 0001 changes how a device is advertised. Applied unconditionally it would break XInput-only titles that
  currently work with a DualSense through Wine's XInput translation, which is why it sits behind a registry
  value with the old behaviour as the default. Wine is reluctant to add registry knobs, so this is the part
  most likely to be contested.
- A maintainer may reasonably answer **"use the hidraw path"** — upstream already sets `prefer_hidraw` for
  DualSense, and that path reports the native layout without either patch, which would make 0002 unnecessary.
  On macOS that path does not work, and the reason is **not yet known**. See the next section: this is the
  weakest point of the submission and is stated as such rather than glossed over.

## Open question: hidraw-backed gamepads are unusable by some applications

With `DisableHidraw=0` and `Enable SDL=0` the pad is exposed through the IOHID backend with its true native
descriptor. The game receives nothing from it — no buttons, no axes — while the same pad on the SDL backend
works. Three hypotheses were tested and **all three were eliminated by measurement**:

| Hypothesis | Test | Result |
|---|---|---|
| DirectInput does not see the hidraw device | `tools/dienum.exe`, `tools/padwatch.exe` | Sees it, reads button presses correctly, `6 axes / 14 buttons / 1 POV` |
| Raw Input does not deliver `WM_INPUT` for it | `tools/rawinput.exe`, 30 s of input | **1971 reports** delivered (SDL backend: 2679) — works |
| The instance ID is malformed and gets rejected | patch 0003, then re-test | ID valid afterwards, game still gets nothing |

So the cause is still unidentified. The remaining structural difference is the `is_hidraw` flag itself,
which on the PE side gates only `HIDRAW_FIXUP_DUALSENSE_BT` and the hidraw/non-hidraw dedup filter.

Anyone reproducing this: the probes in [`../tools/`](../tools/) are the fastest way in — they answer these
questions in a minute each without launching a game.

> An earlier version of this file claimed Raw Input was the culprit. That was an **inference, and it was
> wrong** — the measurement above disproves it. Recorded here rather than quietly deleted.

## Supporting measurements

Everything in the commit messages was measured, not inferred. Method and full results:
[`../docs/03-gamepad-dualsense.md`](../docs/03-gamepad-dualsense.md).

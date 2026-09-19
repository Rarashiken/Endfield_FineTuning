# Probes

Two tiny Win32 programs that let you inspect how a gamepad is exposed to a
CrossOver bottle **without launching the game**. Both write their output to
`Z:\tmp\*.txt` (i.e. `/tmp` on the host).

| Tool | What it answers |
|---|---|
| `dienum.exe` | Which devices does DirectInput see? VID/PID, axis / button / POV counts. |
| `padwatch.exe` | Which button index does each physical button report? Polls for 40 s and logs every press. |

These were what turned the gamepad work from "launch the game and guess" —
roughly a 30 % chance of hitting an unrelated freeze each time — into
measurements that take a minute and cost nothing.

## Build

```bash
make MINGW=/path/to/llvm-mingw-20260908-ucrt-macos-universal/bin/
```

## Run

```bash
cp dienum.exe /tmp/
"$CXR/bin/wine" --bottle <bottle> --wait-children --cx-app 'Z:\tmp\dienum.exe'
cat /tmp/dienum.txt
```

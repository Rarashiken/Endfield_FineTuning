# Graphics configuration and stability

Upstream reached gameplay through Apple's D3DMetal. On this setup that path was unstable, and the fix was a
different translation layer plus a specific set of Unity flags.

## The configuration

Bottle environment (`cxbottle.conf`, `[EnvironmentVariables]`):

```
"CX_GRAPHICS_BACKEND" = "dxmt"
"DXMT_ENABLE_NVEXT"   = "0"
"WINEMSYNC"           = "1"
"ROSETTA_ADVERTISE_AVX" = "1"
```

Launch arguments:

```
-force-d3d11 -force-gfx-direct -force-d3d11-bitblt-mode
```

| Setting | Why |
|---|---|
| `CX_GRAPHICS_BACKEND=dxmt` | D3DMetal — both CrossOver's 3.0 and GPTK4's 4.0b2 — produced random freezes. DXMT does not. |
| `-force-d3d11` | **Required.** Without it Unity falls back to Vulkan, MoltenVK fails with `VK_ERROR_INITIALIZATION_FAILED: Shader library compile failed`, and you get a white screen and a retry loop that looks like shader compilation but is not. |
| `-force-gfx-direct` | Disables Unity's render thread. Markedly fewer freezes. |
| `-force-d3d11-bitblt-mode` | DXMT does not support flip-discard presentation (`CreateSwapChain: unsupported swap effect 3`), which shows as a grey screen in high-resolution mode. |
| `DXMT_ENABLE_NVEXT=0` | Hides DLSS. DXMT's NVAPI path is incomplete; selecting DLSS blacks out the image. TAAU and FSR work. |

High-resolution (Retina) mode works once `-force-d3d11-bitblt-mode` is set.

## DX12 is not available

Not a configuration problem — the build has no such flag. String counts in `UnityPlayer.dll`:

```
force-d3d11   9
force-glcore  9
force-vulkan  3
force-gfx     5
force-d3d12   0
```

There is no game-specific flag either.

## Remaining issue: intermittent freezes

Roughly 30 % of launches freeze, most often during loading. Not solved.

The launcher records every run to a CSV (backend, msync, nvext, retina, pad mode, arguments, outcome, log
file) and prompts for the outcome on exit, grouping statistics by configuration.

That exists because of a methodological problem worth stating plainly: **at a ~30 % failure rate a single
successful run proves nothing**, and two consecutive successes still carry a 1-in-2 chance of being luck.
Two "root causes" were declared prematurely during this work on exactly that basis. Five or more runs per
configuration is the minimum worth acting on.

One known-harmless artifact appears in every log:

```
wine: Unhandled privileged instruction at address 0x... (thread ...), starting debugger...
```

It occurs before Unity starts and the game runs to completion regardless. It is *not* a regression from the
patches here — both the patched and unpatched `ntdll.so` carry the fix (verified via the `CWC-ILLEGAL-INSTR`
marker string), and the earlier belief that it never appeared came from a handful of runs before per-run
logging existed.

## `PsGetProcessExitStatus`

Upstream documents this as a cosmetic residual: an ACE background thread aborts on

```
wine: Call from ... to unimplemented function ntoskrnl.exe.PsGetProcessExitStatus, aborting
```

`patches/01-psgetprocessexitstatus.sh` implements it (the function is a one-liner returning
`process->info.ExitStatus`; the `.spec` entry changes from `@ stub` to `@ stdcall ...(ptr)`).

The abort is gone. Whether it affects the freezes is **unknown** — upstream considers it harmless, and the
sample size so far is too small to say otherwise. It was worth doing regardless, since it also meant the
modules were genuinely compiled against 26.3 rather than carrying 26.2 output forward.

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
| `CX_GRAPHICS_BACKEND=dxmt` | CrossOver's bundled D3DMetal 3.0 produced random freezes; DXMT does not. **See the correction below — GPTK4's 4.0b2 had never actually been tested when this was written.** |
| `-force-d3d11` | **Required.** Without it Unity falls back to Vulkan, MoltenVK fails with `VK_ERROR_INITIALIZATION_FAILED: Shader library compile failed`, and you get a white screen and a retry loop that looks like shader compilation but is not. |
| `-force-gfx-direct` | Disables Unity's render thread. Markedly fewer freezes. |
| `-force-d3d11-bitblt-mode` | DXMT does not support flip-discard presentation (`CreateSwapChain: unsupported swap effect 3`), which shows as a grey screen in high-resolution mode. |
| `DXMT_ENABLE_NVEXT=0` | Hides DLSS. DXMT advertises NVAPI but does not implement the upscaler behind it, so selecting DLSS blacks out the image. TAAU and FSR work. (D3DMetal 4.0b2 does implement it — see below.) |

High-resolution (Retina) mode works once `-force-d3d11-bitblt-mode` is set.

## Correction: D3DMetal 4.0b2 was never actually tested

An earlier version of this page stated that **both** CrossOver's D3DMetal 3.0 **and** GPTK4's 4.0b2
produced random freezes. That was wrong about 4.0b2, and the reason is worth recording.

The bottle had these set:

```
"CX_GRAPHICS_BACKEND" = "dxmt"       ← but the backend was DXMT
"D3DM_MTL4"           = "1"
"D3DM_ENABLE_METALFX" = "1"
```

`D3DM_*` are **D3DMetal's** switches. With the backend on DXMT, D3DMetal is never loaded and those
variables do nothing. GPTK4 had been installed, Metal 4 had been "enabled", MetalFX had been
"enabled" — and none of it was ever in the rendering path. The freeze result belonged to 3.0 alone.

Measured afterwards, on `CX_GRAPHICS_BACKEND=d3dmetal` with D3DMetal 4.0b2: no freeze, and **the
in-game DLSS option works instead of blacking out**.

### Why DLSS works there and not on DXMT

D3DMetal 4.0 carries a DLSS implementation backed by MetalFX. Its symbol table has both halves:

```
N3ngx20TemporalSuperSamplerE        ngx::TemporalSuperSampler (NGX is DLSS's SDK)
D3DM_NVNGX_PATH
DLSS.Hint.Render.Preset.DLAA, DLSS.Feature.Create.Flags, DLSS.Exposure.Scale, …
newTemporalScalerWithDevice:        MetalFX Temporal
newSpatialScalerWithDevice:
```

DXMT's `DXMT_ENABLE_NVEXT=1` only makes NVAPI *present*, so the menu entry appears with nothing
behind it. That is the black screen, and it is a difference in implementation, not in configuration.

### Metal 4 cannot engage in this game

`D3DM_MTL4=1` has no effect here, and not because it is set wrong:

```
D3D12.*MTL4   4   (ID3D12GraphicsCommandListMTL4::…)
D3D11.*MTL4   0
```

The MTL4 path is D3D12-only, and this game is D3D11 (see the next section). The launcher greps each
run's log for `Enabled MTL4 backend` and reports when it is absent, rather than trusting the variable.

### Availability

D3DMetal 4.0b2 comes from **Apple's Game Porting Toolkit 4**, which may not be redistributed. It has
to be installed by hand over `lib64/apple_gptk/external/`. Anything built from this repository, the
patcher app included, ships with whatever D3DMetal your CrossOver came with — 3.0 for CrossOver 26.3.

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

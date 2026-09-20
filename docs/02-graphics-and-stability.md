# Graphics configuration and stability

Upstream reached gameplay through Apple's D3DMetal. On this setup that path was unstable, and the fix was a
different translation layer plus a specific set of Unity flags.

## Which backend to use

Short answer: **DXMT is still the default, and that is deliberate.**

| | Needs | Retina | DLSS | Freezes |
|---|---|---|---|---|
| `CX_GRAPHICS_BACKEND=dxmt` | nothing — ships with CrossOver | ✅ | ❌ (black screen if forced on) | 14 runs, 5 froze |
| `d3dmetal` + **D3DMetal 3.0** | nothing — ships with CrossOver | ✅ | ❌ | **random freezes, verified** |
| `d3dmetal` + **D3DMetal 4.0b2** | Apple GPTK4, installed by hand | ✅ | ✅ MetalFX | 2 runs, 0 froze |

The last row is the best configuration, and it is the one you should use **if you have installed
GPTK4 yourself**. It is not the default here for one reason: **Apple's Game Porting Toolkit may not
be redistributed.** Anything produced from this repository — the patcher app included — carries
whatever D3DMetal your CrossOver shipped with, which for CrossOver 26.3 is 3.0, and 3.0 is the
version with the verified freezes. So for anyone who has not installed GPTK4, DXMT remains the
correct choice, and the launcher keeps `BACKEND=dxmt` as its default.

To use the third row: install GPTK4, copy its `D3DMetal.framework` and `libd3dshared.dylib` over
`Contents/SharedSupport/CrossOver/lib64/apple_gptk/external/`, then launch with `BACKEND=d3dmetal`.

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

## Vulkan: it initialises now, but it is not usable

The game supports both Vulkan and D3D11, and Unity picks Vulkan by default — which on Windows is
usually the faster path. This page used to justify `-force-d3d11` with a MoltenVK failure:

```
[mvk-error] VK_ERROR_INITIALIZATION_FAILED: Shader library compile failed (Error code 3)
```

**That justification has expired.** Vulkan now initialises cleanly, with no `mvk-error` at all:

```
Forcing GfxDevice: Vulkan
[Vulkan init] Physical Device [0]: "Apple M5 Pro" apiVersion=1.2.290
```

The conclusion did not change, but the reason did. Four measured runs:

| Configuration | Result |
|---|---|
| `RETINA=y` | White screen — but with audio and a visible "login succeeded" prompt, i.e. **it is rendering, and overexposed** |
| `RETINA=y`, DLSS switched to TAAU in-game | Same white screen — **DLSS is not the cause** |
| `RETINA=n` | Picture correct, then stuck compiling shaders, extremely slow |
| `RETINA=n`, second run | Compiles quickly, music switches to the in-game track (so the scene loaded) — **black screen throughout** |

Why it is not usable:

1. **Retina has to be off.** The swapchain reports both `colorspace 0` (SRGB_NONLINEAR) and
   `1000104001` (DISPLAY_P3_NONLINEAR); a white screen with the content still visible underneath is
   the signature of a linear/sRGB double conversion. None of MoltenVK's 43 `MVK_CONFIG_*` knobs
   touch colour space, so this layer is out of reach. It is the same class of problem as the grey
   screen D3D11 gets without `-force-d3d11-bitblt-mode`.
2. **Turning Retina off just trades white for black.** The game reaches frame 549, the gameplay
   layer keeps logging, the renderer reports nothing wrong, and no picture arrives. Accompanied by
   `wine client error:544: read: Bad address`.
3. **The PSO cache never lands.** Every run logs `Vulkan PSO: cache data not found` and
   `vulkan_pso_cache.bin` is never created, so every launch recompiles every shader. For contrast,
   `dx11_pso_cache.bin` is 65 bytes — under D3D11 the shaders are managed by D3DMetal/DXMT instead.
   MoltenVK has no disk cache of its own; it relies entirely on that Unity file.
4. **No DLSS on Vulkan, ever.** The Streamline plugins (`sl.dlss.dll` and friends) only have
   D3D11/D3D12 backends, and the NGX implementation underneath them comes from D3DMetal.

The root cause is simply that Unity has never supported Vulkan on macOS, and
`Windows game → Wine → MoltenVK → Metal` is a path nobody tests. Use `GFXAPI=vulkan` in the launcher
if you want to re-check this in future; it prints what the game itself reports, not what was asked for.

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

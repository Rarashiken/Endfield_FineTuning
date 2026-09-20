# Building patched Wine modules without Homebrew

Everything below runs as a normal user. No Homebrew, no `sudo`, no full Xcode — Command Line Tools only.

Tested on macOS 27.0 / Apple M5 Pro, targeting CrossOver 26.3.0 (Wine 11.0).

## 1. Toolchain

```bash
S=~/cx-build
mkdir -p "$S/toolchain" && cd "$S/toolchain"

# PE cross-compiler, macOS universal binary
curl -fsSLO https://github.com/mstorsjo/llvm-mingw/releases/download/20260908/llvm-mingw-20260908-ucrt-macos-universal.tar.xz
tar xf llvm-mingw-*.tar.xz

# macOS ships bison 2.3; Wine needs >= 3.0
curl -fsSLO https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz
tar xf bison-3.8.2.tar.xz && cd bison-3.8.2
./configure --prefix="$S/toolchain/bison-install"
make -j$(sysctl -n hw.ncpu) && make install
```

## 2. SDL2 headers

Needed only to build `winebus.so` with SDL support. Match the version CrossOver ships:

```bash
A=/Applications/CrossOver-Endfield.app/Contents/SharedSupport/CrossOver
strings -a "$A/lib64/libSDL2-2.0.0.dylib" | grep -o 'SDL-release-[0-9.]*' | sort -u   # e.g. 2.30.12

mkdir -p "$S/sdl2" && cd "$S/sdl2"
curl -fsSL https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.30.12.tar.gz -o sdl.tar.gz
tar xzf sdl.tar.gz --strip-components=1 "SDL-release-2.30.12/include"
```

CrossOver bundles the dylib but not the headers, and the dylib is `dlopen`ed at runtime, so headers alone
are enough.

## 3. Source and patches

Fetch the CrossOver source matching your installed version, apply the 23 upstream patches from
[Endfield_FineWine](https://github.com/stoicswe/Endfield_FineWine), then the patches here:

```bash
patches/01-psgetprocessexitstatus.sh  path/to/wine-src
patches/02-sony-no-xinput.sh          path/to/wine-src
patches/03-ds5-native-layout.sh       path/to/wine-src
```

These are **scripts, not context diffs** — they locate anchors in the source and edit them, so they survive
the line-number drift between CrossOver releases. Each is idempotent and refuses to apply twice.

## 4. configure

```bash
MW=$(ls -d "$S/toolchain"/llvm-mingw-*/ | head -1)
export PATH="${MW}bin:$S/toolchain/bison-install/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=10.15

mkdir -p build/wine-build64 && cd build/wine-build64
../wine-src/configure \
  --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
  --enable-archs=x86_64 --disable-tests \
  --without-x --without-freetype --without-gnutls --without-sdl --without-vulkan \
  --without-krb5 --without-gstreamer --without-gphoto --without-sane \
  --without-pcap --without-usb --without-cups \
  CC=/usr/bin/clang CXX=/usr/bin/clang++ \
  CFLAGS="-arch x86_64" CXXFLAGS="-arch x86_64" LDFLAGS="-arch x86_64"
```

Every one of those `--without-*` is load-bearing: without `--without-freetype` configure stops at
*"FreeType 64-bit development files not found"*, and the others fail the same way one at a time.

**`CC` must be the system clang.** The Unix side compiles native macOS code; llvm-mingw only builds
the PE side, and `winebuild` finds it through `PATH`. **`--without-sdl` is deliberate** — `winebus.so`
is rebuilt separately below with SDL injected, so `config.h` stays untouched and the tree does not
rebuild.

Two things here are not optional — see [04-pitfalls.md](04-pitfalls.md):

- **Do not wrap the build in `arch -x86_64`.**
- **llvm-mingw must be first in `PATH`, not last.**

## 5. Build

```bash
make -j$(sysctl -n hw.ncpu)
```

`winebus.so` needs SDL flags injected for that target only, so `config.h` stays untouched and the rest of
the tree does not rebuild:

```bash
rm -f dlls/winebus.sys/bus_sdl.o dlls/winebus.sys/winebus.so
# Single-quoted: the quotes have to survive shell -> make -> sh before reaching clang.
# Written with \" inside double quotes they only survive one hop, the macro expands to a bare
# libSDL2-2.0.0.dylib, and clang reports `invalid suffix '.0.dylib' on floating constant`.
SDL_DEF='-DSONAME_LIBSDL2=\"libSDL2-2.0.0.dylib\"'
make dlls/winebus.sys/winebus.so \
  CFLAGS="-arch x86_64 -I$S/sdl2/include -DHAVE_SDL_H $SDL_DEF" \
  LDFLAGS="-arch x86_64 -Wl,-rpath,@loader_path/../lib64 -Wl,-rpath,@loader_path/../../../lib64"
```

Verify it took, rather than trusting the exit status:

```bash
strings winebus.so | grep -q libSDL2-2.0.0.dylib   # the SONAME actually made it in
strings winebus.so | grep -q "SDL support not compiled in" && echo BROKEN
```

`-DHAVE_SDL_H` is required as well as `-DSONAME_LIBSDL2`: the `#include <SDL.h>` is guarded by the former.
Defining only the latter produces a wall of `use of undeclared identifier SDL_*`.

Check: `strings winebus.so | grep "SDL support not compiled"` must come back empty.

## 6. Install

```bash
BLD=$PWD scripts/swap-built-modules.sh     # ntdll.so, kernel32.dll, ntoskrnl.exe
```

`winebus.so` and `winebus.sys` are installed the same way — copy in, ad-hoc sign the `.so`, re-sign the
bundle. Rollback: `scripts/rollback-modules.sh`.

## Verifying a module is a faithful drop-in

Compare the export table against the shipped one. For `ntoskrnl.exe`:

```
shipped CrossOver 26.3 : 1668 exports, PsGetProcessExitStatus at ordinal 918, RVA 0x4420  (stub)
locally built          : 1668 exports, PsGetProcessExitStatus at ordinal 918, RVA 0x18220 (implemented)
```

Identical count and identical ordinal means the source tree matches what CodeWeavers shipped, and the only
difference is the one intended.

## The architecture this all rests on — and when it expires

Everything above targets **x86_64**, because that is what CrossOver 26.3 is, all the way down:

```
lib/wine/    i386-windows   x86_64-unix   x86_64-windows      (no aarch64 anywhere)
wineserver, ntdll.so, libMoltenVK.dylib    all lipo -archs = x86_64
```

The Unix side runs under Rosetta too. That is *why* this project's hardest problems are Rosetta bugs.

CodeWeavers' Preview release notes state that **Intel/x86_64 support ends with macOS 28**, and that
they are moving to native **arm64 with Rosetta running the PE side** — the new-wow64 arrangement used
on Linux — described there as not yet stable. (Stated by CodeWeavers; not independently verified here.)

### Why that is not just a recompile

Wine compiles exactly one signal-handling file per target architecture:

```
dlls/ntdll/unix/signal_arm.c
dlls/ntdll/unix/signal_arm64.c
dlls/ntdll/unix/signal_i386.c
dlls/ntdll/unix/signal_x86_64.c   ← both Rosetta fixes live here
```

On an arm64 Unix side, `signal_x86_64.c` **is not compiled at all**. The patches do not need porting
so much as re-deriving: the game is still an x86_64 PE still running under Rosetta, so the two bugs
(multi-byte NOP misreported as illegal, `mov reg,cr3` delivered as invalid-opcode instead of `#GP`)
are presumably still there — but they now surface through arm64 Unix code receiving a fault from
Rosetta, which is a different path from the one these fixes sit on.

| Module | Side | Under arm64 Unix |
|---|---|---|
| `ntdll.so` | Unix | **Rosetta fixes do not apply**; needs re-deriving |
| `winebus.so` | Unix | Patch 03's SDL code is platform-independent, but needs an arm64 toolchain |
| `winebus.sys`, `ntoskrnl.exe`, `kernel32.dll` | PE | Unaffected — still x86_64 PE |

So the gamepad work (patches 02/03/04) and `PsGetProcessExitStatus` (01) survive largely intact. The
cost falls on upstream Endfield_FineWine's central contribution: the stage-1 Rosetta fixes.

### Recommendation

**Stay on x86_64 builds for now.** The toolchain, the patches and the whole verification approach are
built around it, and the arm64 path is described by its own authors as unstable.

But this is the one item in this project with an actual deadline. Freezes, Vulkan, newer Wine — those
are trade-offs. This one isn't: once x86_64 Wine is gone, none of this works. Worth revisiting when
any of these happen:

1. CodeWeavers declares the arm64 build stable;
2. macOS 28 reaches beta;
3. someone lands Rosetta fixes for the arm64 path first.

## Building against CrossOver Preview (Wine 11.15)

Preview ships **D3DMetal 4.0b2** where the 26.3 release ships 3.0, so a Preview-based install has
working DLSS without anyone hand-installing GPTK4. The toolchain is identical — same x86_64, same
SDL 2.30.12 — but three things differ.

**1. Libraries live in `lib/x86_64/`, not `lib64/`.** That changes the rpaths, and the longer path
does not fit:

```
26.3      ntdll.so    @loader_path/../../../lib64
preview   ntdll.so    @loader_path/../../../lib/x86_64
26.3      winebus.so  @loader_path/../lib64        + ../../../lib64
preview   winebus.so  @loader_path/../lib/x86_64   + ../../../lib/x86_64
```

`install_name_tool -add_rpath` **fails** for the Preview paths — *"larger updated load commands do not
fit"*, because a Mach-O only reserves so much header padding. It works on 26.3 purely because `lib64`
is short. **Add the rpath at link time instead:**

```bash
rm -f dlls/ntdll/ntdll.so
make dlls/ntdll/ntdll.so LDFLAGS="-arch x86_64 -Wl,-rpath,@loader_path/../../../lib/x86_64"
```

**2. Two upstream patches must be skipped, not merely allowed to fail.** Wine 11.15 implements
`KeAcquireGuardedMutex` / `KeReleaseGuardedMutex` itself in `sync.c` (as `FASTCALL`, which is more
correct than the dw-proton version). Their patches do report failure — but `patch` applies
**hunk by hunk**: the `.spec` hunk conflicts and leaves a `.rej`, while the `sync.c` hunk goes in
regardless, and the build then dies on `redefinition of 'KeAcquireGuardedMutex'`.

*A failed patch is not an unapplied patch.* Check what actually landed:

```bash
grep -cE '^(void|VOID) (WINAPI|FASTCALL) KeAcquireGuardedMutex\(' dlls/ntoskrnl.exe/sync.c   # must be 1
find . -name '*.rej'
```

By contrast `0001-macos-rosetta-signal-fixes` fails with **both** hunks rejected, so it writes
nothing. Same word "failed", opposite consequences — check each one.

**3. Preview has a compile error of its own.** `dlls/winemac.drv/cocoa_app.m` initialises a `static`
with an Objective-C array literal, which is not a compile-time constant:

```objc
static NSArray<NSString *> *whitelistedAUMIDs = @[ ... ];   // error
```

CrossOver 26.3 uses `dispatch_once` in the same place, which is correct; revert to that. This is
Preview's own regression — it fails with no patches applied at all.

### What still has to be ported by hand

Of upstream's 23 patches, 20 apply cleanly to 11.15. Of the rest:

- The two guarded-mutex ones are obsolete (above).
- `0001-macos-rosetta-signal-fixes` needs partial porting. CodeWeavers implemented **half of it
  themselves** — 11.15 has `emulate_nop()` (`CW HACK 27328, 25932, 27266`) for the multi-byte NOP.
  Theirs only accepts the register forms `0F 1F C0/C1/C2`; widening it to a full modrm decode is
  worthwhile. The **privileged-instruction half still has to be added**, in `TRAP_x86_PRIVINFLT`
  after `emulate_nop`:

```c
rec.ExceptionCode = is_privileged_instr( &context.c );
if (rec.ExceptionCode) break;
```

Keep upstream's `CWC-ILLEGAL-INSTR` logging next to it. It exists so an unhandled instruction can be
read off the byte stream instead of guessed at, and it is exactly what you will want the moment
something does not start.

### The bottle must be created by Preview

This costs the most time to diagnose, so it goes last and loudest:

**A bottle marked `26.3.0.39832` opened by a `27.0.0` Preview fails silently.** The process exits
immediately, the log is **zero bytes**, and nothing is printed anywhere.

Create a fresh one with Preview's own `cxbottle`, with the **`win11_64`** template (the default
`win10_64` does not run the game), then carry over `[EnvironmentVariables]`, the game's settings
(`Software\Hypergryph\*`), `Software\Wine\Mac Driver`, `Software\Wine\DllOverrides`, and the
`Services\winebus` section.

If something does not start, the first move is the control experiment — it is the only thing that
separates "our modules are broken" from "the environment is wrong":

```
stock Preview  + old bottle   ✗        ← unpatched, fails too => not our modules
patched Preview + old bottle  ✗
patched Preview + new bottle  ✓
```

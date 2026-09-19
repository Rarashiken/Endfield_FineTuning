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
export CFLAGS="-arch x86_64" CXXFLAGS="-arch x86_64" LDFLAGS="-arch x86_64"

mkdir -p build/wine-build64 && cd build/wine-build64
../wine-src/configure --enable-win64 --disable-tests \
  --build=x86_64-apple-darwin --host=x86_64-apple-darwin
```

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
make dlls/winebus.sys/winebus.so \
  CFLAGS="-arch x86_64 -I$S/sdl2/include -DHAVE_SDL_H -DSONAME_LIBSDL2=\"libSDL2-2.0.0.dylib\"" \
  LDFLAGS="-arch x86_64 -Wl,-rpath,@loader_path/../lib64 -Wl,-rpath,@loader_path/../../../lib64"
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

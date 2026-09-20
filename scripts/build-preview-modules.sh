#!/bin/bash
# 编译 Preview(Wine 11.15)的五个模块。先跑 scripts/prepare-preview-source.sh。
#
#   BUILD_ROOT=~/cx-preview-build scripts/build-preview-modules.sh
#
# BUILD_ROOT 下需要 toolchain/(llvm-mingw、bison-install、sdl2)与 sources/wine。
# 编译 Wine 11.15(CrossOver Preview 20260821)的五个模块。
# 与 26.3 那次的唯一区别是 rpath:preview 的库在 lib/x86_64/,不是 lib64/。
set -euo pipefail
R="${BUILD_ROOT:?需要 BUILD_ROOT=构建目录}"
S="$R/toolchain"
SRC="$R/sources/wine"
BLD="$R/wine-build64"

MW=$(ls -d "$S"/llvm-mingw-*/ | head -1)
# llvm-mingw 必须在 PATH 最前 —— 放末尾会让 winebuild 调到 /usr/bin/clang,
# 报的却是 xcrun libxcrun 缺 x86_64 slice,极具误导性。
export PATH="${MW}bin:$S/bison-install/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=10.15
export CFLAGS="-arch x86_64" CXXFLAGS="-arch x86_64" LDFLAGS="-arch x86_64"

echo "=== 确认工具来源 ==="
echo "  clang:      $(command -v clang)"
echo "  bison:      $(command -v bison)  $(bison --version | head -1 | grep -o '[0-9.]*$')"

mkdir -p "$BLD" && cd "$BLD"
if [ ! -f Makefile ]; then
  echo "=== configure ==="
  # 参数取自 26.3 那次实际用过的 config.status,不是 docs 里那条简写。
  # CC 必须是系统 clang(unix 侧编的是 macOS 原生代码);llvm-mingw 只管 PE 侧,
  # 由 winebuild 通过 PATH 找到。--without-sdl 是故意的,winebus.so 之后单独重编注入。
  "$SRC/configure" \
    --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
    --enable-archs=x86_64 --disable-tests \
    --without-x --without-freetype --without-gnutls --without-sdl --without-vulkan \
    --without-krb5 --without-gstreamer --without-gphoto --without-sane \
    --without-pcap --without-usb --without-cups \
    CC=/usr/bin/clang CXX=/usr/bin/clang++ \
    CFLAGS="-arch x86_64" CXXFLAGS="-arch x86_64" LDFLAGS="-arch x86_64" > configure.log 2>&1 \
    || { echo "configure 失败,见 $BLD/configure.log"; tail -20 configure.log; exit 1; }
  echo "  完成"
fi

echo "=== make -j$(sysctl -n hw.ncpu) ==="
make -j"$(sysctl -n hw.ncpu)" > build.log 2>&1 || {
  echo "make 失败,最后 30 行:"; tail -30 build.log; exit 1; }
echo "  完成"

# ntdll.so 的 rpath 必须在链接时加,不能事后 install_name_tool ——
# "@loader_path/../../../lib/x86_64" 比 26.3 的 ".../lib64" 长,Mach-O 的 header
# 预留空间塞不下,install_name_tool 会直接拒绝。CodeWeavers 自己也是链接时加的。
echo "=== 单独重链 ntdll.so(带 preview 的 rpath)==="
rm -f dlls/ntdll/ntdll.so
make dlls/ntdll/ntdll.so \
  LDFLAGS="-arch x86_64 -Wl,-rpath,@loader_path/../../../lib/x86_64" \
  > ntdll.log 2>&1 || { echo "ntdll.so 失败:"; tail -20 ntdll.log; exit 1; }
echo "  完成"

echo "=== 单独重编 winebus.so(带 SDL + preview 的 rpath)==="
rm -f dlls/winebus.sys/bus_sdl.o dlls/winebus.sys/winebus.so
# 引号要穿过 shell -> make -> sh 三层才到 clang。双引号里的 \" 只够走一层,
# 宏展开成裸的 libSDL2-2.0.0.dylib,clang 把它当浮点数字面量。单引号保住反斜杠。
SDL_DEF='-DSONAME_LIBSDL2=\"libSDL2-2.0.0.dylib\"'
make dlls/winebus.sys/winebus.so \
  CFLAGS="-arch x86_64 -I$S/sdl2/include -DHAVE_SDL_H $SDL_DEF" \
  LDFLAGS="-arch x86_64 -Wl,-rpath,@loader_path/../lib/x86_64 -Wl,-rpath,@loader_path/../../../lib/x86_64" \
  > winebus.log 2>&1 || { echo "winebus.so 失败:"; tail -20 winebus.log; exit 1; }
echo "  完成"

echo
echo "=== 产物 ==="
ok=1
for m in dlls/ntdll/ntdll.so dlls/winebus.sys/winebus.so \
         dlls/winebus.sys/x86_64-windows/winebus.sys \
         dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe \
         dlls/kernel32/x86_64-windows/kernel32.dll; do
  if [ -f "$BLD/$m" ]; then printf "  ✓ %-46s %s\n" "$m" "$(stat -f%z "$BLD/$m") bytes"
  else printf "  ✗ %s 缺失\n" "$m"; ok=0; fi
done
echo
echo "=== ntdll.so rpath 检查 ==="
otool -l "$BLD/dlls/ntdll/ntdll.so" | grep -A2 LC_RPATH | grep "path " | sed 's/.*path /    /;s/ (offset.*//'
otool -l "$BLD/dlls/ntdll/ntdll.so" | grep -A2 LC_RPATH | grep -qF "lib/x86_64" \
  && echo "  ✓ lib/x86_64 已就位(D3DMetal 需要)" || echo "  ✗ 缺 lib/x86_64 rpath"

echo "=== winebus.so 的 SDL 与 rpath 检查 ==="
if strings "$BLD/dlls/winebus.sys/winebus.so" | grep -q "SDL support not compiled in"; then
  echo "  ✗ SDL 没编进去"
else
  echo "  ✓ SDL 已编入"
fi
strings "$BLD/dlls/winebus.sys/winebus.so" | grep -q "libSDL2-2.0.0.dylib" \
  && echo "  ✓ SONAME_LIBSDL2 = libSDL2-2.0.0.dylib" \
  || echo "  ✗ 找不到 libSDL2-2.0.0.dylib 字符串 —— dlopen 会失败"
otool -l "$BLD/dlls/winebus.sys/winebus.so" | grep -A2 LC_RPATH | grep "path " | sed 's/.*path /    /;s/ (offset.*//'
[ "$ok" = 1 ] && echo && echo "全部就绪。"

#!/bin/bash
# 装编译 Wine 所需的工具链:llvm-mingw(PE 交叉编译)、bison 3.8.2(macOS 自带 2.3 太旧)、
# SDL 2.30.12 头文件(编 winebus.so 的 SDL 支持)。只需要 Xcode Command Line Tools。
#
#   BUILD_ROOT=~/cx-preview-build scripts/setup-toolchain.sh
#
# 全部装进 $BUILD_ROOT/toolchain,删掉重跑即可,不碰系统。
set -euo pipefail
S="${BUILD_ROOT:?需要 BUILD_ROOT}/toolchain"
cd "$S"

echo "[1/3] llvm-mingw"
if [ -d llvm-mingw-20260908-ucrt-macos-universal ]; then
  echo "  已存在,跳过"
else
  curl -fsSLO https://github.com/mstorsjo/llvm-mingw/releases/download/20260908/llvm-mingw-20260908-ucrt-macos-universal.tar.xz
  tar xf llvm-mingw-20260908-ucrt-macos-universal.tar.xz
  rm -f llvm-mingw-20260908-ucrt-macos-universal.tar.xz
  echo "  完成"
fi

echo "[2/3] bison 3.8.2"
if [ -x "$S/bison-install/bin/bison" ]; then
  echo "  已存在,跳过"
else
  curl -fsSLO https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz
  tar xf bison-3.8.2.tar.xz
  cd bison-3.8.2
  ./configure --prefix="$S/bison-install" >/dev/null
  make -j"$(sysctl -n hw.ncpu)" >/dev/null 2>&1
  make install >/dev/null
  cd "$S"
  rm -rf bison-3.8.2 bison-3.8.2.tar.xz
  echo "  完成: $("$S/bison-install/bin/bison" --version | head -1)"
fi

echo "[3/3] SDL 2.30.12 headers"
if [ -f "$S/sdl2/include/SDL.h" ]; then
  echo "  已存在,跳过"
else
  curl -fsSL -o sdl.tar.gz https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.30.12.tar.gz
  tar xf sdl.tar.gz
  mkdir -p sdl2
  mv SDL-release-2.30.12/include sdl2/include
  rm -rf SDL-release-2.30.12 sdl.tar.gz
  echo "  完成"
fi

echo
echo "工具链就绪:"
echo "  clang:  $("$S"/llvm-mingw-*/bin/x86_64-w64-mingw32-clang --version 2>/dev/null | head -1)"
echo "  bison:  $("$S/bison-install/bin/bison" --version | head -1)"
echo "  SDL.h:  $(ls "$S/sdl2/include/SDL.h")"

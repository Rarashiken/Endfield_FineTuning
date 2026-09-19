#!/bin/bash
# 把自行编译的 Wine 模块换进 CrossOver-Endfield.app
#
# 相比上游 swap-into-crossover.sh 的关键修正:
#   - 补回 CrossOver 打包时加的 lib64 rpath(上游脚本不管这个,直接换会让 D3DMetal 加载不到库)
#   - 重签名不用 --deep
set -euo pipefail

APP="${APP:-/Applications/CrossOver-Endfield.app}"
CXR="$APP/Contents/SharedSupport/CrossOver"
BLD="${BLD:?请设置 BLD 为 wine 构建目录, 例如 ~/cx-build/wine-build64}"
STAMP=$(date +%Y%m%d-%H%M%S)
BAK="${BAKDIR:-$HOME/.endfield-module-backups}/$STAMP"   # 必须在 bundle 外,否则会被算进签名封印

[ -d "$APP" ] || { echo "找不到 $APP"; exit 1; }
[ -d "$BLD" ] || { echo "找不到构建目录 $BLD"; exit 1; }

# --- 1. 确认 CrossOver 已退出 ---
if pgrep -f "$APP/Contents/MacOS/CrossOver" >/dev/null 2>&1; then
  echo "CrossOver 仍在运行,请先退出"; exit 1
fi
if pgrep -x wineserver >/dev/null 2>&1; then
  echo "wineserver 仍在运行,请先退出所有瓶子"; exit 1
fi

# --- 2. 备份 ---
mkdir -p "$BAK/x86_64-unix" "$BAK/x86_64-windows"
cp -p "$CXR/lib/wine/x86_64-unix/ntdll.so"        "$BAK/x86_64-unix/"
cp -p "$CXR/lib/wine/x86_64-windows/ntoskrnl.exe" "$BAK/x86_64-windows/"
cp -p "$CXR/lib/wine/x86_64-windows/kernel32.dll" "$BAK/x86_64-windows/"
echo "已备份到 $BAK"

# --- 3. 替换 ---
install -m 755 "$BLD/dlls/ntdll/ntdll.so"                            "$CXR/lib/wine/x86_64-unix/ntdll.so"
install -m 755 "$BLD/dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe"  "$CXR/lib/wine/x86_64-windows/ntoskrnl.exe"
install -m 755 "$BLD/dlls/kernel32/x86_64-windows/kernel32.dll"      "$CXR/lib/wine/x86_64-windows/kernel32.dll"

# --- 4. 补回 lib64 rpath(D3DMetal 依赖) ---
NT="$CXR/lib/wine/x86_64-unix/ntdll.so"
RP='@loader_path/../../../lib64'
if ! otool -l "$NT" | grep -A2 LC_RPATH | grep -q "$RP"; then
  install_name_tool -add_rpath "$RP" "$NT"
  echo "已补回 rpath: $RP"
fi
otool -l "$NT" | grep -A2 LC_RPATH | grep -q lib64 || { echo "rpath 补回失败"; exit 1; }

# --- 5. 重新签名(ntdll.so 单独签,bundle 不用 --deep) ---
codesign --force --sign - "$NT"
ENT=$(mktemp /tmp/cxent.XXXXXX.plist)
codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null || rm -f "$ENT"
if [ -s "${ENT:-/nonexistent}" ]; then
  codesign --force --sign - --entitlements "$ENT" "$APP"
  rm -f "$ENT"
else
  codesign --force --sign - "$APP"
fi
codesign --verify "$APP" && echo "签名校验通过"

echo
echo "完成。回滚: BAK=$BAK; cp -p \"\$BAK\"/x86_64-unix/* \"$CXR/lib/wine/x86_64-unix/\" 等"

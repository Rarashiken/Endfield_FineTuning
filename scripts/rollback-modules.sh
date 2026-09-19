#!/bin/bash
# 回滚 swap-built-modules.sh 的替换。用法:
#   ./rollback-modules.sh                # 用最新一次备份
#   ./rollback-modules.sh 20260920-010643
set -euo pipefail
APP="${APP:-/Applications/CrossOver-Endfield.app}"
CXR="$APP/Contents/SharedSupport/CrossOver"
BAKDIR="${BAKDIR:-$HOME/.endfield-module-backups}"
STAMP="${1:-$(ls -1 "$BAKDIR" | sort | tail -1)}"
BAK="$BAKDIR/$STAMP"
[ -d "$BAK" ] || { echo "找不到备份 $BAK"; exit 1; }

pgrep -f "$APP/Contents/MacOS/CrossOver" >/dev/null 2>&1 && { echo "请先退出 CrossOver"; exit 1; }
pgrep -x wineserver >/dev/null 2>&1 && { echo "请先退出所有瓶子"; exit 1; }

install -m 755 "$BAK/x86_64-unix/ntdll.so"        "$CXR/lib/wine/x86_64-unix/ntdll.so"
install -m 755 "$BAK/x86_64-windows/ntoskrnl.exe" "$CXR/lib/wine/x86_64-windows/ntoskrnl.exe"
install -m 755 "$BAK/x86_64-windows/kernel32.dll" "$CXR/lib/wine/x86_64-windows/kernel32.dll"

ENT=$(mktemp /tmp/cxent.XXXXXX.plist)
codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null || true
if [ -s "$ENT" ]; then codesign --force --sign - --entitlements "$ENT" "$APP"; else codesign --force --sign - "$APP"; fi
rm -f "$ENT"
codesign --verify "$APP" && echo "已回滚到 $STAMP,签名校验通过"

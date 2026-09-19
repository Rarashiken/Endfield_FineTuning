#!/usr/bin/env bash
# make-endfield-crossover.sh — 从干净的 CrossOver 26.3 产出可跑终末地的副本。
#
# 这是 2026-09-19 实际走通的流程,与上游 swap-into-crossover.sh 有三处关键差异:
#   1. 用 ditto 而不是 cp -a 复制 app(cp -a 会产出残缺 bundle —— 实测丢文件)
#   2. 重签顶层 bundle(不加 --deep,否则会洗掉 nested 二进制的 CodeWeavers 签名)
#   3. 改一个独立的 CFBundleIdentifier,避免与其他 CrossOver 在 LaunchServices 撞车
#
# 用法: ./make-endfield-crossover.sh [payload目录]
set -euo pipefail

SRC_APP="${SRC_APP:-/Applications/CrossOver.app}"
DEST_APP="${DEST_APP:-/Applications/CrossOver-Endfield.app}"
BUNDLE_ID="${BUNDLE_ID:-com.codeweavers.CrossOver.Endfield}"
PAYLOAD="${1:-${PAYLOAD:-}}"

log(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok(){  printf '  \033[32m✓\033[0m %s\n' "$*"; }

[ -d "$SRC_APP" ] || { echo "ERROR: 找不到 $SRC_APP"; exit 1; }
[ -n "$PAYLOAD" ] && [ -d "$PAYLOAD" ] || {
  echo "ERROR: 需要 payload 目录(含 x86_64-unix/ntdll.so 与 x86_64-windows/{kernel32.dll,ntoskrnl.exe})"
  echo "       从 FineWine Patcher.app/Contents/Resources/payload 取得"
  exit 1; }

log "1. 复制 $SRC_APP -> $DEST_APP (ditto)"
rm -rf "$DEST_APP"
ditto "$SRC_APP" "$DEST_APP"
ok "$(du -sh "$DEST_APP" | cut -f1)"

CXR="$DEST_APP/Contents/SharedSupport/CrossOver"
log "2. 换入补丁模块"
for m in "x86_64-unix/ntdll.so:lib/wine/x86_64-unix/ntdll.so" \
         "x86_64-windows/kernel32.dll:lib/wine/x86_64-windows/kernel32.dll" \
         "x86_64-windows/ntoskrnl.exe:lib/wine/x86_64-windows/ntoskrnl.exe"; do
  src="${m%%:*}"; dst="${m##*:}"
  [ -f "$PAYLOAD/$src" ] || { echo "ERROR: payload 缺 $src"; exit 1; }
  cp -f "$CXR/$dst" "$CXR/$dst.cxorig"
  ditto "$PAYLOAD/$src" "$CXR/$dst"
  ok "$(basename "$dst")"
done

log "3. ntdll.so ad-hoc 签名 + 校验 lib64 rpath (D3DMetal 必需)"
codesign --force --sign - "$CXR/lib/wine/x86_64-unix/ntdll.so"
otool -l "$CXR/lib/wine/x86_64-unix/ntdll.so" | grep -A2 LC_RPATH | grep -q lib64 \
  && ok "lib64 rpath 存在" || { echo "ERROR: ntdll.so 缺 lib64 rpath,D3DMetal 不会生效"; exit 1; }

log "4. 独立 bundle identifier"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$DEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName CrossOver-Endfield" "$DEST_APP/Contents/Info.plist" 2>/dev/null || true
ok "$BUNDLE_ID"

log "5. 重签顶层 bundle + 去隔离"
ENT="$(mktemp -t cxent).plist"
codesign -d --entitlements "$ENT" --xml "$SRC_APP" 2>/dev/null || true
if [ -s "$ENT" ]; then
  codesign --force --sign - --entitlements "$ENT" "$DEST_APP"
else
  codesign --force --sign - "$DEST_APP"
fi
rm -f "$ENT"
xattr -drs com.apple.quarantine "$DEST_APP" 2>/dev/null || true
ok "已重签(ad-hoc)并去隔离"

log "6. 验证"
perl -e 'alarm 25; exec @ARGV' "$CXR/bin/wineserver" --version \
  && ok "wineserver 正常" || { echo "ERROR: wineserver 异常(rc=$?),副本不可用"; exit 1; }

cat <<MSG

完成 -> $DEST_APP

创建容器并启动:
  export CX_ROOT="$CXR"
  "\$CX_ROOT/bin/cxbottle" --bottle endfield263 --create --template win11_64
  # 把图形变量写进 Bottles/endfield263/cxbottle.conf 的 [EnvironmentVariables] 段
  "\$CX_ROOT/bin/wine" --bottle endfield263 --wait-children \\
    --cx-app 'Y:\\WindowsGames\\Arknight Endfield\\Endfield.exe' -force-d3d11

注意: --cx-app 必须用 Windows 路径(Y: 映射到用户主目录),macOS 路径会被当成
      drive_c 相对路径而找不到。
MSG

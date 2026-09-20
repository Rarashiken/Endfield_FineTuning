#!/usr/bin/env bash
# build-app.sh — build "Endfield Patcher.app" (SwiftPM + manual bundle assembly; no Xcode needed,
# only the Command Line Tools).
#
# The app bundles the three pre-built patched Wine modules as its payload, so a completed
# Wine build must exist first:  scripts/build-wine.sh all   (from the repo root)
#
# Usage:  patcher-app/scripts/build-app.sh
# Env:
#   PAYLOAD_DIR_RELEASE     modules built against CrossOver 26.3   (Wine 11.0)
#   PAYLOAD_DIR_PREVIEW     modules built against Preview 20260821 (Wine 11.15)
#   PAYLOAD_DIR             alias for PAYLOAD_DIR_RELEASE
#   APP_NAME / BUNDLE_ID    override, for building one variant per flavour
#                           (default: <repo>/build/wine-build64, the build-wine.sh output tree;
#                            a flat directory holding ntdll.so/kernel32.dll/ntoskrnl.exe also works)
#   CODESIGN_ID             signing identity (default "-" = ad-hoc; set your "Developer ID
#                           Application: …" identity for notarizable builds)
#   ALLOW_MISSING_PAYLOAD=1 build without payload (smoke-test builds only — the app will
#                           refuse to patch, and says so in its UI)
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"          # patcher-app/
REPO="$(cd "$HERE/.." && pwd)"
APP_NAME="${APP_NAME:-Endfield Patcher}"
EXE="EndfieldPatcher"
BUNDLE_ID="${BUNDLE_ID:-io.github.Rarashiken.EndfieldPatcher}"
VERSION="1.0.0"
CODESIGN_ID="${CODESIGN_ID:--}"
OUT="$HERE/build"
APP="$OUT/$APP_NAME.app"

log(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok(){  printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- 1. compile
log "Compiling (swift build, release)"
swift build -c release --package-path "$HERE"
BIN="$(swift build -c release --package-path "$HERE" --show-bin-path)/$EXE"
[ -x "$BIN" ] || { echo "ERROR: build produced no executable at $BIN"; exit 1; }
ok "$(file -b "$BIN")"

# ---------------------------------------------------------------- 2. assemble bundle
log "Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/licenses" \
         "$APP/Contents/Resources/payload/x86_64-unix" \
         "$APP/Contents/Resources/payload/x86_64-windows"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
cp "$HERE/Resources/licenses/"*.txt "$APP/Contents/Resources/licenses/"

ICON_PLIST=""
if [ -f "$HERE/Resources/AppIcon.icns" ]; then
  cp "$HERE/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  ICON_PLIST=$'\t<key>CFBundleIconFile</key>\n\t<string>AppIcon</string>'
  ok "app icon"
else
  warn "Resources/AppIcon.icns not found — building without an icon (run scripts/make-appicon.sh)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleExecutable</key>
	<string>$EXE</string>
$ICON_PLIST
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>MIT — © 2026 Endfield_FineWine contributors. Bundled Wine modules: LGPL-2.1-or-later.</string>
</dict>
</plist>
PLIST
plutil -lint -s "$APP/Contents/Info.plist"
ok "bundle skeleton + Info.plist"

# ---------------------------------------------------------------- 3. payload
#
# Two payloads, one per CrossOver flavour. Wine modules are ABI-bound to the Wine
# they were built from, so the patcher picks by the Wine version it finds in the
# target's own ntdll.so; installing the wrong one crashes rather than degrades.
#
#   PAYLOAD_DIR_RELEASE   modules built against CrossOver 26.3   (Wine 11.0,  libs in lib64/)
#   PAYLOAD_DIR_PREVIEW   modules built against Preview 20260821 (Wine 11.15, libs in lib/x86_64/)
#
# At least one must be present. PAYLOAD_DIR is accepted as an alias for the release one.
PAYLOAD_DIR_RELEASE="${PAYLOAD_DIR_RELEASE:-${PAYLOAD_DIR:-$REPO/build/wine-build64}}"
PAYLOAD_DIR_PREVIEW="${PAYLOAD_DIR_PREVIEW:-}"

stage_payload(){ # 1=label  2=source dir  3=payload subdir  4=rpath suffix (lib64 | lib/x86_64)
  local label="$1" dir="$2" sub="$3" libdir="$4"
  local P="$APP/Contents/Resources/payload/$sub"

  find_module(){ # flat-name  tree-relative-path
    if   [ -f "$dir/$2" ]; then echo "$dir/$2"
    elif [ -f "$dir/$1" ]; then echo "$dir/$1"
    else echo ""; fi
  }
  local NTDLL KERNEL32 NTOSKRNL WINEBUS_SO WINEBUS_SYS
  NTDLL="$(find_module ntdll.so dlls/ntdll/ntdll.so)"
  KERNEL32="$(find_module kernel32.dll dlls/kernel32/x86_64-windows/kernel32.dll)"
  NTOSKRNL="$(find_module ntoskrnl.exe dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe)"
  WINEBUS_SO="$(find_module winebus.so dlls/winebus.sys/winebus.so)"
  WINEBUS_SYS="$(find_module winebus.sys dlls/winebus.sys/x86_64-windows/winebus.sys)"
  if [ -z "$NTDLL" ] || [ -z "$KERNEL32" ] || [ -z "$NTOSKRNL" ] || [ -z "$WINEBUS_SO" ] || [ -z "$WINEBUS_SYS" ]; then
    return 1
  fi

  mkdir -p "$P/x86_64-unix" "$P/x86_64-windows"
  cp "$NTDLL"       "$P/x86_64-unix/ntdll.so"
  cp "$KERNEL32"    "$P/x86_64-windows/kernel32.dll"
  cp "$NTOSKRNL"    "$P/x86_64-windows/ntoskrnl.exe"
  cp "$WINEBUS_SO"  "$P/x86_64-unix/winebus.so"
  cp "$WINEBUS_SYS" "$P/x86_64-windows/winebus.sys"

  # rpaths are added HERE, at app-build time, so patcher users never need Xcode tools.
  # ntdll.so: CrossOver's ntdll dlopens cxcompatdb.so, which resolves @rpath/... through
  # ntdll.so's own LC_RPATH — miss it and D3DMetal never engages.
  # winebus.so: it dlopens libSDL2 by leaf name — miss it and the SDL backend fails
  # silently, meaning no controller at all.
  local NT="$P/x86_64-unix/ntdll.so" WB="$P/x86_64-unix/winebus.so"
  if ! otool -l "$NT" >/dev/null 2>&1; then
    if [ "${ALLOW_MISSING_PAYLOAD:-0}" = "1" ]; then
      warn "$label: ntdll.so is not a Mach-O (dummy payload?) — skipping rpaths"; return 0
    fi
    echo "ERROR: $NTDLL is not a Mach-O binary"; exit 1
  fi
  local rp
  for rp in "@loader_path/../../../$libdir"; do
    otool -l "$NT" | grep -A2 LC_RPATH | grep -qF "$rp" || install_name_tool -add_rpath "$rp" "$NT"
    otool -l "$NT" | grep -A2 LC_RPATH | grep -qF "$rp" \
      || { echo "ERROR: could not add rpath $rp to ntdll.so ($label)"; exit 1; }
  done
  for rp in "@loader_path/../$libdir" "@loader_path/../../../$libdir"; do
    otool -l "$WB" | grep -A2 LC_RPATH | grep -qF "$rp" || install_name_tool -add_rpath "$rp" "$WB"
    otool -l "$WB" | grep -A2 LC_RPATH | grep -qF "$rp" \
      || { echo "ERROR: could not add rpath $rp to winebus.so ($label)"; exit 1; }
  done

  local f
  for f in "$P/x86_64-unix/ntdll.so" "$P/x86_64-windows/kernel32.dll" "$P/x86_64-windows/ntoskrnl.exe" \
           "$P/x86_64-unix/winebus.so" "$P/x86_64-windows/winebus.sys"; do
    codesign --force --sign "$CODESIGN_ID" "$f" 2>/dev/null || true
  done
  ok "$label: 5 modules staged, rpaths → $libdir"
  return 0
}

log "Staging payloads"
rm -rf "$APP/Contents/Resources/payload"
STAGED=0
if stage_payload "CrossOver 26.3" "$PAYLOAD_DIR_RELEASE" "release" "lib64"; then
  STAGED=$((STAGED+1))
else
  warn "no modules under PAYLOAD_DIR_RELEASE ($PAYLOAD_DIR_RELEASE)"
fi
if [ -n "$PAYLOAD_DIR_PREVIEW" ]; then
  if stage_payload "CrossOver Preview" "$PAYLOAD_DIR_PREVIEW" "preview" "lib/x86_64"; then
    STAGED=$((STAGED+1))
  else
    warn "no modules under PAYLOAD_DIR_PREVIEW ($PAYLOAD_DIR_PREVIEW)"
  fi
fi
if [ "$STAGED" = 0 ] && [ "${ALLOW_MISSING_PAYLOAD:-0}" != "1" ]; then
  echo "ERROR: no payload staged. Set PAYLOAD_DIR_RELEASE and/or PAYLOAD_DIR_PREVIEW."
  exit 1
fi

# ---------------------------------------------------------------- 4. sign
log "Signing ($CODESIGN_ID)"
if [ "$CODESIGN_ID" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$APP"
fi
codesign --verify "$APP"
ok "signature verifies"

# ---------------------------------------------------------------- 5. done
log "Done -> $APP"
cat <<EOF

Next:
  open "$APP"

Notes:
  - Ad-hoc-signed builds are for your own machine. To distribute, re-run with
    CODESIGN_ID="Developer ID Application: …" and notarize, or tell users to
    right-click -> Open on first launch.
  - If you distribute the built app, the bundled Wine modules are LGPL-2.1:
    publish the patches + exact CrossOver source used (see patcher-app/README.md).
EOF

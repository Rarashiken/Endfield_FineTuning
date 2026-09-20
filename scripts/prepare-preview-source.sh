#!/bin/bash
# 把 CrossOver Preview 的源码准备成可编译的补丁树。
#
#   BUILD_ROOT=~/cx-preview-build \
#   SOURCE_TARBALL=~/crossover-sources-20260821.tar.gz \
#   UPSTREAM_PATCHES=~/Endfield_FineWine/patches \
#     scripts/prepare-preview-source.sh
#
# 之后用 scripts/build-preview-modules.sh 编译。详见 docs/01-build-environment.md。
# 从干净源码准备 Wine 11.15 的补丁树。
set -euo pipefail
R="${BUILD_ROOT:?需要 BUILD_ROOT=构建目录}"
SRC="$R/sources/wine"
P="${UPSTREAM_PATCHES:?需要 UPSTREAM_PATCHES=上游 patches 目录}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MY="$HERE/../patches"

# 上游已自行实现(11.15 的 sync.c 里有 FASTCALL 版本),再打就是重复定义。
# 注意:这两个补丁 patch 会报"失败"(.spec 冲突),但 sync.c 的 hunk 会照样写入 ——
# 失败不等于没改动,必须显式跳过。
SKIP="0001-ntoskrnl.exe-Implement-KeAcquireGuardedMutex.patch
0002-ntoskrnl.exe-Implement-KeReleaseGuardedMutex.patch"

echo "=== 重新解包 ==="
mkdir -p "$R"
rm -rf "$R/sources"
tar -xzf "${SOURCE_TARBALL:?需要 SOURCE_TARBALL=crossover-sources-*.tar.gz}" -C "$R" sources/wine
echo "  $(cat "$SRC/VERSION")"

echo "=== 上游补丁 ==="
ok=0; skipped=0; failed=0
for f in $(find "$P" -name "*.patch" | sort); do
  n=$(basename "$f")
  if echo "$SKIP" | grep -qx "$n"; then
    echo "  跳过 $n (上游已实现)"; skipped=$((skipped+1)); continue
  fi
  if patch -p1 -d "$SRC" --forward -F 3 < "$f" >/dev/null 2>&1; then
    ok=$((ok+1))
  else
    echo "  ✗ $n"; failed=$((failed+1))
  fi
done
echo "  应用 $ok / 跳过 $skipped / 失败 $failed"

echo "=== 检查有没有残留 .rej(失败补丁可能已部分写入)==="
rej=$(find "$SRC" -name "*.rej")
if [ -n "$rej" ]; then echo "$rej" | sed "s|$SRC/|  |"; else echo "  无"; fi

echo "=== 构建修复:cocoa_app.m 的 static 初始化(preview 自身的回归)==="
/usr/bin/python3 "$HERE/fix-cocoa-static.py" "$SRC"

echo "=== 手工移植:Rosetta 特权指令修复 ==="
/usr/bin/python3 - "$SRC" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "dlls/ntdll/unix/signal_x86_64.c"
s = p.read_text()
if "Endfield_FineWine: Rosetta reports privileged" in s:
    print("  已应用,跳过"); sys.exit(0)
old = """        /* CW HACK 27328, 25932, 27266 */
        if (emulate_nop( sigcontext, &context.c )) return;
#endif
        rec.ExceptionCode = EXCEPTION_ILLEGAL_INSTRUCTION;
        break;"""
new = """        /* CW HACK 27328, 25932, 27266 */
        if (emulate_nop( sigcontext, &context.c )) return;
        /* Endfield_FineWine: Rosetta reports privileged instructions (e.g. mov reg,cr3 in
           ACE-BASE.sys) as invalid-opcode faults instead of #GP, so Wine would hand the app an
           EXCEPTION_ILLEGAL_INSTRUCTION where on Linux (#GP) it gets EXCEPTION_PRIV_INSTRUCTION. */
        rec.ExceptionCode = is_privileged_instr( &context.c );
        if (rec.ExceptionCode) break;
#endif
        rec.ExceptionCode = EXCEPTION_ILLEGAL_INSTRUCTION;
        break;"""
assert s.count(old) == 1, f"锚点出现 {s.count(old)} 次"
p.write_text(s.replace(old, new, 1))
print("  已移植")
PYEOF

echo "=== 本仓库四个补丁 ==="
for f in "$MY"/0*.sh; do
  echo "  --- $(basename "$f") ---"
  bash "$f" "$SRC" 2>&1 | sed 's/^/      /'
done
echo
echo "源码树就绪: $SRC"

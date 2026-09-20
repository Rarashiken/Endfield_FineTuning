#!/bin/bash
# 用法:
#   PREVIEW_CXR="/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver" \
#     scripts/make-preview-bottle.sh
#
#   SRC_BOTTLE  从哪个容器搬配置(默认 endfield263)
#   DST_BOTTLE  新建哪个(默认 endfield27)
#   TEMPLATE    默认 win11_64 —— win10_64 建出来的跑不起游戏
#
# 用 CrossOver Preview 建一个能跑终末地的容器,并把 26.3 容器里已验证的配置搬过来。
# 之所以必须新建:preview 是 27.0.0,打开 26.3 标记的容器会**静默失败**(日志 0 字节、无任何报错)。
set -euo pipefail
SRC_BOTTLE="${SRC_BOTTLE:-endfield263}"
DST_BOTTLE="${DST_BOTTLE:-endfield27}"
TEMPLATE="${TEMPLATE:-win11_64}"
A="${PREVIEW_CXR:?需要 PREVIEW_CXR=.../SharedSupport/CrossOver}"
BR="$HOME/Library/Application Support/CrossOver/Bottles"

pgrep -f "Endfield.exe -force" >/dev/null && { echo "游戏在跑,中止"; exit 1; }
rm -rf "$BR/$DST_BOTTLE"
CX_ROOT="$A" "$A/bin/cxbottle" --bottle "$DST_BOTTLE" --create \
  --template "$TEMPLATE" --description "Arknights Endfield (CrossOver Preview + FineTuning patches)"
echo "  建好: $(grep '"Version"' "$BR/$DST_BOTTLE/cxbottle.conf") $(grep '"Template"' "$BR/$DST_BOTTLE/cxbottle.conf")"

/usr/bin/python3 - "$BR/$SRC_BOTTLE" "$BR/$DST_BOTTLE" <<'PY'
import sys, re, pathlib
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

def merge_env():
    s = (src/"cxbottle.conf").read_text(encoding='utf-8')
    d = (dst/"cxbottle.conf").read_text(encoding='utf-8')
    lines = [l for l in re.search(r'\[EnvironmentVariables\](.*?)(?=\n\[|\Z)', s, re.S).group(1).splitlines()
             if re.match(r'^"\w+" = ', l)]
    m = re.search(r'\[EnvironmentVariables\]', d)
    have = re.search(r'\[EnvironmentVariables\](.*?)(?=\n\[|\Z)', d, re.S).group(1)
    add = [l for l in lines if f'"{l.split(chr(34))[1]}" = ' not in have]
    (dst/"cxbottle.conf").write_text(d[:m.end()] + "\n" + "\n".join(add) + d[m.end():], encoding='utf-8')
    print(f"  环境变量: {len(add)} 个")

def copy_sections(fname, header_re, label):
    s = (src/fname).read_text(encoding='utf-8', errors='replace')
    d = (dst/fname).read_text(encoding='utf-8', errors='replace')
    blocks = [m.group(0) for m in re.finditer(rf'^\[{header_re}\].*?(?=^\[|\Z)', s, re.S | re.M)]
    if not blocks:
        print(f"  {label}: 源里没有"); return
    kept = []
    for b in blocks:
        head = b.splitlines()[0]
        if head in d:
            exist = re.search(re.escape(head) + r'.*?(?=^\[|\Z)', d, re.S | re.M).group(0)
            miss = [k for k in re.findall(r'^"[^"]+"=.*$', b, re.M) if k.split('=')[0] not in exist]
            if miss:
                idx = d.index(head) + len(exist)
                d = d[:idx].rstrip() + "\n" + "\n".join(miss) + "\n\n" + d[idx:]
                kept.append(f"{head.strip()}(+{len(miss)})")
        else:
            d = d.rstrip() + "\n\n" + b.rstrip() + "\n"
            kept.append(f"{head.strip()}(整段)")
    (dst/fname).write_text(d, encoding='utf-8')
    print(f"  {label}: {len(kept)} 段")

merge_env()
copy_sections("user.reg",  r'Software\\\\Hypergryph.*?',              "游戏设置")
copy_sections("user.reg",  r'Software\\\\Wine\\\\Mac Driver',          "Retina/Mac Driver")
copy_sections("user.reg",  r'Software\\\\Wine\\\\DllOverrides',        "DLL overrides")
copy_sections("system.reg", r'System\\\\CurrentControlSet\\\\Services\\\\winebus', "winebus 手柄")
PY
echo "容器就绪: $DST_BOTTLE"

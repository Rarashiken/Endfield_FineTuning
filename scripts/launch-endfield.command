#!/bin/bash
# Arknights: Endfield launcher for a patched CrossOver bottle.
#
# Configure via environment variables (see README). Defaults assume:
#   - patched CrossOver at  /Applications/CrossOver-Endfield.app
#   - game installed at     $HOME/WindowsGames/Arknight Endfield
#   - bottle named          endfield263
#
# 《明日方舟:终末地》启动器。用环境变量覆盖下列默认值。

CXR="${CXR:-/Applications/CrossOver-Endfield.app/Contents/SharedSupport/CrossOver}"
export CX_ROOT="$CXR"
BOTTLE="${BOTTLE:-endfield263}"
# Windows path to the game exe (Y: maps to your home directory)
GAME_EXE="${GAME_EXE:-Y:\\WindowsGames\\Arknight Endfield\\Endfield.exe}"
BACKEND="${BACKEND:-dxmt}"
RETINA="${RETINA:-y}"
MSYNC="${MSYNC:-1}"
PADMODE="${PADMODE:-ps}"   # ps=DualSense 原生图标+按键(已验证) / xinput=回退到 Xbox 图标 / wgi、hid、hid-wgi=已实测失败
NVEXT="${NVEXT:-0}"   # DXMT 的 NVAPI 扩展;开了 DLSS 选项会出现但选中就黑屏
ARGS="${ARGS--force-gfx-direct -force-d3d11-bitblt-mode}"
CONF="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/cxbottle.conf"

# wineserver -k 是异步的;不等它真正退出就往下走,旧进程退出时会把注册表刷回旧内容。
kill_wineserver() {
  "$CXR/bin/wineserver" -k >/dev/null 2>&1
  for _w in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    /usr/bin/pgrep -x wineserver >/dev/null 2>&1 || return 0
    sleep 1
  done
  echo "警告: wineserver 15 秒内未退出" >&2
}

kill_wineserver
# 写入选定的后端
if ! /usr/bin/python3 - "$CONF" "$BACKEND" "$MSYNC" "$NVEXT" <<'PY'
import sys,re
p,b,m,nv=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
s=open(p,encoding='utf-8').read()
s,n1=re.subn(r'"CX_GRAPHICS_BACKEND" = "[^"]*"', f'"CX_GRAPHICS_BACKEND" = "{b}"', s)
s,n2=re.subn(r'"WINEMSYNC" = "[^"]*"',          f'"WINEMSYNC" = "{m}"',          s)
s,n3=re.subn(r'"DXMT_ENABLE_NVEXT" = "[^"]*"',  f'"DXMT_ENABLE_NVEXT" = "{nv}"',  s)
if n1 != 1 or n2 != 1 or n3 != 1:
    sys.exit(f"cxbottle.conf 未按预期替换: BACKEND={n1} MSYNC={n2} NVEXT={n3}")
open(p,'w',encoding='utf-8').write(s)
PY
then
  echo "错误: 写入 cxbottle.conf 失败,已中止" >&2; exit 1
fi
# 回读验证 —— 写入声称成功不等于生效
GOT_B=$(/usr/bin/grep -o '"CX_GRAPHICS_BACKEND" = "[^"]*"' "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
GOT_M=$(/usr/bin/grep -o '"WINEMSYNC" = "[^"]*"'          "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
GOT_N=$(/usr/bin/grep -o '"DXMT_ENABLE_NVEXT" = "[^"]*"'  "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
if [ "$GOT_B" != "$BACKEND" ] || [ "$GOT_M" != "$MSYNC" ] || [ "$GOT_N" != "$NVEXT" ]; then
  echo "错误: 期望 后端=$BACKEND msync=$MSYNC nvext=$NVEXT,实际 $GOT_B / $GOT_M / $GOT_N,已中止" >&2; exit 1
fi
# 手柄模式
#   xinput -> winebus 走 SDL,设备带 &IG_00 XInput 标记。Rewired 用 XInput,一律套
#             Xbox 360 映射(Rewired 官方文档),所以图标是 Xbox。已验证可用。
#   wgi    -> 保留 SDL 后端(游戏确定能看见设备),只对 Endfield.exe 禁用 xinput 系列 DLL。
#             &IG_00 设备的 VID/PID 仍是索尼的 054C/0DF2,而 WGI 不做 IG_ 过滤,
#             所以 Rewired 退到 WGI 后应能认出 DualSense。待实测。
#   hid-wgi-> 原生 IOHID + 禁 XInput。已实测:手柄无反应。
#   hid    -> 原生 IOHID + 保留 XInput。已实测:游戏完全识别不到手柄。
#             ^ 这两条说明"换成原生 HID 后端"本身就会让游戏看不到设备,与 XInput 无关。
# 注意 winebus 读的是 Services\winebus 本身,不是它的 Parameters 子键。
# 两个独立变量:winebus 后端(sdl / 原生HID)× 是否给游戏禁用 XInput
#                    winebus后端   禁游戏XInput  索尼XInput标记
case "$PADMODE" in
  ps)      PAD_HIDRAW=1; PAD_SDL=1; PAD_NOXI=0; PAD_SONYXI=0 ;;  # 仅去掉索尼手柄的 XInput 标记 <- 待测
  wgi)     PAD_HIDRAW=1; PAD_SDL=1; PAD_NOXI=1; PAD_SONYXI=1 ;;  # 已测:手柄无反应
  hid-wgi) PAD_HIDRAW=0; PAD_SDL=0; PAD_NOXI=1; PAD_SONYXI=1 ;;  # 已测:手柄无反应
  hid)     PAD_HIDRAW=0; PAD_SDL=0; PAD_NOXI=0; PAD_SONYXI=1 ;;  # 已测:游戏识别不到
  *)       PAD_HIDRAW=1; PAD_SDL=1; PAD_NOXI=0; PAD_SONYXI=1 ;;  # 已验证可用,Xbox 图标
esac
XIDLLS="xinput1_1 xinput1_2 xinput1_3 xinput1_4 xinput9_1_0 xinputuap"
{
  echo '@echo off'
  echo 'set K=HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winebus'
  echo "reg add \"%K%\" /v \"DisableHidraw\" /t REG_DWORD /d $PAD_HIDRAW /f >nul"
  echo "reg add \"%K%\" /v \"Enable SDL\"    /t REG_DWORD /d $PAD_SDL    /f >nul"
  echo "reg add \"%K%\" /v \"Sony XInput\"   /t REG_DWORD /d $PAD_SONYXI /f >nul"
  echo 'set O=HKEY_CURRENT_USER\Software\Wine\AppDefaults\Endfield.exe\DllOverrides'
  for d in $XIDLLS; do
    if [ "$PAD_NOXI" = 1 ]; then echo "reg add \"%O%\" /v \"$d\" /t REG_SZ /d \"\" /f >nul"
    else echo "reg delete \"%O%\" /v \"$d\" /f >nul 2>&1"; fi
  done
} > /tmp/_padcfg.bat
"$CXR/bin/wine" --bottle "$BOTTLE" --wait-children --cx-app 'Z:\tmp\_padcfg.bat' >/dev/null 2>&1
kill_wineserver
SR="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/system.reg"
UR2="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/user.reg"
for _i in 1 2 3 4 5 6 7 8 9 10; do
  GOT_H=$(/usr/bin/grep -a '"DisableHidraw"=dword:' "$SR" | head -1 | /usr/bin/grep -o '[01]$')
  GOT_S=$(/usr/bin/grep -a '"Enable SDL"=dword:'    "$SR" | head -1 | /usr/bin/grep -o '[01]$')
  GOT_X=$(/usr/bin/grep -ac '"xinput1_4"=""' "$UR2")
  GOT_P=$(/usr/bin/grep -a '"Sony XInput"=dword:' "$SR" | head -1 | /usr/bin/grep -o '[01]$')
  [ "$GOT_H" = "$PAD_HIDRAW" ] && [ "$GOT_S" = "$PAD_SDL" ] && [ "$GOT_X" = "$PAD_NOXI" ] && [ "$GOT_P" = "$PAD_SONYXI" ] && break
  sleep 1
done
if [ "$GOT_H" != "$PAD_HIDRAW" ] || [ "$GOT_S" != "$PAD_SDL" ] || [ "$GOT_X" != "$PAD_NOXI" ] || [ "$GOT_P" != "$PAD_SONYXI" ]; then
  echo "错误: 手柄配置期望 hidraw=$PAD_HIDRAW sdl=$PAD_SDL noxi=$PAD_NOXI sonyxi=$PAD_SONYXI,实际 $GOT_H / $GOT_S / $GOT_X / $GOT_P,已中止" >&2; exit 1
fi

# 切换高分辨率模式:直接改 user.reg(reg.exe 的写入会被 CrossOver 覆盖,不可靠)
if [ -n "${RETINA:-}" ]; then
  UR="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/user.reg"
  [ "$RETINA" = "y" ] && DPI=000000c0 || DPI=00000060
  kill_wineserver
  /usr/bin/sed -i '' "s/\"RetinaMode\"=\"[yn]\"/\"RetinaMode\"=\"$RETINA\"/" "$UR"
  /usr/bin/sed -i '' "s/\"LogPixels\"=dword:[0-9a-f]*/\"LogPixels\"=dword:$DPI/g" "$UR"
  ACT=$(/usr/bin/grep -o '"RetinaMode"="[yn]"' "$UR" | head -1 | /usr/bin/tr -d '"' | /usr/bin/sed 's/RetinaMode=//')
  if [ "$ACT" != "$RETINA" ]; then
    echo "错误: RetinaMode 期望 $RETINA 实际 $ACT,已中止" >&2; exit 1
  fi
fi
RM=$(grep -o '"RetinaMode"="[yn]"' "$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/user.reg" 2>/dev/null | head -1)
echo "后端=$GOT_B(已验证)  msync=$GOT_M  nvext=$GOT_N  手柄=$PADMODE  容器=$BOTTLE  参数=-force-d3d11 $ARGS  $RM"
# 日志:默认开。LOG=0 关闭。
LOGDIR="${LOGDIR:-$HOME/WindowsGames/Endfield工具/日志}"
if [ "${LOG:-1}" = "1" ]; then
  /bin/mkdir -p "$LOGDIR"
  LOGFILE="$LOGDIR/$(date +%Y%m%d-%H%M%S).log"
  /bin/ln -sf "$LOGFILE" "$LOGDIR/最近一次.log"
  echo "日志: $LOGFILE"
  "$CXR/bin/wine" --bottle "$BOTTLE" --wait-children \
    --cx-app "$GAME_EXE" -force-d3d11 $ARGS 2>&1 | /usr/bin/tee "$LOGFILE"
  RC=${PIPESTATUS[0]}

  # 记账:间歇性卡死约五成,单次结果无意义,必须靠累计样本判断
  TALLY="$LOGDIR/战绩.csv"
  [ -f "$TALLY" ] || echo "时间,后端,msync,nvext,retina,手柄,参数,结果,日志" > "$TALLY"
  echo
  printf '这次卡死了吗? [y=卡了 / n=正常 / 回车=跳过] '
  read -r -t 120 VERDICT || VERDICT=""
  case "${VERDICT:-}" in
    y|Y) R=卡死 ;;
    n|N) R=正常 ;;
    *)   R=未记录 ;;
  esac
  # 用 csv 模块写读,ARGS 里出现逗号也不会错位
  /usr/bin/python3 - "$TALLY" "$GOT_B" "$GOT_M" "$GOT_N" "$RETINA" "$PADMODE" "$ARGS" "$R" "$(basename "$LOGFILE")" <<'TALLYPY'
import sys, csv, os, datetime
path, b, m, nv, ret, pad, args, r, logf = sys.argv[1:10]
cfg = (b, m, nv, ret, pad, args)
with open(path, 'a', newline='', encoding='utf-8') as f:
    csv.writer(f).writerow([datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
                            b, m, nv, ret, pad, args, r, logf])
if r == '未记录':
    sys.exit(0)
rows = list(csv.reader(open(path, encoding='utf-8')))[1:]
same = [x for x in rows if len(x) >= 8 and tuple(x[1:7]) == cfg and x[7] != '未记录']
tot = len(same); bad = sum(1 for x in same if x[7] == '卡死')
print(f"已记录。此配置累计 {tot} 次,卡死 {bad} 次" + (f" ({bad*100//tot}%)" if tot else ""))
if tot < 5:
    print(f"样本还差 {5-tot} 次才有参考意义。")
# 顺带列出其它配置,方便横向对比
others = {}
for x in rows:
    if len(x) < 8 or x[7] == '未记录': continue
    k = tuple(x[1:7])
    if k == cfg: continue
    t, bd = others.get(k, (0, 0))
    others[k] = (t + 1, bd + (x[7] == '卡死'))
if others:
    print("其它配置:")
    for k, (t, bd) in others.items():
        print(f"  后端={k[0]} msync={k[1]} nvext={k[2]} retina={k[3]} 手柄={k[4]} args={k[5] or '(空)'}  ->  {t} 次卡死 {bd} 次")
TALLYPY
  echo "明细: $TALLY"
  exit $RC
fi
exec "$CXR/bin/wine" --bottle "$BOTTLE" --wait-children \
  --cx-app "$GAME_EXE" -force-d3d11 $ARGS

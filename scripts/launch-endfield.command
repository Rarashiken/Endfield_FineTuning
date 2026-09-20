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
# 战绩表要区分 CrossOver:26.3 和 preview 的卡死率不能混在一起统计。
CXVER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CXAPP/Contents/Info.plist" 2>/dev/null)
case "$CXVER" in
  20*) CXTAG="preview-${CXVER#2026}" ;;
  "")  CXTAG="未知" ;;
  *)   CXTAG="$CXVER" ;;
esac
export CX_ROOT="$CXR"
BOTTLE="${BOTTLE:-endfield263}"
# Windows path to the game exe (Y: maps to your home directory)
GAME_EXE="${GAME_EXE:-Y:\\WindowsGames\\Arknight Endfield\\Endfield.exe}"
BACKEND="${BACKEND:-dxmt}"
RETINA="${RETINA:-y}"
MSYNC="${MSYNC:-1}"
PADMODE="${PADMODE:-ps}"   # ps=DualSense 原生图标+按键(已验证) / xinput=回退到 Xbox 图标 / wgi、hid、hid-wgi=已实测失败
NVEXT="${NVEXT:-0}"   # DXMT 的 NVAPI 扩展;开了 DLSS 选项会出现但选中就黑屏
# 下面两个只在 BACKEND=d3dmetal 时有意义 —— DXMT 后端下 D3DMetal 根本没被加载,设了也是空转。
MTL4="${MTL4:-1}"        # D3DMetal 4.x 的 Metal 4 后端;生效时日志里有 "Enabled MTL4 backend"
METALFX="${METALFX:-1}"  # D3DMetal 的 MetalFX
# 性能浮层。需要两个变量配合:
#   MTL_HUD_ENABLED      —— Apple Metal 的 HUD 本体,FPS/GPU 时间/帧间隔/MetalFX 那些字段都来自它
#   D3DM_SHOW_HUD_STATS  —— D3DMetal 往那个 HUD 里追加 Dispatch/Draw/Clear Resource 计数
# 只开后者什么都不会显示(实测)。只在 BACKEND=d3dmetal 下有意义。
HUD="${HUD:-0}"

# 向游戏谎报显卡型号。终末地用 HGDLSSUtil::IsStreamlineDLSSGSupported 按 GPU 名字判断
# 能不能开帧生成,并排除 RTX 20/30 系(没有 Ada 的光流加速器)。看到不是 N 卡就直接
# 不显示那个选项 —— 这一层 D3DMetal 管不到,只能改它上报的 adapter 信息。
# DLSS 超分不需要这个(NGX 接口由 D3DMetal 顶着),只有帧生成的菜单项需要。
# GPUSPOOF=0 关闭;=1 用默认型号;也可以直接给型号,如 GPUSPOOF="RTX 4060"。
# 约束只有三条:NVIDIA、40 系(DLSS-G 需要 Ada 的光流加速器)、不在游戏的排除表里
# (RTX 20 / RTX 2050 / RTX 30 / RTX 3050 Laptop / RTX 3050 Ti Laptop)。
# 只报名字不报 device id:排除表是按字符串比的,多报一个没核对过的 id 反而可能帮倒忙。
GPUSPOOF="${GPUSPOOF:-0}"
case "$GPUSPOOF" in
  0|"")  SPOOF_VENDOR=""; SPOOF_DEVICE=""; SPOOF_DESC="" ;;
  1)     SPOOF_VENDOR="0x10DE"; SPOOF_DEVICE=""; SPOOF_DESC="NVIDIA GeForce RTX 4070" ;;
  *)     SPOOF_VENDOR="0x10DE"; SPOOF_DEVICE=""
         case "$GPUSPOOF" in
           NVIDIA*) SPOOF_DESC="$GPUSPOOF" ;;
           *)       SPOOF_DESC="NVIDIA GeForce $GPUSPOOF" ;;
         esac ;;
esac
if [ -n "$SPOOF_DESC" ]; then
  case "$SPOOF_DESC" in
    *"RTX 20"*|*"RTX 30"*)
      echo "警告: $SPOOF_DESC 在游戏的 DLSS-G 排除表里,帧生成选项不会出现" >&2 ;;
  esac
fi
# 渲染 API。游戏同时支持 Vulkan 和 DX11,Unity 默认选 Vulkan。
# Vulkan 走 MoltenVK,实测不可用(Retina 下过曝白屏、关 Retina 后进游戏黑屏、
# PSO 缓存从不落盘、且没有 DLSS)—— 见 docs/02-graphics-and-stability.md。
GFXAPI="${GFXAPI:-d3d11}"
case "$GFXAPI" in
  d3d11)  GFXFLAG="-force-d3d11"
          DEFARGS="-force-gfx-direct -force-d3d11-bitblt-mode" ;;
  vulkan) GFXFLAG="-force-vulkan"
          # bitblt-mode 是 D3D11 专用的,Vulkan 下没有意义
          DEFARGS="-force-gfx-direct" ;;
  *) echo "错误: GFXAPI 只能是 d3d11 或 vulkan(收到 $GFXAPI)" >&2; exit 1 ;;
esac
ARGS="${ARGS-$DEFARGS}"
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
if ! /usr/bin/python3 - "$CONF" "$BACKEND" "$MSYNC" "$NVEXT" "$MTL4" "$METALFX" "$HUD" \
     "$SPOOF_VENDOR" "$SPOOF_DEVICE" "$SPOOF_DESC" <<'PY'
import sys,re
p,b,m,nv,m4,mfx,hud,sv,sd,sdesc=sys.argv[1:11]
s=open(p,encoding='utf-8').read()

def set_env(s, key, value):
    """存在就替换,不存在就插进 [EnvironmentVariables] 段。
    早先只做替换,于是任何新建的容器都会因为缺键而在回读验证处中止。"""
    hit = re.subn(rf'"{key}" = "[^"]*"', f'"{key}" = "{value}"', s)
    if hit[1] == 1: return hit[0]
    if hit[1] > 1: sys.exit(f"cxbottle.conf 里 {key} 出现 {hit[1]} 次,不敢改")
    m = re.search(r'\[EnvironmentVariables\]', s)
    if not m: sys.exit("cxbottle.conf 里没有 [EnvironmentVariables] 段")
    return s[:m.end()] + f'\n"{key}" = "{value}"' + s[m.end():]

for k, v in (("CX_GRAPHICS_BACKEND", b), ("WINEMSYNC", m), ("DXMT_ENABLE_NVEXT", nv),
             ("D3DM_MTL4", m4), ("D3DM_ENABLE_METALFX", mfx),
             ("D3DM_SHOW_HUD_STATS", hud), ("MTL_HUD_ENABLED", hud)):
    s = set_env(s, k, v)

def drop_env(s, key):
    """整行删掉 —— 伪装关掉时必须真的消失,留一个空值会被当成有效的 adapter 信息。"""
    return re.sub(rf'^"{key}" = "[^"]*"\n', '', s, flags=re.M)

for k, v in (("D3DM_VENDOR_ID", sv), ("D3DM_DEVICE_ID", sd), ("D3DM_DEVICE_DESCRIPTION", sdesc)):
    s = set_env(s, k, v) if v else drop_env(s, k)
open(p,'w',encoding='utf-8').write(s)
PY
then
  echo "错误: 写入 cxbottle.conf 失败,已中止" >&2; exit 1
fi
# 回读验证 —— 写入声称成功不等于生效
GOT_B=$(/usr/bin/grep -o '"CX_GRAPHICS_BACKEND" = "[^"]*"' "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
GOT_M=$(/usr/bin/grep -o '"WINEMSYNC" = "[^"]*"'          "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
GOT_N=$(/usr/bin/grep -o '"DXMT_ENABLE_NVEXT" = "[^"]*"'  "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
GOT_M4=$(/usr/bin/grep -o '"D3DM_MTL4" = "[^"]*"'         "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
GOT_FX=$(/usr/bin/grep -o '"D3DM_ENABLE_METALFX" = "[^"]*"' "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
GOT_HUD=$(/usr/bin/grep -o '"D3DM_SHOW_HUD_STATS" = "[^"]*"' "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
GOT_MHUD=$(/usr/bin/grep -o '"MTL_HUD_ENABLED" = "[^"]*"' "$CONF" | head -1 | /usr/bin/sed 's/.*= "//;s/"//')
if [ "$GOT_B" != "$BACKEND" ] || [ "$GOT_M" != "$MSYNC" ] || [ "$GOT_N" != "$NVEXT" ] \
   || [ "$GOT_M4" != "$MTL4" ] || [ "$GOT_FX" != "$METALFX" ] || [ "$GOT_HUD" != "$HUD" ] || [ "$GOT_MHUD" != "$HUD" ]; then
  echo "错误: 期望 后端=$BACKEND msync=$MSYNC nvext=$NVEXT mtl4=$MTL4 metalfx=$METALFX," >&2
  echo "      实际 $GOT_B / $GOT_M / $GOT_N / $GOT_M4 / $GOT_FX,已中止" >&2; exit 1
fi
if [ "$BACKEND" = "dxmt" ] && [ "$MTL4$METALFX" != "00" ]; then
  echo "提示: 后端是 dxmt,D3DM_MTL4/D3DM_ENABLE_METALFX 不会生效(它们是 D3DMetal 的开关)"
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
echo "API=$GFXAPI  后端=$GOT_B(已验证)  msync=$GOT_M  nvext=$GOT_N  手柄=$PADMODE  容器=$BOTTLE  参数=$GFXFLAG $ARGS  $RM"
# 日志:默认开。LOG=0 关闭。
LOGDIR="${LOGDIR:-$HOME/WindowsGames/Endfield工具/日志}"
if [ "${LOG:-1}" = "1" ]; then
  /bin/mkdir -p "$LOGDIR"
  LOGFILE="$LOGDIR/$(date +%Y%m%d-%H%M%S).log"
  /bin/ln -sf "$LOGFILE" "$LOGDIR/最近一次.log"
  echo "日志: $LOGFILE"
  "$CXR/bin/wine" --bottle "$BOTTLE" --wait-children \
    --cx-app "$GAME_EXE" $GFXFLAG $ARGS 2>&1 | /usr/bin/tee "$LOGFILE"
  RC=${PIPESTATUS[0]}

  # 游戏实际选了哪个渲染 API —— 看它自己在 Player.log 里报告的,而不是看我们传了什么参数。
  PLOG="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/drive_c/users/crossover/AppData/LocalLow/Hypergryph/Endfield/Player.log"
  if [ -f "$PLOG" ]; then
    FORCED=$(/usr/bin/grep -o "Forcing GfxDevice: .*" "$PLOG" | tail -1)
    if [ -n "$FORCED" ]; then echo "游戏报告: $FORCED"
    else echo "游戏报告: 无 \"Forcing GfxDevice\" 行 —— 参数没被接受,落回了默认 API"; fi
    if /usr/bin/grep -q "vulkan_pso_cache" "$PLOG" 2>/dev/null; then echo "  PSO 缓存: vulkan_pso_cache.bin(实际走 Vulkan)"; fi
    if /usr/bin/grep -q "dx11_pso_cache" "$PLOG" 2>/dev/null; then echo "  PSO 缓存: dx11_pso_cache.bin(实际走 D3D11)"; fi
    MVKERR=$(/usr/bin/grep -o "\[mvk-error\].*" "$PLOG" | head -1)
    [ -n "$MVKERR" ] && echo "  MoltenVK 报错: $MVKERR"
  fi
  if [ "$GFXAPI" = "vulkan" ]; then
    echo "提示: Vulkan 走 MoltenVK,CX_GRAPHICS_BACKEND($GOT_B)是 D3D 翻译层的开关,此模式下不参与"
  fi

  # 图形后端到底生效了没 —— 不看变量,看日志里 D3DMetal / DXMT 自己说了什么。
  # 变量写进去了不等于跑起来用上了(msync 那次就是这么栽的)。
  if [ "$BACKEND" = "d3dmetal" ]; then
    if /usr/bin/grep -q "Enabled MTL4 backend" "$LOGFILE" 2>/dev/null; then
      echo "✓ Metal 4 后端已启用: $(/usr/bin/grep -o 'Enabled MTL4 backend.*' "$LOGFILE" | head -1)"
    else
      echo "✗ 日志里没有 \"Enabled MTL4 backend\" —— Metal 4 没生效(本游戏是 D3D11,MTL4 路径是 D3D12 专用)"
    fi
  fi

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
  /usr/bin/python3 - "$TALLY" "$CXTAG" "$GFXAPI" "$GOT_B" "$GOT_M" "$GOT_N" "$RETINA" "$PADMODE" "$ARGS" "$R" "$(basename "$LOGFILE")" <<'TALLYPY'
import sys, csv, os, datetime
path, cx, api, b, m, nv, ret, pad, args, r, logf = sys.argv[1:12]
cfg = (cx, api, b, m, nv, ret, pad, args)
with open(path, 'a', newline='', encoding='utf-8') as f:
    csv.writer(f).writerow([datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
                            cx, api, b, m, nv, ret, pad, args, r, logf])
if r == '未记录':
    sys.exit(0)
rows = list(csv.reader(open(path, encoding='utf-8')))[1:]
same = [x for x in rows if len(x) >= 10 and tuple(x[1:9]) == cfg and x[9] != '未记录']
tot = len(same); bad = sum(1 for x in same if x[9] == '卡死')
print(f"已记录。此配置累计 {tot} 次,卡死 {bad} 次" + (f" ({bad*100//tot}%)" if tot else ""))
if tot < 5:
    print(f"样本还差 {5-tot} 次才有参考意义。")
# 顺带列出其它配置,方便横向对比
others = {}
for x in rows:
    if len(x) < 10 or x[9] == '未记录': continue
    k = tuple(x[1:9])
    if k == cfg: continue
    t, bd = others.get(k, (0, 0))
    others[k] = (t + 1, bd + (x[9] == '卡死'))
if others:
    print("其它配置:")
    for k, (t, bd) in sorted(others.items()):
        print(f"  {k[0]} API={k[1]} 后端={k[2]} msync={k[3]} nvext={k[4]} retina={k[5]} 手柄={k[6]} args={k[7] or '(空)'}  ->  {t} 次卡死 {bd} 次")
TALLYPY
  echo "明细: $TALLY"
  exit $RC
fi
exec "$CXR/bin/wine" --bottle "$BOTTLE" --wait-children \
  --cx-app "$GAME_EXE" $GFXFLAG $ARGS

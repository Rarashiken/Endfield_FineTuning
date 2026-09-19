#!/bin/bash
# 让 Wine 对索尼手柄的行为与真 Windows 一致:不打 XInput 标记。
#
# 真 Windows 上 DualSense/DualShock4 不是 XInput 设备 —— XInput 只支持 XUSB(Xbox)手柄。
# 但 Wine 的 SDL 后端对任何手柄都设 is_gamepad=TRUE,于是 get_compatible_ids() 追加
# WINEBUS\WINE_COMP_XINPUT,winexinput.sys 据此生成 &IG_00 / &XI_00 子设备。
# 结果:输入库(如 Rewired)看到 IG_ 就走 XInput 分支,索尼手柄被当成 Xbox 360。
#
# 本补丁仅对索尼手柄跳过该标记,并用注册表开关控制,便于回退与 A/B:
#   HKLM\System\CurrentControlSet\Services\winebus  "Sony XInput" = dword:0  -> 关闭 XInput 标记
#   默认 1 = 保持 Wine 原行为
set -euo pipefail
SRC="${1:?用法: $0 <wine-src 目录>}"
F="$SRC/dlls/winebus.sys/main.c"
[ -f "$F" ] || { echo "找不到 $F"; exit 1; }

if grep -q "sony_xinput_enabled" "$F"; then echo "补丁已应用,跳过"; exit 0; fi

/usr/bin/python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()

# 1) 静态开关
a = 'static struct bus_options options = {.devices = LIST_INIT(options.devices)};'
assert a in s, "锚点1未找到"
s = s.replace(a, a + '\nstatic BOOL sony_xinput_enabled = TRUE;', 1)

# 2) 读取注册表开关
b = '    options.disable_sdl = !check_bus_option(L"Enable SDL", 1);'
assert b in s, "锚点2未找到"
s = s.replace(b, '    sony_xinput_enabled = check_bus_option(L"Sony XInput", 1);\n'
                 '    if (!sony_xinput_enabled) TRACE("Sony gamepads will not be marked XInput-capable\\n");\n' + b, 1)

# 3) get_compatible_ids:索尼手柄跳过 xinput_compat
#    上游与 CrossOver 的该函数形状不同(上游多了 USB 兼容 ID),
#    所以不整块替换,改为在函数体内把 is_gamepad 测试换成 helper。
helper = """/* On Windows, XInput only supports XUSB devices, i.e. Xbox controllers; a
 * DualShock 4 or DualSense is exposed as a plain HID device with Sony's own
 * vendor and product ID. winebus marks every SDL-backed controller as a
 * gamepad, so winexinput.sys creates the &IG_00 and &XI_00 children, and
 * applications skip the device in DirectInput and use XInput instead, which
 * costs them the PlayStation button glyphs.
 * Controlled by the "Sony XInput" registry value; 1 keeps the old behaviour. */
static BOOL want_xinput_compat(const struct device_extension *ext)
{
    if (!ext->desc.is_gamepad) return FALSE;
    if (sony_xinput_enabled) return TRUE;
    if (is_dualsense_gamepad(ext->desc.vid, ext->desc.pid)) return FALSE;
    if (is_dualshock4_gamepad(ext->desc.vid, ext->desc.pid)) return FALSE;
    return TRUE;
}

"""
sig = "static WCHAR *get_compatible_ids(DEVICE_OBJECT *device)"
assert sig in s, "锚点3未找到: get_compatible_ids"
s = s.replace(sig, helper + sig, 1)

# 只在该函数体内替换
i = s.index(sig, len(helper))
j = s.index("\n}\n", i)
body = s[i:j]
n = body.count("ext->desc.is_gamepad")
assert n >= 2, f"函数体内 is_gamepad 出现 {n} 次, 预期 >= 2"
s = s[:i] + body.replace("ext->desc.is_gamepad", "want_xinput_compat(ext)") + s[j:]
print(f"get_compatible_ids: 替换 {n} 处 is_gamepad 测试")

open(p, 'w', encoding='utf-8').write(s)
print("已修改 main.c")
PY

echo "--- 校验 ---"
printf "  静态开关:      %s\n" "$(grep -c 'static BOOL sony_xinput_enabled' "$F")"
printf "  注册表读取:    %s\n" "$(grep -c 'check_bus_option(L"Sony XInput"' "$F")"
printf "  want_xinput:   %s\n" "$(grep -c 'want_xinput' "$F")"

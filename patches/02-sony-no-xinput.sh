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
s = s.replace(a, a + '\nstatic BOOL sony_xinput_enabled = TRUE;  /* 真 Windows 上索尼手柄不是 XInput 设备 */', 1)

# 2) 读取注册表开关
b = '    options.disable_sdl = !check_bus_option(L"Enable SDL", 1);'
assert b in s, "锚点2未找到"
s = s.replace(b, '    sony_xinput_enabled = check_bus_option(L"Sony XInput", 1);\n'
                 '    if (!sony_xinput_enabled) TRACE("Sony gamepads will not be marked XInput-capable\\n");\n' + b, 1)

# 3) get_compatible_ids:索尼手柄跳过 xinput_compat
old = '''    struct device_extension *ext = (struct device_extension *)device->DeviceExtension;
    DWORD size = sizeof(hid_compat);
    WCHAR *dst;

    if (ext->desc.is_gamepad) size += sizeof(xinput_compat);

    if ((dst = ExAllocatePool(PagedPool, size + sizeof(WCHAR))))
    {
        if (ext->desc.is_gamepad) memcpy(dst, xinput_compat, sizeof(xinput_compat));'''
new = '''    struct device_extension *ext = (struct device_extension *)device->DeviceExtension;
    DWORD size = sizeof(hid_compat);
    BOOL want_xinput;
    WCHAR *dst;

    want_xinput = ext->desc.is_gamepad;
    if (want_xinput && !sony_xinput_enabled &&
        (is_dualsense_gamepad(ext->desc.vid, ext->desc.pid) ||
         is_dualshock4_gamepad(ext->desc.vid, ext->desc.pid)))
    {
        TRACE("not marking Sony gamepad %04x:%04x as XInput-capable\\n", ext->desc.vid, ext->desc.pid);
        want_xinput = FALSE;
    }

    if (want_xinput) size += sizeof(xinput_compat);

    if ((dst = ExAllocatePool(PagedPool, size + sizeof(WCHAR))))
    {
        if (want_xinput) memcpy(dst, xinput_compat, sizeof(xinput_compat));'''
assert old in s, "锚点3未找到"
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
print("已修改 main.c")
PY

echo "--- 校验 ---"
printf "  静态开关:      %s\n" "$(grep -c 'static BOOL sony_xinput_enabled' "$F")"
printf "  注册表读取:    %s\n" "$(grep -c 'check_bus_option(L"Sony XInput"' "$F")"
printf "  want_xinput:   %s\n" "$(grep -c 'want_xinput' "$F")"

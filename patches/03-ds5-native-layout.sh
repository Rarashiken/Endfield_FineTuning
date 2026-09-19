#!/bin/bash
# 让 SDL 后端对索尼手柄输出 DualSense 原生 HID 布局(轴序、按钮序、L2/R2 数字键)。
#
# 背景:SDL 路径用 hid_device_add_gamepad() 构造的是写死的 XUSB 风格描述符:
#   轴   X Y Rx Ry Z Rz   <- 右摇杆在 Rx/Ry,扳机在 Z/Rz
#   按钮 0=✕ 1=○ 2=□ 3=△ 4=L1 5=R1 6=Create 7=Options 8=L3 9=R3 10~13=十字键
# 而 DualSense 原生是:
#   轴   X Y Z Rz Rx Ry   <- 右摇杆在 Z/Rz,扳机在 Rx/Ry
#   按钮 0=□ 1=✕ 2=○ 3=△ 4=L1 5=R1 6=L2 7=R2 8=Create 9=Options 10=L3 11=R3 12=PS 13=触摸板
#        十字键只走帽子开关,不占按钮
# Rewired 按 VID/PID 认出 DualSense 后会用原生布局解析,于是面键全错位、L2/R2 无反应。
#
# 必须与"不打 XInput 标记"绑定:默认模式下 winexinput.sys 要靠标准布局翻译成 XInput,
# 改了布局会把默认模式一起弄坏。因此复用 "Sony XInput" 注册表开关:
#   "Sony XInput" = 0  -> 不打 XInput 标记 + 使用原生布局
set -euo pipefail
SRC="${1:?用法: $0 <wine-src 目录>}"
[ -f "$SRC/dlls/winebus.sys/bus_sdl.c" ] || { echo "找不到源码"; exit 1; }
if grep -q "sony_native_layout" "$SRC/dlls/winebus.sys/unixlib.h"; then echo "补丁已应用,跳过"; exit 0; fi

/usr/bin/python3 - "$SRC" <<'PY'
import sys, os
src = sys.argv[1]
def edit(rel, pairs):
    p = os.path.join(src, rel)
    s = open(p, encoding='utf-8').read()
    for old, new in pairs:
        assert old in s, f"{rel}: 锚点未找到 -> {old[:60]}"
        s = s.replace(old, new, 1)
    open(p, 'w', encoding='utf-8').write(s)

# --- 1) 共享结构加字段 ---
edit('dlls/winebus.sys/unixlib.h', [
    ("    BOOL map_controllers;\n    UINT mappings_count;",
     "    BOOL map_controllers;\n    BOOL sony_native_layout;\n    UINT mappings_count;"),
])

# --- 2) WoW64 thunk 同步(字段顺序必须一致)---
# 上游 Wine 没有这个 32 位 thunk,CrossOver 有。不存在就跳过。
_thunk = os.path.join(src, 'dlls/winebus.sys/unixlib.c')
if 'params32->map_controllers,' in open(_thunk, encoding='utf-8').read():
    edit('dlls/winebus.sys/unixlib.c', [
        ("        BOOL map_controllers;\n        UINT mappings_count;",
         "        BOOL map_controllers;\n        BOOL sony_native_layout;\n        UINT mappings_count;"),
        ("        params32->map_controllers,\n        params32->mappings_count,",
         "        params32->map_controllers,\n        params32->sony_native_layout,\n        params32->mappings_count,"),
    ])
    print("WoW64 thunk 已同步")
else:
    print("未发现 WoW64 thunk(上游 Wine),跳过")

# --- 3) PE 侧:与 Sony XInput 开关绑定 ---
edit('dlls/winebus.sys/main.c', [
    ('        options.map_controllers = check_bus_option(L"Map Controllers", 1);',
     '        options.map_controllers = check_bus_option(L"Map Controllers", 1);\n'
     '        options.sony_native_layout = !sony_xinput_enabled;'),
])

# --- 4) unix 侧:原生描述符 + 事件重映射 ---
edit('dlls/winebus.sys/bus_sdl.c', [
    # 4a. 判定helper + 原生描述符,插在 build_controller_report_descriptor 之前
    ("static NTSTATUS build_controller_report_descriptor(struct unix_device *iface)",
     """/* Whether this device should report the native DualSense HID layout. */
static BOOL use_sony_native_layout(struct sdl_device *impl)
{
    if (!options->sony_native_layout) return FALSE;
    if (!pSDL_JoystickGetVendor) return FALSE;
    return pSDL_JoystickGetVendor(impl->sdl_joystick) == 0x054c;
}

/* Native DualSense layout: axes X Y Z Rz Rx Ry, one hat switch, 14 buttons. */
static BOOL hid_device_add_ds5_gamepad(struct unix_device *iface)
{
    static const USAGE_AND_PAGE device_usage = {.UsagePage = HID_USAGE_PAGE_GENERIC, .Usage = HID_USAGE_GENERIC_GAMEPAD};
    static const USAGE lstick[]   = {HID_USAGE_GENERIC_X,  HID_USAGE_GENERIC_Y};
    static const USAGE rstick[]   = {HID_USAGE_GENERIC_Z,  HID_USAGE_GENERIC_RZ};
    static const USAGE triggers[] = {HID_USAGE_GENERIC_RX, HID_USAGE_GENERIC_RY};

    if (!hid_device_begin_input_report(iface, &device_usage)) return FALSE;
    if (!hid_device_add_axes(iface, 2, HID_USAGE_PAGE_GENERIC, lstick, FALSE, -32768, 32767)) return FALSE;
    if (!hid_device_add_axes(iface, 2, HID_USAGE_PAGE_GENERIC, rstick, FALSE, -32768, 32767)) return FALSE;
    if (!hid_device_add_axes(iface, 2, HID_USAGE_PAGE_GENERIC, triggers, FALSE, 0, 32767)) return FALSE;
    if (!hid_device_add_hatswitch(iface, 1)) return FALSE;
    if (!hid_device_add_buttons(iface, HID_USAGE_PAGE_BUTTON, 1, 14)) return FALSE;
    if (!hid_device_end_input_report(iface)) return FALSE;
    return TRUE;
}

/* SDL button -> native DualSense button index; the D-pad returns -1 and
 * drives the hat switch instead. */
static int ds5_button_from_sdl(int sdl_button)
{
    switch (sdl_button)
    {
    case SDL_CONTROLLER_BUTTON_X:             return 0;   /* Square */
    case SDL_CONTROLLER_BUTTON_A:             return 1;   /* Cross */
    case SDL_CONTROLLER_BUTTON_B:             return 2;   /* Circle */
    case SDL_CONTROLLER_BUTTON_Y:             return 3;   /* Triangle */
    case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  return 4;   /* L1 */
    case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return 5;   /* R1 */
    /* 6 = L2 and 7 = R2 are derived from the trigger axes. */
    case SDL_CONTROLLER_BUTTON_BACK:          return 8;   /* Create */
    case SDL_CONTROLLER_BUTTON_START:         return 9;   /* Options */
    case SDL_CONTROLLER_BUTTON_LEFTSTICK:     return 10;  /* L3 */
    case SDL_CONTROLLER_BUTTON_RIGHTSTICK:    return 11;  /* R3 */
    case SDL_CONTROLLER_BUTTON_GUIDE:         return 12;  /* PS */
#ifdef SDL_CONTROLLER_BUTTON_TOUCHPAD
    case SDL_CONTROLLER_BUTTON_TOUCHPAD:      return 13;  /* touchpad */
#endif
    default:                                  return -1;
    }
}

static NTSTATUS build_controller_report_descriptor(struct unix_device *iface)"""),

    # 4b. 描述符选择
    ("    if (!hid_device_add_gamepad(iface)) return STATUS_NO_MEMORY;",
     "    if (use_sony_native_layout(impl))\n"
     "    {\n"
     "        if (!hid_device_add_ds5_gamepad(iface)) return STATUS_NO_MEMORY;\n"
     "    }\n"
     "    else if (!hid_device_add_gamepad(iface)) return STATUS_NO_MEMORY;"),

    # 4c. 初始轴状态:原生布局不做 Y 轴取反
    ("        int value = pSDL_GameControllerGetAxis(impl->sdl_controller, i);\n"
     "        if (i == SDL_CONTROLLER_AXIS_LEFTY || i == SDL_CONTROLLER_AXIS_RIGHTY)\n"
     "            value = -value - 1; /* match XUSB / GIP protocol */",
     "        int value = pSDL_GameControllerGetAxis(impl->sdl_controller, i);\n"
     "        if (!use_sony_native_layout(impl) &&\n"
     "            (i == SDL_CONTROLLER_AXIS_LEFTY || i == SDL_CONTROLLER_AXIS_RIGHTY))\n"
     "            value = -value - 1; /* match XUSB / GIP protocol */"),
])
print("bus_sdl.c / unixlib.h / unixlib.c / main.c 已修改(第一批)")
PY

# --- 5) 事件重映射:按钮序 + 扳机数字键 + Y 轴取反 ---
/usr/bin/python3 - "$SRC" <<'PY2'
import sys, os
p = os.path.join(sys.argv[1], "dlls/winebus.sys/bus_sdl.c")
s = open(p, encoding='utf-8').read()

old_btn = """            SDL_ControllerButtonEvent *ie = &event->cbutton;
            int button;

            switch (ie->button)
            {
            case SDL_CONTROLLER_BUTTON_A: button = 0; break;"""
new_btn = """            SDL_ControllerButtonEvent *ie = &event->cbutton;
            int button;

            if (use_sony_native_layout(impl))
            {
                switch (ie->button)
                {
                case SDL_CONTROLLER_BUTTON_DPAD_UP:
                    hid_device_move_hatswitch(iface, 0, 0, ie->state ? -1 : +1); break;
                case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
                    hid_device_move_hatswitch(iface, 0, 0, ie->state ? +1 : -1); break;
                case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
                    hid_device_move_hatswitch(iface, 0, ie->state ? -1 : +1, 0); break;
                case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
                    hid_device_move_hatswitch(iface, 0, ie->state ? +1 : -1, 0); break;
                default:
                    button = ds5_button_from_sdl(ie->button);
                    if (button >= 0) hid_device_set_button(iface, button, ie->state);
                    break;
                }
                bus_event_queue_input_report(&event_queue, iface, state->report_buf, state->report_len);
                break;
            }

            switch (ie->button)
            {
            case SDL_CONTROLLER_BUTTON_A: button = 0; break;"""
assert old_btn in s, "button anchor not found"
s = s.replace(old_btn, new_btn, 1)

old_axis = """            SDL_ControllerAxisEvent *ie = &event->caxis;

            if (ie->axis == SDL_CONTROLLER_AXIS_LEFTY || ie->axis == SDL_CONTROLLER_AXIS_RIGHTY)
                ie->value = -ie->value - 1; /* match XUSB / GIP protocol */

            hid_device_set_abs_axis(iface, ie->axis, ie->value);"""
new_axis = """            SDL_ControllerAxisEvent *ie = &event->caxis;
            BOOL native = use_sony_native_layout(impl);

            if (!native && (ie->axis == SDL_CONTROLLER_AXIS_LEFTY || ie->axis == SDL_CONTROLLER_AXIS_RIGHTY))
                ie->value = -ie->value - 1; /* match XUSB / GIP protocol */

            hid_device_set_abs_axis(iface, ie->axis, ie->value);
            /* L2 / R2 are digital buttons 6 / 7 in the native layout */
            if (native && ie->axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT)
                hid_device_set_button(iface, 6, ie->value > 1000);
            if (native && ie->axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT)
                hid_device_set_button(iface, 7, ie->value > 1000);"""
assert old_axis in s, "axis anchor not found"
s = s.replace(old_axis, new_axis, 1)
open(p, 'w', encoding='utf-8').write(s)
print("event remapping applied")
PY2

echo "--- 校验 ---"
for f in unixlib.h unixlib.c main.c bus_sdl.c; do
  printf "  %-12s sony_native_layout 出现 %s 次\n" "$f" "$(grep -c sony_native_layout "$SRC/dlls/winebus.sys/$f" || true)"
done

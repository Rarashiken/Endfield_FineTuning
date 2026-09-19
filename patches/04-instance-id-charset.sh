#!/bin/bash
# Sanitise device instance IDs.
#
# get_instance_id() interpolates desc.serialnumber straight into the device
# instance ID. The IOHID backend takes that serial from kIOHIDSerialNumberKey,
# which for a Bluetooth device is the MAC address *with colons*:
#
#   HID\VID_054C&PID_0DF2\256&E8:47:3A:B4:1C:0B&3AB41C0B&0&0
#
# Windows does not allow < > : " / \ | ? * in a device instance ID, so this is
# malformed. Applications that parse or validate device paths reject such a
# device even though every input API reads it correctly, which makes it look as
# though the device is simply absent.
#
# Replace the disallowed characters with '_' when building the instance ID.
# desc.serialnumber itself is left untouched, so the HID serial number string
# reported to applications keeps its original form.
set -euo pipefail
SRC="${1:?usage: $0 <wine-src>}"
F="$SRC/dlls/winebus.sys/main.c"
[ -f "$F" ] || { echo "not found: $F"; exit 1; }
if grep -q "sanitise_instance_id" "$F"; then echo "already applied, skipping"; exit 0; fi

/usr/bin/python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()

old = """static WCHAR *get_instance_id(DEVICE_OBJECT *device)
{
    struct device_extension *ext = (struct device_extension *)device->DeviceExtension;
    DWORD len = wcslen(ext->desc.serialnumber) + 33;
    WCHAR *dst;

    if ((dst = ExAllocatePool(PagedPool, len * sizeof(WCHAR))))
    {
        swprintf(dst, len, L"%u&%s&%x&%u&%u", ext->desc.version, ext->desc.serialnumber,
                 ext->desc.uid, ext->index, ext->desc.is_gamepad);
    }

    return dst;
}"""

new = """/* A device instance ID may not contain < > : " / \\\\ | ? * or control characters.
 * Serial numbers reaching us from a backend can: the IOHID backend reports the
 * Bluetooth MAC address with colons, for example. Replace anything disallowed so
 * applications that validate device paths still see the device. */
static void sanitise_instance_id(WCHAR *str)
{
    static const WCHAR disallowed[] = L"<>:\\"/\\\\|?*";
    for (; *str; str++)
        if (*str < 0x20 || wcschr(disallowed, *str)) *str = '_';
}

static WCHAR *get_instance_id(DEVICE_OBJECT *device)
{
    struct device_extension *ext = (struct device_extension *)device->DeviceExtension;
    DWORD len = wcslen(ext->desc.serialnumber) + 33;
    WCHAR *dst;

    if ((dst = ExAllocatePool(PagedPool, len * sizeof(WCHAR))))
    {
        swprintf(dst, len, L"%u&%s&%x&%u&%u", ext->desc.version, ext->desc.serialnumber,
                 ext->desc.uid, ext->index, ext->desc.is_gamepad);
        sanitise_instance_id(dst);
    }

    return dst;
}"""

assert old in s, "anchor not found: get_instance_id"
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
print("main.c patched")
PY
echo "--- check ---"
printf "  sanitise_instance_id: %s\n" "$(grep -c sanitise_instance_id "$F")"

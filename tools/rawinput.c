/* Raw Input probe: does Wine deliver WM_INPUT for the gamepad in this bottle?
 *
 * Enumerates every Raw Input device, prints the HID ones with their VID/PID and
 * device path (which shows whether winexinput added an &IG_ suffix), then
 * registers for gamepad/joystick input and counts the WM_INPUT reports that
 * actually arrive, per device, for 30 seconds. */
#include <windows.h>
#include <stdio.h>

static FILE *out;

#define MAXDEV 32
static HANDLE  dev_h[MAXDEV];
static unsigned dev_n;
static unsigned dev_reports[MAXDEV];
static unsigned total_reports, unmatched_reports;
static char     dev_name[MAXDEV][512];

static int slot_for(HANDLE h)
{
    unsigned i;
    for (i = 0; i < dev_n; i++) if (dev_h[i] == h) return i;
    return -1;
}

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_INPUT)
    {
        BYTE buf[1024];
        UINT size = sizeof(buf);
        if (GetRawInputData((HRAWINPUT)lp, RID_INPUT, buf, &size, sizeof(RAWINPUTHEADER)) != (UINT)-1)
        {
            RAWINPUT *ri = (RAWINPUT *)buf;
            int s = slot_for(ri->header.hDevice);
            total_reports++;
            if (s >= 0) dev_reports[s]++; else unmatched_reports++;
        }
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

int main(void)
{
    RAWINPUTDEVICELIST list[64];
    UINT count = 64, i;
    WNDCLASSA wc = {0};
    HWND hwnd;
    RAWINPUTDEVICE rid[2];
    DWORD start;
    MSG msg;

    out = fopen("Z:\\tmp\\rawinput.txt", "w");
    if (!out) return 1;
    setvbuf(out, NULL, _IONBF, 0);

    if (GetRawInputDeviceList(list, &count, sizeof(list[0])) == (UINT)-1)
    { fprintf(out, "GetRawInputDeviceList failed: %lu\n", GetLastError()); return 1; }

    fprintf(out, "=== Raw Input devices (%u total) ===\n", count);
    for (i = 0; i < count; i++)
    {
        char name[512]; UINT nlen = sizeof(name);
        RID_DEVICE_INFO info; UINT ilen = sizeof(info);
        if (list[i].dwType != RIM_TYPEHID) continue;
        info.cbSize = sizeof(info);
        if (GetRawInputDeviceInfoA(list[i].hDevice, RIDI_DEVICENAME, name, &nlen) == (UINT)-1) continue;
        if (GetRawInputDeviceInfoA(list[i].hDevice, RIDI_DEVICEINFO, &info, &ilen) == (UINT)-1) continue;

        fprintf(out, "\nHID device\n");
        fprintf(out, "  VID/PID   : %04lX:%04lX\n", info.hid.dwVendorId, info.hid.dwProductId);
        fprintf(out, "  usage     : page %04X usage %04X\n", info.hid.usUsagePage, info.hid.usUsage);
        fprintf(out, "  path      : %s\n", name);

        if (info.hid.usUsagePage == 0x01 &&
            (info.hid.usUsage == 0x04 || info.hid.usUsage == 0x05) && dev_n < MAXDEV)
        {
            dev_h[dev_n] = list[i].hDevice;
            snprintf(dev_name[dev_n], sizeof(dev_name[0]), "%04lX:%04lX %s",
                     info.hid.dwVendorId, info.hid.dwProductId, name);
            dev_n++;
            fprintf(out, "  -> watching this one\n");
        }
    }

    if (!dev_n) { fprintf(out, "\nNo gamepad/joystick found.\n"); fclose(out); return 1; }

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "RawInputProbe";
    RegisterClassA(&wc);
    hwnd = CreateWindowExA(0, "RawInputProbe", "Raw Input probe - keep me focused",
                           WS_OVERLAPPEDWINDOW, 100, 100, 420, 140,
                           NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { fprintf(out, "CreateWindow failed: %lu\n", GetLastError()); fclose(out); return 1; }
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    SetForegroundWindow(hwnd);

    /* RIDEV_INPUTSINK so reports arrive without foreground focus */
    rid[0].usUsagePage = 0x01; rid[0].usUsage = 0x04;
    rid[0].dwFlags = RIDEV_INPUTSINK; rid[0].hwndTarget = hwnd;
    rid[1].usUsagePage = 0x01; rid[1].usUsage = 0x05;
    rid[1].dwFlags = RIDEV_INPUTSINK; rid[1].hwndTarget = hwnd;
    if (!RegisterRawInputDevices(rid, 2, sizeof(rid[0])))
    { fprintf(out, "\nRegisterRawInputDevices failed: %lu\n", GetLastError()); fclose(out); return 1; }

    fprintf(out, "\n=== Registered. Move the sticks and press buttons for 30 s ===\n");
    start = GetTickCount();
    while (GetTickCount() - start < 30000)
    {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE))
        { TranslateMessage(&msg); DispatchMessageA(&msg); }
        Sleep(10);
    }

    fprintf(out, "\n=== WM_INPUT reports received ===\n");
    fprintf(out, "  total %u, of which %u from devices not in the watch list\n",
            total_reports, unmatched_reports);
    for (i = 0; i < dev_n; i++)
        fprintf(out, "  %6u  %s\n", dev_reports[i], dev_name[i]);
    fclose(out);
    return 0;
}

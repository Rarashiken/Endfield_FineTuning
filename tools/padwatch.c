#define INITGUID
#include <windows.h>
#include <dinput.h>
#include <stdio.h>

static IDirectInputDevice8A *dev;
static FILE *out;

static BOOL CALLBACK pick(const DIDEVICEINSTANCEA *inst, void *ctx)
{
    IDirectInput8A *di = ctx;
    if (FAILED(IDirectInput8_CreateDevice(di, &inst->guidInstance, &dev, NULL))) return DIENUM_CONTINUE;
    fprintf(out, "设备: %s  VID/PID=%04X:%04X\n\n", inst->tszProductName,
            (unsigned)(inst->guidProduct.Data1 & 0xffff),
            (unsigned)((inst->guidProduct.Data1 >> 16) & 0xffff));
    return DIENUM_STOP;
}

int main(void)
{
    IDirectInput8A *di = NULL;
    DIJOYSTATE2 st, prev;
    int i, secs = 0;

    out = fopen("Z:\\tmp\\padwatch.txt", "w");
    if (!out) return 1;
    setvbuf(out, NULL, _IONBF, 0);

    if (FAILED(DirectInput8Create(GetModuleHandleA(NULL), DIRECTINPUT_VERSION,
                                  &IID_IDirectInput8A, (void **)&di, NULL)))
    { fprintf(out, "DirectInput8Create 失败\n"); return 1; }

    IDirectInput8_EnumDevices(di, DI8DEVCLASS_GAMECTRL, pick, di, DIEDFL_ATTACHEDONLY);
    if (!dev) { fprintf(out, "没有找到手柄\n"); fclose(out); return 1; }

    IDirectInputDevice8_SetDataFormat(dev, &c_dfDIJoystick2);
    IDirectInputDevice8_Acquire(dev);
    memset(&prev, 0, sizeof(prev));

    fprintf(out, "开始监视 40 秒,请按提示依次按键...\n\n");
    for (i = 0; i < 4000; i++)
    {
        int j;
        if (i % 100 == 0) { fprintf(out, "[%2d 秒]\n", secs); secs++; }
        IDirectInputDevice8_Poll(dev);
        if (FAILED(IDirectInputDevice8_GetDeviceState(dev, sizeof(st), &st)))
        { IDirectInputDevice8_Acquire(dev); Sleep(10); continue; }

        for (j = 0; j < 32; j++)
            if ((st.rgbButtons[j] & 0x80) && !(prev.rgbButtons[j] & 0x80))
                fprintf(out, "    按钮 #%d 按下\n", j);
        if (st.rgdwPOV[0] != prev.rgdwPOV[0] && st.rgdwPOV[0] != 0xFFFFFFFF)
            fprintf(out, "    POV = %lu\n", (unsigned long)st.rgdwPOV[0]);
        prev = st;
        Sleep(10);
    }
    fprintf(out, "\n监视结束\n");
    IDirectInputDevice8_Unacquire(dev);
    fclose(out);
    return 0;
}

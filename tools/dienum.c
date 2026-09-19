#define INITGUID
#include <windows.h>
#include <dinput.h>
#include <stdio.h>

static FILE *out;

static BOOL CALLBACK obj_cb(const DIDEVICEOBJECTINSTANCEA *o, void *ctx)
{
    int *c = ctx;            /* c[0]=axes c[1]=buttons c[2]=povs */
    if (o->dwType & DIDFT_AXIS)   c[0]++;
    if (o->dwType & DIDFT_BUTTON) c[1]++;
    if (o->dwType & DIDFT_POV)    c[2]++;
    return DIENUM_CONTINUE;
}

static BOOL CALLBACK dev_cb(const DIDEVICEINSTANCEA *inst, void *ctx)
{
    IDirectInput8A *di = ctx;
    IDirectInputDevice8A *dev = NULL;
    int c[3] = {0,0,0};

    fprintf(out, "设备: %s\n", inst->tszInstanceName);
    fprintf(out, "  产品名  : %s\n", inst->tszProductName);
    fprintf(out, "  VID/PID : %04X:%04X\n",
            (unsigned)(inst->guidProduct.Data1 & 0xffff),
            (unsigned)((inst->guidProduct.Data1 >> 16) & 0xffff));
    fprintf(out, "  类型    : 0x%08lx\n", (unsigned long)inst->dwDevType);

    if (SUCCEEDED(IDirectInput8_CreateDevice(di, &inst->guidInstance, &dev, NULL)))
    {
        IDirectInputDevice8_EnumObjects(dev, obj_cb, c, DIDFT_ALL);
        fprintf(out, "  轴=%d 按钮=%d POV=%d\n", c[0], c[1], c[2]);
        IDirectInputDevice8_Release(dev);
    }
    else fprintf(out, "  (CreateDevice 失败)\n");
    fprintf(out, "\n");
    return DIENUM_CONTINUE;
}

int main(void)
{
    IDirectInput8A *di = NULL;
    out = fopen("Z:\\tmp\\dienum.txt", "w");
    if (!out) return 1;
    if (FAILED(DirectInput8Create(GetModuleHandleA(NULL), DIRECTINPUT_VERSION,
                                  &IID_IDirectInput8A, (void **)&di, NULL)))
    { fprintf(out, "DirectInput8Create 失败\n"); fclose(out); return 1; }

    fprintf(out, "=== DI8DEVCLASS_GAMECTRL ===\n");
    IDirectInput8_EnumDevices(di, DI8DEVCLASS_GAMECTRL, dev_cb, di, DIEDFL_ATTACHEDONLY);
    fprintf(out, "=== DI8DEVCLASS_ALL (仅手柄类) ===\n");
    IDirectInput8_EnumDevices(di, DI8DEVCLASS_ALL, dev_cb, di, DIEDFL_ATTACHEDONLY);
    IDirectInput8_Release(di);
    fclose(out);
    return 0;
}

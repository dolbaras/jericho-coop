/*
 * Window placement and render adapter selection for test instances (env driven).
 *
 *   JERICHO_WINPOS=x,y      create the game window at x,y (screen coordinates) and keep it
 *                           there, so a test instance opens directly on a chosen monitor.
 *   JERICHO_WINSIZE=w,h     make the game window's client area w x h and keep it so (the
 *                           engine sizes its window on its own, smaller than the
 *                           -WindowedWidth/-WindowedHeight back buffer on some machines).
 *   JERICHO_ADAPTER=window  create the Direct3D 9 device on the adapter that drives the
 *                           monitor holding the window (the game always asks for adapter 0).
 *   JERICHO_ADAPTER=<n>     use adapter n.
 *   JERICHO_PADS=a,b,..     split screen: the game's pad 0 is physical XInput pad a, its pad 1
 *                           is pad b...; the others read as unplugged. "none": no pads.
 *   JERICHO_KBM=0           split screen, second window: keyboard and mouse never reach this
 *                           game (they belong to the first window).
 *   JERICHO_BACKGROUND=1    keep running when the window loses focus: the game pauses on
 *                           deactivation, which would freeze a co-op session (host alt-tabs)
 *                           and test instances that are not in front. The mod's Lua also
 *                           turns it on for the length of a session (Net.CoopBackground).
 *                           The hooks are always installed and pass through while it is off.
 *
 * Hooks go through the exe's import table, so the game code itself is not patched.
 */
#include <windows.h>
#include <d3d9.h>
#include <stdlib.h>
#include <string.h>

#include "coop_net.h"
#include "display_hooks.h"
#include "split.h"
#include "capture.h"

static int win_x, win_y, have_winpos, run_in_background;
static int kbm_off;               /* JERICHO_KBM=0 */
static int pad_map[4] = {0, 1, 2, 3};
static int win_w, win_h, have_winsize;
static DWORD win_style, win_exstyle;

/* Outer window size for the wanted client size. */
static void outer_size(DWORD style, DWORD ex, int *w, int *h)
{
    RECT r = {0, 0, win_w, win_h};
    AdjustWindowRectEx(&r, style, FALSE, ex);
    *w = r.right - r.left;
    *h = r.bottom - r.top;
}
static char adapter_mode[16];
static HWND game_window;
static WNDPROC game_wndproc;

/* ---- import table patching ---- */
static void **find_iat_slot(const char *dll, const char *func)
{
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!dir.VirtualAddress)
        return NULL;
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); d->Name; d++) {
        if (_stricmp((const char *)(base + d->Name), dll) != 0)
            continue;
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
        void **slots = (void **)(base + d->FirstThunk);
        for (int i = 0; names[i].u1.AddressOfData; i++) {
            if (IMAGE_SNAP_BY_ORDINAL(names[i].u1.Ordinal))
                continue;
            IMAGE_IMPORT_BY_NAME *ibn = (IMAGE_IMPORT_BY_NAME *)(base + names[i].u1.AddressOfData);
            if (strcmp((const char *)ibn->Name, func) == 0)
                return &slots[i];
        }
    }
    return NULL;
}

/* An import by ordinal (XINPUT1_3.dll exports XInputGetState as #2, XInputSetState as #3). */
static void **find_iat_slot_ord(const char *dll, WORD ordinal)
{
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!dir.VirtualAddress)
        return NULL;
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); d->Name; d++) {
        if (_stricmp((const char *)(base + d->Name), dll) != 0)
            continue;
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
        void **slots = (void **)(base + d->FirstThunk);
        for (int i = 0; names[i].u1.AddressOfData; i++)
            if (IMAGE_SNAP_BY_ORDINAL(names[i].u1.Ordinal) && IMAGE_ORDINAL(names[i].u1.Ordinal) == ordinal)
                return &slots[i];
    }
    return NULL;
}

static void *patch_slot(void **slot, void *hook)
{
    DWORD old;
    if (!slot || !VirtualProtect(slot, sizeof *slot, PAGE_READWRITE, &old))
        return NULL;
    void *orig = *slot;
    *slot = hook;
    VirtualProtect(slot, sizeof *slot, old, &old);
    return orig;
}

static void *patch_iat(const char *dll, const char *func, void *hook)
{
    void **slot = find_iat_slot(dll, func);
    DWORD old;
    if (!slot || !VirtualProtect(slot, sizeof *slot, PAGE_READWRITE, &old))
        return NULL;
    void *orig = *slot;
    *slot = hook;
    VirtualProtect(slot, sizeof *slot, old, &old);
    return orig;
}

static void *patch_vtable(void *obj, int index, void *hook)
{
    void **vt = *(void ***)obj;
    DWORD old;
    if (vt[index] == hook || !VirtualProtect(&vt[index], sizeof(void *), PAGE_READWRITE, &old))
        return NULL;
    void *orig = vt[index];
    vt[index] = hook;
    VirtualProtect(&vt[index], sizeof(void *), old, &old);
    return orig;
}

/* ---- window placement ---- */
typedef HWND (WINAPI *CreateWindowExA_t)(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
typedef BOOL (WINAPI *SetWindowPos_t)(HWND, HWND, int, int, int, int, UINT);
typedef BOOL (WINAPI *MoveWindow_t)(HWND, int, int, int, int, BOOL);
static CreateWindowExA_t real_CreateWindowExA;
static SetWindowPos_t real_SetWindowPos;
static MoveWindow_t real_MoveWindow;

/* Background mode must not let a game the user is not looking at read their keyboard,
 * move their mouse or grab focus: the game polls GetAsyncKeyState (global key state) and
 * warps the cursor with SetCursorPos for mouse look. All of that is blocked unless the
 * game window is really in front. */
typedef HWND (WINAPI *GetWindow_t)(void);
typedef SHORT (WINAPI *GetAsyncKeyState_t)(int);
typedef BOOL (WINAPI *SetCursorPos_t)(int, int);
typedef BOOL (WINAPI *HwndBool_t)(HWND);
typedef HWND (WINAPI *SetFocus_t)(HWND);
static GetWindow_t real_GetForegroundWindow, real_GetActiveWindow;
static GetAsyncKeyState_t real_GetAsyncKeyState;
static SetCursorPos_t real_SetCursorPos;
static HwndBool_t real_SetForegroundWindow, real_BringWindowToTop;
static SetFocus_t real_SetFocus;
static int test_mode;   /* JERICHO_BACKGROUND set: test instances never activate their window */
typedef BOOL(WINAPI *ShowWindow_t)(HWND, int);
static ShowWindow_t real_ShowWindow;

int display_hooks_key_down(int vk)
{
    /* Our own imports are not hooked: these are the real functions. */
    if (kbm_off || !game_window || GetForegroundWindow() != game_window)
        return 0;
    return (GetAsyncKeyState(vk) & 0x8000) ? 1 : 0;
}

static int really_in_front(void)
{
    if (!run_in_background)
        return 1;
    return game_window && real_GetForegroundWindow() == game_window;
}

/* Keyboard and mouse reach the game: its window is in front and they are not switched off. */
static int kbm_in(void)
{
    return !kbm_off && really_in_front();
}

static HWND WINAPI bg_GetForegroundWindow(void)
{
    return run_in_background && game_window ? game_window : real_GetForegroundWindow();
}

static HWND WINAPI bg_GetActiveWindow(void)
{
    return run_in_background && game_window ? game_window : real_GetActiveWindow();
}

static SHORT WINAPI bg_GetAsyncKeyState(int key)
{
    return kbm_in() ? real_GetAsyncKeyState(key) : 0;
}

static BOOL WINAPI bg_SetCursorPos(int x, int y)
{
    return kbm_in() ? real_SetCursorPos(x, y) : TRUE;
}

static BOOL WINAPI bg_SetForegroundWindow(HWND hw)
{
    return really_in_front() ? real_SetForegroundWindow(hw) : TRUE;
}

static BOOL WINAPI bg_BringWindowToTop(HWND hw)
{
    return really_in_front() ? real_BringWindowToTop(hw) : TRUE;
}

static HWND WINAPI bg_SetFocus(HWND hw)
{
    return really_in_front() ? real_SetFocus(hw) : hw;
}

/* DirectInput: a game left in the background must see no keyboard or mouse input, or it
 * would react to what the user types in other programs. Wrap every device the game
 * creates through our dinput8 proxy. IDirectInput8A::CreateDevice is vtable slot 3;
 * IDirectInputDevice8A::GetDeviceState is slot 9 and GetDeviceData slot 10. */
typedef HRESULT (WINAPI *GetDeviceState_t)(void *, DWORD, void *);
typedef HRESULT (WINAPI *GetDeviceData_t)(void *, DWORD, void *, DWORD *, DWORD);
typedef HRESULT (WINAPI *DICreateDevice_t)(void *, const GUID *, void **, void *);
static GetDeviceState_t real_GetDeviceState;
static GetDeviceData_t real_GetDeviceData;
static DICreateDevice_t real_DICreateDevice;

static HRESULT WINAPI bg_GetDeviceState(void *dev, DWORD size, void *data)
{
    HRESULT hr = real_GetDeviceState(dev, size, data);
    if (!kbm_in() && data)
        memset(data, 0, size);
    return hr;
}

static HRESULT WINAPI bg_GetDeviceData(void *dev, DWORD objsize, void *data, DWORD *count, DWORD flags)
{
    HRESULT hr = real_GetDeviceData(dev, objsize, data, count, flags);
    if (!kbm_in() && count)
        *count = 0;   /* drop buffered events */
    return hr;
}

static HRESULT WINAPI bg_DICreateDevice(void *di, const GUID *guid, void **out, void *outer)
{
    HRESULT hr = real_DICreateDevice(di, guid, out, outer);
    if (SUCCEEDED(hr) && out && *out) {
        void *o9 = patch_vtable(*out, 9, (void *)bg_GetDeviceState);
        void *o10 = patch_vtable(*out, 10, (void *)bg_GetDeviceData);
        if (o9)
            real_GetDeviceState = (GetDeviceState_t)o9;
        if (o10)
            real_GetDeviceData = (GetDeviceData_t)o10;
    }
    return hr;
}

/* Called by the dinput8 proxy for every IDirectInput8 the game creates. */
void display_hooks_wrap_dinput(void *dinput)
{
    if (!dinput)
        return;
    void *orig = patch_vtable(dinput, 3, (void *)bg_DICreateDevice);
    if (orig)
        real_DICreateDevice = (DICreateDevice_t)orig;
}

/* The game's window must never become active by itself: the owner may be playing another
 * game full screen on the main monitor, which minimizes when it loses focus. */
static BOOL WINAPI bg_ShowWindow(HWND hw, int cmd)
{
    if (test_mode && hw == game_window) {
        if (cmd == SW_SHOW || cmd == SW_SHOWNORMAL || cmd == SW_RESTORE || cmd == SW_SHOWDEFAULT)
            cmd = SW_SHOWNOACTIVATE;
        else if (cmd == SW_SHOWMAXIMIZED)
            cmd = SW_SHOWNA;
    }
    return real_ShowWindow(hw, cmd);
}

static void install_background_hooks(void)
{
#define BG_HOOK(name, type)                                                              \
    do {                                                                                 \
        real_##name = (type)patch_iat("USER32.dll", #name, (void *)bg_##name);           \
        if (!real_##name)                                                                \
            real_##name = (type)name;                                                    \
    } while (0)
    BG_HOOK(GetForegroundWindow, GetWindow_t);
    BG_HOOK(GetActiveWindow, GetWindow_t);
    BG_HOOK(GetAsyncKeyState, GetAsyncKeyState_t);
    BG_HOOK(SetCursorPos, SetCursorPos_t);
    BG_HOOK(SetForegroundWindow, HwndBool_t);
    BG_HOOK(BringWindowToTop, HwndBool_t);
    BG_HOOK(SetFocus, SetFocus_t);
    BG_HOOK(ShowWindow, ShowWindow_t);
#undef BG_HOOK
}

/* Hide deactivation from the game so it keeps simulating and rendering in the background. */
static LRESULT CALLBACK background_wndproc(HWND hw, UINT msg, WPARAM wp, LPARAM lp)
{
    if (!run_in_background)
        return CallWindowProcA(game_wndproc, hw, msg, wp, lp);
    switch (msg) {
    case WM_ACTIVATEAPP:
        if (!wp)
            return 0;
        break;
    case WM_ACTIVATE:
        if (LOWORD(wp) == WA_INACTIVE)
            return 0;
        break;
    case WM_KILLFOCUS:
        return 0;
    case WM_NCACTIVATE:
        if (!wp)
            return DefWindowProcA(hw, msg, wp, lp);
        break;
    }
    return CallWindowProcA(game_wndproc, hw, msg, wp, lp);
}

static int show_after_create;

static HWND WINAPI hook_CreateWindowExA(DWORD ex, LPCSTR cls, LPCSTR title, DWORD style, int x, int y,
                                        int w, int h, HWND parent, HMENU menu, HINSTANCE inst, LPVOID param)
{
    int game = cls && !IS_INTRESOURCE(cls) && strcmp(cls, "MercuryGameClass") == 0;
    if (game && have_winpos) {
        coop_log("window %d,%d -> %d,%d", x, y, win_x, win_y);
        x = win_x;
        y = win_y;
    }
    if (game && have_winsize) {
        int ow, oh;
        outer_size(style, ex, &ow, &oh);
        coop_log("window size %dx%d -> %dx%d (client %dx%d)", w, h, ow, oh, win_w, win_h);
        w = ow;
        h = oh;
        win_style = style;
        win_exstyle = ex;
    }
    if (game && test_mode) {
        ex |= WS_EX_NOACTIVATE;
        if (style & WS_VISIBLE) {
            style &= ~WS_VISIBLE;
            show_after_create = 1;
        }
    }
    HWND hw = real_CreateWindowExA(ex, cls, title, style, x, y, w, h, parent, menu, inst, param);
    if (game && hw && show_after_create)
        real_ShowWindow ? real_ShowWindow(hw, SW_SHOWNOACTIVATE) : ShowWindow(hw, SW_SHOWNOACTIVATE);
    if (game && hw) {
        game_window = hw;
        if (!game_wndproc)
            game_wndproc = (WNDPROC)SetWindowLongPtrA(hw, GWLP_WNDPROC, (LONG_PTR)background_wndproc);
    }
    return hw;
}

static BOOL WINAPI hook_SetWindowPos(HWND hw, HWND after, int x, int y, int w, int h, UINT flags)
{
    if (hw == game_window && have_winpos && !(flags & SWP_NOMOVE)) {
        x = win_x;
        y = win_y;
    }
    if (hw == game_window && have_winsize && !(flags & SWP_NOSIZE))
        outer_size((DWORD)GetWindowLongA(hw, GWL_STYLE), (DWORD)GetWindowLongA(hw, GWL_EXSTYLE), &w, &h);
    if (hw == game_window && test_mode)
        flags |= SWP_NOACTIVATE;
    return real_SetWindowPos(hw, after, x, y, w, h, flags);
}

static BOOL WINAPI hook_MoveWindow(HWND hw, int x, int y, int w, int h, BOOL repaint)
{
    if (hw == game_window && have_winpos) {
        x = win_x;
        y = win_y;
    }
    if (hw == game_window && have_winsize)
        outer_size((DWORD)GetWindowLongA(hw, GWL_STYLE), (DWORD)GetWindowLongA(hw, GWL_EXSTYLE), &w, &h);
    return real_MoveWindow(hw, x, y, w, h, repaint);
}

/* ---- Direct3D 9 adapter ---- */
typedef IDirect3D9 *(WINAPI *Direct3DCreate9_t)(UINT);
typedef HRESULT (WINAPI *CreateDevice_t)(IDirect3D9 *, UINT, D3DDEVTYPE, HWND, DWORD,
                                         D3DPRESENT_PARAMETERS *, IDirect3DDevice9 **);
static Direct3DCreate9_t real_Direct3DCreate9;
static CreateDevice_t real_CreateDevice;

#define VT_GETADAPTERCOUNT 4
#define VT_GETADAPTERIDENTIFIER 5
#define VT_GETADAPTERMONITOR 15
#define VT_CREATEDEVICE 16

static UINT pick_adapter(IDirect3D9 *d3d, HWND focus, UINT asked)
{
    void **vt = *(void ***)d3d;
    UINT (WINAPI *count)(IDirect3D9 *) = (UINT (WINAPI *)(IDirect3D9 *))vt[VT_GETADAPTERCOUNT];
    HMONITOR (WINAPI *monitor)(IDirect3D9 *, UINT) = (HMONITOR (WINAPI *)(IDirect3D9 *, UINT))vt[VT_GETADAPTERMONITOR];
    UINT n = count(d3d);
    if (adapter_mode[0] >= '0' && adapter_mode[0] <= '9') {
        UINT want = (UINT)atoi(adapter_mode);
        return want < n ? want : asked;
    }
    if (strcmp(adapter_mode, "window") == 0) {
        HMONITOR mon = have_winpos ? MonitorFromPoint((POINT){win_x + 50, win_y + 50}, MONITOR_DEFAULTTONEAREST)
                                   : MonitorFromWindow(focus, MONITOR_DEFAULTTONEAREST);
        for (UINT i = 0; i < n; i++)
            if (monitor(d3d, i) == mon)
                return i;
        /* Monitor not matched (display settings changing, monitor asleep): test runs must
         * stay off the owner's main GPU, so take the Intel iGPU if there is one. */
        HRESULT (WINAPI *ident)(IDirect3D9 *, UINT, DWORD, D3DADAPTER_IDENTIFIER9 *) =
            (HRESULT (WINAPI *)(IDirect3D9 *, UINT, DWORD, D3DADAPTER_IDENTIFIER9 *))vt[VT_GETADAPTERIDENTIFIER];
        for (UINT i = 0; i < n; i++) {
            D3DADAPTER_IDENTIFIER9 id;
            memset(&id, 0, sizeof id);
            if (SUCCEEDED(ident(d3d, i, 0, &id)) && id.VendorId == 0x8086) {
                coop_log("adapter: window monitor not found, using Intel adapter %u", i);
                return i;
            }
        }
        coop_log("adapter: window monitor not found and no Intel adapter");
    }
    return asked;
}

static HRESULT WINAPI hook_CreateDevice(IDirect3D9 *d3d, UINT adapter, D3DDEVTYPE type, HWND focus, DWORD flags,
                                        D3DPRESENT_PARAMETERS *pp, IDirect3DDevice9 **out)
{
    UINT use = pick_adapter(d3d, focus, adapter);
    void **vt = *(void ***)d3d;
    HRESULT (WINAPI *ident)(IDirect3D9 *, UINT, DWORD, D3DADAPTER_IDENTIFIER9 *) =
        (HRESULT (WINAPI *)(IDirect3D9 *, UINT, DWORD, D3DADAPTER_IDENTIFIER9 *))vt[VT_GETADAPTERIDENTIFIER];
    D3DADAPTER_IDENTIFIER9 id;
    memset(&id, 0, sizeof id);
    ident(d3d, use, 0, &id);
    HRESULT hr = real_CreateDevice(d3d, use, type, focus, flags, pp, out);
    coop_log("CreateDevice asked=%u used=%u (%s) flags=0x%08lx hr=0x%08lx", adapter, use, id.Description,
             (unsigned long)flags, (unsigned long)hr);
    if (FAILED(hr) && use != adapter) {
        hr = real_CreateDevice(d3d, adapter, type, focus, flags, pp, out);
        coop_log("CreateDevice fallback to %u hr=0x%08lx", adapter, (unsigned long)hr);
    }
    if (SUCCEEDED(hr) && out) {
        capture_on_device(*out);
        split_on_device(*out);   /* after capture: the split hooks wrap the recording */
    }
    return hr;
}

static IDirect3D9 *WINAPI hook_Direct3DCreate9(UINT sdk)
{
    IDirect3D9 *d3d = real_Direct3DCreate9(sdk);
    if (d3d) {
        void *orig = patch_vtable(d3d, VT_CREATEDEVICE, (void *)hook_CreateDevice);
        if (orig)
            real_CreateDevice = (CreateDevice_t)orig;
    }
    return d3d;
}

/* ---- split screen: which physical pads this game reads ---- */
typedef DWORD (WINAPI *XInputGetState_t)(DWORD, void *);
typedef DWORD (WINAPI *XInputSetState_t)(DWORD, void *);
static XInputGetState_t real_XInputGetState;
static XInputSetState_t real_XInputSetState;

/* Test pad (pad number 9 in JERICHO_PADS): a connected XInput pad that runs a fixed
 * pattern, 4 s each: left stick forward, right trigger, right stick right, A, idle. For
 * tests without a physical pad (XINPUT_STATE: packet, buttons, LT, RT, LX, LY, RX, RY). */
#pragma pack(push, 1)
typedef struct { DWORD packet; WORD buttons; BYTE lt, rt; SHORT lx, ly, rx, ry; } test_pad_state;
#pragma pack(pop)

/* Test pads 9 and 8 (JERICHO_TESTPAD / JERICHO_TESTPAD2 patterns). */
static DWORD test_pad_as(void *state, const char *var);

static DWORD test_pad(void *state)
{
    return test_pad_as(state, "JERICHO_TESTPAD");
}

static DWORD test_pad_as(void *state, const char *var)
{
    static DWORD t0;
    test_pad_state *s = (test_pad_state *)state;
    DWORD now = GetTickCount();
    if (!t0)
        t0 = now;
    memset(s, 0, sizeof *s);
    s->packet = now / 16;
    char v[8];
    if (GetEnvironmentVariableA(var, v, sizeof v) > 0 && v[0] == '5') {
        /* Walk forward and turn slowly, fire now and then: a player who keeps playing. */
        DWORD t = (now - t0) % 6000;
        s->ly = 26000;
        s->rx = 9000;
        if (t >= 2000 && t < 2600) s->rt = 255;
        return ERROR_SUCCESS;
    }
    if (GetEnvironmentVariableA(var, v, sizeof v) > 0 && v[0] == '7') {
        /* Weapons, every 12 s: Y (power switch) at 1 s, the right trigger (main weapon) held
           3-4.5 s and tapped at 6.5 s; LB (the power) held 8-9 s; the left trigger (secondary
           weapon: Cole's mine launcher) held 10-11 s. */
        DWORD t = (now - t0) % 12000;
        if (t >= 1000 && t < 1300) s->buttons = 0x8000;
        if ((t >= 3000 && t < 4500) || (t >= 6500 && t < 6800)) s->rt = 255;
        if (t >= 8000 && t < 9000) s->buttons = 0x0100;
        if (t >= 10000 && t < 11000) s->lt = 255;
        return ERROR_SUCCESS;
    }
    if (GetEnvironmentVariableA(var, v, sizeof v) > 0 && v[0] == '6') {
        /* Special (RB) held 14 s of every 16 s: Jones's astral projection for that long. */
        DWORD t = (now - t0) % 16000;
        if (t >= 500 && t < 14500) s->buttons = 0x0200;
        return ERROR_SUCCESS;
    }
    if (GetEnvironmentVariableA(var, v, sizeof v) > 0 && v[0] == '3') {
        /* Menus from pad 2: Back (help) at 3 s, B at 9 s; Start (pause) at 15 s, B at 21 s,
           Start at 27 s, dpad down at 30 s, A at 33 s; each press 0.5 s. */
        static const struct { DWORD at; WORD b; } seq[] = {{3000, 0x0020}, {9000, 0x2000}, {15000, 0x0010},
            {21000, 0x2000}, {27000, 0x0010}, {30000, 0x0002}, {33000, 0x1000}};
        DWORD t = now - t0;
        for (size_t i = 0; i < sizeof seq / sizeof seq[0]; i++)
            if (t >= seq[i].at && t < seq[i].at + 500) s->buttons = seq[i].b;
        return ERROR_SUCCESS;
    }
    if (GetEnvironmentVariableA(var, v, sizeof v) > 0 && v[0] == '4') {
        /* Powers, a 16 s cycle: LB held 0-3 s (right trigger 1-2 s), RB held 5-8 s (right
           trigger 6-7 s), taps of LB at 10 s and RB at 12 s; the view turns slowly. */
        DWORD t = (now - t0) % 16000;
        if (t < 3000) s->buttons = 0x0100;
        else if (t >= 5000 && t < 8000) s->buttons = 0x0200;
        else if (t >= 10000 && t < 10300) s->buttons = 0x0100;
        else if (t >= 12000 && t < 12300) s->buttons = 0x0200;
        if ((t >= 1000 && t < 2000) || (t >= 6000 && t < 7000)) s->rt = 255;
        s->rx = 6000;
        return ERROR_SUCCESS;
    }
    if (GetEnvironmentVariableA(var, v, sizeof v) > 0 && v[0] == '2') {
        /* Every button in turn, 3 s each (pressed 1 s, then released): A B X Y LB RB LT RT
           dpad up/down/left/right, back, start, stick clicks; then 6 s of walking forward. */
        static const WORD buttons[] = {0x1000, 0x2000, 0x4000, 0x8000, 0x0100, 0x0200, 0, 0,
                                       0x0001, 0x0002, 0x0004, 0x0008, 0x0020, 0x0010, 0x0040, 0x0080};
        DWORD t = (now - t0) / 1000, n = sizeof buttons / sizeof buttons[0], step = (t / 3) % (n + 2);
        int pressed = t % 3 == 0;
        if (step < n && pressed) {
            s->buttons = buttons[step];
            if (step == 6) s->lt = 255;
            if (step == 7) s->rt = 255;
        } else if (step >= n) {
            s->ly = 30000;
        }
        return ERROR_SUCCESS;
    }
    DWORD ph = ((now - t0) / 4000) % 5;
    if (ph == 0) s->ly = 30000;
    else if (ph == 1) s->rt = 255;
    else if (ph == 2) s->rx = 20000;
    else if (ph == 3) s->buttons = 0x1000;   /* A */
    return ERROR_SUCCESS;
}

static DWORD read_pad(int phys, void *state)
{
    if (phys < 0)
        return ERROR_DEVICE_NOT_CONNECTED;
    if (phys == 9)
        return test_pad(state);
    if (phys == 8)
        return test_pad_as(state, "JERICHO_TESTPAD2");
    return real_XInputGetState((DWORD)phys, state);
}

/* Split screen in one game (split.c): pads_merge while a menu or a scene is up, where the
   game reads only its pad 0: both players' pads act as pad 0 then, pad 1 rests. */
static volatile LONG pads_merge;
static volatile LONG pads_merge_kind;   /* 1: menus and scenes, 2: player 2's astral projection */
static int pads_env;   /* JERICHO_PADS given: the map is the test's, not automatic */
/* Buttons held when the merge changes (the press that opened or closed the menu): kept from
   the game until released, or it would see them as new presses on the other pad. Bit 16/17:
   left/right trigger. */
static volatile LONG latch[2] = {-1, -1};   /* -1: take what is held at the next read */

static DWORD held_bits(const void *state)
{
    const BYTE *b = (const BYTE *)state;
    WORD buttons = *(const WORD *)(b + 4);
    return buttons | (b[6] > 30 ? 0x10000 : 0) | (b[7] > 30 ? 0x20000 : 0);
}

static void apply_latch(int v, void *state)
{
    BYTE *b = (BYTE *)state;
    DWORD held = held_bits(state);
    LONG l = latch[v];
    if (l == -1) l = (LONG)held;
    l &= (LONG)held;   /* released: free again */
    latch[v] = l;
    *(WORD *)(b + 4) &= (WORD)~l;
    if (l & 0x10000) b[6] = 0;
    if (l & 0x20000) b[7] = 0;
}

static DWORD pad_merged(void *state);

static DWORD WINAPI pad_GetState(DWORD i, void *state)
{
    if (i >= 4)
        return ERROR_DEVICE_NOT_CONNECTED;
    if (pads_merge && (i == 0 || i == 1)) {
        test_pad_state *s = (test_pad_state *)state;
        if (i == 1) {
            DWORD r = read_pad(pad_map[1], state);
            /* player 2's pad acts as pad 0 only (also during their astral projection: the
               projection ended when user 1 held "Return" too; virtual pad test 0.2.1) */
            if (r == ERROR_SUCCESS) { DWORD pk = s->packet; memset(s, 0, sizeof *s); s->packet = pk; }
            return r;
        }
        DWORD r0 = pad_merged(state);
        if (r0 == ERROR_SUCCESS) apply_latch(0, state);
        return r0;
    }
    DWORD r = read_pad(pad_map[i], state);
    if (r == ERROR_SUCCESS && i < 2 && latch[i] != 0) apply_latch((int)i, state);
    return r;
}

static DWORD pad_merged(void *state)
{
    {
        test_pad_state *s = (test_pad_state *)state;
        test_pad_state a, b;
        DWORD ra = read_pad(pad_map[0], &a), rb = read_pad(pad_map[1], &b);
        if (ra != ERROR_SUCCESS && rb != ERROR_SUCCESS)
            return ra;
        if (ra != ERROR_SUCCESS) { *s = b; return ERROR_SUCCESS; }
        if (rb != ERROR_SUCCESS) { *s = a; return ERROR_SUCCESS; }
        /* player 2's astral projection: their pad alone steers it (player 1 plays on, driven
           from their own pad by coop_split.lua) */
        if (pads_merge_kind == 2) { *s = b; s->packet = a.packet + b.packet; return ERROR_SUCCESS; }
        *s = a;
        s->packet = a.packet + b.packet;
        s->buttons = a.buttons | b.buttons;
        if (b.lt > s->lt) s->lt = b.lt;
        if (b.rt > s->rt) s->rt = b.rt;
        if (abs(b.lx) + abs(b.ly) > abs(a.lx) + abs(a.ly)) { s->lx = b.lx; s->ly = b.ly; }
        if (abs(b.rx) + abs(b.ry) > abs(a.rx) + abs(a.ry)) { s->rx = b.rx; s->ry = b.ry; }
        return ERROR_SUCCESS;
    }
}

static DWORD WINAPI pad_SetState(DWORD i, void *vib);

/* Pads plugged in or out during a split screen session (a pad's battery, a second player
   sitting down later): the players keep the pads they have; a player without one (or whose
   pad went away) gets the first connected pad nobody uses, player 2 first (player 1 may be
   on keyboard and mouse). Nothing changes with no pad connected. Returns 1 on a change. */
int display_hooks_pads_rescan(void)
{
    if (pads_env || !real_XInputGetState)
        return 0;
    int connected[4] = {0, 0, 0, 0}, any = 0;
    test_pad_state st;
    for (int p = 0; p < 4; p++)
        if (real_XInputGetState((DWORD)p, &st) == ERROR_SUCCESS)
            connected[p] = 1, any = 1;
    if (!any)
        return 0;
    int m[4];
    memcpy(m, pad_map, sizeof m);
    for (int u = 0; u < 2; u++)
        if (m[u] >= 0 && m[u] < 4 && !connected[m[u]])
            m[u] = -1;
    for (int u = 1; u >= 0; u--) {
        if (m[u] >= 0)
            continue;
        for (int p = 0; p < 4; p++)
            if (connected[p] && p != m[0] && p != m[1]) {
                /* player 1 gets a pad only once player 2 has one */
                if (u == 0 && m[1] < 0)
                    break;
                m[u] = p;
                break;
            }
    }
    m[2] = m[3] = -1;
    if (memcmp(m, pad_map, sizeof m) == 0)
        return 0;
    memcpy(pad_map, m, sizeof m);
    coop_log("pads: player 1 %d, player 2 %d (pads plugged in or out)", m[0], m[1]);
    return 1;
}

/* A split screen user's own pad as it is (no merging, no latch): buttons, LT, RT, LX, LY, RX, RY. */
int display_hooks_pad_read(int user, int out[7])
{
    if (user < 0 || user > 3 || !real_XInputGetState)
        return 0;
    test_pad_state s;
    memset(&s, 0, sizeof s);
    if (read_pad(pad_map[user], &s) != ERROR_SUCCESS)
        return 0;
    out[0] = s.buttons, out[1] = s.lt, out[2] = s.rt;
    out[3] = s.lx, out[4] = s.ly, out[5] = s.rx, out[6] = s.ry;
    return 1;
}

/* Split screen: which physical pads the two players use. Two or more connected: player 1 the
   first, player 2 the second. One: it is player 2's (player 1 on keyboard and mouse). None:
   as connected later. Off: as the game reads them. */
void display_hooks_pads_split(int on, int merge)
{
    /* merge 2: no latch, the buttons held go on being held: player 2's astral projection lasts
       while the button that started it is held, on user 0 (whose camera slot the astral camera
       takes; coop_split.lua merges before the engine changes the action set, so it is no new
       press there) and on player 2's own pad alike. */
    if ((on && merge) != pads_merge || (on && merge && merge != pads_merge_kind)) {
        latch[0] = latch[1] = merge == 2 ? 0 : -1;
        InterlockedExchange(&pads_merge_kind, on ? merge : 0);
        InterlockedExchange(&pads_merge, on && merge);
    }
    if (pads_env || !real_XInputGetState)
        return;
    int m[4] = {0, 1, 2, 3};
    if (on) {
        int found[4], n = 0;
        test_pad_state st;
        for (int p = 0; p < 4; p++)
            if (real_XInputGetState((DWORD)p, &st) == ERROR_SUCCESS)
                found[n++] = p;
        m[2] = m[3] = -1;
        if (n >= 2) { m[0] = found[0]; m[1] = found[1]; }
        else if (n == 1) { m[0] = -1; m[1] = found[0]; }
        else { m[0] = 0; m[1] = 1; }
    }
    if (memcmp(m, pad_map, sizeof m) != 0) {
        memcpy(pad_map, m, sizeof m);
        coop_log("pads: player 1 %d, player 2 %d%s", m[0], m[1], on ? "" : " (split off)");
    }
}

static DWORD WINAPI pad_SetState(DWORD i, void *vib)
{
    if (i >= 4 || pad_map[i] < 0 || pad_map[i] == 9)
        return ERROR_DEVICE_NOT_CONNECTED;
    return real_XInputSetState((DWORD)pad_map[i], vib);
}

static void install_pad_router(const char *spec)
{
    for (int i = 0; i < 4; i++)
        pad_map[i] = -1;
    if (_stricmp(spec, "none") != 0) {
        const char *c = spec;
        for (int i = 0; i < 4 && *c; i++) {
            pad_map[i] = atoi(c);
            c = strchr(c, ',');
            if (!c)
                break;
            c++;
        }
    }
    real_XInputGetState = (XInputGetState_t)patch_slot(find_iat_slot_ord("XINPUT1_3.dll", 2), (void *)pad_GetState);
    real_XInputSetState = (XInputSetState_t)patch_slot(find_iat_slot_ord("XINPUT1_3.dll", 3), (void *)pad_SetState);
    coop_log("pads: %d,%d,%d,%d (get %s, set %s)", pad_map[0], pad_map[1], pad_map[2], pad_map[3],
             real_XInputGetState ? "hooked" : "not imported", real_XInputSetState ? "hooked" : "not imported");
}

void display_hooks_install(void)
{
    char v[64];
    run_in_background = GetEnvironmentVariableA("JERICHO_BACKGROUND", v, sizeof v) == 1 && v[0] == '1';
    test_mode = run_in_background;
    kbm_off = GetEnvironmentVariableA("JERICHO_KBM", v, sizeof v) == 1 && v[0] == '0';
    if (kbm_off)
        coop_log("keyboard and mouse off (split screen, second window)");
    /* The pad router is always there (pass-through until split screen or a test sets it). */
    pads_env = GetEnvironmentVariableA("JERICHO_PADS", v, sizeof v) > 0;
    install_pad_router(pads_env ? v : "0,1,2,3");
    if (run_in_background)
        coop_log("background mode on");
    if (!real_CreateWindowExA)
        real_CreateWindowExA = (CreateWindowExA_t)patch_iat("USER32.dll", "CreateWindowExA", (void *)hook_CreateWindowExA);
    install_background_hooks();
    if (GetEnvironmentVariableA("JERICHO_WINPOS", v, sizeof v) > 0) {
        char *comma = strchr(v, ',');
        if (comma) {
            win_x = atoi(v);
            win_y = atoi(comma + 1);
            have_winpos = 1;
            if (!real_CreateWindowExA)
                real_CreateWindowExA = (CreateWindowExA_t)patch_iat("USER32.dll", "CreateWindowExA", (void *)hook_CreateWindowExA);
            real_SetWindowPos = (SetWindowPos_t)patch_iat("USER32.dll", "SetWindowPos", (void *)hook_SetWindowPos);
            real_MoveWindow = (MoveWindow_t)patch_iat("USER32.dll", "MoveWindow", (void *)hook_MoveWindow);
            if (!real_CreateWindowExA)
                coop_log("winpos: CreateWindowExA not in import table");
            /* The hooks above dereference these; fall back to the real functions. */
            if (!real_SetWindowPos)
                real_SetWindowPos = SetWindowPos;
            if (!real_MoveWindow)
                real_MoveWindow = MoveWindow;
        }
    }
    if (GetEnvironmentVariableA("JERICHO_WINSIZE", v, sizeof v) > 0) {
        char *comma = strchr(v, ',');
        if (comma && atoi(v) > 0 && atoi(comma + 1) > 0) {
            win_w = atoi(v);
            win_h = atoi(comma + 1);
            have_winsize = 1;
            if (!real_CreateWindowExA)
                real_CreateWindowExA = (CreateWindowExA_t)patch_iat("USER32.dll", "CreateWindowExA", (void *)hook_CreateWindowExA);
            if (!real_SetWindowPos)
                real_SetWindowPos = (SetWindowPos_t)patch_iat("USER32.dll", "SetWindowPos", (void *)hook_SetWindowPos);
            if (!real_MoveWindow)
                real_MoveWindow = (MoveWindow_t)patch_iat("USER32.dll", "MoveWindow", (void *)hook_MoveWindow);
            if (!real_SetWindowPos)
                real_SetWindowPos = SetWindowPos;
            if (!real_MoveWindow)
                real_MoveWindow = MoveWindow;
        }
    }
    /* Always: split screen (split.c) needs the device on every launch, not only in tests;
       JERICHO_ADAPTER only picks the adapter (tests). */
    GetEnvironmentVariableA("JERICHO_ADAPTER", adapter_mode, sizeof adapter_mode);
    real_Direct3DCreate9 = (Direct3DCreate9_t)patch_iat("d3d9.dll", "Direct3DCreate9", (void *)hook_Direct3DCreate9);
    if (!real_Direct3DCreate9)
        coop_log("adapter: Direct3DCreate9 not in import table");
}

void display_hooks_set_background(int on)
{
    if (run_in_background != (on != 0)) {
        run_in_background = on != 0;
        coop_log("background mode %s", on ? "on" : "off");
    }
}

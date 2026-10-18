/*
 * Window placement and render adapter selection for test instances (env driven).
 *
 *   JERICHO_WINPOS=x,y      create the game window at x,y (screen coordinates) and keep it
 *                           there, so a test instance opens directly on a chosen monitor.
 *   JERICHO_ADAPTER=window  create the Direct3D 9 device on the adapter that drives the
 *                           monitor holding the window (the game always asks for adapter 0).
 *   JERICHO_ADAPTER=<n>     use adapter n.
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
#include "capture.h"

static int win_x, win_y, have_winpos, run_in_background;
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

static int really_in_front(void)
{
    if (!run_in_background)
        return 1;
    return game_window && real_GetForegroundWindow() == game_window;
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
    return really_in_front() ? real_GetAsyncKeyState(key) : 0;
}

static BOOL WINAPI bg_SetCursorPos(int x, int y)
{
    return really_in_front() ? real_SetCursorPos(x, y) : TRUE;
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
    if (!really_in_front() && data)
        memset(data, 0, size);
    return hr;
}

static HRESULT WINAPI bg_GetDeviceData(void *dev, DWORD objsize, void *data, DWORD *count, DWORD flags)
{
    HRESULT hr = real_GetDeviceData(dev, objsize, data, count, flags);
    if (!really_in_front() && count)
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

static HWND WINAPI hook_CreateWindowExA(DWORD ex, LPCSTR cls, LPCSTR title, DWORD style, int x, int y,
                                        int w, int h, HWND parent, HMENU menu, HINSTANCE inst, LPVOID param)
{
    int game = cls && !IS_INTRESOURCE(cls) && strcmp(cls, "MercuryGameClass") == 0;
    if (game && have_winpos) {
        coop_log("window %d,%d -> %d,%d", x, y, win_x, win_y);
        x = win_x;
        y = win_y;
    }
    HWND hw = real_CreateWindowExA(ex, cls, title, style, x, y, w, h, parent, menu, inst, param);
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
    return real_SetWindowPos(hw, after, x, y, w, h, flags);
}

static BOOL WINAPI hook_MoveWindow(HWND hw, int x, int y, int w, int h, BOOL repaint)
{
    if (hw == game_window && have_winpos) {
        x = win_x;
        y = win_y;
    }
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
    coop_log("CreateDevice asked=%u used=%u (%s) hr=0x%08lx", adapter, use, id.Description, (unsigned long)hr);
    if (FAILED(hr) && use != adapter) {
        hr = real_CreateDevice(d3d, adapter, type, focus, flags, pp, out);
        coop_log("CreateDevice fallback to %u hr=0x%08lx", adapter, (unsigned long)hr);
    }
    if (SUCCEEDED(hr) && out)
        capture_on_device(*out);
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

void display_hooks_install(void)
{
    char v[64];
    run_in_background = GetEnvironmentVariableA("JERICHO_BACKGROUND", v, sizeof v) == 1 && v[0] == '1';
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
    GetEnvironmentVariableA("JERICHO_ADAPTER", adapter_mode, sizeof adapter_mode);
    if (adapter_mode[0] || capture_enabled()) {
        real_Direct3DCreate9 = (Direct3DCreate9_t)patch_iat("d3d9.dll", "Direct3DCreate9", (void *)hook_Direct3DCreate9);
        if (!real_Direct3DCreate9)
            coop_log("adapter: Direct3DCreate9 not in import table");
    }
}

void display_hooks_set_background(int on)
{
    if (run_in_background != (on != 0)) {
        run_in_background = on != 0;
        coop_log("background mode %s", on ? "on" : "off");
    }
}

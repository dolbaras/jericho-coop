/*
 * A model of the mods' DllMain import hooks, built as dinput8.dll next to ual_standin.exe:
 * GetCommandLineA gets " -InitLuaLine:MARK" appended (Jericho's boot line), GetSystemInfo reports at most
 * 8 processors (TimeShift's start-up fix). -DPLAIN: a plain import slot write, as Jericho 0.3.1 and
 * TimeShift 0.1.3 do; else iat_guard_hook() (iat_guard.c). Imports winmm.dll, as Jericho's DLL does.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "../iat_guard.h"

static char line[1024];
static void (WINAPI *real_GetSystemInfo)(LPSYSTEM_INFO);

static LPSTR WINAPI hook_GetCommandLineA(void) { return line; }

static void WINAPI hook_GetSystemInfo(LPSYSTEM_INFO si)
{
    real_GetSystemInfo(si);
    if (si->dwNumberOfProcessors > 8)
        si->dwNumberOfProcessors = 8;
    si->dwActiveProcessorMask &= 0xff;
}

static void report(const char *what)
{
    char path[MAX_PATH], t[300];
    if (!GetEnvironmentVariableA("UAL_FAKE_LOG", path, sizeof path))
        return;
    HANDLE f = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, 0, NULL);
    if (f == INVALID_HANDLE_VALUE)
        return;
    DWORD n = (DWORD)snprintf(t, sizeof t, "%s\r\n", what);
    WriteFile(f, t, n, &n, NULL);
    CloseHandle(f);
}

static void *hook(const char *func, void *h)
{
    char t[200];
#ifdef PLAIN
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); d->Name; d++) {
        if (_stricmp((const char *)(base + d->Name), "KERNEL32.dll") != 0)
            continue;
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + d->OriginalFirstThunk);
        void **slots = (void **)(base + d->FirstThunk);
        for (int i = 0; names[i].u1.AddressOfData; i++) {
            if (IMAGE_SNAP_BY_ORDINAL(names[i].u1.Ordinal))
                continue;
            if (strcmp((const char *)((IMAGE_IMPORT_BY_NAME *)(base + names[i].u1.AddressOfData))->Name, func) == 0) {
                DWORD old;
                VirtualProtect(&slots[i], sizeof(void *), PAGE_READWRITE, &old);
                void *prev = slots[i];
                slots[i] = h;
                VirtualProtect(&slots[i], sizeof(void *), old, &old);
                snprintf(t, sizeof t, "model (plain): %s hooked", func);
                report(t);
                return prev;
            }
        }
    }
    return NULL;
#else
    iat_guard_result r;
    if (!iat_guard_hook("KERNEL32.dll", func, h, &r))
        return NULL;
    snprintf(t, sizeof t, "model (guard): %s hooked, prepatched %d by %s, %d call(s) of the exe redirected", func, r.prepatched,
             r.prepatched ? r.by : "-", r.redirected);
    report(t);
    return r.prev;
#endif
}

typedef HRESULT (WINAPI *DirectInput8Create_t)(HINSTANCE, DWORD, REFIID, LPVOID *, LPUNKNOWN);

__declspec(dllexport) HRESULT WINAPI DirectInput8Create(HINSTANCE inst, DWORD ver, REFIID riid, LPVOID *out, LPUNKNOWN outer)
{
    (void)inst; (void)ver; (void)riid; (void)out; (void)outer;
    return E_FAIL;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)inst;
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        (void)timeGetTime();
        snprintf(line, sizeof line, "%s -InitLuaLine:MARK", GetCommandLineA());
        hook("GetCommandLineA", (void *)hook_GetCommandLineA);
        real_GetSystemInfo = (void (WINAPI *)(LPSYSTEM_INFO))hook("GetSystemInfo", (void *)hook_GetSystemInfo);
        if (!real_GetSystemInfo)
            real_GetSystemInfo = GetSystemInfo;
    }
    return TRUE;
}

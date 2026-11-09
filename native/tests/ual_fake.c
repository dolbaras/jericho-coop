/*
 * A stand-in for Ultimate ASI Loader's start-up, written from its source (v10.0.2 source/loader/startup/
 * startup.cpp HookEntryPoints / PatchKernel32 / RestoreSlots, read on GitHub 2026-11-08; never the real
 * loader). Built as winmm.dll next to a stand-in exe (ual_standin.c):
 *   DllMain: the exe's kernel32 import slots of some of the loader's functions get a wrapper; the value each
 *            held is recorded.
 *   the exe's first call of one of them (return address inside the exe): every recorded value is written
 *            back, unconditionally, as the loader does before it loads its plugins.
 * Exports winmm's timeBeginPeriod / timeEndPeriod / timeGetTime (forwarded to the system's winmm.dll) and
 * IsUltimateASILoader, as the loader does.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static BYTE *exe_lo, *exe_hi;
static struct { const char *name; void **slot; void *seen; } rec[8];
static int nrec;
static volatile LONG started;

static void report(const char *what)
{
    char path[MAX_PATH], line[300];
    if (!GetEnvironmentVariableA("UAL_FAKE_LOG", path, sizeof path))
        return;
    HANDLE f = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, 0, NULL);
    if (f == INVALID_HANDLE_VALUE)
        return;
    DWORD n = (DWORD)snprintf(line, sizeof line, "%s\r\n", what);
    WriteFile(f, line, n, &n, NULL);
    CloseHandle(f);
}

static void entry(void *ret)
{
    if ((BYTE *)ret < exe_lo || (BYTE *)ret >= exe_hi || started)
        return;
    if (InterlockedCompareExchange(&started, 1, 0) != 0)
        return;
    for (int i = 0; i < nrec; i++) {
        DWORD old;
        VirtualProtect(rec[i].slot, sizeof(void *), PAGE_READWRITE, &old);
        *rec[i].slot = rec[i].seen;
        VirtualProtect(rec[i].slot, sizeof(void *), old, &old);
    }
    char t[64];
    snprintf(t, sizeof t, "fake loader: %d slot(s) written back", nrec);
    report(t);
}

static void WINAPI w_GetStartupInfoA(LPSTARTUPINFOA a) { entry(__builtin_return_address(0)); GetStartupInfoA(a); }
static LPSTR WINAPI w_GetCommandLineA(void) { entry(__builtin_return_address(0)); return GetCommandLineA(); }
static void WINAPI w_GetSystemInfo(LPSYSTEM_INFO a) { entry(__builtin_return_address(0)); GetSystemInfo(a); }
static void WINAPI w_GetSystemTimeAsFileTime(LPFILETIME a) { entry(__builtin_return_address(0)); GetSystemTimeAsFileTime(a); }
static HMODULE WINAPI w_GetModuleHandleA(LPCSTR a) { entry(__builtin_return_address(0)); return GetModuleHandleA(a); }

static const struct { const char *name; void *wrapper; } wrappers[] = {
    {"GetStartupInfoA", (void *)w_GetStartupInfoA}, {"GetCommandLineA", (void *)w_GetCommandLineA},
    {"GetSystemInfo", (void *)w_GetSystemInfo}, {"GetSystemTimeAsFileTime", (void *)w_GetSystemTimeAsFileTime},
    {"GetModuleHandleA", (void *)w_GetModuleHandleA},
};

static void patch_exe(void)
{
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    exe_lo = base;
    exe_hi = base + nt->OptionalHeader.SizeOfImage;
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); dir.VirtualAddress && d->Name; d++) {
        if (_stricmp((const char *)(base + d->Name), "kernel32.dll") != 0)
            continue;
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + d->OriginalFirstThunk);
        void **slots = (void **)(base + d->FirstThunk);
        for (int i = 0; d->OriginalFirstThunk && names[i].u1.AddressOfData; i++) {
            if (IMAGE_SNAP_BY_ORDINAL(names[i].u1.Ordinal))
                continue;
            const char *fn = (const char *)((IMAGE_IMPORT_BY_NAME *)(base + names[i].u1.AddressOfData))->Name;
            for (size_t w = 0; w < sizeof wrappers / sizeof wrappers[0]; w++)
                if (strcmp(fn, wrappers[w].name) == 0 && nrec < 8) {
                    DWORD old;
                    VirtualProtect(&slots[i], sizeof(void *), PAGE_READWRITE, &old);
                    rec[nrec].name = wrappers[w].name;
                    rec[nrec].slot = &slots[i];
                    rec[nrec].seen = slots[i];
                    slots[i] = wrappers[w].wrapper;
                    VirtualProtect(&slots[i], sizeof(void *), old, &old);
                    nrec++;
                }
        }
    }
    char t[64];
    snprintf(t, sizeof t, "fake loader: %d slot(s) of the exe patched (DllMain)", nrec);
    report(t);
}

static FARPROC sys_winmm(const char *name)
{
    static HMODULE h;
    if (!h) {
        char p[MAX_PATH];
        UINT n = GetSystemDirectoryA(p, MAX_PATH);
        if (n == 0 || n + 11 >= MAX_PATH)
            return NULL;
        strcpy(p + n, "\\winmm.dll");
        h = LoadLibraryA(p);
    }
    return h ? GetProcAddress(h, name) : NULL;
}

__declspec(dllexport) UINT WINAPI timeBeginPeriod(UINT p) { return ((UINT (WINAPI *)(UINT))sys_winmm("timeBeginPeriod"))(p); }
__declspec(dllexport) UINT WINAPI timeEndPeriod(UINT p) { return ((UINT (WINAPI *)(UINT))sys_winmm("timeEndPeriod"))(p); }
__declspec(dllexport) DWORD WINAPI timeGetTime(void) { return ((DWORD (WINAPI *)(void))sys_winmm("timeGetTime"))(); }
__declspec(dllexport) BOOL WINAPI IsUltimateASILoader(void) { return TRUE; }

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)inst;
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
        patch_exe();
    return TRUE;
}

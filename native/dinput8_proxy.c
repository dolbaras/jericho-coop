/*
 * dinput8.dll proxy for Clive Barker's Jericho (32-bit).
 *
 * Placed next to bin/Jericho.exe, it forwards DirectInput8Create to the system DLL,
 * installs the co-op transport (coop_net.c) and these test-only hooks:
 *   JERICHO_MULTI=1  Jericho refuses to start when FindWindowA("MercuryGameClass") finds
 *                    another instance. With this variable set, that lookup returns NULL so
 *                    several instances can run on one PC (bot QA). Nothing else changes.
 *   JERICHO_STACKDUMP=<file>  When the game exits (its FATAL ERROR path calls ExitProcess),
 *                    write candidate return addresses found on the stack to <file>.
 *   JERICHO_WINPOS / JERICHO_ADAPTER  window placement and render adapter (display_hooks.c).
 * The exe on disk is never modified.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "coop_net.h"
#include "display_hooks.h"
#include "boot_inject.h"

typedef HRESULT (WINAPI *DirectInput8Create_t)(HINSTANCE, DWORD, REFIID, LPVOID *, LPUNKNOWN);
static DirectInput8Create_t real_DirectInput8Create;

static HWND WINAPI hook_FindWindowA(LPCSTR cls, LPCSTR name)
{
    if (cls && !IS_INTRESOURCE(cls) && strcmp(cls, "MercuryGameClass") == 0)
        return NULL;
    return FindWindowExA(NULL, NULL, cls, name);
}

/* Overwrite the first 5 bytes of target with `jmp hook`. The hook never calls the
 * original, so no trampoline is needed. */
static BOOL patch_jmp(void *target, void *hook)
{
    DWORD old;
    unsigned char *p = (unsigned char *)target;
    if (!VirtualProtect(p, 5, PAGE_EXECUTE_READWRITE, &old))
        return FALSE;
    p[0] = 0xE9;
    *(DWORD *)(p + 1) = (DWORD)((unsigned char *)hook - (p + 5));
    VirtualProtect(p, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), p, 5);
    return TRUE;
}

static char stackdump_path[MAX_PATH];

/* A dword on the stack is a likely return address if it points into the exe's code and
 * the bytes before it decode as a call (E8 rel32, FF /2 with 2, 3 or 6 byte forms). */
static BOOL looks_like_return(DWORD a, DWORD lo, DWORD hi)
{
    const unsigned char *p = (const unsigned char *)a;
    if (a < lo + 6 || a >= hi)
        return FALSE;
    if (p[-5] == 0xE8)
        return TRUE;
    if (p[-2] == 0xFF && (p[-1] & 0x38) == 0x10)
        return TRUE;
    if (p[-3] == 0xFF && (p[-2] & 0x38) == 0x10)
        return TRUE;
    if (p[-6] == 0xFF && (p[-5] & 0x38) == 0x10)
        return TRUE;
    return FALSE;
}

static void dump_stack(const char *what, DWORD *sp)
{
    NT_TIB *tib = (NT_TIB *)NtCurrentTeb();
    DWORD *top = (DWORD *)tib->StackBase;
    HMODULE exe = GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((BYTE *)exe + ((IMAGE_DOS_HEADER *)exe)->e_lfanew);
    DWORD lo = (DWORD)exe, hi = lo + nt->OptionalHeader.SizeOfImage;
    FILE *f = fopen(stackdump_path, "a");
    if (!f)
        return;
    fprintf(f, "%s thread %lu esp=%p\n", what, GetCurrentThreadId(), (void *)sp);
    /* The whole image is mapped, so reading code bytes inside [lo, hi) is safe. */
    for (DWORD *q = sp; q < top; q++)
        if (looks_like_return(*q, lo, hi))
            fprintf(f, "  [esp+%04x] %08lx\n", (unsigned)((BYTE *)q - (BYTE *)sp), *q);
    fclose(f);
}

static void __stdcall hook_ExitProcess(UINT code)
{
    char what[32];
    sprintf(what, "ExitProcess(%u)", code);
    dump_stack(what, (DWORD *)&code);
    TerminateProcess(GetCurrentProcess(), code);
}

/* Jericho's "Check failed" handlers (0x404f00, 0x404fc0) start with GetLastError. Dump the
 * stack when called from there; otherwise behave exactly like GetLastError (TEB field). */
#define JERICHO_CHECKFAILED_RET1 0x00404f32
#define JERICHO_CHECKFAILED_RET2 0x00404fdb

static DWORD WINAPI hook_GetLastError(void)
{
    DWORD ret = (DWORD)__builtin_return_address(0);
    if (ret == JERICHO_CHECKFAILED_RET1 || ret == JERICHO_CHECKFAILED_RET2)
        dump_stack("CheckFailed", (DWORD *)__builtin_frame_address(0));
    return *(DWORD *)((BYTE *)NtCurrentTeb() + 0x34);
}

static void load_real_dinput8(void)
{
    char path[MAX_PATH];
    UINT n = GetSystemDirectoryA(path, MAX_PATH);
    if (n == 0 || n + 13 >= MAX_PATH)
        return;
    strcpy(path + n, "\\dinput8.dll");
    HMODULE h = LoadLibraryA(path);
    if (h)
        real_DirectInput8Create = (DirectInput8Create_t)GetProcAddress(h, "DirectInput8Create");
}

static BOOL env_is_1(const char *name)
{
    char v[8];
    DWORD n = GetEnvironmentVariableA(name, v, sizeof v);
    return n == 1 && v[0] == '1';
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        load_real_dinput8();
        coop_net_install();
        display_hooks_install();
        boot_inject_install(inst);
        if (env_is_1("JERICHO_MULTI")) {
            void *fw = (void *)GetProcAddress(GetModuleHandleA("user32.dll"), "FindWindowA");
            if (fw)
                patch_jmp(fw, (void *)hook_FindWindowA);
        }
        if (GetEnvironmentVariableA("JERICHO_STACKDUMP", stackdump_path, MAX_PATH) > 0) {
            void *ep = (void *)GetProcAddress(GetModuleHandleA("kernel32.dll"), "ExitProcess");
            if (ep)
                patch_jmp(ep, (void *)hook_ExitProcess);
            void *gle = (void *)GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetLastError");
            if (gle)
                patch_jmp(gle, (void *)hook_GetLastError);
        }
    }
    return TRUE;
}

__declspec(dllexport) HRESULT WINAPI DirectInput8Create(HINSTANCE inst, DWORD ver, REFIID riid,
                                                        LPVOID *out, LPUNKNOWN outer)
{
    if (!real_DirectInput8Create)
        return E_FAIL;
    HRESULT hr = real_DirectInput8Create(inst, ver, riid, out, outer);
    if (SUCCEEDED(hr) && out)
        display_hooks_wrap_dinput(*out);
    return hr;
}

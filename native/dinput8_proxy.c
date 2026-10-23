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
 *   JERICHO_TEST_ABABANILI=1  makes the engine fix below happen on every Ababanili update.
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

/* An access violation (first chance): where, what it touched, the registers and the return
 * addresses on that thread's stack. The game's own handler later ends in ExitProcess with
 * the exception code (0xC0000005), whose stack shows only that handler. The first few only. */
static LONG CALLBACK log_access_violation(EXCEPTION_POINTERS *x)
{
    static LONG seen;
    EXCEPTION_RECORD *r = x->ExceptionRecord;
    CONTEXT *c = x->ContextRecord;
    if (r->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || InterlockedIncrement(&seen) > 4)
        return EXCEPTION_CONTINUE_SEARCH;
    char what[200];
    sprintf(what, "AccessViolation at %p (%s %p) eax=%08lx ebx=%08lx ecx=%08lx edx=%08lx esi=%08lx edi=%08lx ebp=%08lx",
            r->ExceptionAddress, r->ExceptionInformation[0] ? "write" : "read",
            (void *)r->ExceptionInformation[1], c->Eax, c->Ebx, c->Ecx, c->Edx, c->Esi, c->Edi, c->Ebp);
    dump_stack(what, (DWORD *)c->Esp);
    return EXCEPTION_CONTINUE_SEARCH;
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

/* The last boss's Ababanili (Sum_End): their steering (0x4fc9b0) takes a new prey when theirs is
 * gone and reads it with no check. With no prey left (every player near is down or bound by the
 * rune, which the single player game never reaches) that read hit NULL and the game crashed
 * (0.2.4 tests, story split G15). It resumes on the function's own "no target" path (a zero
 * steering vector for that frame). Only on the retail exe (both places' bytes checked), in
 * memory, for that one instruction. */
#define ABABANILI_READ 0x004fcd47
#define ABABANILI_NO_TARGET 0x004fcd2a

static LONG CALLBACK engine_fixes(EXCEPTION_POINTERS *x)
{
    static LONG checked, retail, logged;
    EXCEPTION_RECORD *r = x->ExceptionRecord;
    CONTEXT *c = x->ContextRecord;
    if (r->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || (DWORD)r->ExceptionAddress != ABABANILI_READ
        || r->ExceptionInformation[0] != 0 || c->Edx != 0)
        return EXCEPTION_CONTINUE_SEARCH;
    if (!checked) {
        static const unsigned char read[6] = {0x8b, 0x02, 0x8d, 0x4c, 0x24, 0x38};       /* mov eax,[edx] */
        static const unsigned char none[6] = {0xd9, 0xee, 0x8b, 0x74, 0x24, 0x60};       /* fldz; mov esi,[esp+60] */
        retail = memcmp((void *)ABABANILI_READ, read, 6) == 0 && memcmp((void *)ABABANILI_NO_TARGET, none, 6) == 0;
        checked = 1;
    }
    if (!retail)
        return EXCEPTION_CONTINUE_SEARCH;
    c->Eip = ABABANILI_NO_TARGET;
    if (InterlockedIncrement(&logged) == 1)
        coop_log("engine fix: Ababanili without prey (no target this frame)");
    return EXCEPTION_CONTINUE_EXECUTION;
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
            AddVectoredExceptionHandler(1, log_access_violation);
        }
        /* added last, so it is asked first: a fixed read is not logged as a crash */
        AddVectoredExceptionHandler(1, engine_fixes);
        /* Test: every Ababanili loses its prey at that read (xor edx,edx over the compare). */
        if (env_is_1("JERICHO_TEST_ABABANILI")) {
            static const unsigned char cmp[8] = {0x3b, 0xd1, 0x75, 0x04, 0x84, 0xdb, 0x75, 0x42};
            static const unsigned char lose[8] = {0x31, 0xd2, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90};
            unsigned char *p = (unsigned char *)0x004fcd3f;
            DWORD old;
            if (memcmp(p, cmp, 8) == 0 && VirtualProtect(p, 8, PAGE_EXECUTE_READWRITE, &old)) {
                memcpy(p, lose, 8);
                VirtualProtect(p, 8, old, &old);
                FlushInstructionCache(GetCurrentProcess(), p, 8);
            }
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

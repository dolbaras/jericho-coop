/*
 * Hooks in the exe's import slots that a loader which patched the same slots first cannot undo.
 *
 * Ultimate ASI Loader (as winmm.dll, d3d9.dll or any other name the game loads before this DLL; its
 * source, v10.0.2 source/loader/startup/startup.cpp HookEntryPoints / RestoreSlots, and v7.8.0, which
 * matches the slots by value) patches the exe's kernel32 import slots of about 30 functions in its
 * DllMain, GetCommandLineA and GetSystemInfo among them, and records the value it saw in each. At the
 * exe's first call of one of them it writes every recorded value back, then loads its plugins. A hook
 * this DLL put into such a slot in between is gone then (Jericho: the boot line on the command line;
 * TimeShift: the processor count fix). Only the ORDER decides: a loader that runs after this DLL records
 * our hook and writes it back.
 *
 * iat_guard_hook() writes the hook into the slot as a plain import hook does. When the slot held
 * neither the system's function nor a hook of this DLL (another module patched it first), it also points
 * the exe's own instructions that read the slot (call / jmp / push [slot], mov reg,[slot]) at a cell of
 * this DLL holding the hook: a value written back into the slot later changes nothing for them. The hook
 * calls on to what the slot held (the loader's wrapper, which calls the system's function), as before.
 * Without such a module nothing but the slot changes.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "iat_guard.h"

#define IG_MAX 16
static struct { void **slot; void *cell; } ig_cells[IG_MAX];
static int ig_used;

static void **find_slot(BYTE *base, const char *dll, const char *func)
{
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

static int write_ptr(void **at, void *value)
{
    DWORD old;
    if (!VirtualProtect(at, sizeof *at, PAGE_READWRITE, &old))
        return 0;
    *at = value;
    VirtualProtect(at, sizeof *at, old, &old);
    return 1;
}

static HMODULE module_of(const void *p)
{
    HMODULE m = NULL;
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)p, &m))
        return NULL;
    return m;
}

/* The exe's instructions with the slot's address as their memory operand: FF 15 / FF 25 / FF 35 (call, jmp,
 * push [disp32]), 8B /r with mod 00 rm 101 (mov r32,[disp32]) and A1 (mov eax,[moffs32]). Their operand is
 * pointed at the cell. Executable sections only, committed and readable pages only. */
static int redirect_refs(BYTE *base, void **slot, void **cell)
{
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_SECTION_HEADER *s = IMAGE_FIRST_SECTION(nt);
    DWORD want = (DWORD)(ULONG_PTR)slot, to = (DWORD)(ULONG_PTR)cell;
    BYTE low = (BYTE)(want & 0xff);
    int n = 0;
    for (WORD k = 0; k < nt->FileHeader.NumberOfSections; k++, s++) {
        if (!(s->Characteristics & IMAGE_SCN_MEM_EXECUTE))
            continue;
        BYTE *lo = base + s->VirtualAddress;
        BYTE *hi = lo + (s->Misc.VirtualSize ? s->Misc.VirtualSize : s->SizeOfRawData);
        for (BYTE *p = lo; p < hi;) {
            MEMORY_BASIC_INFORMATION mbi;
            if (!VirtualQuery(p, &mbi, sizeof mbi))
                break;
            BYTE *end = (BYTE *)mbi.BaseAddress + mbi.RegionSize;
            if (end > hi)
                end = hi;
            if (mbi.State == MEM_COMMIT && !(mbi.Protect & (PAGE_GUARD | PAGE_NOACCESS)) && (mbi.Protect & 0xEE)) {
                BYTE *q = p + 2;   /* q: where the 4-byte operand would start */
                while (q + 4 <= end) {
                    BYTE *f = (BYTE *)memchr(q, low, (size_t)(end - 4 - q) + 1);
                    if (!f)
                        break;
                    q = f + 1;
                    if (*(DWORD *)f != want)
                        continue;
                    BYTE op = f[-2], m = f[-1];
                    if (!((op == 0xFF && (m == 0x15 || m == 0x25 || m == 0x35)) || (op == 0x8B && (m & 0xC7) == 0x05) || m == 0xA1))
                        continue;
                    DWORD old;
                    if (!VirtualProtect(f, 4, PAGE_EXECUTE_READWRITE, &old))
                        continue;
                    *(DWORD *)f = to;
                    VirtualProtect(f, 4, old, &old);
                    FlushInstructionCache(GetCurrentProcess(), f - 2, 6);
                    n++;
                    q = f + 4;
                }
            }
            p = end;
        }
    }
    return n;
}

int iat_guard_hook(const char *dll, const char *func, void *hook, iat_guard_result *r)
{
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    memset(r, 0, sizeof *r);
    r->slot = find_slot(base, dll, func);
    if (!r->slot)
        return 0;
    /* a slot redirected before (a second hook of the same function): the cell is what the exe calls */
    for (int i = 0; i < ig_used; i++)
        if (ig_cells[i].slot == r->slot) {
            r->prev = ig_cells[i].cell;
            ig_cells[i].cell = hook;
            write_ptr(r->slot, hook);
            return 1;
        }
    r->prev = *r->slot;
    HMODULE sysmod = GetModuleHandleA(dll);
    void *sys = sysmod ? (void *)GetProcAddress(sysmod, func) : NULL;
    HMODULE self = module_of((const void *)iat_guard_hook), owner = module_of(r->prev);
    r->prepatched = sys && r->prev != sys && owner != self;
    if (!write_ptr(r->slot, hook))
        return 0;
    if (r->prepatched && ig_used < IG_MAX) {
        char path[MAX_PATH];
        DWORD n = owner ? GetModuleFileNameA(owner, path, sizeof path) : 0;
        const char *b = n && n < sizeof path ? strrchr(path, '\\') : NULL;
        snprintf(r->by, sizeof r->by, "%s", b ? b + 1 : n && n < sizeof path ? path : "?");
        int i = ig_used++;
        ig_cells[i].slot = r->slot;
        ig_cells[i].cell = hook;
        r->redirected = redirect_refs(base, r->slot, &ig_cells[i].cell);
    }
    return 1;
}

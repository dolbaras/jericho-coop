/*
 * Starts the co-op mod on a normal game launch: when the command line has no
 * -InitLuaLine of its own, append one that runs <game>\coop\boot.lua after the engine's
 * Lua init (the engine executes InitLuaLine once per Lua start; boot.lua re-arms it).
 * The exe reads its command line through GetCommandLineA (import table hook).
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "boot_inject.h"
#include "coop_net.h"

static char cmdline[4096];
static LPSTR (WINAPI *real_GetCommandLineA)(void);

static LPSTR WINAPI hook_GetCommandLineA(void)
{
    return cmdline;
}

static void **find_import(const char *dll, const char *func)
{
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); dir.VirtualAddress && d->Name; d++) {
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

void boot_inject_install(HINSTANCE self)
{
    const char *orig = GetCommandLineA();
    if (!orig || strstr(orig, "-InitLuaLine") || strstr(orig, "-initlualine"))
        return;   /* test runs and users passing their own line keep it */

    /* <game>\bin\dinput8.dll -> <game>/coop/ */
    char dir[MAX_PATH];
    if (!GetModuleFileNameA(self, dir, MAX_PATH))
        return;
    char *slash = strrchr(dir, '\\');
    if (!slash)
        return;
    *slash = 0;                       /* <game>\bin */
    slash = strrchr(dir, '\\');
    if (!slash)
        return;
    strcpy(slash, "\\coop\\");        /* <game>\coop\ */
    char probe[MAX_PATH];
    snprintf(probe, sizeof probe, "%sboot.lua", dir);
    if (GetFileAttributesA(probe) == INVALID_FILE_ATTRIBUTES)
        return;                       /* mod files not installed: plain game */
    for (char *p = dir; *p; p++)
        if (*p == '\\')
            *p = '/';
    if (strchr(dir, '\'') || strchr(dir, '"'))
        return;                       /* would break the Lua/command line quoting */

    int n = snprintf(cmdline, sizeof cmdline,
                     "%s -InitLuaLine:\"COOP_DIR='%s' COOP_CFG={} dofile(COOP_DIR..'boot.lua')\"", orig, dir);
    if (n <= 0 || n >= (int)sizeof cmdline)
        return;
    void **slot = find_import("KERNEL32.dll", "GetCommandLineA");
    DWORD old;
    if (slot && VirtualProtect(slot, sizeof *slot, PAGE_READWRITE, &old)) {
        real_GetCommandLineA = (LPSTR (WINAPI *)(void))*slot;
        *slot = (void *)hook_GetCommandLineA;
        VirtualProtect(slot, sizeof *slot, old, &old);
        coop_log("boot: mod at %s", dir);
    }
}

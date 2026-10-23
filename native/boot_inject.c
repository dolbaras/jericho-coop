/*
 * Starts the co-op mod on a normal game launch: when the command line has no
 * -InitLuaLine of its own, append one that runs <game>\coop\boot.lua after the engine's
 * Lua init (the engine executes InitLuaLine once per Lua start; boot.lua re-arms it).
 * The exe reads its command line through GetCommandLineA (import table hook).
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

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

/* <game>\coop\ with forward slashes, or %JERICHO_COOP_DIR% (test runs). */
static char coop_dir[MAX_PATH];

const char *boot_inject_dir(void)
{
    return coop_dir;
}

/* The command line holds only a short, path-free boot line: the engine's command-line
 * parser fails on long text after a '.' (App.cpp "iExt < sizeof(Ext)"), and the default
 * install folder "Clive Barker's Jericho" has a quote. Net.CoopBoot() (coop_net.c) returns
 * the real boot chunk with the folder and the test config. */
#define BOOT_LINE "assert(loadstring(Net['CoopBoot']()))()"

/* <game>\coop\ for Lua's dofile, which opens files through the code page: a game folder with
 * characters outside it (Cyrillic on an English Windows...) is given by its short name, else
 * relative to the working directory when that is inside the game folder (the shortcut and
 * Steam start the game there). */
static int coop_dir_ansi(const wchar_t *wdir, const wchar_t *game)
{
    if (coop_ansi_path(wdir, coop_dir, sizeof coop_dir))
        return 1;
    coop_dir[0] = 0;
    wchar_t cwd[MAX_PATH];
    DWORD n = GetCurrentDirectoryW(MAX_PATH, cwd);
    size_t g = wcslen(game);
    if (n == 0 || n >= MAX_PATH || _wcsnicmp(cwd, game, g) != 0 || (cwd[g] && cwd[g] != L'\\'))
        return 0;
    for (const wchar_t *p = cwd + g; *p; p++)
        if (*p == L'\\' && p[1]) {
            if (strlen(coop_dir) + 3 + 6 > sizeof coop_dir) {   /* "..\" and "coop\" with its end */
                coop_dir[0] = 0;
                return 0;
            }
            strcat(coop_dir, "..\\");
        }
    strcat(coop_dir, "coop\\");
    return 1;
}

void boot_inject_install(HINSTANCE self)
{
    wchar_t game[MAX_PATH], wdir[MAX_PATH + 8];
    game[0] = 0;
    DWORD n = GetEnvironmentVariableA("JERICHO_COOP_DIR", coop_dir, sizeof coop_dir);
    if (n == 0 || n >= sizeof coop_dir) {
        /* <game>\bin\dinput8.dll -> <game>/coop/ */
        coop_dir[0] = 0;
        n = GetModuleFileNameW(self, game, MAX_PATH);
        if (n == 0 || n >= MAX_PATH)
            return;
        wchar_t *slash = wcsrchr(game, L'\\');
        if (!slash)
            return;
        *slash = 0;                       /* <game>\bin */
        slash = wcsrchr(game, L'\\');
        if (!slash)
            return;
        *slash = 0;                       /* <game> */
        wcscpy(wdir, game);
        wcscat(wdir, L"\\coop\\");
        if (!coop_dir_ansi(wdir, game)) {
            coop_log("boot: the game folder's name does not fit the code page and has no short name");
            return;
        }
    }
    for (char *p = coop_dir; *p; p++)
        if (*p == '\\')
            *p = '/';

    const char *orig = GetCommandLineA();
    if (!orig || strstr(orig, "-InitLuaLine") || strstr(orig, "-initlualine"))
        return;   /* test runs and users passing their own line keep it */
    char probe[MAX_PATH + 16];
    snprintf(probe, sizeof probe, "%sboot.lua", coop_dir);
    if (GetFileAttributesA(probe) == INVALID_FILE_ATTRIBUTES)
        return;                       /* mod files not installed: plain game */

    int len = snprintf(cmdline, sizeof cmdline, "%s -InitLuaLine:\"" BOOT_LINE "\"", orig);
    if (len <= 0 || len >= (int)sizeof cmdline)
        return;
    void **slot = find_import("KERNEL32.dll", "GetCommandLineA");
    DWORD old;
    if (slot && VirtualProtect(slot, sizeof *slot, PAGE_READWRITE, &old)) {
        real_GetCommandLineA = (LPSTR (WINAPI *)(void))*slot;
        *slot = (void *)hook_GetCommandLineA;
        VirtualProtect(slot, sizeof *slot, old, &old);
        coop_log("boot: mod at %s", coop_dir);
    }
}

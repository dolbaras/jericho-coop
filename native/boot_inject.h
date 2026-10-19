#pragma once
#include <windows.h>

/* Appends the co-op boot line to the game's command line when <game>\coop\boot.lua exists
 * and the command line has no -InitLuaLine (see boot_inject.c). */
void boot_inject_install(HINSTANCE self);

/* The co-op Lua folder ("<game>/coop/" or %JERICHO_COOP_DIR%), "" if unknown. */
const char *boot_inject_dir(void);

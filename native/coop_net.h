#pragma once

/* Rewrites unused entries of Jericho's Lua `Net` table to the Net.Coop* functions and
 * initialises ENet. Call once from DllMain before the game starts Lua. Returns the number
 * of functions installed. */
int coop_net_install(void);

/* Appends a timestamped line to %JERICHO_COOP_LOG% (no-op when unset). */
void coop_log(const char *fmt, ...);

/* A file in the co-op folder (Documents\...\Coop, or %JERICHO_COOP_SAVEDIR%) from "coop:name"
 * (name of [A-Za-z0-9_.-]). 1 = out holds the path. */
int coop_data_path(const char *name, char *out, size_t size);

/* A path for the C library and the game's ANSI calls: as it is when the code page has every
 * character, else its short (8.3) form. 0 when neither works (8.3 names off on that drive). */
int coop_ansi_path(const wchar_t *path, char *out, size_t size);

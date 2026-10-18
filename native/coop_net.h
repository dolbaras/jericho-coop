#pragma once

/* Rewrites unused entries of Jericho's Lua `Net` table to the Net.Coop* functions and
 * initialises ENet. Call once from DllMain before the game starts Lua. Returns the number
 * of functions installed. */
int coop_net_install(void);

/* Appends a timestamped line to %JERICHO_COOP_LOG% (no-op when unset). */
void coop_log(const char *fmt, ...);

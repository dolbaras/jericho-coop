#pragma once

/* Installs the JERICHO_WINPOS / JERICHO_ADAPTER hooks (see display_hooks.c). Call from
 * DllMain before the game creates its window. */
void display_hooks_install(void);

/* In background mode, makes DirectInput devices created from this IDirectInput8 report no
 * input while the game window is not in front. */
void display_hooks_wrap_dinput(void *dinput);

/* Turns background mode (keep running unfocused, no input while unfocused) on or off. */
void display_hooks_set_background(int on);

/* 1 while virtual key vk is held and the game window is really in front, else 0. Never
 * reads the keyboard for other windows. */
int display_hooks_key_down(int vk);

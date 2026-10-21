#pragma once
#include <d3d9.h>

/* The last 30 seconds of the game's frames, kept in memory (clip.c). After CreateDevice. */
void clip_on_device(IDirect3DDevice9 *dev);
/* Writes them as an AVI in the co-op folder (in the background): the path, "" if none. */
const char *clip_save(void);

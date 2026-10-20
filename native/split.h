#ifndef SPLIT_H
#define SPLIT_H

#include <d3d9.h>

/* Local split screen in one game: hooks on the game's D3D device (see split.c). */
void split_on_device(IDirect3DDevice9 *dev);
/* Lua (Net.CoopSplit): mode 0 off / 1 top-bottom; returns the camera slot (0 top, 1 bottom)
   the frame being prepared shows. */
int split_set(int mode);

#endif

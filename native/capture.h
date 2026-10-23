#pragma once
#include <d3d9.h>

/* True when JERICHO_RECORD asks for in-game capture (see capture.c). */
int capture_enabled(void);

/* Starts capturing frames presented by this device (hooks IDirect3DDevice9::Present). */
void capture_on_device(IDirect3DDevice9 *dev);
/* Lets go of the device: its kept surface (made again on the next frame). */
void capture_release_device(void);

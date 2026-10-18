#!/bin/sh
# Build the 32-bit dinput8.dll proxy (co-op transport + test hooks) with Zig's clang.
set -e
cd "$(dirname "$0")"
ZIG="${ZIG:-../../../../tools/zig/zig-x86_64-windows-0.16.0/zig.exe}"
ENET="${ENET:-../../../../tools/enet/enet-1.3.18}"
mkdir -p build
"$ZIG" cc -target x86-windows-gnu -O2 -fno-omit-frame-pointer -shared -o build/dinput8.dll \
  -DWIN32 -I"$ENET/include" \
  dinput8_proxy.c coop_net.c display_hooks.c boot_inject.c capture.c dinput8.def \
  "$ENET/callbacks.c" "$ENET/compress.c" "$ENET/host.c" "$ENET/list.c" \
  "$ENET/packet.c" "$ENET/peer.c" "$ENET/protocol.c" "$ENET/win32.c" \
  -luser32 -lkernel32 -lws2_32 -lwinmm

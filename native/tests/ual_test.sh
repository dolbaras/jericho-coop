#!/bin/sh
# Offline check (no game): the mod's import hooks with an Ultimate ASI Loader-like winmm.dll initialised first.
#   ual_fake.c     stand-in for the loader's start-up (patches the exe's kernel32 slots in DllMain, writes the
#                  values it saw back at the exe's first call), built as winmm.dll
#   ual_standin.c  stand-in for the game's exe (imports WINMM before DINPUT8, calls as the game's C runtime does)
#   ual_model.c    the hooks as a model DLL: -DPLAIN = the 0.3.1 way (a plain slot write), else iat_guard.c
# and the real build\dinput8.dll in the same place (its boot line on the command line).
# OLD_DLL=<dinput8.dll of an earlier release>: also runs that one, which is expected to LOSE the boot line.
# Usage: sh native/tests/ual_test.sh   (from anywhere; exit 0 when every check passes)
set -e
cd "$(dirname "$0")"
ZIG="${ZIG:-../../../../../tools/zig/zig-x86_64-windows-0.16.0/zig.exe}"
# (a worktree under work is one level deeper)
[ -x "$ZIG" ] || ZIG="../../../../../../tools/zig/zig-x86_64-windows-0.16.0/zig.exe"
OUT=../build/ualtest
rm -rf "$OUT"
mkdir -p "$OUT"
CC="$ZIG cc -target x86-windows-gnu -O2"
$CC -shared -o "$OUT/winmm.dll" ual_fake.c ual_fake.def
$CC -o "$OUT/standin.exe" ual_standin.c -lwinmm -ldinput8 -Wl,--no-dynamicbase -Wl,--image-base=0x400000
$CC -shared -DPLAIN -o "$OUT/model_plain.dll" ual_model.c ../dinput8.def -lwinmm
$CC -shared -o "$OUT/model_guard.dll" ual_model.c ../iat_guard.c ../dinput8.def -lwinmm
fails=0; checks=0
check() {   # check <name> <condition result 0/1>
    checks=$((checks + 1))
    if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
# run <case> <dinput8.dll> <with the fake loader: 1/0>: <case>/bin/{standin.exe,dinput8.dll[,winmm.dll]}, <case>/coop/boot.lua
run() {
    d="$OUT/$1"
    mkdir -p "$d/bin" "$d/coop"
    cp "$OUT/standin.exe" "$d/bin/"
    cp "$2" "$d/bin/dinput8.dll"
    [ "$3" = 1 ] && cp "$OUT/winmm.dll" "$d/bin/winmm.dll"
    : > "$d/coop/boot.lua"
    : > "$d/log.txt"
    w=$(cd "$d" && pwd -W)
    (cd "$d" && UAL_FAKE_LOG="$w/log.txt" JERICHO_COOP_LOG="$w/coop.log" ./bin/standin.exe > out.txt 2>&1) || true
}
has() { grep -qi -- "$2" "$1" && echo 0 || echo 1; }
hasnt() { grep -qi -- "$2" "$1" && echo 1 || echo 0; }
order() {   # order <log> <first> <then>: line of <first> before the line of <then>
    a=$(grep -n -- "$2" "$1" | head -1 | cut -d: -f1); b=$(grep -n -- "$3" "$1" | head -1 | cut -d: -f1)
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && echo 0 || echo 1
}

run plain-nofake "$OUT/model_plain.dll" 0
check "no loader: the plain hook works (boot line, 8 processors)" $( [ "$(has "$OUT/plain-nofake/out.txt" "InitLuaLine:MARK")$(has "$OUT/plain-nofake/out.txt" "cpus=8")" = 00 ] && echo 0 || echo 1)
run plain-fake "$OUT/model_plain.dll" 1
check "the fake loader's DllMain runs before the mod's (winmm.dll first)" $(order "$OUT/plain-fake/log.txt" "patched (DllMain)" "model (plain)")
check "the fake loader writes its slots back at the exe's first call" $(has "$OUT/plain-fake/log.txt" "written back")
check "pre-fix model (plain slot write): the boot line is LOST" $(hasnt "$OUT/plain-fake/out.txt" "InitLuaLine:MARK")
check "pre-fix model (plain slot write): the 8-processor fix is LOST ($(grep cpus= "$OUT/plain-fake/out.txt"))" $(hasnt "$OUT/plain-fake/out.txt" "cpus=8")
run guard-nofake "$OUT/model_guard.dll" 0
check "no loader: iat_guard hooks, nothing redirected" $( [ "$(has "$OUT/guard-nofake/out.txt" "InitLuaLine:MARK")$(has "$OUT/guard-nofake/out.txt" "cpus=8")$(has "$OUT/guard-nofake/log.txt" "prepatched 0 by -, 0 call")" = 000 ] && echo 0 || echo 1)
run guard-fake "$OUT/model_guard.dll" 1
check "iat_guard with the fake loader first: the boot line stays" $(has "$OUT/guard-fake/out.txt" "InitLuaLine:MARK")
check "iat_guard with the fake loader first: 8 processors stay ($(grep cpus= "$OUT/guard-fake/out.txt"), $(grep mask= "$OUT/guard-fake/out.txt"))" $(has "$OUT/guard-fake/out.txt" "cpus=8")
check "iat_guard names the loader and redirects the exe's calls" $( [ "$(has "$OUT/guard-fake/log.txt" "GetCommandLineA hooked, prepatched 1 by winmm.dll, [1-9]")$(has "$OUT/guard-fake/log.txt" "GetSystemInfo hooked, prepatched 1 by winmm.dll, [1-9]")" = 00 ] && echo 0 || echo 1)
check "the loader still wrote its slots back (it was not stopped)" $(has "$OUT/guard-fake/log.txt" "written back")

DLL=../build/dinput8.dll
if [ -f "$DLL" ]; then
    run mod-nofake "$DLL" 0
    check "the mod's DLL, no loader: boot line on the command line" $(has "$OUT/mod-nofake/out.txt" "InitLuaLine:")
    run mod-fake "$DLL" 1
    check "the mod's DLL with the fake loader first: boot line on the command line" $(has "$OUT/mod-fake/out.txt" "InitLuaLine:")
    check "the mod's log says who hooked GetCommandLineA first" $(has "$OUT/mod-fake/coop.log" "GetCommandLineA was hooked by winmm.dll before the mod")
else
    echo "skip: $DLL not built (sh native/build.sh)"
fi
if [ -n "$OLD_DLL" ]; then
    run old-nofake "$OLD_DLL" 0
    check "OLD_DLL, no loader: boot line on the command line" $(has "$OUT/old-nofake/out.txt" "InitLuaLine:")
    run old-fake "$OLD_DLL" 1
    check "OLD_DLL with the fake loader first: the boot line is LOST (the published behaviour)" $(hasnt "$OUT/old-fake/out.txt" "InitLuaLine:")
fi
echo "ual_test: $((checks - fails))/$checks passed"
[ "$fails" = 0 ]

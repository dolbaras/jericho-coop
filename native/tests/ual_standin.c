/*
 * A stand-in for the game's exe (never the game): imports WINMM.dll before DINPUT8.dll as Jericho.exe and
 * TimeShift.exe do, so a winmm.dll in its folder (ual_fake.c, standing in for Ultimate ASI Loader) is
 * initialised before the dinput8.dll there (the mod's DLL, or ual_model.c). main() then does what the
 * game's C runtime does at its start: GetSystemTimeAsFileTime (the security cookie) and GetStartupInfoA,
 * where the loader writes its slots back, then GetCommandLineA; and GetSystemInfo as TimeShift's engine.
 * Prints:  cmdline=<what GetCommandLineA gave>  cpus=<dwNumberOfProcessors>  mask=<dwActiveProcessorMask>
 * A large zeroed section covers the fixed addresses the mods' DllMain look at (0x401000-0xf00000), so that
 * they read zeros there and change nothing.
 */
#include <windows.h>
#include <stdio.h>
#include <dinput.h>

static char zeros[0xb00000];

int main(void)
{
    volatile char *z = zeros;
    (void)z[0];
    /* (imported, never called: the import alone makes the loader load dinput8.dll) */
    void *volatile di = (void *)DirectInput8Create;
    (void)di;
    (void)timeGetTime();
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    STARTUPINFOA si = {sizeof si};
    GetStartupInfoA(&si);
    const char *cl = GetCommandLineA();
    SYSTEM_INFO s;
    GetSystemInfo(&s);
    printf("cmdline=%s\ncpus=%lu\nmask=%#lx\n", cl ? cl : "(null)", s.dwNumberOfProcessors, (unsigned long)s.dwActiveProcessorMask);
    fflush(stdout);
    return 0;
}

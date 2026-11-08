# Releasing

From 0.2.3 on, players start the game with the "Jericho Co-op+" shortcut, which runs
`coop\coop-launcher.ps1` (`tools/launcher.ps1`). Before the game starts it reads
`https://api.github.com/repos/dolbaras/jericho-coop/releases/latest` and installs that release when
its tag is newer than `coop\version.txt`. Publishing a release therefore updates every player who
uses the shortcut the next time they start the game, so a release must be finished and tested
before it goes up.

What the launcher already out there relies on, so every later release keeps it:

- **Tag** `v<major>.<minor>.<patch>` (parsed as a .NET `[version]`), a full release: drafts and
  pre-releases are not "latest" and are never installed.
- **Asset** named `jericho-coop-<version>.zip` (the first asset matching `jericho-coop-*.zip`),
  attached to that release, so its URL is under
  `https://github.com/dolbaras/jericho-coop/releases/download/`. The launcher checks the download
  against the `sha256:` digest GitHub gives for the asset.
- **`coop-installer.ps1` at the root of the zip** (as `tools/package.ps1` builds it), taking
  `-Game <folder> -AutoClose -NoShortcut`: install into that folder with the window, close it by
  itself after a successful install, exit code 0 on success and non-zero on failure;
  `-NoShortcut` refreshes only the shortcuts the install record lists.
- **`files\coop\version.txt`** holding the version without the `v`.
- **`<game>\coop\install.txt`**, the install record the next installer reads: `version=`,
  then one line per `file=`, `backup=`, `chain=` (the release after 0.3.1: a copy made for the player's ASI loader, also a `file=`), `built=` and
  `shortcut=`. 0.2.3-0.2.4 wrote all
  shortcuts on one `shortcut=` line joined by spaces (or an empty one with none); from 0.2.5
  the installer splits such a line after each `.lnk` and drops empty ones, and keeps doing so.
- **Installs without a record.** 0.1.0 had no installer (its zip was extracted into the game
  folder): from 0.2.6 the installer recognises it by its files (the proxy DLL's
  `coop_net installed`, `coop\coop.lua`, its root texts by their words), updates and removes it,
  and never keeps an older co-op DLL as the game's original. Keep that detection.

A change to any of these needs a launcher that copes with both the old and the new form, shipped
one release before the old form is dropped.

## Other mods' DLLs: an ASI loader as bin\dinput8.dll (the release after 0.3.1)

The mod is `bin\dinput8.dll` too. What the installer does with what it finds in `bin\`:

- **`bin\dinput8.dll` of someone else's** (an ASI loader, any other mod): kept in `coop-backupin\dinput8.dll` once, replaced, put
  back on uninstall (byte for byte). When it is an **Ultimate ASI Loader** (ThirteenAG; 32-bit, exports `IsUltimateASILoader` and
  winmm's `timeGetTime`; the file's export table is read, nothing of it runs) and `bin\winmm.dll` does not exist, a copy of it is made
  as `bin\winmm.dll` and its `bin\dinput8.ini` as `bin\winmm.ini`: a name the loader serves and `Jericho.exe` imports, so Windows loads
  it at the start and it loads its plugins (`bin\scripts`, `bin\plugins`) as before. The record lists the copies as `chain=` and
  `file=` (written before the copies are made); reinstall and update keep them; the uninstaller removes a copy only while it still
  equals its source. Not `dinput8_real.dll` or any other name: the loader picks its role by its own file name and shows "This library
  isn't supported." and closes the game under one it does not know (its source, read for Revelations 2 Co-op 0.2.0, which does the
  same). Any other `dinput8.dll`, a 64-bit loader, or a loader next to a `winmm.dll` of someone else's stays off while co-op is
  installed; the result page says which of the two happened.
- **A `dinput8.dll` another mod put over the co-op one after the install** (the player installed an ASI mod later): an update keeps it
  in `coop-backup` as the original (it replaces an older one there; copies made from that older one are made again from it) and puts
  the co-op DLL back; the uninstaller leaves it in place. Up to 0.3.1 the update overwrote it without a copy and the uninstaller
  deleted it.
- **Other proxy DLLs and plugin folders** (`d3d9.dll` of SMOD's D9VK, DXVK or ReShade, `dsound.dll` + `dsound.ini` of IndirectSound,
  `version.dll`, `xinput1_3.dll`, a `winmm.dll`, `bin\scripts`, `bin\plugins`): not in the payload, never touched.

The DLL's side (native/iat_guard.c): Ultimate ASI Loader (v10.0.2 `source/loader/startup/startup.cpp`, read on GitHub) patches the
exe's kernel32 import slots of about 30 functions in its DllMain, `GetCommandLineA` among them, records the value it saw and writes it
back at the exe's first such call (the C runtime's start), before the C runtime reads the command line. Loaded before the mod's DLL
(as `bin\winmm.dll` always: the mod's DLL imports winmm) it took the `-InitLuaLine` boot line away and co-op never started. The boot
hook now also points the exe's own call of `GetCommandLineA` at the mod's hook when the slot was patched before (only then); the log
says `boot: GetCommandLineA was hooked by <dll> before the mod ...`. Tests: `sh native/tests/ual_test.sh` (a stand-in loader written
from that source as `winmm.dll`, a stand-in exe importing WINMM before DINPUT8 like `Jericho.exe`, a model DLL and the real build;
`OLD_DLL=<an earlier dinput8.dll>` shows that one losing the boot line). NOT checked with the real loader in the game (no
Jericho ASI plugin is known: ThirteenAG's WidescreenFixesPack has none, 2026-11-08).

## Tests

`powershell -NoProfile -ExecutionPolicy Bypass -File tests	est_installer.ps1 [-Zip <release zip>] [-OldZip <release zip>] [-Keep]`
(Windows PowerShell 5.1; everything under `%TEMP%`, stand-in game folders, made-up PE files that are only read; about 2 minutes).
It packages this tree (`tools\package.ps1 -Dist <temp>`) unless `-Zip` is given and checks: the zip's entry names use `/`; an ASI
loader as `bin\dinput8.dll` next to `d3d9` / `dsound` (+ini) / `version` / `xinput1_3` proxies and plugin folders (backup, the
`winmm.dll` + `winmm.ini` copies, the record, the result text, every other file unchanged, reinstall + update keep it all once,
uninstall byte for byte); a copy the player changed stays; no copy next to a foreign `winmm.dll`, for a 64-bit loader, another
mod's DLL, a DLL that only names the loader; a loader without `dinput8.ini`; no `dinput8.dll` at all; another mod's DLL put over the
co-op one, then uninstall / update / update + uninstall, also over an older loader; with `-OldZip` that release over a loader,
updated by this tree's installer; the new texts in six languages, translated; the longest result text fits its page (measured,
no window) and Fit-Result itself on controls of the page's geometry (none shown). 2026-11-08: this tree 53/53 with `-OldZip` 0.3.1; the published 0.3.1 zip (`-Zip`) fails 28 of 49.
The installer's WINDOW (the result page now gives a long text the progress bar's and the log's room, then a smaller font) needs a
person to look at it.

## Bug reports: Collect logs.bat

`package.ps1` puts the bug-report collector every co-op mod of the workspace shares into `files\coop\`:
`collect-logs.ps1` and `log-profiles\*.psd1` from `<workspace>\tools\log-collector` (the script and one profile per game, all
of them, so that `-All` also takes the other co-op mods found on a PC; `-LogCollector <folder>` for a clone placed elsewhere),
and `Collect logs.bat` (`collect-logs.ps1 -Mod jericho`). A double-click puts `jericho-coop-report-<date>-<time>.zip` on the
desktop: `report.txt` (mod version, SHA-256 of `bin\Jericho.exe`, SMOD's `bin\anselintegrationtestapp.exe` and the mod's
`bin\dinput8.dll`, install record summary, Windows and its UI language, graphics adapters and drivers, memory, CPU, display
modes), `logs\coop*.log` (from `Documents\Codemasters\Clive Barker's Jericho\Coop`), `logs\game\log.html` (the engine's log),
`coop\install.txt`, `install-log.txt`, `version.txt`, `launcher-log.txt`, `settings\display.txt`, `video.txt`,
`temp\jericho-coop-install.log`, and `files.txt` (names and sizes of `coop\` without Python, `bin\`, the game folder and the
Documents folder: the saves and F11 clips by name only). Cleaned out: user, computer and domain names, the profile, Documents
and game paths, any `<drive>:\Users\<x>`, the Steam persona name the log quotes (`name [..]`), Steam's account names, Steam IDs, public
IPv4 / IPv6 addresses (LAN kept), e-mails, MACs; nothing is uploaded. The uninstaller removes it with `coop\`. Tests: the
shared `tools\log-collector\tests\test-collect.ps1` (powershell.exe); before a release, once on a real install: double-click
`coop\Collect logs.bat`, open the zip.

## The setup exe (additional release asset)

`jericho-coop-setup-<version>.exe` is a single-file installer for players who do not want to unzip and run `Install Co-op.bat`.
It is an EXTRA asset: the zip stays the asset the launcher updates from (the launcher takes the first asset matching
`jericho-coop-*.zip`, and the exe's name does not match that pattern; keep it so), the zip's layout and the installer's
parameters are unchanged, and the exe's payload is the release zip byte for byte.

```
powershell -File tools\package.ps1 -Version <x.y.z> -Exe        # dist\jericho-coop-<version>.zip + dist\jericho-coop-setup-<version>.exe
```

`-Exe` calls `<workspace>\tools\mkinstaller\mkinstaller.ps1` (game independent: `-Zip -Out -Product -Version [-Description
-Icon | -Accent -TempPrefix -Installer]`; `-Mkinstaller <folder>` for a clone placed elsewhere; `-Dist <folder>` writes
somewhere other than `dist\`, handy for tests because `dist\` holds the published zips; give a full, not an 8.3 short, path).
It builds `tools\mkinstaller\stub.c` with the workspace's zig (`zig cc -target x86-windows-gnu -Os`, windows subsystem, no
console, system bcrypt/shell32 only), embeds the zip as RCDATA 1 and a small config as RCDATA 2 (product, temp prefix, the
installer's name, the zip's SHA-256), our own icon (`make_icon.ps1`: two players and an install arrow in the game's accent
colour, no game art), VERSIONINFO (product, description, versions, no company) and a manifest (asInvoker, DPI aware, supported
OS list, long paths). Right after the build it runs the exe with `--extract` and compares every unpacked file with the zip
(names, sizes, SHA-256).

What the exe does when a player runs it:

1. Checks its payload's SHA-256 (a mismatch: message box "damaged, download again").
2. Unpacks the zip (own inflate, CRC-32 of every file checked, entry names that could leave the folder refused) into a NEW
   folder `%TEMP%\jericho-coop-setup-<8 hex>` (never the current folder; a folder of an earlier killed run older than a day and
   holding the stub's marker file is removed first).
3. Starts `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File <that folder>\coop-installer.ps1 <the
   command line the player gave, unchanged>` (no console window; the 64-bit PowerShell also from the 32-bit stub, through
   Sysnative), with `COOP_SETUP_DIR` = the folder the exe lies in and `COOP_SETUP_FLAG` = a file the installer writes as its
   first act (not in `-Quiet`). The installer reads them: the game is also looked
   for next to the exe, and a failed run whose flag never appeared makes the exe say "the installer window did not start
   (PowerShell blocked?)" with a pointer to the zip.
4. Waits, returns the installer's exit code (0 ok, 1 failed; a window the player closes is 0, as the launcher relies on), and
   deletes the folder (ten tries, an antivirus may hold a file for a moment; junctions are unlinked, never followed).

`-Quiet` keeps its console output: the exe joins the starter's console or hands the redirected std handles on. Every installer
option works as before: `-Game`, `-Uninstall`, `-Quiet`, `-Lang`, `-AutoClose`, `-NoShortcut`, `-ShortcutDir`.
Only the exe's own `--extract <folder>` is extra (unpack only, run nothing; for audits and tests). The installer still copies
`coop-installer.ps1` and writes `Uninstall Co-op.bat` into the game folder, so removal is the same with or without the exe.
Error boxes are in English, Russian, German, French, Spanish and Italian (Windows' UI language).

Honest limits: the exe is NOT code-signed (no certificate), so SmartScreen will probably warn "Windows protected your PC" and
an antivirus may flag a self-extracting program that starts PowerShell; the README texts say so, offer the zip as the
alternative and `--extract` for a look inside. Nothing is done to avoid detection (no packer, no obfuscation, no
signature tricks): signing it later is the only real fix. The unpacked files do not carry the "downloaded from the Internet"
mark, which the zip's would after Explorer's Extract all; the installer is started with `-ExecutionPolicy Bypass` either way,
as `Install Co-op.bat` does. A machine whose policy forbids running scripts stops both ways. The stub's source is in the
workspace (`tools\mkinstaller`), not in this repository yet: publish it with the release if the exe is shipped.

Tests of the exe (workspace `games\jericho\lab\setup_exe_test.ps1 -Exe <exe>`): `--extract`, quiet install / reinstall / uninstall
through the exe on a copy of the clean game (`work\installs`), exit codes, odd paths, no `jericho-coop-setup-*` folder left in
`%TEMP%`; see `notes\installer-exe.md` in the workspace.

Testing an update without GitHub: serve a releases/latest-style JSON and the zip locally and run
`coop-launcher.ps1 -Feed http://127.0.0.1:<port>/latest.json -NoStart` (or set
`JERICHO_COOP_FEED` for a start through the shortcut). New shortcuts go to `-ShortcutDir <folder>`
in tests, never to the desktop. An update test should start from the previous published zip
installed with two shortcut folders (as a normal install's desktop and Start menu), so the
record looks like a player's; then check the record, that both shortcuts were refreshed, and
that uninstalling removes them. Before a release, also run every published version through the new installer
(`lab/oldversions_test.ps1`, plus `-Chain` and `-RemoveOld`): the folder must end equal to
the clean game after removal.

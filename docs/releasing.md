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
  then one line per `file=`, `backup=`, `built=` and `shortcut=`. 0.2.3-0.2.4 wrote all
  shortcuts on one `shortcut=` line joined by spaces (or an empty one with none); from 0.2.5
  the installer splits such a line after each `.lnk` and drops empty ones, and keeps doing so.
- **Installs without a record.** 0.1.0 had no installer (its zip was extracted into the game
  folder): from 0.2.6 the installer recognises it by its files (the proxy DLL's
  `coop_net installed`, `coop\coop.lua`, its root texts by their words), updates and removes it,
  and never keeps an older co-op DLL as the game's original. Keep that detection.

A change to any of these needs a launcher that copes with both the old and the new form, shipped
one release before the old form is dropped.

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

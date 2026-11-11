# Jericho Co-op+

[![Latest release](https://img.shields.io/github/v/release/dolbaras/jericho-coop?label=latest%20release)](https://github.com/dolbaras/jericho-coop/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Online co-op for the whole campaign of **Clive Barker's Jericho** (2007, PC): 2-4 players, each controls their own squad member, over a local network or Steam; also two players on one PC with split screen. The host runs the game world and the story, the others follow it.

More than a co-op mode:
- **The story, extended for co-op.** Where the squad splits, the players who stay behind get content of their own: waves to hold, the soul walk on the Stations of the Path, and the Lost Patrol played as a parallel branch. Players without a body play as Ross's spirit.
- **Settings and fixes for today's PCs.** Aspect ratios up to 21:9 and 32:9 in the game's own option, a borderless window and the refresh rate in the game's Video settings, a 4 GB memory limit instead of 2, gamepad hot-plug, play without a mouse, crash fixes, six languages.
- **Gameplay improvements.** Each player commands their own fire team, breakable objects are shared, and F11 records the last 30 seconds for bug reports.
- **Works with other mods.** SMOD (its rules are kept the same for every player), SMOD Add-ons, "Clive Upscaler's Jericho" (2x textures) and DXVK.

Until 0.2.3 the mod was called "Jericho Co-op". The repository and file names stay the same, so the auto-update keeps working.

## Status

**Version 0.3.3** ([release notes](https://github.com/dolbaras/jericho-coop/releases/latest)): the mod's texts reviewed in all six languages (in Russian the squad's women Church, Cole and Black were spoken of as men in the story texts, French, Spanish and Italian lines got the feminine forms, names follow the game's own spelling, one form of address per language: German "Sie", Spanish "tú"); `coop\Collect logs.bat` now speaks the player's language (16 languages: the game's language from the mod's last log, else Windows'); the setup exe's error messages are in 16 languages. The rest of the mod is unchanged from 0.3.2. The new texts were seen in the running game in Russian (menus, lobby, settings, hints, squad-choice screens) and the collector's window in five languages; German was seen only on a test copy with the Russian edition's font. Nobody outside the lab has played 0.3.3 yet.

How it is tested: the whole campaign runs through level by level with two real games on two PCs (a playthrough bot plays both sides, both branches of the Lost Patrol included), every story split is played with a real host and client, and every in-engine cutscene is compared with the original. Human playthroughs started with 0.2.1 over Steam; people have played missions 1-8 so far. Every player needs the same version of the mod (the lobby says so when they differ).

## What works

✅ checked in the game on test PCs · 🟨 partly checked (the row says what is missing) · ⬜ not tested · — not offered

| Area | Status |
|---|---|
| "Co-op" entry in the main menu: host, join, lobby (character, nickname, Ready, chapter), session settings on their own screen; all players load the level together | ✅ |
| Local network: join from the list or by IP (UDP 28100) | ✅ |
| Steam: no ports or IPs, join friends' games, invites from the lobby (the mod runs as Valve's free sample app "Spacewar", see `docs/steam-notice.txt`) | 🟨 a session between two different networks (relay) and joining from the Steam friends list are not tested |
| Split screen: a second player on one PC with a gamepad, also together with players on other PCs; each half filled by default (Configuration -> Video -> Split screen) | ✅ |
| Each player controls one squad member, the others stay AI; players see each other move, aim, shoot and use their powers, with nameplates | ✅ |
| Fighting and abilities of every squad member shown to the other players (shots, reloads, melee, powers, for human and AI characters) | ✅ not seen in tests: AI Delgado's dragon, a real quick-time event |
| Squad orders per player: each fire team (Alpha, Omega) follows one player; in Act 1 Ross's player leads everyone, as in the original | ✅ |
| Who the players are in the story: the host is Ross's soul, the second player Jones's astral projection; the third and fourth keep their character | ✅ |
| Enemies run by the host, the same on every screen, fighting every player; enemy toughness per player is a session setting | ✅ |
| Breakable and movable objects break and come to rest the same on every screen, also for a player who joins later | ✅ |
| Story triggers, scenes and level changes follow the host; all 33 levels load and end the real way in a row | ✅ |
| A downed player moves to a free squad member or waits for Rawlings' revive | ✅ |
| Cole's and Black's slow motion slows the world for everyone | ✅ |
| First-person cutscenes: the original scene camera for every player; "own eyes" view as an experimental session setting | ✅ |
| Quick-time events: only the player holding the scene's character plays them (or automatic for everyone); cutscene skip is unanimous | ✅ |
| Story splits: players choose to follow or stay; the ones who stay get their own content; the Lost Patrol as a parallel branch | ✅ |
| Players without a body fly as Ross's spirit, can mark enemies and take a free body | ✅ |
| Co-op save apart from the single-player profile: checkpoints, Continue, unlocked chapters | ✅ |
| Screen: Auto, 4:3, 5:4, 16:10, 16:9, 21:9, 32:9; full screen, window or borderless window; refresh rate | ✅ |
| SMOD detected; a session plays by the host's SMOD values when every player has it | ✅ |
| F11 saves the last 30 seconds as a video for bug reports | ✅ |
| Installer, uninstaller and the self-updating "Jericho Co-op+" shortcut (SHA-256 checked) | ✅ |
| Played through by people | 🟨 missions 1-8 so far |

## Download and install

1. Download from [Releases](https://github.com/dolbaras/jericho-coop/releases/latest): `jericho-coop-setup-<version>.exe` (one file, nothing to extract) or `jericho-coop-<version>.zip` (extract it anywhere and run `Install Co-op.bat`; the same installer).
2. The installer finds the game (its folder, the registry, GOG and Steam libraries, or asks), keeps a copy of every file it replaces in `coop-backup`, updates an older version in place and can uninstall. It follows Windows' language (six languages, or pick one in its list).
3. Start the game with the "Jericho Co-op+" shortcut (desktop and Start menu): before the game starts it installs a newer release from GitHub by itself (the download is checked against the SHA-256 GitHub gives for it); offline the game starts as it is. The main menu has a "Co-op" entry. (Installs older than 0.2.3 have no such shortcut: run the new installer once.)

The setup exe is not code-signed, so Windows SmartScreen may warn ("More info" -> "Run anyway"); the zip with `Install Co-op.bat` does the same. To remove the mod run `Uninstall Co-op.bat` in the game folder: it puts every replaced file back. Details, network ports and the FAQ are in `README-COOP.txt` inside the zip (English and Russian; source `docs/release-readme.txt`).

## Requirements

- Your own copy of the game. Tested: the retail DVD release (`Jericho.exe` SHA-256 `7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62`) on Windows 10 and 11; other versions are untested. The installer only sets the retail exe's large-address-aware flag (4 GB of memory; the original is kept and put back on uninstall) and builds `Pack1.packed` from your own game files.
- Every player needs the same version of the mod.
- Local network: UDP 28100 (game) and UDP 28199 (finding games); allow the game in Windows Firewall. Over the internet the host forwards UDP 28100, or the players use a virtual LAN. Steam: no ports; Steam running on every PC, the players are Steam friends.
- Split screen: a gamepad for the second player.

## How to play

- **Host:** Co-op -> Host game -> pick a chapter (or Continue) -> Create session; the "Network" row picks local network or Steam. In the lobby everyone picks a character and a nickname and presses Ready; the host presses Start. Session settings (host): difficulty, enemy toughness, who does character-only actions, QTEs, the damage AI squadmates take, the cutscene view.
- **Join over the local network:** Co-op -> Join (local network) -> pick a game from the list or type the host's IP -> Connect.
- **Join through Steam:** Co-op -> Join through Steam lists your friends' games; or accept the host's invite while your game is on that screen.
- **Split screen:** in the lobby pick "Player 2 (gamepad)" and their character; it works in a hosted game and when you join one (up to 4 players in a session).

### Controls

| Key / setting | What it does |
|---|---|
| Hold T | puts you next to the host's character when the story has cut you off from the squad |
| F11 | saves the last 30 seconds as a video (`clip-<date>-<time>.avi` in the mod's `Coop` folder) |
| Gamepads in split screen | two connected: player 1 uses the first (and keyboard + mouse), player 2 the second; one connected: it is player 2's |
| Configuration -> Video -> Split screen | Fill (default), Fill (closer) or Whole picture for each half |

## Languages

- **In the game:** the mod's menus and hints follow the game's language: English, Russian, German, French, Spanish and Italian, also when it is changed mid-level; each player sees them in their own game's language. With SMOD the game is English: SMOD sets `SelectedLanguage = "English"` in its `autoexec.lua`; write `"German"`, `"French"`, `"Italian"` or `"Spanish"` there to play in that language.
- **Installer and the shortcut's update window:** the same six languages, following Windows' language (the installer also has a list).
- **Setup exe** (its few error messages) and **`coop\Collect logs.bat`**: 16 languages (English, Russian, German, French, Spanish, Italian, Polish, Czech, Hungarian, Portuguese, Brazilian Portuguese, Dutch, Japanese, Korean, Simplified and Traditional Chinese). The setup exe follows Windows' language; the log collector speaks the game's language from the mod's last log, else Windows'.

## Known limits / not verified

- Not tested: a Steam session between two different networks (relay) and joining from the Steam friends list.
- Nobody outside the lab has played 0.3.3 yet; people have played missions 1-8 so far. Story scripts that assume one player are fixed per level as playtesting finds them (`docs/usrentity-audit.md`).
- Split screen: each view runs at half the frame rate (the engine draws one player's view per frame); Delgado's fire barrier flames are not shown (the barrier itself works). A rare split-screen flicker was reported once and could not be reproduced: an F11 clip of it would help.
- Another mod's `bin\dinput8.dll` (an ASI loader such as Ultimate ASI Loader) is kept in `coop-backup` and is off while co-op is installed; it cannot run under another name for Jericho (Windows' compatibility settings for `Jericho.exe` load the system `winmm.dll` first).
- The setup exe is not code-signed (see above).

## Reporting a bug

Open an [issue](https://github.com/dolbaras/jericho-coop/issues/new/choose) (a form asks for the version, the game edition, other mods, what you were doing and what happened: on which level, host or client). Double-click `coop\Collect logs.bat` in the game folder right after the problem: it puts one zip on your desktop with the mod's logs, the install record and a system summary, with your user, computer and player names, Steam names and IDs, paths, e-mail, MAC and public IP addresses removed. Nothing is uploaded; open the zip to check it before you attach it. The logs are those of the last five runs (`Documents\Codemasters\Clive Barker's Jericho\Coop\coop.log` and the four before it) and the game's `log.html`; its window speaks your language. A zip from the host AND from a client of the same session helps most, and an F11 clip too.

## For developers

- `native/` builds `dinput8.dll`, placed next to `bin\Jericho.exe`. It forwards DirectInput, starts the mod's Lua on every level (`-InitLuaLine` boot line), adds `Net.Coop*` Lua functions on top of ENet (UDP), Steam networking (`steam_net.c`), split screen (`split.c`), display mode and refresh rate (`display_hooks.c`), F11 clips (`clip.c`) and test helpers. The exe on disk keeps its code: the installer only sets the large-address-aware flag; in memory, on the retail exe only, one engine call is redirected and one engine read is caught; the rest goes through import tables, Direct3D's and DirectInput's vtables and the game's own Lua.
- `lua/` is the mod itself, run by the game's own Lua 5.1 (session and puppets `coop.lua`, menus and lobby `coop_menu.lua`, enemies `coop_enemies.lua`, scenes `coop_scenes.lua`, story `coop_story.lua` / `coop_splits.lua`, split screen `coop_split.lua`, SMOD `coop_smod.lua`, texts `lang_*.lua`, ...); the module list and how the parts fit together: `docs/architecture.md`.
- `tools/` installer, launcher, packaging and test runners; `tests/` the installer's and texts' tests; `docs/` the campaign, enemies, cutscenes and co-op UX research, `docs/story/` the co-op story decisions, `docs/releasing.md` what the auto-update needs from every release, `docs/translation-style.md` the style each language keeps.
- Build: `sh native/build.sh` (Zig, path in `ZIG`; the ENet 1.3.18 sources are downloaded separately, path in `ENET`), then `powershell tools/install.ps1 -Game <game dir>` copies the DLL and the Lua files into the game (`-Anims` also builds `Pack1.packed`, needs Python 3). `tools/package.ps1 -Version <v>` builds the release zip (`-Exe` also the setup exe, from `tools/mkinstaller`).
- Tests: `lua/tests/*_mock_test.lua` (the Lua modules against a mock of the engine, Lua 5.1; `lang_mock_test.lua` checks every text in the six languages), `tests/test_texts.ps1`, `tests/test_installer.ps1`; `tools/run_bot.ps1`, `tools/run_pair.ps1`, `tools/run_single.ps1` for live runs (they expect the workspace layout of `tools/paths.ps1`).

## Credits and third-party

- ENet 1.3.18 (MIT): the DLL is built with it; notice in `docs/enet-license.txt`, shipped as `ENET-LICENSE.txt`.
- `steam_api.dll` from Steamworks.NET (Standalone 2025.164.1, Windows-x86) for the Steam network path; Steamworks is Valve's, Steamworks.NET is MIT licensed (`docs/steam-notice.txt`, shipped as `STEAM-NOTICE.txt`).
- Python 3.12.10's embeddable build from python.org (PSF License, `coop\python\LICENSE.txt`) runs the installer's animation build.
- Parts of 0.2.1 (Steam networking, shared QTEs and more) came from MAK-PIVO's fork (MIT), no longer public.
- Compatibility with SMOD (SkacikPL) and SMOD Add-ons (PHM2D): their authors allowed it; this repository contains no file of theirs.

## License

MIT (see `LICENSE`). No game files are in this repository or in the releases; you need your own copy of the game. No assets or decompiled game scripts are included either, and the game's copy protection is not touched. Clive Barker's Jericho is a trademark of its owners; this project is not affiliated with them.

## По-русски

Jericho Co-op+ — кооператив для всей кампании Clive Barker's Jericho (2007, PC): 2-4 игрока по локальной сети или через Steam, а также двое на одном ПК с разделённым экраном. Скачайте `jericho-coop-setup-<версия>.exe` или zip со страницы [выпусков](https://github.com/dolbaras/jericho-coop/releases/latest) и запустите установщик; дальше запускайте игру ярлыком «Jericho Co-op+»: он сам ставит новые версии. Меню и подсказки мода — на языке игры (шесть языков), `coop\Collect logs.bat` для отчёта об ошибке говорит на языке игрока. Подробности на русском — в `README-COOP.txt` в архиве и в описании каждого выпуска.

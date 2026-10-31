# Jericho Co-op+

Online co-op (2-4 players) for **Clive Barker's Jericho** (2007, PC). Each player controls a
squad member; the host runs the game world and the story, clients follow it.

More than a co-op mode:
- **The story, extended for co-op.** Where the squad splits, the players who stay behind get
  content of their own: waves to hold, the soul walk on the Stations of the Path, and the
  Lost Patrol played as a parallel branch. Players without a body play as Ross's spirit.
- **Settings and fixes for today's PCs.** Aspect ratios up to 21:9 and 32:9 in the game's own
  option, a borderless window and the refresh rate in the game's Video settings, a 4 GB memory
  limit instead of 2, gamepad hot-plug, play without a mouse, crash fixes, six languages.
- **Gameplay improvements.** Each player commands their own fire team, breakable objects are
  shared, and F11 records the last 30 seconds for bug reports.
- **Works with other mods.** SMOD (its rules are kept the same for every player), "Clive
  Upscaler's Jericho" (2x textures) and DXVK; Steam or a local network.

Until 0.2.3 the mod was called "Jericho Co-op". The repository and file names stay the same,
so the auto-update keeps working.

Status: **0.2.9**: movement of other players' characters and enemies on the joining PC is smoother (a measured path through the host's states instead of 20 Hz steps), enemy fire now reaches a joining player (flames, missiles, melee blows, bosses' attacks), the squad choice screen is at every story split (Act 1, Brandenburg with its after-choice effects checked in the game, the pillboxes, the abyss, the final; also on split screen), squad bodies are solid, doors and invisible blockers are the same on every PC, the "puppet flies / stuck / snaps" storm is fixed, more ally animations are shown (cover, dazed, trance, possession, the dragon arm) and the spectator camera keeps clear of walls and reads A / D and the mouse; the last five logs are kept (`coop.1.log` ... `coop.4.log`). Still open: a few attacks and boss fights were not seen in a real fight (full list in the release notes); the installer updates every earlier version, 0.1.0 included (see [Releases](https://github.com/dolbaras/jericho-coop/releases/latest)). Each fix was run in the game, mostly on two PCs, the exceptions are named in the release notes; the
complete regression (the whole campaign, every split, every older version through the installer) was run on the final code: passed (33 of 33 levels, every split, the Lost Patrol, every older version updated and removed); not run: a real Steam session; by people, missions 1-8 so far.
Download `jericho-coop-setup-<version>.exe` and run it (one file, nothing to extract; it is not
code-signed, so Windows SmartScreen may warn: "More info" -> "Run anyway"), or download
`jericho-coop-<version>.zip`, extract it anywhere and run `Install Co-op.bat` (the same installer): it
finds the game, keeps a copy of every file it replaces, updates an older version in place and can
uninstall. From 0.2.3 the installer's shortcut ("Jericho Co-op+", desktop and Start menu) checks
GitHub before each start and installs a newer release by itself (`docs/releasing.md`).
Details, network ports and how to report a bug are in `README-COOP.txt` inside the zip
(English and Russian). Every player needs the same mod version (the lobby says so).

QA level: the whole campaign runs through level by level in tests with two real game
instances on two PCs (a playthrough bot plays both sides, both branches of the Lost Patrol
included), every story split is played with a real host and client, every in-engine cutscene
is compared with the original. Human playthroughs started with 0.2.1 over Steam; please report
problems in Issues with `Documents\Codemasters\Clive Barker's Jericho\Coop\coop.log` (the four sessions before it are
`coop.1.log` ... `coop.4.log`; and an F11 clip if you can).

Tested game: retail DVD release, `Jericho.exe` SHA-256
`7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62`, Windows 10 and 11; SMOD
(SkacikPL's pack), "SMOD Add-ons" (PHM2D, on top of SMOD) and "Clive Upscaler's Jericho" (2x textures) on top of it.

### What works (each checked in a test run)

- Main menu "Co-op" entry: host, join, lobby with character, nickname, ready and chapter,
  session settings on their own screen; all players load the level together.
- Network, chosen when creating the game: local network (join from the list or by IP, UDP
  28100) or Steam (no ports or IPs: join friends' games, invites from the lobby; the mod runs
  as Valve's free sample app "Spacewar", see `docs/steam-notice.txt`).
- Two players on one PC: split screen with a gamepad for the second player
  (`coop_split.lua`, `native/split.c`), also together with players on other PCs. While the
  second player waits for a body (none free yet, down with nobody to revive them) the first
  gets the whole screen and each gamepad still drives only its own player; the halves come
  back as soon as a body is free.
- Six languages: the mod's menus, hints and the installer follow the game's language
  (English, Russian, German, French, Spanish, Italian), also when it is changed mid-level.
- Each player controls one squad member; the others stay AI. Players see each other move,
  aim, shoot and use their powers, with nameplates (can be turned off).
- Squad orders per player: each fire team (Alpha, Omega) follows one player; in Act 1 Ross's
  player leads everyone, as in the original (`coop_squad.lua`).
- Who the players are in the story (`coop_souls.lua`, `docs/story/player-souls.md`): the host
  is Ross's soul and the second player Jones's astral projection, both switching bodies freely
  after Ross's death; the third and fourth keep their character (greyed out in their squad
  menu) and move only when they must; the projection is cut while Jones is held.
- Enemies are run by the host and are the same on every screen; they fight every player;
  hits from clients reach the host. Enemy toughness per player is a session setting.
- Breakable and movable objects (crates, barrels, furniture) break and come to rest the same
  on every screen, also for a player who joins later (`coop_world.lua`).
- Story triggers, scenes and level changes follow the host; a scene waits until every
  player has loaded the level. All 33 levels load and end the real way in a row. A player
  cut off from the squad by the story can hold T to be put next to the host's character.
- A downed player moves to a free squad member (during a story split only one on their own
  side) or waits for Rawlings' revive, which works for all players. A wait ends when Rawlings
  can no longer come (down herself, taken by the story, held by the last boss's rune, on the
  other side of a split); bodies the rune holds are not free, so the game ends there as in
  the original when every player is down.
- Cole's and Black's slow motion slows the world for everyone; human players keep their
  normal speed, as the power's owner does in the original.
- First-person cutscenes: every player sees the original scene camera with a caption naming
  the scene's character; the session setting "Cutscenes: own eyes (experimental)" shows each
  player the scene from their own character instead (head camera, retargeted full-body copy).
- QTEs: only the player holding the scene's character plays them (or automatic for everyone,
  a session setting); the outcome is the same on every machine. Cutscene skip is unanimous.
- Character-only objects (Church's abyss, ...): the players are asked to take that character;
  otherwise the AI does it (lobby option: players first / players only / AI at once).
- Players without a body (more players than bodies, story splits) fly as Ross's spirit near
  the squad, can mark enemies and take a free body.
- Story splits (`docs/coop-story-extensions.md`): where the squad splits, players choose to
  follow the character who goes on or stay; the ones who stay get their own content (waves,
  holding a position, a soul walk on the Stations of the Path).
- The Lost Patrol: players who choose it play the trio (Jones, Cole, Rawlings) in their own
  instance of the session through the river, the catacombs and the chapel while the main
  group goes on, and meet the others again in the chapel.
- Co-op save, apart from the single-player profile (`Documents\...\Coop`): checkpoints,
  "Continue" and unlocked chapters; clients load the host's exact state.
- Session settings (host): difficulty, enemy toughness, character-only actions, QTEs, AI
  squadmates' damage, cutscene view. SMOD is detected; the session plays by the host's SMOD
  values when every player has it, and its jump is replicated (`coop_smod.lua`).
- Screen: the game's Video settings have Auto, 4:3, 5:4, 16:10, 16:9, 21:9 and 32:9 aspect
  ratios, a display mode (full screen, window, borderless window over the monitor) and the
  refresh rate (`coop.lua` `Coop.installDisplayMenu`, `display_hooks.c`).
- Lobby: the picked character's picture (the game's own squad art); the main menu shows the
  mod's name and version for a few seconds, mirrored to SMOD's label (top left on 4:3 and 5:4
  screens; after the game's "Press [ENTER] or START" line, never over it).
- F11 saves the last 30 seconds as a video for bug reports (`native/clip.c`).
- Installer (`tools/installer.ps1`): finds the game (its folder, registry, GOG, Steam
  libraries or asks), six languages, backup and uninstall, the "Jericho Co-op+" shortcut with
  the game's icon and a co-op badge; the launcher (`tools/launcher.ps1`) updates from GitHub
  releases (SHA-256 checked) before starting the game.

### Next

Fixes from human playthroughs (please report in Issues); per-level fixes for story scripts
that assume one player (`docs/usrentity-audit.md`) as playtesting finds them. Not yet tested:
a Steam session between two different networks (relay) and joining from the Steam friends list.
A rare split-screen flicker was reported once and could not be reproduced: an F11 clip of it
would help.

## How it works

- `native/` builds `dinput8.dll`, placed next to `bin\Jericho.exe`. It forwards DirectInput,
  starts the mod's Lua on every level (`-InitLuaLine` boot line), adds `Net.Coop*` Lua
  functions on top of ENet (UDP), and has test helpers (window placement, render adapter,
  running unfocused without reading the user's input), Steam networking (`steam_net.c`),
  split screen (`split.c`), display mode and refresh rate (`display_hooks.c`) and F11 clips (`clip.c`).
  The exe on disk keeps its code: the installer only sets the retail exe's large-address-aware
  flag (4 GB of memory; the original is kept and put back on uninstall). In memory, on the
  retail exe only, one engine call is redirected (a user lookup without a bounds check that
  crashed split screen, `split.c`) and one engine read is caught (the last boss's fire spirit
  with nobody left to chase, `dinput8_proxy.c`); the rest goes through import tables,
  Direct3D's and DirectInput's vtables and the game's own Lua. On a PC without a mouse the
  game gets one that never moves (it would refuse to start, `display_hooks.c`). Paths are read
  as Unicode, so a game folder named outside Windows' code page works too.
- `lua/` is the mod itself, run by the game's own Lua 5.1:
  - `boot.lua`, `coop.lua`: session, squad ownership, player state at 20 Hz, puppets
  - `coop_menu.lua`: "Co-op" main menu entry, host/join, lobby (character, nickname,
    ready, chapter); `lang_*.lua`: German, French, Spanish, Italian texts
  - `coop_enemies.lua`: host-authoritative enemies, damage, story triggers, scenes, levels
  - `coop_team.lua`: downed players, Rawlings revives, game over, shared slow motion
  - `coop_scenes.lua`: cutscenes (original camera for everyone; own-character view as an
    experiment), QTE routing
  - `coop_world.lua`: map callbacks (doors, levers, story steps) replicated to clients
  - `coop_claim.lua`: character-only actions offered to the players, AI fallback
  - `coop_spirit.lua`: spirit role for players without a body
  - `coop_save.lua`: co-op save and checkpoints, profile protection
  - `coop_session.lua`: pause menu and leaving a session
  - `coop_story.lua`, `coop_splits.lua`: story steps for several players, the story splits
  - `coop_inst.lua`, `coop_patrol.lua`: side instances in one session, the Lost Patrol
  - `coop_hud.lua`: nameplates, hints
  - `coop_squad.lua`: squad orders per player (fire team leaders)
  - `coop_souls.lua`: who the players are (Ross's soul, Jones's projection, the squad)
  - `coop_powers.lua`, `coop_ross.lua`: the squad's powers for the others, Act 1's Ross
  - `coop_split.lua`: split screen (second player on one PC)
  - `coop_smod.lua`: SMOD detection, one set of rules per session (the host's SMOD values or the game's), its jump for the others, SMOD texts in Russian
  - `dev.lua`: test bots and experiments (loaded only with `dev=true`)
- `docs/architecture.md`: how the parts fit together (load order, frame loop, network
  messages, authority, native hooks) and where to start for common changes.
- `docs/`: analysis of the campaign, enemies and triggers, cutscenes, co-op UX research;
  `docs/story/` the co-op story decisions (splits, player souls); `docs/releasing.md` what
  the auto-update needs from every release.

## Build and install

Players: use the release zip. From the sources:

```
sh native/build.sh                         # needs Zig (see ../../../tools/zig)
powershell tools/install.ps1 -Game <game dir>
```

`install.ps1` copies `dinput8.dll` to `<game dir>\bin` (backing up a foreign one) and the
Lua files to `<game dir>\coop\`. Then start the game normally: the main menu has a
"Co-op" entry. `-Anims` also builds `Pack1.packed` from the game's own archives (needs
Python 3): retargeted scene animations, used only by the experimental own-character
cutscene view. `tools/package.ps1 -Version <v>` builds the release zip in `dist\`
(players' installer: `tools/installer.ps1`).

## Tests

- `tools/run_bot.ps1`: one game instance as host + `tools/bot/coop_bot.py` (headless client).
- `tools/run_pair.ps1`: two game instances (second one on another GPU/monitor).
- `tools/run_single.ps1`: one instance with screenshots; `tools/record.ps1` and
  `tools/sheet.ps1`: video recording and contact sheets. Environment switches for test runs:
  `JERICHO_TEST_NOMOUSE=1` (DirectInput's mouse fails, as on a PC without one).
- `lua/tests/*_mock_test.lua`: the Lua modules against a mock of the engine (run from `lua/`
  with Lua 5.1); the mock errors on reads of write-only engine fields.

The scripts expect the workspace layout described in `tools/paths.ps1` (the private
`../work` folder holds the test copy of the game and run logs).

## Not included

No game files, assets or decompiled game scripts are in this repository. You need your
own copy of the game. Its copy protection is not touched.

## License

MIT (see `LICENSE`). The DLL is built against ENet 1.3.18 (MIT), downloaded separately; the
Steam path loads `steam_api.dll` from Steamworks.NET (`docs/steam-notice.txt`). Credit: parts
of 0.2.1 (Steam networking, shared QTEs and more) came from MAK-PIVO's fork (MIT), no longer
public. Compatibility with SMOD (SkacikPL) and SMOD Add-ons (PHM2D): their authors allowed it
(relayed 2026-10-31); this repository contains no file of theirs.

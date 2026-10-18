# Jericho Co-op

Online co-op (2-4 players) for **Clive Barker's Jericho** (2007, PC). Each player controls a
squad member; the host runs the game world and the story, clients follow it.

Status: work in progress, not released. QA level: automated tests with two real game
instances and a headless bot (see `tools/`), no full playthrough yet.

Tested game: retail DVD release, `Jericho.exe` SHA-256
`7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62`, Windows 11.

### What works (each checked in a test run)

- Main menu "Co-op" entry: host, join by IP, lobby with character, nickname, ready and
  chapter; all players load the level together. Menu text follows the game language
  (Russian, English).
- Each player controls one squad member; the others stay AI. Players see each other move,
  aim and shoot, with nameplates (can be turned off).
- Enemies are run by the host and mirrored on clients; hits from clients reach the host.
- Story triggers, scenes and level changes follow the host.
- A downed player moves to a free squad member; Rawlings' revive works for all players.
- Cole's and Black's slow motion slows the world for everyone; human players keep their
  normal speed, as the power's owner does in the original.
- First-person cutscenes: each player watches from their own character's head, looking at
  what the original scene camera looks at (checked on video in the first palace scene).

### Not done yet

QTE routing, Act 1 seats (Ross), a separate co-op save, difficulty scaling, character
portraits in the lobby, enemy AI targeting remote players, content for players whose
character is away in solo sections. See `docs/scenes-catalog.md`.

## How it works

- `native/` builds `dinput8.dll`, placed next to `bin\Jericho.exe`. It forwards DirectInput,
  starts the mod's Lua on every level (`-InitLuaLine` boot line), adds `Net.Coop*` Lua
  functions on top of ENet (UDP), and has test helpers (window placement, render adapter,
  running unfocused without reading the user's input). The game's exe is never modified.
- `lua/` is the mod itself, run by the game's own Lua 5.1:
  - `boot.lua`, `coop.lua`: session, squad ownership, player state at 20 Hz, puppets
  - `coop_menu.lua`: "Co-op" main menu entry, host/join, lobby (character, nickname,
    ready, chapter); Russian/English from the game's language
  - `coop_enemies.lua`: host-authoritative enemies, damage, story triggers, scenes, levels
  - `coop_team.lua`: downed players, Rawlings revives, game over, shared slow motion
  - `coop_scenes.lua`: cutscenes from each player's own character
  - `coop_hud.lua`: nameplates
  - `dev.lua`: test bots and experiments (loaded only with `dev=true`)
- `docs/`: analysis of the campaign, enemies and triggers, cutscenes, co-op UX research.

## Build and install

```
sh native/build.sh                         # needs Zig (see ../../../tools/zig)
powershell tools/install.ps1 -Game <game dir>
```

`install.ps1` copies `dinput8.dll` to `<game dir>\bin` (backing up a foreign one) and the
Lua files to `<game dir>\coop\`. Then start the game normally: the main menu has a
"Co-op" entry.

## Tests

- `tools/run_bot.ps1`: one game instance as host + `tools/bot/coop_bot.py` (headless client).
- `tools/run_pair.ps1`: two game instances (second one on another GPU/monitor).
- `tools/run_single.ps1`: one instance with screenshots; `tools/record.ps1` and
  `tools/sheet.ps1`: video recording and contact sheets.

The scripts expect the workspace layout described in `tools/paths.ps1` (the private
`../work` folder holds the test copy of the game and run logs).

## Not included

No game files, assets or decompiled game scripts are in this repository. You need your
own copy of the game. The game's exe is not modified and its copy protection is not
touched.

## License

MIT (see `LICENSE`). The DLL is built against ENet 1.3.18 (MIT), downloaded separately.

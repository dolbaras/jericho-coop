# Jericho Co-op

Online co-op (2-4 players) for **Clive Barker's Jericho** (2007, PC). Each player controls a
squad member; the host runs the game world and the story, clients follow it.

Status: work in progress, not released. QA level: automated tests with two real game
instances and a headless bot (see `tools/`), no full playthrough yet.

Tested game: retail DVD release, `Jericho.exe` SHA-256
`7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62`, Windows 11.

### What works (each checked in a test run)

- Main menu "Co-op" entry: host, join by IP or from the list of games on the local network,
  lobby with character, nickname, ready and chapter; all players load the level together.
  Menu text follows the game language (Russian, English).
- Each player controls one squad member; the others stay AI. Players see each other move,
  aim and shoot, with nameplates (can be turned off).
- Enemies are run by the host and mirrored on clients; hits from clients reach the host.
- Story triggers, scenes and level changes follow the host; a scene waits until every
  player has loaded the level.
- A downed player moves to a free squad member; Rawlings' revive works for all players.
- Cole's and Black's slow motion slows the world for everyone; human players keep their
  normal speed, as the power's owner does in the original.
- First-person cutscenes: each player watches from their own character's head, looking at
  what the original scene camera looks at. The first-person character is shown to the
  others with its full body, playing the scene's own motion (retargeted animations).
- QTEs: only the player holding the scene's character sees and plays them; the branch they
  take (success, fail, retry) is the same on every machine.
- Character-only objects (checked on the abyss of Rom_Palace_01, which only Church can
  use): the players are asked to take that character; if nobody does within 30 s the AI
  does it (lobby option: players first / players only / AI at once).
- Players without a body (more players than bodies, story splits) fly as Ross's spirit
  near the squad, can mark enemies and take a free body.
- Co-op save, apart from the single-player profile: checkpoints and level starts are saved
  to `Documents\Codemasters\Clive Barker's Jericho\Coop`; "Continue" in the host menu;
  the single-player profile is never written during a session. Clients load the host's
  exact state on every restart and checkpoint.

### Written, not yet tested in game

- Pause menu that does not pause the world; clients cannot restart levels.
- Leaving: a client whose host leaves is told so and goes back to the main menu.
- Unanimous cutscene skip (every player presses Esc).
- Lobby difficulty (vanilla Easy/Normal/Hard) and enemy toughness per player
  (off / light +15% / full +30% health per extra player).
- Act 1: the host plays Ross; from WWII on the host takes their lobby character
  (Delgado by default, as in the story).

### Not done yet

Character portraits in the lobby, story content for players whose character is away in
solo sections (planned in `docs/coop-story-extensions.md`), per-level fixes for story
scripts that assume one player (`docs/usrentity-audit.md`), a full campaign playthrough.

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
  - `coop_scenes.lua`: cutscenes from each player's own character, QTE routing, full-body
    stand-ins for first-person characters
  - `coop_world.lua`: map callbacks (doors, levers, story steps) replicated to clients
  - `coop_claim.lua`: character-only actions offered to the players, AI fallback
  - `coop_spirit.lua`: spirit role for players without a body
  - `coop_save.lua`: co-op save and checkpoints, profile protection
  - `coop_session.lua`: pause menu and leaving a session
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

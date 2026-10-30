# Architecture of Jericho Co-op+ (0.2.8)

A map of the code for a developer who comes back to it: how the mod starts, what runs every
frame, what goes over the network and who decides what. It describes the code as built; the
design and research behind it are in the other documents:

- [README](../README.md): features, build, install, tests.
- [releasing.md](releasing.md): what the auto-update needs from every release.
- [enemies-and-triggers.md](enemies-and-triggers.md), [usrentity-audit.md](usrentity-audit.md),
  [scenes-catalog.md](scenes-catalog.md), [campaign-structure.md](campaign-structure.md): the
  game's own scripts (sections proposing messages there are designs; section 4 below is the
  real list).
- [splitscreen-research.md](splitscreen-research.md), [scrapland-engine-audit.md](scrapland-engine-audit.md):
  the engine's split screen remnants, users, FP models.
- [coop-story-extensions.md](coop-story-extensions.md), [story/](story/): the story splits and
  player souls.

References are `file:function` or `file:line` (line numbers of 0.2.7).

## 1. Boot and load order

### 1.1 The DLL

`native/` builds `dinput8.dll`, put next to `bin\Jericho.exe`. `DllMain`
(`dinput8_proxy.c`) runs, in this order:

1. `load_real_dinput8`: the system `dinput8.dll`; the export `DirectInput8Create` forwards to it
   and wraps every `IDirectInput8` it returns (`display_hooks_wrap_dinput`).
2. `coop_net_install` (`coop_net.c`): rewrites 19 unused entries of the engine's `Net`
   `luaL_Reg` table (at `0x72e4f8`, 24 entries) to the `Net.Coop*` functions, starts ENet.
   This happens before the game creates its Lua state, so the functions exist in every state.
3. `display_hooks_install` (`display_hooks.c`): import table hooks (window, focus, keyboard,
   XInput, `Direct3DCreate9`).
4. `boot_inject_install` (`boot_inject.c`): finds `<game>\coop\` (or `%JERICHO_COOP_DIR%`) and,
   if `coop\boot.lua` exists and the command line has no `-InitLuaLine`, hooks the exe's
   `GetCommandLineA` import to append `-InitLuaLine:"assert(loadstring(Net['CoopBoot']()))()"`.
   The line is short and path-free on purpose: the engine's parser fails on long text after a
   `.`, and the default folder name has a quote (`boot_inject.c:277-281`).
5. Test-only patches (`JERICHO_MULTI`, `JERICHO_STACKDUMP`, `JERICHO_TEST_ABABANILI`) and the
   vectored exception handler `engine_fixes` (section 7).

### 1.2 From the boot line to the modules

The engine runs `InitLuaLine` once after `Scripts/init.lua` and then clears it; its Lua state is
rebuilt on every level load (`boot.lua:1-4`). The chain:

1. `Net.CoopBoot()` (`coop_net.c:l_boot`) returns
   `COOP_DIR='<dir>/' COOP_CFG=<%JERICHO_COOP_CFG% or {}> dofile(COOP_DIR..'boot.lua')`.
2. `boot.lua` defines `COOP_SERIALIZE` and `COOP_BOOT_LINE()` (the same chunk built from the
   current `COOP_CFG`) and runs `coop.lua` under `pcall`.
3. `coop.lua` defines `Coop`, then at its end (`coop.lua:2052-2181`) loads the rest:

| Order | File | When |
|---|---|---|
| 1 | `Game.UsrEntity` guard (inline) | always (see 8) |
| 2 | `coop_inst.lua` | always, first: it wraps `Net.CoopSend/Recv/Status` |
| 3 | `coop_save.lua` | always (its `sv` message arrives in the menu level too) |
| - | network start | `cfg.auto` tests: `Net.CoopHost`/`CoopJoin`/`CoopSteam`; back in the menu after a session: `Net.CoopClose`, `CoopSave.endSession`, session keys cleared |
| 4 | `coop_menu.lua` | menu level, not `cfg.auto` |
| 5 | `Coop.installFP` | levels, in a session |
| 6 | `coop_enemies.lua`, `coop_hud.lua`, `coop_team.lua`, `coop_scenes.lua`, `coop_spirit.lua`, `coop_powers.lua`, `coop_world.lua`, `coop_claim.lua`, `coop_squad.lua`, `coop_souls.lua`, `coop_session.lua`, `coop_story.lua`, `coop_splits.lua`, `coop_patrol.lua`, `coop_talk.lua` | every level but the menu |
| 7 | `coop_storysolo.lua` | levels, `cfg.storyline` set |
| 8 | `coop_smod.lua`, `coop_split.lua`, `coop_ross.lua` | menu and levels |
| 9 | `dev.lua` | `cfg.dev` (not shipped: `tools/package.ps1` leaves out `dev.lua` and `probe.lua`) |
| 10 | `CoopSave.beginSession` | test sessions that skip the lobby |
| 11 | `Coop.menuLoad` scheduled | menu level with `cfg.auto` and `cfg.level` (host or `role='solo'`); clients wait for the host's `welcome` |
| 12 | `Coop.start` | `Game.Set("OnRenderDebug", "Coop.onFrame")` |

Every file is loaded with `pcall(dofile, ...)`: an error is logged and the rest still loads.
`lang_<code>.lua` are loaded on demand by `Coop.fillLang`. Each module installs most of its
wrappers lazily from its update function (the engine tables it wraps may not exist yet when
the file loads), guarded by an "installed" flag or by comparing the current function with its
own wrapper.

### 1.3 What survives a level load

- **Native state survives**: the ENet/Steam connection runs on its own thread
  (`coop_net.c:net_thread`); messages that arrive during a load wait in its inbox.
- **Lua state does not**: every module table is rebuilt. The only Lua state carried over is
  `COOP_CFG`: `Coop.rearm` (every 20 Hz tick, and before every level load the mod starts)
  writes `COOP_BOOT_LINE()` into `InitLuaLine` when it changed. `COOP_SERIALIZE` writes
  tables, strings, numbers and booleans only, sorted, on one line: never put a function or a
  userdata into `cfg`.
- Files: co-op saves and settings are `coop:*` files in `Documents\Codemasters\Clive Barker's
  Jericho\Coop` (`%JERICHO_COOP_SAVEDIR%` in tests), read and written through `Net.CoopFile`:
  `save.txt`, `checkpoint.txt`, `progress.txt` (`coop_save.lua`), `display.txt` (aspect ratio,
  `coop.lua:Coop.aspectChoice`), `video.txt` (refresh rate, borderless; read by the DLL,
  `display_hooks.c:display_load`), `coop.log` / `coop.prev.log`, `clip-*.avi`. None of them
  feeds `cfg`.

### 1.4 `COOP_CFG` (`Coop.cfg`, `cfg` in the modules)

Sources: `%JERICHO_COOP_CFG%` (a Lua table literal; test scripts and `tools/storylines.ps1`),
else `{}`; then whatever the lobby and the modules write into it during the session.

Session state written by the mod:

| Keys | Meaning |
|---|---|
| `role` | `"host"`, `"client"`, nil (no session); `"solo"` only in `Coop.menuLoad` tests |
| `myId` | this machine's peer id (host 0) |
| `char`, `seatChar` | the body held last, the lobby seat's character |
| `owners`, `seats` | ownership table (`Char=owner,...`) and seat list (`owner:char:ready:nick;...`) |
| `level`, `loaded`, `continuing`, `notice` | level to load / loaded, lobby "continue", reason shown back in the menu (`host_left`) |
| `skill`, `scaling`, `qte`, `aisquad`, `povall`, `smod` | session settings, sent in `start` |
| `actmode`, `smodrules`, `tags` | host-only settings (`actmode`, `smodrules`) and this player's nameplates (`tags`) |
| `nick`, `net`, `addr`, `port`, `joinLabel` | lobby input; `net = "steam"` for a Steam session |
| `snap`, `save` | profile values saved at session start (`CoopSave.beginSession`); `save` is written but read nowhere |
| `inst`, `instAuth`, `instIds`, `instOf`, `instAuthOnHub`, `netRole`, `realId`, `patrol` | side instances (`coop_inst.lua`, `coop_patrol.lua`) |
| `splitWasOn`, `splitSaved` | split screen engine values to put back at the next load |
| `storyline`, `storySpawned`, `storyPatrol`, `storyPatrolT` | story lines alone (`coop_storysolo.lua`) |

Test and development keys (set only through `JERICHO_COOP_CFG`): `auto`, `steamjoin`, `want`,
`prespawn`, `dev`, `bot`, `nobody`, `waitpeers`, `lang`, `split2`, `splitview`, `splithud`,
`splitsx`, `splitsy`, `splitvisflip`, `splitbodies`, `splitbodyflip`, `splitcheckflip`,
`splitfpflip`, `astralmerge`, `astralswap`, `astraluser`, `fxprobe`, `lpchoice`, `patrolsecs`,
`soulauto`, `spiritauto`, `spiritnofx`, `storykick`, `chainlog`, `mirrorlog`, `rosslog`,
`povoff`, `povfallback`, `bodyoff`/`bodyhide`/`bodyskip`/`bodynm`/`bodyface` (the
experimental scene body). Feature switches, on unless set to `false`: `aspect`, `framecap`,
`syncactive`, `mirrorarms`, `puppetlights`, `hazardlocal`, `retarget`, `rejoin`,
`syncblockers`, `syncprops`, `squadlead`, `souls`, `storyturn`, `fpbodyfix`, `menulabel`,
`rossbody`, `smodcam`; off unless `true`: `puppetai`, `puppetcollide`. `dev.lua` reads about
150 more (`cfg.trigger`, `cfg.campaignstep`, ...), all its own.

## 2. Frame loop

### 2.1 Every rendered frame: `Coop.onFrame`

The engine calls the global named by `OnRenderDebug` every rendered frame whatever the game's
time speed; its scheduler follows game time and nearly stops in slowed scenes
(`coop.lua:1386-1389`). `Coop.onFrame` runs `Coop.frameUpdate` under `pcall`, in this order:

1. `Coop.devFrame` (dev), `CoopStorySolo.update`, `CoopSplit.frame` (split screen on).
2. `CoopRoss.update` (Act 1 stand-in; in split screen `CoopSplit.showFor` runs it per view).
3. In a session: `Coop.drivePuppets(dt)`, `CoopPowers.frame` (ghost bullet copies),
   `Coop.puppetLights`, `CoopHud.update`.
4. Client: `CoopEnemies.driveEnemies(dt)`. Any role: `CoopSpirit.frame`,
   `CoopEnemies.updateSceneLabel` (curtain, "through X's eyes" caption).
5. In a session: `CoopScenes.install`, `installQTE`, `update`.
6. When `now >= Coop.nextTick`: `Coop.rearm()` and `Coop.update()`. `nextTick` steps by
   `Coop.TICK` (0.05 s) from the previous tick, so the tick is 20 Hz of real time at any frame
   rate.

### 2.2 Every tick (20 Hz): `Coop.update`

1. `Coop.frame = Coop.frame + 1`.
2. `clipKey` (F11), `autoAspect`, `frameCap`, `displayNotice`, `watchControl`,
   `CoopSmod.update`; in a session `reclaimBody`; `CoopSplit.autoStart` (tick 10 on).
3. Session settings applied every tick: `QTEMode` 2 for `cfg.qte == "auto"`, SMOD's squad menu
   slow motion off, `Net.CoopBackground(1)` while in a session (or `cfg.dev`).
4. `Coop.wrapTeam`; `CoopEnemies.install` and `CoopWorld.install` **before** the pump, so the
   messages that queued during the load meet the client guards (audit 0.2.2 A4).
5. `Coop.pump()`: up to 200 messages (section 3.5).
6. `CoopEnemies.update`, `CoopWorld.update`, `CoopTeam.update`, `CoopSquad.update`,
   `CoopSouls.update`, `CoopClaim.update`, `CoopStory.update`, `CoopPatrol.update`,
   `CoopSplits.update`, `CoopSession.update`, `CoopSpirit.update` (each under `pcall`, a few
   logged errors per module).
7. In a session: `updateLocalOwnership`, `controlWatchdog`, `CoopPowers.update`,
   `sendStates` (every tick, `SEND_EVERY = 1`), host `broadcastOwners` every 40 ticks.
8. Menu level: `CoopMenu.update`. Then `Coop.bot`, `Coop.dev`, and `Coop.report` (one log
   line) every 100 ticks.

### 2.3 `Coop.frame`

`Coop.frame` counts **ticks** (20 Hz), not drawn frames, and starts at 0 on every level load
(the `Coop` table is new). Module timings written as `Coop.frame % n` are ticks: `% 20` is a
second, `% 30` 1.5 s, `% 40` 2 s. The level-start guards use it: host 300 ticks (15 s), client
30 ticks (1.5 s), `Coop.START_WAIT` 600 ticks, `CoopTeam.installTravel` 90 ticks.

### 2.4 Host and client branches

| Step | Host | Client |
|---|---|---|
| `CoopEnemies.install` | `installHost` (spawn, group, death, damage wrappers), scene host hooks, `SaveGame.LoadLevel` wrapper | `installClient`: guards, `guardAIEvents`, damage filter, scene client hooks |
| `CoopEnemies.update` | snapshot `e` every tick, `retarget` every 20 ticks, `flushHeldScenes` | `lready` once, `freezeLocalEnemies` every 10 ticks, `guardAIEvents` every 90 |
| `CoopWorld.install` | every `MapCallbacks` entry wrapped to send `cb` | `Team.SwitchSoldier` refused during a replay |
| `CoopWorld.update` | blockers polled, digest `wd` every 4 s | blockers set back to the host's word (`W.enforceBlockers`), rejoin hint (hold T) |
| `sendStates` | every body no human holds, Act 1's Ross, relayed client states | its own body, its split screen player's |
| frame | | `driveEnemies` |

## 3. Network layer

### 3.1 `Net.Coop*` (native, `coop_net.c`)

| Function | What it does |
|---|---|
| `CoopHost(port, maxPeers)` | ENet host on `port` (UDP, 28100 by default), 2 channels |
| `CoopJoin(addr, port)` | ENet client connecting to `addr` |
| `CoopSend(peer, reliable, data)` | queue a message; peer -1 = everyone (on a client: the host), 0 = the host on clients |
| `CoopRecv()` | next inbox entry: `peer, kind, data`; kind `"msg"`, `"join"`, `"leave"`; nil when empty |
| `CoopStatus()` | `"role=host p1:rtt=3 p2:rtt=40:steam peers=2"` |
| `CoopClose([peer])` | close the session, or (host) disconnect one peer after what was sent |
| `CoopTime()` | high resolution seconds (`QueryPerformanceCounter`) |
| `CoopLog(text)` | a line in `coop.log` (or `%JERICHO_COOP_LOG%`) |
| `CoopBackground(on)` | keep running unfocused, without reading input when not in front |
| `CoopKey(vk)` | key held, only while the game window is really in front; `(-1, user)` one split screen pad's XInput state; `-2` pad rescan; `-3` raw XInput slots; `(-4, user)` hidden FP model's user (`split.c`) |
| `CoopAnnounce(text)` | host: answer LAN queries (UDP 28199) with text, `""` stops |
| `CoopDiscover()` | `"ip\|text;..."` LAN games heard in the last 5 s; asks again at most once a second |
| `CoopFile(path [, "r" / "w", data])` | file exists (game-relative); read or atomically write a `coop:` file |
| `CoopBoot()` | the boot chunk (1.2) |
| `CoopSplit(mode [, pads])` | split screen mode (0 off, 1 wide halves, 2 full frame fitted); pads: 1 merged, 0 apart, -1 off, 2 merged without latch; returns the camera slot of the frame being prepared |
| `CoopSteam(cmd, arg)` | Steam: `init`, `status`, `host`, `join`, `friends`, `pending`, `text`, `invite`, `online`, `inviteuser`, `name` |
| `CoopConsole([reply])` | test console on `%JERICHO_CONSOLE%` (127.0.0.1); run by `dev.lua` |
| `CoopClip("save")` | write the last 30 s as `coop:clip-<date>.avi`, returns its path |
| `CoopDisplay(cmd, ...)` | `get`, `rates`, `monitor`, `set` (refresh rate, borderless), `cap` (frame cap) |

### 3.2 Transport

- **ENet** (LAN, `coop_net.c`): a background thread (`net_thread`, every 2 ms) moves messages
  between two locked queues and ENet. Reliable messages go on channel 0, unreliable on
  channel 1 (`send_one`). Peer timeouts 60-120 s. LAN discovery runs on the same thread: a
  client broadcasts `JCOOP?` to 255.255.255.255, 127.0.0.1 and each adapter's broadcast
  address on UDP 28199; an announcing host answers `JCOOP!<text>`, the text being
  `nick|level|players|max|port` (`CoopMenu.announce`).
- **Steam** (`steam_net.c`, from MAK-PIVO's fork): a friends-only lobby of the Spacewar app (480)
  and `ISteamNetworkingMessages` through Valve's relays. `coop\steam_api.dll` is the mod's own
  copy. Control channel 1: `H` hello, `W` welcome, `P`/`Q` ping and pong every second, `B` bye;
  a peer silent for 20 s is dropped. Data channel 0: `A` + message; reliable messages above
  400 000 bytes go as `F` parts ending with `L`. Steam peers get the same Lua ids as ENet peers
  (`on_steam_event`). The menu still opens an ENet host for a Steam session
  (`CoopMenu.openSession` calls `CoopHost`, then `CoopSteam("host")`).
- A session is one or the other; Lua does not see the difference.

### 3.3 Peers, owners, seats

- **Peer id**: on the host, clients get the first free id from 1 (`MAX_PEERS` 8; the lobby
  opens the host for `MAX_PLAYERS - 1 = 3`); on a client the host is 0. `Coop.myId()` is 0 on
  the host, `cfg.myId` (from `welcome`) on a client.
- **Owner id**: who holds a body in `Coop.owners[char]`. A machine's player is its peer id; its
  split screen player 2 is `peer + Coop.P2` (8). `Coop.peerOf(owner)` gives the machine,
  `Coop.isMine(owner)` is true for both players of this machine, `Coop.heldBy(char, peer)`
  checks a message's sender for either of them. A peer id of 8 would read as the host's
  player 2: keep the player limit below that.
- **Seats**: `cfg.seats = "owner:char:ready:nick;..."`, the lobby's list (owner ids, split
  screen seats included). Used for nicknames (`CoopHud.nicks`), the souls' seat order
  (`CoopSouls.seats`, host first, clients in join order, split screen players last), the
  scene gate's expected machines (`CoopEnemies.expectedAll`) and split screen start
  (`CoopSplit.seatChar`).

### 3.4 Side instances (`coop_inst.lua`)

During the Lost Patrol some players play their own level instance with their own authority.
`CoopInst.install` replaces `Net.CoopSend`, `Net.CoopRecv` and `Net.CoopStatus`, so every other
module stays unchanged:

- On a side machine the side authority is "the host": `cfg.role` becomes `"host"` there and
  its members see it as peer 0. Every message goes to the hub (the session host) as
  `~r|<target>|<reliable>|<payload>`; the hub forwards it as `~f|<from>|<payload>` to side
  members only. `~f|<id>|~join` / `~leave` are synthetic connect events.
- On the hub, `-1` means the main instance only; plain messages from the hub are ignored on
  side machines.
- `~c|split|<name>|<auth>|<ids>|<level>`, `~c|main|<level>`, `~c|merge|<level>` start, drive and
  end the instance (`CoopInst.startSide`, `tellMainLevel`, `merge`).
- `cfg.netRole` and `cfg.realId` keep the real role and id.

### 3.5 Message format and dispatch

Messages are text, fields separated by `|`, first field the kind. Senders must keep `|` out of
fields (`Coop.cleanNick`, `coop_world.lua:encode` uses `\1`, `coop_save.lua:esc` `%XX`,
`coop_story.lua:enc` drops `|` and `;`). `coop.lua:split` keeps empty fields but drops one
trailing empty field.

`Coop.pump` reads up to 200 messages a tick; a handler error is logged (three per kind) and
the pump goes on. A message that starts a level load ends the pump; messages are left queued
until the next level's Lua handles them (`Coop.loading`, at most `LOAD_WAIT` 20 s). In the menu
level (`Coop.menuMode`) `CoopMenu.onMessage` is asked first, and `join`/`leave` go to
`CoopMenu.onJoin`/`onLeave`. In levels `Coop.onMessage` asks the modules in this order, the
first that returns true wins: `CoopEnemies`, `CoopTeam`, `CoopScenes`, `CoopSpirit`,
`CoopWorld`, `CoopClaim`, `CoopSquad`, `CoopSave`, `CoopStory`, `CoopSplits`, `CoopPatrol`,
`CoopTalk`, `CoopPowers`, then the core kinds of `coop.lua`.

Conventions: client to host is `CoopSend(0, ...)`; host to all is `CoopSend(-1, ...)`; a
message every machine must see from a client goes to the host, which checks the sender
(`Coop.heldBy`) and sends it on to `-1` (the sender gets it back and ignores it).

## 4. Message catalogue

R = reliable, U = unreliable. "All" from a client means the host only (a client has one peer).
Payload fields follow the kind, `|`-separated, in the order given.

### Session and bodies (`coop.lua`, `coop_spirit.lua`, `coop_split.lua`, `coop_smod.lua`)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `hello` | client → host | R | wanted char, nick, version | `coop.lua:Coop.onMessage`: version check (else `CoopClose(peer)`), `Coop.assign`, seats, `welcome`, `own`. Sent by `Coop.onJoin`, which runs only outside the menu level (test sessions with `cfg.auto`) |
| `welcome` | host → that client | R | peer id, level (no `Levels/`), char, x, y, z, yaw | `Coop.onMessage` (client): `cfg.myId`, `cfg.char`; loads the host's level if it differs |
| `seats` | host → all | R | seat list | `Coop.onMessage` (client) |
| `own` | host → all; host → a refused claimer | R | `Char=owner,...` | `Coop.onMessage` (client). Sent on every change and every 40 ticks (`broadcastOwners`); `Coop.ownersTo` at most every 2 s per peer |
| `claim` | client → host | R | char | `Coop.onMessage` (host): given if free or already the sender's and not `CoopStory.taken`. Sent by `updateLocalOwnership` and `CoopSpirit.takeBody` |
| `claim2` | client → host | R | char or empty | `Coop.onMessage` (host): owner `peer + P2`. Sent by `coop_split.lua:Sp.syncOwner` |
| `s` | client → host (own bodies); host → all (AI bodies, Ross in Act 1, relayed client states) | U | char, x, y, z, yaw, pitch, walk, strafe, sprint, life, action, shot 0/1, flashlight 0/1, sequence, sender time, weapon slot, first-person action (`-` none), active `1`/`0`/`-` | `Coop.onMessage` → `Coop.pushState` → `Coop.remote`. Built by `Coop.stateOf`; stale-state guard in 5.4 |
| `jump` | jumper → host → all | R | char, upward speed | `Coop.onMessage`: host checks the owner and relays; counted only (height comes with `s`). Sent by `coop_smod.lua:Sm.installJump` |
| `mark` | any → host → all | R | entity | `coop_spirit.lua:P.onMessage`: aura on the enemy for 8 s |

### Lobby (`coop_menu.lua`, menu level)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `welcome` | host → joining client | R | peer id, `Menu`, char, version | `CoopMenu.onMessage`: version check, then `ver`, `nick`, `smod` |
| `full` | host → refused client | R | max players | `CoopMenu.onMessage`: back to the co-op screen |
| `ver` | client → host | R | version | `CoopMenu.onMessage`: another version is refused (`CoopMenu.refuse`) |
| `nick` | client → host | R | nickname | `CoopMenu.onMessage`; a `nick` before `ver` means a client older than 0.2: refused |
| `smod` | client → host | R | `1` | `CoopMenu.onMessage`: `smodPeers` |
| `pick` | client → host | R | char | `CoopMenu.onMessage`: taken unless another seat has it |
| `p2` | client → host | R | char or `-` | `CoopMenu.setP2`: the client's split screen seat |
| `ready` | client → host | R | 0/1 | `CoopMenu.onMessage` |
| `lobby` | host → all | R | level, seats, continuing 0/1, SMOD peers (`0,2`) | `CoopMenu.onMessage` (client) |
| `sv` | host → all | R | escaped save record | `coop_save.lua:CS.onMessage` (client): kept in `CS.pending` until the load. Also before every host level change |
| `start` | host → all | R | level, seats, skill, scaling, qte, aisquad, `own`/`orig` (cutscene view), SMOD values or `-` | `CoopMenu.onMessage` → `CoopMenu.launch` |

### Enemies, scenes, levels (`coop_enemies.lua`)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `e` | host → all | U | host time, then `name,x,y,z,yaw,action,flags,pitch,life%;...` (flags: 1 active, 2 pulling the trigger, 4 faded out; life% of the highest the host saw; packets of about 900 bytes) | `E.onSnapshot` → `Coop.pushState` → `E.targets`; every tick |
| `espawn` | host → all; host → one (catch-up) | R | name, class, group, x, y, z | `E.onMessage` (client): `NPC.Counter` set to the host's number, `NPC.CreateWithAI` through `fromHost`, renamed if needed |
| `egroup` | host → all; host → one | R | group | client: `NPC.ActivateEnemyGroup` with `EnemyGen` spawning stubbed out |
| `edie` | host → all | R | name, `1` if removed quietly | client: `Life = 0` (`uData.RemoveNow` for quiet ones) |
| `pdmg` | host → owner's machine | R | victim, damage, attacker, attacker's x, y, z | `E.onMessage`: `E.origDamage` on the local body (the shooter's place only when its entity is missing here) |
| `pfire` | host → owner's machine | R | victim, fire duration, fire delay, attacker | `E.onMessage`: `FireRemainTime`/`FireDelayTime`/`Pyromaniac` on the local body (a flamethrower's flame reached it); a client's own copy of the flamer does not set bodies alight (`E.installFlamesClient`) |
| `phit` | host → owner's machine | R | victim | `E.onMessage`: `Soldier.DoHitStrong` (the hit reaction; the client suppresses its own) |
| `epart` | host → all; host → one | R | enemy, `seal`/`bomb`/`bombs`, node or 0/1 mask | `E.applyPart`: Behemoth seals and exploding cultists' pustules as the host has them |
| `eact` | host → all | R | boss, action | `E.onMessage`: a boss's non-locomotion action forced at once (fades, attacks) |
| `hit` | client → host | R | enemy, damage (body multiplier applied), attacker, bone, part damage | `E.applyHit` (no check that the attacker is the sender's body) |
| `scene` | host → all | R | `play`/`fp`/`fpni`/`fpnni`/`abort`, class | `E.onScene` (client) |
| `skipvote` | client → host | R | scene name | `E.voteSkip`: skip when every player voted |
| `skipv` | host → all | R | votes, players | `E.showSkip` |
| `level` | host → all | R | level name | `E.onLevel` (client): `CoopSave.applyPending`, `SaveGame.LoadLevel` through `fromHost` |
| `lready` | client → host | R | level name | `E.onMessage` (host): `E.sendCatchup(peer)`, `E.readyPeers[peer] = true` |

### Enemy attacks against bodies other players hold (0.2.9; `coop_enemies.lua`, host)

A body another human holds is a puppet on the host with `bIgnoreCollision = true`: every ray, line test and missile
collision of the engine passes through it, only area queries (`Game.SphereCall`, all masks R/L/G/LPO) find it. How each
kind of attack reaches it (each measured live with the dev scenario `efphases`, `lua/dev.lua`):

| Attack | Mechanism | Code |
|---|---|---|
| Hitscan (soldiers, crossbow guard...) | the shot's ray (muzzle estimate to the engine's impact point) tested against the body's capsule, radius `E.HIT_RADIUS` 27 (calibrated against the engine's hit rate on the host's own body) | `E.noteShot` (wrapper of `Weapons.OnShot`) |
| Melee events, Behemoth vomit, Legionary push, EvilFirstBorn's ray, flamethrower lines | **collision window**: `bIgnoreCollision = false` on the remote bodies for the length of the one Lua call that casts the ray, then true again (no physics step inside, it takes effect at once for rays); the game's own code then hits the puppet exactly as it hits a solid body, damage and `DoHitStrong` included | `E.withCollision`, `E.MELEE` (wrapped events), `E.flameLine` (`DoubleLineTest`). `cfg.window=false`: the old capsule fix |
| Flames | the engine's line meets the puppet inside the window; the host sends `pfire` to the owner, who sets the body alight. A client's own copy of the flamer does not (`E.installFlamesClient`) | `E.flameSend` |
| Missiles (pilum, blades, crossbow bolt, Ki's fireball, mortar, cluster) | **missile window**: from the missile's launch (`E.LAUNCHERS`) and while it is within `E.MW_RANGE` (1500) of a remote body, that body's collision is on (held 0.3 s after the last sample), so the engine's own missile collision and the game's callbacks (`HitPilum`, `HitBlade`, the explosions) meet it. `cfg.mwindow=false`: the geometric test of the missile's path against the capsule | `E.mwApply`, `E.checkMissile` |
| Area attacks (stomp, blades, club, explosions) | already found by `Game.SphereCall` | nothing to do |
| Damage | `Weapons.DoDamage` wrapper: a hit on a remote body becomes `pdmg` (the owner applies it with the game's own function); `Soldier.DoHitStrong` on a remote body becomes `phit` | `E.installHost` |

Switches for tests: `remotehit=false` (no fix at all), `window=false`, `mwindow=false`, `pfire=false`, `localfire=true`.
Counters in the 100-tick report line: `windows`, `missile-windows`, `flame-segs`, `melee swings`, `<kind>: remote hits`, `pdmgby=`.

### World (`coop_world.lua`)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `cb` | host → all | R | callback, triggered entity, encoded args (`s`/`n`/`b`/`-`) | `W.replay` (client): the level's own callback with `Coop.replay` set |
| `use` | client → host | R | callback, encoded args | `W.onMessage` (host): runs the callback if arg 1 is a body the sender holds |
| `door` | host → all | R | door, 1/0 | `W.setDoor`; a shut near the player offers the rejoin |
| `blk` | host → all | R | blocker, 1/0 | `W.setBlocker` (`bMapCollision`) |
| `kill` | any → host → all | R | object | `W.killObject` (`Life = 0`, the engine plays the break) |
| `mv` | mover → host → all; host → one (catch-up) | R | `name,x,y,z,ax,ay,az;...` | `W.applyProps` |
| `wd` | host → all | R | entries, hash | client compares `W.digest(W.entries())`; two misses in a row send `wdneed`; a residual the host's state could not remove (`only here` / `only on the host` in the log) twice in a row delays the next request by `W.NEED_BACKOFF` 120 s |
| `wdneed` | client → host | R | | `W.sendState(peer)` |
| `wdl` | host → clients (dev, `doordiag`) | R | host time, entry list (+ door objects `A:`, their collision `C:`), recent changes | `W.diagOnList`: the client logs `door-diag` episodes where its entries differ for more than 1.5 s |
| `wstate` | host → one | R | `D:name+`, `K:name`, `B:name-`, `;`-separated | `W.applyState` |

### Team, time, game over (`coop_team.lua`)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `revive` | reviver's machine → host → owner's machine | R | body | `T.onMessage`: host forwards to the owner; the owner revives (`T.reviveLocal`) |
| `time` | client → host → all | R | speed (host adds the origin peer) | `T.applyTime`; the origin skips its own echo |
| `gameover` | host → all | R | | `Team.GameOver` through `fromHost` |

### Cutscene branches and QTEs (`coop_scenes.lua`)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `qalt` | decider → host → all | R | scene entity, suffix | `S.onMessage`: `Scene.PlayAlternate` with the decider's branch |
| `qs` | host → all | R | id, sequence (`UDLR`), prefix, scene tag | `S.onSharedStart` (shared QTE mode) |
| `qr` | client → host | R | id, 1/0 | `S.onSharedMessage`: this player's result |
| `qf` | host → all | R | id, 1/0 | `S.onSharedMessage`: the squad's result |

### Powers (`coop_powers.lua`)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `gb` | bullet owner → host → all | U | owner peer, x, y, z, yaw, pitch, time | `P.onBullet`: a passive `GhostBullet` copy, interpolated |
| `gbe` | owner → host → all | R | owner peer | the copy deleted |
| `abby` | Delgado's player → host → all | R | Delgado body, target or empty | `P.onAbby`: the puppet's own Ababanili attacks or comes back (hits only play sound) |
| `pw` | caster → host → all | R | `bt`, Black, target / `cr`, Church, thread / `jt`, owner, target, x, y, z, use 0/1 / `jp`, owner, target / `burn`, caster, target, time, delay, attenuation / `rc`, `rm`, `rh`, Rawlings, target | `P.onPower`: the effect on this machine's copy (no damage) |
| `rl` | host → all | R | cursed enemy, receiver, amount | `P.onLifeFeed`: the receiver's owner adds the life |

### Story steps (`coop_story.lua`)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `sdrive` | host → all | R | char, 1/0 | `St.onMessage` (client): `Coop.storyDriven`; the owner locks its body and makes it invulnerable |
| `sdone` | host → all | R | char | `St.onDone`: the walk's arrival function |
| `sturn` | host → all | R | char, x, y, z, seconds (0: over) | the body's player gets the turn (hint, lock lifted) |
| `sturndone` | body's machine → host | R | char | `St.finishTurn` |
| `ev` | power user → host → all | R | `St.EVENTS` index, origin peer, encoded args | `St.onEvent`: the story callback on every machine |
| `gv` | client → host | R | variable, value | `Game.Set` if the sender holds the character in `St.VARS` (`RuneBloodActive`) |
| `evict` | host → the holder's machine | R | char, new char or empty | `St.onEvict`: switch out (or `CoopSplit.moveOut`) |

### Story splits (`coop_splits.lua`)

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `chs` | host → all | R | split id (`G8`, `G10`, `LP`, `G6`, `G11`, `G15`, `G4`, `G1A`, `G1C`, `G3`), seconds, owner ids, pinned owner ids | `coop_choice.lua:C.onMessage`: the shared "choose your squad" screen opens ([split-choice.md](split-choice.md)) |
| `chp` | player → host | R | split id, group index, confirmed 0/1, OWNER id | `C.setPick` (the sender's own players: its machine's player or its split screen player 2, owner peer + `Coop.P2`; a forged owner is stored under the sender) |
| `chd` | host → all | R | split id | `C.clientDone`: decided with no screen (or asked for with `chq` by a client that loaded late); a client's held call runs |
| `chq` | client → host | R | split id | a held call asks every 2 s whether the split is decided; the host answers `chd` once it is (and the explanation is read) |
| `chst` | host → all | R | split id, `owner:group:confirmed;...` | `C.applyState`: who points where, on every change and once a second |
| `chr` | host → all | R | split id, `owner:char:reason;...` | `C.onResult`: the one-line explanation, the screen closes. Moves go as `evict` first (owners rewritten at once) |
| `spn` | host → all | R | text key, chars | `Sp.showNotice` for the players holding those chars |
| `sps` | host → all (again every 10 s) | R | level, split id or `-`, side A chars, side B chars | `Sp.applySides` (downed players move only within their side) |
| `spcrank` | host → all | R | | `Sp.G11crank` |
| `g6hold` | holder → host | R | char, 1/0 | `Sp.G6onHold` |
| `spstun` | host → all | R | char | `Sp.G15onStun`: the holder struggles |
| `spfree` | holder → host → all | R | char | `Sp.G15onFree` |
| `spp` | host → all | U | percent, at console 1/0 | `Sp.G3show` |
| `spchat` | host → all | R | chat name | `TeamTalk.InitIncidentalChat` |
| `spsoul` | Rawlings' machine → host → all; host → all | R | station `1`-`3`, `arrived`, `begin`, `end` | `Sp.G4onSoul` |

### Other modules

| Kind | From → to | | Payload | Handled in |
|---|---|---|---|---|
| `actreq` | host → all | R | gate, char (`-` none), what (`ai` = the AI does it), seconds (0 closed, -1 no limit) | `coop_claim.lua:C.onMessage` |
| `sqo` | team leader's machine → host | R | `Alpha`/`Omega`, `follow`/`hold` | `coop_squad.lua:Q.onMessage`: applied if the sender's player leads that team |
| `cp` | host → all | R | | `coop_save.lua:CS.onMessage`: checkpoint hint, ammo refill, SMOD heal |
| `lpr` | client → hub | R | 1 main group / 2 trio | `LP.onMessage`: `cfg.patrol` |
| `lpt` | side authority → side members | R | | `LP.showTaken` |
| `talk` | host → all; client → host (a line its own body said) | R | voice id, speaker (entity name or `-`), filtered 0/1, show 0/1, origin peer (relayed lines only) | `coop_talk.lua:K.onMessage`: a client plays the host's line through the game's own `GenericTalk` + `StartTalkingLips`, subtitle and radio filter worked out locally; the host relays a client's line to all (the origin ignores it) and plays it when its voice channel is free (module map) |
| `~r`, `~f`, `~c` | see 3.4 | as wrapped | | `coop_inst.lua:I.recv`, `I.onControl` |

`dev.lua` sends nothing of its own except a test `pw|jt`.

## 5. Authority model

### 5.1 Who decides what

| The host | Each machine for its own players' bodies |
|---|---|
| Enemies: AI, spawns, groups, deaths, damage to every body (`pdmg` to the owner) | Position, aim, actions, life, flashlight of its bodies (`s`) |
| Story: every `MapCallbacks` call (replayed as `cb`), area pulsers, `EnemyGen`, `SaveGame` (levels, checkpoints, flag counters) | Hits on enemies, worked out locally and reported (`hit`) |
| Scenes: start, chained scenes, skip (votes), the default QTE decider | Damage without a source (falls) to its own body (`hazardlocal`) |
| Doors, blockers, the world digest; final say on broken objects and props | Objects it breaks (`kill`) and props it moves (`mv`), sent through the host |
| Bodies no human holds (AI squad), their `bActive` (`s` field 19) | Using objects (`use`), powers (`pw`, `abby`, `gb`, `ev`, `gv`) |
| Ownership (`own`), squad leaders' orders, story walks and turns, evictions | Revives of its own body, story turn done, soul walk, G6 hold, G15 struggle |
| Game over, Rawlings' help for waiting players, splits and their waves | Scene skip votes, shared QTE results, its scene branch when it holds the scene's character |

Clients drop their own copies of host decisions with guards (`coop_enemies.lua:guard`) on
every `MapCallbacks` entry, `AreaTriggers.OnEnterPluser`/`OnExitPluser`,
`NPC.ActivateEnemyGroup`/`CreateWithAI`, `EnemyGen.ActivateNextEnemy`/
`ScheduleActivationOfNextEnemy`/`Start`/`Stop` and `SaveGame.NewLevel`/`NewLevelNow`/
`AutoSaveWaypoint`/`FlagCounter`/`LoadLevel`/`LoadWaypoint`/`Restart`. Two flags let calls
through:

- `Coop.fromHost` (`CoopEnemies.fromHost(fn, ...)`): the client carrying out a host decision
  (an `espawn`, a `level`, a scene).
- `Coop.replay` (set by `CoopWorld.replay`): a replayed callback runs its own effects, including
  `SaveGame.FlagCounter` gates; enemies, saves and level changes inside it stay dropped.

A `MapCallbacks` call the client's engine makes by itself goes to `CoopWorld.onLocalCallback`,
which sends `use` when its first argument is a local body. `Team.GameOver` is guarded on
clients too (`coop_team.lua:T.install`). Since the client mirrors enemy actions, their
animation events run there as well: `E.guardAIEvents` (0.2.7) wraps the
`OnAfterAppear`/`OnAfterDisappear` events of `PsichicCommander`, `EvilFirstBorn`,
`SummerianNANNA`, `SummerianUTU` so that on a client only their non-AI parts run (ragdoll,
shield effects), re-checked every 90 ticks ([enemies-and-triggers.md](enemies-and-triggers.md) 5.3).

### 5.2 Puppets (`coop.lua:Coop.drivePuppets`, every frame)

`Coop.isPuppet(name)`: a body under a story walk is a puppet everywhere but on the host; else
on the host the bodies other humans hold, on a client every squad body except its own players'
(once it has an id). For each puppet with a received state:

- `CoopTeam.syncPuppetLife` (downed/revived/life as the owner's), `Coop.syncPuppetActive`
  (`bActive` as on the host);
- AI off (`oAI.bEnable = false`, unless `cfg.puppetai`), collision off (`bIgnoreCollision`,
  restored by `Coop.releasePuppet`), root motion off for its current action
  (`Coop.suppressRootMotion`, the local players' actions keep theirs);
- messages are taken every frame (`Coop.frameUpdate` calls `Coop.pump()` before `drivePuppets` once
  `Coop.frame >= 40`; `cfg.fastpump=false` = only at the 20 Hz tick, as before 0.2.9): a state used to
  reach the history up to a tick late and in bursts;
- target: `Coop.puppetTarget` reads the state history (`Coop.hist`, up to 48 states, ordered by the
  sender's clock) at the sender's time now minus `Coop.puppetDelay` (two states of the sender's rate +
  3 x the measured lateness, at least `INTERP_MIN` 0.1 s, at most `INTERP_MAX` 0.25 s, plus half the
  averaging window): `pathAt` is a cubic Hermite path through the states (slopes from the
  neighbours, zero where the path turns round; a jump of more than `TELEPORT` 500 units between two states
  is not interpolated), extrapolated at most `EXTRAP_MAX` (0.2 s) when states stop (slowing to a stop over that time, `extrapdamp=false` = at full speed: a body
  that is told nothing runs on past a wall or a turn by up to 90 units at full speed, 45 damped); the target is the
  average of that path over `SMOOTH_W` (0.1 s, five points), because the sender's bodies move in steps of
  the engine's own logic and a run's stride pulses their speed, which 20 Hz sampling turns into stop-and-go
  (an average over two states removes it). Switches: `hermite=false`, `psmooth=0`, `olddelay=true`;
- position: snap when the horizontal or vertical error is above `SNAP_DIST` (250 units), else the body
  is placed on the target (`FOLLOW` 1; `cfg.pfollow=0.9` removes 0.9 of the error per 0.05 s as before
  0.2.9); height only beyond `FOLLOW_Y` (1 unit); the velocity is zeroed after each placement (the engine's
  own walking on top of the placement made a step of 30 units per frame);
- snap storm safety net (`Coop.stormRelease`): more than 20 snaps of one puppet within 5 s (the engine puts the body back after every
  placement: a pin left by a script) releases it for 1 s (2, 4, 8 s when it comes back within 5 s): collision and AI back, velocity zeroed,
  `OnEndMove` cleared, `OffMul` 0, a new short `MoveMePosAng` to where the body is (that replaces a held move); logged `snap storm: released X`;
  `stormrelease=false` switches it off. The known cause: a replayed `MakeFP.CoolUse` (see `coop_world.lua`).
- `Ang`, `ViewAng`, shot, weapon slot (`Coop.syncSlot`), arm actions (`Coop.mirrorArms`) from the state
  drawn now (`tg.st`; `cfg.shotnewest=true`: the newest, as before), walk/strafe/sprint inputs, crouch
  (`Coop.syncCrouch`).
- Metrics and traces (chunk I): the 100-tick report carries `pm:squad` / `pm:enemy`: packets, interval,
  lateness, drawn frames on the move, `stall` (no step), `spike`, `und` (frames drawn on an
  extrapolation), `irr` (speed irregularity of three drawn frames in a row), `jumps`, `snaps`; dev
  traces: client `mxtrace='Delgado,enemy'` (`mxt` lines, every drawn frame of one body), host
  `mxsrc='Delgado'` (`mxs` lines, where the body really is each frame); lab `smooth_iq.sh`,
  `smooth_sum.py`, `mxt.py`, `mxcmp.py`.

- Solid bodies (`Coop.bodyPush`, after `drivePuppets`; `cfg.bodypush=false` = off): puppets have collision off, so this machine's own bodies (the user, split
  screen's player 2, and on the host the AI squad bodies it runs) walked through them, while squad bodies are solid in the original game (centre distance 90-100 when
  one walks into another). A solid body closer than `PUSH_SEP` (90 units) to a puppet is moved away from it by the overlap (at most `PUSH_SPEED` 900 units/s, to
  either side if the way back is a wall, tested with `Game.TestLine`), not while a script holds it (`IgnoreUsrControl`, story walks, scenes, spirit mode, a downed
  body); the puppets are never moved. The test bots hold their bodies with `IgnoreUsrControl`: `pushscripted=true` includes them.
- Wall crossings (dev, chunk W): `wallprobe=true` on both machines tests every drawn step of every remote body with `Game.TestLine` (body height; a hit only
  70 units lower is counted apart as `low`) for the linear, cubic, default and drawn paths and for the sender's raw state pairs, the host's own AI bodies and
  enemies being the control; `laps='Delgado'` walks a host AI body round a loop or back and forth near walls; `simloss=0.15,simburst=3` drops states on
  receive; `doordiag=true` logs door calls with the nearest body and the episodes where the machines' door/blocker/dead-object entries differ. Results:
  `notes/bugfix-029.md` (W: walls); the offline simulation of the path code is `lab/sim/pathsim.lua`.

Nothing is driven while a scene plays (scenes hide the squad). Clients drive host enemies the
same way (`CoopEnemies.driveEnemies`, `E.SNAP_DIST` 250, `E.FOLLOW` 0.9, grabs keep root
motion), drop an enemy not seen for 2 s, and switch off enemies the host never sends for
2.5 s (`E.freezeLocalEnemies`). Damage from puppets is dropped on every machine; the owner's
`hit` is the real one.

### 5.3 Relaying

There is no client-to-client traffic: `Coop.sendStates` on the host sends every body it runs
and resends the latest raw state of every remote-owned body (`st.raw`) to everyone, each tick.
A client drops states of its own bodies (`Coop.isLocalBody`) unless a story walk drives them.
The host takes `s` only from the body's owner (`Coop.peerOf(owner) == peer`). Other relayed
kinds: `jump`, `mark`, `kill`, `mv`, `time`, `revive`, `qalt`, `gb`/`gbe`, `abby`, `pw`, `ev`,
`spfree`, `spsoul`.

### 5.4 Level start

- **Readiness**: a client sends `lready|<level>` once per level after its guards are installed
  and it has an id (`E.update`). The host answers with `E.sendCatchup` (active groups, runtime
  enemies named `Enemy_*`, `CoopWorld.sendState`: doors, dead objects, blockers, moved props)
  and sets `CoopEnemies.readyPeers[peer]`.
- **Scene gate**: the host holds every scene start (`E.heldScenes`) and keeps the screen black
  (`E.holdCurtain`, which also blocks the level's fade-in and HUD) until
  `#readyPeers >= E.expectedPeers()` or `GATE_TIMEOUT` (90 s). Expected peers are machines from
  `cfg.seats` (split screen seats count with their machine, side-instance players not at all),
  or `cfg.waitpeers` in tests.
- **Stale states (0.2.7)**: states sent in the previous level and delivered after the load hold
  that level's places (a body put there fell through the map). `Coop.onMessage` drops `s` on
  the host from a peer not in `readyPeers` during the first 300 ticks, and on a client during
  its first 30 ticks; clients never take relayed copies of their own bodies
  (`coop.lua:905-916`).
- **Moving into the seat's body**: `Coop.updateLocalOwnership` switches once per level to
  `Coop.startChar()` (Ross for the host in Act 1, the story line's character, the last body,
  the seat, the first free one), waiting up to `START_WAIT` for a body the level starts
  switched off. After that the owner table follows the body the player is in (`claim`).
- **Level changes**: only the host's `SaveGame.LoadLevel` runs (`E.installLevelHost`): it sends
  `sv` and `level`, sets `cfg.level`, rearms. Clients apply the vars and load the same level.
  Leaving to the menu goes through `CoopSession.toMenu` (with `fromHost`, past the guard).

### 5.5 Ownership changes

A switch (`Team.SwitchSoldier`, the spirit's E, the claim key Y) moves the player into a body
locally; `updateLocalOwnership` then sends `claim`. The host grants a free body only;
a refused claimer gets the owner table back and `Coop.checkRefusedClaim` moves it out after
3 s. `Coop.wrapTeam` makes `Team.IsPlayerAvaliable` false for bodies other humans hold.
Who may switch at all is `coop_souls.lua` (seats 1-2 free, 3-4 keep their body).

## 6. Module map (`lua/`)

- **`boot.lua`**: `COOP_SERIALIZE`, `COOP_BOOT_LINE`, loads `coop.lua`.
- **`coop.lua`** (`Coop`): constants, ownership (`owners`, `assign`, `peerOf`, `isMine`,
  `heldBy`, `isRemoteOwned`, `isLocalBody`, `isLocalPlayer`), body state (`stateOf`,
  `sendStates`, `pushState`, `puppetTarget`, `drivePuppets`, `puppetLights`), message dispatch
  (`onMessage`, `pump`, `onJoin`, `onLeave`), level start (`startChar`,
  `updateLocalOwnership`, `reclaimBody`, `checkRefusedClaim`), the frame hook, the control lock
  watchdog (`controlWatchdog`: clients only, 12 s), first-person sets for all six
  (`installFP` wraps `Team.SwitchSoldier`; `loadFPSounds` checks every sound file), F11, aspect
  ratio (`ASPECTS`, `autoAspect`, `installAspectMenu` replaces `Menu.Switch_Aspect_Ratio`), frame
  cap, display mode and refresh rate rows (`installDisplayMenu` wraps `Menu.VideoMenu`,
  `SaveConfig2`, `CancelConfig`, `MainMenu`), texts (`lang`, `addLangs`, `enc`, `cp1251`,
  `cp1252`, `textBlock`). Replaces `Game.UsrEntity` with a guard.
- **`coop_inst.lua`** (`CoopInst`): side instances (3.4).
- **`coop_save.lua`** (`CoopSave`): co-op save files and the profile snapshot (`beginSession`,
  `endSession`), `sv`/`cp`. Wraps `SaveGame.SaveWaypoint`, `bCanLoadWaypoint`, `LoadWaypoint`,
  `HardSaveGame` (never writes the profile in a session; a level change saves `coop:save.txt`),
  `CheckVisitedLevels`, `Game.Exit`.
- **`coop_menu.lua`** (`CoopMenu`): the "Co-op" main menu entry (wraps `MainMenu.MainMenu`,
  `Menu.VerticalMenu`), host/join/Steam/invite screens, lobby, settings screen
  (`CoopMenu.Settings`), `Start`/`launch`, LAN announce, the version label (`hookLabel`). Key
  tables: `seats`, `LEVELS`, `CHAR_ORDER`, `TEXT`.
- **`coop_enemies.lua`** (`CoopEnemies`, `E`): enemies, damage, scenes, level changes, the
  level-start gate. Host wraps `NPC.CreateWithAI`, `NPC.ActivateEnemyGroup`,
  `Weapons.OnCharDeath`, `Weapons.DoDamage`, `AIMemberSquad.IsEnable` and `AIEnemy.FindMemb*`
  (targets), `Scene.Play*`, `Scene.EndOfScene`, `Scene.AbortScene`, `SaveGame.LoadLevel`; the
  client wraps the guarded functions (5.1), `Weapons.DoDamage`, scene functions,
  `Scene.AbortScene`. Both: `Scene.EndOfFpScene`, `Scene.LauchFromFP`, `Scene.ReplayScene`,
  `Scorer.Fade`/`Menu.ShowScorer` while the curtain is up. Also `E.FP_OWNER` (scene class →
  the character whose eyes it uses), enemy toughness (`E.SCALING`), `E.retarget` (enemies go for
  visible human bodies, `AIEnemy.DoAttack`), `E.playerCount`, `E.fromHost`.
- **`coop_hud.lua`** (`CoopHud`): nameplates (`Scorer` items `CoopTag_<char>` per user), hidden
  in scenes, menus, the curtain and power cameras.
- **`coop_team.lua`** (`CoopTeam`): downed players and revives (wraps `Team.RevivePlayer`,
  `Team.CheckGameOver`, client `Team.GameOver`), `T.usable` (may a downed player move into a
  body), `checkWipe`, `helpRawlings`, shared slow motion (wraps `Game.SetTimeSpeed`: pause menu
  dropped, switch flight local, Cole's and Black's powers shared, `updateCompensation` keeps
  human bodies at normal speed), `installTravel` (delays `Team.EndTravelCam` 0.1 s in split
  screen), the downed camera on a partner.
- **`coop_scenes.lua`** (`CoopScenes`, `S`): scene end clean-up (cameras handed back to
  `MainCam`, wraps `Scene.EndOfScene`, `Scene.CreateSceneObj`), branch decider and `qalt` (wraps
  `QTE.LaunchSequence`, `LaunchRndSequence`, `WrongAction`, `RightAction`, `ValidateSequence`,
  `Scene.PlayAlternate`), shared QTEs (`cfg.qte == "shared"`, also wraps
  `Scorer.QTELaunchSequence`, `QTESequenceFailed`, `QTE.GenericFail`), and the experimental own
  view (`cfg.povall`: POV camera `CoopPOVCam`, full-body actor `CoopBody` from `Pack1.packed`,
  `Scene.Load` wrapper). `S.POV_SCENES` is empty: every player sees the original camera.
- **`coop_spirit.lua`** (`CoopSpirit`): players without a body fly as Ross's spirit (camera
  `CoopSpiritCam`, F marks, E takes a free body); `startSoul`/`endSoul` for G4's soul walk.
- **`coop_powers.lua`** (`CoopPowers`): powers seen by the others. Wraps
  `ThreadsBlack.CreateGhostBullet`, `Ababanili.AbabaniliStart`/`Close`/`HitTarget`,
  `Black.ApplyTelePower`, `ThreadsChurch.ActivatePower`, `Jones.PressTelekinesis`/
  `PressPyrokinesis`, `WeaponsRawlings.Curse`/`Calm`/`Cure`, host `Weapons.ChooseLifeReceipt`/
  `DistributeLife` (`wrapPower` re-wraps when a character's table is rebuilt). Burns are polled
  (`reportBurns`).
- **`coop_world.lua`** (`CoopWorld`, `W`): map callbacks (host wraps every `MapCallbacks` entry;
  `W.replay`), `AreaTriggers.IsPlayer` accepting any human body, `MakeFP.LaunchFpsAnm` (no
  first-person animation for another player's use), `MakeFP.CoolUse` (for a puppet only the object acts: the pin and the lock the
  first-person animation would end stayed for ever and the engine put the body back every frame; `cooluse=false` = old), doors (wraps `PhysicsObj.OpenDoor`/
  `CloseDoor`), breakable objects (`PhysicsObj.CreateObj`, `pollObjects`), blockers, props,
  digest, the rejoin hint. `W.isHuman(name)` is the "is this a player" test other modules use.
- **`coop_claim.lua`** (`CoopClaim`): character-only objects (`UseJustEntity` in
  `MapPhysicObjects`), the "X is needed here" request, the AI fallback (`AIGen.GoAndAction`),
  `C.acceptsAI` for `AreaTriggers.IsPlayer`.
- **`coop_squad.lua`** (`CoopSquad`): fire team leaders (`Q.assign`), host chase of the leader
  (`AI.SetStateChar(CHASE_WITHOUT_ACTION_CHAR)`; wraps `AIMemberSquad.ExecuteOrder`,
  `OnChangeAdvancePlayerTeam`, `OnChangeAdvanceSecondTeam`, `AISquadTeam.Chase`), orders by the
  leader only (wraps `Team.ActiveFollow`, `ActiveHold`, `SupportFollow`, `SupportHold`,
  `FollowMeOrder`, `HoldPositionOrder`).
- **`coop_souls.lua`** (`CoopSouls`): roles by seat (`S.role`: `ross`, `jones`, `fixed`),
  `mayChoose`, `waitsDowned`, hints. Wraps `Team.SetIdChar`, `Team.SwitchCharacter`,
  `Scene.EndOfScene` ([player-souls.md](story/player-souls.md)).
- **`coop_session.lua`** (`CoopSession`): pause menu without pause and without restart for
  clients (wraps `Menu.MainMenu`, `VerticalMenu`, `InitMenuSys`, `BackTitle`), leaving, the host
  gone.
- **`coop_story.lua`** (`CoopStory`, `St`): story code written for one player
  ([usrentity-audit.md](usrentity-audit.md)): story walks of human bodies and the player's turn
  (wraps `AIGen.GoAndAction`, `GoAndAction_GoToEndEvent`), "the player is X" (`St.AS`,
  `St.asPlayer`), power events (`St.EVENTS`, `St.VARS`), the caldarium fire
  (`AreaTriggers.EnterFireArea`), the First Born (`EvilFirstBorn.IncapacitateSch`), evictions
  (`St.EVICT`, `St.taken`), the chapel (`MapInit.MemberOnOff`).
- **`coop_splits.lua`** (`CoopSplits`, `Sp`): the story splits G1A, G1C, G3, G4, G6, G8, G10,
  G11, G15 (`Sp.LEVELS` level → installer). Building blocks: `Sp.after` (host hook after a
  function), `Sp.offer`/`SPLITS`, `Sp.setSides`/`sameSide`, `Sp.rearm` (re-armed generators),
  `Sp.spawnWave`/`newList`, `Sp.notice`, `Sp.radio`, `Sp.runeBound`.
- **`coop_patrol.lua`** (`CoopPatrol`): the Lost Patrol choice and segments; hub wraps
  `SaveGame.LoadLevel` and `Scene.PlayFP` (BridgeCollapses); sets `CoopEnemies.dropScene`
  (TheRescue in the trio's chapel).
- **`coop_talk.lua`** (`CoopTalk`, `K`): spoken lines. Every line of the game's talk code goes through
  `TeamTalk.GenericTalk(Text, voice, filtered, show)` (voice already chosen); the host wraps it and
  `TeamTalk.StartTalkingLips` (which names the speaker) and sends `talk`. The client drops its own
  `GenericTalk` calls (AI barks, radio lines, chat lines picked by its own random numbers) and plays the
  host's through the original function: voice file of its own language, subtitle `<name>: <line>` rebuilt
  from its own language string of the voice id, radio filter from its own distance to the speaker, lips of
  the speaker. A line waits (up to 2.5 s) for the voice channel. A client's local chat chain
  (`TeamTalk.NextChat`, whose end callback runs the chat's continuation) stays alive: a played host line
  keeps `TeamTalk.EndTalkFunc` when it is `NextChat`; a dropped chat line the host never answers is played
  from the local text after 1.5 s; a stale `EndTalkFunc` left by a dropped bark is cleared. A line a client's own
  body says (its spirit entering a body, its own reload bark, the answer to its order: `Coop.isLocalBody`
  speaker, not in a replay) is played at once there and sent to the host (`K.localSay`); the same voice
  within 3 s is one line. Test:
  `lua/tests/talk_mock_test.lua` (the real `teamtalk.lua` on two simulated machines),
  `lab	alktest.sh` (pair).
- **`coop_anim.lua`** (`CoopAnim`, `A`): what other bodies do, seen here (`docs/ally-animations.md`): per
  puppet and frame from `Coop.drivePuppets` (`A.sync`): a downed puppet the engine left standing is put into
  agony (`Soldier.OnDeath` replica after 0.6 s), one `Team.RevivePlayer` per revive (`A.revive`, called by
  `CoopTeam.syncPuppetLife`), one-shot actions of the owner's body (`A.ONESHOT`: hits, reloads, hacks,
  powers) played once through `ForceAction`. Test: `lua/tests/anim_mock_test.lua`, `labnimtest.sh`.
- **`coop_choice.lua`** (`CoopChoice`, `C`): the shared squad choice at a story split ([split-choice.md](split-choice.md)). `C.DEFS` (G8, G10, LP, G6, G11, G15, G4, G1A, G1C, G3: groups of characters, `inactive` bodies a card may take, `pinned` holders, `settle` seconds, `after` hook), `C.request(id, resume)` / `C.gate(id, fn, when, replayOnly)` hold a split's start (`Sp.gate` wraps `MapCallbacks` entries, `MapInit` functions and `Scene.PlayFPNNI`, `coop_patrol.lua` wraps `Scene.PlayFP("BridgeCollapses")`); on the host the first call opens the screen, on a client the same call (a replayed callback, a level script's own call) waits for the host's `chr`/`chd` (a map callback only for a replay: the client's own use must reach its guard), so both machines start the split together. State (`done`, `pending`, `cur`, the resume queue `later`) is reset at every level load and session change (`C.reset`), the screen is text rows (`C.draw`, input by pad/arrows/digits, `C.press(key, n)` for bots; `s.locals`: one entry per local player, the split screen's player 2 uses pad 2 only), `C.resolve` turns the picks into moves (keepers, free bodies, an exchange of two players' bodies through one owner-table rewrite plus `evict`, reasons `full`/`host`/`pinned`; `result.final` = who ended in which body). One human or fewer than two groups: no screen. Test: `lua/tests/choice_mock_test.lua`.
- **`coop_spectate.lua`** (`CoopSpectate`, `S`): the spectator camera of a downed player (`CoopTeam.down`, all living bodies held by other players): own FCam `CoopSpecCam`, third person behind the watched body's shoulder, smoothed, kept out of walls with `Game.TestLine`, a caption with the nickname (its nameplate is off), A/D / left stick / arrows / fire switch the watched player, mouse / right stick orbit, automatic switch when the watched body dies, normal camera back on revive, scene or level change; split screen keeps the old MainCam targets (`T.watchPartner`). Per-frame hook in `Coop.frameUpdate`; test `lab/spectest.sh`.
- **`coop_ctl.lua`** (`CoopCtl`, `C`): diagnostics of who drives a body a human holds (owner's bug 7, "the body walks by itself").
  One `ctl:` log line whenever a held body's owner, UsrControl, oAI.bEnable, bActive, input lock, AI objective or puppet
  state changes, and `ctl: X moves by itself` when a body this machine's human holds travels more than 70 units/s for
  a second while this machine's pad/keyboard shows no move input (with the drivers it could have: story walk, squad
  leader, puppet state, last position writer, scene). `cfg.ctldiag = false` switches it off. Lab: `lab\ctltest.sh`.
- **`coop_storysolo.lua`** (`CoopStorySolo`): one story line alone (`SS.LINES`: level, char,
  spawn, timed or event-driven steps that call the main line's story functions). Started by
  `tools/storylines.ps1` with `cfg.storyline`.
- **`coop_smod.lua`** (`CoopSmod`): SMOD detection (`Sm.present`), its texts translated, one
  rule set per session (`Sm.applyRules`, `Sm.headshot`, `Sm.checkpointHeal`), its jump
  (`_G.Jump`), its pause/time scale off. Wraps the global `dofile` to re-apply its rules after
  SMOD's `autoexec.lua`.
- **`coop_split.lua`** (`CoopSplit`, `Sp`): split screen. User 1 (`UsrControl = 1`), its camera
  `CoopCam1`, HUD in scorer 1, FP model `1FP_<char>`; per frame camera slot alternation with
  `Net.CoopSplit`, visibility per view (`showFor`), hold to full screen for scenes and menus,
  player 2's powers run as user 1 (`asUser1`, `buildRemap`; wraps the class callbacks in
  `Sp.CALLBACKS` and the `Weapons` table), body checks, `claim2`. Extends `Game.UsrEntity` for
  id 3 (the hidden FP model's user).
- **`coop_ross.lua`** (`CoopRoss`): Act 1's Ross for the others: stand-in `CoopRossBody`
  (TrueRoss model), driven from Ross's entity or from `Coop.remote.Ross`; hides the real Ross.
- **`dev.lua`**: test bots (`cfg.bot`), probes and campaign steps for the test scripts, the test
  console. **`probe.lua`**: a one-off listing of the game's Lua environment.
  **`lang_de/fr/es/it.lua`**: `{["<Module>.TEXT"] = {...}}` tables merged by `Coop.addLangs`.
  **`tests/*_mock_test.lua`**: modules against an engine mock (`inst`, `souls`, `story`);
  `tests/net_ping.lua`: transport smoke test.

## 7. Native side map (`native/`)

- **`dinput8_proxy.c`**: exports `DirectInput8Create` (forwarded; `dinput8.def`). Retail-only
  fix: a vectored handler catches the read at `0x4fcd47` (the last boss's Ababanili steering
  with no prey, `edx == 0`) and resumes at `0x4fcd2a`, after checking both places' bytes. Tests:
  `JERICHO_MULTI=1` (jmp patch on `user32!FindWindowA`: several instances),
  `JERICHO_STACKDUMP=<file>` (jmp patches on `ExitProcess` and `GetLastError` at the "Check
  failed" handlers, an access-violation logger), `JERICHO_TEST_ABABANILI=1` (patches
  `0x4fcd3f` so every Ababanili loses its prey).
- **`boot_inject.c`**: `GetCommandLineA` import hook (1.1); `JERICHO_COOP_DIR`; the coop folder
  as an ANSI or 8.3 path (`coop_ansi_path`).
- **`coop_net.c`**: the `Net.Coop*` functions (3.1), registered over `Net` entries
  `GetServerData`, `AddResource`, `ModifyUsrData`, ... (`coop_funcs`); uses the exe's own Lua
  5.1.1 C API at fixed addresses (`lua_pushnil` `0x662770` ... `lua_tointeger` `0x663ff0`,
  `lua_State` top at +8, base at +0xc). ENet thread, LAN discovery, the log (`coop.log`; the
  previous one becomes `coop.prev.log` once Lua has called `CoopBoot`: no shell calls in
  `DllMain`), `coop:` paths.
  Env: `JERICHO_COOP_CFG`, `JERICHO_COOP_LOG`, `JERICHO_COOP_SAVEDIR`, `JERICHO_CONSOLE`.
- **`steam_net.c`**: Steam transport (3.2) over `coop\steam_api.dll`'s flat API with manual
  callback dispatch. Env: `JERICHO_NOSTEAM=1` (tests: Steam off), `JERICHO_STEAM_DLL` (another
  DLL, e.g. the fake), `JERICHO_STEAM_PART` (smaller parts).
- **`fake_steam_api.c`**: test-only `steam_api.dll` over UDP on 127.0.0.1 (or a remote PC):
  `JERICHO_FAKESTEAM_ID`, `_PORT`, `_REMOTE`, `_LISTREMOTE`; lobbies are files in
  `%TEMP%\jericho-fakesteam`. Never shipped.
- **`display_hooks.c`**: import table hooks on `USER32` (`CreateWindowExA`, `SetWindowPos`,
  `MoveWindow`; background mode: `GetForegroundWindow`, `GetActiveWindow`, `GetAsyncKeyState`,
  `SetCursorPos`, `SetForegroundWindow`, `BringWindowToTop`, `SetFocus`, `ShowWindow`; the game
  window's procedure is subclassed to hide deactivation), `d3d9!Direct3DCreate9` →
  `IDirect3D9` vtable 16 `CreateDevice` (adapter choice, refresh rate) → device vtable 2
  `Release` (lets go of the mod's surfaces before the device goes), `XINPUT1_3` ordinals 2/3
  (pad router, merge, latch, hot-plug, a private `xinput1_4` copy under Steam's overlay),
  `IDirectInput8` vtable 3 `CreateDevice` → device vtable 9/10 (no input when not in front; an
  idle mouse when there is none). Display mode file `coop:video.txt`. Env: `JERICHO_WINPOS`,
  `JERICHO_WINSIZE`, `JERICHO_ADAPTER`, `JERICHO_PADS`, `JERICHO_KBM`, `JERICHO_BACKGROUND`,
  `JERICHO_TEST_NOMOUSE`, `JERICHO_TESTPAD`, `JERICHO_TESTPAD2` (scripted pads 9 and 8).
- **`split.c`**: device vtable hooks `Reset` (16), `Present` (17), `SetViewport` (47),
  `DrawPrimitive`/`DrawIndexedPrimitive`/`DrawPrimitiveUP`/`DrawIndexedPrimitiveUP` (81-84),
  vertex buffer `Lock`/`Unlock` (11/12) for HUD shadows: each frame's world goes into its half of
  a composite, HUD draws are placed per user; the frame cap (`cap_wait` in `Present`). Retail-only
  call-site patch: the call at `0x478a82` to the user lookup `0x427470` goes to
  `fp_user_lookup` (a missing user, the hidden FP model's id 3, resolves to a real one). Env:
  `JERICHO_SPLITICONS`, `JERICHO_SPLITHUD`, `JERICHO_SPLITTRACE` (tests).
- **`clip.c`**: `Present` hook; 8 frames a second scaled to 640 wide, JPEG through WIC on a worker
  thread, 30 s ring, `Net.CoopClip("save")` writes a Motion JPEG AVI. `JERICHO_NOCLIP=1` off.
- **`capture.c`**: test recording from `Present`: `JERICHO_RECORD`, `_FPS`, `_START`, `_FULL`.

Hook order on a new device (`hook_CreateDevice`): `capture_on_device`, `clip_on_device`,
`split_on_device` (each patches `Present`; split's runs first and calls the others).

`build.sh` builds with Zig's clang (32-bit) against ENet 1.3.18; `ghidra_scripts/` holds the
reverse engineering scripts.

## 8. Engine facts the code relies on

- The Lua state is rebuilt on every level load; `InitLuaLine` runs once and is cleared
  (`boot.lua:1-4`). Only what is written into that line survives (`COOP_CFG`, 1.3).
- `OnRenderDebug` is called every drawn frame at any time speed; the scheduler
  (`Game.AddScheduledFunc`) follows game time (`coop.lua:1386-1389`).
- `Game.UsrEntity(i)` reads the engine's user table with no bounds check; only user 0 exists
  without split screen (user 1 with it). The game's scripts pass FP model ids to it
  (`coop.lua:2055-2070`, `coop_split.lua:853-863`, `split.c:932-941`).
- `Game.UsrEntity(0)` is nil inside first-person scenes (`coop_scenes.lua:207`,
  `coop_enemies.lua:274`).
- `UsrControl`: 0 user 0's body, 1 user 1's (split screen), -1 AI or network.
  `AreaTriggers.IsPlayer` accepts only 0 (`coop_world.lua:38-39`).
- FP models are named `<user>FP_<Char>` (`0FP_Black`); their hidden `id` is the user whose camera
  they follow; id 3 (no such user) hides one from a view (`coop_split.lua:77-86`,
  `coop_split.lua:Sp.showFor`).
- With `bCheckFPSVisible` set, the engine draws a squad member it is not looking through
  whatever `bObjectVisible` says; both must be off to hide him (`coop_ross.lua:9-11`,
  `R.hideModel`).
- The squad menu's fields are write-only from Lua: a read is an engine error
  (`coop_souls.lua:146-147`, `tests/souls_mock_test.lua:45-46`).
- Reading a property an entity does not have (e.g. `TgType` on a trigger) and looking up a
  missing entity each write an engine log line, which slowed levels to seconds per frame:
  check `IsType` first, cache absences (`coop_enemies.lua:25-28`, `coop.lua:56-65`).
- The engine picks enemy targets itself among squad bodies whose AI is on: puppets were never
  attacked without `E.retarget` (`coop_enemies.lua:1143-1149`).
- The area manager moves both fire teams around the one player (`coop_squad.lua:2-4`);
  `Team.CanCure` accepts only AI-held bodies (`coop_team.lua:6-7`).
- Locomotion actions move bodies by animation (`UseDisp`); action objects are shared by every
  body of a class (`coop.lua:509-514`). A weapon slot outside the class's slots stops the
  engine (`coop.lua:663-664`).
- New enemies are named from `NPC.Counter` (`coop_enemies.lua:1078-1081`).
- `PhysicsObj.OpenDoor` sets `Action` `Open`, later `Opened` (`coop_world.lua:362`).
  `MapPhysicObjects.PhysicObjects` keeps the level's object property lists
  (`coop_claim.lua:40-41`).
- `Scene.HideChars` sets `Active 0` and `TimeSpeed 0` on the squad (`coop.lua:1247-1249`); at a
  scene's end the engine unlinks only the current camera (`coop_scenes.lua:901-904`).
- The game restores time with `Game.SetTimeFade`, never `SetTimeSpeed(1)` (`coop_team.lua:215-218`).
- Only camera slot 0 moves by input (`coop_split.lua:325-326`); the engine draws one camera
  per frame, slot `R_SplitScreenCamera` (`split.c:1-11`).
- A sound file missing from the folder it is asked from kills the game (`coop.lua:1131-1132`);
  `Game.FileExist` looks in the current `PathInPackFile`.
- The player profile puts its aspect ratio back at the main menu (`coop.lua:1536-1540`).
- Text: Scorer items do not wrap, `CentralText` moves an item each time its text is set
  (`coop.lua:85-99`); `[...]` is markup (`coop_spirit.lua:9`); fonts use cp1251 for Russian,
  cp1252 for the others (`coop.lua:233-234`).
- The game pauses when its window loses focus (`display_hooks.c:16-19`) and refuses to start
  without a mouse (`display_hooks.c:bg_DICreateDevice`).

## 9. Where to start for common changes

- **A new message.** Pick a kind not in section 4 (also not `~r`/`~f`/`~c`). Client to host:
  `Net.CoopSend(0, 1, ...)`; host to all: `-1`; unreliable (0) only for state that is resent
  anyway. Handle it in the module's `onMessage` and return true; a new module's `onMessage` must
  be added to the chain in `Coop.onMessage` (`coop.lua:888-899`). In the menu level only
  `CoopMenu`, `CoopSave` and the core kinds are there. If every machine must see a client's
  message, relay it on the host after `Coop.heldBy(char, peer)`. If it can arrive before the
  module installed its wrappers (it was queued during the load), install them in the handler
  (`W.onObjectMessage` does). Add it to section 4 and to the module's header comment. Clients of
  other versions never meet it: the lobby refuses another `Coop.VERSION`.
- **A new synced object type.** Follow `coop_world.lua`: the host notices the change (wrap the
  engine function that makes it, or poll in `W.update`), sends a reliable message by entity
  name; the client applies it through the original function (keep it, as `W.origOpenDoor`) so
  its own wrapper does not send it back. Add an entry kind to `W.entries` so `wd`/`wstate` and the
  catch-up (`E.sendCatchup` → `W.sendState`) correct late loaders and drift; add the kind to the
  install line of `W.onObjectMessage`; count it in `W.report`.
- **A new lobby or session setting.** `CoopMenu.Settings` (a row and its `Cycle*`/`Toggle*`
  function), its label in `CoopMenu.refreshLobby`, texts in `CoopMenu.TEXT.en` and `.ru` and in
  `["CoopMenu.TEXT"]` of the four `lang_*.lua` (all six languages). If clients need it, append a
  field to `start` in `CoopMenu.Start` and read it in the `start` handler; add it to the
  defaults block in `CoopMenu.Start`. Keep it in `cfg` (it then survives level loads). A text
  table of a new module needs `Coop.addLangs(tbl, "<Module>.TEXT")` and the same key in the
  lang files.
- **A new story split line.** In `coop_splits.lua`: `Sp.installGx(isHost)` registered in
  `Sp.LEVELS`; host hooks with `Sp.after("MapCallbacks.X", fn)`; `Sp.setSides` at its start and
  end; waves with `Sp.rearm` or `Sp.spawnWave` (+ `Sp.newList`, which clients mirror from
  `espawn`); notices with `Sp.notice` and keys in `Sp.TEXT` (+ lang files); a squad choice with
  a `CoopChoice.DEFS` entry and `Sp.gate(path, id)` on the split's entry (outside the `Sp.after` hooks); a body held down with `CoopTeam.holdDowned`. Add a line to
  `SS.LINES` (`coop_storysolo.lua`) and `tools/storylines.ps1` to test it alone; update
  [coop-story-extensions.md](coop-story-extensions.md).
- **Story code that assumes one player.** Add a row to `St.AS` (`char`, `attacker`,
  `triggered`, `pick`, `clientNoop`, `clientRun`, `clientNoSwitch`), `St.EVENTS` (a power that
  drives the story) or `St.EVICT` in `coop_story.lua`; see the item list in
  [usrentity-audit.md](usrentity-audit.md).
- **A new power effect.** `wrapPower(tbl, fname, after, before)` in `coop_powers.lua` and a
  `pw` subkind in `P.onPower`; damage stays with the caster's own hits.
- **A new installer step.** `tools/installer.ps1`: add the step to the `Show-Work` list in
  `Start-Install` (key and text), do the work in `Do-Install` between `Ui-Step "<key>" "run"` and
  `"done"`, add the texts to `$script:TEXTS` for all six languages, record what it writes in
  `install.txt` (`file=`, `backup=`, `built=`) so the uninstall removes it, and keep the
  contract in [releasing.md](releasing.md). `tools/package.ps1` decides what goes into the zip.
- **A new native Lua function.** Add it to `coop_funcs` in `coop_net.c`, replacing one more
  `Net` entry (19 of the 24 are taken; make sure the game's scripts never call the one you
  take), and test for it in Lua (`if Net.CoopX then`) so an older DLL does not break the Lua.

## 10. Older descriptions that differ from the code

The code is right in each case:

- `coop.lua:10-15` lists the `s` message with 13 fields; it has 19 (5.2, section 4).
- `coop_enemies.lua:6-12` gives `e` as `e|n,x,y,...` at about 10 Hz; it is
  `e|<host time>|...` every tick (`E.SNAP_EVERY = 1`, 20 Hz).
- `coop_menu.lua:5-11` gives `start` with five fields and `lobby` with four; they have nine
  and five.
- `coop_splits.lua:27` gives `spc|<split>|<target>`; the target is not sent. `spsoul` also
  carries `begin`/`end`.
- `coop_squad.lua:13-14` says members led by another player get the game's helpers in the
  leader's area; `Q.follow` uses a chase state instead (`Q.areaOf` is left over).
- `coop.lua:905-909` says a client drops states "in its first second", `Coop.frameCap` and
  `Coop.autoAspect` say "once a second": all three count 30 ticks, 1.5 s.
- `native/split.h` names split modes 0 and 1; `coop_split.lua` uses 1 (wide) and 2 (fitted).
- `native/coop_net.h` calls `coop_log` a no-op without `%JERICHO_COOP_LOG%`; it writes
  `coop.log` in the co-op folder.
- `native/display_hooks.c:401` and `coop.lua:1565` name a `coop_display.lua`; the display rows
  are in `coop.lua` (`Coop.installDisplayMenu`).
- The README puts the aspect ratios in `display_hooks.c`; they are Lua
  (`Coop.ASPECTS`, `PhysicalAspectRatio`).
- [enemies-and-triggers.md](enemies-and-triggers.md) 7.2-7.4, the "Suggested generic mechanisms"
  of [usrentity-audit.md](usrentity-audit.md) and [scenes-catalog.md](scenes-catalog.md) 2.10
  are pre-build designs: `ereq`, `eroster`, `efx`, `act`, `prop`, `ckpt`, `shot`,
  `sceneabort`, `goto`/`arrived`/`lock`, `rune`, `alt` were built as the messages in section 4
  or not at all.

# Clive Barker's Jericho co-op: UX research and design proposal

**Scope.** This document looks at how other co-op games and fan co-op mods for single-player games handle the problems a 2-4 player Jericho co-op mod will face. It then proposes a prioritised UX design for Jericho. No code was changed and the game was not run.

**Inputs:**
- web research (sources linked inline and listed in section 7);
- `docs/campaign-structure.md`, sections 2-6: squad mechanics, per-level availability, solo sections S1-S18, single-player assumptions;
- `docs/enemies-and-triggers.md`, sections 3 and 7: damage path, host-authoritative design.

**Labels used in this document:**

| Label | Meaning |
|---|---|
| **[F]** | Fact about another game or mod, with a source URL. Many sources are reviews, wikis or community posts, not official documentation. The weaker ones are marked "(community)". |
| **[J]** | Fact about Jericho's scripts, taken from our own docs (file and line given there). |
| **[P]** | Our design proposal or opinion. It is not a fact. |

Every proposal in section 5 has three tags:
- **Effort:** S = days, M = 1-3 weeks, L = more than 3 weeks, for one modder who knows the codebase.
- **Risk:** Low, Med or High chance that it breaks the story flow or desyncs.
- **Inspired by:** the game or mod it draws on.

---

## 1. Summary of the most important recommendations [P]

1. **Bodies are the currency. Possession is the UX.**
   - Each human owns one squad body. AI drives the rest (L4D bots).
   - Death, catch-up, joining, solo sections and "no body left" are all solved with one verb from the game itself: a **soul flight** into a free body.
   - A player with no free body becomes a **Spirit**: an astral spectator with light support powers. They never see a plain black "you are dead" screen.
2. **Act 1: the host plays Ross; the other players play Omega (Church, Rawlings, Black).**
   - Those three are the only members who stay with Ross through alk_tomb.
   - Nobody can possess anyone until Ross dies, which keeps the story's rules.
3. **Character gates are satisfied by "any human who holds that character".**
   - If nobody holds the character, show a **claim prompt** that any free player can accept.
   - If nobody accepts, the vanilla AI or forced-switch behaviour runs.
4. **Downed humans go into Agony (vanilla) and can be revived by anyone.**
   - After a short delay they may soul-fly to a free body.
   - The team wipes only when no human is standing and no free body is alive. A wipe reloads the checkpoint for everyone (Halo).
5. **Cutscenes:** the host starts them and every machine plays them locally, with world time frozen. Skipping needs every player to hold the button (Guild Wars, Champions Online). **QTEs** go to the human who holds the QTE character, or to whoever claimed it.
6. **Solo and split sections:**
   - In a split, the second human in the other team leads that team's AI.
   - In solo sections the other players defend the pinned position, or watch the soloist as a Spirit and ping for them.
   - The final boss stays Church-only for the killing blow, but the others fight the adds.
7. **Lobby:**
   - Host or Join, then the lobby: player list with ready toggles, a **ranked character preference** with portraits, chapter select from the co-op save, and options (difficulty, scaling, friendly fire, nameplates).
   - The start countdown begins when everyone is ready.
8. **Difficulty scaling is light by default.**
   - Humans already land 100% of their hits, while AI squadmates land about 45% ([J], `TeamDamageFactor` 0.45). Four humans are therefore much stronger than one human with five bots.
   - Use an enemy-health multiplier. Do not spawn extra enemies.
9. **Friendly fire defaults to Reduced. Global slow-motion powers (Cole, Black, the switch flight) must be handled explicitly**, because `Game.SetTimeSpeed` is global [J].
10. **Saves:**
    - The host keeps a separate co-op save: chapter unlocks plus the vanilla checkpoint (`<level>.Spawn.Point`).
    - A dropped player's body falls back to AI and can be reclaimed on reconnect.
    - There is no host migration.

---

## 2. Research findings by game and mod

### 2.1 Commercial games

**Left 4 Dead 1/2 (Valve)**
- [F] Empty survivor slots are filled by AI bots: "if human players are not available, the remaining survivors are filled by AI-controlled bots" ([Wikipedia](https://en.wikipedia.org/wiki/Left_4_Dead)).
- [F] A downed survivor "can only be helped by another survivor", and the third incapacitation kills ([Wikipedia](https://en.wikipedia.org/wiki/Left_4_Dead)).
- [F] An incapacitated survivor can still shoot pistols, and a bleed-out meter replaces health. After two revives without a medkit the screen turns black and white, and the next incapacitation is fatal ([Giant Bomb, L4D2](https://www.giantbomb.com/games/3030-26782/)).
- [F] Dead survivors reappear in **rescue closets** and "must be freed by another survivor to rejoin the team". The AI will not open closets ([Wikipedia](https://en.wikipedia.org/wiki/Left_4_Dead); entity: [info_survivor_rescue](https://developer.valvesoftware.com/wiki/Info_survivor_rescue)).
- [F] Teammate outlines are visible through walls ([Wikipedia](https://en.wikipedia.org/wiki/Left_4_Dead)).
- [F] An "AI Director" places enemies and items dynamically ([Wikipedia](https://en.wikipedia.org/wiki/Left_4_Dead)).
- [F] A player can go idle (`go_away_from_keyboard`), and a bot then plays their survivor until they return. Community reports say this needs another human present ([Steam discussion](https://steamcommunity.com/app/550/discussions/0/1700542332317099364), [workshop comments](https://steamcommunity.com/sharedfiles/filedetails/comments/476997548), community).

**Gears of War 1/2/3**
- [F] Campaign co-op is drop-in/drop-out. Player 2 is Dom ([Co-Optimus, GoW](https://www.co-optimus.com/game/18/xbox-360/gears-of-war.html); [Wikipedia GoW2](https://en.wikipedia.org/wiki/Gears_of_War_2)).
- [F] In GoW2, co-op players can pick **different difficulty levels**, and the AI adapts ([Wikipedia GoW2](https://en.wikipedia.org/wiki/Gears_of_War_2)).
- [F] A downed player can crawl to seek help and bleeds out if not revived in time ([Wikipedia GoW2](https://en.wikipedia.org/wiki/Gears_of_War_2)).
- [F] **Split moments:** "you and your squad must split up, one player covering the other player who is in a dire situation"; they "appear every few levels, and never last for too long" ([Co-Optimus GoW2 review](https://www.co-optimus.com/review/99/Gears_of_War_2_Co-Op_Review.html)).
- [F] In GoW1, left/right path forks mostly "will not make any difference" to the outcome ([Deltia's Gaming](https://deltiasgaming.com/?p=327993)).

**Resident Evil 5**
- [F] Sheva is AI-controlled when playing alone, and the second player takes her over ([Wikipedia](https://en.wikipedia.org/wiki/Resident_Evil_5)).
- [F] A player in critical condition can be revived only by the partner, and dies if the partner cannot reach them ([Wikipedia](https://en.wikipedia.org/wiki/Resident_Evil_5)).
- [F] Items can be traded, but not weapons with online partners ([Wikipedia](https://en.wikipedia.org/wiki/Resident_Evil_5)).
- [F] "At certain points, players are deliberately separated" ([Wikipedia](https://en.wikipedia.org/wiki/Resident_Evil_5)).
- [F] Reviews call solo AI Sheva weak: she wastes ammo ([Nintendo World Report blog](https://nintendoworldreport.com/blog/18201/resident-evil-5-ps3-an-informal-review), community).

**Rainbow Six Vegas 1/2 (a squad game turned into co-op)**
- [F] Vegas 1 campaign co-op supports up to 4 players, even though the single-player squad is 3 ([GameSpot review](https://gamespot.com/reviews/tom-clancys-rainbow-six-vegas-review/1900-6162184/)).
- [F] Vegas 2: "a second player can jump into a single-player at any point, becoming a fourth teammate" ([Epic Store](https://store.epicgames.com/p/rainbow-six-vegas-2)).
- [F] The host (Bishop) keeps sole control over the two AI squadmates. The joiner (Knight) "just has to worry about himself" ([Destructoid preview](https://destructoid.com/hands-on-with-rainbow-six-vegas-2s-co-op), pre-release).
- [F] The series tells its story mostly through HUD video feeds rather than cutscenes ([Wikipedia R6 Vegas](https://en.wikipedia.org/wiki/Tom_Clancy%27s_Rainbow_Six:_Vegas)).

**Halo (CE through MCC)**
- [F] A dead co-op player respawns only when the others are "not engaged in combat and are at a safe location". If all players die, everyone restarts at the last checkpoint ([Halopedia: Cooperative](https://www.halopedia.org/Cooperative); [Giant Bomb concept](https://giantbomb.com/wiki/Concepts/Codependent_Unlimited_Revival)).
- [F] On Halo 2 Legendary, one death reloads the checkpoint for both players. It was "amazingly unpopular" and was reverted in Halo 3 ([Giant Bomb](https://giantbomb.com/wiki/Concepts/Codependent_Unlimited_Revival)).
- [F] Players who "stray too far apart will be teleported back together once a player hits a loading zone" ([Halopedia](https://www.halopedia.org/Cooperative)).
- [F] In Halo 3, player 1 is the Chief, player 2 the Arbiter, and players 3-4 are Elites ([Halopedia](https://www.halopedia.org/Cooperative)).
- [F] In Halo: Reach, enemy counts rise with the number of players ([Halopedia](https://www.halopedia.org/Cooperative)).
- [F] In Halo: Reach split-screen, cutscenes show the version of Noble Six "belonging to the player who triggered the cutscene" ([Halopedia](https://www.halopedia.org/Cooperative)).

**Borderlands**
- [F] Story progress follows the host. Other players get credit for quests they also have ([Wikipedia](https://en.wikipedia.org/wiki/Borderlands_(video_game))).
- [F] More players means the game "alters the statistics of the generated enemies" ([Wikipedia](https://en.wikipedia.org/wiki/Borderlands_(video_game)); BL2: [Co-Optimus FAQ](https://www.co-optimus.com/article/8939/borderlands-2-co-op-faq.html)).
- [F] A downed player gets a "second wind" by killing an enemy, or waits for a revive. Otherwise they respawn at the last New-U station ([Wikipedia](https://en.wikipedia.org/wiki/Borderlands_(video_game))).
- [F] BL3 also offers per-player level scaling ([Android Central](https://androidcentral.com/how-does-co-op-level-scaling-work-borderlands-3)).

**Serious Sam (HD, 3, Fusion)**
- [F] SS3 co-op has presets for lives: Standard (limited lives per player per level, then spectate), Classic (unlimited respawns) and Coin-Op (a shared pool of lives).
- [F] Custom games can toggle whether enemies scale with the number of players, and can set post-respawn invulnerability ([Co-Optimus SS3 review](https://www.co-optimus.com/review/949/page/2/serious-sam-3-bfe-co-op-review.html); [SS HD TSE review](https://www.co-optimus.com/review/472/serious-sam-hd-the-second-encounter-co-op-review.html)).

**Dying Light 2 / The Beast**
- [F] Quests progress only for the host.
- [F] The host can **teleport players who wander too far** back to themselves during quests.
- [F] Guests keep their XP and loot ([Windows Central](https://windowscentral.com/dying-light-2-co-op-how-play-online-friends)).
- [F] At narrative forks all players vote, and the host has the casting vote ([TheSixthAxis](https://www.thesixthaxis.com/?p=391804)).

**Dead Space 3**
- [F] Player 2 plays Carver. Co-op adds co-op-only side missions and Carver cutscenes, and its "asymmetrical dementia" shows different hallucinations to each player.
- [F] Enemy AI and spawn rates were tuned for co-op ([Wikipedia](https://en.wikipedia.org/wiki/Dead_Space_3)).

**Brothers in Arms: Road to Hill 30 / Republic Commando**
- [F] Neither game has campaign co-op.
- [F] BiA's multiplayer has each human commanding 3-man AI squads ([Giant Bomb](https://www.giantbomb.com/brothers-in-arms-road-to-hill-30/3030-9137/)).
- [F] A fan "Republic Commando Coop Mod" exists. User comments say that a second player joining disables bot commands and blocks progress ([ModDB](https://www.moddb.com/mods/republic-commando-coop-mod), community). This is a direct warning for a squad-command game like Jericho.

**Far Cry 2**
- [F] Single-player only; local co-op was not included.
- [F] Its "buddy" system sends a buddy to rescue the downed player. Buddies who are not healed in time die permanently ([Wikipedia](https://en.wikipedia.org/wiki/Far_Cry_2)).
- [F] This is a single-player precedent for "a squadmate revives you", which is Rawlings' role in Jericho.

**Trine / LEGO games (character switching with unique abilities)**
- [F] In Trine co-op, each player controls a different hero. Checkpoints revive dead characters, and a full party wipe returns everyone to the last checkpoint with all heroes resurrected ([Wikipedia](https://en.wikipedia.org/wiki/Trine_(video_game))).
- [F] With fewer than 3 players in Trine 2, players "can swap between who is available" ([Co-Optimus](https://co-optimus.com/article/7210/more-trine-2-co-op-footage-than-you-can-waggle-a-wand-at.html)).
- [F] In LEGO Star Wars, you switch by walking up to a friendly character, and swapping is required for ability puzzles ([Wikipedia](https://en.wikipedia.org/wiki/Lego_Star_Wars:_The_Video_Game)).

**Payday, Deep Rock Galactic (lobbies and disconnects)**
- [F] Payday added drop-in/drop-out. The host can disable AI teammates, set the lobby to friends-only and kick players ([Co-Optimus](https://co-optimus.com/article/8018/payday-the-heist-gets-a-free-update.html); [Steam discussion](https://steamcommunity.com/app/218620/discussions/8/348292787751162604); [Overkill beta notes](https://overkill-archive.starbreeze.com/?p=1789), community).
- [F] DRG is peer-to-peer. A host leaving ends the mission, and a rejoin prompt appears after recoverable disconnects ([Steam discussion](https://steamcommunity.com/app/548430/discussions/3/3492006259509679643), community).

**Apex Legends (ping system)**
- [F] Contextual pings on enemies, items and locations, with replies such as acknowledge and cancel, let teams coordinate without voice ([PC Gamer](https://www.pcgamer.com/au/apex-legends-ping-system-is-a-tiny-miracle-for-fps-teamwork-and-communication/); [Mein-MMO](https://mein-mmo.de/en/the-ping-system-of-apex-legends-is-so-good-that-other-shooters-want-to-copy-it,331956/)).

**Cutscene skipping in multiplayer**
- [F] Champions Online: hold-to-skip fills a dial and shows each player's skip status. The scene skips only if all vote ([Arc forum](https://forum.arcgames.com/championsonline/discussion/comment/12812456), community).
- [F] Guild Wars: per-player checkboxes. A unanimous skip is immediate ([GW Guru archive](https://archive.guildwarslegacy.com/05/05%20Sardelac%20Sanitarium/12006%20Another%20Cutscene%20Skip%20Proposal.001.html), community).

### 2.2 Fan co-op mods for single-player games

**Sven Co-op (Half-Life)**
- [F] Players respawn at `info_player_deathmatch` points. These can start disabled and be enabled by triggers, so the spawn moves forward with progress ([Sven wiki](https://wiki.svencoop.com/Info_player_deathmatch)).
- [F] Backtracking to a previous map is not supported: the map resets and progress is lost. Weapons and ammo are not carried between maps ([Sven mapping guide](https://www.svencoop.com/mapmi.php)).
- [F] **Survival mode:** about 30 s after map start, spawns are disabled. Dead players go to observer mode "until a checkpoint is reached or all players are dead", and a full wipe triggers a vote to restart or change map ([Sven wiki: Survival](https://wiki.svencoop.com/Setting_Up_Survival_Mode)).
- [F] Friendly fire was removed because of trolls ([Steam discussion](https://steamcommunity.com/app/225840/discussions/0/451851477878022687), community).
- [F] A community AntiRush plugin blocks level changes until enough players reach the end or a timer runs out ([wootguy GitHub](https://www.github.com/wootguy)).
- [F] Map-to-map transitions were an early engine obstacle for co-op Half-Life ([Wikipedia](https://en.wikipedia.org/wiki/Sven_Co-op)).

**Synergy (Half-Life 2)**
- [F] Covers HL2, Episodes 1 and 2 and some single-player mods. Its feature list includes "Dynamic Player Checkpoints" and "Multi-passenger vehicles" ([Valve Developer wiki](https://developer.valvesoftware.com/wiki/Synergy)).
- [F] A 2021 update "improved cutscenes" on maps that have them ([Steam changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/2091567258?p=2)).
- [F] The exact checkpoint and teleport rules are not documented in the sources found.

**Deus Ex co-op mods (HX, RolePlay Coop)**
- [F] The HX page is deleted ([ModDB](https://www.moddb.com/mods/hx)).
- [F] RolePlay Coop keeps single-player rules: one main protagonist, a persistent storyline, limited resources, and "every living being has only one life" ([ModDB](https://www.moddb.com/mods/roleplay-coop)).
- [F] An early Deus Ex co-op patch lists save games and map changes as unsolved ([FilePlanet](https://www.fileplanet.com/82165/download/Deux-Ex-Co-Op-Patch-Beta-1.1)). This shows that saves and transitions are the usual hard parts.

**Zandronum (Doom)**
- [F] Survival co-op gives each player `sv_maxlives` lives. Out of lives means spectating until the next map, and the team loses when all are out ([Zandronum wiki: Game modes](https://wiki.zandronum.com/Game_modes)).
- [F] Scripts can turn players into "dead spectators" and back. Inventory can be kept on revival ([SetDeadSpectator](https://wiki.zandronum.com/SetDeadSpectator)).

**Skyrim Together Reborn**
- [F] A **party leader** owns quest progression. Only the leader should talk to quest NPCs or trigger scripted scenes, and the leader's dialogue choices are shown to the others.
- [F] Changing the leader mid-playthrough can break quests ([Wabbanode guide](https://wabbanode.com/help/skyrim-together/understanding-parties-in-skyrim-together-reborn); [Shockbyte guide](https://shockbyte.com/billing/knowledgebase/840/How-to-Create-a-Party-on-your-Skyrim-Together-Server.html), community).
- [F] Players fix desyncs by hand with `setstage` ([80.lv](https://80.lv/articles/skyrim-is-getting-a-new-online-co-op-mod-later-this-week/)). We should avoid needing that.

**Seamless Co-op (Elden Ring)**
- [F] The mod removes fog-wall and area restrictions and supports up to 4 players. "If you die, you stay connected" ([PC Gamer](https://pcgamer.com/is-elden-ring-co-op-multiplayer); [GG Recon](https://www.ggrecon.com/articles/elden-ring-mod-finally-fixes-co-op-mode/)).
- [F] Dead players respawn at the last Site of Grace ([eXputer](https://exputer.com/features/seamless-co-op-best-way-play-elden-ring-friends/)).
- [F] Players vote on fast travel ([Prima Games](https://primagames.com/news/elden-ring-co-op-mod-public-beta)).
- [Unverified] It uses a separate save file and a session password. This is common knowledge about the mod, but none of the fetched sources confirm it, and the Nexus page itself was not fetched.

**sm64coopdx (Super Mario 64)**
- [F] Synchronises all entities and levels for multiple players.
- [F] Has a host setting `coop_stay_in_level_after_star`, so one player's star does not yank everyone out of the level ([commit](https://bytes.keithhacks.cyou/etc/sm64coopdx/commit/3b946eb5e1bc6d2dad0f08cd10af30b5cb74e0b8)).
- [F] Mods can override death with a `HOOK_ON_DEATH` Lua hook ([README](https://bytes.keithhacks.cyou/etc/sm64coopdx/raw/tag/v1.0.4/README.md)).

**Nucleus Co-op**
- [F] A split-screen launcher that runs several game instances on one PC with per-instance input ([GitHub](https://github.com/lucasassislar/nucleuscoop); [SplitScreen.Me docs](https://www.splitscreen.me/docs/create-handlers)).
- [J/P] Not applicable to us: two Jericho D3D instances froze the owner's desktop. It does confirm, though, that "multiple instances plus netcode" is a known path.

---

## 3. Patterns: problem, how others solve it, what fits Jericho

| Problem | Solutions seen [F] | Fit for Jericho [P] |
|---|---|---|
| Squad slots without enough humans | AI bots fill the slots (L4D, RE5, R6V2) | Vanilla already has AI for all 6. Keep it. |
| Who controls AI orders | Host only (R6V2); each human commands their own fireteam (BiA MP); orders broken by a naive mod (RC coop mod) | Orders go to the human who leads that team (Alpha or Omega). See 5.4. |
| Unique characters plus switching | Trine/LEGO: switch only to available heroes; Halo 3: fixed roles | Switch only to free bodies; mutual swap needs consent. |
| Death | Revive by teammate (L4D, Gears, RE5); respawn when safe (Halo); observer until checkpoint (Sven survival); lives (SS3, Zandronum); closet rescue (L4D) | Agony plus revive by anyone, then soul flight to a free body, then Spirit. Wipe means checkpoint reload. |
| Players far apart | Teleport at a loading zone (Halo); host teleport (DL2); AntiRush exit gating (Sven) | "Soul recall" possession into a body near the group, plus auto-teleport at scripted teleports. |
| Solo story sections | Deliberate separation, one player covers another (RE5, GoW2); party leader owns scripted scenes (Skyrim Together) | Others defend, spectate as a Spirit, or lead the other team. |
| Cutscenes | Show the triggering player's version (Halo Reach); unanimous skip (GW, Champions Online); host-only skip | Host starts the scene, every client plays it locally, and skipping needs everyone to hold. |
| Story progress | Host-only (Borderlands, DL2, Skyrim Together) | Host-only co-op save. Clients get chapter unlocks. |
| Difficulty for more players | Enemy stat scaling (Borderlands), more enemies (Halo Reach), toggle (SS3), per-player difficulty (GoW2) | Health multiplier, Off/Light/Full toggle. |
| Griefing | FF removed (Sven), friends-only lobby and kick (Payday) | FF Reduced by default, password, host kick, host-only story triggers. |
| Disconnect | Bot takes over (L4D idle); session ends when the host quits (DRG); rejoin prompt (DRG) | The body falls back to AI. Reclaim on reconnect. No host migration. |

---

## 4. Jericho-specific constraints that shape the UX [J]

These come from `campaign-structure.md` §6 and `enemies-and-triggers.md` §3.

| Constraint | Consequence for the UX [P] |
|---|---|
| `Game.SetTimeSpeed` is global. The switch flight sets it to 0.005, and Cole's and Black's powers change it too. | A slow-motion effect started on one machine must not slow the others. Make the switch flight local-only (camera only), and handle the powers by design (5.11, idea 3). |
| `Input.SetActionSet` is global ("Inactive", "Astral", "Menu"). | Every machine's input state is its own. Never mirror the host's action set to clients. |
| QTE state is a single table bound to `UsrControl == 0`. | One QTE at a time, run on the owning player's machine. Grab-QTE attackers (Arnold, cultist melee or flyer) need per-player routing. |
| `Team.CanCure` refuses targets with `UsrControl >= 0`. | Revive of a human-held body must be added explicitly. |
| `Team.CheckGameOver` auto-switches the dead player to the healthiest member, or ends the game. | Make it per player: soul flight, Spirit, or team wipe. |
| AI hits land about 45% of the time (`TeamDamageFactor` 0.45); human hits always land. | Each extra human raises squad damage. Scaling is needed, but only light. |
| Character gates check `UsrEntity(0).Name == "<Char>"` (biggates, pillboxes, labyrinth, Ninlil, Brandenburg). | Every gate becomes "any human holding X". |
| Three Crusades levels plus catacomb have 3 bodies; bunker_00 and sum_02 have 2; vigil_inside has 3. | With 4 players, someone is bodyless in about 7 levels. The Spirit role is required, not optional. |
| Sections S1-S18 (solo, forced, split). | Handled one by one in 5.5. |

---

## 5. Design proposal for Jericho co-op [P]

The priority tiers are used in section 6:
- **P0:** required for a playable first release.
- **P1:** strongly recommended.
- **P2:** polish or original features.

### 5.1 Session and lobby flow

**Main menu → "Co-op":**
1. **Host game.** Options:
   - Session name; password, or friends-only if a platform layer exists;
   - Max players 2-4;
   - Difficulty: vanilla Easy, Normal or Hard;
   - Co-op scaling: Off, Light or Full (5.7);
   - Friendly fire: Off, Reduced or Full;
   - Nameplates: On or Off. This is also a per-client setting.
   - Then "Continue co-op save", "New co-op campaign" or "Chapter select".
2. **Join game.** Direct IP or code, plus a recent-hosts list. Show host name, chapter and players before joining.

**Lobby screen:**
- **Player list:** nickname, ping, ready tick, chosen portrait.
- **Character preference:**
  - Each player ranks the 4 survivors (Black, Church, Delgado, Rawlings) plus Jones and Cole, using portraits (reuse the `Team.Icons` HUD art).
  - The lobby shows a prediction such as "Next level: you will be Church".
  - Ranking matters because availability changes per level (see 5.2). Duplicate first choices are allowed; ties are resolved at level start.
- **Chapter select:** shows chapters unlocked in the host's co-op save. Show a thumbnail plus "bodies available: 3" for levels with few bodies, so players know someone will spectate.
- **Start:**
  - When all players are ready, a 5 s countdown runs (Payday/L4D style).
  - The host can force-start after 30 s. Unready players join as soon as they are ready.
- **Text chat** in the lobby and in game (open with T). Voice chat is out of scope; recommend Discord.

**In session:**
- **Drop-in:** a joiner receives a free body at the next safe moment: no cutscene, QTE or solo section running.
  - Entry is shown as a soul flight from the squad's position (R6V2 and Gears drop-in).
  - If no body is free, the joiner becomes a Spirit until one is.
- **Pause menu:** never pauses the world while any client is connected. Contents: Leave, Options, player list, host-only Kick and "Return all to lobby".

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Host/Join plus lobby with ready and chat | M | Low | Payday, L4D, Seamless Co-op |
| Ranked character preference with portraits | S | Low | Halo 3 role slots, Trine |
| Chapter select from the co-op save | S | Med (spawn-point and save-var setup per level) | L4D campaign select |
| Drop-in at a safe moment | M | Med | Gears, R6V2 |

### 5.2 Character assignment and switching

**Assignment at level start or checkpoint load.** The host runs this:
1. List the bodies present and unlocked under co-op rules (see "co-op lock policy" below).
2. Give each player their **previous body** if it is present (continuity).
3. Otherwise give the highest-ranked free body from their preference.
4. Leftover players become Spirits.
5. If a gate character for this level is known to be needed (Church in biggates, the abyss and sum_end; Rawlings in pillboxes; Jones in Ninlil), the host may get a one-time prompt to assign it. This is optional; claim prompts cover it anyway.

**Switching in normal play (from Act 2 on):**
- The vanilla tap and hold radial menu are kept.
- Bodies held by another human show that player's nickname and colour, and cannot be selected (extend `Team.IsPlayerAvaliable` with an owner table).
- A free body is possessed with the vanilla soul flight. The camera flight is local only, with no global time slow (see section 4).
- **Soul swap:** if A targets B's body and B targets A's within 3 s, they swap. Both must consent (P2).
- Keep a short cooldown, for example 3 s, to stop ping-pong griefing of AI bodies that others rely on.

**Act 1 (Al-Khali; Ross alive; no possession in vanilla):**
- **The host plays Ross by default.** Ross carries most of the act's scripted logic: tutorials (`MapInit.TestTap`), AI-walks with `IgnoreUsrControl` and Ross-only triggers. Keeping him on the host avoids routing those to a client. The lobby may let the host give Ross away (P2).
- **Players 2-4 get the Omega bodies: Church, Rawlings and Black.** Alpha (Jones, Cole, Delgado) leaves in alk_tomb and returns in alk_city. Only Omega stays with Ross throughout, so Omega players keep their character for the whole act.
- **No possession or switching in Act 1 for anyone.** The tap and hold menu stays disabled, as in vanilla (`SwitchCharacterDeactivated`). This keeps the story's rule that possession begins with Ross's death.
- **alk_bunker_00 has only Ross and Rawlings.** The Church and Black players become Spirits for that level and are told so ("Church and Black hold the perimeter"). The level is short.
- **Ross's death (alk_final RossDeath → RossDeathB):**
  1. The Ross player becomes a Spirit for the cutscene.
  2. At WWII_BigGates the Ross player is placed into Delgado. Vanilla starts there as Delgado, and RossDeathB is filmed from `FP_Delgado`.
  3. The other players keep their Omega bodies.
  4. A one-line HUD note marks the change: "Ross is dead. His spirit can now move between the squad."

**Co-op lock policy.** Vanilla locks fall into three kinds:
- **Tutorial locks:** Jones, Cole and Rawlings in biggates, pillboxes and mosque. Co-op relaxes these when players would otherwise be bodyless, for example the 4th player in biggates. Keep the gated tutorial objects working by using claim prompts.
- **Story absences:** members not loaded, or set `bActive=false`. Always kept. Players without a body become Spirits.
- **Forced switches:** see 5.5.

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Owner table plus filtered radial menu | M | Med | Trine (swap only to available heroes), L4D |
| Assignment algorithm (continuity, then preference) | S | Low | Halo 3 fixed roles |
| Act 1: host = Ross, others = Omega | M | Med (Act 1 scripts assume one human) | Halo 3 (P1 Chief, P2 Arbiter) |
| Relax tutorial locks | M | Med (tutorial prompts may fire for the wrong human) | Seamless Co-op (removes area restrictions) |
| Soul swap with consent | S | Low | Original |

### 5.3 Downed, revive and death

Facts [J]:
- A downed squad member goes into **Agony** and becomes usable for a revive. It does not bleed out on its own.
- Rawlings' ghost-heal and `Team.ReviveAll`, which many checkpoints call, revive AI bodies.
- A human-held body cannot be cured by another character today.

Proposed rules [P]:
1. **A human-held body that hits 0 HP enters Agony.**
   - The camera stays on the body and the screen desaturates.
   - Pistol fire while downed (L4D) is P2. It needs animation work, so skip it at first.
2. **Revive:**
   - Any human or AI squad member can revive a downed human by holding Use for about 3 s. Remove the `UsrControl < 0` restriction in `CanCure` for co-op.
   - **Rawlings keeps his edge.** His ranged ghost-heal works on humans at range and instantly, and AI Rawlings prioritises downed humans over downed AI. This gives Rawlings a clear medic role (Far Cry 2 buddy rescue, L4D).
3. **Leave the body:**
   - After 5 s in Agony, the downed player may press Switch to soul-fly into any **free living** body.
   - The downed body stays in Agony as an AI body and can be revived later.
   - This is the vanilla single-player behaviour (`CheckGameOver` switches to the healthiest member), made a choice instead of automatic. Comparable to Trine (pick another living hero) and L4D (take over a bot).
4. **No free living body:** the player becomes a **Spirit** (5.11, idea 2) until any body is revived, then may possess it.
5. **Team wipe:**
   - A wipe happens only when every body held by a human is in Agony and **no free body is standing**.
   - A 3 s fade, then everyone reloads the last checkpoint (Halo, Trine).
   - Never use per-death reloads; Halo 2 Legendary's reload-on-death was unpopular.
6. **Act 1, Ross:**
   - Keep the vanilla rule: if Rawlings is alive, Ross is revived after 10 s.
   - Add: any human can revive Ross manually sooner.
   - If Ross and every Omega human are down, the team wipes. Nobody can possess anyone in Act 1.
7. **Option, P2: "Agony limit" on Hard.** The third downing without a checkpoint `ReviveAll` sends the player to Spirit until the next checkpoint (L4D black-and-white, Sven survival).

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Revive of human-held bodies plus per-player `CheckGameOver` | M | Med | L4D, Gears, RE5 |
| Leave the body by soul flight | S (it reuses `SwitchSoldier`) | Low | Trine, L4D bot takeover, vanilla Jericho |
| Wipe rule plus checkpoint reload for all | M | Med (must sync with the host's save vars) | Halo, Trine |
| AI Rawlings prioritises humans | S | Low | Far Cry 2 buddy rescue |

### 5.4 Split teams (Alpha/Omega)

Facts [J]:
- The AreaManager has a Main team (the player's) and a Second team.
- Orders exist for both teams (`FollowMeMain/Side`, `HoldPosMain/Side`, `SendMain/Side`).
- `AISquad.OnSwitchPlayer` swaps which team is Main.

Proposed rules [P]:
- **Team leader:**
  - If humans are in both teams, the first human in each team is its **leader** and issues that team's orders. Their team is "Main" from their own point of view.
  - On the host, the AI logic still needs one Main and one Second team. Map them as Main = the host's team, Second = the other team, but let the other team's leader send `*Side` orders through the host.
  - This follows BiA (each human commands their own fireteam) and avoids the RC coop mod failure (a joining player broke orders).
- **One leader only:** if all humans are in one team, that team's leader controls Main and can also give `*Side` orders, as in vanilla.
- **Order conflicts:** two humans in the same team cannot both give orders. Only the leader can. Leadership passes to the next human in the team when the leader leaves it.

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Per-team human leader for orders | M | High (AI follow logic is defined against one player, `AIGen.GetPlyName`) | BiA multiplayer, R6V2 (the host commands the AI) |
| AI "follow" target = nearest human in the team, not `UsrEntity(0)` | M | High | L4D bots follow the nearest humans |

### 5.5 Solo, forced and few-body sections (S1-S18 from campaign-structure §5)

General rules [P]:
- **Character gates** (S6, S8, Church/Jones/Delgado/Black-only objects, Ninlil and similar): the gate accepts any human holding that character.
- **Claim prompt** when the needed character is free (held by AI):
  - All players see "[Church] is needed — hold F to possess". Spirits and players in other bodies can accept; the first to accept takes it.
  - If nobody claims within 20 s, fall back to the vanilla behaviour: AI or forced switch of the host.
  - This replaces Skyrim Together's leader-only scripted scenes with "the owner of the needed character".
- **Forced switches** (rom_outskirts → Rawlings, sum_02 → Black, sum_01 Jones possession, sum_end → Church):
  - If the target character is held by a human, nobody switches. The script continues with that human as "the player".
  - If the target is free, the host's player, or the player nearest the target, is moved by soul flight.
  - If a player is forced *out* of a body (Jones possessed in sum_01), they soul-fly to the free body nearest the group, or become a Spirit.

**Per section:**

| # | Section | Proposal [P] | Effort | Risk | Inspired by |
|---|---|---|---|---|---|
| S1-S3 | Al-Khali | See 5.2. In the S3 bunker_01 ambush, the human Cole (if any) is moved to another body or Spirit while FakeCole works the console. Others defend the wave as normal. | M | Med | GoW2 "cover the other player" |
| S4 | WWII tutorials | Relax locks. Tutorial prompts are shown only to the human holding the taught character. | M | Med | — |
| S5 | pillboxes: Rawlings "killed", solo revive | Any human can perform the revive. Others are teleported with the squad (vanilla) and may act. Drop the solo lock in co-op, since the AI is disabled anyway. | S | Low | L4D revive |
| S6 | pillboxes Rawlings gate | Claim prompt for Rawlings. | S | Low | Original |
| S7 | vigil_inside (3 bodies) | The 4th player is a Spirit with ping and astral camera. During the Rawlings torture QTE, the Spirit sees the scene. | S | Low | Sven observer |
| S8 | Brandenburg sacrifice | Claim prompt for Church. | S | Low | — |
| S9 | Crusades, 4 levels with 3 bodies | 4th player is a Spirit for about 4 levels. This is long, so the Spirit needs real things to do (idea 2): ping, astral use of TK-able objects, rotating every checkpoint. Alternative (P2): give the bodies **round-robin** at each checkpoint so nobody spectates for 4 levels. | M | Low | Zandronum dead spectators, Sven observer |
| S10 | cru_sewers Church climb | Church's human (or a claimer) climbs. Black and Delgado players defend the gate against an **extra wave** until `TriggerBloodWar_3`, then become Spirits following Church until the door opens. | M | Med (extra wave = new enemy names; must be host-spawned deterministically) | GoW2 split moments, RE5 deliberate separation |
| S11 | rom_outskirts CenturiansTale | Forced Rawlings. Apply the forced-switch rule. All players watch the scene. | S | Low | — |
| S12 | rom_caldarium fire | Delgado's player goes solo. The others are **unfrozen** (no `Active=0`) and defend the pinned point (`SetTeamsThere`) against a reused cultist group, or switch to Spirit and follow Delgado with pings. | M | Med | GoW2 cover-the-partner |
| S13 | rom_palace_01 abyss | Church's player does the QTE. The others hold the edge against `LegionariosPuente*` and stand on the `LosetaPuente` pulser plates (vanilla teamwork made human). | S | Low | RE5 separation |
| S14 | sum_ziggurat_01 Jones possessed | The Jones player is forced out (soul flight to a free body). Optional P2: **that player gets to control possessed Jones as the "enemy"** in a short scripted window. This is fun but High risk. | S / L | Low / High | Dead Space 3 asymmetry |
| S15 | sum_ziggurat_02 (Black alone, then caged Jones) | 2 bodies: one human Black, one human Jones (astral only). The other 2 are Spirits. The Jones player uses astral projection from the cage, which is vanilla. | S | Low | — |
| S16-S17 | sum_ziggurat_03/04 partial squad | Spirits possess Delgado and Rawlings on `ShowRawlings`, and Cole and Church on `LetsGo` (claim prompts). | S | Low | Halo Reach drop-in into fixed slots |
| S18 | sum_end final phase | Change `EvilFirstBorn.SchMakeAllUnavailable`: Black, Delgado and Rawlings humans **keep fighting Arnold Leach and the adds** instead of being stunned. Only Church can land the blood-rune finish (story kept). Fallback: the stunned players become Spirits with ping on Church. | M | Med | Halo 3 final run, GoW2 |
| QTEs | various | See 5.6. | | | |

### 5.6 Cutscenes and QTEs

**Cutscenes** (`Scene.Play`; it freezes all WalkChars and sticks camera 0):
- **The host triggers; every client plays the same scene locally** with its own camera 0. Gameplay is frozen for all (vanilla `HideChars`).
- **"From their own perspective":**
  - FP scenes are filmed from a named actor (`FP_Church`, `FP_Delgado`), so everyone sees the scene through that character's eyes. That is acceptable, and it mirrors Halo Reach showing the triggering player's version.
  - P2: for `PlayFP*` scenes that use `UsrEntity(0)`, each client may use its own body's FP actor where one exists.
- **Skip:**
  - Every player must hold Skip for 1.5 s. The HUD shows "2/3 want to skip" without names (Champions Online, Guild Wars).
  - The host can force a skip after 10 s.
  - First viewing in a co-op save is skippable too. The scene was already seen in single player.
- **Sync:**
  - The host sends "scene X start" and "scene X end" plus post-scene positions (`Scene.SetUsrPosAng` data).
  - Clients hold at the last frame until the host's "end" arrives (max 3 s), so nobody acts early.
  - A client that loads late skips straight to the end state.
- **Dialogue and radio (`TeamTalk`):**
  - Today it excludes human members from radio lines.
  - In co-op, AI-only selection is fine. Human-held characters simply do not bark. Their pings use their own voice lines (idea 5).

**QTEs.** Vanilla QTEs belong to one character: Ross, Cole, Rawlings or Church.
- **Owner** = the human holding that character. If nobody holds it, a claim prompt appears before the scene. If nobody claims, the host's player is moved into the character.
- **Others:**
  - They watch the same scene and see the button prompts greyed out, which builds tension.
  - Optional P1 **"Blood pact"** (idea 6): spectators press the same prompts; each correct supporter press adds a little time to the owner's window.
- **Fail result:** vanilla. The scene fails, which usually means death and a checkpoint reload for everyone, as a wipe.
- **Grab QTEs during combat** (Arnold, cultist melee, cultist flyer grab a player):
  - Run on the grabbed player's machine. The host must target the right human.
  - Until that routing exists, disable grab attacks against client-held bodies, or let them deal plain damage instead.

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Host-triggered local cutscenes plus end sync | M | Med | Synergy, Halo |
| Unanimous hold-to-skip | S | Low | Champions Online, Guild Wars |
| QTE owner routing plus claim prompt | M | Med (QTE is single-state and bound to `UsrControl == 0`) | Skyrim Together (leader runs scripted scenes) |
| Grab-QTE per player | L | High | — |

### 5.7 Level transitions and catch-up

- **Transitions are host-authoritative:**
  - When the host's script calls `SaveGame.NewLevel`, all clients load.
  - Assignment (5.2) runs at spawn.
  - No backtracking (Sven).
- **Pre-exit gate (optional, P2):** "AntiRush". A level-exit trigger that the host walks into starts a 15 s countdown, unless all humans are within 30 m. The countdown is cancelled if the host leaves the zone (Sven AntiRush). Default Off, since the host is usually trusted.
- **Scripted teleports** (`FadeAndMove`, `MoverFaster`, `SumTeleport`, rom_chamber "the other 5 are teleported"): apply them to **human bodies too**. The vanilla scripts already move the whole squad; in co-op they must not skip non-host humans.
- **`OnAllInside` triggers** (they need the whole squad inside):
  - Humans count as squad. AI members catch up by themselves.
  - Humans more than about 40 m away get a HUD arrow and "The squad is waiting for you".
  - After 30 s, **soul recall** (idea 1) moves them.
- **Soul recall (catch-up), P0:**
  - A player far from the group (more than 60 m, or in another sector) can hold the Recall key.
  - They soul-fly into a free body near the group. Their old body becomes AI and follows by itself.
  - If no body is free, their own body is teleported behind the nearest human, out of enemy view.
  - This is Jericho's lore-friendly version of Halo's "teleport at loading zone" and Dying Light 2's host teleport.

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Synchronised `NewLevel` plus re-assignment | M | Med | Sven, Synergy |
| Scripted teleports include humans | M | Med | Halo loading zones |
| Soul recall | S-M | Low | Halo, Dying Light 2 |
| AntiRush exit countdown | S | Low | Sven AntiRush plugin |

### 5.8 Difficulty scaling

Facts [J]:
- Vanilla has Easy, Normal and Hard variants (for example `RegenStepEasy/RegenStep/RegenStepHard` in `squadcfg.lua`). The difficulty logic itself is in the engine.
- AI squadmates land about 45% of hits on enemies; humans land 100% (`Weapons.DoDamage`).

Proposal [P]:
- **Lobby difficulty** = vanilla difficulty, chosen by the host.
- **Co-op scaling** (an SS3-style toggle):
  - **Off:** vanilla numbers.
  - **Light (default):** enemy and boss `Life` × (1 + 0.15 × (humans − 1)). That gives 1.0 / 1.15 / 1.30 / 1.45.
  - **Full:** × (1 + 0.30 × (humans − 1)), plus a 15% shorter revive window on Hard.
  - Apply the multiplier once, at enemy creation, on the host.
- **Do not add enemies** (unlike Halo Reach).
  - Enemy names and generator groups must stay deterministic for host/client sync (`enemies-and-triggers.md` §1.3).
  - Extra waves only in the hand-designed solo-section defences (5.5).
- **Per-player difficulty** (GoW2) is not proposed: all damage is host-side, and it adds complexity for little value.

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Health multiplier on enemies and bosses | S | Low-Med (boss scripts that write `Life` directly, such as phase thresholds, need checking) | Borderlands, SS3 |
| Optional extra defence waves in solo sections | M | Med | Halo Reach |

### 5.9 Nameplates, markers, ping and chat

- **Nameplates**, shown when Nameplates is On; each client can toggle them:
  - Nickname in the player's colour above the head of every human-held body, fading with distance (max 60 m) and hidden while aiming down sights.
  - The character's name stays secondary. Example: "Alex (Church)" in the Tab overlay only.
- **Teammate markers:**
  - At the screen edge, an arrow per off-screen human with the distance.
  - A **downed marker**: a red Agony icon that shows through walls (L4D outlines).
  - Spirits are shown as faint wisps; Spirits have no nameplate.
- **Ping** (Apex-style), on the middle mouse button:
  - On an enemy: highlight it for 5 s.
  - On a usable or TK object: "Use here".
  - On the ground: "Go here".
  - Double-tap: "Danger".
  - Pings appear on all clients for 8 s. Spirits can ping too, which is their main job.
- **Tab overlay:** players, characters, health, ping in ms, Spirit or alive state.
- **Chat:** text chat with system lines ("X joined", "X claimed Church", "Checkpoint reached"). No voice.
- **Implementation note [J]:** HUD work goes through `Scorer.*(0, …)`, which is viewport 0 only. That is fine, since each client has its own viewport 0. Projecting world positions to the screen for nameplates is an engine unknown and must be tested early. Fallback: radar-style edge markers only.

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Nameplates (toggle) plus downed icon | M | Med (world-to-screen API unknown) | L4D outlines, Serious Sam names |
| Off-screen arrows | S-M | Med | many shooters |
| Ping | M | Low | Apex |
| Text chat plus system messages | S | Low | Payday, Sven |
| Character portraits in select | S | Low (reuses HUD icons) | Halo 3 |

### 5.10 Saves, checkpoints, disconnects, reconnect, griefing

- **Co-op save** (host only, a separate file or save-var namespace):
  - unlocked chapters;
  - the last checkpoint (level plus `<level>.Spawn.Point`);
  - per-nickname preferred character.
- Clients store a "chapters unlocked as guest" list, so they can host from there later. This follows Borderlands and DL2, where guests keep rewards.
- **Checkpoints** = vanilla autosave waypoints (`SaveGame.AutoSaveWaypoint`), run by the host.
  - On a checkpoint, the host also calls `ReviveAll` as vanilla does, and Spirits get bodies again where possible.
  - In Sven survival, a checkpoint likewise ends observer mode.
- **Wipe or reload:** everyone reloads the host's checkpoint. Body ownership is kept where the body exists.
- **Disconnect:**
  - The player's body reverts to AI at once (L4D bot). Their slot is reserved for 3 minutes.
  - A reconnect with the same nickname and token reclaims the body. A DRG-style "Rejoin" prompt is shown in the menu.
- **Host leaves:**
  - The session ends. Clients get "Host left — progress saved at the last checkpoint" and return to the menu.
  - **No host migration.** The host owns enemies, triggers and the save, as in DRG and most P2P mods.
- **Griefing controls:**
  - Password; host kick.
  - FF default Reduced (25%). Powers never hurt teammates: Abaddon fire, TK throws, ghost bullets and explosions caused by a human are filtered for human targets.
  - Story triggers run only on the host (`enemies-and-triggers.md` §4.2).
  - Possession cooldown.
  - Swap only with consent.

| Item | Effort | Risk | Inspired by |
|---|---|---|---|
| Host-side co-op save plus chapter unlocks | M | Med | Seamless Co-op separate save, Borderlands |
| Disconnect → AI; reconnect reclaims | M | Med | L4D, DRG |
| FF options plus power filtering | S-M | Low | Sven (FF removed), SS3 options |

### 5.11 Original ideas built on Jericho's own mechanics

1. **Soul recall and soul entry (P0).** One verb covers joining, catch-up, leaving a downed body and forced switches: the vanilla possession flight into a free body. Players already understand it from single player.
   - Effort S-M · Risk Low · Inspired by Halo stragglers teleport, L4D bot takeover, Jericho's own `TravelCam`.
2. **Ross's Spirit, the role for bodyless players (P0 minimal, P1 full).**
   - A player without a body is Ross's ghost: an astral orbit camera tied to a chosen teammate (`AstralCamera` "OnlyOrbit" exists), free-flying within about 30 m of the squad.
   - **Minimal:** spectate, ping, chat.
   - **Full:** use Jones-style astral interactions (`funcOnTK`/`funcOnBurn`) on objects already flagged `bUseOnTK`; a weak "chill" that slows one enemy for 2 s on a 20 s cooldown; and a whisper aura that doubles revive speed near the Spirit.
   - The role turns the 3-body Crusades levels and solo sections from waiting into supporting. It also fits the story: everyone is Ross's spirit, whether in a body or not.
   - Effort M (minimal S) · Risk Med (camera per client; astral action set is global) · Inspired by Sven observer, Zandronum dead spectator, Jones's astral projection.
3. **Shared slow-motion as a team moment (P1).**
   - `SetTimeSpeed` is global, so Cole's time-slow and Black's power would slow every player. Do not fight it; design for it.
   - When Cole slows time, all players get the slow-motion with a team-wide tint and a "Cole: Slow" banner. Shots from *other* players during the window deal +25%.
   - This turns a sync problem into a combo, but it needs a cooldown so one player cannot keep the team in slow motion.
   - Alternative if desync is bad: make it local to Cole (only Cole's machine slows and the host scales Cole's input). That is High risk.
   - Effort M · Risk Med · Inspired by Max Payne-style bullet time, original for co-op.
4. **Power combos between players (P2).** Each is a host-side damage bonus on an enemy flagged by another player's power:
   - Church's blood-rune **binding** plus Delgado's Abaddon: bound enemies take double fire damage.
   - Black's TK lift plus anyone shooting: lifted enemies take +50%.
   - Jones possessing an enemy: that enemy gets an "ally" outline for everyone, and others' kills on enemies near it chain a short stun.
   - Effort M each · Risk Med · Original (spirit of the vanilla "Ababanili" and "blood ward" synergies).
5. **Character-voiced pings (P1).** A ping plays a line from the pinging character's existing radio and bark set (`TeamTalk` assets): "Contact!", "Over here". It costs no new audio, keeps characters' voices, and helps tell who pinged.
   - Effort S-M · Risk Low · Inspired by Apex pings.
6. **Blood pact QTEs (P2).** During a single-owner QTE, the other players see the prompts and can press them. Each correct support press adds about 0.2 s to the owner's current window. It makes watching active without letting others take over the story moment.
   - Effort M · Risk Med (QTE engine is single-state) · Original.
7. **Claim the calling (P0).** When a scene needs a specific character and that body is AI-held, show an atmospheric prompt ("The Abyss calls for Church"); the first player to accept soul-flies in. This handles every `UsrEntity(0).Name == "<Char>"` gate without forced switches.
   - Effort S · Risk Low · Original; replaces Skyrim Together's leader-only rule.
8. **Rawlings, the field medic (P1).** A human Rawlings gets:
   - a revive radar that shows downed humans through walls;
   - ghost-heal that works on human bodies;
   - a team bonus: revive time −30% while Rawlings is human-held.
   It gives players a reason to pick Rawlings, who is otherwise the least "shooty" character.
   - Effort S · Risk Low · Inspired by L4D medkit role, Far Cry 2 buddy rescue.
9. **Asymmetric apparitions (P2).** In a few horror set pieces, spawn cosmetic, non-colliding apparitions on only one random client: whispers, a child cruzader at the corner of the eye. Players will argue about "did you see that?".
   - Effort S per set piece · Risk Low (local only) · Inspired by Dead Space 3 asymmetrical dementia.
10. **Round-robin bodies in 3-body levels (P2).** In the Crusades stretch, at each checkpoint the longest-waiting Spirit swaps with the player who has held a body longest, unless that player opts out. Nobody spectates for 4 levels in a row.
    - Effort S · Risk Low · Original; this fairness rule is missing from Sven and Zandronum observer modes.

---

## 6. Prioritised roadmap [P]

| Tier | Items | Why |
|---|---|---|
| **P0** | Lobby with Host/Join, ready, chapter select and portraits; assignment algorithm; owner-filtered switching; Act 1 rule (host = Ross, others = Omega); Agony plus revive of humans; leave body by soul flight; wipe = checkpoint reload; claim prompts for character gates; forced-switch rule; host-triggered cutscenes plus unanimous skip; QTE owner routing; synchronised `NewLevel` plus scripted teleports including humans; soul recall; minimal Spirit (spectate, ping, chat); light health scaling; FF options; disconnect → AI; host-only co-op save | Without these, the campaign cannot be finished with 2-4 players. |
| **P1** | Nameplates and off-screen arrows (the owner asked for them; P0 if the world-to-screen API is easy); per-team leaders for Alpha/Omega orders; S10 and S12 defence waves; S18 others fight adds; full Spirit powers; shared slow-motion design; voiced pings; Rawlings medic perks; reconnect reclaim | Keeps everyone engaged and polishes the core. |
| **P2** | Soul swap; Blood pact QTEs; power combos; asymmetric apparitions; round-robin bodies; AntiRush; Agony limit on Hard; Ross handover in Act 1; per-client FP scene actors; possessed-Jones window (S14) | Fun or polish with more risk. |

**Biggest risks to validate early** (order matters):
1. More than one `UsrControl` index, plus a per-client camera and input. This blocks everything.
2. Global `SetTimeSpeed` during the switch flight and Cole's and Black's powers.
3. QTE routing to a non-host human.
4. AI follow and orders logic hard-wired to `AIGen.GetPlyName()`.
5. World-to-screen projection for nameplates.

---

## 7. Sources

Commercial games:
- Left 4 Dead: https://en.wikipedia.org/wiki/Left_4_Dead · https://www.giantbomb.com/games/3030-26782/ · https://developer.valvesoftware.com/wiki/Info_survivor_rescue · https://steamcommunity.com/app/550/discussions/0/1700542332317099364 · https://steamcommunity.com/sharedfiles/filedetails/comments/476997548
- Gears of War: https://en.wikipedia.org/wiki/Gears_of_War_2 · https://www.co-optimus.com/review/99/Gears_of_War_2_Co-Op_Review.html · https://www.co-optimus.com/game/18/xbox-360/gears-of-war.html · https://deltiasgaming.com/?p=327993
- Resident Evil 5: https://en.wikipedia.org/wiki/Resident_Evil_5 · https://nintendoworldreport.com/blog/18201/resident-evil-5-ps3-an-informal-review
- Rainbow Six Vegas: https://gamespot.com/reviews/tom-clancys-rainbow-six-vegas-review/1900-6162184/ · https://store.epicgames.com/p/rainbow-six-vegas-2 · https://destructoid.com/hands-on-with-rainbow-six-vegas-2s-co-op · https://en.wikipedia.org/wiki/Tom_Clancy%27s_Rainbow_Six:_Vegas
- Halo: https://www.halopedia.org/Cooperative · https://giantbomb.com/wiki/Concepts/Codependent_Unlimited_Revival
- Borderlands: https://en.wikipedia.org/wiki/Borderlands_(video_game) · https://www.co-optimus.com/article/8939/borderlands-2-co-op-faq.html · https://androidcentral.com/how-does-co-op-level-scaling-work-borderlands-3
- Serious Sam: https://www.co-optimus.com/review/949/page/2/serious-sam-3-bfe-co-op-review.html · https://www.co-optimus.com/review/472/serious-sam-hd-the-second-encounter-co-op-review.html
- Dying Light 2: https://windowscentral.com/dying-light-2-co-op-how-play-online-friends · https://www.thesixthaxis.com/?p=391804
- Dead Space 3: https://en.wikipedia.org/wiki/Dead_Space_3
- Brothers in Arms: https://www.giantbomb.com/brothers-in-arms-road-to-hill-30/3030-9137/
- Republic Commando coop mod: https://www.moddb.com/mods/republic-commando-coop-mod
- Far Cry 2: https://en.wikipedia.org/wiki/Far_Cry_2
- Trine: https://en.wikipedia.org/wiki/Trine_(video_game) · https://co-optimus.com/article/7210/more-trine-2-co-op-footage-than-you-can-waggle-a-wand-at.html
- LEGO Star Wars: https://en.wikipedia.org/wiki/Lego_Star_Wars:_The_Video_Game
- Payday: https://co-optimus.com/article/8018/payday-the-heist-gets-a-free-update.html · https://steamcommunity.com/app/218620/discussions/8/348292787751162604 · https://overkill-archive.starbreeze.com/?p=1789
- Deep Rock Galactic: https://steamcommunity.com/app/548430/discussions/3/3492006259509679643
- Apex ping: https://www.pcgamer.com/au/apex-legends-ping-system-is-a-tiny-miracle-for-fps-teamwork-and-communication/ · https://mein-mmo.de/en/the-ping-system-of-apex-legends-is-so-good-that-other-shooters-want-to-copy-it,331956/
- Cutscene skip voting: https://forum.arcgames.com/championsonline/discussion/comment/12812456 · https://archive.guildwarslegacy.com/05/05%20Sardelac%20Sanitarium/12006%20Another%20Cutscene%20Skip%20Proposal.001.html

Fan co-op mods:
- Sven Co-op: https://wiki.svencoop.com/Setting_Up_Survival_Mode · https://wiki.svencoop.com/Info_player_deathmatch · https://www.svencoop.com/mapmi.php · https://en.wikipedia.org/wiki/Sven_Co-op · https://steamcommunity.com/app/225840/discussions/0/451851477878022687 · https://www.github.com/wootguy
- Synergy: https://developer.valvesoftware.com/wiki/Synergy · https://steamcommunity.com/sharedfiles/filedetails/changelog/2091567258?p=2
- Deus Ex co-op: https://www.moddb.com/mods/hx · https://www.moddb.com/mods/roleplay-coop · https://www.fileplanet.com/82165/download/Deux-Ex-Co-Op-Patch-Beta-1.1
- Zandronum: https://wiki.zandronum.com/Game_modes · https://wiki.zandronum.com/SetDeadSpectator
- Skyrim Together: https://wabbanode.com/help/skyrim-together/understanding-parties-in-skyrim-together-reborn · https://shockbyte.com/billing/knowledgebase/840/How-to-Create-a-Party-on-your-Skyrim-Together-Server.html · https://80.lv/articles/skyrim-is-getting-a-new-online-co-op-mod-later-this-week/
- Seamless Co-op: https://pcgamer.com/is-elden-ring-co-op-multiplayer · https://www.ggrecon.com/articles/elden-ring-mod-finally-fixes-co-op-mode/ · https://exputer.com/features/seamless-co-op-best-way-play-elden-ring-friends/ · https://primagames.com/news/elden-ring-co-op-mod-public-beta
- sm64coopdx: https://bytes.keithhacks.cyou/etc/sm64coopdx/commit/3b946eb5e1bc6d2dad0f08cd10af30b5cb74e0b8 · https://bytes.keithhacks.cyou/etc/sm64coopdx/raw/tag/v1.0.4/README.md
- Nucleus Co-op: https://github.com/lucasassislar/nucleuscoop · https://www.splitscreen.me/docs/create-handlers

**Research caveat:** several pages could not be fetched directly (HTTP 403 or 402), and their content was taken from search-result summaries. These include GameSpot, Co-Optimus, the Valve Developer wiki and the Nexus page for Seamless Co-op. Claims marked "(community)" come from forums or user comments.

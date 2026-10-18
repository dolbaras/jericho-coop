## Act 1 (Al-Khali): "stay in own body" lines for splits G1, G2, G3

Status: design proposal, 2026-10-18. Read-only research on the decompiled scripts in
`work/src`. Paths below are relative to `work/src/levels/<level>/scripts/` unless they start
with `scripts/`. Markers: [O] read in the scripts, [I] inference, [guess] needs checking in game.
Voice keys come from `work/voices/catalog.tsv` (keys only, no quotes). A key such as
`talk_jones_help_alpha` is played with `TeamTalk.RadioTalk("Jones", "Help_Alpha", "Talk")`;
mission and scene chats play through `TeamTalk.InitIncidentalChat("<Mission_...>")`.

Act 1 constraint: player 1 is Ross, and Ross cannot switch in Al-Khali
(`scripts/chars/ross.lua:271-272`). Option (a), "switch to a character who goes on", therefore
means taking a free body of the group that stays with Ross.

### 0. Building blocks shared by all three lines

| Need | Existing mechanism | Where |
|---|---|---|
| More enemies without new map data | `NPC.CreateWithAI(acName, x, y, z, groupName)` creates a cultist with AI at any point and adds it to a group. Bosses use it with `ForceAction = "FliesEmerge"` (cultist rises out of a fly swarm). | `scripts/chars/npc.lua:29-52`; `scripts/chars/psichiccommander.lua:290-294` |
| Emerge animation | `CultistaMelee` loads `Emerge`/`QuickEmerge` in its class setup, so it is available wherever the class is loaded. `FliesEmerge` is defined there. alk_city and alk_bunker_01 also add `Emerge` for `CultistaExplosivo`. | `scripts/chars/cultistamelee.lua:151-156, 190-192`; `alk_city/mapinit.lua:1-5`; `alk_bunker_01/mapinit.lua:5-6` |
| Generators | Pool-based; `isInfinite` is read on every spawn, so it can be switched at run time. `EnemyGen.Stop(group, killAll)` ends a generator. `EnemyGen.IncreaseMaxEnemies` raises the simultaneous cap. | `scripts/chars/enemygen.lua:82-105, 161-200, 212-219` |
| One-shot groups | `NPC.ActivateEnemyGroup` stores `<level>.EnemyGroup.<name>.Status` and never activates a group twice. | `scripts/chars/npc.lua:248-277` |
| Radio | `RadioTalk` refuses only when the speaker has `Life <= 0` or `CannotSpeak`. A body with `bActive=false` can still talk. The radio-filtered file (`*_.ogg`) is chosen by distance to `Game.UsrEntity(0)`. | `scripts/chars/teamtalk.lua:186-203, 214-225, 227-262` |
| Trigger gating per character | Pattern: `if Game.GetTriggeredEntity(Playerid) == "Ross" then ...` | `alk_bunker_01/mapcallbacks.lua:231-236` |
| New checkpoints and objective zones | New entries in `MapAreaTriggers.Areas` (data, not geometry), or a scheduled distance poll. | any `mapareatriggers.lua` |
| Objective text | `Scorer.SetMsgText(text, until)` (hint line); new text only as subtitles. | used in every Act 1 `mapinit.lua` |

Caveat for spawning [I]: a group's `el_OnAllDeath` callback runs when all of its members die,
including members added by `CreateWithAI`. Many Act 1 callbacks drive progress through
`SaveGame.FlagCounter` (examples: `alk_tomb/mapcallbacks.lua:233-238`, `alk_city/mapcallbacks.lua:184-193`).
The co-op waves must therefore use their own group names (for example `coop_alpha_tomb`),
created at run time, and never the vanilla ones. Whether `AITeamList.InsertMember` accepts
an unknown team name without a matching `MapEnemiesGroup` entry must be checked
(`scripts/ai/aienemy.lua:46-76`) [guess].

---

### G1. Alpha leaves in alk_tomb and rejoins in alk_city

#### G1.1 Vanilla [O]

1. After the first fight, `AreaTrigger_After_Kill` (box at 2558,-2323,14544) calls
   `MapInit.TalkingAfterKill` (`alk_tomb/mapcallbacks.lua:123-125` → `mapinit.lua:39-47`).
   The chat `Mission_Alk_Tomb_After_Kill` ends with Ross's order: Jones takes Alpha on a recon,
   no fighting without support, meet here in an hour, Omega goes with Ross
   (`mission_alk_tomb_after_kill3`).
2. `MapInit.StartSayGoodbye` (`mapinit.lua:102-149`):
   - sets Jones, Cole and Delgado `bActive=false` (106-108);
   - creates three invulnerable walkers `FakeJones`, `FakeDelgado` and `FakeCole` at
     (176,-2043,16070), (307,-2061,15984) and (-132,-2068,16046), which walk off for 20 s and
     are deleted (`DeleteGoodByeChars`, 170-174);
   - moves Ross, Church, Black and Rawlings, and AI-walks Ross with `IgnoreUsrControl` on
     `UsrEntity(0)` to (320,-2600,13098) (`MiraDetrasDeTi`/`LiberateMe`, 151-164);
   - plays `Mission_Alk_Tomb_Team_Split` (Rawlings and Ross: find the command center and
     Agent Green), then `Bloquer0` loses collision (166-168).
3. Omega continues through the tomb (groups `segundo`..`quinto_grupo_cultistas`, TK door
   `puerta_fistro`, First Born sightings) to `Borrame_cinematica` → scene `BloodDoor`
   (`mapcallbacks.lua:127-129`). In the scene Ross tells Church and Black to stay
   (`scene_alk_tomb_blood7`, see G2). `OnEnd_BloodDoor` loads Alk_Bunker_00 (`mapscenes.lua:182-188`).
4. Spawn table Id 2 (waypoint after `puerta_fistro`) has `bJones/bCole/bDelgado = false`
   (`alk_tomb/mapspawnplayers.lua:104-151`).
5. alk_bunker_00 loads only Rawlings and Ross (`alk_bunker_00/map.lua:5`). In `MurielsTale`
   Jones calls by radio: Alpha needs backup in the north-east part of the dig, multiple
   targets, they keep coming; Ross answers that they are on their way
   (`scene_alk_bunker_00_muriel16`..`21`).
6. alk_city: Alpha's spawn (Id 0) is Jones (-66,-46,-9486), Cole (136,-44,-9274) and
   Delgado (422,-50,-9337) (`alk_city/mapspawnplayers.lua`, Id 0). This is sector `S_10`
   (438,-212,-9326), linked to `S_12` (493,-212,-10757). `AreaTriggerInit` (next to Ross's start)
   hides them at once (`mapcallbacks.lua:97-100` → `mapinit.lua:17-24`).
7. `AreaTrigger119` becomes active after four groups die (`segundos_cultistas_0`, flag
   `revivir_1` = 4, `mapcallbacks.lua:198-204`). On entry, `AreaTrigger119_1` opens
   `primera_puerta_black`, activates the explosive cultists and calls `MapInit.EnableAlpha`
   (`mapcallbacks.lua:12-21`, `mapinit.lua:7-15`).
8. Alpha's pocket is closed by two door objects, `primera_puerta_black` (-969,-41,-8158) and
   `cultista_destruye_esta` (-1452,247,-11510) (`alk_city/mapphysicdoor.lua`), and is
   covered by the two boxes of `AreaTrigger863` (543,88,-8896 and -92,94,-10760). After the
   explosive wave, that trigger plays `Mission_Alk_City_Reunion` and Black opens the second
   door (`mapcallbacks.lua:87-90`, `mapinit.lua:26-43`).

The level geometry agrees with the radio call: the place where Alpha reappears in
alk_city is a dead end sealed by rubble, with the spawn points of the explosive generator
`primeros_cultistas_explosivos` inside it (Enemy144 582,1,-11113; Enemy169 481,88,-8080;
Enemy194 -160,5,-10704; Enemy219 -718,104,-10786) [O].

#### G1.2 "Stay in own body": Alpha's road (three legs)

**Premise.** Jones takes Alpha on the recon Ross ordered. Cole's scan leads them along the
outpost's far side into its east tunnel. The cultists come up out of the dig behind them and
push them out into a dead end in the north-east of the dig. This is the call for help the
game already plays during MurielsTale. Omega fights through the city and breaks the rubble
(the vanilla reunion).

**Leg A: alk_tomb, "Perimeter recon"** (from the goodbye to the BloodDoor scene).

- Start: the Alpha humans keep their bodies. They start at the vanilla walk-off points of the
  Fake walkers above (near sector `S_53` 132,-2058,14676), so the goodbye looks the same.
- Route through cleared areas, using sectors from `alk_tomb/mapareateam.lua`:
  - Preferred, matching the direction of the Fake walkers [guess]: north to `S_10` (599,-2366,21924),
    then the linked chain `S_10 → S_28 → S_29 → S_30 → S_31` to `S_111`/`S_11` (6010-6816, 19487-19604;
    `S_11` has an upper box at y -1884, a natural lookout). These are the storm-plateau
    sectors the script hides and shows around the first fight (`MapInit.HiddenSectors`,
    `mapinit.lua:28-37`).
  - Fallback if that path is blocked: back east through the TK door `Puerta_Black_abre`
    (2868,-2334,14418, open since `mapinit.lua:189-193`), then `S_34` (3618,14661),
    `AreaTeam` (3600,16367), `S_33` (3628,18525), `S_321`/`S_32` (5056, 18467/19397), and
    `S_111`/`S_11`. The invisible blockers `Block1`/`Block2` (4435,18476 and 4464,19191) are
    already disabled by `TalkingOutCaveEnd` (`mapinit.lua:54-57`).
  - All Omega triggers in this area are clear-on-enter and have already fired
    (`AreaTrigger`, `AreaTriggerSecureEnemies`, `AreaTrigger250`/Tag_02, 453, 284, 286, 288),
    so Alpha cannot set off Omega's script by walking here [O].
- Objectives:
  1. Recon marks (new trigger boxes at sector centers): `S_33` (the field where the first
     cultists appeared), the `S_11` lookout, and `S_29` (storm edge). Each mark plays a Cole
     scan line.
  2. At the lookout, "do not engage without support" fails: the waves start, and Alpha holds
     `S_11`/`S_111`.
  3. After the last wave, Cole reports a ley-line convergence. The leg ends with the
     subtitle "Alpha moves toward the outpost's east side". From here the Alpha humans stay
     put (or get a short spirit/spectator view) until Omega triggers BloodDoor, which every
     player watches.
- Enemies: the tomb has no generators and its groups are one-shot and tied to Omega's flag
  counters. Use `CultistaMelee` (the only cultist class loaded, `alk_tomb/map.lua:1-4`) spawned
  with `CreateWithAI` + `FliesEmerge` into `coop_alpha_tomb`, at points around `S_31`/`S_111`/`S_32`.
  The first vanilla group (`Primeros_enemigos_jericho`: Enemy 2995,-2314,14775; Enemy51
  3018,-2307,14661; Enemy72 4103,-2321,15136) came from this field, so the approach is
  plausible. Suggested size: 3 waves of 2-4, scaled by the number of Alpha humans [I].
- Voice beats:

| Beat | Keys |
|---|---|
| Departure | `mission_alk_tomb_after_kill3` (vanilla); `talk_jones_tactical_flavor0`/`1` (Jones scouts ahead) |
| Marks | `talk_delgado_gencom_modern2` (no survivors), `talk_cole_gencom_modern1` (quantum paradox), `talk_cole_gencom_modern4` (quantum signal from the center of the dig), `talk_jones_dark_area1` |
| Waves | `talk_jones_enemy_ambush*`, `talk_delgado_forboding_sound2`/`3`, `talk_cole_forboding_sound2`, `talk_jones_tactical_flavorc4`/`c5` |
| End | `talk_cole_spot_breach1` (ley-line convergence ahead), `talk_cole_hint_right_way1` |

**Leg B: alk_bunker_00, "The east tunnel"** (the whole level, optional; see feasibility).

- Premise: Alpha enters the outpost by the far tunnel, the one Ross and Rawlings later leave
  by, while Omega enters by the blood door in the west.
- Route, from `alk_bunker_00/mapareateam.lua`. Alpha spawns at `S_28` (5530,472,-4862), just
  inside the `New_Level` box (5646,659,-4885), then goes `S_27` (4181,424,-4854) → `S_26`
  (2449,180,-5291) → `S_25` (335,-383,-5793) → `S_24` (1,-383,-4570) → `S_09` (1,-383,-3351).
  It turns back before `S_08` (-2119,-383,-2481), which leads to Muriel's room
  (`puerta_escena_muriel`, -3614,-220,-1346).
- Objectives:
  1. Sweep to `S_09` (mark).
  2. "They are behind us": fall back to the tunnel mouth at `S_28` under pursuit.
  3. Hold the mouth. `MurielsTale` freezes every `WalkChar` during the scene
     (`scripts/missions/scene.lua:622-638`), and Jones' radio call plays inside it.
  4. When Ross enters the exit-chat box `AreaTrigger` (10,256,-4218; `AreaTrigger_4`,
     `mapcallbacks.lua:91-93`), Alpha fades out ("Alpha is pushed out into the dig",
     `bActive=false`). Only a short wait is left before the level change.
- Enemies: `CultistaMelee` only (`alk_bunker_00/map.lua:1-4`), spawned with
  `CreateWithAI` + `Emerge` behind Alpha (`S_24`, `S_25`). Adding `CultistaExplosivo` to
  `init.Enemies` is possible but costs memory [guess].
- Voice beats: `talk_delgado_gencom_modern2`; `talk_cole_dead_victim*` (if the props
  include bodies [guess]); `talk_cole_forboding_sound1`; `talk_jones_tactical_flavorc6` (they
  want to split us); `talk_cole_spot_exit1` for the fallback; the canonical call
  `scene_alk_bunker_00_muriel16`..`21` (vanilla).

**Leg C: alk_city, "Pinned at the north-east dig"** (from level start to the reunion).

- Alpha starts at its vanilla spawn in the pocket (`S_10`/`S_12`) and is not hidden.
- Objective: hold the pocket until Omega opens `primera_puerta_black`.
- Escalation follows Omega's progress, using the vanilla triggers as cues:
  - level start: light wave;
  - `AreaTrigger` (2080,-144,-5485), `AreaTrigger_3` at `mapcallbacks.lua:113-115`: second wave;
  - `AreaTrigger49` (-851,-407,-4876; `mapcallbacks.lua:65-68`): heavy wave, "they keep coming";
  - `AreaTrigger133` (-1984,-304,-7259; `mapcallbacks.lua:23-27`): Alpha hears Omega near;
  - `AreaTrigger119_1`: vanilla door, explosive wave and `EnableAlpha`. Both groups fight the
    same wave, and that is the reunion.
- Enemies: `CultistaMelee` and `CultistaExplosivo` (both loaded, with `Emerge`), spawned with
  `CreateWithAI` into `coop_alpha_city` at the four coordinates of the vanilla generator
  `primeros_cultistas_explosivos` listed above. Do not activate the vanilla group: its death
  counts toward the `reunion` flag (`mapcallbacks.lua:184-193`).
- Voice beats:

| Beat | Keys |
|---|---|
| Pinned | `talk_jones_help_alpha0`..`5` (by radio; Ross answers with `talk_ross_help_alpha4`..`6`), `talk_cole_enemy_ambush1` (trapped), `talk_delgado_forboding_sound2`, `talk_jones_tactical_flavorc4`/`c5` |
| Omega near | `talk_cole_spot_team1` (Omega in sight), `talk_jones_spot_team1`, `talk_delgado_spot_team4` |
| Reunion | `talk_jones_rejoin_team0`, `talk_delgado_rejoin_team4` (stick together this time), `talk_ross_rejoin_team0`, then the vanilla `Mission_Alk_City_Reunion` (`mapinit.lua:26-28`) |

#### G1.3 Engineering and risks

- alk_tomb `StartSayGoodbye`: for human-held Alpha bodies, skip the `bActive=false` and the
  matching Fake walker, and move the body to the walker's position. AI-held Alpha members can
  keep the vanilla behaviour.
- Omega's AI must not try to collect the Alpha humans, and AI-held Alpha bots, if kept, must
  hold position (`Team.HoldPosSide`, `scripts/chars/team.lua:814`, or per-member orders). The
  AreaManager follow logic assumes one human [I] (`campaign-structure.md` 2.4).
- Checkpoints: spawn Id 2 of alk_tomb drops Alpha. Add a co-op variant that places Alpha on
  the plateau (for example `S_31`) while Leg A runs.
- Revive: Rawlings, the healer, is with Omega. A human body currently cannot be revived by
  another character (`Team.CanCure`, `scripts/chars/team.lua:353-356`). The general co-op
  revive rule is needed, otherwise one death in Alpha means waiting until `Team.ReviveAll` at
  the next checkpoint (`team.lua:403`).
- Leg B:
  - add Jones, Cole and Delgado to `init.Team` (`alk_bunker_00/map.lua:5`) and turn on their
    flags with new positions (`mapspawnplayers.lua:8-25`);
  - gate `New_Level` (`AreaTrigger_3`, `mapcallbacks.lua:86-89`), the exit chat (`AreaTrigger_4`) and
    `AreaTriggerWrongWay` (`mapcallbacks.lua:63-65`) to Ross and Rawlings;
  - memory and streaming of three more characters in a level built for two [guess];
  - the door `PuertaXX` (-2,181,-4062, open, portal `Portal04`) lies on the tunnel; check that
    the portal does not cull the area when it is reached from the east [guess].
- Leg C:
  - patch `MapInit.DisableAlpha` so that it does not hide human-held bodies;
  - keep `EnableAlpha`; its `AreaManager:SetActual` call (`mapinit.lua:14`) moves the AI team
    to Cole and is harmless;
  - if the pocket turns out not to be sealed (other exits besides the two doors), gate
    `AreaTrigger119`/`133`/`49`/`279`/`AreaTrigger_3` to Omega members.
- Radio filter: the `_` radio variant depends on distance to `UsrEntity(0)` (host). Per
  client this should depend on the listener [I].

#### G1.4 Feasibility

| Leg | Rating | Must check in game |
|---|---|---|
| C, alk_city pocket | easy-medium | the pocket is sealed; spawns at the generator points are free (`Game.TestSphere`); bots hold |
| A, alk_tomb plateau | medium | where the Fake walkers go (passage near `S_53`); plateau reachable without blockers; `FliesEmerge` plays in this level |
| B, bunker_00 east tunnel | hard | memory with 5 characters; tunnel walkable from `S_28` to `S_09`; AI navigation; trigger gating |

If Leg B is dropped, Alpha players spend bunker_00 as spirits or spectators. The radio
call in `MurielsTale` is then their beat, and Leg C follows directly.

---

### G2. alk_bunker_00: only Ross and Rawlings go down to Muriel

#### G2.1 Vanilla [O]

- In `BloodDoor` (alk_tomb), Ross takes Rawlings and tells Church and Black to stay at the
  door and let them out if it does not open from inside (`scene_alk_tomb_blood7`/`8`).
  Church warns that she does not know how long the seal stays open (`scene_alk_tomb_blood6`).
- `alk_bunker_00/map.lua:5` loads `{"Rawlings", "Ross"}`. The spawn table still contains
  Church (-6262,725,2041) and Black (-6377,725,2241) with `bChurch/bBlack = false`
  (`mapspawnplayers.lua:26, 41`).
- Level flow:
  - `AreaTrigger32` (-6134,690,1917), entry chat (`mapcallbacks.lua:14-17`);
  - `AreaTrigger461` (-5496,716,-1054) activates the single-enemy group `torturer` (35-37);
  - `torturer_0` opens `puerta_escena_muriel` (200-203);
  - `AreaTriggerMurielsTale` (-3038,-257,-1682) plays the scene (59-61);
  - `OnEnd_MurielsTale` gives follow orders (`mapscenes.lua:26-33`);
  - exit chat `AreaTrigger_4` at (10,256,-4218);
  - `New_Level` (5646,659,-4885) → ALK_City (`mapcallbacks.lua:86-89`).
- Inside the scene Ross radios "Abby, Billy, we're coming out" (`scene_alk_bunker_00_muriel25`).
- In alk_city, spawn Id 0 places Church (7918,-98,-6606) and Black (7843,-127,-6253) next to
  Ross (7544,-110,-6448): the vanilla reunion happens off-screen at the level load.

#### G2.2 "Stay in own body": Keep the door open (Church and Black)

**Premise.** The blood seal stays open only while Church stays near it (her own warning in
`blood6`). Cultists that followed the squad out of the tomb try to get in behind Ross. Church
and Black hold the outpost's entrance hall so that Ross and Rawlings keep a way out.

- Area: the entrance sectors of `alk_bunker_00/mapareateam.lua`:
  - `S_00` (-6305,785,1929), the spawn, with the threshold marked by `AreaTrigger32`;
  - `S_01` (-5078,785,1989) and `S_02` (-5023,785,866);
  - approaches from `S_04` (-6643,459,-877), `AreaTeam24` (-6324,253,12) and the high `S_03`
    (-5018,1428,-653).
- Objectives:
  1. "Hold the seal": Church must stay within `S_00`/`S_01`. If she is out longer than a
     grace time, a subtitle warns, and an extra wave comes as a soft penalty (no failure state) [I].
  2. Survive waves timed to Omega's progress:
     - wave 1 when Omega fires `AreaTrigger461`;
     - wave 2 when `torturer_0` opens Muriel's door;
     - nothing during `MurielsTale` (the scene freezes all characters anyway);
     - the final, largest wave after the scene, until Ross enters the exit-chat box.
  3. End: subtitle "Ross and Rawlings are out by the east tunnel; Church releases the seal",
     then the level changes. Reunion at the alk_city start, where they already spawn beside Ross.
- Enemies: `CultistaMelee` (loaded) spawned with `CreateWithAI` + `Emerge` in `S_02`/`S_04`/`AreaTeam24`,
  in a group of their own (`coop_door_b00`). The vanilla `torturer` group is Omega's and stays untouched.
- Voice beats:

| Beat | Keys |
|---|---|
| Waiting | `talk_church_idle_impatient2`, `talk_black_idle_impatient1`, `talk_church_weird_sound1`, `talk_black_forboding_sound0` |
| Waves | `talk_black_tactical_flavorc0`/`c1` (Black to Church: focus, keep everyone together), `talk_black_tactical_flavorc7`, `talk_church_forboding_sound1`, `talk_church_enemy_ambush*`, `talk_black_help_omega*`/`talk_church_help_omega*` by radio |
| Lull | `talk_church_enemy_quiet3`/`4` |
| Ross's cue | `scene_alk_bunker_00_muriel25` (vanilla, inside the scene) |
| Reunion (alk_city start) | `talk_black_rejoin_team2`/`3` ("nice walk?"), `talk_church_rejoin_team0`, `talk_rawlings_rejoin_team1`, `talk_ross_rejoin_team2` |

Players of Jones, Cole and Delgado in this level follow G1 (Leg B, or spirit or spectator).

#### G2.3 Engineering and risks

- Add `"Church", "Black"` to `init.Team` (`alk_bunker_00/map.lua:5`) and set their spawn flags,
  only when those players chose (b). Otherwise use the vanilla tables.
- Omega is one AI team (Church, Rawlings, Black: `scripts/chars/team.lua:5-60`). An AI-held
  Church or Black would follow Ross. Hold them per member, and patch `OnEnd_MurielsTale`, which
  calls `Team.FollowMeSide/Main` (`mapscenes.lua:26-33`), so that it skips them.
- Gate `New_Level`, `AreaTrigger_4`, `AreaTrigger461` and `AreaTriggerMurielsTale` to Ross and Rawlings.
  Church and Black should not reach them, but it is cheap insurance.
- Revive: no healer at the door. Use the co-op revive rule, or `ReviveAll` when a wave ends.
- Memory of two extra characters in this level [guess].

#### G2.4 Feasibility: medium

Loading the two characters is easy. The AI orders, the gating and the spawn points need
work. Check in game:

- the entrance hall is walkable and the spawn points work with `Emerge`;
- the blood door is actually behind `S_00` [guess];
- the frame rate and memory with four squad bodies.

---

### G3. alk_bunker_01: Cole at the console (FakeCole) during a ~120 s ambush

#### G3.1 Vanilla [O]

1. `AreaTrigger_Begin_1` (-394,379,-1165) closes `PuertaEntrada` (3645,-218,-1338), enables
   `blockerEntrada` and sends Rawlings toward Muriel's body (`mapcallbacks.lua:94-98`,
   `mapinit.lua:45-50`).
2. `trigGoToRawlings` (74,120,-1317) fires only for Ross (`mapcallbacks.lua:231-236`). Ross is
   AI-walked with `IgnoreUsrControl` on `UsrEntity(0)` (`mapinit.lua:52-57`). When both have
   arrived, `CryForTheChild` plays `Mission_Alk_Bunker_01_Discover` (59-64).
3. `GoColeToManipulate` (66-74):
   - sets Muriel `Life=0`;
   - plays `Mission_Alk_Bunker_01_Cole` (Cole warns about spatial distortion and sends everyone out);
   - AI-walks Cole to `MapInit.ColePos` (400,330,-138), facing -90 (15-17).
4. `StartManipulation`/`InitManipulation` (96-113) spawns an invulnerable `FakeCole` playing the
   `HackCom` action. That action is added to the Cole class in `MapInit.main` (7-9).
   `DelayedDeactivate` points `TeamTalk.FacialAlias.Cole` to the fake and sets the real Cole
   `bActive=false` (115-119).
5. `MoveSquadAndStartCombat` (87-94) AI-walks Delgado (371,330,-457), Church (-208,330,-336)
   and Jones (45,330,-374), all facing (140,140,-1400).
6. `Ambush` (121-131):
   - activates `emboscada`, an infinite generator with 3 simultaneous enemies. Its spawn points
     are south of the control room: explosive Enemy (170,135,-3697), Enemy82 (-38,135,-3697) and
     Enemy108 (-242,135,-3733); melee Enemy83 (702,123,-2655) and Enemy175 (-417,126,-2598);
   - schedules Cole's chats at +20/40/60/80/100 s: `Mission_Alk_Bunker_01_ACombat`..`ECombat`
     (files deleted, rolling time back, restoration started, almost done, "hurry, Cole");
   - stops the generator at +120 s (138-140).
7. `emboscada_0` → `EnemiesDeath` → `FCombat` → `QuakeOff`, which closes `ScreenView`
   (`mapcallbacks.lua:208-211`, `mapinit.lua:142-158`). `FinalTalk` re-activates Cole and hides the
   fake (160-167). The `End` chat follows, then `OpenLastDoor` opens `LastDoor` (4,586,2257)
   toward `New_Level` (35,698,5184).

#### G3.2 "Stay in own body": Temporal restoration (Cole)

**Premise (canon).** Cole rolls the server back in time to restore the deleted files
(`mission_alk_bunker_01_bcombat0`, `ccombat0`). The distortion she warns about
(`mission_alk_bunker_01_cole0`) draws the cultists to her. The hack advances only while she
is at the console.

- Route: from the discovery point into the control room (sector `S_10`, 30,257,-384; the
  `ScreenView` monitor wall is at 56,410,-346) to the console at (400,330,-138).
- Objectives:
  1. "Reach the console". This replaces the AI walk; Cole's line `talk_cole_use_power_cole1`
     plays on arrival.
  2. "Restore the files": a progress counter (0-100 %, shown with `SetMsgText`) advances while
     Cole is within a radius of `ColePos` (about 120 units [guess]). If she leaves to fight,
     the counter pauses. At 20/40/60/80/100 % the vanilla chats `ACombat`..`ECombat` play
     instead of the timers.
  3. Optional "fold surge" at 60 %: one wave rises (`Emerge`) inside the control room
     (`AreaTeam41`/`AreaTeam65`) and goes for Cole, so the defenders must turn around.
  4. At 100 %, `MapInit.DeactivateEnemies` runs, then the vanilla end (`FCombat` → quake →
     `End`; Cole reports the breach location, `mission_alk_bunker_01_end11`).
- Enemies: the vanilla `emboscada` generator (unchanged). The surge goes into a separate group.
  While Cole is away from the console, `EnemyGen.IncreaseMaxEnemies("emboscada")` could
  temporarily raise the pressure [I].
- Voice beats:

| Beat | Keys |
|---|---|
| Console reached | `talk_cole_use_power_cole1`, `talk_ross_use_power_cole2` |
| Progress (vanilla, now progress-driven) | `mission_alk_bunker_01_acombat0`/`1`, `bcombat0`, `ccombat0`, `dcombat0`, `ecombat0` |
| Surge | `talk_cole_forboding_sound1` (psi spectrum off the scale), `talk_cole_gencom_modern1` |
| Cole attacked | `talk_jones_help_cole*`, `talk_delgado_help_cole*`, `talk_church_help_cole*`, `talk_rawlings_help_cole*` |
| End | `mission_alk_bunker_01_fcombat0`, then the vanilla `Mission_Alk_Bunker_01_End` |

#### G3.3 Engineering and risks

- When Cole is human and chose (b), skip the AI walk (`mapinit.lua:73`), the creation of
  `FakeCole` (102-113) and `DelayedDeactivate` (115-119).
- **Crash risk:** `QuakeOff` (148) and `FinalTalk` (163) call
  `Game.GetEntity(TeamTalk.FacialAlias.Cole)`. Without the fake the alias is nil, so both
  lines must be guarded. If the alias were set to "Cole", `FinalTalk` would hide the real Cole.
- Replace the fixed `AddScheduledFunc` timers (122-128) with a 0.25 s progress poll.
- Optional: put the human Cole into the `HackCom` action while she stands still at the
  console, so that other players see the hack animation. It is FP for her.
- `MoveSquadAndStartCombat` and the Ross/Rawlings AI walks only work on AI bodies. Human-held
  Delgado, Church, Jones, Rawlings or Ross get a subtitle prompt instead. `IgnoreUsrControl` is
  set only on `UsrEntity(0)`, so the co-op layer must apply it to the human who holds Ross.
- If Cole chose (a): vanilla `FakeCole`, and the player takes a free body.

#### G3.4 Feasibility: easy-medium

Check in game:

- the console radius;
- that `HackCom` works on a human-held body;
- `emboscada` spawn points with 4 humans in the room;
- the tutorial-free timing of the chats.

---

### Other separations and solo moments in Act 1

| Level | Moment (script) | Kind | Co-op note |
|---|---|---|---|
| alk_desert | Ross orders "Alpha, Omega, two groups" (`mission_alk_desert_beginning3`) | flavor only, the squad stays together | none |
| alk_desert | Black's TK door played by AI: `AreaTriggerBlack` → `OpenTheTkDoor` (`mapinit.lua:84-93`) | Black gate | prompt a human Black, or let the AI do it |
| alk_tomb | `TombCollapses` QTE for Ross (`mapscenes.lua:28-180`) | QTE | others watch |
| alk_tomb | Ross AI-walked after the goodbye (`mapinit.lua:147-164`) | solo lock on `UsrEntity(0)` | lock the human holding Ross only |
| alk_tomb | Black TK doors 1 and 2 by AI (`mapinit.lua:180-208`) | Black gate | as in alk_desert |
| alk_city | Black TK door `cultista_destruye_esta` (`mapinit.lua:30-43`) | Black gate | as in alk_desert |
| alk_city | Doors close behind the squad: `Placeholder_door_1` (`AreaTrigger863_0`, `mapcallbacks.lua:87-90`), `placeholder_door_2` (`cuartos_cultistas_b_0` 151-158, `AreaTrigger366_0` 49-52) | stragglers can be shut out | close only when all humans are past |
| alk_bunker_01 | `AreaTrigger_Begin_1` closes `PuertaEntrada` and sets `blockerEntrada` (`mapcallbacks.lua:94-98`) | stragglers shut out | same |
| alk_final | `puerta_final` closes at `AreaTrigger_3` (`mapcallbacks.lua:80-84`) | stragglers shut out | same |
| alk_final | `StartAICinematic` turns off all AI during the `BEnd` chat (`mapinit.lua:123-147`) | AI-only freeze | humans keep control |
| alk_final | Ross walks alone to the stone after `AreaTriggerFistro_0` (Child calls him, Black begs him not to go: `mission_alk_final_cend1`..`4`; `mapcallbacks.lua:66-70`) → `RossDeath` (62-64) | narrative separation, short | optional mini-hold: the others hold the base of the stone against fliers spawned with `CreateWithAI` (`cultistas_voladores` is already spent, `mapcallbacks.lua:107-110`). The cutscene `RossDeath` has no Church or Cole actor, but Church speaks off-screen (`scene_alk_final_rossdeath9`, `12`), which fits them fighting at the edge: a one-line subtitle is enough. |
| alk_final | `RossDeath` → `RossDeathB` (FP_Delgado) → WWII_BigGates (`mapscenes.lua:93-99`) | Ross's body is lost | Ross's player becomes the first spirit and takes a free body (only option (a)); the canon matches |

### Summary of proposals

| Split | Own line | Where | Reunion | Rating |
|---|---|---|---|---|
| G1 | Alpha's road: (A) perimeter recon on the storm plateau, (B, optional) sweep of the outpost's east tunnel, (C) pinned in the sealed pocket in alk_city | alk_tomb `S_10`..`S_31`/`S_11`; bunker_00 `S_28`..`S_09`; alk_city `S_10`/`S_12` | vanilla `AreaTrigger119` + `EnableAlpha` + `Mission_Alk_City_Reunion` | C easy-medium, A medium, B hard |
| G2 | Church and Black keep the blood door open in the entrance hall | bunker_00 `S_00`..`S_04`, `AreaTeam24` | alk_city start (vanilla spawn next to Ross) | medium |
| G3 | Cole's temporal restoration, progress tied to her presence at the console | bunker_01 control room, console (400,330,-138) | vanilla `FinalTalk` | easy-medium |

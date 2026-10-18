# Clive Barker's Jericho: campaign structure for co-op planning

**Source analysed:** decompiled Lua 5.1 scripts in `work/src/` (private, next to this repo; not published). All analysis was read-only, and the game was not run.

**Path conventions:**
- Paths starting `scripts/` are relative to `src/scripts/`.
- Paths written as `<level>/<file>` are relative to `src/levels/<level>/scripts/`.
- Line numbers refer to the decompiled files.

**Labels:**
- **[O] Observed:** read directly in the scripts.
- **[I] Inference:** a reasonable conclusion that the scripts do not state directly.
- **[U] Unknown:** not decidable from Lua. This is usually engine (C++) behaviour or binary map data.

**What "orphan" means.** Many levels define `MapCallbacks.*` functions that call `SaveGame.NewLevel(...)` (often `"Cru_Labyrinth"` or `"Cru_River"`). When nothing in that level's Lua data tables refers to such a function, it is listed as **orphan** (dead, debug or leftover code). The data tables checked are `mapareatriggers.lua`, `mapphysiclogic.lua`, `mapenemiesgroup.lua` and the others. Binary map data could in theory still refer to them [U].

---

## 1. Campaign level order

### 1.1 Canonical list [O]

The order comes from two tables:
- `scripts/missionmaker.lua:20-55`: the `MissionMaker.files` table for the retail build. It is used by `MissionMaker.LoadNexLevel` (`missionmaker.lua:122-133`) for automated level cycling.
- `scripts/menu/menu.lua:226-228`: the `Menu.UnlockHistoricMissions` table, which writes the same list into `VisitedLevels`, grouped by era.

The `SaveGame.MsgKeys` table (`scripts/missions/savegame.lua:60-94`) lists the same 33 levels in the same order. That table only maps loading-screen strings.

**How the next level is chosen.** No central table decides the next level. Each level hard-codes its successor:
- **Normal path:** `SaveGame.NewLevel(name)` (`savegame.lua:304-315`) fades out and schedules `SaveGame.NewLevelNow` (`savegame.lua:328-366`). That function:
  - clears the save vars (`Game.DelSaveVars("")`),
  - updates `VisitedLevels` (`CheckVisitedLevels`, 255-288),
  - saves the weapon config,
  - hard-saves, then calls `SaveGame.LoadLevel` (`239-251`, which calls `Game.LoadLevel("Levels/"..name)`).
- **Direct path:** level scripts that call `SaveGame.NewLevelNow(...)` skip the fade.

The 34th folder, `levels/menu`, is the main menu.

### 1.2 Order with the real transition call sites

**Act 1 — Al-Khali (modern era, prefix `alk_`)**

| # | Level | Real transition to next level [O] | Notes |
|---|---|---|---|
| 1 | alk_desert | `alk_desert/mapcallbacks.lua:19-21` `NextLevelTrigger_0` → `Alk_Tomb` | `New_Level_0` → `Alk_Bunker_00` (15-17) is an orphan, not a branch |
| 2 | alk_tomb | cutscene `BloodDoor` → `MapScenes.OnEnd_BloodDoor` → `NewLevelNow("Alk_Bunker_00")` (`alk_tomb/mapscenes.lua:182-188`) | demo build (`RetailType==2`) goes back to the title instead |
| 3 | alk_bunker_00 | `alk_bunker_00/mapcallbacks.lua:86-89` `AreaTrigger_3` → `ALK_City` | `NexLevel_0` → `Cru_Labyrinth` (145-147) is an orphan |
| 4 | alk_city | `alk_city/mapcallbacks.lua:102-104` `AreaTrigger_0` → `Alk_Bunker_01` | |
| 5 | alk_bunker_01 | `alk_bunker_01/mapcallbacks.lua:83-85` `AreaTrigger_4` → `Alk_Final` | `AreaTrigger_3` (79-81) and `NexLevel_0` are orphans |
| 6 | alk_final | `Scene.Play("RossDeath")` → `RossDeathB` → `MapScenes.OnEnd_RossDeathB` → `NewLevelNow("WWII_BigGates")` (`alk_final/mapscenes.lua:93-95`) | `AreaTrigger_0` and `Next_Level_0` → `Cru_River` are orphans |

**Act 2 — WWII (prefix `wwii_`)**

| # | Level | Real transition [O] | Notes |
|---|---|---|---|
| 7 | wwii_biggates | `wwii_biggates/mapcallbacks.lua:18-20` `AreaTrigger146_0` → `WWII_PillBoxes` | `New_Level_0` → `WWII_Mosque` is an orphan |
| 8 | wwii_pillboxes | `wwii_pillboxes/mapcallbacks.lua:12-14` `AreaTrigger181_0` → `WWII_Mosque` | |
| 9 | wwii_mosque | scene `BritishComando` → `OnEnd_BritishComando` → `NewLevelNow("WWII_Mosque_Inside")` (`wwii_mosque/mapscenes.lua:18-20`) | a wired `next_level_0` trigger also exists (`mapcallbacks.lua:146-148`), placed near the start; probably a leftover [I] |
| 10 | wwii_mosque_inside | `wwii_mosque_inside/mapcallbacks.lua:32-34` `NewLevel_0` → `WWII_Vigil` | |
| 11 | wwii_vigil | `MapInit.NextLevel` (`wwii_vigil/mapinit.lua:47-49`), scheduled after the fuel-tank explosion → `WWII_Vigil_Inside` | |
| 12 | wwii_vigil_inside | `PsichicCommander.EndOfBitch` (`scripts/chars/psichiccommander.lua:357-378`) → scene `RawlingsTorture` → `MapScenes.EndRawlingsTorture` → `NewLevelNow("WWII_Brandenburg")` (`wwii_vigil_inside/mapscenes.lua:32-35`) | |
| 13 | wwii_brandenburg | `MapInit.EndOfMap` → `NewLevelNow("Cru_River")` (`wwii_brandenburg/mapinit.lua:190-194`) | |

**Act 3 — Crusades (prefix `cru_`)**

| # | Level | Real transition [O] | Notes |
|---|---|---|---|
| 14 | cru_river | Delgado door `Trigg_DelgadoDoor_0` (`mapcallbacks.lua:284-287`) → `MapScenes.CrossOverBridge` → scene `BridgeCollapses` → `OnEnd_BridgeCollapses` → `NewLevelNow("Cru_Labyrinth")` (`cru_river/mapscenes.lua:132-146`) | `NexLevel_0` is an orphan |
| 15 | cru_labyrinth | Black-only object `o1007_0` (`mapcallbacks.lua:394-396`) → scene `CruzadersSpeech_B` → `NewLevelNow("Cru_Sewers")` (`mapscenes.lua:174-176`) | an active `AreaTrigger5_0` (79-81) also goes to Cru_Sewers |
| 16 | cru_sewers | `MapCallbacks.NextLevel` (`cru_sewers/mapcallbacks.lua:248-257`) → `Cru_Keep` | only fires when `Team.isWithTheTeam()` is true, i.e. switching is enabled |
| 17 | cru_keep | `cru_keep/mapcallbacks.lua:17-19` `AreaTrigger102_0` → `Cru_Catacomb` | |
| 18 | cru_catacomb | `cru_catacomb/mapcallbacks.lua:335-337` `Next_Level_0` → `Cru_Chapel` | |
| 19 | cru_chapel | `Maltheus.OnAfterDeath` (`scripts/chars/maltheus.lua:470-482`) → `NewLevel("Rom_Outskirts")` after 25 s; `UseAltair_0` (`cru_chapel/mapcallbacks.lua:241-247`) also goes there | |

**Act 4 — Rome (prefix `rom_`)**

| # | Level | Real transition [O] | Notes |
|---|---|---|---|
| 20 | rom_outskirts | `rom_outskirts/mapcallbacks.lua:167-169` `AreaTrigger_NextLevel_0` → `Rom_Caldarium` | `NexLevel_0` is an orphan |
| 21 | rom_caldarium | `rom_caldarium/mapcallbacks.lua:164-166` `AreaTrigger925_0` → `Rom_Tepidarium` | `AreaTrigger_3` → `"Rom_Palace"` (218-220) is an orphan, and no level of that name exists |
| 22 | rom_tepidarium | `rom_tepidarium/mapcallbacks.lua:161-163` `AreaTrigger_3` → `Rom_Palace_01` | |
| 23 | rom_palace_01 | `rom_palace_01/mapcallbacks.lua:142-148` `AreaTrigger90_0` → `Rom_Palace_02` | `AreaTrigger_3` → `Rom_Coloseum` is an orphan |
| 24 | rom_palace_02 | `AreaTrigger_3` (`mapcallbacks.lua:175-178`) → scene `TheTrap` → `OnEnd_TheTrap` → `NewLevelNow("Rom_Coloseum")` (`rom_palace_02/mapscenes.lua:23-25`) | |
| 25 | rom_coloseum | `rom_coloseum/mapcallbacks.lua:22-24` `AreaTrigger376_0` → `Rom_Chamber` | `"Rom_coloseum_inside"` (56-58) is an orphan |
| 26 | rom_chamber | `Vicus.OnVicusDead` (`scripts/chars/vicus.lua:428-436`) → `MapInit.IncidentalEnd` (`rom_chamber/mapinit.lua:75-83`) → `NewLevel("Sum_Ziggurat_01")` after 26 s | |

**Act 5 — Sumer (prefix `sum_`)**

| # | Level | Real transition [O] | Notes |
|---|---|---|---|
| 27 | sum_ziggurat_01 | `MapInit.Teletransport` (`sum_ziggurat_01/mapinit.lua:303-307`) → `Sum_Ziggurat_02` after 25 s | chain: `trigEstatuas` OnAllInside → `trigEstatuas_0` (`mapcallbacks.lua:283-289`) → `EnableStatues` → `Teletransport` |
| 28 | sum_ziggurat_02 | `sum_ziggurat_02/mapcallbacks.lua:57-59` `AreaTrigger26_0` → `Sum_Ziggurat_03` | |
| 29 | sum_ziggurat_03 | `sum_ziggurat_03/mapcallbacks.lua:139-145` `AreaTrigger_4` → `Sum_Ziggurat_04` | demo build → `Menu.BackTitle` |
| 30 | sum_ziggurat_04 | `trigUrn_0` (`sum_ziggurat_04/mapcallbacks.lua:326-332`) → `Sum_Ziggurat_Meat` after 39 s | `NextLevelLoad_0` → `Sum_Ziggurat_05` (231-233) is wired but appears to be a leftover from before the level was split [I] |
| 31 | sum_ziggurat_meat | `MapInit.ElevateUrn` (`sum_ziggurat_meat/mapinit.lua:52-56`) → `Sum_ziggurat_05` after 32 s | |
| 32 | sum_ziggurat_05 | cutscene-only level: `Scene.Play("IntoTheUnknown")` (`mapinit.lua:1-9`) → `MapScenes.OnEnd_IntoTheUnknown` → `NewLevelNow("Sum_End")` (`mapscenes.lua:32-34`) | |
| 33 | sum_end | `EvilFirstBorn.KillFirstBornScene` (`scripts/chars/evilfirstborn.lua:579-587`) → `MapInit.EndOfGame` (`sum_end/mapinit.lua:52-56`) → TheEndC → TheEndD → credits → `NewLevelNow("Menu")` (`mapinit.lua:92`) | |

---

## 2. Squad mechanics

### 2.1 Roster [O]

`Team.main` (`scripts/chars/team.lua:5-60`) defines two teams:
- **Alpha:** Jones, Cole, Delgado.
- **Omega:** Church, Rawlings, Black.

The same functions also set HUD icons (`Team.Icons`, 39-46) and register the AreaManager callbacks (48-54).

`init.Team` in `scripts/init.lua:271-278` is overridden per level by `levels/<l>/scripts/map.lua` (`init.Team = {...}`), which decides which characters are loaded at all.

**Ross** is an extra playable character:
- He is used only in the Al-Khali levels: `init.Team` there includes "Ross", and the spawn tables carry `bRoss = true`.
- `Team.CreateMapSpawnPlayers` sets `Team.MainChar = "Ross"` when a spawn entry has a Ross position (`team.lua:1309-1318`).
- Ross's act class has switching disabled: `ac.HoldSwitchChar = "Team.EmptyHold"` and `ac.SwitchChar = "Team.SwitchCharacterDeactivated"` (`scripts/chars/ross.lua:271-272`).
- [O+I] So in Al-Khali the player is always Ross and cannot possess squad members. Possession starts after Ross's death in the `RossDeath`/`RossDeathB` cutscene of alk_final. RossDeathB is filmed from `FP_Delgado`, and WWII_BigGates starts as Delgado.
- From WWII on, Ross has no body in the spawn tables.

### 2.2 Spawn and the initial controlled character [O]

1. `Team.CreateMapSpawnPlayers()` (`team.lua:1247-1330`) is called from each level's `MapSpawnPlayers.main`.
2. It picks the `MapSpawnPlayers.Positions` entry whose `Id` matches the save var `<level>.Spawn.Point` (via `Team.GetSavedSpawnPlayerPoint`, 1243-1245).
3. That entry decides:
   - which of the 6 members exist (`bJones`, `bCole` and the other flags),
   - their positions,
   - the initially controlled member (`Init` index into `{Jones, Cole, Delgado, Church, Rawlings, Black}`, line 1328, or Ross).
4. `Team.CreateTeam()` (62-95) creates the main character first, then the rest.
5. `Team.CreateMainChar` (97-133) gives the first-created character:
   - `o.UsrControl = 0` (123),
   - the camera `MainCam`, via `Game.SetCam(0, ...)` (103-104),
   - `Input.SetActionSet("Walk")` (109).
6. Every member is registered with `Game.SetTriggeredEntity(index, o)` (131) so that area triggers can report it.
7. `AISquad.Create()` (`scripts/ai/aisquad.lua:19-42`) creates AI for every member, with `withAI = 0` for the one named by `AIGen.GetPlyName()`. That function is `Game.UsrEntity(0).Name` (`scripts/ai/aigen.lua:23-29`).

[O] The controlled character after a checkpoint load comes from the spawn table, not from the save.

### 2.3 How switching works [O]

**Input layer.** No Lua code binds the switch button; `Input.Bind` appears only in `init.lua:345` and quickconsole. The engine calls the act-class callback names:

| Callback | Set by | Purpose |
|---|---|---|
| `ac.SwitchChar` (tap) | `Team.SetTeamSwitch` (`team.lua:1403-1409`), or directly in `jones.lua:392-393`, `cole.lua:357-358`, `rawlings.lua:559-560` | `"Team.SwitchCharacter"` |
| `ac.HoldSwitchChar` (hold → radial menu) | same | `"Team.SwitchTeam"` |
| `SetTeamSwitch` calls | `delgado.lua:411`, `church.lua:387`, `black.lua:401` | |

**Tap.** `Team.SwitchCharacter(EntityName)` (`team.lua:324-335`) switches to `e.SelectedEntity`, the squad member under the crosshair, if that is one of the six. Otherwise it uses an auto-selected object.

**Hold.**
1. `Team.SwitchTeam` (437-444) sets `Team.Actual` to Alpha or Omega.
2. `Team.SchedTeamInfo` (524-529) refreshes the radial menu every 0.25 s while `InCtrl_SwitchMen ~= 0`.
3. `Team.SwitchTeamAlpha`/`SwitchTeamOmega` (531-569) fill the menu slots (`Sele_Up/Left/Right/Down_*`) through `Team.SetIdChar` (496-522). `OnSelect = "Team.SwitchSoldier"` is set only if `Team.IsPlayerAvaliable(Name)`. A dead member is shown with an override icon and cannot be selected.

**Core function: `Team.SwitchSoldier(EntityName, Data)` (`team.lua:571-605`).** Its guard is `IsPlayerAvaliable(Data)`. It then:
1. reequips if the old character is out of ammo;
2. calls `Threads.DectivateThread` both ways (`scripts/thread/threads.lua:58-62`);
3. on the new character: `t.UsrControl = 0`, copies the input state, `t.oAI.bEnable = false`, `t:ResetControl()`;
4. on the old character: `f.UsrControl = -1`, `Weapons.SaveWeaponConfig()`, `f.oAI.bEnable = true`;
5. calls `Team.SwitchTeam(Data)`;
6. calls `Team.TravelCam(f, t)` (1349-1374). This builds the "soul flight" camera path, `Game.SetCam(0, "Cameraman")`, **`Game.SetTimeSpeed(0.005)`** (a global slow-down) and `Input.SetActionSet("Inactive")`;
7. calls `Team.OnSwitchChar[Data](t)` and `Team.ResetUsrAnim`.

When the camera path ends, `Team.EndTravelCam` (1376-1396) restores `MainCam`, time speed 1, the "Walk" action set and the HUD, then calls the optional `Team.EndSwitchCallback`.

**Engine-side team swap.** The AreaManager `onTeamSwitching` → `Team.OnTeamSwitching` (618-624) → `AISquad.OnSwitchPlayer(new, old)` (`aisquad.lua:219-227`). It:
- enables and disables the AI,
- calls `AISquadTeamPrinc.AssignTeam(newEntityPly.oAI.Team)` (`aisquadteamprinc.lua:7-13`), which swaps the "player team" and "second team",
- re-executes the old character's order.

**Per-character hooks `Team.OnSwitchChar[...]`:**

| Character | Hook | What it does |
|---|---|---|
| Delgado | `delgado.lua:566-579` | sprint lock, weapon slot, Ababanili FP state on entity `"0FP_Delgado"` |
| Church | `church.lua:532-534` | weapon slot |
| Black | `black.lua:804-820` | TK/LED state on `"0FP_Black"` |
| Jones, Rawlings | `jones.lua:722`, `rawlings.lua:913` | empty |
| Ross | `ross.lua:16` | registered |

**Unused alternative switch functions.** `Jones.SwitchSoldier` (`jones.lua:776-799`), `Cole.SwitchSoldier` (`cole.lua:575-599`) and `Rawlings.SwitchSoldier` (`rawlings.lua:997-1020`) also set `UsrControl`. No code calls them [O].

### 2.4 How AI takes over the others [O]

- **AI flag:** every non-controlled member has `oAI.bEnable = true`. It is set in `Team.SwitchSoldier` and `AISquad.OnSwitchPlayer`.
- **Behaviour:** `scripts/ai/aimembersquad.lua` (1470 lines) and `aisquadteam*.lua` drive it, plus engine "AreaManager" sectors (`mapareateam.lua` per level).
- **Main and second team:**
  - The AreaManager keeps a "Main" team (the player's team, `oActual`) and a "Second" team (`oSecondTeam`).
  - Orders: `Team.FollowMeMain/Side`, `HoldPosMain/Side`, `SelectMain/Side`, `SendMain/Side` (`team.lua:762-1009`).
  - On combat start or end: `Team.StartCombat/EndCombat` (842-868).
  - `AISquad.OnChangeAdvancePlayerTeam` and `...SecondTeam` (`aisquad.lua:266-310`) move the AI teams between sectors.
- [I] AI "follow" logic is defined relative to the single human player and the player's team. `AIMemberSquad.IsPlayer`/`IsBusy`/`ExecuteOrder` compare with `AIGen.GetPlyName()` (`aimembersquad.lua:81-105`, 602-627).

### 2.5 Death and revive of the controlled character [O]

1. `Team.OnDeath` (`team.lua:184-209`): if the dead member has `UsrControl == 0`, it sets `owc.ForceSwitchCharMenu = 1` and schedules `Team.CheckGameOver` after 2 s.
2. `Team.CheckGameOver` (264-308): if `Team.isWithTheTeam()` (the player's class uses `Team.SwitchCharacter`), it auto-switches to the healthiest living member. Otherwise it is game over.
3. Special case for Ross: if Rawlings is alive, Rawlings becomes invulnerable and Ross is revived after 10 s (296-302).
4. `Soldier.OnDeath` (`scripts/chars/soldier.lua:46-61`) puts the member into Agony and makes the body "usable" for a revive (`Team.AssignReviveFunction`, `team.lua:337-341`).
5. `Team.CanCure(obj)` (353-356) requires **`obj.UsrControl < 0` (or Ross)**. A human-controlled body cannot be revived by another character in the current code. The healer must have `usr.UsrControl >= 0` (`CurePlayer`, 358-368).
6. Rawlings' ghost-heal and `Team.ReviveAll` (403-435) revive AI bodies. Many level scripts call `ReviveAll` at checkpoints.

### 2.6 How "available for switching" is enforced [O]

Five layers. A member can be switched to only if all of them allow it.

1. **Existence, set per level and checkpoint:** `init.Team` in `map.lua` and the `b<Name>` flags in `mapspawnplayers.lua`.
2. **`Team.IsPlayerAvaliable(Nam)`** (`team.lua:448-454`). The rule is `not Team.UnavaliablePlayers[Nam] and Life > 0 and bActive`.
   - `Team.UnavaliablePlayers = {}` is set when team.lua loads (446).
   - Level scripts write single keys or replace the whole table. Examples: `wwii_biggates/mapinit.lua:2-8`, `rom_outskirts/mapinit.lua:75-88`, `scripts/fx/sumteleport.lua:77-99`, `evilfirstborn.lua:515-534`.
   - `bActive = false` hides a member. It is used to remove members from a section.
   - [O] `.Active = 0` is a different field. It is used in `rom_caldarium/mapcallbacks.lua:189-197` and in `Scene.HideThis` (`scripts/missions/scene.lua:614-620`). It pauses an entity without making it unavailable [I].
3. **Switch lock on the controlled character's class.**
   - `Team.ResetTeamSwitch(ac)` (1411-1417) sets `SwitchChar = "Team.SwitchCharacterDeactivated"` and the save var `<Name>.CanSwitch = "0"`.
   - `Team.SetTeamSwitch(ac)` (1403-1409) undoes it.
4. **Orders lock.** `Team.ResetTeamOrders/SetTeamOrders` (1419-1449) use the save var `<Name>.CanOrders`.
   - Both save vars are restored on level load by `Team.CheckInitSectors` (137-179).
5. **Solo mission.** `AreaTriggers.StartSoloMision()` / `EndSoloMision()` (`scripts/missions/areatriggers.lua:152-168`) apply layers 3 and 4 to `Game.UsrEntity(0)`'s class. They also hold or release both AI teams and set the flag `AreaTriggers.SoloMision`.

**Levels that use these locks [O]:**

| Mechanism | Levels |
|---|---|
| `UnavaliablePlayers` | wwii_biggates, wwii_pillboxes, wwii_mosque, wwii_brandenburg, rom_outskirts, sum_ziggurat_01, sum_ziggurat_02, sum_end (via evilfirstborn), and the Sumer teleports (sumteleport.lua) |
| `Reset/SetTeamSwitch` | cru_sewers (mapscenes), rom_palace_01 |
| `StartSoloMision` | wwii_pillboxes, rom_caldarium (`EnterFireArea`) |
| Forced `Team.SwitchSoldier` | rom_outskirts (`mapinit.lua:71`), sum_ziggurat_01 (`mapinit.lua:109`), sum_ziggurat_02 (`mapinit.lua:14`), sum_end (`evilfirstborn.lua:261`, `508`) |

### 2.7 APIs involved

| Namespace | Calls seen | Role |
|---|---|---|
| `Game.*` | `UsrEntity(i)`, `GetEntity`, `CreateEntity`, `SetCam(i, name)`/`GetCam(i)`, `SetTimeSpeed`, `SetTriggeredEntity`/`GetTriggeredEntity`, `GetAreaManager`, `AddScheduledFunc`/`DeleteScheduledFuncs`, `Get`/`Set` (globals), `CreateSaveVar`/`SetSaveVar`/`GetSaveVar`/`DelSaveVars`, `LoadLevel`, `SoftSaveAutoSave`/`HardSaveGame` | entity, camera, time, save, scheduler |
| Entity fields | `UsrControl` (-1 = AI, ≥0 = user index), `IgnoreUsrControl`, `oAI.bEnable`, `bActive`, `Active`, `Life`, `Invulnerable`, `SelectedEntity`, `InCtrl_*`, `owc.*`, `Sele_*` (radial menu), `FPSEntity`/`oFPSEntity` | possession state |
| `Act.*` | `GetClass(name)` (act class, with `SwitchChar`/`HoldSwitchChar`/order callbacks), `CreateClass`, `SetAct`/`GetAct` (scene events) | per-character input callbacks |
| `AI.*` / `AISpec` / `AITeamList` / `AIGen` | `AI.IniAI` (`init.lua:168`), `AISpec.CreateAI`, `AITeamList.InsertMember`, `AIGen.GetPlyName`, `AIGen.GoAndAction` | AI creation and teams |
| `Team.*` | see 2.3 to 2.6 | squad logic (Lua) |
| `Input.*` | `SetActionSet("Walk"/"Inactive"/"Astral"/"Menu")`, `GetActionSet`, `Bind(0, ...)` | **global** input mode; `Bind` takes a pad index |
| `Scorer.*` | `Fade(0, ...)`, `Clear(0)`, `QTE*`, `SetMsgText` and others | HUD of viewport 0 |

---

## 3. Per-level squad availability and scripted sequences

**Column meanings:**
- **Present:** loaded and active at some point.
- **Switchable:** reachable by the human under the original rules.
- **Max players (if all present members were humans):** the number of present members, capped later by the owner's rule (section 4).
- **Initially controlled:** the spawn-table `Init` value at the first checkpoint.

All cells are [O] unless marked otherwise.

### Act 1 — Al-Khali (player is Ross; no possession)

| Level | Present | Switchable (original) | Splits / forced sections | Deaths / leaves / joins | Cutscenes / QTE / boss |
|---|---|---|---|---|---|
| alk_desert | 6 + Ross (Ross controlled) | none (Ross `SwitchCharacterDeactivated`); orders disabled for the tutorial (`mapinit.lua:19` `ResetTeamOrders(Ross)`) | tutorial `MapInit.TestTap` hard-coded to Ross (`mapinit.lua:38-82`) | — | intro chain TheDreamA → B → C → HelicopterTrip → FlashBackA/B/C → Landing (`mapinit.lua:10-12`, `mapscenes.lua:3-88`); Black TK door played by AI (`mapinit.lua:84-93`) |
| alk_tomb | 6 + Ross, then Alpha removed | none | **Alpha leaves:** `MapInit.StartSayGoodbye` (`mapinit.lua:102-149`) sets Jones/Cole/Delgado `bActive=false` (106-108) and spawns Fake* walkers; Ross is AI-walked with `IgnoreUsrControl` (147-162); spawn Id 2 has only Church/Rawlings/Black/Ross | Alpha departs (team split, Alpha off-map) | **QTE (Ross)** in scene `TombCollapses` (`mapscenes.lua:121-144`); scene `BloodDoor` (Church's blood door) |
| alk_bunker_00 | Ross + Rawlings only (`map.lua:5`) | none | 2-man level | Muriel (NPC) found | scene `MurielsTale` (`mapcallbacks.lua:59-61`, `mapscenes.lua:26-33`) |
| alk_city | 6 + Ross; Alpha hidden at start | none | `MapInit.DisableAlpha` (`mapinit.lua:17-24`, from `AreaTriggerInit`) until `EnableAlpha` (7-15, from `AreaTrigger119_1`, enabled by group death `mapcallbacks.lua:198-204`) | Alpha rejoins | Black TK door (`mapinit.lua:26-43`); orders tutorial reads `UsrEntity(0).owc` (47-72) |
| alk_bunker_01 | 6 + Ross | none | Ross AI-walked (`MapInit.GoToRawlings` `mapinit.lua:52-64`, trigger only for "Ross" `mapcallbacks.lua:231-235`); Cole replaced by FakeCole hacking a console, `Cole.bActive=false` during a ~120 s ambush (`mapinit.lua:102-140`), restored in `FinalTalk` (162) | Muriel Green killed `Life=0` (`mapinit.lua:69-71`) | ambush wave defence |
| alk_final | 6 + Ross | none | `StartAICinematic`/`EndAICinematic` disable and re-enable all AI (`mapinit.lua:50-57`, 134-147) | **Ross dies** in scene `RossDeath` → `RossDeathB` (`mapscenes.lua:37-149`; RossDeathB filmed from `FP_Delgado`) | First Born appearance; RossDeath cutscenes |

### Act 2 — WWII (possession unlocked progressively)

| Level | Present | Switchable (original) | Splits / forced sections | Deaths / leaves / joins | Cutscenes / QTE / boss |
|---|---|---|---|---|---|
| wwii_biggates | 6 (start Delgado) | Delgado, Black; Church after `BloodWarTutorial` (`mapinit.lua:90`); `UnavaliablePlayers = {Jones, Cole, Rawlings, Church}` (`mapinit.lua:2-8`); **Jones, Cole and Rawlings are never unlocked in this level** | **Church-only gate:** `TestWard` activates the next enemy group only when `UsrEntity(0).Name=="Church"` (`mapinit.lua:100-114`); Cole hacks the exit door by AI script (139-146) | — | scene `Conversation` (`mapinit.lua:24-26`); TK object `UseJustEntity "Black"` (`mapphysiclogic.lua:20-42`) |
| wwii_pillboxes | 6 (start Church; Cole at checkpoint 1) | Jones, Rawlings and Cole locked (`mapinit.lua:7-11`); Cole freed in `TestCole` (44); Rawlings freed in `StartRawlingsTutorial` (155); Jones locked for the whole level | **Solo:** after scene `DelgadokillsRawlings`, `AfterRawlingKilled` → `StartSoloMision` (`mapinit.lua:126-130`) until `RestoreSquad` → `EndSoloMision` (470-522); `DisableAILoop` keeps all AI off (`mapscenes.lua:145-195`); **Rawlings-only gate:** `ActivateBigFuckerGroup` waits until `UsrEntity(0)==ERawlings` (`mapinit.lua:615-623`) | Rawlings set `Life=0` in a cutscene, revived via `TestCure` (`mapscenes.lua:112-118`, `mapinit.lua:136-147`); Jones set `Life=0` for the revive tutorial (`KillSomeone`, 605-613) | pillboxes are Cole-only (`scripts/chars/wwii_pilbox_a.lua:119`); **QTE (Cole)** scene `Pathofsouls` (`mapscenes.lua:56-110`); Nazi Bitch fight (not catchable here) |
| wwii_mosque | 6 (start Church/Black) | Jones locked (`mapinit.lua:4`) until `StartJonesTutorial` (56) | Jones-only TK lever `o175` (`mapphysiclogic.lua:20-42`; `TestJones` checks the "Astral" action set, `mapinit.lua:60-85`) | — | scene `BritishComando` (`mapscenes.lua:18-20`) |
| wwii_mosque_inside | 6 | all 6 | — | NPC Tuck exploded (`mapinit.lua:64-74`) | scene `BritishComandoSpeech` (`mapinit.lua:40-42`); Black ghost bullet on the bomb (`mapinit.lua:97-127`) |
| wwii_vigil | 6 | all 6 | astral puzzle flags (`mapcallbacks.lua:13-23`); a "team splits up" design note only (63-68) | — | fuel-tank explosion |
| wwii_vigil_inside | **Cole, Church, Rawlings only** (`map.lua`, spawn) | the 3 present | 3-man team; `MoverFaster` teleport (`mapinit.lua:48-61`) | Nazi Bitch captured | **boss Nazi Bitch** (`PsichicCommander`); **QTE (Rawlings)** scene `RawlingsTorture` (`mapscenes.lua:18-262`) |
| wwii_brandenburg | 6; Cole and Rawlings hidden or used as props | Cole, Rawlings unavailable (`mapinit.lua:38-59`), not cleared before the level ends | **Church-only gate:** `triggerNaziSacrifice` requires `AreaTriggers.IsPlayer(Playerid,"Church")` (`mapcallbacks.lua:18-25`), or the use object `UseJustEntity "Church"`; final AI walk with `IgnoreUsrControl` (`mapinit.lua:228-270`) | Cole and Rawlings reactivated at the end (`ReposPeople`) | scenes `NaziSacrificeA/B` (FP_Church); astral puzzle |

### Act 3 — Crusades

| Level | Present | Switchable (original) | Splits / forced sections | Deaths / leaves / joins | Cutscenes / QTE / boss |
|---|---|---|---|---|---|
| cru_river | 6 | all 6 (Cole/Church specials disabled, `mapinit.lua:6-17`; Rawlings special returned by `RawlingsVlad`, 34-52) | — | **Jones, Cole and Rawlings lost** in scene `BridgeCollapses` [O: next 4 levels contain only Delgado/Church/Black; design note `Tag_04` `mapcallbacks.lua:272-282`; I: they are separated] | **QTE (Church)** `BehemothDead` (`mapscenes.lua:46-96`, enabled via `Kill_Behemoth_03` `UseJustEntity=Church`); Black TK rocks; Delgado door |
| cru_labyrinth | Delgado, Church, Black (`map.lua:5-9`) | the 3 | — | — | scenes `CruzadersSpeech_A/B`; Black TK puzzles; the exit object is Black-only |
| cru_sewers | Delgado, Church, Black | the 3; **Church switch locked** during the climb (`MapScenes.DeactivateChurchOrders` `mapscenes.lua:320-326` → `ActivateChurchOrders` 333-339) | **Church solo:** scene Escalada sets `SoloMision=true` (`mapcallbacks.lua:362-367`); Black/Delgado held, then `bActive=false` (`TriggerBloodWar_3`, 355-360) until `TriggerAperturaPuerta_0` (319-331, Church only) | — | **QTE (Church)** `DescensoA/B` (`PlayDescenso` 268-276, `IsPlayer(...,"Church")`); scenes Apertura, Escalada, AperturaPuerta |
| cru_keep | Delgado, Church, Black | the 3 | — | — | Black TK `BurnTables_0` (174-181) |
| cru_catacomb | Delgado, Church, Black (map lists 6) | the 3 | — | the rescue exists only in an orphan design note (`Tag_05`, 368-380) | — |
| cru_chapel | 6 (start Black) | all 6 | AI disabled around the Maltheus intro (`MemberOnOff`, `mapinit.lua:165-176`) | **Jones, Cole and Rawlings rejoin** in scene `TheRescue` (`mapinit.lua:1-14`, `mapscenes.lua:24-65`) | **boss Maltheus** (`maltheus.lua`); `MoverFaster` teleport (`mapinit.lua:61-77`) |

### Act 4 — Rome

| Level | Present | Switchable (original) | Splits / forced sections | Deaths / leaves / joins | Cutscenes / QTE / boss |
|---|---|---|---|---|---|
| rom_outskirts | 6 (start Jones) | all 6, except during CenturiansTale | **forced switch to Rawlings** (`MapInit.BeginPlayScene` `mapinit.lua:64-73`); all 6 unavailable (`SchFade` 75-88) during scene `CenturiansTale`; restored in `OnEnd_CenturiansTale` (`mapscenes.lua:105-141`); `FadeAndMove` teleport (`mapcallbacks.lua:410-417`) | — | **QTE (Church)** `BehemothDead` (`mapscenes.lua:42-90`); Delgado door |
| rom_caldarium | 6 (start Delgado) | **Delgado only** during the fire section | **Delgado solo:** `AreaTrigger_Fire_0` → `AreaTriggers.EnterFireArea` → `StartSoloMision`; any non-Delgado player is burned to death (`areatriggers.lua:121-135`); others `Active=0` (`mapcallbacks.lua:189-197`), AI pinned via `SetTeamsThere`; ends at lever `PalancaDelgado_0` → `EndSoloMision` (263-272); checkpoints 1-2 use `MapInit.SetSoloMission` (`mapinit.lua:66-73`) | — | Delgado-only doors |
| rom_tepidarium | 6 | all 6 | — | — | Jones astral puzzle (`mapcallbacks.lua:114-141`, 354-384) |
| rom_palace_01 | 6 (start Jones) | all; **Church switch locked** on the abyss | **Church solo:** `o249_0` → `Team.ResetTeamSwitch(Church)` (`mapcallbacks.lua:476`) + scene `TheAbyss` → `PressChurch_0` → `SetTeamSwitch` (294) | — | **QTE (Church)** `TheAbyss` (`mapscenes.lua:18-81`); Jones crank (`UseJustEntity=Jones`) |
| rom_palace_02 | 6 (start Jones) | all | at the end, Delgado is AI-walked (`MapInit.GoToFinalScene` `mapinit.lua:7-13`) | squad trapped and captured by Vicus [I, scene `TheTrap`] | scene `TheTrap` |
| rom_coloseum | 6 | all | arena; AI blockers released per wave | — | arena waves; 3-plate puzzle (`AreaTriggers.SetupPulser`/`isPulsersActive`, `areatriggers.lua:175-243`) |
| rom_chamber | 6 (start Black) | all | the player is AI-walked in, then the other 5 are teleported (`mapinit.lua:17-50`) | — | **boss Vicus** (`vicus.lua`, `aivicus.lua`) |

### Act 5 — Sumer

| Level | Present | Switchable (original) | Splits / forced sections | Deaths / leaves / joins | Cutscenes / QTE / boss |
|---|---|---|---|---|---|
| sum_ziggurat_01 | 6 (start Black) | all; **Jones locked** while possessed (`mapinit.lua:117` → 206); all 6 locked by the teleport | **Jones possession:** a player controlling Jones is force-switched to a random member (`MapInit.StartJonesPossession` 92-119); the player is AI-walked (`MoveSquadAroundJones` 242-263); end teleport `SumTeleport.Teletransport` (`scripts/fx/sumteleport.lua:77-99`) hides everyone (`bActive=false`) and starts AstralCamera on the player | Jones possessed (temporary); squad scattered by the teleport | Leach flight scene (`mapinit.lua:29-41`); statue ritual (`trigEstatuas` OnAllInside) |
| sum_ziggurat_02 | **Jones, Black only** | Black, then Jones (locked `mapcallbacks.lua:315`, unlocked 374) | forced `Team.SwitchSoldier("Jones","Black")`, `EJones.bActive=false` (`mapinit.lua:10-17`); **Black solo** until Jones is found caged (`ShowJones`, 19-28) | Jones imprisoned, then freed | Jones-only astral lever `oMani`; Black-only TK `TK_Activator` |
| sum_ziggurat_03 | Jones, Black; Delgado + Rawlings join | Jones, Black → +Delgado, Rawlings | Delgado and Rawlings `bActive=false` (`mapinit.lua:10-15`) until `ShowRawlings` (17-31, `AreaTrigger79_0`) | Delgado + Rawlings rejoin | **boss Ninlil + Ki**; Ninlil is vulnerable only via `SummerianNINLIL.Use`, which requires `UsrEntity(0).Name=="Jones"` (`scripts/chars/summerianninlil.lua:249-253`); AstralCamera hint camera (`mapinit.lua:54-126`) |
| sum_ziggurat_04 | Jones, Delgado, Rawlings, Black; Cole + Church join at the end | the 4 → 6 | Cole/Church hidden (`mapinit.lua:5-10`) until `LetsGo` (67-77); urn walk with `IgnoreUsrControl` (90-117); teleport hides all | Cole + Church rejoin | **boss Enlil + Inanna** + wheels (start OnAllInside, `mapcallbacks.lua:272-283`) |
| sum_ziggurat_meat | 6 (start Jones) | all (locked ~12 s on arrival, `sumteleport.lua:101-139`) | end: forced walk + teleport (`mapinit.lua:68-100`) | — | **boss Nanna + Utu** + fly nests |
| sum_ziggurat_05 | 6 (cutscene only) | n/a | no gameplay | Delgado shoots the priest | scene `IntoTheUnknown` |
| sum_end | **Black, Church, Delgado, Rawlings** (spawn `bJones=false`, `bCole=false`) | the 4; the possessed member is locked for 1 s; after the Firstborn's blood rune: forced switch to Church and Black/Delgado/Rawlings permanently locked (`evilfirstborn.lua:504-509`, 515-534) | final phase is Church-only [I: win condition `IncapacitateSch` 293-312 requires the human to be Church with the blood rune active] | **Jones and Cole die** in intro scene `TheEndB` (`scripts/fx/sum_end/mapeffects.lua:87-89` `FXJonesBoom`/`FXColeBoom`; `sum_end/mapinit.lua:11-14`) | scenes TheEndA/B, **boss EvilFirstBorn** + Arnold Leach, TheEndC/D, credits |

---

## 4. Character fates and maximum player count

### 4.1 Fates [O]

| Character | Fate | Evidence |
|---|---|---|
| **Ross** | Dies at the end of alk_final (cutscene). From WWII on he has no body: he is the possessing spirit. | `alk_final/mapscenes.lua:37-149`; no Ross in WWII+ spawn tables; `ross.lua:271-272` |
| **Jones** | Leaves in alk_tomb, back in alk_city. Lost at cru_river, back in cru_chapel. Possessed in sum_ziggurat_01, caged in sum_ziggurat_02. **Dies in sum_end intro cutscene.** | see section 3; `fx/sum_end/mapeffects.lua:87` |
| **Cole** | Leaves in alk_tomb, back in alk_city. Lost at cru_river, back in cru_chapel. Absent in sum_02/03 and most of 04. **Dies in sum_end intro cutscene.** | `fx/sum_end/mapeffects.lua:89` |
| **Delgado** | Leaves in alk_tomb, back in alk_city. Absent in vigil_inside, sum_02 and early sum_03. **Survives.** | sum_end spawn and TheEndC/D actors |
| **Rawlings** | "Killed" by Delgado in wwii_pillboxes, then revived. Absent in cru_labyrinth..catacomb and sum_02. Hidden as a prop in brandenburg. **Survives.** | sum_end spawn |
| **Black** | Absent in alk_bunker_00 and vigil_inside. **Survives.** | sum_end spawn |
| **Church** | Absent in alk_bunker_00 and sum_02/03 (rejoins at the end of 04). **Survives** and is the final protagonist. | sum_end; `evilfirstborn.lua:504-509` |

Scripted temporary deaths that are revived:
- Rawlings in wwii_pillboxes (`mapscenes.lua:116`).
- Jones in wwii_pillboxes (`mapinit.lua:605-613`).

NPC deaths: Muriel Green (alk_bunker_01), Tuck (wwii_mosque_inside).

### 4.2 Maximum player count (owner rule: number of members alive and available at the end)

- **Alive at the final level:** Black, Church, Delgado, Rawlings = **4**. These are the only characters spawned in sum_end and present in the closing scenes TheEndC/D.
- **Campaign-wide maximum: 4 players** [O+I].
- **Final boss caveat [O]:** in the original rules, the last phase of sum_end allows only Church (`SchMakeAllUnavailable` re-locks Black, Delgado and Rawlings every 0.1 s with no exit). Co-op must patch this (see 5.2).

### 4.3 Simultaneous humans possible per level (cap 4)

The table counts characters that physically exist in the level as playable squad bodies:
- **"natural"** = present members, ignoring the original switch locks.
- **"original-locks"** = the most that are simultaneously unlocked at any moment under the vanilla rules.

| Level | Present bodies | Natural (cap 4) | Original-locks note |
|---|---|---|---|
| alk_desert, alk_city, alk_bunker_01, alk_final | 7 incl. Ross | 4 | vanilla: only Ross playable |
| alk_tomb | 7 → 4 (Ross + Omega) | 4 | Ross only |
| alk_bunker_00 | 2 (Ross, Rawlings) | **2** | Ross only |
| wwii_biggates | 6 | 4 | 2-3 (Delgado, Black, + Church) |
| wwii_pillboxes | 6 | 4 | up to 5 (Jones locked) |
| wwii_mosque | 6 | 4 | 5 → 6 |
| wwii_mosque_inside, wwii_vigil | 6 | 4 | 6 |
| wwii_vigil_inside | 3 | **3** | 3 |
| wwii_brandenburg | 6 (Cole and Rawlings as props) | 4 | 4 |
| cru_river | 6 | 4 | 6 |
| cru_labyrinth, cru_sewers, cru_keep, cru_catacomb | 3 | **3** | 3 (sewers: 1 during the Church solo) |
| cru_chapel → rom_chamber | 6 | 4 | 6 (except the solo/forced sections in 5) |
| sum_ziggurat_01 | 6 | 4 | 5 while Jones is possessed |
| sum_ziggurat_02 | 2 | **2** | 1 → 2 |
| sum_ziggurat_03 | 2 → 4 | **2 → 4** | 2 → 4 |
| sum_ziggurat_04 | 4 → 6 | 4 | 4 |
| sum_ziggurat_meat | 6 | 4 | 6 |
| sum_ziggurat_05 | cutscene | — | — |
| sum_end | 4 | 4 | 4 → 1 (Church) |

With 4 players the levels that have too few bodies are:
- alk_bunker_00 (2),
- wwii_vigil_inside (3),
- the four Crusades levels cru_labyrinth to cru_catacomb (3),
- sum_ziggurat_02 (2),
- the start of sum_ziggurat_03 (2).

---

## 5. Solo and restricted sections

### 5.1 What the scripts do with the other members [O]

| # | Section | Who acts | What the others do (script) |
|---|---|---|---|
| S1 | All of Al-Khali (6 levels) | Ross only (switch deactivated) | AI squad follows Ross |
| S2 | alk_tomb end → alk_bunker_00 | Ross (+ Rawlings in bunker_00) | Alpha `bActive=false` (gone); in bunker_00 Church and Black are not loaded |
| S3 | alk_bunker_01 ambush | Ross | Cole replaced by FakeCole at the console, real Cole `bActive=false` (`mapinit.lua:102-119`) |
| S4 | wwii_biggates / pillboxes / mosque tutorials | Delgado, Black, Church, then Cole, Rawlings, Jones unlocked gradually | locked members still fight as AI |
| S5 | wwii_pillboxes after Rawlings is "killed" | current player (solo; must revive Rawlings) | the whole squad is teleported and `DisableAILoop` keeps all AI off (`mapscenes.lua:145-195`) |
| S6 | wwii_pillboxes Rawlings gate | human must be Rawlings | others AI |
| S7 | wwii_vigil_inside | Cole, Church, Rawlings | Jones, Delgado and Black not loaded (outside) |
| S8 | wwii_brandenburg sacrifice | Church must be the human (`IsPlayer`) | Cole and Rawlings are props around the Nazi Bitch |
| S9 | cru_labyrinth → cru_catacomb | Delgado, Church, Black | Jones, Cole and Rawlings not loaded (lost) |
| S10 | cru_sewers climb / blood ward | Church solo (switch locked) | Black and Delgado hold, then `bActive=false` |
| S11 | rom_outskirts CenturiansTale | forced Rawlings, all locked | scene; others repositioned afterwards |
| S12 | rom_caldarium fire | Delgado solo (others burn) | others `Active=0` (frozen) and AI pinned at a point |
| S13 | rom_palace_01 abyss | Church (switch locked) + QTE | others wait at the abyss (AI) |
| S14 | sum_ziggurat_01 possession | anyone but Jones | Jones is a possessed NPC; the player is AI-walked |
| S15 | sum_ziggurat_02 | Black alone, then Jones (caged, astral only) | the other 4 not loaded (scattered by the teleport) |
| S16 | sum_ziggurat_03 first half | Jones, Black | Delgado and Rawlings `bActive=false`; Cole and Church not loaded |
| S17 | sum_ziggurat_04 | Jones, Delgado, Rawlings, Black | Cole and Church hidden |
| S18 | sum_end final phase | Church only | Black, Delgado and Rawlings forced into the "Stupid" (stunned) action, AI off, locked |
| QTEs | alk_tomb (Ross), pillboxes (Cole), vigil_inside (Rawlings), cru_river (Church), cru_sewers (Church), rom_outskirts (Church), rom_palace_01 (Church) | one character | cutscene, `Scene.HideChars` freezes all `WalkChar`s (`scene.lua:622-638`) |

### 5.2 Ideas to keep the other players engaged [I]

These are design proposals, not script facts.

1. **Al-Khali (S1-S3):** the vanilla game has no possession yet.
   - Option A, closest to the story: player 1 is Ross and the others take squad members directly, as "bodies under their own control". The co-op layer simply gives `UsrControl = n` to those members instead of AI.
   - Option B: keep Ross's player solo and let the others watch through a spectator camera. Not recommended: there are 6 levels of it.
   - Option A matters for bunker_00 (2 bodies): players 3-4 spectate, or join as Church/Black kept active as invisible "radio" observers. The extra option is a spectator camera that follows Ross or Rawlings, perhaps with a cosmetic astral look.
2. **Bodies not loaded (S2, S7, S9, S15, S16):**
   - **Spectator / astral camera:** reuse `AstralCamera.Start(owner, false, true)` ("OnlyOrbit" mode, `astralcamera.lua:125-176`) attached to a teammate. The orbit camera already exists and only needs a per-viewport camera.
   - **"Spirit" support role:** a spectator in astral form could trigger limited support, for example pinging enemies or a simplified Jones-style telekinesis/pyro on objects that are already `bUseOnTK` (`AstralCamera.funcOnTK/funcOnBurn`). This turns the absent character's player into "Ross's spirit" helping the active team.
   - **Re-enable the missing bodies as optional companions.** Example: load Jones/Cole/Rawlings into cru_labyrinth through `map.lua init.Team` and the spawn flags. Not recommended: it breaks the story ("lost at the bridge") and their absence is referenced by scenes and dialogue.
3. **Solo-mission sections where the others are still loaded (S5, S10, S12, S13):**
   - **S12 rom_caldarium (fire):** the others are frozen with `Active=0`. Let them stay active as a defensive group at the pinned point (`SetTeamsThere`): spawn the existing torturer and cultist waves near them, or let them cover Delgado from the entrance. Or spectate Delgado.
   - **S10 cru_sewers climb:** Black and Delgado players can stay at the gate, with an extra enemy wave at the gate, until Church opens the door. Note: the script sets them `bActive=false` at `TriggerBloodWar_3`, so those players need a spectator camera during that phase.
   - **S13 palace_01 abyss:** the other players hold the abyss edge against legionaries. The existing `LegionariosPuente*` groups already spawn there, and the pressure plates `LosetaPuenteA/B/C` need teammates (they are pulsers).
   - **S5 pillboxes revive solo:** any player may perform the revive. The solo lock could be removed in co-op, because the AI is disabled anyway.
4. **Character-locked gates (S6, S8, Church/Jones/Delgado-only objects and bosses, QTEs):**
   - In co-op, the gate must be satisfied by **any human controlling that character**, not by `UsrEntity(0)`.
   - If no human holds that character, either let the AI or the host auto-switch into it (vanilla forced-switch behaviour), or let a free player claim it on demand.
   - During a single-character QTE, the other players get a cinematic spectator view. The scene camera already plays for viewport 0; it could be mirrored.
5. **Forced switches (rom_outskirts → Rawlings, sum_02 → Black, sum_01 Jones possession, sum_end → Church):** map "the human" to "the human who currently controls the character named in the call".
   - If Rawlings is free, have the host or any player take Rawlings.
   - If Rawlings is held by another human, the script should target that human instead of switching anybody.
6. **sum_end final phase (S18):** the three non-Church players are stunned ("Stupid" action) for the rest of the fight.
   - Option: keep the lock (story) and give them a spectator or spirit role, with the astral camera on Church.
   - Option: let them keep fighting Arnold Leach and the Firstborn adds. This requires changing `EvilFirstBorn.SchMakeAllUnavailable` (`evilfirstborn.lua:515-534`).
7. **Possession switching between players:** follow the owner rule. In the radial menu (`Team.SetIdChar`, `team.lua:496-522`), mark members held by other humans as unavailable: extend `Team.IsPlayerAvaliable` with an "owned by player k" table. When a human dies, `Team.CheckGameOver` should pick a free member, or put the player into spectator mode rather than game over.

---

## 6. Script-side hooks and single-player assumptions

### 6.1 Global single-player state [O]

| Item | Where | Note |
|---|---|---|
| `Game.UsrEntity(0)` | 119 uses in `scripts/`, 70 in 23 level files | "the" player; also inside `AIGen.GetPlyName` (`aigen.lua:23-29`), which the AI uses everywhere |
| `UsrControl` (0 = human, -1 = AI) | `team.lua:123, 583, 590`; `CanCure` (355); `Soldier.CharDamage` (`soldier.lua:92`); `Weapons.SaveWeaponConfig` (`weapons.lua:802+`); `QTE.canNotQTEAttack` requires `usr.UsrControl == 0` (`qte.lua:278-280`); `AreaTriggers.IsPlayer` (`areatriggers.lua:86-92`) | the engine plumbing seems to support indices ≥ 0 [I], but scripts assume only 0 |
| `Team.MainChar` | `team.lua:6, 68-79, 1314, 1328` | single initial controlled character |
| Camera 0 | `Game.SetCam(0,…)`/`GetCam(0)`: 65 uses (team.lua TravelCam/EndTravelCam, `scene.lua` Play/StickCamera/InterpolCam, `astralcamera.lua:39, 130`, levels) | cutscenes, switch flight and astral mode all take over camera 0 |
| Input action set | `Input.SetActionSet/GetActionSet`: 36 uses, global (no pad index), e.g. `scene.lua:707, 452`, `team.lua:1363, 1385`, `qte.lua:344, 405`, `areatriggers.lua:125, 247-258`, `savegame.lua:305-307` | puts **all** input into "Inactive", "Astral" or "Menu" |
| Input binding | `Input.Bind(0, …)` (`init.lua:345`) | pad/user 0 |
| HUD | `Scorer.*(0, …)`: 396 uses | viewport 0 only |
| First-person models | `MakeFP.MakeFPObject(ac.Name, 0)` in every `fp_*.lua` (e.g. `fp_black.lua:143`); hard-coded `"0FP_<Name>"` names in char, thread and fx scripts (`delgado.lua:572`, `black.lua:805` and others); `MakeFP.LaunchFpsAnm(0, …)`: 82 uses | FP arms exist only for user 0 [O]; whether they rebind per user is unknown [U] |
| Global time | `Game.SetTimeSpeed`: `team.lua:1360` (switch flight 0.005), Cole's power `threadscole.lua:188`, Black's power `threadsblack.lua:137, 286`, `weapons.lua:192`, scenes, `savegame.lua:351` | affects every player |
| QTE state | `QTE.InGame` single table (`qte.lua:267`); `Scorer.QTE*` one sequence; scene QTE via `QTE.AddSequence`/`ValidateSequence` (`qte.lua:49-154`) | one QTE at a time, on user 0 |
| Grab QTE attackers | `arnold.lua:264`, `cultistamelee.lua:484`, `cultistavolador.lua:429` → `QTE.InGameQTE` | only possible against the `UsrControl == 0` character |
| Cutscenes | `Scene.Play` (`scene.lua:669-750`): stores `Scene.usr = UsrEntity(0)`, `HideChars()` freezes every WalkChar, `StickCamera(0, …)`; `Scene.PlayFP`/`PlayFPNI`/`PlayFPNNI`/`SetUsrPosAng` use `UsrEntity(0)` (807-888) | FP scenes are filmed from a named `FP_<Char>` actor; the player's position is set from `UsrEntity(0)` |
| Solo-mission flag | `AreaTriggers.SoloMision` (`areatriggers.lua:152-168`) | global; acts on `UsrEntity(0)`'s class |
| Unavailable table | `Team.UnavaliablePlayers` (`team.lua:446`) | global; often replaced whole by level scripts |
| Radio/dialogue | `TeamTalk.IsValidPlayer` (`teamtalk.lua:120-127`) excludes `UsrControl ~= -1`; `TryRadioChatCall` picks the line by `UsrEntity(0).ActCtrl` (`teamtalk.lua:454-482`) | humans are treated as "the player", who does not radio-talk |
| Level-script player handles | `MapInit.player`, `MapInit.EPlayer` (sum_01, sum_04, wwii_pillboxes and others); `UsrEntity(0).Name == "<Char>"` gates (wwii_biggates `mapinit.lua:100-114`, wwii_pillboxes 615-623, cru_labyrinth 353-359, `summerianninlil.lua:249-253`) | character gates written as "the one human is X" |
| Area triggers | `Game.SetTriggeredEntity(i, member)` for each squad member (`team.lua:131`); callbacks receive `Playerid` | [I] triggers fire for AI members too, since a few callbacks explicitly check `IsPlayer`; `OnAllInside` needs the whole squad; `OnCameraView` uses the player's view [U, engine] |

### 6.2 Save-game variables [O]

All are cleared on level change by `Game.DelSaveVars("")` (`savegame.lua:344`).

| Variable | Where | Meaning |
|---|---|---|
| `LevelName` | `savegame.lua:130` | current level |
| `<level>.Spawn.Point`, `<level>.SavedSpawn.Point` | `team.lua:1`; `savegame.lua:131-146` | checkpoint id → spawn entry; this also fixes the controlled character after a load |
| `<Name>.CanSwitch`, `<Name>.CanOrders` | `team.lua:155-166, 1403-1449` | switch and orders locks; per **character class**, not per player |
| `<level>.EntityValue.<Entity>.<Field>` | `savegame.lua:176-237` | triggers' `OnEnter`/`OnExit`/`bActive` etc. (`areatriggers.lua:14-17, 41-48`) |
| `<level>.FlagCounter.<Name>` | `savegame.lua:390-396` | group-death counters (73 uses in levels) |
| `Level.Complete.Hard/NoDead` | `savegame.lua:571-612` | unlockables; `NoDead` is reset when the controlled character dies (`team.lua:206`) |

**Not saved** [O]: `Team.UnavaliablePlayers`, `AreaTriggers.SoloMision`, and which member is human-controlled. They are rebuilt by each level's `MapInit` according to the checkpoint.

Autosave: `SaveGame.AutoSaveWaypoint` (50 uses in levels) → `Game.SoftSaveAutoSave()`.

### 6.3 Callbacks invoked on switching and related events [O]

| Hook | Fired from | Use for co-op |
|---|---|---|
| `Team.SwitchCharacter` / `Team.SwitchTeam` (act-class `SwitchChar`/`HoldSwitchChar`) | engine input | entry point to filter "taken" members |
| `Team.SwitchSoldier(from, to)` | radial menu, scripts, `CheckGameOver` | central function: needs a user index |
| `Team.OnSwitchChar[<Name>](ent)` | `team.lua:126-127, 173-177, 598-600` | per-character FP/HUD setup (uses `"0FP_*"`) |
| `Team.AreaManager.onTeamSwitching` → `Team.OnTeamSwitching` → `AISquad.OnSwitchPlayer` | engine (`team.lua:53, 618-624`; `aisquad.lua:219-227`) | AI main/second team swap |
| `Team.EndSwitchCallback` | `Team.EndTravelCam` (`team.lua:1393-1395`) | used by rom_outskirts |
| `Game.Set("ChangeCamEvent", "Team.OnChangeCamera")` | `team.lua:59, 1568-1577` | camera-change hook (breathing FX) |
| `AstralCamera.EndReturnCallback`, `cam.uData.EndProjectionCallback` | `astralcamera.lua:59-61, 92-95` | astral end hooks |
| `Team.ReviveAllCallback` | `team.lua:426-430` | used by TeamTalk |
| `Scene.EndOfSceneCallback` / `EndOfSubSceneCallback` / `NextScene` | `scene.lua:455-475` | cutscene completion (level progression) |
| `Team.OnDeath` (EntityList `OnDeath`) → `Team.CheckGameOver` | `team.lua:64-67, 184-308` | must become per-player (spectate or switch instead of game over) |
| `QTE.*` validators via scene events | `qte.lua:130-154` | scene QTEs; route to the right human |

### 6.4 Unknowns

- **Multiple users in the engine.** Whether the engine supports more than one active `UsrControl` index, extra cameras (`Game.SetCam(1, …)`), more FP objects (`MakeFPObject(name, 1)`) or per-pad input sets is unknown [U]. The API shape (`UsrEntity(id)`, `SetCam(id, …)`, `Input.Bind(pad, …)`, the FP name prefix `id..Typo`) suggests index plumbing exists [I].
- **Unavailable table between levels.** Whether `Team.UnavaliablePlayers` and other module globals reset between levels depends on whether the Lua state is rebuilt per level. `init.initGame` preloads Team.lua again (`init.lua:122`), so it probably resets [I].
- **AI-triggered area triggers.** Whether area-trigger `OnEnter` fires for AI-controlled squad members is unknown [U]. The `IsPlayer` checks in a few callbacks suggest it does [I].
- **`.Active = 0`.** Its effect on availability and AI, compared with `bActive`, is unknown [U].
- **rom_caldarium checkpoints.** The switch/orders lock state after loading checkpoints 1 or 2 is probably restored from the `CanSwitch`/`CanOrders` save vars [I].
- **Subtitles.** The text of the subtitles and design-note strings is not in `src` (localisation files are missing).

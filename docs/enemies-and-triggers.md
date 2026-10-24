# Clive Barker's Jericho: enemies, damage and story triggers for host-authoritative co-op

Scope: how enemies are created, enumerated, damaged and killed; how area triggers and other story callbacks fire; what a mod has to wrap so that one machine (the host) runs enemies and story, and the other machines (clients) only mirror them.

Context: squad mechanics and single-player assumptions are covered in `campaign-structure.md`, sections 2 and 6. This document does not repeat them. The existing prototype (`lua/coop.lua`) already syncs squad bodies as "puppets" (AI off, `InCtrl_Walk`/`InCtrl_Str`, position correction; `coop.lua:1-15`, `186-227`). The design in section 7 extends that model to enemies.

Conventions:
- Paths without a prefix are relative to `work/src/`. `levels/<l>/` means `work/src/levels/<l>/scripts/`.
- **[O] Observed**: read directly in the code.
- **[I] Inference**: follows from the code but is not proven.
- **[U] Unknown**: needs a runtime test or engine reverse engineering.

---

## 1. Enemy creation

### 1.1 Load sequence

1. `init.initGame` (`scripts/init.lua:106-351`) preloads `NPC`, `EnemyGen` and `AIGen` (116-118). It loads every enemy class in `init.Enemies` (174-220, sorted at 281, loaded at 282-300). It then calls `Map.main()` (326), `Team.CreateTeam()` (332), `Scene.LoadScenes()` (341) and `SaveGame.InitLocalEntityValues()` (349).
2. Each level's `Map.main` preloads the map libraries and runs their `main` functions in a fixed order (example: `levels/wwii_biggates/map.lua`; `init.PreloadMapLib`/`ExecMapLibs`, `init.lua:407-417`):
   `MapInit` → `MapScenes` → `MapCallbacks` → `MapSpawnPlayers` → `MapAreaTeam` → `MapMoveHelpers` → **`MapEnemies`** → **`MapEnemiesGroup`** → `MapPhysicObjects` → … → **`MapAreaTriggers`**.
3. `MapEnemies.main()` calls `NPC.CreateMapEnemies()`. `MapEnemiesGroup.main()` calls `NPC.CreateMapEnemiesGroup()`. Every level has both (`levels/*/mapenemies.lua:2`, `levels/*/mapenemiesgroup.lua:2`).

### 1.2 Creation functions [O]

| Function | File:lines | Arguments | Name given to the entity |
|---|---|---|---|
| `NPC.CreateSingleEnemy(a, ActCtrlName)` | `scripts/chars/npc.lua:72-113` | `a` = one property table from `MapEnemies.Enemies`, or nil | `"Enemy_" .. NPC.Counter` (73), then the counter is incremented (75). The entity is created as `"WalkChar"` with `bActive = false`. Each `{key, value}` in `a` is then written to the entity (78-87). Map data contains `{"Name", "Enemy65"}`, so the entity is **renamed** to the editor name. |
| `NPC.CreateMapEnemies()` | `npc.lua:115-125` | none | Calls `CreateSingleEnemy` for every entry of `MapEnemies.Enemies`. |
| `NPC.CreateMapEnemiesGroup()` | `npc.lua:127-228` | none | Creates one `EntityList` per group (`Game.CreateEntityList`, 137). Copies the `el_*` properties (`el_OnAllDeath`, `el_OnDeath`, `el_OnDamage`, `el_OnAttackAI`) onto the list (149-155). Sets `EntityList`/`TgType` on the members (177-191). Creates the AI for non-generator groups (`AIEnemiesTeam.Create`, 193-203) and for generator members that are already active (204-211). |
| `EnemyGen.CreateGenData(datalist, els, a)` | `scripts/chars/enemygen.lua:4-28` | group data | Fills the generator's **pool** with extra enemies: `NPC.CreateSingleEnemy(EnemyGen.GetRandomEnemyData(...))` (22). These keep their generated name `"Enemy_<n>"`. The template is picked with `math.random` (50-52). |
| `NPC.CreateWithAI(acName, x, y, z, listName, setOnFloor)` | `npc.lua:29-52` | class, position, group | `CreateSingleEnemy(nil, acName)` gives `"Enemy_<n>"`. The function adds the enemy to `NPC.Groups[listName]`, calls `AI.EnableAIChar(name, 1, ActCtrl, 0)` and `AIEnemy.CreateSingleEnemyAI` (49-50). Bug: it tests the global `bSetOnFloor` instead of the parameter (33), so `SetOnFloor` never runs. `propsAI` is an undefined global (47, 50). |
| `EnemyGen.ActivateEnemy(enemy, listName)` | `enemygen.lua:107-137` | pool enemy | Picks a spawn point with `math.random` (109) and `Game.TestSphere(..., "R")` (113). Deletes the pool entity (124) and **creates a new one** with `NPC.CreateWithAI` (125). The new enemy gets a fresh `"Enemy_<n>"` name, `Ang`, `ForceAction`, `bActive = true` and move helpers. |
| `EnemyGen.ActivateSpontaneousEnemy(listName)` | `enemygen.lua:139-159` | infinite generators | Same pattern, always `NPC.CreateWithAI` (147). |
| `NPC.Create(EneList, listname)`, `NPC.AssignOnEnter`, `NPC.OnEnterCreate` | `npc.lua:7-27`, `54-68` | legacy "create on trigger" path | Uses `Game.CreateEntity(nam, "WalkChar")` with a fixed name. No level script calls it (grep: no hits under `levels/`). |
| Boss summons | `maltheus.lua:788`, `psichiccommander.lua:291`, `summerianinanna.lua:159,170`, `summeriannanna.lua:291`, `summerianninlil.lua:279` | `NPC.CreateWithAI(class, x, y, z, teamName)` | `"Enemy_<n>"` |
| Other runtime `Game.CreateEntity(name, type, pos)` calls | `cru_river/mapinit.lua:25` (`"Culonne"` corpses, all with the same name), `maltheus.lua:280` (`"Rose"`), `evilfirstborn.lua:130-155` (`"EvilAbabanili"`, `"EvilGhostHeal"`, renamed `egh.Name = "EGHBlack"` at 142), `sum_wheel_*.lua:79-86` (`<name>_A/_B/_C`), `npc.lua:96` (`<name>_BadBoy`), `npc.lua:107` (`"\186"..<name>.."_Fly_"..i`), `aigen.lua:300-311` (`AIGen.MakeChar`, debug only) | fixed or derived names | |
| Projectiles (`"Missile"`) | `weaponslegionary.lua:32` (`"LegionaryPilum"`), `weaponsnazisoldier.lua:162,231` (`<ent>_NaziMortar/_NaziCluster`), `weaponscruzader.lua:163` (`"Virote"..count`), `arnold.lua:338` and `cultistavolador.lua:499` (`"CultistBlade"`), `summerianki.lua:288`, `weaponsmaltheus.lua:9`, `weaponsblack.lua:113`, `weaponscole.lua:685`, `fx/cru_keep/mapeffects.lua:41` and `fx/cru_river/mapeffects.lua:70` (fireballs) | | often the same name for several live projectiles |

Map data shape [O]: every entry of `MapEnemies.Enemies` is a list of `{key, value}` pairs: `Pos`, `Ang`, `Name`, `ActCtrl`, `ForceAction`, `bActive`, `uDataAI_DistVis` (`levels/wwii_biggates/mapenemies.lua:5-30`). `EnemyGen.GetEnemyData` relies on index 3 being the name (`enemygen.lua:43`). A group lists its members as a newline-separated string in `List`, plus properties such as `isGenerator`, `poolSize`, `maxSimultaneousEnemies`, `quickFill`, `isInfinite`, `CreatedAttack` (`levels/wwii_biggates/mapenemiesgroup.lua:5-45`).

Whole campaign [O, grep counts over `levels/*/mapenemies.lua` and `mapenemiesgroup.lua`]:
- About 680 placed enemies: 650 with `bActive = false` and 30 with `bActive = true`.
- Their `ForceAction` is `"Relax"` (293) or `"Emerge"` (293), plus a few others.
- 253 groups, of which 102 are generators and 17 of those are infinite.
- Most common classes: CultistaMelee 180, CultistaExplosivo 122, Legionary 87, CultistaVolador 46, NaziSoldierA 40, GhostChildCruzader 39, CruzaderB 38, CruzaderA 33.

### 1.3 Names and determinism

Observed:
- The names written in the editor (`"Enemy65"`, `"Enemigator833"`, `"Behemoth_03"`, ...) are fixed strings in the level data. "Enemy75"-style names come from the editor, not from the game at runtime (`levels/wwii_biggates/mapenemies.lua:15`).
- Names generated at runtime use one Lua counter, `NPC.Counter` (`npc.lua:70`, `73-75`). It counts **every** `CreateSingleEnemy` call, including the map enemies that are renamed afterwards.
- Entity `Name` can be written: `npc.lua:79-80` (via the property list) and `evilfirstborn.lua:142`.
- No `math.randomseed` call exists anywhere in the scripts (grep). Randomness affects:
  - which template a pool enemy uses (`enemygen.lua:22`, `50-52`),
  - the delay before the next spawn (`enemygen.lua:77`),
  - which spawn point is used (`enemygen.lua:109`, `141`),
  - whether a green NPC (British) joins Alpha or Omega (`aienemy.lua:51`, `aienemiesteam.lua:19`).
- Whether a spawn point is free depends on physics: `Game.TestSphere(pos, radius, "R")` (`enemygen.lua:113`, `145`).

Inferred:
- **Map enemies** get the same names and classes on every machine.
- **Generator pools** get the same names on both machines (`Enemy_<#mapEnemies>` …), because the load order is fixed. Their **classes can differ**, because the templates are chosen with `math.random`.
- **Runtime spawns** from generators and boss summons are **not** reproducible on two machines. Name order, timing, spawn point and class all depend on unseeded randomness, game time and physics. They must come from the host.
- Runtime names (`Enemy_<n>` with `n ≥` the load-time counter) cannot collide with editor names. Editor names use `EnemyNNN` without an underscore. The only underscore names in level scripts are group names (`"Enemy_00"`, `"Enemy_2"` in `cru_keep/mapcallbacks.lua:13`), not entities.

Unknown:
- What `Game.CreateEntity` does when the name already exists (fail, replace or rename). Projectiles and `"Culonne"` are created several times with the same name.
- Whether the engine seeds C `rand()`.

### 1.4 What exists when

| When | What | Evidence |
|---|---|---|
| Level load | All placed enemies, mostly inactive (`bActive = false`). Generator pools (inactive). Linked extras: `_BadBoy` for GhostChildCruzader, `_Fly_1..6` for Flies. | `npc.lua:115-228` |
| Group activation (trigger, group death, scene end, `MapInit` polling) | `NPC.ActivateEnemyGroup(G)` (611 calls in level scripts). For a normal group it sets `bActive = true` on all members (272). For a generator it schedules or performs spawns (256-270). It runs once per group per save: save var `<level>.EnemyGroup.<G>.Status` (249-252). | `npc.lua:248-276` |
| Generator runtime | New entities via `CreateWithAI`; the pool entity is deleted. `EnemyGen.Stop(G, killAll)` (89 calls) kills the remaining pool or active enemies by `Life = 0` + `uData.RemoveNow`. `IncreaseMaxEnemies` is used in `rom_palace_01/02`. | `enemygen.lua:107-200`, `212-228` |
| Boss fights | Summoned minions (`NPC.CreateWithAI`). Shields and helpers as physics or WalkChar entities. | see 1.2 |
| Scenes | Actor entities `<Scene><Actor>` of type `"WithLife"`, created by `Scene.Play` and deleted at the end. They are not enemies. | `scene.lua:692-695`, `444-447` |
| Checkpoint load | The level is reloaded from scratch: placed enemies come back. `MapInit` re-activates groups according to `Team.GetSavedSpawnPlayerPoint()` (for example `cru_keep/mapinit.lua:5-12`). Trigger callbacks already consumed are restored from save vars (`savegame.lua:176-218`). | |

---

## 2. Enumerating live enemies

### 2.1 Methods

Observed:
1. **Linked entity list.** `local e = Game.GetFirst(); while e do ... e = Game.GetEntity(e.NextInSlot) end`. This walks every entity. Existing filters:
   - `threadsblack.lua:91-95`: `e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0`.
   - `QuickConsole.killall` (`quickconsole.lua:825-834`) and `Scene.HideChars` (`scene.lua:622-638`).
2. **AI metateam.** `AITeamList.FirstMembMetaTeam(AISetEnemies.Name)` / `NextMembMetaTeam(...)` → `memb.oEnt` (`aisetenemies.lua:74-82`). Only enemies whose AI has been created are listed. `AISetEnemies.Name = AISpec.GetMetaTeamEnemies()` (`aisetenemies.lua:4`). Per-team: `AITeamList.Get(groupName)`, `team.oFirst`/`team:oNext(memb)` (`aienemiesteam.lua:123-128`). Membership test: `AISetEnemies.IsMember(ent)` compares `ent.oAI.MetaTeam` (`aisetenemies.lua:10-15`). Enemies "prevented" by the engine move to a separate team (`aienemteamprev.lua:7-24`).
3. **Lua group tables.** `NPC.Groups[groupName]` is an array of entity userdata plus `.uData` (`npc.lua:128-192`). Generator spawns are appended (`npc.lua:39`) and the deleted pool entries are removed (`enemygen.lua:115-119`). Dead or deleted entities can stay in the table; scripts check `ent.bValidBaseType` before use (`enemygen.lua:94`, `116`, `168`, `205`).
4. **Engine entity list per group.** `Game.GetEntityList(G)` has `:GetEntitiesLeft()` (`rom_palace_01/mapcallbacks.lua:246`) and the callback fields `OnAllDeath`, `OnDeath`, `OnDamage`, `OnAttackAI`, `OnSwitchActive` (`npc.lua:149-155`, `areatriggers.lua:98-110`, `rom_palace_01/mapcallbacks.lua:112`).
5. **Static data.** `MapEnemies.Enemies` (spawn data). `NPC.ListOfMapEnemies` is filled only in ToolMode (`npc.lua:116-123`).

Inferred: for the mod, method 1 filtered on `IsType("WalkChar")` and `TgType ~= "green"` is the most complete live list. Method 3 is the most convenient for "which group does this enemy belong to" (`e.EntityList` is also set on each enemy, `npc.lua:38`, `180`).

Unknown: the cost of a full `GetFirst` walk every tick (the level has hundreds of physics entities). Cache the list and refresh it on spawn/death events instead.

### 2.2 Telling enemies from squad and NPCs

| Kind | How to recognise it | Evidence |
|---|---|---|
| Squad (Jones, Cole, Delgado, Church, Rawlings, Black, Ross) | Fixed names; `EntityList` = `"Alpha"`/`"Omega"`; `TgType = "Green"` (read back as `"green"` [I]); `oAI.MetaTeam` = squad metateam | `team.lua:112-121`; `weapons.lua:590` uses the Alpha/Omega test |
| Allied NPC soldiers (British) | In an enemy group, but `TgType = "green"` and inserted into the Alpha/Omega AI teams | `npc.lua:182-186`, `aienemy.lua:50-55` |
| Enemies | `TgType` `"red"`/`"Red"`; `EntityList` = map group name; AI in `AISetEnemies.Name` | `npc.lua:21`, `185`; `cultistamelee.lua:443` |
| GhostChildCruzader | `TgType = "none"` (not targetable); its `_BadBoy` partner is red | `npc.lua:20-24`, `40-46`, `187-188` |
| Squad helpers | `"Ababanili"` (Delgado's demon), `"GhostHeal"` (Rawlings) are WalkChar with fixed names | `delgado.lua:633`, `rawlings.lua:727` |
| Story fakes | `"FakeCole"`, `"FakeJones"`, ... (WalkChar in cutscenes) | `alk_bunker_01/mapinit.lua:103`, `alk_tomb/mapinit.lua:109-125` |
| Scene actors | `"WithLife"`, not WalkChar | `scene.lua:694` |

[I] `TgType` is an engine enum: scripts assign both `"Red"` and `"red"` and compare against lowercase. Compare in lowercase.

---

## 3. Damage and death

### 3.1 How damage is applied

Observed. Almost all damage goes through **`Weapons.DoDamage(From, To, Damage, BodyMultiplier)`** (`weapons.lua:288-343`). What it does:
- Rawlings' curse side effect (291-293).
- The team filter (294). The hit lands if:
  - attacker and target have different `TgType`, or both are humans (`UsrControl ~= -1`); **and**
  - one of: the target has no `uData.TeamDamageFactor`, or the attacker is human (`From.UsrControl >= 0`), or a random roll is below `TeamDamageFactor`.
- `TeamDamageFactor` is 0.45 for almost every enemy class (`config/enemiescfg.lua:5-123`, set in each `OnCreate`, for example `cultistamelee.lua:444`). **AI squad members land only about 45% of their hits on enemies; humans always land them.**
- Body multiplier: `To:SetLastBodyPiece(From)`, then `To.oWeapHit.oBodyPiece.oRagDollDamagePart.Damage` (295-305). Without a multiplier it sets `From.Hit_Target = To.Name` (307).
- **`To.Life = To.Life - Damage`** (309) and `To.uData.realDamage` (310).
- Hit reactions: `BodyImpact.OnShot` and, for green targets, the friendly-fire lines and `ForceAction = "Hit"`/`"HitDuck"` (313-340).
- `Weapons.LastKilled` (341).

Callers of `DoDamage`:
- **Hitscan weapons.** The engine calls the weapon type's `w.OnShot` string with `(EntityName, TargetName, X, Y, Z, iShot)`, for example `weaponsjones.lua:19`, `112-170`. These call `Weapons.OnShot` (`weapons.lua:381-465`), which applies impulses (`AddShotData`, 445) and `DoDamage` (457).
- **Melee.** Animation events `Weapons.MeleeHitEvent` (136-156, via `oWeapCtrl:CheckMeleeTarget`) and `Weapons.FP_MeleeHitEvent` (213-222). The engine callback `w.OnMeleeHit = "Weapons.MeleeOnHit"` (91, 103-131); its `typo == 3` case writes `tgt.Life - 100` directly (128).
- **Enemy melee and projectiles.** `WeaponsCultistaMelee.HookHitEvent` (`weaponscultistamelee.lua:7-26`, ray from `o:DrawWeapon`), `WeaponsLegionary.HitPilum` (86-101), `WeaponsCruzader.HookHitEvent`, and boss attacks (list in section 6.3).
- **Explosions.** `Weapons.ExplotaExplotaQueExplo` → `Game.SphereCall(pos, r, "L", "Weapons.ExplosionDamage")` → `DoDamage` (485-552). Impulses go through a second `SphereCall` with `"LPO"` (554-582). Gibbing: `NPC.ExplodeChar` (`npc.lua:501-528`) when `Weapons.NameTargetToExplode` matches (`weapons.lua:541`).
- **Squad powers.** Black's TK (`black.lua:607` writes `Life = 0`, `628` uses `DoDamage`), ghost bullet (`threadsblack.lua:245` and `254` write Life directly, `266` uses `DoDamage`), Ababanili (`ababanili.lua:376-378`), Church's sabre (`weaponschurch.lua:768`).

Direct `Life` writes outside `DoDamage` (scripted kills and special cases):
- `EnemyGen.Stop` (`enemygen.lua:170-171`, `191-192`).
- Child/Ghost Cruzader partner kill (`childcruzader.lua:466-472`, `ghostchildcruzader.lua:251-258`).
- Bosses: `summerianinanna.lua:377-378`, `summerianutu.lua:200-207`, `summeriannanna.lua:200-207`, `summerianninlil.lua:223`, `gladiador.lua:452`, `puppetgod.lua:446`.
- Pillbox and flamethrower bunker (`wwii_pilbox_a.lua:128`, `147`; `wwii_lanzallamas_a.lua:124`, `131`).
- Level scripts: `alk_bunker_01/mapinit.lua:71`, `sum_ziggurat_04/mapinit.lua:54`, `wwii_pillboxes/mapinit.lua:609`, `wwii_pillboxes/mapscenes.lua:116`, `cru_river/mapscenes.lua:103-105`, `rom_outskirts/mapscenes.lua:97`.

Inferred / unknown:
- [I] Writing `Life` is what makes the engine run the class callbacks. `ac.OnDamage(MyName, AttackerName, damage)` runs **after** the Life decrement: Behemoth and the pillbox undo it with `ent.Life = ent.Life + damage` (`behemoth.lua:398-401`, `wwii_pilbox_a.lua:123-127`). `QuickConsole.killall` kills by writing `Life = 0` (`quickconsole.lua:825-834`).
- [I] The engine probably detects the change by comparing with `PrevLife` during the entity update. `MapScenes.RemoveBehemoth` sets `PrevLife = 0` and calls `bijimot:CallOnDeath()` explicitly on an inactive entity (`cru_river/mapscenes.lua:98-108`), which suggests **inactive entities do not fire OnDeath by themselves**.
- [U] How the engine fills `AttackerName` for `OnDamage`/`OnDeath`, `Weapons.OnCharDeath(EntityName, From)` and `AIEnemy.OnDamageEvent(entity, attacker)`. The candidates are `From.Hit_Target` (`weapons.lua:307`) and `To:SetLastBodyPiece(From)` (296).
- [U] Fire damage over time (`FireRemainTime`, `bCanBurn`; `weapons.lua:252-255`, `fx/fire.lua:14-53`). `Fire.FireOn`/`FireOff` are **burning-effect** callbacks set per character (`cultistamelee.lua:446-447`). They are not weapon-fire callbacks. The burn damage itself is not in Lua.

### 3.2 What happens on death [O]

- **Global hook** `Game.Set("OnDeathChar", "Weapons.OnCharDeath")` (`weapons.lua:52`). For non-green WalkChars with `UsrControl == -1` that are not in `Weapons.IgnoreDeathList` (Behemoth, 345), it calls `Weapons.DestroyCharacter` and `Team.TargetDown` (347-356). Team.TargetDown is only radio chatter (`team.lua:1210-1219`).
- **`Weapons.DestroyCharacter`** (`weapons.lua:237-263`):
  - for generator groups, calls `EnemyGen.GeneratorEnemyDead` (241-243), which activates the group if needed and **schedules the next spawn** (`enemygen.lua:62-80`);
  - calls `Effects.FXCleanUpOnDeath`;
  - schedules removal: ashes for burning bodies, `uData.TimeToRemove`, 3 s for ragdolls (`oActClass.UseRagdollToDie`), otherwise 0.5 s;
  - `Weapons.RemoveCharacter` → `RemoveChar` → `e:Del()` (265-280, 588-593). Removal is immediate when the body is not visible (`FX.CheckSphereVisibility`), so timing differs per machine.
- **AI death event** `behav.OnDeathEvent = "AIEnemy.OnDeathEvent"` (`aienemy.lua:20`, 368-372) → `AISetEnemies.OnDeathEvent` and `AISquad.OnDeathEnemyEvent` (`aisquad.lua:210-217`). These manage team alert state and squad re-targeting.
- **Class callbacks** `ac.OnDeath`/`ac.OnDamage` per enemy class:
  - `CultistaMelee` head explosion (`cultistamelee.lua:407-431`);
  - `CultistaExplosivo` delayed explosion with area damage (`cultistaexplosivo.lua:392`, `588`, `713-728`);
  - Child/Ghost partner kill;
  - Behemoth (`behemoth.lua:797-807`).
- **Group callbacks from map data** (`el_*`, `npc.lua:149-155`). Non-empty values across all levels:
  - `OnAllDeath`: 198 (signature `(GroupName)`);
  - `OnAttackAI`: 79 (`(EntityName, GroupName)`);
  - `OnDeath`: 31 (`(EntityName, AttackerName)`);
  - `OnDamage`: 28.
  
  These are the "kill N enemies to continue" logic:
  - `SaveGame.FlagCounter(name, N)` (`savegame.lua:390-396`, 73 uses), for example `wwii_biggates/mapcallbacks.lua:111-117`;
  - `GetEntitiesLeft()` cross-checks between groups (`rom_palace_01/mapcallbacks.lua:245-280`), which enable triggers, open doors, start scenes or `NewLevel`;
  - `AreaTriggers.AttackPunishTeam` chains two groups' `OnAllDeath` (`areatriggers.lua:96-119`).
- **Trackers and achievements:** `SaveGame.IncreaseTracker("MeleeKills"/"BlowUpEnemies"/"GhostBulletKills")` on the killer's machine (`weapons.lua:219-221`, `543-546`; `threadsblack.lua:267-269`).
- **Ragdolls:** class flag `UseRagdollToDie`; impulses from `AddShotData`/`AddExplosionData`/`ForcePush` (`weapons.lua:445`, `567`, `580`); `OnCreateRagDoll` marks weak points (`cultistamelee.lua:453-455`). [I] Ragdolls are local PhysX simulations and will differ between machines.

### 3.3 Hooks a mod can wrap

(a) **Report a client's hit to the host.** All are Lua functions, so `Weapons.X = wrapper` works [I]:

| Hook | What it catches |
|---|---|
| `Weapons.DoDamage` (`weapons.lua:288`) | Single choke point for hitscan, melee, explosions, most powers and enemy attacks. On a client: if `From` is the local human and `To` is an enemy, send `hit` and do **not** change `Life`; keep `BodyImpact.OnShot` for feedback. |
| `Weapons.MeleeOnHit` (`weapons.lua:103`) | The direct `Life - 100` case (128). |
| `ThreadsBlack` ghost-bullet code (`threadsblack.lua:240-260`), `Black` TK (`black.lua:607`) | Direct Life writes on enemies and story physics objects. |
| `Weapons.OnShot` (`weapons.lua:381`) | Already has the target name and impact point. Useful to also send a `shot` event so the host can call `AI.NotifySound`/`AI.NotifyImpact` for remote players. Today only `Game.UsrEntity(0)` makes noise (386-391). |

(b) **Apply host-decided damage or death on clients:**

| Action | How |
|---|---|
| Death | `e.Invulnerable = 0; e.Life = 0` (pattern of `EnemyGen.Stop`, `enemygen.lua:170-171`). For an inactive entity, also `e.PrevLife = 0; e:CallOnDeath()` (`cru_river/mapscenes.lua:102-105`). |
| Gibbing | `NPC.ExplodeChar(e, pos, impulse)` (`npc.lua:501-528`), before or instead of `Life = 0`. |
| Must be no-ops on a client | `EnemyGen.GeneratorEnemyDead` (`enemygen.lua:62`), group `OnAllDeath`/`OnDeath` callbacks (that is, the `MapCallbacks.*` functions), `SaveGame.FlagCounter`. |
| Host applying a client's report | Through a copy of `DoDamage` whose "is human" test also accepts remote-owned squad members. The host-side puppet has `UsrControl == -1`, so the stock function would apply the 45% `TeamDamageFactor` roll (`weapons.lua:294`) and suppress the human-only branches. |

---

## 4. Area triggers and story flow

### 4.1 How triggers are built and fire

Observed:
- `MapAreaTriggers.main()` → `AreaTriggers.CreateAreaTriggers()` (`areatriggers.lua:52-63`). Each trigger is `Game.CreateEntity("AreaTrigger", "Trigger")` renamed from the data, with `Boxes`, `OnEnter`, `OnExit`, `OnAllInside`, `OnCameraView`, `bClearOn*`, `ExtraData`, `bActive` (36-50; data example `levels/wwii_biggates/mapareatriggers.lua:5-53`).
- `OnEnter`, `OnExit`, `OnAllInside`, `OnCameraView`, `ExtraData` and `bActive` are saved per checkpoint (`areatriggers.lua:41-48`, `savegame.lua:176-218`).
- Non-empty callbacks over all levels: OnEnter 318, OnAllInside 44, OnCameraView 21, OnExit 6. All are `MapCallbacks.*` strings.
- Callback signature: `(TriggerName, Playerid, ExtraData)`. `Game.GetTriggeredEntity(Playerid)` gives the entering character's name (`areatriggers.lua:86-92`, `121-122`).
- The "triggered entities" are registered by `Game.SetTriggeredEntity(index, o)` for **every** squad member created (`team.lua:131`, called for all members from `CreateTeam`).
- A few callbacks test who entered:
  - `AreaTriggers.IsPlayer(id, Name)` requires `UsrControl == 0` (`areatriggers.lua:86-92`); used in `cru_sewers/mapcallbacks.lua:260-279`, `wwii_brandenburg/mapcallbacks.lua:19`, `rom_chamber/mapcallbacks.lua:16`;
  - `alk_bunker_01/mapcallbacks.lua:232` compares with `"Ross"`;
  - many callbacks pass the name to `TeamTalk.SayCategoryMember`.
- What the callbacks do (counts in level scripts): `NPC.ActivateEnemyGroup` 611, `EnemyGen.Stop` 89, `PhysicsObj.OpenDoor` 132 / `CloseDoor` 65, `SaveGame.NewLevel` 66, `Scene.Play` 50, `SaveGame.AutoSaveWaypoint` 50, `Team.ReviveAll` 96, `SaveGame.FlagCounter` 73, toggling `bActive` of other triggers 87, `ObjectLauncher` 213 (fireball launchers).
  
  Example `wwii_biggates/mapcallbacks.lua`:
  - 8-11: activate two generator groups;
  - 18-20: `SaveGame.NewLevel("WWII_PillBoxes")`;
  - 31-38: chain triggers;
  - 64-70: group-death callbacks enable triggers.
- **Other story entry points that are not area triggers:**
  - usable objects with `UseFunc` (29 in `mapphysic*.lua`; example `wwii_biggates/mapphysiclogic.lua:17-43`, callback signature `(UsrName, ObjName, Action, Descriptor)`, `UseJustEntity` restricts the user);
  - pressure plates (`AreaTriggers.SetupPulser`/`OnEnterPluser`, `areatriggers.lua:175-228`; `uDataOnPulse` 6 uses). `SetupPulser` **resolves the callback string to a function value once** (187-194);
  - physics objects with `OnDeath`/`OnDamage` (4 each);
  - Black's TK targets (`ThreadsBlack.ValidObjects`, `threadsblack.lua:243-255`);
  - scene end callbacks (`Scene.EndOfSceneCallback`/`EndOfSubSceneCallback`/`NextScene`, `scene.lua:459-473`; 25 assignments in levels);
  - `MapInit` polling loops keyed on `Game.UsrEntity(0)`. Example: `wwii_biggates/mapinit.lua:100-114` activates `Enemigator_Group` only when the **local** player is Church and has used the ward.

Inferred:
- [I] Any registered squad member can fire `OnEnter`, AI or human; the `IsPlayer` guards exist for that reason. On the host, remote players' bodies (puppets placed at the client's position) are registered triggered entities, so **the host's triggers already fire for remote players**.
- [I] `bClearOnEnter = true` makes a trigger one-shot: the callback is cleared after it fires, and the cleared value is what the checkpoint save stores.

Unknown:
- [U] `OnAllInside`: does "all" mean every registered member, alive and active ones only, or something else?
- [U] `OnCameraView` uses camera 0. On the host it fires only for the host's view; a client looking at the spot does nothing.

### 4.2 Stopping clients from running story logic

[O] Everything above is Lua called through string names, so a client can neutralise it by replacing table fields. Suggested layers:

1. **Entry points.** After the map libraries load, replace every function in `MapCallbacks` (and the `MapScenes` functions used as `UseFunc`, for example `cru_river/mapscenes.lua:86-91`) with a guard:
   - on a client the guard is a no-op;
   - for `UseFunc` callbacks the guard forwards `use|...` to the host.
   
   This one step covers area triggers, group-death callbacks, use callbacks and pulse callbacks. Pulse callbacks are captured as function values by `SetupPulser`, so either wrap before `SetupPulser` runs, or wrap `AreaTriggers.OnEnterPluser`/`OnExitPluser` (`areatriggers.lua:204-228`) on the client as well.
2. **Effects**, as a second safety net (some calls come from `MapInit`, scenes, class scripts and scheduled functions). On a client these become no-ops unless the call comes from a host message:
   - enemies: `NPC.ActivateEnemyGroup`, `NPC.CreateWithAI`, `EnemyGen.ActivateNextEnemy`, `EnemyGen.ScheduleActivationOfNextEnemy`, `EnemyGen.GeneratorEnemyDead`, `EnemyGen.Stop`;
   - level flow and saves: `SaveGame.NewLevel`, `SaveGame.NewLevelNow`, `SaveGame.AutoSaveWaypoint`, `SaveGame.FlagCounter`;
   - squad and scripted moves: `Team.ReviveAll`, `AreaTriggers.StartSoloMision`/`EndSoloMision`/`FadeAndMove`/`JumpPlayers`;
   - presentation (host-triggered only): `Scene.Play`/`PlayFP`/`PlayFPNI`/`PlayFPNNI`, `PhysicsObj.OpenDoor`/`CloseDoor`;
   - grabs and launchers: `QTE.InGameQTE`, `ObjectLauncher.StartLaunching`.
3. **Host broadcasts** the effects (section 7).

[I] Blocking at the effect level alone is not enough. Callbacks also mutate state directly: `bActive` of triggers, `bArrowCanUse`, `Action` of doors, `MapInit` flags. Blocking at the callback level alone is not enough either, because of `MapInit` polling and class-script side effects. Do both.

---

## 5. AI toggling and puppeting

### 5.1 Fields and functions [O]

| Item | Meaning | Evidence |
|---|---|---|
| `e.oAI.bEnable` | Main AI switch. The squad switch uses it, and the prototype already uses it for squad puppets. | `team.lua` (see campaign doc 2.3); `coop.lua:183`, `194` |
| Things that **re-enable** AI | Animation events `"bAI_bEnable=1"` via `!AnmSetNumVal` added by `MakeChar.AddAditionalAnim` (`makechar.lua:590-598`); `Scene.ShowCharActiveEvent` (`scene.lua:796-805`); `Scene.AICharEnd` (976-981); `QTE.EndOfGameQTEAttacker` (`qte.lua:382-393`); `AIEnemTeamPrev.DeleteMember` (`aienemteamprev.lua:14-17`) | A client must re-force `bEnable = false` every frame. |
| `AI.EnableAIChar(name, 1, behaviour, 0)` | Attaches or enables a behaviour. All observed calls pass 1. | `npc.lua:46`, `49`, `208`; `aigen.lua:310` |
| `AISpec.CreateAI(name, active, behav, 0)` | Creates the oAI. `e.Active` is passed as the second argument. | `aienemy.lua:49`, `aienemiesteam.lua:17` |
| `AI.SetStateChar(STATIC_CHAR, name)` | Forces a state (state ids listed in `aientity.lua:12-24`) | `aigen.lua:49-58` |
| `oAI.bForceDisableControlAllSenses`, `bEnableControlVision/Hearing/Sensory` | Senses on and off | `aigen.lua:113-119` |
| `e.bActive` | Dormant or awake. Inactive enemies are part of the level but not running. | `npc.lua:74`, `272`; `enemygen.lua:128` |
| `e.Active = 0`, `e.TimeSpeed = 0` | Hard freeze used by cutscenes for **every** WalkChar | `scene.lua:614-620`, `603-612` |
| `e.Invulnerable` | Ignore damage | `enemygen.lua:170`, `qte.lua:307` |
| `e.ForceAction` / `e.Action` | Force or set an animation action (both are used everywhere) | `enemygen.lua:127`, `cultistamelee.lua:470-475` |
| `NPC.ModifyAIEnemiesInGroup(G, prop, value)` | Bulk `oAI` field set | `npc.lua:241-246` |

### 5.2 Are enemies the same kind as squad members?

Observed:
- Every enemy, map placed or spawned, is created as `"WalkChar"` (`npc.lua:73`), the same type as the squad (`team.lua:112`).
- Act classes are built with the same `MakeChar` helpers: walk, run and strafe actions with root motion `UseDisp` (`makechar.lua:217-260`).

Special kinds:
- **Fliers:** `CultistaVolador` (`ac.CanFly = 1`, `cultistavolador.lua:115-119`) and `Flies` (`flies.lua:9`; six extra entities per swarm, `npc.lua:104-111`).
- **Turrets:** `WWII_PilBox_A` (`CanFly = 0`, `UseRagdollToDie = 0`, invulnerable through `OnDamage`, killable only by Cole's use action, `wwii_pilbox_a.lua:47-59`, `93-154`) and `WWII_Lanzallamas_A`.
- **Paired ghost:** GhostChildCruzader + `_BadBoy` ChildCruzader (`npc.lua:94-103`).
- **Statues:** `Estatua*` (no AI; `init.EnemiesConfig` `{false, true}`, `init.lua:254-259`).
- **Wheel torture victims:** `Sum_Wheel_*` (spawn siblings, `sum_wheel_a.lua:79-86`; excluded from gibbing, `npc.lua:503-505`).
- **Bosses** with custom damage gating: Behemoth, BlindBehemoth, Maltheus, Vicus, the Summerians, PuppetGod, EvilFirstBorn.

Inferred:
- The `InCtrl_Walk`/`InCtrl_Str` technique *might* move ground enemies, because they are WalkChars with walk actions. It cannot represent flying, emerging (`ForceAction = "Emerge"` for 293 placements), parapet or cover moves, or the scripted attack animations.
- For enemies, **replicating `Pos`/`Ang` plus the current `Action`** is the more general puppet. Keep the prototype's snap-or-nudge correction (`coop.lua:186-227`).

Unknown:
- Whether `InCtrl_*` is honoured on a non-squad class with AI off.
- Whether setting `Action` every time it changes on the host restarts or blends animations correctly.
- Whether root motion plus position correction double-moves the body.

### 5.3 Action events that call into the AI (0.2.7)

The client mirrors the host's enemy actions (`ForceAction`), so their animation events run on the
client too. Four classes end "Appear" / "Disappear" with a call into their AI:
`PsichicCommander`, `EvilFirstBorn`, `SummerianNANNA`, `SummerianUTU` (`oAI:OnAfterAppear()`,
`oAI:OnAfterDisappear()`). With the client's AI off, that call reached a stale pointer: crash
`AccessViolation at 04A0400B (read 00000611)`, stack `0050f4ba` (AI method "OnAfterDisappear",
vtable +0x3a4) -> `005035f0` (AI mode 3) -> `00507c30`, from the Lua method call at `005335ed`
(split test 0.2.7, WWII_PillBoxes G4, the psychic commander; once in about ten runs). On a
client these events now run only their other parts: the ragdoll and the shield effects
(`CoopEnemies.guardAIEvents`, "enemy event ... without its AI" in the log).

---

## 6. Weapons and firing

### 6.1 How a character fires

Observed:
- Weapons are 24 global weapon types (`weapons.lua:20-48`). Each type has callback strings:
  - `w.OnShot` (hit result), for example `weaponsjones.lua:19`, `weaponsnazisoldier.lua:34`;
  - `w.ShotPress`/`w.ShotRelease` (trigger down/up), for example `weaponsnazisoldier.lua:35-36`, `weaponsdelgado.lua:68-69`, `weaponscole.lua:74-75`;
  - `w.OnMeleeHit` (`weapons.lua:91`), `w.OnMelee` (`weaponschurch.lua:71`), `w.OutOfAmmo` (`weapons.lua:64`).
- A character holds them in `oWeapCtrl` slots: `oWeapCtrl:Slot(i)`, `.idMainWeapon`, `.idSecondWeapon`, `.iSlot`, `.iDesiredSlot`, `.oActual`, `.FireCounter`, `:DoMeleeAttack()`, `:CheckMeleeTarget()`. Enemies assign their slot in `OnCreate`, for example `cultistamelee.lua:433-442`, `wwii_pilbox_a.lua:93-106`.
- Human trigger state is readable as `e.owc.Shot` and `e.owc.SecondWeaponTrigger` (`delgado.lua:685`, `weaponschurch.lua:714`, `fp/fp_church.lua:97`).
- `MainWeaponShoot`/`MainWeaponTrigger` and any `InCtrl_Shot`-style fields do **not** appear in any Lua file (grep). The `InCtrl_*` fields used by the scripts are `Sprint`, `UseFPS`, `TimeSwitchCharPressed`, `SwitchChar`, `CornerView`, `ReloadMen`, `ResetSlot`, `ForceCenterCameraVal`, `SwitchMen`, `Walk`, `Str`.
- Many enemy attacks are **animation events**, not weapon fire:
  - `WeaponsLegionary.LaunchPilum` on `Shot`/`ShotStay`/`ShelterDownShot` (`legionary.lua:249`, `266`, `270`);
  - `WeaponsNaziSoldier.LaunchCluster`/`LaunchMortar` (`nazisoldierc.lua:203-206`, `222-223`);
  - melee `HookHitEvent`s;
  - `CultistaMelee.GrabFromAnim` on `QuickEmerge` (`cultistamelee.lua:152`, `505-510`), which starts a grab QTE against `Game.UsrEntity(0)`.

Unknown:
- Whether writing `owc.Shot` or some `InCtrl_*` field makes an AI-disabled WalkChar fire. Not visible in Lua; needs a test or engine reverse engineering.
- How the engine's AI pulls the trigger.

### 6.2 How hits are resolved [O]

| Kind | Mechanism | Evidence |
|---|---|---|
| Hitscan | The engine traces the shot (range `w.ShotDist`, `w.Dispersion`, `w.nShots` pellets) and calls `w.OnShot(EntityName, TargetName, X, Y, Z, iShot)`. `TargetName == ""` means a miss. Lua plays sound and FX and calls `DoDamage`. | `weapons.lua:381-465`; `weaponsjones.lua:112-174`; `weaponsnazisoldier.lua:66-88` |
| Physical projectiles | `Game.CreateEntity(name, "Missile", pos)` with `Vel`, `Gravity`, `bExplodeOnHit`, `TimeToExplode` and the callbacks `OnHit`/`OnExplode`/`OnZeroSpeed` | `weaponsnazisoldier.lua:162-193`; `weaponslegionary.lua:32-55`, `86-101`; `weaponsblack.lua:113-121`; `weaponscole.lua:685-732` |
| Melee | Animation events at a given frame → `CheckMeleeTarget` or `DrawWeapon` ray → `DoDamage` | `weapons.lua:136-188`; `weaponscultistamelee.lua:7-33` |
| Explosions | `SphereCall` damage and impulse | `weapons.lua:485-582` |

[I] Consequence for puppets: replaying an enemy's `Action` on a client also **replays its animation events**: melee damage, pilum and mortar launches, grab QTEs, AI re-enable. Clients must filter damage in `Weapons.DoDamage` and block the grab and QTE functions. The visual side effects (projectile flight, sounds) can stay.

[I] Showing hitscan fire on a puppet: since an AI-off WalkChar cannot be made to fire from Lua (unknown above), the host should send a `efx` event and the client should call the FX-only functions with the host's impact point:
- `WeaponsNaziSoldier.OnShotFX` (`weaponsnazisoldier.lua:109`);
- `WeaponsCruzader.OnShotFX` (`weaponscruzader.lua:67`);
- `WeaponsPilBox.OnShotFX` (`weaponspilbox.lua:78`);
- `FireWeapons.DoFire(entity, chartype, weapon, Tracer, iShoot, TargetName, TargetPos)` (`fx/fireweapons.lua:255`, used at `weaponsjones.lua:173`);
- plus `Sound.PlaySound`.

---

## 7. Recommended design: host-authoritative enemies

> Written before the code (2026-10-18/19). The messages and functions named here were built differently or not at all; the built protocol is in `architecture.md` (section 4).

### 7.1 Principles

1. **The host is the only simulator** of enemy AI, spawning, damage resolution, deaths, group counters, triggers, use actions, scenes, doors, checkpoints and level changes.
2. **Clients render.** Their enemies are puppets: AI permanently off, transform and action from the host. Their story callbacks are dead. Their weapons resolve hits locally, for responsiveness and accuracy, and **report** them instead of applying them.
3. **Damage to a human-controlled body** is decided by the host (enemy AI and projectiles run there) and **applied by the owner** of that body. This matches the prototype, where each owner streams its own body's state including `Life` (`coop.lua:141-147`).
4. Reuse the prototype transport: text messages `type|field|...`; `Net.CoopSend(peer, 0, …)` unreliable and `Net.CoopSend(peer, 1, …)` reliable (`coop.lua:97`, `154`, `253`); the per-frame hook `Coop.onFrame` (`coop.lua:345-359`).

### 7.2 Messages

Host → clients:

| Message | Channel | When | Client action |
|---|---|---|---|
| `e\|name\|x\|y\|z\|yaw\|action\|flags` | 0, about 10 Hz, active and alive enemies near any human | snapshot | Find the entity (if missing, send `ereq`). Set `bActive` from `flags`. Nudge or snap `Pos`, set `Ang`. If `action ~= e.Action`, set `e.ForceAction = action`. Keep `oAI.bEnable = false`. |
| `espawn\|name\|class\|group\|x\|y\|z\|yaw\|forceAction\|active` | 1 | Host wrapper on `NPC.CreateWithAI` (covers generators and boss summons); also the reply to `ereq` | Create a `WalkChar` with **that name** (`Game.CreateEntity(name, "WalkChar")`, or `CreateSingleEnemy` and then `e.Name = name`). Set `ActCtrl`, `EntityList`, `TgType`; insert into `NPC.Groups[group]`. Create the AI (so `e.oAI` is not nil for scripts) and set `bEnable = false`. |
| `egroup\|group` | 1 | Host wrapper on `NPC.ActivateEnemyGroup` (only when the status var flips) | Set the status save var. For non-generator groups set members `bActive = true` with AI off. Generator groups: nothing (spawns arrive as `espawn`). |
| `edie\|name\|attacker\|cause[\|x\|y\|z\|impulse]` | 1 | Host wrapper on `Weapons.OnCharDeath` (pre-call) and `NPC.ExplodeChar` | `cause = gib`: `NPC.ExplodeChar(e, V3D(x,y,z), impulse)`. Then `e.Invulnerable = 0; e.Life = 0`; for an inactive entity also `PrevLife = 0; e:CallOnDeath()`. Stop driving this puppet. |
| `eroster\|n1,n2,...` | 1, 1 Hz | List of live enemy names | Delete, or `Life = 0`, local enemies that are not on the list and are not dying. Request missing ones with `ereq`. |
| `efx\|name\|weaponKind\|target\|x\|y\|z` | 0, rate-limited | Host wrappers on the enemy `OnShot` functions (`WeaponsNaziSoldier.OnShotMinigun`/`OnShotFlamethrower`, `WeaponsBritish.OnShotMachinegun` `weaponsbritish.lua:47`, `WeaponsCruzader.OnShotHarpoon`/`OnShotCrossbow`, `WeaponsPilBox.OnShotCannon`/`OnShotFlamethrower` `weaponspilbox.lua:56`, `162`) | Call the matching `*.OnShotFX` / `FireWeapons.DoFire` and the sound. No damage. |
| `pdmg\|victim\|amount\|attacker` | 1, to the owner of `victim` | Host `DoDamage` wrapper when `To` is a remote-owned squad body | Owner: `Life = Life - amount`, plus the usual hit feedback (`Soldier.CharDamage`-style red flash). |
| `scene\|class\|mode` / `sceneabort` | 1 | Host wrappers on `Scene.Play`/`PlayFP*`/`AbortScene` | Play the same scene (presentation only); end it on `sceneabort`. |
| `act\|entity\|Action` | 1 | Host wrappers on `PhysicsObj.OpenDoor`/`CloseDoor`, plus a periodic diff of door and pulser `Action` | Set `Action`. |
| `prop\|entity\|field\|value` | 1 | Diff of `bActive`/`bArrowCanUse` on triggers and usable objects | Mirror, so use prompts appear correctly. |
| `level\|name` / `ckpt\|id` | 1 | Host wrappers on `SaveGame.NewLevel(Now)` and `SaveGame.AutoSaveWaypoint` | Load the same level, or record the checkpoint id. |

Client → host:

| Message | Channel | From | Host action |
|---|---|---|---|
| `hit\|enemy\|damage\|attackerChar\|flags` | 1 | Client wrapper on `Weapons.DoDamage` (and `MeleeOnHit` case 3, Black's direct writes) when attacker = local human and target = enemy. `damage` already includes the body multiplier computed locally. | Apply through the patched `DoDamage(Game.GetEntity(attackerChar), enemy, damage)`: the human test accepts remote-owned bodies, so the 45% roll is not applied. Set `attacker.Hit_Target` so `AttackerName` resolves [U]. Explosion kills from a client set `flags = gib` so the host can call `NPC.ExplodeChar`. |
| `shot\|char\|target\|x\|y\|z` | 0, rate-limited | Client wrapper on `Weapons.OnShot` | `AI.NotifyImpact(...)`/`AI.NotifySound(...)` from the remote body, as `weapons.lua:386-391` does for user 0; muzzle FX on the puppet; relay to other clients. |
| `use\|callback\|char\|object\|action\|descriptor` | 1 | Client guard on `UseFunc` callbacks | Call the original callback with `UsrName = char`. |
| `ereq\|name` | 1 | Client snapshot for an unknown name | Reply with `espawn`. |

### 7.3 Functions to wrap

Host:

| Wrap | Purpose |
|---|---|
| `NPC.CreateWithAI` (post) | `espawn` |
| `NPC.ActivateEnemyGroup` (post) | `egroup` |
| `Weapons.OnCharDeath` (pre), `NPC.ExplodeChar` | `edie` |
| `Weapons.DoDamage` | Treat remote humans as humans (`weapons.lua:294`, `313`). Route damage aimed at remote-owned bodies to `pdmg` and do not apply it locally. |
| `AIEnemy.FindMembRandom`, `AIEnemy.FindMembVisNear` (`aienemy.lua:187-215`) | Remote humans' puppets are AI-disabled and are not `AIGen.GetPlyName()`. `AIGen.GetMembRandMetaTeam` (`aigen.lua:60-80`) and `FindMembVisNear` (`aienemy.lua:197`) would skip them, so enemies would mostly ignore remote players. Patch narrowly here, not in `AIMemberSquad.IsEnable`, which the squad AI also uses. |
| Enemy `OnShot` functions | `efx` |
| `Scene.Play`/`PlayFP`/`PlayFPNI`/`PlayFPNNI`/`AbortScene`, `PhysicsObj.OpenDoor`/`CloseDoor`, `SaveGame.NewLevel`/`NewLevelNow`/`AutoSaveWaypoint` | Broadcasts |
| Snapshot sender in `Coop.update` | Every tick |

Client:

| Wrap | Purpose |
|---|---|
| All `MapCallbacks.*` (and the `MapScenes`/`MapInit` functions referenced by `UseFunc`) | Guard (no-op, or forward `use`) |
| `AreaTriggers.OnEnterPluser`/`OnExitPluser` | No-op |
| Effect functions listed in 4.2 (enemy spawn and activation, saves, `NewLevel`, `ReviveAll`, solo-mission, QTE, `ObjectLauncher`) | No-op unless `Coop.fromHost` is set |
| `Weapons.DoDamage` | Report-or-drop filter. Apply only self-inflicted costs and messages from the host. |
| `QTE.InGameQTE` (return false), `CultistaMelee.GrabFromAnim`/`GrabAttack`, `Arnold.GrabAttack`, `CultistaVolador.GrabAttack` | Block grabs |
| `Scene.AbortScene` | Local skip disabled, or forwarded to the host |
| Frame hook | For every known enemy, force `oAI.bEnable = false`, then drive the puppet |

### 7.4 Join and checkpoint handshake

1. Both machines load the same level and checkpoint. Placed enemies and pools then exist on both sides with matching names (1.3).
2. When the client is ready, the host sends:
   - `egroup` for every activated group (save vars `<level>.EnemyGroup.*.Status`);
   - `espawn` for every runtime enemy;
   - `eroster`;
   - the door and trigger `Action`/`prop` state.
3. Pool entities on the client stay dormant forever. Their classes may differ from the host's (1.3); the host deletes and recreates pool enemies when it activates them, and the client follows the `espawn`.

### 7.5 Risks of the design

- **Latency of kills.** Kills appear one round-trip after the hit. Mitigation: local hit FX and a local "predicted death" animation without `Life = 0`.
- **Damage to players uses host positions.** A client can dodge locally and still get hit on the host. This is acceptable in co-op; a server-side distance check can be added.
- **Animation events on puppets.** Damage, projectiles, QTEs and AI re-enable fire locally on every client. Every source of side effects must be filtered; unknown ones show up as divergence. A useful debug check: count `DoDamage` calls dropped on the client per source.
- **`UsrEntity(0)`-keyed story** on the host. Examples: `wwii_biggates/mapinit.lua:100-114` progresses only when the **host** plays Church; `QTE.canNotQTEAttack` requires `UsrControl == 0` (`qte.lua:278-280`), so grabs only ever target the host. These need per-level patches (see campaign doc 6.1).
- **`OnCameraView` triggers** (21) fire only from the host's camera [U]. `OnAllInside` (44) depends on unknown engine semantics.
- **Global time and scenes.**
  - `Scene.Play` freezes every WalkChar (`scene.lua:622-638`) and sets `PhysXSpeed = 0` (746-749) on the host, including remote puppets.
  - `Game.SetTimeSpeed` from Cole's or Black's powers or the switch flight affects only the machine that calls it. A client's slow-time does not slow the real enemies.
- **Entity name collisions** if `Game.CreateEntity` renames duplicates [U]. Verify that `espawn` really produces `name`.
- **Bandwidth.** Snapshots for 10-20 enemies at 10 Hz are small, but batch them per packet and send only active, nearby enemies.

### 7.6 Riskiest special cases

1. **Bosses with custom damage.**
   - Behemoth: `OnDamage` heals and routes damage to seals and ragdoll parts, `behemoth.lua:398-430`; ignored by `OnCharDeath`, `weapons.lua:345`; killed by a use-triggered FP scene, `cru_river/mapscenes.lua:86-108`.
   - Summerian bosses write `Life` themselves (`summerianutu.lua:200-207` etc.). EvilFirstBorn swaps squad members and instakills (`evilfirstborn.lua:352`, `411`, `421`).
   - BlindBehemoth hunts by sound (`Game.Get("BlindBehemothInMap")`, `weapons.lua:387`). Remote players' noise must be emitted on the host.
   
   Per-boss testing is mandatory, and ragdoll-part damage (`weapons.lua:520-532`) only exists on the machine that simulates it.
2. **Scripted kills and counters.** `EnemyGen.Stop(..., true)`, `FlagCounter`, `GetEntitiesLeft`, `AttackPunishTeam`, direct `Life = 0` in `MapInit`/`MapScenes`. These must run only on the host; their deaths reach clients as `edie`.
3. **QTE enemies.**
   - In-game grabs: CultistaMelee, CultistaVolador, Arnold (`qte.lua:282-317`), started from AI or from animation (`cultistamelee.lua:505-510`) and only against `UsrControl == 0`.
   - Scene QTEs (`QTE.AddSequence`, `alk_tomb/mapscenes.lua:29-34`).
   
   Phase 1: allow grabs only on the host's player and block them on clients. Phase 2: forward the grab to the victim's owner and return the result.
4. **Linked or composite enemies.**
   - GhostChildCruzader and `_BadBoy` (partner killed on death; `childcruzader.lua:459-472`, `ghostchildcruzader.lua:243-258`).
   - Flies (6 sub-entities).
   - Sum wheels (siblings).
   - CultistaExplosivo: its delayed explosion (`cultistaexplosivo.lua:713-728`) runs on every machine where it dies. Damage is filtered on clients, but the physics push still happens.
5. **Turrets.** `WWII_PilBox_A` is invulnerable until Cole uses it. `OnUse` plays an FP animation for the user and explodes the turret after 6 s (`wwii_pilbox_a.lua:132-154`). Needs `use` forwarding and an FP animation on the client that used it; `MakeFP.CoolUse` relies on user 0 [U].
6. **Ragdolls and physics objects.** Local PhysX means bodies, debris and crates differ per machine. Cosmetic, except for:
   - physics objects with story `OnDeath`/`OnDamage` (4 each in map data);
   - Black's TK puzzle targets (`threadsblack.lua:243-255`);
   - fireball launchers (`ObjectLauncher`, `fx/*/mapeffects.lua`), which spawn damaging missiles.
   
   Run these on the host and mirror their outcome.
7. **Doors and pulsers.** Doors are animation state (`physicsobj.lua:486-506`) with portal switching on an animation event. Mirror `Action`, not the callbacks. Pulsers react to bodies standing on them (`areatriggers.lua:204-228`); only the host should evaluate them.

# `Game.UsrEntity(0)` audit: story code that assumes "the one player"

Scope: every use of `Game.UsrEntity(0)` and its wrappers (`AIGen.GetPlyName`, `Scene.usr`,
`MapInit.player` / `MapInit.EPlayer`, `UsrControl == 0` checks, `IgnoreUsrControl` on the
player, `Team.SwitchSoldier(Game.UsrEntity(0).Name, ...)`) in `levels/*/scripts/*.lua`,
`scripts/missions/*`, the boss and story characters in `scripts/chars/*` and
`models/physics/*/entitydescriptor.lua`. Paths are relative to `work/src/`.
Read-only analysis. Nothing was run in game. `[inferred]` marks conclusions drawn from the code
without a test.

## How the co-op layer changes the meaning of `UsrEntity(0)`

- **Host:** `UsrEntity(0)` is only the host's own body. Remote players' bodies are puppets.
  `drivePuppets` (`mod/lua/coop.lua`) turns their `oAI.bEnable` off every frame and overwrites
  `Pos`/`Ang` from the network.
  - Consequence 1: `AIGen.GoAndAction` on a remote-owned body never reaches its goal, so its
    `funcExec` callback never runs. `GoAndAction` also sets `Invulnerable = 1` until the walk ends
    (`aigen.lua:105-112`), so a remote body can stay invulnerable for the rest of the level
    [inferred].
  - Consequence 2: `Pos` writes on a remote body are undone within one frame.
- **Clients:** they drop map callbacks locally, but the host replays every `MapCallbacks.*` call
  on them (`coop_world.lua` `W.replay`). `MapInit.main`, scheduled polls and scene-end callbacks
  are not guarded, so they also run on each client.
  - On a client, `UsrEntity(0)` is that client's own body.
  - Locks and walks of "the player" run once per machine on each machine's own body. This is
    partly what we want.
  - A lock that is released only by the AI arrival of **another** body stays on forever on a
    client: all non-local bodies are puppets there, with AI off [inferred].
  - Gates that call guarded functions (`NPC.ActivateEnemyGroup`, `EnemyGen.*`, `SaveGame.*`) only
    take effect on the host. Ungated side effects (doors, scenes, `Life` writes) diverge per
    machine.
- **Switching:** `Team.SwitchSoldier` returns `false` when the target is owned by another human
  (`Coop.wrapTeam` wraps `Team.IsPlayerAvaliable`, which `team.lua:574` checks). Story code that
  waits for the switch to finish (`Team.EndSwitchCallback`) then never continues.
- **Character events:** power events such as Church's ward, the blood rune and Jones' astral
  use are computed on the machine that owns the body. Callbacks the level hooks into them
  (`Church.callOnWard`, `ThreadsChurch.OnWardCallback`, `Game.Set("RuneBloodActive")`,
  `SummerianNINLIL.Use`) fire on that machine only, not on the host [inferred].

Classes: **A** gate (progress waits on or branches on "the player is X"), **B** staging (locks,
AI walks, teleports, forced switches), **C** cosmetic or local (HUD, hints, camera, FX),
**D** harmless.
In the "Trigger" column: *poll* means a self-rescheduling `Game.AddScheduledFunc` loop; *cb*
means a `MapCallbacks` entry (replayed on clients); *AI-arrive* means a `GoAndAction` callback;
*chat-end* means a `TeamTalk.InitIncidentalChat` end callback; *scene-end* means
`Scene.EndOfSceneCallback`; *engine* means an act or AI event called by the engine by name.

---

## Act 1: Al-Khali (host is always Ross: `Coop.startChar`)

| Level | File:line | Function | Trigger | Cls | Failure in co-op | Proposed fix |
|---|---|---|---|---|---|---|
| alk_desert | `alk_desert/scripts/mapinit.lua:39` | `MapInit.TestTap` (uses `GetEntity("Ross")`, not `UsrEntity`) | poll | D | none: host = Ross | none |
| alk_city | `alk_city/scripts/mapinit.lua:48` | `MapInit.OrdersTutorial` | cb `AreaTrigger855_0` → poll | C | hint reads the host's D-pad only; on clients it runs on their own body (replay) | none |
| alk_tomb | `alk_tomb/scripts/mapinit.lua:147, 153-162` | `MapInit.StartSayGoodbye` → `MiraDetrasDeTi` → `LiberateMe` | chat-end (`TalkingAfterKillFade`) → scheduled; unlock on AI-arrive of the player's own body | B | Ross (host) is locked and AI-walked, as in vanilla. Each client replays it on its own body: the lock is released by its own arrival, so it works. But a client holding Jones/Cole/Delgado has its body set `bActive=false` by the same function, never arrives, and stays locked [inferred]. The `Pos` writes on Church/Black/Rawlings puppets are undone. | On clients, skip `IgnoreUsrControl` and the walk when the local body is `bActive == false` (spirit mode instead). Or wrap `MapInit.MiraDetrasDeTi`: host broadcasts "cinematic lock + goto pos" to every human (generic mechanism M2). |
| alk_bunker_01 | `alk_bunker_01/scripts/mapinit.lua:53, 60` | `MapInit.GoToRawlings` / `MapInit.CryForTheChild` | cb `trigGoToRawlings_0` (checks Ross) → AI-arrive | B | host = Ross, so the lock and walk act on the right body. On clients the replay locks their own body (`UsrEntity(0)`) but AI-walks **Ross** (a puppet there): `OnRossArrived` never fires on the client, so `CryForTheChild` never unlocks the client [inferred]. | Wrap `MapInit.GoToRawlings`: on clients do nothing (the host-only walk of Ross). Generic: M4 (client lock watchdog). |
| alk_final | `alk_final/scripts/mapinit.lua:118-120` | `MapInit.EveryBodyLooksPlayer` | TeamTalk voice callback `Mission_Alk_Final_BEnd6` | C | Delgado/Jones/Rawlings turn to Ross; walks of puppets are ignored | none (optionally skip remote-owned names) |

Related AI-walk gates in Act 1 (no `UsrEntity`, same root cause: a scripted walk of a
squad member that a remote human may hold):

| Level | File:line | Function | Cls | Failure | Fix |
|---|---|---|---|---|---|
| alk_desert | `alk_desert/scripts/mapinit.lua:85` | `MapInit.OpenTheTkDoor` → `OpenTheFuckingDoor` opens door `o` | A | Black held by a remote player: never "arrives", door never opens, **stall** | M1b (`GoAndAction` on a remote body is delegated to the owner, or completed by teleport + callback) |
| alk_city | `alk_city/scripts/mapinit.lua:31` | `MapInit.OpenTheTkDoor2` → `OpenTheFuckingDoor1` (door `cultista_destruye_esta`) | A | same, **stall** | M1b |
| alk_tomb | `alk_tomb/scripts/mapinit.lua:181, 196` | `MapInit.OpenTheTkDoor1/2` → doors `Puerta_Black_abre`, `puerta_fistro` | A | same, **stall** | M1b |
| alk_bunker_01 | `alk_bunker_01/scripts/mapinit.lua:38, 48` | Rawlings walk → `OnRawlingsArrived` (`CryForTheChild` needs both Ross and Rawlings) | A | Rawlings remote: **stall** before the Cole console phase | M1b |
| alk_bunker_01 | `alk_bunker_01/scripts/mapinit.lua:73` | `MapInit.GoColeToManipulate` → `StartManipulation` → `MoveSquadAndStartCombat` / `Ambush` | A | Cole remote: the ambush and FakeCole never start, **stall** | M1b; also the remote Cole player becomes bodiless at `DelayedDeactivate` (spirit) |

## Act 2: WWII

| Level | File:line | Function | Trigger | Cls | Failure in co-op | Proposed fix |
|---|---|---|---|---|---|---|
| wwii_biggates | `wwii_biggates/scripts/mapinit.lua:38-67` | `MapInit.TestTap` (`usr.Name == "Black"` starts chat `Mission_wwii_BigGates_Black` → `EndIncidentalBlack` → `InitClearPath`, `IncidentalDo = 2`) | `MapInit.main` → poll | A (soft) | Black held by a client: the host never starts the Black dialogue or the clear-path radio hints. `TK_Trigger` is a Black-only use (claim) so no stall [inferred]. The client runs the same poll locally on its Black and starts the chat **locally only**. | Wrap `MapInit.TestTap` on the host: `UsrEntity(0)` resolves to Black's entity when a human holds Black (M1). Set `usr.owc` reads to the puppet's replicated input, or simply treat "Black is human" as true. |
| wwii_biggates | `wwii_biggates/scripts/mapinit.lua:100-113` | `MapInit.TestWard` (`usr.Name ~= "Church"` / `MapInit.WardCalled` → `NPC.ActivateEnemyGroup("Enemigator_Group")`) | chat-end `Incidental_Church_Now` → poll | **A** | Church held by a client: the host never activates `Enemigator_Group`, so `Enemigator_Group_0` never enables `AreaTrigger791`, the Cole door `puertaEnd` never opens: **stall**. Also `MapInit.WardCalled` is set by `Church.callOnWard` (`church.lua:615`), which fires on the machine that runs the ward (the client) [inferred]. | Wrap `MapInit.TestWard` with M1 (resolve to Church's holder). Forward "Church ward used" from the owner to the host (call `Church.callOnWard` there): M3. Fallback: activate the group when any human is Church and 60 s have passed. |
| wwii_biggates | `wwii_biggates/scripts/mapinit.lua:118-136` | `MapInit.TestAbab` | chat-end → poll | C | hints only (`SpecialPress` is set regardless of who plays) | none (it already runs per client) |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:42-124` | `MapInit.TestCole` (tutorial; enables `Cole.PressSpecialInfinite/Fire` on the act class) | chat-end `Mission_wwii_Pillboxes_Begin` (cb, replayed) → poll | C | the class unlock happens per machine; the Cole client gets it from its own replay [inferred]. The host only gets it if the host is Cole (or via `EndOfColeTutorial`, cb line 43). | none, or set the unlocks unconditionally in co-op |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:126-146` | `MapInit.AfterRawlingKilled` → `AreaTriggers.StartSoloMision` (`areatriggers.lua:161`), `MapInit.TestCure` (hint at 138) | scene-end `OnEnd_DelgadokillsRawlings`, `PillBoxOnUse` | B | the solo mission resets switch and orders on the host's class only. `TestCure` waits for `Rawlings.Life > 0`; the revive must reach the host (`coop_team` revive relay). | Revive replication already exists. Solo lock: ignore in co-op (S5 proposal). |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:163-215` | `MapInit.TestRawlings` | chat-end → poll | C | tutorial or class unlock per machine (as TestCole) | none |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:272-321, 374-426` | `MapInit.StartIncidental`, `PlayerLooksRawlingsAgain/Delgado/DelgadoAgain/Jones/Black/Bitch` (`MapInit.EPlayer`) | scheduled from `AfterRawlingHealed`; TeamTalk voice callbacks | B | only the host's body is locked and AI-turned. Remote bodies are teleported (`Pos` undone) and AI-walked (ignored); clients replay nothing here (not a cb chain, except the chat itself) [inferred], so remote players walk freely through the "conflict" dialogue. | M2: lock every human for the window `StartIncidental` … `ActivateNaziBitch`. Teleport via the owner (send `goto`). |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:419, 514` | `MapInit.OnPlayerLookedAtBitch`, `MapInit.ActivateNaziBitch` (unlock) | AI-arrive, chat-end | B | pair of the above | unlock all humans (M2) |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:442-467` | `MapInit.LookAtThatBitch` (skips `EPlayer`) | scheduled | B | AI look-at on remote puppets is ignored | M2, skip remote-owned names |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:469-505` | `MapInit.RestoreSquad` (AI on for all but `UsrEntity(0)`) | chat-end | D | AI flag on puppets is reset by `drivePuppets` | none |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:582-603` | `MapInit.RawTutReposPeople` | scheduled from `StartRawlingsTutorialScene` | B | repositions only the AI; puppets ignore | none, or M2 |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:615-623` | `MapInit.ActivateBigFuckerGroup` (`UsrEntity(0) == ERawlings` → `bigFuckerGroup`, `KillSomeone`) | cb `RawlingsTutorialTrigger_0` → poll every 0.4 s | **A** | Rawlings held by a client: the host never activates `bigFuckerGroup` (the ghost-heal tutorial wave), **stall** of the Rawlings tutorial and possibly the level [inferred]. On the Rawlings client the replayed poll runs `KillSomeone` locally (sets `EJones.Life = 0` there) → desync [inferred]. | Wrap `MapInit.ActivateBigFuckerGroup` with M1 (true when any human holds Rawlings). If nobody holds Rawlings, offer it through the `coop_claim` prompt (AI fallback = proceed after 30 s). On clients, make the replayed poll a no-op. |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:641-677` | `MapInit.StartLichtScene` → `EnsureLookingBitch` (poll) → `PlayerInPos` → `ActivateBCs` → `RestoreUsrControl` | cb `TriggActivateBCs_0` | B | progress depends on the **host's** body reaching the vantage point. That is fine, but on clients the replay locks and AI-walks their own body. Their `PlayerInPos` reaches `ActivateBCs` → `PsichicCommander.ActivateBCs` locally [inferred]. Remote players get a forced look at the Bitch on their own machine (probably acceptable). | Keep it (it already acts as "every human"). On clients skip `PsichicCommander.ActivateBCs` (story side effect) unless it comes from the host. |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapinit.lua:682-688` | `MapInit.SchHintsPillBoxes` | cb → poll | C | hint per machine | none |
| wwii_pillboxes | `wwii_pillboxes/scripts/mapscenes.lua:198-200` | `MapScenes.MemberOnOff` (`MapScenes.player`, never assigned) | | D | none | none |
| wwii_mosque | `wwii_mosque/scripts/mapinit.lua:60-85` | `MapInit.TestJones` | poll | C | astral hints per machine | none |
| wwii_mosque | `wwii_mosque/scripts/mapinit.lua:87-105` | `MapInit.TestDelgadoFlame` | cb → poll | C | hints | none |
| wwii_mosque_inside | `wwii_mosque_inside/scripts/mapinit.lua:97-127` | `MapInit.BlackTrickShoot` | poll | C | hints. It also registers `ThreadsBlack.ValidObjects.oBritishBomb`, which every machine needs for its own Black: it runs on each machine, so OK [inferred]. | none |
| wwii_mosque_inside | `models/physics/wwii_britishbomb/entitydescriptor.lua:30` | `PhysicsObj.BritishBombOnDamage` (`UsrEntity(0).Name == "Black"` → delete bomb, `BritishBombPetaInit`, `MapEffects.FXExplosion`) | engine OnDamage | **A** | a client's Black shoots the bomb. The client's `Weapons.DoDamage` wrapper only forwards hits on enemies, so the bomb takes the damage **locally on the client**: it explodes and opens `oMosqueExplosion` only there. On the host the bomb never explodes (also the host's `UsrEntity(0)` is not Black): **stall** and world desync. | Forward damage on story objects (`oBritishBomb`) from client to host. On the host wrap `PhysicsObj.BritishBombOnDamage` so the check is `AttackerName == "Black"` and Black is human (M1 with the attacker). On clients make the descriptor a no-op unless replayed from the host. |
| wwii_mosque_inside | `wwii_mosque_inside/scripts/mapinit.lua:195-198` | `MapInit.BarndonLooksPlayer` | voice callback → poll | C | NPC faces the host | none |
| wwii_mosque_inside | `wwii_mosque_inside/scripts/mapinit.lua:200-210` | `MapInit.StartRobertson` (NPCs walk to `UsrEntity(0).Pos`; `OnRobertsonArrived` starts the Tuck chat) | scheduled | C | NPCs walk to the host's body; the chat starts anyway | none (or target the nearest human) |
| wwii_vigil_inside | `scripts/chars/psichiccommander.lua:354-373` | `PsichicCommander.EndOfBitch` (lock + AI-walk `UsrEntity(0)` to the Bitch), `PsichicCommander.NilFunc` | engine (`CrazyInit` event / `oAI.EndOfBitch`) | B | only the host's body is locked and walked. The `RawlingsTorture` scene starts after 3 s anyway (no stall). Clients do not run it (engine event on the host only) [inferred]. | M2: lock all humans for the 3 s; the scene then takes over |
| wwii_brandenburg | `wwii_brandenburg/scripts/mapinit.lua:237` (+ `228-270`, `182-202`) | `MapInit.ReposPeople` (lock `UsrEntity(0)`, teleport + AI-walk all six), then `OnChurchArrived` → chat → `EndOfTalk` → `GoToBreech` → `EndOfMap` | scene-end `OnEnd_NaziSacrificeB` (runs on every machine) | **A/B** | the ending chain advances only when **Church** arrives by AI walk (`mapinit.lua:261`, `184`). Church held by a client (likely: S8 needs a human Church): the puppet never arrives, **stall**. Escape fallback: `EscapeEvent = MapInit.EndOfMap` on the host. On clients the scene end runs `ReposPeople` locally: their own body is locked, and the unlock comes only from `NewLevelNow` (fine). | M1b on `AIGen.GoAndAction` for remote bodies (owner walks, or teleport + callback after a timeout). Minimal: wrap `MapInit.ReposPeople` on the host so that if Church is remote-owned, it schedules `MapInit.OnChurchArrived()` after ~4 s. |

## Act 3: Crusades

| Level | File:line | Function | Trigger | Cls | Failure in co-op | Proposed fix |
|---|---|---|---|---|---|---|
| cru_river | `cru_river/scripts/mapinit.lua:34-50` | `MapInit.RawlingsVlad` | poll | C | hints | none |
| cru_labyrinth | `cru_labyrinth/scripts/mapcallbacks.lua:353-359` | `MapCallbacks.TriggerLastScene_0` (`UsrEntity(0).ActCtrl ~= "Black"` → return; else `Scene.PlayFP("CruzadersSpeech_B")`) | cb, area trigger **OnCameraView**, `bClearOnCameraView = true` | A (soft) | fires once from the host's camera. If the host is not Black the trigger is cleared and the scene is skipped. Fallback: `o1007_0` (`UseJustEntity = Black`, handled by `coop_claim`) plays the same scene. If a remote Black looks at the point, nothing fires. | Wrap `MapCallbacks.TriggerLastScene_0` with M1 (true when any human holds Black). The scene POV then goes to the Black owner (coop_scenes). Or leave it to `o1007` via claim. |
| cru_labyrinth | `cru_labyrinth/scripts/mapcallbacks.lua:379-383` | `MapCallbacks.bridgeBHitter4_1` (cancels damage when the **host's** `Pos.x < -12700`) | cb OnDamage | A (soft) | the bridge hitter ignores damage whenever the host stands across, even if a client shoots it from the right side; or the reverse | Wrap it to test the attacker's position (`Game.GetEntity(AttackerName).Pos`) instead of the host's (M1 with the attacker) |
| cru_sewers | `cru_sewers/scripts/mapinit.lua:33-62` | `MapInit.OnWardHit` (punishes `UsrEntity(0)` inside `TriggerBloodWar`; after 5 ticks calls `ThreadsChurch.OnWardCallback` itself) | cb `TriggerBloodWarHit_0` → scheduled | B | a remote Church in the ward is never punished; the host's body is punished if it is inside. The self-fallback after 5 ticks (~15-35 s) still activates `BloodWarGroup`, so no stall. The real ward callback (`threadschurch.lua:402`) fires on the Church owner's machine [inferred]. | M1: resolve to Church's entity, and send the damage through `pdmg` to its owner. Forward the "ward placed" event (M3) for timely progress. |
| cru_sewers | `cru_sewers/scripts/mapinit.lua:85-143` | `MapInit.SwtichBlack`, `MapInit.SwtichChurch` | `isDemo` only | D | demo build only | none |
| cru_chapel | `cru_chapel/scripts/mapinit.lua:165-175` | `MapInit.MemberOnOff` (skips `UsrEntity(0)`), used by `On<X>Arrived` and `StartMaltheus` | AI-arrive, scheduled | B | AI on/off on remote puppets is reset by `drivePuppets`. `MoveSquadAroundMaltheus` / `MoverFaster` (`mapinit.lua:62-97`) teleport and walk remote bodies with no effect: remote players are not placed around Maltheus. No stall. | Skip remote-owned names (`Coop.isRemoteOwned`). Optional M2 teleport via the owner. |
| cru_chapel | `cru_chapel/scripts/mapinit.lua:177-203` | `MapInit.ColeFirestorm` | `MapInit.main` → poll | C | hints | none |

## Act 4: Rome

| Level | File:line | Function | Trigger | Cls | Failure in co-op | Proposed fix |
|---|---|---|---|---|---|---|
| rom_outskirts | `rom_outskirts/scripts/mapinit.lua:64-73` | `MapInit.BeginPlayScene` (if `UsrEntity(0).Name == "Rawlings"` → `SchFade`; else `Team.EndSwitchCallback = SchFade`, `Team.SwitchSoldier(UsrEntity(0).Name, "Rawlings")`) | cb `Enemy_Group_Torturers_0` → scheduled +4 s (runs on every machine) | **A** | Rawlings held by a client: the host's `SwitchSoldier` returns `false`, `EndSwitchCallback` never fires, `CenturiansTale` never plays: **stall**. Each client also runs it 4 s after the replay (outside `W.replaying`, so the client's switch guard does not apply): a client may switch into an AI-held Rawlings at the same time as the host → ownership race [inferred]. | Wrap `MapInit.BeginPlayScene`: on clients no-op. On the host: if any human holds Rawlings → call `MapInit.SchFade()` directly (coop_scenes gives the POV to the Rawlings owner). Else route through the claim prompt ("Rawlings is needed"); after a timeout the host switches (vanilla). Generic M5. |
| rom_outskirts | `rom_outskirts/scripts/mapcallbacks.lua:214, 413` | `Enemy_Group_Torturers_0`, `fadein` (`UsrEntity(0).uData.LoopActive` → `Cole.SwitchPower`) | cb | C | resets Cole's time loop of the local body only. A remote Cole is reset by its own replay [inferred]. | none |
| rom_outskirts | `scripts/missions/areatriggers.lua:245-256` | `AreaTriggers.FadeAndMove` / `JumpPlayers` (waits for the host's `usr.Invulnerable == 0`, `Input` state) | cb `fadein` (line 411), `mapcallbacks.lua:279` | B | waits on and fades the host's state only. `JumpPlayers` moves bodies to the sector, which is undone for puppets [inferred]. It also runs per client via replay (each moves its own) [inferred]. | Probably fine because of the replay. Verify in game that remote bodies land in `Area_S_69`. |
| rom_caldarium | `scripts/missions/areatriggers.lua:119-134` (`usr.Name ~= "Delgado"` → `Input.SetActionSet("Inactive")`, `PlayerBurnOnFire` sets `UsrEntity(0).Life = 0`) | `AreaTriggers.EnterFireArea`, `AreaTriggers.PlayerBurnOnFire` | cb `AreaTrigger_Fire_0`, `AreaFire2_0` (replayed) | **B (severe)** | on the host, any non-Delgado body entering the fire (an AI or a remote puppet) disables the host's input and **kills the host's body**, even when the host is Delgado. Every client replays the callback with the same triggered name, so every client also kills its **own** body → possible team wipe / game over [inferred]. | Wrap `AreaTriggers.EnterFireArea`. Run it only for the triggered body: if it is local (host body or, on a client, `Coop.localChar()`), run the vanilla logic. If it is remote-owned, do nothing on the host (its owner runs it from the replay). If it is an AI, kill that AI body. `PlayerBurnOnFire` must kill the triggered entity, not `UsrEntity(0)`. |
| rom_caldarium | `scripts/missions/areatriggers.lua:152-168` | `AreaTriggers.EndSoloMision` / `StartSoloMision` (class of `UsrEntity(0)`) | cb `PalancaDelgado_0` (`mapcallbacks.lua:270`), `EnterFireArea` | B | resets or sets switch and orders on the host's class only; clients set it on their own class via replay | acceptable; in co-op prefer a no-op (switching is owner-ruled) |
| rom_chamber | `rom_chamber/scripts/mapcallbacks.lua:15-21` | `MapCallbacks.AreaTrigger43_0` (`AreaTriggers.IsPlayer(Playerid, Game.UsrEntity(0).Name)`) | cb area trigger | A (soft) | with `installIsPlayer` the name must still equal the **host's** body, so only the host's entry starts the intro walk (a client entering does nothing; on clients, during replay, the check compares with the client's own body). No stall: the host must eventually enter. | Wrap `MapCallbacks.AreaTrigger43_0`: accept any human (`CoopWorld.isHuman(triggered)`) |
| rom_chamber | `rom_chamber/scripts/mapinit.lua:17-50` | `MapInit.MovePlayer` / `MapInit.EndOfMove` (lock and walk `MapInit.player`; teleport everyone else; unlock; chat; `EnableVicus`) | cb above → AI-arrive of the player's own body | B | host: works. Clients: the replay locks and walks their own body, and their own arrival unlocks it (OK). The `Pos` writes on puppets are undone, so remote players are not lined up. | Acceptable. Optional M2 teleport via the owner. |
| rom_coloseum, rom_chamber, rom_palace_01 | `scripts/chars/gladiador.lua:442-454` | `Gladiador` OnDamage (critical spine damage counts only if `AttackerName == UsrEntity(0).Name`) | engine OnDamage | A (soft) | hits from clients arrive on the host with `AttackerName` = the client's body (`coop_enemies.applyHit`). They are not "player" hits, so only the host can deal critical damage. The body piece of remote hits is also not set on the host [inferred]. | Wrap the gladiator OnDamage: `isAttackerPlayer = CoopWorld.isHuman(AttackerName)` (M1 with the attacker) |
| rom_palace_02 | `rom_palace_02/scripts/mapinit.lua:7-13` | `MapInit.GoToFinalScene` (lock `UsrEntity(0)`, AI-walk Delgado into `AreaTrigger_sceneTheTrap`) | `Delgado.uData.PostCoolUseCallback` after use `puerta_final_delgado_1` (`mapcallbacks.lua:459`) | B | the host is locked until the level changes. A remote Delgado is not walked (puppet), but he can walk in himself. If he idles, the trap scene waits. The lock is never released if the trap trigger is never entered. The callback runs on the machine that performed the CoolUse [inferred]. | Wrap `MapInit.GoToFinalScene`: if Delgado is remote-owned, do not lock the host; send "goto" to the owner (M1b). Unlock all at the scene. |

## Act 5: Sumer

| Level | File:line | Function | Trigger | Cls | Failure in co-op | Proposed fix |
|---|---|---|---|---|---|---|
| sum_ziggurat_01 | `sum_ziggurat_01/scripts/mapinit.lua:92-118` | `MapInit.StartJonesPossession` (if `UsrEntity(0) == EJones` → `SwitchSoldier` to a random member; then `JonesGo`) | cb (`mapcallbacks.lua:271`) → scheduled, retries every 1 s | **A** | Jones held by a client: the host does not move that player out. `JonesGo` AI-walks the Jones puppet, which never arrives, so `OnJonesArrived` → `MoveSquadAroundJones` → `JonesPossession` → `EndOfPossession` (opens `puerta_antes_sala_estatuas`) never runs: **stall**. If the host is Jones, the random target may be remote-owned; the switch then fails and the loop retries (OK). | Wrap `MapInit.StartJonesPossession` on the host: if Jones is remote-owned → send that owner a forced switch to a free member (an "evict" message; the client runs `Team.SwitchSoldier(localChar, free)`), release Jones to the host AI, then call the original. On clients make it a no-op (the replayed scheduled copy). |
| sum_ziggurat_01 | `sum_ziggurat_01/scripts/mapinit.lua:243-263` | `MapInit.MoveSquadAroundJones` (lock + `MapInit.player = UsrEntity(0)`, AI-walk all five) | AI-arrive (`OnJonesArrived`) | B | host locked and walked. Remote puppets never arrive (their `On<X>Arrived` only toggles AI). Remote players stay free (no client copy: an AI-arrive chain) [inferred]. | M2 (lock all humans; owners walk their own bodies) |
| sum_ziggurat_01 | `sum_ziggurat_01/scripts/mapinit.lua:152-202` | `MapInit.OnBlack/Church/Cole/Delgado/RawlingsArrived` (`MapInit.player == E<X>` → `JonesPossession`) | AI-arrive | B | progress comes from the **host's own** body arriving. OK while the host's body is alive and active. | Add a timeout fallback: call `MapInit.JonesPossession` after N s if not called |
| sum_ziggurat_01 | `sum_ziggurat_01/scripts/mapinit.lua:76-84` | `MapInit.JonesPossession` (unlock `UsrEntity(0)`) | AI-arrive | B | paired unlock (host only) | M2 unlock all |
| sum_ziggurat_01 | `sum_ziggurat_01/scripts/mapinit.lua:140-150, 204-214` | `MapInit.MemberOnOff` (skips `MapInit.player`), `MapInit.RestoreSquad` | scheduled | D | AI flags on puppets are reset by `drivePuppets` | none |
| sum_ziggurat_01 | `sum_ziggurat_01/scripts/mapinit.lua:216-238` | `MapInit.EndOfPossession` (unlock `UsrEntity(0)`) | chat-end, `EscapeEvent` | B | paired unlock | M2 |
| sum_ziggurat_02 | `sum_ziggurat_02/scripts/mapinit.lua:10-16` | `MapInit.Init` (`Team.SwitchSoldier("Jones", "Black")`, Jones `bActive = false`) | `MapInit.main` → scheduled (every machine) | B | runs on the host **and every client**. Only one body (Black) is playable: whoever switches first owns it; the others stay in an inactive Jones. On a client the vanilla `SwitchSoldier` (not replaying) can grab Black while the host also does → ownership race [inferred]. | Wrap `MapInit.Init`: on clients, skip the switch (spirit until Jones is freed). On the host, switch the lobby's "Black" player (or the host) via `Coop.assign`. |
| sum_ziggurat_02 | `sum_ziggurat_02/scripts/mapcallbacks.lua:362-366` | `MapCallbacks.trigBlackAgain_0` | cb | D | AI flag on a puppet Black is reset | none |
| sum_ziggurat_02 | `sum_ziggurat_02/scripts/mapcallbacks.lua:377-386` | `MapCallbacks.trigDisableBlack_0` (keeps Jones' AI off while the host is Black, until the cell opens) | cb → poll | B | when Black is remote, the host does not keep the caged Jones' AI off. Jones may move inside the cell (cosmetic) [inferred]. | M1 (resolve to Black's holder) |
| sum_ziggurat_03 | `sum_ziggurat_03/scripts/mapcallbacks.lua:70-75` | `MapCallbacks.AreaTrigger79_0` (`Weapons.QuakeFX(UsrEntity(0).Pos, ...)`) | cb | C | quake at each machine's own body (replay) | none |
| sum_ziggurat_03 | `scripts/chars/summerianninlil.lua:249-254` | `SummerianNINLIL.Use` (`UsrEntity(0).Name == "Jones"` → `Uncover("Ninlil")`, sets `Invulnerable = 0`) | engine (Use on the boss, from Jones' astral form) [inferred] | **A** | Jones held by a client: the astral use happens on the client, which uncovers Ninlil only locally. On the host Ninlil stays invulnerable (the host is not Jones and never receives the use): boss unkillable, **stall** [inferred]. | Forward the event to the host (M3: "use Ninlil by Jones"). On the host wrap `SummerianNINLIL.Use` so the check is `nameUsr == "Jones"` or Jones is human (M1). Replicate `Uncover` to clients from the host. |
| sum_ziggurat_03 | `scripts/chars/summerianninlil.lua:417-426` | `SummerianNINLIL.BloodHit` (squeeze damage only to `UsrEntity(0)` within 60 units) | engine act event | C (gameplay) | clients are never hurt by the squeeze; the host is | iterate over human bodies; damage remote ones through `Weapons.DoDamage` (routed to the owner as `pdmg`) |
| sum_ziggurat_03 | `sum_ziggurat_03/scripts/mapinit.lua:53-127` | `MapInit.StartCamHint(2)` / `CanDoCamHint` (`AstralCamera.Start("Jones")` on camera 0, `SetTimeSpeed(0.1)`) | scheduled hint | C | takes over the host's camera even when the host is not Jones. Time slows for everyone (the time speed is shared). | Run it only on the machine that holds Jones (or skip it in co-op) |
| sum_ziggurat_04 | `sum_ziggurat_04/scripts/mapinit.lua:88-117` | `MapInit.ReposSquad` (`MapInit.EPlayer = UsrEntity(0)`, lock; `OnPlayerArrived` attached only to the Black/Delgado/Jones walk that matches `EPlayer`) | cb `AppearChurchCole` (`mapcallbacks.lua:328`, replayed) | **A/B** | progress (`OnPlayerArrived` → door, `KillEnemy` → `LetsGo`) needs the **host's** body to be Black, Delgado or Jones. Host = Rawlings: no walk is issued at all; the host is locked forever and the level **stalls** (a vanilla bug that co-op makes likely). Host = Cole/Church (hidden in sum_04): **stall**. On clients the replay locks their own body; the unlock (`RestoreUsrControl`) comes from Church's AI arrival, which never happens on a client, so they stay **locked forever** [inferred]. | Wrap `MapInit.ReposSquad` on the host: pick as "player" the first of Black/Delgado/Jones that is **not remote-owned** (host body or AI). Lock all humans (M2). Add a timeout that calls `MapInit.OnPlayerArrived`. On clients: no lock; or unlock when the host broadcasts `RestoreUsrControl`. |
| sum_ziggurat_04 | `sum_ziggurat_04/scripts/mapinit.lua:30-44, 119-123` | `MapInit.RestoreUsrControl`, `MapInit.OnChurchArrived`, `MapInit.ForcePlayerToWatchScene` | AI-arrive (Church walk, `mapinit.lua:76`), scheduled | B | unlocks the host only. Church is hidden before `LetsGo`, so no human holds him [inferred], and the Church walk arrives on the host. | M2: broadcast the unlock to all humans |
| sum_ziggurat_04, sum_ziggurat_meat | `scripts/chars/summeriannanna.lua:185`, `scripts/chars/summerianutu.lua:185` | `SummerianNANNA.OnDamage`, `SummerianUTU.OnDamage` (`GetEntity(AttackerName) ~= UsrEntity(0)` → return after restoring `Life`) | engine OnDamage | **A** | hits from clients (applied on the host with the client's body as attacker) are ignored: **only the host can damage Nanna and Utu**. If the host is down or a spirit, the bosses cannot be killed [inferred]. | Wrap both `OnDamage` functions: during the call `UsrEntity(0)` resolves to `GetEntity(AttackerName)` when `CoopWorld.isHuman(AttackerName)` (M1 with the attacker) |
| sum_ziggurat_04 | `scripts/chars/puppetgod.lua:435-450` | `PuppetGod` OnDamage (back-hit critical damage only for `UsrEntity(0)`) | engine OnDamage | A (soft) | only the host can land the critical back hit | same wrapper as above |
| sum_ziggurat_meat | `sum_ziggurat_meat/scripts/mapinit.lua:30-42, 68-98` | `MapInit.ReposPeople` (lock `MapInit.player = UsrEntity(0)`; teleport and walk all six), `MapInit.NilFunc` (unlock after 5 arrivals) | scheduled from `StartEndScene` (from `MapInit.main` poll) | B | puppets never arrive, so the counter may not reach 5 and the host stays locked. `ElevateUrn` → `SaveGame.NewLevel` at +32 s is independent, so no stall. Runs on every machine (`MapInit` poll) [inferred]. | M2; or a timeout unlock |
| sum_end | `sum_end/scripts/mapinit.lua:37-45` | `MapInit.CheckAmmoLow` (`chr.UsrControl == -1` → refill) | poll | D | also refills remote puppets on the host (their ammo is client-side) | none |
| sum_end | `scripts/chars/evilfirstborn.lua:473-513` | `EvilFirstBorn.DrawBloodRune` (from the boss' `Spell2` → `DoBloodRune`): if `UsrEntity(0) ~= EChurch` → lock `UsrEntity(0)` and schedule `Team.SwitchSoldier(name, "Church")`; `SchMakeAllUnavailable` stuns Black/Delgado/Rawlings | engine act event | **A/B** | Church held by a client: the host's switch fails, so the host stays locked for good (`IgnoreUsrControl = 1`, never reset here). The "Stupid" stun is forced on the three others, puppets included: the host forces the animation and turns their AI off, while their owners keep moving them [inferred]. | Wrap `EvilFirstBorn.DrawBloodRune`: if a human holds Church → skip the host lock and switch; apply the stun lock to the other humans through M2. If nobody holds Church → claim prompt "Church is needed", host-switch fallback (vanilla). |
| sum_end | `scripts/chars/evilfirstborn.lua:293-312` | `EvilFirstBorn.IncapacitateSch` (ends when `UsrEntity(0) == tgt` with FP; if `tgt == "Church"` and `RuneBloodActive == 1` → `KillFirstBornScene` → `MapInit.EndOfGame`) | poll every 0.1 s (from `FXPossesion`) | **A (final boss)** | the kill condition is "the host is Church, in first person, and `RuneBloodActive` is set on the host". With Church held by a client: `UsrEntity(0)` is never Church, and `RuneBloodActive` is set by Church's blood rune on the **client** (`threadschurch.lua:371`). The ending never triggers: **campaign cannot finish** [inferred]. | Wrap `EvilFirstBorn.IncapacitateSch` with M1 (resolve to the Church holder; treat the remote body as FP-active). Forward `RuneBloodActive` from the Church owner to the host (M3: send `rune|1/0`, the host calls `Game.Set`). |
| sum_end | `scripts/chars/evilfirstborn.lua:405-432, 257-269` | `EvilFirstBorn.FXPossesion` → `EvilFirstBorn.DoSwitch` / `RestoreFirstPerson` | engine act event | B | possession of the **host's** body forces the host into a random member; it can be remote-owned (the switch fails, then the host is unlocked after 1 s). Possession of a remote body: no switch; the host forces "Stupid" on the puppet while the client keeps control [inferred]. | Wrap `EvilFirstBorn.DoSwitch`: pick only free members. For a remote target, send the owner "possessed" (client-side lock or stun, and its own switch to a free member). |
| sum_end | `scripts/chars/evilfirstborn.lua:314-356` | `EvilFirstBorn.StartBlackEmulation` (locks the target) / `EndBlackEmulation` (unlocks `UsrEntity(0)`, then `DoDamage(tgt, tgt.Life)`) | engine AI | B | the target can be a remote puppet: lock and unlock act on different bodies, and the lethal damage is routed to the owner via `pdmg` (OK). The client sees no TK grab [inferred]. | Mirror the grab to the owner (lock, then release) |
| sum_end | `scripts/chars/evilfirstborn.lua:212, 228` | `OnThrowRay` FX skip, `DamageMember` (hit reaction only for the host) | engine | C | cosmetic | none |

## Shared scripts (all levels)

| File:line | Function | Cls | Note / co-op handling |
|---|---|---|---|
| `scripts/missions/areatriggers.lua:86-92` | `AreaTriggers.IsPlayer` (`UsrControl == 0`) | D (handled) | replaced by `CoopWorld.installIsPlayer`. Callers that pass `UsrEntity(0).Name` as the name still restrict it to the host (rom_chamber above). |
| `scripts/missions/scene.lua:624, 698, 462, 472` | `Scene.HideChars`, `Scene.Play` (`Scene.usr = UsrEntity(0)`), end callbacks `func(Scene.usr)` | C (handled) | scene POV and `EndOfFpScene` handled by `coop_scenes.lua` / `coop_enemies.lua`. Level end callbacks that use `usr` (`alk_bunker_00/mapscenes.lua:26-31`, `cru_chapel/mapscenes.lua:61`, `rom_outskirts/mapscenes.lua:105-140`, `wwii_mosque_inside/mapscenes.lua:25`, `wwii_pillboxes/mapscenes.lua:120-125`) only pass it to `EndOfFpScene` or `SetOnFloor`. |
| `scripts/missions/scene.lua:677` | `Scene.Play` → `AstralCamera.EndReturn(UsrEntity(0).Name)` | C | per machine |
| `scripts/missions/scene.lua:807-918` | `Scene.SetUsrPosAng`, `PlayFPNI`, `PlayFPNNI`, `PlayFP`, `LauchFromFP`, `EndOfFpScene` | C (handled) | FP scenes start from the host's body; the mod already wraps `EndOfFpScene` |
| `scripts/missions/scene.lua:424` | Delgado sprint lock if `UsrControl ~= -1` | D | |
| `scripts/missions/scene.lua:961` | `Scene.PrintDebugNyapa` | D | debug output |
| `scripts/missions/qte.lua:278-280` | `QTE.canNotQTEAttack` (`usr.UsrControl ~= 0`) | C (known) | in-combat grab QTEs only on the host's body (`coop-ux-research.md` 5.6) |
| `scripts/missions/savegame.lua:317-325` | `SaveWeaponsConfigAfterSwitchLevel` | D | per machine |
| `scripts/missions/areatriggers.lua:152-168` | `StartSoloMision` / `EndSoloMision` | B | see wwii_pillboxes and rom_caldarium |
| `scripts/missions/areatriggers.lua:119-134` | `EnterFireArea` / `PlayerBurnOnFire` | B (severe) | see rom_caldarium |
| `scripts/missions/areatriggers.lua:245-256` | `FadeAndMove` | B | see rom_outskirts |
| `scripts/chars/cultistamelee.lua:505-511` | `CultistaMelee.GrabFromAnim` (grabs only the host) | C (known) | grab QTE, as `qte.lua` |
| `scripts/chars/cultistamelee.lua:595-599` | torturer chase target fallback = host | C | AI targeting bias toward the host |
| `scripts/chars/jones.lua:801-805`, `scripts/chars/rawlings.lua:768-774` | `Jones.OnDeath`, `Rawlings.OnDeath` (astral clean-up when the host is that character) | C | the owner's machine runs it for its own body [inferred] |
| `scripts/chars/soldier.lua:17-27` | `Soldier.DoHitStrong` (host only) | C | hit reaction for remote bodies is the owner's |
| `scripts/chars/teamtalk.lua:120-127, 194, 216, 246, 465, 739` | `IsValidPlayer`, `isFiltered`, `ForceRadioTalk`, `TryRadioChatCall` (line variant by `usr.ActCtrl`) | C | dialogue line choice and filtering follow the host's body |
| `scripts/chars/team.lua:198, 242, 253, 287, 608, 1214, 1355, 1458, 1484` | core switching and death | out of scope | already covered by `coop.lua` / `coop_team.lua` (`CheckGameOver`, `IsPlayerAvaliable`) |
| `scripts/ai/aigen.lua:23-29` and 15 callers in `aisquad*.lua`, `aimembersquad.lua`, `aiteam.lua` | `AIGen.GetPlyName` | D | AI squad logic excludes the host's body; puppets are excluded by `oAI.bEnable = false` [inferred] |
| `scripts/chars/black.lua`, `scripts/weapons/*.lua`, `scripts/thread/*.lua`, `scripts/fp/*.lua`, `scripts/fx/*.lua` | power and weapon code | out of scope | runs on the machine that owns the body |

## Counts

Rows above that use `UsrEntity(0)` or its wrappers (the related AI-walk gate table is counted
separately):

| Class | Count | Of which critical (stall, or wrong body killed) |
|---|---|---|
| A (incl. 3 A/B and the "A soft" rows) | 17 | 10: biggates `TestWard`, pillboxes `ActivateBigFuckerGroup`, mosque_inside `BritishBombOnDamage`, brandenburg `ReposPeople` (Church walk), rom_outskirts `BeginPlayScene`, sum_01 `StartJonesPossession`, sum_03 `SummerianNINLIL.Use`, sum_04 `ReposSquad`, Nanna/Utu `OnDamage`, sum_end `IncapacitateSch` + `DrawBloodRune` |
| B | 29 (26 level rows + 3 shared) | 1 severe (rom_caldarium `EnterFireArea`, which kills the wrong bodies) |
| C | 27 (18 + 9) | 0 |
| D | 12 (7 + 5) | 0 |
| Related AI-walk gates (no `UsrEntity`) | 5 rows / 6 call sites | all are stalls when the walked member is a remote human (Act 1 Black doors in alk_desert, alk_city and alk_tomb ×2; bunker_01 Rawlings and Cole) |

---

## A and B items in campaign order

1. alk_desert / alk_city / alk_tomb: Black's scripted TK-door walks (`MapInit.OpenTheTkDoor*`).
   **A**, stall when Black is remote. Fix: M1b.
2. alk_tomb `MapInit.StartSayGoodbye` / `MiraDetrasDeTi` / `LiberateMe`. B (bodiless clients
   stay locked). Fix: M2/M4.
3. alk_bunker_01 `MapInit.GoToRawlings` (B, client lock); Rawlings walk `OnRawlingsArrived` and
   Cole walk `StartManipulation` (**A**). Fix: M1b, M4.
4. wwii_biggates `MapInit.TestTap` (A soft) and **`MapInit.TestWard` (A, stall)**. Fix: M1 + M3
   (ward event).
5. wwii_pillboxes:
   - `AfterRawlingKilled` / `StartSoloMision` (B).
   - `StartIncidental` … `ActivateNaziBitch` (B).
   - **`ActivateBigFuckerGroup` (A, stall)**.
   - `StartLichtScene` / `EnsureLookingBitch` (B).
   - Fix: M1, M2, claim prompt for Rawlings.
6. wwii_mosque_inside **`PhysicsObj.BritishBombOnDamage` (A, stall + desync)**. Fix: forward
   story-object damage, M1 with the attacker.
7. wwii_vigil_inside `PsichicCommander.EndOfBitch` (B). Fix: M2.
8. wwii_brandenburg **`MapInit.ReposPeople` → Church walk `OnChurchArrived` (A/B, stall)**.
   Fix: M1b.
9. cru_labyrinth `TriggerLastScene_0` (A soft) and `bridgeBHitter4_1` (A soft). Fix: M1.
10. cru_sewers `MapInit.OnWardHit` (B). Fix: M1 + M3.
11. cru_chapel `MapInit.MemberOnOff` / `MoveSquadAroundMaltheus` (B). Fix: skip remote bodies.
12. rom_outskirts **`MapInit.BeginPlayScene` (A, stall)**; `AreaTriggers.FadeAndMove` (B).
    Fix: M5.
13. rom_caldarium **`AreaTriggers.EnterFireArea` / `PlayerBurnOnFire` (B, kills the wrong
    bodies)**; `EndSoloMision` (B). Fix: per-body wrapper.
14. rom_coloseum / rom_chamber / rom_palace_01: `Gladiador` OnDamage (A soft). Fix: M1 with the
    attacker.
15. rom_chamber `AreaTrigger43_0` (A soft), `MovePlayer` / `EndOfMove` (B).
16. rom_palace_02 `MapInit.GoToFinalScene` (B). Fix: M1b / M2.
17. sum_ziggurat_01 **`StartJonesPossession` (A, stall)**; `MoveSquadAroundJones`,
    `On<X>Arrived`, `JonesPossession`, `EndOfPossession` (B). Fix: evict the Jones owner, M2.
18. sum_ziggurat_02 `MapInit.Init` forced `SwitchSoldier("Jones","Black")` on every machine (B);
    `trigDisableBlack_0` (B). Fix: M5, M1.
19. sum_ziggurat_03 **`SummerianNINLIL.Use` (A, boss stays invulnerable)**. Fix: M3 + M1.
20. sum_ziggurat_04:
    - **`MapInit.ReposSquad` (A/B, stall for host = Rawlings/Cole/Church; clients locked)**.
    - `RestoreUsrControl` / `OnChurchArrived` (B).
    - **`SummerianNANNA/UTU.OnDamage` (A, only the host can hurt them)**.
    - `PuppetGod` OnDamage (A soft).
21. sum_ziggurat_meat `MapInit.ReposPeople` / `NilFunc` (B); Nanna/Utu as above.
22. sum_end:
    - **`EvilFirstBorn.DrawBloodRune` (A/B, host locked when Church is remote)**.
    - **`EvilFirstBorn.IncapacitateSch` (A, the final kill never triggers)**.
    - `FXPossesion` / `DoSwitch`, `Start/EndBlackEmulation` (B).
    - Fix: M1 + M3 (`RuneBloodActive`), M5.

## Suggested generic mechanisms

All of them can be installed by name, the same way `CoopWorld.installHost` wraps
`MapCallbacks`. A table `{ "MapInit.TestWard" = {as = "Church"}, ... }` per level is enough.

- **M1. "Resolve the player" wrapper (gates):**
  `CoopStory.as(tblPath, fname, resolver)` replaces `T[f]` with a function that, during the
  call, replaces `Game.UsrEntity` with `function(id) if id == 0 then return target end
  return orig(id) end`, where `target = resolver(...)`.
  - Resolvers:
    - `byChar("Church")`: the entity if any human holds Church (`CoopWorld.isHuman`), else the
      host's own body (vanilla).
    - `byAttacker(argIndex)`: `GetEntity(AttackerName)` if human.
    - `byTriggered(argIndex)`: `GetTriggeredEntity(Playerid)` if human.
  - The wrapper must also accept `usr.owc.*` reads on a puppet. Puppets have no local input, so
    for tutorial polls a resolver that returns "condition met" is simpler.
  - Install it on the host only. On clients the same functions should be no-ops when they are
    story gates (`ActivateBigFuckerGroup`, `BeginPlayScene`, `StartJonesPossession`).
  - Targets: `MapInit.TestTap`, `MapInit.TestWard` (biggates);
    `MapInit.ActivateBigFuckerGroup` (pillboxes); `PhysicsObj.BritishBombOnDamage`;
    `MapCallbacks.TriggerLastScene_0`, `MapCallbacks.bridgeBHitter4_1`; `MapInit.OnWardHit`;
    `MapCallbacks.AreaTrigger43_0`; `Gladiador` / `PuppetGod` / `SummerianNANNA` /
    `SummerianUTU` OnDamage; `SummerianNINLIL.Use`; `MapCallbacks.trigDisableBlack_0`;
    `EvilFirstBorn.IncapacitateSch`.
- **M1b. `AIGen.GoAndAction` on a remote-owned body:**
  - Wrap `AIGen.GoAndAction(nameEnt, pos, posEnd, funcExec, vel)` on the host. If
    `Coop.isRemoteOwned(nameEnt)`, keep `funcExec` on the host and send
    `goto|name|pos|posEnd|vel` to the owner.
  - The owner locks its body, runs the vanilla `GoAndAction` locally and reports
    `arrived|name`.
  - The host then calls `funcExec(entity)`. Fallback after N s: teleport through the owner, then
    call `funcExec`.
  - This one wrapper fixes every "walk a squad member to X, then continue" stall: Act 1 Black
    doors, bunker_01, brandenburg Church, sum_01 Jones, rom_palace_02 Delgado.
- **M2. Cinematic lock for all humans:**
  - Wrap writes of `IgnoreUsrControl` done by story code on `UsrEntity(0)`. The easiest hook is
    in the functions listed under B: after the original runs, broadcast `lock|1` or `lock|0`.
  - Clients set `IgnoreUsrControl` on their own body. They may run a local `GoAndAction` to the
    same target, or just freeze.
  - Pair the lock with a watchdog on clients: a client lock without a host lock is cleared after
    a few seconds. This is **M4**, and it fixes replayed locks whose unlock comes from another
    body's AI arrival (alk_bunker_01, sum_ziggurat_04, bodiless alk_tomb players).
- **M3. Forward character-power story events from the owner to the host:**
  - Church ward (`Church.callOnWard`, `ThreadsChurch.OnWardCallback`).
  - Blood rune (`Game.Set("RuneBloodActive")`).
  - Jones astral use on Ninlil (`SummerianNINLIL.Use`).
  - Black's ghost bullet on story objects (damage on `oBritishBomb`).
  - Pattern: as `W.onLocalCallback` → `use|...`. The client sends `ev|<name>|args`; the host
    calls the function (`Coop.fromHost`-style guard).
- **M5. Forced story switch:**
  - Wrap the story callers (`MapInit.BeginPlayScene`, `EvilFirstBorn.DrawBloodRune`,
    `EvilFirstBorn.DoSwitch`, `MapInit.StartJonesPossession`, sum_02 `MapInit.Init`).
  - If the required character is already human-held: skip the switch and fire the continuation
    (`Team.EndSwitchCallback`, or the next step) immediately.
  - If it is free: open a `coop_claim`-style request ("Rawlings is needed": Y to take it); after
    the timeout the host switches (vanilla).
  - If the story needs a character to be **vacated** (sum_01 Jones): send the owner an
    `evict|<char>` message that switches them to a free member.
  - On clients these callers must be no-ops (they run from replay or `MapInit.main`).
- **Per-body fire area (rom_caldarium):** replace `AreaTriggers.EnterFireArea` /
  `PlayerBurnOnFire` with versions keyed on the triggered body. Act only when that body is local
  to this machine; otherwise ignore. AI bodies are handled by the host.

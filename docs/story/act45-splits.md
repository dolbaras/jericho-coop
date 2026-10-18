# Acts 4-5 (Rome, Sumer): co-op splits G9-G15 and the "own body" lines

Status: design proposal, 2026-10-18. Scope: rom_outskirts, rom_caldarium, rom_tepidarium,
rom_palace_01, rom_palace_02, rom_coloseum, rom_chamber, sum_ziggurat_01..04,
sum_ziggurat_meat, sum_ziggurat_05, sum_end. Builds on `mod/docs/coop-story-extensions.md`
(G9-G15), `campaign-structure.md` (sections 3 and 5) and `scenes-catalog.md`.

Owner's rule for every split: a player whose character leaves the group chooses (a) switch to
a character who goes on, or (b) stay in their own body and play that character's own line,
ending in the reunion the story already has. Players with no body at all play a spirit.

Conventions: `[O]` read in the scripts, `[I]` inferred from them, `[guess]` design guess or
unverified engine behaviour. Paths are relative to `work/src/`. Coordinates are world units
copied from the level data. Voice lines are catalog keys only (`work/voices/catalog.tsv`).
`TeamTalk.ForceRadioTalk` builds the key as `<Prefix>_<Char>_<Text>[N]`
(`scripts/chars/teamtalk.lua:227-238`), so `RadioTalk("Black", "161_L4_Lift_Door", "HINT")`
plays `hint_black_161_l4_lift_door`, and `RadioTalk("Delgado", "Rejoin_Team", "Talk", 3)` plays
`talk_delgado_rejoin_team3`. Multi-line chats go through `TeamTalk.InitIncidentalChat("Mission_...")`
(`teamtalk.lua:540-556`). New text is subtitle only (`Scorer.SetSpeechText`, as
`TeamTalk.GenericTalk` does, `teamtalk.lua:279-300`).

---

## 0. Summary

| # | Split | Who leaves | "Own body" line (short) | Reunion (vanilla) | Effort | Feasibility |
|---|---|---|---|---|---|---|
| G9 | rom_outskirts CenturiansTale | nobody (shared cutscene) | not a split; Rawlings' holder gets the FP view | — | Low | High |
| G10 | rom_caldarium fire | Delgado | Delgado: vanilla solo route. Others: **"The Torturers' Hall"**, hold the pinned hall against emerging cultists, Church's ward over Delgado [guess], cheer him to the lever | lever `o1119` opens `PuertaDelgado1/2` | Med | High |
| G11 | rom_palace_01 abyss | Church | Church: vanilla crossing, then a **new fight on the far side**. Others: **"Cover the Ledge"**, shoot across the abyss, Jones re-cranks the legion door, two players hold plates B/C | `PressChurch_0` opens the bridge | Med | High |
| G12 | sum_ziggurat_01 possession | Jones (possessed) | Jones: **"The Displaced Soul"**, astral orbit around his own body, push the priest out | `EndOfPossession` | Low-Med | Med |
| G13 | sum_ziggurat_02 / 03 | everyone but Black | Jones: **"The Voice in the Cage"** (caged from the start, astral guide). Delgado + Rawlings: **"The Far Corridor"** in sum_02 and **"Behind the Wall"** in sum_03. Church (+Cole): switch to Jones/Black or spirit; optional rear guard | `ShowRawlings` wall break (sum_03) | High | Med |
| G14 | sum_ziggurat_04 | Cole, Church | **"The Time Loop"**: orphan Cole radio chat, they drop into the hall when the boss door closes and hold it; Cole's player kills the last flyer | `LetsGo` | Med | Med-High |
| G15 | sum_end final phase | Black, Delgado, Rawlings (stunned) | **"Break the Blood Link"**: struggle free, then fight the Firstborn's stolen powers (`EvilAbabanili`, `EGH*` ghosts); the kill stays Church's | `KillFirstBornScene` → TheEndC | Med | Med |

Two facts change the existing proposals:
- G15: there are no Arnold Leach adds in the sum_end fight. `init.Enemies` is only
  `EvilFirstBorn` and `Arnold` (`levels/sum_end/scripts/map.lua`), the only enemy group is
  `EvilFB` (`mapenemiesgroup.lua`), and Arnold appears only as a scene actor (TheEndB/C). The
  "adds" are the Firstborn's own copies of squad powers created in `EvilFirstBorn.OnCreate`
  (`scripts/chars/evilfirstborn.lua:112-178`).
- G11: in vanilla the `LegionariosPuente*` assault happens **before** the crossing, and the
  pressure plates come **after** it with no enemies (details in 3.1). `coop-story-extensions.md`
  and `scenes-catalog.md` #34 describe them as one phase.

---

## 1. Shared building blocks

These are reused by several splits. All are Tier 1 (same level, Lua only).

| Id | Need | How (vanilla pattern) | Evidence |
|---|---|---|---|
| B1 | Keep a human-held body active where vanilla freezes or hides it | Skip the member in the vanilla line when `Coop.HeldBy[name]` is set; AI-held members keep the vanilla behaviour | `Active = 0`: `rom_caldarium/scripts/mapcallbacks.lua:189-197`, `mapinit.lua:66-73`; `bActive = false`: `sum_ziggurat_03/scripts/mapinit.lua:10-15`, `sum_ziggurat_04/scripts/mapinit.lua:5-10` |
| B2 | Spawn a fresh wave anywhere on the nav mesh, without doors | `NPC.CreateWithAI(class, x, y, z, listName, 1)`, then `e.bActive = true`, `e.ForceAction = "Emerge"`, as `SummerianNINLIL.OnCreateNewEntity` does | `scripts/chars/summerianninlil.lua:279-287`; `scripts/chars/npc.lua:29-52` |
| B3 | Do not consume a vanilla group early | `NPC.ActivateEnemyGroup` runs **once per group per save** (save var `<level>.EnemyGroup.<G>.Status`). Reusing a vanilla group early removes it from its vanilla moment, so new waves use B2 | `scripts/chars/npc.lua:248-276` |
| B4 | Class must be loaded | Only classes in the level's `init.Enemies` can be spawned [I] | e.g. caldarium: CultistaExplosivo, CultistaMelee; palace_01: Legionary, Gladiador; sum_02/03: CultistaMelee; sum_04: CultistaVolador, CultistaMelee, …; sum_end: EvilFirstBorn, Arnold only |
| B5 | Per-player checks instead of `UsrEntity(0)` | Rewrite the checks listed per split (fire burn, Ninlil use, possession, Firstborn incapacitate, forced switches) to "the human holding X" | see each split |
| B6 | Separated members must not fire story triggers | Any registered member fires `OnEnter` (`mod/docs/enemies-and-triggers.md` 4.1). Guard the listed triggers by name | per split |
| B7 | Hide or reveal a body with the Sumer vortex look | `SumTeleport.FXRagdollTeleport(name)` + `NPC.DisolveEntity` + `bActive = false`; reveal with `SumTeleport.FXRagdollTeleportArrive(name)` (`NPC.AppearEntity`) | `scripts/fx/sumteleport.lua:42-75`, `141-157` |
| B8 | Jones's own astral view | `AstralCamera.Start("Jones", true, OnlyOrbit)`; TK, burn, rune and project are gated by `cam:CanTK/CanBurn/CanRune/CanProject` | `scripts/chars/astralcamera.lua:125-196` |
| B9 | Radio and subtitles | `TeamTalk.RadioTalk(char, text, prefix)`; it refuses dead speakers or those with `uData.CannotSpeak` | `teamtalk.lua:186-203` |
| B10 | Cutscenes freeze everyone | `Scene.HideChars` freezes every WalkChar, humans included | `scripts/missions/scene.lua:622-638` |

Common engine limit: there is one `AstralCam` entity and the scene and astral cameras are set
on viewport 0 (`Game.SetCam(0, ...)`, `astralcamera.lua:129`). Every line below that gives a
non-host player Jones's astral view needs the same per-viewport camera work as the spirit role.

Unused voice lines in Acts 4-5 (no script references them, grep over `work/src`). They were
written for situations that the shipped scripts removed, and several fit the new lines exactly:

| Group | Keys |
|---|---|
| Caldarium, fire | `hint_black_150_l4_hot_coals`, `hint_delgado_153_l4_hot_coals` |
| Caldarium, "lift the door" | `hint_black_161_l4_lift_door`, `hint_church_162_l4_lift_door0/1`, `hint_jones_163_l4_lift_door`, `hint_rawlings_164_l4_lift_door`, `hint_ross_165_l4_lift_door` |
| Caldarium, lever | `hint_jones_147_l4_caldarium_lever` |
| Stuck door (Delgado → Jones) | `hint_delgado_166_l4_stuck_door`, `hint_delgado_167_l4_stuck_door` |
| Palace legion door | `hint_black_173_l4_block_legion`, `hint_delgado_174_l4_block_legion` |
| Tepidarium | `hint_ross_169_l4_firstborn` |
| Blood-fed demon (sum_04 boss) | `hint_church_203_l5_ki0-2`, `hint_church_207_l5_ki_attack0/1`, `hint_church_208_l5_puppet_master0/1`, `hint_cole_200_l5_ki`, `hint_cole_204_l5_ki_attack`, `hint_rawlings_210_l5_puppet_master` |
| Urn walk | `hint_church_l5_follow_urn`, `hint_cole_l5_follow_urn0/1`, `hint_jones_novoice_l5_follow_urn` (text only, no audio) |
| Meat level | `hint_black_216_l5_kill_utu`, `hint_church_217_l5_kill_utu0-2`, `hint_delgado_219_l5_kill_utu0/1`, `hint_ross_220_l5_kill_utu` |
| Orphan chats | `mission_sum_ziggurat_02_findjones0/1` (Jones, Black), `mission_sum_ziggurat_04_begin0-9` (Cole on the radio: a "quantum paradox", a spatial rift, "activating the time loop", a 3-2-1 countdown) |

Generic categories used below (all six speak them unless noted): `talk_<char>_rejoin_team*`
(**Cole has none**), `help_alpha*`, `help_omega*`, `help_<name>*`, `casualty_<name>*`,
`enemy_ambush*`, `under_heavy_fire*`, `spot_team*`, `spot_exit*` (Black, Cole, Rawlings only),
`hot_area*` (not Church, not Jones), `use_power_<name>*`, `gencom_roman*`, `gencom_sumerian*`
(no Church), `terrified*`, `unexpected*`, `revived*`, `thread_unavailable*`.

---

## 2. G9 rom_outskirts: CenturiansTale

### 2.1 Vanilla facts [O]

- `Enemy_Group_Torturers` (Mr_Torture_1/2, Enemy3056) is activated by `AreaTriggerTorture`
  (`levels/rom_outskirts/scripts/mapcallbacks.lua:102-105`); the torture animations are set up in
  `mapinit.lua:31-62`.
- When the group dies, `Enemy_Group_Torturers_0` revives everyone, sets `ERawlings.Invulnerable = 1`,
  opens `puerta_tras_centurion_1/2` and schedules `MapInit.BeginPlayScene` after 4 s
  (`mapcallbacks.lua:208-218`).
- `BeginPlayScene` force-switches the player to Rawlings unless they already are Rawlings
  (`mapinit.lua:64-73`). `SchFade` marks all six unavailable, fades out and plays
  `Scene.PlayFP("CenturiansTale")` after 3 s (`mapinit.lua:75-93`).
- The scene has actors for **all six** plus the Centurion, filmed from `FP_Rawlings`, and can be
  skipped (`mapscenes.lua:14-25`, `148-189`). `OnEnd_CenturiansTale` places the five others,
  clears the unavailability table and calls `EndOfFpScene` (`mapscenes.lua:105-141`).
- Voice: the scene audio is `scene_rom_outskirts_centurion0-39`.

### 2.2 Own-body line

Not applicable: nobody leaves. All six are in the scene, so this is the shared-cutscene case.
- The human holding Rawlings gets the FP view.
- If nobody holds Rawlings, the host (or a volunteer) claims Rawlings before `SchFade`.
- The others watch through their own actor's head (`scenes-catalog.md` #33).

### 2.3 Engineering and risks

- `BeginPlayScene` must target the Rawlings holder; skip the forced switch for everyone else (B5).
- `OnEnd_CenturiansTale` teleports all bodies: allowed here, the scene ends with the squad
  regrouped on purpose.
- Rawlings stays invulnerable until the scene end (`mapcallbacks.lua:210`, `mapscenes.lua:139`): keep it.

### 2.4 Other separations in this level

- **BehemothDead** is a Church-only QTE (`Kill_Behemoth_03`, `UseJustEntity = Church`;
  `mapscenes.lua:79-90`). The others are frozen by `Scene.HideChars` (B10). The existing
  proposal (optional non-blocking clean-up) stands.
- Delgado-only door `o191` (`mapcallbacks.lua:423-426`).

### 2.5 Check in game

Whether a skipped scene (`EscapeScene = true`) still runs `OnEnd_CenturiansTale` for every client.

---

## 3. G10 rom_caldarium: Delgado through the fire

### 3.1 Vanilla facts [O]

Geography (from trigger, door and spawn data):
- The squad enters at spawn 0, Delgado at (-28697, 134, -4628).
- The fire zone `AreaTrigger_Fire` has its centre at (-32476, -550, -7038).
- The squad is **pinned in the hall at (-30732, -170, -4934)**.
- Delgado's route runs south and west through the torture galleries, from z -8 600 down to
  z -13 300.
- It comes back north to the lever `o1119` at (-32234, -159, -4691). The lever sits just
  behind the heavy door `PuertaDelgado1` (-31629, -56, -4888), which separates it from the
  pinned hall.

Sequence:
1. `AreaTriggerHintFireArea` → `MapInit.SchFireArea` plays a random line from
   `MapInit.HintsFireArea` every 35-45 s (`mapcallbacks.lua:181-183`, `mapinit.lua:13-59`).
2. `AreaTrigger_Fire` → `AreaTriggers.EnterFireArea`, `Team.ReviveAll`,
   `SetTeamsThere(V3D(-30732,-170,-4934))` (`mapcallbacks.lua:226-232`):
   - `EnterFireArea` calls `StartSoloMision` (locks switch and orders, holds both AI teams).
   - **Any non-Delgado who enters is killed.** `PlayerBurnOnFire` sets `Game.UsrEntity(0).Life = 0`.
   - Delgado takes 15 damage every 0.5 s unless `uData.bProtection` is set, which is his own
     fire barrier, `Delgado.ActivateBarrier`.
   - Evidence: `scripts/missions/areatriggers.lua:121-150`, `161-168`;
     `scripts/chars/delgado.lua:829-839`.
3. `AreaTrigger` (`_4`) closes `PuertaFuego2` (`mapcallbacks.lua:222-224`).
   `AreaTriggerOutFire` closes `PuertaFuego1`, sets `Active = 0` on Rawlings, Cole, Church,
   Jones and Black, and activates `Primer_cultista_torturador` (`mapcallbacks.lua:189-197`).
4. Delgado's route: `AreaTrigger64`, `44` and `234` (single cultists, then `Primer_gen_cultistas`).
   - `puerta_delgado_1`: checkpoint 1, `tercer_cultista_sorpresa` + `happy_torturer`
     (`mapcallbacks.lua:443-451`).
   - `AreaFire2`: 40 damage per tick (`4-8`).
   - `puerta_delgado_2`: `sorpresaaa` → `segundo_gen_cultistas` (`453-467`).
   - `AreaTrigger308`: checkpoint 2, `cuarto/tercer_gen_cultistas` (`83-90`).
5. `AreaTriggerDelgadoCae` at (-32083, -155, -5201), where Delgado drops back down near the
   lever, sets `Active = 1` on the five again (`mapcallbacks.lua:172-179`).
6. `PalancaDelgado_0` (lever `o1119`, `UseJustEntity = Delgado`) opens `PuertaDelgado1/2`, arms
   `AreaTrigger1079`, calls `EndSoloMision` and saves checkpoint 3 (`mapcallbacks.lua:263-272`).
7. `AreaTrigger1079` OnAllInside → `melee_emb_final` + `explosivos_emb_final`
   (`mapcallbacks.lua:14-22`). `melee_emb_final` is an infinite generator whose spawn points are
   **in the pinned hall** at (-30527..-30755, -176, -5250..-5569), an ambush from behind.
8. Checkpoint loads at waypoints 1 and 2 re-freeze the five through `MapInit.SetSoloMission`
   (`mapinit.lua:5-10`, `66-84`).

Design intent: the orphan placeholder `ToDo___02` says Delgado was meant to go "using the thread
with Church - protection against fire", and `ToDo___04` says he opens a door to the others
(`mapcallbacks.lua:350-377`).

### 3.2 Delgado's line (the one who leaves)

Vanilla route, played by Delgado's human. If nobody holds Delgado, someone must switch to him
(choice a); otherwise the fire kills them, which is the story rule.

### 3.3 The others' line: "The Torturers' Hall"

Premise: the cultists of the Caldarium know the squad is split. While Delgado walks through the
fire, torturers climb out of the blood pits into the hall where the rest wait. The squad must
hold the hall, keep Delgado's way back open, and talk him through the heat.

Route and objectives, all in the pinned hall and the entry corridor (spawn 0 up to
`AreaTrigger1209` at (-31844, 176, -6326)):
1. **Fire entry**, `AreaTrigger_Fire`: the others stay active (B1). Radio:
   `hint_black_150_l4_hot_coals`, `hint_delgado_153_l4_hot_coals` (both unused in vanilla), then
   the vanilla `HintsFireArea` keys.
2. **Wave 1**, when Delgado passes `AreaTriggerOutFire`: 3 CultistaMelee emerge (B2) at the
   `melee_emb_final` spawn points (-30527, -176, -5569), (-30755, -159, -5557), (-30502, -166, -5250).
3. **Wave 2**, when Delgado uses `puerta_delgado_1`: 2 CultistaMelee + 1 CultistaExplosivo.
   - Use the `ke_putada` point (-32276, 165, -5533) for the explosive.
   - Radio: `talk_<char>_enemy_ambush*`, `help_omega*` or `help_alpha*` from Delgado's side.
4. **Wave 3**, when Delgado reaches `AreaTrigger308`: 4 mixed, staggered.
5. **Lever approach**, `AreaTriggerHintLever` camera view or `AreaTriggerDelgadoCae`.
   - Waves stop.
   - The others "hear" Delgado behind the door and play the unused set
     `hint_black_161_l4_lift_door`, `hint_church_162_l4_lift_door0/1`, `hint_jones_163_l4_lift_door`,
     `hint_rawlings_164_l4_lift_door`, and `hint_jones_147_l4_caldarium_lever` at fire entry.
6. **Reunion**: Delgado pulls `o1119`, the doors open (vanilla).
   - Radio: `talk_delgado_rejoin_team0-5` (vanilla category), answered by
     `talk_rawlings_rejoin_team*` or `talk_black_rejoin_team*`.
   - Then the vanilla `AreaTrigger1079` ambush hits the reunited squad.

Optional role, **Church's ward** [guess]:
- Story: realises the "thread with Church" from the design note.
- Church's player stands at the fire edge, inside `AreaTriggerHintFireArea` at (-31202, -150, -7324),
  and keeps his blood rune active.
- While it is active and Church stands there, Delgado's fire damage is halved.
- Implement it as a wrapper around `AreaTriggers.DelgadoBurnDamage` that checks Church's rune state.
- Church can still shoot into the hall, so the hold continues.

Optional role, **Jones's astral help** [guess]:
- Jones's player projects from the hall (B8) and possesses a cultist on Delgado's route.
- This depends on the astral range, which is engine-side.

### 3.4 Engineering

- B1: `AreaTriggerOutFire_0` and `MapInit.SetSoloMission` skip human-held members. Keep
  `SetTeamsThere` for AI members.
- B5:
  - `EnterFireArea` must test the **entering** entity (`Playerid`), not `UsrEntity(0)`.
  - `PlayerBurnOnFire` must kill that entity, not `UsrEntity(0)`. As written, a non-Delgado
    client stepping into the fire kills the **host's** character.
  - `StartSoloMision`/`EndSoloMision` act on `UsrEntity(0)`'s class: apply them to Delgado's holder only.
- Waves: B2 with CultistaMelee and CultistaExplosivo (both in `init.Enemies`).
  - Put them in a list whose vanilla use is over, for example `ke_putada` after `AreaTrigger1209`
    [I], or a new mod list (needs an AI team, [check]).
  - Do **not** activate `melee_emb_final` early (B3), or the post-lever ambush is lost.
- Checkpoints 1 and 2 must re-create the hold state.

### 3.5 Risks

- The others could leave the hall and walk into the fire zone. The zone kills them, which is the story rule.
- Wave pathing in the hall uses the level's nav mesh, which covers the hall [O, `ai/path2dai.pth`
  nodes around x -30..-34k, z -6..-4k].
- If a human Jones stands in the hall during the post-lever ambush, nothing changes from vanilla.

### 3.6 Check in game

- Emerged cultists path into the hall from the `melee_emb_final` points.
- Whether `Active = 0` bodies can be left active without the AreaManager dragging AI members
  into the fire.
- Lever and door sound reach the hall (for the "hear him behind the door" beat).
- Astral range from the hall to Delgado's route.

---

## 4. G11 rom_palace_01: Church crosses the abyss

### 4.1 Vanilla facts [O]

Geography:
- The squad side is around x -57..-61k.
- The abyss bridge `Puente` (-62522, -1651, 4279) is retracted.
- **Church's far side** is x -64..-66k, with:
  - plate `LosetaPuenteA` (-64187, -1531, 4264),
  - the legion door `puertaPuzzlePuente` (-65747, -1183, 6212),
  - the generators `SpawnPuzzlePuente1..4` (-65451..-65457, -1272, 5891..6391),
  - Jones's crank `ManivelaPuertaPuente` (-64383, -1367, 6342; `UseJustEntity = Jones`, `bUseOnTK`),
  - the exit `PuertaPuenteContinuar` (-65742, -1181, 2478).
- Plates `LosetaPuenteB/C` are on the squad side at (-60866, -1526, 5095/3462).
- The ledge `CornisaTheAbyss` (-61407, -1960, 1607) starts at `TriggerTheAbyss` (-61493, -1443, 2595).

Sequence:
1. `legionarios_antes_puzzle` dies (`mapcallbacks.lua:426-443`) or `AreaTrigger757` OnAllInside
   fires (`107-124`). Either one, through `FlagCounter("puzzle", 2)`, does all of this:
   - sets `LegionaryAttackFar = 1`;
   - activates the four infinite `LegionariosPuente*` generators (legionaries throw pilums across
     the abyss from the far side);
   - sets `AstralCam.bPuzzleActive`;
   - starts the shut-door hints `175/176_L4_Block_Legion` (`mapinit.lua:17-40`).
2. Jones closes the legion door with the crank by astral TK (`o237_0`, `mapcallbacks.lua:462-471`).
   The crank stops the generators. After 9 kills the script uses the crank for him
   (`LegionariosPuente2_1`, `263-268`).
3. When all four groups are empty, `TriggerTheAbyss` becomes usable (`245-286`), and Church
   hints `177-180_L4_Cross_Abyss` start (`mapinit.lua:42-64`).
4. `o249_0` (Church only) locks Church's switch and plays `Scene.PlayFP("TheAbyss")`, a QTE
   with 9 sequences (`mapcallbacks.lua:473-486`, `mapscenes.lua:18-81`). Frame 665 places the
   ledge and plays Church's plate hint.
5. Plates: `PressChurch_0` runs on every pulse and needs A, B and C pressed together. Then it
   unlocks Church, opens `Puente` and `PuertaPuenteContinuar` and resets `LegionaryAttackFar`
   (`mapcallbacks.lua:288-302`; pulsers in `mapphysiclogic.lua:19-71`, `AreaTriggers.SetupPulser`
   `scripts/missions/areatriggers.lua:175-243`).
   - Hints: `AreaTriggerHintButtonSafe` → `hint_cole_183_l4_floor_buttons` and
     `HintsOthersButton` (`mapcallbacks.lua:167-170`, `mapinit.lua:66-90`).
   - **No enemies are active during the plate phase.**
6. During TheAbyss, `Scene.HideChars` freezes everyone (B10).

### 4.2 Church's line (the one who leaves): "Alone on the Far Side"

1. Vanilla QTE crossing.
2. New: when the scene ends, the legion door `puertaPuzzlePuente` grinds open again. Legionaries
   emerge on **Church's** side: 4-6 Legionary via B2 at the `SpawnPuzzlePuente*` points, with
   `ForceAction = "Emerge"`; the Emerge animation is loaded, `mapinit.lua:2`.
3. Church fights them in melee next to plate A.
4. The plate phase starts only when this wave is down.

Radio:
- `hint_black_173_l4_block_legion`, `hint_delgado_174_l4_block_legion` (both unused in vanilla);
- `talk_jones_help_church*`, `talk_rawlings_help_omega*`;
- Church: `talk_church_enemy_ambush*`.

### 4.3 The others' line: "Cover the Ledge"

- **During the QTE**: watch from a side camera on `TheAbyssCornisa` (B10 keeps them frozen). A
  truly simultaneous fight needs a scene patch, see 4.5.
- **After the QTE**: the others are on the edge, 2-4k units from Church.
  - They give covering fire across the abyss. Legionaries keep `LegionaryAttackFar = 1`, so they
    also throw at the edge.
  - Jones's player re-closes the legion door: re-enable the crank (`bArrowCanUse = true`) and use
    it by astral TK (B8, `bPuzzleActive`).
- **Plates**: two players stand on B and C, Church on A. With 4 players the 4th covers or
  handles the crank. The vanilla AI fallback through sectors `S_26`/`S_27` stays for AI members.
- **Reunion**: the vanilla bridge opening. Radio: `talk_church_rejoin_team*`, `talk_cole_spot_team*`.

### 4.4 Engineering

- Wrap `MapScenes.OnEnd`. TheAbyss uses `EndOfFpScene`, so hook it, or schedule from the frame-665 generic.
  - Open `puertaPuzzlePuente` (`PhysicsObj.OpenDoor`), spawn the wave (B2 into list
    `LegionariosPuente4`, whose AI team exists), and re-arm the crank.
  - Gate `PressChurch_0` on "wave cleared".
- `o249_0`: `ResetTeamSwitch(Church)` applies to Church's class only. That is harmless in co-op,
  but the radial menu must not offer Church to others anyway.
- `LegionariosPuente2_1` auto-uses the crank with `EJones` after 9 kills. Keep that as the
  fallback for the new wave too.
- The crank's `o237_0` sets `ForceAction "Open"`. Re-arming needs the crank to animate closed
  again [check], or simply re-close the door by script when Jones's player "uses" the crank.

### 4.5 Risks and options

- Option "simultaneous": let the edge team fight **during** the QTE. This needs `Scene.HideChars`
  to skip humans who are not in the scene (`scene.lua:622-638`), and the QTE camera stays on
  viewport 0. That is higher risk. The post-scene wave gives most of the value at low risk.
- Legionaries on the far side might path to the abyss edge and fall. That is acceptable, they die.

### 4.6 Check in game

- Pilum range across the abyss with `LegionaryAttackFar`.
- Whether the crank can be used twice.
- Whether `Emerge` works at `SpawnPuzzlePuente*` (they are generator spawn points, so the floor exists).
- Plate trigger boxes accept human bodies (they should; pulsers use `bAnyPlayerInside`).

---

## 5. G12 sum_ziggurat_01: Jones possessed

### 5.1 Vanilla facts [O]

1. `cultistas_iniciales` (generator, pool 25) dies.
   - `cultistas_iniciales_0` revives all, makes Black, Rawlings and Cole invulnerable with a 0.1 s
     loop (`EnsureInvulnerable`), and starts the possession after 5 s
     (`levels/sum_ziggurat_01/scripts/mapcallbacks.lua:268`; `mapinit.lua:16-27`).
2. `StartJonesPossession` (`mapinit.lua:92-119`):
   - It waits until Jones is alive and the astral camera is off.
   - If the player **is Jones**, it force-switches them to a random squad member.
   - It sets `UnavaliablePlayers.Jones = true`.
3. `JonesGo` walks Jones to (10904, 551, -29926) (`87-90`). `OnJonesArrived` plays
   `casualty_jones` from Rawlings or Black, forces `PossessedInit`, adds an aura and calls
   `MoveSquadAroundJones` (`121-138`).
4. `MoveSquadAroundJones` puts `IgnoreUsrControl = 1` on the player and walks all five into a
   ring around Jones (`242-263`).
5. When the player's body arrives, `JonesPossession` (`77-85`):
   - sets `FacialAlias.Antadurunnu = "Jones"`;
   - sets `EscapeEvent = MapInit.EndOfPossession`, so **the player can end it with Escape**;
   - plays the chat `Mission_sum_ziggurat_01_Anta` (keys `mission_sum_ziggurat_01_anta0-14`)
     with `EndOfPossession` as the callback.
6. `EndOfPossession` releases everyone, plays `PossessedEnd`, opens `puerta_antes_sala_estatuas`
   and activates the six statues. `RestoreSquad` makes Jones available after 4 s (`204-240`).
7. Then `trigEstatuas` OnAllInside (`mapcallbacks.lua:283`) → `EnableStatues` → `Teletransport`
   → `SumTeleport.Teletransport` → level 02 after 25 s (`mapinit.lua:265-307`).

### 5.2 Jones's line: "The Displaced Soul"

Premise: the priest Antadurunnu pushes Jones's soul out of her body. Jones's player is not
switched away. They stay "in" Jones as a displaced soul, and Jones's own gift lets them watch
and fight back.

1. At `OnJonesArrived`: Jones's player goes into astral orbit around their own body (B8,
   `OnlyOrbit = true`, the same call the teleport uses, `sumteleport.lua:60`).
   - Subtitle: "Jones: He's in me... I can see him."
2. While the `anta` chat runs, Jones's soul can drift up to the closed `puerta_antes_sala_estatuas`
   at (9043, 993, -29993) and see the inactive statues.
   - Subtitle only, plus `hint_jones_novoice_l5_follow_urn` (unvoiced text key).
3. **Resist**: three prompts in the HUD style of `Scorer.SetMsgText`.
   - Each one Jones's player holds through skips ahead in the chat.
   - Holding all three calls `EndOfPossession` early. That is the vanilla Escape path made
     diegetic and given to Jones's player only.
4. **Reunion** (vanilla): `PossessedEnd`, then `talk_jones_rejoin_team0-2`;
   `talk_<others>_help_jones*` while it lasts.

Choice (a) remains: Jones's player may instead take a free body. With 4 players and 6 bodies,
two are free, as vanilla does with a random member.

### 5.3 The others

- Human members are not AI-walked. They get a subtitle "Surround Jones".
- `JonesPossession` starts when the first human is within the ring radius, or after a 10 s timeout.

### 5.4 Engineering

- B5: `StartJonesPossession` must test "is Jones held by a human". It must not switch that human
  unless they chose (a), and must not pick a random member held by another human.
- `MoveSquadAroundJones`, `OnXArrived` and `MapInit.player` assume one human. Rewrite them to
  walk AI members only.
- `EscapeEvent` is a global key: in co-op only Jones's holder may trigger it (or the host).
- `EnsureInvulnerable` repeats every 0.1 s on Black, Rawlings and Cole until they arrive: harmless.

### 5.5 Check in game

- Astral camera on a body that plays `Possessed` and has its AI off.
- Can the astral camera move freely, or only orbit (`OnlyOrbit`)?
- Ending the chat early with `EndOfIncidentalChat(true)` leaves no hanging lip-sync.

---

## 6. G13 sum_ziggurat_02 and 03: the scattered squad

### 6.1 Vanilla facts [O]

sum_ziggurat_02:
- Only Jones and Black are loaded (`levels/sum_ziggurat_02/scripts/map.lua`, `init.Team = {"Jones","Black"}`).
- `MapInit.Init` force-switches Jones → Black, slows time and hides Jones (`mapinit.lua:10-17`).
- Black's route:
  1. Start (4825, 752, -25663).
  2. `AreaTrigger215`: `primeros_cultistas` + `segundos` and the begin chat
     `mission_sum_ziggurat_02_begin0-3` (`mapcallbacks.lua:46-52`).
  3. `segunda_puerta`, then `tercer_grupo_cultistas`.
  4. The Black-only TK `TK_Activator` at (-2817, 257, -4334) opens `tercera_puerta` and starts
     the labyrinth groups (`259-267`, `357-360`).
  5. Radio hints `192-194_L5_Find_Jones` from Jones at `AreaTriggerHint1-4` (`152-167`).
  6. The labyrinth groups die → `puerta_antes_jones` opens and `ShowJones` places Jones in his
     cell at (-13617, 0, -3901) (`309-316`, `mapinit.lua:19-28`).
  7. `trigCloseDoor` closes the door behind Black and arms the astral puzzle (`368-375`).
  8. Jones's astral TK on the high lever `oMani` (-13346, 1195, -3956) opens the cell `oJonesDoor`
     and the exit `oPuertaFinal` (-16178, 422, -5858), and activates `hijosdeputa` (`328-339`).
     Jones's hint 196 points at the torture victims upstairs (`oTortured1/2`).
  9. `AreaTrigger26` at (-17099, 106, -5958) → sum_ziggurat_03 (`57-59`).
- The orphan chat `mission_sum_ziggurat_02_findjones0/1` (Jones calls, Black answers) is never played.
- Orphan design placeholders in this level's callbacks describe the intent:
  - "Here appear Delgado and Rawlings surprisingly" (`AreaTrigger13_0`, 13-17);
  - "Black receives message from Jones" (`AreaTrigger7_0`, 118-125);
  - "Cole contacts the player via radio and says she is able to teleport them all ... near the
    top of the tower" (`AreaTrigger44_0`, 95-105).

  They sit at sum_ziggurat_03/04 coordinates, which shows the three levels were cut from one.
- Nav data: sum_02's AI nodes cover x -19 649..5 340 and z -26 751..4 399.
  - This includes a **dead-end corridor past `oPuertaFinal` and past the exit trigger**, from
    (-16 079, 161, -5 751) to (-19 509, 157, -8 271).
  - The `hijosdeputa` spawns are inside it at (-18046, 281, -5795) and (-18121, 268, -6007).
  - Source: `levels/sum_ziggurat_02/ai/path2dai.pth` in `Data05.packed`, first `N×12` bytes are node positions [I].

sum_ziggurat_03:
- `init.Team = {"Jones","Delgado","Rawlings","Black"}`. `InitThis` hides Delgado and Rawlings
  (`levels/sum_ziggurat_03/scripts/mapinit.lua:10-15`).
- Boss: Ninlil + Ki at (-23492, 1304, 1575).
  - `SummerianNINLIL.Use` opens Ninlil only if `UsrEntity(0)` is Jones
    (`scripts/chars/summerianninlil.lua:249-253`).
  - Ninlil summons emerging CultistaMelee (`279-287`).
- `Enemy_Group_0` (boss dead) opens `puerta_tras_demonios` and makes the Delgado-only door `o25`
  usable (`mapcallbacks.lua:189-195`, `269-272`).
- `AreaTrigger79` at (-26239, 855, 1595) → `ShowRawlings`:
  - Delgado is placed at (-27398, 836, 2190) and plays `BrokenWall`; Rawlings at (-27275, 836, 2754);
  - `wallDelgado` (-27432, 848, 2077) breaks;
  - lines `Rejoin_Team3/5` (`mapcallbacks.lua:70-75`, `mapinit.lua:17-31`).
- Nav data shows a **small pocket behind the wall**: nodes (-27339, 746, 2293) and (-27619, 745, 2923).
- sum_02's nav does not reach x < -19 649, so the 03 pocket and arena are **not** in sum_02's
  level data. Each Sumer level has its own `map3d.msh` (sizes differ in `Data05.packed`).

### 6.2 Who plays what (4 players, survivors Black, Church, Delgado, Rawlings)

| Player holds | sum_ziggurat_02 | sum_ziggurat_03 | sum_ziggurat_04 |
|---|---|---|---|
| Black | vanilla (solo route) | vanilla | vanilla |
| Delgado | **"The Far Corridor"** (own line) | **"Behind the Wall"** (own line) → reunion | vanilla |
| Rawlings | with Delgado | with Delgado | vanilla |
| Church | (a) **Jones** "The Voice in the Cage", or spirit; (b) optional rear guard [guess] | (a) Jones (Ninlil needs a human Jones), or spirit | G14 own line |
| Jones (if a player holds Jones) | **"The Voice in the Cage"** | vanilla | vanilla |

### 6.3 Jones's line in sum_02: "The Voice in the Cage"

Premise: the vortex dropped Jones into a cell deep in the tower. She is awake, cannot get out,
and can reach Black only with her gift and the radio.

- Start: Jones is placed in the cell at the `ShowJones` position at **level start**, not after
  the labyrinth. `oJonesDoor` and `puerta_antes_jones` stay closed.
- First beat: the orphan chat `Mission_Sum_Ziggurat_02_FindJones` (Jones: "can you hear me",
  Black answers) when Black reaches `AreaTriggerHint1`.
- Objectives:
  1. **Guide.** Jones's astral flight reaches the labyrinth (B8). Their pings mark cultists of
     `cultistas_laberinto`/`ultimos_laberinto` for Black. The vanilla hints `192-194` play when
     Jones's player is within a set distance of Black's trigger, not on Black's entry.
  2. **Find the hand.** Jones scouts the torture victims upstairs (`oTortured1/2`) so that the
     vanilla puzzle is solved at once when Black arrives.
     - Keep the vanilla gate: `oMani` is usable only after `trigCloseDoor`.
     - Radio: `hint_jones_195/196_l5_door_lever`.
- Reunion: the vanilla `oMani` → cell opens. Radio: `talk_black_rejoin_team*` and
  `talk_jones_rejoin_team1`.

Engineering:
- `ShowJones` and `trigDisableBlack` logic run at start.
- The AI loops `trigDisableBlack`/`trigBlackAgain` (`362-386`) assume one human: skip them for a
  human Jones.
- Jones's body must not leave the cell: its door is closed [check collision].

### 6.4 Delgado and Rawlings in sum_02: "The Far Corridor"

Premise: the vortex threw Delgado and Rawlings deeper into the tower, into the corridor behind
Jones's cell block. The tower jams the radio. They hear only fragments of Black and Jones
(subtitles), and fight to keep the cultists in that corridor away from the cell block.

- Spawn: at the dead end (-19509, 157, -8271) and (-19649, 205, -7501). Add Delgado and
  Rawlings to `init.Team` and to the spawn entry only when humans hold them.
- Objectives:
  1. **Wake up and push east**: 2 small waves of emerging CultistaMelee (B2) along the corridor
     nodes (-19369, 157, -6871) and (-18739, 157, -6031).
     Radio: `talk_rawlings_gencom_sumerian*` (the Tower of Babel line), `talk_delgado_gencom_sumerian*`.
  2. **Hold at the door**: when Black clears the labyrinth (`cultistas_laberinto_0`), the pair
     reaches the closed `oPuertaFinal` from the far side.
     - They fight the `hijosdeputa` generator **as its vanilla content** (pool 10, 2 at once),
       started for them at that moment.
     - Black then meets an empty corridor after `oMani`. Either keep it empty, or spawn 2 B2
       stragglers for Black.
  3. **The tower takes them**: when `oMani` opens `oPuertaFinal`, before Black can see them,
     both vanish with the vortex FX (B7).
     - Subtitle: "Rawlings: It's pulling us again—" plus `talk_rawlings_unexpected*`.
     - Their players watch as spirits near Black until sum_03 loads.
- Reunion: in sum_ziggurat_03 (6.5).

Engineering:
- `AreaTrigger26` (`mapcallbacks.lua:57-59`) must fire only for Black or Jones (B6). The pair
  stands **beyond** it, so any step east would load sum_03.
- `AreaTrigger391` stops `hijosdeputa`. Delay it until the pair is gone.
- `init.Team` and spawn edits happen before `Team.CreateTeam` (`init.lua:332`). The spawn tuple
  layout is positional (`team.lua:1270-1312`).
- AI: Delgado and Rawlings are created with AI that follows the player team. Set them to hold
  (`HoldPosSide`), or turn their AI off while humans hold them.
- Without human holders, nothing is loaded (vanilla).

### 6.5 Delgado and Rawlings in sum_03: "Behind the Wall"

Premise: the vortex dropped them into a collapsed side passage next to the demon arena. They
hear the fight with Ninlil and Ki through the stone. Cultists climb out of the dark end of the
passage.

- Spawn: in the pocket at (-27339, 746, 2293) and (-27619, 745, 2923), active from level start
  (B1 replaces `InitThis`'s hide for human-held members).
- Objective: hold the pocket against small emerging waves (B2, CultistaMelee is loaded) from its
  far node, timed with the boss fight:
  - one wave when Ninlil first uncovers,
  - one when Ki dies [guess at a suitable hook: `Enemy_Group_1` OnAttackAI and `Enemy_Group_2` OnDeath].
- Radio from inside: `talk_delgado_under_heavy_fire*`, `talk_rawlings_help_alpha*` (fragments, subtitled).
- **Reunion**:
  - When the boss group dies (`Enemy_Group_0`), Delgado's player uses the wall. Make `wallDelgado`
    usable with `UseJustEntity = Delgado`, as the light doors are.
  - That calls the vanilla `ShowRawlings` minus its teleport for human bodies.
  - Fallback: the vanilla `AreaTrigger79` when the others walk up.
  - Lines `talk_delgado_rejoin_team3/5` (vanilla), plus `talk_black_rejoin_team2/3`.
  - After that, Delgado opens `o25` (vanilla).

Engineering:
- `ShowRawlings` sets positions and plays `BrokenWall` on `EDelgado`. For a human Delgado, play the
  animation without moving the body, or move it by the few units needed.
- The pocket must be closed off from the arena until the wall breaks [check: the wall door
  `wallDelgado` is a `Sum_BrokenWall` door object; collision before opening].
- B5: `SummerianNINLIL.Use` must accept any human Jones. Otherwise a 4-player group whose Jones is
  AI cannot uncover Ninlil.

### 6.6 Church (and Cole) in sum_02/03

Church and Cole have **no body** in sum_02 or sum_03 (`init.Team`).
- Recommended: choice (a). Church's player plays Jones in sum_02 (6.3) and sum_03. In sum_03 a
  human Jones matters, because only Jones can uncover Ninlil.
- Spirit otherwise.
- Optional (b), low value [guess]: a "rear guard" in sum_02's start corridor. It would load
  Church's body, close `primera_puerta` behind Black, and hold B2 waves, then vortex out (B7) when
  Black frees Jones. It adds a body but little story. Not recommended over (a).

### 6.7 Feasibility and checks

- Medium. Most of the work is roster editing per level (init.Team and spawn tuples) and trigger guards.
- Check in game:
  - sum_02 corridor beyond `AreaTrigger26` is walkable and lit;
  - `oPuertaFinal` blocks sight;
  - the sum_03 pocket is enclosed and the wall has collision before `OpenDoor`;
  - astral flight range from the cell to the labyrinth;
  - `Emerge` cultists in the pocket do not spawn inside walls (`Game.TestSphere` is not used by B2).

---

## 7. G14 sum_ziggurat_04: Cole and Church return

### 7.1 Vanilla facts [O]

- Spawn 0 creates **all six**, Cole at (-27056, 8467, -3286) and Church at (-26833, 8410, -3049)
  (`levels/sum_ziggurat_04/scripts/mapspawnplayers.lua`).
- `MapInit.Init` hides Cole and Church and sets `uData.CannotSpeak` on them (`mapinit.lua:5-10`).
- Main group:
  1. `trigActVoladores` in the west gallery (around x -31..-36k) → `primer_volador` +
     `segundos_voladores`. When both are dead, `puerta_demonios` (-27222, 9347, -6452) opens
     (`mapcallbacks.lua:297-312`).
  2. `TrigActivateSumms` OnAllInside **closes `puerta_demonios` behind the squad** and starts
     Enlil + Inanna and the four wheels (`272-283`).
  3. `Summs_0` → `trigUrn` → `AppearChurchCole` → `ReposSquad` walks the squad to the urn
     (`235-238`, `326-332`; `mapinit.lua:90-140`).
  4. `OnPlayerArrived` opens the door, activates `voladorFinal` (one flyer named `Enemy`), and
     `KillEnemy` blows it up **with `Weapons.Damager = "Cole"`**.
  5. Then `LetsGo` makes Cole and Church appear at (-26564, 9116, -5719) and (-28317, 9116, -5916),
     on the hall side of the door, and walks them in. Church says `Rejoin_Team`
     (`mapinit.lua:40-77`, `125-136`).
- The orphan chat `Mission_Sum_Ziggurat_04_Begin` (Cole on the radio: a paradox, a spatial rift,
  "activating the time loop", a 3-2-1 countdown) is never played.
- Unused Church and Cole hints for the blood-fed demon and the urn walk exist (section 1). The
  original design had them at this fight.
- `NextLevelLoad_0` → sum_05 and `AreaTrigger_4` (Nanna/Utu) are leftovers from before the split
  (`mapcallbacks.lua:231-233`, `76-80`).

### 7.2 Cole and Church's line: "The Time Loop"

Premise: the vortex left Cole and Church outside the tower's time. Cole builds a time loop to
drop them back in. It lands them exactly where the squad has just been, behind the demons' door.

1. **Level start until the boss door closes**: their players are spirits near the main group
   (bodies hidden as vanilla).
   - The orphan chat `Mission_Sum_Ziggurat_04_Begin` plays over the radio in steps:
     - lines 0-2 at level start,
     - 3-6 when the gallery flyers die,
     - 7-9 (countdown) when `TrigActivateSumms` closes the door.
   - The chat path ignores `CannotSpeak` (`TeamTalk.IsValidChatPlayer` checks only `Life`,
     `teamtalk.lua:436-439`), so the chat plays while Cole is hidden. Single `RadioTalk` lines
     from Cole or Church need `CannotSpeak` lifted (B9).
2. **Arrival**: at the end of the countdown both appear in the hall north of the door
   (B7 arrival FX) at the `LetsGo` positions. B1 takes control of them.
3. **Hold the hall** while the main group fights inside:
   - 3 waves (B2): CultistaVolador from the gallery spawn points (-35220, 10134, -1810) and
     (-35237, 10278, -4864); CultistaMelee emerging at hall nodes around (-27344, 9023, -6284)
     and (-27544, 9024, -6084).
   - Radio support through the door: `hint_cole_200_l5_ki`, `hint_church_203_l5_ki0-2`,
     `hint_cole_204_l5_ki_attack`, `hint_church_207_l5_ki_attack0/1`,
     `hint_church_208_l5_puppet_master0/1`, `hint_rawlings_210_l5_puppet_master`. All unused in
     vanilla, and they fit Inanna and Enlil.
4. **Reunion** (vanilla, with Cole's player doing the kill):
   - `trigUrn` → the door opens and `voladorFinal` appears.
   - If Cole is human, `KillEnemy`'s scripted explosion waits until Cole's player kills the flyer
     (timeout 10 s, then the vanilla blast).
   - `LetsGo` walks only the AI bodies; humans walk in themselves.
   - `talk_church_rejoin_team0-2` (vanilla), then the unused `hint_cole_l5_follow_urn0/1` and
     `hint_church_l5_follow_urn` on the urn walk.

Choice (a) instead: before the door closes, Cole or Church players can take a free body if one
exists. With 4 players there is none: the main four hold Jones, Delgado, Rawlings and Black.

### 7.3 Engineering

- B1: keep Cole and Church hidden until the countdown, then reveal them.
- Lift `CannotSpeak` at the reveal so their single radio lines play. The chat needs no change
  (`IsValidChatPlayer`, `teamtalk.lua:436-439`, ignores `CannotSpeak`).
- `ReposSquad`, `OnPlayerArrived` and `ForcePlayerToWatchScene` lock `UsrEntity(0)` only. In
  co-op, lock the main-group humans for the short urn scene (as the original does for one) and
  leave Cole and Church free.
- `LetsGo` teleports Cole and Church. Skip that for human bodies.
- Waves in the hall must stop at `trigUrn`, and leftovers must be killed (`EnemyGen.Stop`
  pattern, or Life = 0 on the B2 list).
- `MapEffects.Teleport` at `trigUrn` + 15 s teleports everybody to meat (`fx/sum_ziggurat_04/mapeffects.lua:102-105`): unchanged.

### 7.4 Check in game

- The hall and gallery stay loaded and lit while the door is closed.
- Flyers from the gallery points reach the hall.
- `puerta_demonios` blocks sight and sound.
- Cole's damage counts on the `Enemy` flyer, which has `Invulnerable = 1` set in `OnPlayerArrived`.
  This must be lifted for the human kill.

---

## 8. G15 sum_end: the final phase

### 8.1 Vanilla facts [O]

- Bodies: Black, Church, Delgado, Rawlings (spawn 0). Jones and Cole die in the intro scenes
  TheEndA/B (`levels/sum_end/scripts/mapinit.lua:11-14`; `scenes-catalog.md` #37-38).
- Enemies: only `EvilFB`. `EvilFirstBorn.OnCreate` creates `EvilAbabanili`, a stolen copy of
  Delgado's fire spirit, and three `EvilGhostHeal` named `EGHBlack`, `EGHChurch` and
  `EGHDelgado` (`scripts/chars/evilfirstborn.lua:112-178`). The fight AI is engine-side
  (`scripts/ai/aievilfirstborn.lua` is 22 lines).
- Possession: `EvilFirstBorn.Incapacitate` freezes a member and makes it unavailable for 1 s.
  `DoSwitch` force-switches the player away (`evilfirstborn.lua:257-291`).
- Black emulation: the Firstborn TK-grabs a member and hits it (`314-356`).
  `OnAfterHitStrong` releases every member from `Stupid` with `StupidEnd` (`358-376`).
- Final phase: the Firstborn casts a blood rune (`Spell2` → `DoBloodRune`, `235-249`).
  `DrawBloodRune` does all of this (`473-513`):
  - calls `SchMakeAllUnavailable`, which every 0.1 s forever turns off the AI of Black, Delgado and
    Rawlings, forces `StupidInit` and marks them unavailable (`515-534`);
  - switches the player to Church after 2 s;
  - draws blood links from the rune to the three.
- Win: `IncapacitateSch(Church)`, with Church as the human in FP and `RuneBloodActive == 1`, calls
  `KillFirstBornScene` → `MapInit.EndOfGame` → TheEndC/D (`293-312`, `579-587`;
  `mapinit.lua:52-56`).

### 8.2 The stunned trio's line: "Break the Blood Link"

Premise: the Firstborn has taken their gifts and bound them with Church's own blood magic.
Church must face it, but the others can still fight the binding, and then fight the stolen
powers that hunt Church.

1. When the rune links them, each stunned player sees a struggle prompt.
   - Holding Use for about 6 s with interruptions [guess at tuning] breaks their link: `StupidEnd`,
     AI stays off, control returns.
   - Radio when free: `talk_<char>_revived*`, `talk_<char>_help_church*`.
2. Free members fight the stolen powers:
   - Delgado vs `EvilAbabanili` (radio `hint_delgado_219_l5_kill_utu0/1`, unused);
   - Black and Rawlings vs the `EGH*` ghosts.
   - They cannot hurt the Firstborn itself (it stays `Invulnerable` per vanilla gating).
3. The Firstborn may re-cast the rune. The struggle repeats.
4. The kill stays Church's: vanilla `RuneBloodActive` check, with Church's human in FP.
5. Reunion: TheEndC/D with all four (vanilla).

### 8.3 Engineering

- Patch `SchMakeAllUnavailable` to skip members flagged "broke free" until the next `DoBloodRune`.
- `DrawBloodRune`, `DoSwitch` and `IncapacitateSch` test `UsrEntity(0)` (B5):
  - the forced switch to Church must not move other humans;
  - "Church is human in FP" must check Church's holder.
- If Church is not held by a human: the host claims Church before the rune (forced-switch rule).
- `EvilAbabanili` and `EGH*` are created inactive (`bActive = false`). Whether the engine AI
  activates them during the final phase is unknown [check]. If not, activate them when a member
  breaks free (they already have AI from `AISpec.CreateAI`).
- `MapInit.CheckAmmoLow` refills AI ammo only (`UsrControl == -1`, `mapinit.lua:29-50`). Humans
  may need the same.

### 8.4 Check in game

- Whether `EvilAbabanili` and `EGH*` are damageable and what they do when activated by script.
- Whether `StupidEnd` on a human body returns full control.
- Whether the Firstborn's AI retargets a freed member and breaks the Church-only finish.

---

## 9. Other separations in Acts 4-5

| Level | Section | Who acts | Co-op handling |
|---|---|---|---|
| rom_outskirts | BehemothDead QTE | Church | Watch or non-blocking clean-up (existing proposal) |
| rom_tepidarium | Firstborn-child astral chain (`AreaTriggerPuzzleJones_0`, `levels/rom_tepidarium/scripts/mapcallbacks.lua:114-141`; lever `o1039` → `o1165_0` 354-384) | Jones (astral hops between invulnerable, senseless legionaries) | Others guard Jones's body. When the lever is pulled the four legionaries wake and attack (`AI.NotifyImpact`), so the guard has a fight. Radio `hint_ross_169_l4_firstborn` (unused). Delgado door `o243` follows. |
| rom_palace_01 | Jones crank (legion door) | Jones | Part of G11 |
| rom_palace_02 | Delgado's final door, then AI walk (`puerta_final_delgado_1` → `GoToFinalScene`, `levels/rom_palace_02/scripts/mapcallbacks.lua:458-462`, `mapinit.lua:7-13`) → TheTrap | Delgado | Lock all humans during the walk. The level also holds a dead copy of the abyss code (`o249_0`/`PressChurch_0`, 245-260, 421-431) with no TheAbyss scene: ignore it. |
| rom_coloseum | 3-plate pulser puzzle (`mapcallbacks.lua:215`), arena waves | all | Natural co-op; nothing to add |
| rom_chamber | Player AI-walked to Vicus, others teleported (`mapinit.lua:17-50`) | — | Walk AI only; teleport only AI bodies |
| sum_ziggurat_01 | Leach flight (`StartFlyingCultistsScene`, `mapinit.lua:29-72`) | — | Watch |
| sum_ziggurat_03 | Ninlil uncover is Jones-only; astral hint camera (`mapinit.lua:54-135`) | Jones | B5 for `SummerianNINLIL.Use`; the hint camera uses viewport 0 |
| sum_ziggurat_04 | Urn walk (`mapinit.lua:90-136`) | — | Part of G14 |
| sum_ziggurat_meat | Arrival lock (~12 s, `sumteleport.lua:101-139`); end walk and teleport (`levels/sum_ziggurat_meat/scripts/mapinit.lua:22-70`) | — | Lock all humans; unused `kill_utu` hints for Black, Church, Delgado, Ross can join the fly-nest fight |
| sum_ziggurat_05 | IntoTheUnknown, cutscene only | — | Watch |
| sum_end | Firstborn possession (`Incapacitate`/`DoSwitch`) before the final phase | possessed member | The possessed human is frozen for the vanilla 1 s; no forced switch in co-op |

---

## 10. Consolidated in-game checks

1. rom_caldarium: emerged cultists in the pinned hall; `Active = 0` skipped safely; fire-burn
   targeting the entering body; door sound through `PuertaDelgado1`.
2. rom_palace_01:
   - legion re-spawn on the far side;
   - crank reusable;
   - pilum range;
   - plates accept humans;
   - (option) `Scene.HideChars` skipping humans.
3. sum_ziggurat_01: astral orbit around possessed Jones; early `EndOfPossession` from the chat.
4. sum_ziggurat_02:
   - corridor beyond `AreaTrigger26` walkable;
   - extra bodies loaded through `init.Team` and the spawn tuple;
   - `oPuertaFinal` blocks sight;
   - Jones in the cell from the start;
   - astral range.
5. sum_ziggurat_03: the pocket behind `wallDelgado` is enclosed and spawnable; a human-triggered
   `ShowRawlings`; Ninlil `Use` from a non-host Jones.
6. sum_ziggurat_04: the hall stays active behind the closed door; the radio chat audible to all
   players while Cole is hidden; the `Enemy` flyer killable by Cole.
7. sum_end: `StupidEnd` on humans; activating `EvilAbabanili`/`EGH*`; the Church-only win with
   the other three active.

## 11. Suggested order of work

1. G10 and G11. Same pattern (hold + B2 waves), both Rome, high value, low risk.
2. G14. Mostly reveal timing, B2 waves and orphan audio.
3. G15. A small patch set on `evilfirstborn.lua`, but engine AI unknowns.
4. G12. Depends on the per-viewport astral camera (shared with the spirit role).
5. G13. Largest: roster edits in two levels, trigger guards, astral guide.

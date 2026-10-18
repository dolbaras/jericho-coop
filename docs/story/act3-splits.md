# Act 3 (Crusades): co-op splits G7 "The Lost Patrol" and G8 "Hold the Gate"

Status: design proposal, 2026-10-18. Scope: cru_river, cru_labyrinth, cru_sewers, cru_keep,
cru_catacomb, cru_chapel. Builds on `mod/docs/coop-story-extensions.md` (G7, G8) and the
owner's decisions:

1. At every split, a player whose character leaves chooses (a) switch to a character who goes
   on, or (b) stay in their own body and play that character's own line, ending in the
   reunion the story already has.
2. The owner wants the big G7 option, **"The Lost Patrol"**: Jones, Cole and Rawlings get their
   own path while Delgado, Church and Black play cru_labyrinth → cru_sewers → cru_keep →
   cru_catacomb, and both groups meet in cru_chapel where `TheRescue` plays.

Conventions: `[O]` read in the scripts, `[I]` inferred from them, `[guess]` design guess or
unverified engine behaviour. Paths are relative to `work/src/levels/` unless stated. Voice
lines are given as catalog keys only (`work/voices/catalog.tsv`); a key is built by
`TeamTalk.ForceRadioTalk` as `<Prefix>_<Char>_<Text>[N]` (`scripts/chars/teamtalk.lua:227-238`),
so `TeamTalk.RadioTalk("Cole", "Spot_Team", "Talk", 2)` plays `talk_cole_spot_team2`.

---

## 1. Vanilla facts

### 1.1 Where the trio is lost (cru_river)

- The level ends with the use object `Trigg_DelgadoDoor` (Delgado only) →
  `MapScenes.CrossOverBridge` → scene `BridgeCollapses` (`cru_river/scripts/mapcallbacks.lua:284-287`,
  `mapscenes.lua:132-136`). The scene is filmed from `FP_Delgado` and has the actors Black,
  Church, Cole, Jones, Rawlings, `CultistaVolador`, `TemplarioAmigo` and `PuenteRoto`
  (`mapscenes.lua:14-23`, `148-199`). Its end callback loads the next level at once:
  `SaveGame.NewLevelNow("Cru_Labyrinth")` (`mapscenes.lua:144-146`). [O]
- Scene subtitles `Scene_Cru_River_Bridge0..4` (`mapscenessnd.lua:162-166`). Content in short:
  Ross orders Alpha across the bridge under Omega's cover; Delgado and Ross shout; the friend
  crusader says the lost ones now belong to the children, and that the damned smell the
  squad's souls and they must get inside. [O, catalog]
- So the captors in the game's own words are **the children** (the ghost child crusaders), and
  a flying cultist (`CultistaVolador` actor) is present when the bridge falls. [O+I]
- Orphan design note `Tag_04` (`mapcallbacks.lua:272-282`): a Firstborn puzzle with
  Jones+Black, then "the bridge collapses and half of the team disappears", the rest follow the
  friend crusader through the catacombs, change of level. Not wired to any trigger (the 13 area
  triggers of the level do not call it). [O]
- Unused callbacks `AreaTrigger_Bridge_0` / `AreaTrigger_Tower_0` call
  `MapInit.BridgeExplosion` (`mapcallbacks.lua:115-117`, `161-163`); no trigger uses them. [O]
- The bridge area: lever `Palanqueitor` at (-14275, -4693, 15768), Delgado door
  `Trigg_DelgadoDoor` at (-12174, -5032, 14570) (`mapphysiclogic.lua:11-19`, `996-1004`). The
  riverbed checkpoint (spawn Id 3) is at about (-8300, -5370, 11000) (`mapspawnplayers.lua:105-145`).
  Whether there is walkable ground below the bridge is unknown [guess: no].

### 1.2 The four levels without the trio

| Level | `init.Team` in map.lua | Spawn flags | Note |
|---|---|---|---|
| cru_river | all 6 (`map.lua:7-14`) | all 6 true in Ids 0-3 | |
| cru_labyrinth | Delgado, Church, Black (`map.lua:5-9`) | trio false | |
| cru_sewers | Delgado, Church, Black (`map.lua:6-10`) | trio false | |
| cru_keep | Delgado, Church, Black (`map.lua:6-10`) | trio false | |
| **cru_catacomb** | **all 6** (`map.lua:8-15`) | trio false in all 3 entries (`mapspawnplayers.lua:8,14,32 / 57,63,81 / 106,112,130`) | entries Id 1 and Id 2 have `Init 0` = **Jones** as the main character (`mapspawnplayers.lua:56`, `105`), although Jones is not spawned |
| cru_chapel | all 6 (`map.lua:6-13`) | all 6 true (`mapspawnplayers.lua:7-47`) | |

[I] cru_catacomb still loads the trio's classes and once expected Jones to be playable there
(`Init 0`). This matches the orphan note `Tag_05` below. The three levels that load all six
(river, catacomb, chapel) are exactly the levels a trio path can use without touching
`map.lua`.

### 1.3 The orphan rescue notes (cru_catacomb, copied into cru_chapel)

`cru_catacomb/scripts/mapcallbacks.lua` keeps a prototype script that once covered both the
catacomb and the chapel. None of the `Tag_*` callbacks is wired to a trigger
(`mapareatriggers.lua` has 18 triggers, none calls a `Tag_*`). [O]

| Note | Lines | What it says (short) |
|---|---|---|
| `Tag_00_0` | 339-350 | catacomb of "plague victims": cultist ambushes, TK and Black+Delgado fire to clear coffins |
| `Tag_07` | 382-384 | entrance to the CC (child crusader) section, cultists do not dare to enter, a door opens by magic |
| `Tag_02` | 352-360 | "Rescue": inside the CC crypt, the children attack, after enough kills the **torture chamber** opens |
| `Tag_03_0` | 362-366 | about to enter the **Inquisitorium**, the children stop pursuing |
| **`Tag_05`** | **368-380** | **"Here is the rest of the team"**: a **bar door** keeps the player from them; a puzzle that needs a **switch to Jones** opens it; then the rescue cinematic (Rawlings explains the children and Maltheus); then the squad goes to the chapel. Warning: rescued mates absent for the rest of the prototype "due to AI issues". |
| `Tag_09_0`, `Tag_10_0` | 386-411 | Maltheus fight in the half-ruined chapel, then the breach and a friend crusader cinematic |

The same notes are duplicated in `cru_chapel/scripts/mapcallbacks.lua:167-233`. [O]

[I] In the prototype the trio was held **behind a bar door at the end of the children's
crypt**, before the chapel, and freeing them needed Jones. The shipped game moved the reunion
into the first seconds of cru_chapel (TheRescue). The note's own warning ("AI issues") is the
reason it was cut, which co-op humans would solve.

Also orphaned in cru_catacomb: `AreaTrigger8` sits at (21541, -1724, -2872)
(`mapareatriggers.lua:8`), which is chapel coordinates; the catacomb's nav helpers only span
x -20301..4193 (`mapmovehelpers.lua`). [I] leftover of the merged prototype, no geometry there.

### 1.4 TheRescue (cru_chapel)

- Plays on **every** chapel load: `MapInit.main` schedules `MapInit.PlayTheRescue` →
  `Scene.PlayFP("TheRescue")` and `MapInit.ColeFirestorm` (Cole power tutorial)
  (`cru_chapel/scripts/mapinit.lua:1-14`, `178-204`). The level has one spawn entry (Id 0). [O]
- Definition: `CameraFrom = "FP_Black"`, `FPPos` (19415.6, -1815.4, -3434.5)
  (`mapscenes.lua:3-15`). Actors: FP_Black, Jones, Rawlings, Delgado, Cole, Church
  (`mapscenes.lua:24-59`). End: `Scene.EndOfFpScene`, then activates `bebes_cruzados`
  (5 ghost children) (`mapscenes.lua:61-65`); their death opens door `o577`, revives and
  reequips the squad (`mapcallbacks.lua:249-253`). [O]
- Sound track: the camera walks in for about 13 s of footsteps before the first line
  (`mapscenessnd.lua:31-71`); subtitles `Scene_Cru_Chapel_Begin0..25` (`mapscenessnd.lua:5-30`). [O]
- Content (keys `scene_cru_chapel_begin0..25`): Rawlings tries to calm a wounded, panicking
  Cole, who threatens everyone with her gun; Ross asks what happened; Rawlings says **the
  children** wanted them to suffer as they once did; Jones felt them inside his skull; Rawlings
  says Cole got the worst of it (darkness, closed spaces, being touched); Black talks Cole down
  with the golden ratio; Jones jokes; Ross: find the next breach; Rawlings asks whether the
  others reached the Templars; Delgado: yes, and the Templars think Leach's people are seraphim
  and the squad is evil; Rawlings is sorry he missed it. [O, catalog]
- Where they were held: the spawn positions (19400-19700, -1815, -3400..-2160) and FPPos are in
  the room that has the chapel's torture props: `Tortured_HandCufs_C`, `Tortured_SpikeChair_A`,
  `Tortured_WallPress_C` at (19937..20979, -1843..-1733, -2641..-2486)
  (`cru_chapel/scripts/mapphysicobjects.lua:536-596`). [I] **The trio was held and tortured in
  the chapel's torture chamber (the "Inquisitorium" of Tag_03), by the children.** They are
  armed when found (Cole aims her weapon).
- Main group context that the scene relies on: in cru_labyrinth `CruzadersSpeech_A`
  (FP_Delgado, `mapscenes.lua:5-9`) the friend crusader hands Delgado, Church and Black to Arnold
  Leach (key `scene_cru_labyr_arnold12`: Leach says to let the heretics entertain the
  children); in `CruzadersSpeech_B` the Templar prisoner explains Maltheus, the Children's
  Crusade whose blood opened the breach, and that the bishop is still in the crypt with the
  children; if the friends are there, pray for them (keys `scene_cru_labyr_prisoner7..14`). [O]
- End of cru_catacomb: last children group `Enemy_Group` dies → `MapCallbacks.Enemy_Group_3`
  opens floor slab `LosetaB`, `Team.ReviveAll`, and 3.5 s later the chat
  `Mission_Cru_Catacomb_Exit` (Ross senses the missing team close; Delgado: find them fast)
  (`cru_catacomb/scripts/mapcallbacks.lua:239-246`, `mapinit.lua:16-18`). [O]

### 1.5 Layout of cru_catacomb (needed for both options)

Positions are trigger or group centres from the level files.

| Part | Where | Content | Callback chain [O] |
|---|---|---|---|
| Plague halls (cultists) | x -20000..-12000, y -1900..-1100 | `Cultist_1`, `Explosive_emerge_0/1` (gen, pool 10), `cultista_tras_puerta`, `Enemy_Group_cruzados_ballesta_0`, `Enemy_Group_cultistas_puente`, `Enemy_Group_explosivos_sorpresa(2)` (gen), `Explosives_crossbow` (gen), `Enemy_Group_pepe` (CruzaderB gen, pool 11), `Enemy_Group_pepe3/4` | checkpoint 1 at `Explosive_emerge_0_0` (door `o1637`, 303-312); checkpoint 2 at `Explosives_crossbow_0` after 9 deaths (door `puerta_cc`, 325-333) |
| Transit | x -12500..-7100 | — | — |
| CC entrance | slab `LosetaA` (-7097, 84, 70) | opened by `ATrigger_O_LosetaA` **OnCameraView** (box -7354,-152,82, camera point -6941,93,82) | `mapcallbacks.lua:4-8`, `mapareatriggers.lua:149` |
| Children's crypt | x -5500..4300, y 200..900 | `Enemy_Group_nens1` (8 ghost children, ~(-1985, 933, 646)), `Enemy_Group_nens2` (9, ~(4272, 323, -350)), `Enemy_Group` (5, ~(126, 190, -9275)) | `AreaTrigger1336` chat (-5530); `AreaTrigger1335` → nens1 + Black radio (-2308); `AreaTrigger1354` (1683,291,-5215) → nens2 after counter `primer_grupo`; `ninyos4` (-18,439,-7811) → `Enemy_Group` after `segundo_grupo` |
| Exit | slab `LosetaB` (-286, 71, -9675), `Next_Level` (-485, -253, -10796) | — | `Next_Level_0` → `SaveGame.NewLevel("Cru_Chapel")` on any OnEnter (335-337) |

Ghost children have `uDataAI_DistVis = 100000` in `mapenemies.lua` (almost all entries). [O]
Whether that makes them notice a group across the map is unknown [guess: only when active].

### 1.6 Tools the scripts already give us [O]

- `NPC.ActivateEnemyGroup(G)` is **one-shot**: it sets the save var
  `<level>.EnemyGroup.<G>.Status` to "1" and does nothing on later calls (`scripts/chars/npc.lua:248-252`).
- `NPC.CreateWithAI(acName, x, y, z, listName)` creates a fresh enemy of any preloaded type
  (`init.Enemies`) into an existing group, with AI; a `GhostChildCruzader` also gets its
  `ChildCruzader` pair (`npc.lua:29-56`). This is the way to make **new waves from existing
  groups and enemy types** without editing maps.
- Generators: `EnemyGen` reads `isInfinite`, `poolSize`, `maxSimultaneousEnemies`, spawn
  times; with `uData.isInfinite = true` it spawns new enemies at the group's own spawn points
  forever (`scripts/chars/enemygen.lua:4-28`, `91-104`, `139-160`); `EnemyGen.Stop(G, killAll)`
  ends it (161). No Crusades group is infinite today, but `uData` can be changed at run time
  [I].
- Radio: `TeamTalk.isFiltered` filters a line as radio when the speaker is more than
  `NonFilterDist = 20` from user 0 (`teamtalk.lua:212-225`) [I: units unclear]. Distant
  groups therefore already sound like radio.
- Team assignment is fixed by the spawn code: Alpha = Jones, Cole, Delgado; Omega = Church,
  Rawlings, Black (`scripts/chars/team.lua:1270-1316`). The lost trio is not one AI team.

---

## 2. "The Lost Patrol" (G7)

### 2.1 Story premise

- **Who:** the ghost children of the Children's Crusade, who rule the crypt under Maltheus'
  chapel. Arnold Leach's flying cultist breaks the bridge; the friend crusader says the fallen
  now belong to the children. Leach later tells his Templars to let the other three "entertain
  the children" too: both halves of the squad are meant to end in the same crypt.
- **Why:** the children feed on suffering; they want the living to hurt as they did (Rawlings in
  TheRescue). They "smell souls" (bridge scene). They do not kill the trio; they drag them down
  and torment them, Cole worst of all.
- **What the trio does in co-op:** they do not wait to be rescued. They wake in the gorge, fight,
  are taken, break out, and are taken again, each time closer to the chapel. Every trio segment
  ends the same way: the children close in, fade to black, a subtitle. This one device lets any
  segment end at any moment, which is what keeps the two groups in sync (section 3).
- **Ending:** the trio's last stand is in the chapel's torture chamber, armed and spent, which is
  exactly the state TheRescue shows. The main group walks in. TheRescue plays as the reunion.
- **The bar door of Tag_05** becomes the trio's last obstacle in the crypt, and its "switch to
  Jones" puzzle becomes a Jones astral task (see T2).

### 2.2 Who plays what

- At the end of `BridgeCollapses` each player who holds Jones, Cole or Rawlings chooses
  (a) switch to Delgado, Church or Black, or (b) stay and play the Lost Patrol. Players who hold
  Delgado, Church or Black stay with the main group (they may also choose to join the trio by
  taking a free trio body, if the owner wants that) [guess].
- Each group needs at least one human; the session host stays in the main group (it owns the
  campaign save). With 4 players the split can be 3+1, 2+2 or 1+3.
- If nobody chooses (b), the trio is not simulated and the vanilla flow (plus the spirit role
  for a bodiless 4th player) applies.
- Trio members without a human are AI and follow the trio's human.

### 2.3 Route, level by level (full version)

Clock = the main group's levels. Trio segments T1-T3 use only the three levels that already load
all six characters (river, catacomb, chapel).

| Main group plays | Trio plays | Trio segment |
|---|---|---|
| cru_labyrinth | cru_river, riverbed | **T1 "Below the Bridge"** |
| cru_sewers, cru_keep | cru_catacomb, crypt in reverse, then the plague halls in reverse | **T2 "The Children's Crypt"** |
| cru_catacomb | cru_chapel, torture chamber | **T3 "The Inquisitorium"** (short, or folded into the merge, see 2.5) |
| cru_chapel | together | reunion: TheRescue, then Maltheus |

#### T1 "Below the Bridge" (cru_river, while the main group is in cru_labyrinth)

- **Start:** a new trio-only spawn entry (bJones/bCole/bRawlings true, the others false) at the
  riverbed checkpoint positions of Id 3 (about (-8300, -5370, 11000)), fade in, subtitle: the
  three wake in the blood river below the broken bridge [guess: there is no reachable ground
  under the bridge itself].
- **Objective 1, regroup:** Jones' player is the leader. Beats: `talk_jones_rejoin_team1`,
  `talk_rawlings_dark_area1`, `talk_cole_dark_area1`, then Cole tries the radio:
  `talk_cole_spot_team2` / `talk_cole_spot_team3` (no answer; subtitle).
- **Objective 2, the corpse golems:** `AreaTriggerCultistasSalaDigim` (-9158, -5355, 12224) as
  in vanilla starts the flyers zone; `AreaTrigger_Behemoth_01` (-7286, -5134, 14520) wakes
  Behemoth_01 and Behemoth_02 (`Behemoth_00_Group_`). These two have no "sellote" lock, so the
  seals (medallions) can be shot by anyone [I from `behemoth.lua:634-646`, check in game]. The
  existing hint table `Behemoth.HintsMedalions` already contains Jones and Rawlings
  (`hint_jones_88_l3_medallions`, `hint_rawlings_89_l3_medallions`), and Cole's
  `hint_cole_86_l3_medallions` exists in the catalog but is unused in vanilla; add it to the
  table for this segment.
- **Not used:** `Group_Behemoth_03` (needs Church's QTE `BehemothDead`); do not activate it
  (its activation is in `Behemoth_00_Group__1`, `mapcallbacks.lua:184-193`, patch for this
  segment). Not used: the lever, the drawbridge, `Trigg_DelgadoDoor`, the Firstborn.
- **Extra pressure:** flying cultists by `NPC.CreateWithAI("CultistaVolador", ...)` into
  `Enemy_Group_09` (the group's own type and spawn points); explosive cultists from the
  `grup_prova_2` spawn points if the trio walks that far upstream.
- **End (any time, or at `AreaTrigger_Behemoth_03` (-7701, -5344, 18333)):** the children come:
  screen darkens, `talk_cole_terrified*` (non-verbal), fade, subtitle "The children take them."
  The segment never loads another level by itself.
- Length [guess]: 15-25 min, shorter than cru_labyrinth.

#### T2 "The Children's Crypt" (cru_catacomb, while the main group is in cru_sewers and cru_keep)

- **Start:** trio-only spawn deep in the crypt near the last children's room, around
  `Enemy_Group` (126, 190, -9275) [guess: verify ground; use enemy or move-helper positions],
  bodies wounded (Life lowered), subtitle: they wake among small coffins.
- **Objective 1, out of the ossuary:** `Enemy_Group` (5 ghost children) attacks at start.
  Its vanilla death callback `Enemy_Group_3` must be replaced in this segment (it opens LosetaB,
  revives and plays the main group's exit chat). LosetaB stays closed: the way to the chapel is
  barred.
- **Objective 2, the long hall:** the trio walks the crypt backwards: `ninyos4` area → hall of
  `Enemy_Group_nens2` (activate directly; the vanilla counters `primer_grupo`/`segundo_grupo`
  expect the opposite order) → `AreaTriggerDescojono` (2100, 240, 1789) → hall of
  `Enemy_Group_nens1`. Vanilla triggers on the way (`AreaTrigger1354`, `AreaTrigger1335`,
  `ninyos4`, `AreaTrigger1336`) are switched off for this segment. Beats:
  `talk_jones_gencom_crusade2` (Jones on the Children's Crusade being real),
  `talk_rawlings_gencom_crusade1`, `talk_cole_cramped_area0..2`, `talk_cole_dark_area2`,
  `talk_*_weird_sound*`, `talk_*_forboding_sound*`.
- **Objective 3, Tag_05's bar door, inverted:** the trio reaches `LosetaA` (-7097, 84, 70) from
  inside. It is closed. Hints: `hint_cole_106_l3_raise_bars` and
  `hint_rawlings_109_l3_raise_bars` (both exist in the catalog and are **unused** in vanilla:
  cru_river's `MapInit.HintsDoorBridge` only lists Black 104, Church 105, Jones 108 and Ross 110,
  `cru_river/scripts/mapinit.lua:82-99`), then `hint_jones_108_l3_raise_bars`.
  **The Jones puzzle:** the slab opens from `ATrigger_O_LosetaA`, which fires **OnCameraView**
  of a camera point outside (-6941, 93, 82). Jones' astral projection flies through the slab and
  looks back at that point; the slab opens [guess: depends on whether the astral camera counts
  for OnCameraView; fallback: a scripted check that the astral camera is inside a box around the
  camera point, then `PhysicsObj.OpenDoor("LosetaA")`]. Without a human Jones, the AI Jones does
  it after a delay (vanilla AI already uses powers in scripted spots) [guess].
- **Objective 4, the plague halls in reverse:** past the transit, the trio meets the cultists of
  the plague halls from the far side: `Enemy_Group_pepe4`, `Enemy_Group_pepe3`,
  `Enemy_Group_pepe` (CruzaderB generator), `Explosives_crossbow`, `Enemy_Group_cultistas_puente`
  (activated by script, not by their vanilla triggers; their shared death callback
  `Explosives_crossbow_0` must not open `puerta_cc` or autosave in this segment). The halls are
  the main group's next level, but T2 runs in its own instance in the full version, so nothing
  is consumed.
- **End:** near the catacomb start the children catch up (they "do not dare" the plague halls in
  Tag_07, so this is their anger breaking the rule): fresh ghost children by
  `NPC.CreateWithAI("GhostChildCruzader", ...)` into `Enemy_Group_nens1`, fade, subtitle "They are
  dragged back under the chapel."
- Checkpoint inside T2: the open LosetaA (for reloads and for the sync rule).
- Length [guess]: 30-45 min, close to cru_sewers + cru_keep together.

#### T3 "The Inquisitorium" (cru_chapel, while the main group is in cru_catacomb)

- **Start:** the chapel's own spawn entry (the trio's three positions only), with TheRescue
  suppressed in this instance (it plays on every load, `mapinit.lua:1-14`).
- **Objective:** break free in the torture chamber and hold it. `bebes_cruzados` (5 ghost
  children) attack; after they die, more come by `NPC.CreateWithAI` into the same group at its
  own positions (~(19058, -1634, -1593)), in waves with pauses, until the merge. Door `o577`
  stays closed in this instance (patch `bebes_cruzados_0`). Maltheus' triggers
  (`AreaTrigger_Maltheus`, `trigMaltheusScene`, `TriggerCloseTentacles`) are off.
- Beats: `talk_rawlings_cramped_area2`, `talk_cole_cramped_area1`, `talk_*_ammolow*`,
  `talk_*_help_alpha*` and `talk_*_help_omega*` heard as "nobody answers", and, when the main
  group reaches the end of cru_catacomb, the first contact: `talk_cole_spot_team1` (Omega in
  sight), `talk_jones_spot_team1`.
- T3 is optional: if the trio is still in T2 when the main group leaves the catacomb, T2 ends
  with its fade and the trio goes straight to the reunion.

#### Reunion (cru_chapel, all players in the main host's level)

- The trio's players spawn in their own bodies at the vanilla chapel positions (all six are
  already in the torture chamber, `mapspawnplayers.lua:7-47`).
- **TheRescue plays unchanged.** Why it still fits "on foot": the trio is in the chamber, armed,
  after a last stand; Cole's breakdown is the price of T1-T3; Black walking in is the main group
  arriving. Nothing in the scene says that the trio was chained when found (the props are
  there, the characters stand).
- Co-op variant details only: who watches through FP_Black (Black's player; if Black has no
  human, a stand-in view as in `scenes-catalog.md` #31), and a one-line subtitle before the
  scene if the trio played T3: "Delgado, Church and Black break into the Inquisitorium."
- After the scene, vanilla continues: `bebes_cruzados`, Cole's Firestorm tutorial
  (`MapInit.ColeFirestorm` checks `UsrEntity(0).Name == "Cole"`; route the hint to Cole's
  player), Maltheus. `MapInit.IncidentalMaltheusVulnerable` needs Church, Jones and Black alive
  (`mapinit.lua:117-126`), which holds.

### 2.4 Voice beats summary (keys only)

| Beat | Keys |
|---|---|
| Trio wakes, regroups | `talk_jones_rejoin_team1`, `talk_jones_dark_area1`, `talk_rawlings_dark_area1`, `talk_cole_dark_area0..2` |
| Cole tries the radio | `talk_cole_spot_team2`, `talk_cole_spot_team3` |
| Corpse golems | `hint_jones_88_l3_medallions`, `hint_rawlings_89_l3_medallions`, `hint_cole_86_l3_medallions` (unused in vanilla), `talk_*_enemy_immune*` |
| Children's crypt mood | `talk_jones_gencom_crusade2/3`, `talk_rawlings_gencom_crusade0/1`, `talk_cole_cramped_area0..2`, `talk_*_weird_sound*`, `talk_*_forboding_sound*`, `talk_*_terrified*` (non-verbal) |
| Dead ends, bars | `talk_*_hint_impassable*`, `hint_cole_106_l3_raise_bars`, `hint_rawlings_109_l3_raise_bars` (both unused in vanilla), `hint_jones_108_l3_raise_bars` |
| A way out | `talk_rawlings_spot_exit*`, `talk_cole_spot_exit*` |
| Main group thinks of them | `talk_black_gencom_crusade2` (Black worries about Cole in the dark), `talk_black_gencom_crusade3`, `talk_delgado_gencom_crusade6/7` (time to find the others) |
| Contact | `talk_cole_spot_team0/1`, `talk_jones_spot_team0/1`, `talk_rawlings_spot_team3/4`, `talk_church_spot_team1/2`, `talk_black_spot_team*` |
| Reunion (Option A only, see 3) | `talk_jones_rejoin_team0`, `talk_rawlings_rejoin_team1/2`, `talk_delgado_rejoin_team0`, `talk_church_rejoin_team0/1`, `talk_black_rejoin_team0..5` |
| Chapel | vanilla `scene_cru_chapel_begin*`, `mission_cru_chapel_*`, `hint_*_142..145_l3_attack_maltheus` |

All other new text is subtitles (segment titles, "The children take them", objectives).

---

## 3. Implementation options

### 3.1 Option A: same level, parallel areas, one host

**Idea:** only cru_catacomb has two areas that both groups can use at once and a story reason
for the trio to be there (the children's crypt is under the chapel, the main group is in the
plague halls). In labyrinth, sewers and keep the trio has no body (map.lua loads only three) and
no story reason to be there, so its players are **spirits** (Tier 2, "echoes of souls held by
the children") or switch (owner rule (a)).

Flow in cru_catacomb (co-op variant script):

1. Spawn all six: main group at the vanilla entry, trio at the crypt start of T2 (new spawn
   entries; the classes are already loaded, `map.lua:8-15`).
2. Trio plays T2 objectives 1-3 (Enemy_Group, nens2, the bar slab). nens1 stays **inactive**
   while the trio walks through its hall (`AreaTrigger1335` off).
3. Main group plays the plague halls as vanilla, to `puerta_cc` (checkpoint 2) and the transit.
4. Trio waits at the closed `LosetaA` with a hold: fresh ghost children by
   `NPC.CreateWithAI` into `Enemy_Group_nens1`'s positions, low rate, until the main group
   arrives. `ATrigger_O_LosetaA` is disabled until the main group has reached checkpoint 2
   (otherwise the trio's own view, or Jones' astral view, could open the slab early).
5. Meeting at LosetaA: the slab opens (from the main side, or Jones' astral puzzle once the main
   group is in the transit, as the joint puzzle). Contact and rejoin lines (section 2.4).
6. The six together: nens1 now activates (the children return), then the empty crypt to
   `LosetaB`, which the script opens after nens1 dies (vanilla `Enemy_Group_3` already fired
   for the trio; its exit chat `Mission_Cru_Catacomb_Exit`, "Ross senses them", must be
   suppressed because the squad is already whole).
7. `Next_Level` must require the merged state (vanilla fires on any OnEnter, so the trio could
   have loaded the chapel alone by walking past LosetaB if it were open).
8. cru_chapel: TheRescue plays unchanged as a debrief (Cole's breakdown comes after the crypt).
   This is the weak point of Option A: the "rescue" is already done. Acceptable [guess], or
   prefix a subtitle "In the chapel, the strain catches up with Cole."

Effort: small to medium on the level side (one level variant: 2-3 spawn entries, about 8
triggers gated, 4 group callbacks replaced, 2 hold spawners, subtitles, radio). The real cost is
in the co-op core: **a second human-led AI group far from the first** (AI followers that follow
their own human, AreaManager sectors in a linear chain `Area_S_00..`, `mapareateam.lua`), and
area triggers that fire for any squad member. Medium overall [guess: 1-2 weeks once the core
supports per-player follow].

Risks: AI squad logic assumes one squad (`AIGen.GetPlyName` = user 0 everywhere); `OnAllInside`
triggers never fire while the groups are apart (catacomb uses them on 1335/1336/1354, chapel on
`TriggerCloseTentacles`, after the merge, fine); vanilla callbacks that act on "the squad"
(`Team.ReviveAll`, `Team.Reequip`) revive the far group too (harmless, even welcome); ghost
children `DistVis 100000` might pull towards the wrong group [check]; one host simulates both
groups (cost low).

Sync: the main group is the clock. The trio's T2 crypt part is shorter than the plague halls, so
the trio waits at LosetaA under the hold. If the trio is slow, the main group waits in the
transit (LosetaA does not open until the trio is at it, or the slab opens and the trio is
teleported to its side with the "children drag them" fade) [design choice; recommend: open
after a 3-minute grace with the teleport fade].

Saves: one host, one save. Checkpoints 1 and 2 of the catacomb are main-group events; add
co-op spawn entries that place the trio at its own last stage (start / bar slab / merged) and
encode the stage in a level save var (`cru_catacomb.FlagCounter.*` style, which is saved with the
game and cleared on level change by `Game.DelSaveVars("")`, `scripts/missions/savegame.lua:344`).
Which groups already fired is in `<level>.EnemyGroup.<G>.Status` [O]; how dead enemies are
restored on a checkpoint load is not known [check].

### 3.2 Option B: two groups in two levels, a second authority

**Idea:** the full route of 2.3. The main host runs the campaign levels. One trio client becomes
a second authority and runs T1 (cru_river), T2 (cru_catacomb) and T3 (cru_chapel) as private
instances with a trio-only spawn entry. At the reunion the trio's players leave their instance
and join the main host's cru_chapel.

Effort: large. Level scripting for T1-T3 is moderate (three variants, about a week [guess]); the
cost is the networking: a session with two hosts, routing each player to an instance, joining
the main level mid-session, and cross-instance signals (main group's level changes, "main at
catacomb exit"). Testing needs two full game instances; the owner's machine cannot run two D3D
instances safely (two Jericho windows froze the desktop), so this needs a second PC or a
headless game mode that does not exist yet [O for the constraint, guess for the rest].

Risks: everything in Option A that concerns one group's AI, plus: the trio instance must never
save the campaign (`SaveGame.AutoSaveWaypoint`, `SoftSaveAutoSave`, `HardSaveGame` blocked or
redirected) and never change level (`SaveGame.NewLevel`/`NewLevelNow` in river, catacomb and
chapel callbacks blocked); the trio instance runs levels with only three bodies, so scripts that
assume Delgado, Church or Black (cru_river `MapInit.main` touches Church's and Cole's act
classes, the Behemoth QTE is Church's) must be checked; TheRescue must be suppressed in T3;
desync if the trio host drops (fallback: the trio's players join the main level as spirits).

Sync (which group waits for which):

- The main group never waits. Its level changes drive the trio: entering cru_sewers moves the
  trio from T1 to T2 (T1 ends with its fade if unfinished); entering cru_catacomb moves it to T3
  (T2 ends with its fade if unfinished); the catacomb's `Next_Level` ends T3 and pulls the trio
  into the chapel.
- If the trio finishes a segment early, it does not start the next one before the main group's
  level change. Instead its players join the main group's current level as spirits until then
  (the children "let their souls drift"), which also gives them something to do.
- The "children take them" fade is the universal cut, so no segment needs a hard end.

Saves: the main host's campaign save stays the only real save. The trio's stage (segment and its
internal checkpoint) is kept by the main host as co-op session data, re-sent when the main group
loads a level, because level save vars are wiped on level change (`savegame.lua:344`). On loading
a campaign save mid-Act 3, the trio restarts the segment that matches the main level
(labyrinth → T1, sewers → T2 start, keep → T2 from LosetaA, catacomb → T3).

### 3.3 Comparison and recommendation

| | Option A: same level | Option B: second authority |
|---|---|---|
| Trio content | 1 level (the crypt, about 15-25 min) + spirit role in 3 levels | 3 segments, about 60-90 min [guess] |
| Story fit | good until the chapel; TheRescue becomes a debrief | best; TheRescue plays as written |
| Level work | one catacomb variant | three variants (river, catacomb, chapel) |
| Core work | per-player follow for a second group in one level | all of A plus multi-instance sessions, routing, join mid-level |
| Testing on the owner's PC | 1 game instance + headless bot | needs a second game instance (second PC) |
| Saves | one save, extra spawn entries | one save + session data for the trio |
| Sync | trio waits at LosetaA, main waits at most a grace period | main never waits, trio segments are cut by the fade |

Recommendation: build **Option A first** (it is also the meeting logic and the crypt segment of
B), with T2 written so the same script runs in either a shared or a private catacomb. Add
Option B later as the full Lost Patrol if the multi-instance core becomes possible. In Option A
the trio's players in labyrinth, sewers and keep get the spirit role plus subtitle "echoes" of
the trio (short text beats from T1 and T2, shown at the main group's checkpoints) so the line
continues even without bodies.

---

## 4. G8 cru_sewers: "Hold the Gate" (Black and Delgado stay below)

### 4.1 Vanilla sequence [O]

1. `Enemy_Generator_Jumpers_0` (counter `zona_final` 5): revive, `TriggerEscalada` usable,
   autosave 1, chat `Mission_Cru_Sewers_Tunnel` (Church goes to check the tunnel alone)
   (`cru_sewers/scripts/mapcallbacks.lua:197-210`). Climb hints repeat:
   `hint_black_80_l2_climb_gate` (`mapinit.lua:171-174`).
2. `TriggerEscalada_0` (Church): scene `Escalada`, `AreaTriggers.SoloMision = true`
   (`mapcallbacks.lua:362-367`). In the scene, frame 0 `DeactivateChurchOrders` (switch and
   orders locked), frame 300 `HoldAllTeams` 5 s later (`mapscenes.lua:82-98`, `320-331`).
   Church ends at `FPPos` (-4751, 1571, -10507) (`mapscenes.lua:21`). Black and Delgado hold in
   the jumpers' hall (~(-4400, 1076, -10500), where `Enemy_First` and `Enemy_Generator_Jumpers`
   spawn) [I].
3. Church's route: `AreaTriggerDescenso` (-8147, 1429, -11807) → QTE `DescensoA/B`
   (`mapcallbacks.lua:268-276`) → `TriggerBloodWar` (206, 872, -7282): **`Black.bActive=false`,
   `Delgado.bActive=false`** and the fire-ward tutorial (`mapcallbacks.lua:355-360`) → the ward
   placed in the trigger starts `BloodWarGroup` (4 CruzaderA, generator) (`mapinit.lua:21-29`) →
   its death opens `DoorCuartichi` and `Enemy_Cuartichi` (`mapcallbacks.lua:153-157`) →
   `Cuartichi_2` (`AreaTrigger467`) → counter `cuartichi` 2 → `TriggerAperturaPuerta` usable,
   chat `Mission_Cru_Sewers_L3_Door_Mechanism` (Black asks Church over the radio whether there is
   a door mechanism) (`mapcallbacks.lua:179-186`).
4. `TriggerAperturaPuerta_0` (Church only): opens `DoorCuartichi836`, sets Black and Delgado
   active again, scene `AperturaPuerta` (FPPos (-3857, 1077, -8864)), `SoloMision = false`
   (`mapcallbacks.lua:319-331`). In the scene Black and Delgado are hidden at frame 0 and shown
   (AI on) at frame 289 (`mapscenes.lua:100-119`); then orders back, hold, follow, chat
   `Mission_Cru_Sewers_Rescue` ("Miss me?", key `mission_cru_sewers_rescue0`)
   (`mapscenes.lua:127-152`).

### 4.2 The co-op line

- **Choice at Escalada:** a Black or Delgado player chooses (a) switch to Church if Church has no
  human, or (b) stay below. Church's player plays the vanilla solo unchanged (climb, QTEs, blood
  ward, Cuartichi, the door).
- **Stay active:** skip `bActive=false` (`mapcallbacks.lua:357-358`) for human-held Black or
  Delgado. AI-only Black/Delgado may keep the vanilla behaviour. `SoloMision` locks only the
  class of `UsrEntity(0)`; in co-op it must lock only Church's player.
- **Objective "Hold the gate":** the noise of the fight brings the Templar patrol back into the
  jumpers' hall (Tag_00 mentions a 12-crusader patrol as the original plan, `mapcallbacks.lua:288-298`).
  Three phases tied to Church's progress:

| Phase | Starts when | Enemies (existing types and spawn points) | Ends when |
|---|---|---|---|
| H1 "They heard us" | Escalada ends (frame 300) | `Enemy_Generator_Jumpers` re-armed: `uData.isInfinite = true`, max 2 at once, its 4 spawn points around (-4422, 1076, -10481); one CruzaderB on the `ultimo_ballesta` perch (-5218, 1494, -10580) by `NPC.CreateWithAI` | Church enters `TriggerBloodWar` |
| H2 "Second wave" | `TriggerBloodWar_3` | `Enemy_First` spawn points (-4162, 1076, -10712) CruzaderA, max 2; crossbowmen from the `ballesta_prueba` points | `BloodWarGroup` dead |
| H3 "From below" | `BloodWarGroup_0` | CultistaMelee with the `Emerge` animation (preloaded, `mapinit.lua:2`) at the hall's positions, max 3 | `TriggerAperturaPuerta_0` |

  At the end: `EnemyGen.Stop(G, true)` for the re-armed groups. Clear the re-armed groups'
  `OnAllDeath` callbacks first: `Enemy_Generator_Jumpers_0` would otherwise re-enable the climb
  and autosave again (`mapcallbacks.lua:197-210`).
- **Pacing:** spawn rate scales with the number of humans below; `Team.ReviveAll` at each phase
  change; if both below are down, they stay down until the door opens (no game over; they watch
  Church as spirits meanwhile).
- **Radio beats:** before the climb `talk_delgado_gencom_crusade8/9` (Delgado tells Church to
  stay close), `hint_black_80_l2_climb_gate`; during H1-H3 `talk_black_help_omega*`,
  `talk_delgado_help_omega*`, `talk_*_enemy_ambush*`, `talk_*_under_heavy_fire*`; vanilla
  `Mission_Cru_Sewers_L3_Door_Mechanism` now has a real speaker below; reunion
  `mission_cru_sewers_rescue0`, then `talk_black_rejoin_team2` or `talk_delgado_rejoin_team0`.
- **AperturaPuerta:** keep the scene for Church's player. For human Black/Delgado, skip the
  `ShowChar(false/true)` toggles (they would vanish and get AI turned on, `scenes-catalog.md`
  section on ShowChar); they watch from their own bodies. Their position: the scene assumes them
  behind the door; if a human wandered off, move them to the hall side at frame 289 [guess].
- Effort: small (one level, one variant). This is Tier 1 and does not depend on the Lost Patrol.

---

## 5. Feasibility and what to check in game

Feasible without new geometry: yes for G8 and Option A; Option B depends on a multi-instance
co-op core that does not exist yet.

Checks, in order of importance:

1. **Area triggers and AI members:** does `OnEnter` fire for AI squad members and for humans other
   than user 0? (decides how many vanilla triggers must be gated when groups are apart).
2. **`OnCameraView` (LosetaA):** whose view counts (user 0 only, any human, the astral camera)?
   Decides the Jones puzzle and the gating of the slab.
3. **Second group's AI:** can AI Jones/Cole/Rawlings follow a human who is not user 0 in another
   part of the map (sectors `Area_S_*` in `cru_catacomb/scripts/mapareateam.lua` are one linear
   chain)? Can the team assignment be changed to Alpha = trio, Omega = main
   (`team.lua:1270-1316`) without side effects?
4. **Trio spawn points in the crypt and riverbed:** stand the trio on enemy positions of
   `Enemy_Group` / `nens2` and on cru_river spawn Id 3; check the floor and the nav helpers.
5. **Ghost children vision:** with `uDataAI_DistVis = 100000`, do active children in the crypt
   chase the main group across the map, or the trio only?
6. **Re-arming groups:** `NPC.CreateWithAI` into a dead group (does the group's `OnAllDeath`
   fire again; does the AI attack at once); switching `uData.isInfinite` on a generator at run
   time; `EnemyGen.Stop(G, true)`.
7. **Behemoth_01/02 without Church:** killable by seals only? (`behemoth.lua`, `ActivateSellote`
   is called only for Behemoth_03 in `cru_river/scripts/mapcallbacks.lua:109-113`).
8. **Checkpoint loads in a variant level:** how dead enemies and fired groups
   (`<level>.EnemyGroup.<G>.Status`) come back after loading a checkpoint.
9. **TheRescue with six present bodies and several humans:** `Scene.EndOfFpScene` moves user 0 to
   `FPPos`; check where the other humans end up and that `Scene.HideChars` freezes and restores
   human bodies correctly.
10. **cru_sewers G8:** human Black/Delgado through `AperturaPuerta`; the scene's `ShowChar`;
    `SoloMision` only on Church.
11. **Option B only:** cru_river/catacomb/chapel with only the trio spawned (scripts that read
    `EChurch`, `EBlack`, `Act.GetClass("Church")`), no save and no level change from the trio
    instance, and a second machine for testing.

Open questions for the owner:

- Option A first (crypt + spirits), then B? Or B only?
- In Option A, is TheRescue as a "debrief" acceptable, or should the merge move to the chapel by
  keeping the trio behind `LosetaB` (shorter crypt part for the trio, but the scene plays as a
  true rescue)?
- Should main-group players be allowed to join the trio (take a free trio body) at the split?

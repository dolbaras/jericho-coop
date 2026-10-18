# Act 2 (WWII): "stay in own body" story lines for the squad splits

Status: design proposal, 2026-10-18. Scope: wwii_biggates, wwii_pillboxes, wwii_mosque,
wwii_mosque_inside, wwii_vigil, wwii_vigil_inside, wwii_brandenburg; splits G4, G5, G6 from
`mod/docs/coop-story-extensions.md`, plus the smaller separations in these levels.

Conventions:
- File references are relative to `work/src/levels/<level>/scripts/` unless a path starts with
  `scripts/` or `models/` (then relative to `work/src/`).
- Positions are world coordinates `(x, y, z)` copied from the level tables, rounded.
- [guess] = inference not confirmed by the scripts. [U] = unknown, must be checked in game.
- Voice keys are catalog keys from `work/voices/catalog.tsv`. In scripts they are called as
  `TeamTalk.RadioTalk(<Char>, <Category>, <Prefix>, <Number>)` or `SayCategoryMember`
  (`scripts/chars/teamtalk.lua:182-205`); the key is built as `Prefix_Char_Category<n>`
  (teamtalk.lua:236). `talk_*`, `hint_*` and most `mission_*` keys have a radio variant
  (`*_.ogg`); `scene_*` keys and `mission_wwii_vigil_bum0` have a plain variant only.

Owner decisions that constrain this document (memory, 2026-10-18):
- At a split, a player whose character leaves chooses (a) switch to a character who goes on,
  or (b) stay in their own body and play that character's own story line, which ends in a
  reunion the story already has.
- Downed players are revived only by Rawlings (human or AI). G4 is the one place where
  Rawlings himself is down, so it needs a scripted exception (vanilla already has one: the
  player, as Ross's spirit, revives him).
- Difficulty scaling adds no extra enemies. The story content below re-runs existing groups;
  this is content, not scaling, but the owner should confirm it (open question 1).

---

## 0. Summary

| Split | Who leaves | Own-body line | Where it plays | Reunion (existing) | Rating |
|---|---|---|---|---|---|
| G4a | Cole, ~21 s | "Path of Souls" QTE, already hers; the others hold `nazis_final` meanwhile | pillbox field | scene `DelgadokillsRawlings` | easy-medium |
| G4b | Rawlings (shot) | **"Stations of the Path"**: Rawlings' soul walks back along the Path of Souls past the three wrecked pillboxes to his body, while the squad defends the body | trap door → pillbox field → body | revive, then vanilla `Mission_wwii_Pillboxes_Conflict` chat | medium (Tier 1 part easy; soul part depends on the Tier 2 spirit) |
| G5 | Jones, Delgado, Black | **"The Diversion"**: they stay in wwii_vigil with the Black Watch commandos and hold the breached courtyard while the infiltrators are inside | wwii_vigil courtyard (second session) | start of wwii_brandenburg ("Church joins the rest of the team") | hard (Tier 3) |
| G5 fallback | same | **"The Vigil's mouth"**: they are loaded into vigil_inside and hold its entrance corridor | vigil_inside S_13-S_16 | crypt door / brandenburg start | medium, needs new enemy coordinates |
| G6 | Cole, Rawlings (hidden all level) | **"The Gate Top"**: they hold the captive Lichthammer on top of the gate and give overwatch to the group below | top of the gate, (-23505, 533, 66981) | scene `NaziSacrificeB`, then `ReposPeople` at the breach | medium |

---

## 1. Shared tools (used by all three)

These are the building blocks; each is grounded in existing script behaviour.

1. **Re-arming an enemy group.** `NPC.ActivateEnemyGroup` runs once per save var
   `<level>.EnemyGroup.<Group>.Status` (`scripts/chars/npc.lua:248-256`). `EnemyGen.Stop` sets
   `uData.Stopped` and, with `killAll`, kills the members (`scripts/chars/enemygen.lua:161-200`).
   To run a group again: set the save var back to `"0"`, clear `uData.Stopped`, and call
   `ActivateEnemyGroup`. Only **infinite** generators (`isInfinite = true`) can respawn without
   limit (`EnemyGen.ActivateSpontaneousEnemy`, enemygen.lua:139-159); finite generators stop when
   their pool is used; plain groups cannot come back once dead.
2. **Spawn points are data.** A generator spawns at the positions of the entities listed in its
   group (`EnemyGen.CreateGenData`, enemygen.lua:4-28, reading `MapEnemies` rows). New spawn rows
   with existing classes are possible without geometry, but that is "new enemy placement", which
   the brief does not allow by default. Proposals below say when they need it.
3. **Pressure without new enemies.** `EnemyGen.IncreaseMaxEnemies(group)` (enemygen.lua:212-219)
   raises a generator's simultaneous count.
4. **Keeping a body active / pinned.** `bActive`, `oAI.bEnable`, `Invulnerable`, `ForceAction`,
   `IgnoreUsrControl` are already used for every staged pose in these levels
   (pillboxes `mapscenes.lua:150-196`, brandenburg `mapinit.lua:72-116`). A "leash" (teleport back
   if a body leaves a radius) is the same pattern as vigil_inside `MapInit.MoverFaster`
   (`mapinit.lua:48-61`, with the box `AreaCheck`).
5. **Revive gate.** `Team.CanCure` refuses a body with `UsrControl >= 0`
   (`scripts/chars/team.lua:353-356`); `Team.CurePlayer` needs the healer to be player-controlled
   (358-368). A human's downed body must be set to `UsrControl = -1` while it is being revived.
6. **Spirit view.** `AstralCamera.Start(owner, ChangeActionSet, OnlyOrbit)`
   (`scripts/chars/astralcamera.lua:125-176`) creates the astral camera on demand
   (`InitAstralCam`, 5-15). It is a single entity on viewport 0 in vanilla; per-client use is part
   of the Tier 2 spirit work, not repeated here.
7. **Radio beats.** Existing categories and keys through `TeamTalk.RadioTalk*`; anything else is a
   subtitle (`Scorer.SetMsgText` with new localized strings).

---

## 2. G4 — wwii_pillboxes: Path of Souls and Rawlings "killed" by Delgado

### 2.1 What the vanilla scripts do

1. `trigActivateBaddies` (-14566, 269, 3450) → `MapCallbacks.trigActivateBaddies_0`
   (`mapcallbacks.lua:166-175`): starts `nazis_final` and switches the three pillboxes' AI on.
   `AreaTrigger49` (`OnAllInside`, mapcallbacks.lua:50-53) closes the door `puerta_trampa`
   (-14574, 328, 3218) behind the squad.
2. When only one pillbox is left, `MapInit.PilboxDeath` (`mapinit.lua:220-233`) makes all three
   usable (`UseFunc = MapInit.PillBoxOnUse`); pillbox use is Cole-only
   (`scripts/chars/wwii_pilbox_a.lua:119`, `UseJustEntity = "Cole"`).
3. `MapInit.PillBoxOnUse` (mapinit.lua:237-247): `Team.ReviveAll()`, **`EnemyGen.Stop("nazis_final", true)`**
   (kills the wave), Cole's cool-use, then `LaunchScenePOS` (249-258) →
   `Scene.PlayFPNNI("Pathofsouls")` (QTE for Cole; definition `mapscenes.lua:3-14`, sequence
   `mapscenes.lua:56-110`; failure → `Scene.ReloadScene`).
4. Chained scene `DelgadokillsRawlings`: at frame 0 Rawlings is put at (-17100, 415, 9112) with
   `Life = 0` (`mapscenes.lua:112-118`).
5. `OnEnd_DelgadokillsRawlings` (mapscenes.lua:120-143) → `MapInit.AfterRawlingKilled`
   (mapinit.lua:126-130): `Team.SuspendAdviceRevive`, `AreaTriggers.StartSoloMision()`
   (`scripts/missions/areatriggers.lua:161-168`: switch and orders locked, both AI teams on hold),
   then `TestCure`.
6. `MapScenes.SchSetChars` (mapscenes.lua:150-196): closes `puerta_trampa` again, places the
   squad around (-17178..-17470, 405, 8853..9246), Rawlings in `Agony`, then
   `MapScenes.DisableAILoop` (145-148), which calls `MapInit.DisableAllSquad`
   (mapinit.lua:352-365) every 0.1 s: **all AI off and all bodies vulnerable**.
7. `MapInit.TestCure` (mapinit.lua:136-147) polls until Rawlings' `Life > 0` (hint
   `Hint_Rawlings_Dead` if the player is more than 250 units away). The player revives him with
   the normal use/heal (`Team.CurePlayer`). Then `AfterRawlingHealed` (260-270) →
   `StartIncidental` (272-326): AI-walked "conflict" chat `Mission_wwii_Pillboxes_Conflict`
   (keys `mission_wwii_pillboxes_conflict0..14`), Lichthammer appears (`BitchAppears`, 429-433;
   entity `Bitch` at (-18328, 1150, 10041)) → `ActivateNaziBitch` (511-522) →
   `RestoreSquad` (470-509, `EndSoloMision`).

Story context: Lichthammer's voice welcomes them to "the path of souls"
(`scene_wwii_pillboxes_bitch0`), Delgado, under her pressure, shoots Rawlings
(`scene_wwii_pillboxes_bitch9..18`), Cole asks whether Ross can bring him back
(`scene_wwii_pillboxes_bitch19`), Ross: "only one way to find out" (`scene_wwii_pillboxes_bitch20`).
Earlier in the level the squad walked through the impaled souls (`AreaTrigger41` at
(-16620, 648, 1687), chat `mission_wwii_pillboxes_souls0`; Jones' `talk_jones_gencom_wwii0/1`
names the "Path of Souls").

Who leaves: **Cole** for ~21 s (QTE inside the pillbox), and **Rawlings** from the shot until the
revive. Nobody leaves the level.

### 2.2 Cole (G4a): the QTE is her own line

Cole does not need a new line: the Path of Souls vision is hers.
- Cole's player plays the QTE alone (scene runs only on Cole's client, as in
  `scenes-catalog.md` #15 option B). Her body stays in the pillbox, invulnerable and pinned.
- Everyone else **keeps fighting `nazis_final`**: do not call `EnemyGen.Stop("nazis_final", true)`
  in `PillBoxOnUse`; stop it when `DelgadokillsRawlings` starts. Spawn points: `Enemy111`
  (-17487, 393, 8838), `Enemy177` (-18020, 414, 7559), `Enemy133` (-16290, 433, 7168)
  (`mapenemies.lua`); infinite, pool 12, 1 at a time (`mapenemiesgroup.lua`).
- Radio while she is under: `talk_cole_using_powertwo4/5` (Cole links to the system) at the
  start, then the others' `talk_*_help_cole*` (e.g. `talk_rawlings_help_cole0`,
  `talk_black_help_cole0`) when enemies close in.
- A QTE failure reloads only the scene (`Scene.ReloadScene`); the fight outside continues.
  If no human holds Cole, the host plays the QTE (owner rule).

### 2.3 Rawlings (G4b), option (b): "Stations of the Path"

**Premise.** Delgado's bullet tears Rawlings' soul out onto Lichthammer's Path of Souls, the
same stream Cole has just seen through the pillbox. The priest has to walk back against the
stream to his own body before Lichthammer takes his soul, while the squad holds the body against
her soldiers. [The "soul torn out" is new story; it fits Jericho's premise that Ross already
lives as a spirit among them.]

**Route (existing areas only).** The soul is placed at the trap door `puerta_trampa`
(-14574, 328, 3218), inside the closed pillbox area, and moves north to the body:

| Station | Place | Beat |
|---|---|---|
| start | `puerta_trampa` (-14574, 328, 3218) / `trigActivateBaddies` (-14566, 269, 3450) | soul wakes; Lichthammer's pull begins |
| 1 | wrecked `PilBox0` (-16728, 391, 5260) | first station (prayer) |
| 2 | wrecked `PilBox1` (-16035, 439, 6940) | second station |
| 3 | wrecked `PilBox2` (-17887, 434, 8239) | third station |
| end | Rawlings' body (-17100, 415, 9112) | soul at the body: revive allowed |

About 6,400 units between the trap door and the body. The wrecked pillboxes stay active as props
after the scenes (`mapscenes.lua:45-47` and `140-142` set them `bActive = true`).
The squad is placed right next to the body, so station 3 and the end are inside the fight.

**Objectives.**
- Soul: reach each station (radius check, ~250 units, the same radius `TestCure` uses) and hold
  a "prayer" there for a few seconds (hold the use button; subtitle prompt). Lichthammer's pull
  pushes the soul back toward her position (-18328, 1150, 10041) if it idles [guess: implement as
  a slow drift of the spirit camera target, cosmetic].
- Squad (the players who go on): defend the body. `nazis_final` is re-armed for this phase
  (section 1, item 1) and may use `IncreaseMaxEnemies` once per station reached, so the pressure
  rises as the soul gets closer ("she is losing him").
- Rite: when the soul reaches the body, any human performs the revive (vanilla `CurePlayer`).
  This is the scripted exception to "only Rawlings revives", taken from the vanilla scene
  (`scene_wwii_pillboxes_bitch20`). The revive is refused until the soul has arrived.

**Ending / reunion.** The revive itself; then the vanilla flow: `AfterRawlingHealed` →
`Mission_wwii_Pillboxes_Conflict` (Rawlings demands Delgado's arrest, `conflict0..6`) →
Lichthammer appears. The new beat leads straight into the existing confrontation, so the
conflict chat now also reads as Rawlings having seen where Lichthammer wanted to send him.

**Voice beats (existing keys).**
| Beat | Keys |
|---|---|
| soul wakes | `talk_rawlings_casualty_rawlings0` / `1` / `2` (radio variant exists; the squad "hears" him) |
| squad reacts | `talk_church_casualty_rawlings0`, `talk_black_casualty_rawlings0`, `talk_cole_casualty_rawlings0`, `talk_jones_help_rawlings0`, `talk_delgado_help_rawlings0` (Delgado's "need help, padre?" — keep for the irony or drop, owner's taste) |
| path named | `talk_jones_gencom_wwii0` / `1` (Path of Souls) |
| stations 1-3 | `talk_rawlings_tactical_flavor0`, `talk_rawlings_tactical_flavor1` (prayers), `talk_rawlings_using_powerone0..2` |
| arrival at body | `talk_rawlings_using_powertwo2` (the "rise" line) |
| revived | `talk_rawlings_revived1` or `talk_rawlings_revived5`, then vanilla `conflict0..14` |
| Lichthammer | `scene_wwii_pillboxes_bitch0` (plain only, play as 2D on the soul's client); `conflict7`/`conflict9` play later in the vanilla chat, so do not reuse them here |

Option (a) for Rawlings' player: take a free body that goes on (Jones is locked for the whole
level in vanilla, `mapinit.lua:7-11`; co-op would unlock him for this) and return to Rawlings at
the revive.

### 2.4 Engineering for G4

- Patch `PillBoxOnUse` to keep `nazis_final` running during the QTE; stop it at
  `OnInit_DelgadokillsRawlings`; re-arm it after `SchSetChars`.
- Replace `DisableAILoop` for co-op: humans keep control; AI bodies hold position
  (`Team.HoldPosMain/Side` as `StartSoloMision` already does) instead of AI-off-and-vulnerable,
  or they die to the wave.
- `StartSoloMision` locks the switch on `UsrEntity(0)` only; in co-op lock nothing, or lock only
  Rawlings (dead) in the radial menu.
- Rawlings' body: `UsrControl = -1` while dead (so `CanCure` accepts it), invulnerable to the wave
  ("Lichthammer wants the soul, not the body" [guess], or the fight becomes a fail state).
- Gate `TestCure` / the revive on a flag `SoulArrived`; stations are radius checks scheduled with
  `Game.AddScheduledFunc` like `TestCure`.
- The soul itself needs the Tier 2 spirit (per-client astral camera with free flight and a leash).
  Fallback without free flight: orbit-only camera on the body (`AstralCamera.Start(.., false,
  true)`) plus three "resist" prompts on a timer, same beats and voice lines.
- `StartIncidental` (mapinit.lua:272-326) AI-walks `UsrEntity(0)`; the multi-human version is a
  scenes topic (scenes-catalog), not repeated here.

### 2.5 Feasibility and checks

- Rating: **medium**. Keeping the wave and gating the revive is easy (Tier 1). The soul route
  depends on the Tier 2 spirit.
- Check in game:
  - the closed `puerta_trampa` and the pillbox wrecks do not block the spirit camera [U];
  - `nazis_final` can be re-armed after `Stop(.., true)`; `Enemy111` spawns almost on top of the
    squad's pose (-17487, 393, 8838), so its spawn point may be blocked by `TestSphere` [U];
  - the AI-walk conflict chat with live humans around.

---

## 3. G5 — wwii_vigil → wwii_vigil_inside: only Cole, Church and Rawlings go in

### 3.1 What the vanilla scripts do

1. wwii_vigil: Jones burns a fuel tank in astral form. `PhysicsObj.FuelTankExplosion`
   (`models/physics/wwii_fueltank/entitydescriptor.lua:44-54`) opens `oVigilExplosion` and
   `oVigilDoor` (both at (-4134, 755, 44630)), kills `granaderos`, stops `nazis_mix_3`, then plays
   `Mission_wwii_Vigil_Bum` (Lt Robertson: the noisy Yanks will bring every German in the area;
   key `mission_wwii_vigil_bum0`) and 5 s later activates `AreaTriggerIncidentalFinal` (29-42).
2. `AreaTriggerIncidentalFinal` (-6016, 426, 44243; `bActive = false` in `mapareatriggers.lua`) →
   `MapCallbacks.AreaTrigger102_0` (`mapcallbacks.lua:9-11`) → chat `Mission_wwii_Vigil_End`:
   Robertson proposes that part of the team goes after Lichthammer while the rest helps the
   commandos draw the guards (`mission_wwii_vigil_end0`); Ross sends Church, Rawlings and Cole and
   keeps the others for the diversionary attack (`mission_wwii_vigil_end1`) → `MapInit.NextLevel`
   (`mapinit.lua:47-49`) → `WWII_Vigil_Inside`. Design note: "Here the team splits up"
   (`mapcallbacks.lua:63-68`).
3. wwii_vigil_inside loads only Cole, Church, Rawlings (`map.lua:9-13`). The spawn table still has
   positions for the other three with `bJones/bDelgado/bBlack = false` (`mapspawnplayers.lua`,
   Id 0: Jones (9005, 600, 20697), Delgado (8828, 580, 21284), Black (9109, 622, 21413)).
4. Inside route (callbacks in `mapcallbacks.lua`): `AreaTrigger59` → `meles_iniciales` (20-22);
   `AreaTrigger62` → `segundo_cultista` (28-30); `AreaTrigger180` → Rawlings `Weird_Sound2` (4-6);
   `AreaTrigger` at (12040, -1188, 13931) → `comite_recepcion` (47-49; on damage → `comite2`,
   89-91); `AreaTrigger34` → `sorpresa` (16-18); `AreaTrigger85` → `explosivos_escalera` (32-34);
   `AreaTrigger61` → `nazis_finales` (24-26); all dead → crypt door `PuertaCripta00` opens and
   checkpoint (93-112); `AreaTriggerIncidentalFinal` → `MapInit.MoverFaster` (36-38);
   `TrigPuertaCripta00` closes the crypt and starts `Mission_wwii_Vigil_Inside_Begin` (79-84);
   `TrigNaziBitch` → boss (73-77). Beaten boss → `PsichicCommander.EndOfBitch`
   (`scripts/chars/psichiccommander.lua:360-373`) → `RawlingsTorture` (QTE, Rawlings) →
   `MapScenes.EndRawlingsTorture` (`mapscenes.lua:32-35`) → `NewLevelNow("WWII_Brandenburg")`.
5. At the end of the torture scene Rawlings sends Church back to the others to help with the
   diversion and says he will carry the prisoner to the gate (`scene_wwii_vigil_inside_nazi14`).
   Design note `Tag_99` (`mapcallbacks.lua:69-71`) says the same: Rawlings and Cole bring the
   Nazi bitch to the Brandenburg gate, Church joins the rest of the team.

So the vanilla story already gives Jones, Delgado and Black a job: **the diversionary attack**
with the Black Watch commandos. It is just never shown.

### 3.2 Can the outside group play in wwii_vigil areas?

Only as a **second, simultaneous session** (Tier 3). wwii_vigil and wwii_vigil_inside are separate
levels with unrelated coordinates (the vigil end trigger is at (-6016, 426, 44243), the vigil_inside
start at (9000, 600, 20700)), and a level holds one simulation. Inside vigil_inside the only
"outside-like" space is its entrance corridor, which is a fallback (3.4).

### 3.3 Main proposal (Tier 3): "The Diversion" in wwii_vigil

**Premise.** As Ross ordered, Jones, Delgado and Black stay with Major Buckland's Black Watch at
the front of the Vigil and make enough noise to keep the garrison off the three infiltrators. They
must hold the breached courtyard until Rawlings has what he needs from Lichthammer, then fall back
to the Brandenburg road.

**Route (existing wwii_vigil areas).**
- Arena: the courtyard in front of and through the breach. AreaManager sectors `Trigger13`
  (1858, 448, 42742), `Trigger14`-`Trigger18` (3590 → -1358, 448, 42742..44800), `Trigger21`
  (-5938, 448, 44632), `AreaTeam348` (-4543, 899, 44447); the three boxes of `AreaTrigger132`
  cover the same yard (`mapareatriggers.lua:58-66`).
- Regroup / respawn point: checkpoint Id 1 of the level (all six around (2000, 30, 42700), with the
  British moved by `MapInit.PutBritishInPlace`, `mapinit.lua:23-34`).
- Hold point: the breach `oVigilExplosion` / `oVigilDoor` (-4134, 755, 44630) and the box of
  `AreaTriggerIncidentalFinal` behind it, the way the infiltrators went in.

**Objectives (beats tied to the inside team's progress).**
| # | Trigger (inside team, vigil_inside) | Outside beat (wwii_vigil) | Reused enemies |
|---|---|---|---|
| 1 | split (vigil end chat finishes) | "Make noise": clear the yard and the two towers | re-arm `nazis_mix_3` (courtyard spawns `Enemy180` (-1733, 363, 43579), `Enemy125` (-2136, 286, 44272), `Enemy293` (-1690, 404, 45147), `Enemy237` (-212, 239, 44262); finite, pool 6) and `granaderos` on the towers `Enemy98` (-4357, 1289, 43081), `Enemy137` (-4355, 1289, 46399) (infinite) — Black's long shots fit here |
| 2 | inside reaches the crypt door (`nazis_finales` dead, `mapcallbacks.lua:103-112`) | "The garrison comes back": hold the breach | re-arm `nazis_mix_2` (spawns from the outer works `Enemy252` (3293, 165, 40088), `Enemy196`, `Enemy99`, `Enemy139`; finite, pool 10) and keep `granaderos` |
| 3 | boss fight starts (`TrigNaziBitch_0`) | last stand at the breach | `granaderos` with `IncreaseMaxEnemies` once; `British_Group` (Buckland, Barndon) fights alongside |
| 4 | `EndRawlingsTorture` | "Fall back": stop all generators, walk to the breach box, load Brandenburg | — |

The outside hold has no fixed end; it ends on the inside team's signal, so the outside group can
never finish first and wait.

**Ending / reunion.** Both sessions load wwii_brandenburg and merge. Vanilla spawn Id 0 already
puts everyone at the start ((-24112, 664, 79257), `mapspawnplayers.lua`), and the design note
there reads "Here the player joins rest of the team" (`wwii_brandenburg/mapcallbacks.lua:71-78`):
Church rejoins Jones, Delgado and Black; Cole and Rawlings go to the gate top (G6).
Reunion lines: `talk_church_rejoin_team0..2`, `talk_jones_rejoin_team0..2`,
`talk_black_rejoin_team2` ("good walk?"), `talk_delgado_rejoin_team4`.

**Voice beats (existing keys).**
| Beat | Keys |
|---|---|
| opener | `mission_wwii_vigil_bum0` already plays before the split in vanilla; for the outside group repeat it only as subtitle, or use `talk_barndon_tactical_flavorc1` (hold position) and `talk_buckland_enemy_quiet1` |
| making noise | `talk_delgado_gencom_wwii0/1` (suicide missions), `talk_black_tactical_flavorc6` (I take the far targets), `talk_jones_tactical_flavorc1/2` (flanks, rear), `talk_black_tactical_flavorc7` (hold them) |
| towers | `talk_*_view_enemyhigh*` (e.g. `talk_barndon_view_enemyhigh0`), hint keys of the level are not needed |
| news from inside | radio from the inside team relayed to the outside session: `talk_church_help_omega*`, `talk_rawlings_help_omega*`, `talk_cole_help_cole0/1`, `talk_cole_gencom_wwii5` (Lichthammer has locked herself to the breach) when the boss starts |
| waiting | `talk_delgado_idle_impatient2..5`, `talk_jones_idle_impatient0/1` |
| fall back | subtitle; `talk_jones_rejoin_team1` ("fall in") |

**Option (a)** for these players: take a free inside body (Cole, Church or Rawlings not held by
another human). With 4 humans at least one must stay out (vigil_inside has 3 bodies), so option
(b) is the natural seat for the 4th player.

### 3.4 Fallback (Tier 1): "The Vigil's mouth" inside vigil_inside

If Tier 3 is not built: load Jones, Delgado and Black into vigil_inside at their unused spawn
positions (3.1 item 3) and give them the entrance: the corridor sectors `S_13` (8981, 368, 20803)
→ `S_14` → `S_15` → `S_16` (8981, 368, 17255) and `S_10` (9071, 120, 15999). Premise: the
diversion moved to the Vigil's gate; they keep the garrison from following the three down.
- Problem: every vigil_inside spawn point lies on the inside team's own route (`meles_iniciales`
  at (8670..9290, 136..146, 16400) is the only group near the entrance, 2 cultists, not a
  generator). A sustained hold needs **new spawn coordinates** for existing classes (e.g.
  `CultistaMelee` emerging from flies, the way `PsichicCommander.OnCreateNewEntity` spawns them,
  `psichiccommander.lua:290-294`), which the brief excludes unless the owner agrees.
- Also needs `init.Team` widened to six (`map.lua:9-13`) and the spawn flags on; memory and
  model loading for six squad members in this level are [U].
- Reunion: when the crypt door closes (`TrigPuertaCripta00`), or simply at the brandenburg start.

### 3.5 Engineering for G5

- Tier 3 core: split the co-op session at `MapInit.NextLevel` (vigil) into two sessions, one host
  per group (one client becomes the authority for wwii_vigil), keep a message channel between the
  hosts (inside progress events → outside beats; inside radio → outside radio), and merge both at
  the load of wwii_brandenburg (`EndRawlingsTorture` must wait for the outside host's
  acknowledgement before `NewLevelNow`).
- Outside level state at the split: the yard is cleared, `granaderos` were killed and
  `nazis_mix_3` stopped by the explosion (entitydescriptor.lua:50-51), so every group must be
  re-armed (section 1, item 1). `nazis_mix_2` and `nazis_mix_3` are finite; if their pools are
  spent, only `granaderos` (infinite) remains [U how much pool is left in a typical run].
- `AreaTriggerIncidentalFinal` and the vigil end chat must not fire again in the outside session
  (it would load vigil_inside).
- Save: checkpoint only at the merge (brandenburg). A disconnect of either host during the split
  ends the split for that group (fallback: the remaining players continue as spirits).
- Testing needs two game instances; the owner's machine froze with two D3D instances, so test
  with one instance plus a headless bot or a second machine (memory: no dual D3D instances).

### 3.6 Feasibility and checks

- Tier 3 "The Diversion": **hard** (second authority, session split and merge; content itself is
  simple).
- Tier 1 fallback "The Vigil's mouth": **medium**, blocked on the new-coordinates question.
- Without either: the G5 proposal in `coop-story-extensions.md` (4th player as a spirit inside)
  stays the default.
- Check in game: whether the towers survive the wall explosion and `granaderos` can respawn there
  [U]; whether the British NPCs still fight after the vigil end chat [U]; pathing of `nazis_mix_2`
  spawns into the yard after the breach [U].

---

## 4. G6 — wwii_brandenburg: Church climbs alone; Cole and Rawlings hidden near the prisoner

### 4.1 What the vanilla scripts do

1. Start: spawn Id 0, controlled character Jones (`Init 0`), everyone near (-24112, 664, 79257)
   (`mapspawnplayers.lua`).
2. `MapInit.Init` (`mapinit.lua:38-59`, scheduled from `main`): Cole and Rawlings are moved to the
   top of the gate ((-23505, 533, 66981) and (-23646, 533, 66995)), `bActive = false`, AI off,
   `CannotSpeak`; `Team.UnavaliablePlayers = {Rawlings, Cole}`; the prisoner `Bitchie`
   (PsichicCommander) is placed at (-23563, 532, 66948), no burn, no astral projection.
3. Fight to the gate: `AreaTrigger192` → `primera_oleada` (`mapcallbacks.lua:27-29`), stopped by
   `AreaTrigger` (59-61); `AreaTrigger161` → `explosivos`, `segunda_oleada`, `segunda_oleada_b`
   (12-16), stopped by `AreaTrigger363` / `AreaTrigger215` (48-50, 35-37); both groups dead →
   door `o53` (-21801, -744, 75713) opens, checkpoint (95-114).
4. `TriggerEntradaPuerta` (-22035, -740, 75700) → `AreaTrigger158_0` (4-10): `GroupFlamethrowers`
   (`FlamethrowerA` (-22838, -495, 71791), `FlamethrowerB` (-24132, -495, 71809)), `granaderos`
   on the parapets (`Enemy166` (-22142, -5, 70901), `Enemy228` (-24968, -5, 70861); infinite),
   astral puzzle on. Jones burns `oFuelTankA` (-22747, -362, 70515) behind the wall; the
   explosion opens `oBranderburgoExplosion`/`oBranderburgoDoor` (-23467, -543, 71222), **kills
   `granaderos` and blows up both flamethrowers**
   (`models/physics/wwii_fueltank/entitydescriptor.lua:55-77`).
5. `AreaTrigger210` (-23453, -1083, 70714) → `MapInit.ShowRawlingsCole` (`mapinit.lua:72-86`,
   `EnsureRawlingsCole` 88-116): both become visible props in the `NaziSacrifice` hold pose,
   invulnerable, removed from the AI team. `AreaTrigger217` (-23535, -1019, 69610) → radio
   `Mission_wwii_Brandenburg_Begin` (Rawlings: Billy, meet us at the top of the gate,
   `mission_wwii_brandenburg_begin0`) and repeating hints `hint_rawlings_78_l2_climb_gate`,
   `hint_rawlings_79_l2_climb_gate` (`mapinit.lua:272-287`).
6. Church only: `triggerNaziSacrifice` (-25629, -782, 66564) with `AreaTriggers.IsPlayer(.., "Church")`
   (`mapcallbacks.lua:18-25`) or the use object `triggerUseChurch` (-25169, -726, 66493,
   `UseJustEntity = "Church"`, `mapphysiclogic.lua:8-49`, callback `mapcallbacks.lua:125-129`) →
   `HideRawlingsCole` (`mapinit.lua:118-122`) → scenes `NaziSacrificeA` → `NaziSacrificeB`
   (`mapscenes.lua:28-59`; Cole and Rawlings are scene actors). There is **no climbing
   gameplay**: the trigger is at ground level and the climb is the scene.
7. `StartEndScene` (124-130) → `ReposPeople` (228-270): all six placed near the breach
   (-23540, -684, 67424), AI walk, `Breech.Play("WWII_bis", 1)` → `OnChurchArrived` (196-202)
   → `Mission_wwii_Brandenburg_End` (Buckland's farewell, `mission_wwii_brandenburg_end0..8`)
   → `EndOfTalk` / `GoToBreech` / `EndOfMap` (173-194) → `Cru_River`.
8. Design notes: `tag_00_0` / `ttttt_0` (`mapcallbacks.lua:116-123`, 131-137): Rawlings and Cole
   have the Nazi bitch on top of the monument; Church climbs and cuts her throat.

Who leaves: **Cole and Rawlings for the whole level** (hidden, then props). Jones, Delgado and
Black are only "left below" for the ~43 s of the two scenes.

Correction to the G6 row in `coop-story-extensions.md`: "players below defend the base against
`primera_oleada` / `segunda_oleada` while Church climbs" does not work as written. There is no
climb window to defend (item 6), and those groups spawn at z 77,000-85,000, 10-18k units from the
gate; by the sacrifice they are spent (finite pools). The below group needs nothing new; Cole and
Rawlings do.

### 4.2 Cole and Rawlings, option (b): "The Gate Top"

**Premise.** Rawlings and Cole carried the captive Lichthammer from the Vigil to the top of the
Brandenburg gate, as Rawlings said they would (`scene_wwii_vigil_inside_nazi14`). The blood that
opens the breach must be shed up there, so they have to keep her bound until Church arrives.
Lichthammer fights back with her mind and calls her followers; from the top, the two also cover
the squad fighting its way to the gate.

**Place (existing positions).** Their own staged positions: Cole (-23505, 533, 66981), Rawlings
(-23646, 533, 66995), prisoner `Bitchie` (-23563, 532, 66948). The script already puts them on the
floor there (`Game.SetOnFloor`, `mapinit.lua:93-94`). From the gate top:
- the parapet grenadiers `Enemy166`/`Enemy228` are about 4,200 units away and 540 lower, on the
  gate side of the wall;
- the flamethrowers are about 4,800 units away;
- the approach after the breach (`AreaTrigger210`/`217`, z 70714 → 69610) is 2,700-3,700 away.

**Phases and objectives.**
| Phase | From → to (existing triggers) | Cole and Rawlings | Reused content |
|---|---|---|---|
| 1. Bound | level start → `TriggerEntradaPuerta` | Keep Lichthammer bound: one of the two must "hold" her (use on `Bitchie` → locked in the `NaziSacrifice` pose, as in `EnsureRawlingsCole`); the other is free. If nobody holds her for a few seconds, she calls followers | her summon: `CultistaMelee` emerging from flies at the gate top, through `PsichicCommander.OnCreateNewEntity` (`psichiccommander.lua:290-294`) — see 4.3 on whether this counts as new placement |
| 2. Overwatch | `TriggerEntradaPuerta` → fuel tank explosion | The free one shoots the parapet grenadiers and the flamethrowers from behind; the holder keeps her bound | `granaderos`, `GroupFlamethrowers` (already started by vanilla `AreaTrigger158_0`) |
| 3. Call Church | `AreaTrigger210` → `AreaTrigger217` → sacrifice | Hold her together; Rawlings' radio calls Church (vanilla beat) | vanilla `ShowRawlingsCole` becomes a no-op (they are already there) |
| 4. Sacrifice | `triggerNaziSacrifice` | Scene: their players watch from their actors' cameras (`NaziSacrificeB` has Cole and Rawlings as actors) | vanilla scenes |

The phase 2 role is strong because the vanilla explosion kills the grenadiers and flamethrowers
(4.1 item 4): every grenadier Cole or Rawlings drops before Jones finds the tank is a real help to
the group below.

**Ending / reunion.** Vanilla: `NaziSacrificeB` (Church with Cole and Rawlings at the top), then
`ReposPeople` puts all six together at the breach and Buckland's farewell plays. No new reunion is
needed. Optional subtitle at `ReposPeople`: the squad complete again.

**Voice beats (existing keys).**
| Beat | Keys |
|---|---|
| level start (top) | `talk_cole_gencom_wwii2` (something unusual in Lichthammer), `talk_cole_gencom_wwii5` (she has locked herself to the breach), `talk_rawlings_gencom_wwii5` (finally closing the file on her) |
| holding her | `talk_rawlings_tactical_flavor0/1` (prayers), `talk_rawlings_using_powerone0..2` |
| she struggles | `hint_rawlings_79_l2_climb_gate` (cannot hold Lichthammer much longer; vanilla hint, radio variant exists), `talk_cole_weird_sound2` (psi surge) |
| summon arrives | `talk_cole_view_enemyclose*`, `talk_rawlings_enemy_ambush*`, `talk_cole_help_cole0/1` |
| overwatch | `talk_cole_view_enemylow*`, `talk_rawlings_view_enemylow*`, `talk_cole_view_enemyfar0`, `talk_cole_spot_team0/1` (Alpha / Omega in sight), `talk_rawlings_help_church0` |
| calling Church | vanilla `mission_wwii_brandenburg_begin0`, `hint_rawlings_78_l2_climb_gate` |
| below hears them | `talk_jones_view_enemyhigh*` / `talk_barndon_view_enemyhigh0` are about enemies; for the duo use subtitles ("Cole and Rawlings on the gate") |

**Option (a)** for these players: take a free body below (Jones, Delgado or Black when not held;
with 4 humans and 6 bodies two are always AI) for phases 1-2, and return to Cole or Rawlings at
`AreaTrigger210` (the vanilla moment they appear), with the normal soul-flight switch.

### 4.3 Engineering for G6

- `MapInit.Init`: for a human-held Cole or Rawlings, keep the body active and controllable on the
  gate top (no `bActive = false`, no `CannotSpeak`, remove them from `UnavaliablePlayers` for
  their own holder only), collision on.
- Leash: teleport back to the anchor if a body leaves the gate top radius (pattern of
  `MoverFaster`), so a fall cannot strand them.
- Hold mechanic: give `Bitchie` a `UseFunc` (entities already take one: `Team.AssignReviveFunction`,
  `team.lua:337-341`) that toggles the holder between free and `ForceAction = "NaziSacrifice"`
  (the move exists for Cole, Rawlings and PsichicCommander, `mapinit.lua:8,15,17`).
- Summon: either `PsichicCommander.OnCreateNewEntity` at gate-top coordinates or a new spawn row
  (both are "existing class at a new coordinate", see open question 2). `CultistaMelee` is not in
  brandenburg's `init.Enemies` (`map.lua`), only `init.MeleeCultistType` is set [U whether the
  class is loaded]; `CultistaExplosivo` is loaded and can replace it.
- `ShowRawlingsCole` / `EnsureRawlingsCole` / `HideRawlingsCole` must leave human bodies alone
  until the scene starts, then hide them for the scene as vanilla does.
- Church gate: `IsPlayer(.., "Church")` and `UseJustEntity = "Church"` must accept any human
  holding Church (general rule, `campaign-structure.md` 5.2 item 4).
- `ReposPeople` sets `IgnoreUsrControl` on `UsrEntity(0)` only and AI-walks the rest; the
  multi-human version is a scenes topic.

### 4.4 Feasibility and checks

- Rating: **medium**.
- Check in game:
  - the gate top has walkable floor and room for two characters and the prisoner [U] (the
    script only proves a floor directly under the two pose points);
  - line of sight and draw distance from the top to the parapets and the flamethrowers [U];
  - the granaderos' AI can target players on the gate top and is not too punishing [U];
  - the `NaziSacrifice` hold pose can be entered and left repeatedly without breaking the scene
    that uses the same move later [U].

---

## 5. Other separations in these levels

None of these needs a full own-body line; listed so the per-level work does not miss them.

| Level | What | Script | Co-op note |
|---|---|---|---|
| wwii_biggates | Jones, Cole, Rawlings locked the whole level | `mapinit.lua:2-8` | lock, not a split; lobby picks must avoid them or unlock them |
| wwii_biggates | Church-only blood-ward gate | `MapInit.TestWard`, `mapinit.lua:100-113` | gate by "any human holding Church" |
| wwii_biggates | Cole hacks the exit door by AI walk | `MapInit.OpenTheColeDoor` / `ColeHackDoor`, `mapinit.lua:139-146` (from `mapcallbacks.lua:42`) | a human Cole must be walked or asked to use the door |
| wwii_pillboxes | Jones locked the whole level; Jones set `Life = 0` for the ghost-heal tutorial | `mapinit.lua:7-11`, `KillSomeone` 605-613 | a human Jones is "down" for a few seconds until Rawlings heals him (fits the owner's revive rule); `CanCure` needs `UsrControl = -1` on him [U for ghost heal] |
| wwii_pillboxes | Rawlings-only gate for `bigFuckerGroup` | `ActivateBigFuckerGroup`, `mapinit.lua:615-623` | gate by "any human holding Rawlings" |
| wwii_pillboxes | British commandos chase Lichthammer off; door opens | `psichiccommander.lua:380-422` | no split |
| wwii_mosque | Jones-only astral TK lever `o175` | `MapInit.TestJones`, `mapinit.lua:60-85` | Jones' body stays put while his spirit works; the others can be asked to guard it (natural mini-hold, reuse whatever the level spawns there) [I] |
| wwii_mosque_inside | Tuck killed; Black's ghost bullet must hit the British bomb | `ArriveTaliban` `mapinit.lua:64-75`, `BlackTrickShoot` 97-127 | Black-only objective; no split |
| wwii_vigil | Jones-only astral burn of the fuel tank | fuel tank descriptor, `entitydescriptor.lua:23-27` | same as the mosque lever |
| wwii_vigil_inside | `RawlingsTorture` QTE (Rawlings), Church and Cole watch | `mapscenes.lua:18-35` | QTE for Rawlings' holder; Cole and Church watch from their actors |
| wwii_brandenburg | Jones-only astral burn of the fuel tank; final AI walk | `mapcallbacks.lua:4-10`, `mapinit.lua:228-270` | no split |

---

## 6. Open questions for the owner

1. The story lines re-run existing enemy groups (`nazis_final`, `nazis_mix_2/3`, `granaderos`).
   This is new content, not difficulty scaling. Is that compatible with "no extra enemies"?
2. G5 fallback and the G6 summon need existing enemy classes at **new coordinates** (data only, no
   geometry). Allowed?
3. G5: build Tier 3 "The Diversion" (two sessions, merge at Brandenburg), or keep the spirit
   default for vigil_inside and skip the outside line?
4. G4: is a "torn-out soul" for Rawlings acceptable in the story, given the vanilla line only has
   Ross reviving him?

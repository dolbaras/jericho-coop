# Ally animations: what every squad body can play and what the mod shows of it

Written 2026-10-28 for the 0.2.8 bug "not all ally animations are synced" (owner's Steam session: wounded
squad members stand instead of falling, Delgado's arm opening when he releases the dragon is not seen,
other characters' animations missing). Companion code: `lua/coop_anim.lua` (first slice), tests
`lua/tests/anim_mock_test.lua`, lab `lab\animtest.sh`. The list of actions below is exact: it comes from
running the game's own character scripts (`work\src\scripts\chars`, plus the level scripts' extra
actions) against a recording mock of the Act API (`lab\actinv.lua`, output `work\notes\actinv.txt`:
action, animation file, loop, UseDisp, priority, events with their functions).

There are seven playable classes: Ross (Act 1 only), Cole, Delgado, Church, Black, Jones, Rawlings. There is
no Paulsen in the scripts. `british.lua` is the NPC British soldiers (they have Agony too, no co-op role).

## 1. What a puppet is driven by today

`Coop.drivePuppets` (`coop.lua`) places and walks a body that another machine owns (on the host: bodies
the clients hold; on a client: every squad body but its own): movement inputs (`InCtrl_Walk/Str/Sprint`),
the shot flag (`owc.Shot`), the weapon slot (`Coop.syncSlot`), crouch (`Coop.syncCrouch`: plays the
owner's `Duck*` action), and `Coop.mirrorArms`, which plays one third-person action when the owner's
first-person arms start `Combo<a>Hit<b>`, `Punch*`, `Reload*`, `Spell*`, `Hack*`, `Special_0Init/0/0End`
(`Coop.ARM_ACTIONS`, `Coop.ARM_BY_CHAR`: Black's `Special*` -> `TKHit`). The state field `st.action` (the
owner's `e.Action`, 20 Hz) was otherwise ignored. Bodies of the host's AI have no first-person arms: their
reloads, punches and hit reactions were never shown on clients. `CoopTeam.syncPuppetLife` only set `Life = 0`
for a downed owner: the engine plays a death only on a killing hit (it calls the class's `OnDeath`), so the
puppet kept standing (to be confirmed by the live check in section 3). Other players' first-person
animations are deliberately dropped at `MakeFP.LaunchFpsAnm` (`coop_world.lua:installFPAnm`): a
first-person animation only exists on its own player's arms.

## 2. Classification

**Locomotion (ignore: the inputs, `UseDisp` and `Coop.syncCrouch` do them)**: `Relax*`, `Walk*`, `Run*`,
`Sprint*`, `Back*`, `StrLeft/Right*`, `Turn*`/`Turn90*`/`Turn180`/`DuckTurn*`, `*ViewLeft/Right/Rear*`,
`RelaxLeft/Right`, `Duck*` movement, `Facial_*`, the shooting loops `Shot*`/`DuckShot*` (the `owc.Shot`
flag), `Shelter*` (cover, see state). The AI squad also toggles crouch and cover through events on these
(`AIMemberSquad.DoCrouchAnmEvent`, `DoNotCrouchAnmEvent`, `EnableAI` on `TurnSprint`): not touched.

**One-shot (mirror once, when the owner's action becomes one of them)** and how each is triggered on the host
(exact function):

| Action(s) | Classes | Triggered by |
|---|---|---|
| `Hit`, `HitDuck` | all but Ross | `Soldier.CharDamage` (`soldier.lua:83`): `ent.Action = ent.WeaponSufix.."Hit"` when the body is AI-held (`UsrControl == -1`) and not walking; class `OnDamage` entries (`Delgado.CharDamage`...) call it. Players get a red fade instead: the animation is for AI bodies |
| `HitStrong` | all | `Soldier.DoHitStrong` (`soldier.lua:17`), strong hits, local user only; its events clear the AI crouch/helper state |
| `FriendlyFire`, `DuckFriendlyFire` | all but Ross | engine/AI friendly-fire reaction (sound hooks in `sound\*sound.lua`) |
| `Punch`, `DuckPunch` | all | `Soldier.OnPunch` (`soldier.lua:8`), `AIMemberSquad` (`aimembersquad.lua:482-484`), the melee key |
| `Reload`, `Reload0`, `DuckReload`, `DuckReload0`, `ReloadE`, `DuckReloadE`, `Shelter*Reload*` | all (E: Rawlings) | the weapon control's reload (`Weapons.ReloadMenu` for the player, the AI's own for squad members); events `!AnmSetAction`, `TeamTalk.Reload` bark |
| `Reequip`, `DuckReequip` | Cole | `Team.Reequip` / `Team.SoftReequip` (`team.lua:1451`), event `Team.SetMaxAmmo` |
| `Hack` | Cole | Cole's hack use (`levels/wwii_biggates/scripts/mapinit.lua:144`, the console hack); first-person set `fp_cole.lua` `Hack` |
| `Spell` | Church | `Church.PressSpecial` (`church.lua:660`), event `Church.LoseLifeCutting` |
| `TKHit`, `TKHitDuck` | Black | Black's telekinesis (events `Black.UseTelePower`, `Black.DoTelekinesisPowerFX`); level scripts use `char.Action = "TKHit"` for the door hacks (alk_city, alk_desert, alk_tomb) |
| `Special1`, `DuckSpecial1` | Rawlings | Vlad's Course, event `WeaponsRawlings.OnDoVladsCourse` |
| `ShotH`, `DuckShotH`, `ShotH_GH`, `DuckShotH_GH` | Rawlings | the heal shot (`WeaponsRawlings.OnShotHeal`), ghost heal (`Rawlings.GhostHealShot`) |
| `Shot0` (grenade) | Cole | event `WeaponsCole.LaunchGrenade` |
| `Shot1Init`, `DuckShot1Init`, `Shot1EndAlt` | Delgado | the dragon: events `Ababanili.AbabaniliStart` (frame 40), `Ababanili.ChangeToMinigun`; the first-person arms are `Special_To/0Init/Relax` (`delgado.lua:871-934`). `coop_powers.lua` (`abby`) carries the dragon itself |
| `NaziSacrifice` | Cole, Rawlings | wwii_brandenburg `mapinit.lua:8,15,99,106` (scene helper actions) |
| `BrokenWall` | Delgado | sum_ziggurat_03 `mapinit.lua:5,27` |
| `KO`, `KOEnd` | Black | sum_ziggurat_02 `mapinit.lua:5-6` |

**State (a body stays in it; needs a begin and an end, or the life)**:

| State | Actions | Triggered / left by |
|---|---|---|
| Downed | `AgonyInit` -> `Agony`/`Agony2` loop (variant chosen at random in `Soldier.OnDeath`, `soldier.lua:46`) | the engine calls the class's `OnDeath` (`Soldier.AddAgonyAnm`, `soldier.lua:29`) when a hit kills it; `Soldier.OnDeath` sets `Action`/`DefLoop`, powers off, `Team.AssignReviveFunction` (usable by Rawlings: `Team.OnUseDeathPlayer`) |
| Revive | `AgonyEnd` / `Agony2End` | `Team.RevivePlayer` (`team.lua:370`; `Team.CanCure` only for AI-held bodies and Ross); the End action's event `Soldier.Revive` gives the life back, `AIMemberSquad.OnRevive`, bark "Revived" |
| Agony loop end | | event `Soldier.CheckRevive` at the end of the loop (a living body is set to 0 and gets the End) |
| Crouch | `DuckRelax*`, `DuckRelaxInit/End` | input; `Coop.syncCrouch` (done) |
| Cover | `Shelter{Down,Left,Right}{Init,End,Set}`, `Sprint/WalkShelter*` | AI (`aimembersquad.lua:950-954` ends it), the player's cover key |
| Dazed | `StupidInit/Stupid/StupidEnd` (Delgado, Church, Black, Rawlings) | `EvilFirstBorn` (`evilfirstborn.lua:296`) for the squad bodies; `MakeChar.DazedChars` |
| Trance | `TranceInit/Trance/TranceEnd` (Jones) | `Jones.PressSpecial` (`jones.lua:642`) astral projection |
| Astral | `AstralInit/Astral/AstralEnd` (Ross) | Ross's soul power (Act 1) |
| Possessed | `PossessedInit/Possessed/PossessedEnd` (Jones, sum_ziggurat_01) | level script `EJones.ForceAction = "PossessedInit"` (`mapinit.lua:132`, end 229) |

First-person only (no third-person action): `Special_To`, `Special_Relax`, `TKON/TKOFF`, `TKLoopON/OFF`,
`LEDLoopON/OFF` and the weapon sets' `<set>_*` actions (`fp_*.lua`, `MakeFP`): other players' ones are dropped
on purpose; what other players should see is the third-person action in the tables above.

## 3. First slice (`lua/coop_anim.lua`, called from `Coop.drivePuppets` and `CoopTeam.syncPuppetLife`)

- **Downed puppet falls**: when the owner's life is 0 and the puppet's `Life` is 0 but its action is not an
  Agony one, `CoopAnim.putDown` does what `Soldier.OnDeath` does (`AgonyInit`/`Agony2Init` of the owner's
  variant from `st.action`, `DefLoop`, powers off, revive function), at most every 0.5 s.
- **Revive**: `CoopAnim.revive` calls `Team.RevivePlayer` once per revive (before, every frame: it ran
  while the owner's life was back and the puppet's was not, restarting the End action and switching Agony to
  `Agony2End` from the second frame). The engine's `Soldier.Revive` gives the life back; after 4 s without it
  the owner's life is set.
- **One-shot mirror**: `A.ONESHOT` (the rows above) is played once, through `ForceAction`, when `st.action`
  of the owner's body becomes one of them and the class has it; not within 0.6 s of `Coop.mirrorArms`'s own
  play of the same strike/reload. Actions that are neither locomotion nor known are logged once per body
  (`anim: <Body>:<Action> seen on the owner's body, not mirrored`): the list for the next slices.
- Switches: `cfg.animmirror = false` (no one-shots), `cfg.animlog = true` (log everything).

## 4. Still open (next slices)

- States other than downed: cover (`Shelter*`), dazed (`Stupid*`), Jones's trance and Ross's astral (these
  run on the owner's body for seconds and need begin/end), possessed Jones in sum_ziggurat_01.
- Delgado's dragon release: third-person `Shot1Init` on the puppet would run the `AbabaniliStart` event
  (frame 40) there and start a second dragon next to the `abby` one: needs the event guarded on puppets
  before the action is mirrored. The first-person arm opening itself cannot be shown on another body.
- Hit reactions of the host's AI bodies are in the whitelist now; check that `Hit` on a walking puppet does
  not stop its walk (the body keeps its inputs).
- Grenade throw (`Shot0` of Cole) is a shot loop here (`owc.Shot`); its launch event runs on the puppet and
  makes a grenade there: check with a live test before mirroring it as an action.
- Verification of every class on a live pair (action by action) once the whitelist is settled.

## Appendix: every action (generated by `labctinv.lua`, 2026-10-28)

Counts: Ross 112, Cole 117, Delgado 128, Church 118, Black 126, Jones 128, Rawlings 147. In all seven classes (79):

`Agony` `AgonyInit` `AgonyEnd` `Agony2` `Agony2Init` `Agony2End` `HitStrong` `Relax` `Relax0` `Relax1` `Relax2` `TurnLeft` `TurnRight` `DuckRelaxEnd` `DuckRelaxInit` `DuckRelaxViewLeft0` `DuckRelaxViewLeft1` `DuckRelaxViewRight0` `DuckRelaxViewRight1` `RelaxViewLeft1` `RelaxViewRear` `RelaxViewRight1` `Sprint` `Walk` `Back` `StrLeft` `StrRight` `Run` `SprintDuckInit` `RunDuckInit` `WalkDuckInit` `SprintInit` `BackInit` `RunInit` `WalkInit` `SprintDuckEnd` `RunDuckEnd` `WalkDuckEnd` `SprintEnd` `BackEnd` `RunEnd` `WalkEnd` `BackDuckInit` `StrLeftDuckInit` `StrRightDuckInit` `WalkViewLeft0` `WalkViewRear` `WalkViewRight0` `DuckRelax` `DuckRelax0` `DuckTurnLeft` `DuckTurnRight` `TurnSprint` `Shot` `DuckShot` `RelaxLeft` `RelaxRight` `DuckRelaxLeft` `DuckRelaxRight` `Turn180` `Turn90Left` `Turn90Right` `DuckTurn180` `DuckTurn90Left` `DuckTurn90Right` `ShelterDownEnd` `ShelterDownInit` `ShelterDown` `SprintShelterDown` `ShelterLeftEnd` `ShelterLeftInit` `ShelterLeft` `ShelterLeftSet` `SprintShelterLeft` `ShelterRightEnd` `ShelterRightInit` `ShelterRight` `ShelterRightSet` `SprintShelterRight`


**Ross only/partial** (33): `AstralInit` `Astral` `AstralEnd` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `WalkViewLeft1` `WalkViewRight1` `Reload` `Reload0` `DuckReload` `DuckReload0` `ShotInit` `Shot0` `ShotEnd` `DuckShotInit` `DuckShot0` `DuckShotEnd` `DuckPunch` `Punch` `ShelterDownReload` `ShelterDownReload0` `ShelterLeftReload` `ShelterLeftReload0` `ShelterRightReload` `ShelterRightReload0` `ShelterRightAbort` `ShelterLeftAbort`


**Cole only/partial** (38): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft0` `RelaxViewRight0` `Hack` `Reequip` `DuckReequip` `WalkViewLeft1` `WalkViewRight1` `DuckRelax1` `DuckRelax2` `ShotInit` `Shot0` `ShotEnd` `DuckShotInit` `DuckShot0` `DuckShotEnd` `Punch` `DuckPunch` `Reload` `DuckReload` `ShelterDownReload` `ShelterLeftReload` `ShelterRightReload` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`


**Delgado only/partial** (49): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `StupidInit` `Stupid` `StupidEnd` `DuckRelax1` `DuckRelax2` `Reload0` `DuckReload0` `Shot1EndAlt` `ShotInit` `ShotEnd` `Shot0Init` `Shot0` `Shot0End` `Shot1Init` `Shot1` `DuckShotInit` `DuckShotEnd` `DuckShot0Init` `DuckShot0` `DuckShot0End` `DuckShot1Init` `DuckShot1` `DuckShot1End` `Punch` `DuckPunch` `Shot0Relax` `DuckShot0Relax` `ShelterDownReload0` `ShelterLeftReload0` `ShelterRightReload0` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2`


**Church only/partial** (39): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `StupidInit` `Stupid` `StupidEnd` `DuckRelax1` `DuckRelax2` `Reload` `DuckReload` `ShotInit` `ShotEnd` `DuckShotInit` `DuckShotEnd` `ShelterDownReload` `ShelterLeftReload` `ShelterRightReload` `WalkShelterLeft` `WalkShelterRight` `Spell` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`


**Black only/partial** (47): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `TKHit` `TKHitDuck` `StupidInit` `Stupid` `StupidEnd` `WalkViewLeft1` `WalkViewRight1` `DuckRelax1` `DuckRelax2` `Reload` `Reload0` `DuckReload` `DuckReload0` `Shot0` `DuckShot0` `Punch` `DuckPunch` `ShelterDownReload` `ShelterDownReload0` `ShelterLeftReload` `ShelterLeftReload0` `ShelterRightReload` `ShelterRightReload0` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`


**Jones only/partial** (49): `Trance` `TranceInit` `TranceEnd` `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `DuckRelax1` `DuckRelax2` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `WalkViewLeft1` `WalkViewRight1` `Reload` `Reload0` `DuckReload` `DuckReload0` `ShotInit` `Shot0` `ShotEnd` `DuckShotInit` `DuckShot0` `DuckShotEnd` `DuckPunch` `Punch` `ShelterDownReload` `ShelterDownReload0` `ShelterLeftReload` `ShelterLeftReload0` `ShelterRightReload` `ShelterRightReload0` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`


**Rawlings only/partial** (68): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft` `RelaxViewRight` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `StupidInit` `Stupid` `StupidEnd` `DuckRelax1` `DuckRelax2` `Reload` `Reload0` `DuckReload` `DuckReload0` `ReloadE` `DuckReloadE` `ShotInit` `ShotEnd` `Shot1` `Shot2` `Shot3` `ShotEInit` `ShotE` `ShotEEnd` `DuckShotEInit` `DuckShotE` `DuckShotEEnd` `DuckShotInit` `DuckShotEnd` `DuckShot1` `DuckShot2` `DuckShot3` `ShotH` `DuckShotH` `Special1` `DuckSpecial1` `ShotH_GH` `DuckShotH_GH` `Punch` `DuckPunch` `ShelterDownReload` `ShelterDownReload0` `ShelterDownReloadE` `ShelterLeftReload` `ShelterLeftReload0` `ShelterLeftReloadE` `ShelterRightReload` `ShelterRightReload0` `ShelterRightReloadE` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`

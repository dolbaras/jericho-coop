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
puppet kept standing (the live check, section 3, did not confirm this: the engine does call `OnDeath` on a puppet, a frame or two after `Life = 0`). Other players' first-person
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

### Live check (pair N100 host + main PC client, WWII_Vigil, `lab\animtest.sh`, 2026-10-28/29)

- Host console sets `Life = 0` on the AI body Rawlings (nobody else revives): the client's puppet of it lies in
  Agony for the 6 s watched and gets up after the host's `Team.RevivePlayer` (log lines `Action`/`Life` per
  second, frame sheet `work\runs\cap\a2-down.png`: the small figure on the ground). With the replica switched
  off (`animdown=false`, run a5) the puppet falls just the same, with its own random variant (Agony2 where the
  host's body has Agony): so the engine plays the death on a puppet; the owner's "stand instead of fall" is not
  reproduced for downed bodies. The replica waits 0.6 s for the engine and only acts on a body left standing
  (it acted at once in run a2 and overrode the engine's variant: fixed).
- The client's own body downed (`Life = 0` on the client): the host's puppet of it goes into Agony and the
  player moves into another body (`downed: Jones -> moved into Black`).
- One-shots (run a4: host `ForceAction` on AI bodies): the client logs `anim: Church plays HitStrong`, `Black
  plays Reload`, `Delgado plays Punch`, `Cole plays Reequip`, `Rawlings plays Reload` and Cole's `Action`
  reads `Reequip` there (a one-shot lasts about a second: the console sample can miss it).
- What the owner saw as "wounded squad members stand" is therefore most likely the AI bodies' hit reactions and
  reloads (never mirrored before this slice), not the downed state.

## 4. Second slice (2026-10-29)

- **Delgado's release of the Ababanili** (the owner's named case). Two bodies: a player's Delgado (first-person
  arms `Special_To/Special_Relax/Special_0Init`, `delgado.lua:SpecialInit`; the spirit is started by
  `FP_Delgado.UsePower` -> `Ababanili.AbabaniliStart`) and the AI Delgado (third-person `Shot1Init` /
  `DuckShot1Init`, event `Ababanili.AbabaniliStart` at frame 40). Before: only a player's spirit was relayed
  (`abby` message), the AI Delgado's spirit and open arm were not seen on clients, and a puppet's own `Shot1Init`
  (played by `Coop.mirrorArms` for `Special_0Init`) fired its frame-40 event there as well (a second spirit, or the
  AI call on a body whose AI is off). Now (`coop_powers.lua`): the host tells the others about an AI Delgado's
  spirit too (`tells`), a puppet's own `AbabaniliStart`/`AbabaniliClose` event is dropped (`puppetEvent`; only the
  `abby` replay starts it), the replay opens the arm in third person when nothing else did (`P.armOpen`), and the
  AI's `Shot1Init`/`DuckShot1Init` is mirrored from its state (`A.ONESHOT`). The arm closes by the game's own code:
  the replayed spirit's arrival calls `Ababanili.OnAbabaniliArrived`, which sends `Shot1EndAlt`.
  Live (WWII_Brandenburg, fight): the client logs `anim: Delgado plays Shot1Init` and `powers: Delgado's own
  AbabaniliStart event dropped (puppet)`. NOT confirmed live: the spirit of the AI Delgado itself (the host's
  `AbabaniliStart` returned false in every console attempt: `oAI.ObjectiveDin` does not take a value from Lua while
  the AI runs, the natural AI start did not happen in the 3-minute fights; the abby message path is the old one).
- **States that last** (`A.FAMILIES`, `A.syncState`): cover (`ShelterDown/Left/Right`), dazed (`Stupid`), trance
  (`Trance`, Jones), astral (`Astral`, Ross), possessed (`Possessed`, Jones): the Init action is played when the
  owner's body enters the family, the End action when the owner's body plays its own End (`<family>End`), or at the
  latest when it leaves the family (the loop in between follows the Init through its own event). Live results
  (2026-10-30, N100 host + this PC client, `lab\animstates.sh`, `cfg.animtrace` log of every action change of the
  puppet and of the owner): dazed Delgado (`StupidInit` -> `Stupid` -> `StupidEnd`), cover Rawlings/Cole/Delgado
  (`ShelterDown/Left/Right`), trance Jones, possessed Jones (Sum_Ziggurat_01): the puppet played Init and End in step
  with the host's body, no Lua error. Found and fixed on the way: (1) the End started only when the owner had left the
  family, 1.2 s after the owner's own End began (now it starts with the owner's End); (2) the Init of `Possessed` has
  the lowest priority (the level script adds it with no `PriorityLevel`), the puppet's walk input (drawn state, up to
  0.2 s old) cut it short: `CoopAnim.moveOverride` gives bodies held in Stupid/Trance/Astral/Possessed no walk input
  (`cfg.animhold=false` = old). Cover is left out (a body walks in cover). Astral (Ross): nothing in the scripts sets
  Ross's `AstralInit`; in Act 1 the other players see Ross through the stand-in `CoopRossBody` (`coop_ross.lua`), whose
  class had no Astral actions: `AstralInit/Astral/AstralEnd` added; run live by a forced `AstralInit` on the host's
  Ross (the stand-in's Action followed: `AstralInit`, `AstralEnd`), the pose itself was not judged on a frame.
- **First-person names -> third-person actions** (`A.FPMAP`): `TKCombo*` -> `TKHit` (Black; `Coop.mirrorArms` had
  no pattern for it), `Reequip`, `Hit*`/`HitStrong` of a human body. `Coop.mirrorArms` keeps what it maps
  (Combo, Punch, Reload, Spell, Hack, Special_0*). Every other first-person name that is not movement, posture or a
  menu is logged once per body (`anim: first-person <Body>:<Name> on the owner's arms, no third-person action
  mapped`). `lab\actinv_fp.lua` lists all first-person actions per class (`work\notes\actinv_fp.txt`):
  there is no third-person action for `Hurdle*`, `Fall*`, `SkipWall*`, `Heal`, `Order*`, `OpenPalancaA`,
  `OpenLightDoor`, `ThrowEnd`, `Activation`, `Special_1*` (Rawlings), `Aim*`: the body's own `Action` carries what
  exists (jumps/falls are locomotion).
- **Cole's grenade** (0.2.9): the third-person `Shot0` plays on a puppet from the owner's shot flag and slot, and its
  frame-29 event `WeaponsCole.LaunchGrenade` made a SECOND grenade on the puppet (own physics and explosion, next to the
  one the owner's machine throws). `CoopAnim.installGrenade` drops that launch event for a puppet (the throw is shown,
  the grenade is the owner's machine's; `cfg.puppetgrenade=true` = old). Live (`lab\grenade.sh`, client holds Cole,
  real virtual pad, LT = the grenade launcher): host log `anim: Cole's grenade launch dropped (puppet ...)`, no
  `Cole_Grenade` entity on the host; with the switch on the host's puppet makes `Cole_Grenade` at once (1 of 1).
  Not seen: a grenade of another player in flight (it exists on the owner's machine only).
- **First-person-only moves** (`CoopAnim.noteFpMove`): `Hurdle*` and `SkipWall*` are moves of the body by the engine
  (`Soldier.HurdleJump`: three `MoveMePosAng` steps) while only the arms play; the body's own `Action` stays `Relax`, so
  the other players saw the ally slide over the obstacle standing. The puppet now gets walk (+ sprint for a hurdle)
  input while the owner's arms name it (0.35 s after the last state): the legs of the closest third-person action,
  root motion off. Live (host `Soldier.LauchHurdleJump`, client frame sheet): Delgado runs on the spot over the move
  instead of sliding upright. Accepted and left out: `Fall*` (the engine's own falling pose), `Heal`, `Special_0/1` of
  Rawlings (his third-person twins `ShotH`, `ShotH_GH`, `Special1` fire game events - a heal, a curse - on the
  puppet's machine too; the powers themselves are relayed as `pw|r*` and shown by the aura; Rawlings' `Special_0` is
  the ghost heal, `Special_1` Vlad's course, from `chars/rawlings.lua` `SpecialInit`), `Order*` (a gesture of the
  squad leader, no twin), `OpenPalancaA` / `OpenLightDoor` (Delgado's lever and door use: the door or lever acts, the
  body stands: no twin; live `lab\fpmap.sh`: the log names it once, the puppet stays in `Relax`), `ThrowEnd`
  (the grenade throw is shown through `Shot0`), `Activation`, `Aim*`.
- Not done: Jones's possession scene as a whole (only the `Possessed` actions).

## 5. Jerky movement of remote bodies: causes noticed

0.2.9 (chunk I) changed the first, second, third and last causes below (every message handled per frame, a
cubic path averaged over 0.1 s with a delay of two states, bodies placed on the path, shot / slot / arm actions
from the drawn state); numbers and switches in `architecture.md` section 5.2 and `notes/bugfix-029.md`
section I. Found on the way: the host's own bodies move in steps of the engine's logic (a zero step every third
frame at 30 fps) and a run's stride pulses their speed, so the sampled path itself stutters; the average over two
states takes that out. Not changed: root motion of a shared action object, `ForceAction` restarts, the frame cap.

- State rate is 20 Hz (`Coop.TICK`, `SEND_EVERY = 1` tick); a puppet is drawn `INTERP_MIN..INTERP_MAX` (0.07-0.25 s) behind
  and extrapolates at most `EXTRAP_MAX` 0.2 s: a lost or late unreliable `s` packet shows as a stop-and-jump.
- `SNAP_DIST` 250 and the vertical snaps (`pdSnap`); `FOLLOW` 0.9 per 0.05 s plus the engine's own walking from the
  inputs fight each other (position written every frame over the body's own displacement).
- Root motion is switched off per action object shared by a class (`Coop.suppressRootMotion`): a local player
  of the same class, or an action not yet seen, moves by its animation on top of the placement.
- `ForceAction` mirrors (this file, `Coop.mirrorArms`, `syncCrouch`) restart an animation from its first frame: a
  repeated or late trigger pops the pose. They are debounced (0.6 s) but not blended.
- The client's frame cap (30 in tests, display Hz x2 in split screen) quantises interpolation to frames.
- Puppet inputs (`InCtrl_Walk/Str/Sprint`) come from the drawn state, shots from the newest: a turn and a shot can
  differ by the interpolation delay.

## 6. Still open

- The 3-player check of relayed `talk`. The AI Delgado's release of the dragon was seen live by itself (runs of
  2026-10-30 on Rom_Outskirts, both sides on autoplay: client `anim: Delgado plays Shot1Init`, `powers: Delgado's
  Ababanili attacks Enemy...`, `own AbabaniliStart event dropped (puppet)`, `comes back`, two cycles in a row);
  the arm opening on a frame is not shown yet (the client camera was in the fight elsewhere).
- Verification of every class on a live pair (action by action) once the whitelist is settled.

## 7. Third slice (0.3.0): fire controls, weapon modes, Rawlings' powers

Owner's report on 0.2.9: pistol shots, Black's guns (one mode only) and Delgado's dragon case were not shown to the watcher. The audit
(`notes/anim-audit-030.md`, every member, weapon, mode and power with its status) found:
- the weapons fired with the second trigger (Black's grenade launcher, Delgado's Raging Bull, Rawlings' pistols: `bFPShotOnSwitch`) were
  never fired on a puppet, which only had `owc.Shot`: state field 22 carries `owc.SecondWeaponTrigger`, `CoopAnim.driveFire` sets both;
- a puppet fired its own magazine (Bull 6 rounds, grenade launcher 1) and ran dry: `CoopAnim.keepAmmo`;
- fire mode (semi / burst / auto, `Weap_Slot0<i>ShootMode`) and Rawlings' pistol load (`ShotReloadPrefix`) were not sent: field 23,
  `CoopAnim.stateModes/applyModes`;
- the mirrored reload of Delgado's Bull was a no-op (he has `Reload0` only): `CoopAnim.reloadAction` (Reload0 for the second weapon of
  Delgado, Black, Jones, Ross; ReloadE for Rawlings' fragmenting/explosive loads);
- Rawlings' ghost heal fell on the general row `Special_0 -> Shot1` (a pistol shot): `Coop.ARM_BY_CHAR.Rawlings` maps `Special_0Init ->
  ShotH_GH`, `Special_1Init -> Special1`, each once; his FP `Heal` (reviving a teammate) -> `ShotH` (`A.FPMAP`);
- the events of those twins (`OnShotHeal`, `GhostHealShot`, `OnDoVladsCourse`) and Church's `LoseLifeCutting` change the game and ran on
  a puppet's machine: dropped there (`CoopAnim.guardEvents`);
- the AI Church's sabre strikes `Combo1Hit1/2` are replayed.
Switches: `cfg.puppetsecond/puppetmodes/puppetammo = false`, `cfg.puppetevents = true` (= 0.2.9). The dragon is unchanged: the code path
(FP `Special_0Init` -> `Shot1Init`, `abby|` replay, `P.armOpen`) exists and was never judged on a frame; live plan T4 in the audit.

## Appendix: every action (generated by `lab\actinv.lua`, 2026-10-28)

Counts: Ross 112, Cole 117, Delgado 128, Church 118, Black 126, Jones 128, Rawlings 147. In all seven classes (79):

`Agony` `AgonyInit` `AgonyEnd` `Agony2` `Agony2Init` `Agony2End` `HitStrong` `Relax` `Relax0` `Relax1` `Relax2` `TurnLeft` `TurnRight` `DuckRelaxEnd` `DuckRelaxInit` `DuckRelaxViewLeft0` `DuckRelaxViewLeft1` `DuckRelaxViewRight0` `DuckRelaxViewRight1` `RelaxViewLeft1` `RelaxViewRear` `RelaxViewRight1` `Sprint` `Walk` `Back` `StrLeft` `StrRight` `Run` `SprintDuckInit` `RunDuckInit` `WalkDuckInit` `SprintInit` `BackInit` `RunInit` `WalkInit` `SprintDuckEnd` `RunDuckEnd` `WalkDuckEnd` `SprintEnd` `BackEnd` `RunEnd` `WalkEnd` `BackDuckInit` `StrLeftDuckInit` `StrRightDuckInit` `WalkViewLeft0` `WalkViewRear` `WalkViewRight0` `DuckRelax` `DuckRelax0` `DuckTurnLeft` `DuckTurnRight` `TurnSprint` `Shot` `DuckShot` `RelaxLeft` `RelaxRight` `DuckRelaxLeft` `DuckRelaxRight` `Turn180` `Turn90Left` `Turn90Right` `DuckTurn180` `DuckTurn90Left` `DuckTurn90Right` `ShelterDownEnd` `ShelterDownInit` `ShelterDown` `SprintShelterDown` `ShelterLeftEnd` `ShelterLeftInit` `ShelterLeft` `ShelterLeftSet` `SprintShelterLeft` `ShelterRightEnd` `ShelterRightInit` `ShelterRight` `ShelterRightSet` `SprintShelterRight`


**Ross only/partial** (33): `AstralInit` `Astral` `AstralEnd` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `WalkViewLeft1` `WalkViewRight1` `Reload` `Reload0` `DuckReload` `DuckReload0` `ShotInit` `Shot0` `ShotEnd` `DuckShotInit` `DuckShot0` `DuckShotEnd` `DuckPunch` `Punch` `ShelterDownReload` `ShelterDownReload0` `ShelterLeftReload` `ShelterLeftReload0` `ShelterRightReload` `ShelterRightReload0` `ShelterRightAbort` `ShelterLeftAbort`


**Cole only/partial** (38): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft0` `RelaxViewRight0` `Hack` `Reequip` `DuckReequip` `WalkViewLeft1` `WalkViewRight1` `DuckRelax1` `DuckRelax2` `ShotInit` `Shot0` `ShotEnd` `DuckShotInit` `DuckShot0` `DuckShotEnd` `Punch` `DuckPunch` `Reload` `DuckReload` `ShelterDownReload` `ShelterLeftReload` `ShelterRightReload` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`


**Delgado only/partial** (49): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `StupidInit` `Stupid` `StupidEnd` `DuckRelax1` `DuckRelax2` `Reload0` `DuckReload0` `Shot1EndAlt` `ShotInit` `ShotEnd` `Shot0Init` `Shot0` `Shot0End` `Shot1Init` `Shot1` `DuckShotInit` `DuckShotEnd` `DuckShot0Init` `DuckShot0` `DuckShot0End` `DuckShot1Init` `DuckShot1` `DuckShot1End` `Punch` `DuckPunch` `Shot0Relax` `DuckShot0Relax` `ShelterDownReload0` `ShelterLeftReload0` `ShelterRightReload0` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2`


**Church only/partial** (39): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `StupidInit` `Stupid` `StupidEnd` `DuckRelax1` `DuckRelax2` `Reload` `DuckReload` `ShotInit` `ShotEnd` `DuckShotInit` `DuckShotEnd` `ShelterDownReload` `ShelterLeftReload` `ShelterRightReload` `WalkShelterLeft` `WalkShelterRight` `Spell` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`


**Black only/partial** (47): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `TKHit` `TKHitDuck` `StupidInit` `Stupid` `StupidEnd` `WalkViewLeft1` `WalkViewRight1` `DuckRelax1` `DuckRelax2` `Reload` `Reload0` `DuckReload` `DuckReload0` `Shot0` `DuckShot0` `Punch` `DuckPunch` `ShelterDownReload` `ShelterDownReload0` `ShelterLeftReload` `ShelterLeftReload0` `ShelterRightReload` `ShelterRightReload0` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`


**Jones only/partial** (49): `Trance` `TranceInit` `TranceEnd` `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `DuckRelax1` `DuckRelax2` `RelaxViewLeft0` `RelaxViewRight0` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `WalkViewLeft1` `WalkViewRight1` `Reload` `Reload0` `DuckReload` `DuckReload0` `ShotInit` `Shot0` `ShotEnd` `DuckShotInit` `DuckShot0` `DuckShotEnd` `DuckPunch` `Punch` `ShelterDownReload` `ShelterDownReload0` `ShelterLeftReload` `ShelterLeftReload0` `ShelterRightReload` `ShelterRightReload0` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`


**Rawlings only/partial** (68): `Hit` `HitDuck` `FriendlyFire` `DuckFriendlyFire` `RelaxViewLeft` `RelaxViewRight` `DuckSprint` `DuckWalk` `DuckBack` `DuckStrLeft` `DuckStrRight` `DuckRun` `StupidInit` `Stupid` `StupidEnd` `DuckRelax1` `DuckRelax2` `Reload` `Reload0` `DuckReload` `DuckReload0` `ReloadE` `DuckReloadE` `ShotInit` `ShotEnd` `Shot1` `Shot2` `Shot3` `ShotEInit` `ShotE` `ShotEEnd` `DuckShotEInit` `DuckShotE` `DuckShotEEnd` `DuckShotInit` `DuckShotEnd` `DuckShot1` `DuckShot2` `DuckShot3` `ShotH` `DuckShotH` `Special1` `DuckSpecial1` `ShotH_GH` `DuckShotH_GH` `Punch` `DuckPunch` `ShelterDownReload` `ShelterDownReload0` `ShelterDownReloadE` `ShelterLeftReload` `ShelterLeftReload0` `ShelterLeftReloadE` `ShelterRightReload` `ShelterRightReload0` `ShelterRightReloadE` `WalkShelterLeft` `WalkShelterRight` `Facial_Relax` `Facial_Relax1` `Facial_Talk` `Facial_Talk1` `Facial_Talk2` `Facial_01_Relax` `Facial_01_Relax1` `Facial_01_Talk` `Facial_01_Talk1` `Facial_01_Talk2`

## 8. Fourth slice (0.3.0): gaps filled with third-person twins, SMOD Add-ons

Study of SMOD Add-ons (PHM2D, on top of SkacikPL's SMOD): `notes/smod-addons11-analysis.md`. Its third-person view (owc.UseFPS = 0) plays the
character's own third-person actions for the player; the add-ons' scripts are the only place where the game's third-person twins of
first-person powers are driven by a player (`Delgado.PressSpecial`: slot 2 + `Shot1Init`, `Shot1EndAlt`; `Rawlings`: `ShotH_GH`,
`Special1`; `Black.PressSpecial`: `TKHit`; `Church.PressSpecial`: `Spell`). A player in that view sends the body's action as the
AI's does, so the one-shot list (`A.ONESHOT`) and the states already show it on the other machines. What the add-ons showed for the
gaps of `anim-audit-030.md` section 2:
- the fire barrier of Delgado has a third-person twin: the open arm (`Shot1Init`, held in `Shot1`, closed by `Shot1EndAlt`), with the
  Ababanili as the weapon in hand (slot 2). A first-person player's puppet now opens the arm on `Special_Relax`, closes it on
  `Special_From` (`A.gapArm`), keeps it open while his arms hold the barrier (`A.dragonArm`), and his state reports slot 2 while his arms
  are in a `Special_*` step (`A.reportSlot`, called from `Coop.stateOf`; the AI's own path sets the same slot);
- Cole's mine detonator (`02_Activation`) and mine mode pick (`ChooseModeInit`) show his `Hack` (a device on the wrist, no event), a
  reviver other than Rawlings (`Heal`) kneels (`DuckRelaxInit`): `A.FPMAP` rows, switch `cfg.gapgestures`;
- no twin exists, even in the add-ons' third-person view: orders, the fire-mode switch gesture, Cole's mine mode LEDs, the pillbox, Delgado's
  levers and doors, Black's trick-shot switch, falling, Rawlings' shaman calm, the QTE strikes. The add-ons' third-person revive
  (`Team.CurePlayerTP`) is explicitly "no animation".
- the events of Rawlings' Special1 are pointed at `Rawlings.TPVladsCourse` by the add-ons: guarded on puppets (`A.PUPPET_EVENTS`);
  their SkipWallInit flourish at every sprint start is no climb (`A.noteFpMove`).
All of it is mock-tested only; live checks are in the analysis (tests G1-G6, A5).

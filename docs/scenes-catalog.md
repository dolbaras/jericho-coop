# Clive Barker's Jericho: in-engine cutscene catalog for co-op

**Sources analysed (read-only; the game was not run):**
- Decompiled Lua in `work/src/` (private, next to this repo; not published).
- File names only from the archives `Data00..05.packed`, listed with `tools/bfpk.py --list`. No game data was extracted.
- Context: `campaign-structure.md`, `enemies-and-triggers.md`, `coop-ux-research.md` in this folder.

**Path conventions:**
- `scripts/...` is relative to `src/`.
- `<level>/<file>:line` is relative to `src/levels/<level>/scripts/`.
- Archive paths are relative to the archive root: `levels/<level>/map/<scene>/<scene>anm/<file>.cm3`.

**Labels:**
- **[O] Observed:** read directly in a script or in an archive file name.
- **[I] Inference:** a reasonable conclusion that the sources do not state directly.
- **[U] Unknown:** cannot be decided from Lua or file names. This is usually engine (C++) behaviour.

**Owner requirements this document follows:**
- **R1.** Bink videos are not changed.
- **R2.** In-engine scenes in which squad members take part are shown to each player from the character that player controls, and stay synchronised.
- **R3.** Only the player who controls the QTE character gets the QTE. If nobody controls it, the host does it, and the clients watch, ideally from a side camera.
- **R4.** Players whose characters are elsewhere get something to do. New content is allowed.

---

## 1. Summary

**Totals:**
- **40 in-engine scenes** in 19 of the 33 campaign levels [O].
  - There is one scene folder per scene in the archives, and the folder names match the `Scene.Scenes` tables 1:1 [O].
  - The other 14 levels have only a stub `mapscenes.lua` (3 or 24 lines): alk_city, alk_bunker_01, wwii_vigil, cru_keep, cru_catacomb, rom_caldarium, rom_tepidarium, rom_coloseum, rom_chamber, sum_ziggurat_01 to 04, and sum_ziggurat_meat.
- **The camera is almost always a first-person actor.**
  - 33 of the 40 scenes are filmed from `FP_<Char>`, an arms-and-camera actor, through `CameraFrom`.
  - 3 more (Apertura, Escalada and AperturaPuerta) animate the FP arms but film from the scene object.
  - Only 4 (TheDreamA and FlashBackA/B/C) use a cinematic camera with no FP actor at all (the scene object `DM_Scene_<Class>`).
- **Squad bodies in scenes:**
  - In **23 scenes**, one squad member is the FP camera and **every other squad member in the scene has a full-body animation** (`<Char>_Play.cm3`). Head-POV for those members can be built from existing assets.
  - The FP character itself has **no full-body animation** in any scene. Other players would see only its arms, or nothing. This needs a stand-in (section 6).
- **8 scenes contain QTEs:**
  - TombCollapses (Ross),
  - Pathofsouls (Cole),
  - RawlingsTorture (Rawlings),
  - BehemothDead ×2 (Church),
  - DescensoA and DescensoB (Church),
  - TheAbyss (Church).
  - A failed QTE never ends the game inside a scene. It branches to a "fail" alternate animation that replays or continues (section 2.5).
- **Bink videos (R1, untouched):**
  - `Intro.bik`, `Prologue.bik`, `LogoCodemasters.bik` and `LogoMSE.bik` sit in `game/Video.disabled/`.
  - `Trailer.bik` and `Tutorial.bik` are referenced from `scripts/menu/mainmenu.lua:127, 412`.
  - Where Intro and Prologue are triggered is not in Lua [U].

---

## 2. How the scene system works

### 2.1 Lifecycle [O]

1. **Preload at level load.**
   - `init.initGame` calls `Scene.LoadScenes()` (`scripts/init.lua:341`), which calls `Scene.Load(class)` for every entry of `Scene.Scenes` (`scripts/missions/scene.lua:39-58`).
   - `Scene.Load` (530-568):
     - creates the act class `"Scene"..Class` with model `<LevelPath>/Map/<Class>/<Class>.m3d` and one action `Play` = `<Class>Anm/Play.m3d`;
     - adds an event at `AnmTotalTime` that calls `Scene.EndOfScene` (544-546);
     - runs `MapScenesSnd[Class]` and `MapEffects[Class.."_Init"]`;
     - runs `MapScenes.OnLoad_<Class>()` (564-567).
   - **So every `OnLoad_*` runs once, at level load, not at play time** [O].
   - `Scene.Load` returns early when the class already exists (533-536). `Scene.Play` therefore does not re-run `OnLoad`.
2. **`OnLoad_<Class>` declares the actors.**
   - `Scene.AddCharActor(name, class)` (115-119) uses the model `Models/<Scene.CharDir>/<class>/<class>.M3D`. With `Scene.CharDir = "FPActor"` this is the FP camera actor `Models/FPActor/FP_<Char>`.
   - `Scene.AddLocalActor(name, class, path, ragdoll)` (121-141) is used for full-body characters (`Models/Chars/<Char>`) and props. A prop without a path uses `Map/<Class>/<class>.M3D`.
   - Both go through `Scene.BaseAddActor` (74-90), which records `{"Actor_"..name, Class..name, class}` in `Scene.Actors[Class]`.
   - `Scene.CreateLocalAction(char, …, "Play", "Play")` (214-233) points the action at `Map/<Class>/<Class>Anm/<Char>_Play.M3D` with `AnimAbsMove = 1`. The archive stores these as `.cm3` [O].
   - Frame-timed hooks:
     - `Scene.ActorAction(frame, actor, action)` (143-167) forces an actor's action at a frame;
     - `Scene.AddGeneric(frame, "lua")` (298-315) runs code at a frame;
     - `Scene.AddText`, `AddSound`, `AddStream` and `ShowChar` work the same way.
3. **`Scene.Play(Class)` (669-750):**
   1. returns `false` on game over;
   2. suspends radio talk;
   3. ends the astral camera and Cole's power loop;
   4. creates one entity of type `"WithLife"` per actor, named **`<Class><ActorName>`** (693-695);
   5. creates the scene object (`CreateSceneObj`, 649-667): an entity named after the map dummy **`DM_Scene_<Class>`** (or that name built from `ScenePos`/`SceneAng` when no dummy exists), with `ActCtrl = "Scene"..Class`;
   6. calls **`Scene.HideChars()`** (622-638), which sets every `WalkChar` (all real squad bodies, enemies and NPCs) to `Active = 0, TimeSpeed = 0`;
   7. stores `Scene.usr = Game.UsrEntity(0)`;
   8. shows cinema bars and creates a `"QTE"` HUD item on viewport 0 (699-702);
   9. sets `Input.SetActionSet("Inactive")` (707);
   10. points `EscapeEvent` at `Scene.AbortScene`;
   11. places every actor at the scene object (723-733). `LinkModel = "<DM_Scene_Class>,Actor_<Name>"` is used only when `UseAbsPos ~= 1`. **Every scene in the game sets `UseAbsPos = 1`** [O], and the animations are absolute (`AnimAbsMove = 1`);
   12. **`Scene.StickCamera(0, Scene.GetCamLink(Class))`** (735);
   13. sets `PhysXSpeed = 0` unless `UsePhysics` is set (746-749).
4. **End: `Scene.EndOfScene` (415-482).**
   1. restores the PhysX speed and runs `MapEffects[...]_CleanUp`;
   2. sets `cam.EntityLink = ""` on `Game.GetCam(0)` (438-439);
   3. calls `UnhideChars`;
   4. deletes the scene object and all actors (441-447);
   5. restores the action set (452);
   6. calls `EndOfSubSceneCallback`;
   7. then **either `Scene.Play(NextScene)` or `EndOfSceneCallback(Scene.usr)`** (464-473).
   - `Scene.AbortScene` (403-413) jumps straight to `EndOfScene` and sets `Scene.Aborted`.

### 2.2 Play variants [O]

| Call | Code | What it does with the player |
|---|---|---|
| `Scene.Play(c)` | 669-750 | Nothing. The real bodies are frozen and hidden. The camera follows the scene's camera link. |
| `Scene.PlayFP(c)` | 874-888 | If `CameraFrom` is set, it behaves as `PlayFPNI` (875-878). Otherwise: a temporary camera `Game.CreateEntity("Temp_Camera","Cam")` with `EntityLink = DM_Scene_<c>` reads `camPos`/`camAng`, then `SetUsrPosAng` (807-842) walks **`UsrEntity(0)`** into that pose with an FP turn animation, then `LauchFromFP`. |
| `Scene.PlayFPNI(c)` | 849-855 | No walk-in. `LauchFromFP(UsrEntity(0).Name)` with a 0.25 s interpolation camera (`InterpolCam`, 890-902). |
| `Scene.PlayFPNNI(c)` | 857-863 | Like `PlayFPNI`, without interpolation. |
| `LauchFromFP` | 910-926 | Saves the level callback in `FPEndOfSceneCallback`, sets `EndOfSceneCallback = Scene.EndOfFpScene`, then `Scene.Play`. |
| `Scene.EndOfFpScene(usr)` | 934-958 | Re-shows the FP weapon. **Teleports `usr` (= `UsrEntity(0)` at scene start)** to `FPPos`/`FPAng`, or to the last camera pose (which prints a "Nyapa" warning), then calls the saved level callback. |

**Notes on the variants:**
- [O] Many scenes overwrite `Scene.EndOfSceneCallback` at frame 0 from an `OnInit_*` generic. That bypasses `EndOfFpScene` unless the level callback calls it itself. Scenes that do call it: MurielsTale, DelgadokillsRawlings, BritishComandoSpeech, TheRescue and CenturiansTale.
- [O] `Scene.Play` has no `return true`. In `LauchFromFP` (921-924) `ret` is therefore `nil`, and the interpolation camera created at 914 is never activated.

### 2.3 Scene table fields (`Scene.Scenes[Class]`, read through `Scene.GetVar`, 29-35) [O]

| Field | Meaning |
|---|---|
| `UseDummyPosition` | Place the scene object at the map dummy. `true` only for both BehemothDead scenes. |
| `UseAbsPos` | 1 everywhere, so actors are not linked to the scene object nodes. |
| `UsePhysics` | Keep PhysX running. `true` for MurielsTale, both BehemothDead, CruzadersSpeech_B and all cru_sewers scenes. |
| `SoundBreak`, `EscapeSoundBreak` | Stop sounds at the end or on abort. |
| `EscapeScene` | Whether the scene can be skipped (`false` for TombCollapses, Pathofsouls, RawlingsTorture, both BehemothDead, Apertura, AperturaPuerta, DescensoA/B and TheAbyss). |
| `ScenePos`, `SceneAng` | Fallback position. |
| **`CameraFrom`** | The name of the actor the camera links to. |
| `NextScene` | Chain. |
| `FPPos`, `FPAng` | Post-scene position of `UsrEntity(0)`. |
| `Preload` | Default `true`. |

### 2.4 Camera link names [O]

`Scene.GetCamLink(Class)` (865-872):
- **`"DM_Scene_"..Class`** when `CameraFrom` is empty. The camera then rides the scene object, whose `Play` animation carries the camera.
- **`Class..CameraFrom`** otherwise, for example `"ConversationFP_Delgado"`.

`Scene.StickCamera(id, ename)` (640-647) on `Game.GetEntity(Game.GetCam(id))` sets:
- `FixedMode = 0`,
- `EntityLink = ename`,
- `clipNear = 5`,
- `clipFar = 400000`.

[I] The scene object's `Play.cm3` is 302 bytes in 26 scenes (314 bytes in both BehemothDead) and 0.4-26 KB in the other 12: TheDreamA 8.7 KB, TheDreamC 441 B, FlashBackA/B/C 1.4-2 KB, BritishComando 583 B, the four cru_sewers scenes 3-13 KB, TheRescue 26 KB, TheEndA 983 B. This supports the reading that the camera is in the FP actor animation unless `CameraFrom` is empty.
- How `EntityLink` derives the eye point from the linked entity (origin or a camera node) is unknown [U].
- `Scene.PlayFP` reads `cam.camPos` right after setting `EntityLink` (881-884). That suggests the link resolves synchronously [I].

### 2.5 Alternates and QTEs [O]

**Alternate animations:**
- `Scene.LoadAlternate(sufix, eosfunc)` (570-601) adds action `"Play"..sufix` from `<Class>Anm/Play<sufix>.m3d`. Its end event is `eosfunc` (default `Scene.EndOfScene`, often `"Scene.ReloadScene"`).
- `Scene.PlayAlternate(sufix)` (752-756) switches the scene object's action.
- `Scene.ReloadScene` / `ReplayScene` (498-517) end the scene and replay it from the start, keeping the callbacks. This is how a failed QTE is retried.

**QTE timing:**
- `QTE.AddSequence(frame, seq, prefix)` (`scripts/missions/qte.lua:49-63`) launches `seq` at `frame − 0.5 s·(len+1)` and validates at `frame`.
- `AddSequenceLauncher` and `AddSequenceValidator` (65-72, 130-138) give explicit frames.

**`QTE.ValidateSequence` (140-154):**
- if `Scorer.QTEIsSequenceOK()` is false, it calls `Scene.PlayAlternate(QTE.AlternatePrefix)`;
- level scripts move `QTE.AlternatePrefix` with `AddGeneric(frame, "QTE.AlternatePrefix = 'B'")`.

**Other QTE facts:**
- `QTE.WrongAction` (196-233) counts mistakes per `GameSkill`. `QTE.DontAllowMistakes` makes any mistake fatal to the sequence.
- All QTE state is global and drawn on viewport 0 (`Scorer.QTE*`).

### 2.6 Entity and node names usable by a mod

| What | Name | Evidence |
|---|---|---|
| Scene object | `DM_Scene_<Class>` | `scene.lua:651, 658, 660`; `Scene.SceneName = l.Name` (711) |
| Actor entity | `<Class><ActorName>`, for example `ConversationJones`, `BridgeCollapsesFP_Delgado`, `CruzadersSpeech_BFriendCrusader` | `scene.lua:78, 694`; used by name in `cru_labyrinth/mapscenes.lua:112-132`, `wwii_mosque_inside/mapscenes.lua:30-46`, `alk_desert/mapscenes.lua:201, 276` |
| Head bone (real chars) | `Bip Jones Head`, `Bip Cole Head`, `Bip Delgado Head`, `Bip Church Head`, **`Bip Rawllings Head`** (sic), `Bip Black Head`; Ross uses `Bip Jones Head`; `Neck` variants exist | `scripts/chars/jones.lua:103`, `cole.lua:87`, `delgado.lua:93`, `church.lua:86`, `rawlings.lua:92`, `black.lua:103`, `ross.lua:60` |
| Bone access on a **scene actor** | `ent.NodePosHierarchy_<node>`, `ent.NodeAngHierarchy_<node>`, `Game.GetRagdollPart(actor, "Bip Friend Crusader Head")` | `cru_labyrinth/mapscenes.lua:122-124, 132` |
| Link an entity to a node | `e.LinkModel = "<Entity>,<Node>"`, `OffModPos`, `OffMul`, `DeltaOffMul`, `UseLinkAng` | `scripts/fx/deathflies.lua:248-253`; `scene.lua:727-733` |

**Quirks in the actor names:**
- [I] The scene's full-body actors load the same models as the playable characters (`Models/Chars/<Char>/<Char>.M3D`), so the bone names should be the same.
- [O] In TheTrap the Jones body is registered under the actor name `"Delgado"`, so its entity is `TheTrapDelgado` (`rom_palace_02/mapscenes.lua:70-72`).
- [O] Landing uses `Cole_2`, an alternate Cole model.

### 2.7 Camera classes seen in the scripts [O]

| Class | Example | Fields and methods used |
|---|---|---|
| `"FCam"` (free or main camera) | `MainCam` (`scripts/chars/team.lua:103-108`), `CameraEnd` (`sum_end/mapinit.lua:61-65`), `MainMenuCamera` (`scripts/init.lua:87-91`) | `Pos`, `Ang`, `Fov` (90 for MainCam, 1.35 for the static cameras: units [U]), `CamDist`, `CamRot`, `CamAng`, `MainTarget`/`Target` (`team.lua:1390-1391`), `QuakeFactor`/`QuakeTime` (`cru_chapel/mapinit.lua:16-21`), `EntityLink`, `clipNear/Far` |
| `"Cam"` | `Temp_Camera` (`scene.lua:881-886`) | `EntityLink`, read-only `camPos`, `camAng` |
| `"CamPath"` | `Cameraman` (`team.lua:1350-1358`), `InterpolusCamera` (`scene.lua:891-901`) | `CreatePathAI(...)`, `nWayPoint`, `[i].TgtCam`, `[i].Time`, `FadeIn/Out`, `OnEnd` |
| `"AstralCam"` (orbit) | `AstralCam` (`scripts/chars/astralcamera.lua:5-14, 125-176`), `RawlingsHealtyCam` (`scripts/weapons/weaponsrawlings.lua:10, 217-230`) | `LinkToEntity(name)`, `SetOwner`, `SphereOffset`, `SphereRot`, `bSphereMove`, `MinFOV/MaxFOV`, `RotationSpeed`, `bCollisionFromLinked` |

Switch with `Game.SetCam(0, name)` and read with `Game.GetCam(0)`.

### 2.8 Attaching a POV camera to a specific actor (R2)

**Why the vanilla camera cannot simply be reused [O]:** apart from the `CameraFrom` character, no squad member has an FP actor in a scene, so its view must be taken from its full-body actor `<Class><Char>`.

Three ways, from least to most certain:
- **A. Direct link** [U]: `Scene.StickCamera(0, Class..Char)` would ride the full-body actor. Where the eye lands (feet origin or a node) is unknown. Expected to need an offset that the API does not expose.
- **B. Anchor entity on the head bone** [I/U]:
  - create a helper (for example `Game.CreateEntity("CoopPOVAnchor","WithLife")`);
  - set `LinkModel = "<Class><Char>,Bip <Char> Head"`, `UseLinkAng = 1`, `OffMul = 1`, `DeltaOffMul = 1`, `OffModPos = <eye offset>` (the same fields as `deathflies.lua:248-253`);
  - then `Scene.StickCamera(0, "CoopPOVAnchor")`.
  - Unknown: whether a `WithLife` entity needs a model, and whether `EntityLink` follows a linked entity [U].
- **C. Per-frame follow camera** (all APIs observed; recommended first prototype):

  ```lua
  -- [I] sketch, untested. Call after Scene.Play has stuck MainCam (e.g. from an injected AddGeneric(0, ...)).
  function CoopScene.StartPOV(class, char)
    CoopScene.pov = { actor = class .. char,
                      node = (char == "Rawlings") and "Bip Rawllings Head" or ("Bip " .. char .. " Head") }
    local cam = Game.GetEntity("CoopPOVCam") or Game.CreateEntity("CoopPOVCam", "FCam")
    cam.Fov = Game.GetEntity("MainCam").Fov           -- units [U]
    Game.SetCam(0, cam.Name)
    CoopScene.TickPOV()
  end
  function CoopScene.TickPOV()
    local p = CoopScene.pov; local a = p and Game.GetEntity(p.actor)
    if not (a and Scene.IsPlaying) then return end
    local cam = Game.GetEntity("CoopPOVCam")
    local hp, ha = a["NodePosHierarchy_" .. p.node], a["NodeAngHierarchy_" .. p.node]
    cam.Pos = hp + CoopScene.EyeOffset:rot(ha)        -- eye offset to calibrate [U]
    cam.Ang = ha + CoopScene.HeadAxisFix              -- bone-axis correction [U]
    Game.AddScheduledFunc(Game.GetTime(), "CoopPOV", "CoopScene.TickPOV")   -- per-frame reschedule as in fx/sum_end/mapeffects.lua:877
  end
  ```

**Gotchas for options A to C:**
- `EndOfScene` clears `EntityLink` on whatever `Game.GetCam(0)` is (438-439). The mod must:
  1. switch back with `Game.SetCam(0,"MainCam")`,
  2. clear `MainCam.EntityLink`, which still points to the deleted FP actor,
  3. do both in a wrapper around `Scene.EndOfScene`.
- The actor's own head mesh will be inside the camera. `clipNear = 5` and a forward eye offset are the cheapest fix.
  - [O] Per-node mesh switches exist (`ent.bExtNodeDisabled_XT_...`, `wwii_mosque/mapscenes.lua:29-31`), but only for `XT_` extension nodes.
  - Hiding a head [U].
- Whether `NodePosHierarchy_` accepts bone names containing spaces is unknown [U]. `Game.GetRagdollPart` does accept them (`cru_labyrinth/mapscenes.lua:132`).
- **The `CameraFrom` character's player** keeps the vanilla camera (it is already that character's eyes).
- **The `CameraFrom` character is bodiless for everyone else** (only `FP_<Char>` arms) [O: no `<FPChar>_Play.cm3` in any scene].
  - Option: spawn a stand-in full-body actor (`Models/Chars/<Char>`, Relax loop) linked to the FP actor's position on the other clients (`LinkModel "<Class>FP_<Char>,<node>"`), or hide the FP arms there.
  - The node names in the FP models are unknown [U].
- **Per-client:** each co-op machine plays the scene locally on its own camera 0 (`coop-ux-research.md` 5.6). No split-screen or second viewport is needed.

### 2.9 Cinematic side camera (R3 spectators, absent players)

1. **Fixed `FCam`:** create the camera and set `Pos`/`Ang`/`Fov` as `sum_end/mapinit.lua:61-65` does.
   - Anchor it on the FP or QTE actor (`Game.GetEntity(Class.."FP_Church").Pos`) or on the dummy.
   - The dummy position is available through `Game.StartDummySearch("DM_Scene_"..Class,1)` / `Game.NextDummySearch()` (`scene.lua:651-652`).
   - Aim it with `(target.Pos - cam.Pos):getrot()`, the pattern in `qte.lua:289` and `weaponsrawlings.lua:307`. The pitch sign is [U]: AstralCamera negates X (`astralcamera.lua:136`).
2. **Orbit camera:**
   - create an `"AstralCam"`-class entity (as `weaponsrawlings.lua:10`);
   - call `cam:LinkToEntity("<Class><Actor>")`, set `SphereOffset`, and leave out the `OnInit*` callbacks (OnlyOrbit style, `astralcamera.lua:125-176`).
   - Do **not** call `AstralCamera.Start` on a scene actor: it touches `usr.oWeapCtrl` and `ViewAng` [I], which `WithLife` actors lack.
   - Whether `LinkToEntity` works on a `WithLife` entity is unknown [U].
3. **Third-person follow:** `FCam` with `Target`/`MainTarget = <actor>` and `CamDist > 0`.
   - [I] `MainCam.CamDist = 0` is set for first person (`astralcamera.lua:42`), which suggests a non-zero value orbits.
   - Untested on scene actors [U].
4. **The scene-object camera** (`DM_Scene_<Class>`) gives a real cinematic view only for TheDreamA, FlashBackA/B/C, Apertura, Escalada and AperturaPuerta.

### 2.10 Synchronisation and QTE routing (implementation notes)

> Written before the code; the built scene and QTE messages are in `architecture.md` (section 4, "Cutscene branches and QTEs").

**Start:**
- The host wraps `Scene.Play`/`PlayFP*` and broadcasts `scene <Class>`. Clients call the same function locally.
- Clients must not run their own triggers (`enemies-and-triggers.md` §5).

**Drift:**
- At level load, wrap `MapScenes.OnLoad_<Class>` and append `Scene.AddGeneric(f, "Coop.SceneTick("..f..")")` every N frames. This is the same mechanism the levels use, and it must run while the scene's class and action are current [I].
- The host broadcasts its ticks. Clients correct with `Scene.SetTimeSpeed(s)` (`scene.lua:758-770`, which sets `TimeSpeed` on the scene object and all actors).
- The field holding the current animation time is not known from scripts [U].

**Alternates and randomness:**
- Only the host chooses: QTE fail branches, `ReloadScene`, and RawlingsTorture's `math.random` loop (`wwii_vigil_inside/mapscenes.lua:177-246`).
- The host broadcasts `alt <prefix>`. Clients apply `Scene.PlayAlternate`.

**QTE owner client:**
- runs the vanilla `QTE.LaunchSequence` / `ValidateSequence`;
- `Scene.PlayAlternate` inside `ValidateSequence` (151) and `WrongAction` (228) is replaced by "send fail to host".

**Non-owner clients:**
- `QTE.LaunchSequence`, `QTE.ValidateSequence` and `QTE.WrongAction` must be stubbed.
- Otherwise the validator sees no input and **forces the fail branch locally** (desync) [I from 140-154].
- The prompts can be drawn greyed (`coop-ux-research.md` 5.6).

**Other required patches:**

| Item | Problem | Patch |
|---|---|---|
| Real bodies after a scene | `EndOfFpScene` teleports `UsrEntity(0)`, not the FP character (934-949). | Teleport the body of the **`CameraFrom` character** (by name) and leave the other humans' bodies alone, unless the level callback repositions them on purpose (CenturiansTale, DelgadokillsRawlings). |
| `Scene.ShowChar(..., true)` in TombCollapses alternate A (`alk_tomb/mapscenes.lua:146-151`) and AperturaPuerta (`cru_sewers/mapscenes.lua:103-110`) | Sets `oAI.bEnable = true` on real bodies (`scene.lua:796-805`). | Skip human-held bodies. |
| `Scene.HideChars` | Resets `Scene.HidenChars` on every call (623). Scenes that call it again from a frame event lose the first list: Landing f1, DelgadokillsRawlings f1, RossDeathB OnInit, TheEndB f695, TheEndD f0. | Re-activate human bodies explicitly at scene end. How vanilla recovers from this is not visible in Lua [U]. |
| Global effects | `Input.SetActionSet("Inactive")`, `PhysXSpeed`, `Game.SetTimeSpeed` / `SetTimeFade` inside scenes (TheEndB, TheEndC, RawlingsTorture's `QTEDeadAndReplay`). | Host-driven; acceptable, since every machine is in the same scene. |

### 2.11 Other observed quirks [O]

- Conversation (wwii_biggates `mapinit.lua:19-21`) and TheRescue (cru_chapel `mapinit.lua:1-5`) play on every level load: there is no spawn-point check. IntoTheUnknown and both alk_desert chains are level-start only by design.
- FlashBackC's `OnInit_FlashBackC` is never scheduled (`alk_desert/mapscenes.lua:380-397`).
- RawlingsTorture alternate A references an actor `"Black"` that was never added (`wwii_vigil_inside/mapscenes.lua:102`). It only logs a console error (`scene.lua:156-158`).
- TheEndB replaces the FP callback at frame 696 (`sum_end/mapscenes.lua:96-98, 121`), so `MapInit.ChatAfterScene` and `EndOfFpScene` do not run after the TheEndA/B chain.
- Orphan or alternate entry points:
  - `wwii_mosque/mapcallbacks.lua:57-59` `AreaTrigger_1` (not wired);
  - `cru_sewers/mapcallbacks.lua:259-286` `PlayAperturaPuerta` / `PlayEscalada` (not wired);
  - `rom_palace_02/mapcallbacks.lua:421-425` `o249_0` → `Scene.Play("TheAbyss")`: not wired, and no TheAbyss scene exists in that level.

---

## 3. Catalog: all scenes in campaign order

**Column meanings:**
- **Mode:** `Play`, `FP` (= `PlayFP`), `FPNI` or `FPNNI`. `FP*` with `CameraFrom` set behaves as `FPNI`.
- **Cam:** the FP actor named in `CameraFrom`, or `DM` for the scene-object camera.
- **Full-body squad / other actors:** from the archive names `<scene>anm/<actor>_play*.cm3` [O]. `FP_<X>` means first-person arms and camera.
- **Squad in level:** at the moment the scene starts. `elsewhere` means not loaded, `bActive = false`, or in another part of the map. Taken from `campaign-structure.md` §3 and the cited lines.
- **Length:** the last frame used by a scripted event is a lower bound.
  - FPS is not in the scripts [U]. QTE windows (about 20-30 frames for a 1 s single-button window, for example `wwii_pillboxes/mapscenes.lua:89-90`) suggest 25-30 fps [I].
  - Seconds are given at 30 fps.

| # | Level | Scene | Started by [O] | Mode | Cam | Full-body squad | Other actors | QTE | End callback [O] | Squad in level at start | Length |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | alk_desert | TheDreamA | `MapInit.PlayTheDreamA` `alk_desert/mapinit.lua:10-12` (scheduled at 2-4, level start) | FPNNI | DM | — (TrueRoss dream body) | FirstBornLegs | — | NextScene TheDreamB (`mapscenes.lua:12`); sub-cb empty (120-121) | 6 + Ross (Ross is the player) | unknown |
| 2 | alk_desert | TheDreamB | NextScene | chain | FP_Ross | — | FirstBornLegs | — | NextScene TheDreamC (23); `OnEnd_TheDreamB` `SoundsOff` (146-148) | same | ≥500 f (≈17 s) |
| 3 | alk_desert | TheDreamC | NextScene | chain | FP_RossNude | — | Telefono | — | NextScene HelicopterTrip (34) | same | ≥645 f (≈22 s) |
| 4 | alk_desert | HelicopterTrip | NextScene | chain | FP_Ross | Black, Church, Cole, Delgado, Jones, Rawlings | Helicopter, Elementos | — | NextScene FlashBackA (45) | same | unknown |
| 5 | alk_desert | FlashBackA | NextScene | chain | DM | — | FirstBornLegs | — | NextScene FlashBackB (55) | same | ≥220 f |
| 6 | alk_desert | FlashBackB | NextScene | chain | DM | — | FirstBornLegs | — | NextScene FlashBackC (65) | same | ≥265 f |
| 7 | alk_desert | FlashBackC | NextScene | chain | DM | — | FirstBornLegs | — | NextScene Landing (75) | same | ≥515 f |
| 8 | alk_desert | Landing | NextScene | chain | FP_Ross | Black, Church, Cole (`Cole_2` model), Delgado, Jones, Rawlings | Helicopter | — | `EndOfFpScene` → Ross to `FPPos` (86-87); `OnEnd_Landing` → `MapInit.StartTutorial` (285-288, `mapinit.lua:14-21`) | same | unknown |
| 9 | alk_tomb | TombCollapses | `MapInit.PlayTombCollapses` `alk_tomb/mapinit.lua:19-22` (spawn 0 only, 4-9) | FPNI | FP_Ross | all 6 (Play + PlayA-D) | Stones | **Ross**: `ULR` at 1065-1115; in alternate A: R, L, R, U, R (`mapscenes.lua:120-144`); fail → B/C/D stumble, which return to A (152-178) | `EndOfFpScene` → `MapInit.ChatAfterScene` (`mapinit.lua:24-26`); alternate A re-activates the real squad at f300 (`ShowChar`, 146-151) | 6 + Ross | Play ≥1129 f (≈38 s) + A ≥315 f |
| 10 | alk_tomb | BloodDoor | `MapCallbacks.Borrame_cinematica_0` `mapcallbacks.lua:127-129` (area trigger, `mapareatriggers.lua:707`) | FP→FPNI | FP_Ross | Black, Church, Rawlings | Door, Sello | — | `OnEnd_BloodDoor` → `NewLevelNow("Alk_Bunker_00")` (`mapscenes.lua:182-188`) | Ross, Church, Rawlings, Black; **Jones, Cole, Delgado elsewhere** (left, `mapinit.lua:102-149`) | ≥1655 f (≈55 s) |
| 11 | alk_bunker_00 | MurielsTale | `AreaTriggerMurielsTale_0` `alk_bunker_00/mapcallbacks.lua:59-61` | FP→FPNI | FP_Ross | Rawlings | MurielGreen, Armas | — | `OnEnd_MurielsTale`: Rawlings position, `EndOfFpScene`, follow orders (`mapscenes.lua:26-33`) | Ross + Rawlings only; **4 others not loaded** | ≥3000 f (≈100 s) |
| 12 | alk_final | RossDeath | `AreaTriggerFinal_1` `alk_final/mapcallbacks.lua:62-64` | Play | FP_Ross | Black, Delgado, Jones, Rawlings | Arnold, CultistaVolador, FirstBorn, RossArm | — | NextScene RossDeathB (`mapscenes.lua:13`) | 6 + Ross; Church and Cole in level but **not in scene** | ≥2130 f (≈71 s) |
| 13 | alk_final | RossDeathB | NextScene | chain | FP_Delgado | Black, Church, Cole, Jones, Rawlings | CultistaVolador, RossDead | — | `OnEnd_RossDeathB` → `NewLevelNow("WWII_BigGates")` (93-95) | same (Ross dead) | ≥275 f |
| 14 | wwii_biggates | Conversation | `MapInit.PlayConversation` `wwii_biggates/mapinit.lua:24-26` (every load, 19-21) | Play | FP_Delgado | Black, Church, Cole, Jones, Rawlings | — | — | `OnEnd_Conversation`: fade (`mapscenes.lua:18-20`) | all 6 | ≥1770 f (≈59 s) |
| 15 | wwii_pillboxes | Pathofsouls | `MapInit.LaunchScenePOS` `wwii_pillboxes/mapinit.lua:249-257`, via Cole's pillbox use (`PillBoxOnUse` 237-246) | FPNNI | FP_Cole | — | NaziSoldierC, Soul, Fusil, Proyectil | **Cole**: R, L, R, DU, L, U (415-632); fail → `_A`/`_B` → ReloadScene (`mapscenes.lua:89-107`) | NextScene DelgadokillsRawlings (13); `OnEnd_Pathofsouls` empty (53-54) | all 6 (Jones locked); others in combat area, frozen | ≥632 f (≈21 s) |
| 16 | wwii_pillboxes | DelgadokillsRawlings | NextScene | chain | FP_Cole | Black, Church, Delgado, Jones, Rawlings | — | — | Frame 0: real Rawlings `Life = 0` (112-118). `OnEnd`: `EndOfFpScene`, `AfterRawlingKilled` → solo mission, `SchSetChars` repositions all, `DisableAILoop` (120-196) | all 6 | ≥1870 f (≈62 s) |
| 17 | wwii_mosque | BritishComando | `MapCallbacks.TriggerBritishScene_0` `wwii_mosque/mapcallbacks.lua:84-88`: `SetUsrPosAng` walks `UsrEntity(0)` in, then `LauchFromFP` | FP (manual) | FP_Black | — | British | — | `OnEnd_BritishComando` → `NewLevelNow("WWII_Mosque_Inside")` (`mapscenes.lua:18-20`) | all 6 (not in scene) | ≥220 f (≈7 s) |
| 18 | wwii_mosque_inside | BritishComandoSpeech | `MapInit.PlayBritishComandoSpeech` `wwii_mosque_inside/mapinit.lua:40-42` (spawn 0, 6-9) | FPNNI | FP_Jones | Black, Church, Cole, Delgado, Rawlings | BritishBarndon, Buckland, Robertson, Matriuskas, MuroExplosivo | — | `OnEnd`: `EndOfFpScene` → `FPPos` (`mapscenes.lua:13-14, 25-27`) | all 6 | unknown |
| 19 | wwii_vigil_inside | RawlingsTorture | `PsichicCommander.PlayEndScene` `scripts/chars/psichiccommander.lua:375-378` (from `EndOfBitch` 360-373, after an AI walk) | Play | FP_Rawlings | Church (+A), Cole | PsichicCommander (A-I), Reja, Book | **Rawlings**: random loop B/C/D/E/H, single buttons; needs 5/8/10 hits by skill; any mistake fails (`DontAllowMistakes`); fail → F/G/I → reset points and replay B (`mapscenes.lua:99-262`) | `EndRawlingsTorture` → `NewLevelNow("WWII_Brandenburg")` (32-35) | Cole, Church, Rawlings (3-body level) | ≥1220 f + variable loop; A fade at 2150 |
| 20 | wwii_brandenburg | NaziSacrificeA | `AreaTrigger168_0` (Church only) `wwii_brandenburg/mapcallbacks.lua:18-25`, or use object `triggerUseNaziSacrifice_0` (125-129); both call `HideRawlingsCole` (`mapinit.lua:118-122`) | FP→FPNI | FP_Church | — | — | — | `OnEnd_NaziSacrificeA` → `PlayFPNI("NaziSacrificeB")` (`mapscenes.lua:33-35`) | 6; Cole and Rawlings hidden (props); Jones, Delgado, Black below | ≥82 f (≈3 s) |
| 21 | wwii_brandenburg | NaziSacrificeB | `OnEnd_NaziSacrificeA` | FPNI | FP_Church | Cole, Rawlings | PsichicCommander, PsichicCommander_Cut | — | `OnEnd_NaziSacrificeB` → `MapInit.StartEndScene` (`mapinit.lua:124-130`) → `ReposPeople` AI walk → `EndOfMap` → Cru_River | Jones, Delgado, Black **not in scene** | ≥1200 f (≈40 s) |
| 22 | cru_river | BehemothDead | `MapScenes.StartBehemotQTE` (`UseFunc` of `Kill_Behemoth_03`, Church only) `cru_river/mapscenes.lua:83-96` | FPNI | FP_Church | — | Behemoth (A-C) | **Church**: `UDU`@80, `UDLR`@180, `LRD`@320, `D`@147 in A; fail → `_A/_B/_C` → ReloadScene (46-81) | `OnEnd_BehemothDead`: music and radio line (41-44) | all 6 (others in the arena, frozen) | ≥320 f (≈11 s) + retries |
| 23 | cru_river | BridgeCollapses | `Trigg_DelgadoDoor_0` (Delgado only) `cru_river/mapcallbacks.lua:284-287` → `MapScenes.CrossOverBridge` (132-136) | FP→FPNI | FP_Delgado | Black, Church, Cole, Jones, Rawlings | CultistaVolador, TemplarioAmigo, PuenteRoto | — | `OnEnd_BridgeCollapses` → `NewLevelNow("Cru_Labyrinth")` (144-146) | all 6; Jones, Cole and Rawlings are **lost** from here | ≥1280 f (≈43 s) |
| 24 | cru_labyrinth | CruzadersSpeech_A | `MapInit.PlayCruzadersSpeech_A` `cru_labyrinth/mapinit.lua:15-18` (spawn 0, 5-8) | FPNNI | FP_Delgado | Black, Church | Arnold, TemplarioAmigo, Door | — | `OnEnd_CruzadersSpeech_A`: fade, door (`mapscenes.lua:79-82`; callback set in OnLoad 45) | Delgado, Church, Black | ≥3300 f (≈110 s) |
| 25 | cru_labyrinth | CruzadersSpeech_B | `o1007_0` (Black-only use object) `mapcallbacks.lua:394-396`, or area trigger `TriggerLastScene_0` (player must be Black) 353-359 | FP→FPNI | FP_Black | Church, Delgado | FriendCrusader (ragdoll and chain physics), Stones | — | `OnEnd_CruzadersSpeech_B` → `NewLevelNow("Cru_Sewers")` (174-176) | Delgado, Church, Black | ≥4080 f (≈136 s) |
| 26 | cru_sewers | Apertura | `TriggerApertura_0` (Black-only use) `cru_sewers/mapcallbacks.lua:333-340` | FP (walk-in) | DM + FP_Black arms | — | (map prop `SceneRocks`) | — | `EndOfFpScene` only | Delgado, Church, Black | unknown (short) [I] |
| 27 | cru_sewers | Escalada | `TriggerEscalada_0` (Church-only use) `mapcallbacks.lua:362-367`; sets `SoloMision = true` | FP (walk-in) | DM + FP_Church arms | — | — | — | `EndOfFpScene` → `FPPos` (`mapscenes.lua:21-22`); f0 `DeactivateChurchOrders`, f300 `HoldAllTeams` after 5 s (82-98, 320-331) | Church climbs; **Black and Delgado stay below** (later `bActive=false`, `mapcallbacks.lua:355-360`) [I order] | ≥300 f (≈10 s) |
| 28 | cru_sewers | DescensoA | `MapCallbacks.PlayDescenso` (area trigger, Church only) `mapcallbacks.lua:268-276` | FP→FPNI | FP_Church | — | CruzadoA | **Church**: 13 single-button sequences from 120 to 735; fail → `_A/_B` → ReloadScene (`mapscenes.lua:161-216`) | NextScene DescensoB (43) | Church solo; Black and Delgado elsewhere [I] | ≥735 f (≈25 s) |
| 29 | cru_sewers | DescensoB | NextScene | chain | FP_Church | — | CruzadoA | **Church**: 6 sequences from 55 to 260; autosave at f270; fail → `_A` → ReloadScene (218-251) | `EndOfFpScene` (no `FPPos` → camera pose) | same | ≥430 f (≈14 s) |
| 30 | cru_sewers | AperturaPuerta | `TriggerAperturaPuerta_0` (user must be Church) `mapcallbacks.lua:319-331`; re-activates Black and Delgado | FP (walk-in) | DM + FP_Church arms | — | (map door `ScenePuerta`) | — | `EndOfFpScene` → `FPPos` (`mapscenes.lua:32-33`). f289 `AperturaPuertaAbierta`: orders, hold, follow, chat (127-152); `ShowChar` Black/Delgado f0 (relax) and f289 (AI on) (103-110) | Church inside; Black and Delgado re-appear | ≥289 f (≈10 s) |
| 31 | cru_chapel | TheRescue | `MapInit.PlayTheRescue` `cru_chapel/mapinit.lua:11-14` (every load, 1-5) | FP→FPNI | FP_Black | Church, Cole, Delgado, Jones, Rawlings | — | — | `OnEnd_TheRescue`: `EndOfFpScene` → `FPPos`; activates `bebes_cruzados` (`mapscenes.lua:61-65`) | 6 (Jones, Cole and Rawlings rejoin here) | unknown (actions start at f50) |
| 32 | rom_outskirts | BehemothDead | `MapScenes.StartBehemotQTE` (`Kill_Behemoth_03`, Church only) `rom_outskirts/mapscenes.lua:79-90` | FPNI | FP_Church | — | Behemoth (A-C) | **Church**: same pattern as #22 (48-75) | `OnEnd_BehemothDead`: music (38-40) | all 6 (others in combat area, frozen) | ≥320 f + retries |
| 33 | rom_outskirts | CenturiansTale | `MapInit.SchPlayScene` `rom_outskirts/mapinit.lua:97-100`, after a forced switch to Rawlings (`BeginPlayScene` 64-73, from `Enemy_Group_Torturers_0` `mapcallbacks.lua:208-213`) | FP→FPNI | FP_Rawlings | Black, Church, Cole, Delgado, Jones | Centurion | — | `OnEnd_CenturiansTale`: places all 5 others, clears `UnavaliablePlayers`, `EndOfFpScene` (`mapscenes.lua:105-141`) | all 6 (all locked) | ≥4450 f (≈148 s) |
| 34 | rom_palace_01 | TheAbyss | `o249_0` (`TriggerTheAbyss`, Church-only use) `rom_palace_01/mapcallbacks.lua:473-480`; locks Church's switch | FP→FPNI | FP_Church | — | Cornisa, Estatua | **Church**: 9 sequences from 70 to 590; fail → A/B → ReloadScene (`mapscenes.lua:53-79`) | `EndOfFpScene` (no `FPPos`) | all 6; others at the abyss edge, frozen | ≥665 f (≈22 s) |
| 35 | rom_palace_02 | TheTrap | `AreaTrigger_3` `rom_palace_02/mapcallbacks.lua:175-178`, after Delgado's light door and AI walk (`puerta_final_delgado_1` 458-462 → `MapInit.GoToFinalScene` `mapinit.lua:7-13`) | FP→FPNI | FP_Delgado | Black, Church, Cole, Jones (entity `TheTrapDelgado`), Rawlings | Vicus2, Trampa, Filete | — | `OnEnd_TheTrap` → `NewLevelNow("Rom_Coloseum")` (`mapscenes.lua:23-25`) | all 6 | ≥2950 f (≈98 s) |
| 36 | sum_ziggurat_05 | IntoTheUnknown | `MapInit.PlayIntoTheUnknown` `sum_ziggurat_05/mapinit.lua:7-9` (level start) | Play | FP_Black | Church, Cole, Delgado, Jones, Rawlings | SummerianPriest, Urnas | — | `OnEnd_IntoTheUnknown` → `NewLevelNow("Sum_End")` (`mapscenes.lua:23-25`) | cutscene-only level | ≥6850 f (≈228 s) |
| 37 | sum_end | TheEndA | `MapInit.PlayInit` `sum_end/mapinit.lua:11-14` (level start) | FPNNI | FP_Black | Cole, Jones | CorpseA/B, Head, Leg | — | NextScene TheEndB (`mapscenes.lua:15`) | Black, Church, Delgado, Rawlings; Jones and Cole exist **only as scene actors** | unknown |
| 38 | sum_end | TheEndB | NextScene | chain | FP_Black | Church, Cole, Delgado, Jones, Rawlings | Arnold, FirstBornLegs, ColeGore, JonesGore | — | `OnEndTheEndB` (music if aborted, 96-104); Jones and Cole die (`fx/sum_end/mapeffects.lua:87-89` per campaign doc) | same | ≥3362 f (≈112 s) |
| 39 | sum_end | TheEndC | `MapInit.EndOfGame` `sum_end/mapinit.lua:52-56`, from `EvilFirstBorn.KillFirstBornScene` (`scripts/chars/evilfirstborn.lua:579-587`) | Play | FP_Church | Black, Delgado, Rawlings | Arnold, FirstBornLegs, Rocks | — | NextScene TheEndD (`mapscenes.lua:40`) | 4 survivors | ≥250 f |
| 40 | sum_end | TheEndD | NextScene | chain | FP_Church | Black, Delgado, Rawlings | CorpseA-C, Head1/2, Leg, Arm | — | `MapInit.ShowCredits`: fixed `FCam` "CameraEnd", credits, menu (`mapinit.lua:58-92`) | 4 survivors | ≥710 f (≈24 s) |

---

## 4. Default co-op rules for every scene [I] (proposal)

1. **Host-triggered, locally played** (`coop-ux-research.md` 5.6).
   - The host's `Scene.Play`/`PlayFP*` broadcasts the class.
   - Each client plays the scene locally (actors are local `WithLife` entities, `scene.lua:694`).
   - Alternates, `ReloadScene` and `NextScene` follow host messages.
2. **POV per client (R2):**
   - the player of the `CameraFrom` character: vanilla camera;
   - every other player whose character has a full-body actor in the scene: head POV on `<Class><Char>` (2.8 C);
   - a player whose character is in the level but not in the scene, or has no body: the `CameraFrom` view (default) or a side camera (2.9). The player chooses with one button; a spectator can also cycle through the head POVs of the other actors.
3. **FP stand-in:** in the 23 multi-character scenes, clients other than the FP owner need a body for the FP character (2.8).
   - Minimum: hide the floating arms on those clients.
   - Better: a full-body stand-in linked to the FP actor.
   - Animation fidelity will be poor (no lip-sync or gestures exist) [I].
4. **QTE (R3):**
   - The owner is the human holding the QTE character.
   - If nobody holds it, the **host** plays it (the host is moved into the character as in `coop-ux-research.md` 5.6) and sees the vanilla FP camera.
   - The other players get a side camera aimed at the QTE target (Behemoth, CruzadoA, PsichicCommander, Soul, Cornisa) or the owner's FP view.
   - Routing as in 2.10.
5. **Post-scene placement:** the FP character's body takes `FPPos`, or the end camera pose. Other human bodies keep their pre-scene positions unless the level callback moves them.
6. **Skipping:** unanimous hold-to-skip. Scenes with `EscapeScene = false` (all QTE scenes plus Apertura and AperturaPuerta) stay unskippable.

**Risk scale:**
- **Low:** dialogue scene, all actors present, no gameplay side effects.
- **Med:** QTE routing, alternates, forced switches, or callbacks that touch real bodies.
- **High:** randomness or solo-split logic, or the scene must run non-blocking for some players.

---

## 5. Per-scene co-op treatment

Abbreviations:
- **POV:** the player of `X` sees `<mode>`. `FP` = vanilla camera; `Head` = head POV on the scene actor; `Side` = side camera; `CF` = the `CameraFrom` view.
- **Absent:** what players without a character in the scene do.

| # | Scene | POV plan | QTE routing | Absent players: what they do | New content? | Risk |
|---|---|---|---|---|---|---|
| 1-3 | TheDreamA/B/C | Everyone: the Ross dream camera (DM or FP_Ross). No squad actors. | — | All watch (level start, nothing to do). | No | Low |
| 4 | HelicopterTrip | Ross: FP. Jones, Cole, Delgado, Church, Rawlings, Black: Head. | — | — | Ross stand-in body for other clients (Ross has no full body in this scene) | Low |
| 5-7 | FlashBackA/B/C | Everyone: DM camera (flash-back montage). | — | All watch. | No | Low |
| 8 | Landing | Ross: FP. All six: Head (Cole on the `Cole_2` actor). | — | — | Ross stand-in | Low |
| 9 | TombCollapses | Ross: FP. All six: Head. Body animations exist for every alternate (A-D), so the Head POV follows retries. | **Ross's player** (host if nobody holds Ross). Others see greyed prompts. | — | Ross stand-in. Patch `ShowChar` (alternate A f300) so it does not enable AI on human bodies. | Med |
| 10 | BloodDoor | Ross: FP. Church, Rawlings, Black: Head. | — | **Jones, Cole and Delgado players have had no body since `StartSayGoodbye`** (`alk_tomb/mapinit.lua:102-149`). In the scene: CF or Side. Before the scene: see section 6, alk_tomb. | **Yes** (Alpha players from the goodbye to the end of the level) | Med |
| 11 | MurielsTale | Ross: FP. Rawlings: Head. Others: CF, or Head on MurielGreen (a spectator option). | — | Players 3-4 have no body in the whole level (`alk_bunker_00` loads only Ross and Rawlings). | **Yes** (level-wide, section 6) | Low (scene) |
| 12 | RossDeath | Ross: FP. Delgado, Jones, Rawlings, Black: Head. Church and Cole: CF or Side (no actor). | — | Church and Cole players watch. | Ross stand-in. Optional short Church/Cole actor? No: no assets exist. | Med |
| 13 | RossDeathB | Delgado: FP. Black, Church, Cole, Jones, Rawlings: Head. Ross's player: CF (Delgado's view), or Side on `RossDeathBRossDead`. | — | Ross's player loses the body; hand over at WWII (`coop-ux-research.md` Act 1 handover). | Delgado stand-in | Med |
| 14 | Conversation | Delgado: FP. Five others: Head. | — | — | Delgado stand-in. Add a spawn-point guard so the scene does not replay on checkpoint loads. | Low |
| 15 | Pathofsouls | Cole: FP. Everyone else: Side on the `Soul`/`NaziSoldierC` actors, or CF. | **Cole's player** (host if nobody holds Cole). | Option A (simple): everyone frozen and watching. Option B (R4): the scene runs only on Cole's client; the others keep fighting the final Nazi wave (`EnemyGen "nazis_final"` is stopped in `PillBoxOnUse`, `mapinit.lua:239`, so co-op would keep it running) until #16 pulls everyone in. | B: yes (keep or add a wave). Cole's frozen body must be invulnerable. | A Med / B High |
| 16 | DelgadokillsRawlings | Cole: FP. Delgado, Jones, Church, Rawlings, Black: Head. The Rawlings player watches its own death. | — | After the scene: solo revive (`AfterRawlingKilled`). The Rawlings player is "dead" until revived. | Small: a "dying-spirit" view for the Rawlings player (Side on its own body) and a revive prompt for the others. Remove the solo lock in co-op (`campaign-structure.md` 5.2). | Med |
| 17 | BritishComando | Black: FP (walk-in uses `UsrEntity(0)`; co-op must walk Black's body). Others: CF or Side on `British`. | — | Watch (≈7 s, level end). | Black stand-in not needed (no other squad actor). Retarget `SetUsrPosAng` to Black. | Low |
| 18 | BritishComandoSpeech | Jones: FP. Five others: Head. | — | — | Jones stand-in | Low |
| 19 | RawlingsTorture | Rawlings: FP. Church, Cole: Head (Church also on alternate A). 4th player (no body in this 3-body level): Side on PsichicCommander. | **Rawlings's player** (host if free). The host decides `ChooseTortureLoop` (random) and broadcasts the alternate. `QTEDeadAndReplay` time fades are host-driven. | 4th player: spectator only (the level has 3 bodies). | Level-wide spectator or spirit role (section 6) | High |
| 20 | NaziSacrificeA | Church: FP. All others: CF or Side. | — | Jones, Delgado and Black players wait below. Cole and Rawlings players have been bodiless props (`mapinit.lua:38-59`) for most of the level. | **Yes** (Church climb section, section 6) | Low (scene) |
| 21 | NaziSacrificeB | Church: FP. Cole, Rawlings: Head. Jones, Delgado, Black: CF or Side. | — | Watch. Afterwards, `ReposPeople` AI-walks everybody, but `IgnoreUsrControl` is set only on `UsrEntity(0)` (`mapinit.lua:237`), so the patch must lock all humans for the walk. | Church stand-in | Med |
| 22 | BehemothDead (cru_river) | Church: FP. Others: Side on `BehemothDeadBehemoth`, or CF. | **Church's player** (host if free). | Option A: watch. Option B: non-blocking; others clean up the remaining flyers. | B: optional mini-wave | A Med / B High |
| 23 | BridgeCollapses | Delgado: FP. Black, Church, Cole, Jones, Rawlings: Head. | — | **After this scene Jones, Cole and Rawlings are gone for 4 levels.** With 4 players, at least one becomes bodiless (3 bodies). Players holding Jones, Cole or Rawlings are re-seated on the free bodies first. | **Yes** (cru_labyrinth to cru_catacomb, section 6). Delgado stand-in. | Med |
| 24 | CruzadersSpeech_A | Delgado: FP. Church, Black: Head. 4th player: CF or Head on TemplarioAmigo. | — | Spectator | Delgado stand-in | Low |
| 25 | CruzadersSpeech_B | Black: FP. Church, Delgado: Head. 4th: CF. | — | Spectator. The chain physics (`UsePhysics`) are local and only cosmetic [I]. | Black stand-in | Low |
| 26 | Apertura | Black: FP (walk-in on Black's body). Others: Side on the DM camera (it is cinematic: `DM_Scene_Apertura` is animated). | — | Short. Delgado and Church may keep playing (non-blocking is safe: no squad actor, no callback) [I]. | No | Low |
| 27 | Escalada | Church: FP (walk-in). Others: DM camera. | — | **Start of the Church solo.** Black and Delgado players stay below. Vanilla holds them, then sets them `bActive=false` at `TriggerBloodWar_3` (`mapcallbacks.lua:355-360`). | **Yes** (section 6, cru_sewers) | Med |
| 28-29 | DescensoA → DescensoB | Church: FP. Others: Side on `DescensoACruzadoA` / `DescensoBCruzadoA`. | **Church's player** (host if free). Both scenes carry QTE alternates and ReloadScene. Host broadcasts. | Black and Delgado players: run non-blocking (they are elsewhere anyway) and keep doing the gate content. | Yes (shared with #27) | Med-High |
| 30 | AperturaPuerta | Church: FP (walk-in). Black and Delgado: real bodies re-shown (`ShowChar`); they watch the DM camera, or Head is not available (no actor), so Side. | — | Reunion | Patch `ShowChar` f289 so it does not turn on AI for human bodies. | Med |
| 31 | TheRescue | Black: FP. Church, Cole, Delgado, Jones, Rawlings: Head. | — | Bodiless players since #23 re-seat on Jones, Cole or Rawlings at scene end. | Black stand-in. Spawn-point guard (plays on every load). | Low |
| 32 | BehemothDead (rom_outskirts) | as #22 | as #22 | as #22 | as #22 | as #22 |
| 33 | CenturiansTale | Rawlings: FP. Black, Church, Cole, Delgado, Jones: Head. | — | — | Rawlings stand-in. Forced-switch rule: the human holding Rawlings gets the FP view; if Rawlings is free, the host or a volunteer claims it before `SchFade`. | Med |
| 34 | TheAbyss | Church: FP. Others: Side on `TheAbyssCornisa`, or CF. | **Church's player** (host if free). | After the scene, the others must hold `LosetaPuenteA/B/C` against `LegionariosPuente*` (existing content, `mapcallbacks.lua:285-298`). Option: start that phase non-blocking during the QTE. | Mostly existing. Optional non-blocking start. | Med |
| 35 | TheTrap | Delgado: FP. Black, Church, Cole, Rawlings: Head. Jones: Head on `TheTrapDelgado` (mis-named actor). | — | — | Delgado stand-in. Lock all humans during `GoToFinalScene` (only `UsrEntity(0)` is locked). | Low-Med |
| 36 | IntoTheUnknown | Black: FP. Church, Cole, Delgado, Jones, Rawlings: Head. | — | — | Black stand-in | Low |
| 37 | TheEndA | Black: FP. Church, Delgado, Rawlings: CF or Side (no actors; Jones and Cole are scene-only and not playable). | — | Watch | Black stand-in for Side viewers | Low |
| 38 | TheEndB | Black: FP. Church, Delgado, Rawlings: Head. | — | — | Black stand-in. Global slow-motion is host-synced. | Med |
| 39 | TheEndC | Church: FP. Black, Delgado, Rawlings: Head. | — | — | Church stand-in | Low |
| 40 | TheEndD | Church: FP. Black, Delgado, Rawlings: Head. Credits: everyone on `CameraEnd`. | — | — | Church stand-in | Low |

---

## 6. Scenes and sections needing new content, by level [I] (proposals)

**Generic, reusable across levels:**
- **FP stand-in body** (2.8). Needed for all 23 multi-character scenes: #4, 8, 9, 10, 11, 12, 13, 14, 16, 18, 19, 21, 23, 24, 25, 31, 33, 35, 36, 37-40.
- **Side-camera rig** (2.9): one implementation, with anchors per scene.
- **Head-POV rig** (2.8 C), with per-character eye offset and calibration.

**Per level:**
- **alk_tomb (#10 BloodDoor):** from `StartSayGoodbye` to BloodDoor, the Jones, Cole and Delgado players have no body.
  - Proposal: an "Alpha detour" holding action. Keep their bodies active in a sealed side area (the `S_28..S_31` hidden sectors listed in `alk_tomb/mapinit.lua:28-37` are candidates [I]) against reused cultist groups, until Ross opens the blood door.
  - Fallback: spirit or spectator.
- **alk_bunker_00 (#11 MurielsTale):** the whole level has 2 bodies.
  - Proposal: players 3-4 are spirits (orbit camera and ping), or a small new "radio overwatch" objective.
  - Making Church and Black present is a large change (not loaded; `map.lua`).
- **wwii_pillboxes (#15, #16):**
  - Pathofsouls non-blocking defence (option B), by keeping `nazis_final` alive.
  - After #16, a dying-spirit view for the Rawlings player.
- **wwii_vigil_inside (#19):** 4th player spectator only (3-body level). Optional spirit "ping" role.
- **wwii_brandenburg (#20-21):**
  - Cole and Rawlings players have no body for most of the level.
  - During Church's climb, Jones, Delgado and Black players defend the gate base (reuse the `primera_oleada` / `segunda_oleada` groups activated by `AreaTrigger192_0` and `AreaTrigger161_0`, `wwii_brandenburg/mapcallbacks.lua:12-16, 27-29`).
  - Cole and Rawlings players: spirit, or keep their bodies active guarding the captive on the monument.
- **cru_river (#22, #23):**
  - Optional non-blocking Behemoth clean-up.
  - **#23 opens the largest gap:** up to 1 bodiless player through cru_labyrinth, cru_sewers, cru_keep and cru_catacomb. Proposal: spirit role, or a new "lost squad" parallel objective. The latter is large; the orphan design note `cru_catacomb` `Tag_05` (368-380) already imagines a rescue.
- **cru_sewers (#27-#30):**
  - Church solo (climb, ward, Descenso QTEs, door).
  - Black and Delgado stay active (drop `bActive=false` at `TriggerBloodWar_3`) and hold the gate against new crusader and cultist waves until AperturaPuerta.
- **rom_outskirts (#32):** optional non-blocking Behemoth clean-up.
- **rom_palace_01 (#34):** optional; start the existing plate and legionary phase during the QTE.
- **No new content needed (beyond the generic items):** alk_desert, alk_final, wwii_biggates, wwii_mosque, wwii_mosque_inside, cru_labyrinth scenes (bodiless 4th player aside), cru_chapel, rom_palace_02, sum_ziggurat_05, sum_end.

---

## 7. Related scripted sequences outside the scene system (not catalogued above) [O]

These are AI walks or camera tricks during gameplay. In co-op they need "lock all humans" instead of `UsrEntity(0).IgnoreUsrControl = 1`:

| Level | Sequence |
|---|---|
| alk_tomb | goodbye walk (`mapinit.lua:102-162`) |
| alk_bunker_01 | `GoToRawlings` (`mapinit.lua:52-64`) |
| alk_final | `StartAICinematic` / `EndAICinematic` (`mapinit.lua:123-147`) |
| wwii_pillboxes | `mapinit.lua:274`, `663` |
| wwii_vigil_inside | `PsichicCommander.EndOfBitch` walk (`scripts/chars/psichiccommander.lua:360-373`) |
| wwii_brandenburg | end walk (`mapinit.lua:124-270`) |
| rom_palace_02 | `GoToFinalScene` (`mapinit.lua:7-13`) |
| rom_chamber | intro (`mapinit.lua:17-50`) |
| sum_ziggurat_01 | flying-cultists sequence (`mapinit.lua:29-41`), Jones walk (`mapinit.lua:254`) |
| sum_ziggurat_03 | astral hint camera (`mapinit.lua:54-126`) |
| sum_ziggurat_04 | urn walk (`mapinit.lua:90-117`) |
| sum_ziggurat_meat | end walk (`mapinit.lua:68-100`) |
| sum_end | credits camera (`mapinit.lua:58-92`) |

In-combat grab QTEs (`QTE.InGameQTE`, `qte.lua:282-413`) are separate from scenes (see `coop-ux-research.md` 5.6).

---

## 8. Unknowns [U]

1. How `EntityLink` places the camera on a linked entity (origin or a camera node) and whether it can follow an entity that is itself `LinkModel`-linked.
2. Whether a `"WithLife"` helper entity needs a model, and whether `"FCam"` or `"Cam"` accept `LinkModel`.
3. Whether `NodePosHierarchy_<name with spaces>` resolves, and the axis convention of `NodeAngHierarchy_` for head bones (the eye offset and angle fix must be calibrated in game).
4. Animation frame rate (25-30 fps inferred), and the field holding a scene's current animation time (needed for drift correction).
5. What the FP actor models contain (arms only or more) and their node names. This decides how a stand-in body can be attached.
6. Whether an `"AstralCam"` can `LinkToEntity` a `WithLife` scene actor.
7. The meaning of the 5th argument (100, 350) that some scenes pass to `Scene.CreateLocalAction`, where the function expects `Loop`.
8. How vanilla re-activates bodies after scenes that call `HideChars` twice (2.10).
9. Where the Bink videos `Intro.bik` and `Prologue.bik` are triggered (engine side).

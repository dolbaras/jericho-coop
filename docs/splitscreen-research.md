# Local split-screen for Clive Barker's Jericho: research

Date: 2026-10-20. This was read-only research. Nothing was run, and no game or mod files were changed.

Sources:
- decompiled vanilla Lua (`work/src`)
- SMOD engine docs (`downloads/smod-103/x/Modding tools and resources/*.txt`)
- a static scan of `work/game/bin/Jericho.exe`: strings, xrefs and a linear capstone disassembly of `.text`, done with throw-away scripts (not in this repository)
- the co-op mod (`mod/lua`, `mod/native`)

Tags:
- **[V]** verified statically (address or file cited)
- **[I]** inference
- **[?]** unknown; needs a runtime test

Note on the exe: it is SecuROM-protected. Several functions in `.text` are "stolen" thunks (`jmp dword ptr [0x11a....]`), for example the backends of `Game.GetCam` (0x4207c0) and `Input.Bind` (0x417040), and 0x455630. The Scorer draw routine (0x495c00) is called only from `.securom`. The static picture is therefore incomplete. Anything not found in it is "not found in visible code", not "absent".

---

## 1. Evidence

### 1.1 Split-screen remnants exist in the engine [V]

`Game Parameters.txt` lists, and the exe registers, four split-screen parameters. Each parameter object has its value at +0x10.

| Param | Object / value | Registered at | Description string |
|---|---|---|---|
| `SplitScreen` | 0x7bfe64 / **0x7bfe74** | 0x6acc50 | "Is split Screen" |
| `R_SplitScreen` | 0x86331c / **0x86332c** | 0x6cfe30 | "Split Screen" |
| `R_SplitScreenCamera` | 0x8633c4 / **0x8633d4** | 0x6cfe70 | "Split Screen Camera Index" |
| `R_SplitScreenUpdate` | 0x863364 / **0x863374** | 0x6cfeb0 | "Split Screen Update Target" |

These are all the code references in the file. A raw dword search across every section found no others.

- **`SplitScreen` (0x7bfe74)** is read in 9 functions:
  - **0x495c00, Scorer draw (`..\..\Menu\Scorer.cpp`).** It loops `for i = 0; i < (SplitScreen ? 2 : 1)`. For each user it:
    1. gets the user's camera name with `World::GetCam(i)` (0x4207c0)
    2. asserts `e->IsType(TYEN_CAMERA)`
    3. makes that camera the render camera (0x599700)
    4. sets a viewport in 640x480 logical units through 0x59b8b0: **`(0, 0, 640, 240)` for user 0 and `(0, 240, 640, 240)` for user 1**, i.e. a top/bottom split
    5. draws `Scorer[i]` (0x4948a0, 0x4925a0)

    This is a working 2-player HUD split.
  - **0x422ea0, `World::SetCam(id, name)`.** Outside split mode, it switches the render camera immediately for any id. In split mode it only stores the per-user camera.
  - **0x423440, world frame (`..\..\World\World.cpp`).** `if (SplitScreen && R_SplitScreen)`:
    - it sets `R_SplitScreenUpdate` from the game timer (1 while the game runs, briefly after a pause)
    - it sets `world+0x78 = R_SplitScreenCamera`
    - it makes **camera slot `[R_SplitScreenCamera]` the render camera**
  - **0x490b40 and 0x4925a0 (Scorer).** They show `"XBox_NoPad_MP_Msg_1"`, the "insert pad" message for player 2. The parameter `XboxNoPadMsgP` reads "for player 2".
  - **0x402280 (loading tips), 0x413290, 0x430cb0 (entity update).** These contain Scrapland leftovers (`LoadingTips_Out_%d`, "ABIndoor", "Orbit", "Bank", "Police", "Ciudad"). This engine is the Scrapland engine (`ScrapEngMain.cpp`, `ScrapEngModel.cpp`), and the split-screen code is inherited from it. [I]
- **`R_SplitScreen` (0x86332c)** is read only in 0x423440 and in 0x5adad0 (`ScrapEngModel`). When it is on, that function reports every model as visible/updated, so per-camera visibility caching is bypassed. That suits rendering from several cameras.
- **`R_SplitScreenCamera`** is read only in 0x423440.
- **`R_SplitScreenUpdate` is written but never read** anywhere in the visible code. Its consumer, presumably the render-target composition of the two views, is missing or hidden. [V for visible code, ? overall]

### 1.2 Multi-user data structures: 4 users [V]

- **User entities:** the world keeps `UsrEntities[4]` at `world+0x2b0`. The assert string is `UsrEntities[i]->IsType("WithLife")` in `World/World.h`.
  - `Game.UsrEntity(id)` is the Lua wrapper 0x5363c0, which calls 0x427470 with no bounds check.
  - The array is rebuilt every frame in 0x423440 from all `WalkChar`s whose user index (0x455630, stolen) is 0..3: `cmp eax,3; ja skip; mov [world+eax*4+0x2b0], ent`.
  - So a body with `UsrControl = 1` should become `Game.UsrEntity(1)`. [I, high]
- **Cameras:** there are 4 per-user slots. Each holds a camera name (0x80 bytes at `world+0x7c+id*0x80`) and a camera position (`world+(0x9f+3*id)*4`). They are set by `World::SetCam` (0x422ea0), which Lua reaches as `Game.SetCam(id, name)` through wrapper 0x536c80 (format `"is"`). `Game.GetCam(id)` is wrapper 0x536ce0.
- **Scorer (HUD):** there are 4 instances of 0x170 bytes, allocated in 0x495e40 with ids 0..3. The getter 0x48f7a0 accepts ids 0..3, and every `Scorer.*(id, ...)` takes that id. `Scorer.SetMPFunc(id, func)` (0x53ddd0) is another per-user leftover.
- **Pads:**
  - `Input\PcPad.cpp` maps pad indices 0..3 to the device names `Joy1`..`Joy4` (0x41a530). Each has its own binding list, the params `Joy1`..`Joy4`.
  - All 4 XInput pads are polled. 0x407360 loops over the four 0x24-byte states at 0x7bf6fc.
  - `XInputGetState` and `XInputSetState` are imported **by ordinal** from `XINPUT1_3.dll` (ordinals 2 and 3), at IAT slots 0x6f4404 and 0x6f4408, through the thunks 0x594cc0 and 0x594cba.
  - `Input.Rumble(id, ...)` calls `XInputSetState(id)` and asserts `id < XINPUT_USER_MAX_COUNT` (0x419c90).
  - Keyboard and mouse go through DirectInput8.

### 1.3 Gaps that prevent native split-screen

- **Only one 3D render per frame [V].**
  - The game's draw callback (rdata 0x6f91cc points to 0x402790, which jumps to 0x59c1c0 in `ScrapEngMain.cpp`) does `SetRenderCam(GetActiveCam())` and then `_renderframework->Render()` (vtable +0x58) once.
  - The only viewport setter, 0x5d18e0, is called only from the Scorer paths: 0x59b740 (rect) and 0x599860 (reset). It also serves Scorer 3D models (0x48cfe0).
  - In visible code, nothing renders the world into a half-screen viewport or a second camera pass.
  - So setting `SplitScreen=1` and `R_SplitScreen=1` is expected to produce **one full-screen 3D view, from camera `R_SplitScreenCamera`, with two HUDs squeezed into its top and bottom halves**. [I, high; ? until tested]
- **`Input.ResetToSplit` is an empty stub [V].** In 0x53b130 it only parses zero arguments and returns. The split-screen binding preset was removed from the PC build.
- **`Input.SetActionSet(name)` takes no user id [V]** (0x53b210, format `"s"`). There is a single global action set ("Walk", "Menu", "Inactive" and so on), so menus and cutscenes switch the input mode for everyone.
- **`PlayerPad` ("Index to the pad that will be used in the game", 0x7bf238) is registered but has no reader in visible code [V].** The Lua sets it only on X360, as single-player pad selection (`mainmenu.lua:102-110, 379`). It is not a split-screen feature.
- **Whether a `WalkChar` with `UsrControl = 1` is driven by `Joy2` [?].** The binding internals (0x417040) are SecuROM-stolen.
  - `QuickConsole.free` sets `cam.UsrControl = 1` to take camera control away from user 0 (`quickconsole.lua:52-61`). That suggests user index 1 is accepted, with nothing reading it by default.
- **Lua assumes user 0 everywhere [V]:**
  - 179 calls to `Game.UsrEntity(0)`; every `Game.GetCam`/`SetCam` call uses 0; 15 calls to `Input.Bind(0, ...)`; `Input.GetDefinedList(0, ...)`
  - the whole HUD is built with `Scorer.NewItem(0, ...)`
  - hard-coded FP models `"0FP_Cole"` and `"0FP_Delgado"`
  - `Team.CreateMainChar` creates the single `"MainCam"` (`FCam`) and calls `SetCam(0, ...)`

  Some helpers do take an id:
  - `MakeFP.MakeFPObject(Typo, id)`, which creates `id..Typo`, i.e. "0FP_x" and "1FP_x"
  - `MakeFP.LaunchFpsAnm(id, ...)`, `Scene.StickCamera(id)`, `Scene.SetUsrPosAng(id)`
  - `Team.RevivePlayer`, which uses `obj.UsrControl` as the id
  - `threadsblack.lua:130`, which calls `GetCam(usr.UsrControl)`

  These helpers are design remnants. The game logic itself is single-user (see also `mod/docs/usrentity-audit.md`).
- **No split-related settings in any config or script [V]:** `R_Split`, `SplitScreen` and `ResetToSplit` do not appear in `work/src` or in the game's cfg files.

### 1.4 Conclusion on native support

- The engine has **data-level support for 4 local users**: user entities, cameras, HUDs, pads.
- It has a **working 2-player HUD split**: top/bottom, 640x240 each.
- The **3D side of split-screen is not present in visible code**. The engine renders one camera per frame. `R_SplitScreenUpdate` hints that an alternate-frame or render-target scheme existed, probably in Scrapland's console build, but the code that would read it is missing. [I]
- The PC input layer has its split preset stubbed out and a global action set.
- Native split-screen is **not usable as-is**. Making it work means writing the missing renderer and input parts yourself (approach (a) below).

---

## 2. Approaches, ranked by effort and risk

### (b) Two game instances side by side, on top of the existing online co-op. **Recommended.**

Effort: low to medium. Risk: medium. Most of the code already exists.

Each player gets a full instance with its own camera, HUD, FP weapon, cutscene view, audio listener and save directory. That is exactly what online co-op already gives. The two instances connect over 127.0.0.1 through the existing ENet session.

Already in place [V]:
- `JERICHO_MULTI`: a second instance is allowed (the `FindWindowA("MercuryGameClass")` check is bypassed in `dinput8_proxy.c`)
- `JERICHO_WINPOS` / `JERICHO_WINSIZE`: window placement and client size (`display_hooks.c`)
- `JERICHO_BACKGROUND` / `Net.CoopBackground`: the instance keeps running without focus (WM_ACTIVATE is hidden), and keyboard/mouse/`GetAsyncKeyState`/`SetCursorPos` are blocked while the window is not really in front (DirectInput `GetDeviceState`/`GetDeviceData` vtable hooks)
- `JERICHO_ADAPTER`, frame cap (`-R_LimitFPS`), per-instance save directory (`JERICHO_COOP_SAVEDIR`)
- auto host/join through `cfg.auto`
- `tools/run_pair.ps1`, which already starts host and client side by side

Missing:
1. **Per-instance gamepad routing (XInput).** XInput ignores window focus, so today both instances would read every pad.
2. **A "pads only" mode for instance 2.** Keyboard and mouse must be blocked even if its window becomes foreground.
3. **A window for instance 2 that never takes activation, plus a borderless half-screen layout** on the main monitor.
4. **A one-click launch:** a menu entry or launcher that starts instance 2, auto-joins and auto-readies.
5. **Audio policy** for two FMOD instances.

### (c) Other options

- **(c1) Nucleus Co-op / SplitScreen.Me handler.** This generic tool does (b): it launches instances, places windows and isolates input with its own ProtoInput hooks. It would mean writing a handler script. However, it injects its own dinput8/xinput hooks, which would clash with our dinput8 proxy, and it adds an external dependency. Effort is low to medium, but control and polish are worse than doing (b) in our own DLL. Worth knowing; not recommended.
- **(c2) Single instance, puppet input plus a D3D alternate-frame composite.** This is in effect (a) without the native flags; see below.

### (a) Native in-engine split-screen in one instance. **Not recommended.**

Effort: very high. Risk: very high. What it would take:

- **Rendering.** Each frame, alternate the render camera: either `R_SplitScreenCamera` 0/1 with `SplitScreen=R_SplitScreen=1`, or switch `SetCam(0, ...)` from the DLL. In the D3D9 `Present` hook, `StretchRect` each frame's back buffer into one half of a composite surface and present the composite every second frame. Consequences:
  - each player gets half the frame rate
  - temporal and accumulating effects (glow, HDR adaptation, motion/monitor blur, `RT_Deformation`) mix the two cameras
  - the FOV/aspect must be adjusted (`CameraViewScaleX/Y`, `CameraDefViewAspect`)
  - the audio listener and LOD jump every frame
  - only one FP weapon entity is shown per frame, so the right one has to be toggled each frame
- **HUD.** Either keep `SplitScreen=0` and draw `Scorer[0]`/`Scorer[1]` on alternate frames, which means rebuilding the HUD in Lua for id 1, or use the native top/bottom Scorer split. The native split only works if the composite is top/bottom and both HUDs are drawn every frame.
- **Player 2's body.** Drive it as a co-op "puppet" from pad 2 through the DLL. The mod already moves puppets through `InCtrl_Walk`/`InCtrl_Str`. Alternatively set `UsrControl = 1` and hope that `Joy2` drives it [?].
- **Logic.** Patch every `UsrEntity(0)`, `GetCam(0)`, `Scorer(0)` and `SetActionSet` dependency, plus cutscenes, QTEs, menus and pause.

All of that re-implements, inside one process, what the client instance in (b) already does. The only advantage is a single GPU context.

A cheap probe, to settle the "hidden code" question once running the game is allowed: on a test level, in the console, run

```lua
Game.Set("SplitScreen",1); Game.Set("R_SplitScreen",1)
local c=Game.CreateEntity("Cam1","FCam"); Game.SetCam(1,"Cam1"); Game.Set("R_SplitScreenCamera",1)
```

Watch for: two HUDs in the top and bottom halves; whether the 3D view is still full screen; whether it switches to `Cam1`. Also set a squad member's `UsrControl = 1` and check whether `Game.UsrEntity(1)` returns it and whether pad 2 moves it. Expected result: HUD split only, no 3D split. [I]

---

## 3. Implementation plan for (b)

### 3.1 Native (dinput8 proxy, `display_hooks.c` or a new `pad_route.c`)

1. **XInput router.**
   - Patch the IAT of `XINPUT1_3.dll` ordinals 2 (`XInputGetState`) and 3 (`XInputSetState`); the slots are 0x6f4404 and 0x6f4408.
   - `find_iat_slot` currently skips ordinal imports (`IMAGE_SNAP_BY_ORDINAL ... continue`), so it needs an ordinal-aware variant that compares `IMAGE_ORDINAL(names[i].u1.Ordinal)`.
   - New env var `JERICHO_PADS`: a comma list of physical pads that become virtual pads 0..n-1 (`"1"` for player 2), or `none`. With no value, behaviour is unchanged.
   - Virtual ids with no mapping return `ERROR_DEVICE_NOT_CONNECTED`. `XInputSetState` (rumble) is remapped the same way.
   - Instance 1 gets `JERICHO_PADS=0` (or `none` for keyboard/mouse only). Instance 2 gets `JERICHO_PADS=1`.
2. **Pads-only input.**
   - New env var `JERICHO_KBM=0`: always zero DirectInput keyboard/mouse state, drop buffered data, return 0 from `GetAsyncKeyState`, make `SetCursorPos` a no-op.
   - This reuses the `bg_*` hooks with a "never in front" predicate. Do not acquire the mouse exclusively; check `MouseExclusive` and pass `-MouseExclusive:0` to instance 2.
3. **Non-activating window and borderless layout.**
   - In the `CreateWindowExA` hook, add `WS_EX_NOACTIVATE` for instance 2 and strip `WS_CAPTION | WS_THICKFRAME` for both when `JERICHO_BORDERLESS=1`.
   - Keep `bg_ShowWindow` from activating the window, and keep `JERICHO_BACKGROUND=1` on both.
   - Instance 1 must stay foreground for keyboard/mouse. Clicking instance 2 must not take activation away from it.
   - Layouts on a 1920x1080 monitor:
     - **Milestone 1:** two 960x540 windows at 16:9, letterboxed, with no aspect risk.
     - **Then:** side by side at 960x1080 or top/bottom at 1920x540, after checking how the engine handles non-16:9 aspect (`PhysicalAspectRatio`, `CameraDefViewAspect`, the 640x480 logical HUD, FOV).
4. **Audio (optional).** Instance 2 starts muted (`-SoundMainVolume:0 -MusicMainVolume:0 -VoiceMainVolume:0`), or it plays at a lower volume. Better: hook `FMOD_System_Init` (fmodex is imported by name) and call `FMOD_System_SetDriver` from `JERICHO_AUDIO_DRIVER`, so player 2 can use headphones.
5. **Lifetime.** Put instance 2 into a job object owned by instance 1, so closing one closes both, or let the co-op session end trigger `Game.Exit` in the peer.

### 3.2 Lua and launcher

6. **A "Split screen" entry in the co-op lobby (`coop_menu.lua`).** It hosts on the loopback interface and calls a new `Net.SpawnLocal(cfg)`. That native function:
   - builds a `CreateProcess` call for `Jericho.exe` with the same `-InitLuaLine` boot line
   - sets `cfg.auto=join`, `addr=127.0.0.1`, the nickname "P2" and the wanted character
   - sets `-PlayVideos:0`, the window size and position, and the env vars from steps 1-3
   - starts the process **after the host's level has loaded or its device has been created**, as `run_pair.ps1` does

   The new instance auto-readies. Character select for P2 can stay in the host's lobby, which already has character select. Until this exists, a `run_local_split.ps1` derived from `run_pair.ps1` will do (main monitor, same GPU, auto host/join).
7. **Session and saves.** Nothing new is needed. The host save is the co-op save, and P2 is a normal client with its own `JERICHO_COOP_SAVEDIR`.

### 3.3 Test order

The owner's rules apply: test on the 2nd monitor, muted, and nothing is published until it works.

1. Unit-test the XInput router on a single instance: with `JERICHO_PADS=1`, pad 2 drives player 1 and pad 1 is ignored.
2. Run two instances on the 2nd monitor (the existing `run_pair` setup) with routing on, and check that each pad drives only its own instance.
3. Same as step 2, with both instances on the dGPU.
4. Move to the main monitor with the borderless layout, then try the full-height layouts.

### 3.4 Main risks

- **Desktop freeze with two D3D9 instances.** It happened once (2026-10-18). It did not recur after the second instance moved to the iGPU monitor, startup became staggered, and focus is no longer touched. A real split-screen puts both windows on the **same monitor and GPU**, which has not been tested yet. Mitigation: stagger startup, never move or focus a window during device creation (create it in place with `WINPOS`), frame cap, `-Antialiasing:0` on instance 2, and staged tests with the owner's consent.
- **Performance.** Two full engine instances double CPU, draw-call and memory cost: two 32-bit processes of about 1-1.5 GB each [I]. The pixel count is about the same as one full-screen window. A 2007 engine on modern hardware should cope, but the iGPU runs showed that 8x MSAA alone was enough to make the iGPU instance unplayable.
- **Pad reading in a background instance.** XInput itself works without focus [V general]. Whether the engine stops polling pads while it thinks it is inactive is hidden by `background_wndproc` [?]. Test in step 2.
- **Focus edge cases.** Alt-tab, the Windows key, or a click on instance 2 could leave keyboard/mouse attached to nothing. `WS_EX_NOACTIVATE`, plus a hotkey to bring instance 1 back to the front, covers this.
- **Aspect ratio.** HUD scaling, FOV, and Bink videos in non-16:9 halves [?]. Milestone 1 avoids this with letterboxed 16:9 windows.
- **Double audio.** Mute player 2, or route it to another device.
- **Everything else already works**, because this is the online co-op: cutscenes from each player's own perspective, QTE ownership, puppets.

---

## 4. Verdict

- **Native split-screen:** the engine has Scrapland-era split-screen remnants:
  - 4 user/camera/HUD/pad slots
  - a working 2-player top/bottom HUD split behind `SplitScreen`/`R_SplitScreen`
  - a camera-index parameter

  The 3D renderer draws one camera per frame. The split render-target consumer (`R_SplitScreenUpdate`) and the PC input preset (`Input.ResetToSplit`) are missing or stubbed. **It is not usable natively.** Making it work means writing an alternate-frame D3D compositor plus a single-instance second player, which is very high effort and risk.
- **Recommended path:** **two instances in borderless half-screen windows, joined through the existing co-op netcode on localhost.** The new pieces are an XInput pad router (an ordinal IAT hook on `XINPUT1_3` #2/#3), a pads-only, non-activating mode for instance 2, a borderless layout, and a one-click "Split screen" launcher in the lobby. Most of the infrastructure already exists (`JERICHO_MULTI/WINPOS/WINSIZE/BACKGROUND/ADAPTER`, DirectInput gating, `run_pair.ps1`). The main risk is GPU and desktop stability with two D3D9 instances on one GPU and monitor, so testing needs to be staged.

---

## 5. What was built (0.1.2)

Approach (a) after all, in one game: `native/split.c` (alternate camera slot per frame, each frame squeezed into its half before the HUD pass, the late power-icon draws moved to their half) and `lua/coop_split.lua` (user 1's body, camera, scorer 1, first-person model with `id = 1`, pads, squad switching, powers run as user 1, down/revive, story moves). The two-window approach (b) was dropped. See `docs/scrapland-engine-audit.md` for the engine details found later.

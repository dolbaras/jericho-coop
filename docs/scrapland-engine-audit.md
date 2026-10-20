# Scrapland engine leftovers in Jericho.exe: audit for the co-op mod

Date: 2026-10-20. Read-only static research. The game was not run, and no game or mod files were changed.

**Sources**
- `work/game/bin/Jericho.exe`: the SecuROM build, SHA `7fb5…`
- a read-only copy of the existing Ghidra project (`work/ghidra`), queried headless (`-readOnly -noanalysis`)
- capstone and pefile scans: strings, RTTI, luaL_Reg tables, xrefs, IAT call sites
- vanilla Lua in `work/src`, and the SMOD docs (`Game LUA API.txt`, `Game Parameters.txt`)
- the mod: `mod/lua`, `mod/native`

**Tags**
- **[V]** verified statically (address cited)
- **[I]** inference
- **[?]** needs a runtime test

**SecuROM caveat (it matters in this report).** Many net and render functions in `.text` are only thunks into `.securom`. Example: `jmp [0x11a2884]` jumps to 0x1201cd0, which runs `push ret; call 0x950e10`, the SecuROM VM dispatcher, so their bodies are virtualized bytecode. Two consequences:
- "Not found in visible code" does not mean the code is absent.
- Those functions cannot be read or easily patched.

Static analysis only (Ghidra and small scripts on a copy of the exe; the scripts are not part of this repository).

---

## 0. Summary

1. **The engine has its own UDP netcode.** It is the complete Scrapland client/server: `Net\GameServer.cpp`, `ManServer.cpp`, `ManClient.cpp`, `msgman.cpp`, `NetData.cpp` and `transport.cpp`, built Feb–May 2006.
   - It uses raw WinSock (`WSOCK32`) and one non-blocking broadcast UDP socket. There is no DirectPlay and no TCP.
   - It is wired into the main loop and has LAN browse, a master server and a chat layer.
2. **The entity replication is a generic framework, but it is empty in Jericho.**
   - The server sends each client a snapshot built from three virtual methods on every entity named `net<N>`: relevance at vtable +0x204, write at +0x200, read at +0x208.
   - In Jericho these are **stubs** (`ret 0xc`, `mov al,1; ret 4`, `ret 8`) for every relevant class: Obj, WithLife, WalkChar, Missile, FP, all PxBody classes and Ragdoll. Only `cItemEntity` (Scrapland pickups) has real code.
   - The session layer is Scrapland-only: ship descriptors (`Motor0..3`, `WeaponBay`), "DeathMatch", a disconnect that loads `Levels/Ciudad`, and the default server map `Levels/FZ`.
   - The core functions (IsServer/IsClient/InitClient/send/bind) are SecuROM-virtualized.
   - There is no interpolation, prediction or dead reckoning for remote entities.
   - **Recommendation: ignore it as a base and keep ENet.** Borrow only two ideas: per-recipient distance relevance, and putting unreliable state in the same datagram as reliable messages.
3. **The useful leftovers are for single-process split screen.** Three are new findings:
   - **FP models are tied to a user index through a hidden FP-entity property `id`** (default 0). The mod's `1FP_*` models are still user 0's, so set `fp.id = 1`.
   - **The sound engine supports 2 listeners, and each sound uses the nearest one.** The world feeds listener *i* from camera slot *i* every frame, so player 2's audio should work with no extra code.
   - **`R_SplitScreen=1` turns off visibility-gated updates of animation, physics and AI at 12 call sites.** This is the original design for alternate-frame split screen, which is exactly what `split.c` does.
4. **The renderer can mechanically run twice per Present.** `CMotorApp::Render` holds its own BeginScene/EndScene, and `Present` is outside it. A full-frame-rate split (two world passes per frame) is therefore possible as an experiment. The obstacles: the HUD is drawn inside the same pass, the LimitFPS busy-wait is inside it, and temporal effects would mix the two views.
5. **Engine C++ hard-codes `UsrEntity(0)` at about 28 sites.** These are boss and enemy AI, the follow camera, missiles, ragdolls and sound events. This explains some behaviour that is "player 1 only" for both online clients and split-screen player 2.
6. **There is no world serialization.** "Hard save" is only the 0x24004-byte save-var blob. Join-in-progress or resync needs the mod's own snapshot. The mod already syncs save vars.

---

## 1. Networking remnants

### 1.1 Transport [V]
- **Imports.** `WSOCK32.dll`: WSAStartup, WSACleanup, socket, bind, closesocket, setsockopt, select, sendto, recvfrom, gethostbyname, gethostbyaddr, inet_ntoa, htonl, htons, ntohs. IAT 0x6f43c4–0x6f43fc, thunks 0x594c60–0x594cb4.
  - There is **no** connect, listen, accept, send or recv, so there is no TCP.
  - There is no `dplayx` or `dpnet` import and no DirectPlay GUID string.
- **Socket.** One global socket at 0x7c2c9c, created in 0x4860e0:
  - `socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)`
  - `ioctlsocket(FIONBIO=0x8004667e, 1)`: non-blocking
  - `setsockopt(SOL_SOCKET, SO_BROADCAST)`
- **Visible call sites.**
  - recvfrom: 0x486d89, 0x486e68, 0x487079
  - sendto: 0x48652e, 0x486de5, 0x486e36, 0x5d9ef2
  - **WSAStartup, bind, select and gethostbyname have no visible caller**, so they are only called from SecuROM VM code.
- **Mode** at 0x7c2ca0: 1 = server, 2 = client, 3 = LAN browser.
  - The receive function 0x486d20 handles all three modes.
  - The browser broadcasts to `255.255.255.255` (the default of `Net.InitBrowser`) and accepts 0x5c-byte server-info replies.
  - `Server %02x '%s':%s (%d/%d) Ver %d.%d at %s:%d`
- **Master server.** 0x486ae8 parses datagrams that start with four zero bytes:
  - `}`: an IP:port list ("IP From Master").
  - `~`: a command string, passed to a callback (0x7c2cb4 → the Lua `MasterCommandFunc`).
  - Heartbeat `HB=%d,%d:%d` (game id, version, port) every `HeartbeatTime` (60 s), in the server frame 0x4822a0. Default `MasterServerPort` is 5000.
- **Command line** (0x402ce0): `-server [map]` starts a server, with default map `Levels/FZ`. `-dedicated` starts a dedicated server; app flag bit 2 then skips input.

### 1.2 Protocol [V where cited, else I]
- **Datagram header** (validated in 0x485ab0 and 0x4845a0):

  | Byte(s) | Meaning |
  |---|---|
  | 0 | 7-bit channel/peer id, plus bit 0x80 = alternating ack toggle |
  | 1–2 | u16 length of the reliable part |
  | 3 | 7-bit reliable sequence |
  | 4 | message type: 6 = connect/hello, 7 = browse query |

  - Connect carries `NET_GAME_ID` **0xCEBA** and `NET_GAME_VERSION` **0x101**. Both are asserted in `ManServer.cpp`.
- **Reliability.** Each datagram carries **one reliable chunk (seq+1 only) plus one unreliable chunk**. It is accepted only if `seq == last+1 (mod 128)`.
  - So reliability is **stop-and-wait with one reliable message in flight** per peer [I].
  - There is no fragmentation. Packets are built in fixed 24000-byte `StaticBuffer`s, and an assert fires when a buffer is reused while still in use.
- **Limits** (parameters; default values from `Game Parameters.txt`):

  | Parameter | Default | Notes |
  |---|---|---|
  | `ClientPPS` | 20 | client packets per second, range 1..20 |
  | `ServerDataRateLimit` | 20480 B/s | |
  | `ServerMinSendDelay` | 5 s | ×1000 gives the keepalive/resend interval at 0x78af9c, used by 0x4847c0 |
  | `NetTimeOut` | 240000 ms | |
  | `DefaultServerPort` | 28086 | 0x6db6 is the fallback in 0x482030 |
  | `DefaultMaxPlayersOnServer` | 10 | |

- **Security.** The default passwords are plaintext: `ServerPassword`=`dtritus`, `ClientPassword`=`sesame`.
  - There is "remote control": `SendCtrlString`, `ClientRemotePassword`, `ServerRemotePassword`.
  - A master `~` packet invokes a Lua callback.
  - All of this is dormant unless a script calls `Net.InitServer`, `InitClient` or `InitBrowser`. Keep it that way.

### 1.3 Classes and wiring [V]
- **RTTI classes**:
  - **`cServerNetManager`** (vtable 0x70be00). Despite the name, this is the client-side proxy of the server:
    - 0x482820 receives a server packet: snapshot entries, then a message switch (0 change level, 1 resource list, 3/4 user/chat strings, 5 user descriptors, 6 delete entity, 7 goodbye)
    - 0x482e60 sends the local player's state
    - 0x4825d0 sends the connect request
  - **`cClientNetManager`** (vtable 0x70bfa0). The server-side object for one client:
    - 0x483730 receives the client's state and its hello (game id, version, name, ship descriptor)
    - 0x483c70 builds and sends the per-client snapshot
    - 0x4836a0 SetLocalData
    - destructor 0x483530
  - `cUserNetManager` (vtable 0x70c1cc): `msgman.cpp`, purecall slots.
  - Network HUD widgets: `cNetStatsScorer` (ping label "APing", `ShowClientPing`) and `cChatScorer` (`ChatMsgPersistence`, quick chat).
- **Main loop.** `CApp` frame 0x4027a0 (CApp vtable 0x6f91a4, slot +0x10):
  - after the game ticks, if `IsServer()` (0x481f90, stolen) and app flags bit 1 are set, it runs the server frame 0x4822a0
  - while `IsClient()` (0x4819c0, stolen), it runs the client frame 0x481cf0
  - `Game.GetNetFlags()` (0x537bb0) returns the app flags at `[0x7bcab4]+0x30` as three values: (net, server, dedicated). These are *not* per-entity net flags.
- **No vanilla script starts the engine net.** The only Lua use is `QuickConsole.reload`, which calls `Net.IsServer` and `Net.IsClient` (`quickconsole.lua:23-27`).

### 1.4 The `Net` Lua table at 0x72e4f8 [V]
Each backend is a small wrapper that parses arguments with `luaL_checkargs` (0x661fe0) and returns through 0x52df90.

| Entry | Wrapper | Format | Backend | What it does | Mod status |
|---|---|---|---|---|---|
| InitServer | 0x53b3e0 | `sii` (map, players, port) | 0x482030 | Fails if client mode is on. Binds the port (default 28086) through stolen 0x4859e0, **loads the map** (0x49cc000 thunk), allocates two 24000-byte buffers, starts the heartbeat. | original |
| CloseServer | 0x53b440 | `s` (level) | 0x4821d0 | Sends goodbyes, frees clients, loads the given level | original |
| ServerChangeLevel | 0x53b340 | `s` | 0x481fd0 (stolen) | | original |
| IsServer | 0x53b490 | – | 0x481f90 (stolen) | | original |
| GetServerData | 0x53b4d0 | – | 0x7c2078 / 0x7c2178 / 0x7c2278 | name, IP, port | replaced |
| AddResource | 0x53b390 | `s` | 0x485280 | Registers a resource name (index 0..255) and broadcasts it | replaced |
| ModifyUsrData | 0x53b2f0 | `i` | 0x485900 | Re-sends a client's descriptor | replaced |
| GetBotName / GetObjName | 0x53b540 / 0x53b5c0 | – | 0x4854a0 / 0x485430 | Next free `net%d` name: 256..512 for "bots", 513..32000 for objects | replaced |
| Kick | 0x53b640 | `s` | 0x481f50 (stolen) | | replaced |
| InitClient | 0x53b790 | `si` (address, port) | 0x481a30 (stolen) | | original |
| CloseClient | 0x53b7f0 | `\|s` | 0x481cd0 / 0x481c00 | Disconnects, then loads a level | original |
| IsClient | 0x53b860 | – | 0x4819c0 (stolen) | | original |
| GetClientData | 0x53b8a0 | – | 0x7c1f68 / 0x7c1f64 | server address, port | replaced |
| GetMyClientShip | 0x53b730 | – | name of the local `net%d` player entity | **ship** | replaced |
| InitBrowser / DoneBrowser | 0x53b690 / 0x53b6f0 | `\|is` (port, address) | 0x485760 (stolen) / 0x4857b0 | LAN/master browse | replaced |
| SendUsrString / SendChatString | 0x53b900 / 0x53b960 | `is` | 0x485020 / 0x485040 (stolen) | Received as Lua `OnUsrString(UsrId,str)` / `OnChatString(UsrId,str)` | replaced |
| SendCtrlString | 0x53b9c0 | `s` | 0x485060 | Remote-control string, type 8, password-gated | replaced |
| SendMasterString / IsMaster / PingInetSvrs | 0x53ba10 / 0x53ba50 / 0x53ba90 | | 0x486a90 (stolen) / 0x486d10 / 0x486c60 (stolen) | | replaced / original / replaced |
| GetPing | 0x53bad0 | `i` | 0x485230 | Server: `client[id]+0x1c`. Client: per-id table 0x7c2280. | original |

The remaining originals are safe to leave alone. A Lua call to `Net.InitServer` or `Net.InitClient` would load a level and start the Scrapland session, so the mod must never call them [I].

### 1.5 Entity replication [V]
- **Server snapshot**, per client, in 0x483c70:
  1. writes a header and the client's **viewpoint**: the position of its own entity, via vfunc +0x80
  2. walks all entities twice, WithLife first and then the others, keeping only names of the form **`net<number>`**
  3. for each kept entity, computes the squared distance to the viewpoint and calls **`e->vfunc[+0x204](dist²)`**, a relevance or "should send" test
  4. if that returns true, calls **`e->vfunc[+0x200](dist², stream, index)`** to serialize the entity
  5. sends through stolen 0x485980, with a per-client packet counter at +0x498
- **Client upload.** 0x482e60 asserts `e->IsType(TYEN_WALKCHAR)` and calls the local player's **+0x200**.
- **Client read.** 0x482820:
  - looks up or creates `net%d`; ids up to 0x200 are created from the resource table through `ClientCreate(EntityName,ResourceName)`
  - calls **+0x208** to read the entity state
  - messages 5 and 6 carry user descriptors (`ReadUsrDescriptor`: entity +0x33c string, +0x580 int) and deletions
- **The serializers are stubs.** RTTI vtable slots for the classes that matter:

  | Class(es) | +0x200 write | +0x204 relevance | +0x208 read |
  |---|---|---|---|
  | cObjEntity, cWithLifeEntity, **cWalkCharEntity**, cMissileEntity, **cFPEntity**, cPxBody{Box, Capsule, ConvexMesh, Physics, Sphere}, cPxRagdollContainer | 0x4ef7c0 = `ret 0xc` | 0x6204b0 = `mov al,1; ret 4` | 0x575b50 = `ret 8` |
  | cItemEntity only | 0x430b90 → `[this+0x150]->vfunc+8` | 0x430c00: `dist² vs NetItemDistAct²` (value 0x7c02cc, default 8000 cm), plus a resend counter at +0x300 | 0x4310b0 → `[this+0x150]->vfunc+4` |

  So in Jericho the snapshot would carry **only headers, names and item data**. There is no position, animation, life or weapon state for characters.
- **Generic or specific?**
  - The *framework* is generic: any `cObjEntity` subclass can override three virtuals.
  - The *conventions* are Scrapland-specific:
    - only entities named `net<N>` are replicated. Jericho's level and squad entities are `Cole`, `Jones` and so on, and are never replicated.
    - Lua callbacks carry ship data: `OnClientJoin(entityname,ModelName,MaxLife,UsrName,PilotName,Motor0..3,WeaponBay,tgtype)`, `ForceServerVehicle`, `ServerType=DeathMatch`, `UsrDefChar=Dtritus`.
    - the input layer still has the "Racer" action set and the `QChatEvent1..6` quick chat.
    - client state 3 (lost) calls `CloseClient("Levels/Ciudad")` (0x481cf0), and that level does not exist in Jericho.
- **Interpolation, prediction, dead reckoning.** None exists for remote entities in the visible code. The read path is empty.
  - The only interpolation is **local render interpolation between simulation sub-steps**, for every `cObjEntity` (0x434980) and `cWalkCharEntity` (0x45c280).
  - Each sub-step saves the previous position and angles (+0xe0..0xe8 and +0xd4..0xdc).
  - With `ActiveExtrapolation=1` (default 0) the render pose is extrapolated as `pos(+0x64) + vel(+0x130)·dt` and `ang(+0x104) + angvel(+0x13c)·dt`, then blended through vfunc +0xe0(extrapolate, alpha).
  - The sub-steps come from `MaxTimeSlotSize` (0x7bc9f8) in the app frame. Related parameters: `SmoothSlotTime`, `DisableSkipSlot`.
  - None of this is network-aware.

### 1.6 Reachability [V/?]
- All imports are present, and the pump is wired into the main loop.
- The code is probably functional at runtime for its original purpose [?]. The virtualized parts run inside the VM, as the stolen `Game.GetCam` does.
- For Jericho gameplay it would replicate nothing useful. It can also be neither debugged nor extended where it is virtualized: connect, bind, send, IsServer, IsClient, Kick and the browser.

### 1.7 Could it replace or improve the Lua-over-ENet sync?

| Aspect | Engine netcode | Mod (ENet + Lua) |
|---|---|---|
| Reliability | 1 reliable chunk in flight (stop-and-wait), 7-bit sequence | windowed reliable channels, sequenced unreliable, fragmentation, RTT and throttle |
| Bandwidth | 20 KB/s cap, at most 20 packets/s, 24000-byte buffers, no deltas | the mod's choice: 20 Hz players, 10 Hz enemies, packets ≤ 900 B |
| State coverage | serializers stubbed for every Jericho class; only `net<N>` entities | squad, enemies, scenes and story events already covered |
| Smoothness | no remote interpolation or prediction | input replay (InCtrl) plus nudge and snap; already effectively dead reckoning |
| Robustness | Scrapland flows: disconnect → `Levels/Ciudad`, ship descriptors, master-command callback, plaintext passwords | under the mod's control |
| Hackability | core virtualized by SecuROM | own C and Lua |

**Verdict: ignore it as a base. Do not revive the engine session or transport.**

Ideas worth borrowing:
1. **Per-recipient relevance by distance**, the +0x204 and `NetItemDistAct` idea. Send each client the enemies near *its* body every snapshot and far ones less often. This would let `E.SNAP_EVERY` and `E.MAX_PACKET` drop for distant groups.
2. **Piggybacking**: carry the 20 Hz unreliable state in the same datagram as pending reliable messages. ENet already batches per `enet_host_flush`, so this is only a check that the mod flushes once per tick.
3. **Native fast path** (optional). The cObjEntity offsets above (pos +0x64, ang +0x104, vel +0x130) are verified. A C capture/apply in the proxy could replace Lua property reads for dozens of enemies if Lua cost ever shows up in profiles. Effort is medium, and the risk is offsets per class [I].

---

## 2. Other engine leftovers that could help

| # | Leftover | Evidence | Potential use | Effort / risk |
|---|---|---|---|---|
| 2.1 | **2-listener positional sound, nearest listener wins** | `CSoundSys::SetListener` 0x4ac580 (vtable 0x7133c4 +0x40) asserts `id>=0 && id<SOUND_MAX_LISTENERS` with ids 0..1; per-listener struct 0x3c bytes; `+0x7c` = highest id set; reset at vtable +0x3c (0x4ac570). The 3D update 0x4ac6d0 picks, for every sound, **the listener with the minimum distance²** for attenuation and pan. The world feeds it in 0x422c80 (called from the world frame at 0x423730): for each of the 4 camera slots that has a camera, it calls `SetListener(slot, pos, ang, vel)`; a FollowCam uses its target's ear position. | Split screen: player 2 hears the world from camera slot 1 once `Game.SetCam(1, cam)` is set. | Nothing to write [?]. Never put a camera in slots 2 or 3: the assert fires (possibly only logged [?]). |
| 2.2 | **FP entity `id` = owning user** | `cFPEntity` (vtable 0x70a7b4) property handler 0x478dd0 maps the property `"id"` to +0x5f0; the constructor 0x477b50 sets 0. Readers: 0x460349 (`CharCallbacks.cpp`: `MeEnt = UsrEntity(FPEnt->id)`, assert `MeEnt->IsType(TYEN_WALKCHAR)`), 0x47a8b4 (FP entity code), probably 0x464259 (`WeaponCtrl` [I]). `MakeFP.MakeFPObject(Typo,id)` only uses `id` in the name. | Split screen: `1FP_*` created by `coop_split.lua` still has id 0, so its animation callbacks (shots, events) resolve to **user 0's body**. Set `fp.id = 1` (and `0` for `0FP_*`). | One line. Low risk. Verify shots and reloads of player 2 [?]. |
| 2.3 | **`R_SplitScreen` = update everything** | 0x5adad0 (`ScrapEngModel`) returns "visible" when `R_SplitScreen`, otherwise model+0x29d bit 0. Called from 12 sites: WalkChar 0x454c6f and 0x457dec, PxBodyPhysics 0x46ac2b, PxBodySphere 0x46ec16, Ragdoll 0x47264f, AIChar 0x4d05d2 and 0x4d0bac, ActCtrl 0x52690e, CharEvents 0x52c433, MapElements 0x41d2c6, Item 0x430d0c, EffectInertia 0x55cdd0. | This is why alternate-frame split works: models seen only by the other camera keep animating. Keep it on whenever two views alternate, and off otherwise (CPU cost). | Already used by `coop_split.lua`. |
| 2.4 | **Per-user HUD (Scorer 0..3)** | Draw 0x495c00, called only from `.securom`. For i < (SplitScreen ? 2 : 1): SetRenderCam(cam slot i) via 0x599700, viewport 0x59b8b0 at (0,0,640,240) or (0,240,640,240), Scorer[i] = `[0x7c5644]+i*0x170`, items 0x4948a0 / 0x4925a0. HUD scorer classes call `UsrEntity(i)` with a variable index (Damage 0x4a419f, Text 0x49f213, 0x4a0c83–0x4a3016) [I]. `Scorer.SetMPFunc(id,f)` (0x53ddd0) is a per-scorer Lua hook at +0x144. | Player 2's HUD shows player 2's own body. Markers and `Get2DPos` project through player 2's camera. | Already used. `SetMPFunc` can hook custom per-user HUD drawing [?]. |
| 2.5 | **Chat scorer** | `Scorer.AddChatMsg(text,r,g,b)` (0x53de70, format `siii`) → 0x48c810, `cChatScorer` (vtable 0x70d764) with `ChatMsgPersistence` | A native, timed chat or notification line for co-op messages instead of custom text blocks | Low. Check that it renders in Jericho's HUD [?]. |
| 2.6 | **Hard-coded `UsrEntity(0)` in engine C++** | About 28 inline `world+0x2b0` reads, plus 69 calls of 0x427470, most with a constant 0. Examples: `Ababanili` AI 0x4f0790, EvilFirstBorn ThrowRay 0x4fd8c0, Flies 0x501040, Maltheus 0x5047c0, AI char control 0x4da620, FollowCam 0x446310, missiles 0x430e40, items 0x430cb0, ragdoll and physics 0x4286e0 and 0x473b20, sound events 0x52cfc0, memory/debug scorer 0x491fe0. | Explains behaviour that is "player 1 only" in boss fights and some AI perception, for online clients (puppets on the host) and split-screen player 2 alike. Complements `mod/docs/usrentity-audit.md`, which is Lua-only. | Info only. Fixing means patching each site natively (high effort). Test the listed bosses with a non-host player [?]. |
| 2.7 | **Per-pad input** | `Joy1..Joy4` bindings, `Input.Bind(id,set,action,func)` (`isss`, stolen 0x1234ea0), `Input.Rumble(id<4,…)` 0x53b0a0. `Input.CheckPadButton(pad,btn)` (0x53b150) is a **stub that always returns 0**. `Input.SetActionSet` is global. `Input.ResetToSplit` is a stub. | Already known and used (player 2 on Joy2) | – |
| 2.8 | **Saves = save vars only** | `HardSaveGame` 0x40ac00 writes header `RGMH` + 0x24004 bytes of save-var blob; `HardLoadGame` 0x40ae50; `SaveGameVars` 0x536740 (default "Mercury SaveGame"). No entity or world serializer exists. Smaller items: `AI.SaveStateAuxChar/RestoreStateAuxChar` (0x531550 / 0x5315e0, AI controller vfunc +0x148/+0x14c), `Physics.SaveClothState/LoadClothState`. | Join-in-progress or resync must be built by the mod (enemy roster, triggers, story flags). The save-var sync in `coop_save.lua` is already the most the engine offers. `SaveStateAuxChar` could freeze or restore one AI's state around a resync [?]. | – |
| 2.9 | **Gvar flags** | `Game.SetFlag(var, "READONLY"\|"PRG_CFG"\|"COMMAND"\|"CONSOLE", b)` 0x536090; `ShowGVars` | Mark co-op parameters `CONSOLE` or `COMMAND` for in-console tuning; protect parameters from SMOD's autoexec with `READONLY` [?] | Low |
| 2.10 | **Debug and profiling** | `LuaDebug` (0–3: breakpoints, stepping), `Game.SetBreakPoint/GetBreakPoint`, `OutDebugFile`, `ShowConsoleLog`, `AlwaysFlushLog`, `S_Show` (sound debug, 0/1/2), `O_Show` (object pool), `DebugPosSoundShow`, `OnRenderDebug` callback + `Debug.DrawSphere/DrawTri/DrawText/DrawLink/AddLine`, `RT_Benchmark`, `R_MaterialLog`, `PhysXVRD` (PhysX Visual Remote Debugger IP), `LogNetData`, fps string in 0x5e69c0 | Debug overlay for puppet error: draw a line from the received to the actual position. Sound-listener check for split screen with `S_Show`. PhysX VRD for ragdoll desync. | Low |
| 2.11 | **Built-in recorder** | AVIFIL32 import; QuickConsole `movie`, `realmovie`, `framemovie` (`MovieFramerate`, `TimerFreqMult`), `Game.ScreenShot` (0x5382f0) | Deterministic showcase capture without OBS | Low |
| 2.12 | **`Game.RunApp(exe,args)`** | 0x5370d0 → CApp vfunc +0x48 (0x401c90, enters `.securom`) | Possibly spawn a second process from Lua [?]. The native `CreateProcess` path planned in the split-screen research is safer. | Unknown |

Not found, or not useful: per-entity network flags (none beyond the `net<N>` name convention), remote-entity interpolation helpers, a world snapshot. `MonitorView`, `EagleView`, `Travel` and similar are full-screen post filters, not extra cameras.

---

## 3. Single-process split screen (in progress: `coop_split.lua` + `native/split.c`)

### 3.1 Render path [V]
- **CApp** (vtable 0x6f91a4): +0x24 = tick (0x402760), **+0x28 = draw** (0x402790 → `jmp 0x59c1c0`).
- **0x59c1c0** (`ScrapEngMain.cpp`):
  1. `SetRenderCam(GetActiveCam())`, i.e. 0x599700 called with the result of 0x5997c0. The current render camera is stored at 0x80de3c, and 0x599700 also switches `gMundo(0x863d04)+0x88` through 0x5c8760.
  2. `_renderframework` = `[0x8637c4]`, vtable +0x58 → 0x59e480 → **0x5e69c0 = CD3DApplication::Render3DEnvironment**.
- **0x5e69c0**:
  1. `TestCooperativeLevel` (device vtable +0xc)
  2. FrameMove = vfunc +0x10 (0x59e8d0, timers only)
  3. **Render = vfunc +0x14 = 0x59fa10** (`CMotorApp`, "RenderFrame", `Motor.cpp`)
  4. fps statistics
  5. **`Present` once** (device vtable +0x44)
  - The device is at `[0x8637c4]+0x2b714`.
- **0x59fa10**:
  - starts with **BeginScene** (0x5cf3b0, device +0xa4) and ends with **EndScene** (0x5cf3d0, device +0xa8)
  - in between, a fixed multi-pass pipeline: shadows, lighting, glow, the render-target effect objects at `[0x88afa8]+0x54/+0x88/+0x8c/+0x90/+0x94`, and the HUD (the HUD viewport is the cue `split.c` already uses)
  - then a **LimitFPS busy-wait** (`R_LimitFPS`)
  - a per-render frame counter 0x80e958
  - many passes go through SecuROM thunks
- **Viewport helper.** 0x59b8b0 (640×480 logical) → **0x5d18e0(rect, adjustProj)**:
  - sets the D3D viewport (0x5cfb80)
  - with `adjustProj`, rewrites the projection scale and offset to map into the rect (0x5d0020)
  - visible callers are only the Scorer paths and the Scorer reset 0x599860
- **Can the world render twice per Present?**
  - **Mechanically yes:** two BeginScene/EndScene pairs before one Present are legal D3D9. A hook on `CMotorApp` vtable slot +0x14 could:
    1. set the slot-0 camera and call the original
    2. StretchRect the back buffer (or the resolved copy) into the top half of a composite
    3. set the slot-1 camera and call the original again
    4. copy the second result into the bottom half, then let Present run
  - **Obstacles:**
    - the HUD is drawn inside each pass, so with `SplitScreen=1` both HUDs would be drawn twice. Suppress the HUD in pass 1, for example with `ScorerRender` [?].
    - the LimitFPS wait runs twice. Use `R_LimitFPS=0`.
    - temporal effects (pixel motion blur, HDR adaptation) see the other camera's frame. They are already disabled in `Sp.FX`.
    - shadow-map and particle state may be advanced twice [?].
    - CPU cost about doubles.
  - The gain is full frame rate for both views instead of the current half rate.
  - **Rendering straight into a half viewport is not recommended:** the post-effect chain works on full-screen render targets [I].
- **`R_SplitScreenUpdate`** (value 0x863374) is written only in 0x423440. It is 1 while the game timer runs. There is no reader in `.text`, and a raw dword scan of `.securom` and `.memory` finds none either. The only route left is a lookup by name inside VM code [?].
  - Together with item 2.3, the original console design was most likely **alternate-frame**: one camera per frame, with an "update target" flag telling the compositor which half to refresh [I].
  - That is exactly the current `split.c` design, so it is consistent with the engine.

### 3.2 FP weapon models [V]
- The FP model is a `cFPEntity` linked from the character's `FPSEntity` / `oFPSEntity` property (WalkChar). Its owner is decided by the FP entity's **`id`** property, not by its name (see 2.2).
- The `0`/`1` prefix (`"0FP_Ross"` is hard-coded at 0x72a198) is only a naming convention.
- **Action: in `Sp.ensureFP`, set `Game.GetEntity("1FP_"..char).id = 1`.**
- Which FP model is drawn per camera is not visible statically [?]. Watch for both FP models appearing in both halves, or none in the bottom half. If that happens, toggle `InCtrl_UseFPS` or the FP entity's visibility per frame from the same hook that flips `R_SplitScreenCamera`.

### 3.3 Audio listener [V]
- See 2.1. It needs no code. With `Game.SetCam(1, "CoopCam1")` the listener for slot 1 is updated every world frame, and each sound attenuates and pans relative to the nearer camera.
- **Check with `S_Show=1`** [?].
- Do not use camera slots 2 and 3.

### 3.4 HUD [V]
- See 2.4. `Sp.buildHud()` with `Scorer.NewItem(1, …)` is the intended use.
- Scorer 3D projections, such as markers, use player 2's camera because the draw loop sets the render camera per user.

### 3.5 What `R_SplitScreenUpdate` and the related parameters cannot give [V]
- There is no second-viewport world render anywhere in the visible code.
- The only per-user render switch is the HUD loop.
- The engine's camera-slot selection (`world+0x78 = R_SplitScreenCamera`, then render camera = slot) happens in the world frame 0x423440. `coop_split.lua` already drives it.

---

## 4. Ranked recommendations

1. **Set the FP owner for player 2: `fp.id = 1` on `1FP_*`** (and keep 0 on `0FP_*`). Trivial, verified mechanism, likely fixes player 2's shot and animation callbacks hitting player 1's body. [V mechanism, ? effect]
2. **Rely on the engine's second sound listener.** Verify with `S_Show=1`, keep cameras only in slots 0 and 1, and drop any planned custom audio work for split screen. [V]
3. **Keep `R_SplitScreen=1` only while split is active.** It disables visibility-gated updates at 12 sites, which alternate-frame needs; turn it off when holding full screen to save CPU. Already done; documented here as matching the original design. [V]
4. **Do not use the engine netcode. Stay on ENet.** Leave `Net.InitServer`/`InitClient`/`CloseServer`/`CloseClient` uncalled. Optionally make them no-ops in the luaL_Reg patch, which also removes the dormant master-command and remote-control surface. [V]
5. **Borrow per-recipient distance relevance for enemy snapshots**, Scrapland's +0x204/`NetItemDistAct` idea: near enemies every snapshot, far ones every Nth. This cuts packet size and improves near-field smoothness. Medium effort, low risk. [I]
6. **Experiment: two world passes per Present** through the `CMotorApp` vtable +0x14 hook for a full-frame-rate split, after the alternate-frame version is stable. Medium-high effort and risk: HUD duplication, LimitFPS, temporal effects. [I/?]
7. **Use the debug leftovers** in tests: `OnRenderDebug` + `Debug.DrawLink` to visualise puppet error, `S_Show`, `LuaDebug`/`OutDebugFile`, and the AVI recorder for showcases. Low effort. [V]
8. **Engine `UsrEntity(0)` sites** (2.6): add the listed bosses to the test plan for non-host and player-2 players. Native fixes only if a stall is proven. [V sites, I impact]
9. **Optional native fast path** for state capture and apply, using the verified offsets (+0x64 pos, +0x104 ang, +0x130 vel), only if Lua profiling shows the 20 Hz loops are costly. [V offsets for cObjEntity, I per subclass]
10. **No world serializer exists.** Plan join-in-progress or resync on the mod's own snapshot (save vars, which are already synced, plus enemy roster, triggers and story flags). `AI.SaveStateAuxChar` may help with single-AI freeze/restore. [V]

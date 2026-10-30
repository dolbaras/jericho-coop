# Split choice: one "choose your squad" screen for every human player

Status: designed for 0.2.8 (owner bug 8); 0.2.8 shipped G8, G10 and the Lost Patrol, 0.2.9 adds G6, G11, G15, G4, G1A, G1C, G3 and split screen
(section 8 says where the code differs from the first design below). The owner's decision (2026-10-29): ONE shared
screen for all human players, **the host included**, shown **before** the scene or split starts; each player goes to
the group he wants, several players may go to the same group or apart (no "the host stays" rule); two or three cards
with the group's members, a short mission blurb and the live nicknames of who picked what; pad left/right + A,
arrows + Enter, or keys 1/2/3; about 25 s; default = stay in the current body; the host resolves conflicts and
applies the moves; one line of explanation after each choice; texts in six languages.

Read with: [coop-story-extensions.md](coop-story-extensions.md) (the splits), [campaign-structure.md](campaign-structure.md)
(who is present where), [story/](story/) (the lines), `lua/coop_souls.lua` (who may switch), `lua/coop_splits.lua`
(`Sp.SPLITS`, `Sp.offer`, `spc`), `lua/coop_patrol.lua` (`LP.offer`, `lpc`/`lpr`).

## 1. What exists today and why the owner saw nothing

- Only G8 (`cru_sewers`) and G10 (`rom_caldarium`) ask anybody, and only the players whose bodies *stay behind*, one
  question ("take the character who goes on, or stay"), 20 s, keys 1/2 (`Sp.SPLITS`, `Sp.offer`, `spc`). The offer is
  made *after* the hook fired (`Sp.after(... TriggerEscalada_0 ...)`), so the scene is already running.
- The Lost Patrol asks a client who holds Jones, Cole or Rawlings, at the bridge scene, with a text overlay while the
  scene plays (`LP.offer`: "the host stays", `lpc`/`lpr`, `cfg.patrol`).
- G1 (alk_tomb, alk_city), G3, G4, G6, G11, G15 never ask: whoever holds a body in the story's role plays it, the rest
  watch or defend.
- Owner's session: both players held main-group bodies at the bridge, so nobody was a trio holder, nobody was asked,
  and the trio went to the children (Cru_Labyrinth: "let them entertain the children").

## 2. The screen

```
          THE BRIDGE IS FALLING                      18
 +---------------------+   +------------------------------+
 | MAIN GROUP          |   | THE LOST PATROL              |
 | Delgado Church Black|   | Jones  Cole  Rawlings        |
 | Fight on through the|   | Wake in the blood river and  |
 | labyrinth.          |   | claw your way to the chapel. |
 |  > Anna, Max        |   |  > Ivan                      |
 +---------------------+   +------------------------------+
   < > choose   A / Enter confirm   1 2 3
```

- Drawn with `Scorer` text items (a dimmed background, one column per card, the picked card highlighted, a tick after a
  confirmed pick). Cards: group name, member characters (names in the game's language), blurb (1-2 lines), the nicknames
  of the players who currently point at the card (live; a confirmed pick is marked, a full card is greyed).
- Controls: the local player's stick / D-pad left-right or arrow keys move the highlight (this is a *tentative pick*,
  visible to the others at once), A / Enter / the digit key confirms; digits 1-3 pick and confirm in one step. Unconfirmed
  players are resolved with their highlight at the end of the timer; a player who touched nothing keeps the default.
- Default and timer: default = the group of the body the player holds now (= "stay"); 25 s; the screen closes at once when
  every human has confirmed.
- While it is up the local human bodies are locked (`IgnoreUsrControl`) and invulnerable (as story drives), because the
  stick and Enter are in use; the world goes on (a session never pauses). It opens only where the squad is at rest (the
  trigger that starts a split); the 25 s are safe.
- After the choice every player gets **one line** (message line, 5 s): "You go with Church: his climb starts now." /
  "You stay: Black and Delgado hold the hall." / "Church was taken a moment before: you stay with Black." (en, ru, de, fr,
  es, it in `CoopChoice.TEXT`).
- Split screen (two local humans): the same screen on both halves; player 2 chooses with pad 2 only (digits belong to
  player 1).

## 3. Data model

One table per split in the new `lua/coop_choice.lua` (`CoopChoice.DEFS`), identical on every machine (code, not
network data):

```lua
DEFS.G8 = {
  level = "levels/cru_sewers",
  title = "g8_title",                       -- text key
  groups = {                                -- 2 or 3 cards, in screen order
    {key = "go",   chars = {"Church"},          blurb = "g8_go"},
    {key = "stay", chars = {"Black", "Delgado"}, blurb = "g8_stay"},
  },
  pinned = {},                              -- holders who cannot leave their group (story script needs them)
  hold = {...},                             -- how the host holds the start (section 5)
  apply = function(result) ... end,         -- what the split code does with the result (sides, waves)
}
```

Capacity of a card = the number of its characters that are in the level, alive and not taken by the story. A player's
body counts toward his own card. Messages (all reliable, handled in `CoopChoice.onMessage`, registered after
`CoopSplits`):

| Kind | From -> to | Payload |
|---|---|---|
| `chs` | host -> all | split id, seconds, the human owner ids in screen order |
| `chp` | player -> host | split id, group index, confirmed 0/1 (owner id added by the host from the sender; a split screen player 2 sends `chp2`) |
| `chst` | host -> all (on every change, 1/s) | split id, `owner:group:confirmed;...` (this drives the nicknames on the cards) |
| `chr` | host -> all | split id, `owner:char:reason;...` (reason = `keep`, `moved`, `full`, `default`, `none`) |

The nicknames come from `CoopHud.nicks()`, the owners from `Coop.owners`. The old `spc`, `Sp.offer`, `Sp.updateChoice`,
`LP.offer`, `LP.updateChoice` are replaced; `lpc`/`lpr` stay only as the Lost Patrol's *result* path into `cfg.patrol`.

### Resolution (host, when the timer ends or all confirmed)

1. Wanted group of each human = his confirmed pick, else his highlight, else the group of his current body.
2. A human whose current body is in his wanted group keeps it.
3. Others need a **free** body of the group: alive, `bActive`, in the level, held by no human (or by a human who is
   leaving it), not taken by the story (`CoopStory.taken`), not rune-bound, on the right side
   (`T.usable`-like rule of `coop_team.lua`). Preference: the one the player held last, then the group's order.
4. Moves are applied in dependency order (a body freed by a leaver is free for the next); the host's own player by a direct
   `Team.SwitchSoldier`, a client by `evict|char|new` (exists: `St.onEvict`), one after the other with the owner table
   acknowledged (2 s time-out). A cycle (A wants B's body and B wants A's, no spare free body) is not resolved in 0.2.8:
   both stay and get the reason `full`.
5. More pickers than capacity: first confirmed (then lowest seat) wins; the rest keep their body, reason `full`.
6. Then `apply(result)`: the split's own code (sides for downed players `Sp.setSides`, the hold waves
   `humansIn(...)`, the Lost Patrol's `cfg.patrol`) runs exactly as it does today for "who holds what".

The mover's role from `coop_souls.lua` is **not** checked: `mayChoose` limits the player's own switching in play (seats
3-4 keep their body); the choice is a forced move through `Team.SwitchSoldier` ("every forced move ... is left alone"),
and the owner wants every player free to pick.

## 4. Mapping of the splits to groups and bodies

"Hero role" = the single-character job the story script needs (QTE, console, gate); "side role" = the others' content
we added (waves, soul, cover). Bodies are the characters present in that level (campaign-structure.md section 3).

| Split | Level | Moment (hold before) | Cards (bodies) | Pinned | Nobody picks the card |
|---|---|---|---|---|---|
| G1 leg A | alk_tomb (act 1) | `MapInit.StartSayGoodbye` (goodbye chat) | Omega: Ross, Church, Black, Rawlings / Alpha: Jones, Cole, Delgado | Ross's holder | Alpha side: vanilla (Alpha switched off, `humansIn = 0`); Omega always has Ross |
| G1 leg C | alk_city (act 1) | `EnableAlpha` (the `AreaTrigger119` callback) | Omega (as above) / Alpha in the pocket: Jones, Cole, Delgado | Ross's holder | Alpha stays hidden until the breakthrough as in vanilla |
| G3 | alk_bunker_01 (act 1) | `MapInit.GoToRawlings` / the console walk | Console: Cole / Defence: Ross, Church, Black, Rawlings, Jones, Delgado | Ross's holder | the vanilla FakeCole hacks; nobody defends |
| G4 | wwii_pillboxes | scene `DelgadokillsRawlings` (Rawlings is alive then) | Rawlings' soul: Rawlings / Defend his body: Church, Black, Cole, Delgado, Jones | none | vanilla solo revive by the current character (soul walk skipped, `Sp.G4on` false) |
| G6 | wwii_brandenburg | level start, before play | Sacrifice: Church / Gate top: Cole, Rawlings / Base: Jones, Delgado, Black | none | Church: AI (QTEs auto); gate top: vanilla props; base: AI |
| G8 | cru_sewers | `TriggerEscalada_0` / scene Escalada | Climb: Church / Hold the gate: Black, Delgado | none | Church's climb by the AI (descent QTE auto); no waves |
| G10 | rom_caldarium | `AreaTrigger_Fire_0` | Fire: Delgado / Hall: Black, Church, Cole, Jones, Rawlings | none | Delgado by the AI; the others frozen as vanilla (no waves) |
| G11 | rom_palace_01 | `o249_0` / scene TheAbyss | Cross: Church / Cover: Black, Cole, Delgado, Jones, Rawlings | none | Church by the AI (QTE auto); cover side without humans: no extra legionaries beyond the existing wave |
| G15 | sum_end (last phase) | `EvilFirstBorn.SchMakeAllUnavailable` (the blood rune) | The kill: Church / Bound: Black, Delgado, Rawlings | none | Church by the AI; bound AI as vanilla |
| Lost Patrol | cru_river | scene `BridgeCollapses` (`Scene.PlayFP` wrapper, host) | Main: Delgado, Church, Black / Lost Patrol: Jones, Cole, Rawlings | the **host's machine** (section 6) | nobody picks the trio: no side instance, the trio is lost as in the story; nobody on main: n/a (the host is) |

Notes:
- G2, G5, G7 (default), G12-G14 have no second group with bodies: the spirit role covers the players without a body
  (`coop_spirit.lua`); no screen.
- Act 1 (G1, G3): nobody switches in play (Ross alive, `mayChoose` = false "act1"); the choice is the one allowed move.
  Ross's holder is pinned to Ross because the level scripts gate on `Game.UsrEntity(0) == Ross` and AI-walk him
  (campaign-structure.md 5.1); everyone else is free. Step 2.
- G4: the soul walk needs the player *in* Rawlings's body *before* he is shot; hence the hold at the scene start.
- G6: three cards; the base group has no extra content today (AI fight); Cole and Rawlings are props unless a human
  holds them (`Sp.G6keepHumans`).
- G15: the bound ones free themselves by the struggle (existing); the card only decides who plays Church.

## 5. How the host holds the moment

The split's own hook is moved *before* the original instead of after:
- **Scene splits** (Escalada, TheAbyss, DelgadokillsRawlings, BridgeCollapses): the host wraps the entry (`MapCallbacks`
  entry or `Scene.PlayFP`), opens the screen, and runs the original when the choice is resolved. The scene gate
  (`CoopEnemies.heldScenes`, curtain) is not used: clients are in the level already and the world keeps running.
- **Trigger splits** (G10 fire, G1C `EnableAlpha`, G3, G15): the callback is wrapped the same way (deferred call with the
  original arguments through `Coop.fromHost`).
- **Level-start split** (G6): opened when every expected machine has said `lready` (`CoopEnemies.readyPeers`), before
  the first play frame.
- A wrapped entry fires **once** per split (a flag `done[id]`, also after a checkpoint reload: the result is kept in the
  `sv`-like per-level state `Sp.sides` and re-applied; a reload at the same spot asks again only if the split restarts).

## 6. Edge cases and decisions

- **One human**: no screen, the story runs as in the original game with that player in the hero role if he holds it
  (the vanilla one-player behaviour), otherwise as today.
- **Four humans**: cards show up to 4 nicknames; a 4th human on a 3-body level has no body to take: he only sees cards
  whose capacity is not exhausted; if all full he stays a spirit/spectator (`coop_spirit.lua`).
- **A player in a downed body**: shown the screen like the rest (he still reads the pad); his default is "keep waiting";
  a pick of a group with a free body moves him there as a downed move (`Team.SwitchSoldier` from the dead body).
- **A player disconnects during the choice**: the host drops his pick on `leave`; the nicknames update, the screen closes
  early if the rest has confirmed; his body goes to the AI as always. The host leaving ends the session.
- **A player joins/rejoins**: not supported mid-split (lobby only); a late `lready` peer simply gets `chs` again with the
  seconds left.
- **At least one body per group**: a card with capacity 0 (all its bodies taken by the story, dead, or not in the level) is
  not shown; if only one card is left the screen is skipped. Two humans cannot both end up on a one-body card; with every
  human wanting the same one-body card, one gets it, the rest keep their body.
- **The Lost Patrol and the host**: the host's machine *is* the hub and plays the main instance (campaign save, level
  changes, `CoopInst` forwards through it). It cannot enter the side instance without a host migration. So the host is
  shown the trio card but a pick of it is refused with the line "the host's game runs the main group". This is the one
  exception to "no restriction"; the alternative (mirroring the instances so the trio becomes the hub's instance) is a
  large change and is **not** in 0.2.8. The owner should confirm.
- **Nobody goes to a group**: the groups are *roles*, not story branches; the script of the level always runs. The hero
  role falls back to the AI of that character (`coop_claim.lua` policy, QTEs automatic); the side role starts only with
  at least one human on it (`Sp.humansIn(...) > 0`, as the code already checks). The only real branch is the Lost Patrol:
  a side instance exists iff somebody picked the trio (`cfg.patrol`).
- **A refused or lost message**: results are authoritative on the host; `chst` is resent every second and `chr` once
  per machine, so a client that missed `chr` shows the state from `chst` and the owner table (`own`) tells it where it is.
- **Test hooks**: `cfg.choice = "<group index>"` (confirm that pick at once), `cfg.choicetime` (seconds), a console
  `CoopChoice.press(key)` for bots; the pad is read through `Input.GetInputState`, keys through `Net.CoopKey`.

## 7. Implementation steps

1. **0.2.8 step 1 (this task)**: `coop_choice.lua` with the generic screen, messages, resolution; G8, G10 and the Lost Patrol
   as definitions; `Sp.offer` / `LP.offer` replaced; texts in six languages; lab script with bots pressing keys and a
   captured frame.
2. Step 2: G6, G11, G15, G4 (hold points inside the existing hooks).
3. Step 3: Act 1 splits (G1A, G1C, G3) with the Ross pin; split screen on both halves; the swap cycle.

## 8. What the code does (0.2.9; the design above, as built)

- **Both machines hold the same call.** `CoopChoice.gate(id, fn, when, replayOnly)` wraps a split's entry on the host AND on clients.
  The host's first call opens the screen; a client's call (the replay of the host's callback, or the level script's own call such as
  `MapInit.StartSayGoodbye`) waits for the host's `chr`/`chd` and then runs after the same 3.5 s the host waits, so neither machine starts the
  split alone. A client that loaded after the host decided asks (`chq`, every 2 s) and gets `chd`; with no word at all a held call runs after
  `TIME + 12` s. Map callbacks are held on a client only when they are a replay (`Coop.replay`): the client's own use must reach the guard that
  tells the host. The gate is always installed OUTSIDE the `Sp.after` hooks of the same entry (the hooks belong to the split's start).
- **Reset.** `C.reset()` clears `done`, `pending`, `cur`, the resume queue and the held calls at every file load, level load (new `Coop`
  table) and session end; the resume queue (`C.later`) is FIFO, so two splits finishing inside `RESULT_HOLD` both start.
- **Owners.** `chp` carries the owner id (split screen player 2 = peer + `Coop.P2`; the host stores it under the sender when the id is not one
  of that machine's). Each local player is one entry of `scr.locals` with his own cursor; the keyboard and pad 1 belong to the first, pad 2
  to the second (`C.press(key, n)` for bots, `cfg.choice` / `cfg.choice2` auto picks).
- **Exchange of bodies.** Two players who want each other's groups and have no spare free body swap: both moves are decided together, the owner
  table is rewritten at once, the host's own player switches directly and the client gets `evict`. (The first design said "both stay"; the
  resolution already did the exchange in 0.2.8, now tested: `choice_mock_test.lua` case 8.) If a mover's target is held by somebody who does not
  leave, both stay with the reason `full`.
- **Lost Patrol.** `LP.chosenTrio` sends to the side instance the machines whose players HOLD a trio body at the end (`result.final`), not the
  ones who asked for it: a player refused for `full` goes on with the main group.
- **Pinned.** `def.pinned()` names bodies whose holder cannot leave (Ross in act 1: the level scripts read `Game.UsrEntity(0) == Ross`). He sees
  the screen with his card fixed and confirmed (`chs` carries the pinned owner ids; reason `pinned`, "You are Ross: ...").
- **Inactive bodies.** `def.inactive` names bodies the level keeps switched off until a player holds them (G6's Cole and Rawlings on the gate
  top, G1C's Alpha): a card counts them, the move switches them on (`evict|from|to|a`) and clears the game's switch lock for the move
  (`CoopChoice.enter`).
- **Where each split is held** (`Sp.gate(path, id)` in `coop_splits.lua`): G6 no call is held, the screen sits on top of the level 3 s after
  the level start (everyone loaded, no scene; a checkpoint reload does not ask again; `def.after` = `Sp.G6afterChoice` keeps the gate-top
  bodies on); G11 `MapCallbacks.o249_0` (the Church-only use of TriggerTheAbyss); G15 `EvilFirstBorn.SchMakeAllUnavailable` (the first rune,
  mid-fight: the world goes on, the local bodies are locked and invulnerable); G4 `Scene.PlayFPNNI("Pathofsouls")` on the host (the scene chains
  into the shot, so the choice comes before the whole chain; the player who picks Rawlings is in his body when he is shot); G1A
  `MapInit.StartSayGoodbye`; G1C `MapInit.DisableAlpha` (called by the start trigger, which is where the pocket closes; the design table's
  `EnableAlpha` is the end of the split); G3 `MapInit.GoToRawlings`.

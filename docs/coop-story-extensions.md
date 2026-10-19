# Story extensions for co-op: what the players left behind do

Status: owner decisions taken 2026-10-19 (see below); detailed per-act designs in `story/`. Facts about the vanilla scripts are in
`campaign-structure.md` (sections 3 and 5) and `scenes-catalog.md` (sections 5 and 6). This
document only proposes what co-op adds.

## Owner decisions (2026-10-19)

- Players with no body: the **spirit role** (plain spectator built first as the fallback).
- **Every split gets a parallel line.** A player whose character leaves chooses: (a) switch to
  a character who goes on, or (b) stay in their own body and play that character's own line.
  The Crusades "Lost Patrol" (G7, Tier 3) is planned too.
- Story content may re-run existing enemy groups and place existing enemy types at new
  spawn points (no new geometry).
- The Lost Patrol (G7) is built in its full form: its own route through cru_river,
  cru_catacomb and cru_chapel with a second host (story/act3-splits.md option B).
- Voice: new beats are built from the game's existing voice lines (catalog:
  `tools/voice_catalog.py`); anything else is subtitle text. Cloning the actors' voices is not
  done.

Per-act designs with routes, enemy groups, voice keys, engineering and in-game checks:
`story/act1-splits.md`, `story/act2-splits.md`, `story/act3-splits.md`, `story/act45-splits.md`.
Corrections they make to the table below:
- G6: there is no climb to defend (the climb is inside the scene); the real gap is Cole and
  Rawlings hidden all level, so their line is on top of the gate with the captive.
- G11: the legion assault comes before Church's crossing and the plates after it.
- G15: the final fight has no Arnold Leach adds; the enemies are the Firstborn's stolen powers
  (`EvilAbabanili`, the ghost copies).

## Implementation status (2026-10-19, `lua/coop_splits.lua`)

| Split | Line | State |
|---|---|---|
| G1 leg C | alk_city: Alpha holds its pocket until Omega breaks through | written |
| G1 legs A, B | alk_tomb plateau, bunker_00 east tunnel | not started (need in-game checks of the routes) |
| G3 | alk_bunker_01: the human Cole hacks the console herself | written |
| G4 | wwii_pillboxes: Stations of the Path (soul walk, revive gate) | written, tested on the test PC |
| G6 | wwii_brandenburg: Cole and Rawlings active on the gate top | written (captive "hold" mechanic not yet) |
| G8 | cru_sewers: Hold the gate (three re-armed waves) | tested on the test PC |
| G10 | rom_caldarium: The Torturers' Hall | written |
| G11 | rom_palace_01: legionaries on Church's side after the crossing | tested on the test PC |
| G15 | sum_end: break the blood link (hold E) | written |
| G2, G5, G7 (default), G12-G14 | spirit role (`lua/coop_spirit.lua`) | the spirit exists; story subtitles for these splits not yet |
| G7 Lost Patrol (full) | second host | not started |

"Written" means the code exists and loads in every level (level smoke test) but the line was
not played through in game yet.

## Goal

The campaign splits the squad many times: a member leaves, is lost, captured, possessed,
or goes on alone, and the others wait or are not loaded at all. In single player the player
simply follows the one character who acts. In co-op every split leaves some players with
nothing to do. Each split below gets:

- a story reason for where the others are and why;
- something for them to do that fits that reason;
- a reunion that the existing scenes already show, or a short added beat.

## What is technically possible

ScrapEngine has no public level editor, so new geometry is out of reach. Everything here
reuses what ships with the game:

- the level's own areas, including places the story has already passed;
- enemy groups and generators the level already defines (`NPC`, `EnemyGen`);
- use objects, telekinesis objects and levers that already exist;
- the squad's existing voice lines (`TeamTalk`, radio).

New text appears as subtitles in the game's language. New voice lines are not possible.

The tools come in three tiers:

- **Tier 1 — same level, scripts only:** keep the bodies active, give them an objective
  in the same level with reused enemies, and add subtitle radio lines.
- **Tier 2 — the spirit role:** a player without a body becomes a spirit; see below.
- **Tier 3 — a parallel mission in another level** (two groups in two different levels at
  once). This needs a second authority in the session, one of the clients hosting the second
  group. It is the most work, so it is proposed for one place only (Crusades, G6) and only
  if the owner wants it.

## The spirit role (Tier 2), one answer for every "no body" case

Jericho's own premise is that the player is **Ross's spirit**, moving between bodies after
his death. A player whose character is not in the level (or is captured or dead) plays
**an echo of that spirit**:

- **Movement:** free astral flight inside the level, with the existing `AstralCamera`
  (Jones' astral projection) in its orbit and fly modes. The spirit cannot leave a radius
  around the squad.
- **Telekinesis:** the spirit can push objects that are marked `bUseOnTK`.
- **Fire:** it can ignite objects through the existing `funcOnBurn`.
- **Marking:** it can mark an enemy so the squad sees it highlighted, like a ping.
- **Possession:** it can take a free squad body as soon as one becomes available, which is
  the same rule as the switch.
- **Look:** the astral filter Jones uses (`RENDEREFFECT_*`), and the player's nickname
  shown as a faint wisp to the others.

The spirit stays useful without breaking the story ("Cole is lost at the bridge" stays
true), and it covers every level that has fewer bodies than players.

## Splits, in campaign order

| # | Where | Story (vanilla) | Who is left out | Proposal | Tier |
|---|---|---|---|---|---|
| G1 | alk_tomb, after the goodbye | Ross splits the squad and Alpha (Jones, Cole, Delgado) leaves for another passage. | Alpha's players | **"Alpha's road":** Alpha keeps its bodies and holds the tomb's cleared upper halls against cultist waves (reused tomb groups) until the blood door, reporting by radio (subtitles). They then rejoin through the existing `alk_city` rejoin (`EnableAlpha`). In co-op Alpha starts active in alk_city on the far side and fights towards the meeting point instead of appearing at it. | 1 |
| G2 | alk_bunker_00 | Only Ross and Rawlings go down to Muriel. | players 3-4 | Spirits that follow Ross and Rawlings. Subtitle radio: the others guard the entrance above. | 2 |
| G3 | alk_bunker_01 ambush | Cole is at the console (FakeCole), the real Cole is inactive for about 120 s. | Cole's player | Cole's player **is** the hacker: they stay at the console in first person and the progress bar is theirs. Leaving the console pauses the hack, so the others must defend them. | 1 |
| G4 | wwii_pillboxes, Rawlings "killed" | The solo revive, with all AI switched off. | everyone but the reviver | Drop the solo lock: whoever reaches Rawlings first revives him while the others hold the final Nazi wave (`nazis_final` kept running). Rawlings' player watches as a spirit next to their own body until revived (a "dying spirit" view). | 1 + 2 |
| G5 | wwii_vigil_inside | Only Cole, Church and Rawlings go inside. | the 4th player | Spirit with the inside team. Optional: the spirit's telekinesis is needed for one existing TK object in the level, so the extra player matters. | 2 |
| G6 | wwii_brandenburg | Church climbs alone; Cole and Rawlings are hidden as props near the Nazi Bitch. | Jones, Delgado, Black below; Cole and Rawlings | Players below **defend the monument's base** against the level's two existing waves (`primera_oleada`, `segunda_oleada`) while Church climbs, with radio beats. Cole and Rawlings players: spirits (in the story they are prisoners), then their bodies come back at `ReposPeople`. | 1 + 2 |
| G7 | cru_river → cru_catacomb (4 levels) | The bridge collapses and Jones, Cole and Rawlings are lost until the chapel rescue. Only 3 bodies exist. | with 4 players, one player | **Default:** the lost member's player is a spirit with the trio, and subtitle "echoes" tell what happened to the lost three (the orphan design note `cru_catacomb` `Tag_05` already imagines a rescue). **Big option (Tier 3), "The Lost Patrol":** the lost three get their own path through existing Crusades areas (for example cru_keep and cru_catacomb in reverse) as captives escaping, run by a second host, meeting the main group in cru_chapel where `TheRescue` plays. | 2 (3 optional) |
| G8 | cru_sewers | Church climbs alone; Black and Delgado wait, then are switched off (`bActive=false`). | Black's and Delgado's players | **Hold the gate:** they stay active below and fight new crusader and cultist waves at the gate (reused groups) until Church opens the door (`AperturaPuerta`). The descent QTE plays only for Church; the others see the fight. | 1 |
| G9 | rom_outskirts CenturiansTale | Forced switch to Rawlings, everyone locked. | — | The human holding Rawlings plays it; if nobody does, the host. Others watch from their own actor (it is a multi-character scene). | — |
| G10 | rom_caldarium fire | Delgado goes alone through the fire; the others are frozen. | everyone but Delgado | **Cover from the entrance:** the others stay active at the pinned point (`SetTeamsThere`) and fight torturers and cultists (reused groups) until Delgado pulls the lever. Optional beat: each lever stage Delgado reaches opens a door near them. | 1 |
| G11 | rom_palace_01 abyss | Church crosses alone with the QTE. | the others | The existing pressure-plate phase (`LosetaPuenteA/B/C` against `LegionariosPuente*`) starts during Church's crossing instead of after it, so both halves run at once. | 1 |
| G12 | sum_ziggurat_01 possession | Jones is possessed. | Jones' player | Jones' player becomes a spirit **fighting for Jones' body**: the astral view on Jones with a short "resist" task (hold the button when prompted); success ends the possession a little earlier. Purely cosmetic otherwise. | 2 |
| G13 | sum_ziggurat_02 / start of 03 | The teleport scatters everybody; Black is alone, Jones caged. | players 3-4 | Spirits that search with Black (the level has Jones-only astral levers, so the spirits' telekinesis can help with one). Delgado and Rawlings rejoin in 03 as in vanilla. | 2 |
| G14 | sum_ziggurat_04 | Cole and Church are hidden until the end. | their players | Spirits; their bodies return at `LetsGo`. | 2 |
| G15 | sum_end, final phase | Only Church fights; the others are stunned. | Black, Delgado, Rawlings | Keep fighting: the stun is removed (patch `EvilFirstBorn.SchMakeAllUnavailable`) and they hold off Arnold Leach's adds while Church finishes the Firstborn. The blood rune stays Church's. | 1 |

## Cutscenes with characters missing from the scene

If a player's character is in the level but has no actor in a scene (for example Church and
Cole in RossDeath), that player watches from a side camera next to the scene, or through the
scene owner's eyes. No new animation can be made for them. Where the gap is noticeable,
a one-line subtitle explains it (for example "Church and Cole cover the entrance").

## Order of work (proposal)

1. Tier 1 holds, in order of play time: G8, G10, G6, G11, G4, G15, G3, G1.
2. The spirit role (G2, G5, G7, G12-G14). One implementation covers all of them.
3. Tier 3 "The Lost Patrol" (G7) only after the rest, and only if wanted.

## Open questions for the owner

- Is the spirit role the right answer for "no body" players, or do you prefer a plain
  spectator camera?
- Should Tier 3 (G7, a parallel path for the lost trio) be planned at all?
- Is subtitle-only radio text acceptable for the new beats (no new voice lines exist)?

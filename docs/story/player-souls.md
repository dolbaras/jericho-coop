# Who the players are: Ross's soul, Jones's projection, the squad

Status: built in 0.2.4 (`lua/coop_souls.lua`; open questions answered below), completed in
0.2.5. Tested with two PCs and a split screen player (lab/souls024.ps1): roles by seat, seat 3's
switch refused, seat 2's allowed, the projection cut and back, a downed seat 3 waiting for
Rawlings.

0.2.5: a downed seat 3-4 waits for Rawlings only while she can come: not down, not walked or
taken by the story, on the same side of a story split and not held by the last boss's rune
(`CoopSplits.runeBound`: the rune's own schedule, not `Team.UnavaliablePlayers`, which the
tutorials also set while the locked character's AI still revives). The split screen player 2
is looked at again once a second while down, so a wait that can no longer end moves them into
a free body; the body left gets its AI back (the game turns it off during the agony animation
and on again at the revive). A body the rune holds is not one a downed player moves into, so
with every player down at the last boss the game ends as in the original.

## The problem

In the original the player is Ross's soul: after his death it lives on in the squad's bodies
and moves between them. In co-op every player can switch bodies, and nothing in the story says
where a second (third, fourth) soul that moves between bodies comes from. The spirit role for
players without a body is explained as "an echo of Ross's spirit" (coop-story-extensions.md,
coop_spirit.lua), but only in a few level hints, and not for a player who switches at will.

## What the game itself says (language files, cp1251 Russian localisation)

- Jones's power (`PC_Menu_Description_Jones_0/1`): hold the special key for the astral
  projection, targets glow white; "project yourself onto the glowing target. After a successful
  astral jump all of your target's abilities are yours." So Jones can, in canon, move his soul
  into another body and act with it. In the original the targets are enemies (the children,
  cultists) and objects, the projection lasts while the key is held, and his body stays behind.
- Ross after his death (`Scene_wwii_BigGates_Begin0-17`): "I'm still with you", "I think... I'm
  in him" (Delgado), about the body's owner "He's here. Just... resting", "Not all of me";
  Rawlings: "I want you to possess Abby. Can you do it?" No link to Jones's gift is made.
- The end (`HINT_Jones_235_L6_Body_Switch`): Jones to Ross: "This is your chance, Ross! Take
  your body back before it's too late!"

## The decision

- **Player 1 (the host) is Ross's soul**, as in the original: switches freely between bodies.
- **Player 2 (the first client) is Jones's projection**: Jones's gift (canon: possessing a body
  and using its abilities) reaches his squad mates too, so player 2 switches freely as well.
  This matches 0.2.3's squad leaders: the host and the first client are the two "main" players
  who lead a fire team each.
- **Players 3 and 4 are the squad members themselves**: they keep the body they chose. They
  move to another body only when they have to (joining, the story takes their character away,
  no body left: then they are the spirit, "an echo of Ross").

## Points to make as logical as possible (owner: yes to all)

1. **Jones's body while player 2 is in another one.** Use the canon of Ross's possession: the
   body's own mind "rests"; Jones's body walks and fights with the squad under the AI, as every
   body no human holds does now. Not spelled out in game.
2. **Where Jones cannot project**: the Lost Patrol (Jones is lost with the trio), the ziggurat
   possession (G12, Jones possessed), the cage (G13). Proposed: player 2's projection is cut
   ("Jones is held - your projection is cut") and they stay in the body they are in until Jones
   is free again; a short story beat rather than a hole. Alternative kept for the planning:
   "Jones's soul got out to the squad in time" (e.g. as the bridge falls).
3. **Act 1**: Ross is alive and in the original does not switch. Free switching for players 1
   and 2 starts with the scene at the big gates (WWII_BigGates), for both at once; a short line
   of Jones's after that scene (all six languages, marked as co-op's addition) tells that his
   projection can now do what Ross does. To check: whether clients can switch in Act 1 today.
4. **Players 3-4**: only forced moves; their own choice of character at the lobby / join stays.

5. **A downed player's body** (`coop_team.lua`, `Team.CheckGameOver`): today, as in the
   original, a player whose body goes down moves into the next living squad member no human
   holds, whichever branch of a split that member is on (seen 2026-10-23 in G8: the host's
   Delgado fell in the hall the players below hold, and the host moved into Church on his
   lone climb). Done in 0.2.3 at the owner's request (coop_splits.lua, Sp.sameSide): during
   a story split nobody moves into a body on the other side; with no free body on their own
   side they wait for Rawlings. For 0.2.4: players 3-4 should not move at all (they wait for
   Rawlings' revive or become the spirit near their body); players 1-2 keep the move within
   their side.

## Decisions on the open questions (owner, 2026-10-23)

- **Jones's body is not reserved:** player 3 may hold Jones's body while player 2's projection
  is elsewhere; player 2 starts in whichever body they pick in the lobby.
- **Split screen: by seat number.** The second player on a PC is simply the next seat of the
  session: seat 2 is Jones's projection and switches freely, seats 3-4 keep their body.
- **When the projection is cut** (Jones lost, possessed or caged): a short hint in the six
  languages plus the game's own end-of-projection fade and sound; player 2 stays in the body
  they are in until Jones is free again.
- **Squad menu for players 3-4:** the other squad members stay visible (health and so on) but
  greyed out; trying to switch shows the reason ("only Ross's soul and Jones's projection move
  between bodies").

## Where the game decides a switch (for the build)

- Voluntary switches: the squad menu (`Team.SetIdChar` puts `Team.SwitchSoldier` as the
  icon's `OnSelect`, shown only when `Team.IsPlayerAvaliable`) and aiming at a squad member
  and pressing the switch key (`Team.SwitchCharacter`).
- Forced moves go straight to `Team.SwitchSoldier`: a downed body (`Team.CheckGameOver`),
  story scripts, the mod's claims, splits, the Lost Patrol, the spirit taking a body. These
  stay allowed for every seat.

# Translation style (Jericho Co-op+)

Every text the mod shows exists in the mod's six languages (English, Russian, German, French, Spanish, Italian): in
the game (the modules' `en` / `ru` tables, `lua/lang_<de|fr|es|it>.lua`), in the installer and uninstaller
(`tools/installer.ps1`), the shortcut's launcher (`tools/launcher.ps1`) and the setup exe (`tools/mkinstaller/stub.c`).
`lua/tests/lang_mock_test.lua` and `tests/test_texts.ps1` check the coverage, the format directives, the code page
and the quotes; `lua/tests/display_mock_test.lua` the Video rows' length. The players' readme is English + Russian.

This file is the style each language keeps, so new texts read like the ones already there. Written 2026-11-11 for the
i18n review; no workspace-wide style guide existed then, so the shared words are chosen to match the TimeShift
Co-op guide (`docs/translation-style.md` there) where the games allow it.

## Rules for every language

- **The game's own words first.** Names of people, places, enemies and powers as the game's own texts write them in
  that language (`work\extracted\language\*.txt` in the lab: zlib after a 4-byte header, cp1251 for Russian, cp1252
  for the others). Russian: Черч (not Чёрч), Перворожденный, Альфа / Омега, культисты, тамплиеры. German: das
  Erstgeborene, das Team. French: la section, Oméga, le Premier Né, les fidèles. Spanish: el comando, Alfa, los
  acólitos. Italian: la squadra, i cultisti.
- **Women of the squad**: Billie Church, Simone Cole and Abigail Black are women. Russian: their names never decline
  (с Черч, за Коул, вместе с Блэк) and verbs agree (Черч вернулась, одна); French / Spanish / Italian agreements
  in the feminine (seule, sola, da sola, ocultas, nascoste). Ross, Jones, Delgado and Rawlings are men.
- **Register as the game's texts**, the same everywhere (game, installer, launcher, setup exe): Russian «вы», German
  "Sie", French "vous", Spanish "tú" (Spain), Italian "tu". A notice the whole group sees (CoopSplits) uses the plural
  of that register in Spanish and Italian ("Defended", "Tenete"); a card or a solo story line talks to one player.
- **Fonts** (the game draws cp1251 for Russian, cp1252 for the others; `Coop.enc`): only characters the game's own
  texts of that language use are known to draw. Russian: Cyrillic letters, ё, ASCII; NO « » and no em dash (the game
  writes " - " and puts no quotes in its texts). The others: Latin letters with their marks, « » (Spanish texts use
  them), ” and …; NOT proven „ “. So the game's texts of the mod use no quotation marks at all: a spoken line is
  "Name: text", as in the subtitles. In the installer, launcher and setup exe (Windows' fonts) the language's own
  quotes: ru «…», de „…“, fr « … », es «…», it «…»; English keeps '…'.
- **PowerShell trap**: PowerShell reads „ “ ” as its own double quotes (and ‘ ’ ‚ as single ones). In
  `installer.ps1` / `launcher.ps1` each needs a backtick (`` `„Koop`“ ``); `tests/test_texts.ps1` fails otherwise.
- **Lengths**: a Video row ("label: value", a three-digit rate with "(fullscreen)") stays at 33 characters or less
  (a 4:3 screen cuts it; `display_mock_test.lua`). The lobby's rows: no longer than the longest text of the same row
  in another language (German is usually the longest). Choice-card names are short capitals.
- **Format directives** (`%s`, `%d`, `%%`) in the English order: `string.format` takes them by position.
- **Colon**: German puts a capital after a colon that opens a sentence ("Ross lebt: Noch wechselt niemand ...");
  French puts a space before : and ; in the game's texts (the game's own majority) and before : ; ? ! in the tools;
  "!" and "?" in the game's French stay as the game writes them (no space).

## Shared words

| Concept | ru | de | fr | es | it |
|---|---|---|---|---|---|
| the mod (in the tools) | кооп-мод | der Koop-Mod | le mod coop | el mod cooperativo | la mod co-op |
| co-op (menu) | Совместная игра | Koop | Coop | Cooperativo | Co-op |
| host (person) | хост | Host | hôte | anfitrión | host |
| host (verb / button) | создать игру | Spiel hosten | héberger | crear partida | crea partita |
| join | присоединиться | beitreten | rejoindre | unirse | entra |
| lobby | лобби | Lobby | salon | sala de espera | lobby |
| ready | готов | bereit | prêt | listo | pronto |
| session | сессия | Sitzung | session | sesión | sessione |
| split screen | разделённый экран | geteilter Bildschirm | écran partagé | pantalla dividida | schermo diviso |
| controller | геймпад | Controller | manette | mando | controller |
| stick | стик | Stick | stick | palanca | levetta |
| squad | отряд | Team | section | comando | squadra |
| cutscenes | сюжетные сцены | Zwischensequenzen | cinématiques | cinemáticas | filmati |
| install / remove | установить / удалить | installieren / entfernen | installer / désinstaller | instalar / desinstalar | installare / rimuovere |
| version of a release | версия (not "релиз") | Version | version | versión | versione |

## Per language

- **English**: the source.
- **Russian**: «вы», "хост", "кооп-мод", "сюжетные сцены" (not "катсцены"), "версия"; no calques "держите ...
  против ..." ("удерживайте ..., отбиваясь от ..."); ё is written in the mod's texts (the game's names keep the game's
  spelling); in the game " - " and no quotes, in the tools «…» and "—".
- **German**: "Sie", "der Koop-Mod" (masculine, also "des Mods"), "Team" for the squad (the game's), "Controller",
  "Warten auf ..." for a waiting line, quotes „…“ in the tools.
- **French**: "vous", "le mod coop", "installateur", "la section", "Oméga", "les fidèles", "le Premier Né", the gate of
  Brandenburg "la porte", "le chemin des âmes"; a space before : ; (and ? ! in the tools).
- **Spanish** (Spain): "tú" (also in the setup exe and the SMOD hint); "el mod cooperativo", "anfitrión", "el comando",
  "Alfa" (feminine: la escuadra Alfa), "los acólitos", "la sala de los torturadores", "el Camino de las almas", the gate
  of Brandenburg "la puerta", "vista subjetiva".
- **Italian**: "tu" ("voi" for the group), "la mod co-op", "host", "controller", menu buttons in the imperative
  ("Continua", "Crea partita", "Esci"), the gate of Brandenburg "la porta" and the sewers' gate "il cancello".

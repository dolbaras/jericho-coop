Jericho Co-op+ for Clive Barker's Jericho
==============================================================================

ENGLISH
-------

Co-op for the Clive Barker's Jericho (2007, PC) campaign, 2-4 players. Each player controls
one squad member, the AI drives the rest. The host runs the world and the story; the others
join it. More than a co-op mode: where the squad splits, the players who stay behind get
their own story content (waves to hold, the Stations of the Path, the Lost Patrol as a
parallel branch); the host is Ross's soul and the second player Jones's astral projection,
both moving between bodies, the others keep their character. It also brings settings the
game lacks (display mode with a borderless window, refresh rate, aspect ratios up to 32:9),
fixes, six languages, and works with SMOD, "Clive Upscaler's Jericho" and DXVK.

Every problem found in tests and code reviews is fixed. The whole campaign, every story split
and the Lost Patrol run through in tests with two real games on two PCs; people have played
missions 1-8 so far. Please report problems (see below).

Requirements
- Your own copy of the game. Tested: retail DVD release (Jericho.exe SHA-256
  7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62), Windows 10 and 11.
  Other versions are untested.
- Every player needs the same mod version (the lobby says so when they differ).

Install
1. Extract the archive anywhere and run "Install Co-op.bat". It finds the game folder (or asks
   for it), keeps a copy of every file it replaces (in <game>\coop-backup) and installs the mod.
   Its window shows each step and a progress bar; building the cutscene animations from your
   game files takes 2-5 minutes (the minutes left are shown). Running it again updates the mod
   or removes it. It updates any earlier version of the mod, from the first test build (0.1.0)
   on, leaving none of its files behind. Its language is Windows' (English, Russian, German, French, Spanish,
   Italian), or pick one in the list at its top.
2. Start the game with the "Jericho Co-op+" shortcut the installer puts on the desktop and in the
   Start menu (the game's icon with a red co-op badge), or as usual. The main menu has a
   "Co-op" entry.
Updates: the shortcut first asks GitHub for the newest release of the mod (a second or two;
offline, the game simply starts). When there is a newer one, it downloads it (checked against
the release's SHA-256), runs its installer for your game folder and then starts the game. A log
is in <game>\coop\launcher-log.txt. Starting the game any other way skips this check.
Languages: the mod's menus and hints (and SMOD's) follow the game's language setting: English,
Russian, German, French, Spanish or Italian.
No mouse needed: the game itself refuses to start without one; on a PC with gamepads only the
mod gives it a mouse that never moves.
Uninstall: "Uninstall Co-op.bat" in the game folder - removes the mod and puts the replaced
files back. What the installer changes in the game: it marks the game's exe as able to use
4 GB of memory instead of 2 (large address aware; only the retail exe, the original is kept and
put back on uninstall) and builds Pack1.packed (cutscene animations, Ross's model) from your
game files. Single-player saves are not touched.
By hand: copy the contents of the "files" folder into the game folder (back up bin\dinput8.dll
if there is one).

Play
- Host: Co-op -> Host game -> pick a chapter (or Continue) -> Create session. In the lobby
  everyone picks a character and a nickname and presses Ready; the host presses Start.
  Session settings (host): difficulty, enemy toughness, who does character-only actions,
  QTEs, how much damage the AI squadmates take, and the cutscene view (below).
- The host picks the network when creating the game ("Network" row): local network or Steam.
  Each has its own way in:
- Local network: Co-op -> Join (local network) -> pick a game from the list or type the
  host's IP -> Connect. Ports UDP 28100 (game) and UDP 28199 (finding games on the local
  network); allow the game in Windows Firewall. Over the internet the host forwards UDP 28100
  on the router, or play over a virtual LAN (Radmin VPN, ZeroTier...) and connect to its IP.
- Steam: no ports or IPs. Steam must be running on every PC and the players must be Steam
  friends. Co-op -> Join through Steam lists your friends' games; or the host picks you in the
  lobby's "Invite friends (Steam)" list and you accept the invite in Steam while your game is
  on that Join through Steam screen. Steam shows the players as playing "Spacewar" (Valve's
  free sample app the mod runs as, see STEAM-NOTICE.txt). If Steam does not connect, the local
  network way still works.

How it works
- Act 1: the host plays Ross (as in the original), then Delgado after his death. Nobody
  switches bodies while Ross lives.
- Who you are: the host is Ross's soul and the second player (the first to join, or the split
  screen player 2 when nobody joined) is Jones's astral projection (in the game Jones can
  project himself into others). Both switch between the squad's bodies as in the original
  (squad menu, or aim at a squad member and press the switch key), from the scene at the big
  gates on. The third and fourth players are the squad members themselves: they keep the
  character they picked (the others are greyed out in their squad menu) and move only when
  they have to (the story takes their character, no Rawlings left to revive them, no body
  left: a spirit). While Jones is lost, possessed or caged, the second player's projection
  is cut and they stay in the body they are in.
- A downed player moves into a free squad member; during a story split (the squad split up
  by the story) only into one on their own side, else they wait for Rawlings.
- Only Rawlings revives downed players (human or AI), as in the original.
- Squad choice at a story split: before the squad splits, every player (the host too) sees one
  screen with the groups, their members and who picks what; choose with the stick/arrows and A/Enter
  (or keys 1-3) within about 25 s; if you do nothing you stay with your character. Shown at every
  split: Act 1 (the tomb, the city, the bunker; the player who holds Ross stays), Brandenburg, the
  Escalada split (Cru_Sewers), the fire hall (Rom_Caldarium), the pillboxes, the abyss, the final
  and the Lost Patrol. On split screen player 2 chooses with gamepad 2. Two players who want each
  other's characters swap them. The host cannot join the Lost Patrol (the host's game runs the
  main group).
- A downed player with nobody to move into watches a living player from behind (third person):
  stick or arrows (or A / D, the left mouse button) switch the player, the right stick or mouse
  looks around; the camera keeps clear of walls; it ends on revive.
- Enemies hurt every player the way they hurt the host: bullets, blows, flames (a flamethrower sets
  a joining player alight), missiles (pilums, bolts, blades, fireballs, mortar shells) and the
  bosses' own attacks. Enemy life is the same on both PCs.
- Everything that moves on the other PC (the other players' and the AI's characters, enemies) is
  drawn smoothly: the movement follows the host's states along a smoothed path, about 0.2 s behind
  and without the old stop-and-go; props the host moved glide to their place.
- Squad members are solid, as in the single-player game: your character no longer walks through
  another player's or the AI's character.
- Doors and invisible blockers are kept the same on every PC (a blocker that a PC's own script
  switched back is set to the host's state again within a second; any other difference heals in
  about ten seconds): fewer "invisible walls".
- The "character flies / stuck / snaps back and forth" storm after a Delgado-only door or lever
  (Rom_Outskirts and others) is fixed.
- Allies' animations are shown on every PC: cover, dazed, trance, astral and possession states,
  the dragon arm of Delgado, hurdles and climbs as a run on the spot; Cole's grenade throw
  no longer makes a second grenade on the other PC.
- Logs: the last five sessions are kept as coop.log (now) and coop.1.log ... coop.4.log; a start
  that only reached the menu does not push the older ones out.
- When the story walks a character a player holds, the player is offered to walk there first (the
  host's too); the squad takes over only after the time is up (or at once / never, per the
  lobby setting).
- Cole's and Black's slow motion slows the world for everyone; players keep their speed.
- Everyone sees the cutscenes at the same time, with the original camera; a scene seen through
  another character's eyes is captioned "Through X's eyes". A scene is skipped only when every
  player pressed Esc.
- Cutscene view (session setting): "original camera" (default) or "own eyes (experimental)":
  each player watches a first-person scene from their own character, with the scene's
  character shown as a full model. The view is directed: you look at whoever speaks, answer
  the one who spoke when your character talks, and follow what the scene shows otherwise;
  where your character's eyes cannot see the scene (a wall, someone in your face, the
  helicopter going down) the original camera takes over for that moment. The scene's
  character walks where the game only moved its camera. Still experimental: the sets were
  made for one camera. Its animations are built by the installer from your game files (the
  Python it needs comes with the mod, nothing to install).
- QTEs (session setting): "as in the game" - seen and played only by the player of the scene's
  character; "automatic" - they pass by themselves; "all players, one success" - everyone gets
  the QTE and it passes when at least one player succeeds.
- Character-only actions: the players are offered to take that character; if nobody does
  within 30 s, the AI does it (lobby setting).
- Squad orders ("Follow me" / "Hold position"): each fire team follows one player. Act 1, while
  Ross lives: Ross's player leads everyone. Otherwise Alpha (Jones, Cole, Delgado) and Omega
  (Church, Rawlings, Black) are each led by the first player (host, then the first client, then
  the others) whose character is in it; a team without a player in it goes to the first player
  who leads nothing yet. So two players lead a team each; a third and fourth lead none. When
  the squad is split up (a story split, a branch), AI members follow the player they are with.
  An order for a team someone else leads says who leads it.
- Breakable and movable objects (crates, barrels, bottles, lamps...) are the same for everyone:
  broken by anyone, broken everywhere; pushed or thrown, at rest in the same place.
- A story action of a character a player holds (Black's telekinesis on the prologue's rubble,
  for example) is that player's: a hint shows where to go; use a power there (or just stand
  there a moment). If they do not within 25 s, the AI walks the character there and does it.
- Cut off from the squad (the story shuts a door or a passage behind whoever goes first, or you
  are far away for a while)? A hint offers to hold T (gamepad: both sticks pressed) to be put
  next to the host's character.
- With more players than living squad members (or when the story takes a character away), a
  player becomes a "spirit": flies near the squad, marks enemies and can take a free body.
- Every player's powers act in the host's world (telekinesis, runes, fire, ghost bullets,
  Ababanili...), and doors, destroyed objects and the other players' and enemies' movement are
  the same on every screen.
- Co-op saves are kept apart from single-player ones: Documents\Codemasters\Clive Barker's
  Jericho\Coop. The single-player profile is not touched during a session.

SMOD
The co-op mod works next to SMOD (SkacikPL's mod pack) and finds it by itself; the lobby marks
the players who have it with [SMOD].
- Every player has SMOD: the session plays by the host's SMOD settings (its autoexec.lua):
  damage, head hits, damage the AI squadmates take, squad health, ironman and the checkpoint
  heal, the same on every machine. The host can turn this off in Session settings ("Rules").
- Not every player has SMOD: everyone plays by the game's own rules, so players with and
  without SMOD get the same game.
- Always off in a session: SMOD's pause and time scale, slow motion in the squad menu and its
  cheat/debug menus (they would stop the world for everyone or act on one machine only).
- Each player's own: FOV, lights, flashlight look, crosshair, recoil, the health counter.
- The others see your SMOD jump (even without SMOD).
- Every player's flashlight shows on the other screens as a beam from their weapon (with or
  without SMOD).
SMOD's own texts follow the game language.

SMOD Add-ons (PHM2D, nexusmods.com/clivebarkersjericho/mods/11, on top of SMOD)
The co-op mod finds them by itself; the lobby marks the players who have them with [SMOD+]. Their files
are yours: the installer never touches or copies them.
- Their third-person view (keys P and O) works for you alone. It is refused in split screen, in a
  cutscene and while you are down, and a player in it is put back into first person when one of
  these begins.
- Always off in a session: Jones' near-death slow motion, the astral slow motion and the F8 "easy
  QTE" switch (they would act on one machine only; the lobby's QTE setting rules).
- What a player does in third person (the dragon, the fire barrier, ghost heal, Vlad's curse,
  telekinesis, Church's spell) is shown to the others like any other body's action.
- Their balance numbers (health, damage, ammo, speed) are each player's own, like SMOD's looks.

Upscaled textures (Clive Upscaler's Jericho)
"Clive Upscaler's Jericho" (nexusmods.com/clivebarkersjericho/mods/8, 2x textures) works with
the co-op mod. It needs SMOD and DXVK: put x32\d3d9.dll of DXVK (the Windows build; 3.1.1
checked) into the game's bin folder. Ross's model for the other players in Act 1 gets the
upscaled textures too. Checked: all 33 levels loaded one after another, split screen, F11 clips.

Screen: aspect ratio, display mode, refresh rate
Main menu Configuration -> Video -> Aspect ratio: Auto (default: from the screen resolution),
4:3, 5:4, 16:10, 16:9, 21:9 (2560x1080), 21:9 (3440x1440), 32:9. The choice is kept by the mod
(the game's player profile used to put its own value back at the main menu, so editing game.cfg
did not hold). Split screen fills each half on a wide screen.
Display mode (the same screen): Full screen, Window, or Borderless window (a window without a
frame over the whole monitor; the picture is drawn at the chosen resolution and stretched, so
pick your monitor's own resolution). It changes at the next start of the game. With SMOD its
autoexec.lua (FullScreen) decides full screen; the window can still be borderless.
Refresh rate (the same screen): Auto (the game's default) or one your monitor has at the
resolution, in full screen.

Split screen
A second player on the same PC, in the same game: the screen is split top and bottom, each
player with their own view and HUD. In the lobby pick "Player 2 (gamepad)" and their
character; it works in a hosted game and when you join one (up to 4 players in a session).
- Gamepads: with two connected, player 1 uses the first (and keyboard + mouse), player 2 the
  second; with one connected, it is player 2's and player 1 plays with keyboard + mouse. A
  gamepad plugged in or out during play is assigned again within a few seconds (player 2 first).
- In menus and cutscenes the screen is whole again and both gamepads work there.
- Each half shows the whole picture with black bars at the sides; the HUD keeps its normal
  shape, its corners (weapons and ammo, powers, squad, SMOD's health) sit on the bars at the
  screen's edges and only the crosshair, messages and subtitles stay over the picture.
- Each player sees their own arms and the other player's whole body, and the screen effects
  of a power (blur, colours, noise) only in the half of the player who uses it. Delgado's fire
  barrier flames are not shown in split screen (they would cover both halves); the barrier
  itself works.
- All powers work for both players. Jones's astral projection: while one player projects, the
  other plays on from their gamepad (with a simple crosshair and ammo count: the game hides its
  own HUD then); player 1 on keyboard + mouse only waits meanwhile (the game has one set of
  controls during a projection).
- It uses the game's own split screen leftovers (from the engine's Scrapland days): each frame
  draws one player's view in turn, so each view runs at half the frame rate.

Reports
https://github.com/dolbaras/jericho-coop/issues — what happened, on which level, host or client.
Attach the log: Documents\Codemasters\Clive Barker's Jericho\Coop\coop.log (the current run; the
four runs before it are kept as coop.1.log (the last one) ... coop.4.log, so attach the one of the
session where it happened; a start that only reached the menu does not push them out).
Saw it happen? Press F11 right after: the last 30 seconds of the game are saved as a video
(clip-<date>-<time>.avi in the same Coop folder) - attach it too. The mod keeps only what the
game draws, in memory, and writes nothing until F11.


РУССКИЙ
-------

Совместное прохождение кампании Clive Barker's Jericho (2007, PC) на 2-4 игроков.
Каждый игрок управляет своим бойцом отряда, остальными управляет ИИ. Хост ведёт мир и
сюжет, остальные подключаются к нему. Это больше, чем кооп: где отряд разделяется, у
оставшихся игроков свой сюжет (волны, Путь душ Роулингса, «Потерянный патруль» параллельной
веткой); хост — душа Росса, второй игрок — астральная проекция Джонса, оба переселяются
между телами, остальные остаются в своём персонаже. Ещё мод добавляет настройки, которых в
игре нет (режим экрана с окном без рамки, частота обновления, форматы до 32:9), исправления,
шесть языков и работает со SMOD, «Clive Upscaler's Jericho» и DXVK.

Исправлено всё, что нашли тесты и проверки кода. Вся кампания, все сюжетные разделения и
«Потерянный патруль» пройдены в тестах двумя настоящими играми на двух ПК; живые игроки пока
прошли миссии 1-8. Пожалуйста, сообщайте об ошибках (см. ниже).

Что нужно
- Своя копия игры. Проверено на розничной DVD-версии (Jericho.exe SHA-256
  7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62), Windows 10 и 11.
  Другие версии не проверялись.
- Мод должен стоять у всех игроков, одной и той же версии (если версии разные, лобби об
  этом скажет).

Установка
1. Распакуйте архив куда угодно и запустите «Install Co-op.bat». Он сам найдёт папку игры (или
   спросит её), сохранит копию каждого файла, который заменяет (в <папка игры>\coop-backup), и
   установит мод. В его окне видны шаги и полоса прогресса; сборка анимаций катсцен из ваших
   файлов игры занимает 2-5 минут (показано, сколько осталось). Повторный запуск обновляет мод
   или удаляет его. Он обновляет любую прежнюю версию мода, начиная с первой тестовой (0.1.0),
   не оставляя её файлов. Язык окна — как у Windows (английский, русский, немецкий, французский,
   испанский, итальянский), его можно сменить в списке вверху окна.
2. Запускайте игру ярлыком «Jericho Co-op+», который установщик кладёт на рабочий стол и в меню
   «Пуск» (значок игры с красным знаком коопа), или как обычно. В главном меню появится пункт
   «Совместная игра».
Обновления: ярлык сначала спрашивает у GitHub, вышла ли новая версия мода (секунда-две; без
интернета игра просто запускается). Если вышла, он скачивает её (с проверкой по SHA-256
выпуска), запускает её установщик для вашей папки игры и только потом запускает игру. Журнал —
<папка игры>\coop\launcher-log.txt. При запуске игры другим способом проверки нет.
Языки: меню и подсказки мода (и SMOD) следуют языку игры: английский, русский, немецкий,
французский, испанский или итальянский.
Мышь не нужна: сама игра без мыши не запускается, но на ПК только с геймпадами мод подставляет
ей мышь, которая никогда не двигается.
Удаление: «Uninstall Co-op.bat» в папке игры — удаляет мод и возвращает заменённые файлы.
Что установщик меняет в игре: помечает exe игры как способный использовать 4 ГБ памяти вместо 2
(large address aware; только розничный exe, оригинал сохраняется и возвращается при удалении) и
собирает Pack1.packed (анимации катсцен, модель Росса) из файлов вашей игры. Одиночные сохранения
не затрагиваются.
Вручную: скопируйте содержимое папки «files» в папку игры (если в bin уже был dinput8.dll,
сохраните его копию).

Как играть
- Хост: «Совместная игра» -> «Создать игру» -> выбрать главу (или «Продолжить») ->
  «Создать сессию». В лобби каждый выбирает персонажа и ник и нажимает «Готов», хост — «Начать».
  «Настройки сессии» (хост): сложность, живучесть врагов, кто делает действия персонажей,
  QTE, сколько урона получают союзники ИИ и вид катсцен (ниже).
- Сеть хост выбирает при создании игры (строка «Сеть»): локальная сеть или Steam. У каждой
  свой вход:
- Локальная сеть: «Совместная игра» -> «Присоединиться (локальная сеть)» -> выбрать игру из
  списка или ввести IP хоста -> «Подключиться». Порты UDP 28100 (игра) и UDP 28199 (поиск игр
  в локальной сети); разрешите игре доступ в брандмауэре Windows. Через интернет: хосту нужно
  пробросить UDP 28100 на роутере, либо играйте через виртуальную локальную сеть (Radmin VPN,
  ZeroTier и т.п.) и подключайтесь по её IP.
- Steam: без портов и IP. Steam должен быть запущен на каждом ПК, а игроки — быть друзьями в
  Steam. «Совместная игра» -> «Присоединиться через Steam» показывает игры ваших друзей; либо
  хост выбирает вас в списке «Пригласить друзей (Steam)» в лобби, а вы принимаете приглашение
  в Steam, пока в игре открыт экран «Присоединиться через Steam». Steam показывает игроков как
  играющих в «Spacewar» (бесплатное демо-приложение Valve, под которым работает мод, см.
  STEAM-NOTICE.txt). Если через Steam не подключается, локальная сеть по-прежнему работает.

Как устроено
- Акт 1: хост играет за Росса (как в оригинале), после его гибели — за Дельгадо. Пока Росс
  жив, никто не переселяется между телами.
- Кто вы: хост — душа Росса, второй игрок (первый подключившийся или второй игрок сплитскрина,
  если никто не подключился) — астральная проекция Джонса (в игре Джонс умеет вселяться в
  других). Оба переселяются между бойцами отряда, как в оригинале (меню отряда или прицел на
  бойца и клавиша переключения), начиная со сцены у больших ворот. Третий и четвёртый игроки —
  сами бойцы отряда: они остаются в выбранном персонаже (остальные в их меню отряда серые) и
  переходят в другое тело, только когда иначе нельзя (сюжет забирает их персонажа, некому их
  поднять, не осталось тела — тогда дух). Пока Джонс потерян, одержим или в клетке, проекция
  второго игрока обрывается, и он остаётся в том теле, где был.
- Упавший игрок переселяется в свободного бойца; во время сюжетного разделения (сюжет разводит
  отряд) — только в бойца на своей стороне, иначе ждёт Роулингса.
- Поднимать упавших может только Роулингс (игрок или ИИ), как в оригинале.
- Выбор отряда при сюжетном разделении: перед разделением все игроки (и хост) видят один экран с
  группами, их составом и тем, кто что выбирает; выбор стиком или стрелками и A/Enter (или клавишами 1-3)
  примерно за 25 с; если ничего не делать, остаётесь со своим персонажем. Экран показывается на каждом
  разделении: первый акт (гробница, город, бункер; игрок, который держит Росса, остаётся), Бранденбург,
  Эскалада (Cru_Sewers), огненный зал (Rom_Caldarium), доты, бездна, финал и «Потерянный патруль». В
  сплитскрине второй игрок выбирает геймпадом 2. Двое игроков, которые хотят персонажей друг друга,
  меняются ими. Хост в «Потерянный патруль» уйти не может (игра хоста ведёт основную группу).
- Упавший игрок, которому некуда перейти, смотрит за живым игроком сзади (от третьего лица): стик или
  стрелки (или A / D, левая кнопка мыши) переключают игрока, правый стик или мышь осматриваются; камера
  не заходит в стены; наблюдение кончается при поднятии.
- Враги ранят каждого игрока так же, как хоста: пули, удары, огонь (огнемёт поджигает подключившегося
  игрока), снаряды (копья, болты, клинки, огненные шары, мины миномёта) и собственные атаки боссов.
  Здоровье врагов одинаково на обоих ПК.
- Всё, что движется на другом ПК (персонажи других игроков и ИИ, враги), рисуется плавно: движение идёт
  по сглаженному пути через состояния хоста, примерно на 0,2 с позади и без прежних «рывков с
  остановками»; предметы, которые сдвинул хост, плавно доезжают на место.
- Бойцы отряда твёрдые, как в одиночной игре: ваш персонаж больше не проходит сквозь персонажа другого
  игрока или ИИ.
- Двери и невидимые барьеры держатся одинаковыми на всех ПК (барьер, который собственный сценарий ПК
  вернул назад, снова ставится по состоянию хоста меньше чем за секунду; любое другое расхождение
  лечится примерно за десять секунд): меньше «невидимых стен».
- Исправлена «буря»: персонаж улетает / застревает / дёргается туда-сюда после двери или рычага только
  для Дельгадо (Rom_Outskirts и другие).
- Анимации союзников показываются на каждом ПК: состояния укрытия, оглушения, транса, астрала и вселения,
  рука дракона Дельгадо, прыжки через препятствия и подъёмы как бег на месте; бросок гранаты Коула
  больше не создаёт вторую гранату на другом ПК.
- Журналы: хранятся последние пять сеансов: coop.log (текущий) и coop.1.log ... coop.4.log; запуск,
  дошедший только до меню, старые не вытесняет.
- Когда сюжет ведёт персонажа, которого держит игрок, игроку сначала предлагают дойти самому (в том числе
  хосту); отряд берёт управление только после времени ожидания (или сразу / никогда, по настройке лобби).
- Замедление времени Коула и Блэка действует на мир для всех, игроки двигаются с обычной скоростью.
- Катсцены видят все одновременно, оригинальной камерой; если сцена показана глазами
  другого персонажа, вверху подпись «Вид глазами: …». Пропуск сцены — только когда Esc
  нажали все игроки.
- Вид катсцен (настройка сессии): «камера оригинала» (по умолчанию) или «своими глазами
  (эксп.)»: каждый игрок смотрит сцену от первого лица из глаз своего персонажа, а персонаж
  сцены показан полной моделью. Вид поставлен как режиссура: вы смотрите на того, кто говорит,
  отвечаете взглядом тому, кто говорил, когда говорит ваш персонаж, а в остальное время следите
  за тем, что показывает сцена; где глазами персонажа сцену не увидеть (стена, кто-то вплотную,
  падение вертолёта), на этот момент включается камера оригинала. Персонаж сцены идёт шагом
  там, где игра двигала только его камеру. Режим всё ещё экспериментальный: декорации сделаны
  под одну камеру. Анимации для него установщик собирает из файлов вашей игры (нужный для этого
  Python входит в мод, ставить ничего не нужно).
- QTE (настройка сессии): «как в игре» — видит и проходит только тот, кто играет за персонажа
  сцены; «автоматически» — проходят сами; «все, хватит одного успеха» — QTE получают все
  игроки, и оно пройдено, если справился хотя бы один.
- Действия, которые может сделать только определённый персонаж: игрокам предлагают взять
  этого персонажа, если никто не взял за 30 с — делает ИИ (настраивается в лобби).
- Приказы отряду («За мной» / «Стоять»): каждая группа следует за одним игроком. В акте 1,
  пока жив Росс, всем отрядом командует игрок за Росса. Иначе «Альфой» (Джонс, Коул,
  Дельгадо) и «Омегой» (Чёрч, Роулингс, Блэк) командует первый игрок (хост, затем первый
  клиент, затем остальные), чей персонаж в этой группе; группа без игроков достаётся первому
  игроку, у которого группы ещё нет. Так двое игроков командуют каждый своей группой, третий
  и четвёртый — никакой. Когда отряд разделён (сюжетное разделение, ответвление), бойцы ИИ
  следуют за игроком, с которым они рядом. Приказ группе, которой командует другой, подскажет,
  кто ею командует.
- Разрушаемые и двигаемые предметы (ящики, бочки, бутылки, лампы...) одинаковы у всех: сломан
  кем угодно — сломан везде; сдвинут или брошен — лежит в одном и том же месте.
- Сюжетное действие персонажа, которого держит игрок (например, телекинез Блэк на завале в
  прологе), — за этим игроком: подсказка покажет, куда подойти; там примените способность (или
  просто постойте секунду). Если за 25 с игрок этого не сделал, персонажа доводит и действует ИИ.
- Отстали от отряда (сюжет закрыл дверь или проход за теми, кто прошёл первым, или вы долго
  далеко)? Подсказка предложит удерживать T (геймпад: оба стика нажаты), чтобы оказаться рядом
  с персонажем хоста.
- Если игроков больше, чем живых бойцов (или персонаж ушёл по сюжету), игрок становится
  «духом»: летает рядом с отрядом, отмечает врагов и может занять свободное тело.
- Способности каждого игрока действуют в мире хоста (телекинез, руны, огонь, призрачные пули,
  Абабанили…), а двери, разрушенные предметы и движение других игроков и врагов на всех
  экранах одинаковые.
- Совместное сохранение отдельно от одиночного: Документы\Codemasters\Clive Barker's
  Jericho\Coop. Одиночный профиль во время сессии не трогается.

SMOD
Мод работает вместе со SMOD (сборка SkacikPL) и сам его распознаёт; в лобби у игроков со SMOD
стоит пометка [SMOD].
- SMOD у всех игроков: в сессии действуют настройки SMOD хоста (его autoexec.lua): урон,
  попадания в голову, урон по союзникам ИИ, здоровье отряда, ironman и лечение на чекпоинтах,
  одинаково на всех машинах. Хост может выключить это в «Настройках сессии» («Правила»).
- SMOD не у всех: у всех правила самой игры, чтобы игроки со SMOD и без него играли в одно
  и то же.
- В сессии всегда выключены: пауза и ускорение времени SMOD, замедление в меню отряда и меню
  читов/отладки (они остановили бы мир для всех или действовали бы только на одной машине).
- У каждого своё: FOV, свет, вид фонаря, прицел, отдача, счётчик здоровья.
- Ваш прыжок SMOD видят остальные (даже без SMOD).
- Фонарь каждого игрока виден на экранах остальных как луч от его оружия (со SMOD и без).
Надписи SMOD показываются на языке игры.

SMOD Add-ons (PHM2D, nexusmods.com/clivebarkersjericho/mods/11, поверх SMOD)
Мод находит их сам; в лобби у игроков с ними стоит пометка [SMOD+]. Их файлы ваши: установщик их не
трогает и не копирует.
- Их вид от третьего лица (клавиши P и O) работает только для вас. В разделённом экране, в
  ролике и пока вы повержены он запрещён, а игрока, который в нём, возвращает в вид от первого
  лица, когда что-то из этого начинается.
- В сессии всегда выключены: замедление Джонса при малом здоровье, замедление астрала и
  переключатель «лёгкого QTE» на F8 (они действовали бы на одной машине; QTE решает лобби).
- То, что игрок делает от третьего лица (дракона, огненный барьер, призрачное лечение, проклятие
  Влада, телекинез, заклинание Чёрча), остальные видят как действие любого другого тела.
- Их числа баланса (здоровье, урон, патроны, скорость) у каждого свои, как внешний вид SMOD.

Увеличенные текстуры (Clive Upscaler's Jericho)
«Clive Upscaler's Jericho» (nexusmods.com/clivebarkersjericho/mods/8, текстуры x2) работает с
кооперативом. Ему нужны SMOD и DXVK: положите x32\d3d9.dll из DXVK (сборка для Windows;
проверена 3.1.1) в папку bin игры. Модель Росса для других игроков в акте 1 тоже получает
увеличенные текстуры. Проверено: все 33 уровня загружены подряд, сплитскрин, клипы F11.

Экран: формат, режим экрана, частота обновления
Конфигурация -> Видео -> Формат: Авто (по умолчанию: по разрешению экрана), 4:3, 5:4, 16:10, 16:9,
21:9 (2560x1080), 21:9 (3440x1440), 32:9. Выбор запоминает мод (профиль игрока раньше возвращал
при входе в меню своё значение, поэтому правка game.cfg не держалась). Сплитскрин на широком
экране заполняет каждую половину.
Режим экрана (тот же экран): Полный экран, Окно или Окно без рамки (окно без рамки на весь
монитор; картинка рисуется в выбранном разрешении и растягивается, поэтому выберите родное
разрешение монитора). Меняется при следующем запуске игры. Со SMOD полный экран задаёт его
autoexec.lua (FullScreen); окно всё равно можно сделать без рамки.
Частота обновления (тот же экран): Авто (как у игры) или одна из частот монитора при этом
разрешении, в полном экране.

Сплитскрин
Второй игрок на том же ПК, в той же игре: экран делится на верх и низ, у каждого игрока свой
вид и свой HUD. В лобби выберите «Игрок 2 (геймпад)» и его персонажа; работает и в своей
игре, и при подключении к чужой (в сессии до 4 игроков).
- Геймпады: если подключены два, у игрока 1 первый (и клавиатура с мышью), у игрока 2 второй;
  если подключён один, он у игрока 2, а игрок 1 играет клавиатурой и мышью. Геймпад,
  подключённый или отключённый во время игры, назначается заново за несколько секунд (сначала
  игроку 2).
- В меню и катсценах экран снова целый, и там работают оба геймпада.
- В каждой половине видна вся картинка, по бокам чёрные полосы; HUD в своих обычных
  пропорциях: его углы (оружие и патроны, способности, отряд, здоровье SMOD) стоят на полосах
  у краёв экрана, а над картинкой остаются только прицел, сообщения и субтитры.
- Каждый видит свои руки и второго игрока целиком, а экранные эффекты способностей (размытие,
  цвет, шум) — только в половине того, кто ими пользуется. Пламя огненного барьера Дельгадо в
  сплитскрине не показывается (оно закрыло бы обе половины), сам барьер работает.
- Все способности работают у обоих игроков. Астральная проекция Джонс: пока один игрок в
  проекции, другой играет дальше со своего геймпада (с простым прицелом и счётчиком патронов:
  свой HUD игра в это время прячет); первый игрок на клавиатуре и мыши в это время только ждёт
  (управление во время проекции в игре одно на всех).
- Сделано на остатках сплитскрина самого движка (со времён Scrapland): кадры по очереди рисуют
  вид каждого игрока, поэтому у каждого вида половина частоты кадров.

Сообщить об ошибке
Пишите в https://github.com/dolbaras/jericho-coop/issues : что делали, на каком уровне,
хост вы или клиент. Приложите лог: Документы\Codemasters\Clive Barker's Jericho\Coop\coop.log
(текущий запуск; четыре предыдущих хранятся как coop.1.log (последний) ... coop.4.log — приложите
лог того сеанса, где это случилось; запуск, дошедший только до меню, их не вытесняет).
Увидели ошибку? Сразу нажмите F11: последние 30 секунд игры сохранятся как видео
(clip-<дата>-<время>.avi в той же папке Coop) — приложите и его. Мод хранит только то, что рисует
игра, в памяти, и ничего не записывает до нажатия F11.

License: MIT (LICENSE.txt). ENet 1.3.18 (MIT, ENET-LICENSE.txt). coop\steam_api.dll: Valve's
Steamworks API (STEAM-NOTICE.txt). coop\python: Python 3.12.10's embeddable build from
python.org (PSF license, coop\python\LICENSE.txt), used only by the installer. No game files
are included.
Credits: the Steam option, shared QTEs, smoother movement, door/object and power sync come
from MAK-PIVO's fork (MAK-PIVO/jericho-coop, MIT; no longer public since 2026-10-22), adapted and
tested here.
SMOD is SkacikPL's, SMOD Add-ons are PHM2D's; their authors allowed this mod to be made compatible with
theirs. No file of either is included here.
Благодарности: SMOD - SkacikPL, SMOD Add-ons - PHM2D; их авторы разрешили сделать этот мод совместимым
с их работами. Файлов ни того, ни другого здесь нет.

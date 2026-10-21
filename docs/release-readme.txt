Clive Barker's Jericho — Co-op mod (test build / тестовая версия)
==================================================================

ENGLISH
-------

Co-op for the Clive Barker's Jericho (2007, PC) campaign, 2-4 players. Each player controls
one squad member, the AI drives the rest. The host runs the world and the story; the others
join it.

This is a test build: the whole campaign runs through in automated tests, but human
playthroughs have only just started. Please report problems (see below).

Requirements
- Your own copy of the game. Tested: retail DVD release (Jericho.exe SHA-256
  7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62), Windows 10 and 11.
  Other versions are untested.
- Every player needs the same mod version (the lobby says so when they differ).

Install
1. Extract the archive anywhere and run "Install Co-op.bat". It finds the game folder (or asks
   for it), keeps a copy of every file it replaces (in <game>\coop-backup) and installs the mod.
   Running it again updates the mod or removes it.
2. Start the game as usual. The main menu has a "Co-op" entry.
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
- Steam (experimental): no ports or IPs. Steam must be running on every PC. Co-op -> Join
  through Steam lists your Steam friends' games; or the host invites you from the lobby
  ("Invite friends (Steam)") and you accept in Steam while the game is on that Join through
  Steam screen. Steam shows the players as playing "Spacewar" (Valve's free sample app the
  mod runs as, see STEAM-NOTICE.txt). Tested with a real Steam client and between two PCs, but
  not yet between two real Steam accounts: if it fails, use the local network way.

How it works
- Act 1: the host plays Ross (as in the original), then Delgado after his death.
- Only Rawlings revives downed players (human or AI), as in the original.
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
Attach the log: Documents\Codemasters\Clive Barker's Jericho\Coop\coop.log (coop.prev.log is the
previous run).
Saw it happen? Press F11 right after: the last 30 seconds of the game are saved as a video
(clip-<date>-<time>.avi in the same Coop folder) - attach it too. The mod keeps only what the
game draws, in memory, and writes nothing until F11.


РУССКИЙ
-------

Совместное прохождение кампании Clive Barker's Jericho (2007, PC) на 2-4 игроков.
Каждый игрок управляет своим бойцом отряда, остальными управляет ИИ. Хост ведёт мир и
сюжет, остальные подключаются к нему.

Это тестовая версия: вся кампания проходится в автоматических тестах, а живые прохождения
людьми только начались. Ошибки возможны — пожалуйста, сообщайте о них (см. ниже).

Что нужно
- Своя копия игры. Проверено на розничной DVD-версии (Jericho.exe SHA-256
  7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62), Windows 10 и 11.
  Другие версии не проверялись.
- Мод должен стоять у всех игроков, одной и той же версии (если версии разные, лобби об
  этом скажет).

Установка
1. Распакуйте архив куда угодно и запустите «Install Co-op.bat». Он сам найдёт папку игры (или
   спросит её), сохранит копию каждого файла, который заменяет (в <папка игры>\coop-backup), и
   установит мод. Повторный запуск обновляет мод или удаляет его.
2. Запустите игру как обычно. В главном меню появится пункт «Совместная игра».
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
- Steam (экспериментально): без портов и IP. Steam должен быть запущен на каждом ПК.
  «Совместная игра» -> «Присоединиться через Steam» показывает игры ваших друзей в Steam; либо
  хост приглашает из лобби («Пригласить друзей (Steam)»), а вы принимаете приглашение в Steam,
  пока в игре открыт экран «Присоединиться через Steam». Steam показывает игроков как играющих
  в «Spacewar» (бесплатное демо-приложение Valve, под которым работает мод, см.
  STEAM-NOTICE.txt). Проверено с настоящим клиентом Steam и между двумя ПК, но ещё не между
  двумя настоящими аккаунтами Steam: если не получится, подключайтесь через локальную сеть.

Как устроено
- Акт 1: хост играет за Росса (как в оригинале), после его гибели — за Дельгадо.
- Поднимать упавших может только Роулингс (игрок или ИИ), как в оригинале.
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
(лог прошлого запуска — coop.prev.log).
Увидели ошибку? Сразу нажмите F11: последние 30 секунд игры сохранятся как видео
(clip-<дата>-<время>.avi в той же папке Coop) — приложите и его. Мод хранит только то, что рисует
игра, в памяти, и ничего не записывает до нажатия F11.

License: MIT (LICENSE.txt). ENet 1.3.18 (MIT, ENET-LICENSE.txt). coop\steam_api.dll: Valve's
Steamworks API (STEAM-NOTICE.txt). coop\python: Python 3.12.10's embeddable build from
python.org (PSF license, coop\python\LICENSE.txt), used only by the installer. No game files
are included.
Credits: the Steam option, shared QTEs, smoother movement, door/object and power sync come
from MAK-PIVO's fork (https://github.com/MAK-PIVO/jericho-coop, MIT), adapted and tested here.

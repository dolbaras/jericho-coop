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
- Every player needs the same mod version.

Install
1. Extract the archive anywhere and run "Install Co-op.bat". It finds the game folder (or asks
   for it), keeps a copy of every file it replaces (in <game>\coop-backup) and installs the mod.
   Running it again updates the mod or removes it.
2. Start the game as usual. The main menu has a "Co-op" entry.
Uninstall: "Uninstall Co-op.bat" in the game folder - removes the mod and puts the replaced
files back. The mod does not change game files or single-player saves.
By hand: copy the contents of the "files" folder into the game folder (back up bin\dinput8.dll
if there is one).

Play
- Host: Co-op -> Host game -> pick a chapter (or Continue) -> Create session. In the lobby
  everyone picks a character and a nickname and presses Ready; the host presses Start.
  Session settings (host): difficulty, enemy toughness, who does character-only actions,
  automatic QTEs, how much damage the AI squadmates take.
- Others: Co-op -> Join game -> pick a game from the local network list or type the host's
  IP -> Connect.
- Network: UDP 28100 (game) and UDP 28199 (finding games on the local network). Allow the game
  in Windows Firewall. Over the internet the host forwards UDP 28100 on the router, or play over
  a virtual LAN (Radmin VPN, ZeroTier...) and connect to its IP.

How it works
- Act 1: the host plays Ross (as in the original), then Delgado after his death.
- Only Rawlings revives downed players (human or AI), as in the original.
- Cole's and Black's slow motion slows the world for everyone; players keep their speed.
- Everyone sees the cutscenes at the same time, with the original camera; a scene seen through
  another character's eyes is captioned "Through X's eyes". A scene is skipped only when every
  player pressed Esc.
- QTEs are seen and played only by the player of the scene's character (or pass by themselves
  if the host turned on automatic QTEs).
- Character-only actions: the players are offered to take that character; if nobody does
  within 30 s, the AI does it (lobby setting).
- With more players than living squad members (or when the story takes a character away), a
  player becomes a "spirit": flies near the squad, marks enemies and can take a free body.
- Co-op saves are kept apart from single-player ones: Documents\Codemasters\Clive Barker's
  Jericho\Coop. The single-player profile is not touched during a session.

SMOD
The co-op mod works next to SMOD (SkacikPL's mod pack) and finds it by itself. In a session
everyone plays by the game's own rules, so players with and without SMOD get the same game:
SMOD's damage and health multipliers, ironman, checkpoint heal, slow motion in the squad menu,
its pause and its cheat/debug menus are off during a session. SMOD's looks (FOV, lights,
flashlight, crosshair, recoil) and its jump stay. SMOD's own texts follow the game language.

Split screen (experimental)
Two copies of the game side by side on one PC, one session between them. Double-click
"Co-op split screen.bat" in the game folder.
- Window 1 (left): keyboard + mouse and gamepad 1. It hosts: Co-op -> Host game, as usual.
- Window 2 (right): gamepad 2 only. It joins window 1's lobby by itself and is ready; its
  player picks the character there. Sound comes from window 1.
- Needs a PC that can run the game twice at once; closing one window closes both.
- Options: coop-splitscreen.ps1 -TopBottom (one above the other), -Pads2 <n> (which gamepad
  window 2 uses, 0-3).

Reports
https://github.com/dolbaras/jericho-coop/issues — what happened, on which level, host or client.
Attach the log: Documents\Codemasters\Clive Barker's Jericho\Coop\coop.log (coop.prev.log is the
previous run; split screen window 2: coop-window2.log).


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
- Мод должен стоять у всех игроков, одной и той же версии.

Установка
1. Распакуйте архив куда угодно и запустите «Install Co-op.bat». Он сам найдёт папку игры (или
   спросит её), сохранит копию каждого файла, который заменяет (в <папка игры>\coop-backup), и
   установит мод. Повторный запуск обновляет мод или удаляет его.
2. Запустите игру как обычно. В главном меню появится пункт «Совместная игра».
Удаление: «Uninstall Co-op.bat» в папке игры — удаляет мод и возвращает заменённые файлы.
Файлы игры и одиночные сохранения мод не меняет.
Вручную: скопируйте содержимое папки «files» в папку игры (если в bin уже был dinput8.dll,
сохраните его копию).

Как играть
- Хост: «Совместная игра» -> «Создать игру» -> выбрать главу (или «Продолжить») ->
  «Создать сессию». В лобби каждый выбирает персонажа и ник и нажимает «Готов», хост — «Начать».
  «Настройки сессии» (хост): сложность, живучесть врагов, кто делает действия персонажей,
  автоматические QTE, сколько урона получают союзники ИИ.
- Остальные: «Совместная игра» -> «Присоединиться» -> выбрать игру из списка «Игры в
  локальной сети» или ввести IP хоста -> «Подключиться».
- Сеть: порты UDP 28100 (игра) и UDP 28199 (поиск игр в локальной сети). Разрешите игре доступ
  в брандмауэре Windows. Через интернет: хосту нужно пробросить UDP 28100 на роутере, либо
  играйте через виртуальную локальную сеть (Radmin VPN, ZeroTier и т.п.) и подключайтесь по её IP.

Как устроено
- Акт 1: хост играет за Росса (как в оригинале), после его гибели — за Дельгадо.
- Поднимать упавших может только Роулингс (игрок или ИИ), как в оригинале.
- Замедление времени Коула и Блэка действует на мир для всех, игроки двигаются с обычной скоростью.
- Катсцены видят все одновременно, оригинальной камерой; если сцена показана глазами
  другого персонажа, вверху подпись «Вид глазами: …». Пропуск сцены — только когда Esc
  нажали все игроки.
- QTE видит и проходит только тот, кто играет за персонажа сцены (или они проходят сами,
  если хост включил автоматические QTE).
- Действия, которые может сделать только определённый персонаж: игрокам предлагают взять
  этого персонажа, если никто не взял за 30 с — делает ИИ (настраивается в лобби).
- Если игроков больше, чем живых бойцов (или персонаж ушёл по сюжету), игрок становится
  «духом»: летает рядом с отрядом, отмечает врагов и может занять свободное тело.
- Совместное сохранение отдельно от одиночного: Документы\Codemasters\Clive Barker's
  Jericho\Coop. Одиночный профиль во время сессии не трогается.

SMOD
Мод работает вместе со SMOD (сборка SkacikPL) и сам его распознаёт. В сессии у всех действуют
правила самой игры, чтобы игроки со SMOD и без него играли в одно и то же: множители урона
и здоровья SMOD, ironman, лечение на чекпоинтах, замедление в меню отряда, его пауза и меню
читов/отладки на время сессии выключены. Внешние улучшения SMOD (FOV, свет, фонарь, прицел,
отдача) и его прыжок остаются. Надписи SMOD показываются на языке игры.

Сплитскрин (экспериментально)
Две копии игры рядом на одном ПК, одна сессия между ними. Запустите «Co-op split screen.bat»
в папке игры.
- Окно 1 (слева): клавиатура + мышь и геймпад 1. Оно создаёт игру: «Совместная игра» ->
  «Создать игру», как обычно.
- Окно 2 (справа): только геймпад 2. Оно само подключается к лобби окна 1 и отмечает «Готов»;
  его игрок выбирает персонажа там. Звук идёт из окна 1.
- Нужен ПК, который тянет игру дважды одновременно; закрытие одного окна закрывает оба.
- Параметры: coop-splitscreen.ps1 -TopBottom (окна друг над другом), -Pads2 <n> (какой геймпад
  у окна 2, 0-3).

Сообщить об ошибке
Пишите в https://github.com/dolbaras/jericho-coop/issues : что делали, на каком уровне,
хост вы или клиент. Приложите лог: Документы\Codemasters\Clive Barker's Jericho\Coop\coop.log
(лог прошлого запуска — coop.prev.log; второе окно сплитскрина — coop-window2.log).

License: MIT (LICENSE.txt). ENet 1.3.18 (MIT, ENET-LICENSE.txt). No game files are included.

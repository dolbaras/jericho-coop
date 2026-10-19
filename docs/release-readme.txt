Clive Barker's Jericho — Co-op mod (тестовая версия / test build)
==================================================================

РУССКИЙ
-------

Совместное прохождение кампании Clive Barker's Jericho (2007, PC) на 2-4 игроков.
Каждый игрок управляет своим бойцом отряда, остальными управляет ИИ. Хост ведёт мир и
сюжет, остальные подключаются к нему.

Это первая тестовая версия: вся кампания проходится в автоматических тестах, но живого
прохождения людьми ещё не было. Ошибки возможны — пожалуйста, сообщайте о них (см. ниже).

Что нужно
- Своя копия игры. Проверено на розничной DVD-версии (Jericho.exe SHA-256
  7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62), Windows 10 и 11.
  Другие версии не проверялись.
- Мод должен стоять у всех игроков, одной и той же версии.

Установка
1. Распакуйте архив в папку игры (там, где лежит папка bin). Должно получиться:
     <папка игры>\bin\dinput8.dll
     <папка игры>\coop\*.lua
   Если в bin уже был свой dinput8.dll, сохраните его копию.
2. Запустите игру как обычно. В главном меню появится пункт «Совместная игра».

Удаление: удалите <папка игры>\bin\dinput8.dll и папку <папка игры>\coop.
Файлы игры и одиночные сохранения мод не меняет.

Как играть
- Хост: «Совместная игра» → «Создать игру» → выбрать главу (или «Продолжить») →
  «Создать сессию». В лобби каждый выбирает персонажа и ник и нажимает «Готов», хост — «Начать».
- Остальные: «Совместная игра» → «Присоединиться» → выбрать игру из списка «Игры в
  локальной сети» или ввести IP хоста → «Подключиться».
- По сети используются порты UDP 28100 (игра) и UDP 28199 (поиск игр в локальной сети).
  Разрешите игре доступ в брандмауэре Windows. Через интернет: хосту нужно пробросить
  UDP 28100 на роутере, либо играйте через виртуальную локальную сеть (Radmin VPN,
  ZeroTier и т.п.) и подключайтесь по её IP.

Как устроено
- Акт 1: хост играет за Росса (как в оригинале), после его гибели — за Дельгадо.
- Поднимать упавших может только Роулингс (игрок или ИИ), как в оригинале.
- Замедление времени Коула и Блэка действует на мир для всех, игроки двигаются с обычной скоростью.
- Катсцены видят все одновременно, оригинальной камерой; если сцена показана глазами
  другого персонажа, вверху подпись «Вид глазами: …». Пропуск сцены — только когда Esc
  нажали все игроки.
- QTE видит и проходит только тот, кто играет за персонажа сцены.
- Действия, которые может сделать только определённый персонаж: игрокам предлагают взять
  этого персонажа, если никто не взял за 30 с — делает ИИ (настраивается в лобби).
- Если игроков больше, чем живых бойцов (или персонаж ушёл по сюжету), игрок становится
  «духом»: летает рядом с отрядом, отмечает врагов и может занять свободное тело.
- Совместное сохранение отдельно от одиночного: Документы\Codemasters\Clive Barker's
  Jericho\Coop. Одиночный профиль во время сессии не трогается.

Сообщить об ошибке
Пишите в https://github.com/dolbaras/jericho-coop/issues : что делали, на каком уровне,
хост вы или клиент. Приложите лог: Документы\Codemasters\Clive Barker's Jericho\Coop\coop.log
(лог прошлого запуска — coop.prev.log).


ENGLISH
-------

Co-op for the Clive Barker's Jericho (2007, PC) campaign, 2-4 players. Each player controls
one squad member, the AI drives the rest. The host runs the world and the story.

This is the first test build: the whole campaign runs through in automated tests, but no
human playthrough has been done yet. Please report problems (see below).

Requirements: your own copy of the game (tested: retail DVD release, Jericho.exe SHA-256
7fb5b759823283a83b685adc4848289a149f520ddbab6dbc7f9e6131b15d2a62, Windows 10/11; other
versions untested). Every player needs the same mod version.

Install: extract the archive into the game folder so that <game>\bin\dinput8.dll and
<game>\coop\*.lua exist (back up an existing bin\dinput8.dll). Start the game; the main menu
has a "Co-op" entry. Uninstall: delete bin\dinput8.dll and the coop folder. The mod does not
change game files or single-player saves.

Play: host: Co-op → Host game → chapter (or Continue) → Create session; everyone picks a
character and nickname in the lobby and presses Ready, the host presses Start. Others: Co-op →
Join game → pick a game from the local network list or type the host's IP → Connect.
Network: UDP 28100 (game) and UDP 28199 (LAN discovery); allow the game in Windows Firewall.
Over the internet the host forwards UDP 28100, or use a virtual LAN (Radmin VPN, ZeroTier...).

Reports: https://github.com/dolbaras/jericho-coop/issues — what happened, which level, host
or client, and attach Documents\Codemasters\Clive Barker's Jericho\Coop\coop.log
(coop.prev.log is the previous run).

License: MIT (LICENSE.txt). ENet 1.3.18 (MIT, ENET-LICENSE.txt). No game files are included.

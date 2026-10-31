# Jericho Co-op+ installer / uninstaller for players (shipped in the release zip as
# "Install Co-op.bat" + coop-installer.ps1, payload in the "files" folder next to it).
#   install: finds the game folder (this folder, install records in the registry, Steam
#            libraries, or the player picks it), keeps the files it replaces in <game>\coop-backup,
#            copies the mod and writes <game>\coop\install.txt (what it installed, what it backed up).
#   update:  the same over an older version; originals already backed up are kept.
#   remove:  deletes what install.txt lists and puts the backed-up files back. The co-op saves
#            (Documents\Codemasters\Clive Barker's Jericho\Coop) are not touched.
# A window shows the steps, a progress bar (also on the taskbar button) and what is being done;
# the longest step, building the cutscene animations from the game's files, reports file by file.
# -Quiet: no window, the same steps written to the console (test scripts, the SMOD bundle).
# -Game without -Uninstall starts installing into that folder right away.
# The window's install also makes the "Jericho Co-op+" shortcut (desktop and Start menu, the game's
# icon with a co-op badge): it runs coop\coop-launcher.ps1, which installs a newer release from
# GitHub before starting the game. The launcher runs a new release's installer as
#   coop-installer.ps1 -Game <folder> -AutoClose -NoShortcut
# so every later installer has to take these: -AutoClose closes the window after a successful
# install, -NoShortcut keeps the shortcuts as they are (only those already made are refreshed).
# -ShortcutDir puts new shortcuts in that folder instead (tests).
# Usage: coop-installer.ps1 [-Game <folder>] [-Uninstall] [-Quiet] [-Lang en|ru|de|fr|es|it]
#                           [-AutoClose] [-NoShortcut] [-ShortcutDir <folder>]
param([string] $Game = "", [switch] $Uninstall, [switch] $Quiet, [switch] $IgnoreRunning, [string] $Lang = "",
      [switch] $AutoClose, [switch] $NoShortcut, [string] $ShortcutDir = "")
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$payload = Join-Path $here "files"
# The window's texts by key, per language ({0}, {1}... filled in from L's arguments). Not $S:
# variable names ignore case and a function sees its callers' ($s of an event handler).
$script:TEXTS = @{
    en = @{
        "the_co_op_mod" = "The co-op mod is not installed in`n{0}"
        "removed_file_s" = "Removed {0} file(s)."
        "put_back" = "Put back: "
        "building_the_cutscene_animations" = "Building the cutscene animations from {0} (a few minutes)..."
        "about_min_left" = ", about {0} min left"
        "animation_of" = "Animation {0} of {1}"
        "the_files_folder_is" = "The 'files' folder is missing next to the installer."
        "close_the_game_first" = "Close the game first."
        "incomplete" = "The downloaded mod is incomplete: nothing was changed. Start the game again to retry."
        "another_install" = "Another installation of the mod is running: wait until it ends."
        "no_admin" = "Windows did not allow writing to the game folder without administrator rights."
        "installed_now_co_op" = "Installed now: co-op "
        "smod_found" = "SMOD found."
        "smod_addons_found" = "SMOD Add-ons found: they stay as they are."
        "original_kept" = "Original kept: "
        "copied_file_s" = "Copied {0} file(s)."
        "already_large_address_aware" = "Already large address aware: "
        "large_address_aware" = "Large address aware: "
        "the_exe_is_not" = "The exe is not the retail one the mod is tested with: left as it is."
        "reading_the_game_s" = "Reading the game's archives..."
        "the_animations_built_by" = "The animations built by an earlier install are current: kept."
        "pack_packed_belongs_to" = "Pack1.packed belongs to another mod: left alone."
        "start_the_game_the" = "Start the game: the main menu has a 'Co-op' entry.`nTo remove: 'Uninstall Co-op.bat' in the game folder (or run this installer again)."
        "smod_found_supported" = "`n`nSMOD found: supported."
        "the_build_of_the" = "The build of the cutscene animations failed."
        "the_cutscene_animations_and" = "The cutscene animations and Ross's model could not be built from your game files: in the 'own eyes' cutscene view the scene's character is not shown, and Ross's rifle looks checkered. Run the installer again; if it fails again, please report it with coop\install-log.txt (see README-COOP.txt)."
        "not_a_jericho_folder" = "Not a Jericho folder: {0}"
        "the_game_was_not" = "The game was not found: give its folder with -Game."
        "the_co_op_mod2" = "The co-op mod was removed; replaced files were put back."
        "jericho_co_op_is" = "Jericho Co-op+ {0} is installed in {1}"
        "error" = "Error: "
        "version_co_op_for" = "Version {0}  -  co-op for Clive Barker's Jericho, 2-4 players"
        "game_folder" = "Game folder"
        "browse" = "Browse..."
        "remove_co_op" = "Remove co-op"
        "cancel" = "Cancel"
        "install" = "Install"
        "copy_log" = "Copy log"
        "open_game_folder" = "Open game folder"
        "close" = "Close"
        "please_wait_until_it" = "Please wait until it finishes: stopping in the middle could leave the game half changed."
        "the_game_was_not2" = "The game was not found automatically: choose its folder (the one with the bin folder)."
        "there_is_no_bin" = "There is no bin\Jericho.exe in this folder."
        "clive_barker_s_jericho" = "Clive Barker's Jericho found."
        "smod_found_supported2" = "SMOD found: supported."
        "co_op_is_already" = "Co-op {0} is already installed: it will be installed again."
        "reinstall" = "Reinstall"
        "co_op_is_installed" = "Co-op {0} is installed: it will be updated to {1}."
        "update" = "Update"
        "the_installer_copies_the" = "The installer copies the mod into the game folder and keeps every game file it replaces (coop-backup); 'Uninstall Co-op.bat' there puts everything back. It also builds the cutscene animations and Ross's model from your own game files: about 2-5 minutes."
        "every_player_needs_the" = "Every player needs the same version of the mod."
        "installing_co_op" = "Installing co-op {0}..."
        "checking_the_game_folder" = "Checking the game folder"
        "copying_the_mod_the" = "Copying the mod (the game's replaced files are kept)"
        "large_address_aware_flag" = "Large address aware flag in the game's exe (original kept)"
        "building_cutscene_animations_and" = "Building cutscene animations and Ross's model from your game files"
        "writing_the_install_record" = "Writing the install record"
        "game_folder2" = "Game folder: "
        "updated_from_to" = "Updated from {0} to {1}"
        "co_op_is_installed2" = "Co-op {0} is installed"
        "installation_failed" = "Installation failed"
        "the_log_is_in" = "The log is in %TEMP%\jericho-coop-install.log. Nothing of the game is lost: the replaced files are in coop-backup."
        "removing_co_op" = "Removing co-op..."
        "removing_the_mod_s" = "Removing the mod's files"
        "putting_back_the_game" = "Putting back the game's original files"
        "removing_the_backups_and" = "Removing the backups and the mod's folder"
        "co_op_removed" = "Co-op removed"
        "the_co_op_mod3" = "The co-op mod was removed; the replaced files were put back.`n`nCo-op saves stay in Documents\Codemasters\Clive Barker's Jericho\Coop."
        "removal_failed" = "Removal failed"
        "select_the_clive_barker" = "Select the Clive Barker's Jericho folder (the one with the bin folder)"
        "remove_the_co_op" = "Remove the co-op mod from`n{0} ?"
        "remove_jericho_co_op" = "Remove Jericho Co-op+ {0} from this folder?`n`nThe game's original files are put back; co-op saves stay in Documents\Codemasters\Clive Barker's Jericho\Coop."
        "removed" = "Removed: "
        "shortcut" = "Shortcut: "
        "shortcut_desc" = "Clive Barker's Jericho with co-op: installs a newer version of the mod first, if there is one"
        "the_shortcut" = "The 'Jericho Co-op+' shortcut (desktop, Start menu) starts the game and installs a newer version of the mod from GitHub first, if there is one."
    }
    ru = @{
        "the_co_op_mod" = "Кооп-мод не установлен в`n{0}"
        "removed_file_s" = "Удалено файлов: {0}."
        "put_back" = "Возвращён: "
        "building_the_cutscene_animations" = "Сборка анимаций катсцен из {0} (несколько минут)..."
        "about_min_left" = ", осталось около {0} мин"
        "animation_of" = "Анимация {0} из {1}"
        "the_files_folder_is" = "Рядом с установщиком нет папки 'files'."
        "close_the_game_first" = "Сначала закройте игру."
        "incomplete" = "Загруженный мод неполный: ничего не изменено. Запустите игру снова, чтобы повторить."
        "another_install" = "Уже идёт другая установка мода: дождитесь её окончания."
        "no_admin" = "Windows не разрешила запись в папку игры без прав администратора."
        "installed_now_co_op" = "Сейчас установлен кооп "
        "smod_found" = "Найден SMOD."
        "smod_addons_found" = "Найдены SMOD Add-ons: они остаются как есть."
        "original_kept" = "Оригинал сохранён: "
        "copied_file_s" = "Скопировано файлов: {0}."
        "already_large_address_aware" = "Флаг уже стоит: "
        "large_address_aware" = "Флаг large address aware: "
        "the_exe_is_not" = "Это не та розничная версия exe, с которой проверен мод: оставлен как есть."
        "reading_the_game_s" = "Чтение архивов игры..."
        "the_animations_built_by" = "Анимации от прошлой установки актуальны: оставлены."
        "pack_packed_belongs_to" = "Pack1.packed принадлежит другому моду: не тронут."
        "start_the_game_the" = "Запустите игру: в главном меню появится «Совместная игра».`nУдалить: «Uninstall Co-op.bat» в папке игры (или снова этот установщик)."
        "smod_found_supported" = "`n`nНайден SMOD: поддерживается."
        "the_build_of_the" = "Сборка анимаций катсцен не удалась."
        "the_cutscene_animations_and" = "Не удалось собрать из файлов игры анимации катсцен и модель Росса: в режиме катсцен «своими глазами» персонаж сцены не виден, а винтовка Росса в клетку. Запустите установщик ещё раз; если снова не получится, сообщите об ошибке, приложив coop\install-log.txt (см. README-COOP.txt)."
        "not_a_jericho_folder" = "Это не папка Jericho: {0}"
        "the_game_was_not" = "Игра не найдена: укажите папку через -Game."
        "the_co_op_mod2" = "Кооп-мод удалён, заменённые файлы возвращены."
        "jericho_co_op_is" = "Jericho Co-op+ {0} установлен в {1}"
        "error" = "Ошибка: "
        "version_co_op_for" = "Версия {0}  -  кооператив для Clive Barker's Jericho, 2-4 игрока"
        "game_folder" = "Папка игры"
        "browse" = "Обзор..."
        "remove_co_op" = "Удалить кооп"
        "cancel" = "Отмена"
        "install" = "Установить"
        "copy_log" = "Копировать журнал"
        "open_game_folder" = "Открыть папку игры"
        "close" = "Закрыть"
        "please_wait_until_it" = "Подождите окончания: остановка на полпути может оставить игру изменённой наполовину."
        "the_game_was_not2" = "Игра не найдена автоматически: выберите её папку (ту, где есть папка bin)."
        "there_is_no_bin" = "В этой папке нет bin\Jericho.exe."
        "clive_barker_s_jericho" = "Clive Barker's Jericho найдена."
        "smod_found_supported2" = "Найден SMOD: поддерживается."
        "co_op_is_already" = "Кооп {0} уже установлен: будет установлен заново."
        "reinstall" = "Переустановить"
        "co_op_is_installed" = "Установлен кооп {0}: он будет обновлён до {1}."
        "update" = "Обновить"
        "the_installer_copies_the" = "Установщик скопирует мод в папку игры и сохранит каждый заменяемый файл игры (coop-backup); «Uninstall Co-op.bat» там всё вернёт. Ещё он соберёт анимации катсцен и модель Росса из ваших файлов игры: около 2-5 минут."
        "every_player_needs_the" = "Версия мода должна быть одинаковой у всех игроков."
        "installing_co_op" = "Установка коопа {0}..."
        "checking_the_game_folder" = "Проверка папки игры"
        "copying_the_mod_the" = "Копирование мода (заменяемые файлы игры сохраняются)"
        "large_address_aware_flag" = "Флаг large address aware в exe игры (оригинал сохраняется)"
        "building_cutscene_animations_and" = "Сборка анимаций катсцен и модели Росса из ваших файлов игры"
        "writing_the_install_record" = "Запись сведений об установке"
        "game_folder2" = "Папка игры: "
        "updated_from_to" = "Обновлено с {0} до {1}"
        "co_op_is_installed2" = "Кооп {0} установлен"
        "installation_failed" = "Установка не удалась"
        "the_log_is_in" = "Журнал: %TEMP%\jericho-coop-install.log. Файлы игры не потеряны: заменённые лежат в coop-backup."
        "removing_co_op" = "Удаление коопа..."
        "removing_the_mod_s" = "Удаление файлов мода"
        "putting_back_the_game" = "Возврат оригинальных файлов игры"
        "removing_the_backups_and" = "Удаление копий и папки мода"
        "co_op_removed" = "Кооп удалён"
        "the_co_op_mod3" = "Кооп-мод удалён, заменённые файлы возвращены.`n`nКооп-сохранения остались в Документы\Codemasters\Clive Barker's Jericho\Coop."
        "removal_failed" = "Удаление не удалось"
        "select_the_clive_barker" = "Выберите папку Clive Barker's Jericho (в ней есть папка bin)"
        "remove_the_co_op" = "Удалить кооп-мод из`n{0} ?"
        "remove_jericho_co_op" = "Удалить Jericho Co-op+ {0} из этой папки?`n`nОригинальные файлы игры будут возвращены; кооп-сохранения останутся в Документы\Codemasters\Clive Barker's Jericho\Coop."
        "removed" = "Удалён: "
        "shortcut" = "Ярлык: "
        "shortcut_desc" = "Clive Barker's Jericho с кооперативом: сначала ставит новую версию мода, если она вышла"
        "the_shortcut" = "Ярлык «Jericho Co-op+» (рабочий стол, меню «Пуск») запускает игру, а перед этим ставит с GitHub новую версию мода, если она вышла."
    }
    de = @{
        "the_co_op_mod" = "Der Koop-Mod ist nicht installiert in`n{0}"
        "removed_file_s" = "{0} Datei(en) entfernt."
        "put_back" = "Wiederhergestellt: "
        "building_the_cutscene_animations" = "Die Animationen der Zwischensequenzen werden aus {0} erstellt (einige Minuten)..."
        "about_min_left" = ", noch etwa {0} Min."
        "animation_of" = "Animation {0} von {1}"
        "the_files_folder_is" = "Der Ordner 'files' fehlt neben dem Installationsprogramm."
        "close_the_game_first" = "Schließen Sie zuerst das Spiel."
        "incomplete" = "Die heruntergeladene Mod ist unvollständig: nichts wurde geändert. Starten Sie das Spiel erneut, um es noch einmal zu versuchen."
        "another_install" = "Eine andere Installation der Mod läuft: warten Sie, bis sie fertig ist."
        "no_admin" = "Windows hat das Schreiben in den Spielordner ohne Administratorrechte nicht erlaubt."
        "installed_now_co_op" = "Derzeit installiert: Koop "
        "smod_found" = "SMOD gefunden."
        "smod_addons_found" = "SMOD Add-ons gefunden: sie bleiben unverändert."
        "original_kept" = "Original gesichert: "
        "copied_file_s" = "{0} Datei(en) kopiert."
        "already_large_address_aware" = "Bereits Large Address Aware: "
        "large_address_aware" = "Large Address Aware: "
        "the_exe_is_not" = "Die exe ist nicht die Verkaufsversion, mit der der Mod getestet ist: unverändert gelassen."
        "reading_the_game_s" = "Die Archive des Spiels werden gelesen..."
        "the_animations_built_by" = "Die von einer früheren Installation erstellten Animationen sind aktuell: beibehalten."
        "pack_packed_belongs_to" = "Pack1.packed gehört zu einem anderen Mod: unverändert gelassen."
        "start_the_game_the" = "Starten Sie das Spiel: im Hauptmenü gibt es den Eintrag 'Koop'.`nZum Entfernen: 'Uninstall Co-op.bat' im Spielordner (oder dieses Installationsprogramm erneut ausführen)."
        "smod_found_supported" = "`n`nSMOD gefunden: wird unterstützt."
        "the_build_of_the" = "Das Erstellen der Zwischensequenz-Animationen ist fehlgeschlagen."
        "the_cutscene_animations_and" = "Die Zwischensequenz-Animationen und Ross' Modell konnten nicht aus Ihren Spieldateien erstellt werden: in der Zwischensequenz-Ansicht 'eigene Sicht' fehlt die Figur der Szene, und Ross' Gewehr sieht kariert aus. Führen Sie das Installationsprogramm erneut aus; schlägt es wieder fehl, melden Sie es bitte mit coop\install-log.txt (siehe README-COOP.txt)."
        "not_a_jericho_folder" = "Kein Jericho-Ordner: {0}"
        "the_game_was_not" = "Das Spiel wurde nicht gefunden: geben Sie seinen Ordner mit -Game an."
        "the_co_op_mod2" = "Der Koop-Mod wurde entfernt; ersetzte Dateien wurden wiederhergestellt."
        "jericho_co_op_is" = "Jericho Co-op+ {0} ist installiert in {1}"
        "error" = "Fehler: "
        "version_co_op_for" = "Version {0}  -  Koop für Clive Barker's Jericho, 2-4 Spieler"
        "game_folder" = "Spielordner"
        "browse" = "Durchsuchen..."
        "remove_co_op" = "Koop entfernen"
        "cancel" = "Abbrechen"
        "install" = "Installieren"
        "copy_log" = "Protokoll kopieren"
        "open_game_folder" = "Spielordner öffnen"
        "close" = "Schließen"
        "please_wait_until_it" = "Bitte warten Sie, bis es fertig ist: ein Abbruch mittendrin könnte das Spiel halb verändert zurücklassen."
        "the_game_was_not2" = "Das Spiel wurde nicht automatisch gefunden: wählen Sie seinen Ordner (den mit dem Ordner bin)."
        "there_is_no_bin" = "In diesem Ordner gibt es keine bin\Jericho.exe."
        "clive_barker_s_jericho" = "Clive Barker's Jericho gefunden."
        "smod_found_supported2" = "SMOD gefunden: wird unterstützt."
        "co_op_is_already" = "Koop {0} ist bereits installiert: es wird neu installiert."
        "reinstall" = "Neu installieren"
        "co_op_is_installed" = "Koop {0} ist installiert: es wird auf {1} aktualisiert."
        "update" = "Aktualisieren"
        "the_installer_copies_the" = "Das Installationsprogramm kopiert den Mod in den Spielordner und sichert jede Spieldatei, die es ersetzt (coop-backup); 'Uninstall Co-op.bat' dort stellt alles wieder her. Außerdem erstellt es die Zwischensequenz-Animationen und Ross' Modell aus Ihren eigenen Spieldateien: etwa 2-5 Minuten."
        "every_player_needs_the" = "Alle Spieler brauchen dieselbe Version des Mods."
        "installing_co_op" = "Koop {0} wird installiert..."
        "checking_the_game_folder" = "Spielordner wird geprüft"
        "copying_the_mod_the" = "Mod wird kopiert (ersetzte Spieldateien werden gesichert)"
        "large_address_aware_flag" = "Large-Address-Aware-Flag in der exe des Spiels (Original gesichert)"
        "building_cutscene_animations_and" = "Zwischensequenz-Animationen und Ross' Modell werden aus Ihren Spieldateien erstellt"
        "writing_the_install_record" = "Installationsdaten werden geschrieben"
        "game_folder2" = "Spielordner: "
        "updated_from_to" = "Aktualisiert von {0} auf {1}"
        "co_op_is_installed2" = "Koop {0} ist installiert"
        "installation_failed" = "Installation fehlgeschlagen"
        "the_log_is_in" = "Das Protokoll liegt in %TEMP%\jericho-coop-install.log. Vom Spiel geht nichts verloren: die ersetzten Dateien liegen in coop-backup."
        "removing_co_op" = "Koop wird entfernt..."
        "removing_the_mod_s" = "Dateien des Mods werden entfernt"
        "putting_back_the_game" = "Originaldateien des Spiels werden wiederhergestellt"
        "removing_the_backups_and" = "Sicherungen und Ordner des Mods werden entfernt"
        "co_op_removed" = "Koop entfernt"
        "the_co_op_mod3" = "Der Koop-Mod wurde entfernt; die ersetzten Dateien wurden wiederhergestellt.`n`nKoop-Spielstände bleiben in Dokumente\Codemasters\Clive Barker's Jericho\Coop."
        "removal_failed" = "Entfernen fehlgeschlagen"
        "select_the_clive_barker" = "Wählen Sie den Ordner von Clive Barker's Jericho (den mit dem Ordner bin)"
        "remove_the_co_op" = "Den Koop-Mod entfernen aus`n{0} ?"
        "remove_jericho_co_op" = "Jericho Co-op+ {0} aus diesem Ordner entfernen?`n`nDie Originaldateien des Spiels werden wiederhergestellt; Koop-Spielstände bleiben in Dokumente\Codemasters\Clive Barker's Jericho\Coop."
        "removed" = "Entfernt: "
        "shortcut" = "Verknüpfung: "
        "shortcut_desc" = "Clive Barker's Jericho mit Koop: installiert zuerst eine neuere Version des Mods, falls es eine gibt"
        "the_shortcut" = "Die Verknüpfung 'Jericho Co-op+' (Desktop, Startmenü) startet das Spiel und installiert vorher eine neuere Version des Mods von GitHub, falls es eine gibt."
    }
    fr = @{
        "the_co_op_mod" = "Le mod coop n'est pas installé dans`n{0}"
        "removed_file_s" = "{0} fichier(s) supprimé(s)."
        "put_back" = "Restauré: "
        "building_the_cutscene_animations" = "Construction des animations des cinématiques à partir de {0} (quelques minutes)..."
        "about_min_left" = ", environ {0} min restantes"
        "animation_of" = "Animation {0} sur {1}"
        "the_files_folder_is" = "Le dossier 'files' est absent à côté de l'installeur."
        "close_the_game_first" = "Fermez d'abord le jeu."
        "incomplete" = "Le mod téléchargé est incomplet : rien n'a été modifié. Relancez le jeu pour réessayer."
        "another_install" = "Une autre installation du mod est en cours : attendez qu'elle se termine."
        "no_admin" = "Windows n'a pas autorisé l'écriture dans le dossier du jeu sans droits d'administrateur."
        "installed_now_co_op" = "Installé actuellement: coop "
        "smod_found" = "SMOD détecté."
        "smod_addons_found" = "SMOD Add-ons détectés: ils restent tels quels."
        "original_kept" = "Original conservé: "
        "copied_file_s" = "{0} fichier(s) copié(s)."
        "already_large_address_aware" = "Déjà large address aware: "
        "large_address_aware" = "Large address aware: "
        "the_exe_is_not" = "L'exe n'est pas la version commerciale avec laquelle le mod est testé: laissé tel quel."
        "reading_the_game_s" = "Lecture des archives du jeu..."
        "the_animations_built_by" = "Les animations d'une installation précédente sont à jour: conservées."
        "pack_packed_belongs_to" = "Pack1.packed appartient à un autre mod: non modifié."
        "start_the_game_the" = "Lancez le jeu: le menu principal a une entrée 'Coop'.`nPour désinstaller: 'Uninstall Co-op.bat' dans le dossier du jeu (ou relancez cet installeur)."
        "smod_found_supported" = "`n`nSMOD détecté: pris en charge."
        "the_build_of_the" = "La construction des animations des cinématiques a échoué."
        "the_cutscene_animations_and" = "Les animations des cinématiques et le modèle de Ross n'ont pas pu être construits à partir de vos fichiers du jeu: en vue subjective, le personnage de la scène n'apparaît pas et le fusil de Ross a un aspect en damier. Relancez l'installeur; en cas de nouvel échec, signalez-le avec coop\install-log.txt (voir README-COOP.txt)."
        "not_a_jericho_folder" = "Ce n'est pas un dossier Jericho: {0}"
        "the_game_was_not" = "Jeu introuvable: indiquez son dossier avec -Game."
        "the_co_op_mod2" = "Le mod coop a été supprimé; les fichiers remplacés ont été restaurés."
        "jericho_co_op_is" = "Jericho Co-op+ {0} est installé dans {1}"
        "error" = "Erreur: "
        "version_co_op_for" = "Version {0}  -  coop pour Clive Barker's Jericho, 2-4 joueurs"
        "game_folder" = "Dossier du jeu"
        "browse" = "Parcourir..."
        "remove_co_op" = "Désinstaller"
        "cancel" = "Annuler"
        "install" = "Installer"
        "copy_log" = "Copier le journal"
        "open_game_folder" = "Ouvrir dossier du jeu"
        "close" = "Fermer"
        "please_wait_until_it" = "Patientez jusqu'à la fin: un arrêt en cours de route pourrait laisser le jeu à moitié modifié."
        "the_game_was_not2" = "Jeu introuvable automatiquement: choisissez son dossier (celui qui contient le dossier bin)."
        "there_is_no_bin" = "Ce dossier ne contient pas bin\Jericho.exe."
        "clive_barker_s_jericho" = "Clive Barker's Jericho détecté."
        "smod_found_supported2" = "SMOD détecté: pris en charge."
        "co_op_is_already" = "Le mod coop {0} est déjà installé: il sera réinstallé."
        "reinstall" = "Réinstaller"
        "co_op_is_installed" = "Le mod coop {0} est installé: il sera mis à jour vers {1}."
        "update" = "Mettre à jour"
        "the_installer_copies_the" = "L'installeur copie le mod dans le dossier du jeu et conserve chaque fichier du jeu qu'il remplace (coop-backup); 'Uninstall Co-op.bat' y restaure tout. Il construit aussi les animations des cinématiques et le modèle de Ross à partir de vos propres fichiers du jeu: environ 2 à 5 minutes."
        "every_player_needs_the" = "Tous les joueurs doivent avoir la même version du mod."
        "installing_co_op" = "Installation du mod coop {0}..."
        "checking_the_game_folder" = "Vérification du dossier du jeu"
        "copying_the_mod_the" = "Copie du mod (les fichiers remplacés du jeu sont conservés)"
        "large_address_aware_flag" = "Indicateur large address aware dans l'exe du jeu (original conservé)"
        "building_cutscene_animations_and" = "Construction des animations des cinématiques et du modèle de Ross à partir de vos fichiers du jeu"
        "writing_the_install_record" = "Enregistrement des informations d'installation"
        "game_folder2" = "Dossier du jeu: "
        "updated_from_to" = "Mis à jour de {0} vers {1}"
        "co_op_is_installed2" = "Mod coop {0} installé"
        "installation_failed" = "Échec de l'installation"
        "the_log_is_in" = "Le journal est dans %TEMP%\jericho-coop-install.log. Rien du jeu n'est perdu: les fichiers remplacés sont dans coop-backup."
        "removing_co_op" = "Désinstallation du mod coop..."
        "removing_the_mod_s" = "Suppression des fichiers du mod"
        "putting_back_the_game" = "Restauration des fichiers d'origine du jeu"
        "removing_the_backups_and" = "Suppression des copies de sécurité et du dossier du mod"
        "co_op_removed" = "Mod coop désinstallé"
        "the_co_op_mod3" = "Le mod coop a été supprimé; les fichiers remplacés ont été restaurés.`n`nLes sauvegardes coop restent dans Documents\Codemasters\Clive Barker's Jericho\Coop."
        "removal_failed" = "Échec de la désinstallation"
        "select_the_clive_barker" = "Sélectionnez le dossier de Clive Barker's Jericho (celui qui contient le dossier bin)"
        "remove_the_co_op" = "Retirer le mod coop de`n{0} ?"
        "remove_jericho_co_op" = "Retirer Jericho Co-op+ {0} de ce dossier?`n`nLes fichiers d'origine du jeu sont restaurés; les sauvegardes coop restent dans Documents\Codemasters\Clive Barker's Jericho\Coop."
        "removed" = "Supprimé: "
        "shortcut" = "Raccourci: "
        "shortcut_desc" = "Clive Barker's Jericho en coop: installe d'abord une version plus récente du mod, s'il y en a une"
        "the_shortcut" = "Le raccourci 'Jericho Co-op+' (bureau, menu Démarrer) lance le jeu et installe d'abord une version plus récente du mod depuis GitHub, s'il y en a une."
    }
    es = @{
        "the_co_op_mod" = "El mod cooperativo no está instalado en`n{0}"
        "removed_file_s" = "Archivos eliminados: {0}."
        "put_back" = "Restaurado: "
        "building_the_cutscene_animations" = "Generando las animaciones de las cinemáticas a partir de {0} (unos minutos)..."
        "about_min_left" = ", quedan unos {0} min"
        "animation_of" = "Animación {0} de {1}"
        "the_files_folder_is" = "Falta la carpeta 'files' junto al instalador."
        "close_the_game_first" = "Cierra primero el juego."
        "incomplete" = "El mod descargado está incompleto: no se ha cambiado nada. Inicia el juego de nuevo para reintentarlo."
        "another_install" = "Ya hay otra instalación del mod en curso: espera a que termine."
        "no_admin" = "Windows no permitió escribir en la carpeta del juego sin permisos de administrador."
        "installed_now_co_op" = "Instalado ahora: cooperativo "
        "smod_found" = "SMOD encontrado."
        "smod_addons_found" = "SMOD Add-ons encontrados: se quedan como están."
        "original_kept" = "Original conservado: "
        "copied_file_s" = "Archivos copiados: {0}."
        "already_large_address_aware" = "Ya es large address aware: "
        "large_address_aware" = "Large address aware: "
        "the_exe_is_not" = "El exe no es la versión comercial con la que se probó el mod: se deja como está."
        "reading_the_game_s" = "Leyendo los archivos del juego..."
        "the_animations_built_by" = "Las animaciones generadas por una instalación anterior están al día: se conservan."
        "pack_packed_belongs_to" = "Pack1.packed pertenece a otro mod: no se toca."
        "start_the_game_the" = "Inicia el juego: el menú principal tiene la opción 'Cooperativo'.`nPara desinstalarlo: 'Uninstall Co-op.bat' en la carpeta del juego (o vuelve a ejecutar este instalador)."
        "smod_found_supported" = "`n`nSMOD encontrado: compatible."
        "the_build_of_the" = "Ha fallado la generación de las animaciones de las cinemáticas."
        "the_cutscene_animations_and" = "No se pudieron generar las animaciones de las cinemáticas ni el modelo de Ross a partir de los archivos de tu juego: en la vista 'tus ojos' de las cinemáticas no se ve el personaje de la escena y el rifle de Ross se ve a cuadros. Vuelve a ejecutar el instalador; si falla de nuevo, infórmanos adjuntando coop\install-log.txt (consulta README-COOP.txt)."
        "not_a_jericho_folder" = "No es una carpeta de Jericho: {0}"
        "the_game_was_not" = "No se encontró el juego: indica su carpeta con -Game."
        "the_co_op_mod2" = "Se ha quitado el mod cooperativo; se han restaurado los archivos sustituidos."
        "jericho_co_op_is" = "Jericho Co-op+ {0} está instalado en {1}"
        "error" = "Error: "
        "version_co_op_for" = "Versión {0}  -  cooperativo para Clive Barker's Jericho, 2-4 jugadores"
        "game_folder" = "Carpeta del juego"
        "browse" = "Examinar..."
        "remove_co_op" = "Desinstalar"
        "cancel" = "Cancelar"
        "install" = "Instalar"
        "copy_log" = "Copiar registro"
        "open_game_folder" = "Abrir carpeta del juego"
        "close" = "Cerrar"
        "please_wait_until_it" = "Espera a que termine: si se detiene a medias, el juego podría quedar modificado a medias."
        "the_game_was_not2" = "No se encontró el juego automáticamente: elige su carpeta (la que contiene la carpeta bin)."
        "there_is_no_bin" = "No hay bin\Jericho.exe en esta carpeta."
        "clive_barker_s_jericho" = "Clive Barker's Jericho encontrado."
        "smod_found_supported2" = "SMOD encontrado: compatible."
        "co_op_is_already" = "El cooperativo {0} ya está instalado: se volverá a instalar."
        "reinstall" = "Reinstalar"
        "co_op_is_installed" = "El cooperativo {0} está instalado: se actualizará a {1}."
        "update" = "Actualizar"
        "the_installer_copies_the" = "El instalador copia el mod en la carpeta del juego y guarda cada archivo del juego que sustituye (coop-backup); 'Uninstall Co-op.bat' lo restaura todo. También genera las animaciones de las cinemáticas y el modelo de Ross a partir de tus propios archivos del juego: unos 2-5 minutos."
        "every_player_needs_the" = "Todos los jugadores necesitan la misma versión del mod."
        "installing_co_op" = "Instalando el cooperativo {0}..."
        "checking_the_game_folder" = "Comprobando la carpeta del juego"
        "copying_the_mod_the" = "Copiando el mod (se guardan los archivos sustituidos del juego)"
        "large_address_aware_flag" = "Marca large address aware en el exe del juego (se guarda el original)"
        "building_cutscene_animations_and" = "Generando las animaciones de las cinemáticas y el modelo de Ross a partir de tus archivos del juego"
        "writing_the_install_record" = "Guardando el registro de instalación"
        "game_folder2" = "Carpeta del juego: "
        "updated_from_to" = "Actualizado de {0} a {1}"
        "co_op_is_installed2" = "Cooperativo {0} instalado"
        "installation_failed" = "Error en la instalación"
        "the_log_is_in" = "El registro está en %TEMP%\jericho-coop-install.log. No se ha perdido nada del juego: los archivos sustituidos están en coop-backup."
        "removing_co_op" = "Desinstalando el cooperativo..."
        "removing_the_mod_s" = "Eliminando los archivos del mod"
        "putting_back_the_game" = "Restaurando los archivos originales del juego"
        "removing_the_backups_and" = "Eliminando las copias de seguridad y la carpeta del mod"
        "co_op_removed" = "Cooperativo desinstalado"
        "the_co_op_mod3" = "Se ha quitado el mod cooperativo; se han restaurado los archivos sustituidos.`n`nLas partidas guardadas del cooperativo se conservan en Documentos\Codemasters\Clive Barker's Jericho\Coop."
        "removal_failed" = "Error al desinstalar"
        "select_the_clive_barker" = "Selecciona la carpeta de Clive Barker's Jericho (la que contiene la carpeta bin)"
        "remove_the_co_op" = "¿Quitar el mod cooperativo de`n{0} ?"
        "remove_jericho_co_op" = "¿Quitar Jericho Co-op+ {0} de esta carpeta?`n`nSe restaurarán los archivos originales del juego; las partidas guardadas del cooperativo se conservan en Documentos\Codemasters\Clive Barker's Jericho\Coop."
        "removed" = "Eliminado: "
        "shortcut" = "Acceso directo: "
        "shortcut_desc" = "Clive Barker's Jericho con cooperativo: primero instala una versión más reciente del mod, si la hay"
        "the_shortcut" = "El acceso directo 'Jericho Co-op+' (escritorio, menú Inicio) inicia el juego y antes instala desde GitHub una versión más reciente del mod, si la hay."
    }
    it = @{
        "the_co_op_mod" = "La mod co-op non è installata in`n{0}"
        "removed_file_s" = "Rimossi {0} file."
        "put_back" = "Ripristinato: "
        "building_the_cutscene_animations" = "Creazione delle animazioni dei filmati da {0} (qualche minuto)..."
        "about_min_left" = ", circa {0} min rimanenti"
        "animation_of" = "Animazione {0} di {1}"
        "the_files_folder_is" = "Manca la cartella 'files' accanto al programma di installazione."
        "close_the_game_first" = "Chiudi prima il gioco."
        "incomplete" = "La mod scaricata è incompleta: non è stato modificato nulla. Avvia di nuovo il gioco per riprovare."
        "another_install" = "È in corso un'altra installazione della mod: attendi che finisca."
        "no_admin" = "Windows non ha consentito di scrivere nella cartella del gioco senza diritti di amministratore."
        "installed_now_co_op" = "Installato ora: co-op "
        "smod_found" = "SMOD rilevato."
        "smod_addons_found" = "SMOD Add-ons rilevati: restano come sono."
        "original_kept" = "Originale conservato: "
        "copied_file_s" = "Copiati {0} file."
        "already_large_address_aware" = "Già large address aware: "
        "large_address_aware" = "Large address aware: "
        "the_exe_is_not" = "L'exe non è quello retail con cui la mod è testata: lasciato invariato."
        "reading_the_game_s" = "Lettura degli archivi del gioco..."
        "the_animations_built_by" = "Le animazioni create da un'installazione precedente sono aggiornate: conservate."
        "pack_packed_belongs_to" = "Pack1.packed appartiene a un'altra mod: lasciato intatto."
        "start_the_game_the" = "Avvia il gioco: il menu principale ha la voce 'Co-op'.`nPer rimuoverla: 'Uninstall Co-op.bat' nella cartella del gioco (o esegui di nuovo questo programma di installazione)."
        "smod_found_supported" = "`n`nSMOD rilevato: supportato."
        "the_build_of_the" = "La creazione delle animazioni dei filmati non è riuscita."
        "the_cutscene_animations_and" = "Le animazioni dei filmati e il modello di Ross non sono stati creati dai file del tuo gioco: nella visuale 'soggettiva' dei filmati il personaggio della scena non viene mostrato e il fucile di Ross appare a scacchi. Esegui di nuovo il programma di installazione; se fallisce ancora, segnalalo allegando coop\install-log.txt (vedi README-COOP.txt)."
        "not_a_jericho_folder" = "Non è una cartella di Jericho: {0}"
        "the_game_was_not" = "Gioco non trovato: indica la sua cartella con -Game."
        "the_co_op_mod2" = "La mod co-op è stata rimossa; i file sostituiti sono stati ripristinati."
        "jericho_co_op_is" = "Jericho Co-op+ {0} è installato in {1}"
        "error" = "Errore: "
        "version_co_op_for" = "Versione {0}  -  co-op per Clive Barker's Jericho, 2-4 giocatori"
        "game_folder" = "Cartella del gioco"
        "browse" = "Sfoglia..."
        "remove_co_op" = "Rimuovi co-op"
        "cancel" = "Annulla"
        "install" = "Installa"
        "copy_log" = "Copia log"
        "open_game_folder" = "Apri cartella del gioco"
        "close" = "Chiudi"
        "please_wait_until_it" = "Attendi la fine: interrompere a metà potrebbe lasciare il gioco modificato solo in parte."
        "the_game_was_not2" = "Gioco non trovato automaticamente: scegli la sua cartella (quella con la cartella bin)."
        "there_is_no_bin" = "In questa cartella non c'è bin\Jericho.exe."
        "clive_barker_s_jericho" = "Clive Barker's Jericho trovato."
        "smod_found_supported2" = "SMOD rilevato: supportato."
        "co_op_is_already" = "Co-op {0} è già installato: verrà installato di nuovo."
        "reinstall" = "Reinstalla"
        "co_op_is_installed" = "Co-op {0} è installato: verrà aggiornato alla {1}."
        "update" = "Aggiorna"
        "the_installer_copies_the" = "Il programma di installazione copia la mod nella cartella del gioco e conserva ogni file del gioco che sostituisce (coop-backup); 'Uninstall Co-op.bat' in quella cartella ripristina tutto. Crea inoltre le animazioni dei filmati e il modello di Ross dai file del tuo gioco: circa 2-5 minuti."
        "every_player_needs_the" = "Ogni giocatore deve avere la stessa versione della mod."
        "installing_co_op" = "Installazione di co-op {0}..."
        "checking_the_game_folder" = "Verifica della cartella del gioco"
        "copying_the_mod_the" = "Copia della mod (i file sostituiti del gioco vengono conservati)"
        "large_address_aware_flag" = "Flag large address aware nell'exe del gioco (originale conservato)"
        "building_cutscene_animations_and" = "Creazione delle animazioni dei filmati e del modello di Ross dai file del tuo gioco"
        "writing_the_install_record" = "Scrittura del registro di installazione"
        "game_folder2" = "Cartella del gioco: "
        "updated_from_to" = "Aggiornato da {0} a {1}"
        "co_op_is_installed2" = "Co-op {0} installato"
        "installation_failed" = "Installazione non riuscita"
        "the_log_is_in" = "Il log è in %TEMP%\jericho-coop-install.log. Nulla del gioco è andato perso: i file sostituiti sono in coop-backup."
        "removing_co_op" = "Rimozione del co-op..."
        "removing_the_mod_s" = "Rimozione dei file della mod"
        "putting_back_the_game" = "Ripristino dei file originali del gioco"
        "removing_the_backups_and" = "Rimozione dei backup e della cartella della mod"
        "co_op_removed" = "Co-op rimosso"
        "the_co_op_mod3" = "La mod co-op è stata rimossa; i file sostituiti sono stati ripristinati.`n`nI salvataggi co-op restano in Documenti\Codemasters\Clive Barker's Jericho\Coop."
        "removal_failed" = "Rimozione non riuscita"
        "select_the_clive_barker" = "Seleziona la cartella di Clive Barker's Jericho (quella con la cartella bin)"
        "remove_the_co_op" = "Rimuovere la mod co-op da`n{0} ?"
        "remove_jericho_co_op" = "Rimuovere Jericho Co-op+ {0} da questa cartella?`n`nI file originali del gioco vengono ripristinati; i salvataggi co-op restano in Documenti\Codemasters\Clive Barker's Jericho\Coop."
        "removed" = "Rimosso: "
        "shortcut" = "Collegamento: "
        "shortcut_desc" = "Clive Barker's Jericho in co-op: prima installa una versione più recente della mod, se c'è"
        "the_shortcut" = "Il collegamento 'Jericho Co-op+' (desktop, menu Start) avvia il gioco e prima installa da GitHub una versione più recente della mod, se c'è."
    }
}
# Windows' own language when there is a translation, else English; the window has a list too.
$script:langs = [ordered]@{ en = "English"; ru = "Русский"; de = "Deutsch"; fr = "Français"; es = "Español"; it = "Italiano" }
$script:lang = if ($Lang) { $Lang.ToLower() } else { (Get-UICulture).TwoLetterISOLanguageName }
if (-not $script:langs.Contains($script:lang)) { $script:lang = (Get-Culture).TwoLetterISOLanguageName }
if (-not $script:langs.Contains($script:lang)) { $script:lang = "en" }
function L($key) {
    $text = $script:TEXTS[$script:lang][$key]
    if (-not $text) { $text = $script:TEXTS.en[$key] }
    if (-not $text) { return $key }
    if ($args.Count) { return ($text -f $args) }
    $text
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# Started hidden ("Install Co-op.bat"): an error outside the install's own steps (before the
# window shows, in building it) would leave the player with nothing on screen. Said and logged.
trap {
    $why = "Jericho Co-op+ installer: " + $_.Exception.Message
    try { Add-Content -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) "jericho-coop-install.log") -Value $why } catch { }
    if ($Quiet) { Write-Host $why } else {
        try { [System.Windows.Forms.MessageBox]::Show($why, "Jericho Co-op+", "OK", "Error") | Out-Null } catch { }
    }
    exit 1
}
# This version: the payload's, or (the uninstaller in the game folder) the installed one's.
$version = ""
foreach ($v in (Join-Path $payload "coop\version.txt"), (Join-Path $here "coop\version.txt")) {
    if (-not $version -and (Test-Path -LiteralPath $v)) { $version = "$(Get-Content -LiteralPath $v -TotalCount 1)".Trim() }
}

# The taskbar button's progress, the console window and sharp text on scaled screens.
try {
    Add-Type -ErrorAction Stop @"
using System;
using System.Runtime.InteropServices;
public static class CoopWin {
    [ComImport, Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ITaskbarList3 {
        void HrInit(); void AddTab(IntPtr h); void DeleteTab(IntPtr h); void ActivateTab(IntPtr h); void SetActiveAlt(IntPtr h);
        void MarkFullscreenWindow(IntPtr h, [MarshalAs(UnmanagedType.Bool)] bool f);
        void SetProgressValue(IntPtr h, ulong done, ulong total);
        void SetProgressState(IntPtr h, int state);
    }
    [ComImport, Guid("56fdf344-fd6d-11d0-958a-006097c9a090"), ClassInterface(ClassInterfaceType.None)]
    class TaskbarList {}
    static ITaskbarList3 bar;
    // state: 0 none, 1 busy, 2 normal, 4 error, 8 paused
    public static void Progress(IntPtr h, int state, int pct) {
        try {
            if (bar == null) { bar = (ITaskbarList3)new TaskbarList(); bar.HrInit(); }
            bar.SetProgressState(h, state);
            if (state == 2 || state == 4 || state == 8) bar.SetProgressValue(h, (ulong)pct, 100);
        } catch { }
    }
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string id);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int v, int size);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint PrivateExtractIcons(string f, int i, int cx, int cy, IntPtr[] h, uint[] id, uint n, uint flags);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    // A dark title bar (Windows 10 2004+ / 11; older ones keep theirs).
    public static void DarkTitle(IntPtr h) { int on = 1; try { DwmSetWindowAttribute(h, 20, ref on, 4); } catch { } }
}
"@
    $script:haveWin = $true
} catch { $script:haveWin = $false }

# ---------------------------------------------------------------------------------------------
# What the steps report: the window's controls, or the console (-Quiet).
$script:ui = $null
$script:logLines = New-Object System.Collections.Generic.List[string]

function Ui-Pump { if ($script:ui) { [System.Windows.Forms.Application]::DoEvents() } }

function Ui-Log($text) {
    $script:logLines.Add("$(Get-Date -Format 'HH:mm:ss') $text")
    if ($script:ui) { $script:ui.log.AppendText("$text`r`n"); Ui-Pump } else { Write-Host $text }
}

function Ui-Progress($pct, $text) {
    $pct = [Math]::Max(0, [Math]::Min(100, [int]$pct))
    if (-not $script:ui) { return }
    $u = $script:ui
    $u.fill.Width = [int]($u.bar.ClientSize.Width * $pct / 100)
    $u.pct.Text = "$pct %"
    if ($null -ne $text) { $u.action.Text = $text }
    if ($script:haveWin) { [CoopWin]::Progress($u.form.Handle, 2, $pct) }
    Ui-Pump
}

# state: run, done, warn, skip, fail
function Ui-Step($key, $state) {
    if (-not $script:ui) { Write-Host "[$state] $key"; return }
    $row = $script:ui.steps[$key]
    if (-not $row) { return }
    $c = $script:ui.colors
    switch ($state) {
        "run"  { $row.icon.Text = [char]0x25CF; $row.icon.ForeColor = $c.accent; $row.text.ForeColor = $c.text; $script:ui.running = $row }
        "done" { $row.icon.Text = [char]0x2714; $row.icon.ForeColor = $c.ok; $row.text.ForeColor = $c.text }
        "warn" { $row.icon.Text = "!"; $row.icon.ForeColor = $c.warn; $row.text.ForeColor = $c.text }
        "skip" { $row.icon.Text = [char]0x2013; $row.icon.ForeColor = $c.dim; $row.text.ForeColor = $c.dim }
        "fail" { $row.icon.Text = [char]0x2716; $row.icon.ForeColor = $c.bad; $row.text.ForeColor = $c.text }
    }
    if ($state -ne "run" -and $script:ui.running -eq $row) { $script:ui.running = $null }
    Ui-Pump
}

# ---------------------------------------------------------------------------------------------
# The game folder

# (Join-Path throws on a drive that does not exist: the D:\Games candidate on a PC without D:)
function Test-Game($dir) {
    if (-not $dir) { return $false }
    try {
        (Test-Path -LiteralPath ([IO.Path]::Combine($dir, "bin\Jericho.exe"))) -or
            (Test-Path -LiteralPath ([IO.Path]::Combine($dir, "bin\anselintegrationtestapp.exe")))
    } catch { $false }
}

# Candidate game folders, most likely first.
function Find-Games {
    $c = New-Object System.Collections.Generic.List[string]
    foreach ($d in @($here, (Split-Path $here -Parent))) { if ($d) { $c.Add($d) } }
    $keys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
              "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
              "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($k in $keys) {
        Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Jericho*" } |
            ForEach-Object { if ($_.InstallLocation) { $c.Add($_.InstallLocation.Trim('"')) } }
    }
    Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.gameName -like "*Jericho*" } | ForEach-Object { if ($_.path) { $c.Add($_.path) } }
    $steam = (Get-ItemProperty "HKCU:\SOFTWARE\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $libs = @($steam)
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value -replace '\\\\', '\' }
        }
        foreach ($l in $libs) { $c.Add((Join-Path $l "steamapps\common\Clive Barker's Jericho")) }
    }
    foreach ($p in @("$env:ProgramFiles (x86)\Codemasters\Clive Barker's Jericho", "$env:ProgramFiles\Codemasters\Clive Barker's Jericho",
                     "C:\Games\Clive Barker's Jericho", "D:\Games\Clive Barker's Jericho")) { $c.Add($p) }
    # (one form of each folder: an install record's "...\Jericho\" is the same as "...\Jericho")
    $c | Where-Object { Test-Game $_ } | ForEach-Object {
        $p = (Resolve-Path -LiteralPath $_).Path
        if ($p.Length -gt 3) { $p.TrimEnd('\') } else { $p }
    } | Select-Object -Unique
}

function Read-Manifest($g) {
    $m = @{ files = @(); backups = @(); built = @(); shortcuts = @(); version = "" }
    $f = Join-Path $g "coop\install.txt"
    if (Test-Path -LiteralPath $f) {
        foreach ($line in Get-Content -LiteralPath $f) {
            if ($line -match '^version=(.*)$') { $m.version = $Matches[1] }
            elseif ($line -match '^file=(.*)$') { $m.files += $Matches[1] }
            elseif ($line -match '^backup=(.*)$') { $m.backups += $Matches[1] }
            elseif ($line -match '^built=(.*)$') { $m.built += $Matches[1] }
            # (0.2.3-0.2.4 wrote all shortcuts on one line, space-separated, and an empty line
            # when there were none)
            elseif ($line -match '^shortcut=(.*)$') { $m.shortcuts += @([regex]::Split($Matches[1], '(?<=\.lnk) ') | Where-Object { $_ }) }
        }
    }
    # (no record, or one without files: 0.1.0, which had no installer, or a record lost)
    if ($m.files.Count -eq 0) {
        $o = Find-OldCoop $g
        if ($o.found) { return $o }
        return $m
    }
    # 0.1.0's files in the root under a later version's record (installed over it): ours too
    foreach ($o in $script:OLD_ROOT) {
        if ($m.files -notcontains $o[0] -and (Has-Text (Join-Path $g $o[0]) @($o[1]))) { $m.files += $o[0] }
    }
    # An "original" kept by an install over 0.1.0's files is that version's DLL: not the game's.
    $m.backups = @($m.backups | Where-Object { -not (Is-CoopDll (Join-Path $g "coop-backup\$_")) })
    $m
}

# The mod's own files from any version, by what is in them: the proxy DLL by its log line, the
# texts by their words (0.1.0 had no installer: its zip was extracted into the game folder).
function Has-Text($p, [string[]] $words) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $false }
    try { $s = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p)) } catch { return $false }
    foreach ($w in $words) { if ($s.Contains($w)) { return $true } }
    $false
}
function Is-CoopDll($p) { Has-Text $p @("coop_net installed") }

# Texts of a release's archive root in the game folder (0.1.0's zip, or a later one extracted
# there): kept while the mod is installed, removed with it.
$script:OLD_ROOT = @(@("README-COOP.txt", "Jericho"), @("LICENSE.txt", "Jericho Co-op contributors"),
                     @("ENET-LICENSE.txt", "Lee Salzman"), @("STEAM-NOTICE.txt", "Spacewar"))
# 0.1.1's two-window split screen (replaced by the split screen in one game in 0.1.2).
$script:OLD_SPLIT = @(@("Co-op split screen.bat", "coop-splitscreen.ps1"), @("coop-splitscreen.ps1", "Split screen"))

# A co-op install without a usable record: what is the mod's, found by the files themselves.
# The version from coop\version.txt (0.1.1 on), else 0.1.0.
function Find-OldCoop($g) {
    $m = @{ files = @(); backups = @(); built = @(); shortcuts = @(); version = ""; found = $false }
    $root = [IO.Path]::GetFullPath($g).TrimEnd('\')
    $coop = Join-Path $root "coop"
    $dll = Is-CoopDll (Join-Path $root "bin\dinput8.dll")
    if (-not $dll -and -not (Test-Path -LiteralPath (Join-Path $coop "coop.lua"))) { return $m }
    $m.found = $true
    if ($dll) { $m.files += "bin\dinput8.dll" }
    if (Test-Path -LiteralPath $coop) {
        foreach ($f in Get-ChildItem -LiteralPath $coop -Recurse -File -Force) { $m.files += $f.FullName.Substring($root.Length + 1) }
    }
    foreach ($o in @($script:OLD_ROOT) + @($script:OLD_SPLIT)) {
        if (Has-Text (Join-Path $root $o[0]) @($o[1])) { $m.files += $o[0] }
    }
    foreach ($f in "coop-installer.ps1", "Uninstall Co-op.bat") { if (Test-Path -LiteralPath (Join-Path $root $f)) { $m.files += $f } }
    $pk = Join-Path $root "Pack1.packed"
    if ((Test-Path -LiteralPath $pk) -and (Select-String -LiteralPath $pk -Pattern "coopbody_" -SimpleMatch -Quiet)) { $m.files += "Pack1.packed" }
    # (originals an installer kept, its record gone)
    $bk = Join-Path $root "coop-backup"
    if (Test-Path -LiteralPath $bk) {
        foreach ($f in Get-ChildItem -LiteralPath $bk -Recurse -File -Force) {
            if (-not (Is-CoopDll $f.FullName)) { $m.backups += $f.FullName.Substring($bk.Length + 1) }
        }
    }
    $v = Get-Content -LiteralPath (Join-Path $coop "version.txt") -TotalCount 1 -ErrorAction SilentlyContinue
    if (-not $v) {
        $lua = Get-Content -LiteralPath (Join-Path $coop "coop.lua") -Raw -ErrorAction SilentlyContinue
        if ($lua -match 'Coop\.VERSION\s*=\s*"([^"]+)"') { $v = $Matches[1] }
    }
    $m.version = if ($v) { "$v".Trim() } else { "0.1.0" }
    $m
}

# The game running from this folder (a copy elsewhere does not lock these files).
function Game-Running($g) {
    $g = [IO.Path]::GetFullPath($g).TrimEnd('\') + "\"
    Get-Process -Name Jericho, anselintegrationtestapp -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Path -or $_.Path.StartsWith($g, [StringComparison]::OrdinalIgnoreCase) }
}

# The game's own exe: with SMOD bin\Jericho.exe is SMOD's starter (an NVIDIA icon) and the
# game is bin\anselintegrationtestapp.exe.
function Game-Exe($g) {
    $smod = Join-Path $g "bin\anselintegrationtestapp.exe"
    if (Test-Path -LiteralPath $smod) { return $smod }
    Join-Path $g "bin\Jericho.exe"
}

# The window's icon: the co-op one once made, else the game's.
function Window-Icon($g) {
    try {
        $ico = Join-Path $g "coop\coop.ico"
        if (Test-Path -LiteralPath $ico) { return New-Object Drawing.Icon($ico, 32, 32) }
        [Drawing.Icon]::ExtractAssociatedIcon((Game-Exe $g))
    } catch { $null }
}

# ---------------------------------------------------------------------------------------------
# Remove

function Do-Uninstall($g) {
    $m = Read-Manifest $g
    if ($m.files.Count -eq 0) { throw (L "the_co_op_mod" $g) }
    Lock-Install
    Ui-Step "rm" "run"
    $all = @($m.files + $m.built)
    $i = 0
    foreach ($rel in $all) {
        $i++
        Ui-Progress (5 + 50 * $i / [Math]::Max(1, $all.Count)) $rel
        Remove-Item -LiteralPath (Join-Path $g $rel) -Force -ErrorAction SilentlyContinue
    }
    Ui-Log (L "removed_file_s" $($all.Count))
    # (only "Jericho Co-op+.lnk" files the install made: the record names them)
    foreach ($lnk in $m.shortcuts) {
        if ($lnk -like "*.lnk" -and (Test-Path -LiteralPath $lnk)) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue; Ui-Log ((L "removed") + $lnk) }
    }
    Ui-Step "rm" "done"
    Ui-Step "restore" "run"
    $i = 0
    foreach ($rel in $m.backups) {
        $i++
        Ui-Progress (55 + 35 * $i / [Math]::Max(1, $m.backups.Count)) $rel
        $b = Join-Path $g "coop-backup\$rel"
        if (Test-Path -LiteralPath $b) { Copy-Item -LiteralPath $b (Join-Path $g $rel) -Force; Ui-Log ((L "put_back") + $rel) }
    }
    Ui-Step "restore" "done"
    Ui-Step "clean" "run"
    Ui-Progress 95 "coop, coop-backup"
    Remove-Item -LiteralPath (Join-Path $g "coop") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $g "coop-backup") -Recurse -Force -ErrorAction SilentlyContinue
    Ui-Step "clean" "done"
    Ui-Progress 100 ""
    @{ removed = $m.version }
}

# ---------------------------------------------------------------------------------------------
# Install

# The experimental "own eyes" cutscene view shows the scene's character with its first-person
# motion moved onto the full model. That motion is made here from the player's own game files
# (coop\anims\cm3_retarget.py, Python 3, a few minutes) into <game>\Pack1.packed, which the
# game mounts by itself. Without Python the view still works, without that body.
# Python comes with the mod (coop\python: python.org's embeddable build); one installed on the
# PC is the fallback.
function Find-Python {
    $own = Join-Path "$script:gameDir" "coop\python\python.exe"
    if ($script:gameDir -and (Test-Path -LiteralPath $own)) { return @{ exe = $own; args = @() } }
    foreach ($c in @(@("py", "-3"), @("python"), @("python3"))) {
        $cmd = Get-Command $c[0] -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $a = @($c | Select-Object -Skip 1)
        $v = & $cmd.Source @a -c "import sys; print(sys.version_info[0])" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq "3") { return @{ exe = $cmd.Source; args = $a } }
    }
    $null
}

# Zeros after the last record of an archive up to where its index sizes reach: the game reads
# that far, and a Pack1 built before 0.2 ended short ("File access error, retry?" in a scene).
function Fix-PackEnd($pack) {
    $need = 0
    $f = [System.IO.File]::OpenRead($pack)
    try {
        $r = New-Object System.IO.BinaryReader($f)
        $null = $r.ReadBytes(8)
        $count = $r.ReadUInt32()
        for ($i = 0; $i -lt $count; $i++) {
            $n = $r.ReadUInt32()
            $null = $r.ReadBytes($n)
            $size = $r.ReadUInt32(); $off = $r.ReadUInt32()
            if ($off + $size -gt $need) { $need = $off + $size }
        }
        $len = $f.Length
    } finally { $f.Close() }
    if ($need -gt $len) {
        $a = [System.IO.File]::Open($pack, [System.IO.FileMode]::Append)
        try { $a.Write((New-Object byte[] ($need - $len)), 0, [int]($need - $len)) } finally { $a.Close() }
    }
}

# A command line argument as the C runtime parses it back.
function Quote-Arg($a) {
    if ($a -and $a -notmatch '[\s"]') { return $a }
    '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

# Runs a program, its output lines to $onLine as they come, the window kept alive meanwhile.
function Run-Live($exe, [string[]] $argList, [scriptblock] $onLine) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($argList | ForEach-Object { Quote-Arg $_ }) -join " "
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEndAsync()
    $next = $p.StandardOutput.ReadLineAsync()
    while ($true) {
        if ($next.Wait(40)) {
            $line = $next.Result
            if ($null -eq $line) { break }
            & $onLine $line
            $next = $p.StandardOutput.ReadLineAsync()
        } else { Ui-Pump }
    }
    while (-not $p.WaitForExit(40)) { Ui-Pump }
    foreach ($line in ($err.Result -split "`r?`n")) { if ($line) { Ui-Log $line } }
    $p.ExitCode
}

function Build-Anims($g) {
    $pack = Join-Path $g "Pack1.packed"
    # Somebody else's Pack1 (not ours): left alone.
    if ((Test-Path -LiteralPath $pack) -and -not (Select-String -LiteralPath $pack -Pattern "coopbody_" -SimpleMatch -Quiet)) { return "foreign" }
    # The game's archives: the game folder, or Packed\ after SMOD unpacked them. That layout
    # reads loose files and not Pack1 ("file not found TrueRoss_coop.M3D", 0.2.1): there the
    # built files also go next to the game's own (listed as built= in coop\install.txt).
    $data = $g
    if (-not (Test-Path -LiteralPath (Join-Path $g "Data00.packed")) -and (Test-Path -LiteralPath (Join-Path $g "Packed\Data00.packed"))) { $data = Join-Path $g "Packed" }
    # A copy made without the archives (the SMOD + Co-op test bundle): the original game's.
    $ptr = Join-Path $g "coop-gamedata.txt"
    if (-not (Test-Path -LiteralPath (Join-Path $data "Data00.packed")) -and (Test-Path -LiteralPath $ptr)) {
        $orig = ([string](Get-Content -LiteralPath $ptr -TotalCount 1)).Trim()
        if ($orig) {
            foreach ($d in @($orig, (Join-Path $orig "Packed"))) {
                if (Test-Path -LiteralPath (Join-Path $d "Data00.packed")) { $data = $d; break }
            }
        }
    }
    $loose = $data -ne $g
    # Built by this version of the builder (its mark inside): kept. An older one is rebuilt
    # (0.2: the scene characters walk instead of gliding), or padded if Python is missing.
    $current = (Test-Path -LiteralPath $pack) -and (Select-String -LiteralPath $pack -Pattern "coopbody_pack_v4" -SimpleMatch -Quiet) -and
        (-not $loose -or (Test-Path -LiteralPath (Join-Path $g "models\chars\trueross\trueross_coop.sm3")))
    if ($current) { Fix-PackEnd $pack; return "kept" }
    $script:gameDir = $g
    $py = Find-Python
    if (-not $py) {
        if (Test-Path -LiteralPath $pack) { Fix-PackEnd $pack; return "ok" }
        return "nopython"
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "jericho-coop-anims"
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Ui-Log (L "building_the_cutscene_animations" $data)
    $script:animStart = Get-Date
    $argList = @($py.args) + @("-I", "-B", "-u", "-X", "utf8", (Join-Path $g "coop\anims\cm3_retarget.py"), "--game", $data, "--out", $tmp, "batch", "--pack", "$pack.tmp")
    $code = Run-Live $py.exe $argList {
        param($line)
        if ($line -match '^progress (\d+)/(\d+)$') {
            $i, $n = [int]$Matches[1], [int]$Matches[2]
            if ($n -gt 0) {
                $left = ""
                $spent = ((Get-Date) - $script:animStart).TotalSeconds
                if ($i -gt 3) {
                    $rest = [int]($spent / ($i - 1) * ($n - $i + 1))
                    $left = L "about_min_left" $([int][Math]::Ceiling($rest / 60))
                }
                Ui-Progress (25 + 70 * ($i - 1) / $n) ((L "animation_of" $i $n) + $left)
            }
        } elseif ($line -match '^(SKIP|packed|model|\d+ generated)') {
            Ui-Log $line
        }
    }
    $ok = $code -eq 0 -and (Test-Path -LiteralPath "$pack.tmp")
    if ($ok -and $loose) {
        $outDir = Join-Path $tmp "out"
        Get-ChildItem -LiteralPath $outDir -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($outDir.Length + 1)
            $dst = Join-Path $g $rel
            New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
            Copy-Item -LiteralPath $_.FullName $dst -Force
            $script:builtFiles.Add($rel)
        }
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $ok) {
        Ui-Log "cm3_retarget.py exit code $code"
        Remove-Item -LiteralPath "$pack.tmp" -ErrorAction SilentlyContinue
        return "failed"
    }
    Move-Item -LiteralPath "$pack.tmp" $pack -Force
    "ok"
}

# The shortcut's icon: the game's own (read from the player's exe at each size, nothing of the
# game is shipped) with a co-op badge, two figures on a red disc, in the lower right corner.
function New-CoopIcon($exe, $ico) {
    $frames = @()
    foreach ($size in 16, 24, 32, 48, 64, 128, 256) {
        $h = New-Object IntPtr[] 1; $id = New-Object UInt32[] 1
        $n = [CoopWin]::PrivateExtractIcons($exe, 0, $size, $size, $h, $id, 1, 0)
        if ($n -lt 1 -or $h[0] -eq [IntPtr]::Zero) { throw "no icon in $exe" }
        $src = [Drawing.Icon]::FromHandle($h[0]).ToBitmap()
        [CoopWin]::DestroyIcon($h[0]) | Out-Null
        $bmp = New-Object Drawing.Bitmap($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gr = [Drawing.Graphics]::FromImage($bmp)
        $gr.SmoothingMode = "AntiAlias"; $gr.InterpolationMode = "HighQualityBicubic"
        $gr.DrawImage($src, 0, 0, $size, $size)
        # (bigger on the small sizes, where it has to be seen at all)
        $d = [single]($size * $(if ($size -le 24) { 0.62 } else { 0.46 }))
        $x = [single]($size - $d); $y = [single]($size - $d)
        $rim = [single][Math]::Max(1, $size / 32)
        $gr.FillEllipse((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(24, 24, 28))), $x, $y, $d, $d)
        $gr.FillEllipse((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(196, 40, 48))), $x + $rim, $y + $rim, $d - 2 * $rim, $d - 2 * $rim)
        # head and shoulders twice, the one behind a little higher and paler
        $u = $d / 10
        foreach ($f in @(@(6.1, 3.0, [Drawing.Color]::FromArgb(240, 200, 200)), @(3.9, 3.6, [Drawing.Color]::White))) {
            $br = New-Object Drawing.SolidBrush($f[2])
            $cx = $x + $f[0] * $u; $top = $y + $f[1] * $u
            $gr.FillEllipse($br, [single]($cx - 1.25 * $u), [single]$top, [single](2.5 * $u), [single](2.5 * $u))
            $path = New-Object Drawing.Drawing2D.GraphicsPath
            $path.AddPie([single]($cx - 2.4 * $u), [single]($top + 2.7 * $u), [single](4.8 * $u), [single](4.2 * $u), [single]180, [single]180)
            $gr.FillPath($br, $path)
            $path.Dispose(); $br.Dispose()
        }
        $gr.Dispose(); $src.Dispose()
        $frames += , @($size, $bmp)
    }
    # ICO: 256 as PNG, the others as 32-bit DIBs (what both the shell and .NET's Icon read).
    $blobs = @()
    foreach ($fr in $frames) {
        $size, $bmp = $fr
        $p = New-Object IO.MemoryStream
        if ($size -ge 256) { $bmp.Save($p, [Drawing.Imaging.ImageFormat]::Png) } else {
            $bw = New-Object IO.BinaryWriter($p)
            $mask = [int]([Math]::Ceiling($size / 32.0) * 4)
            $bw.Write([UInt32]40); $bw.Write([Int32]$size); $bw.Write([Int32](2 * $size)); $bw.Write([UInt16]1); $bw.Write([UInt16]32)
            $bw.Write([UInt32]0); $bw.Write([UInt32]($size * $size * 4 + $mask * $size))
            $bw.Write([Int32]0); $bw.Write([Int32]0); $bw.Write([UInt32]0); $bw.Write([UInt32]0)
            $data = $bmp.LockBits((New-Object Drawing.Rectangle(0, 0, $size, $size)), [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $px = New-Object byte[] ($data.Stride * $size)
            [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length)
            $bmp.UnlockBits($data)
            for ($row = $size - 1; $row -ge 0; $row--) { $bw.Write($px, $row * $data.Stride, $size * 4) }
            $bw.Write((New-Object byte[] ($mask * $size)))
            $bw.Flush()
        }
        $blobs += , $p.ToArray()
    }
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    $w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]$frames.Count)
    $off = 6 + 16 * $frames.Count
    for ($i = 0; $i -lt $frames.Count; $i++) {
        $size = $frames[$i][0]
        $w.Write([byte]($size % 256)); $w.Write([byte]($size % 256)); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([UInt16]1); $w.Write([UInt16]32); $w.Write([UInt32]$blobs[$i].Length); $w.Write([UInt32]$off)
        $off += $blobs[$i].Length
    }
    foreach ($b in $blobs) { $w.Write($b) }
    $w.Flush()
    [IO.File]::WriteAllBytes($ico, $ms.ToArray())
    foreach ($fr in $frames) { $fr[1].Dispose() }
}

# "Jericho Co-op+" shortcuts to coop\coop-launcher.ps1: on the desktop and in the Start menu (the
# window's install), those an earlier install made and the player kept (refreshed), or in
# -ShortcutDir. Returns their paths for the install record.
function Make-Shortcuts($g, $old) {
    $ico = Join-Path $g "coop\coop.ico"
    $iconAt = "$(Game-Exe $g),0"
    if ($script:haveWin) {
        try { New-CoopIcon (Game-Exe $g) $ico; $iconAt = "$ico,0" } catch { Ui-Log "coop.ico: $($_.Exception.Message)" }
    }
    $links = New-Object System.Collections.Generic.List[string]
    foreach ($lnk in $old.shortcuts) {
        if (-not (Test-Path -LiteralPath $lnk)) { continue }
        # (0.2.3 named it "Jericho Co-op": the same folder gets the new name)
        if ((Split-Path $lnk -Leaf) -eq "Jericho Co-op.lnk") {
            Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
            $lnk = Join-Path (Split-Path $lnk -Parent) "Jericho Co-op+.lnk"
        }
        if (-not $links.Contains($lnk)) { $links.Add($lnk) }
    }
    $dirs = @()
    if ($ShortcutDir) { $dirs = @($ShortcutDir) }
    elseif (-not $Quiet -and -not $NoShortcut) { $dirs = @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs")) }
    foreach ($d in $dirs) {
        if (-not $d) { continue }
        $lnk = Join-Path $d "Jericho Co-op+.lnk"
        if (-not $links.Contains($lnk)) { $links.Add($lnk) }
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($lnk in $links) {
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $sc.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $g "coop\coop-launcher.ps1") + '"'
        $sc.WorkingDirectory = $g
        $sc.IconLocation = $iconAt
        $sc.Description = L "shortcut_desc"
        $sc.WindowStyle = 7
        $sc.Save()
        Ui-Log ((L "shortcut") + $lnk)
    }
    $links.ToArray()
}

# One install or removal at a time (a double-clicked shortcut, a second installer window).
function Lock-Install {
    if (-not $script:installLock) { $script:installLock = New-Object Threading.Mutex($false, "Local\JerichoCoopInstall") }
    try { $got = $script:installLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { throw (L "another_install") }
}

# Program Files (the retail disc's default folder): writing there needs administrator rights.
function Need-Admin($g) {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ((New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return $false }
    foreach ($d in @($g, (Join-Path $g "bin"))) {
        $probe = Join-Path $d ("coop-write-test-" + $PID + ".tmp")
        try { [IO.File]::WriteAllText($probe, "1"); Remove-Item -LiteralPath $probe -Force }
        catch [UnauthorizedAccessException] { return $true }
        catch { }
    }
    $false
}

# This installer again with administrator rights for the same folder (Windows asks the player);
# its exit code, -1 when the player said no.
function Run-Elevated($g, [switch] $Remove) {
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Quote-Arg $PSCommandPath), "-Game", (Quote-Arg $g))
    if ($Remove) { $a += "-Uninstall" }
    if ($AutoClose) { $a += "-AutoClose" }
    if ($NoShortcut) { $a += "-NoShortcut" }
    if ($ShortcutDir) { $a += @("-ShortcutDir", (Quote-Arg $ShortcutDir)) }
    if ($Lang) { $a += @("-Lang", $Lang) }
    try {
        $p = Start-Process powershell -Verb RunAs -ArgumentList $a -Wait -PassThru
        return $p.ExitCode
    } catch { return -1 }
}

function Do-Install($g) {
    Ui-Step "check" "run"
    Ui-Progress 1 $g
    if (-not (Test-Path -LiteralPath $payload)) { throw (L "the_files_folder_is") }
    # The payload first into a folder of this installer's own: whatever happens to the folder it
    # came in (an old launcher started twice cleans it up) cannot take files away mid-copy.
    $snap = Join-Path ([IO.Path]::GetTempPath()) ("jericho-coop-payload-" + $PID)
    Remove-Item -LiteralPath $snap -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $payload $snap -Recurse -Force
    $payload = $snap
    # (the package's list of its files: all of them here, or the game is not touched)
    $plist = Join-Path $payload "coop\payload.txt"
    if (-not (Test-Path -LiteralPath $plist)) { Ui-Log "missing: coop\payload.txt"; throw (L "incomplete") }
    $packageFiles = @(Get-Content -LiteralPath $plist | Where-Object { $_ })
    foreach ($rel in $packageFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $payload $rel))) { Ui-Log ("missing: " + $rel); throw (L "incomplete") }
    }
    if (-not $IgnoreRunning -and (Game-Running $g)) { throw (L "close_the_game_first") }
    Lock-Install
    $old = Read-Manifest $g
    if ($old.version) { Ui-Log ((L "installed_now_co_op") + $old.version) }
    # (an older co-op DLL kept as the game's original by an install over 0.1.0's files: dropped)
    $bad = Join-Path $g "coop-backup\bin\dinput8.dll"
    if (Is-CoopDll $bad) { Remove-Item -LiteralPath $bad -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath (Join-Path $g "bin\anselintegrationtestapp.exe")) { Ui-Log (L "smod_found") }
    # SMOD Add-ons (PHM2D, on top of SMOD): their loose scripts and autoexec.lua are the player's own and are never touched or
    # copied; the mod finds them at run time (coop_addon.lua). Told here so that the log shows what the install found.
    $addonTeam = Join-Path $g "scripts\chars\team.lc"
    if ((Test-Path -LiteralPath $addonTeam) -and (Select-String -LiteralPath $addonTeam -Pattern "ReviveCooldownTime" -SimpleMatch -Quiet)) { Ui-Log (L "smod_addons_found") }
    Ui-Step "check" "done"

    Ui-Step "copy" "run"
    $backups = New-Object System.Collections.Generic.List[string]
    foreach ($b in $old.backups) { $backups.Add($b) }
    $files = New-Object System.Collections.Generic.List[string]
    $all = @(Get-ChildItem -LiteralPath $payload -Recurse -File)
    # The install record as far as it got: a failure later on can still be removed or retried.
    # coop\version.txt goes last, once everything is in: the launcher reads it, and an update
    # that broke off is tried again at the next start.
    $built, $links = @($old.built), @($old.shortcuts)
    $writeRecord = {
        $lines = @("version=$version") + ($files | ForEach-Object { "file=$_" }) + ($backups | ForEach-Object { "backup=$_" }) +
            ($built | ForEach-Object { "built=$_" }) + ($links | ForEach-Object { "shortcut=$_" })
        New-Item -ItemType Directory -Force (Join-Path $g "coop") | Out-Null
        Set-Content -LiteralPath (Join-Path $g "coop\install.txt") -Value $lines -Encoding UTF8
    }
    $versionFile = $null
    $i = 0
    foreach ($item in $all) {
        $i++
        $rel = $item.FullName.Substring($payload.Length + 1)
        if ($rel -eq "coop\version.txt") { $versionFile = $item; $files.Add($rel); continue }
        $dst = Join-Path $g $rel
        Ui-Progress (3 + 17 * $i / $all.Count) $rel
        # A file of someone else's that we replace: keep the original once (an older co-op
        # DLL is not one).
        if ((Test-Path -LiteralPath $dst) -and ($old.files -notcontains $rel) -and ($backups -notcontains $rel) -and -not $rel.StartsWith("coop\") -and
            -not (Is-CoopDll $dst)) {
            $bk = Join-Path $g "coop-backup\$rel"
            # A backup from an earlier, interrupted install is the real original: kept
            # (fork MAK-PIVO/jericho-coop).
            if (-not (Test-Path -LiteralPath $bk)) {
                New-Item -ItemType Directory -Force (Split-Path $bk -Parent) | Out-Null
                Copy-Item -LiteralPath $dst $bk -Force
            }
            $backups.Add($rel)
            Ui-Log ((L "original_kept") + $rel)
        }
        New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
        Copy-Item -LiteralPath $item.FullName $dst -Force
        $files.Add($rel)
    }
    Ui-Log (L "copied_file_s" $($all.Count))
    # A release's texts in the game folder's root (0.1.0, or an archive extracted there): kept,
    # and recorded so that the removal takes them too.
    foreach ($o in $script:OLD_ROOT) {
        if ($files -notcontains $o[0] -and (Has-Text (Join-Path $g $o[0]) @($o[1]))) { $files.Add($o[0]) }
    }
    # Files of an older version that this one no longer has.
    # (by the package's list: never a file it has)
    foreach ($rel in $old.files) {
        if ($packageFiles -notcontains $rel -and $files -notcontains $rel -and $rel -ne "Pack1.packed") {
            Remove-Item -LiteralPath (Join-Path $g $rel) -Force -ErrorAction SilentlyContinue
        }
    }
    # The uninstaller stays in the game folder.
    # (not onto itself when the archive was extracted into the game folder)
    foreach ($f in "coop-installer.ps1") {
        $src, $dst = (Join-Path $here $f), (Join-Path $g $f)
        if ([IO.Path]::GetFullPath($src) -ne [IO.Path]::GetFullPath($dst)) { Copy-Item -LiteralPath $src $dst -Force }
        if ($files -notcontains $f) { $files.Add($f) }
    }
    $un = "Uninstall Co-op.bat"
    Set-Content -LiteralPath (Join-Path $g $un) -Encoding ASCII -Value '@start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0coop-installer.ps1" -Uninstall -Game "%~dp0."'
    if ($files -notcontains $un) { $files.Add($un) }
    & $writeRecord
    Ui-Step "copy" "done"

    # The game's exe made large-address-aware (4 GB of address space instead of 2: SMOD, the
    # recordings and the co-op bodies all add memory). Only the retail exe this mod is tested
    # with (SMOD runs it as bin\anselintegrationtestapp.exe); the original is kept and put back
    # on uninstall. The game started and played with it (0.2.1 tests).
    Ui-Step "exe" "run"
    Ui-Progress 21 "bin\Jericho.exe"
    $exeState = "skip"
    foreach ($exe in "bin\Jericho.exe", "bin\anselintegrationtestapp.exe") {
        $p = Join-Path $g $exe
        if (-not (Test-Path -LiteralPath $p) -or (Get-Item -LiteralPath $p).Length -ne 31141888) { continue }
        $bytes = [IO.File]::ReadAllBytes($p)
        $pe = [BitConverter]::ToInt32($bytes, 0x3c)
        $ch = [BitConverter]::ToUInt16($bytes, $pe + 22)
        if ($ch -band 0x20) { $exeState = "done"; Ui-Log ((L "already_large_address_aware") + $exe); continue }
        $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace "-", ""
        if ($sha -ne "7FB5B759823283A83B685ADC4848289A149F520DDBAB6DBC7F9E6131B15D2A62") { continue }
        $bk = Join-Path $g "coop-backup\$exe"
        if (-not (Test-Path -LiteralPath $bk)) {
            New-Item -ItemType Directory -Force (Split-Path $bk -Parent) | Out-Null
            Copy-Item -LiteralPath $p $bk -Force
        }
        if ($backups -notcontains $exe) { $backups.Add($exe) }
        $ch = $ch -bor 0x20
        $bytes[$pe + 22] = [byte]($ch -band 0xff)
        $bytes[$pe + 23] = [byte]($ch -shr 8)
        [IO.File]::WriteAllBytes($p, $bytes)
        $exeState = "done"
        Ui-Log ((L "large_address_aware") + $exe)
    }
    if ($exeState -eq "skip") { Ui-Log (L "the_exe_is_not") }
    & $writeRecord
    Ui-Step "exe" $exeState

    Ui-Step "anims" "run"
    Ui-Progress 25 (L "reading_the_game_s")
    $script:builtFiles = New-Object System.Collections.Generic.List[string]
    try { $anims = Build-Anims $g } catch { Ui-Log ("anims: " + $_.Exception.Message); $anims = "failed" }
    switch ($anims) {
        "kept"     { Ui-Log (L "the_animations_built_by"); Ui-Step "anims" "done" }
        "ok"       { Ui-Step "anims" "done" }
        "foreign"  { Ui-Log (L "pack_packed_belongs_to"); Ui-Step "anims" "skip" }
        default    { Ui-Step "anims" "warn" }
    }
    if ($anims -eq "kept") { $anims = "ok" }
    # (ours, built now or before: removed on uninstall, also after a build that failed)
    $pk1 = Join-Path $g "Pack1.packed"
    if ($files -notcontains "Pack1.packed" -and (Test-Path -LiteralPath $pk1) -and
        ($anims -eq "ok" -or (Select-String -LiteralPath $pk1 -Pattern "coopbody_" -SimpleMatch -Quiet))) { $files.Add("Pack1.packed") }

    Ui-Step "finish" "run"
    Ui-Progress 97 "coop\install.txt"
    # Loose built files (SMOD's layout): this build's, or the earlier ones when the pack was kept.
    $built = @($script:builtFiles)
    if ($built.Count -gt 0) {
        foreach ($rel in $old.built) { if ($built -notcontains $rel) { Remove-Item -LiteralPath (Join-Path $g $rel) -Force -ErrorAction SilentlyContinue } }
    } else { $built = @($old.built | Where-Object { Test-Path -LiteralPath (Join-Path $g $_) }) }
    # Ross's stand-in model with its rifle textured (cm3_retarget.py COOP_MODELS): the mod uses
    # it when this mark says the game can load it (removed with the coop folder on uninstall).
    $mark = Join-Path $g "coop\anims\trueross_coop.ok"
    $pk = Join-Path $g "Pack1.packed"
    $isLoose = -not (Test-Path -LiteralPath (Join-Path $g "Data00.packed")) -and
        ((Test-Path -LiteralPath (Join-Path $g "Packed\Data00.packed")) -or (Test-Path -LiteralPath (Join-Path $g "coop-gamedata.txt")))
    $haveModel = if ($isLoose) { Test-Path -LiteralPath (Join-Path $g "models\chars\trueross\trueross_coop.sm3") }
                 else { (Test-Path -LiteralPath $pk) -and (Select-String -LiteralPath $pk -Pattern "trueross_coop.sm3" -SimpleMatch -Quiet) }
    if ($anims -eq "ok" -and $haveModel) {
        Set-Content -LiteralPath $mark -Value "1" -Encoding ASCII
    } else { Remove-Item -LiteralPath $mark -ErrorAction SilentlyContinue }
    $links = @()
    try { $links = @(Make-Shortcuts $g $old) } catch { Ui-Log "shortcut: $($_.Exception.Message)"; $links = @($old.shortcuts | Where-Object { Test-Path -LiteralPath $_ }) }
    & $writeRecord
    if ($versionFile) { Copy-Item -LiteralPath $versionFile.FullName (Join-Path $g "coop\version.txt") -Force }
    Remove-Item -LiteralPath $snap -Recurse -Force -ErrorAction SilentlyContinue
    Ui-Step "finish" "done"
    Ui-Progress 100 ""
    @{ old = $old.version; anims = $anims; smod = (Test-Path -LiteralPath (Join-Path $g "bin\anselintegrationtestapp.exe")); links = $links.Count }
}

function Install-Message($g, $r) {
    $msg = L "start_the_game_the"
    if ($r.links -gt 0) { $msg += "`n`n" + (L "the_shortcut") }
    if ($r.smod) { $msg += (L "smod_found_supported") }
    if ($r.anims -eq "nopython" -or $r.anims -eq "failed") {
        $msg += "`n`n"
        if ($r.anims -eq "failed") { $msg += (L "the_build_of_the") + " " }
        $msg += (L "the_cutscene_animations_and")
    }
    $msg
}

function Save-Log($g) {
    $text = $script:logLines -join "`r`n"
    try { Set-Content -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) "jericho-coop-install.log") -Value $text -Encoding UTF8 } catch { }
    if ($g -and (Test-Path -LiteralPath (Join-Path $g "coop"))) {
        try { Set-Content -LiteralPath (Join-Path $g "coop\install-log.txt") -Value $text -Encoding UTF8 } catch { }
    }
}

# ---------------------------------------------------------------------------------------------
# -Quiet: the console only (as before 0.2.2)

if ($Quiet) {
    try {
        $g = $Game
        if ($g) { if (-not (Test-Game $g)) { throw (L "not_a_jericho_folder" $g) }; $g = (Resolve-Path -LiteralPath $g).Path }
        else { $g = @(Find-Games)[0]; if (-not $g) { throw (L "the_game_was_not") } }
        if ($Uninstall) {
            $null = Do-Uninstall $g
            Write-Host (L "the_co_op_mod2")
        } else {
            $r = Do-Install $g
            Save-Log $g
            Write-Host ((L "jericho_co_op_is" $version $g) + "`n" + (Install-Message $g $r))
        }
        exit 0
    } catch {
        Write-Host ((L "error") + $_.Exception.Message)
        Save-Log $g
        exit 1
    }
}

# ---------------------------------------------------------------------------------------------
# The window

if ($script:haveWin) {
    [CoopWin]::ShowWindow([CoopWin]::GetConsoleWindow(), 0) | Out-Null
    [CoopWin]::SetProcessDPIAware() | Out-Null
}
[System.Windows.Forms.Application]::EnableVisualStyles()

$C = @{
    bg = [Drawing.Color]::FromArgb(24, 24, 28); panel = [Drawing.Color]::FromArgb(34, 34, 40)
    text = [Drawing.Color]::FromArgb(232, 232, 236); dim = [Drawing.Color]::FromArgb(140, 140, 150)
    accent = [Drawing.Color]::FromArgb(196, 40, 48); accentHi = [Drawing.Color]::FromArgb(224, 62, 70)
    ok = [Drawing.Color]::FromArgb(84, 196, 122); warn = [Drawing.Color]::FromArgb(236, 176, 64); bad = [Drawing.Color]::FromArgb(236, 84, 84)
    hdr1 = [Drawing.Color]::FromArgb(86, 14, 20); hdr2 = [Drawing.Color]::FromArgb(18, 18, 22)
    btn = [Drawing.Color]::FromArgb(58, 58, 66); btnHi = [Drawing.Color]::FromArgb(76, 76, 86)
}
function Font($size, $style = "Regular", $name = "Segoe UI") { New-Object Drawing.Font($name, $size, [Drawing.FontStyle]$style) }

function New-Label($parent, $text, $x, $y, $w, $h, $font, $color) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, $h)
    $l.Font = $font; $l.ForeColor = $color; $l.BackColor = [Drawing.Color]::Transparent
    $l.UseMnemonic = $false
    $parent.Controls.Add($l)
    $l
}

function New-Button($parent, $text, $x, $y, $w, $primary) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object Drawing.Point($x, $y); $b.Size = New-Object Drawing.Size($w, 36)
    $b.FlatStyle = "Flat"; $b.Font = Font 10 $(if ($primary) { "Bold" } else { "Regular" })
    $b.ForeColor = [Drawing.Color]::White; $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.BackColor = $(if ($primary) { $C.accent } else { $C.btn })
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $(if ($primary) { $C.accentHi } else { $C.btnHi })
    $b.UseMnemonic = $false
    $parent.Controls.Add($b)
    $b
}

$form = New-Object Windows.Forms.Form
$form.SuspendLayout()
$form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
$form.AutoScaleMode = "Dpi"
$form.Text = "Jericho Co-op+ $version"
$form.ClientSize = New-Object Drawing.Size(660, 520)
$form.FormBorderStyle = "FixedSingle"; $form.MaximizeBox = $false
$form.StartPosition = "CenterScreen"
$form.BackColor = $C.bg; $form.ForeColor = $C.text
$form.Font = Font 10

# Header: a dark red to black band, the title, a red line under it.
$hdr = New-Object Windows.Forms.Panel
$hdr.Location = New-Object Drawing.Point(0, 0); $hdr.Size = New-Object Drawing.Size(660, 96)
$hdr.Add_Paint({
    param($s, $e)
    $r = $s.ClientRectangle
    if ($r.Width -le 0) { return }
    $br = New-Object Drawing.Drawing2D.LinearGradientBrush($r, $C.hdr1, $C.hdr2, [single]0)
    $e.Graphics.FillRectangle($br, $r); $br.Dispose()
    $pen = New-Object Drawing.Pen($C.accent, [single]3)
    $e.Graphics.DrawLine($pen, 0, $r.Height - 2, $r.Width, $r.Height - 2); $pen.Dispose()
})
$form.Controls.Add($hdr)
$null = New-Label $hdr "JERICHO CO-OP" 26 16 470 40 (Font 22 "Bold") ([Drawing.Color]::White)
$lbSub = New-Label $hdr "" 28 58 600 24 (Font 10) ([Drawing.Color]::FromArgb(210, 190, 190))
# The language of the window.
$cbLang = New-Object Windows.Forms.ComboBox
$cbLang.DropDownStyle = "DropDownList"; $cbLang.FlatStyle = "Flat"
$cbLang.Location = New-Object Drawing.Point(512, 20); $cbLang.Size = New-Object Drawing.Size(122, 28)
$cbLang.BackColor = $C.hdr1; $cbLang.ForeColor = [Drawing.Color]::White; $cbLang.Font = Font 10
foreach ($k in $script:langs.Keys) { [void]$cbLang.Items.Add($script:langs[$k]) }
$cbLang.SelectedIndex = @($script:langs.Keys).IndexOf($script:lang)
$hdr.Controls.Add($cbLang)

# --- page 1: the folder and what will be done
$pSetup = New-Object Windows.Forms.Panel
$pSetup.Location = New-Object Drawing.Point(0, 96); $pSetup.Size = New-Object Drawing.Size(660, 424)
$form.Controls.Add($pSetup)
$lbFolder = New-Label $pSetup "" 28 22 400 22 (Font 10 "Bold") $C.text
$tbGame = New-Object Windows.Forms.TextBox
$tbGame.Location = New-Object Drawing.Point(28, 48); $tbGame.Size = New-Object Drawing.Size(474, 28)
$tbGame.BackColor = $C.panel; $tbGame.ForeColor = $C.text; $tbGame.BorderStyle = "FixedSingle"; $tbGame.Font = Font 10.5
$pSetup.Controls.Add($tbGame)
$btBrowse = New-Button $pSetup (L "browse") 512 45 120 $false
$lbInfo = New-Label $pSetup "" 28 96 604 220 (Font 10.5) $C.text
$btRemove = New-Button $pSetup (L "remove_co_op") 28 360 150 $false
$btCancel = New-Button $pSetup (L "cancel") 372 360 120 $false
$btGo = New-Button $pSetup (L "install") 502 360 130 $true

# --- page 2: the steps and the progress
$pWork = New-Object Windows.Forms.Panel
$pWork.Location = New-Object Drawing.Point(0, 96); $pWork.Size = New-Object Drawing.Size(660, 424); $pWork.Visible = $false
$form.Controls.Add($pWork)
$lbWorkTitle = New-Label $pWork "" 28 18 470 30 (Font 14 "Bold") $C.text
$lbTime = New-Label $pWork "0:00" 500 24 132 22 (Font 10) $C.dim
$lbTime.TextAlign = "MiddleRight"
$steps = @{}
function Add-Steps($list) {
    foreach ($k in @($steps.Keys)) { $pWork.Controls.Remove($steps[$k].icon); $pWork.Controls.Remove($steps[$k].text) }
    $steps.Clear()
    $y = 62
    foreach ($s in $list) {
        $ic = New-Label $pWork ([string][char]0x25CB) 30 $y 24 26 (Font 11 "Bold" "Segoe UI Symbol") $C.dim
        $tx = New-Label $pWork $s[1] 58 ($y + 2) 574 24 (Font 10.5) $C.dim
        $steps[$s[0]] = @{ icon = $ic; text = $tx }
        $y += 30
    }
}
$lbPct = New-Label $pWork "0 %" 540 232 92 22 (Font 10 "Bold") $C.text
$lbPct.TextAlign = "MiddleRight"
$lbAction = New-Label $pWork "" 28 232 510 22 (Font 9.5) $C.dim
$lbAction.AutoEllipsis = $true
$bar = New-Object Windows.Forms.Panel
$bar.Location = New-Object Drawing.Point(28, 258); $bar.Size = New-Object Drawing.Size(604, 14); $bar.BackColor = $C.panel
$pWork.Controls.Add($bar)
$fill = New-Object Windows.Forms.Panel
$fill.Location = New-Object Drawing.Point(0, 0); $fill.Size = New-Object Drawing.Size(0, 14); $fill.BackColor = $C.accent
$bar.Controls.Add($fill)
$tbLog = New-Object Windows.Forms.TextBox
$tbLog.Location = New-Object Drawing.Point(28, 284); $tbLog.Size = New-Object Drawing.Size(604, 70)
$tbLog.Multiline = $true; $tbLog.ReadOnly = $true; $tbLog.ScrollBars = "Vertical"; $tbLog.BorderStyle = "None"
$tbLog.BackColor = $C.panel; $tbLog.ForeColor = $C.dim; $tbLog.Font = Font 8.5 "Regular" "Consolas"
$pWork.Controls.Add($tbLog)
$btLogCopy = New-Button $pWork (L "copy_log") 28 366 170 $false
$btLogCopy.Visible = $false
$btFolder = New-Button $pWork (L "open_game_folder") 206 366 180 $false
$btFolder.Visible = $false
$btReadme = New-Button $pWork "README" 394 366 100 $false
$btReadme.Visible = $false
$btClose = New-Button $pWork (L "close") 502 366 130 $true
$btClose.Visible = $false

# --- page 3 (over page 2's steps): the result
$lbResIcon = New-Label $pWork "" 24 60 60 60 (Font 30 "Bold" "Segoe UI Symbol") $C.ok
$lbResIcon.Visible = $false
$lbResText = New-Label $pWork "" 92 66 540 160 (Font 10.5) $C.text
$lbResText.Visible = $false

$form.ResumeLayout($false)

$script:ui = $null
$script:busy = $false
$script:exitCode = 1
$script:target = ""
$script:t0 = Get-Date

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    if (-not $script:busy) { return }
    $s = [int]((Get-Date) - $script:t0).TotalSeconds
    $lbTime.Text = "{0}:{1:00}" -f [int][Math]::Floor($s / 60), ($s % 60)
    # the running step's dot pulses: something is being done
    $r = $script:ui.running
    if ($r) { $r.icon.ForeColor = $(if ($r.icon.ForeColor.ToArgb() -eq $C.accent.ToArgb()) { $C.accentHi } else { $C.accent }) ; $r.icon.Text = $(if ($r.icon.Text -eq [string][char]0x25CF) { [string][char]0x25C9 } else { [string][char]0x25CF }) }
})

$form.Add_FormClosing({
    param($sender, $ev)
    if ($script:busy) {
        $ev.Cancel = $true
        [Windows.Forms.MessageBox]::Show($form, (L "please_wait_until_it"), "Jericho Co-op+", "OK", "Information") | Out-Null
    }
})

# The texts of the window in the chosen language.
function Set-Texts {
    $lbSub.Text = L "version_co_op_for" $version
    $lbFolder.Text = L "game_folder"
    $btBrowse.Text = L "browse"; $btRemove.Text = L "remove_co_op"; $btCancel.Text = L "cancel"
    $btLogCopy.Text = L "copy_log"; $btFolder.Text = L "open_game_folder"; $btClose.Text = L "close"
    if ($script:removeVer) { $lbInfo.Text = L "remove_jericho_co_op" $script:removeVer } else { Update-Setup }
}
$cbLang.Add_SelectedIndexChanged({
    $script:lang = @($script:langs.Keys)[$cbLang.SelectedIndex]
    Set-Texts
})

# What page 1 says about the chosen folder.
function Update-Setup {
    $g = $tbGame.Text.Trim().Trim('"')
    $ok = Test-Game $g
    $lines = @()
    $btRemove.Visible = $false
    if (-not $g) {
        $lines += (L "the_game_was_not2")
    } elseif (-not $ok) {
        $lines += ([string][char]0x2716 + "  " + (L "there_is_no_bin"))
    } else {
        $lines += ([string][char]0x2714 + "  " + (L "clive_barker_s_jericho"))
        if (Test-Path -LiteralPath (Join-Path $g "bin\anselintegrationtestapp.exe")) { $lines += ([string][char]0x2714 + "  " + (L "smod_found_supported2")) }
        $m = Read-Manifest $g
        if ($m.files.Count -gt 0) {
            $btRemove.Visible = $true
            if ($m.version -eq $version) {
                $lines += ([string][char]0x2022 + "  " + (L "co_op_is_already" $version))
                $btGo.Text = L "reinstall"
            } else {
                $lines += ([string][char]0x2022 + "  " + (L "co_op_is_installed" $($m.version) $version))
                $btGo.Text = L "update"
            }
        } else { $btGo.Text = L "install" }
        $lines += ""
        $lines += (L "the_installer_copies_the")
        $lines += ""
        $lines += (L "every_player_needs_the")
    }
    $lbInfo.Text = $lines -join "`n"
    $lbInfo.ForeColor = $(if ($ok) { $C.text } else { $C.warn })
    $btGo.Enabled = $ok
    $btGo.BackColor = $(if ($ok) { $C.accent } else { $C.btn })
}

function Show-Work($title, $stepList) {
    $pSetup.Visible = $false
    $pWork.Visible = $true
    $lbWorkTitle.Text = $title
    Add-Steps $stepList
    $script:ui = @{ form = $form; bar = $bar; fill = $fill; pct = $lbPct; action = $lbAction; log = $tbLog; steps = $steps; colors = $C; running = $null }
    $script:t0 = Get-Date
    $script:busy = $true
    $cbLang.Enabled = $false
    $timer.Start()
    Ui-Progress 0 ""
}

function Show-Result($ok, $title, $text) {
    $script:busy = $false
    $timer.Stop()
    foreach ($k in @($steps.Keys)) { $steps[$k].icon.Visible = $false; $steps[$k].text.Visible = $false }
    $lbWorkTitle.Text = $title
    $lbWorkTitle.ForeColor = $(if ($ok) { $C.ok } else { $C.bad })
    $lbResIcon.Text = $(if ($ok) { [string][char]0x2714 } else { [string][char]0x2716 })
    $lbResIcon.ForeColor = $(if ($ok) { $C.ok } else { $C.bad })
    $lbResText.Text = $text
    $lbResIcon.Visible = $true; $lbResText.Visible = $true
    $lbAction.Text = ""
    if ($ok) { $fill.BackColor = $C.ok } else { $fill.BackColor = $C.bad; $fill.Width = $bar.ClientSize.Width; $lbPct.Text = "" }
    if ($script:haveWin) { [CoopWin]::Progress($form.Handle, $(if ($ok) { 0 } else { 4 }), 100) }
    $btClose.Visible = $true
    $btLogCopy.Visible = -not $ok
    $btFolder.Visible = $ok -and $script:target -and (Test-Path -LiteralPath $script:target)
    $btReadme.Visible = $ok -and (Test-Path -LiteralPath (Join-Path $here "README-COOP.txt"))
    $btClose.Focus()
    $form.Activate()
}

# A folder Windows protects (Program Files): the same work by an elevated copy of this installer,
# this window closes with its result.
function Elevated-Instead($g, [switch] $Remove) {
    if (-not (Need-Admin $g)) { return $false }
    Ui-Log (L "no_admin")
    $form.Hide()
    $code = Run-Elevated $g -Remove:$Remove
    if ($code -lt 0) {
        $form.Show()
        Show-Result $false $(if ($Remove) { L "removal_failed" } else { L "installation_failed" }) (L "no_admin")
        return $true
    }
    $script:exitCode = $code
    $form.Close()
    $true
}

function Start-Install($g) {
    $g = (Resolve-Path -LiteralPath $g).Path
    if (Elevated-Instead $g) { return }
    $script:target = $g
    $ic = Window-Icon $g
    if ($ic) { $form.Icon = $ic }
    Show-Work (L "installing_co_op" $version) @(
        @("check", (L "checking_the_game_folder")),
        @("copy", (L "copying_the_mod_the")),
        @("exe", (L "large_address_aware_flag")),
        @("anims", (L "building_cutscene_animations_and")),
        @("finish", (L "writing_the_install_record")))
    Ui-Log ((L "game_folder2") + $g)
    try {
        $r = Do-Install $g
        Save-Log $g
        $title = $(if ($r.old -and $r.old -ne $version) { L "updated_from_to" $($r.old) $version } else { L "co_op_is_installed2" $version })
        $script:exitCode = 0
        $ic = Window-Icon $g
        if ($ic) { $form.Icon = $ic }
        Show-Result $true $title (Install-Message $g $r)
        # (the launcher's update: the game starts once this window is gone)
        if ($AutoClose) {
            $script:closer = New-Object Windows.Forms.Timer
            $script:closer.Interval = 2000
            $script:closer.Add_Tick({ $script:closer.Stop(); $form.Close() })
            $script:closer.Start()
        }
    } catch {
        Ui-Log ("ERROR: " + $_.Exception.Message)
        if ($script:ui.running) { $script:ui.running.icon.Text = [string][char]0x2716; $script:ui.running.icon.ForeColor = $C.bad }
        Save-Log $g
        Show-Result $false (L "installation_failed") ($_.Exception.Message + "`n`n" + (L "the_log_is_in"))
    }
}

function Start-Uninstall($g) {
    $g = (Resolve-Path -LiteralPath $g).Path
    if (Elevated-Instead $g -Remove) { return }
    $script:target = $g
    if (-not $IgnoreRunning -and (Game-Running $g)) {
        [Windows.Forms.MessageBox]::Show($form, (L "close_the_game_first"), "Jericho Co-op+", "OK", "Warning") | Out-Null
        return
    }
    $ic = Window-Icon $g
    if ($ic) { $form.Icon = $ic }
    Show-Work (L "removing_co_op") @(
        @("rm", (L "removing_the_mod_s")),
        @("restore", (L "putting_back_the_game")),
        @("clean", (L "removing_the_backups_and")))
    try {
        $null = Do-Uninstall $g
        $script:exitCode = 0
        $btFolder.Text = L "open_game_folder"
        Show-Result $true (L "co_op_removed") (L "the_co_op_mod3")
        $btReadme.Visible = $false
    } catch {
        Ui-Log ("ERROR: " + $_.Exception.Message)
        Save-Log ""
        Show-Result $false (L "removal_failed") $_.Exception.Message
    }
}

$tbGame.Add_TextChanged({ Update-Setup })
$btBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = L "select_the_clive_barker"
    $cur = $tbGame.Text.Trim()
    if ($cur -and (Test-Path -LiteralPath $cur)) { $dlg.SelectedPath = $cur }
    if ($dlg.ShowDialog($form) -eq "OK") { $tbGame.Text = $dlg.SelectedPath }
})
$btCancel.Add_Click({ $form.Close() })
$btClose.Add_Click({ $form.Close() })
$btGo.Add_Click({
    $g = $tbGame.Text.Trim().Trim('"')
    if (-not (Test-Game $g)) { return }
    if (-not $IgnoreRunning -and (Game-Running $g)) {
        [Windows.Forms.MessageBox]::Show($form, (L "close_the_game_first"), "Jericho Co-op+", "OK", "Warning") | Out-Null
        return
    }
    Start-Install $g
})
$btRemove.Add_Click({
    $g = $tbGame.Text.Trim().Trim('"')
    # (the uninstaller's page is the question already)
    if (-not $Uninstall) {
        $q = [Windows.Forms.MessageBox]::Show($form, (L "remove_the_co_op" $g), "Jericho Co-op+", "YesNo", "Question")
        if ($q -ne "Yes") { return }
    }
    Start-Uninstall $g
})
$btFolder.Add_Click({ if ($script:target) { Start-Process explorer.exe -ArgumentList ('"' + $script:target + '"') } })
$btReadme.Add_Click({ Start-Process notepad.exe -ArgumentList ('"' + (Join-Path $here "README-COOP.txt") + '"') })
$btLogCopy.Add_Click({ [Windows.Forms.Clipboard]::SetText(($script:logLines -join "`r`n") + "`r`n") })

# Started for a folder: remove asks first, install goes straight on.
# (the title bar's colour is taken as the window is created)
$form.Add_HandleCreated({ if ($script:haveWin) { [CoopWin]::DarkTitle($form.Handle) } })
$form.Add_Shown({
    if ($script:haveWin) { [CoopWin]::SetWindowTheme($tbLog.Handle, "DarkMode_Explorer", $null) | Out-Null }
    $form.Activate()
    if ($Game) {
        if (-not (Test-Game $Game)) {
            $tbGame.Text = $Game
            return
        }
        $tbGame.Text = (Resolve-Path -LiteralPath $Game).Path
        if ($Uninstall) {
            $m = Read-Manifest $tbGame.Text
            $script:removeVer = "$($m.version)"
            $lbInfo.Text = (L "remove_jericho_co_op" $($m.version))
            $btGo.Visible = $false
            $btRemove.Visible = $true
            $btRemove.BackColor = $C.accent
            $btRemove.Location = New-Object Drawing.Point(($btGo.Left - ($btRemove.Width - $btGo.Width)), $btGo.Top)
            $btCancel.Left = $btRemove.Left - $btCancel.Width - 10
            $tbGame.ReadOnly = $true; $btBrowse.Enabled = $false
            $btRemove.Focus()
        } else {
            Start-Install $tbGame.Text
        }
    } else {
        $found = @(Find-Games)
        if ($found.Count -ge 1) { $tbGame.Text = $found[0] } else { Update-Setup }
        $btGo.Focus()
    }
})

Set-Texts
[Windows.Forms.Application]::Run($form)
exit $script:exitCode

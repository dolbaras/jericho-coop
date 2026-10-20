# Jericho Co-op installer / uninstaller for players (shipped in the release zip as
# "Install Co-op.bat" + coop-installer.ps1, payload in the "files" folder next to it).
#   install: finds the game folder (this folder, install records in the registry, Steam
#            libraries, or asks), keeps the files it replaces in <game>\coop-backup, copies the
#            mod and writes <game>\coop\install.txt (what it installed, what it backed up).
#   update:  the same over an older version; originals already backed up are kept.
#   remove:  deletes what install.txt lists and puts the backed-up files back. The co-op saves
#            (Documents\Codemasters\Clive Barker's Jericho\Coop) are not touched.
# Usage: coop-installer.ps1 [-Game <folder>] [-Uninstall] [-Quiet]
param([string] $Game = "", [switch] $Uninstall, [switch] $Quiet, [switch] $IgnoreRunning)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$payload = Join-Path $here "files"
$ru = (Get-Culture).TwoLetterISOLanguageName -eq "ru"
function L($en, $r) { if ($ru) { $r } else { $en } }
Add-Type -AssemblyName System.Windows.Forms

function Show-Msg($text, $icon = "Information") {
    if ($Quiet) { Write-Host $text; return }
    [System.Windows.Forms.MessageBox]::Show($text, "Jericho Co-op", "OK", $icon) | Out-Null
}

function Test-Game($dir) {
    [bool]$dir -and ((Test-Path (Join-Path $dir "bin\Jericho.exe")) -or (Test-Path (Join-Path $dir "bin\anselintegrationtestapp.exe")))
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
    $c | Where-Object { Test-Game $_ } | ForEach-Object { (Resolve-Path $_).Path } | Select-Object -Unique
}

function Pick-Game {
    if ($Game) { if (Test-Game $Game) { return (Resolve-Path $Game).Path }; throw (L "Not a Jericho folder: $Game" "Это не папка Jericho: $Game") }
    $found = @(Find-Games)
    if ($found.Count -ge 1 -and $Quiet) { return $found[0] }
    if ($found.Count -eq 1) {
        $q = [System.Windows.Forms.MessageBox]::Show((L "Game found:`n$($found[0])`n`nUse this folder?" "Игра найдена:`n$($found[0])`n`nИспользовать эту папку?"),
            "Jericho Co-op", "YesNoCancel", "Question")
        if ($q -eq "Yes") { return $found[0] }
        if ($q -eq "Cancel") { exit 1 }
    }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = L "Select the Clive Barker's Jericho folder (the one with the bin folder)" "Выберите папку Clive Barker's Jericho (в ней есть папка bin)"
    if ($found.Count -ge 1) { $dlg.SelectedPath = $found[0] }
    while ($true) {
        if ($dlg.ShowDialog() -ne "OK") { exit 1 }
        if (Test-Game $dlg.SelectedPath) { return $dlg.SelectedPath }
        Show-Msg (L "bin\Jericho.exe is not in this folder." "В этой папке нет bin\Jericho.exe.") "Warning"
    }
}

function Read-Manifest($g) {
    $m = @{ files = @(); backups = @() ; version = "" }
    $f = Join-Path $g "coop\install.txt"
    if (Test-Path $f) {
        foreach ($line in Get-Content $f) {
            if ($line -match '^version=(.*)$') { $m.version = $Matches[1] }
            elseif ($line -match '^file=(.*)$') { $m.files += $Matches[1] }
            elseif ($line -match '^backup=(.*)$') { $m.backups += $Matches[1] }
        }
    }
    $m
}

function Do-Uninstall($g) {
    $m = Read-Manifest $g
    if ($m.files.Count -eq 0) { Show-Msg (L "The co-op mod is not installed in`n$g" "Кооп-мод не установлен в`n$g") "Warning"; return }
    foreach ($rel in $m.files) { Remove-Item (Join-Path $g $rel) -Force -ErrorAction SilentlyContinue }
    foreach ($rel in $m.backups) {
        $b = Join-Path $g "coop-backup\$rel"
        if (Test-Path $b) { Copy-Item $b (Join-Path $g $rel) -Force }
    }
    Remove-Item (Join-Path $g "coop") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $g "coop-backup") -Recurse -Force -ErrorAction SilentlyContinue
    Show-Msg (L "The co-op mod was removed; replaced files were put back.`nCo-op saves stay in Documents\Codemasters\Clive Barker's Jericho\Coop." "Кооп-мод удалён, заменённые файлы возвращены.`nКооп-сохранения остались в Документы\Codemasters\Clive Barker's Jericho\Coop.")
}

# The experimental "own eyes" cutscene view shows the scene's character with its first-person
# motion moved onto the full model. That motion is made here from the player's own game files
# (coop\anims\cm3_retarget.py, Python 3, a few minutes) into <game>\Pack1.packed, which the
# game mounts by itself. Without Python the view still works, without that body.
function Find-Python {
    foreach ($c in @(@("py", "-3"), @("python"), @("python3"))) {
        $cmd = Get-Command $c[0] -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $a = @($c | Select-Object -Skip 1)
        $v = & $cmd.Source @a -c "import sys; print(sys.version_info[0])" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq "3") { return @{ exe = $cmd.Source; args = $a } }
    }
    $null
}

function Build-Anims($g) {
    $pack = Join-Path $g "Pack1.packed"
    # Somebody else's Pack1 (not ours): left alone.
    if ((Test-Path $pack) -and -not (Select-String -Path $pack -Pattern "coopbody_" -SimpleMatch -Quiet)) { return "foreign" }
    if (Test-Path $pack) { return "ok" }
    $py = Find-Python
    if (-not $py) { return "nopython" }
    # The game's archives: the game folder, or Packed\ after SMOD unpacked them.
    $data = $g
    if (-not (Test-Path (Join-Path $g "Data00.packed")) -and (Test-Path (Join-Path $g "Packed\Data00.packed"))) { $data = Join-Path $g "Packed" }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "jericho-coop-anims"
    Write-Host (L "Building the cutscene animations (a few minutes)..." "Сборка анимаций для катсцен (несколько минут)...")
    & $py.exe @($py.args) -I -B (Join-Path $g "coop\anims\cm3_retarget.py") --game $data --out $tmp batch --pack "$pack.tmp" | Out-Host
    $ok = $LASTEXITCODE -eq 0 -and (Test-Path "$pack.tmp")
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $ok) { Remove-Item "$pack.tmp" -ErrorAction SilentlyContinue; return "failed" }
    Move-Item "$pack.tmp" $pack -Force
    "ok"
}

function Do-Install($g) {
    if (-not (Test-Path $payload)) { throw (L "The 'files' folder is missing next to the installer." "Рядом с установщиком нет папки 'files'.") }
    if (-not $IgnoreRunning -and (Get-Process -Name Jericho, anselintegrationtestapp -ErrorAction SilentlyContinue)) {
        Show-Msg (L "Close the game first." "Сначала закройте игру.") "Warning"; exit 1
    }
    $old = Read-Manifest $g
    $version = (Get-Content (Join-Path $payload "coop\version.txt") -ErrorAction SilentlyContinue | Select-Object -First 1)
    $backups = New-Object System.Collections.Generic.List[string]
    foreach ($b in $old.backups) { $backups.Add($b) }
    $files = New-Object System.Collections.Generic.List[string]
    Get-ChildItem $payload -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($payload.Length + 1)
        $dst = Join-Path $g $rel
        # A file of someone else's that we replace: keep the original once.
        if ((Test-Path $dst) -and ($old.files -notcontains $rel) -and ($backups -notcontains $rel) -and -not $rel.StartsWith("coop\")) {
            $bk = Join-Path $g "coop-backup\$rel"
            New-Item -ItemType Directory -Force (Split-Path $bk -Parent) | Out-Null
            Copy-Item $dst $bk -Force
            $backups.Add($rel)
        }
        New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
        Copy-Item $_.FullName $dst -Force
        $files.Add($rel)
    }
    # Files of an older version that this one no longer has.
    foreach ($rel in $old.files) { if ($files -notcontains $rel -and $rel -ne "Pack1.packed") { Remove-Item (Join-Path $g $rel) -Force -ErrorAction SilentlyContinue } }
    # The uninstaller stays in the game folder.
    foreach ($f in "coop-installer.ps1") { Copy-Item (Join-Path $here $f) (Join-Path $g $f) -Force; if ($files -notcontains $f) { $files.Add($f) } }
    $un = "Uninstall Co-op.bat"
    Set-Content -Path (Join-Path $g $un) -Encoding ASCII -Value '@powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0coop-installer.ps1" -Uninstall -Game "%~dp0."'
    if ($files -notcontains $un) { $files.Add($un) }
    $anims = Build-Anims $g
    if ($anims -eq "ok" -and $files -notcontains "Pack1.packed") { $files.Add("Pack1.packed") }
    $lines = @("version=$version") + ($files | ForEach-Object { "file=$_" }) + ($backups | ForEach-Object { "backup=$_" })
    Set-Content -Path (Join-Path $g "coop\install.txt") -Value $lines -Encoding UTF8
    $smod = Test-Path (Join-Path $g "bin\anselintegrationtestapp.exe")
    $msg = (L "Jericho Co-op $version is installed in`n$g`n`nStart the game: the main menu has a 'Co-op' entry.`nSplit screen: 'Co-op split screen.bat' in the game folder.`nTo remove: 'Uninstall Co-op.bat' in the game folder." `
              "Jericho Co-op $version установлен в`n$g`n`nЗапустите игру: в главном меню появится «Совместная игра».`nСплитскрин: «Co-op split screen.bat» в папке игры.`nУдалить: «Uninstall Co-op.bat» в папке игры.")
    if ($smod) { $msg += (L "`n`nSMOD found: supported." "`n`nНайден SMOD: поддерживается.") }
    if ($anims -eq "nopython" -or $anims -eq "failed") {
        $msg += (L "`n`nThe experimental cutscene view 'own eyes' needs Python 3 to build its animations$(if ($anims -eq 'failed') {' (the build failed)'}): without it the scene's character is not shown in that view. To add it, install Python 3 (python.org) and run the installer again." `
                   "`n`nЭкспериментальному режиму катсцен «своими глазами» нужен Python 3 для сборки анимаций$(if ($anims -eq 'failed') {' (сборка не удалась)'}): без него персонаж сцены в этом режиме не виден. Чтобы добавить, установите Python 3 (python.org) и запустите установщик ещё раз.")
    }
    if ($old.version) { $msg = (L "Updated from $($old.version).`n" "Обновлено с $($old.version).`n") + $msg }
    Show-Msg $msg
}

try {
    $g = Pick-Game
    if ($Uninstall) { Do-Uninstall $g; exit 0 }
    $m = Read-Manifest $g
    if ($m.files.Count -gt 0 -and -not $Quiet) {
        $q = [System.Windows.Forms.MessageBox]::Show((L "Co-op $($m.version) is installed.`nYes - install this version over it`nNo - remove the co-op mod" "Установлен кооп $($m.version).`nДа - установить эту версию поверх`nНет - удалить кооп-мод"),
            "Jericho Co-op", "YesNoCancel", "Question")
        if ($q -eq "No") { Do-Uninstall $g; exit 0 }
        if ($q -eq "Cancel") { exit 1 }
    }
    Do-Install $g
} catch {
    Show-Msg ((L "Error: " "Ошибка: ") + $_.Exception.Message) "Error"
    exit 1
}

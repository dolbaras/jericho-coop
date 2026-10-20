# The co-op story lines alone (lua/coop_storysolo.lua): a menu of the lines, each started in a
# solo session of its own (this game folder, the co-op mod in coop\, SMOD if installed).
# Usage: put this script in the game folder and run "Story Lines.bat" there.
param([string] $Line = "")
$ErrorActionPreference = "Stop"
$game = $PSScriptRoot
$ru = (Get-Culture).TwoLetterISOLanguageName -eq "ru"
function L($en, $r) { if ($ru) { $r } else { $en } }

$lines = @(
    @{ id = "G1A"; level = "Alk_Tomb";         char = "Jones";    en = "Act 1  Alk_Tomb       Alpha's recon (Jones)";                   ru = "Акт 1  Гробница       Разведка Альфы (Джонс)" },
    @{ id = "G1C"; level = "Alk_City";         char = "Jones";    en = "Act 1  Alk_City       Alpha cut off in the dig (Jones)";        ru = "Акт 1  Город          Альфа отрезана на раскопе (Джонс)" },
    @{ id = "G3";  level = "Alk_Bunker_01";    char = "Cole";     en = "Act 1  Alk_Bunker_01  Temporal restoration (Cole)";             ru = "Акт 1  Бункер         Восстановление архива (Коул)" },
    @{ id = "G4";  level = "WWII_PillBoxes";   char = "Rawlings"; en = "Act 2  WWII_PillBoxes Stations of the Path (Rawlings)";         ru = "Акт 2  Доты           Станции Пути (Роулингс)" },
    @{ id = "G6";  level = "WWII_Brandenburg"; char = "Cole";     en = "Act 2  Brandenburg    The gate top (Cole)";                     ru = "Акт 2  Бранденбург    Верх ворот (Коул)" },
    @{ id = "G7";  level = "Cru_River";        char = "Jones";    en = "Act 3  Cru_River      The Lost Patrol (Jones)";                 ru = "Акт 3  Река           Потерянный патруль (Джонс)" },
    @{ id = "G8";  level = "Cru_Sewers";       char = "Black";    en = "Act 3  Cru_Sewers     Hold the gate (Black)";                   ru = "Акт 3  Стоки          Удержать ворота (Блэк)" },
    @{ id = "G10"; level = "Rom_Caldarium";    char = "Black";    en = "Act 4  Rom_Caldarium  The Torturers' Hall (Black)";             ru = "Акт 4  Кальдарий      Зал палачей (Блэк)" },
    @{ id = "G11"; level = "Rom_Palace_01";    char = "Black";    en = "Act 4  Rom_Palace_01  Alone on the far side (Black)";           ru = "Акт 4  Дворец         Один на той стороне (Блэк)" },
    @{ id = "G15"; level = "Sum_End";          char = "Black";    en = "Act 5  Sum_End        Break the blood link (Black)";            ru = "Акт 5  Финал          Разорвать кровавую связь (Блэк)" }
)

if (-not $Line) {
    Write-Host (L "Co-op story lines, alone (the main line goes on by itself):" "Сюжетные линии кооператива в одиночку (основная линия идёт сама):")
    Write-Host ""
    for ($i = 0; $i -lt $lines.Count; $i++) { Write-Host ("  {0,2}  {1}" -f ($i + 1), (L $lines[$i].en $lines[$i].ru)) }
    Write-Host ""
    $pick = Read-Host (L "Number (Enter - quit)" "Номер (Enter - выход)")
    if (-not $pick) { return }
    $n = [int]$pick - 1
    if ($n -lt 0 -or $n -ge $lines.Count) { Write-Host (L "No such line." "Нет такой линии."); return }
    $x = $lines[$n]
} else {
    $x = $lines | Where-Object { $_.id -eq $Line } | Select-Object -First 1
    if (-not $x) { throw "no line $Line" }
}

$exe = Join-Path $game "bin\anselintegrationtestapp.exe"   # SMOD's name for the game
if (-not (Test-Path $exe)) { $exe = Join-Path $game "bin\Jericho.exe" }
$saves = Join-Path $game "storyline-saves"
New-Item -ItemType Directory -Force $saves | Out-Null
$env:JERICHO_COOP_DIR = (Join-Path $game "coop").Replace('\', '/') + "/"
$env:JERICHO_COOP_CFG = "{auto=true,role='host',port=28100,level='$($x.level)',char='$($x.char)',storyline='$($x.id)',tags=false,}"
$env:JERICHO_COOP_SAVEDIR = $saves
$env:JERICHO_COOP_LOG = Join-Path $saves "coop.log"
Write-Host (L "Starting: " "Запуск: ") (L $x.en $x.ru)
Start-Process -FilePath $exe -WorkingDirectory $game -ArgumentList "-InitLuaLine:`"assert(loadstring(Net['CoopBoot']()))()`""

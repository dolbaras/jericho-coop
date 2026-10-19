# Two game instances that stay in the main menu (menu/lobby tests): same safety rules as
# run_pair.ps1 (secondary monitor, client on the other GPU, background mode, frame cap).
# Usage: run_menu_pair.ps1 -HostCfg "dev=true,menutest='lobby'," -ClientCfg "dev=true,menutest='join',menuwait=500," [-Seconds 60] [-Record]
param(
    [string] $HostCfg = "dev=true,menutest='lobby',",
    [string] $ClientCfg = "dev=true,menutest='join',menuwait=500,",
    [int] $Seconds = 60,
    [switch] $Record,
    [string] $HostAdapter = "window"   # both on the iGPU (the owner keeps the main GPU)
)

. (Join-Path $PSScriptRoot "paths.ps1")
$Game = Join-Path $WorkRoot "game"
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
if (-not $screen) { throw "no secondary monitor" }
$wa = $screen.WorkingArea
$winW = [int][math]::Min(960, [math]::Floor(($wa.Width - 40) / 2))
$winH = [int][math]::Floor($winW * 9 / 16)
$run = Join-Path (Join-Path $WorkRoot "runs") (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force $run | Out-Null
$exe = Join-Path $Game "bin\Jericho.exe"
$common = "-SelectedLanguage:English -FullScreen:0 -VideoWidth:$winW -VideoHeight:$winH -WindowedWidth:$winW -WindowedHeight:$winH -debug:3 -R_LimitFPS:30 " +
          "-SoundMainVolume:0 -MusicMainVolume:0 -VoiceMainVolume:0"

function Start-One([string] $name, [string] $cfg, [string] $winpos, [string] $adapter, [bool] $multi) {
    $boot = $BootLine
    $env:JERICHO_COOP_DIR = $LuaDirForward
    $env:JERICHO_COOP_CFG = "{$cfg}"
    $env:JERICHO_COOP_LOG = Join-Path $run "$name.coop.txt"
    $env:JERICHO_WINPOS = $winpos
    $env:JERICHO_BACKGROUND = "1"
    $env:JERICHO_COOP_SAVEDIR = Join-Path $SaveRoot $name
    if ($adapter) { $env:JERICHO_ADAPTER = $adapter }
    if ($multi) { $env:JERICHO_MULTI = "1" }
    if ($Record) { $env:JERICHO_RECORD = Join-Path $run "$name.raw"; $env:JERICHO_RECORD_FULL = "1" }
    $extra = if ($adapter) { " -Antialiasing:0" } else { "" }   # see run_pair.ps1
    $p = Start-Process -FilePath $exe -ArgumentList "$common$extra -OutDebugFile:`"$(Join-Path $run "$name.log")`" -InitLuaLine:`"$boot`"" -WorkingDirectory $Game -PassThru
    foreach ($v in "JERICHO_COOP_LOG", "JERICHO_WINPOS", "JERICHO_ADAPTER", "JERICHO_MULTI", "JERICHO_BACKGROUND", "JERICHO_RECORD", "JERICHO_RECORD_FULL", "JERICHO_COOP_SAVEDIR", "JERICHO_COOP_DIR", "JERICHO_COOP_CFG") {
        Remove-Item "Env:$v" -ErrorAction SilentlyContinue
    }
    try { $p.PriorityClass = 'BelowNormal' } catch {}
    return $p
}

$h = $null; $c = $null
try {
    $h = Start-One "host" $HostCfg "$($wa.X + 10),$($wa.Y + 10)" $HostAdapter $false
    Start-Sleep -Seconds 15
    $c = Start-One "client" $ClientCfg "$($wa.X + 20 + $winW + 10),$($wa.Y + 10)" "window" $true
    "run=$run"
    Start-Sleep -Seconds $Seconds
} finally {
    $ids = @($h, $c) | Where-Object { $_ } | ForEach-Object { $_.Id }
    if ($ids) {
        Stop-Process -Id $ids -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $ids -Timeout 30 -ErrorAction SilentlyContinue
    }
}
if ($Record) { & (Join-Path $PSScriptRoot "record.ps1") -Dir $run }

# One game instance with a given COOP_CFG, screenshots at given seconds, then stop.
# Window opens on the secondary monitor, background mode, below-normal priority, 30 fps cap.
param(
    [string] $Game = "",                # default: <work>\game
    [string] $OutDir = "",              # default: <work>\runs
    [string] $Cfg = "",                # COOP_CFG fields, e.g. "dev=true,menutest='root',"
    [int[]] $Shots = @(25),            # seconds after start
    [int] $Seconds = 30,
    [string] $Adapter = "window",       # "window" = the secondary monitor's GPU (the iGPU); "" = default GPU
    [switch] $Record,                  # in-game video capture (native/capture.c), no screenshots
    [int] $RecordStart = 0,
    [double] $RecordFps = 0,           # 0: capture.c default (8)
    [switch] $DefaultLog               # no JERICHO_COOP_LOG: the mod logs to <save dir>\coop.log as for players
)

. (Join-Path $PSScriptRoot "paths.ps1")
if (-not $Game) { $Game = Join-Path $WorkRoot "game" }
if (-not $OutDir) { $OutDir = Join-Path $WorkRoot "runs" }
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
if (-not $screen) { $screen = [System.Windows.Forms.Screen]::PrimaryScreen }
$run = Join-Path $OutDir (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force $run | Out-Null
$luaDir = $LuaDirForward
$boot = $BootLine
$env:JERICHO_COOP_DIR = $luaDir
$env:JERICHO_COOP_CFG = "{$Cfg}"
$winW, $winH, $winPos = Get-FullWindow $screen
$aa = if ($Adapter) { "-Antialiasing:0 " } else { "" }   # iGPU: without the owner's 8x MSAA
$args = "-SelectedLanguage:English -FullScreen:0 -VideoWidth:$winW -VideoHeight:$winH -WindowedWidth:$winW -WindowedHeight:$winH $aa-debug:3 -R_LimitFPS:30 " +
        "-SoundMainVolume:0 -MusicMainVolume:0 -VoiceMainVolume:0 " +
        "-OutDebugFile:`"$(Join-Path $run 'game.log')`" -InitLuaLine:`"$boot`""
if (-not $DefaultLog) { $env:JERICHO_COOP_LOG = Join-Path $run "coop.txt" }
$env:JERICHO_STACKDUMP = Join-Path $run "stack.txt"
$env:JERICHO_WINPOS = $winPos
$env:JERICHO_WINSIZE = "$winW,$winH"
$env:JERICHO_BACKGROUND = "1"
$env:JERICHO_COOP_SAVEDIR = Join-Path $SaveRoot "single"
if ($Adapter) { $env:JERICHO_ADAPTER = $Adapter }
if ($Record) { $env:JERICHO_RECORD = Join-Path $run "game.raw"; $env:JERICHO_RECORD_START = "$RecordStart"; $Shots = @() }
if ($Record -and $RecordFps -gt 0) { $env:JERICHO_RECORD_FPS = "$RecordFps" }
$p = Start-Process -FilePath (Join-Path $Game "bin\Jericho.exe") -ArgumentList $args -WorkingDirectory $Game -PassThru
foreach ($v in "JERICHO_COOP_LOG", "JERICHO_STACKDUMP", "JERICHO_WINPOS", "JERICHO_BACKGROUND", "JERICHO_ADAPTER", "JERICHO_RECORD", "JERICHO_RECORD_START", "JERICHO_RECORD_FPS", "JERICHO_COOP_SAVEDIR", "JERICHO_COOP_DIR", "JERICHO_COOP_CFG", "JERICHO_WINSIZE") {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
try {
try { $p.PriorityClass = 'BelowNormal' } catch {}
"run=$run pid=$($p.Id)"
$t0 = Get-Date
foreach ($s in ($Shots | Sort-Object)) {
    $wait = $s - ((Get-Date) - $t0).TotalSeconds
    if ($wait -gt 0) { Start-Sleep -Seconds $wait }
    if ($p.HasExited) { break }
    & "$PSScriptRoot\shot.ps1" -OutDir $run -Tag "t$s"
}
$wait = $Seconds - ((Get-Date) - $t0).TotalSeconds
if ($wait -gt 0 -and -not $p.HasExited) { Start-Sleep -Seconds $wait }
} finally {
    # Always stop the game, even when the caller cuts the pipeline short.
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $p.Id -Timeout 30 -ErrorAction SilentlyContinue
}
if ($Record) { & (Join-Path $PSScriptRoot "record.ps1") -Dir $run }
"--- coop.txt"
if (Test-Path (Join-Path $run "coop.txt")) { Get-Content (Join-Path $run "coop.txt") | Select-Object -Last 15 }

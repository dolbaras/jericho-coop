# Safe co-op test: ONE game instance (host) plus the headless Python bot as the client.
# Two D3D9 instances on the owner's PC once froze the desktop, so this is the default test.
# The game runs at below-normal priority with a frame cap; the proxy DLL creates its window
# directly on the secondary monitor (JERICHO_WINPOS), and focus is never touched.
param(
    [string] $Game = "",                # default: <work>\game
    [string] $OutDir = "",              # default: <work>\runs
    [string] $Level = "Rom_Tepidarium",
    [int] $Port = 28100,
    [string] $Want = "Black",
    [string] $Pattern = "circle",
    [string] $Path = "",              # path file for -Pattern replay
    [int] $BotSeconds = 60,
    [int] $LoadTimeout = 120,
    [string] $ExtraArgs = "",
    [string] $HostCfg = "",            # extra COOP_CFG fields, e.g. "dev=true,"
    [string] $Adapter = "window",      # JERICHO_ADAPTER for the host ("window" = the secondary monitor's iGPU)
    [switch] $Record,                  # in-game video capture (native/capture.c)
    [switch] $RecordFull,
    [int] $RecordStart = 0
)

. (Join-Path $PSScriptRoot "paths.ps1")
if (-not $Game) { $Game = Join-Path $WorkRoot "game" }
if (-not $OutDir) { $OutDir = Join-Path $WorkRoot "runs" }

# Open the game window directly on the secondary monitor (the owner works on the primary).
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
if (-not $screen) { $screen = [System.Windows.Forms.Screen]::PrimaryScreen }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$run = Join-Path $OutDir $stamp
New-Item -ItemType Directory -Force $run | Out-Null
$exe = Join-Path $Game "bin\Jericho.exe"
$log = Join-Path $run "host.log"
$coopLog = Join-Path $run "host.coop.txt"
$luaDir = $LuaDirForward
$boot = "COOP_DIR='$luaDir' COOP_CFG={${HostCfg}auto=true,role='host',level='$Level',port=$Port} dofile(COOP_DIR..'boot.lua')"
# Large 16:9 window on the secondary monitor; on the iGPU without the owner's 8x MSAA.
$winW = [int][math]::Min(1280, $screen.WorkingArea.Width - 60)
$winH = [int][math]::Floor($winW * 9 / 16)
$aa = if ($Adapter) { "-Antialiasing:0 " } else { "" }
$args = "-SelectedLanguage:English -FullScreen:0 -VideoWidth:$winW -VideoHeight:$winH -WindowedWidth:$winW -WindowedHeight:$winH $aa-debug:3 -R_LimitFPS:30 " +
        "-SoundMainVolume:0 -MusicMainVolume:0 -VoiceMainVolume:0 $ExtraArgs " +
        "-OutDebugFile:`"$log`" -InitLuaLine:`"$boot`""

$env:JERICHO_COOP_LOG = $coopLog
$env:JERICHO_STACKDUMP = Join-Path $run "host.stack.txt"
$env:JERICHO_WINPOS = "$($screen.WorkingArea.X + 20),$($screen.WorkingArea.Y + 20)"
$env:JERICHO_BACKGROUND = "1"   # keep running unfocused, without reading the user's input
$env:JERICHO_COOP_SAVEDIR = Join-Path $SaveRoot "host"
if ($Adapter) { $env:JERICHO_ADAPTER = $Adapter }
if ($Record) { $env:JERICHO_RECORD = Join-Path $run "host.raw"; $env:JERICHO_RECORD_START = "$RecordStart" }
if ($Record -and $RecordFull) { $env:JERICHO_RECORD_FULL = "1" }
$p = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $Game -PassThru
Remove-Item Env:JERICHO_COOP_LOG, Env:JERICHO_STACKDUMP, Env:JERICHO_WINPOS, Env:JERICHO_BACKGROUND
foreach ($v in "JERICHO_COOP_SAVEDIR", "JERICHO_ADAPTER", "JERICHO_RECORD", "JERICHO_RECORD_START", "JERICHO_RECORD_FULL") { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
try {
try { $p.PriorityClass = 'BelowNormal' } catch {}
"run=$run host pid=$($p.Id)"

# Wait until the mod reports the test level loaded.
$deadline = (Get-Date).AddSeconds($LoadTimeout)
$loaded = $false
while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
    Start-Sleep -Seconds 2
    if ((Test-Path $coopLog) -and (Select-String -Path $coopLog -Pattern "coop.lua loaded level=levels/$($Level.ToLower())" -Quiet)) { $loaded = $true; break }
}
"level loaded=$loaded"

if ($loaded) {
    Start-Sleep -Seconds 3
    & python -I (Join-Path $PSScriptRoot "bot\coop_bot.py") --port $Port --want $Want --pattern $Pattern $(if ($Path) { "--path"; $Path }) --seconds $BotSeconds --log (Join-Path $run "bot.txt") | Out-Null
    Start-Sleep -Seconds 3
}

} finally {
    # Always stop the game, even when the caller cuts the pipeline short.
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $p.Id -Timeout 30 -ErrorAction SilentlyContinue
}
if ($Record) { & (Join-Path $PSScriptRoot "record.ps1") -Dir $run }
"host alive after stop=$(-not $p.HasExited)"
"--- bot.txt"
if (Test-Path (Join-Path $run "bot.txt")) { Get-Content (Join-Path $run "bot.txt") | Select-Object -Last 12 }
"--- host.coop.txt"
if (Test-Path $coopLog) { Get-Content $coopLog | Select-Object -Last 14 }

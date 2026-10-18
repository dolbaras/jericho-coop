# Two real game instances (host + client) on this PC, with the owner's OK only.
# Safety (a two-instance run once froze the desktop): the client renders on another GPU
# (JERICHO_ADAPTER=window on the iGPU monitor), both windows are created directly on the
# secondary monitor by the proxy DLL (JERICHO_WINPOS), focus is never touched, both run at
# below-normal priority with a frame cap, and the client starts only after the host's level
# has loaded.
param(
    [string] $Game = "",                # default: <work>\game
    [string] $OutDir = "",              # default: <work>\runs
    [string] $Level = "Rom_Tepidarium",
    [int] $Port = 28100,
    [string] $HostCfg = "",           # extra COOP_CFG fields for the host, e.g. "dev=true,"
    [string] $ClientCfg = "",         # extra COOP_CFG fields for the client
    [int] $Duration = 60,             # seconds after the client has loaded the level
    [int] $LoadTimeout = 150,
    [switch] $KeepRunning,
    [switch] $Record,                 # in-game video capture of both instances (native/capture.c)
    [switch] $RecordFull,             # ... at full resolution (default half)
    [int] $RecordStartHost = 0,       # seconds after the host's device is created
    [int] $RecordStartClient = 0,
    [string] $HostAdapter = "window"  # both on the iGPU (the owner keeps the main GPU); "" = default GPU
)

. (Join-Path $PSScriptRoot "paths.ps1")
if (-not $Game) { $Game = Join-Path $WorkRoot "game" }
if (-not $OutDir) { $OutDir = Join-Path $WorkRoot "runs" }

Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
if (-not $screen) { throw "no secondary monitor" }
$wa = $screen.WorkingArea

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$run = Join-Path $OutDir $stamp
New-Item -ItemType Directory -Force $run | Out-Null
$exe = Join-Path $Game "bin\Jericho.exe"
$luaDir = $LuaDirForward
# Two windows side by side on the secondary monitor, 16:9, as large as fit (owner's wish).
$winW = [int][math]::Min(960, [math]::Floor(($wa.Width - 40) / 2))
$winH = [int][math]::Floor($winW * 9 / 16)
$common = "-SelectedLanguage:English -FullScreen:0 -VideoWidth:$winW -VideoHeight:$winH -WindowedWidth:$winW -WindowedHeight:$winH -debug:3 -R_LimitFPS:30 " +
          "-SoundMainVolume:0 -MusicMainVolume:0 -VoiceMainVolume:0"

function Start-Jericho([string] $name, [string] $cfg, [string] $winpos, [string] $adapter, [bool] $multi, [int] $recStart) {
    $log = Join-Path $run "$name.log"
    $boot = "COOP_DIR='$luaDir' COOP_CFG={$cfg} dofile(COOP_DIR..'boot.lua')"
    $env:JERICHO_COOP_LOG = Join-Path $run "$name.coop.txt"
    $env:JERICHO_STACKDUMP = Join-Path $run "$name.stack.txt"
    $env:JERICHO_WINPOS = $winpos
    $env:JERICHO_BACKGROUND = "1"   # keep running unfocused, without reading the user's input
    $env:JERICHO_COOP_SAVEDIR = Join-Path $SaveRoot $name
    if ($adapter) { $env:JERICHO_ADAPTER = $adapter }
    if ($multi) { $env:JERICHO_MULTI = "1" }
    if ($Record) { $env:JERICHO_RECORD = Join-Path $run "$name.raw"; $env:JERICHO_RECORD_START = "$recStart" }
    if ($Record -and $RecordFull) { $env:JERICHO_RECORD_FULL = "1" }
    # The instance on the integrated GPU drops the owner's 8x MSAA (game.cfg Antialiasing = 8),
    # which alone took it to a few frames per second; command-line values are not saved.
    $extra = if ($adapter) { " -Antialiasing:0" } else { "" }
    $p = Start-Process -FilePath $exe -ArgumentList "$common$extra -OutDebugFile:`"$log`" -InitLuaLine:`"$boot`"" -WorkingDirectory $Game -PassThru
    foreach ($v in "JERICHO_COOP_LOG", "JERICHO_STACKDUMP", "JERICHO_WINPOS", "JERICHO_ADAPTER", "JERICHO_MULTI", "JERICHO_BACKGROUND", "JERICHO_RECORD", "JERICHO_RECORD_START", "JERICHO_RECORD_FULL", "JERICHO_COOP_SAVEDIR") {
        Remove-Item "Env:$v" -ErrorAction SilentlyContinue
    }
    try { $p.PriorityClass = 'BelowNormal' } catch {}
    return $p
}

function Wait-Loaded([System.Diagnostics.Process] $p, [string] $coop) {
    $deadline = (Get-Date).AddSeconds($LoadTimeout)
    while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
        Start-Sleep -Seconds 2
        if ((Test-Path $coop) -and (Select-String -Path $coop -Pattern "coop.lua loaded level=levels/$($Level.ToLower())" -Quiet)) { return $true }
    }
    return $false
}

$h = $null; $c = $null
try {
$h = Start-Jericho "host" "${HostCfg}auto=true,role='host',level='$Level',port=$Port" "$($wa.X + 10),$($wa.Y + 10)" $HostAdapter $false $RecordStartHost
"run=$run host pid=$($h.Id)"
$hostOk = Wait-Loaded $h (Join-Path $run "host.coop.txt")
"host loaded=$hostOk"
if ($hostOk) {
    Start-Sleep -Seconds 3
    $c = Start-Jericho "client" "${ClientCfg}auto=true,role='client',port=$Port" "$($wa.X + 20 + $winW + 10),$($wa.Y + 10)" "window" $true $RecordStartClient
    "client pid=$($c.Id)"
    $clientOk = Wait-Loaded $c (Join-Path $run "client.coop.txt")
    "client loaded=$clientOk"
    if ($clientOk) { Start-Sleep -Seconds $Duration }
}

$h.Refresh(); if ($c) { $c.Refresh() }
"host alive=$(-not $h.HasExited)" + $(if ($c) { " client alive=$(-not $c.HasExited)" } else { "" })
} finally {
    # Always stop both games, even when the caller cuts the pipeline short.
    if (-not $KeepRunning) {
        $ids = @($h, $c) | Where-Object { $_ } | ForEach-Object { $_.Id }
        if ($ids) {
            Stop-Process -Id $ids -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $ids -Timeout 30 -ErrorAction SilentlyContinue
        }
    }
}
if ($Record -and -not $KeepRunning) { & (Join-Path $PSScriptRoot "record.ps1") -Dir $run }
foreach ($n in "host", "client") {
    $f = Join-Path $run "$n.coop.txt"
    if (Test-Path $f) {
        "--- $n.coop.txt"
        Get-Content $f | Where-Object { $_ -notmatch "lua: path\|" } | Select-Object -Last 12
    }
}

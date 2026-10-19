# Split screen (experimental): two copies of the game side by side on the main screen, one
# co-op session between them over this PC. Shipped in the release as coop-splitscreen.ps1 in
# the game folder, started by "Co-op split screen.bat".
#   Window 1 (left): keyboard + mouse and gamepad 1. It hosts: Co-op -> Host game, as usual.
#   Window 2 (right): gamepad 2 only. It joins window 1's lobby by itself and is ready; its
#   player picks the character there. Sound comes from window 1 only.
# Usage: coop-splitscreen.ps1 [-Pads2 1] [-TopBottom]
param(
    [int] $Pads2 = 1,          # the physical gamepad (0-3) of window 2
    [switch] $TopBottom        # windows one above the other instead of side by side
)
$game = $PSScriptRoot
$exe = Join-Path $game "bin\anselintegrationtestapp.exe"     # SMOD keeps the game under this name
if (-not (Test-Path $exe)) { $exe = Join-Path $game "bin\Jericho.exe" }
if (-not (Test-Path $exe)) { Write-Error "Jericho.exe not found next to this script (put it in the game folder)"; exit 1 }
Add-Type -AssemblyName System.Windows.Forms
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
# Each window keeps the game's 16:9 shape (the HUD and FOV are made for it): side by side,
# centred with black above and below, or one above the other, centred left to right.
if ($TopBottom) {
    $h = [int]($wa.Height / 2); $w = [int]($h * 16 / 9)
    if ($w -gt $wa.Width) { $w = $wa.Width; $h = [int]($w * 9 / 16) }
    $x = $wa.X + [int](($wa.Width - $w) / 2)
    $pos1 = "$x,$($wa.Y)"; $pos2 = "$x,$($wa.Y + [int]($wa.Height / 2))"
} else {
    $w = [int]($wa.Width / 2); $h = [int]($w * 9 / 16)
    $y = $wa.Y + [int](($wa.Height - $h) / 2)
    $pos1 = "$($wa.X),$y"; $pos2 = "$($wa.X + $w),$y"
}
$common = "-FullScreen:0 -VideoWidth:$w -VideoHeight:$h -WindowedWidth:$w -WindowedHeight:$h"

function Start-Game($pos, $extraArgs, $envs) {
    $saved = @{}
    foreach ($k in $envs.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $envs[$k]) }
    $p = Start-Process -FilePath $exe -ArgumentList "$common $extraArgs" -WorkingDirectory $game -PassThru
    foreach ($k in $envs.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    $p
}

# Window 1: the player at the keyboard (and pad 1).
$p1 = Start-Game $pos1 "" @{ JERICHO_WINPOS = $pos1; JERICHO_WINSIZE = "$w,$h"; JERICHO_PADS = "0" }
# Window 2 once window 1 has its device (two games creating theirs at once is asking for trouble).
Start-Sleep -Seconds 20
$docs = [Environment]::GetFolderPath("MyDocuments")
$p2 = Start-Game $pos2 "-SoundMainVolume:0 -MusicMainVolume:0 -VoiceMainVolume:0 -PlayVideos:0" @{
    JERICHO_MULTI = "1"; JERICHO_WINPOS = $pos2; JERICHO_WINSIZE = "$w,$h"; JERICHO_PADS = "$Pads2"
    JERICHO_KBM = "0"; JERICHO_BACKGROUND = "1"
    JERICHO_COOP_LOG = (Join-Path $docs "Codemasters\Clive Barker's Jericho\Coop\coop-window2.log")
    JERICHO_COOP_CFG = "{autojoin=true,addr='127.0.0.1',nick='Player 2',}"
}
# Closing one window closes the other.
while (-not $p1.HasExited -and -not $p2.HasExited) { Start-Sleep -Seconds 2 }
foreach ($p in $p1, $p2) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }

# Workspace layout, derived from this repo's location (dot-source from the other scripts):
#   <root>\games\jericho\mod    this repository
#   <root>\games\jericho\work   private: test copy of the game, extracted/decompiled data, runs
#   <root>\tools                shared tools (zig, ffmpeg, ghidra, jdk, lua, unluac, enet)
$ModRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$GameRoot = Split-Path $ModRoot -Parent
$WorkRoot = Join-Path $GameRoot "work"
$WorkspaceRoot = Split-Path (Split-Path $GameRoot -Parent) -Parent
$ToolsRoot = Join-Path $WorkspaceRoot "tools"
$LuaDirForward = (Join-Path $ModRoot "lua").Replace('\', '/') + "/"
# Co-op saves of test runs (never the player's Documents folder): <work>\saves\<instance>
$SaveRoot = Join-Path $WorkRoot "saves"
New-Item -ItemType Directory -Force $SaveRoot | Out-Null
# The command line carries only this path-free boot line; the DLL's Net.CoopBoot() builds the
# real one from JERICHO_COOP_DIR and JERICHO_COOP_CFG (the engine's command-line parser fails
# on long text after a '.').
$BootLine = "assert(loadstring(Net['CoopBoot']()))()"
# A game window that fills a screen's working area (owner's wish: windowed, maximized),
# its client size leaving room for the title bar and borders. Returns w, h, "x,y".
function Get-FullWindow($screen) {
    Add-Type -AssemblyName System.Windows.Forms
    $wa = $screen.WorkingArea
    $bw = [System.Windows.Forms.SystemInformation]::FrameBorderSize.Width * 2
    $cap = [System.Windows.Forms.SystemInformation]::CaptionHeight
    return @(($wa.Width - $bw), ($wa.Height - $cap - $bw), "$($wa.X),$($wa.Y)")
}
$FfmpegBin = Join-Path $ToolsRoot "ffmpeg\ffmpeg-master-latest-win64-gpl\bin"

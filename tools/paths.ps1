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
$FfmpegBin = Join-Path $ToolsRoot "ffmpeg\ffmpeg-master-latest-win64-gpl\bin"

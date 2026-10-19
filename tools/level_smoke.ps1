# Smoke test of every campaign level in a co-op session: one game instance on the iGPU as
# host plus the headless bot as client (run_bot.ps1), each level for -Seconds. Reports per
# level: loaded, Lua errors in the mod log, engine errors ("Error at") in the game log, and
# a crash (stack dump). Results: <work>\runs\level-smoke\<stamp>\summary.csv
# Usage: level_smoke.ps1 [-Levels Alk_Desert,Cru_River] [-Seconds 60]
param(
    [string[]] $Levels = @(),
    [int] $Seconds = 60,
    [string] $Extra = ""        # extra COOP_CFG fields, e.g. "qtemode=2,"
)

. (Join-Path $PSScriptRoot "paths.ps1")
$all = @("Alk_Desert", "Alk_Tomb", "Alk_Bunker_00", "Alk_City", "Alk_Bunker_01", "Alk_Final",
         "WWII_BigGates", "WWII_PillBoxes", "WWII_Mosque", "WWII_Mosque_Inside", "WWII_Vigil",
         "WWII_Vigil_Inside", "WWII_Brandenburg",
         "Cru_River", "Cru_Labyrinth", "Cru_Sewers", "Cru_Keep", "Cru_Catacomb", "Cru_Chapel",
         "Rom_Outskirts", "Rom_Caldarium", "Rom_Tepidarium", "Rom_Palace_01", "Rom_Palace_02",
         "Rom_Coloseum", "Rom_Chamber",
         "Sum_Ziggurat_01", "Sum_Ziggurat_02", "Sum_Ziggurat_03", "Sum_Ziggurat_04",
         "Sum_Ziggurat_Meat", "Sum_Ziggurat_05", "Sum_End")
if (-not $Levels.Count) { $Levels = $all }
$out = Join-Path $WorkRoot ("runs\level-smoke\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force $out | Out-Null
$rows = @()
foreach ($level in $Levels) {
    $dir = Join-Path $out $level
    $null = & (Join-Path $PSScriptRoot "run_bot.ps1") -OutDir $dir -Level $level -Pattern still -BotSeconds $Seconds `
        -HostCfg "dev=true,qtemode=2,$Extra" 2>&1
    $run = Get-ChildItem $dir -Directory | Sort-Object Name | Select-Object -Last 1
    $coop = Join-Path $run.FullName "host.coop.txt"
    $glog = Join-Path $run.FullName "host.log"
    $loaded = (Test-Path $coop) -and (Select-String -Path $coop -Pattern "coop.lua loaded level=levels/$($level.ToLower())" -Quiet)
    $luaErr = if (Test-Path $coop) { @(Select-String -Path $coop -Pattern "error" | Where-Object { $_.Line -notmatch "err_avg|errors=" }) } else { @() }
    $engErr = if (Test-Path $glog) { @(Select-String -Path $glog -Pattern "^Error at") } else { @() }
    $crash = Test-Path (Join-Path $run.FullName "host.stack.txt")
    $row = [pscustomobject]@{
        level = $level; loaded = $loaded; lua_errors = $luaErr.Count; engine_errors = $engErr.Count; crash = $crash
        first_lua_error = if ($luaErr.Count) { $luaErr[0].Line.Substring(0, [math]::Min(160, $luaErr[0].Line.Length)) } else { "" }
        first_engine_error = if ($engErr.Count) { $engErr[0].Line.Substring(0, [math]::Min(160, $engErr[0].Line.Length)) } else { "" }
        run = $run.FullName
    }
    $rows += $row
    "{0,-20} loaded={1} lua={2} engine={3} crash={4} {5}" -f $level, $loaded, $luaErr.Count, $engErr.Count, $crash, $row.first_lua_error
}
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out "summary.csv")
"summary: $(Join-Path $out 'summary.csv')"

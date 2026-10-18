# Record every in-engine cutscene for review: a vanilla reference (one instance, no co-op
# session) and a co-op run (host + client, both recorded), per row of tests/scene_audit.csv.
# Output: <work>\runs\scene-audit\<id>_<level>\{ref,pair}\<stamp>\*.mp4 plus contact sheets.
# Usage: scene_audit.ps1 [-Ids 09,34] [-Mode both|ref|pair]
param(
    [string[]] $Ids = @(),
    [ValidateSet("both", "ref", "pair")] [string] $Mode = "both"
)

. (Join-Path $PSScriptRoot "paths.ps1")
$list = Join-Path $ModRoot "tests\scene_audit.csv"
$out = Join-Path $WorkRoot "runs\scene-audit"
New-Item -ItemType Directory -Force $out | Out-Null

foreach ($line in Get-Content $list) {
    if ($line -match '^\s*#' -or -not $line.Trim()) { continue }
    $id, $level, $trigger, $targs, $char, $secs = $line.Split(';')
    if ($Ids.Count -and $Ids -notcontains $id) { continue }
    $dir = Join-Path $out "${id}_$level"
    # QTEMode 2: the engine passes QTEs, so the scenes run their vanilla (success) path.
    $exp = "dev=true,qtemode=2,"
    if ($trigger) {
        $exp += "exp='trigger',trigger='$trigger',trigat=40,"
        if ($targs) { $exp += "trigargs={$targs}," }
    }
    "=== $id $level $trigger $targs (client $char, ${secs}s)"
    if ($Mode -ne "pair") {
        & (Join-Path $PSScriptRoot "run_single.ps1") -OutDir (Join-Path $dir "ref") `
            -Cfg "${exp}auto=true,role='solo',level='$level'," -Seconds (45 + [int]$secs) -Record -RecordStart 3 |
            Select-String "mp4|trigger|scene" | ForEach-Object { "  ref: $($_.Line)" }
    }
    if ($Mode -ne "ref") {
        & (Join-Path $PSScriptRoot "run_pair.ps1") -OutDir (Join-Path $dir "pair") -Level $level -Duration ([int]$secs + 10) `
            -Record -RecordStartHost 30 -RecordStartClient 10 `
            -HostCfg "${exp}waitpeers=1," -ClientCfg "dev=true,qtemode=2,char='$char'," |
            Select-String "mp4|trigger|scene|loaded=" | ForEach-Object { "  pair: $($_.Line)" }
    }
    & (Join-Path $PSScriptRoot "scene_compare.ps1") -Dir $dir -Seconds ([int]$secs + 5) | ForEach-Object { "  $_" }
}

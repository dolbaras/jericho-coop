# Line up the recordings of one audited scene side by side: vanilla reference | co-op host |
# co-op client, each starting -Lead seconds before its "scene start" log line (dev.lua).
# Writes compare.mp4 and compare_sheetNN.png (one row per -Step seconds) into the folder.
# Usage: scene_compare.ps1 -Dir <work>\runs\scene-audit\14_WWII_BigGates [-Seconds 70]
param([Parameter(Mandatory)] [string] $Dir, [string] $Scene = "", [int] $Seconds = 60, [double] $Lead = 3, [double] $Step = 2)

. (Join-Path $PSScriptRoot "paths.ps1")
$ffmpeg = Join-Path $FfmpegBin "ffmpeg.exe"

function Latest([string] $sub) {
    $p = Join-Path $Dir $sub
    if (Test-Path $p) { Get-ChildItem $p -Directory | Sort-Object Name | Select-Object -Last 1 }
}

# Seconds into the video where the scene starts (the capture writes in real time from its
# first frame, logged as "capture: WxH").
function SceneOffset([string] $log) {
    $lines = Get-Content $log
    $cap = $lines | Where-Object { $_ -match "capture: \d+x\d+" } | Select-Object -First 1
    $pattern = if ($Scene) { "lua: scene start $Scene$" } else { "lua: scene start " }
    $st = $lines | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if (-not $cap -or -not $st) { return $null }
    $t0 = [datetime]::ParseExact($cap.Substring(0, 12), "HH:mm:ss.fff", $null)
    $t1 = [datetime]::ParseExact($st.Substring(0, 12), "HH:mm:ss.fff", $null)
    return ($t1 - $t0).TotalSeconds
}

$ref = Latest "ref"; $pair = Latest "pair"
$inputs = @()
if ($ref) { $inputs += @{ label = "ORIGINAL"; video = "$($ref.FullName)\game.mp4"; log = "$($ref.FullName)\coop.txt" } }
if ($pair) {
    $inputs += @{ label = "HOST"; video = "$($pair.FullName)\host.mp4"; log = "$($pair.FullName)\host.coop.txt" }
    $inputs += @{ label = "CLIENT"; video = "$($pair.FullName)\client.mp4"; log = "$($pair.FullName)\client.coop.txt" }
}
$ffargs = @("-hide_banner", "-loglevel", "error", "-y")
$filters = @()
$n = 0
foreach ($in in $inputs) {
    if (-not (Test-Path $in.video)) { continue }
    $off = SceneOffset $in.log
    if ($null -eq $off) { "no scene start in $($in.log)"; continue }
    $ss = [math]::Max(0, $off - $Lead)
    "{0}: scene at {1:N1} s" -f $in.label, $off
    $ffargs += @("-ss", ("{0:N2}" -f $ss).Replace(',', '.'), "-t", "$Seconds", "-i", $in.video)
    $filters += "[${n}:v]scale=320:240,setpts=PTS-STARTPTS,fps=8,drawtext=text='$($in.label)':x=4:y=4:fontsize=14:fontcolor=yellow:box=1:boxcolor=black@0.6[v$n]"
    $n++
}
if ($n -eq 0) { "nothing to compare"; return }
$stack = ($(0..($n - 1) | ForEach-Object { "[v$_]" }) -join "") + $(if ($n -gt 1) { "hstack=inputs=$n" } else { "null" }) + ",drawtext=text='%{pts\:hms}':x=w-110:y=4:fontsize=14:fontcolor=white:box=1:boxcolor=black@0.6[out]"
$filter = ($filters + $stack) -join ";"
$mp4 = Join-Path $Dir "compare.mp4"
& $ffmpeg @ffargs -filter_complex $filter -map "[out]" -c:v libx264 -preset veryfast -crf 24 -pix_fmt yuv420p $mp4 2>&1 | Where-Object { $_ -notmatch "Fontconfig" }
Get-ChildItem $Dir -Filter "compare_sheet*.png" | Remove-Item
& $ffmpeg -hide_banner -loglevel error -y -i $mp4 -vf "fps=1/$Step,tile=2x8" (Join-Path $Dir "compare_sheet%02d.png") 2>&1 | Where-Object { $_ -notmatch "Fontconfig" }
Get-ChildItem $Dir -Filter "compare*" | ForEach-Object FullName

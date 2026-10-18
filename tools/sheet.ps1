# Turn a recording into contact sheets (frames in a grid, reading order = time) and a
# jitter metric (mean absolute difference between consecutive frames, per second).
# Usage: sheet.ps1 -Video <file.mp4> [-Step 0.5] [-Cols 4] [-Rows 4] [-Width 320]
param([Parameter(Mandatory)] [string] $Video, [double] $Step = 0.5, [int] $Cols = 4, [int] $Rows = 4, [int] $Width = 320)
. (Join-Path $PSScriptRoot "paths.ps1")
$bin = $FfmpegBin
$ffmpeg = Join-Path $bin "ffmpeg.exe"
$base = [IO.Path]::ChangeExtension($Video, $null).TrimEnd('.')
$fps = 1.0 / $Step
# Frame number and time are burned into each tile so the sheet reads as a timeline.
$label = "drawtext=text='%{pts\:hms}':x=4:y=4:fontsize=14:fontcolor=yellow:box=1:boxcolor=black@0.6"
& $ffmpeg -hide_banner -loglevel error -y -i $Video -vf "fps=$fps,scale=${Width}:-2,$label,tile=${Cols}x${Rows}" "${base}_sheet%02d.png"
Get-ChildItem "${base}_sheet*.png" | ForEach-Object FullName
# Jitter: per-frame scene change score (0..1) averaged per second, from ffmpeg's scdet.
$log = & $ffmpeg -hide_banner -i $Video -vf "scale=160:-2,scdet=threshold=100,metadata=print:key=lavfi.scd.score" -f null - 2>&1 | Out-String
$scores = [regex]::Matches($log, "lavfi.scd.score:\s*([0-9.]+)") | ForEach-Object { [double]$_.Groups[1].Value }
if ($scores.Count -gt 0) {
    "frames=$($scores.Count) mean_change=$([math]::Round(($scores | Measure-Object -Average).Average, 2)) max_change=$([math]::Round(($scores | Measure-Object -Maximum).Maximum, 2))"
}

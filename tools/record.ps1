# Convert in-game captures (JERICHO_RECORD, see native/capture.c) to mp4 and delete the raw
# files. Screen-area recording is not used: windows on top of the game (the owner's chats)
# would be recorded too.
# Usage: record.ps1 -Dir <run dir>        converts every *.raw with its .raw.txt in the folder
param([Parameter(Mandatory)] [string] $Dir)
. (Join-Path $PSScriptRoot "paths.ps1")
$ffmpeg = Join-Path $FfmpegBin "ffmpeg.exe"
foreach ($raw in Get-ChildItem $Dir -Filter *.raw) {
    $meta = "$($raw.FullName).txt"
    if (-not (Test-Path $meta)) { "skip $($raw.Name): no metadata"; continue }
    $w, $h, $fps = (Get-Content $meta -TotalCount 1).Trim() -split '\s+'
    $mp4 = [IO.Path]::ChangeExtension($raw.FullName, ".mp4")
    & $ffmpeg -hide_banner -loglevel error -y -f rawvideo -pixel_format bgr0 -video_size "${w}x${h}" -framerate $fps `
        -i $raw.FullName -vf "crop=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p $mp4
    # (an odd size, e.g. a full-size capture of 1912x1001, is cut by a row: yuv420p needs even ones)
    if ((Test-Path $mp4) -and (Get-Item $mp4).Length -gt 0) {
        # The game may still be exiting and holding the raw file for a few seconds.
        for ($i = 0; $i -lt 20 -and (Test-Path $raw.FullName); $i++) {
            try { Remove-Item $raw.FullName, $meta -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 }
        }
        $mp4
    }
}
